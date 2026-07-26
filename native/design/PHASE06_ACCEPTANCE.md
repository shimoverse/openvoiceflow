# Phase 06 — acceptance checks

The 19 checks from the design handoff README, walked against the shipped
0.5.0 code. Three verdicts:

- **CODE** — the behaviour is in the source and readable there. A Linux CI box
  compiles it but cannot run it, so nothing here is a claim that it *looked*
  right.
- **DEVICE** — needs a real Mac: an actual TCC grant, the OS Reduce Motion
  switch, VoiceOver, a light-mode login, or Gatekeeper.
- **CI** — asserted by an automated check that runs on every push or release.

Every check below is CODE at minimum. The DEVICE column is what still needs a
human in front of a screen.

## First run

| # | Check | Verdict | Where |
| --- | --- | --- | --- |
| 1 | DMG caption tells the user to open the app themselves and pre-warns about Gatekeeper | CODE + CI | `native/scripts/render-dmg-bg.py:55-56`; `build-app.sh` now **fails** the build if the app or DMG is unstapled or `spctl` rejects it — previously `\|\| true` swallowed that |
| 2 | First launch in light mode renders light | CODE, **DEVICE** | The forced `.preferredColorScheme(.dark)` is gone; every surface reads `@Environment(\.colorScheme)` and resolves through `OBPalette` / `DT`. Needs a light-mode Mac to confirm no hardcoded hex survived visually |
| 3 | Menu-bar glyph plays `hello` once, not on second launch, not under Reduce Motion | CODE, **DEVICE** | `StatusIcon.swift:161-186` — guarded by `accessibilityDisplayShouldReduceMotion` and a one-shot task; `OnboardingView.swift:193-197` posts it once per run, and onboarding itself only shows on first run |
| 4 | Row 2's Allow hidden until row 1 granted; a grant from System Settings flips the dot in ~1 s **while the window stays frontmost** | CODE, **DEVICE** | `isReachable(_:)` gates each row; `Permissions.watch(every: .milliseconds(600))` polls instead of relying on `didBecomeKeyNotification`, which never fires when the window never lost key. The 600 ms poll is the fix for exactly this case — but only a real grant proves it |
| 5 | The recovery hint is visible before anything fails | CODE | `escapeHatch` is rendered unconditionally in the permissions step, not behind a failure branch |
| 6 | Download shows MB, rate and a stable ETA; Know-Me fields usable while it runs | CODE, **DEVICE** | `DownloadMeter` — decimal MB, rolling 3 s rate, ETA held ≥ 1 s so it can't jitter. `Transcriber.warmUp` reports raw bytes (a percentage can't yield a rate or an ETA). `KnowMeInterview` renders inline beside the meter. Real timings need a real download |
| 7 | "Try it" accepts any sentence; payoff shows it plus the seconds-versus-typing line; VoiceOver announces it | CODE, **DEVICE** | The old step was a hardcoded mockup — it now takes whatever was said. `spokenComparison` uses the same 40 wpm divisor as the dashboard so the two can't disagree. `NSAccessibility.post(.announcementRequested)` carries **both** lines. VoiceOver itself is device-only |
| 8 | Relaunch → Home still shows those exact words, correct date and app | CODE | `HistoryStore.firstEntry` persists to `first_entry.json` on write, and migrates existing installs from the oldest surviving take |

## HUD

| # | Check | Verdict | Where |
| --- | --- | --- | --- |
| 9 | At rest it is 172 × 38 | CODE | `DT.hudMin` / `DT.hudHeight`, applied at `HUDController.swift:437`. Down from 290 × 44 |
| 10 | Recording → transcribing shows the wave *becoming* the coil, not a cut | CODE, **DEVICE** | `HUDGeometry` samples all five shapes to a uniform 128 points and lerps point-for-point, driven by a closed-form spring off the Canvas clock. Structurally it cannot cross-fade — but whether it *reads* as a morph is a thing you watch, not a thing you grep |
| 11 | Spine invisible while recording, 45 % during transcription, gone after dismissal | CODE | `spineFraction` returns `nil` — absent, not zero-width — outside transcribing/cleaning/result. 0.45 / 0.84 / 1.0 are three real checkpoints, not a synthesised percentage |
| 12 | Success shows the text tail; `echoInsertedText` off reverts to a word count | CODE | `AppController.tail(of:words:echo:)`; the toggle is in Settings |
| 13 | Chip present on day 1, gone on day 8; changing the hotkey brings it back for 7 days | CODE, **DEVICE** | `shouldShowHotkeyChip` against `settings.hotkeyLearnedAt`; `updateHotkey` clears the stamp. Day 8 needs either a clock change or a hand-edited settings file |
| 14 | Reduce Motion: 9-dot meter tracks level at 10 Hz; nothing tweens; nothing rises | CODE, **DEVICE** | `reducedMotionIndicator` — `TimelineView(.periodic(by: 0.1))`, and every `withAnimation`/`.animation` on the HUD path is nil'd or linearised under `reduceMotion` |
| 15 | With the HUD hidden, no render callbacks fire | CODE | `case .hidden: EmptyView()` — no `TimelineView` is constructed at all, so there is no clock to tick. The panel is also `orderOut`'d |

## Dashboard

| # | Check | Verdict | Where |
| --- | --- | --- | --- |
| 16 | Home fits 1000 × 768 with no clipping, both appearances, sentence at three lines | CODE, **DEVICE** | `.defaultSize(width: 1000, height: 768)` and `minHeight: 768`. Whether a three-line first sentence clips at that height is a layout fact only a render settles |
| 17 | No integer renders ungrouped | CODE | `Int.grouped` throughout. Three cases escaped the first pass and were fixed: four-digit hour counts, the HUD word-count fallback (which also read "1 words"), and the typing comparison |
| 18 | "Where you dictate" hidden with fewer than two apps | CODE | `if dist.count >= 2` — the card doesn't exist below that, rather than rendering empty |
| 19 | "Delete history…" asks before discarding the first-words entry | CODE | A `confirmationDialog` with two distinct destructive paths: "Delete, keep my first words" and "Delete everything" |

## Deliberately not done

**T3's dotted ember leader line** from the onboarding window to the menu bar.
The README permits omitting it if it proves fragile, and it is: the path has to
be computed across arbitrary multi-display arrangements where the menu bar may
be on a different screen than the window, and a leader line that points at the
wrong corner is worse than none. The `hello` glyph animation (check 3) carries
the same message — "I live up there" — without needing to draw across screens.

## What a Mac has to confirm

Checks **2, 3, 4, 6, 7, 10, 13, 14, 16**. Grouped by what you actually have to
do:

1. **Light mode** — log in with Appearance: Light, run first-run onboarding
   end to end, then open the dashboard. Looking for any surface that stayed
   dark (2, 16).
2. **A real permission grant** — at the permissions step, leave the onboarding
   window frontmost, grant Accessibility in System Settings, and watch the dot.
   It should flip within about a second without clicking back into the app (4).
3. **Reduce Motion on** — System Settings ▸ Accessibility ▸ Display ▸ Reduce
   Motion. The menu-bar glyph must not wave (3); the HUD must show nine dots
   tracking your voice, with nothing tweening or rising (14).
4. **VoiceOver on** — at the payoff step, confirm it speaks the sentence *and*
   the typing comparison (7).
5. **A real model download** — watch the meter for a jittering ETA, and type
   in the Know-Me fields while it runs (6).
6. **Watch the HUD morph** — hold the key, speak, release. Recording → the
   coil should read as one line changing shape, not two drawings swapping (10).
7. **Day 8** — set the clock forward or edit `hotkeyLearnedAt`; the HELD chip
   should be gone, and changing the hotkey should bring it back (13).

Check 1's Gatekeeper flow is asserted in CI now, but the first person to
download the real 0.5.0 DMG should still confirm the Open button appears.
