#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ARCHIVE_PATH="${OPENVOICEFLOW_ARCHIVE_PATH:-$ROOT/.archives/OpenVoiceFlow.xcarchive}"

cd "$ROOT"
"$ROOT/Scripts/prepare-model.sh"
xcodegen generate --spec "$ROOT/project.yml"

# This command intentionally leaves signing to Xcode's configured Apple team.
# It will stop with an actionable provisioning/certificate error when the
# Mac App Distribution profile is not available; no credentials are stored here.
xcodebuild \
  -project "$ROOT/OpenVoiceFlowStore.xcodeproj" \
  -scheme OpenVoiceFlowStore \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  -archivePath "$ARCHIVE_PATH" \
  -allowProvisioningUpdates \
  archive

echo "Archive: $ARCHIVE_PATH"
