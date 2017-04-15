Description:

traad is a JSON+HTTP server built around the rope refactoring library. This
file provides an API for talking to that server - and thus to rope - from
emacs lisp. Or, put another way, it's another way to use rope from emacs.

For more details, see the project page at
https://github.com/abingham/traad.

Installation:

traad depends on the following packages:

  cl
  deferred - https://github.com/kiwanami/emacs-deferred
  json
  request - https://github.com/tkf/emacs-request
  request-deferred - (same as request)

Copy traad.el to some location in your emacs load path. Then add
"(require 'traad)" to your emacs initialization (.emacs,
init.el, or something).

Example config:

  (require 'traad)
