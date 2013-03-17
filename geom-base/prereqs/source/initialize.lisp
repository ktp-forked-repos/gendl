(in-package :geom-base)

;;
;; Remember symbol, default, new setting for each global param affected by init function.
;;
(defvar *settings* (list (list 'cl-who:*prologue* cl-who:*prologue* "<!doctype HTML>")
			 (list 'cl-who:*attribute-quote-char* cl-who:*attribute-quote-char* #\")
			 (list 'cl-who:*downcase-tokens-p* cl-who:*downcase-tokens-p* nil)
			 (list 'gdl:*gs-path* gdl:*gs-path* #'(lambda() (glisp:find-gs-path)))))

(defvar *new-features* (list :geom-base))

(defun initialize ()
  (let (anything-changed?)
    (setq anything-changed? (glisp:set-settings *settings*)
	  anything-changed? (glisp:set-features *new-features*)) anything-changed?))

