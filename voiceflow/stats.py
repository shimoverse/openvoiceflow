"""Dictation statistics tracking."""

from __future__ import annotations

import json
import os

from .config import CONFIG_DIR, LOG_DIR

STATS_PATH = os.path.join(CONFIG_DIR, "stats.json")


def load_stats() -> dict:
    """Load cumulative stats."""
    defaults = {
        "total_dictations": 0,
        "total_words": 0,
        "total_seconds_recorded": 0.0,
        "total_characters": 0,
    }
    if not os.path.exists(STATS_PATH):
        return defaults
    try:
        with open(STATS_PATH) as f:
            stored = json.load(f)
    except (json.JSONDecodeError, ValueError, OSError):
        return defaults
    if not isinstance(stored, dict):
        return defaults
    # Merge, but never let a wrong-typed value (e.g. "12" instead of 12)
    # poison the counters — record_dictation does arithmetic on these and
    # runs after every dictation.
    merged = dict(defaults)
    for key, default_value in defaults.items():
        value = stored.get(key, default_value)
        if isinstance(value, bool) or not isinstance(value, (int, float)):
            value = default_value
        merged[key] = value
    return merged


def save_stats(stats: dict):
    """Save cumulative stats."""
    from ._secure_io import secure_write_json
    os.makedirs(CONFIG_DIR, exist_ok=True)
    secure_write_json(STATS_PATH, stats)


def record_dictation(cleaned_text: str, duration_seconds: float):
    """Record a completed dictation in stats."""
    stats = load_stats()
    stats["total_dictations"] += 1
    stats["total_words"] += len(cleaned_text.split())
    stats["total_seconds_recorded"] += duration_seconds
    stats["total_characters"] += len(cleaned_text)
    save_stats(stats)


def show_stats():
    """Print dictation statistics to stdout."""
    stats = load_stats()
    total = stats["total_dictations"]
    words = stats["total_words"]
    seconds = stats["total_seconds_recorded"]
    chars = stats["total_characters"]

    # Estimate time saved: ~40 WPM typing vs instant dictation
    typing_minutes_saved = words / 40.0 if words else 0

    print("📊 OpenVoiceFlow Statistics")
    print("─" * 30)
    print(f"   Dictations:    {total}")
    print(f"   Words:         {words:,}")
    print(f"   Characters:    {chars:,}")
    print(f"   Recorded:      {seconds / 60:.1f} minutes")
    print(f"   Time saved:    ~{typing_minutes_saved:.0f} minutes")

    # Count log files
    if LOG_DIR.exists():
        log_days = len(list(LOG_DIR.glob("*.jsonl")))
        print(f"   Days active:   {log_days}")
