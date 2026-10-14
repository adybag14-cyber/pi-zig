// User TypeScript remains supported input; the implementation transformer is Zig/C.
const label: string = "typed";
export default {
  uses: [],
  setup(api: { serve: (...args: unknown[]) => void; signal: AbortSignal }) {
    globalThis.loaderTrace.push({ facet: label, module: import.meta.url, signal: api.signal });
    api.serve(globalThis.loaderTokenTyped, () => ({ marker: { typed: true } }), { lifetime: "host" });
  },
};
