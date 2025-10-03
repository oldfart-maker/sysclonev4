;;; init.el — for emacs-prod

(setq user-emacs-directory
      (or (file-name-directory (or load-file-name buffer-file-name))
          default-directory))


(load (expand-file-name "modules/env.el" user-emacs-directory))
(load (expand-file-name "modules/core.el" user-emacs-directory))
(load (expand-file-name "modules/core-extensions.el" user-emacs-directory))
(load (expand-file-name "modules/ui.el" user-emacs-directory))
(load (expand-file-name "modules/org.el" user-emacs-directory))
(load (expand-file-name "modules/dev.el" user-emacs-directory))
(load (expand-file-name "modules/system-os.el" user-emacs-directory))
(load (expand-file-name "modules/email.el" user-emacs-directory))
(load (expand-file-name "modules/my-functions.el" user-emacs-directory))
(load (expand-file-name "modules/remote.el" user-emacs-directory))
