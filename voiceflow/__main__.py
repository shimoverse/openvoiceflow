"""OpenVoiceFlow CLI entry point."""
import sys
import argparse
from .config import (
    load_config, save_config, get_api_key,
    VALID_HOTKEYS, VALID_MODELS, VALID_BACKENDS, VALID_STYLES, validate_config
)
from . import __version__


def main():
    parser = argparse.ArgumentParser(
        prog="openvoiceflow",
        description="🎙️ OpenVoiceFlow — Free voice dictation for macOS",
    )
    # BUG-019 fix: add --version flag
    parser.add_argument(
        "--version", action="version",
        version=f"%(prog)s {__version__}",
    )
    parser.add_argument("--menubar", action="store_true", help="Run as menu bar app")
    parser.add_argument("--onboarding", "--setup", dest="onboarding", action="store_true", help="Run setup wizard")
    parser.add_argument("--test", action="store_true", help="Test pipeline with microphone")
    parser.add_argument("--hotkey", choices=VALID_HOTKEYS, help="Set hotkey")
    parser.add_argument("--model", choices=VALID_MODELS, help="Set whisper model")
    parser.add_argument("--backend", choices=VALID_BACKENDS, help="Set LLM backend")
    parser.add_argument("--set-key", nargs=2, metavar=("BACKEND", "KEY"), help="Set API key")
    parser.add_argument("--set-prompt", metavar="PROMPT", help="Set custom LLM cleanup prompt")
    parser.add_argument("--clear-prompt", action="store_true", help="Reset to default LLM prompt")
    parser.add_argument("--show-config", action="store_true", help="Print current config")

    # Personal dictionary
    parser.add_argument("--add-word", metavar="WORD", help="Add a word to personal dictionary")
    parser.add_argument("--remove-word", metavar="WORD", help="Remove a word from personal dictionary")
    parser.add_argument("--list-words", action="store_true", help="List personal dictionary words")

    # Snippets
    parser.add_argument("--add-snippet", nargs=2, metavar=("TRIGGER", "TEXT"),
                        help="Add a voice snippet (trigger phrase → expansion)")
    parser.add_argument("--remove-snippet", metavar="TRIGGER", help="Remove a voice snippet")
    parser.add_argument("--list-snippets", action="store_true", help="List all voice snippets")

    # Language
    parser.add_argument("--language", metavar="LANG", help="Set transcription language (e.g., en, es, de, ja, auto)")

    # Style
    parser.add_argument("--style", choices=VALID_STYLES, help="Set output style/tone")

    # Statistics
    parser.add_argument("--stats", action="store_true", help="Show dictation statistics")

    # Auto-start at login
    parser.add_argument(
        "--autostart", choices=["on", "off"],
        help="Enable/disable launch at login via LaunchAgent",
    )

    args = parser.parse_args()

    config = load_config()

    # Validate config on load
    errors = validate_config(config)
    if errors:
        print("⚠️  Config issues detected:")
        for e in errors: print(f"   • {e}")
        print("   Run: openvoiceflow --setup to fix\n")

    # --- Dictionary commands ---
    if args.add_word:
        from .dictionary import add_word
        add_word(args.add_word)
        print(f"✅ Added to dictionary: {args.add_word}")
        return

    if args.remove_word:
        from .dictionary import remove_word
        if remove_word(args.remove_word):
            print(f"✅ Removed from dictionary: {args.remove_word}")
        else:
            print(f"⚠️  Word not found: {args.remove_word}")
        return

    if args.list_words:
        from .dictionary import list_words
        words = list_words()
        if words:
            print("📖 Personal dictionary:")
            for w in words:
                print(f"   • {w}")
        else:
            print("📖 Dictionary is empty. Add words with: openvoiceflow --add-word \"MyWord\"")
        return

    # --- Snippet commands ---
    if args.add_snippet:
        from .snippets import add_snippet
        trigger, text = args.add_snippet
        add_snippet(trigger, text)
        print(f"✅ Snippet added: \"{trigger}\" → \"{text[:50]}{'...' if len(text) > 50 else ''}\"")
        return

    if args.remove_snippet:
        from .snippets import remove_snippet
        if remove_snippet(args.remove_snippet):
            print(f"✅ Snippet removed: \"{args.remove_snippet}\"")
        else:
            print(f"⚠️  Snippet not found: \"{args.remove_snippet}\"")
        return

    if args.list_snippets:
        from .snippets import list_snippets
        snips = list_snippets()
        if snips:
            print("📌 Voice snippets:")
            for trigger, expansion in snips.items():
                print(f"   \"{trigger}\" → \"{expansion[:60]}{'...' if len(expansion) > 60 else ''}\"")
        else:
            print("📌 No snippets. Add one: openvoiceflow --add-snippet \"insert sig\" \"Best regards, Name\"")
        return

    # --- Statistics ---
    if args.stats:
        from .stats import show_stats
        show_stats()
        return

    # --- Config setters ---
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

    if args.language:
        config["language"] = args.language
        # Auto-switch to multilingual model if language isn't English
        if args.language != "en" and config.get("whisper_model", "").endswith(".en"):
            base = config["whisper_model"].replace(".en", "")
            config["whisper_model"] = base
            print(f"✅ Language set to: {args.language}")
            print(f"✅ Switched to multilingual model: {base}")
        else:
            print(f"✅ Language set to: {args.language}")
        save_config(config)

    if args.style:
        config["style"] = args.style
        save_config(config)
        print(f"✅ Style set to: {args.style}")

    if args.autostart:
        from .autostart import set_autostart, get_autostart_status
        enabled = args.autostart == "on"
        success, msg = set_autostart(enabled)
        if success:
            state = "enabled" if enabled else "disabled"
            print(f"✅ Launch at login {state}: {msg}")
            config["launch_at_login"] = enabled
            save_config(config)
        else:
            print(f"❌ Autostart failed: {msg}")
        return

    if args.show_config:
        import json
        safe = {k: ("***" if "key" in k and v else v) for k, v in config.items()}
        print(json.dumps(safe, indent=2))
        return

    if any([args.hotkey, args.model, args.backend, args.set_key, args.set_prompt,
            args.clear_prompt, args.language, args.style]):
        return

    # --- Startup update check (non-blocking) ---
    try:
        from .updater import check_for_updates
        check_for_updates()
    except Exception:
        pass

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
