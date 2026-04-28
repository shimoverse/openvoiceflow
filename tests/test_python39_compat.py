"""SS3 regression test: every voiceflow submodule must import on Python 3.9+.

Background: pyproject.toml advertises ``requires-python = ">=3.9"`` but v0.2
shipped 15 modules using PEP 604 union syntax (``X | None``) without
``from __future__ import annotations``. On Python 3.9 these crash at import
with ``TypeError: unsupported operand type(s) for |: 'type' and 'NoneType'``.

This test runs the import on whatever interpreter pytest is invoked with.
On a 3.9 interpreter, it MUST pass once SS3 is fixed (the fix is to add
``from __future__ import annotations`` to each affected file).
"""
from __future__ import annotations

import importlib
from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).resolve().parent.parent
PACKAGE_ROOT = REPO_ROOT / "voiceflow"


def _all_submodules() -> list[str]:
    """Discover every importable submodule under ``voiceflow/``."""
    modules: list[str] = []
    for py_file in sorted(PACKAGE_ROOT.rglob("*.py")):
        rel = py_file.relative_to(PACKAGE_ROOT)
        parts = list(rel.with_suffix("").parts)
        if parts[-1] == "__init__":
            parts = parts[:-1]
        if not parts:
            modname = "voiceflow"
        else:
            modname = "voiceflow." + ".".join(parts)
        modules.append(modname)
    return modules


SUBMODULES = _all_submodules()


@pytest.mark.parametrize("modname", SUBMODULES)
def test_submodule_imports(modname: str) -> None:
    """Every voiceflow submodule must import without raising."""
    importlib.import_module(modname)
