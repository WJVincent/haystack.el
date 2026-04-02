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

NOTES_DIR = Path("~/notes").expanduser() FRONTMATTER_SENTINEL = "%%% haystack-end-
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


def score_frecency(count: int, last_access: datetime, now: datetime) -> float:
    """Compute a frecency score for a search chain.

    Haystack's frecency formula: count / max(days_since_last_access, 1).
    Note: in Haystack, frecency ranks *search chains* (sequences of root
    search + filters) for replay, not individual notes within results.
    """
    days_since = max((now - last_access).days, 1)
    return count / days_since


def build_retrieval_pipeline(query: str) -> list[dict]:
    """Full pipeline: search -> parse -> return results.

    This is the Python equivalent of a single Haystack root search.
    Results are returned in rg match order (not ranked by frecency —
    Haystack's frecency ranks search chains for replay, not notes
    within a single search).
    """
    matching_paths = run_ripgrep(query, NOTES_DIR, ["org", "md"])

    results = []
    for path_str in matching_paths:
        path = Path(path_str)
        meta = parse_frontmatter(path)
        results.append(meta)

    return results


if __name__ == "__main__":
    # Example: search for zettelkasten/pkm notes
    results = build_retrieval_pipeline("zettelkasten")
    for r in results[:10]:
        print(f"{r.get('title', r['filename'])}")
