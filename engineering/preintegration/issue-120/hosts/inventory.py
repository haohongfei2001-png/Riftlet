#!/usr/bin/env python3
"""Inspect signed browser bundles without launching them or touching their profiles."""
import argparse
import hashlib
import json
import plistlib
import subprocess
import tempfile
import xml.etree.ElementTree as ET
from pathlib import Path

BROWSERS = {
    "chrome": ("Google Chrome", "com.google.Chrome", "EQHXZ8M8AV"),
    "edge": ("Microsoft Edge", "com.microsoft.edgemac", "UBF8T346G9"),
    "safari": ("Safari", "com.apple.Safari", "not set"),
    "brave": ("Brave Browser", "com.brave.Browser", "KL8N8XSYF4"),
    "firefox": ("Firefox", "org.mozilla.firefox", "43AQ936H96"),
}
STANDARD = Path("/System/Library/ScriptingDefinitions/CocoaStandard.sdef")


def dictionaries(resources, declared):
    primary = resources / declared if declared else None
    if not primary or not primary.is_file():
        return [], []
    docs = [ET.parse(primary).getroot()]
    files = [primary]
    # Resolve the local Cocoa standard terminology only. Never follow arbitrary
    # schema locations or read application-controlled external XML references.
    if any(x.get("href") == STANDARD.as_uri() for x in docs[0].iter("{http://www.w3.org/2003/XInclude}include")):
        docs.append(ET.parse(STANDARD).getroot())
        files.append(STANDARD)
    return docs, files


def describe(bundle, expected, team, probe):
    info = plistlib.loads((bundle / "Contents/Info.plist").read_bytes())
    resources = bundle / "Contents/Resources"
    sig = subprocess.run(["codesign", "-dv", "--verbose=4", bundle], check=True,
                         capture_output=True, text=True).stderr.splitlines()
    field = lambda key: next((line.split("=", 1)[1] for line in sig if line.startswith(key + "=")), None)
    if info["CFBundleIdentifier"] != expected or field("Identifier") != expected or field("TeamIdentifier") != team:
        raise ValueError("Unexpected signing identity for " + expected)
    subprocess.run(["codesign", "--verify", "--all-architectures", bundle], check=True)
    assessment = subprocess.run(["spctl", "--assess", "--type", "execute", "--verbose=2", bundle],
                                check=True, capture_output=True, text=True)
    strict = subprocess.run(["codesign", "--verify", "--all-architectures", "--strict", bundle], capture_output=True, text=True)
    strict_result = "PASS" if strict.returncode == 0 else "FAIL"
    if strict.returncode and "resource fork, Finder information" in strict.stderr:
        strict_result = "FAIL_FINDER_METADATA"
    if expected == "com.apple.Safari":
        subprocess.run(["codesign", "--verify", "-R=anchor apple", bundle], check=True)
    docs, files = dictionaries(resources, info.get("OSAScriptingDefinition"))
    commands, props, receives = {}, {}, {}
    for doc in docs:
        for suite in doc.findall("suite"):
            for command in suite.findall("command"):
                if command.get("name") in ("do JavaScript", "execute"):
                    commands[command.get("name")] = {
                        "event": command.get("code"),
                        "parameters": [[p.get("name", "direct"), p.get("type") or [t.get("type") for t in p.findall("type")]] for p in command
                                       if p.tag in ("direct-parameter", "parameter")],
                    }
            for cl in suite:
                if cl.tag not in ("class", "class-extension"):
                    continue
                name = cl.get("name") or cl.get("extends")
                if name not in ("window", "tab", "document"):
                    continue
                props.setdefault(name, {}).update({p.get("name"): p.get("code") for p in cl.findall("property")
                                                 if p.get("name") in ("id", "index", "pid", "URL", "active tab", "current tab")})
                receives.setdefault(name, set()).update(p.get("command") for p in cl.findall("responds-to")
                                                       if p.get("command") in ("execute", "do JavaScript"))
    result = json.loads(subprocess.check_output([probe, bundle], timeout=10))
    result.update({
        "bundleID": expected, "version": info.get("CFBundleShortVersionString"), "build": info.get("CFBundleVersion"),
        "teamIdentifier": team, "cdhash": field("CDHash"), "codeSignature": "PASS",
        "gatekeeperAssessment": "ACCEPTED", "gatekeeperSource": next((l[7:] for l in assessment.stderr.splitlines() if l.startswith("source=")), None),
        "additionalStrictSignatureCheck": strict_result,
        "appleScriptEnabledInBundle": info.get("NSAppleScriptEnabled"),
        "declaredDictionary": info.get("OSAScriptingDefinition"),
        "scriptingResources": sorted(p.name for p in resources.iterdir()
                                     if p.suffix.lower() in (".sdef", ".scriptsuite", ".scriptterminology", ".rsrc")),
        "dictionaryHashes": {p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in files},
        "properties": props, "JavaScriptCommands": commands,
        "JavaScriptReceivers": {k: sorted(v) for k, v in receives.items() if v},
    })
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name, (app, _, _) in BROWSERS.items():
        parser.add_argument("--" + name, type=Path, default=Path("/Applications") / (app + ".app"))
    args = parser.parse_args()
    results = {}
    with tempfile.TemporaryDirectory() as tmp:
        probe = Path(tmp) / "ReceiverProbe"
        subprocess.run(["swiftc", "-parse-as-library", Path(__file__).with_name("ReceiverProbe.swift"), "-o", probe], check=True)
        for key, (_, bundle_id, team) in BROWSERS.items():
            bundle = getattr(args, key)
            results[key] = describe(bundle, bundle_id, team, probe) if bundle.is_dir() else {"status": "NOT_INSTALLED_AT_REQUESTED_PATH"}
    print(json.dumps({"macOS": subprocess.check_output(["sw_vers", "-productVersion"], text=True).strip(),
                      "systemBuild": subprocess.check_output(["sw_vers", "-buildVersion"], text=True).strip(),
                      "browserBundles": results}, indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
