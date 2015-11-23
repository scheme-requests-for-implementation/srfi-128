(define-library comparators
  (import (scheme base))
  (import (scheme case-lambda))
  (export comparator? comparator-ordered? comparator-hashable?)
  (export make-comparator
          make-pair-comparator make-list-comparator make-vector-comparator
          make-eq-comparator make-eqv-comparator make-equal-comparator)
  (export boolean-hash char-hash char-ci-hash
          string-hash string-ci-hash symbol-hash number-hash)
  (export make-default-comparator default-hash comparator-register-default!)
  (export comparator-test-type comparator-check-type comparator-hash)
  (export =? <? >? <=? >=?)
  (export comparator-if<=>)
  (include "comparators-impl.scm")
  (include "default.scm")
)
