;;; isearch-project.el --- Incremental search through the whole project.  -*- lexical-binding: t; -*-

;; Copyright (C) 2019  Shen, Jen-Chieh
;; Created date 2019-03-18 15:16:04

;; Author: Shen, Jen-Chieh <jcs090218@gmail.com>
;; Description: Incremental search through the whole project.
;; Keyword: convenience, search
;; Version: 0.0.1
;; Package-Version: 20190422.1231
;; Package-Requires: ((emacs "25") (cl-lib "0.6"))
;; URL: https://github.com/jcs090218/isearch-project

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
;; Incremental search through the whole project.
;;

;;; Code:

(require 'cl-lib)
(require 'grep)
(require 'isearch)


(defgroup isearch-project nil
  "Incremental search through the whole project."
  :prefix "isearch-project-"
  :group 'isearch
  :link '(url-link :tag "Repository" "https://github.com/jcs090218/isearch-project"))


(defvar isearch-project-search-path ""
  "Record the current search path, so when next time it searhs would not need to research from the start.")

(defvar isearch-project-project-dir ""
  "Current isearch project directory.")

(defvar isearch-project-files '()
  "List of file path in the project.")

(defvar isearch-project-files-starting-index -1
  "Starting search path index, use with `isearch-project-files' list.")

(defvar isearch-project-files-current-index -1
  "Current search path index, use with `isearch-project-files' list.")

(defvar isearch-project-run-advice t
  "Flag to check if run advice.")

(defvar isearch-project-thing-at-point ""
  "Record down the symbol while executing `isearch-project-forward-symbol-at-point' command.")


(defun isearch-project-is-contain-list-string (in-list in-str)
  "Check if a string contain in any string in the string list.
IN-LIST : list of string use to check if IN-STR in contain one of
the string.
IN-STR : string using to check if is contain one of the IN-LIST."
  (cl-some #'(lambda (lb-sub-str) (string-match-p (regexp-quote lb-sub-str) in-str)) in-list))

(defun isearch-project-remove-nth-element (n lst)
  "Remove nth element from the list.
N : nth element you want to remove from the list.
LST : List you want to modified."
  (if (zerop n)
      (cdr lst)
    (let ((last (nthcdr (1- n) lst)))
      (setcdr last (cddr last))
      lst)))

(defun isearch-project-filter-directory-files-recursively (lst)
  "Filter directory files.
LST : Directory files."
  (let ((index 0)
        (path "")
        (ignored-paths '()))
    (setq ignored-paths (mapcar #'copy-sequence grep-find-ignored-directories))
    ;; Add / at the end of each path.
    (while (< index (length ignored-paths))
      (setq path (nth index ignored-paths))
      (setq path (concat path "/"))
      (setf (nth index ignored-paths) path)
      (setq index (+ index 1)))

    (setq index 0)

    (while (< index (length lst))
      (setq path (nth index lst))

      ;; Filter it.
      (if (isearch-project-is-contain-list-string ignored-paths path)
          (setq lst (isearch-project-remove-nth-element index lst))
        (setq index (+ index 1)))))
  lst)

(defun isearch-project-prepare ()
  "Incremental search preparation."
  (let ((prepare-success nil))
    (setq isearch-project-project-dir (cdr (project-current)))
    (when isearch-project-project-dir
      ;; Get the current buffer name.
      (setq isearch-project-search-path (buffer-file-name))
      ;; Get all the file from the project, and filter it.
      (setq isearch-project-files (directory-files-recursively isearch-project-project-dir ""))
      (setq isearch-project-files (isearch-project-filter-directory-files-recursively isearch-project-files))
      ;; Reset to -1.
      (setq isearch-project-files-current-index -1)

      (setq prepare-success t))
    prepare-success))


;;;###autoload
(defun isearch-project-forward-symbol-at-point ()
  "Incremental search forward at current point in the project."
  (interactive)
  (setq isearch-project-thing-at-point (thing-at-point 'symbol))
  (if (or (use-region-p)
          (char-or-string-p isearch-project-thing-at-point))
      (isearch-project-forward)
    (error "Isearch project : no region or symbol at point")))

;;;###autoload
(defun isearch-project-forward ()
  "Incremental search forward in the project."
  (interactive)
  (if (isearch-project-prepare)
      (progn
        (isearch-project-add-advices)
        (isearch-forward)
        (isearch-project-remove-advices))
    (error "Cannot isearch project without project directory defined")))


(defun isearch-project-add-advices ()
  "Add all needed advices."
  (advice-add 'isearch-repeat :after #'isearch-project-advice-isearch-repeat-after))

(defun isearch-project-remove-advices ()
  "Remove all needed advices."
  (advice-remove 'isearch-repeat #'isearch-project-advice-isearch-repeat-after))


(defun isearch-project-contain-string (in-sub-str in-str)
  "Check if a string is a substring of another string.
Return true if contain, else return false.
IN-SUB-STR : substring to see if contain in the IN-STR.
IN-STR : string to check by the IN-SUB-STR."
  (string-match-p in-sub-str in-str))

(defun isearch-project-get-string-from-file (filePath)
  "Return filePath's file content.
FILEPATH : file path."
  (with-temp-buffer
    (insert-file-contents filePath)
    (buffer-string)))


(defun isearch-project-find-file-search (fn dt)
  "Open a file and isearch.
If found, leave it.  If not found, try find the next file.
FN : file to search.
DT : search direction."
  (find-file fn)
  (cond ((eq dt 'forward)
         (goto-char (point-min)))
        ((eq dt 'backward)
         (goto-char (point-max))))

  (isearch-search-string isearch-string nil t)

  (let ((isearch-project-run-advice nil))
    (cond ((eq dt 'forward)
           (isearch-repeat-forward))
          ((eq dt 'backward)
           (isearch-repeat-backward)))))


(defun isearch-project-advice-isearch-repeat-after (dt &optional cnt)
  "Advice when do either `isearch-repeat-backward' or `isearch-repeat-forward' \
command.
DT : search direction.
CNT : search count."
  (when (and (not isearch-success)
             isearch-project-run-advice)
    (let ((next-file-index isearch-project-files-current-index)
          (next-fn ""))
      ;; Get the next file index.
      (when (= isearch-project-files-current-index -1)
        (setq isearch-project-files-current-index
              (cl-position isearch-project-search-path
                           isearch-project-files
                           :test 'string=))
        (setq next-file-index isearch-project-files-current-index))

      ;; Record down the starting file index.
      (setq isearch-project-files-starting-index isearch-project-files-current-index)

      (let ((buf-content "")
            (break-it nil)
            (search-cnt (if cnt cnt 1)))
        (while (not break-it)
          ;; Get the next file index.
          (cond ((eq dt 'backward)
                 (setq next-file-index (- next-file-index 1)))
                ((eq dt 'forward)
                 (setq next-file-index (+ next-file-index 1))))

          ;; Cycle it.
          (cond ((eq dt 'backward)
                 (when (< next-file-index 0)
                   (setq next-file-index (- (length isearch-project-files) 1))))
                ((eq dt 'forward)
                 (when (>= next-file-index (length isearch-project-files))
                   (setq next-file-index 0))))

          ;; Target the next file.
          (setq next-fn (nth next-file-index isearch-project-files))

          ;; Update buffer content.
          (setq buf-content (isearch-project-get-string-from-file next-fn))

          (when (or
                 ;; Found match.
                 (isearch-project-contain-string isearch-string buf-content)
                 ;; Is the same as the starting file, this prevents infinite loop.
                 (= isearch-project-files-starting-index next-file-index))
            (setq search-cnt (- search-cnt 1))
            (when (<= search-cnt 0)
              (setq break-it t)))))

      ;; Open the file.
      (isearch-project-find-file-search next-fn dt)

      ;; Update current file index.
      (setq isearch-project-files-current-index next-file-index))))


(defun isearch-project-isearch-yank-string (search-str)
  "Isearch project allow arrow because we need to search through next file.
SEARCH-STR : Search string."
  (ignore-errors
    (isearch-yank-string search-str)))

(defun isearch-project-isearch-mode-hook ()
  "Paste the current symbol when `isearch' enabled."
  (cond ((use-region-p)
         (let ((search-str (buffer-substring-no-properties (region-beginning) (region-end))))
           (deactivate-mark)
           (isearch-project-isearch-yank-string search-str)))
        ((memq this-command '(isearch-project-forward-symbol-at-point))
         (when (char-or-string-p isearch-project-thing-at-point)
           (isearch-project-isearch-yank-string isearch-project-thing-at-point)))))

(add-hook 'isearch-mode-hook #'isearch-project-isearch-mode-hook)


(provide 'isearch-project)
;;; isearch-project.el ends here
