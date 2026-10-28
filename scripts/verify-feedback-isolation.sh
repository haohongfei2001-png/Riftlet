#!/bin/bash
# Read-only composition audit for the Feedback packet's actual CI checkout.
# Never changes refs, production policy, screenshot databases or user files.
set -euo pipefail
base="${FEEDBACK_BASE_SHA:?Missing pull request base SHA}"
head="${FEEDBACK_HEAD_SHA:?Missing pull request head SHA}"
for revision in "$base" "$head"; do
  [[ "$revision" =~ ^[0-9a-f]{40}$ ]] || { echo 'Invalid commit identity' >&2; exit 1; }
  git cat-file -e "$revision^{commit}"
done
git merge-base --is-ancestor "$base" HEAD
git merge-base --is-ancestor "$head" HEAD
mkdir -p feedback-results
{
  printf 'base=%s\nhead=%s\ncheckout=%s\n' "$base" "$head" "$(git rev-parse HEAD)"
  git show -s --format='parents=%P' HEAD
} | tee feedback-results/composition.txt
# These belong to the screenshot team. Their exact Git blobs in the combined
# checkout must match the current target branch, not our older feature baseline.
git diff --exit-code "$base" HEAD -- \
  Sources/RiftletCore Sources/RiftletCapture Sources/RiftletUI Sources/RiftletAdapters \
  Sources/RiftletGUIAcceptance Resources ThirdPartyNotices Tests/RiftletCoreTests \
  Tests/RiftletCaptureTests Tests/RiftletUITests Tests/RiftletAdaptersTests \
  Tests/RiftletAppTests Tests/WebPageProgram
# Feedback implementation must also be exactly the submitted feature source.
git diff --exit-code "$head" HEAD -- \
  Sources/RiftletFeedback Sources/RiftletFeedbackUI Sources/RiftletFeedbackDemo \
  Sources/RiftletApp/FeedbackHost.swift Tests/RiftletFeedbackTests \
  Tests/RiftletFeedbackUITests services/feedback Package.swift
# The shared App diff is an explicit review artifact, not an inferred guarantee.
git diff "$base" HEAD -- Sources/RiftletApp/RiftletMain.swift > feedback-results/host-integration.patch
printf '%s\n' 'FEEDBACK_COMPOSITION_ISOLATION_PASS; protected screenshot blobs unchanged from recorded base' | tee -a feedback-results/composition.txt
