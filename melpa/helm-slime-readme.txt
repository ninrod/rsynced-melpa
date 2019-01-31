Some Helm and SLIME Configurations for using SLIME within the
Helm interface.

The complete command list:

 `helm-slime-complete'
   Select a symbol from the SLIME completion systems.
 `helm-slime-list-connections'
   Yet another `slime-list-connections' with `helm'.
 `helm-slime-apropos'
   Yet another `slime-apropos' with `helm'.
 `helm-slime-repl-history'
   Select an input from the SLIME repl's history and insert it.

Installation:

Put the helm-slime.el, helm.el to your load-path.
Set up SLIME properly.
Call `slime-setup' and include 'helm-slime as the arguments:

  (slime-setup '([others contribs ...] helm-slime))

or simply require helm-slime in some appropriate manner.
