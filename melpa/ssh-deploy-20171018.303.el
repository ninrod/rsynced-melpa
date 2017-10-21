;;; ssh-deploy.el --- Deployment via SSH or FTP, global or per directory.

;; Author: Christian Johansson <github.com/cjohansson>
;; Maintainer: Christian Johansson <github.com/cjohansson>
;; Created: 5 Jul 2016
;; Modified: 17 Oct 2017
;; Version: 1.66
;; Package-Version: 20171018.303
;; Keywords: tools, convenience
;; URL: https://github.com/cjohansson/emacs-ssh-deploy

;; This file is not part of GNU Emacs.

;; Copyright (C) 2017 Christian Johansson

;; This program is free software; you can redistribute it and/or
;; modify it under the terms of the GNU General Public License as
;; published by the Free Software Foundation; either version 2, or (at
;; your option) any later version.

;; This program is distributed in the hope that it will be useful, but
;; WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
;; General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with GNU Emacs; see the file COPYING.  If not, write to the
;; Free Spathoftware Foundation, Inc., 59 Temple Place - Suite 330,
;; Boston, MA 02111-1307, USA.

;;; Commentary:

;; ssh-deploy enables automatic deploys on explicit-save, manual uploads, renaming,
;; deleting, downloads, file differences, remote terminals, detection of remote changes and remote directory browsing via TRAMP.
;;
;; For asynchrous operations it uses async.el,
;;
;; By setting the variables (globally, per directory or per file):
;; ssh-deploy-root-local,ssh-deploy-root-remote, ssh-deploy-on-explicit-save
;; you can setup a directory for SSH or FTP deployment.
;;
;; For asynchronous transfers you need to setup ~/.netrc or key-based authorization or equivalent for automatic authentication.
;;
;; Example contents of ~/.netrc for FTP:
;; machine myserver.com login myuser port ftp password mypassword
;;
;; Set permissions to this file to 700 with you as the owner.
;;
;; - To setup a upload hook on save do this:
;;     (add-hook 'after-save-hook (lambda() (if ssh-deploy-on-explicit-save (ssh-deploy-upload-handler)) ))
;;
;; - To setup automatic storing of base revisions and detection of external changes do this:
;;     (add-hook 'find-file-hook (lambda() (if ssh-deploy-automatically-detect-remote-changes (ssh-deploy-remote-changes-handler)) ))
;;
;; - To set key-bindings do something like this:
;;     (global-set-key (kbd "C-c C-z f") (lambda() (interactive)(ssh-deploy-upload-handler-forced) ))
;;     (global-set-key (kbd "C-c C-z u") (lambda() (interactive)(ssh-deploy-upload-handler) ))
;;     (global-set-key (kbd "C-c C-z D") (lambda() (interactive)(ssh-deploy-delete-handler) ))
;;     (global-set-key (kbd "C-c C-z d") (lambda() (interactive)(ssh-deploy-download-handler) ))
;;     (global-set-key (kbd "C-c C-z x") (lambda() (interactive)(ssh-deploy-diff-handler) ))
;;     (global-set-key (kbd "C-c C-z t") (lambda() (interactive)(ssh-deploy-remote-terminal-eshell-base-handler) ))
;;     (global-set-key (kbd "C-c C-z T") (lambda() (interactive)(ssh-deploy-remote-terminal-eshell-handler) ))
;;     (global-set-key (kbd "C-c C-z R") (lambda() (interactive)(ssh-deploy-rename-handler) ))
;;     (global-set-key (kbd "C-c C-z e") (lambda() (interactive)(ssh-deploy-remote-changes-handler) ))
;;     (global-set-key (kbd "C-c C-z b") (lambda() (interactive)(ssh-deploy-browse-remote-base-handler) ))
;;     (global-set-key (kbd "C-c C-z B") (lambda() (interactive)(ssh-deploy-browse-remote-handler) ))
;;
;; Here is an example for SSH deployment, /Users/Chris/Web/Site1/.dir.locals.el:
;; ((nil . (
;;   (ssh-deploy-root-local . "/Users/Chris/Web/Site1/")
;;   (ssh-deploy-root-remote . "/ssh:myuser@myserver.com:/var/www/site1/")
;;   (ssh-deploy-on-explicity-save . t)
;; )))
;;
;; Here is an example for FTP deployment, /Users/Chris/Web/Site2/.dir.locals.el:
;; ((nil . (
;;   (ssh-deploy-root-local . "/Users/Chris/Web/Site2/")
;;   (ssh-deploy-root-remote . "/ftp:myuser@myserver.com:/var/www/site2/")
;;   (ssh-deploy-on-explicit-save . nil)
;; )))
;;
;; Now when you are in a directory which is deployed via SSH or FTP you can access these features.
;;
;; Here is a list of other variables you can set globally or per directory:

;; * ssh-deploy-root-local - The local root that should be under deployment *(string)*
;; * ssh-deploy-root-remote - The remote root that should be under deployment, should follow a `/protocol:user@host:path` format *(string)*
;; * ssh-deploy-debug - Enables debugging messages *(boolean)*
;; * ssh-deploy-revision-folder - The folder used for storing local revisions *(string)*
;; * ssh-deploy-automatically-detect-remote-changes - Enables automatic detection of remote changes *(boolean)*
;; * ssh-deploy-on-explicit-save - Enabled automatic uploads on save *(boolean)*
;; * ssh-deploy-exclude-list - A list defining what paths to exclude from deployment *(list)*
;; * ssh-deploy-async - Enables asynchronous transfers (you need to have `async.el` installed as well) *(boolean)*
;;
;; Please see README.md from the same repository for documentation.

;;; Code:

(defgroup ssh-deploy nil
  "Upload, download, difference, browse and terminal handler for files and directories on remote hosts via SSH and FTP."
  :group 'tools
  :group 'convenience)

(defcustom ssh-deploy-root-local nil
  "String variable of local root, nil by default."
  :type 'string
  :group 'ssh-deploy)

(defcustom ssh-deploy-root-remote nil
  "String variable of remote root, nil by default."
  :type 'string
  :group 'ssh-deploy)

(defcustom ssh-deploy-on-explicit-save t
  "Boolean variable if deploy should be made on explicit save, t by default."
  :type 'boolean
  :group 'ssh-deploy)

(defcustom ssh-deploy-debug nil
  "Boolean variable if debug messages should be shown, nil by default."
  :type 'boolean
  :group 'ssh-deploy)

(defcustom ssh-deploy-async t
  "Boolean variable if asynchrous method for transfers should be used, t by default."
  :type 'boolean
  :group 'ssh-deploy)

(defcustom ssh-deploy-revision-folder "~/.ssh-deploy-revisions/"
  "String variable with path to revisions with trailing slash."
  :type 'string
  :group 'ssh-deploy)

(defcustom ssh-deploy-automatically-detect-remote-changes t
  "Detect remote changes and store base revisions automatically, t by default."
  :type 'boolean
  :group 'ssh-deploy)

(defcustom ssh-deploy-exclude-list '("/.git/" ".dir-locals.el")
  "List of strings that if found in paths will exclude paths from sync, '(\"/.git\"/' \".dir-locals.el\") by default."
  :type 'list
  :group 'ssh-deploy)


;; PRIVATE FUNCTIONS - the idea about these is that these functions should only be used by the plug-in internally.


(defun ssh-deploy--get-revision-path (path)
  "Generate revision-path for PATH."
  (if (not (file-exists-p ssh-deploy-revision-folder))
      (make-directory ssh-deploy-revision-folder))
  (concat ssh-deploy-revision-folder (replace-regexp-in-string "\\(/\\|@\\|:\\)" "_" path)))

(defun ssh-deploy--file-is-in-path (file path)
  "Return true if FILE is in the path PATH."
  (not (null (string-match path file))))

(defun ssh-deploy--file-is-included (path)
  "Return true if PATH is not in the exclusion list."
  (let ((not-found t))
    (dolist (element ssh-deploy-exclude-list)
      (if (and (not (null element))
               (not (null (string-match element path))))
          (progn
            (setq not-found nil))))
    not-found))

(defun ssh-deploy--get-relative-path (root path)
  "Return a string for the relative path based on ROOT and PATH."
  (replace-regexp-in-string root "" path))

(defun ssh-deploy--is-not-empty-string (string)
  "Return true if the STRING is not empty and not nil.  Expects string."
  (and (not (null string))
       (not (zerop (length string)))))

(defun ssh-deploy--upload-via-tramp-async (local-path remote-path force)
  "Upload LOCAL-PATH to REMOTE-PATH via TRAMP asynchronously and FORCE upload despite external change."
  (if (fboundp 'async-start)
      (progn
        (let ((file-or-directory (file-regular-p local-path)))
          (if file-or-directory
              (progn
                (let ((revision-path (ssh-deploy--get-revision-path local-path)))
                  (message "Uploading file '%s' to '%s' via TRAMP asynchronously.." local-path remote-path)
                  (async-start
                   `(lambda()
                      (require 'ediff)
                      (if (fboundp 'ediff-same-file-contents)
                          (progn
                            (if (or (eq t ,force) (not (file-exists-p ,remote-path)) (and (file-exists-p ,revision-path) (ediff-same-file-contents ,revision-path ,remote-path)))
                                (progn
                                  (if (not (file-directory-p (file-name-directory ,remote-path)))
                                      (make-directory (file-name-directory ,remote-path) t))
                                  (copy-file ,local-path ,remote-path t t t t)
                                  (copy-file ,local-path ,revision-path t t t t)
                                  (list 0 (format "Upload '%s' completed." ,remote-path)))
                              (list 1 (format "External file '%s' has changed, please download or diff." ,remote-path))))
                        (list 1 "Function ediff-same-file-contents is missing.")))
                   (lambda(return)
                     (if (= (nth 0 return) 0)
                         (message (nth 1 return))
                       (display-warning "ssh-deploy" (nth 1 return) :warning))))))
            (progn
              (message "Uploading directory '%s' to '%s' via TRAMP asynchronously.." local-path remote-path)
              (async-start
               `(lambda()
                  (copy-directory ,local-path ,remote-path t t t)
                  ,local-path)
               (lambda(return-path)
                 (message "Upload '%s' finished." return-path)))))))
    (message "async.el is not installed")))

(defun ssh-deploy--upload-via-tramp (local-path remote-path force)
  "Upload LOCAL-PATH to REMOTE-PATH via TRAMP synchronously and FORCE despite external change."
  (let ((file-or-directory (file-regular-p local-path)))
    (if file-or-directory
        (progn
          (if (or (boundp 'force) (not (ssh-deploy--remote-has-changed local-path remote-path)))
              (progn
                (message "Uploading file '%s' to '%s' via TRAMP synchronously.." local-path remote-path)
                (if (not (file-directory-p (file-name-directory remote-path)))
                    (make-directory (file-name-directory remote-path) t))
                (copy-file local-path remote-path t t t t)
                (message "Upload '%s' finished" local-path)
                (ssh-deploy-store-revision local-path))
            (display-warning "ssh-deploy" "Remote contents has changed or no base revision exists, please download or diff." :warning)))
      (progn
        (message "Uploading directory '%s' to '%s' via TRAMP synchronously.." local-path remote-path)
        (copy-directory local-path remote-path t t t)
        (message "Upload '%s' finished" local-path)))))

(defun ssh-deploy--download-via-tramp-async (remote-path local-path)
  "Download REMOTE-PATH to LOCAL-PATH via TRAMP asynchronously."
  (if (fboundp 'async-start)
      (progn
        (let ((file-or-directory (file-regular-p local-path)))
          (if file-or-directory
              (progn
                (message "Downloading file '%s' to '%s' via TRAMP asynchronously.." remote-path local-path)
                (async-start
                 `(lambda()
                    (copy-file ,remote-path ,local-path t t t t)
                    ,local-path)
                 (lambda(return-path)
                   (message "Download '%s' finished." return-path)
                   (ssh-deploy-store-revision return-path))))
            (progn
              (message "Downloading directory '%s' to '%s' via TRAMP synchronously.." remote-path local-path)
              (async-start
               `(lambda()
                  (copy-directory ,remote-path ,local-path t t t)
                  ,local-path)
               (lambda(return-path)
                 (message "Download '%s' finished." return-path)))))))
    (message "async.el is not installed")))

(defun ssh-deploy--download-via-tramp (remote-path local-path)
  "Download REMOTE-PATH to LOCAL-PATH via TRAMP synchronously."
  (let ((file-or-directory (file-regular-p local-path)))
    (if file-or-directory
        (progn
          (message "Downloading file '%s' to '%s' via TRAMP synchronously.." remote-path local-path)
          (copy-file remote-path local-path t t t t)
          (message "Download '%s' finished." local-path)
          (ssh-deploy-store-revision local-path))
      (progn
        (message "Downloading directory '%s' to '%s' via TRAMP synchronously.." remote-path local-path)
        (copy-directory remote-path local-path t t t)
        (message "Download '%s' finished." local-path)))))

(defun ssh-deploy--remote-has-changed (local remote)
  "Check if last stored revision of LOCAL exists or has changed on REMOTE synchronously."
  (let ((revision-path (ssh-deploy--get-revision-path local)))
    (if (file-exists-p remote)
        (progn
          (if (file-exists-p revision-path)
              (progn
                (require 'ediff)
                (if (fboundp 'ediff-same-file-contents)
                    (progn
                      (if (not (ediff-same-file-contents revision-path remote))
                          t
                        nil))
                  (progn
                    (message "Function ediff-same-file-contents is missing.")
                    nil)))
            t))
      nil)))


;; PUBLIC functions - the idea is that handlers use these to do things and people should be able to use these as they please themselves.


;;;### autoload
(defun ssh-deploy (local-root remote-root upload-or-download path debug async force)
  "Upload/Download file or directory relative to the roots LOCAL-ROOT with REMOTE-ROOT via SSH or FTP according to UPLOAD-OR-DOWNLOAD and the path PATH, DEBUG enables some feedback messages and ASYNC determines if transfers should be asynchrous or not, FORCE upload despite external change."
  (if (and (ssh-deploy--file-is-in-path path local-root)
           (ssh-deploy--file-is-included path))
      (progn
        (let ((file-or-directory (file-regular-p path)))
          (let ((local-path (concat local-root (ssh-deploy--get-relative-path local-root path)))
                (remote-path (concat remote-root (ssh-deploy--get-relative-path local-root path))))
            (if (not (null upload-or-download))
                (ssh-deploy-upload local-path remote-path async force)
              (ssh-deploy-download remote-path local-path async)))))
    (if debug
        (message "Path '%s' is not in the root '%s' or is excluded from it." path local-root))))

;;;### autoload
(defun ssh-deploy-remote-changes (local-root remote-root path async)
  "Check if a local revision exists on LOCAL-ROOT and if remote file has changed on REMOTE-ROOT for file PATH and do it optionally asynchronously if ASYNC is t."
  (if (and (ssh-deploy--file-is-in-path path local-root)
           (ssh-deploy--file-is-included path))
      (progn
        (let ((revision-path (ssh-deploy--get-revision-path path))
              (remote-path (concat remote-root (ssh-deploy--get-relative-path local-root path))))
          (if (file-regular-p path)
              (progn
                (if (file-exists-p revision-path)
                    (progn
                      (if (and async (fboundp 'async-start))
                          (progn
                            (async-start
                             `(lambda()
                                (if (file-exists-p ,remote-path)
                                    (progn
                                      (require 'ediff)
                                      (if (fboundp 'ediff-same-file-contents)
                                          (progn
                                            (if (ediff-same-file-contents ,revision-path ,remote-path)
                                                (list 0 (format "Remote file '%s' has not changed." ,remote-path))
                                              (progn
                                                (if (ediff-same-file-contents ,path ,remote-path)
                                                    (progn
                                                      (copy-file ,path ,revision-path t t t t)
                                                      (list 0 (format "External file '%s' is identical to local file '%s' but different to local revision. Updated local revision." ,remote-path ,path)))
                                                  (list 1 (format "External file '%s' has changed, please download or diff." ,remote-path))))))
                                        (list 1 "Function ediff-same-file-contents is missing.")))
                                  (list 0 (format "Remote file '%s' doesn't exist." ,remote-path))))
                             (lambda(return)
                               (if (= (nth 0 return) 0)
                                   (message (nth 1 return))
                                 (display-warning "ssh-deploy" (nth 1 return) :warning)))))
                        (progn
                          (if (file-exists-p remote-path)
                              (progn
                                (require 'ediff)
                                (if (fboundp 'ediff-same-file-contents)
                                    (progn
                                      (if (ediff-same-file-contents revision-path remote-path)
                                          (message "Remote file '%s' has not changed." remote-path)
                                        (display-warning "ssh-deploy" (format "External file '%s' has changed, please download or diff." remote-path) :warning)))
                                  (display-warning "ssh-deploy" "Function ediff-same-file-contents is missing." :warning)))
                            (message "Remote file '%s' doesn't exist." remote-path)))))
                  (progn
                    (if (and async (fboundp 'async-start))
                        (progn
                          (async-start
                           `(lambda()
                              (if (file-exists-p ,remote-path)
                                  (progn
                                    (require 'ediff)
                                    (if (fboundp 'ediff-same-file-contents)
                                        (progn
                                          (if (ediff-same-file-contents ,path ,remote-path)
                                              (progn
                                                (copy-file ,path ,revision-path t t t t)
                                                (list 0 (format "Remote file '%s' has not changed, created base revision." ,remote-path)))
                                            (list 1 (format "External file '%s' has changed, please download or diff." ,remote-path))))
                                      (list 1 "Function ediff-file-same-contents is missing")))
                                (list 0 (format "Remote file '%s' doesn't exist." ,remote-path))))
                           (lambda(return)
                             (if (= (nth 0 return) 0)
                                 (message (nth 1 return))
                               (display-warning "ssh-deploy" (nth 1 return) :warning)))))
                      (progn
                        (if (file-exists-p remote-path)
                            (progn
                              (require 'ediff)
                              (if (fboundp 'ediff-same-file-contents)
                                  (progn
                                    (if (ediff-same-file-contents path remote-path)
                                        (progn
                                          (copy-file path revision-path t t t t)
                                          (message "Remote file '%s' has not changed, created base revision." remote-path))
                                      (display-warning "ssh-deploy" (format "External file '%s' has changed, please download or diff." remote-path) :warning)))
                                (display-warning "ssh-deploy" "Function ediff-same-file-contents is missing." :warning)))
                          (message "Remote file '%s' doesn't exist." remote-path))))))))))))

;;;### autoload
(defun ssh-deploy-delete (local-path local-root remote-root async debug)
  "Delete LOCAL-PATH relative to LOCAL-ROOT as well as on REMOTE-ROOT, do it asynchronously if ASYNC is non-nil, debug if DEBUG is non-nil."
  (if (and (ssh-deploy--file-is-in-path local-path local-root)
           (ssh-deploy--file-is-included local-path))
      (progn
        (let ((file-or-directory (file-regular-p local-path)))
          (let ((remote-path (concat remote-root (ssh-deploy--get-relative-path local-root local-path))))
            (if (file-regular-p local-path)
                (progn
                  (delete-file local-path t)
                  (message "Deleted file '%s'" local-path))
              (progn
                (delete-directory local-path t t)
                (message "Deleted directory '%s'" local-path)))
            (kill-this-buffer)
            (if (and async (fboundp 'async-start))
                (progn
                  (async-start
                   `(lambda()
                      (if (file-regular-p ,remote-path)
                          (delete-file ,remote-path t)
                        (delete-directory ,remote-path t t))
                      (list ,remote-path))
                   (lambda(files)
                     (message "Asynchronously deleted '%s'." (nth 0 files)))))
              (progn
                (if (file-regular-p remote-path)
                    (delete-file remote-path t)
                  (delete-directory remote-path t t))
                (message "Synchronously deleted '%s'." remote-path))))))
    (if debug
        (message "Path '%s' is not in the root '%s' or is excluded from it." local-path local-root))))

;;;### autoload
(defun ssh-deploy-rename (old-path new-path local-root remote-root async debug)
  "Rename OLD-PATH to NEW-PATH relative to LOCAL-ROOT as well as on REMOTE-ROOT, do it asynchronously if ASYNC is non-nil, debug if DEBUG is non-nil."
  (if (and (ssh-deploy--file-is-in-path old-path local-root)
           (ssh-deploy--file-is-in-path new-path local-root)
           (ssh-deploy--file-is-included old-path)
           (ssh-deploy--file-is-included new-path))
      (progn
        (let ((file-or-directory (file-regular-p old-path)))
          (let ((old-remote-path (concat remote-root (ssh-deploy--get-relative-path local-root old-path)))
                (new-remote-path (concat remote-root (ssh-deploy--get-relative-path local-root new-path))))
            (rename-file old-path new-path t)
            (if (file-regular-p new-path)
                (progn
                  (rename-buffer new-path)
                  (set-buffer-modified-p nil)
                  (set-visited-file-name new-path))
              (dired new-path))
            (message "Renamed '%s' -> '%s'." old-path new-path)
            (if (and async (fboundp 'async-start))
                (progn
                  (async-start
                   `(lambda()
                      (rename-file ,old-remote-path ,new-remote-path t)
                      (list ,old-remote-path ,new-remote-path))
                   (lambda(files)
                     (message "Asynchronously renamed '%s' -> '%s'." (nth 0 files) (nth 1 files)))))
              (progn
                (rename-file old-remote-path new-remote-path t)
                (message "Synchronously renamed '%s' -> '%s'." old-remote-path new-remote-path))))))
    (if debug
        (message "Path '%s' or '%s' is not in the root '%s' or is excluded from it." old-path new-path local-root))))

;;;### autoload
(defun ssh-deploy-browse-remote (local-root remote-root-string path)
  "Browse relative to LOCAL-ROOT on REMOTE-ROOT-STRING the path PATH in `dired-mode'."
  (if (and (ssh-deploy--file-is-in-path path local-root)
           (ssh-deploy--file-is-included path))
      (let ((remote-path (concat remote-root-string (ssh-deploy--get-relative-path local-root path))))
        (message "Opening '%s' for browsing on remote host.." remote-path)
        (dired remote-path))))

;;;### autoload
(defun ssh-deploy-remote-terminal-eshell (local-root remote-root-string path)
  "Browse relative to LOCAL-ROOT on REMOTE-ROOT-STRING the path PATH in `eshell-mode'."
  (if (and (ssh-deploy--file-is-in-path path local-root)
           (ssh-deploy--file-is-included path))
      (let ((remote-path (concat remote-root-string (ssh-deploy--get-relative-path local-root path))))
        (let ((old-directory default-directory))
          (require 'eshell)
          (if (and (fboundp 'eshell-kill-input)
                   (fboundp 'eshell-send-input))
              (progn
                (message "Opening eshell on '%s'.." remote-path)
                (defvar eshell-buffer-name)
                (let ((old-eshell-buffer-name eshell-buffer-name))
                  (setq eshell-buffer-name remote-path)
                  (let ((eshell-buffer (eshell)))
                    (goto-char (point-max))
                    (eshell-kill-input)
                    (insert (concat "cd " remote-path))
                    (eshell-send-input)
                    (goto-char (point-max))
                    (setq eshell-buffer-name old-eshell-buffer-name))))
            (message "Missing required eshell functions"))))))

;;;### autoload
(defun ssh-deploy-store-revision (path)
  "Store PATH in revision-folder."
  (let ((revision-path (ssh-deploy--get-revision-path path)))
    (message "Storing revision of '%s' at '%s'.." path revision-path)
    (copy-file path (ssh-deploy--get-revision-path path) t t t t)))

;;;### autoload
(defun ssh-deploy-diff (local-root remote-root-string path &optional debug)
  "Find differences relative to the roots LOCAL-ROOT with REMOTE-ROOT-STRING and the path PATH, DEBUG enables feedback message."
  (let ((file-or-directory (file-regular-p path)))
    (if (and (ssh-deploy--file-is-in-path path local-root)
             (ssh-deploy--file-is-included path))
        (progn
          (let ((remote-path (concat remote-root-string (ssh-deploy--get-relative-path local-root path))))
            (if file-or-directory
                (progn
                  (require 'ediff)
                  (if (fboundp 'ediff-same-file-contents)
                      (progn
                        (message "Comparing file '%s' to '%s'.." path remote-path)
                        (if (ediff-same-file-contents path remote-path)
                            (message "Files have identical contents.")
                          (ediff path remote-path))
                        (message "Function ediff-same-file-contents is missing."))))
              (progn
                (message "Unfortunately directory differences are not yet implemented."))))))
    (if debug
        (message "Path '%s' is not in the root '%s' or is excluded from it." path local-root))))

;;;### autoload
(defun ssh-deploy-upload (local-path remote-path async force)
  "Upload LOCAL-PATH to REMOTE-PATH and LOCAL-ROOT via TRAMP, ASYNC determines if transfer should be asynchronously or not, FORCE uploads despite external change."
  (if (and async (fboundp 'async-start))
      (ssh-deploy--upload-via-tramp-async local-path remote-path force)
    (ssh-deploy--upload-via-tramp local-path remote-path force)))

;;;### autoload
(defun ssh-deploy-download (remote-path local-path async)
  "Download REMOTE-PATH to LOCAL-PATH via TRAMP, ASYNC determines if transfer should be asynchrous or not."
  (if (and async (fboundp 'async-start))
      (ssh-deploy--download-via-tramp-async remote-path local-path)
    (ssh-deploy--download-via-tramp remote-path local-path)))


;; HANDLERS - the idea is that these are interactive functions and can be bound to various Emacs commands.


;;;### autoload
(defun ssh-deploy-upload-handler ()
  "Upload current path to remote host if it is configured for SSH deployment."
  (interactive)
  (if (and (ssh-deploy--is-not-empty-string ssh-deploy-root-local)
           (ssh-deploy--is-not-empty-string ssh-deploy-root-remote))
      (if (and (ssh-deploy--is-not-empty-string buffer-file-name)
               (file-exists-p buffer-file-name))
          (let ((local-path (file-truename buffer-file-name))
                (local-root (file-truename ssh-deploy-root-local)))
            (ssh-deploy local-root ssh-deploy-root-remote t local-path ssh-deploy-debug ssh-deploy-async nil))
        (if (ssh-deploy--is-not-empty-string default-directory)
            (let ((local-path (file-truename default-directory))
                  (local-root (file-truename ssh-deploy-root-local)))
              (ssh-deploy local-root ssh-deploy-root-remote t local-path ssh-deploy-debug ssh-deploy-async nil))))))

;;;### autoload
(defun ssh-deploy-upload-handler-forced ()
  "Upload current path to remote host if it is configured for SSH deployment."
  (interactive)
  (if (and (ssh-deploy--is-not-empty-string ssh-deploy-root-local)
           (ssh-deploy--is-not-empty-string ssh-deploy-root-remote))
      (if (and (ssh-deploy--is-not-empty-string buffer-file-name)
               (file-exists-p buffer-file-name))
          (let ((local-path (file-truename buffer-file-name))
                (local-root (file-truename ssh-deploy-root-local)))
            (ssh-deploy local-root ssh-deploy-root-remote t local-path ssh-deploy-debug ssh-deploy-async t))
        (if (ssh-deploy--is-not-empty-string default-directory)
            (let ((local-path (file-truename default-directory))
                  (local-root (file-truename ssh-deploy-root-local)))
              (ssh-deploy local-root ssh-deploy-root-remote t local-path ssh-deploy-debug ssh-deploy-async t))))))

;;;### autoload
(defun ssh-deploy-remote-changes-handler()
  "Check if local revision exists or remote file has changed if path is configured for deployment"
  (interactive)
  (if (and (ssh-deploy--is-not-empty-string ssh-deploy-root-local)
           (ssh-deploy--is-not-empty-string ssh-deploy-root-remote))
      (if (and (ssh-deploy--is-not-empty-string buffer-file-name))
          (ssh-deploy-remote-changes (file-truename ssh-deploy-root-local) ssh-deploy-root-remote (file-truename buffer-file-name) ssh-deploy-async))))

;;;### autoload
(defun ssh-deploy-download-handler ()
  "Download current path from remote host if it is configured for deployment."
  (interactive)
  (if (and (ssh-deploy--is-not-empty-string ssh-deploy-root-local)
           (ssh-deploy--is-not-empty-string ssh-deploy-root-remote))
      (if (and (ssh-deploy--is-not-empty-string buffer-file-name)
               (file-exists-p buffer-file-name))
          (let ((local-path (file-truename buffer-file-name))
                (local-root (file-truename ssh-deploy-root-local)))
            (ssh-deploy local-root ssh-deploy-root-remote nil local-path ssh-deploy-debug ssh-deploy-async nil))
        (if (and (ssh-deploy--is-not-empty-string default-directory)
                 (file-exists-p default-directory))
            (let ((local-path (file-truename default-directory))
                  (local-root (file-truename ssh-deploy-root-local)))
              (ssh-deploy local-root ssh-deploy-root-remote nil local-path ssh-deploy-debug ssh-deploy-async nil))))))

;;;### autoload
(defun ssh-deploy-diff-handler ()
  "Compare current path with remote host if it is configured for deployment."
  (interactive)
  (if (and (ssh-deploy--is-not-empty-string ssh-deploy-root-local)
           (ssh-deploy--is-not-empty-string ssh-deploy-root-remote))
      (if (and (ssh-deploy--is-not-empty-string buffer-file-name)
               (file-exists-p buffer-file-name))
          (let ((local-path (file-truename buffer-file-name))
                (local-root (file-truename ssh-deploy-root-local)))
            (ssh-deploy-diff local-root ssh-deploy-root-remote local-path ssh-deploy-debug))
        (if (and (ssh-deploy--is-not-empty-string default-directory)
                 (file-exists-p default-directory))
            (let ((local-path (file-truename default-directory))
                  (local-root (file-truename ssh-deploy-root-local)))
              (ssh-deploy-diff local-root ssh-deploy-root-remote local-path ssh-deploy-debug))))))

;;;### autoload
(defun ssh-deploy-delete-handler ()
  "Delete current file or directory."
  (interactive)
  (if (and (ssh-deploy--is-not-empty-string ssh-deploy-root-local)
           (ssh-deploy--is-not-empty-string ssh-deploy-root-remote))
      (if (and (ssh-deploy--is-not-empty-string buffer-file-name)
               (file-exists-p buffer-file-name))
          (let* ((local-path (file-truename buffer-file-name))
                 (local-root (file-truename ssh-deploy-root-local))
                 (yes-no-prompt (read-string (format "Type 'yes' to confirm that you want to delete the file '%s': " local-path))))
            (if (string= yes-no-prompt "yes")
                (ssh-deploy-delete local-path local-root ssh-deploy-root-remote ssh-deploy-async ssh-deploy-debug)))
        (if (and (ssh-deploy--is-not-empty-string default-directory)
                 (file-exists-p default-directory))
            (let* ((local-path (file-truename default-directory))
                   (local-root (file-truename ssh-deploy-root-local))
                   (yes-no-prompt (read-string (format "Type 'yes' to confirm that you want to delete the directory '%s': " local-path))))
              (if (string= yes-no-prompt "yes")
                  (ssh-deploy-delete local-path local-root ssh-deploy-root-remote ssh-deploy-async ssh-deploy-debug)))))))

;;;### autoload
(defun ssh-deploy-rename-handler ()
  "Rename current file or directory."
  (interactive)
  (if (and (ssh-deploy--is-not-empty-string ssh-deploy-root-local)
           (ssh-deploy--is-not-empty-string ssh-deploy-root-remote))
      (if (and (ssh-deploy--is-not-empty-string buffer-file-name)
               (file-exists-p buffer-file-name))
          (let* ((old-local-path (file-truename buffer-file-name))
                 (local-root (file-truename ssh-deploy-root-local))
                 (basename (file-name-nondirectory old-local-path))
                 (new-local-path-tmp (read-file-name "New file name:" (file-name-directory old-local-path) basename nil basename))
                 (new-local-path (file-truename new-local-path-tmp)))
            (if (not (string= old-local-path new-local-path))
                (ssh-deploy-rename old-local-path new-local-path local-root ssh-deploy-root-remote ssh-deploy-async ssh-deploy-debug)))
        (if (and (ssh-deploy--is-not-empty-string default-directory)
                 (file-exists-p default-directory))
            (let* ((old-local-path (file-truename default-directory))
                   (local-root (file-truename ssh-deploy-root-local))
                   (basename (file-name-nondirectory old-local-path))
                   (new-local-path-tmp (read-file-name "New directory name:" (file-name-directory old-local-path) basename nil basename))
                   (new-local-path (file-truename new-local-path-tmp)))
              (if (not (string= old-local-path new-local-path))
                  (ssh-deploy-rename old-local-path new-local-path local-root ssh-deploy-root-remote ssh-deploy-async ssh-deploy-debug)))))))

;;;### autoload
(defun ssh-deploy-remote-terminal-eshell-handler ()
  "Open current relative path on remote host in `eshell' but only if it's configured for deployment."
  (interactive)
  (if (and (ssh-deploy--is-not-empty-string ssh-deploy-root-local)
           (ssh-deploy--is-not-empty-string ssh-deploy-root-remote)
           (ssh-deploy--is-not-empty-string default-directory))
      (let ((local-path (file-truename default-directory))
            (local-root (file-truename ssh-deploy-root-local)))
        (ssh-deploy-remote-terminal-eshell local-root ssh-deploy-root-remote local-path))))

;;;### autoload
(defun ssh-deploy-remote-terminal-eshell-base-handler ()
  "Open base path on remote host in `eshell' but only if it's configured for deployment."
  (interactive)
  (if (and (ssh-deploy--is-not-empty-string ssh-deploy-root-local)
           (ssh-deploy--is-not-empty-string ssh-deploy-root-remote))
      (let ((local-root (file-truename ssh-deploy-root-local)))
        (ssh-deploy-remote-terminal-eshell local-root ssh-deploy-root-remote local-root))))

;;;### autoload
(defun ssh-deploy-browse-remote-handler ()
  "Open current relative path on remote host in `dired-mode' if it is configured for deployment."
  (interactive)
  (if (and (ssh-deploy--is-not-empty-string ssh-deploy-root-local)
           (ssh-deploy--is-not-empty-string ssh-deploy-root-remote)
           (ssh-deploy--is-not-empty-string default-directory))
      (let ((local-path (file-truename default-directory))
            (local-root (file-truename ssh-deploy-root-local)))
        (ssh-deploy-browse-remote local-root ssh-deploy-root-remote local-path))))

;;;### autoload
(defun ssh-deploy-browse-remote-base-handler ()
  "Open base path on remote host in `dired-mode' if it is configured for deployment."
  (interactive)
  (if (and (ssh-deploy--is-not-empty-string ssh-deploy-root-local)
           (ssh-deploy--is-not-empty-string ssh-deploy-root-remote))
      (let ((local-root (file-truename ssh-deploy-root-local)))
        (ssh-deploy-browse-remote local-root ssh-deploy-root-remote local-root))))


;; Mark variables as safe
(put 'ssh-deploy-root-local 'safe-local-variable 'stringp)
(put 'ssh-deploy-root-remote 'safe-local-variable 'stringp)
(put 'ssh-deploy-debug 'safe-local-variable 'booleanp)
(put 'ssh-deploy-revision-folder 'safe-local-variable 'stringp)
(put 'ssh-deploy-automatically-detect-remote-changes 'safe-local-variable 'booleanp)
(put 'ssh-deploy-on-explicit-save 'safe-local-variable 'booleanp)
(put 'ssh-deploy-exclude-list 'safe-local-variable 'listp)
(put 'ssh-deploy-async 'safe-local-variable 'booleanp)

(provide 'ssh-deploy)
;;; ssh-deploy.el ends here

