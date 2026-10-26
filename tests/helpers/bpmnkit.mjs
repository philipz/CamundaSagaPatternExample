import fs from 'node:fs';
import { Bpmn } from '@bpmnkit/core';
import { Engine } from '@bpmnkit/engine';

/**
 * Loads and adapts a BPMN XML file for execution in @bpmnkit/engine.
 * Translates legacy Camunda 7 attributes (camunda:topic and JUEL expressions)
 * into @bpmnkit/engine / Zeebe compatible structures seamlessly.
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
      // Replace JS/JUEL equality with FEEL equality
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

/**
 * Loads and adapts a BPMN XML file for execution in @bpmnkit/engine.
 */
export function loadBpmnForBpmnKit(filePath) {
  const xml = fs.readFileSync(filePath, 'utf8');
  return createEngineFromXml(xml);
}
