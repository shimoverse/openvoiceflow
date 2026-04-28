"""D12 regression test: ``update_check: false`` short-circuits the GitHub fetch.

Background: ``updater.check_for_updates`` phones the GitHub API on every
launch. There was no way to disable it via config, which a privacy-conscious
or air-gapped user would want. v0.3 adds ``update_check`` to the config
schema (default ``True``) and short-circuits the network call when it's
False.
"""
from __future__ import annotations

import threading
import time
from typing import Any

import voiceflow.updater as updater


def test_update_check_disabled_skips_network(monkeypatch) -> None:
    """When config['update_check'] is False, no thread or HTTP call is started."""
    fetched = []

    def fake_fetch() -> dict | None:
        fetched.append(True)
        return None

    monkeypatch.setattr(updater, "_fetch_latest_release", fake_fetch)

    # Should return synchronously without fetching anything.
    updater.check_for_updates(config={"update_check": False})

    # Allow any (incorrectly-spawned) background thread a brief moment to run.
    time.sleep(0.05)
    assert fetched == [], (
        "_fetch_latest_release was called even though update_check=False"
    )


def test_update_check_enabled_spawns_thread(monkeypatch) -> None:
    """Default behavior unchanged: the worker thread runs and calls fetch."""
    fetched = threading.Event()

    def fake_fetch() -> dict | None:
        fetched.set()
        return None  # don't actually notify

    monkeypatch.setattr(updater, "_fetch_latest_release", fake_fetch)

    updater.check_for_updates(config={"update_check": True})

    assert fetched.wait(timeout=2.0), "worker thread didn't run"


def test_update_check_default_when_no_config(monkeypatch) -> None:
    """If no config is passed and load_config returns no value, default is True."""
    fetched = threading.Event()

    def fake_fetch() -> dict | None:
        fetched.set()
        return None

    monkeypatch.setattr(updater, "_fetch_latest_release", fake_fetch)
    monkeypatch.setattr(
        "voiceflow.config.load_config",
        lambda: {},  # no update_check key — should default to True
    )

    updater.check_for_updates()

    assert fetched.wait(timeout=2.0), "worker thread didn't run with empty config"
