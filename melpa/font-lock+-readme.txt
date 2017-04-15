   Enhancements to standard library `font-lock.el'.

 This library tells font lock to ignore any text that has the text
 property `font-lock-ignore'.  This means, in particular, that font
 lock will not erase or otherwise interfere with highlighting that
 you apply using library `highlight.el'.

 Load this library after standard library `font-lock.el' (which
 should be preloaded).  Put this in your Emacs init file (~/.emacs):

   (require 'font-lock+)


 Non-interactive functions defined here:

   `put-text-property-unless-ignore'.


 ***** NOTE: The following functions defined in `font-lock.el'
             have been REDEFINED HERE:

   `font-lock-append-text-property', `font-lock-apply-highlight',
   `font-lock-apply-syntactic-highlight',
   `font-lock-default-unfontify-region',
   `font-lock-fillin-text-property',
   `font-lock-fontify-anchored-keywords',
   `font-lock-fontify-keywords-region',
   `font-lock-fontify-syntactically-region',
   `font-lock-prepend-text-property'.
