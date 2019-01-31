This package adds support for Pyre type checker to flycheck.
To use it, add to your init.el:

(require 'flycheck-pyre)
(add-hook 'python-mode-hook 'flycheck-mode)
(eval-after-load 'flycheck
  '(add-hook 'flycheck-mode-hook #'flycheck-pyre-setup))
