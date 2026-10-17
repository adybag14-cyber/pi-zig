// Prepared user input, UNRUN. The driver supplies the completed actual source
// createJiti export, actual node:module.createRequire and owned physical names.
// No substitute factory, nested jiti, Module, transform frontend or cache.
export function observeEvalBoundaries(actualCreateJiti, actualCreateRequire, actualModule, physicalRoot, physicalNames) {
  const observations = [];
  for (const kind of ["wrap-throw", "invalid-sync-code", "valid-code", "wrap-async-getter-throw"]) {
    const filename = physicalNames[kind];
    const trace = [];
    const nativeRequire = actualCreateRequire(physicalRoot);
    const parentCache = Object.create(null);
    const marker = {kind};
    const codeValue = {
      startsWith(prefix) { trace.push(["code.startsWith", prefix]); return false; },
      toString() {
        trace.push(["code.toString", !!parentCache[filename], nativeRequire.cache[filename] === parentCache[filename]]);
        if (kind === "wrap-throw") throw marker;
        return kind === "invalid-sync-code" ? "const = ;" : "exports.answer = 7; exports.moduleRecord = module;";
      }
    };
    const parent = {
      parentCache,
      createRequire: actualCreateRequire,
      onError(reason) {
        trace.push(["onError", reason === marker, reason.name, !!parentCache[filename], Object.hasOwn(nativeRequire.cache, filename)]);
        // Returning is legal Source behavior; do not simplify to throw.
      }
    };
    const options = {fsCache:false, moduleCache:true, tsconfigPaths:false, debug:false, interopDefault:false,
      transform(request) { trace.push(["transform", request.filename, request.async]); return {code:codeValue}; }
    };
    const jiti = actualCreateJiti(physicalRoot, options, parent, false);
    let asyncReads = 0;
    const evalOptions = {filename, forceTranspile:true};
    Object.defineProperty(evalOptions, "async", {get() {
      ++asyncReads;
      trace.push(["async", asyncReads, !!parentCache[filename]]);
      if (kind === "wrap-async-getter-throw" && parentCache[filename]) throw marker;
      return false;
    }});
    let result, thrown;
    try { result = jiti.evalModule("export const originalInput = 1;", evalOptions); }
    catch (reason) { thrown = reason; }
    const record = parentCache[filename];
    observations.push({kind, trace, thrownIsMarker:thrown === marker, thrownName:thrown?.name,
      parentPublished:!!record, nativePublished:Object.hasOwn(nativeRequire.cache, filename),
      loaded:record?.loaded, resultIsExports:!!record && result === record.exports,
      actualModuleIdentity:!!record && record.constructor === actualModule,
      answer:result?.answer});
    // Retain physical and cache effects for the bounded owner/post audit. No
    // cleanup/rewrite here, no expected bytes or scheduling assertions.
  }
  return observations;
}
