;;; ob-clojure-literate.el --- Clojure's Org-mode Literate Programming.

;; Authors: stardiviner <numbchild@gmail.com>
;; Package-Requires: ((emacs "24.4") (org "9") (cider "0.16.0") (dash "2.12.0"))
;; Package-Version: 20180111.210
;; Package-X-Original-Version: 1.1
;; Keywords: tools
;; homepage: https://github.com/stardiviner/ob-clojure-literate

;; You should have received a copy of the GNU General Public License
;; along with GNU Emacs.  If not, see <http://www.gnu.org/licenses/>.

;;; Commentary:
;;
;; Auto setup ob-clojure-literate scaffold and jack-in Clojure project.
;;
;; Usage:
;;
;; [M-x ob-clojure-literate-mode] to toggle this minor mode.

;;; Code:

(require 'ob-clojure)
(require 'cider)
(require 'dash)

(defgroup ob-clojure-literate nil
  "Clojure's Org-mode Literate Programming."
  :prefix "ob-clojure-literate-"
  :group 'ob-babel)

;;;###autoload
(defcustom ob-clojure-literate-auto-jackin-p nil
  "Auto jack in ob-clojure project.
Don't auto jack in by default for not rude."
  :type 'boolean
  :group 'ob-clojure-literate)

(defcustom ob-clojure-literate-project-location (concat user-emacs-directory "Org-mode/")
  "The location for `ob-clojure-literate' scaffold project."
  :type 'string
  :group 'ob-clojure-literate)

(defvar ob-clojure-literate-session nil)
(defvar ob-clojure-literate-original-ns nil)
(defvar ob-clojure-literate-session-ns nil)
(defvar ob-clojure-literate-cider-connections nil)

(defcustom ob-clojure-literate-default-session "*cider-repl ob-clojure*"
  "The default session name for `ob-clojure-literate'."
  :type 'string
  :group 'ob-clojure-literate)

(defun ob-clojure-literate-any-connection-p ()
  "Return t if have any CIDER connection."
  (and
   ;; handle the case `cider-jack-in' is not finished creating connection, but `ob-clojure-literate-mode' is enabled.
   (not (null (cider-connections)))
   (not (null ob-clojure-literate-session)) ; before mode enabled, it is nil.
   (not (string-empty-p ob-clojure-literate-session)) ; after disable, it is "".
   ))

(defun ob-clojure-literate-get-session-list ()
  "Return a list of available started CIDER REPL sessions list."
  (-map 'buffer-name cider-connections))

(defun ob-clojure-literate-set-session ()
  "Set session name for buffer local."
  ;; if default session is the only one in connections list.
  (if (and (= (length (ob-clojure-literate-get-session-list)) 1)
           (-contains-p (ob-clojure-literate-get-session-list) ob-clojure-literate-default-session))
      (setq-local ob-clojure-literate-session ob-clojure-literate-default-session)
    ;; if have any connections, choose one from them.
    (if (ob-clojure-literate-any-connection-p)
        (setq-local ob-clojure-literate-session
                    (completing-read "Choose ob-clojure-literate :session : "
                                     (ob-clojure-literate-get-session-list)))
      ;; if none, set to default session name to fix `ob-clojure-literate-mode'
      ;; is enabled before `cider-jack-in' generated connections.
      (setq-local ob-clojure-literate-session ob-clojure-literate-default-session))
    ))

;;;###autoload
(defun ob-clojure-literate-specify-session-header-argument ()
  "Specify ob-clojure header argument :session with value selected from a list of available sessions."
  (interactive)
  (let ((lang (nth 0 (org-babel-get-src-block-info))))
    (if (and (string= lang "clojure") ; only in clojure src block.
             (car (seq-filter ; only when :session is not specified yet.
                   (lambda (header-argument)
                     (if (eq (car header-argument) :session)
                         (not (null (cdr header-argument)))))
                   (nth 2 (org-babel-get-src-block-info)))))
        (org-babel-insert-header-arg
         "session"
         (format "\"%s\""
                 (completing-read
                  "Choose :session for ob-clojure-literate: "
                  (ob-clojure-literate-get-session-list))))
      (message "This function only used in `clojure' src block.")))
  )

;;; Auto start CIDER REPL session in a complete Leiningen project environment for Org-mode Babel to jack-in.
;;;###autoload
(defun ob-clojure-literate-auto-jackin ()
  "Auto setup ob-clojure-literate scaffold and jack-in Clojure project."
  (interactive)
  (unless (file-directory-p (expand-file-name ob-clojure-literate-project-location))
    (make-directory ob-clojure-literate-project-location t)
    (let ((default-directory ob-clojure-literate-project-location))
      (shell-command "lein new ob-clojure")))
  (unless (or
           (and (cider-connected-p)
                (if (not (null ob-clojure-literate-session))
                    (seq-contains cider-connections (get-buffer ob-clojure-literate-session))))
           cider-connections
           (not (null ob-clojure-literate-session)))
    ;; return back to original file.
    (if (not (and (= (length (ob-clojure-literate-get-session-list)) 1)
                  (-contains-p (ob-clojure-literate-get-session-list) ob-clojure-literate-default-session)))
        (save-window-excursion
          (find-file (expand-file-name (concat ob-clojure-literate-project-location "ob-clojure/src/ob_clojure/core.clj")))
          (with-current-buffer "core.clj"
            (cider-jack-in))))))

(defun ob-clojure-literate-set-local-cider-connections (toggle?)
  "Set buffer local `cider-connections' for `ob-clojure-literate-mode' `TOGGLE?'."
  (if toggle?
      (progn
        (setq ob-clojure-literate-cider-connections cider-connections)
        (unless (local-variable-if-set-p 'cider-connections)
          (make-local-variable 'cider-connections))
        (setq-local cider-connections ob-clojure-literate-cider-connections))
    ;; store/restore emptied CIDER connections by `ob-clojure-literate-enable'.
    (kill-local-variable 'cider-connections) ; kill local variable so that I can get the original global variable value.
    ;; Empty all CIDER connections to avoid `cider-current-connection' return any connection.
    ))

(defun ob-clojure-literate-cider-do-not-find-ns (body params)
  "Fix the issue that `cider-current-ns' try to invoke `clojure-find-ns' to extract ns from buffer."
  ;; TODO: Is it possible to find ns in `body'?
  (when (ob-clojure-literate-any-connection-p)
    (setq ob-clojure-literate-original-ns (cider-current-ns))
    (with-current-buffer ob-clojure-literate-session
      (setq ob-clojure-literate-session-ns cider-buffer-ns))
    (setq-local cider-buffer-ns ob-clojure-literate-session-ns))
  (message (format "ob-clojure-literate: current CIDER ns is [%s]." cider-buffer-ns)))

(defun ob-clojure-literate-set-local-session (toggle?)
  "Set buffer local `org-babel-default-header-args:clojure' for `ob-clojure-literate-mode' `TOGGLE?'."
  (if toggle?
      (progn
        ;; set local default session for ob-clojure.
        (setq ob-clojure-literate-session (ob-clojure-literate-set-session))
        (unless (local-variable-if-set-p 'org-babel-default-header-args:clojure)
          (make-local-variable 'org-babel-default-header-args:clojure))
        (add-to-list 'org-babel-default-header-args:clojure
                     `(:session . ,ob-clojure-literate-session))
        )
    ;; remove :session from buffer local default header arguments list.
    (unless (local-variable-if-set-p 'org-babel-default-header-args:clojure)
      (make-local-variable 'org-babel-default-header-args:clojure))
    (setq org-babel-default-header-args:clojure
          (delq t
                (mapcar
                 (lambda (cons) (if (eq (car cons) :session) t cons))
                 org-babel-default-header-args:clojure)))
    ))

;;; Support `org-babel-initiate-session' / [C-c C-v z] to initialize Clojure session.

(defun org-babel-clojure-initiate-session (&optional session _params)
  "Initiate a session named SESSION according to PARAMS."
  (when (and session (not (string= session "none")))
    (save-window-excursion
      (unless (org-babel-comint-buffer-livep session)
        ;; CIDER jack-in to the Clojure project directory.
        (cond
         ((eq org-babel-clojure-backend 'cider)
          (require 'cider)
          (let ((session-buffer (save-window-excursion
                                  (cider-jack-in t)
                                  (current-buffer))))
            (if (org-babel-comint-buffer-livep session-buffer)
                (progn (sit-for .25) session-buffer))))
         ((eq org-babel-clojure-backend 'slime)
          (error "Session evaluation with SLIME is not supported"))
         (t
          (error "Session initiate failed")))
        )
      (get-buffer session)
      )))

(defun org-babel-prep-session:clojure (session params)
  "Prepare SESSION according to the header arguments specified in PARAMS."
  (let* ((session (org-babel-clojure-initiate-session session))
         (var-lines (org-babel-variable-assignments:clojure params)))
    (when session
      (org-babel-comint-in-buffer session
        (mapc (lambda (var)
                (insert var) (comint-send-input nil t)
		            (org-babel-comint-wait-for-output session)
		            (sit-for .1) (goto-char (point-max))) var-lines)))
    session))

(defun org-babel-clojure-var-to-clojure (var)
  "Convert src block's `VAR' to Clojure variable."
  ;; TODO: reference `org-babel-python-var-to-python'
  )

(defun org-babel-variable-assignments:clojure (params)
  "Return a list of Clojure statements assigning the block's variables in `PARAMS'."
  (mapcar
   (lambda (pair)
     (format "(def %s %s)"
             (car pair)
             ;; (org-babel-clojure-var-to-clojure (cdr pair))
             (cdr pair)))
   (org-babel--get-vars params)))


(defvar ob-clojure-literate-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "C-c C-v M-s") 'ob-clojure-literate-specify-session-header-argument)
    (define-key map (kbd "C-c C-v M-j") 'ob-clojure-literate-auto-jackin)
    ;; (define-key map (kbd "C-c C-e") 'cider-eval-last-sexp)
    ;; (define-key map (kbd "C-c C-d") 'cider-doc)
    map)
  "Keymap for `ob-clojure-literate-mode'.")

;;;###autoload
(defun ob-clojure-literate-enable ()
  "Enable Org-mode buffer locally for `ob-clojure-literate'."
  (when (and (not (null cider-connections)) ; only enable `ob-clojure-literate-mode' when has CIDER connections.
             (equal major-mode 'org-mode)) ; `ob-clojure-literate-mode' only works in `org-mode'.
    (ob-clojure-literate-set-local-cider-connections ob-clojure-literate-mode)
    (ob-clojure-literate-set-local-session ob-clojure-literate-mode)
    (advice-add 'org-babel-execute:clojure :before #'ob-clojure-literate-cider-do-not-find-ns)
    (message "ob-clojure-literate minor mode enabled.")))

;;;###autoload
(defun ob-clojure-literate-disable ()
  "Disable Org-mode buffer locally for `ob-clojure-literate'."
  (advice-remove 'org-babel-execute:clojure #'ob-clojure-literate-cider-do-not-find-ns)
  (setq-local cider-buffer-ns ob-clojure-literate-original-ns)
  (ob-clojure-literate-set-local-cider-connections ob-clojure-literate-mode)
  (ob-clojure-literate-set-local-session ob-clojure-literate-mode)
  (message "ob-clojure-literate minor mode disabled."))

;;;###autoload
(if ob-clojure-literate-auto-jackin-p (ob-clojure-literate-auto-jackin))

;;;###autoload
(define-minor-mode ob-clojure-literate-mode
  "A minor mode to toggle `ob-clojure-literate'."
  :require 'ob-clojure-literate
  :init-value t
  :lighter " clj-lp"
  :group 'ob-clojure-literate
  :keymap ob-clojure-literate-mode-map
  :global nil
  (if ob-clojure-literate-mode
      (ob-clojure-literate-enable)
    (ob-clojure-literate-disable))
  )



(provide 'ob-clojure-literate)

;;; ob-clojure-literate.el ends here
