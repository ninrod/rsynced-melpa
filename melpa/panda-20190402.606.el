;;; panda.el --- Client for Bamboo's REST API.  -*- lexical-binding: t; -*-

;; Copyright (C) 2019 Sebastian Monia
;;
;; Author: Sebastian Monia <smonia@outlook.com>
;; URL: https://github.com/sebasmonia/panda
;; Package-Version: 20190402.606
;; Package-Requires: ((emacs "25"))
;; Version: 1.1
;; Keywords: maint tool

;; This file is not part of GNU Emacs.

;;; License: MIT

;;; Commentary:

;; Consume Bamboo's terrible REST API to do useful things
;;
;; Steps to setup:
;;   1. Place panda.el in your load-path.  Or install from MELPA.
;;   2. Customize 'panda' to add the Bamboo URL or manually:
;;      (setq 'panda-api-url "https://bamboo.yourorg.com/rest/api/latest"))
;;      - No trailing / -
;;   3. There's a keymay provided for convenience
;;       (require 'panda)
;;        (global-set-key (kbd "C-c b") 'panda-map) ;; b for "Bamboo"
;;
;; For a detailed user manual see:
;; https://github.com/sebasmonia/panda/blob/master/README.md

;;; Code:

(require 'json)
(require 'cl-lib)
(require 'url)
(require 'browse-url)

(defgroup panda nil
  "Client for Bamboo's REST API."
  :group 'extensions)

(defcustom panda-api-url ""
  "Base URL of the Bamboo API, for example https://bamboo.my-company.com/rest/api/latest, no trailing slash!!!."
  :type 'string)

(defcustom panda-browser-url ""
  "URL to the Bamboo website, to launch a browser to view items.  For example https://bamboo.my-company.com, no trailing slash!!!."
  :type 'string)

(defcustom panda-username ""
  "Username, if empty it will be prompted."
  :type 'string)

(defcustom panda-less-messages nil
  "Display less messages in the echo area."
  :type 'boolean)

(defcustom panda-log-responses nil
  "Display API responses in the log.
Extremely useful for debugging but way too verbose for every day use."
  :type 'boolean)

;; consider making this an independent parameter
;; for builds and deployments
(defcustom panda-latest-max-results 7
  "How many items to retrieve when pulling lists of \"latest items\"."
  :type 'integer)

(defcustom panda-silence-url t
   "Ask url.el not to show messages."
   :type 'boolean)

(defcustom panda-api-timeout 30
   "Timeout for Bamboo API calls, in seconds."
   :type 'integer)

(defcustom panda-deploy-confirmation-regex ""
   "If an environment name matches the regex, Panda will request confirmation before submitting the deploy."
   :type 'string)

(defcustom panda-open-status-after-build 'ask
  "Open the build status for the corresponding branch after requesting a build.
If yes, automatically open it.  No to never ask.  Set to 'ask (default) to be prompted each time."
  :type '(choice (const :tag "No" nil)
                 (const :tag "Yes" t)
                 (const :tag "Ask" ask)))

(defcustom panda-open-status-after-deploy 'ask
  "Open the status for the corresponding project after requesting a deploy.
If yes, automatically open it.  No to never ask.  Set to 'ask (default) to be prompted each time."
  :type '(choice (const :tag "No" nil)
                 (const :tag "Yes" t)
                 (const :tag "Ask" ask)))

(defvar panda--auth-string nil "Caches the credentials for API calls.")
(defvar panda--projects-cache nil "Caches all the build projects the user has access to, in one go.")
(defvar panda--plans-cache nil "Caches the plans for each build project the user has access to, in one go.")
(defvar panda--branches-cache nil "Caches the branches for each plan, as they are requested.")
(defvar panda--deploys-cache nil "Caches the deployment projects (not build projects) in one single call to /deploy/project/all.")

(defvar panda--base-plan "[Master plan]")
(defvar panda--build-status-for-release "Successful")

(defvar panda--branch-key nil "Buffer local variable for panda--build-status-mode.")
(defvar panda--project-name nil "Buffer local variable for panda--deploy-results-mode.")
(defvar panda--deploy-project-id nil "Buffer local variable for panda--deploy-results-mode.")

(defvar panda--browse-build "/browse/%s" "What to add to 'panda-browser-url to open builds in the browser.")
(defvar panda--browse-deploy-project "/deploy/viewDeploymentProjectEnvironments.action?id=%s" "What to add to 'panda-browser-url to open deploy projects in the browser.")

(defvar panda--build-buffer-template "
Build key: %s

Project: %s
Master plan: %s
Plan name: %s

State: %s
Started: %s
Finished: %s
Duration: %s

Reason: %s
Build test summary: %s

Jira Issues:
%s

Changes:
%s

Artifacts:
%s" "Template to call 'format' for the build details buffer.")

(define-prefix-command 'panda-map)
;; Queue commands
(define-key panda-map (kbd "q b") 'panda-queue-build)
(define-key panda-map (kbd "q d") 'panda-queue-deploy)
;; Status commands
(define-key panda-map (kbd "s b") 'panda-build-results)
(define-key panda-map (kbd "s d") 'panda-deploy-status)
(define-key panda-map (kbd "s e") 'panda-environment-history)

;; Create
(define-key panda-map (kbd "c") 'panda-create-release)
;; Refresh
(define-key panda-map (kbd "r") 'panda-refresh-cache)
; Interactive commands not mapped:
;; panda-clear-credentials

;;------------------Package infrastructure----------------------------------------

(defun panda--message (text)
  "Show a TEXT as a message and log it, if 'panda-less-messages' log only."
  (unless panda-less-messages
    (message text))
  (panda--log "Package message:" text "\n"))

(defun panda--log (&rest to-log)
  "Append TO-LOG to the log buffer.  Intended for internal use only."
  (let ((log-buffer (get-buffer-create "*panda-log*"))
        (text (cl-reduce (lambda (accum elem) (concat accum " " (prin1-to-string elem t))) to-log)))
    (with-current-buffer log-buffer
      (goto-char (point-max))
      (insert text)
      (insert "\n"))))

;;------------------HTTP Stuff----------------------------------------------------

;; maybe change parameters order? url, method, qs params, data?
(defun panda--api-call (api-url &optional params method data)
  "Retrieve JSON result of calling API-URL with PARAMS and DATA using METHOD (default GET).  Return parsed objects."
  ;; Modified from https://stackoverflow.com/a/15119407/91877
  (unless panda-api-url
    (error "There's no API URL for Bamboo configured.  Try customize-group -> panda"))
  (unless data
    (setq data ""))
  (let ((url-request-extra-headers
         `(("Accept" . "application/json")
           ("Content-Type" . "application/json")
           ("Authorization" . ,(panda--auth-header))))
        (url-to-get (concat panda-api-url api-url "?os_authType=basic"))
        (url-request-method (or method "GET"))
        (url-request-data (encode-coding-string data 'utf-8))
        (json-false :false))
    (when params
      (setq url-to-get (concat url-to-get "&" params)))
    (panda--log "----- API call: " url-request-method "to "  url-to-get "with data" url-request-data " -----")
    (with-current-buffer (url-retrieve-synchronously url-to-get panda-silence-url nil panda-api-timeout)
      (when panda-log-responses
        (panda--log "API call response: " (buffer-string) "\n"))
      (goto-char url-http-end-of-headers)
      (let ((data 'error))
        (ignore-errors
          ;; if there's a problem parsing the JSON
          ;; data ==> 'error
          (setq data (json-read)))
        (kill-buffer) ;; don't litter with API buffers
        data))))

(defun panda--auth-header ()
  "Return the auth header.  Caches credentials per-session."
  (unless panda--auth-string
    (unless panda-username
      (setq panda-username (read-string "Bamboo username: ")))
    (let ((pass (read-passwd "Bamboo password: ")))
      (setq panda--auth-string
            (base64-encode-string
             (concat panda-username ":" pass)))
       (panda--log "Stored credentials for this session")))
  (concat "Basic " panda--auth-string))


;;------------------JSON traversal and list conversion----------------------------

(defun panda--agetstr (key alist)
  "Do 'alist-get' for KEY in ALIST with string keys."
  (alist-get key alist nil nil 'equal))

;;------------------Cache for projects, plans, and branches-----------------------

(defun panda-clear-credentials ()
  "Clear current credentials, next API call will request them again."
  (interactive)
  (setq panda--auth-string nil)
  (panda--message "Done. Next API call will request credentials."))

(defun panda-refresh-cache ()
  "Refresh the cache of projects, plans, and deploys."
  (interactive)
  (panda--refresh-cache-builds)
  (panda--refresh-cache-deploys))

(defun panda--refresh-cache-builds ()
  "Refresh the cache of projects and plans."
  (panda--message "Refreshing Bamboo build project and plan cache...")
  ;; If you have more than 10000 projects I doubt you are using this package
  (let* ((response (panda--api-call "/project" "expand=projects.project.plans&max-results=10000"))
         ;; convert vector to list
         (data (let-alist response (append .projects.project nil)))
         (project nil)
         (plans nil))
    (setq panda--projects-cache nil)
    (setq panda--plans-cache nil)
    (setq panda--branches-cache nil)
    (dolist (proj data)
      (let-alist proj
        (setq project (cons .name .key))
        (setq plans (mapcar (lambda (a-plan) (let-alist a-plan (cons .name .key)))
                            .plans.plan))
        (push project panda--projects-cache)
        (push (cons (cdr project) plans) panda--plans-cache)))
    (panda--message "Build cache updated!")))

(defun panda--refresh-cache-deploys ()
  "Refresh the cache of deploys."
  (panda--message "Refreshing Bamboo deployment cache...")
  (let* ((data (panda--api-call "/deploy/project/all"))
         (formatted (mapcar 'panda--format-deploy-entry data)))
    (setq panda--deploys-cache (cl-remove-if-not
                                ;; keep only the ones I can deploy to
                                ;; and have a valid plan
                                (lambda (deploy) (and (cddr deploy)
                                                      (car deploy)))
                                formatted)))
  (panda--message "Deploy cache updated!"))

(defun panda--format-deploy-entry (deploy-project)
  "Convert a DEPLOY-PROJECT to the cache format."
  (let-alist deploy-project
    (cons .name
          (cons .id
                (panda--format-environments-entry .environments)))))

(defun panda--format-environments-entry (deploy-envs)
  "Convert DEPLOY-ENVS to the cache format, only for allowedToExecute environments."
  (let ((as-list (append deploy-envs nil))
        (valid-envs nil))
    (dolist (environment as-list valid-envs)
      (let-alist environment
        (when .operations.allowedToExecute
          (push (list .name .id) valid-envs))))))

(defun panda--projects ()
  "Get cached list of projects, fetch them if needed."
  (unless panda--projects-cache
    (panda-refresh-cache))
  panda--projects-cache)

(defun panda--plans (project-key)
  "Get cached list of plans for a PROJECT-KEY, fetch plans if needed."
  (unless panda--plans-cache
    (panda-refresh-cache))
  (panda--agetstr project-key panda--plans-cache))

(defun panda--branches (plan-key)
  "Get cached list of branches for a PLAN-KEY, fetch and cache if needed."
  (let ((in-cache (panda--agetstr plan-key panda--branches-cache)))
    (unless in-cache
      (panda--message "Caching branches for plan...")
      (let* ((data (panda--api-call (concat "/plan/" plan-key "/branch")))
             (formatted nil))
        (let-alist data
          (setq formatted
                (mapcar (lambda (br) (let-alist br (cons .shortName .key)))
                        .branches.branch)))
        (push (cons panda--base-plan plan-key) formatted) ;; adding master plan
        (push (cons plan-key formatted) panda--branches-cache)
        (setq in-cache formatted)
        (panda--message "Caching branches for plan...")))
    in-cache))

(defun panda--deploys ()
  "Get cached list of deploy projects, fetch them if needed."
  (unless panda--deploys-cache
    (panda-refresh-cache))
  panda--deploys-cache)

(defun panda--all-environments ()
  "Return all environments from the cache, in a single list."
  (apply 'append (mapcar (lambda (deploy-project) (nthcdr 2 deploy-project))
                         (panda--deploys))))

;;------------------Common UI utilities-------------------------------------------

(defun panda--select-build-project ()
  "Run 'ido-completing-read' to select a project.  Return the project key."
  (let* ((projects (panda--projects))
         (selected (ido-completing-read "Select project: "
                                        (mapcar 'first projects))))
    (panda--agetstr selected projects)))

(defun panda--select-build-plan (project-key)
  "Run 'ido-completing-read' to select a plan under PROJECT-KEY.  Return the plan key."
  (let* ((plans (panda--plans project-key))
         (selected (ido-completing-read "Select plan: "
                                        (mapcar 'first plans))))
    (panda--agetstr selected plans)))

(defun panda--select-build-branch (plan-key)
  "Run 'ido-completing-read' to select a plan under PLAN-KEY  Return the branch key."
  (let* ((branches (panda--branches plan-key))
         (selected (ido-completing-read "Select branch: "
                                        (mapcar 'first branches))))
    (panda--agetstr selected branches)))

(defun panda--select-build-ppb (&optional project plan)
  "Select the project, plan and branch for a build and return the keys.
If provided PROJECT and PLAN won't be prompted."
  ;; if the plan is provided skip the project when not set
  (when (and (not project) plan)
    (setq project "--"))
  (let* ((project-key (or project (panda--select-build-project)))
         (plan-key (or plan (panda--select-build-plan project-key)))
         (branch-key (panda--select-build-branch plan-key)))
    (list project-key plan-key branch-key)))

(defun panda--select-deploy-project ()
  "Run 'ido-completing-read' to select a deploy project.  Return the project data."
  (let* ((deploy-names (mapcar 'car (panda--deploys)))
         (selected (ido-completing-read "Select deploy project: " deploy-names)))
    selected))

(defun panda--unixms-to-string (unix-milliseconds)
  "Convert UNIX-MILLISECONDS to date string.  I'm surprised this isn't a built in."
  (let ((format-str "%Y-%m-%d %T")
        (unix-epoch "1970-01-01T00:00:00+00:00")
        (converted "")
        (seconds nil))
    (condition-case nil
        (progn
          (setq seconds (/ unix-milliseconds 1000))
          (setq converted
                (format-time-string format-str
                                    (time-add (date-to-time unix-epoch)
                                              seconds))))
      (error (setq converted "")))
    converted))

(defun panda--browse (path)
  "Open the default browser using PATH."
  (unless panda-browser-url
    (error "There's no broser URL for Bamboo configured.  Try customize-group -> panda"))
  (browse-url (concat panda-browser-url path)))

;;------------------Build querying and information--------------------------------

(defun panda-display-build-info (build-key)
  "Show a buffer with the details of BUILD-KEY.  Invoked from build status list."
  (let* ((data (panda--api-call (concat "/result/" build-key)
                                "expand=changes,metadata,artifacts,comments,jiraIssues,variable,stages"))
         (buffer-name (concat "*Panda - Build details " build-key))
         (buffer (get-buffer-create buffer-name))
         (data-to-display nil))
    (let-alist data
      (setq data-to-display
            (list build-key
                  .projectName
                  (or .master.shortName "")
                  .planName
                  .state
                  .prettyBuildStartedTime
                  .prettyBuildCompletedTime
                  .buildDurationDescription
                  .buildReason
                  .buildTestSummary
                  (panda--build-info-format-jira-issues .jiraIssues.issue)
                  (panda--build-info-format-changes .changes.change)
                  "--")) ;; don't have any to test so...
      (with-current-buffer buffer
        (setq buffer-read-only nil)
        (kill-region (point-min) (point-max)) ;; in case of an update
        (insert (apply 'format panda--build-buffer-template data-to-display))
        (setq buffer-read-only t)
        (switch-to-buffer-other-window buffer)
        (panda--message (concat "Showing details for build " build-key))))))

(defun panda--build-info-format-jira-issues (issues)
  "Create a printable string out of ISSUES."
  (let ((to-concat (mapcar (lambda(x) (apply 'format "%s\t%s\t%s\t%s\t\"%s\""
                                             (let-alist x (list .key .issueType .status .asignee .summary))))
                           issues))
        (printable ""))
    (when to-concat
      (setq printable (mapconcat 'identity to-concat "\n")))
    printable)) ;; defaults to "" if no issues

(defun panda--build-info-format-changes (changes-list)
  "Create a printable string out of CHANGES-LIST."
  (let ((to-concat (mapcar (lambda(x) (apply 'format "%s\t%s"
                                             (let-alist x (list .changesetId .fullName))))
                           changes-list))
        (printable ""))
    (when to-concat
      (setq printable (mapconcat 'identity to-concat "\n")))
    printable)) ;; defaults to "" if no issues

;; TODO Make interactive version and write to buffer
(defun panda-get-build-info (build-name plan-key)
  "Retrieve the information of BUILD-NAME for PLAN-KEY."
  (let* ((split-data (split-string build-name "_"))
         (build-number (car (last split-data)))
         (branch-name (mapconcat 'identity (butlast split-data) "_")))
    (setq branch-name (replace-regexp-in-string "/" "-" branch-name))
    (unless (string= branch-name "develop")
      (setq plan-key (panda--agetstr branch-name (panda--branches plan-key))))
    (panda--api-call (concat "/result/" plan-key "-" build-number))))

(defun panda-queue-build (&optional plan)
  "Queue a build.  If PLAN is not provided, select it interactively."
  (interactive)
  (destructuring-bind (_project-key plan-key branch-key) (panda--select-build-ppb nil plan)
    (when (equal branch-key (concat plan-key "0"))
      ;; the base plan has a branch number of 0 but
      ;; won't build if using the prefix num
      (setq branch-key plan-key))
    (let ((show-status panda-open-status-after-build)) ;; later we'll check for 'ask or t
      (panda--api-call (concat "/queue/" branch-key) nil "POST")
      (when (eq panda-open-status-after-build 'ask)
        (setq show-status (y-or-n-p "Show build status for the branch? ")))
      (if show-status
          (panda-build-results-branch branch-key)
        (panda--message "Build queued")))))

(defun panda-build-results (&optional plan)
  "Fetch the build results for a branch under PLAN.
If PLAN is not provided, select it interactively.
The amount of builds to retrieve is controlled by 'panda-latest-max'."
  (interactive)
  (destructuring-bind (_project-key _plan-key branch-key) (panda--select-build-ppb nil plan)
    (panda-build-results-branch branch-key)))

(defun panda-build-results-branch (branch)
  "Fetch the build results for a BRANCH.  For interactive branch selection, use 'panda-build-results'."
  ;; only master plans return the build date on the top level call
  ;; the only option is to fetch the list of build keys and retrieve
  ;; the build date individually for each build
  (let* ((build-data (panda--build-results-data branch))
         (buffer-name (concat "*Panda - Latest builds " branch "*"))
         (buffer (get-buffer-create buffer-name)))
    (with-current-buffer buffer
      ;; setup the tablist
      (panda--build-results-mode)
      ;; buffer local variables
      (setq panda--branch-key branch)
      (setq tabulated-list-entries build-data)
      (tabulated-list-print)
      (local-set-key "g" (lambda ()
                           (interactive)
                           (setq tabulated-list-entries (panda--build-results-data panda--branch-key))
                           (tabulated-list-print)
                           (panda--message (concat "Updated list of builds for " panda--branch-key))))
      (local-set-key "d" (lambda ()
                           (interactive)
                           (panda-display-build-info (tabulated-list-get-id))))
      (local-set-key "b" (lambda ()
                           (interactive)
                           (panda--browse (format panda--browse-build (tabulated-list-get-id)))))
      (local-set-key "c" (lambda ()
                           (interactive)
                           (panda--create-release-from-build-status (tabulated-list-get-entry))))
      (switch-to-buffer buffer)
      (panda--message (concat "Listing builds for " branch ". Press d for build details, b to open the build in the browser, c to create a release, g to refresh.")))))

(defun panda--build-results-data (branch-key)
  "Get BRANCH-KEY build data for 'tabulated-list-entries'."
    (let ((build-keys (panda--latest-build-keys branch-key)))
      (mapcar 'panda--fetch-build-bykey build-keys)))

(defun panda--latest-build-keys (branch-key)
  "Get the list of links to retreive the latest builds for BRANCH-KEY."
    (let* ((target-url (concat "/result/" branch-key))
           (parameters (concat "max-results=" (number-to-string panda-latest-max-results)
                               "&includeAllStates=true"))
           (data (panda--api-call target-url parameters)))
      (let-alist data
        (mapcar (lambda (build) (alist-get 'key build))
                .results.result))))

(defun panda--fetch-build-bykey (build-key)
  "Return the data for BUILD-KEY formatted for tabulated mode."
  (let* ((build-data (panda--api-call (concat "/result/" build-key))))
    (let-alist build-data
      ;; tabulated list requires a list with an ID and a vector
      ;; and also doesn't like nil values, hence the 'or' fest
      (list .key
            (vector .key
                    (or .state "")
                    (or .prettyBuildStartedTime "")
                    (or .prettyBuildCompletedTime "")
                    (or .buildDurationDescription "")
                    (or .master.key ;; for branches this will be non-empty
                        .plan.key)))))) ;; if we get here this is a base plan

(define-derived-mode panda--build-results-mode tabulated-list-mode "Panda build results view" "Major mode to display Bamboo's build results."
  (setq tabulated-list-format [("Build key" 20 nil)
                               ("State" 11 nil)
                               ("Started" 22)
                               ("Finished" 22 nil)
                               ("Duration" 0 nil)])
  (set (make-local-variable 'panda--branch-key) nil)
  (setq tabulated-list-padding 1)
  (tabulated-list-init-header))

;;------------------Creating deployments and pushing them-------------------------

(defun panda-create-release ()
  "Create a new release from a succesful build."
  (interactive)
  (destructuring-bind (_project-key plan-key branch-key) (panda--select-build-ppb nil nil)
    ;; I could re-work the cache to skip this call if I stored the plan key. But some
    ;; deploys dont have them, so I have to code for that too...let's have one extra
    ;; call and be done with it
    (let* ((did (panda--get-deployid-for-plan-key plan-key))
           (formatted (panda--successful-builds-for-release branch-key))
           (selected-build (ido-completing-read "Select a build: " formatted))
           (release-name nil))
      (setq selected-build (car (split-string selected-build))) ;; really shady
      (setq release-name (read-string "Release name: " (panda--proposed-release-name did selected-build)))
      (panda--create-release-execute selected-build did release-name))))

(defun panda--get-deployid-for-plan-key (plan-key)
  "Obtain the deployment id for PLAN-KEY."
  (let ((forplan-response (panda--api-call "/deploy/project/forPlan"
                                           (concat "planKey=" plan-key))))
    (alist-get 'id (elt forplan-response 0))))

(defun panda--create-release-execute (build-key did release-name)
  "Make an API call to create a release in DID with RELEASE-NAME out of BUILD-KEY."
  (let ((payload (json-encode (list (cons 'planResultKey build-key) (cons 'name  release-name)))))
    (panda--api-call (format "/deploy/project/%s/version" did)
                     nil
                     "POST"
                     payload)))

(defun panda--create-release-from-build-status (selected-entry)
  "Create a new release out of SELECTED-ENTRY from the build status screen."
  (interactive)
  (let ((build-key (elt selected-entry 0))
        (plan-key (elt selected-entry 5))
        (build-status (elt selected-entry 1))
        (did nil)
        (release-name nil))
    (if (string= panda--build-status-for-release build-status)
        (progn
          (setq did (panda--get-deployid-for-plan-key plan-key))
          (setq release-name (read-string "Release name: " (panda--proposed-release-name did build-key)))
          (panda--create-release-execute build-key did release-name))
      (panda--message "Can't create a release from a non-successful build."))))

(defun panda--successful-builds-for-release (branch-key)
  "Return the last few successful builds for BRANCH-KEY."
  (let* ((last-builds (mapcar 'cadr (panda--build-results-data branch-key)))
         (successful (cl-remove-if-not (lambda (build) (equal (elt build 1) panda--build-status-for-release)) last-builds)))
    (mapcar (lambda (build) (concat (elt build 0) " - Completed: " (elt build 2))) successful)))

(defun panda--proposed-release-name (did build-key)
  "Use DID (deploy project id) and BUILD-KEY to generate the release name."
  (alist-get 'nextVersionName (panda--api-call (format "/deploy/projectVersioning/%s/nextVersion" did)
                                               (concat "resultKey=" build-key))))

(defun panda-queue-deploy (&optional project environment)
  "Queue a deploy.  If PROJECT and ENVIRONMENT are not provided, select them interactively."
  (interactive)
  (let* ((project-name (or project (panda--select-deploy-project)))
         (metadata (panda--agetstr project-name (panda--deploys)))
         (did (car metadata))
         (environments (cdr metadata))
         (deploy-data (panda--deploys-for-id did))
         (selected-release (ido-completing-read "Select release: "
                                                (mapcar 'first deploy-data)))
         (selected-environment (or environment
                                   (ido-completing-read "Select an environment: "
                                                    (mapcar 'first environments))))
         (confirmed t)) ;; we'll check if there's a regex match later
    (when (not (string-empty-p panda-deploy-confirmation-regex))
      (if (string-match-p panda-deploy-confirmation-regex selected-environment)
          (setq confirmed (y-or-n-p (format "OK to deploy version %s to environment %s? " selected-release selected-environment)))
        (setq confirmed t))) ;; if it doesn't match the regex we don't need to ask

    (if confirmed
        (progn
          (panda--api-call "/queue/deployment"
                           (format "environmentId=%s&versionId=%s"
                                   (car (panda--agetstr selected-environment environments))
                                   (car (panda--agetstr selected-release deploy-data)))
                           "POST")
          (panda--message "Deployment requested")
          (if (and project environment) ;; not 100% correct way of identifying calls from the deploy status buffer
              (panda-deploy-status project) ;; just show it/update it
            (panda--show-deploy-status project-name))) ;; depends on the config
      (message "Deployment cancelled"))))

(defun panda--show-deploy-status (project-name)
  "Show PROJECT-NAME deploy status, according to the user preferences."
  (let ((show-status panda-open-status-after-deploy)) ;; later we'll check for 'ask or t
    (when (eq panda-open-status-after-deploy 'ask)
      (setq show-status (y-or-n-p "Show deployment status for the project? ")))
    (when show-status
      (panda-deploy-status project-name))))

(defun panda--deploys-for-id (did)
  "Get the deployments of a DID (deployment id)."
  (let* ((url (format "/deploy/project/%s/versions" did))
         (parameters (format "max-results=%s" panda-latest-max-results))
         (data (panda--api-call url parameters))
         (deploys (alist-get 'versions data)))
    (mapcar
     (lambda (dep) (let-alist dep (list .name .id)))
     deploys)))

(defun panda-deploy-status (&optional project)
  "Display a project's deploy status.  If PROJECT is not provided, select it interactively."
  (interactive)
  (let* ((project-name (or project (panda--select-deploy-project)))
         (metadata (panda--agetstr project-name (panda--deploys)))
         (did (car metadata))
         (data (elt (panda--api-call (format "/deploy/dashboard/%s" did)) 0))
         (envs (alist-get 'environmentStatuses data))
         (data-formatted (mapcar 'panda--format-deploy-status envs))
         (buffer-name (concat "*Panda - Deploy status " project-name "*"))
         (buffer (get-buffer-create buffer-name)))
    (with-current-buffer buffer
      ;; change to tablist mode
      (panda--deploy-results-mode)
      ;;buffer local variables
      (setq panda--project-name project-name)
      (setq panda--deploy-project-id did)
      (setq tabulated-list-entries data-formatted)
      (tabulated-list-print)
      (local-set-key "g" (lambda ()
                           (interactive)
                           (panda-deploy-status panda--project-name)
                           (panda--message (concat "Updated deploy status for " panda--project-name))))
      (local-set-key "b" (lambda ()
                           (interactive)
                           (panda--browse (format panda--browse-deploy-project panda--deploy-project-id))))
      (local-set-key "q" (lambda ()
                           (interactive)
                           (panda-queue-deploy panda--project-name (tabulated-list-get-id))))
      (local-set-key "h" (lambda ()
                           (interactive)
                           (panda-environment-history (panda--env-id-from-name
                                                       (tabulated-list-get-id)))))
      (local-set-key "l" (lambda ()
                           (interactive)
                           (panda--deploy-log (elt (tabulated-list-get-entry) 5))))
      (switch-to-buffer buffer)
      (panda--message (concat "Listing deploy status for " project-name ". Press b to open the deploy project in a browser, q to queue a deploy under point, h to see history for an environment, l for logs, g to refresh.")))))

(defun panda-environment-history (&optional env-id)
  "Show the history of ENV-ID in a new buffer.  If env-id is not provided, it will be prompted."
  (interactive)
  (unless env-id
    (let* ((project (panda--select-deploy-project))
           (project-data (panda--agetstr project (panda--deploys)))
           (env-name (ido-completing-read "Select an environment: "
                                      (mapcar 'car (cdr project-data)))))
      (setq env-id (panda--env-id-from-name env-name))))
  (let* ((environment-data (panda--api-call (format "/deploy/environment/%s/results" env-id)))
         (data-formatted (mapcar 'panda--format-env-history (alist-get 'results environment-data)))
         (environment-name (panda--env-name-from-id env-id))
         (buffer-name (concat "*Panda - Environment history " environment-name "*"))
         (buffer (get-buffer-create buffer-name)))
    (with-current-buffer buffer
      (panda--environment-history-mode)
      (setq tabulated-list-entries data-formatted)
      (tabulated-list-print)
      (local-set-key "l" (lambda ()
                           (interactive)
                           (panda--deploy-log (tabulated-list-get-id))))
      (switch-to-buffer buffer)
      (panda--message (concat "Showing deployment history. Press l to see a deploy log for the run under point.")))))

(defun panda--deploy-log (deploy-id)
  "Show the log of DEPLOY-ID in a new buffer."
  (let* ((deploy-data (panda--api-call (format "/deploy/result/%s" deploy-id)
                                       ;; questionable, if you have more than 1 million lines log
                                       ;; there are bigger problems if we actually get it all...
                                       "includeLogs=true&max-results=1000000"))
         (logs (panda--deploy-log-from-deploy-data deploy-data))
         (buffer-name (format "*Panda - Deploy log %s*" deploy-id))
         (buffer (get-buffer-create buffer-name)))
    (with-current-buffer buffer
      (setq buffer-read-only nil)
      (erase-buffer)
      (insert logs)
      ;; When reading logs, usually you want to see last first...
      ;; OR: add &optional, and bind "g" using that optional param
      ;; for "don't go up after insert"
      ;; (goto-char (point-min))
      (setq buffer-read-only t)
      (local-set-key "g" (lambda ()
                           (interactive)
                           (panda--deploy-log deploy-id)))
      (panda--message (format "Showing log for deploy %s. Press g to refresh." deploy-id))
      (switch-to-buffer buffer))))

(defun panda--deploy-log-from-deploy-data (deploy-data)
  "Extract the log entries from DEPLOY-DATA."
  (let-alist deploy-data
    (mapconcat (lambda (log-entry) (format "[%s] - %s"
                                           (alist-get 'formattedDate log-entry)
                                           (alist-get 'unstyledLog log-entry)))
               .logEntries.logEntry "\n")))

(defun panda--env-name-from-id (env-id)
  "Find the environment name from ENV-ID."
  ;; this is really inneficient. Should revisit.
  ;; still faster than making an API call most likely
  (let ((found nil))
    (dolist (deploy-data (panda--deploys) found)
      (let* ((env-data (nthcdr 2 deploy-data))
             (id-matched (cl-remove-if-not (lambda (env) (eq env-id (cadr env)))
                                           env-data)))
        (when id-matched
          (setq found (caar id-matched)))))
    found))

(defun panda--env-id-from-name (env-name)
  "Obtain the env-id for ENV-NAME."
  (cadar (cl-remove-if-not (lambda (env) (string= env-name (car env)))
                           (panda--all-environments))))

(define-derived-mode panda--environment-history-mode tabulated-list-mode "Panda environment history view" "Major mode to display Bamboo's environment history."
  (setq tabulated-list-format [("State" 12 nil)
                               ("Status" 8)
                               ("Started" 20 nil)
                               ("Completed" 20 nil)
                               ("Version name" 0 nil)])
  (setq tabulated-list-padding 1)
  (tabulated-list-init-header))

(defun panda--format-env-history (deploy-data)
  "Format DEPLOY-DATA for tabulated output."
  (let-alist deploy-data
    (list .id
          (vector .deploymentState
                  .lifeCycleState
                  (panda--unixms-to-string .startedDate)
                  (panda--unixms-to-string .finishedDate)
                  .deploymentVersionName))))

(defun panda--format-deploy-status (deploy-status)
  "Format DEPLOY-STATUS for tabulated output."
  ;; tabulated list requires a list with an ID and a vector
  (let-alist deploy-status
    (list .environment.name
          (vector .environment.name
                  .deploymentResult.lifeCycleState
                  .deploymentResult.deploymentState
                  (panda--unixms-to-string .deploymentResult.startedDate)
                  (panda--unixms-to-string .deploymentResult.finishedDate)
                  (format "%s" .deploymentResult.id)
                  .deploymentResult.deploymentVersion.name))))

(define-derived-mode panda--deploy-results-mode tabulated-list-mode "Panda deploy results view" "Major mode to display Bamboo's deploy results."
  (setq tabulated-list-format [("Environment" 35 nil)
                               ("State" 12 nil)
                               ("Status" 8)
                               ("Started" 20 nil)
                               ("Completed" 20 nil)
                               ("Deploy ID" 12 nil)
                               ("Version name" 0 nil)])
  (set (make-local-variable 'panda--project-name) nil)
  (set (make-local-variable 'panda--deploy-project-id) nil)
  (setq tabulated-list-padding 1)
  (tabulated-list-init-header))

;; panda-deploy-from-build
;; find if a build has a deploy: https://bamboo.starz.com/rest/api/latest/search/versions?searchTerm=build-name&deploymentProjectId=did

(provide 'panda)
;;; panda.el ends here
