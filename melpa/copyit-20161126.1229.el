;;; copyit.el --- Copy it, yank anything! -*- mode: lexical-binding: t -*-

;; Copyright (C) 2016 USAMI Kenta

;; Author: USAMI Kenta <tadsan@zonu.me>
;; Created: 6 Jun 2016
;; Version: 0.0.1
;; Package-Version: 20161126.1229
;; Keywords: convenience yank clipboard
;; Homepage: https://github.com/zonuexe/emacs-copyit
;; Package-Requires: ((emacs "24") (cl-lib "0.5") (s "1.9.0"))

;; This file is NOT part of GNU Emacs.

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

;; “Copy” is known as “Yank” in Emacs.
;;
;; ** Functions
;; - copyit-variable
;; - copyit-file-pathname
;; - copyit-file-content
;; - copyit-file-exif-information
;; - copyit-file-as-data-uri
;; - copyit-ssh
;;
;; ** Customize
;; - copyit-binary-file-copy-method
;; - copyit-ssh-directory-path
;; - copyit-copy-bare-string

;;; Code:

(require 'cl-lib)
(require 's)

(defgroup copyit nil
  "Copy it!"
  :group 'convenience)

(defcustom copyit-binary-file-copy-method 'data-uri
  "Default copy method for binary file."
  :type '(choice (const :tag "Data URI" 'data-uri)
                 (const :tag "Exif"     'exif)
                 (const :tag "Base64"   'base64)
                 (function-item)))

(defcustom copyit-ssh-directory-path "~/.ssh/"
  "Directory path string for SSH.")

(defcustom copyit-copy-bare-string t
  "Copy non-quoted string value if T when interactively called.")

(defun copyit--copy-binary-file (buffer)
  "Copy binary file content by `BUFFER'."
  (if (fboundp copyit-binary-file-copy-method)
      (funcall copyit-binary-file-copy-method buffer)
    (cl-case copyit-binary-file-copy-method
      ('data-uri (copyit--get-file-as-data-uri buffer))
      ('exif     (copyit--get-file-as-exif-info buffer))
      ('base64   (copyit--get-file-as-base64 buffer))
      (:else     (error "`%s' is unexpected method" copyit-binary-file-copy-method)))))

(defun copyit--get-file-as-data-uri (buffer)
  "Get Data URI format by `BUFFER'."
  (concat "data:"
          (copyit--get-mime-type buffer)
          ";base64,"
          (copyit--get-file-as-base64 buffer)))

(defun copyit--get-file-as-base64 (buffer)
  "Get Base64 encoded content by `BUFFER'."
  (with-current-buffer buffer
    (base64-encode-string (buffer-substring-no-properties (point-min) (point-max)))))

(defun copyit--get-file-as-exif-info (file-path-or-buffer)
  "Get Exif informations by `FILE-PATH-OR-BUFFER'."
  (unless (executable-find "identify")
    (error "`identify' command not exists"))
  (with-temp-buffer
    (let ((buf (current-buffer)))
      (with-current-buffer (copyit--get-buffer file-path-or-buffer)
        (call-process-region (point-min) (point-max)
                             "identify" nil buf nil "-verbose" "--" "-"))
      (buffer-substring-no-properties (point-min) (point-max)))))

(defun copyit--get-buffer (file-path-or-buffer)
  "Return buffer by `FILE-PATH-OR-BUFFER'."
  (if (bufferp file-path-or-buffer)
      file-path-or-buffer
    (find-file-noselect file-path-or-buffer)))

(defun copyit--get-mime-type (file-path-or-buffer)
  "Get MIME content type by `FILE-PATH-OR-BUFFER'."
  ;; require `file' command.
  (unless (executable-find "file")
    (error "`file' command not exists"))
  (with-temp-buffer
    (let ((buf (current-buffer)))
      (with-current-buffer (copyit--get-buffer file-path-or-buffer)
        (call-process-region (point-min) (point-max)
                             "file" nil buf nil "-b" "--mime-type" "--" "-"))
      (goto-char (point-min))
      (search-forward "\n")
      (replace-match  "")
      (buffer-substring-no-properties (point-min) (point-max)))))

(defun copyit--pp-string (value bare-string)
  "Get pretty-printed string VALUE.
Return non-quoted string VALUE if `BARE-STRING' is non-NIL."
  (if (and bare-string (stringp value))
      value
    (s-trim-right (pp-to-string (if (listp value) `(quote ,value) value)))))

;;;###autoload
(defun copyit-variable (symbol &optional flip-bare-string)
  "Copy pretty-printed value `SYMBOL's variable.
Copy quoted string if `FLIP-BARE-STRING' is non-NIL."
  (interactive
   (list (cl-letf (((symbol-function 'custom-variable-p) #'boundp))
           (read-variable "Variable: "))
         (not (and copyit-copy-bare-string current-prefix-arg))))
  (kill-new (copyit--pp-string (symbol-value symbol) flip-bare-string)))

;;;###autoload
(defun copyit-file-pathname (file-path)
  "Copy `FILE-PATH'."
  (interactive "F")
  (kill-new file-path))

;;;###autoload
(defun copyit-file-content (file-path)
  "Copy `FILE-PATH' content."
  (interactive "F")
  (kill-new
   (with-current-buffer (copyit--get-buffer file-path)
     (if (eq 'no-conversion buffer-file-coding-system)
         (copyit--copy-binary-file (current-buffer))
       (buffer-substring-no-properties (point-min) (point-max))))))

;;;###autoload
(defun copyit-file-exif-information (file-path)
  "Copy exif-information by `FILE-PATH'."
  (interactive "F")
  (kill-new (copyit--get-file-as-exif-info file-path)))

;;;###autoload
(defun copyit-file-as-data-uri (file-path)
  "Copy `FILE-PATH' content as Data URI format."
  (interactive "F")
  (kill-new (copyit--get-file-as-data-uri file-path)))

;;;###autoload
(defun copyit-ssh ()
  "Copy ssh file."
  (interactive)
  (let ((default-directory copyit-ssh-directory-path))
    (call-interactively 'copyit-file-content)))

(provide 'copyit)
;;; copyit.el ends here
