;;; ebdb-chn.el --- China-specific internationalization support for EBDB  -*- lexical-binding: t; -*-

;; Copyright (C) 2016-2017  Free Software Foundation, Inc.

;; Author: Eric Abrahamsen <eric@ericabrahamsen.net>
;; Maintainer: Eric Abrahamsen <eric@ericabrahamsen.net>
;; Version: 1.2
;; Package-Requires: ((pyim "1.6.0") (ebdb "0.2"))

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <http://www.gnu.org/licenses/>.

;;; Commentary:

;; Bits of code for making EBDB nicer to use with China-based
;; contacts, both for handling Chinese characters, and for formatting
;; of phones and addresses.  Be aware that using this library will
;; incur a non-neglible slowdown at load time.  It shouldn't have any
;; real impact on search and completion times.

;; Generic methods don't play nice with autoloads: you'll need to
;; require this package after installing it.

;;; Code:

(when t (require 'pyim))
(require 'ebdb-i18n)

(cl-defmethod ebdb-string-i18n ((phone ebdb-field-phone)
				(_cc (eql 86)))
  (with-slots (area-code number extension) phone
    (concat
     "+86 "
     (if area-code
	 (format "%d-%s" area-code number)
       number)
     (if extension
	 (format "X%d" extension)
       ""))))

(cl-defmethod ebdb-parse-i18n ((class (subclass ebdb-field-phone))
			       (str string)
			       (_cc (eql 86))
			       &optional slots)
  ;; First remove everything but the numbers.
  (let ((num-str (string-trim
		  (replace-regexp-in-string "[^0-9Xx]+" "" str)))
	a-code)
    ;; In China, basically everything that starts with a 1 is a cell
    ;; number, unless it starts with a 10, in which case it's the
    ;; Beijing area code.  Sometimes the area codes are written with a
    ;; leading zero, but they shouldn't be saved that way.
    (when (string-match "\\`0?\\(10\\|[2-9][0-9]\\{1,2\\}\\)?\\([0-9]+\\)" num-str)
      (setq a-code (match-string 1 num-str)
	    slots (plist-put slots :number (match-string 2 num-str)))
      (when a-code
	(setq slots (plist-put slots :area-code (string-to-number a-code)))))
    (when (string-match "X\\([0-9]+\\)\\'" num-str)
      (setq slots (plist-put slots :extension
			     (string-to-number (match-string 1 num-str)))))
    (apply #'make-instance class slots)))

(cl-defmethod ebdb-string-i18n ((adr ebdb-field-address)
				(_cc (eql chn)))
  (with-slots (streets locality region postcode) adr
    (if (eql (aref char-script-table (aref locality 0)) 'han)
	(concat
	 ;; There are four municipalities, we don't need to repeat
	 ;; city-plus-province for them.
	 (unless (string-match-p "北京\\|重庆\\|上海\\|天津" region)
	   region)
	 locality
	 (mapconcat #'identity streets "")
	 ", " postcode)
      (ebdb-format-address-default adr))))

;; This isn't all of them, but it seems like a reasonable subset.  See
;; https://en.wikipedia.org/wiki/Chinese_compound_surname for a fuller
;; list.
(defvar ebdb-i18n-chn-compound-surnames
  '("慕容" "上官" "司马" "欧阳" "司徒" "司空" "西门" "爱新觉罗")
  "A list of Chinese surnames that are longer than one
  character.")

(cl-defmethod ebdb-parse-i18n ((class (subclass ebdb-field-name-complex))
			       (string string)
			       (_script (eql han))
			       &optional _slots)
  (let (surname given-names)
    (if (string-match (format "\\`\\(%s\\)\\(.*\\)\\'"
			      (regexp-opt ebdb-i18n-chn-compound-surnames))
		      string)
	(setq surname (match-string 1 string)
	      given-names (match-string 2 string))
      (setq surname (substring string 0 1)
	    given-names (substring string 1)))

    (make-instance class
		   :surname surname
		   :given-names (list given-names))))

(cl-defmethod ebdb-string-i18n ((field ebdb-field-name-complex)
				(_script (eql han)))
  "Properly format names in Chinese characters.

This should only run once, at init time, or any time a record's
name is changed.  The value ends up in the 'name-string slot of
the record cache."
  (with-slots (surname given-names) field
    (concat (when surname surname)
	    (when given-names (car given-names)))))

(cl-defmethod ebdb-china-handle-name ((field ebdb-field-name-complex)
				      (record ebdb-record)
				      add-or-del)
  "Add or remove a hash for a Chinese-character name.

This function is called by both the `ebdb-init-field-i18n' and
`ebdb-delete-field-i18n' methods.  It checks if the name is in
Chinese characters, and if it is, converts it into pinyin, and
either adds or removes a hash entry for the record under that
name.  It also adds the pinyin to the record's name cache, so
searchs via pinyin will find the record."
  ;; We use `pyim-hanzi2pinyin-simple' because it's cheaper, and
  ;; because checking for multiple character pronunciations isn't
  ;; really helpful in people's names.
  (let ((fl-py (pyim-hanzi2pinyin-simple (ebdb-name-fl field)))
	(lf-py (pyim-hanzi2pinyin-simple
		;; Don't use `ebdb-name-lf', because there's no sense
		;; in having the comma in there.
		(concat (ebdb-name-last field)
			" "
			(ebdb-name-given field t))))
	(name-string (ebdb-string field))
	hashfunc listfunc)
    (if (eql add-or-del 'add)
	(progn
	  (setq hashfunc #'ebdb-puthash
		listfunc #'object-add-to-list))
      (setq hashfunc #'ebdb-remhash
	    listfunc #'object-remove-from-list))
    (funcall hashfunc fl-py record)
    (funcall hashfunc lf-py record)
    (funcall hashfunc name-string record)
    (funcall listfunc (ebdb-record-cache record) 'alt-names fl-py)
    (funcall listfunc (ebdb-record-cache record) 'alt-names name-string)
    (funcall listfunc (ebdb-record-cache record) 'alt-names lf-py)))

(cl-defmethod ebdb-china-handle-name ((field ebdb-field-name-simple)
				      (record ebdb-record)
				      add-or-del)
  "Add or remove a hash for a Chinese-character name."
  ;; We use `pyim-hanzi2pinyin-simple' because it's cheaper, and
  ;; because checking for multiple character pronunciations isn't
  ;; really helpful in people's names.
  (let ((name-string (ebdb-string field))
	hashfunc listfunc)
    (if (eql add-or-del 'add)
	(progn
	  (setq hashfunc #'ebdb-puthash
		listfunc #'object-add-to-list))
      (setq hashfunc #'ebdb-remhash
	    listfunc #'object-remove-from-list))
    (funcall hashfunc name-string record)
    (funcall listfunc (ebdb-record-cache record) 'alt-names name-string)))

(cl-defmethod ebdb-init-field-i18n ((field ebdb-field-name)
				    record
				    (_script (eql han)))
  (ebdb-china-handle-name field record 'add))

(cl-defmethod ebdb-delete-field-i18n ((field ebdb-field-name)
				      record
				      (_script (eql han))
				      _unload)
  (ebdb-china-handle-name field record 'del))

(eval-after-load 'ebdb-snarf
  '(push (format "%s\\cc\\{1,2\\}\\|\\cc\\{2,3\\}"
		 (regexp-opt ebdb-i18n-chn-compound-surnames))
	 ebdb-snarf-name-re))

;;;; ChangeLog:

;; 2017-09-26  Eric Abrahamsen  <eric@ericabrahamsen.net>
;; 
;; 	Safer to check script of address locality
;; 
;; 	And bump version
;; 
;; 	* packages/ebdb-i18n-chn/ebdb-i18n-chn.el (ebdb-string-i18n): Check
;; 	 the script of the locality, not the street address.
;; 
;; 2017-09-25  Eric Abrahamsen  <eric@ericabrahamsen.net>
;; 
;; 	Edit address formatting to match changes in EBDB package
;; 
;; 	* packages/ebdb-i18n-chn/ebdb-i18n-chn.el (ebdb-string-i18n): Address
;; 	 formatting is now much simpler, use the new function. Push this
;; 	 change, and try like hell to remember to bump this package version
;; 	 at the same time the EBDB package version gets bumped.
;; 
;; 2017-09-05  Eric Abrahamsen  <eric@ericabrahamsen.net>
;; 
;; 	Guard require statements for packages outside of ELPA
;; 
;; 	* packages/counsel-ebdb/counsel-ebdb.el:
;; 	* packages/ebdb-i18n-chn/ebdb-i18n-chn.el:
;; 	* packages/helm-ebdb/helm-ebdb.el: Wrap require for ivy, pyim and
;; 	 helm, respectively, in (when t ...) forms.
;; 
;; 2017-08-30  Eric Abrahamsen  <eric@ericabrahamsen.net>
;; 
;; 	Teach EBDB to snarf Chinese names
;; 
;; 	* packages/ebdb-i18n-chn/ebdb-i18n-chn.el: Add a regexp specific to
;; 	 Chinese names to the value of ebdb-snarf-name-re.
;; 
;; 2017-08-16  Eric Abrahamsen  <eric@ericabrahamsen.net>
;; 
;; 	Provide the right package name for ebdb-i18n-chn
;; 
;; 	* packages/ebdb-i18n-chn/ebdb-i18n-chn.el: You'd almost think I hadn't
;; 	 tested this.
;; 
;; 2017-08-16  Eric Abrahamsen  <eric@ericabrahamsen.net>
;; 
;; 	Re-convolute ebdb-string-i18n for addresses
;; 
;; 	* packages/ebdb-i18n-chn/ebdb-i18n-chn.el (ebdb-string-i18n): Dunno
;; 	 how that happened.
;; 
;; 2017-08-15  Stefan Monnier  <monnier@iro.umontreal.ca>
;; 
;; 	* edbd-i18n-chn.el: Fix typo in metadata
;; 
;; 2017-08-15  Eric Abrahamsen  <eric@ericabrahamsen.net>
;; 
;; 	Fix up headers for ebdb-i18n-chn
;; 
;; 	* packages/ebdb-i18n-chn/ebdb-i18n-chn.el: There was no Maintainer
;; 	 header -- was that why it didn't deploy?
;; 
;; 2017-08-13  Eric Abrahamsen  <eric@ericabrahamsen.net>
;; 
;; 	Stick to variable naming scheme
;; 
;; 	* packages/ebdb-i18n-chn/ebdb-i18n-chn.el
;; 	(ebdb-i18n-china-compound-surnames):
;; 	 All auxiliary variables should start with "ebdb-i18n".
;; 
;; 2017-08-13  Eric Abrahamsen  <eric@ericabrahamsen.net>
;; 
;; 	Add internationalized ebdb-string method for Chinese addresses
;; 
;; 	* packages/ebdb-i18n-chn/ebdb-i18n-chn.el (ebdb-string-i18n): Format
;; 	 Chinese addresses correctly.
;; 
;; 2017-08-11  Eric Abrahamsen  <eric@ericabrahamsen.net>
;; 
;; 	Add external/contrib packages for EBDB
;; 


(provide 'ebdb-i18n-chn)
;;; ebdb-i18n-chn.el ends here
