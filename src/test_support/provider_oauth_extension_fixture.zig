//! Original user-authored OAuth input from the legacy protocol harness.
pub const source =
    \\
    \\export default function (pi) {
    \\  let attempt = 0;
    \\  pi.registerProvider("oauth-production-e2e", {
    \\    name: "OAuth Production E2E",
    \\    baseUrl: "https://oauth.invalid/v1",
    \\    api: "openai-completions",
    \\    apiKey: "unused",
    \\    models: [{ id: "oauth-e2e", name: "OAuth E2E", reasoning: false, input: ["text"], cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 }, contextWindow: 4096, maxTokens: 512 }],
    \\    oauth: {
    \\      async login(callbacks) {
    \\        attempt += 1;
    \\        if (!(callbacks.signal instanceof AbortSignal)) throw new Error("OAuth AbortSignal missing");
    \\        if (attempt === 1) {
    \\          callbacks.onAuth({ url: "https://login.invalid/start", instructions: "Open the browser" });
    \\          callbacks.onDeviceCode({ verificationUri: "https://device.invalid", userCode: "DEVICE-182", intervalSeconds: 7, expiresInSeconds: 600, instructions: "Enter the code" });
    \\          callbacks.onProgress("waiting-for-user");
    \\          const prompt = await callbacks.onPrompt({ message: "Tenant?", placeholder: "tenant", secret: true });
    \\          const manual = await callbacks.onManualCodeInput();
    \\          const team = await callbacks.onSelect({ message: "Team?", options: [{ id: "team-a", label: "Team A" }, { value: "team-b", label: "Team B", description: "Preferred" }] });
    \\          return {
    \\            refresh: "refresh-182",
    \\            access: "access-182",
    \\            expires: 9999999999999,
    \\            tenant: { prompt, manual, team },
    \\            arbitrary: { retained: true, generation: attempt },
    \\          };
    \\        }
    \\        if (attempt === 2) {
    \\          const answer = await callbacks.onPrompt({ message: "This request will be aborted" });
    \\          return { refresh: "must-not-persist", access: String(answer), expires: 9999999999999 };
    \\        }
    \\        if (attempt === 3) {
    \\          return { refresh: "reuse-refresh", access: "worker-reused-after-abort", expires: 9999999999999 };
    \\        }
    \\        throw new Error("oauth-login-exploded-182");
    \\      },
    \\      getApiKey(credentials) { return "derived:" + credentials.access; },
    \\    },
    \\  });
    \\  pi.registerCommand("oauth-unregister", { handler: async () => pi.unregisterProvider("oauth-production-e2e") });
    \\}
    \\
;
