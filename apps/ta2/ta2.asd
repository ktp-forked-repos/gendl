;;;; -*- coding: utf-8 -*-

(asdf:defsystem #:ta2 :description
 "The Gendl™ (legacy) Testing and Tracking Utility, version 2 (using Ajax but pre-gdlAjax, and no JQuery or CSS)"
 :author "Dave Cooper and Genworks International" :license
 "Gnu Affero General Public License (please see http://www.gnu.org/licenses/)"
 :serial t :version "20130710" :depends-on (:gwl-graphics)
 #+asdf-encoding :encoding #+asdf-encoding :utf-8
 :components
 ((:file "source/package") (:file "source/parameters")
  (:file "source/javascript") (:file "source/action-object")
  (:file "source/ajax") (:file "source/assembly")
  (:file "source/click-mode") (:file "source/inspector")
  (:file "source/object-tree") (:file "source/part-type-form")
  (:file "source/publish") (:file "source/viewport")))

