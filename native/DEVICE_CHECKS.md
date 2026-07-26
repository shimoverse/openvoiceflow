# On-device verification checklist

CI compiles the app; these behaviors need a real Mac. Run them before calling
a release verified — they cover everything a compile can't.

1. **Cold launch → hotkey** — quit and relaunch; press the hotkey WITHOUT
   opening the menu bar. It must start listening immediately.
2. **Light mode** — full pass through onboarding, HUD, and dashboard in light
   appearance; nothing should look designed only for dark.
3. **Permissions round-trip** — revoke Accessibility in System Settings; the
   menu header must say dictation is off and the dashboard PERMISSIONS card
   must notice; re-grant must revive dictation without a relaunch.
4. **Live HUD words** — hold the key and talk: words should appear in the HUD
   within a couple of seconds (Whisper latency, not instantly) and update as
   you go. The border/"Listening" cue must be instant on key-down.
5. **Reduce Motion** — enable it; the HUD morph, ink fill, glyph wave, and
   step animations must all fall back to static states.
6. **VoiceOver** — onboarding and the dashboard settings must be navigable;
   the engine chooser rows must announce name, size, and selection.
7. **Auto-update** — an install of the previous version must be offered the
   current one within a check cycle, and the update must apply and relaunch.
8. **Paste across apps** — dictate into TextEdit, a browser text field, and a
   terminal; clipboard contents must be restored afterwards.
9. **Menu-bar squeeze** — on a crowded bar (or a notched laptop), confirm the
   dashboard Home banner appears when the icon is hidden and disappears when
   it's visible again.
