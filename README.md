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

## Quick Start

| Key | Command |
|-----------|----------------------------|
| `C-c h s` | Search your notes |
| `C-c h n` | Create a new note |
| `C-c h r` | Search the active region |
| `C-c h y` | Yank a MOC at point |
| `C-c h t` | Show the buffer tree |

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

Every file ends with the sentinel `%%% pkm-end-frontmatter %%%` which
marks where frontmatter ends and note content begins. The sentinel is
written in the file's native comment syntax.

If the notes directory does not exist yet, Haystack will offer to
create it.

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

### Search Region

`haystack-search-region` (`C-c h r`) feeds the active region directly
into a root search.

### Input Modifiers

Prefix your search term to change how it is interpreted:

| Prefix | Meaning | Example |
|--------|----------------------------------------|-------------|
| _(none)_ | Case-insensitive literal search | `rust` |
| `/` | Filename filter — match against the filename only | `/cargo` |
| `=` | Exact literal — suppress future expansion | `=async` |
| `~` | Raw regex — passed directly to ripgrep | `~foo|bar` |
| `!`  | Negate — exclude files containing this term | `!async` |

Modifiers compose: `!/pattern` negates a filename filter; `!~pattern`
negates a regex. Note that `/` filters narrow to files whose **basename**
matches the term, then show content lines matching the root search — you
see content hits, not filenames, so grep-mode navigation and MOC
features all continue to work.

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
| `?`  | Show help |

Results buffers are `grep-mode` compatible. `compile-goto-error`,
`next-error`, and any other tool that speaks grep format work out of
the box.

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

## Customization

| Variable | Default | Description |
|----------|---------|-------------|
| `haystack-notes-directory` | `nil` | Root directory for notes. Must be set. |
| `haystack-default-extension` | `"org"` | Default extension for new notes. |
| `haystack-context-width` | `60` | Characters of context shown around each match. |
| `haystack-file-glob` | `nil` | Restrict searches to files matching these globs (e.g. `("*.org" "*.md")`). |
| `haystack-frontmatter-functions` | _(see source)_ | Alist of extension → frontmatter generator function. |

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
