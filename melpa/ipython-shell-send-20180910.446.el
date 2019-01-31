;;; ipython-shell-send.el --- Send code (including magics) to ipython shell  -*- lexical-binding: t; -*-

;; Copyright (C) 2017  Jack Kamm

;; Author: Jack Kamm <jackkamm@gmail.com>
;; Version: 1.0.2
;; Package-Version: 20180910.446
;; Package-Requires: ((emacs "24"))
;; Keywords: tools, processes
;; URL: https://github.com/jackkamm/ipython-shell-send-el

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

;; This package adds extra IPython functionality for Emacs' python.el.
;; It adds the following two features:
;; 1. Connect to and run existing jupyter consoles, e.g. on a remote server.
;; 2. Allow IPython magic in code blocks sent to the inferior Python buffer.
;;
;; The first feature is provided by the function
;; `ipython-shell-send/run-jupyter-existing', which is analogous
;; to python.el's `run-python', except it connects to an existing Jupyter
;; console instead of starting a new Python subprocess.
;;
;; The second feature is provided by the functions
;; `ipython-shell-send-buffer', `ipython-shell-send-region', and
;; `ipython-shell-send-defun', which are analogous to `python-shell-send-*'
;; in python.el, except that they can handle IPython magic commands.

;;; Code:


(require 'python)

(defun ipython-shell-send--save-temp-file (string)
  "Send STRING to temp file with .ipy suffix.
Returns the tempfile name."
  (let* ((temporary-file-directory
          (if (file-remote-p default-directory)
              (concat (file-remote-p default-directory) "/tmp")
            temporary-file-directory))
         (temp-file-name (make-temp-file "ipy" nil ".ipy"))
         (coding-system-for-write (python-info-encoding)))
    (with-temp-file temp-file-name
      (insert string)
      (delete-trailing-whitespace))
    temp-file-name))

(defun ipython-shell-send-string (string &optional process msg)
  "Send STRING to inferior Python PROCESS.
When optional argument MSG is non-nil, forces display of a
user-friendly message if there's no process running; defaults to
t when called interactively."
  (interactive
   (list (read-string "Python command: ") nil t))
  (let ((process (or process (python-shell-get-process-or-error msg))))
    (if (string-match ".\n+." string)   ;Multiline.
        (let* ((temp-file-name (ipython-shell-send--save-temp-file string))
               (file-name (or (buffer-file-name) temp-file-name)))
          (ipython-shell-send-file file-name process temp-file-name t))
      (comint-send-string process string)
      (when (or (not (string-match "\n\\'" string))
                (string-match "\n[ \t].*\n?\\'" string))
        (comint-send-string process "\n")))))

;;;###autoload
(defun ipython-shell-send-region (start end &optional send-main msg)
  "Send the region delimited by START and END to inferior IPython process.
When optional argument SEND-MAIN is non-nil, allow execution of
code inside blocks delimited by \"if __name__== \\='__main__\\=':\".
When called interactively SEND-MAIN defaults to nil, unless it's
called with prefix argument.  When optional argument MSG is
non-nil, forces display of a user-friendly message if there's no
process running; defaults to t when called interactively."
  (interactive
   (list (region-beginning) (region-end) current-prefix-arg t))
  (let* ((string (python-shell-buffer-substring start end (not send-main)))
         (process (python-shell-get-process-or-error msg))
         (original-string (buffer-substring-no-properties start end))
         (_ (string-match "\\`\n*\\(.*\\)" original-string)))
    (message "Sent: %s..." (match-string 1 original-string))
    (ipython-shell-send-string string process)))

;;;###autoload
(defun ipython-shell-send-buffer (&optional send-main msg)
  "Send the entire buffer to inferior IPython process.
When optional argument SEND-MAIN is non-nil, allow execution of
code inside blocks delimited by \"if __name__== \\='__main__\\=':\".
When called interactively SEND-MAIN defaults to nil, unless it's
called with prefix argument.  When optional argument MSG is
non-nil, forces displa qqy of a user-friendly message if there's no
process running; defaults to t when called interactively."
  (interactive (list current-prefix-arg t))
  (save-restriction
    (widen)
    (ipython-shell-send-region (point-min) (point-max) send-main msg)))

;;;###autoload
(defun ipython-shell-send-defun (&optional arg msg)
  "Send the current defun to inferior IPython process.
When argument ARG is non-nil do not include decorators.  When
optional argument MSG is non-nil, forces display of a
user-friendly message if there's no process running; defaults to
t when called interactively."
  (interactive (list current-prefix-arg t))
  (save-excursion
    (ipython-shell-send-region
     (progn
       (end-of-line 1)
       (while (and (or (python-nav-beginning-of-defun)
                       (beginning-of-line 1))
                   (> (current-indentation) 0)))
       (when (not arg)
         (while (and (forward-line -1)
                     (looking-at (python-rx decorator))))
         (forward-line 1))
       (point-marker))
     (progn
       (or (python-nav-end-of-defun)
           (end-of-line 1))
       (point-marker))
     nil  ;; noop
     msg)))

(defun ipython-shell-send-file (file-name &optional process temp-file-name
                                         delete msg)
  "Send FILE-NAME to inferior Python PROCESS.
If TEMP-FILE-NAME is passed then that file is used for processing
instead, while internally the shell will continue to use
FILE-NAME.  If TEMP-FILE-NAME and DELETE are non-nil, then
TEMP-FILE-NAME is deleted after evaluation is performed.  When
optional argument MSG is non-nil, forces display of a
user-friendly message if there's no process running; defaults to
t when called interactively."
  (interactive
   (list
    (read-file-name "File to send: ")   ; file-name
    nil                                 ; process
    nil                                 ; temp-file-name
    nil                                 ; delete
    t))                                 ; msg
  (let* ((process (or process (python-shell-get-process-or-error msg)))
         (file-name (expand-file-name
                     (or (file-remote-p file-name 'localname)
                         file-name)))
         (temp-file-name (when temp-file-name
                           (expand-file-name
                            (or (file-remote-p temp-file-name 'localname)
                                temp-file-name)))))
    (python-shell-send-string
     (format
      (concat
       "import IPython, os;"
       "IPython.get_ipython().magic('''run -i %s''');"
       (when (and delete temp-file-name)
         (format "os.remove('''%s''');" temp-file-name)))
      (or temp-file-name file-name))
     process)))

(defun ipython-shell-send/run-jupyter-existing--command (kernel)
  "Return string for the command to connect to an existing jupyter KERNEL."
  (concat "jupyter console --simple-prompt --existing " kernel))

;;;###autoload
(defun ipython-shell-send/run-jupyter-existing (dedicated show)
  "Run existing Jupyter kernel within inferior Python buffer.

Prompts for an existing kernel, then opens it in the standard
inferior Python buffer from python.el.  For example, the kernel
may correspond to a running Jupyter notebook, or may have been
started manually with the 'jupyter console' command.  Leaving
the prompt blank will select the most recent kernel.

To connect to a remote kernel, call this function from within
a Tramp buffer on the remote machine.

When called interactively with `prefix-arg', it allows the
user to edit such choose whether the interpreter
should be DEDICATED for the current buffer.  When numeric
prefix arg is other than 0 or 4 do not SHOW."
  (interactive
   (if current-prefix-arg
       (list
        (y-or-n-p "Make dedicated process? ")
        (= (prefix-numeric-value current-prefix-arg) 4))
     (list nil t)))
  (run-python
   (read-shell-command
    "Run Python: "
    (ipython-shell-send/run-jupyter-existing--command
     (condition-case err
	 (completing-read
	  "Kernel file (blank for most recent): "
	  (cdr
	   (cdr
	    (directory-files
	     (concat
	      (file-remote-p default-directory)
	      (string-trim
	       (let ((shell-file-name "/bin/sh"))
		 (shell-command-to-string
		  (concat "python3 -c 'import jupyter_core.paths as jsp; "
			  "print(jsp.jupyter_runtime_dir())'"))))))))
	  nil nil "")
       (file-error
	(warn (error-message-string err))
	nil))))
   dedicated show))

(provide 'ipython-shell-send)
;;; ipython-shell-send.el ends here



