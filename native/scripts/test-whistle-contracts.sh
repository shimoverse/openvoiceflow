#!/usr/bin/env bash
# Compile the production engine with its executable, non-network Swift contracts.
set -euo pipefail

native_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [[ $# -ne 0 && ( $# -ne 2 || $1 != --fixture ) ]]; then
  printf 'usage: %s [--fixture /path/to/verified-assets]\n' "$0" >&2
  exit 2
fi
if [[ $# -eq 2 && ! -d $2 ]]; then
  printf 'fixture directory does not exist: %s\n' "$2" >&2
  exit 2
fi

scratch="$(mktemp -d "${TMPDIR:-${HOME}/Library/Caches/}/whistle-contracts.XXXXXX")"
trap 'rm -rf "$scratch"' EXIT
swiftc -o "$scratch/whistle-contracts" \
  "$native_dir/Sources/OpenVoiceFlow/WhistleEngine.swift" \
  "$native_dir/Tests/WhistleContracts.swift"
# The default gate must never fetch model assets or depend on local fixtures.
env -u WHISTLE_DOWNLOAD_TEST -u WHISTLE_FIXTURE_DIR "$scratch/whistle-contracts" --probe-early-eof
env -u WHISTLE_DOWNLOAD_TEST -u WHISTLE_FIXTURE_DIR "$scratch/whistle-contracts" --probe-double-cancel
if [[ $# -eq 2 ]]; then
  env -u WHISTLE_DOWNLOAD_TEST WHISTLE_FIXTURE_DIR="$2" "$scratch/whistle-contracts"
else
  env -u WHISTLE_DOWNLOAD_TEST -u WHISTLE_FIXTURE_DIR "$scratch/whistle-contracts"
fi
