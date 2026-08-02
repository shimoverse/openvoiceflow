# Platform formats: sizes, durations, safe zones, restaging

One master film per aspect ratio. Because the stage is HTML, re-rendering
at a new resolution with a restaged layout costs minutes — so NEVER
center-crop a 16:9 master into 9:16. Crops amputate composition; restages
keep the film award-grade in every frame. Ask which platforms matter,
build the primary aspect first, then restage.

## The four masters

| Master | Resolution | Use for |
|---|---|---|
| Landscape 16:9 | 1920×1080 (or 3840×2160) | YouTube, website embeds, X/Twitter, LinkedIn, keynotes, press kits |
| Portrait 9:16 | 1080×1920 | TikTok, Instagram Reels, YouTube Shorts, Snapchat, Stories |
| Square 1:1 | 1080×1080 | Instagram/Facebook/LinkedIn feed, X in-feed |
| Vertical feed 4:5 | 1080×1350 | Instagram/Facebook feed posts (more screen than 1:1) |

All platforms: MP4, H.264 High profile, yuv420p, AAC. 30 fps is the
sweet spot (60 only for gaming/motion-heavy). CRF 19 + preset medium is
visually lossless at these sizes and uploads fast.

## Duration targets by platform (2026)

| Platform | Hard limit | What actually performs |
|---|---|---|
| YouTube (long-form) | 12 h | 45–90 s product film; 2–3 min deep demo |
| YouTube Shorts | 3 min (was 60 s pre-Oct 2024) | 20–35 s |
| Instagram Reels | 3 min in-app record; up to 20 min upload | 15–30 s |
| TikTok | 10 min in-app; longer uploads | 15–34 s; hook lands < 2 s |
| Instagram/FB feed | — | 15–45 s (1:1 or 4:5) |
| LinkedIn | 10 min | 30–90 s, professional tone |
| X/Twitter | 2:20 organic | 20–45 s |
| Website hero / landing page | — | 40–75 s with a poster frame |

Duration ladder from one storyboard: the 60–70 s flagship (landscape) →
a 25–30 s cut (drop the middle feature beats, keep problem → hero moment
→ end card) → a 15 s teaser (hook + money shot + logo). Shorter cuts are
new `timings.js` files over mostly the same scenes — cut scenes, don't
squeeze them; a rushed film reads cheap.

## Vertical (9:16) safe zones — critical, UI covers your pixels

The platform UI overlays your video. On a 1080×1920 frame keep every
element that must be read inside the safe area; let backgrounds bleed
full-frame.

| Zone | TikTok | Reels | Shorts | Union (design to this) |
|---|---|---|---|---|
| Top (tabs/search/channel) | ~130 px | ~120–220 px | ~80–200 px | **top 220 px clear** |
| Bottom (caption/CTA/music) | ~484 px (ads ≥ 370–500) | ~250–420 px | ~200 px | **bottom 500 px clear** |
| Right (like/comment/share rail) | ~140 px | ~130 px | ~120 px | **right 140 px clear** |
| Left | ~44 px | ~44 px | ~44 px | **left 60 px clear** |

Rule of thumb: compose all type and UI mockups inside the middle
**880×1200** region of the 1080×1920 frame (x 60–940, y 220–1420).
In the film HTML, implement this as a padded inner container — then
verify with a still: draw nothing critical outside it. Square/4:5 need
no reserved UI zones, just breathing room (~80 px margins).

## Restaging 16:9 → 9:16 (not cropping)

- **Stack, don't shrink.** Side-by-side compositions become vertical
  stacks (headline above, card below). One idea per scene matters even
  more in portrait.
- **Type up ~1.25×**, max-widths down (headlines ~90% of width, 2–3
  words per line reads best on phones).
- **App windows**: show a phone-shaped or narrowed card, or zoom into
  the one panel that matters — a full desktop window scaled to fit
  1080 wide is unreadable. Crop the window composition, not the render.
- **Hook first**: portrait viewers decide in ~2 s. Move the most
  arresting visual (the money shot or a bold claim) into the first
  2 seconds; the slow atmospheric open that works on YouTube dies here.
- **Captions**: burn nothing into the bottom 500 px; ship
  `captions.en.vtt` and let the platform render captions, or place
  burned-in caption text mid-frame.
- Grain, vignette, glow, fades all carry over unchanged — they are
  resolution-independent in the template.

## Poster frames

Every deliverable ships with a poster JPEG (for `<video poster=…>`,
YouTube thumbnail base, or feed preview): pick the frame where the
product's hero moment is fully resolved — never a transition frame.

## Extensions

**A/B hook variants (ads).** Paid platforms reward testing the first
2–3 seconds. Because the film is data, a variant = a copy of the project
with only the hook scene's content/timings changed — everything after
the cut is byte-identical. Name outputs `<film>-hook-a.mp4`,
`<film>-hook-b.mp4` and keep one shared poster.

**Localization.** VO lines live in one table in `vo.py`; edge-tts ships
quality neural voices per locale (e.g. `es-ES-ElviraNeural`,
`de-DE-KatjaNeural`, `fr-FR-DeniseNeural`, `hi-IN-SwaraNeural`,
`ja-JP-NanamiNeural`, `pt-BR-FranciscaNeural`). A localized master =
translated LINES + re-run vo/score/finish; keep budgets, and expect
translated lines to run ~20% longer — shorten copy rather than speeding
past +12%. On-screen text needs translating in film.html too.

**GIF / WebM for READMEs and Slack.** From the finished MP4:
```bash
$FF -y -i film.mp4 -vf "fps=12,scale=800:-1:flags=lanczos,split[a][b];[a]palettegen=max_colors=128[p];[b][p]paletteuse=dither=bayer" out.gif
$FF -y -i film.mp4 -c:v libvpx-vp9 -crf 34 -b:v 0 -an out.webm   # muted autoplay embeds
```
Keep GIFs under ~15 s / 800 px wide or the file balloons.

**4K masters.** Set width/height to 3840×2160 only for keynote screens
or YouTube features; double type sizes rather than scaling the stage
(crisper), and expect ~4× render time.
