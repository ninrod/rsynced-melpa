;;; apiwrap.el --- api-wrapping tools      -*- lexical-binding: t; -*-

;; Copyright (C) 2017  Sean Allred

;; Author: Sean Allred <code@seanallred.com>
;; Keywords: tools, maint, convenience
;; Homepage: https://github.com/vermiculus/apiwrap.el
;; Package-Requires: ((emacs "25"))
;; Package-Version: 20170302.1825
;; Package-X-Original-Version: 0.1

;; This file is not part of GNU Emacs.

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

;; API-Wrap.el is a tool to interface with the APIs of your favorite
;; services.  These macros make it easy to define efficient and
;; consistently-documented Elisp functions that use a natural syntax
;; for application development.

;;; Code:

(require 'cl-lib)

(defun apiwrap-resolve-api-params (object url &optional noencode)
  "Resolve parameters in URL to values in OBJECT.

Unless NOENCODE is non-nil, OBJECT values will be passed through
`url-encode-url'.

Example:

    \(apiwrap-resolve-api-params
        '\(\(name . \"Hello-World\"\)
          \(owner \(login . \"octocat\"\)\)\)
      \"/repos/:owner.login/:name/issues\"\)

    ;; \"/repos/octocat/Hello-World/issues\"

"
  (declare (indent 1))
  ;; Yes I know it's hacky, but it works and it's compile-time
  ;; (which is to say: pull-requests welcome!)
  (macroexp--expand-all
   `(let-alist ,object
      ,(let ((in-string t))
         (with-temp-buffer
           (insert url)
           (goto-char 0)
           (insert "(concat \"")
           (while (search-forward ":" nil t)
             (goto-char (1- (point)))
             (insert "\" ")
             (unless noencode (insert "(url-encode-url "))
             (insert ".")
             (setq in-string nil)
             (delete-char 1)
             (when (search-forward "/" nil t)
               (goto-char (1- (point)))
               (unless noencode (insert ")"))
               (insert " \"")
               (setq in-string t)))
           (goto-char (point-max))
           (if in-string (insert "\"")
             (unless noencode (insert ")")))
           (insert ")")
           (delete "" (read (buffer-string))))))))

(defun apiwrap-plist->alist (plist)
  "Convert PLIST to an alist.
If a PLIST key is a `:keyword', then it is converted into a
symbol `keyword'."
  (when (= 1 (mod (length plist) 2))
    (error "bad plist"))
  (let (alist)
    (while plist
      (push (cons (apiwrap--kw->sym (car plist))
                  (cadr plist))
            alist)
      (setq plist (cddr plist)))
    alist))

(defun apiwrap--kw->sym (kw)
  "Convert a keyword to a symbol."
  (if (keywordp kw)
      (intern (substring (symbol-name kw) 1))
    kw))

(defun apiwrap--docfn (service-name doc object-param-doc method external-resource link)
  "Documentation string for resource-wrapping functions created
by `apiwrap--defresource'"
  (format "%s

%sDATA is a data structure to be sent with this request.  If it's
not required, it can simply be omitted.

PARAMS is a plist of parameters appended to the method call.

%s

This generated function wraps the %s API endpoint

    %s %s

which is documented at

    URL `%s'"
          doc (or (and (stringp object-param-doc)
                       (concat object-param-doc "\n\n"))
                  "")
          (make-string 20 ?-)
          service-name
          (upcase (symbol-name method))
          external-resource link))

(defun apiwrap--docmacro (service-name method)
  "Documentation string for macros created by
`apiwrap-new-backend'"
  (apply #'format "Define a new %s resource wrapper function.

RESOURCE is the API endpoint as written in the %s API
documentation.  Along with the backend prefix (from
`apiwrap-new-backend') and the method (%s), this string will be
used to create the symbol for the new function.

DOC is a specific documentation string for the new function.
Usually, this can be copied from the %s API documentation.

LINK is a link to the %s API documentation.

If non-nil, OBJECT is a symbol that will be used to resolve
parameters in the resource and will be a required argument of the
new function.  Its documentation (from the standard parameters of
the call to `apiwrap-new-backend') will be inserted into the
docstring of the generated function.

If non-nil, INTERNAL-RESOURCE is the resource-string used to
resolve OBJECT to the ultimate call instead of RESOURCE.  This is
useful in the likely event that the advertised resource syntax
does not align with the structure of the object it works with.
For example, GitHub's endpoint

    GET /repos/:owner/:repo/issues

would be written as

    \(defapiget-<prefix> \"/repos/:owner/:repo/issues\"
      \"List issues for a repository.\"
      \"issues/#list-issues-for-a-repository\"
      repo \"/repos/:owner.login/:name/issues\"\)

defining a function called `<prefix>-get-repos-owner-repo-issues'
and taking an object with the structure

    \(\(owner \(login . \"octocat\"\)\)
     \(name . \"hello-world\"\)

See the documentation of `apiwrap-resolve-api-params' for more
details on that behavior.

FUNCTIONS is a list of override configuration parameters.  Values
set here (notably those explicitly set to nil) will take
precedence over the defaults provided to `apiwrap-new-backend'."
         (upcase (symbol-name method))
         service-name
         (upcase (symbol-name method))
         (make-list 2 service-name)))

(defun apiwrap-genfunsym (prefix api-method &optional resource)
  "Generate a symbol for a macro/function."
  (let ((api-method (symbol-name (apiwrap--kw->sym api-method))))
    (intern
     (if resource
         (format "%s-%s%s" prefix api-method
                 (replace-regexp-in-string
                  ":" ""
                  (replace-regexp-in-string "/" "-" resource)))
       (format "defapi%s-%s" api-method prefix)))))

(defun apiwrap-stdgenlink (alist)
  "Standard link generation function."
  (alist-get 'link alist))

(defconst apiwrap-primitives
  '(get put head post patch delete)
  "List of primitive methods.  These are required to be
configured.")

(defun apiwrap-genmacros (name prefix standard-parameters functions)
  "Validate arguments and generate all macro forms"
  ;; Default to raw link entered in the macro
  (cl-pushnew '(link . #'apiwrap-stdgenlink) functions)

  ;; Verify all extension functions are actually functions
  (dolist (f functions)
    (let ((key (car f)) (fn (cdr f)))
      (unless (or (functionp fn) (and (consp fn)
                                      (eq 'function (car fn))
                                      (functionp (cadr fn))))
        (if (memq key apiwrap-primitives)
            (error "Primitive function literal required: %s" key)
          (byte-compile-warn "Unknown function for `%S': %S" key fn)))))

  ;; Build the macros
  (let (super-form)
    (dolist (primitive (reverse apiwrap-primitives))
      (let ((macrosym (apiwrap-genfunsym prefix primitive)))
        (push `(defmacro ,macrosym (resource doc link
                                             &optional object internal-resource
                                             &rest functions)
                 ,(apiwrap--docmacro name (apiwrap--kw->sym primitive))
                 (declare (indent defun) (doc-string 2))
                 (apiwrap-gendefun ,name ,prefix ',standard-parameters ',primitive
                                   resource doc link object internal-resource
                                   (append functions ',functions)))
              super-form)))
    super-form))

(defun apiwrap-gendefun (name prefix standard-parameters method resource doc link object internal-resource functions)
  "Generate a single defun form"
  (let ((args '(&optional data &rest params))
        (funsym (apiwrap-genfunsym prefix method resource))
        resolved-resource form
        primitive-func link-func post-process-func pre-process-params-func)

    ;; Be smart about when configuration starts.  Neither `object' nor
    ;; `internal-resource' can be keywords, so we know that if they
    ;; are, then we need to shift things around.
    (when (keywordp object)
      (push internal-resource functions)
      (push object functions)
      (setq object nil internal-resource nil))
    (when (keywordp internal-resource)
      (push internal-resource functions)
      (setq internal-resource nil))

    ;; Now that our arguments have settled, let's use them
    (when object (push object args))

    (setq internal-resource (or internal-resource resource)
          primitive-func (alist-get method functions)
          post-process-func (alist-get 'post-process functions)
          pre-process-params-func (alist-get 'pre-process-params functions)
          link-func (alist-get 'link functions))

    ;; If our functions are already functions (and not quoted), we'll
    ;; have to quote them for the actual defun
    (when (functionp primitive-func)
      (setq primitive-func `(function ,primitive-func)))
    (when (functionp post-process-func)
      (setq post-process-func `(function ,post-process-func)))
    (when (functionp pre-process-params-func)
      (setq pre-process-params-func `(function ,pre-process-params-func)))
    (unless (functionp link-func)
      (setq link-func (eval link-func)))

    ;; Alright, we're ready to build our function
    (setq resolved-resource (apiwrap-resolve-api-params object internal-resource)
          form
          (if pre-process-params-func
              `(apply ,primitive-func ,resolved-resource
                      (if (keywordp data)
                          (list (funcall ,pre-process-params-func (apiwrap-plist->alist (cons data params))))
                        (list (funcall ,pre-process-params-func (apiwrap-plist->alist params)) data)))
            `(apply ,primitive-func ,resolved-resource
                    (if (keywordp data)
                        (list (apiwrap-plist->alist (cons data params)))
                      (list (apiwrap-plist->alist params) data)))))

    (when post-process-func
      (setq form `(funcall ,post-process-func ,form)))

    (let ((props `((prefix   . ,prefix)
                   (method   . ',method)
                   (endpoint . ,resource)
                   (link     . ,link)))
          fn-form)
      (dolist (p props)
        (push `(put ',funsym
                    ',(intern (concat "apiwrap-" (symbol-name (car p))))
                    ,(cdr p))
              fn-form))
      (push `(defun ,funsym ,args
               ,(apiwrap--docfn name doc (alist-get object standard-parameters) method resource
                                (funcall link-func props))
               ,form)
            fn-form)
      (cons 'prog1 fn-form))))

(defmacro apiwrap-new-backend (name prefix standard-parameters &rest functions)
  "Define a new API backend.

SERVICE-NAME is the name of the service this backend will wrap.
It will be used in docstrings of the primitive method macros.

PREFIX is the prefix to use for the macros and for the
resource-wrapping functions.

STANDARD-PARAMETERS is an alist of standard parameters that can
be used to resolve resource URLs like `/users/:user/info'.  Each
key of the alist is the parameter name (as a symbol) and its
value is the documentation to insert in the docstring of
resource-wrapping functions.

FUNCTIONS is a list of arguments to configure the generated
macros.

  Required:

    :get :put :head :post :patch :delete

        API primitives.  See package `ghub' as an example of the
        kinds of primitives these macros are design for; you may
        wish to consider writing wrappers.  Each function is
        expected to take a resource-string as the first
        parameter.  The second parameter should be an alist of
        parameters to the resource.  The third parameter should
        be an alist of data for the resource (e.g., for posting).

  Optional:

    :link

        Function to process an alist and return a link.  This
        function should take an alist as its sole parameter and
        return a fully-qualified URL to be considered the
        official documentation of the API endpoint.

        This function is passed an alist with the following
        properties:

          endpoint  string  the documented endpoint being wrapped
          link      string  the link passed as documentation
          method    symbol  one of `get', `put', etc.
          prefix    string  the prefix used to generate wrappers

        The default is `apiwrap-stdgenlink'.

    :post-process

        Function to process the responses of the API before
        returning.

        The default is `identity'.

    :pre-process-params

        Function to pre-process arguments passed as the
        parameters to the generated wrappers.  The function is
        passed an alist based on the plist of keyword arguments
        given to the wrapper function and should return an alist

        The default is `identity'."
  (let ((sname (cl-gensym)) (sprefix (cl-gensym))
        (sstdp (cl-gensym)) (sfuncs (cl-gensym)))
    `(let ((,sname ,name)
           (,sprefix ,prefix)
           (,sstdp ,standard-parameters)
           (,sfuncs ',(mapcar (lambda (f) (cons (car f) (eval (cdr f))))
                              (apiwrap-plist->alist functions))))
       (mapc #'eval (apiwrap-genmacros ,sname ,sprefix ,sstdp ,sfuncs)))))

(provide 'apiwrap)
;;; apiwrap.el ends here
