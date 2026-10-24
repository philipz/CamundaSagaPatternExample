// Baseline: the parts that are already correct (these must stay green).
// Covers the happy path of every worker and the BR3-relevant structure of V3.

import test from 'node:test';
import assert from 'node:assert/strict';
import { WORKERS, loadWorker, makeTask, makeTaskService, runHandler } from './helpers/worker-sandbox.mjs';
import { parseBpmn, BOOK_TASKS, camundaAttrs, conditionOf, gatewayOn, compensationHandlerOf,
  boundaryEventsOf } from './helpers/bpmn.mjs';

test('baseline: each worker registers exactly its Book* and Cancel* topics', () => {
  for (const w of WORKERS) {
    const { handlers } = loadWorker(w.file);
    assert.deepEqual([...handlers.keys()].sort(), [w.book, w.cancel].sort(),
      `${w.file} should subscribe to ${w.book} and ${w.cancel}`);
  }
});

test('baseline: every Book* handler completes the task with Confirmed and a non-empty ID', async () => {
  for (const w of WORKERS) {
    const { handlers } = loadWorker(w.file);
    const ts = makeTaskService();
    const { threw } = await runHandler(handlers.get(w.book), makeTask({ topicName: w.book }), ts);
    assert.equal(threw, null, `${w.book} handler must not throw on the happy path`);
    assert.equal(ts.calls.length, 1);
    const [{ op, variables }] = ts.calls;
    assert.equal(op, 'complete');
    assert.equal(variables[w.statusVar], 'Confirmed');
    assert.match(variables[w.idVar] ?? '', /^[0-9a-f-]{36}$/, `${w.idVar} must be a UUID`);
  }
});

test('baseline: every Cancel* handler completes the task with Canceled and does not throw', async () => {
  for (const w of WORKERS) {
    const { handlers } = loadWorker(w.file);
    const ts = makeTaskService();
    const task = makeTask({ topicName: w.cancel, variables: { [w.idVar]: 'booking-1' } });
    const { threw } = await runHandler(handlers.get(w.cancel), task, ts);
    assert.equal(threw, null, `${w.cancel} handler must not throw on the happy path`);
    assert.equal(ts.calls.length, 1);
    assert.equal(ts.calls[0].op, 'complete');
    assert.equal(ts.calls[0].variables[w.statusVar], 'Canceled');
  }
});

test('baseline (BR3): V3 only creates a booking task when the user requested it', async () => {
  const m = await parseBpmn();
  const flightGw = gatewayOn(m, 'flightNeeded');
  const trainGw = gatewayOn(m, 'trainTicketNeeded');
  assert.ok(flightGw, 'a gateway conditioned on flightNeeded must exist');
  assert.ok(trainGw, 'a gateway conditioned on trainTicketNeeded must exist');

  const flightYes = m.outgoing(flightGw.id).find((f) => (conditionOf(f) ?? '').includes('flightNeeded'));
  const trainYes = m.outgoing(trainGw.id).find((f) => (conditionOf(f) ?? '').includes('trainTicketNeeded'));
  assert.match(conditionOf(flightYes), /flightNeeded\s*==\s*true/);
  assert.match(conditionOf(trainYes), /trainTicketNeeded\s*==\s*true/);
  // the "no" branch is the gateway default flow, so an unrequested item cannot reach its Book task
  assert.ok(m.outgoing(flightGw.id).some((f) => f.id === (flightGw.default?.id ?? flightGw.default)),
    'the flight gateway needs a default ("no") flow');
  assert.ok(m.outgoing(trainGw.id).some((f) => f.id === (trainGw.default?.id ?? trainGw.default)),
    'the train gateway needs a default ("no") flow');
  // and the default flows must not reach the Book tasks
  for (const [gw, bookId] of [[flightGw, 'Activity_0fy5rid'], [trainGw, 'Activity_1ju8g5e']]) {
    const defaultFlow = m.outgoing(gw.id).find((f) => f.id === (gw.default?.id ?? gw.default));
    assert.notEqual(typeof defaultFlow.targetRef === 'string' ? defaultFlow.targetRef : defaultFlow.targetRef.id,
      bookId, 'the default branch must not lead to the Book task');
  }
});

test('baseline: V3 wires a compensation handler with the matching Cancel* topic to every Book task', async () => {
  const m = await parseBpmn();
  for (const t of BOOK_TASKS) {
    const task = m.get(t.id);
    assert.equal(camundaAttrs(task).topic, t.topic, `${t.id} should be an external task on ${t.topic}`);

    const handlers = boundaryEventsOf(m, t.id);
    assert.ok(handlers.some((b) => b.defs.includes('bpmn:CompensateEventDefinition')),
      `${t.id} needs a compensation boundary event`);

    const handler = compensationHandlerOf(m, t.id);
    assert.ok(handler, `${t.id} needs a compensation handler wired by association`);
    const attrs = camundaAttrs(handler);
    assert.equal(attrs.topic, t.cancelTopic, `compensation of ${t.item} should use ${t.cancelTopic}`);
    assert.equal(attrs.isForCompensation, true);
  }
});

test('baseline: V3 splits and joins the three bookings in parallel', async () => {
  const m = await parseBpmn();
  const parallels = m.ofType('bpmn:ParallelGateway');
  assert.equal(parallels.length, 2, 'one parallel split and one parallel join');
  const split = parallels.find((g) => m.outgoing(g.id).length === 2);
  const join = parallels.find((g) => m.incoming(g.id).length === 2);
  assert.ok(split && join, 'a split with 2 outgoing and a join with 2 incoming flows are required');
  assert.ok(split.id !== join.id);
});
