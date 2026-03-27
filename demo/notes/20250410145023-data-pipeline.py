# title: Data Pipeline for Note Search and Retrieval
# date: 2025-04-10
# %%% haystack-end-frontmatter %%%
""" A simple pipeline for processing a plain-text notes corpus and building a
retrieval-ready data structure. This demonstrates how ripgrep (rg) output can be
consumed by a Python pipeline for further ranking or analysis.

In practice, Haystack handles this in Emacs Lisp with rg subprocess calls, but a
Python pipeline is useful for batch processing, corpus statistics, or building
supplementary indexes outside the editor. """

import subprocess import json import re from pathlib import Path from datetime
import datetime

NOTES_DIR = Path("~/notes").expanduser() FRONTMATTER_SENTINEL = "%%% pkm-end-
frontmatter %%%"


def run_ripgrep(query: str, notes_dir: Path, extensions: list[str]) -> list[str]:
    """Run rg and return list of matching file paths.

    Uses --files-with-matches so we get file paths, not individual lines.
    The search engine here mirrors what Haystack does internally via rg.
    """
    ext_args = []
    for ext in extensions:
        ext_args += ["--glob", f"*.{ext}"]

    result = subprocess.run(
        ["rg", "--files-with-matches", "--ignore-case", query, str(notes_dir)] + ext_args,
        capture_output=True,
        text=True,
    )
    return result.stdout.strip().splitlines()


def parse_frontmatter(file_path: Path) -> dict:
    """Extract frontmatter metadata from a note file.

    Reads up to the haystack-end-frontmatter sentinel and parses key: value lines.
    Works for both org-style (#+KEY: value) and YAML-style (key: value) notes.
    """
    metadata = {"path": str(file_path), "filename": file_path.name}
    try:
        with open(file_path, encoding="utf-8") as f:
            for line in f:
                if FRONTMATTER_SENTINEL in line:
                    break
                # Match org-style #+TITLE: or YAML-style title:
                m = re.match(r"^(?:#\+)?(\w+):\s*(.+)", line.strip(), re.IGNORECASE)
                if m:
                    metadata[m.group(1).lower()] = m.group(2).strip()
    except OSError:
        pass
    return metadata


def score_frecency(path: str, visit_log: dict, now: datetime) -> float:
    """Compute a simple frecency score for a note path.

    Frecency combines recency (time-decayed) and frequency (visit count).
    This mirrors the frecency engine in Haystack's emacs-lisp implementation.
    """
    record = visit_log.get(path, {"visits": [], "count": 0})
    score = 0.0
    for visit_time in record.get("visits", []):
        age_days = (now - datetime.fromisoformat(visit_time)).days
        # Exponential decay with 30-day half-life
        score += 2 ** (-age_days / 30)
    return score


def build_retrieval_pipeline(query: str, visit_log_path: Path) -> list[dict]:
    """Full pipeline: search -> parse -> rank -> return results.

    This is the Python equivalent of a single Haystack search invocation.
    """
    visit_log = {}
    if visit_log_path.exists():
        with open(visit_log_path) as f:
            visit_log = json.load(f)

    matching_paths = run_ripgrep(query, NOTES_DIR, ["org", "md"])
    now = datetime.now()

    results = []
    for path_str in matching_paths:
        path = Path(path_str)
        meta = parse_frontmatter(path)
        meta["frecency_score"] = score_frecency(path_str, visit_log, now)
        results.append(meta)

    # Sort by frecency score descending; text relevance is already filtered by rg
    results.sort(key=lambda r: r["frecency_score"], reverse=True)
    return results


if __name__ == "__main__":
    # Example: search for zettelkasten/pkm notes ranked by frecency
    results = build_retrieval_pipeline("zettelkasten", Path(".haystack-frecency.json"))
    for r in results[:10]:
        print(f"{r.get('title', r['filename'])}  (frecency={r['frecency_score']:.3f})")
