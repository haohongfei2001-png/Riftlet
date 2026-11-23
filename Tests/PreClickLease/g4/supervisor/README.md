# Build 60 website QA supervisor

The monitor samples the two ordinary signed browsers through the private GUI owner's fixed native host. It reads only the host's state digest, twelve visibility and identity checks, the designated case, and an opaque target hash. The independent source, signed DMG, installation and site evidence have separate gates. A host result recorded here does not authorize publication.

## Start and inspect

Use the same private, persistent state directory throughout this candidate. Keep it outside the product profile, old test archives and temporary directories. Run commands in the logged-in macOS user's Aqua session. The registered host, its components and the script must be available across a restart. The host's bundle registry and private inputs are supplied by the GUI owner.

```sh
Q="$PWD/Tests/PreClickLease/g4/supervisor/monitor.py"
S="$HOME/Library/Application Support/Riftlet-QA/1.0.8-60/continuity"
H="/private/tmp/r108-60-continuous-gui-private/host"
L="/private/tmp/r108-60-continuous-gui-private/gui.lock"
python3 -B "$Q" --state "$S" configure --host "$H" --gui-lock "$L"
python3 -B "$Q" --state "$S" run
```

Configuration starts **disarmed**. Continuous read-only polling can coexist with the GUI owner. A poll runs every 120 to 300 seconds. A missing host, failed permission, inconsistent proof or missing original target authorizes zero input. On wake the next poll uses a fresh nonce. Both wall time and monotonic time bound the wait. A healthy sample updates the per-browser counter even when the desktop stays unchanged. The transition log has one environment entry per change.

```sh
python3 -B "$Q" --state "$S" status
```

Status shows the singleton lock, PID of its current holder, start time, monitor/host fingerprints, shared GUI lease state, per-browser sample counts and latest UTC observation. An occupied GUI lease can belong to the separate GUI owner. The SQLite audit log and attempt records survive process exit. A command opening a second state directory against the registered GUI lock root is refused.

## GUI handoff and resumption

The GUI owner and scheduler use the same exclusive `flock`. The owner registers any potentially input-producing run started independently before transferring control. Use its real prior target digest and privately retained evidence. The printed private claim path allows the original executor to deliver its terminal receipt later.

```sh
python3 -B "$Q" --state "$S" adopt edge g4c "$PRIOR_TARGET_SHA256" "$ORIGINAL_OWNER_RECEIPT"
python3 -B "$Q" --state "$S" arm
```

An independently initiated case that remained before its input boundary can instead be handed over with the original executor's affirmative zero-input evidence. If the outcome is uncertain, keep its claim and process other work. Preserve the shared state directory. Never reset it to authorize another click.

`disarm` prevents additional suite dispatches. `stop` also requests a clean monitor exit after any in-flight host invocation has returned. Neither kills a browser or cancels a partially executed product action. `resume` clears the stop request. Then run the same command or start the same LaunchAgent. Existing uncertain cases are reconciled read-only. Inspect both the monitor lock and GUI lease before transferring ownership.

If the private native host or component manifest changes, audit the actual bytes first. With the monitor disarmed, run `update-pin --host-sha256 HASH --manifest-sha256 HASH`. This updates fingerprints only. All pending attempts and terminal records remain in the same journal.

The `plist` command emits a per-user Aqua LaunchAgent definition with `RunAtLoad`, crash restart and at least 120 seconds between launches. For login persistence place the reviewed monitor, native host, dependencies and durable state on persistent storage. A deployment under `/private/tmp` may vanish at reboot. A missing component keeps the service in read-only wait until the owner restores its exact bytes. Use the same private state and explicitly configured lock directory after a host restart. A LaunchAgent only runs while the user is logged in.

```sh
P="$HOME/Library/LaunchAgents/com.riftlet.qa.build60.supervisor.plist"
python3 -B "$Q" --state "$S" plist > "$P"
launchctl bootstrap "gui/$(id -u)" "$P"
launchctl print "gui/$(id -u)/com.riftlet.qa.build60.supervisor"
```

Use `stop` and wait for any active GUI lease before `launchctl bootout`. To restart a registered, stopped service, clear `stop` with `resume`, then use `launchctl kickstart` without replacing a running process.

## Native host contract

| Command | Result and required behavior |
| --- | --- |
| `host sample FAMILY NONCE` | Read-only observation, without activation, input or window creation. Returns the supplied family and fresh nonce, stable environment SHA-256 in `digest`, `environment.eligibleForPreparation`, `ready`, `checks`, bound `heldCase`, and `targetKey`. |
| `host prepare FAMILY CASE NONCE` | Receives the shared GUI lease. May restore only the designated QA window. The owner creates a new scope only if the previous one is absent and it is safe to prepare. One preparation per case and positively observed environment transition. An unavailable sample cannot reset this allowance. |
| `host run FAMILY CASE NONCE CLAIM_JSON` | Receives the shared GUI lease and the durably registered original attempt. It must recheck matching candidate, foreground, target, case and actual draft immediately before each product input. Its original normal entry point runs the real suite and produces a terminal receipt. |

The native host's positive visibility checks are `originalProcessBirth`, `dedicatedSingleTab`, `nativeForeground`, `nativeWindowVisible`, `cgWindowOnScreen`, `axOriginalWindow`, `originalTabSelected`, `documentVisible`, `documentFocused`, `signedIn`, `composer`, and `uploadEntry`. A second fresh sample acquired under the lease must reproduce the target and environment. After successfully preparing a fresh dedicated window, two positive samples under the same GUI lease may immediately trigger that case, before the window loses foreground. A consumed target cannot be used for a different case. The live executor addresses only the held case, even if another suite was scheduled earlier. The installed mappings are Chrome G1 and Edge G2, G4-C and B4. The size-limit probe on its own does not decide G4-B equivalence.

The host receives `RIFTLET_GUI_LOCK_FD` and `RIFTLET_GUI_LOCK_PATH`. It verifies the same inode and keeps the lease through its last child with access to GUI input. A host or user process that directly runs these same fixtures must participate in this lock. The host never treats an Apple Event success alone as permission to enter input.

Each claim contains `attemptID`, `nonce`, `family`, `case`, `targetKey`, `source`, `dmgSHA256` and `terminalPath`. The journal commits the claim and syncs the host-entry marker before launching the input-capable process. The original host writes a terminal file by fsync and atomic rename. It includes the matching identity fields, `outcome` and relevant evidence. Its stdout adds the exact `receiptPath` and `receiptSHA256`.

* `PASS` requires the actual acceptance report's absolute private path (`acceptanceEvidencePath`) and its recalculated SHA-256 (`acceptanceEvidenceSHA256`). Independent release review still has to verify its contents.
* `STOPPED_BEFORE_INPUT` requires a proven `inputBoundaryEntered: false` and integer `productInputCount: 0`. Only this can re-enable the same case on a later environment change.
* `INCONCLUSIVE`, an unbound result, a killed process, or a lost reply leaves the task claimed. The monitor reads later original receipts without running the suite again. Other independent families and cases can proceed.

The scheduler never interprets a missing terminal file as zero input once the input-capable host could have started. If the scheduler crashed strictly before its durable host-entry marker, it can verify an unused GUI lease and safely retire only that unused claim. Please keep raw terminal, page and target evidence private. Public acceptance uses the separately sanitized site receipts.

## Controlled tests

```sh
python3 -B -m unittest discover -s Tests/PreClickLease/g4/supervisor -v
```

The fixtures use private temporary files and an executable stub. They do not start or operate a desktop browser. Check real service liveness with two increasing valid sample counts and the same live worker PID; passing these tests alone does not establish supervisor deployment or a website result.
