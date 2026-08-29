; Symbolic safety model for clients/browser/lifecycle.mjs.
; The executable checker imports the runtime reducer directly; this model adds
; proofs over an arbitrary positive worker pending limit.
(set-logic ALL)

(declare-datatypes () ((CPhase CStarting CReady CDraining CClosed CFailed)))
(declare-datatypes () ((CEvent
  CInitializeRequested
  CInitialized
  CInitializationFailed
  CRequestStarted
  CRequestSettled
  CCloseRequested
  CDrainCompleted
  CTerminate
  CFault)))

(define-fun CTerminal ((p CPhase)) Bool
  (or (= p CClosed) (= p CFailed)))

(define-fun CValid ((p CPhase) (pending Int) (limit Int)) Bool
  (and
    (> limit 0)
    (<= 0 pending)
    (<= pending limit)
    (=> (CTerminal p) (= pending 0))
    (=> (= p CStarting) (<= pending 1))))

(define-fun CNextPhase ((p CPhase) (pending Int) (limit Int) (event CEvent)) CPhase
  (ite (CTerminal p) p
  (ite (= event CTerminate) CClosed
  (ite (= event CFault) CFailed
  (ite (= event CInitializeRequested) p
  (ite (= event CInitialized)
    (ite (and (= p CStarting) (= pending 1)) CReady CFailed)
  (ite (= event CInitializationFailed) CFailed
  (ite (= event CRequestStarted) p
  (ite (= event CRequestSettled)
    (ite (and (or (= p CReady) (= p CDraining)) (> pending 0)) p CFailed)
  (ite (= event CCloseRequested)
    (ite (= p CReady) CDraining p)
  (ite (= event CDrainCompleted)
    (ite (and (= p CDraining) (= pending 0)) CClosed CFailed)
    CFailed)))))))))))

(define-fun CNextPending ((p CPhase) (pending Int) (limit Int) (event CEvent)) Int
  (ite (CTerminal p) 0
  (ite (or (= event CTerminate) (= event CFault)) 0
  (ite (= event CInitializeRequested)
    (ite (and (= p CStarting) (= pending 0)) 1 pending)
  (ite (or (= event CInitialized) (= event CInitializationFailed)) 0
  (ite (= event CRequestStarted)
    (ite (and (= p CReady) (< pending limit)) (+ pending 1) pending)
  (ite (= event CRequestSettled)
    (ite (and (or (= p CReady) (= p CDraining)) (> pending 0)) (- pending 1) 0)
  (ite (= event CCloseRequested) pending
  (ite (= event CDrainCompleted) 0
    0)))))))))

(define-fun CAccepted ((p CPhase) (pending Int) (limit Int) (event CEvent)) Bool
  (ite (CTerminal p)
    (or
      (and (= p CClosed) (= event CTerminate))
      (and (= p CFailed) (= event CFault)))
  (ite (or (= event CTerminate) (= event CFault)) true
  (ite (= event CInitializeRequested)
    (and (= p CStarting) (= pending 0))
  (ite (= event CInitialized)
    (and (= p CStarting) (= pending 1))
  (ite (= event CInitializationFailed)
    (and (= p CStarting) (= pending 1))
  (ite (= event CRequestStarted)
    (and (= p CReady) (< pending limit))
  (ite (= event CRequestSettled)
    (and (or (= p CReady) (= p CDraining)) (> pending 0))
  (ite (= event CCloseRequested)
    (or (= p CReady) (= p CDraining))
  (ite (= event CDrainCompleted)
    (and (= p CDraining) (= pending 0))
    false))))))))))

(declare-const cp CPhase)
(declare-const ce CEvent)
(declare-const pending Int)
(declare-const limit Int)

; Every transition preserves the worker-client state invariant.
(push)
(assert (CValid cp pending limit))
(assert (not (CValid
  (CNextPhase cp pending limit ce)
  (CNextPending cp pending limit ce)
  limit)))
(check-sat)
(pop)

; Closed and failed are absorbing and cannot retain pending requests.
(push)
(assert (CValid cp pending limit))
(assert (CTerminal cp))
(assert (or
  (not (= (CNextPhase cp pending limit ce) cp))
  (not (= (CNextPending cp pending limit ce) 0))))
(check-sat)
(pop)

; Work is accepted exactly while ready and below the configured bound.
(push)
(assert (CValid cp pending limit))
(assert (= ce CRequestStarted))
(assert (not (=
  (CAccepted cp pending limit ce)
  (and (= cp CReady) (< pending limit)))))
(check-sat)
(pop)

; Accepted work increments the rank by one and cannot change phase.
(push)
(assert (CValid cp pending limit))
(assert (= ce CRequestStarted))
(assert (CAccepted cp pending limit ce))
(assert (or
  (not (= (CNextPhase cp pending limit ce) CReady))
  (not (= (CNextPending cp pending limit ce) (+ pending 1)))))
(check-sat)
(pop)

; Every accepted settlement lowers pending work by one.
(push)
(assert (CValid cp pending limit))
(assert (= ce CRequestSettled))
(assert (CAccepted cp pending limit ce))
(assert (not (= (CNextPending cp pending limit ce) (- pending 1))))
(check-sat)
(pop)

; Draining is monotonic: no event can reopen ready or starting.
(push)
(assert (CValid cp pending limit))
(assert (= cp CDraining))
(assert (or
  (= (CNextPhase cp pending limit ce) CReady)
  (= (CNextPhase cp pending limit ce) CStarting)))
(check-sat)
(pop)

; Drain completion is accepted exactly at rank zero and then closes.
(push)
(assert (CValid cp pending limit))
(assert (= ce CDrainCompleted))
(assert (CAccepted cp pending limit ce))
(assert (or
  (not (= cp CDraining))
  (not (= pending 0))
  (not (= (CNextPhase cp pending limit ce) CClosed))))
(check-sat)
(pop)

; Fault and terminate clear all work and enter a controlled terminal phase.
(push)
(assert (CValid cp pending limit))
(assert (not (CTerminal cp)))
(assert (= ce CFault))
(assert (or
  (not (= (CNextPhase cp pending limit ce) CFailed))
  (not (= (CNextPending cp pending limit ce) 0))
  (not (CAccepted cp pending limit ce))))
(check-sat)
(pop)

(push)
(assert (CValid cp pending limit))
(assert (not (CTerminal cp)))
(assert (= ce CTerminate))
(assert (or
  (not (= (CNextPhase cp pending limit ce) CClosed))
  (not (= (CNextPending cp pending limit ce) 0))
  (not (CAccepted cp pending limit ce))))
(check-sat)
(pop)

(declare-datatypes () ((MPhase MInitializing MReady MCalling MFailed)))
(declare-datatypes () ((MEvent MInitialized MInitializationFailed MCallStarted MCallSettled MFault)))

(define-fun MNext ((p MPhase) (event MEvent)) MPhase
  (ite (= p MFailed) MFailed
  (ite (= event MFault) MFailed
  (ite (= event MInitialized)
    (ite (= p MInitializing) MReady MFailed)
  (ite (= event MInitializationFailed) MFailed
  (ite (= event MCallStarted)
    (ite (= p MReady) MCalling (ite (= p MCalling) MCalling MFailed))
  (ite (= event MCallSettled)
    (ite (= p MCalling) MReady MFailed)
    MFailed)))))))

(define-fun MAccepted ((p MPhase) (event MEvent)) Bool
  (ite (= p MFailed) (= event MFault)
  (ite (= event MFault) true
  (ite (= event MInitialized) (= p MInitializing)
  (ite (= event MInitializationFailed) (= p MInitializing)
  (ite (= event MCallStarted) (= p MReady)
  (ite (= event MCallSettled) (= p MCalling)
    false)))))))

(declare-const mp MPhase)
(declare-const me MEvent)

; Main-thread calls can start only from ready.
(push)
(assert (= me MCallStarted))
(assert (not (= (MAccepted mp me) (= mp MReady))))
(check-sat)
(pop)

; A rejected reentrant call stutters instead of corrupting the outer call.
(push)
(assert (= mp MCalling))
(assert (= me MCallStarted))
(assert (or (MAccepted mp me) (not (= (MNext mp me) MCalling))))
(check-sat)
(pop)

; Main-thread failure is absorbing.
(push)
(assert (= mp MFailed))
(assert (not (= (MNext mp me) MFailed)))
(check-sat)
(pop)

(declare-datatypes () ((HPhase HUninitialized HInitializing HReady HFailed)))
(declare-datatypes () ((HEvent HInitializeRequested HInitialized HInitializationFailed HCallRequested HFault)))

(define-fun HNext ((p HPhase) (event HEvent)) HPhase
  (ite (= p HFailed) HFailed
  (ite (= event HFault) HFailed
  (ite (= event HInitializeRequested)
    (ite (= p HUninitialized) HInitializing p)
  (ite (= event HInitialized)
    (ite (= p HInitializing) HReady HFailed)
  (ite (= event HInitializationFailed) HFailed
  (ite (= event HCallRequested) p
    HFailed)))))))

(define-fun HAccepted ((p HPhase) (event HEvent)) Bool
  (ite (= p HFailed) (= event HFault)
  (ite (= event HFault) true
  (ite (= event HInitializeRequested) (= p HUninitialized)
  (ite (= event HInitialized) (= p HInitializing)
  (ite (= event HInitializationFailed) (= p HInitializing)
  (ite (= event HCallRequested) (= p HReady)
    false)))))))

(declare-const hp HPhase)
(declare-const he HEvent)

; Worker-host methods can execute only after one successful initialization.
(push)
(assert (= he HCallRequested))
(assert (not (= (HAccepted hp he) (= hp HReady))))
(check-sat)
(pop)

; Duplicate initialization requests are rejected without reopening the host.
(push)
(assert (= he HInitializeRequested))
(assert (not (= hp HUninitialized)))
(assert (or (HAccepted hp he) (not (= (HNext hp he) hp))))
(check-sat)
(pop)

; Worker-host failure is absorbing.
(push)
(assert (= hp HFailed))
(assert (not (= (HNext hp he) HFailed)))
(check-sat)
(pop)

(declare-datatypes () ((DPhase DInitializing DReady DFailed)))
(declare-datatypes () ((DEvent DInitialized DInitializationFailed)))

(define-fun DNext ((p DPhase) (event DEvent)) DPhase
  (ite (= p DFailed) DFailed
  (ite (= p DInitializing)
    (ite (= event DInitialized) DReady DFailed)
    DFailed)))

(define-fun DAccepted ((p DPhase) (event DEvent)) Bool
  (= p DInitializing))

(declare-const dp DPhase)
(declare-const de DEvent)

; The demo reaches ready only through successful initialization.
(push)
(assert (= (DNext dp de) DReady))
(assert (or (not (= dp DInitializing)) (not (= de DInitialized))))
(check-sat)
(pop)

; Demo failure is absorbing.
(push)
(assert (= dp DFailed))
(assert (not (= (DNext dp de) DFailed)))
(check-sat)
(pop)
