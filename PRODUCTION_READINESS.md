# Production readiness — audit findings & roadmap

An end-to-end audit (runtime/concurrency, macOS UX vs. Apple HIG, packaging/
first-run, security/privacy) was run against the codebase. This file records
**what was fixed** and — more importantly — **what remains**, so the path to a
genuinely Apple-grade, "award-winning" experience is explicit and nothing is
lost.

## Done in this pass (tested, in `voiceflow/` + `build-dmg.sh`)

Runtime robustness
- Mic is armed on the event-tap thread; the ~150 ms of `osascript` context
  capture moved to a worker so a stalled consent dialog can't disable the
  global hotkey (**H1**).
- Max-duration watchdog force-stops a recording whose key-release was lost,
  instead of leaving the mic + `whisper-stream` running forever (**H2**).
- `recorder.stop()` always releases the PortAudio stream even if the device
  was unplugged mid-recording; the guarded stop path surfaces the error
  instead of freezing the overlay (**H3**).
- A failed processing-thread start rolls back the `processing` flag (no wedged
  hotkey); `transcribe()` reports the whisper binary vanishing distinctly.
- Hung `pbcopy`/`osascript` children are reaped on timeout, not orphaned.

Data-loss & privacy
- Selected-text capture no longer destroys a non-text clipboard (image/file)
  and never restores empty text over the user's selection.
- `~/.openvoiceflow/logs/` is created `0700`; the secrets writer uses
  `O_EXCL|O_NOFOLLOW` so a symlink swap can't redirect it.
- LLM/Ollama responses are read with a 16 MB cap; `ollama_url` is validated
  (non-HTTP schemes rejected, off-loopback warns).

Packaging
- The venv marker is **version-stamped**, so a release that bumps a dependency
  actually reinstalls for existing upgraders instead of silently breaking on
  import.

UX polish (safe, standard AppKit — verify visually on device)
- Overlay timers run in `NSRunLoopCommonModes` (no freeze during menu
  tracking); fades honor **Reduce Motion**; the window is `orderOut`-ed after
  fade so it doesn't linger in every Space.
- The Know-Me interview no longer abandons itself (data loss) when Escape is
  pressed while typing in a field.

---

## Remaining — ranked by leverage

### Tier A — the "award-winning native" investments (re-architecture)

**A1. Native SwiftUI onboarding + Know-Me interview.** The first thing every
user sees is a tkinter wizard with a hardcoded dark theme and fonts
(`"SF Pro Display"`, `"SF Mono"`) that Tk can't resolve, so it silently renders
Helvetica fallback with non-native buttons and no focus rings. This is the
single highest-impact polish surface. *Rewrite in SwiftUI/AppKit.* (Cheap
interim already partially addressed: the destructive-Escape bug is fixed.)

**A2. Self-contained bundle — no Homebrew, no Terminal, no pip-at-runtime.**
First launch currently installs the Command Line Tools, runs the Homebrew
installer in Terminal, `brew install whisper-cpp`, builds a venv, pip-installs
unpinned deps, and downloads a 142 MB model — a multi-minute, network-dependent,
non-Apple experience. Ship instead: a code-signed `whisper-cli` per arch in
`Resources/` (add the bundle path to `transcriber.py`'s probe — low risk); the
`ggml-base.en.bin` model in the DMG (or a checksum-pinned download); and a
relocatable interpreter (python-build-standalone) or `py2app`/PyInstaller bundle
with wheels pre-installed and pinned at build time, code-signed and notarized as
nested code. Payoff: true drag-to-Applications, launch-and-go, fully offline.

**A3. SF Symbols + real progress in the HUD.** The recording HUD communicates
with emoji (🔴✅❌📚) inside an `NSTextField` and a fake text-dot "spinner."
Replace with tinted `NSImage.imageWithSystemSymbolName_` glyphs and an
`NSProgressIndicator` (or a live mic-RMS level meter). Highest polish-per-hour;
can be done within the current stack.

**A4. In-app updates (Sparkle).** Today the app only *checks* GitHub Releases
and sends the user to a web page to re-download and re-run the whole bootstrap.
Integrate Sparkle with a signed (EdDSA) appcast for one-click, verified,
auto-relaunch updates.

### Tier B — packaging correctness (do before a real launch; mostly incremental)

**B1. Couple the served DMG to the signing pipeline (audit C1).** Users
download hand-committed blobs in `docs/downloads/`; the "refuse unsigned" guard
only protects the GitHub Release asset nobody clicks. A local unsigned
`build-dmg.sh` run can reach the website while the page claims "notarized." Fix:
have the release workflow copy the just-notarized `dist/*.dmg` into
`docs/downloads/`, regenerate the checksums, and gate on `spctl --assess` +
`stapler validate` before deploy.

**B2. Staple the `.app`, not just the DMG (audit H1).** Only the DMG is
stapled; the dragged-out app carries no ticket, so an offline first launch can
be Gatekeeper-blocked — contradicting the download page. Notarize + staple the
`.app`, then build the DMG from the stapled app.

**B3. Pin + checksum the supply chain (audit H4).** The model is fetched from a
mutable `…/main/ggml-base.en.bin` with no checksum; pip/brew are unpinned. Pin
the model by immutable commit SHA + verify SHA256; pin pip deps
(`--require-hashes`); pin or drop the brew formula.

**B4. Version-drift gate (audit M1) & Intel execution (M2) & CLT-Python matrix
(M3).** Have `verify-version` also assert `download.html`/`site.js`/README match
the tag; exercise the x86_64 launcher under Rosetta in CI; extend the CI Python
matrix to the versions current CLT actually ships (3.12/3.13).

**B5. App Translocation guard (audit M5).** Detect launch from `/Volumes/` or a
translocated path and prompt "move to Applications."

### Tier C — UX correctness within the current stack (cheap, but verify on device)

- **Permission priming (audit UX #3):** three scary TCC prompts fire back-to-
  back at first launch with no explanation and before the user knows what the
  app does. Add a per-capability priming screen; request each in-context; defer
  Input Monitoring until listening starts.
- **CGEventPost paste (audit UX #5):** replace the AppleScript `System Events`
  keystroke (a 4th Automation prompt + a subprocess on every dictation's hot
  path) with `CGEventPost` — needs only Accessibility, no dialog, sub-ms.
- **Screen-aware HUD (audit UX #4):** position on the display containing the
  mouse/active window, within its `visibleFrame` (not primary-only, full frame).
- **Menu HIG (audit UX #9):** ellipsis on dialog-opening items; clearer
  Listening toggle; unify the hotkey label source between menu and onboarding.
- **Measure HUD text** with `NSAttributedString.size()` instead of `chars×8px`;
  visible radio selection in the wizards (`selectcolor=ACCENT`).

### Tier D — privacy/product decisions (need a human call)

- **Profile PII default (audit security M1):** completing the Know-Me interview
  sends home/work names (incl. children's names) into the system prompt of every
  cloud cleanup call by default (default backend is OpenRouter, which fans out to
  sub-providers). Consider: gate the profile fragment behind explicit transmit
  consent; prefer a local backend when a profile exists; show which fields leave
  the machine.
- **`--set-key KEY` (security M3):** the plaintext-arg form leaks the key into
  `ps`/shell history; the `-` stdin form is the documented default. Consider
  warning on, or removing, the literal-arg form.

---

*Effort orientation: Tier A is weeks (A2 is the biggest single lift); Tier B is
days and gates a real public launch; Tier C is hours each but needs on-device
visual verification; Tier D is a product/privacy decision, not just code.*
