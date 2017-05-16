;;; ghub+.el --- a thick GitHub API client built on ghub  -*- lexical-binding: t; -*-

;; Copyright (C) 2017  Sean Allred

;; Author: Sean Allred <code@seanallred.com>
;; Keywords: extensions, multimedia, tools
;; Homepage: https://github.com/vermiculus/ghub-plus
;; Package-Requires: ((emacs "25") (ghub "1.2") (apiwrap "0.1.2"))
;; Package-Version: 20170514.2313
;; Package-X-Original-Version: 0.1

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

;; Provides some sugar for `ghub'.  See package `apiwrap' for
;; generated function usage instructions.

;;; Code:

(require 'url)
(require 'ghub)
(require 'apiwrap)

(eval-and-compile
  (defun ghubp--make-link (alist)
    "Create a link from an ALIST of API endpoint properties."
    (format "https://developer.github.com/v3/%s" (alist-get 'link alist)))

  (defun ghubp--stringify-params (params)
    "Process PARAMS from textual data to Lisp structures."
    (mapcar (lambda (p)
              (let ((k (car p)) (v (cdr p)))
                (cons k (alist-get v '((t . "true") (nil . "false")) v))))
            params))

  (defun ghubp--remove-api-links (object &optional preserve-objects)
    "Remove everything in OBJECT that points back to `api.github.com'.

If PRESERVE-OBJECTS is non-nil, those objects will not be
stripped of references."
    ;; execution time overhead of 0.5%
    (let ((recurse (lambda (o) (ghubp--remove-api-links o preserve-objects))))
      (delq nil (if (and (consp object) (consp (car object)))
                    (mapcar recurse object)
                  (if (consp object)
                      (if (memq (car object) preserve-objects)
                          object
                        (unless (and (stringp (cdr object))
                                     (string-match-p (rx bos (+ alnum) "://api.github.com/")
                                                     (cdr object)))
                          (cons (car object)
                                (if (consp (cdr object))
                                    (mapcar recurse (cdr object))
                                  (cdr object))))))))))

  (defun ghubp--pre-process-params (params)
    (thread-first params
      (ghubp--stringify-params)))

  (defun ghubp--post-process (object &optional preserve-objects)
    (thread-first object
      (ghubp--remove-api-links preserve-objects)))

  (apiwrap-new-backend
   "GitHub" "ghubp"
   '((repo . "REPO is a repository alist of the form returned by `ghubp-get-user-repos'.")
     (org  . "ORG is an organization alist of the form returned by `ghubp-get-user-orgs'.")
     (thread . "THREAD is a thread object of the form returned by `ghubp-get-repos-owner-repo-comments'.")
     (issue . "ISSUE is an issue object of the form returned by `ghubp-get-issues'.")
     (label . "LABEL is a label object of the form returned by `ghubp-get-repos-owner-repo-issues-number-labels'.")
     (ref . "REF is a string and can be a SHA, a branch name, or a tag name.")
     (milestone . "MILESTONE is a milestone object.")
     (user . "USER is a user object."))
   :get #'ghub-get :put #'ghub-put :head #'ghub-head
   :post #'ghub-post :patch #'ghub-patch :delete #'ghub-delete

   :link #'ghubp--make-link
   :post-process #'ghubp--post-process
   :pre-process-params #'ghubp--pre-process-params))

;;; Utilities
(defmacro ghubp-unpaginate (&rest body)
  "Unpaginate API responses and execute BODY.
See `ghub-unpaginate'."
  `(let ((ghub-unpaginate t)) ,@body))

(defun ghubp-keep-only (structure object)
  "Keep a specific STRUCTURE in OBJECT.
See URL `http://emacs.stackexchange.com/a/31050/2264'."
  (declare (indent 1))
  (if (and (consp object) (consp (car object)) (consp (caar object)))
      (mapcar (apply-partially #'ghubp-keep-only structure) object)
    (mapcar (lambda (el)
              (if (consp el)
                  (cons (car el)
                        (ghubp-keep-only (cdr el) (alist-get (car el) object)))
                (cons el (alist-get el object))))
            structure)))

;;; Repositories
(defapiget-ghubp "/repos/:owner/:repo/collaborators"
  "List collaborators."
  "repos/collaborators/#list-collaborators"
  (repo) "/repos/:repo.owner.login/:repo.name/comments")

(defapiget-ghubp "/repos/:owner/:repo/comments"
  "List commit comments for a repository."
  "repos/comments/#list-commit-comments-for-a-repository"
  (repo) "/repos/:repo.owner.login/:repo.name/comments")

;;; Issues
(defapiget-ghubp "/issues"
  "List all issues assigned to the authenticated user across all
visible repositories including owned repositories, member
repositories, and organization repositories."
  "issues/#list-issues")

(defapiget-ghubp "/user/issues"
  "List all issues across owned and member repositories assigned
to the authenticated user."
  "issues/#list-issues")

(defapiget-ghubp "/orgs/:org/issues"
  "List all issues for a given organization assigned to the
authenticated user."
  "issues/#list-issues"
  (org) "/org/:org.login/issues")

(defapiget-ghubp "/repos/:owner/:repo/issues"
  "List issues for a repository."
  "issues/#list-issues-for-a-repository"
  (repo) "/repos/:repo.owner.login/:repo.name/issues")

(defapiget-ghubp "/repos/:owner/:repo/issues/:number"
  "Get a single issue."
  "issues/#get-a-single-issue"
  (repo issue) "/repos/:repo.owner.login/:repo.name/issues/:issue.number")

(defapipost-ghubp "/repos/:owner/:repo/issues"
  "Create an issue.
Any user with pull access to a repository can create an issue."
  "issues/#create-an-issue"
  (repo) "/repos/:repo.owner.login/:repo.name/issues")

(defapipatch-ghubp "/repos/:owner/:repo/issues/:number"
  "Edit an issue.
Issue owners and users with push access can edit an issue."
  "issues/#edit-an-issue"
  (repo issue) "/repos/:repo.owner.login/:repo.name/issues/:issue.number")

(defapiput-ghubp "/repos/:owner/:repo/issues/:number/lock"
  "Lock an issue.
Users with push access can lock an issue's conversation."
  "issues/#lock-an-issue"
  (repo issue) "/repos/:repo.owner.login/:repo.name/issues/:issue.number")

(defapidelete-ghubp "/repos/:owner/:repo/issues/:number/lock"
  "Unlock an issue
Users with push access can unlock an issue's conversation."
  "issues/#unlock-an-issue"
  (repo issue) "/repos/:repo.owner.login/:repo.name/issues/:issue.number")

;;; Issue Assignees
(defapiget-ghubp "/repos/:owner/:repo/assignees"
  "List assignees.
This call lists all the available assignees to which issues may
be assigned."
  "issues/assignees/#list-assignees"
  (repo) "/repos/:repo.owner.login/:repo.name/assignees")

(defapiget-ghubp "/repos/:owner/:repo/assignees/:assignee"
  ;; todo: sugar to handle valid 404 response
  "Check assignee.
You may also check to see if a particular user is an assignee for
a repository."
  "issues/assignees/#check-assignee"
  (repo user) "/repos/:repo.owner.login/:repo.name/assignees/:user.login")

(defapipost-ghubp "/repos/:owner/:repo/issues/:number/assignees"
  ;; todo: sugar to filter users in DATA down to just the usernames
  "Add assignees to an Issue.
This call adds the users passed in the assignees key (as their
logins) to the issue."
  "issues/assignees/#add-assignees-to-an-issue")

(defapidelete-ghubp "/repos/:owner/:repo/issues/:number/assignees"
  ;; todo: sugar to filter users in DATA down to just the usernames
  "Remove assignees from an Issue.
This call removes the users passed in the assignees key (as their
logins) from the issue."
  "issues/assignees/#remove-assignees-from-an-issue"
  (repo issue) "/repos/:repo.owner.login/:repo.name/issues/:issue.number/assignees")

;;; Issue Comments

(defapiget-ghubp "/repos/:owner/:repo/issues/:number/comments"
  "List comments on an issue.
Issue Comments are ordered by ascending ID."
  "issues/comments/#list-comments-on-an-issue"
  (repo issue) "/repos/:repo.owner.login/:repo.name/issues/:issue.number/comments")

(defapiget-ghubp "/repos/:owner/:repo/issues/comments"
  "List comments in a repository.
By default, Issue Comments are ordered by ascending ID."
  "issues/comments/#list-comments-in-a-repository"
  (repo) "/repos/:repo.owner.login/:repo.name/issues/comments")

(defapiget-ghubp "/repos/:owner/:repo/issues/comments/:id"
  "Get a single comment."
  "issues/comments/#get-a-single-comment"
  (repo thread) "/repos/:repo.owner.login/:repo.name/issues/comments/:thread.id")

(defapipatch-ghubp "/repos/:owner/:repo/issues/:number/comments"
  "Create a comment."
  "issues/comments/#create-a-comment"
  (repo issue) "/repos/:repo.owner.login/:repo.name/issues/:issue.number/comments")

(defapipatch-ghubp "/repos/:owner/:repo/issues/comments/:id"
  "Edit a comment."
  "issues/comments/#edit-a-comment"
  (repo thread) "/repos/:repo.owner.login/:repo.name/issues/comments/:thread.id")

(defapidelete-ghubp "/repos/:owner/:repo/issues/comments/:id"
  "Delete a comment."
  "issues/comments/#delete-a-comment"
  (repo thread) "/repos/:repo.owner.login/:repo.name/issues/comments/:thread.id")

;;; Issue Events

(defapiget-ghubp "/repos/:owner/:repo/issues/:number/events"
  ;; note: :number changed from :issue_number for consistency
  "List events for an issue."
  "issues/events/#list-events-for-an-issue"
  (repo issue) "/repos/:repo.owner.login/:repo.name/issues/:issue.number/events")

(defapiget-ghubp "/repos/:owner/:repo/issues/events"
  "List events for a repository."
  "issues/events/#list-events-for-a-repository"
  (repo) "/repos/:repo.owner.login/:repo.name/issues/events")

(defapiget-ghubp "/repos/:owner/:repo/issues/events/:id"
  "Get a single event."
  "issues/events/#get-a-single-event"
  (repo thread) "/repos/:repo.owner.login/:repo.name/issues/events/:thread.id")

;;; Issue Labels

(defapiget-ghubp "/repos/:owner/:repo/labels"
  "List all labels for this repository."
  "issues/labels/#list-all-labels-for-this-repository"
  (repo) "/repos/:repo.owner.login/:repo.name/labels")

(defapiget-ghubp "/repos/:owner/:repo/labels/:name"
  "Get a single label."
  "issues/labels/#get-a-single-label"
  (repo label) "/repos/:repo.owner.login/:repo.name/labels/:label.name")

(defapipost-ghubp "/repos/:owner/:repo/labels"
  "Create a label."
  "issues/labels/#create-a-label"
  (repo) "/repos/:repo.owner.login/:repo.name/labels")

(defapipatch-ghubp "/repos/:owner/:repo/labels/:name"
  "Update a label."
  "issues/labels/#update-a-label"
  (repo label) "/repos/:repo.owner.login/:repo.name/labels/:label.name")

(defapidelete-ghubp "/repos/:owner/:repo/labels/:name"
  "Delete a label."
  "issues/labels/#deleted-a-label"
  (repo label) "/repos/:repo.owner.login/:repo.name/labels/:label.name")

(defapiget-ghubp "/repos/:owner/:repo/issues/:number/labels"
  "List labels on an issue."
  "issues/labels/#list-labels-on-an-issue"
  (repo issue) "/repos/:repo.owner.login/:repo.name/issues/:issue.number/labels")

(defapipost-ghubp "/repos/:owner/:repo/issues/:number/labels"
  ;; todo: sugar to filter labels in DATA down to just the names
  "Add labels to an issue."
  "issues/labels/#add-labels-to-an-issue"
  (repo issue) "/repos/:repo.owner.login/:repo.name/issues/:issue.number/labels")

(defapidelete-ghubp "/repos/:owner/:repo/issues/:number/labels/:name"
  "Remove a label from an issue."
  "issues/labels/#remove-a-label-from-an-issue"
  (repo issue label) "/repos/:repo.owner.login/:repo.name/issues/:issue.number/labels/:label.name")

(defapipatch-ghubp "/repos/:owner/:repo/issues/:number/labels"
  ;; todo: sugar to filter labels in DATA down to just the names
  "Replace all labels for an issue."
  "issues/labels/#replace-all-labels-for-an-issue"
  (repo issue) "/repos/:repo.owner.login/:repo.name/issues/:issue.number/labels")

(defapidelete-ghubp "/repos/:owner/:repo/issues/:number/labels"
  "Remove all labels from an issue."
  "issues/labels/#remove-all-labels-from-an-issue"
  (repo issue) "/repos/:repo.owner.login/:repo.name/issues/:issue.number/labels")

(defapiget-ghubp "/repos/:owner/:repo/milestones/:number/labels"
  "Get labels for every issue in a milestone."
  "issues/labels/#get-labels-for-every-issue-in-a-milestone"
  (repo milestone) "/repos/:repo.owner.login/:repo.name/milestones/:milestone.number/labels")

;;; Unfiled
(defapiget-ghubp "/repos/:owner/:repo"
  ""
  ""
  (repo) "/repos/:repo.owner.login/:repo.name")

(defapiget-ghubp "/repos/:owner/:repo/commits/:ref/statuses"
  "List statuses for a specific ref"
  "repos/statuses/#list-statuses-for-a-specific-ref"
  (repo ref) "/repos/:repo.owner.login/:repo.name/commits/:ref/statuses")

(defapiget-ghubp "/repos/:owner/:repo/commits/:ref/status"
  "Get the combined status for a specific ref"
  "repos/statuses/#get-the-combined-status-for-a-specific-ref"
  (repo ref) "/repos/:repo.owner.login/:repo.name/commits/:ref/status")

(defapiget-ghubp "/user"
  "Return the currently authenticated user"
  "users/#get-the-authenticated-user")

(defapiget-ghubp "/user/repos"
  "Return repositories of the currently authenticated user"
  "issues/#list-issues-for-a-repository")

(defapiget-ghubp "/notifications"
  "List all notifications for the current user, grouped by repository"
  "activity/notifications/#list-your-notifications"
  :post-process (lambda (o) (ghubp--post-process o '(subject))))

(defapipatch-ghubp "/notifications/threads/:id"
  ""
  "activity/notifications/#mark-a-thread-as-read"
  (thread) "/notifications/threads/:thread.id")

(defapipost-ghubp "/repos/:owner/:repo/forks"
  "Create a fork for the authenticated user."
  "repos/forks/#create-a-fork"
  (repo) "/repos/:repo.owner.login/:repo.name/forks")

(defapipost-ghubp "/repos/:owner/:repo/pulls"
  "Open a pull request."
  "pulls/#create-a-pull-request"
  (repo) "/repos/:repo.owner.login/:repo.name/pulls"
  :validate-data
  (lambda (o)
    (--all? (let ((v (alist-get it o)))
              (and v (stringp v) (< 0 (length v))))
            '(title head base))))

(defapipost-ghubp "/user/repos"
  "Create a fork for the authenticated user."
  "repos/forks/#create-a-fork")

(defapiget-ghubp "/notifications/threads/:id"
  "Adds Mlatest_comment_url-callback and Murl-callback to .subject"
  "activity/notifications/#view-a-single-thread"
  (thread) "/notifications/threads/:thread.id"
  :post-process (lambda (o) (ghubp--post-process o '(subject))))

(defapipost-ghubp "/repos/:owner/:repo/issues/:number/comments"
  "Post a comment to an issue"
  "issues/comments/#create-a-comment"
  (repo issue) "/repos/:repo.owner.login/:repo.name/issues/:issue.number/comments")

(defun ghubp-url-parse (url)
  "Parse URL for its type and API callback.

A cons cell is returned.  The car is one of

 - `issue'
 - `pull-request'

and the cdr is a callback suitable for `ghub-get', etc."
  (let ((callback (url-filename (url-generic-parse-url url))))
    (cons
     (cond
      ((string-match-p (rx bol "/repos/" (+? any) "/" (+? any) "/issues/" (+ digit) eol)
                       callback)
       'issue)
      ((string-match-p (rx bol "/repos/" (+? any) "/" (+? any) "/pulls/" (+ digit) eol)
                       callback)
       'pull-request)
      (t 'unknown))
     callback)))

(provide 'ghub+)
;;; ghub+.el ends here
