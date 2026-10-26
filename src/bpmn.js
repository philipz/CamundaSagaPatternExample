import { Bpmn } from '@bpmnkit/core';
import { Engine } from '@bpmnkit/engine';

const defsCache = new Map();

/**
 * Parses and prepares BPMN definitions from XML, caching the result.
 */
export function getOrPrepareDefinitions(xml) {
  let defs = defsCache.get(xml);
  if (!defs) {
    defs = Bpmn.parse(xml);
    const proc = defs.processes[0];

    // Map camunda:topic into zeebe:taskDefinition extension element
    for (const el of proc.flowElements) {
      if (el.unknownAttributes && el.unknownAttributes['camunda:topic']) {
        const topic = el.unknownAttributes['camunda:topic'];
        el.extensionElements = el.extensionElements || [];
        el.extensionElements.push({
          name: 'zeebe:taskDefinition',
          attributes: { type: topic, retries: '3' },
          children: [],
        });
      }
    }

    // Convert JUEL expressions ${...} to FEEL expressions = ...
    for (const f of proc.sequenceFlows) {
      if (f.conditionExpression && f.conditionExpression.text) {
        let expr = f.conditionExpression.text.trim();
        if (expr.startsWith('${') && expr.endsWith('}')) {
          expr = expr.slice(2, -1).trim();
        }
        expr = expr.replace(/==/g, '=');
        f.conditionExpression.text = '= ' + expr;
      }
    }

    defsCache.set(xml, defs);
  }
  return defs;
}

/**
 * Creates and initializes an @bpmnkit/engine instance from a BPMN XML string.
 * Native to Cloudflare Workers (zero node:fs dependencies).
 * Uses cached definitions to minimize CPU time on repeated invocations.
 */
export function createEngineFromXml(xml) {
  const defs = getOrPrepareDefinitions(xml);
  const proc = defs.processes[0];

  const engine = new Engine();
  engine.deploy({ bpmn: defs });

  return {
    defs,
    engine,
    processId: proc.id,
  };
}
