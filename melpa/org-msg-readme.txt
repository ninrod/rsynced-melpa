OrgMsg is a GNU/Emacs global minor mode mixing up Org mode and your
Mail User Agent Mode to compose and reply to emails in a HTML
friendly style.

* Presentation

By default, if the original message is in text form OrgMsg keeps it
that way and does not activate itself.  It allows to reply to
developer mailing list seamlessly.  If the original message is in
the HTML form, it activates the OrgMsg mode on the reply buffer.

OrgMsg provides a `org-msg-edit-mode' which is an derivation of Org
mode in which some functionality of your Mail User Agent are
imported or replicated.  For instance, a OrgMsg buffer uses the
same `font-lock-keywords' than Message mode or the `TAB' key while
the cursor is in the header calls the `message-tab' function.

For convenience, the original message is quoted below the
`--citation follows this line (read-only)--' marker.  So you can
easily refer to the original message.  However, the entire quoted
text is read-only because OrgMsg does not support modification of
the original content.

OrgMsg has a mechanism to support different Mail User Agents
(message, mu4e, ...).  Each function which depends on the Mail User
Agent calls the `org-msg-mua-call' which is an indirection to the
OrgMsg Mail User Agent specific function.

* Keys and interactive functions

The OrgMsg mode keys are the usual key combination used in either
Org mode or Message mode.
- C-c C-e - calls `org-msg-preview', it generates the final HTML
  email, save it into a temporary file and call the `browse-url'
  function on that file.
- C-c C-k - calls `message-kill-buffer'
- C-c C-s - calls `message-goto-subject' (same as in Message
  mode)
- C-c C-b - calls `org-msg-goto-body' (similar to
  `message-goto-body' in Message mode)
- C-c C-a - calls `org-msg-attach', very similar to the
  `org-attach' function.  It lets you add or delete attachment for
  this email.  Attachment list is stored in the `:attachment:'
  property.
- C-c C-c - calls `org-ctrl-c-ctrl-c'.  OrgMsg configures
  `org-msg-ctrl-c-ctrl-c' as a final hook of Org mode.  When
  `org-msg-ctrl-c-ctrl-c' is called in a OrgMsg buffer it
  generates the MIME message and send it.

The `org-msg-mode' interactive function can be called to
enable/disable OrgMsg.  By default, once the module is loaded, it
is disabled.  If you want to reply to an email without making use
of OrgMsg, you should call that function before you call the
reply-to function.

To start composing a new OrgMsg email, you can call the interactive
`message-mail' function.  If your `mail-user-agent' is
`message-user-agent' (which is the by default Emacs configuration),
`compose-mail' calls `message-mail' and is bound to [C-x m] by
default.

* Configuration

The following is my configuration as an Example

(require 'org-msg)
(setq org-msg-options "html-postamble:nil H:5 num:nil ^:{} toc:nil")
(setq org-msg-startup "hidestars indent inlineimages")
(setq org-msg-greeting-fmt "\nHi %s,\n\n")
(setq org-msg-greeting-fmt-mailto t)
(setq org-msg-signature "

Regards,

#+begin_signature
-- *Jeremy* \\\\
/One Emacs to rule them all/
#+end_signature")
(org-msg-mode)

The `org-msg-greeting-fmt' can be customized to configure the
default greeting message.  If this format contains a `%s' token it
is automatically replaced with the first name of the person you are
replying to.  If `org-msg-greeting-fmt-mailto' is t, the first name
it is formatted as mailto link.

In order to avoid CSS conflict, OrgMsg performs inline replacement
when it generates the final HTML message.  See the
`org-msg-enforce-css' variable to customize the style (and the
default `org-msg-default-style' variable for reference).
