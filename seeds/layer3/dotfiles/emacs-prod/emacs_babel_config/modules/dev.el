(use-package typescript-mode
  :mode "\\.ts\\'")

(use-package python-mode
  :hook (python-mode . eglot-ensure))

(use-package pyvenv
  :config (pyvenv-mode 1))

(use-package projectile
  :diminish projectile-mode
  :config (projectile-mode)
  :custom ((projectile-completion-system 'ivy))
  :bind-keymap
  ("C-c p" . projectile-command-map)
  :init
  (when (file-directory-p "~/Documents/Code")
    (setq projectile-project-search-path '("~/Documents/Code")))
  (setq projectile-switch-project-action #'projectile-dired))

(use-package counsel-projectile
  :config (counsel-projectile-mode))

(use-package rainbow-delimiters
  :hook (prog-mode . rainbow-delimiters-mode))

(use-package request
:ensure t)

(require 'request)
(require 'json)

;; Git integration.
(use-package magit
  :config
  (setq magit-push-always-verify nil)
  (setq git-commit-summary-max-length 50)
  :bind
  ("M-g" . magit-status))

(use-package treemacs-magit
  :after treemacs magit)

(use-package ghub
  :demand t
  :after magit)  

;; Enable Eglot automatically for certain modes
(add-hook 'python-mode-hook #'eglot-ensure)
