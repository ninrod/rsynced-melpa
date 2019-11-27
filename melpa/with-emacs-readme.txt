Evaluate expressions in a separate Emacs process:

,---
| ;;; `with-emacs'
|
| ;; Evaluate expressions in a separate Emacs.
| (with-emacs ...)
|
| ;; Specify the version of Emacs and enable lexical binding
| (with-emacs :path "/path/to/{version}/emacs" :lexical t ...)
|
| ;; Use partially applied function (see `with-emacs-define-partially-applied' for more)
| ;; instead of writting verry long parameter each time:
| (with-emacs-nightly-t ...)
| ;; Equaivalent to:
| ;; (with-emacs :path "/path/to/nightly/emacs" :lexical t ...)
|
| ;;; `with-emacs-server'
|
| ;; Evaluate expressions in server "name" or signal an error if no such server.
| (with-emacs-server "name" ...)
|
| ;; Evaluate expressions in server "name" and start a server if necessary.
| (with-emacs-server "name" :ensure t ...)
| (with-emacs-server "name" :ensure "/path/to/{version}/emacs" ...)
`---

See README for more information.
