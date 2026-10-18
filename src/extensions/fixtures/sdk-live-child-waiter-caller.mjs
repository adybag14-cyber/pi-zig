(async function observeActualWait(waitForChildProcess, spawn, execCommand, subject) {
  const rows = [];
  const begin = (mode, stdio = ['ignore', 'pipe', 'pipe']) => {
    const child = spawn(subject.executable, [subject.child, mode], { cwd: subject.cwd, shell: false, stdio });
    const closed = new Promise(resolve => child.once('close', resolve));
    return { child, closed };
  };
  const run = async (id, mode, observeTimers = false) => {
    const { child, closed } = begin(mode); let stdout = '', stderr = '';
    child.stdout.on('data', data => { stdout += data.toString(); });
    child.stderr.on('data', data => { stderr += data.toString(); });
    const originalSetTimeout = globalThis.setTimeout, callbacks = [];
    if (observeTimers) globalThis.setTimeout = function (fn, delay, ...args) {
      if (delay === 100) callbacks.push(fn);
      return Reflect.apply(originalSetTimeout, this, [fn, delay, ...args]);
    };
    let code;
    try { code = await waitForChildProcess(child); }
    finally { if (observeTimers) globalThis.setTimeout = originalSetTimeout; }
    await closed;
    rows.push({ id, code, stdout, stderr, ...(observeTimers ? {
      rearmed: callbacks.length > 1, freshIdleLiterals: new Set(callbacks).size === callbacks.length
    } : {}) });
  };
  rows.push({ id: 'actual-wait-metadata', name: waitForChildProcess.name, length: waitForChildProcess.length, tag: Object.prototype.toString.call(waitForChildProcess), prototype: Object.hasOwn(waitForChildProcess, 'prototype') });
  await run('actual-wait-zero', 'normal');
  await run('actual-wait-nonzero', 'nonzero');
  await run('actual-inherited-stdio-tail', 'inherited', true);
  {
    const { child, closed } = begin('normal', ['ignore', 'ignore', 'ignore']);
    const code = await waitForChildProcess(child); await closed;
    rows.push({ id: 'actual-null-streams', code, stdoutNull: child.stdout === null, stderrNull: child.stderr === null });
  }
  {
    const { child, closed } = begin('sleep');
    const reason = { marker: 'actual-user-error-event' };
    const pending = waitForChildProcess(child); child.emit('error', reason);
    let actual;
    try { await pending; } catch (error) { actual = error; }
    child.kill('SIGTERM'); await closed;
    rows.push({ id: 'actual-error-event-identity', same: actual === reason });
  }
  {
    const { child, closed } = begin('normal'); const effects = [];
    for (const name of ['stdout', 'stderr']) {
      const stream = child[name];
      Object.defineProperty(child, name, { configurable: true, get() { effects.push(name); return stream; } });
    }
    const code = await waitForChildProcess(child); await closed;
    rows.push({ id: 'actual-stream-getter-order', code, effects });
  }
  {
    const RealPromise = globalThis.Promise, executors = [];
    try {
      globalThis.Promise = new Proxy(RealPromise, { construct(target, args) {
        executors.push({ name: args[0].name, length: args[0].length, prototype: Object.hasOwn(args[0], 'prototype') });
        return Reflect.construct(target, args, target);
      }});
      const value = await execCommand(subject.executable, [subject.child, 'normal'], subject.cwd);
      rows.push({ id: 'actual-exec-and-wait-two-constructors', executors, value });
    } finally { globalThis.Promise = RealPromise; }
  }
  {
    const { child, closed } = begin('sleep'); const descriptor = Object.getOwnPropertyDescriptor(globalThis, 'Promise');
    let streamReads = 0, diagnosticReads = 0; const stream = child.stdout;
    Object.defineProperty(child, 'stdout', { configurable: true, get() { streamReads++; return stream; } });
    const reason = { get toString() { diagnosticReads++; throw new Error('unexpected diagnostic'); } };
    let actual;
    try {
      Object.defineProperty(globalThis, 'Promise', { configurable: true, get() { throw reason; } });
      try { waitForChildProcess(child); } catch (error) { actual = error; }
    } finally { Object.defineProperty(globalThis, 'Promise', descriptor); }
    const readsAtThrow = streamReads; child.kill('SIGTERM'); await closed;
    rows.push({ id: 'actual-constructor-getter-before-child', same: actual === reason, readsAtThrow, diagnosticReads });
  }
  return rows;
})
