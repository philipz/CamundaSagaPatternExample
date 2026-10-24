// Parses a BPMN file with the official moddle parsers (bpmn-moddle + camunda-bpmn-moddle) and
// exposes the small graph/dialect queries the counterexample tests need.
//
// Note on the moddle shape (verified against V3):
//   * `camunda:*` attributes become direct properties (`el.asyncBefore === true`,
//     `el.topic`, `el.type`, `el.isForCompensation`), not `$attrs` entries.
//   * `bpmn:Association` is an Artifact, so it lives in `process.artifacts`, not
//     `process.flowElements`. References are already resolved to elements.

import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { BpmnModdle } from 'bpmn-moddle';
import camundaDescriptor from 'camunda-bpmn-moddle/resources/camunda.json' with { type: 'json' };

export const REPO_ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', '..');
export const MODELS_DIR = path.join(REPO_ROOT, 'Models');
export const V3 = path.join(MODELS_DIR, 'BookHolidaySagaPatternV3.bpmn');

const idOf = (ref) => (typeof ref === 'string' ? ref : ref?.id);

/** The three booking steps of V3 (modeled activity ids). */
export const BOOK_TASKS = [
  { item: 'Flight', id: 'Activity_0fy5rid', topic: 'BookFlight', cancelTopic: 'CancelFlightBooking' },
  { item: 'Train', id: 'Activity_1ju8g5e', topic: 'BookTrain', cancelTopic: 'CancelTrainBooking' },
  { item: 'Hotel', id: 'Activity_0nzn307', topic: 'BookHotel', cancelTopic: 'CancelHotelBooking' },
];

/** Parse a .bpmn file into a queryable model. */
export async function parseBpmn(file = V3) {
  const moddle = new BpmnModdle({ camunda: camundaDescriptor });
  const { rootElement } = await moddle.fromXML(fs.readFileSync(file, 'utf8'));
  const process = rootElement.rootElements.find((e) => e.$type === 'bpmn:Process');
  if (!process) throw new Error(`no bpmn:Process in ${file}`);
  const elements = process.flowElements ?? [];
  const artifacts = process.artifacts ?? [];
  const flows = elements.filter((e) => e.$type === 'bpmn:SequenceFlow');
  const all = [...elements, ...artifacts];
  const byId = new Map(all.map((e) => [e.id, e]));
  return {
    root: rootElement,
    process,
    elements,
    artifacts,
    flows,
    byId,
    get: (elementId) => byId.get(elementId),
    ofType: (type) => all.filter((e) => e.$type === type),
    outgoing: (elementId) => flows.filter((f) => idOf(f.sourceRef) === elementId),
    incoming: (elementId) => flows.filter((f) => idOf(f.targetRef) === elementId),
    /** sequence flow from `fromId` to `toId`, or undefined */
    flowBetween: (fromId, toId) =>
      flows.find((f) => idOf(f.sourceRef) === fromId && idOf(f.targetRef) === toId),
  };
}

/** Camunda extension attributes of an element. */
export function camundaAttrs(el) {
  if (!el) return null;
  const a = el.$attrs ?? {};
  return {
    asyncBefore: el.asyncBefore === true || a['camunda:asyncBefore'] === 'true',
    asyncAfter: el.asyncAfter === true || a['camunda:asyncAfter'] === 'true',
    exclusive: el.exclusive,
    type: el.type ?? a['camunda:type'],
    topic: el.topic ?? a['camunda:topic'],
    isForCompensation: el.isForCompensation === true,
    isExternal: (el.type ?? a['camunda:type']) === 'external',
    assignee: el.assignee ?? a['camunda:assignee'],
  };
}

/** Nodes reachable from `startId` along sequence flows (associations are never followed). */
export function reachableFrom(model, startId, { stopAt = new Set() } = {}) {
  const seen = new Set([startId]);
  const queue = [startId];
  while (queue.length) {
    const current = queue.shift();
    if (stopAt.has(current)) continue;
    for (const flow of model.outgoing(current)) {
      const next = idOf(flow.targetRef);
      if (!seen.has(next)) { seen.add(next); queue.push(next); }
    }
  }
  return seen;
}

/** End events reachable from `startId` along sequence flows. */
export function endEventsReachableFrom(model, startId, opts) {
  const endIds = new Set(model.ofType('bpmn:EndEvent').map((e) => e.id));
  return [...reachableFrom(model, startId, opts)].filter((x) => endIds.has(x));
}

/** Compensation throw events (intermediate or end). */
export function compensationThrowEvents(model) {
  return model.elements.filter((ev) =>
    ev.$type === 'bpmn:IntermediateThrowEvent' || ev.$type === 'bpmn:EndEvent'
      ? (ev.eventDefinitions ?? []).some((d) => d.$type === 'bpmn:CompensateEventDefinition')
      : false);
}

/** Boundary events attached to `activityId`, with each event-definition type. */
export function boundaryEventsOf(model, activityId) {
  const id = idOf(activityId);
  return model.ofType('bpmn:BoundaryEvent')
    .filter((b) => idOf(b.attachedToRef) === id)
    .map((b) => ({
      id: b.id,
      cancelActivity: b.cancelActivity,
      defs: (b.eventDefinitions ?? []).map((d) => d.$type),
    }));
}

/** The compensation handler wired to an activity (boundary event + association). */
export function compensationHandlerOf(model, activityId) {
  const boundary = boundaryEventsOf(model, activityId)
    .find((b) => b.defs.includes('bpmn:CompensateEventDefinition'));
  if (!boundary) return null;
  const assoc = model.artifacts.find((a) =>
    a.$type === 'bpmn:Association' && idOf(a.sourceRef) === boundary.id);
  return assoc ? (model.get(idOf(assoc.targetRef)) ?? null) : null;
}

/** Condition expression body of a sequence flow, or null. */
export function conditionOf(flow) {
  return flow?.conditionExpression?.body ?? null;
}

/** The exclusive gateway whose outgoing flows are conditioned on `variableName`. */
export function gatewayOn(model, variableName) {
  return model.ofType('bpmn:ExclusiveGateway').find((g) =>
    model.outgoing(g.id).some((f) => (conditionOf(f) ?? '').includes(variableName)));
}

/** Outgoing flows of the gateway that belong to the `confirm = true` / `= false` branches. */
export function confirmBranches(model) {
  const gateway = gatewayOn(model, 'confirm');
  if (!gateway) return null;
  const branches = model.outgoing(gateway.id).map((f) => ({
    flow: f,
    target: idOf(f.targetRef),
    condition: conditionOf(f),
  }));
  return {
    gateway,
    confirm: branches.find((b) => b.condition && !/not\s+confirm|!\s*confirm/.test(b.condition)
      && /confirm/.test(b.condition)),
    cancel: branches.find((b) => /not\s+confirm|!\s*confirm/.test(b.condition ?? '')),
    branches,
  };
}
