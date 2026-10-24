// -*- mode: Bluespec; -*-
// Deterministic scenarios: the happy path plus a MINIMAL reproduction of every counterexample
// reported in REPORT.md. Run with:  quint test bookHoliday_test.qnt --main=<module>
//
// Fault flags only ENABLE actions; a scripted run chooses its actions explicitly, so the flags do
// not change these scenarios except FLIGHT_REF_BUG (which changes what bookAtSupplier returns).

/// FLIGHT_REF_BUG = false (Flight ref fixed); all fault actions enabled
module bookHoliday_test {
  import bookHoliday(ALLOW_REDELIVERY = true, ALLOW_BOOK_FAILURE = true,
                     ALLOW_CANCEL_FAILURE = true, FLIGHT_REF_BUG = false).* from "./bookHoliday"

  pure val NEED_ALL: Item -> bool = Map(Flight -> true, Train -> true, Hotel -> true)
  pure val NONE: Item -> bool     = Map(Flight -> false, Train -> false, Hotel -> false)

  action bookItem(i: Item): bool =
    fetchAndLock(Book(i)).then(bookAtSupplier(Book(i))).then(completeBook(Book(i)))
  action cancelItem(i: Item): bool =
    fetchAndLock(Cancel(i)).then(cancelAtSupplier(Cancel(i))).then(completeCancel(Cancel(i)))
  action bookAll: bool = bookItem(Train).then(bookItem(Flight)).then(bookItem(Hotel))

  /// baseline: flight + train + hotel, confirm -> every rule holds
  run happyPathTest =
    initWith(NEED_ALL, NONE, NONE)
      .then(bookAll)
      .expect(engine.phase == Review and allInvariants)
      .then(userConfirms)
      .expect(engine.phase == Ended and allInvariants)

  /// only the hotel is needed: both XORs take the default flow, the join fires immediately
  run hotelOnlyTest =
    initWith(Map(Flight -> false, Train -> false, Hotel -> true), NONE, NONE)
      .expect(tasks.get(Book(Hotel)) == Available)
      .then(bookItem(Hotel))
      .then(userConfirms)
      .expect(allInvariants)

  /// CE-1 (BR1): cancel -> compensation is clean -> back at the same user task -> confirm
  /// -> the process ends on the *only* end event, but nothing is booked.
  run ce1_confirmAfterCancelTest =
    initWith(NEED_ALL, NONE, NONE)
      .then(bookAll)
      .then(userCancels)
      .expect(engine.phase == Compensating)
      .then(cancelItem(Hotel)).then(cancelItem(Flight)).then(cancelItem(Train))
      .expect(engine.phase == Review and nothingBooked and BR2_noOrphanAfterCompensation)
      .then(userConfirms)
      .expect(engine.phase == Ended and not(BR1_confirmedEndIsFullyBooked) and BR7_endIsAllOrNothing)

  /// CE-1b: a second "No" is a no-op (subscriptions were consumed): back to Review, no cancel tasks
  run ce1b_secondCancelIsNoopTest =
    initWith(NEED_ALL, NONE, NONE)
      .then(bookAll)
      .then(userCancels)
      .then(cancelItem(Hotel)).then(cancelItem(Flight)).then(cancelItem(Train))
      .then(userCancels)
      .expect(engine.phase == Review and engine.compSubs == Set() and allCancelsDone(tasks))

  /// CE-2 (BR4, BR5, BR2, BR7): BookTrain handler booked, lock expired before complete(),
  /// task re-fetched and booked again -> two train tickets, process knows only the 2nd.
  run ce2_redeliveryDuplicateTest =
    initWith(NEED_ALL, NONE, NONE)
      .then(fetchAndLock(Book(Train)))
      .then(bookAtSupplier(Book(Train)))
      .then(lockExpires(Book(Train)))
      .then(bookItem(Train))
      .expect(not(BR4_atMostOneActiveBooking))
      .then(bookItem(Flight)).then(bookItem(Hotel))
      .expect(engine.phase == Review and not(BR5_displayMatchesSupplier))
      .then(userCancels)
      .then(cancelItem(Hotel)).then(cancelItem(Flight)).then(cancelItem(Train))
      .expect(not(BR2_noOrphanAfterCompensation) and supplier.active.get(Train) == Set(1))
      .then(userConfirms)
      .expect(not(BR7_endIsAllOrNothing))

  /// CE-3 (BR8): flight supplier permanently refuses; the handler throws, the lock expires,
  /// the task is retried forever (retries never decrease, no incident). The train ticket is held
  /// and the user can never reach the cancel decision.
  run ce3_bookFailureStuckTest =
    initWith(NEED_ALL, Map(Flight -> true, Train -> false, Hotel -> false), NONE)
      .then(bookItem(Train))
      .then(fetchAndLock(Book(Flight))).then(handlerFails(Book(Flight)))
      .then(fetchAndLock(Book(Flight))).then(handlerFails(Book(Flight)))
      .expect(and {
        engine.phase == Booking,
        tasks.get(Book(Hotel)) == Absent,
        supplier.active.get(Train) != Set(),
        not(BR8_neverStuckHoldingBookings),
      })

  /// CE-4 (BR8): hotel refuses cancellation permanently; the compensation throw event waits
  /// forever, the hotel booking is never released and the user never sees the form again.
  run ce4_cancelFailureStuckTest =
    initWith(NEED_ALL, NONE, Map(Flight -> false, Train -> false, Hotel -> true))
      .then(bookAll)
      .then(userCancels)
      .then(cancelItem(Flight)).then(cancelItem(Train))
      .then(fetchAndLock(Cancel(Hotel))).then(handlerFails(Cancel(Hotel)))
      .expect(and {
        engine.phase == Compensating,
        supplier.active.get(Hotel) != Set(),
        not(BR8_neverStuckHoldingBookings),
      })
}

/// FLIGHT_REF_BUG = true -- the code as written
module bookHoliday_asIs_test {
  import bookHoliday(ALLOW_REDELIVERY = false, ALLOW_BOOK_FAILURE = false,
                     ALLOW_CANCEL_FAILURE = false, FLIGHT_REF_BUG = true).* from "./bookHoliday"

  pure val NEED_ALL: Item -> bool = Map(Flight -> true, Train -> true, Hotel -> true)
  pure val NONE: Item -> bool     = Map(Flight -> false, Train -> false, Hotel -> false)

  action bookItem(i: Item): bool =
    fetchAndLock(Book(i)).then(bookAtSupplier(Book(i))).then(completeBook(Book(i)))
  action cancelItem(i: Item): bool =
    fetchAndLock(Cancel(i)).then(cancelAtSupplier(Cancel(i))).then(completeCancel(Cancel(i)))

  /// CE-5 (BR5, BR6, BR2, BR7): FlightBooking.js books with `id` but stores another UUID in
  /// FlightBookingID -> CancelFlightBooking cancels a ref that never existed, the real flight stays.
  run ce5_flightRefMismatchTest =
    initWith(Map(Flight -> true, Train -> false, Hotel -> true), NONE, NONE)
      .then(bookItem(Flight))
      .expect(supplier.active.get(Flight) == Set(1) and engine.ref.get(Flight) == 2)
      .then(bookItem(Hotel))
      .expect(engine.phase == Review and not(BR5_displayMatchesSupplier))
      .then(userCancels)
      .then(cancelItem(Hotel)).then(cancelItem(Flight))
      .expect(and {
        engine.status.get(Flight) == Canceled,
        supplier.active.get(Flight) == Set(1),
        not(BR6_cancelTargetsRealBooking),
        not(BR2_noOrphanAfterCompensation),
      })
      .then(userConfirms)
      .expect(not(BR7_endIsAllOrNothing))
}
