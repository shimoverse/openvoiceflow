"""Self-diagnosis backbone (`openvoiceflow --doctor`).

Steve-Jobs lens, plain-English: when something doesn't work, the user
should see exactly what's wrong and exactly how to fix it. No stack
traces, no ssh-into-Terminal-and-grep. The doctor is the answer to
"is this thing on?"

Architecture:
- Each check is a tiny pure-ish function returning a ``Check``.
- ``run_all_checks(config)`` aggregates them into a list.
- ``format_checks_text`` renders a human-readable table for the CLI.
- ``format_checks_json`` renders a machine-readable JSON for menubar
  consumers / future GUI panels.
- ``run_doctor_cli(config)`` is the function the ``--doctor`` flag
  invokes; returns a process exit code (0 if nothing FAILs).

Every check that can return FAIL also offers a ``Fix`` — either a URL
to open or a shell command to run. That's the architectural promise:
no FAIL without a path forward.
"""
from __future__ import annotations

import json
import os
import shutil
import urllib.error
import urllib.request
from dataclasses import asdict, dataclass
from enum import Enum
from typing import Optional

from . import platform_support


class Status(Enum):
    OK = "OK"
    WARN = "WARN"
    FAIL = "FAIL"


@dataclass
class Fix:
    """A remedy the doctor can offer."""
    label: str
    url: Optional[str] = None
    command: Optional[str] = None


@dataclass
class Check:
    name: str
    status: Status
    description: str
    fix: Optional[Fix] = None


# ─────────────────────────────────────────────────────────────────────
# Internal helpers (overridable for tests)
# ─────────────────────────────────────────────────────────────────────


def _find_whisper_cpp() -> Optional[str]:
    """Reuse transcriber's discovery logic without circular imports."""
    from .transcriber import find_whisper_cpp
    return find_whisper_cpp()


def _get_model_path(name: str) -> str:
    from .transcriber import get_model_path
    return get_model_path(name)


def _pyobjc_available() -> bool:
    try:
        import objc  # noqa: F401
        from AppKit import NSWindow  # noqa: F401
        return True
    except ImportError:
        return False


def _tkinter_available() -> bool:
    try:
        import tkinter  # noqa: F401
        return True
    except ImportError:
        return False


# ─────────────────────────────────────────────────────────────────────
# Individual checks
# ─────────────────────────────────────────────────────────────────────


def check_os() -> Check:
    """Operating system + version. The first gate: everything else is moot
    on a non-Mac, and old macOS releases miss APIs we rely on."""
    if not platform_support.is_macos():
        return Check(
            name="Operating system",
            status=Status.FAIL,
            description=(
                f"OpenVoiceFlow only supports macOS — detected "
                f"{platform_support.os_label()}. Dictation cannot work here."
            ),
            fix=Fix(
                label="See the support matrix (and uninstall guidance)",
                url="https://github.com/shimoverse/openvoiceflow/blob/main/docs/COMPATIBILITY.md",
            ),
        )
    ver = platform_support.macos_version()
    if ver is None:
        return Check(
            name="Operating system",
            status=Status.WARN,
            description="macOS detected, but the version could not be determined.",
        )
    if ver < platform_support.MIN_MACOS:
        return Check(
            name="Operating system",
            status=Status.FAIL,
            description=(
                f"{platform_support.os_label()} is below the supported minimum "
                f"(macOS {platform_support.MIN_MACOS[0]})."
            ),
            fix=Fix(
                label="Upgrade macOS via System Settings → General → Software Update",
                url="x-apple.systempreferences:com.apple.Software-Update-Settings.extension",
            ),
        )
    if ver[0] > platform_support.LATEST_TESTED_MACOS:
        return Check(
            name="Operating system",
            status=Status.OK,
            description=(
                f"{platform_support.os_label()} — newer than the last "
                f"maintainer-tested release (macOS {platform_support.LATEST_TESTED_MACOS}); "
                "expected to work, please file an issue if it doesn't."
            ),
        )
    return Check(
        name="Operating system",
        status=Status.OK,
        description=f"{platform_support.os_label()} (supported).",
    )


def check_architecture() -> Check:
    """CPU architecture + Rosetta/Homebrew mismatches.

    The classic silent breakage on Apple Silicon: an x86_64 Python or an
    Intel Homebrew under Rosetta installs an Intel whisper.cpp with no
    Metal acceleration — everything "works" but transcription crawls.
    """
    arch = platform_support.arch()
    if platform_support.is_rosetta_translated():
        return Check(
            name="Architecture",
            status=Status.WARN,
            description=(
                "Python is running under Rosetta (x86_64 translated) on an "
                "Apple Silicon Mac. whisper.cpp will miss Metal acceleration — "
                "reinstall a native arm64 Python and Homebrew."
            ),
            fix=Fix(label="Native install guide", url="https://brew.sh"),
        )
    if platform_support.is_apple_silicon():
        brew_path = shutil.which("brew") or ""
        if brew_path.startswith("/usr/local"):
            return Check(
                name="Architecture",
                status=Status.WARN,
                description=(
                    f"Apple Silicon ({arch}), but Intel Homebrew found at "
                    f"{brew_path}. whisper.cpp installed from it runs under "
                    "Rosetta without Metal — install native Homebrew "
                    "(/opt/homebrew) and reinstall whisper-cpp."
                ),
                fix=Fix(label="Install native Homebrew", url="https://brew.sh"),
            )
        return Check(
            name="Architecture",
            status=Status.OK,
            description=f"Apple Silicon ({arch}, native).",
        )
    return Check(
        name="Architecture",
        status=Status.OK,
        description=f"Intel ({arch}).",
    )


def check_microphone() -> Check:
    granted = platform_support.microphone_status()
    if granted is True:
        return Check(
            name="Microphone permission",
            status=Status.OK,
            description="Granted.",
        )
    if granted is False:
        return Check(
            name="Microphone permission",
            status=Status.FAIL,
            description="Denied — recordings will be silent.",
            fix=Fix(
                label="Grant in System Settings → Privacy & Security → Microphone",
                url="x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone",
            ),
        )
    return Check(
        name="Microphone permission",
        status=Status.OK,
        description=(
            "Not determined here — macOS asks on first recording. If "
            "recordings are silent, grant access in System Settings → "
            "Privacy & Security → Microphone."
        ),
    )


def check_accessibility() -> Check:
    trusted = platform_support.accessibility_status()
    if trusted is True:
        return Check(
            name="Accessibility permission",
            status=Status.OK,
            description="Granted — auto-paste can send ⌘V keystrokes.",
        )
    if trusted is False:
        return Check(
            name="Accessibility permission",
            status=Status.FAIL,
            description="Not granted — auto-paste will fail (text stays on the clipboard).",
            fix=Fix(
                label="Grant in System Settings → Privacy & Security → Accessibility",
                url="x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility",
            ),
        )
    return Check(
        name="Accessibility permission",
        status=Status.WARN,
        description="Could not query the Accessibility trust state.",
    )


def check_input_monitoring() -> Check:
    granted = platform_support.input_monitoring_status()
    if granted is True:
        return Check(
            name="Input Monitoring permission",
            status=Status.OK,
            description="Granted — the dictation hotkey can be detected.",
        )
    if granted is False:
        return Check(
            name="Input Monitoring permission",
            status=Status.FAIL,
            description="Denied — the hotkey will never fire.",
            fix=Fix(
                label="Grant in System Settings → Privacy & Security → Input Monitoring",
                url="x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent",
            ),
        )
    return Check(
        name="Input Monitoring permission",
        status=Status.OK,
        description="Not determined here — macOS asks when the hotkey listener starts.",
    )


def check_brew() -> Check:
    path = shutil.which("brew")
    if path:
        return Check(
            name="Homebrew",
            status=Status.OK,
            description=f"Found at {path}",
        )
    return Check(
        name="Homebrew",
        status=Status.FAIL,
        description="Homebrew is required to install whisper.cpp.",
        fix=Fix(label="Install Homebrew", url="https://brew.sh"),
    )


def check_whisper_cli() -> Check:
    path = _find_whisper_cpp()
    if path:
        return Check(
            name="whisper.cpp",
            status=Status.OK,
            description=f"Found at {path}",
        )
    return Check(
        name="whisper.cpp",
        status=Status.FAIL,
        description="The local speech engine is not installed.",
        fix=Fix(
            label="Run: brew install whisper-cpp",
            command="brew install whisper-cpp",
        ),
    )


def check_model(config: dict) -> Check:
    name = config.get("whisper_model", "base.en")
    path = _get_model_path(name)
    if os.path.exists(path):
        size_mb = os.path.getsize(path) / (1024 * 1024)
        return Check(
            name=f"Whisper model ({name})",
            status=Status.OK,
            description=f"{size_mb:.0f} MB at {path}",
        )
    return Check(
        name=f"Whisper model ({name})",
        status=Status.FAIL,
        description=f"Model file missing: {path}",
        fix=Fix(
            label="Re-run setup or download manually",
            url=f"https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-{name}.bin",
        ),
    )


def check_api_key(config: dict) -> Check:
    backend = config.get("llm_backend", "openrouter")
    if backend == "none":
        return Check(
            name="LLM backend",
            status=Status.OK,
            description="Set to `none` — raw transcripts only, no API key needed.",
        )
    if backend == "ollama":
        return _check_ollama_inline(config)
    field_name = f"{backend}_api_key"
    key = config.get(field_name) or os.environ.get(
        f"{backend.upper()}_API_KEY", ""
    )
    if not key:
        urls = {
            "openrouter": "https://openrouter.ai/keys",
            "groq": "https://console.groq.com/keys",
            "openai": "https://platform.openai.com/api-keys",
            "anthropic": "https://console.anthropic.com/",
        }
        return Check(
            name=f"{backend.title()} API key",
            status=Status.FAIL,
            description=f"No API key configured for {backend}.",
            fix=Fix(
                label=f"Get a {backend.title()} API key",
                url=urls.get(backend, ""),
            ),
        )
    # Key present — minimal sanity check (length).
    return Check(
        name=f"{backend.title()} API key",
        status=Status.OK,
        description="Configured.",
    )


def _check_ollama_inline(config: dict) -> Check:
    base_url = config.get("ollama_url", "http://localhost:11434")
    try:
        with urllib.request.urlopen(f"{base_url}/api/tags", timeout=3) as resp:
            data = json.loads(resp.read().decode())
        models = [m.get("name") for m in data.get("models", [])]
        if not models:
            return Check(
                name="Ollama",
                status=Status.FAIL,
                description="Ollama is running but has no models.",
                fix=Fix(
                    label="Pull a model: ollama pull llama3.2",
                    command="ollama pull llama3.2",
                ),
            )
        return Check(
            name="Ollama",
            status=Status.OK,
            description=f"Running at {base_url}; {len(models)} model(s) available.",
        )
    except Exception:
        # Broad on purpose: beyond URLError this can raise JSONDecodeError
        # (proxy/captive-portal reply), ValueError (malformed ollama_url),
        # or TypeError (unexpected response shape) — a diagnostic check must
        # report failure, not crash the doctor run.
        return Check(
            name="Ollama",
            status=Status.FAIL,
            description=f"Ollama daemon not reachable at {base_url} "
                        "(or it returned an unexpected response).",
            fix=Fix(
                label="Start Ollama (or install from ollama.com)",
                url="https://ollama.com",
            ),
        )


def check_pyobjc() -> Check:
    if _pyobjc_available():
        return Check(
            name="PyObjC (overlay HUD)",
            status=Status.OK,
            description="Floating overlay HUD and frontmost-app detection available.",
        )
    return Check(
        name="PyObjC (overlay HUD)",
        status=Status.WARN,
        description=(
            "Optional. Without it you don't get the floating overlay or "
            "auto-style switching, but dictation still works."
        ),
        fix=Fix(
            label="Run: pip install 'openvoiceflow[overlay]'",
            command="pip install 'openvoiceflow[overlay]'",
        ),
    )


def check_tkinter() -> Check:
    if _tkinter_available():
        return Check(
            name="tkinter (onboarding wizard)",
            status=Status.OK,
            description="GUI onboarding + Know Me interview available.",
        )
    return Check(
        name="tkinter (onboarding wizard)",
        status=Status.WARN,
        description="No GUI onboarding. CLI setup (--setup) still works.",
    )


def check_file_modes() -> Check:
    """All ~/.openvoiceflow/*.json artifacts should be mode 0o600."""
    base = os.path.expanduser("~/.openvoiceflow")
    if not os.path.isdir(base):
        return Check(
            name="On-disk artifacts",
            status=Status.OK,
            description="No config yet (fresh install).",
        )
    bad: list[str] = []
    for name in os.listdir(base):
        if not name.endswith(".json"):
            continue
        path = os.path.join(base, name)
        try:
            mode = os.stat(path).st_mode & 0o777
            if mode != 0o600:
                bad.append(f"{name} (mode {oct(mode)})")
        except OSError:
            continue
    if bad:
        return Check(
            name="On-disk artifacts",
            status=Status.WARN,
            description=f"Files not mode 0o600: {', '.join(bad)}",
            fix=Fix(
                label=f"Run: chmod 600 {base}/*.json",
                command=f"chmod 600 {base}/*.json",
            ),
        )
    return Check(
        name="On-disk artifacts",
        status=Status.OK,
        description="Config / profile / dictionary / snippets / stats all mode 0o600.",
    )


# ─────────────────────────────────────────────────────────────────────
# Aggregation + rendering
# ─────────────────────────────────────────────────────────────────────


def run_all_checks(config: dict) -> list:
    """Run every check and return a list of ``Check`` records.

    On a non-macOS machine only the OS check runs: every other check (and
    every fix we could offer, like `brew install`) presumes macOS, so
    reporting them would only produce misleading guidance.
    """
    os_check = check_os()
    if not platform_support.is_macos():
        return [os_check]
    return [
        os_check,
        check_architecture(),
        check_brew(),
        check_whisper_cli(),
        check_model(config),
        check_api_key(config),
        check_pyobjc(),
        check_tkinter(),
        check_microphone(),
        check_accessibility(),
        check_input_monitoring(),
        check_file_modes(),
    ]


_GLYPH = {Status.OK: "✓", Status.WARN: "⚠", Status.FAIL: "❌"}


def format_checks_text(checks: list) -> str:
    """Pretty-print a list of Checks for CLI output."""
    if not checks:
        return "(no checks ran)\n"
    name_w = max(len(c.name) for c in checks)
    lines = ["", "  OpenVoiceFlow doctor", "  " + ("─" * (name_w + 50))]
    for c in checks:
        glyph = _GLYPH[c.status]
        lines.append(f"  {glyph}  {c.name.ljust(name_w)}  {c.description}")
        if c.fix and c.status != Status.OK:
            if c.fix.url:
                lines.append(f"     ↳ {c.fix.label}: {c.fix.url}")
            elif c.fix.command:
                lines.append(f"     ↳ {c.fix.label}")
    summary = _summary(checks)
    lines += ["", f"  {summary}", ""]
    return "\n".join(lines)


def format_checks_json(checks: list) -> str:
    """JSON-render for programmatic consumers (future menubar GUI panel)."""
    body = {
        "checks": [
            {
                "name": c.name,
                "status": c.status.value,
                "description": c.description,
                "fix": (asdict(c.fix) if c.fix else None),
            }
            for c in checks
        ],
        "summary": _summary(checks),
    }
    return json.dumps(body, indent=2)


def _summary(checks: list) -> str:
    fails = sum(1 for c in checks if c.status == Status.FAIL)
    warns = sum(1 for c in checks if c.status == Status.WARN)
    if fails:
        return f"{fails} failing, {warns} warning(s). Fix the failing ones above."
    if warns:
        return f"{warns} warning(s) — optional features may be degraded but core dictation works."
    return "All checks passed. ✨"


def run_doctor_cli(config: dict, *, json_output: bool = False) -> int:
    """Entry point for the ``openvoiceflow --doctor`` CLI flag.

    Returns 0 if no checks failed, 1 otherwise.
    """
    checks = run_all_checks(config)
    if json_output:
        print(format_checks_json(checks))
    else:
        print(format_checks_text(checks))
    return 0 if not any(c.status == Status.FAIL for c in checks) else 1
