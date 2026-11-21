# Whole-window close and process restart

Chrome 157.0.8103.79 and Edge 157.0.4341.60 exercised the build 53 page resource and the build 54 source resource from commit `95d8cf80` on 2026-11-21. Both cases passed for each resource in each browser. The existing thirteen-case suites have separate receipts.

| Operation | Identity and outcome observed in both engines |
| --- | --- |
| Close the entire original QA window | Two independent headless browser windows received distinct Chromium window IDs. A staged operation held a live witness in the original window. Closing its only tab destroyed the entire window. A bounds query for that window returned “Browser window not found” and its original session rejected the commit. The surviving witness window read an explicitly initialized, nonce-bound ledger with setter/input/change/send counts of 0/0/0/0. |
| Restart the whole browser | The first browser exited normally and its entire owned process group was checked before relaunch. The replacement process had a different actual PID. The same isolated profile and URL restored the ledger nonce and original counters. The new document had a different instance. Given the *exact old serialized operation and the same original native identity arguments*, the product's read reported invalidated and its commit returned ORIGINAL_OPERATION_REQUIRED. All four counters remained zero. |

This is a real process restart with a controlled collision of **page-program arguments**. The operating system did not reuse the PID in these runs. The window IDs come from Chromium's own window management API in headless mode. Kernel process-birth checks, production Apple Events/SQLite admission, installed-app behavior and signed-in website acceptance have separate evidence.

The runner uses private inherited child pipes, a rejecting loopback proxy and a fresh temporary profile per browser. It retains the profile only between the two process lifetimes within its own test. The loopback origin stays alive during the restart. Cleanup verifies the owned process group and removes its profile.

## Run

```sh
node Tests/Build53TargetSafety/run-host-lifetime.cjs
```

To test a different product resource, supply its absolute path and pinned digest. Pass `chrome` or `edge` as a positional argument to limit the run to one browser.

```sh
RIFTLET_SAFETY_ASSET_PATH=/absolute/path/to/chatgpt-web-20261027.js \
RIFTLET_SAFETY_EXPECT_SHA256=9b9a1ecd12b8433c7a9243ebedb72fefcc7dc8d69fd2602e4caf895c89b7ab36 \
node Tests/Build53TargetSafety/run-host-lifetime.cjs
```

The [build 53 source results](build53-host-lifetime.json) and [build 54 source results](build54-source-host-lifetime.json) retain browser versions, source digests, exact refusals, counter totals and timestamps. These source receipts were captured before any signed-build-54-package run.
