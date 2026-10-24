// CE-5 (BR5, BR6, BR2, BR7): the flight worker reports a different ID from the one it booked.
//
// specs/quint/REPORT.md  CE-5  ·  specs/lean/REPORT.md  A5 (ce5_flight_ref_mismatch), C3
//
// FlightBooking.js:19-21 creates `id`, logs it ("Flight booking was finished: <id>") and then puts
// a *second* create_UUID() into FlightBookingID. CancelFlightBooking later cancels the ID the
// process knows, i.e. one that was never booked, so the real flight is never released. Train and
// Hotel use the same `id` for both — they are the control group and must stay green.
//
// Business rule asserted: the booking reference reported to the process (BR5/BR6) must be the one
// the handler actually booked.

import test from 'node:test';
import assert from 'node:assert/strict';
import { WORKERS, loadWorker, makeTask, makeTaskService, runHandler } from './helpers/worker-sandbox.mjs';

const byItem = Object.fromEntries(WORKERS.map((w) => [w.item, w]));
const flight = byItem.Flight;

test('CE-5 (BR5/BR6): BookFlight must report the ID it actually booked',
  async () => {
    const { handlers, logs } = loadWorker(flight.file);
    const ts = makeTaskService();
    assert.equal((await runHandler(handlers.get(flight.book), makeTask(), ts)).threw, null);

    const reported = ts.calls[0]?.variables?.[flight.idVar];
    const booked = logs.map((line) => flight.finishedLog.exec(line)?.[1]).find(Boolean);

    assert.ok(reported, 'BookFlight must report FlightBookingID');
    assert.ok(booked, 'BookFlight must log the booking ID of the flight it booked');
    assert.equal(reported, booked,
      `FlightBookingID is ${reported} but the booked (logged) flight is ${booked}: ` +
      'CancelFlightBooking will cancel an ID that was never booked');
  });

for (const item of ['Train', 'Hotel']) {
  const w = byItem[item];
  test(`CE-5 control: ${w.book} reports the ID it actually booked (already correct)`, async () => {
    const { handlers, logs } = loadWorker(w.file);
    const ts = makeTaskService();
    assert.equal((await runHandler(handlers.get(w.book), makeTask(), ts)).threw, null);

    const reported = ts.calls[0]?.variables?.[w.idVar];
    const booked = logs.map((line) => w.finishedLog.exec(line)?.[1]).find(Boolean);
    assert.ok(reported && booked);
    assert.equal(reported, booked, `${w.idVar} must equal the logged booking id`);
  });
}
