# Versioning

How OpenVoiceFlow numbers its releases and what you can expect from a
version bump.

## Policy

OpenVoiceFlow follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html)
in spirit, with the standard pre-1.0 caveat: while we're on `0.x.y`, a
minor bump (`0.2.x → 0.3.0`) **can** technically include breaking
changes. We try hard to avoid it — when we do break something, the
CHANGELOG calls it out and the migration is automatic where possible
(see the v0.3.0 `cleanup_prompt → llm_prompt` migration as the canonical
example).

Once we ship `1.0.0`, we go strict: breaking changes only on a major
bump, and we'll commit to the overlap rules in the **Cadence + EOL**
section below.

## What "breaking" means here

OpenVoiceFlow is an end-user app, not a library. There's no public API
to break. So "breaking" specifically means one of these three:

1. **Removing or renaming a CLI flag.** If `--auto-learn on/off` becomes
   `--learn on/off`, that's breaking — every shell alias, every doc,
   every screenshot a user has saved is now wrong.
2. **Removing or renaming a config key.** Keys in
   `~/.openvoiceflow/config.json` are part of the contract. If we rename
   one, we ship a migration that runs at config-load time and preserves
   the user's value. SS5 in v0.3.0 (`cleanup_prompt → llm_prompt`) was
   the first time we got this right.
3. **Changing on-disk paths or file layouts** in `~/.openvoiceflow/`
   without a migration. If `profile.json` becomes `profile/main.json`,
   we either move it for you or it's a major bump.

## What is NOT breaking

These can land on a patch or minor bump without ceremony:

- **Adding a new CLI flag.** Old invocations keep working.
- **Adding a new config key with a default.** Old config files load
  fine; the new key just gets its default until the user sets it.
- **Adding a new LLM backend.** Existing backends are unchanged.
- **Internal refactors.** No public API exists to break. Module moves,
  function renames, and schema changes inside `voiceflow/` don't count.
- **Default-value changes that respect existing user state.** v0.3.0
  flipped `log_transcripts` and `auto_learn` from `True` to `False`,
  but only for fresh installs — anyone with an existing `config.json`
  keeps their setting. That's not a breaking change.

## Cadence + EOL

Best-effort, single-maintainer cadence. No promised SLAs while we're
pre-1.0.

- **Pre-1.0:** we support the latest minor only. If `0.4.0` is out,
  please upgrade from `0.3.x`. No security backports to older minors.
- **Post-1.0:** we'll commit to **one minor of overlap**. When `1.2.0`
  ships, `1.1.x` keeps getting security fixes for one minor cycle, then
  we drop it.

## Pre-release tags

Release candidates use `v0.3.0-rc1`, `v0.3.0-rc2`, etc. We use these to
exercise the release pipeline (PyPI Trusted Publisher, DMG build, brew
formula bump) end-to-end before tagging the real release. Don't pin
production installs to an `-rc` tag.

## How to read a release tag

Every git tag in the form `vX.Y.Z` has a matching section in
[CHANGELOG.md](CHANGELOG.md) with the Added / Changed / Fixed / Security
breakdown for that release. The CHANGELOG is the source of truth — the
GitHub Release body is generated from it.

If you're upgrading and want to know what changed for you, the
**Changed** and **Security** sections are the ones that affect existing
installs; **Added** is purely additive.
