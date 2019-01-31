;;; poly-slim.el --- Polymodes for slim -*- lexical-binding: t -*-
;;
;; Author: Siavash Sajjadi and Vitalie Spinu
;; Maintainer: Vitalie Spinu
;; Version: 0.1.5
;; Package-Version: 20181010.2138
;; Package-Requires: ((emacs "25") (polymode "0.1.5") (slim-mode "1.1"))
;; URL: https://github.com/polymode/poly-slim
;; Keywords: emacs
;;
;; ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;; This file is *NOT* part of GNU Emacs.
;;
;; This program is free software; you can redistribute it and/or
;; modify it under the terms of the GNU General Public License as
;; published by the Free Software Foundation; either version 3, or
;; (at your option) any later version.
;;
;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
;; General Public License for more details.
;;
;; You should have received a copy of the GNU General Public License
;; along with this program; see the file COPYING.  If not, write to
;; the Free Software Foundation, Inc., 51 Franklin Street, Fifth
;; Floor, Boston, MA 02110-1301, USA.
;;
;; ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;;; Commentary:
;;
;; ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;;; Code:

(require 'polymode)
(require 'ruby-mode)
(require 'slim-mode)

;; (require 'css-mode)
;; (require 'scss-mode)
;; (require 'coffee-mode)
;; (require 'markdown-mode)

(defconst poly-slim-engines (regexp-opt '("ruby" "javascript" "css" "sass" "scss"
                                          "less" "coffe" "markdown" "textile" "rdoc")))

(defcustom pm-host/slim
  (pm-host-chunkmode :name "slim"
                     :mode 'slim-mode
                     ;; temporary
                     :protect-font-lock t
                     :protect-syntax t
                     :protect-indent t)
  "slim host chunkmode"
  :group 'poly-hostmodes
  :type 'object)

;; https://github.com/slim-template/slim/blob/master/README.md#embedded-engines-markdown-
(defcustom pm-inner/slim-code-block
  (pm-inner-auto-chunkmode :name "slim-code-block"
                           ;; not in comment
                           :head-matcher (cons (format "^[^/]*?\\(%s.*?:\\)" poly-slim-engines) 1)
                           :tail-matcher #'pm-same-indent-tail-matcher
                           :head-mode 'slim-mode
                           :indent-offset 4
                           :mode-matcher "[^ \t:]+")
  "Slim code block.
Slim code blocks are defined by the same level of
indentation (like python)."
  :group 'poly-innermodes
  :type 'object)

;;;###autoload  (autoload 'poly-slim-mode "poly-slim")
(define-polymode poly-slim-mode
  :hostmode 'pm-host/slim
  :innermodes '(pm-inner/slim-code-block))

(add-to-list 'auto-mode-alist '("\\.slim$" . poly-slim-mode))

(provide 'poly-slim)

;;; poly-slim.el ends here
