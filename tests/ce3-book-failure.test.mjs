// CE-3 (BR8): a failing booking handler is never reported, so the task is retried forever.
//
// specs/quint/REPORT.md  CE-3  ·  specs/lean/REPORT.md  A3 (ce3_book_failure_stuck), C4
//
// camunda-external-task-client-js 2.3.1 (`Client#executeTask`) only emits "handler:error" when the
// handler throws: it does not call handleFailure, so `retries` never decreases, no incident is
// created and the task stays locked/expired in a loop. The token never reaches the user task, so
// the user cannot even cancel, and the bookings already made stay held.
//
// Business rule asserted:
//   * a Book* handler must report any failure to the engine (handleFailure / handleBpmnError)
//     instead of letting it escape into the client;
//   * the BPMN must give the booking steps a failure path (error boundary event) so that a
//     failed booking is compensated instead of blocking the saga.

import test from 'node:test';
import assert from 'node:assert/strict';
import { WORKERS, loadWorker, makeTask, makeTaskService, runHandler } from './helpers/worker-sandbox.mjs';
import { parseBpmn, BOOK_TASKS, boundaryEventsOf, camundaAttrs } from './helpers/bpmn.mjs';

for (const w of WORKERS) {
  test(`CE-3 (BR8): a failing ${w.book} handler must report the failure to the engine`,
    { todo: `CE-3: ${w.file} has no try/catch; the error escapes into the client, which swallows it` },
    async () => {
      // failure injected where the handler calls out to the supplier
      const { handlers } = loadWorker(w.file, { failOnSet: true });
      const ts = makeTaskService();
      const task = makeTask({ topicName: w.book, retries: 3 });
      const { threw } = await runHandler(handlers.get(w.book), task, ts);

      const reported = ts.calls.some((c) => c.op === 'handleFailure' || c.op === 'handleBpmnError');
      assert.ok(reported,
        `${w.book} let the error escape (${threw?.message ?? 'no error?'}) without calling ` +
        'handleFailure/handleBpmnError, so the engine never learns the booking failed');
      assert.ok(!ts.calls.some((c) => c.op === 'complete'),
        'a failed handler must not complete the task');
    });
}

test('CE-3 (BR8): the booking steps need a failure path (error boundary event or error subprocess)',
  { todo: 'CE-3: Book tasks only carry compensation boundary events; no error event, no subprocess' },
  async () => {
    const m = await parseBpmn();
    const subprocessesWithError = m.ofType('bpmn:SubProcess').filter((sp) =>
      boundaryEventsOf(m, sp.id).some((b) => b.defs.includes('bpmn:ErrorEventDefinition')));
    for (const t of BOOK_TASKS) {
      const own = boundaryEventsOf(m, t.id).some((b) => b.defs.includes('bpmn:ErrorEventDefinition'));
      assert.ok(own || subprocessesWithError.length > 0,
        `${t.id} (${t.item}) has no error boundary event and is not inside a subprocess with one, ` +
        'so a failed booking leaves the saga stuck instead of triggering compensation');
      assert.equal(camundaAttrs(m.get(t.id)).isExternal, true);
    }
  });
