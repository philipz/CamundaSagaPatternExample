// ENV-1: the workers cannot be loaded by Node under their own package.json.
//
// BookingSystemWorkers/package.json declares "type": "module" (ES modules), but all three worker
// files use CommonJS `require(...)`. Running the documented command
// (`node ./BookFlight.js`, README "Running the Microservice Workers") therefore throws
// `ReferenceError: require is not defined in ES module scope` before any handler is registered.
// The Docker image hides this, because compile.sh bundles the source with `pkg` into an executable.
//
// Business rule asserted: the worker entry points must start under the module system their own
// package.json declares.

import test from 'node:test';
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import { WORKERS, WORKERS_DIR } from './helpers/worker-sandbox.mjs';

const moduleType = JSON.parse(fs.readFileSync(path.join(WORKERS_DIR, 'package.json'), 'utf8')).type;

test('ENV-1: the worker entry points must load under the package.json module system',
  { todo: `ENV-1: package.json says type="${moduleType}" but the workers use require()` },
  async () => {
    assert.ok(moduleType === 'module' || moduleType === 'commonjs',
      `unexpected package.json "type": ${moduleType}`);

    const isCjs = moduleType === 'commonjs';
    for (const w of WORKERS) {
      const source = fs.readFileSync(path.join(WORKERS_DIR, w.file), 'utf8');
      if (isCjs) {
        assert.ok(!/^\s*import\s/m.test(source), `${w.file} uses import under type="commonjs"`);
        continue;
      }
      // type === "module": actually start the file and check Node does not reject the syntax.
      // It is killed after a moment (a healthy worker would poll camunda:8080 forever).
      const run = spawnSync(process.execPath, [w.file], {
        cwd: WORKERS_DIR, encoding: 'utf8', timeout: 4000,
      });
      const output = `${run.stdout ?? ''}${run.stderr ?? ''}`;
      assert.doesNotMatch(output, /require is not defined/,
        `${w.file} starts under type="module" but calls require():\n${output.split('\n').slice(0, 4).join('\n')}`);
    }
  });
