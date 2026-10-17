// PREPARED ORIGINAL NODE24 CALLER ONLY; separate from immutable collector C8A4.
// Dedicated child, owned root, no inherited environment values in observations.
import Module from 'node:module';
import { join, resolve } from 'node:path';
const root = resolve(process.argv[2]);
process.chdir(root);
process.env.HOME = join(root, 'controlled-home');
process.env.USERPROFILE = join(root, 'controlled-home');
delete process.env.NODE_PATH;
Module._initPaths();
const rows = [];
function dedup(id, throwSecond) {
  const savedLookup = Module._resolveLookupPaths;
  const savedFind = Module._findPath;
  const events = [];
  const reason = Object.freeze({ controlledSecondRead: true });
  let reads = 0;
  try {
    Module._resolveLookupPaths = function(request, parent) {
      events.push('lookup');
      return new Proxy(['unused'], { get(target, key, receiver) {
        if (key === 'length') { events.push('length'); return 1; }
        if (key === '0') {
          reads++; events.push(`index:${reads}`);
          if (reads === 2 && throwSecond) throw reason;
          return reads === 1 ? 'controlled-probe' : 'controlled-insert';
        }
        return Reflect.get(target, key, receiver);
      } });
    };
    Module._findPath = function(request, paths) {
      events.push('find');
      return { controlledPaths: [...paths] };
    };
    try { rows.push({ id, status: 'returned', value: Module._resolveFilename('owned-nonbuiltin-request', null, false, { paths: [root] }), events }); }
    catch (error) { rows.push({ id, status: 'thrown', sameReason: error === reason, events }); }
  } finally { Module._resolveLookupPaths = savedLookup; Module._findPath = savedFind; }
}
dedup('lookup-index-read-again-after-includes', false);
dedup('lookup-second-index-read-raw-throw', true);
for (const [id, observedLength] of [['negative', -1], ['numeric-string-zero', '0'], ['nonnumeric-string', 'controlled-nan'], ['positive', 1]]) {
  const events = [];
  const privatePaths = Module._resolveLookupPaths('owned-nonbuiltin-request', null);
  const saved = Object.getOwnPropertyDescriptor(privatePaths, 'constructor');
  try {
    Object.defineProperty(privatePaths, 'constructor', { configurable: true, value: {
      [Symbol.species]: function ControlledSpecies() {
        return { get length() { events.push('get:length'); return observedLength; },
          set length(value) { events.push(`set:length:${value}`); } };
      },
    } });
    try {
      const value = Module._resolveLookupPaths('owned-nonbuiltin-request', { paths: ['controlled-parent'] });
      rows.push({ id: `lookup-return-positive-length-${id}`, status: 'returned', returnedNull: value === null, events });
    } catch (error) { rows.push({ id: `lookup-return-positive-length-${id}`, status: 'thrown', name: error?.name, message: error?.message, events }); }
  } finally {
    if (saved) Object.defineProperty(privatePaths, 'constructor', saved);
    else delete privatePaths.constructor;
  }
}
process.stdout.write(JSON.stringify({ authority: 'original-Node24.14.0-CommonJS-corrections', nodeVersion: process.version, execPath: process.execPath, rows }) + '\n');
