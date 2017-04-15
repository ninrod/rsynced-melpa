;;; rectangle-utils.el --- Some useful rectangle functions.

;; Author: Thierry Volpiatto <thierry.volpiatto@gmail.com>
;; Copyright (C) 2010~2014 Thierry Volpiatto, all rights reserved.
;; X-URL: https://github.com/thierryvolpiatto/rectangle-utils

;; Compatibility: GNU Emacs 24.1+
;; Package-Requires: ((emacs "24") (cl-lib "0.5"))
;; Package-Version: 20160914.2108

;; This file is not part of GNU Emacs.

;; This program is free software; you can redistribute it and/or
;; modify it under the terms of the GNU General Public License as
;; published by the Free Software Foundation; either version 3, or
;; (at your option) any later version.
;;
;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
;; General Public License for more details.
;;
;; You should have received a copy of the GNU General Public License
;; along with this program; see the file COPYING.  If not, write to
;; the Free Software Foundation, Inc., 51 Franklin Street, Fifth
;; Floor, Boston, MA 02110-1301, USA.


;;; Code:

(require 'cl-lib)
(require 'rect)

(defun rectangle-utils--goto-longest-region-line (beg end)
  "Find the longest line in region and go to it."
  (let* ((real-end  (save-excursion (goto-char end) (end-of-line) (point)))
         (buf-str   (buffer-substring beg real-end))
         (line-list (split-string buf-str "\n"))
         (longest   0)
         (count     0)
         nth-longest-line)
    (cl-loop for i in line-list
          do (progn
               (when (> (length i) longest)
                 (setq longest (length i))
                 (setq nth-longest-line count))
               (cl-incf count)))
    (goto-char beg)
    (forward-line nth-longest-line)))

(defvar rectangle-utils--extend-region-to-space-separator " ")
(defvar rectangle-utils-regexp-history nil)

(cl-defun rectangle-utils-num-char-to-space (&optional (space " "))
  (let ((count 0))
    (catch 'eol
      (unless (looking-at " \\|\n\\|\t")
        (save-excursion
          (while (not (looking-at space))
            (and (eolp) (throw 'eol count))
            (forward-char 1)
            (cl-incf count))))
      count)))

(defun rectangle-utils-longest-length-until-space-in-region (beg end)
  (let ((num-lines (count-lines beg end))
        longest)
    (save-excursion
      (goto-char (region-beginning))
      (setq longest (rectangle-utils-num-char-to-space
                     rectangle-utils--extend-region-to-space-separator))
      (let ((col (current-column)))
        (cl-loop repeat (1- num-lines) do
                 (progn
                   (forward-line 1)
                   (forward-char col)
                   (pcase (rectangle-utils-num-char-to-space
                           rectangle-utils--extend-region-to-space-separator)
                     ((and it (pred (< longest)))
                      (setq longest it)))))))
    longest))

(cl-defun rectangle-utils-count-spaces (&optional (space " "))
  (let ((count 0))
    (catch 'eol
      (save-excursion
        (while (looking-at space)
          (and (eolp) (throw 'eol count))
          (forward-char 1)
          (cl-incf count))
        count))))

;;;###autoload
(defun rectangle-utils-extend-rectangle-to-end (beg end)
  "Create a rectangle based on the longest line of region."
  (interactive "r")
  (let ((longest-len (save-excursion
                       (rectangle-utils--goto-longest-region-line beg end)
                       (length (buffer-substring (point-at-bol) (point-at-eol)))))
        (inhibit-read-only t) ; ignore read-only status of the buffer
        column-beg column-end)
    (goto-char beg) (setq column-beg (current-column))
    (save-excursion (goto-char end) (setq column-end (current-column)))
    (if (not (eq column-beg column-end))
        (progn
          (while (< (point) end)
            (goto-char (point-at-eol))
            (let ((len-line (- (point-at-eol) (point-at-bol))))
              (when (< len-line longest-len)
                (let ((diff (- longest-len len-line)))
                  (insert (make-string diff ? ))
                  (setq end (+ diff end)))))
            (forward-line))
          ;; Go back to END and end-of-line to be sure END is there.
          (goto-char end) (end-of-line) (setq end (point))
          ;; Go back to BEG and push mark to new END.
          (goto-char beg)
          (push-mark end 'nomsg 'activate)
          (setq deactivate-mark  nil)
          (when (fboundp 'rectangle-mark-mode)
            (rectangle-mark-mode 1)))
      (deactivate-mark 'force)
      (error "Error: not in a rectangular region."))))


(defvar rectangle-utils-menu-string
  "Rectangle Menu:
==============
i  ==>insert,      a==>insert at right.
k  ==>kill,        d==>delete.
o  ==>open,        w==>copy to register.
e  ==>mark to end, y==>yank.
M-w==>copy,        c==>clear.
r  ==>replace,     q==>quit.
C-g==>exit and restore."
  "Menu for command `rectangle-utils-menu'.")

;;;###autoload
(defun rectangle-utils-menu (beg end)
  (interactive "r")
  (if (and transient-mark-mode (region-active-p))
      (unwind-protect
           (while (let ((input (read-key (propertize rectangle-utils-menu-string
                                          'face 'minibuffer-prompt))))
                    (cl-case input
                      (?i
                       (let* ((def-val (car string-rectangle-history))
                              (string  (read-string (format "String insert rectangle (Default %s): " def-val)
                                                    nil 'string-rectangle-history def-val)))
                         (string-insert-rectangle beg end string) nil))
                      (?a (rectangle-utils-insert-at-right beg end nil) nil)
                      (?k (kill-rectangle beg end) nil)
                      (?\M-w (rectangle-utils-copy-rectangle beg end) nil)
                      (?d (delete-rectangle beg end) nil)
                      (?o (open-rectangle beg end) nil)
                      (?c (clear-rectangle beg end) nil)
                      (?w (copy-rectangle-to-register (read-string "Register: ") beg end) nil)
                      (?e (rectangle-utils-extend-rectangle-to-end beg end)
                          (setq beg (region-beginning)
                                end (region-end)) t)
                      (?\C-g (delete-trailing-whitespace beg end)
                             (goto-char beg) nil)
                      (?y (yank-rectangle) nil)
                      (?r
                       (let* ((def-val (car string-rectangle-history))
                              (string  (read-string (format "Replace region by String (Default %s): " def-val)
                                                    nil 'string-rectangle-history def-val)))
                         (string-rectangle beg end string) nil) nil)
                      (?q nil))))
        (deactivate-mark t)
        (message nil))
      (message "No region, activate region please!")))

;;;###autoload
(defun rectangle-utils-insert-at-right (beg end arg)
  "Create a new rectangle based on longest line of region\
and insert string at right of it.
With prefix arg, insert string at end of each lines (no rectangle)."
  (interactive "r\nP")
  (let ((incstr (lambda (str)
                  (if (and str (string-match "[0-9]+" str))
                      (let ((rep (match-string 0 str)))
                        (replace-match
                         (int-to-string (1+ (string-to-number rep)))
                         nil t str))
                      str)))
        (def-val (car string-rectangle-history))
        str)
    (unless arg
      (rectangle-utils-extend-rectangle-to-end beg end)
      (setq end (region-end)))
    ;; marked region is no more needed.
    (deactivate-mark)
    (goto-char beg) (end-of-line)
    (unless arg (setq beg (point)))
    (while (< (point) end)
      (let ((init (funcall incstr str)))
        (setq str (read-string
                   (format "Insert string at end of rectangle (Default %s): " def-val)
                   nil 'string-rectangle-history def-val))
        ;; Now reuse last used STR in next cycle.
        (setq def-val str)
        (insert str)
        (forward-line 1)
        (end-of-line)
        (setq end (+ end (length str)))))
    (setq str (read-string
               (format "Insert string at end of rectangle (Default %s): " def-val)
               nil 'string-rectangle-history def-val))
    (insert str)))

;;;###autoload
(defun rectangle-utils-copy-rectangle (beg end)
  "Well, copy rectangle, not kill."
  (interactive "r")
  (setq killed-rectangle (extract-rectangle beg end))
  (setq deactivate-mark t))

;;;###autoload
(defun rectangle-utils-extend-rectangle-to-space (beg end)
  "Allow creating a rectangular region up to space.
The rectangle is extended indeed to `rectangle-utils--extend-region-to-space-separator'."
  (interactive "r")
  (let ((lgst      (rectangle-utils-longest-length-until-space-in-region beg end))
        (num-lines (count-lines beg end))
        column-beg column-end new-end)
    (goto-char beg)
    (setq column-beg (current-column))
    (save-excursion
      (goto-char end)
      (setq column-end (current-column)))
    (if (not (eq column-beg column-end))
        (progn
          (save-excursion
            (cl-loop with col = (current-column)
                  repeat num-lines do
                  (progn
                    (pcase (rectangle-utils-num-char-to-space
                            rectangle-utils--extend-region-to-space-separator)
                      ((and it (guard (> lgst it)))
                       (forward-char it)
                       (if (> (rectangle-utils-count-spaces
                               rectangle-utils--extend-region-to-space-separator) (- lgst it))
                           (forward-char (- lgst it))
                         (insert (make-string (- lgst it) ? )))
                       (setq new-end (point)))
                      ((pred zerop)
                       (forward-whitespace 1)
                       (if (>= (rectangle-utils-count-spaces
                                rectangle-utils--extend-region-to-space-separator) lgst)
                           (forward-char lgst)
                         (insert (make-string lgst ? )))
                       (setq new-end (point)))
                      (_ (forward-char lgst) (setq new-end (point))))
                    (forward-line 1)
                    (move-to-column col))))
          (push-mark new-end 'nomsg 'activate)
          (setq deactivate-mark nil)
          (when (fboundp 'rectangle-mark-mode)
            (rectangle-mark-mode 1)))
      (deactivate-mark 'force)
      (error "Error: not in a rectangular region."))))

;;;###autoload
(defun rectangle-utils-extend-rectangle-to-space-or-paren (beg end)
  "Allow creating a rectangular region up to space or paren i.e \"(\".
Useful to realign let, setq etc..."
  (interactive "r")
  (let ((rectangle-utils--extend-region-to-space-separator " \\|("))
    (rectangle-utils-extend-rectangle-to-space beg end)))

;;;###autoload
(defun rectangle-utils-extend-rectangle-to-space-or-dot (beg end)
  "Allow creating a rectangular region up to space or dot.
Useful to realign alists."
  (interactive "r")
  (let ((rectangle-utils--extend-region-to-space-separator " \\|[.]"))
    (rectangle-utils-extend-rectangle-to-space beg end)))

;;;###autoload
(defun rectangle-utils-extend-rectangle-to-regexp (beg end)
  "Allow creating a rectangular region up to regexp."
  (interactive "r")
  (let ((rectangle-utils--extend-region-to-space-separator
         (read-regexp "Regexp: " " " 'rectangle-utils-regexp-history)))
    (rectangle-utils-extend-rectangle-to-space beg end)))

(provide 'rectangle-utils)

;;; rectangle-utils.el ends here.
