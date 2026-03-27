# Haystack

A search-first knowledge management package for Emacs.

The premise is simple: notes are plain text files on disk, and finding
them is a matter of searching that disk efficiently. Haystack drives
[ripgrep](https://github.com/BurntSushi/ripgrep) against your notes
directory and presents the results in a navigable buffer. From there
you narrow further — each refinement scopes its search to the files
already in view and opens a child buffer, building a branching filter
tree you can traverse, compare, and kill at will.

No categories, no tags, no upfront organisation required.

## Requirements

- Emacs 28.1+
- [ripgrep](https://github.com/BurntSushi/ripgrep) (`rg`) on your
  `PATH`
- Linux, macOS, or WSL — Unix toolchain required (`xargs`, shell
  process substitution). Native Windows is not supported.

## Installation

Clone the repository and load the file:

```elisp
(add-to-list 'load-path "/path/to/haystack")
(require 'haystack)
```

Or with `use-package`:

```elisp
(use-package haystack
  :load-path "/path/to/haystack")
```

## Setup

Set your notes directory and bind the prefix map:

```elisp
(setq haystack-notes-directory "~/notes")
(global-set-key (kbd "C-c h") haystack-prefix-map)
```

The prefix map is intentionally unbound by default — `C-c <letter>`
bindings are reserved for users.

## Demo Mode

Not sure if Haystack's workflow fits you? Try it on a bundled corpus
before touching your own notes:

```
M-x haystack-demo
```

This copies 84 ai-generated notes into a temporary directory and points
Haystack there. Your real `haystack-notes-directory` is untouched. A
warning banner appears in every results buffer as a reminder. When
you're done:

```
M-x haystack-demo-stop
```

This kills all demo buffers, deletes the temp directory, and restores
your previous configuration.

The corpus spans Emacs, Lisp, PKM, and Haystack topics across eight
file types. It comes with pre-built expansion groups and frecency
history so features like `C-u C-c h f` (leaf/all toggle) and synonym
expansion work immediately. From any results buffer, try `/orphan` or
`/synthesis` as filename filters to find the intentionally isolated
notes and the cross-topic synthesis candidates.

See `demo/README.org` for a guided walkthrough.

## Quick Start

| Key | Command |
|-----------|----------------------------|
| `C-c h s` | Search your notes |
| `C-c h n` | Create a new note |
| `C-c h N` | Create a new note and insert the current results MOC |
| `C-c h r` | Search the active region |
| `C-c h f` | Jump to a frecent search |
| `C-c h y` | Yank a MOC at point |
| `C-c h t` | Show the buffer tree |
| `C-c h w` | Compose a composite note from results |
| `C-c h C` | Search composite notes only |
| `C-c h D` | Start demo mode |

## Creating Notes

`haystack-new-note` (`C-c h n`) prompts for a slug and optional file
extension, then creates a timestamped file:

```
20250324143012-my-note.org
```

Frontmatter is inserted automatically based on the file type:

- **Org:** `#+TITLE:` and `#+DATE:` properties
- **Markdown:** YAML front matter block
- **Code files:** frontmatter in the appropriate comment syntax

Every file ends with the sentinel `%%% haystack-end-frontmatter %%%` which
marks where frontmatter ends and note content begins. The sentinel is
written in the file's native comment syntax.

If the notes directory does not exist yet, Haystack will offer to
create it.

`haystack-new-note-with-moc` (`N` in a results buffer, or `C-c h N`)
combines note creation with MOC insertion in a single step. It prompts
for a slug and extension, creates the note, opens it, and immediately
inserts the current results as formatted links at point — equivalent to
`haystack-new-note` followed by `haystack-yank-moc`, but without leaving
the results buffer in between. The MOC text is also pushed to the kill
ring.

### Supported File Types

Frontmatter is generated for: `org`, `md`, `html`, `js`, `ts`, `tsx`,
`rs`, `go`, `c`, `lua`, `py`, `rb`, `el`, `ml`, and more. See
`haystack-frontmatter-functions` to add your own.

## Searching

### Root Search

`haystack-run-root-search` (`C-c h s`) prompts for a term and runs
ripgrep across your entire notes directory. Results appear in a
grep-mode buffer named `*haystack:1:TERM*`.

The header shows the search chain, file count, and match count, plus
navigation buttons:

```
;;;;------------------------------------------------------------
;;;;  Haystack
;;;;  root=rust
;;;;  12 files  ·  47 matches
;;;;  [root]  [up]  [down]  [tree]
;;;;------------------------------------------------------------
```

### AND Queries

Separate terms with ` & ` (spaces required) to find files containing
all of them:

```
rust & async
rust & async & tokio
```

Haystack runs a file-level intersection — only files matching every
token survive — then shows content matches for the first term. Prefix
modifiers (`=`, `~`) work per token. The `!` prefix is not supported
inside `&` queries; use `filter-further` for negation after the root.

### Search Region

`haystack-search-region` (`C-c h r`) feeds the active region directly
into a root search.

### Input Modifiers

The filter prompt shows the available prefixes:

```
[=]literal  [/]filename  [!]negate  [~]regex
Filter:
```

| Prefix | Meaning | Example |
|--------|----------------------------------------|-------------|
| _(none)_ | Case-insensitive literal (or synonym-expanded) search | `rust` |
| `=` | Exact literal — suppress expansion | `=async` |
| `/` | Filename filter — match path relative to notes directory | `/cargo` |
| `~` | Raw regex — passed directly to ripgrep | `~foo\|bar` |
| `!`  | Negate — exclude files containing this term | `!async` |

Modifiers compose: `!/pattern` negates a filename filter; `!~pattern`
negates a regex. The `/` prefix matches the **full path relative to the
notes directory** (so `/sicp` matches both `sicp-notes.org` and
`sicp-org/README.org`), then shows content lines from the root search —
grep-mode navigation and MOC features all continue to work.

## Progressive Filtering

From any results buffer, press `f` to filter further. You are prompted
for a new term, and Haystack scopes the search to only the files
currently in view, opening a child buffer:

```
*haystack:1:rust*          ← root
  *haystack:2:rust:/cargo* ← filtered to files whose path contains "cargo"
    *haystack:3:rust:/cargo:!/async* ← excluded files mentioning "async"
```

Each buffer in the tree is independent. You can branch, compare
different filters, and navigate freely between them.

## Expansion Groups

Expansion groups are a synonym system for bridging vocabulary gaps
without rewriting your notes. When you associate two terms, any search
for either automatically expands to a ripgrep alternation across all
members of the group. Both single-word and multi-word terms are
supported.

```
;; After (haystack-associate "rust" "rustlang"):
root=(rust|rustlang)   ← shown in the buffer header
```

Groups are stored in `.expansion-groups.el` in your notes directory
and loaded automatically.

### Building Groups

`haystack-associate` links two terms into a group. Run it
interactively or call it from Elisp:

```
M-x haystack-associate RET rust RET rustlang RET
```

Haystack handles all four cases: creating a new group, adding a term to
an existing group, moving a term from one group to another (with
confirmation), or detecting that the terms are already grouped
(no-op).

### Exclusivity Guardrail

If a filter term is already in the root search's expansion group,
Haystack blocks it and suggests the `=` prefix to search literally
instead. This prevents pointless redundant filters.

### Managing Groups

| Command | Description |
|---------|-------------|
| `haystack-associate` | Link two terms into a group |
| `haystack-rename-group-root` | Rename the canonical root term of a group — atomically updates frecency chain keys and renames any affected composite files |
| `haystack-dissolve-group` | Remove an entire group; all members revert to literal matching |
| `haystack-describe-expansion-groups` | Display all groups in a readable buffer |
| `haystack-validate-groups` | Check for duplicate terms across groups |
| `haystack-reload-expansion-groups` | Force-reload groups from disk |

## Results Buffer Keys

| Key | Action |
|---------|-----------------------------------------------|
| `RET` | Visit file at point (or activate header button) |
| `n` | Next match (preview in other window) |
| `p` | Previous match (preview in other window) |
| `f` | Filter further |
| `u` | Go up to parent buffer |
| `d` | Go down to child buffer |
| `t` | Show the buffer tree |
| `k` | Kill this buffer |
| `K` | Kill this buffer and all descendants |
| `M-k` | Kill the whole tree (walk to root, then kill) |
| `c` | Copy MOC to kill ring |
| `N` | Create a new note and insert the current results MOC into it |
| `C-c C-c` | Compose a composite note from this buffer's results |
| `?`  | Show help |

Results buffers are `grep-mode` compatible. `compile-goto-error`,
`next-error`, and any other tool that speaks grep format work out of
the box.

> **Note:** `f` is bound to `haystack-filter-further` in results buffers.
> This shadows `follow-mode` (`follow-mode` is a minor mode normally bound to
> `f` in some configurations).  If you rely on `follow-mode`, rebind
> `haystack-filter-further` in `haystack-results-mode-map`.

## Buffer Tree

`haystack-show-tree` (`t` or `C-c h t`) opens a tree view of all open
Haystack buffers:

```
;;;;------------------------------------------------------------
;;;;  Haystack — buffer tree
;;;;------------------------------------------------------------

  rust
  ├── /cargo  ←
  │   └── !/async
  └── /tokio

;;;;------------------------------------------------------------
```

The current buffer is marked with `←`. Tree navigation:

| Key | Action |
|-------|---------------------------------|
| `RET` | Visit buffer and close tree |
| `n` | Next item |
| `p` | Previous item |
| `M-n` | Next sibling (same depth) |
| `M-p` | Previous sibling (same depth) |
| `q` | Close tree window |

## MOC Generator

A Map of Content (MOC) is a list of links to your search results —
useful for assembling an index note from a set of search hits.

- `c` — copy MOC links to kill ring (deduplicated by file, one link
  per file)
- `C-c h y` — yank MOC at point in the current buffer

The two-step design is intentional: `c` captures the file locations
from the results buffer while you're still looking at them; `C-c h y`
inserts formatted links at point in whatever buffer you navigate to
next. This lets you inspect the list before inserting and respects
cursor position in the target buffer.

Links are formatted based on the destination file's extension:

| File type | Format |
|-----------|--------|
| Org | `[[file:path::line][Title]]` |
| Markdown | `[Title](path#Lline)` |
| Code files | link in the file's comment syntax |
| Other | `Title — path:line` |

### Structured Data Output

Set `haystack-moc-code-style` to `'data` to yank language-appropriate
data structures instead of comment lines when the target buffer is a
code file:

| Language | Output |
|----------|--------|
| JS / TS / JSX / TSX | `const haystack = [{ title, path, line }, ...]` |
| Python | `haystack = [{"title": ..., "path": ..., "line": ...}, ...]` |
| Lisp dialects (Elisp, CL, Scheme, Clojure) | `(defvar haystack '((:title ... :path ... :line ...) ...))` |
| Lua / Fennel | `local haystack = {{ title = ..., path = ..., line = ... }, ...}` |

Each block opens with a comment line containing the full search chain
for reference.

Add support for any language by writing a function that takes `(loci
chain)` and returns a string, then registering it:

```elisp
;; Each locus is a cons cell: (path . line-number)
;; `chain' is a string like "rust > async" for use as a comment header.
;;
;; Example: Ruby array-of-hashes formatter
(defun my-haystack-moc-ruby (loci chain)
  (let ((entries
         (mapcar (lambda (locus)
                   ;; (car locus) → absolute path string
                   ;; (cdr locus) → integer line number
                   (format "  { title: %s, path: %s, line: %d },"
                           (haystack-moc-quote-string
                            ;; haystack--pretty-title strips the
                            ;; timestamp prefix and extension
                            (haystack--pretty-title
                             (file-name-nondirectory (car locus))))
                           (haystack-moc-quote-string (car locus))
                           (cdr locus)))
                 loci)))
    (concat "# haystack: " chain "\n"
            "HAYSTACK = [\n"
            (mapconcat #'identity entries "\n")
            "\n].freeze\n")))

(push '("rb" . my-haystack-moc-ruby) haystack-moc-data-formatters)
```

`haystack-moc-quote-string` produces a double-quoted string literal
with internal quotes escaped — useful whenever the output language uses
`"string"` syntax.

## Composite Notes

A composite note is a machine-generated document that concatenates
excerpts from a set of search results into a single file. It is a
named, replayable snapshot of a search chain — think of it as
committing a retrieval session to disk so you can read, annotate, or
share it later.

### Creating a Composite

From any results buffer, press `C-c C-c` (or `M-x haystack-compose`)
to open a staging buffer. Each source file appears as an org heading
with a link and up to `haystack-composite-max-lines` lines of content
windowed around the first match.

From the staging buffer:

- `C-c C-c` — write the composite to `@comp__CHAIN.org` in your notes
  directory. If the staging buffer has been modified, Haystack also
  prompts you to save the full buffer as a new note.
- `C-c C-k` — discard without saving.

### Composite Files

Composites are named by a canonical slug derived from the search chain:

```
@comp__rust__async.org
@comp__programming__bevy__ecs.org
```

The `@` prefix keeps them out of normal searches by default. They are
plain text files in your notes directory — no special treatment
required.

When a composite exists for the current search chain, a
`[composite: @comp__CHAIN.org]` link appears in the results buffer
header. Clicking it (or pressing `RET` on it) opens the file.

### Composite Filter

By default composites are excluded from all searches. To change this:

| Command | Effect |
|---------|--------|
| `C-u haystack-run-root-search` | Include composites in results |
| `haystack-search-composites` (`C-c h C`) | Search only composite files |

Child buffers inherit the composite filter from their parent.

### Customization

| Variable | Default | Description |
|----------|---------|-------------|
| `haystack-composite-max-lines` | `300` | Max lines of content per source file. `nil` = no limit. |
| `haystack-composite-all-matches` | `nil` | When non-nil, one section per match line rather than per file. |
| `haystack-composite-protect` | `t` | Intercept manual saves and redirect to `haystack-new-note`. |

## Frecency

Haystack records every root search and filter step and scores them by
frecency: `visit_count / max(days_since_last_access, 1)`. Searches you
run often and recently score highest.

### Jumping to a Frecent Search

`haystack-frecent` (`C-c h f`) presents recorded search chains via
`completing-read`, sorted by score. Scores are shown as completion
annotations. Vertico and Orderless work out of the box.

By default only **leaf** entries are shown — chains that are not merely
an intermediate step toward a more-visited deeper search. Use `C-u
haystack-frecent` to show all recorded chains instead.

Selecting an entry replays the full chain internally and surfaces only
the final result buffer — the intermediate steps are never shown. The
replayed buffer stands alone in the tree with no parent.

### Inspecting and Managing Frecency

`haystack-describe-frecent` opens a diagnostic buffer showing all
recorded entries with their score, visit count, and days since last
access:

```
;;;;------------------------------------------------------------
;;;;  Haystack — frecent searches  [sort: score  view: leaf  |  ?=help]
;;;;------------------------------------------------------------

  score     visits  days    chain
  --------  ------  ------  ----
      8.00       8     1.0  rust > async
      3.00       9     3.0  python > django
      1.00       1     1.0  lua
```

| Key | Action |
|-----|--------|
| `s` | Cycle sort order (score → frequency → recency → score) |
| `t` | Sort by score |
| `f` | Sort by frequency (visit count) |
| `r` | Sort by recency (last accessed) |
| `v` | Toggle between all entries and leaf-only view |
| `k` | Kill the entry at point (with confirmation) |
| `?` | Show help |

### Persistence

Frecency data is written to `.haystack-frecency.el` in your notes
directory. By default it is flushed after 60 seconds of idle time and
always on Emacs shutdown. Set `haystack-frecency-save-interval` to `nil`
to write immediately on every buffer visit instead.

## Customization

| Variable | Default | Description |
|----------|---------|-------------|
| `haystack-notes-directory` | `nil` | Root directory for notes. Must be set. |
| `haystack-default-extension` | `"org"` | Default extension for new notes. |
| `haystack-context-width` | `60` | Characters of context shown around each match. |
| `haystack-file-glob` | `nil` | Restrict searches to files matching these globs (e.g. `("*.org" "*.md")`). |
| `haystack-frontmatter-functions` | _(see source)_ | Alist of extension → frontmatter generator function. |
| `haystack-moc-code-style` | `'comment` | MOC output style for code files: `'comment` for per-line links, `'data` for a language-appropriate data structure. |
| `haystack-moc-data-formatters` | _(built-ins)_ | Alist of extension → `(loci chain) → string` formatter. Extend to add new languages. |
| `haystack-frecency-save-interval` | `60` | Idle seconds before flushing frecency data to disk. `nil` writes immediately on every visit. |
| `haystack-composite-max-lines` | `300` | Max lines of content per source file in a composite. `nil` = no limit. |
| `haystack-composite-all-matches` | `nil` | One section per match line rather than per file in composites. |
| `haystack-composite-protect` | `t` | Intercept manual saves in composite buffers and redirect to `haystack-new-note`. |

### Regenerating Frontmatter

`haystack-regenerate-frontmatter` rebuilds the frontmatter block in an
existing note, preserving everything after the sentinel.

## Benchmarks

Numbers below are from the ERT benchmark suite
(`test/haystack-bench.el`), which asserts a 500ms ceiling per
operation. Each test generates synthetic ripgrep output at scale and
times the pure Elisp processing — no disk I/O involved.

Run `./bench.sh` to reproduce. Update this table before tagging a
release or after touching a hot path.

_Last recorded: 2026-03-24 — 13th Gen Intel Core i7-13700KF_

| Benchmark | Time |
|-----------------------------------------------|---------|
| count-search-stats 10k lines | 0.0099s |
| count-search-stats 100k lines | 0.1159s |
| extract-filenames 10k lines | 0.0231s |
| extract-filenames 100k lines | 0.2813s |
| extract-file-loci 10k lines | 0.0249s |
| extract-file-loci 100k lines | 0.3023s |
| strip-notes-prefix 10k lines | 0.0042s |
| strip-notes-prefix 100k lines | 0.0707s |
| truncate-output 10k lines | 0.0230s |
| truncate-output 100k lines | 0.2633s |
| tree-render realistic (~65 bufs) | 0.0013s |
| tree-render stress (~570 bufs) | 0.0577s |

CI runs the same suite on GitHub Actions (ubuntu-latest) as a
regression gate. If the 2s ceiling holds on that hardware it should be
fine most anywhere else.

---

## Design

**No cognitive overhead.** The friction that kills note-taking habits
is rarely the writing — it is the pressure to file things correctly
before you can write them. Haystack removes that pressure. Drop notes
anywhere in your directory and find them later.

**Plain text.** Notes are ordinary files with no Haystack-specific
encoding or database entry. They are readable by every other tool and
yours to keep regardless of whether this package exists.

**Composability.** Haystack is a thin layer over ripgrep and standard
Emacs buffers. Results buffers are grep-mode compatible — anything
that speaks grep works out of the box.

**Emergent structure.** Graph-based PKM systems (Org-roam, Obsidian)
build structure from explicit links you maintain at capture time.
Haystack builds structure from retrieval patterns you develop through
use — frecency surfaces your real access paths, and composites let you
commit a search chain to a named note (think "git commit for
retrieval") so you can replay it instantly. Structure emerges from
what you actually look for, not from a filing system you planned
upfront.

---

## What Haystack Will Never Do
 
Haystack makes hard tradeoffs. If any of the following are
dealbreakers, this is the wrong tool — and that's fine.
 
**Haystack will never build a link graph.**  There are no backlinks,
no graph views, no "show me things I didn't know were connected." If a
note doesn't contain the words you search for, it doesn't
exist. Surprise connections are what link-based tools like Org-roam
and Obsidian are for. Haystack is not competing with them — it is
rejecting their premise.
 
**Haystack will never maintain a database.**  No SQLite, no indexing
service, no background process. The filesystem is the database and
Ripgrep is the query engine. If that stops scaling for your corpus,
Haystack has no fallback. The design ceiling is "what `rg` on an SSD
can do."
 
**Haystack will never manage sync.**  Your notes are files. Move them
with Git, rsync, Syncthing, Dropbox — whatever you already use to move
files between machines. Haystack does not know or care how they got
there. It will never include a sync protocol, conflict resolution, or
cloud integration.
 
**Haystack will never run outside Emacs.**  No mobile app. No web
app. No Electron wrapper. It is an Emacs package that leans hard on
Emacs infrastructure — buffers, hooks, `completing-read`,
`grep-mode`. If you need your PKM on your phone, this isn't it.
 
**Haystack will never support collaboration.**  Single-user,
single-machine. No shared editing, no permissions model, no real-time
presence. The entire design assumes one person's notes on one person's
disk.
 
**Haystack will never fix your vocabulary for you.**  Search-only
systems live and die by the words in your notes. If you write a note
about Bevy ECS patterns but never mention "Entity Component System,"
that note is invisible to broader searches. Haystack provides
diagnostic tools to surface these gaps, but filling them is your
job. The vocabulary burden is the cost of admission and it is never
going away.
 
**Haystack will never infer what you meant.**  There is no fuzzy
matching, no semantic search, no AI-powered "did you mean." Synonym
expansion bridges terminological gaps you've explicitly declared —
nothing more. If you search for "dog" and your note says "canine," you
get nothing unless you've told the system those words are synonyms.
 
**Haystack will never impose a file format.**  No mandatory Org-mode
properties, no required YAML schema, no custom markup
language. Haystack works on any text file Ripgrep can read. It
generates lightweight frontmatter on notes it creates, but it searches
everything in the directory identically — your `.md`, `.org`, `.lua`,
`.c`, and `.txt` files are all first-class citizens.
 
If you read this list and thought "those are all features I need," you
want a different tool. Org-roam, Obsidian, Logseq, and Notion are
excellent at the things Haystack refuses to do. The gap Haystack fills
is narrow and deliberate: fast, stateful, progressive search over a
pile of plain text files, with nothing between you and your notes.
