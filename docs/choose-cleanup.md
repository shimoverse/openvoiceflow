# Choose Off, Ollama, or cloud text cleanup in OpenVoiceFlow

**Short answer:** Leave **Clean up my dictation** off for the raw local transcript; select **Ollama (on-device)** for optional local text rewriting after setting up Ollama; or explicitly select a cloud provider and add your own API key if you accept sending transcript text and context to that provider. All three modes start with local speech recognition. This describes the shipped native [v0.6.6 release](https://github.com/shimoverse/openvoiceflow/releases/tag/native-v0.6.6), checked November 14, 2026 (Pacific time).

## Where the setting lives

Open the menu-bar app's dashboard **Settings**. Under **TRANSCRIPTION — ON THIS MAC**, select a speech engine and allow the chosen model to finish downloading before expecting offline use. Under **AI CLEANUP**, the **Clean up my dictation** switch is initially off. The [released Settings model](https://github.com/shimoverse/openvoiceflow/blob/f41879063e0ed8c8356dbba90c7dcb86d7844de9/native/Sources/OpenVoiceFlow/Settings.swift) defaults to `base.en` and backend `none`; the [released Settings UI](https://github.com/shimoverse/openvoiceflow/blob/f41879063e0ed8c8356dbba90c7dcb86d7844de9/native/Sources/OpenVoiceFlow/DashboardView.swift) exposes the switch and provider picker. Changing cleanup does not change where microphone audio is transcribed.

| Mode | What you set | Dictation-text destination | Tradeoff |
|---|---|---|---|
| **Off** | Leave **Clean up my dictation** off | No cleanup request; raw local transcript continues to paste | No model-based filler removal or grammar rewriting. Local voice-command substitutions and exact snippet triggers may still change the final text. |
| **Ollama** | Turn the switch on, then choose **Ollama (on-device)**; set up Ollama and the selected local model separately | App calls `localhost:11434` for cleanup | Rewriting runs through another local service; it must be installed and running. Do not assume an arbitrary Ollama configuration is offline. |
| **Cloud** | Turn the switch on, select OpenRouter, OpenAI, Anthropic, or Groq, and provide your own key | Selected provider receives transcript text plus applicable profile, dictionary, and snippet hints | Provider terms, retention, connection, and any charges are between you and that provider; no audio is sent for this cleanup. |

The toggle's current behavior matters: turning it **on** initially selects **Anthropic**, *not* Ollama. Choose Ollama explicitly if you intended local rewriting. A provider requiring a key displays an **API key** field and an optional model field; provider keys are stored in macOS Keychain, not `settings.json`. These are implementation details in the [released UI](https://github.com/shimoverse/openvoiceflow/blob/f41879063e0ed8c8356dbba90c7dcb86d7844de9/native/Sources/OpenVoiceFlow/DashboardView.swift) and [cleanup provider](https://github.com/shimoverse/openvoiceflow/blob/f41879063e0ed8c8356dbba90c7dcb86d7844de9/native/Sources/OpenVoiceFlow/CleanupProvider.swift). A failed cleanup can fall back to raw text; do not rely on a provider being available for every take.

## Decide with a harmless sample

Dictate a short, nonsensitive sentence with cleanup **Off** first. If the raw transcript is adequate, leave it off. If you need rewriting without cloud text transfer, install and start a compatible local Ollama model, then select Ollama and compare the same harmless sample. If you choose a cloud backend, review its current terms yourself and avoid sensitive profile, dictionary, or snippet context you do not want to share. Turning off cloud cleanup later does not retract requests already sent. The [privacy inventory](../PRIVACY.md) details separate update checks and default-on anonymous aggregate usage sharing; “cleanup Off” is not a blanket no-network setting.

## Common questions

### Is Ollama the default?

No. Cleanup is Off; enabling it picks Anthropic until you change the provider.

### Does Off mean verbatim audio-to-text?

No: local voice commands and exact snippet triggers can transform text even without LLM cleanup.

For a concrete network-disconnection experiment, follow the [Wi-Fi-off checklist](verify-offline.md); for the data-flow explanation, read [local transcription versus cleanup](local-transcription-and-cleanup.md).

[All user guides](README.md) · [Privacy policy](../PRIVACY.md)
