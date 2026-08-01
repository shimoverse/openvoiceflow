# Sound: score, sound design, voiceover, mix

Everything is synthesized (numpy) or free (edge-tts). No samples, no
licenses, no paid APIs — and everything is frame-locked to `timings.js`.

## Score recipe (score.py provides the instrument kit)

Minimal-ambient bed, one key throughout (F major has shipped twice —
change key only deliberately):
- **Pads**: chord timeline `(notes, start, end, gain, attack, release,
  dark)`; near-silent under the problem scenes, opens at the thesis,
  fullest through hero + features, strips to sub + dark pad for the
  intimate scene, long resolve on the end card. Change chord on scene
  boundaries and mid-hero — the harmonic motion is what makes cuts feel
  intentional.
- **Pulse**: soft synth kick every beat at ~78 BPM from the brand reveal;
  drop it for the intimate scene; half-time for the finale.
- **Plucks**: sparse pentatonic notes with ping-pong echo, 2–4 per scene
  maximum, panned alternately.
- **One money hit**: stacked-octave kick (freq_hi≈110, dur 0.5, gain
  ~0.2) on the hero payoff's final beat. Exactly one per film.

## Sound design laws

- **ZERO noise-sweep whooshes.** Synthesized noise sweeps at scene cuts
  read as static and reviewers hear them as a defect (hard-won feedback,
  twice). Scene changes need no sound; the pulse carries them.
- The **sfx bus must be silent within ±0.2 s of every scene boundary** —
  score.py prints an audit; every row must say OK.
- Tonal SFX only, scheduled from `timings.js` beats: `pop()` for
  elements landing/paste, `tick()` for small text appearing (gain
  ~0.03), `thock()` for button presses. Gains stay small — sound design
  seasons, it never announces.

## Voiceover (vo.py)

- **Voice**: `en-US-AvaNeural` (edge-tts) — calm, warm, female,
  documentary register; reads premium. Alternatives: `en-US-EmmaNeural`,
  `en-US-AriaNeural`. Keep `rate="+0%"`; use `+12%` only as the
  overflow retry.
- **Writing**: short declarative lines, 3–10 words mostly. One line per
  visual beat. The VO frames moments, it never narrates UI mechanics
  ("click the button" is banned). Go SILENT for the hero demo — narrate
  into it and out of it, not over it.
- **Budgets**: every line has `(start, must_end_by)` from the
  storyboard. A line must never smear across a scene cut. vo.py
  enforces: synth → 48 kHz mono WAV → trim silence (edge-tts pads ~0.7 s;
  scan for first/last sample above −48 dBFS, keep 0.04 s head / 0.10 s
  tail) → measure → retry at +12% → fail loudly (then SHORTEN THE COPY —
  don't speed past +12%, it sounds anxious).
- **Captions**: `captions.en.vtt` is generated from the manifest so
  captions can never drift from the audio. Ship it with every deliverable
  (platforms auto-caption badly).
- **TLS-intercepting proxies**: edge-tts pins certifi's CA store. On
  `CERTIFICATE_VERIFY_FAILED`, append the proxy CA to
  `$(python3 -c 'import certifi; print(certifi.where())')`. Never
  disable verification.

## Mix (score.py implements this)

- Buses: music (ducked), sfx (not ducked), voice.
- Each VO line normalized to −20 dBFS RMS; voice bus at 0.92 into the mix.
- Duck: envelope 1.0 under speech, smoothed 0.15 s attack / 0.40 s
  release; music × (1 − 0.47·env) ≈ −5.5 dB under speech.
- Glue: `tanh(mix × 1.25)/tanh(1.25)` soft clip → 0.25 s fade-in →
  fade-out from `end.fade` → normalize peak to −1.5 dBFS.
- Mux at AAC 176k, `-c:v copy`, no `-shortest` (audio length must equal
  video length by construction; a mismatch is a bug, not a trim).

## Numeric verification (you cannot listen — measure)

score.py prints, before normalizing:
- **Per-scene RMS**: check the *relative* arc — problem scenes quietest,
  build through hero/features, intimate scene dips, finale resolves.
- **Boundary audit**: sfx RMS at every cut ±0.2 s < −60 dBFS.
- **VO presence**: mix RMS during each line ≥ ~+6 dB over the bed-only
  RMS of the same span (template films measured +11 to +22 dB).
- Peak pre-normalize < 1.0 (no clipping into the soft clip).
Also run ffmpeg `volumedetect` on the muxed file if you need an
independent check that audio is present and sane.
