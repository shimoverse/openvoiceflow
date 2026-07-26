#!/usr/bin/env python3
"""Render native/assets/dmg-bg@2x.png — the DMG window background.

Every value here comes from the phase-06 handoff (T1). The ground, the dotted
ember wave and the chevron are unchanged from the shipped asset; only the
caption changed, from a checksum note nobody reads off a disk image to the two
lines that pre-empt Gatekeeper:

    Then open it from Applications.
    macOS can't launch me itself. If it says "downloaded from the Internet",
    click Open.

Canvas 1320 x 800 px @2x = 660 x 400 pt, so every pt below is doubled on the
way out.

Typography note: this renders with DejaVu Sans, the font available on the Linux
build host. The design specifies SF-style weights (600) and −0.01em tracking,
which DejaVu approximates rather than matches — re-run on a Mac with
OVF_DMG_FONT/OVF_DMG_FONT_BOLD pointed at SF Pro (or Helvetica Neue) for an
exact match.

Usage:  python3 native/scripts/render-dmg-bg.py [--out PATH]
"""

from __future__ import annotations

import argparse
import math
import os
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

SCALE = 2
W_PT, H_PT = 660, 400
W, H = W_PT * SCALE, H_PT * SCALE  # 1320 x 800

# ── ground: warm paper gradient, #F9F7F3 → #F4F1EA at 55% → #EFECE2, 150° ────
GROUND = [(0.00, (0xF9, 0xF7, 0xF3)), (0.55, (0xF4, 0xF1, 0xEA)), (1.00, (0xEF, 0xEC, 0xE2))]
GROUND_ANGLE_DEG = 150

EMBER = (0xC9, 0x7B, 0x35)      # dotted wave + chevron
INK = (0x26, 0x22, 0x1B)        # caption line 1
INK2 = (0x84, 0x7D, 0x6E)       # caption line 2

WAVE_STROKE_PT = 3.4
WAVE_DASH_PT = (0.5, 9)         # stroke-dasharray: 0.5 9 — a dotted leader
CAPTION1_PT = 15.0              # weight 600, letter-spacing −0.01em
CAPTION2_PT = 12.5              # regular
CAPTION1_BASELINE_FRAC = 0.09   # baseline 9% up from the bottom

FONT_REG = os.environ.get("OVF_DMG_FONT", "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf")
FONT_BOLD = os.environ.get("OVF_DMG_FONT_BOLD", "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf")

LINE1 = "Then open it from Applications."
LINE2 = 'macOS can’t launch me itself. If it says “downloaded from the Internet”, click Open.'


def lerp(a: float, b: float, t: float) -> float:
    return a + (b - a) * t


def gradient_colour(t: float) -> tuple[int, int, int]:
    """Sample the three-stop ground gradient at t in 0…1."""
    t = min(1.0, max(0.0, t))
    for (t0, c0), (t1, c1) in zip(GROUND, GROUND[1:]):
        if t <= t1:
            k = 0.0 if t1 == t0 else (t - t0) / (t1 - t0)
            return tuple(int(round(lerp(c0[i], c1[i], k))) for i in range(3))
    return GROUND[-1][1]


def draw_ground(img: Image.Image) -> None:
    """Linear gradient at GROUND_ANGLE_DEG, projected per pixel row/column.

    A 150° CSS gradient runs top-left-ish to bottom-right-ish; project each
    pixel onto that axis and normalise by the projection's full span.
    """
    rad = math.radians(GROUND_ANGLE_DEG - 90)  # CSS 0° points up; PIL y grows down
    dx, dy = math.cos(rad), math.sin(rad)
    span = abs(dx) * W + abs(dy) * H
    off = (W if dx < 0 else 0) * abs(dx) + (H if dy < 0 else 0) * abs(dy)
    px = img.load()
    # Cache one colour per projected bucket — the gradient is smooth, and this
    # keeps the render well under a second.
    cache: dict[int, tuple[int, int, int]] = {}
    for y in range(H):
        for x in range(W):
            t = (x * dx + y * dy + off) / span
            key = int(t * 1024)
            c = cache.get(key)
            if c is None:
                c = gradient_colour(key / 1024)
                cache[key] = c
            px[x, y] = c


# ── wave geometry, measured off the shipped asset ────────────────────────────
# The drop positions are pinned to this line, so the curve must not move. These
# constants were recovered by sampling the ember centreline of the previous
# dmg-bg@2x.png: one full sine period across the span, crest up first.
WAVE_X0_PT = 209.5      # first dot
WAVE_X1_PT = 432.0      # last dot (the chevron continues from here)
WAVE_PERIOD_PT = 240.0  # one full cycle
WAVE_MID_PT = 155.4
WAVE_AMP_PT = 11.4
CHEVRON_TIP_PT = (452.0, 155.4)


def wave_y(x_pt: float) -> float:
    """The leader line the user drags along — an S-curve, crest then trough."""
    u = (x_pt - WAVE_X0_PT) / WAVE_PERIOD_PT
    return WAVE_MID_PT - math.sin(u * 2 * math.pi) * WAVE_AMP_PT


def draw_dotted_wave(d: ImageDraw.ImageDraw) -> None:
    """Ember wave as a dashed stroke: 0.5 pt on, 9 pt off, 3.4 pt wide."""
    on_pt, off_pt = WAVE_DASH_PT
    period = on_pt + off_pt
    r = WAVE_STROKE_PT * SCALE / 2
    travelled = 0.0
    prev = (WAVE_X0_PT, wave_y(WAVE_X0_PT))
    step = 0.25
    x_pt = WAVE_X0_PT
    while x_pt <= WAVE_X1_PT:
        cur = (x_pt, wave_y(x_pt))
        travelled += math.dist(prev, cur)
        if (travelled % period) < on_pt:
            cx, cy = cur[0] * SCALE, cur[1] * SCALE
            d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=EMBER)
        prev = cur
        x_pt += step


def draw_chevron(d: ImageDraw.ImageDraw) -> None:
    """Chevron at the right end of the wave, pointing at the Applications drop."""
    tip_x, tip_y = CHEVRON_TIP_PT
    size, wide = 8.0, 8.0
    pts = [
        ((tip_x - size) * SCALE, (tip_y - wide) * SCALE),
        (tip_x * SCALE, tip_y * SCALE),
        ((tip_x - size) * SCALE, (tip_y + wide) * SCALE),
    ]
    d.line(pts, fill=EMBER, width=int(round(WAVE_STROKE_PT * SCALE)), joint="curve")


def tracked_text_width(d: ImageDraw.ImageDraw, text: str, font, tracking_px: float) -> float:
    return sum(d.textlength(ch, font=font) for ch in text) + tracking_px * max(0, len(text) - 1)


def draw_tracked(d: ImageDraw.ImageDraw, cx: float, baseline: float, text: str,
                 font, fill, tracking_px: float) -> None:
    """Centred text with explicit per-character tracking (PIL has no letter-spacing)."""
    total = tracked_text_width(d, text, font, tracking_px)
    x = cx - total / 2
    ascent, _ = font.getmetrics()
    top = baseline - ascent
    for ch in text:
        d.text((x, top), ch, font=font, fill=fill)
        x += d.textlength(ch, font=font) + tracking_px


def draw_caption(d: ImageDraw.ImageDraw) -> None:
    f1 = ImageFont.truetype(FONT_BOLD, int(round(CAPTION1_PT * SCALE)))
    f2 = ImageFont.truetype(FONT_REG, int(round(CAPTION2_PT * SCALE)))
    cx = W / 2
    baseline1 = H - (H * CAPTION1_BASELINE_FRAC)
    # −0.01em at 15 pt ≈ −0.15 pt, doubled for @2x.
    draw_tracked(d, cx, baseline1, LINE1, f1, INK, -0.01 * CAPTION1_PT * SCALE)
    ascent2, descent2 = f2.getmetrics()
    baseline2 = baseline1 + (ascent2 + descent2) * 1.15
    draw_tracked(d, cx, baseline2, LINE2, f2, INK2, 0.0)


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default=str(Path(__file__).resolve().parents[1] / "assets" / "dmg-bg@2x.png"))
    args = ap.parse_args()

    img = Image.new("RGB", (W, H))
    draw_ground(img)
    d = ImageDraw.Draw(img)
    draw_dotted_wave(d)
    draw_chevron(d)
    draw_caption(d)

    out = Path(args.out)
    out.parent.mkdir(parents=True, exist_ok=True)
    img.save(out, "PNG", optimize=True)
    print(f"wrote {out} ({out.stat().st_size} bytes, {W}x{H})")


if __name__ == "__main__":
    main()
