;;; org-edit-latex.el --- Edit embedded LaTeX in a dedicated buffer  -*- lexical-binding: t; -*-

;; Copyright (C) 2017-2018 James Wong

;; Author: James Wong <jianwang.academic@gmail.com>
;; URL: https://github.com/et2010/org-edit-latex
;; Package-Version: 20170621.758
;; Keywords: org, LaTeX
;; Version: 0.8.0
;; Package-Requires: ((emacs "24.4") (org "9.0") (auctex "11.90"))

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

;; This package will let you edit a latex fragment like editing a src code
;; block.

;; Install
;; =======

;; First, download this package and include its path in your load-path. Then, you can add following in your init file:

;; (require 'org-edit-latex)

;; And don't forget to add latex to `org-babel-load-languages' (below is for demonstration, your languages list may differ from it.)

;; (org-babel-do-load-languages
;;  'org-babel-load-languages
;;  '((emacs-lisp . t)
;;    (latex . t)   ;; <== add latex to the list
;;    (python . t)
;;    (shell . t)
;;    (ruby . t)
;;    (perl . t)))

;; Usage
;; =====

;; First, turn on `org-edit-latex-mode'. Then you can edit a LaTeX fragment just
;; as what you'll do to edit a src block.

;; Use `org-edit-special' to enter a dedicated LaTeX buffer.
;; Use `org-edit-src-exit' to exit LaTeX buffer when you finished editing.
;; Use `org-edit-src-abort' to quit editing without saving changes.

;; Note that all above commands are built-in Org commands, so your current
;; keybindings to them will do the job.

;;; Code:

(require 'org)
(require 'org-element)
(require 'ox-latex)
(require 'preview)

(defcustom org-edit-latex-frag-master "frag-master.tex"
  "Master file for LaTeX fragments."
  :group 'org-edit-latex
  :version "24.4")

(defcustom org-edit-latex-create-master t
  "Decide whether we should create a TeX-master file."
  :group 'org-edit-latex
  :version "24.4")

(defvar-local org-edit-latex--before-type nil
  "Element type before wrapping.")

(defconst org-edit-latex-inline-beg-regexp
  "\\\\(\\|\\$[^$]\\|\\\\\\sw"
  "Regexp to match beginning of inline LaTeX")

;;;###autoload
(define-minor-mode org-edit-latex-mode
  "LaTeX editing in org mode."
  :lighter " Edit-LaTeX"
  (if org-edit-latex-mode
      (progn
        (advice-add #'org-edit-special :around #'org-edit-latex--wrap-maybe)
        (advice-add #'org-edit-src-exit :around #'org-edit-latex--unwrap-maybe)
        (org-edit-latex-create-master-maybe)
        (add-hook 'org-src-mode-hook 'org-edit-latex--set-TeX-master))
    (advice-remove #'org-edit-special #'org-edit-latex--wrap-maybe)
    (advice-remove #'org-edit-src-exit #'org-edit-latex--unwrap-maybe)
    (remove-hook 'org-src-mode-hook 'org-edit-latex--set-TeX-master)))


;; TeX-master

(defun org-edit-latex--set-TeX-master ()
  "Set `TeX-master' variable for specific src-edit buffer."
  (when (and (file-exists-p org-edit-latex-frag-master)
             (eq major-mode 'latex-mode))
    (setq TeX-master org-edit-latex-frag-master)
    (define-key (current-local-map) [remap preview-at-point]
      'org-edit-latex-preview-at-point)))

;;;###autoload
(defun org-edit-latex-preview-at-point ()
  "Preview LaTeX at point in the edit buffer."
  (interactive)
  (let ((buffer-file-name nil))
    (preview-at-point)))

;;;###autoload
(defun org-edit-latex-create-master-maybe ()
  "Create master file based on value of variable `org-edit-latex-create-master'.

Its value should be one of the following cases:

'overwrite:    when master file already exists, overwrite it.
'ask:          will ask first before creating master file.
other non-nil: when master doesn't exist, create one.
nil:           do not create master file.
"
  (let ((master-exists-p (file-exists-p org-edit-latex-frag-master)))
    (if (and master-exists-p
             (eq org-edit-latex-create-master 'overwrite)
             (y-or-n-p "This will overwrite existing TeX-master. Are you sure?"))
        (org-edit-latex--create-master)
      (when (not master-exists-p)
        (cl-case org-edit-latex-create-master
          ('ask (when (y-or-n-p "There is no TeX-master. Do you want to create one?")
                  (org-edit-latex--create-master)))
          ('nil nil)
          (t (org-edit-latex--create-master)))))))

(defun org-edit-latex-create-auto-file ()
  "Force the creation of the AUCTeX auto file for a master
buffer. Borrowed from auctex. The original function name is
`bib-create-auto-file'"
  (interactive)
  (if (not (require 'latex))
      (error "Sorry, This is only useful if you have AUCTeX"))
  (let ((TeX-auto-save t)
        (TeX-auto-update t))

    ;; TeX-auto-write may call TeX-master-file which may fail if
    ;; TeX-header-end is unset (by LaTeX-common-initialization in latex-mode)
    (if (not TeX-header-end)
        (setq TeX-header-end LaTeX-header-end))

    (TeX-auto-write)))

(defun org-edit-latex--create-master ()
  "Create a TeX-master file. Borrowed from
`org-create-formula-image'."
  (interactive)
  (let ((latex-header
         (or
          ;; FIXME maybe I should make #+attr_latex work
          ;; (plist-get processing-info :latex-header)
          (org-latex-make-preamble
           (org-export-get-environment (org-export-get-backend 'latex))
           org-format-latex-header)))
        (texfile (expand-file-name org-edit-latex-frag-master)))
    (with-temp-file texfile
      (insert latex-header)
      (insert "\n\\begin{document}\n"
              "This is the master of LaTeX fragments.\n"
              "\n\\end{document}\n")
      (let ((latex-mode-hook nil)) (latex-mode))
      (cl-letf (((symbol-function 'buffer-file-name) (lambda () texfile)))
        (org-edit-latex-create-auto-file)))))

;;;###autoload
(defun org-edit-latex-update-master ()
  "Update TeX-master file.

This function should be called whenever you change the latex
header."
  (interactive)
  (let ((org-edit-latex-create-master 'overwrite))
    (org-edit-latex-create-master-maybe)))



(defun org-edit-latex--wrap-latex (ele)
  "Wrap latex fragment in a latex src block."
  (let* ((beg (org-element-property :begin ele))
         (end (org-element-property :end ele))
         (pb (org-element-property :post-blank ele))
         (pa (org-element-property :post-affiliated ele))
         (type (cond
                ((eq (car ele) 'latex-environment) 'environment)
                ((save-excursion
                   (goto-char beg)
                   (looking-at-p org-edit-latex-inline-beg-regexp)) 'inline)
                (t nil)))
         (pt (point)))
    (save-excursion
      (cond
       ;; latex environment
       ((eq type 'environment)
        (goto-char end)
        (when (not (and (eobp)
                        (equal 0 pb)
                        (save-excursion
                          (beginning-of-line)
                          (looking-at-p "[ \t]*\\\\end{"))))
          (forward-line (- (1+ pb)))
          (end-of-line))
        (insert "\n#+END_SRC")
        (goto-char (setq beg pa))
        (insert "#+BEGIN_SRC latex\n"))
       ;; inline latex fragment
       ((eq type 'inline)
        (goto-char (- end pb))
        (insert "}")
        (goto-char beg)
        (insert " src_latex{"))
       ;; display latex fragment
       (t
        (goto-char end)
        (insert "\n#+END_SRC")
        (goto-char beg)
        (beginning-of-line)
        (insert "#+BEGIN_SRC latex\n"))))
    (when (= pt beg) (goto-char (1+ pt)))))

(defun org-edit-latex--unwrap-latex (ele)
  "Unwrap latex fragment."
  (let* ((lang (org-element-property :language ele))
         (beg (org-element-property :begin ele))
         (end (org-element-property :end ele))
         (pa (org-element-property :post-affiliated ele))
         (pb (org-element-property :post-blank ele))
         (type (car ele)))
    (cond ((eq 'src-block type)
           (save-excursion
             (goto-char end)
             (if (and (eobp)
                      (equal 0 pb)
                      (save-excursion
                        (beginning-of-line)
                        (looking-at-p "#\\+end_src")))
                 (delete-region (point-at-bol) (point-at-eol))
               (forward-line (- (1+ pb)))
               (delete-region (point-at-bol) (1+ (point-at-eol))))
             (goto-char pa)
             (delete-region pa (1+ (point-at-eol)))))
          ;; inline src block
          ((eq 'inline-src-block type)
           (save-excursion
             ;; delete trailing "}"
             (goto-char (- end pb 1))
             (delete-char 1)
             ;; delete " src_block{", note there is a space before "src_block{"
             (goto-char (1- beg))
             (delete-char 11)))
          (t nil))))

(defun org-edit-latex--unwrap-maybe (oldfun &rest args)
  "Unwrap latex fragment only if it meets certain predicates."
  (if (and (boundp 'org-src--beg-marker)
           (let ((beg org-src--beg-marker))
             (save-excursion
               (set-buffer (marker-buffer beg))
               (goto-char beg)
               (eq 'inline-src-block (car (org-element-context))))))
      (let ((org-src--remote t))
        (funcall oldfun))
    (funcall oldfun))
  (when (and org-edit-latex-mode
             (memq org-edit-latex--before-type
                   '(latex-fragment latex-environment)))
    (org-edit-latex--unwrap-latex (org-element-context))
    (setq org-edit-latex--before-type nil)))

(defun org-edit-latex--wrap-maybe (oldfun &rest args)
  "Wrap element at point if its type is latex-fragment or
latex-environment."
  (if org-edit-latex-mode
      (let* ((ele (org-element-context))
             (type (car ele)))
        (setq org-edit-latex--before-type type)
        (if (or (eq type 'latex-fragment)
                (and (eq type 'latex-environment)
                     (save-excursion
                       (beginning-of-line)
                       (not (looking-at-p "^#\\+")))))
            (progn
              (org-edit-latex--wrap-latex ele)
              (let ((org-src-preserve-indentation t))
                (apply oldfun args)))
          (apply oldfun args)))
    (apply oldfun args)))


(provide 'org-edit-latex)
;;; org-edit-latex.el ends here
