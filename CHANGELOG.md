# Changelog

All notable changes to Haystack are documented here.  Format loosely
follows [Keep a Changelog](https://keepachangelog.com/).

## [Unreleased]

### Added

- **Notes-directory switcher** — manage a pool of notes directories and
  switch between them at runtime.  New commands:
  `haystack-directory-switch` (`C-c h c`),
  `haystack-directory-add` (`C-c h a`),
  `haystack-directory-remove` (`C-c h X`), and
  `haystack-directory-kill-other-buffers` (`C-c h K`).  The pool is
  persisted to `haystack-directories-file` (default
  `~/.emacs.d/haystack-directories.el`) as a hand-editable list of
  paths; the switcher re-reads the file on every prompt so manual
  edits take effect immediately.  On first use, the pool is seeded
  with `haystack-notes-directory`.  Existing results buffers keep
  their original directory scope after a switch; removing the active
  directory prompts for confirmation and kills its associated buffers
  on approval.  The four commands refuse to run while demo mode is
  active.

---

## [0.18.0] — 2026-04-04

### Fixed

- **Positive filter match count invariant** — `haystack-filter-further`
  now re-runs the root pattern on the narrowed file set for positive
  content filters, matching the behavior of negation and filename
  filters.  Previously, the child buffer displayed filter-pattern
  matches and could exceed the parent's match count.
- **Body-only filter with expansion group** — scoped filters (`>term`)
  now correctly narrow files by the scoped pattern and re-run the root
  pattern.  The chain display includes the scope prefix (`>` / `<`).
- **Demo restart path** — `haystack--demo-package-dir` now uses a
  load-time defconst instead of a runtime `buffer-file-name` fallback,
  fixing the "demo/demo/notes" double-path error on restart.
- **Demo functions not defined after eval-buffer** —
  `haystack--source-directory` now falls back to `buffer-file-name`
  when both `load-file-name` and `locate-library` are nil (i.e. during
  interactive `eval-buffer`).  Previously the `error` call halted
  evaluation, leaving all demo functions undefined.
- **Chain display: scope prefix** — `haystack--format-search-chain`
  now includes `>` / `<` prefix in the current filter's chain segment.
- **Chain display: literal indicator** — literal filters (`=term`) now
  show `=` in the chain display, distinguishing them from non-expanded
  terms (e.g., `exclude==clojure` vs `exclude=foo`).
- **Help menu: conditional mentions entry** — "yank to origin" is now
  only shown in the help popup when the buffer is part of a mentions
  tree (`haystack--mentions-origin` non-nil).
- **Help menu: removed prefix section** — search/filter prefix
  reference removed from the results buffer help popup (already shown
  in the filter prompt).
- **Tree help popup height** — tree buffer help now opens in a side
  window instead of splitting the often-short tree window.
- **Discoverability spacing** — empty tier sections no longer produce
  an extra blank line before the next heading.
- **`haystack-describe-frecent` overwrites in-memory data** — no longer
  unconditionally reloads frecency from disk, which was clobbering
  seeded or in-session data.  Now guarded like `haystack-frecent`.
- **Composite org headings not nested** — org headings inside source
  file content are now demoted by one level so they nest under the
  composite section heading instead of appearing as siblings.

- **Root header: literal prefix missing** — root search header now shows
  `root==term` for literal (`=`) prefix searches.  Previously the `=`
  was omitted (showed `root=term`), even though filter-further displayed
  it correctly.
- **Root header: regex prefix missing** — root search header now shows
  `root=~pattern` for regex (`~`) prefix searches.
- **Tree view: terms colored by type instead of depth** — tree node
  faces now cycle through `haystack-tree-depth-faces` by depth level,
  matching the documented behavior.  Previously used the filter-type
  face (literal, regex, etc.).
- **Frecent picker: not sorted by score** — the `completing-read` table
  now includes `display-sort-function` in its metadata, preserving the
  pre-sorted score order instead of letting the completion UI re-sort
  alphabetically.
- **Pin toggle: cursor jumps to bottom in frecent buffer** —
  `haystack-frecent-toggle-pin` now preserves point on the same entry
  after re-rendering.

### Added

- **Tree kill bindings** — `k` (kill node), `K` (kill subtree), and
  `M-k` (kill whole tree) are now bound in `haystack-tree-mode-map`.
  Each operates on the buffer at point and refreshes the tree display.
- **Pin indicator in results header** — `haystack-pin-current-search`
  (`P`) now adds or removes a `[pinned]` line in the header for
  visual feedback.
- **Results revert** — `g` in results buffers replays the full search
  chain, refreshing results with current corpus state.
- **`haystack-frecent-all`** — new command bound to `C-c h F` that
  opens the frecent picker showing all entries (equivalent to `C-u C-c h f`).

### Changed

- **MOC code style default** — `haystack-moc-code-style` default
  changed from `'comment` to `'data`, so yanking MOC into code files
  produces structured data blocks by default.
- **Describe buffers: theme-aware highlighting** —
  `haystack-describe-expansion-groups` and `haystack--frecent-render`
  now use standard Emacs faces (bold, shadow, font-lock-keyword-face,
  etc.) that inherit from the user's theme.
- **Tree view: clickable items** — tree node terms are now text buttons
  (mouse-1 visits the buffer).
- **Demo corpus** — added `orphan-invented-taxonomy.org` with genuinely
  isolated vocabulary for discoverability demonstrations.

---

## [0.17.0] — 2026-04-02

### Changed

- **Boolean query set operations** — AND, OR, and NOT in grouped queries
  now use hash tables instead of `member` for set intersection, union,
  and difference.  O(N+M) instead of O(N*M).
- **Tokenizer prefix protection** — `~` (regex) and `=` (literal)
  prefixes now protect parentheses as literal characters within the
  term.  `~fn(x)` is tokenized as one term instead of being misrouted
  to the grouped query parser.
- **defcustom types** — `haystack-context-width`,
  `haystack-discoverability-sparse-max`, and
  `haystack-discoverability-ubiquitous-min` now use `natnum` type
  instead of the invalid `(integer :min 1)`.
- **`haystack-search-region`** now delegates to
  `haystack-run-root-search-at-point`, eliminating duplicated
  region-search logic.
- **Volume gate** — extracted `haystack--rg-for-gate` helper; the
  single-term root search path now shares gate logic with the xargs
  path instead of reimplementing it inline.
- **Scope prefix guards** — `haystack-filter-further` now rejects
  scope (`>`/`<`) combined with filename (`/`) prefix.
  `haystack--run-root-search-or` and `haystack--run-root-search-and`
  now reject mixed scope prefixes across tokens.
- **Mentions exclusion** — `haystack--mentions-exclude-origin` now
  matches the path relative to the notes directory instead of just
  the basename, fixing self-mention leaks for notes in subdirectories.

### Fixed

- **View mode state leak** — running the same search twice no longer
  inherits the previous buffer's view mode.
  `haystack--setup-results-buffer` now resets view state on buffer reuse.
- **Frecency lazy-load guard** — `haystack--frecency-record` now uses a
  dedicated `haystack--frecency-loaded` flag instead of checking whether
  `haystack--frecency-data` is nil, preventing redundant disk reads when
  no prior frecency data exists.

### Removed

- Dead struct slot `root` from `haystack-sd` (written but never read).
- Dead function `haystack--multi-word-p` and `:multi-word` plist field
  (computed but never consumed by production code).
- Identity wrapper `haystack--group-all-members` (inlined at 7 call
  sites).
- Test-only helper `haystack--frecent-leaf-p` moved from production
  code to test file.
- Vestigial `root-pattern` parameter from `haystack--filter-by-content`.
- Unreachable default branch from `haystack--format-moc-link`.

---

## [0.16.0] — 2026-04-02

### Changed

- **`D` in results buffers** — now analyzes the file at point instead
  of the current buffer's file.  Extracts the filename from the
  grep-format line and runs discoverability analysis on it.
- **Unicode tokenizer** — discoverability tokenizer now preserves
  non-ASCII alphanumeric characters (Latin diacritics, Cyrillic, etc.)
  instead of discarding them.  Split pattern changed from ASCII
  `[a-zA-Z0-9]` to POSIX `[:alnum:]`.
- **`haystack-after-create-hook`** — changed from `defvar` to
  `defcustom` so it appears in Customize.

### Added

- **Query grouping** (`(A | B) & C`) — recursive-descent parser
  supporting `()` parentheses in search expressions.  Precedence:
  `!` > `&` > `|`.  Enables complex queries like
  `(emacs | lisp) & !(rust | python)`.  File-set operations:
  AND = intersection, OR = union, NOT = complement.
- **Date parser** — `haystack-search-date-range` and
  `haystack-filter-further-by-date` now accept relative offsets
  (`-7d`, `-2w`, `-3m`, `-1y`) and keywords (`today`, `yesterday`,
  `this-week`, `last-week`, `this-month`, `last-month`).  Keywords
  returning a cons fill both bounds; user-extensible via
  `haystack-date-keywords` defcustom.
- **OR operator** (`A | B`) — alternation via single rg call.
  `rust | python` finds files matching either term.  Multi-way OR
  (`A | B | C`) supported.  Precedence: `!` > `&` > `|`.
- **Frecent kill-region** (`K`) — kill all frecency entries in the
  active region for bulk cleanup.  Complements the single-entry `k`.
- **Mentions origin exclusion** — `haystack-find-mentions` and
  `haystack-insert-mentions` now exclude the origin file from results,
  preventing a note from appearing as its own mention.
- **`haystack-prefix-map` autoload** — the prefix keymap now has an
  `;;;###autoload` cookie for proper lazy loading.
- **Frecency dirty flag** preserved across demo mode transitions.
- **Frecency format versioning** — `.haystack-frecency.el` now uses a
  versioned plist wrapper `(:version 1 :entries ...)`.  Bare alists
  from pre-0.16 are auto-migrated on load.  Future format changes
  have a clean migration path via `haystack--frecency-migrate`.

### Fixed

- **View deduplication** — `haystack--view-apply-files` now deduplicates
  by full file path instead of basename, preventing incorrect hiding
  when files in different directories share a name.
- **`haystack-search-composites` interactive spec** — replaced raw `"s"`
  spec with `(list (read-string ...))` for consistency.
- **Demo corpus count** — documentation updated from 84 to 110 notes.
- **`haystack-associate` docstring** — removed stale "Multi-word terms
  are rejected" sentence.

### Removed

- Dead code: `haystack--frecency-key-filter-terms`,
  `haystack--match-highlight-specs` (zero callers).
- Excessive `;;;###autoload` cookies on ~11 non-entry-point functions.

---

## [0.15.0] — 2026-04-01

### Changed

- **Internal: search descriptor is now a `cl-defstruct`** —
  `haystack-sd` replaces the ad-hoc plist.  The auto-generated copier
  eliminates the field-by-field copy sites in `haystack-filter-further`
  and `haystack-filter-further-by-date`, removing a latent bug class
  where adding a descriptor field required updating every copy site.
  No user-visible behavior change; frecency data format is unchanged.
- **Byte-compile clean** — zero warnings from `batch-byte-compile`.
  Fixed forward-reference declarations, wide docstrings, and one
  unused variable.
- **Lazy-load org** — `(require 'org)` replaced with
  `(declare-function org-mode "org")`.  Org is loaded on first use of
  compose or discoverability modes, not at package load time.
- **Ripgrep entry-point guard** — `haystack-run-root-search` and
  friends now check `(executable-find "rg")` and emit a clear
  `user-error` instead of a raw `file-error`.
- **Author header** — updated to MELPA-required `Name <email>` format.

### Added

- **Search scope modes** — `>` prefix searches body only (after the
  frontmatter sentinel), `<` prefix searches frontmatter only (before
  the sentinel).  Composes with all existing prefixes (`!>`, `>=`,
  `>~`, etc.).  Files without a sentinel are treated as all-body.
  Scope is stored in frecency chain keys and replayed correctly.
- **`haystack-new-note-from-region`** (`C-c h x`) — create a new note
  and insert the active region text after frontmatter.
- **Demo corpus rewrite** — expanded from 87 to 110 notes.  Added 15
  deliberately messy files (spaces in filenames, `.txt` without
  frontmatter, non-timestamped slugs, a 150-line brain dump) and 8
  humanistic notes (philosophy, music, literature, etymology, urban
  planning, film, art history, recipes) so non-developer audiences can
  see themselves in the corpus.  Frecency data now ships empty;
  `haystack-demo-seed-frecency` populates a realistic history on
  demand.  New `writing` expansion group spans humanistic notes.
  Fixed conceptual inaccuracies across demo notes: corrected
  descriptions of the tree view, frecency engine, composites,
  progressive filtering, expansion groups, note creation, and
  frontmatter sentinel.  Replaced references to non-existent
  variables and functions with their actual counterparts.
- **Pinned search paths** — frecency entries can be pinned so they
  always appear in `haystack-frecent` completing-read, regardless of
  score decay.  `p` in the frecent buffer toggles pin at point; `P`
  in a results buffer pins or unpins the current search.  Pinned
  entries bypass leaf filtering and sort before non-pinned entries.
  The `*` indicator marks pinned entries in both the frecent buffer
  and completing-read annotations.
- **`haystack-save-mode`** — buffer-local minor mode that runs
  `haystack-save-hook` after saving a note inside
  `haystack-notes-directory`.  No default hook functions yet;
  provides plumbing for future on-save features.

---

## [0.14.0] — 2026-03-30

### Added

- **`haystack-inherit-view-mode`** defcustom — when non-nil, child
  buffers created by `haystack-filter-further` and
  `haystack-filter-further-by-date` inherit the parent's view mode
  instead of starting in Full. Defaults to nil.
- **`haystack-describe-frontmatter-styles`** — introspect registered
  frontmatter comment styles (prefix, suffix, extensions).
- **`haystack-describe-moc-languages`** — introspect registered MOC
  data format languages (comment prefix, extensions).
- **Results view mode toggle** — three-state display toggle for
  results buffers.  `v` cycles Full → Compact → Files → Full.  Compact
  replaces file paths with human-readable titles via overlays.  Files
  shows one deduplicated line per file.  Direct-jump commands:
  `haystack-view-full`, `haystack-view-compact`,
  `haystack-view-files`.  Underlying buffer text is never modified;
  all existing features (filter, MOC, compose, navigation) work
  unchanged in every view mode.

### Fixed

- **README keybinding errors** — timestamp bindings `C-c h i` / `C-c h I`
  were swapped in the Quick Start table; frecency binding was listed as
  `C-c h r` instead of `C-c h f` in the date-range section.
- **Leading-dash search terms** — patterns like `-foo` or `--config` are
  now separated from rg flags with `--`, preventing misinterpretation.
- **Mentions yank-to-origin on deleted files** —
  `haystack-mentions-yank-to-origin` and `haystack-insert-mentions` now
  signal an error if the origin note has been deleted, instead of
  silently recreating it.
- **Group rename drops old root** — `haystack-rename-group-root` now
  preserves the old root as a member so it still expands to the group.
- **Date-filter drops mentions state** —
  `haystack-filter-further-by-date` now propagates
  `haystack--mentions-origin` and renames child buffers to
  `*haystack-ref:`, matching `haystack-filter-further`.
- **`haystack-new-note` missing autoload** — added `;;;###autoload` so
  `M-x haystack-new-note` works in package-managed installations without
  an explicit `(require 'haystack)`.
- **Frecency replay score inflation** — replaying a multi-step chain no
  longer records intermediate steps; only the final leaf is recorded.

---

## [0.13.0] — 2026-03-29

### Added

- **`haystack-search-date-range`** — search notes by `hs:` timestamp
  range.  Prompts for start and end bounds (`YYYY`, `YYYY-MM`,
  `YYYY-MM-DD`, or `YYYY-MM-DD HH:MM`; either end may be blank for an
  open range).  Uses a broad ripgrep prefilter followed by Elisp
  post-filtering; the volume gate runs against the post-filter count.
  Results use standard grep-mode format and `haystack-filter-further`
  composes normally.  Bound to `R` in `haystack-prefix-map`.

- **`haystack-insert-timestamp-now`** — insert an `hs:` active
  timestamp for the current time at point.  `C-u` produces an inactive
  (square-bracket) form.

- **`haystack-insert-timestamp`** — prompt for `YYYY-MM-DD` or
  `YYYY-MM-DD HH:MM` and insert an `hs:` timestamp at the given
  precision.  `C-u` for inactive form.  Bound under the prefix map.

- **`haystack--frecency-key-display`** — converts a descriptor-shaped
  frecency key to a human-readable string.  Used by the
  `*haystack-frecent*` buffer, completing-read UI, and kill-entry
  confirmation prompts.

- **Demo corpus timestamp notes** — three new notes in `demo/notes/`
  covering January, February, and March 2025, each containing multiple
  `hs:` timestamps.  Used by the new IO tests (Tests 27–30).

### Changed

- **Frecency key format** changed from a list of prefixed strings
  (`("rust" "async" "!cargo")`) to a descriptor-shaped plist (`(:root
  (:kind text :term "rust") :filters ((:term "async") (:negated t
  :term "cargo")))`).  Date-range roots use `(:kind date-range :start
  S :end E)`.  `assoc` continues to work via structural `equal`
  comparison.  Existing frecency data on disk written before this
  change will not be replayed correctly.

- **`haystack--frecency-replay`** now dispatches on `:kind` in the
  root plist.  Date-range roots call `haystack-search-date-range`;
  text roots continue on the `haystack-run-root-search` path.

- **`haystack-volume-gate-threshold`** defcustom (default 2000, nil to
  disable).  Replaces the hardcoded 500-line ceiling.  The new default
  is better calibrated to real usage: 1,700 results on the benchmark
  machine felt instant.

- **`haystack-volume-gate-style`** defcustom (`exact` / `fast`,
  default `exact`).  In `fast` mode the count pass uses `rg --count
  --max-count=1` piped through `head -N`, bounding peak memory to the
  threshold line count rather than the full corpus match count.  The
  prompt says "at least N matches" when the output is capped.  `exact`
  preserves the informative "N lines across M files" prompt.

- **`haystack-max-columns`** defcustom (default 500).  Replaces the
  hardcoded `--max-columns=500` rg flag.  Increase for corpora with
  long prose lines; decrease to reduce memory use on very wide
  content.

- **`haystack-tree-help`** command and
  **`haystack--tree-help-content`** — a tree-buffer-specific help
  popup bound to `?` in `haystack-tree-mode-map`.  Previously `?` fell
  through to `special-mode`'s `describe-mode`.  The new popup lists
  the tree buffer's own keybindings (visit, next/prev, siblings, q).

### Changed

- **`haystack--strip-notes-prefix`** rewritten as a single
  `replace-regexp-in-string` call.  Eliminates the intermediate
  `split-string` / `mapconcat` / lambda allocation passes.  At 123k
  matches this reduces allocation from ~227 MB to a single pass with
  no intermediate strings.

- **Search chain header** now renders each term on its own `;;;;`
  line, broken at `>` separators (via `haystack--format-chain-lines`).
  A four-step chain that previously wrapped mid-line at standard frame
  width now reads as a scannable vertical list with indented
  continuation lines.

---

## [0.12.0] — 2026-03-28

### Fixed

- **`haystack--frecency-replay`** no longer crashes when replaying a
  chain whose root term was later added to the stop-word list.  A new
  `haystack--suppress-stop-word` flag bypasses the stop-word prompt
  during replay (DWIM).  The function now wraps the chain in
  `unwind-protect` to clean up intermediate buffers on error.

- **Stop-word prompt `?r` branch** now adds the `=` literal prefix,
  matching the `?s` branch.  Previously, choosing "remove from list"
  on a term that was also an expansion-group root would silently widen
  the search via group expansion.

- **`haystack--rename-composites-atomic`** rollback now runs in
  correct LIFO order.  The `nreverse` call on the `done` list was
  converting the already-LIFO `push`-built list to FIFO, causing
  mid-sequence failures to leave the filesystem in an inconsistent
  state.

- **`haystack-demo`** now uses `copy-tree` instead of `copy-sequence`
  when saving frecency and expansion-group state, preventing nested
  mutations from leaking across the demo boundary.

- **`haystack--run-root-search-filename`** now runs
  `haystack--volume-gate` before returning results, matching the
  behavior of content searches.  Previously, `/filename` root searches
  could produce arbitrarily large result buffers without prompting.

### Docs

- **`demo/README.org`** steps 6 and 7 rewritten to guide users through
  live discoverability and compose features (previously described as
  "not yet implemented").

- **`docs/how-to-think-about-haystack.md`** corrected nonexistent
  command names: `haystack-search` → `haystack-run-root-search`,
  `haystack-filter` → `haystack-filter-further`.

- **`CHANGELOG.md`** merged duplicate `### Added` sections in
  [Unreleased].

### Added

- **`haystack-find-mentions`** (`C-c h m`): opens a results buffer
  showing every note that mentions the current note by its slug
  (literal root search for the slug, suppressing expansion groups).
  The buffer carries `haystack--mentions-origin` (canonical flag) and
  is cosmetically renamed to the `*haystack-ref:` prefix to
  distinguish it in the buffer list.

- **`haystack-insert-mentions`** (`C-c h M`): direct-insert variant —
  runs the same search internally, shows a count prompt ("N mentions
  found. (y)insert (SPC)open buffer (q)abort"), and appends the
  content immediately on `y`/RET.  Opens the full results buffer on
  SPC.  Zero results inserts a boilerplate no-ref comment rather than
  nothing.

- **`haystack-mentions-yank-to-origin`** (`Y` in results buffers):
  appends a file-type separator + formatted MOC links to the origin
  note, then kills the entire mentions tree.  Only active when
  `haystack--mentions-origin` is set.  File-type-aware separator:
  `.org` → `-----`, `.md`/`.markdown` → `---`, `.html`/`.htm` →
  `<hr>`, fallback `----`.  Zero results appends a boilerplate no-ref
  comment.  Child buffers created by `haystack-filter-further` inside
  a mentions tree inherit the origin and the `*haystack-ref:` rename
  automatically.

- IO test suite (`test/haystack-io-test.el`): end-to-end tests running
  real `rg` calls against a temp copy of the demo corpus.  Covers root
  search, expansion groups, AND queries, progressive filter, filename
  filter, negation, frecency replay, compose staging, discoverability,
  stop-word prompts, frecency recording, and filename-prefix root
  search.  Serves as continuous verification that every feature is
  meaningfully demonstrable in the demo corpus.

### Internal

- **MOC language registry**: `haystack--moc-language-registry` stores
  the data representation for each built-in data-style MOC formatter.
  `haystack-define-moc-language` macro generates
  `haystack--moc-data-format-NAME` functions from `(:comment :open
  :entry :separator :close :extensions)` data.  The four built-in
  languages (js, python, elisp, lua) are now macro calls;
  `haystack-moc-data-formatters` and `haystack--format-moc-data-block`
  are unchanged.

- **Frontmatter registry**: `haystack--frontmatter-registry` stores
  the data representation for comment-based frontmatter styles.
  `haystack-define-frontmatter` macro generates
  `haystack--frontmatter-NAME` functions from `(:prefix :suffix
  :extensions)` data.  The seven comment-based styles (slash, hash,
  semi, dash, c-block, html-block, ml-block) are now macro calls; org
  and markdown retain hand-written functions due to unique formats.
  `haystack-frontmatter-functions` and `haystack--frontmatter` are
  unchanged.

- **Dispatcher decomposition**: `haystack-run-root-search` is now a
  thin dispatcher delegating to `haystack--run-root-search-and` (AND
  query path) and `haystack--run-root-search-filename` (/ prefix
  path).  `haystack-filter-further` delegates to
  `haystack--filter-by-content`, `haystack--filter-by-filename`, and
  `haystack--filter-by-negation`.

- **Unified rg arg builder**: `haystack--rg-args` (`cl-defun` with
  keyword args `:count`, `:files-with-matches`,
  `:files-without-match`, `:composite-filter`, `:file-glob`,
  `:pattern`, `:extra-args`) replaces the four separate builders
  (`haystack--rg-base-args`, `haystack--build-rg-args`,
  `haystack--build-rg-count-args`, `haystack--rg-count-xargs-args`).

- **Cached expansion group loading**:
  `haystack--expansion-groups-loaded` flag prevents redundant disk
  reads.  `haystack-reload-expansion-groups` clears it to force a
  re-read.  Demo mode transitions also clear it.
  `haystack--save-expansion-groups` sets it after any write.

- **Empty slug guard**: `haystack-new-note` and
  `haystack-new-note-with-moc` now signal `user-error` when the slug
  sanitizes to an empty string.

- **AND query auto-quoting verified**: `haystack--run-and-query`
  already routes all tokens through `haystack--parse-input` (which
  applies `regexp-quote`); added explicit tests for `C++` and `~C.+`
  patterns.

- **Frecency leaf algorithm**: `haystack--frecent-leaves` replaced
  with an O(N·L) hash-based algorithm (was O(N²)).
  `haystack--frecent-leaf-p` kept as a thin wrapper for backward
  compatibility.

- **Function rename**: `haystack--run-rg-for-filelist` renamed to
  `haystack--search-in-filelist`.

- **Rename-group-root operation order**: composite file renaming now
  happens first (steps: rename composites → update frecency → update
  groups), so a partial failure leaves the group name and composite
  filenames mutually consistent.

### Fixed

- **`haystack--truncate-content`** now passes `:emacs-pattern` (not
  `:pattern`) to `string-match` at all three call sites, and wraps the
  call in `condition-case` for graceful degradation.  Previously, raw
  ripgrep syntax (`(?i:...)`, `\b`, lookaheads) and bare `|`
  alternations caused crashes or silently wrong match
  positions. (CR-1)

- **`haystack--write-filelist`** no longer leaks a temp file when
  `with-temp-file` signals.  The path is now captured inside the same
  `unwind-protect` that deletes it, so a mid-write signal cannot
  strand the file. (CR-2)

- **`haystack-run-root-search`** parses `raw-input` exactly once,
  after the stop-word gate has settled the input.  The previous code
  parsed twice (with a mutation between parses) and the AND path
  parsed a third time at a different site, making the three parse
  results potentially inconsistent. (CR-3)

- **`haystack--ensure-stop-words`** now uses a separate
  `haystack--stop-words-loaded` boolean flag (parallel to
  `haystack--expansion-groups-loaded`) to distinguish an intentionally
  empty list from "not yet loaded".  Previously, an empty
  `haystack--stop-words` would always trigger a re-seed from the
  182-word default list, making a fully cleared stop-words file
  impossible. (MJ-1)

- **`haystack--composite-rename-pairs`** no longer signals
  `wrong-type-argument` for `@comp__` files with no extension.
  `(file-name-extension …)` returning `nil` is now handled
  explicitly. (MJ-2)

- **`haystack-describe-discoverability`** replaced O(N) synchronous
  `rg` process launches (one per unique token) with a single `rg
  --count` pass using an alternation of all tokens.  A 400-token note
  now runs one subprocess instead of 400. (MJ-4)

- **`haystack-frecent`** now checks `haystack--stop-words-loaded`
  before reloading from disk, matching the pattern of
  `haystack--frecency-ensure`.  Previously, calling `haystack-frecent`
  after a search but before the idle-timer flush discarded the
  just-recorded in-memory entry. (MJ-10)

- **`haystack-demo-stop`** now deletes the temp directory before
  restoring state.  Previously, a `delete-directory` failure left
  `haystack--demo-active` nil while stranding the directory
  permanently (subsequent `haystack-demo-stop` calls would immediately
  error "demo is not running"). (MJ-12)

- **Volume gate** is now consistent between the AND path and the
  single-term path.  The AND path previously counted results after
  intersection; the single-term path counted the full directory, so
  the gate could silently fail to fire on large AND result
  sets. (MN-9)

- **`haystack-compose-commit`** and
  **`haystack--compose-intercept-save`** now `with-current-buffer`
  explicitly when inserting MOC content into the new note buffer,
  instead of relying on `haystack-new-note` leaving it current as a
  side effect. (MN-12)

- **`haystack-discoverability-mode`** now kills the old
  discoverability buffer only after the new one is fully populated,
  eliminating the window-shows-nothing gap during analysis. (MN-19)

- **`haystack-go-root`** final `switch-to-buffer` is now guarded: if
  the root buffer was killed without its descendants, the switch is
  skipped rather than signaling an error. (NP-4)

- **`boundp` on `defvar-local` variables** replaced with
  `bound-and-true-p` throughout (`haystack--assert-results-buffer`,
  `haystack-filter-further`, `haystack-compose`,
  `haystack-mentions-yank-to-origin`).  `defvar-local` always binds
  the symbol, so the plain `boundp` check was vacuously true and
  masked unset variables. (NP-5)

### Internal

- **`(require 'org)`** moved to the top-level require block.  It was
  previously inside `haystack-compose`, but `define-derived-mode
  haystack-compose-mode org-mode` runs at load time and fails if `org`
  has not loaded yet. (MJ-5)

- **`haystack-results-mode-map`** converted to the idiomatic `(let
  ((map (make-sparse-keymap))) … map)` form, consistent with every
  other keymap in the file. (MJ-6)

- **`haystack--create-note-file`** helper extracted, de-duplicating
  the slug-prompt → sanitize → extension-prompt → write → open flow
  that was copy-pasted between `haystack-new-note` and
  `haystack-new-note-with-moc`. (MJ-7)

- **`haystack--append-to-origin-file`** helper extracted,
  de-duplicating the get-ext → get-separator → format → open-file →
  insert → save flow shared by `haystack-insert-mentions` and
  `haystack-mentions-yank-to-origin`. (MJ-8)

- **`haystack--descriptor-leaf-label`** helper extracted, replacing
  three independent copies of "use last filter if filters non-nil,
  else use root fields, apply `haystack--tree-term-label`". (MJ-9)

- **`haystack--rg-args`** no longer accumulates via repeated `(setq
  args (append args (list item)))`.  Sections are now built as `(list
  …)`  and merged with a single `append` at the end. (MN-13)

- **`haystack--sanitize-slug`** rewritten with `thread-last` instead
  of a `let*` chain with repeated `s` rebindings. (MN-14)

- **`haystack--validate-notes-directory`** helper extracted, removing
  the duplicated preamble shared by `haystack--assert-notes-directory`
  and `haystack--ensure-notes-directory`. (MN-15)

- **`haystack--discoverability-render`** now partitions entries in a
  single `dolist` pass, calling `haystack--discoverability-tier` once
  per entry instead of four `seq-filter` passes. (MN-16)

- **`haystack--extract-filenames`** now delegates to `(mapcar #'car
  (haystack--extract-file-loci text))`, removing a near-duplicate
  implementation. (MN-17)

- Dead `first-term` fallback branch in `root-term-str` inside
  `haystack--run-root-search-and` removed; `(cdr and-tokens)` is
  always non-nil by precondition. (NP-1)

- **`haystack--show-help-buffer`** helper extracted, removing the
  three-copy `get-buffer-create` → `erase` → `insert` → `special-mode`
  → `goto-min` → `display-buffer` pattern. (NP-2)

- Demo state variables (`haystack--demo-active` etc.) moved to the
  demo section of the file. (NP-3)

### Docs

- Comment added to `haystack--comment-prefixes` and
  `haystack-frontmatter-functions` explaining the intentional
  divergence for `c`/`h` files (line comments vs. block-comment
  frontmatter) and noting the extensions present in only one
  registry. (MJ-3)

- `;;;###autoload` cookie removed from `haystack--format-moc-text`; it
  is a private helper with no `interactive` form. (MJ-11)

- Stale "Phase 2; currently falls back" language removed from
  `haystack-moc-code-style` docstring; the `data` style is fully
  implemented. (MN-1)

- Error message in `haystack-mentions-yank-to-origin` rewritten to not
  expose the internal variable name: "This command is only available
  in a mentions results buffer — run `haystack-find-mentions'
  first". (MN-2)

- Integer defcustoms `haystack-context-width`,
  `haystack-composite-max-lines`,
  `haystack-discoverability-sparse-max`, and
  `haystack-discoverability-ubiquitous-min` now use `(integer :min 1)`
  in their `:type` spec, rejecting zero and negative values. (MN-3)

- `haystack--discoverability-search-at-point` and
  `haystack--discoverability-add-stop-word` wrapped in thin public
  commands so they appear in `C-h m` under public names. (MN-4)

- **`haystack-yank-moc`** given `;;;###autoload` cookie; it is bound
  in the global prefix map and must be resolvable before any other
  haystack command fires. (MN-5)

- Magic literal `7` for `(length "@comp__")` replaced with `(length
  haystack--composite-prefix)`. (MN-6)

- `haystack--group-all-members` docstring corrected: the claim about
  what the function replaces was misleading. (MN-7)

- `haystack--frecent-leaf-p` docstring updated to document its
  test-only status and clarify "backward compatibility wrapper" is for
  tests, not production callers. (MN-8)

- `haystack--discoverability-tokenize` precondition documented:
  callers must invoke `haystack--ensure-stop-words` before calling
  this function directly. (MN-10)

- **`haystack-tree-depth-faces`** converted from `defvar` to
  `defcustom`. (MN-11)

- Discoverability analysis now emits a "done" completion message after
  the progress loop. (MN-18)

- `haystack-search-region` docstring documents that prefix characters
  (`!`, `~`, `/`, `=`) at the start of selected text are interpreted
  as search modifiers. (NP-6)

- Package `Author:` header updated to a proper `Name <email>` form;
  `Keywords:` updated to use registered Emacs keyword terms. (NP-7)

- `haystack-run-root-search` prompt updated to include an inline hint
  for AND queries and prefix modifiers, matching
  `haystack-filter-further`. (NP-8)

- Comment added to the registry accumulation sites
  (`haystack--frontmatter-registry`,
  `haystack--moc-language-registry`) documenting that top-level macro
  calls update in place via `setf (alist-get …)` and that file reloads
  accumulate correctly. (NP-9)

- Comment added to the frecency score formula documenting that
  `count/days` is a deliberate "recency-weighted count" choice rather
  than exponential decay. (NP-10)

---

## [0.11.0] — 2026-03-27

### Added
- `haystack-describe-discoverability` (`C-c h d`, `D` in results
  buffers): analyzes term discoverability for the current note.
  Tokenizes the buffer, strips stop words, counts how many notes each
  term appears in, and renders the results as a four-tier org-mode
  buffer:
  - **Isolated** (0 files) — potential orphan concepts not linked to
    the corpus
  - **Sparse** (1–`haystack-discoverability-sparse-max` files) —
    specific / niche
  - **Connected** — moderate presence; well-integrated with the corpus
  - **Ubiquitous** (`haystack-discoverability-ubiquitous-min`+ files)
    — consider adding to stop words

  Keybindings in the discoverability buffer: `RET` launches a haystack
  search for the term at point; `a` adds the term at point to stop
  words; `q` closes.  Three new defcustoms:
  `haystack-discoverability-sparse-max` (default 3),
  `haystack-discoverability-ubiquitous-min` (default 500),
  `haystack-discoverability-split-compound-words` (default nil —
  hyphens and underscores treated as word characters).  Gated to
  file-backed buffers inside `haystack-notes-directory`.
- Performance benchmarks for `haystack--discoverability-tokenize` (10k
  and 100k-word notes) and `haystack--discoverability-render` (1k and
  10k terms) added to `test/haystack-bench.el`.
- `haystack-run-root-search-at-point` (`C-c h .`, `.` in results
  buffers): searches the word under the cursor without prompting.
  Hyphens and underscores are treated as word characters, so
  `bevy-ecs` and `my_note` are captured whole.  Falls back to the
  active region when one exists.
- `haystack--word-at-point`: internal helper for word extraction.
- Stop word infrastructure: `.haystack-stop-words.el` in the notes
  directory, auto-seeded from the NLTK English stop words corpus (182
  words) on first use.
  - `haystack-add-stop-word` / `haystack-remove-stop-word` /
    `haystack-describe-stop-words` for list management.
  - Single-word root searches and filter-further queries against a
    stop word now prompt: `[s]earch anyway` (literal), `[r]emove from
    list`, `[q]uit`.  Multi-word terms and `=`-prefixed inputs are
    never blocked.

---

## [0.10.0] — 2026-03-27

### Fixed
- `haystack--frecency-replay` now explicitly loads expansion groups
  before replaying.  Previously they were loaded as a side effect of
  `haystack-run-root-search`, which made replay work only by accident.
- `haystack--frecency-replay` no longer uses `cl-letf` to silence
  `pop-to-buffer`/`switch-to-buffer`.  Instead a
  `haystack--suppress-display` dynamic variable is checked at the
  three display call sites in `haystack-run-root-search` and
  `haystack-filter-further`.  This is cleaner and does not globally
  rebind core Emacs functions during replay.
- Frecency timer and `kill-emacs-hook` are now deferred to first
  interactive use via `haystack--frecency-ensure`.  Previously
  `(require 'haystack)` unconditionally installed an idle timer and a
  shutdown hook, violating the Emacs packaging norm that loading a
  library should not produce side effects.
  `haystack--frecency-ensure` is called at the top of
  `haystack-run-root-search`, `haystack-filter-further`, and
  `haystack-frecent`; customizing `haystack-frecency-save-interval`
  before first use also counts as initialization so the timer is never
  double-installed.

### Removed
- `haystack-composite-extension` defcustom removed.  Composite files
  are always org-formatted (the staging buffer derives from `org-mode`
  and uses org headings, links, and `#+` properties), so a
  configurable extension was misleading.  The extension is now
  hardcoded to `"org"`.

### Added
- `haystack-new-note-with-moc`: combo command — creates a new note and
  inserts the current results buffer as a MOC in one step.  Bound to
  `N` in both `haystack-results-mode-map` and `haystack-prefix-map`.
- `haystack--format-moc-text`: internal helper consolidating MOC
  formatting logic; `haystack-yank-moc` now delegates to it.
- `haystack--suppress-display` dynamic variable: allows internal
  callers (currently `haystack--frecency-replay`) to suppress window
  display without globally redefining `pop-to-buffer` or
  `switch-to-buffer`.
- `haystack--display-term-max-length` and
  `haystack--display-term-context` named constants for the 30/13
  truncation thresholds in `haystack--display-term`.
- `haystack-notes-directory` defcustom type now uses `(choice (const
  :tag "Not set" nil) directory)` so the Customize UI correctly
  represents the unset state.
- `haystack-tree-mode-map` and `haystack-frecent-mode-map` are now
  defined as `defvar` + `make-sparse-keymap` blocks before their
  `define-derived-mode` calls, matching the pattern used by
  `haystack-results-mode-map` and `haystack-compose-mode-map`.
- Demo corpus copy uses `copy-directory` (Elisp built-in) instead of
  `call-process "cp"`.  Removes the GNU coreutils trailing-dot
  convention dependency and works on any platform Emacs supports.

- All rg argument builders (`haystack--rg-base-args`,
  `haystack--build-rg-args`, `haystack--build-rg-count-args`,
  `haystack--rg-count-xargs-args`, `haystack--files-for-root-search`,
  AND query builder) replaced `nconc` with `append`.  The lists were
  always freshly built each call so the mutation was safe, but
  `append` makes the absence of shared state explicit.

### Fixed
- Results buffer `?` help menu: added missing `RET` (visit file /
  activate button), `N` (new note + insert MOC), and a new Composite
  section with `C-c C-c` (compose composite note).  All bound commands
  in `haystack-results-mode-map` are now represented.
- Help buffer now adapts to window width: two-column layout at 100+
  columns (Navigation/Filter/Tree left, MOC/Composite right) roughly
  halves the required height; single-column layout below 100 columns.
  Keys are highlighted with `font-lock-constant-face`, section headers
  with `font-lock-keyword-face`, and rule lines with `shadow` — all
  resolved from the active color theme.

### Docs
- `README.md`: added AND queries section, Composite Notes section,
  updated quick-start table (`C-c h w`, `C-c h C`), results buffer
  keys (`C-c C-c`), customization table (composite defcustoms), and
  noted atomic behaviour of `haystack-rename-group-root`.
- `docs/how-to-think-about-haystack.md`: "The Three Things" expanded
  to four — composite notes added.
- `CLAUDE.md`: renamed from `claude.md`; updated composite filter
  section (prefix arg / dedicated command, no transient), composite
  lookup (file-exists-p, not rg -l), `haystack-composite-extension`
  defcustom name, `:composite-filter` quoting, canonical chain slug
  description.

---

## [0.9.0] — 2026-03-26

### Added
- `haystack-rename-group-root` now performs a fully atomic update
  across three subsystems when a root term is renamed:
  1. **Expansion groups** — root key updated in `.expansion-groups.el`
  2. **Frecency data** — all chain keys containing the old root term
     are rewritten in memory; data is flushed to
     `.haystack-frecency.el`.  When the rename would produce a
     duplicate key, entries are merged (counts summed, latest
     timestamp kept).
  3. **Composite files** — `@comp__*.ext` files whose slug contains
     the old canonical slug segment are renamed atomically; on failure
     any already-completed renames are rolled back.  The success
     message reports how many composites were renamed.
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
  staging buffers.  `C-c C-c` → `haystack-compose-commit`; `C-c C-k` →
  `haystack-compose-discard`.  When `haystack-composite-protect` is
  non-nil, `write-contents-functions` intercepts manual saves and
  redirects to the new-note flow.
- `haystack-compose-commit` — always regenerates the composite cleanly
  from the stored loci and writes it to `@comp__CHAIN.ext`.  If the
  staging buffer was modified, prompts to save the full buffer as a
  new note via `haystack-new-note`.
- `haystack-compose-discard` — kills the staging buffer without
  writing.
- `haystack-compose` — interactive command; builds a
  `*haystack-compose:CHAIN*` staging buffer in `haystack-compose-mode`
  from the current results buffer.  Each source file becomes an org
  heading with a link; content is windowed per
  `haystack-composite-max-lines`.  Bound to `C-c C-c` in results
  buffers and `w` in the global prefix map.
- Composite surfacing in results buffer headers — when a composite
  file exists for the current search chain, a `[composite:
  @comp__CHAIN.ext]` link line is shown in the header.  The link is a
  clickable button that visits the composite file via `find-file`.

### Internal
- `haystack--frecency-rewrite-term` — rewrites one frecency chain key
  list, replacing OLD-ROOT with NEW-ROOT while preserving any prefix
  characters.
- `haystack--frecency-rename-in-data` — applies the rewrite across a
  full frecency alist; merges colliding entries on duplicate keys.
- `haystack--composite-rename-pairs` — scans
  `haystack-notes-directory` for `@comp__*.ext` files and returns
  `(old-path . new-path)` pairs for those whose `__`-delimited slug
  contains the old canonical slug segment.
- `haystack--rename-composites-atomic` — executes a list of rename
  pairs; rolls back completed renames if any step fails.
- `haystack--extract-all-file-loci` — like
  `haystack--extract-file-loci` but returns all `(PATH . LINE)` pairs
  without deduplication, for use with
  `haystack-composite-all-matches`.
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
  runs → hyphens).  Negated terms gain a `not-` prefix; filename terms
  gain `fn-`.
- `haystack--canonical-chain-slug` — builds the full canonical slug
  for a search descriptor by flattening root (expanding AND
  sub-terms), then filter terms, joined with `__`.  Equivalent AND and
  sequential filter chains produce the same slug.
- `haystack--format-header` — gained optional `composite-path`
  argument; when non-nil, a `[composite: FILENAME]` line is inserted
  before the closing rule.
- `haystack--apply-header-buttons` — gained optional `composite-path`
  argument; when non-nil, wires the composite filename as a
  `find-file` button.
- `haystack--setup-results-buffer` — gained optional `composite-path`
  argument; threads it through to `haystack--apply-header-buttons`.

---

## [0.8.0] — 2026-03-26

### Added
- **AND queries** — a root search of `rust & async` (spaces around `&`
  required) finds files containing all terms and returns matches for
  the first term in that intersection.  Any number of terms may be
  combined: `rust & async & tokio`.  Prefix modifiers (`=`, `~`) work
  per token.  The volume gate runs on the intersection file set (not
  the first term alone) so it only fires when the final result would
  be large.  `!`  negation is not supported inside `&` queries — use
  `filter-further` after the AND search instead.  AND chains are
  recorded by frecency and replay correctly.
- **Two-phase volume gate** — before running a root search or content
  filter, haystack runs `rg --count` first and prompts `"N lines
  across M files — run anyway?"` if the total meets or exceeds 500
  lines.  The gate is skipped for filename filters (already narrowed
  in Elisp) and negation filters.  Users who want the large result set
  can confirm and proceed; the prompt is the natural point to refine
  with `=` or `/` prefixes instead.
- `--max-count=50` added to `haystack--rg-base-args` — silently clamps
  per-file output to 50 lines.  Invisible in normal usage; prevents a
  single pathological file from flooding the results buffer.
- `--max-columns=500` added to `haystack--rg-base-args` — drops lines
  wider than 500 characters.  Prevents minified JS and base64 blobs
  from producing unreadable grep lines.

### Changed
- **Sentinel renamed** — `%%% pkm-end-frontmatter %%%` is now `%%%
  haystack-end-frontmatter %%%` across all frontmatter generators, the
  `haystack--sentinel-string` constant, tests, demo corpus, and
  documentation.  Existing notes with the old sentinel will not be
  recognised by `haystack-regenerate-frontmatter` — a one-time `sed`
  pass over your notes directory is needed: `sed -i
  's/pkm-end-frontmatter/haystack-end-frontmatter/g' notes/**/*`

### Documentation
- README Requirements section now states the Unix toolchain
  requirement explicitly: Linux, macOS, or WSL.  Native Windows is
  unsupported.
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
  then a volume-gated content search of the first token's pattern
  across the surviving files.
- `haystack--build-rg-count-args` — builds `rg --count
  --with-filename` args for the volume gate root search, mirroring
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
  `haystack-demo-stop` kills all demo results buffers and
  file-visiting buffers, deletes the temp directory, and restores the
  previous `haystack-notes-directory`, frecency data, and expansion
  groups.
- **Bundled demo corpus** (`demo/notes/`) — 84 pre-written notes
  across four topic areas (Emacs, Lisp, PKM, Haystack) in eight file
  types (`.org`, `.md`, `.el`, `.py`, `.js`, `.lua`, `.rb`, `.rs`).
  Includes pre-built `.expansion-groups.el` and
  `.haystack-frecency.el` so frecency, leaf/all toggle, and expansion
  groups are immediately demonstrable.  Orphan notes and synthesis
  candidates are distributed throughout the corpus for realism.
- `demo/README.org` — guided walkthrough covering search, progressive
  filtering, leaf frecency, MOC generation, orphan notes, and
  synthesis candidates.
- `D` binding on `haystack-prefix-map` → `haystack-demo`.

### Bug Fixes
- `haystack-demo-stop` was killing all haystack results buffers,
  including any open against the user's real notes directory.  Fixed
  by stamping each results buffer with `haystack--buffer-notes-dir` at
  creation time and filtering kills to only those matching the demo
  temp directory.
- The tree view and `haystack--all-haystack-buffers` returned buffers
  from all notes directories.  Now scoped to the active
  `haystack-notes-directory` via the same stamp, so demo and
  real-notes buffers never mix.

### Internal
- `haystack--buffer-notes-dir` (buffer-local) — the expanded
  `haystack-notes-directory` at buffer creation time; set in
  `haystack--setup-results-buffer`.
- `haystack--all-haystack-buffers` filters on
  `haystack--buffer-notes-dir` matching the current
  `haystack-notes-directory`.
- `haystack--demo-active`, `haystack--demo-temp-dir`,
  `haystack--demo-saved-state` — demo state variables.
- `haystack--demo-package-dir` — locates the haystack.el directory for
  resolving the bundled `demo/notes/` path.
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
    flushing to disk (default 60). Set to `nil` to write immediately
    on every buffer visit. Always flushed on Emacs shutdown.

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
  buffer; `haystack--frecent-render` and
  `haystack--frecent-sort-entries` are the rendering primitives.

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

---

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
