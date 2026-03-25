# Haystack

A search-first knowledge management package for Emacs.

The premise is simple: notes are plain text files on disk, and finding them is a matter of searching that disk efficiently. Haystack drives [ripgrep](https://github.com/BurntSushi/ripgrep) against your notes directory and presents the results in a navigable buffer. From there you narrow further — each refinement scopes its search to the files already in view and opens a child buffer, building a branching filter tree you can traverse, compare, and kill at will.

No categories, no tags, no upfront organisation required.

## Requirements

- Emacs 28.1+
- [ripgrep](https://github.com/BurntSushi/ripgrep) (`rg`) on your `PATH`

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

The prefix map is intentionally unbound by default — `C-c <letter>` bindings are reserved for users.

## Quick Start

| Key       | Command                    |
|-----------|----------------------------|
| `C-c h s` | Search your notes          |
| `C-c h n` | Create a new note          |
| `C-c h r` | Search the active region   |
| `C-c h y` | Yank a MOC at point        |
| `C-c h t` | Show the buffer tree       |

## Creating Notes

`haystack-new-note` (`C-c h n`) prompts for a slug and optional file extension, then creates a timestamped file:

```
20250324143012-my-note.org
```

Frontmatter is inserted automatically based on the file type:

- **Org:** `#+TITLE:` and `#+DATE:` properties
- **Markdown:** YAML front matter block
- **Code files:** frontmatter in the appropriate comment syntax

Every file ends with the sentinel `%%% pkm-end-frontmatter %%%` which marks where frontmatter ends and note content begins. The sentinel is written in the file's native comment syntax.

If the notes directory does not exist yet, Haystack will offer to create it.

### Supported File Types

Frontmatter is generated for: `org`, `md`, `html`, `js`, `ts`, `tsx`, `rs`, `go`, `c`, `lua`, `py`, `rb`, `el`, `ml`, and more. See `haystack-frontmatter-functions` to add your own.

## Searching

### Root Search

`haystack-run-root-search` (`C-c h s`) prompts for a term and runs ripgrep across your entire notes directory. Results appear in a grep-mode buffer named `*haystack:1:TERM*`.

The header shows the search chain, file count, and match count, plus navigation buttons:

```
;;;;------------------------------------------------------------
;;;;  Haystack
;;;;  root=rust
;;;;  12 files  ·  47 matches
;;;;  [root]  [up]  [down]  [tree]
;;;;------------------------------------------------------------
```

### Search Region

`haystack-search-region` (`C-c h r`) feeds the active region directly into a root search.

### Input Modifiers

Prefix your search term to change how it is interpreted:

| Prefix | Meaning                                | Example     |
|--------|----------------------------------------|-------------|
| _(none)_ | Case-insensitive literal search      | `rust`      |
| `/`    | Filename filter — match against the filename only | `/cargo` |
| `=`    | Exact literal — suppress future expansion | `=async` |
| `~`    | Raw regex — passed directly to ripgrep | `~foo\|bar` |
| `!`    | Negate — exclude files containing this term | `!async` |

Modifiers compose: `!/pattern` negates a filename filter; `!~pattern` negates a regex.

## Progressive Filtering

From any results buffer, press `f` to filter further. You are prompted for a new term, and Haystack scopes the search to only the files currently in view, opening a child buffer:

```
*haystack:1:rust*          ← root
  *haystack:2:rust:/cargo* ← filtered to files whose path contains "cargo"
    *haystack:3:rust:/cargo:!/async* ← excluded files mentioning "async"
```

Each buffer in the tree is independent. You can branch, compare different filters, and navigate freely between them.

## Results Buffer Keys

| Key     | Action                                        |
|---------|-----------------------------------------------|
| `RET`   | Visit file at point (or activate header button) |
| `n`     | Next match (preview in other window)          |
| `p`     | Previous match (preview in other window)      |
| `f`     | Filter further                                |
| `u`     | Go up to parent buffer                        |
| `d`     | Go down to child buffer                       |
| `t`     | Show the buffer tree                          |
| `k`     | Kill this buffer                              |
| `K`     | Kill this buffer and all descendants          |
| `M-k`   | Kill the whole tree (walk to root, then kill) |
| `c`     | Copy MOC to kill ring                         |
| `?`     | Show help                                     |

Results buffers are `grep-mode` compatible. `compile-goto-error`, `next-error`, and any other tool that speaks grep format work out of the box.

## Buffer Tree

`haystack-show-tree` (`t` or `C-c h t`) opens a tree view of all open Haystack buffers:

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

| Key   | Action                          |
|-------|---------------------------------|
| `RET` | Visit buffer and close tree     |
| `n`   | Next item                       |
| `p`   | Previous item                   |
| `M-n` | Next sibling (same depth)       |
| `M-p` | Previous sibling (same depth)   |
| `q`   | Close tree window               |

## MOC Generator

A Map of Content (MOC) is a list of links to your search results — useful for assembling an index note from a set of search hits.

- `c` — copy MOC links to kill ring (deduplicated by file, one link per file)
- `C-c h y` — yank MOC at point in the current buffer

Links are formatted based on the destination file's extension:

| File type | Format |
|-----------|--------|
| Org       | `[[file:path::line][Title]]` |
| Markdown  | `[Title](path#Lline)` |
| Code files | link in the file's comment syntax |
| Other     | `Title — path:line` |

## Customization

| Variable | Default | Description |
|----------|---------|-------------|
| `haystack-notes-directory` | `nil` | Root directory for notes. Must be set. |
| `haystack-default-extension` | `"org"` | Default extension for new notes. |
| `haystack-context-width` | `60` | Characters of context shown around each match. |
| `haystack-file-glob` | `nil` | Restrict searches to files matching these globs (e.g. `("*.org" "*.md")`). |
| `haystack-frontmatter-functions` | _(see source)_ | Alist of extension → frontmatter generator function. |

### Regenerating Frontmatter

`haystack-regenerate-frontmatter` rebuilds the frontmatter block in an existing note, preserving everything after the sentinel.

## Design

**No cognitive overhead.** The friction that kills note-taking habits is rarely the writing — it is the pressure to file things correctly before you can write them. Haystack removes that pressure. Drop notes anywhere in your directory and find them later.

**Plain text.** Notes are ordinary files with no Haystack-specific encoding or database entry. They are readable by every other tool and yours to keep regardless of whether this package exists.

**Composability.** Haystack is a thin layer over ripgrep and standard Emacs buffers. Results buffers are grep-mode compatible — anything that speaks grep works out of the box.
