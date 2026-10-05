//! Original user-authored provider-method input from the retired JS harness.
pub const source =
    \\
    \\export default function (pi) {
    \\  const closure = "production-bridge-181";
    \\  const config = {
    \\    name: "Provider E2E",
    \\    baseUrl: "https://provider.invalid/v1",
    \\    api: "openai-completions",
    \\    apiKey: "unused",
    \\    models: [{ id: "e2e", name: "E2E", reasoning: false, input: ["text"], cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 }, contextWindow: 4096, maxTokens: 512 }],
    \\    oauth: {
    \\      owner: "oauth-owner",
    \\      async refreshToken(credentials, signal) {
    \\        assertSignal(signal);
    \\        if (this.owner !== "oauth-owner") throw new Error("provider receiver was not retained");
    \\        return { ...credentials, access: closure + ":" + credentials.refresh };
    \\      },
    \\      getApiKey(credentials) {
    \\        if (this.owner !== "oauth-owner") throw new Error("provider key receiver was not retained");
    \\        return closure + ":" + credentials.access;
    \\      },
    \\      async waitForAbort(_credentials, signal) {
    \\        assertSignal(signal);
    \\        await new Promise((resolve, reject) => {
    \\          if (signal.aborted) return reject(signal.reason);
    \\          const timer = setTimeout(() => reject(new Error("abort not delivered")), 1500);
    \\          signal.addEventListener("abort", () => { clearTimeout(timer); reject(signal.reason); }, { once: true });
    \\        });
    \\      },
    \\    },
    \\    nested: { methods: [function (value) { return this.length + ":" + closure + ":" + value; }] },
    \\  };
    \\  function assertSignal(signal) {
    \\    if (!(signal instanceof AbortSignal)) throw new Error("provider signal missing");
    \\  }
    \\  pi.registerProvider("production-e2e", config);
    \\  pi.registerCommand("provider-replace", { handler: async () => pi.registerProvider("production-e2e", { name: "Provider E2E Renamed" }) });
    \\  pi.registerCommand("provider-cycle", { handler: async () => { const cyclic = {}; cyclic.self = cyclic; try { pi.registerProvider("production-e2e", { cyclic }); } catch {} } });
    \\  pi.registerCommand("provider-unregister", { handler: async () => pi.unregisterProvider("production-e2e") });
    \\  pi.registerCommand("provider-ping", { handler: async (_args, ctx) => ctx.ui.notify("worker-reused") });
    \\}
    \\
;
