tco.el provides tail-call optimisation for functions in elisp that
call themselves in tail-position.

It works by replacing each self-call with a thunk, and wrapping the
function body in a loop that repeatedly evaluates the thunk.  Roughly
speaking, a function `foo':

\(defun-tco foo (...)
  (...)
  (foo (...)))

Is rewritten as follows:

\(defun foo (...)
   (cl-flet (foo-thunk (...)
               (...)
               (lambda () (foo-thunk (...))))
     (let ((result (apply foo-thunk (...))))
       (while (functionp result)
         (setq result (funcall result)))
       result)))
