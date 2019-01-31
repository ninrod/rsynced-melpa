;;; lsp-hack.el --- lsp-mode client for hacklang

;; Copyright (C) 2017  John Allen <oss@porcnick.com>

;; Author: John Allen <oss@porcnick.com>
;; Version: 1.1.3
;; Package-Version: 20181114.1747
;; Package-Requires: ((lsp-mode "4.2"))
;; URL: https://github.com/jra3/lsp-hack

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <http://www.gnu.org/licenses/>.

;;; Commentary:
;; A simple LSP client for hooking up hack's hh_client/hh_server to lsp-mode
;; hacklang.org

;;; Code:
(require 'lsp-mode)


(defun lsp-hack--unimplemented (&rest _args)
  "nothing....")

(defun lsp-hack--initialize (client)
  "Initialization callback for hack.
CLIENT will be passed into this function by `lsp-define-stdio-client`"
  (lsp-client-on-notification client "$/cancelRequest" 'lsp-hack--unimplemented)
  (lsp-client-on-notification client "telemetry/event" 'lsp-hack--unimplemented)
  (lsp-client-on-request client "window/showStatus" 'lsp-hack--unimplemented))

(lsp-define-stdio-client
 lsp-hack "hack"
 (lsp-make-traverser #'(lambda (dir)
                         (directory-files
                          dir
                          nil
                          "\\.hhconfig")))
 '("hh_client" "lsp" "--from=emacs")
 :initialize #'lsp-hack--initialize)

(provide 'lsp-hack)
;;; lsp-hack.el ends here
