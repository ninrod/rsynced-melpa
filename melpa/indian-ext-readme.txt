This package provides extensions to the standard Emacs ind-util.el
functions.

It is currently focused on providing methods for Sanskrit, but that
might (and hopefully will) change in the future.

It defines the following extra decode/encode functions:


between Velthuis and Devanāgarī:
`indian-ext-dev-velthuis-encode-region'
`indian-ext-dev-velthuis-decode-region'
between SLP1 and Devanāgarī:
`indian-ext-dev-slp1-encode-region'
`indian-ext-dev-slp1-decode-region'
between IAST and Devanāgarī.
`indian-ext-dev-iast-encode-region'
`indian-ext-dev-iast-decode-region'

IAST and Velthuis encodings are not case sensitive.

This package also defines an additional input method, sanskrit-iast
(use with `M-x set-input-method').

You can find other input methods here:

including Karoṣṭhī: http://stefanbaums.com/unicode/sanskrit.el
requires login: http://indica-et-buddhica.org/repositorium/software/emacs-utf8-input-framework
