---
title: Org-Roam vs Haystack
date: 2025-03-13
---
<!-- %%% haystack-end-frontmatter %%% -->
Org-roam and Haystack are both Emacs packages for personal knowledge management
(pkm) built on top of plain-text notes, but they embody different philosophies
about what a second-brain system should do. Org-roam implements the zettelkasten
model faithfully: it maintains a SQLite database of all note IDs and links,
provides backlinks panels showing which zettel reference the current note, and
supports the org-roam-capture workflow for consistent note creation. Haystack
takes a search-first approach: no database, no link maintenance — just fast
ripgrep (rg) full-text search with frecency ranking, expansion groups for
synonym handling, and a clean completing-read interface. The org-roam database
enables precise backlink queries that Haystack cannot replicate: "which notes
link to this specific note by ID" requires a maintained index, not a text
search. Haystack's expansion groups solve the vocabulary-gap problem that org-
roam leaves unaddressed: if you wrote a note using "elisp" and search for
"emacs-lisp," Haystack finds it; org-roam's search does not automatically bridge
that synonym gap. Performance at scale favors Haystack: ripgrep (rg) on 10,000
notes is faster than a SQLite-backed link traversal for broad content discovery,
though the two tools address somewhat different queries. Org-roam requires all
notes to be org files; Haystack is format-agnostic, supporting org, Markdown,
code files, and any plain-text format with an appropriate frontmatter sentinel.
The maintenance burden differs: org-roam requires periodic database sync when
notes are modified outside Emacs; Haystack requires no maintenance because it
reads files directly on every search. Many advanced Emacs pkm users run both:
org-roam for its backlink graph and structured zettelkasten workflow, Haystack
for fast exploratory search and frecency-ranked navigation. The choice is not
binary — the plain-text storage format means both tools can operate on the same
notes directory simultaneously without conflict.