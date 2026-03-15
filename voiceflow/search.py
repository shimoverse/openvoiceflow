"""History search: full-text search over JSONL transcript logs."""
import json
from datetime import datetime, timedelta
from pathlib import Path
from .config import LOG_DIR


def search_transcripts(
    query: str,
    date: str = None,
    last_days: int = None,
    limit: int = 50,
) -> list[dict]:
    """Search transcript logs for a query string.

    Args:
        query:     Case-insensitive substring to search in raw/cleaned fields.
        date:      Restrict to a single date (YYYY-MM-DD string).
        last_days: Restrict to the last N calendar days (inclusive of today).
        limit:     Maximum number of results to return (most recent first).

    Returns:
        List of matching entries, sorted by timestamp descending, each:
        {"timestamp": str, "raw": str, "cleaned": str, "file": str}
    """
    log_dir = Path(LOG_DIR)
    if not log_dir.exists():
        return []

    # Determine which JSONL files to scan.
    jsonl_files = sorted(log_dir.glob("*.jsonl"))
    if not jsonl_files:
        return []

    # Build date-range filter (applied to filenames for fast pre-filtering).
    date_filter: set[str] | None = None
    if date:
        date_filter = {date}
    elif last_days is not None and last_days > 0:
        today = datetime.now().date()
        date_filter = {
            (today - timedelta(days=i)).isoformat()
            for i in range(last_days)
        }

    query_lower = query.lower()
    matches: list[dict] = []

    for jsonl_path in jsonl_files:
        # Fast skip: filename is YYYY-MM-DD.jsonl — skip if outside date filter.
        if date_filter is not None:
            stem = jsonl_path.stem  # e.g. "2026-03-15"
            if stem not in date_filter:
                continue

        try:
            with open(jsonl_path, "r", encoding="utf-8") as fh:
                for line in fh:
                    line = line.strip()
                    if not line:
                        continue
                    try:
                        entry = json.loads(line)
                    except json.JSONDecodeError:
                        continue

                    raw = entry.get("raw", "")
                    cleaned = entry.get("cleaned", "")

                    if query_lower in raw.lower() or query_lower in cleaned.lower():
                        matches.append(
                            {
                                "timestamp": entry.get("timestamp", ""),
                                "raw": raw,
                                "cleaned": cleaned,
                                "file": jsonl_path.name,
                            }
                        )
        except OSError:
            # Skip unreadable files gracefully.
            continue

    # Sort most-recent first; entries without a timestamp sort to the end.
    matches.sort(key=lambda e: e["timestamp"], reverse=True)

    return matches[:limit]
