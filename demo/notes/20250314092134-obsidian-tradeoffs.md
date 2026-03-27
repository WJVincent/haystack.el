---
title: Obsidian Tradeoffs
date: 2025-03-14
---
<!-- %%% haystack-end-frontmatter %%% -->
Obsidian is a popular personal knowledge management (pkm) application that
stores notes as plain Markdown files, providing a polished GUI with graph
visualization, backlinks, and a plugin ecosystem. Its core strength is ease of
entry: the interface is approachable for users without Emacs or vim experience,
and the mobile app provides genuine capture capability on the go. The graph view
— a force-directed visualization of all note links — is Obsidian's signature
feature and the main reason many zettelkasten practitioners choose it; critics
note that the graph often becomes a dense hairball that provides more aesthetic
pleasure than navigational utility. Obsidian's plugin ecosystem is extensive:
community plugins cover templating (Templater), spaced repetition, task
management, calendar integration, and even Vim keybindings. The trade-off
compared to Emacs-based pkm is programmability: Obsidian plugins are written in
TypeScript against a limited API, while emacs-lisp gives you complete access to
the entire editor. Obsidian's search is competent but not as fast as ripgrep
(rg) on large corpora; Haystack's rg-based search outperforms it substantially
on a notes directory with thousands of files. Sync across devices requires
either the paid Obsidian Sync service or a third-party solution (git, Syncthing,
Dropbox); the plain-text file format makes any sync strategy work. The lack of a
built-in REPL or scripting layer means that custom automations require plugins,
whereas in Emacs pkm, a few lines of emacs-lisp can implement any workflow
modification immediately. Obsidian's "wikilink" syntax (`[[Note Title]]`) is
convenient but creates implicit dependencies on file naming; Haystack avoids
this by using search for navigation rather than hard-coded links. For users who
want a polished out-of-the-box pkm experience with minimal configuration,
Obsidian is hard to beat; for users who want a programmable, fully customizable
second-brain integrated with their editor, Emacs with Haystack or org-roam is
the stronger foundation.