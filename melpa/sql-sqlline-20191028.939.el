;;; sql-sqlline.el --- Adds SQLLine support to SQLi mode -*- lexical-binding: t -*-

;; Copyright (C) since 2019 Matteo Redaelli
;; Author: Matteo Redaelli <matteo.redaelli@gmail.com>

;; Version: 1.0.1
;; Package-Version: 20191028.939
;; Keywords: languages
;; Package-Requires: ((emacs "24.4"))
;; Homepage: https://gitlab.com/matteo.redaelli/sql-sqlline

;; This file is not part of GNU Emacs.

;; This file is free software...

;;; Commentary:
;; * What is it?

;;   Emacs comes with a SQL interpreter which is able to open a connection
;;   to databases and present you with a prompt you are probably familiar
;;   with (e.g. `mysql>', `pgsql>', `sqlline>', etc.). This mode gives you
;;   the ability to do that for Sqlline.


;; * How do I get it?

;;   The canonical repository for the source code is
;;   [https://gitlab.com/matteo.redaelli/sql-sqlline] .

;;   The recommended way to install the package is to utilize Emacs's
;;   `package.el' along with MELPA. To set this up, please follow MELPA's
;;   [getting started guide], and then run `M-x package-install
;;   sql-sqlline'.


;;   [getting started guide] https://melpa.org/#/getting-started


;; * How do I use it?

;;   Within Emacs, run `M-x sql-sqlline'. You will be prompted by in the
;;   minibuffer for a server. Enter the correct server and you should be
;;   greeted by a SQLi buffer with a `sqlline>' prompt.

;;   From there you can either type queries in this buffer, or open a
;;   `sql-mode' buffer and send chunks of SQL over to the SQLi buffer with
;;   the requisite key-chords.


;; * Contributing

;;   Please open GitHub issues and issue pull requests. Prior to submitting
;;   a pull-request, please run `make'. This will perform some linting and
;;   attempt to compile the package.


;; * License

;;   Please see the LICENSE file.

;;; Code:
(require 'sql)

(defgroup sql-sqlline nil
  "Use SQLLine with sql-interactive mode."
  :group 'SQL
  :prefix "sql-sqlline-")

(defcustom sql-sqlline-program "sqlline"
  "Command to start the SQLLine command interpreter."
  :type 'file
  :group 'sql-sqlline)

(defcustom sql-sqlline-login-params '()
  "Parameters needed to connect to SQLLine."
  :type 'sql-login-params
  :group 'sql-sqlline)

(defcustom sql-sqlline-options '("--silent" "true")
  "List of options for `sql-sqlline-program'."
  :type '(repeat string)
  :group 'sql-sqlline)

(defun sql-sqlline-comint (product options &optional buffer-name)
  "Connect to SQLLine in a comint buffer.

PRODUCT is the sql product (sqlline).  OPTIONS are any additional
options to pass to sqlline-shell.  BUFFER-NAME is what you'd like
the SQLi buffer to be named."
  "Connect to SQLLine in a comint buffer.

PRODUCT is the sql product (sqlline). OPTIONS are any additional
options to pass to sqlline-shell. BUFFER-NAME is what you'd like
the SQLi buffer to be named."
    (sql-comint product options buffer-name))

;;;###autoload
(defun sql-sqlline (&optional buffer)
  "Run SQLLine as an inferior process.

The buffer with name BUFFER will be used or created."
  (interactive "P")
  (sql-product-interactive 'sqlline buffer))

(sql-add-product 'sqlline "SQLLine"
                 :free-software t
                 :list-all "!tables"
                 :list-table "!describe %s;"
                 :prompt-regexp "^[^>]*> "
                 :prompt-cont-regexp "^(semicolon|quote|dquote)> "
                 :sqli-comint-func 'sql-sqlline-comint
                 :font-lock 'sql-mode-ansi-font-lock-keywords
                 :sqli-login sql-sqlline-login-params
                 :sqli-program 'sql-sqlline-program
                 :sqli-options 'sql-sqlline-options)

(provide 'sql-sqlline)
;;; sql-sqlline.el ends here
