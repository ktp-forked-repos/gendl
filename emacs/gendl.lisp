;; $Id: //info.ravenbrook.com/project/gendl/master/genworks/emacs/gendl.lisp#5 $

(in-package :swank)

;;                            GENDL.LISP
;;           Nick Levine, Ravenbrook Limited, 2013-05-02
;;
;; 1.  INTRODUCTION
;;
;; The purpose of this document is to implement GENDL customisations
;; for SLIME.
;;
;; The following features have been implemented so far:
;;
;; * modeline and completion help for the keywords accepted by
;;   gendl:define-object,
;;
;; * modeline and completion help for the keywords accepted inside an
;;   :objects or :hidden-objects argument to gendl:define-object,
;;   gendl:make-object, or gendl:make-self.
;;
;; The intended readership is project developers.
;;
;; This document is not confidential. See end for copyright
;; information.

(defparameter *gendl-slime-release* "0.1.1")


;; 2.  TESTS
;;
;; It's handy to be able to test this outside of the SLIME environmemnt.
;;
;; '("define-object" "empty" nil ":objects" ("" %cursor-marker%))
;; ->
;; "(define-object name mixin-list &key ===> objects <=== &allow-other-keys)"

(defun gendl-autodoc-test (raw-form)
  (let ((*buffer-package* (find-package "GDL-USER"))
        (*buffer-readtable* *readtable*))
    (car (autodoc raw-form))))


;; 3.  MACROS

;; We need a (very, very) basic and portable advice facility. The
;; potentially dangerous assumption it makes is that the original
;; function won't be redefined behind our backs. I can't think of an
;; easy way to prevent users from doing that. On the other hand,
;; there's no reason why they should.

;; The #+lispworks conditionalisations immediately below are present
;; purely as development aids.

#+lispworks
(dspec:define-dspec-alias def-wrap (name)
  `(defun ,name))

(defmacro def-wrap (name lambda-list &body body)
  "Wrap BODY around the function defined by NAME. Locally defined #'PUNT
   will access the original definition."
  (let* ((args-var (gensym "ARGS-"))
         (cache-form `(unless (get ',name 'gendl-unwrapped)
                        (setf (get ',name 'gendl-unwrapped) (symbol-function ',name))))
         (wrapped-body `(,@(loop for next = (first body)
                                 while (or (stringp next)
                                           (and (consp next)
                                                (eq (car next) 'declare)))
                                 collect (pop body))
                         (flet ((punt (&rest ,args-var)
                                  (apply (get ',name 'gendl-unwrapped) ,args-var)))
                           ,@body))))
    #+lispworks
    `(dspec:def (def-wrap ,name)
       ,cache-form
       (let ((lw:*redefinition-action* :quiet))
         (defun ,name ,lambda-list ,@wrapped-body))
       ',name)
    #-lispworks
    `(progn
       ,cache-form
       (setf (symbol-function ',name)
             (lambda ,lambda-list ,@wrapped-body)))))


(defun wrap-test-original (x)
  (cons :original x))

(defun test-def-wrap ()
  (def-wrap wrap-test-original (x)
    (cons :wrapped (cdr (punt (1+ x)))))
  (assert (equal (wrap-test-original 3) '(:wrapped . 4)))
  (def-wrap wrap-test-original (x)
    (punt x))
  (assert (equal (wrap-test-original 3) '(:original . 3))))

(test-def-wrap)


;; 4.  ADVISE SWANK FUNCTIONS
;;
;; The main defintions of the four functions wrapped below are all in
;; the contrib file swank-arglists.lisp.
;;
;; We use *autodoc-highlighting* to disable runaway hightlighting when
;; we're showing init-slots in the modeline. The method on
;; compute-enriched-decoded-arglist below might set *autodoc-highlighting*
;; to nil.

(defvar *autodoc-highlighting* t)

;; Used for modeline display of available arguments.
(def-wrap autodoc (raw-form &key print-right-margin)
  (let ((*autodoc-highlighting* *autodoc-highlighting*)
        ;; The default is to view symbols as if we were in the CL-USER
        ;; package. I can't see how this helps anybody, so I'm
        ;; disabling it.
        (*arglist-show-packages* nil))
    (punt raw-form :print-right-margin print-right-margin)))

(def-wrap form-path-to-arglist-path (form-path form arglist)
  (when *autodoc-highlighting*
    (punt form-path form arglist)))

;; There are two different paths which call find-subform-with-arglist. We
;; want to know which one we're on and we do this by binding
;; *grovelling-for-arglist*.

(defvar *grovelling-for-arglist* nil)

;; Used for (keyword) completion.
(def-wrap find-immediately-containing-arglist (form)
  (let ((*grovelling-for-arglist* t))
    (punt form)))

;; This might be useful further down.
(defvar *form-with-arglist*)

;; Invoked by both autodoc and find-immediately-containing-arglist.
(def-wrap find-subform-with-arglist (form)
  (let ((*form-with-arglist* form))
    (if (and *grovelling-for-arglist*
             (eq (car form) 'gendl:define-object))
        (find-define-object-subform form #'punt)
      (punt form))))


;; 5.  KEYWORDS ACCEPTED BY DEFINE-OBJECT, MAKE-OBJECT, MAKE-SELF

;;; We make gendl:define-object appear to have the same arglist as
;;; gendl::%define-object% (modulo three keywords which Dave Cooper
;;; says aren't in use.)

(defparameter *define-object-unsupported*
  '(:methods :no-vanilla-mixin? :query-slots))

;; See (defgeneric extra-keywords) in swank-arglists.lisp
(defmethod extra-keywords ((operator (eql 'gendl:define-object)) &rest arguments)
  (values (reverse (let ((unsupported *define-object-unsupported*))
		     (loop for keyword-arg in (arglist.keyword-args (compute-enriched-decoded-arglist 'gendl::%define-object% arguments))
			unless (find (keyword-arg.keyword keyword-arg) unsupported)
			collect keyword-arg)))
          t nil))

(defmethod extra-keywords ((operator (eql 'gendl:make-object)) &rest args)
  (or (keyword-args-from-class-input-slots (car args))
      (call-next-method)))

(defmethod extra-keywords ((operator (eql 'gendl:make-self)) &rest args)
  (or (keyword-args-from-class-input-slots (car args))
      (call-next-method)))

(defun keyword-args-from-class-input-slots (classname-form)
  (when (and (consp classname-form)
             (= (length classname-form) 2)
             (eq (car classname-form) 'quote))
    (let ((classname (cadr classname-form)))
      (multiple-value-bind (proceed input-slots)
          (class-input-slots classname)
        (when proceed
          (loop for slot in input-slots collect
                (make-keyword-arg slot slot nil)))))))



;; 6.  HELP ON SPECIFIC DEFINE-OBJECT KEYWORDS
;;
;; We use the swank interface for "enriching" an arglist. The method
;; below determines whether we're working on a specific keyword

;; A call might look like this:
;; (compute-enriched-decoded-arglist define-object (empty nil :objects (#s(swank::arglist-dummy :string-representation ""))))
;; Note that SLIME has already chopped everything to the right of the
;; cursor maker; editing
;;     (define-object empty () :objects ( ) :documentation ())
;; with the cursor here:              -->^<--
;; is the same as editing (define-object empty () :objects ()).
;;
;; See (defgeneric compute-enriched-decoded-arglist) in swank-arglists.lisp
(defmethod compute-enriched-decoded-arglist ((operator (eql 'gendl:define-object)) arguments)
  (multiple-value-bind (decoded-arglist determining-args any-enrichment)
      (call-next-method)
    (destructuring-bind (&optional name mixins &rest spec-pairs)
        arguments
      (declare (ignore name mixins))
      ;; Has the user got as far as the keyword list yet?
      (when spec-pairs
        ;; Which keyword are they working on?
        (multiple-value-bind (key values)
            (active-keyword spec-pairs)
          (when key
            (let ((this-keyword-arg (find key (arglist.keyword-args decoded-arglist)
                                          :key 'keyword-arg.keyword)))
              (when this-keyword-arg
                ;; Mangle the arglist structure: only show the keyword we're working on.
                (let ((local-arglist (copy-arglist decoded-arglist)))
                  (setf (arglist.keyword-args local-arglist) (list this-keyword-arg)
                        (arglist.rest local-arglist) nil
                        (arglist.allow-other-keys-p local-arglist) t
                        ;; Disable highlighting.
                        *autodoc-highlighting* nil)
                  (return-from compute-enriched-decoded-arglist
                    ;; If we can, make the init-slots for this keyword appear to be
                    ;; its default initargs. Behold! That makes them look just right.
                    (values (augment-gendl-define-object (keyword-arg.keyword this-keyword-arg)
                                                         local-arglist
                                                         values)
                            determining-args t)))))))))
    ;; &allow-other-keys and &rest don't contribute anything here.
    (setf (arglist.rest decoded-arglist) nil
	  (arglist.allow-other-keys-p decoded-arglist) nil)
    (values decoded-arglist determining-args any-enrichment)))

(defgeneric augment-gendl-define-object (keyword arglist values)
  (:documentation
   "We're editing the value for gendl:define-object keyword KEYWORD. Return
    an arglist based on ARGLIST which conveys more information about the
    VALUES being edited."
   )
  (:method (keyword arglist values)
   (declare (ignore keyword values))
   arglist))


;; 6.1. Keyword support for :objects & :hidden-objects

(defmethod augment-gendl-define-object ((keyword (eql :objects)) arglist values)
  (augment-gendl-define-object-for-objects keyword arglist values))

(defmethod augment-gendl-define-object ((keyword (eql :hidden-objects)) arglist values)
  (augment-gendl-define-object-for-objects keyword arglist values))

;; Perform basic checks and then treat this as an implicit make-object.
(defun augment-gendl-define-object-for-objects (keyword arglist values)
  (let ((keyword-arg (or (find keyword (arglist.keyword-args arglist) :key 'keyword-arg.keyword)
                         ;; Shouldn't get here; playing it safe.
                         (return-from augment-gendl-define-object-for-objects arglist)))
        (value (let ((value (car (last values))))
                 (if (consp value)
                     value
                   (return-from augment-gendl-define-object-for-objects arglist)))))
    (setf (keyword-arg.default-arg keyword-arg) (implicit-make-object value)))
  arglist)

;; Value is the object-form on which the user is working. It'll be a
;; list consisting of lisp objects interspersed with SWANK arglist-dummies.
(defun implicit-make-object (value)
  (or (multiple-value-bind (proceed name type input-slots)
          (destructure-implicit-make-object value)
        (when proceed
          (let ((safe-name (let ((*read-eval* nil))
                             (read-from-string (undummy name)))))
	    ;; Note use of intern, to ensure hardwired symbols arrive in *package*.
            `((,safe-name :type ,type &key ,@input-slots) &rest ,(cautious-intern "MORE-OBJECTS")))))
      ;; We haven't got far enough to say anything yet.
      `((,(cautious-intern "NAME") &key type &allow-other-keys) &rest ,(cautious-intern "MORE-OBJECTS"))))

(defun cautious-intern (string)
  (if (eq (readtable-case *readtable*) :preserve)
      ;; Allegro modern mode?
      (intern (string-downcase string))
    (intern string)))


;; 7.  KEYWORD COMPLETION

(defun find-define-object-subform (form finder)
  (destructuring-bind (&optional name mixins &rest spec-pairs)
      (cdr form)
    (declare (ignore name mixins))
    ;; Has the user got onto the keyword list yet?
    (when spec-pairs
      ;; Which keyword are they working on?
      (multiple-value-bind (key values)
          (active-keyword spec-pairs)
        (when key
          (let* ((value (car (last values)))
                 (new-form ;; (To do: hive this off as a separate GF.)
                           (case key
                             ((:objects
                               :hidden-objects) (let ((keywords (loop for x in (cdr value) until (arglist-dummy-p x) collect x)))
                                                  (multiple-value-bind (proceed name type input-slots)
                                                      (destructure-implicit-make-object
                                                       (cons (intern (undummy (car value))) keywords))
                                                    (declare (ignore name input-slots))
                                                    (if proceed
                                                        `(gendl:make-self ,type)
                                                      ;; Nothing useful found. Bail out.
                                                      (return-from find-define-object-subform
                                                        (values '(gendl:make-self)
                                                                (make-arglist :key-p t
                                                                              :keyword-args (unless (find :type keywords)
                                                                                              (list (make-keyword-arg :type :type nil)))
                                                                              :allow-other-keys-p t))))))))))
            ;; Can we do anything with this keyword?
            (when new-form
              ;; Apply original defintion of find-subform-with-arglist to gendl:make-self form.
              (return-from find-define-object-subform
                (funcall finder new-form))))))))
  ;; No? Apply original defintion of find-subform-with-arglist to original
  (funcall finder form))



;; 8.  DESTRUCTURING IMPLICIT MAKE-OBJECT FORMS

(defun destructure-implicit-make-object (form)
  "If FORM destructures as (SLOTNAME (quote CLASSNAME) ...) and CLASSNAME
   names a subclass of gendl:vanilla-mixin* then treturn four values: t,
   SLOTNAME, (quote CLASSNAME), and the class's init-slots. Otherwise
   return nil."
  (multiple-value-bind (name classname-form)
      (ignore-errors                                   ; catch destructuring-bind errors
        (destructuring-bind (name &key ((:type classname-form)) &allow-other-keys)
            (if (oddp (length form))                   ; is (cdr form) currently a well-formed plist?
                form
              (butlast form))
          (values name classname-form)))
    ;; CLASSNAME-FORM destructures as 'CLASSNAME.
    (let ((classname (when (and (listp classname-form)
                                (eq (car classname-form) 'quote))
                       (cadr classname-form))))
      (multiple-value-bind (proceed input-slots)
          (class-input-slots classname)
        (values proceed name classname-form input-slots)))))

(defun class-input-slots (classname)
  "Use message-list on a prototype instance of CLASSNAME to determine its
   required and optional input-slots. Return two values: t and the slots.
   If the class wasn't a subclass of gendl:vanilla-mixin* then return nil"
  (when (and classname
             (symbolp classname)
             (let ((class (find-class classname nil)))
               (when class
                 (subtypep class 'gendl:vanilla-mixin*))))
    (let ((prototype (class-prototype classname)))
      (values t
              (append (gendl:the-object prototype (message-list :category :required-input-slots))
                      (remove-if 'internal-name-p
                                 (gendl:the-object prototype (message-list :category :optional-input-slots))))))))

(defun class-prototype (class)
  "Install the correct defintion of class-prototype and invoke it, if we
can. Otherwise, fall back on make-self."
  (let* ((package-designator ;; list heaved out of closer-mop-packages.lisp
                             #+abcl      :ext
                             #+allegro   :excl
                             #+clozure   :ccl
                             #+cmu       :pcl
                             #+ecl       :clos
                             #+lispworks :clos
                             #+mcl       :ccl
                             #+sbcl      :sb-pcl)
         (class-prototype (when package-designator
                            (find-symbol (string 'class-prototype) package-designator))))
    (if class-prototype
        (progn
          (setf (symbol-function 'class-prototype)
                (symbol-function class-prototype))
          (funcall class-prototype class))
      (or (get 'class-prototype 'instance)
          (setf (get 'class-prototype 'instance)
                (gendl:make-self class))))))

(defun internal-name-p (keyword)
  (let ((symbol-name (symbol-name keyword)))
    (and (char= (schar symbol-name 0) #\%)
         (char= (schar symbol-name (1- (length symbol-name))) #\%))))


;; 9.  HELP ON MESSAGES FOR THE

(defmethod compute-enriched-decoded-arglist ((operator (eql 'gendl:the)) arguments)
  (let* ((whole-form *form-with-arglist*)
         (messages (when (and (consp whole-form)
                              (eq (car whole-form) 'gendl:define-object))
                     (remove-duplicates (loop for locator in *message-locators* append
                                              (funcall locator whole-form))
                                        :from-end t))))
    (if messages
        (values (make-arglist :key-p t
                              :keyword-args (loop for message in messages collect
                                                  (make-keyword-arg message message nil))
                              :provided-args nil
                              :rest 'reference-chain)
                nil t)
    (call-next-method))))

(defparameter *message-locators*
  '(messages-in-this-form
    messages-from-classes)
  "A list of functions, each taking a (gendl:define-object ...) form,
each returning a list of proposed messages.")

(defun messages-in-this-form (form)
  "Do what define-object itself does, to figure out the messages being
defined by this form."
  (destructuring-bind (classname &optional mixins
                                 &key input-slots computed-slots objects hidden-objects functions methods
                                 &allow-other-keys)
      (cdr form)
    (declare (ignore classname mixins))
    ;; [logic lifted from gendl::with-gdl-message-symbols]
    (loop for section in (list input-slots computed-slots objects hidden-objects functions methods)
          append
          (with-buffer-syntax ()
            (let ((keyword (find-package :keyword)))
              (loop for item in section
                    for symbol = (cond ((symbolp item) item)
                                       ((consp item) (unless ;; Exclude the message we're in the process of creating.
                                                         (form-contains-cursor-marker item)
                                                       (let ((first (gendl::first-symbol item)))
                                                         (typecase first
                                                           (symbol first)
                                                           (arglist-dummy (from-string (arglist-dummy.string-representation first))))))))
                    when symbol
                    collect
                    (if (eq (symbol-package symbol) keyword)
                        symbol
                      (intern (symbol-name symbol) keyword))))))))

(defun form-contains-cursor-marker (form)
  (loop for thing in form
        when (or (eq thing '%cursor-marker%)
                 (and (consp thing)
                      (form-contains-cursor-marker thing)))
        do (return t)))


(defun messages-from-classes (form)
  "Use message-list to find out what the messages might be."
  (let* ((starting-classes (destructuring-bind (classname &optional mixins &rest keywords)
                               (cdr form)
                             (declare (ignore keywords))
                             (let ((this-class (find-class classname nil)))
                               (if this-class
                                   ;; It's a redefinition
                                   (list this-class)
                                 ;; New definition. Hit the superclasses.
                                 (loop for classname in mixins
                                       for class = (find-class classname nil)
                                       when class collect class)))))
         (mixins (remove-duplicates (loop for class in starting-classes append
                                          (gendl:the-object (gendl:make-self class) all-mixins))
                                    :from-end t))
         (messages (remove-duplicates (loop for class in mixins
                                            append (messages-from-class class)))))
    (sort (copy-list messages)
          'string<)))

;; [gendl] make your own defparameter for now, but flag it that it
;; might be redundant with something we already have defined
(defparameter *internal-packages*
  (loop for designator in
        '(:gendl :geom-base :surf :gwl :yadd :tasty)
        collect
        (find-package designator)))

(defparameter *messages-to-suppress*
  (list :aggregate :all-mixins :children-uncached :direct-mixins :documentation
	:hidden? :leaves-uncached :message-documentation :message-list :mixins :name-for-display
	:restore-all-defaults! :restore-tree! :root :root-path-local :root? :safe-children
	:safe-hidden-children :slot-documentation :slot-source :slot-status :update! :visible-children
	:write-snapshot))

(defun messages-from-class (class)
  "Return a list of messages. Take anything from a user-defined class (not
in one of the *internal-packages*), otherwise filter for non-nil message-remarks."
  (unless (find class '(gendl::gdl-basis standard-object t))
    (let ((prototype (class-prototype class)))
      (gendl:the-object prototype
                        (message-list :message-type :local
                                      :filter (if (find (symbol-package class)
                                                        *internal-packages*)
                                                  (lambda (category keyword)
                                                    (declare (ignore category))
                                                    (not (or (find keyword *messages-to-suppress*)
                                                             (null (gendl:the-object prototype (message-remarks keyword))))))
                                                :normal))))))



;; 10.  UTILITIES

;; List is of form (:keyword stuff :keyword stuff ...); the final stuff may be missing.
;; Return the final (:keyword stuff) pair as two values, provided stuff is a list.
;; Otherwise return nil.
(defun active-keyword (list)
  (let ((key nil)
        (stuff nil))
    (loop (setf key (pop list))
          (if list
              (setf stuff (pop list))
            (return-from active-keyword
              nil))
          (unless list
            (return)))
    (when (listp stuff)
      (values key stuff))))

(defun test-active-keyword ()
  (loop for (list . result) in '((() . nil)
                                 ((:foo) . nil)
                                 ((:foo bar) . nil)
                                 ((:foo (bar)) . (:foo (bar)))
                                 ((:foo (bar) :baz) . nil)
                                 ((:foo (bar) :baz ()) . (:baz nil))
                                 )
        do
        (multiple-value-bind (keyword stuff)
            (active-keyword list)
          (if keyword
              (assert (equal (list keyword stuff) result))
            (null result)))))

(test-active-keyword)


;; A.  REFERENCES
;;
;;
;; B.  HISTORY
;;
;; 2013-05-02 NDL Created.
;;
;; 2013-05-09 NDL Version 0.1 as http://paste.lisp.org/display/137088
;;
;; 2013-05-10 NDL Added *gendl-slime-release*.
;;                Release 0.1.1 as http://paste.lisp.org/display/137101
;;
;;
;; C.  COPYRIGHT
;;
;; Copyright 2013 Genworks International
;;
;; This source file is part of the General-purpose Declarative
;; Language project (GDL).
;;
;; This source file contains free software: you can redistribute it
;; and/or modify it under the terms of the GNU Affero General Public
;; License as published by the Free Software Foundation, either
;; version 3 of the License, or (at your option) any later version.
;;
;; This source file is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
;; Affero General Public License for more details.
;;
;; You should have received a copy of the GNU Affero General Public
;; License along with this source file.  If not, see
;; <http://www.gnu.org/licenses/>.


