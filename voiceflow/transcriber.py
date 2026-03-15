"""Local transcription using whisper.cpp."""
import os
import subprocess
from pathlib import Path
from .config import MODELS_DIR


def _is_whisper_cpp(binary: str) -> bool:
    """Check if the found binary is actually whisper.cpp (not Python openai-whisper)."""
    try:
        result = subprocess.run(
            [binary, "--help"],
            capture_output=True, text=True, timeout=5,
        )
        output = (result.stdout + result.stderr).lower()
        # whisper.cpp help output contains ggml or whisper-cpp references
        return "ggml" in output or "whisper-cpp" in output or "whisper.cpp" in output
    except Exception:
        return False


def find_whisper_cpp() -> str | None:
    """Auto-detect whisper.cpp binary location.

    BUG-017 fix: prefer whisper-cli and whisper-cpp names first.
    Only accept a binary named 'whisper' if it actually outputs whisper.cpp-style help
    (contains 'ggml' or 'whisper.cpp'), to avoid false detection of the openai-whisper
    Python CLI.
    """
    # Check explicit whisper.cpp names first (these are never the Python CLI)
    for name in ["whisper-cli", "whisper-cpp"]:
        result = subprocess.run(["which", name], capture_output=True, text=True)
        if result.returncode == 0:
            path = result.stdout.strip()
            if path:
                return path

    # Explicit known paths for whisper.cpp (not Python whisper)
    explicit_paths = [
        "/opt/homebrew/bin/whisper-cli",
        "/opt/homebrew/bin/whisper-cpp",
        "/usr/local/bin/whisper-cli",
        "/usr/local/bin/whisper-cpp",
        os.path.expanduser("~/whisper.cpp/main"),
        os.path.expanduser("~/whisper.cpp/build/bin/whisper-cli"),
    ]
    for p in explicit_paths:
        if os.path.isfile(p) and os.access(p, os.X_OK):
            return p

    # Fall back to 'whisper' only if it is actually whisper.cpp
    result = subprocess.run(["which", "whisper"], capture_output=True, text=True)
    if result.returncode == 0:
        path = result.stdout.strip()
        if path and _is_whisper_cpp(path):
            return path

    return None


def get_model_path(model_name: str) -> str:
    """Get path to a whisper.cpp model file."""
    model_file = f"ggml-{model_name}.bin"
    model_path = MODELS_DIR / model_file

    if model_path.exists():
        return str(model_path)

    # Check common alternate locations (Apple Silicon + Intel Mac)
    for alt in [
        Path.home() / "whisper.cpp" / "models" / model_file,
        Path("/opt/homebrew/share/whisper-cpp/models") / model_file,
        Path("/opt/homebrew/share/whisper-cpp") / model_file,
        Path("/usr/local/share/whisper-cpp/models") / model_file,  # Intel Mac
        Path("/usr/local/share/whisper-cpp") / model_file,         # Intel Mac
        Path.home() / ".cache" / "whisper" / model_file,
    ]:
        if alt.exists():
            return str(alt)

    return str(model_path)


def download_model(model_name: str) -> str | None:
    """Download a whisper.cpp model from HuggingFace."""
    model_path = get_model_path(model_name)
    if os.path.exists(model_path):
        return model_path

    print(f"⬇️  Downloading whisper model '{model_name}'...")
    url = f"https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-{model_name}.bin"
    MODELS_DIR.mkdir(parents=True, exist_ok=True)

    try:
        subprocess.run(["curl", "-L", "-o", model_path, url], check=True)
        print(f"✅ Model downloaded to {model_path}")
        return model_path
    except subprocess.CalledProcessError:
        print(f"❌ Failed to download model from {url}")
        return None


def transcribe(audio_path: str, config: dict) -> str | None:
    """Transcribe audio using whisper.cpp."""
    whisper_bin = config.get("whisper_cpp_path") or find_whisper_cpp()
    if not whisper_bin:
        print("❌ whisper.cpp not found! Install with: brew install whisper-cpp")
        return None

    model_path = get_model_path(config["whisper_model"])
    if not os.path.exists(model_path):
        model_path = download_model(config["whisper_model"])
        if not model_path:
            return None

    cmd = [
        whisper_bin,
        "-m", model_path,
        "-f", audio_path,
        "-l", config.get("language", "en"),
        "--no-timestamps",
        "-t", "4",
    ]

    try:
        result = subprocess.run(cmd, capture_output=True, text=True, timeout=30)
        if result.returncode != 0:
            print(f"❌ Whisper error: {result.stderr}")
            return None

        text = result.stdout.strip()
        text = text.replace("[BLANK_AUDIO]", "").strip()
        return text if text else None
    except subprocess.TimeoutExpired:
        print("❌ Whisper timed out")
        return None
