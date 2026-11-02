# Prior page observer fixture

`chatgpt-web-g3-461e645.js` is the exact page resource from source commit
`461e6455b8fc7a5d4ff78dd08124433c0d3b1381`, path
`Sources/RiftletAdapters/Resources/chatgpt-web-20261027.js`.

SHA-256: `c6fe1036ba3cdc5363d9154b0a83e7807a5c19a522af47f29eb9fe165540b7e2`.

The current VM regression first installs this historical observer in the same
document, then evaluates the new program. It verifies that a new capture gets
the new proof-capable state, old operations retain their old read-only facts,
and a stale pin cannot dispatch another input through an obsolete closure.
This is a synthetic compatibility fixture, not new real-page evidence.
