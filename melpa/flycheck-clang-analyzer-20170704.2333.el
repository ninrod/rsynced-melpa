;;; flycheck-clang-analyzer.el --- Integrate Clang Analyzer with flycheck

;; Copyright (c) 2017 Alex Murray

;; Author: Alex Murray <murray.alex@gmail.com>
;; Maintainer: Alex Murray <murray.alex@gmail.com>
;; URL: https://github.com/alexmurray/flycheck-clang-analyzer
;; Package-Version: 20170704.2333
;; Version: 0.3
;; Package-Requires: ((flycheck "0.24") (emacs "24.4"))

;; This file is not part of GNU Emacs.

;; This program is free software: you can redistribute it and/or modify
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

;; This packages integrates the Clang Analyzer `clang --analyze` tool with
;; flycheck to automatically detect any new defects in your code on the fly.
;;
;; It depends on and leverages either the existing c/c++-clang flycheck
;; backend, or `irony-mode' or `rtags' to provide compilation arguments etc and
;; so provides automatic static analysis with zero setup.
;;
;; Automatically chains itself as the next checker after c/c++-clang, irony and
;; rtags flycheck checkers.

;;;; Setup

;; (with-eval-after-load 'flycheck
;;    (require 'flycheck-clang-analyzer)
;;    (flycheck-clang-analyzer-setup))

;;; Code:
(require 'cl-lib)
(require 'flycheck)

(defvar flycheck-clang-analyzer--backends
  '(((:name . irony)
     (:active . flycheck-clang-analyzer--irony-active)
     (:get-compile-options . flycheck-clang-analyzer--irony-get-compile-options)
     (:get-default-directory . flycheck-clang-analyzer--irony-get-default-directory))
    ((:name . rtags)
     (:active . flycheck-clang-analyzer--rtags-active)
     (:get-compile-options . flycheck-clang-analyzer--rtags-get-compile-options)
     (:get-default-directory . flycheck-clang-analyzer--rtags-get-default-directory))
    ((:name . flycheck-clang)
     (:active . flycheck-clang-analyzer--flycheck-clang-active)
     (:get-compile-options . flycheck-clang-analyzer--flycheck-clang-get-compile-options)
     (:get-default-directory . flycheck-clang-analyzer--flycheck-clang-get-default-directory))))

(defun flycheck-clang-analyzer--backend ()
  "Get current backend which is active."
  (car (cl-remove-if-not (lambda (backend) (funcall (cdr (assoc :active backend))))
                         flycheck-clang-analyzer--backends)))

(defun flycheck-clang-analyzer--buffer-is-header ()
  "Determine if current buffer is a header file."
  (when (buffer-file-name)
    (let ((extension (file-name-extension (buffer-file-name))))
      ;; capture .h, .hpp, .hxx etc - all start with h
      (string-equal "h" (substring extension 0 1)))))

(defun flycheck-clang-analyzer--predicate ()
  "Return t when should be active, nil if not."
  (and (not (flycheck-clang-analyzer--buffer-is-header))
       (flycheck-clang-analyzer--backend)))

;; irony
(defun flycheck-clang-analyzer--irony-active ()
  "Check if 'irony-mode' is available and active."
  (and (fboundp 'irony-mode) (boundp 'irony-mode) irony-mode))

(defun flycheck-clang-analyzer--irony-get-compile-options ()
  "Get compile options from irony."
  (if (fboundp 'irony-cdb--autodetect-compile-options)
      (nth 1 (irony-cdb--autodetect-compile-options))))

(defun flycheck-clang-analyzer--irony-get-default-directory ()
  "Get default directory from irony."
  (if (fboundp 'irony-cdb--autodetect-compile-options)
      (nth 2 (irony-cdb--autodetect-compile-options))))

;; rtags
(defun flycheck-clang-analyzer--rtags-active ()
  "Check if rtags is available and active."
  (and (boundp 'rtags-enabled)
       rtags-enabled
       (fboundp 'rtags-is-running)
       (rtags-is-running)))

(defun flycheck-clang-analyzer--valid-compilation-flag-p (flag)
  "Check whether FLAG is a valid compilation flag for clang --analyze."
  (and (string= (substring flag 0 1) "-")
       (not (string= flag "-o"))
       (not (string= flag "-c"))))

(defun flycheck-clang-analyzer--rtags-get-compile-options ()
  "Get compile options from rtags."
  (if (fboundp 'rtags-compilation-flags)
      (cl-remove-if-not #'flycheck-clang-analyzer--valid-compilation-flag-p
                        (rtags-compilation-flags))))

(defun flycheck-clang-analyzer--rtags-get-default-directory ()
  "Get default directory from rtags."
  (if (boundp 'rtags-current-project)
      rtags-current-project))

;; flycheck-clang
(defun flycheck-clang-analyzer--flycheck-clang-active ()
  "Get active from flycheck-clang."
  t)

(defun flycheck-clang-analyzer--flycheck-clang-get-default-directory ()
  "Get default directory from flycheck-clang."
  default-directory)

(defun flycheck-clang-analyzer--flycheck-clang-get-compile-options ()
  "Get compile options from flycheck clang backend."
  (append (when flycheck-clang-language-standard (list (concat "-std=" flycheck-clang-language-standard)))
          (when flycheck-clang-standard-library (list (concat "-stdlib=" flycheck-clang-standard-library)))
          (when flycheck-clang-ms-extensions (list "-fms-extensions"))
          (when flycheck-clang-no-exceptions (list "-fno-exceptions"))
          (when flycheck-clang-no-rtti (list "-fno-rtti"))
          (when flycheck-clang-blocks (list "-fblocks"))
          (apply #'append (mapcar (lambda (i) (list "-include" i)) flycheck-clang-includes))
          (mapcar (lambda (i) (concat "-D" i)) flycheck-clang-definitions)
          (apply #'append (mapcar (lambda (i) (list "-I" i)) flycheck-clang-include-path))
          flycheck-clang-args))

(defun flycheck-clang-analyzer--get-compile-options ()
  "Get compile options for clang."
  (let ((backend (flycheck-clang-analyzer--backend)))
    (when backend
      (funcall (cdr (assoc :get-compile-options backend))))))

(defun flycheck-clang-analyzer--get-default-directory (_checker)
  "Get default directory for clang."
  (let ((backend (flycheck-clang-analyzer--backend)))
    (when backend
      (funcall (cdr (assoc :get-default-directory backend))))))

(defun flycheck-clang-analyzer--verify (_checker)
  "Verify CHECKER."
  (let ((backend (flycheck-clang-analyzer--backend)))
    (list
     (flycheck-verification-result-new
      :label "Backend"
      :message (format "%s" (if backend (cdr (assoc :name backend))
                              "No active supported backend."))
      :face (if backend 'success '(bold error))))))

(flycheck-define-checker clang-analyzer
  "A checker using clang-analyzer.

See `https://github.com/alexmurray/clang-analyzer/'."
  :command ("clang"
            "--analyze"
            (eval (flycheck-clang-analyzer--get-compile-options))
            ;; disable after compdb options to ensure stay disabled
            "-fno-color-diagnostics" ; don't include color in output
            "-fno-caret-diagnostics" ; don't indicate location in output
            "-fno-diagnostics-show-option" ; don't show warning group
            "-Xanalyzer" "-analyzer-output=text"
            source-inplace)
  :predicate flycheck-clang-analyzer--predicate
  :working-directory flycheck-clang-analyzer--get-default-directory
  :verify flycheck-clang-analyzer--verify
  :error-patterns ((warning line-start (file-name) ":" line ":" column
                            ": warning: " (optional (message))
                            line-end))
  :error-filter
  (lambda (errors)
    (let ((errors (flycheck-sanitize-errors errors)))
      (dolist (err errors)
        ;; Clang will output empty messages for #error/#warning pragmas without
        ;; messages.  We fill these empty errors with a dummy message to get
        ;; them past our error filtering
        (setf (flycheck-error-message err)
              (or (flycheck-error-message err) "no message")))
      (flycheck-fold-include-levels errors "In file included from")))
  :modes (c-mode c++-mode objc-mode))

;;;###autoload
(defun flycheck-clang-analyzer-setup ()
  "Setup flycheck-clang-analyzer.

Add `clang-analyzer' to `flycheck-checkers'."
  (interactive)
  ;; append to list and chain after existing checkers
  (add-to-list 'flycheck-checkers 'clang-analyzer t)
  (with-eval-after-load 'flycheck-irony
    (flycheck-add-next-checker 'irony '(warning . clang-analyzer)))
  (with-eval-after-load 'flycheck-rtags
    (flycheck-add-next-checker 'rtags '(warning . clang-analyzer)))
  (with-eval-after-load 'flycheck
    (flycheck-add-next-checker 'c/c++-clang '(warning . clang-analyzer))))

(provide 'flycheck-clang-analyzer)

;;; flycheck-clang-analyzer.el ends here
