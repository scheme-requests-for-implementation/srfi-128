;;; SPDX-FileCopyrightText: 2015 John Cowan <cowan@ccil.org>
;;;
;;; SPDX-License-Identifier: MIT

(define-library (comparators)
  (import (scheme base))
  (import (scheme case-lambda))
  (import (scheme char) (scheme complex) (scheme inexact))
  (export comparator? comparator-ordered? comparator-hashable?)
  (export make-comparator
          make-pair-comparator make-list-comparator make-vector-comparator
          make-eq-comparator make-eqv-comparator make-equal-comparator)
  (export boolean-hash char-hash char-ci-hash
          string-hash string-ci-hash symbol-hash number-hash)
  (export make-default-comparator default-hash comparator-register-default!)
  (export comparator-type-test-predicate comparator-equality-predicate
        comparator-ordering-predicate comparator-hash-function)
  (export comparator-test-type comparator-check-type comparator-hash)
  (export hash-bound hash-salt)
  (export =? <? >? <=? >=?)
  (export comparator-if<=>)
  (include "comparators-impl.scm")
  (include "default.scm")
)
