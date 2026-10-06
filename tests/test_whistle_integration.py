"""Executable integration contracts for opt-in Whistle selection and routing."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1] / "native" / "Sources" / "OpenVoiceFlow"


def test_transcriber_routes_whistle_without_implicit_download():
    text = (ROOT / "Transcriber.swift").read_text()
    assert 'if modelName == WhistleEngine.modelID' in text
    assert 'try await whistle.transcribe(samples, language: language)' in text
    assert 'try await whistle.download(progress: observer)' in text
    assert 'guard requestedModel == modelName else { throw CancellationError() }' in text
    assert 'await whistle.cancel()' in text


def test_onboarding_download_is_explicit_and_background_preload_does_not_fetch():
    text = (ROOT / "AppController.swift").read_text()
    assert 'transcriber.downloadSelectedModel(model, progress: progress)' in text
    assert 'try? await transcriber.warmUp()' in text


def test_switching_model_from_menu_uses_controller_hotswap():
    text = (ROOT / "OpenVoiceFlowApp.swift").read_text()
    assert 'controller.modelPreparation.choose(model.id, controller: controller)' in text
    preparation = (ROOT / "AppController.swift").read_text()
    assert 'let selection = try await controller.selectModel(model)' in preparation
    assert 'controller.prepareModelForOnboarding(model, generation: selection)' in preparation
    assert 'controller.modelPreparation' in (ROOT / "DashboardView.swift").read_text()


def test_stale_results_cannot_paste_after_aba_model_swap():
    transcriber = (ROOT / "Transcriber.swift").read_text()
    controller = (ROOT / "AppController.swift").read_text()
    assert 'selectionGeneration += 1' in transcriber
    assert 'try validate(model, generation: generation)' in transcriber
    assert transcriber.count('try validate(model, generation: generation)') >= 5
    assert 'modelSelectionGeneration += 1' in controller
    assert 'try validateDictation(selectedModel, selection: selection, generation: generation)' in controller
    assert controller.count('try validateDictation(selectedModel, selection: selection, generation: generation)') == 2


def test_unsupported_language_error_is_user_visible():
    text = (ROOT / "AppController.swift").read_text()
    assert 'error is WhistleError' in text
    assert 'lastError = error is WhistleError ? error.localizedDescription' in text


def test_unsupported_whistle_settings_choice_is_not_called_a_download_failure_or_retried():
    status = (ROOT / 'AppController.swift').read_text().split('final class ModelPreparationStatus:', 1)[1].split('/// Orchestrates', 1)[0]
    dashboard = (ROOT / 'DashboardView.swift').read_text()
    assert 'catch WhistleError.unsupportedArchitecture' in status
    assert 'catch WhistleError.unsupportedLanguage' in status
    assert 'message = "Model unavailable"' in status
    assert 'if modelPreparation.canRetry' in dashboard


def test_timeout_escalates_to_kill_and_distinguishes_cancel():
    text = (ROOT / "WhistleEngine.swift").read_text()
    assert 'func timeout()' in text
    assert 'kill(current.processIdentifier, SIGKILL)' in text
    assert 'if run.isTimedOut { throw WhistleError.timedOut }' in text


def test_whistle_is_a_dashboard_settings_only_beta_option():
    dashboard = (ROOT / "DashboardView.swift").read_text()
    onboarding = (ROOT / "OnboardingView.swift").read_text()
    menu = (ROOT / "OpenVoiceFlowApp.swift").read_text()
    assert '("whistle", "Whistle (Beta)")' in dashboard
    assert 'modelPreparation.choose(controller.settings.whisperModel, controller: controller)' in dashboard
    assert '"whistle"' not in onboarding
    assert 'Whistle' not in onboarding
    assert '"whistle"' not in menu
    assert 'Whistle' not in menu
    assert 'modelPreparation.message' not in menu
    assert 'Try download again' not in menu
    assert 'if controller.lastError == "Microphone unavailable" { return "Pick an input in Sound settings" }' in menu


def test_model_swap_during_cleanup_cannot_paste_old_dictation():
    text = (ROOT / "AppController.swift").read_text()
    assert 'dictationGeneration += 1' in text
    assert 'hud.hide() // A hot swap is a cancellation' in text
    assert 'if generation == dictationGeneration { hud.hide() }' in text
    assert 'guard generation == dictationGeneration, selection == modelSelectionGeneration else { return }' in text


def test_picker_and_preparation_bind_whistle_language_and_readiness_to_selection():
    controller = (ROOT / "AppController.swift").read_text()
    dashboard = (ROOT / "DashboardView.swift").read_text()
    assert '!WhistleEngine.supports(language: settings.language)' in controller
    assert 'Self.languages.filter { WhistleEngine.supports(language: $0.0) }' in dashboard
    assert 'controller.isModelReady(model, generation: selection)' in controller


def test_cancellation_and_status_are_selection_scoped():
    engine = (ROOT / "WhistleEngine.swift").read_text()
    controller = (ROOT / "AppController.swift").read_text()
    assert 'if let downloadTask, !downloadTask.isCancelled' in engine
    assert 'cancelledDownload = downloadTask' in engine
    assert 'if let previous { _ = try? await previous.value }' in engine
    assert 'if downloadToken == token { downloadTask = nil }' in engine
    assert 'dictationTask?.cancel()' in controller
    assert 'lastSamples = []' in controller
    assert 'lastError = nil\n        modelPreparation.selectionChanged(to: name)' in controller
    assert 'guard current == generation else { return }' in controller


def test_whistle_progress_waits_for_both_downloads():
    engine = (ROOT / "WhistleEngine.swift").read_text()
    assert 'progress(500, 1000)' in engine
    assert 'progress(1000, 1000)' in engine
    assert engine.index('progress(500, 1000)') < engine.index('fetcher(Self.weightsURL') < engine.index('progress(1000, 1000)')


def test_overlapping_model_selections_do_not_restore_stale_engine():
    text = (ROOT / "Transcriber.swift").read_text()
    swap = text.split('func setModel(_ name: String, generation: Int) async {', 1)[1].split('\n    }', 1)[0]
    assert 'guard generation > controllerGeneration else { return }' in swap
    assert swap.index('modelName = name') < swap.index('await whistle.cancel()')


def test_arm64_only_vendor_binary_fails_closed_on_other_macs():
    engine = (ROOT / "WhistleEngine.swift").read_text()
    assert 'unsupportedArchitecture, notDownloaded' in engine
    assert '#if !arch(arm64)' in engine
    assert 'throw WhistleError.unsupportedArchitecture' in engine
    assert 'Apple Silicon' in (ROOT / 'DashboardView.swift').read_text()
    assert 'Apple Silicon' in engine


def test_whisper_choices_and_recommended_default_remain_in_onboarding_and_menu():
    onboarding = (ROOT / 'OnboardingView.swift').read_text()
    menu = (ROOT / 'OpenVoiceFlowApp.swift').read_text()
    for model in ['tiny', 'small', 'medium', 'large-v3-v20240930']:
        assert f'("{model}",' in onboarding
        assert f'("{model}",' in menu
    assert 'return (appleSilicon && roomy) ? "large-v3-v20240930" : "small"' in onboarding
    assert 'controller.modelPreparation.choose(model.id, controller: controller)' in menu
