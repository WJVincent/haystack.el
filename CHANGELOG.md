# Changelog

All notable changes to Haystack are documented here.  Format loosely
follows [Keep a Changelog](https://keepachangelog.com/).

---

## [Unreleased]

### Added
- **Frecency leaf/all toggle** — `haystack-frecent` now defaults to
  leaf-only mode, hiding intermediate chains dominated by a deeper
  more-visited search. `C-u haystack-frecent` shows all recorded
  chains. In `*haystack-frecent*`, `v` toggles between views; the
  header reflects the current mode (`view: leaf` / `view: all`).
- **Multi-word expansion groups** — expansion groups now accept
  multi-word terms (e.g. `"emacs lisp"`). Associating, renaming, and
  dissolving groups works identically for multi-word and single-word
  members. Searching for a multi-word term that belongs to a group
  expands it to a ripgrep alternation just like single-word terms.

### Internal
- `haystack--frecent-leaf-p` — predicate: non-nil if no deeper chain
  with a strictly higher score starts with this entry's chain.
- `haystack--frecent-leaves` — filters an entry list to leaves only.
- `haystack--build-pattern` / `haystack--build-emacs-pattern` —
  `multi-word` parameter removed; expansion is now suppressed only by
  the `literal` flag.

---

## [0.5.0] — 2026-03-25

### Added
- **Frecency engine** — records every root search and filter step;
  scores entries as `count / max(days_since_access, 1)`; persists to
  `.haystack-frecency.el` in the notes directory.
  - `haystack-frecent` (`C-c h f`) — `completing-read` interface
    sorted by score descending; selects a recorded search chain and
    replays it, materialising only the final result buffer (leaf-only
    replay).
  - `haystack-describe-frecent` — diagnostic buffer showing all
    recorded chains with score, visit count, and days since last
    access.
    - `t` sort by score (default), `f` by frequency, `r` by recency;
      `s` cycles through all three.
    - `k` kills the entry at point after `y-or-n-p` confirmation.
    - `?` opens a help popup listing all buffer commands.
  - `haystack-frecency-save-interval` defcustom — idle seconds before
    flushing to disk (default 60). Set to `nil` to write immediately on
    every buffer visit. Always flushed on Emacs shutdown.

### Internal
- `haystack--frecency-chain-key` — derives the canonical chain key
  (list of prefixed term strings) from a search descriptor.
- `haystack--frecency-record` — called on every buffer creation to
  increment count and update timestamp.
- `haystack--frecency-score` — pure scoring function; computed on
  read, never stored.
- `haystack--frecency-flush` / `haystack--load-frecency` — disk I/O
  helpers.
- `haystack--frecency-replay` — stubs
  `pop-to-buffer`/`switch-to-buffer` during replay, kills intermediate
  buffers, detaches final buffer from parent chain before surfacing
  it.
- `haystack-frecent-mode` — derived mode for `*haystack-frecent*`
  buffer; `haystack--frecent-render` and `haystack--frecent-sort-entries`
  are the rendering primitives.

---

## [0.4.0] — 2026-03-25

### Added
- **MOC structured data format** — `haystack-moc-code-style 'data` now
  produces language-appropriate data structures instead of falling
  back to comment style. Supported out of the box: JS/TS/JSX/TSX
  (`const` array), Python (list of dicts), Lisp dialects — Emacs Lisp,
  Common Lisp, Scheme, Clojure (`defvar` plist list), Lua/Fennel
  (local table). Each block opens with a comment line containing the
  full search chain.
- `haystack-moc-data-formatters` defcustom — alist mapping file
  extensions to formatter functions `(loci chain) → string`. Add a
  language with one line: `(push '("rb" . my-formatter)
  haystack-moc-data-formatters)`.  Mirrors the
  `haystack-frontmatter-functions` extensibility pattern.
- `haystack-moc-quote-string` — public helper for building
  double-quoted string literals in custom formatter functions.
- Filter prompt updated to `[=]literal [/]filename [!]negate [~]regex`
  format for improved scannability.
- `haystack-rename-group-root` — renames the canonical root term of an
  expansion group. Prompts with completion on existing roots;
  validates the new name is single-word and not already in any group.
- `haystack-dissolve-group` — removes an entire expansion group.
  Prompts with completion on all group members (root or synonym); all
  members revert to literal matching.
- `haystack-test--with-groups` test macro now writes initial groups to
  disk so commands that reload from file see consistent state.

### Changed
- `haystack-copy-moc` now also stores the search chain string
  (`haystack--last-moc-chain`) for use as a comment header in
  data-style output.

### Internal
- Built-in data formatters extracted into named functions
  (`haystack--moc-data-format-js`, `haystack--moc-data-format-python`,
  `haystack--moc-data-format-elisp`, `haystack--moc-data-format-lua`)
  so they can be referenced or reused by custom formatters.
- `haystack--format-moc-data-block` is now a pure dispatcher over
  `haystack-moc-data-formatters`; language logic no longer lives in a
  `cond`.
- `haystack--descriptor-chain-string` — formats the complete search
  chain from a stored descriptor without appending a current term;
  used by `haystack-copy-moc`.

## [0.3.0] — 2026-03-25

### Added
- **Expansion groups** — synonym/alias system stored in
  `.expansion-groups.el` in the notes directory. A single-word search
  term is automatically expanded to a ripgrep alternation `(A|B|C)`
  when a matching group is found.
  - `haystack-associate` — interactive command to link two terms into
    an expansion group; handles four states: same group (no-op),
    different groups (move/abort), one term unassigned (add to
    existing or create new), and the symmetric case.
  - `haystack-validate-groups` — checks for duplicate terms across
    groups and emits a warning buffer on conflicts.
  - `haystack-describe-expansion-groups` — displays the full groups
    alist in a readable buffer for inspection.
  - `haystack-reload-expansion-groups` — force-reloads
    `.expansion-groups.el` from disk.
- **Expansion display in buffer headers** — when a root search or
  filter expands via a group, the header shows
  `root=(Programming|Coding|Code)` so the active expansion is always
  visible.
- `haystack--sanitize-slug` — applied to new-note slug input:
  collapses whitespace runs to `-` and strips characters illegal in
  filenames (`/ \ : * ? " < > |`), so typing "a note name" produces
  `a-note-name.org` instead of a filename with spaces.
- Filter prompt now shows modifier hints: `Filter (! negate / filename
  = literal ~ regex): ` so the available prefix characters are
  discoverable without opening `?` help.

### Bug Fixes
- Negation filter (`!term`) was passing raw user input to rg instead
  of the `regexp-quote`'d pattern — `!C++` errored because `+` is an
  invalid regex quantifier. Fixed by passing `pattern` instead of
  `term` to `haystack--run-negation-filter`.
- Filename negation with expansion groups (`!filename=term`) was not
  excluding all expanded variants. Root cause: ripgrep alternation
  syntax `(A|B)` is not valid Emacs regex. Fixed by adding
  `haystack--build-emacs-pattern` which produces `A\|B` Emacs
  alternation; filename-filter call sites now use the `:emacs-pattern`
  from `haystack--parse-input`.
- `/` filename filter was not matching results inside subdirectories —
  `file-name-nondirectory` returned only the basename, so `sicp`
  failed to exclude `sicp-org/README.org`. Fixed by matching against
  the full path relative to the notes directory.
- `haystack--display-term`: normalises whitespace (collapses
  newlines/tabs to single spaces) and truncates long terms as
  `first13...last13` for display in buffer names, headers, and the
  tree view. Fixes a UX problem where `haystack-search-region` on a
  paragraph produced unwieldy buffer names containing newlines. The
  full term is preserved in the search descriptor and passed to rg
  unchanged.

### Changed
- `xargs -r -a FILE rg ARGS` replaced with POSIX-portable `xargs -0 rg
  ARGS < FILE`. The `-r` (no-run-if-empty) and `-a` (read-from-file)
  flags are GNU-only; the new form works on Linux, macOS, and BSD
  without modification.
- Filelist temp files now use null-byte (`\0`) separators instead of
  newlines, matching `xargs -0` and correctly handling filenames with
  embedded newlines.
- `haystack-moc-code-style` default changed from `'data` to `'comment`
  to reflect actual behaviour (the data formatter unconditionally
  falls back to comment style).
- Renamed `haystack--sentinel-regexp` to `haystack--sentinel-string` —
  it is a literal string, not a regex.

### Internal / Documentation
- `haystack--parse-input` now returns both `:pattern` (ripgrep regex)
  and `:emacs-pattern` (Emacs regex) — necessary because `(A|B)` and
  `A\|B` are different syntaxes.
- Removed dead `haystack--build-rg-args-from-filelist` which
  referenced the nonexistent `rg --files-from` flag.
- `claude.md` updated: xargs usage corrected; `--files-from`
  references removed; dual-pattern system documented.
- `docs/ROADMAP.org` updated: stale `rg --files-from` warning removed;
  composite TODO updated to `xargs -0 rg`.
- `README.md`: `/` filter now documents relative-path matching; `~`
  regex example corrected (`~foo|bar`, not `~foo\|bar`); MOC two-step
  workflow explained.

---

## [0.2.0] — 2026-03-24

### Added
- Result buffer header buttons: `[root]`, `[up]`, `[down]`, `[tree]` —
  clickable with mouse or keyboard `RET`.
- Go-down navigation and child-picker buffer (`d` key) when a buffer
  has multiple children.
- Tree view (`t` / `C-c h t`) showing all open Haystack buffers as a
  navigable forest with sibling navigation (`M-n`/`M-p`) and `←`
  marker on the current buffer.
- Kill operations: `k` (node), `K` (subtree), `M-k` (whole tree).
- `haystack-kill-orphans` — cleans up childless orphaned buffers,
  leaves orphans-with-children as de facto roots.

### Changed
- Buffer naming convention updated to align with tree-view display.

---

## [0.1.0] — initial

### Added
- `haystack-run-root-search` — ripgrep-backed full-notes search with
  results in a `grep-mode` buffer.
- `haystack-filter-further` (`f`) — progressive filtering scoped to
  files in the current buffer.
- Input prefix system: `!` negation, `/` filename filter, `=` exact
  literal, `~` raw regex; modifiers compose.
- `haystack-new-note` — creates a timestamped note with frontmatter
  for org, markdown, and many code file types.
- `haystack-search-region` (`C-c h r`) — root search from active
  region.
- MOC generator: `c` copies links to kill ring; `C-c h y` yanks at
  point.
- `haystack-show-tree` (`C-c h t`) buffer tree view.
- Results buffer minor mode (`haystack-results-mode`) with `n`/`p`
  navigation, `u` (up), `f` (filter), `c` (MOC), `?` (help).
- `haystack-regenerate-frontmatter` — rebuilds frontmatter in an
  existing note.
- Configurable context width (`haystack-context-width`) and file glob
  restriction (`haystack-file-glob`).
- Benchmarking suite (`test/haystack-bench.el`).
