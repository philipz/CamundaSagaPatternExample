// CE-6 (BR4): concurrent completion at the parallel join re-runs a booking even with no outage.
//
// specs/lean/REPORT.md  §4 (CE-6) — found by the adversarial review, *not* by Quint
//
// The external task client swallows a failed complete() (asserted in library-contract.test.mjs:
// TaskService#complete only emits "complete:error"), so the engine keeps the task locked, the
// lock expires, the task is re-fetched and the handler books again. A realistic trigger needs no
// infrastructure fault at all: Book Flight and Book Train finish at the same moment, both
// completions hit the parallel join Gateway_1hfufm4, and one of them is rolled back with an
// OptimisticLockingException.
//
// V2 used camunda:asyncAfter on the Book tasks, which ends the completion transaction before the
// join (the join then runs as its own job and simply retries). V3 changed them all to asyncBefore,
// which is what puts the join inside the external-task completion transaction.
//
// Business rule asserted here: the booking steps that feed the join must not run their completion
// inside the join transaction (camunda:asyncAfter). The other half of the rule — that a retried
// completion must not re-book — is asserted by CE-2's idempotency tests.

import test from 'node:test';
import assert from 'node:assert/strict';
import { parseBpmn, BOOK_TASKS, camundaAttrs } from './helpers/bpmn.mjs';

test('CE-6 (BR4): the bookings feeding the parallel join must not complete inside the join transaction',
  { todo: 'CE-6: Book Flight/Train use camunda:asyncBefore, so a join collision rolls complete() back' },
  async () => {
    const m = await parseBpmn();
    const join = m.ofType('bpmn:ParallelGateway').find((g) => m.incoming(g.id).length === 2);
    assert.ok(join, 'the parallel join must exist');

    // Hotel is booked AFTER the join, so only Flight and Train can race at it.
    for (const t of BOOK_TASKS.filter((x) => x.item !== 'Hotel')) {
      const attrs = camundaAttrs(m.get(t.id));
      assert.equal(attrs.asyncAfter, true,
        `${t.id} (${t.item}) runs its completion in the same transaction as the join ` +
        `(asyncBefore=${attrs.asyncBefore}, asyncAfter=${attrs.asyncAfter}); when the sibling ` +
        'branch completes concurrently the join raises an OptimisticLockingException, the ' +
        'completion is rolled back and the handler books a second time');
    }
  });

test('CE-6 (BR4): V2 (asyncAfter) and V3 (asyncBefore) must not disagree about the join race',
  { todo: 'CE-6: the two models differ exactly on this point; the regression is documented here' },
  async () => {
    const v3 = await parseBpmn();
    const { MODELS_DIR } = await import('./helpers/bpmn.mjs');
    const path = await import('node:path');
    const v2 = await parseBpmn(path.join(MODELS_DIR, 'BookHolidaySagaPatternV2.bpmn'));

    const read = (m) => BOOK_TASKS
      .map((t) => m.get(t.id))
      .filter(Boolean)
      .map((el) => camundaAttrs(el).asyncAfter);

    // The intended design (V2) ends the completion transaction before the join.
    assert.ok(read(v2).some(Boolean), 'V2 is expected to use asyncAfter on the booking tasks');
    assert.deepEqual(read(v3), [true, true, true],
      'V3 should keep the asyncAfter boundary of V2 on all three booking tasks');
  });
