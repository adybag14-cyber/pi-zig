// Guest extension input for the actual Source/native nodeLoader.
import { marker, url } from "../b/shared.mjs";
export default {
  uses: [],
  setup(api) {
    globalThis.loaderTrace.push({ facet: "a", marker, module: import.meta.url, shared: url, signal: api.signal });
    api.serve(globalThis.loaderTokenA, () => ({ marker }), { lifetime: "host" });
  },
};
