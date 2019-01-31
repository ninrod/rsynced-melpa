* ivy-posframe README                                :README:

** What is ivy-posframe

ivy-posframe is a ivy extension, which let ivy use posframe to show
its candidate menu.

NOTE: ivy-posframe requires Emacs 26 and do not support mouse
click.

** Display functions

1. ivy-posframe-display
2. ivy-posframe-display-at-frame-center
3. ivy-posframe-display-at-window-center
   [[./snapshots/ivy-posframe-display-at-window-center.gif]]
4. ivy-posframe-display-at-frame-bottom-left
5. ivy-posframe-display-at-window-bottom-left
   [[./snapshots/ivy-posframe-display-at-window-bottom-left.gif]]
6. ivy-posframe-display-at-frame-bottom-window-center
7. ivy-posframe-display-at-point
   [[./snapshots/ivy-posframe-display-at-point.gif]]

** How to enable ivy-posframe
*** Global mode
#+BEGIN_EXAMPLE
(require 'ivy-posframe)
(setq ivy-display-function #'ivy-posframe-display)
(setq ivy-display-function #'ivy-posframe-display-at-frame-center)
(setq ivy-display-function #'ivy-posframe-display-at-window-center)
(setq ivy-display-function #'ivy-posframe-display-at-frame-bottom-left)
(setq ivy-display-function #'ivy-posframe-display-at-window-bottom-left)
(setq ivy-display-function #'ivy-posframe-display-at-point)
(ivy-posframe-enable)
#+END_EXAMPLE
*** Per-command mode.
#+BEGIN_EXAMPLE
(require 'ivy-posframe)
Different command can use different display function.
(push '(counsel-M-x . ivy-posframe-display-at-window-bottom-left) ivy-display-functions-alist)
(push '(complete-symbol . ivy-posframe-display-at-point) ivy-display-functions-alist)
(push '(swiper . ivy-posframe-display-at-point) ivy-display-functions-alist)
(ivy-posframe-enable)
#+END_EXAMPLE

NOTE: Using swiper as example: swiper's display function *only*
take effect when you call swiper command with global keybinding, if
you call swiper command with 'M-x' (for example: counsel-M-x),
counsel-M-x's display function will take effect instead of
swiper's.

The value of variable `this-command' will be used as the search key
by ivy to find display function in `ivy-display-functions-alist',
"C-h v this-command" is a good idea.

*** Fallback mode
#+BEGIN_EXAMPLE
(require 'ivy-posframe)
(push '(t . ivy-posframe-display) ivy-display-functions-alist)
(ivy-posframe-enable)
#+END_EXAMPLE

** Tips

*** How to show fringe to ivy-posframe
#+BEGIN_EXAMPLE
(setq ivy-posframe-parameters
      '((left-fringe . 10)
        (right-fringe . 10)))
#+END_EXAMPLE

By the way, User can set *any* parameters of ivy-posframe with
the help of `ivy-posframe-parameters'.

*** How to custom your ivy-posframe style

The simplest way is:
#+BEGIN_EXAMPLE
(defun ivy-posframe-display-at-XXX (str)
  (ivy-posframe--display str #'your-own-poshandler-function))
(ivy-posframe-enable) ; This line is needed.
#+END_EXAMPLE
