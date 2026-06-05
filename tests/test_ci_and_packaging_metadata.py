from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
WORKFLOWS = ROOT / ".github" / "workflows"


def read(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def test_github_actions_use_node_24_compatible_major_versions():
    combined = "\n".join(read(path) for path in WORKFLOWS.glob("*.yml"))

    assert "actions/checkout@v6" in combined
    assert "actions/setup-python@v6" in combined
    assert "actions/checkout@v4" not in combined
    assert "actions/setup-python@v5" not in combined


def test_pyproject_uses_spdx_license_metadata_without_deprecated_classifier():
    pyproject = read(ROOT / "pyproject.toml")

    assert 'license = "MIT"' in pyproject
    assert 'license = {text = "MIT"}' not in pyproject
    assert "License :: OSI Approved :: MIT License" not in pyproject
