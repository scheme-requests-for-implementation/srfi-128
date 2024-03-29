;;; SPDX-License-Identifier: MIT
;;;
;;; Copyright (C) John Cowan (2015). All Rights Reserved.
;;; 
;;; Permission is hereby granted, free of charge, to any person
;;; obtaining a copy of this software and associated documentation
;;; files (the "Software"), to deal in the Software without
;;; restriction, including without limitation the rights to use,
;;; copy, modify, merge, publish, distribute, sublicense, and/or
;;; sell copies of the Software, and to permit persons to whom the
;;; Software is furnished to do so, subject to the following
;;; conditions:
;;; 
;;; The above copyright notice and this permission notice shall be
;;; included in all copies or substantial portions of the Software.
;;; 
;;; THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
;;; EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES
;;; OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
;;; NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT
;;; HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
;;; WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
;;; FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
;;; OTHER DEALINGS IN THE SOFTWARE. 

(import (scheme base)
        (scheme cxr)
        (scheme write)
        (scheme file)
        (scheme process-context)
        (scheme inexact)
        (scheme complex)
        (rnrs conditions)
        (rnrs records syntactic)
;       (srfi 116)
        (srfi 128))

;;; Uses "the Chicken test egg, which is provided on Chibi as
;;; the (chibi test) library."  So we have to fake that here.
;;;
;;; The Chicken test egg appears to be documented at
;;; http://wiki.call-cc.org/eggref/4/test

#|
(use test)
(use comparators)
(load "r7rs-shim.scm")
|#

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;
;;; This stuff was copied from test/R7RS/Lib/tests/scheme/test.sld
;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;;; Good enough for this file.

(define (for-all f xs . others)
  (cond ((null? xs)
	 #t)
	((apply f (car xs) (map car others))
	 (apply for-all f (cdr xs) (map cdr others)))
	(else
	 #f)))

(define (exists f xs . others)
  (cond ((null? xs)
	 #f)
	((apply f (car xs) (map car others))
	 #t)
	(else
	 (apply exists f (cdr xs) (map cdr others)))))

(define (get-string-n p n)
  (let loop ((chars '())
	     (i 0))
    (if (= i n)
	(list->string (reverse chars))
	(let ((c (read-char p)))
	  (if (char? c)
	      (loop (cons c chars)
		    (+ i 1))
	      (loop chars n))))))

(define-record-type err
  (make-err err-c)
  err?
  (err-c err-err-c))

(define-record-type expected-exception
  (make-expected-exception)
  expected-exception?)

(define-record-type multiple-results
  (make-multiple-results values)
  multiple-results?
  (values multiple-results-values))

(define-record-type approx
  (make-approx value)
  approx?
  (value approx-value))

(define-record-type alts (make-alts values) alts?
  (values alts-values))

(define-syntax larceny:test    ; FIXME: renamed
  (syntax-rules ()
    ((_ expr expected)
     (begin
       ;; (write 'expr) (newline)
       (run-test 'expr
		 (catch-exns (lambda () expr))
		 expected)))))

(define (catch-exns thunk)
  (guard (c (#t (make-err c)))
	 (call-with-values thunk
	   (lambda x
	     (if (= 1 (length x))
		 (car x)
		 (make-multiple-results x))))))

(define-syntax test/approx
  (syntax-rules ()
    ((_ expr expected)
     (run-test 'expr
	       (make-approx expr)
	       (make-approx expected)))))

(define-syntax test/alts
  (syntax-rules ()
    ((_ expr expected0 expected ...)
     (run-test 'expr
	       expr
	       (make-alts (list expected0 expected ...))))))

(define (good-enough? x y)
  ;; relative error should be with 0.1%, but greater
  ;; relative error is allowed when the expected value
  ;; is near zero.
  (cond ((not (number? x)) #f)
	((not (number? y)) #f)
	((or (not (real? x))
	     (not (real? y)))
	 (and (good-enough? (real-part x) (real-part y))
	      (good-enough? (imag-part x) (imag-part y))))
	((infinite? x)
	 (= x (* 2.0 y)))
	((infinite? y)
	 (= (* 2.0 x) y))
	((nan? y)
	 (nan? x))
	((> (magnitude y) 1e-6)
	 (< (/ (magnitude (- x y))
	       (magnitude y))
	    1e-3))
	(else
	 (< (magnitude (- x y)) 1e-6))))

;; FIXME

(define-syntax test/exn
  (syntax-rules ()
    ((_ expr condition)
     (test (guard (c (((condition-predicate
			(record-type-descriptor condition)) c)
		      (make-expected-exception)))
		  expr)
	   (make-expected-exception)))))

(define-syntax test/values
  (syntax-rules ()
    ((_ expr val ...)
     (run-test 'expr
	       (catch-exns (lambda () expr))
	       (make-multiple-results (list val ...))))))

(define-syntax test/output
  (syntax-rules ()
    ((_ expr expected str)
     (run-test 'expr
	       (capture-output
		(lambda ()
		  (run-test 'expr
			    (guard (c (#t (make-err c)))
				   expr)
			    expected)))
	       str))))

(define-syntax test/unspec
  (syntax-rules ()
    ((_ expr)
     (test (begin expr 'unspec) 'unspec))))

;; FIXME

(define-syntax test/unspec-or-exn
  (syntax-rules ()
    ((_ expr condition)
     (test (guard (c (((condition-predicate
			(record-type-descriptor condition)) c)
		      'unspec))
		  (begin expr 'unspec))
	   'unspec))))

;; FIXME

(define-syntax test/unspec-flonum-or-exn
  (syntax-rules ()
    ((_ expr condition)
     (test (guard (c (((condition-predicate
			(record-type-descriptor condition)) c)
		      'unspec-or-flonum))
		  (let ((v expr))
		    (if (flonum? v)
			'unspec-or-flonum
			(if (eq? v 'unspec-or-flonum)
			    (list v)
			    v))))
	   'unspec-or-flonum))))

(define-syntax test/output/unspec
  (syntax-rules ()
    ((_ expr str)
     (test/output (begin expr 'unspec) 'unspec str))))

(define checked 0)
(define failures '())

(define (capture-output thunk)
  (if (file-exists? "tmp-catch-out")
      (delete-file "tmp-catch-out"))
  (dynamic-wind
      (lambda () 'nothing)
      (lambda ()
        (with-output-to-file "tmp-catch-out"
	  thunk)
        (call-with-input-file "tmp-catch-out"
	  (lambda (p)
	    (get-string-n p 1024))))
      (lambda ()
        (if (file-exists? "tmp-catch-out")
            (delete-file "tmp-catch-out")))))

(define (same-result? got expected)
  (cond
   ((and (real? expected) (nan? expected))
    (and (real? got) (nan? got)))
   ((expected-exception? expected)
    (expected-exception? got))
   ((approx? expected)
    (and (approx? got)
	 (good-enough? (approx-value expected)
		       (approx-value got))))
   ((multiple-results? expected)
    (and (multiple-results? got)
	 (= (length (multiple-results-values expected))
	    (length (multiple-results-values got)))
	 (for-all same-result?
		  (multiple-results-values expected)
		  (multiple-results-values got))))
   ((alts? expected)
    (exists (lambda (e) (same-result? got e))
	    (alts-values expected)))
   (else
    ;(equal? got expected))))
    ((current-test-comparator)
     got expected))))

(define (run-test expr got expected)
  (set! checked (+ 1 checked))
  (unless (same-result? got expected)
	  (set! failures
		(cons (list expr got expected)
		      failures))))

(define (write-result prefix v)
  (cond
   ((multiple-results? v)
    (for-each (lambda (v)
		(write-result prefix v))
	      (multiple-results-values v)))
   ((approx? v)
    (display prefix)
    (display "approximately ")
    (write (approx-value v)))
   ((alts? v)
    (write-result (string-append prefix "   ")
		  (car (alts-values v)))
    (for-each (lambda (v)
		(write-result (string-append prefix "OR ")
			      v))
	      (cdr (alts-values v))))
   (else
    (display prefix)
    (write v))))

(define (report-test-results)
  (if (null? failures)
      (begin
	(display checked)
	(display " tests passed\n"))
      (begin
	(display (length failures))
	(display " tests failed:\n\n")
	(for-each (lambda (t)
		    (display "Expression:\n ")
		    (write (car t))
		    (display "\nResult:")
		    (write-result "\n " (cadr t))
		    (display "\nExpected:")
		    (write-result "\n " (caddr t))
		    (display "\n\n"))
		  (reverse failures))
	(display (length failures))
	(display " of ")
	(display checked)
	(display " tests failed.\n"))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;
;;; End of stuff copied from test/R7RS/Lib/tests/scheme/test.sld
;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(define (iequal? x y)
  (cond #;
        ((and (ipair? x) (ipair? y))
         (and (iequal? (icar x) (icar y))
              (iequal? (icdr x) (icdr y))))
        ((and (pair? x) (pair? y))
         (and (iequal? (car x) (car y))
              (iequal? (cdr x) (cdr y))))
        ((and (vector? x)
              (vector? y))
         (iequal? (vector->list x) (vector->list y)))
        (else
         (equal? x y))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;
;;; Definitions that fake part of the Chicken test egg.
;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(define-syntax test-group
  (syntax-rules ()
   ((_ name expr)
    expr)
   ((_ name expr-or-defn stuff ...)
    (let ()
      expr-or-defn
      (test-group name stuff ...)))))

(define-syntax test
  (syntax-rules ()
   ((_ name expected actual)
    (begin
     ;; (write 'actual) (newline)
     (run-test '(begin name actual)
               (catch-exns (lambda () actual))
               expected)))
   ((_ expected actual)
    (test 'anonymous expected actual))))

(define-syntax test-assert
  (syntax-rules ()
   ((_ name expr)
    (parameterize ((current-test-comparator iequal?))
     (test name #t (and expr #t))))
   ((_ expr)
    (test-assert 'anonymous expr))))

(define-syntax test-deny
  (syntax-rules ()
   ((_ name expr)
    (parameterize ((current-test-comparator iequal?))
     (test name #t (and (not expr) #t))))
   ((_ expr)
    (test-deny 'anonymous expr))))

(define-syntax test-error
  (syntax-rules ()
   ((_ name expr)
    (test/exn expr &condition))
   ((_ expr)
    (test-error 'anonymous expr))))

(define-syntax test-end
  (syntax-rules ()
   ((_ name)
    (begin (report-test-results)
           (display "Done.")
           (newline)))
   ((_)
    (test-end 'anonymous))))

(define (test-exit . rest)
  (let ((error-status (if (null? rest) 1 (car rest))))
    (if (null? failures)
        (exit)
        (exit error-status))))        

(define current-test-comparator
  (make-parameter iequal?))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;
;;; End of definitions faking part of the Chicken test egg.
;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(define (print x) (display x) (newline))

(test-group "comparators"

  (define (vector-cdr vec)
    (let* ((len (vector-length vec))
           (result (make-vector (- len 1))))
      (let loop ((n 1))
        (cond
          ((= n len) result)
          (else (vector-set! result (- n 1) (vector-ref vec n))
                (loop (+ n 1)))))))

  (test '#(2 3 4) (vector-cdr '#(1 2 3 4)))
  (test '#() (vector-cdr '#(1)))

  (print "default-comparator")
  (define default-comparator (make-default-comparator))
  (print "real-comparator")
  (define real-comparator (make-comparator real? = < number-hash))
  (print "degenerate comparator")
  (define degenerate-comparator (make-comparator (lambda (x) #t) equal? #f #f))
  (print "boolean comparator")
  (define boolean-comparator
    (make-comparator boolean? eq? (lambda (x y) (and (not x) y)) boolean-hash))
  (print "bool-pair-comparator")
  (define bool-pair-comparator (make-pair-comparator boolean-comparator boolean-comparator))
  (print "num-list-comparator")
  (define num-list-comparator
    (make-list-comparator real-comparator list? null? car cdr))
  (print "num-vector-comparator")
  (define num-vector-comparator
    (make-vector-comparator real-comparator vector? vector-length vector-ref))
  (print "vector-qua-list comparator")
  (define vector-qua-list-comparator
    (make-list-comparator
      real-comparator
      vector?
      (lambda (vec) (= 0 (vector-length vec)))
      (lambda (vec) (vector-ref vec 0))
      vector-cdr))
  (print "list-qua-vector-comparator")
  (define list-qua-vector-comparator
     (make-vector-comparator default-comparator list? length list-ref))
  (print "eq-comparator")
  (define eq-comparator (make-eq-comparator))
  (print "eqv-comparator")
  (define eqv-comparator (make-eqv-comparator))
  (print "equal-comparator")
  (define equal-comparator (make-equal-comparator))
  (print "symbol-comparator")
  (define symbol-comparator
    (make-comparator
      symbol?
      eq?
      (lambda (a b) (string<? (symbol->string a) (symbol->string b)))
      symbol-hash))

  (test-group "comparators/predicates"
    (test-assert (comparator? real-comparator))
    (test-assert (not (comparator? =)))
    (test-assert (comparator-ordered? real-comparator))
    (test-assert (comparator-hashable? real-comparator))
    (test-assert (not (comparator-ordered? degenerate-comparator)))
    (test-assert (not (comparator-hashable? degenerate-comparator)))
  ) ; end comparators/predicates

  (test-group "comparators/constructors"
    (test-assert (=? boolean-comparator #t #t))
    (test-assert (not (=? boolean-comparator #t #f)))
    (test-assert (<? boolean-comparator #f #t))
    (test-assert (not (<? boolean-comparator #t #t)))
    (test-assert (not (<? boolean-comparator #t #f)))

    (test-assert (comparator-test-type bool-pair-comparator '(#t . #f)))
    (test-assert (not (comparator-test-type bool-pair-comparator 32)))
    (test-assert (not (comparator-test-type bool-pair-comparator '(32 . #f))))
    (test-assert (not (comparator-test-type bool-pair-comparator '(#t . 32))))
    (test-assert (not (comparator-test-type bool-pair-comparator '(32 . 34))))
    (test-assert (=? bool-pair-comparator '(#t . #t) '(#t . #t)))
    (test-assert (not (=? bool-pair-comparator '(#t . #t) '(#f . #t))))
    (test-assert (not (=? bool-pair-comparator '(#t . #t) '(#t . #f))))
    (test-assert (<? bool-pair-comparator '(#f . #t) '(#t . #t)))
    (test-assert (<? bool-pair-comparator '(#t . #f) '(#t . #t)))
    (test-assert (not (<? bool-pair-comparator '(#t . #t) '(#t . #t))))
    (test-assert (not (<? bool-pair-comparator '(#t . #t) '(#f . #t))))
    (test-assert (not (<? bool-pair-comparator '(#f . #t) '(#f . #f))))

    (test-assert (comparator-test-type num-vector-comparator '#(1 2 3)))
    (test-assert (comparator-test-type num-vector-comparator '#()))
    (test-assert (not (comparator-test-type num-vector-comparator 1)))
    (test-assert (not (comparator-test-type num-vector-comparator '#(a 2 3))))
    (test-assert (not (comparator-test-type num-vector-comparator '#(1 b 3))))
    (test-assert (not (comparator-test-type num-vector-comparator '#(1 2 c))))
    (test-assert (=? num-vector-comparator '#(1 2 3) '#(1 2 3)))
    (test-assert (not (=? num-vector-comparator '#(1 2 3) '#(4 5 6))))
    (test-assert (not (=? num-vector-comparator '#(1 2 3) '#(1 5 6))))
    (test-assert (not (=? num-vector-comparator '#(1 2 3) '#(1 2 6))))
    (test-assert (<? num-vector-comparator '#(1 2) '#(1 2 3)))
    (test-assert (<? num-vector-comparator '#(1 2 3) '#(2 3 4)))
    (test-assert (<? num-vector-comparator '#(1 2 3) '#(1 3 4)))
    (test-assert (<? num-vector-comparator '#(1 2 3) '#(1 2 4)))
    (test-assert (<? num-vector-comparator '#(3 4) '#(1 2 3)))
    (test-assert (not (<? num-vector-comparator '#(1 2 3) '#(1 2 3))))
    (test-assert (not (<? num-vector-comparator '#(1 2 3) '#(1 2))))
    (test-assert (not (<? num-vector-comparator '#(1 2 3) '#(0 2 3))))
    (test-assert (not (<? num-vector-comparator '#(1 2 3) '#(1 1 3))))

    (test-assert (not (<? vector-qua-list-comparator '#(3 4) '#(1 2 3))))
    (test-assert (<? list-qua-vector-comparator '(3 4) '(1 2 3)))

    (define bool-pair (cons #t #f))
    (define bool-pair-2 (cons #t #f))
    (define reverse-bool-pair (cons #f #t))
    (test-assert (=? eq-comparator #t #t))
    (test-assert (not (=? eq-comparator #f #t)))
    (test-assert (=? eqv-comparator bool-pair bool-pair))
    (test-assert (not (=? eqv-comparator bool-pair bool-pair-2)))
    (test-assert (=? equal-comparator bool-pair bool-pair-2))
    (test-assert (not (=? equal-comparator bool-pair reverse-bool-pair)))
  ) ; end comparators/constructors

  (test-group "comparators/hash"
    (test-assert (exact-integer? (boolean-hash #f)))
    (test-assert (not (negative? (boolean-hash #t))))
    (test-assert (exact-integer? (char-hash #\a)))
    (test-assert (not (negative? (char-hash #\b))))
    (test-assert (exact-integer? (char-ci-hash #\a)))
    (test-assert (not (negative? (char-ci-hash #\b))))
    (test-assert (= (char-ci-hash #\a) (char-ci-hash #\A)))
    (test-assert (exact-integer? (string-hash "f")))
    (test-assert (not (negative? (string-hash "g"))))
    (test-assert (exact-integer? (string-ci-hash "f")))
    (test-assert (not (negative? (string-ci-hash "g"))))
    (test-assert (= (string-ci-hash "f") (string-ci-hash "F")))
    (test-assert (exact-integer? (symbol-hash 'f)))
    (test-assert (not (negative? (symbol-hash 't))))
    (test-assert (exact-integer? (number-hash 3)))
    (test-assert (not (negative? (number-hash 3))))
    (test-assert (exact-integer? (number-hash -3)))
    (test-assert (not (negative? (number-hash -3))))
    (test-assert (exact-integer? (number-hash 3.0)))
    (test-assert (not (negative? (number-hash 3.0))))
    (test-assert (exact-integer? (number-hash 3.47)))
    (test-assert (not (negative? (number-hash 3.47))))
    (test-assert (exact-integer? (default-hash '())))
    (test-assert (not (negative? (default-hash '()))))
    (test-assert (exact-integer? (default-hash '(a "b" #\c #(dee) 2.718))))
    (test-assert (not (negative? (default-hash '(a "b" #\c #(dee) 2.718)))))
    (test-assert (exact-integer? (default-hash '#u8())))
    (test-assert (not (negative? (default-hash '#u8()))))
    (test-assert (exact-integer? (default-hash '#u8(8 6 3))))
    (test-assert (not (negative? (default-hash '#u8(8 6 3)))))
    (test-assert (exact-integer? (default-hash '#())))
    (test-assert (not (negative? (default-hash '#()))))
    (test-assert (exact-integer? (default-hash '#(a "b" #\c #(dee) 2.718))))
    (test-assert (not (negative? (default-hash '#(a "b" #\c #(dee) 2.718)))))

  ) ; end comparators/hash

  (test-group "comparators/default"
    (test-assert (<? default-comparator '() '(a)))
    (test-assert (not (=? default-comparator '() '(a))))
    (test-assert (=? default-comparator #t #t))
    (test-assert (not (=? default-comparator #t #f)))
    (test-assert (<? default-comparator #f #t))
    (test-assert (not (<? default-comparator #t #t)))
    (test-assert (=? default-comparator #\a #\a))
    (test-assert (<? default-comparator #\a #\b))

    (test-assert (comparator-test-type default-comparator '()))
    (test-assert (comparator-test-type default-comparator #t))
    (test-assert (comparator-test-type default-comparator #\t))
    (test-assert (comparator-test-type default-comparator '(a)))
    (test-assert (comparator-test-type default-comparator 'a))
    (test-assert (comparator-test-type default-comparator (make-bytevector 10)))
    (test-assert (comparator-test-type default-comparator 10))
    (test-assert (comparator-test-type default-comparator 10.0))
    (test-assert (comparator-test-type default-comparator "10.0"))
    (test-assert (comparator-test-type default-comparator '#(10)))

    (test-assert (=? default-comparator '(#t . #t) '(#t . #t)))
    (test-assert (not (=? default-comparator '(#t . #t) '(#f . #t))))
    (test-assert (not (=? default-comparator '(#t . #t) '(#t . #f))))
    (test-assert (<? default-comparator '(#f . #t) '(#t . #t)))
    (test-assert (<? default-comparator '(#t . #f) '(#t . #t)))
    (test-assert (not (<? default-comparator '(#t . #t) '(#t . #t))))
    (test-assert (not (<? default-comparator '(#t . #t) '(#f . #t))))
    (test-assert (not (<? default-comparator '#(#f #t) '#(#f #f))))

    (test-assert (=? default-comparator '#(#t #t) '#(#t #t)))
    (test-assert (not (=? default-comparator '#(#t #t) '#(#f #t))))
    (test-assert (not (=? default-comparator '#(#t #t) '#(#t #f))))
    (test-assert (<? default-comparator '#(#f #t) '#(#t #t)))
    (test-assert (<? default-comparator '#(#t #f) '#(#t #t)))
    (test-assert (not (<? default-comparator '#(#t #t) '#(#t #t))))
    (test-assert (not (<? default-comparator '#(#t #t) '#(#f #t))))
    (test-assert (not (<? default-comparator '#(#f #t) '#(#f #f))))

    (test-assert (= (comparator-hash default-comparator #t) (boolean-hash #t)))
    (test-assert (= (comparator-hash default-comparator #\t) (char-hash #\t)))
    (test-assert (= (comparator-hash default-comparator "t") (string-hash "t")))
    (test-assert (= (comparator-hash default-comparator 't) (symbol-hash 't)))
    (test-assert (= (comparator-hash default-comparator 10) (number-hash 10)))
    (test-assert (= (comparator-hash default-comparator 10.0) (number-hash 10.0)))

    (comparator-register-default!
      (make-comparator procedure? (lambda (a b) #t) (lambda (a b) #f) (lambda (obj) 200)))
    (test-assert (=? default-comparator (lambda () #t) (lambda () #f)))
    (test-assert (not (<? default-comparator (lambda () #t) (lambda () #f))))
    (test 200 (comparator-hash default-comparator (lambda () #t)))

  ) ; end comparators/default

  ;; SRFI 128 does not actually require a comparator's four procedures
  ;; to be eq? to the procedures originally passed to make-comparator.
  ;; For interoperability/interchangeability between the comparators
  ;; of SRFI 114 and SRFI 128, some of the procedures passed to
  ;; make-comparator may need to be wrapped inside another lambda
  ;; expression before they're returned by the corresponding accessor.
  ;;
  ;; So this next group of tests is incorrect, hence commented out
  ;; and replaced by a slightly less naive group of tests.

#;
  (test-group "comparators/accessors"
    (define ttp (lambda (x) #t))
    (define eqp (lambda (x y) #t))
    (define orp (lambda (x y) #t))
    (define hf (lambda (x) 0))
    (define comp (make-comparator ttp eqp orp hf))
    (test ttp (comparator-type-test-predicate comp))
    (test eqp (comparator-equality-predicate comp))
    (test orp (comparator-ordering-predicate comp))
    (test hf (comparator-hash-function comp))
  ) ; end comparators/accessors

  (test-group "comparators/accessors"
    (define x1 0)
    (define x2 0)
    (define x3 0)
    (define x4 0)
    (define ttp (lambda (x) (set! x1 111) #t))
    (define eqp (lambda (x y) (set! x2 222) #t))
    (define orp (lambda (x y) (set! x3 333) #t))
    (define hf (lambda (x) (set! x4 444) 0))
    (define comp (make-comparator ttp eqp orp hf))
    (test #t (and ((comparator-type-test-predicate comp) x1)   (= x1 111)))
    (test #t (and ((comparator-equality-predicate comp) x1 x2) (= x2 222)))
    (test #t (and ((comparator-ordering-predicate comp) x1 x3) (= x3 333)))
    (test #t (and (zero? ((comparator-hash-function comp) x1)) (= x4 444)))
  ) ; end comparators/accessors

  (test-group "comparators/invokers"
    (test-assert (comparator-test-type real-comparator 3))
    (test-assert (comparator-test-type real-comparator 3.0))
    (test-assert (not (comparator-test-type real-comparator "3.0")))
    (test-assert (comparator-check-type boolean-comparator #t))
    (test-error (comparator-check-type boolean-comparator 't))
  ) ; end comparators/invokers

  (test-group "comparators/comparison"
    (test-assert (=? real-comparator 2 2.0 2))
    (test-assert (<? real-comparator 2 3.0 4))
    (test-assert (>? real-comparator 4.0 3.0 2))
    (test-assert (<=? real-comparator 2.0 2 3.0))
    (test-assert (>=? real-comparator 3 3.0 2))
    (test-assert (not (=? real-comparator 1 2 3)))
    (test-assert (not (<? real-comparator 3 1 2)))
    (test-assert (not (>? real-comparator 1 2 3)))
    (test-assert (not (<=? real-comparator 4 3 3)))
    (test-assert (not (>=? real-comparator 3 4 4.0)))

  ) ; end comparators/comparison

  (test-group "comparators/syntax"
    (test 'less (comparator-if<=> real-comparator 1 2 'less 'equal 'greater))
    (test 'equal (comparator-if<=> real-comparator 1 1 'less 'equal 'greater))
    (test 'greater (comparator-if<=> real-comparator 2 1 'less 'equal 'greater))
    (test 'less (comparator-if<=> "1" "2" 'less 'equal 'greater))
    (test 'equal (comparator-if<=> "1" "1" 'less 'equal 'greater))
    (test 'greater (comparator-if<=> "2" "1" 'less 'equal 'greater))

  ) ; end comparators/syntax

  (test-group "comparators/bound-salt"
    (test-assert (exact-integer? (hash-bound)))
    (test-assert (exact-integer? (hash-salt)))
    (test-assert (< (hash-salt) (hash-bound)))
#;  (test (hash-salt) (fake-salt-hash #t))  ; no such thing as fake-salt-hash
  ) ; end comparators/bound-salt

) ; end comparators

(test-end)

(test-exit)
