# G4 acceptance tools

These read-only helpers correlate an independently observed ChatGPT Temporary Chat error with a saved screenshot and two product operations. Use Node.js 18+, an installed Chromium browser and Python 3.9+ with SQLite. The DOM test defaults to the standard macOS Google Chrome binary. Set RIFTLET_G4_BROWSER to an alternate installed Chromium binary for testing. They require no browser extension or Python package. The browser controls use a fresh headless profile, a local file and blocked external networking.

```sh
node --test Tests/PreClickLease/g4/card-observer.test.cjs
python3 -B -m unittest discover -s Tests/PreClickLease/g4 -p 'test*recovery.py'
node --test Tests/OfflineFaultHarness/round-two-network.test.cjs
```

## Collecting the site observations

Use the approved browser control and the signed candidate under test in an independently verified, signed-in dedicated Temporary Chat. After validating the browser process, window, tab, document and real editor, bind `observeNamedUploadError(editor)` from `card-observer.js` to that editor **before** the original Riftlet click. The returned function takes the operation UUID from the resulting dispatch. The collector reads only the verified layout and returns the name of a matched QA file and recognized upload-error text. It creates no input, card, draft, click or network request.

For a positive observation require the original document, a single visible original editor in the original composer container or form, one new card labelled with this operation’s PNG or renamed WebP, an explicit visible upload error and no visible progress indicator on that card. The collector checks existing card and member identities at bind time and checks for competing labels of either suffix across the original layout at observation time. Corroborate it with the original SQLite error. An unrecognized error-card layout, a generic alert or a missing original failure keeps G4 open. During a transport-fault run independently retain the actual one-request fault type and restoration evidence. A page error message does not establish its network cause.

Capture the first SQLite backup after the original error and before the new click. Check the signed app's original-PNG recovery action, its explicit history selection and the new AppKit press. Take a second SQLite backup after the new attachment's START. Use consistent standalone backups of the dedicated QA database. Keep the original operation, asset and private PNG intact.

```sh
python3 -B Tests/PreClickLease/g4/verify_recovery.py \
  /path/to/before/queue.sqlite /path/to/after/queue.sqlite \
  /path/to/original.png ORIGINAL_OPERATION_UUID NEW_OPERATION_UUID
```

For signed build 61, the first explicit reselection commits the schema transition to v7. The default named-error checker above and the neutral-UNKNOWN checker `verify_unknown_recovery.py` accept preselection v4, v5, v6 or v7 and require a postselection v7 with the recovery indexes, triggers and one new predecessor link. They compare the entire original operation, dispatch checkpoint, START and compensation history. A prior input-free retired attempt keeps its number. The next attempt must follow the highest stored attempt for that asset. Use `--legacy-build59` with `verify_recovery.py` only for a historical pre-v7 pair.

Before START, a named error needs the durable dispatch's original failure invocation. After START, the exact attachment ID and profile in the later error must match the preserved positive START. Both paths require the original operation, hash, target, returned invocation and UNKNOWN. In all 17 archived STARTs, the enclosing profile is chatgpt-web-product-system-attached-20261102-v1 and the nested attachmentAcceptanceEvidence profile is chatgpt-web-product-system-start-20261102-v1. The checker validates each role and compares those records across both snapshots and requires one additional operation and invocation for the original PNG on the same document, composer and draft epoch.

The result covers the database and PNG. The acceptance runner must independently establish the actual site-rendered error, the explicit user selection, the browser's single input/change for each operation and zero sends or submits. A fixture result or a missing site observation cannot close G4.

## Inspecting an existing QA archive

Each backup is located at `BACKUP_DIRECTORY/<profile UUID>/queue.sqlite`. The profile parent contains the corresponding `Riftlet-PreClick-QA-<UUID>` directories. Run against closed QA backups and retained media:

```sh
python3 -B Tests/PreClickLease/g4/audit_history.py BACKUP_DIRECTORY QA_PROFILES_PARENT
```

The output includes only counts and SHA-256 hashes of the private backup files. A saved attachment START establishes receipt by the original draft. It does not establish a later error on the same card.
