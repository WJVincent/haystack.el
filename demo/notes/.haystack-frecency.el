;; Haystack frecency data — demo corpus
;; Keys use descriptor-shaped plists: (:root ROOT-PLIST :filters FILTER-LIST)
;; Scores (visit_count / days_since_access):
;;   Leaves shown by default:
;;     haystack > filtering           25/1 = 25.0
;;     lisp > macros                  15/1 = 15.0
;;     emacs > org-mode               12/1 = 12.0
;;     date:2025-01..2025-03          10/1 = 10.0
;;     search > ripgrep                8/1 =  8.0
;;     emacs > magit                   8/2 =  4.0
;;     pkm > zettelkasten             10/3 =  3.3
;;     frecency                        3/1 =  3.0
;;     expansion-groups                5/2 =  2.5
;;   Hidden (non-leaves, dominated by a deeper chain):
;;     emacs       5/5  = 1.0  dominated by (emacs > org-mode)
;;     lisp        3/7  = 0.43 dominated by (lisp > macros)
;;     pkm         4/8  = 0.5  dominated by (pkm > zettelkasten)
;;     haystack   20/1  = 20.0 dominated by (haystack > filtering)
;;     search      6/2  = 3.0  dominated by (search > ripgrep)
(((:root (:kind text :term "haystack") :filters ((:term "filtering")))
  :count 25 :last-access 1774310400.0)
 ((:root (:kind text :term "lisp") :filters ((:term "macros")))
  :count 15 :last-access 1774310400.0)
 ((:root (:kind text :term "emacs") :filters ((:term "org-mode")))
  :count 12 :last-access 1774310400.0)
 ((:root (:kind date-range :start "2025-01" :end "2025-03") :filters nil)
  :count 10 :last-access 1774310400.0)
 ((:root (:kind text :term "haystack") :filters nil)
  :count 20 :last-access 1774310400.0)
 ((:root (:kind text :term "search") :filters ((:term "ripgrep")))
  :count  8 :last-access 1774310400.0)
 ((:root (:kind text :term "frecency") :filters nil)
  :count  3 :last-access 1774310400.0)
 ((:root (:kind text :term "emacs") :filters ((:term "magit")))
  :count  8 :last-access 1774224000.0)
 ((:root (:kind text :term "search") :filters nil)
  :count  6 :last-access 1774224000.0)
 ((:root (:kind text :term "expansion-groups") :filters nil)
  :count  5 :last-access 1774224000.0)
 ((:root (:kind text :term "pkm") :filters ((:term "zettelkasten")))
  :count 10 :last-access 1774137600.0)
 ((:root (:kind text :term "emacs") :filters nil)
  :count  5 :last-access 1773964800.0)
 ((:root (:kind text :term "pkm") :filters nil)
  :count  4 :last-access 1773705600.0)
 ((:root (:kind text :term "lisp") :filters nil)
  :count  3 :last-access 1773792000.0))
