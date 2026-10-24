import Specs.Lemmas
/-
# Reachability-level corollaries of the invariants in `Specs/Lemmas.lean`
-/

namespace Saga

/-! ## Combined reachability statements -/

theorem q_reachable {cfg : Config} (hr : cfg.redelivery = false) :
    ∀ s, Reachable cfg s → Q s := by
  have := inductive_invariant (cfg := cfg) (fun s => Struct s ∧ Q s)
    (fun _ ⟨need, down, cdown, hh, _, _, he⟩ => he ▸ ⟨struct_init _ _ _ hh, by
      cases hf : need .flight <;> cases ht : need .train <;>
        simp [Q, QItem, initState, initItem, hf, ht, Task.lockedTrue]⟩)
    (fun _ _ _ ⟨hs, hq⟩ h => ⟨struct_step hs h, q_step hr hs hq h⟩)
  exact fun s hs => (this s hs).2

theorem r_reachable {cfg : Config} (hb : cfg.flightRefBug = false) :
    ∀ s, Reachable cfg s → R s :=
  inductive_invariant R
    (fun _ ⟨need, down, cdown, _, _, _, he⟩ => he ▸ by
      cases hf : need .flight <;> cases ht : need .train <;>
        simp [R, RItem, initState, initItem, hf, ht, Task.retIn])
    (fun _ _ _ hr h => r_step hb hr h)

theorem exact_step {cfg : Config} (hr : cfg.redelivery = false) (hb : cfg.flightRefBug = false)
    {s t : State} {e : Event} (hs : Struct s) (he : Exact s) (h : step cfg s e = some t) :
    Exact t := by
  rcases step_inv h with ⟨k, j, hg, rfl⟩ | ⟨j, tg, r, hg, _, rfl⟩ | ⟨j, tg, r, hg, hd, rfl⟩ |
    ⟨k, j, tg, r, hg, _, rfl⟩ | ⟨k, j, d, tg, r, hg, hf, rfl⟩ | ⟨j, tg, r, hg, rfl⟩ |
    ⟨j, tg, r, hg, rfl⟩ | ⟨hp, rfl⟩ | ⟨hp, rfl⟩
  · exact exact_fetch hs he hg
  · exact exact_bookSE hb hs he hg
  · exact exact_cancelSE hs he hg
  · exact exact_fail hs he hg
  · simp_all
  · exact exact_completeBook hs he hg
  · exact exact_completeCancel hs he hg
  · exact exact_confirm he hp
  · exact exact_userCancel hs he hp

theorem exact_reachable {cfg : Config} (hr : cfg.redelivery = false)
    (hb : cfg.flightRefBug = false) : ∀ s, Reachable cfg s → Exact s := by
  have := inductive_invariant (cfg := cfg) (fun s => Struct s ∧ Exact s)
    (fun _ ⟨_, _, _, hh, _, _, he⟩ => he ▸ ⟨struct_init _ _ _ hh, exact_init _ _ _⟩)
    (fun _ _ _ ⟨hs, he⟩ h => ⟨struct_step hs h, exact_step hr hb hs he h⟩)
  exact fun s hs => (this s hs).2

/-- One step from a stuck-holding state keeps it stuck-holding with the same phase. -/
theorem stuck_step {cfg : Config} {u v : State} {e : Event} (hs : Struct u)
    (hu : StuckHolding u) (h : step cfg u e = some v) :
    StuckHolding v ∧ v.phase = u.phase := by
  obtain ⟨hph, hb, hm⟩ := hu
  have hsv := struct_step hs h
  have key : ∀ b, blocked (u.items b) → StuckHolding v ∧ v.phase = u.phase := by
    intro b hbb
    obtain ⟨hbv, hpv⟩ := blocked_step hs hph hbb h
    refine ⟨⟨hpv ▸ hph, ?_, ?_⟩, hpv⟩
    · cases b <;> simp_all [anyItem]
    · rcases hph with hph | hph
      · -- Booking: the held booking is never released
        have hh : ∀ m, (u.items m).active ≠ [] → (v.items m).active ≠ [] :=
          fun m hm => held_booking_step hs hph hm h
        rcases hm with hm | hm | hm
        · exact Or.inl (hh _ hm)
        · exact Or.inr (Or.inl (hh _ hm))
        · exact Or.inr (Or.inr (hh _ hm))
      · -- Compensating: the item refusing to cancel still holds its booking
        have hpc : v.phase = .compensating := hpv.trans hph
        have hbook : (v.items b).book = .absent := by
          cases hbk : (v.items b).book with
          | absent => rfl
          | available => have := hsv.booksOnlyBooking b (by simp [hbk]); simp_all
          | locked d t r => have := hsv.booksOnlyBooking b (by simp [hbk]); simp_all
        have hcb : (v.items b).cancel.undone = true ∧ (v.items b).cancelDown = true := by
          simp only [blocked] at hbv; rcases hbv with ⟨h1, _⟩ | h2
          · simp [hbook, Task.undone] at h1
          · exact h2
        have hne : (v.items b).cancel ≠ .absent := by
          intro h0; simp [h0, Task.undone] at hcb
        have := hsv.refusedHeld b hcb.2 (Or.inr hne)
        cases b <;> simp_all [anyItem]
  simp only [anyItem] at hb
  rcases hb with hb | hb | hb
  · exact key _ hb
  · exact key _ hb
  · exact key _ hb

/-- A concrete replay from an admissible start that ends in a violation witnesses `¬ P`. -/
theorem violable_of_replay {cfg : Config} {P : State → Prop} [DecidablePred P]
    {s0 : State} {es : List Event} (hi : Init cfg s0)
    (hv : ((replay cfg s0 es).map fun s => decide (¬ P s)) = some true) :
    ∃ s, Reachable cfg s ∧ ¬ P s := by
  cases hr : replay cfg s0 es with
  | none => simp [hr] at hv
  | some s => simp [hr] at hv; exact ⟨s, ⟨s0, hi, reach_of_replay_aux hr⟩, hv⟩

theorem init_initState {cfg : Config} {need down cdown : Item → Bool} (hh : need .hotel = true)
    (hd : cfg.bookFailure = false → ∀ i, down i = false)
    (hc : cfg.cancelFailure = false → ∀ i, cdown i = false) :
    Init cfg (initState need down cdown) := ⟨need, down, cdown, hh, hd, hc, rfl⟩

end Saga
