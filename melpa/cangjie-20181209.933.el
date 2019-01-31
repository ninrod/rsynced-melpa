;;; cangjie.el --- retrieve cangjie code for han characters  -*- lexical-binding: t; -*-

;; Authors: Kisaragi Hiu <mail@kisaragi-hiu.com>
;; URL: https://github.com/kisaragi-hiu/cangjie.el
;; Package-Version: 20181209.933
;; Version: 0.5.3
;; Package-Requires: ((emacs "24") (s "1.12.0") (dash "2.14.1") (f "0.2.0"))
;; Keywords: convenience, writing

;; This file is NOT part of GNU Emacs.

;; cangjie.el is free software: you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; cangjie.el is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with cangjie.el.
;; If not, see <http://www.gnu.org/licenses/>.

;;; Commentary:

;; Lookup the Cangjie encoding for a given Han character.

;;; Code:

(require 's)
(require 'f)
(require 'dash)
(require 'url)

(defgroup cangjie nil
  "Lookup Cangjie code from a RIME dictionary or Wiktionary."
  :group 'convenience
  :prefix "cangjie-")

(defcustom cangjie-source 'rime
  "RIME dictionary to lookup the character's code in.

Its value can be:

- a path,
  which makes `cangjie' read from that path if it's a valid RIME dictionary.
- `rime',
  to download the dictionary from URL `https://github.com/rime/rime-cangjie',
  and save it for future use.
- `wiktionary-raw',
  to output the line with the Cangjie code on the character's Wiktionary page,
- `wiktionary', or anything else,
  to grep the Wiktionary page like `wiktionary-raw', then try to remove the
  markup in the result, leaving just the Cangjie code.

Set to `rime' by default, so the dictionary will be downloaded on first use."
  :group 'cangjie
  :type '(choice file
                 (const :tag "'rime" rime)
                 (const :tag "'wiktionary-raw" wiktionary-raw)
                 (const :tag "'wiktionary" wiktionary)))


(defun cangjie--grep-buffer (buffer s)
  "Return lines in BUFFER matching S as a list."
  (let (results)
    (with-current-buffer buffer
      (goto-char 0)
      (while (search-forward s nil t)
        (setq results
              (cons (buffer-substring-no-properties
                     (progn (beginning-of-line) (point))
                     (progn (end-of-line) (point)))
                    results))))
    results))

(defun cangjie--grep-file (file s)
  "Grab lines from FILE containing S, and return them as a list."
  (with-temp-buffer
    (insert-file-contents file)
    (cangjie--grep-buffer (current-buffer) s)))

(defun cangjie--file-contains? (file s)
  "Does FILE contain S?"
  (not (not (cangjie--grep-file file s))))

(defun cangjie--valid-rime-dict? (val)
  "Check if VAL is a path to a valid RIME dictionary."
  (and (stringp val)
       (f-exists? val)
       (s-suffix? ".yaml" val)
       (cangjie--file-contains? val "name:")
       (cangjie--file-contains? val "use_preset_vocabulary:")))

(defun cangjie--abc-to-han (abc)
  "Convert alphabetical Cangjie code representation ABC into Han characters."
  (let ((h #s(hash-table
              size 52
              test equal
              data ("a" "日" "b" "月" "c" "金" "d" "木" "e" "水" "f" "火"
                    "g" "土" "h" "竹" "i" "戈" "j" "十" "k" "大" "l" "中"
                    "m" "一" "n" "弓" "o" "人" "p" "心" "q" "手" "r" "口"
                    "s" "尸" "t" "廿" "u" "山" "v" "女" "w" "田" "x" "難"
                    "y" "卜" "z" "重"))))
    (->> (downcase abc)
         (s-split "")
         (--map (gethash it h))
         (s-join ""))))

;;;###autoload
(defun cangjie (character)
  "Retrieve Cangjie code for the han CHARACTER."
  (interactive "M漢字：")
  (when (characterp character)
    (setq character (char-to-string character)))
  (unless (stringp character)
    (error "%s not a string or character" character))
  (unless (eq (aref char-script-table (string-to-char character))
              'han)
    (error "\"%s\" is not a han character" character))
  (let ((result
         (cond ((eq cangjie-source 'rime)
                (let ((cangjie-source (f-join user-emacs-directory "cangjie5.dict.yaml")))
                  (if (cangjie--valid-rime-dict? cangjie-source)
                      (cangjie character)
                    ;; download the dictionary when it's not there
                    (url-copy-file
                     "https://raw.githubusercontent.com/rime/rime-cangjie/master/cangjie5.dict.yaml"
                     cangjie-source)
                    (cangjie character))))

               ((cangjie--valid-rime-dict? cangjie-source)
                ;; take cangjie encoding from RIME dictionary
                (->> (cangjie--grep-file cangjie-source character)
                     (--filter (not (s-prefix? "#" it)))
                     (s-join "")
                     (s-split "\t")
                     second
                     cangjie--abc-to-han))

               ((eq cangjie-source 'wiktionary-raw)
                (cangjie--grep-buffer (url-retrieve-synchronously
                                       (concat "https://zh.wiktionary.org/wiki/"
                                               character))
                                      "仓颉"))

               (t
                ;; Try to extract encoding from grep'd wiktionary text
                (->>
                 (cangjie--grep-buffer (url-retrieve-synchronously
                                        (concat "https://zh.wiktionary.org/wiki/"
                                                character))
                                       "仓颉")
                 (s-replace-regexp "^.*：" "")
                 s-trim
                 (s-replace-regexp "<.*>$" "")
                 cangjie--abc-to-han)))))

    (when (called-interactively-p 'interactive)
      (message result))
    result))

;;;###autoload
(defun cangjie-at-point ()
  "Run `cangjie' at point."
  (interactive)
  (let ((result
         (cangjie (string (char-after)))))
    (when (called-interactively-p 'interactive)
      (message result))
    result))

(provide 'cangjie)
;;; cangjie.el ends here
