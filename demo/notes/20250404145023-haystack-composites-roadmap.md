---
title: Haystack Composites Roadmap
date: 2025-04-04
---
<!-- %%% haystack-end-frontmatter %%% -->
Haystack composites are a Phase 3 feature. A composite is a windowed extract of
the note files in a search result set, assembled into a single org-mode
document with content centered around each match line. The mental model is a
snapshot for retrieval: you find a useful set of notes via progressive
filtering, then commit that search result to a named file so you can return to
it, annotate it, or share it without reconstructing the search.

Running `haystack-compose` (`C-c C-c` in a results buffer) opens an editable
staging buffer showing each matched file as an org section with context
windowed around the match, controlled by `haystack-composite-max-lines`.
Pressing `C-c C-c` in the staging buffer writes to disk as
`@comp__canonical-chain.org` (always `.org`) in the notes directory. `C-c C-k`
discards without saving. The `@` prefix is a naming convention that lets
ripgrep filter composites in or out with a single `--glob` flag; the canonical
chain (each term resolved to its expansion group root, lowercased, slugified,
joined with `__`) ties the composite to the search that produced it.

The composite file gets frontmatter with a `HAYSTACK-CHAIN` field. Haystack
checks for the existence of a composite file matching the current search
chain's canonical slug and surfaces it in the results buffer header as a
clickable `[composite: @comp__chain.org]` link. Regenerating a composite with
`C-c C-c` overwrites the existing file; the canonical slug stays stable across
regeneration so the surfacing mechanism continues to work.
`haystack-composite-protect` (default t) intercepts manual saves in the
staging buffer to prevent accidental overwrites.

Composites are excluded from normal searches by default (`--glob !@*`).
`C-u haystack-run-root-search` includes them, and
`haystack-search-composites` shows only composites. They are ordinary
plain-text org files and are fully portable — readable by any editor, diffable
in git, and independent of Haystack's own data files.
