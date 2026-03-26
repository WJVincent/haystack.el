;;; haystack-test.el --- ERT tests for haystack.el -*- lexical-binding: t -*-

;;; Commentary:
;; Run from the repo root with:
;;   emacs --batch -l ert -l haystack.el -l test/haystack-test.el \
;;         -f ert-run-tests-batch-and-exit

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'haystack)

;;;; Helpers

(defmacro haystack-test--with-notes-dir (&rest body)
  "Run BODY with a temporary directory bound as `haystack-notes-directory'."
  `(let ((haystack-notes-directory (make-temp-file "haystack-test-" t)))
     (unwind-protect
         (progn ,@body)
       (delete-directory haystack-notes-directory t))))

(defmacro haystack-test--with-file-buffer (ext &rest body)
  "Visit a temporary file with EXT, run BODY, then clean up."
  `(let* ((tmpfile (make-temp-file "haystack-regen-" nil (concat "." ,ext)))
          (buf (find-file-noselect tmpfile)))
     (unwind-protect
         (with-current-buffer buf
           ,@body)
       (kill-buffer buf)
       (delete-file tmpfile))))

(defun haystack-test--has-sentinel (str)
  "Return non-nil if STR contains the pkm-end-frontmatter sentinel."
  (string-match-p (regexp-quote haystack--sentinel-string) str))

;;;; haystack--timestamp

(ert-deftest haystack-test/timestamp-is-14-digits ()
  "Timestamp returns a string of exactly 14 digits."
  (should (string-match-p "\\`[0-9]\\{14\\}\\'" (haystack--timestamp))))

;;;; haystack--sanitize-slug

(ert-deftest haystack-test/sanitize-slug-spaces-become-hyphens ()
  (should (equal (haystack--sanitize-slug "my note about rust") "my-note-about-rust")))

(ert-deftest haystack-test/sanitize-slug-runs-of-spaces-collapse ()
  (should (equal (haystack--sanitize-slug "foo  bar") "foo-bar")))

(ert-deftest haystack-test/sanitize-slug-trims-whitespace ()
  (should (equal (haystack--sanitize-slug "  hello world  ") "hello-world")))

(ert-deftest haystack-test/sanitize-slug-strips-unsafe-chars ()
  (should (equal (haystack--sanitize-slug "foo/bar:baz") "foobarbaz")))

(ert-deftest haystack-test/sanitize-slug-preserves-hyphens-and-underscores ()
  (should (equal (haystack--sanitize-slug "my-note_v2") "my-note_v2")))

(ert-deftest haystack-test/sanitize-slug-already-clean-passthrough ()
  (should (equal (haystack--sanitize-slug "rust-ownership") "rust-ownership")))

;;;; haystack--pretty-title

(ert-deftest haystack-test/pretty-title-timestamped-slug ()
  "Strips 14-digit prefix, extension, and converts hyphens to spaces."
  (should (equal (haystack--pretty-title "20240315142233-my-rust-notes.org")
                 "my rust notes")))

(ert-deftest haystack-test/pretty-title-no-timestamp ()
  "Strips extension and converts hyphens when no timestamp present."
  (should (equal (haystack--pretty-title "reference-material.md")
                 "reference material")))

(ert-deftest haystack-test/pretty-title-no-hyphens ()
  "Strips only the extension when no hyphens are present."
  (should (equal (haystack--pretty-title "notes.txt")
                 "notes")))

(ert-deftest haystack-test/pretty-title-underscores-preserved ()
  "Underscores are left as-is — only hyphens become spaces."
  (should (equal (haystack--pretty-title "my_epic_note.txt")
                 "my_epic_note")))

(ert-deftest haystack-test/pretty-title-camelcase-preserved ()
  "CamelCase filenames pass through unchanged aside from extension strip."
  (should (equal (haystack--pretty-title "studentSelector.js")
                 "studentSelector")))

(ert-deftest haystack-test/pretty-title-short-numeric-prefix ()
  "A numeric prefix shorter than 14 digits is not treated as a timestamp."
  (should (equal (haystack--pretty-title "2024-my-note.org")
                 "2024 my note")))

;;;; Frontmatter style functions

(ert-deftest haystack-test/frontmatter-org ()
  (let ((fm (haystack--frontmatter-org "Test Note")))
    (should (string-match-p "#\\+TITLE: Test Note" fm))
    (should (string-match-p "#\\+DATE:" fm))
    (should (haystack-test--has-sentinel fm))
    (should (string-suffix-p "\n\n" fm))))

(ert-deftest haystack-test/frontmatter-md ()
  (let ((fm (haystack--frontmatter-md "Test Note")))
    (should (string-prefix-p "---\n" fm))
    (should (string-match-p "title: Test Note" fm))
    (should (haystack-test--has-sentinel fm))
    (should (string-suffix-p "\n\n" fm))))

(ert-deftest haystack-test/frontmatter-slash ()
  (let ((fm (haystack--frontmatter-slash "Test Note")))
    (should (string-match-p "// title: Test Note" fm))
    (should (haystack-test--has-sentinel fm))
    (should (string-suffix-p "\n\n" fm))))

(ert-deftest haystack-test/frontmatter-hash ()
  (let ((fm (haystack--frontmatter-hash "Test Note")))
    (should (string-match-p "# title: Test Note" fm))
    (should (haystack-test--has-sentinel fm))
    (should (string-suffix-p "\n\n" fm))))

(ert-deftest haystack-test/frontmatter-dash ()
  (let ((fm (haystack--frontmatter-dash "Test Note")))
    (should (string-match-p "-- title: Test Note" fm))
    (should (haystack-test--has-sentinel fm))
    (should (string-suffix-p "\n\n" fm))))

(ert-deftest haystack-test/frontmatter-semi ()
  (let ((fm (haystack--frontmatter-semi "Test Note")))
    (should (string-match-p ";; title: Test Note" fm))
    (should (haystack-test--has-sentinel fm))
    (should (string-suffix-p "\n\n" fm))))

(ert-deftest haystack-test/frontmatter-c-block ()
  (let ((fm (haystack--frontmatter-c-block "Test Note")))
    (should (string-match-p "/\\* title: Test Note \\*/" fm))
    (should (haystack-test--has-sentinel fm))
    (should (string-suffix-p "\n\n" fm))))

(ert-deftest haystack-test/frontmatter-html-block ()
  (let ((fm (haystack--frontmatter-html-block "Test Note")))
    (should (string-match-p "<!-- title: Test Note -->" fm))
    (should (haystack-test--has-sentinel fm))
    (should (string-suffix-p "\n\n" fm))))

(ert-deftest haystack-test/frontmatter-ml-block ()
  (let ((fm (haystack--frontmatter-ml-block "Test Note")))
    (should (string-match-p "(\\* title: Test Note \\*)" fm))
    (should (haystack-test--has-sentinel fm))
    (should (string-suffix-p "\n\n" fm))))

;;;; haystack--frontmatter dispatch

(ert-deftest haystack-test/frontmatter-dispatch-known-extensions ()
  "Every extension in `haystack-frontmatter-functions' returns a string."
  (dolist (entry haystack-frontmatter-functions)
    (let ((ext (car entry)))
      (should (stringp (haystack--frontmatter "Test" ext))))))

(ert-deftest haystack-test/frontmatter-dispatch-unknown-returns-nil ()
  "An unknown extension returns nil."
  (should (null (haystack--frontmatter "Test" "xyz"))))

;;;; haystack-new-note

(ert-deftest haystack-test/new-note-errors-without-directory ()
  "Signals user-error when `haystack-notes-directory' is nil."
  (let ((haystack-notes-directory nil))
    (should-error (haystack-new-note) :type 'user-error)))

(ert-deftest haystack-test/new-note-offers-to-create-missing-directory ()
  "Offers to create the directory when it does not exist."
  (let* ((parent (make-temp-file "haystack-test-parent-" t))
         (haystack-notes-directory (expand-file-name "notes" parent)))
    (unwind-protect
        (progn
          (cl-letf (((symbol-function 'y-or-n-p) (lambda (_) t))
                    ((symbol-function 'read-string)
                     (lambda (_p &optional _i _h _d) "slug"))
                    ((symbol-function 'find-file) #'ignore))
            (haystack-new-note))
          (should (file-directory-p haystack-notes-directory)))
      (delete-directory parent t))))

(ert-deftest haystack-test/new-note-aborts-when-directory-creation-declined ()
  "Signals user-error when user declines to create the missing directory."
  (let ((haystack-notes-directory "/tmp/haystack-nonexistent-dir-xyz/"))
    (cl-letf (((symbol-function 'y-or-n-p) (lambda (_) nil)))
      (should-error (haystack-new-note) :type 'user-error))))

(ert-deftest haystack-test/new-note-creates-file ()
  "Creates a correctly named file with frontmatter in the notes directory."
  (haystack-test--with-notes-dir
   (let ((haystack-default-extension "org")
         (responses (list "test-note" "org")))
     (cl-letf (((symbol-function 'read-string)
                (lambda (_prompt &optional _init _hist _default)
                  (pop responses)))
               ((symbol-function 'find-file) #'ignore))
       (haystack-new-note)
       (let* ((files (directory-files haystack-notes-directory nil "\\.org$"))
              (content (with-temp-buffer
                         (insert-file-contents
                          (expand-file-name (car files) haystack-notes-directory))
                         (buffer-string))))
         (should (= 1 (length files)))
         (should (string-match-p "\\`[0-9]\\{14\\}-test-note\\.org\\'" (car files)))
         (should (string-match-p "#\\+TITLE:" content))
         (should (haystack-test--has-sentinel content)))))))

(ert-deftest haystack-test/new-note-unknown-ext-creates-file-without-frontmatter ()
  "Creates a file for an unknown extension but does not insert frontmatter."
  (haystack-test--with-notes-dir
   (let ((responses (list "test-note" "xyz")))
     (cl-letf (((symbol-function 'read-string)
                (lambda (_prompt &optional _init _hist _default)
                  (pop responses)))
               ((symbol-function 'find-file) #'ignore))
       (haystack-new-note)
       (let* ((files (directory-files haystack-notes-directory nil "\\.xyz$"))
              (content (with-temp-buffer
                         (insert-file-contents
                          (expand-file-name (car files) haystack-notes-directory))
                         (buffer-string))))
         (should (= 1 (length files)))
         (should (string-empty-p content)))))))

;;;; haystack-regenerate-frontmatter

(ert-deftest haystack-test/regen-replaces-frontmatter ()
  "Replaces frontmatter up to the sentinel, preserving the body."
  (haystack-test--with-file-buffer "org"
    (insert "#+TITLE: old title\n#+DATE: 1970-01-01\n"
            "# %%% pkm-end-frontmatter %%%\n\nBody content.\n")
    (cl-letf (((symbol-function 'y-or-n-p) (lambda (_) t)))
      (haystack-regenerate-frontmatter))
    (let ((content (buffer-string)))
      (should-not (string-match-p "old title" content))
      (should (string-match-p "#\\+TITLE:" content))
      (should (string-match-p "Body content\\." content)))))

(ert-deftest haystack-test/regen-no-extra-blank-lines ()
  "Repeated regeneration does not accumulate blank lines before the body."
  (haystack-test--with-file-buffer "org"
    (insert "#+TITLE: test\n#+DATE: 1970-01-01\n"
            "# %%% pkm-end-frontmatter %%%\n\nBody.\n")
    (cl-letf (((symbol-function 'y-or-n-p) (lambda (_) t)))
      (haystack-regenerate-frontmatter)
      (haystack-regenerate-frontmatter)
      (haystack-regenerate-frontmatter))
    (should (string-match-p (concat (regexp-quote haystack--sentinel-string)
                                    "\n\nBody\\.")
                            (buffer-string)))))

(ert-deftest haystack-test/regen-no-sentinel-inserts-at-top ()
  "Inserts frontmatter at top of file when no sentinel is present."
  (haystack-test--with-file-buffer "org"
    (insert "Just some content.\n")
    (cl-letf (((symbol-function 'y-or-n-p) (lambda (_) t)))
      (haystack-regenerate-frontmatter))
    (let ((content (buffer-string)))
      (should (string-prefix-p "#+TITLE:" content))
      (should (string-match-p "Just some content\\." content)))))

(ert-deftest haystack-test/regen-abort-leaves-buffer-unchanged ()
  "Does not modify the buffer when the user aborts."
  (haystack-test--with-file-buffer "org"
    (let ((original "#+TITLE: original\n# %%% pkm-end-frontmatter %%%\n\nBody.\n"))
      (insert original)
      (cl-letf (((symbol-function 'y-or-n-p) (lambda (_) nil)))
        (should-error (haystack-regenerate-frontmatter) :type 'user-error))
      (should (equal (buffer-string) original)))))

(ert-deftest haystack-test/regen-errors-on-non-file-buffer ()
  "Signals user-error when the buffer is not visiting a file."
  (with-temp-buffer
    (should-error (haystack-regenerate-frontmatter) :type 'user-error)))

;;;; Input processing pipeline

;;; haystack--strip-prefixes

(ert-deftest haystack-test/strip-prefixes-bare-term ()
  "A bare term returns no flags and the term unchanged."
  (should (equal (haystack--strip-prefixes "rust")
                 '("rust" nil nil nil nil))))

(ert-deftest haystack-test/strip-prefixes-negate ()
  (should (equal (haystack--strip-prefixes "!rust")
                 '("rust" t nil nil nil))))

(ert-deftest haystack-test/strip-prefixes-filename ()
  (should (equal (haystack--strip-prefixes "/cargo")
                 '("cargo" nil t nil nil))))

(ert-deftest haystack-test/strip-prefixes-negate-and-filename ()
  (should (equal (haystack--strip-prefixes "!/cargo")
                 '("cargo" t t nil nil))))

(ert-deftest haystack-test/strip-prefixes-literal ()
  (should (equal (haystack--strip-prefixes "=rust")
                 '("rust" nil nil t nil))))

(ert-deftest haystack-test/strip-prefixes-regex ()
  (should (equal (haystack--strip-prefixes "~rus+t")
                 '("rus+t" nil nil nil t))))

(ert-deftest haystack-test/strip-prefixes-negate-and-literal ()
  (should (equal (haystack--strip-prefixes "!=rust")
                 '("rust" t nil t nil))))

(ert-deftest haystack-test/strip-prefixes-negate-and-regex ()
  (should (equal (haystack--strip-prefixes "!~rus+t")
                 '("rus+t" t nil nil t))))

(ert-deftest haystack-test/strip-prefixes-literal-and-regex ()
  (should (equal (haystack--strip-prefixes "=~rus+t")
                 '("rus+t" nil nil t t))))

(ert-deftest haystack-test/strip-prefixes-order-matters ()
  "= before ! is not treated as the literal prefix."
  (should (equal (haystack--strip-prefixes "=!rust")
                 '("!rust" nil nil t nil))))

;;; haystack--multi-word-p

(ert-deftest haystack-test/multi-word-single ()
  (should-not (haystack--multi-word-p "rust")))

(ert-deftest haystack-test/multi-word-hyphenated ()
  "Hyphenated terms are single-word."
  (should-not (haystack--multi-word-p "data-structures")))

(ert-deftest haystack-test/multi-word-dotted ()
  "Dotted terms are single-word."
  (should-not (haystack--multi-word-p "std.io")))

(ert-deftest haystack-test/multi-word-with-space ()
  (should (haystack--multi-word-p "rust ownership")))

(ert-deftest haystack-test/multi-word-with-tab ()
  (should (haystack--multi-word-p "rust\townership")))

;;; haystack--build-pattern

(ert-deftest haystack-test/build-pattern-bare-term-is-quoted ()
  "Bare terms are passed through regexp-quote."
  (should (equal (haystack--build-pattern "C++" nil)
                 (regexp-quote "C++"))))

(ert-deftest haystack-test/build-pattern-regex-is-unquoted ()
  "Raw regex terms are returned as-is."
  (should (equal (haystack--build-pattern "rus+t" t)
                 "rus+t")))

;;;; Expansion Groups

;;; haystack--lookup-group

(ert-deftest haystack-test/lookup-group-finds-root-term ()
  (let ((haystack--expansion-groups '(("programming" . ("coding" "code")))))
    (should (equal (haystack--lookup-group "programming")
                   '("programming" "coding" "code")))))

(ert-deftest haystack-test/lookup-group-finds-member-term ()
  (let ((haystack--expansion-groups '(("programming" . ("coding" "code")))))
    (should (equal (haystack--lookup-group "coding")
                   '("programming" "coding" "code")))))

(ert-deftest haystack-test/lookup-group-case-insensitive ()
  (let ((haystack--expansion-groups '(("Rust" . ("rustlang")))))
    (should (equal (haystack--lookup-group "rust")   '("Rust" "rustlang")))
    (should (equal (haystack--lookup-group "RUSTLANG") '("Rust" "rustlang")))))

(ert-deftest haystack-test/lookup-group-returns-nil-for-unknown ()
  (let ((haystack--expansion-groups '(("rust" . ("rustlang")))))
    (should-not (haystack--lookup-group "python"))))

(ert-deftest haystack-test/lookup-group-empty-groups ()
  (let ((haystack--expansion-groups nil))
    (should-not (haystack--lookup-group "rust"))))

;;; haystack--expansion-alternation

(ert-deftest haystack-test/expansion-alternation-single-member ()
  (should (equal (haystack--expansion-alternation '("rust"))
                 "(rust)")))

(ert-deftest haystack-test/expansion-alternation-multiple-members ()
  (should (equal (haystack--expansion-alternation '("programming" "coding" "code"))
                 "(programming|coding|code)")))

(ert-deftest haystack-test/expansion-alternation-quotes-special-chars ()
  "Members with regex special characters are escaped."
  (should (equal (haystack--expansion-alternation '("C++" "C#"))
                 (concat "(" (regexp-quote "C++") "|" (regexp-quote "C#") ")"))))

;;; haystack--build-pattern (with expansion groups)

(ert-deftest haystack-test/build-pattern-expands-known-term ()
  (let ((haystack--expansion-groups '(("rust" . ("rustlang")))))
    (should (equal (haystack--build-pattern "rust" nil)
                   "(rust|rustlang)"))))

(ert-deftest haystack-test/build-pattern-literal-suppresses-expansion ()
  (let ((haystack--expansion-groups '(("rust" . ("rustlang")))))
    (should (equal (haystack--build-pattern "rust" nil t)
                   (regexp-quote "rust")))))

(ert-deftest haystack-test/build-pattern-multi-word-expands-if-in-group ()
  "Multi-word terms that are in a group still expand."
  (let ((haystack--expansion-groups '(("emacs lisp" . ("elisp")))))
    (should (equal (haystack--build-pattern "emacs lisp" nil)
                   "(emacs lisp|elisp)"))))

(ert-deftest haystack-test/build-pattern-regex-suppresses-expansion ()
  (let ((haystack--expansion-groups '(("rust" . ("rustlang")))))
    (should (equal (haystack--build-pattern "rust" t)
                   "rust"))))

(ert-deftest haystack-test/build-pattern-unknown-term-falls-back-to-quote ()
  (let ((haystack--expansion-groups '(("rust" . ("rustlang")))))
    (should (equal (haystack--build-pattern "python" nil)
                   (regexp-quote "python")))))

;;; haystack--load-expansion-groups

(ert-deftest haystack-test/load-expansion-groups-reads-file ()
  (let ((saved haystack--expansion-groups))
    (unwind-protect
        (haystack-test--with-notes-dir
          (with-temp-file (expand-file-name ".expansion-groups.el" haystack-notes-directory)
            (insert "((\"rust\" . (\"rustlang\")) (\"programming\" . (\"coding\")))"))
          (haystack--load-expansion-groups)
          (should (equal haystack--expansion-groups
                         '(("rust" . ("rustlang")) ("programming" . ("coding"))))))
      (setq haystack--expansion-groups saved))))

(ert-deftest haystack-test/load-expansion-groups-no-file-sets-nil ()
  (let ((saved haystack--expansion-groups))
    (unwind-protect
        (haystack-test--with-notes-dir
          (haystack--load-expansion-groups)
          (should (null haystack--expansion-groups)))
      (setq haystack--expansion-groups saved))))

(ert-deftest haystack-test/load-expansion-groups-parse-error-sets-nil ()
  "An unterminated sexp causes a read error; groups should be nil."
  (let ((saved haystack--expansion-groups))
    (unwind-protect
        (haystack-test--with-notes-dir
          (with-temp-file (expand-file-name ".expansion-groups.el" haystack-notes-directory)
            (insert "((("))           ; unterminated — triggers end-of-file error
          (haystack--load-expansion-groups)
          (should (null haystack--expansion-groups)))
      (setq haystack--expansion-groups saved))))

;;; haystack-validate-groups

(ert-deftest haystack-test/validate-groups-no-conflicts-messages ()
  (let ((haystack--expansion-groups '(("rust" . ("rustlang"))
                                      ("python" . ("py")))))
    (haystack-validate-groups)
    ;; No conflict buffer should have been created.
    (should-not (get-buffer "*haystack-group-conflicts*"))))

(ert-deftest haystack-test/validate-groups-conflicts-pops-buffer ()
  "A term in two groups triggers the conflict buffer."
  (let ((haystack--expansion-groups '(("rust" . ("rustlang" "coding"))
                                      ("programming" . ("coding")))))
    (unwind-protect
        (progn
          (haystack-validate-groups)
          (should (get-buffer "*haystack-group-conflicts*")))
      (when (get-buffer "*haystack-group-conflicts*")
        (kill-buffer "*haystack-group-conflicts*")))))

;;; haystack--groups-remove-term

(ert-deftest haystack-test/groups-remove-member-term ()
  "Removing a member leaves root and remaining members."
  (let ((haystack--expansion-groups '(("rust" . ("rustlang" "rs")))))
    (should (equal (haystack--groups-remove-term haystack--expansion-groups "rustlang")
                   '(("rust" . ("rs")))))))

(ert-deftest haystack-test/groups-remove-root-promotes-first-member ()
  "Removing the root promotes the first member."
  (let ((groups '(("programming" . ("coding" "code")))))
    (should (equal (haystack--groups-remove-term groups "programming")
                   '(("coding" . ("code")))))))

(ert-deftest haystack-test/groups-remove-dissolves-two-term-group ()
  "Removing one term from a two-term group dissolves it."
  (let ((groups '(("rust" . ("rustlang")) ("python" . ("py")))))
    (should (equal (haystack--groups-remove-term groups "rustlang")
                   '(("python" . ("py")))))))

(ert-deftest haystack-test/groups-remove-is-case-insensitive ()
  (let ((groups '(("Rust" . ("Rustlang")))))
    (should (equal (haystack--groups-remove-term groups "rust")
                   nil))))

(ert-deftest haystack-test/groups-remove-unrelated-term-unchanged ()
  (let ((groups '(("rust" . ("rustlang")))))
    (should (equal (haystack--groups-remove-term groups "python")
                   groups))))

;;; haystack--groups-add-to-group

(ert-deftest haystack-test/groups-add-to-existing-group-via-root ()
  (let ((groups '(("rust" . ("rustlang")))))
    (should (equal (haystack--groups-add-to-group groups "rust" "rs")
                   '(("rust" . ("rustlang" "rs")))))))

(ert-deftest haystack-test/groups-add-to-existing-group-via-member ()
  "Adding via a member term adds to that member's group."
  (let ((groups '(("rust" . ("rustlang")))))
    (should (equal (haystack--groups-add-to-group groups "rustlang" "rs")
                   '(("rust" . ("rustlang" "rs")))))))

(ert-deftest haystack-test/groups-add-creates-new-group-when-anchor-unassigned ()
  (let ((groups '(("python" . ("py")))))
    (should (equal (haystack--groups-add-to-group groups "rust" "rustlang")
                   '(("python" . ("py")) ("rust" . ("rustlang")))))))

;;; haystack-associate

(defmacro haystack-test--with-groups (initial-groups &rest body)
  "Run BODY with `haystack--expansion-groups' bound to INITIAL-GROUPS.
Saves and restores the global; also creates a temp notes directory so
`haystack--save-expansion-groups' has a valid place to write.
Writes INITIAL-GROUPS to disk so functions that call
`haystack--load-expansion-groups' see the expected state."
  (declare (indent 1))
  `(let ((saved haystack--expansion-groups))
     (unwind-protect
         (haystack-test--with-notes-dir
           (setq haystack--expansion-groups ,initial-groups)
           (when ,initial-groups
             (haystack--save-expansion-groups))
           ,@body)
       (setq haystack--expansion-groups saved))))

(ert-deftest haystack-test/associate-creates-new-group ()
  "Both terms unassigned → new group created."
  (haystack-test--with-groups nil
    (haystack-associate "rust" "rustlang")
    (should (equal haystack--expansion-groups
                   '(("rust" . ("rustlang")))))))

(ert-deftest haystack-test/associate-adds-b-to-a-group ()
  "B unassigned, A has group → B added to A's group."
  (haystack-test--with-groups '(("rust" . ("rustlang")))
    (haystack-associate "rust" "rs")
    (should (equal haystack--expansion-groups
                   '(("rust" . ("rustlang" "rs")))))))

(ert-deftest haystack-test/associate-adds-a-to-b-group ()
  "A unassigned, B has group → A added to B's group."
  (haystack-test--with-groups '(("rust" . ("rustlang")))
    (haystack-associate "rs" "rust")
    (should (equal haystack--expansion-groups
                   '(("rust" . ("rustlang" "rs")))))))

(ert-deftest haystack-test/associate-same-group-is-noop ()
  "Both already in the same group → no change."
  (let ((groups '(("rust" . ("rustlang")))))
    (haystack-test--with-groups groups
      (haystack-associate "rust" "rustlang")
      (should (equal haystack--expansion-groups groups)))))

(ert-deftest haystack-test/associate-accepts-multi-word ()
  "Multi-word terms can now be added to expansion groups."
  (haystack-test--with-groups nil
    (haystack-associate "emacs lisp" "elisp")
    (should (haystack--lookup-group "emacs lisp"))
    (should (haystack--lookup-group "elisp"))))

(ert-deftest haystack-test/associate-rejects-same-term ()
  (haystack-test--with-groups nil
    (should-error (haystack-associate "rust" "rust")
                  :type 'user-error)))

(ert-deftest haystack-test/associate-saves-to-file ()
  "After associate, the groups file is written."
  (haystack-test--with-groups nil
    (haystack-associate "rust" "rustlang")
    (should (file-exists-p (haystack--expansion-groups-file)))))

;;; haystack--groups-rename-root

(ert-deftest haystack-test/groups-rename-root-updates-root ()
  "Renames the root of the matching group."
  (let ((result (haystack--groups-rename-root
                 '(("rust" . ("rustlang" "rs")))
                 "rust" "Rust")))
    (should (equal result '(("Rust" . ("rustlang" "rs")))))))

(ert-deftest haystack-test/groups-rename-root-leaves-other-groups ()
  "Other groups are not affected."
  (let ((result (haystack--groups-rename-root
                 '(("rust" . ("rustlang")) ("python" . ("py")))
                 "rust" "Rust")))
    (should (equal (cadr result) '("python" . ("py"))))))

(ert-deftest haystack-test/groups-rename-root-case-insensitive ()
  "Root matching is case-insensitive."
  (let ((result (haystack--groups-rename-root
                 '(("Rust" . ("rustlang")))
                 "rust" "rs-lang")))
    (should (equal (caar result) "rs-lang"))))

;;; haystack-rename-group-root

(ert-deftest haystack-test/rename-group-root-updates-group ()
  "Renames the root and saves."
  (haystack-test--with-groups '(("rust" . ("rustlang")))
    (haystack-rename-group-root "rust" "rs")
    (should (equal haystack--expansion-groups '(("rs" . ("rustlang")))))))

(ert-deftest haystack-test/rename-group-root-errors-on-member-term ()
  "Errors if the given term is a member, not the root."
  (haystack-test--with-groups '(("rust" . ("rustlang")))
    (should-error (haystack-rename-group-root "rustlang" "newname")
                  :type 'user-error)))

(ert-deftest haystack-test/rename-group-root-errors-on-unknown-term ()
  "Errors if the term is not in any group."
  (haystack-test--with-groups '(("rust" . ("rustlang")))
    (should-error (haystack-rename-group-root "python" "py")
                  :type 'user-error)))

(ert-deftest haystack-test/rename-group-root-accepts-multiword ()
  "Multi-word new root names are now allowed."
  (haystack-test--with-groups '(("rust" . ("rustlang")))
    (haystack-rename-group-root "rust" "rust lang")
    (should (haystack--lookup-group "rust lang"))
    (should (haystack--lookup-group "rustlang"))))

(ert-deftest haystack-test/rename-group-root-errors-if-new-name-taken ()
  "Errors if the new name is already in any group."
  (haystack-test--with-groups '(("rust" . ("rustlang")) ("python" . ("py")))
    (should-error (haystack-rename-group-root "rust" "python")
                  :type 'user-error)))

(ert-deftest haystack-test/rename-group-root-errors-if-same-name ()
  "Errors if old and new names are the same."
  (haystack-test--with-groups '(("rust" . ("rustlang")))
    (should-error (haystack-rename-group-root "rust" "rust")
                  :type 'user-error)))

;;; haystack--groups-dissolve

(ert-deftest haystack-test/groups-dissolve-by-root ()
  "Dissolving by root removes the entire group."
  (let ((result (haystack--groups-dissolve
                 '(("rust" . ("rustlang" "rs"))) "rust")))
    (should (null result))))

(ert-deftest haystack-test/groups-dissolve-by-member ()
  "Dissolving by a member term removes the group."
  (let ((result (haystack--groups-dissolve
                 '(("rust" . ("rustlang" "rs"))) "rustlang")))
    (should (null result))))

(ert-deftest haystack-test/groups-dissolve-leaves-other-groups ()
  "Other groups are not affected."
  (let ((result (haystack--groups-dissolve
                 '(("rust" . ("rustlang")) ("python" . ("py"))) "rust")))
    (should (equal result '(("python" . ("py")))))))

;;; haystack-dissolve-group

(ert-deftest haystack-test/dissolve-group-removes-group ()
  "Removes the group and saves."
  (haystack-test--with-groups '(("rust" . ("rustlang")))
    (haystack-dissolve-group "rust")
    (should (null haystack--expansion-groups))))

(ert-deftest haystack-test/dissolve-group-by-member-term ()
  "Can dissolve by passing a member term rather than the root."
  (haystack-test--with-groups '(("rust" . ("rustlang")))
    (haystack-dissolve-group "rustlang")
    (should (null haystack--expansion-groups))))

(ert-deftest haystack-test/dissolve-group-errors-on-unknown-term ()
  "Errors if the term is not in any group."
  (haystack-test--with-groups '(("rust" . ("rustlang")))
    (should-error (haystack-dissolve-group "python") :type 'user-error)))

(ert-deftest haystack-test/dissolve-group-leaves-other-groups ()
  "Other groups survive dissolution."
  (haystack-test--with-groups '(("rust" . ("rustlang")) ("python" . ("py")))
    (haystack-dissolve-group "rust")
    (should (equal haystack--expansion-groups '(("python" . ("py")))))))

;;; haystack--build-emacs-pattern

(ert-deftest haystack-test/build-emacs-pattern-bare-term-is-quoted ()
  (should (equal (haystack--build-emacs-pattern "C++" nil)
                 (regexp-quote "C++"))))

(ert-deftest haystack-test/build-emacs-pattern-regex-passthrough ()
  (should (equal (haystack--build-emacs-pattern "rus+t" t)
                 "rus+t")))

(ert-deftest haystack-test/build-emacs-pattern-expansion-uses-emacs-alternation ()
  "Expansion group produces \\| alternation, not ripgrep | alternation."
  (let ((haystack--expansion-groups '(("programming" . ("coding")))))
    (should (equal (haystack--build-emacs-pattern "programming" nil)
                   "programming\\|coding"))))

(ert-deftest haystack-test/build-emacs-pattern-literal-suppresses-expansion ()
  (let ((haystack--expansion-groups '(("rust" . ("rustlang")))))
    (should (equal (haystack--build-emacs-pattern "rust" nil t)
                   (regexp-quote "rust")))))

;;; haystack--parse-input :emacs-pattern

(ert-deftest haystack-test/parse-input-emacs-pattern-bare ()
  "Bare term without groups: :emacs-pattern equals regexp-quote."
  (let ((haystack--expansion-groups nil))
    (should (equal (plist-get (haystack--parse-input "rust") :emacs-pattern)
                   (regexp-quote "rust")))))

(ert-deftest haystack-test/parse-input-emacs-pattern-uses-emacs-syntax ()
  "With expansion, :emacs-pattern uses \\| not | so string-match-p works."
  (let ((haystack--expansion-groups '(("programming" . ("coding")))))
    (let ((ep (plist-get (haystack--parse-input "programming") :emacs-pattern)))
      ;; Must match both terms via Emacs string-match-p
      (should (string-match-p ep "programming"))
      (should (string-match-p ep "coding"))
      ;; The ripgrep pattern (programming|coding) would NOT match via Emacs:
      (should-not (string-match-p (plist-get (haystack--parse-input "programming") :pattern)
                                  "coding")))))

;;; filename negation with expansion (regression for !filename= bug)

(ert-deftest haystack-test/filter-further-negated-filename-with-expansion ()
  "!filename= with an expanded term excludes files matching any group member."
  (let ((haystack--expansion-groups '(("coding" . ("programming")))))
    (haystack-test--with-notes-dir
      (let* ((keep   (expand-file-name "unrelated.org" haystack-notes-directory))
             (exclude (expand-file-name "coding-notes.org" haystack-notes-directory)))
        (with-temp-file keep    (insert "some content\n"))
        (with-temp-file exclude (insert "some content\n"))
        (let* ((root-output (concat keep ":1:some content\n"
                                    exclude ":1:some content\n"))
               (buf (haystack--setup-results-buffer
                     "*haystack:1:coding*"
                     ";;;; test\n" root-output
                     (list :root-term "coding" :root-expanded "some content"
                           :root-literal nil :root-regex nil :root-filename nil
                           :root-expansion nil :filters nil :composite-filter 'all))))
          (with-current-buffer buf
            (setq default-directory (file-name-as-directory haystack-notes-directory))
            (haystack-filter-further "!/coding")
            (let ((result (buffer-string)))
              (should (string-match-p "unrelated" result))
              (should-not (string-match-p "coding-notes" result))))
          (kill-buffer buf))))))

;;; haystack--parse-input (with expansion)

(ert-deftest haystack-test/parse-input-expansion-fires-for-known-term ()
  (let ((haystack--expansion-groups '(("rust" . ("rustlang")))))
    (let ((result (haystack--parse-input "rust")))
      (should (equal (plist-get result :expansion) '("rust" "rustlang")))
      (should (equal (plist-get result :pattern)   "(rust|rustlang)")))))

(ert-deftest haystack-test/parse-input-literal-suppresses-expansion ()
  (let ((haystack--expansion-groups '(("rust" . ("rustlang")))))
    (let ((result (haystack--parse-input "=rust")))
      (should-not (plist-get result :expansion))
      (should (equal (plist-get result :pattern) (regexp-quote "rust"))))))

(ert-deftest haystack-test/parse-input-no-expansion-for-unknown-term ()
  (let ((haystack--expansion-groups nil))
    (let ((result (haystack--parse-input "rust")))
      (should-not (plist-get result :expansion))
      (should (equal (plist-get result :pattern) (regexp-quote "rust"))))))

;;; haystack--parse-input (integration)

(ert-deftest haystack-test/parse-input-bare ()
  (let ((result (haystack--parse-input "rust")))
    (should (equal (plist-get result :term)       "rust"))
    (should (equal (plist-get result :negated)    nil))
    (should (equal (plist-get result :filename)   nil))
    (should (equal (plist-get result :literal)    nil))
    (should (equal (plist-get result :regex)      nil))
    (should (equal (plist-get result :multi-word) nil))
    (should (equal (plist-get result :pattern)    (regexp-quote "rust")))))

(ert-deftest haystack-test/parse-input-filename ()
  "/prefix sets :filename and strips the slash."
  (let ((result (haystack--parse-input "/cargo")))
    (should (equal (plist-get result :term)     "cargo"))
    (should (equal (plist-get result :filename) t))
    (should (equal (plist-get result :negated)  nil))
    (should (equal (plist-get result :pattern)  (regexp-quote "cargo")))))

(ert-deftest haystack-test/parse-input-negated-filename ()
  "!/prefix sets both :negated and :filename."
  (let ((result (haystack--parse-input "!/cargo")))
    (should (equal (plist-get result :term)     "cargo"))
    (should (equal (plist-get result :filename) t))
    (should (equal (plist-get result :negated)  t))))

(ert-deftest haystack-test/parse-input-negated-regex ()
  (let ((result (haystack--parse-input "!~rus+t")))
    (should (equal (plist-get result :term)    "rus+t"))
    (should (equal (plist-get result :negated) t))
    (should (equal (plist-get result :regex)   t))
    (should (equal (plist-get result :pattern) "rus+t"))))

(ert-deftest haystack-test/parse-input-multi-word-no-group ()
  "Multi-word terms without a group fall back to regexp-quote."
  (let ((result (haystack--parse-input "rust ownership")))
    (should (plist-get result :multi-word))
    (should (equal (plist-get result :pattern) (regexp-quote "rust ownership")))))

(ert-deftest haystack-test/parse-input-multi-word-expands ()
  "Multi-word terms that are in a group expand."
  (let* ((haystack--expansion-groups '(("emacs lisp" . ("elisp"))))
         (result (haystack--parse-input "emacs lisp")))
    (should (plist-get result :multi-word))
    (should (plist-get result :expansion))
    (should (string-match-p "elisp" (plist-get result :pattern)))))

(ert-deftest haystack-test/parse-input-special-chars-quoted ()
  "Special regex characters in bare terms are escaped."
  (let ((result (haystack--parse-input "C++")))
    (should (equal (plist-get result :pattern) (regexp-quote "C++")))))

;;;; haystack--strip-notes-prefix

(ert-deftest haystack-test/strip-notes-prefix-removes-prefix ()
  "Strips the notes directory prefix from a grep line's path."
  (let ((haystack-notes-directory "/notes"))
    (should (equal (haystack--strip-notes-prefix "/notes/foo.org:1:content")
                   "foo.org:1:content"))))

(ert-deftest haystack-test/strip-notes-prefix-preserves-subdirectories ()
  "Retains subdirectory structure after the notes root."
  (let ((haystack-notes-directory "/notes"))
    (should (equal (haystack--strip-notes-prefix "/notes/sub/foo.org:1:content")
                   "sub/foo.org:1:content"))))

(ert-deftest haystack-test/strip-notes-prefix-leaves-header-lines ()
  "Header lines (;;;) are passed through unchanged."
  (let ((haystack-notes-directory "/notes"))
    (should (equal (haystack--strip-notes-prefix ";;;; Haystack")
                   ";;;; Haystack"))))

(ert-deftest haystack-test/strip-notes-prefix-multiline ()
  "All lines in a multi-line string are processed independently."
  (let ((haystack-notes-directory "/notes"))
    (should (equal (haystack--strip-notes-prefix
                    (mapconcat #'identity
                               '(";;;; header"
                                 "/notes/a.org:1:match"
                                 "/notes/sub/b.org:2:match")
                               "\n"))
                   (mapconcat #'identity
                              '(";;;; header"
                                "a.org:1:match"
                                "sub/b.org:2:match")
                              "\n")))))

(ert-deftest haystack-test/strip-notes-prefix-unrelated-path-unchanged ()
  "A path outside the notes directory is not modified."
  (let ((haystack-notes-directory "/notes"))
    (should (equal (haystack--strip-notes-prefix "/other/foo.org:1:content")
                   "/other/foo.org:1:content"))))

;;;; haystack--build-rg-args

(ert-deftest haystack-test/rg-args-excludes-composites-by-default ()
  "No composite-filter argument produces --glob=!@*."
  (let ((haystack-notes-directory "/notes")
        (haystack-file-glob nil))
    (should (member "--glob=!@*" (haystack--build-rg-args "rust")))))

(ert-deftest haystack-test/rg-args-exclude-symbol ()
  "'exclude produces --glob=!@*."
  (let ((haystack-notes-directory "/notes")
        (haystack-file-glob nil))
    (should (member "--glob=!@*" (haystack--build-rg-args "rust" 'exclude)))))

(ert-deftest haystack-test/rg-args-only-symbol ()
  "'only produces --glob=@* with no negation variant."
  (let ((haystack-notes-directory "/notes")
        (haystack-file-glob nil))
    (let ((args (haystack--build-rg-args "rust" 'only)))
      (should (member "--glob=@*" args))
      (should-not (member "--glob=!@*" args)))))

(ert-deftest haystack-test/rg-args-all-symbol ()
  "'all produces no @* glob at all."
  (let ((haystack-notes-directory "/notes")
        (haystack-file-glob nil))
    (should-not (cl-some (lambda (a) (string-match-p "@\\*" a))
                         (haystack--build-rg-args "rust" 'all)))))

(ert-deftest haystack-test/rg-args-applies-file-glob ()
  "`haystack-file-glob' entries appear as --glob= arguments."
  (let ((haystack-notes-directory "/notes")
        (haystack-file-glob '("*.org" "*.md")))
    (let ((args (haystack--build-rg-args "rust" 'exclude)))
      (should (member "--glob=*.org" args))
      (should (member "--glob=*.md" args)))))

(ert-deftest haystack-test/rg-args-contains-pattern-and-directory ()
  "Pattern and notes directory appear as the final two arguments."
  (let ((haystack-notes-directory "/my/notes")
        (haystack-file-glob nil))
    (let ((args (haystack--build-rg-args "mypattern" 'exclude)))
      (should (member "mypattern" args))
      (should (member "/my/notes" args)))))

(ert-deftest haystack-test/rg-args-expands-tilde-in-directory ()
  "A ~ in `haystack-notes-directory' is expanded to an absolute path."
  (let ((haystack-notes-directory "~/notes")
        (haystack-file-glob nil))
    (let ((args (haystack--build-rg-args "rust" 'exclude)))
      (should-not (member "~/notes" args))
      (should (member (expand-file-name "~/notes") args)))))

;;;; haystack--truncate-content

(ert-deftest haystack-test/truncate-content-short-unchanged ()
  "Content within the width is returned as-is."
  (let ((haystack-context-width 60))
    (should (equal (haystack--truncate-content "short content" "short")
                   "short content"))))

(ert-deftest haystack-test/truncate-content-long-adds-ellipsis ()
  "Content longer than width is truncated with ellipsis."
  (let* ((haystack-context-width 20)
         (content (concat (make-string 30 ?a) "MATCH" (make-string 30 ?b)))
         (result (haystack--truncate-content content "MATCH")))
    (should (<= (length result) (+ 20 6))) ; width + two "..."
    (should (string-match-p "MATCH" result))))

(ert-deftest haystack-test/truncate-content-match-at-start-no-left-ellipsis ()
  "Match near the start produces no left ellipsis."
  (let* ((haystack-context-width 20)
         (content (concat "MATCH" (make-string 50 ?x)))
         (result (haystack--truncate-content content "MATCH")))
    (should-not (string-prefix-p "..." result))
    (should (string-suffix-p "..." result))))

(ert-deftest haystack-test/truncate-content-match-at-end-no-right-ellipsis ()
  "Match near the end produces no right ellipsis."
  (let* ((haystack-context-width 20)
         (content (concat (make-string 50 ?x) "MATCH"))
         (result (haystack--truncate-content content "MATCH")))
    (should (string-prefix-p "..." result))
    (should-not (string-suffix-p "..." result))))

(ert-deftest haystack-test/truncate-content-case-insensitive ()
  "Pattern matching is case-insensitive."
  (let* ((haystack-context-width 20)
         (content (concat (make-string 30 ?a) "match" (make-string 30 ?b)))
         (result (haystack--truncate-content content "MATCH")))
    (should (string-match-p "match" result))))

;;;; haystack--truncate-output

(ert-deftest haystack-test/truncate-output-preserves-prefix ()
  "The file:line: prefix is preserved after truncation."
  (let ((haystack-context-width 20)
        (line (concat "/notes/foo.org:12:" (make-string 80 ?x) "TERM" (make-string 80 ?x))))
    (let ((result (haystack--truncate-output line "TERM")))
      (should (string-prefix-p "/notes/foo.org:12:" result)))))

(ert-deftest haystack-test/truncate-output-leaves-short-lines-intact ()
  "Lines whose content is within the width are not modified."
  (let ((haystack-context-width 60)
        (line "/notes/foo.org:1:short content"))
    (should (equal (haystack--truncate-output line "short") line))))

(ert-deftest haystack-test/truncate-output-handles-non-match-lines ()
  "Lines that don't match the file:line: format are passed through unchanged."
  (let ((haystack-context-width 20)
        (line "this is not a grep line"))
    (should (equal (haystack--truncate-output line "grep") line))))

;;;; haystack--count-search-stats

(ert-deftest haystack-test/count-stats-empty-output ()
  "Empty output yields 0 files and 0 matches."
  (should (equal (haystack--count-search-stats "") '(0 . 0))))

(ert-deftest haystack-test/count-stats-single-file ()
  "One matching line yields 1 file and 1 match."
  (should (equal (haystack--count-search-stats "/notes/foo.org:12:some content")
                 '(1 . 1))))

(ert-deftest haystack-test/count-stats-multiple-matches-same-file ()
  "Multiple matches in one file count as 1 file, N matches."
  (let ((output (mapconcat #'identity
                           '("/notes/foo.org:1:line one"
                             "/notes/foo.org:2:line two"
                             "/notes/foo.org:3:line three")
                           "\n")))
    (should (equal (haystack--count-search-stats output) '(1 . 3)))))

(ert-deftest haystack-test/count-stats-multiple-files ()
  "Matches across two distinct files count as 2 files."
  (let ((output (mapconcat #'identity
                           '("/notes/foo.org:1:match"
                             "/notes/bar.md:5:match")
                           "\n")))
    (should (equal (haystack--count-search-stats output) '(2 . 2)))))

;;;; haystack--rg-base-args

(ert-deftest haystack-test/rg-base-args-exclude ()
  (should (member "--glob=!@*" (haystack--rg-base-args 'exclude))))

(ert-deftest haystack-test/rg-base-args-only ()
  (let ((args (haystack--rg-base-args 'only)))
    (should (member "--glob=@*" args))
    (should-not (member "--glob=!@*" args))))

(ert-deftest haystack-test/rg-base-args-all ()
  (should-not (cl-some (lambda (a) (string-match-p "@\\*" a))
                       (haystack--rg-base-args 'all))))

(ert-deftest haystack-test/rg-base-args-default-is-exclude ()
  (should (member "--glob=!@*" (haystack--rg-base-args))))

;;;; haystack--write-filelist

(ert-deftest haystack-test/write-filelist-creates-file ()
  "Creates a temp file containing null-separated paths (for xargs -0)."
  (let* ((files '("/notes/a.org" "/notes/b.org"))
         (tmp   (haystack--write-filelist files)))
    (unwind-protect
        (progn
          (should (file-exists-p tmp))
          (should (equal (split-string (with-temp-buffer
                                         (insert-file-contents tmp)
                                         (buffer-string))
                                       "\0" t)
                         files)))
      (delete-file tmp))))

;;;; haystack--xargs-rg

(ert-deftest haystack-test/xargs-rg-returns-matches ()
  "Returns grep-format output for a matching search."
  (haystack-test--with-notes-dir
   (let* ((note (expand-file-name "test.org" haystack-notes-directory))
          (tmp  (progn (with-temp-file note (insert "hello world\n"))
                       (haystack--write-filelist (list note)))))
     (unwind-protect
         (should (string-match-p "hello"
                  (haystack--xargs-rg tmp (list "--ignore-case" "hello"))))
       (delete-file tmp)))))

(ert-deftest haystack-test/xargs-rg-empty-on-no-matches ()
  "A search with no matches returns an empty string without signalling."
  (haystack-test--with-notes-dir
   (let* ((note (expand-file-name "test.org" haystack-notes-directory))
          (tmp  (progn (with-temp-file note (insert "hello world\n"))
                       (haystack--write-filelist (list note)))))
     (unwind-protect
         (should (string-empty-p
                  (haystack--xargs-rg tmp (list "nomatchxyz99"))))
       (delete-file tmp)))))

(ert-deftest haystack-test/xargs-rg-errors-on-stderr ()
  "Signals user-error when rg writes to stderr (e.g. bad pattern)."
  (haystack-test--with-notes-dir
   (let* ((note (expand-file-name "test.org" haystack-notes-directory))
          (tmp  (progn (with-temp-file note (insert "hello\n"))
                       (haystack--write-filelist (list note)))))
     (unwind-protect
         ;; An invalid regex causes rg to write to stderr and exit non-zero.
         (should-error
          (haystack--xargs-rg tmp (list "--line-number" "**invalid**"))
          :type 'user-error)
       (delete-file tmp)))))

(ert-deftest haystack-test/xargs-rg-dollar-sign-not-expanded ()
  "A pattern containing $ is not expanded — no shell involved."
  (haystack-test--with-notes-dir
   (let* ((note (expand-file-name "test.org" haystack-notes-directory))
          (tmp  (progn (with-temp-file note (insert "price $100\n"))
                       (haystack--write-filelist (list note)))))
     (unwind-protect
         (should (string-match-p "\\$100"
                  (haystack--run-rg-for-filelist "\\$100" tmp 'all)))
       (delete-file tmp)))))

(ert-deftest haystack-test/xargs-rg-shell-metacharacters-literal ()
  "Patterns containing & | ; are passed through without shell interpretation."
  (haystack-test--with-notes-dir
   (let* ((note (expand-file-name "test.org" haystack-notes-directory))
          (tmp  (progn (with-temp-file note (insert "foo & bar | baz\n"))
                       (haystack--write-filelist (list note)))))
     (unwind-protect
         (should (string-match-p "foo & bar"
                  (haystack--run-rg-for-filelist "foo & bar" tmp 'all)))
       (delete-file tmp)))))

;;;; haystack--extract-filenames

(ert-deftest haystack-test/extract-filenames-basic ()
  "Extracts unique filenames from grep output."
  (let ((text (mapconcat #'identity
                         '("/notes/foo.org:1:match"
                           "/notes/bar.org:5:match"
                           "/notes/foo.org:9:match")
                         "\n")))
    (should (equal (haystack--extract-filenames text)
                   '("/notes/foo.org" "/notes/bar.org")))))

(ert-deftest haystack-test/extract-filenames-skips-header ()
  "Header lines starting with ;;; are ignored."
  (let ((text ";;; haystack: root=rust | 1 files, 1 matches\n/notes/foo.org:1:match"))
    (should (equal (haystack--extract-filenames text)
                   '("/notes/foo.org")))))

(ert-deftest haystack-test/extract-filenames-empty ()
  "Empty output returns nil."
  (should (null (haystack--extract-filenames ""))))

(ert-deftest haystack-test/extract-filenames-expands-relative-paths ()
  "Relative paths are expanded to absolute using `default-directory'."
  (let ((default-directory "/notes/"))
    (should (equal (haystack--extract-filenames "sub/foo.org:1:match")
                   '("/notes/sub/foo.org")))))

(ert-deftest haystack-test/extract-filenames-preserves-order ()
  "Files are returned in first-seen order."
  (let ((text (mapconcat #'identity
                         '("/notes/a.org:1:x"
                           "/notes/b.org:1:x"
                           "/notes/c.org:1:x")
                         "\n")))
    (should (equal (haystack--extract-filenames text)
                   '("/notes/a.org" "/notes/b.org" "/notes/c.org")))))

;;;; haystack--format-search-chain

(ert-deftest haystack-test/format-chain-single-filter ()
  "Root + one positive filter shows both terms."
  (let ((descriptor (list :root-term "rust" :filters nil)))
    (should (equal (haystack--format-search-chain descriptor "async" nil)
                   "root=rust > filter=async"))))

(ert-deftest haystack-test/format-chain-negated-filter ()
  "Negated filter shows as exclude=."
  (let ((descriptor (list :root-term "rust" :filters nil)))
    (should (equal (haystack--format-search-chain descriptor "ownership" t)
                   "root=rust > exclude=ownership"))))

(ert-deftest haystack-test/format-chain-deep-chain ()
  "Full chain shows all prior filters plus the current one."
  (let ((descriptor (list :root-term "rust"
                          :filters (list (list :term "async"  :negated nil)
                                         (list :term "tokio"  :negated nil)))))
    (should (equal (haystack--format-search-chain descriptor "ownership" t)
                   "root=rust > filter=async > filter=tokio > exclude=ownership"))))

(ert-deftest haystack-test/format-chain-filename-filter ()
  "Filename filter shows as filename=."
  (let ((descriptor (list :root-term "rust" :filters nil)))
    (should (equal (haystack--format-search-chain descriptor "cargo" nil t)
                   "root=rust > filename=cargo"))))

(ert-deftest haystack-test/format-chain-negated-filename-filter ()
  "Negated filename filter shows as !filename=."
  (let ((descriptor (list :root-term "rust" :filters nil)))
    (should (equal (haystack--format-search-chain descriptor "cargo" t t)
                   "root=rust > !filename=cargo"))))

(ert-deftest haystack-test/format-chain-filename-root ()
  "A filename root search shows filename= as the root label."
  (let ((descriptor (list :root-term "cargo" :root-filename t :filters nil)))
    (should (equal (haystack--format-search-chain descriptor "async" nil)
                   "filename=cargo > filter=async"))))

(ert-deftest haystack-test/format-chain-mixed-filters ()
  "Chain with a filename filter in history renders correctly."
  (let ((descriptor (list :root-term "rust"
                          :filters (list (list :term "cargo" :negated nil :filename t)))))
    (should (equal (haystack--format-search-chain descriptor "async" nil)
                   "root=rust > filename=cargo > filter=async"))))

;;;; haystack--child-buffer-name

(ert-deftest haystack-test/child-buffer-name-depth-2 ()
  "First filter produces depth 2 name."
  (let ((descriptor (list :root-term "rust" :root-filename nil
                          :root-literal nil :root-regex nil :filters nil)))
    (should (equal (haystack--child-buffer-name descriptor "async" nil nil nil nil)
                   "*haystack:2:rust:async*"))))

(ert-deftest haystack-test/child-buffer-name-depth-3 ()
  "Second filter produces depth 3 name with full chain."
  (let ((descriptor (list :root-term "rust" :root-filename nil
                          :root-literal nil :root-regex nil
                          :filters (list (list :term "async" :negated nil
                                               :filename nil :literal nil :regex nil)))))
    (should (equal (haystack--child-buffer-name descriptor "ownership" nil nil nil nil)
                   "*haystack:3:rust:async:ownership*"))))

(ert-deftest haystack-test/child-buffer-name-with-modifiers ()
  "Modifier flags appear as prefixes in the buffer name."
  (let ((descriptor (list :root-term "rust" :root-filename nil
                          :root-literal nil :root-regex nil :filters nil)))
    (should (equal (haystack--child-buffer-name descriptor "async" t nil nil nil)
                   "*haystack:2:rust:!async*"))
    (should (equal (haystack--child-buffer-name descriptor "notes" nil t nil nil)
                   "*haystack:2:rust:/notes*"))))

;;;; haystack-filter-further

(ert-deftest haystack-test/filter-further-errors-outside-haystack-buffer ()
  "Signals user-error when not in a haystack results buffer."
  (with-temp-buffer
    (should-error (haystack-filter-further "rust") :type 'user-error)))

(ert-deftest haystack-test/filter-further-errors-on-empty-buffer ()
  "Signals user-error when the current buffer has no result files."
  (with-temp-buffer
    (setq haystack--search-descriptor
          (list :root-term "rust" :root-expanded "rust"
                :filters nil :composite-filter 'exclude))
    (insert ";;; haystack: root=rust | 0 files, 0 matches\n")
    (should-error (haystack-filter-further "async") :type 'user-error)))

(ert-deftest haystack-test/filter-further-creates-child-buffer ()
  "Creates a correctly named child buffer with header and parent set."
  (haystack-test--with-notes-dir
   ;; Create a note that matches both terms.
   (let ((note (expand-file-name "20240101000000-test.org" haystack-notes-directory)))
     (with-temp-file note (insert "rust async content\n")))
   (cl-letf (((symbol-function 'pop-to-buffer)    #'ignore)
             ((symbol-function 'switch-to-buffer) #'ignore))
     ;; Run root search to get a real results buffer.
     (haystack-run-root-search "rust")
     (let ((root-buf (get-buffer "*haystack:1:rust*")))
       (should root-buf)
       (unwind-protect
           (with-current-buffer root-buf
             (haystack-filter-further "async")
             (let ((child-buf (get-buffer "*haystack:2:rust:async*")))
               (should child-buf)
               (unwind-protect
                   (with-current-buffer child-buf
                     (should (string-match-p "root=rust > filter=async"
                                             (buffer-string)))
                     (should (eq haystack--parent-buffer root-buf)))
                 (kill-buffer child-buf))))
         (kill-buffer root-buf))))))

(ert-deftest haystack-test/filter-further-filename-narrows-by-name ()
  "A /term filename filter narrows to files whose relative path matches."
  (haystack-test--with-notes-dir
   (let ((match-note (expand-file-name "20240101000000-cargo-notes.org"
                                       haystack-notes-directory))
         (other-note (expand-file-name "20240101000001-async-notes.org"
                                       haystack-notes-directory)))
     (with-temp-file match-note (insert "rust async content\n"))
     (with-temp-file other-note (insert "rust other content\n")))
   (cl-letf (((symbol-function 'pop-to-buffer)    #'ignore)
             ((symbol-function 'switch-to-buffer) #'ignore))
     (haystack-run-root-search "rust")
     (let ((root-buf (get-buffer "*haystack:1:rust*")))
       (unwind-protect
           (with-current-buffer root-buf
             (haystack-filter-further "/cargo")
             (let ((child-buf (get-buffer "*haystack:2:rust:/cargo*")))
               (unwind-protect
                   (with-current-buffer child-buf
                     (should (string-match-p "filename=cargo" (buffer-string)))
                     (should (string-match-p "cargo-notes" (buffer-string)))
                     (should-not (string-match-p "async-notes" (buffer-string))))
                 (when child-buf (kill-buffer child-buf)))))
         (kill-buffer root-buf))))))

(ert-deftest haystack-test/filter-further-negated-filename ()
  "A !/term filter excludes files whose relative path matches."
  (haystack-test--with-notes-dir
   (let ((keep-note (expand-file-name "20240101000000-cargo-notes.org"
                                      haystack-notes-directory))
         (drop-note (expand-file-name "20240101000001-async-notes.org"
                                      haystack-notes-directory)))
     (with-temp-file keep-note (insert "rust content\n"))
     (with-temp-file drop-note (insert "rust content\n")))
   (cl-letf (((symbol-function 'pop-to-buffer)    #'ignore)
             ((symbol-function 'switch-to-buffer) #'ignore))
     (haystack-run-root-search "rust")
     (let ((root-buf (get-buffer "*haystack:1:rust*")))
       (unwind-protect
           (with-current-buffer root-buf
             (haystack-filter-further "!/async")
             (let ((child-buf (get-buffer "*haystack:2:rust:!/async*")))
               (unwind-protect
                   (with-current-buffer child-buf
                     (should (string-match-p "!filename=async" (buffer-string)))
                     (should (string-match-p "cargo-notes" (buffer-string)))
                     (should-not (string-match-p "async-notes" (buffer-string))))
                 (when child-buf (kill-buffer child-buf)))))
         (kill-buffer root-buf))))))

(ert-deftest haystack-test/filter-further-negated-filename-matches-directory-component ()
  "!/term excludes files where the term appears in a directory component.
Regression: previously only the basename was checked, so sicp-org/README.org
would not be excluded by !/sicp even though 'sicp' is in its path."
  (haystack-test--with-notes-dir
   (let* ((subdir (expand-file-name "sicp-org" haystack-notes-directory))
          (subfile (progn (make-directory subdir t)
                          (expand-file-name "README.org" subdir)))
          (flat (expand-file-name "unrelated.org" haystack-notes-directory)))
     (with-temp-file subfile (insert "some content\n"))
     (with-temp-file flat    (insert "some content\n")))
   (cl-letf (((symbol-function 'pop-to-buffer)    #'ignore)
             ((symbol-function 'switch-to-buffer) #'ignore))
     (haystack-run-root-search "some")
     (let ((root-buf (get-buffer "*haystack:1:some*")))
       (unwind-protect
           (with-current-buffer root-buf
             (haystack-filter-further "!/sicp")
             (let ((child-buf (get-buffer "*haystack:2:some:!/sicp*")))
               (unwind-protect
                   (with-current-buffer child-buf
                     (should     (string-match-p "unrelated"   (buffer-string)))
                     (should-not (string-match-p "sicp-org"    (buffer-string))))
                 (when child-buf (kill-buffer child-buf)))))
         (kill-buffer root-buf))))))

(ert-deftest haystack-test/filter-further-negation-special-chars ()
  "Negation with a term containing regex metacharacters (e.g. C++) does not error.
Regression: the negation path previously passed the raw term to rg instead of
the regexp-quote'd pattern, causing rg to reject `+' as an invalid quantifier."
  (haystack-test--with-notes-dir
   (let ((match-note (expand-file-name "20240101000000-cpp-notes.org"
                                       haystack-notes-directory))
         (other-note (expand-file-name "20240101000001-rust-notes.org"
                                       haystack-notes-directory)))
     (with-temp-file match-note (insert "C++ content here\n"))
     (with-temp-file other-note (insert "rust content here\n")))
   (cl-letf (((symbol-function 'pop-to-buffer)    #'ignore)
             ((symbol-function 'switch-to-buffer) #'ignore))
     ;; Root search on a term that matches both files.
     (haystack-run-root-search "content")
     (let ((root-buf (get-buffer "*haystack:1:content*")))
       (should root-buf)
       (unwind-protect
           (with-current-buffer root-buf
             ;; This must not signal an error even though "C++" contains
             ;; regex metacharacters.
             (should-not
              (condition-case _
                  (progn (haystack-filter-further "!C++") nil)
                (error t)))
             (let ((child-buf (get-buffer "*haystack:2:content:!C++*")))
               (unwind-protect
                   (with-current-buffer child-buf
                     ;; The C++ file should be excluded; rust file retained.
                     (should (string-match-p "rust-notes" (buffer-string)))
                     (should-not (string-match-p "cpp-notes" (buffer-string))))
                 (when child-buf (kill-buffer child-buf)))))
         (kill-buffer root-buf))))))

;;; Exclusivity guardrail

(ert-deftest haystack-test/filter-further-guardrail-blocks-same-group-term ()
  "Signals user-error when filter term is in the root's expansion group."
  (haystack-test--with-groups '(("programming" . ("coding" "scripting")))
    (with-temp-buffer
      (setq haystack--search-descriptor
            (list :root-term "programming"
                  :root-expanded "(programming|coding|scripting)"
                  :root-expansion '("programming" "coding" "scripting")
                  :filters nil :composite-filter 'exclude))
      (insert "/fake/note.org:1:some content\n")
      (should-error (haystack-filter-further "coding") :type 'user-error))))

(ert-deftest haystack-test/filter-further-guardrail-blocks-root-term-itself ()
  "Signals user-error when filter term is the root term (member of its own group)."
  (haystack-test--with-groups '(("programming" . ("coding" "scripting")))
    (with-temp-buffer
      (setq haystack--search-descriptor
            (list :root-term "programming"
                  :root-expanded "(programming|coding|scripting)"
                  :root-expansion '("programming" "coding" "scripting")
                  :filters nil :composite-filter 'exclude))
      (insert "/fake/note.org:1:some content\n")
      (should-error (haystack-filter-further "programming") :type 'user-error))))

(ert-deftest haystack-test/filter-further-guardrail-case-insensitive ()
  "Guardrail comparison is case-insensitive."
  (haystack-test--with-groups '(("programming" . ("coding" "scripting")))
    (with-temp-buffer
      (setq haystack--search-descriptor
            (list :root-term "programming"
                  :root-expanded "(programming|coding|scripting)"
                  :root-expansion '("programming" "coding" "scripting")
                  :filters nil :composite-filter 'exclude))
      (insert "/fake/note.org:1:some content\n")
      (should-error (haystack-filter-further "CODING") :type 'user-error))))

(ert-deftest haystack-test/filter-further-guardrail-literal-bypasses ()
  "=term bypasses the guardrail and allows the filter."
  (haystack-test--with-groups '(("programming" . ("coding" "scripting")))
    (haystack-test--with-notes-dir
      (let ((note (expand-file-name "20240101000000-test.org" haystack-notes-directory)))
        (with-temp-file note (insert "programming coding content\n")))
      (cl-letf (((symbol-function 'pop-to-buffer)    #'ignore)
                ((symbol-function 'switch-to-buffer) #'ignore))
        (haystack-run-root-search "programming")
        (let ((root-buf (get-buffer "*haystack:1:programming*")))
          (should root-buf)
          (unwind-protect
              (with-current-buffer root-buf
                ;; =coding forces literal search — should not error
                (should-not
                 (condition-case _
                     (progn (haystack-filter-further "=coding") nil)
                   (user-error t))))
            (kill-buffer root-buf)
            (when (get-buffer "*haystack:2:programming:=coding*")
              (kill-buffer "*haystack:2:programming:=coding*"))))))))

(ert-deftest haystack-test/filter-further-guardrail-no-root-expansion-allows ()
  "No guardrail fires when root did not expand (no group)."
  (haystack-test--with-groups nil
    (haystack-test--with-notes-dir
      (let ((note (expand-file-name "20240101000000-test.org" haystack-notes-directory)))
        (with-temp-file note (insert "rust async content\n")))
      (cl-letf (((symbol-function 'pop-to-buffer)    #'ignore)
                ((symbol-function 'switch-to-buffer) #'ignore))
        (haystack-run-root-search "rust")
        (let ((root-buf (get-buffer "*haystack:1:rust*")))
          (should root-buf)
          (unwind-protect
              (with-current-buffer root-buf
                (should-not
                 (condition-case _
                     (progn (haystack-filter-further "rust") nil)
                   (user-error t))))
            (kill-buffer root-buf)
            (when (get-buffer "*haystack:2:rust:rust*")
              (kill-buffer "*haystack:2:rust:rust*"))))))))

(ert-deftest haystack-test/filter-further-guardrail-multiword-bypasses ()
  "Multi-word filter bypasses the guardrail regardless of expansion."
  (haystack-test--with-groups '(("programming" . ("coding" "scripting")))
    (haystack-test--with-notes-dir
      (let ((note (expand-file-name "20240101000000-test.org" haystack-notes-directory)))
        (with-temp-file note (insert "programming coding in detail\n")))
      (cl-letf (((symbol-function 'pop-to-buffer)    #'ignore)
                ((symbol-function 'switch-to-buffer) #'ignore))
        (haystack-run-root-search "programming")
        (let ((root-buf (get-buffer "*haystack:1:programming*")))
          (should root-buf)
          (unwind-protect
              (with-current-buffer root-buf
                ;; "coding in detail" is multi-word — should not be blocked
                (should-not
                 (condition-case _
                     (progn (haystack-filter-further "coding in detail") nil)
                   (user-error t))))
            (kill-buffer root-buf)
            (when (get-buffer "*haystack:2:programming:coding in detail*")
              (kill-buffer "*haystack:2:programming:coding in detail*"))))))))

;;;; haystack-run-root-search

(ert-deftest haystack-test/run-root-search-errors-without-directory ()
  "Signals user-error when `haystack-notes-directory' is unset."
  (let ((haystack-notes-directory nil))
    (should-error (haystack-run-root-search "rust") :type 'user-error)))

(ert-deftest haystack-test/run-root-search-errors-on-missing-directory ()
  "Signals user-error when the notes directory does not exist."
  (let ((haystack-notes-directory "/tmp/haystack-nonexistent-xyz/"))
    (should-error (haystack-run-root-search "rust") :type 'user-error)))

(ert-deftest haystack-test/run-root-search-creates-buffer ()
  "Creates a buffer named *haystack:1:TERM* with a header."
  (haystack-test--with-notes-dir
   (cl-letf (((symbol-function 'pop-to-buffer) #'ignore))
     (haystack-run-root-search "nomatchxyz99")
     (let ((buf (get-buffer "*haystack:1:nomatchxyz99*")))
       (should buf)
       (unwind-protect
           (with-current-buffer buf
             (should (string-match-p "root=nomatchxyz99"
                                     (buffer-string))))
         (kill-buffer buf))))))

(ert-deftest haystack-test/run-root-search-descriptor-stored ()
  "Buffer-local descriptor reflects the search term and composite-filter."
  (haystack-test--with-notes-dir
   (cl-letf (((symbol-function 'pop-to-buffer) #'ignore))
     (haystack-run-root-search "nomatchxyz99" 'only)
     (let ((buf (get-buffer "*haystack:1:nomatchxyz99*")))
       (should buf)
       (unwind-protect
           (with-current-buffer buf
             (should (equal (plist-get haystack--search-descriptor :root-term)
                            "nomatchxyz99"))
             (should (eq (plist-get haystack--search-descriptor :composite-filter)
                         'only))
             (should (null haystack--parent-buffer)))
         (kill-buffer buf))))))

(ert-deftest haystack-test/run-root-search-header-is-read-only ()
  "The header line carries the read-only text property."
  (haystack-test--with-notes-dir
   (cl-letf (((symbol-function 'pop-to-buffer) #'ignore))
     (haystack-run-root-search "nomatchxyz99")
     (let ((buf (get-buffer "*haystack:1:nomatchxyz99*")))
       (should buf)
       (unwind-protect
           (with-current-buffer buf
             (should (get-text-property (point-min) 'read-only)))
         (kill-buffer buf))))))

(ert-deftest haystack-test/run-root-search-filename-prefix ()
  "A /term root search shows filename= in header and matches by basename."
  (haystack-test--with-notes-dir
   (let ((match (expand-file-name "20240101000000-cargo-build.org"
                                  haystack-notes-directory))
         (no-match (expand-file-name "20240101000001-async-notes.org"
                                     haystack-notes-directory)))
     (with-temp-file match    (insert "some content here\n"))
     (with-temp-file no-match (insert "other content here\n")))
   (cl-letf (((symbol-function 'pop-to-buffer) #'ignore))
     (haystack-run-root-search "/cargo")
     (let ((buf (get-buffer "*haystack:1:/cargo*")))
       (should buf)
       (unwind-protect
           (with-current-buffer buf
             (should (string-match-p "filename=cargo" (buffer-string)))
             (should (string-match-p "cargo-build" (buffer-string)))
             (should-not (string-match-p "async-notes" (buffer-string))))
         (kill-buffer buf))))))

;;;; haystack-search-region

(ert-deftest haystack-test/search-region-errors-without-region ()
  "Signals user-error when there is no active region."
  (with-temp-buffer
    (should-error (haystack-search-region) :type 'user-error)))

;;;; haystack--extract-file-loci

(ert-deftest haystack-test/extract-file-loci-basic ()
  "Returns (path . line) for each unique file."
  (let ((default-directory "/notes/"))
    (let ((result (haystack--extract-file-loci
                   (mapconcat #'identity
                              '("foo.org:3:match"
                                "bar.org:7:match")
                              "\n"))))
      (should (equal result '(("/notes/foo.org" . 3)
                              ("/notes/bar.org" . 7)))))))

(ert-deftest haystack-test/extract-file-loci-deduplicates-keeps-first ()
  "Only the first line number per file is kept."
  (let ((default-directory "/notes/"))
    (let ((result (haystack--extract-file-loci
                   (mapconcat #'identity
                              '("foo.org:3:first match"
                                "foo.org:9:second match"
                                "foo.org:14:third match")
                              "\n"))))
      (should (equal result '(("/notes/foo.org" . 3)))))))

(ert-deftest haystack-test/extract-file-loci-skips-headers ()
  "Header lines are ignored."
  (let ((default-directory "/notes/"))
    (let ((result (haystack--extract-file-loci
                   ";;;; header line\nfoo.org:1:match")))
      (should (equal result '(("/notes/foo.org" . 1)))))))

(ert-deftest haystack-test/extract-file-loci-empty ()
  "Empty input returns nil."
  (should (null (haystack--extract-file-loci ""))))

;;;; haystack--moc-format-for-extension

(ert-deftest haystack-test/moc-format-for-extension-org ()
  (should (eq (haystack--moc-format-for-extension "org") 'org)))

(ert-deftest haystack-test/moc-format-for-extension-md ()
  (should (eq (haystack--moc-format-for-extension "md") 'markdown)))

(ert-deftest haystack-test/moc-format-for-extension-markdown ()
  (should (eq (haystack--moc-format-for-extension "markdown") 'markdown)))

(ert-deftest haystack-test/moc-format-for-extension-code-fallback ()
  "Non-markup extensions fall back to code format."
  (should (eq (haystack--moc-format-for-extension "el")  'code))
  (should (eq (haystack--moc-format-for-extension "rs")  'code))
  (should (eq (haystack--moc-format-for-extension "txt") 'code)))

;;;; haystack--comment-prefix

(ert-deftest haystack-test/comment-prefix-known-extensions ()
  (should (equal (haystack--comment-prefix "el")  ";;"))
  (should (equal (haystack--comment-prefix "js")  "//"))
  (should (equal (haystack--comment-prefix "py")  "#"))
  (should (equal (haystack--comment-prefix "lua") "--")))

(ert-deftest haystack-test/comment-prefix-unknown-falls-back ()
  "Unknown extensions return \"//\"."
  (should (equal (haystack--comment-prefix "xyz") "//")))

;;;; haystack--format-moc-code-comment

(ert-deftest haystack-test/format-moc-code-comment-uses-prefix ()
  "Comment line uses the correct prefix and omits the line number."
  (should (equal (haystack--format-moc-code-comment "/notes/my-rust-notes.rs" "rs")
                 "// my rust notes — /notes/my-rust-notes.rs"))
  (should (equal (haystack--format-moc-code-comment "/notes/my-note.el" "el")
                 ";; my note — /notes/my-note.el")))

;;;; haystack--format-moc-link

(ert-deftest haystack-test/format-moc-link-org ()
  "Org format produces [[file:PATH::LINE][TITLE]]."
  (should (equal (haystack--format-moc-link
                  "/notes/20240101000000-my-rust-notes.org" 42 'org "org")
                 "[[file:/notes/20240101000000-my-rust-notes.org::42][my rust notes]]")))

(ert-deftest haystack-test/format-moc-link-markdown ()
  "Markdown format produces [TITLE](PATH#LLINE)."
  (should (equal (haystack--format-moc-link "/notes/my-rust-notes.md" 7 'markdown "md")
                 "[my rust notes](/notes/my-rust-notes.md#L7)")))

(ert-deftest haystack-test/format-moc-link-code-comment ()
  "Code format with comment style produces a commented line."
  (let ((haystack-moc-code-style 'comment))
    (should (equal (haystack--format-moc-link "/notes/my-note.el" 5 'code "el")
                   ";; my note — /notes/my-note.el"))))

(ert-deftest haystack-test/format-moc-link-code-always-comment ()
  "haystack--format-moc-link always uses comment style for code files.
Data style is handled at the block level in haystack-yank-moc."
  (let ((haystack-moc-code-style 'data))
    (should (equal (haystack--format-moc-link "/notes/my-note.el" 5 'code "el")
                   ";; my note — /notes/my-note.el"))))

;;;; haystack-copy-moc

(ert-deftest haystack-test/copy-moc-errors-outside-haystack-buffer ()
  (with-temp-buffer
    (should-error (haystack-copy-moc) :type 'user-error)))

(ert-deftest haystack-test/copy-moc-errors-on-empty-results ()
  "Signals user-error when the buffer has no match lines."
  (let ((buf (haystack-test--make-results-buf
              " *hs-copy-empty*" nil '(:root-term "rust"))))
    (unwind-protect
        (with-current-buffer buf
          (should-error (haystack-copy-moc) :type 'user-error))
      (kill-buffer buf))))

(ert-deftest haystack-test/copy-moc-stores-loci ()
  "Stores (path . line) loci in `haystack--last-moc'."
  (let ((buf (haystack-test--make-results-buf
              " *hs-copy-moc*" nil '(:root-term "rust")))
        (haystack--last-moc nil))
    (unwind-protect
        (with-current-buffer buf
          (setq default-directory "/notes/")
          (insert "foo.org:3:content\nbar.org:7:content\n")
          (haystack-copy-moc)
          (should (equal haystack--last-moc
                         '(("/notes/foo.org" . 3)
                           ("/notes/bar.org" . 7)))))
      (kill-buffer buf))))

;;; haystack--descriptor-chain-string

(ert-deftest haystack-test/descriptor-chain-string-root-only ()
  "Root-only descriptor produces a single root= segment."
  (should (equal (haystack--descriptor-chain-string
                  '(:root-term "rust" :root-expansion nil
                    :root-filename nil :filters nil))
                 "root=rust")))

(ert-deftest haystack-test/descriptor-chain-string-with-filters ()
  "Descriptor with filters includes all filter segments."
  (should (equal (haystack--descriptor-chain-string
                  '(:root-term "rust" :root-expansion nil :root-filename nil
                    :filters ((:term "async" :negated nil :filename nil :expansion nil)
                               (:term "cargo" :negated t :filename nil :expansion nil))))
                 "root=rust > filter=async > exclude=cargo")))

(ert-deftest haystack-test/descriptor-chain-string-with-expansion ()
  "Root expansion is shown as alternation."
  (should (equal (haystack--descriptor-chain-string
                  '(:root-term "programming"
                    :root-expansion ("programming" "coding" "scripting")
                    :root-filename nil :filters nil))
                 "root=(programming|coding|scripting)")))

;;; haystack-moc-quote-string

(ert-deftest haystack-test/moc-quote-string-simple ()
  (should (equal (haystack-moc-quote-string "hello") "\"hello\"")))

(ert-deftest haystack-test/moc-quote-string-escapes-internal-quotes ()
  (should (equal (haystack-moc-quote-string "say \"hi\"") "\"say \\\"hi\\\"\"")))

;;; haystack--format-moc-data-block

(ert-deftest haystack-test/moc-data-block-js ()
  "JS block has chain comment, const declaration, and one entry per locus."
  (let ((result (haystack--format-moc-data-block
                 '(("/notes/20240101000000-rust.org" . 3)
                   ("/notes/20240101000001-async.org" . 7))
                 "root=rust"
                 "js")))
    (should (string-match-p "^// haystack: root=rust" result))
    (should (string-match-p "^const haystack = \\[" result))
    (should (string-match-p "title:" result))
    (should (string-match-p "path:" result))
    (should (string-match-p "line: 3" result))
    (should (string-match-p "line: 7" result))
    (should (string-match-p "];" result))))

(ert-deftest haystack-test/moc-data-block-ts-same-as-js ()
  "TypeScript produces the same output shape as JavaScript."
  (let ((js-out (haystack--format-moc-data-block
                 '(("/notes/note.org" . 1)) "root=rust" "js"))
        (ts-out (haystack--format-moc-data-block
                 '(("/notes/note.org" . 1)) "root=rust" "ts")))
    (should (equal js-out ts-out))))

(ert-deftest haystack-test/moc-data-block-python ()
  "Python block has # comment, list assignment, and dict entries."
  (let ((result (haystack--format-moc-data-block
                 '(("/notes/20240101000000-rust.org" . 3))
                 "root=rust"
                 "py")))
    (should (string-match-p "^# haystack: root=rust" result))
    (should (string-match-p "^haystack = \\[" result))
    (should (string-match-p "\"title\":" result))
    (should (string-match-p "\"path\":" result))
    (should (string-match-p "\"line\": 3" result))
    (should (string-match-p "]" result))))

(ert-deftest haystack-test/moc-data-block-elisp-single-entry ()
  "Elisp block with one entry uses compact single-line form."
  (let ((result (haystack--format-moc-data-block
                 '(("/notes/20240101000000-rust.el" . 3))
                 "root=rust"
                 "el")))
    (should (string-match-p "^;; haystack: root=rust" result))
    (should (string-match-p "(defvar haystack" result))
    (should (string-match-p ":title" result))
    (should (string-match-p ":path" result))
    (should (string-match-p ":line 3" result))))

(ert-deftest haystack-test/moc-data-block-elisp-multi-entry ()
  "Elisp block with multiple entries indents continuation entries."
  (let ((result (haystack--format-moc-data-block
                 '(("/notes/20240101000000-a.el" . 1)
                   ("/notes/20240101000001-b.el" . 5))
                 "root=rust"
                 "el")))
    (should (string-match-p "(defvar haystack" result))
    ;; Second entry indented with 4 spaces
    (should (string-match-p "\n    (" result))))

(ert-deftest haystack-test/moc-data-block-lua ()
  "Lua block has -- comment, local table, and one entry per locus."
  (let ((result (haystack--format-moc-data-block
                 '(("/notes/20240101000000-rust.lua" . 3))
                 "root=rust"
                 "lua")))
    (should (string-match-p "^-- haystack: root=rust" result))
    (should (string-match-p "^local haystack = {" result))
    (should (string-match-p "title =" result))
    (should (string-match-p "path =" result))
    (should (string-match-p "line = 3" result))
    (should (string-match-p "}" result))))

(ert-deftest haystack-test/moc-data-block-unknown-ext-falls-back ()
  "Unknown extension falls back to comment style (one line per file)."
  (let ((result (haystack--format-moc-data-block
                 '(("/notes/20240101000000-note.xyz" . 3))
                 "root=rust"
                 "xyz")))
    ;; Falls back to comment — no data structure keywords
    (should-not (string-match-p "const\\|local\\|defvar" result))
    (should (string-match-p "/notes/20240101000000-note.xyz" result))))

(ert-deftest haystack-test/moc-data-block-custom-formatter-is-called ()
  "A user-registered formatter in `haystack-moc-data-formatters' is invoked."
  (let ((haystack-moc-data-formatters
         (cons '("rb" . (lambda (loci chain)
                          (concat "# custom: " chain "\n"
                                  "LINKS = []\n")))
               haystack-moc-data-formatters)))
    (let ((result (haystack--format-moc-data-block
                   '(("/notes/note.rb" . 1))
                   "root=ruby"
                   "rb")))
      (should (string-match-p "^# custom: root=ruby" result))
      (should (string-match-p "LINKS" result)))))

;;; copy-moc stores chain

(ert-deftest haystack-test/copy-moc-stores-chain ()
  "haystack-copy-moc stores the search chain alongside loci."
  (let ((buf (haystack-test--make-results-buf
              " *hs-copy-chain*" nil
              '(:root-term "rust" :root-expansion nil :root-filename nil
                :filters ((:term "async" :negated nil :filename nil :expansion nil)))))
        (haystack--last-moc nil)
        (haystack--last-moc-chain nil))
    (unwind-protect
        (with-current-buffer buf
          (setq default-directory "/notes/")
          (insert "foo.el:3:content\n")
          (haystack-copy-moc)
          (should (equal haystack--last-moc-chain "root=rust > filter=async")))
      (kill-buffer buf))))

;;; yank-moc uses data block for code files when style is data

(ert-deftest haystack-test/yank-moc-data-style-js ()
  "Data style produces a JS const block, not a comment line."
  (let ((haystack--last-moc '(("/notes/20240101000000-rust.org" . 3)))
        (haystack--last-moc-chain "root=rust")
        (haystack-moc-code-style 'data))
    (with-temp-buffer
      (let ((buffer-file-name "/target/index.js"))
        (haystack-yank-moc)
        (should (string-match-p "^// haystack:" (buffer-string)))
        (should (string-match-p "const haystack" (buffer-string)))))))

(ert-deftest haystack-test/yank-moc-data-style-org-unaffected ()
  "Data style has no effect on org targets — org link format is unchanged."
  (let ((haystack--last-moc '(("/notes/20240101000000-rust.org" . 3)))
        (haystack--last-moc-chain "root=rust")
        (haystack-moc-code-style 'data))
    (with-temp-buffer
      (let ((buffer-file-name "/target/index.org"))
        (haystack-yank-moc)
        (should (string-match-p "\\[\\[file:" (buffer-string)))))))

;;;; haystack-yank-moc

(ert-deftest haystack-test/yank-moc-errors-when-nothing-copied ()
  "Signals user-error when `haystack--last-moc' is nil."
  (let ((haystack--last-moc nil))
    (with-temp-buffer
      (should-error (haystack-yank-moc) :type 'user-error))))

(ert-deftest haystack-test/yank-moc-inserts-at-point ()
  "Inserts formatted links at point in the target buffer."
  (let ((haystack--last-moc '(("/notes/foo.org" . 3)))
        (haystack-default-extension "org"))
    (with-temp-buffer
      (haystack-yank-moc)
      (should (string-match-p "file:/notes/foo\\.org::3" (buffer-string))))))

(ert-deftest haystack-test/yank-moc-pushes-to-kill-ring ()
  "Also pushes the formatted text to the kill ring."
  (let ((haystack--last-moc '(("/notes/foo.org" . 3)))
        (haystack-default-extension "org"))
    (with-temp-buffer
      (haystack-yank-moc)
      (should (string-match-p "file:/notes/foo\\.org::3" (car kill-ring))))))

(ert-deftest haystack-test/yank-moc-format-follows-file-extension ()
  "Format is determined by the target buffer's file extension."
  (let ((haystack--last-moc '(("/notes/20240101000000-rust.org" . 1))))
    ;; org target → org links
    (with-temp-buffer
      (let ((buffer-file-name "/target/notes.org"))
        (haystack-yank-moc)
        (should (string-match-p "\\[\\[file:" (buffer-string)))))
    ;; md target → markdown links
    (with-temp-buffer
      (let ((buffer-file-name "/target/notes.md"))
        (haystack-yank-moc)
        (should (string-match-p "\\[rust\\](" (buffer-string)))))
    ;; code target → comment fallback
    (with-temp-buffer
      (let ((buffer-file-name "/target/notes.el")
            (haystack-moc-code-style 'comment))
        (haystack-yank-moc)
        (should (string-match-p "^;;" (buffer-string)))))))

;;;; Buffer tree navigation

;;; Test helpers

(defmacro haystack-test--make-results-buf (name parent descriptor)
  "Create a temporary haystack results buffer named NAME.
PARENT is the parent buffer (or nil) and DESCRIPTOR is the search descriptor.
Returns the buffer; caller is responsible for killing it."
  `(let ((buf (get-buffer-create ,name)))
     (with-current-buffer buf
       (setq haystack--search-descriptor ,descriptor
             haystack--parent-buffer     ,parent))
     buf))

;;; haystack--all-haystack-buffers

(ert-deftest haystack-test/all-haystack-buffers-finds-results-buffers ()
  "Returns live haystack buffers and ignores ordinary buffers."
  (let* ((hbuf (haystack-test--make-results-buf
                " *hs-test-all*" nil '(:root-term "rust")))
         (plain (get-buffer-create " *hs-test-plain*")))
    (unwind-protect
        (should (memq hbuf (haystack--all-haystack-buffers)))
      (kill-buffer hbuf)
      (kill-buffer plain))))

(ert-deftest haystack-test/all-haystack-buffers-excludes-ordinary ()
  "Ordinary buffers without a descriptor are not included."
  (let ((plain (get-buffer-create " *hs-test-plain2*")))
    (unwind-protect
        (should-not (memq plain (haystack--all-haystack-buffers)))
      (kill-buffer plain))))

;;; haystack--children-of

(ert-deftest haystack-test/children-of-finds-direct-children ()
  "Returns buffers whose parent is exactly BUF."
  (let* ((root  (haystack-test--make-results-buf " *hs-root*"  nil       '(:root-term "rust")))
         (child (haystack-test--make-results-buf " *hs-child*" root      '(:root-term "rust")))
         (other (haystack-test--make-results-buf " *hs-other*" nil       '(:root-term "async"))))
    (unwind-protect
        (progn
          (should (memq child (haystack--children-of root)))
          (should-not (memq other (haystack--children-of root)))
          (should-not (memq root (haystack--children-of root))))
      (kill-buffer root)
      (kill-buffer child)
      (kill-buffer other))))

;;; haystack-go-up

(ert-deftest haystack-test/go-up-errors-outside-haystack-buffer ()
  (with-temp-buffer
    (should-error (haystack-go-up) :type 'user-error)))

(ert-deftest haystack-test/go-up-messages-on-root ()
  "Messages without switching when there is no parent."
  (let ((buf (haystack-test--make-results-buf " *hs-go-up-root*" nil '(:root-term "rust")))
        (msgs nil))
    (unwind-protect
        (with-current-buffer buf
          (cl-letf (((symbol-function 'message) (lambda (fmt &rest args)
                                                  (push (apply #'format fmt args) msgs))))
            (haystack-go-up))
          (should (cl-some (lambda (m) (string-match-p "root buffer" m)) msgs)))
      (kill-buffer buf))))

(ert-deftest haystack-test/go-up-messages-on-dead-parent ()
  "Messages without switching when the parent buffer is dead."
  (let* ((parent (haystack-test--make-results-buf " *hs-dead-parent*" nil '(:root-term "r")))
         (child  (haystack-test--make-results-buf " *hs-child-dp*" parent '(:root-term "r")))
         (msgs nil))
    (kill-buffer parent)
    (unwind-protect
        (with-current-buffer child
          (cl-letf (((symbol-function 'message) (lambda (fmt &rest args)
                                                  (push (apply #'format fmt args) msgs))))
            (haystack-go-up))
          (should (cl-some (lambda (m) (string-match-p "no longer live" m)) msgs)))
      (kill-buffer child))))

(ert-deftest haystack-test/go-up-switches-to-live-parent ()
  "Switches to the parent buffer when it is live."
  (let* ((parent (haystack-test--make-results-buf " *hs-live-parent*" nil '(:root-term "r")))
         (child  (haystack-test--make-results-buf " *hs-child-lp*" parent '(:root-term "r")))
         (switched-to nil))
    (unwind-protect
        (with-current-buffer child
          (cl-letf (((symbol-function 'switch-to-buffer)
                     (lambda (buf) (setq switched-to buf))))
            (haystack-go-up))
          (should (eq switched-to parent)))
      (kill-buffer parent)
      (kill-buffer child))))

;;; haystack-go-down

(ert-deftest haystack-test/go-down-errors-outside-haystack-buffer ()
  (with-temp-buffer
    (should-error (haystack-go-down) :type 'user-error)))

(ert-deftest haystack-test/go-down-errors-with-no-children ()
  "Signals user-error when the buffer has no children."
  (let ((buf (haystack-test--make-results-buf " *hs-down-none*" nil '(:root-term "rust"))))
    (unwind-protect
        (with-current-buffer buf
          (should-error (haystack-go-down) :type 'user-error))
      (kill-buffer buf))))

(ert-deftest haystack-test/go-down-switches-directly-with-one-child ()
  "With one child, switches to it without showing a picker."
  (let* ((parent (haystack-test--make-results-buf " *hs-down-p*" nil '(:root-term "rust")))
         (child  (haystack-test--make-results-buf " *hs-down-c*" parent '(:root-term "rust")))
         (switched-to nil))
    (unwind-protect
        (with-current-buffer parent
          (cl-letf (((symbol-function 'switch-to-buffer)
                     (lambda (buf) (setq switched-to buf))))
            (haystack-go-down))
          (should (eq switched-to child)))
      (kill-buffer parent)
      (kill-buffer child))))

(ert-deftest haystack-test/go-down-opens-picker-with-multiple-children ()
  "With multiple children, opens *haystack-children* picker."
  (let* ((parent (haystack-test--make-results-buf
                  " *hs-down-mp*" nil
                  '(:root-term "rust" :root-filename nil :root-literal nil :root-regex nil)))
         (c1 (haystack-test--make-results-buf
              " *hs-down-mc1*" parent
              '(:root-term "rust" :filters ((:term "async" :negated nil
                                             :filename nil :literal nil :regex nil)))))
         (c2 (haystack-test--make-results-buf
              " *hs-down-mc2*" parent
              '(:root-term "rust" :filters ((:term "tokio" :negated nil
                                             :filename nil :literal nil :regex nil))))))
    (unwind-protect
        (with-current-buffer parent
          (cl-letf (((symbol-function 'select-window) #'ignore)
                    ((symbol-function 'display-buffer) #'ignore))
            (haystack-go-down))
          (let ((picker (get-buffer "*haystack-children*")))
            (should (buffer-live-p picker))
            (with-current-buffer picker
              (should (string-match-p "async" (buffer-string)))
              (should (string-match-p "tokio" (buffer-string))))
            (kill-buffer picker)))
      (kill-buffer parent)
      (kill-buffer c1)
      (kill-buffer c2))))

(ert-deftest haystack-test/go-down-picker-text-properties ()
  "Each entry in the picker has a haystack-children-buffer property."
  (let* ((parent (haystack-test--make-results-buf
                  " *hs-down-tp*" nil
                  '(:root-term "rust" :root-filename nil :root-literal nil :root-regex nil)))
         (c1 (haystack-test--make-results-buf
              " *hs-down-tp1*" parent
              '(:root-term "rust" :filters ((:term "async" :negated nil
                                             :filename nil :literal nil :regex nil)))))
         (c2 (haystack-test--make-results-buf
              " *hs-down-tp2*" parent
              '(:root-term "rust" :filters ((:term "tokio" :negated nil
                                             :filename nil :literal nil :regex nil))))))
    (unwind-protect
        (with-current-buffer parent
          (cl-letf (((symbol-function 'select-window) #'ignore)
                    ((symbol-function 'display-buffer) #'ignore))
            (haystack-go-down))
          (let ((picker (get-buffer "*haystack-children*")))
            (unwind-protect
                (with-current-buffer picker
                  (goto-char (point-min))
                  (forward-line 1)
                  (should (memq (get-text-property (point) 'haystack-children-buffer)
                                (list c1 c2))))
              (kill-buffer picker))))
      (kill-buffer parent)
      (kill-buffer c1)
      (kill-buffer c2))))

;;; haystack-kill-node

(ert-deftest haystack-test/kill-node-errors-outside-haystack-buffer ()
  (with-temp-buffer
    (should-error (haystack-kill-node) :type 'user-error)))

(ert-deftest haystack-test/kill-node-kills-current-buffer ()
  "Kills the current haystack buffer and nothing else."
  (let* ((buf   (haystack-test--make-results-buf " *hs-kill-node*" nil '(:root-term "r")))
         (child (haystack-test--make-results-buf " *hs-kill-node-child*" buf '(:root-term "r"))))
    (unwind-protect
        (progn
          (with-current-buffer buf (haystack-kill-node))
          (should-not (buffer-live-p buf))
          (should (buffer-live-p child)))
      (when (buffer-live-p buf)   (kill-buffer buf))
      (when (buffer-live-p child) (kill-buffer child)))))

;;; haystack--kill-subtree / haystack-kill-subtree

(ert-deftest haystack-test/kill-subtree-kills-self-and-descendants ()
  "Kills the buffer and all descendants, leaving unrelated buffers."
  (let* ((root    (haystack-test--make-results-buf " *hs-ks-root*"    nil     '(:root-term "r")))
         (child   (haystack-test--make-results-buf " *hs-ks-child*"   root    '(:root-term "r")))
         (grandch (haystack-test--make-results-buf " *hs-ks-grand*"   child   '(:root-term "r")))
         (sibling (haystack-test--make-results-buf " *hs-ks-sibling*" nil     '(:root-term "r"))))
    (unwind-protect
        (progn
          (with-current-buffer child (haystack-kill-subtree))
          (should (buffer-live-p root))
          (should-not (buffer-live-p child))
          (should-not (buffer-live-p grandch))
          (should (buffer-live-p sibling)))
      (when (buffer-live-p root)    (kill-buffer root))
      (when (buffer-live-p child)   (kill-buffer child))
      (when (buffer-live-p grandch) (kill-buffer grandch))
      (when (buffer-live-p sibling) (kill-buffer sibling)))))

;;; haystack-kill-whole-tree

(ert-deftest haystack-test/kill-all-from-leaf-kills-entire-tree ()
  "Walking from a leaf kills the whole tree."
  (let* ((root    (haystack-test--make-results-buf " *hs-ka-root*"  nil   '(:root-term "r")))
         (child   (haystack-test--make-results-buf " *hs-ka-child*" root  '(:root-term "r")))
         (grandch (haystack-test--make-results-buf " *hs-ka-grand*" child '(:root-term "r")))
         (other   (haystack-test--make-results-buf " *hs-ka-other*" nil   '(:root-term "r"))))
    (unwind-protect
        (progn
          (with-current-buffer grandch (haystack-kill-whole-tree))
          (should-not (buffer-live-p root))
          (should-not (buffer-live-p child))
          (should-not (buffer-live-p grandch))
          (should (buffer-live-p other)))
      (when (buffer-live-p root)    (kill-buffer root))
      (when (buffer-live-p child)   (kill-buffer child))
      (when (buffer-live-p grandch) (kill-buffer grandch))
      (when (buffer-live-p other)   (kill-buffer other)))))

(ert-deftest haystack-test/kill-all-from-root-kills-entire-tree ()
  "Calling kill-all from the root also kills all descendants."
  (let* ((root  (haystack-test--make-results-buf " *hs-ka2-root*"  nil  '(:root-term "r")))
         (child (haystack-test--make-results-buf " *hs-ka2-child*" root '(:root-term "r"))))
    (unwind-protect
        (progn
          (with-current-buffer root (haystack-kill-whole-tree))
          (should-not (buffer-live-p root))
          (should-not (buffer-live-p child)))
      (when (buffer-live-p root)  (kill-buffer root))
      (when (buffer-live-p child) (kill-buffer child)))))

;;; haystack-kill-orphans

(ert-deftest haystack-test/kill-orphans-kills-dead-parent-childless-buffers ()
  "Kills buffers whose parent is dead and have no children."
  (let* ((dead-parent (haystack-test--make-results-buf " *hs-ko-dead*"   nil          '(:root-term "r")))
         (orphan      (haystack-test--make-results-buf " *hs-ko-orphan*" dead-parent  '(:root-term "r")))
         (root        (haystack-test--make-results-buf " *hs-ko-root*"   nil          '(:root-term "r"))))
    (kill-buffer dead-parent)
    (unwind-protect
        (progn
          (haystack-kill-orphans)
          (should-not (buffer-live-p orphan))
          (should (buffer-live-p root)))
      (when (buffer-live-p orphan) (kill-buffer orphan))
      (when (buffer-live-p root)   (kill-buffer root)))))

(ert-deftest haystack-test/kill-orphans-spares-dead-parent-with-children ()
  "A buffer with a dead parent but living children is left alone."
  (let* ((dead-parent (haystack-test--make-results-buf " *hs-ko-dead2*"   nil         '(:root-term "r")))
         (mid         (haystack-test--make-results-buf " *hs-ko-mid*"     dead-parent '(:root-term "r")))
         (grandch     (haystack-test--make-results-buf " *hs-ko-grand2*"  mid         '(:root-term "r"))))
    (kill-buffer dead-parent)
    (unwind-protect
        (progn
          (haystack-kill-orphans)
          (should (buffer-live-p mid))
          (should (buffer-live-p grandch)))
      (when (buffer-live-p mid)     (kill-buffer mid))
      (when (buffer-live-p grandch) (kill-buffer grandch)))))

(ert-deftest haystack-test/kill-orphans-messages-when-none ()
  "Messages when there are no orphans."
  (let ((msgs nil))
    (cl-letf (((symbol-function 'message) (lambda (fmt &rest args)
                                            (push (apply #'format fmt args) msgs))))
      (haystack-kill-orphans))
    (should (cl-some (lambda (m) (string-match-p "no orphans" m)) msgs))))

;;;; Keymaps

(ert-deftest haystack-test/results-mode-map-bindings ()
  "Every expected key is bound to the right command in `haystack-results-mode-map'."
  (dolist (binding '(("n"   . haystack-next-match)
                     ("p"   . haystack-previous-match)
                     ("f"   . haystack-filter-further)
                     ("u"   . haystack-go-up)
                     ("d"   . haystack-go-down)
                     ("k"   . haystack-kill-node)
                     ("K"   . haystack-kill-subtree)
                     ("M-k" . haystack-kill-whole-tree)
                     ("c"   . haystack-copy-moc)
                     ("t"   . haystack-show-tree)
                     ("?"   . haystack-help)))
    (should (eq (lookup-key haystack-results-mode-map (kbd (car binding)))
                (cdr binding)))))

;;;; Frecency engine

(defmacro haystack-test--with-frecency (initial-data &rest body)
  "Run BODY with `haystack--frecency-data' bound to INITIAL-DATA.
Saves and restores the global and the dirty flag."
  (declare (indent 1))
  `(let ((saved-data  haystack--frecency-data)
         (saved-dirty haystack--frecency-dirty))
     (unwind-protect
         (progn
           (setq haystack--frecency-data  ,initial-data
                 haystack--frecency-dirty nil)
           ,@body)
       (setq haystack--frecency-data  saved-data
             haystack--frecency-dirty saved-dirty))))

;;; haystack--frecency-chain-key

(ert-deftest haystack-test/frecency-chain-key-root-only ()
  "Root-only descriptor produces a single-element list."
  (should (equal (haystack--frecency-chain-key
                  '(:root-term "rust" :root-filename nil :root-literal nil
                    :root-regex nil :filters nil))
                 '("rust"))))

(ert-deftest haystack-test/frecency-chain-key-with-filters ()
  "Filters are appended with their prefix characters."
  (should (equal (haystack--frecency-chain-key
                  '(:root-term "rust" :root-filename nil :root-literal nil
                    :root-regex nil
                    :filters ((:term "async" :negated nil :filename nil
                                :literal nil :regex nil)
                               (:term "cargo" :negated t :filename nil
                                :literal nil :regex nil))))
                 '("rust" "async" "!cargo"))))

(ert-deftest haystack-test/frecency-chain-key-filename-prefix ()
  "Filename filters get the / prefix."
  (should (equal (haystack--frecency-chain-key
                  '(:root-term "notes" :root-filename nil :root-literal nil
                    :root-regex nil
                    :filters ((:term "cargo" :negated nil :filename t
                                :literal nil :regex nil))))
                 '("notes" "/cargo"))))

(ert-deftest haystack-test/frecency-chain-key-root-modifiers ()
  "Root modifier flags are encoded as prefix characters."
  (should (equal (car (haystack--frecency-chain-key
                       '(:root-term "cargo" :root-filename t :root-literal nil
                         :root-regex nil :filters nil)))
                 "/cargo")))

;;; haystack--frecency-record

(ert-deftest haystack-test/frecency-record-creates-entry ()
  "Recording a new descriptor creates an entry with count 1."
  (haystack-test--with-frecency nil
    (haystack--frecency-record
     '(:root-term "rust" :root-filename nil :root-literal nil
       :root-regex nil :filters nil))
    (let ((entry (assoc '("rust") haystack--frecency-data)))
      (should entry)
      (should (= 1 (plist-get (cdr entry) :count))))))

(ert-deftest haystack-test/frecency-record-increments-count ()
  "Recording the same descriptor a second time increments the count."
  (haystack-test--with-frecency nil
    (let ((desc '(:root-term "rust" :root-filename nil :root-literal nil
                  :root-regex nil :filters nil)))
      (haystack--frecency-record desc)
      (haystack--frecency-record desc)
      (let ((entry (assoc '("rust") haystack--frecency-data)))
        (should (= 2 (plist-get (cdr entry) :count)))))))

(ert-deftest haystack-test/frecency-record-sets-dirty ()
  "Recording sets `haystack--frecency-dirty'."
  (haystack-test--with-frecency nil
    (haystack--frecency-record
     '(:root-term "rust" :root-filename nil :root-literal nil
       :root-regex nil :filters nil))
    (should haystack--frecency-dirty)))

(ert-deftest haystack-test/frecency-record-distinct-chains ()
  "Different chains are stored as separate entries."
  (haystack-test--with-frecency nil
    (haystack--frecency-record
     '(:root-term "rust" :root-filename nil :root-literal nil
       :root-regex nil :filters nil))
    (haystack--frecency-record
     '(:root-term "python" :root-filename nil :root-literal nil
       :root-regex nil :filters nil))
    (should (= 2 (length haystack--frecency-data)))))

(ert-deftest haystack-test/frecency-record-nil-interval-flushes ()
  "When `haystack-frecency-save-interval' is nil, recording flushes immediately."
  (haystack-test--with-notes-dir
    (haystack-test--with-frecency nil
      (let ((haystack-frecency-save-interval nil))
        (haystack--frecency-record
         '(:root-term "rust" :root-filename nil :root-literal nil
           :root-regex nil :filters nil))
        (should (not haystack--frecency-dirty))
        (should (file-exists-p (haystack--frecency-file)))))))

;;; haystack--frecent-leaf-p / haystack--frecent-leaves

(ert-deftest haystack-test/frecent-leaf-p-standalone-is-leaf ()
  "An entry with no deeper chain is always a leaf."
  (let* ((now (float-time))
         (entries (list (cons '("rust") (list :count 5 :last-access now)))))
    (should (haystack--frecent-leaf-p (car entries) entries))))

(ert-deftest haystack-test/frecent-leaf-p-dominated-is-not-leaf ()
  "An entry dominated by a deeper higher-scored chain is not a leaf."
  (let* ((now (float-time))
         (root  (cons '("rust")         (list :count 2 :last-access now)))
         (child (cons '("rust" "async") (list :count 5 :last-access now)))
         (entries (list root child)))
    (should-not (haystack--frecent-leaf-p root entries))
    (should     (haystack--frecent-leaf-p child entries))))

(ert-deftest haystack-test/frecent-leaf-p-higher-scored-root-is-leaf ()
  "A root with higher score than its child is still a leaf."
  (let* ((now (float-time))
         (root  (cons '("rust")         (list :count 5 :last-access now)))
         (child (cons '("rust" "async") (list :count 2 :last-access now)))
         (entries (list root child)))
    (should (haystack--frecent-leaf-p root  entries))
    (should (haystack--frecent-leaf-p child entries))))

(ert-deftest haystack-test/frecent-leaves-filters-correctly ()
  "`haystack--frecent-leaves' keeps only leaf entries."
  (let* ((now (float-time))
         (root  (cons '("rust")         (list :count 2 :last-access now)))
         (child (cons '("rust" "async") (list :count 5 :last-access now)))
         (other (cons '("python")       (list :count 3 :last-access now)))
         (entries (list root child other)))
    (let ((leaves (haystack--frecent-leaves entries)))
      (should     (member child leaves))
      (should     (member other leaves))
      (should-not (member root  leaves)))))

;;; haystack--frecency-score

(ert-deftest haystack-test/frecency-score-recent-entry ()
  "An entry accessed just now has score ≈ count (days ≈ 0 → clamped to 1)."
  (let ((entry (cons '("rust")
                     (list :count 5 :last-access (float-time)))))
    (should (= 5.0 (haystack--frecency-score entry)))))

(ert-deftest haystack-test/frecency-score-old-entry ()
  "An entry accessed 5 days ago has score ≈ count / 5."
  (let* ((five-days-ago (- (float-time) (* 5 86400)))
         (entry (cons '("rust")
                      (list :count 10 :last-access five-days-ago))))
    (should (< (abs (- 2.0 (haystack--frecency-score entry))) 0.01))))

;;; haystack--load-frecency / haystack--frecency-flush

(ert-deftest haystack-test/load-frecency-no-file-sets-nil ()
  "Returns nil when no frecency file exists."
  (haystack-test--with-notes-dir
    (haystack--load-frecency)
    (should (null haystack--frecency-data))))

(ert-deftest haystack-test/frecency-flush-writes-file ()
  "Flush writes data to disk and clears the dirty flag."
  (haystack-test--with-notes-dir
    (haystack-test--with-frecency (list (cons '("rust") '(:count 1 :last-access 0.0)))
      (setq haystack--frecency-dirty t)
      (haystack--frecency-flush)
      (should (file-exists-p (haystack--frecency-file)))
      (should-not haystack--frecency-dirty))))

(ert-deftest haystack-test/frecency-flush-skips-when-clean ()
  "Flush does nothing when not dirty."
  (haystack-test--with-notes-dir
    (haystack-test--with-frecency nil
      (setq haystack--frecency-dirty nil)
      (haystack--frecency-flush)
      (should-not (file-exists-p (haystack--frecency-file))))))

(ert-deftest haystack-test/frecency-round-trips ()
  "Data written by flush is read back correctly by load."
  (haystack-test--with-notes-dir
    (let* ((now   (float-time))
           (data  (list (cons '("rust" "async") (list :count 3 :last-access now)))))
      (haystack-test--with-frecency data
        (setq haystack--frecency-dirty t)
        (haystack--frecency-flush))
      (haystack-test--with-frecency nil
        (haystack--load-frecency)
        (let ((entry (assoc '("rust" "async") haystack--frecency-data)))
          (should entry)
          (should (= 3 (plist-get (cdr entry) :count))))))))

;;; integration: run-root-search records frecency

(ert-deftest haystack-test/run-root-search-records-frecency ()
  "haystack-run-root-search records an entry in haystack--frecency-data."
  (haystack-test--with-frecency nil
    (haystack-test--with-notes-dir
      (let ((note (expand-file-name "20240101000000-test.org" haystack-notes-directory)))
        (with-temp-file note (insert "rust content\n")))
      (let (created-buf)
        (cl-letf (((symbol-function 'pop-to-buffer)
                   (lambda (buf &rest _) (setq created-buf buf))))
          (haystack-run-root-search "rust"))
        (when (buffer-live-p created-buf) (kill-buffer created-buf)))
      (should (assoc '("rust") haystack--frecency-data)))))

;;; haystack-describe-frecent / haystack-frecent-mode

(defmacro haystack-test--with-frecent-buf (initial-data &rest body)
  "Open *haystack-frecent* with INITIAL-DATA and run BODY inside it.
`haystack--load-frecency' is stubbed so in-memory data is preserved."
  (declare (indent 1))
  `(haystack-test--with-frecency ,initial-data
     (cl-letf (((symbol-function 'haystack--load-frecency) #'ignore))
       (haystack-describe-frecent))
     (unwind-protect
         (with-current-buffer "*haystack-frecent*"
           ,@body)
       (when (get-buffer "*haystack-frecent*")
         (kill-buffer "*haystack-frecent*")))))

(ert-deftest haystack-test/describe-frecent-creates-buffer ()
  "haystack-describe-frecent creates the *haystack-frecent* buffer."
  (haystack-test--with-frecent-buf nil
    (should (get-buffer "*haystack-frecent*"))))

(ert-deftest haystack-test/describe-frecent-default-sort-is-score ()
  "Default sort order is `score'."
  (haystack-test--with-frecent-buf nil
    (should (eq haystack--frecent-sort-order 'score))))

(ert-deftest haystack-test/describe-frecent-shows-entries ()
  "Each recorded chain appears in the buffer."
  (let* ((now  (float-time))
         (data (list (cons '("rust") (list :count 5 :last-access now))
                     (cons '("python") (list :count 2 :last-access now)))))
    (haystack-test--with-frecent-buf data
      (should (string-match-p "rust" (buffer-string)))
      (should (string-match-p "python" (buffer-string))))))

(ert-deftest haystack-test/describe-frecent-chain-text-property ()
  "Entry lines carry a `haystack-frecent-chain' text property."
  (let* ((now  (float-time))
         (data (list (cons '("rust") (list :count 5 :last-access now)))))
    (haystack-test--with-frecent-buf data
      (goto-char (point-min))
      (let (found)
        (while (and (not found) (not (eobp)))
          (when (get-text-property (point) 'haystack-frecent-chain)
            (setq found t))
          (forward-line 1))
        (should found)))))

(ert-deftest haystack-test/frecent-toggle-sort-cycles ()
  "s cycles score → frequency → recency → score."
  (haystack-test--with-frecent-buf nil
    (should (eq haystack--frecent-sort-order 'score))
    (haystack-frecent-toggle-sort)
    (should (eq haystack--frecent-sort-order 'frequency))
    (haystack-frecent-toggle-sort)
    (should (eq haystack--frecent-sort-order 'recency))
    (haystack-frecent-toggle-sort)
    (should (eq haystack--frecent-sort-order 'score))))

(ert-deftest haystack-test/frecent-sort-score ()
  "t sets sort order to score and rerenders."
  (haystack-test--with-frecent-buf nil
    (setq haystack--frecent-sort-order 'recency)
    (haystack-frecent-sort-score)
    (should (eq haystack--frecent-sort-order 'score))
    (should (string-match-p "sort: score" (buffer-string)))))

(ert-deftest haystack-test/frecent-sort-frequency ()
  "f sets sort order to frequency and rerenders."
  (haystack-test--with-frecent-buf nil
    (haystack-frecent-sort-frequency)
    (should (eq haystack--frecent-sort-order 'frequency))
    (should (string-match-p "sort: frequency" (buffer-string)))))

(ert-deftest haystack-test/frecent-sort-recency ()
  "r sets sort order to recency and rerenders."
  (haystack-test--with-frecent-buf nil
    (haystack-frecent-sort-recency)
    (should (eq haystack--frecent-sort-order 'recency))
    (should (string-match-p "sort: recency" (buffer-string)))))

(ert-deftest haystack-test/frecent-kill-entry-removes-from-data ()
  "k removes the entry from haystack--frecency-data."
  (let* ((now  (float-time))
         (data (list (cons '("rust") (list :count 5 :last-access now)))))
    (haystack-test--with-frecent-buf data
      (goto-char (point-min))
      (while (and (not (get-text-property (point) 'haystack-frecent-chain))
                  (not (eobp)))
        (forward-line 1))
      (cl-letf (((symbol-function 'y-or-n-p) (lambda (_) t)))
        (haystack-frecent-kill-entry))
      (should (null (assoc '("rust") haystack--frecency-data))))))

(ert-deftest haystack-test/frecent-kill-entry-sets-dirty ()
  "k sets the frecency dirty flag."
  (let* ((now  (float-time))
         (data (list (cons '("rust") (list :count 5 :last-access now)))))
    (haystack-test--with-frecent-buf data
      (goto-char (point-min))
      (while (and (not (get-text-property (point) 'haystack-frecent-chain))
                  (not (eobp)))
        (forward-line 1))
      (cl-letf (((symbol-function 'y-or-n-p) (lambda (_) t)))
        (haystack-frecent-kill-entry))
      (should haystack--frecency-dirty))))

(ert-deftest haystack-test/frecent-kill-entry-aborts-on-no ()
  "k leaves data intact when user answers no."
  (let* ((now  (float-time))
         (data (list (cons '("rust") (list :count 5 :last-access now)))))
    (haystack-test--with-frecent-buf data
      (goto-char (point-min))
      (while (and (not (get-text-property (point) 'haystack-frecent-chain))
                  (not (eobp)))
        (forward-line 1))
      (cl-letf (((symbol-function 'y-or-n-p) (lambda (_) nil)))
        (haystack-frecent-kill-entry))
      (should (assoc '("rust") haystack--frecency-data)))))

(ert-deftest haystack-test/frecent-kill-entry-errors-off-entry ()
  "k signals user-error when point is not on an entry line."
  (haystack-test--with-frecent-buf nil
    (goto-char (point-min))
    (should-error (haystack-frecent-kill-entry) :type 'user-error)))

(ert-deftest haystack-test/frecent-toggle-leaf-toggles ()
  "a toggles haystack--frecent-leaf-only and rerenders."
  (haystack-test--with-frecent-buf nil
    (should-not haystack--frecent-leaf-only)
    (haystack-frecent-toggle-leaf)
    (should haystack--frecent-leaf-only)
    (should (string-match-p "view: leaf" (buffer-string)))
    (haystack-frecent-toggle-leaf)
    (should-not haystack--frecent-leaf-only)
    (should (string-match-p "view: all" (buffer-string)))))

(ert-deftest haystack-test/frecent-toggle-leaf-filters-entries ()
  "Leaf mode hides dominated entries."
  (let* ((now (float-time))
         (data (list (cons '("rust")         (list :count 2 :last-access now))
                     (cons '("rust" "async") (list :count 5 :last-access now)))))
    (haystack-test--with-frecent-buf data
      (haystack-frecent-toggle-leaf)
      (should     (string-match-p "async" (buffer-string)))
      (should-not (string-match-p "^  .*rust$" (buffer-string))))))

(ert-deftest haystack-test/frecent-mode-keybindings ()
  "s/t/f/r/a/k/? are bound in haystack-frecent-mode-map."
  (should (eq (lookup-key haystack-frecent-mode-map "s") #'haystack-frecent-toggle-sort))
  (should (eq (lookup-key haystack-frecent-mode-map "t") #'haystack-frecent-sort-score))
  (should (eq (lookup-key haystack-frecent-mode-map "f") #'haystack-frecent-sort-frequency))
  (should (eq (lookup-key haystack-frecent-mode-map "r") #'haystack-frecent-sort-recency))
  (should (eq (lookup-key haystack-frecent-mode-map "v") #'haystack-frecent-toggle-leaf))
  (should (eq (lookup-key haystack-frecent-mode-map "k") #'haystack-frecent-kill-entry))
  (should (eq (lookup-key haystack-frecent-mode-map "?") #'haystack-frecent-help)))

;;; haystack-frecent errors when empty

(ert-deftest haystack-test/frecent-errors-when-no-data ()
  "Signals user-error when no frecency entries exist."
  (haystack-test--with-frecency nil
    (should-error (haystack-frecent) :type 'user-error)))

;;;; Prefix map

(ert-deftest haystack-test/prefix-map-bindings ()
  "Every expected key is bound to the right command in `haystack-prefix-map'."
  (dolist (binding '(("s" . haystack-run-root-search)
                     ("r" . haystack-search-region)
                     ("n" . haystack-new-note)
                     ("y" . haystack-yank-moc)
                     ("t" . haystack-show-tree)
                     ("f" . haystack-frecent)))
    (should (eq (lookup-key haystack-prefix-map (kbd (car binding)))
                (cdr binding)))))

;;;; haystack-help

(ert-deftest haystack-test/help-key-returns-binding ()
  "Returns the key description for a bound command."
  (should (equal (haystack--help-key 'haystack-next-match) "n")))

(ert-deftest haystack-test/help-key-returns-unbound-for-unknown ()
  "Returns \"unbound\" for a command not in the results map."
  (should (equal (haystack--help-key 'undefined-command-xyz) "unbound")))

(ert-deftest haystack-test/help-content-contains-all-commands ()
  "Help content mentions every user-facing command."
  (let ((content (haystack--help-content)))
    (dolist (cmd '("next match" "previous match" "filter further"
                   "show tree" "go up" "go down" "kill node" "kill subtree" "kill whole tree"
                   "copy moc"))
      (should (string-match-p cmd content)))))

(ert-deftest haystack-test/haystack-help-creates-buffer ()
  "haystack-help creates and displays *haystack-help*."
  (haystack-help)
  (let ((buf (get-buffer "*haystack-help*")))
    (should (buffer-live-p buf))
    (kill-buffer buf)))

;;;; haystack--display-term

(ert-deftest haystack-test/display-term-short-passthrough ()
  "Terms 30 chars or shorter are returned as-is."
  (should (equal (haystack--display-term "rust") "rust"))
  (should (equal (haystack--display-term (make-string 30 ?x))
                 (make-string 30 ?x))))

(ert-deftest haystack-test/display-term-truncates-long ()
  "Terms longer than 30 chars get first-13...last-13 truncation."
  (let* ((term "abcdefghijklmnopqrstuvwxyz0123456789")  ; 36 chars
         (result (haystack--display-term term)))
    (should (equal result "abcdefghijklm...xyz0123456789"))
    (should (string-prefix-p "abcdefghijklm" result))
    (should (string-suffix-p "xyz0123456789" result))
    (should (string-match-p "\\.\\.\\." result))))

(ert-deftest haystack-test/display-term-normalises-whitespace ()
  "Newlines and tabs are collapsed to single spaces and trimmed."
  (should (equal (haystack--display-term "  foo\n\nbar\t baz  ")
                 "foo bar baz")))

(ert-deftest haystack-test/display-term-paragraph-gets-truncated ()
  "A paragraph selection collapses whitespace and truncates."
  (let* ((para "This is a long paragraph that someone selected by accident.")
         (result (haystack--display-term para)))
    ;; Must not contain newlines or runs of spaces.
    (should-not (string-match-p "\n" result))
    ;; Must be at most 29 chars (13+3+13) after truncation.
    (should (<= (length result) 29))
    ;; Must contain the ellipsis marker.
    (should (string-match-p "\\.\\.\\." result))))

;;;; haystack--tree-term-label

(ert-deftest haystack-test/tree-term-label-bare ()
  (should (equal (haystack--tree-term-label "rust" nil nil nil nil) "rust")))

(ert-deftest haystack-test/tree-term-label-negated ()
  (should (equal (haystack--tree-term-label "rust" t nil nil nil) "!rust")))

(ert-deftest haystack-test/tree-term-label-filename ()
  (should (equal (haystack--tree-term-label "foo" nil t nil nil) "/foo")))

(ert-deftest haystack-test/tree-term-label-negated-filename ()
  (should (equal (haystack--tree-term-label "foo" t t nil nil) "!/foo")))

(ert-deftest haystack-test/tree-term-label-regex ()
  (should (equal (haystack--tree-term-label "fo+" nil nil nil t) "~fo+")))

(ert-deftest haystack-test/tree-term-label-literal ()
  (should (equal (haystack--tree-term-label "foo" nil nil t nil) "=foo")))

;;;; Tree view

(ert-deftest haystack-test/tree-roots-finds-root-buffers ()
  "Returns buffers with no live parent."
  (let* ((root  (haystack-test--make-results-buf " *hs-tree-root*"  nil '(:root-term "rust" :filters nil)))
         (child (haystack-test--make-results-buf " *hs-tree-child*" root '(:root-term "rust" :filters ((:term "async"))))))
    (unwind-protect
        (let ((roots (haystack--tree-roots)))
          (should     (memq root  roots))
          (should-not (memq child roots)))
      (kill-buffer root)
      (kill-buffer child))))

(ert-deftest haystack-test/tree-roots-treats-dead-parent-as-root ()
  "A buffer whose parent is dead is treated as a root."
  (let* ((dead-parent (haystack-test--make-results-buf " *hs-tree-dead*" nil '(:root-term "x" :filters nil)))
         (orphan      (haystack-test--make-results-buf " *hs-tree-orphan*" dead-parent '(:root-term "x" :filters ((:term "y"))))))
    (kill-buffer dead-parent)
    (unwind-protect
        (should (memq orphan (haystack--tree-roots)))
      (kill-buffer orphan))))

(ert-deftest haystack-test/tree-render-node-leaf-term ()
  "Renders the leaf filter term for child buffers."
  (let* ((root  (haystack-test--make-results-buf " *hs-rn-root*" nil '(:root-term "rust" :filters nil)))
         (child (haystack-test--make-results-buf " *hs-rn-child*" root '(:root-term "rust" :filters ((:term "async"))))))
    (unwind-protect
        (with-temp-buffer
          (haystack--tree-render-node root nil "" "" 0)
          (should (string-match-p "rust"  (buffer-string)))
          (should (string-match-p "async" (buffer-string))))
      (kill-buffer root)
      (kill-buffer child))))

(ert-deftest haystack-test/tree-render-node-marks-current ()
  "Current buffer line contains ←."
  (let ((root (haystack-test--make-results-buf " *hs-rn-cur*" nil '(:root-term "rust" :filters nil))))
    (unwind-protect
        (with-temp-buffer
          (haystack--tree-render-node root root "" "" 0)
          (should (string-match-p "←" (buffer-string))))
      (kill-buffer root))))

(ert-deftest haystack-test/tree-render-node-indents-children ()
  "Child nodes are indented relative to their parent."
  (let* ((root  (haystack-test--make-results-buf " *hs-ind-root*" nil '(:root-term "rust" :filters nil)))
         (child (haystack-test--make-results-buf " *hs-ind-child*" root '(:root-term "rust" :filters ((:term "async"))))))
    (unwind-protect
        (with-temp-buffer
          (haystack--tree-render-node root nil "" "" 0)
          (let ((lines (split-string (buffer-string) "\n" t)))
            (should (string-match-p "^rust"      (nth 0 lines)))
            (should (string-match-p "└── async$" (nth 1 lines)))))
      (kill-buffer root)
      (kill-buffer child))))

(ert-deftest haystack-test/tree-render-node-depth-property ()
  "Each rendered line carries the correct haystack-tree-depth property."
  (let* ((root  (haystack-test--make-results-buf " *hs-dp-root*" nil '(:root-term "rust" :filters nil)))
         (child (haystack-test--make-results-buf " *hs-dp-child*" root '(:root-term "rust" :filters ((:term "async"))))))
    (unwind-protect
        (with-temp-buffer
          (haystack--tree-render-node root nil "" "" 0)
          (goto-char (point-min))
          (should (= (get-text-property (point) 'haystack-tree-depth) 0))
          (forward-line 1)
          (should (= (get-text-property (point) 'haystack-tree-depth) 1)))
      (kill-buffer root)
      (kill-buffer child))))

(defmacro haystack-test--with-tree (&rest body)
  "Run BODY with a populated *haystack-tree* buffer current."
  (declare (indent 0))
  `(let* ((root   (haystack-test--make-results-buf
                   " *hs-nav-root*" nil
                   '(:root-term "rust" :root-filename nil
                     :root-literal nil :root-regex nil :filters nil)))
           (child1 (haystack-test--make-results-buf
                    " *hs-nav-c1*" root
                    '(:root-term "rust" :filters ((:term "async" :negated nil
                                                   :filename nil :literal nil :regex nil)))))
           (child2 (haystack-test--make-results-buf
                    " *hs-nav-c2*" root
                    '(:root-term "rust" :filters ((:term "ownership" :negated nil
                                                   :filename nil :literal nil :regex nil))))))
     (unwind-protect
         (progn
           (haystack-show-tree)
           (with-current-buffer "*haystack-tree*"
             ,@body))
       (when (get-buffer "*haystack-tree*") (kill-buffer "*haystack-tree*"))
       (kill-buffer root)
       (kill-buffer child1)
       (kill-buffer child2))))

(ert-deftest haystack-test/tree-next-moves-to-next-entry ()
  "n moves to the next line with a buffer property, skipping blanks."
  (haystack-test--with-tree
    (goto-char (point-min))
    (haystack-tree-next)
    (should (get-text-property (point) 'haystack-tree-buffer))))

(ert-deftest haystack-test/tree-prev-moves-to-prev-entry ()
  "p moves to the previous line with a buffer property."
  (haystack-test--with-tree
    (goto-char (point-max))
    (haystack-tree-prev)
    (should (get-text-property (point) 'haystack-tree-buffer))))

(ert-deftest haystack-test/tree-next-sibling-skips-children ()
  "M-n from a child jumps to the next sibling, not deeper nodes."
  (haystack-test--with-tree
    (goto-char (point-min))
    (haystack-tree-next)
    (haystack-tree-next)
    (let ((depth-before (get-text-property (point) 'haystack-tree-depth)))
      (haystack-tree-next-sibling)
      (should (= (get-text-property (point) 'haystack-tree-depth) depth-before)))))

(ert-deftest haystack-test/tree-next-sibling-errors-at-last ()
  "M-n errors when there is no next sibling."
  (haystack-test--with-tree
    (goto-char (point-min))
    (haystack-tree-next)
    (should-error (haystack-tree-next-sibling) :type 'user-error)))

(ert-deftest haystack-test/show-tree-creates-buffer ()
  "haystack-show-tree creates and displays *haystack-tree*."
  (haystack-show-tree)
  (let ((buf (get-buffer "*haystack-tree*")))
    (should (buffer-live-p buf))
    (kill-buffer buf)))

(ert-deftest haystack-test/tree-render-node-text-property ()
  "Each rendered line carries a haystack-tree-buffer text property."
  (let ((root (haystack-test--make-results-buf " *hs-tp-root*" nil '(:root-term "rust" :filters nil))))
    (unwind-protect
        (with-temp-buffer
          (haystack--tree-render-node root nil "" "" 0)
          (goto-char (point-min))
          (should (eq (get-text-property (point) 'haystack-tree-buffer) root)))
      (kill-buffer root))))

;;;; Header buttons

(defun haystack-test--make-header-buf ()
  "Return a results buffer with header buttons (no real rg output)."
  (let ((buf (get-buffer-create " *hs-btn-test*")))
    (with-current-buffer buf
      (let ((inhibit-read-only t))
        (erase-buffer)
        (insert (haystack--format-header "root=rust" 0 0))
        (let ((header-end (point)))
          (grep-mode)
          (haystack-results-mode 1)
          (haystack--apply-header-buttons)
          (let ((inhibit-read-only t))
            (put-text-property (point-min) header-end 'read-only t))
          (setq haystack--search-descriptor '(:root-term "rust" :filters nil)
                haystack--parent-buffer nil))))
    buf))

(ert-deftest haystack-test/header-contains-nav-line ()
  "Formatted header includes the navigation line."
  (let ((h (haystack--format-header "root=rust" 3 10)))
    (should (string-match-p "\\[root\\]" h))
    (should (string-match-p "\\[up\\]" h))
    (should (string-match-p "\\[down\\]" h))
    (should (string-match-p "\\[tree\\]" h))))

(ert-deftest haystack-test/header-buttons-are-buttons ()
  "apply-header-buttons wires real button text properties into the header."
  (let ((buf (haystack-test--make-header-buf)))
    (unwind-protect
        (with-current-buffer buf
          (dolist (label '("[root]" "[up]" "[down]" "[tree]"))
            (goto-char (point-min))
            (search-forward label)
            (goto-char (match-beginning 0))
            (should (button-at (point)))))
      (kill-buffer buf))))

(ert-deftest haystack-test/go-root-at-root-is-noop ()
  "haystack-go-root messages when already at root."
  (let ((buf (haystack-test--make-results-buf " *hs-root-nav*" nil
                                              '(:root-term "rust" :filters nil))))
    (unwind-protect
        (with-current-buffer buf
          (haystack-go-root)
          (should (eq (current-buffer) buf)))
      (kill-buffer buf))))

(ert-deftest haystack-test/go-root-walks-to-root ()
  "haystack-go-root switches to the root buffer from a child."
  (let* ((root  (haystack-test--make-results-buf " *hs-r-root*" nil
                                                 '(:root-term "rust" :filters nil)))
         (child (haystack-test--make-results-buf " *hs-r-child*" root
                                                 '(:root-term "rust" :filters ((:term "async"))))))
    (unwind-protect
        (with-current-buffer child
          (haystack-go-root)
          (should (eq (current-buffer) root)))
      (kill-buffer root)
      (kill-buffer child))))

(ert-deftest haystack-test/ret-binding-exists ()
  "RET is bound to haystack-ret in haystack-results-mode-map."
  (should (eq (lookup-key haystack-results-mode-map (kbd "RET"))
              'haystack-ret)))

;;;; Demo mode

(defmacro haystack-test--with-demo-dir (&rest body)
  "Run BODY with a temporary demo source directory and reset demo state after."
  `(let* ((demo-src (make-temp-file "haystack-demo-src-" t))
          (saved-notes haystack-notes-directory)
          (saved-demo haystack--demo-active))
     (unwind-protect
         (progn
           ;; Create a minimal demo/notes layout at demo-src
           (make-directory (expand-file-name "demo/notes" demo-src) t)
           (with-temp-file (expand-file-name "demo/notes/sample.org" demo-src)
             (insert "#+TITLE: Sample\n#+DATE: 2025-01-01\n# %%% pkm-end-frontmatter %%%\n\nSample note.\n"))
           (cl-letf (((symbol-function 'haystack--demo-package-dir)
                      (lambda () demo-src)))
             ,@body))
       (setq haystack--demo-active     saved-demo
             haystack--demo-temp-dir   nil
             haystack--demo-saved-state nil
             haystack-notes-directory  saved-notes)
       (delete-directory demo-src t))))

(ert-deftest haystack-test/demo-sets-notes-directory ()
  "haystack-demo switches haystack-notes-directory to a temp copy."
  (haystack-test--with-demo-dir
   (haystack-demo)
   (should haystack--demo-active)
   (should haystack--demo-temp-dir)
   (should (not (equal haystack-notes-directory saved-notes)))
   (should (file-directory-p haystack-notes-directory))
   ;; Clean up the temp dir.
   (let ((td haystack--demo-temp-dir))
     (setq haystack--demo-active nil haystack--demo-temp-dir nil
           haystack--demo-saved-state nil haystack-notes-directory saved-notes)
     (when (file-directory-p td) (delete-directory td t)))))

(ert-deftest haystack-test/demo-errors-if-already-active ()
  "haystack-demo signals if called while already active."
  (haystack-test--with-demo-dir
   (haystack-demo)
   (should-error (haystack-demo) :type 'user-error)
   (let ((td haystack--demo-temp-dir))
     (setq haystack--demo-active nil haystack--demo-temp-dir nil
           haystack--demo-saved-state nil haystack-notes-directory saved-notes)
     (when (file-directory-p td) (delete-directory td t)))))

(ert-deftest haystack-test/demo-stop-restores-directory ()
  "haystack-demo-stop restores the original notes directory."
  (haystack-test--with-demo-dir
   (haystack-demo)
   (haystack-demo-stop)
   (should (equal haystack-notes-directory saved-notes))
   (should (not haystack--demo-active))
   (should (not haystack--demo-temp-dir))))

(ert-deftest haystack-test/demo-stop-errors-if-not-active ()
  "haystack-demo-stop signals if demo is not running."
  (should-error (haystack-demo-stop) :type 'user-error))

(ert-deftest haystack-test/demo-header-shows-warning ()
  "haystack--format-header includes demo warning when demo is active."
  (let ((haystack--demo-active t))
    (should (string-match-p "DEMO MODE"
                            (haystack--format-header "root=test" 1 1)))))

(ert-deftest haystack-test/demo-header-no-warning-when-inactive ()
  "haystack--format-header does not include demo warning when inactive."
  (let ((haystack--demo-active nil))
    (should (not (string-match-p "DEMO MODE"
                                 (haystack--format-header "root=test" 1 1))))))

(provide 'haystack-test)
;;; haystack-test.el ends here
