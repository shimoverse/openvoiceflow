"""OpenVoiceFlow — "Know Me" Personalization Interview Wizard.

A 6-screen conversational onboarding that learns WHO the user is so the
very first dictation already knows how to spell their kid's name, their
technical stack, and how they like to communicate.

Design principles (Steve Jobs-ish):
  - The wizard does the work, not the user.
  - Questions feel conversational, not form-like.
  - Skip is possible but de-emphasized (small, gray link).
  - The summary at the end makes you feel *known*.
  - "Your data never leaves your Mac" is front and center.

Visual style matches onboarding.py exactly:
  BG="#1a1a2e", BG_CARD="#16213e", FG="#e0e0e0", ACCENT="#0f89ff"
"""
import sys
from pathlib import Path

try:
    import tkinter as tk
    from tkinter import font as tkfont
    HAS_TKINTER = True
except ImportError:
    HAS_TKINTER = False
    tk = None

from .profile import save_profile, load_profile, profile_to_dictionary

# ── Color palette (matches onboarding.py) ──────────────────────────────────
BG        = "#1a1a2e"
BG_CARD   = "#16213e"
FG        = "#e0e0e0"
FG_DIM    = "#8888aa"
ACCENT    = "#0f89ff"
ACCENT_HOVER = "#3da5ff"
SUCCESS   = "#00c853"

# Industry choices shown in the dropdown on screen 3
INDUSTRIES = ["tech", "healthcare", "legal", "finance", "education", "creative", "other"]

# Human-friendly labels for communication style options
STYLE_OPTIONS = [
    ("casual",   "Casual",   "Hey, what's up? Contractions, short sentences."),
    ("balanced", "Balanced", "Natural and clear. A mix of formal and informal."),
    ("formal",   "Formal",   "Professional tone. No contractions. Polished."),
]


class InterviewWizard:
    """6-screen personalization interview.

    After completion the profile is saved to disk and all names/terms are
    auto-added to the personal dictionary so corrections kick in immediately.

    Usage::

        wizard = InterviewWizard()
        completed = wizard.run()   # True = saved, False = skipped
    """

    def __init__(self):
        self.root = tk.Tk()
        self.root.title("OpenVoiceFlow — Know Me")
        self.root.configure(bg=BG)
        self.root.resizable(False, False)

        # Window size and centering (matches onboarding.py)
        w, h = 600, 520
        sx = self.root.winfo_screenwidth()
        sy = self.root.winfo_screenheight()
        x = (sx - w) // 2
        y = (sy - h) // 3
        self.root.geometry(f"{w}x{h}+{x}+{y}")

        # Bind Escape to skip/cancel
        self.root.bind("<Escape>", lambda e: self._skip())

        # Interview state
        self._name_var         = tk.StringVar()
        self._role_var         = tk.StringVar()
        self._industry_var     = tk.StringVar(value="tech")
        self._work_names_var   = tk.StringVar()
        self._home_names_var   = tk.StringVar()
        self._style_var        = tk.StringVar(value="casual")
        self._completed        = False

        # Pre-fill from existing profile (re-run scenario)
        existing = load_profile()
        if existing:
            self._name_var.set(existing.get("name", ""))
            self._role_var.set(existing.get("occupation", ""))
            ind = existing.get("industry", "tech")
            self._industry_var.set(ind if ind in INDUSTRIES else "tech")
            self._work_names_var.set(", ".join(existing.get("work_names", [])))
            self._home_names_var.set(", ".join(existing.get("home_names", [])))
            cs = existing.get("communication_style", "casual")
            self._style_var.set(cs if cs in [s[0] for s in STYLE_OPTIONS] else "casual")

        # Main container
        self.container = tk.Frame(self.root, bg=BG)
        self.container.pack(fill="both", expand=True, padx=30, pady=20)

        self._show_welcome()

    # ── Helpers ────────────────────────────────────────────────────────────

    def _clear(self):
        """Destroy all widgets in the container."""
        for w in self.container.winfo_children():
            w.destroy()

    def _title(self, text: str, size: int = 22):
        tk.Label(
            self.container, text=text, bg=BG, fg=FG,
            font=("SF Pro Display", size, "bold"),
            wraplength=540,
        ).pack(pady=(0, 5))

    def _subtitle(self, text: str):
        tk.Label(
            self.container, text=text, bg=BG, fg=FG_DIM,
            font=("SF Pro Text", 13), wraplength=520,
        ).pack(pady=(0, 12))

    def _primary_button(self, text: str, command, parent=None) -> tk.Button:
        p = parent or self.container
        btn = tk.Button(
            p, text=text, command=command,
            bg=ACCENT, fg="white", activebackground=ACCENT_HOVER,
            font=("SF Pro Text", 14, "bold"),
            relief="flat", cursor="hand2",
            padx=30, pady=10,
        )
        btn.pack(pady=8)
        return btn

    def _secondary_button(self, text: str, command, parent=None) -> tk.Button:
        p = parent or self.container
        btn = tk.Button(
            p, text=text, command=command,
            bg=BG_CARD, fg=FG, activebackground=BG,
            font=("SF Pro Text", 13),
            relief="flat", cursor="hand2",
            padx=20, pady=8,
        )
        btn.pack(pady=4)
        return btn

    def _skip_link(self, parent=None):
        """A de-emphasized 'Skip for now' link at the bottom."""
        p = parent or self.container
        btn = tk.Button(
            p, text="Skip for now",
            command=self._skip,
            bg=BG, fg=FG_DIM, activebackground=BG,
            font=("SF Pro Text", 11),
            relief="flat", cursor="hand2",
            borderwidth=0,
        )
        btn.pack(pady=(2, 0))
        return btn

    def _text_entry(self, var: tk.StringVar, placeholder: str = "") -> tk.Entry:
        """Create a styled single-line text entry."""
        entry = tk.Entry(
            self.container,
            textvariable=var,
            font=("SF Pro Text", 14),
            bg=BG_CARD, fg=FG,
            insertbackground=FG,
            relief="flat",
        )
        entry.pack(fill="x", ipady=10, pady=(0, 4))

        # Placeholder support
        if placeholder:
            def _on_focus_in(e):
                if var.get() == placeholder:
                    var.set("")
                    entry.config(fg=FG)

            def _on_focus_out(e):
                if not var.get():
                    var.set(placeholder)
                    entry.config(fg=FG_DIM)

            if not var.get():
                var.set(placeholder)
                entry.config(fg=FG_DIM)
            entry.bind("<FocusIn>", _on_focus_in)
            entry.bind("<FocusOut>", _on_focus_out)

        return entry

    def _text_area(self, var: tk.StringVar, placeholder: str = "", height: int = 3) -> tk.Text:
        """Create a styled multi-line text area with StringVar sync."""
        frame = tk.Frame(self.container, bg=BG_CARD)
        frame.pack(fill="x", pady=(0, 8))

        widget = tk.Text(
            frame,
            font=("SF Pro Text", 13),
            bg=BG_CARD, fg=FG,
            insertbackground=FG,
            relief="flat",
            height=height,
            wrap="word",
            padx=8, pady=6,
        )
        widget.pack(fill="x")

        # Pre-fill from StringVar
        if var.get():
            widget.insert("1.0", var.get())
            widget.config(fg=FG)
        elif placeholder:
            widget.insert("1.0", placeholder)
            widget.config(fg=FG_DIM)

        def _on_focus_in(e):
            content = widget.get("1.0", "end-1c")
            if content == placeholder:
                widget.delete("1.0", "end")
                widget.config(fg=FG)

        def _on_focus_out(e):
            content = widget.get("1.0", "end-1c").strip()
            var.set(content)
            if not content and placeholder:
                widget.insert("1.0", placeholder)
                widget.config(fg=FG_DIM)

        widget.bind("<FocusIn>", _on_focus_in)
        widget.bind("<FocusOut>", _on_focus_out)

        # Keep var in sync on every keystroke
        def _on_key(_e):
            var.set(widget.get("1.0", "end-1c").strip())

        widget.bind("<KeyRelease>", _on_key)

        return widget

    def _spacer(self, h: int = 10):
        tk.Frame(self.container, bg=BG, height=h).pack()

    # ── Screen 1: Welcome ──────────────────────────────────────────────────

    def _show_welcome(self):
        self._clear()

        tk.Label(
            self.container, text="✨", bg=BG,
            font=("Apple Color Emoji", 46),
        ).pack(pady=(25, 5))

        self._title("Let's make OpenVoiceFlow yours")
        self._subtitle(
            "Answer a few quick questions so I can understand you better.\n"
            "This takes about 60 seconds."
        )

        tk.Label(
            self.container, bg=BG, fg=FG_DIM,
            font=("SF Pro Text", 12),
            text="🔒  Your data never leaves your Mac. Stored locally only.",
        ).pack(pady=(0, 20))

        self._primary_button("Let's go →", self._show_name)
        self._skip_link()

    # ── Screen 2: Name ─────────────────────────────────────────────────────

    def _show_name(self):
        self._clear()

        self._title("What's your name?")
        self._subtitle("So I always spell it right.")

        self._spacer(15)
        entry = self._text_entry(self._name_var)
        entry.focus_set()
        self._spacer(20)

        btn_row = tk.Frame(self.container, bg=BG)
        btn_row.pack()

        tk.Button(
            btn_row, text="← Back", command=self._show_welcome,
            bg=BG_CARD, fg=FG, relief="flat",
            font=("SF Pro Text", 13), padx=20, pady=8, cursor="hand2",
        ).pack(side="left", padx=5)

        tk.Button(
            btn_row, text="Next →", command=self._show_what_you_do,
            bg=ACCENT, fg="white", activebackground=ACCENT_HOVER,
            relief="flat", font=("SF Pro Text", 13, "bold"),
            padx=20, pady=8, cursor="hand2",
        ).pack(side="left", padx=5)

        self._spacer(8)
        self._skip_link()

        # Allow Enter to advance
        self.root.bind("<Return>", lambda e: self._show_what_you_do())

    # ── Screen 3: What You Do ──────────────────────────────────────────────

    def _show_what_you_do(self):
        # Clear Enter binding from screen 2
        try:
            self.root.unbind("<Return>")
        except Exception:
            pass
        self._clear()

        self._title("What do you do?")
        self._subtitle("This helps me understand your vocabulary.")

        self._spacer(10)

        tk.Label(
            self.container, text="Role / title:", bg=BG, fg=FG_DIM,
            font=("SF Pro Text", 12), anchor="w",
        ).pack(anchor="w", pady=(0, 2))

        entry = self._text_entry(self._role_var)
        entry.focus_set()

        self._spacer(10)

        tk.Label(
            self.container, text="Industry:", bg=BG, fg=FG_DIM,
            font=("SF Pro Text", 12), anchor="w",
        ).pack(anchor="w", pady=(0, 4))

        # Industry dropdown (OptionMenu)
        option_frame = tk.Frame(self.container, bg=BG_CARD)
        option_frame.pack(fill="x", pady=(0, 8))

        menu = tk.OptionMenu(option_frame, self._industry_var, *INDUSTRIES)
        menu.config(
            bg=BG_CARD, fg=FG, activebackground=ACCENT,
            activeforeground="white", relief="flat",
            font=("SF Pro Text", 13), highlightthickness=0,
            indicatoron=True, bd=0,
        )
        menu["menu"].config(
            bg=BG_CARD, fg=FG, activebackground=ACCENT,
            activeforeground="white", font=("SF Pro Text", 13),
        )
        menu.pack(side="left", padx=8, pady=6)

        self._spacer(20)

        btn_row = tk.Frame(self.container, bg=BG)
        btn_row.pack()

        tk.Button(
            btn_row, text="← Back", command=self._show_name,
            bg=BG_CARD, fg=FG, relief="flat",
            font=("SF Pro Text", 13), padx=20, pady=8, cursor="hand2",
        ).pack(side="left", padx=5)

        tk.Button(
            btn_row, text="Next →", command=self._show_people,
            bg=ACCENT, fg="white", activebackground=ACCENT_HOVER,
            relief="flat", font=("SF Pro Text", 13, "bold"),
            padx=20, pady=8, cursor="hand2",
        ).pack(side="left", padx=5)

        self._spacer(8)
        self._skip_link()

    # ── Screen 4: People You Mention ──────────────────────────────────────

    def _show_people(self):
        self._clear()

        self._title("Who do you talk about most?")
        self._subtitle(
            "Names, tools, brands — anything you say often that I should spell correctly."
        )

        tk.Label(
            self.container, text="At work:", bg=BG, fg=FG_DIM,
            font=("SF Pro Text", 12), anchor="w",
        ).pack(anchor="w", pady=(8, 2))

        self._text_area(
            self._work_names_var,
            placeholder="e.g., Sarah, Kubernetes, Jira",
            height=2,
        )

        tk.Label(
            self.container, text="At home:", bg=BG, fg=FG_DIM,
            font=("SF Pro Text", 12), anchor="w",
        ).pack(anchor="w", pady=(4, 2))

        self._text_area(
            self._home_names_var,
            placeholder="e.g., Meer, Luna, Dr. Patel",
            height=2,
        )

        self._spacer(10)

        btn_row = tk.Frame(self.container, bg=BG)
        btn_row.pack()

        tk.Button(
            btn_row, text="← Back", command=self._show_what_you_do,
            bg=BG_CARD, fg=FG, relief="flat",
            font=("SF Pro Text", 13), padx=20, pady=8, cursor="hand2",
        ).pack(side="left", padx=5)

        tk.Button(
            btn_row, text="Next →", command=self._show_style,
            bg=ACCENT, fg="white", activebackground=ACCENT_HOVER,
            relief="flat", font=("SF Pro Text", 13, "bold"),
            padx=20, pady=8, cursor="hand2",
        ).pack(side="left", padx=5)

        self._spacer(8)
        self._skip_link()

    # ── Screen 5: Communication Style ─────────────────────────────────────

    def _show_style(self):
        self._clear()

        self._title("How do you usually communicate?")
        self._subtitle("I'll match your tone when cleaning up dictation.")

        self._spacer(10)

        for value, label, desc in STYLE_OPTIONS:
            frame = tk.Frame(self.container, bg=BG_CARD, cursor="hand2")
            frame.pack(fill="x", pady=4, ipady=10, ipadx=12)

            rb = tk.Radiobutton(
                frame,
                variable=self._style_var,
                value=value,
                bg=BG_CARD, fg=FG,
                selectcolor=BG_CARD,
                activebackground=BG_CARD,
                activeforeground=FG,
                font=("SF Pro Text", 13, "bold"),
                text=f"  {label}",
            )
            rb.pack(side="left", padx=(8, 0))

            tk.Label(
                frame, text=desc, bg=BG_CARD, fg=FG_DIM,
                font=("SF Pro Text", 11),
            ).pack(side="right", padx=10)

            # Make the whole row clickable
            frame.bind("<Button-1>", lambda e, v=value: self._style_var.set(v))

        self._spacer(20)

        btn_row = tk.Frame(self.container, bg=BG)
        btn_row.pack()

        tk.Button(
            btn_row, text="← Back", command=self._show_people,
            bg=BG_CARD, fg=FG, relief="flat",
            font=("SF Pro Text", 13), padx=20, pady=8, cursor="hand2",
        ).pack(side="left", padx=5)

        tk.Button(
            btn_row, text="Finish →", command=self._save_and_show_done,
            bg=SUCCESS, fg="white",
            relief="flat", font=("SF Pro Text", 14, "bold"),
            padx=25, pady=10, cursor="hand2",
        ).pack(side="left", padx=5)

        self._spacer(8)
        self._skip_link()

    # ── Screen 6: Done! ────────────────────────────────────────────────────

    def _save_and_show_done(self):
        """Build the profile dict, persist it, populate the dictionary, show summary."""
        profile = self._build_profile()
        save_profile(profile)

        # Auto-populate personal dictionary with all names + terms
        self._populate_dictionary(profile)

        # Also update config style field if it diverges from default
        self._sync_style_to_config(profile.get("communication_style", "casual"))

        self._show_done(profile)

    def _build_profile(self) -> dict:
        """Assemble the profile dict from wizard state."""
        def parse_csv(raw: str) -> list[str]:
            """Split a comma-separated string into a clean list."""
            return [
                item.strip()
                for item in raw.replace(";", ",").split(",")
                if item.strip()
            ]

        name          = self._name_var.get().strip()
        occupation    = self._role_var.get().strip()
        industry      = self._industry_var.get().strip()
        work_raw      = self._work_names_var.get().strip()
        home_raw      = self._home_names_var.get().strip()
        style         = self._style_var.get().strip()

        # Separate work entries into names vs. technical terms heuristically:
        # entries with no spaces are typically tool names / tech terms.
        work_all = parse_csv(work_raw)
        work_names:       list[str] = []
        technical_terms:  list[str] = []
        for item in work_all:
            # If it looks like a technical term (no space, or camelCase / dotted)
            if (
                " " not in item
                and (item[0].isupper() or "." in item or "_" in item or item.isupper())
            ):
                technical_terms.append(item)
            else:
                work_names.append(item)

        home_names = parse_csv(home_raw)

        return {
            "name":               name,
            "occupation":         occupation,
            "industry":           industry,
            "work_names":         work_names,
            "home_names":         home_names,
            "technical_terms":    technical_terms,
            "communication_style": style,
            "additional_context": "",
        }

    def _populate_dictionary(self, profile: dict):
        """Add all names + technical terms to the personal dictionary."""
        try:
            from .dictionary import add_word
            words = profile_to_dictionary(profile)
            for word in words:
                add_word(word)
        except Exception:
            pass  # Dictionary errors must not crash the interview

    def _sync_style_to_config(self, style: str):
        """Write the chosen communication style to config.json."""
        try:
            from .config import load_config, save_config, VALID_STYLES
            # Map interview style names to config VALID_STYLES
            style_map = {
                "casual":   "casual",
                "balanced": "default",
                "formal":   "formal",
            }
            config_style = style_map.get(style, "default")
            if config_style in VALID_STYLES:
                config = load_config()
                config["style"] = config_style
                save_config(config)
        except Exception:
            pass  # Config errors must not crash the interview

    def _show_done(self, profile: dict):
        self._clear()

        tk.Label(
            self.container, text="✨", bg=BG,
            font=("Apple Color Emoji", 46),
        ).pack(pady=(25, 5))

        self._title("I know you now")

        # Summary line
        name       = profile.get("name") or "—"
        occupation = profile.get("occupation") or "—"
        work_names = profile.get("work_names", [])
        home_names = profile.get("home_names", [])
        tech_terms = profile.get("technical_terms", [])
        style      = profile.get("communication_style", "casual").capitalize()

        total_names = len(work_names) + len(home_names) + len(tech_terms)
        names_label = (
            f"{total_names} name{'s' if total_names != 1 else ''} learned"
            if total_names > 0
            else "no names yet"
        )

        summary = f"Name: {name}  |  Work: {occupation}  |  {names_label}  |  Style: {style}"

        summary_frame = tk.Frame(self.container, bg=BG_CARD)
        summary_frame.pack(fill="x", pady=12, ipady=12, ipadx=12)

        tk.Label(
            summary_frame, text=summary, bg=BG_CARD, fg=FG,
            font=("SF Pro Text", 12), wraplength=520, justify="center",
        ).pack(padx=10)

        # Privacy note
        tk.Label(
            self.container,
            text="🔒  All of this is stored locally. Your data never leaves your Mac.",
            bg=BG, fg=FG_DIM,
            font=("SF Pro Text", 12),
        ).pack(pady=(6, 20))

        self._completed = True

        self._primary_button("Start Dictating 🎙️", self._finish)

    # ── Skip / Finish ──────────────────────────────────────────────────────

    def _skip(self):
        """Close without saving."""
        self._completed = False
        self.root.destroy()

    def _finish(self):
        """Close after a completed interview."""
        self.root.destroy()

    # ── Public API ─────────────────────────────────────────────────────────

    def run(self) -> bool:
        """Run the wizard event loop.

        Returns:
            True if the user completed the interview, False if skipped.
        """
        self.root.mainloop()
        return self._completed


def run_interview() -> bool:
    """Launch the interview wizard as a standalone call.

    Returns:
        True if the user completed and saved a profile, False if skipped.
    """
    if not HAS_TKINTER:
        print("❌ tkinter not available. Profile interview requires a display.")
        return False
    wizard = InterviewWizard()
    return wizard.run()
