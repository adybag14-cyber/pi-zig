#!/usr/bin/env node

import { createHash } from "node:crypto";
import { readFileSync, unlinkSync, writeFileSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { spawnSync } from "node:child_process";

const scriptDir = dirname(fileURLToPath(import.meta.url));
const repoRoot = resolve(scriptDir, "..");
const sourcePath = resolve(repoRoot, "src/ai/catalog_source.json");
const outputPath = resolve(repoRoot, "src/ai/catalog_generated.zig");

const apiTransport = {
  "anthropic-messages": "anthropic",
  "azure-openai-responses": "openai",
  "bedrock-converse-stream": "amazon_bedrock",
  "google-generative-ai": "google",
  "google-vertex": "google",
  "mistral-conversations": "mistral",
  "openai-codex-responses": "openai",
  "openai-completions": "openai",
  "openai-responses": "openai",
};

const apiEnum = {
  "anthropic-messages": "anthropic_messages",
  "azure-openai-responses": "azure_openai_responses",
  "bedrock-converse-stream": "bedrock_converse_stream",
  "google-generative-ai": "google_generative_ai",
  "google-vertex": "google_vertex",
  "mistral-conversations": "mistral_conversations",
  "openai-codex-responses": "openai_codex_responses",
  "openai-completions": "openai_completions",
  "openai-responses": "openai_responses",
};

const compatFields = {
  allowEmptySignature: "allow_empty_signature",
  cacheControlFormat: "cache_control_format",
  deferredToolsMode: "deferred_tools_mode",
  forceAdaptiveThinking: "force_adaptive_thinking",
  maxTokensField: "max_tokens_field",
  requiresAssistantAfterToolResult: "requires_assistant_after_tool_result",
  requiresReasoningContentOnAssistantMessages: "requires_reasoning_content_on_assistant_messages",
  requiresThinkingAsText: "requires_thinking_as_text",
  requiresToolResultName: "requires_tool_result_name",
  sendSessionAffinityHeaders: "send_session_affinity_headers",
  sessionAffinityFormat: "session_affinity_format",
  supportsAdditionalTools: "supports_additional_tools",
  supportsCacheControlOnTools: "supports_cache_control_on_tools",
  supportsDeveloperRole: "supports_developer_role",
  supportsEagerToolInputStreaming: "supports_eager_tool_input_streaming",
  supportsExplicitPromptCacheMode: "supports_explicit_prompt_cache_mode",
  supportsFinishReason: "supports_finish_reason",
  supportsLongCacheRetention: "supports_long_cache_retention",
  supportsOpenAIGrammarTools: "supports_openai_grammar_tools",
  supportsReasoningEffort: "supports_reasoning_effort",
  supportsStore: "supports_store",
  supportsStrictMode: "supports_strict_mode",
  supportsStrictTools: "supports_strict_tools",
  supportsTemperature: "supports_temperature",
  supportsThinkingTokenBudget: "supports_thinking_token_budget",
  supportsToolReferences: "supports_tool_references",
  supportsToolSearch: "supports_tool_search",
  supportsUsageInStreaming: "supports_usage_in_streaming",
  thinkingFormat: "thinking_format",
  zaiToolStream: "zai_tool_stream",
};

const enumCompatValues = {
  cacheControlFormat: { anthropic: "anthropic" },
  deferredToolsMode: { kimi: "kimi" },
  maxTokensField: {
    max_completion_tokens: "max_completion_tokens",
    max_tokens: "max_tokens",
  },
  sessionAffinityFormat: {
    openai: "openai",
    "openai-nosession": "openai_nosession",
    openrouter: "openrouter",
  },
  thinkingFormat: {
    "ant-ling": "ant_ling",
    baseten: "baseten",
    "chat-template": "chat_template",
    deepseek: "deepseek",
    openai: "openai",
    openrouter: "openrouter",
    qwen: "qwen",
    "qwen-chat-template": "qwen_chat_template",
    "string-thinking": "string_thinking",
    together: "together",
    zai: "zai",
  },
};

const thinkingFields = ["off", "minimal", "low", "medium", "high", "xhigh", "max"];
const modelFields = new Set(["api", "baseUrl", "compat", "contextWindow", "cost", "headers", "id", "input", "maxTokens", "name", "provider", "reasoning", "samplingParams", "thinkingLevelMap"]);
const costFields = new Set(["cacheRead", "cacheWrite", "input", "output", "tiers"]);
const costTierFields = new Set(["cacheRead", "cacheWrite", "input", "inputTokensAbove", "output"]);

function fail(message) {
  throw new Error(message);
}

function zigString(value) {
  return JSON.stringify(value);
}

function zigNumber(value, label) {
  if (typeof value !== "number" || !Number.isFinite(value)) fail(`${label} must be a finite number`);
  return Object.is(value, -0) ? "0" : String(value);
}

function renderThinkingMap(map, identity) {
  if (map === undefined) return null;
  const fields = [];
  for (const key of Object.keys(map)) {
    if (!thinkingFields.includes(key)) fail(`${identity}: unsupported thinking level ${key}`);
  }
  for (const key of thinkingFields) {
    if (!(key in map)) continue;
    const value = map[key];
    if (value === null) fields.push(`.${key} = .unsupported`);
    else if (typeof value === "string" && value.length > 0) fields.push(`.${key} = .{ .mapped = ${zigString(value)} }`);
    else fail(`${identity}: invalid thinkingLevelMap.${key}`);
  }
  return `.{ ${fields.join(", ")} }`;
}

function renderCost(cost, identity) {
  if (!cost || typeof cost !== "object") fail(`${identity}: missing cost`);
  for (const key of Object.keys(cost)) if (!costFields.has(key)) fail(`${identity}: unsupported cost field ${key}`);
  const fields = [
    `.input = ${zigNumber(cost.input, `${identity}.cost.input`)}`,
    `.output = ${zigNumber(cost.output, `${identity}.cost.output`)}`,
    `.cache_read = ${zigNumber(cost.cacheRead, `${identity}.cost.cacheRead`)}`,
    `.cache_write = ${zigNumber(cost.cacheWrite, `${identity}.cost.cacheWrite`)}`,
  ];
  if (cost.tiers !== undefined) {
    if (!Array.isArray(cost.tiers)) fail(`${identity}: cost.tiers must be an array`);
    const tiers = cost.tiers.map((tier, index) => {
      for (const key of Object.keys(tier)) if (!costTierFields.has(key)) fail(`${identity}: unsupported cost tier field ${key}`);
      return `.{ .input_tokens_above = ${zigNumber(tier.inputTokensAbove, `${identity}.cost.tiers[${index}].inputTokensAbove`)}, .input = ${zigNumber(tier.input, `${identity}.cost.tiers[${index}].input`)}, .output = ${zigNumber(tier.output, `${identity}.cost.tiers[${index}].output`)}, .cache_read = ${zigNumber(tier.cacheRead, `${identity}.cost.tiers[${index}].cacheRead`)}, .cache_write = ${zigNumber(tier.cacheWrite, `${identity}.cost.tiers[${index}].cacheWrite`)} }`;
    });
    fields.push(`.tiers = &.{ ${tiers.join(", ")} }`);
  }
  return `.{ ${fields.join(", ")} }`;
}

function renderHeaders(headers, identity) {
  if (headers === undefined) return null;
  if (!headers || typeof headers !== "object" || Array.isArray(headers)) fail(`${identity}: headers must be an object`);
  const rows = Object.entries(headers).map(([name, value]) => {
    if (typeof value !== "string") fail(`${identity}: header ${name} must be a string`);
    return `.{ .name = ${zigString(name)}, .value = ${zigString(value)} }`;
  });
  return `&.{ ${rows.join(", ")} }`;
}

function renderSampling(params, identity) {
  if (params === undefined) return null;
  if (!params || typeof params !== "object" || Array.isArray(params)) fail(`${identity}: samplingParams must be an object`);
  const rows = Object.entries(params).map(([name, value]) => `.{ .name = ${zigString(name)}, .value_json = ${zigString(JSON.stringify(value))} }`);
  return `&.{ ${rows.join(", ")} }`;
}

function renderCompat(compat, identity) {
  if (compat === undefined) return null;
  if (!compat || typeof compat !== "object" || Array.isArray(compat)) fail(`${identity}: compat must be an object`);
  const fields = [];
  for (const [sourceName, value] of Object.entries(compat)) {
    if (sourceName === "chatTemplateArgs") {
      const expected = JSON.stringify({ enable_thinking: { $var: "thinking.enabled" } });
      if (JSON.stringify(value) !== expected) fail(`${identity}: unsupported chatTemplateArgs shape`);
      fields.push(".chat_template_args_enable_thinking = true");
      continue;
    }
    if (sourceName === "chatTemplateKwargs" || sourceName === "openRouterRouting" || sourceName === "vercelGatewayRouting") {
      fail(`${identity}: generated catalog unexpectedly contains ${sourceName}`);
    }
    const targetName = compatFields[sourceName];
    if (!targetName) fail(`${identity}: unsupported compat field ${sourceName}`);
    if (typeof value === "boolean") {
      fields.push(`.${targetName} = ${value}`);
      continue;
    }
    const mapping = enumCompatValues[sourceName];
    if (typeof value === "string" && mapping?.[value]) {
      fields.push(`.${targetName} = .${mapping[value]}`);
      continue;
    }
    fail(`${identity}: unsupported compat value for ${sourceName}`);
  }
  return `.{ ${fields.join(", ")} }`;
}

function applyCurrentFixes(model) {
  if (model.provider === "openrouter" && model.id === "openrouter/free") {
    model.thinkingLevelMap = { ...(model.thinkingLevelMap ?? {}), off: null };
  }
  return model;
}

function renderModel(sourceModel) {
  const model = applyCurrentFixes(structuredClone(sourceModel));
  const identity = `${model.provider}/${model.id}`;
  for (const key of Object.keys(model)) if (!modelFields.has(key)) fail(`${identity}: unsupported model field ${key}`);
  const transport = apiTransport[model.api];
  const api = apiEnum[model.api];
  if (!transport || !api) fail(`${identity}: unsupported API ${model.api}`);
  if (!model.id || !model.name || !model.provider || typeof model.baseUrl !== "string") fail(`${identity}: incomplete model identity`);
  if (!Array.isArray(model.input) || !model.input.includes("text")) fail(`${identity}: text input is required`);
  for (const input of model.input) if (input !== "text" && input !== "image") fail(`${identity}: unsupported input ${input}`);

  const fields = [
    `.provider = .${transport}`,
    `.provider_id = ${zigString(model.provider)}`,
    `.id = ${zigString(model.id)}`,
    `.display = ${zigString(model.name)}`,
    `.base_url = ${zigString(model.baseUrl)}`,
    `.reasoning = ${Boolean(model.reasoning)}`,
    `.input_image = ${model.input.includes("image")}`,
    `.context_window = ${zigNumber(model.contextWindow, `${identity}.contextWindow`)}`,
    `.max_tokens = ${zigNumber(model.maxTokens, `${identity}.maxTokens`)}`,
    `.cost = ${renderCost(model.cost, identity)}`,
    `.api = .${api}`,
  ];
  const thinkingMap = renderThinkingMap(model.thinkingLevelMap, identity);
  if (thinkingMap) fields.push(`.thinking_level_map = ${thinkingMap}`);
  const headers = renderHeaders(model.headers, identity);
  if (headers) fields.push(`.headers = ${headers}`);
  const sampling = renderSampling(model.samplingParams, identity);
  if (sampling) fields.push(`.sampling_params = ${sampling}`);
  const compat = renderCompat(model.compat, identity);
  if (compat) fields.push(`.compat = ${compat}`);
  return `        .{ ${fields.join(", ")} },`;
}

function normalizeLineEndings(value) {
  return value.replaceAll("\r\n", "\n");
}

const sourceText = normalizeLineEndings(readFileSync(sourcePath, "utf8"));
const sourceHash = createHash("sha256").update(sourceText).digest("hex");
const source = JSON.parse(sourceText);
if (source.schemaVersion !== 1) fail("unsupported catalog source schema");
if (source.upstreamPackage !== "@earendil-works/pi-ai" || source.upstreamVersion !== "0.84.1") fail("unexpected upstream catalog provenance");
if (!Array.isArray(source.models) || source.models.length !== source.modelCount || source.modelCount !== 1258) fail("catalog must contain exactly 1258 models");

const seen = new Set();
const providers = new Set();
for (const model of source.models) {
  const key = `${model.provider}\0${model.id}`;
  if (seen.has(key)) fail(`duplicate model ${model.provider}/${model.id}`);
  seen.add(key);
  providers.add(model.provider);
}
if (providers.size !== 39) fail(`expected 39 providers, found ${providers.size}`);

const output = `//! Generated from catalog_source.json. Do not edit manually.\n//! Source SHA-256: ${sourceHash}\n\npub const source_sha256 = ${zigString(sourceHash)};\npub const upstream_version = ${zigString(source.upstreamVersion)};\npub const model_count: usize = ${source.models.length};\npub const provider_count: usize = ${providers.size};\n\npub fn rows(comptime ModelInfo: type) [model_count]ModelInfo {\n    return .{\n${source.models.map(renderModel).join("\n")}\n    };\n}\n`;

function formatZig(path) {
  const zig = process.env.ZIG_EXE ?? process.env.ZIG ?? "zig";
  const result = spawnSync(zig, ["fmt", path], { encoding: "utf8" });
  if (result.error) fail(`could not execute ${zig}: ${result.error.message}`);
  if (result.status !== 0) fail(`zig fmt failed: ${result.stderr || result.stdout}`);
}

if (process.argv.includes("--check")) {
  const temporaryPath = `${outputPath}.tmp.zig`;
  writeFileSync(temporaryPath, output);
  formatZig(temporaryPath);
  const expected = normalizeLineEndings(readFileSync(temporaryPath, "utf8"));
  unlinkSync(temporaryPath);
  const current = normalizeLineEndings(readFileSync(outputPath, "utf8"));
  if (current !== expected) fail(`${outputPath} is stale; run scripts/generate_builtin_catalog.mjs`);
} else {
  writeFileSync(outputPath, output);
  formatZig(outputPath);
}

process.stdout.write(`catalog_models=${source.models.length}\nproviders=${providers.size}\nsource_sha256=${sourceHash}\n`);
