This package is inspired by python howdoi (https://github.com/gleitz/howdoi)
and howdoi Emacs package (https://github.com/lockie/emacs-howdoi and
https://github.com/atykhonov/emacs-howdoi). it searches your query all
across stackoverflow and its sisters' sites. They are: stackoverflow.com,
stackexchange.com, superuser.com, serverfault.com and askubunu.com. The
result is then showed in an `org-mode' buffer. For each result, the question
and three answers were showed, but they are collapsed by default except the
first answer. As this package uses Google to get the links, for each query
there will be a dozen of links, the fist link will be used, but then use can
go to next link and previous link. The author believes that when searching
for solutions it is important for users to read both questions and answers,
so no "quick look" features such as code only view or code completion are
provided.

Dependencies
`promise' and `request' are required.
user must have `org-mode' 9.2 or later installed also.

Commands
howdoyou-query:                   prompt for query and do search
howdoyou-next-link:               go to next link
howdoyou-previous-link:           go to previous link
howdoyou-go-back-to-first-link:   go back to first link
howdoyou-reload-link:             reload link

Customization
howdoyou-use-curl:                default is true if curl is available
howdoyou-number-of-answers:       maximal number of answers to show, default is 3
howdoyou-switch-to-answer-buffer: switch to answer buffer if non nil, default is nil
