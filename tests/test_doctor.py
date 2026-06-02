"""Tests for `voiceflow.doctor` — the self-diagnosis backbone.

The audit's UX_REVIEW.md identified that every error path in OpenVoiceFlow
should eventually route through one shared diagnostic surface. ``doctor``
is that surface. Each check is composable (testable in isolation), the
runner aggregates them, and the CLI prints a pretty table or JSON.
"""
from __future__ import annotations

import json


def test_check_status_enum_has_three_levels() -> None:
    from voiceflow.doctor import Status
    assert {Status.OK, Status.WARN, Status.FAIL} == set(Status)


def test_check_record_has_required_fields() -> None:
    from voiceflow.doctor import Check, Status
    c = Check(name="brew", status=Status.OK, description="Homebrew installed")
    assert c.name == "brew"
    assert c.status == Status.OK
    assert c.description == "Homebrew installed"
    assert c.fix is None  # default


def test_check_brew_uses_subprocess_which(monkeypatch) -> None:
    from voiceflow import doctor

    def fake_run(cmd, **kwargs):
        class R:
            returncode = 0
            stdout = "/opt/homebrew/bin/brew\n"
        assert cmd[0] == "command" or cmd[0] == "which", cmd
        return R()

    monkeypatch.setattr(doctor.subprocess, "run", fake_run)
    result = doctor.check_brew()
    assert result.status == doctor.Status.OK
    assert "brew" in result.name.lower()


def test_check_brew_fail_when_missing(monkeypatch) -> None:
    from voiceflow import doctor

    def fake_run(cmd, **kwargs):
        class R:
            returncode = 1
            stdout = ""
        return R()

    monkeypatch.setattr(doctor.subprocess, "run", fake_run)
    result = doctor.check_brew()
    assert result.status == doctor.Status.FAIL
    assert result.fix is not None  # must offer a remedy


def test_check_whisper_cli_finds_binary(monkeypatch) -> None:
    from voiceflow import doctor
    monkeypatch.setattr(doctor, "_find_whisper_cpp", lambda: "/opt/homebrew/bin/whisper-cli")
    result = doctor.check_whisper_cli()
    assert result.status == doctor.Status.OK


def test_check_whisper_cli_fails(monkeypatch) -> None:
    from voiceflow import doctor
    monkeypatch.setattr(doctor, "_find_whisper_cpp", lambda: None)
    result = doctor.check_whisper_cli()
    assert result.status == doctor.Status.FAIL
    assert result.fix is not None


def test_check_model_present(monkeypatch, tmp_path) -> None:
    from voiceflow import doctor
    model_path = tmp_path / "ggml-base.en.bin"
    model_path.write_bytes(b"fake model bytes")
    monkeypatch.setattr(doctor, "_get_model_path", lambda name: str(model_path))
    result = doctor.check_model({"whisper_model": "base.en"})
    assert result.status == doctor.Status.OK


def test_check_model_missing(monkeypatch, tmp_path) -> None:
    from voiceflow import doctor
    monkeypatch.setattr(doctor, "_get_model_path", lambda name: str(tmp_path / "missing.bin"))
    result = doctor.check_model({"whisper_model": "base.en"})
    assert result.status == doctor.Status.FAIL


def test_check_api_key_no_key(monkeypatch) -> None:
    from voiceflow import doctor
    config = {"llm_backend": "openrouter", "openrouter_api_key": ""}
    result = doctor.check_api_key(config)
    assert result.status == doctor.Status.FAIL
    assert result.fix is not None
    assert "openrouter" in (result.fix.url or "")


def test_check_api_key_none_backend(monkeypatch) -> None:
    """`none` backend (raw transcript only) needs no key."""
    from voiceflow import doctor
    result = doctor.check_api_key({"llm_backend": "none"})
    assert result.status == doctor.Status.OK


def test_check_pyobjc_when_present(monkeypatch) -> None:
    from voiceflow import doctor
    monkeypatch.setattr(doctor, "_pyobjc_available", lambda: True)
    result = doctor.check_pyobjc()
    assert result.status == doctor.Status.OK


def test_check_pyobjc_when_missing_warns(monkeypatch) -> None:
    """Missing pyobjc is a degraded state, not a hard fail (overlay HUD only)."""
    from voiceflow import doctor
    monkeypatch.setattr(doctor, "_pyobjc_available", lambda: False)
    result = doctor.check_pyobjc()
    assert result.status == doctor.Status.WARN


def test_run_all_checks_returns_list(monkeypatch) -> None:
    from voiceflow import doctor

    # Stub every check so the test doesn't poke at the user's real machine.
    fake = doctor.Check(
        name="stub", status=doctor.Status.OK, description="ok",
    )
    for fn_name in [
        "check_brew", "check_whisper_cli", "check_model",
        "check_api_key", "check_pyobjc", "check_tkinter",
        "check_file_modes",
    ]:
        if fn_name in ("check_model", "check_api_key"):
            monkeypatch.setattr(doctor, fn_name, lambda cfg, _f=fake: _f)
        else:
            monkeypatch.setattr(doctor, fn_name, lambda _f=fake: _f)

    results = doctor.run_all_checks({"llm_backend": "none", "whisper_model": "base.en"})
    assert isinstance(results, list)
    assert len(results) >= 5


def test_format_checks_text_renders(monkeypatch) -> None:
    from voiceflow.doctor import Check, Status, format_checks_text
    checks = [
        Check(name="brew", status=Status.OK, description="Homebrew installed"),
        Check(name="model", status=Status.FAIL, description="Model not found",
              fix=None),
    ]
    out = format_checks_text(checks)
    assert "brew" in out
    assert "model" in out
    assert "✓" in out
    assert "❌" in out


def test_format_checks_json_renders(monkeypatch) -> None:
    from voiceflow.doctor import Check, Fix, Status, format_checks_json
    checks = [
        Check(
            name="api_key", status=Status.FAIL,
            description="No OpenRouter key",
            fix=Fix(label="Get a key", url="https://openrouter.ai/keys"),
        ),
    ]
    parsed = json.loads(format_checks_json(checks))
    assert parsed["checks"][0]["name"] == "api_key"
    assert parsed["checks"][0]["status"] == "FAIL"
    assert parsed["checks"][0]["fix"]["url"] == "https://openrouter.ai/keys"


def test_doctor_cli_flag(monkeypatch, capsys) -> None:
    """`openvoiceflow --doctor` prints the report and returns nonzero on FAIL."""
    from voiceflow import doctor

    fake_ok = doctor.Check(name="x", status=doctor.Status.OK, description="ok")
    fake_fail = doctor.Check(name="y", status=doctor.Status.FAIL, description="bad")
    monkeypatch.setattr(doctor, "run_all_checks", lambda cfg: [fake_ok, fake_fail])

    rc = doctor.run_doctor_cli({"llm_backend": "none"})
    out = capsys.readouterr().out
    assert "x" in out and "y" in out
    assert rc != 0  # FAIL ⇒ nonzero exit
