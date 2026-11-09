#!/usr/bin/env bash
# Exercise the production meeting recorder/store and acoustic speech gate.
set -euo pipefail
native_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
scratch="$(mktemp -d "${TMPDIR:-${HOME}/Library/Caches/}/meeting-asr-contracts.XXXXXX")"
trap 'rm -rf "$scratch"' EXIT
swiftc -o "$scratch/meeting-asr-contracts" \
  "$native_dir/Sources/OpenVoiceFlow/MeetingRecorder.swift" \
  "$native_dir/Sources/OpenVoiceFlow/MeetingSummarizer.swift" \
  "$native_dir/Sources/OpenVoiceFlow/MeetingSpeechGate.swift" \
  "$native_dir/Sources/OpenVoiceFlow/MeetingStore.swift" \
  "$native_dir/Tests/MeetingASRContracts.swift"
"$scratch/meeting-asr-contracts"
