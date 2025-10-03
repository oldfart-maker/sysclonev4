(defun my/bbdb-reset-and-import (file-path)
  "Clear BBDB and import contacts from FILE-PATH."
  (interactive "fPath to .contacts file: ")
  ;; 1. Clear in-memory
  (setq bbdb-records nil)
  ;; 2. Delete on-disk DB
  (when (file-exists-p bbdb-file)
    (delete-file bbdb-file))
  ;; 3. Re-initialize
  (bbdb-initialize 'mu4e)
  ;; 4. Load and import
  (my/import-contacts-to-bbdb file-path)
  ;; 5. Save DB
  (bbdb-save)
  (message "BBDB reset and import complete."))

(defun my/import-contacts-to-bbdb (file-path)
  "Import contacts from FILE-PATH into BBDB."
  (interactive "fPath to .contacts file: ")
  (let ((imported 0)
        (skipped 0))
    (with-temp-buffer
      (insert-file-contents file-path)
      (goto-char (point-min))
      (while (re-search-forward "^\\(.*?\\) <\\(.*?\\)>$" nil t)
        (let* ((name (match-string 1))
               (email (match-string 2))
               (name-parts (split-string name " "))
               (first (car name-parts))
               (last (mapconcat #'identity (cdr name-parts) " "))
               (existing (bbdb-search (bbdb-records) nil nil nil email)))
          (condition-case err
              (unless existing
                (bbdb-create-internal first last nil nil (list email) nil)
                (setq imported (1+ imported)))
            (error
             (setq skipped (1+ skipped))
             (message "Skipped: %s <%s> (%s)" name email (error-message-string err)))))))
    (message "Contacts import complete. Imported: %d, Skipped: %d" imported skipped)))
