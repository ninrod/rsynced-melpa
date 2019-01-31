;;; cc-cedict.el --- Interface to CC-CEDICT (a Chinese-English dictionary)  -*- lexical-binding: t; -*-

;; Copyright (C) 2018  Xu Chunyang

;; Author: Xu Chunyang <mail@xuchunyang.me>
;; Homepage: https://github.com/xuchunyang/cc-cedict.el
;; Created: 2018-12-03
;; Version: 0.1
;; Package-Version: 20181217.1112
;; Package-Requires: ((emacs "25"))

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <https://www.gnu.org/licenses/>.

;;; Commentary:

;; cc-cedict.el is an Emacs interface for CC-CEDICT, a public-domain
;; Chinese-English dictionary.

;;; Code:

(require 'cl-lib)

;; Download it from https://cc-cedict.org/wiki/
;;
;; $ wget https://www.mdbg.net/chinese/export/cedict/cedict_1_0_ts_utf-8_mdbg.txt.gz
;; $ gunzip cedict_1_0_ts_utf-8_mdbg.txt.gz
(defvar cc-cedict-file (let ((file
                              (expand-file-name
                               "cedict_1_0_ts_utf-8_mdbg.txt"
                               (file-name-directory
                                (or load-file-name buffer-file-name)))))
                         (and (file-exists-p file) file))
  "Path to the dictionary file.")

(cl-defstruct (cc-cedict-entry (:constructor cc-cedict-entry-create)
                               (:copier nil))
  traditional simplified pinyin english)

(defun cc-cedict-parse ()
  (let (vec (idx 0))
    (with-temp-buffer
      (insert-file-contents cc-cedict-file)
      (goto-char (point-min))
      (re-search-forward "^[^#]")
      (goto-char (line-beginning-position))
      (setq vec (make-vector (count-lines (point) (point-max)) nil))
      (while (not (eobp))
        (if (looking-at (rx bol
                            (group (1+ (not (in " "))))
                            " "
                            (group (1+ (not (in " "))))
                            " "
                            "[" (group (1+ nonl)) "]"
                            " "
                            "/" (group (+ nonl)) "/"
                            eol))
            (aset vec idx
                  (cc-cedict-entry-create :traditional (match-string 1)
                                          :simplified (match-string 2)
                                          :pinyin (match-string 3)
                                          :english (split-string (match-string 4) "/")))
          (error "Failed to parse '%s'"
                 (buffer-substring
                  (line-beginning-position) (line-end-position))))
        (setq idx (1+ idx))
        (forward-line 1))
      vec)))

(defvar cc-cedict-cache nil
  "Vector of `cc-cedict-entry' objects or nil.")

(defun cc-cedict-completing-read ()
  (unless cc-cedict-cache
    (setq cc-cedict-cache (cc-cedict-parse)))
  (completing-read "Chinese: "
                   (mapcar #'cc-cedict-entry-simplified cc-cedict-cache)))

;;;###autoload
(defun cc-cedict (chinese)
  "Search CC-CEDICT by traditional or simplified CHINESE.
Return the result, a `cc-cedict-entry' object or nil.
Interactively, display the result in echo area."
  (interactive (list (cc-cedict-completing-read)))
  (unless cc-cedict-cache
    (setq cc-cedict-cache (cc-cedict-parse)))
  (let ((found
         (cl-loop for entry across cc-cedict-cache
                  when (or (string= chinese (cc-cedict-entry-traditional entry))
                           (string= chinese (cc-cedict-entry-simplified entry)))
                  return entry)))
    (when (called-interactively-p 'interactive)
      (if found
          (message "%s %s [%s] /%s/"
                   (cc-cedict-entry-traditional found)
                   (cc-cedict-entry-simplified found)
                   (cc-cedict-entry-pinyin found)
                   (mapconcat #'identity (cc-cedict-entry-english found) "/"))
        (message "No result found for %s" chinese)))
    found))

(provide 'cc-cedict)
;;; cc-cedict.el ends here
