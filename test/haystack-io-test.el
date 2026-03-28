;;; haystack-io-test.el --- IO tests against the demo corpus  -*- lexical-binding: t -*-

;;; Commentary:
;; Runs each major haystack feature against a fresh copy of the demo corpus
;; (demo/notes/), verifying both that the feature works end-to-end and that
;; the corpus contains enough real content to demonstrate it.
;;
;; Real rg calls are made against real files.  Only UI functions are mocked:
;; pop-to-buffer, switch-to-buffer, yes-or-no-p, read-char-choice.
;;
;; Run from the repo root with:
;;   emacs --batch -l haystack.el -l test/haystack-io-test.el \
;;         -f ert-run-tests-batch-and-exit
;;
;; Expected runtime: ~15 seconds (dominated by Test 9, discoverability,
;; which runs one rg invocation per unique token in the note).

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'haystack)

;;;; Setup macro

;; Capture the repo root at load time while load-file-name is still set.
;; haystack--demo-package-dir() returns nil in batch after the file has
;; finished loading, so we cannot call it lazily inside a defmacro body.
(defconst haystack-io-test--demo-notes-dir
  (expand-file-name
   "../demo/notes"
   (file-name-directory (file-truename (or load-file-name buffer-file-name))))
  "Absolute path to demo/notes/ in the haystack repository.")

(defmacro haystack-io-test--with-corpus (&rest body)
  "Run BODY with `haystack-notes-directory' pointing at a temp copy of demo/notes.
Saves and restores all haystack globals that BODY may mutate.  On exit,
kills all haystack results buffers scoped to the temp directory, kills any
file-visiting buffers inside it, then deletes the temp directory."
  (declare (indent 0))
  `(let* ((src-dir  haystack-io-test--demo-notes-dir)
          (temp-dir (make-temp-file "haystack-io-test-" t))
          (saved-notes-dir     haystack-notes-directory)
          (saved-freq-data     (copy-sequence haystack--frecency-data))
          (saved-freq-dirty    haystack--frecency-dirty)
          (saved-freq-init     haystack--frecency-initialized)
          (saved-exp-groups    (copy-sequence haystack--expansion-groups))
          (saved-exp-loaded    haystack--expansion-groups-loaded)
          (saved-stop-words    (copy-sequence haystack--stop-words)))
     (unwind-protect
         (progn
           (copy-directory src-dir temp-dir nil t t)
           (setq haystack-notes-directory          temp-dir
                 haystack--frecency-dirty          nil
                 haystack--stop-words              nil
                 haystack--expansion-groups-loaded nil)
           ;; Load corpus data and mark initialized to skip idle-timer setup
           (haystack--load-expansion-groups)
           (haystack--load-frecency)
           (setq haystack--frecency-initialized t)
           ,@body)
       ;; Kill results buffers scoped to this temp dir
       (dolist (buf (buffer-list))
         (when (buffer-live-p buf)
           (when (equal (buffer-local-value 'haystack--buffer-notes-dir buf)
                        (expand-file-name temp-dir))
             (ignore-errors (kill-buffer buf)))))
       ;; Kill file-visiting buffers inside the temp dir (e.g. notes opened
       ;; for discoverability)
       (let ((prefix (file-name-as-directory (expand-file-name temp-dir))))
         (dolist (buf (buffer-list))
           (when (buffer-live-p buf)
             (let ((fname (buffer-file-name buf)))
               (when (and fname (string-prefix-p prefix (expand-file-name fname)))
                 (ignore-errors (kill-buffer buf)))))))
       ;; Restore globals
       (setq haystack-notes-directory             saved-notes-dir
             haystack--frecency-data              saved-freq-data
             haystack--frecency-dirty             saved-freq-dirty
             haystack--frecency-initialized       saved-freq-init
             haystack--expansion-groups           saved-exp-groups
             haystack--expansion-groups-loaded    saved-exp-loaded
             haystack--stop-words                 saved-stop-words)
       (when (file-directory-p temp-dir)
         (delete-directory temp-dir t)))))

;;;; Test 1 — Root search

(ert-deftest haystack-io-test/root-search-returns-results ()
  "Root search for 'haystack' returns real results from the demo corpus.
Proves the rg pipeline works end-to-end and that the corpus contains
enough content to be found."
  (haystack-io-test--with-corpus
   (cl-letf (((symbol-function 'pop-to-buffer)    #'ignore)
             ((symbol-function 'switch-to-buffer) #'ignore)
             ((symbol-function 'yes-or-no-p)      (lambda (_) t)))
     (let ((buf (haystack-run-root-search "haystack")))
       (unwind-protect
           (progn
             (should (buffer-live-p buf))
             (with-current-buffer buf
               (let* ((content    (buffer-string))
                      (file-count (car (haystack--count-search-stats content))))
                 (should (>= file-count 10))
                 ;; grep-mode compatible: at least one filename:line:content line
                 (should (string-match-p "[^:]+:[0-9]+:.+" content))
                 (should (string-match-p "root=haystack" content)))))
         (when (buffer-live-p buf) (kill-buffer buf)))))))

;;;; Test 2 — Expansion group widens results

(ert-deftest haystack-io-test/expansion-widens-results ()
  "Searching 'lisp' (expansion-group match) finds more files than '=lisp' (literal).
The lisp expansion group adds common-lisp, cl, scheme, and clojure; 'cl'
appears as a substring in many words across the corpus, ensuring the
expanded count exceeds the literal count."
  (haystack-io-test--with-corpus
   (cl-letf (((symbol-function 'pop-to-buffer)    #'ignore)
             ((symbol-function 'switch-to-buffer) #'ignore)
             ((symbol-function 'yes-or-no-p)      (lambda (_) t)))
     (let ((exp-buf (haystack-run-root-search "lisp"))
           (lit-buf (haystack-run-root-search "=lisp")))
       (unwind-protect
           (let ((exp-count (with-current-buffer exp-buf
                              (car (haystack--count-search-stats (buffer-string)))))
                 (lit-count (with-current-buffer lit-buf
                              (car (haystack--count-search-stats (buffer-string))))))
             (should (> exp-count lit-count))
             (with-current-buffer exp-buf
               (should (string-match-p "(lisp|common-lisp|cl|scheme|clojure)"
                                       (buffer-string)))
               (should (plist-get haystack--search-descriptor :root-expansion))))
         (when (buffer-live-p exp-buf) (kill-buffer exp-buf))
         (when (buffer-live-p lit-buf) (kill-buffer lit-buf)))))))

;;;; Test 3 — AND query

(ert-deftest haystack-io-test/and-query-intersects-files ()
  "AND query 'lisp & macros' finds a non-empty subset of the 'lisp' results.
Confirms the two-pass --files-with-matches intersection pipeline works
against real files."
  (haystack-io-test--with-corpus
   (cl-letf (((symbol-function 'pop-to-buffer)    #'ignore)
             ((symbol-function 'switch-to-buffer) #'ignore)
             ((symbol-function 'yes-or-no-p)      (lambda (_) t)))
     (let ((and-buf  (haystack-run-root-search "lisp & macros"))
           (root-buf (haystack-run-root-search "=lisp")))
       (unwind-protect
           (let ((and-count  (with-current-buffer and-buf
                               (car (haystack--count-search-stats (buffer-string)))))
                 (root-count (with-current-buffer root-buf
                               (car (haystack--count-search-stats (buffer-string))))))
             (should (>= and-count 1))
             (should (< and-count root-count))
             (with-current-buffer and-buf
               (should (string-match-p "&" (buffer-string)))))
         (when (buffer-live-p and-buf)  (kill-buffer and-buf))
         (when (buffer-live-p root-buf) (kill-buffer root-buf)))))))

;;;; Test 4 — Progressive filter

(ert-deftest haystack-io-test/filter-further-narrows ()
  "filter-further 'filtering' narrows a 'haystack' root search.
Confirms the xargs-rg pipeline works and that the demo corpus contains
haystack-filtering.org (the canonical haystack+filtering note)."
  (haystack-io-test--with-corpus
   (cl-letf (((symbol-function 'pop-to-buffer)    #'ignore)
             ((symbol-function 'switch-to-buffer) #'ignore)
             ((symbol-function 'yes-or-no-p)      (lambda (_) t)))
     (let* ((root-buf  (haystack-run-root-search "haystack"))
            (child-buf (with-current-buffer root-buf
                         (haystack-filter-further "filtering"))))
       (unwind-protect
           (let ((root-count  (with-current-buffer root-buf
                                (car (haystack--count-search-stats (buffer-string)))))
                 (child-count (with-current-buffer child-buf
                                (car (haystack--count-search-stats (buffer-string))))))
             (should (buffer-live-p child-buf))
             (should (>= child-count 1))
             (should (< child-count root-count))
             (with-current-buffer child-buf
               (should (equal (plist-get haystack--search-descriptor :root-term)
                              "haystack"))
               (should (equal (plist-get (car (plist-get haystack--search-descriptor
                                                         :filters))
                                         :term)
                              "filtering"))
               (should (eq haystack--parent-buffer root-buf))
               (should (string-match-p "filter=filtering" (buffer-string)))))
         (when (buffer-live-p child-buf) (kill-buffer child-buf))
         (when (buffer-live-p root-buf)  (kill-buffer root-buf)))))))

;;;; Test 5 — Filename filter

(ert-deftest haystack-io-test/filter-further-filename-restricts-by-path ()
  "Filename filter '/emacs' restricts results to files whose names contain 'emacs'.
Confirms the Elisp-side filename filtering path and that the demo corpus
contains notes with 'emacs' in their filenames."
  (haystack-io-test--with-corpus
   (cl-letf (((symbol-function 'pop-to-buffer)    #'ignore)
             ((symbol-function 'switch-to-buffer) #'ignore)
             ((symbol-function 'yes-or-no-p)      (lambda (_) t)))
     (let* ((root-buf  (haystack-run-root-search "emacs"))
            (child-buf (with-current-buffer root-buf
                         (haystack-filter-further "/emacs"))))
       (unwind-protect
           (let ((root-count  (with-current-buffer root-buf
                                (car (haystack--count-search-stats (buffer-string)))))
                 (child-count (with-current-buffer child-buf
                                (car (haystack--count-search-stats (buffer-string))))))
             (should (>= child-count 1))
             (should (<= child-count root-count))
             (with-current-buffer child-buf
               (should (string-match-p "filename=emacs" (buffer-string)))
               (dolist (path (haystack--extract-filenames (buffer-string)))
                 (should (string-match-p "emacs" (file-name-nondirectory path))))))
         (when (buffer-live-p child-buf) (kill-buffer child-buf))
         (when (buffer-live-p root-buf)  (kill-buffer root-buf)))))))

;;;; Test 6 — Negation filter

(ert-deftest haystack-io-test/filter-further-negation-excludes-clojure ()
  "Negation '!clojure' removes clojure-overview.md from lisp results.
Confirms the --files-without-match pipeline and that the demo corpus
contains a dedicated clojure note to be excluded."
  (haystack-io-test--with-corpus
   (cl-letf (((symbol-function 'pop-to-buffer)    #'ignore)
             ((symbol-function 'switch-to-buffer) #'ignore)
             ((symbol-function 'yes-or-no-p)      (lambda (_) t)))
     (let* ((root-buf  (haystack-run-root-search "lisp"))
            (child-buf (with-current-buffer root-buf
                         (haystack-filter-further "!=clojure"))))
       (unwind-protect
           (let ((root-count  (with-current-buffer root-buf
                                (car (haystack--count-search-stats (buffer-string)))))
                 (child-count (with-current-buffer child-buf
                                (car (haystack--count-search-stats (buffer-string))))))
             (should (< child-count root-count))
             (with-current-buffer child-buf
               (should (string-match-p "exclude=clojure" (buffer-string)))
               (dolist (path (haystack--extract-filenames (buffer-string)))
                 (should-not (string-match-p "clojure"
                                             (file-name-nondirectory path))))))
         (when (buffer-live-p child-buf) (kill-buffer child-buf))
         (when (buffer-live-p root-buf)  (kill-buffer root-buf)))))))

;;;; Test 7 — Frecency replay

(ert-deftest haystack-io-test/frecency-replay-known-chain ()
  "Frecency replay of (\"haystack\" \"filtering\") produces the correct leaf buffer.
Confirms that haystack--frecency-replay works against real files and that
the demo corpus's pre-built frecency data is coherent."
  (haystack-io-test--with-corpus
   (cl-letf (((symbol-function 'pop-to-buffer)    #'ignore)
             ((symbol-function 'switch-to-buffer) #'ignore)
             ((symbol-function 'yes-or-no-p)      (lambda (_) t)))
     (let ((buf (haystack--frecency-replay '("haystack" "filtering"))))
       (unwind-protect
           (progn
             (should (buffer-live-p buf))
             (with-current-buffer buf
               (should (equal (plist-get haystack--search-descriptor :root-term)
                              "haystack"))
               (should (equal (plist-get (car (plist-get haystack--search-descriptor
                                                         :filters))
                                         :term)
                              "filtering"))
               (should (null haystack--parent-buffer))
               (should (>= (car (haystack--count-search-stats (buffer-string))) 1)))
             ;; Replay kills the intermediate root buffer
             (should-not (get-buffer "*haystack:1:haystack*")))
         (when (buffer-live-p buf) (kill-buffer buf)))))))

;;;; Test 8 — Composite staging buffer

(ert-deftest haystack-io-test/compose-creates-staging-buffer ()
  "haystack-compose creates a valid staging buffer from real search results.
Confirms the locus-extraction and section-rendering pipeline works against
real files and that 'zettelkasten' is searchable in the demo corpus."
  (haystack-io-test--with-corpus
   (cl-letf (((symbol-function 'pop-to-buffer)    #'ignore)
             ((symbol-function 'switch-to-buffer) #'ignore)
             ((symbol-function 'yes-or-no-p)      (lambda (_) t)))
     (let* ((root-buf    (haystack-run-root-search "zettelkasten"))
            (compose-buf (with-current-buffer root-buf
                           (haystack-compose))))
       (unwind-protect
           (progn
             (should (buffer-live-p compose-buf))
             (with-current-buffer compose-buf
               (should (eq major-mode 'haystack-compose-mode))
               (let ((content (buffer-string)))
                 (should (string-match-p "#\\+TITLE: Haystack Composite:" content))
                 (should (string-match-p "#\\+HAYSTACK-CHAIN:" content))
                 (should (string-match-p "\n\\* " content)))
               (should (not (null haystack--compose-loci)))))
         (when (buffer-live-p compose-buf) (kill-buffer compose-buf))
         (when (buffer-live-p root-buf)    (kill-buffer root-buf)))))))

;;;; Test 9 — Discoverability analysis of a real note

(ert-deftest haystack-io-test/discoverability-real-note ()
  "haystack-describe-discoverability analyses a real demo note end-to-end.
Confirms the tokenise → rg-per-term → tier-render pipeline against the
full 84-note corpus.  The note haystack-discoverability.org exists in the
demo corpus specifically to demonstrate this feature.

NOTE: This is the slowest IO test — it runs one rg invocation per unique
token in the note (~150 calls).  Expect 5–15 seconds."
  (haystack-io-test--with-corpus
   (let* ((note-path (expand-file-name "20250407092134-haystack-discoverability.org"
                                       haystack-notes-directory))
          (note-buf  (find-file-noselect note-path)))
     (unwind-protect
         (cl-letf (((symbol-function 'pop-to-buffer) #'ignore))
           (let ((result (with-current-buffer note-buf
                           (haystack-describe-discoverability))))
             (unwind-protect
                 (progn
                   (should (buffer-live-p result))
                   (with-current-buffer result
                     (should (eq major-mode 'haystack-discoverability-mode))
                     (should (equal (buffer-name)
                                    "*haystack-discoverability: haystack-discoverability*"))
                     (let ((content (buffer-substring-no-properties
                                     (point-min) (point-max))))
                       (should (string-match-p "Isolated" content))
                       (should (string-match-p "Sparse" content))
                       (should (string-match-p "Connected" content))
                       (should (string-match-p "Ubiquitous" content))
                       (should (string-match-p ":HAYSTACK_TIER:" content)))))
               (when (buffer-live-p result) (kill-buffer result)))))
       (when (buffer-live-p note-buf) (kill-buffer note-buf))))))

;;;; Test 10 — Stop word prompt

(ert-deftest haystack-io-test/stop-word-check-prompts-and-aborts ()
  "Stop word gate fires for 'the': ?q aborts without creating a buffer; ?s proceeds.
Confirms that haystack--ensure-stop-words seeds defaults correctly in a
fresh notes directory and that the prompt intercept runs end-to-end."
  (haystack-io-test--with-corpus
   (cl-letf (((symbol-function 'pop-to-buffer)    #'ignore)
             ((symbol-function 'switch-to-buffer) #'ignore)
             ((symbol-function 'yes-or-no-p)      (lambda (_) t)))
     ;; Case 1: user quits — no buffer created
     (let ((prompt-called nil))
       (cl-letf (((symbol-function 'haystack--stop-word-prompt)
                  (lambda (_term) (setq prompt-called t) ?q)))
         (should (null (haystack-run-root-search "the")))
         (should prompt-called)
         (should-not (get-buffer "*haystack:1:the*"))))
     ;; Case 2: user searches anyway — buffer is created (literal "=the")
     (let ((buf nil))
       (cl-letf (((symbol-function 'haystack--stop-word-prompt)
                  (lambda (_term) ?s)))
         (setq buf (haystack-run-root-search "the")))
       (unwind-protect
           (should (buffer-live-p buf))
         (when (buffer-live-p buf) (kill-buffer buf)))))))

;;;; Test 11 — Frecency recording

(ert-deftest haystack-io-test/frecency-records-search ()
  "Running a root search records a frecency entry and marks the data dirty.
Confirms the frecency-record → dirty-flag pipeline works against real rg
output (the record call fires after a successful search)."
  (haystack-io-test--with-corpus
   (cl-letf (((symbol-function 'pop-to-buffer)    #'ignore)
             ((symbol-function 'switch-to-buffer) #'ignore)
             ((symbol-function 'yes-or-no-p)      (lambda (_) t)))
     (setq haystack--frecency-dirty nil)
     (let ((buf (haystack-run-root-search "emacs")))
       (unwind-protect
           (progn
             (should haystack--frecency-dirty)
             (should (cl-some (lambda (entry)
                                (equal (car entry) '("emacs")))
                              haystack--frecency-data)))
         (when (buffer-live-p buf) (kill-buffer buf)))))))

;;;; Test 12 — Filename-prefix root search

(ert-deftest haystack-io-test/root-search-filename-prefix ()
  "Root search with '/emacs' filename prefix restricts results to emacs-named files.
Confirms the filename-filter root path and that the demo corpus contains
≥ 6 notes with 'emacs' in their filenames."
  (haystack-io-test--with-corpus
   (cl-letf (((symbol-function 'pop-to-buffer)    #'ignore)
             ((symbol-function 'switch-to-buffer) #'ignore)
             ((symbol-function 'yes-or-no-p)      (lambda (_) t)))
     (let ((buf (haystack-run-root-search "/emacs")))
       (unwind-protect
           (progn
             (should (buffer-live-p buf))
             (with-current-buffer buf
               (let* ((content    (buffer-string))
                      (file-count (car (haystack--count-search-stats content)))
                      (paths      (haystack--extract-filenames content)))
                 (should (>= file-count 6))
                 (should (string-match-p "filename=emacs" content))
                 (dolist (path paths)
                   (should (string-match-p "emacs"
                                           (file-name-nondirectory path)))))))
         (when (buffer-live-p buf) (kill-buffer buf)))))))

(provide 'haystack-io-test)
;;; haystack-io-test.el ends here
