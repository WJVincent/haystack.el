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

(provide 'haystack-test)
;;; haystack-test.el ends here
