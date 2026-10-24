import Specs.Trace
/-
# Proof infrastructure (helper lemmas; not headline theorems)

* `step_inv` — inversion: the nine transition shapes of `step`, guards included.
* `Struct` — structural invariant of every reachable state in **every** configuration.
* Rule-specific inductive invariants (BR3, BR4, BR6, BR8, the exact-ledger invariant for
  BR2/BR5/BR7) and the stuck-permanence step lemma.
All proofs are kernel-checked; no `sorry`, no axioms beyond Lean's standard three.
-/

namespace Saga
set_option maxHeartbeats 8000000


theorem Reach.head {cfg : Config} {s t u : State} {e : Event}
    (h1 : step cfg s e = some t) (h2 : Reach cfg t u) : Reach cfg s u := by
  induction h2 with
  | refl => exact .tail e (.refl s) h1
  | tail e' _ h ih => exact .tail e' ih h

theorem Reach.trans {cfg : Config} {s t u : State}
    (h1 : Reach cfg s t) (h2 : Reach cfg t u) : Reach cfg s u := by
  induction h2 with
  | refl => exact h1
  | tail e _ h ih => exact .tail e ih h

theorem reach_of_replay_aux {cfg : Config} {s t : State} {es : List Event}
    (h : replay cfg s es = some t) : Reach cfg s t := by
  induction es generalizing s with
  | nil => simp [replay] at h; subst h; exact .refl _
  | cons e es ih =>
    simp only [replay] at h
    cases hs : step cfg s e with
    | none => simp [hs] at h
    | some s1 => simp [hs] at h; exact Reach.head hs (ih h)

theorem init_of_initOk (tr : QTrace) (h : tr.initOk = true) : Init tr.cfg tr.start := by
  refine ⟨tr.need, tr.down, tr.cdown, ?_, ?_, ?_, rfl⟩
  · simp [QTrace.initOk] at h; exact h.1.1
  · intro hb i
    simp [QTrace.initOk, hb] at h
    cases i <;> simp_all
  · intro hc i
    simp [QTrace.initOk, hc] at h
    cases i <;> simp_all

theorem traceConfirmed_of_check_aux (tr : QTrace) (P : State → Prop) [DecidablePred P]
    (hc : checkTrace tr = true)
    (hv : (tr.final.map fun s => decide (¬ P s)) = some true) :
    TraceConfirmed tr P := by
  refine ⟨hc, ?_⟩
  cases hf : tr.final with
  | none => simp [hf] at hv
  | some s =>
    simp [hf] at hv
    have hinit : tr.initOk = true := by
      simp [checkTrace] at hc; exact hc.1
    exact ⟨s, rfl, ⟨tr.start, init_of_initOk tr hinit, reach_of_replay_aux hf⟩, hv⟩



def fetchTask (k : Kind) (x : ItemSt) : ItemSt :=
  x.setTask k (.locked false (match k with | .cancel => x.ref | .book => 0) 0)

def bookSE (cfg : Config) (s : State) (j : Item) (tg : Nat) : State :=
  { (s.upd j fun x =>
      { x with book := .locked true tg (if cfg.buggy j then s.nextRef + 1 else s.nextRef),
               active := s.nextRef :: x.active, ever := s.nextRef :: x.ever })
    with nextRef := if cfg.buggy j then s.nextRef + 2 else s.nextRef + 1 }

def cancelSE (s : State) (j : Item) (tg r : Nat) : State :=
  s.upd j fun x => { x with cancel := .locked true tg r, active := x.active.filter (· != tg) }

/-- Inversion: every enabled step has one of nine shapes (guards included). -/
theorem step_inv {cfg : Config} {s t : State} {e : Event} (h : step cfg s e = some t) :
    (∃ k j, (s.items j).task k = .available ∧ t = s.upd j (fetchTask k)) ∨
    (∃ j tg r, (s.items j).book = .locked false tg r ∧ (s.items j).down = false ∧
        t = bookSE cfg s j tg) ∨
    (∃ j tg r, (s.items j).cancel = .locked false tg r ∧ (s.items j).cancelDown = false ∧
        t = cancelSE s j tg r) ∨
    (∃ k j tg r, (s.items j).task k = .locked false tg r ∧ cfg.failureAllowed k = true ∧
        t = s.upd j fun x => x.setTask k .available) ∨
    (∃ k j d tg r, (s.items j).task k = .locked d tg r ∧ cfg.redelivery = true ∧
        t = s.upd j fun x => x.setTask k .available) ∨
    (∃ j tg r, (s.items j).book = .locked true tg r ∧ t = completeBook s j r) ∨
    (∃ j tg r, (s.items j).cancel = .locked true tg r ∧ t = completeCancel s j) ∨
    (s.phase = .review ∧ t = { s with phase := .ended }) ∨
    (s.phase = .review ∧ t = userCancel s) := by
  cases e with
  | fetch k j =>
    simp only [step] at h; split at h <;> simp at h
    exact Or.inl ⟨k, j, by assumption, by subst h; rfl⟩
  | sideEffect k j =>
    cases k <;> simp only [step] at h <;> split at h <;> simp at h
    · rename_i tg r hb
      obtain ⟨hd, rfl⟩ := h
      exact Or.inr (Or.inl ⟨j, tg, r, hb, by simpa using hd, rfl⟩)
    · rename_i tg r hc
      obtain ⟨hd, rfl⟩ := h
      exact Or.inr (Or.inr (Or.inl ⟨j, tg, r, hc, by simpa using hd, rfl⟩))
  | handlerFail k j =>
    simp only [step] at h; split at h <;> simp at h
    rename_i tg r hk
    obtain ⟨hf, rfl⟩ := h
    exact Or.inr (Or.inr (Or.inr (Or.inl ⟨k, j, tg, r, hk, hf, rfl⟩)))
  | lockExpire k j =>
    simp only [step] at h; split at h <;> simp at h
    rename_i d tg r hk
    obtain ⟨hf, rfl⟩ := h
    exact Or.inr (Or.inr (Or.inr (Or.inr (Or.inl ⟨k, j, d, tg, r, hk, hf, rfl⟩))))
  | complete k j =>
    cases k <;> simp only [step] at h <;> split at h <;> simp at h
    · rename_i tg r hb; subst h
      exact Or.inr (Or.inr (Or.inr (Or.inr (Or.inr (Or.inl ⟨j, tg, r, hb, rfl⟩)))))
    · rename_i tg r hc; subst h
      exact Or.inr (Or.inr (Or.inr (Or.inr (Or.inr (Or.inr (Or.inl ⟨j, tg, r, hc, rfl⟩))))))
  | userConfirm =>
    simp only [step] at h; split at h <;> simp at h
    exact Or.inr (Or.inr (Or.inr (Or.inr (Or.inr (Or.inr (Or.inr (Or.inl ⟨by assumption, h.symm⟩)))))))
  | userCancel =>
    simp only [step] at h; split at h <;> simp at h
    exact Or.inr (Or.inr (Or.inr (Or.inr (Or.inr (Or.inr (Or.inr (Or.inr ⟨by assumption, h.symm⟩)))))))
@[simp] theorem upd_phase (s : State) (i : Item) (f : ItemSt → ItemSt) :
    (s.upd i f).phase = s.phase := rfl
@[simp] theorem upd_uc (s : State) (i : Item) (f : ItemSt → ItemSt) :
    (s.upd i f).userCanceled = s.userCanceled := rfl
@[simp] theorem upd_nextRef (s : State) (i : Item) (f : ItemSt → ItemSt) :
    (s.upd i f).nextRef = s.nextRef := rfl
@[simp] theorem upd_items (s : State) (i j : Item) (f : ItemSt → ItemSt) :
    (s.upd i f).items j = if j = i then f (s.items j) else s.items j := rfl
@[simp] theorem setTask_need (x : ItemSt) (k t) : (x.setTask k t).need = x.need := by cases k <;> rfl
@[simp] theorem setTask_down (x : ItemSt) (k t) : (x.setTask k t).down = x.down := by cases k <;> rfl
@[simp] theorem setTask_cdown (x : ItemSt) (k t) : (x.setTask k t).cancelDown = x.cancelDown := by cases k <;> rfl

def Frame (s t : State) : Prop :=
  ∀ i, (t.items i).need = (s.items i).need ∧ (t.items i).down = (s.items i).down ∧
       (t.items i).cancelDown = (s.items i).cancelDown

theorem completeBook_frame (s : State) (j : Item) (r : Nat) : Frame s (completeBook s j r) := by
  intro i
  cases j <;> cases i <;> simp [completeBook] <;> split <;> simp

def cancelDone (x : ItemSt) : ItemSt := { x with cancel := .absent, status := .canceled }

theorem completeCancel_items (s : State) (j : Item) :
    (completeCancel s j).items = (s.upd j cancelDone).items := by
  simp only [completeCancel]; split <;> rfl
theorem completeCancel_phase (s : State) (j : Item) :
    (completeCancel s j).phase =
      if allCancelsAbsent (s.upd j cancelDone) then .review else .compensating := by
  unfold completeCancel cancelDone; split <;> simp_all
theorem completeCancel_uc (s : State) (j : Item) :
    (completeCancel s j).userCanceled = s.userCanceled := by
  simp only [completeCancel]; split <;> rfl
theorem completeCancel_nextRef (s : State) (j : Item) :
    (completeCancel s j).nextRef = s.nextRef := by
  simp only [completeCancel]; split <;> rfl

theorem completeCancel_frame (s : State) (j : Item) : Frame s (completeCancel s j) := by
  intro i
  rw [completeCancel_items]
  by_cases hij : i = j <;> simp [hij, cancelDone]

theorem userCancel_frame (s : State) : Frame s (userCancel s) := by
  intro i; simp [userCancel]

theorem step_frame {cfg s e t} (h : step cfg s e = some t) : Frame s t := by
  intro i
  cases e with
  | fetch k j =>
    simp only [step] at h
    split at h <;> simp at h
    subst h; by_cases hij : i = j <;> simp [hij]
  | sideEffect k j =>
    cases k <;> simp only [step] at h <;> split at h <;> simp at h
    all_goals (obtain ⟨_, rfl⟩ := h; by_cases hij : i = j <;> simp [hij])
  | handlerFail k j =>
    simp only [step] at h; split at h <;> simp at h
    obtain ⟨_, rfl⟩ := h; by_cases hij : i = j <;> simp [hij]
  | lockExpire k j =>
    simp only [step] at h; split at h <;> simp at h
    obtain ⟨_, rfl⟩ := h; by_cases hij : i = j <;> simp [hij]
  | complete k j =>
    cases k <;> simp only [step] at h <;> split at h <;> simp at h <;> subst h
    · exact completeBook_frame _ _ _ i
    · exact completeCancel_frame _ _ i
  | userConfirm =>
    simp only [step] at h; split at h <;> simp at h; subst h; simp
  | userCancel =>
    simp only [step] at h; split at h <;> simp at h; subst h; exact userCancel_frame _ i

theorem reach_preserves {cfg : Config} {I : State → Prop}
    (hs : ∀ s e t, I s → step cfg s e = some t → I t) {s t : State}
    (h : Reach cfg s t) (h0 : I s) : I t := by
  induction h with
  | refl => exact h0
  | tail e _ hst ih => exact hs _ e _ ih hst

theorem inductive_invariant {cfg : Config} (I : State → Prop) (h0 : ∀ s, Init cfg s → I s)
    (hs : ∀ s e t, I s → step cfg s e = some t → I t) : ∀ s, Reachable cfg s → I s := by
  rintro s ⟨s0, hi, hr⟩; exact reach_preserves hs hr (h0 s0 hi)

/-! ### BR8 without failures -/
def NoDown (s : State) : Prop := ∀ i, (s.items i).down = false ∧ (s.items i).cancelDown = false

theorem noDown_inv (cfg : Config) (h1 : cfg.bookFailure = false) (h2 : cfg.cancelFailure = false) :
    ∀ s, Reachable cfg s → NoDown s := by
  apply inductive_invariant
  · rintro s ⟨need, down, cdown, _, hd, hc, rfl⟩ i
    exact ⟨hd h1 i, hc h2 i⟩
  · intro s e t hs hst i
    obtain ⟨_, hd, hc⟩ := step_frame hst i
    rw [hd, hc]; exact hs i

def Task.lockedTrue : Task → Bool
  | .locked true _ _ => true
  | _ => false

/-- Structural invariant of every reachable state (all configurations). -/
structure Struct (s : State) : Prop where
  hotelNeed : (s.items .hotel).need = true
  bookingUc : s.phase = .booking → s.userCanceled = false
  bookingHotel : s.phase = .booking → (s.items .hotel).status = .noBooking
  join : (s.items .hotel).book ≠ .absent →
    (s.items .flight).branchDone = true ∧ (s.items .train).branchDone = true
  booksOnlyBooking : ∀ i, (s.items i).book ≠ .absent → s.phase = .booking
  cancelsOnlyComp : ∀ i, (s.items i).cancel ≠ .absent → s.phase = .compensating
  bookNeeded : ∀ i, (s.items i).book ≠ .absent → (s.items i).need = true
  everNeeded : ∀ i, (s.items i).ever ≠ [] → (s.items i).need = true
  branchPending : ∀ i, i ≠ .hotel → (s.items i).book ≠ .absent → (s.items i).branchDone = false
  lockedHeld : ∀ i, (s.items i).book.lockedTrue = true → (s.items i).active ≠ []
  refusedHeld : ∀ i, (s.items i).cancelDown = true →
    ((s.items i).sub = true ∨ (s.items i).cancel ≠ .absent) → (s.items i).active ≠ []

theorem struct_init (need down cdown : Item → Bool) (hh : need .hotel = true) :
    Struct (initState need down cdown) := by
  cases hf : need .flight <;> cases ht : need .train <;>
  refine ⟨?_, ?_, ?_, ?_, ?_, ?_, ?_, ?_, ?_, ?_, ?_⟩ <;>
  first
  | (intro i; cases i <;> simp [initState, initItem, hf, ht, hh, Task.lockedTrue])
  | simp [initState, initItem, hf, ht, hh, Task.lockedTrue]

/-- destructure `Struct` and instantiate every `∀ i` field at the three items -/
syntax "struct_unfold " term : tactic
macro_rules
  | `(tactic| struct_unfold $hs) => `(tactic| (
    obtain ⟨h1, h2, h3, h4, h5, h6, h7, h8, h9, h10, h11⟩ := $hs
    have h5f := h5 .flight
    have h5t := h5 .train
    have h5h := h5 .hotel
    have h6f := h6 .flight
    have h6t := h6 .train
    have h6h := h6 .hotel
    have h7f := h7 .flight
    have h7t := h7 .train
    have h7h := h7 .hotel
    have h8f := h8 .flight
    have h8t := h8 .train
    have h8h := h8 .hotel
    have h10f := h10 .flight
    have h10t := h10 .train
    have h10h := h10 .hotel
    have h11f := h11 .flight
    have h11t := h11 .train
    have h11h := h11 .hotel
    have h9f := h9 .flight (by decide); have h9t := h9 .train (by decide)
    clear h5 h6 h7 h8 h9 h10 h11))

/-- the standard closing tactic for a `Struct` goal after a concrete transition -/
syntax "struct_close " ident " [" Lean.Parser.Tactic.simpLemma,* "]" : tactic
macro_rules
  | `(tactic| struct_close $j [$ls,*]) => `(tactic|
    (refine ⟨?_, ?_, ?_, ?_, ?_, ?_, ?_, ?_, ?_, ?_, ?_⟩ <;> (try intro i) <;>
      cases $j:ident <;> (try cases i) <;>
      simp_all [ItemSt.setTask, ItemSt.task, Task.lockedTrue, $ls,*]))

set_option maxHeartbeats 4000000

theorem struct_fetch {s : State} {k : Kind} {j : Item} (hs : Struct s)
    (hg : (s.items j).task k = .available) : Struct (s.upd j (fetchTask k)) := by
  struct_unfold hs
  cases k <;> struct_close j [fetchTask]

theorem struct_bookSE {cfg : Config} {s : State} {j : Item} {tg r : Nat} (hs : Struct s)
    (hg : (s.items j).book = .locked false tg r) : Struct (bookSE cfg s j tg) := by
  struct_unfold hs
  struct_close j [bookSE]

theorem struct_cancelSE {s : State} {j : Item} {tg r : Nat} (hs : Struct s)
    (hg : (s.items j).cancel = .locked false tg r) (hd : (s.items j).cancelDown = false) :
    Struct (cancelSE s j tg r) := by
  struct_unfold hs
  struct_close j [cancelSE]

theorem struct_unlock {s : State} {k : Kind} {j : Item} {d : Bool} {tg r : Nat} (hs : Struct s)
    (hg : (s.items j).task k = .locked d tg r) :
    Struct (s.upd j fun x => x.setTask k .available) := by
  struct_unfold hs
  cases k <;> struct_close j []

theorem struct_completeBook {s : State} {j : Item} {tg r : Nat} (hs : Struct s)
    (hg : (s.items j).book = .locked true tg r) : Struct (completeBook s j r) := by
  struct_unfold hs
  cases hbf : (s.items .flight).branchDone <;> cases hbt : (s.items .train).branchDone <;>
    struct_close j [completeBook]

theorem struct_completeCancel {s : State} {j : Item} {tg r : Nat} (hs : Struct s)
    (hg : (s.items j).cancel = .locked true tg r) : Struct (completeCancel s j) := by
  struct_unfold hs
  simp only [completeCancel]
  split <;> struct_close j [allCancelsAbsent]

theorem struct_confirm {s : State} (hs : Struct s) (hp : s.phase = .review) :
    Struct { s with phase := .ended } := by
  struct_unfold hs
  refine ⟨?_, ?_, ?_, ?_, ?_, ?_, ?_, ?_, ?_, ?_, ?_⟩ <;> (try intro i) <;> (try cases i) <;>
    simp_all [Task.lockedTrue]

theorem struct_userCancel {s : State} (hs : Struct s) (hp : s.phase = .review) :
    Struct (userCancel s) := by
  struct_unfold hs
  by_cases hc : ((s.items .flight).sub || (s.items .train).sub || (s.items .hotel).sub) = true <;>
  refine ⟨?_, ?_, ?_, ?_, ?_, ?_, ?_, ?_, ?_, ?_, ?_⟩ <;> (try intro i) <;> (try cases i) <;>
    simp_all [userCancel, Task.lockedTrue] <;> (try split) <;> simp_all


theorem struct_step {cfg : Config} {s t : State} {e : Event} (hs : Struct s)
    (h : step cfg s e = some t) : Struct t := by
  rcases step_inv h with ⟨k, j, hg, rfl⟩ | ⟨j, tg, r, hg, _, rfl⟩ | ⟨j, tg, r, hg, hd, rfl⟩ |
    ⟨k, j, tg, r, hg, _, rfl⟩ | ⟨k, j, d, tg, r, hg, _, rfl⟩ | ⟨j, tg, r, hg, rfl⟩ |
    ⟨j, tg, r, hg, rfl⟩ | ⟨hp, rfl⟩ | ⟨hp, rfl⟩
  · exact struct_fetch hs hg
  · exact struct_bookSE hs hg
  · exact struct_cancelSE hs hg hd
  · exact struct_unlock hs hg
  · exact struct_unlock hs hg
  · exact struct_completeBook hs hg
  · exact struct_completeCancel hs hg
  · exact struct_confirm hs hp
  · exact struct_userCancel hs hp

theorem struct_reachable {cfg : Config} : ∀ s, Reachable cfg s → Struct s :=
  inductive_invariant Struct (fun _ ⟨_, _, _, hh, _, _, he⟩ => he ▸ struct_init _ _ _ hh)
    (fun _ _ _ hs h => struct_step hs h)

theorem struct_reach {cfg : Config} {s t : State} (hs : Struct s) (h : Reach cfg s t) :
    Struct t := reach_preserves (fun _ _ _ h1 h2 => struct_step h1 h2) h hs


/-! ## Rule-specific invariants -/

/-! ### BR4 without redelivery: each item's booking side effect happens at most once -/
def QItem (x : ItemSt) : Prop :=
  x.active.length ≤ 1 ∧
  (x.status = .noBooking → x.book.lockedTrue = false → x.active = []) ∧
  (x.status ≠ .noBooking → x.book = .absent)

def Q (s : State) : Prop := QItem (s.items .flight) ∧ QItem (s.items .train) ∧ QItem (s.items .hotel)

syntax "q_close " ident " [" Lean.Parser.Tactic.simpLemma,* "]" : tactic
macro_rules
  | `(tactic| q_close $j [$ls,*]) => `(tactic|
    (cases $j:ident <;>
      simp_all [Q, QItem, ItemSt.setTask, ItemSt.task, Task.lockedTrue, $ls,*]))

theorem q_step {cfg : Config} (hr : cfg.redelivery = false) {s t : State} {e : Event}
    (hs : Struct s) (hq : Q s) (h : step cfg s e = some t) : Q t := by
  struct_unfold hs
  rcases step_inv h with ⟨k, j, hg, rfl⟩ | ⟨j, tg, r, hg, _, rfl⟩ | ⟨j, tg, r, hg, hd, rfl⟩ |
    ⟨k, j, tg, r, hg, _, rfl⟩ | ⟨k, j, d, tg, r, hg, hf, rfl⟩ | ⟨j, tg, r, hg, rfl⟩ |
    ⟨j, tg, r, hg, rfl⟩ | ⟨hp, rfl⟩ | ⟨hp, rfl⟩
  · cases k <;> q_close j [fetchTask]
  · q_close j [bookSE]
  · have lf := Nat.le_trans (List.length_filter_le (fun x => x != tg) (s.items .flight).active) hq.1.1
    have lt := Nat.le_trans (List.length_filter_le (fun x => x != tg) (s.items .train).active) hq.2.1.1
    have lh := Nat.le_trans (List.length_filter_le (fun x => x != tg) (s.items .hotel).active) hq.2.2.1
    q_close j [cancelSE]
  · cases k <;> q_close j []
  · simp_all
  · cases hbf : (s.items .flight).branchDone <;> cases hbt : (s.items .train).branchDone <;>
      q_close j [completeBook]
  · rw [show completeCancel s j = _ from rfl]; simp only [completeCancel]
    split <;> q_close j [cancelDone]
  · simp_all [Q, QItem]
  · simp_all [Q, QItem, userCancel] <;> (try split) <;> simp_all

/-! ### BR6 without the flight bug: every recorded / returned ref was really booked -/
def Task.retIn : Task → List Nat → Prop
  | .locked true _ r, l => r ∈ l
  | _, _ => True

def RItem (x : ItemSt) : Prop :=
  (x.status ≠ .noBooking → x.ref ∈ x.ever) ∧ x.book.retIn x.ever ∧
  (x.cancel ≠ .absent → x.status ≠ .noBooking) ∧ (x.sub = true → x.status ≠ .noBooking)

def R (s : State) : Prop := RItem (s.items .flight) ∧ RItem (s.items .train) ∧ RItem (s.items .hotel)

syntax "r_close " ident " [" Lean.Parser.Tactic.simpLemma,* "]" : tactic
macro_rules
  | `(tactic| r_close $j [$ls,*]) => `(tactic|
    (cases $j:ident <;>
      simp_all [R, RItem, ItemSt.setTask, ItemSt.task, Task.retIn, Config.buggy, $ls,*]))

theorem r_step {cfg : Config} (hb : cfg.flightRefBug = false) {s t : State} {e : Event}
    (hrr : R s) (h : step cfg s e = some t) : R t := by
  rcases step_inv h with ⟨k, j, hg, rfl⟩ | ⟨j, tg, r, hg, _, rfl⟩ | ⟨j, tg, r, hg, hd, rfl⟩ |
    ⟨k, j, tg, r, hg, _, rfl⟩ | ⟨k, j, d, tg, r, hg, hf, rfl⟩ | ⟨j, tg, r, hg, rfl⟩ |
    ⟨j, tg, r, hg, rfl⟩ | ⟨hp, rfl⟩ | ⟨hp, rfl⟩
  · cases k <;> r_close j [fetchTask]
  · r_close j [bookSE]
  · r_close j [cancelSE]
  · cases k <;> r_close j []
  · cases k <;> r_close j []
  · cases hbf : (s.items .flight).branchDone <;> cases hbt : (s.items .train).branchDone <;>
      r_close j [completeBook]
  · simp only [completeCancel]; split <;> r_close j [cancelDone]
  · simp_all [R, RItem]
  · cases hsf : (s.items .flight).sub <;> cases hst : (s.items .train).sub <;>
      cases hsh : (s.items .hotel).sub <;> simp_all [R, RItem, userCancel]

/-! ### Exact ledger (no redelivery, no flight bug): what each supplier holds, per phase -/
def bookedRef : Task → List Nat
  | .locked true _ r => [r]
  | _ => []

def cancelExact (x : ItemSt) : Prop :=
  match x.cancel with
  | .absent => x.status ≠ .confirmed ∧ x.active = []
  | .available => x.status = .confirmed ∧ x.active = [x.ref]
  | .locked false tg _ => x.status = .confirmed ∧ x.active = [x.ref] ∧ tg = x.ref
  | .locked true _ _ => x.status = .confirmed ∧ x.active = []

def ExactItem (p : Phase) (uc : Bool) (x : ItemSt) : Prop :=
  match p with
  | .booking =>
    x.status ≠ .canceled ∧ (x.sub = true ↔ x.status = .confirmed) ∧ x.cancel = .absent ∧
    (x.status = .confirmed → x.book = .absent ∧ x.active = [x.ref] ∧ x.need = true) ∧
    (x.status = .noBooking → x.active = bookedRef x.book) ∧
    (x.branchDone = true → (x.need = true → x.status = .confirmed) ∧
                           (x.need = false → x.status = .noBooking ∧ x.book = .absent))
  | .review | .ended =>
    x.book = .absent ∧ x.cancel = .absent ∧
    (uc = true → x.sub = false ∧ x.active = [] ∧ x.status ≠ .confirmed) ∧
    (uc = false → (x.need = true → x.status = .confirmed ∧ x.active = [x.ref] ∧ x.sub = true) ∧
                  (x.need = false → x.status = .noBooking ∧ x.active = [] ∧ x.sub = false))
  | .compensating => x.book = .absent ∧ x.sub = false ∧ cancelExact x

def Exact (s : State) : Prop :=
  (s.phase = .compensating → s.userCanceled = true) ∧
  ExactItem s.phase s.userCanceled (s.items .flight) ∧
  ExactItem s.phase s.userCanceled (s.items .train) ∧
  ExactItem s.phase s.userCanceled (s.items .hotel)

theorem exact_init (need down cdown : Item → Bool) : Exact (initState need down cdown) := by
  cases hf : need .flight <;> cases ht : need .train <;> cases hh : need .hotel <;>
    simp [Exact, ExactItem, initState, initItem, hf, ht, hh, bookedRef]

syntax "x_close " ident ident " [" Lean.Parser.Tactic.simpLemma,* "]" : tactic
macro_rules
  | `(tactic| x_close $s $j [$ls,*]) => `(tactic|
    (cases hp : ($s:ident).phase <;> cases hu : ($s:ident).userCanceled <;> cases $j:ident <;>
      simp_all [Exact, ExactItem, cancelExact, bookedRef, ItemSt.setTask, ItemSt.task,
        Task.lockedTrue, Config.buggy, $ls,*]))

theorem exact_fetch {s : State} {k : Kind} {j : Item} (hs : Struct s) (he : Exact s)
    (hg : (s.items j).task k = .available) : Exact (s.upd j (fetchTask k)) := by
  struct_unfold hs
  cases k <;> x_close s j [fetchTask]

theorem exact_bookSE {cfg : Config} (hb : cfg.flightRefBug = false) {s : State} {j : Item}
    {tg r : Nat} (hs : Struct s) (he : Exact s)
    (hg : (s.items j).book = .locked false tg r) : Exact (bookSE cfg s j tg) := by
  struct_unfold hs
  x_close s j [bookSE]

theorem exact_cancelSE {s : State} {j : Item} {tg r : Nat} (hs : Struct s) (he : Exact s)
    (hg : (s.items j).cancel = .locked false tg r) : Exact (cancelSE s j tg r) := by
  struct_unfold hs
  x_close s j [cancelSE]

theorem exact_fail {s : State} {k : Kind} {j : Item} {tg r : Nat} (hs : Struct s)
    (he : Exact s) (hg : (s.items j).task k = .locked false tg r) :
    Exact (s.upd j fun x => x.setTask k .available) := by
  struct_unfold hs
  cases k <;> x_close s j []

theorem exact_completeBook {s : State} {j : Item} {tg r : Nat} (hs : Struct s) (he : Exact s)
    (hg : (s.items j).book = .locked true tg r) : Exact (completeBook s j r) := by
  struct_unfold hs
  cases hbf : (s.items .flight).branchDone <;> cases hbt : (s.items .train).branchDone <;>
  cases hsf : (s.items .flight).status <;> cases hst : (s.items .train).status <;>
  cases hsh : (s.items .hotel).status <;>
    x_close s j [completeBook]

theorem exact_completeCancel {s : State} {j : Item} {tg r : Nat} (hs : Struct s) (he : Exact s)
    (hg : (s.items j).cancel = .locked true tg r) : Exact (completeCancel s j) := by
  struct_unfold hs
  simp only [completeCancel]
  split <;> x_close s j [allCancelsAbsent]

theorem exact_confirm {s : State} (he : Exact s) (hp : s.phase = .review) :
    Exact { s with phase := .ended } := by
  cases hu : s.userCanceled <;> simp_all [Exact, ExactItem]

theorem exact_userCancel {s : State} (hs : Struct s) (he : Exact s) (hp : s.phase = .review) :
    Exact (userCancel s) := by
  struct_unfold hs
  cases hu : s.userCanceled <;>
  cases hsf : (s.items .flight).sub <;> cases hst : (s.items .train).sub <;>
    cases hsh : (s.items .hotel).sub <;>
    cases hnf : (s.items .flight).need <;> cases hnt : (s.items .train).need <;>
    simp_all [Exact, ExactItem, cancelExact, userCancel]


/-! ## Stuck permanence -/

syntax "b_close " ident ident ident " [" Lean.Parser.Tactic.simpLemma,* "]" : tactic
macro_rules
  | `(tactic| b_close $u $j $b [$ls,*]) => `(tactic|
    (cases hp : ($u:ident).phase <;> cases $j:ident <;> cases $b:ident <;>
      simp_all [blocked, Task.undone, ItemSt.setTask, ItemSt.task, Task.lockedTrue, $ls,*]))

/-- L1: a blocked item stays blocked and the phase does not move. -/
theorem blocked_step {cfg : Config} {u v : State} {e : Event} {b : Item} (hs : Struct u)
    (hph : u.phase = .booking ∨ u.phase = .compensating) (hb : blocked (u.items b))
    (h : step cfg u e = some v) : blocked (v.items b) ∧ v.phase = u.phase := by
  struct_unfold hs
  rcases step_inv h with ⟨k, j, hg, rfl⟩ | ⟨j, tg, r, hg, hd, rfl⟩ | ⟨j, tg, r, hg, hd, rfl⟩ |
    ⟨k, j, tg, r, hg, _, rfl⟩ | ⟨k, j, d, tg, r, hg, _, rfl⟩ | ⟨j, tg, r, hg, rfl⟩ |
    ⟨j, tg, r, hg, rfl⟩ | ⟨hp, rfl⟩ | ⟨hp, rfl⟩
  · cases k <;> b_close u j b [fetchTask]
  · b_close u j b [bookSE]
  · b_close u j b [cancelSE]
  · cases k <;> b_close u j b []
  · cases k <;> cases d <;> b_close u j b []
  · cases hbf : (u.items .flight).branchDone <;> cases hbt : (u.items .train).branchDone <;>
      b_close u j b [completeBook]
  · simp only [completeCancel]; split <;> b_close u j b [allCancelsAbsent]
  · simp_all
  · simp_all

/-- L2: in Booking nothing is ever released at a supplier. -/
theorem held_booking_step {cfg : Config} {u v : State} {e : Event} {m : Item} (hs : Struct u)
    (hph : u.phase = .booking) (hm : (u.items m).active ≠ [])
    (h : step cfg u e = some v) : (v.items m).active ≠ [] := by
  struct_unfold hs
  rcases step_inv h with ⟨k, j, hg, rfl⟩ | ⟨j, tg, r, hg, hd, rfl⟩ | ⟨j, tg, r, hg, hd, rfl⟩ |
    ⟨k, j, tg, r, hg, _, rfl⟩ | ⟨k, j, d, tg, r, hg, _, rfl⟩ | ⟨j, tg, r, hg, rfl⟩ |
    ⟨j, tg, r, hg, rfl⟩ | ⟨hp, rfl⟩ | ⟨hp, rfl⟩
  · cases k <;> cases j <;> cases m <;> simp_all [fetchTask, ItemSt.setTask]
  · cases j <;> cases m <;> simp_all [bookSE]
  · cases j <;> simp_all
  · cases k <;> cases j <;> cases m <;> simp_all [ItemSt.setTask]
  · cases k <;> cases j <;> cases m <;> simp_all [ItemSt.setTask]
  · cases hbf : (u.items .flight).branchDone <;> cases hbt : (u.items .train).branchDone <;>
      cases j <;> cases m <;> simp_all [completeBook]
  · cases j <;> simp_all
  · simp_all
  · simp_all

end Saga
