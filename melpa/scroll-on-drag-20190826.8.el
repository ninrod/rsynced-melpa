;;; scroll-on-drag.el --- Interactive scrolling. -*- lexical-binding: t -*-

;; Copyright (C) 2019  Campbell Barton

;; Author: Campbell Barton <ideasman42@gmail.com>

;; URL: https://github.com/ideasman42/emacs-scroll-on-drag
;; Package-Version: 20190826.8
;; Version: 0.1
;; Package-Requires: ((emacs "26.2"))

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <https://www.gnu.org/licenses/>.

;;; Commentary:

;; Interactive scrolling which can be cancelled by pressing escape.

;;; Usage

;; (scroll-on-drag) ; Interactively scroll the current buffer
;;

;;; Code:

(defcustom scroll-on-drag-style 'line-by-pixel
  "The method of scrolling."
  :group 'scroll-on-drag
  :type
  '
  (choice
    (const :tag "Line" line)
    (const :tag "Line-By-Pixel" line-by-pixel)))

(defcustom scroll-on-drag-delay 0.01
  "Idle time between scroll updates."
  :group 'scroll-on-drag
  :type  'float)

(defcustom scroll-on-drag-motion-scale 0.25
  "Scroll speed multiplier."
  :group 'scroll-on-drag
  :type  'float)

(defcustom scroll-on-drag-motion-accelerate 0.3
  "Non-linear scroll power (0.0 for linear speed, 1.0 for very fast acceleration)."
  :group 'scroll-on-drag
  :type  'float)

(defcustom scroll-on-drag-smooth t
  "Use smooth (pixel) scrolling."
  :group 'scroll-on-drag
  :type  'boolean)

(defcustom scroll-on-drag-pre-hook nil
  "List of functions to be called when scroll-on-drag starts."
  :group 'scroll-on-drag
  :type 'hook)

(defcustom scroll-on-drag-post-hook nil
  "List of functions to be called when scroll-on-drag finishes."
  :group 'scroll-on-drag
  :type 'hook)

(defcustom scroll-on-drag-redisplay-hook nil
  "List of functions to run on scroll redraw."
  :group 'scroll-on-drag
  :type 'hook)


;; Generic scrolling functions.
;;
;; It would be nice if this were part of a more general library.
;; Optionally also move the point is needed because _not_ doing this
;; makes the window constraint so the point stays within it.

;; Per-line Scroll.
;; return remainder of lines to scroll (matching forward-line).
(defun scroll-on-drag--scroll-by-lines (window lines also-move-point)
  "Line based scroll that optionally move the point.
Argument WINDOW The window to scroll.
Argument LINES The number of lines to scroll (signed).
Argument ALSO-MOVE-POINT When non-nil, move the POINT as well."
  (let ((lines-remainder 0))
    (when also-move-point
      (let ((lines-point-remainder (forward-line lines)))
        (unless (zerop lines-point-remainder)
          (setq lines (- lines lines-point-remainder)))))
    (unless (zerop lines)
      (set-window-start
        window
        (save-excursion
          (goto-char (window-start))
          (setq lines-remainder (forward-line lines))
          (point))
        t)
      (when also-move-point
        (unless (zerop lines-remainder)
          (forward-line (- lines-remainder)))))
    lines-remainder))

;; Per-pixel Scroll,
;; return remainder of lines to scroll (matching forward-line).
(defun scroll-on-drag--scroll-by-pixels (window char-height delta-px also-move-point)
  "Line based scroll that optionally move the point.
Argument WINDOW The window to scroll.
Argument CHAR-HEIGHT The result of `frame-char-height'.
Argument DELTA-PX The number of pixels to scroll (signed).
Argument ALSO-MOVE-POINT When non-nil, move the POINT as well."
  (cond
    ((< delta-px 0)
      (let*
        (
          (scroll-px-prev (- char-height (window-vscroll nil t))) ;; flip.
          (scroll-px-next (+ scroll-px-prev (- delta-px))) ;; flip.
          (lines (/ scroll-px-next char-height))
          (scroll-px (- scroll-px-next (* lines char-height)))
          (lines-remainder 0))
        (unless (zerop lines)
          (setq lines-remainder (- (scroll-on-drag--scroll-by-lines window (- lines) also-move-point))) ;; flip
          (unless (zerop lines-remainder)
            (setq scroll-px char-height)))
        (set-window-vscroll window (- char-height scroll-px) t)
        (- lines-remainder)))
    ((> delta-px 0)
      (let*
        (
          (scroll-px-prev (window-vscroll nil t))
          (scroll-px-next (+ scroll-px-prev delta-px))
          (lines (/ scroll-px-next char-height))
          (scroll-px (- scroll-px-next (* lines char-height)))
          (lines-remainder 0))
        (unless (zerop lines)
          (setq lines-remainder (scroll-on-drag--scroll-by-lines window lines also-move-point))
          (unless (zerop lines-remainder)
            (setq scroll-px char-height)))
        (set-window-vscroll window scroll-px t)
        lines-remainder))
    ;; no lines scrolled.
    (t 0)))

;; End generic scrolling functions.

;;;###autoload
(defun scroll-on-drag ()
  "Interactively scroll (typically on click event).
Returns true when scrolling took place, otherwise nil."
  (interactive)
  (let*
    (
      ;; Don't run unnecessary logic when scrolling.
      (inhibit-point-motion-hooks t)
      ;; Only draw explicitly once all actions have been done.
      (inhibit-redisplay t)

      ;; Variables for re-use.
      (this-window (selected-window))
      (this-frame-char-height (frame-char-height))
      (this-frame-char-height-as-float (float this-frame-char-height))

      ;; Reset's when pressing Escape.
      (has-scrolled nil)
      ;; Doesn't reset (so we can detect clicks).
      (has-scrolled-real nil)

      (scroll-timer nil)

      ;; Cursor offset.
      (delta 0)
      (delta-prev 0)

      ;; Only for 'line-by-pixel' style.
      (delta-px-accum 0)

      ;; Restoration position.
      (restore-window-start (window-start))
      (restore-point (point))
      (restore-point-use-scroll-offset nil)

      ;; X11 cursor.
      (restore-x-pointer-shape (and (boundp 'x-pointer-shape) x-pointer-shape))

      ;; Restore indent (lost when scrolling).
      (restore-indent (- (point) (save-excursion (back-to-indentation) (point))))

      (mouse-y-fn
        (cond
          ((eq scroll-on-drag-style 'line)
            (lambda () (cdr (cdr (mouse-position)))))
          (t
            (lambda () (cdr (cdr (mouse-pixel-position)))))))

      ;; Reference to compare all mouse motion to.
      (y-init (funcall mouse-y-fn))

      (point-of-last-line
        (if scroll-on-drag-smooth
          (save-excursion
            (goto-char (point-max))
            (move-beginning-of-line nil)
            (point))
          0))

      (mouse-y-delta-scale-fn
        ;; '(f * motion-scale) ^ power', then truncate to int.
        (lambda (delta)
          (let*
            (
              (f (/ (float delta) this-frame-char-height-as-float))
              (f-abs (abs f)))
            (truncate
              (copysign
                ;; Clamp so converting to int won't fail.
                (min
                  1e+18
                  (*
                    (expt
                      (* f-abs scroll-on-drag-motion-scale)
                      (+ 1.0 (* f-abs scroll-on-drag-motion-accelerate)))
                    this-frame-char-height-as-float))
                  f)))))

      ;; Calls 'timer-update-fn'.
      (timer-start-fn
        (lambda (timer-update-fn)
          (setq scroll-timer
            (run-with-timer
              scroll-on-drag-delay
              nil
              #'(lambda () (funcall timer-update-fn timer-update-fn))))))

      ;; Stops calling 'timer-update-fn'.
      (timer-stop-fn
        (lambda ()
          (when scroll-timer
            (cancel-timer scroll-timer)
            (setq scroll-timer nil))))

      (timer-update-fn
        (cond

          ((eq scroll-on-drag-style 'line)
            ;; -------------
            ;; Style: "line"

            (lambda (self-fn)
              (let ((lines delta))
                (unless (zerop lines)
                  (setq delta-px-accum
                    (- delta-px-accum (* lines this-frame-char-height)))
                  (let ((lines-remainder (scroll-on-drag--scroll-by-lines this-window lines t)))
                    (unless (zerop (- lines lines-remainder))
                      (let ((inhibit-redisplay nil))
                        (run-hooks 'scroll-on-drag-redisplay-hook)
                        (redisplay))))))
              (funcall timer-start-fn self-fn)))

          ((eq scroll-on-drag-style 'line-by-pixel)
            ;; ----------------------
            ;; Style: "line-by-pixel"

            (lambda (self-fn)
              (let
                (
                  (do-draw nil)
                  (delta-scaled (funcall mouse-y-delta-scale-fn delta)))

                (if scroll-on-drag-smooth
                  ;; Smooth-Scrolling.
                  (let
                    (
                      (lines-remainder
                        (scroll-on-drag--scroll-by-pixels
                          this-window
                          this-frame-char-height
                          delta-scaled
                          t)))
                    (when (>= (point) point-of-last-line)
                      (set-window-vscroll this-window 0 t))
                    (setq do-draw t))

                  ;; Non-Smooth-Scrolling (snap to lines).
                  ;; Basically same logic as above, but only step over lines.
                  (progn
                    (setq delta-px-accum
                      (+ delta-scaled delta-px-accum))
                    (let ((lines (/ delta-px-accum this-frame-char-height)))

                      (unless (zerop lines)
                        (setq delta-px-accum
                          (- delta-px-accum (* lines this-frame-char-height)))
                        (let ((lines-remainder (scroll-on-drag--scroll-by-lines this-window lines t)))
                          (setq do-draw t))))))

                (when do-draw
                  (let
                    ((inhibit-redisplay nil))
                    (run-hooks 'scroll-on-drag-redisplay-hook)
                    (redisplay))))
              (funcall timer-start-fn self-fn)))))

      ;; Apply pixel offset and snap to a line.
      (scroll-snap-smooth-to-line-fn
        (lambda ()
          (when scroll-on-drag-smooth
            (when (> (window-vscroll this-window t) (/ this-frame-char-height 2))
              (scroll-on-drag--scroll-by-lines this-window 1 nil))
            (set-window-vscroll this-window 0 t)
            (setq delta-px-accum 0)
            (let
              ((inhibit-redisplay nil))
              (run-hooks 'scroll-on-drag-redisplay-hook)
              (redisplay)))))

      (scroll-reset-fn
        (lambda ()
          (funcall timer-stop-fn)
          (funcall scroll-snap-smooth-to-line-fn)
          (setq delta-prev 0)
          (setq y-init (funcall mouse-y-fn))))

      (scroll-restore-fn
        (lambda ()
          (goto-char restore-point)
          (set-window-start this-window restore-window-start t)))

      ;; Workaround for bad pixel scrolling performance
      ;; when the cursor is partially outside the view.
      (scroll-consrtain-point-below-window-start-fn
        (lambda ()
          (let
            (
              (lines-from-top
                (count-lines
                  (window-start)
                  (save-excursion (move-beginning-of-line nil) (point)))))
            (when (> scroll-margin lines-from-top)
              (forward-line (- scroll-margin lines-from-top))
              (let
                ((inhibit-redisplay nil))
                (run-hooks 'scroll-on-drag-redisplay-hook)
                (redisplay))
              (setq restore-point-use-scroll-offset t))))))

    ;; Set arrow cursor (avoids annoying flicker on scroll).
    (when (display-graphic-p)
      (setq x-pointer-shape x-pointer-top-left-arrow)
      (set-mouse-color nil))


    ;; ---------------
    ;; Main Event Loop

    (track-mouse
      (while
        (let ((event (read-event)))
          (cond
            ;; Escape restores initial state, restarts scrolling.
            ((eq event 'escape)
              (setq has-scrolled nil)
              (funcall scroll-reset-fn)
              (funcall scroll-restore-fn)
              (let ((inhibit-redisplay nil))
                (run-hooks 'scroll-on-drag-redisplay-hook)
                (redisplay))
              t)

            ;; Space keeps current position, restarts scrolling.
            ((eq event ?\s)
              (funcall scroll-reset-fn)
              t)
            ((mouse-movement-p event)
              (setq delta (- (funcall mouse-y-fn) y-init))
              (if (zerop delta)
                (funcall timer-stop-fn)
                (when (zerop delta-prev)
                  (unless has-scrolled
                    ;; Clamp point to scroll bounds on first scroll,
                    ;; allow pressing 'Esc' to use unclamped position.
                    (when scroll-on-drag-smooth
                      (funcall scroll-consrtain-point-below-window-start-fn))
                    (setq has-scrolled t))
                  (unless has-scrolled-real
                    (let
                      ((inhibit-redisplay nil))
                        (run-hooks 'scroll-on-drag-pre-hook)))
                  (setq has-scrolled-real t)
                  (funcall timer-stop-fn)
                  (funcall timer-update-fn timer-update-fn)))
              (setq delta-prev delta)
              t)
            ;; Cancel...
            (t nil)))))

    (funcall scroll-snap-smooth-to-line-fn)
    (funcall timer-stop-fn)

    ;; Restore state (the point may have been moved by constraining to the scroll margin).
    (when (eq restore-window-start (window-start))
      (funcall scroll-restore-fn)
      (setq has-scrolled nil))

    ;; Restore indent level if possible.
    (when (and has-scrolled (> restore-indent 0))
      (move-beginning-of-line nil)
      (right-char
        (min
          restore-indent
          (- (save-excursion (move-end-of-line nil) (point)) (point)))))

    ;; Restore pointer.
    (when (boundp 'x-pointer-shape)
      (setq x-pointer-shape restore-x-pointer-shape)
      (set-mouse-color nil))

    (when has-scrolled-real
      (let
        ((inhibit-redisplay nil))
          (run-hooks 'scroll-on-drag-post-hook)))

    ;; Result so we know if any scrolling occurred,
    ;; allowing a fallback action on 'click'.
    has-scrolled-real))

;;;###autoload
(defmacro scroll-on-drag-with-fallback (&rest body)
  "A macro to scroll and perform a different action on click.
Optional argument BODY Hello."
  `(lambda () (interactive) (unless (scroll-on-drag-internal) ,@body)))

(provide 'scroll-on-drag)

;;; scroll-on-drag.el ends here
