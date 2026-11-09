#!/usr/bin/env python3
"""Rendered native regression for delayed, identical, and failed notes regeneration."""
import json
import os
import subprocess
import sys
import time
import uuid
from pathlib import Path

root = Path(sys.argv[1])
fixture = root / ("regeneration-data-" + uuid.uuid4().hex[:8])
exe = root / "MeetingNotesUIFixture.app/Contents/MacOS/MeetingNotesUIFixture"


def call(name, payload):
    command = ["cua-driver", "call", name, json.dumps(payload)]
    if os.environ.get("CUA_DRIVER_SOCKET"):
        command += ["--socket", os.environ["CUA_DRIVER_SOCKET"]]
    proc = subprocess.run(command, capture_output=True, text=True, timeout=65)
    if proc.returncode or not proc.stdout.strip():
        raise RuntimeError(f"{name}: {proc.stdout[:500]} {proc.stderr[:500]}")
    response = json.loads(proc.stdout)
    if response.get("isError") or response.get("code"):
        raise RuntimeError(f"{name}: {str(response)[:700]}")
    return response


app = subprocess.Popen([str(exe), str(fixture)], env=os.environ.copy(),
                       stdout=(root / "regeneration-app.log").open("w"), stderr=subprocess.STDOUT)
try:
    window = None
    for _ in range(50):
        matches = [w for w in call("list_windows", {"pid": app.pid})["windows"]
                   if w["title"] == "Meeting notes fixture"]
        if matches:
            window = matches[0]["window_id"]
            break
        time.sleep(0.2)
    assert window, "fixture window unavailable"
    target = {"pid": app.pid, "window_id": window, "session": "meeting-regeneration-ui-fixture"}

    def snapshot(step):
        state = call("get_window_state", {**target, "screenshot_out_file": str(root / f"regeneration-{step}.png")})
        (root / f"regeneration-{step}.json").write_text(json.dumps(state, indent=2))
        return state

    def records():
        return json.loads((fixture / "library" / "meetings.json").read_text())

    def rendered(step):
        result = subprocess.run([str(root / "meeting-notes-ocr"), str(root / f"regeneration-{step}.png")],
                                capture_output=True, text=True, check=True)
        (root / f"regeneration-{step}.txt").write_text(result.stdout)
        return result.stdout

    def until_rendered(step, text):
        observed = ""
        for _ in range(20):
            snapshot(step)
            observed = rendered(step)
            if text in observed:
                return observed
            time.sleep(0.2)
        raise AssertionError(f"Timed out waiting for rendered {text!r}: {observed}")

    def labels(state):
        return [e.get("label") or "" for e in state["elements"]]

    def contains(state, text):
        return any(text in x for x in labels(state))

    def element(state, text):
        found = [e for e in state["elements"]
                 if (e.get("label") or "").startswith(text) and e.get("role") == "AXButton"]
        assert len(found) == 1, (text, [(e.get("role"), e.get("label")) for e in state["elements"]])
        return found[0]

    def click(state, text):
        call("click", {**target, "element_token": element(state, text)["element_token"]})

    def until(step, predicate):
        state = None
        for _ in range(30):
            state = snapshot(step)
            if predicate(state):
                return state
            time.sleep(0.15)
        raise AssertionError(f"Timed out waiting for {step}: {labels(state)}")

    def wait_for_marker(name):
        marker = fixture / "control" / name
        for _ in range(50):
            if marker.exists():
                return
            time.sleep(0.1)
        raise AssertionError(f"fixture marker {name} missing")

    def wait_for_gate(number):
        wait_for_marker(f"waiting-{number}")

    def release(number, content="ok"):
        (fixture / "control" / f"release-{number}").write_text(content)

    state = until("initial", lambda s: contains(s, "Harbor planning review,") and contains(s, "Regenerate notes"))
    baseline = records()
    click(state, "Regenerate notes")
    wait_for_gate(1)
    observed = until_rendered("pending-first", "Regenerating notes")
    state = snapshot("pending-first")
    assert "Generating notes" in observed and "team reviewed the harbor schedule" in observed
    assert "MEETING NOTES" in observed, "Progress is not near notes heading"
    # The native AX tree removes the disabled button, while screenshot OCR proves
    # its label stays rendered. Compare against its enabled initial AX node.
    assert not any(e.get("label") == "Regenerate notes" and e.get("role") == "AXButton" for e in state["elements"])
    assert records() == baseline, "Existing notes changed before completion"
    click(state, "Orchard follow-up,")
    state = until("other-during-first", lambda s: next(
        (e.get("value") for e in s["elements"] if e.get("label") == "Meeting title"), None) == "Orchard follow-up")
    other_text = rendered("other-during-first")
    assert "Regenerating notes" not in other_text and "Generating notes" not in other_text
    click(state, "Harbor planning review,")
    observed = until_rendered("first-reselected", "Regenerating notes")
    assert "Generating notes" in observed
    release(1)
    until_rendered("first-completed", "Notes updated")
    state = until("first-button-reenabled", lambda s: contains(s, "Regenerate notes"))
    first_output = records()
    assert first_output != baseline
    print("PASS delayed progress retains notes and is scoped to selected meeting", flush=True)

    click(state, "Regenerate notes")
    wait_for_gate(2)
    until_rendered("pending-identical", "Regenerating notes")
    state = snapshot("pending-identical")
    click(state, "Orchard follow-up,")
    state = until("other-during-identical", lambda s: next(
        (e.get("value") for e in s["elements"] if e.get("label") == "Meeting title"), None) == "Orchard follow-up")
    release(2)
    # Completion belongs to the originating meeting, never the current selection.
    wait_for_marker("finished-2")
    state = snapshot("other-after-identical")
    assert "Notes unchanged" not in rendered("other-after-identical")
    click(state, first_output[0]["title"] + ",")
    until_rendered("identical-completed", "Notes unchanged")
    state = until("identical-button-reenabled", lambda s: contains(s, "Regenerate notes"))
    assert records() == first_output
    print("PASS identical result explicitly acknowledged", flush=True)

    click(state, "Regenerate notes")
    wait_for_gate(3)
    until_rendered("pending-failure", "Regenerating notes")
    release(3, "fail")
    until_rendered("failure", "Simulated local notes failure")
    state = until("failure-button-reenabled", lambda s: contains(s, "Regenerate notes"))
    assert records() == first_output
    click(state, "Regenerate notes")
    wait_for_gate(4)
    until_rendered("retry-pending", "Regenerating notes")
    release(4)
    until_rendered("retry-completed", "Notes unchanged")
    print("PASS failure visible; existing notes survive and retry completes", flush=True)
except Exception as error:
    print("FAIL regeneration", repr(error), flush=True)
    raise
finally:
    app.terminate()
    try:
        app.wait(timeout=5)
    except subprocess.TimeoutExpired:
        app.kill()
        app.wait(timeout=5)
    print("Regeneration fixture stopped pid", app.pid, flush=True)
