// Parses a BPMN file with the official moddle parsers (bpmn-moddle + camunda-bpmn-moddle) and
// exposes the small graph/dialect queries the counterexample tests need.

import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { BpmnModdle } from 'bpmn-moddle';
import camundaDescriptor from 'camunda-bpmn-moddle/resources/camunda.json' with { type: 'json' };

export const REPO_ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', '..');
export const MODELS_DIR = path.join(REPO_ROOT, 'Models');
export const V3 = path.join(MODELS_DIR, 'BookHolidaySagaPatternV3.bpmn');

/** Parse a .bpmn file into { root, process, elements, flows, byId }. */
export async function parseBpmn(file = V3) {
  const moddle = new BpmnModdle({ camunda: camundaDescriptor });
  const { rootElement } = await moddle.fromXML(fs.readFileSync(file, 'utf8'));
  const process = rootElement.rootElements.find((e) => e.$type === 'bpmn:Process');
  if (!process) throw new Error(`no bpmn:Process in ${file}`);
  const elements = process.flowElements ?? [];
  const flows = elements.filter((e) => e.$type === 'bpmn:SequenceFlow');
  const byId = new Map(elements.map((e) => [e.id, e]));
  const id = (ref) => (typeof ref === 'string' ? ref : ref?.id);
  return {
    root: rootElement,
    process,
    elements,
    flows,
    byId,
    get: (elementId) => byId.get(elementId),
    ofType: (type) => elements.filter((e) => e.$type === type),
    /** sequence flows whose sourceRef is `elementId` */
    outgoing: (elementId) => flows.filter((f) => id(f.sourceRef) === elementId),
    /** sequence flows whose targetRef is `elementId` */
    incoming: (elementId) => flows.filter((f) => id(f.targetRef) === elementId),
  };
}

/** The Camunda extension attributes the tests care about, read from $attrs. */
export function camundaAttrs(el) {
  const a = el.$attrs ?? {};
  return {
    asyncBefore: a['camunda:asyncBefore'] === 'true',
    asyncAfter: a['camunda:asyncAfter'] === 'true',
    type: a['camunda:type'],
    topic: a['camunda:topic'],
    isForCompensation: el.isForCompensation === true,
    assignee: a['camunda:assignee'],
  };
}

/**
 * Nodes reachable from `startId` along sequence flows.
 * @returns {Set<string>} every element id reachable (start included)
 */
export function reachableFrom(model, startId, { stopAt = new Set(), endEvents = [] } = {}) {
  const seen = new Set([startId]);
  const queue = [startId];
  while (queue.length) {
    const current = queue.shift();
    if (stopAt.has(current)) continue;
    for (const flow of model.outgoing(current)) {
      const next = typeof flow.targetRef === 'string' ? flow.targetRef : flow.targetRef.id;
      if (!seen.has(next)) { seen.add(next); queue.push(next); }
    }
  }
  return seen;
}

/** End events reachable from `startId` (following sequence flows only, never associations). */
export function endEventsReachableFrom(model, startId) {
  const endIds = new Set(model.ofType('bpmn:EndEvent').map((e) => e.id));
  const seen = reachableFrom(model, startId);
  return [...seen].filter((x) => endIds.has(x));
}

/** Compensation throw events (intermediate or end) in the process. */
export function compensationThrowEvents(model) {
  return model.ofType('bpmn:IntermediateThrowEvent').filter((ev) =>
    (ev.eventDefinitions ?? []).some((d) => d.$type === 'bpmn:CompensateEventDefinition'));
}

/** Boundary events attached to `activityId`, with the type of each event definition. */
export function boundaryEventsOf(model, activityId) {
  const id = typeof activityId === 'string' ? activityId : activityId.id;
  return model.ofType('bpmn:BoundaryEvent')
    .filter((b) => (typeof b.attachedToRef === 'string' ? b.attachedToRef : b.attachedToRef?.id) === id)
    .map((b) => ({
      id: b.id,
      defs: (b.eventDefinitions ?? []).map((d) => d.$type),
    }));
}

/** The compensation handler wired to an activity through boundary event + association. */
export function compensationHandlerOf(model, activityId) {
  const boundary = boundaryEventsOf(model, activityId)
    .find((b) => b.defs.includes('bpmn:CompensateEventDefinition'));
  if (!boundary) return null;
  const assoc = model.ofType('bpmn:Association')
    .find((a) => (typeof a.sourceRef === 'string' ? a.sourceRef : a.sourceRef?.id) === boundary.id);
  if (!assoc) return null;
  const target = typeof assoc.targetRef === 'string' ? assoc.targetRef : assoc.targetRef?.id;
  return model.get(target) ?? null;
}

/** The condition expression of a sequence flow, or null. */
export function conditionOf(flow) {
  return flow?.conditionExpression?.body ?? null;
}
