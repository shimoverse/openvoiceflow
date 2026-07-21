# OpenVoiceFlow — native (Swift) rewrite

This directory is the **foundation** for the native macOS rewrite of
OpenVoiceFlow. Its goal is an Apple-grade experience: a signed,
notarized, drag-to-Applications app with **no Homebrew, no Terminal, no
Python, no first-run download** — everything ships inside the bundle.

> Status: **scaffold**. This code was authored to be idiomatic and
> compile-ready, but it has **not** been compiled or run yet — that has to
> happen on a Mac with Xcode (see [`BUILD_RUNBOOK.md`](BUILD_RUNBOOK.md)).
> Treat it as the architecture + first working slice, not a finished app.

## Why native (what it fixes over the Python app)

| Problem in the Python app | Native fix |
| --- | --- |
| First launch installs Homebrew + a venv + downloads a 142 MB model | WhisperKit model bundled/pinned; single self-contained `.app` |
| **fn/Globe key never works** (pynput has no fn key) | `CGEventTap` reads the secondary-fn flag directly → fn works |
| Auto-paste shells out to `osascript` (a 4th TCC prompt + latency) | `CGEventPost` synthesizes ⌘V (needs only Accessibility) |
| tkinter onboarding renders non-native (wrong fonts, dark-only) | SwiftUI onboarding that tracks system appearance |
| Emoji HUD + fake text "spinner" | SwiftUI HUD with SF Symbols + real progress |
| Update = "go re-download and re-run the installer" | Sparkle in-app updates (signed appcast) |

## Technology choices

- **UI:** SwiftUI + AppKit. Menu bar via `MenuBarExtra` (macOS 13+); the
  floating HUD is a non-activating `NSPanel` hosting a SwiftUI view.
- **Transcription:** [WhisperKit](https://github.com/argmaxinc/WhisperKit)
  (on-device, CoreML/Metal, Swift). Replaces the whisper.cpp subprocess.
- **Hotkey:** a `CGEventTap` on `keyDown`/`keyUp`/`flagsChanged`, so both
  modifier keys (incl. **fn**) and F-keys work as push-to-talk.
- **Audio:** `AVAudioEngine` tap → 16 kHz mono `Float` buffer fed to WhisperKit.
- **LLM cleanup:** `URLSession` async/await; a `CleanupProvider` protocol with
  OpenRouter/OpenAI/Anthropic/Groq/Ollama/none implementations.
- **Paste:** `CGEventPost` ⌘V (Accessibility only — no Apple Events prompt).
- **Updates:** [Sparkle 2](https://sparkle-project.org) with an EdDSA-signed appcast.
- **Persistence:** a `Settings` `Codable` in `~/Library/Application Support/OpenVoiceFlow/`;
  API keys in the **Keychain** (not a JSON file).
- **Min OS:** macOS 13 Ventura (SwiftUI `MenuBarExtra`, modern WhisperKit).

## Module map (`Sources/OpenVoiceFlow`)

| File | Responsibility |
| --- | --- |
| `OpenVoiceFlowApp.swift` | `@main` app, `MenuBarExtra`, wiring |
| `AppController.swift` | State machine: idle → recording → transcribing → cleaning → pasting |
| `HotkeyEngine.swift` | `CGEventTap` push-to-talk (modifiers incl. fn, F-keys) |
| `AudioCapture.swift` | `AVAudioEngine` → 16 kHz mono Float buffer |
| `Transcriber.swift` | WhisperKit wrapper (async transcribe) |
| `CleanupProvider.swift` | LLM cleanup protocol + implementations |
| `Paster.swift` | `CGEventPost` ⌘V, clipboard-safe |
| `HUDController.swift` | Non-activating `NSPanel` + SwiftUI HUD, screen-aware |
| `Permissions.swift` | Mic / Accessibility / Input Monitoring checks + prompts |
| `Onboarding.swift` | SwiftUI first-run flow (backend, key, hotkey, permissions) |
| `Settings.swift` | `Codable` settings + Keychain for secrets |
| `Log.swift` | `os.Logger` wrappers |

## How to build

See [`BUILD_RUNBOOK.md`](BUILD_RUNBOOK.md). Short version, on a Mac:

```bash
cd native
open Package.swift        # or: swift build
```

The runbook covers turning the SwiftPM executable into a signed, notarized
`.app`, wiring WhisperKit + Sparkle, and the DMG.

## What's intentionally NOT done yet (tracked)

This is a foundation. The following are stubbed or pending and are the next
milestones (see `BUILD_RUNBOOK.md` → "Milestones"): per-app style detection,
the Know-Me profile, voice commands/snippets, streaming partial results,
auto-learn, statistics, and full settings UI. The core dictation loop
(hotkey → capture → transcribe → clean → paste) is the first slice.
