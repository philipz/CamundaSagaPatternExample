import Specs.Rules
/-
# Replaying Quint counterexample traces

A `QTrace` is a Quint simulator trace (`specs/quint/traces/*.itf.json`) transcribed by
`gen_traces.py`: the initial choices, the event labels Quint recorded (`lastEvent`), and every
Quint state projected onto the Lean state shape. `checkTrace` replays the events through the
**Lean** transition relation and requires the Lean state to agree with the Quint state after
every single step (ledger lists compared as sets, since Quint stores sets).
-/

namespace Saga

/-- Build an `Item → Bool` from three booleans (flight, train, hotel). -/
def ofTriple (f t h : Bool) : Item → Bool
  | .flight => f
  | .train => t
  | .hotel => h

/-- Set equality on ledger lists. -/
def setEqb (a b : List Nat) : Bool := a.all (b.contains ·) && b.all (a.contains ·)

def ItemSt.agree (x y : ItemSt) : Bool :=
  x.need == y.need && x.branchDone == y.branchDone && x.status == y.status &&
  x.ref == y.ref && x.sub == y.sub && x.book == y.book && x.cancel == y.cancel &&
  setEqb x.active y.active && setEqb x.ever y.ever &&
  x.down == y.down && x.cancelDown == y.cancelDown

def State.agree (s t : State) : Bool :=
  s.phase == t.phase && s.userCanceled == t.userCanceled && s.nextRef == t.nextRef &&
  (s.items .flight).agree (t.items .flight) && (s.items .train).agree (t.items .train) &&
  (s.items .hotel).agree (t.items .hotel)

structure QTrace where
  cfg : Config
  need : Item → Bool
  down : Item → Bool
  cdown : Item → Bool
  /-- Quint states 0..n, projected -/
  states : List State
  /-- Quint `lastEvent` of states 1..n -/
  events : List Event

def QTrace.start (tr : QTrace) : State := initState tr.need tr.down tr.cdown

/-- The initial choices are admissible for the trace's configuration (`Init`). -/
def QTrace.initOk (tr : QTrace) : Bool :=
  tr.need .hotel &&
  (tr.cfg.bookFailure || (!tr.down .flight && !tr.down .train && !tr.down .hotel)) &&
  (tr.cfg.cancelFailure || (!tr.cdown .flight && !tr.cdown .train && !tr.cdown .hotel))

/-- Replay events from `s`, demanding agreement with each expected Quint state. -/
def agreeAlong (cfg : Config) : State → List Event → List State → Bool
  | _, [], [] => true
  | s, e :: es, q :: qs =>
    match step cfg s e with
    | some t => t.agree q && agreeAlong cfg t es qs
    | none => false
  | _, _, _ => false

def checkTrace (tr : QTrace) : Bool :=
  tr.initOk &&
  match tr.states with
  | q0 :: qs => tr.start.agree q0 && agreeAlong tr.cfg tr.start tr.events qs
  | [] => false

/-- The Lean state at the end of the trace (if every step is enabled in Lean). -/
def QTrace.final (tr : QTrace) : Option State := replay tr.cfg tr.start tr.events

/-- **What "Quint's counterexample is correct" means**: the trace agrees with the Lean model
state-by-state, and its final state is a reachable Lean state violating rule `P`. -/
def TraceConfirmed (tr : QTrace) (P : State → Prop) : Prop :=
  checkTrace tr = true ∧ ∃ s, tr.final = some s ∧ Reachable tr.cfg s ∧ ¬ P s

end Saga
