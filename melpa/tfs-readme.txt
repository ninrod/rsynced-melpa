Basic steps to setup:
  1. Place `tfs.el' in your `load-path'.
  2. In your .emacs file:
       (require 'tfs)
       (setq tfs/tf-exe  "c:\\vs2010\\common7\\ide\\tf.exe")
       (setq tfs/login "/login:domain\\userid,password")
             -or-
       (setq tfs/login (getenv "TFSLOGIN"))
  3. also in your .emacs file:
       set local or global key bindings for tfs commands.  like so:

       (global-set-key  "\C-xvo" 'tfs/checkout)
       (global-set-key  "\C-xvi" 'tfs/checkin)
       (global-set-key  "\C-xvp" 'tfs/properties)
       (global-set-key  "\C-xvr" 'tfs/rename)
       (global-set-key  "\C-xvg" 'tfs/get)
       (global-set-key  "\C-xvh" 'tfs/history)
       (global-set-key  "\C-xvu" 'tfs/undo)
       (global-set-key  "\C-xvd" 'tfs/diff)
       (global-set-key  "\C-xv-" 'tfs/delete)
       (global-set-key  "\C-xv+" 'tfs/add)
       (global-set-key  "\C-xvs" 'tfs/status)
       (global-set-key  "\C-xva" 'tfs/annotate)
       (global-set-key  "\C-xvw" 'tfs/workitem)
