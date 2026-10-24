// CE-1 (BR1): "cancel" and "confirm" are not distinguishable outcomes.
//
// specs/quint/REPORT.md  CE-1  ·  specs/lean/REPORT.md  A1 (ce1_confirm_after_cancel)
//
// After the compensation throw event, Flow_0u9r45z leads BACK to "Check Booking Details", and
// the only end event is reachable only through confirm = true. So a user who canceled, whose
// bookings are all gone, must press "confirm" to finish — and the completed instance looks
// identical to a fully booked trip.
//
// Business rule asserted: choosing "cancel" must lead to an outcome of its own (its own end
// event) without having to pass through the confirm/deny task again.

import test from 'node:test';
import assert from 'node:assert/strict';
import { parseBpmn, compensationThrowEvents, endEventsReachableFrom, confirmBranches }
  from './helpers/bpmn.mjs';

test('CE-1 (BR1): after compensation the process can reach an end event without the confirm task',
  async () => {
    const m = await parseBpmn();
    const throws = compensationThrowEvents(m);
    assert.equal(throws.length, 1, 'V3 should throw compensation exactly once');

    const userTasks = new Set(m.ofType('bpmn:UserTask').map((u) => u.id));
    const ends = endEventsReachableFrom(m, throws[0].id, { stopAt: userTasks });
    assert.notEqual(ends.length, 0,
      `no end event is reachable from ${throws[0].id} without re-entering a user task ` +
      '(the compensation path loops back to "Check Booking Details")');
  });

test('CE-1 (BR1): the cancel branch and the confirm branch reach different end events',
  async () => {
    const m = await parseBpmn();
    const branches = confirmBranches(m);
    assert.ok(branches?.confirm && branches?.cancel,
      'the confirm/deny gateway must have a confirm = true and a not confirm branch');

    const confirmEnds = new Set(endEventsReachableFrom(m, branches.confirm.target));
    const cancelEnds = new Set(endEventsReachableFrom(m, branches.cancel.target));

    assert.notEqual(confirmEnds.size, 0, '"confirm" must end the instance');
    assert.notEqual(cancelEnds.size, 0, '"cancel" must end the instance');
    for (const end of cancelEnds) {
      assert.ok(!confirmEnds.has(end),
        `the cancel branch reaches ${end}, which is also the "trip confirmed" end event`);
    }
  });
