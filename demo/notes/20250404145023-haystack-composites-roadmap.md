---
title: Haystack Composites Roadmap
date: 2025-04-04
---
<!-- %%% haystack-end-frontmatter %%% -->
Haystack composites are a planned Phase 3 feature. A composite is a full-text
concatenation of the note files in a search result set, assembled into a single
readable document. The mental model is a git commit for retrieval: you find a
useful set of notes via progressive filtering, then commit that search result to
a named file so you can return to it, annotate it, or share it without
reconstructing the search.

Running `haystack-compose` on a results buffer reads the full content of each
file in view and builds a read-only staging buffer showing all the material
together, separated by file headers and navigation links. Pressing `C-c C-c`
writes this to disk as `@comp__canonical-chain.ext` in the notes directory. The
`@` prefix is a naming convention that lets ripgrep filter composites in or out
with a single `--glob` flag; the canonical chain (`programming--rust--bevy`,
derived from expansion group roots) ties the composite to the search that
produced it.

The composite file gets frontmatter with a SOURCE-CHAIN field. Haystack reads
this on every search to surface any matching composite in the results buffer
header, so the next time you search that chain you see a navigable link to the
document you assembled last time. Regenerating a composite with `C-c C-c`
overwrites the existing file after confirmation; the SOURCE-CHAIN stays stable
across regeneration so the surfacing mechanism continues to work.

Composites are excluded from normal searches by default (`--glob !@*`) and can
be isolated for browsing with the composite filter toggle. They are ordinary
plain-text files and are fully portable — readable by any editor, diffable in
git, and independent of Haystack's own data files.
