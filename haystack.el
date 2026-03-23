;;; haystack.el --- Search-first knowledge management -*- lexical-binding: t -*-

;; Author: wv
;; Version: 0.1.0
;; Package-Requires: ((emacs "28.1"))
;; Keywords: tools, notes, search
;; URL: https://github.com/WJVincent/haystack.el

;;; Commentary:

;; Haystack is a minimalist, retrieval-focused knowledge management
;; package for Emacs.
;;
;; The premise is simple: notes are plain text files on disk, and
;; finding them is a matter of searching that disk efficiently.
;; Haystack drives ripgrep against your notes directory and presents
;; the results in a navigable buffer.
;;
;; From there you narrow further — each refinement scopes its search
;; to the files already in view and opens a child buffer, building a
;; branching filter tree you can traverse, compare, and kill at will.
;; No categories, no tags, no upfront organisation required.
;;

;;; Design Principles:
;;
;; * No cognitive overhead :: The friction that kills note-taking
;;   habits is rarely the writing — it is the pressure to file things
;;   correctly before you can write them.  Haystack removes that
;;   pressure entirely.  Drop notes anywhere in your directory and
;;   find them later via powerful search tools, like being able to
;;   find a needle in a Haystack.
;;
;; * Plain text :: Notes are ordinary files.  They carry no
;;   Haystack-specific encoding, metadata format, or database entry.
;;   They are readable by every other tool, ingestible by any other
;;   system, and yours to keep regardless of whether this package
;;   exists.
;;
;; * Composability :: Haystack is a thin layer over ripgrep and
;;   standard Emacs buffers.  Results buffers are grep-mode
;;   compatible, anything that speaks grep works out of the box.  The
;;   package does not try to own your workflow — it fits into the one
;;   you already have.
;;
;; Entry points:
;;   `haystack-run-root-search'  — search the notes directory
;;   `haystack-new-note'         — create a timestamped note

;;; Code:

(require 'grep)

;;;; Customization

(defgroup haystack nil
  "Search-first knowledge management."
  :group 'tools
  :prefix "haystack-")

(defcustom haystack-notes-directory nil
  "Root directory for Haystack notes.  Must be set before use."
  :type 'directory
  :group 'haystack)

(defcustom haystack-default-extension "org"
  "Default file extension for new notes created with `haystack-new-note'.
Must be a string without a leading dot (e.g. \"org\", \"md\", \"txt\")."
  :type 'string
  :group 'haystack)

(defcustom haystack-file-glob nil
  "Restrict searches to files matching these glob patterns.
Each entry is passed as a separate --glob argument to ripgrep, limiting
which files in `haystack-notes-directory' are searched.  Useful when your
notes directory contains mixed file types and you only want to search a
subset (e.g. Markdown and Org files but not plain text or code).

nil means search all files (no restriction).
Example: (\"*.md\" \"*.org\")"
  :type '(repeat string)
  :group 'haystack)

;;;; Buffer-local variables

(defvar-local haystack--parent-buffer nil
  "The haystack results buffer that spawned this one, or nil for roots.")

(defvar-local haystack--search-descriptor nil
  "Plist describing the full search chain for this buffer.

Structure:
  (:root-term       STRING   — raw user input for root search
   :root-expanded   STRING   — regex sent to rg (may be alternation)
   :root-literal    BOOL     — = prefix: suppress expansion
   :root-regex      BOOL     — ~ prefix: skip regexp-quote
   :filters         LIST     — ordered list of filter plists
   :composite-filter SYMBOL  — \\='exclude | \\='only | \\='all)

Each filter plist:
  (:term     STRING
   :negated  BOOL
   :literal  BOOL
   :regex    BOOL)")

;;;; Hooks

(defvar haystack-after-create-hook nil
  "Hook run after a note is created via `haystack-new-note'.")

;;;; Internal utilities

(defun haystack--assert-notes-directory ()
  "Signal an error if `haystack-notes-directory' is unset or missing."
  (unless haystack-notes-directory
    (user-error "Haystack: `haystack-notes-directory' is not set"))
  (unless (file-directory-p haystack-notes-directory)
    (user-error "Haystack: notes directory does not exist: %s"
                haystack-notes-directory)))

(defun haystack--ensure-notes-directory ()
  "Ensure `haystack-notes-directory' is set and exists.
If the directory is missing, offer to create it.  Signals a
`user-error' if unset or if the user declines to create it."
  (unless haystack-notes-directory
    (user-error "Haystack: `haystack-notes-directory' is not set"))
  (unless (file-directory-p haystack-notes-directory)
    (if (y-or-n-p (format "Directory %s does not exist.  Create it? "
                          haystack-notes-directory))
        (make-directory haystack-notes-directory t)
      (user-error "Haystack: notes directory does not exist: %s"
                  haystack-notes-directory))))

;;;; Creation engine

;;; Frontmatter generators — one function per comment type.
;;; Each takes TITLE (string) and returns a complete frontmatter block
;;; including the pkm-end-frontmatter sentinel on the final line.

(defun haystack--frontmatter-org (title)
  "Return Org-mode frontmatter for TITLE."
  (concat "#+TITLE: " title "\n"
          "#+DATE: " (format-time-string "%Y-%m-%d") "\n"
          "# %%% pkm-end-frontmatter %%%\n\n"))

(defun haystack--frontmatter-md (title)
  "Return Markdown (YAML) frontmatter for TITLE."
  (concat "---\n"
          "title: " title "\n"
          "date: " (format-time-string "%Y-%m-%d") "\n"
          "---\n"
          "<!-- %%% pkm-end-frontmatter %%% -->\n\n"))

(defun haystack--frontmatter-c-block (title)
  "Return frontmatter for TITLE using /* */ block comments (C, CSS)."
  (concat "/* title: " title " */\n"
          "/* date: " (format-time-string "%Y-%m-%d") " */\n"
          "/* %%% pkm-end-frontmatter %%% */\n\n"))

(defun haystack--frontmatter-dash (title)
  "Return frontmatter for TITLE using -- line comments (Lua, Haskell, SQL)."
  (concat "-- title: " title "\n"
          "-- date: " (format-time-string "%Y-%m-%d") "\n"
          "-- %%% pkm-end-frontmatter %%%\n\n"))

(defun haystack--frontmatter-semi (title)
  "Return frontmatter for TITLE using ;; line comments (Lisps)."
  (concat ";; title: " title "\n"
          ";; date: " (format-time-string "%Y-%m-%d") "\n"
          ";; %%% pkm-end-frontmatter %%%\n\n"))

(defun haystack--frontmatter-slash (title)
  "Return frontmatter for TITLE using // line comments (JS, TS, Rust, Go)."
  (concat "// title: " title "\n"
          "// date: " (format-time-string "%Y-%m-%d") "\n"
          "// %%% pkm-end-frontmatter %%%\n\n"))

(defun haystack--frontmatter-hash (title)
  "Return frontmatter for TITLE using # line comments (Python, Ruby, Shell)."
  (concat "# title: " title "\n"
          "# date: " (format-time-string "%Y-%m-%d") "\n"
          "# %%% pkm-end-frontmatter %%%\n\n"))

(defun haystack--frontmatter-html-block (title)
  "Return frontmatter for TITLE using <!-- --> block comments (HTML)."
  (concat "<!-- title: " title " -->\n"
          "<!-- date: " (format-time-string "%Y-%m-%d") " -->\n"
          "<!-- %%% pkm-end-frontmatter %%% -->\n\n"))

(defun haystack--frontmatter-ml-block (title)
  "Return frontmatter for TITLE using (* *) block comments (OCaml, SML)."
  (concat "(* title: " title " *)\n"
          "(* date: " (format-time-string "%Y-%m-%d") " *)\n"
          "(* %%% pkm-end-frontmatter %%% *)\n\n"))

(defcustom haystack-frontmatter-functions
  '(;; Markup / unique formats
    ("org"      . haystack--frontmatter-org)
    ("md"       . haystack--frontmatter-md)
    ("markdown" . haystack--frontmatter-md)
    ("html"     . haystack--frontmatter-html-block)
    ("htm"      . haystack--frontmatter-html-block)
    ;; // line comments
    ("js"       . haystack--frontmatter-slash)
    ("mjs"      . haystack--frontmatter-slash)
    ("ts"       . haystack--frontmatter-slash)
    ("tsx"      . haystack--frontmatter-slash)
    ("rs"       . haystack--frontmatter-slash)
    ("go"       . haystack--frontmatter-slash)
    ;; /* */ block comments
    ("c"        . haystack--frontmatter-c-block)
    ("h"        . haystack--frontmatter-c-block)
    ("css"      . haystack--frontmatter-c-block)
    ;; -- line comments
    ("lua"      . haystack--frontmatter-dash)
    ("hs"       . haystack--frontmatter-dash)
    ("sql"      . haystack--frontmatter-dash)
    ;; # line comments
    ("txt"      . haystack--frontmatter-hash)
    ("py"       . haystack--frontmatter-hash)
    ("rb"       . haystack--frontmatter-hash)
    ("sh"       . haystack--frontmatter-hash)
    ("bash"     . haystack--frontmatter-hash)
    ;; ;; line comments
    ("el"       . haystack--frontmatter-semi)
    ("lisp"     . haystack--frontmatter-semi)
    ("cl"       . haystack--frontmatter-semi)
    ("rkt"      . haystack--frontmatter-semi)
    ("scm"      . haystack--frontmatter-semi)
    ("ss"       . haystack--frontmatter-semi)
    ("clj"      . haystack--frontmatter-semi)
    ("cljs"     . haystack--frontmatter-semi)
    ("cljc"     . haystack--frontmatter-semi)
    ("fnl"      . haystack--frontmatter-semi)
    ("fennel"   . haystack--frontmatter-semi)
    ;; (* *) block comments
    ("ml"       . haystack--frontmatter-ml-block)
    ("mli"      . haystack--frontmatter-ml-block))
  "Alist mapping file extensions to frontmatter generator functions.
Each entry is (EXT . FUNCTION) where EXT is a lowercase extension string
without the leading dot, and FUNCTION takes a single TITLE argument and
returns a frontmatter string ending with the pkm-end-frontmatter sentinel.

To add support for a new file type, define a function and add it:

  (defun my-python-frontmatter (title)
    (concat \"# title: \" title \"\\n\"
            \"# date: \" (format-time-string \"%Y-%m-%d\") \"\\n\"
            \"# %%% pkm-end-frontmatter %%%\\n\\n\"))

  (add-to-list \\='haystack-frontmatter-functions
               \\='(\"py\" . my-python-frontmatter))"
  :type '(alist :key-type string :value-type function)
  :group 'haystack)

(defconst haystack--sentinel-regexp "%%% pkm-end-frontmatter %%%"
  "Pattern used to locate the end of a Haystack frontmatter block.")

(defun haystack--frontmatter (title ext)
  "Return frontmatter string for TITLE and file extension EXT.
Looks up EXT in `haystack-frontmatter-functions'.  Returns nil and emits
a message if EXT is not recognised — callers should create the note
without frontmatter in that case."
  (let ((fn (cdr (assoc ext haystack-frontmatter-functions))))
    (if fn
        (funcall fn title)
      (message "Haystack: no frontmatter template for .%s — note created without frontmatter" ext)
      nil)))

(defun haystack--pretty-title (filename)
  "Derive a human-readable title from FILENAME (basename, no directory).
If the name starts with a 14-digit timestamp, strip it and the following
hyphen.  Always strips the file extension."
  (let* ((base (file-name-sans-extension filename))
         (stripped (if (string-match "\\`[0-9]\\{14\\}-" base)
                       (substring base (match-end 0))
                     base)))
    (replace-regexp-in-string "-" " " stripped)))

(defun haystack--timestamp ()
  "Return the current time as a YYYYMMDDHHMMSS string."
  (format-time-string "%Y%m%d%H%M%S"))

;;;###autoload
(defun haystack-new-note ()
  "Create a new timestamped note in `haystack-notes-directory'.
Prompts for a slug and file extension, writes frontmatter, opens the
file, and runs `haystack-after-create-hook'."
  (interactive)
  (haystack--ensure-notes-directory)
  (let* ((slug (read-string "Slug: "))
         (ext  (read-string (format "Extension (default %s): " haystack-default-extension)
                            nil nil haystack-default-extension))
         (filename (concat (haystack--timestamp) "-" slug "." ext))
         (path (expand-file-name filename haystack-notes-directory))
         (title (haystack--pretty-title filename))
         (fm (haystack--frontmatter title ext)))
    (when (file-exists-p path)
      (user-error "Haystack: file already exists: %s" path))
    (with-temp-file path
      (when fm (insert fm)))
    (find-file path)
    (goto-char (point-max))
    (run-hooks 'haystack-after-create-hook)))

;;;###autoload
(defun haystack-regenerate-frontmatter ()
  "Regenerate the frontmatter block in the current buffer.
If a pkm-end-frontmatter sentinel is found, everything from the top of
the file up to and including the sentinel line is replaced.  If no
sentinel exists, the new frontmatter is inserted at the top.

Warns the user that any custom frontmatter fields (e.g. TAGS) will be
lost, and offers to abort before making any changes."
  (interactive)
  (unless (buffer-file-name)
    (user-error "Haystack: buffer is not visiting a file"))
  (let* ((ext   (file-name-extension (buffer-file-name)))
         (title (haystack--pretty-title (file-name-nondirectory (buffer-file-name))))
         (fm    (haystack--frontmatter title ext)))
    (unless fm
      (user-error "Haystack: no frontmatter template for .%s" ext))
    (unless (y-or-n-p
             "Regenerating frontmatter will overwrite any custom fields \
(e.g. TAGS).  Save them first if needed.  Continue? ")
      (user-error "Haystack: frontmatter regeneration aborted"))
    (save-excursion
      (let ((inhibit-read-only t))
        (goto-char (point-min))
        (if (re-search-forward (regexp-quote haystack--sentinel-regexp) nil t)
            ;; Replace from top of file through the sentinel line.
            (let ((delete-to (save-excursion
                               (goto-char (line-end-position))
                               (skip-chars-forward "\n")
                               (point))))
              (delete-region (point-min) delete-to)
              (goto-char (point-min))
              (insert fm))
          ;; No sentinel found — insert at top.
          (goto-char (point-min))
          (insert fm))))))

;;;; Input processing pipeline

(defun haystack--strip-prefixes (raw)
  "Strip leading prefix characters from RAW user input.
Returns a list (TERM NEGATED LITERAL REGEX) where each flag is non-nil
if its corresponding prefix was present.  Detection order: ! then = then ~."
  (let ((negated nil)
        (literal nil)
        (regex   nil)
        (term    raw))
    (when (string-prefix-p "!" term)
      (setq negated t
            term (substring term 1)))
    (when (string-prefix-p "=" term)
      (setq literal t
            term (substring term 1)))
    (when (string-prefix-p "~" term)
      (setq regex t
            term (substring term 1)))
    (list term negated literal regex)))

(defun haystack--multi-word-p (term)
  "Return non-nil if TERM contains any whitespace (multi-word query)."
  (string-match-p "[[:space:]]" term))

(defun haystack--build-pattern (term regex)
  "Return the ripgrep pattern string for TERM.
If REGEX is non-nil, TERM is used as-is (raw ripgrep regex).
Otherwise, `regexp-quote' is applied for literal-by-default matching.

Phase 2 hook point: for single-word, non-literal terms, expansion
group lookup will slot in here before the `regexp-quote' fallback."
  (if regex
      term
    (regexp-quote term)))

(defun haystack--parse-input (raw)
  "Parse RAW user input through the prefix/classification/escaping pipeline.
Returns a plist:
  :term       — input after prefix stripping
  :negated    — ! prefix: exclude files that match this term
  :literal    — = prefix: suppress expansion group lookup (Phase 2)
  :regex      — ~ prefix: treat term as raw ripgrep regex, skip escaping
  :multi-word — non-nil if term contains whitespace after stripping
  :pattern    — final regex string to pass to ripgrep"
  (cl-destructuring-bind (term negated literal regex)
      (haystack--strip-prefixes raw)
    (list :term       term
          :negated    negated
          :literal    literal
          :regex      regex
          :multi-word (haystack--multi-word-p term)
          :pattern    (haystack--build-pattern term regex))))

(provide 'haystack)
;;; haystack.el ends here
