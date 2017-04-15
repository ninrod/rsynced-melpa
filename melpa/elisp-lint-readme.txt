This is a tool for finding certain problems in Emacs Lisp files. Use it on
the command line like this:

emacs -Q --batch -l elisp-lint.el -f elisp-lint-files-batch *.el

You can disable individual checks, by passing flags on the command line:

emacs -Q --batch -l elisp-lint.el -f elisp-lint-files-batch --no-indent *.el

Alternatively, you can disable checks using file variables or the following
.dir.locals file:

((nil . ((elisp-lint-ignored-validators . ("fill-column")))))

For a full list of validators, see `elisp-lint-file-validators' and
`elisp-lint-buffer-validators'.
