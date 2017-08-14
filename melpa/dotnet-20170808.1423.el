;;; dotnet.el --- Interact with dotnet CLI tool

;; Copyright (C) 2017 by Julien Blanchard

;; Author: Julien BLANCHARD <julien@sideburns.eu>
;; URL: https://github.com/julienXX/dotnet.el
;; Package-Version: 20170808.1423
;; Version: 0.10
;; Keywords: .net, tools

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
;;
;; dotnet CLI minor mode.
;; Provides some key combinations to interact with dotnet CLI.

;;; Code:

(defgroup dotnet nil
  "dotnet group."
  :prefix "dotnet-"
  :group 'tools)

(defcustom dotnet-mode-keymap-prefix (kbd "C-c C-n")
  "Dotnet minor mode keymap prefix."
  :group 'dotnet
  :type 'string)

;;;###autoload
(defun dotnet-add-package (package-name)
  "Add package reference from PACKAGE-NAME."
  (interactive "sPackage name: ")
  (dotnet-command (concat "dotnet add package " package-name)))

;;;###autoload
(defun dotnet-add-reference (project)
  "Add PROJECT to project reference."
  (interactive "sReference to: ")
  (dotnet-command (concat "dotnet add reference " project)))

;;;###autoload
(defun dotnet-build ()
  "Build a .NET project."
  (interactive)
  (dotnet-command "dotnet build -v n"))

;;;###autoload
(defun dotnet-clean ()
  "Clean build output."
  (interactive)
  (dotnet-command "dotnet clean -v n"))

(defvar dotnet-langs '("c#" "f#"))
(defvar dotnet-templates '("console" "classlib" "mstest" "xunit" "web" "mvc" "webapi"))

;;;###autoload
(defun dotnet-new (project-path template lang)
  "Initialize a new console .NET project.
PROJECT-PATH is the path to the new project, TEMPLATE is a
template (see `dotnet-templates'), and LANG is a supported
language (see `dotnet-langs')."
  (interactive (list (read-string "Project path: ")
                     (completing-read "Choose a template: " dotnet-templates)
                     (completing-read "Choose a language: " dotnet-langs)))
  (dotnet-command (concat "dotnet"
                          (mapconcat 'shell-quote-argument
                                     (list "new" template  "-o" project-path "-lang" lang)
                                     " "))))

;;;###autoload
(defun dotnet-publish ()
  "Publish a .NET project for deployment."
  (interactive)
  (dotnet-command "dotnet publish -v n"))

;;;###autoload
(defun dotnet-restore ()
  "Restore dependencies specified in the .NET project."
  (interactive)
  (dotnet-command "dotnet restore"))

;;;###autoload
(defun dotnet-run ()
  "Compile and execute a .NET project."
  (interactive)
  (dotnet-command "dotnet run"))

;;;###autoload
(defun dotnet-run-with-args (args)
  "Compile and execute a .NET project with ARGS."
  (interactive "sArguments: ")
  (dotnet-command (concat "dotnet run " args)))

;;;###autoload
(defun dotnet-test ()
  "Launch project unit-tests."
  (interactive)
  (dotnet-command "dotnet test"))

(defun dotnet-command (cmd)
  "Run CMD in an async buffer."
  (async-shell-command cmd "*dotnet*"))

(defvar dotnet-mode-command-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "a p") #'dotnet-add-package)
    (define-key map (kbd "a r") #'dotnet-add-reference)
    (define-key map (kbd "b") #'dotnet-build)
    (define-key map (kbd "c") #'dotnet-clean)
    (define-key map (kbd "n") #'dotnet-new)
    (define-key map (kbd "p") #'dotnet-publish)
    (define-key map (kbd "r") #'dotnet-restore)
    (define-key map (kbd "e") #'dotnet-run)
    (define-key map (kbd "C-e") #'dotnet-run-with-args)
    (define-key map (kbd "t") #'dotnet-test)
    map)
  "Keymap for dotnet-mode commands after `dotnet-mode-keymap-prefix'.")

(defvar dotnet-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd dotnet-mode-keymap-prefix) dotnet-mode-command-map)
    map)
  "Keymap for dotnet-mode.")

;;;###autoload
(define-minor-mode dotnet-mode
  "dotnet CLI minor mode."
  nil
  " dotnet"
  dotnet-mode-map
  :group 'dotnet)


(provide 'dotnet)
;;; dotnet.el ends here
