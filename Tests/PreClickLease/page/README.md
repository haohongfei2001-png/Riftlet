# Pre-click page lease

Run the focused suite against the source asset or the exact page JavaScript extracted from a candidate application. The only browser it opens is a new headless Chrome or Edge child with its own temporary profile and private pipes. The test checks that the process exits before removing that profile.

```sh
node Tests/PreClickLease/page/run.cjs chrome "$PWD/Sources/RiftletAdapters/Resources/chatgpt-web-20261027.js"
node Tests/PreClickLease/page/run.cjs edge "$PWD/Sources/RiftletAdapters/Resources/chatgpt-web-20261027.js"
```

Each run records the input resource hash, browser version, PNG hash, original-target validation, browser-generated pointer-down times, operation IDs, invocation IDs, setter/input/change/submit counts and per-case result. The disposable file fixture uses the repository's controlled route and native-identity arguments and calls the compact shipping pin plus the full capture, validation and operation commands. It tests a trusted click on a fixture button with an already acknowledged lease. The macOS thumbnail, Apple Events, signed app, remote provider card, START and failure recovery have separate acceptance gates.

The pair case requires two byte-distinct PNG deliveries in less than two seconds and hashes both actual File objects returned by the native setter. The foreground-lifetime case waits at least 61 real seconds between acknowledgement and pressing. The other cases cover replacing the file or opener, moving the original file's ancestor away and back, changing a declared mode twice, changing drafts with one editor object, moving a file after staging, an unrelated late file beside a legitimate dynamic menu, a real browser tab round trip, and bounded release. It checks the original text, selection and prior attachment throughout.

The capture command starts a ten-minute unused-lease ceiling before resolving the page. A successful `renewPreparedTarget` command for the same pending target resets that ceiling from the renewal command entry. Elapsed monotonic time and wall time are checked at the begin boundary even when background timers have not run. An enrolled operation retains its separate existing ten-minute observation cleanup. The original pin has a sixty-second orphan watchdog until the exact editor acknowledges the lease. A native owner should start a shorter freeze deadline before sending the prepare command.

The capacity case presses twice while begin is paused, refills the third slot and checks that a fourth prepare is rejected; it then delivers both original files. Separate cases cover missing/ambiguous controls, explicit release from a fresh program instance in the same document, reclaiming stale original objects, and the exact ten-minute boundary with a controlled monotonic/wall clock and scheduler. Only the 61-second stationary case measures real elapsed idle time.

The renewal cases reuse an exact serialized TargetLease from a fresh instance of the same program. They advance the injected clocks to the fourth and eighth minute, renew the original ticket twice, and then deliver once after its original ten-minute deadline. Separate assertions reject a moved file, explicit release, enrollment and an expired ticket even when its timer callback has not run.
