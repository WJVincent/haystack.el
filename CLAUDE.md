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

## Documentation Hygiene

After completing any feature, update all of the following that apply:

- **`docs/ROADMAP.org`** — flip `TODO → DONE` on the task heading; tick
  any unchecked Definition-of-Done checkboxes; verify the phase DoD is
  fully checked before declaring the phase complete.
- **Docstrings in `haystack.el`** — remove any "not yet implemented"
  or "future work" language from the relevant function's docstring.
- **`CLAUDE.md`** — update quick-reference snippets or notes if the
  implementation changed the calling convention or defaults.
- **`CHANGELOG.md`** — add an entry under the appropriate version.
- **`README.md`** — update the Quick Start table, results-buffer keys
  table, and any relevant prose section for new user-facing commands or
  keybindings.
- **`docs/how-to-think-about-haystack.md`** — update only if the feature
  introduces a new *concept or mental model*, not just a new command.
  Ask the question explicitly before moving on.

Run a quick pass over all six before closing a feature.

---

## Tests

```sh
# Unit + bench (~2s)
emacs --batch -l haystack.el -l test/haystack-test.el --eval '(ert-run-tests-batch-and-exit t)'

# IO suite — runs rg for real against demo corpus (~2s)
emacs --batch -l haystack.el -l test/haystack-io-test.el --eval '(ert-run-tests-batch-and-exit t)'
```

Run the **unit suite after every source edit**. Current count: 487 tests.
Run the **IO suite** when touching search pipelines, frecency, compose, discoverability, or stop words.

Performance ceiling (asserted by `test/haystack-bench.el`):
- 500 ms per operation at 10k lines
- 2 s per operation at 100k lines

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
- **`xargs -0` always**: No conditional branching on file count. One
  code path, no `ARG_MAX` concerns. Filenames are written
  null-separated to a temp file and piped via `xargs -0 rg ARGS <
  FILELIST` in `haystack--xargs-rg`. (`rg --files-from` does not exist
  in ripgrep. `xargs -0` is POSIX-portable; `-r`/`-a` are GNU-only.)
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

;; With xargs (the standard path for filters)
;; haystack--xargs-rg writes filenames null-separated to a temp file and calls:
;;   xargs -0 rg ARGS < FILELIST
;; Use haystack--xargs-rg or haystack--run-rg-for-filelist — do not
;; call rg directly.

;; Negation step 1: get files WITHOUT a match (also via xargs)
;;   xargs -0 rg --files-without-match -i --color never PATTERN < FILELIST
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
        ;; Write filenames null-separated (for xargs -0)
        (with-temp-file tmpfile
          (insert (mapconcat #'identity files "\0")))
        ;; Use tmpfile...
        )
    (delete-file tmpfile)))
```

### Buffer Creation & Local Variables

```elisp
(with-current-buffer (get-buffer-create buf-name)
  ;; Set buffer-local vars
  (setq-local haystack--parent-buffer parent)
  (setq-local haystack--search-descriptor descriptor)
  ;; Stamp with the notes directory so tree/kill ops stay scoped
  (setq-local haystack--buffer-notes-dir (expand-file-name haystack-notes-directory))

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
;; Find all haystack results buffers for the *current* notes directory.
;; haystack--all-haystack-buffers is the canonical function — use it.
;; It filters on haystack--buffer-notes-dir matching haystack-notes-directory,
;; so demo and real-notes buffers never mix in the tree view.
(haystack--all-haystack-buffers)

;; Find children of a given buffer
(seq-filter (lambda (b)
              (with-current-buffer b
                (eq haystack--parent-buffer target-buf)))
            (buffer-list))
```

### Composite Filter

No transient — the project uses prefix args and dedicated commands instead.

```elisp
;; Default: exclude composites (--glob=!@*)
(haystack-run-root-search "rust")

;; C-u prefix: include composites ('all — no glob restriction)
;; Interactively: C-u M-x haystack-run-root-search
(haystack-run-root-search "rust" 'all)

;; Only composites ('only — --glob=@*)
;; Bound to C in the global prefix map
(haystack-search-composites "rust")
```

The `composite-filter` symbol (`'exclude`, `'all`, `'only`) is stored in
`:composite-filter` on the search descriptor and inherited by child buffers.

---

## Ripgrep Patterns

### Standard Search

```sh
rg -n -i --color never --max-count 50 --max-columns 500 "pattern" /path/to/notes
```

`-n` = line numbers (three-field output: `file:line:content`)
`-i` = case insensitive
`--color never` = no ANSI escapes in output
`--max-count 50` = silent per-file clamp; prevents one pathological file flooding results
`--max-columns 500` = drops minified/base64 lines silently

**Do not use `--vimgrep`** — it adds a column field that breaks
parsers.

### Two-Phase Volume Gate

Before running any content search, run `rg --count` first. If the total
exceeds 500 lines, prompt the user before proceeding.

```sh
# Count run — always include --with-filename
rg --count --with-filename -i --color never [--glob flags] "pattern" /path
```

**`--with-filename` is mandatory for count runs.** Without it, rg omits
the filename prefix when only one file matches (outputs `47` instead of
`file.org:47`), which breaks `haystack--count-output-stats`. This applies
to both the direct `call-process` variant and the `xargs` variant.

Sum the per-file counts; if total ≥ 500, call `yes-or-no-p`. Gate only
on content filters — filename filters are already narrowed in Elisp.

### With File Glob

```sh
# User-configured file scope
rg -n -i --color never --glob '*.md' --glob '*.org' "pattern" /path

# Exclude composites (default)
rg -n -i --color never --glob '!@*' "pattern" /path

# Only composites
rg -n -i --color never --glob '@*' "pattern" /path
```

### With xargs (All Filters)

```sh
xargs -0 rg -n -i --color never "pattern" < /tmp/haystack-xxxxx
```

All filenames in the tmpfile are absolute and null-separated.
`xargs -0` is POSIX-portable (GNU, BSD, macOS). The empty-filelist
case is handled in Elisp before the call — `xargs` is never invoked
with an empty input.

### Negation (--files-without-match)

```sh
# Step 1: Get files that do NOT contain the term
xargs -0 rg --files-without-match -i --color never "pattern" < /tmp/haystack-xxxxx
# Output: one filename per line (no line numbers, no content)

# Step 2: Re-run root pattern against the narrowed set
# Write step 1 output (null-separated) to a new tmpfile, then:
xargs -0 rg -n -i --color never "root-pattern" < /tmp/haystack-narrowed
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

Composite existence is checked via `file-exists-p` on the deterministic
filename — no `rg` call needed:

```elisp
;; haystack--find-composite returns the path or nil
(haystack--find-composite descriptor)

;; haystack--composite-filename returns the canonical path regardless of existence
;; → /notes/@comp__rust__async.org
(haystack--composite-filename descriptor)
```

The filename is fully determined by `haystack--canonical-chain-slug`, so
a single `file-exists-p` is sufficient.

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
 :composite-filter 'exclude)
```

Everything derives from this. Buffer names, frecency entries, and
SOURCE-CHAIN strings are computed from it — never the reverse.

---

## Input Prefix Summary

| Prefix | Meaning                              | Composable With |
|--------|--------------------------------------|-----------------|
| `!`    | Negate (filter only)                 | `/`, `=`, `~`   |
| `/`    | Match filename, not content          | `!`, `=`, `~`   |
| `=`    | Suppress expansion                   | `!`, `~`        |
| `~`    | Raw regex (skip escaping)            | `!`, `=`        |

Detection order: strip `!` first, then `=`, then `~`. All three flags
are independent booleans on the filter plist.

---

## Settled Design Decisions

These were decided before implementation began. Do not relitigate them.

- **Minor mode over grep-mode**: Results buffers call `grep-mode` then
  activate `haystack-results-mode`, a `define-minor-mode` layered on
  top. This gives a clean keymap for `haystack-filter-further`,
  `haystack-go-up`, `haystack-yank-moc`, etc. without clobbering
  grep-mode globally. `compile-goto-error` is inherited automatically.

- **Absolute paths in tmpfiles**: All filenames written to tmpfiles are
  absolute. This removes any ambiguity about rg's working directory
  when piped through `xargs -0`.

- **Phase 1 input pipeline is intentionally minimal**: Without expansion
  groups, every single-word term is just `regexp-quote`'d (unless `~`
  prefix). No group lookup, no exclusivity guardrail, no expanded query
  feedback. Leave a clear hook point where expansion slots in during
  Phase 2.

- **Spec uses `pkm-` prefix, code uses `haystack-`**: The design doc
  (`pkm.md`) predates the rename. The translation is mechanical —
  don't rename the spec, just know they map 1:1.

---

## Key Conventions

- **Output format**: Always `filename:line:content` (rg -n). Never
  `--vimgrep`.
- **Filename extraction**: Parse colon-delimited output. Timestamped
  slugs avoid colons in filenames.
- **Header protection**: Header lines get `read-only` text
  property. Filter extraction skips them using the `read-only`
  property as the predicate — never a hardcoded line count. This
  stays correct if a composite-surfacing line is added later.
- **Pretty titles**: `YYYYMMDDHHMMSS-slug.ext` → strip timestamp +
  ext. Fallback: strip ext only.
- **Composite slugs**: `@comp__canonical-chain.ext`. No timestamp. `@`
  prefix for glob filtering.
- **Canonical chain**: Each term → expansion group root → downcase →
  slugify (non-alphanumeric runs → hyphens). Segments joined with `__`.
  AND root terms flattened inline. Negated terms prefixed `not-`;
  filename terms prefixed `fn-`.
