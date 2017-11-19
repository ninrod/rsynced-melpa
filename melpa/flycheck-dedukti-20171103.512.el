;;; flycheck-dedukti.el --- Flycheck integration of Dedukti

;; Copyright 2014 Raphaël Cauderlier

;; Author: Raphaël Cauderlier
;; Version: 0.1
;; Package-Version: 20171103.512
;; License: CeCILL-B
;; Package-Requires: ((flycheck "0.19") (dedukti-mode "0.1"))
;; Keywords: convenience languages tools flycheck dedukti
;; URL: https://github.com/rafoo/flycheck-dedukti

;;; Commentary:
;; This file defines a flycheck checker based on Dedukti type checker dkcheck.
;; Dedukti is a type checker for the lambda-Pi-calculus modulo.
;; It is a free software under the CeCILL-B license.
;; Dedukti is available at the following url:
;; <https://www.rocq.inria.fr/deducteam/Dedukti/>
;; Flycheck is an on-the-fly syntax checker for GNU Emacs 24

;;; Configuration
;; To enable this checker in all files visited by dedukti-mode, add
;; the following code to your Emacs configuration file:
;;
;; (eval-after-load 'dedukti-mode
;;   '(add-hook 'dedukti-mode-hook 'flycheck-dedukti-hook))

;;; Code:

(require 'flycheck)
(require 'dedukti-mode)

(flycheck-define-checker dedukti
  "Dedukti type checker."
  :command ("dkcheck"
            (eval dedukti-check-options)
            source-inplace)
  :error-patterns
  ((warning
    line-start
    "WARNING file:" (file-name)
    " line:" line
    " column:" column
    (message) line-end)
   (error
    line-start
    "ERROR file:" (file-name)
    " line:" line
    " column:" column
    (message) line-end)
   (warning
    line-start
    "WARNING line:" line
    " column:" column
    (message) line-end)
   (error
    line-start
    "ERROR line:" line
    " column:" column
    (message) line-end))
  :modes dedukti-mode)

(add-to-list 'flycheck-checkers 'dedukti)

;;;###autoload
(defun flycheck-dedukti-hook ()
  "Hook to activate flycheck in a dedukti-mode buffers.

To activate flycheck in all dedukti-mode buffers, add this hook
to `dedukti-mode-hook' like this:

(eval-after-load 'dedukti-mode
  '(add-hook 'dedukti-mode-hook 'flycheck-dedukti-hook))"
  (flycheck-select-checker 'dedukti)
  (flycheck-mode 1))

(provide 'flycheck-dedukti)
;;; flycheck-dedukti.el ends here
