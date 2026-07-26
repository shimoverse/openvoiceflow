# OpenVoiceFlow — native macOS app

**Status: shipping.** This is the app users run (v0.5.x, signed + notarized,
auto-updating via Sparkle). It replaced the legacy Python app at 0.4.0.

- Swift 5.10 / SwiftUI, no storyboards
- Min OS: **macOS 14.0** (WhisperKit's floor in practice; `project.yml` is
  the source of truth)
- Dependencies: WhisperKit 0.18.0, Sparkle 2.9.4 — pinned exactly in
  `project.yml`

## Build

```bash
brew install xcodegen
bash native/scripts/run-local.sh   # generate + build + launch (ad-hoc signed)
```

The `.xcodeproj` is generated from `project.yml`; edit the yml. For the
signed, notarized, stapled release pipeline — and why each step exists — read
[`BUILD_RUNBOOK.md`](BUILD_RUNBOOK.md).

## Module map (`Sources/OpenVoiceFlow/`)

| File | Job |
|---|---|
| `OpenVoiceFlowApp.swift` | entry point, menu bar, login item, Dock policy |
| `AppController.swift` | the state machine: idle → recording → transcribing → cleaning → pasting |
| `HotkeyEngine.swift` | CGEvent tap for the push-to-talk key |
| `AudioCapture.swift` | 16 kHz mono capture + level metering |
| `Transcriber.swift` | WhisperKit lifecycle, model downloads, live partials |
| `CleanupProvider.swift` | optional LLM cleanup (5 backends, one protocol) |
| `Paster.swift` | ⌘V synthesis with clipboard restore |
| `HUDController.swift` | floating waveform HUD |
| `DashboardView.swift` | dashboard window (history, stats, dictionary, snippets, styles, settings) |
| `OnboardingView.swift` | first-run flow: permissions, engine choice, first dictation |
| `KnowMeInterview.swift` | the Know-Me profile interview |
| `FeatureStores.swift` | persisted stores: dictionary, snippets, styles, profile, history |
| `Settings.swift` | preferences (JSON in App Support) + Keychain wrapper |
| `Permissions.swift` | the three TCC permissions: status, request, deep links |
| `HelloCallout.swift` | onboarding's anchored "I live up there" callout |
| `StatusIcon.swift` | menu-bar icon renderer + animator |
| `DesignTokens.swift` | shared colors/metrics from the design system |
| `Updater.swift` | Sparkle wiring |

Design provenance for the UI lives in git history (phase-06 redesign);
`BUILD_RUNBOOK.md` covers release mechanics.
