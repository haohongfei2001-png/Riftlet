# Original response validation units

This small package contains only deterministic validation code and neutral fixtures. It does not include the native DevTools operator, live observation loop, case configuration, local queue paths, browser identities, HAR, service file IDs, or captured media.

It is a portable subset of the v2 QA observer: 91 of the previously run 98 cases. All 91 were rerun against these extracted files. Seven tests of the original before/watch file orchestration stay with that private operator package and are not claimed here. `provenance.json` pins the original source files and describes the extraction.

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

The 39 Python fixtures cover original input settlement, independent files, scheduling and identity rejection. The 38 policy fixtures cover explicit zero versus unavailable/contradictory counts and matching Payload identity. The 14 response fixtures cover complete matching events, wrong file, partial/missing terminal, duplicate/conflicting fields and invalid progress.

These units validate supplied observations. They cannot prove that an external UI observation actually occurred, recover absent response data, establish native click reliability or admit product completion. In particular, a UI projection is not a raw SSE/NDJSON transport entity. HTTP 200, PUT 201 and a declared body length do not substitute for an original processing terminal.

Maintenance is limited to three schemas: the existing two-click diagnostic facts, the closed UI identity projection and the known processing-event sequence. All external effects stay outside these units. The schemas are intentionally strict; changes should add narrowly justified fixtures rather than widen unknown data into success. The Swift files fit the repository's existing macOS CI; Foundation/CryptoKit availability is the only native build dependency.
