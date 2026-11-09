#!/usr/bin/env bash
# Compile the production meeting store and recorder with executable disk contracts.
set -euo pipefail

native_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
scratch="$(mktemp -d "${TMPDIR:-${HOME}/Library/Caches/}/meeting-contracts.XXXXXX")"
trap 'rm -rf "$scratch"' EXIT

swiftc -o "$scratch/meeting-contracts" \
  "$native_dir/Sources/OpenVoiceFlow/MeetingRecorder.swift" \
  "$native_dir/Sources/OpenVoiceFlow/MeetingSummarizer.swift" \
  "$native_dir/Sources/OpenVoiceFlow/MeetingSpeechGate.swift" \
  "$native_dir/Sources/OpenVoiceFlow/MeetingStore.swift" \
  "$native_dir/Tests/MeetingContracts.swift"
"$scratch/meeting-contracts"
