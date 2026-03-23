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
  (string-match-p (regexp-quote haystack--sentinel-regexp) str))

;;;; haystack--timestamp

(ert-deftest haystack-test/timestamp-is-14-digits ()
  "Timestamp returns a string of exactly 14 digits."
  (should (string-match-p "\\`[0-9]\\{14\\}\\'" (haystack--timestamp))))

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
    (should (string-match-p (concat (regexp-quote haystack--sentinel-regexp)
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
                 '("rust" nil nil nil))))

(ert-deftest haystack-test/strip-prefixes-negate ()
  (should (equal (haystack--strip-prefixes "!rust")
                 '("rust" t nil nil))))

(ert-deftest haystack-test/strip-prefixes-literal ()
  (should (equal (haystack--strip-prefixes "=rust")
                 '("rust" nil t nil))))

(ert-deftest haystack-test/strip-prefixes-regex ()
  (should (equal (haystack--strip-prefixes "~rus+t")
                 '("rus+t" nil nil t))))

(ert-deftest haystack-test/strip-prefixes-negate-and-literal ()
  (should (equal (haystack--strip-prefixes "!=rust")
                 '("rust" t t nil))))

(ert-deftest haystack-test/strip-prefixes-negate-and-regex ()
  (should (equal (haystack--strip-prefixes "!~rus+t")
                 '("rus+t" t nil t))))

(ert-deftest haystack-test/strip-prefixes-literal-and-regex ()
  (should (equal (haystack--strip-prefixes "=~rus+t")
                 '("rus+t" nil t t))))

(ert-deftest haystack-test/strip-prefixes-order-matters ()
  "= before ! is not treated as the literal prefix."
  (should (equal (haystack--strip-prefixes "=!rust")
                 '("!rust" nil t nil))))

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

;;; haystack--parse-input (integration)

(ert-deftest haystack-test/parse-input-bare ()
  (let ((result (haystack--parse-input "rust")))
    (should (equal (plist-get result :term)       "rust"))
    (should (equal (plist-get result :negated)    nil))
    (should (equal (plist-get result :literal)    nil))
    (should (equal (plist-get result :regex)      nil))
    (should (equal (plist-get result :multi-word) nil))
    (should (equal (plist-get result :pattern)    (regexp-quote "rust")))))

(ert-deftest haystack-test/parse-input-negated-regex ()
  (let ((result (haystack--parse-input "!~rus+t")))
    (should (equal (plist-get result :term)    "rus+t"))
    (should (equal (plist-get result :negated) t))
    (should (equal (plist-get result :regex)   t))
    (should (equal (plist-get result :pattern) "rus+t"))))

(ert-deftest haystack-test/parse-input-multi-word ()
  (let ((result (haystack--parse-input "rust ownership")))
    (should (plist-get result :multi-word))
    (should (equal (plist-get result :pattern) (regexp-quote "rust ownership")))))

(ert-deftest haystack-test/parse-input-special-chars-quoted ()
  "Special regex characters in bare terms are escaped."
  (let ((result (haystack--parse-input "C++")))
    (should (equal (plist-get result :pattern) (regexp-quote "C++")))))

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
             (should (string-match-p ";;; haystack: root=nomatchxyz99"
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

;;;; haystack-search-region

(ert-deftest haystack-test/search-region-errors-without-region ()
  "Signals user-error when there is no active region."
  (with-temp-buffer
    (should-error (haystack-search-region) :type 'user-error)))

(provide 'haystack-test)
;;; haystack-test.el ends here
