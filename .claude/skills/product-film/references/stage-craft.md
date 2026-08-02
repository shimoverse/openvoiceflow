# Stage craft: making HTML read as an award-winning film

The template gives you the machinery. This file is the taste — patterns
proven across shipped films. Read before writing scenes.

## Art direction

- **Dark stage, glowing product.** A near-black stage (#0A0D13-ish, not
  pure black) with a soft radial accent glow, deep vignette, and 5%
  deterministic grain. Light-themed app UIs floating on that stage with
  huge soft shadows (`0 50px 130px rgba(0,0,0,.6)`) read as cinema.
  Dark-themed apps: raise the stage a touch lighter so the window still
  separates.
- **Derive the palette from the product's brand.** One accent color used
  everywhere (glyphs, kickers, canvas strokes); never borrow another
  product's palette. Keep 2–4 supporting hues for category chips only.
- **Typography: Inter** (`InterVariable.ttf` from the official Inter
  GitHub release → `~/.fonts` + `fc-cache -f` on Linux). Big lines at
  `font-variation-settings: "wght" 620–660`, letter-spacing −0.03em.
  Monospace kickers (`SMART CAPTURE`) in the accent color, letterspaced
  +0.15em, are the cheapest "designed" signal there is.
- **UI mockups are loving idealizations**: real window chrome
  (traffic-light dots), hairline borders (`rgba(20,40,80,.13)` on
  light), rounded 12–18 px, believable 15–18 px UI type, real feature
  names, mock-but-believable data. Never lorem ipsum, never gray-bar
  wireframes — recreate the actual product honestly.
- **No stock footage, no emoji, no gradient-of-the-week.** Restraint is
  the award look: one idea per scene, generous negative space, cuts on
  the musical pulse.

## Film structure that works (60–70 s flagship)

1. **The problem, dramatized** (0–15 s) — not screenshots: the *feeling*
   (scattered fragments, a failed search, an anxious deadline chip).
2. **Thesis line** (one sentence, word-by-word reveal).
3. **Brand reveal** (mark draws itself in; the musical pulse starts here).
4. **The hero demo** (10+ uninterrupted seconds of the product's magic
   moment, VO silent — the moment carries itself).
5. **2–3 fast feature cuts** (~3.5 s each: kicker + headline + one card,
   one motion each).
6. **The differentiator** (privacy / price / speed — whatever the product
   would put on a billboard).
7. **End card** (mark + name + positioning line, long musical resolve,
   fade from `end.fade`).

15–30 s cuts: problem (compressed) → hero → end card. Never squeeze all
seven beats into 20 seconds.

## Motion patterns (all pure functions of t)

```js
// scene visibility — every scene, every frame
el.style.opacity = win(t, a, b, 0.3, 0.45);

// card/window entrance: rise + settle
const p = expoOut((t - beat) / 0.8);
el.style.opacity = p;
el.style.transform = `translateY(${(1 - p) * 60}px) scale(${0.97 + p * 0.03})`;

// word-by-word headline (the keynote feel)
revealWords(list, t, start, 0.09 /*per word*/, 0.55 /*dur*/);

// element flying from A to B with an arc (chips, snapshots)
const q = easeInOut((t - beat) / 0.62);
const x = lerp(x0, x1, q), y = lerp(y0, y1, q) - Math.sin(q * Math.PI) * 46;
el.style.transform = `translate(${x}px, ${y}px) scale(${0.9 + 0.1 * q})`;

// typing = string slice; caret blink = Math.floor(t * 2.2) % 2
// button press: scale dip 1 → 0.94 → 1 over 0.22s with sin(π·p)
// money-beat pop on a container: 1 + 0.006 * Math.sin(clamp01((t-beat)/0.3) * Math.PI)
```

Canvas painters (brand marks, waveforms, drawn borders) follow the same
rule: progress = `easeInOut((t - beat) / dur)`, geometry from `t`, glow
via `shadowColor`/`shadowBlur`. A rounded-rect border that draws itself:
`ctx.setLineDash([perimeter * progress, perimeter])`.

Never call `Date.now()` or `Math.random()` in the render path — use the
`hash(n)` helper where randomness is needed. Determinism is the trick.

## The hero demo pattern

Give the product's magic moment 10+ seconds and your best easing:
1. Show the trigger honestly (paste, keypress, click) with a tonal pop.
2. A visible beat of "the product thinking" (a scan sweep, a spinner) —
   1–2 s of anticipation before the payoff.
3. The payoff lands in stages (chips landing one by one, each with a
   small pop), building to the last one — which gets the film's ONE big
   tonal hit and a subtle container pop.
4. A settle state that proves completion (counts, a check, "All sorted").

## The stills loop (mandatory)

Art-direct on stills BEFORE any full render:
1. Render a still at the midpoint of every scene.
2. Look at each like a poster: composition, spacing, spelling, overlap,
   dead zones, safe areas (portrait).
3. Fix, re-render those stills, repeat until every frame could ship.
4. After the full render, tile stills every ~2 s into a contact sheet
   (ffmpeg `xstack`) and scan again — transitions hide sins that
   midpoints miss.

## Content rules (demo data)

- Mock-but-believable data only; generic personas ("Priya", "Sam"),
  generic projects ("Q3 launch readiness"). Never a real person's data.
- No absolute past dates — relative labels ("Yesterday", "Today",
  "Tomorrow · 9:00 AM") keep the film evergreen.
- Placeholder identity ("Your name / Your title") unless the client
  provides one.
- Third-party products (paste targets, integrations) appear briefly and
  respectfully, no claims about them.
- If no official logo is available, design a simple geometric placeholder
  mark, and SAY SO in the delivery summary so it can be swapped.
