;;; aurel.el --- Search, get info, vote for and download AUR packages  -*- lexical-binding: t -*-

;; Copyright (C) 2014-2017 Alex Kost

;; Author: Alex Kost <alezost@gmail.com>
;; Created: 6 Feb 2014
;; Version: 0.9
;; Package-Version: 20170114.937
;; URL: https://github.com/alezost/aurel
;; Keywords: tools
;; Package-Requires: ((emacs "24.3") (bui "1.1.0") (dash "2.11.0"))

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.
;;
;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.
;;
;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <http://www.gnu.org/licenses/>.

;;; Commentary:

;; This package provides an interface for searching, getting information,
;; voting for, subscribing and downloading packages from the Arch User
;; Repository (AUR) <https://aur.archlinux.org/>.

;; To manually install the package, add the following to your init-file:
;;
;;   (add-to-list 'load-path "/path/to/aurel-dir")
;;   (autoload 'aurel-package-info "aurel" nil t)
;;   (autoload 'aurel-package-search "aurel" nil t)
;;   (autoload 'aurel-package-search-by-name "aurel" nil t)
;;   (autoload 'aurel-maintainer-search "aurel" nil t)
;;   (autoload 'aurel-installed-packages "aurel" nil t)

;; Also set a directory where downloaded packages will be put:
;;
;;   (setq aurel-download-directory "~/aur")

;; To search for packages, use `aurel-package-search' or
;; `aurel-maintainer-search' commands.  If you know the name of a
;; package, use `aurel-package-info' command.  Also you can display a
;; list of installed AUR packages with `aurel-installed-packages'.

;; Information about the packages is represented in a list-like buffer
;; similar to a buffer containing emacs packages.  Press "h" to see a
;; hint (a summary of the available key bindings).  To get more info
;; about a package (or marked packages), press "RET".  To download a
;; package, press "d" (don't forget to set `aurel-download-directory'
;; before).  In a list buffer, you can mark several packages for
;; downloading with "m"/"M" (and unmark with "u"/"U" and "DEL"); also
;; you can perform filtering (press "f f" to enable a filter and "f d"
;; to disable all filters) of a current list to hide particular
;; packages.

;; It is possible to move to the previous/next displayed results with
;; "l"/"r" (each aurel buffer has its own history) and to refresh
;; information with "g".

;; After receiving information about the packages, pacman is called to
;; find what packages are installed.  To disable that, set
;; `aurel-installed-packages-check' to nil.

;; To vote/subscribe for a package, press "v"/"s" (with prefix,
;; unvote/unsubscribe) in a package info buffer (you should have an AUR
;; account for that).  To add information about "Voted"/"Subscribed"
;; status, use the following:
;;
;;   (setq aurel-aur-user-package-info-check t)

;; For full description and screenshots, see
;; <https://github.com/alezost/aurel>.

;;; Code:

(require 'url)
(require 'url-handlers)
(require 'json)
(require 'cl-lib)
(require 'dash)
(require 'bui)

(defgroup aurel nil
  "Search for and download AUR (Arch User Repository) packages."
  :group 'applications)

(defgroup aurel-faces nil
  "Faces for 'aurel' buffers."
  :group 'aurel
  :group 'faces)

(defcustom aurel-aur-user-package-info-check nil
  "If non-nil, check additional info before displaying a package info.
Additional info is an AUR user specific information (whether the user
voted for the package or subscribed to receive comments)."
  :type 'boolean
  :group 'aurel)

(defvar aurel-unknown-string "Unknown"
  "String used if a value of the parameter is unknown.")

(defvar aurel-none-string "None"
  "String saying that a parameter has no value.
This string can be displayed by pacman.")

(defvar aurel-package-name-re
  "[-+_[:alnum:]]+"
  "Regexp matching a valid package name.")


;;; Debugging

(defvar aurel-debug-level 0
  "If > 0, display debug messages in `aurel-debug-buffer'.
The greater the number, the more messages is printed.
Max level is 9.")

(defvar aurel-debug-buffer "*aurel debug*"
  "Name of a buffer containing debug messages.")

(defvar aurel-debug-time-format "%T.%3N"
  "Time format used for debug mesages.")

(defun aurel-debug (level msg &rest args)
  "Print debug message if needed.
If `aurel-debug-level' >= LEVEL, print debug message MSG with
arguments ARGS into `aurel-debug-buffer'.
Return nil."
  (when (>= aurel-debug-level level)
    (with-current-buffer (get-buffer-create aurel-debug-buffer)
      (goto-char (point-max))
      (insert (format-time-string aurel-debug-time-format (current-time)))
      (insert " " (apply 'format msg args) "\n")))
  nil)


;;; Interacting with AUR server

(defcustom aurel-aur-user-name ""
  "User name for AUR."
  :type 'string
  :group 'aurel)

(defvar aurel-aur-host "aur.archlinux.org"
  "AUR domain.")

(defvar aurel-aur-base-url (concat "https://" aurel-aur-host)
  "Root URL of the AUR service.")

(defvar aurel-aur-login-url
  (url-expand-file-name "login" aurel-aur-base-url)
  "Login URL.")

(defconst aurel-aur-cookie-name "AURSID"
  "Cookie name used for AUR login.")

;; Avoid compilation warning about `url-http-response-status'
(defvar url-http-response-status)

(defun aurel-check-response-status (buffer &optional noerror)
  "Return t, if URL response status in BUFFER is 2XX or 3XX.
Otherwise, throw an error or return nil, if NOERROR is nil."
  (with-current-buffer buffer
    (aurel-debug 3 "Response status: %s" url-http-response-status)
    (if (or (null (numberp url-http-response-status))
            (> url-http-response-status 399))
        (unless noerror (error "Error during request: %s"
                               url-http-response-status))
      t)))

(defun aurel-receive-parse-info (url)
  "Return received output from URL processed with `json-read'."
  (aurel-debug 3 "Retrieving %s" url)
  (with-temp-buffer
    (url-insert-file-contents url)
    (goto-char (point-min))
    (let ((json-key-type 'string)
          (json-array-type 'list)
          (json-object-type 'alist))
      (json-read))))

(defun aurel-get-aur-packages-info (url)
  "Return information about the packages from URL.
Output from URL should be a json data.  It is parsed with
`json-read'.
Returning value is alist of AUR package parameters (strings from
`aurel-aur-param-alist') and their values."
  (let* ((full-info (aurel-receive-parse-info url))
         (type      (cdr (assoc "type" full-info)))
         (count     (cdr (assoc "resultcount" full-info)))
         (results   (cdr (assoc "results" full-info))))
    (cond
     ((string= type "error")
      (error "%s" results))
     ((= count 0)
      nil)
     (t
      (when (string= type "info")
        (setq results (list results)))
      results))))

;; Because of the bug <http://bugs.gnu.org/16960>, we can't use
;; `url-retrieve-synchronously' (or any other simple call of
;; `url-retrieve', as the callback is never called) to login to
;; <https://aur.archlinux.org>.  So we use
;; `aurel-url-retrieve-synchronously' - it is almost the same, except it
;; can exit from the waiting loop when a buffer with received data
;; appears in `url-dead-buffer-list'.  This hack is currently possible,
;; because `url-http-parse-headers' marks the buffer as dead when it
;; returns nil.

(defun aurel-url-retrieve-synchronously (url &optional silent inhibit-cookies)
  "Retrieve URL synchronously.
Return the buffer containing the data, or nil if there are no data
associated with it (the case for dired, info, or mailto URLs that need
no further processing).  URL is either a string or a parsed URL.
See `url-retrieve' for SILENT and INHIBIT-COOKIES."
  (url-do-setup)
  (let (asynch-buffer retrieval-done)
    (setq asynch-buffer
          (url-retrieve url
                        (lambda (&rest ignored)
                          (url-debug 'retrieval
                                     "Synchronous fetching done (%S)"
                                     (current-buffer))
                          (setq retrieval-done t
                                asynch-buffer (current-buffer)))
                        nil silent inhibit-cookies))
    (when asynch-buffer
      (let ((proc (get-buffer-process asynch-buffer)))
        (while (not (or retrieval-done
                        ;; retrieval can be done even if
                        ;; `retrieval-done' is nil (see the comment
                        ;; above)
                        (memq asynch-buffer url-dead-buffer-list)))
          (url-debug 'retrieval
                     "Spinning in url-retrieve-synchronously: %S (%S)"
                     retrieval-done asynch-buffer)
          (if (buffer-local-value 'url-redirect-buffer asynch-buffer)
              (setq proc (get-buffer-process
                          (setq asynch-buffer
                                (buffer-local-value 'url-redirect-buffer
                                                    asynch-buffer))))
            (if (and proc (memq (process-status proc)
                                '(closed exit signal failed))
                     ;; Make sure another process hasn't been started.
                     (eq proc (or (get-buffer-process asynch-buffer) proc)))
                (progn ;; Call delete-process so we run any sentinel now.
                  (delete-process proc)
                  (setq retrieval-done t)))
            (unless (or (with-local-quit
                          (accept-process-output proc))
                        (null proc))
              (when quit-flag
                (delete-process proc))
              (setq proc (and (not quit-flag)
                              (get-buffer-process asynch-buffer)))))))
      asynch-buffer)))

(defun aurel-url-post (url args &optional inhibit-cookies)
  "Send ARGS to URL as a POST request.
ARGS is alist of field names and values to send.
Return the buffer with the received data.
If INHIBIT-COOKIES is non-nil, do not use saved cookies."
  (let ((url-request-method "POST")
        (url-request-extra-headers
         '(("Content-Type" . "application/x-www-form-urlencoded")))
        (url-request-data (aurel-get-fields-string args)))
    (aurel-debug 2 "POSTing to %s" url)
    (aurel-url-retrieve-synchronously url inhibit-cookies)))

(defun aurel-get-aur-cookie ()
  "Return cookie for AUR login.
Return nil, if there is no such cookie or it is expired."
  (url-do-setup) ; initialize cookies
  (let* ((cookies (url-cookie-retrieve aurel-aur-host "/" t))
         (cookie (car (cl-member-if
                       (lambda (cookie)
                         (equal (url-cookie-name cookie)
                                aurel-aur-cookie-name))
                       cookies))))
    (if (null cookie)
        (aurel-debug 4 "AUR login cookie not found")
      (if (url-cookie-expired-p cookie)
          (aurel-debug 4 "AUR login cookie is expired")
        (aurel-debug 4 "AUR login cookie is valid")
        cookie))))

(declare-function auth-source-search "auth-source" t)

(defun aurel-aur-login-maybe (&optional force noerror)
  "Login to AUR, use cookie if possible.
If FORCE is non-nil (interactively, with prefix), prompt for
credentials and login without trying the cookie.
See `aurel-aur-login' for the meaning of NOERROR and returning value."
  (interactive "P")
  (if (aurel-get-aur-cookie)
      (progn
        (aurel-debug 2 "Using cookie instead of a real login")
        t)
    (let (user password)
      (let ((auth (car (auth-source-search :host aurel-aur-host))))
        (when auth
          (let ((secret (plist-get auth :secret)))
            (setq user (plist-get auth :user)
                  password (if (functionp secret)
                               (funcall secret)
                             secret)))))
      (when (or force (null user))
        (setq user (read-string "AUR user name: " aurel-aur-user-name)))
      (when (or force (null password))
        (setq password (read-passwd "Password: ")))
      (aurel-aur-login user password t noerror))))

(defun aurel-aur-login (user password &optional remember noerror)
  "Login to AUR with USER and PASSWORD.
If REMEMBER is non-nil, remember a cookie.
Return t, if login was successful, otherwise throw an error or
return nil, if NOERROR is non-nil."
  (let ((buf (aurel-url-post
              aurel-aur-login-url
              (list (cons "user" user)
                    (cons "passwd" password)
                    (cons "remember_me" (if remember "on" "off")))
              'inhibit-cookie)))
    (when (aurel-check-response-status buf noerror)
      (with-current-buffer buf
        (if (re-search-forward "errorlist.+<li>\\(.+\\)</li>" nil t)
            (let ((err (match-string 1)))
              (aurel-debug 1 "Error during login: %s" )
              (or noerror (error "%s" err))
              nil)
          (url-cookie-write-file)
          (aurel-debug 1 "Login for %s is successful" user)
          t)))))

(defun aurel-add-aur-user-package-info (info)
  "Return a new info by adding AUR user info to package INFO.
See `aurel-aur-user-package-info-check' for the meaning of
additional info."
  (let ((add (aurel-get-aur-user-package-info
              (aurel-get-aur-package-url
               (bui-entry-value info 'name)))))
    (if add
        (cons (cons 'user-info add)
              info)
      info)))

(defun aurel-get-aur-user-package-info (url)
  "Return AUR user specific information about a package from URL.
Returning value is alist of package parameters specific for AUR
user (`voted' and `subscribed') and their values.
Return nil, if information is not found."
  (when (aurel-aur-login-maybe nil t)
    (aurel-debug 3 "Retrieving %s" url)
    (let ((buf (url-retrieve-synchronously url)))
      (aurel-debug 4 "Searching in %S for voted/subscribed params" buf)
      (list (cons 'voted
                  (aurel-aur-package-voted buf))
            (cons 'subscribed
                  (aurel-aur-package-subscribed buf))))))

(defun aurel-aur-package-voted (buffer)
  "Return `voted' parameter value from BUFFER with fetched data.
Return non-nil if a package is voted by the user; nil if it is not;
`aurel-unknown-string' if the information is not found.
BUFFER should contain html data about the package."
  (cond
   ((aurel-search-in-buffer
     (aurel-get-aur-user-action-name 'vote) buffer)
    nil)
   ((aurel-search-in-buffer
     (aurel-get-aur-user-action-name 'unvote) buffer)
    t)
   (t aurel-unknown-string)))

(defun aurel-aur-package-subscribed (buffer)
  "Return `subscribed' parameter value from BUFFER with fetched data.
Return non-nil if a package is subscribed by the user; nil if it is not;
`aurel-unknown-string' if the information is not found.
BUFFER should contain html data about the package."
  (cond
   ((aurel-search-in-buffer
     (aurel-get-aur-user-action-name 'subscribe) buffer)
    nil)
   ((aurel-search-in-buffer
     (aurel-get-aur-user-action-name 'unsubscribe) buffer)
    t)
   (t aurel-unknown-string)))

(defun aurel-search-in-buffer (regexp buffer)
  "Return non-nil if BUFFER contains REGEXP; return nil otherwise."
  (with-current-buffer buffer
    (goto-char (point-min))
    (let ((res (re-search-forward regexp nil t)))
      (aurel-debug 7 "Searching for %s in %S: %S" regexp buffer res)
      res)))

(defvar aurel-aur-user-actions
  '((vote        "do_Vote"     "vote"     "Vote for '%s' package?")
    (unvote      "do_UnVote"   "unvote"   "Remove vote from '%s' package?")
    (subscribe   "do_Notify"   "notify"   "Enable notifications for '%s' package?")
    (unsubscribe "do_UnNotify" "unnotify" "Disable notifications for '%s' package?"))
  "Alist of the available actions.
Each association has the following form:

  (SYMBOL NAME URL-END CONFIRM)

SYMBOL is a name of the action used internally in code of this package.
NAME is a name (string) used in the html-code of AUR package page.
URL-END is appended to the package URL; used for posting the action.
CONFIRM is a prompt to confirm the action or nil if it is not required.")

(defun aurel-get-aur-user-action-name (action)
  "Return the name of an ACTION."
  (cadr (assoc action aurel-aur-user-actions)))

(defun aurel-aur-user-action (action package-base)
  "Perform AUR user ACTION on the PACKAGE-BASE.
ACTION is a symbol from `aurel-aur-user-actions'.
PACKAGE-BASE is a name of the package base (string).
Return non-nil, if ACTION was performed; return nil otherwise."
  (let ((assoc (assoc action aurel-aur-user-actions)))
    (let ((action-name (nth 1 assoc))
          (url-end     (nth 2 assoc))
          (confirm     (nth 3 assoc)))
      (when (or (null confirm)
                (y-or-n-p (format confirm package-base)))
        (aurel-aur-login-maybe)
        (aurel-url-post
         (aurel-get-package-action-url package-base url-end)
         (list (cons "token" (url-cookie-value (aurel-get-aur-cookie)))
               (cons action-name "")))
        t))))


;;; Interacting with pacman

(defcustom aurel-pacman-program (executable-find "pacman")
  "Absolute or relative name of `pacman' program."
  :type 'string
  :group 'aurel)

(defvar aurel-pacman-locale "C"
  "Default locale used to start pacman.")

(defcustom aurel-installed-packages-check
  (and aurel-pacman-program t)
  "If non-nil, check if the found packages are installed.
If nil, searching works faster, because `aurel-pacman-program' is not
called, but it stays unknown if a package is installed or not."
  :type 'boolean
  :group 'aurel)

(defvar aurel-pacman-buffer-name " *aurel-pacman*"
  "Name of the buffer used internally for pacman output.")

(defvar aurel-pacman-info-line-re
  (rx line-start
      (group (+? (any word " ")))
      (+ " ") ":" (+ " ")
      (group (+ any) (* (and "\n " (+ any))))
      line-end)
  "Regexp matching a line of pacman query info output.
Contain 2 parenthesized groups: parameter name and its value.")

(defun aurel-call-pacman (&optional buffer &rest args)
  "Call `aurel-pacman-program' with arguments ARGS.
Insert output in BUFFER.  If it is nil, use `aurel-pacman-buffer-name'.
Return numeric exit status."
  (or aurel-pacman-program
      (error (concat "Couldn't find pacman.\n"
                     "Set aurel-pacman-program to a proper value")))
  (with-current-buffer
      (or buffer (get-buffer-create aurel-pacman-buffer-name))
    (erase-buffer)
    (let ((process-environment
           (cons (concat "LC_ALL=" aurel-pacman-locale)
                 process-environment)))
      (apply #'call-process aurel-pacman-program nil t nil args))))

(defun aurel-get-foreign-packages ()
  "Return list of names of installed foreign packages."
  (let ((buf (get-buffer-create aurel-pacman-buffer-name)))
    (aurel-call-pacman buf "--query" "--foreign")
    (aurel-pacman-query-names-buffer-parse buf)))

(defun aurel-pacman-query-names-buffer-parse (&optional buffer)
  "Parse BUFFER with packages names.
BUFFER should contain an output returned by 'pacman -Q' command.
If BUFFER is nil, use `aurel-pacman-buffer-name'.
Return list of names of packages."
  (with-current-buffer
      (or buffer (get-buffer-create aurel-pacman-buffer-name))
    (goto-char (point-min))
    (let (names)
      (while (re-search-forward
              (concat "^\\(" aurel-package-name-re "\\) ") nil t)
        (setq names (cons (match-string 1) names)))
      names)))

(defun aurel-get-installed-packages-info (&rest names)
  "Return information about installed packages NAMES.
Each name from NAMES should be a string (a name of a package).
Returning value is a list of alists with installed package
parameters (strings from `aurel-installed-param-alist') and their
values."
  (let ((buf (get-buffer-create aurel-pacman-buffer-name)))
    (apply 'aurel-call-pacman buf "--query" "--info" names)
    (aurel-pacman-query-buffer-parse buf)))

(defun aurel-pacman-query-buffer-parse (&optional buffer)
  "Parse BUFFER with packages info.
BUFFER should contain an output returned by 'pacman -Qi' command.
If BUFFER is nil, use `aurel-pacman-buffer-name'.
Return list of alists with parameter names and values."
  (with-current-buffer
      (or buffer (get-buffer-create aurel-pacman-buffer-name))
    (let ((beg (point-min))
          end info)
      ;; Packages info are separated with empty lines, search for those
      ;; till the end of buffer
      (cl-loop
       do (progn
            (goto-char beg)
            (setq end (re-search-forward "^\n" nil t))
            (and end
                 (setq info (aurel-pacman-query-region-parse beg end)
                       beg end)))
       while end
       if info collect info))))

(defun aurel-pacman-query-region-parse (beg end)
  "Parse text (package info) in current buffer from BEG to END.
Parsing region should be an output for one package returned by
'pacman -Qi' command.
Return alist with parameter names and values."
  (goto-char beg)
  (let (point)
    (cl-loop
     do (setq point (re-search-forward
                     aurel-pacman-info-line-re end t))
     while point
     collect (cons (match-string 1) (match-string 2)))))


;;; Package parameters

(defvar aurel-aur-param-alist
  '((pkg-url     . "URLPath")
    (home-url    . "URL")
    (last-date   . "LastModified")
    (first-date  . "FirstSubmitted")
    (outdated    . "OutOfDate")
    (votes       . "NumVotes")
    (popularity  . "Popularity")
    (license     . "License")
    (description . "Description")
    (keywords    . "Keywords")
    (version     . "Version")
    (name        . "Name")
    (id          . "ID")
    (base-name   . "PackageBase")
    (base-id     . "PackageBaseID")
    (maintainer  . "Maintainer")
    (replaces    . "Replaces")
    (provides    . "Provides")
    (conflicts   . "Conflicts")
    (depends     . "Depends")
    (depends-make . "MakeDepends"))
  "Association list of symbols and names of package info parameters.
Car of each assoc is a symbol used in code of this package.
Cdr - is a parameter name (string) returned by the AUR server.")

(defvar aurel-pacman-param-alist
  '((installed-name    . "Name")
    (installed-version . "Version")
    (architecture      . "Architecture")
    (installed-provides . "Provides")
    (installed-depends . "Depends On")
    (depends-opt       . "Optional Deps")
    (script            . "Install Script")
    (reason            . "Install Reason")
    (validated         . "Validated By")
    (required          . "Required By")
    (optional-for      . "Optional For")
    (installed-conflicts . "Conflicts With")
    (installed-replaces . "Replaces")
    (installed-size    . "Installed Size")
    (packager          . "Packager")
    (build-date        . "Build Date")
    (install-date      . "Install Date"))
  "Association list of symbols and names of package info parameters.
Car of each assoc is a symbol used in code of this package.
Cdr - is a parameter name (string) returned by pacman.")

(defun aurel-get-aur-param-name (param-symbol)
  "Return a name (string) of a parameter.
PARAM-SYMBOL is a symbol from `aurel-aur-param-alist'."
  (cdr (assoc param-symbol aurel-aur-param-alist)))

(defun aurel-get-aur-param-symbol (param-name)
  "Return a symbol name of a parameter.
PARAM-NAME is a string from `aurel-aur-param-alist'."
  (car (rassoc param-name aurel-aur-param-alist)))

(defun aurel-get-pacman-param-name (param-symbol)
  "Return a name (string) of a parameter.
PARAM-SYMBOL is a symbol from `aurel-pacman-param-alist'."
  (cdr (assoc param-symbol aurel-pacman-param-alist)))

(defun aurel-get-pacman-param-symbol (param-name)
  "Return a symbol name of a parameter.
PARAM-NAME is a string from `aurel-pacman-param-alist'."
  (car (rassoc param-name aurel-pacman-param-alist)))


;;; Filters for processing package info

(defvar aurel-filter-params nil
  "List of parameters (symbols), that should match specified strings.
Used in `aurel-filter-contains-every-string'.")

(defvar aurel-filter-strings nil
  "List of strings, a package info should match.
Used in `aurel-filter-contains-every-string'.")

(defvar aurel-aur-filters
  '(aurel-aur-filter-intern
    aurel-filter-contains-every-string
    aurel-filter-pkg-url)
  "List of filter functions applied to a package info got from AUR.

Each filter function should accept a single argument - info alist
with package parameters and should return info alist or
nil (which means: ignore this package info).  Functions may
modify associations or add the new ones to the alist.  In the
latter case you might want to add descriptions of the added
symbols into `aurel-titles'.

`aurel-aur-filter-intern' should be the first symbol in the list as
other filters use symbols for working with info parameters (see
`aurel-aur-param-alist').

For more information, see `aurel-receive-packages-info'.")

(defvar aurel-pacman-filters
  '(aurel-pacman-filter-intern
    aurel-pacman-filter-none)
"List of filter functions applied to a package info got from pacman.

`aurel-pacman-filter-intern' should be the first symbol in the list as
other filters use symbols for working with info parameters (see
`aurel-pacman-param-alist').

For more information, see `aurel-aur-filters' and
`aurel-receive-packages-info'.")

(defvar aurel-final-filters
  '()
  "List of filter functions applied to a package info.
For more information, see `aurel-receive-packages-info'.")

(defun aurel-apply-filters (info filters)
  "Apply functions from FILTERS list to a package INFO.

INFO is alist with package parameters.  It is passed as an
argument to the first function from FILTERS, the returned result
is passed to the second function from that list and so on.

Return filtered info (result of the last filter).  Return nil, if
one of the FILTERS returns nil (do not call the rest filters)."
  (cl-loop for fun in filters
           do (setq info (funcall fun info))
           while info
           finally return info))

(defun aurel-filter-intern (info param-fun &optional warning)
  "Replace names of parameters with symbols in a package INFO.
INFO is alist of parameter names (strings) and values.
PARAM-FUN is a function for getting parameter internal symbol by
its name (string).
If WARNING is non-nil, show a message if unknown parameter is found.
Return modified info."
  (delq nil
        (mapcar
         (-lambda ((param-name . param-val))
           (let ((param-symbol (funcall param-fun param-name)))
             (if param-symbol
                 (cons param-symbol param-val)
               (when warning
                 (message "\
Warning: unknown parameter '%s'. It will be omitted."
                          param-name))
               nil)))
         info)))

(defun aurel-aur-filter-intern (info)
  "Replace names of parameters with symbols in a package INFO.
INFO is alist of parameter names (strings) from
`aurel-aur-param-alist' and their values.
Return modified info."
  (aurel-filter-intern info 'aurel-get-aur-param-symbol t))

(defun aurel-pacman-filter-intern (info)
  "Replace names of parameters with symbols in a package INFO.
INFO is alist of parameter names (strings) from
`aurel-pacman-param-alist' and their values.
Return modified info."
  (aurel-filter-intern info 'aurel-get-pacman-param-symbol))

(defun aurel-pacman-filter-none (info)
  "Replace `aurel-none-string' values in pacman INFO with nil."
  (mapcar (-lambda ((name . val))
            (cons name
                  (unless (string= val aurel-none-string) val)))
          info))

(defun aurel-filter-contains-every-string (info)
  "Check if a package INFO contains all necessary strings.

Return INFO, if values of parameters from `aurel-filter-params'
contain all strings from `aurel-filter-strings', otherwise return nil.

Pass the check (return INFO), if `aurel-filter-strings' or
`aurel-filter-params' is nil."
  (when (or (null aurel-filter-params)
            (null aurel-filter-strings)
            (let ((str (mapconcat (lambda (param)
                                    (bui-entry-value info param))
                                  aurel-filter-params
                                  "\n")))
              (cl-every (lambda (substr)
                          (string-match-p (regexp-quote substr) str))
                        aurel-filter-strings)))
    info))

(defun aurel-filter-pkg-url (info)
  "Update `pkg-url' parameter in a package INFO.
INFO is alist of parameter symbols and values.
Return modified info."
  (let ((param (assoc 'pkg-url info)))
    (setcdr param (url-expand-file-name (cdr param) aurel-aur-base-url)))
  info)


;;; Searching/showing packages

(defun aurel-receive-packages-info (url)
  "Return information about the packages from URL.

Information is received with `aurel-get-aur-packages-info', then
it is passed through `aurel-aur-filters' with
`aurel-apply-filters'.  If `aurel-installed-packages-check' is
non-nil, additional information about installed packages is
received with `aurel-get-installed-packages-info' and is passed
through `aurel-installed-filters'.  Finally packages info is passed
through `aurel-final-filters'.

Returning value is alist of (ID . PACKAGE-ALIST) entries."
  ;; To speed-up the process, pacman should be called once with the
  ;; names of found packages (instead of calling it for each name).  So
  ;; we need to know the names at first, that's why we don't use a
  ;; single filters variable: at first we filter info received from AUR,
  ;; then we add information about installed packages from pacman and
  ;; finally filter the whole info.
  (let (aur-info-list aur-info-alist
        pac-info-list pac-info-alist
        info-list)
    ;; Receive and process information from AUR server
    (setq aur-info-list  (aurel-get-aur-packages-info url)
          aur-info-alist (aurel-get-filtered-alist
                          aur-info-list aurel-aur-filters 'name))
    ;; Receive and process information from pacman
    (when aurel-installed-packages-check
      (setq pac-info-list  (apply 'aurel-get-installed-packages-info
                                  (mapcar #'car aur-info-alist))
            pac-info-alist (aurel-get-filtered-alist
                            pac-info-list
                            aurel-pacman-filters
                            'installed-name)))
    ;; Join info and do final processing
    (setq info-list
          (mapcar (lambda (aur-info-assoc)
                    (let* ((name (car aur-info-assoc))
                           (pac-info-assoc (assoc name pac-info-alist)))
                      (append (cdr aur-info-assoc)
                              (cdr pac-info-assoc))))
                  aur-info-alist))
    (aurel-get-filtered-alist info-list aurel-final-filters 'id)))

(defun aurel-get-filtered-alist (info-list filters param)
  "Return alist with filtered packages info.
INFO-LIST is a list of packages info.  Each info is passed through
FILTERS with `aurel-apply-filters'.

Each association of a returned value has a form:

  (PARAM-VAL . INFO)

PARAM-VAL is a value of a parameter PARAM.
INFO is a filtered package info."
  (delq nil                             ; ignore filtered (empty) info
        (mapcar (lambda (info)
                  (let ((info (aurel-apply-filters info filters)))
                    (and info
                         (cons (bui-entry-value info param) info))))
                info-list)))

(defun aurel-get-packages-by-name (&rest names)
  "Return packages by package NAMES (list of strings)."
  (aurel-receive-packages-info
   (apply #'aurel-get-package-info-url names)))

(defun aurel-get-packages-by-string (&rest strings)
  "Return packages matching STRINGS."
  ;; A hack for searching by multiple strings: the actual server search
  ;; is done by the biggest string and the rest strings are searched in
  ;; the results returned by the server
  (let* ((str-list
          ;; sort to search by the biggest (first) string
          (sort strings
                (lambda (a b)
                  (> (length a) (length b)))))
         (aurel-filter-params '(name description))
         (aurel-filter-strings (cdr str-list)))
    (aurel-receive-packages-info
     (aurel-get-package-search-url (car str-list)))))

(defun aurel-get-packages-by-name-string (string)
  "Return packages with name containing STRING."
  (aurel-receive-packages-info
   (aurel-get-package-name-search-url string)))

(defun aurel-get-packages-by-maintainer (name)
  "Return packages by maintainer NAME."
  (aurel-receive-packages-info
   (aurel-get-maintainer-search-url name)))

(defvar aurel-search-type-alist
  '((name       . aurel-get-packages-by-name)
    (string     . aurel-get-packages-by-string)
    (name-string . aurel-get-packages-by-name-string)
    (maintainer . aurel-get-packages-by-maintainer))
  "Alist of available search types and search functions.")

(defun aurel-search-packages (type &rest vals)
  "Search for AUR packages and return results.
TYPE is a type of search - symbol from `aurel-search-type-alist'.
It defines a search function which is called with VALS as
arguments."
  (let ((fun (cdr (assoc type aurel-search-type-alist))))
    (or fun
        (error "Wrong search type '%s'" type))
    (apply fun vals)))

(defun aurel-search-packages-with-user-info (type &rest vals)
  "Search for AUR packages and return results.
This is like `aurel-search-packages' but also add AUR user info
depending on `aurel-aur-user-package-info-check'."
  (let ((entries (apply #'aurel-search-packages type vals)))
    (if aurel-aur-user-package-info-check
        (mapcar #'aurel-add-aur-user-package-info entries)
      entries)))

(defun aurel-search-show-packages (search-type &rest search-vals)
  "Search for packages and show results.
See `aurel-search-packages' for the meaning of SEARCH-TYPE and
SEARCH-VALS."
  (apply #'bui-list-get-display-entries
         'aurel search-type search-vals))

(defvar aurel-found-messages
  '((name       (0    "The package \"%s\" not found." "Packages not found.")
                (1    "The package \"%s\"."))
    (string     (0    "No packages matching %s.")
                (1    "A single package matching %s.")
                (many "%d packages matching %s."))
    (maintainer (0    "No packages by maintainer %s.")
                (1    "A single package by maintainer %s.")
                (many "%d packages by maintainer %s.")))
  "Alist used by `aurel-found-message'.")

(defun aurel-found-message (packages search-type &rest search-vals)
  "Display a proper message about found PACKAGES.
SEARCH-TYPE and SEARCH-VALS are arguments for
`aurel-search-packages', by which the PACKAGES were found."
  (let* ((count (length packages))
         (found-key (if (> count 1) 'many count))
         (type-alist (cdr (assoc search-type aurel-found-messages)))
         (found-list (cdr (assoc found-key type-alist)))
         (msg (if (or (= 1 (length search-vals))
                      (null (cdr found-list)))
                  (car found-list)
                (cadr found-list)))
         (args (delq nil
                     (list
                      (and (eq found-key 'many) count)
                      (cond
                       ((eq search-type 'string)
                        (mapconcat (lambda (str) (concat "\"" str "\""))
                                   search-vals " "))
                       ((and (= count 1) (eq search-type 'name))
                        (bui-entry-value (cdar packages) 'name))
                       (t (car search-vals)))))))
    (and msg (apply 'message msg args))))


;;; Downloading

(defcustom aurel-download-directory temporary-file-directory
  "Default directory for downloading AUR packages."
  :type 'directory
  :group 'aurel)

(defcustom aurel-directory-prompt "Download to: "
  "Default directory prompt for downloading AUR packages."
  :type 'string
  :group 'aurel)

(defvar aurel-download-functions
  '(aurel-download aurel-download-unpack aurel-download-unpack-dired
    aurel-download-unpack-pkgbuild aurel-download-unpack-eshell)
  "List of available download functions.")

(defun aurel-read-download-directory ()
  "Return `aurel-download-directory' or prompt for it.
This function is intended for using in `interactive' forms."
  (if current-prefix-arg
      (read-directory-name aurel-directory-prompt
                           aurel-download-directory)
    aurel-download-directory))

(defun aurel-download-get-defcustom-type ()
  "Return `defcustom' type for selecting a download function."
  `(radio ,@(mapcar (lambda (fun) (list 'function-item fun))
                    aurel-download-functions)
          (function :tag "Other function")))

(defun aurel-download (url dir)
  "Download AUR package from URL to a directory DIR.
Return a path to the downloaded file."
  ;; Is there a simpler way to download a file?
  (let ((file-name-handler-alist
         (cons (cons url-handler-regexp 'url-file-handler)
               file-name-handler-alist)))
    (with-temp-buffer
      (insert-file-contents-literally url)
      (let ((file (expand-file-name (url-file-nondirectory url) dir)))
        (write-file file)
        file))))

;; Code for working with `tar-mode' came from `package-untar-buffer'

;; Avoid compilation warnings about tar functions and variables
(defvar tar-parse-info)
(defvar tar-data-buffer)
(declare-function tar-untar-buffer "tar-mode" ())
(declare-function tar-header-name "tar-mode" (tar-header) t)
(declare-function tar-header-link-type "tar-mode" (tar-header) t)

(defun aurel-tar-subdir (tar-info)
  "Return directory name where files from TAR-INFO will be extracted."
  (let* ((first-header (car tar-info))
         (first-header-type (tar-header-link-type first-header)))
    (cl-case first-header-type
      (55                               ; pax_global_header
       ;; There are other special headers (see `tar--check-descriptor', for
       ;; example).  Should they also be ignored?
       (aurel-tar-subdir (cdr tar-info)))
      (5                                ; directory
       (let* ((dir-name (tar-header-name first-header))
              (dir-re (regexp-quote dir-name)))
         (dolist (tar-data (cdr tar-info))
           (or (string-match dir-re (tar-header-name tar-data))
               (error (concat "Not all files are going to be extracted"
                              " into directory '%s'")
                      dir-name)))
         dir-name))
      (t
       (error "The first entry '%s' in tar file is not a directory"
              (tar-header-name first-header))))))

(defun aurel-download-unpack (url dir)
  "Download AUR package from URL and unpack it into a directory DIR.

Use `tar-untar-buffer' from Tar mode.  All files should be placed
in one directory; otherwise, signal an error.

Return a path to the unpacked directory."
  (let ((file-name-handler-alist
         (cons (cons url-handler-regexp 'url-file-handler)
               file-name-handler-alist)))
    (with-temp-buffer
      (insert-file-contents url)
      (setq default-directory dir)
      (let ((file (expand-file-name (url-file-nondirectory url) dir)))
        (write-file file))
      (tar-mode)
      (let ((tar-dir (aurel-tar-subdir tar-parse-info)))
        (tar-untar-buffer)
        (expand-file-name tar-dir dir)))))

(defun aurel-download-unpack-dired (url dir)
  "Download and unpack AUR package, and open the unpacked directory.
For the meaning of URL and DIR, see `aurel-download-unpack'."
  (dired (aurel-download-unpack url dir)))

(defun aurel-download-unpack-pkgbuild (url dir)
  "Download and unpack AUR package, and open PKGBUILD file.
For the meaning of URL and DIR, see `aurel-download-unpack'."
  (let* ((pkg-dir (aurel-download-unpack url dir))
         (file (expand-file-name "PKGBUILD" pkg-dir)))
    (if (file-exists-p file)
        (find-file file)
      (error "File '%s' doesn't exist" file))))

;; Avoid compilation warning about `eshell/cd'
(declare-function eshell/cd "em-dirs" (&rest args))

(defun aurel-download-unpack-eshell (url dir)
  "Download and unpack AUR package, switch to eshell.
For the meaning of URL and DIR, see `aurel-download-unpack'."
  (let ((pkg-dir (aurel-download-unpack url dir)))
    (eshell)
    (eshell/cd pkg-dir)))


;;; Defining URL

(defun aurel-get-fields-string (args)
  "Return string of names and values from ARGS alist.
Each association of ARGS has a form: (NAME . VALUE).
If NAME and VALUE are not strings, they are converted to strings
with `prin1-to-string'.
Returning string has a form: \"NAME=VALUE&...\"."
  (cl-flet ((hexify (arg)
                    (url-hexify-string
                     (if (stringp arg) arg (prin1-to-string arg)))))
    (mapconcat (lambda (arg)
                 (concat (car arg)
                         "="
                         (hexify (cdr arg))))
               args
               "&")))

(defun aurel-get-rpc-url (type args)
  "Return URL for getting info about AUR packages.
TYPE is the name of an allowed method.
ARGS should have a form taken by `aurel-get-fields-string'."
  (url-expand-file-name
   (concat "rpc/?"
           (aurel-get-fields-string
            (append `(("v" . "5") ; v5 of the RPC API.
                      ("type" . ,type))
                    args)))
   aurel-aur-base-url))

(defun aurel-get-package-info-url (&rest names)
  "Return URL for getting info about packages with NAMES."
  (let ((args (mapcar (lambda (name)
                        (cons "arg[]" name))
                      names)))
    (aurel-get-rpc-url "info" args)))

(defun aurel-get-package-search-url (str &optional field)
  "Return URL for searching a package by string STR.
FIELD is a field (string) for searching.  May be: 'name',
'name-desc' (default) or 'maintainer'."
  (or field (setq field "name-desc"))
  (aurel-get-rpc-url
   "search"
   `(("by" . ,field)
     ("arg" . ,str))))

(defun aurel-get-package-name-search-url (str)
  "Return URL for searching a package name by string STR."
  (aurel-get-package-search-url str "name"))

(defun aurel-get-maintainer-search-url (str)
  "Return URL for searching a maintainer by string STR."
  (aurel-get-package-search-url str "maintainer"))

(defun aurel-get-maintainer-account-url (maintainer)
  "Return URL for MAINTAINER's AUR account."
  (url-expand-file-name (concat "account/" maintainer)
                        aurel-aur-base-url))

(defun aurel-get-aur-package-url (package)
  "Return AUR URL of a PACKAGE."
  (url-expand-file-name (concat "packages/" package)
                        aurel-aur-base-url))

(defun aurel-get-package-base-url (package-base)
  "Return AUR URL of a PACKAGE-BASE."
  (url-expand-file-name (concat "pkgbase/" package-base)
                        aurel-aur-base-url))

(defun aurel-get-package-action-url (package-base action)
  "Return URL for the PACKAGE-BASE ACTION."
  (concat (aurel-get-package-base-url package-base)
          "/" action))


;;; UI

(defvar aurel-package-info-history nil
  "A history list for `aurel-package-info'.")

(defvar aurel-package-search-history nil
  "A history list for `aurel-package-search'.")

(defvar aurel-maintainer-search-history nil
  "A history list for `aurel-maintainer-search'.")

;;;###autoload
(defun aurel-package-info (name)
  "Display information about AUR package with NAME."
  (interactive
   (list (read-string "Name: "
                      nil 'aurel-package-info-history)))
  (aurel-search-show-packages 'name name))

;;;###autoload
(defun aurel-package-search (string)
  "Search for AUR packages matching STRING.

STRING can be a string of multiple words separated by spaces.  To
search for a string containing spaces, quote it with double
quotes.  For example, the following search is allowed:

  \"python library\" plot"
  (interactive
   (list (read-string "Search by name/description: "
                      nil 'aurel-package-search-history)))
  (apply #'aurel-search-show-packages
         'string (split-string-and-unquote string)))

;;;###autoload
(defun aurel-package-search-by-name (string)
  "Search for AUR packages with name containing STRING."
  (interactive
   (list (read-string "Search by name: "
                      nil 'aurel-package-search-history)))
  (aurel-search-show-packages 'name-string string))

;;;###autoload
(defun aurel-maintainer-search (name)
  "Search for AUR packages by maintainer NAME."
  (interactive
   (list (read-string "Search by maintainer: "
                      nil 'aurel-maintainer-search-history)))
  (aurel-search-show-packages 'maintainer name))

;;;###autoload
(defun aurel-installed-packages ()
  "Display information about AUR packages installed in the system."
  (interactive)
  (apply #'aurel-search-show-packages
         'name (aurel-get-foreign-packages)))


;;; Filtering packages

(defvar aurel-available-filters
  '(aurel-filter-maintained
    aurel-filter-unmaintained
    aurel-filter-outdated
    aurel-filter-not-outdated
    aurel-filter-match-regexp
    aurel-filter-not-match-regexp
    aurel-filter-different-versions
    aurel-filter-same-versions)
  "List of commands that can be called for filtering a package list.
Used by `aurel-enable-filter'.")

(defvar aurel-filter-map
  (let ((map (make-sparse-keymap)))
    (set-keymap-parent map bui-filter-map)
    (define-key map (kbd "f") 'aurel-enable-filter)
    (define-key map (kbd "v") 'aurel-filter-same-versions)
    (define-key map (kbd "V") 'aurel-filter-different-versions)
    (define-key map (kbd "m") 'aurel-filter-unmaintained)
    (define-key map (kbd "M") 'aurel-filter-maintained)
    (define-key map (kbd "o") 'aurel-filter-outdated)
    (define-key map (kbd "O") 'aurel-filter-not-outdated)
    (define-key map (kbd "r") 'aurel-filter-not-match-regexp)
    (define-key map (kbd "R") 'aurel-filter-match-regexp)
    map)
  "Keymap with filter commands for `aurel-list-mode'.")
(fset 'aurel-filter-map aurel-filter-map)

(defun aurel-package-maintained? (entry)
  "Return non-nil, if package ENTRY has a maintainer."
  (bui-entry-non-void-value entry 'maintainer))

(defun aurel-package-unmaintained? (entry)
  "Return non-nil, if package ENTRY does not have a maintainer."
  (not (aurel-package-maintained? entry)))

(defun aurel-package-outdated? (entry)
  "Return non-nil, if package ENTRY is outdated."
  (bui-entry-non-void-value entry 'outdated))

(defun aurel-package-not-outdated? (entry)
  "Return non-nil, if package ENTRY is not outdated."
  (not (aurel-package-outdated? entry)))

(defun aurel-package-same-versions? (entry)
  "Return non-nil, if package ENTRY has the same installed and
available AUR versions."
  (equal (bui-entry-non-void-value entry 'version)
         (bui-entry-non-void-value entry 'installed-version)))

(defun aurel-package-different-versions? (entry)
  "Return non-nil, if package ENTRY has different installed and
available AUR versions."
  (not (aurel-package-same-versions? entry)))

(defun aurel-package-matching-regexp? (entry regexp)
  "Return non-nil, if package ENTRY's name or description match REGEXP."
  (or (string-match-p regexp (bui-entry-non-void-value entry 'name))
      (string-match-p regexp (bui-entry-non-void-value entry 'description))))

(defun aurel-package-not-matching-regexp? (entry regexp)
  "Return non-nil, if package ENTRY's name or description do not match REGEXP."
  (not (aurel-package-matching-regexp? entry regexp)))

(defun aurel-enable-filter (arg)
  "Prompt for a function for filtering package list and call it.
Choose candidates from `aurel-available-filters'.
If ARG is non-nil (with prefix), make selected filter the only
active one (remove other filters)."
  (interactive "P")
  (let ((fun (intern (completing-read
                      (if current-prefix-arg
                          "Add filter: "
                        "Enable filter: ")
                      aurel-available-filters))))
    (or (fboundp fun)
        (error "Wrong function %s" fun))
    (funcall fun arg)))

(defun aurel-filter-maintained (arg)
  "Filter current list by hiding maintained packages.
See `aurel-enable-filter' for the meaning of ARG."
  (interactive "P")
  (bui-enable-filter 'aurel-package-unmaintained? arg))

(defun aurel-filter-unmaintained (arg)
  "Filter current list by hiding unmaintained packages.
See `aurel-enable-filter' for the meaning of ARG."
  (interactive "P")
  (bui-enable-filter 'aurel-package-maintained? arg))

(defun aurel-filter-outdated (arg)
  "Filter current list by hiding outdated packages.
See `aurel-enable-filter' for the meaning of ARG."
  (interactive "P")
  (bui-enable-filter 'aurel-package-not-outdated? arg))

(defun aurel-filter-not-outdated (arg)
  "Filter current list by hiding not outdated packages.
See `aurel-enable-filter' for the meaning of ARG."
  (interactive "P")
  (bui-enable-filter 'aurel-package-outdated? arg))

(defun aurel-filter-same-versions (arg)
  "Hide packages with the same installed and available AUR versions.
See `aurel-enable-filter' for the meaning of ARG."
  (interactive "P")
  (bui-enable-filter 'aurel-package-different-versions? arg))

(defun aurel-filter-different-versions (arg)
  "Hide packages with different installed and available AUR versions.
See `aurel-enable-filter' for the meaning of ARG."
  (interactive "P")
  (bui-enable-filter 'aurel-package-same-versions? arg))

(defun aurel-filter-match-regexp (arg)
  "Hide packages with names or descriptions matching prompted regexp.
See `aurel-enable-filter' for the meaning of ARG."
  (interactive "P")
  (let ((re (read-regexp "Hide packages matching regexp: ")))
    (bui-enable-filter
     (lambda (entry)
       (aurel-package-not-matching-regexp? entry re))
     arg)))

(defun aurel-filter-not-match-regexp (arg)
  "Hide packages with names or descriptions not matching prompted regexp.
See `aurel-enable-filter' for the meaning of ARG."
  (interactive "P")
  (let ((re (read-regexp "Hide packages not matching regexp: ")))
    (bui-enable-filter
     (lambda (entry)
       (aurel-package-matching-regexp? entry re))
     arg)))


;;; Minibuffer readers

(defun aurel-read-package-name (&optional entries)
  "Prompt for a package name and return it.
Names are completed from package ENTRIES."
  (completing-read "Package: "
                   (--map (bui-entry-value it 'name) entries)))

(defun aurel-read-entry-by-name (entries)
  "Prompt for a package name and return an entry with this name from ENTRIES."
  (pcase entries
    (`(,entry) entry)
    (_ (bui-entry-by-param entries 'name
                           (aurel-read-package-name entries)))))


;;; Common for 'list' and 'info'

(bui-define-entry-type aurel
  :message-function 'aurel-found-message
  :mode-init-function 'aurel-initialize
  :titles
  '((pkg-url             . "Package URL")
    (home-url            . "Home page")
    (aur-url             . "AUR page")
    (base-url            . "Package base")
    (last-date           . "Last modified")
    (first-date          . "Submitted")
    (outdated            . "Out of date")
    (base-name           . "Package base")
    (base-id             . "Package base ID")
    (depends             . "Depends on")
    (depends-make        . "Make deps")
    (conflicts           . "Conflicts with"))
  :filter-predicates
  '(aurel-package-maintained?
    aurel-package-unmaintained?
    aurel-package-outdated?
    aurel-package-not-outdated?
    aurel-package-different-versions?
    aurel-package-same-versions?)
  :boolean-params '(outdated))

(defun aurel-initialize ()
  "Set local variables common for aurel modes."
  (setq default-directory aurel-download-directory))


;;; Package list

(defcustom aurel-list-download-function 'aurel-download-unpack
  "Function used for downloading a single AUR package from list buffer.
It should accept 2 arguments: URL of a downloading file and a
destination directory."
  :type (aurel-download-get-defcustom-type)
  :group 'aurel-list)

(defcustom aurel-list-multi-download-function 'aurel-download-unpack
  "Function used for downloading multiple AUR packages from list buffer.
It should accept 2 arguments: URL of a downloading file and a
destination directory."
  :type (aurel-download-get-defcustom-type)
  :group 'aurel-list)

(defcustom aurel-list-multi-download-no-confirm nil
  "If non-nil, do not ask to confirm if multiple packages are downloaded."
  :type 'boolean
  :group 'aurel-list)

(bui-define-interface aurel list
  :buffer-name "*AUR Packages*"
  :mode-name "AURel-List"
  :get-entries-function 'aurel-search-packages
  :describe-function 'aurel-list-describe
  :titles '((installed-version . "Installed"))
  :format '((name aurel-list-get-name 30 t)
            (version nil 12 t)
            (installed-version nil 12 t)
            (maintainer aurel-list-get-maintainer 13 t)
            (votes nil 8 bui-list-sort-numerically-4 :right-align t)
            (popularity aurel-list-get-popularity 12 t)
            (description nil 30 nil))
  :hint 'aurel-list-hint
  :sort-key '(name))

(let ((map aurel-list-mode-map))
  (define-key map (kbd "d") 'aurel-list-download-package)
  (define-key map (kbd "f") 'aurel-filter-map))

(defvar aurel-list-default-hint
  '(("\\[aurel-list-download-package]") " download package(s);\n"))

(defun aurel-list-hint ()
  (bui-format-hints
   aurel-list-default-hint
   (bui-default-hint)))

(defun aurel-list-get-name (name entry)
  "Return package NAME.
Colorize the name with `aurel-info-outdated' if the package is
out of date."
  (bui-get-string name
                  (when (bui-entry-value entry 'outdated)
                    'aurel-info-outdated)))

(defun aurel-list-get-popularity (popularity &optional _)
  "Return formatted POPULARITY."
  ;; Display popularity in a decimal-point notation to avoid things like
  ;; "9.6e-05".
  (format "%10.4f" popularity))

(defun aurel-list-get-maintainer (name &optional _)
  "Return maintainer NAME specification for `tabulated-list-entries'."
  (bui-get-non-nil name
    (list name
          'face 'aurel-info-maintainer
          'action (lambda (btn)
                    (aurel-maintainer-search (button-label btn)))
          'follow-link t
          'help-echo "Find packages by this maintainer")))

(defun aurel-list-describe (&rest ids)
  "Describe packages with IDS."
  ;; A list of packages is received using 'search' type.  However, in
  ;; AUR RPC API, 'info' type returns several additional parameters
  ;; ("Depends", "Replaces", ...) comparing to the 'search' type.  So
  ;; re-receiving a package info (using 'info' type this time) is
  ;; needed.  Moreover, this API does not (!) provide a way to get info
  ;; by package IDs, so we have to search by names.
  (let* ((entries (bui-entries-by-ids (bui-current-entries) ids))
         (names   (--map (bui-entry-value it 'name)
                         entries)))
    (bui-get-display-entries 'aurel 'info (cons 'name names))))

(defun aurel-list-download-package ()
  "Download marked packages or the current package if nothing is marked.

With prefix, prompt for a directory with `aurel-directory-prompt'
to save the package; without prefix, save to
`aurel-download-directory' without prompting.

Use `aurel-list-download-function' if a single package is
downloaded or `aurel-list-multi-download-function' otherwise."
  (interactive)
  (let* ((dir (aurel-read-download-directory))
         (ids (or (bui-list-get-marked-id-list)
                  (list (bui-list-current-id))))
         (count (length ids)))
    (if (> count 1)
        (when (or aurel-list-multi-download-no-confirm
                  (y-or-n-p (format "Download %d marked packages? "
                                    count)))
          (mapcar (lambda (entry)
                    (funcall aurel-list-multi-download-function
                             (bui-entry-value entry 'pkg-url)
                             dir))
                  (bui-entries-by-ids (bui-current-entries) ids)))
      (funcall aurel-list-download-function
               (bui-entry-value (bui-entry-by-id (bui-current-entries)
                                                 (car ids))
                                'pkg-url)
               dir))))


;;; Package info

(defface aurel-info-id
  '((t))
  "Face used for ID of a package."
  :group 'aurel-info-faces)

(defface aurel-info-name
  '((t :inherit font-lock-keyword-face))
  "Face used for a name of a package."
  :group 'aurel-info-faces)

(defface aurel-info-maintainer
  '((t :inherit button))
  "Face used for a maintainer of a package."
  :group 'aurel-info-faces)

(defface aurel-info-version
  '((t :inherit font-lock-builtin-face))
  "Face used for a version of a package."
  :group 'aurel-info-faces)

(defface aurel-info-keywords
  '((t :inherit font-lock-comment-face))
  "Face used for keywords of a package."
  :group 'aurel-info-faces)

(defface aurel-info-description
  '((t))
  "Face used for a description of a package."
  :group 'aurel-info-faces)

(defface aurel-info-license
  '((t))
  "Face used for a license of a package."
  :group 'aurel-info-faces)

(defface aurel-info-votes
  '((t :weight bold))
  "Face used for a number of votes of a package."
  :group 'aurel-info-faces)

(defface aurel-info-popularity
  '((t))
  "Face used for popularity of a package."
  :group 'aurel-info-faces)

(defface aurel-info-voted-mark
  '((t :inherit aurel-info-voted))
  "Face used for `aurel-info-voted-mark' string."
  :group 'aurel-info-faces)

(defface aurel-info-outdated
  '((t :inherit font-lock-warning-face))
  "Face used if a package is out of date."
  :group 'aurel-info-faces)

(defface aurel-info-voted
  '((default :weight bold)
    (((class color) (min-colors 88) (background light))
     :foreground "ForestGreen")
    (((class color) (min-colors 88) (background dark))
     :foreground "PaleGreen")
    (((class color) (min-colors 8))
     :foreground "green")
    (t :underline t))
  "Face used if a package is voted."
  :group 'aurel-info-faces)

(defface aurel-info-not-voted
  '((t))
  "Face used if a package is not voted."
  :group 'aurel-info-faces)

(defface aurel-info-subscribed
  '((t :inherit aurel-info-voted))
  "Face used if a package is subscribed."
  :group 'aurel-info-faces)

(defface aurel-info-not-subscribed
  '((t :inherit aurel-info-not-voted))
  "Face used if a package is not subscribed."
  :group 'aurel-info-faces)

(defface aurel-info-date
  '((t :inherit font-lock-constant-face))
  "Face used for dates."
  :group 'aurel-info-faces)

(defface aurel-info-size
  '((t :inherit font-lock-variable-name-face))
  "Face used for size of installed package."
  :group 'aurel-info-faces)

(defface aurel-info-architecture
  '((t))
  "Face used for 'Architecture' parameter."
  :group 'aurel-info-faces)

(defface aurel-info-provides
  '((t :inherit font-lock-function-name-face))
  "Face used for 'Provides' parameter."
  :group 'aurel-info-faces)

(defface aurel-info-replaces
  '((t :inherit aurel-info-provides))
  "Face used for 'Replaces' parameter."
  :group 'aurel-info-faces)

(defface aurel-info-conflicts
  '((t :inherit aurel-info-provides))
  "Face used for 'Conflicts With' parameter."
  :group 'aurel-info-faces)

(defface aurel-info-depends
  '((t))
  "Face used for 'Depends On' parameter."
  :group 'aurel-info-faces)

(defface aurel-info-depends-make
  '((t))
  "Face used for 'Make Deps' parameter."
  :group 'aurel-info-faces)

(defface aurel-info-depends-opt
  '((t :inherit aurel-info-depends))
  "Face used for 'Optional Deps' parameter."
  :group 'aurel-info-faces)

(defface aurel-info-required
  '((t))
  "Face used for 'Required By' parameter."
  :group 'aurel-info-faces)

(defface aurel-info-optional-for
  '((t :inherit aurel-info-required))
  "Face used for 'Optional For' parameter."
  :group 'aurel-info-faces)

(defface aurel-info-packager
  '((t))
  "Face used for 'Packager' parameter."
  :group 'aurel-info-faces)

(defface aurel-info-validated
  '((t))
  "Face used for 'Validated By' parameter."
  :group 'aurel-info-faces)

(defface aurel-info-script
  '((t))
  "Face used for 'Install script' parameter."
  :group 'aurel-info-faces)

(defcustom aurel-info-download-function 'aurel-download-unpack-dired
  "Function used for downloading AUR package from package info buffer.
It should accept 2 arguments: URL of a downloading file and a
destination directory."
  :type (aurel-download-get-defcustom-type)
  :group 'aurel-info)

(defcustom aurel-info-voted-mark "*"
  "String inserted after the number of votes in info buffer.
See `aurel-info-display-voted-mark' for details."
  :type 'string
  :group 'aurel-info)

(defcustom aurel-info-display-voted-mark t
  "If non-nil, display `aurel-info-voted-mark' in info buffer.
It is displayed only if a package is voted by you (this
information is available if `aurel-aur-user-package-info-check'
is non-nil)."
  :type 'boolean
  :group 'aurel-info)

(defcustom aurel-info-installed-package-string
  "\nThis package is installed:\n\n"
  "String inserted in info buffer if a package is installed.
It is inserted after printing info from AUR and before info from pacman."
  :type 'string
  :group 'aurel-info)

(defcustom aurel-info-aur-user-string
  "\nAUR user account info:\n\n"
  "String inserted before printing info specific for AUR user."
  :type 'string
  :group 'aurel-info)

(bui-define-interface aurel info
  :buffer-name "*AUR Package Info*"
  :mode-name "AURel-Info"
  :get-entries-function 'aurel-search-packages-with-user-info
  :format '((name nil (simple aurel-info-name))
            nil
            (description nil (simple aurel-info-description))
            nil
            (pkg-url simple aurel-info-insert-package-url)
            (version format (simple aurel-info-version))
            (maintainer format aurel-info-insert-maintainer)
            (home-url format (format bui-url))
            aurel-info-insert-aur-url
            aurel-info-insert-base-url
            (provides format (format aurel-info-provides))
            (depends-make format (format aurel-info-depends-make))
            (depends format (format aurel-info-depends))
            (conflicts format (format aurel-info-conflicts))
            (replaces format (format aurel-info-replaces))
            (license format (format aurel-info-license))
            (keywords format (format aurel-info-keywords))
            (votes format aurel-info-insert-votes)
            (popularity format (simple aurel-info-popularity))
            (outdated format (time aurel-info-outdated))
            (first-date format (time aurel-info-date))
            (last-date format (time aurel-info-date))
            aurel-info-insert-pacman-info
            aurel-info-insert-aur-user-info)
  :hint 'aurel-info-hint)

(bui-define-interface aurel-pacman info
  :reduced? t
  :format '((installed-version format (simple aurel-info-version))
            (architecture format (simple aurel-info-architecture))
            (installed-size format (simple aurel-info-size))
            (installed-provides format (format aurel-info-provides))
            (installed-depends format (format aurel-info-depends))
            (depends-opt format (format aurel-info-depends-opt))
            (required format (format aurel-info-required))
            (optional-for format (format aurel-info-optional-for))
            (installed-conflicts format (format aurel-info-conflicts))
            (installed-replaces format (format aurel-info-replaces))
            (packager format (simple aurel-info-packager))
            (build-date format (time aurel-info-date))
            (install-date format (time aurel-info-date))
            (script format (format aurel-info-script))
            (validated format (format aurel-info-validated)))
  :titles
  '((installed-name      . "Name")
    (installed-version   . "Version")
    (installed-provides  . "Provides")
    (installed-depends   . "Depends on")
    (installed-conflicts . "Conflicts with")
    (installed-replaces  . "Replaces")
    (installed-size      . "Size")
    (depends-opt         . "Optional deps")
    (script              . "Install script")
    (reason              . "Install reason")
    (validated           . "Validated by")
    (required            . "Required by")))

(bui-define-interface aurel-user info
  :reduced? t
  :format '((voted format aurel-info-insert-voted)
            (subscribed format aurel-info-insert-subscribed)))

(let ((map aurel-info-mode-map))
  (define-key map (kbd "f") 'aurel-filter-map)
  (define-key map (kbd "d") 'aurel-info-download-package)
  (define-key map (kbd "v") 'aurel-info-vote-unvote)
  (define-key map (kbd "s") 'aurel-info-subscribe-unsubscribe))

(defvar aurel-info-default-hint
  '(("\\[aurel-info-download-package]") " download package;\n"
    ("\\[aurel-info-vote-unvote]") " vote/unvote;\n"
    ("\\[aurel-info-subscribe-unsubscribe]") " subscribe/unsubscribe;\n"))

(defun aurel-info-hint ()
  (bui-format-hints
   aurel-info-default-hint
   (bui-default-hint)))

(defun aurel-info-insert-votes (votes entry)
  "Insert the number of VOTES at point.
If `aurel-info-display-voted-mark' is non-nil, insert
`aurel-info-voted-mark' after."
  (bui-format-insert votes 'aurel-info-votes)
  (and aurel-info-display-voted-mark
       (--when-let (bui-entry-non-void-value entry 'user-info)
         (bui-entry-value it 'voted))
       (bui-format-insert aurel-info-voted-mark
                          'aurel-info-voted-mark)))

(define-button-type 'aurel-maintainer
  :supertype 'bui
  'face 'aurel-info-maintainer
  'follow-link t
  'help-echo "Browse maintainer's account"
  'action (lambda (btn)
            (browse-url (aurel-get-maintainer-account-url
                         (button-label btn)))))

(defun aurel-info-insert-maintainer (name &optional _)
  "Make button from maintainer NAME and insert it at point."
  (bui-insert-non-nil name
    (bui-insert-button name 'aurel-maintainer)
    (bui-insert-indent)
    (bui-insert-action-button
     "Packages"
     (lambda (btn)
       (aurel-maintainer-search (button-get btn 'maintainer)))
     "Find packages by this maintainer"
     'maintainer name)))

(defun aurel-info-insert-package-url (url &optional _)
  "Insert package URL and 'Download' button at point."
  (bui-insert-action-button
   "Download"
   (lambda (btn)
     (aurel-info-download-package (button-get btn 'url)
                                  (aurel-read-download-directory)))
   "Download this package"
   'url url)
  (bui-info-insert-value-indent url 'bui-url))

(defun aurel-info-insert-aur-url (entry)
  "Insert URL of the AUR package."
  (bui-info-insert-title-format (bui-info-param-title 'aurel 'aur-url))
  (bui-info-insert-value-simple
   (aurel-get-aur-package-url (bui-entry-value entry 'name))
   'bui-url)
  (bui-newline))

(defun aurel-info-insert-base-url (entry)
  "Insert URL of the AUR package base."
  (bui-info-insert-title-format (bui-info-param-title 'aurel 'base-url))
  (bui-info-insert-value-simple
   (aurel-get-package-base-url (bui-entry-value entry 'base-name))
   'bui-url)
  (bui-newline))

(defun aurel-info-insert-pacman-info (entry)
  "Insert installed (pacman) info from package ENTRY."
  (when (bui-entry-non-void-value entry 'installed-name)
    (insert aurel-info-installed-package-string)
    (bui-info-insert-entry entry 'aurel-pacman)))

(defun aurel-info-insert-aur-user-info (entry)
  "Insert AUR user info from package ENTRY."
  (--when-let (bui-entry-non-void-value entry 'user-info)
    (insert aurel-info-aur-user-string)
    (bui-info-insert-entry
     ;; Add 'base-name' as it is needed for Vote/Subscribe buttons.
     `((base-name . ,(bui-entry-value entry 'base-name))
       ,@it)
     'aurel-user)))

(defun aurel-info-insert-boolean (val &optional t-face nil-face)
  "Insert boolean value VAL at point.
If VAL is nil, use NIL-FACE, otherwise use T-FACE."
  (let ((face (if val t-face nil-face)))
    (insert (bui-get-string (or val bui-false-string) face))))

(defun aurel-info-aur-user-action-button (button)
  (aurel-info-aur-user-action (button-get button 'aur-action)
                              (button-get button 'base-name)))

(defun aurel-info-insert-voted (voted entry)
  "Insert VOTED parameter at point."
  (aurel-info-insert-boolean voted
                             'aurel-info-voted
                             'aurel-info-not-voted)
  (bui-insert-indent)
  (bui-insert-action-button
   (if voted "Unvote" "Vote")
   'aurel-info-aur-user-action-button
   (if voted
       "Remove your vote for this package"
     "Vote for this package")
   'base-name (bui-entry-value entry 'base-name)
   'aur-action (if voted 'unvote 'vote)))

(defun aurel-info-insert-subscribed (subscribed entry)
  "Insert SUBSCRIBED parameter at point."
  (aurel-info-insert-boolean subscribed
                             'aurel-info-subscribed
                             'aurel-info-not-subscribed)
  (bui-insert-indent)
  (bui-insert-action-button
   (if subscribed "Unsubscribe" "Subscribe")
   'aurel-info-aur-user-action-button
   (if subscribed
       "Unsubscribe from this package"
     "Subscribe to this package")
   'base-name (bui-entry-value entry 'base-name)
   'aur-action (if subscribed 'unsubscribe 'subscribe)))

(defun aurel-info-download-package (url dir)
  "Download package URL to DIR using `aurel-info-download-function'.
Interactively, download the current package.
With prefix, prompt for a directory with `aurel-directory-prompt'
to save the package; without prefix, save to
`aurel-download-directory' without prompting."
  (interactive
   (list (bui-entry-value (aurel-read-entry-by-name (bui-current-entries))
                          'pkg-url)
         (aurel-read-download-directory)))
  (funcall aurel-info-download-function url dir))

(defun aurel-info-aur-user-action (action package-base &optional norevert)
  "Perform AUR user ACTION on the current package.
See `aurel-aur-user-action' for the meaning of ACTION and PACKAGE-BASE.
If NOREVERT is non-nil, do not revert the buffer (i.e. do not
refresh package information) after ACTION."
  (and (aurel-aur-user-action action package-base)
       (null norevert)
       (revert-buffer nil t)))

(defun aurel-info-vote-unvote (arg)
  "Vote for the current package.
With prefix (if ARG is non-nil), unvote."
  (interactive "P")
  (aurel-info-aur-user-action
   (if arg 'unvote 'vote)
   (bui-entry-value (aurel-read-entry-by-name (bui-current-entries))
                    'base-name)))

(defun aurel-info-subscribe-unsubscribe (arg)
  "Subscribe to the new comments of the current package.
With prefix (if ARG is non-nil), unsubscribe."
  (interactive "P")
  (aurel-info-aur-user-action
   (if arg 'unsubscribe 'subscribe)
   (bui-entry-value (aurel-read-entry-by-name (bui-current-entries))
                    'base-name)))

(provide 'aurel)

;;; aurel.el ends here
