#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DERIVED_DATA="${OPENVOICEFLOW_DERIVED_DATA:-$ROOT/.derived-data}"

cd "$ROOT"
"$ROOT/Scripts/prepare-model.sh"
xcodegen generate --spec "$ROOT/project.yml"
xcodebuild \
  -project "$ROOT/OpenVoiceFlowStore.xcodeproj" \
  -scheme OpenVoiceFlowStore \
  -configuration Release \
  -derivedDataPath "$DERIVED_DATA" \
  CODE_SIGNING_ALLOWED=NO \
  build

echo "Built: $DERIVED_DATA/Build/Products/Release/OpenVoiceFlow.app"
