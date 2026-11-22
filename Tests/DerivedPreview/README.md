# Derived PNG attachment receipts

Run the page resource through a private headless browser using its absolute path.

```sh
node Tests/DerivedPreview/run.cjs chrome "$PWD/Sources/RiftletAdapters/Resources/chatgpt-web-20261027.js"
node Tests/DerivedPreview/run.cjs edge "$PWD/Sources/RiftletAdapters/Resources/chatgpt-web-20261027.js"
```

The optional `--baseline58` argument requires the build 58 page SHA and checks that both fully decoded replacement cards remain unconfirmed after input. It does not admit build 58.

The runner opens a temporary browser profile over private pipes. The harness uses the existing fixture convention to supply a controlled route and native identifiers. Each input uses the shipping pin, capture, validate, begin, chunk, commit and observation commands. It records the original file receipt and checks that repeated commit is refused. These results cover actual DOM layout, browser file handling and pixel decoding on a fixture. Separate evidence is required for a signed application, logged-in website or physical click.

Two distinct original PNGs contain partially transparent pixels and a legal ancillary metadata chunk. The card’s `.webp` display name preserves the original operation UUID, while the decoded preview contains differently encoded PNG bytes. The fixture checks every decoded pixel independently, including all alpha values. The positive pair requires two distinct attachments, two original operations, a single input per image, the prior text, selection and attachment, and zero sends.

The cases include other files sharing the exact bytes, near names, mismatched MIME declarations, single-pixel and alpha changes, reused original components, a foreign draft, competing labels or failed members, and changes while the original receipt is pending. The decoder-bound replacement case waits for the real browser decoder to finish and holds its result until the competing DOM replacement occurs.
