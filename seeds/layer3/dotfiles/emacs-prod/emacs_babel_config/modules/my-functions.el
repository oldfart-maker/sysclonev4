(defun niri-babel-build-and-deploy ()
  "Tangle and deploy config.kdl to ~/.config/niri/config.kdl with 5 rotating backups.
Also copy key_bindings.txt to ~/.config/niri/ if present."
  (interactive)
  (let* ((org-file   "~/projects/niri_babel_config/niri_config.org")
         (output-dir "~/projects/niri_babel_config/")
         (output-file (expand-file-name "config.kdl" output-dir))
         (kb-src      (expand-file-name "key_bindings.txt" output-dir))
         (target-dir  (expand-file-name "~/.config/niri/"))
         (target-file (expand-file-name "config.kdl" target-dir))
         (kb-target   (expand-file-name "key_bindings.txt" target-dir)))

    ;; Execute all non-KDL blocks first
    (with-current-buffer (find-file-noselect org-file)
      (org-babel-map-src-blocks org-file
        (let* ((info (org-babel-get-src-block-info 'light))
               (lang (nth 0 info)))
          (unless (string= lang "kdl")
            (org-babel-execute-src-block))))
      ;; Tangle everything
      (org-babel-tangle))

    ;; Ensure target directory exists
    (make-directory target-dir t)

    ;; Backup rotation (keep last 5) for config.kdl
    (when (file-exists-p target-file)
      (dotimes (i 5)
        (let* ((n (- 5 i))
               (old (format "%s.%03d" target-file n))
               (new (format "%s.%03d" target-file (1+ n))))
          (when (file-exists-p old)
            (rename-file old new t))))
      (copy-file target-file (format "%s.001" target-file) t))

    ;; Deploy new config.kdl
    (when (file-exists-p output-file)
      (copy-file output-file target-file t)
      (message "Tangled and deployed config.kdl to %s" target-file))

    ;; Copy key_bindings.txt if present
    (when (file-exists-p kb-src)
      (copy-file kb-src kb-target t)
      (message "Copied key_bindings.txt to %s" kb-target))))

(require 'image-dired)

(defun my/image-dired-copy-and-exit ()
  "Copy image under point in image-dired and exit Emacsclient."
  (interactive)
  (let* ((file (image-dired-original-file-name))
         (copy-prog (or (executable-find "wl-copy")
                        (executable-find "xclip"))))
    (unless copy-prog
      (error "No clipboard utility (wl-copy or xclip) found"))
    (unless (and file (file-exists-p file))
      (error "No image found under cursor"))
    (with-temp-buffer
      (insert-file-contents-literally file)
      (call-process-region
       (point-min) (point-max)
       copy-prog nil nil nil "-t" "image/png"))
    (save-buffers-kill-terminal)))

(with-eval-after-load 'image-dired
  ;; `m` to copy and exit
  (define-key image-dired-thumbnail-mode-map (kbd "m") #'my/image-dired-copy-and-exit)
  ;; `q` to just quit
  (define-key image-dired-thumbnail-mode-map (kbd "q")
    (lambda ()
      (interactive)
      (save-buffers-kill-terminal))))

(defun my/image-picker-thumbnail-mode ()
  "Launch thumbnail-only image picker. Press `m` to copy & exit."
  (interactive)
  (let ((dir "~/Pictures/screenshots/"))
    ;; Save current window configuration, run image-dired
    (image-dired dir)
    ;; Force delete all windows except the one showing *image-dired*
    (let ((image-buffer "*image-dired*"))
      (dolist (win (window-list))
        (unless (eq (window-buffer win) (get-buffer image-buffer))
          (delete-window win)))
      (select-window (get-buffer-window image-buffer)))))

;; Show the server name that this emacsclient is connected to.
(defun show-current-server-name ()
  "Display the name of the Emacs server this client is connected to."
  (interactive)
  (message "Connected to Emacs server: %s" server-name))

;; Then bind it in the startup hook
(add-hook 'emacs-startup-hook
          (lambda ()
            (global-set-key (kbd "<f12>") #'show-current-server-name)))

;; Output niri-windows to new buffer
(defun niri-windows ()
  "Show Niri windows in a new buffer."
  (interactive)
  (let ((buf (get-buffer-create "*niri-windows*")))
    (with-current-buffer buf
      (read-only-mode -1)
      (erase-buffer)
      (call-process "~/projects/niri_toolkit/niri-windows.py" nil buf)
      (goto-char (point-min))
      (read-only-mode 1))
    (pop-to-buffer buf)))

;;Output niri-event-stream via IPC to new buffer
(defun niri-event-stream ()
  "Show the Niri event stream in a new buffer."
  (interactive)
  (let ((buf (get-buffer-create "*Niri Event Stream*")))
    (apply 'make-comint-in-buffer
           "Niri Event Stream"
           buf
           (expand-file-name "~/projects/niri_toolkit/niri-tail-event-stream.py")
           nil)
    (pop-to-buffer buf)))

(defun open-timeshift-backup ()
  "Open already-mounted Timeshift backup in Dired."
  (interactive)
  (let ((mount-point "/mnt/timeshift"))
    (if (file-directory-p mount-point)
        (dired mount-point)
      (message "Mount point does not exist or is not accessible: %s" mount-point))))

(defun my/ob-remove-all-results ()
  "Delete every #+RESULTS in the current Org buffer.
If a region is active, operate only within that region."
  (interactive)
  (require 'ob)
  (save-excursion
    (save-restriction
      (when (use-region-p)
        (narrow-to-region (region-beginning) (region-end)))
      (let ((n 0))
        (org-babel-map-src-blocks nil
          ;; Here, point is at the #+begin_src line.
          (when (org-babel-where-is-src-block-result)
            (org-babel-remove-result)
            (cl-incf n)))
        (message "Removed %d result block(s)." n)))))

(defun emacs-babel-build-and-deploy ()
  "Tangle and deploy Emacs config to proper env directory with backup and timestamp."
  (interactive)
  (let* ((target-env "emacs-prod")  ;; Assumes `target-env` is a custom function
         (org-file "~/projects/emacs_babel_config/emacs_config.org")
         (modules-dir (expand-file-name (format "~/.config/%s/modules" target-env)))
         (src-dir (expand-file-name "~/projects/emacs_babel_config/modules/"))
         (timestamp-file (expand-file-name
                          (format "~/.config/%s/last_deployed.org" target-env))))

    ;; Debug
    (message "Target env: %s" target-env)

    ;; Run non-Elisp blocks to update values
    (with-current-buffer (find-file-noselect org-file)
      (org-babel-map-src-blocks org-file
        (let* ((info (org-babel-get-src-block-info 'light)))
          (when info
            (let ((lang (nth 0 info)))
              (unless (string= lang "emacs-lisp")
                (org-babel-execute-src-block))))))

    ;; Tangle all blocks
    (org-babel-tangle)

    ;; Copy modules
    (when (file-directory-p src-dir)
      (make-directory modules-dir t)
      (dolist (file (directory-files src-dir t "^[^.].*"))  ; skip dotfiles
        (copy-file file
                   (expand-file-name (file-name-nondirectory file) modules-dir)
                   t)))

    ;; Also copy init.el and early-init.el into the target env dir
    (let* ((target-dir (file-name-directory modules-dir))
           (project-root (file-name-directory org-file))
           (init-src  (expand-file-name "init.el" project-root))
           (early-src (expand-file-name "early-init.el" project-root))
           (init-dest  (expand-file-name "init.el" target-dir))
           (early-dest (expand-file-name "early-init.el" target-dir)))
      (when (file-exists-p init-src)
	(copy-file init-src init-dest t))
      (when (file-exists-p early-src)
	(copy-file early-src early-dest t)))

    ;; Write timestamp
    (with-temp-file timestamp-file
      (insert (format "* Last Deployed\n\nDeployed at: %s\n" (current-time-string))))

    (message "Emacs config deployed to %s" modules-dir))))

;; Toggle to last buffer, but filter out dired and buffer list results
;; when going back.
(require 'seq)      ;; built-in since Emacs 25

(defvar my/skip-back-buffer-modes
  '(dired-mode ibuffer-mode Buffer-menu-mode)
  "Major modes to skip when jumping back to the previous buffer.")

(defun my/other-buffer-skip-browsers ()
  "Switch to the most recent buffer for this window that is not in
`my/skip-back-buffer-modes`. Falls back to `mode-line-other-buffer`."
  (interactive)
  (let* ((cands   (mapcar #'car (window-prev-buffers)))   ;; per-window history
         (target  (seq-find
                   (lambda (buf)
                     (and (buffer-live-p buf)
                          (with-current-buffer buf
                            (not (apply #'derived-mode-p my/skip-back-buffer-modes)))))
                   cands)))
    (if target
        (switch-to-buffer target)
      (mode-line-other-buffer))))

(global-set-key (kbd "C-c b") #'my/other-buffer-skip-browsers)
