// R1: the three workers share the library's default workerId, so a late `complete()` from a
// "zombie" handler (whose lock had already expired) is accepted by the engine.
//
// specs/quint/REPORT.md §7 (F8)  ·  specs/lean/MODEL-MAP.md (abstraction ledger, "zombie handler")
//
// camunda-external-task-client-js 2.3.1 `Client` defaults to `workerId: "some-random-id"` when the
// config does not set one (lib/Client.js, defaultOptions). All three workers inherit that same
// default, so after a lock expiry the engine cannot tell the original handler from the new one:
// the stale `complete()` succeeds and the re-fetched handler may still go on to book — after
// compensation, or even after the instance ended.
//
// Business rule asserted: every worker must set its own non-empty workerId.

import test from 'node:test';
import assert from 'node:assert/strict';
import { WORKERS, loadWorker } from './helpers/worker-sandbox.mjs';

test('R1: each worker must configure its own workerId (not the library default "some-random-id")',
  { todo: 'R1: none of the workers sets workerId; all three fall back to "some-random-id"' },
  async () => {
    const ids = [];
    for (const w of WORKERS) {
      const { clients } = loadWorker(w.file);
      assert.equal(clients.length, 1, `${w.file} should create exactly one client`);
      const workerId = clients[0].config.workerId;
      assert.equal(typeof workerId, 'string', `${w.file} does not set config.workerId`);
      assert.ok(workerId.length > 0, `${w.file} sets an empty config.workerId`);
      assert.notEqual(workerId, 'some-random-id', `${w.file} relies on the library default workerId`);
      ids.push(workerId);
    }
    assert.equal(new Set(ids).size, ids.length, `workerIds must be unique per worker, got ${ids}`);
  });
