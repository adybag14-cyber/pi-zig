// Separate fresh genuine Node process so earlier .parent reads cannot warn.
// Prepared only; Root must admit each actual host-option profile separately.
import Module from 'node:module';
import readline from 'node:readline';
if (process.version !== 'v24.14.0') throw Error('exact Node required');
const fence = readline.createInterface({ input: process.stdin, crlfDelay: Infinity });
const line = await new Promise(resolve => fence.once('line', resolve)); fence.close();
if (line !== 'ADMIT-NODE-MODULE-SOURCE-ONLY') throw Error('missing admission');
const trace = [], rows = [], marker = {}, original = Object.getOwnPropertyDescriptor(process, 'emitWarning');
const descriptor = Object.getOwnPropertyDescriptor(Module.prototype, 'parent'), a = new Module('a'), b = new Module('b');
Object.defineProperty(process, 'emitWarning', { configurable: true, writable: true, value: function(message, type, code, ctor) { 'use strict'; trace.push({ message, type, code, getter: ctor === descriptor.get, setter: ctor === descriptor.set, undefinedReceiver: this === undefined }); throw marker; } });
try {
  let caught; try { void a.parent; } catch (e) { caught = e; }
  rows.push({ id: 'first-getter-throw', sameReason: caught === marker, trace: trace.slice() });
  rows.push({ id: 'second-getter-no-warning', undefinedParent: a.parent === undefined, count: trace.length });
  Object.defineProperty(process, 'emitWarning', { configurable: true, writable: true, value: function(message, type, code, ctor) { 'use strict'; trace.push({ message, type, code, getter: ctor === descriptor.get, setter: ctor === descriptor.set, undefinedReceiver: this === undefined }); } });
  a.parent = b; a.parent = b;
  rows.push({ id: 'setter-warning-and-shared-code', exactParent: a.parent === b, trace: trace.slice() });
} finally { Object.defineProperty(process, 'emitWarning', original); }
process.stdout.write(JSON.stringify({ node: process.version, execPath: process.execPath, execArgv: process.execArgv, rows }) + '\n');
