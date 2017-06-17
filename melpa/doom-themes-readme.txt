DOOM Themes is an opinionated UI plugin and pack of themes extracted from my
[emacs.d], inspired by some of my favorite color themes including:

  [X] `doom-one': inspired by Atom's One Dark themes
  [-] `doom-one-light': light version of doom-one
  [X] `doom-vibrant': a more vibrant version of `doom-one`
  [X] `doom-molokai': based on Textmate's monokai
  [X] `doom-nova': adapted from Nova (thanks to bigardone)
  [ ] `doom-x': reads your colors from ~/.Xresources
  [-] `doom-tomorrow-night' / `doom-tomorrow-day': by Chris Kempson
  [ ] `doom-spacegrey': I'm sure you've heard of it
  [ ] `doom-mono-dark' / `doom-mono-light': a minimalistic, monochromatic theme
  [ ] `doom-tron': based on Tron Legacy from daylerees' themes
  [ ] `doom-peacock': based on Peacock from daylerees' themes

## Install

  `M-x package-install RET doom-themes`

A comprehensive configuration example:

  (require 'doom-themes)

  ;; Global settings (defaults)
  (setq doom-themes-enable-bold t    ; if nil, bold is universally disabled
        doom-themes-enable-italic t) ; if nil, italics is universally disabled

  ;; Load the theme (doom-one, doom-molokai, etc); keep in mind that each
  ;; theme may have their own settings.
  (load-theme 'doom-one t)

  ;; Enable flashing mode-line on errors
  (doom-themes-visual-bell-config)

  ;; Enable custom neotree theme
  (doom-themes-neotree-config)  ; all-the-icons fonts must be installed!
