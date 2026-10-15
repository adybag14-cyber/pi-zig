// Caller-only oracle. Load with the ae7 Source observer; no Source body replacement.
import { pathToFileURL } from 'node:url';
import { writeFileSync } from 'node:fs';
import { createHash } from 'node:crypto';
const root = process.env.PI_SOURCE_ROOT ?? 'C:/Users/adyba/pi-upstream-source-ae7b16d-20261015';
const { InteractiveMode } = await import(pathToFileURL(root + '/packages/coding-agent/src/modes/interactive/interactive-mode.ts'));
const show = InteractiveMode.prototype.showExtensionCustom;
if (typeof show !== 'function') throw Error('Original InteractiveMode.showExtensionCustom absent');
const tick = async () => { for (let i = 0; i < 8; i++) await Promise.resolve(); };
function caller() {
  const log = [], stack = [], handles = new Map(), done = new Map(), state = new Map();
  const editor = { text: 'saved draft', getText() { return this.text; }, setText(text) { this.text = text; log.push(['text', text]); } };
  const owner = {
    editor, keybindings: {},
    editorContainer: { clear() { log.push(['clear']); }, addChild(c) { log.push(['add', c === editor ? 'editor' : c.id]); } },
    disposeActiveSelector() { log.push(['selector']); },
    ui: {
      setFocus(c) { log.push(['focus', c === editor ? 'editor' : c.id]); }, requestRender() { log.push(['render']); },
      hideOverlay() { throw Error('topmost hide must never be called'); },
      showOverlay(c, options) {
        stack.push(c.id); log.push(['show', c.id, options ?? null]);
        const handle = { hide() { log.push(['hide', c.id]); if (c.hideError) throw c.hideError; const i = stack.indexOf(c.id); if (i >= 0) stack.splice(i, 1); log.push(['render']); } };
        handles.set(c.id, handle); return handle;
      },
    },
  };
  const open = (id, configure = {}) => {
    state.set(id, 'pending');
    const component = { id, width: configure.width, hideError: configure.hideError, render() { return [id]; }, dispose() { log.push(['dispose', id]); if (configure.disposeError) throw configure.disposeError; } };
    const factory = (_tui, _theme, _keys, close) => {
      done.set(id, close); log.push(['factory', id]);
      if (configure.early) close(id + '-early');
      if (configure.reject) return Promise.reject(configure.reject);
      if (configure.throw) throw configure.throw;
      return configure.defer ? new Promise(resolve => { configure.resolve = () => resolve(component); }) : component;
    };
    const options = { overlay: configure.overlay ?? true, overlayOptions: configure.options, onHandle(h) { log.push(['handle', id]); if (h !== handles.get(id)) throw Error('Saved handle identity lost'); } };
    const promise = show.call(owner, factory, options);
    promise.then(value => { state.set(id, ['resolved', value]); }, error => { state.set(id, ['rejected', error.message]); });
    return promise;
  };
  return { owner, log, stack, handles, done, state, open, snapshot() { return { log: [...log], stack: [...stack], state: Object.fromEntries(state), editor: editor.text }; } };
}
const rows = [];
for (const order of [['middle', 'lower', 'top'], ['lower', 'top', 'middle'], ['top', 'middle', 'lower']]) {
  const c = caller(); for (const id of ['lower', 'middle', 'top']) c.open(id); await tick();
  const steps = [c.snapshot()];
  for (const id of order) { c.done.get(id)(id + '-result'); c.done.get(id)('duplicate'); await tick(); steps.push(c.snapshot()); }
  rows.push({ case: 'close-order', order, steps });
}
{
  const c = caller(), deferred = { defer: true }; c.open('slow', deferred); c.open('fast'); await tick();
  const steps = [c.snapshot()]; deferred.resolve(); await tick(); steps.push(c.snapshot());
  c.done.get('fast')('fast-result'); await tick(); steps.push(c.snapshot()); c.done.get('slow')('slow-result'); await tick(); steps.push(c.snapshot());
  rows.push({ case: 'async-factory', steps });
}
for (const variant of ['early', 'early-async', 'reject', 'throw', 'dispose-error', 'raw-hide-error', 'normal-restore', 'normal-reject']) {
  const c = caller(), error = Error(variant), configure = {};
  if (variant.startsWith('early')) configure.early = true;
  if (variant === 'early-async') configure.defer = true;
  if (variant === 'reject' || variant === 'normal-reject') configure.reject = error;
  if (variant === 'throw') configure.throw = error;
  if (variant === 'dispose-error') configure.disposeError = error;
  if (variant === 'raw-hide-error') configure.hideError = error;
  if (variant.startsWith('normal-')) configure.overlay = false;
  c.open('subject', configure); await tick();
  const steps = [c.snapshot()];
  if (configure.defer) { configure.resolve(); await tick(); steps.push(c.snapshot()); }
  if (!configure.early && !configure.reject && !configure.throw) {
    c.owner.editor.text = 'edited while open';
    try { c.done.get('subject')('result'); } catch (e) { c.log.push(['caller-caught', e.message, e === error]); }
    c.done.get('subject')('duplicate'); await tick(); steps.push(c.snapshot());
  }
  rows.push({ case: variant, steps });
}
const result = { sourceCommit: 'ae7b16d43b7c78c5b6fa3213fdd1215bb339729d', authority: 'actual InteractiveMode.prototype.showExtensionCustom; controlled caller collaborators', methodSha256: createHash('sha256').update(Function.prototype.toString.call(show)).digest('hex'), actualNode: { version: process.version, execPath: process.execPath }, rows };
if (process.env.PI_UI_OVERLAY_OUTPUT) writeFileSync(process.env.PI_UI_OVERLAY_OUTPUT, JSON.stringify(result, null, 2) + '\n');
else process.stdout.write(JSON.stringify(result, null, 2) + '\n');
