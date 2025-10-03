;;Debug statements
;;(setq tramp-verbose 10)
;;(setq tramp-debug-buffer t)

(defun remote/dired-pi-5 ()
  "Open Dired in home directory on pi-5."
  (interactive)
  (dired "/ssh:username@192.168.1.57:/home/username/"))

(defun remote/dired-lenovo ()
  "Open Dired in home directory on lenovo."
  (interactive)
  (dired "/ssh:username@192.168.1.80:/home/username/"))

(defun remote/dired-dell ()
  "Open Dired in home directory on dell."
  (interactive)
  (dired "/ssh:username@192.168.1.108:/home/username/"))
