import Specs.Model
/-
# Business rules BR1–BR8 (transcribed from RULES.md — do not edit without owner approval)

Each rule is a `Prop` on a single state, with a `Decidable` instance so that concrete states
(e.g. replayed Quint traces) can be checked by the kernel with `decide`.
-/

namespace Saga

/-- `P` holds for all three items (finite, decidable form of `∀ i`). -/
def allItems (P : Item → Prop) : Prop := P .flight ∧ P .train ∧ P .hotel
/-- `P` holds for some item. -/
def anyItem (P : Item → Prop) : Prop := P .flight ∨ P .train ∨ P .hotel

instance (P : Item → Prop) [DecidablePred P] : Decidable (allItems P) := by
  unfold allItems; infer_instance
instance (P : Item → Prop) [DecidablePred P] : Decidable (anyItem P) := by
  unfold anyItem; infer_instance

/-- The supplier holds exactly the single booking `r` (set semantics on the ledger list). -/
def holdsExactly (l : List Nat) (r : Nat) : Prop := r ∈ l ∧ ∀ x ∈ l, x = r

instance (l : List Nat) (r : Nat) : Decidable (holdsExactly l r) := by
  unfold holdsExactly; infer_instance

/-- Item `x` is correctly settled for a confirmed trip: needed ⇒ Confirmed and exactly the
recorded booking is held; not needed ⇒ nothing held. -/
def settledBooked (x : ItemSt) : Prop :=
  if x.need then x.status = .confirmed ∧ holdsExactly x.active x.ref else x.active = []

instance (x : ItemSt) : Decidable (settledBooked x) := by unfold settledBooked; infer_instance

def fullyBooked (s : State) : Prop := allItems fun i => settledBooked (s.items i)
def nothingBooked (s : State) : Prop := allItems fun i => (s.items i).active = []

instance (s : State) : Decidable (fullyBooked s) := by unfold fullyBooked; infer_instance
instance (s : State) : Decidable (nothingBooked s) := by unfold nothingBooked; infer_instance

/-- BR1 — ending via "confirm" means the trip is fully booked. -/
def BR1 (s : State) : Prop := s.phase = .ended → fullyBooked s

/-- BR2 — after the user canceled and compensation finished (Review or Ended), nothing is held. -/
def BR2 (s : State) : Prop :=
  s.userCanceled = true ∧ (s.phase = .review ∨ s.phase = .ended) → nothingBooked s

/-- BR3 — a supplier never received a booking for an item the user did not request. -/
def BR3 (s : State) : Prop := allItems fun i => (s.items i).ever ≠ [] → (s.items i).need = true

/-- BR4 — at most one valid booking per item at the supplier. -/
def BR4 (s : State) : Prop := allItems fun i => (s.items i).active.length ≤ 1

/-- What the Review form shows for item `x` agrees with the supplier. -/
def displayAgrees (x : ItemSt) : Prop :=
  if x.status = .confirmed then holdsExactly x.active x.ref else x.active = []

instance (x : ItemSt) : Decidable (displayAgrees x) := by unfold displayAgrees; infer_instance

/-- BR5 — while "Check Booking Details" is shown, it matches supplier reality. -/
def BR5 (s : State) : Prop := s.phase = .review → allItems fun i => displayAgrees (s.items i)

/-- BR6 — a cancellation addresses a booking that was actually made. -/
def BR6 (s : State) : Prop :=
  allItems fun i => (s.items i).status = .canceled → (s.items i).ref ∈ (s.items i).ever

/-- BR7 — saga atomicity at the end: all or nothing. -/
def BR7 (s : State) : Prop := s.phase = .ended → fullyBooked s ∨ nothingBooked s

/-- A pending task of item `x` whose supplier refuses forever (handler cannot ever succeed). -/
def blocked (x : ItemSt) : Prop :=
  (x.book.undone = true ∧ x.down = true) ∨ (x.cancel.undone = true ∧ x.cancelDown = true)

instance (x : ItemSt) : Decidable (blocked x) := by unfold blocked; infer_instance

/-- Stuck while holding bookings: Booking or Compensating, some task blocked forever, and some
booking still held at a supplier. -/
def StuckHolding (s : State) : Prop :=
  (s.phase = .booking ∨ s.phase = .compensating) ∧
  anyItem (fun i => blocked (s.items i)) ∧
  anyItem (fun i => (s.items i).active ≠ [])

instance (s : State) : Decidable (StuckHolding s) := by unfold StuckHolding; infer_instance

/-- BR8 — the process is never stuck while holding bookings. -/
def BR8 (s : State) : Prop := ¬ StuckHolding s

instance (s : State) : Decidable (BR1 s) := by unfold BR1; infer_instance
instance (s : State) : Decidable (BR2 s) := by unfold BR2; infer_instance
instance (s : State) : Decidable (BR3 s) := by unfold BR3; infer_instance
instance (s : State) : Decidable (BR4 s) := by unfold BR4; infer_instance
instance (s : State) : Decidable (BR5 s) := by unfold BR5; infer_instance
instance (s : State) : Decidable (BR6 s) := by unfold BR6; infer_instance
instance (s : State) : Decidable (BR7 s) := by unfold BR7; infer_instance
instance (s : State) : Decidable (BR8 s) := by unfold BR8; infer_instance

end Saga
