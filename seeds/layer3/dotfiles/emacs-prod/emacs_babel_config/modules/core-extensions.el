;; Enable which-key for keybinding discovery
  (use-package which-key
    :defer 0
    :diminish
    :config
    (which-key-mode))

  ;; Completion and search system
  (use-package ivy
    :diminish
    :bind (("C-s" . swiper)
           :map ivy-minibuffer-map
           ("TAB" . ivy-alt-done)
           ("C-l" . ivy-alt-done)
           ("C-j" . ivy-next-line)
           ("C-k" . ivy-previous-line)
           :map ivy-switch-buffer-map
           ("C-k" . ivy-previous-line)
           ("C-l" . ivy-done)
           ("C-d" . ivy-switch-buffer-kill)
           :map ivy-reverse-i-search-map
           ("C-k" . ivy-previous-line)
           ("C-d" . ivy-reverse-i-search-kill))
    :config
    (ivy-mode 1))

  (use-package counsel
    :bind (("C-M-j" . counsel-switch-buffer)
           :map minibuffer-local-map
           ("C-r" . counsel-minibuffer-history))
    :custom
    (counsel-linux-app-format-function #'counsel-linux-app-format-function-name-only)
    :config
    (counsel-mode 1))

  (use-package ivy-rich
    :after counsel
    :init
    (ivy-rich-mode 1))

  ;; Use to prioritize command history based on usage.
  (use-package ivy-prescient
  :after counsel
  :custom
  (ivy-prescient-enable-filtering nil)
  :config
  ;; Uncomment the following line to have sorting remembered across sessions!
  ;: (prescient-persist-mode 1)
  (ivy-prescient-mode 1))

  (use-package helpful
    :custom
    (counsel-describe-function-function #'helpful-callable)
    (counsel-describe-variable-function #'helpful-variable)
    :bind
    ([remap describe-function] . counsel-describe-function)
    ([remap describe-command] . helpful-command)
    ([remap describe-variable] . counsel-describe-variable)
    ([remap describe-key] . helpful-key))

  ;; Set up leader keys.
  (use-package general
    :demand t
    :config
    (general-define-key
     :keymaps 'global
     :prefix-map 'my/leader-map
     :prefix "M-m")

    (general-create-definer my/leader
      :keymaps 'my/leader-map)

    (global-set-key (kbd "M-i") #'back-to-indentation))

  ;; Define a macro that builds sub-menus off M-m using `my/leader`
  (defmacro +general-global-menu! (name prefix-key &rest body)
    "Create a definer named my/global-NAME wrapping `my/leader`.
  Create prefix map: my/global-NAME-map. Bind BODY under M-m PREFIX-KEY."
    (declare (indent 2))
    (let* ((sym (intern (format "my/global-%s" name)))
           (prefix-map (intern (format "my/global-%s-map" name))))
      `(progn
         (general-create-definer ,sym
           :wrapping my/leader
           :prefix-map ',prefix-map
           :prefix ,prefix-key
           :wk-full-keys nil
           "" '(:ignore t :which-key ,name))
         (,sym ,@body))))

;; Bookmark leader keys.
(use-package bookmark
  :straight nil
  :custom
  (bookmark-save-flag 1)   ;; autosave bookmarks after each change
  (bookmark-sort-flag t)   ;; keep bookmarks sorted by name
  :config
  (+general-global-menu! "bookmark" "b"
    "j" '(bookmark-jump       :which-key "jump")
    "s" '(bookmark-set        :which-key "set")
    "l" '(bookmark-bmenu-list :which-key "list")
    "d" '(bookmark-delete     :which-key "delete")
    "r" '(bookmark-rename     :which-key "rename")))

;; Faster global chords
(require 'bookmark)
(global-set-key (kbd "C-x j")   #'bookmark-jump)       ;; jump
(global-set-key (kbd "C-x J")   #'bookmark-bmenu-list) ;; list/manage
(global-set-key (kbd "C-x M-j") #'bookmark-set)        ;; set
