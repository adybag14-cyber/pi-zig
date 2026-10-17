'use strict';
// Prepared original/native observable controls, UNRUN. Root supplies genuine
// namespaces and an owned real console WriteStream; no fd/TTY/provider is faked.
const assert = require('node:assert/strict');
module.exports = async function verifyCanonicalTTY(net, tty, streams, output) {
  assert.equal(net.Stream, net.Socket);
  assert.equal(Object.getPrototypeOf(net.Socket), streams.Duplex);
  assert.equal(Object.getPrototypeOf(net.Socket.prototype), streams.Duplex.prototype);
  assert.equal(Object.getOwnPropertyDescriptor(net.Socket.prototype, 'constructor').enumerable, false);
  for (const [name, length] of [['_read', 1], ['_write', 3], ['_final', 1], ['_destroy', 2], ['ref', 0], ['unref', 0]]) {
    const method = net.Socket.prototype[name];
    assert.equal(method.name, ''); assert.equal(method.length, length);
    assert.equal(Object.hasOwn(method, 'prototype'), true);
  }
  for (const name of ['bytesRead', 'bytesWritten', '_bytesDispatched']) {
    const descriptor = Object.getOwnPropertyDescriptor(net.Socket.prototype, name);
    assert.equal(descriptor.enumerable, true); assert.equal(descriptor.configurable, false);
    assert.equal(descriptor.get.name, name); assert.equal(Object.hasOwn(descriptor.get, 'prototype'), true);
  }
  for (const name of ['bufferSize', 'readyState', 'pending']) {
    const descriptor = Object.getOwnPropertyDescriptor(net.Socket.prototype, name);
    assert.equal(descriptor.enumerable, false); assert.equal(descriptor.configurable, name === 'pending');
    assert.equal(descriptor.get.name, 'get');
    assert.equal(Object.hasOwn(descriptor.get, 'prototype'), name !== 'pending');
  }
  assert.equal(output instanceof tty.WriteStream, true);
  assert.equal(output instanceof net.Socket, true);
  assert.equal(output instanceof streams.Duplex, true);
  assert.equal(output.isTTY, true);
  const descriptor = Object.getOwnPropertyDescriptor(Buffer, 'from');
  const original = Buffer.from;
  let lookups = 0;
  const trace = [];
  const write = (value, encoding) => new Promise((resolve, reject) => {
    trace.push('before');
    output.write(value, encoding, error => {
      trace.push('callback');
      if (error) reject(error); else resolve();
    });
    trace.push('after');
  });
  try {
    Object.defineProperty(Buffer, 'from', { configurable: true, get() { lookups++; return original; } });
    for (const encoding of ['utf8', 'utf-8', 'ascii', 'latin1', 'binary', 'ucs2', 'ucs-2', 'utf16le', 'utf-16le']) {
      await write('x', encoding);
      assert.equal(lookups, 0, 'recognized Source binding bypasses Buffer.from');
    }
    await write('78', 'hex');
    assert.equal(lookups, 1, 'default route reads live captured Buffer.from');
    for (let i = 0; i < trace.length; i += 3) assert.deepEqual(trace.slice(i, i + 3), ['before', 'after', 'callback']);
    return { fixture: 'actual-canonical-tty', callbacks: trace.length / 3, fallbackLookups: lookups };
  } finally { Object.defineProperty(Buffer, 'from', descriptor); }
};
