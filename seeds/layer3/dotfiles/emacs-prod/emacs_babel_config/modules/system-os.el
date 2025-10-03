(use-package dired
    :straight (:type built-in)
    :ensure nil
    :custom (dired-listing-switches "-alh --group-directories-first")
    :commands (dired dired-jump)
    :bind (("C-x C-j" . dired-jump)))

;; Leader menu for Dired: M-m d …
(with-eval-after-load 'dired
  ;; Only if general.el is available
  (when (require 'general nil t)
    (general-define-key
     :keymaps 'dired-mode-map
     :prefix "M-m d"
     "" '(:ignore t :which-key "dired")

     ;; open / jump
     "d" '(dired :which-key "open dired")
     "." '((lambda () (interactive) (dired default-directory)) :which-key "here")
     "j" '(dired-jump :which-key "jump to file")
     "J" '(dired-jump-other-window :which-key "jump (other win)")

     ;; view / listing
     "r" '(revert-buffer :which-key "refresh")
     "h" '(dired-hide-details-mode :which-key "toggle details")
     "o" '(dired-omit-mode :which-key "toggle dotfiles")
     "s" '(dired-sort-toggle-or-edit :which-key "sort")

     ;; edit names (wdired)
     "e" '(wdired-change-to-wdired-mode :which-key "edit names")

     ;; create / file ops
     "+" '(dired-create-directory :which-key "mkdir")
     "C" '(dired-do-copy :which-key "copy")
     "R" '(dired-do-rename :which-key "rename/move")
     "D" '(dired-do-delete :which-key "delete")
     "X" '(dired-do-flagged-delete :which-key "delete flagged")
     "z" '(dired-do-compress :which-key "compress")
     "T" '(dired-do-touch :which-key "touch mtime")
     "M" '(dired-do-chmod :which-key "chmod")
     "O" '(dired-do-chown :which-key "chown")

     ;; marking
     "m" '(dired-mark :which-key "mark")
     "u" '(dired-unmark :which-key "unmark")
     "U" '(dired-unmark-all-marks :which-key "unmark all")
     "t" '(dired-toggle-marks :which-key "toggle marks")

     ;; search / replace
     "f" '(dired-do-find-regexp :which-key "find regexp")
     "Q" '(dired-do-find-regexp-and-replace :which-key "query replace")

     ;; shell
     "!" '(dired-do-shell-command :which-key "shell cmd")
     "&" '(dired-do-async-shell-command :which-key "async shell"))))

  (use-package all-the-icons-dired
    :hook (dired-mode . all-the-icons-dired-mode))

  ;; Launch apps based on content.
  (use-package dired-open
    :config
    (setq dired-open-extensions
  	'(("png" . "imv")
  	  ("jpg" . "imv")
  	  ("pdf" . "zathura")
  	  ("mp4" . "mpv")
  	  ("mkv" . "mpv")
  	  ("html" . "floorp"))))

  ;; Bind enter to launch associated file app.
  (with-eval-after-load 'dired
  ;; Replace RET behavior
  (define-key dired-mode-map (kbd "RET") #'dired-open-file))


  (use-package dired-hide-dotfiles
    :hook (dired-mode . dired-hide-dotfiles-mode))

  ;; Must have dired extensions
  (use-package peep-dired
    :ensure t
    :bind (:map dired-mode-map
                ("P" . peep-dired))
    :hook (peep-dired-mode . (lambda () (setq-local image-dired-display-image-buffer 'other))))

  (use-package dired-subtree
    :ensure t
    :bind (:map dired-mode-map
                ("<tab>" . dired-subtree-toggle)))

(use-package vterm
  :commands vterm
  :bind ("C-c v" . vterm)
  :config
  (setq vterm-shell "/usr/bin/fish")
  (setq vterm-max-scrollback 10000))
