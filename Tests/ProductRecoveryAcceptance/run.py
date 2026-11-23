#!/usr/bin/env python3
"""Operate only the newly created native test application, owned page and private SQLite."""

import argparse, fcntl, hashlib, json, os, plistlib, sqlite3, subprocess, time, uuid
from pathlib import Path


def sha(p):
    return hashlib.file_digest(p.open("rb"), "sha256").hexdigest()


def dump(p, v):
    p.write_text(json.dumps(v, indent=2, ensure_ascii=False))


def read(p):
    return json.loads(p.read_bytes())


def until(fn, limit=20, label="condition"):
    end = time.monotonic() + limit
    while time.monotonic() < end:
        v = fn()
        if v:
            return v
        time.sleep(0.09)
    raise RuntimeError("timeout: " + label)


class Run:
    def __init__(self, build, root):
        self.build = build
        self.root = root
        self.pid = str(uuid.uuid4())
        self.app = None
        self.page = None
        self.step = 0
        root.mkdir(mode=0o700)
        for s in ["ui", "page"]:
            for suffix in ["in", "inflight", "out"]:
                (root / (s + "-" + suffix)).mkdir(mode=0o700)
        self.profile = root / "app-support" / ("Riftlet-PreClick-QA-" + self.pid)
        self.db = self.profile / "queue.sqlite"
        self.manifest = read(build / "manifest.json")
        dump(root / "binary-manifest.json", self.manifest)
        for artifact in [
            Path(self.manifest["product"]),
            build / "page-host",
            build / "page/shipping-adapter.js",
        ]:
            if sha(artifact) != self.manifest["sha256"][str(artifact)]:
                raise RuntimeError("Built artifact changed")

    def rpc(self, kind, action, **kw):
        name = str(uuid.uuid4()) + ".json"
        request = self.root / (kind + "-in") / name
        reply = self.root / (kind + "-out") / name
        tmp = request.with_suffix(".tmp")
        dump(tmp, dict(action=action, **kw))
        tmp.replace(request)
        until(reply.exists, 12, kind + "/" + action)
        obj = read(reply)
        if not obj.get("ok"):
            raise RuntimeError(str((action, obj)))
        return obj.get("value", obj)

    def pagecall(self, a, **k):
        return self.rpc("page", a, **k)

    def ui(self, a, **k):
        return self.rpc("ui", a, **k)

    def sql(self):
        with sqlite3.connect(self.db.as_uri() + "?mode=ro", uri=True) as cx:
            cx.row_factory = sqlite3.Row
            return {
                t: [dict(r) for r in cx.execute("SELECT * FROM " + t)]
                for t in [
                    "assets",
                    "operations",
                    "upload_starts",
                    "attachment_reselections",
                ]
            }

    def copydb(self, tag):
        a = sqlite3.connect(self.db.as_uri() + "?mode=ro", uri=True)
        b = sqlite3.connect(self.root / (tag + ".sqlite"))
        a.backup(b)
        a.close()
        b.close()

    def snap(self, tag):
        result = {
            "page": self.pagecall("snapshot"),
            "ui": self.ui("read"),
            "db": self.sql(),
        }
        self.copydb(tag)
        dump(self.root / (tag + ".json"), result)
        return result

    def boot(self):
        env = dict(os.environ, RIFTLET_OWNED_RECOVERY_FIXTURE=str(self.root))
        self.app = subprocess.Popen(
            [
                self.manifest["product"],
                "--preclick-qa-profile",
                self.pid,
                "--acceptance-trace",
            ],
            env=env,
            stdout=(self.root / f"app-{self.step}.log").open("a"),
            stderr=subprocess.STDOUT,
        )
        until(
            lambda: any(
                read(p).get("event") == "productUIReady"
                and read(p).get("pid") == self.app.pid
                for p in self.root.glob("transport-*.json")
            ),
            25,
            "Riftlet normal startup",
        )

    def start(self):
        self.page = subprocess.Popen(
            [
                str(self.build / "page-host"),
                str(self.root),
                str(self.build / "page/index.html"),
            ],
            stdout=(self.root / "page.log").open("w"),
            stderr=subprocess.STDOUT,
        )
        until((self.root / "native.json").exists, 8, "WK doc loaded")
        doc = self.pagecall("snapshot")
        js = (
            self.build
            / "source/Sources/RiftletAdapters/Resources/chatgpt-web-20261027.js"
        )
        assert doc["adapterSHA256"] == self.manifest["sha256"][str(js)]
        assert (
            doc["originalDocument"]
            and doc["selection"] == "preserve this original draft"
        )
        dump(self.root / "initial-document.json", doc)
        self.boot()
        png = (
            self.profile
            / "capture-source"
            / ("Screenshot Recovery " + self.pid + ".png")
        )
        wid = read(self.root / "native.json")["windowID"]
        subprocess.run(
            ["/usr/sbin/screencapture", "-x", "-o", "-l", wid, str(png)], check=True
        )
        mark = plistlib.loads(
            bytes.fromhex(
                subprocess.check_output(
                    [
                        "/usr/bin/xattr",
                        "-px",
                        "com.apple.metadata:kMDItemIsScreenCapture",
                        str(png),
                    ],
                    text=True,
                )
            )
        )
        assert mark is True or mark == 1
        dump(
            self.root / "screenshot.json",
            {
                "windowID": wid,
                "source": "screencapture -l exact owned WK host",
                "sha256": sha(png),
                "bytes": png.stat().st_size,
                "systemMarker": bool(mark),
            },
        )
        until(lambda: len(self.sql()["assets"]) == 1, 18, "captured PNG imported")
        assert (
            len(
                [
                    q
                    for q in (self.profile / "media").iterdir()
                    if q.is_file() and sha(q) == sha(png)
                ]
            )
            == 1
        )

    def click(self):
        self.ui("approach")
        until(lambda: self.ui("read")["binding"], 14, "witness for tray press")
        until(lambda: bool(self.ui("read")["rows"]), 8, "visible original tray")
        time.sleep(0.36)
        return self.ui("tray")

    def history(self):
        self.ui("history")
        until(
            lambda: any(
                b["id"] == "control.history" for b in self.ui("read")["buttons"]
            ),
            5,
            "control center history button",
        )
        self.button("control.history")
        until(lambda: self.ui("read")["tables"], 6, "history table")
        self.ui("table")
        time.sleep(0.25)

    def button(self, key):
        return self.ui("button", key=key)

    def risk(self):
        self.button("history.reattach")
        return until(
            lambda: (u if (u := self.ui("read"))["sheets"] else None), 5, "risk sheet"
        )

    def title(self, options):
        b = self.ui("read")["buttons"]
        return next(
            (i["title"] for i in b if i["title"] in options and i["enabled"]), None
        )

    def confirm(self):
        key = self.title(
            [
                "准备重新附加",
                "Prepare to Attach Again",
                "Attach Again Anyway",
                "仍要重新附加",
                "Reattach Anyway",
            ]
        )
        if not key:
            raise RuntimeError("no explicit consent control")
        self.button(key)
        time.sleep(0.45)
        self.button("history.focusOriginal")
        time.sleep(0.3)

    def startup_case(self, mode="preview"):
        self.pagecall("setNext", mode=mode)
        self.click()

    def settle(self, n):
        until(
            lambda: len(self.sql()["upload_starts"]) == n, 30, "durable original START"
        )
        until(
            lambda: self.sql()["operations"][-1]["phase"] == "unknown",
            25,
            "stable UNKNOWN",
        )

    def run(self, kind):
        self.start()
        if kind == "A":
            self.startup_case("pre-input-failure")
            until(
                lambda: len(self.sql()["operations"]) == 1
                and self.sql()["operations"][0]["phase"]
                not in ["prepared", "dispatchIntent"],
                25,
                "pre-input failed terminal",
            )
            first = self.snap("A-initial")
            assert (
                first["page"]["inputs"] == 0
                and not first["db"]["upload_starts"]
                and first["ui"]["rows"]
            )
            self.pagecall("setNext", mode="preview")
            self.click()
            self.settle(1)
            self.snap("A-after")
            return
        self.startup_case()
        if kind == "baseline":
            until(
                lambda: len(self.sql()["upload_starts"]) == 1,
                15,
                "durable original START",
            )
            time.sleep(0.4)
        else:
            self.settle(1)
        until(lambda: not self.ui("read")["rows"], 3, "completed swallow")
        b = self.snap("B-unknown")
        assert (
            b["page"]["inputs"] == 1
            and b["page"]["changes"] == 1
            and not b["ui"]["rows"]
        )
        src = read(self.root / "screenshot.json")
        assert b["page"]["files"][0]["sha256"] == src["sha256"]
        if kind == "rebirth":
            old = b["page"]["files"][0]["operationID"]
            self.pagecall("transition", id=old, mode="failed")

            def reborn():
                return (
                    self.ui("read")["rows"]
                    and self.sql()["assets"][0]["visibility_reason"] == "safeFailure"
                )

            until(reborn, 45, "exact original error produced a clickable row")
            before = self.snap("Reborn-visible")
            assert (
                len(before["db"]["operations"]) == 1 and before["page"]["inputs"] == 1
            )
            self.click()
            self.settle(2)
            self.snap("Reborn-attached")
            return
        if kind in ["B", "C"]:
            old = b["page"]["files"][0]["operationID"]
            self.pagecall("transition", id=old, mode="ambiguous")

            def uncertain():
                receipt = self.sql()["operations"][0]["receipt_json"]
                if not receipt:
                    return False
                value = json.loads(receipt)
                return (
                    value.get("outcome") == "unknown" and value.get("hasError") is True
                )

            until(uncertain, 45, "attributable weak failure on already accepted member")
            self.history()
            state = self.snap("B-neutral-unknown")
            assert state["page"]["inputs"] == 1 and state["page"]["setterEntries"] == 1
            assert not state["page"]["sends"] and not state["page"]["submits"]
            assert any(
                "结果尚未确认" in s
                or "Outcome unconfirmed" in s
                or "Outcome not confirmed" in s
                or "结果待确认" in s
                for s in state["ui"]["text"]
            ), state["ui"]["text"]
            self.snap("B-neutral-later")
            if kind == "B":
                return
        if kind == "G":
            self.quitapp()
            self.step += 1
            self.boot()
            time.sleep(2)
            self.snap("G-restart")
        if kind != "C":
            self.history()
        before = self.snap("D-existing")
        w = self.risk()
        dump(self.root / "D-warning.json", w)
        cancel = self.title(["取消", "Cancel"])
        assert cancel
        self.button(cancel)
        time.sleep(0.3)
        after = self.snap("H-cancel")
        assert (
            before["page"]["inputs"] == after["page"]["inputs"]
            and before["db"]["operations"] == after["db"]["operations"]
        )
        if kind == "H":
            return
        self.risk()
        self.confirm()
        if kind == "E":
            self.pagecall("navigate")
        self.click()
        if kind == "baseline" or kind == "E":
            time.sleep(5)
            self.snap(kind + "-final")
            return
        self.settle(2)
        positive = self.snap("C-explicit")
        assert positive["page"]["files"][1]["sha256"] == src["sha256"]
        if kind != "F":
            return
        old = positive["page"]["files"][0]["operationID"]
        self.pagecall("transition", id=old, mode="failed")

        def late():
            with sqlite3.connect(self.db.as_uri() + "?mode=ro", uri=True) as cx:
                return cx.execute(
                    "SELECT 1 FROM checkpoints WHERE key=?",
                    ("transfer-late-original-card-v1:" + old.upper(),),
                ).fetchone()

        until(late, 65, "original-only late observation")
        self.snap("F-late")

    def quitapp(self):
        if self.app and self.app.poll() is None:
            self.ui("quit")
            self.app.wait(timeout=12)

    def close(self):
        try:
            self.quitapp()
        except Exception:
            if self.app and self.app.poll() is None:
                self.app.terminate()
                self.app.wait(timeout=5)
        if self.page and self.page.poll() is None:
            try:
                self.pagecall("quit")
            except Exception:
                self.page.terminate()
            self.page.wait(timeout=5)


if __name__ == "__main__":
    if not __debug__:
        raise RuntimeError("Run with Python assertions enabled")
    a = argparse.ArgumentParser()
    a.add_argument("build", type=Path)
    a.add_argument("output", type=Path)
    a.add_argument(
        "case", choices=["baseline", "A", "B", "C", "D", "E", "F", "G", "H", "rebirth"]
    )
    v = a.parse_args()
    legacy_lock = Path("/private/tmp/r108-61-continuous-gui-private/gui.lock")
    default_lock = (
        legacy_lock
        if legacy_lock.is_file()
        else Path("/private/tmp")
        / ("riftlet-owned-recovery-" + str(os.getuid()) + ".lock")
    )
    lock_path = Path(os.environ.get("RIFTLET_RECOVERY_GUI_LOCK", str(default_lock)))
    fd = os.open(lock_path, os.O_RDWR | os.O_CREAT | os.O_NOFOLLOW, 0o600)
    if os.fstat(fd).st_uid != os.getuid():
        raise RuntimeError("Expected an owned GUI lock")
    lock = os.fdopen(fd, "a+")
    fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
    os.umask(0o077)
    r = Run(v.build, v.output)
    try:
        r.run(v.case)
    except Exception as e:
        dump(r.root / "stopped.json", {"error": str(e)})
        if r.app and r.app.poll() is None and r.db.exists():
            try:
                r.snap("stopped-state")
            except Exception:
                pass
        raise
    finally:
        r.close()
