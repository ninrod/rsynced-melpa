;;; goto-last-point.el --- Record and jump to the last point in the buffer. -*- lexical-binding: t -*-

;; Copyright (C) 2019  Manuel Uberti

;; Author: Manuel Uberti <manuel.uberti@inventati.org>
;; URL: https://github.com/manuel-uberti/goto-last-point
;; Package-Version: 20190525.1855
;; Version: 0.1.0
;; Package-Requires: ((emacs "24.3"))
;; Keywords: convenience

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

;; When `goto-last-point-mode' is active, the last position of point in the
;; buffer is saved every time point moves, so you can easily go back to it using
;; `goto-last-point'.

;; This package is a MELPA-polished version of Chris Done's one:
;; https://github.com/chrisdone/emacs-config/blob/master/packages/goto-last-point/goto-last-point.el

;;; Code:

(require 'ring)

(defcustom goto-last-point-max-length
  5
  "Maximum length of the undo stack."
  :group 'goto-last-point
  :type 'integer)

(defvar-local goto-last-point-next nil
  "Next point to be added to the stack.")

(defvar-local goto-last-point-stack nil
  "The point undo stack.")

(defvar goto-last-point-goto-hook nil
  "Hook called after a jump happens.")

(define-minor-mode goto-last-point-mode
  "Record and jump to the last point in the buffer."
  nil
  :lighter " GLP"
  :require 'goto-last-point
  :global t
  (if goto-last-point-mode
      (goto-last-point--add-hooks)
    (goto-last-point--remove-hooks)
    (kill-local-variable 'goto-last-point-stack)))

(defun goto-last-point ()
  "Jump to the last point."
  (interactive)
  (when (local-variable-p 'goto-last-point-stack)
    (when (not (ring-empty-p goto-last-point-stack))
      (let ((point (ring-remove goto-last-point-stack 0)))
        (setq goto-last-point-next nil)
        (when point (goto-char point))
        (run-hooks 'goto-last-point-goto-hook)))))

(defun goto-last-point--add-hooks ()
  "Add hooks for recording point."
  (add-hook 'post-command-hook #'goto-last-point--record)
  (add-hook 'after-change-functions #'goto-last-point--clear))

(defun goto-last-point--remove-hooks ()
  "Remove hooks for recording point."
  (remove-hook 'post-command-hook #'goto-last-point--record)
  (remove-hook 'after-change-functions #'goto-last-point--clear))

(defun goto-last-point--clear (_ _1 _2)
  "Clear the last point after a change occur."
  (setq goto-last-point-stack nil)
  (setq goto-last-point-next nil))

(defun goto-last-point--record ()
  "Record the current point in the current buffer."
  (unless (or (minibufferp)
              (eq this-command 'self-insert-command))
    (unless (and (local-variable-p 'goto-last-point-stack)
                 goto-last-point-stack)
      (set (make-local-variable 'goto-last-point-stack)
           (make-ring goto-last-point-max-length))
      (make-local-variable 'goto-last-point-next))
    (when (and goto-last-point-next
               (/= goto-last-point-next
                   (point)))
      (ring-insert goto-last-point-stack
                   goto-last-point-next))
    (setq goto-last-point-next (point))))

(provide 'goto-last-point)

;;; goto-last-point.el ends here
