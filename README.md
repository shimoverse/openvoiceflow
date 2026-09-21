![OpenVoiceFlow](native/assets/readme-banner.png)

# OpenVoiceFlow

**Free and open source voice dictation for macOS. Hold a key, talk, release — polished text lands in whatever app you're in. Your audio never leaves your Mac.**

[![macOS 14+](https://img.shields.io/badge/macOS-14%2B-black)](https://openvoiceflow.com/download.html)
[![License: AGPL v3](https://img.shields.io/badge/license-AGPL--3.0-blue.svg)](LICENSE)
[![Release](https://img.shields.io/github/v/release/shimoverse/openvoiceflow?filter=native-v*&label=release)](https://github.com/shimoverse/openvoiceflow/releases)

People speak at roughly 150 words a minute and type at roughly 40. OpenVoiceFlow exists because closing that gap shouldn't cost $144 a year or require streaming your voice to someone's cloud. We think voice input should eventually be a default feature of every operating system; until it is, this is our contribution — and contributions are welcome.

## Install

**[Download the DMG](https://openvoiceflow.com/download.html)** — one universal build for Apple Silicon and Intel, Developer-ID signed and Apple-notarized. Drag it to Applications, open it, and a one-minute setup walks you through permissions and a speech-engine choice.

Requires macOS 14 (Sonoma) or newer. On macOS 12–13, the download page offers a retained legacy build.

## What it does

- **Push-to-talk dictation** — hold your chosen key (default: `fn`), speak, release. Text pastes at your cursor in any app.
- **On-device transcription** — [WhisperKit](https://github.com/argmaxinc/WhisperKit) runs Whisper locally, from `tiny` (39 MB) to `large-v3-turbo`. Audio is processed in memory and discarded; nothing is uploaded, nothing is recorded when the key isn't held.
- **Live feedback** — your words appear in the HUD as you speak, so you know it hears you.
- **Optional AI cleanup** — off by default (raw transcript, fully local). Turn it on to polish grammar and filler words via OpenRouter, OpenAI, Anthropic, Groq, or a fully-local Ollama model. Keys live in the macOS Keychain. Only cleaned *text* ever touches an API — never audio.
- **Personal dictionary, snippets, per-app styles** — teach it names and jargon once; spoken shortcuts expand to full text; casual in Slack, formal in Mail.
- **Auto-updates** — signed Sparkle updates from [openvoiceflow.com](https://openvoiceflow.com), verified with an EdDSA key pinned in the app.

No account or consumer subscription — see [the mission](https://openvoiceflow.com/#mission). Anonymous aggregate usage sharing is on by default and takes one switch to turn off; it never includes dictation text (see [PRIVACY.md](PRIVACY.md) §7).

## Build from source

You need a Mac on macOS 14+ with Xcode 16.4+ and [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).

```bash
git clone https://github.com/shimoverse/openvoiceflow.git
cd openvoiceflow
bash native/scripts/run-local.sh
```

That generates the Xcode project from `native/project.yml`, builds an ad-hoc-signed debug app, and launches it. (Ad-hoc rather than unsigned, because macOS ties the Accessibility and Input Monitoring grants to a code signature — unsigned, the hotkey silently never fires.) For the signed + notarized release pipeline, see [`native/BUILD_RUNBOOK.md`](native/BUILD_RUNBOOK.md).

## How it's put together

Everything shipping lives in `native/Sources/OpenVoiceFlow/` — a small Swift/SwiftUI app with no storyboard and no dependencies beyond WhisperKit and Sparkle:

| Piece | File | Job |
|---|---|---|
| App + menu bar | `OpenVoiceFlowApp.swift` | `MenuBarExtra`, login item, Dock policy |
| State machine | `AppController.swift` | idle → recording → transcribing → cleaning → pasting |
| Hotkey | `HotkeyEngine.swift` | CGEvent tap; one key watched, everything else passes through |
| Audio | `AudioCapture.swift` | 16 kHz mono capture, level metering |
| Transcription | `Transcriber.swift` | WhisperKit lifecycle, model download, live partials |
| Cleanup | `CleanupProvider.swift` | the five backends behind one protocol |
| Paste | `Paster.swift` | ⌘V synthesis with clipboard restore |
| HUD | `HUDController.swift` | the floating waveform pill |
| Dashboard | `DashboardView.swift` | history, stats, dictionary, snippets, styles, settings |
| Onboarding | `OnboardingView.swift` | permissions, engine choice, first dictation |

The repo also contains the **legacy Python app** (`voiceflow/`, ≤ 0.3.6) that the native app replaced. It is end-of-life, receives no security fixes, and its defaults differ from current policy — kept only for reference and for the macOS 12–13 fallback build. Don't start there.

## Contributing

Start with [CONTRIBUTING.md](CONTRIBUTING.md). The short version: pull requests are welcome, CI compiles the Swift app and runs the Python test suite on every PR (the website tests live in the separate site repo), and the maintainer reviews everything. Good first contributions: try the app and file honest bug reports, add an XCTest target (we want one), improve accuracy for your language.

## Privacy and security

The one-page version: audio on-device always; text to a cloud only if you enable cleanup; keys in the Keychain; anonymous aggregate usage sharing on by default, one switch to turn off, never dictation text. Full statements: [PRIVACY.md](PRIVACY.md) · [SECURITY.md](SECURITY.md) · [threat model](THREAT_MODEL.md). To report a vulnerability, see [SECURITY.md](SECURITY.md).

## License

OpenVoiceFlow is free and open source software under the
**[GNU Affero General Public License v3.0](LICENSE)** (AGPL-3.0).

Use it for anything, including at work, with no permission to ask for and
nothing to pay. If you convey a modified version, or let people use one over a
network, the AGPL asks you to publish that version's complete corresponding
source under the same license. Keep the notices, state **"Based on
OpenVoiceFlow by Shimoverse Studios"** with a link to the
[original source](https://github.com/shimoverse/openvoiceflow), and rename your
fork — the license grants no rights in the OpenVoiceFlow name or logo. Those
two conditions are additional terms under AGPL Section 7, recorded in
[NOTICE](NOTICE).

There is no second license and nothing to buy. If you build something on
OpenVoiceFlow we would like to hear about it at **contact@openvoiceflow.com** —
a request, not a condition of the license.

Copyright © 2025–2026 **Shimoverse Studios**. See [LICENSING.md](LICENSING.md),
[TRADEMARKS.md](TRADEMARKS.md),
[legal/LEGACY_MIT_PORTIONS.md](legal/LEGACY_MIT_PORTIONS.md), and
[legal/THIRD_PARTY_NOTICES.md](legal/THIRD_PARTY_NOTICES.md).
