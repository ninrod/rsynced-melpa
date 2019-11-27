;;; 0x0.el --- Upload to 0x0.st -*- lexical-binding: t -*-

;; Author: Philip K. <philip@warpmail.net>
;; Version: 0.1.1
;; Package-Version: 20190902.929
;; Keywords: comm
;; Package-Requires: ((emacs "24.1"))
;; URL: https://git.sr.ht/~zge/nullpointer-emacs

;; This file is NOT part of Emacs.
;;
;; This file is in the public domain, to the extent possible under law,
;; published under the CC0 1.0 Universal license.
;;
;; For a full copy of the CC0 license see
;; https://creativecommons.org/publicdomain/zero/1.0/legalcode

;;; Commentary:
;;
;; This package defines three main functions: `0x0-upload',
;; `0x0-upload-file' and `0x0-upload-string', which respectively upload
;; (parts of) the current buffer, a file on your disk and a string from
;; the minibuffer to a 0x0.st comparable server.
;;
;; Besides the built-in `url' library, this package has no dependencies,
;; especially no external ones, such as curl.
;;
;; See https://0x0.st/ for more details, and consider donating to
;; https://liberapay.com/lachs0r/donate if you like the service.

(require 'url)

;;; Code:

(defgroup 0x0 nil
  "Upload data to 0x0.st-compatible servers."
  :group 'convenience
  :prefix "0x0-")

(defcustom 0x0-url "https://0x0.st"
  "URL to use for `0x0-upload'."
  :type 'string)

(defcustom 0x0-min-age 30.0
  "Maximal number of days a file is kept.

See https://github.com/lachs0r/0x0/blob/master/cleanup.py#L12"
  :type 'float)

(defcustom 0x0-max-age 365.0
  "Minimal number of days a file is kept.

See https://github.com/lachs0r/0x0/blob/master/cleanup.py#L13"
  :type 'float)

(defcustom 0x0-max-size (float (* 1024 1024 256))
  "Maximal permitted file size.

See https://github.com/lachs0r/0x0/blob/master/fhost.py#L22"
  :type 'float)

(defcustom 0x0-use-curl-if-installed t
  "Maximal permitted file size.

See https://github.com/lachs0r/0x0/blob/master/fhost.py#L22"
  :type 'boolean)

(defvar 0x0--filename nil)

(defun 0x0--calculate-timeout (size)
  "Calculate days a file of size SIZE would last.

See also `0x0-min-age' and `0x0-max-age'."
  (+ 0x0-min-age
     (* (- 0x0-min-age 0x0-max-age)
        (expt (- (/ size 0x0-max-size) 1.0) 3))))

(defun 0x0--use-curl (start end)
  "Backend function for uploading using curl.

Operate on region between START and END."
  (let ((buf (generate-new-buffer "*0x0 response*")))
    (call-process-region start end "curl"
                         nil buf nil
                         "-s" "-S" "-F"
                         (concat "file=@-;filename="
                                 0x0--filename)
                         0x0-url)
    buf))

(defun 0x0--use-url (start end)
  "Backend function for uploading using `url' functions.

Operate on region between START and END."
  (let* ((boundary (format "%X-%X-%X" (random) (random) (random)))
         (url-request-extra-headers
          `(("Content-Type" . ,(concat "multipart/form-data; boundary=" boundary))))
         (url-request-data
          (let ((source (current-buffer))
                (filename (or 0x0--filename (buffer-name))))
            (with-temp-buffer
              (insert "--" boundary "\r\n"
                      "Content-Disposition: form-data; name=\"file\"; filename=\"" filename "\"\r\n"
                      "Content-type: text/plain\r\n\r\n")
              (insert-buffer-substring-no-properties source start end)
              (insert "\r\n--" boundary "--")
              (buffer-string))))
         (url-request-method "POST"))
    (url-retrieve-synchronously 0x0-url)))

;;;###autoload
(defun 0x0-upload (start end)
  "Upload current buffer to `0x0-url' from START to END.

If START and END are not specified, upload entire buffer."
  (interactive (list (if (use-region-p) (region-beginning) (point-min))
                     (if (use-region-p) (region-end) (point-max))))
  (let ((resp (if (and 0x0-use-curl-if-installed
                       (executable-find "curl"))
                  (0x0--use-curl start end)
                (0x0--use-url start end)))
        (timeout (0x0--calculate-timeout (- end start))))
    (with-current-buffer resp
      (goto-char (point-min))
      (unless (search-forward-regexp (concat "^" (regexp-quote 0x0-url)) nil t)
        (error "Failed to upload"))
      (kill-new (buffer-string))
      (message "Yanked `%s' into kill ring. Should last ~%2g days"
               (buffer-string) timeout))
    (kill-buffer resp)))

;;;###autoload
(defun 0x0-upload-file (file)
  "Upload FILE to `0x0-url'."
  (interactive "f")
  (with-temp-buffer
    (insert-file-contents file)
    (let ((0x0--filename file))
      (0x0-upload (point-min) (point-max)))))

;;;###autoload
(defun 0x0-upload-string (string)
  "Upload STRING to `0x0-url'."
  (interactive "MUpload: ")
  (with-temp-buffer
    (insert string)
    (let ((0x0--filename "upload.txt"))
      (0x0-upload (point-min) (point-max)))))

(provide '0x0)

;;; 0x0.el ends here
