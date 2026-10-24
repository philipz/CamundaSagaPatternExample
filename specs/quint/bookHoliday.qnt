// -*- mode: Bluespec; -*-
/**
 * Book Holiday Saga (BookHolidaySagaPatternV3 + Node.js external-task workers)
 *
 * Grounds:
 *   Models/BookHolidaySagaPatternV3.bpmn        -- orchestration (engine side)
 *   BookingSystemWorkers/FlightBooking.js       -- BookFlight / CancelFlightBooking
 *   BookingSystemWorkers/TrainBooking.js        -- BookTrain  / CancelTrainBooking
 *   BookingSystemWorkers/BookHotel.js           -- BookHotel  / CancelHotelBooking
 *   camunda-external-task-client-js 2.3.1       -- fetchAndLock / handler / complete semantics
 *
 * Scope: ONE process instance (instances share no business state).
 * Coordination is shared state: the engine's external-task table, pulled by workers.
 *
 * Atomic grain (deliberately split to expose at-least-once delivery):
 *   fetchAndLock  ->  handler side effect at supplier  ->  complete (engine commits vars + moves token)
 * A lock expiry / worker crash returns a Locked task to Available, but the supplier-side
 * effect (if already done) persists.
 *
 * The supplier ledger is an ABSTRACTION of what the stub workers stand for once they call a
 * real booking API: it is the ground truth the business rules talk about.
 */
module bookHoliday {

  // ───────────────────────── System-model assumptions ─────────────────────────
  /// Q3(a) worker crashes / lock expires AFTER the supplier side effect but BEFORE complete
  const ALLOW_REDELIVERY: bool
  /// Q3(b) booking handler can throw (transient), or a supplier is permanently down
  const ALLOW_BOOK_FAILURE: bool
  /// Q3(c) cancel handler can throw (transient), or a supplier refuses cancels permanently
  const ALLOW_CANCEL_FAILURE: bool
  /// Q9  FlightBooking.js:19-21 books with `id` but returns a second create_UUID()
  const FLIGHT_REF_BUG: bool

  // ───────────────────────────────── Types ───────────────────────────────────
  type Item = Flight | Train | Hotel
  /// opaque booking reference (stands for the UUIDs); 0 = none
  type Ref = int
  /// process variables *BookingStatus
  type Status = NoBooking | Confirmed | Canceled
  type Phase =
    | Booking        // tokens in the parallel booking part (before "Check Booking Details")
    | Review         // user task "Check Booking Details" is open
    | Compensating   // intermediate throw "Cancel Bookings" waiting for compensation handlers
    | Ended          // end event Event_07xntzc (only reachable via confirm == true)

  type TaskKind = Book(Item) | Cancel(Item)
  type LockInfo = {
    sideEffectDone: bool,  // handler already performed the supplier call
    targetRef: Ref,        // Cancel: ref read from input mapping ${XBookingID}
    returnRef: Ref,        // Book: ref the handler will send in complete()
  }
  type TaskState = Absent | Available | Locked(LockInfo)

  /// trace label: which transition produced the current state
  type Event =
    | Started
    | Fetched(TaskKind)
    | SideEffect(TaskKind)
    | HandlerFailed(TaskKind)
    | LockExpired(TaskKind)
    | Completed(TaskKind)
    | UserConfirmed
    | UserCanceled

  /// one process instance (cohesive engine-side state)
  type Engine = {
    phase:        Phase,
    need:         Item -> bool,    // flightNeeded / trainTicketNeeded; Hotel always true
    branchDone:   Item -> bool,    // Flight / Train branch reached the parallel join
    status:       Item -> Status,  // shown read-only in "Check Booking Details"
    ref:          Item -> Ref,     // FlightBookingID / TrainBookingID / HotelBookingID
    compSubs:     Set[Item],       // compensation subscriptions (created on completion, removed on throw)
    userCanceled: bool,            // user has chosen "No" (cancel) at least once
  }

  /// supplier-side world (abstract ledger) -- what really exists at the providers
  type Supplier = {
    active:     Item -> Set[Ref],  // currently valid bookings
    everBooked: Item -> Set[Ref],  // every booking ever created
    nextRef:    Ref,               // fresh-reference generator
    down:       Item -> bool,      // permanently refuses bookings
    cancelDown: Item -> bool,      // permanently refuses cancellations
  }

  // ───────────────────────────────── State ───────────────────────────────────
  var engine:    Engine
  var tasks:     TaskKind -> TaskState   // engine external-task table (shared with workers)
  var supplier:  Supplier
  var lastEvent: Event

  // ──────────────────────────────── Constants ────────────────────────────────
  pure val ITEMS: Set[Item] = Set(Flight, Train, Hotel)
  pure val BOOLS: Set[bool] = Set(true, false)
  pure val TASK_KINDS: Set[TaskKind] = ITEMS.map(i => Book(i)).union(ITEMS.map(i => Cancel(i)))
  pure val NO_REF: Ref = 0
  pure val NO_LOCK: LockInfo = { sideEffectDone: false, targetRef: NO_REF, returnRef: NO_REF }

  // ─────────────────────────────── Helpers ───────────────────────────────────
  pure def itemOf(k: TaskKind): Item = match k { | Book(i) => i | Cancel(i) => i }
  pure def isBook(k: TaskKind): bool = match k { | Book(_) => true | Cancel(_) => false }
  pure def isLocked(t: TaskState): bool = match t { | Locked(_) => true | _ => false }
  pure def lockOf(t: TaskState): LockInfo = match t { | Locked(l) => l | _ => NO_LOCK }
  pure def isPending(t: TaskState): bool = t != Absent

  // ────────────────────────────── Initialisation ─────────────────────────────
  /// start event listener sets all *BookingStatus = "No Booking Made";
  /// parallel split: each XOR either creates the booking task or goes straight to the join.
  pure def initEngine(need: Item -> bool): Engine = {
    phase:        Booking,
    need:         need,
    branchDone:   ITEMS.mapBy(i => if (i == Hotel) false else not(need.get(i))),
    status:       ITEMS.mapBy(_ => NoBooking),
    ref:          ITEMS.mapBy(_ => NO_REF),
    compSubs:     Set(),
    userCanceled: false,
  }

  pure def initTasks(need: Item -> bool): TaskKind -> TaskState =
    TASK_KINDS.mapBy(k => match k {
      | Book(i) =>
          if (i == Hotel)
            (if (not(need.get(Flight)) and not(need.get(Train))) Available else Absent)
          else
            (if (need.get(i)) Available else Absent)
      | Cancel(_) => Absent
    })

  pure def initSupplier(down: Item -> bool, cancelDown: Item -> bool): Supplier = {
    active:     ITEMS.mapBy(_ => Set()),
    everBooked: ITEMS.mapBy(_ => Set()),
    nextRef:    1,
    down:       down,
    cancelDown: cancelDown,
  }

  // ─────────────────────── Worker side: fetch / handler ──────────────────────
  pure def canFetch(ts: TaskKind -> TaskState, k: TaskKind): bool =
    ts.get(k) == Available

  /// fetchAndLock; for Cancel tasks the input mapping ${XBookingID} is resolved here
  pure def applyFetch(ts: TaskKind -> TaskState, e: Engine, k: TaskKind): TaskKind -> TaskState =
    ts.set(k, Locked({ ...NO_LOCK, targetRef: if (isBook(k)) NO_REF else e.ref.get(itemOf(k)) }))

  /// handler can call the supplier (not yet done, supplier not permanently down)
  pure def canSideEffect(ts: TaskKind -> TaskState, s: Supplier, k: TaskKind): bool = and {
    isLocked(ts.get(k)),
    not(lockOf(ts.get(k)).sideEffectDone),
    if (isBook(k)) not(s.down.get(itemOf(k))) else not(s.cancelDown.get(itemOf(k))),
  }

  /// booking reference the handler creates at the supplier vs. the one it reports to the engine
  pure def bookedRefOf(s: Supplier): Ref = s.nextRef
  pure def returnedRefOf(s: Supplier, i: Item, refBug: bool): Ref =
    if (refBug and i == Flight) s.nextRef + 1 else s.nextRef

  pure def applyBookAtSupplier(s: Supplier, i: Item, refBug: bool): Supplier = {
    val r = bookedRefOf(s)
    { ...s,
      active:     s.active.setBy(i, rs => rs.union(Set(r))),
      everBooked: s.everBooked.setBy(i, rs => rs.union(Set(r))),
      // the buggy Flight handler draws a second UUID that is never booked
      nextRef:    if (refBug and i == Flight) s.nextRef + 2 else s.nextRef + 1,
    }
  }

  pure def applyCancelAtSupplier(s: Supplier, i: Item, target: Ref): Supplier =
    { ...s, active: s.active.setBy(i, rs => rs.exclude(Set(target))) }

  pure def markSideEffect(ts: TaskKind -> TaskState, k: TaskKind, returnRef: Ref): TaskKind -> TaskState =
    ts.set(k, Locked({ ...lockOf(ts.get(k)), sideEffectDone: true, returnRef: returnRef }))

  /// handler throws before the supplier call: client only emits handler:error (no handleFailure),
  /// the lock expires and the task is fetchable again -- retries never decrease, no incident.
  pure def canHandlerFail(ts: TaskKind -> TaskState, k: TaskKind, allowBook: bool, allowCancel: bool): bool = and {
    isLocked(ts.get(k)),
    not(lockOf(ts.get(k)).sideEffectDone),
    if (isBook(k)) allowBook else allowCancel,
  }

  /// worker crash / lock expiry AFTER the supplier call, before complete()
  pure def canLockExpire(ts: TaskKind -> TaskState, k: TaskKind, allowRedelivery: bool): bool = and {
    allowRedelivery,
    isLocked(ts.get(k)),
    lockOf(ts.get(k)).sideEffectDone,
  }

  pure def applyUnlock(ts: TaskKind -> TaskState, k: TaskKind): TaskKind -> TaskState =
    ts.set(k, Available)

  pure def canComplete(ts: TaskKind -> TaskState, k: TaskKind): bool = and {
    isLocked(ts.get(k)),
    lockOf(ts.get(k)).sideEffectDone,
  }

  // ─────────────────────── Engine side: complete() effects ───────────────────
  /// Book X completed: *Status=Confirmed, *BookingID=returned ref, compensation subscription created,
  /// branch reaches the join; Hotel completion opens "Check Booking Details".
  pure def applyBookComplete(e: Engine, i: Item, returnRef: Ref): Engine = {
    ...e,
    status:     e.status.set(i, Confirmed),
    ref:        e.ref.set(i, returnRef),
    compSubs:   e.compSubs.union(Set(i)),
    branchDone: if (i == Hotel) e.branchDone else e.branchDone.set(i, true),
    phase:      if (i == Hotel) Review else e.phase,
  }

  /// parallel join Gateway_1hfufm4: Book Hotel is created once both branches arrived
  pure def tasksAfterBookComplete(ts: TaskKind -> TaskState, e1: Engine, i: Item): TaskKind -> TaskState = {
    val t1 = ts.set(Book(i), Absent)
    if (i != Hotel and e1.branchDone.get(Flight) and e1.branchDone.get(Train))
      t1.set(Book(Hotel), Available)
    else t1
  }

  pure def allCancelsDone(ts: TaskKind -> TaskState): bool =
    ITEMS.forall(i => ts.get(Cancel(i)) == Absent)

  /// Cancel X completed: *Status=Canceled; when every compensation handler finished the throw
  /// event is left and Flow_0u9r45z leads BACK to "Check Booking Details".
  pure def applyCancelComplete(e: Engine, i: Item, ts1: TaskKind -> TaskState): Engine = {
    ...e,
    status: e.status.set(i, Canceled),
    phase:  if (allCancelsDone(ts1)) Review else Compensating,
  }

  // ───────────────────────── User task: Check Booking Details ────────────────
  pure def canUserDecide(e: Engine): bool = e.phase == Review

  /// confirm == true -> Flow_00gdo4p -> end event
  pure def applyConfirm(e: Engine): Engine = { ...e, phase: Ended }

  /// confirm == false -> compensation throw. Every subscription is triggered once and removed.
  /// With no subscriptions left (second "No"), the throw completes immediately -> back to Review.
  pure def applyUserCancel(e: Engine): Engine = {
    ...e,
    phase:        if (e.compSubs == Set()) Review else Compensating,
    compSubs:     Set(),
    userCanceled: true,
  }

  pure def tasksAfterUserCancel(ts: TaskKind -> TaskState, subs: Set[Item]): TaskKind -> TaskState =
    subs.fold(ts, (t, i) => t.set(Cancel(i), Available))

  // ───────────────────────────────── Actions ─────────────────────────────────
  action initWith(need: Item -> bool, down: Item -> bool, cancelDown: Item -> bool): bool = all {
    engine'    = initEngine(need),
    tasks'     = initTasks(need),
    supplier'  = initSupplier(down, cancelDown),
    lastEvent' = Started,
  }

  action init: bool = {
    nondet needFlight = BOOLS.oneOf()
    nondet needTrain  = BOOLS.oneOf()
    nondet down       = ITEMS.setOfMaps(if (ALLOW_BOOK_FAILURE) BOOLS else Set(false)).oneOf()
    nondet cancelDown = ITEMS.setOfMaps(if (ALLOW_CANCEL_FAILURE) BOOLS else Set(false)).oneOf()
    initWith(Map(Flight -> needFlight, Train -> needTrain, Hotel -> true), down, cancelDown)
  }

  action fetchAndLock(k: TaskKind): bool = all {
    canFetch(tasks, k),
    tasks'     = applyFetch(tasks, engine, k),
    engine'    = engine,
    supplier'  = supplier,
    lastEvent' = Fetched(k),
  }

  action bookAtSupplier(k: TaskKind): bool = all {
    isBook(k),
    canSideEffect(tasks, supplier, k),
    tasks'     = markSideEffect(tasks, k, returnedRefOf(supplier, itemOf(k), FLIGHT_REF_BUG)),
    supplier'  = applyBookAtSupplier(supplier, itemOf(k), FLIGHT_REF_BUG),
    engine'    = engine,
    lastEvent' = SideEffect(k),
  }

  action cancelAtSupplier(k: TaskKind): bool = all {
    not(isBook(k)),
    canSideEffect(tasks, supplier, k),
    tasks'     = markSideEffect(tasks, k, NO_REF),
    supplier'  = applyCancelAtSupplier(supplier, itemOf(k), lockOf(tasks.get(k)).targetRef),
    engine'    = engine,
    lastEvent' = SideEffect(k),
  }

  action handlerFails(k: TaskKind): bool = all {
    canHandlerFail(tasks, k, ALLOW_BOOK_FAILURE, ALLOW_CANCEL_FAILURE),
    tasks'     = applyUnlock(tasks, k),
    engine'    = engine,
    supplier'  = supplier,
    lastEvent' = HandlerFailed(k),
  }

  action lockExpires(k: TaskKind): bool = all {
    canLockExpire(tasks, k, ALLOW_REDELIVERY),
    tasks'     = applyUnlock(tasks, k),
    engine'    = engine,
    supplier'  = supplier,
    lastEvent' = LockExpired(k),
  }

  action completeBook(k: TaskKind): bool = {
    val i  = itemOf(k)
    val e1 = applyBookComplete(engine, i, lockOf(tasks.get(k)).returnRef)
    all {
      isBook(k),
      canComplete(tasks, k),
      engine'    = e1,
      tasks'     = tasksAfterBookComplete(tasks, e1, i),
      supplier'  = supplier,
      lastEvent' = Completed(k),
    }
  }

  action completeCancel(k: TaskKind): bool = {
    val i   = itemOf(k)
    val ts1 = tasks.set(k, Absent)
    all {
      not(isBook(k)),
      canComplete(tasks, k),
      engine'    = applyCancelComplete(engine, i, ts1),
      tasks'     = ts1,
      supplier'  = supplier,
      lastEvent' = Completed(k),
    }
  }

  action userConfirms: bool = all {
    canUserDecide(engine),
    engine'    = applyConfirm(engine),
    tasks'     = tasks,
    supplier'  = supplier,
    lastEvent' = UserConfirmed,
  }

  action userCancels: bool = all {
    canUserDecide(engine),
    engine'    = applyUserCancel(engine),
    tasks'     = tasksAfterUserCancel(tasks, engine.compSubs),
    supplier'  = supplier,
    lastEvent' = UserCanceled,
  }

  /// nondet picks only among task kinds for which the action is enabled
  action step: bool = any {
    { nondet k = TASK_KINDS.filter(k => canFetch(tasks, k)).oneOf()
      fetchAndLock(k) },
    { nondet k = TASK_KINDS.filter(k => isBook(k) and canSideEffect(tasks, supplier, k)).oneOf()
      bookAtSupplier(k) },
    { nondet k = TASK_KINDS.filter(k => not(isBook(k)) and canSideEffect(tasks, supplier, k)).oneOf()
      cancelAtSupplier(k) },
    { nondet k = TASK_KINDS.filter(k => canHandlerFail(tasks, k, ALLOW_BOOK_FAILURE, ALLOW_CANCEL_FAILURE)).oneOf()
      handlerFails(k) },
    { nondet k = TASK_KINDS.filter(k => canLockExpire(tasks, k, ALLOW_REDELIVERY)).oneOf()
      lockExpires(k) },
    { nondet k = TASK_KINDS.filter(k => isBook(k) and canComplete(tasks, k)).oneOf()
      completeBook(k) },
    { nondet k = TASK_KINDS.filter(k => not(isBook(k)) and canComplete(tasks, k)).oneOf()
      completeCancel(k) },
    userConfirms,
    userCancels,
  }

  // ═══════════════════════════ Business rules (BR1–BR8) ═══════════════════════
  def needs(i: Item): bool = engine.need.get(i)
  def activeOf(i: Item): Set[Ref] = supplier.active.get(i)

  /// every needed item is Confirmed in the process AND really held at the supplier
  val fullyBooked: bool = ITEMS.forall(i =>
    if (needs(i)) engine.status.get(i) == Confirmed and activeOf(i) == Set(engine.ref.get(i))
    else activeOf(i) == Set())
  val nothingBooked: bool = ITEMS.forall(i => activeOf(i) == Set())

  /// BR1 — ending via "confirm" means the trip is fully booked (Q5(b): confirm-after-cancel is a violation)
  val BR1_confirmedEndIsFullyBooked: bool =
    engine.phase == Ended implies fullyBooked

  /// BR2 — once compensation finished (back at Review or Ended), nothing is held at any supplier
  val BR2_noOrphanAfterCompensation: bool =
    (engine.userCanceled and (engine.phase == Review or engine.phase == Ended)) implies nothingBooked

  /// BR3 — never book an item the user did not request
  val BR3_noUnrequestedBooking: bool =
    ITEMS.forall(i => supplier.everBooked.get(i) != Set() implies needs(i))

  /// BR4 — at most one valid booking per item at the supplier (no duplicates)
  val BR4_atMostOneActiveBooking: bool =
    ITEMS.forall(i => activeOf(i).size() <= 1)

  /// BR5 — what "Check Booking Details" shows equals supplier reality (checked when shown, Q13(a))
  val BR5_displayMatchesSupplier: bool =
    engine.phase == Review implies ITEMS.forall(i =>
      activeOf(i) == (if (engine.status.get(i) == Confirmed) Set(engine.ref.get(i)) else Set()))

  /// BR6 — a cancellation addresses the booking that was actually made
  val BR6_cancelTargetsRealBooking: bool =
    ITEMS.forall(i => engine.status.get(i) == Canceled implies supplier.everBooked.get(i).contains(engine.ref.get(i)))

  /// BR7 — saga atomicity at the end: all-or-nothing
  val BR7_endIsAllOrNothing: bool =
    engine.phase == Ended implies (fullyBooked or nothingBooked)

  /// a pending task whose supplier refuses forever -> the token can never move on
  def taskBlockedForever(k: TaskKind): bool = and {
    isPending(tasks.get(k)),
    not(lockOf(tasks.get(k)).sideEffectDone),
    if (isBook(k)) supplier.down.get(itemOf(k)) else supplier.cancelDown.get(itemOf(k)),
  }

  /// BR8 — the process never gets permanently stuck while holding bookings
  /// (in Booking the user cannot reach the cancel decision; in Compensating the throw waits forever)
  val BR8_neverStuckHoldingBookings: bool =
    not(and {
      engine.phase == Booking or engine.phase == Compensating,
      TASK_KINDS.exists(k => taskBlockedForever(k)),
      ITEMS.exists(i => activeOf(i) != Set()),
    })

  val allInvariants: bool = and {
    BR1_confirmedEndIsFullyBooked, BR2_noOrphanAfterCompensation, BR3_noUnrequestedBooking,
    BR4_atMostOneActiveBooking, BR5_displayMatchesSupplier, BR6_cancelTargetsRealBooking,
    BR7_endIsAllOrNothing, BR8_neverStuckHoldingBookings,
  }

  // ═════════════════════════════ Witnesses (reachability) ═════════════════════
  pure def evFetched(ev: Event): bool       = match ev { | Fetched(_) => true | _ => false }
  pure def evHandlerFailed(ev: Event): bool = match ev { | HandlerFailed(_) => true | _ => false }
  pure def evLockExpired(ev: Event): bool   = match ev { | LockExpired(_) => true | _ => false }

  val w_fetched:            bool = evFetched(lastEvent)
  val w_flightBooked:       bool = supplier.everBooked.get(Flight) != Set()
  val w_trainBooked:        bool = supplier.everBooked.get(Train) != Set()
  val w_hotelBooked:        bool = supplier.everBooked.get(Hotel) != Set()
  val w_reviewReached:      bool = engine.phase == Review
  val w_compensating:       bool = engine.phase == Compensating
  val w_cancelAtSupplier:   bool = ITEMS.exists(i => engine.status.get(i) == Canceled)
  val w_backToReview:       bool = engine.userCanceled and engine.phase == Review
  val w_endedConfirmed:     bool = engine.phase == Ended and not(engine.userCanceled)
  val w_endedAfterCancel:   bool = engine.phase == Ended and engine.userCanceled
  val w_handlerFailed:      bool = evHandlerFailed(lastEvent)
  val w_lockExpired:        bool = evLockExpired(lastEvent)
  val w_duplicateBooking:   bool = ITEMS.exists(i => supplier.everBooked.get(i).size() >= 2)
  val w_noTransportNeeded:  bool = not(needs(Flight)) and not(needs(Train)) and w_hotelBooked
}
