(set-logic QF_LIA)

; Machine-checked mirror of the borrow checker's ownership state machine
; (tools/borrow-checker/borrow_check.py). States, transitions, and the
; flagging predicate below must stay transition-for-transition identical to
; the Python implementation; the proofs establish that the machine as
; implemented cannot let a segfault-class event trace through unflagged.
;
; Event vocabulary (abstraction of the Python analyzer's actions):
;   alloc          x = allocator(...)        -> maybe-null
;   refine         null-check passed         maybe-null -> owned
;   free           f2e_free(x) / taker call  -> freed
;   use            deref / read / pass       state unchanged
;   assign-null    x = NULL                  -> null
;   move           return x / store x        -> moved
;   scope-end      x leaves scope            state unchanged (leak check)
;
; Conditional transfers (realloc's argument, may-take callees) blur the
; variable to the untracked `unknown` state in the Python analyzer; from
; that point it makes no claims, so `unknown` participates in joins here
; but no trace event models it. The theorems quantify over tracked
; variables, matching what the checker actually promises.

; States
(define-fun st_uninit () Int 0)
(define-fun st_null () Int 1)
(define-fun st_maybe_null () Int 2)
(define-fun st_owned () Int 3)
(define-fun st_borrowed () Int 4)
(define-fun st_freed () Int 5)
(define-fun st_moved () Int 6)
(define-fun st_unknown () Int 7)
(define-fun valid_state ((s Int)) Bool (and (>= s 0) (<= s 7)))

; Events
(define-fun ev_alloc () Int 0)
(define-fun ev_refine () Int 1)
(define-fun ev_free () Int 2)
(define-fun ev_use () Int 3)
(define-fun ev_assign_null () Int 4)
(define-fun ev_move () Int 5)
(define-fun ev_scope_end () Int 6)
(define-fun valid_event ((e Int)) Bool (and (>= e 0) (<= e 6)))

; Transition function: mirrors Analyzer.assign / eval_call / refinement.
(define-fun step ((s Int) (e Int)) Int
  (ite (= e ev_alloc) st_maybe_null
  (ite (= e ev_refine)
       (ite (= s st_maybe_null) st_owned
       (ite (= s st_null) st_unknown s))
  (ite (= e ev_free) st_freed
  (ite (= e ev_use) s
  (ite (= e ev_assign_null) st_null
  (ite (= e ev_move)
       (ite (or (= s st_owned) (= s st_maybe_null)) st_moved s)
       s)))))))

; Flagging predicate: mirrors every Analyzer.report call site.
(define-fun flags ((s Int) (e Int)) Bool
  (or
    ; double-free / use-after-free on a released pointer
    (and (= s st_freed) (or (= e ev_free) (= e ev_use) (= e ev_move)))
    ; freeing a borrowed (public-ABI undeclared) pointer
    (and (= s st_borrowed) (= e ev_free))
    ; dereferencing an unchecked or definitely-null pointer
    (and (or (= s st_maybe_null) (= s st_null)) (= e ev_use))
    ; overwrite-leak: reallocating over a still-owned pointer
    (and (or (= s st_owned) (= s st_maybe_null))
         (or (= e ev_alloc) (= e ev_assign_null)))
    ; leak: owned at scope end
    (and (or (= s st_owned) (= s st_maybe_null)) (= e ev_scope_end))))

; Join: mirrors the JOIN table (branch-merge lattice), default st_unknown.
(define-fun join2 ((a Int) (b Int)) Int
  (ite (= a b) a
  (ite (or (and (= a st_freed)
                (or (= b st_null) (= b st_owned)
                    (= b st_maybe_null) (= b st_moved)))
           (and (= b st_freed)
                (or (= a st_null) (= a st_owned)
                    (= a st_maybe_null) (= a st_moved))))
       st_freed
  (ite (or (and (= a st_moved)
                (or (= b st_owned) (= b st_maybe_null) (= b st_null)))
           (and (= b st_moved)
                (or (= a st_owned) (= a st_maybe_null) (= a st_null))))
       st_moved
  (ite (or (and (= a st_null) (or (= b st_owned) (= b st_maybe_null)))
           (and (= b st_null) (or (= a st_owned) (= a st_maybe_null)))
           (and (= a st_owned) (= b st_maybe_null))
           (and (= b st_owned) (= a st_maybe_null)))
       st_maybe_null
       st_unknown)))))

; --- Lemma: a free is never lost. After any free the state is freed, and
; both a second free and any use of a freed pointer are flagged.
(declare-const s0 Int)
(push)
(assert (valid_state s0))
(assert (or (not (= (step s0 ev_free) st_freed))
            (not (flags (step s0 ev_free) ev_free))
            (not (flags (step s0 ev_free) ev_use))))
(check-sat)
(pop)

; --- Lemma: an allocation is unusable until refined. Dereferencing the
; result of step(alloc) without a null check is always flagged.
(push)
(assert (valid_state s0))
(assert (not (flags (step s0 ev_alloc) ev_use)))
(check-sat)
(pop)

; --- Lemma: the canonical contract never flags.
; alloc; refine; use; free; assign-null; scope-end from an uninitialized
; variable raises no diagnostic at any step.
(define-fun g1 () Int (step st_uninit ev_alloc))
(define-fun g2 () Int (step g1 ev_refine))
(define-fun g3 () Int (step g2 ev_use))
(define-fun g4 () Int (step g3 ev_free))
(define-fun g5 () Int (step g4 ev_assign_null))
(push)
(assert (or (flags st_uninit ev_alloc)
            (flags g1 ev_refine)
            (flags g2 ev_use)
            (flags g3 ev_free)
            (flags g4 ev_assign_null)
            (flags g5 ev_scope_end)))
(check-sat)
(pop)

; --- Lemma: join is commutative over the whole lattice.
(declare-const ja Int)
(declare-const jb Int)
(push)
(assert (and (valid_state ja) (valid_state jb)))
(assert (not (= (join2 ja jb) (join2 jb ja))))
(check-sat)
(pop)

; --- Lemma: a conditional free is never forgotten by a merge. Joining
; freed with any state the analyzer can still track keeps freed.
(push)
(assert (and (valid_state jb)
             (or (= jb st_null) (= jb st_owned)
                 (= jb st_maybe_null) (= jb st_moved))))
(assert (not (= (join2 st_freed jb) st_freed)))
(check-sat)
(pop)

; --- Theorem: no unflagged use-after-free within bounded traces.
; For every 6-event trace from every valid start state: if some event is a
; free and a later event uses the variable with no re-initialization
; (alloc / assign-null) in between, then at least one step in the whole
; trace raises a flag. This is the machine-level "never segfaults" claim
; the borrow checker enforces per tracked variable.
(declare-const e1 Int)
(declare-const e2 Int)
(declare-const e3 Int)
(declare-const e4 Int)
(declare-const e5 Int)
(declare-const e6 Int)
(define-fun t0 () Int st_uninit)
(define-fun t1 () Int (step t0 e1))
(define-fun t2 () Int (step t1 e2))
(define-fun t3 () Int (step t2 e3))
(define-fun t4 () Int (step t3 e4))
(define-fun t5 () Int (step t4 e5))
(define-fun reinit ((e Int)) Bool (or (= e ev_alloc) (= e ev_assign_null)))
(define-fun uaf_pair ((ei Int) (ej Int)) Bool
  (and (= ei ev_free) (or (= ej ev_use) (= ej ev_free))))
(push)
(assert (and (valid_event e1) (valid_event e2) (valid_event e3)
             (valid_event e4) (valid_event e5) (valid_event e6)))
; the trace contains free ... use/free on the same variable, un-reinitialized
(assert (or
  (and (uaf_pair e1 e2))
  (and (uaf_pair e1 e3) (not (reinit e2)))
  (and (uaf_pair e1 e4) (not (reinit e2)) (not (reinit e3)))
  (and (uaf_pair e1 e5) (not (reinit e2)) (not (reinit e3))
       (not (reinit e4)))
  (and (uaf_pair e1 e6) (not (reinit e2)) (not (reinit e3))
       (not (reinit e4)) (not (reinit e5)))
  (and (uaf_pair e2 e3))
  (and (uaf_pair e2 e4) (not (reinit e3)))
  (and (uaf_pair e2 e5) (not (reinit e3)) (not (reinit e4)))
  (and (uaf_pair e2 e6) (not (reinit e3)) (not (reinit e4))
       (not (reinit e5)))
  (and (uaf_pair e3 e4))
  (and (uaf_pair e3 e5) (not (reinit e4)))
  (and (uaf_pair e3 e6) (not (reinit e4)) (not (reinit e5)))
  (and (uaf_pair e4 e5))
  (and (uaf_pair e4 e6) (not (reinit e5)))
  (and (uaf_pair e5 e6))))
; ... and the checker never flags anywhere: impossible.
(assert (not (or (flags t0 e1) (flags t1 e2) (flags t2 e3)
                 (flags t3 e4) (flags t4 e5) (flags t5 e6))))
(check-sat)
(pop)

; --- Vacuity witness for the theorem above, kept inside the all-unsat
; discipline: pin the concrete trace alloc; refine; free; use; use; move
; and prove it both satisfies the use-after-free condition and is flagged.
; If the condition (or the flagging) were unsatisfiable, this would be sat.
(push)
(assert (= e1 ev_alloc))
(assert (= e2 ev_refine))
(assert (= e3 ev_free))
(assert (= e4 ev_use))
(assert (= e5 ev_use))
(assert (= e6 ev_move))
(assert (not (and (uaf_pair e3 e4)
                  (flags t3 e4)
                  (= t3 st_freed))))
(check-sat)
(pop)
