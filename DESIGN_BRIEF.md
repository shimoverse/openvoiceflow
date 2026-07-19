# Design Brief: OpenVoiceFlow — end-to-end redesign (macOS app + website)

> Hand-off prompt for a design-focused agent ("Claude Design"). Grounded in the
> shipping Python app, the native Swift rewrite (PR #29), and the current
> `docs/` website. Deliverables land back in this repo: app design feeds
> `native/`, website design feeds `docs/`.

## Your role

You are the design lead for OpenVoiceFlow. Redesign the ENTIRE product
experience from scratch — brand, macOS app, and website. There are no legacy
users and no existing brand equity to preserve: you have a blank canvas. The
bar is an Apple Design Award. The direct competitor to beat on every surface is
**Wispr Flow** — we must feel more alive, more native, more trustworthy, and
faster than they do.

## What the product is

OpenVoiceFlow is free, open-source voice dictation for macOS. The core loop:

**Hold a key → speak → release → polished text appears at your cursor in any app.**

- Transcription runs 100% locally (Whisper on-device — WhisperKit/CoreML in the
  native app). Optional AI cleanup of the raw transcript via local Ollama or
  cloud LLMs (Anthropic, OpenAI, Groq, OpenRouter) — user's choice, local-first
  by default.
- Positioning: the $0, privacy-first alternative to Wispr Flow ($144/yr). "Your
  voice never leaves your Mac" is a core promise and should be a core aesthetic.
- Distribution: Developer-ID signed + notarized DMG from our website (not the
  App Store).
- The app is being rewritten natively in Swift/SwiftUI (menu bar app via
  MenuBarExtra, macOS 13+). Design for the native app as the canonical target.

## Feature inventory (design for exactly these — do not invent others)

1. Push-to-talk dictation via a global hotkey (default Right ⌘; also fn/🌐
   Globe, Right Option, Right Control). Hold-to-talk, release-to-transcribe.
2. Live recording HUD with a real-time waveform driven by mic levels.
3. Pipeline states: listening → transcribing (local Whisper) → AI cleanup
   (optional) → auto-paste at cursor. Plus error states (mic unavailable, paste
   blocked, model missing).
4. Menu bar app: status icon + dropdown menu (start/stop, hotkey picker, model
   picker, backend picker, open dashboard, pause, quit).
5. Dashboard window: stats (words dictated, time saved, streaks, WPM),
   transcript history (daily logs), personal dictionary (names/jargon
   corrections), snippets (voice-triggered text expansion), per-app writing
   styles (e.g. casual in iMessage, formal in Mail), settings.
6. Onboarding: welcome → 3 permission grants (Microphone, Accessibility, Input
   Monitoring) with in-context priming → hotkey choice + rehearsal → model
   download with progress → first successful dictation ("aha" moment).
7. "Know-Me" interview: a short conversational Q&A that learns the user's name,
   jargon, and tone to personalize cleanup.
8. Sparkle in-app updates; API keys stored in Keychain; everything works
   offline with the local backend.

## Scope — redesign ALL of the following

### A. Brand identity

- Name stays OpenVoiceFlow. Design: logo + wordmark, full color system (light +
  dark), typography (system SF Pro is acceptable; justify any display face),
  iconography rules, motion language (springs, durations, easings — specified
  numerically), and a sound-design direction (start/stop/success/error earcons
  — describe character, not files).
- A signature "voice" motif. The waveform IS the brand — one recognizable
  waveform identity that recurs in the app icon, HUD, menu bar animation,
  website hero, and social cards. This is the thing people should remember us
  by, the way Wispr Flow's bottom bar is remembered. Make ours better: organic,
  responsive, calm — not an EQ cliché, not the generic
  AI-sparkle-purple-gradient cliché.
- Privacy as aesthetic: local-first should FEEL like a design choice — calm,
  contained, no cloud imagery, no data-in-flight metaphors.

### B. App icon + Dock presence

- macOS app icon (1024pt master, squircle grid, proper depth/lighting for
  modern macOS; provide dark-mode and tinted-mode variants per current Apple
  HIG).
- The Dock icon appears only when the dashboard is open (menu bar app
  otherwise) — design the About window and a delightful Dock bounce-free
  presence.
- DMG installer window background (drag-to-Applications layout, 660×400 @2x) —
  first brand touchpoint after download; make it feel like unboxing.

### C. Menu bar icon (critical surface)

- Template-image states at menu bar size (~18pt, monochrome, auto light/dark):
  idle / listening (subtle live animation) / transcribing / cleanup / success
  flash / error / paused. Must read at a glance from peripheral vision.
- The full dropdown menu: structure, ordering, iconography, and the
  hotkey/model/backend submenus. SwiftUI MenuBarExtra idioms.

### D. The recording HUD — "the waves" (THE hero surface, spend the most effort here)

- A floating, non-activating panel (NSPanel — it must never steal focus from
  the app the user is dictating into). Choose and justify placement (Wispr Flow
  uses a bottom-center pill; consider bottom-center, near-cursor, or
  notch-adjacent — pick the best and say why).
- Design every state with motion specs:
  1. Summon (hotkey down): how it enters. Target feel: <100ms, weightless.
  2. Listening: live waveform reacting to actual voice amplitude; distinguish
     silence vs speech; show elapsed time subtly; show which hotkey is held.
  3. Release → transcribing: waveform gracefully collapses into a processing
     state.
  4. Cleanup (when enabled): distinct-but-quiet second phase.
  5. Success: the text "arrives" at the cursor — design the handoff moment.
  6. Errors: mic gone, timeout, paste blocked (each with one-line recovery
     action).
  7. Long-dictation mode (multi-minute), and a max-duration warning state.
- Variants: light/dark, Reduce Motion (fully designed, not an afterthought),
  Reduce Transparency, multi-monitor rules, and behavior over full-screen apps.

### E. Dashboard window

- A native SwiftUI sidebar app (think System Settings / Linear-level polish):
  Home (stats hero — make "words dictated / time saved vs typing" feel
  rewarding), History (searchable daily transcripts), Dictionary, Snippets,
  Styles (per-app), Know-Me profile, Settings (hotkey, model, backend + API
  keys, sounds, updates, privacy). Design empty states, loading states, and the
  data-viz for stats.

### F. Onboarding flow

- Screen-by-screen: value promise → each permission with an in-context
  explainer of WHY (mic = hear you, accessibility = paste for you, input
  monitoring = hear the hotkey) and what macOS will show → hotkey selection
  with a keyboard visual highlighting the actual key → model download progress
  (can take minutes: design the wait to build trust — show what's happening
  locally) → guided first dictation with live success feedback.
- Failure paths: permission denied, download failed, unsupported Mac.

### G. Website (full redesign — static HTML/CSS/JS on Vercel, no framework)

Pages today: index (hero, how-it-works, 60-second install, Wispr Flow
comparison, backend picker, FAQ), download.html (DMG downloads + checksums),
install.html, how-it-works.html. Redesign all of it:

- Landing: hero that demos the actual loop (an animated waveform → text moment
  above the fold), the privacy story, the $0 vs $144/yr comparison table,
  social proof placeholder, FAQ. It must make a Wispr Flow user feel silly not
  to switch.
- Download page: architecture picker (Apple Silicon / Intel), checksums
  presented in a trust-building way, notarization badge story.
- Docs/how-it-works with the same design system.
- Open Graph / social cards, favicon set, GitHub README header banner.
- Constraints: fast (Lighthouse ~100), accessible (WCAG AA), dark + light via
  prefers-color-scheme, no heavy JS libraries; the hero animation must be
  CSS/canvas, self-contained.

## Hard technical constraints (design within these)

- macOS 13+, SwiftUI + AppKit interop. Menu bar icons are template images
  (monochrome).
- HUD is a non-activating NSPanel; never takes focus; visible on all Spaces.
- Waveform is driven by real-time RMS/amplitude buckets from AVAudioEngine
  (~30–60fps).
- Respect: Reduce Motion, Reduce Transparency, Increased Contrast, VoiceOver
  (label every state change; the HUD state must be announced), Dynamic Type
  where applicable.
- Prefer SF Symbols; custom symbols allowed if they follow symbol grid/weights.
- Everything ships in light AND dark, Retina @1x/@2x.

## Benchmarks (study, then beat)

- Wispr Flow (the target: their bottom pill, onboarding, and site — find what's
  weak: genericness, cloud dependence, subscription friction — and counter it),
  Superwhisper, MacWhisper, Raycast (menu bar + command aesthetics), CleanShot
  X (menu bar app polish), Things 3 / Linear (restraint + motion), Arc (brand
  courage).
- Judge yourself against Apple Design Award criteria: Delight & Fun,
  Interaction, Visuals & Graphics, Innovation.

## Design principles (in priority order)

1. Invisible until summoned; unmistakable when active.
2. The voice made visible — one waveform identity everywhere.
3. Feels like Apple made it, remembered like nobody else made it.
4. Privacy is the aesthetic: calm, local, contained.
5. Zero jank: every animation has a spec; every state has a design; no unstyled
   moment.

## Deliverables (in this order)

1. Design system: tokens (color light/dark, type scale, spacing, radii,
   elevation, motion curves/durations as numbers), component library, the
   waveform motif spec.
2. High-fidelity mockups of EVERY surface and state listed above (HTML/CSS or
   React artifacts are ideal — interactive state toggles where it helps, e.g.
   the HUD states).
3. The redesigned website as production-quality HTML/CSS.
4. Asset specs: app icon master + variants, menu bar template icon set (all
   states, @1x/@2x), DMG background, OG cards, favicon.
5. Motion spec sheet: every transition with duration/easing/spring values +
   Reduce Motion equivalents.
6. A one-page rationale: the 5 decisions that make this award-worthy, and
   specifically where and why it beats Wispr Flow.

Start with the design system + the recording HUD (the "waves") — that's the
heart. Show me the HUD in all 7 states before going wide on the rest.
