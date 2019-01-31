;;; fwb-cmds.el --- misc frame, window and buffer commands  -*- lexical-binding: t -*-

;; Copyright (C) 2008-2018  Jonas Bernoulli

;; Author: Jonas Bernoulli <jonas@bernoul.li>
;; Homepage: https://github.com/tarsius/fwb-cmds
;; Keywords: convenience
;; Package-Version: 20180318.2219

;; This file is not part of GNU Emacs.

;; This file is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation; either version 3, or (at your option)
;; any later version.

;; This file is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <http://www.gnu.org/licenses/>.

;;; Commentary:

;; Commands defined here operate on frames, windows and buffers and
;; make it easier and faster to access certain functionality that
;; is already available using the builtin commands.

;;  ***** NOTE: The following EMACS PRIMITIVES have been REDEFINED HERE:
;;  `delete-window' If there is only one window in frame, then
;;                  delete whole frame using `delete-frame'.
;;
;;  ***** NOTE: The symbols defined here do not have a proper package
;;              prefix.

;; Inspired by Drew Adams' `frame-cmds.el', `misc-cmds.el' and
;; `find-func+.el'.

;;; Code:

(require 'find-func)

(or (fboundp 'old-delete-window)
    (fset 'old-delete-window (symbol-function 'delete-window)))

;; REPLACES ORIGINAL (built-in):
;; If WINDOW is the only one in its frame, `delete-frame'.
;;;###autoload
(defun delete-window (&optional window)
  "Remove WINDOW from the display.  Default is `selected-window'.
If WINDOW is the only one in its frame, then `delete-frame' too."
  (interactive)
  (save-current-buffer
    (if window
        (select-window window)
      (setq window (selected-window)))
    (if (one-window-p t)
        (delete-frame)
      (with-no-warnings
        (old-delete-window (selected-window))))))

;;;###autoload
(defun kill-this-buffer-and-its-window ()
  "Kill the current buffer and delete its window.
When called in the minibuffer, get out of the minibuffer
using `abort-recursive-edit'."
  (interactive)
  (if (menu-bar-non-minibuffer-window-p)
      (let ((buffer (current-buffer)))
        (delete-window (selected-window))
        (kill-buffer buffer))
    (abort-recursive-edit)))

;;;###autoload
(defun kill-other-buffers-and-their-window ()
  "Kill non-current buffers in the selected frame and delete their window.
Only buffers are considered that have a window in the current frame."
  (interactive)
  (dolist (window (window-list nil :exclude-minibuffer))
    (unless (equal window (selected-window))
      (kill-buffer (window-buffer window))
      (with-no-warnings
        (old-delete-window window)))))

;;;###autoload
(defun replace-current-window-with-frame ()
  "Delete window but show buffer in a newly created frame."
  (interactive)
  (let ((window (selected-window)))
    (switch-to-buffer-other-frame (current-buffer))
    (with-no-warnings
      (old-delete-window window))))

;;;###autoload
(defun switch-to-current-buffer-other-frame ()
  "Create new frame with the current buffer."
  (interactive)
  (switch-to-buffer-other-frame (current-buffer)))

;;;###autoload
(defun toggle-window-split ()
  "Toggle between vertical and horizontal split."
  ;; Source: https://www.emacswiki.org/emacs/ToggleWindowSplit.
  ;; Author: Jeff Dwork
  (interactive)
  (if (= (count-windows) 2)
      (let* ((this-win-buffer (window-buffer))
             (next-win-buffer (window-buffer (next-window)))
             (this-win-edges (window-edges (selected-window)))
             (next-win-edges (window-edges (next-window)))
             (this-win-2nd (not (and (<= (car this-win-edges)
                                         (car next-win-edges))
                                     (<= (cadr this-win-edges)
                                         (cadr next-win-edges)))))
             (splitter
              (if (= (car this-win-edges)
                     (car (window-edges (next-window))))
                  'split-window-horizontally
                'split-window-vertically)))
        (delete-other-windows)
        (let ((first-win (selected-window)))
          (funcall splitter)
          (if this-win-2nd (other-window 1))
          (set-window-buffer (selected-window) this-win-buffer)
          (set-window-buffer (next-window) next-win-buffer)
          (select-window first-win)
          (if this-win-2nd (other-window 1))))))

(defun read-library-name ()
  (require 'find-func)
  (let* ((dirs (or find-function-source-path load-path))
         (suffixes (find-library-suffixes))
         (table (apply-partially 'locate-file-completion-table
                                 dirs suffixes))
         (def (if (eq (function-called-at-point) 'require)
                  ;; `function-called-at-point' may return 'require
                  ;; with `point' anywhere on this line.  So wrap the
                  ;; `save-excursion' below in a `condition-case' to
                  ;; avoid reporting a scan-error here.
                  (condition-case nil
                      (save-excursion
                        (backward-up-list)
                        (forward-char)
                        (forward-sexp 2)
                        (thing-at-point 'symbol))
                    (error nil))
                (thing-at-point 'symbol))))
    (when (and def (not (test-completion def table)))
      (setq def nil))
    (completing-read (if def (format "Library name (default %s): " def)
                       "Library name: ")
                     table nil nil nil nil def)))

;;;###autoload
(defun find-library-other-window (library)
  "Find the Emacs-Lisp source of LIBRARY in another window."
  (interactive (list (read-library-name)))
  (let ((buf (find-file-noselect (find-library-name library))))
    (pop-to-buffer buf 'other-window)))

;;;###autoload
(defun find-library-other-frame (library)
  "Find the Emacs-Lisp source of LIBRARY in another frame."
  (interactive (list (read-library-name)))
  (let ((buf (find-file-noselect (find-library-name library))))
    (condition-case nil
        (switch-to-buffer-other-frame buf)
      (error (pop-to-buffer buf)))))

;;;###autoload
(defun sudo-find-file (&optional arg)
  (interactive "P")
  (require 'tramp)
  (if (or arg
          (not buffer-file-name)
          (file-writable-p buffer-file-name))
      (let ((default-directory
              (concat "/sudo:root@localhost:" default-directory)))
        (apply 'find-file
               (find-file-read-args
                "Find file: "
                (confirm-nonexistent-file-or-buffer))))
    (find-alternate-file (concat "/sudo:root@localhost:" buffer-file-name))))

;;; _
(provide 'fwb-cmds)
;; Local Variables:
;; indent-tabs-mode: nil
;; End:
;;; fwb-cmds.el ends here
