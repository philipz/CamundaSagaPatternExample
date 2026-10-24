// CE-4 (BR8): a failing cancellation handler is never reported, so compensation hangs forever.
//
// specs/quint/REPORT.md  CE-4  ·  specs/lean/REPORT.md  A4 (ce4_cancel_failure_stuck)
//
// Camunda 7 leaves an intermediate compensation throw event only after every compensation
// handler has completed. Because the Cancel* handlers have no error handling, a permanent
// cancellation failure means the throw event waits forever: the booking is never released, the
// user never sees the task again and no incident is raised for an operator.
//
// Business rule asserted: a Cancel* handler must report a failure with handleFailure and a
// *decreased* retry count, so the engine eventually raises an incident for a human.

import test from 'node:test';
import assert from 'node:assert/strict';
import { WORKERS, loadWorker, makeTask, makeTaskService, runHandler } from './helpers/worker-sandbox.mjs';

for (const w of WORKERS) {
  test(`CE-4 (BR8): a failing ${w.cancel} handler must call handleFailure with fewer retries`,
    async () => {
      const { handlers } = loadWorker(w.file, { failOnSet: true });
      const ts = makeTaskService();
      const task = makeTask({
        topicName: w.cancel, retries: 3, variables: { [w.idVar]: 'booking-1' },
      });
      const { threw } = await runHandler(handlers.get(w.cancel), task, ts);

      const failure = ts.calls.find((c) => c.op === 'handleFailure');
      assert.ok(failure,
        `${w.cancel} let the error escape (${threw?.message ?? 'no error?'}) without calling ` +
        'handleFailure, so the compensation throw event waits forever and no incident is raised');
      const opts = failure.args[0] ?? {};
      assert.equal(opts.retries, 2, 'handleFailure must decrease the retry count (3 → 2)');
      assert.ok(!ts.calls.some((c) => c.op === 'complete'),
        'a failed cancellation must not be reported as completed');
    });
}
