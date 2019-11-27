To use, add wisp-mode.el to your Emacs Lisp path and add the following
to your ~/.emacs or ~/.emacs.d/init.el

(require 'wisp-mode)

For details on wisp, see
https://www.draketo.de/english/wisp

If you came here looking for wisp the lisp-to-javascript
compiler[1], have a look at wispjs-mode[2].

[1]: http://jeditoolkit.com/try-wisp

[2]: http://github.com/krisajenkins/wispjs-mode

ChangeLog:

 - 0.2.5: backtab chooses existing lower indentation values from previous lines.
 - 0.2.4: better indentation support:
          cycle forward on tab,
          cycle backwards on backtab (s-tab),
          keep indentation on enter.
 - 0.2.1: Disable electric-indent-local-mode in wisp-mode buffers.
 - 0.2: Fixed the regular expressions.  Now org-mode HTML export works with wisp-code.
