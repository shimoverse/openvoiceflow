# Build runbook — OpenVoiceFlow native (for a Mac-equipped agent/dev)

This scaffold was authored on Linux and has **never been compiled**. Your job:
get it building on a Mac, iterate the first working slice to a signed,
notarized `.app`, then extend it toward feature parity. Expect to fix real
compile errors — treat the scaffold as a strong first draft, not gospel.

Prereqs: macOS 14+, Xcode 15+ (or the matching Command Line Tools), an Apple
Developer ID (for signing/notarization), `git`.

## Phase 0 — compile the core loop

```bash
cd native
swift build            # resolves WhisperKit + Sparkle, compiles Sources/
```

Fix what the compiler flags. Likely first-pass issues to expect and resolve:
- **WhisperKit API drift.** Pin an actual released tag (`swift package
  resolve` then check `Package.resolved`); adjust `WhisperKitConfig` /
  `DecodingOptions` / `transcribe(audioArray:)` to that version's signatures
  in `Transcriber.swift`.
- **Sparkle wiring.** Sparkle needs an `SPUStandardUpdaterController` and the
  `SUFeedURL`/`SUPublicEDKey` in Info.plist; it's declared as a dependency but
  not yet instantiated — add the updater to `OpenVoiceFlowApp` when you host an
  appcast (can be deferred; remove the dependency to build without it first).
- **`MenuBarExtra` label** with a dynamic SF Symbol may need `.menuBarExtraStyle`.

Then run it headless to sanity-check the loop:
```bash
swift run        # grant Accessibility/Input Monitoring/Mic when prompted
```

## Phase 1 — wrap into a proper `.app` (Xcode)

A menu-bar app needs an Info.plist, entitlements, and code signing, so move to
an Xcode app target (keep it building the same `Sources/`):

1. Create a macOS App target "OpenVoiceFlow" (SwiftUI lifecycle, LSUIElement).
2. Add the local package (or the two remote packages) as dependencies.
3. Set the target's Info.plist from [`Info.plist`](Info.plist) and code-signing
   entitlements from [`OpenVoiceFlow.entitlements`](OpenVoiceFlow.entitlements).
4. Enable **Hardened Runtime**. Do NOT enable App Sandbox (a global
   `CGEventTap` + arbitrary-app paste can't run sandboxed).
5. Build & run; walk the onboarding, grant the three permissions, and verify
   the full loop: **hold hotkey → speak → release → text pastes at the cursor.**
   Explicitly verify the **fn/Globe key** works as push-to-talk (the whole
   point — set System Settings ▸ Keyboard ▸ "Press 🌐 to: Do Nothing" first).

## Phase 2 — bundle the model (offline first launch)

Add a WhisperKit CoreML model to the app's Resources and point
`Transcriber.warmUp()` at `Bundle.main` so there's **no first-run download**.
Verify a fresh Mac, offline, transcribes on first launch.

## Phase 3 — sign, notarize, DMG

```bash
xcodebuild -scheme OpenVoiceFlow -configuration Release \
  -derivedDataPath build archive ...
codesign --force --options runtime --timestamp \
  --entitlements native/OpenVoiceFlow.entitlements \
  --sign "Developer ID Application: …" OpenVoiceFlow.app
xcrun notarytool submit OpenVoiceFlow.app.zip --keychain-profile ovf --wait
xcrun stapler staple OpenVoiceFlow.app        # staple the .app, not just the DMG
# build DMG (reuse the repo's create-dmg approach), staple + notarize the DMG too
```

Gate on `spctl --assess --type execute OpenVoiceFlow.app` before shipping.

## Phase 4 — feature parity (milestones, in priority order)

The scaffold ships the core loop. Port from the Python app next:
1. Per-app style detection (`NSWorkspace.frontmostApplication`).
2. Voice commands + snippets (pre-cleanup text substitution).
3. Streaming partial results in the HUD (WhisperKit streaming API).
4. Know-Me profile + prompt personalization.
5. Auto-learn corrections, statistics, transcript logging (0600), history search.
6. Full Settings window; Sparkle appcast + EdDSA key; launch-at-login (SMAppService).
7. Doctor-equivalent diagnostics.

## Phase 5 — CI

Add a macOS GitHub Actions job: `swift build` + `swift test` on `native/`, and
a signed release workflow mirroring the Python one. Keep the Python app as the
shipping product until native reaches parity + passes a real on-device test.

---

### Map: Python module → native file

| Python | Native |
| --- | --- |
| `app.py` (orchestrator) | `AppController.swift` |
| `recorder.py` | `AudioCapture.swift` |
| `transcriber.py` (whisper.cpp) | `Transcriber.swift` (WhisperKit) |
| hotkey (pynput) | `HotkeyEngine.swift` (CGEventTap — **fn works**) |
| `system.py` paste | `Paster.swift` (CGEventPost) |
| `overlay.py` | `HUDController.swift` |
| `menubar.py` (rumps) | `OpenVoiceFlowApp.swift` MenuBarExtra |
| `onboarding.py`/`interview.py` (tkinter) | `OnboardingView.swift` (SwiftUI) |
| `llm/*` | `CleanupProvider.swift` |
| `config.py` + keys in JSON | `Settings.swift` + **Keychain** |
| doctor / permissions | `Permissions.swift` |
