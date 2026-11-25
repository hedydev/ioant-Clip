#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
sources=()
while IFS= read -r path; do sources+=("$path"); done < <(find Sources/ClipCore -name '*.swift' -type f | sort)
for mode in daily review; do
  flags=(-D CLIP_DAILY_REVIEW_TEST)
  if [ "$mode" = review ]; then flags=(-D CLIP_CLOUDKIT_REVIEW); fi
  /usr/bin/swiftc -swift-version 5 "${flags[@]}" "${sources[@]}" App/Features/Library/LibraryLocation.swift App/Features/Sync/Providers/CloudKitRevisionTransport.swift App/Features/Sync/Providers/CloudKitReviewConfiguration.swift scripts/test_cloudkit_review.swift -o "$tmp/$mode" || exit 1
  "$tmp/$mode" || exit 1
done
