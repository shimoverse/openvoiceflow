---
name: product-film
description: "Build finished, award-style product films entirely in code — Apple-keynote-grade demo videos, launch films, ads, teasers, and trailers with an original synthesized score, sound design, and optional female voiceover, rendered deterministically (HTML stage → Playwright frames → ffmpeg) with no screen recording, no After Effects, no stock assets, and no paid services. Ships platform-ready variants: YouTube/web 16:9, TikTok/Reels/Shorts 9:16 with safe zones, square 1:1, and 4:5 feed. Use this skill whenever the user wants ANY promotional or demo video for a product, app, website, feature, or prototype — 'demo video', 'product video', 'launch video', 'promo', 'ad', 'trailer', 'teaser', 'explainer', 'hype video', 'video for my landing page', 'a Reel/Short/TikTok for my app' — even if they don't specify format, length, or how it should be made."
license: MIT
---

# Product Film Studio

You are acting as an award-level motion studio — the kind that makes
Apple keynote films and Google product spots. The deliverable is a
**finished, rendered MP4** with score (and usually voiceover), not a
storyboard, a prototype, or an HTML page. This pipeline has shipped
multiple polished narrated films; trust it and execute end to end.

**Portable by design**: this folder follows the open Agent Skills
standard (SKILL.md + references/ + assets/), so it works unmodified in
Claude Code (`.claude/skills/`), Codex CLI (`.agents/skills/`), Cursor,
Gemini CLI, and any agent with a shell — everything is plain markdown,
Python, Node, and sh. Paths are relative to this folder;
`assets/template/` is a complete working film project to copy and
reshape.

**What this makes**: launch films and feature demos (45–70 s), teasers
and ads (10–30 s, including A/B hook variants), logo stings (4–7 s,
mark + one line + one hit), kinetic-typography explainers, and
platform cuts of any of these. **When to reach elsewhere**: authentic
in-app footage required → screen-record instead; a long data-driven or
React-component-reusing video → a Remotion project may fit better. For
award-style product films with zero paid dependencies, this pipeline is
the tool.

## The idea

One HTML file is the film set. It exposes `window.seek(t)` — a pure
function that computes every pixel from a time `t`. Playwright screenshots
frame `N` at `seek(N/fps)` and pipes JPEGs straight into ffmpeg/x264.
Music and sound are synthesized in numpy; voiceover comes from edge-tts;
and every beat — visual, musical, narrated — reads from ONE timing file,
`timings.js`. That is what makes the result frame-accurate, deterministic,
re-renderable, and free.

## Phase 0 — The brief (2 minutes, don't skip)

Establish, from the user or the product's repo/site/screenshots:
1. Product name, one-line positioning, the 2–4 capabilities that matter,
   and the single **magic moment** (the hero demo).
2. **Platforms** → aspect(s) and duration. Defaults if unspecified:
   45–70 s landscape 1920×1080 flagship; offer a 9:16 cut if the product
   is consumer-facing. Read `references/formats.md` for the platform
   matrix, duration ladders, and 9:16 safe zones BEFORE storyboarding a
   vertical film.
3. Voiceover or not (default: yes for 30 s+, no for teasers under 20 s).
4. Brand: colors, logo. No logo available → design a geometric
   placeholder mark and say so in the delivery summary.

Only ask the user when a *product fact* is genuinely ambiguous — format,
craft, and pipeline decisions are yours to make. Proceed autonomously.

## Phase 1 — Environment (once per machine)

```bash
npm i playwright-core            # in the project dir (no browser download)
pip install numpy edge-tts imageio-ffmpeg
FF=$(python3 -c "import imageio_ffmpeg; print(imageio_ffmpeg.get_ffmpeg_exe())")
```
- `imageio-ffmpeg` ships a static ffmpeg WITH libx264+AAC — use it for
  every ffmpeg call; system builds often lack libx264. The template
  scripts auto-discover it (or honor `FF`/`CHROMIUM` env vars).
- Chromium: the template's `findChromium()` checks `CHROMIUM`,
  `PLAYWRIGHT_BROWSERS_PATH`, `~/.cache/ms-playwright`, system chrome
  paths. Nothing found → `npm i playwright && npx playwright install
  chromium` once.
- Font: download `InterVariable.ttf` from the official Inter GitHub
  release into `~/.fonts` + `fc-cache -f` (Linux) or install via Font
  Book (macOS). Verify with `fc-list | grep -i inter` before rendering —
  a fallback font silently ruins the type.

## Phase 2 — Project + storyboard + timings

Copy `assets/template/` to a working directory (e.g. `film/`). It renders
a complete 12 s placeholder film out of the box — your job is to replace
the demo scenes with the real storyboard, extending, not rewriting, the
machinery.

Write the storyboard as scenes with one idea each (structure guidance:
`references/stage-craft.md`), then encode it in `timings.js`:

- The object body must be **strict JSON** (double-quoted keys, no
  comments/trailing commas): Python reads it with `json.loads` after
  stripping the `window.TIMING =` wrapper; Node does the same. Never
  hardcode fps/duration/size anywhere else.
- Required keys: `fps`, `duration`, `width`, `height`, `scenes`
  (`{"s1": [start, end], …}`), `end.fade`. Add a named beat for every
  animation moment (paste, chips landing, button presses, money beat) —
  the score schedules SFX from these same numbers, which is why sound
  lands exactly on picture.

## Phase 3 — Build the stage (film.html)

This is the creative lift. Rules that make it filmic (full patterns and
art direction in `references/stage-craft.md` — read it now):
- **No CSS animations or transitions anywhere.** Everything derives from
  `t` inside `seek(t)`. Frame N = `seek(N/fps)` + screenshot.
- Scenes are absolutely-positioned layers, faded by the `win()` envelope.
- Use the template's easing kit (`expoOut` for entrances, `easeInOut`
  for travel), word-by-word reveals, and the flying-element pattern.
- Keep the grain/vignette/fade stack and `window.filmReady` (fonts gate).
- Recreate the product UI as crisp HTML/CSS mockups — never screen
  recordings (they don't animate deterministically and show stale data).
- Portrait films: compose inside the safe area (`references/formats.md`).

## Phase 4 — Stills loop (mandatory gate)

`node stills.mjs 2.4 7.1 10.6 …` (midpoint of every scene) and LOOK at
each image like a poster. Fix composition, spacing, spelling, overlaps,
safe zones. Iterate until every still could ship. Only then render.
Skipping this gate is how films come out embarrassing.

## Phase 5 — Sound (read `references/sound.md` for the full recipes)

1. `vo.py`: put the narration lines with `(start, must_end_by)` budgets;
   it synthesizes, trims, enforces budgets, writes `vo/manifest.json` +
   `captions.en.vtt`. Over budget at +12% → shorten the copy.
2. `score.py`: author pads/pulse/plucks/SFX from `timings.js` beats on
   top of the template's instrument kit. Laws: zero noise-sweep whooshes
   (they read as static); sfx bus silent at every scene boundary ±0.2 s;
   exactly one money hit; VO ducks the music, and the hero demo plays
   with no narration.
3. Verify numerically from the printed report (per-scene RMS arc,
   boundary audit all OK, VO presence ≥ +6 dB). You can't listen —
   measure.

## Phase 6 — Render + finish

```bash
node render.mjs        # frames → film_video.mp4  (~2-3 min per 2000 frames)
python3 vo.py && python3 score.py
OUT=product-film.mp4 POSTER_T=<hero-resolved-seconds> bash finish.sh
```
`finish.sh` muxes (`-c:v copy`, AAC 176k, `+faststart`), extracts the
poster at the film's resolved hero moment, and decode-verifies (must
print nothing). Then build a contact sheet (stills every ~2 s tiled with
ffmpeg `xstack`) and scan it for transition glitches.

For each additional platform: copy the project dir, change
`width`/`height` in `timings.js`, restage layouts per
`references/formats.md` (stack, bigger type, safe zones — never crop),
adjust durations if the platform wants a shorter cut, re-render.

## Phase 7 — QA gates (the run is not done until all pass)

- [ ] Stills from every scene midpoint reviewed and art-directed before
      the full render; contact sheet scanned after.
- [ ] Output duration == `TIMING.duration`; resolution matches the
      target platform; H.264 High yuv420p + AAC; decode-verify silent.
- [ ] Every VO line within budget; hero demo window has no narration;
      captions cue count == line count.
- [ ] Score audit: boundary rows all OK, one money hit, no clipping.
- [ ] Portrait: nothing critical outside the safe area.
- [ ] Content: mock data only, relative dates only, placeholder
      identity, third-party products shown respectfully, brand-mark
      status (official vs placeholder) noted in the summary.

**Deliver**: the MP4(s) per platform, `poster.jpg`, `captions.en.vtt`,
and the film source directory (re-renderable end to end). Close with a
short summary: what was built, per-platform variants, any deviations,
and whether the mark was official or a placeholder.
