---
title: Plain Text PKM
date: 2025-04-03
---
<!-- %%% haystack-end-frontmatter %%% -->
Plain-text PKM (personal knowledge management) is the practice of maintaining
your second-brain as a directory of plain-text files — org, Markdown, or similar
— without relying on proprietary databases or binary formats. The alignment
between plain-text storage and the Haystack design is complete: Haystack
requires no format beyond the frontmatter sentinel and works equally well on
.org, .md, and any other text file. The zettelkasten tradition is itself a
plain-text tradition: Luhmann's note cards were physical plain text; digital
plain-text implementations like org-roam and Haystack preserve this ethos.
Version control with Git is the natural companion to plain-text PKM: each commit
is a snapshot of your second-brain, diffs show exactly what changed in any note,
and branching enables experimental reorganization. Ripgrep (rg) operates on
plain text — there is no special indexing step, no database to update, no format
conversion. You create a file, and it is immediately searchable. The portability
of plain-text PKM means you can switch tools without losing your notes: a corpus
of Markdown zettel works equally well with Obsidian, with a shell script, with
Haystack, or with any future tool that understands text files. Cross-referencing
in plain-text PKM can be done either with explicit links (org-roam IDs, Markdown
wikilinks) or implicitly through shared vocabulary that full-text search can
surface. The cognitive-load of plain-text PKM is low at the format level: no
decisions about rich text formatting, embedded media, or database schema — just
write, save, search. For long-lived knowledge-management practices (10+ year
horizons), plain-text is the only format with a proven durability track record —
every other format has a risk of obsolescence. Haystack's design explicitly
targets plain-text PKM workflows: it adds speed, frecency, and vocabulary
expansion on top of what the filesystem and ripgrep already provide for free.