(add-to-list 'load-path "/usr/share/emacs/site-lisp/mu4e")
  (require 'mu4e)

  (setq mu4e-maildir "~/Maildir/yahoo") ;; or wherever your Maildir lives
  (require 'mu4e)

  (setq user-mail-address "mkburns61@yahoo.com")
  (setq user-full-name "Mike Burns")

  (setq send-mail-function 'sendmail-send-it
        message-send-mail-function 'sendmail-send-it
        sendmail-program "/usr/bin/msmtp"
        mail-specify-envelope-from t
        mail-envelope-from 'header)

  (defun my/run-mbsync ()
    "Run mbsync to sync mail."
    (start-process-shell-command "mbsync" "*mbsync*" "mbsync -a"))

  ;; Run every 5 minutes (adjust as needed)
  (run-at-time "5 min" 300 #'my/run-mbsync)

  (setq mu4e-update-interval 300)  ;; 5 minutes

  ;; Setup image preview
  (setq mu4e-view-show-images t)
  (setq mu4e-view-use-gnus t) 
  (setq mu4e-view-image-max-width 800)
  (setq mu4e-view-show-addresses 't)

  (setq shr-inhibit-images nil)
  (setq gnus-inhibit-images nil)

  (defun my-mu4e-view-inline-images ()
    "Show images automatically in mu4e."
    (when (fboundp 'shr-put-image)
      (setq mu4e-view-show-images t)))

  (setq url-privacy-level 'low)

  (defun my/mu4e-view-message-no-focus ()
    "View the current message in another window without changing focus."
    (interactive)
    (let ((msg (mu4e-message-at-point)))
      (when msg
        (save-selected-window
          (mu4e-view msg)))))

  (with-eval-after-load 'mu4e
    (define-key mu4e-headers-mode-map (kbd "V") #'my/mu4e-view-message-no-focus))

  ;; Open email in a dedicated frame for better workflow.
  (defun my/mu4e-open-in-dedicated-frame ()
    "Open mu4e in a dedicated frame named 'mu4e'."
    (interactive)
    (let ((bufname "*mu4e*"))
      (if (get-buffer bufname)
          ;; If buffer already exists, raise the frame or switch to it
          (progn
            (select-frame-set-input-focus
             (window-frame (get-buffer-window bufname))))
        ;; Else create new frame and launch mu4e
  	(let* ((frame (make-frame '((name . "mu4e")
                                    (width . 100)
                                    (height . 40)))))
          (select-frame-set-input-focus frame)
          (with-selected-frame frame
            (mu4e)
            (set-window-dedicated-p (selected-window) t))))))

  ;; Use bbdb for email contacts configuration.
  (use-package bbdb
        :defer t )

  (setq bbdb-file "~/.config/emacs-common/bbdb")
  (require 'bbdb)
  (require 'bbdb-com)
  (bbdb-initialize 'mu4e 'message)

  (setq mu4e-use-bbdb t)

  (bbdb-mua-auto-update-init 'mu4e)

  (setq message-completion-alist
      '((message-to . bbdb-complete-mail)
        (message-cc . bbdb-complete-mail)
        (message-bcc . bbdb-complete-mail)))

  (define-key message-mode-map (kbd "TAB") 'bbdb-complete-mail)

;; --- Mu4e leader menu ---
(with-eval-after-load 'mu4e
  ;; DWIM wrappers so reply/all/forward work from headers or view
  (defun my/mu4e-reply ()      (interactive) (call-interactively #'mu4e-compose-reply))
  (defun my/mu4e-reply-all ()  (interactive) (call-interactively #'mu4e-compose-wide-reply))
  (defun my/mu4e-forward ()    (interactive) (call-interactively #'mu4e-compose-forward))

  (+general-global-menu! "mail" "e"
    ;; open / sync
    "m" '(mu4e                       :which-key "open mu4e")
    "u" '(mu4e-update-mail-and-index :which-key "update & index")
    ;; compose
    "c" '(mu4e-compose-new           :which-key "new email")
    "r" '(my/mu4e-reply              :which-key "reply")
    "a" '(my/mu4e-reply-all          :which-key "reply all")
    "f" '(my/mu4e-forward            :which-key "forward")
    ;; search
    "s" '(mu4e-headers-search        :which-key "search")
    "S" '(mu4e-headers-search-edit   :which-key "edit last search")))

;; Compose-mode keys: send / draft / abort
(with-eval-after-load 'mu4e-compose
  (general-define-key
   :keymaps 'mu4e-compose-mode-map
   :prefix "M-m"
   "m s" '(message-send-and-exit :which-key "send & exit")
   "m d" '(message-dont-send     :which-key "save draft")
   "m A" '(message-kill-buffer   :which-key "abort")))
