// Actual public Node24.14 TTY calls. Prepared only; no expected packet/capture.
// All descriptor inputs fail validation before any real descriptor is opened.
import tty from 'node:tty';
const rows = [];
const inspectError = e => ({
  prototype: Object.getPrototypeOf(e)?.constructor?.name,
  name: e.name, code: e.code, message: e.message, string: String(e),
  own: Object.getOwnPropertyNames(e).filter(k => k !== 'stack'),
  codeDescriptor: Object.getOwnPropertyDescriptor(e, 'code'),
  messageDescriptor: Object.getOwnPropertyDescriptor(e, 'message'),
  nodeMarker: Object.getOwnPropertySymbols(Object.getPrototypeOf(e)).map(k => ({
    description: k.description,
    value: e[k],
    descriptor: Object.getOwnPropertyDescriptor(Object.getPrototypeOf(e), k),
  })),
});
function record(name, call) {
  try { rows.push({name, value: call()}); }
  catch (e) { rows.push({name, error: inspectError(e)}); }
}
for (const fd of [-1, 1.5, '-1']) {
  record(`fd:${String(fd)}`, () => new tty.WriteStream(fd));
}
for (const count of ['not a number', "contains'quote", 'x'.repeat(40), null,
  undefined, true, 16n, Symbol('color'), function namedCount() {},
  NaN, Infinity, -0, 1, 1.5, 4294967297, 9007199254740992]) {
  record(`count:${String(count)}`, () => tty.WriteStream.prototype.hasColors(count, {FORCE_COLOR: '3'}));
}
record('node-error-code-class-field', () => {
  const before = Object.getOwnPropertyDescriptor(RangeError.prototype, 'code');
  let intercepted = 0;
  Object.defineProperty(RangeError.prototype, 'code', {configurable: true, set() { intercepted++; }});
  try {
    try { new tty.WriteStream(-1); }
    catch (e) { return {intercepted, error: inspectError(e)}; }
  } finally {
    if (before) Object.defineProperty(RangeError.prototype, 'code', before);
    else delete RangeError.prototype.code;
  }
});
// hasColors' function count is validated, rather than treated as its object
// environment overload. A live function.name getter can replace the error.
record('function-name-reason-identity', () => {
  const reason = {};
  const count = function() {};
  let calls = 0;
  Object.defineProperty(count, 'name', {get() { calls++; throw reason; }});
  try { tty.WriteStream.prototype.hasColors(count, {FORCE_COLOR: '3'}); }
  catch (e) { return {same: e === reason, calls}; }
});
record('late-global-Function-poison', () => {
  const before = Object.getOwnPropertyDescriptor(globalThis, 'Function');
  const reason = {}; let calls = 0;
  Object.defineProperty(globalThis, 'Function', {configurable: true, get() { calls++; throw reason; }});
  try {
    try { new tty.WriteStream(-1); }
    catch (e) { return {same: e === reason, calls, error: inspectError(e)}; }
  } finally { Object.defineProperty(globalThis, 'Function', before); }
});
// A fresh owner must establish fd INT32_MAX is absent before capture. This
// reaches actual native tty initialization failure without opening a real fd.
record('native-context-ordinary-false-continues', () => {
  const before = Object.getOwnPropertyDescriptor(Object.prototype, 'errno');
  Object.defineProperty(Object.prototype, 'errno', {configurable: true, writable: false, value: 'blocked-errno'});
  try {
    try { new tty.WriteStream(2147483647); }
    catch (e) { return {error: inspectError(e), info: e.info && {
      keys: Object.keys(e.info), errno: e.info.errno,
      code: e.info.code, message: e.info.message, syscall: e.info.syscall,
    }}; }
  } finally {
    if (before) Object.defineProperty(Object.prototype, 'errno', before);
    else delete Object.prototype.errno;
  }
});
process.stdout.write(JSON.stringify(rows, (key, value) => typeof value === 'function' ? {function: value.name} : value) + '\n');
