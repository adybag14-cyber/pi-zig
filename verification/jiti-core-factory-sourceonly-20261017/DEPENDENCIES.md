# Finite remaining jiti inputs

Authority is jiti 2.7.0 / fd3bb289b75ed207edfb686d671ed50144f7e90f,
the retained original npm archive and its exact pnpm lock. This is a source
inventory, not a claim that the typed imports are complete native modules.

| Actual export/body | Exact authority and version | Consumed algorithm / direct dependencies | Current ownership / gap |
| --- | --- | --- | --- |
| `hasESMSyntax(code, opts={})` | mlly1.8.2 `dist/index.mjs`, lines2644–2653, owner tree `worktrees/jiti-resolver-dependencies/verification/jiti-resolver-deps-sourceonly-20261017/authority/mlly-1.8.2/dist/index.mjs.txt` | Module-scoped ESM_RE; optional COMMENT_RE replacement when `opts.stripComments`, then live ESM_RE.test(code). **No Acorn tokenizer in this export.** Acorn is used by other mlly location helpers. Exact original regex and object lifetime must be retained. | This lane. No parser port or heuristic needed. |
| `getTsconfig`, `createPathsMatcher` | get-tsconfig4.14.0; `require("get-tsconfig")` only inside jiti `src/jiti.ts` tsconfigPaths branch; version fixed by retained `pnpm-lock.yaml` importer | Actual config search/read/parse, extends/reference paths, baseUrl/paths matcher; get-tsconfig package primary body/archive still needs pinning before port. Default true in jiti options, so not optional for default closure. | Missing real library require namespace; Root can assign package leaf. |
| `transform(ctx,topts)` | jiti2.7 `src/transform.ts`, SHA D93A6FE0B63A33A729ED510912C8728794CD18F07084B88482CB40F0367F2705 | Actual getCache callback; live ctx.opts.transform and transformOptions spreads, babel subobject/order, sourceMaps, interopDefault, user topts, res.error/debug, raw res.code; live startsWith("#!") and string prefix. | Missing original orchestration; native API12a is a separately bounded compiler profile, **not this algorithm/default Babel replacement**. |
| `getCache`, `prepareCacheDir`, `getCacheDir` | jiti2.7 `src/cache.ts`, SHA84A3D6812AD44D8CD835081C25DF283CFD28938C13C4A9E2BD64FBFFD9434930, CACHE_VERSION9 | node:fs exists/mkdir/read/write; node:os.tmpdir; pathe dirname/join/basename/resolve and pathe/utils.filename; Source debug/isWritable/hash; inline sourceHash/file name policy, __JITI_ERROR__ non-store, exact temporary TMPDIR delete/restore. | Missing finite cache module; real FS/path dependencies have other owners. No replacement cache. |
| `debug`, static debugMap | jiti2.7 `src/utils.ts`, SHAC0B823DF0E6F848236EAC75BC6081CBA55A9C2EC076D5AF240750A081989C954 | At module initialization actual yoctocolors2.1.2 green/yellow/blue/cyan/red calls populate15 entries; function ctx.opts.debug guard, process.cwd, live console.log and gray; actual args.map callback, `in`/property access, JSON.stringify or live string.replace, array join. | Missing finite debug/initialization graph. yoctocolors2.1.2 archive/body must be pinned; not a no-op when debug false. |
| `readNearestPackageJSON` | same jiti2.7 `src/utils.ts` | Repeated pathe.join(path,".."); actual readFileSync(join(path,"package.json"),"utf8"); nested JSON.parse catch; invalid found JSON breaks rather than ascending; ordinary catches/fresh-fatal ownership. | This lane or concrete utility owner. No parser/SourceLoader alias. |
| `isDir`, `isWritable`, `hash`/private `isFipsMode` | same jiti2.7 `src/utils.ts` | typeof/startWith early guard; actual lstatSync().isDirectory; accessSync(constants.W_OK) catch; node:crypto default namespace getFips optional-call cached once, createHash(md5/sha256), update/digest/slice. | Actual lstat and crypto source leaves exist in other lanes; orchestration still required. |
| `fileURLToPath`, `pathToFileURL`, `resolvePathSync`; pathe/aliases | mlly1.8.2, pathe2.0.3, runtime ufo1.6.4/import-meta-resolve4.2.0 | Exact owned URL/path/resolution algorithms, actual FS + parent URL/options behavior. | models_refresh owner. No substitution with old SourceLoader path policy. |
| real CommonJS createRequire, builtinModules, .resolve/.paths/.extensions/cache | Node24.14 primary source and existing Engine/CommonJS identity | Constructor8a and reviewed CommonJS seam are independent source units. Need actual identities and same shared cache supplied to core/require/eval. | models_auth owner; no duplicate namespace/cache. |
| public package `createJiti` wrapper and lazyTransform | jiti2.7 `lib/jiti.cjs` / `lib/jiti.mjs`, original npm packet in `verification/node-module-constructor-sourceonly-20261016/authority/jiti-package` | Public wrapper supplies actual native createRequire, throwing onError, queued nativeImport; only when opts.transform falsy it installs actual lazy dist/babel.cjs loader. It calls the real four-argument internal core. | Public wrapper/default transformer still separate from this internal-core unit. No complete public createJiti claim. |
| `esmEval` / `writeEsmTempFile` | jiti2.7 `src/eval.ts` after main body | SyntaxError+async+nativeImport compile fallback; actual Buffer/base64/data URI or temporary .mjs write, ENAMETOOLONG-only fallback, nativeImport, default(...args), finally unlink.catch. | Missing real fallback, explicit RequiredActualJitiEsmEval. No fake compiled function or unconditional ordinary-error simplification. |

`escape-string-regexp`5.0.0 is implemented in this source unit, using its
exact two regex literals and live replace calls. RegExp objects are actual VM
objects. Its original source/license and npm SHA512 receipt are retained here.

Root can assign cache+transform orchestration, utility/debug+yoctocolors, and
get-tsconfig as three finite source ports. This lane retains core/frontend/cells,
the exact mlly hasESMSyntax export, and the public wrapper composition after
those actual dependencies arrive. The qualified Graph0 queued import and
Graph2/private transformed graph/default interop/reclamation integration remain
separate gates; this packet changes none of them.
