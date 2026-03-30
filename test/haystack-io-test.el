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
          (saved-stop-words    (copy-sequence haystack--stop-words))
          (saved-stop-loaded   haystack--stop-words-loaded))
     (unwind-protect
         (progn
           (copy-directory src-dir temp-dir nil t t)
           (setq haystack-notes-directory          temp-dir
                 haystack--frecency-dirty          nil
                 haystack--stop-words              nil
                 haystack--stop-words-loaded       nil
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
             haystack--stop-words                 saved-stop-words
             haystack--stop-words-loaded          saved-stop-loaded)
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
     (let ((buf (haystack--frecency-replay
                 (list :root (list :kind 'text :term "haystack")
                       :filters (list (list :term "filtering"))))))
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
                                (equal (car entry)
                                       '(:root (:kind text :term "emacs")
                                         :filters nil)))
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

;;;; Test 13 — Empty results (zero-hit path)

(ert-deftest haystack-io-test/root-search-empty-results ()
  "Root search for a nonsense term returns a live buffer with zero file hits.
Confirms the zero-result code path does not error out and that the buffer
is still grep-mode compatible (header present, no filename:line lines)."
  (haystack-io-test--with-corpus
   (cl-letf (((symbol-function 'pop-to-buffer)    #'ignore)
             ((symbol-function 'switch-to-buffer) #'ignore)
             ((symbol-function 'yes-or-no-p)      (lambda (_) t)))
     (let ((buf (haystack-run-root-search "xyzzy-no-such-term-42")))
       (unwind-protect
           (progn
             (should (buffer-live-p buf))
             (with-current-buffer buf
               (let ((file-count (car (haystack--count-search-stats (buffer-string)))))
                 (should (= file-count 0)))))
         (when (buffer-live-p buf) (kill-buffer buf)))))))

;;;; Test 14 — Regex prefix ~ bypasses regexp-quote

(ert-deftest haystack-io-test/regex-prefix-passes-raw-pattern ()
  "A ~ prefix sends the pattern to rg unescaped and sets :root-regex t.
'~zettelkas.en' matches 'zettelkasten' via the regex dot; the descriptor
records :root-regex t to prove the prefix was parsed correctly."
  (haystack-io-test--with-corpus
   (cl-letf (((symbol-function 'pop-to-buffer)    #'ignore)
             ((symbol-function 'switch-to-buffer) #'ignore)
             ((symbol-function 'yes-or-no-p)      (lambda (_) t)))
     (let ((buf (haystack-run-root-search "~zettelkas.en")))
       (unwind-protect
           (progn
             (should (buffer-live-p buf))
             (with-current-buffer buf
               (should (plist-get haystack--search-descriptor :root-regex))
               (should (>= (car (haystack--count-search-stats (buffer-string))) 1))))
         (when (buffer-live-p buf) (kill-buffer buf)))))))

;;;; Test 15 — Three-term AND query

(ert-deftest haystack-io-test/three-term-and-query ()
  "AND query 'emacs & lisp & macros' finds a strict subset of 'emacs & lisp'.
Confirms the multi-pass intersection pipeline handles more than two terms
and that the demo corpus contains notes at that intersection."
  (haystack-io-test--with-corpus
   (cl-letf (((symbol-function 'pop-to-buffer)    #'ignore)
             ((symbol-function 'switch-to-buffer) #'ignore)
             ((symbol-function 'yes-or-no-p)      (lambda (_) t)))
     (let ((three-buf (haystack-run-root-search "emacs & lisp & macros"))
           (two-buf   (haystack-run-root-search "emacs & lisp")))
       (unwind-protect
           (let ((three-count (with-current-buffer three-buf
                                (car (haystack--count-search-stats (buffer-string)))))
                 (two-count   (with-current-buffer two-buf
                                (car (haystack--count-search-stats (buffer-string))))))
             (should (>= three-count 1))
             (should (<= three-count two-count)))
         (when (buffer-live-p three-buf) (kill-buffer three-buf))
         (when (buffer-live-p two-buf)   (kill-buffer two-buf)))))))

;;;; Test 16 — Three-level filter chain

(ert-deftest haystack-io-test/three-level-filter-chain ()
  "Three-level chain haystack → filtering → stop produces a depth-2-filter buffer.
Confirms the recursive xargs-rg narrowing works across three levels and
that the descriptor carries both filter terms in order."
  (haystack-io-test--with-corpus
   (cl-letf (((symbol-function 'pop-to-buffer)    #'ignore)
             ((symbol-function 'switch-to-buffer) #'ignore)
             ((symbol-function 'yes-or-no-p)      (lambda (_) t)))
     (let* ((root-buf   (haystack-run-root-search "haystack"))
            (child1-buf (with-current-buffer root-buf
                          (haystack-filter-further "filtering")))
            (child2-buf (with-current-buffer child1-buf
                          (haystack-filter-further "stop"))))
       (unwind-protect
           (progn
             (should (buffer-live-p child2-buf))
             (with-current-buffer child2-buf
               (let* ((desc    haystack--search-descriptor)
                      (filters (plist-get desc :filters)))
                 (should (equal (plist-get desc :root-term) "haystack"))
                 (should (= (length filters) 2))
                 (should (equal (plist-get (nth 0 filters) :term) "filtering"))
                 (should (equal (plist-get (nth 1 filters) :term) "stop"))
                 (should (>= (car (haystack--count-search-stats (buffer-string))) 1)))))
         (when (buffer-live-p child2-buf) (kill-buffer child2-buf))
         (when (buffer-live-p child1-buf) (kill-buffer child1-buf))
         (when (buffer-live-p root-buf)   (kill-buffer root-buf)))))))

;;;; Test 17 — Negated filename filter

(ert-deftest haystack-io-test/negated-filename-filter-excludes-paths ()
  "Negated filename filter '!/emacs' removes all files named '*emacs*' from results.
Confirms the Elisp-side filename negation path: no result path contains
'emacs' in its base name after applying the negation filter."
  (haystack-io-test--with-corpus
   (cl-letf (((symbol-function 'pop-to-buffer)    #'ignore)
             ((symbol-function 'switch-to-buffer) #'ignore)
             ((symbol-function 'yes-or-no-p)      (lambda (_) t)))
     (let* ((root-buf  (haystack-run-root-search "emacs"))
            (child-buf (with-current-buffer root-buf
                         (haystack-filter-further "!/emacs"))))
       (unwind-protect
           (with-current-buffer child-buf
             ;; At least some files remain (emacs content without emacs in name)
             (should (>= (car (haystack--count-search-stats (buffer-string))) 1))
             ;; None of the result files have "emacs" in their base name
             (dolist (path (haystack--extract-filenames (buffer-string)))
               (should-not (string-match-p "emacs" (file-name-nondirectory path)))))
         (when (buffer-live-p child-buf) (kill-buffer child-buf))
         (when (buffer-live-p root-buf)  (kill-buffer root-buf)))))))

;;;; Test 18 — composite-filter 'only with empty composite set

(ert-deftest haystack-io-test/composite-filter-only-empty-corpus ()
  "composite-filter 'only returns zero results when demo corpus has no composites.
Confirms the 'only path (--glob=@*) completes without error even when no
files match the glob — the empty-results path must be graceful."
  (haystack-io-test--with-corpus
   (cl-letf (((symbol-function 'pop-to-buffer)    #'ignore)
             ((symbol-function 'switch-to-buffer) #'ignore)
             ((symbol-function 'yes-or-no-p)      (lambda (_) t)))
     (let ((buf (haystack-run-root-search "haystack" 'only)))
       (unwind-protect
           (progn
             (should (buffer-live-p buf))
             (with-current-buffer buf
               (should (= (car (haystack--count-search-stats (buffer-string))) 0))
               (should (eq (plist-get haystack--search-descriptor :composite-filter)
                           'only))))
         (when (buffer-live-p buf) (kill-buffer buf)))))))

;;;; Test 19 — Frecency flush writes a readable file to disk

(ert-deftest haystack-io-test/frecency-flush-writes-disk ()
  "Frecency flush writes a readable elisp file to the notes directory.
Confirms that haystack--frecency-flush produces a well-formed alist and
that subsequent haystack--load-frecency can read it back."
  (haystack-io-test--with-corpus
   (cl-letf (((symbol-function 'pop-to-buffer)    #'ignore)
             ((symbol-function 'switch-to-buffer) #'ignore)
             ((symbol-function 'yes-or-no-p)      (lambda (_) t)))
     ;; Run a search to create a frecency entry
     (let ((buf (haystack-run-root-search "emacs")))
       (when (buffer-live-p buf) (kill-buffer buf)))
     (should haystack--frecency-dirty)
     (haystack--frecency-flush)
     (should-not haystack--frecency-dirty)
     (let ((ffile (haystack--frecency-file)))
       (should (file-exists-p ffile))
       ;; File must be readable as an elisp alist
       (let ((data (with-temp-buffer
                     (insert-file-contents ffile)
                     (read (current-buffer)))))
         (should (listp data))
         (should (> (length data) 0))
         (should (listp (caar data))))))))

;;;; Test 20 — Frecency replay with zero-result chain

(ert-deftest haystack-io-test/frecency-replay-empty-results ()
  "Frecency replay of a nonsense chain produces a live buffer with zero hits.
Confirms that haystack--frecency-replay does not error out on zero results
— the empty-results buffer is valid and has the expected descriptor."
  (haystack-io-test--with-corpus
   (cl-letf (((symbol-function 'pop-to-buffer)    #'ignore)
             ((symbol-function 'switch-to-buffer) #'ignore)
             ((symbol-function 'yes-or-no-p)      (lambda (_) t)))
     (let ((buf (haystack--frecency-replay
                 (list :root (list :kind 'text :term "xyzzy-no-such-term-42")
                       :filters nil))))
       (unwind-protect
           (progn
             (should (buffer-live-p buf))
             (with-current-buffer buf
               (should (= (car (haystack--count-search-stats (buffer-string))) 0))
               (should (equal (plist-get haystack--search-descriptor :root-term)
                              "xyzzy-no-such-term-42"))
               ;; Replayed buffer has no parent (it stands alone)
               (should (null haystack--parent-buffer))))
         (when (buffer-live-p buf) (kill-buffer buf)))))))

;;;; Test 21 — Compose commit writes composite file to disk

(ert-deftest haystack-io-test/compose-commit-writes-file ()
  "haystack-compose-commit writes the @comp__ file to the notes directory.
After commit the file must exist and contain valid org frontmatter.
Re-running haystack-compose on the same results buffer detects the
existing composite and mentions it in the staging buffer header."
  (haystack-io-test--with-corpus
   (cl-letf (((symbol-function 'pop-to-buffer)    #'ignore)
             ((symbol-function 'switch-to-buffer) #'ignore)
             ((symbol-function 'yes-or-no-p)      (lambda (_) t)))
     (let* ((root-buf    (haystack-run-root-search "zettelkasten"))
            (compose-buf (with-current-buffer root-buf (haystack-compose)))
            (comp-path   (with-current-buffer compose-buf
                           (haystack--composite-filename haystack--compose-descriptor))))
       (unwind-protect
           (progn
             ;; Commit — file does not yet exist, so no overwrite prompt
             (with-current-buffer compose-buf
               (haystack-compose-commit))
             ;; File must now exist on disk
             (should (file-exists-p comp-path))
             ;; File must contain valid org frontmatter
             (let ((content (with-temp-buffer
                              (insert-file-contents comp-path)
                              (buffer-string))))
               (should (string-match-p "#\\+TITLE:" content))
               (should (string-match-p "#\\+HAYSTACK-CHAIN:" content)))
             ;; Re-compose detects the existing composite
             (let ((compose-buf2 (with-current-buffer root-buf (haystack-compose))))
               (unwind-protect
                   (with-current-buffer compose-buf2
                     (should (string-match-p "Existing composite:" (buffer-string))))
                 (when (buffer-live-p compose-buf2) (kill-buffer compose-buf2)))))
         (when (buffer-live-p compose-buf) (kill-buffer compose-buf))
         (when (buffer-live-p root-buf)    (kill-buffer root-buf)))))))

;;;; Test 22 — Frecency replay bypasses stop-word prompt

(ert-deftest haystack-io-test/frecency-replay-bypasses-stop-word ()
  "Frecency replay succeeds even when the root term is a stop word.
The stop-word prompt must never fire during replay — this is DWIM behavior.
Before the fix, replay would invoke the prompt, and a ?q abort would crash
with `wrong-type-argument' because `haystack-run-root-search' returns nil."
  (haystack-io-test--with-corpus
   (let ((prompt-called nil))
     (cl-letf (((symbol-function 'pop-to-buffer)         #'ignore)
               ((symbol-function 'switch-to-buffer)      #'ignore)
               ((symbol-function 'yes-or-no-p)           (lambda (_) t))
               ((symbol-function 'haystack--stop-word-prompt)
                (lambda (_) (setq prompt-called t) ?q)))
       ;; Add the root term as a stop word (after ensure has loaded)
       (haystack--ensure-stop-words)
       (push "haystack" haystack--stop-words)
       (let ((buf (haystack--frecency-replay
                   (list :root (list :kind 'text :term "haystack")
                         :filters (list (list :term "filtering"))))))
         (unwind-protect
             (progn
               (should-not prompt-called)
               (should (buffer-live-p buf))
               (with-current-buffer buf
                 (should (equal (plist-get haystack--search-descriptor :root-term)
                                "haystack"))))
           (when (buffer-live-p buf) (kill-buffer buf))))))))

;;;; Test 23 — Frecency replay cleans up on error

(ert-deftest haystack-io-test/frecency-replay-cleans-up-on-error ()
  "Frecency replay cleans up intermediate buffers when an error occurs mid-chain.
Confirms that `unwind-protect' kills the in-progress buffer so no orphan
haystack buffers remain after a failed replay."
  (haystack-io-test--with-corpus
   (cl-letf (((symbol-function 'pop-to-buffer)    #'ignore)
             ((symbol-function 'switch-to-buffer) #'ignore)
             ((symbol-function 'yes-or-no-p)      (lambda (_) t)))
     ;; Replay a chain where the second term will work but we sabotage
     ;; filter-further to error on the third step.
     (let ((call-count 0))
       (cl-letf (((symbol-function 'haystack-filter-further)
                  (let ((orig (symbol-function 'haystack-filter-further)))
                    (lambda (term)
                      (cl-incf call-count)
                      (if (>= call-count 2)
                          (error "Simulated mid-chain failure")
                        (funcall orig term))))))
         (condition-case nil
             (haystack--frecency-replay
              (list :root (list :kind 'text :term "haystack")
                    :filters (list (list :term "filtering")
                                   (list :term "search")
                                   (list :term "extra"))))
           (error nil)))
       ;; No orphan haystack buffers should remain
       (let ((orphans (cl-remove-if-not
                       (lambda (buf)
                         (string-prefix-p "*haystack:" (buffer-name buf)))
                       (buffer-list))))
         (should (null orphans)))))))

;;;; Test 25 — Filename search runs volume gate

(ert-deftest haystack-io-test/filename-search-runs-volume-gate ()
  "Root /filename search calls `haystack--volume-gate' before returning results.
Confirms that the filename search path applies the same volume limit
as content searches."
  (haystack-io-test--with-corpus
   (let ((gate-called nil))
     (cl-letf (((symbol-function 'pop-to-buffer)    #'ignore)
               ((symbol-function 'switch-to-buffer) #'ignore)
               ((symbol-function 'yes-or-no-p)      (lambda (_) t))
               ((symbol-function 'haystack--volume-gate)
                (let ((orig (symbol-function 'haystack--volume-gate)))
                  (lambda (count-output)
                    (setq gate-called t)
                    (funcall orig count-output)))))
       (let ((buf (haystack-run-root-search "/emacs")))
         (unwind-protect
             (progn
               (should gate-called)
               (should (buffer-live-p buf)))
           (when (buffer-live-p buf) (kill-buffer buf))))))))

;;;; Test 26 — Discoverability counts capitalized tokens

(ert-deftest haystack-io-test/discoverability-counts-capitalized-tokens ()
  "Discoverability counts a term that appears only in capitalized form.
A note containing only 'Xyloquartz' (never lowercase) must still be
counted when we ask for the count of 'xyloquartz'.  Confirms the fix for
the [a-z0-9_-]+ parsing regex that previously dropped uppercase matches."
  (haystack-io-test--with-corpus
   (let ((test-note (expand-file-name "20260328000000-caps-test.org"
                                      haystack-notes-directory)))
     (with-temp-file test-note
       (insert "#+TITLE: Caps Test\n\nXyloquartz appears here.\n"))
     (let ((results (haystack--discoverability-count-all-terms '("xyloquartz"))))
       (should (assoc "xyloquartz" results))
       (should (>= (cdr (assoc "xyloquartz" results)) 1))))))

;;;; Test 27 — Date-range search end-to-end against demo corpus

(ert-deftest haystack-io-test/date-range-search-finds-stamped-notes ()
  "Date-range search returns notes with hs: timestamps within the range.
Verifies that the broad rg prefilter, elisp post-filter, and buffer setup
all produce grep-mode output from the demo corpus timestamp notes."
  (haystack-io-test--with-corpus
   (cl-letf (((symbol-function 'pop-to-buffer)    #'ignore)
             ((symbol-function 'switch-to-buffer) #'ignore)
             ((symbol-function 'yes-or-no-p)      (lambda (_) t)))
     (let ((buf (haystack-search-date-range "2025-01" "2025-03")))
       (unwind-protect
           (progn
             (should (buffer-live-p buf))
             (with-current-buffer buf
               ;; Output must contain results from all three timestamp notes.
               (should (string-match-p "standup-log" (buffer-string)))
               (should (string-match-p "reading-log" (buffer-string)))
               (should (string-match-p "weekly-review" (buffer-string)))
               ;; Every non-header output line must be in grep-mode format.
               (let ((content-lines
                      (cl-remove-if
                       (lambda (l) (or (string-match-p "\\`;;;;" l)
                                       (string= l "")))
                       (split-string (buffer-string) "\n" t))))
                 (should content-lines)
                 (dolist (line content-lines)
                   (should (string-match-p "\\`.+:[0-9]+:" line))))))
         (when (buffer-live-p buf) (kill-buffer buf)))))))

;;;; Test 28 — Date-range partial hit (single month)

(ert-deftest haystack-io-test/date-range-search-partial-hit ()
  "Date-range search scoped to January 2025 finds only January notes.
The February and March timestamp notes must not appear."
  (haystack-io-test--with-corpus
   (cl-letf (((symbol-function 'pop-to-buffer)    #'ignore)
             ((symbol-function 'switch-to-buffer) #'ignore)
             ((symbol-function 'yes-or-no-p)      (lambda (_) t)))
     (let ((buf (haystack-search-date-range "2025-01" "2025-01")))
       (unwind-protect
           (progn
             (should (buffer-live-p buf))
             (with-current-buffer buf
               (should     (string-match-p "standup-log"   (buffer-string)))
               (should-not (string-match-p "reading-log"   (buffer-string)))
               (should-not (string-match-p "weekly-review" (buffer-string)))))
         (when (buffer-live-p buf) (kill-buffer buf)))))))

;;;; Test 29 — Filter-further after date-root

(ert-deftest haystack-io-test/date-range-filter-further ()
  "haystack-filter-further works correctly on a date-root results buffer.
A keyword filter applied after a date-range search must narrow to only
notes matching both the date range and the keyword."
  (haystack-io-test--with-corpus
   (cl-letf (((symbol-function 'pop-to-buffer)    #'ignore)
             ((symbol-function 'switch-to-buffer) #'ignore)
             ((symbol-function 'yes-or-no-p)      (lambda (_) t)))
     (let ((root-buf (haystack-search-date-range "2025-01" "2025-03")))
       (unwind-protect
           (progn
             (should (buffer-live-p root-buf))
             (with-current-buffer root-buf
               (haystack-filter-further "zettelkasten"))
             (let ((child-buf
                    (car (seq-filter
                          (lambda (b)
                            (and (string-match-p "haystack:" (buffer-name b))
                                 (string-match-p "zettelkasten" (buffer-name b))))
                          (buffer-list)))))
               (unwind-protect
                   (progn
                     (should child-buf)
                     (with-current-buffer child-buf
                       ;; Only the reading-log note mentions zettelkasten.
                       (should (string-match-p "reading-log" (buffer-string)))
                       (should-not (string-match-p "standup-log" (buffer-string)))))
                 (when (and child-buf (buffer-live-p child-buf))
                   (kill-buffer child-buf)))))
         (when (buffer-live-p root-buf) (kill-buffer root-buf)))))))

;;;; Test 30 — Frecency replay of a date-root search

(ert-deftest haystack-io-test/frecency-replay-date-root ()
  "Frecency replay of a date-root key dispatches to haystack-search-date-range.
The replayed buffer must contain the same hs: timestamp results as a
fresh date-range search."
  (haystack-io-test--with-corpus
   (cl-letf (((symbol-function 'pop-to-buffer)    #'ignore)
             ((symbol-function 'switch-to-buffer) #'ignore)
             ((symbol-function 'yes-or-no-p)      (lambda (_) t)))
     (let* ((key (list :root (list :kind 'date-range :start "2025-02" :end "2025-02")
                       :filters nil))
            (buf (haystack--frecency-replay key)))
       (unwind-protect
           (progn
             (should (buffer-live-p buf))
             (with-current-buffer buf
               ;; Replayed date search must find February notes.
               (should (string-match-p "reading-log" (buffer-string)))
               ;; January/March notes must not appear.
               (should-not (string-match-p "standup-log"   (buffer-string)))
               (should-not (string-match-p "weekly-review" (buffer-string)))))
         (when (buffer-live-p buf) (kill-buffer buf)))))))

;;;; Test 31 — haystack-filter-further-by-date narrows a results buffer by date

(ert-deftest haystack-io-test/filter-further-by-date-narrows-results ()
  "filter-further-by-date applied to a text-root buffer keeps only dated matches."
  (haystack-io-test--with-corpus
   (cl-letf (((symbol-function 'pop-to-buffer)    #'ignore)
             ((symbol-function 'switch-to-buffer) #'ignore)
             ((symbol-function 'yes-or-no-p)      (lambda (_) t)))
     ;; Root search finds all demo notes containing hs: timestamps.
     (let ((root-buf (haystack-run-root-search "hs:")))
       (unwind-protect
           (progn
             (should (bufferp root-buf))
             ;; Filter the results buffer to only January 2025.
             (let ((child-buf (with-current-buffer root-buf
                                (haystack-filter-further-by-date "2025-01" "2025-01"))))
               (unwind-protect
                   (progn
                     (should (bufferp child-buf))
                     (with-current-buffer child-buf
                       ;; January standup note should appear.
                       (should (string-match-p "standup-log" (buffer-string)))
                       ;; February and March notes must not appear.
                       (should-not (string-match-p "reading-log"  (buffer-string)))
                       (should-not (string-match-p "weekly-review" (buffer-string)))))
                 (when (buffer-live-p child-buf) (kill-buffer child-buf)))))
         (when (buffer-live-p root-buf) (kill-buffer root-buf)))))))

;;;; Test — View toggle preserves filter-further

(ert-deftest haystack-io-test/view-toggle-preserves-filter ()
  "Toggling to compact view does not interfere with `haystack-filter-further'.
The child buffer should have valid results because `buffer-string' returns
raw text regardless of overlays."
  (haystack-io-test--with-corpus
    (cl-letf (((symbol-function 'pop-to-buffer)    #'ignore)
              ((symbol-function 'switch-to-buffer) #'ignore)
              ((symbol-function 'yes-or-no-p)      (lambda (_) t)))
      (let ((root-buf (haystack-run-root-search "haystack")))
        (unwind-protect
            (with-current-buffer root-buf
              ;; Toggle to compact, then filter.
              (haystack-view-compact)
              (let ((child-buf (haystack-filter-further "emacs")))
                (unwind-protect
                    (with-current-buffer child-buf
                      (let ((content (buffer-string)))
                        ;; Should have at least one result line.
                        (should (string-match-p "[^:]+:[0-9]+:.+" content))))
                  (when (buffer-live-p child-buf) (kill-buffer child-buf)))))
          (when (buffer-live-p root-buf) (kill-buffer root-buf)))))))

;;;; Test — View toggle preserves MOC

(ert-deftest haystack-io-test/view-toggle-preserves-moc ()
  "Toggling to files view does not affect `haystack-copy-moc' loci count.
The MOC should contain the same number of unique files as the full view."
  (haystack-io-test--with-corpus
    (cl-letf (((symbol-function 'pop-to-buffer)    #'ignore)
              ((symbol-function 'switch-to-buffer) #'ignore)
              ((symbol-function 'yes-or-no-p)      (lambda (_) t)))
      (let ((root-buf (haystack-run-root-search "haystack")))
        (unwind-protect
            (with-current-buffer root-buf
              ;; Count unique files in full view.
              (let* ((full-files (length (haystack--extract-filenames (buffer-string)))))
                ;; Toggle to files view, copy MOC.
                (haystack-view-files)
                (haystack-copy-moc)
                ;; The MOC loci count should match.
                (should (= (length haystack--last-moc) full-files))))
          (when (buffer-live-p root-buf) (kill-buffer root-buf)))))))

(provide 'haystack-io-test)
;;; haystack-io-test.el ends here
