// c268 model-resolver.ts executable bodies; TypeScript-only forms erased.
// The selected caller controls retain real imported component owners. Separate
// minimatch qualification is required for the matcher's full package contract.
(function (isValidThinkingLevel, modelsAreEqual, minimatch, defaultModelPerProvider) {
"use strict";
function splitThinkingSuffix(text) {
    const colonIndex = text.lastIndexOf(":");
    const suffix = text.substring(colonIndex + 1);
    if (colonIndex === -1 || !isValidThinkingLevel(suffix)) return undefined;
    return { base: text.substring(0, colonIndex), thinkingLevel: suffix };
}
function splitProviderPrefix(text, models) {
    const slashIndex = text.indexOf("/");
    if (slashIndex === -1) return undefined;
    const prefix = text.substring(0, slashIndex).trim().toLowerCase();
    const modelText = text.substring(slashIndex + 1).trim();
    if (!prefix || !modelText) return undefined;
    const provider = models.find((model) => model.provider.toLowerCase() === prefix)?.provider;
    return provider ? { provider, modelText } : undefined;
}
function resolveModelReference(request, models, usable) {
    const text = request.text.trim();
    if (!text) return { status: "not-found" };
    const constraint = request.provider?.toLowerCase();
    const pool = constraint ? models.filter((model) => model.provider.toLowerCase() === constraint) : models;
    const result = resolveText(text, request, pool, usable);
    if (result.status !== "not-found") return result;
    const split = splitProviderPrefix(text, pool);
    const anchor = constraint ? pool[0] : pool.find((model) => model.provider === split?.provider);
    if (!anchor) return result;
    const modelText = split?.modelText ?? text;
    const suffix = request.thinkingSuffix === "none" ? undefined : splitThinkingSuffix(modelText);
    return {
        status: "not-found",
        target: {
            provider: anchor.provider,
            providerModels: [anchor, ...pool.filter((model) => model.provider === anchor.provider && model !== anchor)],
            modelText,
            modelId: suffix?.base ?? modelText,
            thinkingLevel: suffix?.thinkingLevel,
        },
    };
}
function resolveText(text, request, pool, usable) {
    const reference = selectReference(text, pool, request.fuzzy, usable);
    if (reference) return reference;
    if (request.fuzzy) {
        const fuzzy = selectFuzzy(fuzzyMatches(text, pool), usable);
        if (fuzzy) return fuzzy;
    }
    if (request.thinkingSuffix === "none") return { status: "not-found" };
    const thinking = splitThinkingSuffix(text);
    if (thinking) {
        const inner = resolveText(thinking.base, request, pool, usable);
        if (inner.status === "not-found") return inner;
        return { ...inner, thinkingLevel: inner.warning ? undefined : thinking.thinkingLevel };
    }
    if (request.thinkingSuffix === "strict") return { status: "not-found" };
    const colonIndex = text.lastIndexOf(":");
    if (colonIndex === -1) return { status: "not-found" };
    const suffix = text.substring(colonIndex + 1);
    const inner = resolveText(text.substring(0, colonIndex), request, pool, usable);
    if (inner.status === "not-found") return inner;
    return {
        ...inner,
        thinkingLevel: undefined,
        warning: `Invalid thinking level "${suffix}" in pattern "${text}". Using default instead.`,
    };
}
function selectReference(text, pool, fuzzy, usable) {
    const lowerText = text.toLowerCase();
    const raw = pool.filter((model) => model.id.toLowerCase() === lowerText);
    const split = splitProviderPrefix(text, pool);
    let named;
    if (split) {
        const providerModels = pool.filter((model) => model.provider === split.provider);
        const lowerModelText = split.modelText.toLowerCase();
        named =
            providerModels.find((model) => model.id.toLowerCase() === lowerModelText) ??
            raw.find((model) => model.provider === split.provider) ??
            (fuzzy ? bestFuzzyMatch(fuzzyMatches(split.modelText, providerModels)) : undefined);
    }
    const others = raw.filter((model) => model !== named);
    const candidates = named ? [named, ...others] : others;
    if (candidates.length === 0) return undefined;
    if (new Set(candidates.map((model) => model.provider)).size === 1)
        return { status: "resolved", model: candidates[0] };
    if (named && usable(named.provider)) return { status: "resolved", model: named };
    const usableOthers = others.filter((model) => usable(model.provider));
    if (usableOthers.length === 1) return { status: "resolved", model: usableOthers[0] };
    if (usableOthers.length === 0 && named) return { status: "resolved", model: named };
    return { status: "ambiguous", candidates, usableCount: usableOthers.length };
}
function fuzzyMatches(text, models) {
    const lowerText = text.toLowerCase();
    return models.filter(
        (model) => model.id.toLowerCase().includes(lowerText) || model.name?.toLowerCase().includes(lowerText),
    );
}
function selectFuzzy(matches, usable) {
    if (matches.length === 0) return undefined;
    const multipleProviders = new Set(matches.map((model) => model.provider)).size > 1;
    const usableMatches = multipleProviders ? matches.filter((model) => usable(model.provider)) : [];
    const pool = usableMatches.length > 0 ? usableMatches : matches;
    const best = bestFuzzyMatch(pool);
    if (!best) return undefined;
    const tied = pool.filter((model) => model.id === best.id);
    if (new Set(tied.map((model) => model.provider)).size === 1) return { status: "resolved", model: best };
    return {
        status: "ambiguous",
        candidates: tied,
        usableCount: usableMatches.length > 0 ? tied.length : 0,
    };
}
function bestFuzzyMatch(matches) {
    const aliases = matches.filter((model) => isAlias(model.id));
    return [...(aliases.length > 0 ? aliases : matches)].sort((a, b) => b.id.localeCompare(a.id))[0];
}
function isAlias(id) {
    return id.endsWith("-latest") || !/-\d{8}$/.test(id);
}
function buildFallbackModel(providerModels, modelId) {
    const defaultId = defaultModelPerProvider[providerModels[0].provider];
    const baseModel = defaultId
        ? (providerModels.find((m) => m.id === defaultId) ?? providerModels[0])
        : providerModels[0];
    return {
        ...baseModel,
        id: modelId,
        name: modelId,
    };
}
function resolveModelScopeFromModels(patterns, models) {
    const scopedModels = [];
    const diagnostics = [];
    const add = (model, thinkingLevel) => {
        if (!scopedModels.some((scoped) => modelsAreEqual(scoped.model, model))) {
            scopedModels.push({ model, thinkingLevel });
        }
    };
    const noMatch = (pattern) =>
        diagnostics.push({ type: "warning", code: "no-match", message: `No models match pattern "${pattern}"`, pattern });
    const ambiguous = (pattern, candidates) => {
        const providers = [...new Set(candidates.map((m) => m.provider))].sort((a, b) => a.localeCompare(b));
        diagnostics.push({
            type: "warning",
            code: "ambiguous",
            message: `Pattern "${pattern}" matches several providers: ${providers.join(", ")}. Use provider/id to choose one.`,
            pattern,
        });
    };
    for (const pattern of patterns) {
        if (pattern.includes("*") || pattern.includes("?") || pattern.includes("[")) {
            const thinking = splitThinkingSuffix(pattern);
            const globPattern = thinking?.base ?? pattern;
            const thinkingLevel = thinking?.thinkingLevel;
            const exact = resolveModelReference(
                { text: globPattern, thinkingSuffix: "none", fuzzy: false },
                models,
                () => true,
            );
            let matches = [];
            if (exact.status === "resolved") matches = [exact.model];
            else if (exact.status === "ambiguous") {
                matches = exact.candidates;
                ambiguous(pattern, matches);
            } else {
                matches = models.filter(
                    (m) =>
                        minimatch(`${m.provider}/${m.id}`, globPattern, { nocase: true }) ||
                        minimatch(m.id, globPattern, { nocase: true }),
                );
            }
            if (matches.length === 0) noMatch(pattern);
            for (const model of matches) add(model, thinkingLevel);
            continue;
        }
        const result = resolveModelReference(
            { text: pattern, thinkingSuffix: "lenient", fuzzy: true },
            models,
            () => true,
        );
        if (result.status === "not-found") {
            noMatch(pattern);
            continue;
        }
        if (result.warning) {
            diagnostics.push({ type: "warning", code: "invalid-thinking-level", message: result.warning, pattern });
        }
        if (result.status === "ambiguous") ambiguous(pattern, result.candidates);
        const matches = result.status === "resolved" ? [result.model] : result.candidates;
        for (const model of matches) add(model, result.thinkingLevel);
    }
    return { scopedModels, diagnostics };
}
async function resolveModelScopeWithDiagnostics(patterns, modelRuntime, options) {
    return resolveModelScopeFromModels(patterns, await modelRuntime.getAvailable(undefined, options));
}
function resolveCliModel(options) {
    const { cliProvider, cliModel, cliThinking, inlineApiKey, modelRuntime } = options;
    if (!cliModel) {
        return { model: undefined, warning: undefined, error: undefined };
    }
    const models = [...modelRuntime.getModels()];
    if (models.length === 0) {
        return {
            model: undefined,
            warning: undefined,
            error: "No models available. Check your installation or add models to models.json.",
        };
    }
    const provider = cliProvider
        ? models.find((m) => m.provider.toLowerCase() === cliProvider.toLowerCase())?.provider
        : undefined;
    if (cliProvider && !provider) {
        return {
            model: undefined,
            warning: undefined,
            error: `Unknown provider "${cliProvider}". Use --list-models to see available providers/models.`,
        };
    }
    const result = resolveModelReference(
        { text: cliModel, provider, thinkingSuffix: "strict", fuzzy: true },
        models,
        inlineApiKey ? () => false : (providerId) => modelRuntime.hasConfiguredAuth(providerId),
    );
    if (result.status === "resolved") {
        return { model: result.model, thinkingLevel: result.thinkingLevel, warning: result.warning, error: undefined };
    }
    if (result.status === "ambiguous") {
        const matches = result.candidates
            .map((m) => `${m.provider}/${m.id}`)
            .sort((a, b) => a.localeCompare(b))
            .join(", ");
        const authHint = inlineApiKey
            ? "--api-key does not choose a provider."
            : result.usableCount === 0
                ? "No matching provider is authenticated."
                : "More than one matching provider is authenticated.";
        return {
            model: undefined,
            warning: undefined,
            error: `Model "${cliModel}" is ambiguous across providers: ${matches}. ${authHint} Use --provider or provider/model.`,
        };
    }
    const { target } = result;
    if (!target) {
        return {
            model: undefined,
            warning: undefined,
            error: `Model "${cliModel}" not found. Use --list-models to see available models.`,
        };
    }
    const modelId = cliThinking ? target.modelText : target.modelId;
    const fallbackThinking = cliThinking ? undefined : target.thinkingLevel;
    const fallbackModel = buildFallbackModel(target.providerModels, modelId);
    const requestedThinking = cliThinking ?? fallbackThinking;
    return {
        model: requestedThinking && requestedThinking !== "off" ? { ...fallbackModel, reasoning: true } : fallbackModel,
        thinkingLevel: fallbackThinking,
        warning: `Model "${modelId}" not found for provider "${target.provider}". Using custom model id.`,
        error: undefined,
    };
}
return { resolveCliModel, resolveModelScopeWithDiagnostics };
})
