# Handoff: OpenVoiceFlow phase-06 redesign (macOS)

## Overview

This bundle specifies a redesign of three surfaces of the OpenVoiceFlow macOS app — the **first-run experience**, the **dictation HUD**, and the **dashboard Home pane** — plus a full copy pass, a motion spec, and asset direction.

The redesign is **subtractive**. The existing design system (phases 01–05, implemented in `native/Sources/OpenVoiceFlow/DesignTokens.swift`) is not being replaced. Every colour, radius, spring, and every piece of waveform math stays exactly as it is. What changes is **sequence, scale, and honesty**:

1. **The HUD becomes one continuous stroke.** Today it draws five unrelated paths and cuts between them. It should morph — wave → coil → flat line → tick — so it reads as one object doing different jobs. It also shrinks from 290×44 to 172×38 at rest.
2. **The model download stops being a step.** It runs behind the Know-Me interview, so the longest wait in the product happens while the user does the most valuable thing they can do for transcription quality.
3. **The first successful dictation is kept forever.** A full-window payoff moment during onboarding, then a permanent "Your first words" card on Home.

Goal, from the brief: *make a person's first 60 seconds feel like magic, and the 500th dictation feel effortless.*

---

## About the design files

`06-redesign.dc.html` in this bundle is a **design reference created in HTML**. It is a prototype communicating intended look, geometry, and behaviour — **not production code to port**. Do not translate its DOM, its inline styles, or its `class Component` logic into anything.

The target is the existing SwiftUI/AppKit app at `native/Sources/OpenVoiceFlow/`. Implement the designs using that codebase's established patterns: `DT` tokens, `Canvas`/`TimelineView` for the waveform drawing, `NSPanel` for the HUD, SwiftUI views for windows.

**Two things in the HTML *are* authoritative and should be copied literally:**
- The **canvas drawing math** in its `<script data-dc-script>` block (`S(t)`, `win(u)`, `wob()`, the coil, the shimmer, the tick). This is transcribed verbatim from `DesignTokens.swift` → `Voiceline` and `HUDController.draw()`. It is there so you can see the motion, not because it needs porting — the Swift already has it.
- The **exact copy strings** in §06. Those are the deliverable.

To open the prototype: serve this folder over HTTP (`python3 -m http.server`) and load `06-redesign.dc.html`. `support.js` and `native/assets/` must sit beside it, as they do here. It is interactive — §02's frame chips walk the whole first run, §03's hero pill responds to press-and-hold.

## Fidelity

**High-fidelity.** Every dimension, hex value, font size, weight, letter-spacing, duration and easing curve in this README is final and was measured from the design file. Where a value is unchanged from the current build, it says so explicitly — treat those as "do not touch".

The one exception: the mock content (names, numbers, sentences like *"Priya — let's ship the HUD on Friday."*) is placeholder. Real data comes from the existing stores.

---

## Target codebase

Repo: `github.com/shimoverse/openvoiceflow`, branch `main`, subtree `native/`.

| File | Role in this work |
| --- | --- |
| `Sources/OpenVoiceFlow/DesignTokens.swift` | Add new tokens. Change nothing existing. |
| `Sources/OpenVoiceFlow/HUDController.swift` | HUD geometry, states, progress, text tail. Substantial change. |
| `Sources/OpenVoiceFlow/OnboardingView.swift` | Rewritten flow: 4 steps → 5, sequential permissions, inline Know-Me. |
| `Sources/OpenVoiceFlow/DashboardView.swift` | Home pane restructured. Other panes: copy only. |
| `Sources/OpenVoiceFlow/Settings.swift` | 3 new persisted fields. |
| `Sources/OpenVoiceFlow/FeatureStores.swift` | `firstEntry`, `firstUseDate`, minutes-per-day. |
| `Sources/OpenVoiceFlow/Transcriber.swift` | Download progress must report bytes, not a fraction. |
| `Sources/OpenVoiceFlow/StatusIcon.swift` | One new glyph state + a one-shot animation. |
| `Sources/OpenVoiceFlow/KnowMeInterview.swift` | Must render inline, not only as a sheet. |
| `Sources/OpenVoiceFlow/Permissions.swift` | No change to logic; add a polling helper. |
| `assets/dmg-bg@2x.png` | Re-render with new caption. |
| `scripts/build-app.sh` / DMG build | No geometry change needed. |

### Do not change

- Any colour in `DT`. Any radius (6 / 12 / 14 / capsule h/2).
- The three springs: `snap(0.25, 0.90)`, `arrive(0.30, 0.85)`, `settle(0.45, 1.0)`.
- `Voiceline.envelope`, `Voiceline.window`, `Voiceline.wobble`.
- Every glyph path in `StatusIconRenderer` (a new case is added; existing cases are untouched).
- The HUD's summon (90 ms fade + 9 px rise) and dismiss (160 ms fade + 4 px down) timings.
- The HUD's bottom-centre position and 24 pt offset above `visibleFrame.minY`.
- The 212 pt dashboard sidebar, its pane list, its ordering, its selection tint.
- `appicon-1024.png` and `appicon-1024-light.png`.
- The DMG window geometry and drop positions.

### One design decision to understand before you start

**The HUD stays bottom-centre.** The brief floated putting it near the cursor. It must not go there: following the caret requires reading text position out of every app through the Accessibility API, and "I don't read what's on your screen" is a promise the redesign makes explicitly in the permissions copy. Bottom-centre costs no additional permission, never occludes the insertion point, and is in the same place every time — which is what "glanceable" actually means. Do not reintroduce cursor tracking.

---

## Implementation tasks, in dependency order

Each task is self-contained and shippable. **T1, T4 and T8 deliver most of the value** — if scope has to be cut, cut from the middle.

### T1 — DMG background caption

**File:** `assets/dmg-bg@2x.png` (regenerate), no code change.

The current asset is good and mostly stays: warm paper gradient (`#F9F7F3` → `#F4F1EA` at 55% → `#EFECE2`, 150°), the dotted ember wave (`#C97B35`, 3.4 pt stroke, `stroke-dasharray: 0.5 9`), the chevron at the right end, the drop positions. Canvas is 1320×800 px @2× = 660×400 pt.

**Only the caption changes.** Replace:

> `drag along the line · signed & notarized · sha-256 on the download page`

with two centred lines, baseline of the first at 9% up from the bottom:

> **Then open it from Applications.** — 15 pt, weight 600, `#26221B`, letter-spacing −0.01em
> `macOS can't launch me itself. If it says "downloaded from the Internet", click Open.` — 12.5 pt, regular, `#847D6E`

Why: nobody verifies a checksum off a DMG background, and they can see the line. Those two lines are the only place to pre-empt Gatekeeper, and matching the OS's exact phrasing ("downloaded from the Internet") means the user *recognises* the dialog instead of parsing it.

**Also:** add a CI assertion that notarisation is live. The copy promises an **Open** button; if notarisation lapses, Gatekeeper shows a dead-end "Move to Trash" instead and the copy becomes a lie.

**Website (separate repo/target):** the download page gains three "What happens next" cards — *Drag it to Applications* / *Open it from Applications — macOS won't launch it for you, nothing is broken* / *macOS will warn you once: "downloaded from the Internet." Click **Open**.* Card 3 is highlighted (`#FBF3E7` fill, `#D9CBB4` border). See §02 frame 0.

---

### T2 — Drop the forced dark scheme

**File:** `OnboardingView.swift`

Delete `.preferredColorScheme(.dark)`. Onboarding must track system appearance like `DashboardView` already does, using the same `DT` light/dark pairs:

| Role | Dark | Light |
| --- | --- | --- |
| Window ground | `DT.winDark` `#1D1B18` | `DT.winLight` `#FCFBF8` |
| Card / inset fill | `.white.opacity(0.04)` | `.black.opacity(0.035)` |
| Hairline | `.white.opacity(0.07)` | `.black.opacity(0.07)` |
| Primary ink | `DT.inkDark` `#EAE6DD` | `DT.inkLight` `#26221B` |
| Secondary ink | `DT.ink2Dark` `#96907F` | `DT.ink2Light` `#847D6E` |
| Tertiary ink | `#6B6558` | `#9A9384` |
| Accent | `DT.emberDark` `#E8974E` | `DT.emberLight` `#B4661F` |
| Accent button label | `#1A1508` | `#FFFFFF` |

The design file renders onboarding in dark only (it sits on a dark desktop mock). Light mode uses the pairs above with no layout change.

Also change the window from **640 × 440** to **720 × 470**. The current window uses ~180 pt of its 440 and floats content in the top half.

---

### T3 — Welcome step: answer "where did it go?"

**File:** `OnboardingView.swift`, step 0. See §02 frame 3.

Replace the current welcome (`"Speak. It types."` + tagline + 72 pt ring, centred) with:

- `RingGlyph(size: 96)`, centred, 22 pt below it:
- **"I live up there."** — 34 pt, bold, letter-spacing −0.03em, primary ink
- Body, 12 pt below, 14.5 pt regular, line-height 1.65, secondary ink, max width 420, centred:
  *"No window to keep open, no Dock icon to hunt for. Just a small waveform in the menu bar, and a key you hold when you want to talk."*
- Footer: `"Takes about a minute."` (12.5 pt, tertiary) left; primary pill **"Let's go"** right.

**Remove the 4-dot pagination header entirely.** It is a web carousel pattern. Mac onboarding names its steps or shows nothing; show nothing.

**Concurrently:** the menu-bar glyph plays its `hello` animation (see T7) while this step is on screen, and a dotted ember leader line is drawn from the window's top-right toward the menu-bar icon. In the prototype this is an SVG; in AppKit, draw it in a borderless transparent overlay panel positioned between the window and the status item, or omit the line and rely on the glyph animation alone if that proves fragile across multi-display setups. **Under Reduce Motion the glyph does not animate** — in that case the line is the only cue, so it should not be the piece you drop.

Primary pill spec (unchanged from current build except radius): 13.5 pt semibold, label `#1A1508`, fill `DT.emberDark`, padding 22 × 10, `Capsule()`. Hover fill `#F0A55F`.

---

### T4 — Sequential permissions

**Files:** `OnboardingView.swift`, `Permissions.swift`. See §02 frame 4.

This is the highest-value change after T1. Today three `Allow` buttons are presented simultaneously with no stated order, and the recovery hint appears only *after* a grant fails.

**Structure.** One card, `RoundedRectangle(cornerRadius: 12)`, fill `.white.opacity(0.04)`, border `.white.opacity(0.06)`, containing three rows separated by 1 pt hairlines inset 17 pt.

**Rows reveal progressively.** Row 2's `Allow` button and its limit line appear only once row 1 is granted; row 3's only once row 2 is granted. Ungranted-and-not-yet-reachable rows show name + reason at full opacity but **no button and no limit line** — the user can see what's coming without being asked yet. Reveal uses `DT.arrive`.

**Each row.**
- Status dot: 8 pt circle, top-aligned +5 pt. `DT.moss` `#7FAF8A` when granted, else `.white.opacity(0.16)`.
- Name: 14 pt, weight 600, primary ink.
- Reason: 12.5 pt, regular, secondary ink, on the same baseline.
- Limit line (new, 5 pt below): 12 pt, tertiary ink.
- Trailing: `Allow` pill — 12.5 pt semibold, `#1A1508` on `DT.emberDark`, padding 17 × 7, capsule. Once granted it becomes the text **"Allowed"**, 12.5 pt semibold, `DT.moss`.
- Row padding 17 × 15.

| Permission | Reason | Limit line |
| --- | --- | --- |
| Microphone | so I can hear you | I only listen while the key is held. Nothing is recorded before or after. |
| Accessibility | so I can type for you | I press ⌘V on your behalf. I don't read what's on your screen. |
| Input Monitoring | so I can feel the key | One key — the one you choose. Every other keystroke passes straight through. |

The limit lines are the point. Stating what each permission *cannot* do buys more trust than any badge.

**Header.** "Three switches, then we're done." — 25 pt bold, letter-spacing −0.025em. Sub, 6 pt below: "macOS holds the keys, not me." — 13 pt, secondary ink.

Note the old sub — *"Everything happens on this Mac. Nothing is uploaded, ever."* — is **deleted**. It is contradicted three panes later by five cloud LLM providers. The replacement is true and also explains *why* there are three system dialogs.

**Escape hatch is always visible**, 15 pt below the card, one row, 11.5 pt:
`Clicked Allow and nothing happened?` (tertiary) · **`Open System Settings`** (`DT.emberDark`, semibold, opens `permission.settingsURL`) · `— click + and pick OpenVoiceFlow from Applications.` (`#514C42`)

**Footer.** `‹ Back` left. Right: the primary **Continue** pill only when all three are granted; before that, quiet progress text `"1 of 3"` / `"2 of 3"` (13 pt, tertiary).

**New capability required.** Grants must be detected while the onboarding window *stays key* — the current `NSWindow.didBecomeKeyNotification` refresh misses this, because `AXIsProcessTrusted()` can flip while the user never leaves the app. Add a 0.6 s poll of `Permission.status` that starts when the step appears and cancels when all three are granted or the step is left.

---

### T5 — Model download behind the Know-Me interview

**Files:** `OnboardingView.swift`, `Transcriber.swift`, `KnowMeInterview.swift`. See §02 frame 5.

Delete the standalone "Getting ready" step. The download now runs **underneath** the Know-Me interview in a single step.

**Header:** "While that downloads — who am I typing for?" (25 pt bold, −0.025em) / "Two answers, and your name comes out spelled right the first time." (13 pt, secondary).

**Interview card** — radius 12, fill `.white.opacity(0.04)`, border `.white.opacity(0.06)`, padding 18:
- Label "What should I call you?" 12.5 pt secondary, 8 pt above a 36 pt-high text field: radius 8, fill `.white.opacity(0.06)`, focus border `DT.emberDark` at 45% opacity, text 14 pt primary ink, padding-h 12.
- 16 pt below: "Any names or words I'd get wrong?" then a wrapping token row — each token 12 pt, `DT.chipInkDark` `#CFC9BB`, fill `.white.opacity(0.07)`, radius 6, padding 10 × 5, gap 7. Trailing `+ add` in tertiary ink.

**Progress card** below, gap 14 — radius 12, fill `.white.opacity(0.03)`, border `.white.opacity(0.06)`, padding 17 × 14:
- Header row, baseline-aligned: `Speech engine` (12.5 pt, weight 600, `#CFC9BB`) · spacer · `412 of 981 MB` · `·` · `5.4 MB/s` · `·` · `2 min left`. The three metrics are 11.5 pt; the first two `#847D6E`, the ETA `DT.emberDark` weight 600. **All monospaced digits** (`.monospacedDigit()`).
- Bar: 5 pt tall, radius 3, track `.white.opacity(0.09)`, fill `DT.emberDark`. Animate with `spineCurve` (T6).
- Footer, 9 pt below: "Downloaded once. After this, everything runs offline on this Mac." — 11 pt, tertiary.

**Failure state** (replaces the current failure copy): "That stopped. Check your connection?" — 12.5 pt, `#C9C3B4`. Bar fill switches to `DT.errorAccent`. Keep the existing `Try again` pill and the `Details` disclosure with the monospaced `error.localizedDescription`; don't narrate the button.

**Footer:** `‹ Back` left. Right: primary pill **"Try it"** once complete; before that, quiet `"48%"` (13 pt tertiary, monospaced digits).

**New capability required (two).**
1. `Transcriber.warmUp` currently forwards a `Double` fraction. MB / rate / ETA need `bytesReceived` and `bytesExpected`. Change the `DownloadProgressObserver` signature to carry both; derive rate from a rolling 3-second window and ETA from that rate, and hold the last displayed ETA for 1 s minimum so it doesn't flicker.
2. `KnowMeInterview` must render **inline** in this step, not as a `.sheet`. Extract its question views so both the inline path and the existing dashboard "Re-run interview" sheet share them.

If the model is already present (reinstall, or a user who switched models), skip the progress card, keep the interview, and label the footer button "Try it" immediately.

---

### T6 — HUD

**Files:** `HUDController.swift`, `DesignTokens.swift`, `Settings.swift`, `AppController.swift`. See §03.

#### Geometry

| Token | Now | Proposed |
| --- | --- | --- |
| height | 44 | **38** |
| min width | 290 | **172** |
| max width | 460 | **330** |
| h-padding | 14 | **12** |
| gap | 10 | **9** |
| stroke width | 2 | 2 — unchanged |
| bottom offset | 24 | 24 — unchanged |
| corner radius | h/2 | h/2 — unchanged |
| hotkey chip | always | **first 7 days only** |
| elapsed timer | from 3 s | **from 20 s** |
| progress spine | — | **1.5 pt, inset 12 each side** |

Capsule material, the 10%-opacity hairline border, and the shadow are unchanged. The panel's `NSPanel` configuration (`.nonactivatingPanel`, `.statusBar` level, `canJoinAllSpaces`, `fullScreenAuxiliary`) is unchanged.

**Per-state widths:** Listening / Transcribing / Polishing **172**. Inserted **300**. Too short **244**. Error **330**. Width changes animate with `grow` (200 ms, `snap`).

#### The one line

State changes must **morph the path**, not cross-fade two drawings. Interpolate the point arrays between shapes over 220 ms with `spring(0.22, 0.85)`:

`wave → coil` · `coil → flat line` · `flat line → tick` · `→ broken line` (error)

All five path generators already exist in `HUDController.draw()` and are correct — the work is tweening between them rather than switching on `model.state` at the top of the function. Implementation sketch: sample each state's path to a fixed point count (128 is plenty at these sizes), keep `from`/`to` arrays plus a `0…1` morph clock in `HUDModel`, and lerp per point.

Existing per-state math, all unchanged:
- **Listening** — 150-bucket amplitude history, EMA τ≈70 ms at 60 Hz. `y = mid + breath + wobble(x,t,a,h) · win(x/w)`, where `breath = sin(0.045x − 1.7t) · 1.15 · max(0, 1−3a)` and applies only when `a < 0.03`. Dim stroke `DT.dimWaveDark`/`Light`; hot ember overlay on segments where `a > 0.04`, alpha `min(1, amp·5)`.
- **Transcribing** — coil, `rot = 6.9t` rad/s, `r = (2.5 + 0.95a)·rg` where `rg = min(1, 0.028h)`, `a` sweeping to 4π step 0.12, y scaled 0.92.
- **Polishing** — flat dim line plus an ember gradient window travelling at 150 px/s, 96 px wide, wrapping over `w + 160` offset −80.
- **Inserted** — 16 pt check, `(cx−8, mid) → (cx−2, mid+5) → (cx+8, mid−5)`, stroke 2.4, round cap and join.
- **Too short** — three dots, 2.2 pt base radius, `scale = 0.6 + 0.4·(0.5 + 0.5·sin(3t + 0.6i))`, spaced 9 pt, `DT.warnAmber` at `0.55 + 0.45·scale`.
- **Error** — broken line with a 8 pt gap, right half offset +1 pt, 1.6 pt `DT.errorAccent` dots at each break.

#### Progress spine (new)

A 1.5 pt hairline pinned 5 pt above the capsule's bottom edge, inset 12 pt each side. Track `.white.opacity(0.07)` (dark) / `.black.opacity(0.07)` (light), fill `DT.emberDark` / `#B5763C`.

Fill fraction: `0` recording · `0.45` transcribing · `0.84` cleaning · `1.0` on deliver. Fades in and out over 200 ms; **it must not be visible when there is no operation in flight.** Animate with `spineCurve` = `timingCurve(0.34, 1.1, 0.44, 1)` over 280 ms.

The fixed fractions are deliberate — a fake continuous bar would be dishonest, three real checkpoints are not. If WhisperKit ever exposes real transcription progress, feed it in between 0 and 0.45.

#### Success shows text, not a count

`case result(words: Int)` becomes `case result(tail: String)`. The tail is the **last 5 whitespace-separated words** of the delivered text, prefixed with a horizontal ellipsis when truncated: `…ship the HUD on Friday.`

Rendered 12.5 pt, primary ink, single line, truncating tail, in a 300 pt capsule beside a 34 pt tick canvas. Dwell **1.4 s** (`dwellSuccess`) then dismiss.

A count is a receipt; the tail is proof, and it lets someone catch a bad transcription without looking away from their cursor.

**Gate it behind `Settings.echoInsertedText`, default `true`.** Some users dictate passwords or medical notes; the setting belongs in the Privacy card as *"Show what was typed in the HUD"*. When off, fall back to the current word count.

**VoiceOver:** announce the tail, not the count — `"Inserted: …on Friday."`

#### Chip and timer expiry

Add `Settings.hotkeyLearnedAt: Date?`. Set it on first successful dictation; **reset it whenever the hotkey changes**. Show the chip while `now < hotkeyLearnedAt + 7 days`, otherwise never. Chip spec is unchanged (h 23, padding-h 8, radius 6, glyph 12.5 semibold, `HELD` 8.5 semibold kerning 0.5 opacity 0.6, `DT.chipInk*`).

Raise the elapsed-timer threshold from 3 s to **20 s**. Keep the existing promotions: at 60 s it goes to 14 pt semibold primary ink; under 30 s remaining it becomes `DT.warnAmber` bold `"0:24 left"`. Keep the sub-0.9 s `"Keep going"` primer.

#### Frame rate

`TimelineView(.animation)` currently never idles. Run at display rate while recording (it is tracking a live signal), **20 fps** while transcribing/cleaning (the coil and shimmer read identically), and **stop entirely** when hidden. `StatusIconAnimator` already does exactly this — mirror it.

#### Reduce Motion

Geometry is preserved; only movement is dropped.

| State | Reduce Motion |
| --- | --- |
| Listening | 9-dot meter, 4.8 pt dots, gap 6, lit count `round(amp · 9)`, unlit at 0.4 alpha, **updating at 10 Hz** |
| Transcribing / Polishing | 3 dots, 5.2 pt, opacity cycle only, 0.9 s period |
| Anything else | static 36 × 2 dim capsule |
| Success tick | drawn complete, not stroked on |
| State change | straight swap at the frame boundary, no tween |
| Spine | linear 200 ms, no overshoot |
| Summon | 130 ms fade, no rise (already implemented) |

---

### T7 — Menu-bar glyph: one new state

**File:** `StatusIcon.swift`

Add `case hello` to `StatusIconState`. It reuses the **listening** path exactly, with the envelope replaced:

```
amplitude = max(0, sin(2.2 · t))
y = mid + sin(0.85x + 7t) · 3.4 · amplitude · win(x/16)
```

(3.4 rather than listening's 3.2 — a fraction more presence.)

Add `StatusIconAnimator.playHello()`: a **one-shot**, three swells 700 ms apart, then return to `.idle`. It plays **once, on first launch only**, while the welcome step is on screen. It does not play under Reduce Motion.

Every existing glyph case — idle, listening, working, success, error, paused — is unchanged, including the 45%-alpha baselines and the 24×16 template-image size.

**Dock icon:** leave `Settings.showInDock` defaulting to **off**. A Dock icon for a menu-bar utility concedes that the menu bar failed; the fix is `hello` plus "I live up there." Keep the toggle under Advanced for notched-MacBook users whose status item genuinely gets hidden, and mention that case by name in Settings — not in onboarding.

**App icon:** no change. `appicon-1024.png` is already right — one ember stroke on near-black, no gloss, no microphone, legible at 16 pt because it is a single closed gesture with no interior detail. That property is the thing to protect if it is ever revisited. `appicon-1024-light.png` covers tinted contexts.

---

### T8 — Dashboard Home

**Files:** `DashboardView.swift`, `FeatureStores.swift`. See §04.

Window min becomes **1000 × 768** (was 1000 × 660). Sidebar unchanged at 212 pt. Content pane padding: 34 top, 30 horizontal, 30 bottom. Row gap 14.

**Delete** the greeting (`"Good afternoon."`) and the four equal stat cards. The greeting held the largest type on the pane and said nothing; four equal cards means no card is the point.

All cards: radius 12, fill `DT.cardDark`/`cardLight`, border `.white.opacity(0.09)`/`.black.opacity(0.08)`.

#### Row 1 — height 256 pt, fixed

**Left card, `1.55fr`, padding 24 × 22.**
- Eyebrow: `TIME BACK` — 11 pt, monospaced, letter-spacing 0.07em, `DT.ink2`.
- The number, 10 pt below, baseline-aligned run: `16` **68 pt bold, letter-spacing −0.045em, line-height 0.94**, primary ink · `h` 26 pt weight 600 secondary · `20` same as `16` · `m` same as `h`.
- Sentence, 14 pt below: 14.5 pt, line-height 1.55, secondary ink, max width 340 — *"Two working days you didn't spend typing, since March."* Allow **three lines**; that is why the row is pinned.
- Footnote row, 18 pt below and separated by a 1 pt hairline with 15 pt of padding above it: `38,412 words` · 3 pt dot `#514C42` · `412 takes` · dot · `12 days running`. All 12 pt, `DT.ink2`, gap 16.

Note **`38,412`** — thousands-grouped. The current build prints `38412`.

**Right card, `1fr`, padding 22 × 20 — "Your first words".**
- Eyebrow: `YOUR FIRST WORDS` — 11 pt monospaced, 0.07em, **`DT.moss`** (the one non-ember accent on the pane).
- Quote, 12 pt below, filling the card: 15 pt, weight 500, line-height 1.5, primary ink.
- Meta at the bottom: `14 March, 9:41 AM · in Notes` — 11.5 pt, tertiary ink.

#### Row 2 — week chart, content height ≈192 pt

Header row, baseline-aligned: `This week` (13 pt bold, primary) · **`minutes returned per day`** (11 pt, `DT.ink2`) · spacer · `3 h 04 m total` (11.5 pt, `DT.ink2`).

Seven bars, 124 pt band, gap 10, max bar width 52, `UnevenRoundedRectangle(topLeading: 6, bottomLeading: 2, bottomTrailing: 2, topTrailing: 6)`. Past days `.white.opacity(0.13)`/`.black.opacity(0.12)`; **today `DT.emberWave`**. Value label above each bar, 10.5 pt, `#6B6558`; today's is weight 600 `DT.emberDark`. Day letter below, 10 pt `DT.ink2`; today's weight 600 primary ink. Minimum bar height 4% of the band so a zero day is still a visible tick.

Words → **minutes**: words are the app's unit, nobody wants more words. Same 40 wpm divisor already used for "time saved".

#### Row 3 — height 214 pt, fixed

**Left, `1fr` — "Where you dictate".** Moved here from above the History list; it is the most human number in the app.

Title 13 pt bold. 14 pt below, a 10 pt stacked bar, radius 5, segment gap 1.5, segments at `DT.emberWave` stepped by 0.13 opacity per rank, remainder `.white.opacity(0.10)`. Then up to **four** legend rows, gap 9: 7 pt dot at the matching opacity · app name 12.5 pt primary · spacer · percentage 12.5 pt weight 600 primary. Hide the whole card until there are at least two apps.

(The current build shows six rows and a raw word count per row. Four rows and no raw count fits the fixed height and reads better; the full breakdown can stay on History.)

**Right, `1.15fr` — "Recent".** Header: `Recent` 13 pt bold · spacer · `See all` 11.5 pt `DT.emberLight`. **Three rows only.** Each: time 11 pt `DT.ink2` fixed 46 pt · app badge 10 pt bold `DT.ink2` on `.white.opacity(0.06)` radius 5 padding 6 × 2 · text 12.5 pt primary, single line, truncating tail. Rows 1–2 have a 1 pt hairline below. Footer pinned to the bottom: *"Stored on this Mac. Audio is discarded the moment it's transcribed."* 11 pt tertiary.

**Streak stays demoted.** A streak card creates an obligation; the brief asked for a reward. As a footnote it is a fact you can enjoy — and it cannot visibly *break*, which is the part that makes streaks punitive.

#### Store additions

- `firstEntry` — text + timestamp + app, persisted **separately from the history log**, so "Delete history…" can keep it. Ask once at deletion time.
- `firstUseDate` — for "since March".
- `minutesLastWeek: [Int]` — or derive from the existing `lastWeek` word counts at 40 wpm.
- Thousands-group every displayed integer.

---

## Copy pass — every string

Complete table in §06 of the design file. Apply all of it.

### The rule

Second person, present tense, contractions. **Report the outcome, never the mechanism.** No ellipses — if something is in progress the animation already says so. If a sentence can lose a word, lose it.

**The app says "I" only when asking for something or admitting a limit** — "So I can hear you", "macOS can't launch me itself". Never when reporting a fact: "Inserted 42 words" has no *I* in it and shouldn't. This is the rule that lets the welcome screen say "I live up there" without being twee.

**Never:** "we" · exclamation marks · jokes the user has to read twice (the old *"Hello from my own two vocal cords"*) · model names, hostnames, checksums or file paths outside a Details disclosure · apologies — say what to do next instead.

### HUD

| Now | Proposed |
| --- | --- |
| Keep talking… | Keep going |
| Transcribing… | Transcribing |
| Polishing… | Polishing |
| 42 words | …ship the HUD on Friday. |
| Hold and speak a little longer | Hold a moment longer |
| Microphone unavailable. / Open Sound Settings | No microphone. / Sound settings |
| Timed out. Audio kept. / Retry | Took too long — audio kept. / Try again |
| Copied instead — press ⌘V. / Grant Access | Copied instead — press ⌘V / Fix |

### Onboarding

| Now | Proposed |
| --- | --- |
| Speak. It types. | I live up there. |
| Hold a key, talk, let go — polished text appears at your cursor in any app. | No window to keep open, no Dock icon to hunt for. Just a small waveform in the menu bar, and a key you hold when you want to talk. |
| Get started | Let's go |
| Three quick permissions | Three switches, then we're done. |
| Everything happens on this Mac. Nothing is uploaded, ever. | macOS holds the keys, not me. |
| to hear you | so I can hear you |
| to type for you | so I can type for you |
| to feel the hotkey — one key, nothing else | so I can feel the key |
| Not listed? Click + and add OpenVoiceFlow from Applications. *(after failure)* | Clicked Allow and nothing happened? Open System Settings — click + and pick OpenVoiceFlow from Applications. *(always visible)* |
| Getting ready / Downloading the speech engine — one time, then everything works offline. | While that downloads — who am I typing for? / 412 of 981 MB · 5.4 MB/s · 2 min left |
| That didn't finish — check your connection and try again. | That stopped. Check your connection? |
| Your voice never leaves this Mac. | Downloaded once. After this, everything runs offline on this Mac. |
| Try it / Hold fn and say: "Hey, I'm using OpenVoiceFlow." | Say anything. / Hold fn and talk. Let go when you're done. |
| Waiting for you… | Waiting for you… *(unchanged)* |
| Skip this | Skip |
| That worked. You're set — hold the key in any app. ↗ | YOUR FIRST WORDS / You spoke for 4 seconds. Typing that would have taken 18. |
| Finish | Start using it |

Don't script the user's sentence. "Say anything" makes the result theirs — which is the whole reason it's worth keeping.

### Dashboard

| Now | Proposed |
| --- | --- |
| Good afternoon. / You've spoken 1,284 words today — about 32 minutes you didn't spend typing. | 16 h 20 m / Two working days you didn't spend typing, since March. |
| say something! | *(deleted)* |
| Words dictated · Time saved · Streak · This week *(4 cards)* | *(deleted — see T8)* |
| This week · words per day | This week · minutes returned per day |
| Nothing here yet / Hold fn in any app and say hello. Every take lands here — on this Mac only. | Nothing yet. / Hold fn anywhere and say hello. |
| Dictations land here — searchable, on this Mac only. | Stored on this Mac. Audio is discarded the moment it's transcribed. |
| Names and jargon Whisper gets wrong — corrected before cleanup ever runs. | Words I keep getting wrong. Fix them once. |
| Say the trigger, get the expansion — mid-dictation. | Say the short thing, get the long thing. |
| Try one: trigger "my address", expansion your street address. Then just say it. | Try "my address". Then just say it. |
| Cleanup adapts to where you're typing. Detected from the frontmost app. | How you sound, per app. |
| A two-minute interview that teaches cleanup your voice. Stored locally, editable, deletable. | Two minutes, and your name comes out right every time. |
| Off — raw transcript, nothing leaves this Mac | Off. Raw transcript, nothing leaves this Mac. |
| Your data — on this Mac only | Your data |

Menu-bar strings (`Ready`, `Hold Right ⌘ to dictate`, `Pause for 1 hour`, `Start Dictation`, the ordering, the separators) are already correct. Leave them.

---

## Motion

| Name | What moves | Curve | Reduce Motion |
| --- | --- | --- | --- |
| `snap` | Menu selections, toggles, chip appear/disappear | `spring(0.25, 0.90)` — existing | 100 ms cross-fade |
| `arrive` | Permission row unlocking, pane switch, card insert | `spring(0.30, 0.85)` — existing | Opacity only, 180 ms |
| `settle` | Window resize, sheet dismiss, big-number recount | `spring(0.45, 1.0)` — existing | Instant, no overshoot |
| `morph` **new** | HUD line between states. Interpolate the **points**, never cross-fade the paths. | 220 ms, `spring(0.22, 0.85)` | Straight swap at the frame boundary |
| `spine` **new** | Progress hairline 0 → 0.45 → 0.84 → 1.0 | 280 ms, `timingCurve(0.34, 1.1, 0.44, 1)` | Linear 200 ms, no overshoot |
| `grow` | HUD width change (172 → 300 → 330) | 200 ms, `snap` | Instant resize |
| `summon` | HUD appearing — 90 ms fade + 9 px rise | `cubic(0.34, 1.3, 0.44, 1)` — existing | 130 ms fade, no rise |
| `dismiss` | HUD leaving — 160 ms fade + 4 px down | ease-out — existing | Fade only |
| `hello` **new** | Menu-bar glyph, first launch only — 3 amplitude swells | 3 × 700 ms, `max(0, sin 2.2t)` | Does not play |
| `payoff` **new** | First-dictation moment: contents fade to 0 except the sentence; ring strokes itself once above it; sentence scales 0.98 → 1.0 | fade 260 ms · ring draw 900 ms ease-out · scale `settle` | Ring appears complete, no draw-on, no scale, 200 ms cross-fade |

**Principles.**
1. **Nothing loops forever.** Every animation is either driven by real input (the waveform is a voice) or bounded by a real operation (the coil stops when transcription stops). The breathing ring at 0.7 rad/s is the single exception, and it appears only on surfaces the user opened deliberately.
2. **Frame rate is a state, not a constant.** See T6.
3. **VoiceOver runs parallel, not after.** Existing labels are good. Two additions: success announces the tail rather than the count, and the payoff moment needs `.accessibilityAddTraits(.isHeader)` plus a posted announcement — otherwise the most important instant in the app is silent.

---

## New design tokens

Add to `DT`. Nothing existing changes.

| Token | Value | Used by |
| --- | --- | --- |
| `hudHeight` | `38` | HUD frame |
| `hudMin` / `hudMax` | `172` / `330` | HUD frame |
| `hudPad` / `hudGap` | `12` / `9` | HUD layout |
| `spineWeight` | `1.5` | HUD progress hairline |
| `morph` | `.spring(response: 0.22, dampingFraction: 0.85)` | HUD state change |
| `spineCurve` | `.timingCurve(0.34, 1.1, 0.44, 1, duration: 0.28)` | Progress fill |
| `dwellSuccess` | `1.4` | Success hold before dismiss |
| `heroNumber` | `68 pt / −0.045 em / .bold` | Dashboard time-back figure |

New `Settings` fields: `hotkeyLearnedAt: Date?`, `echoInsertedText: Bool = true`, `firstUseDate: Date?`.

### Unchanged, for the avoidance of doubt

Every colour in `DT`: `emberDark #E8974E`, `emberLight #B4661F`, `emberWave #C97B35`, `moss #7FAF8A`, `mossLight #4E7A58`, `errorAccent #E0523A`, `warnAmber #D99A3D`, `destructive #C7402C`, `hudMsgDark #EAE6DD`, `hudMsgLight #26221B`, `hudSideDark #96907F`, `hudSideLight #847D6E`, `dimWaveDark rgba(214,208,194,0.5)`, `dimWaveLight rgba(58,52,40,0.45)`, `chipInkDark #CFC9BB`, `chipInkLight #4A4437`, `winDark #1D1B18`, `winLight #FCFBF8`, `sideDark #191714`, `sideLight #F4F2EC`, `cardDark #211F1B`, `cardLight #FFFFFF`, `inkDark #EAE6DD`, `inkLight #26221B`, `ink2Dark #96907F`, `ink2Light #847D6E`. Radii `rControl 6`, `rCard 12`, `rWindow 14`. Springs `snap`, `arrive`, `settle`. All of `Voiceline`. All of `StatusIconRenderer`.

The HUD's light-mode accent is `Color(red: 181/255, green: 118/255, blue: 60/255)` (`#B5763C`) — note this is *not* `emberLight`, and it should stay as it is.

---

## Assets

Shipped, in `native/assets/`, included in this bundle:

| File | Size | Status |
| --- | --- | --- |
| `appicon-1024.png` | 1024² | **No change.** Used in the DMG frame and the Gatekeeper dialog mock. |
| `appicon-1024-light.png` | 1024² | **No change.** Tinted/light contexts. |
| `dmg-bg@2x.png` | 1320 × 800 | **Re-render with the new caption** — see T1. Ground, wave and chevron stay. |

Not in this bundle, unchanged: `favicon.svg`, `og-card.png`, `readme-banner.png`.

No new icon artwork is required by this redesign. Every glyph in the design file is generated from the existing `StatusIconRenderer` and `RingGlyph` math.

---

## Acceptance checks

**First run**
1. Fresh install → the DMG caption tells the user to open the app themselves and pre-warns about Gatekeeper.
2. First launch in **light mode** renders light. (Today it forces dark.)
3. Welcome step: the menu-bar glyph plays `hello` once; it does not replay on the second launch; it does not play under Reduce Motion.
4. Permissions: row 2's Allow is hidden until row 1 is granted. Granting Accessibility from System Settings **while the onboarding window stays frontmost** flips the dot within ~1 s.
5. The recovery hint is visible before anything fails.
6. Download step shows MB, rate and a stable ETA, and the Know-Me fields are usable while it runs.
7. "Try it" accepts *any* sentence; the payoff shows that sentence and the seconds-versus-typing comparison; VoiceOver announces it.
8. Relaunch → Home still shows those exact words with the correct date and app.

**HUD**
9. At rest it is 172 × 38.
10. Recording → transcribing shows the wave *becoming* the coil, not a cut.
11. The spine is invisible while recording, at 45% during transcription, and gone after dismissal.
12. Success shows the text tail; turning off `echoInsertedText` reverts it to a word count.
13. The chip is present on day 1 and gone on day 8; changing the hotkey brings it back for 7 days.
14. Reduce Motion: the 9-dot meter tracks level at 10 Hz; nothing tweens; nothing rises.
15. With the HUD hidden, no render callbacks fire.

**Dashboard**
16. Home fits 1000 × 768 with no clipping, in both appearances, with the sentence at three lines.
17. No integer renders ungrouped.
18. "Where you dictate" is hidden with fewer than two apps.
19. "Delete history…" asks before discarding the first-words entry.

---

## Files in this bundle

| File | What it is |
| --- | --- |
| `06-redesign.dc.html` | The design reference. Eight sections: 01 critique (with the current build recreated at 1:1 from the Swift), 02 first run (interactive, frames 0–7), 03 HUD (all six states live, both appearances, Reduce Motion variants), 04 dashboard, 05 identity, 06 copy pass, 07 motion, 08 tokens and capability list. |
| `support.js` | Runtime the prototype needs to render. Not part of the product. |
| `native/assets/*.png` | The three shipped assets referenced above, copied from the repo so the prototype renders standalone. |

Serve over HTTP and open `06-redesign.dc.html`. §02 and §03 are interactive.

Repo context lives in `github.md` at the project root: `shimoverse/openvoiceflow`, branch `main`, subtree `native/`, with a screen-to-source map.
