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
const temp = mkdtempSync(path.join(tmpdir(), "pi-provider-stream-185-"));
const extensionPath = path.join(temp, "provider-stream-e2e.mjs");

writeFileSync(extensionPath, String.raw`
import { createAssistantMessageEventStream } from "@mariozechner/pi-ai";
const usage = { input: 3, output: 4, cacheRead: 1, cacheWrite: 0, totalTokens: 8, cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0, total: 0 } };
const assistant = (content, stopReason = "pending") => ({ role: "assistant", content, api: "custom-stream", provider: "stream-production-e2e", model: "stream-model", usage, stopReason, timestamp: 185 });
export default function (pi) {
  pi.registerProvider("stream-production-e2e", {
    name: "Stream Production E2E",
    api: "custom-stream",
    apiKey: "local",
    models: [{ id: "stream-model", name: "Stream Model", reasoning: true, input: ["text"], cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 }, contextWindow: 4096, maxTokens: 512 }],
    streamSimple(model, context, options) {
      if (model.id !== "stream-model") throw new Error("model snapshot missing");
      if (!Object.isFrozen(model) || !Object.isFrozen(context) || !Object.isFrozen(options)) throw new Error("stream inputs are mutable");
      if (!(options.signal instanceof AbortSignal)) throw new Error("stream AbortSignal missing");
      const mode = context.mode;
      if (mode === "throw-after-terminal") {
        return (async function* () {
          yield { type: "start", partial: assistant([]) };
          yield { type: "done", reason: "stop", message: assistant([{ type: "text", text: "premature" }], "stop") };
          throw new Error("iterator-exploded-after-terminal-185");
        })();
      }
      if (mode === "tool-mismatch") {
        return (async function* () {
          yield { type: "start", partial: assistant([]) };
          yield { type: "toolcall_start", contentIndex: 0, partial: assistant([]) };
          yield { type: "toolcall_delta", contentIndex: 0, delta: '{"x":1}', partial: assistant([]) };
          yield { type: "toolcall_end", contentIndex: 0, toolCall: { type: "toolCall", id: "bad", name: "bad", arguments: { x: 2 } }, partial: assistant([]) };
          yield { type: "done", reason: "toolUse", message: assistant([], "toolUse") };
        })();
      }
      if (mode === "cancel") {
        return (async function* () {
          yield { type: "start", partial: assistant([]) };
          await new Promise((resolve, reject) => {
            options.signal.addEventListener("abort", () => reject(options.signal.reason), { once: true });
          });
        })();
      }
      if (mode === "cancel-ignores-signal") {
        return (async function* () {
          yield { type: "start", partial: assistant([]) };
          await new Promise(() => {});
        })();
      }
      if (mode === "queue-overflow") {
        const stream = createAssistantMessageEventStream();
        for (let index = 0; index < 65; index++) stream.push({ type: "queued", index });
        return stream;
      }
      const stream = createAssistantMessageEventStream();
      const partial = assistant([]);
      stream.push({ type: "start", partial });
      stream.push({ type: "text_start", contentIndex: 0, partial });
      stream.push({ type: "thinking_start", contentIndex: 1, partial });
      stream.push({ type: "toolcall_start", contentIndex: 2, partial });
      stream.push({ type: "text_delta", contentIndex: 0, delta: "A", partial });
      stream.push({ type: "thinking_delta", contentIndex: 1, delta: "plan", partial });
      stream.push({ type: "text_delta", contentIndex: 0, delta: "\uD83D", partial });
      stream.push({ type: "toolcall_delta", contentIndex: 2, delta: '{"x":1,"nested":{"b":2,', partial });
      stream.push({ type: "text_delta", contentIndex: 0, delta: "\uDE80", partial });
      stream.push({ type: "toolcall_delta", contentIndex: 2, delta: '"a":1}}', partial });
      stream.push({ type: "thinking_end", contentIndex: 1, content: "plan", partial });
      stream.push({ type: "text_end", contentIndex: 0, content: "A🚀", partial });
      const toolCall = { type: "toolCall", id: "call-185", name: "probe", arguments: { nested: { a: 1, b: 2 }, x: 1 } };
      stream.push({ type: "toolcall_end", contentIndex: 2, toolCall, partial });
      stream.push({ type: "done", reason: "toolUse", message: assistant([{ type: "text", text: "A🚀" }, { type: "thinking", thinking: "plan" }, toolCall], "toolUse") });
      return stream;
    },
  });
  pi.registerCommand("stream-ping", { handler: async (_args, ctx) => ctx.ui.notify("stream-worker-reused-185") });
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
function start(callbackId, invocationId, mode) {
  send({
    kind: "provider_stream_simple",
    callbackId,
    invocationId,
    abortable: true,
    model: { id: "stream-model", provider: "stream-production-e2e", api: "custom-stream" },
    streamContext: { mode, messages: [{ role: "user", content: "hello", timestamp: 1 }] },
    options: { apiKey: "secret", maxTokens: 128, sessionId: "session-185" },
    context: { mode: "print", hasUI: false },
  });
}
async function ack(eventRecord, ok = true) {
  send({ kind: "provider_stream_ack", invocationId: eventRecord.invocationId, sequence: eventRecord.sequence, ok, accepted: ok, ...(ok ? {} : { error: "rejected-for-test" }) });
}
async function drainSuccessful(callbackId) {
  start(callbackId, "good-185", "good");
  const events = [];
  for (;;) {
    const item = await record();
    if (item.type === "provider_stream_event") {
      events.push(item);
      await ack(item);
      continue;
    }
    assert.equal(item.ok, true, JSON.stringify(item));
    assert.equal(item.result.invocationId, "good-185");
    assert.equal(item.result.events, events.length);
    assert.equal(item.result.terminal, "done");
    return events;
  }
}
async function command(name, invocationId) {
  send({ kind: "command", name, rawArguments: "", flags: {}, invocationId, context: { mode: "print", hasUI: false } });
  return record();
}

try {
  const ready = await record();
  assert.equal(ready.type, "ready");
  const registration = ready.manifest.providers.find((entry) => entry.name === "stream-production-e2e");
  assert.ok(registration);
  const descriptor = registration.config.streamSimple;
  assert.equal(descriptor.__pi_callback_kind, "provider_method");
  assert.equal(descriptor.__pi_callback_path, "streamSimple");

  const events = await drainSuccessful(descriptor.__pi_callback_id);
  assert.deepEqual(events.map((entry) => entry.sequence), Array.from({ length: events.length }, (_, index) => index + 1));
  const textDeltas = events.filter((entry) => entry.event.type === "text_delta").map((entry) => entry.event.delta);
  assert.deepEqual(textDeltas, ["A", "", "🚀"]);
  assert.equal(events.at(-1).event.type, "done");
  assert.equal(events.at(-1).event.message.content[2].arguments.nested.a, 1);

  start(descriptor.__pi_callback_id, "throw-after-185", "throw-after-terminal");
  let terminalSeen = false;
  for (;;) {
    const item = await record();
    if (item.type === "provider_stream_event") {
      if (item.event.type === "done") terminalSeen = true;
      await ack(item);
      continue;
    }
    assert.equal(terminalSeen, true);
    assert.equal(item.ok, false);
    assert.match(item.error, /iterator-exploded-after-terminal-185/);
    break;
  }

  start(descriptor.__pi_callback_id, "mismatch-185", "tool-mismatch");
  for (;;) {
    const item = await record();
    if (item.type === "provider_stream_event") { await ack(item); continue; }
    assert.equal(item.ok, false);
    assert.match(item.error, /do not match accumulated deltas/);
    break;
  }

  start(descriptor.__pi_callback_id, "cancel-185", "cancel");
  const first = await record();
  assert.equal(first.type, "provider_stream_event");
  assert.equal(first.event.type, "start");
  send({ kind: "abort_current", invocationId: "cancel-185", reason: "cancelled-by-native-185" });
  const cancelled = await record();
  assert.equal(cancelled.ok, false);
  assert.match(cancelled.error, /cancelled-by-native-185/);

  start(descriptor.__pi_callback_id, "ignore-abort-185", "cancel-ignores-signal");
  const ignoredStart = await record();
  assert.equal(ignoredStart.type, "provider_stream_event");
  assert.equal(ignoredStart.event.type, "start");
  await ack(ignoredStart);
  send({ kind: "abort_current", invocationId: "ignore-abort-185", reason: "ignored-signal-abort-185" });
  const ignoredAbort = await record();
  assert.equal(ignoredAbort.ok, false);
  assert.match(ignoredAbort.error, /ignored-signal-abort-185/);

  start(descriptor.__pi_callback_id, "queue-overflow-185", "queue-overflow");
  const overflow = await record();
  assert.equal(overflow.ok, false);
  assert.match(overflow.error, /bounded pending queue/);

  start(descriptor.__pi_callback_id, "reject-ack-185", "good");
  const rejectedEvent = await record();
  assert.equal(rejectedEvent.type, "provider_stream_event");
  await ack(rejectedEvent, false);
  const rejected = await record();
  assert.equal(rejected.ok, false);
  assert.match(rejected.error, /rejected-for-test/);

  const reuse = await command("stream-ping", "reuse-185");
  assert.equal(reuse.ok, true);
  assert.match(reuse.result.message, /stream-worker-reused-185/);

  send({ kind: "shutdown" });
  assert.equal((await record()).ok, true);
  child.stdin.end();
  assert.equal(await new Promise((resolve) => child.once("close", resolve)), 0, stderr);
  console.log(`production provider streamSimple bridge e2e: ok (${events.length} ordered events)`);
} finally {
  if (child.exitCode === null) child.kill("SIGKILL");
  rmSync(temp, { recursive: true, force: true });
}
