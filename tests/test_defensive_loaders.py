"""Regression tests: corrupt user-data files must never break dictation.

Every loader for a ~/.openvoiceflow/*.json artifact feeds the per-dictation
pipeline (LLMBackend.__init__, match_snippet, record_dictation, notify.tip).
Before these fixes, one malformed file — hand-edited, torn by a crash, or
simply the wrong JSON shape — made EVERY dictation fail with a generic
"Dictation failed", with no hint which file was the cause.

Each test writes the exact malformed payload that used to crash and asserts
the loader degrades to its empty/default value instead.
"""
from __future__ import annotations

import json
from pathlib import Path

import pytest

# ─────────────────────────────────────────────────────────────────────
# snippets.json
# ─────────────────────────────────────────────────────────────────────


@pytest.fixture
def snippets_path(monkeypatch, tmp_path: Path) -> Path:
    import voiceflow.snippets as snip
    path = tmp_path / "snippets.json"
    monkeypatch.setattr(snip, "SNIPPETS_PATH", str(path))
    return path


def test_snippets_non_dict_json_degrades_to_empty(snippets_path: Path) -> None:
    """A JSON list used to raise AttributeError inside match_snippet."""
    from voiceflow.snippets import load_snippets, match_snippet
    snippets_path.write_text(json.dumps(["insert sig"]))
    assert load_snippets() == {}
    assert match_snippet("insert sig") is None
    assert match_snippet("hello world") is None


def test_snippets_wrong_typed_entries_are_dropped(snippets_path: Path) -> None:
    from voiceflow.snippets import load_snippets
    snippets_path.write_text(json.dumps({"good": "expansion", "bad": 42, "worse": None}))
    assert load_snippets() == {"good": "expansion"}


def test_snippets_unreadable_file_degrades_to_empty(snippets_path: Path) -> None:
    """An OSError (e.g. snippets.json is a directory) used to propagate."""
    from voiceflow.snippets import load_snippets
    snippets_path.mkdir()  # IsADirectoryError on open
    assert load_snippets() == {}


# ─────────────────────────────────────────────────────────────────────
# stats.json
# ─────────────────────────────────────────────────────────────────────


@pytest.fixture
def stats_path(monkeypatch, tmp_path: Path) -> Path:
    import voiceflow.stats as stats_mod
    path = tmp_path / "stats.json"
    monkeypatch.setattr(stats_mod, "STATS_PATH", str(path))
    monkeypatch.setattr(stats_mod, "CONFIG_DIR", str(tmp_path))
    return path


def test_stats_non_dict_json_degrades_to_defaults(stats_path: Path) -> None:
    """stats.json containing `5` used to raise TypeError in load_stats."""
    from voiceflow.stats import load_stats
    stats_path.write_text("5")
    stats = load_stats()
    assert stats["total_dictations"] == 0


def test_stats_wrong_typed_counter_reset_not_crash(stats_path: Path) -> None:
    """A string counter used to crash record_dictation after every paste."""
    from voiceflow.stats import load_stats, record_dictation
    stats_path.write_text(json.dumps({"total_words": "12", "total_dictations": 3}))
    stats = load_stats()
    assert stats["total_words"] == 0        # wrong type → reset to default
    assert stats["total_dictations"] == 3   # right type → preserved
    record_dictation("hello world", 1.5)    # must not raise
    stats = load_stats()
    assert stats["total_dictations"] == 4
    assert stats["total_words"] == 2


def test_stats_bool_counter_is_not_accepted_as_int(stats_path: Path) -> None:
    from voiceflow.stats import load_stats
    stats_path.write_text(json.dumps({"total_dictations": True}))
    assert load_stats()["total_dictations"] == 0


# ─────────────────────────────────────────────────────────────────────
# profile.json
# ─────────────────────────────────────────────────────────────────────


@pytest.fixture
def profile_path(monkeypatch, tmp_path: Path) -> Path:
    import voiceflow.profile as prof
    path = tmp_path / "profile.json"
    monkeypatch.setattr(prof, "PROFILE_DIR", tmp_path)
    monkeypatch.setattr(prof, "PROFILE_PATH", path)
    return path


def test_profile_non_dict_json_returns_none(profile_path: Path) -> None:
    """A JSON list used to raise AttributeError inside LLMBackend.__init__."""
    from voiceflow.profile import get_profile_prompt_fragment, load_profile
    profile_path.write_text(json.dumps(["oops"]))
    assert load_profile() is None
    assert get_profile_prompt_fragment() == ""


def test_profile_null_fields_do_not_crash_fragment(profile_path: Path) -> None:
    """`"name": null` used to raise AttributeError ('NoneType'.strip)."""
    from voiceflow.profile import get_profile_prompt_fragment
    profile_path.write_text(json.dumps({
        "name": None,
        "occupation": 42,
        "work_names": None,
        "home_names": ["Ana", 7, None],
        "technical_terms": "not-a-list",
        "communication_style": None,
    }))
    fragment = get_profile_prompt_fragment()
    assert "Ana" in fragment          # valid items survive
    assert "42" not in fragment       # wrong-typed fields are ignored


def test_profile_to_dictionary_tolerates_bad_shapes(profile_path: Path) -> None:
    from voiceflow.profile import profile_to_dictionary
    words = profile_to_dictionary({
        "work_names": ["Kai", None, 3],
        "home_names": None,
        "technical_terms": ["Kubernetes"],
        "name": None,
    })
    assert words == ["Kai", "Kubernetes"]


# ─────────────────────────────────────────────────────────────────────
# dictionary.json
# ─────────────────────────────────────────────────────────────────────


@pytest.fixture
def dictionary_path(monkeypatch, tmp_path: Path) -> Path:
    import voiceflow.dictionary as dic
    path = tmp_path / "dictionary.json"
    monkeypatch.setattr(dic, "DICTIONARY_PATH", str(path))
    monkeypatch.setattr(dic, "CONFIG_DIR", str(tmp_path))
    return path


def test_dictionary_non_list_aliases_sanitized(dictionary_path: Path) -> None:
    """`"aliases": 5` used to crash add_word; non-str items crashed the
    LLM prompt fragment (str.join) — i.e. every dictation."""
    from voiceflow.dictionary import add_word, get_dictionary_prompt_fragment
    dictionary_path.write_text(json.dumps([
        {"word": "Kubernetes", "aliases": [1, 2, "cubanets"]},
        {"word": "Meer", "aliases": 5},
    ]))
    fragment = get_dictionary_prompt_fragment()  # must not raise
    assert "cubanets" in fragment
    assert "Kubernetes" in fragment
    add_word("Meer", aliases=["mir"])  # must not raise
    fragment = get_dictionary_prompt_fragment()
    assert "mir" in fragment


# ─────────────────────────────────────────────────────────────────────
# transcript log search
# ─────────────────────────────────────────────────────────────────────


def test_search_tolerates_wrong_shape_jsonl_lines(monkeypatch, tmp_path: Path) -> None:
    """One bad line used to make ALL history search crash."""
    import voiceflow.search as search_mod
    monkeypatch.setattr(search_mod, "LOG_DIR", tmp_path)
    log = tmp_path / "2026-07-10.jsonl"
    log.write_text(
        '"just a string"\n'
        '{"timestamp": null, "raw": null, "cleaned": "keep me"}\n'
        '{"timestamp": "2026-07-10T10:00:00", "raw": "hello world", "cleaned": "Hello world."}\n'
        "[1, 2, 3]\n"
    )
    from voiceflow.search import search_transcripts
    results = search_transcripts("hello")
    assert len(results) == 1
    assert results[0]["cleaned"] == "Hello world."
    results = search_transcripts("keep me")
    assert len(results) == 1  # null fields coerced, entry still searchable


# ─────────────────────────────────────────────────────────────────────
# _seen_tips.json (notify)
# ─────────────────────────────────────────────────────────────────────


def test_seen_tips_wrong_shape_does_not_crash_tip(monkeypatch, tmp_path: Path) -> None:
    """A JSON list used to raise AttributeError inside notify.tip() — which
    app.start_hotkey_runtime_checks calls unwrapped."""
    import voiceflow.notify as notify
    path = tmp_path / "_seen_tips.json"
    path.write_text(json.dumps(["a", "b"]))
    monkeypatch.setattr(notify, "SEEN_TIPS_PATH", str(path))
    monkeypatch.setattr(notify, "_post_macos_notification", lambda *a, **kw: None)
    notify.tip("hello", once_key="test_key")  # must not raise
    # And the save path must round-trip through the atomic writer
    assert "test_key" in notify._load_seen_tips()


# ─────────────────────────────────────────────────────────────────────
# learner similarity gate
# ─────────────────────────────────────────────────────────────────────


def test_learner_rejects_content_edits_keeps_real_corrections() -> None:
    """The 0.4 threshold learned date/word edits ("june"→"july") as
    permanent corrections, poisoning every future LLM prompt."""
    from voiceflow.learner import CorrectionWatcher
    watcher = CorrectionWatcher.__new__(CorrectionWatcher)  # no Tk/AX needed

    # Ordinary content edits — must NOT be learned
    assert watcher._extract_corrections("meet in june", "meet in july") == []
    assert watcher._extract_corrections("free monday ok", "free tuesday ok") == []
    assert watcher._extract_corrections("see you in there", "see you on there") == []

    # Genuine mishearing corrections — MUST still be learned
    assert watcher._extract_corrections("lake mir trip", "lake Meer trip") == [("mir", "Meer")]
    assert watcher._extract_corrections("i recieve mail", "i receive mail") == [("recieve", "receive")]


# ─────────────────────────────────────────────────────────────────────
# updater response shape
# ─────────────────────────────────────────────────────────────────────


def test_updater_fetch_tolerates_exotic_failures(monkeypatch) -> None:
    """UnicodeDecodeError / BadStatusLine used to escape and kill the
    check thread, leaving the menubar item stuck on 'Checking…' forever."""
    import voiceflow.updater as upd

    class _FakeResp:
        status = 200
        def read(self, *args):
            return b"\xff\xfe garbage"  # not UTF-8
        def __enter__(self):
            return self
        def __exit__(self, *a):
            return False

    monkeypatch.setattr(upd.urllib.request, "urlopen", lambda *a, **kw: _FakeResp())
    assert upd._fetch_latest_release() is None  # must not raise

    class _ListResp(_FakeResp):
        def read(self, *args):
            return b'["not", "a", "dict"]'

    monkeypatch.setattr(upd.urllib.request, "urlopen", lambda *a, **kw: _ListResp())
    assert upd._fetch_latest_release() is None


# ─────────────────────────────────────────────────────────────────────
# platform_support macOS version parsing
# ─────────────────────────────────────────────────────────────────────


def test_macos_version_resolves_1016_compat_shim(monkeypatch) -> None:
    """CPython built against a pre-11 SDK reports '10.16' on Big Sur+ —
    doctor used to hard-FAIL users on supported macOS 13/14."""
    import voiceflow.platform_support as ps
    monkeypatch.setattr(ps, "is_macos", lambda: True)
    monkeypatch.setattr(ps.platform, "mac_ver", lambda: ("10.16", ("", "", ""), ""))

    class _Result:
        returncode = 0
        stdout = "14.5\n"

    monkeypatch.setattr(ps.subprocess, "run", lambda *a, **kw: _Result())
    assert ps.macos_version() == (14, 5)


def test_macos_version_1016_without_sysctl_is_unknown(monkeypatch) -> None:
    import voiceflow.platform_support as ps
    monkeypatch.setattr(ps, "is_macos", lambda: True)
    monkeypatch.setattr(ps.platform, "mac_ver", lambda: ("10.16", ("", "", ""), ""))

    def _boom(*a, **kw):
        raise OSError("no sysctl")

    monkeypatch.setattr(ps.subprocess, "run", _boom)
    assert ps.macos_version() is None  # honest "unknown", not a false FAIL


def test_macos_version_bare_major_is_padded(monkeypatch) -> None:
    """'12' parsed to (12,) compared < (12, 0) — a false below-minimum."""
    import voiceflow.platform_support as ps
    monkeypatch.setattr(ps, "is_macos", lambda: True)
    monkeypatch.setattr(ps.platform, "mac_ver", lambda: ("12", ("", "", ""), ""))
    ver = ps.macos_version()
    assert ver == (12, 0)
    assert not (ver < ps.MIN_MACOS)
