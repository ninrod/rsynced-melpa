;;; hack-mode.el --- Major mode for the Hack programming language -*- lexical-binding: t -*-

;; Copyright (c) Facebook, Inc. and its affiliates. All Rights Reserved.

;; This program is free software: you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <https://www.gnu.org/licenses/>.

;; Author: John Allen <jallen@fb.com>, Wilfred Hughes <me@wilfred.me.uk>
;; Version: 1.0.0
;; Package-Version: 20190426.1617
;; Package-Requires: ((emacs "25.1") (s "1.11.0"))
;; URL: https://github.com/hhvm/hack-mode

;;; Commentary:
;;
;; Implements `hack-mode' for the Hack programming language.  This
;; includes basic support for highlighting and indentation.
;;

;;; Code:
(require 's)

(defgroup hack nil
  "Major mode `hack-mode' for editing Hack code."
  :prefix "hack-"
  :group 'languages)

(defcustom hack-client-program-name "hh_client"
  "The command to run to communicate with hh_server."
  :type 'string
  :group 'hack-mode)

(defcustom hack-format-on-save nil
  "Format the current buffer on save."
  :type 'boolean
  :safe #'booleanp
  :group 'hack-mode)

(defcustom hack-hackfmt-name "hackfmt"
  "The command to run to format code."
  :type 'string
  :group 'hack-mode)

(defcustom hack-indent-offset 2
  "Indentation amount (in spaces) for Hack code."
  :safe #'integerp
  :type 'integer
  :group 'hack-mode)

(defface hack-xhp-tag
  '((t . (:inherit font-lock-function-name-face)))
  "Face used to highlight XHP tags in `hack-mode' buffers."
  :group 'hack-mode)

(defun hack--propertize-xhp ()
  "Syntax highlight XHP blocks."
  (let ((start-pos (match-beginning 1)))
    (hack--forward-parse-xhp start-pos nil)
    ;; Point is now at the end of the XHP section.
    (let ((end-pos (point)))
      (goto-char start-pos)
      ;; Ensure that ' is not treated as a string delimiter, unless
      ;; we're in an XHP interpolated region.
      (while (search-forward "'" end-pos t)
        (let* ((ppss (syntax-ppss))
               (paren-pos (nth 1 ppss)))
          (when (or (null paren-pos)
                    (> start-pos paren-pos))
            (put-text-property (1- (point)) (point)
                               'syntax-table
                               (string-to-syntax ".")))))
      ;; We need to leave point after where we started, or we get an
      ;; infinite loop.
      (goto-char end-pos))))

(defun hack--propertize-heredoc ()
  "Put `syntax-table' text properties on heredoc and nowdoc string literals.

See <http://php.net/manual/en/language.types.string.php>."
  ;; Point starts just after the <<<, so the start position is three
  ;; chars back.
  (let ((start-pos (match-beginning 0))
        (identifier (match-string 1)))
    ;; Nowdoc literals have the form
    ;; $x <<<'FOO'
    ;; bar
    ;; FOO; // unquoted at end.
    (setq identifier
          (s-chop-suffix "'" (s-chop-prefix "'" identifier)))
    ;; The closing identifier must be at the beginning of a line.
    (search-forward (format "\n%s" identifier) nil t)

    ;; Mark the beginning < as a string beginning, so we don't think
    ;; any ' or " inside the heredoc are string delimiters.
    (put-text-property start-pos (1+ start-pos)
                       'syntax-table
                       (string-to-syntax "|"))
    (put-text-property (1- (point)) (point)
                       'syntax-table
                       (string-to-syntax "|"))))

(eval-when-compile
  ;; https://www.php.net/manual/en/language.types.string.php#language.types.string.syntax.heredoc
  (defconst hack--heredoc-regex
    (rx
     "<<<"
     (group
      (or
       (+ (or (syntax word) (syntax symbol)))
       ;; https://www.php.net/manual/en/language.types.string.php#language.types.string.syntax.nowdoc
       (seq "'" (+ (or (syntax word) (syntax symbol))) "'")))
     "\n"))

  (defconst hack--header-regex
    ;; <?hh can only occur on the first line. The only thing it may be preceded
    ;; by is a shebang. It's compulsory, except in .hack files. See hphp.ll.
    (rx
     (or
      buffer-start
      (seq "#!" (* not-newline) "\n"))
     (group "<?hh")
     ;; Match // strict if it's present.
     ;; See full_fidelity_parser.ml which calls FileInfo.parse_mode.
     (? (0+ space)
	"//"
	(0+ space)
	(group (or "strict" "partial" "experimental"))
	(or space "\n"))))

  ;; TODO: Check against next_xhp_element_token in full_fidelity_lexer.ml
  (defconst hack-xhp-start-regex
    (rx (or
         (seq symbol-start "return" symbol-end)
         bol
         "==>"
         "?"
         "="
         "(")
        (* space)
        (group "<" (not (any ?< ?\\ ??))))
    "The regex used to match the start of an XHP expression."))

(defun hack-font-lock-xhp (limit)
  "Search up to LIMIT for an XHP expression.
If we find one, move point to its end, and set match data."
  (let ((start-pos nil)
        (end-pos nil))
    (save-excursion
      (while (and (not end-pos)
                  (re-search-forward hack-xhp-start-regex limit t)
                  ;; Ignore XHP in comments.
                  (not (nth 4 (syntax-ppss))))
        (setq start-pos (match-beginning 1))
        (hack--forward-parse-xhp start-pos limit t)
        (setq end-pos (point))))
    (when end-pos
      (set-match-data (list start-pos end-pos))
      (goto-char end-pos))))

(defun hack--propertize-lt ()
  "Ensure < is not treated a < delimiter in other syntactic contexts."
  (let ((start (1- (point))))
    (when (or (looking-at "?hh")
              ;; Ignore left shift operators 1 << 2.
              (looking-at "< ")
              ;; If there's a following space, assume it's 1 < 2.
              (looking-at " "))
      (put-text-property start (1+ start)
		         'syntax-table (string-to-syntax ".")))))

(defun hack--propertize-gt ()
  "Ensure > in -> or => isn't treated as a > delimiter."
  (let* ((start (1- (point))))
    (when (> start (point-min))
      (let ((prev-char (char-before start))
	    (prev-prev-char (char-before (1- start)))
            (next-char (char-after (1+ start)))
	    (next-next-char (char-after (+ start 2))))
        ;; If there's a preceding space, we assume it's 1 > 2 rather than
        ;; a type vec < int > with excess space.
        (when (or (memq prev-char (list ?= ?- ?\ ))
                  ;; Also ignore 1 >> 2, first char.
                  (and (eq prev-char ?\ ) (eq next-char ?>) (eq next-next-char ?\ ))
		  ;; Ignore 1 >> 2, second car.
                  (and (eq prev-prev-char ?\ ) (eq prev-char ?>) (eq next-char ?\ )))
          (put-text-property start (1+ start)
		             'syntax-table (string-to-syntax ".")))))))

(defconst hack--syntax-propertize-function
  (syntax-propertize-rules
   ;; Heredocs, e.g.
   ;; $x = <<<EOT
   ;; foo bar
   ;; EOT;
   (hack--heredoc-regex
    (0 (ignore (hack--propertize-heredoc))))
   (hack-xhp-start-regex
    (0 (ignore (hack--propertize-xhp))))
   ("<"
    (0 (ignore (hack--propertize-lt))))
   (">"
    (0 (ignore (hack--propertize-gt))))))

(defun hack-font-lock-fallthrough (limit)
  "Search for FALLTHROUGH comments."
  (let ((case-fold-search nil)
	(found-pos nil)
	(match-data nil))
    ;; FALLTHROUGH must start with //, and can have any text afterwards. See
    ;; full_fidelity_lexer.ml.
    (save-excursion
      (while (and (not found-pos)
		  (search-forward "FALLTHROUGH" limit t))
	(let* ((ppss (syntax-ppss))
	       (in-comment (nth 4 ppss))
	       (comment-start (nth 8 ppss)))
	  (when in-comment
	    (save-excursion
	      (goto-char comment-start)
	      (when (re-search-forward
		     (rx point "//" (0+ whitespace) (group "FALLTHROUGH"))
		     limit t)
		(setq found-pos (point))
		(setq match-data (match-data))))))))
    (when found-pos
      (set-match-data match-data)
      (goto-char found-pos))))

(defun hack-font-lock-unsafe (limit)
  "Search for UNSAFE comments."
  (let ((case-fold-search nil)
	(found-pos nil)
	(match-data nil))
    ;; UNSAFE must start with //, and can have any text afterwards. See
    ;; full_fidelity_lexer.ml.
    (save-excursion
      (while (and (not found-pos)
		  (search-forward "UNSAFE" limit t))
	(let* ((ppss (syntax-ppss))
	       (in-comment (nth 4 ppss))
	       (comment-start (nth 8 ppss)))
	  (when in-comment
	    (save-excursion
	      (goto-char comment-start)
	      (when (re-search-forward
		     (rx point "//" (0+ whitespace) (group "UNSAFE"))
		     limit t)
		(setq found-pos (point))
		(setq match-data (match-data))))))))
    (when found-pos
      (set-match-data match-data)
      (goto-char found-pos))))

(defun hack-font-lock-unsafe-expr (limit)
  "Search for UNSAFE_EXPR comments."
  (let ((case-fold-search nil)
	(found-pos nil)
	(match-data nil))
    ;; UNSAFE_EXPR must start with /*, and can have any text afterwards. See
    ;; full_fidelity_lexer.ml.
    (save-excursion
      (while (and (not found-pos)
		  (search-forward "UNSAFE_EXPR" limit t))
	(let* ((ppss (syntax-ppss))
	       (in-comment (nth 4 ppss))
	       (comment-start (nth 8 ppss)))
	  (when in-comment
	    (save-excursion
	      (goto-char comment-start)
	      (when (re-search-forward
		     (rx point "/*" (0+ whitespace) (group "UNSAFE_EXPR"))
		     limit t)
		(setq found-pos (point))
		(setq match-data (match-data))))))))
    (when found-pos
      (set-match-data match-data)
      (goto-char found-pos))))

(defun hack-font-lock-fixme (limit)
  "Search for HH_FIXME comments."
  (let ((case-fold-search nil)
	(found-pos nil)
	(match-data nil))
    ;; HH_FIXME must start with /*, see full_fidelity_lexer.ml. The
    ;; format is matched by scour_comments in full_fidelity_ast.ml,
    ;; using, the ignore_error regex defined in that file.
    (save-excursion
      (while (and (not found-pos)
		  (search-forward "HH_FIXME" limit t))
	(let* ((ppss (syntax-ppss))
	       (in-comment (nth 4 ppss))
	       (comment-start (nth 8 ppss)))
	  (when in-comment
	    (save-excursion
	      (goto-char comment-start)
	      (when (re-search-forward
		     (rx point "/*" (0+ whitespace)
			 (group "HH_FIXME" (0+ whitespace) "[" (+ digit) "]"))
		     limit t)
		(setq found-pos (point))
		(setq match-data (match-data))))))))
    (when found-pos
      (set-match-data match-data)
      (goto-char found-pos))))

(defun hack-font-lock-ignore-error (limit)
  "Search for HH_IGNORE_ERROR comments."
  (let ((case-fold-search nil)
	(found-pos nil)
	(match-data nil))
    ;; HH_IGNORE_ERROR must start with /*, see full_fidelity_lexer.ml. The
    ;; format is matched by scour_comments in full_fidelity_ast.ml,
    ;; using, the ignore_error regex defined in that file.
    (save-excursion
      (while (and (not found-pos)
		  (search-forward "HH_IGNORE_ERROR" limit t))
	(let* ((ppss (syntax-ppss))
	       (in-comment (nth 4 ppss))
	       (comment-start (nth 8 ppss)))
	  (when in-comment
	    (save-excursion
	      (goto-char comment-start)
	      (when (re-search-forward
		     (rx point "/*" (0+ whitespace)
			 (group "HH_IGNORE_ERROR" (0+ whitespace) "[" (+ digit) "]"))
		     limit t)
		(setq found-pos (point))
		(setq match-data (match-data))))))))
    (when found-pos
      (set-match-data match-data)
      (goto-char found-pos))))

(defun hack-font-lock-interpolate (limit)
  "Search for $foo string interpolation."
  (let ((pattern
         (rx (not (any "\\"))
             (group
              (or
               (seq
                ;; $foo
                "$" (+ (or (syntax word) (syntax symbol))) symbol-end
                (0+ (or
                     ;; $foo->bar
                     (seq "->" (+ (or (syntax word) (syntax symbol))) symbol-end)
                     ;; $foo[123]
                     (seq "[" (+ (or (syntax word) (syntax symbol))) symbol-end "]"))))
               ;; ${foo}
               (seq "${" (+ (or (syntax word) (syntax symbol))) symbol-end "}")))))
        res match-data)
    (save-match-data
      ;; Search forward for $foo and terminate on the first
      ;; instance we find that's inside a sring.
      (while (and
              (not res)
              (re-search-forward pattern limit t))
        (let* ((ppss (syntax-ppss))
               (in-string-p (nth 3 ppss))
               (string-delimiter-pos (nth 8 ppss))
               (string-delimiter
                (when in-string-p (char-after string-delimiter-pos)))
               (interpolation-p in-string-p))
          (cond
           ;; Interpolation does not apply in single-quoted strings.
           ((eq string-delimiter ?')
            (setq interpolation-p nil))
           ;; We can interpolate in <<<FOO, but not in <<<'FOO'
           ((eq string-delimiter ?<)
            (save-excursion
              (goto-char string-delimiter-pos)
              (save-match-data
                (re-search-forward (rx (+ "<")))
                (when (looking-at (rx "'"))
                  (setq interpolation-p nil))))))

          (when interpolation-p
            (setq res (point))
            ;; Set match data to the group we matched.
            (setq match-data (list (match-beginning 1) (match-end 1)))))))
    ;; Set match data and return point so we highlight this
    ;; instance.
    (when res
      (set-match-data match-data)
      res)))

(defun hack--forward-parse-xhp (start-pos limit &optional propertize-tags)
  "Move point past the XHP expression beginning at START-POS.
If PROPERTIZE-TAGS is non-nil, apply `hack-xhp-tag' to tag names."
  (let ((tags nil))
    (goto-char start-pos)

    (catch 'done
      ;; Whilst we're inside XHP, and there are still more
      ;; tags in the buffer.
      (while t
        (unless (search-forward "<" limit t)
          ;; Can't find any more open tags.
          (throw 'done t))

        (let ((close-p (looking-at-p "/"))
              tag-name
              self-closing-p)
          (when close-p
            (forward-char 1))
          ;; Get the name of the current tag.
          (re-search-forward
           (rx (+ (or (syntax word) (syntax symbol)))))
          (setq tag-name (match-string 0))

          (when propertize-tags
            (let* ((inhibit-modification-hooks t)
                   (before-change-functions nil))
              (add-face-text-property (match-beginning 0) (match-end 0)
                                      'hack-xhp-tag)))

          (unless (search-forward ">" limit t)
            ;; Can't find the matching close angle bracket, so the XHP
            ;; expression is incomplete.
            (throw 'done t))

          (save-excursion
            (backward-char 2)
            (when (looking-at "/>")
              (setq self-closing-p t)))
          (cond
           (self-closing-p
            ;; A self-closing tag doesn't need pushing to the stack.
            nil)
           ((and close-p (string= tag-name (car tags)))
            ;; A balanced closing tag.
            (pop tags))
           (close-p
            ;; An unbalanced close tag, we were expecting something
            ;; else. Assume this is the end of the XHP section.
            (throw 'done t))
           (t
            ;; An open tag.
            (push tag-name tags)))

          (unless tags
            ;; Reach the close of the initial open XHP tag.
            (throw 'done t)))))

    (put-text-property start-pos (point)
                       'hack-xhp-expression start-pos)))

(defun hack-font-lock-interpolate-complex (limit)
  "Search for {$foo} string interpolation."
  (let (res start)
    (while (and
            (not res)
            (search-forward "{$" limit t))
      (let* ((ppss (syntax-ppss))
             (in-string-p (nth 3 ppss))
             (string-delimiter-pos (nth 8 ppss))
             (string-delimiter
              (when in-string-p (char-after string-delimiter-pos)))
             (interpolation-p in-string-p))
        (cond
         ;; Interpolation does not apply in single-quoted strings.
         ((eq string-delimiter ?')
          (setq interpolation-p nil))
         ;; We can interpolate in <<<FOO, but not in <<<'FOO'
         ((eq string-delimiter ?<)
          (save-excursion
            (goto-char string-delimiter-pos)
            (save-match-data
              (re-search-forward (rx (+ "<")))
              (when (looking-at (rx "'"))
                (setq interpolation-p nil))))))

        (when interpolation-p
          (setq start (match-beginning 0))
          (let ((restart-pos (match-end 0)))
            ;; Search forward for the } that matches the opening {.
            (while (and (not res) (search-forward "}" limit t))
              (let ((end-pos (point)))
                (save-excursion
                  (when (and (ignore-errors (backward-list 1))
                             (= start (point)))
                    (setq res end-pos)))))
            (unless res
              (goto-char restart-pos))))))
    ;; Set match data and return point so we highlight this
    ;; instance.
    (when res
      (set-match-data (list start res))
      res)))

(defconst hack--keyword-regex
  ;; Keywords, based on hphp.ll.
  ;; We don't highlight endforeach etc, as they're syntax errors
  ;; in full_fidelity_syntax_error.ml
  (regexp-opt
   '("exit"
     "die"
     "const"
     "return"
     "yield"
     "from"
     "try"
     "catch"
     "finally"
     "using"
     "throw"
     "if"
     "else"
     "while"
     "do"
     "for"
     "foreach"
     "declare"
     "enddeclare"
     "instanceof"
     "as"
     "super"
     "switch"
     "case"
     "default"
     "break"
     "continue"
     "goto"
     "echo"
     "print"
     "class"
     "interface"
     "trait"
     "insteadof"
     "extends"
     "implements"
     "enum"
     "attribute"
     "category"
     "children"
     "required"
     "function"
     "new"
     "clone"
     "var"
     "callable"
     "eval"
     "include"
     "include_once"
     "require"
     "require_once"
     "namespace"
     "use"
     "global"
     "isset"
     "empty"
     "__halt_compiler"
     "__compiler_halt_offset__"
     "static"
     "abstract"
     "final"
     "private"
     "protected"
     "public"
     "unset"
     "==>"
     "list"
     "array"
     "OR"
     "AND"
     "XOR"
     "dict"
     "keyset"
     "shape"
     "type"
     "newtype"
     "where"
     "await"
     "vec"
     "varray"
     "darray"
     "inout"
     "async"
     "tuple"
     "__CLASS__"
     "__TRAIT__"
     "__FUNCTION__"
     "__METHOD__"
     "__LINE__"
     "__FILE__"
     "__DIR__"
     "__NAMESPACE__"
     "__COMPILER_FRONTEND__"
     ;; Treat self:: and static:: as keywords.
     "self"
     "parent")
   'symbols))

(defconst hack--type-regex
  (rx
   (or
    (seq
     (? "?")
     symbol-start
     (or
      ;; Built-in classes, based on Classes in
      ;; naming_special_names.ml, excluding self/parent (which we've
      ;; treated as keywords above).
      "stdClass"
      "classname"
      "typename"

      ;; Built-in types, based on Typehints in naming_special_names.ml.
      "void"
      "resource"
      "num"
      "arraykey"
      "noreturn"
      "mixed"
      "nonnull"
      "this"
      "dynamic"
      "int"
      "bool"
      "float"
      "string"
      "array"
      "darray"
      "varray"
      "varray_or_darray"
      "integer"
      "boolean"
      "double"
      "real"
      "callable"
      "object"
      "unset"
      ;; User-defined type.
      (seq
       (0+ "_")
       (any upper)
       (* (or (syntax word) (syntax symbol)))))
     symbol-end)
    ;; We also highlight _ as a type, but don't highlight ?_.
    (seq symbol-start "_" symbol-end))))

(defun hack--in-xhp-p (pos)
  "Is POS inside an XHP expression?

Returns t if we're in a text context, and nil if we're
interpolating inside the XHP expression."
  (let ((expression-start-pos
         (get-text-property pos 'hack-xhp-expression)))
    (when expression-start-pos
      (let* ((ppss (save-excursion (syntax-ppss pos)))
             (paren-pos (nth 1 ppss))
             (interpolation-p
              (when (and paren-pos (< expression-start-pos paren-pos))
                (eq (char-after paren-pos) ?\{))))
        (not interpolation-p)))))

(defun hack--search-forward-no-xhp (regex limit)
  "Search forward for REGEX up to LIMIT, ignoring occurrences inside XHP blocks."
  (let ((end-pos nil)
        (match-data nil)
        (case-fold-search nil))
    (save-excursion
      (while (and (not end-pos)
                  (re-search-forward regex limit t))
        (unless (hack--in-xhp-p (point))
          (setq match-data (match-data))
          (setq end-pos (point)))))
    (when match-data
      (set-match-data match-data)
      (goto-char end-pos))))

(defun hack--search-forward-keyword (limit)
  "Search forward from point for an occurrence of a keyword."
  (hack--search-forward-no-xhp hack--keyword-regex limit))

(defun hack--search-forward-type (limit)
  "Search forward from point for an occurrence of a type name."
  (hack--search-forward-no-xhp hack--type-regex limit))

(defconst hack--user-constant-regex
  (rx
   symbol-start
   ;; Constants are all in upper case, and cannot start with a
   ;; digit.
   (seq (any upper "_")
        (+ (any upper "_" digit)))
   symbol-end))

(defun hack--search-forward-constant (limit)
  "Search forward from point for an occurrence of a constant."
  (hack--search-forward-no-xhp
   ;; null is also a type in Hack, but we highlight it as a
   ;; constant. It's going to occur more often as a value than a type.
   (regexp-opt '("null" "true" "false") 'symbols)
   limit))

(defun hack--search-forward-user-constant (limit)
  "Search forward from point for an occurrence of a constant."
  (hack--search-forward-no-xhp hack--user-constant-regex
                               limit))

(defun hack--search-forward-variable (limit)
  "Search forward from point for an occurrence of a variable."
  (hack--search-forward-no-xhp
   (rx symbol-start
       "$" (group (+ (or (syntax word) (syntax symbol))))
       symbol-end)
   limit))

(defun hack--search-forward-dollardollar (limit)
  "Search forward from point for an occurrence of $$."
  (hack--search-forward-no-xhp
   (rx symbol-start "$$" symbol-end)
   limit))

(defvar hack-font-lock-keywords
  `(
    (,hack--header-regex
     (1 font-lock-keyword-face)
     (2 font-lock-keyword-face t t))
    ;; Handle XHP first, so we don't confuse <p>vec</p> with the vec
    ;; keyword.
    (hack-font-lock-xhp
     (0 'default))

    (hack--search-forward-keyword
     (0 'font-lock-keyword-face))

    (hack--search-forward-type
     (0 'font-lock-type-face))

    (hack--search-forward-constant
     (0 'font-lock-constant-face))

    ;; We use font-lock-variable-name-face for consistency with c-mode.
    (hack--search-forward-user-constant
     (0 'font-lock-variable-name-face))

    ;; $$ is a special variable used with the pipe operator
    ;; |>. Highlight the entire string, to avoid confusion with $s.
    (hack--search-forward-dollardollar
     (0 'font-lock-variable-name-face))
    ;; Highlight variables that start with $, e.g. $foo. Don't
    ;; highlight the $, to make the name easier to read (consistent with php-mode).
    (hack--search-forward-variable
     (1 'font-lock-variable-name-face))

    ;; Highlight function names.
    (,(rx symbol-start
          "function"
          symbol-end
          (+ space)
          (group
           symbol-start
           (+ (or (syntax word) (syntax symbol)))
           symbol-end))
     1 font-lock-function-name-face)

    (hack-font-lock-fallthrough
     (1 'font-lock-keyword-face t))
    (hack-font-lock-unsafe
     (1 'error t))
    (hack-font-lock-unsafe-expr
     (1 'error t))
    (hack-font-lock-fixme
     (1 'error t))
    (hack-font-lock-ignore-error
     (1 'error t))

    ;; TODO: It would be nice to highlight interpolation operators in
    ;; Str\format or metacharacters in regexp literals too.
    (hack-font-lock-interpolate
     (0 font-lock-variable-name-face t))
    (hack-font-lock-interpolate-complex
     (0 font-lock-variable-name-face t))))

(defvar hack-mode-syntax-table
  (let ((table (make-syntax-table)))
    ;; Characters that are punctuation, not symbol elements.
    (modify-syntax-entry ?- "." table)
    (modify-syntax-entry ?< "." table)
    (modify-syntax-entry ?> "." table)
    (modify-syntax-entry ?+ "." table)
    (modify-syntax-entry ?& "." table)
    (modify-syntax-entry ?| "." table)
    (modify-syntax-entry ?= "." table)

    ;; Treat \ as punctuation, so we can navigate between different
    ;; parts of a namespace reference.
    (modify-syntax-entry ?\\ "." table)

    ;; Strings
    (modify-syntax-entry ?\" "\"" table)
    (modify-syntax-entry ?\\ "\\" table)
    (modify-syntax-entry ?' "\"" table)

    ;; Comments of the form
    ;; # This is a single-line comment.
    ;; Tag these as comment sequence b.
    (modify-syntax-entry ?# "< b" table)

    ;; / can start both // and /* style comments. When it's a second
    ;; character, it's a single line comment, so also tag as comment
    ;; sequence b.
    (modify-syntax-entry ?/ ". 124b" table)

    ;; * is the second character in /* comments, and the first
    ;; character in the end */.
    (modify-syntax-entry ?* ". 23" table)

    ;; Newlines end both # and // comments. Ensure we support both
    ;; unix and dos style newlines.
    (modify-syntax-entry ?\n "> b" table)
    (modify-syntax-entry ?\^m "> b" table)

    ;; < and > are paired delimiters.
    (modify-syntax-entry ?< "(>" table)
    (modify-syntax-entry ?> ")<" table)

    table))

(defun hack--comment-prefix (s)
  "Extract the leading '* ' from '* foo'."
  (when (string-match
         (rx bol (0+ space) (? "/") "*" (1+ space))
         s)
    (match-string 0 s)))

(defun hack--wrap-comment-inner (s)
  "Given a string of the form:

* a very long sentence here...

wrap it to:

* a very long
* sentence here..."
  (let* ((prefix (hack--comment-prefix s))
         (lines (s-lines s))
         (stripped-lines
          (mapcar
           (lambda (line) (s-chop-prefix prefix line))
           lines)))
    (with-temp-buffer
      (insert (s-join "\n" stripped-lines))
      (goto-char (point-min))
      (fill-paragraph)

      (let* ((wrapped-lines (s-lines (buffer-string)))
             (prefixed-lines
              (mapcar
               (lambda (line) (concat prefix line))
               wrapped-lines)))
        (s-join "\n" prefixed-lines)))))

(defun hack--fill-paragraph-star ()
  "Fill paragraph when point is inside a /* comment."
  (let* ((line-start-pos (line-beginning-position))
         (comment-start (nth 8 (syntax-ppss)))
         (comment-end nil))
    ;; Put a property on the text at point, so we can put point back afterwards.
    (put-text-property (point) (1+ (point)) 'hack-fill-start-pos t)
    (save-excursion
      (search-forward "*/")
      (setq comment-end (point)))
    (save-excursion
      (save-restriction
        ;; Narrow to the comment, to ensure we don't move beyond the end.
        (narrow-to-region comment-start comment-end)

        ;; Move over all the non-empty comment lines, considering * to
        ;; be an empty line.
        (while (and
                (not (eobp))
                (not (looking-at
                      (rx
                       bol
                       (? "/")
                       (0+ space) (? "*")
                       (0+ space)
                       eol))))
          (forward-line))

        (if (eobp)
            ;; Don't add the */ to our wrapped comment.
            (progn
              (forward-line -1)
              (end-of-line))
          ;; Exclude the trailing newline.
          (backward-char))

        (let ((contents (buffer-substring line-start-pos (point))))
          (delete-region line-start-pos (point))
          (insert (hack--wrap-comment-inner contents)))))
    (while (and (not (eobp))
                (not (get-text-property (point) 'hack-fill-start-pos)))
      (forward-char))
    (when (get-text-property (point) 'hack-fill-start-pos)
      (remove-text-properties (point) (1+ (point)) '(hack-fill-start-pos nil)))))

(defun hack-fill-paragraph (&optional _justify)
  "Fill the paragraph at point."
  (let* ((ppss (syntax-ppss))
         (in-comment-p (nth 4 ppss))
         (comment-start (nth 8 ppss))
         (comment-end nil)
         (in-star-comment-p nil))
    (when in-comment-p
      (save-excursion
        (goto-char comment-start)
        (when (looking-at (rx "/*"))
          (setq in-star-comment-p t))))
    (if in-star-comment-p
        (progn
          (hack--fill-paragraph-star)
          t)
      ;; Returning nil means that `fill-paragraph' will run, which is
      ;; sufficient for // comments.
      nil)))

(defvar hack-xhp-indent-debug-on nil)

(defun hack-xhp-indent-debug (&rest args)
  "Log ARGS if ‘hack-xhp-indent-debug-on’ is set."
  (if hack-xhp-indent-debug-on
      (apply 'message args)))

(defun hack-xhp-in-code-p ()
  "Return non-nil if point is currently in code,
i.e. not in a comment or string."
  (let* ((ppss (syntax-ppss))
         (in-string (nth 3 ppss))
         (in-comment (nth 4 ppss)))
    (and (not in-comment)
         (not in-string))))

(defun hack-xhp-indent-previous-semi (limit)
  "Search backward from point for the last semicolon.
Return nil if no semicolons were found before we reached position LIMIT.
Ignore semicolons in strings and comments."
  (if (not limit)
      (setq limit (point-min)))
  (when (> (point) limit)
    (let (res
          (keep-going t))
      (save-excursion
        (while keep-going
          (setq keep-going nil)

          (when (search-backward ";" limit t)
            (if (hack-xhp-in-code-p)
                (setq keep-going t)
              ;; semi found, done.
              (setq res (point)))))
        res))))

(defun hack-xhp-backward-whitespace ()
  "Move backwards until point is not on whitespace."
  (catch 'done
    (while t
      (when (bobp)
        (throw 'done nil))

      (let ((prev-char (char-after (1- (point))))
            (prev-syntax (syntax-after (1- (point)))))
        (unless (or (eq prev-char ?\n)
                    ;; 0 is the syntax code for whitespace.
                    (eq 0 (car-safe prev-syntax))
                    ;; Ignore whitespace in comments.
                    (nth 4 (syntax-ppss)))
          (throw 'done nil)))

      (backward-char))))

(defun hack-xhp-enclosing-brace-pos ()
  "Return the position of the innermost enclosing brace before point."
  (nth 1 (syntax-ppss)))

(defun hack-xhp-indent-offset ()
  "If point is inside an XHP expression, return the correct indentation amount.
Return nil otherwise."
  (let* ((start-pos (point))
         (min-brace
          (save-excursion
            ;; get out of anything being typed that might confuse the parsing
            (beginning-of-line)
            (hack-xhp-enclosing-brace-pos)))
         (min (save-excursion
                (or
                 (hack-xhp-indent-previous-semi min-brace)
                 min-brace
                 ;; skip past <?php
                 (+ (point-min) 5))))
         base-indent)
    ;; STEP 1: find a previous xhp element, and derive the normal
    ;; indentation from it.
    (save-excursion
      (if (and
           (> (point) min)
           (re-search-backward hack-xhp-start-regex min t)
           (hack-xhp-in-code-p))
          (setq
           base-indent
           ;; decide from this context if indentation should
           ;; be initially adjusted.
           (+
            ;; start with the indentation at this elt
            (current-indentation)
            ;; at the matched xhp element, figure out if the
            ;; indentation should be modified
            ;; TODO(abrady) too lazy to parse forward properly, these
            ;; work fine for now.
            (cond
             ;; CASE 1: matched elt is closed or self-closing e.g. <br />
             ;; or a 1-line enclosed stmt: <fbt:param>foo</fbt:param>
             ((save-excursion
                (beginning-of-line)
                (or
                 (re-search-forward "</" (line-end-position) t)
                 (re-search-forward "/> *$" start-pos t)
                 (re-search-forward "--> *$" start-pos t)))
              0)
             ;; DEFAULT: increase indent
             (t hack-indent-offset))))))
    ;; STEP 2: indentation adjustment based on what user has typed so far
    (if base-indent
        ;; STEP 2.1: we found indentation to adjust. use the current
        ;; context to determine how it should be adjusted
        (cond
         ;; CASE 0: indenting an attribute
         ((looking-at "^ *[a-zA-Z_-]+")
          base-indent)
         ;; CASE 1: Terminating a multiline php block is a special
         ;; case where we should default to php indentation as if we
         ;; were inside the braces
         ;; e.g. <div class={foo($a
         ;;                      $b)}>
         ((save-excursion
            (and
             (not (re-search-forward "^ *<" (line-end-position) t))
             (re-search-forward "}> *$" (line-end-position) t)))
          (hack-xhp-indent-debug "terminating php block")
          nil)
         ;; CASE 2: user is indenting a closing block, so out-dent
         ;; e.g.
         ;; <div>
         ;; </div>
         ((save-excursion
            (beginning-of-line)
            (re-search-forward "^ *</" (line-end-position) t))
          (+ base-indent (- hack-indent-offset)))
         ;; CASE 3: if this happens to be /> on its own
         ;; line, reduce indent (coding standard)
         ((save-excursion
            (goto-char start-pos)
            (re-search-forward "^ */> *" (line-end-position) t))
          (+ base-indent (- hack-indent-offset)))
         ;; CASE 4: close of xhp passed to a function, e.g.
         ;; foo(
         ;;   <xhp>
         ;; );
         ((save-excursion
            (re-search-forward "^ *);" (line-end-position) t))
          (+ base-indent (- hack-indent-offset)))
         ;; DEFAULT: no modification.
         (t base-indent))
      ;; STEP 2.2: FIRST STATEMENT AFTER XHP. if we're after
      ;; the close of an xhp statement it still messes up the php
      ;; indentation, so check that here and override
      (cond
       ;; CASE 1: multiline self-enclosing tag or closing tag
       ;; e.g.
       ;; <div
       ;;   foo="bar"
       ;; />;
       ;; - or -
       ;; <div>
       ;;  ...
       ;; </div>;
       ((save-excursion
          (hack-xhp-backward-whitespace)
          (and
           (looking-back "\\(/>\\|</.*>\\);" nil)
           ;; don't match single-line xhp $foo = <x:frag />;
           (not (re-search-backward "^ *\\$" (line-beginning-position) t))))
        ;; previous statement IS xhp. check what user has typed so
        ;; far
        (+
         (save-excursion (hack-xhp-backward-whitespace) (current-indentation))
         (cond
          ;; CASE 0: user typed a brace. outdent even more
          ((looking-at ".*}") (* -2 hack-indent-offset))
          ;; CASE 1: close of case in a switch stmt, e.g. case FOO:
          ((looking-at ".*: *$") (* -2 hack-indent-offset))
          ;; DEFAULT
          (t (- hack-indent-offset)))))
       ;; DEFAULT: not first stmt after xhp, indent normally
       (t nil)))))

(defun hack--indent-preserve-point (offset)
  "Indent the current line by OFFSET spaces.
Ensure point is still on the same part of the line afterwards."
  (let ((point-offset (- (current-column) (current-indentation))))
    (indent-line-to offset)

    ;; Point is now at the beginning of indentation, restore it
    ;; to its original position (relative to indentation).
    (when (>= point-offset 0)
      (move-to-column (+ (current-indentation) point-offset)))))

(defun hack--paren-depth-for-indent (pos)
  "Return the number of parentheses around POS.
Repeated parens on the same line are consider a single paren."
  (let ((depth 0)
        ;; Keep tracking of which line we saw each paren on. Since
        ;; calculating line number is O(n), just track the start
        ;; position of each line.
        (prev-paren-line-start nil))
    (save-excursion
      (goto-char pos)
      (catch 'done
        (while t
          (let* ((ppss (syntax-ppss))
                 (paren-start (nth 1 ppss)))
            (if paren-start
                (progn
                  (goto-char paren-start)
                  (unless (eq (line-beginning-position) prev-paren-line-start)
                    (setq depth (1+ depth)))
                  (setq prev-paren-line-start (line-beginning-position)))
              (throw 'done t))))))
    depth))

(defun hack--ends-with-infix-p (str)
  "Does STR end with an infix operator?"
  (string-match-p
   (rx
    space
    ;; https://docs.hhvm.com/hack/expressions-and-operators/operator-precedence
    (or "*" "/" "%" "+" "-" "."
	"<<" ">>" "<" "<=" ">" ">="
	"==" "!=" "===" "!==" "<=>"
	"&" "^" "|" "&&" "||" "?:" "??" "|>"
	"=" "+=" "-=" ".=" "*=" "/=" "%=" "<<=" ">>=" "&=" "^=" "|="
	"instanceof" "is" "as" "?as")
    (0+ space)
    line-end)
   str))

(defun hack-indent-line ()
  "Indent the current line of Hack code.
Preserves point position in the line where possible."
  (interactive)
  (if (hack--in-xhp-p (point))
      (let ((indent (hack-xhp-indent-offset)))
	(when indent
	  (hack--indent-preserve-point indent)))
    (hack--indent-line)))

(defun hack--indent-line ()
  "Indent the current line of non-XHP Hack code."
  (let* ((syntax-bol (syntax-ppss (line-beginning-position)))
         (in-multiline-string-p (nth 3 syntax-bol))
         (point-offset (- (current-column) (current-indentation)))
         (paren-depth (hack--paren-depth-for-indent (line-beginning-position)))

         (ppss (syntax-ppss (line-beginning-position)))
         (current-paren-pos (nth 1 ppss))
         (text-after-paren
          (when current-paren-pos
            (save-excursion
              (goto-char current-paren-pos)
              (buffer-substring
               (1+ current-paren-pos)
               (line-end-position)))))
         (in-multiline-comment-p (nth 4 ppss))
         (current-line (buffer-substring (line-beginning-position) (line-end-position))))
    ;; If the current line is just a closing paren, unindent by one level.
    (when (and
           (not in-multiline-comment-p)
           (string-match-p (rx bol (0+ space) (or ")" "}")) current-line))
      (setq paren-depth (1- paren-depth)))
    (cond
     ;; Don't indent inside heredoc/nowdoc strings.
     (in-multiline-string-p
      nil)
     ;; In multiline comments, ensure the leading * is indented by one
     ;; more space. For example:
     ;; /*
     ;;  * <- this line
     ;;  */
     (in-multiline-comment-p
      ;; Don't modify lines that don't start with *, to avoid changing the indentation of commented-out code.
      (when (or (string-match-p (rx bol (0+ space) "*") current-line)
                (string= "" current-line))
        (hack--indent-preserve-point (1+ (* hack-indent-offset paren-depth)))))
     ;; Indent according to the last paren position, if there is text
     ;; after the paren. For example:
     ;; foo(bar,
     ;;     baz, <- this line
     ((and
       text-after-paren
       (not (string-match-p (rx bol (0+ space) eol) text-after-paren)))
      (let (open-paren-column)
        (save-excursion
          (goto-char current-paren-pos)
          (setq open-paren-column (current-column)))
        (hack--indent-preserve-point (1+ open-paren-column))))
     ;; Indent according to the amount of nesting.
     (t
      (let ((current-line (s-trim current-line))
	    prev-line)
	(save-excursion
          ;; Try to go back one line.
          (when (zerop (forward-line -1))
            (setq prev-line
		  (buffer-substring (line-beginning-position) (line-end-position)))))

	;; Increase indent if the past line ended with an infix
	;; operator, so we get
	;; $x =
	;;   foo();
	(when (and prev-line
		   (hack--ends-with-infix-p prev-line))
	  (setq paren-depth (1+ paren-depth)))

	;; Increase indent for lines that are method calls or pipe expressions.
	;;
	;; $foo
	;;   ->bar(); <- this line
	(when (or (s-starts-with-p "->" current-line)
                  (s-starts-with-p "?->" current-line)
                  (s-starts-with-p "|>" current-line))
          (setq paren-depth (1+ paren-depth))))

      (hack--indent-preserve-point (* hack-indent-offset paren-depth))))
    ;; Point is now at the beginning of indentation, restore it
    ;; to its original position (relative to indentation).
    (when (>= point-offset 0)
      (move-to-column (+ (current-indentation) point-offset)))))

(defalias 'hack-xhp-indent-line 'hack-indent-line)

;; hh_server can choke if you symlink your www root
(setq find-file-visit-truename t)

;; Ensure that we use `hack-mode' for .php files, but put the
;; association at the end of the list so `php-mode' wins (if installed).
;;;###autoload
(add-to-list 'auto-mode-alist '("\\.php$" . hack-mode) t)

;; These extensions are hack-specific.
;;;###autoload
(add-to-list 'auto-mode-alist '("\\.hhi$" . hack-mode))
;;;###autoload
(add-to-list 'auto-mode-alist '("\\.hack$" . hack-mode))
;;;###autoload
(add-to-list 'auto-mode-alist '("\\.hck$" . hack-mode))

(defun hack-format-buffer ()
  "Format the current buffer with hackfmt."
  (interactive)
  (let ((src-buf (current-buffer))
        (src (buffer-string))
        (start-line (line-number-at-pos (point)))
        (start-column (current-column))
        (output-buf (get-buffer-create "*hackfmt*")))
    (with-current-buffer output-buf
      (erase-buffer)
      (insert src)
      (if (zerop
           (call-process-region (point-min) (point-max)
                                hack-hackfmt-name t t nil))
          (progn
            (unless (string= (buffer-string) src)
              ;; We've changed something, so update the source buffer.
              (copy-to-buffer src-buf (point-min) (point-max)))
            (kill-buffer))
        (error "Hackfmt failed, see *hackfmt* buffer for details")))
    ;; Do our best to restore point position.
    (goto-char (point-min))
    (forward-line (1- start-line))
    (forward-char start-column)))

(defun hack--maybe-format ()
  (when hack-format-on-save
    (hack-format-buffer)))

(defun hack-enable-format-on-save ()
  "Enable automatic formatting on the current hack-mode buffer.."
  (interactive)
  (setq-local hack-format-on-save t))

(defun hack-disable-format-on-save ()
  "Disable automatic formatting on the current hack-mode buffer.."
  (interactive)
  (setq-local hack-format-on-save nil))

;;;###autoload
(define-derived-mode hack-mode prog-mode "Hack"
  "Major mode for editing Hack code.

\\{hack-mode-map\\}"
  (setq-local font-lock-defaults '(hack-font-lock-keywords))
  (set (make-local-variable 'syntax-propertize-function)
       hack--syntax-propertize-function)

  (setq-local compile-command (concat hack-client-program-name " --from emacs"))
  (setq-local indent-line-function #'hack-indent-line)
  (setq-local comment-start "// ")
  (setq-local fill-paragraph-function #'hack-fill-paragraph)
  (setq imenu-generic-expression
        ;; TODO: distinguish functions from methods.
        `(("Function"
           ,(rx
             line-start
             (? (* space) (seq symbol-start (or "private" "protected" "public") symbol-end))
             (? (* space) (seq symbol-start "static" symbol-end))
             (? (* space) (seq symbol-start "async" symbol-end))
             (* space)
             symbol-start "function" symbol-end
             (+ space)
             (group (seq symbol-start (+? any) symbol-end)))
           1)
          ("Class"
           ,(rx
             line-start
             (? (* space) (seq symbol-start "abstract" symbol-end))
             (? (* space) (seq symbol-start "final" symbol-end))
             (* space)
             symbol-start "class" symbol-end
             (+ space)
             (group (seq symbol-start (+? any) symbol-end)))
           1)
          ("Interface"
           ,(rx symbol-start "interface" symbol-end
                (+ space)
                (group (seq symbol-start (+? any) symbol-end)))
           1)
          ("Trait"
           ,(rx symbol-start "trait" symbol-end
                (+ space)
                (group (seq symbol-start (+? any) symbol-end)))
           1)))

  (add-hook 'before-save-hook #'hack--maybe-format nil t))



(provide 'hack-mode)
;;; hack-mode.el ends here
