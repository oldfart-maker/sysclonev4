;; Font sizing defaults for UI scaling (override per-host if needed)
  (defvar my/default-font-size 100)
  (defvar my/default-variable-font-size 100)

  ;; Frame transparency defaults
  (defvar my/frame-transparency '(90 . 90))

  ;; Disable unnecessary UI elements
  (scroll-bar-mode -1)
  (tool-bar-mode -1)
  (tooltip-mode -1)
  (menu-bar-mode -1)
  (set-fringe-mode 10)

  ;; Set up the visible bell
  (setq visible-bell t)

  ;; Show column and line numbers
  (column-number-mode)
  (global-display-line-numbers-mode t)

  ;; Set frame font and theme
  (set-face-attribute 'default nil :font "JetBrains Mono" :height my/default-font-size)
  (set-face-attribute 'fixed-pitch nil :font "Fira Code Retina" :height my/default-font-size)
  (set-face-attribute 'variable-pitch nil :font "Cantarell" :height my/default-variable-font-size :weight 'regular)

  ;; Apply frame transparency
  (set-frame-parameter (selected-frame) 'alpha my/frame-transparency)
  (add-to-list 'default-frame-alist `(alpha . ,my/frame-transparency))

  ;; Themes
  (use-package spacemacs-theme :defer t)
  (use-package doom-themes :defer t)
  (use-package modus-themes :defer t)

  (load-theme 'doom-1337 t)

  (use-package doom-modeline
    :after (nerd-icons)
    :config
    (setq doom-modeline-minor-modes t)
    (setq doom-modeline-major-mode-icon t)
    (setq doom-modeline-enable-word-count t)
    (setq doom-modeline-height 30)
    (setq doom-modeline-bar-width 5)
    (setq doom-modeline-indent-info t)
    (setq doom-modeline-lsp t)
    (setq doom-modeline-github t)
    (setq doom-modeline-buffer-modification-icon t)
    (setq doom-modeline-unicode-fallback t)
    :hook (after-init . doom-modeline-mode))

     ;; Focus follows mouse
  (setq mouse-autoselect-window t)

    ;; Setup window borders like wtm
  (window-divider-mode 1)
  (setq window-divider-default-places t)
  (setq window-divider-default-bottom-width 1)
  (setq window-divider-default-right-width 1)

   ;; Set all borders to orange
  (set-face-attribute 'window-divider nil :foreground "orange")
  (set-face-attribute 'vertical-border nil :foreground "orange")

  ;; Mode line borders - also orange
  (set-face-attribute 'mode-line nil
                    :background "#4c566a"
                    :foreground "#eceff4"
                    :box '(:line-width 1 :color "orange"))

  (set-face-attribute 'mode-line-inactive nil
                    :background "#2e3440"
                    :foreground "#88909f"
                    :box '(:line-width 1 :color "orange"))

;; Window shading - active window much darker
  (defvar my-active-window-background "#000000")    ; Very dark for active
  (defvar my-inactive-window-background "#2a2a2a")  ; Lighter for inactive

  (defun my-apply-window-shading ()
  "Apply shading - active window darker, inactive lighter."
     (dolist (window (window-list))
       (with-current-buffer (window-buffer window)
         (face-remap-reset-base 'default)
         (if (eq window (selected-window))
             ;; Active window - much darker
             (face-remap-add-relative 'default :background my-active-window-background)
           ;; Inactive windows - lighter
           (face-remap-add-relative 'default :background my-inactive-window-background)))))

  ;; Apply shading on window changes
  (add-hook 'window-selection-change-functions 
          (lambda (&rest _) (my-apply-window-shading)))

  ;; Protect settings from being overridden
  (defun my-protect-window-settings (&rest _)
     (when window-divider-mode
       (setq window-divider-default-bottom-width 1)
       (setq window-divider-default-right-width 1))
     (set-face-attribute 'window-divider nil :foreground "orange")
     (set-face-attribute 'vertical-border nil :foreground "orange")
     (my-apply-window-shading))

  (advice-add 'load-theme :after #'my-protect-window-settings)

  ;; Initialize everything
  (my-apply-window-shading)

  ;; End of Window Configuration
  (put 'erase-buffer 'disabled nil)

  ;; Show line numbers:
  (add-hook 'prog-mode-hook 'display-line-numbers-mode)
  (add-hook 'text-mode-hook 'display-line-numbers-mode)
  (global-set-key (kbd "<f9>") 'display-line-numbers-mode)

  ;; Show parent parenthesis.
  (show-paren-mode 1)

  ;; Setup smooth scrolling.
  (setq scroll-conservatively 1)

  ;; Switch cursor to new window automatically
  (defun split-and-follow-horizontally ()
    (interactive)
    (split-window-below)
    (balance-windows)
    (other-window 1))
  (global-set-key (kbd "C-x 2") 'split-and-follow-horizontally)

  (defun split-and-follow-vertically ()
    (interactive)
    (split-window-right)
    (balance-windows)
    (other-window 1))
  (global-set-key (kbd "C-x 3") 'split-and-follow-vertically)  

  ;; Highlight current line.  
  (add-hook 'after-init-hook 'global-hl-line-mode)

  ;; Bracket pair-matching.
  (setq electric-pair-pairs '(
                          (?\{ . ?\})
                          (?\( . ?\))
                          (?\[ . ?\])
                          (?\" . ?\")
                          ))
  (electric-pair-mode t)

  ;; Clean up minor mode with minions.
  (use-package minions
  :config (minions-mode 1)
  (setq minions-mode-line-lighter "☰"))

  ;; Icons on Emacs.
  (use-package nerd-icons
    :custom
    (nerd-icons-scale-factor 1.0)
    (nerd-icons-default-adjust 0.0))

  (use-package nerd-icons-completion      :straight
    (nerd-icons-completion :type git :host github
                       :repo "rainstormstudio/nerd-icons-completion")
    :demand t
    :hook
    (marginalia-mode . nerd-icons-completion-marginalia-setup)
    :config
    (nerd-icons-completion-mode))

  (use-package nerd-icons-dired
    :straight (nerd-icons-dired :type git :host github
                            :repo "rainstormstudio/nerd-icons-dired")
    :hook
    (dired-mode . nerd-icons-dired-mode))

  (use-package treemacs-nerd-icons
    :straight (treemacs-nerd-icons :type git :host github
                               :repo "rainstormstudio/treemacs-nerd-icons")
    :config
    (with-eval-after-load 'treemacs
      (treemacs-load-theme "nerd-icons")))

  ;; Better undo + redo
  (use-package undo-tree
    :config
    (global-undo-tree-mode 1))

  ;; Briefly highlight the cursor when switching windows/buffers.
  (use-package beacon
    :init
    (beacon-mode 1))

  ;; Hightlight, index and go to any character by pressing the index key.
  (use-package avy
    :bind
    ("M-s" . avy-goto-char))

  ;; Shows window numbers to select to change window
  (use-package ace-window
  :ensure t
  :bind (("M-o" . ace-window)))

  ;; Better way to switch windows.
  (use-package switch-window
    :config
    (setq switch-window-input-style 'minibuffer)
    (setq switch-window-increase 4)
    (setq switch-window-threshold 2)
    (setq switch-window-shortcut-style 'qwerty)
    (setq switch-window-qwerty-shortcuts
	  '("a" "s" "d" "f" "j" "k" "l"))
    (setq switch-window-minibuffer-shortcut ?z)
    :bind
    ([remap other-window] . switch-window))

    ;; Display page breaks as horizontal lines.
    (use-package page-break-lines
      :requires dashboard
      :init
      (global-page-break-lines-mode))

  ;; Window management leader keys.
  (require 'windmove)

  (+general-global-menu! "window" "w"
    "?" 'split-window-vertically            ;; or use split-window-below
    "=" 'balance-windows
    "/" 'split-window-horizontally          ;; or use split-window-right
    "O" 'delete-other-windows
    "X" '((lambda () (interactive)
            (call-interactively #'other-window)
            (kill-buffer-and-window))
          :which-key "kill other buf+win")
    "d" 'delete-window
    "h" 'windmove-left
    "j" 'windmove-down
    "k" 'windmove-up
    "l" 'windmove-right
    "o" 'other-window
    "t" 'window-toggle-side-windows
    "."  '(:ignore t :which-key "resize")   ;; <-- fixed :ignore
    ".h" '((lambda () (interactive)
             (call-interactively (if (window-prev-sibling)
                                     #'enlarge-window-horizontally
                                   #'shrink-window-horizontally)))
           :which-key "divider left")
    ".l" '((lambda () (interactive)
             (call-interactively (if (window-next-sibling)
                                     #'enlarge-window-horizontally
                                   #'shrink-window-horizontally)))
           :which-key "divider right")
    ".j" '((lambda () (interactive)
             (call-interactively (if (window-next-sibling)
                                     #'enlarge-window
                                   #'shrink-window)))
           :which-key "divider up")
    ".k" '((lambda () (interactive)
             (call-interactively (if (window-prev-sibling)
                                     #'enlarge-window
                                   #'shrink-window)))
           :which-key "divider down")
    "x" 'kill-buffer-and-window)
