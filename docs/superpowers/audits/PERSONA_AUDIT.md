# OpenVoiceFlow — Persona Friction Audit (Phase 2, v0.2.0)

> **Status:** Discovery output. Not committed. Pairs with `PROJECT_AUDIT.md`.
> Audited: 2026-04-27 against `HEAD = 3b03d29` (v0.2.0).
>
> Reframings (kept from Phase 1): "Indie developer integrating in their app" → **forking/extending**; "Self-hoster deploying in production" → **IT lead deploying to a team / running fully-local Ollama at scale**.

Severity legend: 🔴 ship-stopper · 🟠 major · 🟡 minor

---

## Persona 1 — Indie developer (extending/forking)

> "I want to fork this, swap in a custom LLM (or my company's internal LLM gateway), tweak the cleanup prompt for my workflows, and ship it to my team."

### Journey on v0.2.0

1. README: clear pitch in 30 s ✅
2. Clones repo (URL is correct now ✅).
3. Tries Option 3 manual: `python3 -m venv .venv && .venv/bin/pip install -e ".[all]"` → wheel builds ✅ (SS1 fixed).
4. Tries `.venv/bin/openvoiceflow --help` → if their default `python3` is **3.9** (system default on macOS 12+), 🔴 **TypeError on `config.py:113`** at module import. (SS3 still broken.)
5. Pivots to 3.11 venv → works ✅.
6. Reads code → feels well-organized. New v0.2 modules (`learner`, `interview`, `streamer`, etc.) are short and well-commented.
7. Wants to add a backend → `LLMBackend` interface changed in v0.2: `cleanup()` now takes `context`, `app_context`, `override_style`. They look at `groq_backend.py` as a template — fine. They add their backend to `BACKENDS` in `llm/__init__.py` ✅. They forget to add it to `onboarding.py:BACKENDS` (a duplicate UI registry). Their backend works from CLI but is missing from the GUI wizard. Confusing 🟡.
8. Wants to test their backend → no test infra; they dictate at it manually. Their backend passes → ship it.
9. Wants to share with team → `bash build-dmg.sh` produces split arm64 + x86_64 DMGs ✅. Unsigned → teammates need to override Gatekeeper. Many give up.
10. Wants to keep fork in sync → no `CONTRIBUTING.md`, no branch policy, no upgrade migration story (and the v0.2 `cleanup_prompt → llm_prompt` rename was silent — they realize their custom prompt wasn't picked up after rebasing).

### Friction table

| Step | Friction | Severity | Mitigation |
|---|---|---|---|
| `pip install` on Python 3.9 | Crashes at import | 🔴 | Add `from __future__ import annotations` to all `.py` files OR bump `requires-python = ">=3.10"`. (Decision D3.) |
| `~/.local/bin/openvoiceflow` shim | install.sh writes a broken shim | 🔴 | One-line fix: `exec "$VENV_DIR/bin/openvoiceflow" "$@"` (use the pip-installed console script) |
| Add a backend | Two registries to update (`llm/__init__.py`, `onboarding.py`) | 🟡 | Single source of truth; have onboarding import metadata from the backend class itself |
| Test the backend | No test infra | 🟠 | pytest scaffold + mocked HTTP per backend |
| Ship to team | Unsigned DMG | 🟡 | Notarize (D6); or document Gatekeeper override prominently |
| Stay in sync | No CONTRIBUTING / VERSIONING / migration notes | 🟠 | Add the three; document the `cleanup_prompt → llm_prompt` migration retrospectively |
| Custom prompt loss on upgrade | `cleanup_prompt` renamed to `llm_prompt` with no migration code | 🔴 (SS5) | Add an upgrade step in `config.py:load_config()` — if `cleanup_prompt` exists, copy to `llm_prompt`, drop the old key, log it once |

**Time-to-running fork:** ~30 min if they hit Python 3.10 and write a single new backend. Up to half a day if they hit the 3.9 crash, the silent prompt rename, or the broken install.sh shim.

---

## Persona 2 — End user (the dictation user)

> "I want to dictate emails and code without paying $144/year for Wispr Flow."

### Journey on v0.2.0 (DMG path — primary install)

1. README + landing page → "Free, local, smart" → clicks "Download for Mac" → GitHub Releases page.
2. **Repo is currently private** → 404. (Will be fine after publish; not a long-term issue. Still a deal-breaker for anyone the link is shared with today.)
3. After publish: downloads the right DMG (arm64 if Apple Silicon — README and landing page need to make that arch detection clear ✅ build-dmg now produces split DMGs).
4. Drags to Applications → first launch → Gatekeeper override (System Settings → Privacy & Security → Open Anyway).
5. App launches → tkinter onboarding wizard pops up. Clean UI, 4 steps (welcome → backend → API key → hotkey).
6. Picks Gemini, pastes key, picks Right Cmd → "Personalize OpenVoiceFlow ✨" button → 🔴 **if `interview.py` errors for ANY reason, the button silently does nothing** (SS6, `onboarding.py:455-458`). User sees "nothing happened, did I break it?" — no log, no diagnostic.
7. If interview works: 6 screens collect name, occupation, industry, names/tools they say a lot, communication style. Profile auto-populates dictionary. ✅
8. Menu bar icon appears. User holds Right Cmd, says "schedule a meeting for um Thursday no wait Friday." Floating overlay HUD shows red dot recording → animated dots processing → check ✅. Cleaned text pasted in Gmail. Magic.
9. Two days later: switches to VS Code, dictates "make a function that returns prime numbers." Per-app auto-style detects `code` mode (from default `app_styles` mapping). LLM cleans differently. ✅
10. Three days later: notices `~/.openvoiceflow/profile.json` and `~/OpenVoiceFlow/logs/2026-04-29.md` contain everything they've said. Plaintext. Mode 644. Slight panic 🟠.
11. Switches back to Wispr Flow because of the privacy concerns. Repo loses a user.

### Friction table

| Step | Friction | Severity | Mitigation |
|---|---|---|---|
| Repo private during pre-publish | Anyone sharing the link before publish hits 404 | 🟡 | Just don't share until public; ensure transferred + made public on Day 0 |
| Personalize button silently fails | `try/except/pass` in `onboarding.py:455-458` | 🔴 (SS6) | Log the exception; show a "personalization couldn't start, here's why" dialog with a retry |
| Gatekeeper override per machine | Unsigned DMG | 🟠 | Notarize (D6) |
| Right Cmd hotkey collisions | Same v0.1 issue | 🟠 | Default to F5; warn during onboarding if Right Cmd is chosen |
| Wrong-app paste race | Wider window in v0.2 because of streaming/overlay | 🟠 | Snapshot frontmost app at hotkey-release; if focus changed, copy-only + notify |
| API key plaintext | Same v0.1 issue + new `profile.json` joins it | 🔴 | chmod 600 minimum; Keychain ideal (D5) |
| Profile / logs plaintext default-on | New surface — name, employer, colleague names; every dictation | 🔴 | Default-off for logs; opt-in step in onboarding; chmod 600 (D8) |
| Auto-learn watching focused text | Strong privilege; no in-app disclosure | 🟠 | Onboarding step explaining what auto-learn does + how to disable; default on after consent (D9) |
| No "is this thing working?" | Same v0.1 issue | 🟡 | `openvoiceflow doctor` |
| Update path | `updater.py` exists but only notifies; no auto-update | 🟡 | Either land Sparkle-style auto-update or just ship a "click here to download" notification |
| `cleanup_prompt → llm_prompt` upgrade silently drops user's custom prompt | If user customized v0.1 prompt | 🔴 (SS5) | One-shot migration in `load_config()` |
| 24 vs 14 voice commands inconsistency | landing page says 24, README table shows 14, README claim says ✅ 24 | 🟡 (D10) | Pick a number, verify it matches `commands.py`, fix all three places |

**Time-to-first-cleaned-paste (today, after publish):** ~5 min on a happy path (DMG, Apple Silicon, network is fine). Up to an hour on the unhappy path (Intel Mac, slow brew install, Gatekeeper, or the silent personalization failure).

---

## Persona 3 — AI coding agent (Claude Code, Cursor, Copilot)

> "Install OpenVoiceFlow on this Mac and configure it with my Gemini key" / "Add a Mistral backend."

### 3a) Install-and-configure flow

| Step | What the agent reads | Friction | Severity |
|---|---|---|---|
| Find install instructions | README Option 1 (DMG) | DMG requires GUI override the agent can't perform | 🟠 |
| Fall back to install.sh | README Option 2 | URL is correct now, runs → installs venv + deps + model + the broken `~/.local/bin/openvoiceflow` shim | 🔴 |
| Run `openvoiceflow --help` after install | The shim runs `python3 -m openvoiceflow` | 🔴 fails | 🔴 |
| Fall back to manual pip | README Option 3 | Works on 3.10+ ✅; fails on 3.9 (most macOS default Pythons) | 🔴 (3.9) / ✅ (3.10+) |
| Once running, set key | `--set-key gemini KEY` ✅ | Stable, well-named flag |
| Verify | `openvoiceflow --test` exists ✅ |  |
| Background it | `--menubar` flag exists; documented |  |

**Net for 3a:** Two of the three install paths the agent can attempt are broken; the third works only if the agent thinks to use a 3.10+ venv (and even then, the agent has to skip install.sh and use pip directly, then run the venv's `bin/openvoiceflow` directly). Most agents will fail or hallucinate around the broken shim.

### 3b) Add-a-backend flow

| Step | Friction | Severity |
|---|---|---|
| Find extension point | `voiceflow/llm/base.py`; clear ✅ |  |
| Find example | All 5 backends are short single-files; pick `groq_backend.py` ✅ |  |
| Notice the v0.2 interface change | `cleanup()` signature now takes `context, app_context, override_style` — a careful agent reads `base.py` first; a sloppy one will copy `groq_backend.py` and break compat with v0.1 | 🟡 |
| Register in `BACKENDS` | `voiceflow/llm/__init__.py` ✅ |  |
| Add config keys | `config.py:DEFAULTS` ✅ |  |
| Add API-key flag | `__main__.py:key_map` ✅ |  |
| Add to onboarding registry | `onboarding.py:BACKENDS` (duplicate) — easy to miss | 🟡 |
| Add to menubar | `menubar.py` reads from main `BACKENDS` ✅ |  |
| Test | No test infra | 🟠 |
| Verify nothing else broke | CI runs ruff (non-blocking) + import smoke | 🟠 |

**Net for 3b:** Code structure is friendly to agents. The dual `BACKENDS` registry is the same v0.1 footgun.

### Common friction

| Friction | Severity | Mitigation |
|---|---|---|
| No `AGENTS.md` | 🟠 | Add per agentsmd.org. Should cover: file map (28 files now); "to add a backend, edit these 4 files"; CLI cheat sheet (40+ flags); "do NOT edit dist/ or build/ artifacts" |
| Two `BACKENDS` registries | 🟡 | One source of truth |
| README claim "Audio never leaves your Mac" | An agent quoting README → relays a half-truth | 🟠 | Already addressed in PROJECT_AUDIT §5 #1 |
| Install paths broken for agent | 2 of 3 paths fail | 🔴 | Fix SS2 + SS3 |

---

## Persona 4 — IT lead deploying to a team

> "I want to roll this out to 30 Macs at my company. We have MDM (Jamf/Mosyle); we don't allow random `curl … | bash`; we can't send transcripts to consumer LLMs."

### Journey on v0.2.0

1. Reads README → privacy claim looks great → 🟠 same half-truth as v0.1 about transcripts.
2. Reads PRD → discovers `shimoverse/homebrew-tap` is **promised but doesn't exist yet**. So no `brew install --cask openvoiceflow` for clean MDM packaging.
3. Looks at install paths:
   - DMG: unsigned → MDM-pushable but each user clicks through Gatekeeper → bad UX, plus security review will flag the `arm64` vs `x86_64` arch detection (no signed manifest).
   - install.sh: shim broken (SS2). Even if fixed, `curl | bash` is blocked by their security policy.
   - PyPI: not published. (Also wouldn't help — their users don't have admin pip.)
4. Looks for a config-management story → none. Each user runs the `Know Me` interview, edits their own `~/.openvoiceflow/config.json`, has their own keys. No managed config; no ability to lock backend to "Ollama only" or to a corporate LLM gateway.
5. Looks for offline install → undocumented. Possible (pre-stage `~/.openvoiceflow/`, `brew bundle` whisper-cpp, ship a wheel) — but they'd have to figure it out.
6. Looks for telemetry → none ✅. But also no `PRIVACY.md` to point their CISO at.
7. Looks for SBOM / pinning → `requirements.txt` and install.sh use `>=` only. PyObjC is a transitive that comes via `rumps` only.
8. Looks for the auto-update behavior → `updater.py` phones home to GitHub on every launch. CISO will want this disable-able. There's no env var or config flag to disable it.
9. Looks at the v0.2 expansion of persisted state → 4 new JSON files in `~/.openvoiceflow/` plus daily logs plus a LaunchAgent if launch-at-login is on. None of which are currently chmod 600.

### Friction table

| Concern | Today | Severity | Mitigation |
|---|---|---|---|
| Mass install via MDM | Unsigned DMG; no `.pkg`; no Homebrew tap; no PyPI | 🔴 | Land at least one MDM-friendly path. Notarized DMG (D6) or `brew tap` |
| Lock to local-only | Possible via Ollama; unenforced by the app | 🟠 | "Enforce local mode" managed plist key; bail on cloud backend if set |
| Pre-staged offline install | Undocumented | 🟠 | `docs/airgap.md` |
| API-key central management | Per-user JSON; no env-var fallback for `--set-key`-set keys (env vars work for live config but the wizard always writes to JSON) | 🟠 | Document env-var precedence; ship a managed-plist override |
| SBOM / pinning | None | 🟠 | `pip-tools` lockfile; `requirements.lock.txt` shipped with releases |
| `PRIVACY.md` | Doesn't exist | 🔴 | Wave 3 |
| `SECURITY.md` | Doesn't exist | 🔴 | Wave 3 |
| Update channel | Phones home to GitHub on every launch; no opt-out | 🟠 | Add `update_check: false` config; document |
| `~/.openvoiceflow/` permissions | mode 644 across the board | 🔴 | chmod 600 on save; document the permission model |
| Auto-learn reads focused text | Strong privilege | 🟠 | Default-off for managed deployments; managed-plist override |
| Voice commands ambiguity | "24" vs "14" | 🟡 | Fix |

**Net for 4:** Not deployable today in a regulated environment. With the mitigations above + a Homebrew tap + notarized DMG, deployable for low-stakes teams (≤50 people, BYOK, not regulated). Regulated industries (healthcare/finance/gov) still won't approve — and that's a fair outcome the docs should make explicit.

---

## Persona 5 — Compliance / security reviewer (procurement)

> "Security review before approving 30 employees to install on company Macs. I read SECURITY.md, PRIVACY.md, and the threat model first."

### Procurement-checklist walk-through

| Question | Today (v0.2.0) | Severity |
|---|---|---|
| **License?** | MIT, present, correct ✅ | ✅ |
| **Data-flow diagram?** | Not in repo | 🔴 |
| **Where does audio go?** | Local only ✅ (whisper.cpp + optional whisper-stream) | ✅ |
| **Where does text go?** | 6 backend choices: 4 cloud (Gemini/Groq/OpenAI/Anthropic), 1 local (Ollama), 1 none. Default = Gemini. | 🟠 |
| **What user data is stored?** | `config.json` (keys), `profile.json` (PII), `dictionary.json` (names), `snippets.json` (sensitive text), `stats.json` (aggregate), daily logs (every word). All plaintext, all mode 644. | 🔴 |
| **Auto-learner reading the user's other apps' text fields** | Yes — for 30s after every paste | 🟠 |
| **Sub-processor list?** | Not in repo | 🟠 |
| **Data Processing Addendum (DPA)?** | None | 🟠 |
| **GDPR posture?** | Cloud LLM transcripts may contain PII; consumer terms apply per provider; not fit for EU users w/o their own DPA with the LLM provider | 🔴 (EU) |
| **SOC2 / ISO 27001?** | Single-developer OSS; not applicable, but no doc says so | 🟡 |
| **Vulnerability disclosure?** | No `SECURITY.md` | 🔴 |
| **Supply-chain integrity (sigstore, signed releases)?** | None | 🟠 |
| **Notarized binaries?** | No (Apple Dev fee not paid) | 🟠 |
| **Reproducible builds?** | No pinning | 🟠 |
| **PII redaction option?** | None (a flagship request for any text-to-LLM tool in 2026) | 🟠 |
| **Audit log?** | Daily plaintext logs, on by default, world-readable | 🔴 |
| **Retention policy?** | None | 🟠 |
| **Key storage?** | Plaintext JSON | 🔴 |
| **Telemetry?** | Update check phones GitHub on every launch (public, no PII), nothing else | 🟡 |
| **Threat model document?** | None | 🟠 |
| **CVE history?** | None — but no `SECURITY.md` to put advisories in either | 🟡 |
| **CODE_OF_CONDUCT, CONTRIBUTING?** | None | 🟡 |
| **Maintenance signal?** | 4 commits in last 60 days; 2 releases; ~30 commits total ✅ | ✅ |

### Friction table

| Concern | Severity | Mitigation |
|---|---|---|
| No `SECURITY.md` | 🔴 | Wave 3 — template; supported-version table; report-via channel |
| No `PRIVACY.md` / data-flow diagram | 🔴 | Wave 3 — single page covering audio/text/keys/profile/dictionary/snippets/logs × in-transit/at-rest/sub-processors |
| No `THREAT_MODEL.md` | 🟠 | Wave 3 — STRIDE-lite. Special attention to: prompt-tampering via cleanup_prompt; key exfil via crafted llm_prompt; focus-switch paste race; auto-learner reading sensitive fields |
| No `COMPLIANCE.md` | 🟠 | Explicit: "BYOK self-managed personal-productivity tool. Not SOC2. Not for regulated industries without your own DPA with your LLM provider." |
| API key + profile + logs plaintext | 🔴 | chmod 600 minimum; Keychain ideal (D5) |
| Logs default-on, indexed by `--search` | 🔴 | Default-off; opt-in (D8) |
| README hero claim misleads | 🔴 | Rewrite (D4) |
| No DPA template | 🟠 | `legal/DPA-template.md` boilerplate |
| No third-party notices | 🟡 | `legal/THIRD_PARTY_NOTICES.md` |
| Update phone-home not opt-out-able | 🟠 | Add `update_check` config flag |

**Net for 5:** Today, a competent reviewer rejects this in 5 minutes. **Plus the v0.2 expansion of stored data (`profile.json`, `dictionary.json`, `snippets.json`) and the auto-learner permission make the gap to acceptability bigger than at v0.1.** With Wave 2 + Wave 3 (security/privacy/threat docs + chmod 600 + default-off logs + README rewrite + opt-in auto-learn), a small-team reviewer could plausibly approve it. Regulated reviewers still won't — and `COMPLIANCE.md` should say so explicitly.

---

## Cross-cutting observations

**What v0.2 fixed across personas:**
- `pyproject.toml` build → 3 personas now have working `pip install`
- All `shimoverse-ops` URLs gone → all 5 personas no longer hit 404s
- DMG split arm64/x86_64 → end-user no longer gets Rosetta fallback
- Per-app auto-styling → end-user gets better dictation in code/email apps without flipping flags

**What v0.2 made worse across personas:**
- More state to leak (4 new JSON files); same plaintext storage; same world-readable mode
- New auto-learner permission, no in-app disclosure
- Larger surface for the privacy framing to be wrong about
- Lint debt grew 17 → 43

**What v0.2 left untouched across personas:**
- install.sh shim still broken
- 22 of 28 modules still crash on Python 3.9
- No tests
- No community-health files (SECURITY/PRIVACY/THREAT/COMPLIANCE/CONTRIBUTING/CODE_OF_CONDUCT/CHANGELOG)
- Hotkey collision UX
- Wrong-app paste race

**The same three "cheap wins" still unlock multiple personas:**
- Fix SS2 + SS3 → unlock 1, 3
- Fix SS5 + SS6 + chmod 600 + default-off logs → unlock 2, 4, 5
- Add SECURITY/PRIVACY/THREAT_MODEL → unlock 5 (and earn trust with 4)

**One expensive win:** Apple Developer notarization → unlocks DMG-friction for 2 + makes 4 deployable.

---

## What's next

- **PROJECT_AUDIT.md** ✅ (Phase 1) — what works, what's broken, security/privacy
- **PERSONA_AUDIT.md** ✅ (Phase 2, this doc)
- **READINESS_CHECKLIST.md** (Phase 3) — 49-item open-source readiness checklist re-scored on v0.2.0
- **Phase 4** — only with Mohit's explicit approval after reviewing the three docs
