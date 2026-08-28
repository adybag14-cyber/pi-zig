import { registerHooks, stripTypeScriptTypes } from 'node:module';
import { readFileSync } from 'node:fs';
import { fileURLToPath, pathToFileURL } from 'node:url';
import path from 'node:path';
import readline from 'node:readline';
import { spawn } from 'node:child_process';

// File-based launch passes the bridge itself as argv[1] and the extension as
// argv[2]. Keep argv[1] fallback for older embedded `node -e` hosts.
const extensionPath = process.argv[2] ?? process.argv[1];
if (!extensionPath) throw new Error('missing extension path');

const originalConsole = globalThis.console;
const stderrWrite = (...parts) => process.stderr.write(parts.map((part) => typeof part === 'string' ? part : JSON.stringify(part)).join(' ') + '\n');
globalThis.console = { ...originalConsole, log: stderrWrite, info: stderrWrite, debug: stderrWrite, warn: stderrWrite, error: stderrWrite };

const optionalMarker = Symbol('optional');
const cleanSchema = (value) => {
  if (Array.isArray(value)) return value.map(cleanSchema);
  if (!value || typeof value !== 'object') return value;
  const out = {};
  for (const [key, item] of Object.entries(value)) {
    if (key === '__piOptional') continue;
    out[key] = cleanSchema(item);
  }
  return out;
};
const Type = {
  Any: (options = {}) => ({ ...options }),
  Unknown: (options = {}) => ({ ...options }),
  String: (options = {}) => ({ type: 'string', ...options }),
  Number: (options = {}) => ({ type: 'number', ...options }),
  Integer: (options = {}) => ({ type: 'integer', ...options }),
  Boolean: (options = {}) => ({ type: 'boolean', ...options }),
  Null: (options = {}) => ({ type: 'null', ...options }),
  Literal: (value, options = {}) => ({ const: value, type: value === null ? 'null' : typeof value, ...options }),
  Enum: (value, options = {}) => ({ enum: Object.values(value).filter((v) => typeof v !== 'number'), ...options }),
  Array: (items, options = {}) => ({ type: 'array', items: cleanSchema(items), ...options }),
  Tuple: (items, options = {}) => ({ type: 'array', prefixItems: items.map(cleanSchema), minItems: items.length, maxItems: items.length, ...options }),
  Union: (items, options = {}) => ({ anyOf: items.map(cleanSchema), ...options }),
  Intersect: (items, options = {}) => ({ allOf: items.map(cleanSchema), ...options }),
  Record: (key, value, options = {}) => ({ type: 'object', additionalProperties: cleanSchema(value), ...options }),
  Optional: (schema) => ({ ...schema, __piOptional: true }),
  Object: (properties = {}, options = {}) => {
    const cleaned = {};
    const required = [];
    for (const [name, schema] of Object.entries(properties)) {
      cleaned[name] = cleanSchema(schema);
      if (!schema?.__piOptional) required.push(name);
    }
    const out = { type: 'object', properties: cleaned, ...options };
    if (required.length) out.required = required;
    return out;
  },
};
const StringEnum = (values, options = {}) => ({ type: 'string', enum: [...values], ...options });
const uuidv7 = () => `${Date.now().toString(16).padStart(12, '0')}-7000-8000-${Math.random().toString(16).slice(2, 14).padEnd(12, '0')}`;
const defineTool = (tool) => tool;
const identityToolFactory = (options = {}) => ({ ...options, parameters: options.parameters ?? Type.Object({}), async execute() { return { content: [{ type: 'text', text: 'Tool compatibility shim is not executable directly.' }], details: {} }; } });
const builtinToolSpecs = {
  read: {
    description: 'Read a file from the filesystem. Supports optional 1-indexed line offset and limit.',
    parameters: Type.Object({
      path: Type.String({ description: 'Path to the file to read (relative or absolute)' }),
      offset: Type.Optional(Type.Number({ description: 'Line number to start reading from (1-indexed)' })),
      limit: Type.Optional(Type.Number({ description: 'Maximum number of lines to read' })),
    }),
  },
  write: {
    description: 'Write content to a file, creating parent directories as needed.',
    parameters: Type.Object({ path: Type.String(), content: Type.String() }),
  },
  edit: {
    description: 'Edit a single file using exact text replacement.',
    parameters: Type.Object({
      path: Type.String(),
      edits: Type.Array(Type.Object({ oldText: Type.String(), newText: Type.String() })),
    }),
  },
  bash: {
    description: 'Run a shell command and return stdout, stderr, and exit code. Optional timeout in seconds.',
    parameters: Type.Object({ command: Type.String(), timeout: Type.Optional(Type.Number()) }),
  },
  grep: {
    description: 'Search files for a pattern.',
    parameters: Type.Object({
      pattern: Type.String(), path: Type.Optional(Type.String()), glob: Type.Optional(Type.String()),
      ignoreCase: Type.Optional(Type.Boolean()), literal: Type.Optional(Type.Boolean()),
      limit: Type.Optional(Type.Number()), context: Type.Optional(Type.Number()),
    }),
  },
  find: {
    description: 'Find files by glob-like pattern.',
    parameters: Type.Object({ pattern: Type.String(), path: Type.Optional(Type.String()), limit: Type.Optional(Type.Number()) }),
  },
  ls: {
    description: 'List directory entries.',
    parameters: Type.Object({ path: Type.Optional(Type.String()), limit: Type.Optional(Type.Number()) }),
  },
};
const builtinToolFactory = (name, _cwd, _options) => {
  const spec = builtinToolSpecs[name] ?? { description: String(name), parameters: Type.Object({}) };
  return {
    name, label: name, description: spec.description, parameters: spec.parameters,
    async execute(_toolCallId, params) {
      // The native host recognizes this sentinel and falls back to the Zig
      // implementation. It lets original renderer-only extensions delegate to
      // createReadTool()/createBashTool() without replacing safe native code by
      // a JavaScript compatibility stub.
      return { __piDelegateBuiltin: name, __piDelegateArgs: params, content: [], details: {} };
    },
  };
};
const visibleWidth = (text) => [...String(text).replace(/\x1b\[[0-9;?]*[ -/]*[@-~]/g, '')].length;
const truncateToWidth = (text, width) => [...String(text)].slice(0, Math.max(0, width)).join('');
const wrapTextWithAnsi = (text) => [String(text)];
const matchesKey = () => false;
const parseKey = (value) => value;
const isKeyRelease = () => false;
const normalizeLines = (value) => {
  if (value == null) return [];
  if (Array.isArray(value)) return value.flatMap((item) => normalizeLines(item));
  return String(value).split('\n');
};
class DummyComponent {
  constructor(...args) { this.args = args; this.children = []; }
  addChild(child) { this.children.push(child); return child; }
  removeChild(child) { const index = this.children.indexOf(child); if (index >= 0) this.children.splice(index, 1); }
  clear() { this.children.length = 0; }
  render() { return this.children.length ? this.children.flatMap(normalizeLines) : normalizeLines(this.args[0]); }
  invalidate() {}
  handleInput() {}
  dispose() { for (const child of this.children) { try { child?.dispose?.(); } catch {} } }
}
class Text extends DummyComponent { render() { return normalizeLines(this.args[0]); } }
const renderChildSync = (child, width) => child?.render ? normalizeLines(child.render(width)) : normalizeLines(child);
const padVisible = (line, width) => String(line) + ' '.repeat(Math.max(0, Number(width) - visibleWidth(line)));
class Box extends DummyComponent {
  render(width = 80) {
    const paddingX = Math.max(0, Number(this.args[0] ?? 0));
    const paddingY = Math.max(0, Number(this.args[1] ?? 0));
    const background = typeof this.args[2] === 'function' ? this.args[2] : undefined;
    const legacyChild = this.args.find((arg, index) => index > 2 && arg?.render);
    const children = this.children.length ? this.children : (legacyChild ? [legacyChild] : []);
    let lines = children.length
      ? children.flatMap((child) => renderChildSync(child, Math.max(1, Number(width) - paddingX * 2)))
      : normalizeLines(typeof this.args[0] === 'string' ? this.args[0] : '');
    if (!lines.length) lines = [''];
    const innerWidth = Math.max(0, ...lines.map(visibleWidth));
    const padded = lines.map((line) => ' '.repeat(paddingX) + padVisible(line, innerWidth) + ' '.repeat(paddingX));
    const blank = ' '.repeat(innerWidth + paddingX * 2);
    const framed = [...Array(paddingY).fill(blank), ...padded, ...Array(paddingY).fill(blank)];
    return background ? framed.map((line) => background(line)) : framed;
  }
}
class Container extends DummyComponent {
  render(width = 80) { return this.children.flatMap((child) => renderChildSync(child, width)); }
}
class Markdown extends Text {}
class Spacer extends DummyComponent { render() { return Array(Math.max(1, Number(this.args[0] ?? 1))).fill(''); } }
class SelectList extends DummyComponent {}
class SettingsList extends DummyComponent {}
class Input extends Text {}
class Editor extends Text {}
const keyJoin = (...parts) => parts.filter(Boolean).join('+').toLowerCase();
const Key = new Proxy({
  ctrl: (key) => keyJoin('ctrl', key), shift: (key) => keyJoin('shift', key), alt: (key) => keyJoin('alt', key), super: (key) => keyJoin('super', key),
  ctrlShift: (key) => keyJoin('ctrl', 'shift', key), ctrlAlt: (key) => keyJoin('ctrl', 'alt', key), altShift: (key) => keyJoin('alt', 'shift', key),
  ctrlShiftAlt: (key) => keyJoin('ctrl', 'shift', 'alt', key), ctrlAltShift: (key) => keyJoin('ctrl', 'shift', 'alt', key),
}, { get: (target, key) => key in target ? target[key] : String(key) });
const fuzzyFilter = (items, query) => items.filter((item) => String(item?.label ?? item?.value ?? item).toLowerCase().includes(String(query).toLowerCase()));
const hyperlink = (text, url) => `\x1b]8;;${String(url)}\x1b\\${String(text)}\x1b]8;;\x1b\\`;
const fgCodes = { text: 39, accent: 36, muted: 90, dim: 90, success: 32, warning: 33, error: 31, border: 90, borderAccent: 36, userMessageText: 39, assistantMessageText: 39, toolTitle: 36, toolOutput: 90, thinkingText: 90 };
const styleWrap = (open, text) => `\x1b[${open}m${String(text)}\x1b[0m`;
const theme = {
  fg(name, text) { return styleWrap(fgCodes[name] ?? 39, text); },
  bg(_name, text) { return String(text); },
  bold: (text) => styleWrap(1, text), dim: (text) => styleWrap(2, text), italic: (text) => styleWrap(3, text),
  underline: (text) => styleWrap(4, text), inverse: (text) => styleWrap(7, text), strikethrough: (text) => styleWrap(9, text),
  reset: (text) => `\x1b[0m${String(text)}\x1b[0m`,
};
const dummyTui = { requestRender() {}, invalidate() {}, setFocus() {}, addChild() {}, removeChild() {}, terminal: { columns: 80, rows: 24 } };
const dummyKeybindings = { get() {}, matches() { return false; }, getKey() { return undefined; } };
const renderComponent = async (value) => {
  try {
    const component = await value;
    if (component == null) return [];
    if (Array.isArray(component) || typeof component === 'string') return normalizeLines(component);
    if (typeof component.render === 'function') return normalizeLines(await component.render(Number(currentContext.width ?? 80)));
    return normalizeLines(component);
  } catch (error) {
    stderrWrite(`extension component render failed: ${error?.stack ?? error}`);
    return [];
  }
};
const renderComponentSync = (component) => {
  try {
    if (component == null || typeof component?.then === 'function') return [];
    if (Array.isArray(component) || typeof component === 'string') return normalizeLines(component);
    if (typeof component.render === 'function') {
      const rendered = component.render(Number(currentContext.width ?? 80));
      return typeof rendered?.then === 'function' ? [] : normalizeLines(rendered);
    }
    return normalizeLines(component);
  } catch (error) {
    stderrWrite(`extension component render failed: ${error?.stack ?? error}`);
    return [];
  }
};
const PROVIDER_STREAM_MAX_QUEUED_EVENTS = 64;
const PROVIDER_STREAM_MAX_QUEUED_BYTES = 1024 * 1024;
const PROVIDER_STREAM_MAX_EVENT_BYTES = 512 * 1024;
const PROVIDER_STREAM_MAX_TOTAL_BYTES = 16 * 1024 * 1024;
const jsonByteLength = (value, label = 'value') => {
  let encoded;
  try { encoded = JSON.stringify(value); }
  catch (error) { throw new TypeError(`${label} must be JSON serializable: ${error?.message ?? String(error)}`); }
  if (encoded === undefined) throw new TypeError(`${label} must be JSON serializable`);
  return Buffer.byteLength(encoded);
};
class CompatEventStream {
  constructor(isComplete, extractResult) {
    this.queue = [];
    this.waiting = [];
    this.done = false;
    this.queuedBytes = 0;
    this.isComplete = isComplete;
    this.extractResult = extractResult;
    this.finalResultPromise = new Promise((resolve, reject) => {
      this.resolveFinalResult = resolve;
      this.rejectFinalResult = reject;
    });
    // Queue-limit failures may happen before an extension calls result(). Mark
    // the promise as observed without changing what later awaiters receive.
    this.finalResultPromise.catch(() => {});
  }
  push(event) {
    if (this.done) return;
    const eventBytes = jsonByteLength(event, 'assistant stream event');
    if (eventBytes > PROVIDER_STREAM_MAX_EVENT_BYTES) {
      throw new RangeError(`assistant stream event exceeds ${PROVIDER_STREAM_MAX_EVENT_BYTES} bytes`);
    }
    const waiter = this.waiting.shift();
    if (!waiter && (this.queue.length >= PROVIDER_STREAM_MAX_QUEUED_EVENTS || this.queuedBytes + eventBytes > PROVIDER_STREAM_MAX_QUEUED_BYTES)) {
      const error = new RangeError('assistant stream producer exceeded the bounded pending queue');
      this.done = true;
      this.rejectFinalResult(error);
      while (this.waiting.length) this.waiting.shift().reject(error);
      throw error;
    }
    if (this.isComplete(event)) {
      this.done = true;
      this.resolveFinalResult(this.extractResult(event));
    }
    if (waiter) {
      waiter.resolve({ value: event, done: false });
      return;
    }
    this.queue.push({ event, bytes: eventBytes });
    this.queuedBytes += eventBytes;
  }
  end(result) {
    if (this.done) return;
    this.done = true;
    if (result !== undefined) this.resolveFinalResult(result);
    while (this.waiting.length) this.waiting.shift().resolve({ value: undefined, done: true });
  }
  fail(error) {
    if (this.done) return;
    this.done = true;
    this.rejectFinalResult(error instanceof Error ? error : new Error(String(error)));
    while (this.waiting.length) this.waiting.shift().reject(error);
  }
  async *[Symbol.asyncIterator]() {
    while (true) {
      if (this.queue.length) {
        const queued = this.queue.shift();
        this.queuedBytes -= queued.bytes;
        yield queued.event;
      } else if (this.done) {
        return;
      } else {
        const result = await new Promise((resolve, reject) => this.waiting.push({ resolve, reject }));
        if (result.done) return;
        yield result.value;
      }
    }
  }
  result() { return this.finalResultPromise; }
}
class CompatAssistantMessageEventStream extends CompatEventStream {
  constructor() {
    super(
      (event) => event?.type === 'done' || event?.type === 'error',
      (event) => event.type === 'done' ? event.message : event.error,
    );
  }
}
const createCompatAssistantMessageEventStream = () => new CompatAssistantMessageEventStream();

const shimCoding = `
export const VERSION = 'zig-compat';
export const CONFIG_DIR_NAME = '.pi';
export const DEFAULT_MAX_BYTES = 5242880;
export const DEFAULT_MAX_LINES = 2000;
export const defineTool = globalThis.__piCompat.defineTool;
export const createBashTool = (...args) => globalThis.__piCompat.builtinToolFactory('bash', ...args);
export const createEditTool = (...args) => globalThis.__piCompat.builtinToolFactory('edit', ...args);
export const createFindTool = (...args) => globalThis.__piCompat.builtinToolFactory('find', ...args);
export const createGrepTool = (...args) => globalThis.__piCompat.builtinToolFactory('grep', ...args);
export const createLsTool = (...args) => globalThis.__piCompat.builtinToolFactory('ls', ...args);
export const createReadTool = (...args) => globalThis.__piCompat.builtinToolFactory('read', ...args);
export const createWriteTool = (...args) => globalThis.__piCompat.builtinToolFactory('write', ...args);
export const getAgentDir = () => process.env.PI_CODING_AGENT_DIR || process.env.HOME + '/.pi/agent';
export const copyToClipboard = (text) => globalThis.__piCompat.copyToClipboard(String(text));
export const parseFrontmatter = (text) => ({ body: String(text), frontmatter: {} });
export const truncateHead = (text) => ({ content: String(text), truncated: false });
export const truncateLine = (text) => ({ content: String(text), truncated: false });
export const formatSize = (value) => String(value) + ' B';
export const withFileMutationQueue = async (_path, fn) => await fn();
export const convertToLlm = (messages) => messages;
export const serializeConversation = (messages) => JSON.stringify(messages);
export const getMarkdownTheme = () => ({});
export const getSettingsListTheme = () => ({});
export class BorderedLoader { constructor(...args) { this.args = args; } }
export class DynamicBorder { constructor(...args) { this.args = args; } }
export class CustomEditor { constructor(...args) { this.args = args; } }
`;
const shimAi = `
export const Type = globalThis.__piCompat.Type;
export const StringEnum = globalThis.__piCompat.StringEnum;
export const uuidv7 = globalThis.__piCompat.uuidv7;
export const calculateCost = () => ({ input: 0, output: 0, cacheRead: 0, cacheWrite: 0, total: 0 });
export const EventStream = globalThis.__piCompat.EventStream;
export const AssistantMessageEventStream = globalThis.__piCompat.AssistantMessageEventStream;
export const createAssistantMessageEventStream = globalThis.__piCompat.createAssistantMessageEventStream;
export const registerApiProvider = () => {};
export const streamSimple = async () => { throw new Error('provider compatibility shim is unavailable'); };
export const anthropicMessagesApi = {};
export const openAIResponsesApi = {};
`;
const shimTui = `
export const CURSOR_MARKER = '\\x1b_pi:c\\x07';
export const Text = globalThis.__piCompat.Text;
export const Box = globalThis.__piCompat.Box;
export const Container = globalThis.__piCompat.Container;
export const Markdown = globalThis.__piCompat.Markdown;
export const Spacer = globalThis.__piCompat.Spacer;
export const SelectList = globalThis.__piCompat.SelectList;
export const SettingsList = globalThis.__piCompat.SettingsList;
export const Input = globalThis.__piCompat.Input;
export const Editor = globalThis.__piCompat.Editor;
export const Key = globalThis.__piCompat.Key;
export const matchesKey = globalThis.__piCompat.matchesKey;
export const parseKey = globalThis.__piCompat.parseKey;
export const isKeyRelease = globalThis.__piCompat.isKeyRelease;
export const visibleWidth = globalThis.__piCompat.visibleWidth;
export const truncateToWidth = globalThis.__piCompat.truncateToWidth;
export const wrapTextWithAnsi = globalThis.__piCompat.wrapTextWithAnsi;
export const fuzzyFilter = globalThis.__piCompat.fuzzyFilter;
export const hyperlink = globalThis.__piCompat.hyperlink;
`;
const shimTypebox = `export const Type = globalThis.__piCompat.Type; export default Type;`;
const shimTypeboxCompile = `export const TypeCompiler = { Compile: (schema) => ({ Check: () => true, Errors: () => [] }) };`;
const shimTypeboxValue = `export const Value = { Check: () => true, Errors: () => [] };`;
const shimAgent = `export const Agent = class {}; export const defaultConvertToLlm = (messages) => messages;`;

globalThis.__piCompat = { Type, StringEnum, uuidv7, defineTool, identityToolFactory, builtinToolFactory, Text, Box, Container, Markdown, Spacer, SelectList, SettingsList, Input, Editor, Key, matchesKey, parseKey, isKeyRelease, visibleWidth, truncateToWidth, wrapTextWithAnsi, fuzzyFilter, hyperlink, EventStream: CompatEventStream, AssistantMessageEventStream: CompatAssistantMessageEventStream, createAssistantMessageEventStream: createCompatAssistantMessageEventStream };
const moduleSources = new Map();
for (const name of ['@earendil-works/pi-coding-agent', '@mariozechner/pi-coding-agent']) moduleSources.set(name, shimCoding);
for (const name of ['@earendil-works/pi-ai', '@earendil-works/pi-ai/compat', '@earendil-works/pi-ai/oauth', '@earendil-works/pi-ai/providers/all', '@mariozechner/pi-ai', '@mariozechner/pi-ai/compat', '@mariozechner/pi-ai/oauth', '@mariozechner/pi-ai/providers/all']) moduleSources.set(name, shimAi);
for (const name of ['@earendil-works/pi-tui', '@mariozechner/pi-tui']) moduleSources.set(name, shimTui);
for (const name of ['@earendil-works/pi-agent-core', '@mariozechner/pi-agent-core']) moduleSources.set(name, shimAgent);
for (const name of ['typebox', '@sinclair/typebox']) moduleSources.set(name, shimTypebox);
for (const name of ['typebox/compile', '@sinclair/typebox/compile']) moduleSources.set(name, shimTypeboxCompile);
for (const name of ['typebox/value', '@sinclair/typebox/value']) moduleSources.set(name, shimTypeboxValue);
const dataUrls = new Map([...moduleSources].map(([name, source]) => [name, `data:text/javascript;base64,${Buffer.from(source).toString('base64')}`]));
registerHooks({
  resolve(specifier, context, nextResolve) {
    try { return nextResolve(specifier, context); }
    catch (error) {
      const url = dataUrls.get(specifier);
      if (url) return { url, shortCircuit: true };
      throw error;
    }
  },
  load(url, context, nextLoad) {
    // Node's built-in TypeScript loader intentionally refuses to strip files
    // below node_modules (ERR_UNSUPPORTED_NODE_MODULES_TYPE_STRIPPING). Pi
    // packages commonly publish their extension entrypoints as source .ts,
    // so transform those modules explicitly in the trusted extension worker.
    if (url.startsWith('file:') && /\.(?:ts|mts|cts)(?:$|[?#])/.test(url)) {
      const filename = fileURLToPath(url);
      const source = readFileSync(filename, 'utf8');
      const transformed = stripTypeScriptTypes(source, {
        mode: 'transform',
        sourceMap: false,
        sourceUrl: url,
      });
      return {
        format: filename.endsWith('.cts') ? 'commonjs' : 'module',
        source: transformed,
        shortCircuit: true,
      };
    }
    return nextLoad(url, context);
  },
});

const handlers = new Map();
const tools = new Map();
const commands = new Map();
const shortcuts = new Map();
const flags = new Map();
const flagValues = new Map();
const eventHandlers = new Map();
const providers = new Map();
const providerSourceConfigs = new Map();
const providerLiveConfigs = new Map();
const providerCallbacks = new Map();
const providerCallbackIds = new Map();
let nextProviderCallbackOrdinal = 1;
let nextProviderGeneration = 1;
const messageRenderers = new Map();
const entryRenderers = new Map();
let markdownTransformer;
const toolRenderState = new Map();
let currentFlags = {};
let currentContext = { mode: 'print', hasUI: false, cwd: process.cwd(), editorText: '', thinkingLevel: 'off', projectTrusted: false };
let sessionName;
let activeTools = [];
let currentActions = null;
const staleContextMessage = 'This extension ctx is stale after session replacement or reload. Do not use a captured pi or command ctx after ctx.newSession(), ctx.fork(), ctx.switchSession(), or ctx.reload(). For reload, do not use the old ctx after await ctx.reload().';
let nextUiRequestId = 1;
const pendingUi = new Map();
const pendingProviderStreamAcks = new Map();
let bridgeReady = false;
const startupUiActions = [];
const writeResponse = (value) => process.stdout.write('\x1e' + JSON.stringify(value) + '\n');
const emitUiAction = (method, args = {}) => {
  const record = { type: 'ui_action', method, args };
  if (!bridgeReady) startupUiActions.push(record); else writeResponse(record);
};
const defaultUiValue = (method) => method === 'confirm' ? false : undefined;
const requestUi = (method, args = {}) => {
  if (!currentContext.hasUI) return Promise.resolve(defaultUiValue(method));
  const id = nextUiRequestId++;
  writeResponse({ type: 'ui_request', id, method, args });
  return new Promise((resolve, reject) => pendingUi.set(id, { resolve, reject }));
};
const requestHost = (method, args = {}, signal = undefined) => {
  if (signal?.aborted) return Promise.reject(signal.reason ?? new Error('Operation aborted'));
  const id = nextUiRequestId++;
  return new Promise((resolve, reject) => {
    let onAbort;
    const cleanup = () => { if (onAbort) signal?.removeEventListener('abort', onAbort); };
    const pending = {
      resolve(value) { cleanup(); resolve(value); },
      reject(error) { cleanup(); reject(error); },
    };
    onAbort = () => {
      if (!pendingUi.delete(id)) return;
      pending.reject(signal.reason ?? new Error('Operation aborted'));
    };
    pendingUi.set(id, pending);
    signal?.addEventListener('abort', onAbort, { once: true });
    writeResponse({ type: 'ui_request', id, method, args });
  });
};
globalThis.__piCompat.copyToClipboard = async (text) => {
  const copied = await requestHost('copyToClipboard', { text: String(text) });
  if (copied !== true) throw new Error('Failed to copy to clipboard');
};

const assertCurrentActionContext = () => {
  if (currentActions?.contextInvalidated) {
    currentActions.staleActionAttempts++;
    throw new Error(staleContextMessage);
  }
};
const pushMessage = (value) => { assertCurrentActionContext(); if (currentActions && value !== undefined && value !== null) currentActions.messages.push(String(value)); };
const recordAction = (type, payload = {}) => {
  if (!currentActions) return;
  assertCurrentActionContext();
  currentActions.actionQueue.push({ type: String(type), ...payload });
};
const normalizeCustomMessage = (message) => {
  if (typeof message === 'string') return { customType: 'extension', content: message, display: true };
  if (!message || typeof message !== 'object') return { customType: 'extension', content: String(message ?? ''), display: true };
  return {
    customType: String(message.customType ?? message.type ?? 'extension'),
    content: message.content ?? '',
    display: message.display !== false,
    ...(message.details !== undefined ? { details: message.details } : {}),
  };
};
const customMessageText = (message) => {
  const normalized = textContent(message?.content);
  return normalized.text || (message?.content == null ? '' : JSON.stringify(message.content));
};
const execCommand = (command, args = [], options = {}) => new Promise((resolve) => {
  const child = spawn(command, args, { cwd: options.cwd ?? currentContext.cwd ?? process.cwd(), env: { ...process.env, ...(options.env ?? {}) }, shell: false });
  const stdout = []; const stderr = [];
  child.stdout?.on('data', (chunk) => stdout.push(chunk));
  child.stderr?.on('data', (chunk) => stderr.push(chunk));
  child.on('error', (error) => resolve({ stdout: '', stderr: String(error), code: -1, killed: false }));
  child.on('close', (code, signal) => resolve({ stdout: Buffer.concat(stdout).toString(), stderr: Buffer.concat(stderr).toString(), code: code ?? -1, killed: signal !== null }));
});
const events = { emit(channel, data) { for (const handler of eventHandlers.get(channel) ?? []) Promise.resolve(handler(data)).catch(stderrWrite); }, on(channel, handler) { const list = eventHandlers.get(channel) ?? []; list.push(handler); eventHandlers.set(channel, list); return () => { const i = list.indexOf(handler); if (i >= 0) list.splice(i, 1); }; } };
const providerPathText = (path) => path.join('.');
const removeProviderCallbacks = (name) => {
  const ids = providerCallbackIds.get(name);
  if (ids) for (const id of ids) providerCallbacks.delete(id);
  providerCallbackIds.delete(name);
};
const encodeProviderConfig = (name, root, generation) => {
  const pending = new Map();
  const active = new WeakSet();
  const walk = (value, path, owner) => {
    if (typeof value === 'function') {
      const callbackId = `provider:${encodeURIComponent(name)}:${nextProviderCallbackOrdinal++}`;
      pending.set(callbackId, {
        callback: owner == null ? value : value.bind(owner),
        generation,
        path: providerPathText(path),
      });
      return {
        __pi_callback_id: callbackId,
        __pi_callback_kind: 'provider_method',
        __pi_callback_path: providerPathText(path),
        __pi_callback_generation: generation,
      };
    }
    if (!value || typeof value !== 'object') return value;
    if (active.has(value)) {
      const location = providerPathText(path) || '<root>';
      throw new TypeError(`provider ${name} configuration contains a cycle at ${location}`);
    }
    active.add(value);
    try {
      if (Array.isArray(value)) return value.map((item, index) => walk(item, path.concat(String(index)), value));
      const copy = Object.create(null);
      for (const key of Object.keys(value)) copy[key] = walk(value[key], path.concat(key), value);
      return copy;
    } finally {
      active.delete(value);
    }
  };
  return { config: walk(root ?? {}, [], null), pending };
};
const installProvider = (rawName, rawConfig, replace = false) => {
  const name = String(rawName);
  if (!rawConfig || typeof rawConfig !== 'object' || Array.isArray(rawConfig)) {
    throw new TypeError(`provider ${name} configuration must be an object`);
  }
  // Named re-registration follows upstream's shallow, defined-value merge.
  // Re-encode the complete effective object so callbacks retained from the
  // previous registration receive live IDs instead of dangling descriptors.
  const effective = replace ? {} : { ...(providerSourceConfigs.get(name) ?? {}) };
  for (const [key, value] of Object.entries(rawConfig)) if (value !== undefined) effective[key] = value;
  // Keep a live, identity-preserving provider object beside the JSON-facing
  // shallow snapshot. Config-form refresh callbacks commonly close over and
  // mutate their original config object inside publish.update(); cloning that
  // object here would make the native catalog snapshot observe stale models.
  let liveConfig;
  if (replace) {
    liveConfig = rawConfig;
  } else {
    const previousLive = providerLiveConfigs.get(name);
    if (previousLive) {
      for (const [key, value] of Object.entries(rawConfig)) if (value !== undefined) previousLive[key] = value;
      liveConfig = previousLive;
    } else {
      liveConfig = rawConfig;
    }
  }
  const generation = nextProviderGeneration++;
  if (!Number.isSafeInteger(generation) || generation <= 0) throw new RangeError('provider callback generation exhausted');
  const encoded = encodeProviderConfig(name, effective, generation);
  // Fail before changing the live registration when any retained non-function
  // value cannot cross the JSON protocol (for example BigInt).
  JSON.stringify(encoded.config);
  // Encoding is complete before anything live changes. Retain prior callback
  // IDs until explicit unregister/runtime shutdown: native provider actions are
  // applied at a deterministic safe point after the JavaScript call returns,
  // so the old native snapshot must remain callable during that handoff window.
  const retainedIds = providerCallbackIds.get(name) ?? new Set();
  for (const [id, callback] of encoded.pending) {
    providerCallbacks.set(id, { ...callback, provider: name });
    retainedIds.add(id);
  }
  providerCallbackIds.set(name, retainedIds);
  providerSourceConfigs.set(name, effective);
  providerLiveConfigs.set(name, liveConfig);
  providers.set(name, encoded.config);
  return encoded.config;
};
const pi = {
  on(event, handler) { const list = handlers.get(event) ?? []; list.push(handler); handlers.set(event, list); },
  registerTool(tool) { if (tool?.name) tools.set(tool.name, tool); },
  registerCommand(name, options) { commands.set(name, { name, ...(options ?? {}) }); },
  registerShortcut(key, options = {}) { shortcuts.set(String(key).toLowerCase(), { key: String(key).toLowerCase(), ...options }); },
  registerMessageRenderer(customType, renderer) {
    if (String(customType).length && typeof renderer === 'function') messageRenderers.set(String(customType), renderer);
  },
  registerMarkdownTransformer(transformer) { markdownTransformer = typeof transformer === 'function' ? transformer : undefined; },
  registerEntryRenderer(customType, renderer) {
    if (String(customType).length && typeof renderer === 'function') entryRenderers.set(String(customType), renderer);
  },
  registerFlag(name, options = {}) { flags.set(name, { name, ...options }); if (options.default !== undefined && !flagValues.has(name)) flagValues.set(name, options.default); },
  getFlag(name) { return Object.prototype.hasOwnProperty.call(currentFlags, name) ? currentFlags[name] : flagValues.get(name); },
  sendMessage(message, options = {}) {
    assertCurrentActionContext();
    const normalized = normalizeCustomMessage(message);
    pushMessage(customMessageText(normalized));
    recordAction('send_message', {
      message: normalized,
      options: {
        triggerTurn: !!options?.triggerTurn,
        deliverAs: options?.deliverAs ?? options?.mode ?? undefined,
      },
    });
  },
  sendUserMessage(content, options = {}) {
    assertCurrentActionContext();
    if (currentActions) {
      currentActions.prompt = typeof content === 'string' ? content : JSON.stringify(content);
      currentActions.promptMode = options?.deliverAs ?? options?.mode;
    }
    recordAction('send_user_message', {
      content,
      options: {
        deliverAs: options?.deliverAs ?? options?.mode ?? undefined,
        expandPromptTemplates: !!options?.expandPromptTemplates,
      },
    });
  },
  appendEntry(type, data) {
    assertCurrentActionContext();
    if (currentActions) currentActions.entries.push({ type, data });
    recordAction('append_entry', { customType: String(type), ...(data !== undefined ? { data } : {}) });
  },
  setSessionName(name) {
    assertCurrentActionContext();
    sessionName = String(name);
    if (currentActions) currentActions.sessionName = sessionName;
    recordAction('set_session_name', { name: sessionName });
  },
  getSessionName() { return sessionName ?? currentContext.sessionName; },
  setLabel(entryId, label) {
    assertCurrentActionContext();
    const normalized = label == null ? null : String(label);
    if (currentActions) currentActions.labels.push({ entryId: String(entryId), label: normalized });
    recordAction('set_label', { entryId: String(entryId), label: normalized });
  },
  exec: execCommand,
  getActiveTools() { return activeTools.length ? [...activeTools] : [...(currentContext.activeTools ?? [])]; },
  getAllTools() {
    const merged = new Map();
    for (const item of currentContext.allTools ?? []) {
      if (item?.name) merged.set(String(item.name), { ...item });
    }
    for (const [name, tool] of tools) {
      merged.set(name, {
        name,
        description: tool.description ?? tool.label ?? '',
        parameters: cleanSchema(tool.parameters ?? tool.inputSchema ?? Type.Object({})),
        source: 'extension',
      });
    }
    return [...merged.values()];
  },
  setActiveTools(names) {
    assertCurrentActionContext();
    activeTools = [...names].map(String);
    if (currentActions) currentActions.activeTools = [...activeTools];
    recordAction('set_active_tools', { names: [...activeTools] });
  },
  getCommands() { return [...commands.values()].map((c) => ({ name: c.name, description: c.description ?? '', source: 'extension', sourceInfo: { path: extensionPath } })); },
  async setModel(model) {
    assertCurrentActionContext();
    if (currentActions) currentActions.model = model;
    recordAction('set_model', { model });
    return true;
  },
  getThinkingLevel: () => currentContext.thinkingLevel ?? 'off',
  setThinkingLevel(level) {
    assertCurrentActionContext();
    if (currentActions) currentActions.thinkingLevel = String(level);
    recordAction('set_thinking_level', { level: String(level) });
  },
  registerProvider(nameOrProvider, config) {
    assertCurrentActionContext();
    const rawName = typeof nameOrProvider === 'string' ? nameOrProvider : nameOrProvider?.id ?? nameOrProvider?.name;
    if (rawName == null || String(rawName).length === 0) throw new Error('provider registration requires a non-empty name or id');
    const name = String(rawName);
    const named = typeof nameOrProvider === 'string';
    if (named && config == null) throw new Error('provider config is required when registering by name');
    const value = named ? config : nameOrProvider;
    const encoded = installProvider(name, value, !named);
    if (currentActions) currentActions.providers.push({ action: 'register', name, config: encoded });
    recordAction('register_provider', { name, config: encoded });
  },
  unregisterProvider(rawName) {
    assertCurrentActionContext();
    const name = String(rawName);
    providers.delete(name);
    providerSourceConfigs.delete(name);
    providerLiveConfigs.delete(name);
    removeProviderCallbacks(name);
    if (currentActions) currentActions.providers.push({ action: 'unregister', name });
    recordAction('unregister_provider', { name });
  },
  events,
};
const createActions = () => ({ actionQueue: [], messages: [], prompt: undefined, promptMode: undefined, terminate: false, isError: false, entries: [], labels: [], sessionName: undefined, activeTools: undefined, model: undefined, thinkingLevel: undefined, providers: [], abort: false, contextInvalidated: false, staleActionAttempts: 0 });
const snapshotFactory = async (factory, extraArgs = []) => {
  if (typeof factory !== 'function') return [];
  const component = await factory(dummyTui, theme, ...extraArgs);
  return await renderComponent(component);
};
const snapshotFactorySync = (factory, extraArgs = []) => {
  if (typeof factory !== 'function') return [];
  try { return renderComponentSync(factory(dummyTui, theme, ...extraArgs)); }
  catch (error) { stderrWrite(`extension component factory failed: ${error?.stack ?? error}`); return []; }
};
const createContext = (actions, event = {}) => {
  const assertActive = () => {
    if (actions.contextInvalidated) {
      actions.staleActionAttempts++;
      throw new Error(staleContextMessage);
    }
  };
  const guardObject = (target) => new Proxy(target, {
    get(object, property, receiver) {
      assertActive();
      const value = Reflect.get(object, property, receiver);
      return typeof value === 'function' ? (...args) => { assertActive(); return value.apply(object, args); } : value;
    },
  });
  const ui = {
    async select(title, options, opts = {}) { const value = await requestUi('select', { title: String(title), options: [...options].map(String), timeout: opts?.timeout }); return value ?? undefined; },
    async confirm(title, message, opts = {}) { return !!(await requestUi('confirm', { title: String(title), message: String(message), timeout: opts?.timeout })); },
    async input(title, placeholder = '', opts = {}) { const value = await requestUi('input', { title: String(title), placeholder: String(placeholder ?? ''), timeout: opts?.timeout }); return value ?? undefined; },
    async editor(title, prefill = '') { const value = await requestUi('editor', { title: String(title), prefill: String(prefill ?? '') }); return value ?? undefined; },
    notify(message, type = 'info') { if (currentContext.hasUI) emitUiAction('notify', { message: String(message), type: String(type) }); else actions.messages.push(String(message)); },
    onTerminalInput() { return () => {}; },
    setStatus(key, text) { emitUiAction('setStatus', { key: String(key), text: text == null ? null : String(text) }); },
    setWorkingMessage(message) { emitUiAction('setWorkingMessage', { message: message == null ? null : String(message) }); },
    setWorkingVisible(visible) { emitUiAction('setWorkingVisible', { visible: !!visible }); },
    setWorkingIndicator(options) { emitUiAction('setWorkingIndicator', { options: options == null ? null : { frames: Array.isArray(options.frames) ? options.frames.map(String) : undefined, intervalMs: options.intervalMs } }); },
    setHiddenThinkingLabel(label) { emitUiAction('setHiddenThinkingLabel', { label: label == null ? null : String(label) }); },
    setWidget(key, content, options = {}) {
      let lines = null;
      if (content != null) lines = typeof content === 'function' ? snapshotFactorySync(content) : normalizeLines(content);
      emitUiAction('setWidget', { key: String(key), lines, placement: options?.placement === 'belowEditor' ? 'belowEditor' : 'aboveEditor' });
    },
    setFooter(factory) { emitUiAction('setFooter', { lines: factory == null ? null : snapshotFactorySync(factory, [{ getGitBranch: () => currentContext.gitBranch, getExtensionStatuses: () => currentContext.statuses ?? {} }]) }); },
    setHeader(factory) { emitUiAction('setHeader', { lines: factory == null ? null : snapshotFactorySync(factory) }); },
    setTitle(title) { emitUiAction('setTitle', { title: String(title) }); },
    async custom(factory, options = {}) {
      let settled = false; let settledValue;
      const done = (value) => { settled = true; settledValue = value; };
      const component = typeof factory === 'function' ? await factory(dummyTui, theme, dummyKeybindings, done) : factory;
      if (settled) return settledValue;
      const lines = await renderComponent(component);
      const value = await requestUi('custom', { lines, overlay: !!options?.overlay, overlayOptions: options?.overlayOptions });
      try { component?.dispose?.(); } catch {}
      return value ?? undefined;
    },
    pasteToEditor(text) { currentContext.editorText = String(currentContext.editorText ?? '') + String(text); emitUiAction('pasteToEditor', { text: String(text) }); },
    setEditorText(text) { currentContext.editorText = String(text); emitUiAction('setEditorText', { text: String(text) }); },
    getEditorText() { return String(currentContext.editorText ?? ''); },
    addAutocompleteProvider() { emitUiAction('autocompleteProvider', { supported: false }); },
    setEditorComponent(factory) { emitUiAction('setEditorComponent', { enabled: factory != null }); },
    getEditorComponent() { return undefined; },
    theme,
    getAllThemes() { return currentContext.themes ?? [{ name: 'default', path: undefined }]; },
    getTheme(name) { return (currentContext.themes ?? []).some((item) => item.name === name) ? theme : undefined; },
    setTheme(value) { const name = typeof value === 'string' ? value : value?.name ?? 'custom'; emitUiAction('setTheme', { name: String(name) }); return { success: true }; },
    showCustom(lines) { emitUiAction('showCustom', { lines: normalizeLines(lines) }); },
    hideCustom() { emitUiAction('hideCustom', {}); },
  };
  const cloneSnapshot = (value) => value == null ? value : structuredClone(value);
  const sessionEntries = () => Array.isArray(currentContext.sessionEntries) ? currentContext.sessionEntries : [];
  const sessionBranch = () => Array.isArray(currentContext.sessionBranch) ? currentContext.sessionBranch : [];
  const entryById = (entryId) => sessionEntries().find((entry) => entry?.id === entryId);
  const resolvedLabel = (entryId) => {
    let result;
    for (const entry of sessionEntries()) {
      if (entry?.type === 'label' && entry.targetId === entryId) result = entry.label ?? undefined;
    }
    return result;
  };
  const sessionTree = () => {
    const nodes = new Map();
    for (const entry of sessionEntries()) nodes.set(entry.id, { entry: cloneSnapshot(entry), children: [] });
    const roots = [];
    for (const entry of sessionEntries()) {
      const node = nodes.get(entry.id);
      const label = resolvedLabel(entry.id);
      if (label !== undefined) node.label = label;
      if (entry.parentId != null && nodes.has(entry.parentId)) nodes.get(entry.parentId).children.push(node);
      else roots.push(node);
    }
    return roots;
  };
  const sessionManager = {
    getCwd: () => currentContext.cwd ?? process.cwd(),
    getSessionDir: () => currentContext.sessionDir ?? undefined,
    getSessionId: () => currentContext.sessionId,
    getSessionFile: () => currentContext.sessionFile ?? undefined,
    getSessionName: () => sessionName ?? currentContext.sessionName,
    // Kept as a compatibility extension over the original read-only surface.
    setSessionName: (name) => pi.setSessionName(name),
    getLeafId: () => currentContext.sessionLeafId ?? undefined,
    getLeafEntry: () => cloneSnapshot(entryById(currentContext.sessionLeafId)),
    getEntry: (entryId) => cloneSnapshot(entryById(String(entryId))),
    getLabel: (entryId) => resolvedLabel(String(entryId)),
    getEntries: () => cloneSnapshot(sessionEntries()),
    getBranch: () => cloneSnapshot(sessionBranch()),
    buildContextEntries: () => cloneSnapshot(sessionBranch()),
    getHeader: () => cloneSnapshot(currentContext.sessionHeader),
    getTree: () => cloneSnapshot(sessionTree()),
  };
  const modelList = Array.isArray(currentContext.models) ? currentContext.models : [];
  const configuredProviders = new Set(Array.isArray(currentContext.configuredProviders) ? currentContext.configuredProviders.map(String) : []);
  const modelRegistry = {
    async refresh() { return { changed: false, models: modelList.length }; },
    getError() { return undefined; },
    getAll() { return modelList.map((model) => ({ ...model })); },
    getAvailable() { return modelList.filter((model) => configuredProviders.size === 0 || configuredProviders.has(String(model.provider))).map((model) => ({ ...model })); },
    find(provider, modelId) { return modelList.find((model) => String(model.provider).toLowerCase() === String(provider).toLowerCase() && String(model.id) === String(modelId)); },
    hasConfiguredAuth(model) { return configuredProviders.size === 0 || configuredProviders.has(String(model?.provider ?? model)); },
    getProviderDisplayName(provider) { return String(provider); },
    getProviderAuthStatus(provider) { return { configured: configuredProviders.size === 0 || configuredProviders.has(String(provider)) }; },
    getProvider() { return undefined; }, getRegisteredProviderConfig() { return undefined; }, getRegisteredNativeProvider() { return undefined; },
    getRegisteredProviderIds() { return [...providers.keys()]; },
    async getApiKeyAndHeaders(model) { return this.hasConfiguredAuth(model) ? { ok: true } : { ok: false, error: `No API key found for "${model?.provider ?? ''}"` }; },
    async getProviderAuth() { return undefined; }, async getApiKeyForProvider() { return undefined; }, isUsingOAuth() { return false; },
    async complete() { throw new Error('modelRegistry.complete is not available through the Pi Zig extension bridge'); },
  };
  const context = {
    ui: guardObject(ui),
    mode: currentContext.mode ?? 'print', hasUI: !!currentContext.hasUI, cwd: currentContext.cwd ?? process.cwd(),
    sessionManager: guardObject(sessionManager), modelRegistry: guardObject(modelRegistry), model: currentContext.model, scopedModels: currentContext.scopedModels ?? [], thinkingLevel: currentContext.thinkingLevel ?? 'off',
    isIdle: () => currentContext.idle !== false, isProjectTrusted: () => !!currentContext.projectTrusted, signal: event.signal,
    abort() { actions.abort = true; recordAction('abort'); }, hasPendingMessages: () => !!currentContext.hasPendingMessages,
    shutdown() { actions.terminate = true; recordAction('shutdown'); }, getContextUsage: () => currentContext.contextUsage,
    async reload() {
      if (!event.canReload) throw new Error('reload is only available to extension commands and shortcuts');
      recordAction('reload');
      actions.contextInvalidated = true;
    },
    compact: async () => undefined, getSystemPrompt: () => event.systemPrompt ?? currentContext.systemPrompt ?? '', getSystemPromptOptions: () => event.systemPromptOptions ?? currentContext.systemPromptOptions ?? {}, waitForIdle: async () => {},
  };
  return new Proxy(context, {
    get(target, property, receiver) {
      if (property !== 'reload') assertActive();
      const value = Reflect.get(target, property, receiver);
      if (property === 'reload') return value;
      return typeof value === 'function' ? (...args) => { assertActive(); return value.apply(target, args); } : value;
    },
  });
};

const module = await import(pathToFileURL(path.resolve(extensionPath)).href + `?pi_zig=${Date.now()}`);
const factory = module.default ?? module.extension ?? module;
if (typeof factory !== 'function') throw new Error('extension default export must be a function');
await factory(pi);

const aliasHooks = new Set();
for (const name of handlers.keys()) {
  if (name === 'input') aliasHooks.add('before_prompt');
  else if (name === 'tool_call') aliasHooks.add('before_tool');
  else if (name === 'tool_result') aliasHooks.add('after_tool');
  else aliasHooks.add(name);
}
const sanitizeTool = (tool) => ({
  name: tool.name,
  description: tool.description ?? tool.label ?? '',
  parameters: cleanSchema(tool.parameters ?? tool.inputSchema ?? Type.Object({})),
  executionMode: tool.executionMode === 'sequential' ? 'sequential' : 'parallel',
  hasRenderCall: typeof tool.renderCall === 'function',
  hasRenderResult: typeof tool.renderResult === 'function',
  hasPrepareArguments: typeof tool.prepareArguments === 'function',
  renderShell: tool.renderShell === 'self' ? 'self' : 'default',
});
const manifest = {
  name: path.basename(extensionPath).replace(/\.(?:[cm]?[jt]s)$/i, ''), version: 'legacy-js', entry: '',
  hooks: [...aliasHooks], tools: [...tools.values()].map(sanitizeTool),
  commands: [...commands.values()].map((command) => ({ name: command.name, description: command.description ?? '', argumentHint: command.argumentHint })),
  shortcuts: [...shortcuts.values()].map((shortcut) => ({ key: shortcut.key, description: shortcut.description ?? '' })),
  flags: [...flags.values()].map((flag) => ({ name: flag.name, description: flag.description ?? '', type: flag.type ?? (typeof flag.default === 'boolean' ? 'boolean' : 'string'), ...(flag.default !== undefined ? { default: flag.default } : {}) })),
  providers: [...providers.entries()].map(([name, config]) => ({ name, config })),
  messageRenderers: [...messageRenderers.keys()],
  entryRenderers: [...entryRenderers.keys()],
  hasMarkdownTransformer: typeof markdownTransformer === 'function',
};
writeResponse({ type: 'ready', manifest });
bridgeReady = true;
for (const action of startupUiActions.splice(0)) writeResponse(action);

const textContent = (content) => {
  if (typeof content === 'string') return { text: content, images: [] };
  if (!Array.isArray(content)) return { text: content == null ? '' : JSON.stringify(content), images: [] };
  const texts = [];
  const images = [];
  for (const item of content) {
    if (typeof item === 'string') texts.push(item);
    else if (item?.type === 'text') texts.push(String(item.text ?? ''));
    else if (item?.type === 'image') {
      const data = item.data ?? item.base64;
      if (typeof data === 'string' && data.length > 0) {
        images.push({ data, mime: item.mimeType ?? item.mime_type ?? 'image/png' });
      }
    }
  }
  return { text: texts.join('\n'), images };
};
const normalizeToolResult = (result) => {
  const normalized = textContent(result?.content);
  const out = {
    content: normalized.text,
    isError: !!result?.isError,
    details: result?.details ?? null,
    terminate: !!result?.terminate,
  };
  if (result?.usage && typeof result.usage === 'object') out.usage = result.usage;
  if (Array.isArray(result?.addedToolNames)) {
    out.addedToolNames = result.addedToolNames.filter((name) => typeof name === 'string' && name.length > 0);
  }
  if (normalized.images.length > 0) {
    out.imageBase64 = normalized.images[0].data;
    out.imageMime = normalized.images[0].mime ?? 'image/png';
    out.images = normalized.images.map((image) => ({
      dataBase64: image.data,
      mimeType: image.mime ?? 'image/png',
    }));
  }
  return out;
};
const mergeActions = (result, actions) => {
  if (actions.actionQueue.length) result.actionQueue = actions.actionQueue;
  if (actions.messages.length) result.message = actions.messages.join('\n');
  if (actions.prompt !== undefined) result.prompt = actions.prompt;
  if (actions.terminate) result.terminate = true;
  if (actions.isError) result.isError = true;
  if (actions.sessionName !== undefined) result.sessionName = actions.sessionName;
  if (actions.entries.length) result.entries = actions.entries;
  if (actions.labels.length) result.labels = actions.labels;
  if (actions.activeTools !== undefined) result.activeTools = actions.activeTools;
  if (actions.model !== undefined) result.model = actions.model;
  if (actions.thinkingLevel !== undefined) result.thinkingLevel = actions.thinkingLevel;
  if (actions.providers.length) result.providers = actions.providers;
  if (actions.promptMode !== undefined) result.promptMode = actions.promptMode;
  if (actions.abort) result.abort = true;
  return result;
};
async function invokeHandlers(names, event, actions) {
  let merged = {};
  const ctx = createContext(actions, event);
  for (const name of names) {
    for (const handler of handlers.get(name) ?? []) {
      const value = await handler(event, ctx);
      if (value && typeof value === 'object') merged = { ...merged, ...value };
    }
  }
  return merged;
}
async function invokeBeforeAgentStart(payload, actions, signal = undefined) {
  let currentSystemPrompt = String(payload.systemPrompt ?? '');
  let modified = false;
  const messages = [];
  let merged = {};
  for (const handler of handlers.get('before_agent_start') ?? []) {
    const event = { ...payload, type: 'before_agent_start', systemPrompt: currentSystemPrompt, signal };
    const value = await handler(event, createContext(actions, event));
    if (!value || typeof value !== 'object') continue;
    merged = { ...merged, ...value };
    if (value.message !== undefined) messages.push(value.message);
    if (value.systemPrompt !== undefined) {
      currentSystemPrompt = String(value.systemPrompt);
      modified = true;
    }
  }
  delete merged.message;
  if (messages.length === 1) merged.message = messages[0];
  else if (messages.length > 1) merged.messages = messages;
  if (modified) merged.systemPrompt = currentSystemPrompt;
  return merged;
}
async function invokeHook(name, payload, actions, signal = undefined) {
  if (name === 'before_agent_start') return await invokeBeforeAgentStart(payload, actions, signal);
  if (name === 'before_prompt') {
    let result = await invokeHandlers(['before_prompt'], { ...payload, type: 'before_prompt', signal }, actions);
    const input = await invokeHandlers(['input'], { type: 'input', text: payload.prompt ?? '', source: 'interactive', signal }, actions);
    if (input.action === 'transform' && typeof input.text === 'string') result.prompt = input.text;
    if (input.action === 'handled') result.handled = true;
    return result;
  }
  if (name === 'before_tool') {
    const event = { type: 'tool_call', toolName: payload.toolName, toolCallId: payload.toolCallId, input: payload.args ?? {}, signal };
    return { ...(await invokeHandlers(['before_tool'], { ...payload, signal }, actions)), ...(await invokeHandlers(['tool_call'], event, actions)) };
  }
  if (name === 'after_tool') {
    const content = Array.isArray(payload.content)
      ? payload.content
      : [{ type: 'text', text: String(payload.content ?? '') }];
    const event = {
      type: 'tool_result', toolName: payload.toolName, toolCallId: payload.toolCallId,
      input: payload.args ?? {}, content, details: payload.details ?? undefined,
      usage: payload.usage, addedToolNames: payload.addedToolNames,
      isError: !!payload.isError, signal,
    };
    return { ...(await invokeHandlers(['after_tool'], { ...payload, signal }, actions)), ...(await invokeHandlers(['tool_result'], event, actions)) };
  }
  return await invokeHandlers([name], { ...payload, type: name, signal }, actions);
}
async function invokeTool(name, payload, actions, streamUpdates = false, signal = undefined, toolCallId = undefined) {
  const tool = tools.get(name);
  if (!tool || typeof tool.execute !== 'function') throw new Error(`unknown extension tool: ${name}`);
  const ctx = createContext(actions, { signal });
  const updates = [];
  let acceptingUpdates = true;
  const onUpdate = (partial) => {
    if (!acceptingUpdates) return;
    const normalized = normalizeToolResult(partial);
    if (streamUpdates) writeResponse({ type: 'tool_update', update: normalized });
    else updates.push(normalized);
  };
  let result;
  try {
    result = await tool.execute(String(toolCallId ?? `pi-zig-${Date.now()}`), payload ?? {}, signal, onUpdate, ctx);
  } finally {
    acceptingUpdates = false;
  }
  if (result?.__piDelegateBuiltin === name) {
    return { content: '', isError: false, delegateBuiltin: true };
  }
  const out = normalizeToolResult(result);
  if (updates.length) out.updates = updates;
  return out;
}
async function invokeCommand(name, raw, actions) {
  const command = commands.get(name);
  if (!command || typeof command.handler !== 'function') throw new Error(`unknown extension command: ${name}`);
  const returned = await command.handler(String(raw ?? ''), createContext(actions, { canReload: true }));
  return returned && typeof returned === 'object' ? returned : {};
}
async function invokeShortcut(key, actions) {
  const shortcut = shortcuts.get(String(key).toLowerCase());
  if (!shortcut || typeof shortcut.handler !== 'function') throw new Error(`unknown extension shortcut: ${key}`);
  const returned = await shortcut.handler(createContext(actions, { canReload: true }));
  return returned && typeof returned === 'object' ? returned : {};
}
async function invokeProviderMethod(callbackId, args, signal = undefined, appendSignal = false) {
  const record = providerCallbacks.get(String(callbackId));
  if (!record || typeof record.callback !== 'function') throw new Error(`unknown or unloaded provider callback: ${callbackId}`);
  if (!Array.isArray(args)) throw new TypeError('provider method arguments must be a JSON array');
  const invokeArgs = appendSignal ? [...args, signal] : args;
  return await record.callback(...invokeArgs);
}
const commitProviderCallbacks = (providerName, rawCallbackIds) => {
  const provider = String(providerName);
  if (!Array.isArray(rawCallbackIds)) throw new TypeError('provider callback commit requires an array');
  const selected = new Set(rawCallbackIds.map((value) => String(value)));
  if (selected.size !== rawCallbackIds.length) throw new TypeError('provider callback commit contains duplicate IDs');
  const owned = providerCallbackIds.get(provider) ?? new Set();
  for (const id of selected) {
    const record = providerCallbacks.get(id);
    if (!record || record.provider !== provider || !owned.has(id)) {
      throw new Error(`provider callback commit selected unknown callback: ${provider}:${id}`);
    }
  }
  let retired = 0;
  for (const id of [...owned]) {
    if (selected.has(id)) continue;
    providerCallbacks.delete(id);
    owned.delete(id);
    retired++;
  }
  if (owned.size) providerCallbackIds.set(provider, owned); else providerCallbackIds.delete(provider);
  return { provider, retained: owned.size, retired };
};
const cloneProviderJson = (value, label) => {
  if (value === undefined) return undefined;
  let encoded;
  try { encoded = JSON.stringify(value); }
  catch (error) { throw new TypeError(`${label} must be JSON serializable: ${error?.message ?? String(error)}`); }
  if (encoded === undefined) throw new TypeError(`${label} must be JSON serializable`);
  try { return JSON.parse(encoded); }
  catch (error) { throw new TypeError(`${label} must be valid JSON: ${error?.message ?? String(error)}`); }
};
const deepFreezeProviderJson = (value) => {
  if (!value || typeof value !== 'object' || Object.isFrozen(value)) return value;
  for (const item of Object.values(value)) deepFreezeProviderJson(item);
  return Object.freeze(value);
};
const currentProviderModels = async (providerName) => {
  const source = providerLiveConfigs.get(String(providerName));
  if (!source) throw new Error(`unknown or unloaded provider: ${providerName}`);
  if (typeof source.getModels === 'function') {
    const models = await source.getModels();
    if (!Array.isArray(models)) throw new TypeError(`provider ${providerName} getModels() must return an array`);
    return cloneProviderJson(models, `provider ${providerName} models`);
  }
  if (Array.isArray(source.models)) return cloneProviderJson(source.models, `provider ${providerName} models`);
  return undefined;
};
async function invokeProviderRefreshModels(callbackId, providerName, rawContext, signal) {
  const record = providerCallbacks.get(String(callbackId));
  if (!record || typeof record.callback !== 'function') throw new Error(`unknown or unloaded provider callback: ${callbackId}`);
  const provider = String(providerName);
  if (!rawContext || typeof rawContext !== 'object' || Array.isArray(rawContext)) {
    throw new TypeError('provider refresh context must be an object');
  }
  const generation = Number(rawContext.generation);
  if (!Number.isSafeInteger(generation) || generation <= 0) throw new TypeError('provider refresh generation must be a positive integer');
  const allowNetwork = rawContext.allowNetwork === true;
  const credential = deepFreezeProviderJson(cloneProviderJson(rawContext.credential, 'provider refresh credential'));
  const stored = deepFreezeProviderJson(cloneProviderJson(rawContext.stored, 'provider refresh stored catalog'));
  let publicationSequence = 0;
  const publish = async (publication = {}) => {
    if (!publication || typeof publication !== 'object' || Array.isArray(publication)) {
      throw new TypeError('provider model publication must be an object');
    }
    signal?.throwIfAborted?.();
    const hasPersist = Object.prototype.hasOwnProperty.call(publication, 'persist') && publication.persist !== undefined;
    const request = {
      provider,
      generation,
      sequence: ++publicationSequence,
      hasPersist,
    };
    if (hasPersist) {
      if (publication.persist !== null && (typeof publication.persist !== 'object' || Array.isArray(publication.persist))) {
        throw new TypeError('provider model publication persist must be an object, null, or omitted');
      }
      request.persist = cloneProviderJson(publication.persist, 'provider model publication persist');
    }
    const accepted = await requestHost('provider_models_publish', request, signal);
    if (accepted !== true) return false;

    if (publication.update !== undefined) {
      if (typeof publication.update !== 'function') throw new TypeError('provider model publication update must be a function');
      const updateResult = publication.update();
      if (updateResult && typeof updateResult.then === 'function') {
        throw new TypeError('provider model publication update must execute synchronously');
      }
      const models = await currentProviderModels(provider);
      if (models !== undefined) {
        const catalogAccepted = await requestHost('provider_models_catalog', {
          provider,
          generation,
          sequence: ++publicationSequence,
          models,
        }, signal);
        if (catalogAccepted !== true) return false;
      }
    }
    return true;
  };
  const context = {
    credential,
    stored,
    publish,
    allowNetwork,
    signal,
  };
  if (allowNetwork && Object.prototype.hasOwnProperty.call(rawContext, 'force')) context.force = rawContext.force === true;
  Object.freeze(context);

  const returned = await record.callback(context);
  let models;
  if (Array.isArray(returned)) {
    models = cloneProviderJson(returned, `provider ${provider} refreshModels result`);
  } else if (returned === undefined && typeof providerLiveConfigs.get(provider)?.getModels === 'function') {
    models = await currentProviderModels(provider);
  } else if (returned === undefined) {
    throw new TypeError(`provider ${provider} refreshModels() must return a model array`);
  } else {
    throw new TypeError(`provider ${provider} refreshModels() must return a model array`);
  }
  signal?.throwIfAborted?.();
  return { models };
}

const providerStreamAckKey = (invocationId, sequence) => `${invocationId}:${sequence}`;
const requestProviderStreamAck = (invocationId, sequence, event, signal) => {
  signal?.throwIfAborted?.();
  const key = providerStreamAckKey(invocationId, sequence);
  if (pendingProviderStreamAcks.has(key)) throw new Error(`duplicate provider stream acknowledgement key: ${key}`);
  return new Promise((resolve, reject) => {
    let onAbort;
    const cleanup = () => { if (onAbort) signal?.removeEventListener('abort', onAbort); };
    pendingProviderStreamAcks.set(key, {
      resolve(value) { cleanup(); resolve(value); },
      reject(error) { cleanup(); reject(error); },
    });
    onAbort = () => {
      const pending = pendingProviderStreamAcks.get(key);
      if (!pending) return;
      pendingProviderStreamAcks.delete(key);
      pending.reject(signal.reason ?? new Error('Operation aborted'));
    };
    signal?.addEventListener('abort', onAbort, { once: true });
    writeResponse({ type: 'provider_stream_event', invocationId, sequence, event });
  });
};
const awaitProviderStreamStep = (promise, signal) => {
  if (!signal) return Promise.resolve(promise);
  if (signal.aborted) return Promise.reject(signal.reason ?? new Error('Operation aborted'));
  return new Promise((resolve, reject) => {
    const onAbort = () => reject(signal.reason ?? new Error('Operation aborted'));
    signal.addEventListener('abort', onAbort, { once: true });
    Promise.resolve(promise).then(resolve, reject).finally(() => signal.removeEventListener('abort', onAbort));
  });
};
const retireProviderStreamIterator = async (iterator) => {
  if (typeof iterator?.return !== 'function') return true;
  // A hostile iterator may ignore return() forever. Do not let cleanup suppress
  // the real stream failure or keep the protocol invocation permanently busy.
  return await Promise.race([
    Promise.resolve().then(() => iterator.return()).then(() => true, () => true),
    new Promise((resolve) => setTimeout(() => resolve(false), 250)),
  ]);
};
const requireProviderAssistantMessage = (value, label) => {
  if (!value || typeof value !== 'object' || Array.isArray(value)) throw new TypeError(`${label} must be an assistant message object`);
  if (value.role !== 'assistant' || !Array.isArray(value.content)) throw new TypeError(`${label} must have assistant role and array content`);
};
const requireProviderStreamIndex = (event) => {
  const index = Number(event.contentIndex);
  if (!Number.isSafeInteger(index) || index < 0) throw new TypeError(`${event.type} contentIndex must be a non-negative safe integer`);
  return index;
};
const appendUnicodeFragment = (block, fragment, label) => {
  if (typeof fragment !== 'string') throw new TypeError(`${label} must be a string`);
  let source = fragment;
  let normalized = '';
  if (block.pendingHighSurrogate) {
    if (!source.length || source.charCodeAt(0) < 0xDC00 || source.charCodeAt(0) > 0xDFFF) {
      throw new TypeError(`${label} did not complete the preceding UTF-16 surrogate pair`);
    }
    normalized += block.pendingHighSurrogate + source[0];
    block.pendingHighSurrogate = '';
    source = source.slice(1);
  }
  for (let index = 0; index < source.length; index++) {
    const code = source.charCodeAt(index);
    if (code >= 0xD800 && code <= 0xDBFF) {
      if (index + 1 >= source.length) {
        block.pendingHighSurrogate = source[index];
        break;
      }
      const low = source.charCodeAt(index + 1);
      if (low < 0xDC00 || low > 0xDFFF) throw new TypeError(`${label} contains an unpaired high surrogate`);
      normalized += source[index] + source[index + 1];
      index++;
    } else if (code >= 0xDC00 && code <= 0xDFFF) {
      throw new TypeError(`${label} contains an unpaired low surrogate`);
    } else {
      normalized += source[index];
    }
  }
  block.value += normalized;
  return normalized;
};
const canonicalJson = (value) => {
  if (Array.isArray(value)) return `[${value.map(canonicalJson).join(',')}]`;
  if (value && typeof value === 'object') {
    return `{${Object.keys(value).sort().map((key) => `${JSON.stringify(key)}:${canonicalJson(value[key])}`).join(',')}}`;
  }
  return JSON.stringify(value);
};
const parseToolArguments = (raw, label) => {
  try { return JSON.parse(raw); }
  catch (error) { throw new TypeError(`${label} is not complete JSON: ${error?.message ?? String(error)}`); }
};
const normalizeProviderStreamEvent = (rawEvent, state) => {
  const event = cloneProviderJson(rawEvent, 'provider stream event');
  if (!event || typeof event !== 'object' || Array.isArray(event) || typeof event.type !== 'string') {
    throw new TypeError('provider stream event must be an object with a string type');
  }
  if (state.terminal) throw new Error(`provider stream emitted ${event.type} after terminal ${state.terminal}`);
  if (event.type === 'start') {
    if (state.started) throw new Error('provider stream emitted start more than once');
    if (!event.partial || typeof event.partial !== 'object' || Array.isArray(event.partial)) throw new TypeError('provider stream start.partial must be an assistant message object');
    requireProviderAssistantMessage(event.partial, 'provider stream start.partial');
    state.started = true;
    return event;
  }
  if (!state.started) throw new Error(`provider stream emitted ${event.type} before start`);
  if (!['done', 'error'].includes(event.type)) requireProviderAssistantMessage(event.partial, `provider stream ${event.type}.partial`);
  const startKinds = { text_start: 'text', thinking_start: 'thinking', toolcall_start: 'toolcall' };
  const deltaKinds = { text_delta: 'text', thinking_delta: 'thinking', toolcall_delta: 'toolcall' };
  const endKinds = { text_end: 'text', thinking_end: 'thinking', toolcall_end: 'toolcall' };
  if (Object.prototype.hasOwnProperty.call(startKinds, event.type)) {
    const index = requireProviderStreamIndex(event);
    if (state.blocks.has(index)) throw new Error(`provider stream content index ${index} was started more than once`);
    state.blocks.set(index, { kind: startKinds[event.type], value: '', pendingHighSurrogate: '', sawDelta: false });
    return event;
  }
  if (Object.prototype.hasOwnProperty.call(deltaKinds, event.type)) {
    const index = requireProviderStreamIndex(event);
    const block = state.blocks.get(index);
    const kind = deltaKinds[event.type];
    if (!block || block.kind !== kind) throw new Error(`${event.type} does not match an active ${kind} block at content index ${index}`);
    event.delta = appendUnicodeFragment(block, event.delta, `${event.type}.delta`);
    block.sawDelta = true;
    return event;
  }
  if (Object.prototype.hasOwnProperty.call(endKinds, event.type)) {
    const index = requireProviderStreamIndex(event);
    const block = state.blocks.get(index);
    const kind = endKinds[event.type];
    if (!block || block.kind !== kind) throw new Error(`${event.type} does not match an active ${kind} block at content index ${index}`);
    if (block.pendingHighSurrogate) throw new TypeError(`${event.type} terminated with an incomplete UTF-16 surrogate pair`);
    if (kind === 'toolcall') {
      if (!event.toolCall || typeof event.toolCall !== 'object' || Array.isArray(event.toolCall)) throw new TypeError('toolcall_end.toolCall must be an object');
      if (event.toolCall.type !== 'toolCall' || typeof event.toolCall.id !== 'string' || !event.toolCall.id || typeof event.toolCall.name !== 'string' || !event.toolCall.name) {
        throw new TypeError('toolcall_end.toolCall must contain type, id, and name');
      }
      if (!event.toolCall.arguments || typeof event.toolCall.arguments !== 'object' || Array.isArray(event.toolCall.arguments)) {
        throw new TypeError('toolcall_end.toolCall.arguments must be an object');
      }
      if (block.sawDelta) {
        const accumulated = parseToolArguments(block.value, 'accumulated tool-call arguments');
        if (canonicalJson(accumulated) !== canonicalJson(event.toolCall.arguments)) throw new Error(`tool-call arguments at content index ${index} do not match accumulated deltas`);
      }
    } else {
      if (typeof event.content !== 'string') throw new TypeError(`${event.type}.content must be a string`);
      if (block.sawDelta && event.content !== block.value) throw new Error(`${event.type}.content does not match accumulated deltas at content index ${index}`);
    }
    state.blocks.delete(index);
    return event;
  }
  if (event.type === 'done' || event.type === 'error') {
    if (state.blocks.size) throw new Error(`provider stream terminated with ${state.blocks.size} open content block(s)`);
    const allowed = event.type === 'done' ? new Set(['stop', 'length', 'toolUse', 'deferred']) : new Set(['error', 'aborted']);
    if (!allowed.has(event.reason)) throw new TypeError(`invalid provider stream terminal reason: ${event.reason}`);
    const message = event.type === 'done' ? event.message : event.error;
    requireProviderAssistantMessage(message, `provider stream ${event.type} message`);
    state.terminal = event.type;
    state.terminalReason = event.reason;
    return event;
  }
  throw new TypeError(`unsupported provider stream event type: ${event.type}`);
};
const requireProviderCallbackGeneration = (callbackId, providerName, callbackGeneration) => {
  const record = providerCallbacks.get(String(callbackId));
  if (!record || typeof record.callback !== 'function') throw new Error(`unknown or unloaded provider callback: ${callbackId}`);
  const provider = String(providerName);
  const generation = Number(callbackGeneration);
  if (record.provider !== provider || record.generation !== generation || !Number.isSafeInteger(generation) || generation <= 0) {
    throw new Error(`stale provider callback generation: ${provider}:${callbackId}:${callbackGeneration}`);
  }
  return record;
};
async function consumeProviderEventStream(stream, invocationId, signal, label) {
  if (!stream || typeof stream[Symbol.asyncIterator] !== 'function') {
    throw new TypeError(`${label} must return an AsyncIterable assistant event stream`);
  }
  const iterator = stream[Symbol.asyncIterator]();
  const state = { started: false, terminal: null, terminalReason: null, blocks: new Map(), totalBytes: 0 };
  let sequence = 0;
  try {
    while (true) {
      signal?.throwIfAborted?.();
      const step = await awaitProviderStreamStep(iterator.next(), signal);
      if (step.done) break;
      const event = normalizeProviderStreamEvent(step.value, state);
      const eventBytes = jsonByteLength(event, 'provider stream event');
      if (eventBytes > PROVIDER_STREAM_MAX_EVENT_BYTES) throw new RangeError(`provider stream event exceeds ${PROVIDER_STREAM_MAX_EVENT_BYTES} bytes`);
      state.totalBytes += eventBytes;
      if (state.totalBytes > PROVIDER_STREAM_MAX_TOTAL_BYTES) throw new RangeError(`provider stream exceeds ${PROVIDER_STREAM_MAX_TOTAL_BYTES} cumulative bytes`);
      sequence++;
      const accepted = await requestProviderStreamAck(invocationId, sequence, event, signal);
      if (accepted !== true) throw new Error(`native host rejected provider stream event ${sequence}`);
    }
  } catch (error) {
    const retired = await retireProviderStreamIterator(iterator);
    if (!retired) {
      throw new Error(`PI_PROVIDER_STREAM_RETIRE_TIMEOUT: ${error?.message ?? String(error)}`, { cause: error });
    }
    throw error;
  }
  if (!state.terminal) throw new Error('provider stream ended without a terminal done or error event');
  return { invocationId, events: sequence, terminal: state.terminal, reason: state.terminalReason, bytes: state.totalBytes };
}
async function invokeProviderStreamSimple(callbackId, providerName, callbackGeneration, invocationId, rawModel, rawContext, rawOptions, signal) {
  const record = requireProviderCallbackGeneration(callbackId, providerName, callbackGeneration);
  const model = deepFreezeProviderJson(cloneProviderJson(rawModel, 'provider stream model'));
  const context = deepFreezeProviderJson(cloneProviderJson(rawContext, 'provider stream context'));
  const options = deepFreezeProviderJson(cloneProviderJson(rawOptions ?? {}, 'provider stream options'));
  const stream = await record.callback(model, context, Object.freeze({ ...options, signal }));
  return consumeProviderEventStream(stream, invocationId, signal, 'provider streamSimple()');
}
async function invokeProviderFetchDeferred(callbackId, providerName, callbackGeneration, invocationId, rawModel, rawHandle, rawOptions, signal) {
  const record = requireProviderCallbackGeneration(callbackId, providerName, callbackGeneration);
  const model = deepFreezeProviderJson(cloneProviderJson(rawModel, 'provider deferred model'));
  const handle = deepFreezeProviderJson(cloneProviderJson(rawHandle, 'provider deferred handle'));
  const options = deepFreezeProviderJson(cloneProviderJson(rawOptions ?? {}, 'provider deferred options'));
  const stream = await record.callback(model, handle, Object.freeze({ ...options, signal }));
  return consumeProviderEventStream(stream, invocationId, signal, 'provider fetchDeferred()');
}
async function invokeProviderCancelDeferred(callbackId, providerName, callbackGeneration, rawModel, rawHandle, rawOptions, signal) {
  const record = requireProviderCallbackGeneration(callbackId, providerName, callbackGeneration);
  const model = deepFreezeProviderJson(cloneProviderJson(rawModel, 'provider deferred model'));
  const handle = deepFreezeProviderJson(cloneProviderJson(rawHandle, 'provider deferred handle'));
  const options = deepFreezeProviderJson(cloneProviderJson(rawOptions ?? {}, 'provider deferred options'));
  await record.callback(model, handle, Object.freeze({ ...options, signal }));
  return { cancelled: true };
}

async function invokeProviderOAuthLogin(callbackId, signal) {
  const record = providerCallbacks.get(String(callbackId));
  if (!record || typeof record.callback !== 'function') throw new Error(`unknown or unloaded provider callback: ${callbackId}`);
  const text = (value) => value == null ? '' : String(value);
  const optionalText = (value) => value == null ? undefined : String(value);
  const callbacks = {
    onAuth(info = {}) {
      emitUiAction('oauth_auth', {
        url: text(info.url),
        instructions: optionalText(info.instructions),
      });
    },
    onDeviceCode(info = {}) {
      emitUiAction('oauth_device_code', {
        verificationUri: text(info.verificationUri ?? info.verification_uri ?? info.url),
        userCode: text(info.userCode ?? info.user_code ?? info.code),
        intervalSeconds: info.intervalSeconds ?? info.interval_seconds,
        expiresInSeconds: info.expiresInSeconds ?? info.expires_in_seconds,
        instructions: optionalText(info.instructions),
      });
    },
    onPrompt(prompt = {}) {
      return requestHost('oauth_prompt', {
        message: text(prompt.message ?? prompt.title),
        placeholder: optionalText(prompt.placeholder),
        secret: !!prompt.secret,
      }, signal);
    },
    onProgress(message) {
      emitUiAction('oauth_progress', { message: text(message) });
    },
    onManualCodeInput() {
      return requestHost('oauth_manual_code', { message: 'Paste the authorization code' }, signal);
    },
    onSelect(prompt = {}) {
      const options = Array.isArray(prompt.options) ? prompt.options.map((option) =>
        option && typeof option === 'object'
          ? {
              value: text(option.id ?? option.value),
              label: text(option.label ?? option.id ?? option.value),
              description: optionalText(option.description),
            }
          : { value: text(option), label: text(option) }) : [];
      return requestHost('oauth_select', {
        message: text(prompt.message ?? prompt.title),
        options,
      }, signal);
    },
    signal,
  };
  return await record.callback(callbacks);
}
const toolRendererContext = (name, payload, state, slot) => ({
  args: state.args,
  toolCallId: state.toolCallId,
  invalidate() {},
  lastComponent: state[slot],
  state: state.shared,
  cwd: currentContext.cwd ?? process.cwd(),
  executionStarted: payload.executionStarted !== false,
  argsComplete: payload.argsComplete !== false,
  isPartial: !!payload.isPartial,
  expanded: !!payload.expanded,
  showImages: payload.showImages !== false,
  isError: !!payload.isError,
});
async function invokeRenderer(kind, name, payload) {
  if (kind === 'prepare_tool_arguments') {
    const tool = tools.get(String(name));
    if (!tool || typeof tool.prepareArguments !== 'function') return { found: false, arguments: payload.args ?? {} };
    const prepared = await tool.prepareArguments(payload.args ?? {});
    if (!prepared || typeof prepared !== 'object' || Array.isArray(prepared)) throw new Error(`prepareArguments for ${name} must return an object`);
    return { found: true, arguments: prepared };
  }
  if (kind === 'render_message') {
    const renderer = messageRenderers.get(String(name));
    if (!renderer) return { found: false, lines: [] };
    const component = await renderer(payload.message ?? {}, { expanded: !!payload.expanded, outputPad: Number(payload.outputPad ?? 0) }, theme);
    return { found: true, lines: await renderComponent(component) };
  }
  if (kind === 'render_entry') {
    const renderer = entryRenderers.get(String(name));
    if (!renderer) return { found: false, lines: [] };
    const component = await renderer(payload.entry ?? {}, { expanded: !!payload.expanded }, theme);
    return { found: true, lines: await renderComponent(component) };
  }
  if (kind === 'transform_markdown') {
    if (typeof markdownTransformer !== 'function') return { found: false, markdown: String(payload.markdown ?? '') };
    const transformed = await markdownTransformer(String(payload.markdown ?? ''), {
      messageType: payload.messageType ?? 'assistant',
      isStreaming: !!payload.isStreaming,
      availableWidth: Number(payload.availableWidth ?? currentContext.width ?? 80),
    });
    return { found: true, markdown: transformed == null ? String(payload.markdown ?? '') : String(transformed) };
  }
  if (kind === 'render_tool_call') {
    const tool = tools.get(String(name));
    if (!tool || typeof tool.renderCall !== 'function') return { found: false, lines: [] };
    const id = String(payload.toolCallId ?? `${name}:default`);
    const state = toolRenderState.get(id) ?? { toolCallId: id, args: payload.args ?? {}, shared: {}, call: undefined, result: undefined };
    state.args = payload.args ?? state.args ?? {};
    const component = await tool.renderCall(state.args, theme, toolRendererContext(name, payload, state, 'call'));
    state.call = component;
    toolRenderState.set(id, state);
    return { found: true, lines: await renderComponent(component) };
  }
  if (kind === 'render_tool_result') {
    const tool = tools.get(String(name));
    if (!tool || typeof tool.renderResult !== 'function') return { found: false, lines: [] };
    const id = String(payload.toolCallId ?? `${name}:default`);
    const state = toolRenderState.get(id) ?? { toolCallId: id, args: payload.args ?? {}, shared: {}, call: undefined, result: undefined };
    state.args = payload.args ?? state.args ?? {};
    const component = await tool.renderResult(
      payload.result ?? { content: [], isError: !!payload.isError },
      { expanded: !!payload.expanded, isPartial: !!payload.isPartial },
      theme,
      toolRendererContext(name, payload, state, 'result'),
    );
    state.result = component;
    if (payload.isPartial) toolRenderState.set(id, state); else toolRenderState.delete(id);
    return { found: true, lines: await renderComponent(component) };
  }
  throw new Error(`unsupported renderer kind: ${kind}`);
}

const rl = readline.createInterface({ input: process.stdin, crlfDelay: Infinity, terminal: false });
let invocationBusy = false;
let currentAbortController = null;
let currentInvocationId = null;
const runInvocation = async (request) => {
  currentFlags = request.flags && typeof request.flags === 'object' ? request.flags : {};
  currentContext = request.context && typeof request.context === 'object' ? { ...currentContext, ...request.context } : currentContext;
  if (Array.isArray(request.context?.activeTools)) activeTools = request.context.activeTools.map(String);
  const actions = createActions(); currentActions = actions;
  const abortController = (request.kind === 'tool' || request.abortable) ? new AbortController() : null;
  const invocationId = String(request.invocationId ?? '');
  currentAbortController = abortController;
  currentInvocationId = invocationId;
  if (abortController && request.aborted) abortController.abort(new Error(String(request.abortReason ?? 'Operation aborted')));
  try {
    let result;
    if (request.kind === 'hook') result = await invokeHook(request.name, request.payload ?? {}, actions, abortController?.signal);
    else if (request.kind === 'tool') result = await invokeTool(request.name, request.payload ?? {}, actions, !!request.streamUpdates, abortController.signal, request.toolCallId);
    else if (request.kind === 'provider_method') {
      result = await invokeProviderMethod(request.callbackId, request.args ?? [], abortController?.signal, !!request.appendSignal);
      writeResponse({ ok: true, result: { value: result === undefined ? null : result } });
      return;
    }
    else if (request.kind === 'provider_oauth_login') {
      result = await invokeProviderOAuthLogin(request.callbackId, abortController?.signal);
      writeResponse({ ok: true, result: { value: result === undefined ? null : result } });
      return;
    }
    else if (request.kind === 'provider_refresh_models') {
      result = await invokeProviderRefreshModels(request.callbackId, request.providerName, request.refreshContext ?? {}, abortController?.signal);
      writeResponse({ ok: true, result });
      return;
    }
    else if (request.kind === 'provider_stream_simple') {
      result = await invokeProviderStreamSimple(request.callbackId, request.providerName, request.callbackGeneration, invocationId, request.model ?? {}, request.streamContext ?? {}, request.options ?? {}, abortController?.signal);
      writeResponse({ ok: true, result });
      return;
    }
    else if (request.kind === 'provider_fetch_deferred') {
      result = await invokeProviderFetchDeferred(request.callbackId, request.providerName, request.callbackGeneration, invocationId, request.model ?? {}, request.handle ?? {}, request.options ?? {}, abortController?.signal);
      writeResponse({ ok: true, result });
      return;
    }
    else if (request.kind === 'provider_cancel_deferred') {
      result = await invokeProviderCancelDeferred(request.callbackId, request.providerName, request.callbackGeneration, request.model ?? {}, request.handle ?? {}, request.options ?? {}, abortController?.signal);
      writeResponse({ ok: true, result });
      return;
    }
    else if (request.kind === 'provider_callback_commit') {
      result = commitProviderCallbacks(request.providerName, request.callbackIds ?? []);
      writeResponse({ ok: true, result });
      return;
    }
    else if (request.kind === 'command') result = await invokeCommand(request.name, request.rawArguments ?? '', actions);
    else if (request.kind === 'shortcut') result = await invokeShortcut(request.name, actions);
    else if (request.kind.startsWith('render_') || request.kind === 'transform_markdown' || request.kind === 'prepare_tool_arguments') {
      result = await invokeRenderer(request.kind, request.name ?? '', request.payload ?? {});
      writeResponse({ ok: true, result });
      return;
    } else throw new Error(`unsupported request kind: ${request.kind}`);
    writeResponse({ ok: true, result: mergeActions(result && typeof result === 'object' ? result : {}, actions) });
  } catch (error) {
    if (request.kind === 'tool' && abortController?.signal.aborted) {
      const reason = abortController.signal.reason;
      const message = reason instanceof Error ? reason.message : String(reason ?? 'Operation aborted');
      const result = normalizeToolResult({
        content: [{ type: 'text', text: `Tool execution aborted: ${message}` }],
        details: { aborted: true, reason: message },
        isError: true,
      });
      writeResponse({ ok: true, result: mergeActions(result, actions) });
    } else if (actions.contextInvalidated) {
      actions.isError = true;
      writeResponse({ ok: true, result: mergeActions({ staleContextError: error?.message ?? String(error) }, actions) });
    } else {
      writeResponse({ ok: false, error: error?.stack ?? String(error) });
    }
  } finally {
    currentActions = null;
    if (currentInvocationId === invocationId) { currentAbortController = null; currentInvocationId = null; }
    invocationBusy = false;
  }
};
for await (const line of rl) {
  if (!line.trim()) continue;
  let request;
  try { request = JSON.parse(line); } catch (error) { writeResponse({ ok: false, error: `invalid request: ${error.message}` }); continue; }
  if (request.kind === 'abort_current' || request.kind === 'abort') {
    const target = String(request.invocationId ?? '');
    if (currentAbortController && !currentAbortController.signal.aborted && (!target || target === currentInvocationId)) {
      currentAbortController.abort(new Error(String(request.reason ?? 'Operation aborted')));
    }
    continue;
  }
  if (request.kind === 'provider_stream_ack') {
    const key = providerStreamAckKey(String(request.invocationId ?? ''), Number(request.sequence));
    const pending = pendingProviderStreamAcks.get(key);
    if (!pending) continue;
    pendingProviderStreamAcks.delete(key);
    if (request.ok === false) pending.reject(new Error(request.error ?? 'native provider stream event rejected'));
    else pending.resolve(request.accepted !== false);
    continue;
  }
  if (request.kind === 'ui_response') {
    const pending = pendingUi.get(Number(request.id));
    if (!pending) continue;
    pendingUi.delete(Number(request.id));
    if (request.ok) pending.resolve(request.result); else pending.reject(new Error(request.error ?? 'native UI request failed'));
    continue;
  }
  if (request.kind === 'shutdown') {
    if (currentAbortController && !currentAbortController.signal.aborted) currentAbortController.abort(new Error('extension runtime shutting down'));
    for (const pending of pendingUi.values()) pending.reject(new Error('extension runtime shutting down'));
    pendingUi.clear();
    for (const pending of pendingProviderStreamAcks.values()) pending.reject(new Error('extension runtime shutting down'));
    pendingProviderStreamAcks.clear();
    writeResponse({ ok: true, result: {} });
    break;
  }
  if (invocationBusy) { writeResponse({ ok: false, error: 'extension invocation already in progress' }); continue; }
  invocationBusy = true;
  void runInvocation(request);
}
