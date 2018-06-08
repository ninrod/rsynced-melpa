;;; org-index.el --- A personal adaptive index for org  -*- lexical-binding: t; -*-

;; Copyright (C) 2011-2018 Free Software Foundation, Inc.

;; Author: Marc Ihm <org-index@2484.de>
;; URL: https://github.com/marcIhm/org-index
;; Package-Version: 20180519.725
;; Version: 5.8.9
;; Package-Requires: ((emacs "24.4"))

;; This file is not part of GNU Emacs.

;;; License:

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation; either version 3, or (at your option)
;; any later version.
;;
;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.
;;
;; You should have received a copy of the GNU General Public License
;; along with GNU Emacs.  If not, see <http://www.gnu.org/licenses/>.

;;; Commentary:

;; Purpose:
;;
;;  Fast search for selected org nodes and things outside of org.
;;
;;  org-index creates and updates an index table with keywords; each line
;;  either points to a heading in org, references something outside or
;;  carries a snippet of text to yank.  When searching the index, the set
;;  of matching lines is updated with every keystroke; results are sorted
;;  by usage count and date, so that frequently used entries appear first
;;  in the list of results.
;;
;;  In addition, org-index introduces these supplemental concepts:
;;
;;  - References are decorated numbers (e.g. 'R237' or '--455--'); they are
;;    well suited to be used outside of org, e.g. in folder names,
;;    ticket systems or on printed documents.
;;  - Focus is a small set of nodes for your daily work; it can be managed
;;    and traversed easily.
;;
;;  On first invocation org-index will assist you in creating the index
;;  table.
;;
;;  To start using your index, invoke the subcommand 'add' to create
;;  entries and 'occur' to find them.
;;
;;
;; Setup:
;;
;;  - org-index can be installed with package.el
;;  - Invoke `org-index'; on first run it will assist in creating your
;;    index table.
;;
;;  - Optionally invoke `M-x org-customize', group 'Org Index', to tune
;;    its settings.
;;
;;
;; Further information:
;;
;;  - Watch the screencast at http://2484.de/org-index.html.
;;  - See the documentation of `org-index', which can also be read by
;;    invoking `org-index' and typing '?'.
;;
;;

;;; Change Log:

;; 
;;  - See the command 'news' for recent changes, or
;;  - https://github.com/marcIhm/org-index/ChangeLog.org    for older news
;;  - https://github.com/marcIhm/org-index/commits/master   for a complete list of changes
;;
;;

;;; Code:

;;
;;  Please note, that this package uses two prefixes, `org-index' for user
;;  visible symbols and `oidx' (which is shorter) for internal stuff.
;;
;;  Code can be folded and browsed with `hs-minor-mode'.
;; 

(require 'org-table)
(require 'org-id)
(require 'org-inlinetask)
(require 'cl-lib)
(require 'widget)

;; Version of this package
(defvar org-index-version "5.8.9" "Version of `org-index', format is major.minor.bugfix, where \"major\" are incompatible changes and \"minor\" are new features.")

;; customizable options
(defgroup org-index nil
  "Options concerning the optional index for org."
  :tag "Org Index"
  :group 'org)

(defcustom org-index-id nil
  "Id of the Org-mode node, which contains the index table."
  :type 'string
  :group 'org-index)

(defcustom org-index-sort-by 'mixed
  "Strategy for sorting index table (and whence entries in occur).
Valid values are:

last-access  Sort index by date and time of last access; show
             more recent entries first.
count  Sort by usage count; more often used entries first.
mixed  First, show all index entries, which have been
       used today; sort them by last access.  Then show
       older entries sorted by usage count."
  :group 'org-index
  :set (lambda (s v)
         (custom-set-default s v)
         (if (and org-index-id
                  oidx--buffer
                  (functionp 'oidx--sort-silent))
             (oidx--sort-silent)))
  :initialize 'custom-initialize-default
  :type '(choice
	  (const last-accessed)
	  (const count)
	  (const mixed)))

(defcustom org-index-key nil
  "Key to invoke ‘org-index’, which is the central entry function for ‘org-index’."
  :group 'org-index
  :initialize 'custom-initialize-set
  :set (lambda (var val)
         (custom-set-default var val)
         (when val
           (global-set-key org-index-key 'org-index)))
  :type 'key-sequence)

(defcustom org-index-idle-delay 68
  "Delay in seconds after which buffer will sorted or fontified when Emacs is idle."
  :group 'org-index
  :type 'integer)

(defcustom org-index-prepare-when-idle nil
  "Fontify and sort index-table when idle to make first call faster.
You only need this if your index has grown so large, that first
invocation of `org-index' needs a noticable amount of time."
  :group 'org-index
  :initialize 'custom-initialize-set
  :set (lambda (var val)
         (custom-set-default var val)
         (when val
           (run-with-idle-timer org-index-idle-delay nil 'oidx--idle-prepare)))
  :type 'boolean)

(defcustom org-index-yank-after-add 'ref
  "Specifies which column should be yanked after adding a new index row.
Valid values are some columns of index table."
  :group 'org-index
  :type '(choice
	  (const ref)
	  (const category)
	  (const keywords)))

(defcustom org-index-copy-heading-to-keywords t
  "When adding a new node to index: Copy heading to keywords-column ?"
  :group 'org-index
  :type '(choice (const :tag "Yes" t)
                 (const :tag "No" nil)))

(defcustom org-index-strip-ref-and-date-from-heading t
  "When adding a node to index: strip leading ref or timestamps ?

This can be useful, if you have the habit of adding refs and
dates to the start of your headings; then, if you change your
heading and want to update your index, you do not need to remove
those pieces."
  :group 'org-index
  :type '(choice (const :tag "Yes" t)
                 (const :tag "No" nil)))

(defcustom org-index-edit-on-add '(category keywords)
  "List of columns to edit when adding a new row."
  :group 'org-index
  :type '(repeat (choice
                  (const category)
                  (const keywords))))

(defcustom org-index-edit-on-yank '(keywords yank)
  "List of columns to edit when adding new text to yank."
  :group 'org-index
  :type '(repeat (choice
                  (const yank)
                  (const category)
                  (const keywords))))

(defcustom org-index-edit-on-ref '(category keywords)
  "List of columns to edit when adding new ref."
  :group 'org-index
  :type '(repeat (choice
                  (const category)
                  (const keywords))))

(defcustom org-index-clock-into-focus nil
  "Clock into focused node ?"
  :group 'org-index
  :type 'boolean)

(defcustom org-index-show-focus-overlay t
  "Show overlay text when changing focus."
  :group 'org-index
  :type 'boolean)

(defcustom org-index-goto-bottom-after-focus nil
  "After visiting a focused nodes; position cursor at bottom of node (as opposed to heading) ?"
  :group 'org-index
  :type 'boolean)

;; Variables to hold the configuration of the index table
(defvar oidx--head nil "Header before number (e.g. 'R').")
(defvar oidx--tail nil "Tail after number (e.g. '}' or ')'.")
(defvar oidx--numcols nil "Number of columns in index table.")
(defvar oidx--ref-regex nil "Regular expression to match a reference.")
(defvar oidx--ref-format nil "Format, that can print a reference.")
(defvar oidx--columns nil "Columns of index-table.")
(defvar oidx--buffer nil "Buffer of index table.")
(defvar oidx--point nil "Position at start of headline of index table.")
(defvar oidx--below-hline nil "Position of first cell in first line below hline.")
(defvar oidx--saved-positions nil "Saved positions within current buffer and index buffer; filled by ‘oidx--save-positions’.")
(defvar oidx--headings nil "Headlines of index-table as a string.")
(defvar oidx--headings-visible nil "Visible part of headlines of index-table as a string.")
(defvar oidx--ids-focused-nodes nil "Ids of focused node (if any).")
(defvar oidx--ids-focused-nodes-saved nil "Backup for ‘oidx--ids-focused-nodes’.")
(defvar oidx--id-last-goto-focus nil "Id of last node, that has been focused to.")

;; Variables to hold context and state
;; Variables for occur, see the respective section
(defvar oidx--buffer nil "Buffer, that contains index.")
(defvar oidx--last-fingerprint nil "Fingerprint of last line created.")
(defvar oidx--category-before nil "Category of node before.")
(defvar oidx--active-region nil "Active region, initially.  I.e. what has been marked.")
(defvar oidx--below-cursor nil "Word below cursor.")
(defvar oidx--within-index-node nil "Non-nil, if we are within node of the index table.")
(defvar oidx--within-occur nil "Non-nil, if we are within the occur-buffer.")
(defvar oidx--message-text nil "Text that was issued as an explanation; helpful for regression tests.")
(defvar oidx--last-sort-assumed nil "Last column, the index has been sorted after (best guess).")
(defvar oidx--sort-timer nil "Timer to sort index in correct order.")
(defvar oidx--inhibit-sort-idle nil "If set, index will not be sorted in idle background.")
(defvar oidx--aligned 0 "For this Emacs session: remember number of table lines aligned.")
(defvar oidx--align-interactive most-positive-fixnum "Number of rows to align in ‘oidx--parse-table’.")
(defvar oidx--edit-widgets nil "List of widgets used to edit.")
(defvar oidx--context-index nil "Position and line used for index in edit buffer.")
(defvar oidx--context-occur nil "Position and line used for occur in edit buffer.")
(defvar oidx--context-node nil "Buffer and position for node in edit buffer.")
(defvar oidx--short-help-buffer-name "*org-index commands*" "Name of buffer to display short help.")
(defvar oidx--news-buffer-name "*org-index news*" "Name of buffer to display news.")
(defvar oidx--short-help-wanted nil "Non-nil, if short help should be displayed.")
(defvar oidx--short-help-displayed nil "Non-nil, if short help message has been displayed.")
(defvar oidx--prefix-arg nil "Non-nil, if prefix argument has been received during input.")
(defvar oidx--minibuffer-saved-key nil "Temporarily save entry of minibuffer keymap.")
(defvar oidx--this-command nil "Subcommand, that is currently excecuted.")
(defvar oidx--last-command nil "Subcommand, that hast been excecuted last.")
(defvar oidx--last-focus-message nil "Last message issued by focus-command.")
(defvar oidx--cancel-focus-wait-function nil "Function to call on timeout for focus commands.")
(defvar oidx--focus-cancel-timer nil "Timer to cancel waiting for key.")
(defvar oidx--focus-overlay nil "Overlay to display name of focus node.")
(defvar oidx--skip-verify-id nil "If true, do not verify index id; intended to be let-bound.")

;; static information for this program package
(defconst oidx--commands '(occur add kill head ping index ref yank column edit help short-help news focus example sort find-ref highlight maintain) "List of commands available.")
(defconst oidx--valid-headings '(ref id created last-accessed count keywords category level yank tags) "All valid headings.")
(defconst oidx--edit-buffer-name "*org-index-edit*" "Name of edit buffer.")
(defvar oidx--short-help-text nil "Cache for result of `oidx--get-short-help-text.")
(defvar oidx--shortcut-chars nil "Cache for result of `oidx--get-shortcut-chars.")


(defmacro oidx--on (column value &rest body)
  "Execute the forms in BODY with point on index line whose COLUMN is VALUE.
The value returned is the value of the last form in BODY or nil,
if VALUE cannot be found."
  (declare (indent 2) (debug t))
  (let ((pointvar (make-symbol "point"))
        (foundvar (make-symbol "found"))
        (retvar (make-symbol "ret")))
    `(save-current-buffer
       (let ((,pointvar (point))
             ,foundvar
             ,retvar)

         (set-buffer oidx--buffer)

         (setq ,foundvar (oidx--go ,column ,value))
         (when ,foundvar
           (setq ,retvar (progn ,@body)))
         
         (goto-char ,pointvar)
         
         ,retvar))))


(defun org-index (&optional arg)
  "Fast search-index for selected org nodes and things outside.

This function creates and updates an index table with keywords;
each line either points to a heading in org, references something
outside or carries a snippet of text to yank.  When searching the
index, the set of matching lines is updated with every keystroke;
results are sorted by usage count and date, so that frequently
used entries appear first in the list of results.

In addition, org-index introduces these supplemental concepts:
- References are decorated numbers (e.g. 'R237' or '--455--'); they are
  well suited to be used outside of org, e.g. in folder names,
  ticket systems or on printed documents.
- Focus is a small set of nodes for your daily work; it can be managed
  and traversed easily.

On first invocation org-index will assist you in creating the index
table.

To start using your index, invoke the subcommand 'add' to create
entries and 'occur' to find them.

This is version 5.8.9 of org-index.el.

The function `org-index' is the only interactive function of this
package and its main entry point; it will present you with a list
of subcommands to choose from:

\(Note the one-letter shortcuts, e.g. [o]; used like `\\[org-index] o'.)

  occur: [o] Incrementally show matching lines from index.
    Result is updated after every keystroke.  You may enter a
    list of words seperated by space or comma (`,'), to select
    lines that contain all of the given words. With a numeric
    prefix argument, show lines, which have been accessed at
    most this many days ago.

  add: [a] Add the current node to index.
    So that (e.g.) it can be found through the subcommand
    'occur'.  Update index, if node is already present.

  kill: [k] Kill (delete) the current node from index.
    Can be invoked from index, from occur or from a headline.

  head: [h] Search for heading, by ref or from index line.
    If invoked from within index table, go to associated
    node (if any), otherwise ask for ref to search.
  
  index: [i] Enter index table and maybe go to a specific reference.
    Use `org-mark-ring-goto' (\\[org-mark-ring-goto]) to go back.

  ping: [p] Echo line from index table for current node.
    If current node is not in index, than search among its
    parents.

  ref: [r] Create a new index line with a reference.
    This line will not be associated with a node.

  yank: [y] Store a new string, that can be yanked from occur.
    The index line will not be associated with a node.

  column: [c] From within index table: read char and jump to column.
    Shortcut for column movement; stays within one index line.

  edit: [e] Present current line in edit buffer.
    Can be invoked from index, from occur or from a headline.

  focus: [f] Return to first focused node; repeat to see them all.
    The focused nodes are kept in a short list; they need not be
    part of the index though.  With a prefix argument, this
    command offers more options, e.g. to set focus initially.

  help: Show complete help text of `org-index'.
    I.e. this text.

  short-help: [?] Show one-line descriptions of each subcommand.
    I.e. from the complete help, show only the first line for each
    subcommand.

  news: [n] Show news for the current point release.

  example: Create an example index, that will not be saved.
    May serve as an example.

  sort: Sort lines in index, in region or buffer.
    Region or buffer can be sorted by contained reference; Index
    by count, reference or last access.

  find-ref: Search for given reference in all org-buffers.
    A wrapper to employ Emacs standard `multi-occur' function;
    asks for reference.

  highlight: Highlight or unhighlight all references.
     Operates on active region or whole buffer.  Call with prefix
     argument (`C-u') to remove highlights.

  maintain: [m] Index maintainance.
     Offers some choices to check, update or fix your index.

If you invoke `org-index' for the first time, an assistant will be
invoked, that helps you to create your own index.

Invoke `org-customize' to tweak the behaviour of `org-index'.

This includes the global key `org-index-key' to invoke
the most important subcommands with one additional key.

A numeric prefix argument is used as a reference number for
commands, that need one (e.g. 'head') or to modify their
behaviour (e.g. 'occur').

Also, a single prefix argument may be specified just before the
final character or by just typing an upper case letter.

Use from elisp: Optional argument COMMAND is a symbol naming the
command to execute.  SEARCH-REF specifies a reference to search
for, if needed.  ARG allows passing in a prefix argument as in
interactive calls."
  (interactive "P")

  (catch 'new-index
    (oidx--verify-id)
    (let (char command (c-u-text (if arg " C-u " "")))
      (while (not char)
        (if (sit-for 1)
            (message (concat "org-index (type a shortcut char or <space> or ? for a detailed prompt) -" c-u-text)))
        (setq char (key-description (read-key-sequence nil)))
        (if (string= char "C-g") (keyboard-quit))
        (if (string= char "SPC") (setq char "?"))
        (when (string= char (upcase char))
          (setq char (downcase char))
          (setq arg (or arg '(4))))
        (when (string= char "C-u")
          (setq arg (or arg '(4)))
          (setq c-u-text " C-u ")
          (setq char nil)))
      (setq command (cdr (assoc char (oidx--get-shortcut-chars))))
      (unless command
        (when (yes-or-no-p (format "No subcommand for '%s'; switch to detailed prompt ? " char))
          (setq command 'short-help)))

      (let ((oidx--skip-verify-id t))
        (oidx--do command nil arg)))))


(defun oidx--do (&optional command search-ref arg)
  "Does the work for `org-index', for arguments COMMAND, SEARCH-REF and ARG see there."
  (interactive "i\ni\nP")

  (let (search-id             ; id to search for
        search-fingerprint    ; fingerprint to search for
        sort-what             ; sort what ?
        kill-new-text         ; text that will be appended to kill ring
        message-text)         ; text that will be issued as an explanation


    (catch 'new-index

      ;;
      ;; Initialize and parse
      ;;

      ;; creates index table, if necessary
      (oidx--verify-id)

      ;; Get configuration of index table
      (oidx--parse-table oidx--align-interactive t)

      ;; store context information
      (oidx--retrieve-context)


      ;;
      ;; Arrange for proper sorting of index
      ;;

      ;; lets assume, that it has been sorted this way (we try hard to make sure)
      (unless oidx--last-sort-assumed (setq oidx--last-sort-assumed org-index-sort-by))
      ;; rearrange for index beeing sorted into default sort order after 300 secs of idle time
      (unless oidx--sort-timer
        (setq oidx--sort-timer
              (run-with-idle-timer org-index-idle-delay t 'oidx--sort-silent)))


      ;;
      ;; Find out, what we are supposed to do
      ;;

      ;; Check or read command
      (if (and command (not (eq command 'short-help)))
          (unless (memq command oidx--commands)
            (error "Unknown command '%s' passed as argument, valid choices are any of these symbols: %s"
                   command (mapconcat 'symbol-name oidx--commands ",")))
        
        ;; read command; if requested display help in read-loop
        (setq oidx--short-help-wanted (eq command 'short-help))
        (setq command (oidx--read-command))
	(if oidx--prefix-arg (setq arg (or arg '(4))))
        (setq oidx--short-help-wanted nil))

      (setq oidx--last-command oidx--this-command)
      (setq oidx--this-command command)


      ;;
      ;; Get search string, if required; process possible sources one after
      ;; another (lisp argument, prefix argument, user input).
      ;;

      ;; Try prefix, if no lisp argument given
      (if (and (not search-ref)
               (numberp arg))
          (setq search-ref (format "%s%d%s" oidx--head arg oidx--tail)))
      
      ;; These actions really need a search string and may even prompt for it
      (when (memq command '(index head find-ref))

        ;; search from surrounding text ?
        (unless search-ref
          (if oidx--within-index-node

              (if (org-at-table-p)
                  (setq search-ref (oidx--get-or-set-field 'ref)))
            
            (if (and oidx--below-cursor
                     (string-match (concat "\\(" oidx--ref-regex "\\)")
                                   oidx--below-cursor))
                (setq search-ref (match-string 1 oidx--below-cursor)))))
        
        ;; If we still do not have a search string, ask user explicitly
        (unless search-ref
          (if (eq command 'index)
              (let ((r (oidx--read-search-for-command-index)))
                (setq search-ref (cl-first r))
                (setq search-id (cl-second r))
                (setq search-fingerprint (cl-third r)))
            (unless (and (eq command 'head)
                         oidx--within-index-node
                         (org-at-table-p))
              (setq search-ref (read-from-minibuffer "Search reference number: ")))))

        ;; Clean up search string
        (when search-ref
          (setq search-ref (org-trim search-ref))
          (if (string-match "^[0-9]+$" search-ref)
              (setq search-ref (concat oidx--head search-ref oidx--tail)))
          (if (string= search-ref "") (setq search-ref nil)))

        (if (and (not search-ref)
                 (not (eq command 'index))
                 (not (and (eq command 'head)
                           oidx--within-index-node
                           (org-at-table-p))))
            (error "Command %s needs a reference number" command)))

      
      ;;
      ;; Command sort needs to know in advance, what to sort for
      ;;
      
      (when (eq command 'sort)
        (setq sort-what (intern (oidx--completing-read "You may sort:\n  - index  : your index table by various columns\n  - region : the active region by contained reference\n  - buffer : the whole current buffer\nPlease choose what to sort: " (list "index" "region" "buffer")))))
      
      
      ;;
      ;; Enter table
      ;;

      ;; Arrange for beeing able to return
      (when (and (memq command '(occur head index example sort maintain focus))
                 (not (string= (buffer-name) oidx--occur-buffer-name)))
        (org-mark-ring-push))

      ;; These commands will leave user in index table after they are finished
      (when (or (memq command '(index maintain))
                (and (eq command 'sort)
                     (eq sort-what 'index)))

        (pop-to-buffer-same-window oidx--buffer)
        (goto-char oidx--point)
        (oidx--unfold-buffer))


      ;;
      ;; Actually do, what is requested
      ;;

      (cond
       
       ((eq command 'help)

        ;; bring up help-buffer for this function
        (describe-function 'org-index))

       
       ((eq command 'short-help)

        (oidx--display-short-help))

       
       ((eq command 'news)
        (with-current-buffer-window
         oidx--news-buffer-name nil nil
         (insert (format "News for Version %s of org-index:\n"
                         (progn
                           (string-match "\\([0-9]+\\.[0-9]+\\)\\." org-index-version)
                           (match-string 1 org-index-version))))
         ;; Copy the text from ChangeLog.org unchanged into the following string
         (insert "
  - Timeout in prompt for additional focus-command
  - Popup to show current node during after focus change
  - Various changes to become ready for melpa
  - Refactored org-index--do-occur (now named oidx--do-occur), creating various new functions
  - Restructured source code, grouping related functions together; groups are separated as usual by 
  - Introduced the secondary prefix 'oidx--' and renamed everything starting with 'org-index--'. Functions and
    variables starting with 'org-index-' are left untouched.
  - Renamed functions org-index-dispatch to org-index, org-index to oidx--do and variable org-index-dispatch-key
    to org-index-key
")
         (insert "\nSee https://github.com/marcIhm/org-index/ChangeLog.org for older news.\n")
         (org-mode))
        (shrink-window-if-larger-than-buffer (get-buffer-window oidx--news-buffer-name)))
       

       ((eq command 'find-ref)

        ;; Construct list of all org-buffers
        (let (org-buffers)
          (dolist (buff (buffer-list))
            (set-buffer buff)
            (if (string= major-mode "org-mode")
                (setq org-buffers (cons buff org-buffers))))

          ;; Do multi-occur
          (multi-occur org-buffers (oidx--make-guarded-search search-ref))

          ;; Present results
          (if (get-buffer "*Occur*")
              (progn
                (setq message-text (format "Found '%s'" search-ref))
                (other-window 1)
                (toggle-truncate-lines 1))
            (setq message-text (format "Did not find '%s'" search-ref)))))


       ((eq command 'add)

        (let ((r (oidx--do-add-or-update (if (equal arg '(4)) t nil)
                                         (if (numberp arg) arg nil))))
          (setq message-text (car r))
          (setq kill-new-text (cdr r))))


       ((eq command 'kill)
        (setq message-text (oidx--do-kill)))


       ((eq command 'head)

        (if (and oidx--within-index-node
                 (org-at-table-p))
            (setq search-id (oidx--get-or-set-field 'id)))
        
        (if (and (not search-id) search-ref)
            (setq search-id (oidx--id-from-ref search-ref)))
        
        (setq message-text
              (if search-id
                  (oidx--find-id search-id)
                "Current line has no id")))


       ((eq command 'index)

        (goto-char oidx--below-hline)

        (setq message-text

              (if search-ref
                  (if (oidx--go 'ref search-ref)
                      (progn
                        (oidx--update-current-line)
                        (org-table-goto-column (oidx--column-num 'ref))
                        (format "Found index line '%s'" search-ref))
                    (format "Did not find index line with reference '%s'" search-ref))

                (if search-id
                    (if (oidx--go 'id search-id)
                        (progn
                          (oidx--update-current-line)
                          (org-table-goto-column (oidx--column-num 'ref))
                          (format "Found index line '%s'" (oidx--get-or-set-field 'ref)))
                      (format "Did not find index line with id '%s'" search-id))

                  (if search-fingerprint
                      (if (oidx--go 'fingerprint oidx--last-fingerprint)
                          (progn
                            (oidx--update-current-line)
                            (beginning-of-line)
                            (format "Found latest index line"))
                        (format "Did not find index line"))

                    ;; simply go into table
                    "At index table"))))

        (recenter))


       ((eq command 'ping)

        (let ((moved-up 0) id info reached-top done)
          
          (unless (string= major-mode "org-mode") (error "Not in org-mode"))
          ;; take id from current node or reference
          (setq id (if search-ref
                       (oidx--id-from-ref search-ref)
                     (org-id-get)))

          ;; move up until we find a node in index
          (save-excursion
            (org-with-limited-levels (org-back-to-heading))
            (while (not done)
              (if id
                  (setq info (oidx--on 'id id
                               (mapcar (lambda (x) (oidx--get-or-set-field x))
                                       (list 'keywords 'count 'created 'last-accessed 'category 'ref)))))

              (setq reached-top (= (org-outline-level) 1))

              (if (or info reached-top)
                  (setq done t)
                (outline-up-heading 1 t)
                (cl-incf moved-up))

              (setq id (org-id-get))))
          
          (if info
              (progn
                (setq message-text
                      (apply 'format
                             (append (list "'%s'%s has been accessed %s times between %s and %s; category is '%s', reference is '%s'"
                                           (pop info)
                                           (if (> moved-up 0) (format " (parent node, %d level up)" moved-up) ""))
                                     info)))
                (setq kill-new-text (car (last info))))
            (setq message-text "Neither this node nor any of its parents is part of index"))))


       ((eq command 'occur)

        (set-buffer oidx--buffer)
        (oidx--do-occur (if (numberp arg) arg nil)))


       ((eq command 'ref)

        (let (args newref)

          (setq args (oidx--collect-values-from-user org-index-edit-on-ref))
          (setq newref (oidx--get-save-maxref))
          (setq args (plist-put args 'ref newref))
          (apply 'oidx--do-new-line args)

          (setq kill-new-text newref)

          (setq message-text (format "Added new row with ref '%s'" newref))))


       ((eq command 'yank)

        (let (args)

          (setq args (oidx--collect-values-from-user org-index-edit-on-yank))
          (if (plist-get args 'yank)
              (plist-put args 'yank (replace-regexp-in-string "|" "\\vert" (plist-get args 'yank) nil 'literal)))
          (setq args (plist-put args 'category "yank"))
          (apply 'oidx--do-new-line args)
          
          (setq message-text "Added new row with text to yank")))


       ((eq command 'column)

        (if (and oidx--within-index-node
                 (org-at-table-p))
            (let (char col num)
              (setq char (read-char "Please specify, which column to go to (r=ref, k=keywords, c=category, y=yank): "))
              (unless (memq char (list ?r ?k ?c ?y))
                (error (format "Invalid char '%c', cannot goto this column" char)))
              (setq col (cdr (assoc char '((?r . ref) (?k . keywords) (?c . category) (?y . yank)))))
              (setq num (oidx--column-num col))
              (if num
                  (progn
                    (org-table-goto-column num)
                    (setq message-text (format "At column %s" (symbol-name col))))
                
                (error (format "Column '%s' is not present" col))))
          (error "Need to be in index table to go to a specific column")))
       

       ((eq command 'edit)

        (setq message-text (oidx--do-edit)))
       

       ((eq command 'sort)

        (let ((sorts (list "count" "last-accessed" "mixed" "id" "ref"))
              sort groups-and-counts)

          (cond
           ((eq sort-what 'index)
            (setq sort
                  (intern
                   (oidx--completing-read
                    "Please choose column to sort index table: "
                    (cl-copy-list sorts)
                    (symbol-name org-index-sort-by))))

            (oidx--do-sort-index sort)
            (org-table-goto-column (oidx--column-num (if (eq sort 'mixed) 'last-access sort)))
            ;; When saving index, it should again be sorted correctly
            (with-current-buffer oidx--buffer
              (add-hook 'before-save-hook 'oidx--sort-silent t))
            
            (setq message-text
                  (format
                   (concat "Your index has been sorted temporarily by %s and will be sorted again by %s after %d seconds of idle time"
                           (if groups-and-counts
                               "; %d groups with equal %s and a total of %d lines have been found"
                             ""))
                   (symbol-name sort)
                   org-index-sort-by
                   org-index-idle-delay
                   (cl-second groups-and-counts)
                   (symbol-name sort)
                   (cl-third groups-and-counts))))

           ((memq sort-what '(region buffer))
            (oidx--do-sort-lines sort-what)
            (setq message-text (format "Sorted %s by contained references" sort-what))))))


       ((eq command 'highlight)

        (let ((where "buffer"))
          (save-excursion
            (save-restriction
              (when (and transient-mark-mode
                         mark-active)
                (narrow-to-region (region-beginning) (region-end))
                (setq where "region"))

              (if arg
                  (progn
                    (unhighlight-regexp oidx--ref-regex)
                    (setq message-text (format "Removed highlights for references in %s" where)))
                (highlight-regexp oidx--ref-regex 'isearch)
                (setq message-text (format "Highlighted references in %s" where)))))))


       ((eq command 'focus)
        (let ((mt (if arg
                      (oidx--more-focus-commands)
                    (setq oidx--last-focus-message nil)
                    (oidx--goto-focus))))
          (setq message-text (concat (upcase (substring mt 0 1)) (substring mt 1)))))


       ((eq command 'maintain)
        (setq message-text (oidx--do-maintain)))

       
       ((eq command 'example)

        (if (y-or-n-p "This assistant will help you to create a temporary index with detailed comments.\nDo you want to proceed ? ")
            (oidx--create-index t)))


       ((not command) (setq message-text "No command given"))

       
       (t (error "Unknown subcommand '%s'" command)))


      ;; tell, what we have done and what can be yanked
      (if kill-new-text (setq kill-new-text
                              (substring-no-properties kill-new-text)))
      (if (string= kill-new-text "") (setq kill-new-text nil))
      (let ((m (concat
                message-text
                (if (and message-text kill-new-text)
                    " and r"
                  (if kill-new-text "R" ""))
                (if kill-new-text (format "eady to yank '%s'." kill-new-text) (if message-text "." "")))))
        (unless (string= m "")
          (message m)
          (setq oidx--message-text m)))
      (if kill-new-text (kill-new kill-new-text)))))


(defalias 'org-index-dispatch 'org-index) ; for backward compatibility


(defun org-index-new-line (&rest keys-values)
  "Create a new line within the index table, returning its reference.

The function takes a varying number of argument pairs; each pair
is a symbol for an existing column heading followed by its value.
The return value is the new reference.

Example:

  (message \"Created reference %s\"
           (org-index-new-line 'keywords \"foo bar\" 'category \"baz\"))

Optional argument KEYS-VALUES specifies content of new line."

  (let ((ref (plist-get keys-values 'ref)))
    (oidx--verify-id)
    (oidx--parse-table)
    (if (not (memq ref  '(t nil)))
        (error "Column 'ref' accepts only 't' or 'nil'"))
    (when ref
      (setq ref (oidx--get-save-maxref))
      (setq keys-values (plist-put keys-values 'ref ref)))

    (apply 'oidx--do-new-line keys-values)
    ref))



;; Reading user input
(defun oidx--read-command ()
  "Read subcommand for ‘org-index’ from minibuffer."
  (let (minibuffer-scroll-window
        command)
    (setq oidx--short-help-displayed nil)
    (setq oidx--prefix-arg nil)
    (add-hook 'minibuffer-setup-hook 'oidx--minibuffer-setup-function)
    (add-hook 'minibuffer-exit-hook 'oidx--minibuffer-exit-function)
    (unwind-protect
        (setq command
              (completing-read
               (concat
                "Please choose"
                (if oidx--short-help-wanted "" " (<space> or ? for short help)")
                ": ")
               (append (mapcar 'symbol-name oidx--commands)
                       (mapcar 'upcase-initials (mapcar 'symbol-name oidx--commands)))))
      (remove-hook 'minibuffer-setup-hook 'oidx--minibuffer-setup-function)
      (remove-hook 'minibuffer-exit-hook 'oidx--minibuffer-exit-function)
      (when command
        (unless (string= command (downcase command))
          (setq command (downcase command))
          (setq oidx--prefix-arg '(4)))
        (setq command (intern command)))
      (when oidx--short-help-displayed
        (quit-windows-on oidx--short-help-buffer-name)))
    command))


(defun oidx--minibuffer-setup-function ()
  "Prepare minibuffer for `oidx--read-command'."
  (setq oidx--minibuffer-saved-key (local-key-binding (kbd "?")))
  (local-set-key (kbd "?") 'oidx--display-short-help)
  (local-set-key (kbd "C-u") (lambda () (interactive)
			       (setq oidx--prefix-arg t)
			       (message "C-u")))
  (if oidx--short-help-wanted (oidx--display-short-help)))


(defun oidx--minibuffer-exit-function ()
  "Restore minibuffer after `oidx--read-command'."
  (local-set-key (kbd "?") oidx--minibuffer-saved-key)
  (local-set-key (kbd "C-u") 'universal-argument)
  (setq oidx--minibuffer-saved-key nil))


(defun oidx--display-short-help (&optional prompt choices)
  "Helper function to show help for minibuffer and PROMPT for CHOICES."
  (interactive)

  (with-temp-buffer-window
   oidx--short-help-buffer-name nil nil
   (setq oidx--short-help-displayed t)
   (princ (or prompt "Short help; shortcuts in []; capital letter acts like C-u.\n"))
   (princ (or choices (oidx--get-short-help-text))))
  (with-current-buffer oidx--short-help-buffer-name
    (let ((inhibit-read-only t))
      (setq mode-line-format nil)
      (setq cursor-type nil)
      (fit-window-to-buffer (get-buffer-window))
      (setq window-size-fixed 'height)
      (goto-char (point-min))
      (end-of-line))))


(defun oidx--get-short-help-text ()
  "Extract text for short help message from long help."
  (or oidx--short-help-text
      (with-temp-buffer
        (insert (documentation 'org-index))
        (goto-char (point-min))
        (search-forward (concat "  " (symbol-name (cl-first oidx--commands)) ": "))
        (forward-line 0)
        (kill-region (point-min) (point))
        (search-forward (concat "  " (symbol-name (car (last oidx--commands))) ": "))
        (forward-line 1)
        (kill-region (point) (point-max))
        (keep-lines "^  [-a-z]+:" (point-min) (point-max))
        (align-regexp (point-min) (point-max) "\\(\\s-*\\):")
        (goto-char (point-min))
        (while (re-search-forward "\\. *$" nil t)
          (replace-match "" nil nil))
        (goto-char (point-min))
        (re-search-forward "short-help")
        (end-of-line)
        (insert " (this text)")
        (delete-blank-lines)
        (goto-char (point-min))
        (unless (= (line-number-at-pos (point-max)) (1+ (length oidx--commands)))
          (error "Internal error, unable to properly extract one-line descriptions of subcommands"))
        (setq oidx--short-help-text (buffer-string)))))


(defun oidx--get-shortcut-chars ()
  "Collect shortcut chars from short help message."
  (or oidx--shortcut-chars
      (with-temp-buffer
        (insert (oidx--get-short-help-text))
        (goto-char (point-min))
        (while (< (point) (point-max))
          (when (looking-at "^  \\([-a-z]+\\)[ \t]+: +\\[\\([a-z?]\\)\\] ")
            (setq oidx--shortcut-chars
                  (cons (cons (match-string 2) (intern (match-string 1)))
                        oidx--shortcut-chars)))
          (forward-line 1))
        (unless (> (length oidx--shortcut-chars) 0)
          (error "Internal error, did not find shortcut chars"))
        oidx--shortcut-chars)))


(defun oidx--completing-read (prompt choices &optional default)
  "Completing read, that displays multiline PROMPT in a windows and then asks for CHOICES with DEFAULT."
  (interactive)
  (let ((bname "*org-index explanation for input prompt*")
        explain short-prompt lines result)
    (ignore-errors (quit-windows-on bname))
    (setq lines (split-string prompt "\n"))
    (setq short-prompt (car (last lines)))
    (setq explain (apply 'concat (mapcar (lambda (x) (concat x "\n")) (butlast lines))))
    (unless (string= explain "")
      (setq explain (substring explain 0 (- (length explain) 1))))
    (unwind-protect
        (progn
          (when (not (string= explain ""))
            (with-temp-buffer-window
             bname '((display-buffer-at-bottom)) nil
             (princ explain))
            
            (with-current-buffer bname
              (let ((inhibit-read-only t))
                (setq mode-line-format nil)
                (setq cursor-type nil)
                (fit-window-to-buffer (get-buffer-window))
                (setq window-size-fixed 'height)
                (add-text-properties (point-min) (point-at-eol) '(face org-level-3))
                (goto-char (point-min)))))
          (setq result (org-completing-read short-prompt choices nil t nil nil default)))
      (ignore-errors
        (quit-windows-on bname)
        (kill-buffer bname)))
    result))


(defun oidx--read-search-for-command-index ()
  "Special input routine for command index."

  ;; Accept single char commands or switch to reading a sequence of digits
  (let (char prompt search-ref search-id search-fingerprint)
    
    ;; start with short prompt but give more help on next iteration
    (setq prompt "Please specify, where to go in index (0-9,.,space,backspace,return or ? for short help) - ")
    
    ;; read one character
    (while (not (memq char (append (number-sequence ?0 ?9) (list ?\d ?\b ?\r ?\j ?\s ?.))))
      (setq char (read-char prompt))
      (setq prompt "Go to specific position in index table. Digits specify a reference number, <space> goes to top of index, <backspace> or <delete> to last line created and <return> or `.' to index line of current node.  Please choose - "))
    
    (if (memq char (number-sequence ?0 ?9))
        ;; read rest of digits
        (setq search-ref (read-from-minibuffer "Search reference number: " (char-to-string char))))
    ;; decode single chars
    (if (memq char '(?\r ?\n ?.)) (setq search-id (org-id-get)))
    (if (memq char '(?\d ?\b)) (setq search-fingerprint oidx--last-fingerprint))
    
    (list search-ref search-id search-fingerprint)))



;; Parse index and refs
(defun oidx--ref-from-id (id)
  "Get reference from line ID."
  (oidx--on 'id id (oidx--get-or-set-field 'ref)))


(defun oidx--id-from-ref (ref)
  "Get id from line REF."
  (oidx--on 'ref ref (oidx--get-or-set-field 'id)))


(defun oidx--get-fingerprint ()
  "Get fingerprint of current line."
  (replace-regexp-in-string
   "\\s " ""
   (mapconcat (lambda (x) (oidx--get-or-set-field x)) '(id ref yank keywords created) "")))


(defun oidx--verify-id ()
  "Check, that we have a valid id."

  (unless oidx--skip-verify-id
    ;; Check id
    (unless org-index-id
      (let ((answer (oidx--completing-read "Cannot find an index (org-index-id is not set). You may:\n  - read-help    : to learn more about org-index\n  - create-index : invoke an assistant to create an initial index\nPlease choose: " (list "read-help" "create-index") "read-help")))
        (if (string= answer "create-index")
            (oidx--create-missing-index "Variable org-index-id is not set, so probably no index table has been created yet.")
          (describe-function 'org-index)
          (throw 'new-index nil))))

    ;; Find node
    (let (marker)
      (setq marker (org-id-find org-index-id 'marker))
      (unless marker (oidx--create-missing-index "Cannot find the node with id \"%s\" (as specified by variable org-index-id)." org-index-id))
                                                  ; Try again with new node
      (setq marker (org-id-find org-index-id 'marker))
      (unless marker (error "Could not create node"))
      (setq oidx--buffer (marker-buffer marker)
            oidx--point (marker-position marker))
      (move-marker marker nil))))


(defun oidx--retrieve-context ()
  "Collect context information before starting with command."

  ;; Get the content of the active region or the word under cursor
  (setq oidx--active-region
        (if (and transient-mark-mode mark-active)
            (buffer-substring (region-beginning) (region-end))
          nil))
  (setq oidx--below-cursor (thing-at-point 'symbol))

  ;; get category of current node
  (setq oidx--category-before
        (save-excursion ; workaround: org-get-category does not give category when at end of buffer
          (beginning-of-line)
          (org-get-category (point) t)))

  ;; Find out, if we are within index table or occur buffer
  (setq oidx--within-index-node (string= (org-id-get) org-index-id))
  (setq oidx--within-occur (string= (buffer-name) oidx--occur-buffer-name)))


(defun oidx--parse-table (&optional num-lines-to-format check-sort-mixed)
  "Parse content of index table.
Optional argument NUM-LINES-TO-FORMAT limits formatting effort and duration.
Optional argument CHECK-SORT-MIXED triggers resorting if mixed and stale."

  (let (initial-point
        end-of-headings
        start-of-headings
        max-ref-field)

    (unless num-lines-to-format (setq num-lines-to-format 0))

    (with-current-buffer oidx--buffer

      (setq initial-point (point))

      (oidx--go-below-hline)
      (org-reveal)

      ;; if table is sorted mixed and it was sorted correctly yesterday, it could still be wrong today; so check
      (when (and check-sort-mixed (eq org-index-sort-by 'mixed))
        (goto-char oidx--below-hline)
        (let (count-first-line count-second-line)
          (setq count-first-line (string-to-number (concat (oidx--get-or-set-field 'count) " 0")))
          (forward-line)
          (setq count-second-line (string-to-number (concat (oidx--get-or-set-field 'count) " 0")))
          (forward-line -1)
          (if (and (string< (oidx--get-or-set-field 'last-accessed)
                            (oidx--get-mixed-time))
                   (< count-first-line count-second-line))
              (oidx--do-sort-index org-index-sort-by)))
        (oidx--go-below-hline))

      ;; align and fontify table once for this emacs session
      (when (> num-lines-to-format oidx--aligned)
        (oidx--go-below-hline)
        (message "Aligning and fontifying %s lines of index table (once per emacs session)..."
                 (if (= num-lines-to-format most-positive-fixnum) "all" (format "%d" num-lines-to-format)))
        (save-restriction
          (let (from to)
            (forward-line -3)
            (setq from (point))
            (setq to (org-table-end))
            (when (< num-lines-to-format most-positive-fixnum)
              (forward-line (+ 3 num-lines-to-format))
              (narrow-to-region from (point))
              (setq to (min (point) to)))
            (goto-char oidx--below-hline)
            (org-table-align)
            (setq to (min (point-max) to))
            (font-lock-fontify-region from to)))
        (setq oidx--aligned num-lines-to-format)
        (oidx--go-below-hline)
        (message "Done."))

      (beginning-of-line)
      
      ;; get headings to display during occur
      (setq end-of-headings (point))
      (goto-char (org-table-begin))
      (setq start-of-headings (point))
      (setq oidx--headings-visible (substring-no-properties (oidx--copy-visible start-of-headings end-of-headings)))
      (setq oidx--headings (buffer-substring start-of-headings end-of-headings))
      
      ;; count columns
      (org-table-goto-column 100)
      (setq oidx--numcols (- (org-table-current-column) 1))
      
      ;; go to top of table
      (goto-char (org-table-begin))
      
      ;; parse line of headings
      (oidx--parse-headings)

      ;; read property or go through table to find maximum number
      (goto-char oidx--below-hline)
      (setq max-ref-field (or (org-entry-get oidx--point "max-ref")
                              (oidx--migrate-maxref-to-property)))
      
      (unless oidx--head (oidx--get-decoration-from-ref-field max-ref-field))
      
      ;; Get ids of focused node (if any)
      (setq oidx--ids-focused-nodes (split-string (or (org-entry-get nil "ids-focused-nodes") "")))
      (org-entry-delete (point) "id-focused-node") ; migrate (kind of) from previous versions

      ;; save position below hline
      (oidx--go-below-hline)
      ;; go back to initial position
      (goto-char initial-point))))


(defun oidx--get-decoration-from-ref-field (ref-field)
  "Extract decoration from a REF-FIELD."
  (unless (string-match "^\\([^0-9]*\\)\\([0-9]+\\)\\([^0-9]*\\)$" ref-field)
    (oidx--report-index-error
     "Reference in index table ('%s') does not contain a number" ref-field))
  
  ;; These are the decorations used within the first ref of index
  (setq oidx--head (match-string 1 ref-field))
  (setq oidx--tail (match-string 3 ref-field))
  (setq oidx--ref-regex (concat (regexp-quote oidx--head)
                                "\\([0-9]+\\)"
                                (regexp-quote oidx--tail)))
  (setq oidx--ref-format (concat oidx--head "%d" oidx--tail)))


(defun oidx--extract-refnum (ref-field)
  "Extract the number from a complete reference REF-FIELD like 'R102'."
  (unless (string-match oidx--ref-regex ref-field)
    (oidx--report-index-error
     "Reference '%s' is not formatted properly (does not match '%s')" ref-field oidx--ref-regex))
  (string-to-number (match-string 1 ref-field)))


(defun oidx--parse-headings ()
  "Parse headings of index table."

  (let (field         ;; field content
        field-symbol) ;; and as a symbol

    (setq oidx--columns nil)

    ;; For each column
    (dotimes (col oidx--numcols)

      (setq field (substring-no-properties (downcase (org-trim (org-table-get-field (+ col 1))))))

      (if (string= field "")
          (error "Heading of column cannot be empty"))
      (if (and (not (string= (substring field 0 1) "."))
               (not (member (intern field) oidx--valid-headings)))
          (error "Column name '%s' is not a valid heading (custom headings may start with a dot, e.g. '.foo')" field))

      (setq field-symbol (intern field))

      ;; check if heading has already appeared
      (if (assoc field-symbol oidx--columns)
          (oidx--report-index-error
           "'%s' appears two times as column heading" (downcase field))
        ;; add it to list at front, reverse later
        (setq oidx--columns (cons (cons field-symbol (+ col 1)) oidx--columns)))))

  (setq oidx--columns (reverse oidx--columns))

  ;; check if all necessary headings have appeared
  (mapc (lambda (head)
          (unless (cdr (assoc head oidx--columns))
            (oidx--report-index-error "No column has heading '%s'" head)))
        oidx--valid-headings))


(defun oidx--refresh-parse-table ()
  "Fast refresh of selected results of parsing index table."

  (setq oidx--point (marker-position (org-id-find org-index-id 'marker)))
  (with-current-buffer oidx--buffer
    (save-excursion
      (oidx--go-below-hline))))


(defun oidx--verify-ids ()
  "Check, that ids really point to a node."
  
  (let ((marker t) id)
    
    (goto-char oidx--below-hline)
    
    (while (and marker (org-at-table-p))
      
      (when (setq id (oidx--get-or-set-field 'id))
        
        ;; check, if id is valid
        (setq marker (org-id-find id t)))

      (when marker (forward-line)))
    
    (if marker
        (progn
          (goto-char oidx--below-hline)
          "All ids of index are valid")
      (org-table-goto-column 1)
      "The id of this row cannot be found; please fix and check again for rest of index")))



;; Edit, add or kill lines
(defun oidx--do-edit ()
  "Perform command edit."
  (let ((maxlen 0) cols-vals buffer-keymap field-keymap keywords-pos val)

    (setq oidx--context-node nil)
    (setq oidx--context-occur nil)
    
    ;; change to index, if whithin occur
    (if oidx--within-occur
        (let ((pos (get-text-property (point) 'org-index-lbp)))
          (oidx--occur-test-stale pos)
          (setq oidx--context-occur (cons (point) (oidx--line-in-canonical-form)))
          (set-buffer oidx--buffer)
          (goto-char pos))
      
      ;; change to index, if still not within
      (if (not oidx--within-index-node)
          (let ((id (org-id-get)))
            (setq oidx--context-node (cons (current-buffer) (point)))
            (set-buffer oidx--buffer)
            (unless (and id (oidx--go 'id id))
              (setq oidx--context-node nil)
              (error "This node is not in index")))))
    
    ;; retrieve current content of index line
    (dolist (col (mapcar 'car (reverse oidx--columns)))
      (if (> (length (symbol-name col)) maxlen)
          (setq maxlen (length (symbol-name col))))
      (setq val (oidx--get-or-set-field col))
      (if (and val (eq col 'yank)) (setq val (replace-regexp-in-string (regexp-quote "\\vert") "|" val nil 'literal)))
      (setq cols-vals (cons (cons col val)
                            cols-vals)))

    ;; we need two different keymaps
    (setq buffer-keymap (make-sparse-keymap))
    (set-keymap-parent buffer-keymap widget-keymap)
    (define-key buffer-keymap (kbd "C-c C-c") 'oidx--edit-accept)
    (define-key buffer-keymap (kbd "C-c C-k") 'oidx--edit-abort)
    
    (setq field-keymap (make-sparse-keymap))
    (set-keymap-parent field-keymap widget-field-keymap)
    (define-key field-keymap (kbd "C-c C-c") 'oidx--edit-accept)
    (define-key field-keymap (kbd "C-c C-k") 'oidx--edit-abort)

    ;; prepare buffer
    (setq oidx--context-index (cons (point) (oidx--line-in-canonical-form)))
    (if (get-buffer oidx--edit-buffer-name) (kill-buffer oidx--edit-buffer-name))
    (switch-to-buffer (get-buffer-create oidx--edit-buffer-name))

    ;; create and fill widgets
    (setq oidx--edit-widgets nil)
    (widget-insert "Edit this line from index; type C-c C-c when done, C-c C-k to abort.\n\n")
    (dolist (col-val cols-vals)
      (if (eq (car col-val) 'keywords) (setq keywords-pos (point)))
      (setq oidx--edit-widgets (cons
                                (cons (car col-val)
                                      (widget-create 'editable-field
                                                     :format (format  (format "%%%ds: %%%%v" maxlen) (symbol-name (car col-val)))
                                                     :keymap field-keymap
                                                     (or (cdr col-val) "")))
                                oidx--edit-widgets)))

    (widget-setup)
    (goto-char keywords-pos)
    (beginning-of-line)
    (forward-char (+  maxlen 2))
    (use-local-map buffer-keymap)
    (setq oidx--inhibit-sort-idle t)
    "Editing a single line from index"))


(defun oidx--edit-accept ()
  "Function to accept editing in Edit buffer."
  (interactive)

  (let ((obuf (get-buffer oidx--occur-buffer-name))
        val line)
    
    ;; Time might have passed
    (oidx--refresh-parse-table)

    (with-current-buffer oidx--buffer
      
      ;; check, if buffer has become stale
      (save-excursion
        (goto-char (car oidx--context-index))
        (unless (string= (cdr oidx--context-index)
                         (oidx--line-in-canonical-form))
          (switch-to-buffer oidx--edit-buffer-name)
          (error "Index table has changed: Cannot find line, that this buffer is editing")))

      (pop-to-buffer-same-window oidx--buffer)
      (goto-char (car oidx--context-index))

      ;; write back line to index
      (dolist (col-widget oidx--edit-widgets)
        (setq val (widget-value (cdr col-widget)))
        (if (eq (car col-widget) 'yank) (setq val (replace-regexp-in-string "|" (regexp-quote "\\vert") val)))
        (oidx--get-or-set-field (car col-widget) val))

      (setq line (oidx--align-and-fontify-current-line))
      (beginning-of-line))

    ;; write line to occur if appropriate
    (if oidx--context-occur
        (if obuf
            (if (string= (cdr oidx--context-index)
                         (cdr oidx--context-occur))
                (progn
                  (pop-to-buffer-same-window obuf)
                  (goto-char (car oidx--context-occur))
                  (beginning-of-line)
                  (let ((inhibit-read-only t))
                    (delete-region (line-beginning-position) (line-end-position))
                    (insert line)
                    (put-text-property (line-beginning-position) (line-end-position)
                                       'org-index-lbp (car oidx--context-index))))
              (error "Occur buffer and index buffer do not match any longer"))
          (message "Occur buffer has gone, cannot switch back."))
      (setq oidx--context-occur nil))

    ;; return to node, if invoked from there
    (when oidx--context-node
      (pop-to-buffer-same-window (car oidx--context-node))
      (goto-char (cdr oidx--context-node)))

    ;; clean up
    (kill-buffer oidx--edit-buffer-name)
    (setq oidx--inhibit-sort-idle nil)
    (setq oidx--context-index nil)
    (setq oidx--edit-widgets nil)
    (beginning-of-line)
    (message "Index line has been edited.")))


(defun oidx--edit-abort ()
  "Function to abort editing in Edit buffer."
  (interactive)
  (kill-buffer oidx--edit-buffer-name)
  (setq oidx--context-index nil)
  (setq oidx--edit-widgets nil)
  (beginning-of-line)
  (message "Edit aborted."))


(defun oidx--do-new-line (&rest keys-values)
  "Do the work for `org-index-new-line'.
Optional argument KEYS-VALUES specifies content of new line."

  (oidx--retrieve-context)
  (with-current-buffer oidx--buffer
    (goto-char oidx--point)

    ;; check arguments early; they might come from userland
    (let ((kvs keys-values)
          k v)
      (while kvs
        (setq k (car kvs))
        (setq v (cadr kvs))
        (if (or (not (symbolp k))
                (and (symbolp v) (not (eq v t)) (not (eq v nil))))
            (error "Arguments must be alternation of key and value"))
        (unless (oidx--column-num k)
          (error "Unknown column or column not defined in table: '%s'" (symbol-name k)))
        (setq kvs (cddr kvs))))

    (let (yank)
      ;; create new line
      (oidx--create-new-line)

      ;; fill columns
      (let ((kvs keys-values)
            k v)
        (while kvs
          (setq k (car kvs))
          (setq v (cadr kvs))
          (org-table-goto-column (oidx--column-num k))
          (insert (org-trim (or v "")))
          (setq kvs (cddr kvs))))

      ;; align and fontify line
      (oidx--promote-current-line)
      (oidx--align-and-fontify-current-line)

      ;; remember fingerprint to be able to return
      (setq oidx--last-fingerprint (oidx--get-or-set-field 'fingerprint))
      
      ;; get column to yank
      (setq yank (oidx--get-or-set-field org-index-yank-after-add))

      yank)))


(defun oidx--create-new-line ()
  "Do the common work for `org-index-new-line' and `org-index'."

  ;; insert ref or id as last or first line, depending on sort-column
  (goto-char oidx--below-hline)
  (if (eq org-index-sort-by 'count)
      (progn
        (goto-char (org-table-end))
        (forward-line -1)
        (org-table-insert-row t))
    (org-table-insert-row))

  ;; insert some of the standard values
  (org-table-goto-column (oidx--column-num 'created))
  (org-insert-time-stamp nil nil t)
  (org-table-goto-column (oidx--column-num 'count))
  (insert "1"))


(defun oidx--collect-values-for-add-update (id &optional silent category)
  "Collect values for adding or updating line specified by ID, do not ask if SILENT, use CATEGORY, if given."
  
  (let ((args (list 'id id))
        content)
    
    (dolist (col (mapcar 'car oidx--columns))
      
      (setq content "")

      (cond
       ((eq col 'keywords)
        (if org-index-copy-heading-to-keywords
            (setq content (nth 4 (org-heading-components))))
        
        ;; Shift ref and timestamp ?
        (if org-index-strip-ref-and-date-from-heading
            (dotimes (_i 2)
              (if (or (string-match (concat "^\\s-*" oidx--ref-regex) content)
                      (string-match (concat "^\\s-*" org-ts-regexp-both) content))
                  (setq content (substring content (match-end 0)))))))
       
       ((eq col 'category)
        (setq content (or category oidx--category-before)))
       
       ((eq col 'level)
        (setq content (number-to-string (org-outline-level))))
       
       ((eq col 'tags)
        (setq content (org-get-tags-string))))
      
      (unless (string= content "")
        (setq args (plist-put args col content))))

    (if (not silent)
        (let ((args-edited (oidx--collect-values-from-user org-index-edit-on-add args)))
          (setq args (append args-edited args))))

    args))


(defun oidx--collect-values-for-add-update-remote (id)
  "Wrap `oidx--collect-values-for-add-update' by prior moving to remote node identified by ID."
  
  (let (marker point args)

    (setq marker (org-id-find id t))
    ;; enter buffer and collect information
    (with-current-buffer (marker-buffer marker)
      (setq point (point))
      (goto-char marker)
      (setq args (oidx--collect-values-for-add-update id t (org-get-category (point) t)))
      (goto-char point))

    args))


(defun oidx--collect-values-from-user (cols &optional defaults)
  "Collect values for adding a new line.
Argument COLS gives list of columns to edit.
Optional argument DEFAULTS gives default values."
  
  (let (content args)
    
    (dolist (col cols)
      
      (setq content "")

      (setq content (read-from-minibuffer
                     (format "Enter text for column '%s': " (symbol-name col))
                     (plist-get col defaults)))
      
      (unless (string= content "")
        (setq args (plist-put args col content))))
    args))


(defun oidx--write-fields (kvs)
  "Update current line with values from KVS (keys-values)."
  (while kvs
    (oidx--get-or-set-field (car kvs) (org-trim (cadr kvs)))
    (setq kvs (cddr kvs))))


(defun oidx--do-add-or-update (&optional create-ref tag-with-ref)
  "For current node or current line in index, add or update in index table.
CREATE-REF and TAG-WITH-REF if given."

  (let* (id id-from-index ref args yank ret)

    (oidx--save-positions)
    (unless (or oidx--within-index-node
                oidx--within-occur)
      (org-with-limited-levels (org-back-to-heading)))
    
    ;; try to do the same things from within index and from outside
    (if oidx--within-index-node

        (progn
          (unless (org-at-table-p)
            (error "Within index node but not on table"))

          (setq id (oidx--get-or-set-field 'id))
          (setq ref (oidx--get-or-set-field 'ref))
          (setq args (oidx--collect-values-for-add-update-remote id))
          (oidx--write-fields args)
          (setq yank (oidx--get-or-set-field org-index-yank-after-add))

          (setq ret
                (if ref
                    (cons (format "Updated index line %s" ref) yank)
                  (cons "Updated index line" nil))))

      (setq id (org-id-get-create))
      (oidx--refresh-parse-table)
      (setq id-from-index (oidx--on 'id id id))
      (setq ref (oidx--on 'id id (oidx--get-or-set-field 'ref)))

      (if tag-with-ref
          (org-toggle-tag (format "%s%d%s" oidx--head tag-with-ref oidx--tail) 'on))
      (setq args (oidx--collect-values-for-add-update id))

      (when (and create-ref
                 (not ref))
        (setq ref (oidx--get-save-maxref))
        (setq args (plist-put args 'ref ref)))

      
      (if id-from-index
          ;; already have an id in index, find it and update fields
          (progn

            (oidx--on
                'id id
              (oidx--write-fields args)
              (setq yank (oidx--get-or-set-field org-index-yank-after-add)))

            (setq ret
                  (if ref
                      (cons (format "Updated index line %s" ref) yank)
                    (cons "Updated index line" nil))))

        ;; no id here, create new line in index
        (if ref (setq args (plist-put args 'ref ref)))
        (setq yank (apply 'oidx--do-new-line args))

        (setq ret
              (if ref
                  (cons
                   (format "Added new index line %s" ref)
                   (concat yank " "))
                (cons
                 "Added new index line"
                 nil)))))
    
    (oidx--restore-positions)

    ret))


(defun oidx--do-kill ()
  "Perform command kill from within occur, index or node."

  (let (id ref chars-deleted-index text-deleted-from pos-in-index)

    (oidx--save-positions)
    (unless (or oidx--within-index-node
                oidx--within-occur)
      (org-with-limited-levels (org-back-to-heading)))
    
    ;; Collect information: What should be deleted ?
    (if (or oidx--within-occur
            oidx--within-index-node)

        (progn
          (if oidx--within-index-node
              ;; In index
              (setq pos-in-index (point))
            ;; In occur
            (setq pos-in-index (get-text-property (point) 'org-index-lbp))
            (oidx--occur-test-stale pos-in-index)
            (set-buffer oidx--buffer)
            (goto-char pos-in-index))
          ;; In Index (maybe moved there)
          (setq id (oidx--get-or-set-field 'id))
          (setq ref (oidx--get-or-set-field 'ref)))

      ;; At a headline
      (setq id (org-entry-get (point) "ID"))
      (setq ref (oidx--ref-from-id id))
      (setq pos-in-index (oidx--on 'id id (point)))
      (unless pos-in-index (error "This node is not in index")))

    ;; Remark: Current buffer is not certain here, but we have all the information to delete
    
    ;; Delete from node
    (when id
      (let ((m (org-id-find id 'marker)))
        (set-buffer (marker-buffer m))
        (goto-char m)
        (move-marker m nil)
        (unless (string= (org-id-get) id)
          (error "Could not find node with id %s" id)))

      (oidx--delete-any-ref-from-tags)
      (if ref (oidx--delete-ref-from-heading ref))
      (setq text-deleted-from (cons "node" text-deleted-from)))

    ;; Delete from index
    (set-buffer oidx--buffer)
    (unless pos-in-index "Internal error, pos-in-index should be defined here")
    (goto-char pos-in-index)
    (setq chars-deleted-index (length (delete-and-extract-region (line-beginning-position) (line-beginning-position 2))))
    (setq text-deleted-from (cons "index" text-deleted-from))
    
    ;; Delete from occur only if we started there, accept that it will be stale otherwise
    (if oidx--within-occur
        (let ((inhibit-read-only t))
          (set-buffer oidx--occur-buffer-name)
          (delete-region (line-beginning-position) (line-beginning-position 2))
          ;; correct positions
          (while (org-at-table-p)
            (put-text-property (line-beginning-position) (line-end-position) 'org-index-lbp
                               (- (get-text-property (point) 'org-index-lbp) chars-deleted-index))
            (forward-line))
          (setq text-deleted-from (cons "occur" text-deleted-from))))

    (oidx--restore-positions)
    (concat "Deleted from: " (mapconcat 'identity (sort text-deleted-from 'string<) ","))))



;; Sorting
(defun oidx--get-mixed-time ()
  "Get timestamp for sorting order mixed."
  (format-time-string
   (org-time-stamp-format t t)
   (apply 'encode-time (append '(0 0 0) (nthcdr 3 (decode-time))))))


(defun oidx--do-sort-index (sort)
  "Sort index table according to SORT."

  (let ((is-modified (buffer-modified-p))
        top
        bottom
        mixed-time)

    (unless buffer-read-only

      (message "Sorting index table for %s..." (symbol-name sort))
      (undo-boundary)

      (let ((message-log-max nil)) ; we have just issued a message, dont need those of sort-subr

        ;; if needed for mixed sort
        (if (eq sort 'mixed)
            (setq mixed-time (oidx--get-mixed-time)))

        ;; get boundaries of table
        (oidx--go-below-hline)
        (forward-line 0)
        (setq top (point))
        (goto-char (org-table-end))

        ;; kill all empty rows at bottom
        (while (progn
                 (forward-line -1)
                 (org-table-goto-column 1)
                 (and
                  (not (oidx--get-or-set-field 'ref))
                  (not (oidx--get-or-set-field 'id))
                  (not (oidx--get-or-set-field 'yank))))
          (org-table-kill-row))
        (forward-line 1)
        (setq bottom (point))
        
        ;; sort lines
        (save-restriction
          (narrow-to-region top bottom)
          (goto-char top)
          (sort-subr t
                     'forward-line
                     'end-of-line
                     (lambda ()
                       (oidx--get-sort-key sort t mixed-time))
                     nil
                     'string<)
          (goto-char (point-min))

          ;; restore modification state
          (set-buffer-modified-p is-modified)))

      (setq oidx--last-sort-assumed sort))))


(defun oidx--do-sort-lines (what)
  "Sort lines in WHAT according to contained reference."
  (save-restriction
    (cond
     ((eq what 'region)
      (if (region-active-p)
          (narrow-to-region (region-beginning) (region-end))
        (error "No active region, cannot sort")))
     ((eq what 'buffer)
      (unless (y-or-n-p "Sort whole current buffer ? ")
        (error "Canceled"))
      (narrow-to-region (point-min) (point-max))))

    (goto-char (point-min))
    (sort-subr nil 'forward-line 'end-of-line
               (lambda ()
                 (if (looking-at (concat ".*"
                                         (oidx--make-guarded-search oidx--ref-regex 'dont-quote)))
                     (string-to-number (match-string 1))
                   0)))))


(defun oidx--get-sort-key (&optional sort with-ref mixed-time)
  "Get value for sorting from column SORT, optional WITH-REF; if mixes use MIXED-TIME."
  (let (ref
        ref-field
        key)

    (unless sort (setq sort oidx--last-sort-assumed)) ; use default value

    (when (or with-ref
              (eq sort 'ref))
      ;; get reference with leading zeroes, so it can be
      ;; sorted as text
      (setq ref-field (oidx--get-or-set-field 'ref))
      (if ref-field
          (progn
            (string-match oidx--ref-regex ref-field)
            (setq ref (format
                       "%06d"
                       (string-to-number
                        (match-string 1 ref-field)))))
        (setq ref "000000")))

    (setq key
          (cond
           ((eq sort 'count)
            (format "%08d" (string-to-number (or (oidx--get-or-set-field 'count) ""))))
           ((eq sort 'mixed)
            (let ((last-accessed (oidx--get-or-set-field 'last-accessed)))
              (unless mixed-time (setq mixed-time (oidx--get-mixed-time)))
              (concat
               (if (string< mixed-time last-accessed) last-accessed mixed-time)
               (format "%08d" (string-to-number (or (oidx--get-or-set-field 'count) ""))))))
           ((eq sort 'ref)
            ref)
           ((memq sort '(id last-accessed created))
            (oidx--get-or-set-field sort))
           (t (error "This is a bug: unmatched case '%s'" sort))))

    (if with-ref (setq key (concat key ref)))

    key))




;; Reading, modifying and handling single index line
(defun org-index-get-line (column value)
  "Retrieve an existing line within the index table by ref or id.
Return its contents as a property list.

The function `plist-get' may be used to retrieve specific elements
from the result.

Example:

  (plist-get (org-index-get-line 'ref \"R12\") 'count)

retrieves the value of the count-column for reference number 12.

Argument COLUMN is a symbol, either ref or id,
argument VALUE specifies the value to search for."
  ;; check arguments
  (unless (memq column '(ref id keywords 'yank))
    (error "Argument column can only be 'ref', 'id', 'keywords' or 'yank'"))

  (unless value
    (error "Need a value to search for"))
  
  (oidx--verify-id)
  (oidx--parse-table)

  (oidx--get-line column value))


(defun oidx--get-line (column value)
  "Find a line by ID, return its contents.
Argument COLUMN and VALUE specify line to get."
  (let (content)
    (oidx--on
        column value
      (mapc (lambda (x)
              (if (and (numberp (cdr x))
                       (> (cdr x) 0))
                  (setq content (cons (car x) (cons (or (oidx--get-or-set-field (car x)) "") content)))))
            (reverse oidx--columns)))
    content))


(defun oidx--update-line (&optional id-or-pos no-error)
  "Update columns count and last-accessed in line ID-OR-POS.
Optional argument NO-ERROR suppresses error."

  (let (initial)

    (with-current-buffer oidx--buffer
      (unless buffer-read-only

        (setq initial (point))

        (if (if (integerp id-or-pos)
                (goto-char id-or-pos)
              (oidx--go 'id id-or-pos))
            (oidx--update-current-line)
          (unless no-error (error "Did not find reference or id '%s'" (list id-or-pos))))
        
        (goto-char initial)))))


(defun oidx--update-current-line ()
  "Update current lines columns count and last-accessed."
  (let (newcount (count-field (oidx--get-or-set-field 'count)))

    ;; update count field only if number or empty
    (when (or (not count-field)
              (string-match "^[0-9]+$" count-field))
      (setq newcount (+ 1 (string-to-number (or count-field "0"))))
      (oidx--get-or-set-field 'count
                              (number-to-string newcount)))

    ;; update timestamp
    (org-table-goto-column (oidx--column-num 'last-accessed))
    (org-table-blank-field)
    (org-insert-time-stamp nil t t)

    ;; move line according to new content
    (oidx--promote-current-line)
    (oidx--align-and-fontify-current-line)))


(defun oidx--align-and-fontify-current-line (&optional num)
  "Make current line (or NUM lines) blend well among others."
  (let (lines lines-fontified)
    ;; get current content
    (unless num (setq num 1))
    (setq lines (delete-and-extract-region (line-beginning-position) (line-end-position num)))
    ;; create minimum table with fixed-width columns to align and fontify new line
    (insert
     (setq
      lines-fontified
      (with-temp-buffer
        (org-set-font-lock-defaults)
        (insert oidx--headings-visible)
        ;; fill columns, so that aligning cannot shrink them
        (goto-char (point-min))
        (search-forward "|")
        (while (search-forward " " (line-end-position) t)
          (replace-match "." nil t))
        (goto-char (point-min))
        (while (search-forward ".|." (line-end-position) t)
          (replace-match " | " nil t))
        (goto-char (point-min))
        (while (search-forward "|." (line-end-position) t)
          (replace-match "| " nil t))
        (goto-char (point-max))
        (insert lines)
        (forward-line 0)
        (let ((start (point)))
          (while (re-search-forward "^\s +|-" nil t)
            (replace-match "| -"))
          (goto-char start))
        (org-mode)
        (org-table-align)
        (font-lock-fontify-region (point-min) (point-max))
        (goto-char (point-max))
        (if (eq -1 (skip-chars-backward "\n"))
            (delete-char 1))
        (forward-line (- 1 num))
        (buffer-substring (line-beginning-position) (line-end-position num)))))
    lines-fontified))


(defun oidx--promote-current-line ()
  "Move current line up in table according to changed sort fields."
  (let (begin end key
              (to-skip 0))

    (forward-line 0) ; stay at beginning of line

    (setq key (oidx--get-sort-key))
    (setq begin (point))
    (setq end (line-beginning-position 2))

    (forward-line -1)
    (while (and (org-at-table-p)
                (not (org-at-table-hline-p))
                (string< (oidx--get-sort-key) key))

      (cl-incf to-skip)
      (forward-line -1))
    (forward-line 1)

    ;; insert line at new position
    (when (> to-skip 0)
      (insert (delete-and-extract-region begin end))
      (forward-line -1))))


(defun oidx--get-or-set-field (key &optional value)
  "Retrieve field KEY from index table or set it to VALUE."
  (let (field)
    (save-excursion
      (if (eq key 'fingerprint)
          (progn
            (if value (error "Internal error, pseudo-column fingerprint cannot be set"))
            (setq field (oidx--get-fingerprint)))
        (setq field (org-trim (org-table-get-field (cdr (assoc key oidx--columns)) value))))
      (if (string= field "") (setq field nil))

      (org-no-properties field))))


(defun oidx--column-num (key)
  "Return number of column KEY."
  (if (numberp key)
      key
    (cdr (assoc key oidx--columns))))



;; Navigation
(defun oidx--go-below-hline ()
  "Move below hline in index-table."

  (let ((errstring (format "index table within node %s" org-index-id)))

    (goto-char oidx--point)

    ;; go to heading of node
    (while (not (org-at-heading-p)) (forward-line -1))
    (forward-line 1)

    ;; go to first table, but make sure we do not get into another node
    (while (and (not (org-at-table-p))
                (not (org-at-heading-p))
                (not (eobp)))
      (forward-line))

    ;; check, if there really is a table
    (unless (org-at-table-p)
      (oidx--create-missing-index "Cannot find %s." errstring))

    ;; go just after hline
    (while (and (not (org-at-table-hline-p))
                (org-at-table-p))
      (forward-line))
    (forward-line)

    ;; and check
    (unless (org-at-table-p)
      (oidx--report-index-error "Cannot find a hline within %s" errstring))

    (org-table-goto-column 1)
    (setq oidx--below-hline (point))))


(defun oidx--unfold-buffer ()
  "Helper function to unfold buffer."
  (org-show-context 'tree)
  (org-reveal '(4))
  (recenter 1))


(defun oidx--make-guarded-search (ref &optional dont-quote)
  "Make robust search string from REF; DONT-QUOTE it, if requested."
  (concat "\\_<" (if dont-quote ref (regexp-quote ref)) "\\_>"))


(defun oidx--save-positions ()
  "Save current buffer and positions in index- and current buffer; not in occur-buffer."

  (let (cur-buf cur-mrk idx-pnt idx-mrk)
    (setq cur-buf (current-buffer))
    (setq cur-mrk (point-marker))
    (set-buffer oidx--buffer)
    (if (string= (org-id-get) org-index-id)
        (setq idx-pnt (point))
      (setq idx-mrk (point-marker)))
    (set-buffer cur-buf)
    (setq oidx--saved-positions (list cur-buf cur-mrk idx-pnt idx-mrk))))


(defun oidx--restore-positions ()
  "Restore positions as saved by `oidx--save-positions'."

  (cl-multiple-value-bind
      (cur-buf cur-mrk idx-pnt idx-mrk buf)
      oidx--saved-positions
    (setq buf (current-buffer))
    (set-buffer cur-buf)
    (goto-char cur-mrk)
    (set-buffer oidx--buffer)
    (goto-char (or idx-pnt idx-mrk))
    (set-buffer buf))
  (setq oidx--saved-positions nil))


(defun oidx--go (column value)
  "Position cursor on index line where COLUMN equals VALUE.
Return t or nil, leave point on line or at top of table, needs to be in buffer initially."
  (let (found)

    (unless (eq (current-buffer) oidx--buffer)
      (error "This is a bug: Not in index buffer"))

    (unless value
      (error "Cannot search for nil"))
    
    (if (string= value "")
        (error "Cannot search for empty string"))

    (if (<= (length value) 2)
        (warn "Searching for short string '%s' will be slow" value))

    (goto-char oidx--below-hline)
    (forward-line 0)
    (save-restriction
      (narrow-to-region (point) (org-table-end))
      (while (and (not found)
                  (search-forward value nil t))
        (setq found (string= value (oidx--get-or-set-field column)))))
    
    ;; return value
    (if found
        t
      (goto-char oidx--below-hline)
      nil)))


(defun oidx--find-id (id &optional other)
  "Perform command head: Find node with ID and present it.
If OTHER in separate window."
  
  (let (message marker)

    (setq marker (org-id-find id t))

    (if marker
        (progn
          (oidx--update-line id)
          (if other
              (progn
                (pop-to-buffer (marker-buffer marker)))
            (pop-to-buffer-same-window (marker-buffer marker)))
          
          (goto-char marker)
          (org-reveal t)
          (org-show-entry)
          (recenter)
          (unless (string= (org-id-get) id)
            (setq message (format "Could not go to node with id %s (narrowed ?)" id)))
          (setq message "Found headline"))
      (setq message (format "Did not find node with %s" id)))
    message))



;; Some helper functions
(defun oidx--get-save-maxref (&optional no-inc)
  "Get next reference, increment number and store it in index.
Optional argument NO-INC skips automatic increment on maxref."
  (let (ref-field)
    (with-current-buffer oidx--buffer
      (setq ref-field (org-entry-get oidx--point "max-ref"))
      (unless no-inc
        (setq ref-field (format oidx--ref-format (1+ (oidx--extract-refnum ref-field))))
        (org-entry-put oidx--point "max-ref" ref-field)))
    ref-field))


(defun oidx--line-in-canonical-form ()
  "Return current line in its canonical form."
  (org-trim (substring-no-properties (replace-regexp-in-string "\s +" " " (buffer-substring (line-beginning-position) (line-beginning-position 2))))))


(defun oidx--wrap (text)
  "Wrap TEXT at fill column."
  (with-temp-buffer
    (insert text)
    (fill-region (point-min) (point-max) nil t)
    (buffer-string)))



;; Index maintainance
(defun oidx--do-maintain ()
  "Choose among and perform some tasks to maintain index."
  (let (message-text choices choices-short check-what text)
    
    (setq choices (list "statistics : compute statistics about index table\n"
                        "verify     : verify ids by visiting their nodes\n"
                        "duplicates : check index for duplicate refs or ids\n"
                        "max        : compute and check maximum ref\n"
                        "clean      : remove obsolete property org-index-id\n"
                        "update     : update content of index lines having an id\n"))

    (setq choices-short (mapcar (lambda (x) (car (split-string x))) choices))
    (setq text (concat "These checks and fixes are available:\n" (apply 'concat choices) "Please choose: "))
    (setq check-what (intern (oidx--completing-read text choices-short (car choices-short))))

    (message nil)
    
    (cond
     ((eq check-what 'verify)
      (setq message-text (oidx--verify-ids)))

     ((eq check-what 'statistics)
      (setq message-text (oidx--do-statistics)))

     ((eq check-what 'duplicates)
      (setq message-text (oidx--find-duplicates)))

     ((eq check-what 'clean)
      (let ((lines 0))
        (org-map-entries
         (lambda ()
           (when (org-entry-get (point) "org-index-ref")
             (cl-incf lines)
             (org-entry-delete (point) "org-index-ref")))
         nil 'agenda)
        (setq message-text (format "Removed property 'org-index-ref' from %d lines" lines))))
     
     ((eq check-what 'update)
      (if (y-or-n-p "Updating your index will overwrite certain columns with content from the associated heading and category.  If unsure, you may try this for a single, already existing line of your index by invoking `add'.  Are you SURE to proceed for ALL INDEX LINES ? ")
          (setq message-text (oidx--update-all-lines))
        (setq message-text "Canceled")))

     ((eq check-what 'max)
      (setq message-text (oidx--check-maximum))))
    message-text))


(defun oidx--find-duplicates ()
  "Find duplicate references or ids in index table."
  (let (ref-duplicates id-duplicates)

    (setq ref-duplicates (oidx--find-duplicates-helper 'ref))
    (setq id-duplicates (oidx--find-duplicates-helper 'id))
    (goto-char oidx--below-hline)
    (if (or ref-duplicates id-duplicates)
        (progn
          (pop-to-buffer-same-window
           (get-buffer-create "*org-index-duplicates*"))
          (erase-buffer)
          (insert "\n")
          (if ref-duplicates
              (progn
                (insert " These references appear more than once:\n")
                (mapc (lambda (x) (insert "   " x "\n")) ref-duplicates)
                (insert "\n\n"))
            (insert " No references appear more than once.\n"))
          (if id-duplicates
              (progn
                (insert " These ids appear more than once:\n")
                (mapc (lambda (x) (insert "   " x "\n")) id-duplicates))
            (insert " No ids appear more than once."))
          (insert "\n")

          "Some references or ids are duplicate")
      "No duplicate references or ids found")))


(defun oidx--find-duplicates-helper (column)
  "Helper for `oidx--find-duplicates': Go through table and count given COLUMN."
  (let (counts duplicates field found)

    ;; go through table
    (goto-char oidx--below-hline)
    (while (org-at-table-p)

      ;; get column
      (setq field (oidx--get-or-set-field column))

      ;; and increment
      (setq found (assoc field counts))
      (if found
          (cl-incf (cdr found))
        (setq counts (cons (cons field 1) counts)))

      (forward-line))

    (mapc (lambda (x) (if (and (> (cdr x) 1)
                               (car x))
                          (setq duplicates (cons (car x) duplicates)))) counts)
    
    duplicates))


(defun oidx--check-maximum ()
  "Check maximum reference."
  (let (ref-field ref-num (max 0) (max-prop))

    (goto-char oidx--below-hline)
    (setq max-prop (oidx--extract-refnum (org-entry-get oidx--point "max-ref")))

    (while (org-at-table-p)

      (setq ref-field (oidx--get-or-set-field 'ref))
      (setq ref-num (if ref-field (oidx--extract-refnum ref-field) 0))

      (if (> ref-num max) (setq max ref-num))

      (forward-line))

    (goto-char oidx--below-hline)
    
    (cond ((< max-prop max)
           (format "Maximum ref from property max-ref (%d) is smaller than maximum ref from table (%d); you should correct this" max-prop max))
          ((> max-prop max)
           (format  "Maximum ref from property max-ref (%d) is larger than maximum ref from table (%d); you may correct this" max-prop max))
          (t (format "Maximum ref from property max-ref and maximum ref from table are equal (%d); as expected" max-prop)))))


(defun oidx--do-statistics ()
  "Compute statistics about index table."
  (let ((total-lines 0) (total-refs 0)
        ref ref-field min max message)

    ;; go through table
    (goto-char oidx--below-hline)
    (while (org-at-table-p)

      ;; get ref
      (setq ref-field (oidx--get-or-set-field 'ref))

      (when ref-field
        (string-match oidx--ref-regex ref-field)
        (setq ref (string-to-number (match-string 1 ref-field)))

        ;; record min and max
        (if (or (not min) (< ref min)) (setq min ref))
        (if (or (not max) (> ref max)) (setq max ref))

        (setq total-refs (1+ total-refs)))

      ;; count
      (setq total-lines (1+ total-lines))

      (forward-line))

    (setq message (format "%d Lines in index table. First reference is %s, last %s; %d of them are used (%d percent)"
                          total-lines
                          (format oidx--ref-format min)
                          (format oidx--ref-format max)
                          total-refs
                          (truncate (* 100 (/ (float total-refs) (1+ (- max min)))))))

    (goto-char oidx--below-hline)
    message))


(defun oidx--migrate-maxref-to-property ()
  "One-time migration: No property; need to go through whole table once to find max."
  (oidx--go-below-hline)
  (let ((max-ref-num 0)
        ref-field ref-num)
    (message "One-time migration to set index-property maxref...")
    (while (org-at-table-p)
      (setq ref-field (oidx--get-or-set-field 'ref))
      (when ref-field
        (unless oidx--head (oidx--get-decoration-from-ref-field ref-field))
        (setq ref-num (oidx--extract-refnum ref-field))
        (if (> ref-num max-ref-num) (setq max-ref-num ref-num)))
      (forward-line))
    (unless (> max-ref-num 0)
      (oidx--report-index-error "No reference found in property max-ref and none in index"))
    (setq ref-field (format oidx--ref-format max-ref-num))
    (oidx--go-below-hline)
    (org-entry-put oidx--point "max-ref" ref-field)
    (message "Done.")
    ref-field))


(defun oidx--sort-silent ()
  "Sort index for default column to remove any effects of temporary sorting."
  (unless oidx--inhibit-sort-idle
    (save-excursion
      (oidx--verify-id)
      (oidx--parse-table)
      (with-current-buffer oidx--buffer
        (save-excursion
          (goto-char oidx--below-hline)
          (oidx--do-sort-index org-index-sort-by)
          (remove-hook 'before-save-hook 'oidx--sort-silent))))))


(defun oidx--idle-prepare ()
  "For parsing table when idle."
  (oidx--verify-id)
  (oidx--parse-table most-positive-fixnum t))


(defun oidx--update-all-lines ()
  "Update all lines of index at once."

  (let ((lines 0)
        id kvs)
    
    (goto-char oidx--below-hline)
    (while (org-at-table-p)
      
      ;; update single line
      (when (setq id (oidx--get-or-set-field 'id))
	(setq kvs (oidx--collect-values-for-add-update-remote id))
	(oidx--write-fields kvs)
	(cl-incf lines))
      (forward-line))

    (goto-char oidx--below-hline)
    (org-table-align)
    (format "Updated %d lines" lines)))


(defun oidx--delete-ref-from-heading (ref)
  "Delete given REF from current heading."
  (save-excursion
    (end-of-line)
    (let ((end (point)))
      (beginning-of-line)
      (when (search-forward ref end t)
        (delete-char (- (length ref)))
        (just-one-space)))))


(defun oidx--delete-any-ref-from-tags ()
  "Delete any reference from list of tags."
  (let (new-tags)
    (mapc (lambda (tag)
            (unless (or (string-match oidx--ref-regex tag)
			(string= tag ""))
              (setq new-tags (cons tag new-tags))))
          (org-get-tags))
    (org-set-tags-to new-tags)))



;; Creating a new Index
(defun oidx--create-missing-index (&rest reasons)
  "Create a new empty index table with detailed explanation.  Argument REASONS explains why."

  (oidx--ask-before-create-index "Cannot find index table: "
                                 "new permanent" "."
                                 reasons)
  (oidx--create-index))


(defun oidx--report-index-error (&rest reasons)
  "Report an error (explained by REASONS) with the existing index and offer to create a valid one to compare with."

  (when oidx--buffer
    (pop-to-buffer-same-window oidx--buffer)
    (goto-char oidx--below-hline)
    (org-reveal t))
  (oidx--ask-before-create-index "The existing index contains this error: "
                                 "temporary" ", to compare with."
                                 reasons)
  (oidx--create-index t t))


(defun oidx--ask-before-create-index (explanation type for-what reasons)
                                                  ; checkdoc-params: (explanation type for-what reasons)
  "Ask the user before creating an index or throw error.  Arguments specify bits of issued message."
  (let (reason prompt)

    (setq reason (apply 'format reasons))

    (setq prompt (concat explanation reason "\n"
                         "However, this assistant can help you to create a "
                         type " index with detailed comments" for-what "\n\n"
                         "Do you want to proceed ?"))

    (unless (let ((max-mini-window-height 1.0))
              (y-or-n-p prompt))
      (error (concat explanation reason)))))


(defun oidx--create-index (&optional temporary compare)
  "Create a new empty index table with detailed explanation.
specify flag TEMPORARY for th new table temporary, maybe COMPARE it with existing index."
  (let (buffer
        title
        firstref
        id)

    (if temporary
        (let ((file-name (concat temporary-file-directory "oidx--example-index.org"))
              (buffer-name "*org-index-example-index*"))
          (setq buffer (get-buffer-create buffer-name))
          (with-current-buffer buffer
            ;; but it needs a file for its index to be found
            (unless (string= (buffer-file-name) file-name)
              (set-visited-file-name file-name))
            (rename-buffer buffer-name) ; name is change by line above

            (erase-buffer)
            (org-mode)))

      (setq buffer (get-buffer (oidx--completing-read "Please choose the buffer, where the new node for the index table should be created; the new node will be inserted at its end.\n\nBuffer: " (mapcar 'buffer-name (org-buffer-list))))))

    (setq title (read-from-minibuffer "Please enter the title of the index node (leave empty for default 'index'): "))
    (if (string= title "") (setq title "index"))
    
    (while (progn
             (setq firstref (read-from-minibuffer "Please enter your first reference-number. This is an integer number preceeded by some and optionally followed by some non-numeric chars; e.g. 'R1', '-1-' or '#1#' (and your initial number does not need to be '1'). The format of your reference-numbers only needs to make sense for yourself, so that you can spot it easily in your texts or write it on a piece of paper; it should however not already appear frequently within your existing notes, to avoid too many false hits when searching.\n\nPlease choose (leave empty for default 'R1'): "))
             (if (string= firstref "") (setq firstref "R1"))
             (let (desc)
               (when (string-match "[[:blank:]]" firstref)
                 (setq desc "Contains whitespace"))
               (when (string-match "[[:cntrl:]]" firstref)
                 (setq desc "Contains control characters"))
               (unless (string-match "^[^0-9]+[0-9]+[^0-9]*$" firstref)
                 ;; firstref not okay, report details
                 (setq desc
                       (cond ((string= firstref "") "is empty")
                             ((not (string-match "^[^0-9]+" firstref)) "starts with a digit")
                             ((not (string-match "^[^0-9]+[0-9]+" firstref)) "does not contain a number")
                             ((not (string-match "^[^0-9]+[0-9]+[^0-9]*$" firstref)) "contains more than one sequence of digits")

                             )))
               (if desc
                   (progn
                     (read-from-minibuffer (format "Your input '%s' does not meet the requirements because it %s.\nPlease hit RET and try again: " firstref desc))
                     t)
                 nil))))

    (with-current-buffer buffer
      (goto-char (point-max))
      (insert (format "* %s %s\n" firstref title))
      (org-entry-put oidx--point "max-ref" firstref)
      (if temporary
          (insert "
  Below you find your temporary index table, which WILL NOT LAST LONGER
  THAN YOUR CURRENT EMACS SESSION; please use it only for evaluation.
")
        (insert "
  Below you find your initial index table, which will grow over time.
"))
      (insert "  You may start using it by adding some lines. Just
  move to another heading within org, invoke `org-index' and
  choose the command 'add'.  After adding a few nodes, try the
  command 'occur' to search among them.

  To gain further insight you may invoke the subcommand 'help', or
  (with the same content) read the help of `org-index'.

  Invoke `org-customize' to tweak the behaviour of org-index,
  see the group org-index. It might be useful to set the global
  key `org-index-key'.

  This node needs not be a top level node; its name is completely
  at your choice; it is found through its ID only.
")
      (unless temporary
        (insert "
  Remark: These lines of explanation can be removed at any time.
"))

      (setq id (org-id-get-create))
      (insert (format "

  | ref | category | keywords | tags | count | level | last-accessed | created | id  | yank |
  |     |          |          |      |       |       |               |         | <4> | <4>  |
  |-----+----------+----------+------+-------+-------+---------------+---------+-----+------|
  | %s  |          | %s       |      |       |       |               | %s      | %s  |      |

"
                      firstref
                      title
                      (with-temp-buffer (org-insert-time-stamp nil nil t))
                      id))

      ;; make sure, that node can be found
      (org-id-add-location id (buffer-file-name))
      (setq buffer-save-without-query t)
      (basic-save-buffer)

      (while (not (org-at-table-p)) (forward-line -1))
      (unless buffer-read-only (org-table-align))
      (while (not (org-at-heading-p)) (forward-line -1))

      ;; read back some info about new index
      (let ((org-index-id id))
	(oidx--verify-id))

      ;; remember at least for this session
      (setq org-index-id id)

      ;; present results to user
      (if temporary
          (progn
            ;; Present existing and temporary index together
            (when compare
              (pop-to-buffer-same-window oidx--buffer)
              (goto-char oidx--point)
              (oidx--unfold-buffer)
              (delete-other-windows)
              (select-window (split-window-vertically)))
            ;; show new index
            (pop-to-buffer-same-window buffer)
            (org-id-goto id)
            (oidx--unfold-buffer)
            (if compare
                (progn
                  (message "Please compare your existing index (upper window) and a temporary new one (lower window) to fix your index")
                  (throw 'new-index nil))
              (message "This is your new temporary index, use command add to populate, occur to search.")))
        (progn
          ;; Show the new index
          (pop-to-buffer-same-window buffer)
          (delete-other-windows)
          (org-id-goto id)
          (oidx--unfold-buffer)
          (if (y-or-n-p "This is your new index table.  It is already set for this Emacs session, so you may try it out.  Do you want to save it's id to make it available for future Emacs sessions too ? ")
              (progn
                (customize-save-variable 'org-index-id id)
                (message "Saved org-index-id '%s' to %s." id (or custom-file user-init-file)))
            (let (sq)
              (setq sq (format "(setq org-index-id \"%s\")" id))
              (kill-new sq)
              (message "Did not make the id of this new index permanent; you may want to put\n\n   %s\n\ninto your own initialization; it is copied already, just yank it." sq)))

          (when (and (not org-index-key)
		     (y-or-n-p "The central function `org-index' can be bound to a global key.  Do you want to make such a binding for now ? "))
	    (let ((prompt (concat "Please type your desired key sequence. For example, with the user-prefix key C-c, these keys are available: " (mapconcat 'char-to-string (remove nil (mapcar (lambda (c) (if (key-binding (kbd (format "C-c %c" c))) nil c)) (number-sequence ?a ?z))) ",") ". But of course, you may choose any free key-sequence you like (C-g to cancel): "))
		  (preprompt "")
		  key)
	      (while (progn
		       (setq key (read-key-sequence (concat preprompt prompt)))
		       (setq preprompt (format "Key '%s' is already taken; please choose another one. " (kbd key)))
		       (and (key-binding key)
			    (not (string= (kbd key) (kbd "^g"))))))
	      (unless (string= (kbd key) (kbd "^g"))
		(global-set-key key 'org-index)
		(let ((saved ""))
		  (when (y-or-n-p "Do you want to save this for future Emacs sessions ? ")
		    (customize-save-variable 'org-index-key key)
		    (setq saved "and saved "))
		  (message "Set %sorg-index-key '%s' to %s." saved (kbd key) (or custom-file user-init-file)))))
	    (message "Did not set org-index-key; however this can be done any time with `org-customize'."))
          (throw 'new-index nil))))))



;; Functions for focus-feature
(defun oidx--goto-focus ()
  "Goto focus node, one after the other."
  (if oidx--ids-focused-nodes
      (let (again last-id following-id in-last-id target-id explain marker heading-is-clause head
                  (bottom-clause (if org-index-goto-bottom-after-focus "bottom of " ""))
                  (menu-clause ""))
        (setq again (and (eq this-command last-command)
                         (eq oidx--this-command oidx--last-command)))
        (setq last-id (or oidx--id-last-goto-focus
                          (car (last oidx--ids-focused-nodes))))
        (setq following-id (car (or (cdr-safe (member last-id
                                                      (append oidx--ids-focused-nodes
                                                              oidx--ids-focused-nodes)))
                                    oidx--ids-focused-nodes)))
        (setq in-last-id (string= (ignore-errors (org-id-get)) last-id))

        (setq target-id (if (or again in-last-id) following-id last-id))

        ;; bail out on inactivity
        (if oidx--focus-cancel-timer (cancel-timer oidx--focus-cancel-timer))
        (setq oidx--focus-cancel-timer
              (run-at-time 8 nil
                           (lambda () (if oidx--cancel-focus-wait-function
                                          (funcall oidx--cancel-focus-wait-function)))))
        
        (setq oidx--cancel-focus-wait-function
              (set-transient-map (let ((map (make-sparse-keymap)))
                                   (define-key map (vector ?f)
                                     (lambda () (interactive)
                                       (setq this-command last-command)
                                       (setq oidx--this-command oidx--last-command)
                                       (oidx--focus-message (oidx--goto-focus))))
                                   (define-key map (vector ?h)
                                     (lambda () (interactive)
                                       (org-with-limited-levels (org-back-to-heading))
                                       (recenter 1)
                                       (oidx--focus-message "On heading of focused node")))
                                   (define-key map (vector ?b)
                                     (lambda () (interactive)
                                       (oidx--end-of-focused-node)
                                       (recenter -1)
                                       (oidx--focus-message "At bottom of focused node")))
                                   (define-key map (vector ??)
                                     (lambda () (interactive)
                                       (setq oidx--short-help-wanted t)
                                       (message (oidx--goto-focus))
                                       (setq oidx--short-help-wanted nil)))
                                   (define-key map (vector ?d)
                                     (lambda () (interactive)
                                       (setq this-command last-command)
                                       (oidx--delete-from-focus)
                                       (oidx--persist-focused-nodes)
                                       (oidx--focus-message (concat  "Current node has been removed from list of focused nodes (undo available), " (oidx--goto-focus)))
                                       (setq oidx--cancel-focus-wait-function nil)))
                                   map)
                                 t
				 ;; this is run (in any case) on leaving the map
                                 (lambda () (cancel-timer oidx--focus-cancel-timer)
                                   ;; Clean up overlay
                                   (if oidx--focus-overlay (delete-overlay oidx--focus-overlay))
                                   (setq oidx--focus-overlay nil)
                                   (if org-index-clock-into-focus
                                       (let (keys)
                                         ;; save and repeat terminating key, because org-clock-in might read interactively
                                         (if (input-pending-p) (setq keys (read-key-sequence nil)))
                                         (org-with-limited-levels (org-clock-in))
                                         (if keys (setq unread-command-events (listify-key-sequence keys)))))
				   ;; ignore-errors saves during tear-down of some tests
                                   (ignore-errors (oidx--update-line (org-id-get) t)))))
        (setq menu-clause (if oidx--short-help-wanted "; type 'f' to jump to next node in list; 'h' for heading, 'b' for bottom of node; type 'd' to delete this node from list" "; type f,h,b,d or ? for short help"))

        (if (member target-id (oidx--ids-up-to-top))
            (setq explain (format "staying below %scurrent" bottom-clause))
          (unless (setq marker (org-id-find target-id 'marker))
            (setq oidx--id-last-goto-focus nil)
            (error "Could not find focus-node with id %s" target-id))
          
          (pop-to-buffer-same-window (marker-buffer marker))
          (goto-char (marker-position marker))
          (oidx--unfold-buffer)
          (move-marker marker nil)
          (when org-index-goto-bottom-after-focus
            (oidx--end-of-focused-node)
            (org-reveal)
            (recenter -2)))

        (setq head (org-with-limited-levels (org-get-heading t t t t)))
        (when org-index-show-focus-overlay
          ;; tooltip-overlay to show current heading
          (if oidx--focus-overlay (delete-overlay oidx--focus-overlay))
          (setq oidx--focus-overlay (make-overlay (point-at-bol) (point-at-bol)))
          (overlay-put oidx--focus-overlay
                       'after-string
                       (propertize
                        (format " %s (%d of %d) "
                                head
                                (1+ (- (length oidx--ids-focused-nodes)
                                       (length (member target-id oidx--ids-focused-nodes))))
                                (length oidx--ids-focused-nodes))
                        'face 'highlight))
          (overlay-put oidx--focus-overlay 'priority most-positive-fixnum))

        (setq heading-is-clause (format "Focus %s, " (propertize head 'face 'org-todo)))
        
        (setq explain (or explain
                          (if (or again in-last-id)
                              (format "at %snext" bottom-clause)
                            (format "back to %scurrent" bottom-clause))))
        
        (setq oidx--id-last-goto-focus target-id)
        (concat
         heading-is-clause
         (if (cdr oidx--ids-focused-nodes)
             (format "%s node (out of %d)"
                     explain
                     (length oidx--ids-focused-nodes))
           (format "%s single node" explain))
         menu-clause))
    "No nodes in focus, use set-focus"))


(defun oidx--focus-message (message)
  "Issue given MESSAGE and append string '(again)' if appropriate."
  (let ((again (if (string= message oidx--last-focus-message) " (again)" "")))
    (setq oidx--last-focus-message message)
    (message (concat message again "."))))


(defun oidx--end-of-focused-node ()
  "Goto end of focused nodes, ignoring inline-tasks but stopping at first child."
  (let (level (pos (point)))
    (when (ignore-errors (org-with-limited-levels (org-back-to-heading)))
      (setq level (outline-level))
      (forward-char 1)
      (if (and (org-with-limited-levels (re-search-forward org-outline-regexp-bol nil t))
               (> (outline-level) level))
          (progn        ; landed on child node
            (goto-char (match-beginning 0))
            (forward-line -1))
        (goto-char pos) ; landed on next sibling or end of buffer
        (org-with-limited-levels
         (org-end-of-subtree nil t)
         (when (org-at-heading-p)
           (forward-line -1))))
      (beginning-of-line))))


(defun oidx--more-focus-commands ()
  "More commands for handling focused nodes."
  (let (id text more-text char prompt ids-up-to-top)

    (setq prompt (format "Please specify action on list of %d focused nodes (s,a,d,r or ? for short help) - " (length oidx--ids-focused-nodes)))
    (while (not (memq char (list ?s ?a ?d ?r)))
      (setq char (read-char prompt))
      (setq prompt (format "Actions on list of %d focused nodes:  s)et single focus on this node,  a)ppend this node to list,  d)elete this node from list,  r)estore previous list of focused nodes.  Please choose - " (length oidx--ids-focused-nodes))))
    (setq text
          (cond

           ((eq char ?s)
            (setq id (org-id-get-create))
            (setq oidx--ids-focused-nodes-saved oidx--ids-focused-nodes)
            (setq oidx--ids-focused-nodes (list id))
            (setq oidx--id-last-goto-focus id)
            (oidx--update-line id t)
            (if org-index-clock-into-focus (org-with-limited-levels (org-clock-in)))
            "focus has been set on current node (1 node in focus)")

           ((eq char ?a)
            (setq id (org-id-get-create))
            (unless (member id oidx--ids-focused-nodes)
              ;; remove any children, that are already in list of focused nodes
              (setq oidx--ids-focused-nodes
                    (delete nil (mapcar (lambda (x)
                                          (if (member id (org-with-point-at (org-id-find x t)
                                                           (oidx--ids-up-to-top)))
                                              (progn
                                                (setq more-text ", removing its children")
                                                nil)
                                            x))
                                        oidx--ids-focused-nodes)))
              (setq oidx--ids-focused-nodes-saved oidx--ids-focused-nodes)
              ;; remove parent, if already in list of focused nodes
              (setq ids-up-to-top (oidx--ids-up-to-top))
              (when (seq-intersection ids-up-to-top oidx--ids-focused-nodes)
                (setq oidx--ids-focused-nodes (seq-difference oidx--ids-focused-nodes ids-up-to-top))
                (setq more-text (concat more-text ", replacing its parent")))
              (setq oidx--ids-focused-nodes (cons id oidx--ids-focused-nodes)))
            (setq oidx--id-last-goto-focus id)
            (oidx--update-line id t)
            (if org-index-clock-into-focus (org-with-limited-levels (org-clock-in)))
            "current node has been appended to list of focused nodes%s (%d node%s in focus)")

           ((eq char ?d)
            (oidx--delete-from-focus)
            (concat "current node has been removed from list of focused nodes%s (%d node%s in focus), " (oidx--goto-focus) "."))

           ((eq char ?r)
            (if oidx--ids-focused-nodes-saved
                (let (txt)
                  (setq txt (format "discarded current list of focused %d focused node%s and restored previous list; now %%s%%d node%%s in focus" (length oidx--ids-focused-nodes-saved) (if (cdr oidx--ids-focused-nodes-saved) "s" "")))
                  (setq oidx--ids-focused-nodes oidx--ids-focused-nodes-saved)
                  txt)
              "no saved list of focused nodes to restore, nothing to do"))))

    (oidx--persist-focused-nodes)
    
    (format text (or more-text "") (length oidx--ids-focused-nodes) (if (cdr oidx--ids-focused-nodes) "s" ""))))


(defun oidx--persist-focused-nodes ()
  "Write list of focused nodes to property."
  (with-current-buffer oidx--buffer
    (org-entry-put oidx--point "ids-focused-nodes" (mapconcat 'identity oidx--ids-focused-nodes " "))))


(defun oidx--delete-from-focus ()
  "Delete current node from list of focused nodes."
  (let (id)
    (setq id (org-id-get))
    (if (and id (member id oidx--ids-focused-nodes))
        (progn
          (setq oidx--id-last-goto-focus
                (or (car-safe (cdr-safe (member id (reverse (append oidx--ids-focused-nodes
                                                                    oidx--ids-focused-nodes)))))
                    oidx--id-last-goto-focus))
          (setq oidx--ids-focused-nodes-saved oidx--ids-focused-nodes)
          (setq oidx--ids-focused-nodes (delete id oidx--ids-focused-nodes))
          (setq oidx--id-last-goto-focus nil)
          "Current node has been removed from list of focused nodes%s (%d node%s in focus)")
      "Current node has not been in list of focused nodes%s (%d node%s in focus)")))


(defun oidx--ids-up-to-top ()
  "Get list of all ids from current node up to top level."
  (when (string= major-mode "org-mode")
    (let (ids id)
      (save-excursion
        (ignore-errors
          (while (progn (and (setq id (org-id-get))
                             (setq ids (cons id ids)))
                        (outline-up-heading 1)))))
      ids)))



;; Variable and Functions for occur; most of them share state
;; between the functions of the occur-family of functions
(defconst oidx--usage-note " NOTE: If you invoke the subcommands edit (`e') or kill (`C-c i k')
from within this buffer, the index is updated accordingly" "Note on usage in occur buffer.")
(defconst oidx--occur-buffer-name "*org-index-occur*" "Name of occur buffer.")
(defvar oidx--occur-help-text nil "Text for help in occur buffer; cons with text short and long.")
(defvar oidx--occur-help-overlay nil "Overlay for help in occur buffer.")
(defvar oidx--occur-stack nil "Stack with overlays for hiding lines.")
(defvar oidx--occur-tail-overlay nil "Overlay to cover invisible lines.")
(defvar oidx--occur-lines-collected 0 "Number of lines collected in occur buffer; helpful for tests.")
(defvar oidx--occur-win-config nil "Window configuration stored away during occur.")
(defvar oidx--occur-point-begin nil "Point of first line of table contents.")
(defvar oidx--occur-buffer nil "Buffer, where occur takes place.")
(defvar oidx--occur-search-text nil "Description of text to search for.")
(defvar oidx--occur-words nil "Final list of match words.")
(defvar oidx--occur-days-clause nil "Clause for help text, denoting the number of days searched back.")


(defun oidx--do-occur (&optional days)
  "Perform command occur; optional narrow to DAYS back."
  (let ((word "") ; last word to search for growing and shrinking on keystrokes
        (prompt "Search for: ")
        (lines-wanted (window-body-height))
        words                                ; list words that should match
        done                           ; true, if loop is done
        in-c-backspace                 ; true, while processing C-backspace
        initial-frame                  ; Frame when starting occur
        key                            ; input from user in various forms
        key-sequence
        key-sequence-raw)


    (oidx--occur-prepare-buffer days)

    (setq initial-frame (selected-frame))

    ;; do not enter loop if number of days is requested
    (when days
      (goto-char oidx--occur-point-begin)
      (oidx--hide-with-overlays (cons word words) lines-wanted days)
      (move-overlay oidx--occur-tail-overlay (oidx--occur-end-of-visible) (point-max))
      
      (goto-char oidx--occur-point-begin)
      (setq done t))

    ;; main loop
    (while (not done)

      (if in-c-backspace
          (setq key "<backspace>")
        (setq oidx--occur-search-text (mapconcat 'identity (reverse (cons word words)) ","))

        ;; read key, if selected frame has not changed
        (if (eq initial-frame (selected-frame))
            (progn
              (setq key-sequence
                    (let ((echo-keystrokes 0)
                          (full-prompt (format "%s%s%s"
                                               prompt
                                               oidx--occur-search-text
                                               (if (string= oidx--occur-search-text "") "" " "))))
                      (read-key-sequence full-prompt nil nil t t)))
              (setq key (key-description key-sequence))
              (setq key-sequence-raw (this-single-command-raw-keys)))
          (setq done t)
          (setq key-sequence nil)
          (setq key nil)
          (setq key-sequence-raw nil)))
      

      (cond


       ((string= key "<C-backspace>")
        (setq in-c-backspace t))


       ((member key (list "<backspace>" "DEL"))   ; erase last char

        (if (= (length word) 0)

            ;; nothing more to delete from current word; try next
            (progn
              (setq word (car words))
              (setq words (cdr words))
              (setq in-c-backspace nil))

          ;; some chars are left; shorten word
          (setq word (substring word 0 -1))
          (when (= (length word) 0) ; when nothing left, use next word from list
            (setq word (car words))
            (setq words (cdr words))
            (setq in-c-backspace nil))

          ;; free top list of overlays and remove list
          (oidx--unhide)
          (move-overlay oidx--occur-tail-overlay
                        (oidx--occur-end-of-visible)
                        (point-max))
          
          ;; make sure, point is still visible
          (goto-char oidx--occur-point-begin)))


       ((member key (list "SPC" ",")) ; space or comma: enter an additional search word

        ;; push current word and clear, no need to change display
        (unless (string= word "")
          (setq words (cons word words))
          (setq word "")))


       ((string= key "?") ; question mark: toggle display of headlines and help
        (setq oidx--occur-help-text (cons (cdr oidx--occur-help-text)
                                          (car oidx--occur-help-text))) ; swap
        (overlay-put oidx--occur-help-overlay 'display (car oidx--occur-help-text)))

       ((and (= (length key) 1)
             (aref printable-chars (elt key 0))) ; any printable char: add to current search word

        ;; add to word
        (setq word (concat word key))
        
        ;; make overlays to hide lines, that do not match longer word any more
        (goto-char oidx--occur-point-begin)
        (oidx--hide-with-overlays (cons word words) lines-wanted days)
        (move-overlay oidx--occur-tail-overlay
                      (oidx--occur-end-of-visible)
                      (point-max))
        
        (goto-char oidx--occur-point-begin)
        
        ;; make sure, point is on a visible line
        (line-move -1 t)
        (line-move 1 t))

       ;; anything else terminates input loop
       (t (setq done t))))

    ;; remember list of words
    (setq oidx--occur-words (cons word words))

    ;; put back input event, that caused the loop to end
    (if (string= key "C-g")
        (progn (if oidx--occur-win-config (set-window-configuration oidx--occur-win-config))
               (keyboard-quit))
      (setq unread-command-events (listify-key-sequence key-sequence-raw))
      (message key))
    

    (oidx--occur-make-permanent lines-wanted)

    (oidx--occur-install-keyboard-shortcuts)))


(defun oidx--occur-prepare-buffer (days)
  "Prepare buffer for 'oidx--do-occur; optional narrow to DAYS back."

  ;; make and show buffer
  (if (get-buffer oidx--occur-buffer-name)
      (kill-buffer oidx--occur-buffer-name))
  (setq oidx--occur-buffer (make-indirect-buffer oidx--buffer oidx--occur-buffer-name))
  (setq oidx--occur-win-config (current-window-configuration))
  (pop-to-buffer-same-window oidx--occur-buffer)

  ;; avoid modifying direct buffer
  (setq buffer-read-only t)
  (toggle-truncate-lines 1)

  ;; reset stack and overlays
  (setq oidx--occur-stack nil)
  (setq oidx--occur-tail-overlay nil)
  
  ;; narrow to table rows and one line before
  (goto-char oidx--below-hline)
  (forward-line 0)
  (setq oidx--occur-point-begin (point))
  (forward-line -1)
  (narrow-to-region (point) (org-table-end))
  (forward-line)

  ;; initialize help text
  (setq oidx--occur-days-clause (if days (format " (%d days back)" days) ""))
  (setq oidx--occur-help-text
        (cons
         (concat
          (propertize (format "Incremental occur%s" oidx--occur-days-clause) 'face 'org-todo)
          (propertize  "; ? toggles help and headlines.\n" 'face 'org-agenda-dimmed-todo-face))
         (concat
          (propertize
           (oidx--wrap
            (concat
             "Normal keys add to search word; <space> or <comma> start additional word; <backspace> erases last char, <C-backspace> last word; <return> jumps to heading, <tab> jumps to heading in other window, <S-return> jumps to matching line in index; all other keys end search." oidx--usage-note "\n"))
           'face 'org-agenda-dimmed-todo-face)
          oidx--headings)))
  
  ;; insert overlays for help text and to cover unsearched lines
  (setq oidx--occur-help-overlay (make-overlay (point-min) oidx--occur-point-begin))
  (overlay-put oidx--occur-help-overlay 'display (car oidx--occur-help-text))
  (setq oidx--occur-tail-overlay (make-overlay (point-max) (point-max)))
  (overlay-put oidx--occur-tail-overlay 'invisible t))


(defun oidx--occur-make-permanent (lines-wanted)
  "Make permanent copy of current view into index.
Argument LINES-WANTED specifies number of lines to display."

  ;; copy visible lines
  (let ((lines-collected 0)
        line all-lines all-lines-lbp header-lines lbp)

    (setq cursor-type t)
    (goto-char oidx--occur-point-begin)
    (let ((inhibit-read-only t))
      (put-text-property oidx--occur-point-begin (org-table-end) 'face nil))

    ;; collect all visible lines
    (while (and (not (eobp))
                (< lines-collected lines-wanted))
      ;; skip over invisible lines
      (while (and (invisible-p (point))
                  (not (eobp)))
        (goto-char (1+ (overlay-end (car (overlays-at (point)))))))
      (setq lbp (line-beginning-position))
      (setq line (buffer-substring-no-properties lbp (line-end-position)))
      (unless (string= line "")
        (cl-incf lines-collected)
        (setq all-lines (cons (concat line
                                      "\n")
                              all-lines))
        (setq all-lines-lbp (cons lbp all-lines-lbp)))
      (forward-line 1))
    
    (kill-buffer oidx--occur-buffer-name) ; cannot keep this buffer; might become stale soon

    ;; create new buffer
    (setq oidx--occur-buffer (get-buffer-create oidx--occur-buffer-name))
    (pop-to-buffer-same-window oidx--occur-buffer)
    (insert oidx--headings)
    (setq header-lines (line-number-at-pos))

    ;; insert into new buffer
    (save-excursion
      (apply 'insert (reverse all-lines))
      (if (= lines-collected lines-wanted)
          (insert "\n(more lines omitted)\n")))
    (setq oidx--occur-lines-collected lines-collected)
    
    (org-mode)
    (setq truncate-lines t)
    (if all-lines (oidx--align-and-fontify-current-line (length all-lines)))
    (when (fboundp 'font-lock-ensure)
      (font-lock-ensure))
    (when all-lines-lbp
      (while (not (org-at-table-p))
        (forward-line -1))
      (while all-lines-lbp
        (put-text-property (line-beginning-position) (line-end-position) 'org-index-lbp (car all-lines-lbp))
        (setq all-lines-lbp (cdr all-lines-lbp))
        (forward-line -1)))

    ;; prepare help text
    (goto-char (point-min))
    (forward-line (1- header-lines))
    (setq oidx--occur-help-overlay (make-overlay (point-min) (point)))
    (setq oidx--occur-help-text
          (cons
           (oidx--wrap
            (propertize (format "Search is done%s;    ? toggles help and headlines.\n" oidx--occur-days-clause) 'face 'org-agenda-dimmed-todo-face))
           (concat
            (oidx--wrap
             (propertize
              (format
               (concat (format "Search is done%s." oidx--occur-days-clause)
                       (if (< lines-collected lines-wanted)
                           " Showing all %d matches for "
                         " Showing one window of matches for ")
                       "\"" oidx--occur-search-text
                       "\". <return> jumps to heading, <tab> jumps to heading in other window, <S-return> jumps to matching line in index, <space> increments count.\n" oidx--usage-note "\n")
               (length all-lines))
              'face 'org-agenda-dimmed-todo-face))
            oidx--headings)))
    
    (overlay-put oidx--occur-help-overlay 'display (car oidx--occur-help-text))

    ;; highlight words
    (mapc (lambda (w) (unless (or (not w) (string= w ""))
                        (highlight-regexp
                         (if (string= w (downcase w))
                             (apply 'concat (mapcar (lambda (c) (if (string-match "[[:alpha:]]" (char-to-string c))
                                                                    (format "[%c%c]" (downcase c) (upcase c))
                                                                  (char-to-string c)))
                                                    (regexp-quote w)))
                           (regexp-quote w)) 'isearch)))
          oidx--occur-words)
    
    (setq buffer-read-only t)))


(defun oidx--occur-install-keyboard-shortcuts ()
  "Install keyboard-shortcuts for result of occur buffer."

  (let (keymap)
    (setq keymap (make-sparse-keymap))
    (set-keymap-parent keymap org-mode-map)
    
    (mapc (lambda (x) (define-key keymap (kbd x)
                        (lambda () (interactive)
                          (message "%s" (oidx--occur-action)))))
          (list "<return>" "RET"))
    
    (define-key keymap (kbd "<tab>")
      (lambda () (interactive)
        (message (oidx--occur-action t))))
    
    (define-key keymap (kbd "e")
      (lambda () (interactive)
        (message (oidx--do 'edit))))
    
    (define-key keymap (kbd "SPC")
      (lambda () (interactive)
        (oidx--refresh-parse-table)
        ;; increment in index
        (let ((ref (oidx--get-or-set-field 'ref))
              count)
          (oidx--on
              'ref ref
            (setq count (+ 1 (string-to-number (oidx--get-or-set-field 'count))))
            (oidx--get-or-set-field 'count (number-to-string count))
            (oidx--promote-current-line)
            (oidx--align-and-fontify-current-line))
          ;; increment in this buffer
          (let ((inhibit-read-only t))
            (oidx--get-or-set-field 'count (number-to-string count)))
          (message "Incremented count to %d" count))))
    
    (define-key keymap (kbd "<S-return>")
      (lambda () (interactive)
        (let ((pos (get-text-property (point) 'org-index-lbp)))
          (oidx--refresh-parse-table)
          (oidx--occur-test-stale pos)
          (pop-to-buffer oidx--buffer)
          (goto-char pos)
          (org-reveal t)
          (oidx--update-current-line)
          (beginning-of-line))))

    (define-key keymap (kbd "?")
      (lambda () (interactive)
        (oidx--refresh-parse-table)
        (setq-local oidx--occur-help-text (cons (cdr oidx--occur-help-text) (car oidx--occur-help-text)))
        (overlay-put oidx--occur-help-overlay 'display (car oidx--occur-help-text))))
    
    (use-local-map keymap)))


(defun oidx--occur-end-of-visible ()
  "End of visible stretch during occur."
  (if oidx--occur-stack
      (cdr (assoc :end-of-visible (car oidx--occur-stack)))
    (point-max)))


(defun oidx--occur-test-stale (pos)
  "Test, if current line in occur buffer has become stale at POS."
  (let (here there)
    (oidx--refresh-parse-table)
    (setq here (oidx--line-in-canonical-form))
    (with-current-buffer oidx--buffer
      (goto-char pos)
      (setq there (oidx--line-in-canonical-form)))
    (unless (string= here there)
      (error "Occur buffer has become stale; please repeat search"))))


(defun oidx--occur-action (&optional other)
  "Helper for `oidx--occur', find heading with ref or id; if OTHER, in other window; or copy yank column."
  (if (org-at-table-p)
      (let ((id (oidx--get-or-set-field 'id))
            (ref (oidx--get-or-set-field 'ref))
            (yank (oidx--get-or-set-field 'yank)))
        (if id
            (oidx--find-id id other)
          (if ref
              (progn
                (org-mark-ring-goto)
                (format "Found reference %s (no node is associated)" ref))
            (if yank
                (progn
                  (oidx--update-line (get-text-property (point) 'org-index-lbp))
                  (setq yank (replace-regexp-in-string (regexp-quote "\\vert") "|" yank nil 'literal))
                  (kill-new yank)
                  (org-mark-ring-goto)
                  (if (and (>= (length yank) 4) (string= (substring yank 0 4) "http"))
                      (progn
                        (browse-url yank)
                        (format "Opened '%s' in browser (and copied it too)" yank))
                    (format "Copied '%s' (no node is associated)" yank)))
              (error "Internal error, this line contains neither id, nor reference, nor text to yank")))))
    (message "Not at table")))


(defun oidx--hide-with-overlays (words lines-wanted days)
  "Hide lines that are currently visible and do not match WORDS; 
leave LINES-WANTED lines visible.
Argument DAYS hides older lines."
  (let ((lines-found 0)
        (end-of-visible (point))
        overlay overlays start matched places all-places)

    ;; main loop
    (while (and (not (eobp))
                (< lines-found lines-wanted))

      ;; skip invisible lines
      (while (and (not (eobp))
                  (and
                   (invisible-p (point))
                   (< (point) (overlay-start oidx--occur-tail-overlay))))
        (goto-char (overlay-end (car (overlays-at (point))))))

      ;; find stretch of lines, that are currently visible but should be invisible now
      (setq matched nil)
      (setq places nil)
      (setq start (point))
      (while (and (not (eobp))
                  (not (and
                        (invisible-p (point))
                        (< (point) (overlay-start oidx--occur-tail-overlay))))
                  ;; either regard words or days, but not both
                  (if days
                      (let ((last-accessed (oidx--get-or-set-field 'last-accessed)))
                        (if last-accessed
                            (not (and
                                  (<= (- (time-to-days (current-time))
                                         (time-to-days (org-read-date nil t last-accessed nil)))
                                      days)
                                  (setq matched t))) ; for its side effect
                          t))
                    (not (and (setq places (oidx--test-words words))
                              (setq matched t))))) ; for its side effect
        (forward-line 1))

      (setq all-places (append places all-places))

      ;; create overlay to hide this stretch
      (when (< start (point))           ; avoid creating an empty overlay
        (setq overlay (make-overlay start (point)))
        (overlay-put overlay 'invisible t)
        (setq overlays (cons overlay overlays)))

      ;; skip and count line, that matched
      (when matched
        (let ((inhibit-read-only t) (lbp (line-beginning-position)))
          (put-text-property lbp (line-end-position) 'face nil)
          (while places
            (put-text-property (caar places) (+ (caar places) (cdar places)) 'face 'isearch)
            (setq places (cdr places))))
        (forward-line 1)
        (setq end-of-visible (point))
        (cl-incf lines-found)))
    
    ;; put new list on top of stack
    (setq oidx--occur-stack
          (cons (list (cons :overlays overlays)
                      (cons :end-of-visible end-of-visible)
                      (cons :lines lines-found)
		      (cons :places all-places))
                oidx--occur-stack))

    lines-found))


(defun oidx--unhide ()
  "Unhide text that does has been hidden by `oidx--hide-with-overlays'."
  (let (places)
    (when oidx--occur-stack
      ;; delete overlays and make visible again
      (mapc (lambda (y)
              (delete-overlay y))
            (cdr (assoc :overlays (car oidx--occur-stack))))
      ;; remove latest highlights
      (setq places (cdr (assoc :places (car oidx--occur-stack))))
      (while places
        (let ((inhibit-read-only t))
          (put-text-property (caar places) (+ (caar places) (cdar places)) 'face nil))
        (setq places (cdr places)))
      ;; remove top of stack
      (setq oidx--occur-stack (cdr oidx--occur-stack))
      ;; redo older highlights
      (setq places (cdr (assoc :places (car oidx--occur-stack))))
      (while places
        (let ((inhibit-read-only t))
          (put-text-property (caar places) (+ (caar places) (cdar places)) 'face 'isearch))
        (setq places (cdr places))))))


(defun oidx--test-words (words)
  "Test current line for match against WORDS."
  (let ((lbp (line-beginning-position))
        line dc-line places index)
    (setq line (buffer-substring lbp (line-beginning-position 2)))
    (setq dc-line (downcase line))
    (catch 'not-found
      (dolist (word words)
        (if (setq index (cl-search word (if (string= word (downcase word)) dc-line line)))
            (setq places (cons (cons (+ lbp index) (length word)) places))
          (throw 'not-found nil)))
      places)))


(defun oidx--copy-visible (beg end)
  "Copy the visible parts of the region between BEG and END without adding it to `kill-ring'; copy of `org-copy-visible'."
  (let (snippets s)
    (save-excursion
      (save-restriction
	(narrow-to-region beg end)
	(setq s (goto-char (point-min)))
	(while (not (= (point) (point-max)))
	  (goto-char (org-find-invisible))
	  (push (buffer-substring s (point)) snippets)
	  (setq s (goto-char (org-find-visible))))))
    (apply 'concat (nreverse snippets))))


(provide 'org-index)

;; Local Variables:
;; fill-column: 75
;; comment-column: 50
;; End:

;;; org-index.el ends here
