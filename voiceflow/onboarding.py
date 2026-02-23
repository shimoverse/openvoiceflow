"""OpenVoiceFlow — macOS GUI Onboarding Wizard.

A step-by-step setup experience:
  1. Welcome screen
  2. Choose LLM backend
  3. Enter API key (with link + instructions)
  4. Choose hotkey
  5. Test & Done

Uses tkinter (built into macOS Python — no extra dependencies).
"""
import sys
import os
import json
import webbrowser
import threading
import subprocess
from pathlib import Path

try:
    import tkinter as tk
    from tkinter import ttk, messagebox, font as tkfont
    HAS_TKINTER = True
except ImportError:
    HAS_TKINTER = False
    tk = None

CONFIG_DIR = Path.home() / ".openvoiceflow"
CONFIG_PATH = CONFIG_DIR / "config.json"

# --- Color palette ---
BG = "#1a1a2e"
BG_CARD = "#16213e"
FG = "#e0e0e0"
FG_DIM = "#8888aa"
ACCENT = "#0f89ff"
ACCENT_HOVER = "#3da5ff"
SUCCESS = "#00c853"
WARN = "#ffab00"

# --- Backend definitions ---
BACKENDS = {
    "gemini": {
        "name": "Google Gemini Flash",
        "cost": "~$3/year (free tier available)",
        "speed": "Fast",
        "privacy": "Cloud",
        "url": "https://aistudio.google.com/apikey",
        "instructions": [
            "1. Click the link below to open Google AI Studio",
            "2. Sign in with your Google account",
            "3. Click 'Create API Key'",
            "4. Copy the key and paste it below",
        ],
        "recommended": True,
    },
    "groq": {
        "name": "Groq (Llama 3.3)",
        "cost": "Free tier (30 req/min)",
        "speed": "Fastest",
        "privacy": "Cloud",
        "url": "https://console.groq.com/keys",
        "instructions": [
            "1. Click the link below to open Groq Console",
            "2. Create a free account",
            "3. Go to API Keys → Create API Key",
            "4. Copy the key and paste it below",
        ],
        "recommended": False,
    },
    "openai": {
        "name": "OpenAI GPT-4o-mini",
        "cost": "~$5/year",
        "speed": "Fast",
        "privacy": "Cloud",
        "url": "https://platform.openai.com/api-keys",
        "instructions": [
            "1. Click the link below to open OpenAI Platform",
            "2. Sign in or create an account",
            "3. Go to API Keys → Create new secret key",
            "4. Copy the key and paste it below",
        ],
        "recommended": False,
    },
    "anthropic": {
        "name": "Anthropic Claude",
        "cost": "~$8/year",
        "speed": "Fast",
        "privacy": "Cloud",
        "url": "https://console.anthropic.com/",
        "instructions": [
            "1. Click the link below to open Anthropic Console",
            "2. Sign in or create an account",
            "3. Go to API Keys → Create Key",
            "4. Copy the key and paste it below",
        ],
        "recommended": False,
    },
    "ollama": {
        "name": "Ollama (Fully Local)",
        "cost": "$0 forever",
        "speed": "Moderate",
        "privacy": "100% Local — nothing leaves your Mac",
        "url": "https://ollama.com",
        "instructions": [
            "1. Click the link below to download Ollama",
            "2. Install and open Ollama",
            "3. Open Terminal and run: ollama pull llama3.2",
            "4. That's it — no API key needed!",
        ],
        "recommended": False,
        "no_key": True,
    },
}


class OnboardingWizard:
    """Step-by-step GUI setup wizard."""

    def __init__(self):
        self.root = tk.Tk()
        self.root.title("OpenVoiceFlow Setup")
        self.root.configure(bg=BG)
        self.root.resizable(False, False)

        # Window size and centering
        w, h = 600, 520
        x = (self.root.winfo_screenwidth() - w) // 2
        y = (self.root.winfo_screenheight() - h) // 3
        self.root.geometry(f"{w}x{h}+{x}+{y}")

        # State
        self.selected_backend = tk.StringVar(value="gemini")
        self.api_key = tk.StringVar()
        self.selected_hotkey = tk.StringVar(value="right_cmd")
        self.config = {}

        # Load existing config
        self._load_existing_config()

        # Container
        self.container = tk.Frame(self.root, bg=BG)
        self.container.pack(fill="both", expand=True, padx=30, pady=20)

        # Start with welcome screen
        self.show_welcome()

    def _load_existing_config(self):
        """Load existing config if present."""
        if CONFIG_PATH.exists():
            try:
                with open(CONFIG_PATH) as f:
                    self.config = json.load(f)
                backend = self.config.get("llm_backend", "gemini")
                self.selected_backend.set(backend)
                key_field = f"{backend}_api_key"
                if self.config.get(key_field):
                    self.api_key.set(self.config[key_field])
                if self.config.get("hotkey"):
                    self.selected_hotkey.set(self.config["hotkey"])
            except Exception:
                pass

    def _clear(self):
        """Clear the container."""
        for w in self.container.winfo_children():
            w.destroy()

    def _title(self, text, size=22):
        tk.Label(
            self.container, text=text, bg=BG, fg=FG,
            font=("SF Pro Display", size, "bold"),
        ).pack(pady=(0, 5))

    def _subtitle(self, text):
        tk.Label(
            self.container, text=text, bg=BG, fg=FG_DIM,
            font=("SF Pro Text", 13), wraplength=520,
        ).pack(pady=(0, 15))

    def _button(self, text, command, primary=True):
        btn = tk.Button(
            self.container, text=text, command=command,
            bg=ACCENT if primary else BG_CARD,
            fg="white", activebackground=ACCENT_HOVER,
            font=("SF Pro Text", 14, "bold" if primary else "normal"),
            relief="flat", cursor="hand2",
            padx=30, pady=10,
        )
        btn.pack(pady=8)
        return btn

    # ─── Step 1: Welcome ─────────────────────────

    def show_welcome(self):
        self._clear()

        tk.Label(
            self.container, text="🎙️", bg=BG,
            font=("Apple Color Emoji", 50),
        ).pack(pady=(20, 5))

        self._title("OpenVoiceFlow")
        self._subtitle(
            "Free, open-source voice dictation for macOS.\n"
            "Hold a key → speak → release → clean text appears at your cursor."
        )

        tk.Label(
            self.container, bg=BG, fg=FG_DIM,
            font=("SF Pro Text", 12),
            text=(
                "✅  Local speech-to-text (your audio never leaves your Mac)\n"
                "✅  AI-powered cleanup (removes fillers, fixes grammar)\n"
                "✅  Works in any app — Slack, Gmail, Notion, everywhere\n"
                "✅  Costs ~$0-3/year vs $144/year for Wispr Flow"
            ),
            justify="left",
        ).pack(pady=15)

        self._button("Get Started →", self.show_backend_select)

    # ─── Step 2: Choose Backend ───────────────────

    def show_backend_select(self):
        self._clear()
        self._title("Choose Your AI Backend")
        self._subtitle("This powers the transcript cleanup. You can change it anytime.")

        # Scrollable frame for backend options
        for name, info in BACKENDS.items():
            frame = tk.Frame(self.container, bg=BG_CARD, cursor="hand2")
            frame.pack(fill="x", pady=3, ipady=8, ipadx=12)

            # Radio button
            rb = tk.Radiobutton(
                frame, variable=self.selected_backend, value=name,
                bg=BG_CARD, fg=FG, selectcolor=BG_CARD,
                activebackground=BG_CARD, activeforeground=FG,
                font=("SF Pro Text", 13, "bold"),
                text=f"  {info['name']}",
            )
            rb.pack(side="left", padx=(8, 0))

            # Badge
            badge_text = info["cost"]
            badge_color = SUCCESS if "Free" in info["cost"] or "$0" in info["cost"] else FG_DIM
            tk.Label(
                frame, text=badge_text, bg=BG_CARD, fg=badge_color,
                font=("SF Pro Text", 11),
            ).pack(side="right", padx=10)

            if info.get("recommended"):
                tk.Label(
                    frame, text="⭐ Recommended", bg=BG_CARD, fg=WARN,
                    font=("SF Pro Text", 10),
                ).pack(side="right", padx=5)

            # Make entire frame clickable
            frame.bind("<Button-1>", lambda e, n=name: self.selected_backend.set(n))

        tk.Frame(self.container, bg=BG, height=10).pack()
        self._button("Continue →", self.show_api_key)

    # ─── Step 3: API Key ─────────────────────────

    def show_api_key(self):
        self._clear()
        backend = self.selected_backend.get()
        info = BACKENDS[backend]

        if info.get("no_key"):
            self._show_ollama_setup(info)
            return

        self._title(f"Set Up {info['name']}")
        self._subtitle(f"Speed: {info['speed']}  •  Privacy: {info['privacy']}  •  Cost: {info['cost']}")

        # Instructions
        instr_frame = tk.Frame(self.container, bg=BG_CARD)
        instr_frame.pack(fill="x", pady=10, ipady=10, ipadx=15)

        for step in info["instructions"]:
            tk.Label(
                instr_frame, text=step, bg=BG_CARD, fg=FG,
                font=("SF Pro Text", 12), anchor="w",
            ).pack(anchor="w", padx=10, pady=1)

        # Link button
        link_btn = tk.Button(
            self.container, text=f"🔗  Open {info['url'].split('//')[1].split('/')[0]}",
            command=lambda: webbrowser.open(info["url"]),
            bg=BG_CARD, fg=ACCENT, activebackground=BG_CARD,
            font=("SF Pro Text", 12, "underline"),
            relief="flat", cursor="hand2",
        )
        link_btn.pack(pady=8)

        # API Key input
        tk.Label(
            self.container, text="Paste your API key:", bg=BG, fg=FG,
            font=("SF Pro Text", 12),
        ).pack(anchor="w", pady=(10, 3))

        key_entry = tk.Entry(
            self.container, textvariable=self.api_key,
            font=("SF Mono", 13), bg=BG_CARD, fg=FG,
            insertbackground=FG, relief="flat",
            show="•",
        )
        key_entry.pack(fill="x", ipady=8)
        key_entry.focus()

        # Show/hide toggle
        self._key_visible = False

        def toggle_visibility():
            self._key_visible = not self._key_visible
            key_entry.config(show="" if self._key_visible else "•")
            toggle_btn.config(text="🙈 Hide" if self._key_visible else "👁 Show")

        toggle_btn = tk.Button(
            self.container, text="👁 Show", command=toggle_visibility,
            bg=BG, fg=FG_DIM, relief="flat", font=("SF Pro Text", 10),
            cursor="hand2",
        )
        toggle_btn.pack(anchor="e")

        # Buttons
        btn_frame = tk.Frame(self.container, bg=BG)
        btn_frame.pack(pady=10)

        tk.Button(
            btn_frame, text="← Back", command=self.show_backend_select,
            bg=BG_CARD, fg=FG, relief="flat", font=("SF Pro Text", 13),
            padx=20, pady=8, cursor="hand2",
        ).pack(side="left", padx=5)

        tk.Button(
            btn_frame, text="Continue →", command=self.validate_and_continue,
            bg=ACCENT, fg="white", relief="flat", font=("SF Pro Text", 13, "bold"),
            padx=20, pady=8, cursor="hand2",
        ).pack(side="left", padx=5)

    def _show_ollama_setup(self, info):
        """Special setup screen for Ollama (no API key needed)."""
        self._title("Set Up Ollama")
        self._subtitle("Fully local — your data never leaves your Mac. $0 forever.")

        instr_frame = tk.Frame(self.container, bg=BG_CARD)
        instr_frame.pack(fill="x", pady=10, ipady=10, ipadx=15)

        for step in info["instructions"]:
            tk.Label(
                instr_frame, text=step, bg=BG_CARD, fg=FG,
                font=("SF Pro Text", 12), anchor="w",
            ).pack(anchor="w", padx=10, pady=2)

        link_btn = tk.Button(
            self.container, text="🔗  Download Ollama",
            command=lambda: webbrowser.open(info["url"]),
            bg=BG_CARD, fg=ACCENT, activebackground=BG_CARD,
            font=("SF Pro Text", 13, "underline"),
            relief="flat", cursor="hand2",
        )
        link_btn.pack(pady=15)

        btn_frame = tk.Frame(self.container, bg=BG)
        btn_frame.pack(pady=10)

        tk.Button(
            btn_frame, text="← Back", command=self.show_backend_select,
            bg=BG_CARD, fg=FG, relief="flat", font=("SF Pro Text", 13),
            padx=20, pady=8, cursor="hand2",
        ).pack(side="left", padx=5)

        tk.Button(
            btn_frame, text="Continue →", command=self.show_hotkey,
            bg=ACCENT, fg="white", relief="flat", font=("SF Pro Text", 13, "bold"),
            padx=20, pady=8, cursor="hand2",
        ).pack(side="left", padx=5)

    def validate_and_continue(self):
        """Validate API key and move to hotkey selection."""
        key = self.api_key.get().strip()
        if not key:
            messagebox.showwarning("API Key Required", "Please paste your API key to continue.")
            return
        if len(key) < 10:
            messagebox.showwarning("Invalid Key", "That doesn't look like a valid API key. Please try again.")
            return
        self.show_hotkey()

    # ─── Step 4: Hotkey ──────────────────────────

    def show_hotkey(self):
        self._clear()
        self._title("Choose Your Hotkey")
        self._subtitle("Hold this key to start dictating. Release to stop and paste.")

        hotkeys = [
            ("right_cmd", "Right ⌘ Command", "Recommended — easy to reach"),
            ("right_alt", "Right ⌥ Option", "Good alternative"),
            ("left_alt", "Left ⌥ Option", "If right side is awkward"),
            ("f5", "F5", "Traditional push-to-talk"),
            ("f6", "F6", "Alternative function key"),
        ]

        for value, label, desc in hotkeys:
            frame = tk.Frame(self.container, bg=BG_CARD, cursor="hand2")
            frame.pack(fill="x", pady=2, ipady=6, ipadx=12)

            rb = tk.Radiobutton(
                frame, variable=self.selected_hotkey, value=value,
                bg=BG_CARD, fg=FG, selectcolor=BG_CARD,
                activebackground=BG_CARD, activeforeground=FG,
                font=("SF Pro Text", 13, "bold"),
                text=f"  {label}",
            )
            rb.pack(side="left", padx=(8, 0))

            tk.Label(
                frame, text=desc, bg=BG_CARD, fg=FG_DIM,
                font=("SF Pro Text", 11),
            ).pack(side="right", padx=10)

            frame.bind("<Button-1>", lambda e, v=value: self.selected_hotkey.set(v))

        tk.Frame(self.container, bg=BG, height=15).pack()

        btn_frame = tk.Frame(self.container, bg=BG)
        btn_frame.pack(pady=10)

        tk.Button(
            btn_frame, text="← Back",
            command=self.show_api_key if self.selected_backend.get() != "ollama" else self.show_backend_select,
            bg=BG_CARD, fg=FG, relief="flat", font=("SF Pro Text", 13),
            padx=20, pady=8, cursor="hand2",
        ).pack(side="left", padx=5)

        tk.Button(
            btn_frame, text="Finish Setup ✓",
            command=self.save_and_finish,
            bg=SUCCESS, fg="white", relief="flat", font=("SF Pro Text", 14, "bold"),
            padx=25, pady=10, cursor="hand2",
        ).pack(side="left", padx=5)

    # ─── Save & Finish ───────────────────────────

    def save_and_finish(self):
        """Save config and show success screen."""
        backend = self.selected_backend.get()

        # Build config
        CONFIG_DIR.mkdir(parents=True, exist_ok=True)

        # Preserve existing config
        if CONFIG_PATH.exists():
            with open(CONFIG_PATH) as f:
                self.config = json.load(f)

        self.config["llm_backend"] = backend
        self.config["hotkey"] = self.selected_hotkey.get()

        # Save API key
        key = self.api_key.get().strip()
        if key:
            key_field = f"{backend}_api_key"
            self.config[key_field] = key

        # Set defaults for missing fields
        defaults = {
            "whisper_model": "base.en",
            "sound_feedback": True,
            "auto_paste": True,
            "log_transcripts": True,
            "language": "en",
            "sample_rate": 16000,
            "channels": 1,
            "cleanup_prompt": (
                "Clean up this voice dictation transcript. "
                "Remove filler words (um, uh, like, you know), "
                "fix grammar and punctuation, "
                "handle corrections (e.g. 'no wait' means discard what came before), "
                "and make it read naturally. "
                "Keep the speaker's intent and tone. "
                "Output ONLY the cleaned text, nothing else."
            ),
        }
        for k, v in defaults.items():
            if k not in self.config:
                self.config[k] = v

        with open(CONFIG_PATH, "w") as f:
            json.dump(self.config, f, indent=2)

        self.show_success()

    def show_success(self):
        """Show success screen."""
        self._clear()

        tk.Label(
            self.container, text="✅", bg=BG,
            font=("Apple Color Emoji", 50),
        ).pack(pady=(30, 5))

        self._title("You're All Set!")

        backend = self.selected_backend.get()
        hotkey = self.selected_hotkey.get()
        info = BACKENDS[backend]

        tk.Label(
            self.container, bg=BG, fg=FG,
            font=("SF Pro Text", 13),
            text=(
                f"Backend: {info['name']}\n"
                f"Hotkey: {hotkey}\n"
                f"Config: ~/.openvoiceflow/config.json"
            ),
            justify="center",
        ).pack(pady=15)

        tk.Label(
            self.container, bg=BG, fg=FG_DIM,
            font=("SF Pro Text", 12),
            text=(
                "How to use:\n"
                f"  Hold [{hotkey}] → Speak → Release → Text appears at cursor\n\n"
                "⚠️ Grant Accessibility permission when macOS prompts you"
            ),
            justify="center",
        ).pack(pady=10)

        self._button("Start OpenVoiceFlow 🎙️", self.launch_and_close)

    def launch_and_close(self):
        """Close wizard and launch OpenVoiceFlow."""
        self.root.destroy()

    def run(self):
        """Start the wizard."""
        self.root.mainloop()
        return self.config


def run_onboarding():
    """Run the onboarding wizard and return the config."""
    if not HAS_TKINTER:
        print("❌ tkinter not available. Run: openvoiceflow --setup for CLI setup.")
        return None
    wizard = OnboardingWizard()
    return wizard.run()


def needs_onboarding() -> bool:
    """Check if onboarding is needed (no config or no API key)."""
    if not CONFIG_PATH.exists():
        return True
    try:
        with open(CONFIG_PATH) as f:
            config = json.load(f)
        backend = config.get("llm_backend", "gemini")
        if backend in ("ollama", "none"):
            return False
        key_field = f"{backend}_api_key"
        return not config.get(key_field)
    except Exception:
        return True


if __name__ == "__main__":
    config = run_onboarding()
    if config:
        print(f"✅ Setup complete! Config saved to {CONFIG_PATH}")
