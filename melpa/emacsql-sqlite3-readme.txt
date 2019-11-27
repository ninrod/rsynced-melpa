* README                                                             :README:

[[https://melpa.org/#/emacsql-sqlite3][file:https://melpa.org/packages/emacsql-sqlite3-badge.svg]]
[[https://travis-ci.org/cireu/emacsql-sqlite3][file:https://travis-ci.org/cireu/emacsql-sqlite3.svg?branch=master]]

** Introduction

This is yet another [[https://github.com/skeeto/emacsql][EmacSQL]] backend for SQLite, which use official =sqlite3=
executable to access SQL database.

The tests don't pass under Emacs 25.1 for unknown reason, so we don't support
Emacs 25.1 currently. But any PR to improve this are welcomed.

** Installation

=emacsql-sqlite3= is available on melpa.

** Usage

You need to install =sqlite3= official CLI tool, 3.8.2 version or above were
tested, =emacsql-sqlite3= may won't work if you using lower version.

=sqlite3= CLI tool will load =~/.sqliterc= if presented, =emacsql-sqlite3=
will get undefined behaviour if any error occurred during the load progress.

The only entry point to a EmacSQL interface is =emacsql-sqlite3=, for more
information, please check EmacSQL's README.

** About Closql

[[https://github.com/emacscollective/closql][closql]] is using =emacsql-sqlite= as backend, you can use following code to force
closql use =emacsql-sqlite3= since it's full compatible.

#+BEGIN_SRC emacs-lisp :results none
(with-eval-after-load 'closql
  (defclass closql-database (emacsql-sqlite3-connection)
    ((object-class :allocation :class))))
#+END_SRC

* _                                                                  :ignore:
