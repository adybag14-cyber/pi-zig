// Genuine Node24 Module wrapper inputs, no expected/observed output.
import Module from 'node:module';
if (process.version !== 'v24.14.0') throw new Error('exact original Node24.14.0 required');
const rows = [];
const events = [];
const marker = Object.freeze({ owned: 'wrapper-reason' });
function observe(id, operation) {
  events.length = 0;
  try { rows.push({ id, status: 'returned', value: operation(), events: [...events] }); }
  catch (reason) { rows.push({ id, status: 'thrown', type: typeof reason, name: reason?.name, message: reason?.message, sameReason: reason === marker, events: [...events] }); }
}
const originalWrap = Module.wrap;
const originalWrapper = Module.wrapper;
const shape = fn => ({ name: fn.name, length: fn.length, ownsPrototype: Object.hasOwn(fn, 'prototype'), prototypeConstructor: fn.prototype?.constructor === fn });
observe('wrapper-default-shape-and-descriptors', () => ({
  wrap: shape(Module.wrap), wrapper: [...Module.wrapper],
  properties: ['wrap', 'wrapper'].map(key => { const d = Object.getOwnPropertyDescriptor(Module, key); return { key, enumerable: d.enumerable, configurable: d.configurable, get: shape(d.get), set: shape(d.set) }; }),
  wrapped: Module.wrap('module.exports=1;'),
}));
observe('wrapper-prefix-coercion-before-suffix-reread', () => {
  try {
    Module.wrapper = ['prefix:', 'old-suffix'];
    return originalWrap({ [Symbol.toPrimitive](hint) { events.push(hint); Module.wrapper = ['unused', ':new-suffix']; return 'body'; } });
  } finally { Module.wrapper = originalWrapper; }
});
observe('wrapper-live-index-getter-order', () => {
  try {
    Module.wrapper = { get 0() { events.push('prefix'); return { [Symbol.toPrimitive](hint) { events.push('prefix:' + hint); return '<'; } }; }, get 1() { events.push('suffix'); return '>'; } };
    return originalWrap({ [Symbol.toPrimitive](hint) { events.push('body:' + hint); return 'x'; } });
  } finally { Module.wrapper = originalWrapper; }
});
observe('wrapper-raw-prefix-coercion-throw', () => {
  try {
    Module.wrapper = { get 0() { events.push('prefix'); return { [Symbol.toPrimitive]() { throw marker; } }; }, get 1() { events.push('unexpected-suffix'); return '>'; } };
    return originalWrap('x');
  } finally { Module.wrapper = originalWrapper; }
});
observe('wrapper-real-proxy-set-and-define', () => {
  const old0 = originalWrapper[0]; const old1 = originalWrapper[1];
  try {
    const set = Reflect.set(originalWrapper, '0', '<');
    Object.defineProperty(originalWrapper, '1', { value: '>', writable: true, enumerable: true, configurable: true });
    return { set, same: Module.wrapper === originalWrapper, wrapped: originalWrap('x') };
  } finally { originalWrapper[0] = old0; originalWrapper[1] = old1; }
});
observe('wrapper-setters-ignore-borrowed-receiver', () => {
  try {
    const fn = function replacement() { return 'actual-replacement'; };
    Object.getOwnPropertyDescriptor(Module, 'wrap').set.call({}, fn);
    const wrapSame = Module.wrap === fn;
    const pair = ['[', ']']; Object.getOwnPropertyDescriptor(Module, 'wrapper').set.call({}, pair);
    return { wrapSame, wrapperSame: Module.wrapper === pair, wrapped: originalWrap('x') };
  } finally { Module.wrap = originalWrap; Module.wrapper = originalWrapper; }
});
process.stdout.write(JSON.stringify({ authority: { nodeVersion: process.version, execPath: process.execPath }, rows }) + '\n');
