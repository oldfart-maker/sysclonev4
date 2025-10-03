;; Tell straight not to fetch/build Org; use Emacs' built-in instead.
  (use-package org
    :straight (:type built-in))
  
  (use-package org
         :defer t )
   
   (setq my/random-notes-file "~/Documents/Office-Docs (Global Sync)/random_notes.org")

     ;; Org Capture Template
     (setq org-capture-templates
           '(("r" "Random quick note"
              entry
              (file+headline my/random-notes-file "Inbox")
              "* %U %?\n  :tags: %^{Tags}\n"
              :empty-lines 1)))
     (global-set-key (kbd "C-c r") 'org-capture)

(org-babel-do-load-languages
'org-babel-load-languages
'((python . t)))
