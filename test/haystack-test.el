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
  "Run BODY with a temporary directory bound as `haystack-notes-directory'.
Also resets `haystack--expansion-groups-loaded' so each test gets a
clean cache state independent of test execution order."
  `(let ((haystack-notes-directory (make-temp-file "haystack-test-" t))
         (haystack--expansion-groups-loaded nil))
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
  "Return non-nil if STR contains the haystack-end-frontmatter sentinel."
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

(ert-deftest haystack-test/sanitize-slug-all-unsafe-returns-empty ()
  "`haystack--sanitize-slug' returns empty string for all-unsafe input."
  (should (string-empty-p (haystack--sanitize-slug ":/\\"))))

(ert-deftest haystack-test/new-note-empty-slug-signals-user-error ()
  "`haystack-new-note' signals user-error when slug sanitizes to empty."
  (haystack-test--with-notes-dir
   (cl-letf (((symbol-function 'read-string)
              (lambda (_prompt &optional _init _hist _default) ":/\\")))
     (should-error (haystack-new-note) :type 'user-error))))

(ert-deftest haystack-test/new-note-with-moc-empty-slug-signals-user-error ()
  "`haystack-new-note-with-moc' signals user-error when slug sanitizes to empty."
  (haystack-test--with-notes-dir
   (let* ((desc (list :root-term "foo" :root-expanded "foo" :root-literal nil
                      :root-regex nil :root-filename nil :root-expansion nil
                      :filters nil :composite-filter 'exclude))
          (buf  (get-buffer-create "*haystack:test-slug-guard*")))
     (with-current-buffer buf
       (setq-local haystack--search-descriptor desc)
       (insert "/notes/foo.org:1:some content\n"))
     (with-current-buffer buf
       (cl-letf (((symbol-function 'read-string)
                  (lambda (_prompt &optional _init _hist _default) ":/\\")))
         (should-error (haystack-new-note-with-moc) :type 'user-error)))
     (kill-buffer buf))))

;;;; haystack-regenerate-frontmatter

(ert-deftest haystack-test/regen-replaces-frontmatter ()
  "Replaces frontmatter up to the sentinel, preserving the body."
  (haystack-test--with-file-buffer "org"
    (insert "#+TITLE: old title\n#+DATE: 1970-01-01\n"
            "# %%% haystack-end-frontmatter %%%\n\nBody content.\n")
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
            "# %%% haystack-end-frontmatter %%%\n\nBody.\n")
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
    (let ((original "#+TITLE: original\n# %%% haystack-end-frontmatter %%%\n\nBody.\n"))
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

;;; haystack--frecency-rewrite-term

(ert-deftest haystack-test/frecency-rewrite-term-root-position ()
  "Rewrites the old root term when it appears in the root position."
  (should (equal (haystack--frecency-rewrite-term '("programming" "rust") "programming" "coding")
                 '("coding" "rust"))))

(ert-deftest haystack-test/frecency-rewrite-term-filter-position ()
  "Rewrites the old root term when it appears in a filter position."
  (should (equal (haystack--frecency-rewrite-term '("rust" "programming") "programming" "coding")
                 '("rust" "coding"))))

(ert-deftest haystack-test/frecency-rewrite-term-preserves-prefix ()
  "Prefix characters on a matched term are preserved after rewriting."
  (should (equal (haystack--frecency-rewrite-term '("rust" "!programming") "programming" "coding")
                 '("rust" "!coding"))))

(ert-deftest haystack-test/frecency-rewrite-term-compound-prefix ()
  "Compound prefix (e.g. !=) is preserved after rewriting."
  (should (equal (haystack--frecency-rewrite-term '("rust" "!=programming") "programming" "coding")
                 '("rust" "!=coding"))))

(ert-deftest haystack-test/frecency-rewrite-term-non-matching-unchanged ()
  "Terms that do not match old-root are returned unchanged."
  (should (equal (haystack--frecency-rewrite-term '("rust" "async") "programming" "coding")
                 '("rust" "async"))))

(ert-deftest haystack-test/frecency-rewrite-term-case-insensitive ()
  "Matching is case-insensitive."
  (should (equal (haystack--frecency-rewrite-term '("Programming" "rust") "programming" "coding")
                 '("coding" "rust"))))

;;; haystack--frecency-rename-in-data

(ert-deftest haystack-test/frecency-rename-in-data-single-entry ()
  "Rewrites the matching term in a single frecency entry."
  (let* ((data '((("programming" "rust") :count 3 :last-access 1000.0)))
         (result (haystack--frecency-rename-in-data data "programming" "coding")))
    (should (equal (caar result) '("coding" "rust")))))

(ert-deftest haystack-test/frecency-rename-in-data-multiple-entries ()
  "Rewrites matching terms across multiple entries."
  (let* ((data '((("programming") :count 2 :last-access 1000.0)
                 (("rust" "programming") :count 1 :last-access 900.0)))
         (result (haystack--frecency-rename-in-data data "programming" "coding")))
    (should (assoc '("coding") result))
    (should (assoc '("rust" "coding") result))))

(ert-deftest haystack-test/frecency-rename-in-data-non-matching-unchanged ()
  "Entries without the old term are returned unchanged."
  (let* ((data '((("rust" "async") :count 5 :last-access 1000.0)))
         (result (haystack--frecency-rename-in-data data "programming" "coding")))
    (should (assoc '("rust" "async") result))))

(ert-deftest haystack-test/frecency-rename-in-data-collision-merges ()
  "When rename would produce a duplicate key, entries are merged (counts summed, latest timestamp kept)."
  (let* ((data '((("coding")       :count 4 :last-access 2000.0)
                 (("programming")  :count 3 :last-access 1000.0)))
         (result (haystack--frecency-rename-in-data data "programming" "coding")))
    (should (= (length result) 1))
    (let ((entry (assoc '("coding") result)))
      (should (= (plist-get (cdr entry) :count) 7))
      (should (= (plist-get (cdr entry) :last-access) 2000.0)))))

;;; haystack--composite-rename-pairs

(ert-deftest haystack-test/composite-rename-pairs-root-position ()
  "Finds composite whose slug starts with the old slug."
  (haystack-test--with-notes-dir
   (with-temp-file (expand-file-name "@comp__programming.org" haystack-notes-directory)
     (insert ""))
   (let ((pairs (haystack--composite-rename-pairs "programming" "coding")))
     (should (= (length pairs) 1))
     (should (string-match-p "@comp__coding\\.org" (cdr (car pairs)))))))

(ert-deftest haystack-test/composite-rename-pairs-middle-position ()
  "Finds composite whose slug contains the old slug as a middle segment."
  (haystack-test--with-notes-dir
   (with-temp-file (expand-file-name "@comp__rust__programming__async.org" haystack-notes-directory)
     (insert ""))
   (let ((pairs (haystack--composite-rename-pairs "programming" "coding")))
     (should (= (length pairs) 1))
     (should (string-match-p "@comp__rust__coding__async\\.org" (cdr (car pairs)))))))

(ert-deftest haystack-test/composite-rename-pairs-non-matching-excluded ()
  "Composites whose slugs do not contain old slug are excluded."
  (haystack-test--with-notes-dir
   (with-temp-file (expand-file-name "@comp__rust__async.org" haystack-notes-directory)
     (insert ""))
   (should (null (haystack--composite-rename-pairs "programming" "coding")))))

(ert-deftest haystack-test/composite-rename-pairs-no-composites ()
  "Returns empty list when there are no composite files."
  (haystack-test--with-notes-dir
   (should (null (haystack--composite-rename-pairs "programming" "coding")))))

;;; haystack--rename-composites-atomic

(ert-deftest haystack-test/rename-composites-atomic-succeeds ()
  "Renames all files when all targets are available."
  (haystack-test--with-notes-dir
   (let ((old (expand-file-name "@comp__programming.org" haystack-notes-directory))
         (new (expand-file-name "@comp__coding.org"      haystack-notes-directory)))
     (with-temp-file old (insert ""))
     (haystack--rename-composites-atomic (list (cons old new)))
     (should     (file-exists-p new))
     (should-not (file-exists-p old)))))

(ert-deftest haystack-test/rename-composites-atomic-empty-list ()
  "No-op on empty pairs list."
  (haystack-test--with-notes-dir
   (should (null (haystack--rename-composites-atomic nil)))))

(ert-deftest haystack-test/rename-composites-atomic-rollback-on-failure ()
  "A failed rename rolls back already-completed renames."
  (haystack-test--with-notes-dir
   (let ((old1 (expand-file-name "@comp__alpha.org" haystack-notes-directory))
         (new1 (expand-file-name "@comp__beta.org"  haystack-notes-directory))
         (old2 "/nonexistent/path/@comp__gamma.org")
         (new2 "/nonexistent/path/@comp__delta.org"))
     (with-temp-file old1 (insert ""))
     (should-error (haystack--rename-composites-atomic (list (cons old1 new1)
                                                             (cons old2 new2))))
     ;; old1 should have been restored
     (should     (file-exists-p old1))
     (should-not (file-exists-p new1)))))

;;; haystack-rename-group-root — full atomic integration

(ert-deftest haystack-test/rename-group-root-updates-frecency ()
  "rename-group-root rewrites matching frecency chain keys."
  (haystack-test--with-groups '(("programming" . ("coding" "scripting")))
    (haystack-test--with-frecency
     '((("programming" "rust") :count 2 :last-access 1000.0)
       (("rust" "programming") :count 1 :last-access 900.0))
     (haystack-rename-group-root "programming" "dev")
     (should (assoc '("dev" "rust") haystack--frecency-data))
     (should (assoc '("rust" "dev") haystack--frecency-data))
     (should-not (assoc '("programming" "rust") haystack--frecency-data)))))

(ert-deftest haystack-test/rename-group-root-renames-composites ()
  "rename-group-root renames composite files containing the old slug."
  (haystack-test--with-groups '(("programming" . ("coding")))
    (with-temp-file (expand-file-name "@comp__programming.org" haystack-notes-directory)
      (insert ""))
    (haystack-test--with-frecency nil
      (haystack-rename-group-root "programming" "dev"))
    (should     (file-exists-p (expand-file-name "@comp__dev.org" haystack-notes-directory)))
    (should-not (file-exists-p (expand-file-name "@comp__programming.org" haystack-notes-directory)))))

(ert-deftest haystack-test/rename-group-root-no-composites-no-error ()
  "rename-group-root completes without error when no composites exist."
  (haystack-test--with-groups '(("programming" . ("coding")))
    (haystack-test--with-frecency nil
      (should-not (condition-case err
                      (progn (haystack-rename-group-root "programming" "dev") nil)
                    (error err))))))

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

;;;; haystack--rg-args

(ert-deftest haystack-test/rg-args-excludes-composites-by-default ()
  "Default composite-filter produces --glob=!@*."
  (let ((haystack-file-glob nil))
    (should (member "--glob=!@*" (haystack--rg-args :pattern "rust")))))

(ert-deftest haystack-test/rg-args-exclude-symbol ()
  "'exclude produces --glob=!@*."
  (let ((haystack-file-glob nil))
    (should (member "--glob=!@*"
                    (haystack--rg-args :composite-filter 'exclude :pattern "rust")))))

(ert-deftest haystack-test/rg-args-only-symbol ()
  "'only produces --glob=@* with no negation variant."
  (let ((haystack-file-glob nil))
    (let ((args (haystack--rg-args :composite-filter 'only :pattern "rust")))
      (should (member "--glob=@*" args))
      (should-not (member "--glob=!@*" args)))))

(ert-deftest haystack-test/rg-args-all-symbol ()
  "'all produces no @* glob at all."
  (let ((haystack-file-glob nil))
    (should-not (cl-some (lambda (a) (string-match-p "@\\*" a))
                         (haystack--rg-args :composite-filter 'all :pattern "rust")))))

(ert-deftest haystack-test/rg-args-applies-file-glob ()
  "`haystack-file-glob' entries appear as --glob= arguments when :file-glob t."
  (let ((haystack-notes-directory "/notes")
        (haystack-file-glob '("*.org" "*.md")))
    (let ((args (haystack--rg-args :composite-filter 'exclude
                                   :file-glob t
                                   :pattern "rust"
                                   :extra-args (list "/notes"))))
      (should (member "--glob=*.org" args))
      (should (member "--glob=*.md" args)))))

(ert-deftest haystack-test/rg-args-contains-pattern-and-directory ()
  "Pattern and notes directory appear in the argument list."
  (let ((haystack-notes-directory "/my/notes")
        (haystack-file-glob nil))
    (let ((args (haystack--rg-args :composite-filter 'exclude
                                   :pattern "mypattern"
                                   :extra-args (list "/my/notes"))))
      (should (member "mypattern" args))
      (should (member "/my/notes" args)))))

(ert-deftest haystack-test/rg-args-expands-tilde-in-directory ()
  "A ~ in `haystack-notes-directory' is expanded before being passed as extra-arg."
  (let ((haystack-notes-directory "~/notes")
        (haystack-file-glob nil))
    (let ((args (haystack--rg-args :composite-filter 'exclude
                                   :pattern "rust"
                                   :extra-args (list (expand-file-name haystack-notes-directory)))))
      (should-not (member "~/notes" args))
      (should (member (expand-file-name "~/notes") args)))))

(ert-deftest haystack-test/rg-args-count-mode-has-count-and-with-filename ()
  "Count mode adds --count and --with-filename at the head."
  (let ((haystack-file-glob nil))
    (let ((args (haystack--rg-args :count t :composite-filter 'all :pattern "rust")))
      (should (member "--count" args))
      (should (member "--with-filename" args))
      (should-not (member "--line-number" args)))))

(ert-deftest haystack-test/rg-args-fwm-mode-has-files-with-matches ()
  "Files-with-matches mode adds --files-with-matches."
  (let ((haystack-file-glob nil))
    (let ((args (haystack--rg-args :files-with-matches t
                                   :composite-filter 'all :pattern "rust")))
      (should (member "--files-with-matches" args))
      (should-not (member "--line-number" args)))))

(ert-deftest haystack-test/rg-args-file-glob-not-applied-without-flag ()
  "File globs are NOT added when :file-glob is nil (or omitted)."
  (let ((haystack-file-glob '("*.org")))
    (let ((args (haystack--rg-args :composite-filter 'exclude :pattern "rust")))
      (should-not (member "--glob=*.org" args)))))

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

;;;; haystack--rg-args (content mode)

(ert-deftest haystack-test/rg-base-args-exclude ()
  "Content mode with 'exclude adds --glob=!@*."
  (let ((haystack-file-glob nil))
    (should (member "--glob=!@*" (haystack--rg-args :composite-filter 'exclude)))))

(ert-deftest haystack-test/rg-base-args-only ()
  "Content mode with 'only adds --glob=@* only."
  (let ((haystack-file-glob nil))
    (let ((args (haystack--rg-args :composite-filter 'only)))
      (should (member "--glob=@*" args))
      (should-not (member "--glob=!@*" args)))))

(ert-deftest haystack-test/rg-base-args-all ()
  "Content mode with 'all adds no @* glob."
  (let ((haystack-file-glob nil))
    (should-not (cl-some (lambda (a) (string-match-p "@\\*" a))
                         (haystack--rg-args :composite-filter 'all)))))

(ert-deftest haystack-test/rg-base-args-default-is-exclude ()
  "Content mode with no composite-filter defaults to 'exclude."
  (let ((haystack-file-glob nil))
    (should (member "--glob=!@*" (haystack--rg-args)))))

(ert-deftest haystack-test/rg-base-args-has-max-count ()
  "Content mode includes --max-count=50 to clamp per-file output."
  (let ((haystack-file-glob nil))
    (should (member "--max-count=50" (haystack--rg-args)))))

(ert-deftest haystack-test/rg-base-args-has-max-columns ()
  "Content mode includes --max-columns=500 to drop minified/base64 lines."
  (let ((haystack-file-glob nil))
    (should (member "--max-columns=500" (haystack--rg-args)))))

;;;; haystack--count-output-stats

(ert-deftest haystack-test/count-output-stats-empty ()
  (should (equal '(0 . 0) (haystack--count-output-stats ""))))

(ert-deftest haystack-test/count-output-stats-single-file ()
  (should (equal '(1 . 47) (haystack--count-output-stats "/notes/foo.org:47\n"))))

(ert-deftest haystack-test/count-output-stats-multi-file ()
  (let* ((out   "/notes/a.org:10\n/notes/b.org:5\n/notes/c.org:1\n")
         (stats (haystack--count-output-stats out)))
    (should (= (car stats) 3))
    (should (= (cdr stats) 16))))

(ert-deftest haystack-test/count-output-stats-ignores-blank-lines ()
  (should (equal '(2 . 10)
                 (haystack--count-output-stats "/notes/a.org:3\n\n/notes/b.org:7\n"))))

;;;; haystack--volume-gate

(ert-deftest haystack-test/volume-gate-no-prompt-under-threshold ()
  "Does not prompt when total lines < 500."
  ;; 10 files × 49 lines = 490 < 500
  (let ((out (mapconcat (lambda (i) (format "/notes/f%d.org:49" i))
                        (number-sequence 1 10) "\n")))
    (cl-letf (((symbol-function 'yes-or-no-p)
               (lambda (&rest _) (error "Should not have prompted"))))
      (should-not (haystack--volume-gate out)))))

(ert-deftest haystack-test/volume-gate-prompts-at-threshold ()
  "Prompts when total = 500."
  (let ((prompted nil))
    (cl-letf (((symbol-function 'yes-or-no-p)
               (lambda (&rest _) (setq prompted t) t)))
      (haystack--volume-gate "/notes/f.org:500\n"))
    (should prompted)))

(ert-deftest haystack-test/volume-gate-user-approves ()
  "Returns normally when user confirms."
  (cl-letf (((symbol-function 'yes-or-no-p) (lambda (&rest _) t)))
    (should-not (haystack--volume-gate "/notes/f.org:501\n"))))

(ert-deftest haystack-test/volume-gate-user-declines ()
  "Signals user-error when user declines."
  (cl-letf (((symbol-function 'yes-or-no-p) (lambda (&rest _) nil)))
    (should-error (haystack--volume-gate "/notes/f.org:501\n") :type 'user-error)))

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
                  (haystack--search-in-filelist "\\$100" tmp 'all)))
       (delete-file tmp)))))

(ert-deftest haystack-test/xargs-rg-shell-metacharacters-literal ()
  "Patterns containing & | ; are passed through without shell interpretation."
  (haystack-test--with-notes-dir
   (let* ((note (expand-file-name "test.org" haystack-notes-directory))
          (tmp  (progn (with-temp-file note (insert "foo & bar | baz\n"))
                       (haystack--write-filelist (list note)))))
     (unwind-protect
         (should (string-match-p "foo & bar"
                  (haystack--search-in-filelist "foo & bar" tmp 'all)))
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
             ((symbol-function 'switch-to-buffer) #'ignore)
             ((symbol-function 'haystack--stop-word-p) (lambda (_) nil)))
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

(ert-deftest haystack-test/filter-further-volume-gate-prompts ()
  "Prompts when a content filter would return >= 500 lines."
  (haystack-test--with-notes-dir
   (let ((note (expand-file-name "big.org" haystack-notes-directory)))
     (with-temp-file note
       (insert (mapconcat (lambda (_) "rust hit\n") (make-list 500 nil) ""))))
   (let ((prompted nil))
     (cl-letf (((symbol-function 'pop-to-buffer)    #'ignore)
               ((symbol-function 'switch-to-buffer) #'ignore)
               ;; let the root search volume gate pass silently
               ((symbol-function 'yes-or-no-p) (lambda (&rest _) t)))
       (haystack-run-root-search "rust")
       (let ((root-buf (get-buffer "*haystack:1:rust*")))
         (unwind-protect
             (with-current-buffer root-buf
               (setq prompted nil)
               (cl-letf (((symbol-function 'yes-or-no-p)
                          (lambda (&rest _) (setq prompted t) t)))
                 (haystack-filter-further "hit"))
               (should prompted))
           (kill-buffer root-buf)
           (when (get-buffer "*haystack:2:rust:hit*")
             (kill-buffer (get-buffer "*haystack:2:rust:hit*")))))))))

(ert-deftest haystack-test/filter-further-volume-gate-cancels ()
  "Signals user-error when user declines at the filter volume gate."
  (haystack-test--with-notes-dir
   (let ((note (expand-file-name "big.org" haystack-notes-directory)))
     (with-temp-file note
       (insert (mapconcat (lambda (_) "rust hit\n") (make-list 500 nil) ""))))
   (cl-letf (((symbol-function 'pop-to-buffer)    #'ignore)
             ((symbol-function 'switch-to-buffer) #'ignore)
             ((symbol-function 'yes-or-no-p)      (lambda (&rest _) t)))
     (haystack-run-root-search "rust")
     (let ((root-buf (get-buffer "*haystack:1:rust*")))
       (unwind-protect
           (with-current-buffer root-buf
             (cl-letf (((symbol-function 'yes-or-no-p) (lambda (&rest _) nil)))
               (should-error (haystack-filter-further "hit") :type 'user-error)))
         (kill-buffer root-buf))))))

;;;; haystack--parse-and-tokens

(ert-deftest haystack-test/parse-and-tokens-returns-nil-without-ampersand ()
  "Returns nil when input contains no ' & '."
  (should-not (haystack--parse-and-tokens "rust"))
  (should-not (haystack--parse-and-tokens "rust async"))
  (should-not (haystack--parse-and-tokens "rust&async")))

(ert-deftest haystack-test/parse-and-tokens-splits-on-spaced-ampersand ()
  "Splits on ' & ' and returns a list of trimmed tokens."
  (should (equal (haystack--parse-and-tokens "rust & async")
                 '("rust" "async"))))

(ert-deftest haystack-test/parse-and-tokens-three-terms ()
  "Works with three or more terms."
  (should (equal (haystack--parse-and-tokens "rust & async & tokio")
                 '("rust" "async" "tokio"))))

(ert-deftest haystack-test/parse-and-tokens-preserves-prefixes ()
  "Prefix characters on tokens are preserved in the returned list."
  (should (equal (haystack--parse-and-tokens "=rust & ~async")
                 '("=rust" "~async"))))

(ert-deftest haystack-test/parse-and-tokens-returns-nil-for-single-token ()
  "Returns nil when splitting produces fewer than two non-empty tokens."
  (should-not (haystack--parse-and-tokens " & "))
  (should-not (haystack--parse-and-tokens "rust & ")))

;;;; haystack--run-and-query

(ert-deftest haystack-test/run-and-query-intersection ()
  "Returns content matches for the first term only in files matching all terms."
  (haystack-test--with-notes-dir
   (let ((both  (expand-file-name "both.org"  haystack-notes-directory))
         (only1 (expand-file-name "only1.org" haystack-notes-directory)))
     ;; both.org has rust and async; only1.org has rust but not async
     (with-temp-file both  (insert "rust is fast\nasync fn main() {}\n"))
     (with-temp-file only1 (insert "rust is great\n"))
     (let ((out (haystack--run-and-query '("rust" "async") 'all)))
       ;; Should contain both.org (has both terms)
       (should (string-match-p "both\\.org" out))
       ;; Should show first-term (rust) matches, not async lines
       (should (string-match-p "rust is fast" out))
       ;; Should NOT contain only1.org (has rust but not async)
       (should-not (string-match-p "only1\\.org" out))))))

(ert-deftest haystack-test/run-and-query-no-intersection ()
  "Returns empty string when no files match all terms."
  (haystack-test--with-notes-dir
   (let ((note (expand-file-name "note.org" haystack-notes-directory)))
     (with-temp-file note (insert "rust is fast\n"))
     (should (string-empty-p
              (haystack--run-and-query '("rust" "nomatchxyz99") 'all))))))

(ert-deftest haystack-test/run-and-query-three-terms ()
  "File must match all three terms to appear in results."
  (haystack-test--with-notes-dir
   (let ((all3  (expand-file-name "all3.org"  haystack-notes-directory))
         (only2 (expand-file-name "only2.org" haystack-notes-directory)))
     (with-temp-file all3  (insert "rust async tokio\n"))
     (with-temp-file only2 (insert "rust async\n"))
     (let ((out (haystack--run-and-query '("rust" "async" "tokio") 'all)))
       (should     (string-match-p "all3\\.org"  out))
       (should-not (string-match-p "only2\\.org" out))))))

(ert-deftest haystack-test/run-and-query-negation-errors ()
  "Signals user-error when any token carries the ! negation prefix."
  (haystack-test--with-notes-dir
   (let ((note (expand-file-name "note.org" haystack-notes-directory)))
     (with-temp-file note (insert "rust\n"))
     (should-error
      (haystack--run-and-query '("rust" "!async") 'all)
      :type 'user-error))))

(ert-deftest haystack-test/run-and-query-gate-on-intersection-not-first-term ()
  "Volume gate fires based on the AND intersection count, not the first term alone.
11 files × 50 rust lines = 550 (above 500 threshold).  Only one file also
has async, so the intersection count is 50 (below threshold) — no prompt."
  (haystack-test--with-notes-dir
   ;; Create 11 files each with 50 'rust' lines — first term alone exceeds gate.
   (dotimes (i 11)
     (with-temp-file (expand-file-name (format "note%d.org" i) haystack-notes-directory)
       (insert (mapconcat #'identity (make-list 50 "rust mention") "\n"))))
   ;; One file also contains 'async' — intersection is just that file (50 lines < 500).
   (with-temp-file (expand-file-name "note0.org" haystack-notes-directory)
     (insert (concat (mapconcat #'identity (make-list 50 "rust mention") "\n")
                     "\nasync fn here\n")))
   (cl-letf (((symbol-function 'yes-or-no-p)
              (lambda (&rest _) (error "Gate should not have fired on intersection"))))
     (haystack--run-and-query '("rust" "async") 'all))))

(ert-deftest haystack-test/run-and-query-special-chars-auto-quoted ()
  "AND query tokens with regex metacharacters are regexp-quoted by default.
C++ without = prefix should not cause an rg error — the + chars are escaped."
  (haystack-test--with-notes-dir
   (let ((note (expand-file-name "cplusplus.org" haystack-notes-directory)))
     (with-temp-file note (insert "C++ is a language\nfoo bar baz\n"))
     ;; Should succeed without error and find the file.
     (let ((out (haystack--run-and-query '("C++" "foo") 'all)))
       (should (string-match-p "cplusplus\\.org" out))))))

(ert-deftest haystack-test/run-and-query-regex-prefix-not-quoted ()
  "AND query tokens with ~ prefix are passed as raw regex, not escaped."
  (haystack-test--with-notes-dir
   (let ((note (expand-file-name "regex-note.org" haystack-notes-directory)))
     (with-temp-file note (insert "Cargo is great\nfoo bar baz\n"))
     ;; ~C.+ matches "Cargo" via raw regex; foo matches the second line.
     (let ((out (haystack--run-and-query '("~C.+" "foo") 'all)))
       (should (string-match-p "regex-note\\.org" out))))))

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

(ert-deftest haystack-test/run-root-search-volume-gate-prompts ()
  "Prompts when rg --count returns >= 500 total lines."
  (haystack-test--with-notes-dir
   (let ((note (expand-file-name "big.org" haystack-notes-directory)))
     (with-temp-file note
       (insert (mapconcat (lambda (_) "hit\n") (make-list 500 nil) ""))))
   (let ((prompted nil))
     (cl-letf (((symbol-function 'pop-to-buffer) #'ignore)
               ((symbol-function 'yes-or-no-p)
                (lambda (&rest _) (setq prompted t) t)))
       (haystack-run-root-search "hit")
       (should prompted)
       (when (get-buffer "*haystack:1:hit*")
         (kill-buffer (get-buffer "*haystack:1:hit*")))))))

(ert-deftest haystack-test/run-root-search-volume-gate-cancels ()
  "Signals user-error when user declines at the volume gate."
  (haystack-test--with-notes-dir
   (let ((note (expand-file-name "big.org" haystack-notes-directory)))
     (with-temp-file note
       (insert (mapconcat (lambda (_) "hit\n") (make-list 500 nil) ""))))
   (cl-letf (((symbol-function 'pop-to-buffer) #'ignore)
             ((symbol-function 'yes-or-no-p)   (lambda (&rest _) nil)))
     (should-error (haystack-run-root-search "hit") :type 'user-error))))

(ert-deftest haystack-test/run-root-search-volume-gate-no-prompt-under-threshold ()
  "Does not prompt when total lines < 500."
  (haystack-test--with-notes-dir
   (let ((note (expand-file-name "small.org" haystack-notes-directory)))
     (with-temp-file note (insert "hit\nhit\n")))
   (cl-letf (((symbol-function 'pop-to-buffer) #'ignore)
             ((symbol-function 'yes-or-no-p)
              (lambda (&rest _) (error "Should not have prompted"))))
     (haystack-run-root-search "hit")
     (when (get-buffer "*haystack:1:hit*")
       (kill-buffer (get-buffer "*haystack:1:hit*"))))))

;;;; haystack-run-root-search AND queries

(ert-deftest haystack-test/run-root-search-and-creates-buffer ()
  "An & query creates a buffer named after all terms joined with &."
  (haystack-test--with-notes-dir
   (let ((note (expand-file-name "note.org" haystack-notes-directory)))
     (with-temp-file note (insert "rust async\n"))
     (cl-letf (((symbol-function 'pop-to-buffer) #'ignore))
       (haystack-run-root-search "rust & async")
       (let ((buf (get-buffer "*haystack:1:rust&async*")))
         (should buf)
         (unwind-protect
             (with-current-buffer buf
               (should (string-match-p "root=rust & async" (buffer-string))))
           (kill-buffer buf)))))))

(ert-deftest haystack-test/run-root-search-and-descriptor ()
  "AND query descriptor stores joined root-term and first token's pattern."
  (haystack-test--with-notes-dir
   (let ((note (expand-file-name "note.org" haystack-notes-directory)))
     (with-temp-file note (insert "rust async\n"))
     (cl-letf (((symbol-function 'pop-to-buffer) #'ignore))
       (haystack-run-root-search "rust & async")
       (let ((buf (get-buffer "*haystack:1:rust&async*")))
         (should buf)
         (unwind-protect
             (with-current-buffer buf
               ;; root-term stores stripped-first & raw-rest for frecency replay
               (should (equal (plist-get haystack--search-descriptor :root-term)
                              "rust & async"))
               ;; root-expanded is the first token's rg pattern
               (should (equal (plist-get haystack--search-descriptor :root-expanded)
                              "rust"))
               (should (null haystack--parent-buffer)))
           (kill-buffer buf)))))))

(ert-deftest haystack-test/run-root-search-and-intersection ()
  "AND query result contains only files matching all terms."
  (haystack-test--with-notes-dir
   (let ((both  (expand-file-name "both.org"  haystack-notes-directory))
         (only1 (expand-file-name "only1.org" haystack-notes-directory)))
     (with-temp-file both  (insert "rust async\n"))
     (with-temp-file only1 (insert "rust only\n"))
     (cl-letf (((symbol-function 'pop-to-buffer) #'ignore))
       (haystack-run-root-search "rust & async")
       (let ((buf (get-buffer "*haystack:1:rust&async*")))
         (should buf)
         (unwind-protect
             (with-current-buffer buf
               (should     (string-match-p "both\\.org"  (buffer-string)))
               (should-not (string-match-p "only1\\.org" (buffer-string))))
           (kill-buffer buf)))))))

;;;; haystack-run-root-search composite filter via prefix arg

(ert-deftest haystack-test/run-root-search-prefix-arg-passes-all ()
  "C-u prefix arg causes composite-filter 'all in the stored descriptor."
  (haystack-test--with-notes-dir
   (let ((current-prefix-arg '(4)))
     (cl-letf (((symbol-function 'pop-to-buffer) #'ignore)
               ((symbol-function 'read-string) (lambda (&rest _) "nomatchzq")))
       (call-interactively #'haystack-run-root-search)
       (let ((buf (get-buffer "*haystack:1:nomatchzq*")))
         (should buf)
         (unwind-protect
             (with-current-buffer buf
               (should (eq (plist-get haystack--search-descriptor :composite-filter)
                           'all)))
           (kill-buffer buf)))))))

(ert-deftest haystack-test/run-root-search-no-prefix-arg-excludes ()
  "No prefix arg leaves composite-filter as 'exclude."
  (haystack-test--with-notes-dir
   (let ((current-prefix-arg nil))
     (cl-letf (((symbol-function 'pop-to-buffer) #'ignore))
       (haystack-run-root-search "nomatchzz")
       (let ((buf (get-buffer "*haystack:1:nomatchzz*")))
         (should buf)
         (unwind-protect
             (with-current-buffer buf
               (should (eq (plist-get haystack--search-descriptor :composite-filter)
                           'exclude)))
           (kill-buffer buf)))))))

(ert-deftest haystack-test/run-root-search-all-includes-composites ()
  "With composite-filter 'all, composite @* files appear in results."
  (haystack-test--with-notes-dir
   (with-temp-file (expand-file-name "@comp__rust.org" haystack-notes-directory)
     (insert "rust is fast\n"))
   (cl-letf (((symbol-function 'pop-to-buffer) #'ignore))
     (haystack-run-root-search "rust" 'all)
     (let ((buf (get-buffer "*haystack:1:rust*")))
       (should buf)
       (unwind-protect
           (with-current-buffer buf
             (should (string-match-p "@comp__rust\\.org" (buffer-string))))
         (kill-buffer buf))))))

;;;; haystack-search-composites

(ert-deftest haystack-test/search-composites-uses-only-filter ()
  "haystack-search-composites sets composite-filter to 'only."
  (haystack-test--with-notes-dir
   (cl-letf (((symbol-function 'pop-to-buffer) #'ignore))
     (haystack-search-composites "rust")
     (let ((buf (get-buffer "*haystack:1:rust*")))
       (should buf)
       (unwind-protect
           (with-current-buffer buf
             (should (eq (plist-get haystack--search-descriptor :composite-filter)
                         'only)))
         (kill-buffer buf))))))

(ert-deftest haystack-test/search-composites-excludes-regular-notes ()
  "haystack-search-composites returns composites but not regular notes."
  (haystack-test--with-notes-dir
   (with-temp-file (expand-file-name "note.org" haystack-notes-directory)
     (insert "rust is fast\n"))
   (with-temp-file (expand-file-name "@comp__rust.org" haystack-notes-directory)
     (insert "rust is fast\n"))
   (cl-letf (((symbol-function 'pop-to-buffer) #'ignore))
     (haystack-search-composites "rust")
     (let ((buf (get-buffer "*haystack:1:rust*")))
       (should buf)
       (unwind-protect
           (with-current-buffer buf
             (should     (string-match-p "@comp__rust\\.org" (buffer-string)))
             (should-not (string-match-p "\\bnote\\.org\\b" (buffer-string))))
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

;;;; haystack--format-moc-text

(ert-deftest haystack-test/format-moc-text-org ()
  "org extension produces org-link lines joined by newlines."
  (let ((loci '(("/notes/20240101000000-rust.org" . 3)
                ("/notes/20240101000000-async.org" . 7))))
    (should (equal (haystack--format-moc-text loci "root=rust" "org")
                   (concat "[[file:/notes/20240101000000-rust.org::3][rust]]\n"
                           "[[file:/notes/20240101000000-async.org::7][async]]")))))

(ert-deftest haystack-test/format-moc-text-markdown ()
  "md extension produces markdown-link lines."
  (let ((loci '(("/notes/20240101000000-rust.org" . 5))))
    (should (equal (haystack--format-moc-text loci "root=rust" "md")
                   "[rust](/notes/20240101000000-rust.org#L5)"))))

(ert-deftest haystack-test/format-moc-text-code-comment-style ()
  "code extension with comment style produces comment lines."
  (let ((loci '(("/notes/20240101000000-rust.el" . 2)))
        (haystack-moc-code-style 'comment))
    (should (equal (haystack--format-moc-text loci "root=rust" "el")
                   ";; rust — /notes/20240101000000-rust.el"))))

(ert-deftest haystack-test/format-moc-text-code-data-style ()
  "code extension with data style produces a data block, not comment lines."
  (let ((loci '(("/notes/20240101000000-rust.el" . 2)))
        (haystack-moc-code-style 'data))
    (let ((result (haystack--format-moc-text loci "root=rust" "el")))
      (should (string-match-p "(defvar haystack" result))
      (should (string-match-p ":line 2" result)))))

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

;;;; haystack--help-content layout

(defun haystack-test--all-commands-present (content)
  "Return t if CONTENT contains a description for every results-mode command."
  (cl-every (lambda (desc)
               (string-match-p (regexp-quote desc) content))
             '("visit file"
               "next match"
               "previous match"
               "filter further"
               "show tree"
               "go up"
               "go down"
               "kill node"
               "kill subtree"
               "kill whole tree"
               "copy moc"
               "new note"
               "compose")))

(ert-deftest haystack-test/help-content-single-col-has-all-commands ()
  "Narrow width produces single-column content containing all commands."
  (let ((content (haystack--help-content 80)))
    (should (haystack-test--all-commands-present content))))

(ert-deftest haystack-test/help-content-two-col-has-all-commands ()
  "Wide width produces two-column content still containing all commands."
  (let ((content (haystack--help-content 120)))
    (should (haystack-test--all-commands-present content))))

(ert-deftest haystack-test/help-content-two-col-is-shorter ()
  "Two-column layout produces fewer lines than single-column."
  (let ((single (haystack--help-content 80))
        (two    (haystack--help-content 120)))
    (should (< (length (split-string two "\n"))
               (length (split-string single "\n"))))))

(ert-deftest haystack-test/help-content-threshold-is-100 ()
  "Width 99 gives single-column; width 100 gives two-column."
  (let ((at-99  (haystack--help-content 99))
        (at-100 (haystack--help-content 100)))
    (should (< (length (split-string at-100 "\n"))
               (length (split-string at-99  "\n"))))))

(ert-deftest haystack-test/help-content-rule-has-shadow-face ()
  "Rule lines carry the shadow face."
  (let* ((content (haystack--help-content 80))
         (pos     0))  ; rule is the very first character
    (should (eq (get-text-property pos 'face content) 'shadow))))

(ert-deftest haystack-test/help-content-section-header-has-keyword-face ()
  "Section header lines carry font-lock-keyword-face."
  (let* ((content (haystack--help-content 80))
         (pos     (string-search ";;;;  Navigation" content)))
    (should (eq (get-text-property pos 'face content) 'font-lock-keyword-face))))

(ert-deftest haystack-test/help-content-key-has-constant-face ()
  "The key portion of each entry carries font-lock-constant-face."
  (let* ((content (haystack--help-content 80))
         ;; Find the key for haystack-next-match ("n") and check its face.
         ;; The entry looks like: ";;;;    n          next match"
         ;; Locate "n " after the indent prefix and check the face there.
         (entry-pos (string-search "next match" content))
         ;; Step back past "  " separator and the padded key field to find
         ;; the start of the key; the key field is %-9s so step back 11.
         (key-pos   (- entry-pos 11)))
    (should (eq (get-text-property key-pos 'face content) 'font-lock-constant-face))))

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

;;;; haystack--frecency-ensure

(ert-deftest haystack-test/frecency-ensure-sets-initialized-flag ()
  "`haystack--frecency-ensure' sets `haystack--frecency-initialized' to t."
  (let ((haystack--frecency-initialized nil))
    (cl-letf (((symbol-function 'haystack--frecency-setup-timer) #'ignore))
      (haystack--frecency-ensure)
      (should haystack--frecency-initialized))))

(ert-deftest haystack-test/frecency-ensure-is-idempotent ()
  "`haystack--frecency-ensure' calls setup exactly once even when invoked twice."
  (let ((haystack--frecency-initialized nil)
        (call-count 0))
    (cl-letf (((symbol-function 'haystack--frecency-setup-timer)
               (lambda () (cl-incf call-count))))
      (haystack--frecency-ensure)
      (haystack--frecency-ensure)
      (should (= call-count 1)))))

(ert-deftest haystack-test/frecency-ensure-skips-when-already-initialized ()
  "`haystack--frecency-ensure' does not call setup when already initialized."
  (let ((haystack--frecency-initialized t)
        (called nil))
    (cl-letf (((symbol-function 'haystack--frecency-setup-timer)
               (lambda () (setq called t))))
      (haystack--frecency-ensure)
      (should-not called))))

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
             (insert "#+TITLE: Sample\n#+DATE: 2025-01-01\n# %%% haystack-end-frontmatter %%%\n\nSample note.\n"))
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

;;;; Composite surfacing in buffer headers

(ert-deftest haystack-test/format-header-no-composite-line-when-absent ()
  "format-header without a composite-path has no composite line."
  (let ((h (haystack--format-header "root=rust" 3 10)))
    (should-not (string-match-p "composite" h))))

(ert-deftest haystack-test/format-header-shows-composite-line ()
  "format-header with a composite-path includes a [composite:…] line."
  (let ((h (haystack--format-header "root=rust" 3 10 "/notes/@comp__rust.org")))
    (should (string-match-p "composite.*@comp__rust\\.org" h))))

(ert-deftest haystack-test/run-root-search-surfaces-composite ()
  "Root search header shows composite line when a composite file exists."
  (haystack-test--with-notes-dir
   (with-temp-file (expand-file-name "note.org" haystack-notes-directory)
     (insert "rust is fast\n"))
   ;; Pre-create the composite file for this chain.
   (with-temp-file (expand-file-name "@comp__rust.org" haystack-notes-directory)
     (insert "#+HAYSTACK-CHAIN: rust\n"))
   (cl-letf (((symbol-function 'pop-to-buffer) #'ignore))
     (haystack-run-root-search "rust"))
   (let ((buf (get-buffer "*haystack:1:rust*")))
     (should buf)
     (unwind-protect
         (with-current-buffer buf
           (should (string-match-p "composite.*@comp__rust\\.org"
                                   (buffer-string))))
       (kill-buffer buf)))))

(ert-deftest haystack-test/filter-further-surfaces-composite ()
  "Filter-further header shows composite line when composite exists."
  (haystack-test--with-notes-dir
   (with-temp-file (expand-file-name "note.org" haystack-notes-directory)
     (insert "rust async\n"))
   (with-temp-file (expand-file-name "@comp__rust__async.org" haystack-notes-directory)
     (insert "#+HAYSTACK-CHAIN: rust__async\n"))
   (cl-letf (((symbol-function 'pop-to-buffer) #'ignore)
             ((symbol-function 'switch-to-buffer) #'ignore))
     (haystack-run-root-search "rust")
     (let ((root-buf (get-buffer "*haystack:1:rust*")))
       (with-current-buffer root-buf
         (haystack-filter-further "async"))
       (let ((child-buf (get-buffer "*haystack:2:rust:async*")))
         (should child-buf)
         (unwind-protect
             (with-current-buffer child-buf
               (should (string-match-p "composite.*@comp__rust__async\\.org"
                                       (buffer-string))))
           (kill-buffer root-buf)
           (when (buffer-live-p child-buf) (kill-buffer child-buf))))))))

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

;;;; haystack-compose-commit / haystack-compose-discard

(defmacro haystack-test--with-compose-committed (&rest body)
  "Set up notes dir + results buffer + compose buffer, call commit, run BODY."
  (declare (indent 0))
  `(haystack-test--with-notes-dir
    (with-temp-file (expand-file-name "note.org" haystack-notes-directory)
      (insert "hello world\n"))
    (cl-letf (((symbol-function 'pop-to-buffer) #'ignore))
      (haystack-run-root-search "hello"))
    (let* ((results-buf (get-buffer "*haystack:1:hello*"))
           (compose-buf (with-current-buffer results-buf (haystack-compose))))
      (unwind-protect
          (with-current-buffer compose-buf
            ,@body)
        (when (buffer-live-p results-buf) (kill-buffer results-buf))
        (when (buffer-live-p compose-buf) (kill-buffer compose-buf))))))

(ert-deftest haystack-test/compose-commit-writes-file ()
  "C-c C-c writes @comp__CHAIN.org to the notes directory."
  (haystack-test--with-compose-committed
   (cl-letf (((symbol-function 'y-or-n-p) (lambda (&rest _) t)))
     (haystack-compose-commit))
   (should (file-exists-p
            (expand-file-name "@comp__hello.org" haystack-notes-directory)))))

(ert-deftest haystack-test/compose-commit-file-has-frontmatter ()
  "Written composite file contains HAYSTACK-CHAIN org property."
  (haystack-test--with-compose-committed
   (cl-letf (((symbol-function 'y-or-n-p) (lambda (&rest _) t)))
     (haystack-compose-commit))
   (let* ((path (expand-file-name "@comp__hello.org" haystack-notes-directory))
          (content (with-temp-buffer (insert-file-contents path) (buffer-string))))
     (should (string-match-p "HAYSTACK-CHAIN.*hello" content)))))

(ert-deftest haystack-test/compose-commit-file-has-source-section ()
  "Written composite file contains the source file heading."
  (haystack-test--with-compose-committed
   (cl-letf (((symbol-function 'y-or-n-p) (lambda (&rest _) t)))
     (haystack-compose-commit))
   (let* ((path (expand-file-name "@comp__hello.org" haystack-notes-directory))
          (content (with-temp-buffer (insert-file-contents path) (buffer-string))))
     (should (string-match-p "\\* \\[\\[file:" content)))))

(ert-deftest haystack-test/compose-commit-unmodified-no-note-prompt ()
  "Unmodified buffer does not prompt to save as a new note."
  (haystack-test--with-compose-committed
   ;; Buffer is unmodified after setup — the note prompt should never fire.
   (cl-letf (((symbol-function 'y-or-n-p)
              (lambda (prompt &rest _)
                (if (string-match-p "new note" prompt)
                    (error "Should not have prompted for new note")
                  t))))  ; answer yes to any overwrite prompt
     (haystack-compose-commit))
   (should t)))  ; reaches here ⇒ no note prompt fired

(ert-deftest haystack-test/compose-commit-modified-prompts-for-note ()
  "Modified buffer prompts to save as a new note after writing composite."
  (haystack-test--with-compose-committed
   (goto-char (point-max))
   (insert "my annotation\n")   ; makes buffer-modified-p t
   (let ((prompted nil))
     (cl-letf (((symbol-function 'y-or-n-p)
                (lambda (prompt &rest _)
                  (when (string-match-p "new note" prompt)
                    (setq prompted t))
                  nil))  ; answer no to avoid actually creating a note
               ((symbol-function 'haystack-new-note) #'ignore))
       (haystack-compose-commit))
     (should prompted))))

(ert-deftest haystack-test/compose-discard-kills-buffer ()
  "C-c C-k kills the compose buffer without writing."
  (haystack-test--with-notes-dir
   (with-temp-file (expand-file-name "note.org" haystack-notes-directory)
     (insert "hello world\n"))
   (cl-letf (((symbol-function 'pop-to-buffer) #'ignore))
     (haystack-run-root-search "hello"))
   (let* ((results-buf (get-buffer "*haystack:1:hello*"))
          (compose-buf (with-current-buffer results-buf (haystack-compose))))
     (unwind-protect
         (progn
           (with-current-buffer compose-buf
             (haystack-compose-discard))
           (should-not (buffer-live-p compose-buf)))
       (when (buffer-live-p results-buf) (kill-buffer results-buf))
       (when (buffer-live-p compose-buf) (kill-buffer compose-buf))))))

(ert-deftest haystack-test/compose-intercept-save-protect-on ()
  "When `haystack-composite-protect' is t, write-contents-functions intercepts save."
  (haystack-test--with-notes-dir
   (with-temp-file (expand-file-name "note.org" haystack-notes-directory)
     (insert "hello world\n"))
   (cl-letf (((symbol-function 'pop-to-buffer) #'ignore))
     (haystack-run-root-search "hello"))
   (let* ((results-buf (get-buffer "*haystack:1:hello*"))
          (haystack-composite-protect t)
          (compose-buf (with-current-buffer results-buf (haystack-compose)))
          (intercepted nil))
     (unwind-protect
         (with-current-buffer compose-buf
           (cl-letf (((symbol-function 'y-or-n-p)
                      (lambda (&rest _) (setq intercepted t) nil))
                     ((symbol-function 'haystack-new-note) #'ignore))
             (run-hook-with-args-until-success 'write-contents-functions))
           (should intercepted))
       (when (buffer-live-p results-buf) (kill-buffer results-buf))
       (when (buffer-live-p compose-buf) (kill-buffer compose-buf))))))

(ert-deftest haystack-test/compose-intercept-save-protect-off ()
  "When `haystack-composite-protect' is nil, write-contents-functions does not intercept."
  (haystack-test--with-notes-dir
   (with-temp-file (expand-file-name "note.org" haystack-notes-directory)
     (insert "hello world\n"))
   (cl-letf (((symbol-function 'pop-to-buffer) #'ignore))
     (haystack-run-root-search "hello"))
   (let* ((results-buf (get-buffer "*haystack:1:hello*"))
          (haystack-composite-protect nil)
          (compose-buf (with-current-buffer results-buf (haystack-compose))))
     (unwind-protect
         (with-current-buffer compose-buf
           (should-not
            (run-hook-with-args-until-success 'write-contents-functions)))
       (when (buffer-live-p results-buf) (kill-buffer results-buf))
       (when (buffer-live-p compose-buf) (kill-buffer compose-buf))))))

;;;; haystack-compose

(defmacro haystack-test--with-compose-buffer (notes-body &rest body)
  "Set up a notes dir, a root-search results buffer, run NOTES-BODY to
populate the notes, then evaluate BODY with the compose buffer active.
Cleans up both the results buffer and the compose buffer."
  (declare (indent 1))
  `(haystack-test--with-notes-dir
    (progn
      ,notes-body
      (cl-letf (((symbol-function 'pop-to-buffer) #'ignore))
        (haystack-run-root-search "hello"))
      (let* ((results-buf (get-buffer "*haystack:1:hello*"))
             (compose-buf nil))
        (unwind-protect
            (progn
              (with-current-buffer results-buf
                (setq compose-buf (haystack-compose)))
              (with-current-buffer compose-buf
                ,@body))
          (when (buffer-live-p results-buf)  (kill-buffer results-buf))
          (when (buffer-live-p compose-buf)  (kill-buffer compose-buf)))))))

(ert-deftest haystack-test/compose-errors-outside-results-buffer ()
  "Signals user-error when called outside a haystack results buffer."
  (should-error (haystack-compose) :type 'user-error))

(ert-deftest haystack-test/compose-creates-buffer ()
  "Creates a *haystack-compose:CHAIN* buffer."
  (haystack-test--with-notes-dir
   (with-temp-file (expand-file-name "note.org" haystack-notes-directory)
     (insert "hello world\n"))
   (cl-letf (((symbol-function 'pop-to-buffer) #'ignore))
     (haystack-run-root-search "hello"))
   (let ((results-buf (get-buffer "*haystack:1:hello*")))
     (unwind-protect
         (let ((compose-buf (with-current-buffer results-buf
                              (haystack-compose))))
           (unwind-protect
               (should (buffer-live-p compose-buf))
             (kill-buffer compose-buf)))
       (kill-buffer results-buf)))))

(ert-deftest haystack-test/compose-buffer-contains-source-heading ()
  "Compose buffer has an org heading linking to each source file."
  (haystack-test--with-compose-buffer
   (with-temp-file (expand-file-name "20240101000000-my-note.org"
                                     haystack-notes-directory)
     (insert "hello world\n"))
   (should (string-match-p "\\* \\[\\[file:.*my-note" (buffer-string)))
   (should (string-match-p "hello world" (buffer-string)))))

(ert-deftest haystack-test/compose-buffer-title-in-header ()
  "Compose buffer header contains the search chain."
  (haystack-test--with-compose-buffer
   (with-temp-file (expand-file-name "note.org" haystack-notes-directory)
     (insert "hello world\n"))
   (should (string-match-p "hello" (buffer-string)))))

(ert-deftest haystack-test/compose-all-matches-multiple-sections ()
  "With `haystack-composite-all-matches' t, one section per match line."
  (haystack-test--with-notes-dir
   (with-temp-file (expand-file-name "note.org" haystack-notes-directory)
     (insert "hello one\nhello two\nhello three\n"))
   (cl-letf (((symbol-function 'pop-to-buffer) #'ignore))
     (haystack-run-root-search "hello"))
   (let* ((results-buf (get-buffer "*haystack:1:hello*"))
          (haystack-composite-all-matches t)
          (compose-buf (with-current-buffer results-buf (haystack-compose))))
     (unwind-protect
         ;; Three matches → three headings
         (with-current-buffer compose-buf
           (should (= (cl-count-if (lambda (l) (string-prefix-p "* " l))
                                   (split-string (buffer-string) "\n"))
                      3)))
       (kill-buffer results-buf)
       (kill-buffer compose-buf)))))

;;;; haystack--compose-file-section

(ert-deftest haystack-test/compose-file-section-heading ()
  "Section starts with an org heading containing a file link."
  (haystack-test--with-notes-dir
   (let* ((path (expand-file-name "20240101000000-my-note.org"
                                  haystack-notes-directory))
          (_ (with-temp-file path (insert "hello world\n")))
          (section (haystack--compose-file-section path 1)))
     (should (string-match-p "^\\* \\[\\[file:" section))
     (should (string-match-p "my note" section)))))

(ert-deftest haystack-test/compose-file-section-contains-content ()
  "Section body contains the file content."
  (haystack-test--with-notes-dir
   (let* ((path (expand-file-name "note.org" haystack-notes-directory))
          (_ (with-temp-file path (insert "hello world\n")))
          (section (haystack--compose-file-section path 1)))
     (should (string-match-p "hello world" section)))))

(ert-deftest haystack-test/compose-file-section-line-number-in-link ()
  "The org link includes the match line number."
  (haystack-test--with-notes-dir
   (let* ((path (expand-file-name "note.org" haystack-notes-directory))
          (_ (with-temp-file path (insert "line1\nline2\nline3\n")))
          (section (haystack--compose-file-section path 2)))
     (should (string-match-p "::2\\]" section)))))

;;;; haystack--composite-file-content

(ert-deftest haystack-test/composite-file-content-short-file ()
  "Files within the line limit are returned unchanged."
  (let ((lines (mapconcat #'identity (make-list 10 "line") "\n")))
    (should (equal (haystack--composite-file-content lines 1 300)
                   lines))))

(ert-deftest haystack-test/composite-file-content-nil-max ()
  "nil max-lines returns the full content regardless of size."
  (let ((lines (mapconcat (lambda (i) (format "line%d" i))
                          (number-sequence 1 500) "\n")))
    (should (equal (haystack--composite-file-content lines 250 nil)
                   lines))))

(ert-deftest haystack-test/composite-file-content-truncates-long-file ()
  "Files over the limit are windowed around the match line."
  ;; 100 lines, limit 10 → window of 10 lines centred on match
  (let* ((all-lines (mapcar (lambda (i) (format "line%d" i))
                            (number-sequence 1 100)))
         (text      (mapconcat #'identity all-lines "\n"))
         (result    (haystack--composite-file-content text 50 10))
         (result-lines (split-string result "\n" t)))
    ;; Should be capped at 10 lines of content (plus possible ellipsis markers)
    (should (<= (length (cl-remove-if (lambda (l) (string-prefix-p "..." l))
                                      result-lines))
                10))
    ;; Match line content should be present
    (should (string-match-p "line50" result))))

(ert-deftest haystack-test/composite-file-content-ellipsis-markers ()
  "Truncated content gets ellipsis markers at truncated ends."
  (let* ((all-lines (mapcar (lambda (i) (format "line%d" i))
                            (number-sequence 1 100)))
         (text   (mapconcat #'identity all-lines "\n"))
         (result (haystack--composite-file-content text 50 10)))
    (should (string-prefix-p "..." result))
    (should (string-suffix-p "..." result))))

(ert-deftest haystack-test/composite-file-content-no-leading-ellipsis-at-start ()
  "No leading ellipsis when the window starts at line 1."
  (let* ((all-lines (mapcar (lambda (i) (format "line%d" i))
                            (number-sequence 1 100)))
         (text   (mapconcat #'identity all-lines "\n"))
         ;; match at line 2, window of 10 → starts at line 1
         (result (haystack--composite-file-content text 2 10)))
    (should-not (string-prefix-p "..." result))
    (should     (string-suffix-p "..." result))))

;;;; haystack--find-composite

(ert-deftest haystack-test/find-composite-returns-nil-when-absent ()
  "Returns nil when no composite file exists for the descriptor."
  (haystack-test--with-notes-dir
   (let ((desc (list :root-term "rust" :root-literal nil :root-regex nil
                     :root-filename nil :filters nil)))
     (should-not (haystack--find-composite desc)))))

(ert-deftest haystack-test/find-composite-returns-path-when-present ()
  "Returns the absolute path when the composite file exists."
  (haystack-test--with-notes-dir
   (let* ((desc (list :root-term "rust" :root-literal nil :root-regex nil
                      :root-filename nil :filters nil))
          (path (haystack--composite-filename desc)))
     (with-temp-file path (insert "placeholder"))
     (should (equal (haystack--find-composite desc) path)))))

(ert-deftest haystack-test/find-composite-nil-for-different-chain ()
  "Returns nil when a composite exists for a different chain."
  (haystack-test--with-notes-dir
   (let* ((desc-rust  (list :root-term "rust"   :root-literal nil :root-regex nil
                            :root-filename nil :filters nil))
          (desc-async (list :root-term "async"  :root-literal nil :root-regex nil
                            :root-filename nil :filters nil)))
     (with-temp-file (haystack--composite-filename desc-rust) (insert "placeholder"))
     (should-not (haystack--find-composite desc-async)))))

;;;; haystack--composite-filename

(ert-deftest haystack-test/composite-filename-basic ()
  "Returns absolute path @comp__SLUG.org in the notes directory."
  (haystack-test--with-notes-dir
   (let ((desc (list :root-term "rust" :root-literal nil :root-regex nil
                     :root-filename nil :filters nil)))
     (should (equal (haystack--composite-filename desc)
                    (expand-file-name "@comp__rust.org" haystack-notes-directory))))))

(ert-deftest haystack-test/composite-filename-extension-is-always-org ()
  "Composite files always use the .org extension — the format is always org."
  (haystack-test--with-notes-dir
   (let ((desc (list :root-term "rust" :root-literal nil :root-regex nil
                     :root-filename nil :filters nil)))
     (should (string-suffix-p ".org" (haystack--composite-filename desc))))))

(ert-deftest haystack-test/composite-filename-chain-in-name ()
  "Filter terms appear in the filename joined by __."
  (haystack-test--with-notes-dir
   (let ((desc (list :root-term "rust" :root-literal nil :root-regex nil
                     :root-filename nil
                     :filters (list (list :term "async" :negated nil
                                          :filename nil :literal nil :regex nil)))))
     (should (equal (haystack--composite-filename desc)
                    (expand-file-name "@comp__rust__async.org"
                                      haystack-notes-directory))))))

;;;; haystack--canonical-chain-slug

(ert-deftest haystack-test/canonical-chain-slug-single-bare-term ()
  "A single bare term is lowercased and slugified."
  (let ((desc (list :root-term "Rust" :root-literal nil :root-regex nil
                    :root-filename nil :filters nil)))
    (should (equal (haystack--canonical-chain-slug desc) "rust"))))

(ert-deftest haystack-test/canonical-chain-slug-resolves-group-root ()
  "A synonym resolves to its expansion group root."
  (haystack-test--with-groups '(("programming" . ("coding" "scripting")))
    (let ((desc (list :root-term "coding" :root-literal nil :root-regex nil
                      :root-filename nil :filters nil)))
      (should (equal (haystack--canonical-chain-slug desc) "programming")))))

(ert-deftest haystack-test/canonical-chain-slug-with-filters ()
  "Filter terms are appended after the root, joined with __."
  (let ((desc (list :root-term "rust" :root-literal nil :root-regex nil
                    :root-filename nil
                    :filters (list (list :term "async" :negated nil
                                         :filename nil :literal nil :regex nil)
                                   (list :term "tokio" :negated nil
                                         :filename nil :literal nil :regex nil)))))
    (should (equal (haystack--canonical-chain-slug desc) "rust__async__tokio"))))

(ert-deftest haystack-test/canonical-chain-slug-negated-filter ()
  "Negated filter terms are prefixed with not-."
  (let ((desc (list :root-term "rust" :root-literal nil :root-regex nil
                    :root-filename nil
                    :filters (list (list :term "async" :negated t
                                         :filename nil :literal nil :regex nil)))))
    (should (equal (haystack--canonical-chain-slug desc) "rust__not-async"))))

(ert-deftest haystack-test/canonical-chain-slug-filename-filter ()
  "Filename filter terms are prefixed with fn-."
  (let ((desc (list :root-term "rust" :root-literal nil :root-regex nil
                    :root-filename nil
                    :filters (list (list :term "cargo" :negated nil
                                         :filename t :literal nil :regex nil)))))
    (should (equal (haystack--canonical-chain-slug desc) "rust__fn-cargo"))))

(ert-deftest haystack-test/canonical-chain-slug-and-root ()
  "AND root terms are flattened into the slug with __ between them."
  (let ((desc (list :root-term "rust & async" :root-literal nil :root-regex nil
                    :root-filename nil :filters nil)))
    (should (equal (haystack--canonical-chain-slug desc) "rust__async"))))

(ert-deftest haystack-test/canonical-chain-slug-and-root-with-filter ()
  "AND root + filter produces same slug as equivalent sequential filter chain."
  (let ((desc-and (list :root-term "rust & async" :root-literal nil :root-regex nil
                         :root-filename nil
                         :filters (list (list :term "tokio" :negated nil
                                              :filename nil :literal nil :regex nil))))
        (desc-seq (list :root-term "rust" :root-literal nil :root-regex nil
                         :root-filename nil
                         :filters (list (list :term "async" :negated nil
                                              :filename nil :literal nil :regex nil)
                                        (list :term "tokio" :negated nil
                                              :filename nil :literal nil :regex nil)))))
    (should (equal (haystack--canonical-chain-slug desc-and)
                   (haystack--canonical-chain-slug desc-seq)))))

(ert-deftest haystack-test/canonical-chain-slug-multi-word-term ()
  "Multi-word terms have spaces replaced with hyphens."
  (let ((desc (list :root-term "emacs lisp" :root-literal nil :root-regex nil
                    :root-filename nil :filters nil)))
    (should (equal (haystack--canonical-chain-slug desc) "emacs-lisp"))))

(ert-deftest haystack-test/canonical-chain-slug-literal-prefix-stripped ()
  "The = literal prefix on a filter term does not appear in the slug."
  (let ((desc (list :root-term "rust" :root-literal nil :root-regex nil
                    :root-filename nil
                    :filters (list (list :term "async" :negated nil
                                         :filename nil :literal t :regex nil)))))
    (should (equal (haystack--canonical-chain-slug desc) "rust__async"))))

;;;; haystack-new-note-with-moc

(ert-deftest haystack-test/new-note-with-moc-errors-outside-results-buffer ()
  "Signals user-error when called outside a haystack results buffer."
  (with-temp-buffer
    (should-error (haystack-new-note-with-moc) :type 'user-error)))

(ert-deftest haystack-test/new-note-with-moc-errors-on-empty-results ()
  "Signals user-error when the results buffer has no match lines."
  (let ((buf (haystack-test--make-results-buf
              " *hs-nwm-empty*" nil '(:root-term "rust" :filters nil))))
    (unwind-protect
        (with-current-buffer buf
          (should-error (haystack-new-note-with-moc) :type 'user-error))
      (kill-buffer buf))))

(ert-deftest haystack-test/new-note-with-moc-creates-file ()
  "Creates a timestamped note file in the notes directory."
  (haystack-test--with-notes-dir
   (let ((buf (haystack-test--make-results-buf
               " *hs-nwm-creates*" nil '(:root-term "rust" :filters nil))))
     (unwind-protect
         (with-current-buffer buf
           (setq default-directory haystack-notes-directory)
           (insert (concat haystack-notes-directory "/a.org:3:content\n"))
           (cl-letf (((symbol-function 'read-string)
                      (lambda (prompt &rest _)
                        (if (string-match-p "Slug" prompt) "my-note" "org")))
                     ((symbol-function 'find-file) #'ignore))
             (haystack-new-note-with-moc))
           (should (= 1 (length (directory-files
                                 haystack-notes-directory nil
                                 "^[0-9]\\{14\\}-my-note\\.org$")))))
       (kill-buffer buf)))))

(ert-deftest haystack-test/new-note-with-moc-writes-frontmatter ()
  "The created file contains the haystack sentinel."
  (haystack-test--with-notes-dir
   (let ((buf (haystack-test--make-results-buf
               " *hs-nwm-fm*" nil '(:root-term "rust" :filters nil))))
     (unwind-protect
         (with-current-buffer buf
           (setq default-directory haystack-notes-directory)
           (insert (concat haystack-notes-directory "/a.org:3:content\n"))
           (cl-letf (((symbol-function 'read-string)
                      (lambda (prompt &rest _)
                        (if (string-match-p "Slug" prompt) "fm-test" "org")))
                     ((symbol-function 'find-file) #'ignore))
             (haystack-new-note-with-moc))
           (let* ((files (directory-files haystack-notes-directory t
                                          "^[0-9]\\{14\\}-fm-test\\.org$"))
                  (content (with-temp-buffer
                             (insert-file-contents (car files))
                             (buffer-string))))
             (should (haystack-test--has-sentinel content))))
       (kill-buffer buf)))))

(ert-deftest haystack-test/new-note-with-moc-inserts-moc-in-buffer ()
  "The opened buffer contains the MOC text after creation."
  (haystack-test--with-notes-dir
   (let ((buf (haystack-test--make-results-buf
               " *hs-nwm-insert*" nil '(:root-term "rust" :filters nil)))
         opened-buf)
     (unwind-protect
         (with-current-buffer buf
           (setq default-directory haystack-notes-directory)
           (insert (concat haystack-notes-directory
                           "/20240101000000-rust.org:3:content\n"))
           (cl-letf (((symbol-function 'read-string)
                      (lambda (prompt &rest _)
                        (if (string-match-p "Slug" prompt) "moc-insert" "org")))
                     ((symbol-function 'find-file)
                      (lambda (path)
                        (setq opened-buf (find-file-noselect path))
                        (set-buffer opened-buf))))
             (haystack-new-note-with-moc))
           (should (not (null opened-buf)))
           (with-current-buffer opened-buf
             (should (string-match-p "\\[\\[file:.*rust.*::3" (buffer-string)))))
       (kill-buffer buf)
       (when (buffer-live-p opened-buf) (kill-buffer opened-buf))))))

(ert-deftest haystack-test/new-note-with-moc-pushes-to-kill-ring ()
  "MOC text is pushed to the kill ring."
  (haystack-test--with-notes-dir
   (let ((buf (haystack-test--make-results-buf
               " *hs-nwm-kr*" nil '(:root-term "rust" :filters nil))))
     (unwind-protect
         (with-current-buffer buf
           (setq default-directory haystack-notes-directory)
           (insert (concat haystack-notes-directory
                           "/20240101000000-rust.org:3:content\n"))
           (cl-letf (((symbol-function 'read-string)
                      (lambda (prompt &rest _)
                        (if (string-match-p "Slug" prompt) "kr-test" "org")))
                     ((symbol-function 'find-file) #'ignore))
             (haystack-new-note-with-moc))
           (should (string-match-p "\\[\\[file:.*rust.*::3" (car kill-ring))))
       (kill-buffer buf)))))

(ert-deftest haystack-test/new-note-with-moc-updates-last-moc ()
  "Sets haystack--last-moc and haystack--last-moc-chain from the results buffer."
  (haystack-test--with-notes-dir
   (let ((buf (haystack-test--make-results-buf
               " *hs-nwm-state*" nil
               '(:root-term "rust" :root-expansion nil :root-filename nil
                 :filters nil)))
         (haystack--last-moc nil)
         (haystack--last-moc-chain nil))
     (unwind-protect
         (with-current-buffer buf
           (setq default-directory haystack-notes-directory)
           (insert (concat haystack-notes-directory "/a.org:3:content\n"))
           (cl-letf (((symbol-function 'read-string)
                      (lambda (prompt &rest _)
                        (if (string-match-p "Slug" prompt) "state-test" "org")))
                     ((symbol-function 'find-file) #'ignore))
             (haystack-new-note-with-moc))
           (should (not (null haystack--last-moc)))
           (should (equal haystack--last-moc-chain "root=rust")))
       (kill-buffer buf)))))

(ert-deftest haystack-test/new-note-with-moc-runs-after-create-hook ()
  "Runs haystack-after-create-hook after the note is created."
  (haystack-test--with-notes-dir
   (let ((buf (haystack-test--make-results-buf
               " *hs-nwm-hook*" nil '(:root-term "rust" :filters nil)))
         (hook-ran nil))
     (unwind-protect
         (with-current-buffer buf
           (setq default-directory haystack-notes-directory)
           (insert (concat haystack-notes-directory "/a.org:3:content\n"))
           (cl-letf (((symbol-function 'read-string)
                      (lambda (prompt &rest _)
                        (if (string-match-p "Slug" prompt) "hook-test" "org")))
                     ((symbol-function 'find-file) #'ignore))
             (let ((haystack-after-create-hook
                    (list (lambda () (setq hook-ran t)))))
               (haystack-new-note-with-moc)))
           (should hook-ran))
       (kill-buffer buf)))))

;;;; haystack--suppress-display

(ert-deftest haystack-test/suppress-display-default-nil ()
  "`haystack--suppress-display' is nil by default."
  (should (null haystack--suppress-display)))

(ert-deftest haystack-test/suppress-display-root-search-returns-buf ()
  "With suppress-display t, haystack-run-root-search still returns the buffer."
  (haystack-test--with-notes-dir
   (let ((haystack--suppress-display t)
         (pop-to-buffer-called nil))
     (cl-letf (((symbol-function 'pop-to-buffer)
                (lambda (&rest _) (setq pop-to-buffer-called t))))
       (let ((buf (haystack-run-root-search "zzznomatch")))
         (should (bufferp buf))
         (should-not pop-to-buffer-called)
         (when (buffer-live-p buf) (kill-buffer buf)))))))

(ert-deftest haystack-test/suppress-display-root-search-pops-normally ()
  "Without suppress-display, haystack-run-root-search calls pop-to-buffer."
  (haystack-test--with-notes-dir
   (let ((haystack--suppress-display nil)
         (pop-to-buffer-called nil))
     (cl-letf (((symbol-function 'pop-to-buffer)
                (lambda (buf &rest _) (setq pop-to-buffer-called t) buf)))
       (let ((buf (haystack-run-root-search "zzznomatch")))
         (should pop-to-buffer-called)
         (when (buffer-live-p buf) (kill-buffer buf)))))))

(ert-deftest haystack-test/suppress-display-filter-further-returns-buf ()
  "With suppress-display t, haystack-filter-further still returns the buffer."
  (haystack-test--with-notes-dir
   ;; Need a real file so filter-further finds something to narrow.
   (let ((note (expand-file-name "testfile.org" haystack-notes-directory)))
     (with-temp-file note (insert "haystack-suppress-test content here\n"))
     (let ((switch-to-buffer-called nil))
       (cl-letf (((symbol-function 'switch-to-buffer)
                  (lambda (&rest _) (setq switch-to-buffer-called t))))
         (let* ((root-buf
                 (let ((haystack--suppress-display t))
                   (haystack-run-root-search "haystack-suppress-test")))
                (child-buf
                 (let ((haystack--suppress-display t))
                   (with-current-buffer root-buf
                     (haystack-filter-further "content")))))
           (should (bufferp child-buf))
           (should-not switch-to-buffer-called)
           (when (buffer-live-p child-buf) (kill-buffer child-buf))
           (when (buffer-live-p root-buf)  (kill-buffer root-buf))))))))

(ert-deftest haystack-test/suppress-display-replay-no-cl-letf ()
  "haystack--frecency-replay uses suppress-display, not cl-letf."
  ;; After the fix, cl-letf is gone from replay. Verify replay works
  ;; end-to-end and pop-to-buffer is called exactly once (for the leaf).
  (haystack-test--with-notes-dir
   (let ((pop-count 0))
     (cl-letf (((symbol-function 'pop-to-buffer)
                (lambda (buf &rest _) (cl-incf pop-count) buf)))
       (let ((buf (haystack--frecency-replay (list "zzznomatch"))))
         (should (bufferp buf))
         (should (= 1 pop-count))
         (when (buffer-live-p buf) (kill-buffer buf)))))))

;;;; haystack--word-at-point

(ert-deftest haystack-test/word-at-point-plain-word ()
  "Returns the plain word under point."
  (with-temp-buffer
    (insert "hello world")
    (goto-char (point-min))
    (should (equal (haystack--word-at-point) "hello"))))

(ert-deftest haystack-test/word-at-point-hyphenated ()
  "Returns the full hyphenated word under point."
  (with-temp-buffer
    (insert "bevy-ecs patterns")
    (goto-char (point-min))
    (should (equal (haystack--word-at-point) "bevy-ecs"))))

(ert-deftest haystack-test/word-at-point-underscored ()
  "Returns the full underscored word under point."
  (with-temp-buffer
    (insert "my_note here")
    (goto-char (point-min))
    (should (equal (haystack--word-at-point) "my_note"))))

(ert-deftest haystack-test/word-at-point-cursor-mid-word ()
  "Returns the full word even when point is in the middle."
  (with-temp-buffer
    (insert "bevy-ecs")
    (goto-char 4)
    (should (equal (haystack--word-at-point) "bevy-ecs"))))

(ert-deftest haystack-test/word-at-point-on-whitespace-returns-nil ()
  "Returns nil when point is on whitespace."
  (with-temp-buffer
    (insert "hello world")
    (goto-char 6)
    (should (null (haystack--word-at-point)))))

(ert-deftest haystack-test/word-at-point-on-punctuation-returns-nil ()
  "Returns nil when point is on a punctuation character."
  (with-temp-buffer
    (insert "foo.bar")
    (goto-char 4)
    (should (null (haystack--word-at-point)))))

;;;; haystack-run-root-search-at-point

(ert-deftest haystack-test/search-at-point-uses-word-at-point ()
  "Calls haystack-run-root-search with the word under point."
  (haystack-test--with-notes-dir
   (with-temp-buffer
     (insert "rust programming")
     (goto-char (point-min))
     (let ((searched nil))
       (cl-letf (((symbol-function 'haystack-run-root-search)
                  (lambda (term &rest _) (setq searched term))))
         (haystack-run-root-search-at-point)
         (should (equal searched "rust")))))))

(ert-deftest haystack-test/search-at-point-uses-region-when-active ()
  "Uses the active region instead of word at point when a region is active."
  (haystack-test--with-notes-dir
   (with-temp-buffer
     (insert "bevy ecs patterns")
     (goto-char (point-min))
     (push-mark (point-min) t t)
     (goto-char 9)
     (let ((searched nil)
           (transient-mark-mode t))
       (cl-letf (((symbol-function 'haystack-run-root-search)
                  (lambda (term &rest _) (setq searched term))))
         (haystack-run-root-search-at-point)
         (should (equal searched "bevy ecs")))))))

(ert-deftest haystack-test/search-at-point-errors-on-no-word-no-region ()
  "Signals user-error when point is on whitespace and no region is active."
  (haystack-test--with-notes-dir
   (with-temp-buffer
     (insert "  ")
     (goto-char (point-min))
     (should-error (haystack-run-root-search-at-point) :type 'user-error))))

;;;; Stop words — data layer

(ert-deftest haystack-test/stop-words-load-returns-nil-when-no-file ()
  "Loading stop words when no file exists returns nil (not an error)."
  (haystack-test--with-notes-dir
   (let ((haystack--stop-words nil))
     (haystack--load-stop-words)
     (should (null haystack--stop-words)))))

(ert-deftest haystack-test/stop-words-auto-seed-on-first-access ()
  "haystack--ensure-stop-words seeds defaults and creates the file when absent."
  (haystack-test--with-notes-dir
   (let ((haystack--stop-words nil))
     (haystack--ensure-stop-words)
     (should (listp haystack--stop-words))
     (should (> (length haystack--stop-words) 50))
     (should (member "the" haystack--stop-words))
     (should (file-exists-p (expand-file-name ".haystack-stop-words.el"
                                              haystack-notes-directory))))))

(ert-deftest haystack-test/stop-words-add-word-persists ()
  "haystack-add-stop-word adds the word and saves the file."
  (haystack-test--with-notes-dir
   (let ((haystack--stop-words nil))
     (haystack--ensure-stop-words)
     (haystack-add-stop-word "widget")
     (should (member "widget" haystack--stop-words))
     ;; Reload from disk and verify
     (setq haystack--stop-words nil)
     (haystack--load-stop-words)
     (should (member "widget" haystack--stop-words)))))

(ert-deftest haystack-test/stop-words-remove-word-persists ()
  "haystack-remove-stop-word removes the word and saves the file."
  (haystack-test--with-notes-dir
   (let ((haystack--stop-words nil))
     (haystack--ensure-stop-words)
     (haystack-add-stop-word "widget")
     (haystack-remove-stop-word "widget")
     (should-not (member "widget" haystack--stop-words))
     (setq haystack--stop-words nil)
     (haystack--load-stop-words)
     (should-not (member "widget" haystack--stop-words)))))

(ert-deftest haystack-test/stop-words-describe-buffer-created ()
  "haystack-describe-stop-words opens a buffer listing the stop words."
  (haystack-test--with-notes-dir
   (let ((haystack--stop-words nil))
     (haystack--ensure-stop-words)
     (haystack-describe-stop-words)
     (let ((buf (get-buffer "*haystack-stop-words*")))
       (should (bufferp buf))
       (should (string-match-p "the" (with-current-buffer buf (buffer-string))))
       (kill-buffer buf)))))

;;;; Stop words — check helper

(ert-deftest haystack-test/stop-word-check-single-word-in-list ()
  "haystack--stop-word-p returns t for a single word in the stop list."
  (let ((haystack--stop-words '("the" "a" "and")))
    (should (haystack--stop-word-p "the"))))

(ert-deftest haystack-test/stop-word-check-not-in-list ()
  "haystack--stop-word-p returns nil for a word not in the list."
  (let ((haystack--stop-words '("the" "a" "and")))
    (should-not (haystack--stop-word-p "rust"))))

(ert-deftest haystack-test/stop-word-check-case-insensitive ()
  "haystack--stop-word-p is case-insensitive."
  (let ((haystack--stop-words '("the")))
    (should (haystack--stop-word-p "THE"))
    (should (haystack--stop-word-p "The"))))

(ert-deftest haystack-test/stop-word-check-multi-word-never-blocked ()
  "haystack--stop-word-p returns nil for multi-word input."
  (let ((haystack--stop-words '("the" "a")))
    (should-not (haystack--stop-word-p "the quick"))))

;;;; Stop words — search integration prompt

(ert-deftest haystack-test/stop-word-prompt-s-searches-literally ()
  "Choosing s runs a literal search (descriptor has :root-literal t)."
  (haystack-test--with-notes-dir
   (let ((haystack--stop-words '("the")))
     (cl-letf (((symbol-function 'haystack--stop-word-prompt)
                (lambda (_term) ?s))
               ((symbol-function 'pop-to-buffer) #'ignore))
       (let ((buf (haystack-run-root-search "the")))
         (unwind-protect
             (should (plist-get
                      (buffer-local-value 'haystack--search-descriptor buf)
                      :root-literal))
           (when (buffer-live-p buf) (kill-buffer buf))))))))

(ert-deftest haystack-test/stop-word-prompt-r-removes-and-searches ()
  "Choosing r removes the word from the stop list and searches normally."
  (haystack-test--with-notes-dir
   (let ((haystack--stop-words '("the")))
     (cl-letf (((symbol-function 'haystack--stop-word-prompt)
                (lambda (_term) ?r))
               ((symbol-function 'pop-to-buffer) #'ignore))
       (let ((buf (haystack-run-root-search "the")))
         (unwind-protect
             (progn
               (should-not (member "the" haystack--stop-words))
               (should-not (plist-get
                            (buffer-local-value 'haystack--search-descriptor buf)
                            :root-literal)))
           (when (buffer-live-p buf) (kill-buffer buf))))))))

(ert-deftest haystack-test/stop-word-prompt-q-aborts ()
  "Choosing q returns nil and opens no buffer."
  (haystack-test--with-notes-dir
   (let ((haystack--stop-words '("the")))
     (cl-letf (((symbol-function 'haystack--stop-word-prompt)
                (lambda (_term) ?q)))
       (should (null (haystack-run-root-search "the")))))))

(ert-deftest haystack-test/stop-word-literal-prefix-bypasses-check ()
  "A =term input bypasses the stop word check entirely."
  (haystack-test--with-notes-dir
   (let ((haystack--stop-words '("the"))
         (prompt-called nil))
     (cl-letf (((symbol-function 'haystack--stop-word-prompt)
                (lambda (_term) (setq prompt-called t) ?q))
               ((symbol-function 'pop-to-buffer) #'ignore))
       (let ((buf (haystack-run-root-search "=the")))
         (when (buffer-live-p buf) (kill-buffer buf)))
       (should-not prompt-called)))))

(ert-deftest haystack-test/stop-word-multi-word-bypasses-check ()
  "A multi-word input bypasses the stop word check."
  (haystack-test--with-notes-dir
   (let ((haystack--stop-words '("the"))
         (prompt-called nil))
     (cl-letf (((symbol-function 'haystack--stop-word-prompt)
                (lambda (_term) (setq prompt-called t) ?q))
               ((symbol-function 'pop-to-buffer) #'ignore))
       (let ((buf (haystack-run-root-search "the quick")))
         (when (buffer-live-p buf) (kill-buffer buf)))
       (should-not prompt-called)))))

;;;; haystack--discoverability-tokenize

(ert-deftest haystack-test/discoverability-tokenize-basic ()
  "Tokenize splits on whitespace and lowercases."
  (let ((haystack--stop-words '()))
    (should (equal (sort (haystack--discoverability-tokenize "Foo bar baz") #'string<)
                   '("bar" "baz" "foo")))))

(ert-deftest haystack-test/discoverability-tokenize-punctuation ()
  "Common punctuation is treated as a separator."
  (let ((haystack--stop-words '()))
    (let ((tokens (haystack--discoverability-tokenize "foo, bar. baz: qux!")))
      (should (member "foo" tokens))
      (should (member "bar" tokens))
      (should (member "baz" tokens))
      (should (member "qux" tokens)))))

(ert-deftest haystack-test/discoverability-tokenize-deduplicated ()
  "Duplicate tokens are removed."
  (let ((haystack--stop-words '()))
    (let ((tokens (haystack--discoverability-tokenize "rust rust Rust")))
      (should (equal (length tokens) 1))
      (should (member "rust" tokens)))))

(ert-deftest haystack-test/discoverability-tokenize-stop-words-removed ()
  "Stop words are excluded from the token list."
  (let ((haystack--stop-words '("the" "and" "is")))
    (let ((tokens (haystack--discoverability-tokenize "the quick brown fox and is")))
      (should-not (member "the" tokens))
      (should-not (member "and" tokens))
      (should-not (member "is" tokens))
      (should (member "quick" tokens)))))

(ert-deftest haystack-test/discoverability-tokenize-hyphens-kept ()
  "Hyphens are word chars by default — compound words kept intact."
  (let ((haystack--stop-words '())
        (haystack-discoverability-split-compound-words nil))
    (let ((tokens (haystack--discoverability-tokenize "word-word under_score")))
      (should (member "word-word" tokens))
      (should (member "under_score" tokens)))))

(ert-deftest haystack-test/discoverability-tokenize-split-compound ()
  "With split-compound-words t, hyphens and underscores split tokens."
  (let ((haystack--stop-words '())
        (haystack-discoverability-split-compound-words t))
    (let ((tokens (haystack--discoverability-tokenize "word-word under_score")))
      (should-not (member "word-word" tokens))
      (should-not (member "under_score" tokens))
      (should (member "word" tokens))
      (should (member "under" tokens))
      (should (member "score" tokens)))))

(ert-deftest haystack-test/discoverability-tokenize-no-length-filter ()
  "Short tokens like 'c', 'go', 'js' are kept."
  (let ((haystack--stop-words '()))
    (let ((tokens (haystack--discoverability-tokenize "c go js rust")))
      (should (member "c" tokens))
      (should (member "go" tokens))
      (should (member "js" tokens)))))

(ert-deftest haystack-test/discoverability-tokenize-empty-string ()
  "Empty input returns empty list."
  (let ((haystack--stop-words '()))
    (should (null (haystack--discoverability-tokenize "")))))

;;;; haystack--discoverability-tier

(ert-deftest haystack-test/discoverability-tier-isolated ()
  "Zero files → isolated."
  (let ((haystack-discoverability-sparse-max 3)
        (haystack-discoverability-ubiquitous-min 500))
    (should (eq 'isolated (haystack--discoverability-tier 0)))))

(ert-deftest haystack-test/discoverability-tier-sparse-min ()
  "One file → sparse."
  (let ((haystack-discoverability-sparse-max 3)
        (haystack-discoverability-ubiquitous-min 500))
    (should (eq 'sparse (haystack--discoverability-tier 1)))))

(ert-deftest haystack-test/discoverability-tier-sparse-max ()
  "sparse-max files → sparse."
  (let ((haystack-discoverability-sparse-max 3)
        (haystack-discoverability-ubiquitous-min 500))
    (should (eq 'sparse (haystack--discoverability-tier 3)))))

(ert-deftest haystack-test/discoverability-tier-connected-min ()
  "sparse-max+1 files → connected."
  (let ((haystack-discoverability-sparse-max 3)
        (haystack-discoverability-ubiquitous-min 500))
    (should (eq 'connected (haystack--discoverability-tier 4)))))

(ert-deftest haystack-test/discoverability-tier-connected-max ()
  "ubiquitous-min-1 files → connected."
  (let ((haystack-discoverability-sparse-max 3)
        (haystack-discoverability-ubiquitous-min 500))
    (should (eq 'connected (haystack--discoverability-tier 499)))))

(ert-deftest haystack-test/discoverability-tier-ubiquitous ()
  "ubiquitous-min+ files → ubiquitous."
  (let ((haystack-discoverability-sparse-max 3)
        (haystack-discoverability-ubiquitous-min 500))
    (should (eq 'ubiquitous (haystack--discoverability-tier 500)))))

;;;; haystack--discoverability-buffer-name

(ert-deftest haystack-test/discoverability-buffer-name-timestamped ()
  "Timestamped filename → slug (no timestamp, no ext) in buffer name."
  (should (equal (haystack--discoverability-buffer-name
                  "/notes/20241215120000-rust-async.org")
                 "*haystack-discoverability: rust-async*")))

(ert-deftest haystack-test/discoverability-buffer-name-plain ()
  "Plain filename → stripped extension in buffer name."
  (should (equal (haystack--discoverability-buffer-name
                  "/notes/my-note.md")
                 "*haystack-discoverability: my-note*")))

;;;; haystack--discoverability-in-notes-dir-p

(ert-deftest haystack-test/discoverability-in-notes-dir-p-yes ()
  "File inside notes directory → non-nil."
  (haystack-test--with-notes-dir
   (let ((f (expand-file-name "note.org" haystack-notes-directory)))
     (should (haystack--discoverability-in-notes-dir-p f)))))

(ert-deftest haystack-test/discoverability-in-notes-dir-p-no ()
  "File outside notes directory → nil."
  (haystack-test--with-notes-dir
   (should-not (haystack--discoverability-in-notes-dir-p "/tmp/outsider.org"))))

;;;; haystack-describe-discoverability (integration)

(ert-deftest haystack-test/discoverability-errors-not-file-backed ()
  "Signal user-error when buffer has no associated file."
  (haystack-test--with-notes-dir
   (with-temp-buffer
     (should-error (haystack-describe-discoverability) :type 'user-error))))

(ert-deftest haystack-test/discoverability-errors-outside-notes-dir ()
  "Signal user-error when the buffer's file is outside the notes directory."
  (haystack-test--with-notes-dir
   (haystack-test--with-file-buffer "org"
     (should-error (haystack-describe-discoverability) :type 'user-error))))

(ert-deftest haystack-test/discoverability-creates-org-buffer ()
  "Produces a live buffer in haystack-discoverability-mode."
  (haystack-test--with-notes-dir
   (let* ((file (expand-file-name "20241215120000-test-note.org"
                                  haystack-notes-directory))
          (buf (find-file-noselect file)))
     (unwind-protect
         (with-current-buffer buf
           (let ((inhibit-read-only t))
             (insert "uniqueterm12345")
             (write-region nil nil file))
           (cl-letf (((symbol-function 'pop-to-buffer) #'ignore))
             (let ((result (haystack-describe-discoverability)))
               (unwind-protect
                   (should (eq (buffer-local-value 'major-mode result)
                               'haystack-discoverability-mode))
                 (when (buffer-live-p result) (kill-buffer result))))))
       (kill-buffer buf)
       (when (file-exists-p file) (delete-file file))))))

(ert-deftest haystack-test/discoverability-buffer-has-tier-headings ()
  "Buffer content contains all four tier headings."
  (haystack-test--with-notes-dir
   (let* ((file (expand-file-name "20241215120000-test-note.org"
                                  haystack-notes-directory))
          (buf (find-file-noselect file)))
     (unwind-protect
         (with-current-buffer buf
           (let ((inhibit-read-only t))
             (insert "uniqueterm12345")
             (write-region nil nil file))
           (cl-letf (((symbol-function 'pop-to-buffer) #'ignore))
             (let ((result (haystack-describe-discoverability)))
               (unwind-protect
                   (with-current-buffer result
                     (let ((content (buffer-substring-no-properties
                                     (point-min) (point-max))))
                       (should (string-match-p "Isolated" content))
                       (should (string-match-p "Sparse" content))
                       (should (string-match-p "Connected" content))
                       (should (string-match-p "Ubiquitous" content))))
                 (when (buffer-live-p result) (kill-buffer result))))))
       (kill-buffer buf)
       (when (file-exists-p file) (delete-file file))))))

(ert-deftest haystack-test/discoverability-buffer-is-read-only ()
  "Discoverability buffer is read-only."
  (haystack-test--with-notes-dir
   (let* ((file (expand-file-name "20241215120000-test-note.org"
                                  haystack-notes-directory))
          (buf (find-file-noselect file)))
     (unwind-protect
         (with-current-buffer buf
           (let ((inhibit-read-only t))
             (insert "uniqueterm12345")
             (write-region nil nil file))
           (cl-letf (((symbol-function 'pop-to-buffer) #'ignore))
             (let ((result (haystack-describe-discoverability)))
               (unwind-protect
                   (should (buffer-local-value 'buffer-read-only result))
                 (when (buffer-live-p result) (kill-buffer result))))))
       (kill-buffer buf)
       (when (file-exists-p file) (delete-file file))))))

(ert-deftest haystack-test/discoverability-refresh-kills-old-buffer ()
  "Re-running replaces the existing discoverability buffer."
  (haystack-test--with-notes-dir
   (let* ((file (expand-file-name "20241215120000-test-note.org"
                                  haystack-notes-directory))
          (buf (find-file-noselect file)))
     (unwind-protect
         (with-current-buffer buf
           (let ((inhibit-read-only t))
             (insert "uniqueterm12345")
             (write-region nil nil file))
           (cl-letf (((symbol-function 'pop-to-buffer) #'ignore))
             (let ((r1 (haystack-describe-discoverability)))
               (let ((r2 (haystack-describe-discoverability)))
                 (unwind-protect
                     (progn
                       (should (buffer-live-p r2))
                       (should-not (buffer-live-p r1)))
                   (when (buffer-live-p r2) (kill-buffer r2)))))))
       (kill-buffer buf)
       (when (file-exists-p file) (delete-file file))))))

(ert-deftest haystack-test/discoverability-org-properties-drawer ()
  "Each tier section has a PROPERTIES drawer with HAYSTACK_TIER."
  (haystack-test--with-notes-dir
   (let* ((file (expand-file-name "20241215120000-test-note.org"
                                  haystack-notes-directory))
          (buf (find-file-noselect file)))
     (unwind-protect
         (with-current-buffer buf
           (let ((inhibit-read-only t))
             (insert "uniqueterm12345")
             (write-region nil nil file))
           (cl-letf (((symbol-function 'pop-to-buffer) #'ignore))
             (let ((result (haystack-describe-discoverability)))
               (unwind-protect
                   (with-current-buffer result
                     (let ((content (buffer-substring-no-properties
                                     (point-min) (point-max))))
                       (should (string-match-p ":HAYSTACK_TIER:" content))
                       (should (string-match-p ":PROPERTIES:" content))
                       (should (string-match-p ":END:" content))))
                 (when (buffer-live-p result) (kill-buffer result))))))
       (kill-buffer buf)
       (when (file-exists-p file) (delete-file file))))))

(provide 'haystack-test)
;;; haystack-test.el ends here
