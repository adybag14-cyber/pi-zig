// Native test guest only. All expected rows come from the real Source5ab
// public provider capture; the native host replays its retained HTTP replies.
function snapshot(value) {
  if (ArrayBuffer.isView(value)) return {$bytes: [...value]};
  if (Array.isArray(value)) return value.map(snapshot);
  if (value && typeof value === 'object') {
    const result = {};
    for (const [key, member] of Object.entries(value)) {
      if (value.role === 'assistant' && key === 'timestamp') result[key] = '$TIMESTAMP';
      else if (value.role === 'assistant' && key === 'durationMs') result[key] = '$DURATION';
      else if (value.type && value.details && key === 'timestamp') result[key] = '$DIAGNOSTIC_TIME';
      else result[key] = snapshot(member);
    }
    return result;
  }
  return value;
}
function canonical(value) {
  if (Array.isArray(value)) return value.map(canonical);
  if (value && typeof value === 'object') return Object.fromEntries(Object.keys(value).sort().map(key => [key, canonical(value[key])]));
  return value;
}
export async function run(source, streams, baseUrl, identityFile) {
  if (source.sourceHead !== '5ab7fe74c400097b386662205cd93900695b8a71' || source.cases !== 16 || source.tokenExchanges !== 2) throw Error('genuine extended Source16 required');
  for (const row of source.rows) {
    const item = row.input;
    // Copy recorded input graphs so deliberate caller mutation does not alter
    // the authority fixture or leak into the next cache lifecycle case.
    const model = JSON.parse(JSON.stringify({...row.model, baseUrl}));
    const context = JSON.parse(JSON.stringify(row.context));
    const env = item.federation ? {
      ANTHROPIC_FEDERATION_RULE_ID: 'owned-rule',
      ANTHROPIC_ORGANIZATION_ID: 'owned-org',
      ANTHROPIC_IDENTITY_TOKEN_FILE: identityFile,
      ANTHROPIC_WORKSPACE_ID: 'owned-workspace',
      ANTHROPIC_SERVICE_ACCOUNT_ID: 'owned-service',
    } : {};
    const callbacks = [], events = [], payloads = [];
    const options = {
      apiKey: item.federation ? '' : 'fixture-placeholder-key', env, maxTokens: 1000,
      maxRetries: 0, sessionId: 'fixture-session', ...JSON.parse(JSON.stringify(item.options ?? {})),
      onPayload(payload) {
        callbacks.push('payload');
        payloads.push(snapshot(payload));
        if (item.callback === 'mutate') {
          model.baseUrl = 'http://127.0.0.1:1';
          model.headers['x-captured'] = 'changed';
          options.apiKey = 'changed-key';
          options.headers['x-option'] = 'changed';
          options.fetch = () => { throw Error('changed fetch must not run'); };
        }
        if (item.callback === 'wire-fields') return {
          ...payload, user_profile_id: 'owned-profile', workspace_id: 'owned-payload-workspace',
          output_format: {type: 'json_schema', schema: {type: 'object', properties: {ok: {type: 'boolean'}}, required: ['ok']}},
        };
        if (item.callback === 'format-conflict') return {
          ...payload, output_format: {type: 'json_schema', schema: {}}, output_config: {format: {type: 'json_schema', schema: {}}},
        };
      },
      onResponse(response) { callbacks.push('response:' + response.status + ':' + response.headers['x-fixture']); },
      onProviderStreamEvent() { callbacks.push('chunk'); },
    };
    if (item.keyGetter) Object.defineProperty(options, 'apiKey', {get() { throw Error('owned key getter failed'); }});
    let result, syncError;
    try {
      const stream = streams.stream(model, context, options);
      if (item.long) result = snapshot(await stream.result());
      for await (const event of stream) events.push(snapshot(event));
      if (!item.long) result = snapshot(await stream.result());
    } catch (error) {
      syncError = {name: error.name, message: error.message};
    }
    for (const [key, actual] of Object.entries({payloads, callbacks, events, result, syncError})) {
      if (JSON.stringify(actual) !== JSON.stringify(row[key])) throw Error(JSON.stringify({name: row.name, key, actual, expected: row[key], terminalResult: result, synchronousError: syncError}));
    }
  }
  return true;
}
export function checkRequests(source, captured) {
  const expected = source.rows.flatMap(row => row.requests.map(request => ({method: request.method, path: request.path, body: request.body})));
  if (JSON.stringify(canonical(captured)) !== JSON.stringify(canonical(expected))) throw Error(JSON.stringify({captured, expected}));
  return true;
}
