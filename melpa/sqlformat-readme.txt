Provides commands and a minor mode for easily reformatting SQL
using external programs such as "sqlformat" and "pg_format".

Install the "sqlparse" (Python) package to get "sqlformat", or
"pgformatter" to get "pg_format".

Customise the `sqlformat-command' variable as desired, then call
`sqlformat', `sqlformat-buffer' or `sqlformat-region' as convenient.

Enable `sqlformat-on-save-mode' in SQL buffers like this:

    (add-hook 'sql-mode-hook 'sqlformat-on-save-mode)

or locally to your project with a form in your .dir-locals.el like
this:

    ((sql-mode
      (mode . sqlformat-on-save)))

You might like to bind `sqlformat' or `sqlformat-buffer' to a key,
e.g. with:

    (define-key 'sql-mode-map (kbd "C-c C-f") 'sqlformat)
