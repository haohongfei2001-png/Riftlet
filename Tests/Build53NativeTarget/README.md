# Native receiver and SQLite restart check

On an authorized macOS QA machine with Google Chrome and Microsoft Edge installed, build the intended product checkout's RiftletAdapters target in Debug, then supply its Swift build products to this check.

```sh
Tests/Build53NativeTarget/run.sh /absolute/product/checkout /absolute/swift/bin /absolute/new/evidence-directory
```

The runner links the actual Core and Adapters objects and loads their bundled page program. It launches each browser headless with a temporary QA profile, stores a QA PNG and its independent dispatch intent in a fresh QueueStore, terminates the original receiver, and starts a new receiver. It checks kernel birth, the persisted operation and invocation, and the actual trace of a fresh ChromeAppleEventsExecutor when given the old identity. A read-only observation between two refused commits must preserve the same invocation, UNKNOWN row and PNG. The constructed equal-PID/new-birth case and the two observed OS process identities are reported separately.

Each local evidence directory contains the product's structured native trace, a SQLite snapshot, the retained PNG, and a per-browser JSON result. The test samples the headless window through a PID-addressed read that cannot prompt. Only a successfully identified window belonging to the QA child is eligible for a single close. When the headless Apple Event endpoint is unavailable, the synthetic window/tab fields and the reason are explicit in the result. A cached, foreground click-bound route and page setter/input/change/send counts require separate instrumentation. The native result records null DOM counts. It establishes no signed-package or website acceptance.

Close verification captures the original child PID, kernel identity, window and tab before sending a single close. The test then polls that same live receiver's window-ID list for up to four seconds. An uncertain close reply is never retried. The receipt retains the send count, its acknowledgement or error, the last read, the number of polls and the exact phase of an incomplete check. Initial receiver acquisition now follows the first native window read so a newly created profile directory alone cannot establish readiness.

The executor's private write route is installed by a successful foreground `targetForClick` and matching page witness. This headless test deliberately leaves that route unseeded. Closed-window reads in a live receiver and post-restart lookup in the reopened receiver have separate trace entries. The process-birth fixture covers the equal-PID/different-birth collision independently of the actual new process's PID.

The ID list decoder accepts an empty list or unique canonical positive decimal IDs. Missing, nonnumeric, zero, leading-zero and duplicate entries cannot prove a window disappeared. `run.sh --check-window-list PRODUCT_CHECKOUT SWIFT_BIN` checks the decoder without launching a browser.
