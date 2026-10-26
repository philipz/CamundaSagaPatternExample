import { Bpmn } from '@bpmnkit/core';
import { Engine } from '@bpmnkit/engine';

/**
 * Creates and initializes an @bpmnkit/engine instance from a BPMN XML string.
 * Native to Cloudflare Workers (zero node:fs dependencies).
 */
export function createEngineFromXml(xml) {
  const defs = Bpmn.parse(xml);
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

  const engine = new Engine();
  engine.deploy({ bpmn: defs });

  return {
    defs,
    engine,
    processId: proc.id,
  };
}
