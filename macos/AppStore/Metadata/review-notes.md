# App Review notes

OpenVoiceFlow is a native, sandboxed macOS menu-bar and windowed productivity app.

## Review path

1. Launch OpenVoiceFlow. Its status window appears and a waveform icon appears in the menu bar.
2. Approve the system microphone prompt.
3. Hold **Control+Option+Space**, speak a short sentence, then release the shortcut.
4. Wait for the local transcription to finish.
5. The transcript appears in the window and is copied to the pasteboard. Press Command+V in TextEdit to verify the output.

The Store edition intentionally does not inject keyboard events or automate other apps. It does not request Accessibility or Input Monitoring access.

## Network and data

- The app makes no runtime network requests.
- The whisper.cpp runtime and `ggml-base.en` model are included in the submitted bundle.
- Audio is written only to the app's sandboxed Application Support container while processing.
- Transcription runs locally and finished text is placed on the pasteboard.
- No user account, analytics, advertising, tracking, crash reporting, or cloud service is used.

## Shortcut

The normal Carbon hotkey **Control+Option+Space** is registered while the app runs. Press starts recording; release stops recording. If another app has reserved the shortcut, OpenVoiceFlow reports that conflict in its status window and its on-screen Record button remains usable.
