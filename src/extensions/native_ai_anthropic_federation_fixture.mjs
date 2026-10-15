// Guest test input only. Implementation under test is native Zig or the actual
// installed SDK; this file supplies fake credentials and records observations.
export async function run(adapter, fixture) {
  let clock = 1000000;
  const originalNow = Date.now;
  Date.now = () => clock;
  const captures = [];
  const exchanges = [];
  const responses = [];
  const deferredResponse = () => {
    let release, fail, entered;
    const promise = new Promise((resolve, reject) => { release = resolve; fail = reject; });
    // This promise belongs to the fake endpoint queue. Observe it immediately,
    // including while the actual SDK is still doing asynchronous file I/O.
    promise.catch(() => {});
    const observed = new Promise(resolve => { entered = resolve; });
    responses.push({ promise, entered });
    return { release, fail, observed };
  };
  const config = {
    organization_id: "org-owned-fixture",
    workspace_id: "workspace-owned-fixture",
    authentication: {
      type: "oidc_federation",
      federation_rule_id: "rule-owned-fixture",
      service_account_id: "service-owned-fixture",
      identity_token: { source: "file", path: fixture.path },
    },
  };
  const response = (body, status = 200) => {
    const encoded = new TextEncoder().encode(body);
    return {
      status,
      ok: status >= 200 && status < 300,
      headers: { get: name => name.toLowerCase() === "request-id" ? "request-owned-fixture" : null },
      text: async () => body,
      body: { getReader() {
        let read = false;
        return {
          async read() { if (read) return { done: true }; read = true; return { done: false, value: encoded }; },
          async cancel() { read = true; },
        };
      } },
    };
  };
  const fetch = async (url, init) => {
    exchanges.push({ url, method: init.method, headers: init.headers, body: init.body, hasSignal: Object.hasOwn(init, "signal") });
    const next = responses.shift();
    if (!next) throw Error("owned fixture did not schedule a token response");
    if (next.promise) { next.entered(); return await next.promise; }
    return await next;
  };
  const tokenResponse = value => response(JSON.stringify({ access_token: value, token_type: "Bearer", expires_in: 180 }));
  const outcome = async promise => {
    try { return { token: await promise }; }
    catch (error) { return { error: { name: error.name, message: error.message, statusCode: error.statusCode, body: error.body, requestId: error.requestId } }; }
  };
  try {
    fixture.write("  owned.fixture.jwt.first\n");
    const first = adapter.make(config, fetch);
    const initial = deferredResponse();
    const a = adapter.token(first);
    const b = adapter.token(first);
    initial.release(tokenResponse("owned-access-first"));
    captures.push({ case: "coalesced-first", results: await Promise.all([outcome(a), outcome(b)]), count: exchanges.length });
    captures.push({ case: "fresh-cache", result: await outcome(adapter.token(first)), count: exchanges.length });

    clock = 1060000; // Exactly 120 seconds remaining enters advisory refresh.
    const advisory = deferredResponse();
    captures.push({ case: "advisory-stale", result: await outcome(adapter.token(first)) });
    await advisory.observed;
    clock = 1151000; // 29 seconds remaining requires the same pending refresh.
    const mandatory = outcome(adapter.token(first));
    advisory.fail(Error("owned endpoint offline"));
    captures.push({ case: "mandatory-joins-advisory-error", result: await mandatory });

    fixture.write("owned.fixture.jwt.rotated");
    responses.push(tokenResponse("owned-access-rotated"));
    adapter.invalidate(first);
    captures.push({ case: "force-refresh-rereads-file", result: await outcome(adapter.token(first)), count: exchanges.length });
    captures.push({ case: "same-config-fetch-shares", result: await outcome(adapter.token(adapter.make(config, fetch))), count: exchanges.length });

    clock = 1211000; // Rotated token has exactly 120 seconds remaining.
    const background = deferredResponse();
    await adapter.token(first);
    await background.observed;
    const backgroundFinished = outcome(adapter.pending(first));
    background.fail(Error("owned advisory failure"));
    await backgroundFinished;
    clock = 1212000;
    captures.push({ case: "advisory-backoff", result: await outcome(adapter.token(first)), count: exchanges.length });

    const changed = { ...config, workspace_id: "workspace-owned-other" };
    responses.push(response(JSON.stringify({ error: "invalid_grant", error_description: "owned mismatch", assertion: "must-be-redacted", access_token: "must-be-redacted" }), 401));
    captures.push({ case: "workspace-change-replaces-cache", result: await outcome(adapter.token(adapter.make(changed, fetch))), count: exchanges.length });

    fixture.write("\n  \t");
    captures.push({ case: "empty-identity-file", result: await outcome(adapter.token(adapter.make(config, fetch))), count: exchanges.length });
    fixture.write("x".repeat(16385));
    captures.push({ case: "oversize-assertion", result: await outcome(adapter.token(adapter.make(changed, fetch))), count: exchanges.length });
    fixture.write("owned.fixture.jwt.final");
    responses.push(response(JSON.stringify({ access_token: "redacted", token_type: "MAC", expires_in: 180 })));
    captures.push({ case: "unsupported-token-type", result: await outcome(adapter.token(adapter.make(config, fetch))), count: exchanges.length });

    const insecure = { ...config, base_url: "http://owned.example.invalid" };
    captures.push({ case: "secure-endpoint-before-file", result: await outcome(adapter.token(adapter.make(insecure, fetch))), count: exchanges.length });
    return { captures, exchanges };
  } finally { Date.now = originalNow; }
}
