shx ("shell-extras") extends comint-mode: it parses markup in the output
stream, enabling plots and graphics to be embedded, and adds command-line
functions which plug into Emacs (e.g. use :e <filename> to edit a file).

Manual install:

1. Move shx.el to a directory in your load-path or add this to your .emacs:
   (add-to-list 'load-path "~/path/to/this-file/")
2. Add this line to your .emacs:
   (require 'shx)

Type M-x shx RET to create a new shell session using shx.
Type M-x customize-group RET shx RET to see customization options.
You can enable shx in every comint-mode buffer with (shx-global-mode 1).
