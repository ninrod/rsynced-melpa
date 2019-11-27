;;; org-shoplist.el --- Eat the world -*- lexical-binding: t -*-

;; Copyright (C) 2019 lordnik22

;; Author: lordnik22
;; Version: 1.0.0
;; Package-Version: 20190809.2156
;; Keywords: extensions matching
;; URL: https://github.com/lordnik22
;; Package-Requires: ((emacs "25"))

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.
;;; Commentary:
;; An extension to Emacs for operating on org-files who provide
;; food-recipes.  It's meant to generate shopping lists and make
;; eating-plans.  (We talk about delicious food — nothing technical).
;;; Code:
(require 'subr-x)
(require 'seq)
(require 'calc-ext)
(require 'calc-units)
(require 'org)
(require 'calendar)
(require 'cl-lib)

(defgroup org-shoplist nil
  "All customizable variables to generate your personal shoplist."
  :prefix "org-shoplist-"
  :group 'applications)

(defcustom org-shoplist-buffer-name "*Shopping List*"
  "Name of buffer when generating a shopping list."
  :type 'string)

(defcustom org-shoplist-keyword "TOBUY"
  "Keyword to mark recies for shopping."
  :type 'string)

(defcustom org-shoplist-factor-property-name "FACTOR"
  "The default name for the factor-property of headers."
  :type 'string)

(defcustom org-shoplist-table-header (list "Ingredient" "Amount")
  "Defines the header of the standard ingredient header."
  :type '(repeat string))

(defcustom org-shoplist-additional-units nil
  "Additional units that are needed for recipes with special units.
Beaware that the unit can't contain dots."
  :type '(repeat (list (symbol)
		       (string :tag "Definition")
		       (string :tag "Description"))))

(defcustom org-shoplist-explicit-keyword nil
  "When non-nil, only striclty include ingredients of marked headings.
Meaning: When for example a level-1-header is marked, the
ingredients defined in subheadings which aren’t marked don’t get
included in the shoplist."
  :type 'boolean)

(defcustom org-shoplist-aggregate t
  "When non-nil will aggregate the ingredient of the generated shoplist.
When nil won’t aggregate."
  :type 'boolean)

(defcustom org-shoplist-ing-invert nil
  "When non-nil, handle ingredient name first, amount second.
When nil, handle ingredient amount first, name second"
  :type 'boolean)

(defcustom org-shoplist-ing-start-char "("
  "Start char which introduces a ingredient."
  :type 'string)

(defcustom org-shoplist-ing-end-char ")"
  "End char which terminats a ingredient."
  :type 'string)

(defcustom org-shoplist-default-format #'org-shoplist-shoplist-as-table
  "Function name with one parameter which formats the shoplist."
  :type 'function)

(defcustom org-shoplist-ing-default-separator " "
  "Default separator for a ing parts."
  :type 'string)

(defcustom org-shoplist-auto-add-unit nil
  "When non-nil add unknown units to ‘ORG-SHOPLIST-ADDITIONAL-UNITS’.
Else throw an ‘user-error’."
  :type 'boolean)

(defconst org-shoplist--ing-first-part-regex
  '(format "\\([^%s%s]+?[^[:space:]%s%s]?\\)"
	   (regexp-quote org-shoplist-ing-start-char)
	   (regexp-quote org-shoplist-ing-end-char)
	   (regexp-quote org-shoplist-ing-start-char)
	   (regexp-quote org-shoplist-ing-end-char))
  "A regex which matches first part of ingredient the amount.")

(defconst org-shoplist--ing-second-part-regex
  '(format "\\([^[:space:]%s%s]?[^%s%s]+?\\)"
	   (regexp-quote org-shoplist-ing-start-char)
	   (regexp-quote org-shoplist-ing-end-char)
	   (regexp-quote org-shoplist-ing-start-char)
	   (regexp-quote org-shoplist-ing-end-char))
  "A regex which matches second part of the ingredient the name.")

(defconst org-shoplist--ing-content-spliter-regex "\\([[:space:]]+\\)"
  "A regex which matches whitespace which splits the date of ingredient.")

(defconst org-shoplist--ing-optional-content-spliter-regex "\\([[:space:]]*\\)"
  "A regex which matches whitespace which splits the date of ingredient.")

(defconst org-shoplist-ing-regex
  '(concat (regexp-quote org-shoplist-ing-start-char)
	   (eval org-shoplist--ing-first-part-regex)
	   (eval org-shoplist--ing-content-spliter-regex)
	   (eval org-shoplist--ing-second-part-regex)
	   (regexp-quote org-shoplist-ing-end-char))
  "Match an ingredient.")


(defun org-shoplist--calc-unit (amount)
  "Get the unit from AMOUNT by suppling it to calc.
AMOUNT is handled as a string.
When AMOUNT has no unit return nil."
  (let ((unit (calc-eval (math-extract-units (math-read-expr amount)))))
    (unless (string= "1" unit) unit)))

(defun org-shoplist--calc-default-unit (amount)
  "Find the ground unit of ‘AMOUNT’s unit.
When ‘AMOUNT’ nil, return nil"
  (calc-eval (math-extract-units (math-to-standard-units (math-read-expr amount) nil))))

(defun org-shoplist--calc-eval (str round-func &optional separator &rest args)
  "Calc-eval ‘STR’ and apply ‘ROUND-FUNC’ to the final result.
Optional ‘SEPARATOR’ and ‘ARGS’ are supplied to (calc-eval).
When ‘STR’ is nil or 0, return 0."
  (if (and str (not (string= str "0")))
      (let ((e-str (save-match-data (ignore-errors (eval (calc-eval str separator args))))))
	(when (or (null e-str) (string-match-p "[<>+*/-]" e-str)) (user-error "Invalid ‘AMOUNT’(%s) for ingredient" str))
	(when (string-match "\\(\\.\\)\\([^0-9]\\|$\\)" e-str) (setq e-str (replace-match "" t t e-str 1)))
	(if (string= "0" e-str)
	    (concat e-str (org-shoplist--calc-unit str))
	  (if (string-match-p "[^0-9]" (substring e-str 0 1))
	      (concat "1" e-str)
	    (let ((s-e-str (split-string e-str " ")))
	      (concat (number-to-string (funcall round-func (string-to-number (car s-e-str))))
		      (cadr s-e-str))))))
    "0"))

(defun org-shoplist--ing-transform-amount (amount &optional round-func)
  "Transform ‘AMOUNT’ to a valid form when possible else throw an error.
Optional ‘ROUND-FUNC’ is a function which is applied to the
result to round it.  Default is math-round."
  (let ((math-backup math-simplifying-units)
	(unit-backup math-additional-units)
	(str-amount (cond ((numberp amount) (number-to-string amount))
			  ((null amount) "0")
			  (amount))))
    (unwind-protect
	(progn
	  (setq math-simplifying-units t)
	  (setq math-additional-units org-shoplist-additional-units)
	  (let ((e-str-amount (org-shoplist--calc-eval str-amount (if (null round-func) 'math-round round-func))))
	    (if (and (not (string-match "[<>+*/-]" str-amount))
		     (string-match "[^.0-9<>+*/-]" str-amount)
		     (not (org-shoplist--calc-unit str-amount)))
		(if org-shoplist-auto-add-unit
		    (progn
		      (setq math-additional-units nil)
		      (add-to-list 'org-shoplist-additional-units (list (intern (match-string 0 e-str-amount)) nil "*Auto inserted unit by org-shoplist"))
		      (setq math-additional-units org-shoplist-additional-units)
		      (setq math-units-table nil)
		      (setq e-str-amount (org-shoplist--ing-transform-amount e-str-amount round-func)))
		  (user-error "Unit in ‘AMOUNT’(%s) unknown; Set org-shoplist-auto-add-unit to automatically add these units with a default definiton" amount)))
	    e-str-amount))
      (setq math-simplifying-units math-backup)
      (setq math-additional-units unit-backup))))

(defun org-shoplist-ing-name (ing)
  "Get name of ‘ING’."
  (car ing))

(defun org-shoplist-ing-amount (ing)
  "Get amount of ‘ING’."
  (cadr ing))

(defun org-shoplist-ing-unit (ing)
  "Get unit of ‘ING’."
  (let ((unit-backup math-additional-units))
    (unwind-protect
	(progn
	  (dolist (i org-shoplist-additional-units) (add-to-list 'math-additional-units i))
	  (org-shoplist--calc-unit (org-shoplist-ing-amount ing)))
      (setq math-additional-units unit-backup))))

(defun org-shoplist-ing-group (ing)
  "Get group of ‘ING’."
  (caddr ing))

(defun org-shoplist-ing-separator (ing)
  "Get separator of ‘ING’."
  (cadddr ing))

(defun org-shoplist-ing-create (amount name &optional separator)
  "Create an ingredient.
‘AMOUNT’ can be a string, a number or a valid sequence.
‘NAME’ is a string.
‘SEPARATOR’ a string by which ‘NAME’ and ‘AMOUNT’ is separated.
If one constraint gets disregarded throw error."
  (save-match-data
    (unless (stringp name) (user-error "Invalid ‘NAME’(%S) for ingredient" name))
    (let ((transform-amount (org-shoplist--ing-transform-amount amount)))
      (list name
	    transform-amount
	    (org-shoplist--calc-default-unit transform-amount)
	    (if (null separator) org-shoplist-ing-default-separator separator)))))

(defun org-shoplist-ing-content-string (ing)
  "Return ‘ING’ as follow: “amount name”.
When ORG-SHOPLIST-ING-INVERT is non-nil will return ”name amount”."
  (if org-shoplist-ing-invert
      (concat (org-shoplist-ing-name ing) (org-shoplist-ing-separator ing) (org-shoplist-ing-amount ing))
    (concat (org-shoplist-ing-amount ing) (org-shoplist-ing-separator ing) (org-shoplist-ing-name ing))))

(defun org-shoplist-ing-full-string (ing)
  "Return ‘ING’ as follow: “(amount name)”.
When ORG-SHOPLIST-ING-INVERT is non-nil will return ”(name amount)”."
  (if org-shoplist-ing-invert
      (concat org-shoplist-ing-start-char (org-shoplist-ing-name ing) (org-shoplist-ing-separator ing) (org-shoplist-ing-amount ing) org-shoplist-ing-end-char)
    (concat org-shoplist-ing-start-char (org-shoplist-ing-amount ing) (org-shoplist-ing-separator ing) (org-shoplist-ing-name ing) org-shoplist-ing-end-char)))

(defun org-shoplist-ing-+ (&rest amounts)
  "Add ‘AMOUNTS’ toghether return the sum."
  (let ((sum-amount
	 (mapconcat
	  (lambda (x)
	    (cond ((stringp x) x)
		  ((integerp x) (number-to-string x))
		  ((null x) "0")
		  ((listp x) (org-shoplist-ing-amount x))
		  (t (user-error "Given ‘AMOUNT’(%S) can’t be converted" x))))
	  amounts "+")))
    (let ((t-sum-amount (ignore-errors (org-shoplist--ing-transform-amount sum-amount))))
      (unless t-sum-amount (user-error "Incompatible units while aggregating(%S)" amounts))
      t-sum-amount)))

(defun org-shoplist-ing-* (ing factor &optional round-func)
  "Multiply the amount of ‘ING’ with given ‘FACTOR’.
Return new ingredient with modified amount.  When ‘ROUND-FUNC’
given round resulting amount with it."
  (org-shoplist-ing-create
   (org-shoplist--ing-transform-amount (concat (number-to-string factor) "*" (org-shoplist-ing-amount ing)) round-func)
   (org-shoplist-ing-name ing)
   (org-shoplist-ing-separator ing)))

(defun org-shoplist-ing-aggregate (&rest ings)
  "Aggregate ‘INGS’."
  (let ((group-ings (seq-group-by
		     (lambda (x) (list (org-shoplist-ing-name x) (org-shoplist-ing-group x)))
		     ings))
	(aggregate-ings (list)))
    (while (car group-ings)
      (setq aggregate-ings
	    (cons (org-shoplist-ing-create
		   (apply #'org-shoplist-ing-+ (cdar group-ings))
		   (org-shoplist-ing-name (caar group-ings))
		   (org-shoplist-ing-separator (caar group-ings)))
		  aggregate-ings))
      (setq group-ings (cdr group-ings)))
    aggregate-ings))

(defun org-shoplist--ing-read-loop (str start-pos ings)
  "Helper functions for (org-shoplist-read) which does the recursive matching.
‘STR’ is a string where regex is getting matched against.
‘START-POS’ is where in string should start.
‘INGS’ is a list of the found ingredients."
  (if (string-match (eval org-shoplist-ing-regex) str start-pos)
      (org-shoplist--ing-read-loop
       str
       (match-end 0)
       (if org-shoplist-ing-invert
	   (cons (org-shoplist-ing-create
		  (match-string 3 str)
		  (match-string 1 str)
		  (match-string 2 str))
		 ings)
	 (cons (org-shoplist-ing-create
		(match-string 1 str)
		(match-string 3 str)
		(match-string 2 str))
	       ings)))

    ings))

(defun org-shoplist--ing-concat-when-broken (str last-pos)
  "Concat broken ing when it’s splitted into two by newline.
STR which maybe broken
LAST-POS position of last match"
  (when (string-match (concat (regexp-quote org-shoplist-ing-start-char) (eval org-shoplist--ing-first-part-regex) (eval org-shoplist--ing-content-spliter-regex) "$")
		      str
		      last-pos)
    (let ((ing-start (match-string 0 str))
	  (nl (save-excursion (beginning-of-line 2) (thing-at-point 'line))))
      (when (string-match (concat "^" (eval org-shoplist--ing-optional-content-spliter-regex) (eval org-shoplist--ing-second-part-regex) (regexp-quote org-shoplist-ing-end-char))
			  nl)
	(concat ing-start (match-string 0 nl))))))

(defun org-shoplist-ing-read (&optional aggregate str)
  "‘AGGREGATE’ output when non-nil else return parsed ‘STR’ raw.
Whenn ‘STR’ is nil read line where point is at."
  (unless str (setq str (thing-at-point 'line)))
  (unless (or (null str) (string= str ""))
    (let ((read-ings (org-shoplist--ing-read-loop str 0 '())))
      (when-let ((breaked-ing (org-shoplist--ing-concat-when-broken str (if (null read-ings) 0 (match-end 0)))))
	(setq read-ings (org-shoplist--ing-read-loop breaked-ing 0 read-ings)))
      (if aggregate
	  (apply #'org-shoplist-ing-aggregate read-ings)
	(reverse read-ings)))))

(defun org-shoplist-recipe-create (name &rest ings)
  "Create a recipe.
‘NAME’ must be a string.
‘INGS’ must be valid ingredients.
Use ‘org-shoplist-ing-create’ to create valid ingredients."
  (when (and (stringp name) (string= name "")) (user-error "Invalid name for recipe: ‘%s’" name))
  (when (listp (caar ings)) (setq ings (car ings)))
  (when (and name ings (not (equal ings '(nil))))
    (list name ings)))

(defun org-shoplist-recipe-name (recipe)
  "Get name of ‘RECIPE’."
  (car recipe))

(defun org-shoplist-recipe-get-all-ing (recipe)
  "Get all ingredients of ‘RECIPE’."
  (cadr recipe))

(defun org-shoplist-recipe-* (recipe factor &optional round-func)
  "Multiply all ingredients of ‘RECIPE’ by given ‘FACTOR’.
When ROUND-FUNC given round resulting amounts with it."
  (if (null factor)
      recipe
    (let (f-ing-list)
      (dolist (i (org-shoplist-recipe-get-all-ing recipe) f-ing-list)
	(push (org-shoplist-ing-* i factor round-func) f-ing-list))
      (org-shoplist-recipe-create (org-shoplist-recipe-name recipe) (reverse f-ing-list)))))

(defun org-shoplist--recipe-read-factor ()
  "Read the value of ‘ORG-SHOPLIST-FACTOR-PROPERTY-NAME’ in recipe where point is at."
  (unless (ignore-errors (org-back-to-heading t)) (user-error "Not in recipe"))
  (ignore-errors (string-to-number (org-entry-get (point) org-shoplist-factor-property-name))))

(defun org-shoplist--recipe-read-all-ings (&optional explicit-match)
    "Collect all ingredients of current recipe.
‘EXPLICIT-MATCH’ when is non-nil only marked sub-headings will be included."
    (save-match-data
      (let ((ing-list nil)
	    (h (org-get-heading)) ;current header
	    (l (org-current-level)))
	(beginning-of-line 2)
	(while (and (or (string= h (org-get-heading))
			(> (org-current-level) l))
		    (not (>= (point) (point-max))))
	  (if explicit-match
	      (if (string= (org-get-todo-state) org-shoplist-keyword)
		  (setq ing-list (append ing-list (org-shoplist-ing-read))))
	    (setq ing-list (append ing-list (org-shoplist-ing-read))))
	  (beginning-of-line 2))
	ing-list)))

(defun org-shoplist-recipe-read (&optional aggregate explicit-match)
  "Assums that at beginning of recipe.
Which is at (beginning-of-line) at heading (╹* Nut Salat...).
Return a recipe structure or throw error.  To read a recipe there
must be at least a org-heading (name of the recipe) and one
ingredient.
‘AGGREGATE’ ingredients when non-nil.
‘EXPLICIT-MATCH’ when is non-nil only marked sub-headings will be included.
See ‘org-shoplist-recipe-create’ for more details on creating general
recipes."
  (save-match-data
    (unless (looking-at org-heading-regexp) (user-error "Not at beginning of recipe"))
    (let ((read-ings (org-shoplist--recipe-read-all-ings explicit-match)))
      (org-shoplist-recipe-create
       (string-trim (replace-regexp-in-string org-todo-regexp "" (match-string 2)))
       (if aggregate (apply #'org-shoplist-ing-aggregate read-ings) read-ings)))))

(defun org-shoplist-shoplist-create (&rest recipes)
  "Create a shoplist.
‘RECIPES’ is a sequence of recipes."
  (when (and recipes (car recipes))
    (list (calendar-current-date)
	  recipes
	  (reverse (apply #'org-shoplist-ing-aggregate
			  (apply #'append
				 (mapcar #'org-shoplist-recipe-get-all-ing recipes)))))))

(defun org-shoplist-shoplist-creation-date (shoplist)
  "Get shopdate of shoplist.
‘SHOPLIST’ of which the date should be extracted."
  (car shoplist))

(defun org-shoplist-shoplist-recipes (shoplist)
  "Get recipes of shoplist.
‘SHOPLIST’ a."
  (cadr shoplist))

(defun org-shoplist-shoplist-ings (shoplist)
  "Get recipes of shoplist.
‘SHOPLIST’ a."
  (caddr shoplist))

(defun org-shoplist-shoplist-read (&optional aggregate explicit-match)
  "Return a shoplist structure or throw error.
To read a recipe there must be at least a org-heading (name of the recipe).
See ‘org-shoplist-recipe-create’ for more details on creating general recipes.
‘AGGREGATE’ ingredients when non-nil.
‘EXPLICIT-MATCH’ when is non-nil only marked headings will be included."
  (let ((recipe-list
	 (save-match-data
	   (let ((recipe-list nil))
	     (while (and (not (= (point-max) (point)))
			 (search-forward-regexp org-heading-regexp nil t 1))
	       (when (save-excursion (beginning-of-line 1) (looking-at-p (concat ".+" org-shoplist-keyword)))
		 (beginning-of-line 1)
		 (if (null recipe-list)
		     (setq recipe-list (list (org-shoplist-recipe-read aggregate explicit-match)))
		   (push (org-shoplist-recipe-read aggregate explicit-match) recipe-list))))
	     recipe-list))))
    (apply #'org-shoplist-shoplist-create (reverse recipe-list))))

(defun org-shoplist-shoplist-as-table (shoplist)
  "Format ‘SHOPLIST’ as table."
  (concat "|" (mapconcat 'identity org-shoplist-table-header "|")
	  "|\n"
	  (mapconcat (lambda (i) (concat "|" (org-shoplist-ing-name i) "|" (org-shoplist-ing-amount i)))
		     (org-shoplist-shoplist-ings shoplist)
		     "|\n")
	  "|\n"))

(defun org-shoplist-shoplist-as-todo-list (shoplist)
  "Format ‘SHOPLIST’ as todo-list."
  (concat
   (concat "#+SEQ_TODO:\s" org-shoplist-keyword "\s|\sBOUGHT\n")
   (mapconcat (lambda (i) (concat "*\s" org-shoplist-keyword "\s" (org-shoplist-ing-content-string i)))
	      (org-shoplist-shoplist-ings shoplist)
	      "\n")))

(defun org-shoplist-shoplist-insert (as-format)
  "Insert a shoplist with given format(‘AS-FORMAT’)."
  (save-excursion
    (funcall #'org-mode)
    (insert as-format)
    (goto-char (point-min))
    (when (org-at-table-p) (org-table-align))))

(defun org-shoplist (&optional arg)
  "Generate a shoplist from current buffer.
With a non-default prefix argument ARG, prompt the user for a
formatter; otherwise, just use `org-shoplist-default-format'."
  (interactive "p")
  (let ((formatter
	 (if (= arg 1)
	     org-shoplist-default-format
	   (intern (completing-read "Formatter-Name: " obarray 'functionp t nil nil "org-shoplist-default-format"))))
        (sl
	 (save-excursion
	   (goto-char (point-min))
	   (org-shoplist-shoplist-read org-shoplist-aggregate org-shoplist-explicit-keyword))))
    (with-current-buffer (switch-to-buffer org-shoplist-buffer-name)
      (when (>= (buffer-size) 0) (erase-buffer))
      (org-shoplist-shoplist-insert (funcall formatter sl)))))

(defun org-shoplist-init ()
  "Setting the todo-keywords for current file."
  (interactive)
  (save-excursion
    (goto-char (point-min))
    (unless (looking-at-p "#\\+SEQ_TODO:") )
    (funcall #'org-mode)))

(defun org-shoplist-unmark-all ()
  "Unmark all recipes which are marked with ‘org-shoplist-keyword’."
  (interactive)
  (save-excursion
    (goto-char (point-min))
    (beginning-of-line 2)
    (while (re-search-forward (concat " " org-shoplist-keyword) nil t)
      (replace-match "" nil nil))))

(defun org-shoplist-recipe-set-factor (new-factor &optional inclusivness)
  "Set ‘NEW-FACTOR’ as value of the factor-property of current header.
If already set, adjust ingredients accordingly else
set value as inital value.
‘INCLUSIVNESS’ defines how to handle nested headers."
  (interactive "NValue: " )
  (let ((old-factor (org-shoplist--recipe-read-factor)))
    (unless new-factor (user-error "No inital value for %s defined" org-shoplist-factor-property-name))
    (when (< new-factor 1) (user-error "Can’t decrement under 1"))
    (when old-factor
      (let* ((current-recipe (save-excursion (org-shoplist-recipe-read nil inclusivness)))
	     (new-recipe (org-shoplist-recipe-*
			  current-recipe
			  (ignore-errors (/ (float new-factor) old-factor))
			  (if (< new-factor old-factor) 'ffloor 'fceiling ))))

	(unless new-recipe (user-error "No ingredients to apply factor"))
	;; replace current with new
	(save-excursion
	  (cl-mapc
	   (lambda (new old)
	     (search-forward (org-shoplist-ing-full-string old) nil t 1)
	     (replace-match (org-shoplist-ing-full-string new) t))
	   (org-shoplist-recipe-get-all-ing new-recipe)
	   (org-shoplist-recipe-get-all-ing current-recipe)))))
    (org-set-property org-shoplist-factor-property-name (number-to-string new-factor))))

(defun org-shoplist-recipe-factor-down (&optional arg)
  "Decrement the factor-property of current header.
With a non-default prefix argument ARG, apply
‘org-shoplist-explicit-keyword’ to recipe-scan.  Meaning when
‘org-shoplist-explicit-keyword’ is t, only factor down the
ingredients of (nested) recipes which are marked."
  (interactive "p")
  (save-excursion (org-shoplist-recipe-set-factor (ignore-errors (1- (org-shoplist--recipe-read-factor)))
				      (org-shoplist--when-arg-return-keyword-else-nil arg))))

(defun org-shoplist-recipe-factor-up (&optional arg)
  "Increment the factor-property of current header.
With a non-default prefix argument ARG, apply
‘org-shoplist-explicit-keyword’ to recipe-scan.  Meaning when
‘org-shoplist-explicit-keyword’ is t, only factor up the
ingredients of (nested) recipes which are marked."
  (interactive "p")
  (save-excursion (org-shoplist-recipe-set-factor (ignore-errors (1+ (org-shoplist--recipe-read-factor)))
				      (org-shoplist--when-arg-return-keyword-else-nil arg))))

(defun org-shoplist--when-arg-return-keyword-else-nil (arg)
  "When ARG equals 1 return nil else ‘org-shoplist-explicit-keyword’."
  (when (and arg (= arg 1)) org-shoplist-explicit-keyword))

(defun org-shoplist-overview ()
  "An overview of the current recipes you added."
  (interactive)
  (org-search-view t org-shoplist-keyword))

(provide 'org-shoplist)
;;; org-shoplist.el ends here
