// CE-2 (BR4, BR5, BR2, BR7): the handlers are not idempotent.
//
// specs/quint/REPORT.md  CE-2  ·  specs/lean/REPORT.md  A2 (ce2_redelivery_duplicate), C2
//
// An external task is delivered at-least-once: when `complete()` fails or the lock expires after
// the supplier call, the same task is fetched again and the handler runs a second time. Each
// handler mints a fresh UUID per run, so a second run books a second time and only the last ID is
// known to the process — the earlier booking can never be compensated.
//
// Business rule asserted: running the same task twice must report the same booking ID.

import test from 'node:test';
import assert from 'node:assert/strict';
import { WORKERS, loadWorker, makeTask, makeTaskService, runHandler } from './helpers/worker-sandbox.mjs';

for (const w of WORKERS) {
  test(`CE-2 (BR4): ${w.book} must report the same ${w.idVar} when the task is executed twice`,
    { todo: `CE-2: ${w.file} mints a new UUID per execution; redelivery books twice` },
    async () => {
      const { handlers } = loadWorker(w.file);
      const handler = handlers.get(w.book);

      // first delivery
      const first = makeTaskService();
      assert.equal((await runHandler(handler, makeTask({ id: 't-1' }), first)).threw, null);
      // second delivery of the SAME task (crash / lock expiry / failed complete — see R1 ≡ CE-6)
      const second = makeTaskService();
      assert.equal((await runHandler(handler, makeTask({ id: 't-1' }), second)).threw, null);

      const firstId = first.calls[0]?.variables?.[w.idVar];
      const secondId = second.calls[0]?.variables?.[w.idVar];
      assert.ok(firstId && secondId, 'both executions should complete with a booking ID');
      assert.equal(secondId, firstId,
        `${w.idVar} changed between two deliveries of the same task ` +
        `(${firstId} → ${secondId}), so the supplier was booked twice`);
    });
}
