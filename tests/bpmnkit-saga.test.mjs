import test from 'node:test';
import assert from 'node:assert/strict';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { loadBpmnForBpmnKit } from './helpers/bpmnkit.mjs';

const REPO_ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const V3_PATH = path.join(REPO_ROOT, 'Models', 'BookHolidaySagaPatternV3.bpmn');

function setupTestWorkers(engine, tracker = []) {
  engine.registerJobWorker('BookFlight', (job) => {
    tracker.push({ action: 'BookFlight', vars: { ...job.variables } });
    job.complete({
      FlightBookingStatus: 'Confirmed',
      FlightBookingID: 'flight-uuid-1',
    });
  });

  engine.registerJobWorker('BookTrain', (job) => {
    tracker.push({ action: 'BookTrain', vars: { ...job.variables } });
    job.complete({
      TrainBookingStatus: 'Confirmed',
      TrainBookingID: 'train-uuid-2',
    });
  });

  engine.registerJobWorker('BookHotel', (job) => {
    tracker.push({ action: 'BookHotel', vars: { ...job.variables } });
    job.complete({
      HotelBookingStatus: 'Confirmed',
      HotelBookingID: 'hotel-uuid-3',
    });
  });

  engine.registerJobWorker('CancelFlightBooking', (job) => {
    tracker.push({ action: 'CancelFlightBooking', vars: { ...job.variables } });
    job.complete({
      FlightBookingStatus: 'Canceled',
    });
  });

  engine.registerJobWorker('CancelTrainBooking', (job) => {
    tracker.push({ action: 'CancelTrainBooking', vars: { ...job.variables } });
    job.complete({
      TrainBookingStatus: 'Canceled',
    });
  });

  engine.registerJobWorker('CancelHotelBooking', (job) => {
    tracker.push({ action: 'CancelHotelBooking', vars: { ...job.variables } });
    job.complete({
      HotelBookingStatus: 'Canceled',
    });
  });
}

test('bpmnkit local simulation: happy path completes all bookings without compensation', async () => {
  const { engine, processId } = loadBpmnForBpmnKit(V3_PATH);
  const tracker = [];
  setupTestWorkers(engine, tracker);

  const instance = engine.start(processId, {
    confirm: true,
    flightNeeded: true,
    trainTicketNeeded: true,
  });

  await new Promise((r) => setTimeout(r, 100));

  assert.equal(instance.state, 'completed');
  const vars = instance.variables_snapshot;
  assert.equal(vars.FlightBookingStatus, 'Confirmed');
  assert.equal(vars.TrainBookingStatus, 'Confirmed');
  assert.equal(vars.HotelBookingStatus, 'Confirmed');

  // Verify only book actions were executed, no cancel actions
  const actions = tracker.map((t) => t.action);
  assert.deepEqual(actions.sort(), ['BookFlight', 'BookHotel', 'BookTrain'].sort());
});

test('bpmnkit local simulation: full Saga rollback when confirm = false', async () => {
  const { engine, processId } = loadBpmnForBpmnKit(V3_PATH);
  const tracker = [];
  setupTestWorkers(engine, tracker);

  const visitedElements = [];
  const instance = engine.start(processId, {
    confirm: false,
    flightNeeded: true,
    trainTicketNeeded: true,
  });
  instance.onChange((ev) => {
    if (ev.type === 'element:entered') visitedElements.push(ev.elementId);
  });

  await new Promise((r) => setTimeout(r, 150));

  assert.equal(instance.state, 'completed');
  const vars = instance.variables_snapshot;
  assert.equal(vars.FlightBookingStatus, 'Canceled');
  assert.equal(vars.TrainBookingStatus, 'Canceled');
  assert.equal(vars.HotelBookingStatus, 'Canceled');

  // Verify all 3 cancellations were performed
  const cancelActions = tracker.map((t) => t.action).filter((a) => a.startsWith('Cancel'));
  assert.equal(cancelActions.length, 3);
  assert.ok(cancelActions.includes('CancelFlightBooking'));
  assert.ok(cancelActions.includes('CancelTrainBooking'));
  assert.ok(cancelActions.includes('CancelHotelBooking'));

  // CE-1 check: reached Trip Canceled end event (Event_0b7jeb0)
  assert.ok(visitedElements.includes('Event_0b7jeb0'), 'Must reach Trip Canceled end event');
});

test('bpmnkit local simulation: partial booking only compensates executed tasks', async () => {
  const { engine, processId } = loadBpmnForBpmnKit(V3_PATH);
  const tracker = [];
  setupTestWorkers(engine, tracker);

  const instance = engine.start(processId, {
    confirm: false,
    flightNeeded: false,
    trainTicketNeeded: true,
  });

  await new Promise((r) => setTimeout(r, 150));

  assert.equal(instance.state, 'completed');
  const vars = instance.variables_snapshot;
  assert.equal(vars.TrainBookingStatus, 'Canceled');
  assert.equal(vars.HotelBookingStatus, 'Canceled');
  assert.equal(vars.FlightBookingStatus, undefined);

  // Flight was never booked, so CancelFlightBooking must NOT be called
  const actions = tracker.map((t) => t.action);
  assert.ok(!actions.includes('BookFlight'), 'BookFlight should not run');
  assert.ok(!actions.includes('CancelFlightBooking'), 'CancelFlightBooking should not run');
  assert.ok(actions.includes('CancelTrainBooking'), 'CancelTrainBooking should run');
  assert.ok(actions.includes('CancelHotelBooking'), 'CancelHotelBooking should run');
});
