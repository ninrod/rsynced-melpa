;;; tickscript-mode.el --- A major mode for Tickscript files  -*- lexical-binding: t; -*-

;; Copyright (C) 2017  Marc Sherry
;; Homepage: https://github.com/msherry/tickscript-mode
;; Version: 0.1
;; Package-Version: 20171020.1330
;; Author: Marc Sherry <msherry@gmail.com>
;; Keywords: languages
;; Package-Requires: ((emacs "24.1"))

;; This file is not part of GNU Emacs.

;; This file is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation; either version 3, or (at your option)
;; any later version.

;; This file is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <https://www.gnu.org/licenses/>.

;;; Commentary:
;; Copyright Marc Sherry <msherry@gmail.com>
;;
;; Provides Emacs font-lock, indentation, navigation, and utility functions for
;; working with TICKscript (https://docs.influxdata.com/kapacitor/v1.3/tick/),
;; a DSL for use with Kapacitor and InfluxDB.
;;
;; Installation:
;;
;; Available on MELPA (https://melpa.org/) and MELPA Stable
;; (https://stable.melpa.org/) -- installation from there is easiest:
;;
;; `M-x package-install tickscript-mode'
;;
;; Alternately, add the following to your .init.el:
;;
;;     (add-to-list 'load-path "path-to-tickscript-mode")
;;     (require 'tickscript-mode)
;;
;; Usage:
;;
;; In addition to syntax highlighting and indentation support,
;; `tickscript-mode' provides a number of utility functions for working
;; directly with Kapacitor:
;;
;; * `C-c C-c' -- `tickscript-define-task'
;;
;;   Send the current task to Kapacitor via `kapacitor define'.
;;
;; * `C-c C-v' -- `tickscript-show-task'
;;
;;   View the current task's definition with `kapacitor show <task>'.  This
;;   will also render the DOT output inline, for easier visualization of the
;;   nodes involved.
;;
;; * `C-c C-l p' -- `tickscript-list-replays'
;;
;; * `C-c C-l r' -- `tickscript-list-recordings'
;;
;; * `C-c C-l t' -- `tickscript-list-tasks'
;;
;;   Query Kapacitor for information about the specified objects.
;;
;;
;; Support is also provided for looking up node and property definitions:
;;
;; * `C-c C-d' -- `tickscript-get-help'
;;
;;   Look up the node, and possibly property, currently under point online.

;;; Code:

(defvar tickscript-font-lock-keywords nil)
(defvar tickscript-properties nil)
(defvar tickscript-toplevel-nodes nil)
(defvar tickscript-nodes nil)
(defvar tickscript-chaining-methods nil)
(defvar tickscript-series-name nil)
(defvar tickscript-series-type nil)
(defvar tickscript-series-dbrp nil)

(defvar tickscript-webhelp-case-map (make-hash-table :test 'equal))

(defgroup tickscript nil
  "TICKscript support for Emacs."
  :group 'languages
  :version "0.1")

(defcustom tickscript-indent-offset 4
  "Number of spaces per indentation level."
  :type 'integer
  :group 'tickscript
  :safe 'integerp)

(defcustom tickscript-kapacitor-prog-name "kapacitor"
  "The name of the executable used to invoke Kapacitor."
  :type 'string
  :group 'tickscript
  :safe 'stringp)

(defcustom tickscript-kapacitor-url ""
  "The URL host/port of the Kapacitor server.

If unset, defaults to \"http://localhost:9092\"."
  :type 'string
  :group 'tickscript
  :safe 'stringp)

(defcustom tickscript-render-dot-output t
  "Whether to render DOT output with Graphviz when executing tickscript-show-task."
  :type 'boolean
  :group 'tickscript
  :safe 'booleanp)

(defcustom tickscript-indent-trigger-commands
  '(indent-for-tab-command yas-expand yas/expand)
  "Commands that might trigger a `tickscript-indent-line' call."
  :type '(repeat symbol)
  :group 'tickscript)

(defface tickscript-node
  '((t :inherit font-lock-type-face))
  "Face for nodes in TICKscript, like alert, batch, query, groupBy, etc."
  :tag "tickscript-node"
  :group 'tickscript)

(defface tickscript-chaining-method
  '((t :inherit font-lock-type-face))
  "Face for chaining methods in TICKscript, like median, mean, etc."
  :tag "tickscript-chaining-method"
  :group 'tickscript)

(defface tickscript-udf
  '((t :inherit font-lock-type-face))
  "Face for user-defined functions in TICKscript."
  :tag "tickscript-udf"
  :group 'tickscript)

(defface tickscript-property
  '((t :inherit font-lock-keyword-face))
  "Face for properties in TICKscript, like align, groupBy, period, etc."
  :tag "tickscript-property"
  :group 'tickscript)

(defface tickscript-chaining-method
  '((t :inherit font-lock-type-face))
  "Face for chaining methods in TICKscript, like median, mean, etc."
  :tag "tickscript-chaining-method"
  :group 'tickscript)

(defface tickscript-udf-param
  '((t :inherit font-lock-keyword-face
     :foreground "#cb4b16"))
  "Face for parameters to user-defined functions in TICKscript."
  :tag "tickscript-udf-param"
  :group 'tickscript)

(defface tickscript-variable
  '((t :inherit font-lock-variable-name-face))
  "Face for variables in TICKscript."
  :tag "tickscript-variable"
  :group 'tickscript)

(defface tickscript-number
  '((t :inherit font-lock-constant-face))
  "Face for numbers in TICKscript."
  :tag "tickscript-number"
  :group 'tickscript)

(defface tickscript-duration
  '((t :inherit font-lock-constant-face))
  "Face for time ranges in TICKscript, like 1h, 20us, etc.."
  :tag "tickscript-duration"
  :group 'tickscript)

(defface tickscript-operator
  '((t :inherit font-lock-warning-face
     :foreground "#bf3d5e"))
  "Face used for highlighting operators like \"|\" and \"/\" in TICKscript."
  :tag "tickscript-operator"
  :group 'tickscript)


(setq tickscript-properties
      '("align" "alignGroup" "as" "buffer" "byMeasurement" "channel" "cluster"
        "create" "crit" "cron" "database" "delimiter" "every" "field" "fill"
        "flushInterval" "groupBy" "groupByMeasurement" "id" "info" "keep" "level"
        "measurement" "message" "noRecoveries" "offset" "on" "period" "post"
        "precision" "quiet" "retentionPolicy" "slack" "stateChangesOnly" "streamName"
        "tag" "tags" "tcp" "tolerance" "usePointTimes" "warn" "writeConsistency"))

(setq tickscript-toplevel-nodes
      '("batch" "stream"))

(setq tickscript-nodes
      '("alert" "batch" "combine" "default" "delete" "derivative" "eval"
        "exclude" "flatten" "from" "groupBy" "httpOut" "httpPost" "influxDBOut"
        "influxQL" "join" "k8sAutoscale" "kapacitorLoopback" "log" "noOp"
        "query" "sample" "shift" "stateCount" "stateDuration" "stats" "stream"
        "union" "where" "window"))

(setq tickscript-chaining-methods
      '("bottom" "count" "cumulativeSum" "deadman" "difference" "distinct"
        "elapsed" "first" "holtWinters" "holtWintersWithFit" "last" "max"
        "mean" "median" "min" "mode" "movingAverage" "percentile" "spread"
        "stddev" "sum" "top"))

(puthash "groupBy" "group_by" tickscript-webhelp-case-map)
(puthash "httpOut" "http_out" tickscript-webhelp-case-map)
(puthash "httpPost" "http_post" tickscript-webhelp-case-map)
(puthash "influxDBOut" "influx_d_b_out" tickscript-webhelp-case-map)
(puthash "influxQL" "influx_q_l" tickscript-webhelp-case-map)
(puthash "k8sAutoscale" "k8s_autoscale" tickscript-webhelp-case-map)
(puthash "kapacitorLoopback" "kapacitor_loopback" tickscript-webhelp-case-map)
(puthash "noOp" "no_op" tickscript-webhelp-case-map)
(puthash "stateCount" "state_count" tickscript-webhelp-case-map)
(puthash "stateDuration" "state_duration" tickscript-webhelp-case-map)

(setq tickscript-font-lock-keywords
    `(;; General keywords
      ,(rx symbol-start (or "var" "lambda") symbol-end)
       ;; UDF parameters. Takes precedence over node properties, which match
       ;; similarly.  Inspired by python.el
       (,(lambda (limit)
           (let ((re (rx ?. (group (+ letter) (* alnum))))
                 (res nil))
             (while (and (setq res (re-search-forward re limit t))
                         (not (tickscript-current-udf))))
             res))
         (1 'tickscript-udf-param nil nil))
       ;; Node properties - start with "." to avoid collisions for e.g. "groupBy"
       (,(concat "\\.\\_<" (regexp-opt tickscript-properties t) "\\_>") .
         'tickscript-property)
       ;; Chaining methods - like nodes, but not
       (,(concat "\\_<" (regexp-opt tickscript-chaining-methods t) "\\_>") . 'tickscript-chaining-method)
       ;; Nodes
       (,(concat "\\_<" (regexp-opt tickscript-nodes t) "\\_>") . 'tickscript-node)
       ;; UDFs
       (,(rx "@" (+ (or alnum "_"))) . 'tickscript-udf)
       ;; Time units
       (,(rx symbol-start (? "-") (1+ digit) (or "u" "µ" "ms" "s" "m" "h" "d" "w") symbol-end) . 'tickscript-duration)
       (,(rx symbol-start (? "-") (1+ digit) (optional "\." (1+ digit))) . 'tickscript-number)
       ;; Variable declarations
       ("\\_<\\(?:var\\)\\_>[[:space:]]+\\([[:alpha:]]\\(?:[[:alnum:]]\\|_\\)*\\)" (1 'tickscript-variable nil nil))
       ;; Operators
       (,(rx (or "\|" "\+" "\-" "\*" "/")) . 'tickscript-operator)
       ))

(defconst tickscript-mode-syntax-table
  (let ((table (make-syntax-table)))
    ;; ' is a string delimiter
    (modify-syntax-entry ?' "\"" table)
    ;; " is a dereferencing string delimiter
    (modify-syntax-entry ?\" "\"" table)
    ;; | is punctuation?
    (modify-syntax-entry ?| "." table)
    ;; @ is punctuation?
    (modify-syntax-entry ?@ "." table)
    ;; / is punctuation, but // is a comment starter
    (modify-syntax-entry ?/ ". 12" table)
     ;; \n is a comment ender
    (modify-syntax-entry ?\n ">" table)
    table))

(defvar tickscript-list-commands-map
  (let ((map (define-prefix-command 'tickscript-list-commands-map)))
    (define-key map (kbd "t") #'tickscript-list-tasks)
    (define-key map (kbd "r") #'tickscript-list-recordings)
    (define-key map (kbd "p") #'tickscript-list-replays))
  map)

(defvar tickscript-mode-map
  (let ((map (make-sparse-keymap)))
    ;; Indentation
    (define-key map (kbd "<backtab>") #'tickscript-indent-dedent-line)
    ;; Movement
    (define-key map (kbd "<M-down>") #'tickscript-move-line-or-region-down)
    (define-key map (kbd "<M-up>") #'tickscript-move-line-or-region-up)
    ;; Help
    (define-key map (kbd "C-c C-d") #'tickscript-get-help)
    ;; Util
    (define-key map (kbd "C-c C-c") #'tickscript-define-task)
    (define-key map (kbd "C-c C-v") #'tickscript-show-task)
    ;; Listing
    (define-key map (kbd "C-c C-l") 'tickscript-list-commands-map)
    map)
  "Keymap for `tickscript-mode'.")

;; if backward-sexp gives an error, move back 1 char to move over the open
;; paren.
(defun tickscript-safe-backward-sexp ()
  "Move backward by one sexp, ignoring errors.  Jump out of strings/comments first."
  (when (or (tickscript--in-string)
            (tickscript--in-comment))
    (goto-char (nth 8 (syntax-ppss))))
  (if (condition-case nil (backward-sexp) (error t))
      (ignore-errors (backward-char))))

(defun tickscript--at-keyword (kw-list)
  "Return the word at point if it matches any keyword in KW-LIST.

KW-LIST is a list of strings."
  (let ((word (current-word t)))
    (and (member word kw-list)
         (not (looking-at "("))
         (not (or (tickscript--in-comment)
                  (tickscript--in-string)))
         word)))

(defun tickscript-node-at-point (&optional toplevel-only)
  "Return the word at point if it is a node.

To be a node, it must be a keyword in the nodes list, and either
be preceded by the \"|\" sigil, or no sigil.  Specifically, it
must not be preceded by \".\", as some keywords (like \"groupBy\"
are both properties and nodes.  If TOPLEVEL-ONLY is specified,
only toplevel nodes \"batch\" and \"stream\" are checked."
  ;; Skip over any sigil, if present
  (save-excursion
    (when (looking-at "\|")
      (forward-char))
    (let* ((word-bounds (bounds-of-thing-at-point 'word))
           (word-start (and word-bounds
                            (car word-bounds))))
      (and word-start
       (or (= word-start 1)
               (equal (char-before word-start) ?|)
               (not (equal (char-before word-start) ?.)))
           (tickscript--at-keyword (if toplevel-only
                                       tickscript-toplevel-nodes
                                     tickscript-nodes))))))

(defun tickscript-chaining-method-at-point ()
  "Return the word at point if it is a chaining method.

Chaining methods act much like nodes, but are only available
under certain nodes.  See `tickscript-node-at-point' for details on how
this function works."
    ;; Skip over any sigil, if present
  (save-excursion
    (when (looking-at "\|")
      (forward-char))
    (let* ((word-bounds (bounds-of-thing-at-point 'word))
           (word-start (and word-bounds
                            (car word-bounds))))
      (and word-start
           (equal (char-before word-start) ?|)
           (tickscript--at-keyword tickscript-chaining-methods)))))

(defun tickscript-udf-at-point ()
  "Return the symbol at point if it is a user-defined function."
  ;; Skip over any sigil, if present
  (save-excursion
    (when (looking-at "@")
      (forward-char))
    (let* ((word-bounds (bounds-of-thing-at-point 'symbol))
           (word-start (and word-bounds
                            (car word-bounds))))
      (and word-start
           (equal (char-before word-start) ?@)
           (substring-no-properties (thing-at-point 'symbol))))))

(defun tickscript-property-at-point ()
  "Return the word at point if it is a property.

To be a property, it must be a keyword in the properties list, and
be preceded by the \".\" sigil."
  (save-excursion
    (when (looking-at "\\.")
      (forward-char))
    (let* ((word-bounds (bounds-of-thing-at-point 'word))
           (word-start (and word-bounds
                            (car word-bounds))))
      (and word-start
           (> word-start 1)
           (equal (char-before word-start) ?.)
           (tickscript--at-keyword tickscript-properties)))))

(defun tickscript--in-string ()
  "Return non-nil if point is inside a string."
  (nth 3 (syntax-ppss)))

(defun tickscript--in-comment ()
  "Return non-nil if point is inside a comment."
  (nth 4 (syntax-ppss)))

(defun tickscript-at-node-instance ()
  "Return whether word at point is an instance of a previously-defined node."
  (not (or (tickscript-node-at-point)
           (tickscript-property-at-point)
           (tickscript--in-string)
           (tickscript--in-comment))))

(defun tickscript--last-identifier-pos (fn stop-at-node)
  "Internal method to find the last identifier matching FN.
If STOP-AT-NODE is true, the search stops once a node (or UDF) is hit."
  (save-excursion
    ;; Skip the sigil, if we're on one
    (if (looking-at "\\.|\|@")
        (forward-char))
    (let ((count 0)
          (node-count 0))
      (while (not (or (> count 0) (> node-count 0) (<= (point) 1)))
        (tickscript-safe-backward-sexp)
        (when (funcall fn)
          (setq count (1+ count)))
        (when (and stop-at-node
                   (or (tickscript-node-at-point)
                       (tickscript-udf-at-point)))
          (setq node-count (1+ node-count))))
      (if (> count 0)
          (point)
        nil))))

(defun tickscript-last-node-pos (&optional stop-at-node)
  "Return the position of the last node, if found.
Optional arg STOP-AT-NODE tells the parser to stop at the first
node boundary found (which includes UDFs)."
  (tickscript--last-identifier-pos #'tickscript-node-at-point stop-at-node))

(defun tickscript-last-udf-pos (&optional stop-at-node)
  "Return the position of the last UDF, if found.
Optional arg STOP-AT-NODE tells the parser to stop at the first
node boundary found (which includes UDFs)."
  (tickscript--last-identifier-pos #'tickscript-udf-at-point stop-at-node))

(defun tickscript-last-chaining-method-pos ()
  "Return the position of the last chaining method, if found."
  (tickscript--last-identifier-pos #'tickscript-chaining-method-at-point t))

(defun tickscript-last-property-pos ()
  "Return the position of the last property, if found."
  (tickscript--last-identifier-pos #'tickscript-property-at-point t))

(defun tickscript-current-node ()
  "Return the name of the current node.
Returns the name of the node under point, or the last node in the
current chain if point is not on a node."
  (let ((last-node-pos (tickscript-last-node-pos t)))
    (if last-node-pos
        (save-excursion
          (goto-char last-node-pos)
          (tickscript--at-keyword tickscript-nodes)))))

(defun tickscript-current-udf ()
  "Return the name of the current UDF.
Returns the name of the UDF under point, or the last UDF in the
current chain if point is not on a UDF."
  (save-excursion
    ;; This function is used in font-locking, so must preserve match data
     (save-match-data
     (let ((last-udf-pos (tickscript-last-udf-pos t)))
       (if last-udf-pos
           (goto-char last-udf-pos)
         (tickscript-udf-at-point))))))

(defun tickscript--node-indentation (&optional min)
  "Return indentation level for items under the last node.
Do not move back beyond MIN."
  ;; Ensure MIN is not before start of buffer
  (unless min
    (setq min 0))
  (save-excursion
    (setq min (max min (point-min)))
    (let ((pos (tickscript-last-node-pos min)))
      (when pos
        (goto-char pos)
        (+ tickscript-indent-offset (current-indentation))))))

(defmacro tickscript--at-bol (&rest body)
  `(progn
     (save-excursion
       (beginning-of-line)
       ;; jump up out of any comments
       (let ((state (syntax-ppss)))
         (when (nth 4 state)
           (goto-char (nth 8 state))))
       (forward-to-indentation 0)
       ,(macroexp-progn body))))

(defun tickscript-indent-in-string ()
  "Indentation inside strings with newlines is \"manual\",
meaning always increase indent on TAB and decrease on S-TAB."
  ;; Taken from julia-mode.el
  (save-excursion
    (beginning-of-line)
    (when (tickscript--in-string)
      ;; (message "STRING")
      (if (member this-command tickscript-indent-trigger-commands)
          (+ tickscript-indent-offset (current-indentation))
        ;; return the current indentation to prevent other functions from
        ;; indenting inside strings
        (current-indentation)))))

(defun tickscript-indent-in-continuation ()
  "Indentation for statements/expressions broken across multiple lines."
   (tickscript--at-bol
    (let ((open-paren (nth 1 (syntax-ppss)))
          (linum (line-number-at-pos)))
      (when open-paren
        (goto-char open-paren)
        ;; If open paren is on the current line, we're not in a continuation
        (unless (eq linum (line-number-at-pos))
          ;; (message "CONTINUATION")
          ;; Found the open paren, indent to right after it
          (1+ (current-column)))))))

(defun tickscript-indent-comment-line ()
  "Indentation for comment lines."
  (tickscript--at-bol
   (when (looking-at "//")
     ;; (message "COMMENT LINE")
     ;; Match previous line's indentation if non-empty (not just whitespace),
     ;; otherwise 0 indentation
     (if (eq (line-number-at-pos) 1)
         0
       (forward-line -1)
       (current-indentation)))))

(defun tickscript-indent-toplevel-node ()
  "Indentation for toplevel nodes, which are always at level 0.

 \"batch\" or \"stream\", with optional \"var\" declarations."
  (tickscript--at-bol
   (when (or (looking-at "var")
             (tickscript-node-at-point t))
     ;; (message "TOPLEVEL")
     0)))

(defun tickscript-indent-non-toplevel-node ()
  "Indentation for non-toplevel nodes."
  (tickscript--at-bol
   (when (or (tickscript-node-at-point)
             (tickscript-chaining-method-at-point))
     ;; (message "NODE")
     tickscript-indent-offset)))

(defun tickscript-indent-udf ()
  "Indentation for user-defined functions."
  (tickscript--at-bol
   (when (tickscript-udf-at-point)
     ;; (message "UDF")
     tickscript-indent-offset)))

(defun tickscript-indent-property ()
  "Indentation for property members.
Properties can either be standard tickscript property names, or
be part of user-defined functions."
  (tickscript--at-bol
   (when (or (tickscript-property-at-point)
             ;; for now, anything starting with "." is a property, because of
             ;; UDFs. TODO: tighten this up to only work under real UDFs?
             (looking-at "\\."))
     ;; (message "PROP")
     (* 2 tickscript-indent-offset))))

(defun tickscript-indent-node-instance ()
  "Indentation for previously-defined nodes."
  (tickscript--at-bol
   (when (tickscript-at-node-instance)
     ;; (message "INSTANCE")
     0)))

(defun tickscript-indent-dedent-line ()
  "Deindent by `tickscript-indent-offset' spaces regardless of
current indentation context."
  (interactive)
  (indent-line-to (max 0 (- (current-indentation) tickscript-indent-offset))))

(defun tickscript-indent-line ()
  "Indent current line of TICKscript code."
  (interactive)
  (let* ((point-offset (- (current-column) (current-indentation))))
    (indent-line-to
     (or
      ;; Within a string
      (tickscript-indent-in-string)
      ;; Continuation line
      (tickscript-indent-in-continuation)
      ;; Comment lines
      (tickscript-indent-comment-line)
      ;; Top-level node w/optional var declaration
      (tickscript-indent-toplevel-node)
      ;; A child node or chaining method
      (tickscript-indent-non-toplevel-node)
      ;; A UDF
      (tickscript-indent-udf)
      ;; A property
      (tickscript-indent-property)
      ;; Previously-defined node
      (tickscript-indent-node-instance)
      ;;(error "Couldn't find a way to indent this line")
      0
      ))
    ;; We've indented and point is now at the beginning of indentation. Restore
    ;; it to its original position relative to the start of indentation.
    (when (>= point-offset 0)
      (move-to-column (+ (current-indentation) point-offset)))))

(defun tickscript-move-line-or-region-down (&optional beg end)
  "Move the current line or active region down."
  (interactive
   (if (use-region-p)
       (list (region-beginning) (region-end))
     (list nil nil)))
  (if beg
      (tickscript--move-region-vertically beg end 1)
    (tickscript--move-line-vertically 1)))

(defun tickscript-move-line-or-region-up (&optional beg end)
  "Move the current line or active region down."
  (interactive
   (if (use-region-p)
       (list (region-beginning) (region-end))
     (list nil nil)))
  (if beg
      (tickscript--move-region-vertically beg end -1)
    (tickscript--move-line-vertically -1)))

(defun tickscript--move-line-vertically (dir)
  (let* ((beg (point-at-bol))
         (end (point-at-bol 2))
         (col (current-column))
         (region (delete-and-extract-region beg end)))
    (forward-line dir)
    (save-excursion
      (insert region))
    (goto-char (+ (point) col))))

(defun tickscript--move-region-vertically (beg end dir)
  (let* ((point-before-mark (< (point) (mark)))
         (beg (save-excursion
                (goto-char beg)
                (point-at-bol)))
         (end (save-excursion
                (goto-char end)
                (if (bolp)
                    (point)
                  (point-at-bol 2))))
         (region (delete-and-extract-region beg end)))
    (goto-char beg)
    (forward-line dir)
    (save-excursion
      (insert region))
    (if point-before-mark
        (set-mark (+ (point)
                     (length region)))
      (set-mark (point))
      (goto-char (+ (point)
                    (length region))))
    (setq deactivate-mark nil)))


(defun tickscript--deftask-get-series-name ()
  (if tickscript-series-name
      tickscript-series-name
    (let ((resp (read-string "Series name: ")))
      (setq tickscript-series-name resp)
      (add-file-local-variable 'tickscript-series-name resp)
      resp)))


(defun tickscript--deftask-get-series-type ()
  (if tickscript-series-type
      tickscript-series-type
    (let ((resp (read-string "Series type (batch/stream): ")))
      (unless (member resp '("batch" "stream"))
        (error "Must specify \"batch\" or \"stream\""))
      (setq tickscript-series-type resp)
      (add-file-local-variable 'tickscript-series-type resp)
      resp)))


(defun tickscript--deftask-get-series-dbrp ()
  (if tickscript-series-dbrp
      tickscript-series-dbrp
    (let ((resp (read-string "Series DBRP (database.retention_policy): ")))
      (setq tickscript-series-dbrp resp)
      (add-file-local-variable 'tickscript-series-dbrp resp)
      resp)))

(defun tickscript--kapacitor-base-cmd ()
  "The command used to run `kapacitor', including the -url option."
  (if (and tickscript-kapacitor-url
           (not (string= tickscript-kapacitor-url "")))
      (format "%s -url %s" tickscript-kapacitor-prog-name tickscript-kapacitor-url)
    tickscript-kapacitor-prog-name))

(defun tickscript-define-task ()
  "Use Kapacitor to define the current task.

Prompts for any information needed to define the task, and then
calls Kapacitor to define it.  This information is cached in the
file comments for later re-use."
  (interactive)
  (save-buffer)
  ;; Reload file-local variables in case the user has changed them manually
  (hack-local-variables)
  (let* ((name (tickscript--deftask-get-series-name))
         (type (tickscript--deftask-get-series-type))
         (dbrp (tickscript--deftask-get-series-dbrp))
         (filename (file-name-nondirectory (buffer-file-name)))
         (cmd (format "%s define %s -type %s -tick %s -dbrp %s"
                      (tickscript--kapacitor-base-cmd) name type filename dbrp))
         (results (shell-command-to-string (format "echo -n \"%s - \" ; RESULT=`%s 2>&1`&& echo -n SUCCESS || echo FAILURE && echo -n $RESULT" cmd cmd))))
    (message results)))


(defun tickscript--cleanup-dot (dot)
  "Cleanup the broken DOT output generated by Kapacitor.
Escapes it properly so `dot' will actually render it."
  (let ((escaped (replace-regexp-in-string
                  (regexp-quote "]") "\"]"
                  (replace-regexp-in-string
                   (regexp-quote "[") "[\""
                   (replace-regexp-in-string
                    "\"" "\\\""
                    (replace-regexp-in-string
                     (regexp-quote "/") "\\/"
                     dot t t) t t)))))
    escaped))


(defun tickscript--extract-dot-from-buffer ()
  "Extract and return the DOT graph from the current buffer."
  (save-excursion
    (goto-char (point-min))
    (re-search-forward "^DOT:$")
    (forward-line 1)
    (let* ((beg (point))
           (end (point-max))
           (region (buffer-substring-no-properties beg end)))
      region)))

(defun tickscript--dump-cleaned-dot-to-buffer ()
  "Extract and clean the DOT from the current buffer, and dump it to a new buffer."
  (interactive)
  (let ((dot (tickscript--cleanup-dot (tickscript--extract-dot-from-buffer)))
        (buffer-name "*tickscript-dot-debug*"))
    (with-output-to-temp-buffer buffer-name
      (switch-to-buffer-other-window buffer-name)
      (insert dot))))

(defun tickscript-render-task-dot-to-buffer ()
  "Extract the DOT graph from the current buffer, render it with Graphviz, and insert the image."
  (interactive)
  (let* ((dot (tickscript--extract-dot-from-buffer))
         (cleaned (tickscript--cleanup-dot dot))
         (tmpfile (format "/%s/%s.png" temporary-file-directory (make-temp-name "tickscript-")))
         (cmd (format "echo \"%s\" | dot -T png -o %s" cleaned tmpfile)))
    (shell-command cmd)
    (goto-char (point-max))
    (insert-char ?\n)
    (let ((inhibit-read-only t)
          (image (if (image-type-available-p 'imagemagick)
                     (create-image tmpfile 'imagemagick nil
                                   :max-width (truncate (* .9 (window-pixel-width))))
                   (create-image tmpfile))))
      (insert-image image))))


(defun tickscript-show-task ()
  "Use Kapacitor to show the definition of the current task."
  (interactive)
  (let* ((name (tickscript--deftask-get-series-name))
         (task (shell-command-to-string (format "%s show %s"
                                                tickscript-kapacitor-prog-name name)))
         (buffer-name "*tickscript-task*"))
    (with-output-to-temp-buffer buffer-name
      (switch-to-buffer-other-window buffer-name)
      (erase-buffer)
      (set (make-local-variable 'font-lock-defaults) '(tickscript-font-lock-keywords))
      (set (make-local-variable 'comment-start) "// ")
      (set-syntax-table tickscript-mode-syntax-table)
      (font-lock-mode)
      (insert task)
      (when tickscript-render-dot-output
        (tickscript-render-task-dot-to-buffer)))))


(defun tickscript--list-things (noun)
  (let ((things
         (shell-command-to-string (format "%s list %s" tickscript-kapacitor-prog-name noun)))
        (buffer-name (format "*tickscript-%s*" noun)))
    (with-output-to-temp-buffer buffer-name
      (unless (equal (buffer-name) buffer-name)
        (switch-to-buffer-other-window buffer-name))
      (set (make-local-variable 'font-lock-defaults) '(tickscript-font-lock-keywords))
      (set (make-local-variable 'revert-buffer-function)
           (lambda (_ignore-auto _noconfirm) (tickscript--list-things noun)))
      (font-lock-mode)
      (insert things))))

(defun tickscript-list-tasks ()
  "Use Kapacitor to list all defined tasks."
  (interactive)
  (tickscript--list-things "tasks"))

(defun tickscript-list-recordings ()
  "Use Kapacitor to list all recordings."
  (interactive)
  (tickscript--list-things "recordings"))

(defun tickscript-list-replays ()
  "Use Kapacitor to list all replays."
  (interactive)
  (tickscript--list-things "replays"))

(defun tickscript--downcase-for-webhelp (word)
  (or (gethash word tickscript-webhelp-case-map) (downcase word)))

(defun tickscript-get-help ()
  "Gets help for the node or property at point, if any."
  (interactive)
  (let* ((node (tickscript-current-node))
         (chaining-method-or-property (or (tickscript-chaining-method-at-point)
                                          (tickscript-property-at-point))))
    ;; We must have found a containing node, and either be pointing at it, or
    ;; have found a legitimate chaining method/property child
    (unless (and node
                 (or (tickscript-node-at-point)
                     chaining-method-or-property))
      (error "Could not find help topic for thing at point"))
    (let ((url (format "https://docs.influxdata.com/kapacitor/v1.3/nodes/%s_node/"
                       (tickscript--downcase-for-webhelp node))))
      (when chaining-method-or-property
        (setq url (format "%s#%s" url (tickscript--downcase-for-webhelp chaining-method-or-property))))
      (browse-url url))))

;;;###autoload
(define-derived-mode tickscript-mode prog-mode "Tickscript"
  "Major mode for editing TICKscript files

\\{tickscript-mode-map}"
  :syntax-table tickscript-mode-syntax-table

  (set (make-local-variable 'indent-tabs-mode) nil)
  (set (make-local-variable 'font-lock-defaults) '(tickscript-font-lock-keywords))

  (set (make-local-variable 'comment-start) "// ")

  (set (make-local-variable 'indent-line-function) 'tickscript-indent-line)

  ;; Task definition
  (set (make-local-variable 'tickscript-series-name) nil)
  (set (make-local-variable 'tickscript-series-type) nil)
  (set (make-local-variable 'tickscript-series-dbrp) nil)
  )

;;;###autoload
(add-to-list 'auto-mode-alist '("\\.tick\\'" . tickscript-mode))

(provide 'tickscript-mode)
;;; tickscript-mode.el ends here
