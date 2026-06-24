# Third-Party Notices

This file enumerates the third-party software OpenVoiceFlow depends on at runtime, along with each component's license. It is intended for procurement, legal, and security reviewers verifying that OpenVoiceFlow's dependency tree is compatible with their organisation's licensing posture.

OpenVoiceFlow itself is licensed under MIT. See [`LICENSE`](../../LICENSE).

Repository: <https://github.com/shimoverse/openvoiceflow>
Source of truth for runtime dependencies: [`pyproject.toml`](../../pyproject.toml).

---

## 1. Direct runtime dependencies (Python)

These are the packages declared in `[project].dependencies` and `[project.optional-dependencies]` in `pyproject.toml`.

### Core (always installed)

| Package        | License        | Version constraint | Role                                  | Upstream                                                 |
| -------------- | -------------- | ------------------ | ------------------------------------- | -------------------------------------------------------- |
| `sounddevice`  | MIT            | `>=0.4`            | Microphone capture (PortAudio bindings). | <https://github.com/spatialaudio/python-sounddevice/blob/master/LICENSE> |
| `numpy`        | BSD-3-Clause   | `>=1.20`           | Audio buffer math.                    | <https://github.com/numpy/numpy/blob/main/LICENSE.txt>   |
| `pynput`       | LGPL-3.0       | `>=1.7`            | Global hotkey listener.               | <https://github.com/moses-palmer/pynput/blob/master/COPYING.LGPL> |

**LGPL note for procurement.** `pynput` is the only LGPL-3.0 component. We consume it as a normal Python import — i.e. it is dynamically loaded at runtime, not statically linked into a derivative work. LGPL-3.0 explicitly permits this usage pattern: the consuming program (OpenVoiceFlow) does not become a derivative work of the library, and the obligations are limited to (a) preserving copyright/licence notices and (b) allowing the user to substitute a modified version of `pynput` if they wish. Both are satisfied by our MIT-licensed pip-installable distribution. No copyleft obligation propagates to OpenVoiceFlow itself or to consumers of OpenVoiceFlow.

### Optional extras

Installed only when the user opts in via `pip install ".[menubar]"`, `".[overlay]"`, or `".[all]"`.

| Package                    | Extra      | License        | Version constraint | Role                                       | Upstream                                                 |
| -------------------------- | ---------- | -------------- | ------------------ | ------------------------------------------ | -------------------------------------------------------- |
| `rumps`                    | `menubar`  | BSD-3-Clause   | `>=0.4`            | macOS menubar UI.                          | <https://github.com/jaredks/rumps/blob/master/LICENSE>   |
| `pyobjc-framework-Cocoa`   | `overlay`  | MIT            | `>=9.0`            | AppKit bridging (overlay HUD, frontmost-app detection, Accessibility API). | <https://github.com/ronaldoussoren/pyobjc/blob/master/pyobjc-core/License.txt> |

## 2. Transitive runtime dependencies

Pulled in automatically by the direct deps above. Versions are resolved by pip at install time and are not pinned by OpenVoiceFlow.

| Package                                      | Pulled in by              | License | Role                                          |
| -------------------------------------------- | ------------------------- | ------- | --------------------------------------------- |
| `pyobjc-core`                                | `pyobjc-framework-Cocoa`  | MIT     | Core Python ↔ Objective-C bridge.             |
| `pyobjc-framework-Quartz` (and others)       | `pyobjc-framework-Cocoa`  | MIT     | Additional AppKit / Quartz bindings auto-pulled by Cocoa. |
| `CFFI`                                       | `sounddevice`             | MIT     | C foreign-function interface used by sounddevice. |
| `pycparser`                                  | `cffi` (transitive)       | BSD-3-Clause | C parser used by cffi.                    |

The full set of `pyobjc-framework-*` sub-packages installed alongside `pyobjc-framework-Cocoa` varies slightly by pyobjc version. All pyobjc components are MIT-licensed under the same upstream LICENSE. `[verify]` — confirm the exact transitive set with `pip install ".[all]" && pip list` against the v0.3 release artefact.

## 3. External binaries and models (not Python deps)

These are not pip-installed, but they are pieces OpenVoiceFlow loads at runtime. We document them here for completeness.

| Component                        | License | Distribution channel                            | Role                                                  |
| -------------------------------- | ------- | ----------------------------------------------- | ----------------------------------------------------- |
| `whisper.cpp` (`whisper-cli` / `whisper-cpp` binary) | MIT | Installed via Homebrew (`brew install whisper-cpp`); not bundled in our DMG. | Local speech-to-text engine. |
| `whisper-stream` binary          | MIT     | Bundled with the Homebrew `whisper-cpp` formula. | Real-time streaming transcription.                    |
| `ggml-*.bin` model files (e.g. `ggml-base.en.bin`) | MIT, per the upstream `ggerganov/whisper.cpp` HuggingFace repo | Downloaded at first run from `huggingface.co/ggerganov/whisper.cpp`. | Whisper model weights consumed by `whisper.cpp`. |

Upstream license: <https://github.com/ggerganov/whisper.cpp/blob/master/LICENSE>.

## 4. LLM provider SDKs — none bundled

OpenVoiceFlow's LLM backends (OpenRouter, Groq, OpenAI, Anthropic, Ollama) are implemented in `voiceflow/llm/*.py` using only the Python standard library — `urllib`, `json`, `ssl`. No vendor SDK is shipped or required.

This means there is no OpenRouter, `openai`, `anthropic`, or `groq` SDK in our dependency tree, and consequently no licensing obligation flowing from those SDKs.

## 5. Bundled docs, fonts, and assets

The DMG contains Python source code, the launcher shell script, and the project-generated OpenVoiceFlow app icon. No third-party fonts, images, or icon sets with separate licenses are bundled. The overlay HUD draws using macOS system fonts (San Francisco), which carry no separate licensing obligation for an app running on macOS.

## 6. Build- and dev-time only (not shipped)

For completeness — these appear in `[project.optional-dependencies].dev` and never reach end users:

| Package        | License | Role                          |
| -------------- | ------- | ----------------------------- |
| `pytest`       | MIT     | Test runner.                  |
| `pytest-cov`   | MIT     | Coverage plugin.              |
| `ruff`         | MIT     | Linter / formatter.           |
| `build`        | MIT     | PEP 517 build front-end.      |
| `twine`        | Apache-2.0 | PyPI upload tool.          |
| `setuptools`, `wheel` | MIT | Build backend.            |

## 7. Cumulative license posture

The runtime-shipped license set is:

- **MIT** — `sounddevice`, `pyobjc-framework-Cocoa` (+ all pyobjc-* siblings), `pyobjc-core`, `cffi`, `whisper.cpp`, `whisper-stream`, `ggml-*` model files, OpenVoiceFlow itself.
- **BSD-3-Clause** — `numpy`, `rumps`, `pycparser`.
- **LGPL-3.0** — `pynput` (dynamically loaded; see §1 note).

There is **no GPL-2.0-or-later or GPL-3.0 obligation** propagating to OpenVoiceFlow or to its consumers. The LGPL-3.0 component is consumed in a manner permitted without copyleft propagation.

## 8. Trademark notice

The names "OpenRouter", "Gemma", "GPT-4o", "Claude", "Llama", "Whisper", "Homebrew", "macOS", and "Apple Silicon" are trademarks of their respective owners. OpenVoiceFlow references them descriptively to identify the third-party services or platforms it interoperates with, and does not claim affiliation with, endorsement by, or sponsorship from any of those owners.

---

## How this list is maintained

This file is regenerated each release. Pull requests that touch `pyproject.toml` (adding, removing, or upgrading a runtime dependency) **must** update this file in the same PR.

**Follow-up flagged for the maintainer:** add this rule to the [`CONTRIBUTING.md`](../../CONTRIBUTING.md) PR checklist so the obligation is enforced at review time rather than relying on memory.

Last reviewed against:

- `pyproject.toml` runtime deps (core + optional extras).
- `main` branch at v0.3.0.
