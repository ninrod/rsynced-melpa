;;; easy-kill.el --- kill & mark things easily       -*- lexical-binding: t; -*-

;; Copyright (C) 2013-2014  Free Software Foundation, Inc.

;; Author: Leo Liu <sdl.web@gmail.com>
;; Version: 0.9.2
;; Package-Requires: ((emacs "24") (cl-lib "0.5"))
;; Keywords: killing, convenience
;; Created: 2013-08-12
;; URL: https://github.com/leoliu/easy-kill

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

;; `easy-kill' aims to be a drop-in replacement for `kill-ring-save'.
;;
;; To use: (global-set-key [remap kill-ring-save] 'easy-kill)

;; `easy-mark' is similar to `easy-kill' but marks the region
;; immediately. It can be a handy replacement for `mark-sexp' allowing
;; `+'/`-' to do list-wise expanding/shrinking.
;;
;; To use: (global-set-key [remap mark-sexp] 'easy-mark)

;; Please send bug reports or feature requests to:
;;      https://github.com/leoliu/easy-kill/issues

;;; Code:

(require 'cl-lib)
(require 'thingatpt)
(eval-when-compile (require 'cl))       ;For `defsetf'.

(eval-and-compile
  (cond
   ((fboundp 'set-transient-map) nil)
   ((fboundp 'set-temporary-overlay-map) ; new in 24.3
    (defalias 'set-transient-map 'set-temporary-overlay-map))
   (t
    (defun set-transient-map (map &optional keep-pred)
      (let* ((clearfunsym (make-symbol "clear-temporary-overlay-map"))
             (overlaysym (make-symbol "t"))
             (alist (list (cons overlaysym map)))
             (clearfun
              `(lambda ()
                 (unless ,(cond ((null keep-pred) nil)
                                ((eq t keep-pred)
                                 `(eq this-command
                                      (lookup-key ',map
                                                  (this-command-keys-vector))))
                                (t `(funcall ',keep-pred)))
                   (set ',overlaysym nil) ;Just in case.
                   (remove-hook 'pre-command-hook ',clearfunsym)
                   (setq emulation-mode-map-alists
                         (delq ',alist emulation-mode-map-alists))))))
        (set overlaysym overlaysym)
        (fset clearfunsym clearfun)
        (add-hook 'pre-command-hook clearfunsym)
        (push alist emulation-mode-map-alists))))))

(defcustom easy-kill-alist
  '((?w word     " ")
    (?s sexp     "\n")
    (?l list     "\n")
    (?f filename "\n")
    (?d defun    "\n\n")
    (?e line     "\n")
    (?b buffer-file-name))
  "A list of (CHAR THING APPEND).
CHAR is used immediately following `easy-kill' to select THING.
APPEND is optional and if non-nil specifies the separator (a
string) for appending current selection to previous kill.

Note: each element can also be (CHAR . THING) but this is
deprecated."
  :type '(repeat (list character symbol
                       (choice string (const :tag "None" nil))))
  :group 'killing)

(defcustom easy-kill-try-things '(url email line)
  "A list of things for `easy-kill' to try."
  :type '(repeat symbol)
  :group 'killing)

(defcustom easy-mark-try-things '(url email sexp)
  "A list of things for `easy-mark' to try."
  :type '(repeat symbol)
  :group 'killing)

(defface easy-kill-selection '((t (:inherit secondary-selection)))
  "Faced used to highlight kill candidate."
  :group 'killing)

(defface easy-kill-origin '((t (:inverse-video t :inherit error)))
  "Faced used to highlight the origin."
  :group 'killing)

(defvar easy-kill-base-map
  (let ((map (make-sparse-keymap)))
    (define-key map "-" 'easy-kill-shrink)
    (define-key map "+" 'easy-kill-expand)
    (define-key map "=" 'easy-kill-expand)
    (define-key map "@" 'easy-kill-append)
    (define-key map [remap set-mark-command] 'easy-kill-mark-region)
    (define-key map [remap kill-region] 'easy-kill-region)
    (define-key map [remap keyboard-quit] 'easy-kill-abort)
    (mapc (lambda (d)
            (define-key map (number-to-string d) 'easy-kill-digit-argument))
          (number-sequence 0 9))
    map))

(defun easy-kill-map ()
  "Build the keymap according to `easy-kill-alist'."
  (let ((map (make-sparse-keymap)))
    (set-keymap-parent map easy-kill-base-map)
    (mapc (lambda (c)
            ;; (define-key map (vector meta-prefix-char c) 'easy-kill-select)
            (define-key map (char-to-string c) 'easy-kill-thing))
          (mapcar 'car easy-kill-alist))
    map))

(defvar easy-kill-inhibit-message nil)

(defun easy-kill-echo (format-string &rest args)
  "Same as `message' except not writing to *Messages* buffer.
Do nothing if `easy-kill-inhibit-message' is non-nil."
  (unless easy-kill-inhibit-message
    (let (message-log-max)
      (apply 'message format-string args))))

(defun easy-kill-trim (s &optional how)
  (let ((wchars "[ \t\n\r\f\v]*"))
    (pcase how
      (`left (and (string-match (concat "\\`" wchars) s)
                  (substring s (match-end 0))))
      (`right (substring s 0 (string-match-p (concat wchars "\\'") s)))
      (_ (easy-kill-trim (easy-kill-trim s 'left) 'right)))))

(defun easy-kill-fboundp (name)
  "Like `fboundp' but NAME can be string or symbol.
The value is the function's symbol if non-nil."
  (cl-etypecase name
    (string (easy-kill-fboundp (intern-soft name)))
    (symbol (and (fboundp name) name))))

(defun easy-kill-pair-to-list (pair)
  (pcase pair
    (`nil nil)
    (`(,beg . ,end) (list beg end))
    (_ (signal 'wrong-type-argument (list pair "Not a dot pair")))))

(defun easy-kill-interprogram-cut (text)
  "Make non-empty TEXT available to other programs."
  (cl-check-type text string)
  (and interprogram-cut-function
       (not (equal text ""))
       (funcall interprogram-cut-function text)))

(defvar easy-kill-candidate nil)
(defvar easy-kill-append nil)
(defvar easy-kill-mark nil)

(defun easy-kill--bounds ()
  (cons (overlay-start easy-kill-candidate)
        (overlay-end easy-kill-candidate)))

;;; Note: gv-define-setter not available in 24.1 and 24.2
;; (gv-define-setter easy-kill--bounds (val)
;;   (macroexp-let2 macroexp-copyable-p v val
;;     `(move-overlay easy-kill-candidate (car ,v) (cdr ,v))))

(defsetf easy-kill--bounds () (v)
  `(let ((tmp ,v))
     (move-overlay easy-kill-candidate (car tmp) (cdr tmp))))

(defmacro easy-kill-get (prop)
  "Get the value of the kill candidate's property PROP.
Use `setf' to change property value."
  (pcase prop
    (`start  '(overlay-start easy-kill-candidate))
    (`end    '(overlay-end easy-kill-candidate))
    (`bounds '(easy-kill--bounds))
    (`buffer '(overlay-buffer easy-kill-candidate))
    (`properties '(append (list 'start (easy-kill-get start))
                          (list 'end (easy-kill-get end))
                          (overlay-properties easy-kill-candidate)))
    (_       `(overlay-get easy-kill-candidate ',prop))))

(defun easy-kill-init-candidate (n)
  ;; Manipulate `easy-kill-candidate' directly during initialisation;
  ;; should use `easy-kill-get' elsewhere.
  (let ((o (make-overlay (point) (point))))
    (unless easy-kill-mark
      (overlay-put o 'face 'easy-kill-selection))
    (overlay-put o 'origin (point))
    (overlay-put o 'help-echo #'easy-kill-describe-candidate)
    ;; Use higher priority to avoid shadowing by, for example,
    ;; `hl-line-mode'.
    (overlay-put o 'priority 999)
    (when easy-kill-mark
      (let ((i (make-overlay (point) (point))))
        (overlay-put i 'priority (1+ (overlay-get o 'priority)))
        (overlay-put i 'face 'easy-kill-origin)
        (overlay-put i 'as (propertize " " 'face 'easy-kill-origin))
        (overlay-put o 'origin-indicator i)))
    (setq easy-kill-candidate o)
    (save-restriction
      ;; Work around http://debbugs.gnu.org/15808; not needed in 24.4.
      (narrow-to-region (max (point-min) (- (point) 1000))
                        (min (point-max) (+ (point) 1000)))
      (let ((easy-kill-inhibit-message t))
        (cl-dolist (thing easy-kill-try-things)
          (easy-kill-thing thing n)
          (or (string= (easy-kill-candidate) "")
              (cl-return)))))
    o))

(defun easy-kill-indicate-origin ()
  (let ((i (easy-kill-get origin-indicator))
        (origin (easy-kill-get origin)))
    (cond
     ((not (overlayp i)) nil)
     ((= origin (point))
      (overlay-put i 'after-string nil))
     ((memq (char-after origin) '(?\t ?\n))
      (overlay-put i 'after-string (overlay-get i 'as)))
     (t (move-overlay i origin (1+ origin))
        (overlay-put i 'after-string nil)))))

(defun easy-kill-candidate ()
  "Get the kill candidate as a string.
If the overlay specified by variable `easy-kill-candidate' has
non-zero length, it is the string covered by the overlay.
Otherwise, it is the value of the overlay's candidate property."
  (with-current-buffer (easy-kill-get buffer)
    (or (pcase (easy-kill-get bounds)
          (`(,_x . ,_x) (easy-kill-get candidate))
          (`(,beg . ,end) (filter-buffer-substring beg end)))
        "")))

(defun easy-kill-describe-candidate (&rest _)
  "Return a string that describes current kill candidate."
  (let* ((props (cl-loop for k in '(thing start end origin)
                         with all = (easy-kill-get properties)
                         ;; Allow describe-PROP to provide customised
                         ;; description.
                         for dk = (intern-soft (format "describe-%s" k))
                         for dv = (and dk (plist-get all dk))
                         for v = (or (if (functionp dv) (funcall dv) dv)
                                     (plist-get all k))
                         when v collect (format "%s:\t%s" k v)))
         (txt (mapconcat #'identity props "\n")))
    (format "cmd:\t%s\n%s" (if easy-kill-mark "easy-mark" "easy-kill") txt)))

(defun easy-kill-adjust-candidate (thing &optional beg end)
  "Adjust kill candidate to THING, BEG, END.
If BEG is a string, shrink the overlay to zero length and set its
candidate property instead."
  (setf (easy-kill-get thing) thing)
  (cond ((stringp beg)
         (setf (easy-kill-get bounds) (cons (point) (point)))
         (setf (easy-kill-get candidate) beg)
         (let ((easy-kill-inhibit-message nil))
           (easy-kill-echo "%s" beg)))
        (t
         (setf (easy-kill-get bounds) (cons (or beg (easy-kill-get start))
                                            (or end (easy-kill-get end))))))
  (cond (easy-kill-mark (easy-kill-mark-region)
                        (easy-kill-indicate-origin))
        (t (easy-kill-interprogram-cut (easy-kill-candidate)))))

(defun easy-kill-save-candidate ()
  (unless (string= (easy-kill-candidate) "")
    ;; Don't modify the clipboard here since it is called in
    ;; `pre-command-hook' per `easy-kill-activate-keymap' and will
    ;; confuse `yank' if it is current command. Also
    ;; `easy-kill-adjust-candidate' already did that.
    (let ((interprogram-cut-function nil)
          (interprogram-paste-function nil))
      (kill-new (if (and easy-kill-append kill-ring)
                    (cl-labels ((join (x sep y)
                                      (if sep (concat (easy-kill-trim x 'right)
                                                      sep
                                                      (easy-kill-trim y 'left))
                                        (concat x y))))
                      (join (car kill-ring)
                            (nth 2 (cl-rassoc (easy-kill-get thing)
                                              easy-kill-alist :key #'car))
                            (easy-kill-candidate)))
                  (easy-kill-candidate))
                easy-kill-append))
    t))

(defun easy-kill-destroy-candidate ()
  (let ((hook (make-symbol "easy-kill-destroy-candidate")))
    (fset hook `(lambda ()
                  (let ((o ,easy-kill-candidate))
                    (when o
                      (let ((i (overlay-get o 'origin-indicator)))
                        (and (overlayp i) (delete-overlay i)))
                      (delete-overlay o)))
                  (remove-hook 'post-command-hook ',hook)))
    ;; Run in `post-command-hook' so that exit commands can still use
    ;; `easy-kill-candidate'.
    (add-hook 'post-command-hook hook)))

(defun easy-kill-expand ()
  (interactive)
  (easy-kill-thing nil '+))

(defun easy-kill-digit-argument (n)
  (interactive
   (list (- (logand (if (integerp last-command-event)
                        last-command-event
                      (get last-command-event 'ascii-character))
                    ?\177)
            ?0)))
  (easy-kill-thing nil n))

(defun easy-kill-shrink ()
  (interactive)
  (easy-kill-thing nil '-))

;; Helper for `easy-kill-thing'.
(defun easy-kill-thing-forward (n)
  (when (and (easy-kill-get thing) (/= n 0))
    (let* ((step (if (cl-minusp n) -1 +1))
           (thing (easy-kill-get thing))
           (bounds1 (or (easy-kill-pair-to-list (bounds-of-thing-at-point thing))
                        (list (point) (point))))
           (start (easy-kill-get start))
           (end (easy-kill-get end))
           (front (or (car (cl-set-difference (list end start) bounds1))
                      (pcase step
                        (`-1 start)
                        (`1 end))))
           (new-front (save-excursion
                        (goto-char front)
                        (with-demoted-errors
                          (cl-labels ((forward-defun (s)
                                                     (pcase s
                                                       (`-1 (beginning-of-defun 1))
                                                       (`+1 (end-of-defun 1)))))
                            (dotimes (_ (abs n))
                              ;; Work around http://debbugs.gnu.org/17247
                              (if (eq thing 'defun)
                                  (forward-defun step)
                                (forward-thing thing step)))))
                        (point))))
      (pcase (and (/= front new-front)
                  (sort (cons new-front bounds1) #'<))
        (`(,start ,_ ,end)
         (easy-kill-adjust-candidate thing start end)
         t)))))

(defun easy-kill-thing-handler (thing mode)
  "Get the handler for THING or nil if none is defined.
For example, if THING is list and MODE is nxml-mode
`nxml:easy-kill-on-list', `easy-kill-on-list:nxml' are checked in
order. The former is never defined in this package and is safe
for users to customise. If neither is defined continue checking
on the parent mode. Finally `easy-kill-on-list' is checked."
  (cl-labels ((sname (m) (cl-etypecase m
                           (symbol (sname (symbol-name m)))
                           (string (substring m 0 (string-match-p
                                                   "\\(?:-minor\\)?-mode\\'" m))))))
    (let ((parent (get mode 'derived-mode-parent)))
      (or (and mode (or (easy-kill-fboundp
                         (format "%s:easy-kill-on-%s" (sname mode) thing))
                        (easy-kill-fboundp
                         (format "easy-kill-on-%s:%s" thing (sname mode)))))
          (and parent (easy-kill-thing-handler thing parent))
          (easy-kill-fboundp (format "easy-kill-on-%s" thing))))))

(defun easy-kill-thing (&optional thing n inhibit-handler)
  ;; N can be -, + and digits
  (interactive
   (list (pcase (assq last-command-event easy-kill-alist)
           (`(,_ ,th . ,_) th)
           (`(,_ . ,th) th))
         (prefix-numeric-value current-prefix-arg)))
  (let* ((thing (or thing (easy-kill-get thing)))
         (n (or n 1))
         (handler (and (not inhibit-handler)
                       (easy-kill-thing-handler thing major-mode))))
    (when easy-kill-mark
      (goto-char (easy-kill-get origin)))
    (cond
     (handler (funcall handler n))
     ((or (eq thing (easy-kill-get thing))
          (memq n '(+ -)))
      (easy-kill-thing-forward (pcase n
                                 (`+ 1)
                                 (`- -1)
                                 (_ n))))
     (t (pcase (bounds-of-thing-at-point thing)
          (`nil (easy-kill-echo "No `%s'" thing))
          (`(,start . ,end)
           (easy-kill-adjust-candidate thing start end)
           (easy-kill-thing-forward (1- n))))))
    (when easy-kill-mark
      (easy-kill-adjust-candidate (easy-kill-get thing)))))

(put 'easy-kill-abort 'easy-kill-exit t)
(defun easy-kill-abort ()
  (interactive)
  (when easy-kill-mark
    ;; The after-string may interfere with `goto-char'.
    (overlay-put (easy-kill-get origin-indicator) 'after-string nil)
    (goto-char (easy-kill-get origin))
    (setq deactivate-mark t))
  (ding))

(put 'easy-kill-region 'easy-kill-exit t)
(defun easy-kill-region ()
  "Kill current selection and exit."
  (interactive "*")
  (pcase (easy-kill-get bounds)
    (`(,_x . ,_x) (easy-kill-echo "Empty region"))
    (`(,beg . ,end) (kill-region beg end))))

(put 'easy-kill-mark-region 'easy-kill-exit t)
(defun easy-kill-mark-region ()
  (interactive)
  (pcase (easy-kill-get bounds)
    (`(,_x . ,_x)
     (easy-kill-echo "Empty region"))
    (`(,beg . ,end)
     (set-mark beg)
     (goto-char end)
     (activate-mark))))

(put 'easy-kill-append 'easy-kill-exit t)
(defun easy-kill-append ()
  (interactive)
  (setq easy-kill-append t)
  (when (easy-kill-save-candidate)
    (easy-kill-interprogram-cut (car kill-ring))
    (setq deactivate-mark t)
    (easy-kill-echo "Appended")))

(defun easy-kill-exit-p (cmd)
  (and (symbolp cmd) (get cmd 'easy-kill-exit)))

(defun easy-kill-activate-keymap ()
  (let ((map (easy-kill-map)))
    (set-transient-map
     map
     (lambda ()
       ;; Prevent any error from activating the keymap forever.
       (condition-case err
           (or (and (not (easy-kill-exit-p this-command))
                    (or (eq this-command
                            (lookup-key map (this-single-command-keys)))
                        (let ((cmd (key-binding
                                    (this-single-command-keys) nil t)))
                          (command-remapping cmd nil (list map)))))
               (ignore
                (easy-kill-destroy-candidate)
                (unless (or easy-kill-mark (easy-kill-exit-p this-command))
                  (easy-kill-save-candidate))))
         (error (message "%s:%s" this-command (error-message-string err))
                nil))))))

;;;###autoload
(defun easy-kill (&optional n)
  "Kill thing at point in the order of region, url, email and line.
Temporally activate additional key bindings as follows:

  letters => select or expand selection according to `easy-kill-alist';
  0..9    => expand selection by that number;
  +,=/-   => expand or shrink selection;
  @       => append selection to previous kill;
  C-w     => kill selection;
  C-SPC   => turn selection into an active region;
  C-g     => abort;
  others  => save selection and exit."
  (interactive "p")
  (if (use-region-p)
      (if (fboundp 'rectangle-mark-mode) ; New in 24.4
          (with-no-warnings
            (kill-ring-save (region-beginning) (region-end) t))
        (kill-ring-save (region-beginning) (region-end)))
    (setq easy-kill-mark nil)
    (setq easy-kill-append (eq last-command 'kill-region))
    (easy-kill-init-candidate n)
    (when (zerop (buffer-size))
      (easy-kill-echo "Warn: `easy-kill' activated in empty buffer"))
    (easy-kill-activate-keymap)))

;;;###autoload
(defalias 'easy-mark-sexp 'easy-mark
  "Use `easy-mark' instead. The alias may be removed in future.")

;;;###autoload
(defun easy-mark (&optional n)
  "Similar to `easy-kill' (which see) but for marking."
  (interactive "p")
  (let ((easy-kill-try-things easy-mark-try-things))
    (setq easy-kill-mark t)
    (easy-kill-init-candidate n)
    (easy-kill-activate-keymap)
    (unless (easy-kill-get thing)
      (setf (easy-kill-get thing) 'sexp)
      (easy-kill-thing 'sexp n))))

;;;; Extended things

;;; Handler for `buffer-file-name'.

(defun easy-kill-on-buffer-file-name (n)
  "Get `buffer-file-name' or `default-directory'.
If N is zero, remove the directory part; -, remove the file name
part; +, full path."
  (if easy-kill-mark
      (easy-kill-echo "Not supported in `easy-mark'")
    (pcase (or buffer-file-name default-directory)
      (`nil (easy-kill-echo "No `buffer-file-name'"))
      (file (let* ((file (directory-file-name file))
                   (text (pcase n
                           (`- (file-name-directory file))
                           (`0 (file-name-nondirectory file))
                           (_ file))))
              (easy-kill-adjust-candidate 'buffer-file-name text))))))

;;; Handler for `defun-name'.

(defun easy-kill-on-defun-name (_n)
  "Get current defun name."
  (if easy-kill-mark
      (easy-kill-echo "Not supported in `easy-mark'")
    (pcase (add-log-current-defun)
      (`nil (easy-kill-echo "No `defun-name' at point"))
      (name (easy-kill-adjust-candidate 'defun-name name)))))

;;; Handler for `url'.

(defun easy-kill-on-url (&optional _n)
  "Get url at point or from char properties.
Char properties `help-echo', `shr-url' and `w3m-href-anchor' are
inspected."
  (if (or easy-kill-mark (bounds-of-thing-at-point 'url))
      (easy-kill-thing 'url nil t)
    (cl-labels ((get-url (text)
                         (when (stringp text)
                           (with-temp-buffer
                             (insert text)
                             (pcase (bounds-of-thing-at-point 'url)
                               (`(,beg . ,end) (buffer-substring beg end)))))))
      (cl-dolist (p '(help-echo shr-url w3m-href-anchor))
        (pcase (get-char-property-and-overlay (point) p)
          (`(,text . ,ov)
           (pcase (or (get-url text)
                      (get-url (and ov (overlay-get ov p))))
             ((and url (guard url))
              (easy-kill-adjust-candidate 'url url)
              (cl-return url)))))))))

;;; Handler for `sexp' and `list'.

(defvar up-list-fn)                     ; Dynamically bound

(defun easy-kill-backward-up ()
  (let ((ppss (syntax-ppss)))
    (condition-case nil
        (progn
          (funcall (or (bound-and-true-p up-list-fn) #'up-list) -1)
          ;; `up-list' may jump to another string.
          (when (and (nth 3 ppss) (< (point) (nth 8 ppss)))
            (goto-char (nth 8 ppss))))
      (scan-error (and (nth 3 ppss) (goto-char (nth 8 ppss)))))))

(defun easy-kill-forward-down (point &optional bound)
  (condition-case nil
      (progn
        (easy-kill-backward-up)
        (backward-prefix-chars)
        (if (and (or (not bound) (> (point) bound))
                 (/= point (point)))
            (easy-kill-forward-down (point) bound)
          (goto-char point)))
    (scan-error (goto-char point))))

(defun easy-kill-bounds-of-list (n)
  (save-excursion
    (pcase n
      (`+ (goto-char (easy-kill-get start))
          (easy-kill-backward-up))
      (`- (easy-kill-forward-down (point) (easy-kill-get start)))
      (_ (error "Unsupported argument `%s'" n)))
    (bounds-of-thing-at-point 'sexp)))

(defun easy-kill-on-list (n)
  (pcase n
    ((or `+ `-)
     (pcase (easy-kill-bounds-of-list n)
       (`(,beg . ,end)
        (easy-kill-adjust-candidate 'list beg end))))
    (_ (easy-kill-thing 'list n t))))

(defun easy-kill-on-sexp (n)
  (pcase n
    ((or `+ `-)
     (unwind-protect (easy-kill-thing 'list n)
       (setf (easy-kill-get thing) 'sexp)))
    (_ (easy-kill-thing 'sexp n t))))

;;; nxml support for list-wise +/-

(defvar nxml-sexp-element-flag)

(defun easy-kill-on-list:nxml (n)
  (let ((nxml-sexp-element-flag t)
        (up-list-fn 'nxml-up-element))
    (cond
     ((memq n '(+ -))
      (pcase (easy-kill-bounds-of-list n)
        (`(,beg . ,end) (easy-kill-adjust-candidate 'list beg end))))
     ((eq 'list (easy-kill-get thing))
      (let ((new-end (save-excursion
                       (goto-char (easy-kill-get end))
                       (forward-sexp n)
                       (point))))
        (when (and new-end (/= new-end (easy-kill-get end)))
          (easy-kill-adjust-candidate 'list nil new-end))))
     (t (save-excursion
          (ignore-errors (easy-kill-backward-up))
          (easy-kill-thing 'sexp n t)
          (setf (easy-kill-get thing) 'list))))))

;;; js2 support for list-wise +/-

(defun easy-kill-find-js2-node (beg end &optional inner)
  (eval-and-compile (require 'js2-mode nil t))
  (let* ((node (js2-node-at-point))
         (last-node node))
    (while (progn
             (if (or (js2-ast-root-p node)
                     (and (<= (js2-node-abs-pos node) beg)
                          (>= (js2-node-abs-end node) end)
                          (or inner
                              (not (and (= (js2-node-abs-pos node) beg)
                                        (= (js2-node-abs-end node) end))))))
                 nil
               (setq last-node node
                     node (js2-node-parent node))
               t)))
    (if inner last-node node)))

(defun easy-kill-on-list:js2 (n)
  (let ((node (pcase n
                ((or `+ `-)
                 (easy-kill-find-js2-node (easy-kill-get start)
                                          (easy-kill-get end)
                                          (eq n '-)))
                ((guard (eq 'list (easy-kill-get thing)))
                 (error "List forward not supported in js2-mode"))
                (_ (js2-node-at-point)))))
    (easy-kill-adjust-candidate 'list
                                (js2-node-abs-pos node)
                                (js2-node-abs-end node))
    (setf (easy-kill-get describe-thing)
          ;; Also used by `sexp' so delay computation until needed.
          (lambda ()
            (format "%s (%s)" (easy-kill-get thing) (js2-node-short-name node))))
    (easy-kill-echo "%s" (js2-node-short-name node))))

;;;; ChangeLog:

;; 2014-04-13  Leo Liu  <sdl.web@gmail.com>
;; 
;; 	Merge branch 'master' of https://github.com/leoliu/easy-kill
;; 
;; 2014-04-05  Leo Liu  <sdl.web@gmail.com>
;; 
;; 	Merge easy-kill as packages/easy-kill
;; 


(provide 'easy-kill)
;;; easy-kill.el ends here
