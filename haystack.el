;;; haystack.el --- Search-first knowledge management -*- lexical-binding: t -*-

;; Author: wv
;; Version: 0.11.0
;; Package-Requires: ((emacs "28.1"))
;; Keywords: tools, files, outlines
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
(require 'org)

;;;; Customization

(defgroup haystack nil
  "Search-first knowledge management."
  :group 'tools
  :prefix "haystack-")

(defcustom haystack-notes-directory nil
  "Root directory for Haystack notes.  Must be set before use."
  :type '(choice (const :tag "Not set" nil) directory)
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
  :type '(integer :min 1)
  :group 'haystack)


(defcustom haystack-moc-code-style 'comment
  "How MOC links are formatted when yanking into code files.
  data    — language-appropriate structured data block (e.g. a JS array);
            falls back to `comment' for extensions with no data formatter
  comment — line prefixed with the language's comment syntax"
  :type '(choice (const :tag "Structured data" data)
                 (const :tag "Commented lines" comment))
  :group 'haystack)

(defcustom haystack-composite-max-lines 300
  "Maximum number of lines included per source file in a composite.
When a file exceeds this limit, a window of this many lines centred on
the first search match is used instead, with ellipsis markers at the
truncated ends.  Set to nil for no limit (entire file always included)."
  :type '(choice (integer :min 1) (const :tag "No limit" nil))
  :group 'haystack)

(defcustom haystack-composite-all-matches nil
  "When non-nil, include one section per match line rather than per file.
The default (nil) includes each source file once, centred on its first
match.  When t, files that appear multiple times in the results buffer
get a separate section for each match line."
  :type 'boolean
  :group 'haystack)

(defcustom haystack-composite-protect t
  "When non-nil, intercept manual saves in composite buffers.
Saving a composite buffer directly (\\[save-buffer]) will prompt the
user to create a new note with the buffer contents instead, keeping the
composite file machine-generated.  Set to nil to allow direct saves."
  :type 'boolean
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

(defvar-local haystack--mentions-origin nil
  "Absolute path of the note that triggered this mentions search.
Non-nil only in results buffers created by `haystack-find-mentions' and
their `haystack-filter-further' descendants.  This is the canonical flag
for mentions trees; the *haystack-ref: buffer-name prefix is cosmetic.")

(defvar-local haystack--compose-descriptor nil
  "Search descriptor for the current composite staging buffer.")

(defvar-local haystack--compose-loci nil
  "List of (PATH . LINE) pairs used to generate the current composite buffer.")

;;;; Hooks

(defvar haystack-after-create-hook nil
  "Hook run after a note is created via `haystack-new-note'.")

;;;; Internal utilities

(defun haystack--validate-notes-directory ()
  "Signal a `user-error' if `haystack-notes-directory' is unset."
  (unless haystack-notes-directory
    (user-error "Haystack: `haystack-notes-directory' is not set")))

(defun haystack--assert-notes-directory ()
  "Signal an error if `haystack-notes-directory' is unset or missing."
  (haystack--validate-notes-directory)
  (unless (file-directory-p haystack-notes-directory)
    (user-error "Haystack: notes directory does not exist: %s"
                haystack-notes-directory)))

(defun haystack--ensure-notes-directory ()
  "Ensure `haystack-notes-directory' is set and exists.
If the directory is missing, offer to create it.  Signals a
`user-error' if unset or if the user declines to create it."
  (haystack--validate-notes-directory)
  (unless (file-directory-p haystack-notes-directory)
    (if (y-or-n-p (format "Directory %s does not exist.  Create it? "
                          haystack-notes-directory))
        (make-directory haystack-notes-directory t)
      (user-error "Haystack: notes directory does not exist: %s"
                  haystack-notes-directory))))

;;;; Creation engine

;;; Frontmatter generators — one function per comment style.
;;; Each takes TITLE (string) and returns a complete frontmatter block
;;; including the haystack-end-frontmatter sentinel on the final line.
;;;
;;; Org-mode and Markdown use unique formats defined manually below.
;;; All other styles are generated by `haystack-define-frontmatter'.

(defvar haystack--frontmatter-registry nil
  "Alist of registered frontmatter comment styles.
Each entry is (NAME . PLIST) with keys:
  :prefix     — comment opening token (e.g. \"//\" or \"/*\")
  :suffix     — comment closing token, or \"\" for line comments
  :extensions — list of file extension strings (documentation only)

Populated by `haystack-define-frontmatter' calls at load time.  Do not
modify directly.  File reload is safe: each macro call uses `setf
(alist-get ...)' which updates existing entries in place rather than
accumulating duplicates.")

(cl-defmacro haystack-define-frontmatter (name &key prefix (suffix "") extensions)
  "Define a frontmatter generator for comment style NAME.
Registers NAME in `haystack--frontmatter-registry' and defines
`haystack--frontmatter-NAME' as its generator function.

The generated function takes TITLE and returns a frontmatter block:
  PREFIX title: TITLE SUFFIX
  PREFIX date: DATE SUFFIX
  PREFIX %%% haystack-end-frontmatter %%% SUFFIX

Keyword arguments:
  :prefix     — comment opening token (e.g. \"//\", \"/*\", \"<!--\")
  :suffix     — comment closing token (default \"\"; use \" */\" for C block)
  :extensions — list of extensions this style covers (for documentation and
                registry introspection; register extensions in
                `haystack-frontmatter-functions' to activate them)"
  (declare (indent defun))
  (let ((fn-name (intern (format "haystack--frontmatter-%s" name))))
    `(progn
       (setf (alist-get ',name haystack--frontmatter-registry)
             (list :prefix ,prefix :suffix ,suffix :extensions ',extensions))
       (defun ,fn-name (title)
         ,(format "Return frontmatter for TITLE using %s comments." name)
         (concat ,prefix " title: " title ,suffix "\n"
                 ,prefix " date: " (format-time-string "%Y-%m-%d") ,suffix "\n"
                 ,prefix " %%% haystack-end-frontmatter %%%" ,suffix "\n\n")))))

;;; Unique-format styles (do not fit the PREFIX/SUFFIX pattern)

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

;;; Comment-style generators (generated via haystack-define-frontmatter)

(haystack-define-frontmatter slash
  :prefix "//"
  :extensions ("js" "mjs" "ts" "tsx" "rs" "go"))

(haystack-define-frontmatter hash
  :prefix "#"
  :extensions ("txt" "py" "rb" "sh" "bash"))

(haystack-define-frontmatter semi
  :prefix ";;"
  :extensions ("el" "lisp" "cl" "rkt" "scm" "ss" "clj" "cljs" "cljc" "fnl" "fennel"))

(haystack-define-frontmatter dash
  :prefix "--"
  :extensions ("lua" "hs" "sql"))

(haystack-define-frontmatter c-block
  :prefix "/*"
  :suffix " */"
  :extensions ("c" "h" "css"))

(haystack-define-frontmatter html-block
  :prefix "<!--"
  :suffix " -->"
  :extensions ("html" "htm"))

(haystack-define-frontmatter ml-block
  :prefix "(*"
  :suffix " *)"
  :extensions ("ml" "mli"))

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

(defun haystack--note-slug (filename)
  "Return the slug component of FILENAME: basename minus timestamp and extension.
Unlike `haystack--pretty-title', hyphens are preserved (not converted to
spaces), making this suitable for use as a search term."
  (let* ((base (file-name-sans-extension (file-name-nondirectory filename))))
    (if (string-match "\\`[0-9]\\{14\\}-" base)
        (substring base (match-end 0))
      base)))

(defun haystack--timestamp ()
  "Return the current time as a YYYYMMDDHHMMSS string."
  (format-time-string "%Y%m%d%H%M%S"))

(defun haystack--sanitize-slug (slug)
  "Return SLUG safe for use as a filename component.
Leading and trailing whitespace is trimmed.  Any run of whitespace is
replaced by a single hyphen.  Characters unsafe in filenames
(/ \\ : * ? \" < > |) are removed."
  (thread-last slug
    string-trim
    (replace-regexp-in-string "[[:space:]]+" "-")
    (replace-regexp-in-string "[/\\\\:*?\"<>|]" "")))

;;;###autoload
(defun haystack--create-note-file ()
  "Prompt for slug and extension, create the timestamped note file, and open it.
Writes frontmatter and (when demo mode is active) a demo banner.
Positions point at the end of the buffer.  Returns the new file path.
Running `haystack-after-create-hook' is the caller's responsibility."
  (let* ((slug     (haystack--sanitize-slug (read-string "Slug: ")))
         (_        (when (string-empty-p slug)
                     (user-error "Haystack: slug is empty after sanitization")))
         (ext      (read-string (format "Extension (default %s): " haystack-default-extension)
                                nil nil haystack-default-extension))
         (filename (concat (haystack--timestamp) "-" slug "." ext))
         (path     (expand-file-name filename haystack-notes-directory))
         (title    (haystack--pretty-title filename))
         (fm       (haystack--frontmatter title ext)))
    (when (file-exists-p path)
      (user-error "Haystack: file already exists: %s" path))
    (with-temp-file path
      (when fm (insert fm))
      (when haystack--demo-active
        (insert "HAYSTACK DEMO NOTE — this file will be deleted when haystack-demo-stop is called.\n\n")))
    (find-file path)
    (goto-char (point-max))
    path))

(defun haystack-new-note ()
  "Create a new timestamped note in `haystack-notes-directory'.
Prompts for a slug and file extension, writes frontmatter, opens the
file, and runs `haystack-after-create-hook'."
  (interactive)
  (haystack--ensure-notes-directory)
  (haystack--create-note-file)
  (run-hooks 'haystack-after-create-hook))

;;;###autoload
(defun haystack-new-note-with-moc ()
  "Create a new note and insert the current results MOC into it.
Must be called from a haystack results buffer.  Prompts for a slug and
extension, creates the note with frontmatter, opens it, inserts the MOC
formatted for the note's extension, and runs `haystack-after-create-hook'.
Also updates `haystack--last-moc' and pushes the MOC text to the kill ring."
  (interactive)
  (haystack--assert-results-buffer)
  (let* ((loci (haystack--extract-file-loci (buffer-string))))
    (when (zerop (length loci))
      (user-error "Haystack: no results to yank"))
    (let* ((descriptor haystack--search-descriptor)
           (chain      (haystack--descriptor-chain-string descriptor)))
      (setq haystack--last-moc       loci)
      (setq haystack--last-moc-chain chain)
      (haystack--ensure-notes-directory)
      (let* ((path     (haystack--create-note-file))
             (ext      (file-name-extension path))
             (moc-text (haystack--format-moc-text loci chain ext)))
        (kill-new moc-text)
        (insert moc-text "\n")
        (run-hooks 'haystack-after-create-hook)))))

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

(defvar haystack--expansion-groups-loaded nil
  "Non-nil when `haystack--expansion-groups' has been loaded from disk.
Set to t after a successful load.  Cleared by
`haystack-reload-expansion-groups' and by demo mode transitions.")

(defun haystack--expansion-groups-file ()
  "Return the path to `.expansion-groups.el' in `haystack-notes-directory'."
  (expand-file-name ".expansion-groups.el" haystack-notes-directory))

(defun haystack--load-expansion-groups ()
  "Load expansion groups from `.expansion-groups.el' into `haystack--expansion-groups'.
Silently sets `haystack--expansion-groups' to nil when the file is
absent.  Emits a message on parse errors rather than signalling.
Skips the disk read when `haystack--expansion-groups-loaded' is non-nil
(cache is warm); use `haystack-reload-expansion-groups' to force a re-read."
  (unless haystack--expansion-groups-loaded
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
                  (error-message-string err)))))
    (setq haystack--expansion-groups-loaded t)))

;;;###autoload
(defun haystack-reload-expansion-groups ()
  "Reload expansion groups from `.expansion-groups.el' and report the count.
Clears the cache flag so the next load re-reads from disk."
  (interactive)
  (setq haystack--expansion-groups-loaded nil)
  (haystack--load-expansion-groups)
  (message "Haystack: loaded %d expansion group%s"
           (length haystack--expansion-groups)
           (if (= 1 (length haystack--expansion-groups)) "" "s")))

(defun haystack--show-info-buffer (buf-name content &optional display-fn)
  "Show BUF-NAME in `special-mode' populated with CONTENT.
DISPLAY-FN is called with the buffer to display it; defaults to
`pop-to-buffer'.  The buffer is created if it does not exist and is
always erased and repopulated."
  (let ((buf (get-buffer-create buf-name)))
    (with-current-buffer buf
      (let ((inhibit-read-only t))
        (erase-buffer)
        (insert content)
        (special-mode)
        (goto-char (point-min))))
    (funcall (or display-fn #'pop-to-buffer) buf)))

;;;###autoload
(defun haystack-validate-groups ()
  "Check loaded expansion groups for terms that appear in more than one group.
Reports conflicts in a dedicated buffer.  If no conflicts are found, a
message is shown instead."
  (interactive)
  (let ((seen (make-hash-table :test #'equal))
        (dups nil))
    (dolist (group haystack--expansion-groups)
      (dolist (term (haystack--group-all-members group))
        (let ((key (downcase term)))
          (if (gethash key seen)
              (push (list term (gethash key seen)) dups)
            (puthash key term seen)))))
    (if (null dups)
        (message "Haystack: expansion groups OK — no duplicate terms")
      (haystack--show-info-buffer
       "*haystack-group-conflicts*"
       (concat "Haystack — Expansion Group Conflicts\n"
               (make-string 40 ?=) "\n\n"
               (mapconcat (lambda (dup)
                            (format "  %S conflicts with %S\n"
                                    (car dup) (cadr dup)))
                          (nreverse dups) ""))))))

;;;###autoload
(defun haystack-describe-expansion-groups ()
  "Display all loaded expansion groups in a dedicated buffer."
  (interactive)
  (haystack--show-info-buffer
   "*haystack-expansion-groups*"
   (concat "Haystack — Expansion Groups\n"
           (make-string 40 ?=) "\n\n"
           (if (null haystack--expansion-groups)
               "(no groups loaded)\n"
             (mapconcat (lambda (group)
                          (format "%-20s → %s\n"
                                  (car group)
                                  (mapconcat #'identity (cdr group) ", ")))
                        haystack--expansion-groups "")))))

(defun haystack--group-all-members (group)
  "Return GROUP as a flat list of all members including the root element.
GROUP has the form (ROOT MEMBER1 MEMBER2 ...).  Use this at call sites
where the intent — include the root — should be explicit."
  group)

(defun haystack--member-in-group-p (term members)
  "Return non-nil if TERM matches any element of MEMBERS case-insensitively."
  (let ((key (downcase term)))
    (cl-some (lambda (m) (string= key (downcase m))) members)))

(defun haystack--lookup-group (term)
  "Return the full member list of TERM's expansion group, or nil.
Searches all groups in `haystack--expansion-groups' case-insensitively.
Returns (ROOT MEMBER1 MEMBER2 ...) if TERM matches any entry, nil if
no group contains TERM."
  (catch 'found
    (dolist (group haystack--expansion-groups)
      (let ((all (haystack--group-all-members group)))
        (when (haystack--member-in-group-p term all)
          (throw 'found all))))
    nil))

(defun haystack--expansion-alternation (members)
  "Return a ripgrep alternation pattern for MEMBERS.
Each member is passed through `regexp-quote'.  Returns \"(A|B|C)\"."
  (concat "("
          (mapconcat (lambda (m) (regexp-quote m)) members "|")
          ")"))

(defun haystack--format-term-display (term expansion)
  "Return a display string for TERM, using EXPANSION alternation when non-nil.
When EXPANSION is non-nil, returns the alternation form \"(A|B|C)\".
When nil, returns the truncated display form via `haystack--display-term'."
  (if expansion
      (haystack--expansion-alternation expansion)
    (haystack--display-term term)))

(defun haystack--save-expansion-groups ()
  "Write `haystack--expansion-groups' to `.expansion-groups.el'.
Creates or overwrites the file.  Signals `user-error' if
`haystack-notes-directory' is not set.  Sets
`haystack--expansion-groups-loaded' to t since the in-memory data is
authoritative after a write."
  (haystack--assert-notes-directory)
  (with-temp-file (haystack--expansion-groups-file)
    (insert ";; Haystack expansion groups — managed with `haystack-associate'\n")
    (insert ";; Format: ((root . (synonym1 synonym2 ...)) ...)\n\n")
    (pp haystack--expansion-groups (current-buffer)))
  (setq haystack--expansion-groups-loaded t))

(defun haystack--groups-remove-term (groups term)
  "Return GROUPS with TERM removed from whichever group contains it.
If TERM was the root, the first remaining member is promoted to root.
Groups that fall below two total terms after removal are dissolved."
  (let ((key (downcase term)))
    (delq nil
          (mapcar (lambda (group)
                    (let* ((all       (haystack--group-all-members group))
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
  (let* ((found  nil)
         (result
          (mapcar (lambda (group)
                    (let ((all (haystack--group-all-members group)))
                      (if (haystack--member-in-group-p anchor all)
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

(defun haystack--frecency-rewrite-term (chain old-root new-root)
  "Return CHAIN with OLD-ROOT replaced by NEW-ROOT, preserving prefix characters.
CHAIN is a list of prefixed term strings such as (\"rust\" \"!programming\").
Matching is case-insensitive.  Prefix characters (`!' `=' `~' `/') are
stripped before comparison and re-applied to the replacement."
  (let ((old-down (downcase old-root)))
    (mapcar (lambda (key-str)
              (string-match "\\`[!/=~]*" key-str)
              (let* ((pfx  (match-string 0 key-str))
                     (term (substring key-str (match-end 0))))
                (if (string= (downcase term) old-down)
                    (concat pfx new-root)
                  key-str)))
            chain)))

(defun haystack--frecency-rename-in-data (data old-root new-root)
  "Return DATA with every occurrence of OLD-ROOT replaced by NEW-ROOT.
DATA is a frecency alist of (CHAIN . PROPS) pairs.  When the rename
produces a key already present in DATA, the entries are merged: counts
are summed and the later timestamp is kept."
  (let ((result nil))
    (dolist (entry data)
      (let* ((new-chain (haystack--frecency-rewrite-term (car entry) old-root new-root))
             (props      (cdr entry))
             (existing   (assoc new-chain result)))
        (if existing
            (let* ((ep    (cdr existing))
                   (count (+ (plist-get props :count) (plist-get ep :count)))
                   (ts    (max (plist-get props :last-access)
                               (plist-get ep :last-access))))
              (setcdr existing (list :count count :last-access ts)))
          (push (cons new-chain props) result))))
    (nreverse result)))

;;;###autoload
(defun haystack-rename-group-root (old-root new-root)
  "Rename the canonical root term OLD-ROOT to NEW-ROOT in the expansion groups.
OLD-ROOT must be the root (not just a member) of an existing group.
NEW-ROOT must not already be present in any group.

Renames atomically: updates the expansion groups file, rewrites
frecency chain keys (flushing immediately), and renames any composite
files whose slugs contain OLD-ROOT (rolling back on failure)."
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
  ;; Compute composite rename pairs while the old slug is still canonical.
  (let ((composite-pairs (haystack--composite-rename-pairs old-root new-root)))
    ;; Step 1: Rename composite files on disk first (rolls back on failure).
    ;; This must complete before the group is updated so a partial failure
    ;; leaves group and composites mutually consistent.
    (when composite-pairs
      (haystack--rename-composites-atomic composite-pairs))
    ;; Step 2: Update frecency chain keys in memory.
    (when haystack--frecency-data
      (setq haystack--frecency-data
            (haystack--frecency-rename-in-data haystack--frecency-data old-root new-root))
      (setq haystack--frecency-dirty t)
      (haystack--frecency-flush))
    ;; Step 3: Update expansion groups and write to disk.
    (setq haystack--expansion-groups
          (haystack--groups-rename-root haystack--expansion-groups old-root new-root))
    (haystack--save-expansion-groups)
    (message "Haystack: renamed root %S → %S (group: (%s)%s)"
             old-root new-root
             (mapconcat #'identity (haystack--lookup-group new-root) ", ")
             (if composite-pairs
                 (format "; %d composite(s) renamed" (length composite-pairs))
               ""))))

(defun haystack--groups-dissolve (groups term)
  "Return GROUPS with the group containing TERM removed entirely.
Matches any member of the group, not just the root."
  (cl-remove-if (lambda (group)
                  (haystack--member-in-group-p term (haystack--group-all-members group)))
                groups))

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
                                   (mapcar #'haystack--group-all-members
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

(cl-defun haystack--rg-args (&key count files-with-matches files-without-match
                                   composite-filter file-glob pattern extra-args)
  "Return a ripgrep argument list for a haystack search.

Mode flags (at most one should be non-nil):
  COUNT               — volume-gate mode: adds --count --with-filename
  FILES-WITH-MATCHES  — intersection mode: adds --files-with-matches
  FILES-WITHOUT-MATCH — negation step 1: adds --files-without-match

Content mode (default when all mode flags are nil) adds:
  --line-number --ignore-case --color=never --no-heading --with-filename
  --max-count=50 --max-columns=500

COMPOSITE-FILTER controls @* composite-file scoping:
  \\='exclude (default) — add --glob=!@*
  \\='only              — add --glob=@*
  \\='all               — no composite glob added

FILE-GLOB: when non-nil, expand `haystack-file-glob' into --glob= flags.

PATTERN: the rg pattern string, appended after the glob flags.

EXTRA-ARGS: additional args appended last (e.g. the notes directory path)."
  (let* (;; Mode-specific leading flags (prepended before base flags)
         (mode-args
          (cond (count                (list "--count" "--with-filename"))
                (files-with-matches   (list "--files-with-matches"))
                (files-without-match  (list "--files-without-match"))
                (t                    nil)))
         ;; Base flags shared by all modes
         (base-args
          (if (or count files-with-matches files-without-match)
              (list "--ignore-case" "--color=never")
            (list "--line-number" "--ignore-case" "--color=never"
                  "--no-heading" "--with-filename"
                  "--max-count=50" "--max-columns=500")))
         ;; Composite-file scoping glob
         (composite-args
          (pcase (or composite-filter 'exclude)
            ('exclude (list "--glob=!@*"))
            ('only    (list "--glob=@*"))
            (_        nil)))
         ;; User-configured file globs (direct directory searches only)
         (file-glob-args
          (when (and file-glob haystack-file-glob)
            (mapcar (lambda (g) (concat "--glob=" g)) haystack-file-glob)))
         ;; Pattern and trailing positional args
         (tail-args
          (append (when pattern (list pattern)) extra-args)))
    (append mode-args base-args composite-args file-glob-args tail-args)))

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

(defun haystack--truncate-content (content emacs-pattern)
  "Return CONTENT windowed to `haystack-context-width' chars around EMACS-PATTERN.
EMACS-PATTERN must be an Emacs regexp (not a ripgrep pattern); use the
`:emacs-pattern' field from `haystack--parse-input', not `:pattern'.
If CONTENT fits within the width it is returned unchanged.  Otherwise a
window centred on the first match is returned, with ... at truncated ends.
If EMACS-PATTERN is invalid or does not match, the window starts at position 0."
  (let ((width haystack-context-width))
    (if (<= (length content) width)
        content
      (let* ((case-fold-search t)
             (match-start (condition-case nil
                              (and (string-match emacs-pattern content)
                                   (match-beginning 0))
                            (invalid-regexp nil)))
             (match-start (or match-start 0))
             (match-end   (or (and (> match-start 0) (match-end 0))
                              match-start))
             (match-len   (- match-end match-start))
             (pad         (max 0 (/ (- width match-len) 2)))
             (win-start   (max 0 (- match-start pad)))
             (win-end     (min (length content) (+ win-start width)))
             (win-start   (max 0 (- win-end width)))
             (prefix      (if (> win-start 0) "..." ""))
             (suffix      (if (< win-end (length content)) "..." "")))
        (concat prefix (substring content win-start win-end) suffix)))))

(defun haystack--truncate-output (output emacs-pattern)
  "Truncate content of every grep-format line in OUTPUT around EMACS-PATTERN.
EMACS-PATTERN must be an Emacs regexp; see `haystack--truncate-content'.
The file:line: prefix of each line is preserved so `compile-goto-error'
continues to work."
  (mapconcat
   (lambda (line)
     (if (string-match "\\`\\([^:]+:[0-9]+:\\)\\(.*\\)" line)
         (concat (match-string 1 line)
                 (haystack--truncate-content (match-string 2 line) emacs-pattern))
       line))
   (split-string output "\n")
   "\n"))

(defun haystack--format-header (chain-string files matches &optional composite-path)
  "Return a formatted multi-line header string for a results buffer.
CHAIN-STRING describes the full search path (e.g. \"root=rust > filter=async\").
FILES and MATCHES are the result counts.
When COMPOSITE-PATH is non-nil, a composite link line is included."
  (let ((rule (concat ";;;;" (make-string 60 ?-))))
    (concat rule "\n"
            ";;;;  Haystack\n"
            (when haystack--demo-active
              ";;;;  *** DEMO MODE — changes will be discarded on haystack-demo-stop ***\n")
            (format ";;;;  %s\n" chain-string)
            (format ";;;;  %d files  ·  %d matches\n" files matches)
            ";;;;  [root]  [up]  [down]  [tree]\n"
            (when composite-path
              (format ";;;;  [composite: %s]\n" (file-name-nondirectory composite-path)))
            rule "\n")))

(defun haystack-go-root ()
  "Switch to the root buffer of this haystack tree."
  (interactive)
  (let ((buf (current-buffer)))
    (while (buffer-live-p (buffer-local-value 'haystack--parent-buffer buf))
      (setq buf (buffer-local-value 'haystack--parent-buffer buf)))
    (cond
     ((eq buf (current-buffer)) (message "Already at root"))
     ((not (buffer-live-p buf)) (message "Haystack: root buffer no longer exists"))
     (t (switch-to-buffer buf)))))

(defun haystack-ret ()
  "Visit result at point, or activate button if point is on one."
  (interactive)
  (if (button-at (point))
      (push-button)
    (compile-goto-error)))

(defun haystack--apply-header-buttons (&optional composite-path)
  "Wire up navigation buttons in the header of the current results buffer.
Must be called inside `inhibit-read-only' with point anywhere in the buffer.
When COMPOSITE-PATH is non-nil, also wire the composite filename as a button."
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
                            'help-echo (symbol-name (cdr pair))))))
    (when composite-path
      (goto-char (point-min))
      (let ((fname (file-name-nondirectory composite-path)))
        (when (search-forward (concat "[composite: " fname "]") nil t)
          (make-text-button (match-beginning 0) (match-end 0)
                            'action (let ((p composite-path))
                                      (lambda (_) (find-file p)))
                            'follow-link t
                            'help-echo composite-path))))))

(defun haystack--setup-results-buffer (buf-name header output descriptor
                                               &optional parent-buf composite-path)
  "Prepare a grep-mode results buffer named BUF-NAME.
Inserts HEADER (marked read-only) then OUTPUT, enables `grep-mode',
and stores DESCRIPTOR and PARENT-BUF as buffer-locals.
When COMPOSITE-PATH is non-nil, a composite button is wired in the header."
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
          (haystack--apply-header-buttons composite-path)
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
  (mapcar #'car (haystack--extract-file-loci text)))

(defun haystack--filter-label (negated filename)
  "Return the chain label string for a filter with NEGATED and FILENAME flags."
  (cond ((and negated filename) "!filename")
        (negated                "exclude")
        (filename               "filename")
        (t                      "filter")))

(defun haystack--chain-parts (descriptor)
  "Return an ordered list of formatted chain segments for DESCRIPTOR.
Each segment is a \"label=display\" string covering the root term and all
stored filters.  The current in-progress filter is not included; callers
append it as needed."
  (let* ((root-label   (if (plist-get descriptor :root-filename) "filename" "root"))
         (root-exp     (plist-get descriptor :root-expansion))
         (root-display (haystack--format-term-display
                        (plist-get descriptor :root-term) root-exp))
         (parts (list (format "%s=%s" root-label root-display))))
    (dolist (f (plist-get descriptor :filters))
      (let* ((f-exp     (plist-get f :expansion))
             (f-display (haystack--format-term-display (plist-get f :term) f-exp)))
        (setq parts (append parts
                             (list (format "%s=%s"
                                           (haystack--filter-label (plist-get f :negated)
                                                                   (plist-get f :filename))
                                           f-display))))))
    parts))

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
  (let ((current-display (haystack--format-term-display current-term current-expansion)))
    (mapconcat #'identity
               (append (haystack--chain-parts descriptor)
                       (list (format "%s=%s"
                                     (haystack--filter-label current-negated
                                                             current-filename)
                                     current-display)))
               " > ")))

(defun haystack--descriptor-chain-string (descriptor)
  "Return the full search chain string for DESCRIPTOR.
Formats root + all stored filters with no additional current term appended.
Used to produce the header comment in data-style MOC output."
  (mapconcat #'identity (haystack--chain-parts descriptor) " > "))

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
for deleting the file.  If writing fails the temp file is cleaned up
before the error is re-signaled."
  (let ((tmp (make-temp-file "haystack-files-")))
    (condition-case err
        (progn
          (with-temp-file tmp
            (insert (mapconcat #'identity files "\0")))
          tmp)
      (error
       (ignore-errors (delete-file tmp))
       (signal (car err) (cdr err))))))

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

(defun haystack--search-in-filelist (pattern filelist cf)
  "Search for PATTERN in files listed in FILELIST with composite filter CF.
Uses xargs to pass file paths to rg, avoiding argument length limits."
  (haystack--xargs-rg filelist
                      (haystack--rg-args :composite-filter cf :pattern pattern)))

(defun haystack--files-for-root-search (&optional cf)
  "Return a list of all files in `haystack-notes-directory' for a filename search.
Applies `haystack-file-glob' and the composite filter CF (default \\='exclude)."
  (let ((args (list "--files")))
    (when haystack-file-glob
      (dolist (g haystack-file-glob)
        (setq args (append args (list (concat "--glob=" g))))))
    (pcase (or cf 'exclude)
      ('exclude (setq args (append args (list "--glob=!@*"))))
      ('only    (setq args (append args (list "--glob=@*"))))
      ('all     nil))
    (setq args (append args (list (expand-file-name haystack-notes-directory))))
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
                               (haystack--rg-args :files-without-match t
                                                  :composite-filter 'all
                                                  :pattern term))
           "\n" t)))
    (if (null narrowed)
        ""
      (let ((tmp2 (haystack--write-filelist narrowed)))
        (unwind-protect
            (haystack--search-in-filelist root-pattern tmp2 cf)
          (delete-file tmp2))))))

(defun haystack--filter-by-content (filenames pattern root-pattern cf)
  "Filter FILENAMES by positive content match on PATTERN.
CF is the composite filter.  Applies the volume gate, then returns rg output.
ROOT-PATTERN is unused here but passed for interface symmetry."
  (ignore root-pattern)
  (let ((tmp (haystack--write-filelist filenames)))
    (unwind-protect
        (progn
          (haystack--volume-gate
           (haystack--xargs-rg tmp (haystack--rg-args :count t
                                                      :composite-filter cf
                                                      :pattern pattern)))
          (haystack--search-in-filelist pattern tmp cf))
      (delete-file tmp))))

(defun haystack--filter-by-filename (filenames emacs-pat negated root-pattern cf)
  "Filter FILENAMES by EMACS-PAT on the relative file path.
When NEGATED is non-nil, keeps files whose path does NOT match.
Re-runs ROOT-PATTERN against the narrowed set for content.
CF is the composite filter.  Returns rg output."
  (let* ((notes-root (file-name-as-directory
                      (expand-file-name haystack-notes-directory)))
         (narrowed (cl-remove-if-not
                    (lambda (f)
                      ;; Match against relative path so directory components
                      ;; (e.g. sicp-org/README.org) are included.
                      ;; Use emacs-pat — :pattern is ripgrep syntax.
                      (let* ((rel   (if (string-prefix-p notes-root f)
                                        (substring f (length notes-root))
                                      (file-name-nondirectory f)))
                             (match (string-match-p emacs-pat rel)))
                        (if negated (not match) match)))
                    filenames)))
    (if (null narrowed)
        ""
      (let ((tmp (haystack--write-filelist narrowed)))
        (unwind-protect
            (haystack--search-in-filelist root-pattern tmp cf)
          (delete-file tmp))))))

(defun haystack--filter-by-negation (filenames negated-pattern root-pattern cf)
  "Filter FILENAMES by excluding those containing NEGATED-PATTERN.
Step 1: find files without the negated term.
Step 2: re-run ROOT-PATTERN against the surviving set.
CF is the composite filter.  Returns rg output."
  (let ((tmp (haystack--write-filelist filenames)))
    (unwind-protect
        (haystack--run-negation-filter negated-pattern root-pattern tmp cf)
      (delete-file tmp))))

;;;###autoload
(defun haystack-filter-further (raw-input)
  "Narrow the current haystack results buffer by RAW-INPUT.
Extracts files from the current buffer, runs rg scoped to those files,
and opens the child results buffer in the current window.

Prefix RAW-INPUT with ! to exclude files containing the term.
Prefix RAW-INPUT with / to match against filenames instead of content.
Prefix RAW-INPUT with = for literal matching (suppress expansion groups).
Prefix RAW-INPUT with ~ to use raw ripgrep regex."
  (interactive
   (list (read-string "[=]literal  [/]filename  [!]negate  [~]regex\nFilter: ")))
  (haystack--frecency-ensure)
  (unless (bound-and-true-p haystack--search-descriptor)
    (user-error "Haystack: not in a haystack results buffer"))
  (haystack--load-expansion-groups)
  (let* ((parent-buf   (current-buffer))
         (descriptor   haystack--search-descriptor)
         (cf           (plist-get descriptor :composite-filter))
         (root-pattern    (plist-get descriptor :root-expanded))
         (root-emacs-pat  (haystack--build-emacs-pattern
                            (plist-get descriptor :root-term)
                            (plist-get descriptor :root-regex)
                            (plist-get descriptor :root-literal)))
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
               (haystack--member-in-group-p term root-exp))
      (user-error
       "Haystack: '%s' is already in the root expansion (%s) — use =%s to search literally"
       term
       (mapconcat #'identity root-exp "|")
       term))
    (let* ((raw-output
            (cond
             (filename
              (haystack--filter-by-filename filenames emacs-pat negated root-pattern cf))
             (negated
              (haystack--filter-by-negation filenames pattern root-pattern cf))
             (t
              (haystack--filter-by-content filenames pattern root-pattern cf))))
           (stats       (haystack--count-search-stats raw-output))
           (trunc-pat   (if (or filename negated) root-emacs-pat emacs-pat))
           (output      (haystack--strip-notes-prefix
                         (haystack--truncate-output raw-output trunc-pat)))
           (buf-name    (haystack--child-buffer-name descriptor term negated filename
                                                     (plist-get parsed :literal)
                                                     (plist-get parsed :regex)))
           (chain-str   (haystack--format-search-chain descriptor term negated
                                                       filename expansion))
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
                                 :composite-filter cf))
           (composite-path (haystack--find-composite new-descriptor))
           (header         (haystack--format-header chain-str (car stats) (cdr stats)
                                                    composite-path)))
      (haystack--frecency-record new-descriptor)
      (let* ((parent-origin haystack--mentions-origin)
             (buf (haystack--setup-results-buffer
                   buf-name header output new-descriptor parent-buf composite-path)))
        ;; Propagate mentions origin and rename buffer when inside a mentions tree.
        (when parent-origin
          (with-current-buffer buf
            (setq-local haystack--mentions-origin parent-origin)
            (rename-buffer
             (replace-regexp-in-string "\\`\\*haystack:" "*haystack-ref:" (buffer-name))
             t)))
        (unless haystack--suppress-display
          (switch-to-buffer buf))
        buf))))

(defun haystack--run-and-query (tokens cf)
  "Execute a file-level AND query for TOKENS with composite filter CF.
Each element of TOKENS is a raw input string parsed through
`haystack--parse-input'.  The candidate file set is narrowed by
successive `--files-with-matches' passes (one per token).  The final
output is a content search of the first token's pattern across the
surviving files, formatted as standard rg grep output.
Returns a raw rg output string, or an empty string when no files survive.
Signals `user-error' if any token carries the ! negation prefix."
  (let* ((parsed-list   (mapcar #'haystack--parse-input tokens))
         (first-parsed  (car parsed-list))
         (first-pattern (plist-get first-parsed :pattern)))
    ;; Negation in AND queries is not supported — filter-further handles that.
    (when (cl-some (lambda (p) (plist-get p :negated)) parsed-list)
      (user-error
       "Haystack: ! prefix is not supported in & queries — use filter-further to negate"))
    ;; Step 1: find files matching the first token across the notes directory.
    (let* ((current-files
            (split-string
             (with-temp-buffer
               (apply #'call-process "rg" nil t nil
                      (haystack--rg-args :files-with-matches t
                                         :composite-filter cf
                                         :file-glob t
                                         :pattern first-pattern
                                         :extra-args (list (expand-file-name haystack-notes-directory))))
               (buffer-string))
             "\n" t)))
      (if (null current-files)
          ""
        ;; Steps 2+: narrow by each subsequent token (xargs, no file-glob).
        (dolist (parsed (cdr parsed-list))
          (when current-files
            (let* ((pattern (plist-get parsed :pattern))
                   (tmp     (haystack--write-filelist current-files)))
              (unwind-protect
                  (setq current-files
                        (split-string
                         (haystack--xargs-rg
                          tmp (haystack--rg-args :files-with-matches t
                                                  :composite-filter 'all
                                                  :pattern pattern))
                         "\n" t))
                (delete-file tmp)))))
        ;; Step 3: volume gate on the intersection, then content search.
        ;; The gate counts only the intersection files (not the full directory)
        ;; because that is the actual search scope for the AND query.  This is
        ;; intentional: a strict second term can legitimately shrink a large
        ;; result below the threshold without user intervention.
        (if (null current-files)
            ""
          (let ((tmp (haystack--write-filelist current-files)))
            (unwind-protect
                (progn
                  (haystack--volume-gate
                   (haystack--xargs-rg tmp (haystack--rg-args :count t
                                                               :composite-filter cf
                                                               :pattern first-pattern)))
                  (haystack--search-in-filelist first-pattern tmp cf))
              (delete-file tmp))))))))

(defun haystack--parse-and-tokens (raw)
  "Split RAW on \" & \" and return a list of token strings, or nil.
Returns nil when RAW does not contain \" & \" (no AND query).  Each
token is whitespace-trimmed; results with fewer than two non-empty
tokens are treated as a normal search and return nil."
  (when (string-match-p " & " raw)
    (let ((tokens (cl-remove-if #'string-empty-p
                                (mapcar #'string-trim
                                        (split-string raw " & " t)))))
      (when (>= (length tokens) 2)
        tokens))))

(defun haystack--run-root-search-and (and-tokens cf)
  "Handle the AND query path for `haystack-run-root-search'.
AND-TOKENS is a list of raw token strings; CF is the composite filter.
Returns a plist with :buf-name :header :output :descriptor :composite-path
for the dispatcher to use."
  (let* ((parsed-list   (mapcar #'haystack--parse-input and-tokens))
         (first-parsed  (car parsed-list))
         (first-term    (plist-get first-parsed :term))
         (first-pattern (plist-get first-parsed :pattern))
         (first-exp     (plist-get first-parsed :expansion))
         (raw-output    (haystack--run-and-query and-tokens cf))
         (stats         (haystack--count-search-stats raw-output))
         (output        (haystack--strip-notes-prefix
                         (haystack--truncate-output raw-output
                                                    (plist-get first-parsed :emacs-pattern))))
         (buf-name      (format "*haystack:1:%s*"
                                (mapconcat
                                 (lambda (p)
                                   (haystack--tree-term-label
                                    (plist-get p :term) nil
                                    (plist-get p :filename)
                                    (plist-get p :literal)
                                    (plist-get p :regex)))
                                 parsed-list "&")))
         (display-parts (mapcar (lambda (p)
                                  (haystack--format-term-display
                                   (plist-get p :term)
                                   (plist-get p :expansion)))
                                parsed-list))
         (chain-label   (format "root=%s"
                                (mapconcat #'identity display-parts " & ")))
         ;; :root-term stores stripped first token + raw subsequent tokens so
         ;; that the frecency chain key reconstructs the exact replay input:
         ;;   chain-key = (concat root-pfx root-term)
         ;;             = (concat "=" "rust & async") = "=rust & async"
         ;;   replay: (haystack-run-root-search "=rust & async") → splits correctly.
         ;; (cdr and-tokens) is always non-nil here: haystack--parse-and-tokens
         ;; guarantees at least two tokens before dispatching to this path.
         (root-term-str (concat first-term " & "
                                (mapconcat #'identity (cdr and-tokens) " & ")))
         (descriptor    (list :root-term        root-term-str
                              :root-expanded    first-pattern
                              :root-literal     (plist-get first-parsed :literal)
                              :root-regex       (plist-get first-parsed :regex)
                              :root-filename    nil
                              :root-expansion   first-exp
                              :filters          nil
                              :composite-filter cf))
         (composite-path (haystack--find-composite descriptor))
         (header         (haystack--format-header chain-label (car stats) (cdr stats)
                                                  composite-path)))
    (haystack--frecency-record descriptor)
    (list :buf-name buf-name :header header :output output
          :descriptor descriptor :composite-path composite-path)))

(defun haystack--run-root-search-filename (parsed cf)
  "Handle the filename (/ prefix) path for `haystack-run-root-search'.
PARSED is the result of `haystack--parse-input'; CF is the composite filter.
Returns rg output as a string.  Searches all files in
`haystack-notes-directory' whose relative path matches the Emacs pattern
in PARSED, then re-runs rg on the matching set for content."
  (let* ((emacs-pat  (plist-get parsed :emacs-pattern))
         (all-files  (haystack--files-for-root-search cf))
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
            (haystack--search-in-filelist "." tmp cf)
          (delete-file tmp))))))

;;;###autoload
(defun haystack-run-root-search (raw-input &optional composite-filter)
  "Search for RAW-INPUT in `haystack-notes-directory'.
Parses prefixes, builds a ripgrep command, and opens a grep-mode
results buffer named *haystack:1:TERM* with a statistics header.

Prefix RAW-INPUT with / to match against filenames instead of content.
Prefix RAW-INPUT with TERM1 & TERM2 for a file-level AND intersection.
COMPOSITE-FILTER is a symbol controlling how @* composite files are
treated: \\='exclude (default), \\='only, or \\='all.
Interactively, a \\[universal-argument] prefix sets COMPOSITE-FILTER to \\='all,
including composite files in the search."
  (interactive (list (read-string "[=]literal  [/]filename  [~]regex  [A & B]AND\nSearch: ")
                     (when current-prefix-arg 'all)))
  (haystack--frecency-ensure)
  (haystack--assert-notes-directory)
  (haystack--load-expansion-groups)
  (haystack--ensure-stop-words)
  ;; Stop word check: single-word, non-literal, non-regex terms only.
  (let* ((pre-parsed  (haystack--parse-input raw-input))
         (pre-term    (plist-get pre-parsed :term))
         (stop-abort  nil))
    (when (and (not (plist-get pre-parsed :literal))
               (not (plist-get pre-parsed :regex))
               (not (haystack--parse-and-tokens raw-input))
               (haystack--stop-word-p pre-term))
      (pcase (haystack--stop-word-prompt pre-term)
        (?s (setq raw-input (concat "=" pre-term)))
        (?r (haystack-remove-stop-word pre-term))
        (_  (setq stop-abort t))))
    (unless stop-abort
      (let* ((cf     (or composite-filter 'exclude))
             (parsed (haystack--parse-input raw-input)))
        (if-let ((and-tokens (haystack--parse-and-tokens raw-input)))
            ;; AND query path.
            (let* ((result         (haystack--run-root-search-and and-tokens cf))
                   (buf-name       (plist-get result :buf-name))
                   (header         (plist-get result :header))
                   (output         (plist-get result :output))
                   (descriptor     (plist-get result :descriptor))
                   (composite-path (plist-get result :composite-path))
                   (buf (haystack--setup-results-buffer buf-name header output descriptor nil
                                                        composite-path)))
              (unless haystack--suppress-display
                (pop-to-buffer buf))
              buf)
          ;; Single-term or filename query path.
          (let* ((term      (plist-get parsed :term))
                 (pattern   (plist-get parsed :pattern))
                 (emacs-pat (plist-get parsed :emacs-pattern))
                 (filename  (plist-get parsed :filename))
                 (output
                  (if filename
                      (haystack--run-root-search-filename parsed cf)
                    (progn
                      (haystack--volume-gate
                       (with-temp-buffer
                         (apply #'call-process "rg" nil t nil
                                (haystack--rg-args :count t
                                                   :composite-filter cf
                                                   :file-glob t
                                                   :pattern pattern
                                                   :extra-args (list (expand-file-name haystack-notes-directory))))
                         (buffer-string)))
                      (with-temp-buffer
                        (let ((exit-code (apply #'call-process "rg" nil t nil
                                                (haystack--rg-args :composite-filter cf
                                                                   :file-glob t
                                                                   :pattern pattern
                                                                   :extra-args (list (expand-file-name haystack-notes-directory))))))
                          (when (= exit-code 2)
                            (user-error "Haystack: rg error: %s" (buffer-string))))
                        (buffer-string)))))
                 (trunc-pat (if filename "." emacs-pat))
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
                                      (haystack--format-term-display term expansion)))
                 (descriptor (list :root-term        term
                                   :root-expanded    (if filename "." pattern)
                                   :root-literal     (plist-get parsed :literal)
                                   :root-regex       (plist-get parsed :regex)
                                   :root-filename    filename
                                   :root-expansion   expansion
                                   :filters          nil
                                   :composite-filter cf)))
            (let* ((composite-path (haystack--find-composite descriptor))
                   (header         (haystack--format-header chain-label (car stats) (cdr stats)
                                                            composite-path)))
              (haystack--frecency-record descriptor)
              (let ((buf (haystack--setup-results-buffer buf-name header output descriptor nil
                                                         composite-path)))
                (unless haystack--suppress-display
                  (pop-to-buffer buf))
                buf))))))))

;;;###autoload
(defun haystack-search-region ()
  "Search for the active region text via `haystack-run-root-search'.
Note: prefix characters at the start of the region (!, ~, /, =) are
interpreted as search modifiers, the same as when typed interactively.
If the selected text begins with one of these characters and you want
a literal match, prefix the term with = instead."
  (interactive)
  (unless (use-region-p)
    (user-error "Haystack: no active region"))
  (haystack-run-root-search
   (buffer-substring-no-properties (region-beginning) (region-end))))

(defun haystack--word-at-point ()
  "Return the word at point, treating hyphens and underscores as word characters.
Scans outward from point using alphanumeric, hyphen, and underscore characters.
Returns nil if point is not on such a character."
  (save-excursion
    (let ((chars "a-zA-Z0-9_-"))
      (let ((ch (char-after (point))))
        (when (and ch (string-match-p (concat "[" chars "]") (string ch)))
          (let ((start (progn (skip-chars-backward chars) (point)))
                (end   (progn (skip-chars-forward  chars) (point))))
            (buffer-substring-no-properties start end)))))))

;;;###autoload
(defun haystack-run-root-search-at-point ()
  "Run a root search on the word at point, or the active region if one exists.
If a region is active its text is used as the search term.  Otherwise the
word under point is used, treating hyphens and underscores as word
characters.  Signals `user-error' if neither a region nor a word is found."
  (interactive)
  (cond
   ((use-region-p)
    (haystack-run-root-search
     (buffer-substring-no-properties (region-beginning) (region-end))))
   ((haystack--word-at-point)
    (haystack-run-root-search (haystack--word-at-point)))
   (t
    (user-error "Haystack: no word at point and no active region"))))

;;;###autoload
(defun haystack-search-composites (raw-input)
  "Search only composite (@*) files for RAW-INPUT.
Like `haystack-run-root-search' with composite-filter set to \\='only."
  (interactive "sHaystack search composites: ")
  (haystack-run-root-search raw-input 'only))

;;;; Results minor mode

(defvar haystack-results-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "RET")     #'haystack-ret)
    (define-key map "n"             #'haystack-next-match)
    (define-key map "p"             #'haystack-previous-match)
    (define-key map "f"             #'haystack-filter-further)
    (define-key map "u"             #'haystack-go-up)
    (define-key map "d"             #'haystack-go-down)
    (define-key map "k"             #'haystack-kill-node)
    (define-key map "K"             #'haystack-kill-subtree)
    (define-key map (kbd "M-k")     #'haystack-kill-whole-tree)
    (define-key map "c"             #'haystack-copy-moc)
    (define-key map "N"             #'haystack-new-note-with-moc)
    (define-key map (kbd "C-c C-c") #'haystack-compose)
    (define-key map "."             #'haystack-run-root-search-at-point)
    (define-key map "t"             #'haystack-show-tree)
    (define-key map "D"             #'haystack-describe-discoverability)
    (define-key map "Y"             #'haystack-mentions-yank-to-origin)
    (define-key map "?"             #'haystack-help)
    map)
  "Keymap active in haystack results buffers (on top of `grep-mode').")

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

(defun haystack--help-rule ()
  "Return a propertized rule line for the help buffer."
  (propertize (concat ";;;;" (make-string 50 ?-)) 'face 'shadow))

(defun haystack--help-section (title)
  "Return a propertized section header line for TITLE."
  (propertize (concat ";;;;  " title) 'face 'font-lock-keyword-face))

(defun haystack--help-entry (cmd description)
  "Return a propertized help entry line for CMD with DESCRIPTION.
The key is highlighted with `font-lock-constant-face'."
  (concat ";;;;    "
          (propertize (format "%-9s" (haystack--help-key cmd))
                      'face 'font-lock-constant-face)
          "  "
          description))

(defun haystack--help-content (&optional avail-width)
  "Return the formatted string for the haystack help buffer.
AVAIL-WIDTH is the window body width of the calling window; at 100+
columns a two-column layout is used to reduce the required height."
  (if (>= (or avail-width 0) 100)
      (haystack--help-content-two-col)
    (haystack--help-content-one-col)))

(defun haystack--help-content-one-col ()
  "Return single-column help content for narrow windows."
  (let ((rule (haystack--help-rule)))
    (mapconcat #'identity
               (list rule
                     (propertize ";;;;  Haystack — results buffer commands" 'face 'bold)
                     rule
                     ""
                     (haystack--help-section "Navigation")
                     (haystack--help-entry 'haystack-ret             "visit file (or activate button)")
                     (haystack--help-entry 'haystack-next-match      "next match")
                     (haystack--help-entry 'haystack-previous-match  "previous match")
                     ""
                     (haystack--help-section "Filter")
                     (haystack--help-entry 'haystack-filter-further  "filter further")
                     ""
                     (haystack--help-section "Tree")
                     (haystack--help-entry 'haystack-show-tree       "show tree")
                     (haystack--help-entry 'haystack-go-up           "go up")
                     (haystack--help-entry 'haystack-go-down         "go down")
                     (haystack--help-entry 'haystack-kill-node       "kill node")
                     (haystack--help-entry 'haystack-kill-subtree    "kill subtree")
                     (haystack--help-entry 'haystack-kill-whole-tree "kill whole tree")
                     ""
                     (haystack--help-section "MOC")
                     (haystack--help-entry 'haystack-copy-moc                 "copy moc")
                     (haystack--help-entry 'haystack-new-note-with-moc        "new note + insert moc")
                     (haystack--help-entry 'haystack-mentions-yank-to-origin  "yank to origin note (mentions tree)")
                     ""
                     (haystack--help-section "Composite")
                     (haystack--help-entry 'haystack-compose             "compose composite note")
                     ""
                     (concat ";;;;    " (propertize "q        " 'face 'font-lock-constant-face) "  close this window")
                     rule)
               "\n")))

(defun haystack--help-content-two-col ()
  "Return two-column help content for wide windows (100+ cols).
Navigation/Filter/Tree on the left; MOC/Composite on the right."
  (let* ((rule  (haystack--help-rule))
         (left  (list (haystack--help-section "Navigation")
                      (haystack--help-entry 'haystack-ret             "visit file / button")
                      (haystack--help-entry 'haystack-next-match      "next match")
                      (haystack--help-entry 'haystack-previous-match  "previous match")
                      ""
                      (haystack--help-section "Filter")
                      (haystack--help-entry 'haystack-filter-further  "filter further")
                      ""
                      (haystack--help-section "Tree")
                      (haystack--help-entry 'haystack-show-tree       "show tree")
                      (haystack--help-entry 'haystack-go-up           "go up")
                      (haystack--help-entry 'haystack-go-down         "go down")
                      (haystack--help-entry 'haystack-kill-node       "kill node")
                      (haystack--help-entry 'haystack-kill-subtree    "kill subtree")
                      (haystack--help-entry 'haystack-kill-whole-tree "kill whole tree")))
         (right (list (haystack--help-section "MOC")
                      (haystack--help-entry 'haystack-copy-moc                "copy moc")
                      (haystack--help-entry 'haystack-new-note-with-moc       "new note + moc")
                      (haystack--help-entry 'haystack-mentions-yank-to-origin "yank to origin (mentions)")
                      ""
                      (haystack--help-section "Composite")
                      (haystack--help-entry 'haystack-compose           "compose composite")
                      ""
                      ";;;;"
                      (concat ";;;;    " (propertize "q        " 'face 'font-lock-constant-face) "  close this window")))
         (col-w 50)
         (n     (max (length left) (length right)))
         (left  (append left  (make-list (- n (length left))  "")))
         (right (append right (make-list (- n (length right)) "")))
         (rows  (cl-mapcar (lambda (l r)
                             (if (string-empty-p (string-trim r))
                                 l
                               (format (concat "%-" (number-to-string col-w) "s  %s") l r)))
                           left right)))
    (mapconcat #'identity
               (append (list rule
                             (propertize ";;;;  Haystack — results buffer commands" 'face 'bold)
                             rule "")
                       rows
                       (list "" rule))
               "\n")))

;;;###autoload
(defun haystack-help ()
  "Show a popup window listing all haystack results buffer commands.
Layout adapts to the current window width: two columns at 100+ characters,
single column otherwise."
  (interactive)
  (let ((win-width (window-body-width)))
    (haystack--show-info-buffer
     "*haystack-help*"
     (haystack--help-content win-width)
     (lambda (buf)
       (select-window
        (display-buffer buf
                        '((display-buffer-below-selected)
                          (window-height . fit-window-to-buffer))))))))

;;;; Tree view

(defcustom haystack-tree-depth-faces
  '(font-lock-keyword-face
    font-lock-function-name-face
    font-lock-variable-name-face
    font-lock-constant-face
    font-lock-string-face)
  "Faces cycled through successive depth levels in `haystack-show-tree'.
Each face is drawn from the active theme, so the tree adapts to colorscheme
changes automatically."
  :type '(repeat face)
  :group 'haystack)

(defvar haystack-tree-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "RET") #'haystack-tree-visit)
    (define-key map "n"         #'haystack-tree-next)
    (define-key map "p"         #'haystack-tree-prev)
    (define-key map (kbd "M-n") #'haystack-tree-next-sibling)
    (define-key map (kbd "M-p") #'haystack-tree-prev-sibling)
    map)
  "Keymap for `haystack-tree-mode'.")

(define-derived-mode haystack-tree-mode special-mode "Haystack-Tree"
  "Major mode for the haystack tree buffer.
Shows all open haystack buffers as a navigable indented tree."
  :keymap haystack-tree-mode-map)

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

(defconst haystack--display-term-max-length 30
  "Maximum length of a search term in buffer names before truncation.")

(defconst haystack--display-term-context 13
  "Characters to keep from head and tail when truncating display terms.")

(defun haystack--display-term (term)
  "Return TERM suitable for display in buffer names and headers.
Collapses all whitespace runs (including newlines) to single spaces and
trims leading/trailing whitespace.  If the result exceeds
`haystack--display-term-max-length' characters, it is truncated to
\"FIRST...LAST\" where FIRST and LAST are each
`haystack--display-term-context' characters."
  (let* ((normalised (string-trim (replace-regexp-in-string "[ \t\n\r]+" " " term)))
         (len        (length normalised)))
    (if (<= len haystack--display-term-max-length)
        normalised
      (concat (substring normalised 0 haystack--display-term-context)
              "..."
              (substring normalised (- len haystack--display-term-context))))))

(defun haystack--tree-term-label (term negated filename literal regex)
  "Return TERM prefixed with its modifier characters for display.
Negation maps to !, filename to /, regex to ~, literal to =."
  (concat (when negated "!")
          (cond (filename "/")
                (regex    "~")
                (literal  "="))
          (haystack--display-term term)))

(defun haystack--descriptor-leaf-label (descriptor)
  "Return the display label for DESCRIPTOR's leaf (deepest) term.
If DESCRIPTOR has filters, uses the last filter's term and modifiers.
Otherwise uses the root term and modifiers."
  (let ((filters (plist-get descriptor :filters)))
    (if filters
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
       (plist-get descriptor :root-regex)))))

(defun haystack--tree-render-node (buf current-buf prefix connector depth)
  "Insert a rendered line for BUF, then recurse into its children.
PREFIX is the accumulated continuation art from ancestor nodes (e.g. \"│   \").
CONNECTOR is the branching art for this node (\"├── \", \"└── \", or \"\").
DEPTH drives the face chosen from `haystack-tree-depth-faces'.
Each line gets a `haystack-tree-buffer' text property pointing to BUF."
  (let* ((descriptor (buffer-local-value 'haystack--search-descriptor buf))
         (term       (haystack--descriptor-leaf-label descriptor))
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
  (unless (bound-and-true-p haystack--search-descriptor)
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
                 (term       (haystack--descriptor-leaf-label descriptor))
                 (start      (point)))
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
    ("rs" . "//") ("go" . "//") ("java" . "//") ("kt" . "//") ("swift" . "//")
    ;; /* */ block comments — opening delimiter only, matching frontmatter style
    ("c" . "/*") ("h" . "/*") ("css" . "/*")
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

(defvar haystack--moc-language-registry nil
  "Alist of registered MOC data format languages.
Each entry is (NAME . PLIST) where PLIST has keys:
  :comment    — line comment prefix (e.g. \"//\")
  :open       — variable declaration opening (e.g. \"const haystack = [\\n\")
  :entry      — format string per item: %s title, %s path, %d line
  :separator  — string inserted between entries
  :close      — closing delimiter (e.g. \"\\n];\")
  :extensions — list of file extension strings (documentation only)

Populated by `haystack-define-moc-language' calls at load time.  Do not
modify directly.  File reload is safe: each macro call uses `setf
(alist-get ...)' which updates existing entries in place rather than
accumulating duplicates.")

(cl-defmacro haystack-define-moc-language (name &key comment open entry
                                                      (separator "\n") close
                                                      extensions)
  "Define a MOC data formatter for language NAME.
Registers NAME in `haystack--moc-language-registry' and defines
`haystack--moc-data-format-NAME' as its formatter function.

Keyword arguments:
  :comment    — line comment prefix for the chain header (e.g. \"//\")
  :open       — variable declaration opening (e.g. \"const haystack = [\\n\")
  :entry      — format string per item: %s title, %s path, %d line
  :separator  — string inserted between entries (default \"\\n\")
  :close      — closing delimiter (e.g. \"\\n];\")
  :extensions — list of extensions this language covers (for documentation
                and registry introspection; register extensions in
                `haystack-moc-data-formatters' to activate them)"
  (declare (indent defun))
  (let ((fn-name (intern (format "haystack--moc-data-format-%s" name))))
    `(progn
       (setf (alist-get ',name haystack--moc-language-registry)
             (list :comment ,comment :open ,open :entry ,entry
                   :separator ,separator :close ,close
                   :extensions ',extensions))
       (defun ,fn-name (loci chain)
         ,(format "Format LOCI as a %s data structure.\nCHAIN is included as a leading comment." name)
         (let ((entries (mapcar (lambda (locus)
                                  (format ,entry
                                          (haystack-moc-quote-string
                                           (haystack--pretty-title
                                            (file-name-nondirectory (car locus))))
                                          (haystack-moc-quote-string (car locus))
                                          (cdr locus)))
                                loci)))
           (concat ,comment " haystack: " chain "\n"
                   ,open
                   (mapconcat #'identity entries ,separator)
                   ,close))))))

(haystack-define-moc-language js
  :comment "//"
  :open    "const haystack = [\n"
  :entry   "  { title: %s, path: %s, line: %d },"
  :close   "\n];"
  :extensions ("js" "mjs" "jsx" "ts" "tsx"))

(haystack-define-moc-language python
  :comment "#"
  :open    "haystack = [\n"
  :entry   "    {\"title\": %s, \"path\": %s, \"line\": %d},"
  :close   "\n]"
  :extensions ("py"))

(haystack-define-moc-language elisp
  :comment   ";;"
  :open      "(defvar haystack\n  '("
  :entry     "(:title %s :path %s :line %d)"
  :separator "\n    "
  :close     "))"
  :extensions ("el" "lisp" "cl" "rkt" "scm" "ss" "clj" "cljs" "cljc"))

(haystack-define-moc-language lua
  :comment "--"
  :open    "local haystack = {\n"
  :entry   "  { title = %s, path = %s, line = %d },"
  :close   "\n}"
  :extensions ("lua" "fnl" "fennel"))

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

(defun haystack--format-moc-text (loci chain ext)
  "Return a formatted MOC string for LOCI using CHAIN label and file extension EXT.
Format is determined by EXT via `haystack--moc-format-for-extension'.
For code targets, respects `haystack-moc-code-style' (\\='comment or \\='data)."
  (let ((fmt (haystack--moc-format-for-extension ext)))
    (if (and (eq fmt 'code) (eq haystack-moc-code-style 'data))
        (haystack--format-moc-data-block loci (or chain "search") ext)
      (mapconcat (lambda (locus)
                   (haystack--format-moc-link (car locus) (cdr locus) fmt ext))
                 loci
                 "\n"))))

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
         (text (haystack--format-moc-text
                haystack--last-moc haystack--last-moc-chain ext)))
    (kill-new text)
    (insert text "\n")))

;;;; Mentions (find-references) engine

(defun haystack--mentions-separator (ext)
  "Return the horizontal-rule separator string for a file with extension EXT.
Follows the same conventions as frontmatter sentinel comments:
  org        → -----
  md/markdown → ---
  html/htm   → <hr>
  anything else → ----"
  (pcase (and ext (downcase ext))
    ("org"      "-----")
    ("md"       "---")
    ("markdown" "---")
    ("html"     "<hr>")
    ("htm"      "<hr>")
    (_          "----")))

(defun haystack--mentions-no-ref-comment (slug ext)
  "Return a boilerplate comment noting no references were found for SLUG.
Format is chosen by EXT using the same conventions as
`haystack--mentions-separator': org and fallback use # comments; md,
markdown, html, and htm use HTML comment syntax."
  (let ((msg (format "No references found for: %s" slug)))
    (pcase (and ext (downcase ext))
      ((or "md" "markdown" "html" "htm")
       (format "<!-- %s -->" msg))
      (_
       (format "# %s" msg)))))

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
           (haystack--frecency-setup-timer)
           ;; Mark as initialized so haystack--frecency-ensure won't
           ;; call setup again — customizing the interval before first
           ;; use counts as explicit initialization.
           (setq haystack--frecency-initialized t)))
  :group 'haystack)

(defvar haystack--frecency-data nil
  "In-memory frecency alist.
Each entry: (CHAIN :count N :last-access FLOAT-TIME) where CHAIN is a
list of prefixed term strings derived from the search descriptor.
Persisted to `.haystack-frecency.el' in the notes directory.")

(defvar haystack--frecency-dirty nil
  "Non-nil when `haystack--frecency-data' has unsaved changes.")

(defvar haystack--suppress-display nil
  "When non-nil, suppress `pop-to-buffer'/`switch-to-buffer' in search commands.
Used by `haystack--frecency-replay' to run the search chain internally
without affecting the window layout.")

(defvar haystack--frecency-timer nil
  "Idle timer that flushes frecency data; interval set by `haystack-frecency-save-interval'.")

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

(defvar haystack--frecency-initialized nil
  "Non-nil once frecency infrastructure has been set up for this session.
Prevents the idle timer and `kill-emacs-hook' from being installed
redundantly on repeated calls to `haystack--frecency-ensure'.")

(defun haystack--frecency-ensure ()
  "Set up frecency infrastructure on first interactive use.
Subsequent calls are no-ops.  This defers timer and hook installation
until a haystack command is actually invoked, so loading the library
does not produce side effects."
  (unless haystack--frecency-initialized
    (haystack--frecency-setup-timer)
    (setq haystack--frecency-initialized t)))

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
  "Return the frecency score for ENTRY: count / max(days-since-access, 1).
This is a recency-weighted count rather than a true exponential-decay
frecency formula.  The simpler formula was chosen because it stays
interpretable (score ≈ visits per day) and degrades gracefully as notes
age without requiring tuning parameters."
  (let* ((props   (cdr entry))
         (count   (plist-get props :count))
         (last-ts (plist-get props :last-access))
         (days    (/ (- (float-time) last-ts) 86400.0)))
    (/ (float count) (max days 1.0))))

(defun haystack--frecent-leaf-p (entry all-entries)
  "Return non-nil if ENTRY is a leaf among ALL-ENTRIES.
Used in tests; not called by production code directly.  Callers must
ensure frecency data is loaded before invoking this."
  (not (null (memq entry (haystack--frecent-leaves all-entries)))))

(defun haystack--frecent-leaves (entries)
  "Return only the leaf entries from ENTRIES.
An entry is a leaf if no entry with a strictly longer chain starting
with this entry's chain has a strictly higher score.

Uses an O(N·L) algorithm: builds a hash table mapping each chain
prefix to the maximum score of any of its extensions, then tests each
entry against that table."
  (if (null entries)
      nil
    ;; Build max-descendant-score table: for each entry with chain (A B C)
    ;; and score S, update max-descendant[(A)] and max-descendant[(A B)] if
    ;; S exceeds the current value.
    (let ((max-desc (make-hash-table :test #'equal)))
      (dolist (entry entries)
        (let ((chain (car entry))
              (score (haystack--frecency-score entry)))
          ;; Update all proper prefixes of this entry's chain.
          (let ((len (length chain)))
            (when (> len 1)
              (cl-loop for i from 1 to (1- len)
                       do (let* ((prefix (cl-subseq chain 0 i))
                                 (cur    (gethash prefix max-desc)))
                            (when (or (null cur) (> score cur))
                              (puthash prefix score max-desc))))))))
      ;; An entry is a leaf if no descendant dominates it.
      (cl-remove-if-not
       (lambda (entry)
         (let* ((chain (car entry))
                (score (haystack--frecency-score entry))
                (best-desc (gethash chain max-desc)))
           (or (null best-desc) (<= best-desc score))))
       entries))))

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

(defvar haystack-frecent-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map "s" #'haystack-frecent-toggle-sort)
    (define-key map "v" #'haystack-frecent-toggle-leaf)
    (define-key map "t" #'haystack-frecent-sort-score)
    (define-key map "f" #'haystack-frecent-sort-frequency)
    (define-key map "r" #'haystack-frecent-sort-recency)
    (define-key map "k" #'haystack-frecent-kill-entry)
    (define-key map "?" #'haystack-frecent-help)
    map)
  "Keymap for `haystack-frecent-mode'.")

(define-derived-mode haystack-frecent-mode special-mode "Haystack-Frecent"
  "Major mode for the Haystack frecency diagnostic buffer.
\\{haystack-frecent-mode-map}"
  :group 'haystack
  :keymap haystack-frecent-mode-map)

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
  (haystack--load-expansion-groups)
  (let ((current-buf nil))
    (let ((haystack--suppress-display t))
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
  (haystack--frecency-ensure)
  (unless haystack--frecency-data
    (haystack--load-frecency))
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

;;;; Find mentions commands

;;;###autoload
(defun haystack-find-mentions ()
  "Open a results buffer showing all notes that mention this note by its slug.
The current buffer must be visiting a file.  The slug is derived from the
filename: the 14-digit timestamp prefix (if any) and extension are stripped,
leaving the bare hyphenated slug.  A literal search (`=' prefix) is run so
expansion groups do not widen the results.

The resulting buffer is renamed to use the `*haystack-ref:' prefix (cosmetic)
and has `haystack--mentions-origin' set (canonical).  From that buffer the
extra key `haystack-mentions-yank-to-origin' appends the MOC to this note
and kills the entire mentions tree."
  (interactive)
  (unless (buffer-file-name)
    (user-error "Haystack: not visiting a file"))
  (let* ((origin (buffer-file-name))
         (slug   (haystack--note-slug origin))
         (buf    (haystack-run-root-search (concat "=" slug))))
    (when buf
      (with-current-buffer buf
        (setq-local haystack--mentions-origin origin)
        (rename-buffer
         (replace-regexp-in-string "\\`\\*haystack:" "*haystack-ref:" (buffer-name))
         t)))
    buf))

(defun haystack--append-to-origin-file (origin content ext)
  "Append a mentions separator and CONTENT to ORIGIN and save.
EXT determines the separator style."
  (let ((sep (haystack--mentions-separator ext)))
    (with-current-buffer (find-file-noselect origin)
      (goto-char (point-max))
      (insert "\n" sep "\n" content "\n")
      (save-buffer))))

;;;###autoload
(defun haystack-insert-mentions ()
  "Search for mentions of this note and prompt to insert them directly.
Like `haystack-find-mentions' but skips the results buffer.  Shows the
match count and offers three choices:
  y / RET  — append separator + MOC links to this note immediately
  SPC      — open the standard mentions results buffer instead
  q        — abort without inserting anything

When there are zero matches a boilerplate comment is inserted instead of
links.  The current buffer must be visiting a file."
  (interactive)
  (unless (buffer-file-name)
    (user-error "Haystack: not visiting a file"))
  (let* ((origin (buffer-file-name))
         (slug   (haystack--note-slug origin))
         (haystack--suppress-display t)
         (buf    (haystack-run-root-search (concat "=" slug))))
    (unless buf
      (user-error "Haystack: search returned nil"))
    (let* ((loci  (with-current-buffer buf (haystack--extract-file-loci (buffer-string))))
           (n     (length loci))
           (ext   (file-name-extension origin))
           (choice (read-char-choice
                    (format "Haystack: %d mention%s found.  (y)insert  (SPC)open buffer  (q)abort "
                            n (if (= 1 n) "" "s"))
                    '(?y ?\r ?\s ?q))))
      (pcase choice
        ((or ?y ?\r)
         (let* ((chain   (with-current-buffer buf
                           (when (bound-and-true-p haystack--search-descriptor)
                             (haystack--descriptor-chain-string haystack--search-descriptor))))
                (content (if (null loci)
                             (haystack--mentions-no-ref-comment slug ext)
                           (haystack--format-moc-text loci chain ext))))
           (kill-buffer buf)
           (haystack--append-to-origin-file origin content ext)
           (message "Haystack: inserted %d mention%s into %s"
                    n (if (= 1 n) "" "s") (file-name-nondirectory origin))))
        (?\s
         ;; Open the full mentions buffer instead
         (with-current-buffer buf
           (setq-local haystack--mentions-origin origin)
           (rename-buffer
            (replace-regexp-in-string "\\`\\*haystack:" "*haystack-ref:" (buffer-name))
            t))
         (pop-to-buffer buf))
        (_
         (kill-buffer buf)
         (message "Haystack: mentions insert aborted"))))))

;;;###autoload
(defun haystack-mentions-yank-to-origin ()
  "Append MOC links to the origin note and kill the mentions tree.
Only valid in buffers that belong to a `haystack-find-mentions' tree
\(i.e. `haystack--mentions-origin' is non-nil).  Appends a file-type
separator followed by formatted MOC links — or a boilerplate no-ref
comment when there are no results — to the origin note, saves the file,
then kills the entire mentions tree via `haystack-kill-whole-tree'."
  (interactive)
  (haystack--assert-results-buffer)
  (unless (bound-and-true-p haystack--mentions-origin)
    (user-error "Haystack: this command is only available in a mentions results buffer — run `haystack-find-mentions' first"))
  (let* ((origin  haystack--mentions-origin)
         (loci    (haystack--extract-file-loci (buffer-string)))
         (chain   (when (bound-and-true-p haystack--search-descriptor)
                    (haystack--descriptor-chain-string haystack--search-descriptor)))
         (ext     (file-name-extension origin))
         (content (if (null loci)
                      (haystack--mentions-no-ref-comment
                       (haystack--note-slug origin) ext)
                    (haystack--format-moc-text loci chain ext)))
         (n       (length loci)))
    (haystack--append-to-origin-file origin content ext)
    (message "Haystack: inserted %d mention%s into %s"
             n (if (= 1 n) "" "s") (file-name-nondirectory origin))
    (haystack-kill-whole-tree)))

;;;; Stop words

(defvar haystack--stop-words nil
  "List of stop words loaded from `.haystack-stop-words.el'.
Nil means not yet loaded.  Use `haystack--ensure-stop-words' before access.")

(defvar haystack--stop-words-loaded nil
  "Non-nil when `haystack--stop-words' has been loaded from disk.
Nil and an empty list are both valid loaded states; this flag distinguishes
them from the unloaded state.  Set by `haystack--load-stop-words' and
`haystack--ensure-stop-words'.  Cleared by demo mode transitions.")

(defconst haystack--default-stop-words
  '("a" "about" "above" "after" "again" "against" "all" "also" "am" "an"
    "and" "any" "are" "aren't" "as" "at" "be" "because" "been" "before"
    "being" "below" "between" "both" "but" "by" "can" "can't" "cannot"
    "could" "couldn't" "did" "didn't" "do" "does" "doesn't" "doing" "don't"
    "down" "during" "each" "few" "for" "from" "further" "get" "got" "had"
    "hadn't" "has" "hasn't" "have" "haven't" "having" "he" "he'd" "he'll"
    "he's" "her" "here" "here's" "hers" "herself" "him" "himself" "his"
    "how" "how's" "i" "i'd" "i'll" "i'm" "i've" "if" "in" "into" "is"
    "isn't" "it" "it's" "its" "itself" "just" "let's" "like" "me" "more"
    "most" "mustn't" "my" "myself" "no" "nor" "not" "now" "of" "off" "on"
    "once" "only" "or" "other" "ought" "our" "ours" "ourselves" "out"
    "over" "own" "same" "shan't" "she" "she'd" "she'll" "she's" "should"
    "shouldn't" "so" "some" "such" "than" "that" "that's" "the" "their"
    "theirs" "them" "themselves" "then" "there" "there's" "these" "they"
    "they'd" "they'll" "they're" "they've" "this" "those" "through" "to"
    "too" "under" "until" "up" "very" "was" "wasn't" "we" "we'd" "we'll"
    "we're" "we've" "were" "weren't" "what" "what's" "when" "when's"
    "where" "where's" "which" "while" "who" "who's" "whom" "why" "why's"
    "will" "with" "won't" "would" "wouldn't" "you" "you'd" "you'll"
    "you're" "you've" "your" "yours" "yourself" "yourselves")
  "Default English stop words seeded into `.haystack-stop-words.el' on first use.
This is the standard NLTK English stop words corpus (182 words).")

(defun haystack--stop-words-file ()
  "Return the path to the stop words data file."
  (expand-file-name ".haystack-stop-words.el" haystack-notes-directory))

(defun haystack--load-stop-words ()
  "Load stop words from disk into `haystack--stop-words'.
Does not seed defaults — leaves `haystack--stop-words' nil if no file exists.
Always sets `haystack--stop-words-loaded' to t on return."
  (let ((path (haystack--stop-words-file)))
    (setq haystack--stop-words
          (condition-case err
              (when (file-exists-p path)
                (with-temp-buffer
                  (insert-file-contents path)
                  (read (current-buffer))))
            (error
             (message "Haystack: failed to load stop words: %s"
                      (error-message-string err))
             nil)))
    (setq haystack--stop-words-loaded t)))

(defun haystack--save-stop-words ()
  "Persist `haystack--stop-words' to disk."
  (condition-case err
      (with-temp-file (haystack--stop-words-file)
        (let ((print-level nil) (print-length nil))
          (pp haystack--stop-words (current-buffer))))
    (error
     (message "Haystack: failed to save stop words: %s"
              (error-message-string err)))))

(defun haystack--ensure-stop-words ()
  "Load stop words, seeding defaults if the file does not yet exist.
Uses `haystack--stop-words-loaded' to distinguish an intentionally empty
list from the unloaded state, so a user who removes every stop word is not
silently reset to the defaults on the next call."
  (unless haystack--stop-words-loaded
    (let ((path (haystack--stop-words-file)))
      (if (file-exists-p path)
          (haystack--load-stop-words)
        (setq haystack--stop-words (copy-sequence haystack--default-stop-words))
        (haystack--save-stop-words)
        (setq haystack--stop-words-loaded t)))))

;;;###autoload
(defun haystack-reload-stop-words ()
  "Reload stop words from disk and report the count.
Clears the loaded flag so the next call re-reads from disk.
Use this after editing `.haystack-stop-words.el' by hand."
  (interactive)
  (setq haystack--stop-words-loaded nil)
  (haystack--load-stop-words)
  (message "Haystack: loaded %d stop word%s"
           (length haystack--stop-words)
           (if (= 1 (length haystack--stop-words)) "" "s")))

;;;###autoload
(defun haystack-reset-stop-words-to-defaults ()
  "Replace the current stop-word list with the built-in defaults and save.
Use this to recover from an accidentally emptied stop-words file."
  (interactive)
  (setq haystack--stop-words (copy-sequence haystack--default-stop-words)
        haystack--stop-words-loaded t)
  (haystack--save-stop-words)
  (message "Haystack: reset to %d default stop word%s"
           (length haystack--stop-words)
           (if (= 1 (length haystack--stop-words)) "" "s")))

(defun haystack--stop-word-p (term)
  "Return non-nil if TERM is a single-word stop word.
Multi-word terms (containing whitespace) are never stop words.
Comparison is case-insensitive."
  (and (not (string-match-p "[ \t]" term))
       (member (downcase term) haystack--stop-words)))

(defun haystack--stop-word-prompt (term)
  "Prompt the user about stop word TERM and return the chosen character.
Returns ?s (search literally), ?r (remove from list and search), or ?q (quit)."
  (read-char-choice
   (format "Haystack: '%s' is a stop word.  [s]earch anyway  [r]emove from list  [q]uit: "
           term)
   '(?s ?r ?q)))

;;;###autoload
(defun haystack-add-stop-word (word)
  "Add WORD to the stop word list and save."
  (interactive "sAdd stop word: ")
  (haystack--ensure-stop-words)
  (let ((w (downcase (string-trim word))))
    (unless (member w haystack--stop-words)
      (push w haystack--stop-words)
      (haystack--save-stop-words)
      (message "Haystack: added '%s' to stop words" w))))

;;;###autoload
(defun haystack-remove-stop-word (word)
  "Remove WORD from the stop word list and save."
  (interactive
   (progn
     (haystack--ensure-stop-words)
     (list (completing-read "Remove stop word: " haystack--stop-words nil t))))
  (haystack--ensure-stop-words)
  (let ((w (downcase (string-trim word))))
    (setq haystack--stop-words (delete w haystack--stop-words))
    (haystack--save-stop-words)
    (message "Haystack: removed '%s' from stop words" w)))

;;;###autoload
(defun haystack-describe-stop-words ()
  "Display all stop words in a dedicated buffer."
  (interactive)
  (haystack--ensure-stop-words)
  (let ((buf (get-buffer-create "*haystack-stop-words*")))
    (with-current-buffer buf
      (let ((inhibit-read-only t))
        (erase-buffer)
        (insert (format ";;;; Haystack stop words (%d)\n\n"
                        (length haystack--stop-words)))
        (dolist (w (sort (copy-sequence haystack--stop-words) #'string<))
          (insert w "\n"))
        (special-mode)
        (goto-char (point-min))))
    (pop-to-buffer buf)))

;;;; Demo mode

(defvar haystack--demo-active nil
  "Non-nil while Haystack demo mode is active.")

(defvar haystack--demo-temp-dir nil
  "Absolute path to the temporary demo notes directory.")

(defvar haystack--demo-saved-state nil
  "Plist of state saved before demo start; restored by `haystack-demo-stop'.")

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
      (condition-case err
          (copy-directory src-dir temp-dir nil t t)
        (error
         (delete-directory temp-dir t)
         (user-error "Haystack: failed to copy demo corpus to %s: %s"
                     temp-dir (error-message-string err))))
      (setq haystack--demo-saved-state
            (list :notes-dir   haystack-notes-directory
                  :frecency    (copy-sequence haystack--frecency-data)
                  :exp-groups  (copy-sequence haystack--expansion-groups)))
      (setq haystack--demo-temp-dir  temp-dir
            haystack--demo-active    t
            haystack-notes-directory temp-dir
            haystack--expansion-groups-loaded nil
            haystack--stop-words-loaded nil)
      (haystack--load-expansion-groups)
      (haystack--load-frecency)
      (haystack--ensure-stop-words)
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
  ;; Delete the temp dir before clearing state so that a deletion failure
  ;; leaves haystack--demo-active non-nil and the function retryable.
  (when (and haystack--demo-temp-dir (file-directory-p haystack--demo-temp-dir))
    (delete-directory haystack--demo-temp-dir t))
  ;; Restore saved state and mark demo as stopped.
  (let ((saved haystack--demo-saved-state))
    (setq haystack-notes-directory           (plist-get saved :notes-dir)
          haystack--frecency-data            (plist-get saved :frecency)
          haystack--expansion-groups         (plist-get saved :exp-groups)
          haystack--demo-active              nil
          haystack--demo-temp-dir            nil
          haystack--demo-saved-state         nil
          haystack--expansion-groups-loaded  nil
          haystack--stop-words-loaded        nil
          haystack--stop-words               nil))
  (message "Haystack demo stopped.  Your notes directory has been restored."))

;;;; Composite notes

(defun haystack--compose-file-section (path match-line)
  "Return an org section string for the source file at PATH.
MATCH-LINE (1-based) is used both in the heading link and as the centre
of the content window when `haystack-composite-max-lines' applies.
The section is a top-level org heading with a file link, followed by
the (possibly windowed) file contents."
  (let* ((basename (file-name-nondirectory path))
         (title    (haystack--pretty-title basename))
         (heading  (format "* [[file:%s::%d][%s]]\n" path match-line title))
         (raw-text (with-temp-buffer
                     (insert-file-contents path)
                     (buffer-string)))
         (content  (haystack--composite-file-content
                    raw-text match-line haystack-composite-max-lines)))
    (concat heading "\n" content "\n")))

(defun haystack--composite-file-content (text match-line max-lines)
  "Return TEXT windowed around MATCH-LINE, respecting MAX-LINES.
TEXT is the full file contents as a string.  MATCH-LINE is 1-based.
MAX-LINES is the ceiling from `haystack-composite-max-lines'; nil means
no limit (return TEXT unchanged).  When truncation is needed a window of
MAX-LINES lines centred on MATCH-LINE is used, with \"...\" prepended
and/or appended at the cut points."
  (let* ((lines   (split-string text "\n"))
         (n-lines (length lines)))
    (if (or (null max-lines) (<= n-lines max-lines))
        text
      (let* ((half      (/ max-lines 2))
             (win-start (max 0 (- match-line 1 half)))
             (win-end   (min n-lines (+ win-start max-lines)))
             ;; Shift window back if it ran off the end
             (win-start (max 0 (- win-end max-lines)))
             (window    (cl-subseq lines win-start win-end))
             (prefix    (when (> win-start 0) "..."))
             (suffix    (when (< win-end n-lines) "...")))
        (mapconcat #'identity
                   (cl-remove nil (list prefix
                                        (mapconcat #'identity window "\n")
                                        suffix))
                   "\n")))))

(defun haystack--find-composite (descriptor)
  "Return the path of the existing composite for DESCRIPTOR, or nil.
Checks whether the file returned by `haystack--composite-filename'
exists.  Returns nil if no composite has been written for this chain."
  (let ((path (haystack--composite-filename descriptor)))
    (when (file-exists-p path) path)))

(defun haystack--composite-filename (descriptor)
  "Return the absolute path of the composite file for DESCRIPTOR.
The filename is @comp__CANONICAL-CHAIN.org; composite content is always
org-formatted so the extension is hardcoded."
  (expand-file-name
   (format "@comp__%s.org" (haystack--canonical-chain-slug descriptor))
   haystack-notes-directory))

(defun haystack--canonical-term-slug (term negated filename)
  "Return the canonical slug component for TERM.
If NEGATED is non-nil, prefix with \"not-\".
If FILENAME is non-nil, prefix with \"fn-\".
The term is resolved to its expansion group root when one exists,
then lowercased and slugified (non-alphanumeric runs → hyphens)."
  (let* ((group    (haystack--lookup-group term))
         (resolved (if group (car group) term))
         (lower    (downcase resolved))
         (slug     (replace-regexp-in-string
                    "-+" "-"
                    (replace-regexp-in-string "[^a-z0-9]+" "-" lower)))
         (slug     (string-trim slug "-")))
    (concat (cond (negated "not-") (filename "fn-")) slug)))

(defun haystack--canonical-chain-slug (descriptor)
  "Return the canonical chain slug string for DESCRIPTOR.
Each term (root, AND sub-terms, filter terms) is resolved to its
expansion group root, lowercased, and slugified.  Terms are joined
with \"__\".  Negated filters are prefixed \"not-\"; filename filters
with \"fn-\".  AND queries at the root are flattened inline, so
\"rust & async\" with filter \"tokio\" produces the same slug as
\"rust\" filtered by \"async\" then \"tokio\"."
  (let* ((root-term (plist-get descriptor :root-term))
         (filters   (plist-get descriptor :filters))
         ;; Expand AND root into individual tokens; fall back to list of one.
         (root-tokens (or (haystack--parse-and-tokens root-term)
                          (list root-term)))
         (root-slugs  (mapcar (lambda (tok)
                                (haystack--canonical-term-slug tok nil nil))
                              root-tokens))
         (filter-slugs (mapcar (lambda (f)
                                 (haystack--canonical-term-slug
                                  (plist-get f :term)
                                  (plist-get f :negated)
                                  (plist-get f :filename)))
                               filters)))
    (mapconcat #'identity (append root-slugs filter-slugs) "__")))

(defun haystack--composite-rename-pairs (old-root new-root)
  "Return (OLD-PATH . NEW-PATH) pairs for composites affected by renaming OLD-ROOT to NEW-ROOT.
Scans `haystack-notes-directory' for `@comp__*.ext' files.  For each,
splits the slug portion on `__', replaces any segment equal to
OLD-ROOT's canonical slug with NEW-ROOT's canonical slug, and returns
the pair only when at least one segment actually changed."
  (let* ((old-slug (haystack--canonical-term-slug old-root nil nil))
         (new-slug (haystack--canonical-term-slug new-root nil nil))
         (dir      (file-name-as-directory (expand-file-name haystack-notes-directory)))
         (files    (file-expand-wildcards (concat dir "@comp__*"))))
    (delq nil
          (mapcar (lambda (path)
                    (let* ((base      (file-name-nondirectory path))
                           (ext       (file-name-extension base))
                           (prefix-len (length "@comp__"))
                           ;; Slug portion sits between the "@comp__" prefix and
                           ;; the ".EXT" suffix (if any).
                           (slug-end  (if ext
                                          (- (length base) (1+ (length ext)))
                                        (length base)))
                           (slug-part (substring base prefix-len slug-end))
                           (segments  (split-string slug-part "__"))
                           (new-segs  (mapcar (lambda (s)
                                               (if (string= s old-slug) new-slug s))
                                             segments)))
                      (when (cl-some (lambda (s) (string= s old-slug)) segments)
                        (cons path
                              (expand-file-name
                               (if ext
                                   (format "@comp__%s.%s"
                                           (mapconcat #'identity new-segs "__")
                                           ext)
                                 (format "@comp__%s"
                                         (mapconcat #'identity new-segs "__")))
                               dir)))))
                  files))))

(defun haystack--rename-composites-atomic (pairs)
  "Rename composite files according to PAIRS, rolling back on any failure.
PAIRS is a list of (OLD-PATH . NEW-PATH) cons cells.  If any rename
fails, all already-completed renames are reversed before signalling an
error.  Returns nil on success."
  (let ((done nil))
    (condition-case err
        (dolist (pair pairs)
          (rename-file (car pair) (cdr pair))
          (push pair done))
      (error
       ;; Roll back completed renames in reverse order.
       (dolist (pair (nreverse done))
         (condition-case _
             (rename-file (cdr pair) (car pair))
           (error nil)))
       (signal (car err) (cdr err))))
    nil))

(defun haystack--extract-all-file-loci (text)
  "Return all (PATH . LINE) pairs from grep-format TEXT, including duplicates.
Unlike `haystack--extract-file-loci', the same file may appear multiple
times when it has multiple match lines.  Used when
`haystack-composite-all-matches' is non-nil."
  (let ((loci nil))
    (dolist (line (split-string text "\n" t))
      (when (string-match "\\`\\([^:]+\\):\\([0-9]+\\):" line)
        (push (cons (expand-file-name (match-string 1 line))
                    (string-to-number (match-string 2 line)))
              loci)))
    (nreverse loci)))

;;;###autoload
(defun haystack-compose ()
  "Build a composite staging buffer from the current haystack results buffer.
Each source file is included as an org heading with a link; content is
windowed per `haystack-composite-max-lines'.  When
`haystack-composite-all-matches' is non-nil, files with multiple match
lines get one section per match.  Returns the compose buffer."
  (interactive)
  (unless (bound-and-true-p haystack--search-descriptor)
    (user-error "Haystack: not in a haystack results buffer"))
  (let* ((descriptor  haystack--search-descriptor)
         (buf-text    (buffer-string))
         (loci        (if haystack-composite-all-matches
                          (haystack--extract-all-file-loci buf-text)
                        (haystack--extract-file-loci buf-text)))
         (slug        (haystack--canonical-chain-slug descriptor))
         (existing    (haystack--find-composite descriptor))
         (buf-name    (format "*haystack-compose:%s*" slug))
         (sections    (mapconcat (lambda (locus)
                                   (haystack--compose-file-section
                                    (car locus) (cdr locus)))
                                 loci "\n"))
         (header      (concat "#+TITLE: Haystack Composite: " slug "\n"
                              "#+HAYSTACK-CHAIN: " slug "\n"
                              (when existing
                                (format "# Existing composite: %s\n"
                                        (file-name-nondirectory existing)))
                              "# C-c C-c to write composite  |  C-c C-k to discard\n"
                              "\n"))
         (compose-buf (get-buffer-create buf-name)))
    (with-current-buffer compose-buf
      (erase-buffer)
      (insert header sections)
      (goto-char (point-min))
      (haystack-compose-mode)
      (setq-local haystack--compose-descriptor descriptor)
      (setq-local haystack--compose-loci       loci)
      (set-buffer-modified-p nil))
    (pop-to-buffer compose-buf)
    compose-buf))

;;;; Composite mode

(defvar haystack-compose-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "C-c C-c") #'haystack-compose-commit)
    (define-key map (kbd "C-c C-k") #'haystack-compose-discard)
    map)
  "Keymap for `haystack-compose-mode'.")

(define-derived-mode haystack-compose-mode org-mode "Haystack-Compose"
  "Major mode for Haystack composite staging buffers.
\\{haystack-compose-mode-map}"
  (add-hook 'write-contents-functions #'haystack--compose-intercept-save nil t))

(defun haystack--compose-intercept-save ()
  "Intercept manual saves in composite buffers when `haystack-composite-protect' is t.
Added to `write-contents-functions' in `haystack-compose-mode'.  Returns
non-nil to signal the save was handled, preventing Emacs from writing the
file directly."
  (when haystack-composite-protect
    (if (y-or-n-p
         "Composite buffers are machine-generated.  Save as a new note instead? ")
        (let ((content (buffer-string)))
          (haystack-new-note)
          (let ((note-buf (current-buffer)))
            (with-current-buffer note-buf
              (insert content)
              (save-buffer))))
      (message "Haystack: save cancelled"))
    t))

(defun haystack--composite-write-content (descriptor loci)
  "Return the string to write to a composite file for DESCRIPTOR and LOCI.
Produces clean org frontmatter followed by one section per locus."
  (let* ((slug    (haystack--canonical-chain-slug descriptor))
         (now     (format-time-string "%Y-%m-%dT%H:%M:%S"))
         (count   (length loci))
         (header  (concat "#+TITLE: Haystack Composite: " slug "\n"
                          "#+HAYSTACK-CHAIN: " slug "\n"
                          "#+HAYSTACK-LAST-GENERATED: " now "\n"
                          "#+HAYSTACK-SOURCE-COUNT: "
                          (number-to-string count) "\n\n"))
         (sections (mapconcat (lambda (locus)
                                (haystack--compose-file-section
                                 (car locus) (cdr locus)))
                              loci "\n")))
    (concat header sections)))

(defun haystack-compose-commit ()
  "Write the composite file and optionally save annotations as a new note.
Always regenerates the composite cleanly from the stored loci.  If the
staging buffer has been modified since generation, prompts to save the
full buffer contents as a new note via `haystack-new-note'."
  (interactive)
  (let* ((descriptor  haystack--compose-descriptor)
         (loci        haystack--compose-loci)
         (path        (haystack--composite-filename descriptor))
         (was-modified (buffer-modified-p)))
    (when (and (file-exists-p path)
               (not (y-or-n-p (format "Overwrite existing %s? "
                                      (file-name-nondirectory path)))))
      (user-error "Haystack: composite write cancelled"))
    (with-temp-file path
      (insert (haystack--composite-write-content descriptor loci)))
    (message "Haystack: wrote %s" (file-name-nondirectory path))
    (when (and was-modified
               (y-or-n-p "Buffer has been modified.  Save as a new note? "))
      (let ((content (buffer-string)))
        (haystack-new-note)
        (let ((note-buf (current-buffer)))
          (with-current-buffer note-buf
            (insert content)
            (save-buffer)))))))

(defun haystack-compose-discard ()
  "Kill the composite staging buffer without writing."
  (interactive)
  (when (or (not (buffer-modified-p))
            (y-or-n-p "Discard changes to composite buffer? "))
    (kill-buffer)))

;;;; Discoverability engine

(defcustom haystack-discoverability-sparse-max 3
  "Maximum file count for a term to be classified as SPARSE.
Terms found in 1 to this many notes fall in the SPARSE tier.
Terms found in 0 notes are ISOLATED; those found in more notes
than `haystack-discoverability-ubiquitous-min' are UBIQUITOUS."
  :type '(integer :min 1)
  :group 'haystack)

(defcustom haystack-discoverability-ubiquitous-min 500
  "Minimum file count for a term to be classified as UBIQUITOUS.
Terms found in this many or more notes fall in the UBIQUITOUS tier."
  :type '(integer :min 1)
  :group 'haystack)

(defcustom haystack-discoverability-split-compound-words nil
  "When non-nil, treat hyphens and underscores as word separators.
By default (nil), hyphenated and underscored terms like `word-word'
and `word_word' are kept as single tokens, preserving technical
vocabulary (e.g. `emacs-lisp', `file_path').  Set to t to split
them into their component words."
  :type 'boolean
  :group 'haystack)

(defun haystack--discoverability-buffer-name (file-path)
  "Return the buffer name for a discoverability analysis of FILE-PATH.
Strips a leading 14-digit timestamp and the file extension from the
basename, keeping hyphens intact."
  (let* ((basename (file-name-nondirectory file-path))
         (base     (file-name-sans-extension basename))
         (slug     (if (string-match "\\`[0-9]\\{14\\}-" base)
                       (substring base (match-end 0))
                     base)))
    (format "*haystack-discoverability: %s*" slug)))

(defun haystack--discoverability-in-notes-dir-p (file-path)
  "Return non-nil if FILE-PATH is inside `haystack-notes-directory'."
  (when haystack-notes-directory
    (file-in-directory-p file-path (expand-file-name haystack-notes-directory))))

(defun haystack--discoverability-tokenize (text)
  "Return a deduplicated list of lowercase tokens from TEXT.
Splits on whitespace and common punctuation.  Hyphens and underscores
are treated as word characters unless
`haystack-discoverability-split-compound-words' is t.  Stop words
(per `haystack--stop-words') are excluded.  No minimum length is
enforced — short technical terms like \"c\" and \"go\" are kept.

Precondition: `haystack--ensure-stop-words' must have been called
before this function so that `haystack--stop-words' is populated."
  (let* ((sep (if haystack-discoverability-split-compound-words
                  "[^a-zA-Z0-9]+"
                "[^a-zA-Z0-9_-]+"))
         (raw     (split-string text sep t))
         (lowered (mapcar #'downcase raw))
         (no-stop (seq-filter (lambda (tok)
                                (not (member tok haystack--stop-words)))
                              lowered)))
    (seq-uniq no-stop)))

(defun haystack--discoverability-tier (count)
  "Return the discoverability tier symbol for COUNT files.
  isolated   — 0 files
  sparse     — 1 to `haystack-discoverability-sparse-max' files
  connected  — sparse-max+1 to ubiquitous-min-1 files
  ubiquitous — `haystack-discoverability-ubiquitous-min' or more files"
  (cond
   ((= count 0)                                         'isolated)
   ((<= count haystack-discoverability-sparse-max)      'sparse)
   ((< count haystack-discoverability-ubiquitous-min)   'connected)
   (t                                                   'ubiquitous)))

(defun haystack--discoverability-count-all-terms (tokens)
  "Return an alist of (TOKEN . FILE-COUNT) for each token in TOKENS.
Runs a single rg call with all tokens joined as an alternation pattern.
Tokens are sorted longest-first so shorter tokens do not shadow longer
ones at the same position in the text.

Each file is counted at most once per token regardless of how many
times the token appears in that file."
  (when tokens
    (let* ((sorted  (sort (copy-sequence tokens)
                          (lambda (a b) (> (length a) (length b)))))
           (pattern (mapconcat #'regexp-quote sorted "|"))
           (args    (list "--no-heading" "--only-matching" "--ignore-case"
                          "--color=never" "--no-line-number"))
           (seen    (make-hash-table :test 'equal))
           (counts  (make-hash-table :test 'equal)))
      (dolist (tok tokens)
        (puthash tok 0 counts))
      (when haystack-file-glob
        (dolist (g haystack-file-glob)
          (setq args (append args (list (concat "--glob=" g))))))
      (setq args (append args (list "--glob=!@*"
                                    pattern
                                    (expand-file-name haystack-notes-directory))))
      (with-temp-buffer
        (apply #'call-process "rg" nil t nil args)
        (dolist (line (split-string (buffer-string) "\n" t))
          (when (string-match "\\`\\(.*\\):\\([a-z0-9_-]+\\)\\'" line)
            (let* ((file (match-string 1 line))
                   (term (downcase (match-string 2 line)))
                   (key  (cons file term)))
              (when (and (gethash term counts)
                         (not (gethash key seen)))
                (puthash key t seen)
                (puthash term (1+ (gethash term counts)) counts))))))
      (mapcar (lambda (tok) (cons tok (gethash tok counts 0))) tokens))))

(defun haystack--discoverability-tier-section (heading tier-symbol range tc-list)
  "Return the org string for one discoverability tier section.
HEADING is the display name; TIER-SYMBOL is the keyword stored in
PROPERTIES; RANGE is the human-readable file count range; TC-LIST is
an alist of (TERM . COUNT) pairs for this tier."
  (let* ((sorted (sort (copy-sequence tc-list)
                       (lambda (a b)
                         (if (= (cdr a) (cdr b))
                             (string< (car a) (car b))
                           (< (cdr a) (cdr b))))))
         (count  (length sorted)))
    (concat
     (format "* %s (%s) [%d terms]\n" heading range count)
     ":PROPERTIES:\n"
     (format ":HAYSTACK_TIER: %s\n" tier-symbol)
     ":END:\n\n"
     (mapconcat (lambda (tc)
                  (format "- %s (%d)\n" (car tc) (cdr tc)))
                sorted
                "")
     "\n")))

(defun haystack--discoverability-render (term-counts file-path)
  "Return the org string for a discoverability buffer.
TERM-COUNTS is an alist of (TERM . COUNT); FILE-PATH is the source note."
  (let* ((title    (haystack--discoverability-buffer-name file-path))
         (now      (format-time-string "%Y-%m-%d"))
         (isolated nil) (sparse nil) (connected nil) (ubiquitous nil))
    (dolist (tc term-counts)
      (pcase (haystack--discoverability-tier (cdr tc))
        ('isolated   (push tc isolated))
        ('sparse     (push tc sparse))
        ('connected  (push tc connected))
        ('ubiquitous (push tc ubiquitous))))
    (setq isolated   (nreverse isolated)
          sparse     (nreverse sparse)
          connected  (nreverse connected)
          ubiquitous (nreverse ubiquitous))
    (concat
     (format "#+TITLE: %s\n#+DATE: %s\n\n" title now)
     (haystack--discoverability-tier-section
      "Isolated" 'isolated "0 files" isolated)
     (haystack--discoverability-tier-section
      "Sparse" 'sparse
      (format "1\u2013%d files" haystack-discoverability-sparse-max) sparse)
     (haystack--discoverability-tier-section
      "Connected" 'connected
      (format "%d\u2013%d files"
              (1+ haystack-discoverability-sparse-max)
              (1- haystack-discoverability-ubiquitous-min))
      connected)
     (haystack--discoverability-tier-section
      "Ubiquitous" 'ubiquitous
      (format "%d+ files" haystack-discoverability-ubiquitous-min) ubiquitous))))

(defun haystack-discoverability-search-at-point ()
  "Launch a haystack search for the term at point.
On org heading lines (starting with *), show a message instead."
  (interactive)
  (let ((line (buffer-substring-no-properties
               (line-beginning-position) (line-end-position))))
    (if (string-match-p "\\`\\*" line)
        (message "Haystack: move cursor to a term line to search")
      (let ((term (haystack--word-at-point)))
        (if term
            (haystack-run-root-search term)
          (message "Haystack: no term at point"))))))

(defun haystack-discoverability-add-stop-word ()
  "Add the word at point to the haystack stop word list."
  (interactive)
  (let ((term (haystack--word-at-point)))
    (if term
        (haystack-add-stop-word term)
      (message "Haystack: no term at point"))))

(defvar haystack-discoverability-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "RET") #'haystack-discoverability-search-at-point)
    (define-key map "a"         #'haystack-discoverability-add-stop-word)
    (define-key map "q"         #'quit-window)
    map)
  "Keymap for `haystack-discoverability-mode'.")

(define-derived-mode haystack-discoverability-mode org-mode "Haystack-Discov"
  "Major mode for Haystack discoverability analysis buffers.
Each org heading groups terms by how many notes contain them:
  Isolated   — 0 files (potential orphan concepts)
  Sparse     — few files (specific / niche)
  Connected  — moderate files (well-linked)
  Ubiquitous — many files (consider adding to stop words)

\\{haystack-discoverability-mode-map}"
  :keymap haystack-discoverability-mode-map
  (setq-local buffer-read-only t))

;;;###autoload
(defun haystack-describe-discoverability ()
  "Analyze term discoverability for the current buffer's note.
Tokenizes the buffer, counts how many notes each term appears in,
and presents the results sorted into four tiers (Isolated, Sparse,
Connected, Ubiquitous) in an org-mode buffer.

Gate: only works from file-backed buffers whose file is inside
`haystack-notes-directory'.  Re-running refreshes the existing buffer."
  (interactive)
  (haystack--assert-notes-directory)
  (unless (buffer-file-name)
    (user-error "Haystack: discoverability requires a file-backed buffer"))
  (unless (haystack--discoverability-in-notes-dir-p (buffer-file-name))
    (user-error "Haystack: current file is not in the notes directory"))
  (haystack--ensure-stop-words)
  (let* ((file-path   (buffer-file-name))
         (text        (buffer-substring-no-properties (point-min) (point-max)))
         (tokens      (haystack--discoverability-tokenize text))
         (term-counts (haystack--discoverability-count-all-terms tokens))
         (buf-name    (haystack--discoverability-buffer-name file-path)))
    (let ((buf (get-buffer-create buf-name)))
      (with-current-buffer buf
        (let ((inhibit-read-only t))
          (erase-buffer)
          (insert (haystack--discoverability-render term-counts file-path)))
        (haystack-discoverability-mode)
        (goto-char (point-min)))
      (message "Haystack: discoverability analysis complete (%d terms)" (length tokens))
      (pop-to-buffer buf)
      buf)))

;;;; Global prefix map

(defvar haystack-prefix-map (make-sparse-keymap)
  "Prefix keymap for global haystack commands.
Not bound by default.  Add to your config, e.g.:
  (global-set-key (kbd \"C-c h\") haystack-prefix-map)")
(define-key haystack-prefix-map "s" #'haystack-run-root-search)
(define-key haystack-prefix-map "." #'haystack-run-root-search-at-point)
(define-key haystack-prefix-map "r" #'haystack-search-region)
(define-key haystack-prefix-map "n" #'haystack-new-note)
(define-key haystack-prefix-map "N" #'haystack-new-note-with-moc)
(define-key haystack-prefix-map "y" #'haystack-yank-moc)
(define-key haystack-prefix-map "t" #'haystack-show-tree)
(define-key haystack-prefix-map "f" #'haystack-frecent)
(define-key haystack-prefix-map "w" #'haystack-compose)
(define-key haystack-prefix-map "C" #'haystack-search-composites)
(define-key haystack-prefix-map "d" #'haystack-describe-discoverability)
(define-key haystack-prefix-map "m" #'haystack-find-mentions)
(define-key haystack-prefix-map "M" #'haystack-insert-mentions)
(define-key haystack-prefix-map "D" #'haystack-demo)

(provide 'haystack)
;;; haystack.el ends here
