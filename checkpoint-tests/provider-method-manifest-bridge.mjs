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
const temp = mkdtempSync(path.join(tmpdir(), "pi-provider-method-181-"));
const extensionPath = path.join(temp, "provider-e2e.mjs");

writeFileSync(extensionPath, String.raw`
export default function (pi) {
  const closure = "production-bridge-181";
  const config = {
    name: "Provider E2E",
    baseUrl: "https://provider.invalid/v1",
    api: "openai-completions",
    apiKey: "unused",
    models: [{ id: "e2e", name: "E2E", reasoning: false, input: ["text"], cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 }, contextWindow: 4096, maxTokens: 512 }],
    oauth: {
      owner: "oauth-owner",
      async refreshToken(credentials, signal) {
        assertSignal(signal);
        if (this.owner !== "oauth-owner") throw new Error("provider receiver was not retained");
        return { ...credentials, access: closure + ":" + credentials.refresh };
      },
      getApiKey(credentials) {
        if (this.owner !== "oauth-owner") throw new Error("provider key receiver was not retained");
        return closure + ":" + credentials.access;
      },
      async waitForAbort(_credentials, signal) {
        assertSignal(signal);
        await new Promise((resolve, reject) => {
          if (signal.aborted) return reject(signal.reason);
          const timer = setTimeout(() => reject(new Error("abort not delivered")), 1500);
          signal.addEventListener("abort", () => { clearTimeout(timer); reject(signal.reason); }, { once: true });
        });
      },
    },
    nested: { methods: [function (value) { return this.length + ":" + closure + ":" + value; }] },
  };
  function assertSignal(signal) {
    if (!(signal instanceof AbortSignal)) throw new Error("provider signal missing");
  }
  pi.registerProvider("production-e2e", config);
  pi.registerCommand("provider-replace", { handler: async () => pi.registerProvider("production-e2e", { name: "Provider E2E Renamed" }) });
  pi.registerCommand("provider-cycle", { handler: async () => { const cyclic = {}; cyclic.self = cyclic; try { pi.registerProvider("production-e2e", { cyclic }); } catch {} } });
  pi.registerCommand("provider-unregister", { handler: async () => pi.unregisterProvider("production-e2e") });
  pi.registerCommand("provider-ping", { handler: async (_args, ctx) => ctx.ui.notify("worker-reused") });
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
function descriptorAt(rootValue, dottedPath) {
  let value = rootValue;
  for (const segment of dottedPath.split(".")) value = value[segment];
  assert.equal(value.__pi_callback_kind, "provider_method");
  assert.equal(value.__pi_callback_path, dottedPath);
  assert.equal(typeof value.__pi_callback_id, "string");
  assert.ok(value.__pi_callback_id.length > 0);
  return value;
}
async function invoke(callbackId, args, appendSignal = false, invocationId = "provider") {
  send({ kind: "provider_method", callbackId, args, appendSignal, abortable: appendSignal, invocationId, context: { mode: "print", hasUI: false } });
  return record();
}
async function command(name, invocationId) {
  send({ kind: "command", name, rawArguments: "", flags: {}, invocationId, context: { mode: "print", hasUI: false } });
  return record();
}

try {
  const ready = await record();
  assert.equal(ready.type, "ready");
  const registration = ready.manifest.providers.find((entry) => entry.name === "production-e2e");
  assert.ok(registration, "production provider missing from startup manifest");
  const refresh = descriptorAt(registration.config, "oauth.refreshToken");
  const key = descriptorAt(registration.config, "oauth.getApiKey");
  const wait = descriptorAt(registration.config, "oauth.waitForAbort");
  const nested = descriptorAt(registration.config, "nested.methods.0");
  assert.ok(!JSON.stringify(registration.config).includes("production-bridge-181"), "function source/closure leaked into manifest");

  const refreshed = await invoke(refresh.__pi_callback_id, [{ refresh: "r181" }], true, "refresh");
  assert.equal(refreshed.ok, true);
  assert.equal(refreshed.result.value.access, "production-bridge-181:r181");
  const apiKey = await invoke(key.__pi_callback_id, [{ access: "a181" }], false, "key");
  assert.deepEqual(apiKey, { ok: true, result: { value: "production-bridge-181:a181" } });
  const nestedResult = await invoke(nested.__pi_callback_id, ["array"], false, "nested");
  assert.equal(nestedResult.result.value, "1:production-bridge-181:array");

  send({ kind: "provider_method", callbackId: wait.__pi_callback_id, args: [{}], appendSignal: true, abortable: true, invocationId: "abort-181", context: { mode: "print", hasUI: false } });
  setTimeout(() => send({ kind: "abort_current", invocationId: "abort-181", reason: "Operation aborted" }), 30);
  const aborted = await record();
  assert.equal(aborted.ok, false);
  assert.match(aborted.error, /Operation aborted/);

  const replaced = await command("provider-replace", "replace");
  assert.equal(replaced.ok, true);
  const action = replaced.result.providers.find((entry) => entry.action === "register" && entry.name === "production-e2e");
  assert.ok(action, "dynamic provider action missing");
  assert.equal(action.config.name, "Provider E2E Renamed");
  const replacementRefresh = descriptorAt(action.config, "oauth.refreshToken");
  assert.notEqual(replacementRefresh.__pi_callback_id, refresh.__pi_callback_id);
  assert.equal((await invoke(refresh.__pi_callback_id, [{ refresh: "old" }], true, "old-generation")).result.value.access, "production-bridge-181:old");
  assert.equal((await invoke(replacementRefresh.__pi_callback_id, [{ refresh: "new" }], true, "new-generation")).result.value.access, "production-bridge-181:new");

  const cycle = await command("provider-cycle", "cycle");
  assert.equal(cycle.ok, true);
  assert.equal((await invoke(replacementRefresh.__pi_callback_id, [{ refresh: "after-cycle" }], true, "after-cycle")).result.value.access, "production-bridge-181:after-cycle");

  const removed = await command("provider-unregister", "unregister");
  assert.equal(removed.ok, true);
  assert.ok(removed.result.providers.some((entry) => entry.action === "unregister" && entry.name === "production-e2e"));
  const unavailable = await invoke(replacementRefresh.__pi_callback_id, [{}], true, "removed");
  assert.equal(unavailable.ok, false);
  assert.match(unavailable.error, /unknown or unloaded provider callback/);
  const ping = await command("provider-ping", "ping");
  assert.equal(ping.ok, true);
  assert.match(ping.result.message, /worker-reused/);

  send({ kind: "shutdown" });
  const shutdown = await record();
  assert.equal(shutdown.ok, true);
  child.stdin.end();
  const exitCode = await new Promise((resolve) => child.once("close", resolve));
  assert.equal(exitCode, 0, stderr);
  console.log("production provider-method bridge e2e: ok");
} finally {
  if (child.exitCode === null) child.kill("SIGKILL");
  rmSync(temp, { recursive: true, force: true });
}
