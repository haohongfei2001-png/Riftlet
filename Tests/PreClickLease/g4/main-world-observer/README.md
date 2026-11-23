# Local document ownership controls

Run from the repository root on macOS with the installed ordinary Google Chrome and Microsoft Edge applications.

```sh
node Tests/PreClickLease/g4/main-world-observer/run.cjs
```

The command accepts no parameters. It launches each browser headless in a new temporary profile over an inherited private pipe. It opens only the fixed local fixture file and its own initial blank tab. The local page's content policy denies network connections, frames and forms. The target's HTTP request counter and upload counter both remained zero. Each browser process group exited and its profile was removed.

| Recorded property | Chrome 157.0.8103.79 | Edge 158.0.4370.33 |
| --- | --- | --- |
| Default / DevTools isolated execution context | 2 / 3 | 2 / 3 |
| Shared DOM backend node, read in each context | 3 / 3 | 3 / 3 |
| Fixed local link's console event context | 2 | 2 |
| New backend node after reload | 5 | 6 |
| Stale isolated context after reload | Rejected | Rejected |

These numbers identify objects only within each disposable tab. Each context wrote a fresh local data attribute to the shared DOM and read the other context's attribute. Own properties on the DOM wrapper, the page's private global state and an inert test property on the XHR prototype were visible only in their originating context. Each context constructed two native XMLHttpRequest instances and verified they remained distinct and unopened. An instance-specific property on the first instance never appeared on the second.

A native-style click activated the local document's existing fixed read-only script link. The browser attributed its one console event to the original default context. The document, node and both sets of XHR references were checked again afterward. Replacing the fixture's own inert prototype mark made its old nonce check fail in the default context while the isolated fixture retained its original mark. Reloading the fixed file yielded a different document loader, nonce and backend node.

The test read descriptors for `window.fetch` and `XMLHttpRequest.prototype.open`, `send` and `abort`. In all four browser/context combinations they were writable and configurable data properties. Their observed references remained equal throughout the test. Later code could change them. Neither the fixture nor the driver invokes, wraps or replaces any of these methods.

The isolation tested here is Chromium's documented DevTools isolated context created for one frame. macOS AppleScript execution, browser-extension worlds, authenticated pages and production request ownership remain outside this result. [Results and exact source hashes](receipt.json)
