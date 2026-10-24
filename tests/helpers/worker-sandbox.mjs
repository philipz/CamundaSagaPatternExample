// Runs an UNMODIFIED worker source file (BookingSystemWorkers/*.js) inside a node:vm sandbox
// with a fake `camunda-external-task-client-js`, so its topic handlers can be driven directly.
//
// Why a sandbox: the workers create a polling Client at load time (network to camunda:8080),
// and BookingSystemWorkers/package.json declares "type": "module" while the files use
// `require` — they cannot be imported as-is (see ENV-1). The sandbox supplies `require`, so the
// exact production source is exercised without changing a single line of it.

import fs from 'node:fs';
import path from 'node:path';
import vm from 'node:vm';
import { fileURLToPath } from 'node:url';

export const REPO_ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', '..');
export const WORKERS_DIR = path.join(REPO_ROOT, 'BookingSystemWorkers');

/** The three workers, their topics and the process variables they own. */
export const WORKERS = [
  { item: 'Flight', file: 'FlightBooking.js', book: 'BookFlight', cancel: 'CancelFlightBooking',
    idVar: 'FlightBookingID', statusVar: 'FlightBookingStatus', activityId: 'Activity_0fy5rid',
    finishedLog: /Flight booking was finished: (\S+)/ },
  { item: 'Train', file: 'TrainBooking.js', book: 'BookTrain', cancel: 'CancelTrainBooking',
    idVar: 'TrainBookingID', statusVar: 'TrainBookingStatus', activityId: 'Activity_1ju8g5e',
    finishedLog: /Train booking was finished: (\S+)/ },
  { item: 'Hotel', file: 'BookHotel.js', book: 'BookHotel', cancel: 'CancelHotelBooking',
    idVar: 'HotelBookingID', statusVar: 'HotelBookingStatus', activityId: 'Activity_0nzn307',
    finishedLog: /Hotel booking was finished: (\S+)/ },
];

/** Deterministic PRNG (mulberry32) so UUIDs are reproducible across runs. */
function seededRandom(seed) {
  let a = seed >>> 0;
  return () => {
    a = (a + 0x6d2b79f5) >>> 0;
    let t = a;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

/**
 * Load a worker file into a fresh sandbox.
 * @param {string} file  file name inside BookingSystemWorkers/
 * @param {object} [opts]
 * @param {number} [opts.seed=1]            PRNG seed for Math.random
 * @param {boolean} [opts.failOnSet=false]  make `Variables#set` throw — simulates the supplier
 *                                          call inside the handler throwing (CE-3 / CE-4)
 */
export function loadWorker(file, { seed = 1, failOnSet = false } = {}) {
  const source = fs.readFileSync(path.join(WORKERS_DIR, file), 'utf8');
  const handlers = new Map();
  const clients = [];
  const logs = [];

  class FakeVariables {
    constructor() { this.values = {}; }
    set(key, value) {
      if (failOnSet) throw new Error(`injected supplier failure while setting ${key}`);
      this.values[key] = value;
      return this;
    }
    get(key) { return this.values[key]; }
    getAll() { return { ...this.values }; }
  }

  class FakeClient {
    constructor(config) { this.config = config; clients.push(this); }
    subscribe(topic, options, handler) {
      handlers.set(topic, typeof options === 'function' ? options : handler);
      return { unsubscribe() {} };
    }
  }

  const fakeModule = { Client: FakeClient, Variables: FakeVariables, logger: () => {} };
  const random = seededRandom(seed);
  let clock = 1_700_000_000_000;
  const sandboxMath = Object.create(Math, { random: { value: random } });
  class SandboxDate extends Date {
    constructor(...args) { super(...(args.length ? args : [clock++])); }
    static now() { return clock++; }
  }

  const context = {
    require(name) {
      if (name === 'camunda-external-task-client-js') return fakeModule;
      throw new Error(`worker required an unexpected module: ${name}`);
    },
    console: { log: (...args) => logs.push(args.join(' ')), error: () => {}, warn: () => {} },
    setTimeout: (fn) => { fn(); return 0; },   // skip the 2 s "work" sleep in FlightBooking.js
    Math: sandboxMath,
    Date: SandboxDate,
    Promise,
  };
  vm.runInNewContext(source, context, { filename: path.join(WORKERS_DIR, file) });
  return { handlers, clients, logs, Variables: FakeVariables };
}

/** A fetched external task as the client hands it to a handler. */
export function makeTask({ id = 'ext-task-1', processInstanceId = 'pi-1', activityId = 'act',
  topicName = 'topic', retries = null, variables = {} } = {}) {
  return {
    id, processInstanceId, activityId, topicName, retries,
    variables: { get: (k) => variables[k], getAll: () => ({ ...variables }) },
  };
}

/** Records every TaskService call the handler makes (mirrors client 2.3.1's TaskService API). */
export function makeTaskService() {
  const calls = [];
  const record = (op) => async (task, ...args) => { calls.push({ op, task, args }); };
  return {
    calls,
    complete: async (task, variables, localVariables) => {
      calls.push({ op: 'complete', task, variables: variables?.getAll?.() ?? {}, localVariables });
    },
    handleFailure: record('handleFailure'),
    handleBpmnError: record('handleBpmnError'),
    extendLock: record('extendLock'),
    lock: record('lock'),
    unlock: record('unlock'),
  };
}

/** Invoke a handler the way client 2.3.1 `executeTask` does; report whether it threw. */
export async function runHandler(handler, task, taskService) {
  try {
    await handler({ task, taskService });
    return { threw: null };
  } catch (err) {
    return { threw: err };
  }
}
