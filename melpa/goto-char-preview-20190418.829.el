;;; goto-char-preview.el --- Preview character when executing `goto-char` command.  -*- lexical-binding: t; -*-

;; Copyright (C) 2019  Shen, Jen-Chieh
;; Created date 2019-04-18 16:03:46

;; Author: Shen, Jen-Chieh <jcs090218@gmail.com>
;; Description: Preview character when executing `goto-char` command.
;; Keyword: character navigation
;; Version: 0.0.1
;; Package-Version: 20190418.829
;; Package-Requires: ((emacs "24.3"))
;; URL: https://github.com/jcs090218/goto-char-preview

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
;;
;; Preview character when executing `goto-char` command.
;;

;;; Code:


(defgroup goto-char-preview nil
  "Preview char when executing `goto-char` command."
  :prefix "goto-char-preview-"
  :group 'convenience
  :group 'tools
  :link '(url-link :tag "Repository" "https://github.com/jcs090218/goto-char-preview"))


(defvar goto-char-preview-prev-window nil
  "Record down the previous window before we do `goto-char-preview' command.")

(defvar goto-char-preview-prev-char-pos nil
  "Record down the previous character position before we do `goto-char-preview' command.")

(defcustom goto-char-preview-before-hook nil
  "Hooks run before `goto-char-preview' is run."
  :group 'goto-char-preview
  :type 'hook)

(defcustom goto-char-preview-after-hook nil
  "Hooks run after `goto-char-preview' is run."
  :group 'goto-char-preview
  :type 'hook)


(defun goto-char-preview-do-preview ()
  "Do the goto char preview action."
  (save-selected-window
    (when goto-char-preview-prev-window
      (let ((char-pos-str (thing-at-point 'line)))

        (select-window goto-char-preview-prev-window)

        (if char-pos-str
            (let ((char-pos (string-to-number char-pos-str)))
              (when (<= char-pos 0)
                (setq char-pos 1))

              (goto-char-preview-do char-pos))
          (goto-char-preview-do goto-char-preview-prev-char-pos))))))

(defun goto-char-preview-do (char-pos)
  "Do goto char.
CHAR-POS : Target character position to navigate to."
  (save-selected-window
    (select-window goto-char-preview-prev-window)
    (goto-char (point-min))
    (when (< (point-max) char-pos)
      (setq char-pos (point-max)))
    (forward-char (1- char-pos))))


;;;###autoload
(defun goto-char-preview ()
  "Preview goto char."
  (interactive)
  (let ((window (selected-window))
        (window-point (window-point))
        jumped)
    (run-hooks 'goto-char-preview-before-hook)
    (unwind-protect
        (let ((goto-char-preview-prev-window (selected-window))
              (goto-char-preview-prev-char-pos (point)))
          (setq jumped (read-number "Goto char: ")))
      (unless jumped
        (set-window-point window window-point))
      (run-hooks 'goto-char-preview-after-hook))))

(defun goto-char-preview-minibuffer-setup ()
  "Locally set up preview hooks for this minibuffer command."
  (when (memq this-command '(goto-char-preview))
    (add-hook 'post-command-hook
              #'goto-char-preview-do-preview nil t)))

(add-hook 'minibuffer-setup-hook 'goto-char-preview-minibuffer-setup)


(provide 'goto-char-preview)
;;; goto-char-preview.el ends here
