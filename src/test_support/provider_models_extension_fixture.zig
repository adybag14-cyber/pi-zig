//! Original user-authored extension input from provider-refresh-models-bridge.mjs.
pub const source =
    \\
    \\export default function (pi) {
    \\  const model = (id, name = id) => ({ id, name, reasoning: false, input: ["text"], cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 }, contextWindow: 4096, maxTokens: 512 });
    \\  const config = {
    \\    name: "Refresh Production E2E",
    \\    baseUrl: "https://models.invalid/v1",
    \\    api: "openai-completions",
    \\    apiKey: "local",
    \\    models: [model("initial")],
    \\    async refreshModels(context) {
    \\      if (!(context.signal instanceof AbortSignal)) throw new Error("refresh AbortSignal missing");
    \\      if (!Object.isFrozen(context)) throw new Error("refresh context is mutable");
    \\      if (context.credential && !Object.isFrozen(context.credential)) throw new Error("credential is mutable");
    \\      if (context.stored && !Object.isFrozen(context.stored)) throw new Error("stored snapshot is mutable");
    \\      if (!context.allowNetwork && Object.hasOwn(context, "force")) throw new Error("offline force leaked");
    \\      if (context.stored?.mode === "reject") throw new Error("refresh-models-exploded-183");
    \\      if (context.stored?.mode === "abort") {
    \\        await context.publish({ persist: { models: [model("never")] } });
    \\        return [model("never")];
    \\      }
    \\      if (context.stored?.mode === "stale") {
    \\        const accepted = await context.publish({
    \\          persist: { models: [model("stale")] },
    \\          update: () => { config.models = [model("must-not-update")]; },
    \\        });
    \\        if (accepted) throw new Error("stale publication unexpectedly accepted");
    \\        return [model("stale-result")];
    \\      }
    \\      if (!context.allowNetwork) {
    \\        const restored = context.stored?.models ?? [model("offline-empty")];
    \\        const accepted = await context.publish({
    \\          update: () => { config.models = restored.map((entry) => ({ ...entry, name: entry.name + ":updated" })); },
    \\        });
    \\        if (!accepted) throw new Error("offline publication rejected");
    \\        return restored;
    \\      }
    \\      if (context.force !== true) throw new Error("online force missing");
    \\      if (context.credential?.tenant !== "corp") throw new Error("effective credential missing");
    \\      const fresh = [model("fresh", "Fresh")];
    \\      const accepted = await context.publish({
    \\        persist: { models: fresh, checkedAt: 183, etag: '"etag-183"' },
    \\        update: () => { config.models = fresh.map((entry) => ({ ...entry, name: entry.name + ":committed" })); },
    \\      });
    \\      if (!accepted) throw new Error("online publication rejected");
    \\      return fresh;
    \\    },
    \\  };
    \\  pi.registerProvider("refresh-production-e2e", config);
    \\  const objectState = { models: [model("object-initial")] };
    \\  pi.registerProvider({
    \\    id: "object-refresh-production-e2e",
    \\    name: "Object Refresh Production E2E",
    \\    baseUrl: "https://object-models.invalid/v1",
    \\    api: "openai-completions",
    \\    apiKey: "local",
    \\    getModels() { return objectState.models; },
    \\    async refreshModels(context) {
    \\      const next = [model("object-fresh", "Object Fresh")];
    \\      const accepted = await context.publish({ update: () => { objectState.models = next; } });
    \\      if (!accepted) throw new Error("object publication rejected");
    \\    },
    \\  });
    \\  pi.registerCommand("refresh-ping", { handler: async (_args, ctx) => ctx.ui.notify(config.models[0].name) });
    \\}
    \\
;
