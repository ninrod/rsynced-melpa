;;; xclip.el --- Copy&paste GUI clipboard from text terminal  -*- lexical-binding:t -*-

;; Copyright (C) 2007, 2012, 2013, 2017, 2018  Free Software Foundation, Inc.

;; Author: Leo Liu <sdl.web@gmail.com>
;; Keywords: convenience, tools
;; Created: 2007-12-30
;; Version: 1.6

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

;; This package allows Emacs to copy to and paste from the GUI clipboard
;; when running in text terminal.
;;
;; It relies on external command-line tools for that, which you may need
;; to install in order for the package to work.
;; More specifically, it can use the following tools:
;; - Under X11: `xclip' or `xsel' (http://xclip.sourceforge.net and
;;   http://www.vergenet.net/~conrad/software/xsel/ respectively).
;; - MacOS: `pbpaste/pbcopy'
;; - Cygwin: `getclip/putclip'
;;
;; To use, just add (xclip-mode 1) to your ~/.emacs or do `M-x clip-mode'
;; after which the usual kill/yank commands will use the GUI selections
;; according to `select-enable-clipboard/primary'.

;; An alternative package for use under X11 is
;; [Gpastel](https://gitlab.petton.fr/DamienCassou/gpastel), which uses
;; [GPaste](https://github.com/Keruspe/GPaste/) rather than Xclip and hooks
;; into Emacs in a different way.  AFAICT it currently only supports
;; copy/pasting from an external application to Emacs and not from Emacs to
;; another application (for which it relies on the default code).

;;; Code:

(defgroup xclip ()
  "Copy&paste GUI clipboard from text terminal."
  :group 'killing)

(defcustom xclip-select-enable-clipboard t
  "Non-nil means cutting and pasting uses the clipboard.
This is in addition to, but in preference to, the primary selection."
  :type 'boolean)
(make-obsolete 'xclip-select-enable-clipboard
               'select-enable-clipboard "Emacs-25")

(defvar xclip-use-pbcopy&paste (and (eq system-type 'darwin)
                                    (executable-find "pbcopy")
                                    t)
  "Non-nil means using pbcopy and pbpaste instead of xclip.
If non-nil `xclip-program' is ignored.")
(make-obsolete 'xclip-use-pbcopy&paste 'xclip-method "xclip-1.5")

(defcustom xclip-method
   (if xclip-use-pbcopy&paste 'pbpaste
     (or
      (and (executable-find "xclip") 'xclip)
      (and (executable-find "xsel") 'xsel)
      (and (eq system-type 'cygwin) (executable-find "getclip") 'getclip)
      'xclip))
  "Method to use to access the GUI's clipboard.
Can be one of `pbpaste' for MacOS, `xclip' or `xsel' for X11,
and `getclip' under Cygwin."
  :type '(choice
          (const :tag "MacOS: pbcopy/pbpaste" pbpaste)
          (const :tag "X11: xclip" xclip)))

(defcustom xclip-program (symbol-name xclip-method)
  "Name of the clipboard access command."
  :type 'string)

;;;; Core functions.

(defun xclip-set-selection (type data)
  "TYPE is a symbol: primary, secondary and clipboard.

See also `x-set-selection'."
  (let* ((process-connection-type nil)
         (proc
          (pcase xclip-method
            (`pbpaste
             (when (memq type '(clipboard CLIPBOARD))
               (start-process
                "pbcopy" nil
                (replace-regexp-in-string "\\(.*\\)pbpaste" "\\1pbcopy"
                                          xclip-program 'fixedcase))))
            (`getclip
             (when (memq type '(clipboard CLIPBOARD))
               (start-process
                "putclip" nil
                (replace-regexp-in-string "\\(.*\\)getclip" "\\1putclip"
                                          xclip-program 'fixedcase))))
            (`xclip
             (when (getenv "DISPLAY")
               (start-process "xclip" nil xclip-program
                              "-selection" (symbol-name type))))
            (`xsel
             (when (and (getenv "DISPLAY")
                        (memq type '(clipboard CLIPBOARD
                                     primary PRIMARY
                                     secondary SECONDARY)))
               (start-process
                "xsel" nil xclip-program
                "-i" (concat "--" (downcase (symbol-name type))))))
            (method (error "Unknown `xclip-method': %S" method)))))
    (when proc
      (process-send-string proc data)
      (process-send-eof proc))
    data))

(defun xclip-get-selection (type)
  "TYPE is a symbol: primary, secondary and clipboard."
  (with-output-to-string
    (pcase xclip-method
      (`pbpaste
       (when (memq type '(clipboard CLIPBOARD))
         (process-file xclip-program nil standard-output nil "-Prefer" "txt")))
      (`getclip
       (when (memq type '(clipboard CLIPBOARD))
         (process-file xclip-program nil standard-output nil)))
      (`xclip
       (when (getenv "DISPLAY")
         (process-file xclip-program nil standard-output nil
                       "-o" "-selection" (symbol-name type))))
      (`xsel
       (when (and (getenv "DISPLAY")
                  (memq type '(clipboard CLIPBOARD
                               primary PRIMARY
                               secondary SECONDARY)))
         (process-file xclip-program nil standard-output nil
                       "-o" (concat "--" (downcase (symbol-name type))))))
      (method (error "Unknown `xclip-method': %S" method)))))

;;;###autoload
(define-minor-mode xclip-mode
  "Minor mode to use the `xclip' program to copy&paste."
  :global t
  (remove-hook 'terminal-init-xterm-hook #'xclip--setup)
  (when xclip-mode
    (unless (executable-find xclip-program)
      (setq xclip-mode nil)
      (signal 'file-error (list "Searching for program"
				xclip-program "no such file")))
    (when (< emacs-major-version 25)
      ;; NOTE: See `tty-run-terminal-initialization' and term/README
      (add-hook 'terminal-init-xterm-hook #'xclip--setup))))

;;;; Glue code for Emacs ≥ 25

(eval-when-compile
  (defmacro xclip--if (test then &rest else)
    ;; FIXME: copy&pasted from AUCTeX's tex.el.
    "Execute THEN if TEST is non-nil and ELSE otherwise.

TEST is assumed to be \"monotone\" in Emacs versions: if it is non-nil in
Emacs-NN, it should also always be non-nil in Emacs≥NN.

The macro takes care of byte-compilation issues that might affect THEN,
where the byte-code for it could signal an error if it has been compiled with
Emacs-NN and is then later run by Emacs>NN."
    (declare (indent 2) (debug (symbolp form &rest form)))
    (if (eval test t)    ;If test is already true at compile-time, just use it.
        then
      `(if ,test                        ;Else, check at run-time.
	   (eval ',then)                ;If it does, then run the then code.
         ,@else))))                     ;Otherwise, run the else code.

(xclip--if (>= emacs-major-version 25)
    (progn
      ;; FIXME: implement the methods for gui-backend-selection-owner-p
      ;; and gui-backend-selection-exists-p.  Not sure about pbcopy, but at
      ;; least with xcopy, gui-backend-selection-owner-p should just require us
      ;; to use "-silent" and keep track of the liveness of the subprocess.

      (cl-defmethod gui-backend-get-selection (selection-symbol _target-type
                                               &context (window-system nil))
        (if (not xclip-mode)
            (cl-call-next-method)
          (xclip-get-selection selection-symbol)))

      (cl-defmethod gui-backend-set-selection (selection-symbol value
                                               &context (window-system nil))
        (if (not xclip-mode)
            (cl-call-next-method)
          (xclip-set-selection selection-symbol value)
          nil))

      ;; BIG UGLY HACK!
      ;; xterm.el has a defmethod to use some (poorly supported) escape
      ;; sequences (code named OSC 52) for clipboard interaction, and enables
      ;; it by default.
      ;; Problem is, that its defmethod takes precedence over our defmethod,
      ;; so we need to disable it in order to be called.
      (cl-defmethod gui-backend-set-selection :extra "xclip-override"
          (selection-symbol value
           &context (window-system nil)
                    ((terminal-parameter nil 'xterm--set-selection) (eql t)))
        ;; Disable this method which doesn't work anyway in 99% of the cases!
        (setf (terminal-parameter nil 'xterm--set-selection) nil)
        ;; Try again!
        (gui-backend-set-selection selection-symbol value)))

;;;; Glue code for Emacs < 25

  (defvar xclip-last-selected-text-clipboard nil
    "The value of the CLIPBOARD X selection from xclip.")

  (defvar xclip-last-selected-text-primary nil
    "The value of the PRIMARY X selection from xclip.")

  (defun xclip-select-text (text)
    "See `x-select-text'."
    (xclip-set-selection 'primary text)
    (setq xclip-last-selected-text-primary text)
    (when xclip-select-enable-clipboard
      (xclip-set-selection 'clipboard text)
      (setq xclip-last-selected-text-clipboard text)))

  (defun xclip-selection-value ()
    "See `x-selection-value'."
    (let ((clip-text (when xclip-select-enable-clipboard
                       (xclip-get-selection 'CLIPBOARD))))
      (setq clip-text
            (cond                       ; Check clipboard selection.
             ((or (not clip-text) (string= clip-text ""))
              (setq xclip-last-selected-text-clipboard nil))
             ((eq clip-text xclip-last-selected-text-clipboard)
              nil)
             ((string= clip-text xclip-last-selected-text-clipboard)
              ;; Record the newer string so subsequent calls can use the
              ;; `eq' test.
              (setq xclip-last-selected-text-clipboard clip-text)
              nil)
             (t (setq xclip-last-selected-text-clipboard clip-text))))
      (or clip-text
          (when (and (memq xclip-method '(xsel xclip)) (getenv "DISPLAY"))
            (let ((primary-text (with-output-to-string
                                  (process-file xclip-program nil
                                                standard-output nil "-o"))))
              (setq primary-text
                    (cond               ; Check primary selection.
                     ((or (not primary-text) (string= primary-text ""))
                      (setq xclip-last-selected-text-primary nil))
                     ((eq primary-text xclip-last-selected-text-primary)
                      nil)
                     ((string= primary-text xclip-last-selected-text-primary)
                      ;; Record the newer string so subsequent calls can
                      ;; use the `eq' test.
                      (setq xclip-last-selected-text-primary primary-text)
                      nil)
                     (t (setq xclip-last-selected-text-primary primary-text))))
              primary-text)))))

  (defun xclip--setup ()
    (setq interprogram-cut-function 'xclip-select-text)
    (setq interprogram-paste-function 'xclip-selection-value)))

;;;; ChangeLog:

;; 2018-12-11  Stefan Monnier  <monnier@iro.umontreal.ca>
;; 
;; 	* xclip/xclip.el: Make it work again on Emacs<25
;; 
;; 	(xclip-set-selection, xclip-get-selection): Avoid pcase's quote.
;; 	(xclip--if): Generalize xclip--if-macro-fboundp. Use it to better test
;; 	whether the cl-generic features are available.
;; 
;; 2018-11-18  Stefan Monnier  <monnier@iro.umontreal.ca>
;; 
;; 	* xclip/xclip.el: Fix bug#33399
;; 
;; 	(xclip-set-selection): Don't use start-file-process.
;; 
;; 2018-08-23  Stefan Monnier  <monnier@iro.umontreal.ca>
;; 
;; 	* xclip/xclip.el: Add support for `xsel` and Cygwin's `getclip`
;; 
;; 	Move Emacs<25 code to the end.
;; 	(xclip): New group.
;; 	(xclip-program): Change default to depend on xclip-use-pbcopy&paste. 
;; 	Move accordingly.
;; 	(xclip-select-enable-clipboard): Mark as obsolete.
;; 	(xclip-use-pbcopy&paste): Make it into a defvar.  Mark as obsolete.
;; 	(xclip-method): New defcustom.
;; 	(xclip-set-selection, xclip-get-selection): Use it.
;; 	(xclip-mode): Simplify.
;; 
;; 2017-11-08  Stefan Monnier  <monnier@iro.umontreal.ca>
;; 
;; 	* xclip/xclip.el: Use gui-backend-*-selection in Emacs≥25
;; 
;; 	(xclip-set-selection) <pbcopy>: Don't set the clipboard when primary is
;; 	requested.
;; 	(xclip-get-selection): New function extracted from
;; 	xclip-selection-value.
;; 	(turn-on-xclip): Rename to xclip--setup.
;; 	(xclip-mode): Don't use xclip--setup in Emacs≥25. Disable the mode is
;; 	xclip-program is not found.
;; 	(xclip--if-macro-fboundp): New macro.
;; 	(gui-backend-get-selection, gui-backend-set-selection): New methods.
;; 
;; 2013-09-06  Leo Liu  <sdl.web@gmail.com>
;; 
;; 	* xclip.el: Fix last change
;; 
;; 2013-09-06  Leo Liu  <sdl.web@gmail.com>
;; 
;; 	* xclip.el: Use pbcopy and pbpaste if available
;; 
;; 	(xclip-use-pbcopy&paste): New variable.
;; 	(xclip-set-selection, xclip-selection-value, xclip-mode): Use it.
;; 
;; 2013-09-05  Leo Liu  <sdl.web@gmail.com>
;; 
;; 	* xclip.el: Some cleanups and fix copyright years.
;; 
;; 	(xclip-program, xclip-select-enable-clipboard): Use defcustom.
;; 	(xclip-select-text): Cleanup.
;; 	(turn-off-xclip): Remove.
;; 	(xclip-mode): Check xclip-program here.
;; 
;; 2012-02-05  Stefan Monnier  <monnier@iro.umontreal.ca>
;; 
;; 	* xclip.el: Better follow conventions. Fix up copyright notice.
;; 	(xclip-program): Make it work in the usual way.
;; 	(xclip-set-selection, xclip-selection-value): Obey xclip-program.
;; 	(turn-on-xclip, turn-off-xclip): Don't autoload, not interactive.
;; 	(xclip-mode): New minor mode to avoid enabling it unconditionally.
;; 
;; 2012-02-05  Leo Liu  <sdl.web@gmail.com>
;; 
;; 	Add xclip.el.
;; 



(provide 'xclip)
;;; xclip.el ends here
