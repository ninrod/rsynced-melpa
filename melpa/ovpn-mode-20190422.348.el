;;; ovpn-mode.el --- an openvpn management mode -*- lexical-binding: t; -*-

;; This is free and unencumbered software released into the public domain.

;; Author: Bas Alberts <bas@anti.computer>
;; URL: https://github.com/anticomputer/ovpn-mode
;; Package-Version: 20190422.348

;; Version: 0.1
;; Package-Requires: ((emacs "24") (cl-lib "0.5"))

;; Keywords: comm

;;; Commentary:

;; ovpn-mode expects configurations to be named with the name.ovpn convention
;;
;; M-x ovpn will pop you into the default configuration directory and list any
;; existing .ovpn files from there.  You can then interact with that listing with
;; the following single key commands:
;;
;; s: start the selected ovpn
;; n: start the selected ovpn in a dedicated namespace
;; q: stop the selected ovpn
;; r: restart the selected ovpn
;;
;; There's a simple color coding scheme that tells you which state a given ovpn
;; is in:
;;
;; red: ovpn has stopped/dropped/broken, use q to reset/purge, or b to debug
;; pink: VPN is in the process of initializing
;; blue: namespaced VPN is ready for use
;; green: system wide VPN is ready for use
;;
;; Additionally you have available:
;;
;; i: remote link info for the selected ovpn
;; b: switch to the output buffer for the selected ovpn
;; e: edit the selected ovpn
;; d: set the active vpn conf directory
;; ~: apply a keyword filter to the current conf listing
;; 6: toggle ipv6 support on/off (automatically called on start of ovpn)
;; x: execute an asynchronous shell command in the context of any associated namespace
;; X: spawn an xterm in the context of any associated namespace
;; C: spawn a google-chrome instance in the context of any associated namespace
;; a: show all active vpn configurations accross all conf directories
;; h: describe mode
;;
;; ovpn-mode will maintain state for any running configurations, so you can
;; switch between multiple directories and keep state accordingly.

;;; Code:
(require 'cl-lib)
(require 'netrc)  ; authinfo handling

(defgroup ovpn nil
  "An OpenVPN management mode for Emacs."
  :prefix "ovpn-mode"
  :group  'comm)

(defcustom ovpn-mode-hook nil
  "Hook run after `ovpn-mode' has completely set up the buffer."
  :type  'hook
  :group 'ovpn)

(defcustom ovpn-mode-base-directory "~/vpn/default"
  "Default base directory for .ovpn configurations."
  :type  'string
  :group 'ovpn)

;; used for keyword filtering of .ovpn listings
(defvar ovpn-mode-base-filter nil)

(defcustom ovpn-mode-authinfo-path "~/.authinfo.gpg"
  "Path to authinfo data."
  :type 'string
  :group 'ovpn)

(defcustom ovpn-mode-check-authinfo t
  "Check authinfo for configname.ovpn associated user:pass data."
  :type 'boolean
  :group 'ovpn)

(defcustom ovpn-mode-power-user nil
  "Enables potentially dangerous interactive privileged shell use."
  :type 'boolean
  :group 'ovpn)

(defcustom ovpn-mode-ipv6-auto-toggle nil
  "Automatically toggle IPv6 support without prompting when t."
  :type 'boolean
  :group 'ovpn)

(defun ovpn-mode-pull-authinfo (config)
  "Return a LIST of user and password for a given config or NIL.

Example authinfo entry: machine CONFIG.OVPN login USER password PASS"
  (let* ((netrc (netrc-parse (expand-file-name ovpn-mode-authinfo-path)))
         (machine-entry (netrc-machine netrc config)))
    (if machine-entry
        (list (netrc-get machine-entry "login")
              (netrc-get machine-entry "password"))
      nil)))

(defun ovpn-mode-clear-authinfo-cache ()
  "Call this if you add new `ovpn-mode' authinfo data in a running Emacs instance."
  (interactive)
  (setq netrc-cache nil))

;;; major mode for future buffer and keymap enhancements
(defvar ovpn-mode-keywords '("ovpn"))
(defvar ovpn-mode-keywords-regexp (regexp-opt ovpn-mode-keywords 'words))
(defvar ovpn-mode-font-lock-keywords `((,ovpn-mode-keywords-regexp . font-lock-keyword-face)))

;;; struct so that we can expand this easily
(cl-defstruct struct-ovpn-mode-platform-specific
  ipv6-toggle
  ipv6-status
  netns-create
  netns-delete
  netns-delete-default-route)

(defvar ovpn-mode-platform-specific nil)

(cond
 ;; we are on a linux
 ((eq system-type 'gnu/linux)
  (setq ovpn-mode-platform-specific
        (make-struct-ovpn-mode-platform-specific
         :ipv6-toggle                'ovpn-mode-ipv6-linux-toggle
         :ipv6-status                'ovpn-mode-ipv6-linux-status
         :netns-create               'ovpn-mode-netns-linux-create
         :netns-delete               'ovpn-mode-netns-linux-delete
         :netns-delete-default-route 'ovpn-mode-netns-linux-delete-default-route
         )))
 ;; we are on some UNIX-like system with openvpn and sudo available
 (t
  ;; default to 'ignore non-specifics platform
  (setq ovpn-mode-platform-specific
        (make-struct-ovpn-mode-platform-specific
         :ipv6-toggle                'ignore
         :ipv6-status                'ignore
         :netns-create               'ignore
         :netns-delete               'ignore
         :netns-delete-default-route 'ignore
         ))))

(defvar ovpn-mode-map
  (let ((map (make-sparse-keymap)))
    ;; inherit from fundamental and do mode-global keybindings here
    (define-key map "s" 'ovpn-mode-start-vpn)
    (define-key map "r" 'ovpn-mode-restart-vpn)
    (define-key map "q" 'ovpn-mode-stop-vpn)
    (define-key map "i" 'ovpn-mode-info-vpn)
    (define-key map "b" 'ovpn-mode-buffer-vpn)
    (define-key map "e" 'ovpn-mode-edit-vpn)
    (define-key map "d" 'ovpn-mode-dir-set)
    (define-key map "~" 'ovpn-mode-dir-filter)
    (define-key map "n" 'ovpn-mode-start-vpn-with-namespace)
    (when ovpn-mode-power-user
      (define-key map "x" 'ovpn-mode-async-shell-command-in-namespace))
    (define-key map "X" 'ovpn-mode-spawn-xterm-in-namespace)
    (define-key map "R" 'ovpn-mode-spawn-rtorrent-screen-in-namespace)
    (define-key map "C" 'ovpn-mode-spawn-chrome-in-namespace)
    (define-key map "a" 'ovpn-mode-active)
    (define-key map "6" (struct-ovpn-mode-platform-specific-ipv6-toggle
                         ovpn-mode-platform-specific))
    (define-key map "h" 'describe-mode)
    map)
  "The keyboard map for `ovpn-mode'.")

(define-derived-mode ovpn-mode special-mode
  "ovpn-mode"
  "Management mode for interacting with openvpn configurations"
  (setq font-lock-defaults '((ovpn-mode-font-lock-keywords))))

(setq ovpn-mode-keywords nil)
(setq ovpn-mode-keywords-regexp nil)
;; end of major mode code

(defvar ovpn-mode-configurations nil)
(defvar ovpn-mode-buffer-name "*ovpn-mode*")
(defvar ovpn-mode-buffer nil)

;; control buffer switch or kill behavior on stop
(defvar ovpn-mode-switch-to-buffer-on-stop nil)

;; resolve full paths to binaries we use ... prevent CWD abuse
(defvar ovpn-mode-bin-paths
  `(
    ;; build a plist with full paths to any binaries we may use, it's fine if
    ;; some of them don't exist (e.g. firewall-cmd), since then they won't be
    ;; used anyways ...

    :echo          ,(executable-find "echo")
    :firewall-cmd  ,(executable-find "firewall-cmd")
    :google-chrome ,(executable-find "google-chrome")
    :ip            ,(executable-find "ip")
    :iptables      ,(executable-find "iptables")
    :kill          ,(executable-find "kill")
    :mkdir         ,(executable-find "mkdir")
    :openvpn       ,(executable-find "openvpn")
    :pgrep         ,(executable-find "pgrep")
    :rm            ,(executable-find "rm")
    :rtorrent      ,(executable-find "rtorrent")
    :screen        ,(executable-find "screen")
    :sudo          ,(executable-find "sudo")
    :sysctl        ,(executable-find "sysctl")
    :xterm         ,(executable-find "xterm")
    ))

(defmacro ovpn-mode-sudo (name buffer &rest args)
  "Sudo exec a command ARGS as NAME and output to BUFFER."
  `(with-current-buffer ,buffer
     (cd "/sudo::/tmp")
     (let ((process (start-file-process ,name ,buffer ,@args)))
       (when (process-live-p process)
         (set-process-filter process
                             #'(lambda (_proc string)
                                 (mapc 'message (split-string string "\n"))))))))

;; only use this for safety critical commands
(defun ovpn-mode-assert-shell-command (cmd)
  "Assert that a 'shell-command' CMD did not return error."
  (cl-assert (equal 0 (shell-command cmd)) t
             (format "Error executing: %s" cmd)))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;; Linux specifics

;; namespace management ... inspired by https://github.com/crasm/vpnshift.sh
;; in contrast, this implementation lets you juggle multiple namespaces at once

(defvar ovpn-mode-netns-base 0)
(defvar ovpn-mode-netns-free-base '()) ; :P

(defcustom ovpn-mode-netns-ns0 "1.0.0.1"
  "Default NS0 to use in `ovpn-mode' namespaces."
  :type  'string
  :group 'ovpn)

(defcustom ovpn-mode-netns-ns1 "1.1.1.1"
  "Default NS1 to use in `ovpn-mode' namespaces."
  :type  'string
  :group 'ovpn)

(defun ovpn-mode-netns-linux-create ()
  "Return a prop list containing an active namespace description."

  ;; we only increment the base-id counter if we can't recycle an old id
  ;; current logic hard limits us to 256-10 concurrent namespaces in use
  ;; because we also use the base-id to increment our network ranges in use
  ;; this should be moved to some proper CIDR logic

  ;; make an id available if we need one
  (when (= (length ovpn-mode-netns-free-base) 0)
    (message "Peeling off a network id for new namespace")
    (push ovpn-mode-netns-base ovpn-mode-netns-free-base)
    (setq ovpn-mode-netns-base (1+ ovpn-mode-netns-base)))

  (let* ((base-id (pop ovpn-mode-netns-free-base)) ;; recycle old base-id's
         (netns (format "ovpnmode_ns%d" base-id))
         (netns-buffer (get-buffer-create netns))
         (veth-default (format "veth_default%d" base-id))
         (veth-vpn (format "veth_vpn%d" base-id))

         ;; bind full bin paths
         (ip (plist-get ovpn-mode-bin-paths :ip))
         (firewall-cmd (plist-get ovpn-mode-bin-paths :firewall-cmd))
         (mkdir (plist-get ovpn-mode-bin-paths :mkdir))
         (echo (plist-get ovpn-mode-bin-paths :echo))
         (sysctl (plist-get ovpn-mode-bin-paths :sysctl))
         (iptables (plist-get ovpn-mode-bin-paths :iptables))
         (pgrep (plist-get ovpn-mode-bin-paths :pgrep))

         ;; this is a little icky, need some CIDR templating and upper bound checking
         (netns-range-default
          (format "%s/31"
                  (mapconcat
                   #'(lambda (x) (format "%d" x))
                   `[10 255 ,base-id 10] ; 10.255.X.10/31 base
                   ".")))
         (netns-range-vpn
          (format "%s/31"
                  (mapconcat
                   #'(lambda (x) (format "%d" x))
                   `[10 255 ,base-id 11] ; 10.255.X.11/31 base
                   ".")))

         ;; the device set for openvpn inside the namespace
         (netns-tunvpn (format "tunvpn%d" base-id))

         ;; initialize namespace ... not shell escaping any args because we
         ;; explicitly control the content of the variables here (see above)
         ;; in the case of potentially destructive commands, we will escape

         ;; use old ip netns syntax for wider compatibility base ... e.g. Ubuntu 14.04.5 LTS
         ;; does not support the newer -n/-netns switch

         (setup-cmds
          `(
            ;; setup the basic namespace
            (,ip "netns" "add" ,netns)
            (,mkdir "--parents" ,(format "/etc/netns/%s" netns))
            (,ip "netns" "exec" ,netns ,ip "address" "add" "127.0.0.1/8" "dev" "lo")
            (,ip "netns" "exec" ,netns ,ip "address" "add" "::1/128" "dev" "lo")
            (,ip "netns" "exec" ,netns ,ip "link" "set" "lo" "up")

            ;; build a veth tunnel
            (,ip "link" "add" ,veth-vpn "type" "veth" "peer" "name" ,veth-default)
            (,ip "link" "set" ,veth-vpn "netns" ,netns)
            (,ip "link" "set" ,veth-default "up")
            (,ip "netns" "exec" ,netns ,ip "link" "set" ,veth-vpn "up")
            (,ip "address" "add" ,netns-range-default "dev" ,veth-default)
            (,ip "netns" "exec" ,netns ,ip "address" "add" ,netns-range-vpn "dev" ,veth-vpn)
            (,ip "netns" "exec" ,netns ,ip "route" "add" "default" "via" ,(car (split-string netns-range-default "/")) "dev" ,veth-vpn)

            ;; enable IP forwarding ... we just keep this blanket enabled after set initially
            (,sysctl "-w" "net.ipv4.ip_forward=1")

            ;; set up the dns for the namespace
            (,echo "-e" ,(format "\"nameserver %s\\nnameserver %s\\n\""
                                 ovpn-mode-netns-ns0
                                 ovpn-mode-netns-ns1)
                   ">" ,(format "/etc/netns/%s/resolv.conf" netns))
            ))

         ;; enable masquerading
         (masquerade-cmds-iptables
          `(
            (,iptables "--table" "nat" "--append" "POSTROUTING" "--jump" "MASQUERADE" "--source" ,netns-range-default)
            ))
         (masquerade-cmds-firewalld
          `(
            ;; add interface to default zone
            (,firewall-cmd "-q" ,(format "--add-interface=%s" veth-default))

            ;; enable masquerading on the default zone
            (,firewall-cmd "-q"  "--add-masquerade")
            (,firewall-cmd "-q" ,(format "--add-rich-rule=\'rule family=\"ipv4\" source address=\"%s\" masquerade\'" netns-range-default))

            ))
         )

    ;; cycle through the setup commands synchronously as root
    (with-current-buffer netns-buffer
      (cd "/sudo::/tmp")
      ;; init namespace
      (dolist (cmd (append setup-cmds
                           ;; check if we're on a firewalld enabled system per chance
                           (if (equal (shell-command-to-string (format "%s firewalld" pgrep)) "")
                               masquerade-cmds-iptables
                             (progn
                               (message "Firewalld is running on this system, diverting masquerade setup")
                               masquerade-cmds-firewalld))))
        (let ((cmd (mapconcat #'(lambda (x) (format "%s" x)) cmd " ")))
          (message "ovpn-mode sudo executing: %s" cmd)

          ;; pull the chute hard on failure here
          (ovpn-mode-assert-shell-command cmd)

          )))

    ;; return the relevant property list for this namespace
    `(:netns ,netns
             :netns-buffer ,netns-buffer
             :veth-default ,veth-default
             :veth-vpn ,veth-vpn
             :netns-range-default ,netns-range-default
             :netns-range-vpn ,netns-range-vpn
             :netns-tunvpn ,netns-tunvpn
             :base-id ,base-id)
    ))

(defun ovpn-mode-netns-linux-delete-default-route (netns)
  "Remove the default route for a given network namespace property list NETNS."
  (let* ((netns-buffer (plist-get netns :netns-buffer))
         (netns-range-default (plist-get netns :netns-range-default))
         (veth-vpn (plist-get netns :veth-vpn))
         (namespace (plist-get netns :netns))
         (ip (plist-get ovpn-mode-bin-paths :ip)))

    (with-current-buffer netns-buffer
      (cd "/sudo::/tmp")
      ;; wait for the link to actually be up
      (ovpn-mode-assert-shell-command
       (format "%s netns exec %s %s route delete default via \"%s\" dev %s"
               ip
               namespace
               ip
               (car (split-string netns-range-default "/"))
               veth-vpn)))
    ))

(defun ovpn-mode-netns-linux-delete (netns)
  "Delete a given network namespace based on property list NETNS."

  (let ((netns-buffer (plist-get netns :netns-buffer))
        (namespace (plist-get netns :netns))
        (veth-default (plist-get netns :veth-default))
        (veth-vpn (plist-get netns :veth-vpn))
        (base-id (plist-get netns :base-id))
        (netns-range-default (plist-get netns :netns-range-default))
        (ip (plist-get ovpn-mode-bin-paths :ip))
        (rm (plist-get ovpn-mode-bin-paths :rm))
        (firewall-cmd (plist-get ovpn-mode-bin-paths :firewall-cmd))
        (iptables (plist-get ovpn-mode-bin-paths :iptables))
        (pgrep (plist-get ovpn-mode-bin-paths :pgrep)))

    ;; failure here is less critical

    (with-current-buffer netns-buffer
      (cd "/sudo::/tmp")

      ;; clear out the namespace and delete the links we created (these might error but you can safely ignore interface not found errors)
      (shell-command (format "%s netns delete %s" ip namespace))
      (shell-command (format "%s -rf /etc/netns/%s" rm (shell-quote-argument namespace)))

      ;; make these quiet because most likely they'll already be gone
      (shell-command-to-string (format "%s link delete %s" ip veth-default))
      (shell-command-to-string (format "%s link delete %s" ip veth-vpn))

      ;; as a rule we _only_ cleanup the things we _know_ we changed, we can make no assumptions about turning off masquerading completely
      ;; even if we gathered state at startup, emacs is routinely running for weeks if not months, so make no assumptions about the general
      ;; state of the system and the user preferences, only clean up things we _know_ we introduced into the environment

      (cond

       ;; firewalld
       ((not (equal (shell-command-to-string (format "%s firewalld" pgrep)) ""))
        (ovpn-mode-assert-shell-command
         (format "%s -q --remove-rich-rule=\'rule family=\"ipv4\" source address=\"%s\" masquerade\'" firewall-cmd netns-range-default))
        (ovpn-mode-assert-shell-command
         (format "%s -q --remove-interface=%s" firewall-cmd veth-default)))

       ;; fall through to iptables
       (t
        (ovpn-mode-assert-shell-command
         (format "%s -D POSTROUTING --table nat --jump MASQUERADE --source %s" iptables netns-range-default))))

      )

    ;; just clear out buffers unless we explicitly want to keep them around
    (unless ovpn-mode-switch-to-buffer-on-stop
      (kill-buffer netns-buffer))

    ;; release the base-id for re-use
    (push base-id ovpn-mode-netns-free-base)

    ))

;; ipv6 support

(defun ovpn-mode-ipv6-linux-status ()
  "Message status of IPv6 support."
  (let* ((sysctl (plist-get ovpn-mode-bin-paths :sysctl))
         (status_all
          (shell-command-to-string
           (format "%s net.ipv6.conf.all.disable_ipv6"
                   sysctl)))
         (status_def
          (shell-command-to-string
           (format "%s net.ipv6.conf.default.disable_ipv6"
                   sysctl)))
         (status_loc
          (shell-command-to-string
           (format "%s net.ipv6.conf.lo.disable_ipv6"
                   sysctl))))
    (if (and (string-match-p "^.*= 1" status_all)
             (string-match-p "^.*= 1" status_def)
             (string-match-p "^.*= 1" status_loc))
        ;; disabled
        nil
      ;; enabled
      t)))

(defun ovpn-mode-ipv6-linux-toggle ()
  "Toggle ipv6 state (enabled/disabled)."
  (interactive)
  (let* ((on-or-off '((t . 1) (nil . 0))) ; t means current val is 0 ...
         (sysctl-arg (cdr (assoc (ovpn-mode-ipv6-linux-status) on-or-off))))
    (when (or ovpn-mode-ipv6-auto-toggle
              (y-or-n-p (format "IPv6 support is %s, toggle to %s? "
                                (nth sysctl-arg '("off" "on")) ; :P
                                (nth sysctl-arg '("on" "off")))))
      (ovpn-mode-ipv6-linux-sysctl-disable sysctl-arg))))

(defun ovpn-mode-ipv6-linux-sysctl-disable (on-or-off)
  "Disable ipv6 support via sysctl to value of ON-OR-OFF."
  (unless (ovpn-mode-sudo
           "ipv6-linux-sysctl-disable"
           ;;(get-buffer-create "*Messages*")
           (current-buffer)
           (plist-get ovpn-mode-bin-paths :sysctl)
           "-w" (format "net.ipv6.conf.all.disable_ipv6=%d" on-or-off)
           "-w" (format "net.ipv6.conf.default.disable_ipv6=%d" on-or-off)
           "-w" (format "net.ipv6.conf.lo.disable_ipv6=%d" on-or-off))
    (message "Could not disable ipv6 support")))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;; End of Linux specifics

;;; this lets you juggle multiple dirs of confs and maintain state between them
(defun ovpn-mode-dir-set (dir)
  "Set new base DIR for ovpn confs and redisplay."
  (interactive "DPath to .ovpn configurations: ")
  (setq ovpn-mode-base-directory dir)
  (setq ovpn-mode-configurations nil)
  (ovpn))

(defun ovpn-mode-dir-filter (filter)
  "Keyword FILTER the current base listing and redisplay."
  (interactive "sFilter: ")
  (setq ovpn-mode-base-filter filter)
  (setq ovpn-mode-configurations nil)
  (ovpn))

(defun ovpn-mode-pull-configurations (dir &optional filter)
  "Pull .ovpn configs from directory DIR with an optional FILTER."
  (let ((regex (if filter (format ".*%s.*\\.ovpn$" filter) ".*\\.ovpn$")))
    (setq ovpn-mode-configurations (directory-files dir t regex))))

(defun ovpn-mode-link-status (status &optional clear)
  "Update the `ovpn-mode' current link status with STATUS or CLEAR."
  (save-excursion
    (with-current-buffer ovpn-mode-buffer
      (let ((inhibit-read-only t))
        (goto-char (point-max))
        ;; delete any existing status line
        (delete-region
         (progn (forward-visible-line 0) (point))
         (progn (forward-visible-line 1) (point))))
      (unless clear
        (ovpn-mode-insert-line (format "Last seen link status: %s" status) t)))))

(defvar ovpn-mode-process-map (make-hash-table :test 'equal))
(cl-defstruct struct-ovpn-process buffer buffer-name process conf pid link-remote netns)

(defun ovpn-mode-insert-line (line &optional no-newline)
  "Insert a LINE into the main `ovpn-mode' interface buffer optionally with NO-NEWLINE."
  (with-current-buffer ovpn-mode-buffer
    (goto-char (point-max))
    (let ((inhibit-read-only t))
      (let ((fmt (if no-newline "%s" "%s\n")))
        (insert (format fmt line)))
      (let* ((ovpn-process (gethash line ovpn-mode-process-map)))
        (cond ((and ovpn-process (process-live-p (struct-ovpn-process-process ovpn-process)))
               ;; highlight blue if we're running inside of a namespace
               (if (struct-ovpn-process-netns ovpn-process)
                   (ovpn-mode-highlight-conf line 'hi-blue)
                 (ovpn-mode-highlight-conf line 'hi-green)))
              ;; if it's in the list but the process is dead, it's waiting for purging by q
              (ovpn-process
               (ovpn-mode-highlight-conf line 'hi-red-b))
              )))))

;;; we use tramp's password prompt matcher
(require 'tramp)

;; deal with any ovpn password prompts
(defun ovpn-mode-push-prompt-input (proc prompt)
  "Echo a control char stripped PROMPT to PROC to retrieve requested user input."
  (process-send-string
   proc
   (concat (read-passwd
            (replace-regexp-in-string "\e\\[[0-9;]*m" "" prompt))
           "\n")))

(defun ovpn-process-filter (proc string)
  "Process filter for PROC which receives process output STRING."
  (when (process-live-p proc)
    (let* ((prompts
            ;; deal with openvpn auth and 2fa challenge response prompts as well
            (format "\\(%s\\)\\|\\(^.*\\(Enter Auth Username\\|Enter Auth Password\\|Enter Private Key Password\\|Response\\).*: *\\)\\|\\(^.*Enter Google Authenticator Code*\\)"
                    tramp-password-prompt-regexp))

           ;; grab this here because we use it a bunch in our cond
           (ovpn-process (gethash proc ovpn-mode-process-map))
           (netns (if ovpn-process (struct-ovpn-process-netns ovpn-process) nil))
           (conf (if ovpn-process (struct-ovpn-process-conf ovpn-process) nil)))

      (save-match-data
        (cond

         ;; handle password/auth prompts
         ((string-match-p prompts string)

          ;; deal with any ovpn password prompts
          (if ovpn-mode-check-authinfo
              (let ((authinfo (ovpn-mode-pull-authinfo (file-name-nondirectory conf))))
                (if (and authinfo (equal (length authinfo) 2))
                    (cond
                     ;; add other user/password prompts here as they come up
                     ((string-match-p "^.*Enter Auth Username.*: *" string)
                      (message "ovpn-mode: passing in authinfo based username")
                      (process-send-string proc (concat (nth 0 authinfo) "\n")))
                     ((string-match-p "^.*\\(Enter Auth Password\\|Enter Private Key Password\\).*: *" string)
                      (message "ovpn-mode: passing in authinfo based password")
                      (process-send-string proc (concat (nth 1 authinfo) "\n")))
                     ;; play safe and fall through to manual for any unknown prompts
                     (t
                      (ovpn-mode-push-prompt-input proc string)))
                  ;; something is likely wrong ... fall through to manual handling
                  (message "ovpn-mode: could not pull authinfo for: %s" (file-name-nondirectory conf))
                  (ovpn-mode-push-prompt-input proc string)))
            ;; do everything manual if no authinfo support enabled
            (ovpn-mode-push-prompt-input proc string)))

         ;; handle link remote info
         ((string-match "link remote: \\(.*\\)" string)
          (let ((link-remote (match-string 1 string)))
            (when ovpn-process
              (setf (struct-ovpn-process-link-remote ovpn-process) link-remote)
              ;; update status first time we see link remote, or on ovpn buffer redraws
              ;; only do this when an active mode buffer exists re: autostarted confs
              (when ovpn-mode-buffer
                (ovpn-mode-link-status
                 (format "%s (%s)" link-remote (file-name-nondirectory conf))))
              )))

         ;; handle init complete
         ((string-match-p "Initialization Sequence Completed" string)
          (if netns
              ;; drop default route in namespaced vpn on full vpn init
              (progn
                (message "Dropping default route in namespace %s" (plist-get netns :netns))
                (funcall (struct-ovpn-mode-platform-specific-netns-delete-default-route
                          ovpn-mode-platform-specific) netns)
                ;; namespace vpn highlight
                (when ovpn-mode-buffer
                  (ovpn-mode-unhighlight-conf conf)
                  (ovpn-mode-highlight-conf conf 'hi-blue))
                )
            ;; global vpn highlight
            (progn
              (when ovpn-mode-buffer
                (ovpn-mode-unhighlight-conf conf)
                (ovpn-mode-highlight-conf conf 'hi-green))))
          (message "%s (re)initialized" (file-name-nondirectory conf)))

         ;; handle DNS options ... overwrite any default servers we're using
         ;; we _could_ also dump a proper update-resolv-conf script into our
         ;; namespace dir, pass that to openvpn via --up and handle updating
         ;; the NS like that, but this is nicely self-contained
         ((string-match "PUSH_REPLY.*dhcp-option DNS \\(\\([0-9]+.\\)+[0-9]+\\)" string)
          (if netns
              (let ((dns (match-string 1 string))
                    (netns-buffer (plist-get netns :netns-buffer))
                    (netns-name (plist-get netns :netns)))
                (message "Setting DNS option for %s to nameserver %s"
                         (file-name-nondirectory conf) dns)
                (with-current-buffer netns-buffer
                  (cd "/sudo::/tmp")
                  (shell-command
                   (format
                    "%s -e \"nameserver %s\\n\" > /etc/netns/%s/resolv.conf"
                    (plist-get ovpn-mode-bin-paths :echo)
                    (shell-quote-argument dns)
                    netns-name))))))
         ))

      (when (buffer-live-p (process-buffer proc))
        (princ (format "%s" string) (process-buffer proc))))))

(defun ovpn-process-sentinel (proc string)
  "Process sentinel for PROC which receives input STRING."
  (let* ((ovpn-process (gethash proc ovpn-mode-process-map))
         (conf nil))
    (cond

     ;; this case implies something happened to our openvpn process without our intervention
     ;; since the hash-map entry for the process is still active ...
     ((and ovpn-process
           (memq (process-status proc) '(exit signal)))
      (setq conf  (struct-ovpn-process-conf ovpn-process))
      (ovpn-mode-unhighlight-conf conf)
      (ovpn-mode-highlight-conf conf 'hi-red-b)
      (message "Manually q conf \"%s\" to reset state (%s)"
               (file-name-nondirectory conf)
               (replace-regexp-in-string "\n$" "" string)))

     ;; switch on normal finish
     ((string-match-p "^finished" string)
      ;; swap to the associated buffer for convenient killing if desired
      (when ovpn-mode-switch-to-buffer-on-stop
        (switch-to-buffer (process-buffer proc))))

     ;; something funky happened ... check it out
     ((buffer-live-p (process-buffer proc))
      (message "Abnormal exit of openvpn, switching to buffer for debug")
      (princ (format "ovpn-process-sentinel: %s"
                     (replace-regexp-in-string "\n$" "" string)) (process-buffer proc))
      (switch-to-buffer (process-buffer proc))))
    ))

(defun ovpn-mode-purge-process-map ()
  "Clear the process hash table."
  (setq ovpn-mode-process-map (make-hash-table :test 'equal)))

(defun ovpn-mode-highlight-conf (conf face)
  "Highlight lines matching CONF with FACE."
  (with-current-buffer ovpn-mode-buffer
    (let ((inhibit-read-only t))
      (highlight-regexp conf face))))

(defun ovpn-mode-unhighlight-conf (conf)
  "Remove highlight from lines matching CONF."
  (with-current-buffer ovpn-mode-buffer
    (let ((inhibit-read-only t))
      (unhighlight-regexp conf))))

(defun ovpn-mode-start-vpn-with-namespace ()
  "Start ovpn at point with namespace."
  (interactive)
  (ovpn-mode-start-vpn t))

(defun ovpn-mode-start-vpn-conf (conf &optional with-namespace)
  "Start ovpn CONF optionally WITH-NAMESPACE."
  (interactive "fFull path to ovpn conf: ")

  ;; disable ipv6 (if so desired, and supported on the current platform)
  (when (funcall (struct-ovpn-mode-platform-specific-ipv6-status ovpn-mode-platform-specific))
    (funcall (struct-ovpn-mode-platform-specific-ipv6-toggle ovpn-mode-platform-specific)))

  (unless (not (gethash conf ovpn-mode-process-map))
    (error "Already started %s (q to purge)" (file-name-nondirectory conf)))

  (let* ((default-directory (file-name-directory conf))
         (buffer-name (file-name-nondirectory conf))
         (buffer (generate-new-buffer buffer-name))
         ;; init a namespace if needed (and supported on platform)
         (netns (if with-namespace
                    (funcall (struct-ovpn-mode-platform-specific-netns-create
                              ovpn-mode-platform-specific))
                  nil))
         ;; bin paths
         (ip (plist-get ovpn-mode-bin-paths :ip))
         (openvpn (plist-get ovpn-mode-bin-paths :openvpn)))

    (when (and with-namespace (not netns))
      (error "No namespace support on this platform!"))

    ;; if you are using something else, ensure a "openvpn" binary exists in exec-path, this may
    ;; require a symlink e.g. for macports openvpn2 please symlink /opt/local/sbin/openvpn2 to /opt/local/sbin/openvpn
    (unless openvpn
      (error "No openvpn binary found in exec-path"))

    (with-current-buffer buffer
      (cd (format "/sudo::%s" default-directory))
      (let ((process (apply 'start-file-process
                            buffer-name
                            buffer
                            (if (and with-namespace netns)
                                ;; set up an openvpn instance for conf inside a given namespace
                                (progn
                                  (message "Starting %s with namespace %s"
                                           (file-name-nondirectory conf)
                                           (plist-get netns :netns))
                                  (list ip
                                        "netns" "exec"
                                        (format "%s" (plist-get netns :netns))
                                        openvpn
                                        ;; be explicitly verbose to the max default range
                                        "--verb" "4"
                                        "--cd" (file-name-directory conf)
                                        "--config" conf
                                        "--dev" (plist-get netns :netns-tunvpn)))
                              ;; just start normally for the main system route
                              (list openvpn
                                    "--verb" "4"
                                    "--cd" (file-name-directory conf)
                                    "--config" conf)))))

        (unless (process-live-p process)
          (error "Could not start openvpn for %s" (file-name-nondirectory conf)))

        (set-process-filter process 'ovpn-process-filter)
        (set-process-sentinel process 'ovpn-process-sentinel)

        ;; throw the process struct into the lookup maps
        (let ((ovpn-process (make-struct-ovpn-process
                             :buffer buffer
                             :buffer-name buffer-name
                             :process process
                             :conf conf
                             :netns netns)))
          ;; so we can look up by both conf name as well as process
          (puthash conf ovpn-process ovpn-mode-process-map)
          (puthash process ovpn-process ovpn-mode-process-map))

        ;; highlight to the starting state color
        ;; pink means 'initializing'
        ;; blue means 'namespace vpn ready for use'
        ;; green means 'regular vpn ready for use'
        (message "Started %s, wait for init to complete (n: blue, s: green)"
                 (file-name-nondirectory conf))
        (when ovpn-mode-buffer
          (ovpn-mode-highlight-conf conf 'hi-pink))))))

(defun ovpn-mode-start-vpn (&optional with-namespace)
  "Start ovpn conf at point optionally WITH-NAMESPACE.

This assumes any associated certificates live in the same directory as the conf."
  (interactive)
  (let* ((conf (replace-regexp-in-string "\n$" "" (thing-at-point 'line))))
    (when (string-match-p ".*\\.ovpn" conf)
      (ovpn-mode-start-vpn-conf conf with-namespace))))

;;; as root through kill since we don't know about priv-drops and can't use signal-process
(defun ovpn-mode-signal-process (sig ovpn-process)
  "Send SIG to OVPN-PROCESS -> process (sudo) child directly."
  (when ovpn-process
    (progn
      (let* ((process (struct-ovpn-process-process ovpn-process))
             (buffer (struct-ovpn-process-buffer ovpn-process))
             ;(buffer-name (struct-ovpn-process-buffer-name ovpn-process))
             (kill (plist-get ovpn-mode-bin-paths :kill)))
        (if (process-live-p process)
            (ovpn-mode-sudo
             "ovpn-mode-signal-process"
             buffer
             kill (format "-%d" sig) (format "%d" (process-id process)))
          (message "Target openvpn process no longer alive"))))))

(defun ovpn-mode-stop-vpn-conf (conf)
  "Stop openvpn CONF through SIGTERM."
  (interactive "fFull path to ovpn conf: ")
  (let* ((ovpn-process (gethash conf ovpn-mode-process-map))
         (netns (if ovpn-process (struct-ovpn-process-netns ovpn-process) nil)))

    (unless ovpn-process
      (error "No active openvpn process found for %s" conf))

    (ovpn-mode-signal-process 15 ovpn-process)
    (when ovpn-mode-buffer
      (ovpn-mode-unhighlight-conf conf))
    ;; pull the hash table entry for this instance
    (remhash conf ovpn-mode-process-map)
    (remhash (struct-ovpn-process-process ovpn-process) ovpn-mode-process-map)
    ;; clear the status line from the mode buffer
    (ovpn-mode-link-status nil t)
    ;; clear out any associated namespace if needed
    (when netns
      (funcall (struct-ovpn-mode-platform-specific-netns-delete
                ovpn-mode-platform-specific) netns))))

(defun ovpn-mode-stop-vpn ()
  "Stop openvpn conf at point through SIGTERM."
  (interactive)
  (let* ((conf (replace-regexp-in-string "\n$" "" (thing-at-point 'line))))
    (ovpn-mode-stop-vpn-conf conf)))

(defun ovpn-mode-restart-vpn ()
  "Restart openvpn conf through SIGHUP."
  (interactive)
  (let* ((conf (replace-regexp-in-string "\n$" "" (thing-at-point 'line)))
         (ovpn-process (gethash conf ovpn-mode-process-map)))
    ;; relay SIGHUP through sudo
    (when ovpn-process
      (ovpn-mode-signal-process 1 ovpn-process))))

(defun ovpn-mode-info-vpn ()
  "Dump info stats on selected ovpn conf."
  (interactive)
  (let* ((conf (replace-regexp-in-string "\n$" "" (thing-at-point 'line)))
         (ovpn-process (gethash conf ovpn-mode-process-map)))
    (when ovpn-process
      (let ((link-remote (struct-ovpn-process-link-remote ovpn-process))
            (netns (struct-ovpn-process-netns ovpn-process))
            (conf (file-name-nondirectory conf)))
        (cond ((and link-remote netns)
               (message "%s: %s (namespace: %s)"
                        conf link-remote (plist-get netns :netns)))
              (link-remote
               (message "%s: %s (no namespace)" conf link-remote))
              (t
               (message "%s: no info available" conf)))))))

(defun ovpn-mode-buffer-vpn ()
  "Switch to the associated ovpn conf output buffer."
  (interactive)
  (let* ((conf (replace-regexp-in-string "\n$" "" (thing-at-point 'line)))
         (ovpn-process (gethash conf ovpn-mode-process-map)))
    (when ovpn-process
      (switch-to-buffer (struct-ovpn-process-buffer ovpn-process)))))

(defun ovpn-mode-spawn-xterm-in-namespace ()
  "Execute an xterm inside of the selected namespace."
  (interactive)
  (let* ((conf (replace-regexp-in-string "\n$" "" (thing-at-point 'line)))
         (proc-name (format "xterm-%s" (file-name-nondirectory conf)))
         (cmd (format "%s -e \"%s -u %s PS1=\\\"%s> \\\" /bin/sh\""
                      (plist-get ovpn-mode-bin-paths :xterm)
                      (plist-get ovpn-mode-bin-paths :sudo)
                      (user-real-login-name)
                      (file-name-nondirectory conf))))
    ;; we exec this as root because of the priv drop that occurs on the -e
    (ovpn-mode-async-shell-command-in-namespace cmd "root" proc-name)))

(defun ovpn-mode-spawn-rtorrent-screen-in-namespace (user dir torrent)
  "Execute a headless screen rtorrent for TORRENT in DIR as USER.
Use `screen -list' to find and attach your desired namespaced rtorrent instance."
  (interactive "sSpawn rtorrent in screen as (default current user): \nfDownload directory: \nsTorrent URI (default no URI): ")
  (let* ((conf (replace-regexp-in-string "\n$" "" (thing-at-point 'line)))
         (user (if (equal user "") (user-real-login-name) user))
         (torrent (if (equal torrent "") nil torrent))
         (proc-name (format "rtorrent-%s" (file-name-nondirectory conf)))
         ;; run screen -dmS headless so we're not locked to emacs terminal support for the screen process
         (cmd
          (cond (torrent
                 ;; start with a torrent
                 (format "%s -fa -DmS %s %s -s %s -d %s \"%s\""
                         (plist-get ovpn-mode-bin-paths :screen) proc-name
                         (plist-get ovpn-mode-bin-paths :rtorrent)
                         dir
                         dir
                         torrent))
                (t
                 ;; start without a torrent
                 (format "%s -fa -DmS %s %s -s %s -d %s"
                         (plist-get ovpn-mode-bin-paths :screen) proc-name
                         (plist-get ovpn-mode-bin-paths :rtorrent)
                         dir
                         dir)))
          ))
    (ovpn-mode-async-shell-command-in-namespace cmd user proc-name)))

(defvar ovpn-mode-chrome-data-dir-base "/dev/shm")

(defun ovpn-mode-spawn-chrome-in-namespace ()
  "Execute an incognito session of chrome with a namespace dedicated user-data-dir."
  (interactive)
  (let* ((conf (replace-regexp-in-string "\n$" "" (thing-at-point 'line)))
         (ovpn-process (gethash conf ovpn-mode-process-map))
         (netns (if ovpn-process (struct-ovpn-process-netns ovpn-process) nil))
         (data-dir (if netns (shell-quote-argument (plist-get netns :netns)) nil))
         (user (user-real-login-name))
         (proc-name (format "chrome-%s-%s" user (file-name-nondirectory conf)))
         ;; we have to go through an additional /bin/sh -c here because otherwise
         ;; the && would bust us out of the namespace exec since that is executed
         ;; through: "ip netns exec %s sudo -u %s %s"
         (cmd (format "/bin/sh -c \"mkdir %s/%s; %s --no-referrers --disable-translate --disable-plugins --disable-plugins-discovery --disable-client-side-phishing-detection --incognito --user-data-dir=%s/%s && %s -rf %s/%s\""
                      ovpn-mode-chrome-data-dir-base
                      data-dir
                      (plist-get ovpn-mode-bin-paths :google-chrome)
                      ovpn-mode-chrome-data-dir-base
                      data-dir
                      (plist-get ovpn-mode-bin-paths :rm)
                      ovpn-mode-chrome-data-dir-base
                      data-dir)))
    (when netns
      (ovpn-mode-async-shell-command-in-namespace cmd user proc-name))))

(defun ovpn-mode-async-shell-command-in-namespace (cmd user &optional proc-name)
  "Run CMD (optionally as PROC-NAME) as USER in the conf associated namespace.

Please be very careful how you use this, as this is passed to the shell directly
and with root privileges.

Also note that you will have to properly shell escape to ensure you actually
execute your desired command within the context of the namespace.

E.g. it would be flawed to provide a command like:

something && somethingelse

Since this would expand into:

sh -c ip netns exec namespacename sudo -u user something && somethingelse

Thus something else would execute OUTSIDE the namespace, instead you'd want to do:

/bin/sh -c \"something && somethingelse\"

Which would expand into:

sh -c ip netns exec namespacename sudo -u user /bin/sh -c \"something && somethingelse\""
  (interactive "sCmd: \nsUser (default current user): \n")
  (let* ((conf (replace-regexp-in-string "\n$" "" (thing-at-point 'line)))
         (ovpn-process (gethash conf ovpn-mode-process-map))
         (netns (if ovpn-process (struct-ovpn-process-netns ovpn-process) nil))
         (user (if (equal user "") (user-real-login-name) user)))

    (unless netns
      (error "%s" "No associated namespace at point"))

    (message "Attempting to execute \"%s\" in namespace %s as user %s"
             cmd
             (plist-get netns :netns)
             user)

    ;; you can do stuff like xterm -e "sudo -u targetuser bash" here
    ;; to deal with e.g. X server annoyances (as user root obviously)

    (ovpn-mode-sudo
     (or proc-name "ovpn-mode-sudo-exec")
     (plist-get netns :netns-buffer)
     "/bin/sh" "-c"
     (format "ip netns exec %s %s -u %s %s"
             (plist-get netns :netns)
             (plist-get ovpn-mode-bin-paths :sudo)
             user
             cmd))))

(defun ovpn-mode-edit-vpn ()
  "Open the selected ovpn conf for editing."
  (interactive)
  (let* ((conf (replace-regexp-in-string "\n$" "" (thing-at-point 'line))))
    (when (string-match-p ".*\\.ovpn" conf)
      (find-file conf))))

(defun ovpn-mode-active ()
  "Wrapper for the main entry that enters the only-active display mode."
  (interactive)
  (ovpn t))

;;;###autoload
(defun ovpn (&optional show-active)
  "Main entry point for `ovpn-mode' interface optionally filters on SHOW-ACTIVE."
  (interactive)
  (cond ((not ovpn-mode-buffer)
         (setq ovpn-mode-buffer (get-buffer-create ovpn-mode-buffer-name))
         (with-current-buffer ovpn-mode-buffer
           ;; initialize to read only, lift inhibit-read-only to t where needed
           (setq buffer-read-only t)
           ;; set a local kill-buffer-hook to reset our configurations and buffer
           (add-hook 'kill-buffer-hook '(lambda () (setq ovpn-mode-configurations nil
                                                    ovpn-mode-buffer nil)) nil t))
         (switch-to-buffer ovpn-mode-buffer)
         (ovpn-mode))
        (t
         (switch-to-buffer ovpn-mode-buffer)))
  ;; populate with confs if needed ... if empty or we just want to list active
  (when (or (not ovpn-mode-configurations) show-active)
    ;; we clear ovpn-mode-configurations on ovpn-mode-dir-set thus triggering
    ;; a redisplay ... ovpn-mode-insert-line will check for any active processes
    ;; associated with a displayed config and highlight accordingly
    (with-current-buffer ovpn-mode-buffer
      (let ((inhibit-read-only t))
        (erase-buffer)))
    (ovpn-mode-insert-line
     "s start, n start with namespace, r restart, q stop/purge\n\n")

    (cond

     ;; dump any active configurations, regardless of directory base
     (show-active
      (ovpn-mode-insert-line "Active openvpn configurations:\n")
      (maphash #'(lambda (key _value)
                   ;; our hash map contains process objects and conf name strings
                   (when (stringp key) (ovpn-mode-insert-line key))) ovpn-mode-process-map))

     ;; pull configurations from the active directory base
     (t
      (ovpn-mode-insert-line
       (if ovpn-mode-base-filter
           (format "Available configurations in %s with \"%s\":\n"
                   ovpn-mode-base-directory
                   ovpn-mode-base-filter)
         (format "Available configurations in %s:\n"
                 ovpn-mode-base-directory)))
      (cond ((file-exists-p ovpn-mode-base-directory)
             (ovpn-mode-pull-configurations ovpn-mode-base-directory ovpn-mode-base-filter)
             (setq ovpn-mode-base-filter nil) ; reset filter to nil
             (mapc #'(lambda (config) (ovpn-mode-insert-line config)) ovpn-mode-configurations))
            (t
             (ovpn-mode-insert-line "Please set a valid base directory (d)")))))

    (ovpn-mode-insert-line "\n") ; space for link status
    ;; put any active link status
    (dolist (conf ovpn-mode-configurations)
      (let* ((ovpn-process (gethash conf ovpn-mode-process-map))
             (link-remote (if ovpn-process
                              (struct-ovpn-process-link-remote ovpn-process)
                            nil)))
        (when link-remote
          (ovpn-mode-link-status (format "%s (%s)" link-remote (file-name-nondirectory conf))))))
    (goto-char (point-min))))

(provide 'ovpn-mode)
;;; ovpn-mode.el ends here
