# 5a997969 native magnet observation

This is an implementation-author diagnosis, not independent visual approval. Source and checkout: `5a9979693ac1bb28fa898d23c60bc791c2c7ec4d`; push Native run `40762471599` failed its normal visual semantic gate. Original artifact ZIP and all original PNG/MOV/manifests are preserved.

## Observed facts

- Actual NSWorkspace state was normal: Reduce Motion false, Increase Contrast false, Reduce Transparency false, at both capture start and end. No helper reduction override was requested.
- `synthetic_asset_ready` has `sourceProvided=true`, ready uptime 399.469420625. `decorationStarted` was magnet at 399.502189083. `decorationEnded` was `timedOut` at 400.134096875. There was no observed `finished` event.
- The product plan is 0.560 seconds. Cleanup occurred approximately 0.665 seconds after asset readiness, consistent with the existing duration plus 0.100-second safety timeout. The timeout was not relabeled as natural completion.
- `capture.json` contains sixteen original keyframes and a real 135-frame MOV with actual monotonic timestamps. The driver excluded that failed scene from its accepted total; its summary therefore has 102 accepted PNG and four accepted movies, rather than claiming the fifth completed normally.
- Actual original frame-02, frame-05, frame-06, frame-07 and frame-08 show a nonempty decoration at the source, an image travelling toward the rift, and the final slot. This is sufficient to distinguish the failure from the earlier blank-backdrop capture bug. It does not prove natural completion or a final aesthetic verdict.
- The next synthetic swallow was scheduled for 0.12 seconds and emitted `swallowClose`. This does not grant a real upload receipt.

## Limits and likely contributors

The exporter calls WindowServer capture and performs PNG encoding plus a full original-pixel backdrop comparison on MainActor. During the magnet interval the native capture calls themselves took about 0.5–1.2 ms, but measured gaps between sampled movie frames reached 101.8 ms. That gap includes capture/encoding/scheduling overhead and is not an application performance benchmark. It is enough to make an extra main-queue callback hop compete with the product's 100-ms completion grace.

`MagnetAnimationEnd.animationDidStop` unconditionally dispatches its completion to the main queue. The safety timeout also queues its completion. Current evidence records the winning product completion, not the raw CA delegate arrival and its `finished` flag. Therefore it cannot distinguish an undelivered render-server completion from a delegate/main-queue ordering race. A pure product animation defect and observation-induced delay cannot be separated from this run alone.

Apple documents `animationDidStop(_:finished:)` as reporting natural end only when its flag is true; removal can also trigger the delegate. A CATransaction completion block also fires after removal, so substituting such a block without generation/cancellation guards would weaken the meaning. Apple also recommends allowing implicit transaction flushing through the normal run loop instead of gratuitous explicit `flush()` calls.

Primary references:

- https://developer.apple.com/documentation/quartzcore/caanimationdelegate/animationdidstop(_:finished:)
- https://developer.apple.com/documentation/quartzcore/catransaction/setcompletionblock(_:)
- https://developer.apple.com/documentation/quartzcore/catransaction/flush()

## Minimal next step

Keep `magnetCompletionNotObserved` as a failure and preserve the driver requirement for a true natural completion. Add bounded diagnostic observation of raw CA delegate start/stop time, `finished` flag, and cleanup timing, with no queue/store/upload action. If the callback already arrives on the main thread, avoiding an unnecessary extra dispatch hop is a small candidate change for non-author review; if it arrives late, the main-thread observation workload should be reduced before changing product timing. Do not increase the animation duration, accept `timedOut` as `finished`, or hide this run by rerunning without explanation.

No product or driver guard was changed during this diagnosis.
