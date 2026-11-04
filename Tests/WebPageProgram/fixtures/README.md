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

`chatgpt-web-main-1cd7bc90.js` is the exact same path at merged main
`1cd7bc9054b07ce6648a9f8bb42b2425b2c8aaad` (PR #39).

SHA-256: `88bd99b9415c7c668fa7023874507e6e7abf9768186a11b5ca710d5e1fd59d32`.

The P1 regression executes this unchanged source to reproduce the collapsed
route/frame/visibility/focus refusal, Home query and candidate Project route
rejections, and a captured-target → Window blur → native press refusal. The
current source must distinguish those predicates and accept only the exact
continuously observed target when a native pre-press receipt proves the same
foreground browser route. Candidate Project paths use controlled existing Chat
composer profiles; they do not establish the live Project route or DOM shape.
No private URL, conversation ID, content, screenshot or production database is
included. These executable counterexamples establish former code behavior, not
which predicate caused the user's previously indistinguishable log entry.
