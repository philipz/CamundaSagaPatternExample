// -*- mode: Bluespec; -*-
// Concrete, runnable instantiations of bookHoliday. One assumption set per module so that every
// counterexample can be attributed to exactly one assumption (see REPORT.md, matrix).

/// Baseline: perfect infrastructure AND Flight ref bug fixed (only the BPMN logic is under test)
module ideal {
  import bookHoliday(ALLOW_REDELIVERY = false, ALLOW_BOOK_FAILURE = false,
                     ALLOW_CANCEL_FAILURE = false, FLIGHT_REF_BUG = false).* from "./bookHoliday"
}

/// Code as written (FlightBooking.js two-UUID bug) on perfect infrastructure
module asIs {
  import bookHoliday(ALLOW_REDELIVERY = false, ALLOW_BOOK_FAILURE = false,
                     ALLOW_CANCEL_FAILURE = false, FLIGHT_REF_BUG = true).* from "./bookHoliday"
}

/// Q3(a) at-least-once redelivery only
module redelivery {
  import bookHoliday(ALLOW_REDELIVERY = true, ALLOW_BOOK_FAILURE = false,
                     ALLOW_CANCEL_FAILURE = false, FLIGHT_REF_BUG = false).* from "./bookHoliday"
}

/// Q3(b) booking failures only
module bookFailure {
  import bookHoliday(ALLOW_REDELIVERY = false, ALLOW_BOOK_FAILURE = true,
                     ALLOW_CANCEL_FAILURE = false, FLIGHT_REF_BUG = false).* from "./bookHoliday"
}

/// Q3(c) cancellation failures only
module cancelFailure {
  import bookHoliday(ALLOW_REDELIVERY = false, ALLOW_BOOK_FAILURE = false,
                     ALLOW_CANCEL_FAILURE = true, FLIGHT_REF_BUG = false).* from "./bookHoliday"
}

/// Everything at once (code as written + all faults)
module allFaults {
  import bookHoliday(ALLOW_REDELIVERY = true, ALLOW_BOOK_FAILURE = true,
                     ALLOW_CANCEL_FAILURE = true, FLIGHT_REF_BUG = true).* from "./bookHoliday"
}
