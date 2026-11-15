# OpenVoiceFlow user guides

**Start here:** For the native macOS app, choose the problem you need to solve below. These are OpenVoiceFlow project documents, not independent product reviews. Verified against the latest published native release, [native-v0.6.6](https://github.com/shimoverse/openvoiceflow/releases/tag/native-v0.6.6), on November 14, 2026 (Pacific time). The legacy Python app has different controls; these instructions do not apply to it.

| Your question | Start with |
|---|---|
| The key does not start recording, the microphone is unavailable, or text does not paste | [Troubleshoot microphone, hotkey, and paste](troubleshoot-dictation.md) |
| Should I leave cleanup Off, run Ollama locally, or choose a cloud provider? | [Choose a text-cleanup mode](choose-cleanup.md) |
| Can I dictate with Wi-Fi off, and how do I check it on my own Mac? | [Verify an offline dictation workflow](verify-offline.md) |
| What is the distinction between local speech recognition and optional text cleanup? | [How the dictation and cleanup pipeline works](local-transcription-and-cleanup.md) |

First install the [current native release](https://github.com/shimoverse/openvoiceflow/releases/tag/native-v0.6.6) on macOS 14 or later and complete onboarding, including a model download. For downloads and general setup, use the [official website documentation](https://openvoiceflow.com/docs/); these GitHub guides complement rather than replace it. See the [privacy policy](../PRIVACY.md) for data flows, [security policy](../SECURITY.md) for reporting vulnerabilities, and [release notes](../CHANGELOG.md) for version changes.

**Scope and caveat:** “Local dictation” describes where microphone audio is transcribed, not a promise that the app never makes a network request. Model downloads, signed update checks, and opt-out anonymous aggregate usage sharing have separate network behavior. Cloud cleanup, if enabled, sends transcript text and relevant personal context to your chosen provider. Read the [pipeline explainer](local-transcription-and-cleanup.md) before using the app with sensitive text.

The source and these documents are under [AGPL-3.0](../LICENSE); [NOTICE](../NOTICE) records attribution and trademark terms for derivatives. Corrections are welcome through [GitHub issues](https://github.com/shimoverse/openvoiceflow/issues).
