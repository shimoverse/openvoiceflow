#!/bin/bash
set -euo pipefail

ROOT="${SRCROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
DEST="$ROOT/BuildResources/Models/ggml-base.en.bin"
LOCAL_SOURCE="${OPENVOICEFLOW_MODEL_SOURCE:-$HOME/.openvoiceflow/models/ggml-base.en.bin}"
URL="https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.en.bin"
SHA256="a03779c86df3323075f5e796cb2ce5029f00ec8869eee3fdfb897afe36c6d002"
EXPECTED_BYTES=147964211

verify_model() {
    local file="$1"
    [[ -f "$file" ]] || return 1
    [[ "$(stat -f %z "$file")" == "$EXPECTED_BYTES" ]] || return 1
    [[ "$(shasum -a 256 "$file" | cut -d ' ' -f 1)" == "$SHA256" ]]
}

mkdir -p "$(dirname "$DEST")"
if verify_model "$DEST"; then
    echo "Verified bundled Whisper model: $DEST"
    exit 0
fi
rm -f "$DEST" "$DEST.download"

if verify_model "$LOCAL_SOURCE"; then
    cp "$LOCAL_SOURCE" "$DEST"
else
    echo "Downloading pinned Whisper model data..."
    curl -fL --retry 3 --progress-bar -o "$DEST.download" "$URL"
    mv "$DEST.download" "$DEST"
fi

if ! verify_model "$DEST"; then
    rm -f "$DEST"
    echo "error: Whisper model failed size/SHA-256 verification" >&2
    exit 1
fi

echo "Prepared checksum-verified model at BuildResources/Models/ggml-base.en.bin"
