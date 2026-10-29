# Built-in capture evidence boundaries

`results.json` records the reviewed source, exact CI runs, failures, corrections and remaining release blockers. A green software job is not physical screenshot acceptance.

## Rejected output path and diagnostic

`capture-path-diagnostic.json` is a metadata-only extract of run [40758912572](https://github.com/haohongfei2001-png/Riftlet/actions/runs/40758912572), diagnostic source `df5d5a0741aa89a36538ccca098d58e16f2f5b80`. On Intel macOS 15.7.9 at 1×, ordinary leaf names in regular or hidden private directories produced the exact PNG; hidden leaf names returned exit 0 with the exact path missing and no entry in that owned directory. This is no evidence of a renamed file elsewhere. The arm64 guard rejected capture before invocation because a foreign window overlapped the fixture. The tested variants were one window and two interior regions, not full display.

## Actual captured synthetic previews

The two PNGs in `synthetic-previews/` came from actual SCScreenshotManager captures in arm64 job `123056435473`, run [40756422188](https://github.com/haohongfei2001-png/Riftlet/actions/runs/40756422188), PR head `b901b5e10a94aa25165d0e020e50931ae8015a77`, merge checkout `d60685f5ce5e8711b039645a8c47c027dbb00e12`, on macOS 15.7.9, one 1024×768 1× display. The fixture contained only synthetic color bands and pixel strips. Every retained pixel passed the tool's strict synthetic allowlist before an sRGB re-encode with no copied source metadata; the encoder-generated EXIF contains only color-space and image-dimension values. `manifest.json` fixes both preview and original-PNG digests.

These are **sanitized actual captures**, not original PNG files, not the production CLI backend, and not evidence for HDR, ICC fidelity, orientation, physical interaction or new-source upload. Intel and nonmatching samples retained no images. Raw screenshots, arbitrary window titles, desktop contents and user data are not included.

The same run exposed a real CLI output failure despite passing software suites. That candidate was rejected and its direct-hidden-leaf layout was replaced. Later CI must be assessed against its own source; these previews do not validate the replacement production publication path.
