#!/usr/bin/env python3
"""Voiceover via edge-tts (free): one clip per line, frame-budgeted.

Each line = (id, start, must_end_by, text, rate). The budget is the moment
the next visual beat lands; the script fails loudly if a rendered line
overflows, so timing problems surface HERE, not in the mix.
Writes vo/<id>.wav, vo/manifest.json and captions.en.vtt.

Edit LINES to your script. Leave LINES empty for a film without narration
(the score template handles a missing manifest gracefully).
"""
import asyncio, json, subprocess, sys, wave
from pathlib import Path

import edge_tts
import imageio_ffmpeg
import numpy as np

HERE = Path(__file__).parent
VODIR = HERE / "vo"
VODIR.mkdir(exist_ok=True)
FF = imageio_ffmpeg.get_ffmpeg_exe()
VOICE = "en-US-AvaNeural"   # calm female documentary register; also try EmmaNeural, AriaNeural

# (id, start, must_end_by, text, rate)
LINES = [
    ("l01", 0.90, 3.80, "One sentence of problem or promise.", "+0%"),
    ("l02", 8.90, 11.00, "Your product, in one line.", "+0%"),
]

def trim_silence(path, head_pad=0.04, tail_pad=0.10, thresh_db=-48.0):
    """edge-tts pads clips with ~0.7s of silence; trim so budgets measure speech."""
    with wave.open(str(path)) as w:
        sr = w.getframerate()
        pcm = np.frombuffer(w.readframes(w.getnframes()), dtype=np.int16)
    x = pcm.astype(float) / 32768
    loud = np.abs(x) > 10 ** (thresh_db / 20)
    if not loud.any():
        raise RuntimeError(f"{path} is silent")
    a = max(0, int(np.argmax(loud) - head_pad * sr))
    b = min(len(x), int(len(loud) - np.argmax(loud[::-1]) + tail_pad * sr))
    out = pcm[a:b]
    with wave.open(str(path), "wb") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(sr)
        w.writeframes(out.tobytes())
    return len(out) / sr

async def render(line_id, text, rate):
    mp3 = VODIR / f"{line_id}.mp3"
    wav = VODIR / f"{line_id}.wav"
    tts = edge_tts.Communicate(text, VOICE, rate=rate)
    await tts.save(str(mp3))
    subprocess.run([FF, "-y", "-loglevel", "error", "-i", str(mp3),
                    "-ar", "48000", "-ac", "1", str(wav)], check=True)
    return trim_silence(wav)

def vtt_ts(s):
    h = int(s // 3600); m = int(s % 3600 // 60)
    return f"{h:02d}:{m:02d}:{s % 60:06.3f}"

async def main():
    manifest = []
    failures = []
    for line_id, start, end_by, text, rate in LINES:
        dur = await render(line_id, text, rate)
        budget = end_by - start
        status = "OK " if dur <= budget else "OVER"
        if dur > budget:
            dur = await render(line_id, text, "+12%")   # one retry, slightly faster
            status = "OK*" if dur <= budget else "OVER"
        print(f"{line_id} {status} {dur:5.2f}s / {budget:5.2f}s  {text}")
        if dur > budget:
            failures.append(line_id)
        manifest.append({"id": line_id, "start": start, "dur": round(dur, 3), "text": text})
    (VODIR / "manifest.json").write_text(json.dumps(manifest, indent=1))
    vtt = ["WEBVTT", ""]
    for m in manifest:
        vtt.append(f"{vtt_ts(m['start'])} --> {vtt_ts(m['start'] + m['dur'])}")
        vtt.append(m["text"])
        vtt.append("")
    (HERE / "captions.en.vtt").write_text("\n".join(vtt))
    if failures:
        sys.exit(f"lines over budget even at +12%: shorten the copy for {failures}")
    print("manifest + captions.en.vtt written")

asyncio.run(main())
