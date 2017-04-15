Usage:
1. At first set autoload function in your .emacs like this:
   (autoload 'se/make-summary-buffer "summarye" nil t)
   (autoload 'soccur "summarye" nil t)
2. [Optional] bind se/make-summary-buffer to your favorite key
sequence(or menu)
   like the following:
   (define-key help-map "M" 'se/make-summary-buffer)
   NOTE: You can use summarye from menu (Tools->Make summary) or
   M-x se/make-summary-buffer
3. Invoke it. You will get the summary buffer of current buffer. You
   will use it easily, I think.
4. If you want to specify the item pattern, set the value to buffer-local
   variable se/item-delimiter-regexp like the following examples. The
   value must be either a regular expression string or a list of a list
   of a tag string and a regexp string. See examples.
5. And if you want to specify the displayed string in summary buffer,
   assign a function to buffer-local variable
   se/item-name-constructor-function.

Coding memo:
* While cluster is an internal structure which index starts from
  zero, item means objects user can view like a displayed line or
  the corresponding text. Thus every commands do not have cluster
  in their names.
* In this program, term `face' is used. But it means not face but overlay.
