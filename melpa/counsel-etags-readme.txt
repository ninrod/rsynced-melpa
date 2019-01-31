 Setup:
  "Ctags" (Universal Ctags is recommended) should exist.
  "GNU Find" is used if it's installed but it's optional.
  Or else, customize `counsel-etags-update-tags-backend' to generate tags file

Usage:

  `counsel-etags-find-tag-at-point' to navigate.  This command will also
  run `counsel-etags-scan-code' AUTOMATICALLY if tags file is not built yet.

  `counsel-etags-scan-code' to create tags file
  `counsel-etags-grep' to grep
  `counsel-etags-grep-symbol-at-point' to grep the symbol at point
  `counsel-etags-recent-tag' to open recent tag
  `counsel-etags-find-tag' to two step tag matching use regular expression and filter
  `counsel-etags-list-tag' to list all tags

Tips:
- Add below code into "~/.emacs" to AUTOMATICALLY update tags file:

  ;; Don't ask before re-reading changed TAGS files
  (setq tags-revert-without-query t)
  ;; NO warning when loading large TAGS files
  (setq large-file-warning-threshold nil)
  (add-hook 'prog-mode-hook
    (lambda ()
      (add-hook 'after-save-hook
                'counsel-etags-virtual-update-tags 'append 'local)))

- You can use ivy's negative pattern to filter candidates.
  For example, input "keyword1 !keyword2 keyword3" means:
  "(keyword1 and (not (keyword2 or keyword3))"

- You can setup `counsel-etags-ignore-directories' and `counsel-etags-ignore-filenames',
  (eval-after-load 'counsel-etags
    '(progn
       ;; counsel-etags-ignore-directories does NOT support wildcast
       (add-to-list 'counsel-etags-ignore-directories "build_clang")
       (add-to-list 'counsel-etags-ignore-directories "build_clang")
       ;; counsel-etags-ignore-filenames supports wildcast
       (add-to-list 'counsel-etags-ignore-filenames "TAGS")
       (add-to-list 'counsel-etags-ignore-filenames "*.json")))

See https://github.com/redguardtoo/counsel-etags/ for more tips.
