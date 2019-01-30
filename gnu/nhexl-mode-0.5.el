;;; nhexl-mode.el --- Minor mode to edit files via hex-dump format  -*- lexical-binding: t -*-

;; Copyright (C) 2010, 2012, 2016, 2018  Free Software Foundation, Inc.

;; Author: Stefan Monnier <monnier@iro.umontreal.ca>
;; Keywords: data
;; Version: 0.5
;; Package-Requires: ((emacs "24") (cl-lib "0.5"))

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

;; This package implements NHexl mode, a minor mode for editing files
;; in hex dump format.  The mode command is called `nhexl-mode'.
;;
;; This minor mode implements similar functionality to `hexl-mode',
;; but using a different implementation technique, which makes it
;; usable as a "plain" minor mode.  It works on any buffer, and does
;; not mess with the undo log or with the major mode.
;;
;; In theory it could also work just fine even on very large buffers,
;; although in practice it seems to make the display engine suffer.
;;
;; It also comes with:
;;
;; - `nhexl-nibble-edit-mode': a "nibble editor" minor mode.
;;   where the cursor pretends to advance by nibbles (4-bit) and the
;;   self-insertion keys (which only work for hex-digits) will only modify the
;;   nibble under point.
;;
;; - `nhexl-overwrite-only-mode': a minor mode to try and avoid moving text.
;;   In this minor mode, not only self-inserting keys overwrite existing
;;   text, but commands like `yank' and `kill-region' as well.

;;; Todo:
;; - Clicks on the hex side should put point at the right place.

;;; Code:

(eval-when-compile (require 'cl-lib))
(require 'hexl)                         ;For faces.

(defgroup nhexl nil
  "Edit a file in a hex dump format."
  :group 'data)

(defcustom nhexl-line-width 16
  "Number of bytes per line."
  :type 'integer)

(defcustom nhexl-display-unprintables nil
  "If non-nil, display non-printable chars using the customary codes.
If nil, use just `.' for those chars instead of things like `\\NNN' or `^C'."
  :type 'boolean)

(defvar nhexl--display-table
  (let ((dt (make-display-table)))
    (unless nhexl-display-unprintables
      (dotimes (i 128)
        (when (> (char-width i) 1)
          (setf (aref dt i) [?.])))
      (dotimes (i 128)
        (setf (aref dt (unibyte-char-to-multibyte (+ i 128))) [?.])))
    ;; (aset dt ?\n [?␊])
    (aset dt ?\t [?␉])
    dt))

(defvar nhexl--saved-vars nil)
(make-variable-buffer-local 'nhexl--saved-vars)
(defvar nhexl--point nil)
(make-variable-buffer-local 'nhexl--point)

;;;; Nibble editing minor mode

(defvar nhexl-nibble-edit-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map [remap self-insert-command] #'nhexl-nibble-self-insert)
    (define-key map [remap right-char] #'nhexl-nibble-forward)
    (define-key map [remap forward-char] #'nhexl-nibble-forward)
    (define-key map [remap left-char] #'nhexl-nibble-backward)
    (define-key map [remap backward-char] #'nhexl-nibble-backward)
    map))

(define-minor-mode nhexl-nibble-edit-mode
  "Minor mode to edit the hex nibbles in `nhexl-mode'."
  :global nil
  (if nhexl-nibble-edit-mode
      (setq-local cursor-type 'hbar)
    (kill-local-variable 'cursor-type))
  (nhexl--refresh-cursor))

(defvar-local nhexl--nibble nil)

(defun nhexl--nibble (&optional pos)
  (or (and (eq (or pos (point)) (nth 1 nhexl--nibble))
           (eq (buffer-chars-modified-tick) (nth 2 nhexl--nibble))
           (nth 0 nhexl--nibble))
      (progn
        (setq nhexl--nibble nil)
        0)))

(defun nhexl--nibble-set (n)
  (setq nhexl--nibble (list n (point) (buffer-chars-modified-tick))))

(defun nhexl--refresh-cursor (&optional pos)
  (unless pos (setq pos (point)))
  (let* ((zero (save-restriction (widen) (point-min)))
         (n (truncate (- pos zero) nhexl-line-width))
         (from (max (point-min) (+ zero (* n nhexl-line-width))))
         (to (min (point-max) (+ zero (* (1+ n) nhexl-line-width)))))
    (with-silent-modifications
      (put-text-property from to 'fontified nil))))

(defun nhexl--nibble-max (&optional char)
  (unless char (setq char (following-char)))
  (if (< char 256) 1
    (let ((i 1))
      (setq char (/ char 256))
      (while (> char 0)
        (setq char (/ char 16))
        (setq i (1+ i)))
      i)))

(defun nhexl-nibble-forward ()
  "Advance by one nibble."
  (interactive)
  (let ((nib (nhexl--nibble)))
    (if (>= nib (nhexl--nibble-max))
        (forward-char 1)
      (nhexl--nibble-set (1+ nib))
      (nhexl--refresh-cursor))))

(defun nhexl-nibble-backward ()
  "Advance by one nibble."
  (interactive)
  (let ((nib (nhexl--nibble)))
    (if (> nib 0)
        (progn
          (nhexl--nibble-set (1- nib))
          (nhexl--refresh-cursor))
      (backward-char 1)
      (nhexl--nibble-set (nhexl--nibble-max)))))

(defun nhexl-nibble-self-insert ()
  "Overwrite current nibble with the hex character you type."
  (interactive)
  (let* ((max (nhexl--nibble-max))
         (nib (min max (nhexl--nibble)))
         (char (following-char))
         (hex (format "%02x" char))
         (nhex (concat (substring hex 0 nib)
                       (string last-command-event)
                       (substring hex (1+ nib))))
         (nchar (string-to-number nhex 16)))
    (insert nchar)
    (unless (eobp) (delete-char 1))
    (if (= max nib) nil
      (backward-char 1)
      (nhexl--nibble-set (1+ nib)))))

;;;; No insertion/deletion minor mode

(defvar nhexl-overwrite-clear-byte ?\000
  "Byte to use to replace deleted content.")

(defvar nhexl-overwrite-only-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map [remap yank] #'nhexl-overwrite-yank)
    (define-key map [remap yank-pop] #'nhexl-overwrite-yank-pop)
    (define-key map [remap kill-region] #'nhexl-overwrite-kill-region)
    (define-key map [remap delete-char] #'nhexl-overwrite-delete-char)
    (define-key map [remap backward-delete-char-untabify]
      #'nhexl-overwrite-backward-delete-char)
    map))

(defun nhexl-overwrite-backward-delete-char (&optional arg)
  "Delete ARG chars backward by overwriting them.
Uses `nhexl-overwrite-clear-byte'."
  (interactive "p")
  (unless arg (setq arg 1))
  (if (< arg 0)
      (nhexl-overwrite-delete-char (- arg))
    (forward-char (- arg))
    (save-excursion
      (insert-char nhexl-overwrite-clear-byte arg)
      (delete-char arg))))

(defun nhexl-overwrite-delete-char (&optional arg)
  "Delete ARG chars forward by overwriting them.
Uses `nhexl-overwrite-clear-byte'."
  (interactive "p")
  (unless arg (setq arg 1))
  (if (< arg 0)
      (nhexl-overwrite-backward-delete-char (- arg))
    (insert-char nhexl-overwrite-clear-byte arg)
    (delete-char arg)))

(defun nhexl-overwrite-kill-region (beg end &optional region)
  "Kill the region, replacing it with `nhexl-overwrite-clear-byte'."
  (interactive (list (mark) (point) 'region))
  (copy-region-as-kill beg end region)
  (barf-if-buffer-read-only)
  (pcase-dolist (`(,beg . ,end)
                 (if region (funcall region-extract-function 'bounds)
                   (list beg end)))
    (goto-char beg)
    (nhexl-overwrite-delete-char (- end beg))))

(defun nhexl-overwrite--yank-wrapper (fun)
  ;; FIXME? doesn't work when yanking things like rectangles.
  (let ((orig-size (buffer-size)))
    (funcall fun)
    (let* ((inserted (- (buffer-size) orig-size))
           (deleted (delete-and-extract-region
                     (point)
                     (min (point-max) (+ (point) inserted)))))
      (unless yank-undo-function
        (setq yank-undo-function #'delete-region))
      (add-function :before yank-undo-function
                    (lambda (_beg end)
                      (save-excursion
                        (goto-char end)
                        (insert deleted)))))))

(defun nhexl-overwrite-yank (&optional arg)
  "Like `yank' but overwriting existing text."
  (interactive "*P")
  (nhexl-overwrite--yank-wrapper (lambda () (yank arg))))

(defun nhexl-overwrite-yank-pop (&optional arg)
  "Like `yank-pop' but overwriting existing text."
  (interactive "*P")
  (nhexl-overwrite--yank-wrapper (lambda () (yank-pop arg))))

(defvar-local nhexl--overwrite-save-settings nil)

(define-minor-mode nhexl-overwrite-only-mode
  "Minor mode where text is only overwritten.
Insertion/deletion is avoided where possible and replaced by overwriting
existing text, if needed with `nhexl-overwrite-clear-byte'."
  :lighter nil
  (cond
   (nhexl-overwrite-only-mode
    (push (cons 'overwrite-mode overwrite-mode)
          nhexl--overwrite-save-settings)
    (setq-local overwrite-mode 'overwrite-mode-binary)
    (setq-local overwrite-mode-binary " OnlyOvwrt"))
   (t
    (pcase-dolist (`(,var . ,val)
                   (prog1 nhexl--overwrite-save-settings
                     (setq nhexl--overwrite-save-settings nil)))
      (set var val))
    (kill-local-variable 'overwrite-mode-binary))))

;;;; Main minor mode

(defvar nhexl-mode-map
  (let ((map (make-sparse-keymap)))
    ;; `next-line' and `previous-line' work correctly, but they take ages in
    ;; large buffers and allocate an insane amount of memory, so the GC is
    ;; constantly triggered.
    ;; So instead we just override them with our own custom-tailored functions
    ;; which don't have to work nearly as hard to figure out where's the
    ;; next line.
    ;; FIXME: It would also be good to try and improve `next-line' and
    ;; `previous-line' for this case, tho it is pretty pathological for them.
    (define-key map [remap next-line] #'nhexl-next-line)
    (define-key map [remap previous-line] #'nhexl-previous-line)
    ;; Just as for line movement, scrolling movement could/should work as-is
    ;; but benefit from an ad-hoc implementation.
    (define-key map [remap scroll-up-command] #'nhexl-scroll-up)
    (define-key map [remap scroll-down-command] #'nhexl-scroll-down)
    ;; FIXME: Find a key binding for nhexl-nibble-edit-mode!
    map))

;;;###autoload
(define-minor-mode nhexl-mode
  "Minor mode to edit files via hex-dump format"
  :lighter (" NHexl" (nhexl-nibble-edit-mode "/ne"))
  (if (not nhexl-mode)
      (progn
        (dolist (varl nhexl--saved-vars)
          (set (make-local-variable (car varl)) (cdr varl)))
        (kill-local-variable 'nhexl--saved-vars)
        (jit-lock-unregister #'nhexl--jit)
        (remove-hook 'after-change-functions #'nhexl--change-function 'local)
        (remove-hook 'post-command-hook #'nhexl--post-command 'local)
        ;; FIXME: This will conflict with any other use of `display'.
        (with-silent-modifications
          (put-text-property (point-min) (point-max) 'display nil))
        (remove-overlays (point-min) (point-max) 'nhexl t))
    (when (and enable-multibyte-characters
               (not (save-excursion
                      (save-restriction
                        (widen)
                        (goto-char (point-min))
                        (re-search-forward "[^[:ascii:]\200-\377]" nil t))))
               ;; We're in a multibyte buffer which only contains bytes,
               ;; so we could advantageously convert it to unibyte.
               (y-or-n-p "Make buffer unibyte? "))
      (set-buffer-multibyte nil))
                   
    (unless (local-variable-p 'nhexl--saved-vars)
      (dolist (var '(buffer-display-table buffer-invisibility-spec
                     overwrite-mode header-line-format))
        (push (cons var (symbol-value var)) nhexl--saved-vars)))
    (setq nhexl--point (point))
    (setq header-line-format '(:eval (nhexl--header-line)))
    (binary-overwrite-mode 1)
    (setq buffer-invisibility-spec ())
    (set (make-local-variable 'buffer-display-table) nhexl--display-table)
    (jit-lock-register #'nhexl--jit)
    (add-hook 'change-major-mode-hook (lambda () (nhexl-mode -1)) nil 'local)
    (add-hook 'post-command-hook #'nhexl--post-command nil 'local)
    (add-hook 'after-change-functions #'nhexl--change-function nil 'local)))

(defun nhexl-next-line (&optional arg)
  "Move cursor vertically down ARG lines."
  (interactive "p")
  (unless arg (setq arg 1))
  (if (< arg 0)
      (nhexl-previous-line (- arg))
    (let ((nib (nhexl--nibble)))
      (forward-char (* arg nhexl-line-width))
      (nhexl--nibble-set nib))))

(defun nhexl-previous-line (&optional arg)
  "Move cursor vertically up ARG lines."
  (interactive "p")
  (unless arg (setq arg 1))
  (if (< arg 0)
      (nhexl-next-line (- arg))
    (let ((nib (nhexl--nibble)))
      (backward-char (* arg nhexl-line-width))
      (nhexl--nibble-set nib))))

(defun nhexl-scroll-down (&optional arg)
  "Scroll text of selected window down ARG lines; or near full screen if no ARG."
  (interactive "P")
  (unless arg
    ;; Magic extra 2 lines: 1 line to account for the header-line, and a second
    ;; to account for the extra empty line that somehow ends up being there
    ;; pretty much all the time right below the header-line :-(
    (setq arg (max 1 (- (window-text-height) next-screen-context-lines 2))))
  (cond
   ((< arg 0) (nhexl-scroll-up (- arg)))
   ((eq arg '-) (nhexl-scroll-up nil))
   ((bobp) (scroll-down arg))			; signal error
   (t
    (let* ((ws (window-start))
           (nws (- ws (* nhexl-line-width arg))))
      (if (eq ws (point-min))
          (if scroll-error-top-bottom
              (nhexl-previous-line arg)
            (scroll-down arg))
        (nhexl-previous-line arg)
        (set-window-start nil (max (point-min) nws)))))))

(defun nhexl-scroll-up (&optional arg)
  "Scroll text of selected window up ARG lines; or near full screen if no ARG."
  (interactive "P")
  (unless arg
    ;; Magic extra 2 lines: 1 line to account for the header-line, and a second
    ;; to account for the extra empty line that somehow ends up being there
    ;; pretty much all the time right below the header-line :-(
    (setq arg (max 1 (- (window-text-height) next-screen-context-lines 2))))
  (cond
   ((< arg 0) (nhexl-scroll-down (- arg)))
   ((eq arg '-) (nhexl-scroll-down nil))
   ((eobp) (scroll-up arg))			; signal error
   (t
    (let* ((ws (window-start))
           (nws (+ ws (* nhexl-line-width arg))))
      (if (pos-visible-in-window-p (point-max))
          (if scroll-error-top-bottom
              (nhexl-next-line arg)
            (scroll-up arg))
        (nhexl-next-line arg)
        (set-window-start nil (min (point-max) nws)))))))

(defun nhexl--change-function (beg end len)
  ;; Round modifications up-to the hexl-line length since nhexl--jit will need
  ;; to modify the overlay that covers that text.
  (let* ((zero (save-restriction (widen) (point-min)))
         (from (max (point-min)
                    (+ zero (* (truncate (- beg zero) nhexl-line-width)
                               nhexl-line-width))))
         (to (min (point-max)
                  (+ zero (* (ceiling (- end zero) nhexl-line-width)
                             nhexl-line-width)))))
    (with-silent-modifications    ;Don't store this change in buffer-undo-list!
      (put-text-property from to 'fontified nil)))
  ;; Also make sure the tail's addresses are refreshed when
  ;; text is inserted/removed.
  (when (/= len (- end beg))
    (with-silent-modifications    ;Don't store this change in buffer-undo-list!
      (put-text-property beg (point-max) 'fontified nil))))

(defvar nhexl--overlay-counter 100)
(make-variable-buffer-local 'nhexl--overlay-counter)

(defun nhexl--debug-count-ols ()
  (let ((i 0))
    (dolist (ol (overlays-in (point-min) (point-max)))
      (when (overlay-get ol 'nhexl) (cl-incf i)))
    i))

(defun nhexl--flush-overlays (buffer)
  (with-current-buffer buffer
    (kill-local-variable 'nhexl--overlay-counter)
    ;; We've created many overlays in this buffer, which can slow
    ;; down operations significantly.  Let's flush them.
    ;; An easy way to flush them is
    ;;   (remove-overlays min max 'nhexl t)
    ;;   (put-text-property min max 'fontified nil)
    ;; but if the visible part of the buffer requires more than
    ;; nhexl--overlay-counter overlays, then we'll inf-loop.
    ;; So let's be more careful about removing overlays.
    (let ((windows (get-buffer-window-list nil nil t))
          (start (point-min))
          (zero (save-restriction (widen) (point-min)))
          (debug-count (nhexl--debug-count-ols)))
      (with-silent-modifications
        (while (< start (point-max))
          (let ((end (point-max)))
            (dolist (window windows)
              (cond
               ((< start (1- (window-start window)))
                (setq end (min (1- (window-start window)) end)))
               ((< start (1+ (window-end window)))
                (setq start (1+ (window-end window))))))
            ;; Round to multiple of nhexl-line-width.
            (setq start (+ zero (* (ceiling (- start zero) nhexl-line-width)
                                   nhexl-line-width)))
            (setq end (+ zero (* (truncate (- end zero) nhexl-line-width)
                                 nhexl-line-width)))
            (when (< start end)
              (remove-overlays start end 'nhexl t)
              (put-text-property start end 'fontified nil)
              (setq start (+ end nhexl-line-width))))))
      (let ((debug-new-count (nhexl--debug-count-ols)))
        (message "Flushed %d overlays, %d remaining"
                 (- debug-count debug-new-count) debug-new-count)))))

(defun nhexl--make-line (from next zero)
  (let* ((nextpos (min next (point-max)))
         (bufstr (buffer-substring from nextpos))
         (i -1)
         (s (concat
             (unless (eq zero from) "\n")
             (format (propertize "%08x:" 'face
                                 (if (or (< nhexl--point from)
                                         (>= nhexl--point next))
                                     'hexl-address-region
                                   '(highlight hexl-address-region)))
                     (- from zero))
             (propertize " " 'display '(space :align-to 12))
             (mapconcat (lambda (c)
                          (setq i (1+ i))
                          ;; FIXME: In multibyte buffers,
                          ;; do something clever about
                          ;; non-ascii chars.
                          (let ((s (format "%02x" c)))
                            (when (eq nhexl--point (+ from i))
                              (if nhexl-nibble-edit-mode
                                  (let ((nib (min (nhexl--nibble nhexl--point)
                                                  (1- (length s)))))
                                    (put-text-property nib (1+ nib)
                                                       'face 'highlight
                                                       s))
                                (put-text-property 0 (length s)
                                                   'face 'highlight
                                                   s)))
                            (if (zerop (mod i 2))
                                s (concat s " "))))
                        bufstr
                        "")
             (if (> next nextpos)
                 (make-string (+ (/ (1+ (- next nextpos)) 2)
                                 (* (- next nextpos) 2))
                              ?\s))
             (propertize "  " 'display
                         `(space :align-to
                                 ,(+ (/ (* nhexl-line-width 5) 2)
                                     12 3))))))
    (font-lock-append-text-property 0 (length s) 'face 'default s)
    s))

(defun nhexl--jit (from to)
  (let ((zero (save-restriction (widen) (point-min))))
    (setq from (max (point-min)
                    (+ zero (* (truncate (- from zero) nhexl-line-width)
                               nhexl-line-width))))
    (setq to (min (point-max)
                  (+ zero (* (ceiling (- to zero) nhexl-line-width)
                             nhexl-line-width))))
    (remove-overlays from to 'nhexl t)
    (remove-text-properties from to '(display))
    (save-excursion
      (goto-char from)
      (while (search-forward "\n" to t)
        (put-text-property (match-beginning 0) (match-end 0)
                           'display (copy-sequence "␊"))))
    (while (< from to)

      (cl-decf nhexl--overlay-counter)
      (when (and (= nhexl--overlay-counter 0)
                 ;; If the user enabled jit-lock-stealth fontification, then
                 ;; removing overlays is just a waste since
                 ;; jit-lock-stealth will restore them anyway.
                 (not jit-lock-stealth-time))
        ;; (run-with-idle-timer 0 nil 'nhexl--flush-overlays (current-buffer))
        )
      
      (let* ((next (+ from nhexl-line-width))
             (ol (make-overlay from next))
             (s (nhexl--make-line from next zero)))
        (overlay-put ol 'nhexl t)
        (overlay-put ol 'face 'hexl-ascii-region)
        (overlay-put ol 'before-string s)
        (setq from next)))))

(defun nhexl--header-line ()
  ;; FIXME: merge with nhexl--make-line.
  ;; FIXME: Memoize last line to avoid recomputation!
  (let* ((zero (save-restriction (widen) (point-min)))
         (text
          (let ((tmp ()))
            (dotimes (i nhexl-line-width)
              (push (if (< i 10) (+ i ?0) (+ i -10 ?a)) tmp))
            (apply 'string (nreverse tmp))))
         (pos (mod (- nhexl--point zero) nhexl-line-width))
         (i -1))
    (put-text-property pos (1+ pos) 'face 'highlight text)
    (concat
     (propertize " " 'display '(space :align-to 0))
     "Address:"
     (propertize " " 'display '(space :align-to 12))
     (mapconcat (lambda (c)
                  (setq i (1+ i))
                  (let ((s (string c c)))
                    (when (eq i pos)
                      (if nhexl-nibble-edit-mode
                          (let ((nib (min (nhexl--nibble nhexl--point)
                                          (1- (length s)))))
                            (put-text-property nib (1+ nib)
                                               'face 'highlight
                                               s))
                        (put-text-property 0 (length s)
                                           'face 'highlight
                                           s)))
                    (if (zerop (mod i 2)) s
                      (concat
                       s (propertize " " 'display
                                     `(space :align-to
                                             ,(+ (/ (* i 5) 2) 12 3)))))))
                text
                "")
     (propertize "  " 'display
                 `(space :align-to
                         ,(+ (/ (* nhexl-line-width 5) 2)
                             12 3)))
     text)))
  

(defun nhexl--post-command ()
  (when (/= (point) nhexl--point)
    (let ((zero (save-restriction (widen) (point-min)))
          (oldpoint nhexl--point))
      (setq nhexl--point (point))
      (nhexl--refresh-cursor)
      ;; (nhexl--jit (point) (1+ (point)))
      (if (/= (truncate (- (point) zero) nhexl-line-width)
              (truncate (- oldpoint zero) nhexl-line-width))
          (nhexl--refresh-cursor oldpoint)))))

;;;; ChangeLog:

;; 2018-04-16  Stefan Monnier  <monnier@iro.umontreal.ca>
;; 
;; 	* nhexl-mode.el: Hide undisplayable chars by default
;; 
;; 	(nhexl-line-width): Make it a defcustom.
;; 	(nhexl-display-unprintables): New defcustom.
;; 	(nhexl--display-table): Avoid \NNN by default.
;; 	(nhexl-mode): Suggest converting to unibyte when applicable.
;; 	(nhexl-scroll-down, nhexl-scroll-up): New commands.
;; 	(nhexl-mode-map): Use them.
;; 
;; 2018-04-15  Stefan Monnier  <monnier@iro.umontreal.ca>
;; 
;; 	* nhexl-mode.el: Bump version number for new release
;; 
;; 2018-04-15  Stefan Monnier  <monnier@iro.umontreal.ca>
;; 
;; 	* nhexl-mode.el (nhexl-overwrite-only-mode): New minor mode.
;; 
;; 2018-04-12  Stefan Monnier  <monnier@iro.umontreal.ca>
;; 
;; 	* nhexl-mode.el: Add our own line-movement functions
;; 
;; 	(nhexl-mode-map): New keymap.
;; 	(nhexl-next-line, nhexl-previous-line): New commands.
;; 	(nhexl-nibble-next-line, nhexl-nibble-previous-line): Remove.
;; 
;; 2018-04-12  Stefan Monnier  <monnier@iro.umontreal.ca>
;; 
;; 	* nhexl-mode.el (nhexl-nibble-edit-mode): New minor mode
;; 
;; 2016-08-08  Stefan Monnier  <monnier@iro.umontreal.ca>
;; 
;; 	* nhexl-mode.el: Use cl-lib
;; 
;; 2012-03-25  Chong Yidong  <cyd@gnu.org>
;; 
;; 	nhexl-mode.el: Fix last change.
;; 
;; 2012-03-24  Chong Yidong  <cyd@gnu.org>
;; 
;; 	Commentary tweaks for csv-mode, ioccur, and nhexl-mode packages.
;; 
;; 2012-03-20  Stefan Monnier  <monnier@iro.umontreal.ca>
;; 
;; 	Add nhexl-mode.
;; 

  

(provide 'nhexl-mode)
;;; nhexl-mode.el ends here
