# Releasing OpenVoiceFlow

This is the maintainer's playbook. End users want [README.md](README.md).

## TL;DR — the three-command happy path

Once the one-time setup below is done, every release is:

```bash
# 1. Update version + CHANGELOG, commit
./scripts/bump-version 0.3.0   # (or do it by hand: pyproject.toml + voiceflow/__init__.py + CHANGELOG section header)
git commit -am "chore: bump to v0.3.0"

# 2. Tag (RC tags don't publish to PyPI; real tags do)
git tag -a v0.3.0 -m "v0.3.0"

# 3. Push
git push origin main --tags
```

That's it. The release workflow does the rest:

- Verifies the tag, `pyproject.toml`, and `voiceflow/__init__.py` all agree on the version
- Builds wheel + sdist, runs `twine check`
- Builds split arm64 + x86_64 DMGs
- Uploads everything to a new GitHub Release
- Publishes wheel + sdist to PyPI via Trusted Publisher OIDC (only on non-pre-release tags)

## Pre-release tags

Use `v0.3.0-rc1` (or `-alpha1` / `-beta1`) to dry-run the pipeline without burning the real version number. The release workflow detects `rc`, `alpha`, `beta`, `dev`, or `aN`/`bN` in the tag and:

- Marks the GitHub Release as "Pre-release"
- **Skips** the PyPI publish step

Use this for the first cut of every minor release. Confirm the artifacts attach correctly, then re-tag the real version once you're satisfied.

## One-time setup

These are not part of every release — they happen once.

### 1. Reserve the PyPI project name

Create the project on PyPI by uploading a placeholder release manually, OR by using the "create empty project" path.

```bash
python -m build
twine upload dist/*
```

You'll need a PyPI account and a one-time token for this initial upload.

### 2. Configure Trusted Publisher OIDC

This replaces the long-lived `PYPI_TOKEN` secret approach. Trusted Publisher means PyPI accepts releases from a specific GitHub workflow without an API token — it verifies via OIDC.

On PyPI: project settings → "Publishing" → "Add a new publisher". Fill in:

- Owner: `shimoverse` (or whichever org you transfer to per Decision D1)
- Repository: `openvoiceflow`
- Workflow filename: `release.yml`
- Environment: leave blank (we don't use a GitHub environment)

After this lands, the workflow's `pypa/gh-action-pypi-publish@release/v1` step will publish without any secret.

### 3. (Optional) Stand up the Homebrew tap

If/when you want `brew tap shimoverse/tap && brew install openvoiceflow`:

- Create `shimoverse/homebrew-tap` (or `shimoverse/homebrew-openvoiceflow`)
- Add a Formula like `Formula/openvoiceflow.rb` matching the PRD's draft (see [PRD.md](PRD.md))
- Update the formula's `url` and `sha256` after each PyPI release. (Can be automated later via a separate workflow if it becomes a chore.)

### 4. (When ready) Code signing + notarization

Skipped for v0.3.0 (Decision D6). When you decide to pay the $99/yr Apple Developer fee:

- Generate a Developer ID Application certificate
- Add `APPLE_ID`, `APPLE_TEAM_ID`, `APPLE_APP_PASSWORD`, `DEVELOPER_ID_CERT_BASE64` to repo secrets
- Add a `codesign` + `xcrun notarytool submit` step to `release.yml` between `build-dmg.sh` and the Release upload
- Update README to drop the Gatekeeper-override footnote

## When things go wrong

| Symptom | What to check first |
|---|---|
| Workflow fails at `verify-version` | Tag ≠ `pyproject.toml` ≠ `voiceflow/__init__.py`. Pick one, propagate, force-update the tag. |
| `twine check` fails | Almost always a malformed README rendering or a missing `[project]` field. Run `python -m build && twine check dist/*` locally. |
| DMG build fails on `bash build-dmg.sh` | Run it locally on a Mac with the `[all]` extras installed; the script is finicky about brew + arch detection. |
| PyPI publish step fails with "Trusted publisher not found" | The OIDC config on PyPI doesn't match the workflow filename or the repo path. Re-check both sides. |
| GitHub Release artifact missing | The two upload jobs (`publish-pypi` and `build-dmg`) target the same Release; race conditions are usually benign — the second upload appends. If something's missing, re-run the failed job. |
| Tag accidentally pushed without bumping the version | Delete the tag locally and remotely (`git tag -d vX.Y.Z; git push origin :refs/tags/vX.Y.Z`), bump, re-tag. |
| PyPI publish for a real tag was the wrong content | Yank the release on PyPI (it stays in the index but is hidden from `pip install`), bump the patch version, re-release. PyPI does not allow overwriting a version. |

## Cutting v0.3.0 — the actual checklist

Before tagging:

- [ ] All Wave 1–6 items in `docs/superpowers/plans/v0.3-readiness.md` are ✅ or explicitly deferred
- [ ] `pytest -q` green on Py 3.9, 3.10, 3.11
- [ ] `ruff check voiceflow/` clean
- [ ] `python -m build && twine check dist/*` clean
- [ ] CHANGELOG.md "Unreleased" → "0.3.0" with date
- [ ] the maintainer has filled in or removed the `<security-email-tbd>` placeholder in SECURITY.md
- [ ] the maintainer has run the 4-agent pre-publish review pass (Wave 6)
- [ ] PyPI Trusted Publisher OIDC is configured
- [ ] Repo is public on GitHub (or you've decided to publish on PyPI before flipping the GitHub repo public)

Then:

```bash
git tag -a v0.3.0-rc1 -m "v0.3.0 release candidate 1"
git push origin v0.3.0-rc1
# Watch the workflow; verify GH Release is marked Pre-release; verify
# DMGs and wheel are attached; verify PyPI was NOT published.

# If everything looks right:
git tag -a v0.3.0 -m "v0.3.0"
git push origin v0.3.0
# Watch the workflow; verify PyPI release lands within ~2 min;
# verify GH Release is final (not Pre-release).
```

## Post-release

- Open a `chore: bump to v0.X.0-dev` PR setting `__version__` and the pyproject version to the next planned minor with a `-dev0` suffix, so accidental local installs from `main` don't conflict with the just-published release.
- Tweet / post / whatever marketing channel. Keep it short.
- Add a "Now / Next" entry to your roadmap noting the v0.4 follow-ups in `docs/superpowers/audits/READINESS_CHECKLIST.md`.

## Maintainer notes

- The release workflow is idempotent in spirit but not in fact. Don't push the same tag twice.
- DMG signing/notarization is a future-the maintainer problem. Until then, every first launch needs a Gatekeeper override; this is documented in README.
- If you transfer the GitHub repo to a different owner (Decision D1), the Trusted Publisher OIDC config on PyPI breaks until you re-add it under the new path.
