#!/usr/bin/env python3
"""Offline, byte-preserving Riftlet storage inspection and recovery.

No App launch, migration, SQL writes to the source, cleanup, or input replay.
SQLite is opened only on disposable copies, including its original sidecars.
"""

import argparse
import contextlib
import datetime
import fcntl
import hashlib
import json
import os
from pathlib import Path
import re
import sqlite3
import stat
import struct
import sys
import tempfile
import uuid


FORMAT = "riftlet-offline-storage-v1"
CURRENT_QUEUE_VERSION = 4
CHUNK = 1024 * 1024
NOFOLLOW = os.O_NOFOLLOW | os.O_CLOEXEC | os.O_NONBLOCK
HEX = re.compile(r"^[0-9a-f]{64}$")


class StorageError(Exception):
    def __init__(self, code, detail):
        self.code = code
        super().__init__(detail)


def require(condition, code, detail):
    if not condition:
        raise StorageError(code, detail)


def encoded(value):
    return (json.dumps(value, ensure_ascii=True, sort_keys=True, separators=(",", ":")) + "\n").encode()


def sha(data):
    return hashlib.sha256(data).hexdigest()


def now():
    return datetime.datetime.now(datetime.timezone.utc).isoformat()


def absolute(path):
    path = Path(path).expanduser()
    require(".." not in path.parts, "unsafe-path", "Parent traversal is not accepted")
    return Path(os.path.abspath(path))


def parts(relative):
    require(isinstance(relative, str) and relative and not relative.startswith("/"),
            "unsafe-path", "Expected a nonempty relative path")
    result = relative.split("/")
    require(all(x not in ("", ".", "..") and "\\" not in x and "\x00" not in x for x in result),
            "unsafe-path", "Unsafe relative path")
    return result


def stamp(info):
    return (info.st_dev, info.st_ino, info.st_size, info.st_mtime_ns, info.st_ctime_ns, info.st_mode)


class Tree:
    """All traversals are descriptor-relative; never follow symlinks."""

    def __init__(self, path, create=False):
        self.path = absolute(path)
        names = self.path.parts[1:]
        require(bool(names), "unsafe-path", "The filesystem root is not a data directory")
        fd = os.open("/", os.O_RDONLY | os.O_DIRECTORY | NOFOLLOW)
        try:
            for i, name in enumerate(names):
                if create and i == len(names) - 1:
                    os.mkdir(name, 0o700, dir_fd=fd)  # Atomic no-overwrite reservation.
                    os.fsync(fd)
                nxt = os.open(name, os.O_RDONLY | os.O_DIRECTORY | NOFOLLOW, dir_fd=fd)
                os.close(fd)
                fd = nxt
            self.fd = fd
        except BaseException:
            os.close(fd)
            raise

    def close(self):
        if self.fd is not None:
            os.close(self.fd)
            self.fd = None

    def __enter__(self):
        return self

    def __exit__(self, *exc):
        self.close()

    @contextlib.contextmanager
    def parent(self, relative):
        names = parts(relative)
        fd = os.dup(self.fd)
        try:
            for name in names[:-1]:
                nxt = os.open(name, os.O_RDONLY | os.O_DIRECTORY | NOFOLLOW, dir_fd=fd)
                os.close(fd)
                fd = nxt
            yield fd, names[-1]
        finally:
            os.close(fd)

    def open(self, relative, write=False):
        with self.parent(relative) as (parent, name):
            flags = os.O_WRONLY | os.O_CREAT | os.O_EXCL if write else os.O_RDONLY
            fd = os.open(name, flags | NOFOLLOW, 0o600, dir_fd=parent)
        if not stat.S_ISREG(os.fstat(fd).st_mode):
            os.close(fd)
            raise StorageError("unsafe-file", "Only regular files may be copied")
        return fd

    def exists(self, relative):
        try:
            with self.parent(relative) as (parent, name):
                os.stat(name, dir_fd=parent, follow_symlinks=False)
            return True
        except FileNotFoundError:
            return False

    def mkdir(self, relative):
        with self.parent(relative) as (parent, name):
            os.mkdir(name, 0o700, dir_fd=parent)
            os.fsync(parent)

    def write(self, relative, data):
        fd = self.open(relative, write=True)
        with os.fdopen(fd, "wb") as handle:
            handle.write(data)
            handle.flush()
            os.fsync(handle.fileno())
        with self.parent(relative) as (parent, _):
            os.fsync(parent)

    def read(self, relative, limit=32 * CHUNK):
        with os.fdopen(self.open(relative), "rb") as handle:
            before = os.fstat(handle.fileno())
            require(before.st_size <= limit, "oversized-metadata", "Metadata exceeds its bounded reader")
            data = handle.read(limit + 1)
            require(len(data) <= limit and stamp(before) == stamp(os.fstat(handle.fileno())),
                    "source-changed", "Metadata changed while being read")
            return data

    def json(self, relative, limit=32 * CHUNK):
        return json.loads(self.read(relative, limit))

    def snapshot(self, destination=None):
        inventory, identities = [], {}

        def visit(directory, prefix):
            for name in sorted(os.listdir(directory)):
                relative = prefix + name
                parts(relative)
                info = os.stat(name, dir_fd=directory, follow_symlinks=False)
                if stat.S_ISDIR(info.st_mode):
                    child = os.open(name, os.O_RDONLY | os.O_DIRECTORY | NOFOLLOW, dir_fd=directory)
                    try:
                        require((info.st_dev, info.st_ino) == (os.fstat(child).st_dev, os.fstat(child).st_ino),
                                "source-changed", "Directory changed while being opened")
                        inventory.append({"path": relative, "type": "directory"})
                        identities[relative] = (info.st_dev, info.st_ino, info.st_mode)
                        if destination:
                            destination.mkdir(relative)
                        visit(child, relative + "/")
                        if destination:
                            with destination.parent(relative) as (parent, leaf):
                                target = os.open(leaf, os.O_RDONLY | os.O_DIRECTORY | NOFOLLOW, dir_fd=parent)
                                try:
                                    os.fsync(target)
                                finally:
                                    os.close(target)
                    finally:
                        os.close(child)
                else:
                    require(stat.S_ISREG(info.st_mode), "unsafe-file", "Symlinks and special files are not accepted")
                    source = os.open(name, os.O_RDONLY | NOFOLLOW, dir_fd=directory)
                    with os.fdopen(source, "rb") as src:
                        before = os.fstat(src.fileno())
                        require(stamp(info) == stamp(before), "source-changed", "File changed while being opened")
                        digest, count = hashlib.sha256(), 0
                        output = os.fdopen(destination.open(relative, write=True), "wb") if destination else contextlib.nullcontext()
                        with output as dst:
                            while True:
                                block = src.read(CHUNK)
                                if not block:
                                    break
                                digest.update(block)
                                count += len(block)
                                if dst:
                                    dst.write(block)
                            if dst:
                                dst.flush()
                                os.fsync(dst.fileno())
                        require(count == before.st_size and stamp(before) == stamp(os.fstat(src.fileno())),
                                "source-changed", "File changed while being copied")
                        inventory.append({"path": relative, "type": "file", "bytes": count, "sha256": digest.hexdigest()})
                        identities[relative] = stamp(before)
            if destination:
                # Every destination directory was created privately by this run.
                target = destination.fd if not prefix else None
                if target is not None:
                    os.fsync(target)

        visit(self.fd, "")
        return sorted(inventory, key=lambda x: x["path"]), identities


def separated(a, b):
    common = Path(os.path.commonpath([absolute(a), absolute(b)]))
    require(common not in (absolute(a), absolute(b)), "overlapping-paths", "Source and destination must be separate trees")


@contextlib.contextmanager
def offline(tree, detached=False):
    """Only take existing locks: even a read-only check creates no source file."""
    held, proof = [], []
    try:
        for name, needed in [("instance.lock", True), ("Feedback-v01/feedback.lock", tree.exists("Feedback-v01/feedback.sqlite"))]:
            if not tree.exists(name):
                require(detached or not needed, "offline-lock-missing",
                        "Existing offline ownership lock is missing; use --detached-source only for a detached copy")
                continue
            fd = tree.open(name)
            try:
                fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
            except OSError:
                os.close(fd)
                raise StorageError("source-in-use", "Riftlet or a sidecar still owns the source; no files were copied")
            held.append(fd)
            proof.append(name)
        yield {"kind": "detached-source-declaration" if detached else "cooperative-offline-locks", "locksHeld": proof}
        for name, fd in zip(proof, held):
            with os.fdopen(tree.open(name), "rb") as check:
                a, b = os.fstat(fd), os.fstat(check.fileno())
                require((a.st_dev, a.st_ino) == (b.st_dev, b.st_ino), "source-changed", "An ownership lock was replaced")
    finally:
        for fd in reversed(held):
            os.close(fd)


def quoted(identifier):
    return '"' + identifier.replace('"', '""') + '"'


def row_hash(row):
    digest = hashlib.sha256()
    for value in row:
        if value is None:
            tag, data = b"n", b""
        elif isinstance(value, bytes):
            tag, data = b"b", value
        elif isinstance(value, str):
            tag, data = b"t", value.encode("utf-8")
        elif isinstance(value, int):
            tag, data = b"i", str(value).encode("ascii")
        else:
            tag, data = b"f", struct.pack(">d", value)
        digest.update(tag + len(data).to_bytes(8, "big") + data)
    return digest.digest()


def inspect(tree, inventory, known_queue_version=CURRENT_QUEUE_VERSION):
    """Health is distinct from byte integrity; no repair/adoption is performed."""
    indexed = {entry["path"]: entry for entry in inventory}
    errors, warnings, databases, images = [], [], {}, {}

    def issue(code, path, **facts):
        errors.append({"code": code, "path": path, **facts})

    def check_image(image, location, fallback=None):
        require(isinstance(image, dict), "invalid-image-metadata", "Expected image metadata")
        name, digest, size = image.get("fileName"), image.get("sha256"), image.get("byteCount")
        require(isinstance(name, str) and len(parts(name)) == 1 and isinstance(digest, str)
                and HEX.fullmatch(digest.lower()) and type(size) is int and size > 0,
                "invalid-image-metadata", "Invalid immutable image metadata")
        candidate = indexed.get("media/" + name)
        if not candidate and fallback:
            candidate = indexed.get(fallback)
        if not candidate:
            issue("missing-media", location)
        elif candidate.get("type") != "file" or candidate.get("sha256") != digest.lower() or candidate.get("bytes") != size:
            issue("media-content-mismatch", location)

    with tempfile.TemporaryDirectory(prefix="riftlet-storage-check-") as temporary:
        scratch = Path(temporary).resolve()
        names = [p for p, e in indexed.items() if e["type"] == "file" and p.lower().endswith((".sqlite", ".db"))]
        if "queue.sqlite" not in names:
            issue("queue-database-missing", "queue.sqlite")
        for relative in names:
            target = scratch / relative
            target.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
            for suffix in ("", "-wal", "-shm", "-journal"):
                origin = relative + suffix
                if origin not in indexed:
                    continue
                with os.fdopen(tree.open(origin), "rb") as src, open(str(target) + suffix, "xb") as dst:
                    while block := src.read(CHUNK):
                        dst.write(block)
            connection = None
            try:
                # Recovery/checkpoint, if required by SQLite, affects this copy only.
                connection = sqlite3.connect(target.as_uri() + "?mode=rw", uri=True, timeout=1)
                connection.enable_load_extension(False)
                connection.execute("PRAGMA trusted_schema=OFF")
                connection.execute("PRAGMA query_only=ON")
                version = connection.execute("PRAGMA user_version").fetchone()[0]
                integrity = [x[0] for x in connection.execute("PRAGMA integrity_check")]
                foreign = sum(1 for _ in connection.execute("PRAGMA foreign_key_check"))
                tables = {}
                schema = list(connection.execute("SELECT type,name,tbl_name,sql FROM sqlite_master ORDER BY type,name"))
                for (name,) in connection.execute("SELECT name FROM sqlite_master WHERE type='table' ORDER BY name"):
                    rows = sorted(row_hash(row) for row in connection.execute("SELECT * FROM " + quoted(name)))
                    tables[name] = {"rows": len(rows), "contentSHA256": sha(b"".join(rows))}
                result = {"userVersion": version, "integrityCheck": integrity, "foreignKeyViolations": foreign,
                          "schemaSHA256": sha(b"".join(row_hash(row) for row in schema)), "tables": tables}
                databases[relative] = result
                if integrity != ["ok"]:
                    issue("sqlite-integrity", relative)
                if foreign:
                    issue("sqlite-foreign-keys", relative, count=foreign)
                if relative == "queue.sqlite":
                    if not 1 <= version <= known_queue_version:
                        warnings.append({"code": "queue-schema-not-understood", "userVersion": version})
                    if "operations" in tables:
                        result["unknownOperationSequences"] = [x[0] for x in connection.execute("SELECT sequence FROM operations WHERE phase='unknown' ORDER BY sequence")]
                    if "assets" in tables:
                        for sequence, identifier, name, raw in connection.execute("SELECT sequence,id,file_name,image_json FROM assets ORDER BY sequence"):
                            location = "queue.sqlite:asset:" + str(sequence)
                            try:
                                image = json.loads(raw)
                                require(image.get("fileName") == name and str(image.get("id")).lower() == identifier.lower(),
                                        "image-identity-mismatch", "Queue image identity differs")
                                check_image(image, location)
                                images[identifier.lower()] = image
                            except (ValueError, TypeError, AttributeError, StorageError) as error:
                                issue(getattr(error, "code", "invalid-image-json"), location)
                elif relative == "Feedback-v01/feedback.sqlite" and version != 1:
                    warnings.append({"code": "feedback-schema-not-understood", "userVersion": version})
            except (sqlite3.Error, UnicodeError, ValueError) as error:
                issue("sqlite-unreadable", relative, exception=type(error).__name__)
            finally:
                if connection:
                    connection.close()

    journaled, pending = set(), 0
    for relative, entry in indexed.items():
        if not (relative.startswith("journal/") and relative.endswith(".json") and entry["type"] == "file"):
            continue
        try:
            manifest = tree.json(relative, 32768)
            image = manifest["image"]
            identifier = str(uuid.UUID(image["id"]))
            require(manifest.get("version") == 1 and relative.lower() == "journal/" + identifier + ".json"
                    and image["fileName"].startswith(identifier + "."), "invalid-import-journal", "Journal identity differs")
            stage = "staging/" + identifier + ".part"
            journaled.add(stage)
            check_image(image, relative, stage)
            if identifier in images and images[identifier] != image:
                issue("journal-queue-mismatch", relative)
            if "media/" + image["fileName"] not in indexed and stage in indexed:
                pending += 1
        except (ValueError, KeyError, TypeError, AttributeError, StorageError) as error:
            issue(getattr(error, "code", "invalid-import-journal"), relative)
    loose_staging = sum(e["type"] == "file" and p.startswith("staging/") and p not in journaled for p, e in indexed.items())
    if pending:
        warnings.append({"code": "journaled-import-awaiting-native-recovery", "count": pending})
    if loose_staging:
        warnings.append({"code": "unowned-staging-retained", "count": loose_staging})
    for name in ("rift-configuration.json", "lifecycle-settings.json", "capture-entry-settings.json", "arrival-motion-settings.json"):
        if name in indexed:
            try:
                tree.json(name)
            except (ValueError, StorageError):
                issue("settings-json-unreadable", name)
    return {"status": "attention" if errors else "ok", "errors": errors, "warnings": warnings,
            "databases": databases, "migrationPerformed": False, "mediaDecodePerformed": False}


def source_still_same(tree, inventory, identities):
    current, stamps = tree.snapshot()
    require(current == inventory and stamps == identities, "source-changed", "Source changed during the operation; incomplete output is retained")
    with Tree(tree.path) as again:
        a, b = os.fstat(tree.fd), os.fstat(again.fd)
        require((a.st_dev, a.st_ino) == (b.st_dev, b.st_ino), "source-changed", "Source root was replaced")


def provenance():
    return {"tool": "storage-recovery.py", "toolSHA256": sha(Path(__file__).read_bytes()),
            "python": sys.version.split()[0], "sqlite": sqlite3.sqlite_version}


def health(source, detached=False):
    with Tree(source) as tree, offline(tree, detached) as proof:
        inventory, identities = tree.snapshot()
        result = inspect(tree, inventory)
        source_still_same(tree, inventory, identities)
        return {"command": "health", "sourceReadOnly": True, "offline": proof,
                "inventorySHA256": sha(encoded(inventory)), "health": result, **provenance()}


def backup(source, destination, detached=False):
    separated(source, destination)
    with Tree(source) as tree, offline(tree, detached) as proof:
        with Tree(destination, create=True) as output:
            capture = {"format": FORMAT, "startedAt": now(), "captureID": str(uuid.uuid4()),
                       "sourceDirectoryName": tree.path.name, "offline": proof, **provenance()}
            output.write("capture.json", encoded(capture))
            try:
                output.mkdir("data")
                with Tree(output.path / "data") as data:
                    inventory, identities = tree.snapshot(data)
                    copied, _ = data.snapshot()
                    require(copied == inventory, "copy-mismatch", "Copied bytes do not match source inventory")
                    report = inspect(data, inventory)
                source_still_same(tree, inventory, identities)
                manifest = {"format": FORMAT, "completedAt": now(), "captureSHA256": sha(encoded(capture)),
                            "entries": inventory, "health": report, "knownQueueVersion": CURRENT_QUEUE_VERSION,
                            "exclusions": ["Original screenshots outside this directory", "UserDefaults and source-access bookmarks",
                                           "Keychain credentials", "macOS permissions", "Other mode roots or external native clipboard journal"],
                            "metadataScope": "Regular-file bytes and empty directories; private output modes. No ACL/xattr or filesystem snapshot claim."}
                body = encoded(manifest)
                require(len(body) <= 32 * CHUNK, "oversized-metadata", "Manifest exceeds the verifier's bounded reader; copied data is retained")
                output.write("manifest.json", body)
                output.write("COMPLETE.json", encoded({"format": FORMAT, "manifestSHA256": sha(body)}))
                return {"command": "backup", "byteIntegrity": "verified", "manifestSHA256": sha(body),
                        "files": sum(e["type"] == "file" for e in inventory), "health": report,
                        "offline": proof, "sourceReadOnly": True}
            except BaseException as error:
                try:
                    output.write("failure.json", encoded({"failedAt": now(), "exception": type(error).__name__,
                                                          "code": getattr(error, "code", "operation-interrupted")}))
                except OSError:
                    pass
                raise


def validate_entries(entries):
    require(isinstance(entries, list), "invalid-manifest", "Missing entries")
    seen = {}
    for entry in entries:
        require(isinstance(entry, dict), "invalid-manifest", "Invalid entry")
        relative = entry.get("path")
        names = parts(relative)
        require(relative not in seen, "invalid-manifest", "Duplicate path")
        kind = entry.get("type")
        require(kind in ("file", "directory"), "invalid-manifest", "Invalid entry kind")
        if kind == "file":
            require(set(entry) == {"path", "type", "bytes", "sha256"} and type(entry["bytes"]) is int and entry["bytes"] >= 0
                    and isinstance(entry["sha256"], str) and HEX.fullmatch(entry["sha256"]), "invalid-manifest", "Invalid file entry")
        else:
            require(set(entry) == {"path", "type"}, "invalid-manifest", "Invalid directory entry")
        seen[relative] = kind
        for i in range(1, len(names)):
            parent = "/".join(names[:i])
            require(seen.get(parent) == "directory", "invalid-manifest", "Missing or conflicting parent directory")
    require(entries == sorted(entries, key=lambda x: x["path"]), "invalid-manifest", "Entries are not canonical")


def verified_bundle(bundle, expected=None):
    require(set(os.listdir(bundle.fd)) == {"capture.json", "manifest.json", "COMPLETE.json", "data"},
            "incomplete-or-altered-bundle", "Bundle has missing or unexpected entries; partial captures are retained")
    body = bundle.read("manifest.json")
    digest = sha(body)
    complete = bundle.json("COMPLETE.json")
    require(complete == {"format": FORMAT, "manifestSHA256": digest}, "manifest-checksum", "Manifest checksum differs")
    if expected:
        require(HEX.fullmatch(expected) and expected == digest, "manifest-checksum", "Manifest does not match the external expected digest")
    manifest = json.loads(body)
    require(isinstance(manifest, dict) and manifest.get("format") == FORMAT, "invalid-manifest", "Unsupported backup format")
    # Original backups include the v3 inspector's warnings in their exact
    # health checksum, even if that tool backed up a newer queue.
    known_queue_version = manifest.get("knownQueueVersion", 3)
    require(type(known_queue_version) is int and known_queue_version in (3, 4),
            "invalid-manifest", "Unsupported queue inspection version")
    require(manifest.get("captureSHA256") == sha(bundle.read("capture.json")), "capture-checksum", "Capture provenance differs")
    validate_entries(manifest.get("entries"))
    with Tree(bundle.path / "data") as data:
        actual, identities = data.snapshot()
        require(actual == manifest["entries"], "data-checksum", "Backup data bytes or inventory differ")
        report = inspect(data, actual, known_queue_version)
        source_still_same(data, actual, identities)
        require(report == manifest.get("health"), "health-checksum", "Logical database or media health differs from the capture")
    return digest, manifest, known_queue_version


def verify(source, expected=None):
    with Tree(source) as bundle:
        digest, manifest, _ = verified_bundle(bundle, expected)
        return {"command": "verify", "byteIntegrity": "verified", "manifestSHA256": digest, "health": manifest["health"],
                "authenticity": "external-digest-matched" if expected else "self-checksum-only"}


def restore(source, destination, expected=None):
    separated(source, destination)
    with Tree(source) as bundle:
        digest, manifest, known_queue_version = verified_bundle(bundle, expected)  # Reject before making a destination.
        with Tree(destination, create=True) as output, Tree(bundle.path / "data") as data:
            try:
                inventory, identities = data.snapshot(output)
                require(inventory == manifest["entries"], "data-checksum", "Bundle changed during restore")
                restored, _ = output.snapshot()
                require(restored == inventory, "restore-checksum", "Restored bytes differ")
                report = inspect(output, restored, known_queue_version)
                require(report == manifest["health"], "restore-health", "Restored logical health differs")
                source_still_same(data, inventory, identities)
                receipt = {"format": FORMAT, "restoredAt": now(), "manifestSHA256": digest,
                           "dataInventorySHA256": sha(encoded(inventory)), "health": report,
                           "applicationStarted": False, "migrationPerformed": False, **provenance()}
                receipt_name = ".storage-restore-" + str(uuid.uuid4()) + ".json"
                output.write(receipt_name, encoded(receipt))
                return {"command": "restore", "byteIntegrity": "verified", "manifestSHA256": digest,
                        "receipt": receipt_name, "health": report, "applicationStarted": False}
            except BaseException as error:
                try:
                    output.write(".storage-restore-failed-" + str(uuid.uuid4()) + ".json",
                                 encoded({"format": FORMAT, "failedAt": now(), "manifestSHA256": digest,
                                          "exception": type(error).__name__, "code": getattr(error, "code", "operation-interrupted"),
                                          "applicationStarted": False}))
                except OSError:
                    pass
                raise


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    for name in ("health", "backup", "verify", "restore"):
        command = commands.add_parser(name)
        command.add_argument("--source", required=True, help="Data root for health/backup; bundle root for verify/restore")
        if name in ("backup", "restore"):
            command.add_argument("--destination", required=True, help="A nonexistent directory under an existing parent")
        if name in ("health", "backup"):
            command.add_argument("--detached-source", action="store_true", help="Declare an already-detached offline copy; never bypass a held lock")
        else:
            command.add_argument("--expected-manifest-sha256", help="Trusted digest saved separately from the bundle")
    args = parser.parse_args(argv)
    try:
        if args.command == "health":
            result = health(args.source, args.detached_source)
        elif args.command == "backup":
            result = backup(args.source, args.destination, args.detached_source)
        elif args.command == "verify":
            result = verify(args.source, args.expected_manifest_sha256)
        else:
            result = restore(args.source, args.destination, args.expected_manifest_sha256)
        print(json.dumps(result, ensure_ascii=True, sort_keys=True, indent=2))
        return 0 if result["health"]["status"] == "ok" else 2
    except (StorageError, OSError, ValueError, sqlite3.Error) as error:
        print(json.dumps({"command": args.command, "status": "refused-or-incomplete",
                          "code": getattr(error, "code", type(error).__name__), "detail": str(error)}, ensure_ascii=True), file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
