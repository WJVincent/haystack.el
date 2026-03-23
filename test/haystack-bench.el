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

(defmacro haystack-bench--within-1s (label &rest body)
  "Evaluate BODY once, assert it completes in under 1 second, print LABEL."
  (declare (indent 1))
  `(let ((elapsed (car (benchmark-run 1 ,@body))))
     (message "haystack-bench: %s — %.4fs" ,label elapsed)
     (should (< elapsed 1.0))))

;;;; haystack--count-search-stats

(ert-deftest haystack-bench/count-stats-10k ()
  "haystack--count-search-stats handles 10,000 lines in under 1 second."
  (let ((output (haystack-bench--make-rg-output 10000 "rust")))
    (haystack-bench--within-1s "count-stats 10k lines"
      (haystack--count-search-stats output))))

(ert-deftest haystack-bench/count-stats-100k ()
  "haystack--count-search-stats handles 100,000 lines in under 1 second."
  (let ((output (haystack-bench--make-rg-output 100000 "rust")))
    (haystack-bench--within-1s "count-stats 100k lines"
      (haystack--count-search-stats output))))

;;;; haystack--truncate-output

(ert-deftest haystack-bench/truncate-output-10k ()
  "haystack--truncate-output handles 10,000 lines in under 1 second."
  (let ((output (haystack-bench--make-rg-output 10000 "rust")))
    (haystack-bench--within-1s "truncate-output 10k lines"
      (haystack--truncate-output output "rust"))))

(ert-deftest haystack-bench/truncate-output-100k ()
  "haystack--truncate-output handles 100,000 lines in under 1 second."
  (let ((output (haystack-bench--make-rg-output 100000 "rust")))
    (haystack-bench--within-1s "truncate-output 100k lines"
      (haystack--truncate-output output "rust"))))

(provide 'haystack-bench)
;;; haystack-bench.el ends here
