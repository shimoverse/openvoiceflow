"""Behavior contracts for History feedback and dashboard app identities."""

import re
import shutil
import subprocess
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[1]
NATIVE_SOURCES = ROOT / "native" / "Sources" / "OpenVoiceFlow"


def compile_and_run_swift(tmp_path: Path, sources: list[Path], harness_source: str) -> None:
    if shutil.which("xcrun") is None:
        pytest.skip("Swift contract requires the macOS Xcode toolchain")

    harness = tmp_path / "main.swift"
    harness.write_text(harness_source, encoding="utf-8")
    binary = tmp_path / "contract"
    compile_result = subprocess.run(
        ["xcrun", "swiftc", "-parse-as-library", *map(str, sources), str(harness), "-o", str(binary)],
        text=True,
        capture_output=True,
        check=False,
    )
    assert compile_result.returncode == 0, compile_result.stderr

    run_result = subprocess.run([str(binary)], text=True, capture_output=True, check=False)
    assert run_result.returncode == 0, run_result.stderr


def test_copy_feedback_moves_between_rows_and_self_dismisses(tmp_path: Path) -> None:
    """A stale timer must not clear a newer row's acknowledgement."""
    compile_and_run_swift(
        tmp_path,
        [NATIVE_SOURCES / "HistoryCopyFeedback.swift"],
        """
import Foundation

@main
struct Runner {
    @MainActor
    static func main() async {
        let first = UUID()
        let second = UUID()
        let feedback = HistoryCopyFeedback()

        feedback.markCopied(first, dismissAfterNanoseconds: 80_000_000)
        let firstIsCopied = feedback.isCopied(first)
        precondition(firstIsCopied)

        feedback.markCopied(second, dismissAfterNanoseconds: 10_000_000)
        let firstWasCleared = !feedback.isCopied(first)
        let secondIsCopied = feedback.isCopied(second)
        precondition(firstWasCleared)
        precondition(secondIsCopied)

        try? await Task.sleep(nanoseconds: 30_000_000)
        let secondWasDismissed = !feedback.isCopied(second)
        precondition(secondWasDismissed)
    }
}
""",
    )


def test_seeded_apps_and_claude_have_real_identity_descriptors(tmp_path: Path) -> None:
    """Every app users see before dictating must resolve beyond initials."""
    compile_and_run_swift(
        tmp_path,
        [NATIVE_SOURCES / "AppIdentityCatalog.swift"],
        r"""
import Foundation

@main
struct Runner {
    static func main() {
        let knownApps = [
            "Visual Studio Code", "Xcode", "PyCharm", "Zed", "Terminal", "iTerm2",
            "Sublime Text", "Nova", "Mail", "Gmail", "Outlook", "Superhuman",
            "Slack", "Discord", "Messages", "WhatsApp", "Telegram", "Signal",
            "Microsoft Word", "Pages", "Notion", "Safari", "Google Chrome", "Claude",
        ]

        for name in knownApps {
            guard let descriptor = AppIdentityCatalog.descriptor(for: name) else {
                preconditionFailure("Missing descriptor for \(name)")
            }
            precondition(!descriptor.bundleIdentifiers.isEmpty || descriptor.brandResource != nil)
        }

        precondition(AppIdentityCatalog.descriptor(for: "Notion")?.brandResource == "notion")
        precondition(AppIdentityCatalog.descriptor(for: "Outlook")?.brandResource == "microsoftoutlook")
        precondition(AppIdentityCatalog.descriptor(for: "Claude")?.brandResource == "claude")
        precondition(AppIdentityCatalog.descriptor(for: "Discord")?.brandResource == "discord")
        precondition(AppIdentityCatalog.descriptor(for: "Unknown") == nil)
    }
}
""",
    )


def test_every_catalog_brand_fallback_is_packaged() -> None:
    """A descriptor is useless when its SVG is omitted from the app bundle."""
    brand_dir = ROOT / "native" / "Resources" / "BrandIcons"
    resources = {
        "apple",
        "claude",
        "discord",
        "gmail",
        "googlechrome",
        "iterm2",
        "microsoftoutlook",
        "microsoftword",
        "notion",
        "panic",
        "pycharm",
        "safari",
        "signal",
        "slack",
        "sublimetext",
        "superhuman",
        "telegram",
        "visualstudiocode",
        "whatsapp",
        "zedindustries",
    }

    for resource in resources:
        svg = brand_dir / f"{resource}.svg"
        png = brand_dir / f"{resource}.png"
        assert svg.is_file() or png.is_file(), f"Missing packaged brand fallback: {resource}"
        if svg.is_file():
            assert "<svg" in svg.read_text(encoding="utf-8")


def test_every_dashboard_app_name_uses_the_shared_identity_view() -> None:
    """Recent, History, usage, and Styles must not regress to text-only app names."""
    dashboard = (NATIVE_SOURCES / "DashboardView.swift").read_text(encoding="utf-8")
    identity_view = NATIVE_SOURCES / "AppIdentityView.swift"
    provider = NATIVE_SOURCES / "AppIconProvider.swift"

    assert identity_view.is_file()
    assert len(re.findall(r"AppIdentityLabel\(\s*name:", dashboard)) >= 4
    assert "ringFraction: row.fraction" in dashboard
    assert "AppIdentityIcon(name: name" in identity_view.read_text(encoding="utf-8")
    assert "monogram(" not in provider.read_text(encoding="utf-8")
    assert "Text(row.app)" not in dashboard
    assert "Text(entry.app)" not in dashboard
    assert "Text(app).font(.system(size: 13, weight: .semibold))" not in dashboard
