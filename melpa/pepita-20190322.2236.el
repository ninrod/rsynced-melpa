;;; pepita.el --- Run Splunk search commands, export results to CSV/HTML/JSON  -*- lexical-binding: t; -*-

;; Copyright (C) 2019 Sebastian Monia
;;
;; Author: Sebastian Monia <smonia@outlook.com>
;; URL: https://github.com/sebasmonia/pepita.git
;; Package-Version: 20190322.2236
;; Package-Requires: ((emacs "25") (csv "2.1"))
;; Version: 1.0
;; Keywords: tools convenience matching

;; This file is not part of GNU Emacs.

;;; License: MIT

;;; Commentary:

;; Runs a Splunk search from Emacs.  Returns the results as CSV, with option to export
;; to JSON and HTML.
;; The entry points are pepita-new-search and pepita-search-at-point
;; You will be prompted a query text, and time range for the query, and will get back
;; the results (when ready) in a new buffer.  In the results you can use:
;; j - to export to JSON
;; h - to export to HTML
;; ? - to see the parameters used in the query
;; g - to refresh the results buffer

;;; Code:

(require 'json)
(require 'cl-lib)
(require 'csv)

(defgroup pepita nil
  "Run a searche in Splunk from Emacs."
  :group 'extensions)

(defcustom pepita-splunk-url ""
  "URL of the Splunk services endpoint."
  :type 'string)

(defcustom pepita-splunk-username nil
  "Username, if empty it will be prompted."
  :type 'string)

(defcustom pepita-message-on-search-complete t
  "Show a message when search results are available."
  :type 'boolean)

(defcustom pepita--html-template "<HTML><HEAD>
  <link rel=\"stylesheet\" type=\"text/css\" href=\"https://cdn.datatables.net/1.10.19/css/jquery.dataTables.min.css\"/>
  <STYLE TYPE=\"text/css\">
      body { font-family: monospace; font-size: small; }
  </STYLE>
  <script type=\"text/javascript\" src=\"https://code.jquery.com/jquery-3.3.1.js\"></script>
  <script type=\"text/javascript\" src=\"https://cdn.datatables.net/1.10.19/js/jquery.dataTables.min.js\"></script>
  <script
   <script>
$(document).ready(function() {
    var table = $('#tbResults').DataTable( {
    } );

    $('th[col-index]').each(function (ndx, th) {
        $('#cols').append(\"<a col-index='\" + $(this).attr('col-index') + \"' href='#'>\" + th.innerText  + \"</a>  \") });

    $('a[col-index]').on( 'click', function (e) {
        e.preventDefault();

        // Get the column API object
        var column = table.column( $(this).attr('col-index') );

        // Toggle the visibility
        column.visible( ! column.visible() );

       table.columns.adjust().draw()
    } );
} );
  </script>
</HEAD>
<BODY>
Toggle column: <span id=\"cols\"> </span>
</br>
</br>
  <TABLE id=\"tbResults\" class=\"cell-border\" style=\"width: 100%%\">
    <THEAD>%s</THEAD>
    <TBODY>%s</TBODY>
    <TFOOT>%s</TFOOT>
  </TABLE>
</BODY></HTML>"
  "HTML used when exporting search results."
  :type 'string)


(defvar pepita--pending-requests (make-vector 20 nil) "Holds data for the pending requests.")
(defvar pepita--auth-header nil "Cached credentials for Splunk.")
(defvar pepita--last-search-parameters nil)

;; buffer local variables in results
(defvar-local pepita--search-parameters nil "Parameters used in the current Results buffer.")
;;------------------Package infrastructure----------------------------------------

(defun pepita--message (text)
  "Show a TEXT as a message and log it."
  (message text)
  (pepita--log "Message:" text "\n"))

(defun pepita--log (&rest to-log)
  "Append TO-LOG to the log buffer.  Intended for internal use only."
  (let ((log-buffer (get-buffer-create "*pepita-log*"))
        (text (cl-reduce (lambda (accum elem) (concat accum " " (prin1-to-string elem t))) to-log)))
    (with-current-buffer log-buffer
      (goto-char (point-max))
      (insert text)
      (insert "\n"))))

;;------------------HTTP Stuff----------------------------------------------------

(defun pepita--request (pri callback url &optional verb headers query-params data)
  "Retrieve the result of calling URL with HEADERS, QUERY-PARAMS and DATA using VERB (default GET), invoke CALLBACK with PRI when ready."
  ;; Modified from https://stackoverflow.com/a/15119407/91877
  (unless pepita-splunk-url
    (error "Missing URL"))
  (unless data
    (setq data ""))
  (setq url (concat pepita-splunk-url url))
  (push (pepita--get-auth-header) headers)
  (let ((url-request-extra-headers headers)
        (url-request-method (or verb "GET"))
        (url-request-data (encode-coding-string data 'utf-8)))
    (when query-params
      (setq url (concat url (pepita--build-querystring query-params))))
    (pepita--log (format "API call #%s - URL %s\n" pri url))
    (url-retrieve url callback (list pri))))

(defun pepita--build-querystring (params)
  "Convert PARAMS alist to an encoded query string."
  (concat "?"
          (mapconcat (lambda (pair)
                       (format "%s=%s"
                               (car pair)
                               (url-hexify-string (cdr pair))))
                     params
                     "&")))

(defun pepita--get-auth-header ()
  "Return the auth header.  Caches credentials per-session."
  (unless pepita--auth-header
    (let ((username (or pepita-splunk-username (read-string "Splunk username: ")))
          (password (read-passwd "Splunk password: ")))
      (setq pepita--auth-header (cons "Authorization"
                                      (concat "Basic "
                                              (base64-encode-string
                                               (format "%s:%s" username password)))))))
  pepita--auth-header)

(defun pepita-clear-cached-credentials ()
  "Clear current credentials, next request will prompt them again."
  (interactive)
  (setq pepita--auth-header nil)
  (pepita--message "Done. Next request will prompt for credentials."))


;;------------------Pending request management------------------------------------

(defun pepita--store-request-parameters (query from to out-buffer)
  "Store QUERY FROM TO OUT-BUFFER for a search and return their index."
  (condition-case nil
      (progn
        (let ((index 0)
              (params `((query . ,query)
                        (from . ,from)
                        (to . ,to)
                        (out-buffer . ,out-buffer))))
          (while (aref pepita--pending-requests index)
            (setq index (+ 1 index)))
          (aset pepita--pending-requests index params)
          (setq pepita--last-search-parameters params)
          index)) ;;return index
    (args-out-of-range (error "Too many pending requests"))))

(defun pepita--complete-request (index)
  "Clear INDEX from the list of pending requests, return the values."
  (let ((values (aref pepita--pending-requests index)))
    (aset pepita--pending-requests index nil)
    values))

;;------------------Search functions and internal commands------------------------

(defun pepita-search (query-text &optional from to out-buffer-name)
  "Run a Splunk search with QUERY-TEXT, between FROM and TO, if provided use OUT-BUFFER-NAME."
  (let ((method "search/jobs/export")
        (querystring  `((output_mode . "csv")
                        (max_time . "0")
                        (max_count . "10000")
                        (search . ,(concat "search " query-text))))
        (out-buffer (or out-buffer-name (generate-new-buffer-name "Splunk result" )))
        (pending-request-index nil))
    (unless (eq (length from) 0)
      (push (cons 'earliest_time from) querystring))
    (unless (eq (length to) 0)
      (push (cons 'latest_time to) querystring))
    (setq pending-request-index (pepita--store-request-parameters query-text from to out-buffer))
    (with-current-buffer (get-buffer-create out-buffer)
      (setq buffer-read-only nil)
      (erase-buffer)
      (insert (format "Search started %s\nQuery: %s\nFrom: %s\nTo: %s\n"
                      (format-time-string "%Y-%m-%d %T")
                      query-text
                      from
                      to)))
    (pepita--request pending-request-index
                     'pepita--search-cb
                     method
                     "GET"
                     nil
                     querystring)
    (unless out-buffer-name
      (switch-to-buffer-other-window out-buffer))))

(defun pepita--search-cb (_status pri)
  "Call back to process the data of PRI  from a Splunk search, _STATUS is ignored."
  ;; here we start in the http output buffer, briefly move to results to clear it, then copy the raw output
  ;; and finally go back to work on output
  (pepita--log (format "Results for %s: received %s lines of output" pri (count-lines (point-min) (point-max))))
  (delete-region (point-min) (+ 1 url-http-end-of-headers))
  (let-alist (pepita--complete-request pri)
    (with-current-buffer (get-buffer-create .out-buffer)
      (pepita-results-mode)
      (setq buffer-read-only nil)
      (setq pepita--search-parameters (list .query .from .to)))
    (if (= (buffer-size) 0)
        (progn
          (with-current-buffer (get-buffer-create .out-buffer)
            (goto-char (point-max))
            (insert (format "\nSearch completed %s -- No matches found"
                            (format-time-string "%Y-%m-%d %T")))
            (setq buffer-read-only t)))
      (progn
        ;; erase results buffer
        (with-current-buffer (get-buffer-create .out-buffer)
          (setq buffer-read-only nil)
          (erase-buffer)) ;; remove old text
        (copy-to-buffer .out-buffer (point-min) (point-max))
        (with-current-buffer .out-buffer
          ;; unquote all field names, makes things easier later
          ;; replace first line, then re-insert it, delete old line
          (goto-char (point-min))
          (insert (replace-regexp-in-string "\"" "" (thing-at-point 'line)))
          (delete-region (point) (search-forward "\n" nil t))
          (goto-char (point-min))
          (setq buffer-read-only t)
          (when pepita-message-on-search-complete
            (pepita--message (concat "Pepita: Results available in buffer " .out-buffer)))))))
    (kill-buffer)) ;; this kills the original url.el output buffer

(defun pepita--rerun-query (arg)
  "Re-run the current query.  If ARG, run it in a new buffer."
  (interactive "P")
  (let ((out-buf-name (if arg nil (buffer-name))))
    (destructuring-bind (query from to) pepita--search-parameters
      (pepita-search query
                     from
                     to
                     out-buf-name))))

(defun pepita--search-parameters ()
  "Show a message with the parameters used to run the search in this buffer."
  (interactive)
  (destructuring-bind (query from to) pepita--search-parameters
    (message "Query: \"%s\". \nEvents from %s to %s"
             query
             (if (equal from "")
                 "-"
               from)
             (if (equal to "")
                 "-"
               to))))

;;------------------Search - interactive commands---------------------------------

(defun pepita-search-at-point (arg)
  "Search using the region or line at point as query.  With ARG use last search parameters as starting point."
  (interactive "P")
  (pepita--read-and-search (if (use-region-p)
                               (buffer-substring-no-properties (region-beginning) (region-end))
                             (substring (thing-at-point 'line t) 0 -1))
                           arg))

(defun pepita-new-search (arg)
  "Run a search.  With ARG use last search parameters as starting point."
  (interactive "P")
  (pepita--read-and-search "" arg))

(defun pepita--read-and-search (initial-input use-last)
  "Read the params for a search using INITIAL-INPUT, feed from last query if USE-LAST."
  (let-alist pepita--last-search-parameters
    (pepita-search (read-string "Query term: " (concat (when use-last .query) " " initial-input))
                   (read-string "Events from: " (when use-last .from))
                   (read-string "Events to: " (when use-last .to)))))

;;------------------Export functions----------------------------------------------

(defun pepita--export-field-list ()
  "Helper invoked by export functions to get the list of fields."
  (save-excursion
    ;; go to first line to get the list of fields
    (goto-char (point-min))
    (let* ((field-list (split-string (substring
                                     (thing-at-point 'line t)
                                     0
                                     -1)
                                    ","))
          (selection (completing-read-multiple "Select fields to filter, separate by comma, blank for [ALL]: "
                                               field-list
                                               nil
                                               t)))
      (if selection
          selection
        field-list))))


(defun pepita--cleanup-row (field-list row)
  "Format ROW with only the values in FIELD-LIST."
  (cl-remove-if-not (lambda (pair)
                      (member (car pair) field-list)) row))

(defun pepita--filter-data-for-export ()
  "Filter data in the current buffer to export it."
  (let ((field-list (pepita--export-field-list))
        (all-data (csv-parse-buffer t)))
    (mapcar (lambda (row) (pepita--cleanup-row field-list row)) all-data)))

(defun pepita--aliststr (field alist)
  "Return FIELD from ALIST using equal to compare."
  (alist-get field alist nil nil 'equal))

(defun pepita--export-json ()
  "Export the current buffer to a JSON file."
  (interactive)
  (save-excursion
    (let ((data (pepita--filter-data-for-export))
          (json-buffer (concat (buffer-name) ".json")))
      (with-current-buffer (get-buffer-create json-buffer)
        (insert (json-encode data))
        (json-mode)
        (json-mode-beautify)
        (switch-to-buffer json-buffer)))))

(defun pepita--export-html ()
  "Export the current buffer to an HTML table."
  (interactive)
  (save-excursion
    (let ((data (pepita--filter-data-for-export))
          (html-file-name (concat (make-temp-file "Pepita-")
                                  ".html")))
      (let ((header (pepita--make-html-header data))
            (footer (pepita--make-html-footer data))
            (rows (pepita--make-html-rows data)))
        (with-temp-file html-file-name
          (insert (format pepita--html-template header rows footer)))
        (browse-url (concat "file:///" html-file-name))))))

(defun pepita--make-html-header (data)
  "Create the table header using DATA."
  (let ((cell-template "<TH col-index=\"%s\">%s</TH>")
        (col-index -1)
        (first-row (car data)))
    (mapconcat (lambda (cell)
                 (setq col-index (+ 1 col-index))
                 (format cell-template
                                      col-index
                                      (car cell)))
               first-row "")))

(defun pepita--make-html-footer (data)
  "Create the table footer using DATA."
  (let ((cell-template "<TH>%s</TH>")
        (first-row (car data)))
    (mapconcat (lambda (cell) (format cell-template (car cell))) first-row "")))

(defun pepita--make-html-rows (data)
  "Create the table rows using DATA."
  (mapconcat (lambda (row) (format "<TR>%s</TR>" (pepita--make-html-cells row))) data ""))

(defun pepita--make-html-cells (row)
  "Create individual cells for ROW."
  (mapconcat (lambda (cell) (format "<TD>%s</TD>" (cdr cell))) row ""))

(defvar pepita-results-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map "?" 'pepita--search-parameters)
    (define-key map "h" 'pepita--export-html)
    (define-key map "j" 'pepita--export-json)
    (define-key map "g" 'pepita--rerun-query)
    map) "Keymap for pepita-results-mode.")

(define-derived-mode pepita-results-mode
  fundamental-mode "Splunk results"
  "Major mode for Splunk results buffers.")

(provide 'pepita)
;;; pepita.el ends here
