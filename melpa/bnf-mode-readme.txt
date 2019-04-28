  GNU Emacs major mode for editing BNF grammars.  Currently this mode
provides basic syntax and font-locking for BNF files.  BNF notation is
supported exactly form as it was first announced in the ALGOL 60 report.

When developing this mode, the following documents were taken into account:

- RFC822: Standard for ARPA Internet Text Messages
  (see URL `https://www.ietf.org/rfc/rfc822.txt')
- RFC5234: Augmented BNF for Syntax Specifications: ABNF
  (see URL `https://www.ietf.org/rfc/rfc5234.txt')
- FRC7405: Case-Sensitive String Support in ABNF
  (see URL `https://www.ietf.org/rfc/rfc7405.txt')
- Revised Report on the Algorithmic Language Algol 60
  (see URL `https://www.masswerk.at/algol60/report.htm')

Usage:  Put this file in your Emacs Lisp path (eg. site-lisp) and add to
your .emacs file:

  (require 'bnf-mode)

Bugs: Bug tracking is currently handled using the GitHub issue tracker
(see URL `https://github.com/sergeyklay/bnf-mode/issues')

History: History is tracked in the Git repository rather than in this file.
See URL `https://github.com/sergeyklay/bnf-mode/blob/master/CHANGELOG.org'
