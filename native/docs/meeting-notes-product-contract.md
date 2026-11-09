# Meeting notes: product and integrity contract

## Product decision

Make a useful, shareable meeting document the primary outcome, not a wall of
raw recognized words. Keep recording evidence available on demand. Preserve the
local-only boundary rather than copying competitors' cloud architecture.

### Patterns reviewed (official documentation, November 9, 2026)

- [Granola: enhanced notes](https://docs.granola.ai/help-center/taking-notes/ai-enhanced-notes):
  notes are the primary artifact; the owner can inspect supporting evidence and
  regenerate. Its model architecture is not evidence of our local model quality.
- [Granola: templates](https://docs.granola.ai/help-center/taking-notes/customise-notes-with-templates):
  purpose, length and explicit sections are separate prompt concerns. Adopt the
  strong general-purpose section structure now, not a large template gallery.
- [Granola: sharing](https://docs.granola.ai/help-center/sharing/sharing-notes):
  copying enhanced notes is separate from copying the full conversation.
  Adopt intentional notes-only sharing, not automatic attendee distribution.
- [Otter: meeting templates](https://help.otter.ai/hc/en-us/articles/31402572907415-Custom-Meeting-Type-Templates):
  separates overview, action items, insights and outline; source navigation is a
  distinct interaction. Adopt scannable sections and explicit task treatment.
- [Fathom: advanced AI features](https://help.fathom.video/en/articles/640768):
  offers meeting-specific templates and follow-up workflows. Defer integrations,
  custom templates and automated sending until the basic document is trustworthy.

These are product patterns, not a claim of competitive transcription accuracy,
feature parity, or a benchmark on the same meeting audio.

## Document organization

1. Meeting title and date, with recording duration as secondary metadata.
2. **Overview:** concise context; no commentary about the input or AI.
3. **Key points:** meaningful topics, constraints, risks and rejected proposals.
4. **Decisions:** explicit agreements only. Suggestions are not decisions.
5. **Action items:** explicit commitments; retain owners/dates only when spoken.
6. **Open questions:** unresolved questions, not invented next steps.
7. **Private notes:** owner-written material, distinct from the shared document.
8. **Recording details:** audio and conversation text, secondary/collapsible when
   not recording. Live words must remain visible during capture.

Omit absent sections rather than filling them with invented content. Use native
cards, SF Symbols, generous line spacing, and task affordances rather than
emoji decoration or an unbroken paragraph. Copy/export must not include raw
conversation or private notes by default. Export never sends anything itself.

## Generation contract

- Use bounded, word-preserving windows across the complete conversation.
- Use FoundationModels guided generation where available, with a fresh session
  per window so one long meeting does not exhaust a single context.
- Require a verbatim supporting sentence for each model item and render that
  exact sentence. The model selects and groups evidence; it does not rewrite
  factual relationships. A word-subset check cannot prevent swapping owners,
  objects, deadlines, or the attachment of a negation within one sentence.
- Organize globally by section and remove exact duplicates after all windows.
  Do not truncate every window's answer at an arbitrary 400-character boundary.
- Preserve explicit follow-ups omitted by the model through source-derived
  candidates. Retain dates, decimals, negation and uncertainty.
- If the local model is unavailable, errors, or returns unusable output, use
  deterministic sectioned verbatim highlights. This release is deliberately
  extractive, including on supported Macs, not equivalent to Granola's
  abstractive notes. Exact source wording preserves relationships but does not
  prove the speech recognizer heard the original audio correctly.
- Keep short substantive decisions and source facts beyond the first few
  sentences. Long sections collapse visually without truncating copy/export.
- Cancellation preserves previous notes; manual titles/private notes remain
  untouched by regeneration. Existing stored notes are not silently rewritten.

## Speech integrity and evidence boundary

A repeated closing phrase is a symptom, not proof of its exact origin. Inspect
acoustic input and decoding separately from text accumulation. Gate silent input
in both live and imported recordings, preserve audio, and never solve the symptom
by globally banning genuine phrases such as “thank you.” Background sound can
still be mistaken for speech; acoustic thresholds alone are not a full learned
voice-activity detector or a guarantee against hallucinations. Quiet voiced
subwindows must bypass stationary-noise rejection; ambiguous long chunks fail
open rather than losing a brief utterance. Exact 30- and 60-second imports
must finish without an extra read beyond AVAudioFile's end.

Do not claim the original meeting is repaired without reprocessing its actual
saved audio. Keep private recordings and generated business notes out of source,
fixtures, public screenshots and external model calls.

## Acceptance gates

- Grounding tests reject invented owners/dates and source meta-commentary.
- Conditional/negated proposals never become approved decisions.
- Distinct windows and late commitments survive organization; no repeated
  bullet for an exact duplicate; decimals and complete sentences survive.
- Real local model execution is recorded separately from injected-output tests.
- Speech gates run through both live and imported-audio storage paths.
- Native layout, sharing defaults and draft persistence are independently tested.
- Build/CI, rendered fixture QA, physical microphone quality and the user's
  original recording are distinct verification claims.

No calendar ingestion, system-audio capture, speaker identity attribution,
cloud sharing links, meeting chat, CRM integration or automatic attendee delivery
is implied by this change.
