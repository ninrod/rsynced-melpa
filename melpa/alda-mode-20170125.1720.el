;;; alda-mode.el --- A simple major mode for the musical programming language Alda

;; Copyright (C) 2016 Jay Kamat
;; Author: Jay Kamat <github@jgkamat.33mail.com>
;; Version: 0.2.1
;; Package-Version: 20170125.1720
;; Keywords: alda, highlight
;; URL: http://github.com/jgkamat/alda-mode
;; Package-Requires: ((emacs "24.0"))

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
;; This package provides syntax highlighting and basic alda integration.
;; Activate font-lock-mode to use the syntax features, and run 'alda-play-region' to play song files
;;
;;
;; Variables:
;; alda-binary-location: Set to the location of the binary executable.
;; If nil, alda-mode will search for your binary executable on your path
;; If set to a string, alda-mode will use that binary instead of 'alda' on your path.
;; Ex: (setq alda-binary-location "/usr/local/bin/alda")
;; Ex: (setq alda-binary-location nil) ;; Use default alda location
;; alda-ess-keymap: Whether to add the default ess keymap.
;; If nil, alda-mode will not add the default ess keymaps.
;; Ex: (setq alda-ess-keymap nil) ;; before (require 'alda)

;;; Constants:

(defconst +alda-output-buffer+ "*alda-output*")
(defconst +alda-output-name+ "alda-playback")
(defconst +alda-comment-str+ "#")

;;; Code:

;;; -- Region playback functions --

(defgroup Alda nil
  "Alda customization options"
  :group 'applications)

(defcustom alda-binary-location nil
  "Alda binary location for `alda-mode'.
When set to nil, will attempt to use the binary found on your $PATH."
  :type 'string
  :group 'Alda)

(defcustom alda-ess-keymap t
  "Whether to use ess keymap in alda-mode
When set to nil, will not set any ess keybindings"
  :type 'boolean
  :group 'Alda)

(defun alda-location()
  "Returns what 'alda' should be called as in the shell based on alda-binary-location or the path."
  (if alda-binary-location
    alda-binary-location
    (locate-file "alda" exec-path)))

(defun alda-server()
  "Starts an alda server in an emacs process."
  (interactive)
  (start-process-shell-command +alda-output-name+ +alda-output-buffer+ (concat (alda-location)  " server")))

(defun alda-run-cmd (cmd)
  "Plays the given cmd using alda play --code.
Argument CMD the cmd to run alda with"
  (interactive "sEnter alda command: ")
  (let ((server-down
          (if (string-match "[Ss]erver [Dd]own" (shell-command-to-string (concat (alda-location) " status")))
            (progn (message "Alda server down, starting in Emacs.") t)
            nil)))
    (if (not (alda-location))
      (message "Alda was not found on your $PATH and alda-binary-location was nil.")
      (progn
        (when server-down
          (alda-server)
          (sleep-for 2)) ;; Try to stop a race condition
        (start-process-shell-command +alda-output-name+ +alda-output-buffer+
          (concat (alda-location) " " cmd))))))

(defun alda-play-text (text)
  "Plays the specified TEXT in the alda server.
ARGUMENT TEXT The text to play with the current alda server."
  (alda-run-cmd (concat "play --code '" text "'")))

(defun alda-play-file ()
  "Plays the current buffer's file in alda."
  (interactive)
  (alda-run-cmd (concat "play --file " "\"" (buffer-file-name) "\"")))

;; TODO Come up with a replacement for the alda append command
;; alda append was deprecated, which breaks all these commands
;; Before, you could use these commands to load only parts of your file, but
;; there's no way to do this right now. Ask for a replacement for alda append!

;; (defun alda-append-text (text)
;;   "Append the specified TEXT to the alda server instance.
;; ARGUMENT TEXT The text to append to the current alda server."
;;   (alda-run-cmd (concat "append --code '" text "'")))

;; (defun alda-append-file ()
;;   "Append the current buffer's file to the alda server without playing it.
;; Argument START The start of the selection to append from.
;; Argument END The end of the selection to append from."
;;   (interactive)
;;   (alda-run-cmd (concat "append --file " "\"" (buffer-file-name) "\"")))

;; (defun alda-append-region (start end)
;;   "Append the current buffer's file to the alda server without playing it.
;; Argument START The start of the selection to append from.
;; Argument END The end of the selection to append from."
;;   (interactive "r")
;;   (if (eq start end)
;;     (message "no mark was set")
;;     (alda-append-text (buffer-substring-no-properties start end))))

(defun alda-play-region (start end)
  "Plays the current selection in alda.
Argument START The start of the selection to play from.
Argument END The end of the selection to play from."
  (interactive "r")
  (if (eq start end)
    (message "No mark was set!")
    (alda-play-text (buffer-substring-no-properties start end))))

;; If evil is found, make evil commands as well.
(eval-when-compile
  (unless (require 'evil nil 'noerror)
    ;; Evil must be sourced in order to define this macro
    (defmacro evil-define-operator (name &rest trash)
      ;; Define a dummy instead if not present.
      `(defun ,name () (interactive) (message "Evil was not present while compiling alda-mode. Recompile with evil installed!")))))

;; Macro will be expanded based on the above dummy/evil load
(evil-define-operator alda-evil-play-region (beg end type register yank-hanlder)
  "Plays the text from BEG to END"
  :move-point nil
  :repeat nil
  (interactive "<R><x><y>")
  (alda-play-region beg end))

(defun alda-stop ()
  "Stops songs from playing, and cleans up idle alda runner processes.
Because alda runs in the background, the only way to do this is with alda restart as of now."
  (interactive)
  (shell-command (concat (alda-location) " down"))
  (delete-process +alda-output-buffer+))

;;; -- Font Lock Regexes --
(let
  ;; Prevent regexes from taking up memory
  ((alda-comment-regexp "\\(#.*$\\)\\|\\(?1:(comment\\_>\\)")
    (alda-instrument-regexp "\\([a-zA-Z]\\{2\\}[A-Za-z0-9_\-]*\\)\\(\s*\\(\"[A-Za-z0-9_\-]*\"\\)\\)?:")
    (alda-voice-regexp "\\([Vv][0-9]+\\):")
    (alda-string-regexp "“\\([^ ]+?\\)”")
    (alda-timing-regexp "[a-gA-GrR][\s+-]*\\([~.0-9\s/]*\\(m?s\\)?\\)")
    (alda-repeating-regexp "\\(\\*[0-9]+\\)")
    (alda-cramming-regexp "\\({\\|}\\)")
    (alda-grouping-regexp "\\(\\[\\|\\]\\)")
    (alda-accidental-regexp "\\([a-gA-GrR]\s*[-+]+\\)")
    (alda-bar-regexp "\\(|\\)")
    (alda-set-octave-regexp "\\(o[0-9]+\\)")
    (alda-shift-octave-regexp "\\(>\\|<\\)")
    (alda-variable-regexp "\\(([a-zA-Z-]+!?\s+\\(\\([0-9]+\\)\\|\\(\\[\\(:[a-zA-Z]+\s?\\)+\\]\\)\\))\\)")
    (alda-markers-regexp "\\([@%][a-zA-Z]\\{2\\}[a-zA-Z0-9()+-]*\\)"))

  (defvar alda-highlights nil
    "Font lock highlights for alda-mode")
  (setq alda-highlights
    `((,alda-comment-regexp . (1 font-lock-comment-face))
       (,alda-bar-regexp . (1 font-lock-comment-face))
       (,alda-voice-regexp . (1 font-lock-function-name-face))
       (,alda-instrument-regexp . (1 font-lock-type-face))
       (,alda-string-regexp . (1 font-lock-string-face))
       (,alda-variable-regexp . (1 font-lock-variable-name-face))
       (,alda-set-octave-regexp . (1 font-lock-constant-face))
       (,alda-shift-octave-regexp . (1 font-lock-constant-face))
       (,alda-markers-regexp . (1 font-lock-builtin-face))
       (,alda-timing-regexp . (1 font-lock-builtin-face))
       (,alda-repeating-regexp . (1 font-lock-builtin-face))
       (,alda-cramming-regexp . (1 font-lock-builtin-face))
       (,alda-grouping-regexp . (1 font-lock-builtin-face))
       (,alda-accidental-regexp . (1 font-lock-preprocessor-face)))))

;;; -- Indention code --

;; A duplicate of asm-mode.el with changes
;; changes were made to the naming convention and to how the labels are calculated.
(defun alda-indent-line ()
  "Auto-indent the current line."
  (interactive)
  (let* ((savep (point))
          (indent (condition-case nil
                    (save-excursion
                      (forward-line 0)
                      (skip-chars-forward " \t")
                      (if (>= (point) savep) (setq savep nil))
                      (max (alda-calculate-indentation) 0))
                    (error 0))))
    (if savep
      (save-excursion (indent-line-to indent))
      (indent-line-to indent))))

(defun alda-indent-prev-level ()
  "Indent this line to the indention level of the previous non-whitespace line."
  (save-excursion
    (forward-line -1)
    (while (and
             (not (eq (point) (point-min))) ;; Point at start of bufffer
             ;; Point has a empty line
             (let ((match-str (buffer-substring-no-properties (line-beginning-position) (line-end-position))))
               (or (string-match "^\\s-*$" match-str)) (eq 0 (length match-str))))
      (forward-line -1))
    (current-indentation)))


(defun alda-calculate-indentation ()
  "Calculates indentation for `alda-mode' code."
  (or
    ;; Flush labels to the left margin.
    (and (looking-at "[A-Za-z0-9\" \\t-]+:\\s-*") 0)
    ;; All comments indention are the previous line's indention.
    (and (looking-at +alda-comment-str+) (alda-indent-prev-level))
    ;; The rest goes at the first tab stop.
    (or (indent-next-tab-stop 0))))

(defun alda-colon ()
  "Insert a colon; if it follows a label, delete the label's indentation."
  (interactive)
  (let ((labelp nil))
    (save-excursion
      (skip-chars-backward "A-Za-z\"\s\t")
      (if (setq labelp (bolp)) (delete-horizontal-space)))
    (call-interactively 'self-insert-command)
    (when labelp
      (delete-horizontal-space)
      (tab-to-tab-stop))))

(defun alda-play-block ()
  (interactive)
  (save-excursion
    (mark-paragraph)
    (alda-play-region (region-beginning) (region-end))))

(defun alda-play-line ()
  (interactive)
  (alda-play-region (line-beginning-position) (line-end-position)))

(defun alda-play-buffer ()
  (interactive)
  (alda-play-text (buffer-string)))

;;; -- Alda Keymaps --
;; TODO determine standard keymap for alda-mode

(defvar alda-mode-map nil "Keymap for `alda-mode'.")
(when (not alda-mode-map) ; if it is not already defined

  ;; assign command to keys
  (setq alda-mode-map (make-sparse-keymap))
  (define-key alda-mode-map (kbd ":") 'alda-colon)

  (define-key alda-mode-map [menu-bar alda-mode] (cons "Alda" (make-sparse-keymap)))
  (define-key alda-mode-map [menu-bar alda-mode alda-colon]
    '(menu-item "Insert Colon" alda-colon
       :help "Insert a colon; if it follows a label, delete the label's indentation"))

  ;; Add alda-ess-keymap if requested
  (when alda-ess-keymap
    (define-key alda-mode-map "\C-c\C-r" 'alda-play-region)
    (define-key alda-mode-map "\C-c\C-c" 'alda-play-block)
    (define-key alda-mode-map "\C-c\C-n" 'alda-play-line)
    (define-key alda-mode-map "\C-c\C-b" 'alda-play-buffer)))


;;; -- Alda Mode Definition --

;;;###autoload
(define-derived-mode alda-mode prog-mode
  "Alda"
  "A major mode for alda-lang, providing syntax highlighting and basic indention."

  ;; Set alda comments
  (setq comment-start +alda-comment-str+)
  (setq comment-padding " ")
  (setq comment-start-skip (concat +alda-comment-str+ "\\s-*"))
  (setq comment-multi-line (concat +alda-comment-str+ " "))
  ;; Comments should use the indention of the last line
  (setq comment-indent-function #'alda-indent-prev-level)

  ;; Set custom mappings
  (use-local-map alda-mode-map)
  (setq indent-line-function 'alda-indent-line)

  ;; Set alda highlighting
  (setq font-lock-defaults '(alda-highlights)))

;; Open alda files in alda-mode
;;;###autoload
(add-to-list 'auto-mode-alist '("\\.alda\\'" . alda-mode))

(provide 'alda-mode)

;;; alda-mode.el ends here
