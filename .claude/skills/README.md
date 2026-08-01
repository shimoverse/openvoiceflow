# Agent Skills

Portable skills following the open [Agent Skills](https://code.claude.com/docs/en/skills) standard
(SKILL.md + references/ + assets/). Claude Code loads them from this
directory automatically; for Codex CLI copy to `.agents/skills/`, for
other agents paste the skill's SKILL.md as instructions.

- **product-film** — build finished, award-style product demo films
  entirely in code (HTML stage → Playwright frames → ffmpeg, numpy
  score, edge-tts voiceover), with platform variants for YouTube 16:9,
  Reels/Shorts/TikTok 9:16 (safe zones), 1:1 and 4:5.
