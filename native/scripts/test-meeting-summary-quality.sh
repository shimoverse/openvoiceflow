#!/usr/bin/env bash
set -euo pipefail
native_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
scratch="$(mktemp -d "${TMPDIR:-${HOME}/Library/Caches/}/meeting-summary.XXXXXX")"
trap 'rm -rf "$scratch"' EXIT
swiftc -o "$scratch/contracts" \
  "$native_dir/Sources/OpenVoiceFlow/MeetingSummarizer.swift" \
  "$native_dir/Tests/MeetingSummaryQualityContracts.swift"
"$scratch/contracts"
