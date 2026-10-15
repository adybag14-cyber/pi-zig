import * as api from 'file:///C:/Users/adyba/pi-upstream-source-ae7b16d-20261015/packages/ai/src/utils/json-parse.ts';
const intrinsicParse = JSON.parse;
const rows = [];
for (const name of ['wrapper-rethrow', 'proxy-rethrow', 'caller-syntax', 'caller-sentinel', 'wrapper-replace-syntax', 'reviver-sentinel']) {
  const events = [], input = name === 'reviver-sentinel' ? '{}' : '{"bad":.5}';
  const sentinel = { toString() { events.push('sentinel.string'); return 'caller sentinel'; } };
  const callerSyntax = new SyntaxError('caller syntax');
  let latest;
  const delegate = function (text) {
    events.push(['delegate', this === JSON, text]);
    try { return Reflect.apply(intrinsicParse, this, [text]); }
    catch (error) {
      events.push(['intrinsic.error', error.name, error.message]);
      latest = name === 'wrapper-replace-syntax' ? new SyntaxError('caller replaced: ' + error.message) : error;
      throw latest;
    }
  };
  try {
    JSON.parse = name === 'proxy-rethrow' ? new Proxy(intrinsicParse, {
      apply(target, receiver, args) {
        events.push(['proxy', receiver === JSON, args.length, args[0]]);
        try { return Reflect.apply(target, receiver, args); }
        catch (error) { events.push(['intrinsic.error', error.name, error.message]); latest = error; throw error; }
      },
    }) : name === 'caller-syntax' ? function () { latest = callerSyntax; throw callerSyntax; }
      : name === 'caller-sentinel' ? function () { latest = sentinel; throw sentinel; }
        : name === 'reviver-sentinel' ? function (text) {
          return Reflect.apply(intrinsicParse, this, [text, function (key) { events.push(['reviver', key]); latest = sentinel; throw sentinel; }]);
        } : delegate;
    const observed = {};
    for (const method of ['parseJsonWithRepair', 'parseToolCallArguments']) {
      events.push(['method', method]);
      try { observed[method] = { value: api[method](input) }; }
      catch (error) { observed[method] = { caughtIdentity: error === latest, callerSyntaxIdentity: error === callerSyntax, sentinelIdentity: error === sentinel, ...(error === sentinel ? {} : { error: { name: error.name, message: error.message } }) }; }
    }
    rows.push({ name, input, observed, events });
  } finally { JSON.parse = intrinsicParse; }
}
export default rows;
