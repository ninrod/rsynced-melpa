;;; helm-tramp.el --- Tramp helm interface for ssh server and docker -*- lexical-binding: t; -*-

;; Copyright (C) 2017 by Masashı Mıyaura

;; Author: Masashı Mıyaura
;; URL: https://github.com/masasam/emacs-helm-tramp
;; Package-Version: 20170412.437
;; Version: 0.3.3
;; Package-Requires: ((emacs "24.3") (helm "2.0"))

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <http://www.gnu.org/licenses/>.

;;; Commentary:

;; helm-tramp provides interfaces of Tramp
;; You can also use tramp with helm interface as root
;; If you use it with docker-tramp, you can also use docker with helm interface

;;; Code:

(require 'helm)
(require 'tramp)
(require 'cl-lib)

(defgroup helm-tramp nil
  "Tramp with helm interface for server and docker"
  :group 'helm)

(defcustom helm-tramp-docker-user nil
  "If you want to use login user name when docker-tramp used, set variable."
  :group 'helm-tramp
  :type 'string)

(defun helm-tramp--candidates ()
  "Collect candidates for helm-tramp."
  (let ((source (split-string
                 (with-temp-buffer
                   (insert-file-contents "~/.ssh/config")
                   (buffer-string))
                 "\n"))
        (hosts (list)))
    (dolist (host source)
      (when (string-match "[H\\|h]ost +\\(.+?\\)$" host)
	(setq host (match-string 1 host))
	(if (string-match "[ \t\n\r]+\\'" host)
	    (replace-match "" t t host))
	(if (string-match "\\`[ \t\n\r]+" host)
	    (replace-match "" t t host))
        (unless (string= host "*")
          (push
	   (concat "/" tramp-default-method ":" host ":/")
	   hosts)
	  (push
	   (concat "/ssh:" host "|sudo:" host ":/")
	   hosts))))
    (when (featurep 'docker-tramp)
      (cl-loop for line in (cdr (ignore-errors (apply #'process-lines "docker" (list "ps"))))
	       for info = (split-string line "[[:space:]]+" t)
	       collect (progn (push
			       (concat "/docker:" (car info) ":/")
			       hosts)
			      (unless (null helm-tramp-docker-user)
				(push
				 (concat "/docker:" helm-tramp-docker-user "@" (car info) ":/")
				 hosts)))))
    (reverse hosts)))

(defun helm-tramp-open (path)
  "Tramp open with PATH."
  (find-file path))

(defvar helm-tramp--source
  (helm-build-sync-source "Tramp"
    :candidates #'helm-tramp--candidates
    :volatile t
    :action (helm-make-actions
             "Tramp" #'helm-tramp-open)))

;;;###autoload
(defun helm-tramp ()
  "Open your ~/.ssh/config with helm interface.
You can connect your server with tramp"
  (interactive)
  (unless (file-exists-p "~/.ssh/config")
    (error "There is no ~/.ssh/config"))
  (when (featurep 'docker-tramp)
    (unless (executable-find "docker")
      (error "'docker' is not installed")))
  (helm :sources '(helm-tramp--source) :buffer "*helm tramp*"))

(provide 'helm-tramp)

;;; helm-tramp.el ends here
