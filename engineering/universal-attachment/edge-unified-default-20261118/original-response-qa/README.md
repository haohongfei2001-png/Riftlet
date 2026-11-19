# Original response validation units

This small package contains only deterministic validation code and neutral fixtures. It does not include the native DevTools operator, live observation loop, case configuration, local queue paths, browser identities, HAR, service file IDs, or captured media.

It originated as a portable subset of the v2 QA observer: 91 of the previously run 98 cases. This public QA follow-up retains all 91 and appends 50 boundary cases, for 141 passing cases. Seven tests of the original before/watch file orchestration stay with that private operator package and are not claimed here. `provenance.json` pins the original source files, the original extraction receipt and these subsequent repairs.

| Unit | Responsibility |
| --- | --- |
| `settled.py` | Validate supplied original two-click sender, reservation, operation and trace facts; never reads a database or submits input. |
| `identity.py` | Prioritize an appearing row and reject changed ticket, native context, filename, file ID, missing before/after Payload proof or reused identity. |
| `network_policy.swift` | Accept a zero count only from explicit, consistent count facts; distinguish missing data, filtered totals, read errors and conflicting ownership. |
| `response.swift` | Classify a bounded already-observed UI projection only when the complete known event sequence belongs to the supplied file-ID digest. |

Run the tests with Python 3 and the repository's macOS Swift toolchain:

```sh
python3 -B verify.py
```

The runner compiles a temporary command-line executable using Foundation and CryptoKit, then removes it. It needs no third-party Python packages, AppKit, browser, GUI session, Apple Events, accessibility permission, database, account or network. To retain a new test receipt, use `--output` with a new local JSON filename.

The 55 Python fixtures comprise the original 39 plus 16 operation-identity and filename-boundary cases. The 72 policy fixtures comprise the original 38 plus 34 count/parser and Payload-digest boundary cases. All 14 original response fixtures remain unchanged. The receipt lists every appended case separately.

Independent review found two false acceptances in the extracted QA code: `7 / 0 requests` used only the denominator, and two assets could share one operation UUID when their supplied diagnostics matched that UUID. The follow-up rejects a numerator above its denominator and requires distinct canonical operation UUIDs before a pending sender/trace can return. The count audit also reproduced and rejects a negative header-table count paired with an explicit zero footer. Valid filtered totals, canonical UUIDs and independent filenames remain supported; malformed UUID spellings cannot be concatenated into a filename. Existing Payload-digest code already rejected trailing newlines in the executed regression and was not changed.

These are subsequent repairs to this public QA package. The private live observer and the original acceptance artifacts remain unchanged. In particular, these fixtures do not reinterpret the recorded 636/637 observation failure, supply absent response bodies, or upgrade either processing result from UNKNOWN.

These units validate supplied observations. They cannot prove that an external UI observation actually occurred, recover absent response data, establish native click reliability or admit product completion. In particular, a UI projection is not a raw SSE/NDJSON transport entity. HTTP 200, PUT 201 and a declared body length do not substitute for an original processing terminal.

Maintenance is limited to three schemas: the existing two-click diagnostic facts, the closed UI identity projection and the known processing-event sequence. All external effects stay outside these units. The schemas are intentionally strict; changes should add narrowly justified fixtures rather than widen unknown data into success. The Swift files fit the repository's existing macOS CI; Foundation/CryptoKit availability is the only native build dependency.
