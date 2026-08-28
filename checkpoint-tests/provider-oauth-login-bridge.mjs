import assert from "node:assert/strict";
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import { spawn } from "node:child_process";
import readline from "node:readline";
import { fileURLToPath } from "node:url";

const here = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(here, "..");
const bridgeSource = readFileSync(path.join(root, "src/extensions/js_bridge.mjs"), "utf8");
const temp = mkdtempSync(path.join(tmpdir(), "pi-provider-oauth-182-"));
const extensionPath = path.join(temp, "oauth-login-e2e.mjs");

writeFileSync(extensionPath, String.raw`
export default function (pi) {
  let attempt = 0;
  pi.registerProvider("oauth-production-e2e", {
    name: "OAuth Production E2E",
    baseUrl: "https://oauth.invalid/v1",
    api: "openai-completions",
    apiKey: "unused",
    models: [{ id: "oauth-e2e", name: "OAuth E2E", reasoning: false, input: ["text"], cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 }, contextWindow: 4096, maxTokens: 512 }],
    oauth: {
      async login(callbacks) {
        attempt += 1;
        if (!(callbacks.signal instanceof AbortSignal)) throw new Error("OAuth AbortSignal missing");
        if (attempt === 1) {
          callbacks.onAuth({ url: "https://login.invalid/start", instructions: "Open the browser" });
          callbacks.onDeviceCode({ verificationUri: "https://device.invalid", userCode: "DEVICE-182", intervalSeconds: 7, expiresInSeconds: 600, instructions: "Enter the code" });
          callbacks.onProgress("waiting-for-user");
          const prompt = await callbacks.onPrompt({ message: "Tenant?", placeholder: "tenant", secret: true });
          const manual = await callbacks.onManualCodeInput();
          const team = await callbacks.onSelect({ message: "Team?", options: [{ id: "team-a", label: "Team A" }, { value: "team-b", label: "Team B", description: "Preferred" }] });
          return {
            refresh: "refresh-182",
            access: "access-182",
            expires: 9999999999999,
            tenant: { prompt, manual, team },
            arbitrary: { retained: true, generation: attempt },
          };
        }
        if (attempt === 2) {
          const answer = await callbacks.onPrompt({ message: "This request will be aborted" });
          return { refresh: "must-not-persist", access: String(answer), expires: 9999999999999 };
        }
        if (attempt === 3) {
          return { refresh: "reuse-refresh", access: "worker-reused-after-abort", expires: 9999999999999 };
        }
        throw new Error("oauth-login-exploded-182");
      },
      getApiKey(credentials) { return "derived:" + credentials.access; },
    },
  });
  pi.registerCommand("oauth-unregister", { handler: async () => pi.unregisterProvider("oauth-production-e2e") });
}
`);

const child = spawn(process.execPath, [
  "--no-warnings",
  "--experimental-strip-types",
  "--experimental-transform-types",
  "--input-type=module",
  "-e",
  bridgeSource,
  extensionPath,
], { stdio: ["pipe", "pipe", "pipe"] });
let stderr = "";
child.stderr.setEncoding("utf8");
child.stderr.on("data", (chunk) => { stderr += chunk; });
const lines = readline.createInterface({ input: child.stdout, crlfDelay: Infinity })[Symbol.asyncIterator]();

async function record() {
  for (;;) {
    const next = await lines.next();
    if (next.done) throw new Error(`bridge closed before a protocol record; stderr=${stderr}`);
    const marker = next.value.indexOf("\x1e");
    if (marker < 0) continue;
    return JSON.parse(next.value.slice(marker + 1));
  }
}
function send(value) {
  child.stdin.write(JSON.stringify(value) + "\n");
}
function loginDescriptor(config) {
  const descriptor = config.oauth.login;
  assert.equal(descriptor.__pi_callback_kind, "provider_method");
  assert.equal(descriptor.__pi_callback_path, "oauth.login");
  assert.equal(typeof descriptor.__pi_callback_id, "string");
  assert.ok(descriptor.__pi_callback_id.length > 0);
  return descriptor;
}
function startLogin(callbackId, invocationId) {
  send({
    kind: "provider_oauth_login",
    callbackId,
    abortable: true,
    invocationId,
    context: { mode: "interactive", hasUI: true },
  });
}
async function command(name, invocationId) {
  send({ kind: "command", name, rawArguments: "", flags: {}, invocationId, context: { mode: "print", hasUI: false } });
  return record();
}

try {
  const ready = await record();
  assert.equal(ready.type, "ready");
  const registration = ready.manifest.providers.find((entry) => entry.name === "oauth-production-e2e");
  assert.ok(registration, "OAuth provider missing from production startup manifest");
  const login = loginDescriptor(registration.config);
  assert.ok(!JSON.stringify(registration.config).includes("oauth-login-exploded-182"), "function source leaked into manifest");

  const actions = [];
  const requests = [];
  const replies = {
    oauth_prompt: "tenant-answer",
    oauth_manual_code: "manual-code-182",
    oauth_select: "team-b",
  };
  startLogin(login.__pi_callback_id, "oauth-login-1");
  let firstResult;
  while (!firstResult) {
    const next = await record();
    if (next.type === "ui_action") {
      actions.push(next);
      continue;
    }
    if (next.type === "ui_request") {
      requests.push(next);
      assert.ok(Object.hasOwn(replies, next.method), `unexpected OAuth UI request: ${next.method}`);
      send({ kind: "ui_response", id: next.id, ok: true, result: replies[next.method] });
      continue;
    }
    firstResult = next;
  }
  assert.equal(firstResult.ok, true);
  assert.deepEqual(firstResult.result.value, {
    refresh: "refresh-182",
    access: "access-182",
    expires: 9999999999999,
    tenant: { prompt: "tenant-answer", manual: "manual-code-182", team: "team-b" },
    arbitrary: { retained: true, generation: 1 },
  });
  assert.deepEqual(actions.map((entry) => entry.method), ["oauth_auth", "oauth_device_code", "oauth_progress"]);
  assert.equal(actions[0].args.url, "https://login.invalid/start");
  assert.equal(actions[1].args.userCode, "DEVICE-182");
  assert.equal(actions[1].args.intervalSeconds, 7);
  assert.equal(actions[1].args.expiresInSeconds, 600);
  assert.deepEqual(requests.map((entry) => entry.method), ["oauth_prompt", "oauth_manual_code", "oauth_select"]);
  assert.equal(requests[0].args.secret, true);
  assert.equal(requests[2].args.options[1].description, "Preferred");

  // Abort while the callback is awaiting a host prompt. No ui_response is sent:
  // the AbortSignal must remove and reject the pending promise itself.
  startLogin(login.__pi_callback_id, "oauth-login-abort");
  const pendingPrompt = await record();
  assert.equal(pendingPrompt.type, "ui_request");
  assert.equal(pendingPrompt.method, "oauth_prompt");
  send({ kind: "abort_current", invocationId: "oauth-login-abort", reason: "Operation aborted" });
  const aborted = await record();
  assert.equal(aborted.ok, false);
  assert.match(aborted.error, /Operation aborted/);

  // The worker and callback registry must remain usable with no stale prompt.
  startLogin(login.__pi_callback_id, "oauth-login-reuse");
  const reused = await record();
  assert.equal(reused.ok, true);
  assert.equal(reused.result.value.access, "worker-reused-after-abort");

  startLogin(login.__pi_callback_id, "oauth-login-reject");
  const rejected = await record();
  assert.equal(rejected.ok, false);
  assert.match(rejected.error, /oauth-login-exploded-182/);
  assert.match(rejected.error, /login/);

  const removed = await command("oauth-unregister", "oauth-unregister");
  assert.equal(removed.ok, true);
  assert.ok(removed.result.providers.some((entry) => entry.action === "unregister" && entry.name === "oauth-production-e2e"));
  startLogin(login.__pi_callback_id, "oauth-login-removed");
  const unavailable = await record();
  assert.equal(unavailable.ok, false);
  assert.match(unavailable.error, /unknown or unloaded provider callback/);

  send({ kind: "shutdown" });
  const shutdown = await record();
  assert.equal(shutdown.ok, true);
  child.stdin.end();
  const exitCode = await new Promise((resolve) => child.once("close", resolve));
  assert.equal(exitCode, 0, stderr);
  console.log("production provider OAuth login bridge e2e: ok");
} finally {
  if (child.exitCode === null) child.kill("SIGKILL");
  rmSync(temp, { recursive: true, force: true });
}
