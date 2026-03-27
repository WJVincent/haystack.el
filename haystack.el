;;; haystack.el --- Search-first knowledge management -*- lexical-binding: t -*-

;; Author: wv
;; Version: 0.7.0
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

(require 'cl-lib)
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

(defcustom haystack-context-width 60
  "Number of content characters to show around a match in results buffers.
When a result line's content exceeds this width, it is truncated to a
window of this many characters centred on the match, with ... at either
truncated end.  Increase for more context; decrease for tighter lines."
  :type 'integer
  :group 'haystack)


(defcustom haystack-moc-code-style 'comment
  "How MOC links are formatted when yanking into code files.
  data    — language-appropriate structured data (Phase 2; currently falls
            back to `comment' for all extensions)
  comment — line prefixed with the language's comment syntax"
  :type '(choice (const :tag "Structured data" data)
                 (const :tag "Commented lines" comment))
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

(defvar-local haystack--buffer-notes-dir nil
  "The expanded `haystack-notes-directory' at the time this buffer was created.
Used to scope tree views and kill operations to the correct notes directory.")

(defvar-local haystack--search-descriptor nil
  "Plist describing the full search chain for this buffer.

Structure:
  (:root-term       STRING   — raw user input for root search
   :root-expanded   STRING   — regex sent to rg (may be alternation)
   :root-literal    BOOL     — = prefix: suppress expansion
   :root-regex      BOOL     — ~ prefix: skip regexp-quote
   :root-filename   BOOL     — / prefix: root was a filename search
   :root-expansion  LIST     — group members if expansion fired, nil otherwise
   :filters         LIST     — ordered list of filter plists
   :composite-filter SYMBOL  — \\='exclude | \\='only | \\='all)

Each filter plist:
  (:term      STRING
   :negated   BOOL
   :filename  BOOL
   :literal   BOOL
   :regex     BOOL
   :expansion LIST — group members if expansion fired, nil otherwise)")

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
;;; including the haystack-end-frontmatter sentinel on the final line.

(defun haystack--frontmatter-org (title)
  "Return Org-mode frontmatter for TITLE."
  (concat "#+TITLE: " title "\n"
          "#+DATE: " (format-time-string "%Y-%m-%d") "\n"
          "# %%% haystack-end-frontmatter %%%\n\n"))

(defun haystack--frontmatter-md (title)
  "Return Markdown (YAML) frontmatter for TITLE."
  (concat "---\n"
          "title: " title "\n"
          "date: " (format-time-string "%Y-%m-%d") "\n"
          "---\n"
          "<!-- %%% haystack-end-frontmatter %%% -->\n\n"))

(defun haystack--frontmatter-c-block (title)
  "Return frontmatter for TITLE using /* */ block comments (C, CSS)."
  (concat "/* title: " title " */\n"
          "/* date: " (format-time-string "%Y-%m-%d") " */\n"
          "/* %%% haystack-end-frontmatter %%% */\n\n"))

(defun haystack--frontmatter-dash (title)
  "Return frontmatter for TITLE using -- line comments (Lua, Haskell, SQL)."
  (concat "-- title: " title "\n"
          "-- date: " (format-time-string "%Y-%m-%d") "\n"
          "-- %%% haystack-end-frontmatter %%%\n\n"))

(defun haystack--frontmatter-semi (title)
  "Return frontmatter for TITLE using ;; line comments (Lisps)."
  (concat ";; title: " title "\n"
          ";; date: " (format-time-string "%Y-%m-%d") "\n"
          ";; %%% haystack-end-frontmatter %%%\n\n"))

(defun haystack--frontmatter-slash (title)
  "Return frontmatter for TITLE using // line comments (JS, TS, Rust, Go)."
  (concat "// title: " title "\n"
          "// date: " (format-time-string "%Y-%m-%d") "\n"
          "// %%% haystack-end-frontmatter %%%\n\n"))

(defun haystack--frontmatter-hash (title)
  "Return frontmatter for TITLE using # line comments (Python, Ruby, Shell)."
  (concat "# title: " title "\n"
          "# date: " (format-time-string "%Y-%m-%d") "\n"
          "# %%% haystack-end-frontmatter %%%\n\n"))

(defun haystack--frontmatter-html-block (title)
  "Return frontmatter for TITLE using <!-- --> block comments (HTML)."
  (concat "<!-- title: " title " -->\n"
          "<!-- date: " (format-time-string "%Y-%m-%d") " -->\n"
          "<!-- %%% haystack-end-frontmatter %%% -->\n\n"))

(defun haystack--frontmatter-ml-block (title)
  "Return frontmatter for TITLE using (* *) block comments (OCaml, SML)."
  (concat "(* title: " title " *)\n"
          "(* date: " (format-time-string "%Y-%m-%d") " *)\n"
          "(* %%% haystack-end-frontmatter %%% *)\n\n"))

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
returns a frontmatter string ending with the haystack-end-frontmatter sentinel.

To add support for a new file type, define a function and add it:

  (defun my-python-frontmatter (title)
    (concat \"# title: \" title \"\\n\"
            \"# date: \" (format-time-string \"%Y-%m-%d\") \"\\n\"
            \"# %%% haystack-end-frontmatter %%%\\n\\n\"))

  (add-to-list \\='haystack-frontmatter-functions
               \\='(\"py\" . my-python-frontmatter))"
  :type '(alist :key-type string :value-type function)
  :group 'haystack)

(defconst haystack--sentinel-string "%%% haystack-end-frontmatter %%%"
  "Literal string marking the end of a Haystack frontmatter block.")

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

(defun haystack--sanitize-slug (slug)
  "Return SLUG safe for use as a filename component.
Leading and trailing whitespace is trimmed.  Any run of whitespace is
replaced by a single hyphen.  Characters unsafe in filenames
(/ \\ : * ? \" < > |) are removed."
  (let* ((s (string-trim slug))
         (s (replace-regexp-in-string "[[:space:]]+" "-" s))
         (s (replace-regexp-in-string "[/\\\\:*?\"<>|]" "" s)))
    s))

;;;###autoload
(defun haystack-new-note ()
  "Create a new timestamped note in `haystack-notes-directory'.
Prompts for a slug and file extension, writes frontmatter, opens the
file, and runs `haystack-after-create-hook'."
  (interactive)
  (haystack--ensure-notes-directory)
  (let* ((slug (haystack--sanitize-slug (read-string "Slug: ")))
         (ext  (read-string (format "Extension (default %s): " haystack-default-extension)
                            nil nil haystack-default-extension))
         (filename (concat (haystack--timestamp) "-" slug "." ext))
         (path (expand-file-name filename haystack-notes-directory))
         (title (haystack--pretty-title filename))
         (fm (haystack--frontmatter title ext)))
    (when (file-exists-p path)
      (user-error "Haystack: file already exists: %s" path))
    (with-temp-file path
      (when fm (insert fm))
      (when haystack--demo-active
        (insert "HAYSTACK DEMO NOTE — this file will be deleted when haystack-demo-stop is called.\n\n")))
    (find-file path)
    (goto-char (point-max))
    (run-hooks 'haystack-after-create-hook)))

;;;###autoload
(defun haystack-regenerate-frontmatter ()
  "Regenerate the frontmatter block in the current buffer.
If a haystack-end-frontmatter sentinel is found, everything from the top of
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
        (if (re-search-forward (regexp-quote haystack--sentinel-string) nil t)
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

;;;; Expansion Groups

(defvar haystack--expansion-groups nil
  "Alist of expansion groups loaded from `.expansion-groups.el'.
Each entry is (ROOT . MEMBERS) where ROOT is the canonical group name
and MEMBERS is a list of synonym strings.  All matching is
case-insensitive.  Format example:
  ((\"programming\" . (\"coding\" \"code\" \"scripting\"))
   (\"rust\" . (\"rustlang\")))")

(defun haystack--expansion-groups-file ()
  "Return the path to `.expansion-groups.el' in `haystack-notes-directory'."
  (expand-file-name ".expansion-groups.el" haystack-notes-directory))

(defun haystack--load-expansion-groups ()
  "Load expansion groups from `.expansion-groups.el' into `haystack--expansion-groups'.
Silently sets `haystack--expansion-groups' to nil when the file is
absent.  Emits a message on parse errors rather than signalling."
  (setq haystack--expansion-groups nil)
  (when (and haystack-notes-directory
             (file-readable-p (haystack--expansion-groups-file)))
    (condition-case err
        (setq haystack--expansion-groups
              (with-temp-buffer
                (insert-file-contents (haystack--expansion-groups-file))
                (read (current-buffer))))
      (error
       (setq haystack--expansion-groups nil)
       (message "Haystack: failed to load expansion groups: %s"
                (error-message-string err))))))

;;;###autoload
(defun haystack-reload-expansion-groups ()
  "Reload expansion groups from `.expansion-groups.el' and report the count."
  (interactive)
  (haystack--load-expansion-groups)
  (message "Haystack: loaded %d expansion group%s"
           (length haystack--expansion-groups)
           (if (= 1 (length haystack--expansion-groups)) "" "s")))

;;;###autoload
(defun haystack-validate-groups ()
  "Check loaded expansion groups for terms that appear in more than one group.
Reports conflicts in a dedicated buffer.  If no conflicts are found, a
message is shown instead."
  (interactive)
  (let ((seen (make-hash-table :test #'equal))
        (dups nil))
    (dolist (group haystack--expansion-groups)
      (dolist (term (cons (car group) (cdr group)))
        (let ((key (downcase term)))
          (if (gethash key seen)
              (push (list term (gethash key seen)) dups)
            (puthash key term seen)))))
    (if (null dups)
        (message "Haystack: expansion groups OK — no duplicate terms")
      (let ((buf (get-buffer-create "*haystack-group-conflicts*")))
        (with-current-buffer buf
          (let ((inhibit-read-only t))
            (erase-buffer)
            (insert "Haystack — Expansion Group Conflicts\n")
            (insert (make-string 40 ?=) "\n\n")
            (dolist (dup (nreverse dups))
              (insert (format "  %S conflicts with %S\n"
                              (car dup) (cadr dup))))
            (special-mode)
            (goto-char (point-min))))
        (pop-to-buffer buf)))))

;;;###autoload
(defun haystack-describe-expansion-groups ()
  "Display all loaded expansion groups in a dedicated buffer."
  (interactive)
  (let ((buf (get-buffer-create "*haystack-expansion-groups*")))
    (with-current-buffer buf
      (let ((inhibit-read-only t))
        (erase-buffer)
        (insert "Haystack — Expansion Groups\n")
        (insert (make-string 40 ?=) "\n\n")
        (if (null haystack--expansion-groups)
            (insert "(no groups loaded)\n")
          (dolist (group haystack--expansion-groups)
            (insert (format "%-20s → %s\n"
                            (car group)
                            (mapconcat #'identity (cdr group) ", ")))))
        (special-mode)
        (goto-char (point-min))))
    (pop-to-buffer buf)))

(defun haystack--lookup-group (term)
  "Return the full member list of TERM's expansion group, or nil.
Searches all groups in `haystack--expansion-groups' case-insensitively.
Returns (ROOT MEMBER1 MEMBER2 ...) if TERM matches any entry, nil if
no group contains TERM."
  (let ((key (downcase term)))
    (catch 'found
      (dolist (group haystack--expansion-groups)
        (let ((all (cons (car group) (cdr group))))
          (when (cl-some (lambda (m) (string= key (downcase m))) all)
            (throw 'found all))))
      nil)))

(defun haystack--expansion-alternation (members)
  "Return a ripgrep alternation pattern for MEMBERS.
Each member is passed through `regexp-quote'.  Returns \"(A|B|C)\"."
  (concat "("
          (mapconcat (lambda (m) (regexp-quote m)) members "|")
          ")"))

(defun haystack--save-expansion-groups ()
  "Write `haystack--expansion-groups' to `.expansion-groups.el'.
Creates or overwrites the file.  Signals `user-error' if
`haystack-notes-directory' is not set."
  (haystack--assert-notes-directory)
  (with-temp-file (haystack--expansion-groups-file)
    (insert ";; Haystack expansion groups — managed with `haystack-associate'\n")
    (insert ";; Format: ((root . (synonym1 synonym2 ...)) ...)\n\n")
    (pp haystack--expansion-groups (current-buffer))))

(defun haystack--groups-remove-term (groups term)
  "Return GROUPS with TERM removed from whichever group contains it.
If TERM was the root, the first remaining member is promoted to root.
Groups that fall below two total terms after removal are dissolved."
  (let ((key (downcase term)))
    (delq nil
          (mapcar (lambda (group)
                    (let* ((all       (cons (car group) (cdr group)))
                           (remaining (cl-remove-if
                                       (lambda (m) (string= key (downcase m)))
                                       all)))
                      (if (>= (length remaining) 2)
                          (cons (car remaining) (cdr remaining))
                        ;; Fewer than 2 terms — dissolve
                        nil)))
                  groups))))

(defun haystack--groups-add-to-group (groups anchor term)
  "Return GROUPS with TERM added to ANCHOR's group.
If ANCHOR is not in any group, a new group is created with ANCHOR as
root and TERM as its first member."
  (let* ((anchor-key (downcase anchor))
         (found      nil)
         (result
          (mapcar (lambda (group)
                    (let ((all (cons (car group) (cdr group))))
                      (if (cl-some (lambda (m) (string= anchor-key (downcase m))) all)
                          (progn (setq found t)
                                 (cons (car group)
                                       (append (cdr group) (list term))))
                        group)))
                  groups)))
    (if found
        result
      (append groups (list (cons anchor (list term)))))))

;;;###autoload
(defun haystack-associate (term-a term-b)
  "Associate TERM-A and TERM-B as synonyms in an expansion group.
Multi-word terms are rejected.  Three states:

  • Neither assigned or A has a group: TERM-B is added to TERM-A's
    group (or a new group is created if both are unassigned).
  • A unassigned, B has a group: TERM-A is added to TERM-B's group.
  • Both assigned to different groups: offers to move TERM-B into
    TERM-A's group (or create TERM-A's group if it lacks one).
  • Both already in the same group: no-op."
  (interactive
   (list (read-string "Term A: ")
         (read-string "Term B: ")))
  (when (string= (downcase term-a) (downcase term-b))
    (user-error "Haystack: TERM-A and TERM-B must be different"))
  (let* ((group-a (haystack--lookup-group term-a))
         (group-b (haystack--lookup-group term-b)))
    (cond
     ;; State 3: already in the same group — no-op
     ((and group-a group-b (equal group-a group-b))
      (message "Haystack: %S and %S are already in the same group: (%s)"
               term-a term-b (mapconcat #'identity group-a ", ")))

     ;; State 2: both assigned to different groups — offer move
     ((and group-a group-b)
      (let* ((prompt (format (concat "Conflict:\n  %S is in group: (%s)\n"
                                     "  %S is in group: (%s)\n"
                                     "Move %S to %S's group? ")
                             term-a (mapconcat #'identity group-a ", ")
                             term-b (mapconcat #'identity group-b ", ")
                             term-b term-a))
             (response (read-char-choice
                        (concat prompt "(m)ove / (a)bort: ")
                        '(?m ?a))))
        (if (eq response ?a)
            (message "Haystack: aborted")
          (setq haystack--expansion-groups
                (haystack--groups-remove-term haystack--expansion-groups term-b))
          (setq haystack--expansion-groups
                (haystack--groups-add-to-group haystack--expansion-groups term-a term-b))
          (haystack--save-expansion-groups)
          (message "Haystack: moved %S → group now: (%s)"
                   term-b
                   (mapconcat #'identity (haystack--lookup-group term-a) ", ")))))

     ;; State 1a: B unassigned, A has group or both unassigned → add B toward A
     ((null group-b)
      (setq haystack--expansion-groups
            (haystack--groups-add-to-group haystack--expansion-groups term-a term-b))
      (haystack--save-expansion-groups)
      (if group-a
          (message "Haystack: added %S to group: (%s)"
                   term-b
                   (mapconcat #'identity (haystack--lookup-group term-a) ", "))
        (message "Haystack: created new group: %S → %S" term-a term-b)))

     ;; State 1b: A unassigned, B has group → add A to B's group
     (t
      (setq haystack--expansion-groups
            (haystack--groups-add-to-group haystack--expansion-groups term-b term-a))
      (haystack--save-expansion-groups)
      (message "Haystack: added %S to group: (%s)"
               term-a
               (mapconcat #'identity (haystack--lookup-group term-b) ", "))))))

(defun haystack--groups-rename-root (groups old-root new-root)
  "Return GROUPS with OLD-ROOT replaced by NEW-ROOT as the canonical root.
Only the root (car) of each group is matched; members are not affected."
  (let ((key (downcase old-root)))
    (mapcar (lambda (group)
              (if (string= key (downcase (car group)))
                  (cons new-root (cdr group))
                group))
            groups)))

;;;###autoload
(defun haystack-rename-group-root (old-root new-root)
  "Rename the canonical root term OLD-ROOT to NEW-ROOT in the expansion groups.
OLD-ROOT must be the root (not just a member) of an existing group.
NEW-ROOT must not already be present in any group.

Note: when frecency and composite notes are implemented, those records
will also be updated here.  For now only the groups file is changed."
  (interactive
   (progn
     (haystack--load-expansion-groups)
     (let* ((roots (mapcar #'car haystack--expansion-groups))
            (old   (completing-read "Rename root: " roots nil t))
            (new   (read-string (format "Rename %S to: " old))))
       (list old new))))
  (haystack--load-expansion-groups)
  (when (string= (downcase old-root) (downcase new-root))
    (user-error "Haystack: new root is the same as the old root"))
  (unless (assoc (downcase old-root)
                 (mapcar (lambda (g) (cons (downcase (car g)) g))
                         haystack--expansion-groups))
    (user-error "Haystack: %S is not the root of any group" old-root))
  (when (haystack--lookup-group new-root)
    (user-error "Haystack: %S is already in a group — choose a fresh term" new-root))
  (setq haystack--expansion-groups
        (haystack--groups-rename-root haystack--expansion-groups old-root new-root))
  (haystack--save-expansion-groups)
  (message "Haystack: renamed root %S → %S (group now: (%s))"
           old-root new-root
           (mapconcat #'identity (haystack--lookup-group new-root) ", ")))

(defun haystack--groups-dissolve (groups term)
  "Return GROUPS with the group containing TERM removed entirely.
Matches any member of the group, not just the root."
  (let ((key (downcase term)))
    (cl-remove-if (lambda (group)
                    (cl-some (lambda (m) (string= key (downcase m)))
                             (cons (car group) (cdr group))))
                  groups)))

;;;###autoload
(defun haystack-dissolve-group (term)
  "Remove the entire expansion group that contains TERM.
All members lose their expansion; searches for any of them will
fall back to literal matching.  This cannot be undone except by
editing `.expansion-groups.el' directly or re-running `haystack-associate'."
  (interactive
   (progn
     (haystack--load-expansion-groups)
     (list (completing-read "Dissolve group containing: "
                            (apply #'append
                                   (mapcar (lambda (g) (cons (car g) (cdr g)))
                                           haystack--expansion-groups))
                            nil t))))
  (haystack--load-expansion-groups)
  (unless (haystack--lookup-group term)
    (user-error "Haystack: %S is not in any expansion group" term))
  (let ((group (haystack--lookup-group term)))
    (setq haystack--expansion-groups
          (haystack--groups-dissolve haystack--expansion-groups term))
    (haystack--save-expansion-groups)
    (message "Haystack: dissolved group (%s)"
             (mapconcat #'identity group ", "))))

;;;; Input processing pipeline

(defun haystack--strip-prefixes (raw)
  "Strip leading prefix characters from RAW user input.
Returns a list (TERM NEGATED FILENAME LITERAL REGEX) where each flag is non-nil
if its corresponding prefix was present.  Detection order: ! then / then = then ~."
  (let ((negated  nil)
        (filename nil)
        (literal  nil)
        (regex    nil)
        (term     raw))
    (when (string-prefix-p "!" term)
      (setq negated t
            term (substring term 1)))
    (when (string-prefix-p "/" term)
      (setq filename t
            term (substring term 1)))
    (when (string-prefix-p "=" term)
      (setq literal t
            term (substring term 1)))
    (when (string-prefix-p "~" term)
      (setq regex t
            term (substring term 1)))
    (list term negated filename literal regex)))

(defun haystack--multi-word-p (term)
  "Return non-nil if TERM contains any whitespace (multi-word query)."
  (string-match-p "[[:space:]]" term))

(defun haystack--build-pattern (term regex &optional literal)
  "Return the ripgrep pattern string for TERM.
If REGEX is non-nil, TERM is used as-is (raw ripgrep regex).
If LITERAL is non-nil, expansion is suppressed and `regexp-quote' is
applied directly.
Otherwise: look up an expansion group for TERM (case-insensitive); if
found, return a ripgrep alternation pattern; if not found, fall back to
`regexp-quote'.  Multi-word terms participate in expansion if a group
contains them."
  (cond
   (regex term)
   (literal (regexp-quote term))
   (t (let ((group (haystack--lookup-group term)))
        (if group
            (haystack--expansion-alternation group)
          (regexp-quote term))))))

(defun haystack--build-emacs-pattern (term regex &optional literal)
  "Return an Emacs regexp for TERM, for use with `string-match-p'.
Same expansion logic as `haystack--build-pattern', but uses Emacs
alternation syntax (\\|) so the result works with `string-match-p'.
For raw regex terms the string is passed through as-is — the user is
responsible for Emacs regexp syntax when using the ~ prefix on a
filename filter."
  (cond
   (regex term)
   (literal (regexp-quote term))
   (t (let ((group (haystack--lookup-group term)))
        (if group
            (mapconcat #'regexp-quote group "\\|")
          (regexp-quote term))))))

(defun haystack--parse-input (raw)
  "Parse RAW user input through the prefix/classification/escaping pipeline.
Returns a plist:
  :term       — input after prefix stripping
  :negated    — ! prefix: exclude files that match this term
  :filename   — / prefix: match against the file's basename, not content
  :literal    — = prefix: suppress expansion group lookup
  :regex      — ~ prefix: treat term as raw ripgrep regex, skip escaping
  :multi-word     — non-nil if term contains whitespace after stripping
  :expansion      — group member list if expansion fired, nil otherwise
  :pattern        — ripgrep regex string (for rg calls)
  :emacs-pattern  — Emacs regexp string (for `string-match-p' filename matching)"
  (cl-destructuring-bind (term negated filename literal regex)
      (haystack--strip-prefixes raw)
    (let* ((multi-word (haystack--multi-word-p term))
           (expansion  (and (not regex) (not literal)
                            (haystack--lookup-group term)))
           (pattern    (haystack--build-pattern       term regex literal))
           (emacs-pat  (haystack--build-emacs-pattern term regex literal)))
      (list :term          term
            :negated       negated
            :filename      filename
            :literal       literal
            :regex         regex
            :multi-word    multi-word
            :expansion     expansion
            :pattern       pattern
            :emacs-pattern emacs-pat))))

;;;; Search engine

(defun haystack--rg-base-args (&optional composite-filter)
  "Return the rg flags shared by all haystack searches.
Includes output formatting flags and the composite filter glob.
COMPOSITE-FILTER controls how @* composite files are handled:
  \\='exclude  — exclude them (default, adds --glob=!@*)
  \\='only     — restrict to them (adds --glob=@*)
  \\='all      — no composite filter applied"
  (let ((args (list "--line-number" "--ignore-case"
                    "--color=never" "--no-heading" "--with-filename"
                    "--max-count=50" "--max-columns=500")))
    (pcase (or composite-filter 'exclude)
      ('exclude (setq args (nconc args (list "--glob=!@*"))))
      ('only    (setq args (nconc args (list "--glob=@*"))))
      ('all     nil))
    args))

(defun haystack--build-rg-args (pattern &optional composite-filter)
  "Return rg args for a root search of PATTERN in `haystack-notes-directory'.
Applies `haystack-file-glob' restrictions and expands ~ in the directory path."
  (let ((args (haystack--rg-base-args composite-filter)))
    (when haystack-file-glob
      (dolist (glob haystack-file-glob)
        (setq args (nconc args (list (concat "--glob=" glob))))))
    (nconc args (list pattern (expand-file-name haystack-notes-directory)))))

(defun haystack--build-rg-count-args (pattern &optional composite-filter)
  "Return rg --count args for PATTERN in `haystack-notes-directory'.
Like `haystack--build-rg-args' but uses --count for the two-phase gate."
  (let ((args (list "--count" "--with-filename" "--ignore-case" "--color=never")))
    (pcase (or composite-filter 'exclude)
      ('exclude (setq args (nconc args (list "--glob=!@*"))))
      ('only    (setq args (nconc args (list "--glob=@*"))))
      ('all     nil))
    (when haystack-file-glob
      (dolist (glob haystack-file-glob)
        (setq args (nconc args (list (concat "--glob=" glob))))))
    (nconc args (list pattern (expand-file-name haystack-notes-directory)))))

(defun haystack--rg-count-xargs-args (pattern &optional composite-filter)
  "Return rg --count args for use with xargs (no directory).
Like the xargs variant of `haystack--build-rg-count-args'."
  (let ((args (list "--count" "--with-filename" "--ignore-case" "--color=never")))
    (pcase (or composite-filter 'exclude)
      ('exclude (setq args (nconc args (list "--glob=!@*"))))
      ('only    (setq args (nconc args (list "--glob=@*"))))
      ('all     nil))
    (nconc args (list pattern))))

(defun haystack--count-output-stats (output)
  "Return (FILES . LINES) from rg --count OUTPUT.
FILES is the number of files with matches; LINES is the sum of all counts."
  (let ((files 0) (lines 0))
    (dolist (line (split-string output "\n" t))
      (when (string-match ":\\([0-9]+\\)\\'" line)
        (cl-incf files)
        (cl-incf lines (string-to-number (match-string 1 line)))))
    (cons files lines)))

(defun haystack--volume-gate (count-output)
  "Prompt when COUNT-OUTPUT from rg --count would produce a large result.
If the total line count is >= 500, asks the user to confirm.
Signals `user-error' if the user declines."
  (let* ((stats (haystack--count-output-stats count-output))
         (files (car stats))
         (lines (cdr stats)))
    (when (>= lines 500)
      (unless (yes-or-no-p
               (format "Haystack: %d lines across %d files — run anyway? "
                       lines files))
        (user-error "Haystack: search cancelled")))))

(defun haystack--count-search-stats (output)
  "Return (FILES . MATCHES) from ripgrep OUTPUT string.
FILES is the count of unique file paths; MATCHES is the total line count."
  (let ((files (make-hash-table :test #'equal))
        (matches 0))
    (dolist (line (split-string output "\n" t))
      (when (string-match "\\`\\([^\n:]+\\):[0-9]+:" line)
        (puthash (match-string 1 line) t files)
        (cl-incf matches)))
    (cons (hash-table-count files) matches)))

(defun haystack--truncate-content (content pattern)
  "Return CONTENT windowed to `haystack-context-width' chars around PATTERN.
If CONTENT fits within the width it is returned unchanged.  Otherwise a
window centred on the first match is returned, with ... at truncated ends."
  (let ((width haystack-context-width))
    (if (<= (length content) width)
        content
      (let* ((case-fold-search t)
             (_           (string-match pattern content))
             (match-start (or (match-beginning 0) 0))
             (match-end   (or (match-end 0) 0))
             (match-len   (- match-end match-start))
             (pad         (max 0 (/ (- width match-len) 2)))
             (win-start   (max 0 (- match-start pad)))
             (win-end     (min (length content) (+ win-start width)))
             (win-start   (max 0 (- win-end width)))
             (prefix      (if (> win-start 0) "..." ""))
             (suffix      (if (< win-end (length content)) "..." "")))
        (concat prefix (substring content win-start win-end) suffix)))))

(defun haystack--truncate-output (output pattern)
  "Truncate content of every grep-format line in OUTPUT around PATTERN.
The file:line: prefix of each line is preserved so `compile-goto-error'
continues to work."
  (mapconcat
   (lambda (line)
     (if (string-match "\\`\\([^:]+:[0-9]+:\\)\\(.*\\)" line)
         (concat (match-string 1 line)
                 (haystack--truncate-content (match-string 2 line) pattern))
       line))
   (split-string output "\n")
   "\n"))

(defun haystack--format-header (chain-string files matches)
  "Return a formatted multi-line header string for a results buffer.
CHAIN-STRING describes the full search path (e.g. \"root=rust > filter=async\").
FILES and MATCHES are the result counts."
  (let ((rule (concat ";;;;" (make-string 60 ?-))))
    (concat rule "\n"
            ";;;;  Haystack\n"
            (when haystack--demo-active
              ";;;;  *** DEMO MODE — changes will be discarded on haystack-demo-stop ***\n")
            (format ";;;;  %s\n" chain-string)
            (format ";;;;  %d files  ·  %d matches\n" files matches)
            ";;;;  [root]  [up]  [down]  [tree]\n"
            rule "\n")))

(defun haystack-go-root ()
  "Switch to the root buffer of this haystack tree."
  (interactive)
  (let ((buf (current-buffer)))
    (while (buffer-live-p (buffer-local-value 'haystack--parent-buffer buf))
      (setq buf (buffer-local-value 'haystack--parent-buffer buf)))
    (if (eq buf (current-buffer))
        (message "Already at root")
      (switch-to-buffer buf))))

(defun haystack-ret ()
  "Visit result at point, or activate button if point is on one."
  (interactive)
  (if (button-at (point))
      (push-button)
    (compile-goto-error)))

(defun haystack--apply-header-buttons ()
  "Wire up navigation buttons in the header of the current results buffer.
Must be called inside `inhibit-read-only' with point anywhere in the buffer."
  (save-excursion
    (goto-char (point-min))
    (let ((actions `(("[root]"  . haystack-go-root)
                     ("[up]"    . haystack-go-up)
                     ("[down]"  . haystack-go-down)
                     ("[tree]"  . haystack-show-tree))))
      (dolist (pair actions)
        (when (search-forward (car pair) nil t)
          (make-text-button (match-beginning 0) (match-end 0)
                            'action (lambda (_) (call-interactively (cdr pair)))
                            'follow-link t
                            'help-echo (symbol-name (cdr pair))))))))

(defun haystack--setup-results-buffer (buf-name header output descriptor
                                               &optional parent-buf)
  "Prepare a grep-mode results buffer named BUF-NAME.
Inserts HEADER (marked read-only) then OUTPUT, enables `grep-mode',
and stores DESCRIPTOR and PARENT-BUF as buffer-locals."
  (let ((buf (get-buffer-create buf-name)))
    (with-current-buffer buf
      (let ((inhibit-read-only t))
        (erase-buffer)
        (insert header)
        (let ((header-end (point)))
          (insert output)
          (grep-mode)
          (haystack-results-mode 1)
          ;; Wire up navigation buttons before locking the header.
          (haystack--apply-header-buttons)
          ;; Keep header lines read-only even when wgrep is active.
          (let ((inhibit-read-only t))
            (put-text-property (point-min) header-end 'read-only t))
          (setq haystack--search-descriptor descriptor
                haystack--parent-buffer    parent-buf
                haystack--buffer-notes-dir (expand-file-name haystack-notes-directory)
                default-directory          (file-name-as-directory
                                            (expand-file-name haystack-notes-directory)))
          ;; Land on the first result line so n/p/RET work immediately.
          (goto-char header-end))))
    buf))

(defun haystack--strip-notes-prefix (output)
  "Strip the `haystack-notes-directory' prefix from file paths in OUTPUT.
Each grep-format line whose path begins with the notes directory is
shortened to a path relative to that directory.  Header lines and any
other non-matching lines are passed through unchanged."
  (let ((prefix (file-name-as-directory
                 (expand-file-name haystack-notes-directory))))
    (mapconcat
     (lambda (line)
       (if (string-prefix-p prefix line)
           (substring line (length prefix))
         line))
     (split-string output "\n")
     "\n")))

(defun haystack--extract-filenames (text)
  "Return a deduplicated list of absolute file paths from grep-format TEXT.
Header lines (starting with ;;;) are automatically skipped because they
do not match the file:line: pattern.  Relative paths are expanded using
`default-directory', which is set to `haystack-notes-directory' in all
results buffers."
  (let ((seen  (make-hash-table :test #'equal))
        (files nil))
    (dolist (line (split-string text "\n" t))
      (when (string-match "\\`\\([^:]+\\):[0-9]+:" line)
        (let ((f (expand-file-name (match-string 1 line))))
          (unless (gethash f seen)
            (puthash f t seen)
            (push f files)))))
    (nreverse files)))

(defun haystack--filter-label (negated filename)
  "Return the chain label string for a filter with NEGATED and FILENAME flags."
  (cond ((and negated filename) "!filename")
        (negated                "exclude")
        (filename               "filename")
        (t                      "filter")))

(defun haystack--format-search-chain (descriptor current-term current-negated
                                                 &optional current-filename
                                                 current-expansion)
  "Return a string showing the full search chain for a child buffer header.
Combines the root term, all existing filters from DESCRIPTOR, and the
CURRENT-TERM being applied.  CURRENT-NEGATED and CURRENT-FILENAME control
the label (filter=, exclude=, filename=, or !filename=).
When CURRENT-EXPANSION (a member list) is non-nil it is shown as an
alternation in place of the raw term.  Expansions stored in DESCRIPTOR
are shown the same way."
  (let* ((root-label   (if (plist-get descriptor :root-filename) "filename" "root"))
         (root-exp     (plist-get descriptor :root-expansion))
         (root-display (if root-exp
                           (haystack--expansion-alternation root-exp)
                         (haystack--display-term (plist-get descriptor :root-term))))
         (parts (list (format "%s=%s" root-label root-display))))
    (dolist (f (plist-get descriptor :filters))
      (let* ((f-exp     (plist-get f :expansion))
             (f-display (if f-exp
                            (haystack--expansion-alternation f-exp)
                          (haystack--display-term (plist-get f :term)))))
        (setq parts (nconc parts
                           (list (format "%s=%s"
                                         (haystack--filter-label (plist-get f :negated)
                                                                 (plist-get f :filename))
                                         f-display))))))
    (setq parts (nconc parts
                       (list (format "%s=%s"
                                     (haystack--filter-label current-negated
                                                             current-filename)
                                     (if current-expansion
                                         (haystack--expansion-alternation current-expansion)
                                       (haystack--display-term current-term))))))
    (mapconcat #'identity parts " > ")))

(defun haystack--descriptor-chain-string (descriptor)
  "Return the full search chain string for DESCRIPTOR.
Formats root + all stored filters with no additional current term appended.
Used to produce the header comment in data-style MOC output."
  (let* ((root-label   (if (plist-get descriptor :root-filename) "filename" "root"))
         (root-exp     (plist-get descriptor :root-expansion))
         (root-display (if root-exp
                           (haystack--expansion-alternation root-exp)
                         (haystack--display-term (plist-get descriptor :root-term))))
         (parts (list (format "%s=%s" root-label root-display))))
    (dolist (f (plist-get descriptor :filters))
      (let* ((f-exp     (plist-get f :expansion))
             (f-display (if f-exp
                            (haystack--expansion-alternation f-exp)
                          (haystack--display-term (plist-get f :term)))))
        (setq parts (nconc parts
                           (list (format "%s=%s"
                                         (haystack--filter-label (plist-get f :negated)
                                                                 (plist-get f :filename))
                                         f-display))))))
    (mapconcat #'identity parts " > ")))

(defun haystack--child-buffer-name (descriptor new-term new-negated
                                               new-filename new-literal new-regex)
  "Return the results buffer name for a child filter of DESCRIPTOR.
NEW-TERM and its modifier flags (NEW-NEGATED, NEW-FILENAME, NEW-LITERAL,
NEW-REGEX) describe the filter being applied.  All terms in the chain
are prefixed with their modifier characters for clarity."
  (let* ((root    (haystack--tree-term-label
                   (plist-get descriptor :root-term)
                   nil
                   (plist-get descriptor :root-filename)
                   (plist-get descriptor :root-literal)
                   (plist-get descriptor :root-regex)))
         (filters (mapcar (lambda (f)
                            (haystack--tree-term-label
                             (plist-get f :term)
                             (plist-get f :negated)
                             (plist-get f :filename)
                             (plist-get f :literal)
                             (plist-get f :regex)))
                          (plist-get descriptor :filters)))
         (chain   (append (list root) filters
                          (list (haystack--tree-term-label
                                 new-term new-negated new-filename
                                 new-literal new-regex)))))
    (format "*haystack:%d:%s*"
            (length chain)
            (mapconcat #'identity chain ":"))))

(defun haystack--write-filelist (files)
  "Write FILES (list of absolute paths) to a temp file; return its path.
Paths are null-separated for use with xargs -0.  Caller is responsible
for deleting the file."
  (let ((tmp (make-temp-file "haystack-files-")))
    (with-temp-file tmp
      (insert (mapconcat #'identity files "\0")))
    tmp))

(defun haystack--xargs-rg (filelist rg-args)
  "Run xargs -0 rg RG-ARGS < FILELIST, return stdout as a string.
Each element of RG-ARGS is passed through `shell-quote-argument'.
Stderr is redirected to a temp file so that rg error messages never
appear in search results.  Non-empty stderr signals a `user-error'.
Exit codes are not used: rg exits 1 for no matches (normal) and xargs
propagates exit codes in a version-dependent way."
  (let* ((err-file (make-temp-file "haystack-rg-err-"))
         (cmd (concat "xargs -0 rg "
                      (mapconcat #'shell-quote-argument rg-args " ")
                      " < "
                      (shell-quote-argument filelist)
                      " 2>"
                      (shell-quote-argument err-file))))
    (unwind-protect
        (let ((stdout (with-temp-buffer
                        (call-process-shell-command cmd nil t)
                        (buffer-string)))
              (stderr (with-temp-buffer
                        (insert-file-contents err-file)
                        (string-trim (buffer-string)))))
          (unless (string-empty-p stderr)
            (user-error "Haystack: rg error: %s" stderr))
          stdout)
      (delete-file err-file))))

(defun haystack--run-rg-for-filelist (pattern filelist cf)
  "Search for PATTERN in files listed in FILELIST with composite filter CF.
Uses xargs to pass file paths to rg, avoiding argument length limits."
  (haystack--xargs-rg filelist
                      (nconc (haystack--rg-base-args cf) (list pattern))))

(defun haystack--files-for-root-search (&optional cf)
  "Return a list of all files in `haystack-notes-directory' for a filename search.
Applies `haystack-file-glob' and the composite filter CF (default \\='exclude)."
  (let ((args (list "--files")))
    (when haystack-file-glob
      (dolist (g haystack-file-glob)
        (setq args (nconc args (list (concat "--glob=" g))))))
    (pcase (or cf 'exclude)
      ('exclude (setq args (nconc args (list "--glob=!@*"))))
      ('only    (setq args (nconc args (list "--glob=@*"))))
      ('all     nil))
    (setq args (nconc args (list (expand-file-name haystack-notes-directory))))
    (split-string
     (with-temp-buffer
       (apply #'call-process "rg" nil t nil args)
       (buffer-string))
     "\n" t)))

(defun haystack--run-negation-filter (term root-pattern filelist cf)
  "Return rg output for a negation filter against files in FILELIST.
Step 1: find files that do not contain TERM via xargs + --files-without-match.
Step 2: write the narrowed set to a second temp file and re-run ROOT-PATTERN."
  (let* ((narrowed
          (split-string
           (haystack--xargs-rg filelist
                               (list "--files-without-match"
                                     "--ignore-case"
                                     term))
           "\n" t)))
    (if (null narrowed)
        ""
      (let ((tmp2 (haystack--write-filelist narrowed)))
        (unwind-protect
            (haystack--run-rg-for-filelist root-pattern tmp2 cf)
          (delete-file tmp2))))))

;;;###autoload
(defun haystack-filter-further (raw-input)
  "Narrow the current haystack results buffer by RAW-INPUT.
Extracts files from the current buffer, runs rg scoped to those files,
and opens the child results buffer in the current window.
Prefix RAW-INPUT with ! to exclude files containing the term."
  (interactive
   (list (read-string "[=]literal  [/]filename  [!]negate  [~]regex\nFilter: ")))
  (unless (and (boundp 'haystack--search-descriptor)
               haystack--search-descriptor)
    (user-error "Haystack: not in a haystack results buffer"))
  (haystack--load-expansion-groups)
  (let* ((parent-buf   (current-buffer))
         (descriptor   haystack--search-descriptor)
         (cf           (plist-get descriptor :composite-filter))
         (root-pattern (plist-get descriptor :root-expanded))
         (parsed       (haystack--parse-input raw-input))
         (term         (plist-get parsed :term))
         (pattern      (plist-get parsed :pattern))
         (emacs-pat    (plist-get parsed :emacs-pattern))
         (negated      (plist-get parsed :negated))
         (filename     (plist-get parsed :filename))
         (expansion    (plist-get parsed :expansion))
         (filenames    (haystack--extract-filenames (buffer-string)))
         (root-exp     (plist-get descriptor :root-expansion)))
    (when (null filenames)
      (user-error "Haystack: no files in current buffer to filter"))
    ;; Exclusivity guardrail: a bare single-word term that belongs to the
    ;; same expansion group as the root is already covered — filtering with
    ;; it would produce a redundant (and confusing) sub-search.  Suggest =
    ;; to force a literal search instead.
    (when (and root-exp
               (not (plist-get parsed :literal))
               (not (plist-get parsed :filename))
               (not (plist-get parsed :regex))
               (cl-some (lambda (m) (string= (downcase term) (downcase m)))
                        root-exp))
      (user-error
       "Haystack: '%s' is already in the root expansion (%s) — use =%s to search literally"
       term
       (mapconcat #'identity root-exp "|")
       term))
    (let* ((raw-output
            (if filename
                ;; Filename filter: narrow filelist by basename match in elisp,
                ;; then re-run root-pattern for content.
                ;; Use :emacs-pattern (not :pattern) — :pattern is ripgrep syntax.
                (let* ((notes-root (file-name-as-directory
                                    (expand-file-name haystack-notes-directory)))
                       (narrowed (cl-remove-if-not
                                  (lambda (f)
                                    (let* ((rel   (if (string-prefix-p notes-root f)
                                                      (substring f (length notes-root))
                                                    (file-name-nondirectory f)))
                                           (match (string-match-p emacs-pat rel)))
                                      (if negated (not match) match)))
                                  filenames)))
                  (if (null narrowed)
                      ""
                    (let ((tmp2 (haystack--write-filelist narrowed)))
                      (unwind-protect
                          (haystack--run-rg-for-filelist root-pattern tmp2 cf)
                        (delete-file tmp2)))))
              ;; Content filter: write filelist to temp file, run rg.
              (let ((tmp (haystack--write-filelist filenames)))
                (unwind-protect
                    (if negated
                        (haystack--run-negation-filter pattern root-pattern tmp cf)
                      (progn
                        (haystack--volume-gate
                         (haystack--xargs-rg tmp (haystack--rg-count-xargs-args pattern cf)))
                        (haystack--run-rg-for-filelist pattern tmp cf)))
                  (delete-file tmp)))))
           (stats       (haystack--count-search-stats raw-output))
           (trunc-pat   (if (or filename negated) root-pattern pattern))
           (output      (haystack--strip-notes-prefix
                         (haystack--truncate-output raw-output trunc-pat)))
           (buf-name    (haystack--child-buffer-name descriptor term negated filename
                                                    (plist-get parsed :literal)
                                                    (plist-get parsed :regex)))
           (header      (haystack--format-header
                         (haystack--format-search-chain descriptor term negated
                                                        filename expansion)
                         (car stats) (cdr stats)))
           (new-filters (append (plist-get descriptor :filters)
                                (list (list :term      term
                                            :negated   negated
                                            :filename  filename
                                            :literal   (plist-get parsed :literal)
                                            :regex     (plist-get parsed :regex)
                                            :expansion expansion))))
           (new-descriptor (list :root-term        (plist-get descriptor :root-term)
                                 :root-expanded    root-pattern
                                 :root-literal     (plist-get descriptor :root-literal)
                                 :root-regex       (plist-get descriptor :root-regex)
                                 :root-filename    (plist-get descriptor :root-filename)
                                 :root-expansion   (plist-get descriptor :root-expansion)
                                 :filters          new-filters
                                 :composite-filter cf)))
      (haystack--frecency-record new-descriptor)
      (switch-to-buffer
       (haystack--setup-results-buffer
        buf-name header output new-descriptor parent-buf)))))

;;;###autoload
(defun haystack-run-root-search (raw-input &optional composite-filter)
  "Search for RAW-INPUT in `haystack-notes-directory'.
Parses prefixes, builds a ripgrep command, and opens a grep-mode
results buffer named *haystack:1:TERM* with a statistics header.

Prefix RAW-INPUT with / to match against filenames instead of content.
COMPOSITE-FILTER is a symbol controlling how @* composite files are
treated: \\='exclude (default), \\='only, or \\='all."
  (interactive "sHaystack search: ")
  (haystack--assert-notes-directory)
  (haystack--load-expansion-groups)
  (let* ((cf       (or composite-filter 'exclude))
         (parsed   (haystack--parse-input raw-input))
         (term      (plist-get parsed :term))
         (pattern   (plist-get parsed :pattern))
         (emacs-pat (plist-get parsed :emacs-pattern))
         (filename  (plist-get parsed :filename))
         (output
          (if filename
              (let* ((all-files  (haystack--files-for-root-search cf))
                     (notes-root (file-name-as-directory
                                  (expand-file-name haystack-notes-directory)))
                     (matching   (cl-remove-if-not
                                  (lambda (f)
                                    ;; Match against path relative to notes dir so that
                                    ;; directory components (e.g. sicp-org/README.org)
                                    ;; are included.  Use :emacs-pattern — :pattern is
                                    ;; ripgrep syntax.
                                    (let ((rel (if (string-prefix-p notes-root f)
                                                   (substring f (length notes-root))
                                                 (file-name-nondirectory f))))
                                      (string-match-p emacs-pat rel)))
                                  all-files)))
                (if (null matching)
                    ""
                  (let ((tmp (haystack--write-filelist matching)))
                    (unwind-protect
                        (haystack--run-rg-for-filelist "." tmp cf)
                      (delete-file tmp)))))
            (progn
              (haystack--volume-gate
               (with-temp-buffer
                 (apply #'call-process "rg" nil t nil
                        (haystack--build-rg-count-args pattern cf))
                 (buffer-string)))
              (with-temp-buffer
                (let ((exit-code (apply #'call-process "rg" nil t nil
                                        (haystack--build-rg-args pattern cf))))
                  (when (= exit-code 2)
                    (user-error "Haystack: rg error: %s" (buffer-string))))
                (buffer-string)))))
         (trunc-pat (if filename "." pattern))
         (stats    (haystack--count-search-stats output))
         (output   (haystack--strip-notes-prefix
                    (haystack--truncate-output output trunc-pat)))
         (buf-name (format "*haystack:1:%s*"
                           (haystack--tree-term-label term nil filename
                                                      (plist-get parsed :literal)
                                                      (plist-get parsed :regex))))
         (expansion   (plist-get parsed :expansion))
         (chain-label (format "%s=%s"
                              (if filename "filename" "root")
                              (if expansion
                                  (haystack--expansion-alternation expansion)
                                (haystack--display-term term))))
         (header   (haystack--format-header chain-label (car stats) (cdr stats)))
         (descriptor (list :root-term        term
                           :root-expanded    (if filename "." pattern)
                           :root-literal     (plist-get parsed :literal)
                           :root-regex       (plist-get parsed :regex)
                           :root-filename    filename
                           :root-expansion   expansion
                           :filters          nil
                           :composite-filter cf)))
    (haystack--frecency-record descriptor)
    (pop-to-buffer
     (haystack--setup-results-buffer buf-name header output descriptor))))

;;;###autoload
(defun haystack-search-region ()
  "Search for the active region text via `haystack-run-root-search'."
  (interactive)
  (unless (use-region-p)
    (user-error "Haystack: no active region"))
  (haystack-run-root-search
   (buffer-substring-no-properties (region-beginning) (region-end))))

;;;; Results minor mode

(defvar haystack-results-mode-map (make-sparse-keymap)
  "Keymap active in haystack results buffers (on top of `grep-mode').")
(define-key haystack-results-mode-map (kbd "RET") #'haystack-ret)
(define-key haystack-results-mode-map "n" #'haystack-next-match)
(define-key haystack-results-mode-map "p" #'haystack-previous-match)
(define-key haystack-results-mode-map "f" #'haystack-filter-further)
(define-key haystack-results-mode-map "u" #'haystack-go-up)
(define-key haystack-results-mode-map "d" #'haystack-go-down)
(define-key haystack-results-mode-map "k" #'haystack-kill-node)
(define-key haystack-results-mode-map "K" #'haystack-kill-subtree)
(define-key haystack-results-mode-map (kbd "M-k") #'haystack-kill-whole-tree)
(define-key haystack-results-mode-map "c" #'haystack-copy-moc)
(define-key haystack-results-mode-map "t" #'haystack-show-tree)
(define-key haystack-results-mode-map "?" #'haystack-help)

(define-minor-mode haystack-results-mode
  "Minor mode active in all haystack results buffers.
Provides navigation commands that keep focus in the results buffer
while previewing matched files in another window."
  :keymap haystack-results-mode-map)

;;;###autoload
(defun haystack-next-match (&optional n)
  "Move to the next N-th match in the results buffer and preview it.
Focus remains in the results buffer; the matched file is shown in
another window."
  (interactive "p")
  (compilation-next-error (or n 1))
  (save-selected-window
    (compile-goto-error)))

;;;###autoload
(defun haystack-previous-match (&optional n)
  "Move to the previous N-th match in the results buffer and preview it.
Focus remains in the results buffer; the matched file is shown in
another window."
  (interactive "p")
  (compilation-next-error (- (or n 1)))
  (save-selected-window
    (compile-goto-error)))

;;;; Help

(defun haystack--help-key (cmd)
  "Return a human-readable key string for CMD in `haystack-results-mode-map'.
Returns \"unbound\" if CMD has no binding in that map."
  (let ((keys (where-is-internal cmd haystack-results-mode-map)))
    (if keys (key-description (car keys)) "unbound")))

(defun haystack--help-content ()
  "Return the formatted string for the haystack help buffer."
  (let ((rule (concat ";;;;" (make-string 50 ?-)))
        (key  #'haystack--help-key))
    (mapconcat #'identity
               (list rule
                     ";;;;  Haystack — results buffer commands"
                     rule
                     ""
                     ";;;;  Navigation"
                     (format ";;;;    %-8s  next match"      (funcall key 'haystack-next-match))
                     (format ";;;;    %-8s  previous match"  (funcall key 'haystack-previous-match))
                     ""
                     ";;;;  Filter"
                     (format ";;;;    %-8s  filter further"  (funcall key 'haystack-filter-further))
                     ""
                     ";;;;  Tree"
                     (format ";;;;    %-8s  show tree"       (funcall key 'haystack-show-tree))
                     (format ";;;;    %-8s  go up"           (funcall key 'haystack-go-up))
                     (format ";;;;    %-8s  go down"         (funcall key 'haystack-go-down))
                     (format ";;;;    %-8s  kill node"       (funcall key 'haystack-kill-node))
                     (format ";;;;    %-8s  kill subtree"    (funcall key 'haystack-kill-subtree))
                     (format ";;;;    %-8s  kill whole tree" (funcall key 'haystack-kill-whole-tree))
                     ""
                     ";;;;  MOC"
                     (format ";;;;    %-8s  copy moc"        (funcall key 'haystack-copy-moc))
                     ""
                     ";;;;    q         close this window"
                     rule)
               "\n")))

;;;###autoload
(defun haystack-help ()
  "Show a popup window listing all haystack results buffer commands."
  (interactive)
  (let ((buf (get-buffer-create "*haystack-help*")))
    (with-current-buffer buf
      (let ((inhibit-read-only t))
        (erase-buffer)
        (insert (haystack--help-content))
        (special-mode)
        (goto-char (point-min))))
    (select-window
     (display-buffer buf
                     '((display-buffer-below-selected)
                       (window-height . fit-window-to-buffer))))))

;;;; Tree view

(defvar haystack-tree-depth-faces
  '(font-lock-keyword-face
    font-lock-function-name-face
    font-lock-variable-name-face
    font-lock-constant-face
    font-lock-string-face)
  "Faces cycled through successive depth levels in `haystack-show-tree'.
Each face is drawn from the active theme, so the tree adapts to colorscheme
changes automatically.  Customize to taste.")

(define-derived-mode haystack-tree-mode special-mode "Haystack-Tree"
  "Major mode for the haystack tree buffer.
Shows all open haystack buffers as a navigable indented tree.")

(define-key haystack-tree-mode-map (kbd "RET") #'haystack-tree-visit)
(define-key haystack-tree-mode-map "n"         #'haystack-tree-next)
(define-key haystack-tree-mode-map "p"         #'haystack-tree-prev)
(define-key haystack-tree-mode-map (kbd "M-n") #'haystack-tree-next-sibling)
(define-key haystack-tree-mode-map (kbd "M-p") #'haystack-tree-prev-sibling)

(defun haystack-tree-visit ()
  "Switch to the haystack buffer on the current line and close the tree window."
  (interactive)
  (let ((buf (get-text-property (point) 'haystack-tree-buffer)))
    (unless (and buf (buffer-live-p buf))
      (user-error "Haystack: no buffer at point"))
    (quit-window)
    (switch-to-buffer buf)))

(defun haystack--tree-move-to-term ()
  "Move point to the first character of the term on the current line.
Skips past tree art characters (spaces, │, ├, └, ─)."
  (beginning-of-line)
  (skip-chars-forward " │├└─"))

(defun haystack-tree-next ()
  "Move point to the next buffer entry in the tree."
  (interactive)
  (let (found)
    (save-excursion
      (forward-line 1)
      (while (and (not found) (not (eobp)))
        (if (get-text-property (point) 'haystack-tree-buffer)
            (setq found (point))
          (forward-line 1))))
    (if found
        (progn (goto-char found) (haystack--tree-move-to-term))
      (user-error "Haystack: no next entry"))))

(defun haystack-tree-prev ()
  "Move point to the previous buffer entry in the tree."
  (interactive)
  (let (found)
    (save-excursion
      (forward-line -1)
      (while (and (not found) (not (bobp)))
        (if (get-text-property (point) 'haystack-tree-buffer)
            (setq found (point))
          (forward-line -1))))
    (if found
        (progn (goto-char found) (haystack--tree-move-to-term))
      (user-error "Haystack: no previous entry"))))

(defun haystack-tree-next-sibling ()
  "Move point to the next entry at the same depth."
  (interactive)
  (let ((depth (get-text-property (point) 'haystack-tree-depth))
        found)
    (unless depth (user-error "Haystack: no entry at point"))
    (save-excursion
      (forward-line 1)
      (while (and (not found) (not (eobp)))
        (let ((d (get-text-property (point) 'haystack-tree-depth)))
          (cond ((null d)    (forward-line 1))
                ((= d depth) (setq found (point)))
                ((> d depth) (forward-line 1))
                (t           (setq found 'none))))))
    (if (and found (not (eq found 'none)))
        (progn (goto-char found) (haystack--tree-move-to-term))
      (user-error "Haystack: no next sibling"))))

(defun haystack-tree-prev-sibling ()
  "Move point to the previous entry at the same depth."
  (interactive)
  (let ((depth (get-text-property (point) 'haystack-tree-depth))
        found)
    (unless depth (user-error "Haystack: no entry at point"))
    (save-excursion
      (forward-line -1)
      (while (and (not found) (not (bobp)))
        (let ((d (get-text-property (point) 'haystack-tree-depth)))
          (cond ((null d)    (forward-line -1))
                ((= d depth) (setq found (point)))
                ((> d depth) (forward-line -1))
                (t           (setq found 'none))))))
    (if (and found (not (eq found 'none)))
        (progn (goto-char found) (haystack--tree-move-to-term))
      (user-error "Haystack: no previous sibling"))))

(defun haystack--tree-roots ()
  "Return all root haystack buffers (those with no live parent)."
  (cl-remove-if
   (lambda (buf)
     (let ((parent (buffer-local-value 'haystack--parent-buffer buf)))
       (and parent (buffer-live-p parent))))
   (haystack--all-haystack-buffers)))

(defun haystack--display-term (term)
  "Return TERM suitable for display in buffer names and headers.
Collapses all whitespace runs (including newlines) to single spaces and
trims leading/trailing whitespace.  If the result exceeds 30 characters,
it is truncated to \"FIRST...LAST\" where FIRST and LAST are each 13
characters, keeping both ends of the term visible."
  (let* ((normalised (string-trim (replace-regexp-in-string "[ \t\n\r]+" " " term)))
         (len        (length normalised)))
    (if (<= len 30)
        normalised
      (concat (substring normalised 0 13) "..." (substring normalised (- len 13))))))

(defun haystack--tree-term-label (term negated filename literal regex)
  "Return TERM prefixed with its modifier characters for display.
Negation maps to !, filename to /, regex to ~, literal to =."
  (concat (when negated "!")
          (cond (filename "/")
                (regex    "~")
                (literal  "="))
          (haystack--display-term term)))

(defun haystack--tree-render-node (buf current-buf prefix connector depth)
  "Insert a rendered line for BUF, then recurse into its children.
PREFIX is the accumulated continuation art from ancestor nodes (e.g. \"│   \").
CONNECTOR is the branching art for this node (\"├── \", \"└── \", or \"\").
DEPTH drives the face chosen from `haystack-tree-depth-faces'.
Each line gets a `haystack-tree-buffer' text property pointing to BUF."
  (let* ((descriptor (buffer-local-value 'haystack--search-descriptor buf))
         (filters    (plist-get descriptor :filters))
         (term       (if filters
                         (let ((f (car (last filters))))
                           (haystack--tree-term-label
                            (plist-get f :term)
                            (plist-get f :negated)
                            (plist-get f :filename)
                            (plist-get f :literal)
                            (plist-get f :regex)))
                       (haystack--tree-term-label
                        (plist-get descriptor :root-term)
                        nil
                        (plist-get descriptor :root-filename)
                        (plist-get descriptor :root-literal)
                        (plist-get descriptor :root-regex))))
         (current-p  (eq buf current-buf))
         (term-face  (nth (mod depth (length haystack-tree-depth-faces))
                          haystack-tree-depth-faces))
         (line-start (point)))
    ;; Tree art — dimmed so it recedes behind the terms
    (let ((art-start (point)))
      (insert prefix connector)
      (put-text-property art-start (point) 'face 'shadow))
    ;; Term — depth-coloured, bold when current
    (let ((term-start (point)))
      (insert term)
      (put-text-property term-start (point) 'face
                         (if current-p (list 'bold term-face) term-face)))
    ;; Current-buffer marker
    (when current-p
      (insert "  ←"))
    (insert "\n")
    ;; Navigation text properties span the whole line (excluding newline)
    (put-text-property line-start (1- (point)) 'haystack-tree-buffer buf)
    (put-text-property line-start (1- (point)) 'haystack-tree-depth  depth)
    ;; Recurse into children
    (let* ((children (haystack--children-of buf))
           (n        (length children)))
      (cl-loop for child in children
               for i from 0
               do (haystack--tree-render-node
                   child current-buf
                   (concat prefix (if (= i (1- n)) "    " "│   "))
                   (if (= i (1- n)) "└── " "├── ")
                   (1+ depth))))))

;;;###autoload
(defun haystack-show-tree ()
  "Show all open haystack buffers as a navigable indented tree.
Each line shows the leaf search term with box-drawing connectors indicating
the chain structure.  Terms are coloured by depth using
`haystack-tree-depth-faces'.  The current buffer is marked with ←.
RET visits the buffer at point and closes the tree window.
q closes the tree window without navigating."
  (interactive)
  (let* ((current-buf (current-buffer))
         (roots       (haystack--tree-roots))
         (buf         (get-buffer-create "*haystack-tree*")))
    (with-current-buffer buf
      (let* ((inhibit-read-only t)
             (rule (concat ";;;;" (make-string 50 ?-))))
        (erase-buffer)
        (insert rule "\n")
        (if (null roots)
            (insert ";;;;  No open haystack buffers.\n")
          (insert "\n")
          (dolist (root roots)
            (haystack--tree-render-node root current-buf "" "" 0)
            (insert "\n")))
        (insert rule "\n")
        (haystack-tree-mode)
        (goto-char (point-min))
        (when roots (haystack-tree-next))))
    (select-window
     (display-buffer buf
                     '((display-buffer-below-selected)
                       (window-height . fit-window-to-buffer))))))

;;;; Buffer tree navigation

(defun haystack--all-haystack-buffers ()
  "Return live haystack results buffers belonging to `haystack-notes-directory'."
  (let ((notes-dir (and haystack-notes-directory
                        (expand-file-name haystack-notes-directory))))
    (cl-remove-if-not
     (lambda (buf)
       (and (buffer-local-value 'haystack--search-descriptor buf)
            (equal (buffer-local-value 'haystack--buffer-notes-dir buf)
                   notes-dir)))
     (buffer-list))))

(defun haystack--children-of (buf)
  "Return all live haystack buffers whose direct parent is BUF."
  (cl-remove-if-not
   (lambda (b)
     (eq (buffer-local-value 'haystack--parent-buffer b) buf))
   (haystack--all-haystack-buffers)))

(defun haystack--kill-subtree (buf)
  "Recursively kill BUF and all its descendant haystack buffers."
  (dolist (child (haystack--children-of buf))
    (haystack--kill-subtree child))
  (kill-buffer buf))

(defun haystack--assert-results-buffer ()
  "Signal a user-error if the current buffer is not a haystack results buffer."
  (unless (and (boundp 'haystack--search-descriptor)
               haystack--search-descriptor)
    (user-error "Haystack: not in a haystack results buffer")))

;;;###autoload
(defun haystack-go-up ()
  "Switch to the parent haystack buffer, if any.
Messages and does nothing if this is a root buffer or the parent is dead."
  (interactive)
  (haystack--assert-results-buffer)
  (cond
   ((null haystack--parent-buffer)
    (message "Haystack: this is a root buffer"))
   ((not (buffer-live-p haystack--parent-buffer))
    (message "Haystack: parent buffer is no longer live"))
   (t
    (switch-to-buffer haystack--parent-buffer))))

;;;###autoload
(defun haystack-go-down ()
  "Navigate to a child haystack buffer.
If there is exactly one child, switch to it directly.
If there are multiple children, open a picker buffer to choose from.
Signals a user-error if there are no children."
  (interactive)
  (haystack--assert-results-buffer)
  (let ((children (haystack--children-of (current-buffer))))
    (cond
     ((null children)
      (user-error "Haystack: no child buffers"))
     ((= 1 (length children))
      (switch-to-buffer (car children)))
     (t
      (haystack--show-children-picker children)))))

(define-derived-mode haystack-children-mode special-mode "Haystack-Children"
  "Major mode for the haystack children picker buffer.")

(define-key haystack-children-mode-map "n"         #'next-line)
(define-key haystack-children-mode-map "p"         #'previous-line)
(define-key haystack-children-mode-map (kbd "RET") #'haystack-children-visit)

(defun haystack-children-visit ()
  "Switch to the haystack buffer on the current line and close the picker."
  (interactive)
  (let ((buf (get-text-property (point) 'haystack-children-buffer)))
    (unless (and buf (buffer-live-p buf))
      (user-error "Haystack: no buffer at point"))
    (quit-window)
    (switch-to-buffer buf)))

(defun haystack--show-children-picker (children)
  "Display a picker buffer listing CHILDREN for selection."
  (let ((buf (get-buffer-create "*haystack-children*"))
        (rule (concat ";;;;" (make-string 50 ?-))))
    (with-current-buffer buf
      (let ((inhibit-read-only t))
        (erase-buffer)
        (insert rule "\n")
        (dolist (child children)
          (let* ((descriptor (buffer-local-value 'haystack--search-descriptor child))
                 (filters    (plist-get descriptor :filters))
                 (term       (if filters
                                 (let ((f (car (last filters))))
                                   (haystack--tree-term-label
                                    (plist-get f :term)    (plist-get f :negated)
                                    (plist-get f :filename) (plist-get f :literal)
                                    (plist-get f :regex)))
                               (haystack--tree-term-label
                                (plist-get descriptor :root-term) nil
                                (plist-get descriptor :root-filename)
                                (plist-get descriptor :root-literal)
                                (plist-get descriptor :root-regex))))
                 (start (point)))
            (insert term "\n")
            (put-text-property start (1- (point)) 'haystack-children-buffer child)))
        (insert rule "\n")
        (haystack-children-mode)
        ;; Land on first entry
        (goto-char (point-min))
        (forward-line 1)))
    (select-window
     (display-buffer buf
                     '((display-buffer-below-selected)
                       (window-height . fit-window-to-buffer))))))

;;;###autoload
(defun haystack-kill-node ()
  "Kill this haystack results buffer."
  (interactive)
  (haystack--assert-results-buffer)
  (kill-buffer (current-buffer)))

;;;###autoload
(defun haystack-kill-subtree ()
  "Kill this haystack buffer and all its descendants."
  (interactive)
  (haystack--assert-results-buffer)
  (haystack--kill-subtree (current-buffer)))

;;;###autoload
(defun haystack-kill-whole-tree ()
  "Kill all haystack buffers in this tree, starting from the root."
  (interactive)
  (haystack--assert-results-buffer)
  (let ((root (current-buffer)))
    (while (let ((parent (buffer-local-value 'haystack--parent-buffer root)))
             (and parent (buffer-live-p parent)))
      (setq root (buffer-local-value 'haystack--parent-buffer root)))
    (haystack--kill-subtree root)))

;;;###autoload
(defun haystack-kill-orphans ()
  "Kill haystack buffers whose parent is dead and have no living children.
Buffers with living children are left alone — they become de facto roots."
  (interactive)
  (let ((orphans (cl-remove-if-not
                  (lambda (buf)
                    (let ((parent (buffer-local-value 'haystack--parent-buffer buf)))
                      (and parent
                           (not (buffer-live-p parent))
                           (null (haystack--children-of buf)))))
                  (haystack--all-haystack-buffers))))
    (if (null orphans)
        (message "Haystack: no orphans to kill")
      (dolist (buf orphans)
        (kill-buffer buf))
      (message "Haystack: killed %d orphan buffer%s"
               (length orphans)
               (if (= 1 (length orphans)) "" "s")))))

;;;; MOC generator

(defvar haystack--last-moc nil
  "Loci from the most recent `haystack-copy-moc' call.
A list of (PATH . LINE) conses with absolute paths, one per unique file.
Format-agnostic; rendered at yank time by `haystack-yank-moc'.")

(defvar haystack--last-moc-chain nil
  "Search chain string from the most recent `haystack-copy-moc' call.
Used as a header comment in data-style MOC output.")

(defun haystack--extract-file-loci (text)
  "Return a list of (PATH . LINE) for the first match per file in TEXT.
Paths are expanded to absolute using `default-directory'.  Header lines
and any non-grep lines are skipped."
  (let ((seen  (make-hash-table :test #'equal))
        (loci  nil))
    (dolist (line (split-string text "\n" t))
      (when (string-match "\\`\\([^:]+\\):\\([0-9]+\\):" line)
        (let ((path (expand-file-name (match-string 1 line)))
              (lnum (string-to-number (match-string 2 line))))
          (unless (gethash path seen)
            (puthash path t seen)
            (push (cons path lnum) loci)))))
    (nreverse loci)))

(defun haystack--moc-format-for-extension (ext)
  "Return the MOC link format symbol for file extension EXT.
org → \\='org, md/markdown → \\='markdown, anything else → \\='code."
  (cond ((equal ext "org")               'org)
        ((member ext '("md" "markdown")) 'markdown)
        (t                               'code)))

(defconst haystack--comment-prefixes
  '(;; ;; line comments
    ("el" . ";;") ("lisp" . ";;") ("cl" . ";;") ("rkt" . ";;")
    ("scm" . ";;") ("ss" . ";;") ("clj" . ";;") ("cljs" . ";;")
    ("cljc" . ";;") ("fnl" . ";;") ("fennel" . ";;")
    ;; // line comments
    ("js" . "//") ("mjs" . "//") ("jsx" . "//")
    ("ts" . "//") ("tsx" . "//")
    ("rs" . "//") ("go" . "//") ("c" . "//") ("h" . "//")
    ("css" . "//") ("java" . "//") ("kt" . "//") ("swift" . "//")
    ;; # line comments
    ("py" . "#") ("rb" . "#") ("sh" . "#") ("bash" . "#")
    ("txt" . "#") ("toml" . "#") ("yaml" . "#") ("yml" . "#")
    ;; -- line comments
    ("lua" . "--") ("hs" . "--") ("sql" . "--") ("elm" . "--")
    ;; (* *) block comments — rendered as line prefix
    ("ml" . "(*") ("mli" . "(*"))
  "Alist mapping file extensions to their line comment prefix strings.")

(defun haystack--comment-prefix (ext)
  "Return the line comment prefix for EXT, or \"//\" as a fallback."
  (or (cdr (assoc ext haystack--comment-prefixes)) "//"))

(defun haystack--format-moc-code-comment (path ext)
  "Format PATH as a commented line using EXT's comment syntax.
Line numbers are omitted — this format is for reference, not navigation."
  (let ((prefix (haystack--comment-prefix ext))
        (title  (haystack--pretty-title (file-name-nondirectory path))))
    (format "%s %s — %s" prefix title path)))

(defun haystack-moc-quote-string (s)
  "Return S as a double-quoted string literal, escaping internal double-quotes.
Available as a helper for custom `haystack-moc-data-formatters' functions."
  (concat "\"" (replace-regexp-in-string "\"" "\\\\\"" s) "\""))

(defun haystack--moc-data-format-js (loci chain)
  "Format LOCI as a JavaScript/TypeScript const array.
CHAIN is the search chain string, included as a leading // comment."
  (let ((entries (mapcar (lambda (locus)
                           (format "  { title: %s, path: %s, line: %d },"
                                   (haystack-moc-quote-string
                                    (haystack--pretty-title
                                     (file-name-nondirectory (car locus))))
                                   (haystack-moc-quote-string (car locus))
                                   (cdr locus)))
                         loci)))
    (concat "// haystack: " chain "\n"
            "const haystack = [\n"
            (mapconcat #'identity entries "\n")
            "\n];")))

(defun haystack--moc-data-format-python (loci chain)
  "Format LOCI as a Python list of dicts.
CHAIN is the search chain string, included as a leading # comment."
  (let ((entries (mapcar (lambda (locus)
                           (format "    {\"title\": %s, \"path\": %s, \"line\": %d},"
                                   (haystack-moc-quote-string
                                    (haystack--pretty-title
                                     (file-name-nondirectory (car locus))))
                                   (haystack-moc-quote-string (car locus))
                                   (cdr locus)))
                         loci)))
    (concat "# haystack: " chain "\n"
            "haystack = [\n"
            (mapconcat #'identity entries "\n")
            "\n]")))

(defun haystack--moc-data-format-elisp (loci chain)
  "Format LOCI as an Emacs Lisp defvar holding a list of plists.
CHAIN is the search chain string, included as a leading ;; comment."
  (let ((entries (mapcar (lambda (locus)
                           (format "(:title %s :path %s :line %d)"
                                   (haystack-moc-quote-string
                                    (haystack--pretty-title
                                     (file-name-nondirectory (car locus))))
                                   (haystack-moc-quote-string (car locus))
                                   (cdr locus)))
                         loci)))
    (if (null (cdr entries))
        (concat ";; haystack: " chain "\n"
                "(defvar haystack\n"
                "  '(" (car entries) "))")
      (concat ";; haystack: " chain "\n"
              "(defvar haystack\n"
              "  '(" (car entries) "\n"
              (mapconcat (lambda (e) (concat "    " e)) (cdr entries) "\n")
              "))"))))

(defun haystack--moc-data-format-lua (loci chain)
  "Format LOCI as a Lua table of record tables.
CHAIN is the search chain string, included as a leading -- comment."
  (let ((entries (mapcar (lambda (locus)
                           (format "  { title = %s, path = %s, line = %d },"
                                   (haystack-moc-quote-string
                                    (haystack--pretty-title
                                     (file-name-nondirectory (car locus))))
                                   (haystack-moc-quote-string (car locus))
                                   (cdr locus)))
                         loci)))
    (concat "-- haystack: " chain "\n"
            "local haystack = {\n"
            (mapconcat #'identity entries "\n")
            "\n}")))

(defcustom haystack-moc-data-formatters
  '(("js"     . haystack--moc-data-format-js)
    ("mjs"    . haystack--moc-data-format-js)
    ("jsx"    . haystack--moc-data-format-js)
    ("ts"     . haystack--moc-data-format-js)
    ("tsx"    . haystack--moc-data-format-js)
    ("py"     . haystack--moc-data-format-python)
    ("el"     . haystack--moc-data-format-elisp)
    ("lisp"   . haystack--moc-data-format-elisp)
    ("cl"     . haystack--moc-data-format-elisp)
    ("rkt"    . haystack--moc-data-format-elisp)
    ("scm"    . haystack--moc-data-format-elisp)
    ("ss"     . haystack--moc-data-format-elisp)
    ("clj"    . haystack--moc-data-format-elisp)
    ("cljs"   . haystack--moc-data-format-elisp)
    ("cljc"   . haystack--moc-data-format-elisp)
    ("lua"    . haystack--moc-data-format-lua)
    ("fnl"    . haystack--moc-data-format-lua)
    ("fennel" . haystack--moc-data-format-lua))
  "Alist mapping file extensions to data-style MOC formatter functions.
Each function receives (LOCI CHAIN) and must return a formatted string:
  LOCI  — list of (PATH . LINE) conses, one per result file
  CHAIN — the search chain string (e.g. \"root=rust > filter=async\")

To add a language, push a new entry:
  (push \\='(\"rb\" . my-ruby-moc-formatter) haystack-moc-data-formatters)

`haystack-moc-quote-string' is available as a helper for building
double-quoted string literals in formatter output.

Extensions not present in this alist fall back to comment-style output
when `haystack-moc-code-style' is \\='data."
  :type '(alist :key-type (string :tag "Extension")
                :value-type (function :tag "Formatter"))
  :group 'haystack)

(defun haystack--format-moc-data-block (loci chain ext)
  "Return a structured data block for LOCI using the formatter for EXT.
Looks up EXT in `haystack-moc-data-formatters'.  Falls back to one
comment line per file when no formatter is registered for EXT."
  (let ((formatter (cdr (assoc ext haystack-moc-data-formatters))))
    (if formatter
        (funcall formatter loci chain)
      (mapconcat (lambda (locus)
                   (haystack--format-moc-code-comment (car locus) ext))
                 loci "\n"))))

(defun haystack--format-moc-link (path lnum format ext)
  "Return a formatted link string for PATH at line LNUM.
FORMAT is \\='org, \\='markdown, or \\='code.  EXT is the target file extension,
used to select comment syntax.  The \\='data code style is handled at the
block level in `haystack-yank-moc' — this function always uses comment style
for code files."
  (let ((title (haystack--pretty-title (file-name-nondirectory path))))
    (pcase format
      ('org      (format "[[file:%s::%d][%s]]" path lnum title))
      ('markdown (format "[%s](%s#L%d)" title path lnum))
      ('code     (haystack--format-moc-code-comment path ext))
      (_ (user-error "Haystack: unknown moc format: %s" format)))))

;;;###autoload
(defun haystack-copy-moc ()
  "Copy the current results buffer as a MOC to `haystack--last-moc'.
Stores one (PATH . LINE) entry per file (first match line).
Use `haystack-yank-moc' to insert the links into a target buffer."
  (interactive)
  (haystack--assert-results-buffer)
  (let* ((loci (haystack--extract-file-loci (buffer-string)))
         (n    (length loci)))
    (when (zerop n)
      (user-error "Haystack: no results to copy"))
    (setq haystack--last-moc loci)
    (setq haystack--last-moc-chain
          (when (bound-and-true-p haystack--search-descriptor)
            (haystack--descriptor-chain-string haystack--search-descriptor)))
    (message "Haystack: copied %d file link%s" n (if (= 1 n) "" "s"))))

;;;###autoload
(defun haystack-yank-moc ()
  "Insert MOC links at point, formatted for the current buffer's file type.
Uses the loci stored by the last `haystack-copy-moc'.  Format is
determined by the current buffer's file extension (org, md/markdown, or
plaintext for everything else).  Also pushes the formatted text to the
kill ring."
  (interactive)
  (unless haystack--last-moc
    (user-error "Haystack: nothing copied — run `haystack-copy-moc' first"))
  (let* ((ext  (or (and (buffer-file-name)
                        (file-name-extension (buffer-file-name)))
                   haystack-default-extension))
         (fmt  (haystack--moc-format-for-extension ext))
         (text (if (and (eq fmt 'code) (eq haystack-moc-code-style 'data))
                   (haystack--format-moc-data-block
                    haystack--last-moc
                    (or haystack--last-moc-chain "search")
                    ext)
                 (mapconcat (lambda (locus)
                              (haystack--format-moc-link
                               (car locus) (cdr locus) fmt ext))
                            haystack--last-moc
                            "\n"))))
    (kill-new text)
    (insert text "\n")))

;;;; Frecency engine

(defcustom haystack-frecency-save-interval 60
  "Idle seconds before frecency data is flushed to disk.
When nil, data is written immediately on every buffer visit instead of
being deferred.  Data is always flushed on Emacs shutdown regardless of
this setting.  Changing this value takes effect immediately."
  :type '(choice (integer :tag "Idle seconds")
                 (const   :tag "Save immediately (no timer)" nil))
  :set (lambda (sym val)
         (set-default sym val)
         (when (fboundp 'haystack--frecency-setup-timer)
           (haystack--frecency-setup-timer)))
  :group 'haystack)

(defvar haystack--frecency-data nil
  "In-memory frecency alist.
Each entry: (CHAIN :count N :last-access FLOAT-TIME) where CHAIN is a
list of prefixed term strings derived from the search descriptor.
Persisted to `.haystack-frecency.el' in the notes directory.")

(defvar haystack--frecency-dirty nil
  "Non-nil when `haystack--frecency-data' has unsaved changes.")

(defvar haystack--frecency-timer nil
  "Idle timer that flushes frecency data; interval set by `haystack-frecency-save-interval'.")

;;;; Demo mode state

(defvar haystack--demo-active nil
  "Non-nil while Haystack demo mode is active.")

(defvar haystack--demo-temp-dir nil
  "Absolute path to the temporary demo notes directory.")

(defvar haystack--demo-saved-state nil
  "Plist of state saved before demo start; restored by `haystack-demo-stop'.")

(defun haystack--frecency-file ()
  "Return the absolute path of the frecency data file."
  (expand-file-name ".haystack-frecency.el" haystack-notes-directory))

(defun haystack--load-frecency ()
  "Load frecency data from disk into `haystack--frecency-data'.
On failure: warn, set nil, continue."
  (setq haystack--frecency-data
        (condition-case err
            (let ((path (haystack--frecency-file)))
              (if (file-exists-p path)
                  (with-temp-buffer
                    (insert-file-contents path)
                    (read (current-buffer)))
                nil))
          (error
           (message "Haystack: failed to load frecency: %s"
                    (error-message-string err))
           nil))))

(defun haystack--frecency-flush ()
  "Write `haystack--frecency-data' to disk if dirty."
  (when (and haystack--frecency-dirty
             haystack-notes-directory
             (file-directory-p haystack-notes-directory))
    (condition-case err
        (progn
          (with-temp-file (haystack--frecency-file)
            (let ((print-level nil)
                  (print-length nil))
              (pp haystack--frecency-data (current-buffer))))
          (setq haystack--frecency-dirty nil))
      (error
       (message "Haystack: failed to save frecency: %s"
                (error-message-string err))))))

(defun haystack--frecency-setup-timer ()
  "Set up (or cancel) the frecency idle timer based on `haystack-frecency-save-interval'.
Always registers `haystack--frecency-flush' on `kill-emacs-hook'."
  (when haystack--frecency-timer
    (cancel-timer haystack--frecency-timer)
    (setq haystack--frecency-timer nil))
  (when haystack-frecency-save-interval
    (setq haystack--frecency-timer
          (run-with-idle-timer haystack-frecency-save-interval
                               t #'haystack--frecency-flush)))
  (add-hook 'kill-emacs-hook #'haystack--frecency-flush))

(defun haystack--frecency-chain-key (descriptor)
  "Return the frecency chain key for DESCRIPTOR.
A list of prefixed term strings, e.g. (\"rust\" \"async\" \"!cargo\").
Prefix characters are preserved; the root term is first."
  (let* ((root-term (plist-get descriptor :root-term))
         (root-pfx  (cond ((plist-get descriptor :root-filename) "/")
                          ((plist-get descriptor :root-literal)  "=")
                          ((plist-get descriptor :root-regex)    "~")
                          (t "")))
         (filter-keys
          (mapcar (lambda (f)
                    (concat (if (plist-get f :negated) "!" "")
                            (cond ((plist-get f :filename) "/")
                                  ((plist-get f :literal)  "=")
                                  ((plist-get f :regex)    "~")
                                  (t ""))
                            (plist-get f :term)))
                  (plist-get descriptor :filters))))
    (cons (concat root-pfx root-term) filter-keys)))

(defun haystack--frecency-record (descriptor)
  "Record or update a frecency entry for DESCRIPTOR.
Loads data from disk on first call.  Sets `haystack--frecency-dirty'."
  (unless haystack--frecency-data
    (haystack--load-frecency))
  (let* ((key      (haystack--frecency-chain-key descriptor))
         (now      (float-time))
         (existing (assoc key haystack--frecency-data)))
    (if existing
        (setcdr existing
                (list :count      (1+ (plist-get (cdr existing) :count))
                      :last-access now))
      (push (cons key (list :count 1 :last-access now))
            haystack--frecency-data))
    (setq haystack--frecency-dirty t)
    (when (null haystack-frecency-save-interval)
      (haystack--frecency-flush))))

(defun haystack--frecency-score (entry)
  "Return the frecency score for ENTRY: count / max(days-since-access, 1)."
  (let* ((props   (cdr entry))
         (count   (plist-get props :count))
         (last-ts (plist-get props :last-access))
         (days    (/ (- (float-time) last-ts) 86400.0)))
    (/ (float count) (max days 1.0))))

(defun haystack--frecent-leaf-p (entry all-entries)
  "Return non-nil if ENTRY is a leaf among ALL-ENTRIES.
An entry is a leaf if no other entry with a strictly higher score has a
chain that starts with this entry's chain — i.e. this is not merely an
intermediate step toward a more-visited deeper search."
  (let ((chain (car entry))
        (score (haystack--frecency-score entry)))
    (not (cl-some
          (lambda (other)
            (and (not (equal (car other) chain))
                 (> (haystack--frecency-score other) score)
                 (let ((oc (car other)))
                   (and (> (length oc) (length chain))
                        (equal (cl-subseq oc 0 (length chain)) chain)))))
          all-entries))))

(defun haystack--frecent-leaves (entries)
  "Return only the leaf entries from ENTRIES."
  (cl-remove-if-not (lambda (e) (haystack--frecent-leaf-p e entries))
                    entries))

;;; Frecency diagnostic buffer mode

(defvar-local haystack--frecent-sort-order 'score
  "Current sort order for *haystack-frecent*: `score', `frequency', or `recency'.")

(defvar-local haystack--frecent-leaf-only nil
  "When non-nil, *haystack-frecent* shows only leaf entries.")

(defun haystack--frecent-sort-entries (entries order)
  "Return ENTRIES sorted by ORDER (`score', `frequency', or `recency')."
  (sort (copy-sequence entries)
        (pcase order
          ('score     (lambda (a b) (> (haystack--frecency-score a)
                                       (haystack--frecency-score b))))
          ('frequency (lambda (a b) (> (plist-get (cdr a) :count)
                                       (plist-get (cdr b) :count))))
          (_          (lambda (a b) (> (plist-get (cdr a) :last-access)
                                       (plist-get (cdr b) :last-access)))))))

(defun haystack--frecent-render ()
  "Redraw *haystack-frecent* using the current sort order and leaf filter."
  (let* ((inhibit-read-only t)
         (base       (if haystack--frecent-leaf-only
                         (haystack--frecent-leaves haystack--frecency-data)
                       haystack--frecency-data))
         (entries    (haystack--frecent-sort-entries base haystack--frecent-sort-order))
         (sort-label (pcase haystack--frecent-sort-order
                       ('score     "score")
                       ('frequency "frequency")
                       (_          "recency")))
         (view-label (if haystack--frecent-leaf-only "leaf" "all")))
    (erase-buffer)
    (insert ";;;;------------------------------------------------------------\n")
    (insert (format ";;;;  Haystack — frecent searches  [sort: %s  view: %s  |  ?=help]\n"
                    sort-label view-label))
    (insert ";;;;------------------------------------------------------------\n\n")
    (if (null entries)
        (insert "  (no entries recorded yet)\n")
      (insert (format "  %-8s  %-6s  %-6s  %s\n" "score" "visits" "days" "chain"))
      (insert "  --------  ------  ------  ----\n")
      (dolist (entry entries)
        (let* ((props      (cdr entry))
               (score      (haystack--frecency-score entry))
               (count      (plist-get props :count))
               (days       (/ (- (float-time) (plist-get props :last-access)) 86400.0))
               (chain-str  (mapconcat #'identity (car entry) " > "))
               (line-start (point)))
          (insert (format "  %8.2f  %6d  %6.1f  %s\n" score count days chain-str))
          (put-text-property line-start (point)
                             'haystack-frecent-chain (car entry)))))
    (insert "\n;;;;------------------------------------------------------------\n")))

(defun haystack-frecent-toggle-sort ()
  "Cycle sort order: score → frequency → recency → score."
  (interactive)
  (setq haystack--frecent-sort-order
        (pcase haystack--frecent-sort-order
          ('score     'frequency)
          ('frequency 'recency)
          (_          'score)))
  (haystack--frecent-render)
  (goto-char (point-min))
  (message "Haystack frecent: sorting by %s"
           (symbol-name haystack--frecent-sort-order)))

(defun haystack-frecent-sort-score ()
  "Sort the frecency buffer by score (visit count / days)."
  (interactive)
  (setq haystack--frecent-sort-order 'score)
  (haystack--frecent-render)
  (goto-char (point-min))
  (message "Haystack frecent: sorting by score"))

(defun haystack-frecent-sort-frequency ()
  "Sort the frecency buffer by visit count."
  (interactive)
  (setq haystack--frecent-sort-order 'frequency)
  (haystack--frecent-render)
  (goto-char (point-min))
  (message "Haystack frecent: sorting by frequency"))

(defun haystack-frecent-sort-recency ()
  "Sort the frecency buffer by most recently accessed."
  (interactive)
  (setq haystack--frecent-sort-order 'recency)
  (haystack--frecent-render)
  (goto-char (point-min))
  (message "Haystack frecent: sorting by recency"))

(defun haystack-frecent-toggle-leaf ()
  "Toggle between showing all entries and leaf-only entries.
A leaf entry is one where no deeper chain with a higher score exists."
  (interactive)
  (setq haystack--frecent-leaf-only (not haystack--frecent-leaf-only))
  (haystack--frecent-render)
  (goto-char (point-min))
  (message "Haystack frecent: showing %s"
           (if haystack--frecent-leaf-only "leaves only" "all entries")))

(defun haystack-frecent-kill-entry ()
  "Kill the frecency entry at point after `y-or-n-p' confirmation."
  (interactive)
  (let ((chain (get-text-property (point) 'haystack-frecent-chain)))
    (unless chain
      (user-error "Haystack: no frecency entry at point"))
    (when (y-or-n-p (format "Kill frecency entry '%s'? "
                             (mapconcat #'identity chain " > ")))
      (setq haystack--frecency-data
            (cl-remove-if (lambda (e) (equal (car e) chain))
                          haystack--frecency-data))
      (setq haystack--frecency-dirty t)
      (haystack--frecent-render)
      (message "Haystack: removed frecency entry"))))

(defun haystack--frecent-help-key (cmd)
  "Return a human-readable key string for CMD in `haystack-frecent-mode-map'."
  (let ((keys (where-is-internal cmd haystack-frecent-mode-map)))
    (if keys (key-description (car keys)) "unbound")))

(defun haystack--frecent-help-content ()
  "Return the formatted string for the frecency help buffer."
  (let ((rule (concat ";;;;" (make-string 50 ?-)))
        (key  #'haystack--frecent-help-key))
    (mapconcat #'identity
               (list rule
                     ";;;;  Haystack — frecent buffer commands"
                     rule
                     ""
                     ";;;;  Sort"
                     (format ";;;;    %-8s  cycle sort order"           (funcall key 'haystack-frecent-toggle-sort))
                     (format ";;;;    %-8s  sort by score (frecency)"   (funcall key 'haystack-frecent-sort-score))
                     (format ";;;;    %-8s  sort by frequency (visits)" (funcall key 'haystack-frecent-sort-frequency))
                     (format ";;;;    %-8s  sort by recency"            (funcall key 'haystack-frecent-sort-recency))
                     ""
                     ";;;;  View"
                     (format ";;;;    %-8s  toggle all / leaf-only"     (funcall key 'haystack-frecent-toggle-leaf))
                     ""
                     ";;;;  Entries"
                     (format ";;;;    %-8s  kill entry at point"        (funcall key 'haystack-frecent-kill-entry))
                     ""
                     ";;;;    q         close this window"
                     rule)
               "\n")))

(defun haystack-frecent-help ()
  "Show a popup window listing all frecency buffer commands."
  (interactive)
  (let ((buf (get-buffer-create "*haystack-frecent-help*")))
    (with-current-buffer buf
      (let ((inhibit-read-only t))
        (erase-buffer)
        (insert (haystack--frecent-help-content))
        (special-mode)
        (goto-char (point-min))))
    (select-window
     (display-buffer buf
                     '((display-buffer-below-selected)
                       (window-height . fit-window-to-buffer))))))

(define-derived-mode haystack-frecent-mode special-mode "Haystack-Frecent"
  "Major mode for the Haystack frecency diagnostic buffer.
\\{haystack-frecent-mode-map}"
  :group 'haystack)

(define-key haystack-frecent-mode-map "s" #'haystack-frecent-toggle-sort)
(define-key haystack-frecent-mode-map "v" #'haystack-frecent-toggle-leaf)
(define-key haystack-frecent-mode-map "t" #'haystack-frecent-sort-score)
(define-key haystack-frecent-mode-map "f" #'haystack-frecent-sort-frequency)
(define-key haystack-frecent-mode-map "r" #'haystack-frecent-sort-recency)
(define-key haystack-frecent-mode-map "k" #'haystack-frecent-kill-entry)
(define-key haystack-frecent-mode-map "?" #'haystack-frecent-help)

;;;###autoload
(defun haystack-describe-frecent ()
  "Display all recorded frecency entries in a navigable buffer.
Columns: score, visits, days since last access, search chain.
\\<haystack-frecent-mode-map>\\[haystack-frecent-sort-score] score  \
\\[haystack-frecent-sort-frequency] frequency  \
\\[haystack-frecent-sort-recency] recency  \
\\[haystack-frecent-kill-entry] kill entry  \
\\[haystack-frecent-help] help"
  (interactive)
  (haystack--load-frecency)
  (with-current-buffer (get-buffer-create "*haystack-frecent*")
    (haystack-frecent-mode)
    (unless (local-variable-p 'haystack--frecent-sort-order)
      (setq-local haystack--frecent-sort-order 'score))
    (haystack--frecent-render)
    (goto-char (point-min))
    (pop-to-buffer (current-buffer))))

(defun haystack--frecency-replay (chain)
  "Replay CHAIN and display a leaf results buffer.
CHAIN is a list of prefixed term strings.  Each step is run internally;
only the final buffer is kept.  Its parent is set to nil so it stands
alone in the tree."
  (let ((current-buf nil))
    (cl-letf (((symbol-function 'pop-to-buffer)    (lambda (buf &rest _) buf))
              ((symbol-function 'switch-to-buffer) (lambda (buf &rest _) buf)))
      (setq current-buf (haystack-run-root-search (car chain)))
      (dolist (filter-term (cdr chain))
        (let ((next-buf (with-current-buffer current-buf
                          (haystack-filter-further filter-term))))
          (kill-buffer current-buf)
          (setq current-buf next-buf))))
    (with-current-buffer current-buf
      (setq-local haystack--parent-buffer nil))
    (pop-to-buffer current-buf)
    current-buf))

;;;###autoload
(defun haystack-frecent (&optional all)
  "Select a frecent search chain via `completing-read' and replay it.
Entries are sorted by score (visit count / days since last access).
Each entry's score is shown as a completion annotation.
By default only leaf entries are shown — chains that are not merely an
intermediate step toward a more-visited deeper search.  With a prefix
argument ALL, show every recorded chain."
  (interactive "P")
  (haystack--load-frecency)
  (unless haystack--frecency-data
    (user-error "Haystack: no frecent searches recorded yet"))
  (let* ((pool        (if all
                          haystack--frecency-data
                        (haystack--frecent-leaves haystack--frecency-data)))
         (_           (unless pool
                        (user-error "Haystack: no leaf entries (use C-u to show all)")))
         (sorted      (sort (copy-sequence pool)
                            (lambda (a b) (> (haystack--frecency-score a)
                                             (haystack--frecency-score b)))))
         (display-map (make-hash-table :test #'equal))
         (candidates  (mapcar (lambda (entry)
                                (let ((str (mapconcat #'identity (car entry) " > ")))
                                  (puthash str (car entry) display-map)
                                  str))
                              sorted))
         (annot       (lambda (str)
                        (when-let* ((chain (gethash str display-map))
                                    (entry (assoc chain haystack--frecency-data)))
                          (format "  %.1f" (haystack--frecency-score entry)))))
         (table       (lambda (string pred action)
                        (if (eq action 'metadata)
                            `(metadata (annotation-function . ,annot))
                          (complete-with-action action candidates string pred))))
         (prompt      (if all "Haystack frecent (all): " "Haystack frecent: "))
         (choice      (completing-read prompt table nil t)))
    (haystack--frecency-replay (gethash choice display-map))))

;;;; Demo mode

(defun haystack--demo-package-dir ()
  "Return the directory containing haystack.el."
  (file-name-directory (or load-file-name
                           (locate-library "haystack")
                           (buffer-file-name))))

;;;###autoload
(defun haystack-demo ()
  "Start Haystack demo mode using the bundled sample corpus.
Your `haystack-notes-directory' is temporarily shadowed by a fresh
copy of the bundled demo corpus in a temporary directory.  You can
search, filter, create notes, and use every Haystack feature normally.
All changes are isolated — nothing touches your real notes.

A warning banner appears in every results buffer header while demo
mode is active.  Call `haystack-demo-stop' to end the session;
this kills all demo buffers, deletes the temporary directory, and
restores your previous `haystack-notes-directory'."
  (interactive)
  (when haystack--demo-active
    (user-error "Haystack demo is already running — call `haystack-demo-stop' first"))
  (let* ((pkg-dir (haystack--demo-package-dir))
         (src-dir (expand-file-name "demo/notes" pkg-dir)))
    (unless (file-directory-p src-dir)
      (user-error "Haystack: demo corpus not found at %s" src-dir))
    (let ((temp-dir (make-temp-file "haystack-demo-" t)))
      (let ((exit (call-process "cp" nil nil nil "-r"
                                (concat (file-name-as-directory src-dir) ".")
                                temp-dir)))
        (unless (zerop exit)
          (delete-directory temp-dir t)
          (user-error "Haystack: failed to copy demo corpus to %s" temp-dir)))
      (setq haystack--demo-saved-state
            (list :notes-dir   haystack-notes-directory
                  :frecency    (copy-sequence haystack--frecency-data)
                  :exp-groups  (copy-sequence haystack--expansion-groups)))
      (setq haystack--demo-temp-dir  temp-dir
            haystack--demo-active    t
            haystack-notes-directory temp-dir)
      (haystack--load-expansion-groups)
      (haystack--load-frecency)
      (message (concat "Haystack demo active.\n"
                       "Notes directory: %s\n"
                       "Call `haystack-demo-stop' when done — all changes will be discarded.")
               temp-dir))))

;;;###autoload
(defun haystack-demo-stop ()
  "Stop Haystack demo mode and restore your previous configuration.
Kills all Haystack results buffers and any file-visiting buffers in the
temporary demo directory, then deletes that directory and restores your
previous `haystack-notes-directory'."
  (interactive)
  (unless haystack--demo-active
    (user-error "Haystack demo is not running"))
  ;; Kill only the haystack results buffers that belong to the demo directory.
  (let ((demo-dir (expand-file-name haystack--demo-temp-dir)))
    (dolist (buf (buffer-list))
      (when (and (buffer-live-p buf)
                 (equal (buffer-local-value 'haystack--buffer-notes-dir buf)
                        demo-dir))
        (kill-buffer buf))))
  ;; Kill file-visiting buffers inside the temp dir.
  (when haystack--demo-temp-dir
    (let ((prefix (file-name-as-directory haystack--demo-temp-dir)))
      (dolist (buf (buffer-list))
        (when (buffer-live-p buf)
          (let ((fname (buffer-file-name buf)))
            (when (and fname (string-prefix-p prefix (expand-file-name fname)))
              (kill-buffer buf)))))))
  ;; Restore saved state.
  (let ((saved haystack--demo-saved-state))
    (setq haystack-notes-directory     (plist-get saved :notes-dir)
          haystack--frecency-data      (plist-get saved :frecency)
          haystack--expansion-groups   (plist-get saved :exp-groups)))
  ;; Clean up.
  (let ((temp-dir haystack--demo-temp-dir))
    (setq haystack--demo-active      nil
          haystack--demo-temp-dir    nil
          haystack--demo-saved-state nil)
    (when (and temp-dir (file-directory-p temp-dir))
      (delete-directory temp-dir t)))
  (message "Haystack demo stopped.  Your notes directory has been restored."))

;;;; Global prefix map

(defvar haystack-prefix-map (make-sparse-keymap)
  "Prefix keymap for global haystack commands.
Not bound by default.  Add to your config, e.g.:
  (global-set-key (kbd \"C-c h\") haystack-prefix-map)")
(define-key haystack-prefix-map "s" #'haystack-run-root-search)
(define-key haystack-prefix-map "r" #'haystack-search-region)
(define-key haystack-prefix-map "n" #'haystack-new-note)
(define-key haystack-prefix-map "y" #'haystack-yank-moc)
(define-key haystack-prefix-map "t" #'haystack-show-tree)
(define-key haystack-prefix-map "f" #'haystack-frecent)
(define-key haystack-prefix-map "D" #'haystack-demo)

(haystack--frecency-setup-timer)

(provide 'haystack)
;;; haystack.el ends here
