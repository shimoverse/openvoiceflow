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

    # Voice commands (Feature 3)
    parser.add_argument("--add-command", nargs=2, metavar=("PHRASE", "REPLACEMENT"),
                        help="Add or update a custom voice command (e.g. --add-command \"new line\" \"\\n\")")
    parser.add_argument("--remove-command", metavar="PHRASE",
                        help="Remove a custom voice command by phrase")
    parser.add_argument("--list-commands", action="store_true",
                        help="List all active voice commands (defaults + custom)")
    parser.add_argument("--voice-commands", choices=["on", "off"],
                        help="Enable or disable voice command replacement")

    # Per-app style management (Feature 2)
    parser.add_argument("--app-style", nargs=2, metavar=("APP", "STYLE"),
                        dest="app_style",
                        help="Set style for a specific app (e.g. --app-style \"Slack\" casual)")
    parser.add_argument("--remove-app-style", metavar="APP",
                        dest="remove_app_style",
                        help="Remove per-app style override for an app")
    parser.add_argument("--list-app-styles", action="store_true",
                        dest="list_app_styles",
                        help="List all per-app style mappings")
    parser.add_argument("--auto-style", choices=["on", "off"],
                        dest="auto_style",
                        help="Enable or disable automatic per-app style detection")

    # Language
    parser.add_argument("--language", metavar="LANG", help="Set transcription language (e.g., en, es, de, ja, auto)")

    # Style
    parser.add_argument("--style", choices=VALID_STYLES, help="Set output style/tone")

    # "Know Me" profile
    parser.add_argument(
        "--profile", action="store_true",
        help="Run the Know Me personalization interview (re-run anytime to update)",
    )
    parser.add_argument(
        "--show-profile", action="store_true", dest="show_profile",
        help="Print the current user profile",
    )
    parser.add_argument(
        "--clear-profile", action="store_true", dest="clear_profile",
        help="Delete the user profile",
    )

    # Statistics
    parser.add_argument("--stats", action="store_true", help="Show dictation statistics")

    # Auto-start at login
    parser.add_argument(
        "--autostart", choices=["on", "off"],
        help="Enable/disable launch at login via LaunchAgent",
    )

    # History search (Feature 6)
    parser.add_argument("--search", metavar="QUERY", help="Search past transcripts")
    parser.add_argument(
        "--search-date", metavar="DATE",
        help="Filter search to a specific date (YYYY-MM-DD)",
    )
    parser.add_argument(
        "--search-last", metavar="DAYS", type=int,
        help="Filter search to the last N days",
    )
    parser.add_argument(
        "--limit", metavar="N", type=int, default=50,
        help="Maximum number of search results (default: 50)",
    )

    # Streaming transcription (Feature 1)
    parser.add_argument(
        "--streaming", choices=["on", "off"],
        help="Enable/disable real-time streaming transcription (requires whisper-stream binary)",
    )
    parser.add_argument(
        "--streaming-step", metavar="MS", type=int,
        dest="streaming_step",
        help="Audio step size in milliseconds for streaming mode (default: 3000)",
    )

    # Auto-learn corrections
    parser.add_argument(
        "--auto-learn", choices=["on", "off"],
        dest="auto_learn",
        help="Enable/disable auto-learning corrections from post-paste edits",
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

    # --- Voice command commands (Feature 3) ---
    if args.add_command:
        from .commands import DEFAULT_COMMANDS
        phrase, replacement = args.add_command
        # Support escape sequences in replacement (e.g. "\\n" → "\n")
        replacement = replacement.replace("\\n", "\n").replace("\\t", "\t")
        custom = config.get("custom_commands", {})
        custom[phrase.lower()] = replacement
        config["custom_commands"] = custom
        save_config(config)
        display = repr(replacement)
        print(f"✅ Voice command added: \"{phrase}\" → {display}")
        return

    if args.remove_command:
        phrase = args.remove_command.lower()
        custom = config.get("custom_commands", {})
        if phrase in custom:
            del custom[phrase]
            config["custom_commands"] = custom
            save_config(config)
            print(f"✅ Custom voice command removed: \"{phrase}\"")
        else:
            from .commands import DEFAULT_COMMANDS
            if phrase in DEFAULT_COMMANDS:
                print(f"⚠️  \"{phrase}\" is a built-in default command and cannot be removed. "
                      f"Override it with --add-command if needed.")
            else:
                print(f"⚠️  Custom voice command not found: \"{phrase}\"")
        return

    if args.list_commands:
        from .commands import load_commands
        commands = load_commands(config)
        if not commands:
            print("🔇 Voice commands are disabled (--voice-commands on to enable).")
            return
        custom = config.get("custom_commands", {})
        print("🗣️  Active voice commands:")
        for phrase in sorted(commands.keys(), key=len, reverse=True):
            replacement = commands[phrase]
            tag = " [custom]" if phrase in custom else ""
            print(f"   \"{phrase}\" → {repr(replacement)}{tag}")
        return

    if args.voice_commands:
        enabled = args.voice_commands == "on"
        config["voice_commands"] = enabled
        save_config(config)
        state = "enabled" if enabled else "disabled"
        print(f"✅ Voice commands {state}.")
        return

    # --- Per-app style management (Feature 2) ---
    if args.app_style:
        app_name, style = args.app_style
        if style not in VALID_STYLES:
            print(f"❌ Invalid style '{style}'. Valid: {VALID_STYLES}")
            sys.exit(1)
        app_styles = config.get("app_styles", {})
        app_styles[app_name] = style
        config["app_styles"] = app_styles
        save_config(config)
        print(f"✅ App style set: \"{app_name}\" → {style}")
        return

    if args.remove_app_style:
        app_styles = config.get("app_styles", {})
        if args.remove_app_style in app_styles:
            del app_styles[args.remove_app_style]
            config["app_styles"] = app_styles
            save_config(config)
            print(f"✅ App style removed: \"{args.remove_app_style}\"")
        else:
            print(f"⚠️  No style mapping found for: \"{args.remove_app_style}\"")
        return

    if args.list_app_styles:
        app_styles = config.get("app_styles", {})
        if app_styles:
            print("🎨 Per-app style mappings:")
            for app, style in sorted(app_styles.items()):
                print(f"   \"{app}\" → {style}")
        else:
            print("🎨 No per-app style mappings configured.")
        auto = config.get("auto_style", True)
        print(f"   Auto-style: {'enabled' if auto else 'disabled'}")
        return

    if args.auto_style:
        enabled = args.auto_style == "on"
        config["auto_style"] = enabled
        save_config(config)
        state = "enabled" if enabled else "disabled"
        print(f"✅ Auto-style {state}.")
        return

    # --- "Know Me" profile commands ---
    if args.profile:
        from .interview import run_interview
        completed = run_interview()
        if completed:
            print("✅ Profile saved! Your personalization is active.")
        else:
            print("⏭  Profile interview skipped.")
        return

    if args.show_profile:
        import json as _json
        from .profile import load_profile, has_profile
        if not has_profile():
            print("No profile found. Run: openvoiceflow --profile")
        else:
            profile = load_profile()
            print(_json.dumps(profile, indent=2))
        return

    if args.clear_profile:
        from .profile import clear_profile, has_profile
        if has_profile():
            clear_profile()
            print("✅ Profile deleted.")
        else:
            print("⚠️  No profile found.")
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

    if args.streaming:
        enabled = args.streaming == "on"
        config["streaming"] = enabled
        save_config(config)
        state = "enabled" if enabled else "disabled"
        print(f"✅ Streaming transcription {state}.")
        if enabled:
            from .streamer import find_whisper_stream
            if not find_whisper_stream():
                print("⚠️  whisper-stream binary not found. Install with: brew install whisper-cpp")
                print("   Streaming will fall back to batch mode until the binary is available.")

    if args.streaming_step:
        config["streaming_step_ms"] = args.streaming_step
        save_config(config)
        print(f"✅ Streaming step size set to: {args.streaming_step} ms")

    if args.auto_learn:
        enabled = args.auto_learn == "on"
        config["auto_learn"] = enabled
        save_config(config)
        state = "enabled" if enabled else "disabled"
        print(f"✅ Auto-learn corrections {state}.")
        return

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

    # --- History search (Feature 6) ---
    if args.search:
        from .search import search_transcripts
        results = search_transcripts(
            query=args.search,
            date=args.search_date,
            last_days=args.search_last,
            limit=args.limit,
        )
        if not results:
            print(f"No transcripts found matching: {args.search!r}")
            sys.exit(1)
        print(f"🔍 {len(results)} result(s) for {args.search!r}:\n")
        for entry in results:
            ts = entry["timestamp"]
            text = entry["cleaned"] or entry["raw"]
            display = text[:100] + ("…" if len(text) > 100 else "")
            print(f"  [{ts}] {display}")
            print(f"   ↳ {entry['file']}")
        sys.exit(0)

    if any([args.hotkey, args.model, args.backend, args.set_key, args.set_prompt,
            args.clear_prompt, args.language, args.style,
            args.streaming, args.streaming_step, args.auto_learn]):
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
