# Pending tasks before v0.3.0 actually publishes

> Created: 2026-04-27 evening, after `v0.3.0-rc1` came out green.
> Branch state at creation: `main` at `0e946fa`. `v0.3.0-rc1` tag pushed; `v0.3.0` tag NOT pushed (waiting on the items below).

## Three things only Mohit can do

### 1. Reserve `openvoiceflow` on PyPI via Trusted Publisher OIDC

Go to **https://pypi.org/manage/account/publishing/**. Log in (or create account). Add a **Pending GitHub Publisher**:

| Field | Value |
|---|---|
| PyPI Project Name | `openvoiceflow` |
| Owner | `shimoverse` |
| Repository name | `openvoiceflow` |
| Workflow name | `release.yml` |
| Environment name | (leave blank) |

Why "pending publisher" not "manual upload first": PyPI accepts the first OIDC token from `release.yml` as the project-creator. No long-lived API token, no manual `twine upload`, cleanest path. About 5 minutes.

### 2. Decide GitHub repo visibility

Three options:

- **Stay private.** PyPI publish still works (PyPI doesn't check GitHub visibility). README badges and the GitHub-Release wheel URL will 404 until you flip public.
- **Make current repo public.** `gh repo edit shimoverse/openvoiceflow --visibility public`. Anyone who clones during the public window has it forever — that's fine for an MIT project but worth a beat to confirm.
- **Transfer to a personal GitHub account first** (Decision D1, deferred). After transfer, the Trusted Publisher OIDC config from step 1 needs re-doing under the new owner/repo path.

### 3. Fill placeholders before going public

Things flagged during Wave 3 that need your hand:

- `SECURITY.md` — `<security-email-tbd>` placeholder
- `CODE_OF_CONDUCT.md` — optional moderation-email if you want one separate from the security advisory channel
- `docs/COMPLIANCE.md` — HIPAA/GDPR per-provider claims worth a quick lawyer pass

## What Claude does next, after you signal

```bash
git tag -a v0.3.0 -m "v0.3.0"
git push origin v0.3.0
```

Workflow runs ~1 minute. PyPI publish lands. GitHub Release v0.3.0 (not Pre-release this time) gets the wheel + sdist + both DMGs. We confirm `pip install openvoiceflow` works from a clean Mac and call it done.

## v0.3.x follow-ups (post-publish, not blocking)

These were tracked through the audit but explicitly deferred from v0.3.0:

| ID | Item | Notes |
|---|---|---|
| W2C | Onboarding UI opt-in screens for `log_transcripts` and `auto_learn` | Defaults are off; users currently opt in via CLI flags or config edit. The flagship "Personalize" path could ask explicitly. |
| W2E | Real API-key validation in onboarding (provider ping) | Current check is length≥10. A 1-second `/v1/models` request per provider would catch typos and expired keys at setup time. |
| W2F | `openvoiceflow doctor` diagnostic command | `app.validate_setup()` has half of what's needed; ~50 lines to wire as a CLI subcommand. Self-recovery surface for "is this thing on?" questions. |
| W4 | Broader pytest coverage | 60 tests pin the ship-stoppers + privacy invariants. Next add: `_make_prompt` chain in `llm/base.py` (5+ moving parts, zero coverage today). |
| v0.4-A | Collapse `STYLE_PROMPTS` (`styles.py`) and `STYLE_PRESETS` (`llm/base.py`) into one source | Two registries with subtly different copy. |
| v0.4-B | One-time HAS_APPKIT-False warn for CLI users | Currently silent if PyObjC is missing; users lose overlay HUD without explanation. |
| v0.4-C | Frontmost-app snapshot to fix wrong-app paste race | Snapshot at hotkey-release; paste only if focus didn't change. |
| v0.4-D | HuggingFace model checksum verification | First-run model download has no integrity check. |
| v0.4-E | `pip-tools` lockfile + Dependabot | Reproducible builds; supply-chain hygiene. |
| v0.4-F | Restrict auto-learner to same-role focused fields | Currently watches any focused text field. Narrow the surface. |
| v0.4-G | Bump GitHub Actions to Node.js 24-compatible majors when upstreams ship them | Deprecation warning on every CI run, hard cutover by September 2026. |

## When you've done steps 1–3, ping Claude

Just say "PyPI is set up, repo is [public/private/transferred-to-X]" and Claude will tag and push.
