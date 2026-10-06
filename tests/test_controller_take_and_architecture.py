"""Regression contracts for controller take replacement and Whistle selection on Intel."""
from pathlib import Path


CONTROLLER = (Path(__file__).resolve().parents[1] / "native/Sources/OpenVoiceFlow/AppController.swift")


def method(name: str) -> str:
    source = CONTROLLER.read_text()
    start = source.index(f"    {name}")
    return source[start:source.index("\n    }", start) + len("\n    }")]


def test_new_take_cancels_preceding_dictation_before_recording():
    start = method("private func startRecording()")
    assert start.index("dictationTask?.cancel()") < start.index("dictationGeneration += 1")
    assert start.index("dictationTask?.cancel()") < start.index("try audio.start()")


def test_selecting_whistle_on_intel_rejects_before_changing_or_saving_model():
    selection = method("func selectModel(_ name: String)")
    architecture = selection.index("#if !arch(arm64)")
    assert selection.index("if name == WhistleEngine.modelID") < architecture
    assert architecture < selection.index("throw WhistleError.unsupportedArchitecture")
    assert selection.index("throw WhistleError.unsupportedArchitecture") < selection.index("settings.whisperModel = name")
    assert selection.index("throw WhistleError.unsupportedArchitecture") < selection.index("settings.save()")


def test_settings_whistle_choice_on_intel_rejects_before_changing_or_saving_model():
    update = method("func updateModel(_ name: String)")
    architecture = update.index("#if !arch(arm64)")
    assert update.index("if name == WhistleEngine.modelID") < architecture
    assert architecture < update.index("WhistleError.unsupportedArchitecture.localizedDescription")
    assert update.index("return", architecture) < update.index("settings.whisperModel = name")
    assert update.index("return", architecture) < update.index("settings.save()")
