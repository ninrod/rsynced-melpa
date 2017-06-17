                             _____________

                                FCITX.EL

                              Junpeng Qiu
                             _____________


Table of Contents
_________________

1 Setup
2 Example Settings
3 Features
.. 3.1 The Feature List
.. 3.2 Features Enabled in Both Setup Commands
..... 3.2.1 Disable Fcitx by Prefix Keys
..... 3.2.2 Evil Support
..... 3.2.3 Character & Key Input Support
..... 3.2.4 `org-speed-command' Support
.. 3.3 Features Enabled *ONLY* in `fcitx-default-setup' Command
..... 3.3.1 `M-x', `M-!', `M-&' and `M-:' Support
.. 3.4 Features Enabled *ONLY* in `fcitx-aggressive-setup' Command
..... 3.4.1 Disable Fcitx in Minibuffer
.. 3.5 Extra Functions That are not Enabled in Both Commands
..... 3.5.1 I-search Support
4 Using D-Bus Interface
5 Work with Other Input Methods
6 TODO TODO


[[file:http://melpa.org/packages/fcitx-badge.svg]]
[[file:http://stable.melpa.org/packages/fcitx-badge.svg]]

Better [fcitx] integration for Emacs.

[中文版(需要更新）]

This package provides a set of functions to make fcitx work better in
Emacs.

This is originally designed to be used along with `fcitx' on Linux, but
it can also be used on other platforms with other input methods.
- For OSX users, see [fcitx-remote-for-osx]
- For Windows users, see [fcitx-remote-for-windows]
- For users who want to add support for other input methods, see the
  following section: *Work with Other Input methods*


[[file:http://melpa.org/packages/fcitx-badge.svg]]
http://melpa.org/#/fcitx

[[file:http://stable.melpa.org/packages/fcitx-badge.svg]]
http://stable.melpa.org/#/fcitx

[fcitx] https://github.com/fcitx/fcitx/

[中文版(需要更新）] ./README-zh.org

[fcitx-remote-for-osx]
https://github.com/CodeFalling/fcitx-remote-for-osx

[fcitx-remote-for-windows]
https://github.com/cute-jumper/fcitx-remote-for-windows


1 Setup
=======

  Recommendation: install this package from [melpa].

  Or, if you like to manually install this package:
  ,----
  | (add-to-list 'load-path "/path/to/fcitx.el")
  | (require 'fcitx)
  `----

  You can choose between two different setup commands:
  ,----
  | M-x fcitx-default-setup
  `----
  or
  ,----
  | M-x fcitx-aggressive-setup
  `----

  The differences between these two setups will be explained later.


[melpa] http://melpa.org


2 Example Settings
==================

  All the examples below use `fcitx-aggressive-setup'.

  For Emacs users on Linux:
  ,----
  | (fcitx-aggressive-setup)
  | (setq fcitx-use-dbus t)
  `----

  For Emacs users on OS X:
  ,----
  | (fcitx-aggressive-setup)
  `----

  For Spacemacs users:
  ,----
  | ;; Make sure the following comes before `(fcitx-aggressive-setup)'
  | (setq fcitx-active-evil-states '(insert emacs hybrid)) ; if you use hybrid mode
  | (fcitx-aggressive-setup)
  | (fcitx-prefix-keys-add "M-m") ; M-m is common in Spacemacs
  | ;; (setq fcitx-use-dbus t) ; uncomment if you're using Linux
  `----

  *NOTE*: In Linux, using the `dbus' interface has a better performance.
  But if you also set `echo-keystrokes', you may experience a lagging
  issue.  See [#30].  If that is something you can't tolerate, don't
  change the value of `fcitx-use-dbus' to `t'.


[#30] https://github.com/cute-jumper/fcitx.el/issues/30


3 Features
==========

  This package comes with a bunch of features to provide better `fcitx'
  integration for Emacs.  For every feature, you can enable or disable
  it using the corresponding `*-turn-on' or `*-turn-off' command.

  To simplify the configuration, we provide two different setup
  commands, `fcitx-default-setup' and `fcitx-aggressive-setup'.  They
  will enable different lists of features.  You can choose the setup
  command that fits your need best.  For users who want a better
  control, you can define and use your own setup command by enabling the
  features you want using the `*-turn-on' commands.


3.1 The Feature List
~~~~~~~~~~~~~~~~~~~~

  *X* indicates that the corresponding feature is enabled.

   Feature                      fcitx-default-setup  fcitx-aggressive-setup
  --------------------------------------------------------------------------
   Prefix-key                   X                    X
   Evil                         X                    X
   Character & key input        X                    X
   M-x,M-!,M-& and M-:          X
   Disable fcitx in minibuffer                       X
   org-speed-command support    X                    X
   Isearch


3.2 Features Enabled in Both Setup Commands
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

  The following features are enabled in both `fcitx-default-setup' and
  `fcitx-aggressive-setup'.  You don't have to do anything if you're
  satisfied with the default settings.


3.2.1 Disable Fcitx by Prefix Keys
----------------------------------

  - *Why this feature*

    If you've enabled fcitx, then you can't easily change your buffer by
    `C-x b' because the second key, `b', will be blocked by fcitx(and
    you need to press `enter' in order to send `b' to emacs).  This
    feature allows you to temporarily disable fcitx after pressing some
    prefix keys you've defined.

  - *What do the pre-defined setup comamnds do*

    Both setup comamnds define `C-x' and `C-c' to be such prefix keys,
    which means fcitx will be disabled after `C-x' or `C-c' is pressed.
    This setting should be enough for most users.

  - *For Spacemacs users*

    If you're a Spacemacs user who uses it in the Emacs way(or hybrid
    mode), it is possible that you want `M-m' to be the prefix key too.
    You can use the following command to add `M-m':
    ,----
    | (fcitx-prefix-keys-add "M-m")
    `----

  - *For users who want more customizations*

    You can define the prefix keys as you want:
    ,----
    | (fcitx-prefix-keys-add "C-x" "C-c" "C-h" "M-s" "M-o")
    `----

    After defining prefix keys, you need to call
    ,----
    | (fcitx-prefix-keys-turn-on)
    `----
    to enable this feature.

    Of course, you can use
    ,----
    | (fcitx-prefix-keys-turn-off)
    `----
    to disable this feature.


3.2.2 Evil Support
------------------

  - *Why this feature*

    This feature allows you to disable fcitx when you exit the "insert
    mode" and to reenable fcitx after enter "insert mode".  Similar to
    [fcitx.vim].

    In addition, it will also disable fcitx if you use
    `switch-to-buffer' or `other-window' to switch to a buffer which is
    not in "insert mode".  For example, if you're currently in "insert
    mode" in buffer `A' and you've enabled fcitx, then you call
    `switch-to-buffer' to switch to another buffer `B', which is
    currently, say, in normal mode, then fcitx will be disabled in
    buffer `B'.

  - *What do the pre-defined setup comamnds do*

    Both setup commands enable this feature.  By default, `fcitx.el'
    consider both `evil-insert-state' and `evil-emacs-state' as "insert
    mode".  Any transition from `evil-insert-state' or
    `evil-emacs-state' to any other evil state will disable fcitx if
    necessary.

  - *How to customize it*

    The evil states in which fcitx should be enabled are defined in the
    variable `fcitx-active-evil-states'.  The default value is `(insert
    emacs)', which means fcitx will be enabled if necessary when
    entering `evil-insert-state' or `evil-emacs-state'.  For Spacemacs
    users who use its hybrid mode, you may also want to add hybrid mode
    to the list:
    ,----
    | (setq fcitx-active-evil-states '(insert emacs hybrid))
    `----

  - *Bugs*

    Note that currently the Evil support is not perfect.  If you come
    across any bugs, consider filing an issue or creating a pull
    request.


[fcitx.vim] https://github.com/vim-scripts/fcitx.vim


3.2.3 Character & Key Input Support
-----------------------------------

  - *Why this feature*
    - Case 1: If you're using `ace-pinyin', you need to input a letter
      after calling `ace-pinyin'.
    - Case 2: You're using `C-h k' to see the binding for a key
      sequence.
    In both cases, fcitx will block your input.  This feature can make
    `fcitx' automatically disabled when you're required to input a key
    sequence or a character.

  - *What do the pre-defined setup comamnds do*

    Both commands call `(fcitx-read-funcs-turn-on)' to enable this
    feature.

  - *What if I don't want it*

    Use `(fcitx-read-funcs-turn-off)' to disable it.


3.2.4 `org-speed-command' Support
---------------------------------

  - *Why this feature*

    This feature allows fcitx to be disabled when the cursor is at the
    beginning of an org heading so that you can use speed keys such as
    `n' and `p'.

  - *What do the pre-defined setup comamnds do*

    Both commands call `(fcitx-org-speed-command-turn-on)' to enable
    this feature.

  - *What if I don't want it*

    Use `(fcitx-org-speed-command-turn-off)' to disable it.


3.3 Features Enabled *ONLY* in `fcitx-default-setup' Command
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

3.3.1 `M-x', `M-!', `M-&' and `M-:' Support
-------------------------------------------

  - *Why these features*

    Usually you don't want to type Chinese when you use `M-x', `M-!'
    (`shell-command'), `M-&' (`async-shell-command') or `M-:'
    (`eval-expression').  You can automatically disable fcitx when
    you're using these commands.

  - *What does fcitx-default-setup do*

    It enables these features by calling the following commands:
    ,----
    | (fcitx-M-x-turn-on)
    | (fcitx-shell-command-turn-on)
    | (fcitx-eval-expression-turn-on)
    `----

    Your `M-x' binding should be one of `execute-extended-command' (the
    default `M-x' command), `smex' , `helm-M-x' and `counsel-M-x'.

    *WARNING*: If you rebind `M-x' to `smex', `helm-M-x', or
    `counsel-M-x', then you should call `fcitx-default-setup' or
    `fcitx-M-x-turn-on' *after* the key rebinding.

  - *How to customize it*

    You can enable some of the above three features by calling their
    corresponding `*-turn-on' commands, but remember if you rebind your
    `M-x', you should call `(fcitx-M-x-turn-on)' after the key
    rebinding.


3.4 Features Enabled *ONLY* in `fcitx-aggressive-setup' Command
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

3.4.1 Disable Fcitx in Minibuffer
---------------------------------

  - *Why this features*

    For me, I personally don't need to type Chinese in minibuffer, so I
    would like to temporarily disable fcitx in minibuffer, no matter in
    what kind of command.  If you are the same as me, then you could
    choose this setup.

  - *What does fcitx-aggressive-setup do*

    Unlike `fcitx-default-setup', it would not turn on `M-x', `M-!',
    `M-&' and `M-:' support.  Instead, it will call
    `fcitx-aggressive-minibuffer-turn-on' to temporarily disable fcitx
    in all commands that use minibuffer as a source of input, including,
    but not limited to, `M-x', `M-!', `M-&' and `M-:'.  That is why this
    is called "aggressive-setup".  For example, if you press C-x b to
    switch buffer, or press C-x C-f to find file, fcitx will be disabled
    when you are in the minibuffer so that you can type English letters
    directly.  However, if you choose `fcitx-default-setup', fcitx will
    not be disabled after you press C-x b or C-x C-f.  I prefer this
    more aggressive setup because I don't use Chinese in my filename or
    buffer name.


3.5 Extra Functions That are not Enabled in Both Commands
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

  These functions are not enabled in either `fcitx-default-setup' or
  `fcitx-aggressive-setup'.  You need to enable them manually if you
  want to use them.


3.5.1 I-search Support
----------------------

  Usually when you use fcitx, you also want to I-search in Chinese, so
  this feature is not enabled by eith `fcitx-default-setup' or
  `fcitx-aggressive-setup'.  If you do want to disable fcitx when using
  I-search, enable this feature explicitly by
  ,----
  | (fcitx-isearch-turn-on)
  `----


4 Using D-Bus Interface
=======================

  For Linux users, it is recommended that you set `fcitx-use-dbus' to be
  `t' to speed up a little (but pay attention to the lagging issue
  mentioned above):
  ,----
  | (setq fcitx-use-dbus t)
  `----

  For OSX users who use [fcitx-remote-for-osx], don't set this variable.


[fcitx-remote-for-osx]
https://github.com/CodeFalling/fcitx-remote-for-osx


5 Work with Other Input Methods
===============================

  Although this package is named `fcitx.el', it is not tightly coupled
  with `fcitx' itself.  `fcitx.el' makes use of the tool `fcitx-remote'
  (or the dbus interface in Linux) to do the following two things:
  1. Know the status of the current input method (active or inactive)
  2. Activate or deactivate the input method

  If you want to add support for other input methods, as long as it is
  possible to achieve the above two things from Emacs Lisp, then you get
  all the functionalities in `fcitx.el' for free.  That said, you just
  need to provide three functions:
  1. one that returns the status of the current input method
  2. one to activate the input method
  3. one to deactivate the input method

  So we can see that the functionalities provided in this package is
  very general, which can be easily adapted to used with other input
  methods.


6 TODO TODO
===========

  - Better Evil support

  For more features, pull requests are always welcome!
