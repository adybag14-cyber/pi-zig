(async function observeActualExec(execCommand, subject) {
  const rows = [];
  const run = async (id, command, args, options) => {
    try {
      const value = await execCommand(command, args, subject.cwd, options);
      rows.push({ id, value, keys: Object.keys(value) });
    } catch (error) { rows.push({ id, error: { name: error.name, code: error.code, message: error.message } }); }
  };
  await run('actual-output-zero', subject.executable, [subject.child, 'normal']);
  await run('actual-output-nonzero', subject.executable, [subject.child, 'nonzero']);
  await run('actual-timeout', subject.executable, [subject.child, 'sleep'], { timeout: 40 });
  const pre = new AbortController(); pre.abort();
  await run('actual-preaborted', subject.executable, [subject.child, 'sleep'], { signal: pre.signal });
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), 40);
  await run('actual-abort', subject.executable, [subject.child, 'sleep'], { signal: controller.signal });
  clearTimeout(timer);
  await run('actual-missing-command', subject.missing, []);
  await run('actual-invalid-command', undefined, []);
  const observed = new AbortController(); const effects = [];
  const options = {
    get signal() { effects.push('signal'); return observed.signal; },
    get timeout() { effects.push('timeout'); return 10000; },
    get cwd() { throw new Error('core/exec must use its cwd argument'); }
  };
  await run('actual-option-getters', subject.executable, [subject.child, 'normal'], options);
  rows[rows.length - 1].effects = effects;
  rows.push({ id: 'actual-function-metadata', name: execCommand.name, length: execCommand.length, async: Object.prototype.toString.call(execCommand), prototype: Object.hasOwn(execCommand, 'prototype') });
  return rows;
})
