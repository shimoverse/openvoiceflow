# OpenVoiceFlow — Open-Source Readiness Checklist (Phase 3, v0.2.0)

> **Status:** Discovery output. Not committed. Pairs with `PROJECT_AUDIT.md` and `PERSONA_AUDIT.md`.
> Audited: 2026-04-27 against `HEAD = 3b03d29` (v0.2.0).

> **Note on stack mismatch:** the user-supplied checklist was written for npm/Node projects (npm pack, tsup, files[], `npx <pkg> doctor`, NPM_TOKEN). OpenVoiceFlow is **Python**. Where an item is npm-specific, I mark **🔄 reframed** and give the Python equivalent.

Legend: ✅ exists / works · 🟡 partial · ❌ missing · 🔄 reframed for Python · N/A not applicable

---

## Legal & compliance

| # | Item | v0.1.0 | v0.2.0 | Notes |
|---|---|---|---|---|
| L1 | LICENSE (MIT or other) | ✅ | ✅ | MIT, copyright 2025 Mohit Jain |
| L2 | SECURITY.md | ❌ | ❌ | Required for procurement persona; Wave 3 |
| L3 | PRIVACY.md (data-flow diagram) | ❌ | ❌ | Required especially given v0.2 added profile/dictionary/snippets/auto-learn |
| L4 | THREAT_MODEL.md | ❌ | ❌ | STRIDE-lite covering: prompt-tampering, key exfil, focus-switch paste, auto-learner Accessibility surface |
| L5 | COMPLIANCE.md (GDPR, SOC2 posture) | ❌ | ❌ | Should explicitly say "not for regulated industries; BYOK; we are not your sub-processor" |
| L6 | CODE_OF_CONDUCT.md | ❌ | ❌ | Contributor Covenant v2.1 boilerplate |
| L7 | CONTRIBUTING.md | ❌ | ❌ | Dev-mode setup, branch policy, PR checklist; landing page references it (line 600) but file doesn't exist — broken link |
| L8 | SUPPORT.md | ❌ | ❌ | GitHub Discussions/Issues policy + response-time expectation |
| L9 | CHANGELOG.md (Keep-a-Changelog) | ❌ | ❌ | Two releases shipped (v0.1.1, v0.2.0) without a CHANGELOG; need retro entries |
| L10 | VERSIONING.md (semver policy) | ❌ | ❌ | Pre-1.0 caveat; what counts as breaking (CLI flags, config schema) |
| L11 | COMPATIBILITY.md (host versions) | 🔄 ❌ | 🔄 ❌ | Reframe: macOS / Python / whisper.cpp / each LLM provider compat table |
| L12 | legal/DPA-template.md | ❌ | ❌ | Boilerplate stub: "we have no data; you contract directly with your LLM provider" |
| L13 | legal/THIRD_PARTY_NOTICES.md | ❌ | ❌ | Need: sounddevice, numpy, pynput, rumps, pyobjc (transitive), whisper.cpp, ggml model |

**Subtotal:** 1 ✅, 0 🟡, 11 ❌, 1 🔄. **Zero progress since v0.1.0.**

---

## Docs

| # | Item | v0.1.0 | v0.2.0 | Notes |
|---|---|---|---|---|
| D1 | README hero screenshot + 3-column journey | ❌ | 🟡 | README rewritten and now has feature matrix, comparison table, FAQ. **Animated terminal demo on landing page** ✅. No screenshots/GIFs of the actual app yet. |
| D2 | MANUAL.md (full reference) | ❌ | 🟡 | README is much fuller now (~600 lines); covers most flags. Still no single canonical reference doc — content is split across README + PRD. |
| D3 | PLAYBOOK.md (recipes) | ❌ | 🟡 | README has recipe-like sections (style modes, voice commands, dictionary). Not a separate doc. |
| D4 | ARCHITECTURE.md | ❌ | ❌ | Module-map + data-flow diagram still missing |
| D5 | SECURITY_REPORT.md (own audit findings) | ❌ | 🟡 | This audit is the seed — when public-facing version is written, can pull from PROJECT_AUDIT |
| D6 | customization.md | ❌ | 🟡 | README covers customization (hotkey/model/prompt/style) — still scattered |
| D7 | Per-extension/integration setup guides (5-step format) | 🔄 ❌ | 🔄 🟡 | Reframe to per-LLM-backend setup. Each backend has a row in the README table linking to its own API-key page. No per-backend N-step guides yet. |
| D8 | Per-framework quickstart that ACTUALLY BUILDS clean | 🔄 ❌ | 🔄 🟡 | Reframe to per-install-path quickstart (DMG / install.sh / pip-from-source). README documents all three. **DMG works ✅, install.sh creates broken shim 🔴 (SS2), pip works on 3.10+ 🟠 (SS3 broken on 3.9).** |
| D9 | AGENTS.md (agentsmd.org convention) | ❌ | ❌ | Still missing; v0.2 adds 15 modules → AGENTS.md is more useful, not less |
| D10 | Mobile-support section (✅/🚧 table) | 🟡 | 🟡 | README implies macOS-only via badges; no explicit "iOS: never" table |
| D11 (new) | PRD.md present | N/A | ✅ | New in v0.2; useful internally; should be linked from CONTRIBUTING when that exists |
| D12 (new) | Landing page (`docs/index.html`) | ❌ | ✅ | Polished, animated demo, FAQ, CTAs all point at correct URLs |

**Subtotal:** 1 ✅ (new D11/D12), 7 🟡, 4 ❌, 0 🔄. **Substantial progress** — from 0/3/5/2 in v0.1.0 to 2/7/4/2.

---

## Developer UX

| # | Item | v0.1.0 | v0.2.0 | Notes |
|---|---|---|---|---|
| DX1 | `npx <pkg> doctor` for health check | 🔄 ❌ | 🔄 ❌ | Reframe: `openvoiceflow doctor`. Still missing. Especially valuable now that v0.2 has more failure modes (auto-learn permission, whisper-stream, pyobjc availability) |
| DX2 | Smart env-var typo detection | ❌ | ❌ | Same |
| DX3 | Production-readiness warning | N/A | N/A | No prod analogue |
| DX4 | Custom-extension worked example | ❌ | ❌ | No `examples/custom-backend/` sub-project |
| DX5 | subpath exports for tree-shaking | N/A | N/A | Python has no tree-shaking. Closest analogue: lazy imports of optional deps. v0.2 does this well: `rumps`, `tkinter`, `pyobjc.AppKit`, `pyobjc.Cocoa`, `whisper-stream` are all lazy/optional ✅ |
| DX6 | `pyproject.toml` `[tool.setuptools]` packages + package-data audited | 🔄 ❌ | 🔄 🟡 | No explicit `[tool.setuptools.packages.find]`; relies on default discovery. Wheel ships `requirements.txt` (dev-only noise). No `MANIFEST.in`. |
| DX7 | All console scripts reachable | N/A | ✅ | One entry: `openvoiceflow → voiceflow.__main__:main` ✅. (The install.sh-written shim that's broken is a separate issue under SS2.) |
| DX8 (new) | `--version` flag | ❌ | ✅ | New in v0.2 (`__main__.py:51-54`) |
| DX9 (new) | `--show-config` flag | ❌ | ✅ | New in v0.2 |
| DX10 (new) | `--search` (transcript history) | ❌ | ✅ | New in v0.2 |
| DX11 (new) | `--stats` (usage stats) | ❌ | ✅ | New in v0.2 |

**Subtotal:** 4 ✅ (all new), 1 🟡, 4 ❌, 3 N/A. **Improved.**

---

## Release infrastructure

| # | Item | v0.1.0 | v0.2.0 | Notes |
|---|---|---|---|---|
| R1 | `.github/workflows/release.yml` on tag push | ❌ | ✅ | Triggers on `v*` tags, builds split arm64/x86_64 DMGs, uses `softprops/action-gh-release@v2`, attaches DMGs to GitHub Release |
| R2 | Version-tag matches `pyproject.toml` | ❌ | 🟡 | `build-dmg.sh` parses version from pyproject dynamically ✅, but no CI step asserts that the git tag matches |
| R3 | build + type-check + test + lint + pack-shape sanity in CI | ❌ | 🟡 | `ci.yml` runs ruff (non-blocking) + import smoke + config-validate. No type-check (mypy). No tests. No `python -m build` smoke (would have caught SS1, SS3). No `pip install .` smoke (would have caught SS3). |
| R4 | npm publish --provenance | 🔄 ❌ | 🔄 ❌ | Reframe: PyPI publish via Trusted Publisher OIDC. **Not in release.yml.** Wheel never gets published. |
| R5 | GitHub Release with CHANGELOG body | ❌ | 🟡 | Releases are auto-created and DMGs attached, but body is hand-written via the GitHub UI (no `--notes` from a `CHANGELOG.md`) |
| R6 | RELEASE.md (3-command happy path + when-things-go-wrong) | ❌ | ❌ | Missing |
| R7 | PyPI package name claimed | 🔄 ❓ | 🔄 ❓ | Still unverified. `openvoiceflow` on PyPI is the assumed name; needs reservation before publishing. **Decision D2.** |
| R8 | NPM_TOKEN / Trusted Publisher OIDC | 🔄 ❌ | 🔄 ❌ | Reframe: PyPI Trusted Publisher OIDC via `pypa/gh-action-pypi-publish`. **Not configured.** Release workflow only uses default `GITHUB_TOKEN`. |
| R9 | Homebrew tap | ❌ | ❌ | PRD describes `shimoverse/homebrew-tap`; **the repo does not exist** |
| R10 | DMG signing + notarization | ❌ | ❌ | No Apple Developer account. Decision D6. |
| R11 (new) | Split arm64/x86_64 DMG | ❌ | ✅ | New in v0.2 — `build-dmg.sh` builds two artifacts; better UX than the v0.1 universal-with-Rosetta dance |
| R12 (new) | `--version` flag for tag-version asserting | ❌ | ✅ | Available; not yet wired into CI |

**Subtotal:** 3 ✅ (all new), 3 🟡, 6 ❌, 4 🔄. **Substantial progress** — from 0/0/8/4 to 3/3/6/4.

---

## Quality gates

| # | Item | v0.1.0 | v0.2.0 | Notes |
|---|---|---|---|---|
| Q1 | All tests pass; high coverage on critical path | ❌ | ❌ | Still zero tests |
| Q2 | No fictional API examples in docs | 🟡 | 🟡 | README + landing page examples mostly correct. **Voice-command count discrepancy:** landing page says "24" while README table lists 14 ⚠️ (D10). Install paths in README still lead to broken shim (SS2) and 3.9 crash (SS3). |
| Q3 | No claims in README that don't match the code | 🟡 | 🟡 | "Audio never leaves your Mac" hero claim still in tension with default-cloud-backend (D4). Auto-learner flagship feature is silently behind a `try/except/pass` (SS6). |
| Q4 | Every quickstart actually builds clean from scratch | ❌ | 🟡 | DMG ✅. install.sh shim 🔴 broken. pip on 3.10+ ✅. pip on 3.9 🔴 broken. |
| Q5 | `npm pack --dry-run` audited | 🔄 ❌ | 🔄 🟡 | Reframe: `python -m build && twine check dist/* + inspect wheel`. Verified by me manually (clean wheel, no junk except the `requirements.txt` at root). **Not gated in CI.** |
| Q6 | `npm audit` clean | 🔄 ❓ | 🔄 ❓ | Reframe: `pip-audit`. Not run in CI. Need to run + commit results. |

**Subtotal:** 0 ✅, 3 🟡, 1 ❌, 2 🔄. Marginally better than v0.1.0 (0/2/3/2).

---

## Top-level scoreboard

| Category | ✅ | 🟡 | ❌ | 🔄 / N/A | v0.1.0 was |
|---|---:|---:|---:|---:|---:|
| Legal & compliance | 1 | 0 | 11 | 1 | 1/0/11/1 |
| Docs | 2 | 7 | 4 | 2 | 0/3/5/2 |
| Developer UX | 4 | 1 | 4 | 3 | 0/0/3/4 |
| Release infrastructure | 3 | 3 | 6 | 4 | 0/0/8/4 |
| Quality gates | 0 | 3 | 1 | 2 | 0/2/3/2 |
| **Total** | **10** | **14** | **26** | **12** | **1 / 5 / 30 / 13** |

**Net:** 1 → **10** ✅, 5 → **14** 🟡, 30 → **26** ❌. Roughly half the missing items are now at least partial. The four "still ❌" categories that haven't moved at all: **Legal & compliance** (11/11 still missing) and the "no-tests" gap.

---

## Re-confirmed plan (waves)

### Wave 1 — finish unbreaking the basics (½ day)
**v0.1 ship-stoppers still open:**
- 🔴 Fix `install.sh:86` shim → `exec "$VENV_DIR/bin/openvoiceflow" "$@"` (SS2)
- 🔴 Add `from __future__ import annotations` to all 15 affected files OR bump `requires-python = ">=3.10"` (SS3, decision D3)

**v0.2 ship-stoppers introduced:**
- 🔴 Add `cleanup_prompt → llm_prompt` migration in `config.load_config()` (SS5)
- 🔴 Replace `try/except/pass` in `onboarding.py:455-458` with logging + user-visible error (SS6)

**Smaller fixes:**
- Fix the 24-vs-14 voice command count (D10)
- Re-evaluate Anthropic/Groq default model choices (D11)
- Add a `update_check: false` config flag (D12)

**Deliverable:** every install path actually works on a clean Mac with macOS 12+ default Python; flagship "Personalize" button surfaces errors; v0.1.0 users upgrade without losing their custom prompt.

### Wave 2 — make it safe to ship (1 day)
- chmod 600 on save for `config.json`, `profile.json`, `dictionary.json`, `snippets.json`, `~/.openvoiceflow/logs/*` (D5; if Keychain is decided, swap config.json for keyring)
- Default `log_transcripts: false`; add an opt-in step in onboarding (D8)
- Default `auto_learn: false` OR explicit consent step explaining what auto-learn reads (D9)
- Rewrite README hero privacy framing (D4)
- Add real API-key validation in onboarding (provider ping, not length>=10)
- Add `openvoiceflow doctor` diagnostic command (DX1)
- Fix the 43 ruff lint findings (mostly auto-fixable via `ruff check --fix`)

**Deliverable:** safe-by-default; first run lands user in a privacy-respecting state.

### Wave 3 — community-health files (1 day, parallel-friendly via subagents)
Fan out a fresh-context subagent per file:
- SECURITY.md (template + supported-version table)
- PRIVACY.md (3×N data-flow table covering all six on-disk artifacts)
- THREAT_MODEL.md (STRIDE-lite for v0.2's expanded surface)
- COMPLIANCE.md (BYOK / not-a-sub-processor)
- CODE_OF_CONDUCT.md (Contributor Covenant)
- CONTRIBUTING.md (the broken landing-page link points here)
- SUPPORT.md
- CHANGELOG.md (retro v0.1.0 → v0.1.1 → v0.2.0)
- VERSIONING.md
- COMPATIBILITY.md
- ARCHITECTURE.md (28-module map + data-flow diagram from PROJECT_AUDIT)
- AGENTS.md (file map; "to add a backend, edit these 4 files"; CLI cheat sheet)
- legal/DPA-template.md
- legal/THIRD_PARTY_NOTICES.md

**Deliverable:** any reviewer (persona 5) can find what they need in <5 minutes.

### Wave 4 — tests + CI (1 day)
- pytest scaffold; one test per LLM backend (mocked HTTP); config schema + migration round-trip; transcriber argv assembly; commands/snippets matchers; learner correction extraction; search filtering
- `.github/workflows/ci.yml` extended: `ruff check` (gating), `mypy` (gating), `pytest`, `python -m build`, `pip install .` smoke on **3.9 AND 3.10 AND 3.11** (would have caught SS3)
- `pip-audit` step
- Pin runtime deps via `pip-tools` lockfile

**Deliverable:** every PR is CI-verified; SS-class regressions caught before merge.

### Wave 5 — release infrastructure (½ day)
- Extend `release.yml`: PyPI publish via Trusted Publisher OIDC (R4, R8); generate GitHub Release body from `CHANGELOG.md` (R5); assert `pyproject.toml` version matches the git tag (R2)
- Reserve `openvoiceflow` on PyPI (D2)
- `RELEASE.md` (3-command happy path + when-things-go-wrong)
- DMG signing + notarization — only if D6 = yes
- Stand up `shimoverse/homebrew-tap` repo with the formula (R9; PRD has the formula text already)

**Deliverable:** `git tag v0.3.0 && git push --tags` ⇒ wheel + sdist on PyPI, DMGs on GitHub Release, brew formula updated.

### Wave 6 — pre-publish 4-agent parallel review (Mohit's standing instruction)
- Security review: SECURITY.md sufficiency, key-leak surfaces, auto-learner threat model
- DX review: fresh-clone-to-first-paste timing on a clean Mac
- Docs accuracy: every command in every doc actually runs clean
- Cold-start integrator: persona 1's journey from README to working fork

**Deliverable:** four independent green-lights before transferring the repo + tagging the public release.

---

## Decisions still blocking Phase 4

| # | Decision |
|---|---|
| **D1** | GitHub owner / org for the published repo (Today: `shimoverse`. Options: keep, move to `mohitjain`, or new dedicated org) |
| **D2** | PyPI package name — claim `openvoiceflow`? |
| **D3** | Min Python: 3.9 (with `from __future__ import annotations`) or 3.10 (cleaner code; loses macOS 12 default Python) |
| **D4** | Default LLM backend — Gemini (zero-config) or Ollama (privacy default) |
| **D5** | API-key + profile + dictionary + snippets storage — chmod 600 plaintext, or Keychain via `keyring` (would add a runtime dep)? |
| **D6** | DMG signing/notarization — pay $99/yr Apple Developer fee, yes/no |
| **D7** | v0.2.1 scope — only ship-stoppers (Wave 1), or full pre-publish bundle (all six waves) |
| **D8** | `log_transcripts` default — on (current) or off (privacy default) |
| **D9** | `auto_learn` default — on or off, and what's the consent step |
| **D10** | Voice-command count — fix the 24 vs 14 inconsistency |
| **D11** | Anthropic + Groq default model choices — keep Haiku/Llama-3.1-8B (cheap) or revisit |
| **D12** | Telemetry — formally commit to "none" in PRIVACY.md, OR ship a documented anonymous "did update succeed" ping |

---

## What I'm NOT doing without your explicit approval

- Editing any `voiceflow/*.py` source
- Committing any of the audit docs
- Pushing anything (per your standing memory: never push without explicit ask)
- Publishing to PyPI
- Transferring the repo
- Spending money on Apple Dev membership
- Starting Phase 4 (brainstorm + spec + plan + execute)

---

## Recommended next move

Phase 4 is ready to start. The shape I'd brainstorm into:
1. Read PROJECT_AUDIT + PERSONA_AUDIT + this checklist
2. Decide **D1, D3, D5, D7** (the biggest unblockers; the rest can default)
3. Tell me whether to:
   - (a) Brainstorm + spec + plan + execute the full 6-wave bundle as **v0.3.0** (~3 working days for Claude, paced over a few sessions), OR
   - (b) Cut a focused **v0.2.1** that fixes only Wave 1 ship-stoppers (½ day), then do the rest later, OR
   - (c) Different scope you suggest

I lean (a) — the readiness work is mostly orthogonal templates and tests; doing it as one bundle makes for a clean "OpenVoiceFlow goes public" moment rather than dribbling fixes into v0.2.x.
