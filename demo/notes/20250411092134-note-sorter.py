# title: Note Sorter — Sorting and Ranking Zettel
# date: 2025-04-11
# %%% haystack-end-frontmatter %%%
""" Utilities for sorting and ranking a corpus of plain-text notes (zettel).

Sorting notes by different criteria — date, title, frecency, word count — is a
common need in PKM tooling. This module provides a set of sort key functions and
a configurable sorter that mirrors the ranking logic Haystack applies before
presenting search results. """

import re from pathlib import Path from datetime import datetime from
dataclasses import dataclass, field from typing import Callable

TIMESTAMP_RE = re.compile(r"^(\d{14})-")


@dataclass
class NoteRecord:
    """Parsed metadata for a single note (zettel) in the corpus."""
    path: Path
    filename: str
    title: str = ""
    date: str = ""
    word_count: int = 0
    frecency_score: float = 0.0
    tags: list[str] = field(default_factory=list)

    @property
    def creation_timestamp(self) -> datetime | None:
        """Extract creation datetime from the zettelkasten-style filename."""
        m = TIMESTAMP_RE.match(self.filename)
        if m:
            try:
                return datetime.strptime(m.group(1), "%Y%m%d%H%M%S")
            except ValueError:
                return None
        return None


def parse_note(path: Path) -> NoteRecord:
    """Parse a note file into a NoteRecord, reading past the frontmatter sentinel."""
    sentinel = "%%% haystack-end-frontmatter %%%"
    record = NoteRecord(path=path, filename=path.name)
    body_lines = []
    in_body = False

    try:
        with open(path, encoding="utf-8") as f:
            for line in f:
                if sentinel in line:
                    in_body = True
                    continue
                if not in_body:
                    # Parse frontmatter fields
                    m = re.match(r"^(?:#\+)?title:\s*(.+)", line.strip(), re.IGNORECASE)
                    if m:
                        record.title = m.group(1).strip()
                    m = re.match(r"^(?:#\+)?date:\s*(.+)", line.strip(), re.IGNORECASE)
                    if m:
                        record.date = m.group(1).strip()
                else:
                    body_lines.append(line)
    except OSError:
        pass

    # Count words in the note body
    body_text = " ".join(body_lines)
    record.word_count = len(body_text.split())
    # Use filename stem as fallback title for notes and zettel without explicit title
    if not record.title:
        record.title = path.stem

    return record


def sort_by_date(notes: list[NoteRecord], reverse: bool = True) -> list[NoteRecord]:
    """Sort zettel by creation date embedded in filename."""
    return sorted(notes, key=lambda n: n.creation_timestamp or datetime.min, reverse=reverse)


def sort_by_title(notes: list[NoteRecord]) -> list[NoteRecord]:
    """Sort notes alphabetically by title, case-insensitive."""
    return sorted(notes, key=lambda n: n.title.lower())


def sort_by_frecency(notes: list[NoteRecord], reverse: bool = True) -> list[NoteRecord]:
    """Sort notes by frecency score.

    Note: Haystack's frecency ranks search *chains* for replay, not individual
    notes within a search.  This function is a general-purpose sorter useful
    for supplementary tooling outside Haystack.
    """
    return sorted(notes, key=lambda n: n.frecency_score, reverse=reverse)


def sort_by_length(notes: list[NoteRecord], reverse: bool = True) -> list[NoteRecord]:
    """Sort notes by word count; longer notes rank higher by default."""
    return sorted(notes, key=lambda n: n.word_count, reverse=reverse)


def multi_sort(
    notes: list[NoteRecord],
    sorters: list[tuple[Callable, bool]],
) -> list[NoteRecord]:
    """Apply multiple sort criteria in order of priority.

    sorters is a list of (sort_key_fn, reverse) pairs applied left to right.
    General-purpose multi-criteria sort for supplementary note tooling.
    """
    import functools

    def compare(a: NoteRecord, b: NoteRecord) -> int:
        for fn, rev in sorters:
            ka, kb = fn(a), fn(b)
            if ka != kb:
                return (kb < ka) - (kb > ka) if rev else (ka < kb) - (ka > kb)
        return 0

    return sorted(notes, key=functools.cmp_to_key(compare))


if __name__ == "__main__":
    notes_dir = Path("~/notes").expanduser()
    all_notes = [parse_note(p) for p in notes_dir.glob("*.org")]
    by_date = sort_by_date(all_notes)
    print(f"Newest zettel: {by_date[0].title if by_date else 'none'}")
    by_title = sort_by_title(all_notes)
    print(f"First alphabetically: {by_title[0].title if by_title else 'none'}")
