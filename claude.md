# Haystack — Claude Code Reference

## Project Overview

Haystack (formerly PKM.el) is a search-first, filesystem-native
knowledge management package for Emacs. It uses Ripgrep (`rg`) on the
filesystem instead of a database. The core invention is the
**progressive filter tree**: stateful branching search where each
filter spawns a child buffer.

The full specification lives in `pkm.md` (the canonical design
doc). The phased delivery plan lives in `ROADMAP.org`. This file is a
quick-reference for coding — not a restated spec.

### Non-Negotiable Principles

- **grep-mode compatibility**: Every results buffer must produce
  `filename:line:content` output so `compile-goto-error` works.
- **File-level filtering, not line-level**: Filters mean "notes
  containing X", not "lines containing X". Never pipe buffer contents
  through grep.
- **Literal-by-default**: User input goes through `regexp-quote`
  unless `~` prefix or expansion fires.
- **Buffer-local state is canonical**: `haystack--search-descriptor`
  is the source of truth. Buffer names are UI convenience for
  Vertico/Orderless.
- **`--files-from` always**: No conditional branching on file
  count. One code path, no `ARG_MAX` concerns.
- **Warn and degrade**: `condition-case` on data file loads. On
  failure: warn, empty default, continue.

---

## Namespace

All public symbols: `haystack-`
All private symbols: `haystack--`
All buffer-local vars: `haystack--` (set with `make-local-variable`)

---

## Emacs API Quick Reference

### Process Invocation (Ripgrep)

```elisp
;; Synchronous rg call — use for all search operations
(with-temp-buffer
  (let ((exit-code (call-process "rg" nil t nil
                                 "-n" "-i"
                                 "--color" "never"
                                 ;; add more args...
                                 pattern
                                 haystack-notes-directory)))
    (buffer-string)))

;; With --files-from (the standard path for filters)
(call-process "rg" nil t nil
              "-n" "-i" "--color" "never"
              "--files-from" tmpfile
              pattern)

;; Negation step 1: get files WITHOUT a match
(call-process "rg" nil t nil
              "--files-without-match" "-i" "--color" "never"
              "--files-from" tmpfile
              pattern)
```

**Key**: `call-process` is synchronous — it blocks until rg
finishes. This is fine for <10k files on SSD. Do not use
`start-process` or `make-process` — async adds complexity with no
benefit here.

### Temp Files

```elisp
(let ((tmpfile (make-temp-file "haystack-")))
  (unwind-protect
      (progn
        ;; Write filenames, one per line
        (with-temp-file tmpfile
          (dolist (f files)
            (insert f "\n")))
        ;; Use tmpfile...
        )
    (delete-file tmpfile)))

;; Or more simply:
(with-temp-file tmpfile
  (insert (string-join files "\n")))
```

### Buffer Creation & Local Variables

```elisp
(with-current-buffer (get-buffer-create buf-name)
  ;; Set buffer-local vars
  (setq-local haystack--parent-buffer parent)
  (setq-local haystack--search-descriptor descriptor)

  ;; Insert header with read-only property
  (let ((inhibit-read-only t))
    (insert (propertize header-text 'read-only t))
    (insert "\n"))

  ;; Insert rg output
  (insert rg-output)

  ;; Set major mode (grep-mode or a derivative)
  (grep-mode)
  (setq buffer-read-only nil) ;; grep-mode sets this; undo if needed

  (current-buffer))
```

### Read-Only Text Properties

```elisp
;; Make header lines untouchable by wgrep
(propertize line 'read-only t 'front-sticky t 'rear-nonsticky t)

;; To modify read-only text later:
(let ((inhibit-read-only t))
  (delete-region beg end)
  (insert new-text))
```

### completing-read (Frecency, Describe, etc.)

```elisp
;; Basic completing-read — Vertico/Orderless handle the UI
(completing-read "Haystack frecent: " candidates nil t)

;; With annotation function for scores
(let ((table (lambda (string pred action)
               (if (eq action 'metadata)
                   '(metadata (annotation-function . haystack--frecent-annotate))
                 (complete-with-action action candidates string pred)))))
  (completing-read "Haystack frecent: " table nil t))
```

### Hooks

```elisp
;; Define a hook
(defvar haystack-after-create-hook nil
  "Hook run after a note is created via the creation engine.")

;; Run it
(run-hooks 'haystack-after-create-hook)
```

### Defcustom

```elisp (defcustom haystack-notes-directory nil "Root directory for
Haystack notes. Must be set before use."  :type 'directory :group
'haystack)

(defcustom haystack-file-glob nil
  "List of glob patterns for rg --glob. nil means no restriction."
  :type '(repeat string)
  :group 'haystack)

(defcustom haystack-composite-format 'org
  "Filetype for composite notes."
  :type '(choice (const org) (const md) (const txt))
  :group 'haystack)
```

### Data File I/O

```elisp
;; Read a data file safely
(defun haystack--load-data-file (path default)
  "Load an elisp data file at PATH, returning DEFAULT on failure."
  (condition-case err
      (if (file-exists-p path)
          (with-temp-buffer
            (insert-file-contents path)
            (read (current-buffer)))
        default)
    (error
     (message "Haystack: failed to load %s: %s" path (error-message-string err))
     default)))

;; Write a data file
(defun haystack--save-data-file (path data)
  "Write DATA to PATH as readable elisp."
  (with-temp-file path
    (let ((print-level nil)
          (print-length nil))
      (pp data (current-buffer)))))
```

### Timer (Frecency Flush)

```elisp
;; Idle timer — fires after 60 seconds of idle
(defvar haystack--frecency-timer nil)

(defun haystack--setup-frecency-timer ()
  (when haystack--frecency-timer
    (cancel-timer haystack--frecency-timer))
  (setq haystack--frecency-timer
        (run-with-idle-timer 60 t #'haystack--frecency-flush)))

;; Shutdown hook
(add-hook 'kill-emacs-hook #'haystack--frecency-flush)
```

### Finding Buffers (for tree ops)

```elisp
;; Find all haystack results buffers
(seq-filter (lambda (b)
              (with-current-buffer b
                (bound-and-true-p haystack--search-descriptor)))
            (buffer-list))

;; Find children of a given buffer
(seq-filter (lambda (b)
              (with-current-buffer b
                (eq haystack--parent-buffer target-buf)))
            (buffer-list))
```

### Transient (Composite Filter Toggle)

```elisp
;; Phase 2: transient menu for composite filter + all/leaf toggle
(require 'transient)

(transient-define-prefix haystack-menu ()
  "Haystack options."
  ["Composite Filter"
   ("c" "Exclude composites" haystack--set-filter-exclude)
   ("C" "Only composites"    haystack--set-filter-only)
   ("a" "All files"          haystack--set-filter-all)]
  ["Actions"
   ("s" "Search" haystack-run-root-search)
   ("f" "Frecent" haystack-frecent)])
```

---

## Ripgrep Patterns

### Standard Search

```sh
rg -n -i --color never "pattern" /path/to/notes
```

`-n` = line numbers (three-field output: `file:line:content`)  
`-i` = case insensitive  
`--color never` = no ANSI escapes in output

**Do not use `--vimgrep`** — it adds a column field that breaks
parsers.

### With File Glob

```sh
# User-configured file scope
rg -n -i --color never --glob '*.md' --glob '*.org' "pattern" /path

# Exclude composites (default)
rg -n -i --color never --glob '!@*' "pattern" /path

# Only composites
rg -n -i --color never --glob '@*' "pattern" /path
```

### With --files-from (All Filters)

```sh
rg -n -i --color never --files-from /tmp/haystack-xxxxx "pattern"
```

No directory argument when using `--files-from` — the file paths in
the tmpfile are absolute (or relative to cwd).

### Negation (--files-without-match)

```sh
# Step 1: Get files that do NOT contain the term
rg --files-without-match -i --color never --files-from /tmp/haystack-xxxxx "pattern"
# Output: one filename per line (no line numbers, no content)

# Step 2: Re-run root terms against the narrowed set
# Write step 1 output to a new tmpfile, then:
rg -n -i --color never --files-from /tmp/haystack-narrowed "root-pattern"
```

### Expansion Group Alternation

```sh
# After escaping each member: C++ → C\+\+, etc.
rg -n -i --color never "(Programming|Coding|Code|Scripting)" /path
```

The alternation is constructed in Elisp from individually
`regexp-quote`'d members. The `(A|B|C)` is Ripgrep regex, not Emacs
regex.

### Composite Lookup

```sh
# One extra rg per search/filter — scoped to @ files only
rg -l -i --color never "^SOURCE-CHAIN: programming > rust > bevy" --glob '@*' /path
```

`-l` = filenames only (just checking existence).

---

## Data Files

All live in `haystack-notes-directory`:

| File                      | Format                                            | Version Control? | Phase |
|---------------------------|---------------------------------------------------|------------------|-------|
| `.expansion-groups.el`    | Alist: `((root . (syn1 syn2)) ...)`               | Yes              | 2     |
| `.haystack-frecency.el`   | Alist: `(((t1 t2) :count N :last-access TS) ...)` | Optional         | 2     |
| `.haystack-stop-words.el` | List: `("the" "a" "an" ...)`                      | Yes              | 3     |

---

## Buffer Naming

```
*haystack:DEPTH:term1:term2:...*
```

- DEPTH starts at 1 (root)
- Each segment is the raw user input for that level
- Designed for Vertico/Orderless: typing `haystack rust bevy` narrows
  instantly

---

## Search Descriptor Structure

```elisp
(:root-term "coding"
 :root-expanded "(Programming|Coding|Code|Scripting)"
 :root-literal nil
 :root-regex nil
 :filters ((:term "rust" :negated nil :literal nil :regex nil)
           (:term "gamedev" :negated t :literal nil :regex nil))
 :composite-filter exclude)
```

Everything derives from this. Buffer names, frecency entries, and
SOURCE-CHAIN strings are computed from it — never the reverse.

---

## Input Prefix Summary

| Prefix | Meaning                   | Composable With |
|--------|---------------------------|-----------------|
| `!`    | Negate (filter only)      | `=`, `~`        |
| `=`    | Suppress expansion        | `!`, `~`        |
| `~`    | Raw regex (skip escaping) | `!`, `=`        |

Detection order: strip `!` first, then `=`, then `~`. All three flags
are independent booleans on the filter plist.

---

## Key Conventions

- **Output format**: Always `filename:line:content` (rg -n). Never
  `--vimgrep`.
- **Filename extraction**: Parse colon-delimited output. Timestamped
  slugs avoid colons in filenames.
- **Header protection**: Header lines get `read-only` text
  property. Filter extraction skips them via line offset.
- **Pretty titles**: `YYYYMMDDHHMMSS-slug.ext` → strip timestamp +
  ext. Fallback: strip ext only.
- **Composite slugs**: `@comp__canonical-chain.ext`. No timestamp. `@`
  prefix for glob filtering.
- **Canonical chain**: Each term → expansion group root →
  downcase. Joined with `-`.
