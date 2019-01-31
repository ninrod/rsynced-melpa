Multiple commands are provided to grep files in the project to get
auto complete candidates.
The keyword to grep is text from line beginning to current cursor.
Project is *automatically* detected if Git/Mercurial/Subversion is used.
You can override the project root by setting `eacl-project-root',

List of commands,

`eacl-complete-line' complete single line.
`eacl-complete-multiline' completes multiline code or html tag.

Modify `grep-find-ignored-directories' and `grep-find-ignored-files'
to setup directories and files grep should ignore:
  (eval-after-load 'grep
    '(progn
       (dolist (v '("node_modules"
                    "bower_components"
                    ".sass_cache"
                    ".cache"
                    ".npm"))
         (add-to-list 'grep-find-ignored-directories v))
       (dolist (v '("*.min.js"
                    "*.bundle.js"
                    "*.min.css"
                    "*.json"
                    "*.log"))
         (add-to-list 'grep-find-ignored-files v))))

Or you can setup above ignore options in ".dir-locals.el".
The content of ".dir-locals.el":
  ((nil . ((eval . (progn
                     (dolist (v '("node_modules"
                                  "bower_components"
                                  ".sass_cache"
                                  ".cache"
                                  ".npm"))
                       (add-to-list 'grep-find-ignored-directories v))
                     (dolist (v '("*.min.js"
                                  "*.bundle.js"
                                  "*.min.css"
                                  "*.json"
                                  "*.log"))
                       (add-to-list 'grep-find-ignored-files v)))))))

"git grep" is automatically detected for single line completion.
