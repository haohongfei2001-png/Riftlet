# Controlled product recovery fixture

Stage a fresh local copy from the checkout under test. The command prints the SHA-256 of the shipping page resource embedded in `shipping-adapter.js`.

```sh
node Tests/ProductRecoveryAcceptance/Fixture/bridge.cjs /private/tmp/riftlet-recovery-example-new
node --test Tests/WebPageProgram/explicit-recovery-fixture.test.cjs
```

Open the staged `index.html` in the controlled test host. The authored file contains a nonempty composer, a noncollapsed selection, and a previous attachment. Its content security policy disables connections and form submission. The bridge supplies a fixture-local logical route so the production page adapter runs its ordinary binding, input and observation code on these elements. Host process/window identifiers come from the test host. A file-page run covers the controlled adapter and cannot establish a signed-in website result.

The native fixture host invokes `window.recoveryFixture.command(command, native)` with the adapter's serialized commands. Use `snapshot()` before and after each action to read the independent page counters, original nodes, selection offsets, full File SHA-256, per-operation card state and ordered events. The command returns the native adapter result, including any original Promise. The page receives actual `input` and `change`; its counter forwards every file setter invocation to the original browser setter. The file name supplied by the adapter carries the operation UUID. Its page record survives a disappearance or failure and detects any reuse of that UUID.

| Fixture action | Controlled page behavior |
| --- | --- |
| `setNext('preview')` | The next change immediately renders that File's named Blob preview. |
| `setNext('pre-input-failure')` | The page disables its original input at commit. Call `setNext('preview')` before the next independent click to restore availability. |
| `setNext('pending')` | The page renders a progress control. `transition(id, 'preview')` later exposes the original File preview for observation. |
| `setNext('silent')` | The page registers the File and change without drawing any card. |
| `transition(id, 'ambiguous')` | The existing preview stays visible and its surface reports a generic error. |
| `transition(id, 'failed')` | The original card renders a named alert and retry button. The fixture never presses it. |
| `transition(id, 'unknown')` | The original card disappears. The page retains its input record. |
| `navigate()` | A distinct editor and draft replace the original, changing the logical route. |

The headless tests use fresh profiles and file pages with the installed macOS Chrome and Edge executables. A simulated one-hour clock advances the actual product retirement callbacks while leaving the original DOM alive; the separate ABA control changes the declared draft and restores its previous value. These controls exercise page identity and replay protection. Durable operation rows and native mouse events require the separate native host.
