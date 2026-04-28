r"""SS2 regression test: ``install.sh`` writes a working ``openvoiceflow`` shim.

Background: v0.1.0 → v0.2.0 the install.sh shim block reads roughly:

    cat > "$BINDIR/openvoiceflow" << EOF
    #!/bin/bash
    exec "$VENV_DIR/bin/python3" -m openvoiceflow "\$@"
    EOF

The Python module is named ``voiceflow``, not ``openvoiceflow``, so
``python3 -m openvoiceflow`` raises ``ModuleNotFoundError``. The pyproject
``[project.scripts]`` entry already creates a working console script at
``$VENV_DIR/bin/openvoiceflow`` from ``voiceflow.__main__:main``; the shim
should simply exec it.

This test is static (no execution): it inspects ``install.sh`` and asserts
the shim is wired correctly.
"""
from __future__ import annotations

from pathlib import Path

INSTALL_SH = Path(__file__).resolve().parent.parent / "install.sh"


def test_install_sh_exists() -> None:
    assert INSTALL_SH.is_file(), f"{INSTALL_SH} not found"


def test_shim_does_not_invoke_module_named_openvoiceflow() -> None:
    """The ``-m openvoiceflow`` invocation never works (wrong module name)."""
    text = INSTALL_SH.read_text()
    assert "-m openvoiceflow" not in text, (
        "install.sh still references the broken `-m openvoiceflow` shim. "
        "The Python module is named `voiceflow`; prefer execing the "
        "pip-installed console script $VENV_DIR/bin/openvoiceflow."
    )


def test_shim_invokes_console_script() -> None:
    """The shim should exec the ``openvoiceflow`` console script in the venv."""
    text = INSTALL_SH.read_text()
    assert '"$VENV_DIR/bin/openvoiceflow"' in text, (
        "install.sh should exec $VENV_DIR/bin/openvoiceflow (the pip-installed "
        "console script) rather than reinventing a module-style invocation."
    )
