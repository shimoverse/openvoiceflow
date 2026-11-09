#!/usr/bin/env bash
# Compile and exercise the real native MeetingsView with isolated sanitized records.
set -euo pipefail
native_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
scratch="${MEETING_NOTES_QA_SCRATCH:-$HOME/.hermes/cache/scratch}"
mkdir -p "$scratch"
artifacts="${1:-$(mktemp -d "$scratch/meeting-notes-ui.XXXXXX")}"
mkdir -p "$artifacts"
artifacts="$(cd "$artifacts" && pwd)"
case "$artifacts" in "$scratch"/*) ;; *) echo 'Artifact directory must be inside isolated scratch' >&2; exit 2;; esac
bundle="$artifacts/MeetingNotesUIFixture.app"
mkdir -p "$bundle/Contents/MacOS"
python3 -c 'import plistlib,sys; plistlib.dump({"CFBundleIdentifier":"org.openvoiceflow.qa.meeting-notes-rendered", "CFBundleExecutable":"MeetingNotesUIFixture", "CFBundleName":"MeetingNotesUIFixture", "CFBundlePackageType":"APPL", "LSUIElement":False},open(sys.argv[1],"wb"))' "$bundle/Contents/Info.plist"
sources=("$native_dir/Sources/OpenVoiceFlow/MeetingRecorder.swift"
 "$native_dir/Sources/OpenVoiceFlow/MeetingSummarizer.swift"
 "$native_dir/Sources/OpenVoiceFlow/MeetingSpeechGate.swift"
 "$native_dir/Sources/OpenVoiceFlow/MeetingStore.swift"
 "$native_dir/Sources/OpenVoiceFlow/MeetingNotesPresentation.swift"
 "$native_dir/Sources/OpenVoiceFlow/DesignTokens.swift"
 "$native_dir/Sources/OpenVoiceFlow/MeetingsView.swift"
 "$native_dir/Tests/MeetingNotesUIFixture.swift")
swiftc -O -parse-as-library -o "$bundle/Contents/MacOS/MeetingNotesUIFixture" "${sources[@]}" 2>&1 | tee "$artifacts/compile.log"
echo "Fixture bundle: $bundle"
if [[ -z "${CUA_DRIVER_SOCKET:-}" ]]; then
  export CUA_DRIVER_SOCKET="$artifacts/cua-driver.sock"
  cua-driver serve --socket "$CUA_DRIVER_SOCKET" --no-overlay >"$artifacts/cua-driver.log" 2>&1 &
  driver_pid=$!
  trap 'kill "$driver_pid" 2>/dev/null || true' EXIT
  for _ in {1..40}; do
    if cua-driver call list_windows '{"pid":1}' --socket "$CUA_DRIVER_SOCKET" >/dev/null 2>&1; then break; fi
    sleep 0.25
  done
fi
swiftc -O -o "$artifacts/meeting-clipboard-guard" "$native_dir/Tests/MeetingClipboardGuard.swift" 2>&1 | tee "$artifacts/clipboard-compile.log"
swiftc -O -o "$artifacts/meeting-notes-ocr" "$native_dir/Tests/MeetingNotesRenderedOCR.swift" 2>&1 | tee "$artifacts/ocr-compile.log"
if [[ "${MEETING_NOTES_UI_REGEN_ONLY:-0}" != 1 ]]; then
  MEETING_NOTES_QA_SCRATCH="$scratch" "$artifacts/meeting-clipboard-guard" "$native_dir/Tests/meeting_notes_ui.py" "$artifacts" 2>&1 | tee "$artifacts/run.log"
fi
MEETING_NOTES_QA_SCRATCH="$scratch" "$artifacts/meeting-clipboard-guard" "$native_dir/Tests/meeting_notes_regeneration_ui.py" "$artifacts" 2>&1 | tee "$artifacts/regeneration-run.log"
