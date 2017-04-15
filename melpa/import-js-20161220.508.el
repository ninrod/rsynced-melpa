;;; import-js.el --- Import Javascript dependencies -*- lexical-binding: t; -*-
;; Copyright (C) 2015 Henric Trotzig and Kevin Kehl
;;
;; Author: Kevin Kehl <kevin.kehl@gmail.com>
;; URL: http://github.com/Galooshi/emacs-import-js/
;; Package-Version: 20161220.508
;; Package-Requires: ((grizzl "0.1.0") (emacs "24"))
;; Version: 1.0.0
;; Keywords: javascript

;; This file is not part of GNU Emacs.

;;; License:

;; Licensed under the MIT license, see:
;; http://github.com/Galooshi/emacs-import-js/blob/master/LICENSE

;;; Commentary:

;; Quick start:
;; run-import-js
;;
;; Bind the following commands:
;; import-js-import
;; import-js-goto
;;
;; For a detailed introduction see:
;; http://github.com/Galooshi/emacs-import-js/blob/master/README.md

;;; Code:

(require 'json)

(eval-when-compile
  (require 'grizzl))

(defvar import-js-buffer nil "Current import-js process buffer")
(defvar import-buffer nil "The current buffer under operation")

(defvar import-js-current-project-root nil "Current project root")

(defun import-js-send-input (&rest opts)
  (let ((path buffer-file-name)
        (temp-buffer (generate-new-buffer "import-js"))
        (old-default-dir default-directory))
    (setq default-directory (setq import-js-current-project-root (import-js-locate-project-root path)))
    (apply 'call-process `("importjs"
                           ,path
                           ,temp-buffer
                           nil
                           ,@opts
                           ,path))
    (setq default-directory old-default-dir)
    (let ((out (with-current-buffer temp-buffer (buffer-string))))
      (kill-buffer temp-buffer)
      out)))

(defun import-js-locate-project-root (path)
  "Find the dir containing package.json by walking up the dir tree from path"
  (let ((parent-dir (file-name-directory path))
        (project-found nil))
    (while (and parent-dir (not (setf project-found (file-exists-p (concat parent-dir "package.json")))))
      (let* ((pd (file-name-directory (directory-file-name parent-dir)))
             (pd-exists (not (equal pd parent-dir))))
        (setf parent-dir (if pd-exists pd nil))))
    (if project-found parent-dir ".")))

(defun import-js-word-at-point ()
  (save-excursion
    (skip-chars-backward "A-Za-z0-9:_")
    (let ((beg (point)) module)
      (skip-chars-forward "A-Za-z0-9:_")
      (setq module (buffer-substring-no-properties beg (point)))
      module)))

(defun import-js-write-content (import-data)
  (let ((file-content (cdr (assoc 'fileContent import-data))))
    (write-region file-content nil buffer-file-name))
  (revert-buffer t t t))

(defun import-js-add (add-alist)
  "Resolves an import with multiple matches"
  (let ((json-data (json-encode-alist add-alist)))
    (let ((import-data (json-read-from-string
                        (import-js-send-input "add" json-data))))
      (import-js-handle-imports import-data))))

(defun import-js-handle-unresolved (unresolved word)
  (let ((paths (mapcar
                (lambda (car)
                  (cdr (assoc 'importPath car)))
                (cdr (assoc-string word unresolved)))))
    (minibuffer-with-setup-hook
        (lambda () (make-sparse-keymap))
      (grizzl-completing-read (format "Unresolved import (%s)" word)
                              (grizzl-make-index
                               paths
                               'files
                               import-js-current-project-root
                               nil)))))

(defun import-js-handle-imports (import-data)
  "Check to see if import is unresolved. If resolved, write file. Else, prompt the user to select"
  (let ((unresolved (cdr (assoc 'unresolvedImports import-data))))
    (if unresolved
        (import-js-add (mapcar
                        (lambda (word)
                          (let ((key (car word)))
                            (cons key (import-js-handle-unresolved unresolved key))))
                        unresolved))
      (import-js-write-content import-data))))

;;;###autoload
(defun import-js-import ()
  (interactive)
  (save-some-buffers)
  (import-js-handle-imports (json-read-from-string
                             (import-js-send-input "word" (import-js-word-at-point)))))

;;;###autoload
(defun import-js-fix ()
  (interactive)
  (save-some-buffers)
  (import-js-handle-imports (json-read-from-string
                             (import-js-send-input "fix"))))

;;;###autoload
(defun import-js-goto ()
  (interactive)
  (let ((goto-list (json-read-from-string
                    (import-js-send-input "goto" (import-js-word-at-point)))))
    (find-file (expand-file-name (cdr (assoc 'goto goto-list)) import-js-current-project-root))))

(provide 'import-js)
;;; import-js.el ends here
