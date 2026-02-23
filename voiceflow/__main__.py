"""OpenVoiceFlow CLI entry point."""
import argparse
import sys
import time
import tempfile
import os
from .config import load_config, save_config, CONFIG_PATH
from .transcriber import download_model


def main():
    parser = argparse.ArgumentParser(
        description="OpenVoiceFlow — Free voice dictation for macOS",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  openvoiceflow                          Start listening (CLI mode)
  openvoiceflow --menubar                Start as menu bar app
  openvoiceflow --onboarding             Launch GUI setup wizard
  openvoiceflow --set-key gemini KEY     Set Gemini API key
  openvoiceflow --backend ollama         Switch to fully local (free) LLM
  openvoiceflow --test                   Test the full pipeline
  openvoiceflow --setup                  Interactive CLI setup
        """,
    )
    parser.add_argument("--menubar", action="store_true", help="Run as menu bar app")
    parser.add_argument("--onboarding", action="store_true", help="Launch GUI setup wizard")
    parser.add_argument("--setup", action="store_true", help="Interactive CLI setup wizard")
    parser.add_argument("--test", action="store_true", help="Test with a 3-second recording")
    parser.add_argument("--set-key", nargs=2, metavar=("BACKEND", "KEY"),
                        help="Set API key (e.g., --set-key gemini YOUR_KEY)")
    parser.add_argument("--backend", metavar="NAME",
                        help="Set LLM backend (gemini, openai, anthropic, groq, ollama, none)")
    parser.add_argument("--model", metavar="MODEL", help="Set whisper model (tiny.en, base.en, small.en, medium.en)")
    parser.add_argument("--hotkey", metavar="KEY", help="Set hotkey (right_cmd, right_alt, f5, etc.)")
    args = parser.parse_args()

    config = load_config()

    # --- Set API key ---
    if args.set_key:
        backend, key = args.set_key
        key_map = {
            "gemini": "gemini_api_key",
            "openai": "openai_api_key",
            "anthropic": "anthropic_api_key",
            "groq": "groq_api_key",
        }
        if backend not in key_map:
            print(f"❌ Unknown backend: {backend}")
            print(f"   Available: {', '.join(key_map.keys())}")
            sys.exit(1)
        config[key_map[backend]] = key
        save_config(config)
        print(f"✅ {backend} API key saved to {CONFIG_PATH}")
        return

    # --- Set backend ---
    if args.backend:
        valid = ["gemini", "openai", "anthropic", "groq", "ollama", "none"]
        if args.backend not in valid:
            print(f"❌ Unknown backend: {args.backend}")
            print(f"   Available: {', '.join(valid)}")
            sys.exit(1)
        config["llm_backend"] = args.backend
        save_config(config)
        print(f"✅ LLM backend set to: {args.backend}")
        return

    # --- Set model ---
    if args.model:
        config["whisper_model"] = args.model
        save_config(config)
        print(f"✅ Whisper model set to: {args.model}")
        download_model(args.model)
        return

    # --- Set hotkey ---
    if args.hotkey:
        config["hotkey"] = args.hotkey
        save_config(config)
        print(f"✅ Hotkey set to: {args.hotkey}")
        return

    # --- GUI Onboarding ---
    if args.onboarding:
        from .onboarding import run_onboarding
        run_onboarding()
        return

    # --- Interactive CLI setup ---
    if args.setup:
        interactive_setup(config)
        return

    # --- Test pipeline ---
    if args.test:
        test_pipeline(config)
        return

    # --- Menu bar mode ---
    if args.menubar:
        from .menubar import run_menubar
        run_menubar()
        return

    # --- First-run onboarding ---
    from .onboarding import needs_onboarding, run_onboarding
    if needs_onboarding():
        print("🎙️  Welcome to OpenVoiceFlow! Launching setup wizard...")
        config = run_onboarding()
        if not config:
            print("Setup cancelled.")
            return

    # --- Default: CLI listener ---
    from .app import OpenVoiceFlow
    OpenVoiceFlow().run()


def interactive_setup(config):
    """Interactive setup wizard."""
    from .llm import BACKENDS

    print("🔧 OpenVoiceFlow Setup\n")

    # LLM backend
    print("LLM backends for transcript cleanup:")
    print("  gemini    — Google Gemini Flash (cheapest, ~$3/year)")
    print("  openai    — OpenAI GPT-4o-mini")
    print("  anthropic — Anthropic Claude Sonnet")
    print("  groq      — Groq Llama 3.3 (fast, free tier)")
    print("  ollama    — Ollama local models (fully free, needs Ollama installed)")
    print("  none      — No cleanup (raw transcripts only)")
    backend = input(f"\nBackend [{config['llm_backend']}]: ").strip()
    if backend:
        config["llm_backend"] = backend

    # API key
    chosen = config["llm_backend"]
    if chosen in ("gemini", "openai", "anthropic", "groq"):
        key_field = f"{chosen}_api_key"
        current = config.get(key_field, "")
        masked = f"...{current[-8:]}" if len(current) > 8 else "(not set)"
        urls = {
            "gemini": "https://aistudio.google.com/apikey",
            "openai": "https://platform.openai.com/api-keys",
            "anthropic": "https://console.anthropic.com/",
            "groq": "https://console.groq.com/keys",
        }
        print(f"\nGet your key at: {urls[chosen]}")
        key = input(f"API key [{masked}]: ").strip()
        if key:
            config[key_field] = key

    # Whisper model
    print("\nWhisper models (bigger = more accurate, slower):")
    print("  tiny.en   — ~75 MB, fastest")
    print("  base.en   — ~142 MB, balanced (recommended)")
    print("  small.en  — ~466 MB, more accurate")
    print("  medium.en — ~1.5 GB, high accuracy")
    model = input(f"Model [{config['whisper_model']}]: ").strip()
    if model:
        config["whisper_model"] = model

    # Hotkey
    print("\nHotkey options: right_cmd, right_alt, left_alt, f5, f6, f7, f8")
    hotkey = input(f"Hotkey [{config['hotkey']}]: ").strip()
    if hotkey:
        config["hotkey"] = hotkey

    save_config(config)
    print(f"\n✅ Config saved to {CONFIG_PATH}")
    download_model(config["whisper_model"])
    print("\n🎉 Setup complete! Run 'openvoiceflow' to start.")


def test_pipeline(config):
    """Test the full pipeline with a short recording."""
    from .recorder import AudioRecorder
    from .transcriber import transcribe
    from .llm import cleanup_text

    print("🧪 Testing OpenVoiceFlow pipeline...\n")
    print("🎤 Recording for 3 seconds — say something!")

    recorder = AudioRecorder(
        sample_rate=config["sample_rate"],
        channels=config["channels"],
    )
    recorder.start()
    time.sleep(3)
    recorder.stop()

    with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as f:
        temp_path = f.name

    try:
        recorder.save_wav(temp_path)
        print("\n🔄 Transcribing...")
        raw = transcribe(temp_path, config)
        print(f"📝 Raw: {raw}")

        if raw:
            print("\n✨ Cleaning with LLM...")
            cleaned = cleanup_text(raw, config)
            print(f"✅ Cleaned: {cleaned}")
        else:
            print("⚠️  No speech detected")
    finally:
        if os.path.exists(temp_path):
            os.unlink(temp_path)


if __name__ == "__main__":
    main()
