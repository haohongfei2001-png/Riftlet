#!/usr/bin/env python3
"""Validate or create a named notarytool Keychain profile using Apple's own secure prompt."""
import argparse
import importlib.util
from pathlib import Path
import subprocess
import sys

SPEC = importlib.util.spec_from_file_location("riftlet_pipeline", Path(__file__).with_name("release-macos.py"))
P = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(P)


def configure(profile, team, identity):
    P.R.credential_values(profile=profile, notary=True)
    cmd = ["xcrun", "notarytool"]
    result = subprocess.run([*cmd, "history", "--keychain-profile", profile, "--output-format", "json"],
                            stdout=subprocess.DEVNULL, stderr=subprocess.PIPE, timeout=60)
    if result.returncode == 0:
        print("Existing Keychain profile authenticated.")
        return 0
    if b"no keychain password item found for profile" not in result.stderr.lower():
        print("The existing profile or Apple service could not be verified. Kept the Keychain as it was.")
        return 3
    if not sys.stdin.isatty() or not sys.stdout.isatty():
        print("Open a local Terminal to configure this profile with Apple's interactive password prompt.")
        return 3
    _, team = P.select_signer(identity, team)
    account = input("Apple Account email for notarization: ").strip()
    if not account or account.startswith("-") or "@" not in account or any(c.isspace() for c in account):
        raise P.R.ReleaseError("invalid_apple_account")
    # Do not read or forward the password. notarytool owns the controlling terminal.
    return subprocess.run([*cmd, "store-credentials", profile, "--apple-id", account, "--team-id", team]).returncode


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--profile", default="Riftlet-Notary")
    parser.add_argument("--team")
    parser.add_argument("--identity")
    args = parser.parse_args()
    try:
        sys.exit(configure(args.profile, args.team, args.identity))
    except (P.R.ReleaseError, OSError, EOFError, subprocess.TimeoutExpired) as error:
        sys.exit(error.code if isinstance(error, P.R.ReleaseError) else type(error).__name__)
