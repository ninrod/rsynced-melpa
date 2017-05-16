;;; cyphejor.el --- Shorten major mode names using user-defined rules -*- lexical-binding: t; -*-
;;
;; Copyright © 2015–2017 Mark Karpov <markkarpov@openmailbox.org>
;;
;; Author: Mark Karpov <markkarpov@openmailbox.org>
;; URL: https://github.com/mrkkrp/cyphejor
;; Package-Version: 20170501.1126
;; Version: 0.1.1
;; Package-Requires: ((emacs "24.4"))
;; Keywords: mode-line major-mode
;;
;; This file is not part of GNU Emacs.
;;
;; This program is free software: you can redistribute it and/or modify it
;; under the terms of the GNU General Public License as published by the
;; Free Software Foundation, either version 3 of the License, or (at your
;; option) any later version.
;;
;; This program is distributed in the hope that it will be useful, but
;; WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General
;; Public License for more details.
;;
;; You should have received a copy of the GNU General Public License along
;; with this program. If not, see <http://www.gnu.org/licenses/>.

;;; Commentary:

;; This package allows to shorten major mode names using a set of
;; user-defined rules.

;;; Code:

(require 'cl-lib)
(require 'subr-x)

(defgroup cyphejor nil
  "Shorten major mode names using user-defined rules"
  :group  'convenience
  :tag    "Cyphejor"
  :prefix "cyphejor-"
  :link   '(url-link :tag "GitHub" "https://github.com/mrkkrp/cyphejor"))

(defcustom cyphejor-rules nil
  "Rules used to convert names of major modes.

Every element of the list must be either a list:

  (STRING REPLACEMENT &rest PARAMETERS)

where STRING is a “word” in major mode symbol name, REPLACEMENT
is another string to be used instead, PARAMETERS is a list that
may be empty but may have the following keywords in it as well:

  :prefix  — put it in the beginning of result string
  :postfix — put it in the end of result string

Apart from elements of the form described above the following
keywords are allowed (they influence the algorithm in general):

  :downcase — replace words that are not specified explicitly
  with their first letter downcased

  :upcase — replace words that are not specified explicitly with
  their first letter upcased

If nothing is specified, use word unchanged separating it from
other words with spaces if necessary."
  :tag  "Active Rules"
  :type '(repeat
          (choice
           (const :tag "use first downcased letter" :downcase)
           (const :tag "use first upcased letter"   :upcase)
           (list string string)
           (list string string
                 (choice (const :tag "put it in the beginning" :prefix)
                         (const :tag "put it in the end"       :postfix))))))

(defun cyphejor--cypher (old-name rules)
  "Convert OLD-NAME into its shorter form following RULES.

Format of RULES is described in doc-string of `cyphejor-rules'.

OLD-NAME must be a string where “words” are separated with
punctuation characters.  Casing of every words doesn't matter
because the whole thing will be downcased first."
  (let ((words    (split-string (downcase old-name) "[[:punct:]]" t))
        (downcase (cl-find :downcase rules))
        (upcase   (cl-find :upcase   rules))
        prefix-words
        postfix-words
        conversion-table
        prefix-result
        result
        postfix-result)
    (dolist (rule (cl-remove-if-not #'listp rules))
      (let ((before (car      rule))
            (after  (cadr     rule))
            (where  (cl-caddr rule)))
        (push (cons before after) conversion-table)
        (cl-case where
          (:prefix  (push before prefix-words))
          (:postfix (push before postfix-words)))))
    (dolist (word words)
      (let ((translated
             (or (cdr (assoc word conversion-table))
                 (cond (downcase (cl-subseq word 0 1))
                       (upcase   (upcase (cl-subseq word 0 1)))
                       (t        (format " %s " word))))))
        (cond ((member word prefix-words)
               (push translated prefix-result))
              ((member word postfix-words)
               (push translated postfix-result))
              (t
               (push translated result)))))
    (string-trim
     (apply #'concat
            (mapcar (lambda (x) (apply #'concat (reverse x)))
                    (list prefix-result
                          result
                          postfix-result))))))

(defun cyphejor--hook ()
  "Set `mode-name' according of symbol name in `major-mode'.

This uses `cyphejor--cypher' and `cyphejor-rules' to generate new
mode name."
  (setq mode-name
        (cyphejor--cypher
         (symbol-name major-mode)
         cyphejor-rules)))

;;;###autoload
(define-minor-mode cyphejor-mode
  "Toggle `cyphejor-mode' minor mode.

With a prefix argument ARG, enable `cyphejor-mode' if ARG is
positive, and disable it otherwise.  If called from Lisp, enable
the mode if ARG is omitted or NIL, and toggle it if ARG is
`toggle'.

This global minor mode shortens names of major modes
automatically following user-defined rules in
`cyphejor-rules'. See description of the variable for more
information."
  nil "" nil
  :global t
  (funcall (if cyphejor-mode #'add-hook #'remove-hook)
           'after-change-major-mode-hook
           #'cyphejor--hook)
  (if cyphejor-mode
      (advice-add 'wdired-change-to-dired-mode :after #'cyphejor--hook)
    (advice-remove 'wdired-change-to-dired-mode #'cyphejor--hook)))

(provide 'cyphejor)

;;; cyphejor.el ends here
