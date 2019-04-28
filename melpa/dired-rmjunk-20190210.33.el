;;; dired-rmjunk.el --- A home directory cleanup utility for Dired. -*- lexical-binding: t; -*-

;; Copyright (C) 2019 Jakob L. Kreuze

;; Author: Jakob L. Kreuze <zerodaysfordays@sdf.lonestar.org>
;; Version: 1.0
;; Package-Version: 20190210.33
;; Package-Requires (dired)
;; Keywords: files matching
;; URL: https://git.sr.ht/~jakob/dired-rmjunk

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

;; dired-rmjunk is a port of Jakub Klinkovský's home directory cleanup tool to
;; Dired. The interactive function, `dired-rmjunk' will mark all files in the
;; current Dired buffer that match one of the patterns specified in
;; `dired-rmjunk-patterns'. The tool is intended as a simple means for
;; keeping one's home directory tidy -- removing "junk" dotfiles.

;; The script that this is based on can be found at:
;; <https://github.com/lahwaacz/Scripts/blob/master/rmshit.py>

;;; Code:

(defgroup dired-rmjunk ()
  "Remove junk files with dired."
  :group 'dired)

(defcustom dired-rmjunk-patterns
  '(".adobe" ".macromedia" ".recently-used"
    ".local/share/recently-used.xbel" "Desktop" ".thumbnails" ".gconfd"
    ".gconf" ".local/share/gegl-0.2" ".FRD/log/app.log" ".FRD/links.txt"
    ".objectdb" ".gstreamer-0.10" ".pulse" ".esd_auth" ".config/enchant"
    ".spicec" ".dropbox-dist" ".parallel" ".dbus" "ca2" "ca2~"
    ".distlib" ".bazaar" ".bzr.log" ".nv" ".viminfo" ".npm" ".java"
    ".oracle_jre_usage" ".jssc" ".tox" ".pylint.d" ".qute_test"
    ".QtWebEngineProcess" ".qutebrowser" ".asy" ".cmake" ".gnome"
    "unison.log" ".texlive" ".w3m" ".subversion" "nvvp_workspace")
  "Default list of files to remove. Current as of f707d92."
  :type '(list string))

;;;###autoload
(defun dired-rmjunk ()
  "Mark all junk files in the current dired buffer.
'Junk' is defined to be any file with a name matching one of the
patterns in `dired-rmjunk-patterns'."
  (interactive)
  (when (eq major-mode 'dired-mode)
    (save-excursion
      (let ((files-marked-count 0))
        (dolist (file (directory-files dired-directory))
          (dolist (pattern dired-rmjunk-patterns)
            (when (string-match pattern file)
              (setq files-marked-count (1+ files-marked-count))
              (dired-goto-file (concat (expand-file-name dired-directory) file))
              (dired-flag-file-deletion 1))))
        (message (if (zerop files-marked-count)
                     "No junk files found :)"
                   "Junk files marked."))))))

(provide 'dired-rmjunk)
;;; dired-rmjunk.el ends here
