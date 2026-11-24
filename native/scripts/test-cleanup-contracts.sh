#!/usr/bin/env bash
# Exercise production cleanup over an offline URLProtocol transport.
set -euo pipefail
native_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
scratch="$(mktemp -d "${TMPDIR:-${HOME}/Library/Caches/}/cleanup-contracts.XXXXXX")"
trap 'rm -rf "$scratch"' EXIT
swiftc -o "$scratch/cleanup-contracts" \
  "$native_dir/Sources/OpenVoiceFlow/HotkeyEngine.swift" \
  "$native_dir/Sources/OpenVoiceFlow/Settings.swift" \
  "$native_dir/Sources/OpenVoiceFlow/CleanupProvider.swift" \
  "$native_dir/Tests/CleanupContracts.swift"
"$scratch/cleanup-contracts"
