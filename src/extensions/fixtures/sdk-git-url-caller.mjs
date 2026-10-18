(function captureActualGitParser(parseGitUrl, nodeURL, cases) {
  const rows = [];
  const describe = value => value === null ? null : {
    keys: Object.keys(value), type: value.type, repo: value.repo,
    host: value.host, path: value.path,
    ref: value.ref === undefined ? { undefined: true } : value.ref,
    pinned: value.pinned
  };
  for (const entry of cases) {
    try { rows.push({ id: entry.id, returned: describe(parseGitUrl(entry.value)) }); }
    catch (error) { rows.push({ id: entry.id, threw: { name: error.name, message: error.message } }); }
  }
  rows.push({ id: 'ordinary-metadata', returned: {
    name: parseGitUrl.name, length: parseGitUrl.length,
    prototype: Object.hasOwn(parseGitUrl, 'prototype'), async: Object.prototype.toString.call(parseGitUrl)
  }});
  let diagnosticReads = 0;
  const reason = { get toString() { diagnosticReads++; throw new Error('diagnostic must not execute'); } };
  let caught;
  try { parseGitUrl({ get trim() { throw reason; } }); } catch (error) { caught = error; }
  rows.push({ id: 'actual-trim-getter-reason', returned: { same: caught === reason, diagnosticReads } });
  const effects = [];
  const source = { get trim() { effects.push('trim:get'); return function () {
    effects.push(this === source ? 'trim:receiver' : 'trim:wrong'); return 'git:github:pi/observed';
  }; } };
  rows.push({ id: 'actual-trim-getter-order', returned: describe(parseGitUrl(source)), effects });
  const originalMatch = String.prototype.match;
  const literals = [];
  try {
    String.prototype.match = function (regexp) { literals.push(regexp); return Reflect.apply(originalMatch, this, [regexp]); };
    parseGitUrl('git:github:pi/literal-one'); parseGitUrl('git:github:pi/literal-two');
  } finally { String.prototype.match = originalMatch; }
  rows.push({ id: 'source-regexp-literal-freshness', returned: {
    calls: literals.length, unique: new Set(literals).size
  }});
  const originalGlobalURL = globalThis.URL;
  const originalNodeURL = nodeURL.URL;
  let globalCalls = 0, nodeCalls = 0;
  try {
    globalThis.URL = new Proxy(originalGlobalURL, { construct(target, args) {
      globalCalls++; return Reflect.construct(target, args, target);
    }});
    nodeURL.URL = new Proxy(originalNodeURL, { construct(target, args) {
      nodeCalls++; return Reflect.construct(target, args, target);
    }});
    parseGitUrl('https://github.com/pi/private-cache-observation-20261017');
    parseGitUrl('https://github.com/pi/private-cache-observation-20261017');
  } finally { nodeURL.URL = originalNodeURL; globalThis.URL = originalGlobalURL; }
  rows.push({ id: 'actual-url-bindings-and-memo', returned: { globalCalls, nodeCalls } });
  const originalStringify = JSON.stringify;
  const keyEffects = [];
  try {
    JSON.stringify = function (value) { keyEffects.push(Object.keys(value)); return Reflect.apply(originalStringify, this, [value]); };
    parseGitUrl('git:github:pi/json-key-observation-20261017');
  } finally { JSON.stringify = originalStringify; }
  rows.push({ id: 'actual-hosted-key-json', returned: keyEffects });
  return rows;
})
