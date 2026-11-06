#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT
swiftc -o "$scratch/update-check-contracts" \
  "$root/Sources/OpenVoiceFlow/UpdateCheckStatus.swift" \
  "$root/Tests/UpdateCheckStatusContracts.swift"
"$scratch/update-check-contracts"
