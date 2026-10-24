import Specs.Reachability
import Specs.Scenarios
/-
# Headline theorems

Phase 2 (theorem-first): statements are frozen here and snapshotted in `MODEL-MAP.md`.
Proof plans are in comments. Business-language versions are in `MODEL-MAP.md` for sign-off.

Groups
* A — every Quint counterexample class (CE-1…CE-5) is a real reachable violation, for **every**
      configuration that has the triggering assumption (not just the named Quint instance).
* B — BR8 stuck states are permanent.
* C — attribution: the ✓ cells of the Quint matrix hold for **all** reachable states, under the
      weakest assumption set that excludes the responsible fault.
* D — the whole 6 × 8 Quint matrix, cell by cell.
(E — the 22 replayed simulator traces live in `Specs/Traces.lean`.)
-/

namespace Saga

/-- Rule `P` is violated in some reachable state of configuration `cfg`. -/
def Violable (cfg : Config) (P : State → Prop) : Prop := ∃ s, Reachable cfg s ∧ ¬ P s
/-- Rule `P` holds in every reachable state of configuration `cfg`. -/
def Invariant (cfg : Config) (P : State → Prop) : Prop := ∀ s, Reachable cfg s → P s

/-! ## Infrastructure (helper lemmas, not headline) -/

theorem reach_of_replay {cfg : Config} {s t : State} {es : List Event}
    (h : replay cfg s es = some t) : Reach cfg s t := by
  -- induction on `es` generalizing `s`, using `Reach` closed under prepending a step
  exact reach_of_replay_aux h

theorem traceConfirmed_of_check (tr : QTrace) (P : State → Prop) [DecidablePred P]
    (hc : checkTrace tr = true)
    (hv : (tr.final.map fun s => decide (¬ P s)) = some true) :
    TraceConfirmed tr P := by
  -- `initOk` gives `Init`; `final = some s` + `reach_of_replay` gives `Reachable`; `hv` gives `¬ P s`
  exact traceConfirmed_of_check_aux tr P hc hv

/-! ## A — counterexample classes are real (any configuration with the trigger) -/

/-- **CE-1** (BR1, pure BPMN design): in *every* configuration a trip can end on the only end
event after the user canceled and compensation removed every booking. -/
theorem ce1_confirm_after_cancel (cfg : Config) : Violable cfg BR1 := by
  -- witness: hotel only; book, cancel, compensate, confirm (no fault event used) — replay + decide
  obtain ⟨a, b, c, d⟩ := cfg
  cases a <;> cases b <;> cases c <;> cases d <;> exact violable_of_replay (s0 := ce1Start) (es := ce1Events) (init_initState (by decide) (fun _ i => by cases i <;> simp_all [noneDown, ofTriple]) (fun _ i => by cases i <;> simp_all [noneDown, ofTriple])) (by decide)

/-- **CE-2** (BR4, BR5, BR2, BR7): with at-least-once redelivery a booking handler can run twice,
leaving a duplicate the process does not know about. -/
theorem ce2_redelivery_duplicate (cfg : Config) (h : cfg.redelivery = true) :
    Violable cfg BR4 ∧ Violable cfg BR5 ∧ Violable cfg BR2 ∧ Violable cfg BR7 := by
  -- witness: train+hotel; book train, lockExpire after side effect, book train again, … (flight unused)
  obtain ⟨a, b, c, d⟩ := cfg
  simp only at h; subst h
  cases b <;> cases c <;> cases d <;>
    exact ⟨violable_of_replay (s0 := ce2Start) (es := ce2Dup) (init_initState (by decide) (fun _ i => by cases i <;> simp_all [noneDown, ofTriple]) (fun _ i => by cases i <;> simp_all [noneDown, ofTriple])) (by decide),
      violable_of_replay (s0 := ce2Start) (es := ce2Review) (init_initState (by decide) (fun _ i => by cases i <;> simp_all [noneDown, ofTriple]) (fun _ i => by cases i <;> simp_all [noneDown, ofTriple])) (by decide),
      violable_of_replay (s0 := ce2Start) (es := ce2Comp) (init_initState (by decide) (fun _ i => by cases i <;> simp_all [noneDown, ofTriple]) (fun _ i => by cases i <;> simp_all [noneDown, ofTriple])) (by decide),
      violable_of_replay (s0 := ce2Start) (es := ce2End) (init_initState (by decide) (fun _ i => by cases i <;> simp_all [noneDown, ofTriple]) (fun _ i => by cases i <;> simp_all [noneDown, ofTriple])) (by decide)⟩

/-- **CE-3** (BR8): with booking failures a permanently refusing supplier blocks the saga while
another booking is held. -/
theorem ce3_book_failure_stuck (cfg : Config) (h : cfg.bookFailure = true) :
    Violable cfg BR8 := by
  -- witness: flight down; book train; flight task pending
  obtain ⟨a, b, c, d⟩ := cfg
  simp only at h; subst h
  cases a <;> cases c <;> cases d <;> exact violable_of_replay (s0 := ce3Start) (es := ce3Events) (init_initState (by decide) (fun _ i => by cases i <;> simp_all [noneDown, ofTriple]) (fun _ i => by cases i <;> simp_all [noneDown, ofTriple])) (by decide)

/-- **CE-4** (BR8): with cancellation failures a supplier refusing to cancel blocks compensation
while its booking is held. -/
theorem ce4_cancel_failure_stuck (cfg : Config) (h : cfg.cancelFailure = true) :
    Violable cfg BR8 := by
  -- witness: hotel cancelDown; book hotel only; user cancels; Cancel(hotel) pending
  obtain ⟨a, b, c, d⟩ := cfg
  simp only at h; subst h
  cases a <;> cases b <;> cases d <;> exact violable_of_replay (s0 := ce4Start) (es := ce4Events) (init_initState (by decide) (fun _ i => by cases i <;> simp_all [noneDown, ofTriple]) (fun _ i => by cases i <;> simp_all [noneDown, ofTriple])) (by decide)

/-- **CE-5** (BR5, BR6, BR2, BR7): the FlightBooking.js two-UUID bug alone makes the form lie,
cancels a non-existent booking, and leaves the real flight booked. -/
theorem ce5_flight_ref_mismatch (cfg : Config) (h : cfg.flightRefBug = true) :
    Violable cfg BR5 ∧ Violable cfg BR6 ∧ Violable cfg BR2 ∧ Violable cfg BR7 := by
  -- witness: flight+hotel; book both; review; cancel; compensate; confirm
  obtain ⟨a, b, c, d⟩ := cfg
  simp only at h; subst h
  cases a <;> cases b <;> cases c <;>
    exact ⟨violable_of_replay (s0 := ce5Start) (es := ce5Review) (init_initState (by decide) (fun _ i => by cases i <;> simp_all [noneDown, ofTriple]) (fun _ i => by cases i <;> simp_all [noneDown, ofTriple])) (by decide),
      violable_of_replay (s0 := ce5Start) (es := ce5Comp) (init_initState (by decide) (fun _ i => by cases i <;> simp_all [noneDown, ofTriple]) (fun _ i => by cases i <;> simp_all [noneDown, ofTriple])) (by decide),
      violable_of_replay (s0 := ce5Start) (es := ce5Comp) (init_initState (by decide) (fun _ i => by cases i <;> simp_all [noneDown, ofTriple]) (fun _ i => by cases i <;> simp_all [noneDown, ofTriple])) (by decide),
      violable_of_replay (s0 := ce5Start) (es := ce5End) (init_initState (by decide) (fun _ i => by cases i <;> simp_all [noneDown, ofTriple]) (fun _ i => by cases i <;> simp_all [noneDown, ofTriple])) (by decide)⟩

/-! ## B — stuck is forever -/

/-- **BR8 permanence**: once a reachable state is stuck holding bookings, every state reachable
from it is still stuck holding bookings and the process phase never changes (so the user task
never reopens and the process never ends). -/
theorem stuck_is_permanent (cfg : Config) {s t : State}
    (hr : Reachable cfg s) (hs : StuckHolding s) (h : Reach cfg s t) :
    StuckHolding t ∧ t.phase = s.phase := by
  -- structural invariant of reachable states (books only in Booking, cancels only in
  -- Compensating, join bookkeeping, held refs never released by a refusing supplier),
  -- then induction on `h` with the blocked item fixed
  have hs0 := struct_reachable s hr
  induction h with
  | refl => exact ⟨hs, rfl⟩
  | tail e hst hstep ih =>
    obtain ⟨ih1, ih2⟩ := ih
    obtain ⟨h1, h2⟩ := stuck_step (struct_reach hs0 hst) ih1 hstep
    exact ⟨h1, h2.trans ih2⟩

/-! ## C — attribution: ✓ cells hold for all reachable states -/

/-- **BR3** holds in every configuration. -/
theorem br3_always (cfg : Config) : Invariant cfg BR3 := by
  -- invariant: book task present ⇒ needed; ever ≠ [] ⇒ needed
  intro s hs
  have := (struct_reachable s hs).everNeeded
  exact ⟨this .flight, this .train, this .hotel⟩

/-- **BR4** holds whenever there is no redelivery (whatever the other assumptions). -/
theorem br4_of_no_redelivery (cfg : Config) (h : cfg.redelivery = false) :
    Invariant cfg BR4 := by
  -- invariant: each item's booking side effect happens at most once
  intro s hs
  obtain ⟨q1, q2, q3⟩ := q_reachable h s hs
  exact ⟨q1.1, q2.1, q3.1⟩

/-- **BR6** holds whenever the flight ref bug is absent (whatever the other assumptions). -/
theorem br6_of_no_flight_bug (cfg : Config) (h : cfg.flightRefBug = false) :
    Invariant cfg BR6 := by
  -- invariant: recorded/returned refs are always in `ever`
  intro s hs
  obtain ⟨r1, r2, r3⟩ := r_reachable h s hs
  exact ⟨fun hc => r1.1 (by rw [hc]; decide), fun hc => r2.1 (by rw [hc]; decide),
    fun hc => r3.1 (by rw [hc]; decide)⟩

/-- **BR8** holds whenever no supplier can fail (whatever the other assumptions). -/
theorem br8_of_no_failures (cfg : Config) (h1 : cfg.bookFailure = false)
    (h2 : cfg.cancelFailure = false) : Invariant cfg BR8 := by
  -- `down`/`cancelDown` are all false initially and never change
  intro s hs ⟨_, hb, _⟩
  have hd := noDown_inv cfg h1 h2 s hs
  have hf := hd .flight; have ht := hd .train; have hh := hd .hotel
  simp only [anyItem, blocked] at hb
  simp_all

/-- **BR2** holds whenever there is neither redelivery nor the flight ref bug. -/
theorem br2_of_reliable (cfg : Config) (h1 : cfg.redelivery = false)
    (h2 : cfg.flightRefBug = false) : Invariant cfg BR2 := by
  -- exact per-phase ledger invariant (`Exact`), see proof module
  intro s hs
  obtain ⟨_, ef, et, eh⟩ := exact_reachable h1 h2 s hs
  intro ⟨hu, hp⟩
  rcases hp with hp | hp <;> simp_all [ExactItem, nothingBooked, allItems]

/-- **BR5** holds whenever there is neither redelivery nor the flight ref bug. -/
theorem br5_of_reliable (cfg : Config) (h1 : cfg.redelivery = false)
    (h2 : cfg.flightRefBug = false) : Invariant cfg BR5 := by
  intro s hs hp
  obtain ⟨_, ef, et, eh⟩ := exact_reachable h1 h2 s hs
  cases hu : s.userCanceled <;>
  cases hnf : (s.items .flight).need <;> cases hnt : (s.items .train).need <;>
  cases hnh : (s.items .hotel).need <;>
    simp_all [ExactItem, allItems, displayAgrees, holdsExactly]

/-- **BR7** holds whenever there is neither redelivery nor the flight ref bug. -/
theorem br7_of_reliable (cfg : Config) (h1 : cfg.redelivery = false)
    (h2 : cfg.flightRefBug = false) : Invariant cfg BR7 := by
  intro s hs hp
  obtain ⟨_, ef, et, eh⟩ := exact_reachable h1 h2 s hs
  cases hu : s.userCanceled <;>
  cases hnf : (s.items .flight).need <;> cases hnt : (s.items .train).need <;>
  cases hnh : (s.items .hotel).need <;>
    simp_all [ExactItem, allItems, fullyBooked, nothingBooked, settledBooked, holdsExactly]

/-! ## D — the Quint matrix (`specs/quint/REPORT.md` §4), all 48 cells -/

/-- Every ✗ of the Quint matrix is a real violation and every ✓ is a theorem. -/
theorem quint_matrix :
    -- ideal:          ✗ BR1 │ ✓ BR2 BR3 BR4 BR5 BR6 BR7 BR8
    (Violable idealCfg BR1 ∧ Invariant idealCfg BR2 ∧ Invariant idealCfg BR3 ∧
      Invariant idealCfg BR4 ∧ Invariant idealCfg BR5 ∧ Invariant idealCfg BR6 ∧
      Invariant idealCfg BR7 ∧ Invariant idealCfg BR8) ∧
    -- asIs:           ✗ BR1 BR2 BR5 BR6 BR7 │ ✓ BR3 BR4 BR8
    (Violable asIsCfg BR1 ∧ Violable asIsCfg BR2 ∧ Invariant asIsCfg BR3 ∧
      Invariant asIsCfg BR4 ∧ Violable asIsCfg BR5 ∧ Violable asIsCfg BR6 ∧
      Violable asIsCfg BR7 ∧ Invariant asIsCfg BR8) ∧
    -- redelivery:     ✗ BR1 BR2 BR4 BR5 BR7 │ ✓ BR3 BR6 BR8
    (Violable redeliveryCfg BR1 ∧ Violable redeliveryCfg BR2 ∧ Invariant redeliveryCfg BR3 ∧
      Violable redeliveryCfg BR4 ∧ Violable redeliveryCfg BR5 ∧ Invariant redeliveryCfg BR6 ∧
      Violable redeliveryCfg BR7 ∧ Invariant redeliveryCfg BR8) ∧
    -- bookFailure:    ✗ BR1 BR8 │ ✓ BR2 BR3 BR4 BR5 BR6 BR7
    (Violable bookFailureCfg BR1 ∧ Invariant bookFailureCfg BR2 ∧ Invariant bookFailureCfg BR3 ∧
      Invariant bookFailureCfg BR4 ∧ Invariant bookFailureCfg BR5 ∧ Invariant bookFailureCfg BR6 ∧
      Invariant bookFailureCfg BR7 ∧ Violable bookFailureCfg BR8) ∧
    -- cancelFailure:  ✗ BR1 BR8 │ ✓ BR2 BR3 BR4 BR5 BR6 BR7
    (Violable cancelFailureCfg BR1 ∧ Invariant cancelFailureCfg BR2 ∧
      Invariant cancelFailureCfg BR3 ∧ Invariant cancelFailureCfg BR4 ∧
      Invariant cancelFailureCfg BR5 ∧ Invariant cancelFailureCfg BR6 ∧
      Invariant cancelFailureCfg BR7 ∧ Violable cancelFailureCfg BR8) ∧
    -- allFaults:      ✗ BR1 BR2 BR4 BR5 BR6 BR7 BR8 │ ✓ BR3
    (Violable allFaultsCfg BR1 ∧ Violable allFaultsCfg BR2 ∧ Invariant allFaultsCfg BR3 ∧
      Violable allFaultsCfg BR4 ∧ Violable allFaultsCfg BR5 ∧ Violable allFaultsCfg BR6 ∧
      Violable allFaultsCfg BR7 ∧ Violable allFaultsCfg BR8) := by
  -- assemble from groups A and C (each config instantiates the hypotheses by `rfl`)
  refine ⟨⟨ce1_confirm_after_cancel _, br2_of_reliable _ rfl rfl, br3_always _,
      br4_of_no_redelivery _ rfl, br5_of_reliable _ rfl rfl, br6_of_no_flight_bug _ rfl,
      br7_of_reliable _ rfl rfl, br8_of_no_failures _ rfl rfl⟩,
    ⟨ce1_confirm_after_cancel _, (ce5_flight_ref_mismatch _ rfl).2.2.1, br3_always _,
      br4_of_no_redelivery _ rfl, (ce5_flight_ref_mismatch _ rfl).1,
      (ce5_flight_ref_mismatch _ rfl).2.1, (ce5_flight_ref_mismatch _ rfl).2.2.2,
      br8_of_no_failures _ rfl rfl⟩,
    ⟨ce1_confirm_after_cancel _, (ce2_redelivery_duplicate _ rfl).2.2.1, br3_always _,
      (ce2_redelivery_duplicate _ rfl).1, (ce2_redelivery_duplicate _ rfl).2.1,
      br6_of_no_flight_bug _ rfl, (ce2_redelivery_duplicate _ rfl).2.2.2,
      br8_of_no_failures _ rfl rfl⟩,
    ⟨ce1_confirm_after_cancel _, br2_of_reliable _ rfl rfl, br3_always _,
      br4_of_no_redelivery _ rfl, br5_of_reliable _ rfl rfl, br6_of_no_flight_bug _ rfl,
      br7_of_reliable _ rfl rfl, ce3_book_failure_stuck _ rfl⟩,
    ⟨ce1_confirm_after_cancel _, br2_of_reliable _ rfl rfl, br3_always _,
      br4_of_no_redelivery _ rfl, br5_of_reliable _ rfl rfl, br6_of_no_flight_bug _ rfl,
      br7_of_reliable _ rfl rfl, ce4_cancel_failure_stuck _ rfl⟩,
    ⟨ce1_confirm_after_cancel _, (ce2_redelivery_duplicate _ rfl).2.2.1, br3_always _,
      (ce2_redelivery_duplicate _ rfl).1, (ce2_redelivery_duplicate _ rfl).2.1,
      (ce5_flight_ref_mismatch _ rfl).2.1, (ce2_redelivery_duplicate _ rfl).2.2.2,
      ce3_book_failure_stuck _ rfl⟩⟩

end Saga
