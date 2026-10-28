#!/bin/bash
# Read-only composition audit. The event base may lag GitHub's actual merge.
set -euo pipefail
reported_base="${FEEDBACK_BASE_SHA:?Missing event base SHA}"
head="${FEEDBACK_HEAD_SHA:?Missing pull request head SHA}"
for revision in "$reported_base" "$head"; do
  [[ "$revision" =~ ^[0-9a-f]{40}$ ]] || { echo 'Invalid commit identity' >&2; exit 1; }
  git cat-file -e "$revision^{commit}"
done
read -r -a parents <<< "$(git show -s --format='%P' HEAD)"
[[ "${#parents[@]}" == 2 && "${parents[1]}" == "$head" ]] || {
  echo 'Expected an exact two-parent PR test merge with this feature head' >&2; exit 1;
}
base="${parents[0]}"
# Do not accept an unrelated target or a rewritten history as a newer base.
git merge-base --is-ancestor "$reported_base" "$base"
git merge-base --is-ancestor "$base" refs/remotes/origin/codex/engineering-foundation-20261027
mkdir -p feedback-results
{
  printf 'event_base=%s\nbase=%s\nhead=%s\ncheckout=%s\n' "$reported_base" "$base" "$head" "$(git rev-parse HEAD)"
  git show -s --format='parents=%P' HEAD
} | tee feedback-results/composition.txt
# Exact protected blobs compare to the actual merge parent, not stale metadata.
git diff --exit-code "$base" HEAD -- \
  Sources/RiftletCore Sources/RiftletCapture Sources/RiftletUI Sources/RiftletAdapters \
  Sources/RiftletGUIAcceptance Resources ThirdPartyNotices Tests/RiftletCoreTests \
  Tests/RiftletCaptureTests Tests/RiftletUITests Tests/RiftletAdaptersTests \
  Tests/RiftletAppTests Tests/WebPageProgram
git diff --exit-code "$head" HEAD -- \
  Sources/RiftletFeedback Sources/RiftletFeedbackUI Sources/RiftletFeedbackDemo \
  Sources/RiftletApp/FeedbackHost.swift Tests/RiftletFeedbackTests \
  Tests/RiftletFeedbackUITests services/feedback Package.swift
git diff "$base" HEAD -- Sources/RiftletApp/RiftletMain.swift > feedback-results/host-integration.patch
printf '%s\n' 'FEEDBACK_COMPOSITION_ISOLATION_PASS; protected screenshot blobs unchanged from actual base' | tee -a feedback-results/composition.txt
