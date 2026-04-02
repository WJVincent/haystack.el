;; title: Emacs Init Snippet for Haystack
;; date: 2025-04-08
;; %%% haystack-end-frontmatter %%%

;; This snippet shows a complete use-package configuration for Haystack
;; integrated into a modern Emacs init with Vertico, Consult, and Orderless.
;;
;; The setup assumes straight.el for package management; replace :straight
;; with :ensure t if using package.el with a MELPA source configured.

(use-package vertico
  :straight t
  :init (vertico-mode 1))

(use-package orderless
  :straight t
  :custom
  (completion-styles '(orderless basic))
  (completion-category-overrides '((file (styles basic partial-completion)))))

(use-package consult
  :straight t
  :bind
  ("C-c r" . consult-ripgrep)
  ("C-x b" . consult-buffer))

;; Haystack configuration block.
;; haystack-notes-directory is the only required setting.
;; All other variables have defaults that work well for most users.
(use-package haystack
  :straight (:host github :repo "user/haystack")
  :init
  (global-set-key (kbd "C-c h") haystack-prefix-map)
  :custom
  (haystack-notes-directory "~/notes/")
  (haystack-default-extension "org"))

;; Optional: integrate haystack-new-note with org-capture.
(with-eval-after-load 'org-capture
  (add-to-list 'org-capture-templates
               '("h" "Haystack note" plain
                 (function haystack-new-note)
                 ""
                 :immediate-finish t)))

;; End of haystack init snippet.
;; This configuration provides fast emacs-lisp-backed search over your
;; zettelkasten with frecency ranking and vocabulary expansion.
