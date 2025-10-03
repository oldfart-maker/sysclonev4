(setq my/env "emacs-prod")
(setq server-name "emacs-prod")

(load-file (concat "~/.config/emacs-common" "/api-keys.el"))

(require 'server)
(unless (server-running-p)
   (server-start))

;; Turn of eval protection
(setq org-confirm-babel-evaluate nil)

(setq custom-file (expand-file-name "custom.el" user-emacs-directory))
(load custom-file 'noerror)
