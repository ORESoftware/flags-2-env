(set-logic QF_LIA)

; A known option and a reported unknown option are mutually exclusive.
(declare-const scanning Bool)
(declare-const known Bool)
(declare-const allow_unknown Bool)
(define-fun apply_known () Bool (and scanning known))
(define-fun report_unknown () Bool
  (and scanning (not known) (not allow_unknown)))
(push)
(assert (and apply_known report_unknown))
(check-sat)
(pop)

; Once `--` ends option scanning, no later token can mutate a known flag.
(declare-const end_of_options Bool)
(define-fun scanning_after () Bool (and scanning (not end_of_options)))
(push)
(assert (not scanning))
(assert scanning_after)
(check-sat)
(pop)

; Permissive mode never reports an unknown option.
(push)
(assert allow_unknown)
(assert report_unknown)
(check-sat)
(pop)

; The min/max helpers retain both inputs inside the resulting interval.
(declare-const a Int)
(declare-const b Int)
(define-fun minimum () Int (ite (< a b) a b))
(define-fun maximum () Int (ite (> a b) a b))
(push)
(assert (or (> minimum a)
            (> minimum b)
            (< maximum a)
            (< maximum b)))
(check-sat)
(pop)
