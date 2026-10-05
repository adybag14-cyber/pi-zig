//! Original user-authored extension input from provider-stream-simple-bridge.mjs.
pub const source =
    \\
    \\import { createAssistantMessageEventStream } from "@mariozechner/pi-ai";
    \\const usage = { input: 3, output: 4, cacheRead: 1, cacheWrite: 0, totalTokens: 8, cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0, total: 0 } };
    \\const assistant = (content, stopReason = "pending") => ({ role: "assistant", content, api: "custom-stream", provider: "stream-production-e2e", model: "stream-model", usage, stopReason, timestamp: 185 });
    \\export default function (pi) {
    \\  pi.registerProvider("stream-production-e2e", {
    \\    name: "Stream Production E2E",
    \\    api: "custom-stream",
    \\    apiKey: "local",
    \\    models: [{ id: "stream-model", name: "Stream Model", reasoning: true, input: ["text"], cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 }, contextWindow: 4096, maxTokens: 512 }],
    \\    streamSimple(model, context, options) {
    \\      if (model.id !== "stream-model") throw new Error("model snapshot missing");
    \\      if (!Object.isFrozen(model) || !Object.isFrozen(context) || !Object.isFrozen(options)) throw new Error("stream inputs are mutable");
    \\      if (!(options.signal instanceof AbortSignal)) throw new Error("stream AbortSignal missing");
    \\      const mode = context.mode;
    \\      if (mode === "throw-after-terminal") {
    \\        return (async function* () {
    \\          yield { type: "start", partial: assistant([]) };
    \\          yield { type: "done", reason: "stop", message: assistant([{ type: "text", text: "premature" }], "stop") };
    \\          throw new Error("iterator-exploded-after-terminal-185");
    \\        })();
    \\      }
    \\      if (mode === "tool-mismatch") {
    \\        return (async function* () {
    \\          yield { type: "start", partial: assistant([]) };
    \\          yield { type: "toolcall_start", contentIndex: 0, partial: assistant([]) };
    \\          yield { type: "toolcall_delta", contentIndex: 0, delta: '{"x":1}', partial: assistant([]) };
    \\          yield { type: "toolcall_end", contentIndex: 0, toolCall: { type: "toolCall", id: "bad", name: "bad", arguments: { x: 2 } }, partial: assistant([]) };
    \\          yield { type: "done", reason: "toolUse", message: assistant([], "toolUse") };
    \\        })();
    \\      }
    \\      if (mode === "cancel") {
    \\        return (async function* () {
    \\          yield { type: "start", partial: assistant([]) };
    \\          await new Promise((resolve, reject) => {
    \\            options.signal.addEventListener("abort", () => reject(options.signal.reason), { once: true });
    \\          });
    \\        })();
    \\      }
    \\      if (mode === "cancel-ignores-signal") {
    \\        return (async function* () {
    \\          yield { type: "start", partial: assistant([]) };
    \\          await new Promise(() => {});
    \\        })();
    \\      }
    \\      if (mode === "queue-overflow") {
    \\        const stream = createAssistantMessageEventStream();
    \\        for (let index = 0; index < 65; index++) stream.push({ type: "queued", index });
    \\        return stream;
    \\      }
    \\      const stream = createAssistantMessageEventStream();
    \\      const partial = assistant([]);
    \\      stream.push({ type: "start", partial });
    \\      stream.push({ type: "text_start", contentIndex: 0, partial });
    \\      stream.push({ type: "thinking_start", contentIndex: 1, partial });
    \\      stream.push({ type: "toolcall_start", contentIndex: 2, partial });
    \\      stream.push({ type: "text_delta", contentIndex: 0, delta: "A", partial });
    \\      stream.push({ type: "thinking_delta", contentIndex: 1, delta: "plan", partial });
    \\      stream.push({ type: "text_delta", contentIndex: 0, delta: "\uD83D", partial });
    \\      stream.push({ type: "toolcall_delta", contentIndex: 2, delta: '{"x":1,"nested":{"b":2,', partial });
    \\      stream.push({ type: "text_delta", contentIndex: 0, delta: "\uDE80", partial });
    \\      stream.push({ type: "toolcall_delta", contentIndex: 2, delta: '"a":1}}', partial });
    \\      stream.push({ type: "thinking_end", contentIndex: 1, content: "plan", partial });
    \\      stream.push({ type: "text_end", contentIndex: 0, content: "A🚀", partial });
    \\      const toolCall = { type: "toolCall", id: "call-185", name: "probe", arguments: { nested: { a: 1, b: 2 }, x: 1 } };
    \\      stream.push({ type: "toolcall_end", contentIndex: 2, toolCall, partial });
    \\      stream.push({ type: "done", reason: "toolUse", message: assistant([{ type: "text", text: "A🚀" }, { type: "thinking", thinking: "plan" }, toolCall], "toolUse") });
    \\      return stream;
    \\    },
    \\  });
    \\  pi.registerCommand("stream-ping", { handler: async (_args, ctx) => ctx.ui.notify("stream-worker-reused-185") });
    \\}
    \\
;
