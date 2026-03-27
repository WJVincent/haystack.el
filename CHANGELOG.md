# Changelog

All notable changes to Haystack are documented here.  Format loosely
follows [Keep a Changelog](https://keepachangelog.com/).

## [Unreleased]

### Added
- `haystack-run-root-search-at-point` (`C-c h .`, `.` in results buffers):
  searches the word under the cursor without prompting.  Hyphens and
  underscores are treated as word characters, so `bevy-ecs` and `my_note`
  are captured whole.  Falls back to the active region when one exists.
- `haystack--word-at-point`: internal helper for word extraction.
- Stop word infrastructure: `.haystack-stop-words.el` in the notes directory,
  auto-seeded from the NLTK English stop words corpus (182 words) on first use.
  - `haystack-add-stop-word` / `haystack-remove-stop-word` /
    `haystack-describe-stop-words` for list management.
  - Single-word root searches and filter-further queries against a stop word
    now prompt: `[s]earch anyway` (literal), `[r]emove from list`, `[q]uit`.
    Multi-word terms and `=`-prefixed inputs are never blocked.

---

## [0.10.0] — 2026-03-27

### Fixed
- `haystack--frecency-replay` now explicitly loads expansion groups before
  replaying.  Previously they were loaded as a side effect of
  `haystack-run-root-search`, which made replay work only by accident.
- `haystack--frecency-replay` no longer uses `cl-letf` to silence
  `pop-to-buffer`/`switch-to-buffer`.  Instead a `haystack--suppress-display`
  dynamic variable is checked at the three display call sites in
  `haystack-run-root-search` and `haystack-filter-further`.  This is cleaner
  and does not globally rebind core Emacs functions during replay.
- Frecency timer and `kill-emacs-hook` are now deferred to first interactive
  use via `haystack--frecency-ensure`.  Previously `(require 'haystack)`
  unconditionally installed an idle timer and a shutdown hook, violating the
  Emacs packaging norm that loading a library should not produce side effects.
  `haystack--frecency-ensure` is called at the top of `haystack-run-root-search`,
  `haystack-filter-further`, and `haystack-frecent`; customizing
  `haystack-frecency-save-interval` before first use also counts as
  initialization so the timer is never double-installed.

### Removed
- `haystack-composite-extension` defcustom removed.  Composite files are
  always org-formatted (the staging buffer derives from `org-mode` and uses
  org headings, links, and `#+` properties), so a configurable extension was
  misleading.  The extension is now hardcoded to `"org"`.

### Added
- `haystack-new-note-with-moc`: combo command — creates a new note and inserts
  the current results buffer as a MOC in one step.  Bound to `N` in both
  `haystack-results-mode-map` and `haystack-prefix-map`.
- `haystack--format-moc-text`: internal helper consolidating MOC formatting
  logic; `haystack-yank-moc` now delegates to it.
- `haystack--suppress-display` dynamic variable: allows internal callers
  (currently `haystack--frecency-replay`) to suppress window display without
  globally redefining `pop-to-buffer` or `switch-to-buffer`.
- `haystack--display-term-max-length` and `haystack--display-term-context`
  named constants for the 30/13 truncation thresholds in `haystack--display-term`.
- `haystack-notes-directory` defcustom type now uses
  `(choice (const :tag "Not set" nil) directory)` so the Customize UI correctly
  represents the unset state.
- `haystack-tree-mode-map` and `haystack-frecent-mode-map` are now defined as
  `defvar` + `make-sparse-keymap` blocks before their `define-derived-mode`
  calls, matching the pattern used by `haystack-results-mode-map` and
  `haystack-compose-mode-map`.
- Demo corpus copy uses `copy-directory` (Elisp built-in) instead of
  `call-process "cp"`.  Removes the GNU coreutils trailing-dot convention
  dependency and works on any platform Emacs supports.

- All rg argument builders (`haystack--rg-base-args`, `haystack--build-rg-args`,
  `haystack--build-rg-count-args`, `haystack--rg-count-xargs-args`,
  `haystack--files-for-root-search`, AND query builder) replaced `nconc` with
  `append`.  The lists were always freshly built each call so the mutation was
  safe, but `append` makes the absence of shared state explicit.

### Fixed
- Results buffer `?` help menu: added missing `RET` (visit file / activate
  button), `N` (new note + insert MOC), and a new Composite section with
  `C-c C-c` (compose composite note).  All bound commands in
  `haystack-results-mode-map` are now represented.
- Help buffer now adapts to window width: two-column layout at 100+ columns
  (Navigation/Filter/Tree left, MOC/Composite right) roughly halves the
  required height; single-column layout below 100 columns.  Keys are
  highlighted with `font-lock-constant-face`, section headers with
  `font-lock-keyword-face`, and rule lines with `shadow` — all resolved
  from the active color theme.

### Docs
- `README.md`: added AND queries section, Composite Notes section,
  updated quick-start table (`C-c h w`, `C-c h C`), results buffer keys
  (`C-c C-c`), customization table (composite defcustoms), and noted
  atomic behaviour of `haystack-rename-group-root`.
- `docs/how-to-think-about-haystack.md`: "The Three Things" expanded to
  four — composite notes added.
- `CLAUDE.md`: renamed from `claude.md`; updated composite filter
  section (prefix arg / dedicated command, no transient), composite
  lookup (file-exists-p, not rg -l), `haystack-composite-extension`
  defcustom name, `:composite-filter` quoting, canonical chain slug
  description.

---

## [0.9.0] — 2026-03-26

### Added
- `haystack-rename-group-root` now performs a fully atomic update across
  three subsystems when a root term is renamed:
  1. **Expansion groups** — root key updated in `.expansion-groups.el`
  2. **Frecency data** — all chain keys containing the old root term are
     rewritten in memory; data is flushed to `.haystack-frecency.el`.
     When the rename would produce a duplicate key, entries are merged
     (counts summed, latest timestamp kept).
  3. **Composite files** — `@comp__*.ext` files whose slug contains the
     old canonical slug segment are renamed atomically; on failure any
     already-completed renames are rolled back.
  The success message reports how many composites were renamed.
- `haystack-search-composites` — search only composite (`@*`) files;
  bound to `C` in the global prefix map.
- `haystack-run-root-search` now accepts a `C-u` prefix argument to
  include composite files in the search (`composite-filter` = `'all`).
  Without a prefix, composite files are excluded as before.
- `haystack-composite-max-lines` defcustom — per-file line cap in
  composites (default 300, `nil` = no limit).  Truncated files are
  windowed around the first match with `...` ellipsis markers.
- `haystack-composite-all-matches` defcustom — when non-nil, one
  section per match line rather than per file (default `nil`).
- `haystack-composite-protect` defcustom — when non-nil (default),
  manual saves in composite buffers redirect to the new-note flow.
- `haystack-composite-extension` defcustom — file extension for
  composite notes (default `"org"`).
- `haystack-compose-mode` — org-derived major mode for composite
  staging buffers.  `C-c C-c` → `haystack-compose-commit`;
  `C-c C-k` → `haystack-compose-discard`.  When
  `haystack-composite-protect` is non-nil, `write-contents-functions`
  intercepts manual saves and redirects to the new-note flow.
- `haystack-compose-commit` — always regenerates the composite cleanly
  from the stored loci and writes it to `@comp__CHAIN.ext`.  If the
  staging buffer was modified, prompts to save the full buffer as a new
  note via `haystack-new-note`.
- `haystack-compose-discard` — kills the staging buffer without writing.
- `haystack-compose` — interactive command; builds a
  `*haystack-compose:CHAIN*` staging buffer in `haystack-compose-mode`
  from the current results buffer.  Each source file becomes an org
  heading with a link; content is windowed per
  `haystack-composite-max-lines`.  Bound to `C-c C-c` in results buffers
  and `w` in the global prefix map.
- Composite surfacing in results buffer headers — when a composite file
  exists for the current search chain, a `[composite: @comp__CHAIN.ext]`
  link line is shown in the header.  The link is a clickable button
  that visits the composite file via `find-file`.

### Internal
- `haystack--frecency-rewrite-term` — rewrites one frecency chain key list,
  replacing OLD-ROOT with NEW-ROOT while preserving any prefix characters.
- `haystack--frecency-rename-in-data` — applies the rewrite across a full
  frecency alist; merges colliding entries on duplicate keys.
- `haystack--composite-rename-pairs` — scans `haystack-notes-directory`
  for `@comp__*.ext` files and returns `(old-path . new-path)` pairs for
  those whose `__`-delimited slug contains the old canonical slug segment.
- `haystack--rename-composites-atomic` — executes a list of rename pairs;
  rolls back completed renames if any step fails.
- `haystack--extract-all-file-loci` — like `haystack--extract-file-loci`
  but returns all `(PATH . LINE)` pairs without deduplication, for use
  with `haystack-composite-all-matches`.
- `haystack--composite-file-content` — applies the line-cap window
  around a match line, with `...` ellipsis at truncated ends.
- `haystack--compose-file-section` — formats one org section
  (heading + windowed content) for a single source file locus.
- `haystack-compose-mode` — derived org-mode for composite staging
  buffers; keybindings and write path added in the next step.
- `haystack--find-composite` — returns the path of an existing
  composite for a descriptor (via `file-exists-p` on the deterministic
  filename), or nil when none has been written yet.
- `haystack--composite-filename` — returns the absolute path
  `@comp__CANONICAL-CHAIN.EXT` in the notes directory for a given
  search descriptor.
- `haystack--canonical-term-slug` — resolves a single term to its
  expansion group root, lowercases, and slugifies (non-alphanumeric
  runs → hyphens).  Negated terms gain a `not-` prefix; filename
  terms gain `fn-`.
- `haystack--canonical-chain-slug` — builds the full canonical slug
  for a search descriptor by flattening root (expanding AND sub-terms),
  then filter terms, joined with `__`.  Equivalent AND and sequential
  filter chains produce the same slug.
- `haystack--format-header` — gained optional `composite-path` argument;
  when non-nil, a `[composite: FILENAME]` line is inserted before the
  closing rule.
- `haystack--apply-header-buttons` — gained optional `composite-path`
  argument; when non-nil, wires the composite filename as a `find-file`
  button.
- `haystack--setup-results-buffer` — gained optional `composite-path`
  argument; threads it through to `haystack--apply-header-buttons`.

---

## [0.8.0] — 2026-03-26

### Added
- **AND queries** — a root search of `rust & async` (spaces around `&`
  required) finds files containing all terms and returns matches for the
  first term in that intersection.  Any number of terms may be combined:
  `rust & async & tokio`.  Prefix modifiers (`=`, `~`) work per token.
  The volume gate runs on the intersection file set (not the first term
  alone) so it only fires when the final result would be large.  `!`
  negation is not supported inside `&` queries — use `filter-further`
  after the AND search instead.  AND chains are recorded by frecency and
  replay correctly.
- **Two-phase volume gate** — before running a root search or content
  filter, haystack runs `rg --count` first and prompts
  `"N lines across M files — run anyway?"` if the total meets or
  exceeds 500 lines.  The gate is skipped for filename filters
  (already narrowed in Elisp) and negation filters.  Users who want
  the large result set can confirm and proceed; the prompt is the
  natural point to refine with `=` or `/` prefixes instead.
- `--max-count=50` added to `haystack--rg-base-args` — silently clamps
  per-file output to 50 lines.  Invisible in normal usage; prevents a
  single pathological file from flooding the results buffer.
- `--max-columns=500` added to `haystack--rg-base-args` — drops lines
  wider than 500 characters.  Prevents minified JS and base64 blobs
  from producing unreadable grep lines.

### Changed
- **Sentinel renamed** — `%%% pkm-end-frontmatter %%%` is now
  `%%% haystack-end-frontmatter %%%` across all frontmatter generators,
  the `haystack--sentinel-string` constant, tests, demo corpus, and
  documentation.  Existing notes with the old sentinel will not be
  recognised by `haystack-regenerate-frontmatter` — a one-time
  `sed` pass over your notes directory is needed:
  `sed -i 's/pkm-end-frontmatter/haystack-end-frontmatter/g' notes/**/*`

### Documentation
- README Requirements section now states the Unix toolchain requirement
  explicitly: Linux, macOS, or WSL.  Native Windows is unsupported.
- README Design section gains an **Emergent structure** paragraph
  contrasting Haystack's retrieval-driven structure (frecency +
  composites) with graph PKM's link-maintenance model.  Includes the
  "git commit for retrieval" framing for composites.
- Demo note `haystack-composites-roadmap.md` rewritten — the previous
  version incorrectly described composites as saved search profiles.
  The note now accurately describes composites as full-text
  concatenations of search results committed to a named `@comp__*`
  file, with SOURCE-CHAIN frontmatter enabling header surfacing on
  future searches.

### Internal
- `haystack--parse-and-tokens` — splits raw input on `" & "` into a
  token list; returns nil for single-term input (no AND).
- `haystack--run-and-query` — executes the AND logic: one
  `--files-with-matches` pass per token to narrow the candidate set,
  then a volume-gated content search of the first token's pattern across
  the surviving files.
- `haystack--build-rg-count-args` — builds `rg --count --with-filename`
  args for the volume gate root search, mirroring
  `haystack--build-rg-args` without the output-formatting flags.
- `haystack--rg-count-xargs-args` — the xargs variant: count args
  without the notes directory, for use in filter-further.
- `haystack--count-output-stats` — parses `rg --count` output
  (`file:N` lines) into a `(files . lines)` cons.
- `haystack--volume-gate` — checks stats from a count run against the
  500-line threshold and calls `yes-or-no-p` if exceeded.

---

## [0.7.0] — 2026-03-25

### Added
- **Demo mode** — `haystack-demo` copies the bundled `demo/notes/`
  corpus into a fresh temporary directory and redirects
  `haystack-notes-directory` there.  Every results buffer header shows
  a `*** DEMO MODE ***` warning banner.  New notes created during the
  demo carry a body label indicating they will be discarded.
  `haystack-demo-stop` kills all demo results buffers and file-visiting
  buffers, deletes the temp directory, and restores the previous
  `haystack-notes-directory`, frecency data, and expansion groups.
- **Bundled demo corpus** (`demo/notes/`) — 84 pre-written notes across
  four topic areas (Emacs, Lisp, PKM, Haystack) in eight file types
  (`.org`, `.md`, `.el`, `.py`, `.js`, `.lua`, `.rb`, `.rs`).
  Includes pre-built `.expansion-groups.el` and
  `.haystack-frecency.el` so frecency, leaf/all toggle, and expansion
  groups are immediately demonstrable.  Orphan notes and synthesis
  candidates are distributed throughout the corpus for realism.
- `demo/README.org` — guided walkthrough covering search, progressive
  filtering, leaf frecency, MOC generation, orphan notes, and
  synthesis candidates.
- `D` binding on `haystack-prefix-map` → `haystack-demo`.

### Bug Fixes
- `haystack-demo-stop` was killing all haystack results buffers, including
  any open against the user's real notes directory.  Fixed by stamping each
  results buffer with `haystack--buffer-notes-dir` at creation time and
  filtering kills to only those matching the demo temp directory.
- The tree view and `haystack--all-haystack-buffers` returned buffers from
  all notes directories.  Now scoped to the active `haystack-notes-directory`
  via the same stamp, so demo and real-notes buffers never mix.

### Internal
- `haystack--buffer-notes-dir` (buffer-local) — the expanded
  `haystack-notes-directory` at buffer creation time; set in
  `haystack--setup-results-buffer`.
- `haystack--all-haystack-buffers` filters on `haystack--buffer-notes-dir`
  matching the current `haystack-notes-directory`.
- `haystack--demo-active`, `haystack--demo-temp-dir`,
  `haystack--demo-saved-state` — demo state variables.
- `haystack--demo-package-dir` — locates the haystack.el directory
  for resolving the bundled `demo/notes/` path.
- `haystack--format-header` injects the demo warning line when
  `haystack--demo-active` is non-nil.

---

## [0.6.0] — 2026-03-25

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
