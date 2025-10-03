;; Start quiet
(setq inhibit-startup-screen t
      inhibit-startup-message t
      ring-bell-function #'ignore)

;; Files/backups
(setq make-backup-files nil
      auto-save-default nil
      load-prefer-newer t)

;; UTF-8 everywhere
(prefer-coding-system 'utf-8)
(set-default-coding-systems 'utf-8)
(set-terminal-coding-system 'utf-8)
(set-keyboard-coding-system 'utf-8)

;; Make ESC quit prompts
(global-set-key (kbd "<escape>") #'keyboard-escape-quit)

;; Don’t let package.el auto-enable itself (we use straight.el)
(setq package-enable-at-startup nil)

;; straight.el bootstrap + use-package integration
(defvar bootstrap-version)
(let* ((user-dir user-emacs-directory)
       (bootstrap-file
        (expand-file-name "straight/repos/straight.el/bootstrap.el" user-dir)))
  (unless (file-exists-p bootstrap-file)
    (with-current-buffer
        (url-retrieve-synchronously
         "https://raw.githubusercontent.com/radian-software/straight.el/develop/install.el"
         'silent 'inhibit-cookies)
      (goto-char (point-max))
      (eval-print-last-sexp)))
  (load bootstrap-file nil 'nomessage))

;; Install use-package via straight and make it the default installer
(straight-use-package 'use-package)
(setq straight-use-package-by-default t)
(require 'use-package)

;; Housekeeping
(use-package no-littering
  :config
  (setq auto-save-file-name-transforms
        `((".*" ,(no-littering-expand-var-file-name "auto-save/") t))))

;; Optional: Weekly straight update + lock versions at 09:00
(add-hook 'emacs-startup-hook
          (lambda ()
            (run-at-time "09:00" (* 7 24 60 60)
                         (lambda ()
                           (message "Straight: pulling all & freezing versions…")
                           (straight-pull-all)
                           (straight-freeze-versions)
                           (message "Straight: done.")))))

;; Ensure environment variables inside Emacs look the same as in the shell.
(use-package exec-path-from-shell
  :init)
(when (memq window-system '(mac ns x))
  (exec-path-from-shell-initialize))
(when (daemonp)
  (exec-path-from-shell-initialize))

(provide 'core)
