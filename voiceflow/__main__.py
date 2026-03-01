"""OpenVoiceFlow CLI entry point."""
import sys
import argparse
from .config import (
    load_config, save_config, get_api_key,
    VALID_HOTKEYS, VALID_MODELS, VALID_BACKENDS, validate_config
)


def main():
    parser = argparse.ArgumentParser(
        prog="openvoiceflow",
        description="🎙️ OpenVoiceFlow — Free voice dictation for macOS",
    )
    parser.add_argument("--menubar", action="store_true", help="Run as menu bar app")
    parser.add_argument("--onboarding", "--setup", action="store_true", help="Run setup wizard")
    parser.add_argument("--test", action="store_true", help="Test pipeline with microphone")
    parser.add_argument("--hotkey", choices=VALID_HOTKEYS, help="Set hotkey")
    parser.add_argument("--model", choices=VALID_MODELS, help="Set whisper model")
    parser.add_argument("--backend", choices=VALID_BACKENDS, help="Set LLM backend")
    parser.add_argument("--set-key", nargs=2, metavar=("BACKEND", "KEY"), help="Set API key")
    parser.add_argument("--set-prompt", metavar="PROMPT", help="Set custom LLM cleanup prompt")
    parser.add_argument("--clear-prompt", action="store_true", help="Reset to default LLM prompt")
    parser.add_argument("--show-config", action="store_true", help="Print current config")
    args = parser.parse_args()

    config = load_config()

    # Validate config on load
    errors = validate_config(config)
    if errors:
        print("⚠️  Config issues detected:")
        for e in errors: print(f"   • {e}")
        print("   Run: openvoiceflow --setup to fix\n")

    if args.hotkey:
        config["hotkey"] = args.hotkey
        save_config(config)
        print(f"✅ Hotkey set to: {args.hotkey}")

    if args.model:
        config["whisper_model"] = args.model
        save_config(config)
        print(f"✅ Whisper model set to: {args.model}")

    if args.backend:
        config["llm_backend"] = args.backend
        save_config(config)
        print(f"✅ LLM backend set to: {args.backend}")

    if args.set_key:
        backend, key = args.set_key
        key_field = f"{backend}_api_key"
        config[key_field] = key
        save_config(config)
        print(f"✅ API key saved for: {backend}")

    if args.set_prompt:
        config["llm_prompt"] = args.set_prompt
        save_config(config)
        print(f"✅ Custom LLM prompt saved.")

    if args.clear_prompt:
        config["llm_prompt"] = None
        save_config(config)
        print("✅ LLM prompt reset to default.")

    if args.show_config:
        import json
        safe = {k: ("***" if "key" in k and v else v) for k, v in config.items()}
        print(json.dumps(safe, indent=2))
        return

    if any([args.hotkey, args.model, args.backend, args.set_key, args.set_prompt, args.clear_prompt]):
        return

    if args.onboarding:
        from .onboarding import run_onboarding
        run_onboarding()
        return

    if args.test:
        from .app import OpenVoiceFlow
        app = OpenVoiceFlow()
        if app.validate_setup():
            print("\n✅ All checks passed. Run openvoiceflow to start.")
        return

    # First run — launch onboarding
    is_first_run = not config.get("gemini_api_key") and \
                   not config.get("openai_api_key") and \
                   not config.get("anthropic_api_key") and \
                   not config.get("groq_api_key") and \
                   config.get("llm_backend") != "ollama" and \
                   config.get("llm_backend") != "none"

    if is_first_run:
        print("👋 Welcome to OpenVoiceFlow! Starting setup wizard...")
        from .onboarding import run_onboarding
        run_onboarding()
        config = load_config()

    if args.menubar:
        from .menubar import run_menubar
        run_menubar()
    else:
        from .app import OpenVoiceFlow
        app = OpenVoiceFlow()
        app.run()


if __name__ == "__main__":
    main()
