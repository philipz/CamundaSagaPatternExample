import Specs.Trace
/-
# Concrete scenarios (minimal counterexample witnesses)

Hand-written minimal event lists mirroring `specs/quint/bookHoliday_test.qnt` (CE-1…CE-5).
They are *data*; the claims about them are the theorems in `Specs/Proofs.lean`.
-/

namespace Saga

def bookItem (i : Item) : List Event := [.fetch .book i, .sideEffect .book i, .complete .book i]
def cancelItem (i : Item) : List Event :=
  [.fetch .cancel i, .sideEffect .cancel i, .complete .cancel i]

def noneDown : Item → Bool := ofTriple false false false

/-! CE-1: hotel only; book, cancel, compensate, confirm. -/
def ce1Start : State := initState (ofTriple false false true) noneDown noneDown
def ce1Events : List Event := bookItem .hotel ++ [.userCancel] ++ cancelItem .hotel ++ [.userConfirm]

/-! CE-2: train + hotel; the first train booking is redelivered. -/
def ce2Start : State := initState (ofTriple false true true) noneDown noneDown
/-- after this prefix: two train bookings held (¬BR4) -/
def ce2Dup : List Event :=
  [.fetch .book .train, .sideEffect .book .train, .lockExpire .book .train] ++ bookItem .train
/-- … reaches the form (¬BR5) -/
def ce2Review : List Event := ce2Dup ++ bookItem .hotel
/-- … compensation done, first train booking orphaned (¬BR2) -/
def ce2Comp : List Event := ce2Review ++ [.userCancel] ++ cancelItem .hotel ++ cancelItem .train
/-- … ends with a partial booking (¬BR7) -/
def ce2End : List Event := ce2Comp ++ [.userConfirm]

/-! CE-3: all needed; flight supplier permanently down; train booked and held. -/
def ce3Start : State := initState (ofTriple true true true) (ofTriple true false false) noneDown
def ce3Events : List Event := bookItem .train ++ [.fetch .book .flight, .handlerFail .book .flight]

/-! CE-4: hotel only; hotel refuses cancellation forever. -/
def ce4Start : State := initState (ofTriple false false true) noneDown (ofTriple false false true)
def ce4Events : List Event :=
  bookItem .hotel ++ [.userCancel, .fetch .cancel .hotel, .handlerFail .cancel .hotel]

/-! CE-5: flight + hotel with the two-UUID bug. -/
def ce5Start : State := initState (ofTriple true false true) noneDown noneDown
/-- the form shows ref 2, supplier holds ref 1 (¬BR5) -/
def ce5Review : List Event := bookItem .flight ++ bookItem .hotel
/-- compensation canceled ref 2 (never booked: ¬BR6), real flight ref 1 still held (¬BR2) -/
def ce5Comp : List Event := ce5Review ++ [.userCancel] ++ cancelItem .hotel ++ cancelItem .flight
/-- ends with the flight still booked (¬BR7) -/
def ce5End : List Event := ce5Comp ++ [.userConfirm]

/-! Positive path: everything booked and confirmed. -/
def happyStart : State := initState (ofTriple true true true) noneDown noneDown
def happyEvents : List Event :=
  bookItem .train ++ bookItem .flight ++ bookItem .hotel ++ [.userConfirm]

end Saga
