# C1 passive expiry metadata

The existing passive sampler records a hash of its allocated upload URL. Its historical receipts give no expiration time. This optional QA projection reads the declared Azure Blob expiry only inside the sampler's existing, same-file create-response callback. It adds no network hook, request, delay or timer. It never reads signature or header values and retains no URL or reference to the parsed URL. The original sampler still uses its temporary URL for its existing in-memory equality check and releases it at teardown.

The recognized schema is an HTTPS public Azure Blob storage account, one blob resource marker, one ISO-format storage service version and one explicit UTC `se` value. The parser accepts whole seconds and up to seven fractional digits and rejects malformed dates, multiple values and conflicting expiry parameters. Custom domains and unfamiliar encodings have no result. The timestamp describes the allocation's declared expiry. It does not establish what a server would do. [Microsoft's service SAS field definition](https://learn.microsoft.com/en-us/rest/api/storageservices/create-service-sas)

Build the static QA module into a new private file. The composer verifies the source SHA-256 against the public regular-PNG sampler or its reviewed 20–30 MiB variant. It refuses to overwrite a file.

```sh
node Tests/PreClickLease/g4/expiry-observation/compose.cjs \
  Tests/PreClickLease/g4/network/calibrate.js /path/to/new-private-passive.js
node --test Tests/PreClickLease/g4/expiry-observation/*.test.cjs
```

Use only the existing approved passive host on its exact disposable QA tab. Pin the newly composed bytes independently before arming. A regular image uses the regular sampler, with the original size guard. All original route, selection, original-file and full-byte checks stay active. No private host or running observer is changed by this source. The final normal-transfer receipt can include `declaredExpiry` with exactly the schema name, UTC timestamp and three SHA-256 digests for operation, original PNG and allocated URL. The host must independently check operation and PNG against the signed App/SQLite and check the URL digest against the same passive byte receipt.

Unfinished samples emit no field. A finished sample returns null unless there is exactly one attributed create and PUT, the actual original File, a matching full payload hash and a successful HTTP response. A prior completed upload supplies metadata only. This observer cannot reserve a pending request, prove a 4xx by waiting, or supply G4-A, G4-B or G4-C acceptance.

The local VM cases check the five-field projection, full precision, redaction, absence on partial/foreign/ambiguous traces, refusal to build over changed source, and the original sampler regressions. They neither contact Azure nor control any browser.
