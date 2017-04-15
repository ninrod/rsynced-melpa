;;; context-coloring.el --- Highlight by scope  -*- lexical-binding: t; -*-

;; Copyright (C) 2014-2015  Free Software Foundation, Inc.

;; Author: Jackson Ray Hamilton <jackson@jacksonrayhamilton.com>
;; Version: 6.2.1
;; Keywords: convenience faces tools
;; Homepage: https://github.com/jacksonrayhamilton/context-coloring
;; Package-Requires: ((emacs "24") (js2-mode "20150126"))

;; This file is part of GNU Emacs.

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

;; Highlights code by scope.  Top-level scopes are one color, second-level
;; scopes are another color, and so on.  Variables retain the color of the scope
;; in which they are defined.  A variable defined in an outer scope referenced
;; by an inner scope is colored the same as the outer scope.

;; By default, comments and strings are still highlighted syntactically.

;; To use with js2-mode, add the following to your init file:

;; (require 'context-coloring)
;; (add-hook 'js2-mode-hook 'context-coloring-mode)

;; To use with js-mode or js3-mode, install Node.js 0.10+ and the scopifier
;; executable:

;; $ npm install -g scopifier

;;; Code:

(require 'js2-mode)


;;; Local variables

(defvar-local context-coloring-buffer nil
  "Reference to this buffer (for timers).")


;;; Utilities

(defun context-coloring-join (strings delimiter)
  "Join a list of STRINGS with the string DELIMITER."
  (mapconcat 'identity strings delimiter))

(defsubst context-coloring-trim-right (string)
  "Remove leading whitespace from STRING."
  (if (string-match "[ \t\n\r]+\\'" string)
      (replace-match "" t t string)
    string))

(defsubst context-coloring-trim-left (string)
  "Remove trailing whitespace from STRING."
  (if (string-match "\\`[ \t\n\r]+" string)
      (replace-match "" t t string)
    string))

(defsubst context-coloring-trim (string)
  "Remove leading and trailing whitespace from STRING."
  (context-coloring-trim-left (context-coloring-trim-right string)))


;;; Faces

(defun context-coloring-defface (level tty light dark)
  "Define a face for LEVEL with colors for TTY, LIGHT and DARK
backgrounds."
  (let ((face (intern (format "context-coloring-level-%s-face" level)))
        (doc (format "Context coloring face, level %s." level)))
    (custom-declare-face
     face
     `((((type tty)) (:foreground ,tty))
       (((background light)) (:foreground ,light))
       (((background dark)) (:foreground ,dark)))
     doc
     :group 'context-coloring)))

(defun context-coloring-defface-neutral (level)
  "Define a face for LEVEL with the default neutral colors."
  (context-coloring-defface level nil "#3f3f3f" "#cdcdcd"))

(context-coloring-defface 0 nil       "#000000" "#ffffff")
(context-coloring-defface 1 "yellow"  "#008b8b" "#00ffff")
(context-coloring-defface 2 "green"   "#0000ff" "#87cefa")
(context-coloring-defface 3 "cyan"    "#483d8b" "#b0c4de")
(context-coloring-defface 4 "blue"    "#a020f0" "#eedd82")
(context-coloring-defface 5 "magenta" "#a0522d" "#98fb98")
(context-coloring-defface 6 "red"     "#228b22" "#7fffd4")
(context-coloring-defface-neutral 7)

(defvar context-coloring-maximum-face nil
  "Index of the highest face available for coloring.")

(defvar context-coloring-original-maximum-face nil
  "Fallback value for `context-coloring-maximum-face' when all
  themes have been disabled.")

(setq context-coloring-maximum-face 7)

(setq context-coloring-original-maximum-face
      context-coloring-maximum-face)

;; Theme authors can have up to 26 levels: 1 (0th) for globals, 24 (1st-24th)
;; for nested levels, and 1 (25th) for infinity.
(dotimes (number 18)
  (context-coloring-defface-neutral (+ number context-coloring-maximum-face 1)))


;;; Face functions

(defsubst context-coloring-level-face (level)
  "Return the symbol for a face with LEVEL."
  ;; `concat' is faster than `format' here.
  (intern-soft
   (concat "context-coloring-level-" (number-to-string level) "-face")))

(defsubst context-coloring-bounded-level-face (level)
  "Return the symbol for a face with LEVEL, bounded by
`context-coloring-maximum-face'."
  (context-coloring-level-face (min level context-coloring-maximum-face)))


;;; Colorization utilities

(defsubst context-coloring-colorize-region (start end level)
  "Color characters from the 1-indexed START point (inclusive) to
the END point (exclusive) with the face corresponding to LEVEL."
  (add-text-properties
   start
   end
   `(face ,(context-coloring-bounded-level-face level))))

(defcustom context-coloring-comments-and-strings nil
  "If non-nil, also color comments and strings using `font-lock'."
  :group 'context-coloring)

(make-obsolete-variable
 'context-coloring-comments-and-strings
 "use `context-coloring-syntactic-comments' and
 `context-coloring-syntactic-strings' instead."
 "6.1.0")

(defcustom context-coloring-syntactic-comments t
  "If non-nil, also color comments using `font-lock'."
  :group 'context-coloring)

(defcustom context-coloring-syntactic-strings t
  "If non-nil, also color strings using `font-lock'."
  :group 'context-coloring)

(defun context-coloring-font-lock-syntactic-comment-function (state)
  "Tell `font-lock' to color a comment but not a string."
  (if (nth 3 state) nil font-lock-comment-face))

(defun context-coloring-font-lock-syntactic-string-function (state)
  "Tell `font-lock' to color a string but not a comment."
  (if (nth 3 state) font-lock-string-face nil))

(defsubst context-coloring-maybe-colorize-comments-and-strings ()
  "Color the current buffer's comments and strings if
`context-coloring-comments-and-strings' is non-nil."
  (when (or context-coloring-comments-and-strings
            context-coloring-syntactic-comments
            context-coloring-syntactic-strings)
    (let ((old-function font-lock-syntactic-face-function)
          saved-function-p)
      (cond
       ((and context-coloring-syntactic-comments
             (not context-coloring-syntactic-strings))
        (setq font-lock-syntactic-face-function
              'context-coloring-font-lock-syntactic-comment-function)
        (setq saved-function-p t))
       ((and context-coloring-syntactic-strings
             (not context-coloring-syntactic-comments))
        (setq font-lock-syntactic-face-function
              'context-coloring-font-lock-syntactic-string-function)
        (setq saved-function-p t)))
      (save-excursion
        (font-lock-fontify-syntactically-region (point-min) (point-max)))
      (when saved-function-p
        (setq font-lock-syntactic-face-function old-function)))))


;;; js2-mode colorization

(defvar-local context-coloring-js2-scope-level-hash-table nil
  "Associate `js2-scope' structures and with their scope
  levels.")

(defcustom context-coloring-js-block-scopes nil
  "If non-nil, also color block scopes in the scope hierarchy in JavaScript.

The block-scoped `let' and `const' are introduced in ES6.  Enable
this for ES6 code; disable it elsewhere.

Supported modes: `js2-mode'"
  :group 'context-coloring)

(defsubst context-coloring-js2-scope-level (scope)
  "Return the level of SCOPE."
  (cond ((gethash scope context-coloring-js2-scope-level-hash-table))
        (t
         (let ((level 0)
               (current-scope scope)
               enclosing-scope)
           (while (and current-scope
                       (js2-node-parent current-scope)
                       (setq enclosing-scope
                             (js2-node-get-enclosing-scope current-scope)))
             (when (or context-coloring-js-block-scopes
                       (let ((type (js2-scope-type current-scope)))
                         (or (= type js2-SCRIPT)
                             (= type js2-FUNCTION)
                             (= type js2-CATCH))))
               (setq level (+ level 1)))
             (setq current-scope enclosing-scope))
           (puthash scope level context-coloring-js2-scope-level-hash-table)))))

(defsubst context-coloring-js2-local-name-node-p (node)
  "Determine if NODE is a `js2-name-node' representing a local
variable."
  (and (js2-name-node-p node)
       (let ((parent (js2-node-parent node)))
         (not (or (and (js2-object-prop-node-p parent)
                       (eq node (js2-object-prop-node-left parent)))
                  (and (js2-prop-get-node-p parent)
                       ;; For nested property lookup, the node on the left is a
                       ;; `js2-prop-get-node', so this always works.
                       (eq node (js2-prop-get-node-right parent))))))))

(defvar-local context-coloring-point-max nil
  "Cached value of `point-max'.")

(defsubst context-coloring-js2-colorize-node (node level)
  "Color NODE with the color for LEVEL."
  (let ((start (js2-node-abs-pos node)))
    (context-coloring-colorize-region
     start
     (min
      ;; End
      (+ start (js2-node-len node))
      ;; Somes nodes (like the ast when there is an unterminated multiline
      ;; comment) will stretch to the value of `point-max'.
      context-coloring-point-max)
     level)))

(defun context-coloring-js2-colorize ()
  "Color the current buffer using the abstract syntax tree
generated by `js2-mode'."
  ;; Reset the hash table; the old one could be obsolete.
  (setq context-coloring-js2-scope-level-hash-table (make-hash-table :test 'eq))
  (setq context-coloring-point-max (point-max))
  (with-silent-modifications
    (js2-visit-ast
     js2-mode-ast
     (lambda (node end-p)
       (when (null end-p)
         (cond
          ((js2-scope-p node)
           (context-coloring-js2-colorize-node
            node
            (context-coloring-js2-scope-level node)))
          ((context-coloring-js2-local-name-node-p node)
           (let* ((enclosing-scope (js2-node-get-enclosing-scope node))
                  (defining-scope (js2-get-defining-scope
                                   enclosing-scope
                                   (js2-name-node-name node))))
             ;; The tree seems to be walked lexically, so an entire scope will
             ;; be colored, including its name nodes, before they are reached.
             ;; Coloring the nodes defined in that scope would be redundant, so
             ;; don't do it.
             (when (not (eq defining-scope enclosing-scope))
               (context-coloring-js2-colorize-node
                node
                (context-coloring-js2-scope-level defining-scope))))))
         ;; The `t' indicates to search children.
         t)))
    (context-coloring-maybe-colorize-comments-and-strings)))


;;; Shell command scopification / colorization

(defun context-coloring-apply-tokens (tokens)
  "Process a vector of TOKENS to apply context-based coloring to
the current buffer.  Tokens are 3 integers: start, end, level.
The vector is flat, with a new token occurring after every 3rd
element."
  (with-silent-modifications
    (let ((i 0)
          (len (length tokens)))
      (while (< i len)
        (context-coloring-colorize-region
         (elt tokens i)
         (elt tokens (+ i 1))
         (elt tokens (+ i 2)))
        (setq i (+ i 3))))
    (context-coloring-maybe-colorize-comments-and-strings)))

(defun context-coloring-parse-array (array)
  "Parse ARRAY as a flat JSON array of numbers."
  (let ((braceless (substring (context-coloring-trim array) 1 -1)))
    (cond
     ((> (length braceless) 0)
      (vconcat
       (mapcar 'string-to-number (split-string braceless ","))))
     (t
      (vector)))))

(defvar-local context-coloring-scopifier-process nil
  "The single scopifier process that can be running.")

(defun context-coloring-kill-scopifier ()
  "Kill the currently-running scopifier process."
  (when (not (null context-coloring-scopifier-process))
    (delete-process context-coloring-scopifier-process)
    (setq context-coloring-scopifier-process nil)))

(defun context-coloring-scopify-shell-command (command callback)
  "Invoke a scopifier via COMMAND, read its response
asynchronously and invoke CALLBACK with its output."

  ;; Prior running tokenization is implicitly obsolete if this function is
  ;; called.
  (context-coloring-kill-scopifier)

  ;; Start the process.
  (setq context-coloring-scopifier-process
        (start-process-shell-command "scopifier" nil command))

  (let ((output ""))

    ;; The process may produce output in multiple chunks.  This filter
    ;; accumulates the chunks into a message.
    (set-process-filter
     context-coloring-scopifier-process
     (lambda (_process chunk)
       (setq output (concat output chunk))))

    ;; When the process's message is complete, this sentinel parses it as JSON
    ;; and applies the tokens to the buffer.
    (set-process-sentinel
     context-coloring-scopifier-process
     (lambda (_process event)
       (when (equal "finished\n" event)
         (funcall callback output))))))

(defun context-coloring-send-buffer-to-scopifier ()
  "Give the scopifier process its input so it can begin
scopifying."
  (process-send-region
   context-coloring-scopifier-process
   (point-min) (point-max))
  (process-send-eof
   context-coloring-scopifier-process))

(defun context-coloring-scopify-and-colorize (command &optional callback)
  "Invoke a scopifier via COMMAND with the current buffer's contents,
read the scopifier's response asynchronously and apply a parsed
list of tokens to `context-coloring-apply-tokens'.

Invoke CALLBACK when complete."
  (let ((buffer context-coloring-buffer))
    (context-coloring-scopify-shell-command
     command
     (lambda (output)
       (let ((tokens (context-coloring-parse-array output)))
         (with-current-buffer buffer
           (context-coloring-apply-tokens tokens))
         (setq context-coloring-scopifier-process nil)
         (when callback (funcall callback))))))
  (context-coloring-send-buffer-to-scopifier))


;;; Dispatch

(defvar context-coloring-dispatch-hash-table (make-hash-table :test 'eq)
  "Map dispatch strategy names to their corresponding property
  lists, which contain details about the strategies.")

(defvar context-coloring-mode-hash-table (make-hash-table :test 'eq)
  "Map major mode names to dispatch property lists.")

(defun context-coloring-define-dispatch (symbol &rest properties)
  "Define a new dispatch named SYMBOL with PROPERTIES.

A \"dispatch\" is a property list describing a strategy for
coloring a buffer.  There are three possible strategies: Parse
and color in a single function (`:colorizer'), parse in a
function that returns scope data (`:scopifier'), or parse with a
shell command that returns scope data (`:command').  In the
latter two cases, the scope data will be used to automatically
color the buffer.

PROPERTIES must include `:modes' and one of `:colorizer',
`:scopifier' or `:command'.

`:modes' - List of major modes this dispatch is valid for.

`:colorizer' - Symbol referring to a function that parses and
colors the buffer.

`:scopifier' - Symbol referring to a function that parses the
buffer a returns a flat vector of start, end and level data.

`:executable' - Optional name of an executable required by
`:command'.

`:command' - Shell command to execute with the current buffer
sent via stdin, and with a flat JSON array of start, end and
level data returned via stdout.

`:version' - Minimum required version that should be printed when
executing `:command' with a \"--version\" flag.  The version
should be numeric, e.g. \"2\", \"19700101\", \"1.2.3\",
\"v1.2.3\" etc.

`:setup' - Arbitrary code to set up this dispatch when
`context-coloring-mode' is enabled.

`:teardown' - Arbitrary code to tear down this dispatch when
`context-coloring-mode' is disabled."
  (let ((modes (plist-get properties :modes))
        (colorizer (plist-get properties :colorizer))
        (scopifier (plist-get properties :scopifier))
        (command (plist-get properties :command)))
    (when (null modes)
      (error "No mode defined for dispatch"))
    (when (not (or colorizer
                   scopifier
                   command))
      (error "No colorizer, scopifier or command defined for dispatch"))
    (puthash symbol properties context-coloring-dispatch-hash-table)
    (dolist (mode modes)
      (when (null (gethash mode context-coloring-mode-hash-table))
        (puthash mode properties context-coloring-mode-hash-table)))))

(context-coloring-define-dispatch
 'javascript-node
 :modes '(js-mode js3-mode)
 :executable "scopifier"
 :command "scopifier"
 :version "v1.1.1")

(context-coloring-define-dispatch
 'javascript-js2
 :modes '(js2-mode)
 :colorizer 'context-coloring-js2-colorize
 :setup
 (lambda ()
   (add-hook 'js2-post-parse-callbacks 'context-coloring-colorize nil t))
 :teardown
 (lambda ()
   (remove-hook 'js2-post-parse-callbacks 'context-coloring-colorize t)))

(defun context-coloring-dispatch (&optional callback)
  "Determine the optimal track for scopification / coloring of
the current buffer, then execute it.

Invoke CALLBACK when complete.  It is invoked synchronously for
elisp tracks, and asynchronously for shell command tracks."
  (let ((dispatch (gethash major-mode context-coloring-mode-hash-table))
        colorizer
        scopifier
        command)
    (cond
     ((setq colorizer (plist-get dispatch :colorizer))
      (funcall colorizer)
      (when callback (funcall callback)))
     ((setq scopifier (plist-get dispatch :scopifier))
      (context-coloring-apply-tokens (funcall scopifier))
      (when callback (funcall callback)))
     ((setq command (plist-get dispatch :command))
      (context-coloring-scopify-and-colorize command callback)))))


;;; Colorization

(defvar context-coloring-colorize-hook nil
  "Hooks to run after coloring a buffer.")

(defun context-coloring-colorize (&optional callback)
  "Color the current buffer by function context.

Invoke CALLBACK when complete; see `context-coloring-dispatch'."
  (interactive)
  (context-coloring-dispatch
   (lambda ()
     (when callback (funcall callback))
     (run-hooks 'context-coloring-colorize-hook))))

(defvar-local context-coloring-changed nil
  "Indication that the buffer has changed recently, which implies
that it should be colored again by
`context-coloring-colorize-idle-timer' if that timer is being
used.")

(defun context-coloring-change-function (_start _end _length)
  "Register a change so that a buffer can be colorized soon."
  ;; Tokenization is obsolete if there was a change.
  (context-coloring-kill-scopifier)
  (setq context-coloring-changed t))

(defun context-coloring-maybe-colorize ()
  "Colorize the current buffer if it has changed."
  (when (and (eq context-coloring-buffer (window-buffer (selected-window)))
             context-coloring-changed)
    (setq context-coloring-changed nil)
    (context-coloring-colorize)))


;;; Versioning

(defun context-coloring-parse-version (string)
  "Extract segments of a version STRING into a list.  \"v1.0.0\"
produces (1 0 0), \"19700101\" produces (19700101), etc."
  (let (version)
    (while (string-match "[0-9]+" string)
      (setq version (append version
                            (list (string-to-number (match-string 0 string)))))
      (setq string (substring string (match-end 0))))
    version))

(defun context-coloring-check-version (expected actual)
  "Check that version EXPECTED is less than or equal to ACTUAL."
  (let ((expected (context-coloring-parse-version expected))
        (actual (context-coloring-parse-version actual))
        (continue t)
        (acceptable t))
    (while (and continue expected)
      (let ((an-expected (car expected))
            (an-actual (car actual)))
        (cond
         ((> an-actual an-expected)
          (setq acceptable t)
          (setq continue nil))
         ((< an-actual an-expected)
          (setq acceptable nil)
          (setq continue nil))))
      (setq expected (cdr expected))
      (setq actual (cdr actual)))
    acceptable))

(defvar context-coloring-check-scopifier-version-hook nil
  "Hooks to run after checking the scopifier version.")

(defun context-coloring-check-scopifier-version (&optional callback)
  "Asynchronously invoke CALLBACK with a predicate indicating
whether the current scopifier version satisfies the minimum
version number required for the current major mode."
  (let ((dispatch (gethash major-mode context-coloring-mode-hash-table)))
    (when dispatch
      (let ((version (plist-get dispatch :version))
            (command (plist-get dispatch :command)))
        (context-coloring-scopify-shell-command
         (context-coloring-join (list command "--version") " ")
         (lambda (output)
           (if (context-coloring-check-version version output)
               (progn
                 (when callback (funcall callback t)))
             (when callback (funcall callback nil)))
           (run-hooks 'context-coloring-check-scopifier-version-hook)))))))


;;; Themes

(defvar context-coloring-theme-hash-table (make-hash-table :test 'eq)
  "Map theme names to theme properties.")

(defun context-coloring-theme-p (theme)
  "Return t if THEME is defined, nil otherwise."
  (and (gethash theme context-coloring-theme-hash-table)))

(defconst context-coloring-level-face-regexp
  "context-coloring-level-\\([[:digit:]]+\\)-face"
  "Extract a level from a face.")

(defvar context-coloring-originally-set-theme-hash-table
  (make-hash-table :test 'eq)
  "Cache custom themes who originally set their own
  `context-coloring-level-N-face' faces.")

(defun context-coloring-theme-originally-set-p (theme)
  "Return t if there is a `context-coloring-level-N-face'
originally set for THEME, nil otherwise."
  (let (originally-set)
    (cond
     ;; `setq' might return a non-nil value for the sake of this `cond'.
     ((setq
       originally-set
       (gethash
        theme
        context-coloring-originally-set-theme-hash-table))
      (eq originally-set 'yes))
     (t
      (let* ((settings (get theme 'theme-settings))
             (tail settings)
             found)
        (while (and tail (not found))
          (and (eq (nth 0 (car tail)) 'theme-face)
               (string-match
                context-coloring-level-face-regexp
                (symbol-name (nth 1 (car tail))))
               (setq found t))
          (setq tail (cdr tail)))
        found)))))

(defun context-coloring-cache-originally-set (theme originally-set)
  "Remember if THEME had colors originally set for it.  If
ORIGINALLY-SET is non-nil, it did, otherwise it didn't."
  ;; Caching whether a theme was originally set is kind of dirty, but we have to
  ;; do it to remember the past state of the theme.  There are probably some
  ;; edge cases where caching will be an issue, but they are probably rare.
  (puthash
   theme
   (if originally-set 'yes 'no)
   context-coloring-originally-set-theme-hash-table))

(defun context-coloring-warn-theme-originally-set (theme)
  "Warn the user that the colors for THEME are already originally
set."
  (warn "Context coloring colors for theme `%s' are already defined" theme))

(defun context-coloring-theme-highest-level (theme)
  "Return the highest level N of a face like
`context-coloring-level-N-face' set for THEME, or `-1' if there
is none."
  (let* ((settings (get theme 'theme-settings))
         (tail settings)
         face-string
         number
         (found -1))
    (while tail
      (and (eq (nth 0 (car tail)) 'theme-face)
           (setq face-string (symbol-name (nth 1 (car tail))))
           (string-match
            context-coloring-level-face-regexp
            face-string)
           (setq number (string-to-number
                         (substring face-string
                                    (match-beginning 1)
                                    (match-end 1))))
           (> number found)
           (setq found number))
      (setq tail (cdr tail)))
    found))

(defun context-coloring-apply-theme (theme)
  "Apply THEME's properties to its respective custom theme,
which must already exist and which *should* already be enabled."
  (let* ((properties (gethash theme context-coloring-theme-hash-table))
         (colors (plist-get properties :colors))
         (level -1))
    ;; Only clobber when we have to.
    (when (custom-theme-enabled-p theme)
      (setq context-coloring-maximum-face (- (length colors) 1)))
    (apply
     'custom-theme-set-faces
     theme
     (mapcar
      (lambda (color)
        (setq level (+ level 1))
        `(,(context-coloring-level-face level) ((t (:foreground ,color)))))
      colors))))

(defun context-coloring-define-theme (theme &rest properties)
  "Define a context theme named THEME for coloring scope levels.

PROPERTIES is a property list specifiying the following details:

`:aliases': List of symbols of other custom themes that these
colors are applicable to.

`:colors': List of colors that this context theme uses.

`:override': If non-nil, this context theme is intentionally
overriding colors set by a custom theme.  Don't set this non-nil
unless there is a custom theme you want to use which sets
`context-coloring-level-N-face' faces that you want to replace.

`:recede': If non-nil, this context theme should not apply its
colors if a custom theme already sets
`context-coloring-level-N-face' faces.  This option is
optimistic; set this non-nil if you would rather confer the duty
of picking colors to a custom theme author (if / when he ever
gets around to it).

By default, context themes will always override custom themes,
even if those custom themes set `context-coloring-level-N-face'
faces.  If a context theme does override a custom theme, a
warning will be raised, at which point you may want to enable the
`:override' option, or just delete your context theme and opt to
use your custom theme's author's colors instead.

Context themes only work for the custom theme with the highest
precedence, i.e. the car of `custom-enabled-themes'."
  (let ((aliases (plist-get properties :aliases))
        (override (plist-get properties :override))
        (recede (plist-get properties :recede)))
    (dolist (name (append `(,theme) aliases))
      (puthash name properties context-coloring-theme-hash-table)
      (when (custom-theme-p name)
        (let ((originally-set (context-coloring-theme-originally-set-p name)))
          (context-coloring-cache-originally-set name originally-set)
          ;; In the particular case when you innocently define colors that a
          ;; custom theme originally set, warn.  Arguably this only has to be
          ;; done at enable time, but it is probably more useful to do it at
          ;; definition time for prompter feedback.
          (when (and originally-set
                     (not recede)
                     (not override))
            (context-coloring-warn-theme-originally-set name))
          ;; Set (or overwrite) colors.
          (when (not (and originally-set
                          recede))
            (context-coloring-apply-theme name)))))))

(defun context-coloring-enable-theme (theme)
  "Apply THEME if its colors are not already set, else just set
`context-coloring-maximum-face' to the correct value for THEME."
  (let* ((properties (gethash theme context-coloring-theme-hash-table))
         (recede (plist-get properties :recede))
         (override (plist-get properties :override)))
    (cond
     (recede
      (let ((highest-level (context-coloring-theme-highest-level theme)))
        (cond
         ;; This can be true whether originally set by a custom theme or by a
         ;; context theme.
         ((> highest-level -1)
          (setq context-coloring-maximum-face highest-level))
         ;; It is possible that the corresponding custom theme did not exist at
         ;; the time of defining this context theme, and in that case the above
         ;; condition proves the custom theme did not originally set any faces,
         ;; so we have license to apply the context theme for the first time
         ;; here.
         (t
          (context-coloring-apply-theme theme)))))
     (t
      (let ((originally-set (context-coloring-theme-originally-set-p theme)))
        ;; Cache now in case the context theme was defined after the custom
        ;; theme.
        (context-coloring-cache-originally-set theme originally-set)
        (when (and originally-set
                   (not override))
          (context-coloring-warn-theme-originally-set theme))
        (context-coloring-apply-theme theme))))))

(defadvice enable-theme (after context-coloring-enable-theme (theme) activate)
  "Enable colors for context themes just-in-time."
  (when (and (not (eq theme 'user)) ; Called internally by `enable-theme'.
             (custom-theme-p theme) ; Guard against non-existent themes.
             (context-coloring-theme-p theme))
    (when (= (length custom-enabled-themes) 1)
      ;; Cache because we can't reliably figure it out in reverse.
      (setq context-coloring-original-maximum-face
            context-coloring-maximum-face))
    (context-coloring-enable-theme theme)))

(defadvice disable-theme (after context-coloring-disable-theme (theme) activate)
  "Update `context-coloring-maximum-face'."
  (when (custom-theme-p theme) ; Guard against non-existent themes.
    (let ((enabled-theme (car custom-enabled-themes)))
      (if (context-coloring-theme-p enabled-theme)
          (progn
            (context-coloring-enable-theme enabled-theme))
        ;; Assume we are back to no theme; act as if nothing ever happened.
        ;; This is still prone to intervention, but rather extraordinarily.
        (setq context-coloring-maximum-face
              context-coloring-original-maximum-face)))))

(context-coloring-define-theme
 'ample
 :recede t
 :colors '("#bdbdb3"
           "#baba36"
           "#6aaf50"
           "#5180b3"
           "#ab75c3"
           "#cd7542"
           "#dF9522"
           "#454545"))

(context-coloring-define-theme
 'anti-zenburn
 :recede t
 :colors '("#232333"
           "#6c1f1c"
           "#401440"
           "#0f2050"
           "#205070"
           "#336c6c"
           "#23733c"
           "#6b400c"
           "#603a60"
           "#2f4070"
           "#235c5c"))

(context-coloring-define-theme
 'grandshell
 :recede t
 :colors '("#bebebe"
           "#5af2ee"
           "#b2baf6"
           "#f09fff"
           "#efc334"
           "#f6df92"
           "#acfb5a"
           "#888888"))

(context-coloring-define-theme
 'leuven
 :recede t
 :colors '("#333333"
           "#0000FF"
           "#6434A3"
           "#BA36A5"
           "#D0372D"
           "#036A07"
           "#006699"
           "#006FE0"
           "#808080"))

(context-coloring-define-theme
 'monokai
 :recede t
 :colors '("#F8F8F2"
           "#66D9EF"
           "#A1EFE4"
           "#A6E22E"
           "#E6DB74"
           "#FD971F"
           "#F92672"
           "#FD5FF0"
           "#AE81FF"))

(context-coloring-define-theme
 'solarized
 :recede t
 :aliases '(solarized-light
            solarized-dark
            sanityinc-solarized-light
            sanityinc-solarized-dark)
 :colors '("#839496"
           "#268bd2"
           "#2aa198"
           "#859900"
           "#b58900"
           "#cb4b16"
           "#dc322f"
           "#d33682"
           "#6c71c4"
           "#69B7F0"
           "#69CABF"
           "#B4C342"
           "#DEB542"
           "#F2804F"
           "#FF6E64"
           "#F771AC"
           "#9EA0E5"))

(context-coloring-define-theme
 'spacegray
 :recede t
 :colors '("#ffffff"
           "#89AAEB"
           "#C189EB"
           "#bf616a"
           "#DCA432"
           "#ebcb8b"
           "#B4EB89"
           "#89EBCA"))

(context-coloring-define-theme
 'tango
 :recede t
 :colors '("#2e3436"
           "#346604"
           "#204a87"
           "#5c3566"
           "#a40000"
           "#b35000"
           "#c4a000"
           "#8ae234"
           "#8cc4ff"
           "#ad7fa8"
           "#ef2929"
           "#fcaf3e"
           "#fce94f"))

(context-coloring-define-theme
 'zenburn
 :recede t
 :colors '("#DCDCCC"
           "#93E0E3"
           "#BFEBBF"
           "#F0DFAF"
           "#DFAF8F"
           "#CC9393"
           "#DC8CC3"
           "#94BFF3"
           "#9FC59F"
           "#D0BF8F"
           "#DCA3A3"))


;;; Minor mode

(defvar-local context-coloring-colorize-idle-timer nil
  "The currently-running idle timer.")

(defcustom context-coloring-delay 0.25
  "Delay between a buffer update and colorization.

Increase this if your machine is high-performing.  Decrease it if
it ain't.

Supported modes: `js-mode', `js3-mode'"
  :group 'context-coloring)

(defun context-coloring-setup-idle-change-detection ()
  "Setup idle change detection."
  (add-hook
   'after-change-functions 'context-coloring-change-function nil t)
  (setq context-coloring-colorize-idle-timer
        (run-with-idle-timer
         context-coloring-delay
         t
         'context-coloring-maybe-colorize)))

;;;###autoload
(define-minor-mode context-coloring-mode
  "Context-based code coloring, inspired by Douglas Crockford."
  nil " Context" nil
  (if (not context-coloring-mode)
      (progn
        (context-coloring-kill-scopifier)
        (when context-coloring-colorize-idle-timer
          (cancel-timer context-coloring-colorize-idle-timer))
        (let ((dispatch (gethash major-mode context-coloring-mode-hash-table)))
          (when dispatch
            (let ((command (plist-get dispatch :command))
                  (teardown (plist-get dispatch :teardown)))
              (when command
                (remove-hook
                 'after-change-functions 'context-coloring-change-function t))
              (when teardown
                (funcall teardown)))))
        (font-lock-mode)
        (jit-lock-mode t))

    ;; Remember this buffer.  This value should not be dynamically-bound.
    (setq context-coloring-buffer (current-buffer))

    ;; Font lock is incompatible with this mode; the converse is also true.
    (font-lock-mode 0)
    (jit-lock-mode nil)

    ;; Safely change the valye of this function as necessary.
    (make-local-variable 'font-lock-syntactic-face-function)

    (let ((dispatch (gethash major-mode context-coloring-mode-hash-table)))
      (if dispatch
          (progn
            (let ((command (plist-get dispatch :command))
                  (version (plist-get dispatch :version))
                  (executable (plist-get dispatch :executable))
                  (setup (plist-get dispatch :setup))
                  (colorize-initially-p t))
              (when command
                ;; Shell commands recolor on change, idly.
                (cond
                 ((and executable
                       (null (executable-find executable)))
                  (message "Executable \"%s\" not found" executable)
                  (setq colorize-initially-p nil))
                 (version
                  (context-coloring-check-scopifier-version
                   (lambda (sufficient-p)
                     (if sufficient-p
                         (progn
                           (context-coloring-setup-idle-change-detection)
                           (context-coloring-colorize))
                       (message "Update to the minimum version of \"%s\" (%s)"
                                executable version))))
                  (setq colorize-initially-p nil))
                 (t
                  (context-coloring-setup-idle-change-detection))))
              (when setup
                (funcall setup))
              ;; Colorize once initially.
              (when colorize-initially-p
                (context-coloring-colorize))))
        (when (null dispatch)
          (message "Context coloring is not available for this major mode"))))))

;;;; ChangeLog:

;; 2015-05-05  Jackson Ray Hamilton  <jackson@jacksonrayhamilton.com>
;; 
;; 	Merge commit '283a006be8e96c7e011dedddb460b289d335a9fb' from
;; 	context-coloring
;; 
;; 2015-03-22  Jackson Ray Hamilton  <jackson@jacksonrayhamilton.com>
;; 
;; 	Merge commit '901db7732bf61d9809712e8adfad9f84adc2eb56' from
;; 	context-coloring
;; 
;; 2015-03-14  Jackson Ray Hamilton  <jackson@jacksonrayhamilton.com>
;; 
;; 	Merge commit 'f062d5a55496e22cf89f2ef9778a24a840a5a68e' from
;; 	context-coloring
;; 
;; 2015-02-14  Jackson Ray Hamilton  <jackson@jacksonrayhamilton.com>
;; 
;; 	Merge commit 'f4e1cbc5386fbf197ff8bcb6a9275f17c9cbe8e4' from
;; 	context-coloring
;; 
;; 2015-02-08  Jackson Ray Hamilton  <jackson@jacksonrayhamilton.com>
;; 
;; 	Merge commit '6f3ad757155b9b3089aba55ee6102ecc9bed647d' from
;; 	context-coloring
;; 
;; 2015-02-07  Jackson Ray Hamilton  <jackson@jacksonrayhamilton.com>
;; 
;; 	Merge commit '59de0b7591713d38c6d5c99cb49c4a4cc434a272' from
;; 	context-coloring
;; 
;; 2015-02-05  Jackson Ray Hamilton  <jackson@jacksonrayhamilton.com>
;; 
;; 	Merge commit 'fedf88552990afa269366dfa4c3f5af6d1cdb7c2' from
;; 	context-coloring
;; 
;; 2015-02-04  Jackson Ray Hamilton  <jackson@jacksonrayhamilton.com>
;; 
;; 	Add 'packages/context-coloring/' from commit
;; 	'f2b5d796d4dffc71b10503a8ae119bfa3274978e'
;; 
;; 	git-subtree-dir: packages/context-coloring git-subtree-mainline:
;; 	3c57fa96866983e1cf20ca2ab2f0db7c140ccd4d git-subtree-split:
;; 	f2b5d796d4dffc71b10503a8ae119bfa3274978e
;; 


(provide 'context-coloring)

;;; context-coloring.el ends here
