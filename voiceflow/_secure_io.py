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


def secure_dir(path: str | os.PathLike[str]) -> None:
    """Best-effort ``chmod 700`` for a directory holding sensitive files."""
    try:
        os.chmod(path, 0o700)
    except OSError:
        pass


def secure_write_json(path: str | os.PathLike[str], data: Any, *, indent: int = 2) -> None:
    """Write JSON to ``path`` atomically, created with mode 600.

    The payload is written to a same-directory temp file opened with 0600
    (never world-readable, even transiently) and moved into place with
    ``os.replace``, so a crash mid-write can't truncate the target file.
    """
    path = os.fspath(path)
    payload = json.dumps(data, indent=indent)
    tmp_path = f"{path}.tmp{os.getpid()}"
    # O_EXCL: refuse to open through an attacker-pre-planted temp file.
    # O_NOFOLLOW: never follow a symlink at the temp path. Together these
    # stop a same-directory symlink swap from redirecting a secrets write.
    # (O_NOFOLLOW may be absent on exotic platforms — degrade gracefully.)
    flags = os.O_WRONLY | os.O_CREAT | os.O_TRUNC | os.O_EXCL
    flags |= getattr(os, "O_NOFOLLOW", 0)
    try:
        fd = os.open(tmp_path, flags, 0o600)
    except FileExistsError:
        # A stale temp file from a crashed write (same pid reused) — remove
        # it and retry once. A real symlink here is refused by O_EXCL above.
        os.unlink(tmp_path)
        fd = os.open(tmp_path, flags, 0o600)
    try:
        with os.fdopen(fd, "w") as f:
            f.write(payload)
        os.replace(tmp_path, path)
    except BaseException:
        try:
            os.unlink(tmp_path)
        except OSError:
            pass
        raise
    secure_chmod(path)
