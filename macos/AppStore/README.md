# OpenVoiceFlow — Mac App Store target

This directory contains a separate, native Mac App Store edition of OpenVoiceFlow. It does not replace or alter the Python/rumps direct-download edition built by `build-dmg.sh`.

## Store-safe product differences

- Native Swift/AppKit/SwiftUI executable; no runtime shell bootstrap, Homebrew, Python, venv, or pip.
- Official `whisper.cpp` v1.9.1 XCFramework linked at build time.
- Checksum-verified `ggml-base.en` model bundled as app data.
- App Sandbox with microphone access only.
- Control+Option+Space is the push-to-talk shortcut. Modifier-only Right Command requires low-level input monitoring and remains exclusive to the direct edition.
- Transcriptions are copied to the clipboard. Automatic cross-app Cmd+V injection remains exclusive to the direct edition because broad Accessibility/event injection is a Mac App Store review risk.
- Initial Store edition performs raw local transcription only; it makes no network requests at runtime.

## Generate and build

Requirements: Xcode 26+, XcodeGen, and internet access the first time SwiftPM resolves the pinned whisper XCFramework. The model script prefers a previously verified `~/.openvoiceflow/models/ggml-base.en.bin` and otherwise downloads the exact pinned model data.

```bash
cd macos/AppStore
./Scripts/build-release.sh
```

The unsigned local verification artifact is written to:

```text
.derived-data/Build/Products/Release/OpenVoiceFlow.app
```

## Test

```bash
./Scripts/prepare-model.sh
xcodegen generate --spec project.yml
xcodebuild -project OpenVoiceFlowStore.xcodeproj \
  -scheme OpenVoiceFlowStore \
  -derivedDataPath .derived-data \
  CODE_SIGNING_ALLOWED=NO test
```

## App Store archive

A real App Store archive requires an active Mac App Distribution/Apple Distribution identity, a matching Mac App Store provisioning profile for `com.shimoverse.openvoiceflow`, and an App Store Connect app record. Do not submit until every item in `Metadata/submission-checklist.md` has been read back from Apple.
