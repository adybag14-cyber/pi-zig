// Guest extension input for the actual Source/native nodeLoader.
import { marker, url } from "./shared.mjs";
export default {
  uses: [],
  setup(api) {
    globalThis.loaderTrace.push({ facet: "b", marker, module: import.meta.url, shared: url, signal: api.signal });
    api.serve(globalThis.loaderTokenB, () => ({ marker }), { lifetime: "host" });
  },
};
