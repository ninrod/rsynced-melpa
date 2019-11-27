;;; side-notes.el --- Easy access to a directory notes file  -*- lexical-binding: t; -*-

;; Copyright (c) 2019 Paul W. Rankin

;; Author: Paul W. Rankin <hello@paulwrankin.com>
;; Keywords: convenience
;; Package-Version: 20190903.818
;; Version: 0.2.1
;; Package-Requires: ((emacs "24.5"))
;; URL: https://github.com/rnkn/side-notes

;; This file is not part of GNU Emacs.

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or (at
;; your option) any later version.

;; This program is distributed in the hope that it will be useful, but
;; WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU
;; General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program. If not, see <https://www.gnu.org/licenses/>.

;;; Commentary:

;; # Side Notes #

;; Quickly display your quick side notes in quick side window.

;; Side notes live in a file in the current directory or any parent
;; directory thereof. The filename to look for is defined by custom option
;; side-notes-file, which defaults to "notes.txt".

;; For more info, see (info "(elisp) Side Windows")

;; ## Installation ##

;; Add something like the following to your init file:

;; (define-key (current-global-map) (kbd "M-s n") #'side-notes-toggle-notes)


;;; Code:

(defgroup side-notes ()
  "Display a notes file."
  :group 'convenience)

(defcustom side-notes-hook
  nil
  "Hook run after showing notes buffer."
  :type 'hook
  :group 'side-notes)

(defcustom side-notes-file
  "notes.txt"
  "Name of the notes file to find.

This file lives in the current directory or any parent directory
thereof, which allows you to keep a notes file in the top level
of a multi-directory project.

If you would like to use a file-specific notes file, specify a
string with `add-file-local-variable'. Likewise you can specify a
directory-specific notes file with `add-dir-local-variable'."
  :type 'string
  :safe 'stringp
  :group 'side-notes)
(make-variable-buffer-local 'side-notes-file)

(defcustom side-notes-select-window
  t
  "If non-nil, switch to notes window upon displaying it."
  :type 'boolean
  :safe 'booleanp
  :group 'side-notes)

(defcustom side-notes-display-alist
  '((side . right)
    (window-width . 35)
    (slot . 0))
  "Alist used to display notes buffer.

See `display-buffer-in-side-window' for example options."
  :type 'alist
  :group 'side-notes)

(defface side-notes
  '((t nil))
  "Default face for notes buffer."
  :group 'side-notes)

(defvar-local side-notes-buffer-identify
  nil
  "Buffer local variable to identify a notes buffer.")

(defun side-notes-locate-notes ()
  "Look up directory hierachy for file `side-notes-file'.

Return nil if no notes file found."
  (expand-file-name
   side-notes-file (locate-dominating-file default-directory side-notes-file)))

;;;###autoload
(defun side-notes-toggle-notes ()
  "Pop up a side window containing the notes file.

See `side-notes-display-alist' for options concerning displaying
the notes buffer."
  (interactive)
  (if side-notes-buffer-identify
      (quit-window)
    (let ((display-buffer-mark-dedicated t)
          (buffer (find-file-noselect (side-notes-locate-notes))))
      (if (get-buffer-window buffer (selected-frame))
          (delete-windows-on buffer (selected-frame))
        (display-buffer-in-side-window buffer side-notes-display-alist)
        (with-current-buffer buffer
          (setq side-notes-buffer-identify t)
          (face-remap-add-relative 'default 'side-notes)
          (run-hooks 'side-notes-hook))
        (if side-notes-select-window
            (select-window (get-buffer-window buffer (selected-frame))))
        (message "Showing `%s'; %s to hide" buffer
                 (key-description (where-is-internal this-command
                                                     overriding-local-map t)))))))

(provide 'side-notes)
;;; side-notes.el ends here
