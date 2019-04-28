This package is designed to recreate a Quake-style drop-down console fully
within Emacs, compatible with 'eshell, 'term, 'ansi-term, and 'shell modes.
It has multi-tab functionality, and the tabs can be moved and renamed
(different shells can be opened and used in different tabs).  It is intended
to be bound to shortcut key like F12 to toggle it off-and-on.

Installation:
To install manually, clone the git repo somewhere and put it in your
load-path, e.g., add something like this to your init.el:
(add-to-list 'load-path
            "~/.emacs.d/equake/")
 (require 'equake)

Usage:
Run with:---
emacsclient -n -e '(equake-invoke)' ,
after launching an Emacs daemon of course.

For multimonitor use using X11, you can set
(setq equake-use-xdotool-probe 't) to use xdotool to
automatically detect which screen the Equake frame should open on.

Alternatively, on a non-X11 multi-monitor setup, launch:
emacsclient -n -c -e '(equake-invoke)' -F '((title . "*transient*") (alpha . (0 . 0)) (width . (text-pixels . 0)) (height . (text-pixels . 0)))'
(although this may be noticably slower)

I recommend binding the relevant command to a key like F12 in your DE/WM.
Executing this command will create a new equake console
on your screen the first time, and subsequently toggle
the console (i.e. hide or show it).

It works with eshell, ansi-term, term, shell.  But it was
really designed to work with eshell, which is the default.
New console tabs can be specified to open with a shell
other than the default shell.

Equake is designed to work with multi-screen setups,
with a different set of tabs for each screen.

You'll probably also want to configure your WM/DE to
ignore the window in the task manager etc and
have no titlebar or frame

In KDE Plasma 5:
systemsettings > Window Management > Window Rules:
Button: New

In Window matching tab:
Description: equake rules
Window types: Normal Window
Window title: Substring Match : *EQUAKE*

In Arrangement & Access tab:
Check: 'Keep above' - Force - Yes
Check: 'Skip taskbar' - Force - Yes
Check: 'Skip switcher' - Force - Yes

In Appearance & Fixes tab:
Check: 'No titlebar and frame' - Force - Yes
Check: Focus stealing prevention - Force - None
Check: Focus protection - Force - Normal
Check: Accept focus - Force - Yes

In awesomewm, probably adding to your 'Rules' something
like this:

{ rule = { instance = "*EQUAKE*", class = "Emacs" },
   properties = { titlebars_enabled = false } },

In stumpwm, I'm not sure: probably the frame needs to be set as floating.

Advice:
add (global-set-key (kbd "C-x C-c") 'equake-check-if-in-equake-frame-before-closing)
to your settings to prevent accidental closure of equake frames

TODO:
1. defcustoms:
  (a) for keybindings
  (b) make shell choice into actual list, or else more flexible functions
2. Prevent last tab from being closed, or at least prompt.
3. Test on:
   (a) MacOS -- reported to work
   (b) Windows -- ??
  Comments: In theory it should work on Mac & Windows, since frame.el defines
            frame-types 'ns (=Next Step) and 'w32 (=Windows).
