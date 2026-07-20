# Website deploy — switching downloads to the native 0.4.0 app

The site currently serves the **Python 0.3.6** DMGs (macOS 12+). This is the
checklist to point it at the **native 0.4.0** app once the notarized DMG exists
(built by `release-native.yml` — see `native/RELEASE_NATIVE_RUNBOOK.md`).

It is intentionally **not applied yet**: the download page is checksum-forward,
and `tests/test_docs_distribution.py` verifies the DMG exists and its SHA-256
matches. Neither can be truthful until the binary is built — so this waits for
the artifact, then goes live in one reviewed merge.

`docs/appcast.xml` (shipped now) is the empty Sparkle feed so a running app's
"Check for Updates…" resolves cleanly to "up to date" until the first release.

## When the notarized `OpenVoiceFlow-0.4.0.dmg` exists

Native ships as **one universal DMG** (arm64 + x86_64 in a single binary), not
the Python split-arch pair — the download page simplifies to a single build.

1. **Drop the artifacts in:**
   - `cp OpenVoiceFlow-0.4.0.dmg docs/downloads/`
   - overwrite `docs/appcast.xml` with the signed feed the Release produced.
   - `sha256=$(shasum -a 256 docs/downloads/OpenVoiceFlow-0.4.0.dmg | awk '{print $1}')`

2. **`docs/download.html`** — replace the two `data-arch` build rows with one
   universal build row, and update:
   - JSON-LD `"operatingSystem": "macOS 14+"`, `"softwareVersion": "0.4.0"`,
     single `downloadUrl` → `…/downloads/OpenVoiceFlow-0.4.0.dmg`.
   - hero `Download v0.4.0`; the recommendation copy → "one universal build,
     Apple Silicon and Intel".
   - checksum line → the computed `sha256` (one line, not two).
   - notes → "macOS 14 or later" (WhisperKit floor); keep the signed/notarized
     paragraph; drop "byte-for-byte copies of v0.3.6".

3. **`docs/site.js`** — point the download logic at the single universal DMG
   (`/downloads/OpenVoiceFlow-0.4.0.dmg`); keep the `download_click` analytics
   event; arch detection is no longer needed to pick a file.

4. **`docs/index.html`, `docs/install.html`, `docs/how-it-works.html`** — change
   "macOS 12+"/"macOS 12 or later" claims to **macOS 14+**, and any `0.3.6`
   version string to `0.4.0`. Keep the local-first / free-forever messaging.

5. **`tests/test_docs_distribution.py`** — set `RELEASE_VERSION = "0.4.0"`,
   collapse the arm64/x86_64 constants to a single `UNIVERSAL_SHA256`, and
   change the split-build assertions to the single-universal-DMG shape. Keep the
   hash check gated so it only asserts when the DMG is present.

6. **`vercel.json`** — add redirects from the retired Python DMG paths
   (`/downloads/OpenVoiceFlow-0.3.6-{arm64,x86_64}.dmg`) to
   `/downloads/OpenVoiceFlow-0.4.0.dmg`, mirroring the existing redirect block.

7. **Decision — macOS 12–13 users.** Native requires macOS 14 (WhisperKit). If
   a fallback matters, keep one retained Python `0.3.6` DMG reachable via a
   small "on macOS 12–13?" link; otherwise 0.4.0 fully replaces it.

8. Run `pytest tests/test_docs_distribution.py`, open the preview, verify the
   download + `https://openvoiceflow.vercel.app/appcast.xml`, then merge.
