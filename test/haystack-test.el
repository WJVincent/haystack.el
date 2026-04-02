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
         (haystack--expansion-groups-loaded nil)
         (haystack--stop-words-loaded nil))
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

(defun haystack-test--tkey (term &rest filter-terms)
  "Return a text-root frecency key for TERM with plain string FILTER-TERMS.
Each element of FILTER-TERMS becomes a filter plist (:term ELEM).
For tests that only need simple unmodified filter terms."
  (list :root (list :kind 'text :term term)
        :filters (mapcar (lambda (ft) (list :term ft)) filter-terms)))

(defun haystack-test--has-sentinel (str)
  "Return non-nil if STR contains the haystack-end-frontmatter sentinel."
  (string-match-p (regexp-quote haystack--sentinel-string) str))

;;;; haystack--timestamp

(ert-deftest haystack-test/timestamp-is-14-digits ()
  "Timestamp returns a string of exactly 14 digits."
  (should (string-match-p "\\`[0-9]\\{14\\}\\'" (haystack--timestamp))))

;;;; haystack--format-hs-timestamp

(ert-deftest haystack-test/format-hs-timestamp-active-with-time ()
  "Active timestamp with time uses angle brackets and includes HH:MM."
  (let* ((time   (encode-time 0 30 14 15 6 2024))
         (result (haystack--format-hs-timestamp time)))
    (should (equal result "hs: <2024-06-15 Sat 14:30>"))))

(ert-deftest haystack-test/format-hs-timestamp-inactive-with-time ()
  "Inactive timestamp with time uses square brackets."
  (let* ((time   (encode-time 0 30 14 15 6 2024))
         (result (haystack--format-hs-timestamp time t)))
    (should (equal result "hs: [2024-06-15 Sat 14:30]"))))

(ert-deftest haystack-test/format-hs-timestamp-active-date-only ()
  "Active date-only timestamp omits time component."
  (let* ((time   (encode-time 0 30 14 15 6 2024))
         (result (haystack--format-hs-timestamp time nil t)))
    (should (equal result "hs: <2024-06-15 Sat>"))))

(ert-deftest haystack-test/format-hs-timestamp-inactive-date-only ()
  "Inactive date-only timestamp uses square brackets with no time."
  (let* ((time   (encode-time 0 30 14 15 6 2024))
         (result (haystack--format-hs-timestamp time t t)))
    (should (equal result "hs: [2024-06-15 Sat]"))))

;;;; haystack-insert-timestamp-now

(ert-deftest haystack-test/insert-timestamp-now-active-pattern ()
  "`haystack-insert-timestamp-now' inserts an active hs: timestamp."
  (with-temp-buffer
    (haystack-insert-timestamp-now)
    (should (string-match-p
             "\\`hs: <[0-9]\\{4\\}-[0-9]\\{2\\}-[0-9]\\{2\\} [A-Z][a-z]\\{2\\} [0-9]\\{2\\}:[0-9]\\{2\\}>\\'"
             (buffer-string)))))

(ert-deftest haystack-test/insert-timestamp-now-inactive ()
  "`haystack-insert-timestamp-now' with non-nil arg uses square brackets."
  (with-temp-buffer
    (haystack-insert-timestamp-now t)
    (should (string-match-p
             "\\`hs: \\[[0-9]\\{4\\}-[0-9]\\{2\\}-[0-9]\\{2\\} [A-Z][a-z]\\{2\\} [0-9]\\{2\\}:[0-9]\\{2\\}\\]\\'"
             (buffer-string)))))

;;;; haystack-insert-timestamp

(ert-deftest haystack-test/insert-timestamp-date-only ()
  "`haystack-insert-timestamp' with YYYY-MM-DD produces a date-only stamp."
  (with-temp-buffer
    (cl-letf (((symbol-function 'read-string) (lambda (&rest _) "2024-06-15")))
      (haystack-insert-timestamp))
    (should (equal (buffer-string) "hs: <2024-06-15 Sat>"))))

(ert-deftest haystack-test/insert-timestamp-with-time ()
  "`haystack-insert-timestamp' with YYYY-MM-DD HH:MM produces a full stamp."
  (with-temp-buffer
    (cl-letf (((symbol-function 'read-string) (lambda (&rest _) "2024-06-15 14:30")))
      (haystack-insert-timestamp))
    (should (equal (buffer-string) "hs: <2024-06-15 Sat 14:30>"))))

(ert-deftest haystack-test/insert-timestamp-inactive-date-only ()
  "`haystack-insert-timestamp' with inactive prefix uses square brackets."
  (with-temp-buffer
    (cl-letf (((symbol-function 'read-string) (lambda (&rest _) "2024-06-15")))
      (haystack-insert-timestamp t))
    (should (equal (buffer-string) "hs: [2024-06-15 Sat]"))))

(ert-deftest haystack-test/insert-timestamp-inactive-with-time ()
  "`haystack-insert-timestamp' inactive with time uses square brackets."
  (with-temp-buffer
    (cl-letf (((symbol-function 'read-string) (lambda (&rest _) "2024-06-15 14:30")))
      (haystack-insert-timestamp t))
    (should (equal (buffer-string) "hs: [2024-06-15 Sat 14:30]"))))

(ert-deftest haystack-test/insert-timestamp-invalid-input ()
  "`haystack-insert-timestamp' signals user-error on bad input."
  (with-temp-buffer
    (cl-letf (((symbol-function 'read-string) (lambda (&rest _) "not-a-date")))
      (should-error (haystack-insert-timestamp) :type 'user-error))))

;;;; haystack--parse-date-bound

;; Empty / whitespace

(ert-deftest haystack-test/parse-date-bound-empty-nil ()
  "Empty string returns nil for both start and end."
  (should (null (haystack--parse-date-bound "" nil)))
  (should (null (haystack--parse-date-bound "" t))))

(ert-deftest haystack-test/parse-date-bound-whitespace-nil ()
  "Whitespace-only string returns nil."
  (should (null (haystack--parse-date-bound "   " nil))))

;; Year only

(ert-deftest haystack-test/parse-date-bound-year-start ()
  "YYYY lower bound resolves to Jan 1 at midnight."
  (should (= (haystack--parse-date-bound "2024" nil)
             (float-time (encode-time 0 0 0 1 1 2024)))))

(ert-deftest haystack-test/parse-date-bound-year-end ()
  "YYYY upper bound resolves to Dec 31 at 23:59:59."
  (should (= (haystack--parse-date-bound "2024" t)
             (float-time (encode-time 59 59 23 31 12 2024)))))

;; Year and month

(ert-deftest haystack-test/parse-date-bound-month-start ()
  "YYYY-MM lower bound resolves to first of month at midnight."
  (should (= (haystack--parse-date-bound "2024-06" nil)
             (float-time (encode-time 0 0 0 1 6 2024)))))

(ert-deftest haystack-test/parse-date-bound-month-end ()
  "YYYY-MM upper bound resolves to last day of month at 23:59:59."
  (should (= (haystack--parse-date-bound "2024-06" t)
             (float-time (encode-time 59 59 23 30 6 2024)))))

(ert-deftest haystack-test/parse-date-bound-feb-leap-end ()
  "Feb in a leap year ends on the 29th."
  (should (= (haystack--parse-date-bound "2024-02" t)
             (float-time (encode-time 59 59 23 29 2 2024)))))

(ert-deftest haystack-test/parse-date-bound-feb-nonleap-end ()
  "Feb in a non-leap year ends on the 28th."
  (should (= (haystack--parse-date-bound "2023-02" t)
             (float-time (encode-time 59 59 23 28 2 2023)))))

;; Full date

(ert-deftest haystack-test/parse-date-bound-day-start ()
  "YYYY-MM-DD lower bound resolves to midnight."
  (should (= (haystack--parse-date-bound "2024-06-15" nil)
             (float-time (encode-time 0 0 0 15 6 2024)))))

(ert-deftest haystack-test/parse-date-bound-day-end ()
  "YYYY-MM-DD upper bound resolves to 23:59:59."
  (should (= (haystack--parse-date-bound "2024-06-15" t)
             (float-time (encode-time 59 59 23 15 6 2024)))))

;; Exact point

(ert-deftest haystack-test/parse-date-bound-exact-start ()
  "YYYY-MM-DD HH:MM is exact when upper-p is nil."
  (should (= (haystack--parse-date-bound "2024-06-15 14:30" nil)
             (float-time (encode-time 0 30 14 15 6 2024)))))

(ert-deftest haystack-test/parse-date-bound-exact-upper ()
  "YYYY-MM-DD HH:MM is exact even when upper-p is t."
  (should (= (haystack--parse-date-bound "2024-06-15 14:30" t)
             (float-time (encode-time 0 30 14 15 6 2024)))))

;; Malformed month / day / time

(ert-deftest haystack-test/parse-date-bound-bad-month-high ()
  "Month 13 signals user-error."
  (should-error (haystack--parse-date-bound "2024-13" nil) :type 'user-error))

(ert-deftest haystack-test/parse-date-bound-bad-month-zero ()
  "Month 0 signals user-error."
  (should-error (haystack--parse-date-bound "2024-00" nil) :type 'user-error))

(ert-deftest haystack-test/parse-date-bound-bad-day-high ()
  "Day 32 signals user-error."
  (should-error (haystack--parse-date-bound "2024-06-32" nil) :type 'user-error))

(ert-deftest haystack-test/parse-date-bound-bad-day-zero ()
  "Day 0 signals user-error."
  (should-error (haystack--parse-date-bound "2024-06-00" nil) :type 'user-error))

(ert-deftest haystack-test/parse-date-bound-feb30 ()
  "Feb 30 signals user-error."
  (should-error (haystack--parse-date-bound "2024-02-30" nil) :type 'user-error))

(ert-deftest haystack-test/parse-date-bound-feb29-nonleap ()
  "Feb 29 in a non-leap year signals user-error."
  (should-error (haystack--parse-date-bound "2023-02-29" nil) :type 'user-error))

(ert-deftest haystack-test/parse-date-bound-feb29-leap-ok ()
  "Feb 29 in a leap year does not signal an error."
  (should (haystack--parse-date-bound "2024-02-29" nil)))

(ert-deftest haystack-test/parse-date-bound-bad-hour ()
  "Hour 24 signals user-error."
  (should-error (haystack--parse-date-bound "2024-06-15 24:00" nil) :type 'user-error))

(ert-deftest haystack-test/parse-date-bound-bad-minute ()
  "Minute 60 signals user-error."
  (should-error (haystack--parse-date-bound "2024-06-15 10:60" nil) :type 'user-error))

(ert-deftest haystack-test/parse-date-bound-malformed ()
  "Completely malformed input signals user-error."
  (should-error (haystack--parse-date-bound "not-a-date" nil) :type 'user-error))

;;;; haystack--resolve-date-range

(ert-deftest haystack-test/resolve-date-range-empty-start ()
  "Empty start resolves lo to -infinity."
  (should (= (car (haystack--resolve-date-range "" "2024")) -1.0e+INF)))

(ert-deftest haystack-test/resolve-date-range-empty-end ()
  "Empty end resolves hi to +infinity."
  (should (= (cdr (haystack--resolve-date-range "2024" "")) 1.0e+INF)))

(ert-deftest haystack-test/resolve-date-range-both-empty ()
  "Both bounds empty gives (-inf . +inf)."
  (let ((r (haystack--resolve-date-range "" "")))
    (should (= (car r) -1.0e+INF))
    (should (= (cdr r)  1.0e+INF))))

(ert-deftest haystack-test/resolve-date-range-normal ()
  "Normal year range lo/hi are correct float-times."
  (let* ((r  (haystack--resolve-date-range "2024-01" "2024-03"))
         (lo (car r))
         (hi (cdr r)))
    (should (= lo (float-time (encode-time 0 0 0 1 1 2024))))
    (should (= hi (float-time (encode-time 59 59 23 31 3 2024))))))

(ert-deftest haystack-test/resolve-date-range-reversed ()
  "Start after end signals user-error."
  (should-error (haystack--resolve-date-range "2024-06" "2024-01") :type 'user-error))

(ert-deftest haystack-test/resolve-date-range-same-day ()
  "Start and end on same day spans the full day."
  (let* ((r  (haystack--resolve-date-range "2024-06-15" "2024-06-15"))
         (lo (car r))
         (hi (cdr r)))
    (should (= lo (float-time (encode-time 0 0 0 15 6 2024))))
    (should (= hi (float-time (encode-time 59 59 23 15 6 2024))))))

;;;; haystack--parse-hs-timestamp

(ert-deftest haystack-test/parse-hs-timestamp-active-with-time ()
  "Active hs: timestamp with time returns correct float and date-only=nil."
  (let* ((line   "notes/test.org:5:some text hs: <2024-06-15 Sat 14:30> end")
         (result (haystack--parse-hs-timestamp line)))
    (should result)
    (should (= (plist-get result :time)
               (float-time (encode-time 0 30 14 15 6 2024))))
    (should-not (plist-get result :date-only))))

(ert-deftest haystack-test/parse-hs-timestamp-inactive-with-time ()
  "Inactive hs: timestamp with time is matched correctly."
  (let* ((line   "notes/test.org:5:hs: [2024-06-15 Sat 14:30]")
         (result (haystack--parse-hs-timestamp line)))
    (should result)
    (should (= (plist-get result :time)
               (float-time (encode-time 0 30 14 15 6 2024))))
    (should-not (plist-get result :date-only))))

(ert-deftest haystack-test/parse-hs-timestamp-active-date-only ()
  "Active date-only hs: timestamp sets date-only=t."
  (let* ((line   "notes/test.org:3:hs: <2024-06-15 Sat>")
         (result (haystack--parse-hs-timestamp line)))
    (should result)
    (should (= (plist-get result :time)
               (float-time (encode-time 0 0 0 15 6 2024))))
    (should (plist-get result :date-only))))

(ert-deftest haystack-test/parse-hs-timestamp-inactive-date-only ()
  "Inactive date-only hs: timestamp sets date-only=t."
  (let* ((line   "notes/test.org:3:hs: [2024-06-15 Sat]")
         (result (haystack--parse-hs-timestamp line)))
    (should result)
    (should (plist-get result :date-only))))

(ert-deftest haystack-test/parse-hs-timestamp-no-match-returns-nil ()
  "Line with no hs: timestamp returns nil."
  (should-not (haystack--parse-hs-timestamp "notes/test.org:1:plain text")))

(ert-deftest haystack-test/parse-hs-timestamp-bare-org-ignored ()
  "Bare org timestamp without hs: prefix is ignored."
  (should-not (haystack--parse-hs-timestamp
               "notes/test.org:1:<2024-06-15 Sat 14:30>")))

(ert-deftest haystack-test/parse-hs-timestamp-embedded-in-grep-line ()
  "Timestamp embedded in a full grep-format line is found correctly."
  (let* ((line "notes/foo.org:10:created hs: <2024-02-29 Thu> in leap year")
         (result (haystack--parse-hs-timestamp line)))
    (should result)
    (should (plist-get result :date-only))))

;;;; haystack--filter-lines-by-date-range

(defun haystack-test--make-line (date-str)
  "Return a synthetic grep-format line embedding an hs: timestamp for DATE-STR."
  (format "notes/test.org:1:entry hs: <%s>" date-str))

(ert-deftest haystack-test/filter-lines-keeps-in-range ()
  "Lines whose timestamps fall within [lo, hi] are kept."
  (let* ((lo  (float-time (encode-time 0 0 0 1 6 2024)))
         (hi  (float-time (encode-time 59 59 23 30 6 2024)))
         (in  (haystack-test--make-line "2024-06-15 Sat 12:00"))
         (out (haystack-test--make-line "2024-07-01 Mon 00:00")))
    (let ((result (haystack--filter-lines-by-date-range (list in out) lo hi)))
      (should (equal result (list in))))))

(ert-deftest haystack-test/filter-lines-drops-no-timestamp ()
  "Lines without an hs: timestamp are dropped."
  (let* ((lo (float-time (encode-time 0 0 0 1 1 2024)))
         (hi (float-time (encode-time 59 59 23 31 12 2024))))
    (should (null (haystack--filter-lines-by-date-range
                   (list "notes/test.org:1:no stamp here") lo hi)))))

(ert-deftest haystack-test/filter-lines-boundary-inclusive ()
  "Boundaries are inclusive: timestamps exactly at lo and hi are kept."
  (let* ((lo (float-time (encode-time 0 0 14 15 6 2024)))
         (hi (float-time (encode-time 0 0 18 15 6 2024)))
         (at-lo (haystack-test--make-line "2024-06-15 Sat 14:00"))
         (at-hi (haystack-test--make-line "2024-06-15 Sat 18:00")))
    (let ((result (haystack--filter-lines-by-date-range (list at-lo at-hi) lo hi)))
      (should (member at-lo result))
      (should (member at-hi result)))))

(ert-deftest haystack-test/filter-lines-date-only-whole-day ()
  "Date-only stamp matches the full day regardless of time components on bounds."
  (let* (;; Bounds have time components: 10:00 to 18:00 on June 15
         (lo (float-time (encode-time 0 0 10 15 6 2024)))
         (hi (float-time (encode-time 0 0 18 15 6 2024)))
         ;; Date-only stamp for the same day — should match even though
         ;; its midnight is before lo's 10:00
         (stamp (haystack-test--make-line "2024-06-15 Sat")))
    (should (haystack--filter-lines-by-date-range (list stamp) lo hi))))

(ert-deftest haystack-test/filter-lines-date-only-outside-day-span ()
  "Date-only stamp for a day outside the range's day span is dropped."
  (let* ((lo (float-time (encode-time 0 0 0 15 6 2024)))
         (hi (float-time (encode-time 59 59 23 15 6 2024)))
         (stamp (haystack-test--make-line "2024-06-16 Sun")))
    (should (null (haystack--filter-lines-by-date-range (list stamp) lo hi)))))

(ert-deftest haystack-test/filter-lines-empty-result ()
  "Returns nil when no lines match."
  (let* ((lo (float-time (encode-time 0 0 0 1 1 2024)))
         (hi (float-time (encode-time 59 59 23 31 1 2024)))
         (lines (list (haystack-test--make-line "2024-06-15 Sat 12:00")
                      (haystack-test--make-line "2024-07-01 Mon 00:00"))))
    (should (null (haystack--filter-lines-by-date-range lines lo hi)))))

(ert-deftest haystack-test/filter-lines-unbounded-lo ()
  "Open lo (-inf) keeps all lines before hi."
  (let* ((hi   (float-time (encode-time 59 59 23 31 12 2023)))
         (line (haystack-test--make-line "2023-01-01 Sun 00:00")))
    (should (haystack--filter-lines-by-date-range (list line) -1.0e+INF hi))))

(ert-deftest haystack-test/filter-lines-unbounded-hi ()
  "Open hi (+inf) keeps all lines after lo."
  (let* ((lo   (float-time (encode-time 0 0 0 1 1 2025)))
         (line (haystack-test--make-line "2025-06-15 Sun 10:00")))
    (should (haystack--filter-lines-by-date-range (list line) lo 1.0e+INF))))

;;;; haystack--date-root-label

(ert-deftest haystack-test/date-root-label-full-range ()
  "Both bounds non-empty produce START..END."
  (should (equal (haystack--date-root-label "2024-01" "2024-03")
                 "2024-01..2024-03")))

(ert-deftest haystack-test/date-root-label-empty-start ()
  "Empty start produces ..END."
  (should (equal (haystack--date-root-label "" "2024-03") "..2024-03")))

(ert-deftest haystack-test/date-root-label-empty-end ()
  "Empty end produces START.. with no trailing wildcard."
  (should (equal (haystack--date-root-label "2024-01" "") "2024-01..")))

(ert-deftest haystack-test/date-root-label-both-empty ()
  "Both empty produces \"all\"."
  (should (equal (haystack--date-root-label "" "") "all")))

(ert-deftest haystack-test/date-root-label-whitespace-treated-as-empty ()
  "Whitespace-only bounds are treated as empty."
  (should (equal (haystack--date-root-label "  " "  ") "all")))

;;;; haystack--date-root-descriptor

(ert-deftest haystack-test/date-root-descriptor-has-kind ()
  "Date-root descriptor has :root-kind set to 'date-range."
  (let ((d (haystack--date-root-descriptor "2024-01" "2024-03")))
    (should (eq (haystack-sd-root-kind d) 'date-range))))

(ert-deftest haystack-test/date-root-descriptor-stores-raw-bounds ()
  "Descriptor stores raw start/end strings in :root-date-start/:root-date-end."
  (let ((d (haystack--date-root-descriptor "2024-01" "2024-03")))
    (should (equal (haystack-sd-root-date-start d) "2024-01"))
    (should (equal (haystack-sd-root-date-end d)   "2024-03"))))

(ert-deftest haystack-test/date-root-descriptor-root-term-is-label ()
  ":root-term equals the display label."
  (let ((d (haystack--date-root-descriptor "2024-01" "2024-03")))
    (should (equal (haystack-sd-root-term d) "2024-01..2024-03"))))

(ert-deftest haystack-test/date-root-descriptor-root-expanded-set ()
  ":root-expanded is set to the broad hs: prefilter pattern."
  (let ((d (haystack--date-root-descriptor "2024-01" "2024-03")))
    (should (stringp (haystack-sd-root-expanded d)))
    (should (string-prefix-p "hs: " (haystack-sd-root-expanded d)))))

(ert-deftest haystack-test/date-root-descriptor-literal-flag ()
  ":root-literal is t so the label is not treated as a search term."
  (let ((d (haystack--date-root-descriptor "2024-01" "2024-03")))
    (should (haystack-sd-root-literal d))))

(ert-deftest haystack-test/date-root-descriptor-empty-filters ()
  ":filters is nil for a fresh date-root descriptor."
  (let ((d (haystack--date-root-descriptor "2024-01" "2024-03")))
    (should (null (haystack-sd-filters d)))))

;;;; haystack--chain-parts with date root

(ert-deftest haystack-test/chain-parts-date-root-uses-date-label ()
  "chain-parts uses \"date\" as the root label for date-range descriptors."
  (let* ((d     (haystack--date-root-descriptor "2024-01" "2024-03"))
         (parts (haystack--chain-parts d)))
    (should (equal "date" (plist-get (car parts) :label)))))

(ert-deftest haystack-test/chain-parts-renders-date-filter-in-chain ()
  "chain-parts renders a date-range filter entry as date=LABEL."
  (let* ((desc (haystack-sd-create :root-term "rust" :root-filename nil :root-literal nil
                     :root-regex nil :root-kind 'text :root-expansion nil
                     :filters (list (list :kind 'date-range
                                          :start "2025-01" :end "2025-03"))
                     :composite-filter nil))
         (parts (haystack--chain-parts desc)))
    (should (= (length parts) 2))
    (should (equal "date" (plist-get (cadr parts) :label)))))

;;;; haystack--search-date-range-internal — output format

(ert-deftest haystack-test/date-search-output-is-grep-format ()
  "date-range search output lines are in filename:line:content format."
  (haystack-test--with-notes-dir
   (let ((note (expand-file-name "20240101000000-timestamped.org"
                                 haystack-notes-directory)))
     (with-temp-file note
       (insert "A line with hs: <2024-06-15 Sat 10:00> in it\n")))
   (let* ((result (haystack--search-date-range-internal "2024-06" "2024-06"))
          (output (plist-get result :output)))
     (should (not (string= output "")))
     (dolist (line (split-string output "\n" t))
       (should (string-match-p "\\`.+:[0-9]+:" line))))))

;;;; haystack-filter-further from a date-root buffer

(ert-deftest haystack-test/date-root-filter-further-composes ()
  "haystack-filter-further creates a child buffer from a date-root results buffer."
  (haystack-test--with-notes-dir
   (let ((note (expand-file-name "20240101000000-rust-timestamped.org"
                                 haystack-notes-directory)))
     (with-temp-file note
       (insert "rust hs: <2024-06-15 Sat 10:00> ownership\n")))
   (haystack-test--with-frecency nil
     (cl-letf (((symbol-function 'haystack--load-frecency) #'ignore)
               ((symbol-function 'pop-to-buffer)    #'ignore)
               ((symbol-function 'switch-to-buffer) #'ignore))
       (let ((root-buf (haystack-search-date-range "2024-06" "2024-06")))
         (should root-buf)
         (unwind-protect
             (with-current-buffer root-buf
               (haystack-filter-further "rust")
               ;; Child buffer name encodes the date label and filter term.
               (let ((child-buf (car (seq-filter
                                      (lambda (b)
                                        (and (string-match-p "haystack:2" (buffer-name b))
                                             (string-match-p "rust" (buffer-name b))))
                                      (buffer-list)))))
                 (unwind-protect
                     (progn
                       (should child-buf)
                       (with-current-buffer child-buf
                         (should (string-match-p "date=" (buffer-string)))))
                   (when (and child-buf (buffer-live-p child-buf))
                     (kill-buffer child-buf)))))
           (when (buffer-live-p root-buf)
             (kill-buffer root-buf))))))))

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

;;;; haystack--frontmatter-registry

(ert-deftest haystack-test/frontmatter-registry-has-builtin-styles ()
  "Registry contains entries for all seven macro-defined comment styles."
  (should (assq 'slash      haystack--frontmatter-registry))
  (should (assq 'hash       haystack--frontmatter-registry))
  (should (assq 'semi       haystack--frontmatter-registry))
  (should (assq 'dash       haystack--frontmatter-registry))
  (should (assq 'c-block    haystack--frontmatter-registry))
  (should (assq 'html-block haystack--frontmatter-registry))
  (should (assq 'ml-block   haystack--frontmatter-registry)))

(ert-deftest haystack-test/frontmatter-registry-entry-has-required-keys ()
  "A registry entry contains prefix, suffix, and extensions keys."
  (let ((entry (cdr (assq 'slash haystack--frontmatter-registry))))
    (should (equal (plist-get entry :prefix) "//"))
    (should (equal (plist-get entry :suffix) ""))
    (should (plist-get entry :extensions))))

(ert-deftest haystack-test/frontmatter-registry-block-comment-suffix ()
  "Block comment styles record a non-empty suffix."
  (should (equal " */" (plist-get (cdr (assq 'c-block    haystack--frontmatter-registry)) :suffix)))
  (should (equal " -->" (plist-get (cdr (assq 'html-block haystack--frontmatter-registry)) :suffix)))
  (should (equal " *)" (plist-get (cdr (assq 'ml-block   haystack--frontmatter-registry)) :suffix))))

(ert-deftest haystack-test/frontmatter-define-macro-registers-and-defines ()
  "haystack-define-frontmatter creates a registry entry and a callable generator."
  (let ((haystack--frontmatter-registry haystack--frontmatter-registry))
    (haystack-define-frontmatter test-style-xyz
      :prefix "%%"
      :suffix " END"
      :extensions ("xyz"))
    (should (assq 'test-style-xyz haystack--frontmatter-registry))
    (should (fboundp 'haystack--frontmatter-test-style-xyz))
    (let ((fm (haystack--frontmatter-test-style-xyz "My Note")))
      (should (string-match-p "%% title: My Note END" fm))
      (should (haystack-test--has-sentinel fm))
      (should (string-suffix-p "\n\n" fm)))))

;;;; haystack-describe-frontmatter-styles

(ert-deftest haystack-test/describe-frontmatter-styles-creates-buffer ()
  "Creates a describe buffer listing registered frontmatter styles."
  (cl-letf (((symbol-function 'pop-to-buffer) #'ignore))
    (haystack-describe-frontmatter-styles)
    (let ((buf (get-buffer "*haystack-frontmatter-styles*")))
      (unwind-protect
          (progn
            (should buf)
            (with-current-buffer buf
              (should (string-match-p "slash" (buffer-string)))
              (should (string-match-p "hash" (buffer-string)))
              (should (string-match-p "//" (buffer-string)))))
        (when buf (kill-buffer buf))))))

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
   (let* ((desc (haystack-sd-create :root-term "foo" :root-expanded "foo" :root-literal nil
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

;;;; haystack-new-note-from-region

(ert-deftest haystack-test/new-note-from-region-creates-file-with-content ()
  "Creates a note containing the region text after frontmatter."
  (haystack-test--with-notes-dir
   (let ((haystack-default-extension "org")
         (responses (list "from-region" "org")))
     (with-temp-buffer
       (insert "This is the selected text.")
       (set-mark (point-min))
       (goto-char (point-max))
       (cl-letf (((symbol-function 'read-string)
                  (lambda (_prompt &optional _init _hist _default)
                    (pop responses)))
                 ((symbol-function 'find-file) #'ignore))
         (haystack-new-note-from-region (region-beginning) (region-end))
         (let* ((files (directory-files haystack-notes-directory nil "\\.org$"))
                (content (with-temp-buffer
                           (insert-file-contents
                            (expand-file-name (car files) haystack-notes-directory))
                           (buffer-string))))
           (should (= 1 (length files)))
           (should (string-match-p "from-region" (car files)))
           (should (string-match-p "#\\+TITLE:" content))
           (should (haystack-test--has-sentinel content))
           (should (string-match-p "This is the selected text\\." content))))))))

(ert-deftest haystack-test/new-note-from-region-errors-without-region ()
  "Signals user-error when no region is active."
  (haystack-test--with-notes-dir
   (with-temp-buffer
     (deactivate-mark)
     (should-error (haystack-new-note-from-region (point) (point))
                   :type 'user-error))))

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
                 '("rust" nil nil nil nil nil))))

(ert-deftest haystack-test/strip-prefixes-negate ()
  (should (equal (haystack--strip-prefixes "!rust")
                 '("rust" t nil nil nil nil))))

(ert-deftest haystack-test/strip-prefixes-filename ()
  (should (equal (haystack--strip-prefixes "/cargo")
                 '("cargo" nil t nil nil nil))))

(ert-deftest haystack-test/strip-prefixes-negate-and-filename ()
  (should (equal (haystack--strip-prefixes "!/cargo")
                 '("cargo" t t nil nil nil))))

(ert-deftest haystack-test/strip-prefixes-literal ()
  (should (equal (haystack--strip-prefixes "=rust")
                 '("rust" nil nil t nil nil))))

(ert-deftest haystack-test/strip-prefixes-regex ()
  (should (equal (haystack--strip-prefixes "~rus+t")
                 '("rus+t" nil nil nil t nil))))

(ert-deftest haystack-test/strip-prefixes-negate-and-literal ()
  (should (equal (haystack--strip-prefixes "!=rust")
                 '("rust" t nil t nil nil))))

(ert-deftest haystack-test/strip-prefixes-negate-and-regex ()
  (should (equal (haystack--strip-prefixes "!~rus+t")
                 '("rus+t" t nil nil t nil))))

(ert-deftest haystack-test/strip-prefixes-literal-and-regex ()
  (should (equal (haystack--strip-prefixes "=~rus+t")
                 '("rus+t" nil nil t t nil))))

(ert-deftest haystack-test/strip-prefixes-order-matters ()
  "= before ! is not treated as the literal prefix."
  (should (equal (haystack--strip-prefixes "=!rust")
                 '("!rust" nil nil t nil nil))))

(ert-deftest haystack-test/strip-prefixes-body-scope ()
  "> sets scope to body."
  (should (equal (haystack--strip-prefixes ">rust")
                 '("rust" nil nil nil nil body))))

(ert-deftest haystack-test/strip-prefixes-frontmatter-scope ()
  "< sets scope to frontmatter."
  (should (equal (haystack--strip-prefixes "<title")
                 '("title" nil nil nil nil frontmatter))))

(ert-deftest haystack-test/strip-prefixes-negate-body-scope ()
  "!> sets negated and body scope."
  (should (equal (haystack--strip-prefixes "!>rust")
                 '("rust" t nil nil nil body))))

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
  "Renames the root and adds the old root as a member."
  (let ((result (haystack--groups-rename-root
                 '(("rust" . ("rustlang" "rs")))
                 "rust" "Rust")))
    (should (equal result '(("Rust" . ("rust" "rustlang" "rs")))))))

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

(ert-deftest haystack-test/groups-rename-root-preserves-old-root-as-member ()
  "The old root becomes a member so it still expands to the group."
  (let ((result (haystack--groups-rename-root
                 '(("rust" . ("rustlang" "rs")))
                 "rust" "Rust-lang")))
    (should (equal (caar result) "Rust-lang"))
    (should (member "rust" (cdar result)))))

(ert-deftest haystack-test/groups-rename-root-no-duplicate-old-root ()
  "If the old root is already a member, it is not duplicated."
  (let ((result (haystack--groups-rename-root
                 '(("rust" . ("Rust" "rs")))
                 "rust" "rustlang")))
    (should (equal (caar result) "rustlang"))
    ;; "rust" was already in members as "Rust" (case-insensitive),
    ;; so it should appear exactly once.
    (should (= 1 (cl-count-if
                  (lambda (m) (string= (downcase m) "rust"))
                  (cdar result))))))

;;; haystack-rename-group-root

(ert-deftest haystack-test/rename-group-root-updates-group ()
  "Renames the root, adds old root as member, and saves."
  (haystack-test--with-groups '(("rust" . ("rustlang")))
    (haystack-rename-group-root "rust" "rs")
    (should (equal haystack--expansion-groups '(("rs" . ("rust" "rustlang")))))))

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
  (let* ((key    (list :root '(:kind text :term "programming") :filters '((:term "rust"))))
         (result (haystack--frecency-rewrite-term key "programming" "coding")))
    (should (equal (plist-get (plist-get result :root) :term) "coding"))
    (should (equal (plist-get (car (plist-get result :filters)) :term) "rust"))))

(ert-deftest haystack-test/frecency-rewrite-term-filter-position ()
  "Rewrites the old root term when it appears in a filter position."
  (let* ((key    (list :root '(:kind text :term "rust") :filters '((:term "programming"))))
         (result (haystack--frecency-rewrite-term key "programming" "coding")))
    (should (equal (plist-get (plist-get result :root) :term) "rust"))
    (should (equal (plist-get (car (plist-get result :filters)) :term) "coding"))))

(ert-deftest haystack-test/frecency-rewrite-term-preserves-prefix ()
  "Flag fields on a matched filter are preserved after rewriting."
  (let* ((key    (list :root '(:kind text :term "rust")
                       :filters '((:term "programming" :negated t))))
         (result (haystack--frecency-rewrite-term key "programming" "coding")))
    (should (equal (plist-get (car (plist-get result :filters)) :term) "coding"))
    (should (plist-get (car (plist-get result :filters)) :negated))))

(ert-deftest haystack-test/frecency-rewrite-term-compound-prefix ()
  "Multiple flag fields (:negated and :literal) are preserved after rewriting."
  (let* ((key    (list :root '(:kind text :term "rust")
                       :filters '((:term "programming" :negated t :literal t))))
         (result (haystack--frecency-rewrite-term key "programming" "coding")))
    (should (equal (plist-get (car (plist-get result :filters)) :term) "coding"))
    (should (plist-get (car (plist-get result :filters)) :negated))
    (should (plist-get (car (plist-get result :filters)) :literal))))

(ert-deftest haystack-test/frecency-rewrite-term-non-matching-unchanged ()
  "Terms that do not match old-root are returned unchanged."
  (let* ((key    (haystack-test--tkey "rust" "async"))
         (result (haystack--frecency-rewrite-term key "programming" "coding")))
    (should (equal result key))))

(ert-deftest haystack-test/frecency-rewrite-term-case-insensitive ()
  "Matching is case-insensitive."
  (let* ((key    (list :root '(:kind text :term "Programming") :filters '((:term "rust"))))
         (result (haystack--frecency-rewrite-term key "programming" "coding")))
    (should (equal (plist-get (plist-get result :root) :term) "coding"))))

;;; haystack--frecency-rename-in-data

(ert-deftest haystack-test/frecency-rename-in-data-single-entry ()
  "Rewrites the matching term in a single frecency entry."
  (let* ((key    (list :root '(:kind text :term "programming") :filters '((:term "rust"))))
         (data   (list (cons key '(:count 3 :last-access 1000.0))))
         (result (haystack--frecency-rename-in-data data "programming" "coding")))
    (should (equal (plist-get (plist-get (caar result) :root) :term) "coding"))
    (should (equal (plist-get (car (plist-get (caar result) :filters)) :term) "rust"))))

(ert-deftest haystack-test/frecency-rename-in-data-multiple-entries ()
  "Rewrites matching terms across multiple entries."
  (let* ((k1 (haystack-test--tkey "programming"))
         (k2 (haystack-test--tkey "rust" "programming"))
         (data (list (cons k1 '(:count 2 :last-access 1000.0))
                     (cons k2 '(:count 1 :last-access 900.0))))
         (result (haystack--frecency-rename-in-data data "programming" "coding")))
    (should (assoc (haystack-test--tkey "coding") result))
    (should (assoc (haystack-test--tkey "rust" "coding") result))))

(ert-deftest haystack-test/frecency-rename-in-data-non-matching-unchanged ()
  "Entries without the old term are returned unchanged."
  (let* ((k      (haystack-test--tkey "rust" "async"))
         (data   (list (cons k '(:count 5 :last-access 1000.0))))
         (result (haystack--frecency-rename-in-data data "programming" "coding")))
    (should (assoc k result))))

(ert-deftest haystack-test/frecency-rename-in-data-collision-merges ()
  "When rename would produce a duplicate key, entries are merged (counts summed, latest timestamp kept)."
  (let* ((k1 (haystack-test--tkey "coding"))
         (k2 (haystack-test--tkey "programming"))
         (data (list (cons k1 '(:count 4 :last-access 2000.0))
                     (cons k2 '(:count 3 :last-access 1000.0))))
         (result (haystack--frecency-rename-in-data data "programming" "coding")))
    (should (= (length result) 1))
    (let ((entry (assoc k1 result)))
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

(ert-deftest haystack-test/rename-composites-atomic-rollback-order-is-lifo ()
  "Rollback of a 3-pair rename where pair 3 fails runs in LIFO order.
Pair 2 must be rolled back before pair 1.  Verifies that the `done' list
is not `nreverse'd, preserving the correct LIFO ordering from `push'."
  (haystack-test--with-notes-dir
   (let* ((old1 (expand-file-name "@comp__one.org"   haystack-notes-directory))
          (new1 (expand-file-name "@comp__uno.org"   haystack-notes-directory))
          (old2 (expand-file-name "@comp__two.org"   haystack-notes-directory))
          (new2 (expand-file-name "@comp__dos.org"   haystack-notes-directory))
          (old3 "/nonexistent/path/@comp__three.org")
          (new3 "/nonexistent/path/@comp__tres.org")
          (rollback-log nil))
     (with-temp-file old1 (insert "one"))
     (with-temp-file old2 (insert "two"))
     ;; Wrap rename-file to log rollback calls (where src is a "new" path)
     (cl-letf (((symbol-function 'rename-file)
                (let ((orig (symbol-function 'rename-file)))
                  (lambda (src dst &rest args)
                    ;; Log rollbacks: when src matches a renamed-to path
                    (when (or (equal src new1) (equal src new2))
                      (push src rollback-log))
                    (apply orig src dst args)))))
       (should-error (haystack--rename-composites-atomic
                      (list (cons old1 new1) (cons old2 new2) (cons old3 new3)))))
     ;; Both originals restored
     (should (file-exists-p old1))
     (should (file-exists-p old2))
     ;; Rollback order: pair 2 (new2) first, then pair 1 (new1) — LIFO.
     ;; push-based log records in reverse: last-pushed = first-rolled-back.
     (should (equal rollback-log (list new1 new2))))))

;;; haystack-rename-group-root — full atomic integration

(ert-deftest haystack-test/rename-group-root-updates-frecency ()
  "rename-group-root rewrites matching frecency chain keys."
  (haystack-test--with-groups '(("programming" . ("coding" "scripting")))
    (let* ((k-prog-rust (haystack-test--tkey "programming" "rust"))
           (k-rust-prog (haystack-test--tkey "rust" "programming")))
      (haystack-test--with-frecency
       (list (cons k-prog-rust '(:count 2 :last-access 1000.0))
             (cons k-rust-prog '(:count 1 :last-access 900.0)))
       (haystack-rename-group-root "programming" "dev")
       (should (assoc (haystack-test--tkey "dev" "rust") haystack--frecency-data))
       (should (assoc (haystack-test--tkey "rust" "dev") haystack--frecency-data))
       (should-not (assoc k-prog-rust haystack--frecency-data))))))

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
                     (haystack-sd-create :root-term "coding" :root-expanded "some content"
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

;;; haystack--parse-input (scope prefixes)

(ert-deftest haystack-test/parse-input-body-scope ()
  ">prefix sets :scope to body."
  (let ((result (haystack--parse-input ">rust")))
    (should (equal (plist-get result :term)  "rust"))
    (should (equal (plist-get result :scope) 'body))
    (should (equal (plist-get result :negated) nil))))

(ert-deftest haystack-test/parse-input-frontmatter-scope ()
  "<prefix sets :scope to frontmatter."
  (let ((result (haystack--parse-input "<title")))
    (should (equal (plist-get result :term)  "title"))
    (should (equal (plist-get result :scope) 'frontmatter))
    (should (equal (plist-get result :negated) nil))))

(ert-deftest haystack-test/parse-input-negated-body-scope ()
  "!>prefix sets both :negated and :scope."
  (let ((result (haystack--parse-input "!>rust")))
    (should (equal (plist-get result :term)    "rust"))
    (should (equal (plist-get result :scope)   'body))
    (should (equal (plist-get result :negated) t))))

(ert-deftest haystack-test/parse-input-body-scope-literal ()
  ">=prefix sets :scope and :literal."
  (let ((result (haystack--parse-input ">=rust")))
    (should (equal (plist-get result :term)    "rust"))
    (should (equal (plist-get result :scope)   'body))
    (should (equal (plist-get result :literal) t))))

(ert-deftest haystack-test/parse-input-body-scope-regex ()
  ">~prefix sets :scope and :regex."
  (let ((result (haystack--parse-input ">~rus+t")))
    (should (equal (plist-get result :term)    "rus+t"))
    (should (equal (plist-get result :scope)   'body))
    (should (equal (plist-get result :regex)   t))))

(ert-deftest haystack-test/parse-input-no-scope-by-default ()
  "Bare term has nil :scope."
  (let ((result (haystack--parse-input "rust")))
    (should (null (plist-get result :scope)))))

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

(ert-deftest haystack-test/strip-notes-prefix-trailing-newline-preserved ()
  "A trailing newline in the output string is preserved."
  (let ((haystack-notes-directory "/notes"))
    (should (equal (haystack--strip-notes-prefix "/notes/foo.org:1:content\n")
                   "foo.org:1:content\n"))))

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

(ert-deftest haystack-test/rg-args-leading-dash-pattern-separated ()
  "A leading-dash pattern is preceded by \"--\" so rg does not parse it as a flag."
  (let ((haystack-file-glob nil))
    (let ((args (haystack--rg-args :composite-filter 'exclude :pattern "-foo")))
      (should (member "-foo" args))
      (let ((pos-sep (cl-position "--" args :test #'string=))
            (pos-pat (cl-position "-foo" args :test #'string=)))
        (should pos-sep)
        (should pos-pat)
        (should (< pos-sep pos-pat))))))

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

(ert-deftest haystack-test/truncate-content-emacs-alternation-centers-on-match ()
  "Emacs alternation syntax \\| correctly centers the window on the match."
  (let* ((haystack-context-width 20)
         ;; Match term is in the middle; pattern uses Emacs alternation.
         (content (concat (make-string 40 ?a) "second" (make-string 40 ?b)))
         (result (haystack--truncate-content content "first\\|second")))
    (should (string-match-p "second" result))))

(ert-deftest haystack-test/truncate-content-rg-alternation-does-not-center ()
  "rg-style alternation (foo|bar) is NOT Emacs regexp; window falls back to
position 0, so the match term is absent from the truncated window."
  (let* ((haystack-context-width 20)
         ;; \"second\" is 40 chars in — well outside a 20-char window at pos 0.
         (content (concat (make-string 40 ?a) "second" (make-string 40 ?b)))
         (result (haystack--truncate-content content "(first|second)")))
    ;; rg-style pattern: string-match treats ( as a group anchor producing
    ;; wrong position; the match term is not in the truncated window.
    (should-not (string-match-p "second" result))))

(ert-deftest haystack-test/truncate-content-invalid-emacs-regex-no-crash ()
  "An invalid Emacs regexp (e.g. a raw rg lookahead) does not crash; the
function degrades gracefully and returns a non-empty string."
  (let* ((haystack-context-width 20)
         (content (concat (make-string 40 ?a) "hello" (make-string 40 ?b))))
    ;; (?i:hello) is valid ripgrep syntax but invalid Emacs regexp.
    (should (stringp (haystack--truncate-content content "(?i:hello)")))))

(ert-deftest haystack-test/truncate-output-emacs-alternation-preserves-prefix ()
  "Emacs alternation pattern works end-to-end through truncate-output."
  (let* ((haystack-context-width 20)
         (padding (make-string 40 ?x))
         (line (concat "/notes/foo.org:5:" padding "target" padding)))
    (let ((result (haystack--truncate-output line "miss\\|target")))
      (should (string-prefix-p "/notes/foo.org:5:" result))
      (should (string-match-p "target" result)))))

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

;;;; haystack--scope-filter-output

(ert-deftest haystack-test/scope-filter-body-keeps-lines-after-sentinel ()
  "Body scope keeps only lines with line-number > sentinel line."
  (let ((sentinel-table (make-hash-table :test 'equal))
        (output (concat "foo.org:2:title: My Note\n"
                        "foo.org:4:body content\n"
                        "foo.org:5:more body\n")))
    (puthash "foo.org" 3 sentinel-table)
    (let ((result (haystack--scope-filter-output output sentinel-table 'body)))
      (should (string-match-p "foo.org:4:body content" result))
      (should (string-match-p "foo.org:5:more body" result))
      (should-not (string-match-p "foo.org:2:title" result)))))

(ert-deftest haystack-test/scope-filter-frontmatter-keeps-lines-at-or-before-sentinel ()
  "Frontmatter scope keeps only lines with line-number <= sentinel line."
  (let ((sentinel-table (make-hash-table :test 'equal))
        (output (concat "foo.org:2:title: My Note\n"
                        "foo.org:3:sentinel line\n"
                        "foo.org:5:body content\n")))
    (puthash "foo.org" 3 sentinel-table)
    (let ((result (haystack--scope-filter-output output sentinel-table 'frontmatter)))
      (should (string-match-p "foo.org:2:title" result))
      (should (string-match-p "foo.org:3:sentinel" result))
      (should-not (string-match-p "foo.org:5:body" result)))))

(ert-deftest haystack-test/scope-filter-body-includes-files-without-sentinel ()
  "Files without a sentinel are all-body; body scope keeps all their lines."
  (let ((sentinel-table (make-hash-table :test 'equal))
        (output "bar.org:1:no frontmatter here\n"))
    (let ((result (haystack--scope-filter-output output sentinel-table 'body)))
      (should (string-match-p "bar.org:1:no frontmatter" result)))))

(ert-deftest haystack-test/scope-filter-frontmatter-excludes-files-without-sentinel ()
  "Files without a sentinel have no frontmatter; frontmatter scope drops them."
  (let ((sentinel-table (make-hash-table :test 'equal))
        (output "bar.org:1:no frontmatter here\n"))
    (let ((result (haystack--scope-filter-output output sentinel-table 'frontmatter)))
      (should (string-empty-p result)))))

(ert-deftest haystack-test/scope-filter-preserves-header-lines ()
  "Header lines starting with ;;; pass through regardless of scope."
  (let ((sentinel-table (make-hash-table :test 'equal))
        (output (concat ";;; haystack: root=rust | 5 files\n"
                        "foo.org:2:in frontmatter\n"
                        "foo.org:5:in body\n")))
    (puthash "foo.org" 3 sentinel-table)
    (let ((result (haystack--scope-filter-output output sentinel-table 'body)))
      (should (string-match-p "^;;; haystack:" result))
      (should (string-match-p "foo.org:5:in body" result))
      (should-not (string-match-p "foo.org:2:in frontmatter" result)))))

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
  "Does not prompt when total lines < threshold."
  ;; 10 files × 49 lines = 490 < 500
  (let ((haystack-volume-gate-threshold 500)
        (out (mapconcat (lambda (i) (format "/notes/f%d.org:49" i))
                        (number-sequence 1 10) "\n")))
    (cl-letf (((symbol-function 'yes-or-no-p)
               (lambda (&rest _) (error "Should not have prompted"))))
      (should-not (haystack--volume-gate out)))))

(ert-deftest haystack-test/volume-gate-prompts-at-threshold ()
  "Prompts when total = threshold."
  (let ((haystack-volume-gate-threshold 500)
        (prompted nil))
    (cl-letf (((symbol-function 'yes-or-no-p)
               (lambda (&rest _) (setq prompted t) t)))
      (haystack--volume-gate "/notes/f.org:500\n"))
    (should prompted)))

(ert-deftest haystack-test/volume-gate-user-approves ()
  "Returns normally when user confirms."
  (let ((haystack-volume-gate-threshold 500))
    (cl-letf (((symbol-function 'yes-or-no-p) (lambda (&rest _) t)))
      (should-not (haystack--volume-gate "/notes/f.org:501\n")))))

(ert-deftest haystack-test/volume-gate-user-declines ()
  "Signals user-error when user declines."
  (let ((haystack-volume-gate-threshold 500))
    (cl-letf (((symbol-function 'yes-or-no-p) (lambda (&rest _) nil)))
      (should-error (haystack--volume-gate "/notes/f.org:501\n") :type 'user-error))))

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

(ert-deftest haystack-test/write-filelist-cleans-up-on-write-error ()
  "If the write step signals, the temp file is deleted before re-signaling."
  (let (tmp-path)
    ;; Intercept make-temp-file to capture the path, then make insert fail.
    (cl-letf* (((symbol-function 'orig-make-temp-file)
                (symbol-function 'make-temp-file))
               ((symbol-function 'make-temp-file)
                (lambda (prefix &rest args)
                  (let ((p (apply 'orig-make-temp-file prefix args)))
                    (setq tmp-path p)
                    p)))
               ((symbol-function 'insert)
                (lambda (&rest _) (error "simulated write failure"))))
      (should-error (haystack--write-filelist '("/notes/a.org"))))
    ;; The temp file must not survive the error.
    (should (stringp tmp-path))
    (should-not (file-exists-p tmp-path))))

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
  (let ((descriptor (haystack-sd-create :root-term "rust" :filters nil)))
    (should (equal (haystack--format-search-chain descriptor "async" nil)
                   "root=rust > filter=async"))))

(ert-deftest haystack-test/format-chain-negated-filter ()
  "Negated filter shows as exclude=."
  (let ((descriptor (haystack-sd-create :root-term "rust" :filters nil)))
    (should (equal (haystack--format-search-chain descriptor "ownership" t)
                   "root=rust > exclude=ownership"))))

(ert-deftest haystack-test/format-chain-deep-chain ()
  "Full chain shows all prior filters plus the current one."
  (let ((descriptor (haystack-sd-create :root-term "rust"
                          :filters (list (list :term "async"  :negated nil)
                                         (list :term "tokio"  :negated nil)))))
    (should (equal (haystack--format-search-chain descriptor "ownership" t)
                   "root=rust > filter=async > filter=tokio > exclude=ownership"))))

(ert-deftest haystack-test/format-chain-filename-filter ()
  "Filename filter shows as filename=."
  (let ((descriptor (haystack-sd-create :root-term "rust" :filters nil)))
    (should (equal (haystack--format-search-chain descriptor "cargo" nil t)
                   "root=rust > filename=cargo"))))

(ert-deftest haystack-test/format-chain-negated-filename-filter ()
  "Negated filename filter shows as !filename=."
  (let ((descriptor (haystack-sd-create :root-term "rust" :filters nil)))
    (should (equal (haystack--format-search-chain descriptor "cargo" t t)
                   "root=rust > !filename=cargo"))))

(ert-deftest haystack-test/format-chain-filename-root ()
  "A filename root search shows filename= as the root label."
  (let ((descriptor (haystack-sd-create :root-term "cargo" :root-filename t :filters nil)))
    (should (equal (haystack--format-search-chain descriptor "async" nil)
                   "filename=cargo > filter=async"))))

(ert-deftest haystack-test/format-chain-mixed-filters ()
  "Chain with a filename filter in history renders correctly."
  (let ((descriptor (haystack-sd-create :root-term "rust"
                          :filters (list (list :term "cargo" :negated nil :filename t)))))
    (should (equal (haystack--format-search-chain descriptor "async" nil)
                   "root=rust > filename=cargo > filter=async"))))

;;;; haystack--child-buffer-name

(ert-deftest haystack-test/child-buffer-name-depth-2 ()
  "First filter produces depth 2 name."
  (let ((descriptor (haystack-sd-create :root-term "rust" :root-filename nil
                          :root-literal nil :root-regex nil :filters nil)))
    (should (equal (haystack--child-buffer-name descriptor "async" nil nil nil nil)
                   "*haystack:2:rust:async*"))))

(ert-deftest haystack-test/child-buffer-name-depth-3 ()
  "Second filter produces depth 3 name with full chain."
  (let ((descriptor (haystack-sd-create :root-term "rust" :root-filename nil
                          :root-literal nil :root-regex nil
                          :filters (list (list :term "async" :negated nil
                                               :filename nil :literal nil :regex nil)))))
    (should (equal (haystack--child-buffer-name descriptor "ownership" nil nil nil nil)
                   "*haystack:3:rust:async:ownership*"))))

(ert-deftest haystack-test/child-buffer-name-with-modifiers ()
  "Modifier flags appear as prefixes in the buffer name."
  (let ((descriptor (haystack-sd-create :root-term "rust" :root-filename nil
                          :root-literal nil :root-regex nil :filters nil)))
    (should (equal (haystack--child-buffer-name descriptor "async" t nil nil nil)
                   "*haystack:2:rust:!async*"))
    (should (equal (haystack--child-buffer-name descriptor "notes" nil t nil nil)
                   "*haystack:2:rust:/notes*"))))

(ert-deftest haystack-test/child-buffer-name-handles-date-filter-in-existing-filters ()
  "child-buffer-name renders a date-range entry in :filters without nil/crash."
  (let ((descriptor (haystack-sd-create :root-term "rust" :root-filename nil
                          :root-literal nil :root-regex nil
                          :filters (list (list :kind 'date-range
                                               :start "2025-01" :end "2025-03")))))
    (let ((name (haystack--child-buffer-name descriptor "async" nil nil nil nil)))
      (should (stringp name))
      (should (string-match-p "haystack:3" name))
      (should (string-match-p "async" name)))))

;;;; haystack-filter-further

(ert-deftest haystack-test/filter-further-errors-outside-haystack-buffer ()
  "Signals user-error when not in a haystack results buffer."
  (with-temp-buffer
    (should-error (haystack-filter-further "rust") :type 'user-error)))

(ert-deftest haystack-test/filter-further-errors-on-empty-buffer ()
  "Signals user-error when the current buffer has no result files."
  (with-temp-buffer
    (setq haystack--search-descriptor
          (haystack-sd-create :root-term "rust" :root-expanded "rust"
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
                     (should (string-match-p "root=rust" (buffer-string)))
                     (should (string-match-p "> filter=async" (buffer-string)))
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
            (haystack-sd-create :root-term "programming"
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
            (haystack-sd-create :root-term "programming"
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
            (haystack-sd-create :root-term "programming"
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
  "Prompts when a content filter would return >= threshold lines."
  (let ((haystack-volume-gate-threshold 500))
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
               (kill-buffer (get-buffer "*haystack:2:rust:hit*"))))))))))

(ert-deftest haystack-test/filter-further-volume-gate-cancels ()
  "Signals user-error when user declines at the filter volume gate."
  (let ((haystack-volume-gate-threshold 500))
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
           (kill-buffer root-buf)))))))

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

;;;; haystack--parse-or-tokens

(ert-deftest haystack-test/parse-or-tokens-returns-nil-without-pipe ()
  "Returns nil when input contains no ' | '."
  (should-not (haystack--parse-or-tokens "rust"))
  (should-not (haystack--parse-or-tokens "rust async"))
  (should-not (haystack--parse-or-tokens "rust|async")))

(ert-deftest haystack-test/parse-or-tokens-splits-on-spaced-pipe ()
  "Splits on ' | ' and returns a list of trimmed tokens."
  (should (equal (haystack--parse-or-tokens "rust | python")
                 '("rust" "python"))))

(ert-deftest haystack-test/parse-or-tokens-three-terms ()
  "Works with three or more terms."
  (should (equal (haystack--parse-or-tokens "rust | python | go")
                 '("rust" "python" "go"))))

(ert-deftest haystack-test/parse-or-tokens-preserves-prefixes ()
  "Prefix characters on tokens are preserved in the returned list."
  (should (equal (haystack--parse-or-tokens "=rust | ~async")
                 '("=rust" "~async"))))

(ert-deftest haystack-test/parse-or-tokens-returns-nil-for-single-token ()
  "Returns nil when splitting produces fewer than two non-empty tokens."
  (should-not (haystack--parse-or-tokens " | "))
  (should-not (haystack--parse-or-tokens "rust | ")))

;;;; haystack--run-or-query

(ert-deftest haystack-test/run-or-query-alternation ()
  "Returns results matching either term."
  (haystack-test--with-notes-dir
   (let ((only-a (expand-file-name "a.org" haystack-notes-directory))
         (only-b (expand-file-name "b.org" haystack-notes-directory))
         (neither (expand-file-name "c.org" haystack-notes-directory)))
     (with-temp-file only-a  (insert "rust is fast\n"))
     (with-temp-file only-b  (insert "python is flexible\n"))
     (with-temp-file neither (insert "nothing relevant here\n"))
     (let ((output (haystack--run-root-search-or '("rust" "python") 'all)))
       (let ((out (plist-get output :output)))
         (should (string-match-p "a\\.org" out))
         (should (string-match-p "b\\.org" out))
         (should-not (string-match-p "c\\.org" out)))))))

(ert-deftest haystack-test/run-or-query-rejects-negation ()
  "Signals user-error when a token has the ! prefix."
  (haystack-test--with-notes-dir
   (let ((f (expand-file-name "x.org" haystack-notes-directory)))
     (with-temp-file f (insert "content\n"))
     (should-error (haystack--run-root-search-or '("!rust" "python") 'all)
                   :type 'user-error))))

(ert-deftest haystack-test/run-or-query-descriptor-root-term ()
  "Descriptor root-term stores the full OR expression."
  (haystack-test--with-notes-dir
   (let ((f (expand-file-name "x.org" haystack-notes-directory)))
     (with-temp-file f (insert "rust or python\n"))
     (let* ((result (haystack--run-root-search-or '("rust" "python") 'all))
            (desc   (plist-get result :descriptor)))
       (should (equal (haystack-sd-root-term desc) "rust | python"))))))

;;;; Mixed & and | guard

(ert-deftest haystack-test/mixed-and-or-errors ()
  "Signals user-error when both & and | appear in input."
  (haystack-test--with-notes-dir
   (cl-letf (((symbol-function 'pop-to-buffer) #'ignore)
             ((symbol-function 'switch-to-buffer) #'ignore))
     (should-error (haystack-run-root-search "rust & async | python")
                   :type 'user-error))))

;;;; OR frecency recording

(ert-deftest haystack-test/or-query-records-frecency ()
  "OR queries produce a frecency entry."
  (haystack-test--with-notes-dir
   (let ((f (expand-file-name "x.org" haystack-notes-directory))
         (haystack--frecency-data nil)
         (haystack--frecency-dirty nil))
     (with-temp-file f (insert "rust python\n"))
     (cl-letf (((symbol-function 'pop-to-buffer) #'ignore)
               ((symbol-function 'switch-to-buffer) #'ignore))
       (let ((buf (haystack-run-root-search "rust | python")))
         (unwind-protect
             (should (= 1 (length haystack--frecency-data)))
           (when (buffer-live-p buf) (kill-buffer buf))))))))

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
             (should (equal (haystack-sd-root-term haystack--search-descriptor)
                            "nomatchxyz99"))
             (should (eq (haystack-sd-composite-filter haystack--search-descriptor)
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
  "Prompts when rg --count returns >= threshold total lines."
  (let ((haystack-volume-gate-threshold 500))
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
           (kill-buffer (get-buffer "*haystack:1:hit*"))))))))

(ert-deftest haystack-test/run-root-search-volume-gate-cancels ()
  "Signals user-error when user declines at the volume gate."
  (let ((haystack-volume-gate-threshold 500))
    (haystack-test--with-notes-dir
     (let ((note (expand-file-name "big.org" haystack-notes-directory)))
       (with-temp-file note
         (insert (mapconcat (lambda (_) "hit\n") (make-list 500 nil) ""))))
     (cl-letf (((symbol-function 'pop-to-buffer) #'ignore)
               ((symbol-function 'yes-or-no-p)   (lambda (&rest _) nil)))
       (should-error (haystack-run-root-search "hit") :type 'user-error)))))

(ert-deftest haystack-test/run-root-search-volume-gate-no-prompt-under-threshold ()
  "Does not prompt when total lines < threshold."
  (let ((haystack-volume-gate-threshold 500))
    (haystack-test--with-notes-dir
     (let ((note (expand-file-name "small.org" haystack-notes-directory)))
       (with-temp-file note (insert "hit\nhit\n")))
     (cl-letf (((symbol-function 'pop-to-buffer) #'ignore)
               ((symbol-function 'yes-or-no-p)
                (lambda (&rest _) (error "Should not have prompted"))))
       (haystack-run-root-search "hit")
       (when (get-buffer "*haystack:1:hit*")
         (kill-buffer (get-buffer "*haystack:1:hit*")))))))

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
               (should (equal (haystack-sd-root-term haystack--search-descriptor)
                              "rust & async"))
               ;; root-expanded is the first token's rg pattern
               (should (equal (haystack-sd-root-expanded haystack--search-descriptor)
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
               (should (eq (haystack-sd-composite-filter haystack--search-descriptor)
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
               (should (eq (haystack-sd-composite-filter haystack--search-descriptor)
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
             (should (eq (haystack-sd-composite-filter haystack--search-descriptor)
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
              " *hs-copy-empty*" nil (haystack-sd-create :root-term "rust"))))
    (unwind-protect
        (with-current-buffer buf
          (should-error (haystack-copy-moc) :type 'user-error))
      (kill-buffer buf))))

(ert-deftest haystack-test/copy-moc-stores-loci ()
  "Stores (path . line) loci in `haystack--last-moc'."
  (let ((buf (haystack-test--make-results-buf
              " *hs-copy-moc*" nil (haystack-sd-create :root-term "rust")))
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
                  (haystack-sd-create :root-term "rust" :root-expansion nil
                    :root-filename nil :filters nil))
                 "root=rust")))

(ert-deftest haystack-test/descriptor-chain-string-with-filters ()
  "Descriptor with filters includes all filter segments."
  (should (equal (haystack--descriptor-chain-string
                  (haystack-sd-create :root-term "rust" :root-expansion nil :root-filename nil
                    :filters '((:term "async" :negated nil :filename nil :expansion nil)
                               (:term "cargo" :negated t :filename nil :expansion nil))))
                 "root=rust > filter=async > exclude=cargo")))

(ert-deftest haystack-test/descriptor-chain-string-with-expansion ()
  "Root expansion is shown as alternation."
  (should (equal (haystack--descriptor-chain-string
                  (haystack-sd-create :root-term "programming"
                    :root-expansion '("programming" "coding" "scripting")
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

;;; haystack--moc-language-registry

(ert-deftest haystack-test/moc-language-registry-has-builtin-languages ()
  "Registry contains entries for all four built-in languages."
  (should (assq 'js     haystack--moc-language-registry))
  (should (assq 'python haystack--moc-language-registry))
  (should (assq 'elisp  haystack--moc-language-registry))
  (should (assq 'lua    haystack--moc-language-registry)))

(ert-deftest haystack-test/moc-language-registry-entry-has-required-keys ()
  "A registry entry contains the expected plist keys."
  (let ((entry (cdr (assq 'js haystack--moc-language-registry))))
    (should (plist-get entry :comment))
    (should (plist-get entry :open))
    (should (plist-get entry :entry))
    (should (plist-get entry :separator))
    (should (plist-get entry :close))
    (should (plist-get entry :extensions))))

(ert-deftest haystack-test/moc-language-registry-extensions-correct ()
  "Registry :extensions lists match expected file types."
  (should (member "ts" (plist-get (cdr (assq 'js     haystack--moc-language-registry)) :extensions)))
  (should (member "py" (plist-get (cdr (assq 'python haystack--moc-language-registry)) :extensions)))
  (should (member "el" (plist-get (cdr (assq 'elisp  haystack--moc-language-registry)) :extensions)))
  (should (member "lua" (plist-get (cdr (assq 'lua    haystack--moc-language-registry)) :extensions))))

(ert-deftest haystack-test/moc-define-language-macro-registers-and-defines ()
  "haystack-define-moc-language creates a registry entry and a callable formatter."
  (let ((haystack--moc-language-registry haystack--moc-language-registry))
    (haystack-define-moc-language test-lang-xyz
      :comment "##"
      :open    "OPEN\n"
      :entry   "  ITEM %s %s %d"
      :close   "\nCLOSE"
      :extensions ("xyz"))
    (should (assq 'test-lang-xyz haystack--moc-language-registry))
    (should (fboundp 'haystack--moc-data-format-test-lang-xyz))
    (let ((result (haystack--moc-data-format-test-lang-xyz
                   '(("/notes/20240101000000-foo.xyz" . 5))
                   "root=foo")))
      (should (string-match-p "^## haystack: root=foo" result))
      (should (string-match-p "OPEN" result))
      (should (string-match-p "CLOSE" result)))))

;;;; haystack-describe-moc-languages

(ert-deftest haystack-test/describe-moc-languages-creates-buffer ()
  "Creates a describe buffer listing registered MOC data format languages."
  (cl-letf (((symbol-function 'pop-to-buffer) #'ignore))
    (haystack-describe-moc-languages)
    (let ((buf (get-buffer "*haystack-moc-languages*")))
      (unwind-protect
          (progn
            (should buf)
            (with-current-buffer buf
              (should (string-match-p "js" (buffer-string)))
              (should (string-match-p "python" (buffer-string)))
              (should (string-match-p "elisp" (buffer-string)))))
        (when buf (kill-buffer buf))))))

;;; copy-moc stores chain

(ert-deftest haystack-test/copy-moc-stores-chain ()
  "haystack-copy-moc stores the search chain alongside loci."
  (let ((buf (haystack-test--make-results-buf
              " *hs-copy-chain*" nil
              (haystack-sd-create :root-term "rust" :root-expansion nil :root-filename nil
                :filters '((:term "async" :negated nil :filename nil :expansion nil)))))
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
                " *hs-test-all*" nil (haystack-sd-create :root-term "rust")))
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
  (let* ((root  (haystack-test--make-results-buf " *hs-root*"  nil       (haystack-sd-create :root-term "rust")))
         (child (haystack-test--make-results-buf " *hs-child*" root      (haystack-sd-create :root-term "rust")))
         (other (haystack-test--make-results-buf " *hs-other*" nil       (haystack-sd-create :root-term "async"))))
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
  (let ((buf (haystack-test--make-results-buf " *hs-go-up-root*" nil (haystack-sd-create :root-term "rust")))
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
  (let* ((parent (haystack-test--make-results-buf " *hs-dead-parent*" nil (haystack-sd-create :root-term "r")))
         (child  (haystack-test--make-results-buf " *hs-child-dp*" parent (haystack-sd-create :root-term "r")))
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
  (let* ((parent (haystack-test--make-results-buf " *hs-live-parent*" nil (haystack-sd-create :root-term "r")))
         (child  (haystack-test--make-results-buf " *hs-child-lp*" parent (haystack-sd-create :root-term "r")))
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
  (let ((buf (haystack-test--make-results-buf " *hs-down-none*" nil (haystack-sd-create :root-term "rust"))))
    (unwind-protect
        (with-current-buffer buf
          (should-error (haystack-go-down) :type 'user-error))
      (kill-buffer buf))))

(ert-deftest haystack-test/go-down-switches-directly-with-one-child ()
  "With one child, switches to it without showing a picker."
  (let* ((parent (haystack-test--make-results-buf " *hs-down-p*" nil (haystack-sd-create :root-term "rust")))
         (child  (haystack-test--make-results-buf " *hs-down-c*" parent (haystack-sd-create :root-term "rust")))
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
                  (haystack-sd-create :root-term "rust" :root-filename nil :root-literal nil :root-regex nil)))
         (c1 (haystack-test--make-results-buf
              " *hs-down-mc1*" parent
              (haystack-sd-create :root-term "rust" :filters '((:term "async" :negated nil
                                             :filename nil :literal nil :regex nil)))))
         (c2 (haystack-test--make-results-buf
              " *hs-down-mc2*" parent
              (haystack-sd-create :root-term "rust" :filters '((:term "tokio" :negated nil
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
                  (haystack-sd-create :root-term "rust" :root-filename nil :root-literal nil :root-regex nil)))
         (c1 (haystack-test--make-results-buf
              " *hs-down-tp1*" parent
              (haystack-sd-create :root-term "rust" :filters '((:term "async" :negated nil
                                             :filename nil :literal nil :regex nil)))))
         (c2 (haystack-test--make-results-buf
              " *hs-down-tp2*" parent
              (haystack-sd-create :root-term "rust" :filters '((:term "tokio" :negated nil
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
  (let* ((buf   (haystack-test--make-results-buf " *hs-kill-node*" nil (haystack-sd-create :root-term "r")))
         (child (haystack-test--make-results-buf " *hs-kill-node-child*" buf (haystack-sd-create :root-term "r"))))
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
  (let* ((root    (haystack-test--make-results-buf " *hs-ks-root*"    nil     (haystack-sd-create :root-term "r")))
         (child   (haystack-test--make-results-buf " *hs-ks-child*"   root    (haystack-sd-create :root-term "r")))
         (grandch (haystack-test--make-results-buf " *hs-ks-grand*"   child   (haystack-sd-create :root-term "r")))
         (sibling (haystack-test--make-results-buf " *hs-ks-sibling*" nil     (haystack-sd-create :root-term "r"))))
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
  (let* ((root    (haystack-test--make-results-buf " *hs-ka-root*"  nil   (haystack-sd-create :root-term "r")))
         (child   (haystack-test--make-results-buf " *hs-ka-child*" root  (haystack-sd-create :root-term "r")))
         (grandch (haystack-test--make-results-buf " *hs-ka-grand*" child (haystack-sd-create :root-term "r")))
         (other   (haystack-test--make-results-buf " *hs-ka-other*" nil   (haystack-sd-create :root-term "r"))))
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
  (let* ((root  (haystack-test--make-results-buf " *hs-ka2-root*"  nil  (haystack-sd-create :root-term "r")))
         (child (haystack-test--make-results-buf " *hs-ka2-child*" root (haystack-sd-create :root-term "r"))))
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
  (let* ((dead-parent (haystack-test--make-results-buf " *hs-ko-dead*"   nil          (haystack-sd-create :root-term "r")))
         (orphan      (haystack-test--make-results-buf " *hs-ko-orphan*" dead-parent  (haystack-sd-create :root-term "r")))
         (root        (haystack-test--make-results-buf " *hs-ko-root*"   nil          (haystack-sd-create :root-term "r"))))
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
  (let* ((dead-parent (haystack-test--make-results-buf " *hs-ko-dead2*"   nil         (haystack-sd-create :root-term "r")))
         (mid         (haystack-test--make-results-buf " *hs-ko-mid*"     dead-parent (haystack-sd-create :root-term "r")))
         (grandch     (haystack-test--make-results-buf " *hs-ko-grand2*"  mid         (haystack-sd-create :root-term "r"))))
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

;;;; Frecency format versioning

(ert-deftest haystack-test/frecency-load-versioned-v1 ()
  "Loading a versioned v1 file extracts :entries correctly."
  (haystack-test--with-notes-dir
   (let ((path (expand-file-name ".haystack-frecency.el"
                                 haystack-notes-directory))
         (entries '((("=foo") :count 3 :last-access 1700000000.0))))
     (with-temp-file path
       (let ((print-level nil) (print-length nil))
         (pp (list :version 1 :entries entries) (current-buffer))))
     (let ((haystack--frecency-data nil)
           (haystack--frecency-dirty nil))
       (haystack--load-frecency)
       (should (equal haystack--frecency-data entries))
       (should-not haystack--frecency-dirty)))))

(ert-deftest haystack-test/frecency-load-bare-alist-migrates ()
  "Loading a pre-versioned bare alist auto-migrates and marks dirty."
  (haystack-test--with-notes-dir
   (let ((path (expand-file-name ".haystack-frecency.el"
                                 haystack-notes-directory))
         (entries '((("=foo") :count 5 :last-access 1700000000.0))))
     (with-temp-file path
       (let ((print-level nil) (print-length nil))
         (pp entries (current-buffer))))
     (let ((haystack--frecency-data nil)
           (haystack--frecency-dirty nil))
       (haystack--load-frecency)
       (should (equal haystack--frecency-data entries))
       (should haystack--frecency-dirty)))))

(ert-deftest haystack-test/frecency-load-future-version-warns ()
  "Loading a file with version > current sets data to nil."
  (haystack-test--with-notes-dir
   (let ((path (expand-file-name ".haystack-frecency.el"
                                 haystack-notes-directory)))
     (with-temp-file path
       (let ((print-level nil) (print-length nil))
         (pp (list :version 999 :entries '((("=x") :count 1 :last-access 0.0)))
             (current-buffer))))
     (let ((haystack--frecency-data nil)
           (haystack--frecency-dirty nil))
       (haystack--load-frecency)
       (should-not haystack--frecency-data)))))

(ert-deftest haystack-test/frecency-flush-writes-versioned ()
  "Flushing writes a versioned plist with :version and :entries."
  (haystack-test--with-notes-dir
   (let ((haystack--frecency-data '((("=bar") :count 2 :last-access 1700000000.0)))
         (haystack--frecency-dirty t))
     (haystack--frecency-flush)
     (let* ((path (haystack--frecency-file))
            (raw  (with-temp-buffer
                    (insert-file-contents path)
                    (read (current-buffer)))))
       (should (= (plist-get raw :version) 1))
       (should (equal (plist-get raw :entries) haystack--frecency-data))))))

(ert-deftest haystack-test/frecency-round-trip ()
  "Flush then load preserves data identity."
  (haystack-test--with-notes-dir
   (let ((entries '((("=baz" "qux") :count 7 :last-access 1700000000.0)
                    (("=quux") :count 1 :last-access 1700000001.0)))
         (haystack--frecency-dirty t))
     (setq haystack--frecency-data entries)
     (haystack--frecency-flush)
     (setq haystack--frecency-data nil)
     (haystack--load-frecency)
     (should (equal haystack--frecency-data entries)))))

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
  "Root-only descriptor produces a plist with :root kind=text and empty :filters."
  (let ((key (haystack--frecency-chain-key
              (haystack-sd-create :root-term "rust" :root-filename nil :root-literal nil
                :root-regex nil :filters nil :root-kind nil))))
    (should (equal key (haystack-test--tkey "rust")))))

(ert-deftest haystack-test/frecency-chain-key-with-filters ()
  "Filters produce :filters list with :term and flag plists."
  (let ((key (haystack--frecency-chain-key
              (haystack-sd-create :root-term "rust" :root-filename nil :root-literal nil
                :root-regex nil :root-kind nil
                :filters '((:term "async" :negated nil :filename nil
                            :literal nil :regex nil)
                           (:term "cargo" :negated t :filename nil
                            :literal nil :regex nil))))))
    (should (equal (plist-get (plist-get key :root) :term) "rust"))
    (should (equal (plist-get (car (plist-get key :filters)) :term) "async"))
    (should (null (plist-get (car (plist-get key :filters)) :negated)))
    (should (equal (plist-get (cadr (plist-get key :filters)) :term) "cargo"))
    (should (plist-get (cadr (plist-get key :filters)) :negated))))

(ert-deftest haystack-test/frecency-chain-key-filename-prefix ()
  "Filename filters produce :filename t in the filter plist."
  (let ((key (haystack--frecency-chain-key
              (haystack-sd-create :root-term "notes" :root-filename nil :root-literal nil
                :root-regex nil :root-kind nil
                :filters '((:term "cargo" :negated nil :filename t
                            :literal nil :regex nil))))))
    (should (equal (plist-get (plist-get key :root) :term) "notes"))
    (should (plist-get (car (plist-get key :filters)) :filename))))

(ert-deftest haystack-test/frecency-chain-key-root-modifiers ()
  "Root modifier flags produce :filename t in the root plist."
  (let ((key (haystack--frecency-chain-key
              (haystack-sd-create :root-term "cargo" :root-filename t :root-literal nil
                :root-regex nil :filters nil :root-kind nil))))
    (should (plist-get (plist-get key :root) :filename))
    (should (equal (plist-get (plist-get key :root) :term) "cargo"))))

;;; frecency key shape (refactored plist format)

(ert-deftest haystack-test/frecency-chain-key-text-root-plist-shape ()
  "Text root key is a plist with :root kind=text and :filters ()."
  (let ((key (haystack--frecency-chain-key
              (haystack-sd-create :root-term "rust" :root-filename nil :root-literal nil
                :root-regex nil :filters nil :root-kind nil))))
    (should (equal (plist-get (plist-get key :root) :kind) 'text))
    (should (equal (plist-get (plist-get key :root) :term) "rust"))
    (should (null (plist-get key :filters)))))

(ert-deftest haystack-test/frecency-chain-key-date-root-plist-shape ()
  "Date-range root key is a plist with :root kind=date-range, :start, :end."
  (let* ((desc (haystack--date-root-descriptor "2024-01" "2024-03"))
         (key (haystack--frecency-chain-key desc)))
    (should (equal (plist-get (plist-get key :root) :kind) 'date-range))
    (should (equal (plist-get (plist-get key :root) :start) "2024-01"))
    (should (equal (plist-get (plist-get key :root) :end) "2024-03"))))

(ert-deftest haystack-test/frecency-chain-key-filters-plist-shape ()
  "Filter terms are plists with at least :term; :negated and :filename when set."
  (let* ((key (haystack--frecency-chain-key
               (haystack-sd-create :root-term "rust" :root-filename nil :root-literal nil
                 :root-regex nil :root-kind nil
                 :filters '((:term "async" :negated nil :filename nil
                             :literal nil :regex nil)
                            (:term "cargo" :negated t :filename nil
                             :literal nil :regex nil))))))
    (let ((f1 (car (plist-get key :filters)))
          (f2 (cadr (plist-get key :filters))))
      (should (equal (plist-get f1 :term) "async"))
      (should (null (plist-get f1 :negated)))
      (should (equal (plist-get f2 :term) "cargo"))
      (should (plist-get f2 :negated)))))

(ert-deftest haystack-test/frecency-chain-key-date-filter-in-filters ()
  "A date-range filter entry passes through as :kind date-range in the key."
  (let* ((key (haystack--frecency-chain-key
               (haystack-sd-create :root-term "rust" :root-filename nil :root-literal nil
                     :root-regex nil :root-kind 'text :root-expansion nil
                     :filters (list (list :kind 'date-range
                                          :start "2025-01" :end "2025-03")))))
         (f (car (plist-get key :filters))))
    (should (eq (plist-get f :kind) 'date-range))
    (should (equal (plist-get f :start) "2025-01"))
    (should (equal (plist-get f :end) "2025-03"))))

(ert-deftest haystack-test/frecency-chain-key-includes-root-scope ()
  "Root scope is recorded in the frecency chain key."
  (let ((key (haystack--frecency-chain-key
              (haystack-sd-create :root-term "rust" :root-filename nil :root-literal nil
                :root-regex nil :root-kind nil :root-scope 'body :filters nil))))
    (should (eq (plist-get (plist-get key :root) :scope) 'body))))

(ert-deftest haystack-test/frecency-chain-key-includes-filter-scope ()
  "Filter scope is recorded in the frecency chain key."
  (let ((key (haystack--frecency-chain-key
              (haystack-sd-create :root-term "rust" :root-filename nil :root-literal nil
                :root-regex nil :root-kind nil :filters
                '((:term "title" :scope frontmatter))))))
    (should (eq (plist-get (car (plist-get key :filters)) :scope) 'frontmatter))))

(ert-deftest haystack-test/frecency-chain-key-omits-nil-scope ()
  "Nil scope is not stored in the chain key (backward compat)."
  (let ((key (haystack--frecency-chain-key
              (haystack-sd-create :root-term "rust" :root-filename nil :root-literal nil
                :root-regex nil :root-kind nil :root-scope nil :filters nil))))
    (should (null (plist-get (plist-get key :root) :scope)))))

(ert-deftest haystack-test/frecency-key-root-term-includes-scope ()
  "Root term reconstruction includes the scope prefix."
  (let ((key (list :root (list :kind 'text :term "rust" :scope 'body)
                   :filters nil)))
    (should (equal (haystack--frecency-key-root-term key) ">rust")))
  (let ((key (list :root (list :kind 'text :term "rust" :literal t :scope 'frontmatter)
                   :filters nil)))
    (should (equal (haystack--frecency-key-root-term key) "<=rust"))))

(ert-deftest haystack-test/frecency-key-display-includes-scope ()
  "Display string includes scope prefix."
  (let ((key (list :root (list :kind 'text :term "rust" :scope 'body)
                   :filters (list (list :term "title" :scope 'frontmatter)))))
    (should (equal (haystack--frecency-key-display key) ">rust > <title"))))

;;; frecency UI label for plist keys

(ert-deftest haystack-test/frecency-key-display-text-root ()
  "haystack--frecency-key-display produces a readable string for text roots."
  (let* ((key (haystack--frecency-chain-key
               (haystack-sd-create :root-term "rust" :root-filename nil :root-literal nil
                 :root-regex nil :root-kind nil :filters nil))))
    (should (equal (haystack--frecency-key-display key) "rust"))))

(ert-deftest haystack-test/frecency-key-display-date-root ()
  "haystack--frecency-key-display shows date: prefix for date-range roots."
  (let* ((desc (haystack--date-root-descriptor "2024-01" "2024-03"))
         (key (haystack--frecency-chain-key desc)))
    (should (string-prefix-p "date:" (haystack--frecency-key-display key)))))

(ert-deftest haystack-test/frecency-key-display-with-filters ()
  "haystack--frecency-key-display includes filters separated by \" > \"."
  (let* ((key (haystack--frecency-chain-key
               (haystack-sd-create :root-term "rust" :root-filename nil :root-literal nil
                 :root-regex nil :root-kind nil
                 :filters '((:term "async" :negated nil :filename nil
                             :literal nil :regex nil))))))
    (should (string-match-p " > async" (haystack--frecency-key-display key)))))

(ert-deftest haystack-test/frecency-key-display-date-filter-in-filters ()
  "haystack--frecency-key-display renders a date filter entry as date:LABEL."
  (let* ((key (list :root (list :kind 'text :term "rust")
                    :filters (list (list :kind 'date-range
                                         :start "2025-01" :end "2025-03"))))
         (display (haystack--frecency-key-display key)))
    (should (string-match-p "rust" display))
    (should (string-match-p "date:" display))
    (should (string-match-p " > " display))))

;;; frecency replay with plist keys

(ert-deftest haystack-test/frecency-replay-text-root ()
  "Replaying a text-root plist key runs haystack-run-root-search."
  (haystack-test--with-notes-dir
   (let ((note (expand-file-name "20240101000000-replay-test.org"
                                 haystack-notes-directory)))
     (with-temp-file note (insert "replay-unique-keyword\n")))
   (haystack-test--with-frecency nil
     (cl-letf (((symbol-function 'haystack--load-frecency) #'ignore)
               ((symbol-function 'pop-to-buffer)    #'ignore)
               ((symbol-function 'switch-to-buffer) #'ignore))
       (let* ((key (haystack--frecency-chain-key
                    (haystack-sd-create :root-term "replay-unique-keyword"
                      :root-filename nil :root-literal nil
                      :root-regex nil :root-kind nil :filters nil)))
              (buf (haystack--frecency-replay key)))
         (unwind-protect
             (progn
               (should (bufferp buf))
               (with-current-buffer buf
                 (should (string-match-p "replay-unique" (buffer-string)))))
           (when (buffer-live-p buf) (kill-buffer buf))))))))

(ert-deftest haystack-test/frecency-replay-date-root ()
  "Replaying a date-root plist key dispatches to haystack-search-date-range."
  (haystack-test--with-notes-dir
   (let ((note (expand-file-name "20240101000000-date-replay.org"
                                 haystack-notes-directory)))
     (with-temp-file note
       (insert "date replay hs: <2024-06-15 Sat 10:00>\n")))
   (haystack-test--with-frecency nil
     (cl-letf (((symbol-function 'haystack--load-frecency) #'ignore)
               ((symbol-function 'pop-to-buffer)    #'ignore)
               ((symbol-function 'switch-to-buffer) #'ignore))
       (let* ((desc (haystack--date-root-descriptor "2024-06" "2024-06"))
              (key  (haystack--frecency-chain-key desc))
              (buf  (haystack--frecency-replay key)))
         (unwind-protect
             (progn
               (should (bufferp buf))
               (with-current-buffer buf
                 (should (string-match-p "hs: " (buffer-string)))))
           (when (buffer-live-p buf) (kill-buffer buf))))))))

(ert-deftest haystack-test/frecency-replay-dispatches-date-filter ()
  "Replaying a key with a date-range filter applies the date filter correctly.
A note within the range must appear; a note outside the range must not."
  (haystack-test--with-notes-dir
   (let ((jan-note (expand-file-name "20250115090000-jan-replay.org"
                                     haystack-notes-directory))
         (mar-note (expand-file-name "20250310110000-mar-replay.org"
                                     haystack-notes-directory)))
     (with-temp-file jan-note
       (insert "rustlang hs: <2025-01-15 Wed 09:00>\n"))
     (with-temp-file mar-note
       (insert "rustlang hs: <2025-03-10 Mon 11:00>\n")))
   (haystack-test--with-frecency nil
     (cl-letf (((symbol-function 'haystack--load-frecency) #'ignore)
               ((symbol-function 'pop-to-buffer)    #'ignore)
               ((symbol-function 'switch-to-buffer) #'ignore))
       (let* ((key (list :root (list :kind 'text :term "rustlang")
                         :filters (list (list :kind 'date-range
                                              :term "2025-01..2025-01"
                                              :start "2025-01" :end "2025-01"))))
              (buf (haystack--frecency-replay key)))
         (unwind-protect
             (progn
               (should (bufferp buf))
               (with-current-buffer buf
                 (should     (string-match-p "jan-replay" (buffer-string)))
                 (should-not (string-match-p "mar-replay" (buffer-string)))))
           (when (buffer-live-p buf) (kill-buffer buf))))))))

(ert-deftest haystack-test/frecency-replay-does-not-inflate-intermediate-scores ()
  "Replaying a 2-step chain records only the leaf, not the intermediate root."
  (haystack-test--with-notes-dir
   (let ((note (expand-file-name "20240101000000-inflate-test.org"
                                 haystack-notes-directory)))
     (with-temp-file note (insert "rust async content\n")))
   (haystack-test--with-frecency nil
     (cl-letf (((symbol-function 'haystack--load-frecency) #'ignore)
               ((symbol-function 'pop-to-buffer)    #'ignore)
               ((symbol-function 'switch-to-buffer) #'ignore))
       (let* ((key (list :root (list :kind 'text :term "rust")
                         :filters (list (list :term "async"))))
              (buf (haystack--frecency-replay key)))
         (unwind-protect
             (let* ((root-key (haystack-test--tkey "rust"))
                    (leaf-key (haystack-test--tkey "rust" "async"))
                    (root-entry (assoc root-key haystack--frecency-data))
                    (leaf-entry (assoc leaf-key haystack--frecency-data)))
               ;; The root should NOT have been recorded during replay
               (should-not root-entry)
               ;; The leaf SHOULD have been recorded (the final step)
               (should leaf-entry)
               (should (= 1 (plist-get (cdr leaf-entry) :count))))
           (when (buffer-live-p buf) (kill-buffer buf))))))))

;;; haystack--frecency-record

(ert-deftest haystack-test/frecency-record-creates-entry ()
  "Recording a new descriptor creates an entry with count 1."
  (haystack-test--with-frecency nil
    (haystack--frecency-record
     (haystack-sd-create :root-term "rust" :root-filename nil :root-literal nil
       :root-regex nil :filters nil :root-kind nil))
    (let ((entry (assoc (haystack-test--tkey "rust") haystack--frecency-data)))
      (should entry)
      (should (= 1 (plist-get (cdr entry) :count))))))

(ert-deftest haystack-test/frecency-record-increments-count ()
  "Recording the same descriptor a second time increments the count."
  (haystack-test--with-frecency nil
    (let ((desc (haystack-sd-create :root-term "rust" :root-filename nil :root-literal nil
                  :root-regex nil :filters nil :root-kind nil)))
      (haystack--frecency-record desc)
      (haystack--frecency-record desc)
      (let ((entry (assoc (haystack-test--tkey "rust") haystack--frecency-data)))
        (should (= 2 (plist-get (cdr entry) :count)))))))

(ert-deftest haystack-test/frecency-record-sets-dirty ()
  "Recording sets `haystack--frecency-dirty'."
  (haystack-test--with-frecency nil
    (haystack--frecency-record
     (haystack-sd-create :root-term "rust" :root-filename nil :root-literal nil
       :root-regex nil :filters nil))
    (should haystack--frecency-dirty)))

(ert-deftest haystack-test/frecency-record-distinct-chains ()
  "Different chains are stored as separate entries."
  (haystack-test--with-frecency nil
    (haystack--frecency-record
     (haystack-sd-create :root-term "rust" :root-filename nil :root-literal nil
       :root-regex nil :filters nil))
    (haystack--frecency-record
     (haystack-sd-create :root-term "python" :root-filename nil :root-literal nil
       :root-regex nil :filters nil))
    (should (= 2 (length haystack--frecency-data)))))

(ert-deftest haystack-test/frecency-record-nil-interval-flushes ()
  "When `haystack-frecency-save-interval' is nil, recording flushes immediately."
  (haystack-test--with-notes-dir
    (haystack-test--with-frecency nil
      (let ((haystack-frecency-save-interval nil))
        (haystack--frecency-record
         (haystack-sd-create :root-term "rust" :root-filename nil :root-literal nil
           :root-regex nil :filters nil))
        (should (not haystack--frecency-dirty))
        (should (file-exists-p (haystack--frecency-file)))))))

;;; haystack--frecent-leaf-p / haystack--frecent-leaves

(ert-deftest haystack-test/frecent-leaf-p-standalone-is-leaf ()
  "An entry with no deeper chain is always a leaf."
  (let* ((now (float-time))
         (entries (list (cons (haystack-test--tkey "rust") (list :count 5 :last-access now)))))
    (should (haystack--frecent-leaf-p (car entries) entries))))

(ert-deftest haystack-test/frecent-leaf-p-dominated-is-not-leaf ()
  "An entry dominated by a deeper higher-scored chain is not a leaf."
  (let* ((now (float-time))
         (root  (cons (haystack-test--tkey "rust")         (list :count 2 :last-access now)))
         (child (cons (haystack-test--tkey "rust" "async") (list :count 5 :last-access now)))
         (entries (list root child)))
    (should-not (haystack--frecent-leaf-p root entries))
    (should     (haystack--frecent-leaf-p child entries))))

(ert-deftest haystack-test/frecent-leaf-p-higher-scored-root-is-leaf ()
  "A root with higher score than its child is still a leaf."
  (let* ((now (float-time))
         (root  (cons (haystack-test--tkey "rust")         (list :count 5 :last-access now)))
         (child (cons (haystack-test--tkey "rust" "async") (list :count 2 :last-access now)))
         (entries (list root child)))
    (should (haystack--frecent-leaf-p root  entries))
    (should (haystack--frecent-leaf-p child entries))))

(ert-deftest haystack-test/frecent-leaves-filters-correctly ()
  "`haystack--frecent-leaves' keeps only leaf entries."
  (let* ((now (float-time))
         (root  (cons (haystack-test--tkey "rust")         (list :count 2 :last-access now)))
         (child (cons (haystack-test--tkey "rust" "async") (list :count 5 :last-access now)))
         (other (cons (haystack-test--tkey "python")       (list :count 3 :last-access now)))
         (entries (list root child other)))
    (let ((leaves (haystack--frecent-leaves entries)))
      (should     (member child leaves))
      (should     (member other leaves))
      (should-not (member root  leaves)))))

(ert-deftest haystack-test/frecent-leaves-equal-score-both-survive ()
  "When parent and child have equal scores, both survive as leaves.
The <= comparison in `haystack--frecent-leaves' means a descendant
must strictly dominate its ancestor to prune it."
  (let* ((now    (float-time))
         (root  (cons (haystack-test--tkey "rust")         (list :count 5 :last-access now)))
         (child (cons (haystack-test--tkey "rust" "async") (list :count 5 :last-access now)))
         (entries (list root child)))
    (let ((leaves (haystack--frecent-leaves entries)))
      (should (assoc (haystack-test--tkey "rust") leaves))
      (should (assoc (haystack-test--tkey "rust" "async") leaves)))))

;;; haystack--frecency-score

(ert-deftest haystack-test/frecency-score-recent-entry ()
  "An entry accessed just now has score ≈ count (days ≈ 0 → clamped to 1)."
  (let ((entry (cons (haystack-test--tkey "rust")
                     (list :count 5 :last-access (float-time)))))
    (should (= 5.0 (haystack--frecency-score entry)))))

(ert-deftest haystack-test/frecency-score-old-entry ()
  "An entry accessed 5 days ago has score ≈ count / 5."
  (let* ((five-days-ago (- (float-time) (* 5 86400)))
         (entry (cons (haystack-test--tkey "rust")
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
    (haystack-test--with-frecency (list (cons (haystack-test--tkey "rust") '(:count 1 :last-access 0.0)))
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
           (key   (haystack-test--tkey "rust" "async"))
           (data  (list (cons key (list :count 3 :last-access now)))))
      (haystack-test--with-frecency data
        (setq haystack--frecency-dirty t)
        (haystack--frecency-flush))
      (haystack-test--with-frecency nil
        (haystack--load-frecency)
        (let ((entry (assoc key haystack--frecency-data)))
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
      (should (assoc (haystack-test--tkey "rust") haystack--frecency-data)))))

(ert-deftest haystack-test/search-date-range-records-frecency ()
  "haystack-search-date-range records an entry in haystack--frecency-data."
  (haystack-test--with-frecency nil
    (haystack-test--with-notes-dir
      (let ((note (expand-file-name "20240101000000-ts.org" haystack-notes-directory)))
        (with-temp-file note (insert "hs: <2024-06-15 Sat 10:00>\n")))
      (let (created-buf)
        (cl-letf (((symbol-function 'pop-to-buffer)
                   (lambda (buf &rest _) (setq created-buf buf))))
          (haystack-search-date-range "2024-06" "2024-06"))
        (when (buffer-live-p created-buf) (kill-buffer created-buf)))
      (let* ((desc (haystack--date-root-descriptor "2024-06" "2024-06"))
             (key  (haystack--frecency-chain-key desc)))
        (should (assoc key haystack--frecency-data))))))

(ert-deftest haystack-test/search-date-range-no-bounds-records-frecency ()
  "haystack-search-date-range with empty bounds records frecency."
  (haystack-test--with-frecency nil
    (haystack-test--with-notes-dir
      (let ((note (expand-file-name "20240101000000-ts.org" haystack-notes-directory)))
        (with-temp-file note (insert "hs: <2024-06-15 Sat 10:00>\n")))
      (let (created-buf)
        (cl-letf (((symbol-function 'pop-to-buffer)
                   (lambda (buf &rest _) (setq created-buf buf))))
          (haystack-search-date-range "" ""))
        (when (buffer-live-p created-buf) (kill-buffer created-buf)))
      (let* ((desc (haystack--date-root-descriptor "" ""))
             (key  (haystack--frecency-chain-key desc)))
        (should (assoc key haystack--frecency-data))
        (should (equal "date:all"
                       (haystack--frecency-key-display key)))))))

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
         (data (list (cons (haystack-test--tkey "rust")   (list :count 5 :last-access now))
                     (cons (haystack-test--tkey "python") (list :count 2 :last-access now)))))
    (haystack-test--with-frecent-buf data
      (should (string-match-p "rust" (buffer-string)))
      (should (string-match-p "python" (buffer-string))))))

(ert-deftest haystack-test/describe-frecent-chain-text-property ()
  "Entry lines carry a `haystack-frecent-chain' text property."
  (let* ((now  (float-time))
         (data (list (cons (haystack-test--tkey "rust") (list :count 5 :last-access now)))))
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
         (key  (haystack-test--tkey "rust"))
         (data (list (cons key (list :count 5 :last-access now)))))
    (haystack-test--with-frecent-buf data
      (goto-char (point-min))
      (while (and (not (get-text-property (point) 'haystack-frecent-chain))
                  (not (eobp)))
        (forward-line 1))
      (cl-letf (((symbol-function 'y-or-n-p) (lambda (_) t)))
        (haystack-frecent-kill-entry))
      (should (null (assoc key haystack--frecency-data))))))

(ert-deftest haystack-test/frecent-kill-entry-sets-dirty ()
  "k sets the frecency dirty flag."
  (let* ((now  (float-time))
         (data (list (cons (haystack-test--tkey "rust") (list :count 5 :last-access now)))))
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
         (key  (haystack-test--tkey "rust"))
         (data (list (cons key (list :count 5 :last-access now)))))
    (haystack-test--with-frecent-buf data
      (goto-char (point-min))
      (while (and (not (get-text-property (point) 'haystack-frecent-chain))
                  (not (eobp)))
        (forward-line 1))
      (cl-letf (((symbol-function 'y-or-n-p) (lambda (_) nil)))
        (haystack-frecent-kill-entry))
      (should (assoc key haystack--frecency-data)))))

(ert-deftest haystack-test/frecent-kill-entry-errors-off-entry ()
  "k signals user-error when point is not on an entry line."
  (haystack-test--with-frecent-buf nil
    (goto-char (point-min))
    (should-error (haystack-frecent-kill-entry) :type 'user-error)))

(ert-deftest haystack-test/frecent-kill-region-removes-entries ()
  "K on a region removes all entries in the region."
  (let* ((now  (float-time))
         (k1   (haystack-test--tkey "rust"))
         (k2   (haystack-test--tkey "emacs"))
         (k3   (haystack-test--tkey "lisp"))
         (data (list (cons k1 (list :count 5 :last-access now))
                     (cons k2 (list :count 3 :last-access now))
                     (cons k3 (list :count 1 :last-access now)))))
    (haystack-test--with-frecent-buf data
      ;; Find first and last entry lines to form a region covering all three
      (goto-char (point-min))
      (let ((first-entry nil) (last-entry nil))
        (while (not (eobp))
          (when (get-text-property (point) 'haystack-frecent-chain)
            (unless first-entry (setq first-entry (line-beginning-position)))
            (setq last-entry (line-end-position)))
          (forward-line 1))
        (cl-letf (((symbol-function 'y-or-n-p) (lambda (_) t)))
          (haystack-frecent-kill-region first-entry last-entry))
        (should (null haystack--frecency-data))))))

(ert-deftest haystack-test/frecent-kill-region-preserves-outside ()
  "K on a region only removes entries inside the region."
  (let* ((now  (float-time))
         (k1   (haystack-test--tkey "aaa"))
         (k2   (haystack-test--tkey "bbb"))
         (data (list (cons k1 (list :count 5 :last-access now))
                     (cons k2 (list :count 3 :last-access now)))))
    (haystack-test--with-frecent-buf data
      ;; Select only the first entry line
      (goto-char (point-min))
      (while (and (not (get-text-property (point) 'haystack-frecent-chain))
                  (not (eobp)))
        (forward-line 1))
      (let ((beg (line-beginning-position))
            (end (line-end-position)))
        (cl-letf (((symbol-function 'y-or-n-p) (lambda (_) t)))
          (haystack-frecent-kill-region beg end))
        (should (= 1 (length haystack--frecency-data)))))))

(ert-deftest haystack-test/frecent-kill-region-aborts-on-no ()
  "K leaves data intact when user answers no."
  (let* ((now  (float-time))
         (k1   (haystack-test--tkey "rust"))
         (data (list (cons k1 (list :count 5 :last-access now)))))
    (haystack-test--with-frecent-buf data
      (goto-char (point-min))
      (while (and (not (get-text-property (point) 'haystack-frecent-chain))
                  (not (eobp)))
        (forward-line 1))
      (let ((beg (line-beginning-position))
            (end (line-end-position)))
        (cl-letf (((symbol-function 'y-or-n-p) (lambda (_) nil)))
          (haystack-frecent-kill-region beg end))
        (should (= 1 (length haystack--frecency-data)))))))

(ert-deftest haystack-test/frecent-kill-region-errors-empty ()
  "K on a region with no entries signals user-error."
  (haystack-test--with-frecent-buf nil
    (should-error (haystack-frecent-kill-region (point-min) (point-max))
                  :type 'user-error)))

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
         (data (list (cons (haystack-test--tkey "rust")         (list :count 2 :last-access now))
                     (cons (haystack-test--tkey "rust" "async") (list :count 5 :last-access now)))))
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

;;;; haystack--descriptor-leaf-label

(ert-deftest haystack-test/descriptor-leaf-label-no-filters ()
  "Returns root term label when descriptor has no filters."
  (let ((descriptor (haystack-sd-create :root-term "rust" :root-filename nil
                      :root-literal t :root-regex nil :filters nil)))
    (should (string= (haystack--descriptor-leaf-label descriptor) "=rust"))))

(ert-deftest haystack-test/descriptor-leaf-label-with-filters ()
  "Returns last filter label when descriptor has filters."
  (let ((descriptor (haystack-sd-create :root-term "rust" :root-filename nil
                      :root-literal nil :root-regex nil
                      :filters '((:term "async" :negated nil
                                 :filename nil :literal nil :regex nil)
                                (:term "cargo" :negated t
                                 :filename nil :literal nil :regex nil)))))
    (should (string= (haystack--descriptor-leaf-label descriptor) "!cargo"))))

;;;; Tree view

(ert-deftest haystack-test/tree-roots-finds-root-buffers ()
  "Returns buffers with no live parent."
  (let* ((root  (haystack-test--make-results-buf " *hs-tree-root*"  nil (haystack-sd-create :root-term "rust" :filters nil)))
         (child (haystack-test--make-results-buf " *hs-tree-child*" root (haystack-sd-create :root-term "rust" :filters '((:term "async"))))))
    (unwind-protect
        (let ((roots (haystack--tree-roots)))
          (should     (memq root  roots))
          (should-not (memq child roots)))
      (kill-buffer root)
      (kill-buffer child))))

(ert-deftest haystack-test/tree-roots-treats-dead-parent-as-root ()
  "A buffer whose parent is dead is treated as a root."
  (let* ((dead-parent (haystack-test--make-results-buf " *hs-tree-dead*" nil (haystack-sd-create :root-term "x" :filters nil)))
         (orphan      (haystack-test--make-results-buf " *hs-tree-orphan*" dead-parent (haystack-sd-create :root-term "x" :filters '((:term "y"))))))
    (kill-buffer dead-parent)
    (unwind-protect
        (should (memq orphan (haystack--tree-roots)))
      (kill-buffer orphan))))

(ert-deftest haystack-test/tree-render-node-leaf-term ()
  "Renders the leaf filter term for child buffers."
  (let* ((root  (haystack-test--make-results-buf " *hs-rn-root*" nil (haystack-sd-create :root-term "rust" :filters nil)))
         (child (haystack-test--make-results-buf " *hs-rn-child*" root (haystack-sd-create :root-term "rust" :filters '((:term "async"))))))
    (unwind-protect
        (with-temp-buffer
          (haystack--tree-render-node root nil "" "" 0)
          (should (string-match-p "rust"  (buffer-string)))
          (should (string-match-p "async" (buffer-string))))
      (kill-buffer root)
      (kill-buffer child))))

(ert-deftest haystack-test/tree-render-node-marks-current ()
  "Current buffer line contains ←."
  (let ((root (haystack-test--make-results-buf " *hs-rn-cur*" nil (haystack-sd-create :root-term "rust" :filters nil))))
    (unwind-protect
        (with-temp-buffer
          (haystack--tree-render-node root root "" "" 0)
          (should (string-match-p "←" (buffer-string))))
      (kill-buffer root))))

(ert-deftest haystack-test/tree-render-node-indents-children ()
  "Child nodes are indented relative to their parent."
  (let* ((root  (haystack-test--make-results-buf " *hs-ind-root*" nil (haystack-sd-create :root-term "rust" :filters nil)))
         (child (haystack-test--make-results-buf " *hs-ind-child*" root (haystack-sd-create :root-term "rust" :filters '((:term "async"))))))
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
  (let* ((root  (haystack-test--make-results-buf " *hs-dp-root*" nil (haystack-sd-create :root-term "rust" :filters nil)))
         (child (haystack-test--make-results-buf " *hs-dp-child*" root (haystack-sd-create :root-term "rust" :filters '((:term "async"))))))
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
                   (haystack-sd-create :root-term "rust" :root-filename nil
                     :root-literal nil :root-regex nil :filters nil)))
           (child1 (haystack-test--make-results-buf
                    " *hs-nav-c1*" root
                    (haystack-sd-create :root-term "rust" :filters '((:term "async" :negated nil
                                                   :filename nil :literal nil :regex nil)))))
           (child2 (haystack-test--make-results-buf
                    " *hs-nav-c2*" root
                    (haystack-sd-create :root-term "rust" :filters '((:term "ownership" :negated nil
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
  (let ((root (haystack-test--make-results-buf " *hs-tp-root*" nil (haystack-sd-create :root-term "rust" :filters nil))))
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
          (setq haystack--search-descriptor (haystack-sd-create :root-term "rust" :filters nil)
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
                                              (haystack-sd-create :root-term "rust" :filters nil))))
    (unwind-protect
        (with-current-buffer buf
          (haystack-go-root)
          (should (eq (current-buffer) buf)))
      (kill-buffer buf))))

(ert-deftest haystack-test/go-root-walks-to-root ()
  "haystack-go-root switches to the root buffer from a child."
  (let* ((root  (haystack-test--make-results-buf " *hs-r-root*" nil
                                                 (haystack-sd-create :root-term "rust" :filters nil)))
         (child (haystack-test--make-results-buf " *hs-r-child*" root
                                                 (haystack-sd-create :root-term "rust" :filters '((:term "async"))))))
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

(ert-deftest haystack-test/demo-deep-copies-mutable-state ()
  "Demo mode deep-copies frecency and expansion-group state.
A stale reference to a pre-demo nested cons cell, if mutated during demo,
must not corrupt the saved state that demo-stop restores from."
  (haystack-test--with-demo-dir
   (let ((haystack--expansion-groups
          '(("lang" . ("rust" "python")))))
     ;; Capture a reference to the shared nested cons cell BEFORE demo.
     (let ((stale-cell (assoc "lang" haystack--expansion-groups)))
       (haystack-demo)
       ;; Mutate through the stale reference — with copy-sequence, this
       ;; also mutates the saved state because the cons cell is shared.
       (setcdr stale-cell '("go" "java"))
       ;; Restore — the saved state must be unaffected by the mutation.
       (haystack-demo-stop)
       (should (equal (cdr (assoc "lang" haystack--expansion-groups))
                      '("rust" "python")))))))

(ert-deftest haystack-test/demo-binds-and-releases-C-c-h ()
  "demo binds C-c h when free and releases it on stop."
  (haystack-test--with-demo-dir
   (let ((key (kbd "C-c h")))
     (global-unset-key key)
     (haystack-demo)
     (should (eq (lookup-key global-map key) haystack-prefix-map))
     (haystack-demo-stop)
     (should (null (lookup-key global-map key))))))

(ert-deftest haystack-test/demo-skips-keybind-when-C-c-h-taken ()
  "demo leaves C-c h untouched when it is already bound."
  (haystack-test--with-demo-dir
   (let ((key (kbd "C-c h"))
         (sentinel (lambda () (interactive))))
     (global-set-key key sentinel)
     (unwind-protect
         (progn
           (haystack-demo)
           (should (eq (lookup-key global-map key) sentinel))
           (haystack-demo-stop)
           (should (eq (lookup-key global-map key) sentinel)))
       (global-unset-key key)))))

;;;; haystack--format-chain-lines

(ert-deftest haystack-test/format-chain-lines-single-term ()
  "Single-term chain produces one ;;;;  line."
  (let ((lines (haystack--format-chain-lines "root=rust")))
    (should (equal lines ";;;;  root=rust\n"))))

(ert-deftest haystack-test/format-chain-lines-two-terms ()
  "Two-term chain produces root line plus one indented continuation."
  (let ((lines (haystack--format-chain-lines "root=rust > filter=async")))
    (should (equal lines ";;;;  root=rust\n;;;;    > filter=async\n"))))

(ert-deftest haystack-test/format-chain-lines-four-terms ()
  "Four-term chain produces four ;;;; lines."
  (let ((lines (haystack--format-chain-lines "root=ai > filter=training > filter=learning > filter=deep")))
    (should (= (length (split-string lines "\n" t)) 4))
    (should (string-match-p "root=ai" lines))
    (should (string-match-p "> filter=deep" lines))))

(ert-deftest haystack-test/format-header-multi-term-chain ()
  "format-header with a multi-term chain renders each term on its own line."
  (let ((h (haystack--format-header "root=rust > filter=async" 3 10)))
    (should (string-match-p ";;;;  root=rust" h))
    (should (string-match-p ";;;;    > filter=async" h))))

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
   (let ((desc (haystack-sd-create :root-term "rust" :root-literal nil :root-regex nil
                     :root-filename nil :filters nil)))
     (should-not (haystack--find-composite desc)))))

(ert-deftest haystack-test/find-composite-returns-path-when-present ()
  "Returns the absolute path when the composite file exists."
  (haystack-test--with-notes-dir
   (let* ((desc (haystack-sd-create :root-term "rust" :root-literal nil :root-regex nil
                      :root-filename nil :filters nil))
          (path (haystack--composite-filename desc)))
     (with-temp-file path (insert "placeholder"))
     (should (equal (haystack--find-composite desc) path)))))

(ert-deftest haystack-test/find-composite-nil-for-different-chain ()
  "Returns nil when a composite exists for a different chain."
  (haystack-test--with-notes-dir
   (let* ((desc-rust  (haystack-sd-create :root-term "rust"   :root-literal nil :root-regex nil
                            :root-filename nil :filters nil))
          (desc-async (haystack-sd-create :root-term "async"  :root-literal nil :root-regex nil
                            :root-filename nil :filters nil)))
     (with-temp-file (haystack--composite-filename desc-rust) (insert "placeholder"))
     (should-not (haystack--find-composite desc-async)))))

;;;; haystack--composite-filename

(ert-deftest haystack-test/composite-filename-basic ()
  "Returns absolute path @comp__SLUG.org in the notes directory."
  (haystack-test--with-notes-dir
   (let ((desc (haystack-sd-create :root-term "rust" :root-literal nil :root-regex nil
                     :root-filename nil :filters nil)))
     (should (equal (haystack--composite-filename desc)
                    (expand-file-name "@comp__rust.org" haystack-notes-directory))))))

(ert-deftest haystack-test/composite-filename-extension-is-always-org ()
  "Composite files always use the .org extension — the format is always org."
  (haystack-test--with-notes-dir
   (let ((desc (haystack-sd-create :root-term "rust" :root-literal nil :root-regex nil
                     :root-filename nil :filters nil)))
     (should (string-suffix-p ".org" (haystack--composite-filename desc))))))

(ert-deftest haystack-test/composite-filename-chain-in-name ()
  "Filter terms appear in the filename joined by __."
  (haystack-test--with-notes-dir
   (let ((desc (haystack-sd-create :root-term "rust" :root-literal nil :root-regex nil
                     :root-filename nil
                     :filters (list (list :term "async" :negated nil
                                          :filename nil :literal nil :regex nil)))))
     (should (equal (haystack--composite-filename desc)
                    (expand-file-name "@comp__rust__async.org"
                                      haystack-notes-directory))))))

;;;; haystack--canonical-chain-slug

(ert-deftest haystack-test/canonical-chain-slug-single-bare-term ()
  "A single bare term is lowercased and slugified."
  (let ((desc (haystack-sd-create :root-term "Rust" :root-literal nil :root-regex nil
                    :root-filename nil :filters nil)))
    (should (equal (haystack--canonical-chain-slug desc) "rust"))))

(ert-deftest haystack-test/canonical-chain-slug-resolves-group-root ()
  "A synonym resolves to its expansion group root."
  (haystack-test--with-groups '(("programming" . ("coding" "scripting")))
    (let ((desc (haystack-sd-create :root-term "coding" :root-literal nil :root-regex nil
                      :root-filename nil :filters nil)))
      (should (equal (haystack--canonical-chain-slug desc) "programming")))))

(ert-deftest haystack-test/canonical-chain-slug-with-filters ()
  "Filter terms are appended after the root, joined with __."
  (let ((desc (haystack-sd-create :root-term "rust" :root-literal nil :root-regex nil
                    :root-filename nil
                    :filters (list (list :term "async" :negated nil
                                         :filename nil :literal nil :regex nil)
                                   (list :term "tokio" :negated nil
                                         :filename nil :literal nil :regex nil)))))
    (should (equal (haystack--canonical-chain-slug desc) "rust__async__tokio"))))

(ert-deftest haystack-test/canonical-chain-slug-negated-filter ()
  "Negated filter terms are prefixed with not-."
  (let ((desc (haystack-sd-create :root-term "rust" :root-literal nil :root-regex nil
                    :root-filename nil
                    :filters (list (list :term "async" :negated t
                                         :filename nil :literal nil :regex nil)))))
    (should (equal (haystack--canonical-chain-slug desc) "rust__not-async"))))

(ert-deftest haystack-test/canonical-chain-slug-filename-filter ()
  "Filename filter terms are prefixed with fn-."
  (let ((desc (haystack-sd-create :root-term "rust" :root-literal nil :root-regex nil
                    :root-filename nil
                    :filters (list (list :term "cargo" :negated nil
                                         :filename t :literal nil :regex nil)))))
    (should (equal (haystack--canonical-chain-slug desc) "rust__fn-cargo"))))

(ert-deftest haystack-test/canonical-chain-slug-and-root ()
  "AND root terms are flattened into the slug with __ between them."
  (let ((desc (haystack-sd-create :root-term "rust & async" :root-literal nil :root-regex nil
                    :root-filename nil :filters nil)))
    (should (equal (haystack--canonical-chain-slug desc) "rust__async"))))

(ert-deftest haystack-test/canonical-chain-slug-and-root-with-filter ()
  "AND root + filter produces same slug as equivalent sequential filter chain."
  (let ((desc-and (haystack-sd-create :root-term "rust & async" :root-literal nil :root-regex nil
                         :root-filename nil
                         :filters (list (list :term "tokio" :negated nil
                                              :filename nil :literal nil :regex nil))))
        (desc-seq (haystack-sd-create :root-term "rust" :root-literal nil :root-regex nil
                         :root-filename nil
                         :filters (list (list :term "async" :negated nil
                                              :filename nil :literal nil :regex nil)
                                        (list :term "tokio" :negated nil
                                              :filename nil :literal nil :regex nil)))))
    (should (equal (haystack--canonical-chain-slug desc-and)
                   (haystack--canonical-chain-slug desc-seq)))))

(ert-deftest haystack-test/canonical-chain-slug-multi-word-term ()
  "Multi-word terms have spaces replaced with hyphens."
  (let ((desc (haystack-sd-create :root-term "emacs lisp" :root-literal nil :root-regex nil
                    :root-filename nil :filters nil)))
    (should (equal (haystack--canonical-chain-slug desc) "emacs-lisp"))))

(ert-deftest haystack-test/canonical-chain-slug-literal-prefix-stripped ()
  "The = literal prefix on a filter term does not appear in the slug."
  (let ((desc (haystack-sd-create :root-term "rust" :root-literal nil :root-regex nil
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
              " *hs-nwm-empty*" nil (haystack-sd-create :root-term "rust" :filters nil))))
    (unwind-protect
        (with-current-buffer buf
          (should-error (haystack-new-note-with-moc) :type 'user-error))
      (kill-buffer buf))))

(ert-deftest haystack-test/new-note-with-moc-creates-file ()
  "Creates a timestamped note file in the notes directory."
  (haystack-test--with-notes-dir
   (let ((buf (haystack-test--make-results-buf
               " *hs-nwm-creates*" nil (haystack-sd-create :root-term "rust" :filters nil))))
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
               " *hs-nwm-fm*" nil (haystack-sd-create :root-term "rust" :filters nil))))
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
               " *hs-nwm-insert*" nil (haystack-sd-create :root-term "rust" :filters nil)))
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
               " *hs-nwm-kr*" nil (haystack-sd-create :root-term "rust" :filters nil))))
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
               (haystack-sd-create :root-term "rust" :root-expansion nil :root-filename nil
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
               " *hs-nwm-hook*" nil (haystack-sd-create :root-term "rust" :filters nil)))
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
       (let ((buf (haystack--frecency-replay (haystack-test--tkey "zzznomatch"))))
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

;;;; Stop words — loaded flag

(ert-deftest haystack-test/stop-words-load-sets-loaded-flag ()
  "haystack--load-stop-words sets haystack--stop-words-loaded to t."
  (haystack-test--with-notes-dir
   (should-not haystack--stop-words-loaded)
   (haystack--load-stop-words)
   (should haystack--stop-words-loaded)))

(ert-deftest haystack-test/stop-words-load-sets-flag-even-when-no-file ()
  "haystack--load-stop-words sets the flag even when the file is absent."
  (haystack-test--with-notes-dir
   (should-not (file-exists-p (haystack--stop-words-file)))
   (haystack--load-stop-words)
   (should haystack--stop-words-loaded)
   (should (null haystack--stop-words))))

(ert-deftest haystack-test/stop-words-ensure-does-not-reseed-empty-list ()
  "ensure-stop-words leaves nil in place when loaded flag is t — empty list is valid."
  (haystack-test--with-notes-dir
   (let ((haystack--stop-words nil)
         (haystack--stop-words-loaded t))
     (haystack--ensure-stop-words)
     (should (null haystack--stop-words)))))

(ert-deftest haystack-test/stop-words-reload-clears-flag-and-reloads ()
  "haystack-reload-stop-words forces a fresh read from disk."
  (haystack-test--with-notes-dir
   (haystack--ensure-stop-words)
   (should haystack--stop-words-loaded)
   ;; Mutate in-memory state.
   (setq haystack--stop-words '("only-word"))
   ;; Reload must re-read disk (which has the default set).
   (haystack-reload-stop-words)
   (should haystack--stop-words-loaded)
   (should (> (length haystack--stop-words) 50))
   (should (member "the" haystack--stop-words))))

(ert-deftest haystack-test/stop-words-reset-to-defaults-restores-full-list ()
  "haystack-reset-stop-words-to-defaults restores all default stop words."
  (haystack-test--with-notes-dir
   ;; Start with an empty list.
   (setq haystack--stop-words nil
         haystack--stop-words-loaded t)
   (haystack-reset-stop-words-to-defaults)
   (should (> (length haystack--stop-words) 50))
   (should (member "the" haystack--stop-words))
   (should (member "a" haystack--stop-words))))

(ert-deftest haystack-test/stop-words-reset-to-defaults-persists-to-disk ()
  "haystack-reset-stop-words-to-defaults saves the default list to disk."
  (haystack-test--with-notes-dir
   (haystack-reset-stop-words-to-defaults)
   (should (file-exists-p (haystack--stop-words-file)))
   ;; Reload from disk and verify defaults are there.
   (setq haystack--stop-words nil
         haystack--stop-words-loaded nil)
   (haystack--load-stop-words)
   (should (member "the" haystack--stop-words))))

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
             (should (haystack-sd-root-literal
                      (buffer-local-value 'haystack--search-descriptor buf)))
           (when (buffer-live-p buf) (kill-buffer buf))))))))

(ert-deftest haystack-test/stop-word-prompt-r-removes-and-searches-literally ()
  "Choosing r removes the word from the stop list and searches literally.
The literal prefix ensures that expansion-group roots are not expanded,
matching the behavior of ?s (search anyway)."
  (haystack-test--with-notes-dir
   (let ((haystack--stop-words '("the")))
     (cl-letf (((symbol-function 'haystack--stop-word-prompt)
                (lambda (_term) ?r))
               ((symbol-function 'pop-to-buffer) #'ignore))
       (let ((buf (haystack-run-root-search "the")))
         (unwind-protect
             (progn
               (should-not (member "the" haystack--stop-words))
               (should (haystack-sd-root-literal
                        (buffer-local-value 'haystack--search-descriptor buf))))
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

(ert-deftest haystack-test/discoverability-tokenize-latin-diacritics ()
  "Latin diacritics are preserved as tokens."
  (let ((haystack--stop-words '()))
    (should (member "café" (haystack--discoverability-tokenize "café résumé")))))

(ert-deftest haystack-test/discoverability-tokenize-emoji-splits ()
  "Emoji are treated as separators, not tokens (not alphanumeric)."
  (let ((haystack--stop-words '()))
    (let ((tokens (haystack--discoverability-tokenize "search 🔍 here")))
      (should (member "search" tokens))
      (should (member "here" tokens))
      (should-not (member "🔍" tokens)))))

(ert-deftest haystack-test/discoverability-tokenize-unicode-words ()
  "Non-ASCII alphabetic words are kept."
  (let ((haystack--stop-words '()))
    (let ((tokens (haystack--discoverability-tokenize "über straße naïve")))
      (should (member "über" tokens))
      (should (member "straße" tokens))
      (should (member "naïve" tokens)))))

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

;;;; haystack--discoverability-count-all-terms

(ert-deftest haystack-test/discoverability-count-all-basic ()
  "Returns correct per-token file counts from a single rg call."
  (haystack-test--with-notes-dir
   (let* ((dir (file-name-as-directory (expand-file-name haystack-notes-directory))))
     (write-region "rust emacs\n" nil (concat dir "note1.org"))
     (write-region "emacs python\n" nil (concat dir "note2.org"))
     (let ((result (haystack--discoverability-count-all-terms
                    '("rust" "emacs" "python" "missing"))))
       (should (= (cdr (assoc "rust"    result)) 1))
       (should (= (cdr (assoc "emacs"   result)) 2))
       (should (= (cdr (assoc "python"  result)) 1))
       (should (= (cdr (assoc "missing" result)) 0))))))

(ert-deftest haystack-test/discoverability-count-all-deduplicates-file-matches ()
  "Each file counted at most once per token even with repeated occurrences."
  (haystack-test--with-notes-dir
   (let* ((dir (file-name-as-directory (expand-file-name haystack-notes-directory))))
     (write-region "rust rust rust\n" nil (concat dir "note1.org"))
     (let ((result (haystack--discoverability-count-all-terms '("rust"))))
       (should (= (cdr (assoc "rust" result)) 1))))))

(ert-deftest haystack-test/discoverability-count-all-empty-tokens ()
  "Returns nil for empty token list without calling rg."
  (haystack-test--with-notes-dir
   (should (null (haystack--discoverability-count-all-terms nil)))))

(ert-deftest haystack-test/discoverability-count-all-skips-at-composites ()
  "Does not count @comp__ files."
  (haystack-test--with-notes-dir
   (let* ((dir (file-name-as-directory (expand-file-name haystack-notes-directory))))
     (write-region "rust\n" nil (concat dir "@comp__rust.org"))
     (let ((result (haystack--discoverability-count-all-terms '("rust"))))
       (should (= (cdr (assoc "rust" result)) 0))))))

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

(ert-deftest haystack-test/discoverability-refresh-reuses-buffer ()
  "Re-running reuses the existing discoverability buffer rather than killing it."
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
                       (should (eq r1 r2)))
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

(ert-deftest haystack-test/discoverability-at-point-creates-buffer ()
  "D in results buffer analyzes the file at point."
  (haystack-test--with-notes-dir
   (let* ((fname "20241215120000-test-note.org")
          (file  (expand-file-name fname haystack-notes-directory))
          (rbuf  (get-buffer-create "*haystack:test-discov-at-point*")))
     (with-temp-buffer
       (insert "uniqueterm12345 anotherterm67890")
       (write-region nil nil file))
     (unwind-protect
         (with-current-buffer rbuf
           (setq-local haystack--search-descriptor
                       (haystack-sd-create :root-term "test"))
           (setq-local haystack--buffer-notes-dir
                       (expand-file-name haystack-notes-directory))
           (insert (concat fname ":1:uniqueterm12345\n"))
           (goto-char (point-min))
           (cl-letf (((symbol-function 'pop-to-buffer) #'ignore))
             (let ((result (haystack-describe-discoverability-at-point)))
               (unwind-protect
                   (progn
                     (should (buffer-live-p result))
                     (should (eq (buffer-local-value 'major-mode result)
                                 'haystack-discoverability-mode)))
                 (when (buffer-live-p result) (kill-buffer result))))))
       (kill-buffer rbuf)
       (when (file-exists-p file) (delete-file file))))))

(ert-deftest haystack-test/discoverability-at-point-errors-not-results ()
  "D outside results buffer signals user-error."
  (with-temp-buffer
    (should-error (haystack-describe-discoverability-at-point)
                  :type 'user-error)))

(ert-deftest haystack-test/discoverability-at-point-errors-no-file ()
  "D on a non-grep line signals user-error."
  (haystack-test--with-notes-dir
   (let ((rbuf (get-buffer-create "*haystack:test-discov-no-file*")))
     (unwind-protect
         (with-current-buffer rbuf
           (setq-local haystack--search-descriptor
                       (haystack-sd-create :root-term "test"))
           (insert "this is not a grep line\n")
           (goto-char (point-min))
           (should-error (haystack-describe-discoverability-at-point)
                         :type 'user-error))
       (kill-buffer rbuf)))))

;;;; haystack--note-slug

(ert-deftest haystack-test/note-slug-strips-timestamp ()
  "Strips 14-digit timestamp prefix and file extension, keeps hyphens."
  (should (equal (haystack--note-slug "20240315142233-my-rust-notes.org")
                 "my-rust-notes")))

(ert-deftest haystack-test/note-slug-no-timestamp ()
  "Returns base name without extension when no timestamp is present."
  (should (equal (haystack--note-slug "my-rust-notes.org") "my-rust-notes")))

(ert-deftest haystack-test/note-slug-strips-directory ()
  "Only the basename is used; directory components are ignored."
  (should (equal (haystack--note-slug "/path/to/20240315142233-foo-bar.md")
                 "foo-bar")))

(ert-deftest haystack-test/note-slug-no-extension ()
  "Works when there is no file extension."
  (should (equal (haystack--note-slug "my-note") "my-note")))

;;;; haystack--mentions-separator

(ert-deftest haystack-test/mentions-separator-org ()
  (should (equal (haystack--mentions-separator "org") "-----")))

(ert-deftest haystack-test/mentions-separator-md ()
  (should (equal (haystack--mentions-separator "md") "---")))

(ert-deftest haystack-test/mentions-separator-markdown ()
  (should (equal (haystack--mentions-separator "markdown") "---")))

(ert-deftest haystack-test/mentions-separator-html ()
  (should (equal (haystack--mentions-separator "html") "<hr>")))

(ert-deftest haystack-test/mentions-separator-htm ()
  (should (equal (haystack--mentions-separator "htm") "<hr>")))

(ert-deftest haystack-test/mentions-separator-fallback ()
  (should (equal (haystack--mentions-separator "txt") "----")))

(ert-deftest haystack-test/mentions-separator-nil ()
  (should (equal (haystack--mentions-separator nil) "----")))

;;;; haystack--mentions-no-ref-comment

(ert-deftest haystack-test/mentions-no-ref-comment-org ()
  "Org comment starts with # and includes the slug."
  (let ((result (haystack--mentions-no-ref-comment "my-note" "org")))
    (should (string-prefix-p "# " result))
    (should (string-match-p "my-note" result))))

(ert-deftest haystack-test/mentions-no-ref-comment-md ()
  "Markdown comment uses HTML comment syntax and includes the slug."
  (let ((result (haystack--mentions-no-ref-comment "my-note" "md")))
    (should (string-prefix-p "<!-- " result))
    (should (string-suffix-p " -->" result))
    (should (string-match-p "my-note" result))))

(ert-deftest haystack-test/mentions-no-ref-comment-html ()
  "HTML comment uses HTML comment syntax and includes the slug."
  (let ((result (haystack--mentions-no-ref-comment "my-note" "html")))
    (should (string-prefix-p "<!-- " result))
    (should (string-suffix-p " -->" result))
    (should (string-match-p "my-note" result))))

(ert-deftest haystack-test/mentions-no-ref-comment-fallback ()
  "Unknown extension falls back to # comment style."
  (let ((result (haystack--mentions-no-ref-comment "my-note" "txt")))
    (should (string-prefix-p "# " result))
    (should (string-match-p "my-note" result))))

;;;; haystack-find-mentions

(ert-deftest haystack-test/find-mentions-errors-without-file ()
  "Signal user-error when called from a buffer not visiting a file."
  (with-temp-buffer
    (should-error (haystack-find-mentions) :type 'user-error)))

(ert-deftest haystack-test/find-mentions-sets-mentions-origin ()
  "Result buffer has haystack--mentions-origin set to the origin file path."
  (haystack-test--with-notes-dir
   (haystack-test--with-file-buffer "org"
     (cl-letf (((symbol-function 'pop-to-buffer)    #'ignore)
               ((symbol-function 'switch-to-buffer) #'ignore)
               ((symbol-function 'yes-or-no-p)      (lambda (_) t)))
       (let ((origin (buffer-file-name))
             (result-buf (haystack-find-mentions)))
         (unwind-protect
             (should (equal (buffer-local-value 'haystack--mentions-origin result-buf)
                            origin))
           (when (buffer-live-p result-buf) (kill-buffer result-buf))))))))

(ert-deftest haystack-test/find-mentions-renames-buffer ()
  "Result buffer name starts with *haystack-ref: prefix."
  (haystack-test--with-notes-dir
   (haystack-test--with-file-buffer "org"
     (cl-letf (((symbol-function 'pop-to-buffer)    #'ignore)
               ((symbol-function 'switch-to-buffer) #'ignore)
               ((symbol-function 'yes-or-no-p)      (lambda (_) t)))
       (let ((result-buf (haystack-find-mentions)))
         (unwind-protect
             (should (string-prefix-p "*haystack-ref:" (buffer-name result-buf)))
           (when (buffer-live-p result-buf) (kill-buffer result-buf))))))))

;;;; filter-further mentions tree inheritance

(ert-deftest haystack-test/filter-further-inherits-mentions-origin ()
  "Child buffer inherits haystack--mentions-origin from a mentions-tree parent."
  (haystack-test--with-notes-dir
   (let ((note (expand-file-name "20240101000000-test.org" haystack-notes-directory))
         (origin "/path/to/origin.org"))
     (with-temp-file note (insert "rust async content\n"))
     (cl-letf (((symbol-function 'pop-to-buffer)    #'ignore)
               ((symbol-function 'switch-to-buffer) #'ignore))
       (haystack-run-root-search "rust")
       (let ((root-buf (get-buffer "*haystack:1:=rust*")))
         ;; Fall back to the unescaped name if expansion groups are absent
         (unless root-buf (setq root-buf (get-buffer "*haystack:1:rust*")))
         (should root-buf)
         (with-current-buffer root-buf
           (setq-local haystack--mentions-origin origin))
         (unwind-protect
             (with-current-buffer root-buf
               (let ((child (haystack-filter-further "async")))
                 (unwind-protect
                     (should (equal (buffer-local-value 'haystack--mentions-origin child)
                                    origin))
                   (when (buffer-live-p child) (kill-buffer child)))))
           (kill-buffer root-buf)))))))

(ert-deftest haystack-test/filter-further-renames-child-in-mentions-tree ()
  "Child buffer name uses *haystack-ref: prefix when parent is a mentions buffer."
  (haystack-test--with-notes-dir
   (let ((note (expand-file-name "20240101000000-test.org" haystack-notes-directory))
         (origin "/path/to/origin.org"))
     (with-temp-file note (insert "rust async content\n"))
     (cl-letf (((symbol-function 'pop-to-buffer)    #'ignore)
               ((symbol-function 'switch-to-buffer) #'ignore))
       (haystack-run-root-search "rust")
       (let ((root-buf (get-buffer "*haystack:1:=rust*")))
         (unless root-buf (setq root-buf (get-buffer "*haystack:1:rust*")))
         (should root-buf)
         (with-current-buffer root-buf
           (setq-local haystack--mentions-origin origin))
         (unwind-protect
             (with-current-buffer root-buf
               (let ((child (haystack-filter-further "async")))
                 (unwind-protect
                     (should (string-prefix-p "*haystack-ref:" (buffer-name child)))
                   (when (buffer-live-p child) (kill-buffer child)))))
           (kill-buffer root-buf)))))))

(ert-deftest haystack-test/filter-further-no-rename-outside-mentions ()
  "Child buffer keeps standard *haystack: name when parent is not a mentions buffer."
  (haystack-test--with-notes-dir
   (let ((note (expand-file-name "20240101000000-test.org" haystack-notes-directory)))
     (with-temp-file note (insert "rust async content\n"))
     (cl-letf (((symbol-function 'pop-to-buffer)    #'ignore)
               ((symbol-function 'switch-to-buffer) #'ignore))
       (haystack-run-root-search "rust")
       (let ((root-buf (get-buffer "*haystack:1:=rust*")))
         (unless root-buf (setq root-buf (get-buffer "*haystack:1:rust*")))
         (should root-buf)
         ;; Ensure no mentions-origin is set (normal search, not mentions)
         (with-current-buffer root-buf
           (setq-local haystack--mentions-origin nil))
         (unwind-protect
             (with-current-buffer root-buf
               (let ((child (haystack-filter-further "async")))
                 (unwind-protect
                     (should (string-prefix-p "*haystack:" (buffer-name child)))
                   (when (buffer-live-p child) (kill-buffer child)))))
           (kill-buffer root-buf)))))))

(ert-deftest haystack-test/date-filter-inherits-mentions-origin ()
  "Date-filtered child inherits haystack--mentions-origin from parent."
  (haystack-test--with-notes-dir
   (let ((note (expand-file-name "20250115120000-test.org" haystack-notes-directory))
         (origin "/path/to/origin.org"))
     (with-temp-file note (insert "rust content hs: <2025-01-15 Wed 12:00>\n"))
     (cl-letf (((symbol-function 'pop-to-buffer)    #'ignore)
               ((symbol-function 'switch-to-buffer) #'ignore))
       (haystack-run-root-search "rust")
       (let ((root-buf (get-buffer "*haystack:1:=rust*")))
         (unless root-buf (setq root-buf (get-buffer "*haystack:1:rust*")))
         (should root-buf)
         (with-current-buffer root-buf
           (setq-local haystack--mentions-origin origin))
         (unwind-protect
             (with-current-buffer root-buf
               (let ((child (haystack-filter-further-by-date "2025-01" "2025-01")))
                 (unwind-protect
                     (progn
                       (should (equal (buffer-local-value 'haystack--mentions-origin child)
                                      origin))
                       (should (string-prefix-p "*haystack-ref:" (buffer-name child))))
                   (when (buffer-live-p child) (kill-buffer child)))))
           (kill-buffer root-buf)))))))

;;;; haystack-inherit-view-mode

(ert-deftest haystack-test/filter-further-inherits-view-mode-when-enabled ()
  "Child buffer inherits parent's view mode when `haystack-inherit-view-mode' is t."
  (haystack-test--with-notes-dir
   (let ((note (expand-file-name "20240101000000-test.org" haystack-notes-directory)))
     (with-temp-file note (insert "rust async content\n"))
     (cl-letf (((symbol-function 'pop-to-buffer)    #'ignore)
               ((symbol-function 'switch-to-buffer) #'ignore))
       (haystack-run-root-search "rust")
       (let ((root-buf (get-buffer "*haystack:1:=rust*")))
         (unless root-buf (setq root-buf (get-buffer "*haystack:1:rust*")))
         (should root-buf)
         (with-current-buffer root-buf
           (setq haystack--view-mode 'compact))
         (unwind-protect
             (with-current-buffer root-buf
               (let ((haystack-inherit-view-mode t))
                 (let ((child (haystack-filter-further "async")))
                   (unwind-protect
                       (should (eq (buffer-local-value 'haystack--view-mode child)
                                   'compact))
                     (when (buffer-live-p child) (kill-buffer child))))))
           (kill-buffer root-buf)))))))

(ert-deftest haystack-test/filter-further-does-not-inherit-view-mode-by-default ()
  "Child buffer starts in full view mode when `haystack-inherit-view-mode' is nil."
  (haystack-test--with-notes-dir
   (let ((note (expand-file-name "20240101000000-test.org" haystack-notes-directory)))
     (with-temp-file note (insert "rust async content\n"))
     (cl-letf (((symbol-function 'pop-to-buffer)    #'ignore)
               ((symbol-function 'switch-to-buffer) #'ignore))
       (haystack-run-root-search "rust")
       (let ((root-buf (get-buffer "*haystack:1:=rust*")))
         (unless root-buf (setq root-buf (get-buffer "*haystack:1:rust*")))
         (should root-buf)
         (with-current-buffer root-buf
           (setq haystack--view-mode 'compact))
         (unwind-protect
             (with-current-buffer root-buf
               (let ((haystack-inherit-view-mode nil))
                 (let ((child (haystack-filter-further "async")))
                   (unwind-protect
                       (should (eq (buffer-local-value 'haystack--view-mode child)
                                   'full))
                     (when (buffer-live-p child) (kill-buffer child))))))
           (kill-buffer root-buf)))))))

;;;; haystack--append-to-origin-file

(ert-deftest haystack-test/append-to-origin-file-appends-separator-and-content ()
  "Appends separator and content to the origin file and saves."
  (haystack-test--with-notes-dir
   (let* ((origin (expand-file-name "origin.org" haystack-notes-directory)))
     (write-region "initial content\n" nil origin)
     (haystack--append-to-origin-file origin "links here" "org")
     (let ((content (with-temp-buffer
                      (insert-file-contents origin)
                      (buffer-string))))
       (should (string-match-p "initial content" content))
       (should (string-match-p "links here" content))
       ;; old content precedes new content in the file
       (should (< (string-match "initial content" content)
                  (string-match "links here" content)))))))


(ert-deftest haystack-test/append-to-origin-file-does-not-clobber-existing ()
  "Does not remove existing content when appending."
  (haystack-test--with-notes-dir
   (let* ((origin (expand-file-name "origin.org" haystack-notes-directory)))
     (write-region "first line\nsecond line\n" nil origin)
     (haystack--append-to-origin-file origin "appended" "org")
     (let ((content (with-temp-buffer
                      (insert-file-contents origin)
                      (buffer-string))))
       (should (string-match-p "first line" content))
       (should (string-match-p "second line" content))
       (should (string-match-p "appended" content))))))

(ert-deftest haystack-test/append-to-origin-file-errors-on-deleted-file ()
  "Signals user-error when the origin file does not exist."
  (haystack-test--with-notes-dir
   (let ((origin (expand-file-name "deleted.org" haystack-notes-directory)))
     (should-error (haystack--append-to-origin-file origin "content" "org")
                   :type 'user-error))))

;;;; haystack-mentions-yank-to-origin

(ert-deftest haystack-test/mentions-yank-errors-outside-mentions-tree ()
  "Signal user-error when called from a non-mentions results buffer."
  (haystack-test--with-notes-dir
   (let ((buf (haystack-test--make-results-buf " *hs-not-mentions*" nil
                                               (haystack-sd-create :root-term "rust"))))
     (unwind-protect
         (with-current-buffer buf
           (setq-local haystack--buffer-notes-dir
                       (expand-file-name haystack-notes-directory))
           (should-error (haystack-mentions-yank-to-origin) :type 'user-error))
       (kill-buffer buf)))))

(ert-deftest haystack-test/mentions-yank-appends-separator-and-content ()
  "Appends separator and MOC links to the origin file."
  (haystack-test--with-notes-dir
   (let* ((origin (expand-file-name "origin.org" haystack-notes-directory))
          (note   (expand-file-name "20240101000000-ref.org" haystack-notes-directory)))
     (write-region "initial content\n" nil origin)
     (write-region "ref content here\n" nil note)
     (let ((buf (haystack-test--make-results-buf " *hs-mentions-yank*" nil
                                                 (haystack-sd-create :root-term "ref"
                                                   :root-expanded "ref"
                                                   :root-literal t
                                                   :root-regex nil
                                                   :root-filename nil
                                                   :root-expansion nil
                                                   :filters nil
                                                   :composite-filter 'exclude))))
       (unwind-protect
           (with-current-buffer buf
             (setq-local haystack--buffer-notes-dir
                         (expand-file-name haystack-notes-directory))
             (setq-local haystack--mentions-origin origin)
             (setq-local default-directory
                         (file-name-as-directory
                          (expand-file-name haystack-notes-directory)))
             (insert (format "%s:1:ref content here\n" note))
             (haystack-mentions-yank-to-origin)
             ;; Buffer should be killed by yank
             (let ((file-content (with-temp-buffer
                                   (insert-file-contents origin)
                                   (buffer-string))))
               (should (string-match-p "-----" file-content))
               (should (string-match-p "initial content" file-content))
               (should (string-match-p "ref" file-content))))
         (when (buffer-live-p buf) (kill-buffer buf)))))))

(ert-deftest haystack-test/mentions-yank-empty-inserts-boilerplate ()
  "When no results exist, appends separator and a no-ref comment to origin file."
  (haystack-test--with-notes-dir
   (let* ((origin (expand-file-name "origin.org" haystack-notes-directory)))
     (write-region "initial content\n" nil origin)
     (let ((buf (haystack-test--make-results-buf " *hs-mentions-empty*" nil
                                                 (haystack-sd-create :root-term "xyzzy"
                                                   :root-expanded "xyzzy"
                                                   :root-literal t
                                                   :root-regex nil
                                                   :root-filename nil
                                                   :root-expansion nil
                                                   :filters nil
                                                   :composite-filter 'exclude))))
       (unwind-protect
           (with-current-buffer buf
             (setq-local haystack--buffer-notes-dir
                         (expand-file-name haystack-notes-directory))
             (setq-local haystack--mentions-origin origin)
             (setq-local default-directory
                         (file-name-as-directory
                          (expand-file-name haystack-notes-directory)))
             ;; No result lines inserted — empty buffer
             (haystack-mentions-yank-to-origin)
             (let ((file-content (with-temp-buffer
                                   (insert-file-contents origin)
                                   (buffer-string))))
               (should (string-match-p "-----" file-content))
               (should (string-match-p "No references" file-content))))
         (when (buffer-live-p buf) (kill-buffer buf)))))))

(ert-deftest haystack-test/mentions-yank-kills-whole-tree ()
  "haystack-mentions-yank-to-origin kills the entire mentions tree."
  (haystack-test--with-notes-dir
   (let* ((origin (expand-file-name "origin.org" haystack-notes-directory)))
     (write-region "content\n" nil origin)
     (let* ((root  (haystack-test--make-results-buf " *hs-mref-root*" nil
                                                    (haystack-sd-create :root-term "x"
                                                      :root-expanded "x"
                                                      :root-literal t
                                                      :root-regex nil
                                                      :root-filename nil
                                                      :root-expansion nil
                                                      :filters nil
                                                      :composite-filter 'exclude)))
            (child (haystack-test--make-results-buf " *hs-mref-child*" root
                                                    (haystack-sd-create :root-term "x"
                                                      :root-expanded "x"
                                                      :root-literal t
                                                      :root-regex nil
                                                      :root-filename nil
                                                      :root-expansion nil
                                                      :filters '((:term "y" :negated nil
                                                                 :filename nil :literal t
                                                                 :regex nil :expansion nil))
                                                      :composite-filter 'exclude))))
       (with-current-buffer root
         (setq-local haystack--buffer-notes-dir
                     (expand-file-name haystack-notes-directory))
         (setq-local haystack--mentions-origin origin))
       (with-current-buffer child
         (setq-local haystack--buffer-notes-dir
                     (expand-file-name haystack-notes-directory))
         (setq-local haystack--mentions-origin origin))
       (with-current-buffer child
         (haystack-mentions-yank-to-origin))
       (should-not (buffer-live-p root))
       (should-not (buffer-live-p child))))))

;;;; haystack--mentions-exclude-origin

(ert-deftest haystack-test/mentions-exclude-origin-removes-matching-lines ()
  "Origin file's lines are removed from the results buffer."
  (with-temp-buffer
    (let ((marker (point-marker)))
      (insert "Header line\n")
      (set-marker marker (point))
      (insert "origin.org:1:some match\n"
              "other.org:2:another match\n"
              "origin.org:5:second match\n")
      (setq-local haystack--header-end-marker marker)
      (setq-local haystack--search-descriptor (haystack-sd-create :root-term "x"))
      (haystack--mentions-exclude-origin "/path/to/origin.org")
      (let ((content (buffer-substring-no-properties (point-min) (point-max))))
        (should (string-match-p "other.org:2:another match" content))
        (should-not (string-match-p "origin.org" content))))))

(ert-deftest haystack-test/mentions-exclude-origin-preserves-header ()
  "Header content is untouched even if it mentions the origin filename."
  (with-temp-buffer
    (let ((marker (point-marker)))
      (insert "Header: origin.org stuff\n")
      (set-marker marker (point))
      (insert "origin.org:1:content\n"
              "other.org:2:content\n")
      (setq-local haystack--header-end-marker marker)
      (setq-local haystack--search-descriptor (haystack-sd-create :root-term "x"))
      (haystack--mentions-exclude-origin "/path/to/origin.org")
      (let ((content (buffer-substring-no-properties (point-min) (point-max))))
        (should (string-match-p "Header: origin.org stuff" content))
        (should-not (string-match-p "origin.org:1:" content))))))

(ert-deftest haystack-test/mentions-exclude-origin-noop-when-absent ()
  "No changes when the origin file does not appear in results."
  (with-temp-buffer
    (let ((marker (point-marker)))
      (insert "Header\n")
      (set-marker marker (point))
      (insert "foo.org:1:text\nbar.org:2:text\n")
      (setq-local haystack--header-end-marker marker)
      (setq-local haystack--search-descriptor (haystack-sd-create :root-term "x"))
      (let ((before (buffer-string)))
        (haystack--mentions-exclude-origin "/path/to/origin.org")
        (should (equal before (buffer-string)))))))

;;;; haystack-insert-mentions

(ert-deftest haystack-test/insert-mentions-errors-without-file ()
  "Signal user-error when called from a non-file buffer."
  (with-temp-buffer
    (should-error (haystack-insert-mentions) :type 'user-error)))

(ert-deftest haystack-test/insert-mentions-y-appends-to-origin ()
  "Choosing y appends MOC links to the origin file."
  (haystack-test--with-notes-dir
   (let* ((origin (expand-file-name "20240101000000-origin.org"
                                    haystack-notes-directory))
          (ref    (expand-file-name "20240101000001-ref.org"
                                    haystack-notes-directory))
          (result-buf nil))
     (write-region "origin content\n" nil origin)
     (write-region "mentions origin slug\n" nil ref)
     ;; Create a fake results buffer that haystack-run-root-search would return
     (setq result-buf (get-buffer-create " *hs-insert-mentions-test*"))
     (with-current-buffer result-buf
       (let ((marker (point-marker)))
         (insert ";;;; header\n")
         (set-marker marker (point))
         (insert (format "%s:1:mentions origin slug\n"
                         (file-name-nondirectory ref)))
         (setq-local haystack--header-end-marker marker)
         (setq-local haystack--search-descriptor
                     (haystack-sd-create :root-term "origin"
                       :root-expanded "origin" :root-literal t
                       :root-regex nil :root-filename nil
                       :root-expansion nil :filters nil
                       :composite-filter 'exclude))
         (setq-local default-directory
                     (file-name-as-directory
                      (expand-file-name haystack-notes-directory)))))
     (unwind-protect
         (let ((buf (find-file-noselect origin)))
           (unwind-protect
               (with-current-buffer buf
                 (cl-letf (((symbol-function 'haystack-run-root-search)
                            (lambda (_input &optional _cf) result-buf))
                           ((symbol-function 'read-char-choice)
                            (lambda (_prompt _chars) ?y))
                           ((symbol-function 'pop-to-buffer) #'ignore)
                           ((symbol-function 'switch-to-buffer) #'ignore))
                   (haystack-insert-mentions)
                   (let ((content (with-temp-buffer
                                    (insert-file-contents origin)
                                    (buffer-string))))
                     (should (string-match-p "ref" content)))))
             (kill-buffer buf)))
       (when (buffer-live-p result-buf) (kill-buffer result-buf))))))

(ert-deftest haystack-test/insert-mentions-q-aborts ()
  "Choosing q kills the search buffer without modifying origin."
  (haystack-test--with-notes-dir
   (let* ((origin (expand-file-name "20240101000000-origin.org"
                                    haystack-notes-directory))
          (result-buf nil))
     (write-region "origin content\n" nil origin)
     (setq result-buf (get-buffer-create " *hs-insert-mentions-abort*"))
     (with-current-buffer result-buf
       (let ((marker (point-marker)))
         (insert ";;;; header\n")
         (set-marker marker (point))
         (insert "other.org:1:stuff\n")
         (setq-local haystack--header-end-marker marker)
         (setq-local haystack--search-descriptor
                     (haystack-sd-create :root-term "origin"
                       :root-expanded "origin" :root-literal t
                       :root-regex nil :root-filename nil
                       :root-expansion nil :filters nil
                       :composite-filter 'exclude))
         (setq-local default-directory
                     (file-name-as-directory
                      (expand-file-name haystack-notes-directory)))))
     (unwind-protect
         (let ((buf (find-file-noselect origin)))
           (unwind-protect
               (with-current-buffer buf
                 (cl-letf (((symbol-function 'haystack-run-root-search)
                            (lambda (_input &optional _cf) result-buf))
                           ((symbol-function 'read-char-choice)
                            (lambda (_prompt _chars) ?q))
                           ((symbol-function 'pop-to-buffer) #'ignore)
                           ((symbol-function 'switch-to-buffer) #'ignore))
                   (haystack-insert-mentions)
                   ;; Origin file should be unchanged
                   (let ((content (with-temp-buffer
                                    (insert-file-contents origin)
                                    (buffer-string))))
                     (should (equal content "origin content\n")))))
             (kill-buffer buf)))
       (when (buffer-live-p result-buf) (kill-buffer result-buf))))))

(ert-deftest haystack-test/insert-mentions-spc-opens-buffer ()
  "Choosing SPC opens the mentions results buffer instead of inserting."
  (haystack-test--with-notes-dir
   (let* ((origin (expand-file-name "20240101000000-origin.org"
                                    haystack-notes-directory))
          (result-buf nil))
     (write-region "origin content\n" nil origin)
     (setq result-buf (get-buffer-create "*haystack:1:=origin*"))
     (with-current-buffer result-buf
       (let ((marker (point-marker)))
         (insert ";;;; header\n")
         (set-marker marker (point))
         (insert "other.org:1:stuff\n")
         (setq-local haystack--header-end-marker marker)
         (setq-local haystack--search-descriptor
                     (haystack-sd-create :root-term "origin"
                       :root-expanded "origin" :root-literal t
                       :root-regex nil :root-filename nil
                       :root-expansion nil :filters nil
                       :composite-filter 'exclude))
         (setq-local default-directory
                     (file-name-as-directory
                      (expand-file-name haystack-notes-directory)))))
     (unwind-protect
         (let ((buf (find-file-noselect origin)))
           (unwind-protect
               (with-current-buffer buf
                 (cl-letf (((symbol-function 'haystack-run-root-search)
                            (lambda (_input &optional _cf) result-buf))
                           ((symbol-function 'read-char-choice)
                            (lambda (_prompt _chars) ?\s))
                           ((symbol-function 'pop-to-buffer) #'ignore)
                           ((symbol-function 'switch-to-buffer) #'ignore))
                   (haystack-insert-mentions)
                   ;; Buffer should still be alive and renamed
                   (should (buffer-live-p result-buf))
                   (should (buffer-local-value 'haystack--mentions-origin result-buf))
                   ;; Origin file should be unchanged
                   (let ((content (with-temp-buffer
                                    (insert-file-contents origin)
                                    (buffer-string))))
                     (should (equal content "origin content\n")))))
             (kill-buffer buf)))
       (when (buffer-live-p result-buf) (kill-buffer result-buf))))))

;;;; haystack--comment-prefix

(ert-deftest haystack-test/comment-prefix-c-block-style ()
  "C, H, and CSS use /* to match their frontmatter style."
  (should (string= (haystack--comment-prefix "c")   "/*"))
  (should (string= (haystack--comment-prefix "h")   "/*"))
  (should (string= (haystack--comment-prefix "css") "/*")))

(ert-deftest haystack-test/comment-prefix-slash-unchanged ()
  "JS, TS, Go, Rust etc. still use //."
  (should (string= (haystack--comment-prefix "js") "//"))
  (should (string= (haystack--comment-prefix "go") "//"))
  (should (string= (haystack--comment-prefix "rs") "//")))

;;;; haystack--composite-rename-pairs

(ert-deftest haystack-test/composite-rename-pairs-basic ()
  "Returns the correct rename pair when old slug appears in a composite."
  (haystack-test--with-notes-dir
   (let* ((dir (file-name-as-directory (expand-file-name haystack-notes-directory)))
          (old-file (concat dir "@comp__foo__bar.org")))
     (write-region "" nil old-file)
     (let ((result (haystack--composite-rename-pairs "foo" "baz")))
       (should (= (length result) 1))
       (should (string= (caar result) old-file))
       (should (string-suffix-p "@comp__baz__bar.org" (cdar result)))))))

(ert-deftest haystack-test/composite-rename-pairs-no-match ()
  "Returns nil when no composite contains the old slug."
  (haystack-test--with-notes-dir
   (let* ((dir (file-name-as-directory (expand-file-name haystack-notes-directory))))
     (write-region "" nil (concat dir "@comp__foo__bar.org"))
     (should (null (haystack--composite-rename-pairs "qux" "baz"))))))

(ert-deftest haystack-test/composite-rename-pairs-extensionless ()
  "Does not crash on an extensionless @comp__ file; produces a clean new path."
  (haystack-test--with-notes-dir
   (let* ((dir (file-name-as-directory (expand-file-name haystack-notes-directory)))
          (old-file (concat dir "@comp__foo__bar")))
     (write-region "" nil old-file)
     (let ((result (haystack--composite-rename-pairs "foo" "baz")))
       (should (= (length result) 1))
       (should (string= (caar result) old-file))
       (should (string-suffix-p "@comp__baz__bar" (cdar result)))
       (should-not (string-match-p "\\.nil\\'" (cdar result)))))))

;;;; haystack--volume-gate

(ert-deftest haystack-test/volume-gate-nil-threshold-never-fires ()
  "When `haystack-volume-gate-threshold' is nil the gate never prompts."
  (let ((haystack-volume-gate-threshold nil)
        (prompted nil))
    (cl-letf (((symbol-function 'yes-or-no-p)
               (lambda (_) (setq prompted t) t)))
      (haystack--volume-gate "file.org:9999")
      (should-not prompted))))

(ert-deftest haystack-test/volume-gate-fires-at-threshold ()
  "Gate prompts when total line count meets the threshold."
  (let ((haystack-volume-gate-threshold 100)
        (prompted nil))
    (cl-letf (((symbol-function 'yes-or-no-p)
               (lambda (_) (setq prompted t) t)))
      ;; a.org:60 + b.org:40 = 100 lines — exactly at threshold
      (haystack--volume-gate "a.org:60\nb.org:40\n")
      (should prompted))))

(ert-deftest haystack-test/volume-gate-does-not-fire-below-threshold ()
  "Gate does not prompt when line count is below the threshold."
  (let ((haystack-volume-gate-threshold 2000)
        (prompted nil))
    (cl-letf (((symbol-function 'yes-or-no-p)
               (lambda (_) (setq prompted t) t)))
      (haystack--volume-gate "a.org:5\nb.org:3\n")
      (should-not prompted))))

(ert-deftest haystack-test/volume-gate-cancels-on-no ()
  "Gate signals `user-error' when user answers no."
  (let ((haystack-volume-gate-threshold 10))
    (cl-letf (((symbol-function 'yes-or-no-p) (lambda (_) nil)))
      (should-error
       (haystack--volume-gate "a.org:100\n")
       :type 'user-error))))

;;;; haystack-max-columns

(ert-deftest haystack-test/max-columns-default-is-500 ()
  "Default value of `haystack-max-columns' is 500."
  (should (= (default-value 'haystack-max-columns) 500)))

(ert-deftest haystack-test/max-columns-used-in-rg-args ()
  "Content-mode rg args include --max-columns set to the defcustom value."
  (let ((haystack-max-columns 300))
    (should (member "--max-columns=300" (haystack--rg-args :pattern "foo")))))

(ert-deftest haystack-test/max-columns-not-in-count-mode ()
  "Count-mode rg args do not include --max-columns."
  (should-not (cl-some (lambda (a) (string-prefix-p "--max-columns" a))
                       (haystack--rg-args :count t :pattern "foo"))))

;;;; haystack-volume-gate-style

(ert-deftest haystack-test/volume-gate-style-default-is-exact ()
  "Default value of `haystack-volume-gate-style' is \\='exact."
  (should (eq (default-value 'haystack-volume-gate-style) 'exact)))

(ert-deftest haystack-test/volume-gate-exact-prompt-shows-counts ()
  "In exact mode the prompt includes line and file counts."
  (let ((haystack-volume-gate-threshold 100)
        (haystack-volume-gate-style 'exact)
        (prompt-text nil))
    (cl-letf (((symbol-function 'yes-or-no-p)
               (lambda (msg) (setq prompt-text msg) t)))
      ;; 60 + 40 = 100 lines across 2 files
      (haystack--volume-gate "a.org:60\nb.org:40\n")
      (should (string-match-p "100" prompt-text))
      (should (string-match-p "2" prompt-text)))))

(ert-deftest haystack-test/volume-gate-fast-prompt-says-at-least ()
  "In fast mode the prompt says \"at least N\" when output is at the cap."
  (let ((haystack-volume-gate-threshold 100)
        (haystack-volume-gate-style 'fast)
        (prompt-text nil))
    (cl-letf (((symbol-function 'yes-or-no-p)
               (lambda (msg) (setq prompt-text msg) t)))
      ;; Exactly threshold lines in output — simulates head cap being hit
      (let ((capped-output
             (mapconcat (lambda (i) (format "f%d.org:1" i))
                        (number-sequence 1 100) "\n")))
        (haystack--volume-gate capped-output)
        (should (string-match-p "at least" prompt-text))))))

(ert-deftest haystack-test/volume-gate-fast-still-fires ()
  "In fast mode the gate still fires when threshold is met."
  (let ((haystack-volume-gate-threshold 100)
        (haystack-volume-gate-style 'fast)
        (prompted nil))
    (cl-letf (((symbol-function 'yes-or-no-p)
               (lambda (_) (setq prompted t) t)))
      (let ((capped-output
             (mapconcat (lambda (i) (format "f%d.org:1" i))
                        (number-sequence 1 100) "\n")))
        (haystack--volume-gate capped-output)
        (should prompted)))))

;;;; haystack-tree-help

(ert-deftest haystack-test/tree-mode-map-has-help-binding ()
  "`haystack-tree-mode-map' binds ? to `haystack-tree-help'."
  (should (eq (lookup-key haystack-tree-mode-map "?") #'haystack-tree-help)))

(ert-deftest haystack-test/tree-help-opens-help-buffer ()
  "`haystack-tree-help' opens a *haystack-help* buffer."
  (cl-letf (((symbol-function 'display-buffer) #'ignore)
            ((symbol-function 'select-window)  #'ignore))
    (haystack-tree-help)
    (let ((buf (get-buffer "*haystack-help*")))
      (unwind-protect
          (progn
            (should buf)
            (should (string-match-p "tree" (with-current-buffer buf (buffer-string)))))
        (when buf (kill-buffer buf))))))

(ert-deftest haystack-test/tree-help-content-lists-tree-keys ()
  "`haystack-tree-help' content references tree-buffer commands, not results-buffer commands."
  (let ((content (haystack--tree-help-content)))
    ;; Tree commands present
    (should (string-match-p "visit" content))
    (should (string-match-p "next" content))
    (should (string-match-p "prev" content))
    ;; Results-buffer-only commands absent
    (should-not (string-match-p "filter further" content))
    (should-not (string-match-p "compose" content))))

;;;; View mode tests

(ert-deftest haystack-test/view-mode-default-is-full ()
  "New results buffer has `haystack--view-mode' set to `full'."
  (let ((haystack-notes-directory temporary-file-directory))
    (let ((buf (haystack--setup-results-buffer
                "*haystack:1:test-view*"
                ";;;; test header\n"
                "file.org:1:content\n"
                (haystack-sd-create :root-term "test" :filters nil))))
      (unwind-protect
          (with-current-buffer buf
            (should (eq haystack--view-mode 'full)))
        (kill-buffer buf)))))

(ert-deftest haystack-test/view-mode-cycles-correctly ()
  "Three calls to `haystack-cycle-view' cycle full → compact → files → full."
  (let ((haystack-notes-directory temporary-file-directory))
    (let ((buf (haystack--setup-results-buffer
                "*haystack:1:test-cycle*"
                ";;;; test header\n"
                "file.org:1:content\n"
                (haystack-sd-create :root-term "test" :filters nil))))
      (unwind-protect
          (with-current-buffer buf
            (should (eq haystack--view-mode 'full))
            (haystack-cycle-view)
            (should (eq haystack--view-mode 'compact))
            (haystack-cycle-view)
            (should (eq haystack--view-mode 'files))
            (haystack-cycle-view)
            (should (eq haystack--view-mode 'full)))
        (kill-buffer buf)))))

(ert-deftest haystack-test/view-clear-removes-all-overlays ()
  "After clearing, `haystack--view-overlays' is nil and no tagged overlays remain."
  (let ((haystack-notes-directory temporary-file-directory))
    (let ((buf (haystack--setup-results-buffer
                "*haystack:1:test-clear*"
                ";;;; test header\n"
                "file.org:1:content\n"
                (haystack-sd-create :root-term "test" :filters nil))))
      (unwind-protect
          (with-current-buffer buf
            ;; Manually add some overlays to simulate view mode state.
            (let ((ov (make-overlay (point-min) (+ (point-min) 4))))
              (overlay-put ov 'haystack-view t)
              (push ov haystack--view-overlays))
            (should haystack--view-overlays)
            (haystack--view-clear)
            (should-not haystack--view-overlays))
        (kill-buffer buf)))))

(ert-deftest haystack-test/view-direct-jump-sets-mode ()
  "Each direct-jump command sets the expected mode value."
  (let ((haystack-notes-directory temporary-file-directory))
    (let ((buf (haystack--setup-results-buffer
                "*haystack:1:test-direct*"
                ";;;; test header\n"
                "file.org:1:content\n"
                (haystack-sd-create :root-term "test" :filters nil))))
      (unwind-protect
          (with-current-buffer buf
            (haystack-view-compact)
            (should (eq haystack--view-mode 'compact))
            (haystack-view-files)
            (should (eq haystack--view-mode 'files))
            (haystack-view-full)
            (should (eq haystack--view-mode 'full)))
        (kill-buffer buf)))))

(ert-deftest haystack-test/header-end-marker-is-set ()
  "`haystack--header-end-marker' is set to a marker at the end of the header."
  (let ((haystack-notes-directory temporary-file-directory))
    (let ((buf (haystack--setup-results-buffer
                "*haystack:1:test-marker*"
                ";;;; test header\n"
                "file.org:1:content\n"
                (haystack-sd-create :root-term "test" :filters nil))))
      (unwind-protect
          (with-current-buffer buf
            (should (markerp haystack--header-end-marker))
            (should (= (marker-position haystack--header-end-marker)
                       (1+ (length ";;;; test header\n")))))
        (kill-buffer buf)))))

;;;; View mode — compact tests

(ert-deftest haystack-test/compact-overlay-replaces-filename ()
  "In compact mode, overlay at filename position displays pretty-title."
  (let ((haystack-notes-directory temporary-file-directory))
    (let ((buf (haystack--setup-results-buffer
                "*haystack:1:test-compact*"
                ";;;; header\n"
                "20240101120000-my-note.org:1:some content\n"
                (haystack-sd-create :root-term "test" :filters nil))))
      (unwind-protect
          (with-current-buffer buf
            (haystack-view-compact)
            (goto-char haystack--header-end-marker)
            (let ((ovs (overlays-at (point))))
              (should ovs)
              (should (equal (overlay-get (car ovs) 'display) "my note"))))
        (kill-buffer buf)))))

(ert-deftest haystack-test/compact-preserves-buffer-string ()
  "After compact overlays, `buffer-string' still contains raw grep-format text."
  (let ((haystack-notes-directory temporary-file-directory)
        (raw-output "20240101120000-my-note.org:1:some content\n"))
    (let ((buf (haystack--setup-results-buffer
                "*haystack:1:test-compact-raw*"
                ";;;; header\n"
                raw-output
                (haystack-sd-create :root-term "test" :filters nil))))
      (unwind-protect
          (with-current-buffer buf
            (haystack-view-compact)
            (should (string-match-p "20240101120000-my-note\\.org:1:some content"
                                    (buffer-string))))
        (kill-buffer buf)))))

(ert-deftest haystack-test/compact-skips-header ()
  "Compact overlays are only created after `haystack--header-end-marker'."
  (let ((haystack-notes-directory temporary-file-directory))
    (let ((buf (haystack--setup-results-buffer
                "*haystack:1:test-compact-hdr*"
                ";;;; header\n"
                "file.org:1:content\n"
                (haystack-sd-create :root-term "test" :filters nil))))
      (unwind-protect
          (with-current-buffer buf
            (haystack-view-compact)
            (let ((header-ovs (overlays-in (point-min)
                                           (marker-position haystack--header-end-marker))))
              ;; No view overlays should exist in the header region.
              (should-not (cl-some (lambda (ov) (overlay-get ov 'haystack-view))
                                   header-ovs))))
        (kill-buffer buf)))))

(ert-deftest haystack-test/compact-caches-pretty-titles ()
  "Pretty-title is computed once per unique filename, not once per line."
  (let ((haystack-notes-directory temporary-file-directory)
        (call-count 0))
    (let ((buf (haystack--setup-results-buffer
                "*haystack:1:test-compact-cache*"
                ";;;; header\n"
                (concat "fileA.org:1:line one\n"
                        "fileA.org:2:line two\n"
                        "fileA.org:3:line three\n"
                        "fileB.org:1:line one\n"
                        "fileB.org:2:line two\n")
                (haystack-sd-create :root-term "test" :filters nil))))
      (unwind-protect
          (with-current-buffer buf
            (cl-letf (((symbol-function 'haystack--pretty-title)
                       (lambda (f)
                         (setq call-count (1+ call-count))
                         (replace-regexp-in-string "-" " " (file-name-sans-extension f)))))
              (haystack-view-compact))
            ;; 2 unique files = 2 calls, not 5.
            (should (= call-count 2)))
        (kill-buffer buf)))))

;;;; View mode — files tests

(ert-deftest haystack-test/files-hides-duplicates ()
  "Files mode shows one visible line per unique file."
  (let ((haystack-notes-directory temporary-file-directory))
    (let ((buf (haystack--setup-results-buffer
                "*haystack:1:test-files*"
                ";;;; header\n"
                (concat "fileA.org:1:line one\n"
                        "fileA.org:2:line two\n"
                        "fileA.org:3:line three\n"
                        "fileB.org:1:line one\n"
                        "fileB.org:4:line four\n")
                (haystack-sd-create :root-term "test" :filters nil))))
      (unwind-protect
          (with-current-buffer buf
            (haystack-view-files)
            ;; Count visible lines in the results region.
            (let ((visible 0))
              (goto-char (marker-position haystack--header-end-marker))
              (while (not (eobp))
                (unless (invisible-p (point))
                  (setq visible (1+ visible)))
                (forward-line 1))
              (should (= visible 2))))
        (kill-buffer buf)))))

(ert-deftest haystack-test/files-preserves-buffer-string ()
  "After files overlays, `buffer-string' still contains all raw lines."
  (let ((haystack-notes-directory temporary-file-directory)
        (raw-output (concat "fileA.org:1:line one\n"
                            "fileA.org:2:line two\n"
                            "fileB.org:1:line one\n")))
    (let ((buf (haystack--setup-results-buffer
                "*haystack:1:test-files-raw*"
                ";;;; header\n"
                raw-output
                (haystack-sd-create :root-term "test" :filters nil))))
      (unwind-protect
          (with-current-buffer buf
            (haystack-view-files)
            (should (string-match-p "fileA\\.org:2:line two" (buffer-string))))
        (kill-buffer buf)))))

(ert-deftest haystack-test/files-first-occurrence-shows-pretty-title ()
  "In files mode, the kept line's filename is overlaid with pretty-title."
  (let ((haystack-notes-directory temporary-file-directory))
    (let ((buf (haystack--setup-results-buffer
                "*haystack:1:test-files-title*"
                ";;;; header\n"
                "20240101120000-my-note.org:1:content\n"
                (haystack-sd-create :root-term "test" :filters nil))))
      (unwind-protect
          (with-current-buffer buf
            (haystack-view-files)
            (goto-char (marker-position haystack--header-end-marker))
            (let ((ovs (overlays-at (point))))
              (should (cl-some (lambda (ov)
                                 (equal (overlay-get ov 'display) "my note"))
                               ovs))))
        (kill-buffer buf)))))

(ert-deftest haystack-test/files-first-occurrence-hides-content ()
  "In files mode, the kept line's :line:content portion is hidden."
  (let ((haystack-notes-directory temporary-file-directory))
    (let ((buf (haystack--setup-results-buffer
                "*haystack:1:test-files-content*"
                ";;;; header\n"
                "file.org:1:some content here\n"
                (haystack-sd-create :root-term "test" :filters nil))))
      (unwind-protect
          (with-current-buffer buf
            (haystack-view-files)
            (goto-char (marker-position haystack--header-end-marker))
            ;; Move past the filename overlay to the :line:content region.
            (when (looking-at "\\([^:\n]+\\)")
              (goto-char (match-end 0)))
            (let ((ovs (overlays-at (point))))
              (should (cl-some (lambda (ov)
                                 (equal (overlay-get ov 'display) ""))
                               ovs))))
        (kill-buffer buf)))))

;;;; View mode — header indicator tests

(ert-deftest haystack-test/header-shows-view-mode ()
  "After cycling view mode, the header reflects the new mode."
  (let ((haystack-notes-directory temporary-file-directory))
    (let ((buf (haystack--setup-results-buffer
                "*haystack:1:test-hdr-view*"
                (haystack--format-header "root=test" 1 1)
                "file.org:1:content\n"
                (haystack-sd-create :root-term "test" :filters nil))))
      (unwind-protect
          (with-current-buffer buf
            ;; Default: underlying text says "Full", no overlay yet.
            (goto-char (point-min))
            (should (search-forward "view: Full" (marker-position haystack--header-end-marker) t))
            ;; Cycle to compact — overlay should show "Compact".
            (haystack-cycle-view)
            (should haystack--view-header-overlay)
            (should (string-match-p "Compact"
                                    (overlay-get haystack--view-header-overlay 'display)))
            ;; Cycle to files.
            (haystack-cycle-view)
            (should (string-match-p "Files"
                                    (overlay-get haystack--view-header-overlay 'display)))
            ;; Cycle back to full — overlay cleared.
            (haystack-cycle-view)
            (should-not haystack--view-header-overlay))
        (kill-buffer buf)))))

;;;; View mode — navigation tests

(ert-deftest haystack-test/next-match-skips-invisible-lines ()
  "In files mode, `haystack-next-match' skips invisible (duplicate) lines."
  (let ((haystack-notes-directory temporary-file-directory))
    (let ((buf (haystack--setup-results-buffer
                "*haystack:1:test-nav*"
                (haystack--format-header "root=test" 2 4)
                (concat "fileA.org:1:line one\n"
                        "fileA.org:2:line two\n"
                        "fileA.org:3:line three\n"
                        "fileB.org:1:line one\n")
                (haystack-sd-create :root-term "test" :filters nil))))
      (unwind-protect
          (with-current-buffer buf
            (haystack-view-files)
            ;; Start at the first result.
            (goto-char (marker-position haystack--header-end-marker))
            ;; fileA is visible at point.  Next should jump to fileB,
            ;; skipping the two invisible fileA duplicates.
            (cl-letf (((symbol-function 'compile-goto-error) #'ignore)
                      ((symbol-function 'save-selected-window)
                       (lambda (&rest _) nil)))
              (haystack-next-match 1))
            ;; Point should be on the fileB line.
            (should (string-match-p "fileB"
                                    (buffer-substring (line-beginning-position)
                                                      (line-end-position)))))
        (kill-buffer buf)))))

;;; Pinned search paths

(ert-deftest haystack-test/frecency-rename-merge-preserves-pin ()
  "When rename merges two entries and one is pinned, result is pinned."
  (let* ((k1 (haystack-test--tkey "coding"))
         (k2 (haystack-test--tkey "programming"))
         (data (list (cons k1 '(:count 4 :last-access 2000.0 :pinned t))
                     (cons k2 '(:count 3 :last-access 1000.0))))
         (result (haystack--frecency-rename-in-data data "programming" "coding")))
    (should (= (length result) 1))
    (let ((entry (assoc k1 result)))
      (should (= (plist-get (cdr entry) :count) 7))
      (should (eq (plist-get (cdr entry) :pinned) t)))))

(ert-deftest haystack-test/frecency-rename-merge-preserves-pin-reverse ()
  "When the second (existing) entry is pinned, merged result is still pinned."
  (let* ((k1 (haystack-test--tkey "coding"))
         (k2 (haystack-test--tkey "programming"))
         (data (list (cons k1 '(:count 4 :last-access 2000.0))
                     (cons k2 '(:count 3 :last-access 1000.0 :pinned t))))
         (result (haystack--frecency-rename-in-data data "programming" "coding")))
    (should (= (length result) 1))
    (let ((entry (assoc k1 result)))
      (should (eq (plist-get (cdr entry) :pinned) t)))))

(ert-deftest haystack-test/frecent-toggle-pin-sets-flag ()
  "Toggling pin on an unpinned entry sets :pinned t and marks dirty."
  (let* ((k1 (haystack-test--tkey "rust"))
         (haystack--frecency-data
          (list (cons k1 '(:count 5 :last-access 1000.0))))
         (haystack--frecency-dirty nil))
    (with-temp-buffer
      (haystack-frecent-mode)
      (let ((inhibit-read-only t))
        (insert "  test line\n")
        (put-text-property (line-beginning-position 0) (point)
                           'haystack-frecent-chain k1))
      (forward-line -1)
      (cl-letf (((symbol-function 'haystack--frecent-render) #'ignore))
        (haystack-frecent-toggle-pin))
      (let ((entry (assoc k1 haystack--frecency-data)))
        (should (eq (plist-get (cdr entry) :pinned) t))
        (should haystack--frecency-dirty)))))

(ert-deftest haystack-test/frecent-toggle-pin-unsets-flag ()
  "Toggling pin on a pinned entry removes :pinned and marks dirty."
  (let* ((k1 (haystack-test--tkey "rust"))
         (haystack--frecency-data
          (list (cons k1 '(:count 5 :last-access 1000.0 :pinned t))))
         (haystack--frecency-dirty nil))
    (with-temp-buffer
      (haystack-frecent-mode)
      (let ((inhibit-read-only t))
        (insert "  test line\n")
        (put-text-property (line-beginning-position 0) (point)
                           'haystack-frecent-chain k1))
      (forward-line -1)
      (cl-letf (((symbol-function 'haystack--frecent-render) #'ignore))
        (haystack-frecent-toggle-pin))
      (let ((entry (assoc k1 haystack--frecency-data)))
        (should-not (plist-get (cdr entry) :pinned))
        (should haystack--frecency-dirty)))))

(ert-deftest haystack-test/frecent-leaves-includes-pinned ()
  "A pinned entry that is NOT a leaf still appears in the leaf pool."
  (let* ((k-root   (haystack-test--tkey "rust"))
         (k-deep   (haystack-test--tkey "rust" "async"))
         ;; k-root is dominated by k-deep (higher score), so it's not a leaf.
         ;; But it's pinned, so it must still appear.
         (now      (float-time))
         (data     (list (cons k-root (list :count 1 :last-access now :pinned t))
                         (cons k-deep (list :count 100 :last-access now)))))
    ;; Without pinning, k-root would be pruned because k-deep dominates it.
    (let ((leaves (haystack--frecent-leaves data)))
      (should (assoc k-root leaves))
      (should (assoc k-deep leaves)))))

(ert-deftest haystack-test/frecent-sort-pinned-first ()
  "Pinned entries sort before non-pinned even with lower score."
  (let* ((k1 (haystack-test--tkey "rust"))
         (k2 (haystack-test--tkey "emacs"))
         (k3 (haystack-test--tkey "python"))
         (now (float-time))
         ;; k1: pinned, low score.  k2: not pinned, high score.  k3: pinned, mid score.
         (data (list (cons k1 (list :count 1 :last-access (- now 9999) :pinned t))
                     (cons k2 (list :count 500 :last-access now))
                     (cons k3 (list :count 10 :last-access now :pinned t))))
         (sorted (haystack--frecent-sort-entries data 'score)))
    ;; First two should be pinned (k3 higher score than k1 among pinned)
    (should (eq (plist-get (cdr (nth 0 sorted)) :pinned) t))
    (should (eq (plist-get (cdr (nth 1 sorted)) :pinned) t))
    ;; Third should be non-pinned k2
    (should-not (plist-get (cdr (nth 2 sorted)) :pinned))
    ;; Within pinned group, k3 (higher score) comes before k1
    (should (equal (car (nth 0 sorted)) k3))
    (should (equal (car (nth 1 sorted)) k1))))

(ert-deftest haystack-test/frecent-render-shows-pin-indicator ()
  "Pinned entries display a * indicator, non-pinned display a space."
  (let* ((k1 (haystack-test--tkey "rust"))
         (k2 (haystack-test--tkey "emacs"))
         (now (float-time))
         (haystack--frecency-data
          (list (cons k1 (list :count 10 :last-access now :pinned t))
                (cons k2 (list :count 5  :last-access now))))
         (haystack--frecent-sort-order 'score)
         (haystack--frecent-leaf-only nil))
    (with-temp-buffer
      (haystack-frecent-mode)
      (haystack--frecent-render)
      (goto-char (point-min))
      ;; Pinned entry line should contain "*"
      (should (search-forward "* " nil t))
      ;; Find the non-pinned entry — its line should not start with *
      ;; The pinned entry (rust) sorts first, then emacs
      (goto-char (point-min))
      (let ((found-pinned nil)
            (found-unpinned nil))
        (while (not (eobp))
          (when (get-text-property (point) 'haystack-frecent-chain)
            (let ((line (buffer-substring (line-beginning-position) (line-end-position))))
              (if (equal (get-text-property (point) 'haystack-frecent-chain) k1)
                  (progn (setq found-pinned t)
                         (should (string-match-p "^  \\*" line)))
                (setq found-unpinned t)
                (should (string-match-p "^   " line))
                (should-not (string-match-p "^  \\*" line)))))
          (forward-line 1))
        (should found-pinned)
        (should found-unpinned)))))

(ert-deftest haystack-test/pin-current-search-existing-entry ()
  "Pinning from results buffer when chain exists sets :pinned t."
  (let* ((desc (haystack-sd-create :root-term "rust" :filters nil))
         (key  (haystack--frecency-chain-key desc))
         (haystack--frecency-data
          (list (cons key (list :count 5 :last-access 1000.0))))
         (haystack--frecency-dirty nil))
    (with-temp-buffer
      (setq-local haystack--search-descriptor desc)
      (haystack-pin-current-search)
      (let ((entry (assoc key haystack--frecency-data)))
        (should (eq (plist-get (cdr entry) :pinned) t))
        (should (= (plist-get (cdr entry) :count) 5))
        (should haystack--frecency-dirty)))))

(ert-deftest haystack-test/pin-current-search-new-entry ()
  "Pinning from results buffer when chain does not exist creates it."
  (let* ((desc (haystack-sd-create :root-term "novel-search" :filters nil))
         (key  (haystack--frecency-chain-key desc))
         (haystack--frecency-data nil)
         (haystack--frecency-dirty nil))
    (with-temp-buffer
      (setq-local haystack--search-descriptor desc)
      (haystack-pin-current-search)
      (let ((entry (assoc key haystack--frecency-data)))
        (should entry)
        (should (eq (plist-get (cdr entry) :pinned) t))
        (should (= (plist-get (cdr entry) :count) 0))
        (should haystack--frecency-dirty)))))

(ert-deftest haystack-test/pin-current-search-unpin ()
  "Pinning an already-pinned search from results buffer unpins it."
  (let* ((desc (haystack-sd-create :root-term "rust" :filters nil))
         (key  (haystack--frecency-chain-key desc))
         (haystack--frecency-data
          (list (cons key (list :count 5 :last-access 1000.0 :pinned t))))
         (haystack--frecency-dirty nil))
    (with-temp-buffer
      (setq-local haystack--search-descriptor desc)
      (haystack-pin-current-search)
      (let ((entry (assoc key haystack--frecency-data)))
        (should-not (plist-get (cdr entry) :pinned))
        (should haystack--frecency-dirty)))))

(ert-deftest haystack-test/frecency-record-preserves-pin ()
  "Recording a search preserves the :pinned flag on an existing entry."
  (let* ((desc (haystack-sd-create :root-term "rust" :filters nil))
         (key  (haystack--frecency-chain-key desc))
         (haystack--frecency-data
          (list (cons key (list :count 5 :last-access 1000.0 :pinned t))))
         (haystack--frecency-dirty nil)
         (haystack--suppress-frecency-recording nil)
         (haystack-frecency-save-interval 300))
    (haystack--frecency-record desc)
    (let ((entry (assoc key haystack--frecency-data)))
      (should (= (plist-get (cdr entry) :count) 6))
      (should (eq (plist-get (cdr entry) :pinned) t)))))

;;;; haystack-save-mode

(ert-deftest haystack-test/save-hook-is-defcustom ()
  "haystack-save-hook should be a hook variable."
  (should (boundp 'haystack-save-hook))
  (should (custom-variable-p 'haystack-save-hook)))

(ert-deftest haystack-test/save-mode-exists ()
  "haystack-save-mode should be a minor mode."
  (should (fboundp 'haystack-save-mode)))

(ert-deftest haystack-test/save-mode-runs-hook-in-notes-dir ()
  "Saving a file inside the notes directory runs `haystack-save-hook'."
  (haystack-test--with-notes-dir
   (let* ((file (expand-file-name "20241215120000-test.org"
                                  haystack-notes-directory))
          (ran nil))
     (write-region "initial" nil file)
     (let ((buf (find-file-noselect file)))
       (unwind-protect
           (with-current-buffer buf
             (haystack-save-mode 1)
             (let ((haystack-save-hook (list (lambda () (setq ran t)))))
               (insert "change")
               (save-buffer))
             (should ran))
         (when (buffer-live-p buf) (kill-buffer buf))
         (when (file-exists-p file) (delete-file file)))))))

(ert-deftest haystack-test/save-mode-skips-outside-notes-dir ()
  "Saving a file outside the notes directory does not run `haystack-save-hook'."
  (haystack-test--with-notes-dir
   (let* ((file (make-temp-file "haystack-outside-" nil ".org"))
          (ran nil))
     (let ((buf (find-file-noselect file)))
       (unwind-protect
           (with-current-buffer buf
             (haystack-save-mode 1)
             (let ((haystack-save-hook (list (lambda () (setq ran t)))))
               (insert "change")
               (save-buffer))
             (should-not ran))
         (when (buffer-live-p buf) (kill-buffer buf))
         (when (file-exists-p file) (delete-file file)))))))

(ert-deftest haystack-test/save-mode-skips-when-no-notes-dir ()
  "When `haystack-notes-directory' is nil the hook does not run."
  (let* ((file (make-temp-file "haystack-nodir-" nil ".org"))
         (haystack-notes-directory nil)
         (ran nil))
    (let ((buf (find-file-noselect file)))
      (unwind-protect
          (with-current-buffer buf
            (haystack-save-mode 1)
            (let ((haystack-save-hook (list (lambda () (setq ran t)))))
              (insert "change")
              (save-buffer))
            (should-not ran))
        (when (buffer-live-p buf) (kill-buffer buf))
        (when (file-exists-p file) (delete-file file))))))

(ert-deftest haystack-test/save-mode-off-removes-hook ()
  "Disabling the mode prevents the hook from running on subsequent saves."
  (haystack-test--with-notes-dir
   (let* ((file (expand-file-name "20241215120000-test.org"
                                  haystack-notes-directory))
          (ran nil))
     (write-region "initial" nil file)
     (let ((buf (find-file-noselect file)))
       (unwind-protect
           (with-current-buffer buf
             (haystack-save-mode 1)
             (haystack-save-mode -1)
             (let ((haystack-save-hook (list (lambda () (setq ran t)))))
               (insert "change")
               (save-buffer))
             (should-not ran))
         (when (buffer-live-p buf) (kill-buffer buf))
         (when (file-exists-p file) (delete-file file)))))))

(provide 'haystack-test)
;;; haystack-test.el ends here
