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

`chatgpt-web-main-6c677f55.js` is the exact same path at merged main
`6c677f555376e4abcbdfa59e6e9ef1aabb8eadec` (PRs #37 and #38).

SHA-256: `3f28f31208ff3c2786d5628c03ab6467a4ba3c26dfbf3432be724dac1649c457`.

It preserves the empty-native-picker-only implementation for red regressions
and same-document hot upgrade tests. A retained START operation is left in its
original registry; the current program must install its new capability and
qualify that exact original File without replaying it or resetting the page.
The fixture also reproduces the stale inputOwners key when a synchronous change
retires its state. These are controlled code reproductions, not proof that either
predicate uniquely caused the user's Mac incident.
