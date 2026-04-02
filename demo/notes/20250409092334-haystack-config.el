;; title: Haystack Configuration Reference
;; date: 2025-04-09
;; %%% haystack-end-frontmatter %%%

;; Complete reference for key Haystack configuration variables.
;; These are all defcustom variables in the haystack group,
;; accessible via M-x customize-group RET haystack.

;;; Core directory and search settings

(defvar my/haystack-notes-dir (expand-file-name "~/notes/")
  "Local notes directory for haystack searches.
All rg (ripgrep) invocations use this as the search root.")

;; Point haystack at the notes directory.
(setopt haystack-notes-directory my/haystack-notes-dir)

;; Restrict search to specific file types via glob.
;; nil (default) means search all files in the notes directory.
(setopt haystack-file-glob "*.org")

;; Default extension for new notes created with haystack-new-note.
(setopt haystack-default-extension "org")

;;; Expansion groups for vocabulary/synonym handling.
;; Expansion groups live in .expansion-groups.el in your notes directory.
;; They are loaded automatically — no defcustom needed.  Edit the file
;; directly or use M-x haystack-associate to manage groups interactively.

;;; Display settings

;; Maximum context width (chars) for each match line in the results buffer.
;; Content is centred on the match with ... at truncated ends.
(setopt haystack-context-width 60)

;; Whether new filter buffers inherit the parent's view mode
;; (Full, Compact, or Files).
(setopt haystack-inherit-view-mode nil)

;; Maximum number of columns before line truncation in results output.
(setopt haystack-max-columns 500)

;;; MOC settings

;; Code file MOC style: 'comment (default) inserts links as comments,
;; 'data generates language-specific data structures.
(setopt haystack-moc-code-style 'comment)

;;; Frecency settings

;; Idle seconds before dirty frecency data is flushed to disk.
(setopt haystack-frecency-save-interval 60)

;;; Keybinding setup
;; Haystack ships haystack-prefix-map unbound.
;; Bind it to a convenient prefix:
(global-set-key (kbd "C-c h") haystack-prefix-map)

;; End of haystack configuration reference.
