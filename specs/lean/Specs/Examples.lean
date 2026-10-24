import Specs.Proofs
import Specs.Scenarios
import Specs.Traces
/-
# Non-vacuity witnesses (Rule 3: hypotheses of the headline theorems are satisfiable)

These are tests, not the claim. Each `example` shows that a hypothesis or antecedent used by a
headline theorem actually occurs in a reachable state, so the universal theorems in group C are
not vacuously true and `stuck_is_permanent` has a reachable premise.
-/

namespace Saga

/-- BR5's antecedent (form shown) is reachable in `ideal`. -/
example : ∃ s, replay idealCfg happyStart (bookItem .train ++ bookItem .flight ++ bookItem .hotel)
    = some s ∧ s.phase = .review ∧ (s.items .flight).status = .confirmed := by
  exact ⟨_, rfl, by decide, by decide⟩

/-- BR1/BR7 antecedent with a *positive* outcome: a fully booked confirmed end in `ideal`. -/
example : (replay idealCfg happyStart happyEvents).map (fun s => decide (s.phase = .ended ∧ fullyBooked s))
    = some true := by decide

/-- BR2's antecedent (canceled, back at Review / Ended) is reachable in `ideal`, and BR2 holds there. -/
example : (replay idealCfg ce1Start ce1Events).map
    (fun s => decide (s.userCanceled = true ∧ s.phase = .ended ∧ nothingBooked s)) = some true := by
  decide

/-- BR6's antecedent (a Canceled status) is reachable in `ideal`, and BR6 holds there. -/
example : (replay idealCfg ce1Start ce1Events).map
    (fun s => decide ((s.items .hotel).status = .canceled ∧ BR6 s)) = some true := by decide

/-- BR3/BR4 antecedents: a reachable booking is held (`ever ≠ []`, `active.length = 1`). -/
example : (replay asIsCfg ce5Start (bookItem .flight)).map
    (fun s => decide ((s.items .flight).ever ≠ [] ∧ (s.items .flight).active.length = 1)) = some true := by
  decide

/-- BR8 / `stuck_is_permanent` premise: a reachable stuck-holding state exists (`bookFailure`). -/
example : (replay bookFailureCfg ce3Start ce3Events).map (fun s => decide (StuckHolding s))
    = some true := by decide

/-- …and the system can still take steps from it (the premise `Reach s t` is non-trivial). -/
example : (replay bookFailureCfg ce3Start (ce3Events ++ [.fetch .book .flight])).map
    (fun s => decide (StuckHolding s ∧ s.phase = .booking)) = some true := by decide

/-- In `ideal`, a booking is held during Booking and the state is *not* stuck (BR8 not trivial). -/
example : (replay idealCfg happyStart (bookItem .train)).map
    (fun s => decide ((s.items .train).active ≠ [] ∧ ¬ StuckHolding s)) = some true := by decide

/-! ### CE-6 (owner decision R1(a)): concurrent completion at the parallel join

`Gateway_1hfufm4` (V3:159): Flight and Train complete concurrently, one `complete()` is rolled
back by an OptimisticLockingException, the JS client swallows the error
(`TaskService.complete`, client 2.3.1), the lock expires, the handler books again. In the model
the failed `complete()` is a `lockExpire` after the side effect, i.e. it lives under
`redelivery` (R1). These two examples show the path is excluded in `ideal` but reachable — and
violates BR4 — once that re-execution is admitted. -/
def ce6Events : List Event :=
  bookItem .flight ++ [.fetch .book .train, .sideEffect .book .train, .lockExpire .book .train] ++
    bookItem .train

example : replay idealCfg happyStart ce6Events = none := by decide

example : (replay redeliveryCfg happyStart ce6Events).map (fun s => decide (¬ BR4 s)) = some true := by
  decide

/-! Quint trace agreement (evaluation only; the kernel-checked claims are `quint_*` theorems). -/
#eval [checkTrace tr_ideal_BR1, checkTrace tr_asIs_BR6, checkTrace tr_redelivery_BR4,
       checkTrace tr_bookFailure_BR8, checkTrace tr_cancelFailure_BR8, checkTrace tr_allFaults_BR8]

end Saga
