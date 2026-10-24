// Library contract: the facts the counterexample analysis relies on, asserted against the real
// camunda-external-task-client-js 2.3.1 that the workers use (not against a mock).
//
// These tests PASS today — they document the library behaviour that makes CE-2/CE-3/CE-6/R1
// possible. If a future version changes this contract, the reasoning in
// specs/quint/REPORT.md (F7/F8) and specs/lean/REPORT.md (R1) must be revisited.

import test from 'node:test';
import assert from 'node:assert/strict';
import * as esm from 'camunda-external-task-client-js';

// Node's CJS named-export detection only surfaces part of this package; the full module.exports
// object is the default export.
const lib = esm.default ?? esm;
const { Client, Variables } = lib;

const BASE = { baseUrl: 'http://127.0.0.1:1/engine-rest', autoPoll: false };

test('library: a Client without config.workerId falls back to the shared default', () => {
  const client = new Client({ ...BASE });
  try {
    assert.equal(client.options.workerId, 'some-random-id',
      'every worker that omits workerId shares this id — the basis of R1');
    assert.equal(client.options.lockDuration, 50000, 'the default lock duration is 50 s');
    assert.equal(client.options.maxTasks, 10);
  } finally {
    client.stop();
  }
});

test('library (F7): a throwing handler only emits "handler:error" — handleFailure is not called', async () => {
  const client = new Client({ ...BASE });
  const emitted = [];
  client.on('handler:error', () => emitted.push('handler:error'));
  client.on('handler:success', () => emitted.push('handler:success'));

  const failureCalls = [];
  client.taskService.handleFailure = async (...args) => { failureCalls.push(args); };

  client.subscribe('SomeTopic', async () => { throw new Error('supplier call failed'); });
  // executeTask is what the poll loop calls for every fetched task
  await client.executeTask({ id: 't1', topicName: 'SomeTopic', variables: {} });
  client.stop();

  assert.deepEqual(emitted, ['handler:error'],
    'the handler error is reported only as an event; nothing is sent to the engine');
  assert.equal(failureCalls.length, 0,
    'the client never calls handleFailure on its own, so retries never decrease and no incident ' +
    'is raised (CE-3 / CE-4)');
});

test('library (R1/CE-6): TaskService#complete swallows a rejected completion', async () => {
  const client = new Client({ ...BASE });
  const emitted = [];
  client.on('complete:error', () => emitted.push('complete:error'));
  client.on('complete:success', () => emitted.push('complete:success'));
  const sent = [];
  client.taskService.api = {
    complete: async (body) => {
      sent.push(body);
      throw new Error('OptimisticLockingException: concurrent modification');
    },
  };

  // The worker awaits this, then carries on as if the booking were recorded: the engine keeps the
  // task locked, the lock expires and the handler is executed again.
  await assert.doesNotReject(client.taskService.complete({ id: 't1' }),
    'complete() must not reject — the worker cannot observe the failure');
  client.stop();

  assert.equal(sent.length, 1, 'the request was attempted once');
  assert.deepEqual(emitted, ['complete:error'],
    'the rejection is only emitted as an event; nothing reaches the worker');
});

test('library: TaskService#complete forwards dirty variables on success', async () => {
  const client = new Client({ ...BASE });
  const sent = [];
  client.taskService.api = { complete: async (body) => { sent.push(body); } };

  const variables = new Variables();
  variables.set('FlightBookingID', 'booking-1');
  await client.taskService.complete({ id: 't1' }, variables);
  client.stop();

  assert.deepEqual(sent, [{
    id: 't1',
    variables: { FlightBookingID: { type: 'string', value: 'booking-1', valueInfo: {} } },
  }], 'this is how the ProcessVariables of a booking reach the engine');
});
