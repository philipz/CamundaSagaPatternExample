/-
# Book Holiday Saga — Lean model (derived independently from the sources)

Sources (read-only):
* `Models/BookHolidaySagaPatternV3.bpmn`            (abbrev. `V3:<line>`)
* `BookingSystemWorkers/FlightBooking.js`           (`FB:<line>`)
* `BookingSystemWorkers/TrainBooking.js`            (`TB:<line>`)
* `BookingSystemWorkers/BookHotel.js`               (`BH:<line>`)
* camunda-external-task-client-js 2.3.1 `lib/Client.js` (`executeTask`: handler error is only
  emitted, no `handleFailure`; lock expires after `lockDuration`, task is fetched again)
* Camunda 7.21 compensation semantics (subscription created on completion, consumed when
  thrown; throw waits for all handlers) and `ExternalTaskEntity.complete` (variables are set
  with propagation to the process-instance scope).

State is grouped **per saga item** (`ItemSt`): engine variables, the item's two external tasks,
and the supplier-side ledger of that item live together, because every transition except the
gateways touches exactly one item. See `MODEL-MAP.md` for the line-by-line correspondence and the
comparison with the Quint model (`specs/quint/bookHoliday.qnt`).
-/

namespace Saga

/-- The three saga steps. `V3:23` (hotel), `V3:32` (flight), `V3:139` (train). -/
inductive Item where
  | flight | train | hotel
  deriving DecidableEq, Repr

/-- Process variables `*BookingStatus`: "No Booking Made" (`V3:12-14`), "Confirmed"
(`FB:20`, `TB:16`, `BH:16`), "Canceled" (`FB:33`, `TB:27`, `BH:25`). -/
inductive Status where
  | noBooking | confirmed | canceled
  deriving DecidableEq, Repr

/-- Where the process token(s) are. -/
inductive Phase where
  | booking       -- parallel booking part, before `Activity_034u6ma`
  | review        -- user task "Check Booking Details" `V3:43` is open
  | compensating  -- throw event "Cancel Bookings" `V3:86` waits for its handlers
  | ended         -- end event `V3:20`
  deriving DecidableEq, Repr

/-- The two external-task topics per item: Book* and Cancel* (`isForCompensation`). -/
inductive Kind where
  | book | cancel
  deriving DecidableEq, Repr

/-- One external task in the engine's task table.
`locked done target ret`: fetched by a worker; `done` = the handler already called the supplier;
`target` = booking ref resolved from the input mapping `${XBookingID}` (cancel only);
`ret` = booking ref the handler will report in `complete()` (book only). -/
inductive Task where
  | absent
  | available
  | locked (done : Bool) (target : Nat) (ret : Nat)
  deriving DecidableEq, Repr

/-- The four system-model assumptions (owner decisions Q3, Q9). -/
structure Config where
  /-- worker crash / lock expiry while a task is locked (at-least-once delivery) -/
  redelivery : Bool
  /-- a booking handler may throw (and a supplier may refuse bookings forever) -/
  bookFailure : Bool
  /-- a cancel handler may throw (and a supplier may refuse cancellations forever) -/
  cancelFailure : Bool
  /-- `FB:19-21`: books with `id`, reports a second `create_UUID()` -/
  flightRefBug : Bool
  deriving DecidableEq, Repr

/-- Everything about one saga item. -/
structure ItemSt where
  /-- `flightNeeded` / `trainTicketNeeded` (start form `V3:8-9`); hotel always true -/
  need : Bool
  /-- this branch reached the parallel join `Gateway_1hfufm4` (`V3:159`) -/
  branchDone : Bool
  status : Status
  /-- process variable `*BookingID` (0 = none) -/
  ref : Nat
  /-- compensation subscription of the boundary event (`V3:100`, `V3:111`, `V3:149`) -/
  sub : Bool
  book : Task
  cancel : Task
  /-- supplier ledger: currently valid bookings -/
  active : List Nat
  /-- supplier ledger: every booking ever created -/
  ever : List Nat
  /-- supplier refuses bookings forever -/
  down : Bool
  /-- supplier refuses cancellations forever -/
  cancelDown : Bool
  deriving DecidableEq, Repr

structure State where
  phase : Phase
  /-- the user has answered "No" at least once (`V3:83-85`) -/
  userCanceled : Bool
  /-- fresh-reference generator (stands for `create_UUID()`) -/
  nextRef : Nat
  items : Item → ItemSt

/-- Labels of the transition relation. -/
inductive Event where
  | fetch (k : Kind) (i : Item)
  | sideEffect (k : Kind) (i : Item)
  | handlerFail (k : Kind) (i : Item)
  | lockExpire (k : Kind) (i : Item)
  | complete (k : Kind) (i : Item)
  | userConfirm
  | userCancel
  deriving DecidableEq, Repr

/-! ## Helpers -/

def ItemSt.task (x : ItemSt) : Kind → Task
  | .book => x.book
  | .cancel => x.cancel

def ItemSt.setTask (x : ItemSt) : Kind → Task → ItemSt
  | .book, t => { x with book := t }
  | .cancel, t => { x with cancel := t }

def State.upd (s : State) (i : Item) (f : ItemSt → ItemSt) : State :=
  { s with items := fun j => if j = i then f (s.items j) else s.items j }

/-- "available, or locked but the handler has not called the supplier yet" -/
def Task.undone : Task → Bool
  | .available => true
  | .locked false _ _ => true
  | _ => false

def Config.failureAllowed (cfg : Config) : Kind → Bool
  | .book => cfg.bookFailure
  | .cancel => cfg.cancelFailure

/-- `FB:19-21`: with the bug the flight handler reports a *second* fresh UUID. -/
def Config.buggy (cfg : Config) (i : Item) : Bool :=
  cfg.flightRefBug && i == .flight

/-! ## Initial state — start event listener `V3:11-16`, parallel split + XORs `V3:123-158` -/

def initItem (need down cdown : Item → Bool) (i : Item) : ItemSt where
  need := need i
  -- an XOR whose condition is false takes the default flow straight to the join
  branchDone := match i with
    | .hotel => false
    | _ => !need i
  status := .noBooking
  ref := 0
  sub := false
  book := match i with
    -- both XORs took the default flow -> the join fires immediately -> Book Hotel
    | .hotel => if !need .flight && !need .train then .available else .absent
    | _ => if need i then .available else .absent
  cancel := .absent
  active := []
  ever := []
  down := down i
  cancelDown := cdown i

def initState (need down cdown : Item → Bool) : State where
  phase := .booking
  userCanceled := false
  nextRef := 1
  items := initItem need down cdown

/-- Admissible initial states: hotel is always needed (unconditional task `V3:23`); permanent
supplier failures exist only if the corresponding failure assumption is on. -/
def Init (cfg : Config) (s : State) : Prop :=
  ∃ need down cdown : Item → Bool,
    need .hotel = true ∧
    (cfg.bookFailure = false → ∀ i, down i = false) ∧
    (cfg.cancelFailure = false → ∀ i, cdown i = false) ∧
    s = initState need down cdown

/-! ## Engine reactions to `complete()` -/

/-- Book X completed (`FB:20-23`, `TB:16-19`, `BH:16-19`): status Confirmed, `*BookingID` = the
reported ref (variables propagate to process scope), compensation subscription created, branch
arrives at the join. Hotel completion leads to the user task (`V3:74`). When the second branch
arrives at the parallel join (`V3:159-165`), Book Hotel is created. -/
def completeBook (s : State) (i : Item) (r : Nat) : State :=
  let s1 := s.upd i fun x =>
    { x with book := .absent, status := .confirmed, ref := r, sub := true,
             branchDone := if i = .hotel then x.branchDone else true }
  if i = .hotel then { s1 with phase := .review }
  else if (s1.items .flight).branchDone && (s1.items .train).branchDone then
    s1.upd .hotel fun x => { x with book := .available }
  else s1

def allCancelsAbsent (s : State) : Bool :=
  (s.items .flight).cancel == .absent && (s.items .train).cancel == .absent &&
  (s.items .hotel).cancel == .absent

/-- Cancel X completed (`FB:33-35`, `TB:27-29`, `BH:25-27`): status Canceled. When every
compensation handler has finished, the throw event is left and `Flow_0u9r45z` (`V3:91`) leads
back to the user task. -/
def completeCancel (s : State) (i : Item) : State :=
  let s1 := s.upd i fun x => { x with cancel := .absent, status := .canceled }
  if allCancelsAbsent s1 then { s1 with phase := .review } else { s1 with phase := .compensating }

/-- `confirm = false` (`V3:83-85`) → compensation throw `V3:86-90`: every existing subscription
is triggered once and consumed. With no subscription left the throw completes at once and the
token returns to the user task. -/
def userCancel (s : State) : State where
  phase := if (s.items .flight).sub || (s.items .train).sub || (s.items .hotel).sub
           then .compensating else .review
  userCanceled := true
  nextRef := s.nextRef
  items := fun j =>
    let x := s.items j
    { x with sub := false, cancel := if x.sub then .available else x.cancel }

/-! ## The transition relation (executable) -/

def step (cfg : Config) (s : State) : Event → Option State
  -- fetchAndLock; a cancel task resolves `${XBookingID}` (input mapping, e.g. `V3:106`)
  | .fetch k i =>
    match (s.items i).task k with
    | .available =>
      some (s.upd i fun x => x.setTask k
        (.locked false (match k with | .cancel => x.ref | .book => 0) 0))
    | _ => none
  -- booking handler calls the supplier (stub `create_UUID()` = fresh ref)
  | .sideEffect .book i =>
    match (s.items i).book with
    | .locked false t _ =>
      if (s.items i).down then none else
      let n := s.nextRef
      some { (s.upd i fun x =>
                { x with book := .locked true t (if cfg.buggy i then n + 1 else n),
                         active := n :: x.active, ever := n :: x.ever })
             with nextRef := if cfg.buggy i then n + 2 else n + 1 }
    | _ => none
  -- cancel handler calls the supplier with the resolved ref
  | .sideEffect .cancel i =>
    match (s.items i).cancel with
    | .locked false t r =>
      if (s.items i).cancelDown then none else
      some (s.upd i fun x =>
        { x with cancel := .locked true t r, active := x.active.filter (· != t) })
    | _ => none
  -- handler throws before calling the supplier: lock expires, task fetchable again
  | .handlerFail k i =>
    match (s.items i).task k with
    | .locked false _ _ =>
      if cfg.failureAllowed k then some (s.upd i fun x => x.setTask k .available) else none
    | _ => none
  -- worker crash / lock expiry while locked (before or after the supplier call)
  | .lockExpire k i =>
    match (s.items i).task k with
    | .locked _ _ _ =>
      if cfg.redelivery then some (s.upd i fun x => x.setTask k .available) else none
    | _ => none
  | .complete .book i =>
    match (s.items i).book with
    | .locked true _ r => some (completeBook s i r)
    | _ => none
  | .complete .cancel i =>
    match (s.items i).cancel with
    | .locked true _ _ => some (completeCancel s i)
    | _ => none
  -- `confirm = true` (`V3:80-82`) → end event
  | .userConfirm => if s.phase = .review then some { s with phase := .ended } else none
  | .userCancel => if s.phase = .review then some (userCancel s) else none

/-- Reflexive–transitive closure of `step`. -/
inductive Reach (cfg : Config) : State → State → Prop
  | refl (s : State) : Reach cfg s s
  | tail {s t u : State} (e : Event) : Reach cfg s t → step cfg t e = some u → Reach cfg s u

def Reachable (cfg : Config) (s : State) : Prop :=
  ∃ s0, Init cfg s0 ∧ Reach cfg s0 s

/-! ## Replay of a concrete event list -/

def replay (cfg : Config) : State → List Event → Option State
  | s, [] => some s
  | s, e :: es => (step cfg s e).bind fun t => replay cfg t es

/-! ## The six named assumption sets of the Quint matrix (`bookHolidayInstances.qnt`) -/

def idealCfg : Config := ⟨false, false, false, false⟩
def asIsCfg : Config := ⟨false, false, false, true⟩
def redeliveryCfg : Config := ⟨true, false, false, false⟩
def bookFailureCfg : Config := ⟨false, true, false, false⟩
def cancelFailureCfg : Config := ⟨false, false, true, false⟩
def allFaultsCfg : Config := ⟨true, true, true, true⟩

end Saga
