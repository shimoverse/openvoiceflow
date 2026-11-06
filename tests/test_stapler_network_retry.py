"""Subprocess contract for the release stapler wrapper (mock xcrun/sleep only)."""

import json
import os
import subprocess
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[1]
HELPER = ROOT / "native/scripts/stapler-with-network-retry.sh"
NETWORK_LOST = "Error Domain=NSURLErrorDomain Code=-1005 'network connection lost'"


@pytest.fixture
def run_mock(tmp_path):
    """Use test-only PATH fakes; no Apple service or signed artifact is involved."""
    bin_dir = tmp_path / "mock-bin"
    bin_dir.mkdir()
    xcrun = bin_dir / "xcrun"
    xcrun.write_text(
        "#!/usr/bin/env python3\n"
        "import json, os, pathlib, sys\n"
        "root = pathlib.Path(os.environ['MOCK_ROOT'])\n"
        "calls = root / 'calls.jsonl'\n"
        "with calls.open('a') as f: f.write(json.dumps(sys.argv[1:]) + '\\n')\n"
        "attempt = len(calls.read_text().splitlines()) - 1\n"
        "status, output = json.loads(os.environ['MOCK_RESPONSES'])[attempt]\n"
        "sys.stderr.write(output + '\\n')\n"
        "sys.exit(status)\n",
        encoding="utf-8",
    )
    xcrun.chmod(0o755)
    sleep = bin_dir / "sleep"
    sleep.write_text(
        "#!/usr/bin/env python3\n"
        "import os, pathlib, sys\n"
        "with (pathlib.Path(os.environ['MOCK_ROOT']) / 'sleeps').open('a') as f:\n"
        "    f.write(' '.join(sys.argv[1:]) + '\\n')\n",
        encoding="utf-8",
    )
    sleep.chmod(0o755)

    def run(responses, operation="staple", target="/some path/Open VoiceFlow.app"):
        env = os.environ.copy()
        env.update(
            PATH=f"{bin_dir}{os.pathsep}{env['PATH']}",
            MOCK_ROOT=str(tmp_path),
            MOCK_RESPONSES=json.dumps(responses),
        )
        result = subprocess.run(
            [str(HELPER), operation, target],
            env=env, capture_output=True, text=True, timeout=10, check=False,
        )
        calls_file = tmp_path / "calls.jsonl"
        calls = [json.loads(line) for line in calls_file.read_text().splitlines()] if calls_file.exists() else []
        sleeps_file = tmp_path / "sleeps"
        sleeps = sleeps_file.read_text().splitlines() if sleeps_file.exists() else []
        return result, calls, sleeps

    return run


def test_first_success_preserves_operation_and_spaced_path(run_mock):
    result, calls, sleeps = run_mock([(0, "stapled")])
    assert result.returncode == 0
    assert calls == [["stapler", "staple", "/some path/Open VoiceFlow.app"]]
    assert sleeps == []


@pytest.mark.parametrize("operation", ["staple", "validate"])
def test_network_loss_then_recovery(run_mock, operation):
    result, calls, sleeps = run_mock([(68, NETWORK_LOST), (0, "succeeded")], operation)
    assert result.returncode == 0
    assert calls == [["stapler", operation, "/some path/Open VoiceFlow.app"]] * 2
    assert sleeps == ["1"]
    assert "succeeded" in result.stdout


def test_network_exhaustion_fails_closed_after_three_attempts(run_mock):
    result, calls, sleeps = run_mock([(68, NETWORK_LOST)] * 3, "validate", "/image with space.dmg")
    assert result.returncode == 68
    assert calls == [["stapler", "validate", "/image with space.dmg"]] * 3
    assert sleeps == ["1", "2"]


@pytest.mark.parametrize(
    "output",
    ["Invalid ticket", "NSURLErrorDomain Code=-1004", "Code=-1005", "NSURLErrorDomain: Code=-1005"],
)
def test_exit_68_without_exact_network_signature_does_not_retry(run_mock, output):
    result, calls, sleeps = run_mock([(68, output)])
    assert result.returncode == 68
    assert len(calls) == 1
    assert sleeps == []


def test_other_error_does_not_retry_even_with_network_signature(run_mock):
    result, calls, sleeps = run_mock([(1, NETWORK_LOST)])
    assert result.returncode == 1
    assert len(calls) == 1
    assert sleeps == []


def test_later_nonnetwork_failure_stops_after_one_retry(run_mock):
    result, calls, sleeps = run_mock([(68, NETWORK_LOST), (68, "invalid ticket")])
    assert result.returncode == 68
    assert len(calls) == 2
    assert sleeps == ["1"]


def test_invalid_invocation_fails_without_running_stapler(run_mock):
    result, calls, sleeps = run_mock([(0, "unexpected")], operation="submit")
    assert result.returncode != 0
    assert calls == []
    assert sleeps == []


def test_native_build_wraps_both_artifacts_but_preserves_hard_gates():
    script = (ROOT / "native/scripts/build-app.sh").read_text(encoding="utf-8")
    helper = '"$HERE/scripts/stapler-with-network-retry.sh"'
    for artifact in ("APP", "DMG"):
        assert f'{helper} staple "${artifact}"' in script
        assert f'{helper} validate "${artifact}"' in script
    assert script.count(helper) == 4
    assert script.count("xcrun notarytool submit") == 2
    assert 'spctl -a -vvv -t install "$DMG"' in script
