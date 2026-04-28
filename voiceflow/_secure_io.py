"""Secure-write helpers for ``~/.openvoiceflow/`` artifacts.

Default macOS umask (022) gives 644 — world-readable. API keys, profile,
dictionary, snippets, stats, and daily transcript logs all need 600 instead.

These helpers centralize the chmod, so every save site converges on the same
posture without each module reinventing the dance.
"""
from __future__ import annotations

import json
import os
import sys
from typing import Any


def secure_chmod(path: str | os.PathLike[str]) -> None:
    """Best-effort ``chmod 600``. A warning on stderr if the FS doesn't support it."""
    try:
        os.chmod(path, 0o600)
    except OSError as exc:  # pragma: no cover - exotic filesystems / Windows
        print(
            f"⚠️  Could not chmod 600 {path}: {exc}. "
            "File may be world-readable.",
            file=sys.stderr,
        )


def secure_write_json(path: str | os.PathLike[str], data: Any, *, indent: int = 2) -> None:
    """Write JSON to ``path`` and ``chmod 600`` immediately afterwards."""
    with open(path, "w") as f:
        json.dump(data, f, indent=indent)
    secure_chmod(path)
