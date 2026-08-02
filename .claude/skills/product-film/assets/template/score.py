#!/usr/bin/env python3
"""Score + sound design + VO mix — pure numpy, no samples, no paid audio.

Three buses: music (ducked under VO), sfx (not ducked), voice. The buffer
is allocated to exactly TIMING.duration so audio length always equals
video length. A default F-major arrangement is generated from the scene
list so this file produces a listenable bed for ANY timings out of the
box — then you AUTHOR: replace the default pads/melody/SFX with beats
scheduled from your timings.js (see the AUTHOR HERE markers).

Laws learned the hard way:
- ZERO noise-sweep whooshes. They read as static. Cuts ride the pulse.
- The sfx bus stays silent within ±0.2s of every scene boundary.
- One big tonal hit on the film's money beat, nowhere else.
The script prints per-scene RMS, a boundary audit, and VO presence so
you can verify the mix numerically (you cannot listen — measure).
"""
import json, re, wave
from pathlib import Path

import numpy as np

HERE = Path(__file__).parent
raw = (HERE / "timings.js").read_text()
T = json.loads(re.sub(r"^window\.TIMING\s*=\s*|;\s*$", "", raw.strip()))
vo_path = HERE / "vo" / "manifest.json"
VO = json.loads(vo_path.read_text()) if vo_path.exists() else []

SR = 48000
DUR = T["duration"]
N = int(SR * DUR)

ML = np.zeros(N); MR = np.zeros(N)
XL = np.zeros(N); XR = np.zeros(N)
VL = np.zeros(N); VR = np.zeros(N)

def sec(x): return int(x * SR)

def add(bufL, bufR, sig, at, gain=1.0, pan=0.0):
    i = sec(at)
    if i >= N: return
    seg = sig[: N - i]
    gl = gain * np.cos((pan + 1) * np.pi / 4)
    gr = gain * np.sin((pan + 1) * np.pi / 4)
    bufL[i:i+len(seg)] += seg * gl
    bufR[i:i+len(seg)] += seg * gr

def add_m(sig, at, gain=1.0, pan=0.0): add(ML, MR, sig, at, gain, pan)
def add_x(sig, at, gain=1.0, pan=0.0): add(XL, XR, sig, at, gain, pan)

def env_ar(n, a, r, hold=0.0):
    x = np.arange(int(n)) / SR
    e = np.ones(int(n))
    e = np.where(x < a, x / max(a, 1e-9), e)
    e = np.where(x > a + hold, np.maximum(0, 1 - (x - a - hold) / max(r, 1e-9)), e)
    return np.clip(e, 0, 1)

NOTE = {
    "F1": 43.65, "F2": 87.31, "C3": 130.81, "D3": 146.83, "E3": 164.81,
    "F3": 174.61, "G3": 196.0, "A3": 220.0, "Bb3": 233.08, "C4": 261.63,
    "D4": 293.66, "E4": 329.63, "F4": 349.23, "G4": 392.0, "A4": 440.0,
    "C5": 523.25, "D5": 587.33, "F5": 698.46,
}

def pad_chord(notes, start, end, gain, attack=1.4, release=2.2, dark=0.0):
    """Two detuned sines + quiet octave per note, slow AR, tremolo, lowpass."""
    dur = (end - start) + release
    n = sec(dur)
    x = np.arange(n) / SR
    sig = np.zeros(n)
    for k, name in enumerate(notes):
        f = NOTE[name]
        det = 1 + 0.0015 * (1 if k % 2 else -1)
        ph = k * 1.7
        s = np.sin(2*np.pi*f*x + ph) + np.sin(2*np.pi*f*det*x + ph*1.3)
        s += (0.25 - dark * 0.18) * np.sin(2*np.pi*f*2*x + ph)
        sig += s / len(notes)
    sig *= 1 + 0.08 * np.sin(2*np.pi*0.7*x)
    sig *= env_ar(n, attack, release, hold=max(0.0, dur - attack - release))
    alpha = 0.12 - dark * 0.07
    out = np.empty_like(sig); acc = 0.0
    for i in range(len(sig)):
        acc += alpha * (sig[i] - acc)
        out[i] = acc
    return out * gain

def pluck(freq, dur=1.4):
    n = sec(dur)
    x = np.arange(n) / SR
    s = np.sin(2*np.pi*freq*x) + 0.35*np.sin(2*np.pi*freq*2*x) + 0.12*np.sin(2*np.pi*freq*3*x)
    s *= np.exp(-x * 4.2)
    a = sec(0.004)
    s[:a] *= np.linspace(0, 1, a)
    return s

def pluck_echo(freq, at, gain, pan=0.0):
    """Ping-pong echo: +0.29s @42%, +0.58s @18%, alternating pan."""
    p = pluck(freq)
    add_m(p, at, gain, pan)
    add_m(p, at + 0.29, gain * 0.42, -pan * 0.8 - 0.15)
    add_m(p, at + 0.58, gain * 0.18, pan * 0.8 + 0.15)

def kick(at, gain=0.16, freq_hi=88, freq_lo=48, dur=0.22):
    n = sec(dur)
    x = np.arange(n) / SR
    f = freq_lo + (freq_hi - freq_lo) * np.exp(-x * 26)
    ph = 2*np.pi*np.cumsum(f)/SR
    s = np.sin(ph) * np.exp(-x * 15)
    add_m(s, at, gain)

def tick(at, gain=0.05, bright=2000, dur=0.03):
    n = sec(dur)
    rng = np.random.default_rng(int(at * 977) & 0xffff)
    s = rng.standard_normal(n) * np.exp(-np.arange(n)/SR * 320)
    x = np.arange(n) / SR
    s += 0.6 * np.sin(2*np.pi*bright*x) * np.exp(-x * 260)
    add_x(s, at, gain)

def thock(at, gain=0.14):
    """Button-press body."""
    n = sec(0.09)
    x = np.arange(n) / SR
    s = np.sin(2*np.pi*140*x) * np.exp(-x * 60)
    rng = np.random.default_rng(7)
    s += 0.35 * rng.standard_normal(n) * np.exp(-x * 500)
    add_x(s, at, gain)

def pop(at, gain=0.12):
    """Paste / element-landing pop: 40ms sine glide 660→330 Hz."""
    n = sec(0.07)
    x = np.arange(n) / SR
    f = 660 - 330 * np.clip(x / 0.05, 0, 1)
    s = np.sin(2*np.pi*np.cumsum(f)/SR) * np.exp(-x * 55)
    add_x(s, at, gain)

# ─── default arrangement from the scene list (REPLACE: author per film) ─
S = T["scenes"]
skeys = sorted(S.keys(), key=lambda k: S[k][0])
CYCLE = [
    ["F2", "C3", "E3", "A3"], ["A3", "C4", "E4", "G4"], ["D3", "F3", "A3", "C4"],
    ["Bb3", "D4", "F4", "A4"], ["F2", "A3", "C4", "F4"], ["E3", "G3", "C4", "E4"],
]
end_fade = T.get("end", {}).get("fade", DUR - 1.0)
for i, k in enumerate(skeys):
    a, b = S[k]
    first, last = i == 0, i == len(skeys) - 1
    if last:
        add_m(pad_chord(["F2", "C3", "E3", "G3", "A3"], a, end_fade, 0.11, 1.4, 3.0, 0.1), a)
    elif first:
        add_m(pad_chord(["F2", "C3"], a, b, 0.055, 2.4, 2.0, 0.4), a)
    else:
        add_m(pad_chord(CYCLE[(i - 1) % len(CYCLE)], a, b, 0.095, 1.0, 1.6, 0.1), a)

# pulse: soft 78 BPM kick from the second scene to the last scene start
BEAT = 60 / 78
if len(skeys) > 2:
    tt = S[skeys[1]][0]
    while tt < S[skeys[-1]][0] - 0.3:
        kick(tt, gain=0.12)
        tt += BEAT

# ─── AUTHOR HERE: melody + tonal SFX scheduled from timings.js ─────────
# pluck_echo(NOTE["A4"], 4.4, 0.055, -0.2)      # sparse, a few per scene
# pop(T["beats"]["card_in"], 0.10)               # element lands
# thock(T["beats"]["press"], 0.14)               # button press
# kick(T["beats"]["money"], gain=0.22, freq_hi=110, freq_lo=40, dur=0.5)  # THE hit
if "beats" in T and "money" in T["beats"]:
    kick(T["beats"]["money"], gain=0.20, freq_hi=110, freq_lo=40, dur=0.5)

# ─── voiceover (skipped gracefully when there is no manifest) ──────────
def load_wav(path):
    with wave.open(str(path)) as w:
        assert w.getframerate() == SR
        return np.frombuffer(w.readframes(w.getnframes()), dtype=np.int16).astype(float) / 32768

duck = np.zeros(N)
for line in VO:
    v = load_wav(HERE / "vo" / f"{line['id']}.wav")
    rms = np.sqrt((v ** 2).mean())
    v *= (10 ** (-20 / 20)) / max(rms, 1e-9)   # every line at -20 dBFS RMS
    add(VL, VR, v, line["start"], gain=1.0)
    a, b = sec(line["start"]), min(N, sec(line["start"] + line["dur"]))
    duck[a:b] = 1.0

if VO:
    k_a, k_r = sec(0.15), sec(0.40)             # attack / release ramps
    env = duck.copy()
    for i in range(1, N):
        env[i] = max(env[i], env[i-1] - 1.0 / k_r)
    for i in range(N - 2, -1, -1):
        env[i] = max(env[i], env[i+1] - 1.0 / k_a)
    dg = 1.0 - 0.47 * env                       # ≈ -5.5 dB under speech
    ML *= dg; MR *= dg

# ─── bus glue + verification ────────────────────────────────────────────
L = ML + XL + VL * 0.92
R = MR + XR + VR * 0.92
mix = np.stack([L, R])
mix = np.tanh(mix * 1.25) / np.tanh(1.25)
fade_in = sec(0.25)
mix[:, :fade_in] *= np.linspace(0, 1, fade_in)
fade_start = sec(max(0.0, end_fade - 0.4))
mix[:, fade_start:] *= np.linspace(1, 0, N - fade_start) ** 1.4
peak = np.abs(mix).max()

def rms_db(seg):
    r = np.sqrt((seg ** 2).mean())
    return 20 * np.log10(max(r, 1e-9))

print("per-scene mix RMS (pre-normalize):")
for k in skeys:
    a, b = sec(S[k][0]), min(N, sec(S[k][1]))
    print(f"  {k} [{S[k][0]:5.1f}-{S[k][1]:5.1f}]  {rms_db(mix[:, a:b]):6.1f} dBFS")
print("scene-boundary SFX audit (all must be ~silent, < -60 dBFS):")
sfx = np.stack([XL, XR])
for k in skeys[1:]:
    tb = S[k][0]
    a, b = max(0, sec(tb - 0.2)), min(N, sec(tb + 0.2))
    r = rms_db(sfx[:, a:b])
    print(f"  cut@{tb:5.1f}s  sfx {r:6.1f} dBFS  {'OK' if r < -60 else 'LOUD!'}")
if VO:
    print("VO presence (mix RMS above bed RMS during each line; want +6 dB or more):")
    bed = np.stack([ML + XL, MR + XR])
    for line in VO:
        a, b = sec(line["start"]), min(N, sec(line["start"] + line["dur"]))
        print(f"  {line['id']}  +{rms_db(mix[:, a:b]) - rms_db(bed[:, a:b]):4.1f} dB")

mix *= (10 ** (-1.5 / 20)) / max(peak, 1e-9)   # normalize peak to -1.5 dBFS
pcm = (mix.T * 32767).astype(np.int16)
with wave.open(str(HERE / "score.wav"), "wb") as w:
    w.setnchannels(2); w.setsampwidth(2); w.setframerate(SR)
    w.writeframes(pcm.tobytes())
print(f"score.wav written: {DUR}s, {len(VO)} VO lines, peak {peak:.3f} pre-normalize")
