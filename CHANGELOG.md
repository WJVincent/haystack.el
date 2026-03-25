# Changelog

All notable changes to Haystack are documented here.
Format loosely follows [Keep a Changelog](https://keepachangelog.com/).

---

## [Unreleased]

### Bug Fixes
- Negation filter (`!term`) passes raw user input to rg instead of `regexp-quote`'d pattern — `!C++` errors because `+` is an invalid regex quantifier. Fix: pass `pattern` instead of `term` to `haystack--run-negation-filter`.

### Documentation
- `claude.md` has three inaccuracies to correct: results buffers use `define-minor-mode` (not `define-derived-mode`); rg invocation uses `xargs -r -a` (not `--files-from`); `/` filename prefix is missing from the Input Prefix Summary table.
- Rename `haystack--sentinel-regexp` to `haystack--sentinel-string` (it is a literal string, not a regex).

### Default Value
- `haystack-moc-code-style` defaults to `'data` but the data formatter falls back to comment style unconditionally. Change default to `'comment` to reflect actual behavior.

---

## [0.2.0] — 2026-03-24

### Added
- Result buffer header buttons: `[root]`, `[up]`, `[down]`, `[tree]` — clickable with mouse or keyboard `RET`.
- Go-down navigation and child-picker buffer (`d` key) when a buffer has multiple children.
- Tree view (`t` / `C-c h t`) showing all open Haystack buffers as a navigable forest with sibling navigation (`M-n`/`M-p`) and `←` marker on the current buffer.
- Kill operations: `k` (node), `K` (subtree), `M-k` (whole tree).
- `haystack-kill-orphans` — cleans up childless orphaned buffers, leaves orphans-with-children as de facto roots.

### Changed
- Buffer naming convention updated to align with tree-view display.

---

## [0.1.0] — initial

### Added
- `haystack-run-root-search` — ripgrep-backed full-notes search with results in a `grep-mode` buffer.
- `haystack-filter-further` (`f`) — progressive filtering scoped to files in the current buffer.
- Input prefix system: `!` negation, `/` filename filter, `=` exact literal, `~` raw regex; modifiers compose.
- `haystack-new-note` — creates a timestamped note with frontmatter for org, markdown, and many code file types.
- `haystack-search-region` (`C-c h r`) — root search from active region.
- MOC generator: `c` copies links to kill ring; `C-c h y` yanks at point.
- `haystack-show-tree` (`C-c h t`) buffer tree view.
- Results buffer minor mode (`haystack-results-mode`) with `n`/`p` navigation, `u` (up), `f` (filter), `c` (MOC), `?` (help).
- `haystack-regenerate-frontmatter` — rebuilds frontmatter in an existing note.
- Configurable context width (`haystack-context-width`) and file glob restriction (`haystack-file-glob`).
- Benchmarking suite (`test/haystack-bench.el`).
