#!/usr/bin/env python3
"""Real AX/screenshot smoke for sanitized production MeetingsView."""

import json
import os
import subprocess
import sys
import time
import uuid
from pathlib import Path

root = Path(sys.argv[1])
fixture = root / ("fixture-data-" + uuid.uuid4().hex[:8])
exe = root / "MeetingNotesUIFixture.app/Contents/MacOS/MeetingNotesUIFixture"
log = []


def call(name, payload):
    command = ["cua-driver", "call", name, json.dumps(payload)]
    if os.environ.get("CUA_DRIVER_SOCKET"):
        command += ["--socket", os.environ["CUA_DRIVER_SOCKET"]]
    proc = subprocess.run(command, capture_output=True, text=True, timeout=65)
    if proc.returncode:
        raise RuntimeError(f"{name}: {proc.stdout[:500]} {proc.stderr[:500]}")
    if not proc.stdout.strip() and name == "click":
        return {"effect": "unverifiable"}
    try:
        response = json.loads(proc.stdout)
    except json.JSONDecodeError as error:
        raise RuntimeError(f"{name} returned non-JSON: {proc.stdout[:300]!r} {proc.stderr[:300]!r}") from error
    if response.get("isError") or response.get("code"):
        raise RuntimeError(f"{name}: {str(response)[:700]}")
    return response


def record_list():
    return json.loads((fixture / "library/meetings.json").read_text())


def label(state, text, role=None, exact=False):
    matches = [
        e
        for e in state["elements"]
        if ((e.get("label") or "") == text if exact else (e.get("label") or "").startswith(text))
        and (role is None or e.get("role") == role)
    ]
    assert len(matches) == 1, f"Expected one {text!r}, got {[(e.get('role'), e.get('label')) for e in matches]}"
    return matches[0]


def value(state, text):
    return label(state, text)["value"]


app = subprocess.Popen(
    [str(exe), str(fixture)], env=os.environ.copy(), stdout=(root / "app.log").open("w"), stderr=subprocess.STDOUT
)
try:
    window = None
    for _ in range(40):
        try:
            matches = [
                w for w in call("list_windows", {"pid": app.pid})["windows"] if w["title"] == "Meeting notes fixture"
            ]
            if matches:
                window = matches[0]["window_id"]
                break
        except RuntimeError:
            pass
        time.sleep(0.25)
    assert window, "fixture window unavailable"
    target = {"pid": app.pid, "window_id": window, "session": "meeting-notes-ui-fixture"}

    def snapshot(step):
        state = None
        for _ in range(15):
            state = call("get_window_state", {**target, "screenshot_out_file": str(root / f"{step}.png")})
            if any(e.get("label") == "Meeting title" for e in state["elements"]):
                break
            time.sleep(0.3)
        (root / f"{step}.json").write_text(json.dumps(state, indent=2))
        log.append(
            {
                "step": step,
                "image": str(root / f"{step}.png"),
                "title": next((e.get("value") for e in state["elements"] if e.get("label") == "Meeting title"), None),
                "elements": len(state["elements"]),
            }
        )
        return state

    def click(state, text, role="AXButton", exact=False):
        element = label(state, text, role, exact)
        result = call("click", {**target, "element_token": element["element_token"]})
        if result.get("verdict", {}).get("status") == "failed":
            raise RuntimeError(f"Click failed: {result}")
        time.sleep(0.2)

    def prime_clipboard():
        subprocess.run(["pbcopy"], input="SANITIZED-QA-CLIPBOARD-PRIMED", text=True, check=True)

    def copied():
        return subprocess.run(["pbpaste"], capture_output=True, text=True, check=True).stdout

    state = snapshot("01-initial")
    assert len(record_list()) == 2
    assert value(state, "Meeting title") == "Harbor planning review"
    labels = [e.get("label") or "" for e in state["elements"]]
    assert any("team reviewed the harbor schedule" in s for s in labels)
    assert any("pilot scope limited" in s for s in labels)
    assert "Recording details" in labels
    # Raw transcript is inside a collapsed disclosure and must not surface visibly.
    assert not any("RAW-CONVERSATION sentinel" in s for s in labels)
    assert "Copy notes" in labels
    print("PASS initial rendered notes cards and collapsed raw details", flush=True)

    prime_clipboard()
    click(state, "Copy notes")
    text = copied()
    assert "Harbor planning review" in text and "## Overview" in text and "## Action items" in text
    assert "PRIVATE-DRAFT sentinel" not in text and "RAW-CONVERSATION sentinel" not in text
    log.append({"step": "copy-default", "length": len(text), "private": False, "raw": False})
    print("PASS copy notes excludes private draft and raw transcript", flush=True)

    state = snapshot("02-before-share")
    click(state, "Share notes", role="AXMenuButton")
    state = snapshot("03-share-menu")
    print(
        "SHARE MENU",
        [
            (e.get("role"), e.get("label"), e.get("value"))
            for e in state["elements"]
            if "Include my notes" in (e.get("label") or "")
        ],
        flush=True,
    )
    click(state, "Include my notes", role=None)
    state = snapshot("04-private-enabled")
    prime_clipboard()
    click(state, "Copy notes")
    text = copied()
    assert "PRIVATE-DRAFT sentinel" in text and "## My notes" in text
    assert "RAW-CONVERSATION sentinel" not in text
    print("PASS explicit include-private copy includes private only, not raw", flush=True)

    state = snapshot("05-before-select-second")
    click(state, "Orchard follow-up,")
    state = snapshot("06-second-selected")
    assert value(state, "Meeting title") == "Orchard follow-up"
    prime_clipboard()
    click(state, "Copy notes")
    text = copied()
    assert (
        "Orchard follow-up" in text and "Second private reminder" not in text and "Second raw conversation" not in text
    )
    print("PASS selection resets include-private", flush=True)

    state = snapshot("07-before-edit")
    field = label(state, "Personal meeting notes")
    call(
        "set_value",
        {**target, "element_token": field["element_token"], "value": "Second private reminder — edited QA draft"},
    )
    state = snapshot("08-unsaved-edit")
    assert "edited QA draft" in value(state, "Personal meeting notes")
    click(state, "Harbor planning review,")
    state = snapshot("09-reselect-first")
    assert value(state, "Meeting title") == "Harbor planning review"
    click(state, "Orchard follow-up,")
    state = snapshot("10-second-reopened")
    assert "edited QA draft" in value(state, "Personal meeting notes")
    assert "edited QA draft" in record_list()[1]["notes"]
    print("PASS private draft edit persists across select/reopen", flush=True)

    click(state, "Recording details", role=None)
    state = snapshot("11-raw-expanded")
    assert any("Second raw conversation" in (e.get("value") or "") for e in state["elements"]), (
        "raw text not AX accessible after expansion"
    )
    print("PASS raw transcript accessible by disclosure", flush=True)

    click(state, "Harbor planning review,")
    state = snapshot("12-long-notes-top")
    assert value(state, "Meeting title") == "Harbor planning review"
    overview_before = label(state, "The team reviewed the harbor schedule")["frame"]["y"]
    call("scroll", {**target, "direction": "down", "amount": 12, "x": 740, "y": 560})
    state = snapshot("13-long-notes-scrolled")
    overview_after = label(state, "The team reviewed the harbor schedule")["frame"]["y"]
    assert overview_after < overview_before - 100, (overview_before, overview_after)
    print(f"PASS long notes scroll moved rendered card by {overview_before - overview_after:.0f} points", flush=True)
    assert not any("Verify milestone 16 " in (e.get("label") or "") for e in state["elements"])
    click(state, "Show all 16 items", role="AXLink")
    state = snapshot("14-all-actions-expanded")
    assert any("Verify milestone 16 " in (e.get("label") or "") for e in state["elements"])
    click(state, "Show less", role="AXLink")
    state = snapshot("15-actions-condensed")
    assert not any("Verify milestone 16 " in (e.get("label") or "") for e in state["elements"])
    prime_clipboard()
    click(state, "Copy notes")
    text = copied()
    assert "Verify milestone 16 " in text
    assert "PRIVATE-DRAFT sentinel" not in text and "RAW-CONVERSATION sentinel" not in text
    print("PASS long sections expand/collapse without losing shared content", flush=True)

    # A failed on-selection save must not discard either edit when reopening.
    click(state, "Orchard follow-up,")
    state = snapshot("16-failure-edit-start")
    title_field = label(state, "Meeting title")
    bounds = state["window_bounds"]
    field = title_field["frame"]
    call("click", {**target, "x": field["x"] - bounds["x"] + 300, "y": field["y"] - bounds["y"] + field["h"] / 2})
    state = snapshot("16a-title-focused")
    call("type_text", {**target, "text": " — unsaved QA title"})
    state = snapshot("17-failure-title-edited")
    assert label(state, "Save changes", role="AXButton")
    call("set_value", {**target, "element_token": label(state, "Personal meeting notes")["element_token"],
                       "value": "Orchard unsaved private note"})
    state = snapshot("18-failure-both-edited")
    assert value(state, "Meeting title") == "Orchard follow-up — unsaved QA title"
    assert value(state, "Personal meeting notes") == "Orchard unsaved private note"
    library = fixture / "library"
    library.chmod(0o500)  # MeetingStore cannot create its atomic .tmp file.
    try:
        click(state, "Harbor planning review,")
        state = snapshot("19-save-failed-selection")
        assert value(state, "Meeting title") == "Harbor planning review"
        assert label(state, "OK", role="AXButton")  # Save failure surfaced to user.
        assert record_list()[1]["title"] == "Orchard follow-up"
        assert record_list()[1]["notes"] == "Second private reminder — edited QA draft"
        windows = call("list_windows", {"pid": app.pid})["windows"]
        alert_window = next(w["window_id"] for w in windows if w["window_id"] != window and w.get("is_on_screen"))
        call("click", {**target, "window_id": alert_window, "x": 130, "y": 108, "delivery_mode": "foreground"})
        state = snapshot("20-failure-alert-dismissed")
        assert not any(e.get("label") == "OK" for e in state["elements"]), "save alert did not dismiss"
        click(state, "Orchard follow-up,")
        state = snapshot("21-failed-draft-reopened")
        assert value(state, "Meeting title") == "Orchard follow-up — unsaved QA title"
        assert value(state, "Personal meeting notes") == "Orchard unsaved private note"
    finally:
        library.chmod(0o700)
    click(state, "Save changes")
    state = snapshot("22-retry-save")
    assert record_list()[1]["title"] == "Orchard follow-up — unsaved QA title"
    assert record_list()[1]["notes"] == "Orchard unsaved private note"
    click(state, "Harbor planning review,")
    state = snapshot("23-after-retry-switch")
    click(state, "Orchard follow-up — unsaved QA title,")
    state = snapshot("24-retry-reopened")
    assert value(state, "Meeting title") == "Orchard follow-up — unsaved QA title"
    assert value(state, "Personal meeting notes") == "Orchard unsaved private note"
    print("PASS failed save preserves both edits across selection and retry persists them", flush=True)
    print("PASS screenshots:", root / "01-initial.png", root / "13-long-notes-scrolled.png", flush=True)
except Exception as error:
    log.append({"step": "failure", "error": repr(error)})
    print("FAIL", repr(error), flush=True)
    raise
finally:
    (root / "results.json").write_text(json.dumps({"pid": app.pid, "fixture": str(fixture), "steps": log}, indent=2))
    app.terminate()
    try:
        app.wait(timeout=5)
    except subprocess.TimeoutExpired:
        app.kill()
        app.wait(timeout=5)
    print("Fixture stopped pid", app.pid, flush=True)
