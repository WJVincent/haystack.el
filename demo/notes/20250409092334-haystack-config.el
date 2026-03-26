;; title: Haystack Configuration Reference
;; date: 2025-04-09
;; %%% pkm-end-frontmatter %%%

;; Complete reference for all Haystack configuration variables.
;; These are all defcustom variables in the haystack group,
;; accessible via M-x customize-group RET haystack.

;;; Core directory and search settings

(defvar my/haystack-notes-dir (expand-file-name "~/notes/")
  "Local notes directory for haystack searches.
All rg (ripgrep) invocations use this as the search root.")

;; Point haystack at the notes directory.
(setopt haystack-notes-directory my/haystack-notes-dir)

;; File types to include in search.
;; Add "txt" for plain-text notes or "el" to search emacs-lisp notes.
(setopt haystack-search-extensions '("org" "md" "txt"))

;;; Expansion groups for vocabulary/synonym handling.
;; Each group is a list of strings treated as synonyms by the rg query engine.
;; A search for any term in a group matches notes containing any other term.
(setopt haystack-expansion-groups
        '(;; Lisp dialect synonyms
          ("elisp" "emacs-lisp" "emacs lisp")
          ("lisp" "common-lisp" "cl" "scheme" "clojure")
          ;; PKM synonyms
          ("pkm" "zettelkasten" "knowledge-management" "second-brain")
          ;; Search tool synonyms
          ("search" "ripgrep" "rg" "full-text search")
          ;; Note vocabulary synonyms
          ("note" "notes" "zettel")))

;;; Frecency configuration
;; The frecency file stores visit frequency and recency data.
;; Keeping it in the notes dir makes it version-controllable.
(setopt haystack-frecency-file
        (expand-file-name ".haystack-frecency" my/haystack-notes-dir))

;; Frecency half-life in days: how quickly old visits decay.
;; Lower values = more aggressively recency-weighted.
(setopt haystack-frecency-half-life 30)

;;; Display preferences
;; Open selected notes in other-window to preserve current context.
(setopt haystack-result-display-function #'find-file-other-window)

;; Maximum number of candidates to display in the completing-read list.
(setopt haystack-max-candidates 200)

;;; Additional rg flags passed verbatim to the ripgrep invocation.
;; --smart-case: case-insensitive unless query contains uppercase.
(setopt haystack-rg-extra-args "--smart-case")

;; End of haystack configuration reference.
