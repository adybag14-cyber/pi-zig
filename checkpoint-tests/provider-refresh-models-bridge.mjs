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
const temp = mkdtempSync(path.join(tmpdir(), "pi-provider-models-183-"));
const extensionPath = path.join(temp, "provider-models-e2e.mjs");

writeFileSync(extensionPath, String.raw`
export default function (pi) {
  const model = (id, name = id) => ({ id, name, reasoning: false, input: ["text"], cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 }, contextWindow: 4096, maxTokens: 512 });
  const config = {
    name: "Refresh Production E2E",
    baseUrl: "https://models.invalid/v1",
    api: "openai-completions",
    apiKey: "local",
    models: [model("initial")],
    async refreshModels(context) {
      if (!(context.signal instanceof AbortSignal)) throw new Error("refresh AbortSignal missing");
      if (!Object.isFrozen(context)) throw new Error("refresh context is mutable");
      if (context.credential && !Object.isFrozen(context.credential)) throw new Error("credential is mutable");
      if (context.stored && !Object.isFrozen(context.stored)) throw new Error("stored snapshot is mutable");
      if (!context.allowNetwork && Object.hasOwn(context, "force")) throw new Error("offline force leaked");
      if (context.stored?.mode === "reject") throw new Error("refresh-models-exploded-183");
      if (context.stored?.mode === "abort") {
        await context.publish({ persist: { models: [model("never")] } });
        return [model("never")];
      }
      if (context.stored?.mode === "stale") {
        const accepted = await context.publish({
          persist: { models: [model("stale")] },
          update: () => { config.models = [model("must-not-update")]; },
        });
        if (accepted) throw new Error("stale publication unexpectedly accepted");
        return [model("stale-result")];
      }
      if (!context.allowNetwork) {
        const restored = context.stored?.models ?? [model("offline-empty")];
        const accepted = await context.publish({
          update: () => { config.models = restored.map((entry) => ({ ...entry, name: entry.name + ":updated" })); },
        });
        if (!accepted) throw new Error("offline publication rejected");
        return restored;
      }
      if (context.force !== true) throw new Error("online force missing");
      if (context.credential?.tenant !== "corp") throw new Error("effective credential missing");
      const fresh = [model("fresh", "Fresh")];
      const accepted = await context.publish({
        persist: { models: fresh, checkedAt: 183, etag: '"etag-183"' },
        update: () => { config.models = fresh.map((entry) => ({ ...entry, name: entry.name + ":committed" })); },
      });
      if (!accepted) throw new Error("online publication rejected");
      return fresh;
    },
  };
  pi.registerProvider("refresh-production-e2e", config);
  const objectState = { models: [model("object-initial")] };
  pi.registerProvider({
    id: "object-refresh-production-e2e",
    name: "Object Refresh Production E2E",
    baseUrl: "https://object-models.invalid/v1",
    api: "openai-completions",
    apiKey: "local",
    getModels() { return objectState.models; },
    async refreshModels(context) {
      const next = [model("object-fresh", "Object Fresh")];
      const accepted = await context.publish({ update: () => { objectState.models = next; } });
      if (!accepted) throw new Error("object publication rejected");
    },
  });
  pi.registerCommand("refresh-ping", { handler: async (_args, ctx) => ctx.ui.notify(config.models[0].name) });
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
    if (next.done) throw new Error(`bridge closed before protocol record; stderr=${stderr}`);
    const marker = next.value.indexOf("\x1e");
    if (marker >= 0) return JSON.parse(next.value.slice(marker + 1));
  }
}
function send(value) { child.stdin.write(JSON.stringify(value) + "\n"); }
function model(id, name = id) {
  return { id, name, reasoning: false, input: ["text"], cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 }, contextWindow: 4096, maxTokens: 512 };
}
function start(callbackId, invocationId, refreshContext, providerName = "refresh-production-e2e") {
  send({ kind: "provider_refresh_models", callbackId, providerName, refreshContext, abortable: true, invocationId, context: { mode: "print", hasUI: false } });
}
async function command(name, invocationId) {
  send({ kind: "command", name, rawArguments: "", flags: {}, invocationId, context: { mode: "print", hasUI: false } });
  return record();
}

try {
  const ready = await record();
  assert.equal(ready.type, "ready");
  const registration = ready.manifest.providers.find((entry) => entry.name === "refresh-production-e2e");
  assert.ok(registration);
  const descriptor = registration.config.refreshModels;
  assert.equal(descriptor.__pi_callback_kind, "provider_method");
  assert.equal(descriptor.__pi_callback_path, "refreshModels");
  const objectRegistration = ready.manifest.providers.find((entry) => entry.name === "object-refresh-production-e2e");
  assert.ok(objectRegistration);
  const objectDescriptor = objectRegistration.config.refreshModels;
  assert.equal(objectDescriptor.__pi_callback_path, "refreshModels");

  start(descriptor.__pi_callback_id, "offline-183", {
    generation: 1,
    allowNetwork: false,
    credential: { type: "api_key", key: "local" },
    stored: { models: [model("cached", "Cached")], checkedAt: 1 },
  });
  const offlinePublish = await record();
  assert.equal(offlinePublish.type, "ui_request");
  assert.equal(offlinePublish.method, "provider_models_publish");
  assert.equal(offlinePublish.args.hasPersist, false);
  send({ kind: "ui_response", id: offlinePublish.id, ok: true, result: true });
  const offlineCatalog = await record();
  assert.equal(offlineCatalog.method, "provider_models_catalog");
  assert.equal(offlineCatalog.args.models[0].name, "Cached:updated");
  send({ kind: "ui_response", id: offlineCatalog.id, ok: true, result: true });
  const offlineResult = await record();
  assert.equal(offlineResult.ok, true);
  assert.equal(offlineResult.result.models[0].id, "cached");

  start(descriptor.__pi_callback_id, "online-183", {
    generation: 2,
    allowNetwork: true,
    force: true,
    credential: { type: "oauth", access: "a", refresh: "r", expires: 9999999999999, tenant: "corp" },
    stored: { models: [model("cached")], checkedAt: 1 },
  });
  const onlinePublish = await record();
  assert.equal(onlinePublish.method, "provider_models_publish");
  assert.equal(onlinePublish.args.hasPersist, true);
  assert.equal(onlinePublish.args.persist.checkedAt, 183);
  assert.equal(onlinePublish.args.persist.etag, '"etag-183"');
  send({ kind: "ui_response", id: onlinePublish.id, ok: true, result: true });
  const onlineCatalog = await record();
  assert.equal(onlineCatalog.method, "provider_models_catalog");
  assert.equal(onlineCatalog.args.models[0].name, "Fresh:committed");
  send({ kind: "ui_response", id: onlineCatalog.id, ok: true, result: true });
  const onlineResult = await record();
  assert.equal(onlineResult.ok, true);
  assert.equal(onlineResult.result.models[0].name, "Fresh");

  start(objectDescriptor.__pi_callback_id, "object-183", {
    generation: 1,
    allowNetwork: false,
    credential: { type: "api_key", key: "local" },
  }, "object-refresh-production-e2e");
  const objectPublish = await record();
  assert.equal(objectPublish.method, "provider_models_publish");
  assert.equal(objectPublish.args.hasPersist, false);
  send({ kind: "ui_response", id: objectPublish.id, ok: true, result: true });
  const objectCatalog = await record();
  assert.equal(objectCatalog.method, "provider_models_catalog");
  assert.equal(objectCatalog.args.models[0].id, "object-fresh");
  send({ kind: "ui_response", id: objectCatalog.id, ok: true, result: true });
  const objectResult = await record();
  assert.equal(objectResult.ok, true);
  assert.equal(objectResult.result.models[0].name, "Object Fresh");

  start(descriptor.__pi_callback_id, "stale-183", {
    generation: 3,
    allowNetwork: false,
    stored: { mode: "stale", models: [model("old")] },
  });
  const stalePublish = await record();
  assert.equal(stalePublish.method, "provider_models_publish");
  send({ kind: "ui_response", id: stalePublish.id, ok: true, result: false });
  const staleResult = await record();
  assert.equal(staleResult.ok, true);
  assert.equal(staleResult.result.models[0].id, "stale-result");
  const ping = await command("refresh-ping", "ping-183");
  assert.equal(ping.ok, true);
  assert.match(ping.result.message, /Fresh:committed/);

  start(descriptor.__pi_callback_id, "abort-183", {
    generation: 4,
    allowNetwork: false,
    stored: { mode: "abort", models: [] },
  });
  const pending = await record();
  assert.equal(pending.method, "provider_models_publish");
  send({ kind: "abort_current", invocationId: "abort-183", reason: "Operation aborted" });
  const aborted = await record();
  assert.equal(aborted.ok, false);
  assert.match(aborted.error, /Operation aborted/);

  start(descriptor.__pi_callback_id, "reject-183", {
    generation: 5,
    allowNetwork: false,
    stored: { mode: "reject", models: [] },
  });
  const rejected = await record();
  assert.equal(rejected.ok, false);
  assert.match(rejected.error, /refresh-models-exploded-183/);
  assert.match(rejected.error, /refreshModels/);

  const reuse = await command("refresh-ping", "reuse-183");
  assert.equal(reuse.ok, true);
  send({ kind: "shutdown" });
  assert.equal((await record()).ok, true);
  child.stdin.end();
  assert.equal(await new Promise((resolve) => child.once("close", resolve)), 0, stderr);
  console.log("production provider refreshModels bridge e2e: ok");
} finally {
  if (child.exitCode === null) child.kill("SIGKILL");
  rmSync(temp, { recursive: true, force: true });
}
