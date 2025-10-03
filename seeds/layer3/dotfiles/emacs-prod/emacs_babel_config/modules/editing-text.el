;; --- Defaults ---------------------------------------------------------------

  (setq-default fill-column 80)              ;; used for hard wrap (auto-fill / M-q)
  (setq sentence-end-double-space nil)
  (setq comment-auto-fill-only-comments t)

  ;; Show a guide in code buffers (redundant for prose when using VFC)
  (add-hook 'prog-mode-hook #'display-fill-column-indicator-mode)

  ;; --- Prose wrapping helpers -------------------------------------------------

  (defvar my/prose-width 88
    "Preferred visual text width for prose buffers (Org/Markdown/Text).")

  (defun my/enable-prose-wrapping ()
    "Soft-wrap at `my/prose-width` with centered text (no hard line breaks)."
    (setq-local truncate-lines nil)
    (setq-local visual-fill-column-width my/prose-width)
    (visual-line-mode 1)
    (when (boundp 'display-fill-column-indicator-mode)
      (display-fill-column-indicator-mode 0))
    (when (fboundp 'visual-fill-column-mode)
      (visual-fill-column-mode 1)))

  (defun my/text-soft-wrap ()
    "Soft wrap at window/visual width (no hard breaks)."
    (interactive)
    (setq-local truncate-lines nil)
    (visual-line-mode 1)
    (when (fboundp 'visual-fill-column-mode)
      (visual-fill-column-mode 1))
    (message "wrap: soft (visual)%s"
             (if (bound-and-true-p visual-fill-column-mode)
                 (format " @ %d" (or visual-fill-column-width my/prose-width))
               "")))

  (defun my/text-hard-wrap ()
    "Hard wrap at `fill-column` (auto-fill)."
    (interactive)
    (visual-line-mode 0)
    (when (fboundp 'visual-fill-column-mode)
      (visual-fill-column-mode -1))
    (auto-fill-mode 1)
    (message "wrap: hard (auto-fill) @ %d" fill-column))

  (defun my/toggle-wrap ()
    "Cycle: off → soft → hard."
    (interactive)
    (cond
     ((and (not visual-line-mode) (not auto-fill-function))
      (my/text-soft-wrap))
     ((and visual-line-mode (not auto-fill-function))
      (my/text-hard-wrap))
     (t
      (visual-line-mode 0)
      (when (fboundp 'visual-fill-column-mode)
        (visual-fill-column-mode -1))
      (auto-fill-mode 0)
      (message "wrap: off"))))

  (defun my/set-fill-column (n)
    "Set buffer-local `fill-column` to N and update indicator."
    (interactive "nFill column: ")
    (setq-local fill-column n
                display-fill-column-indicator-column n)
    (when (bound-and-true-p display-fill-column-indicator-mode)
      (force-window-update (current-buffer)))
    (message "fill-column → %d" n))

  ;; --- visual-fill-column (soft wrap at fixed width) --------------------------

  (use-package visual-fill-column
    :straight t
    :commands (visual-fill-column-mode visual-fill-column-split-window-sensibly)
    :init
    ;; Center text; set to nil if you prefer left-aligned.
    (setq visual-fill-column-center-text nil)
    ;; Make window splitting respect VFC margins.
    (setq split-window-preferred-function
          #'visual-fill-column-split-window-sensibly)
    :hook
    ((text-mode markdown-mode org-mode) . my/enable-prose-wrapping))

  ;; Convenience commands to adjust visual width on the fly
  (defun my/vfc-set-width (n)
    "Set the visual body width to N columns in this buffer."
    (interactive "nVisual width (cols): ")
    (setq-local visual-fill-column-width n)
    (when (bound-and-true-p visual-fill-column-mode)
      (visual-fill-column-mode -1)
      (visual-fill-column-mode 1))
    (message "visual width → %d" n))

  (defun my/vfc-wider (n)
    "Widen visual body by prefix N (default 2) columns."
    (interactive "p")
    (my/vfc-set-width (+ (or visual-fill-column-width my/prose-width 80)
                         (or n 2))))

  (defun my/vfc-narrower (n)
    "Narrow visual body by prefix N (default 2) columns (min 40)."
    (interactive "p")
    (my/vfc-set-width (max 40
                           (- (or visual-fill-column-width my/prose-width 80)
                              (or n 2)))))

  (defun my/vfc-toggle ()
    "Toggle visual-fill-column + visual-line for this buffer."
    (interactive)
    (if (bound-and-true-p visual-fill-column-mode)
        (progn
          (visual-fill-column-mode -1)
          (visual-line-mode -1)
          (message "visual-fill-column: off"))
      (my/enable-prose-wrapping)
      (message "visual-fill-column: on @ %d"
               (or visual-fill-column-width my/prose-width))))

  ;; --- Org-specific -----------------------------------------------------------

  ;; Org starts truncated by default; disable so wrapping works as expected.
  (setq org-startup-truncated nil)

  ;; --- Leader keys ------------------------------------------------------------
  (+general-global-menu! "text" "t"
    ;; Visual fill controls
    "v" 'my/vfc-toggle
    "V" 'my/vfc-set-width
    "]" 'my/vfc-wider
    "[" 'my/vfc-narrower

    ;; Wrap style
    "w" 'my/toggle-wrap
    "s" 'my/text-soft-wrap
    "h" 'my/text-hard-wrap

    ;; Fill column
    "c" 'my/set-fill-column)

  ;; Markdown mode
(use-package markdown-mode
  :straight t
  :mode (("README\\.md\\'" . gfm-mode)
         ("\\.md\\'"       . markdown-mode)
         ("\\.markdown\\'" . markdown-mode))
  :init
  ;; Optional: use pandoc for conversions from within markdown-mode
  ;; (setq markdown-command "pandoc -f gfm -t html")
  (setq markdown-hide-markup t          ; cleaner look (toggle: markdown-toggle-markup-hiding)
        markdown-fontify-code-blocks-natively t
        markdown-enable-math t)
  :hook
  ((markdown-mode gfm-mode) . my/enable-prose-wrapping))

;; --- Leader keys (uses your +general-global-menu! macro) -------------------
(+general-global-menu! "markdown" "m"
  "p" 'markdown-live-preview-mode      ;; start/stop built-in HTML preview
  "b" 'markdown-insert-bold
  "i" 'markdown-insert-italic
  "c" 'markdown-insert-code
  "l" 'markdown-insert-link
  "h" 'markdown-toggle-markup-hiding)

  (provide 'editing-text)
  ;;; editing-text.el ends here
