;;; haystack-bench.el --- Performance benchmarks for haystack.el -*- lexical-binding: t -*-

;;; Commentary:
;; Timing assertions integrated into the ERT suite.  Each test generates
;; synthetic rg output at a given scale and asserts that the function under
;; test completes in under 1 second.  A failure means something has gone
;; wrong algorithmically -- not that the machine is slow.
;;
;; Scales tested:
;;   10k lines  — realistic ceiling for a large corpus with a broad search term
;;   100k lines — stress / outlier (100k+ note corpus, every note matched)
;;
;; Functions covered:
;;   haystack--count-search-stats          — unique-file + match counting
;;   haystack--truncate-output             — per-line content windowing
;;   haystack--extract-filenames           — filelist extraction (filter hot path)
;;   haystack--strip-notes-prefix          — path shortening before display
;;   haystack--extract-file-loci           — file+line extraction for MOC
;;   haystack--discoverability-tokenize    — note text → token list (stop-word filter, dedup)
;;   haystack--discoverability-render      — term-count alist → org buffer string
;;
;; Run from the repo root with:
;;   emacs --batch -l ert -l haystack.el -l test/haystack-test.el \
;;         -l test/haystack-bench.el -f ert-run-tests-batch-and-exit

;;; Code:

(require 'ert)
(require 'benchmark)
(require 'haystack)

;;;; Helpers

(defun haystack-bench--make-rg-output (n-lines pattern)
  "Return a string of N-LINES synthetic rg output lines containing PATTERN.
Each line is a realistic file:line:content triple with long content so
that the truncation path is exercised, not just the short-circuit."
  (let ((lines (make-vector n-lines nil)))
    (dotimes (i n-lines)
      (aset lines i
            (format "/notes/%014d-synthetic-note.org:%d:%s %s %s"
                    i (1+ i)
                    (make-string 40 ?a)
                    pattern
                    (make-string 40 ?b))))
    (mapconcat #'identity lines "\n")))

(defmacro haystack-bench--within-500ms (label &rest body)
  "Evaluate BODY once, assert it completes in under 500ms, print LABEL.
Used for realistic-scale tests (10k lines).  A failure here means the
function is too slow for normal interactive use."
  (declare (indent 1))
  `(let ((elapsed (car (benchmark-run 1 ,@body))))
     (message "haystack-bench: %s — %.4fs" ,label elapsed)
     (should (< elapsed 0.5))))

(defmacro haystack-bench--within-2s (label &rest body)
  "Evaluate BODY once, assert it completes in under 2 seconds, print LABEL.
Used for stress-scale tests (100k lines).  A failure here means something
has gone algorithmically wrong — O(N²) or worse — not just a slow machine."
  (declare (indent 1))
  `(let ((elapsed (car (benchmark-run 1 ,@body))))
     (message "haystack-bench: %s — %.4fs" ,label elapsed)
     (should (< elapsed 2.0))))

;;;; haystack--count-search-stats

(ert-deftest haystack-bench/count-stats-10k ()
  "haystack--count-search-stats handles 10,000 lines in under 1 second."
  (let ((output (haystack-bench--make-rg-output 10000 "rust")))
    (haystack-bench--within-500ms "count-stats 10k lines"
      (haystack--count-search-stats output))))

(ert-deftest haystack-bench/count-stats-100k ()
  "haystack--count-search-stats handles 100,000 lines in under 2 seconds."
  (let ((output (haystack-bench--make-rg-output 100000 "rust")))
    (haystack-bench--within-2s "count-stats 100k lines"
      (haystack--count-search-stats output))))

;;;; haystack--truncate-output

(ert-deftest haystack-bench/truncate-output-10k ()
  "haystack--truncate-output handles 10,000 lines in under 1 second."
  (let ((output (haystack-bench--make-rg-output 10000 "rust")))
    (haystack-bench--within-500ms "truncate-output 10k lines"
      (haystack--truncate-output output "rust"))))

(ert-deftest haystack-bench/truncate-output-100k ()
  "haystack--truncate-output handles 100,000 lines in under 2 seconds."
  (let ((output (haystack-bench--make-rg-output 100000 "rust")))
    (haystack-bench--within-2s "truncate-output 100k lines"
      (haystack--truncate-output output "rust"))))

;;;; haystack--extract-filenames
;;
;; This is on the filter-further hot path: every `f' keypress calls
;; (haystack--extract-filenames (buffer-string)) to build the filelist
;; for the next rg invocation.  Degradation here means sluggish filtering.

(ert-deftest haystack-bench/extract-filenames-10k ()
  "haystack--extract-filenames handles 10,000 lines in under 1 second."
  (let ((output (haystack-bench--make-rg-output 10000 "rust"))
        (default-directory "/notes/"))
    (haystack-bench--within-500ms "extract-filenames 10k lines"
      (haystack--extract-filenames output))))

(ert-deftest haystack-bench/extract-filenames-100k ()
  "haystack--extract-filenames handles 100,000 lines in under 2 seconds."
  (let ((output (haystack-bench--make-rg-output 100000 "rust"))
        (default-directory "/notes/"))
    (haystack-bench--within-2s "extract-filenames 100k lines"
      (haystack--extract-filenames output))))

;;;; haystack--strip-notes-prefix
;;
;; Called on all rg output before it is inserted into a results buffer —
;; both on root search and on every filter.  Degradation adds latency to
;; every visible search result.

(ert-deftest haystack-bench/strip-notes-prefix-10k ()
  "haystack--strip-notes-prefix handles 10,000 lines in under 1 second."
  (let ((output (haystack-bench--make-rg-output 10000 "rust"))
        (haystack-notes-directory "/notes"))
    (haystack-bench--within-500ms "strip-notes-prefix 10k lines"
      (haystack--strip-notes-prefix output))))

(ert-deftest haystack-bench/strip-notes-prefix-100k ()
  "haystack--strip-notes-prefix handles 100,000 lines in under 2 seconds."
  (let ((output (haystack-bench--make-rg-output 100000 "rust"))
        (haystack-notes-directory "/notes"))
    (haystack-bench--within-2s "strip-notes-prefix 100k lines"
      (haystack--strip-notes-prefix output))))

;;;; haystack--extract-file-loci
;;
;; Used by the MOC generator to collect the first match per file.
;; Less latency-sensitive than filtering (it is a deliberate `c' action),
;; but the same parsing pattern — a regression here often signals a
;; broader algorithmic problem.

(ert-deftest haystack-bench/extract-file-loci-10k ()
  "haystack--extract-file-loci handles 10,000 lines in under 1 second."
  (let ((output (haystack-bench--make-rg-output 10000 "rust"))
        (default-directory "/notes/"))
    (haystack-bench--within-500ms "extract-file-loci 10k lines"
      (haystack--extract-file-loci output))))

(ert-deftest haystack-bench/extract-file-loci-100k ()
  "haystack--extract-file-loci handles 100,000 lines in under 2 seconds."
  (let ((output (haystack-bench--make-rg-output 100000 "rust"))
        (default-directory "/notes/"))
    (haystack-bench--within-2s "extract-file-loci 100k lines"
      (haystack--extract-file-loci output))))

;;;; haystack--tree-render-node
;;
;; The tree renderer is recursive and calls haystack--children-of once
;; per node.  haystack--children-of scans all live haystack buffers, so
;; render time is O(N²) in the number of open buffers.  This is
;; acceptable at normal use, but will degrade if the algorithm changes.
;;
;; Realistic: ~50 buffers (a few weeks of active use, several root
;;   searches each with a handful of filter children).
;; Aggressive: 500 buffers (worst-case long-lived session).
;;
;; Structure: N roots, each with C children, each child with G
;;   grandchildren.  This exercises both breadth (sibling iteration)
;;   and depth (recursion depth), and keeps the parent-pointer fan-out
;;   realistic (each node has at most G or C children, not one giant fan).

(defun haystack-bench--make-forest (n-roots children-per-root grandchildren-per-child)
  "Create a forest of live haystack buffers and return them as a list.
N-ROOTS root buffers each get CHILDREN-PER-ROOT children, each of which
gets GRANDCHILDREN-PER-CHILD grandchildren.  Every buffer has the minimum
buffer-local state required by haystack--tree-render-node.
Caller must kill all returned buffers when done."
  (let (all-bufs)
    (dotimes (r n-roots)
      (let* ((root-desc (list :root-term     (format "root%d" r)
                              :root-filename nil :root-literal nil :root-regex nil
                              :filters       nil))
             (root-buf  (get-buffer-create (format " *hs-bench-%d*" r))))
        (with-current-buffer root-buf
          (setq haystack--search-descriptor root-desc
                haystack--parent-buffer     nil))
        (push root-buf all-bufs)
        (dotimes (c children-per-root)
          (let* ((child-desc (list :root-term     (format "root%d" r)
                                   :root-filename nil :root-literal nil :root-regex nil
                                   :filters       (list (list :term     (format "f%d" c)
                                                              :negated  nil :filename nil
                                                              :literal  nil :regex    nil))))
                 (child-buf  (get-buffer-create (format " *hs-bench-%d-%d*" r c))))
            (with-current-buffer child-buf
              (setq haystack--search-descriptor child-desc
                    haystack--parent-buffer     root-buf))
            (push child-buf all-bufs)
            (dotimes (g grandchildren-per-child)
              (let* ((gc-desc (list :root-term     (format "root%d" r)
                                    :root-filename nil :root-literal nil :root-regex nil
                                    :filters       (list (list :term     (format "f%d" c)
                                                               :negated  nil :filename nil
                                                               :literal  nil :regex    nil)
                                                         (list :term     (format "g%d" g)
                                                               :negated  nil :filename nil
                                                               :literal  nil :regex    nil))))
                     (gc-buf  (get-buffer-create (format " *hs-bench-%d-%d-%d*" r c g))))
                (with-current-buffer gc-buf
                  (setq haystack--search-descriptor gc-desc
                        haystack--parent-buffer     child-buf))
                (push gc-buf all-bufs)))))))
    (nreverse all-bufs)))

(defmacro haystack-bench--with-forest (roots-var args &rest body)
  "Bind ROOTS-VAR to the root buffers of a forest built by ARGS, run BODY.
ARGS is a list (N-ROOTS CHILDREN GRANDCHILDREN) forwarded to
`haystack-bench--make-forest'.  All created buffers are killed on exit,
even if an error occurs during setup."
  (declare (indent 2))
  (let ((all-var (make-symbol "all-bufs")))
    `(let ((,all-var (apply #'haystack-bench--make-forest ',args)))
       (unwind-protect
           (let ((,roots-var (cl-remove-if
                              (lambda (b)
                                (buffer-local-value 'haystack--parent-buffer b))
                              ,all-var)))
             ,@body)
         (dolist (b ,all-var)
           (when (buffer-live-p b) (kill-buffer b)))))))

(defun haystack-bench--render-forest (roots)
  "Render all ROOTS into a temp buffer, exercising the full recursive renderer."
  (with-temp-buffer
    (dolist (root roots)
      (haystack--tree-render-node root nil "" "" 0)
      (insert "\n"))))

;; Realistic: 5 roots × 3 children × 3 grandchildren = 5+15+45 = 65 buffers
(ert-deftest haystack-bench/tree-render-realistic ()
  "Tree renderer handles a realistic session (~65 buffers) in under 500ms."
  (haystack-bench--with-forest roots (5 3 3)
    (haystack-bench--within-500ms "tree-render realistic (~65 bufs)"
      (haystack-bench--render-forest roots))))

;; Aggressive: 10 roots × 7 children × 7 grandchildren = 10+70+490 = 570 buffers
(ert-deftest haystack-bench/tree-render-stress ()
  "Tree renderer handles an extreme session (~570 buffers) in under 500ms."
  (haystack-bench--with-forest roots (10 7 7)
    (haystack-bench--within-500ms "tree-render stress (~570 bufs)"
      (haystack-bench--render-forest roots))))

;;;; haystack--discoverability-tokenize
;;
;; The primary cost of `haystack-describe-discoverability' has two parts:
;;   1. Tokenization — pure Elisp on the note text (benched here)
;;   2. N rg invocations — one per unique token (I/O-bound; cannot be
;;      unit-benched, but each call is bounded by rg's own latency)
;;
;; Tokenization must remain sub-linear in output size even for very large
;; notes.  Regressions here multiply across every term in the corpus.

(defun haystack-bench--make-note-text (n-words)
  "Return a synthetic note string of N-WORDS space-separated tokens.
The vocabulary includes stop words, punctuation-flanked words, and
hyphenated/underscored compound terms to exercise the full tokenization
path: split, downcase, stop-word filter, dedup."
  (let* ((vocab '("rust" "async" "tokio" "bevy" "emacs" "lisp" "haskell"
                  "programming" "coding" "system" "function" "method" "value"
                  "the" "and" "is" "a" "an" "of" "in" "to" "for" "with"
                  "word-word" "under_score" "multi-term" "file_path" "emacs-lisp"))
         (vocab-len (length vocab))
         (parts (make-vector n-words nil)))
    (dotimes (i n-words)
      (aset parts i (nth (mod i vocab-len) vocab)))
    (mapconcat #'identity parts " ")))

(ert-deftest haystack-bench/discoverability-tokenize-10k-words ()
  "haystack--discoverability-tokenize handles a 10k-word note in under 500ms."
  (let ((text (haystack-bench--make-note-text 10000))
        (haystack--stop-words haystack--default-stop-words)
        (haystack-discoverability-split-compound-words nil))
    (haystack-bench--within-500ms "discoverability-tokenize 10k words"
      (haystack--discoverability-tokenize text))))

(ert-deftest haystack-bench/discoverability-tokenize-100k-words ()
  "haystack--discoverability-tokenize handles a 100k-word note in under 2s."
  (let ((text (haystack-bench--make-note-text 100000))
        (haystack--stop-words haystack--default-stop-words)
        (haystack-discoverability-split-compound-words nil))
    (haystack-bench--within-2s "discoverability-tokenize 100k words"
      (haystack--discoverability-tokenize text))))

;;;; haystack--discoverability-render
;;
;; After all rg calls complete, `haystack--discoverability-render' must
;; sort N terms into four tier sections and build the org string.
;; Realistic notes: a few hundred unique tokens after stop-word filtering.
;; Stress: 10k terms (implausibly large, but verifies O(N log N) sort).

(defun haystack-bench--make-term-counts (n-terms)
  "Return an alist of N-TERMS (TERM . COUNT) pairs spanning all four tiers."
  (let (result)
    (dotimes (i n-terms)
      (push (cons (format "term%d" i)
                  ;; Distribute evenly across tiers: isolated/sparse/connected/ubiquitous
                  (pcase (mod i 4)
                    (0 0)    ; isolated
                    (1 2)    ; sparse  (within default sparse-max of 3)
                    (2 50)   ; connected
                    (_ 600))) ; ubiquitous (above default ubiquitous-min of 500)
            result))
    result))

(ert-deftest haystack-bench/discoverability-render-1k-terms ()
  "haystack--discoverability-render handles 1k terms in under 500ms."
  (let ((tc (haystack-bench--make-term-counts 1000))
        (haystack-discoverability-sparse-max 3)
        (haystack-discoverability-ubiquitous-min 500)
        (haystack-notes-directory "/notes"))
    (haystack-bench--within-500ms "discoverability-render 1k terms"
      (haystack--discoverability-render
       tc "/notes/20241215120000-bench-note.org"))))

(ert-deftest haystack-bench/discoverability-render-10k-terms ()
  "haystack--discoverability-render handles 10k terms in under 2s."
  (let ((tc (haystack-bench--make-term-counts 10000))
        (haystack-discoverability-sparse-max 3)
        (haystack-discoverability-ubiquitous-min 500)
        (haystack-notes-directory "/notes"))
    (haystack-bench--within-2s "discoverability-render 10k terms"
      (haystack--discoverability-render
       tc "/notes/20241215120000-bench-note.org"))))

(provide 'haystack-bench)
;;; haystack-bench.el ends here
