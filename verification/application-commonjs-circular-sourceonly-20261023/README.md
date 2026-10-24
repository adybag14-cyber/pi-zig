# Actual CommonJS circular-export collaborator

This source-only packet closes the two missing circular-export collaborators at the canonical `native_node_commonjs_load.create` boundary. It implements the original Node 24.14 `CircularRequirePrototypeWarningProxy` and `getExportsForCircularRequire`, then creates and retains them from the actual shared Module owner. The old caller-supplied `circular_exports` and `circular_warning_proxy` inputs are removed.

Base Main: `65fac9975b25e9a5e4c00d7d7bca499aae1275c0`. Main is unchanged. No compiler, metadata query, runtime, Node capture, formatter, generator, or candidate execution was performed.

## Selected source

Use the exact candidates and digests in `source-accounting.json`, not the preserved earlier drafts:

| Target | Selected candidate |
| --- | --- |
| src/extensions/native_node_commonjs_circular.zig | projected-v2/src/extensions/native_node_commonjs_circular.zig |
| src/extensions/native_node_commonjs_load.zig | projected-v2/src/extensions/native_node_commonjs_load.zig |
| src/extensions/native_node_module_constructor.zig | projected-v2/src/extensions/native_node_module_constructor.zig |
| src/native_node_commonjs_circular_test.zig | projected-v3/src/native_node_commonjs_circular_test.zig |
| build.zig | build-addition.zig.txt, inserted before the exact recorded anchor |

`application-commonjs-circular-source.patch` is the exact five-target standalone patch against Main. Its read-only `git apply --check` passed. The build change is an additive install-only test root; compose its insertion with other accepted build additions instead of replacing an already-composed build file.

## Behavior and authority

The retained Node authority is loader.js lines 974–1035 at commit `f657bb8ed86365ff3fdbe32e27563e778b41486a`; the original `ERR_REQUIRE_CYCLE_MODULE` registration is the same commit's internal/errors.js line 1690. Exact existing authority paths and digests are referenced once in the accounting; no authority bytes are copied into this packet.

The native Proxy has a null-prototype handler and a real ordinary target. Its get trap uses inherited-property semantics, while its descriptor trap uses the retained hasOwnProperty declaration. Both preserve the __esModule exception. The warning reads the live process.emitWarning callee before String(prop), preserving the original evaluation order and receiver.

The genuine Module captures the six required Object/String primordials in its existing private lexical owner before guest execution. Linking this collaborator later therefore does not capture guest replacements. The native circular function retains the actual private required-module symbol, last-parent relationship, real Node error constructor, warning Proxy, and original operation scopes. It repeats all six module.exports reads on the plain-object path; it does not fold getters or replace the actual exports identity.

The evaluated module phase remains a required input from the actual module_wrap owner. This packet neither invents that enum nor supplies an ESM implementation. The test value 71 is deliberately controlled comparison data.

Only `create` changes in the existing _load owner, and only `createBody` changes in the existing Module constructor. The loader body, cache/cleanup branches, other helpers, and warning-prototype reset are preserved. Complete helper-body and finite byte-inverse checks are recorded in the accounting.

## Focused controls

The new install-only target is `build-native-node-commonjs-circular`, with filter `native actual CommonJS circular`. Nine authored declarations cover actual Proxy/function identity, inherited versus own property behavior, warning order and symbol formatting, excluded export shapes, all six getter occurrences, real cycle error/private parent behavior, completed and throwing ESM status, warning/prototype abrupt completion, canonical primordial capture after guest mutation, and rejection of missing status or a foreign Module. Some declarations exercise several related cases.

The controls use the real native Engine, process/Stream installation, Module core, private keys, and error owners. They do not publish a substitute public node:module. They remain uncompiled and unexecuted; no native metadata count is predicted.

## Application seam and remaining integration

`application-seam-review.json` pins the actual Main sources and original Pi loader authority. The native worker already launches the linked executable without a Node process, but still installs the earlier createRequire-only module and SDK facade path. The completed application owner requires the shared canonical Module graph, physical loader/config inputs, actual lazy Jiti imports and native supplier lifetimes. Main's default remains legacy.

This packet removes two missing caller-supplied policies from the real canonical _load assembly. It does not itself remove the production bridge or activate the full application owner. Remaining work includes real hooks/builtin/TS/synchronous-ESM/inspector collaborators, actual module_wrap status ownership, full native Jiti/Babel/provider/compiler/IO graph and namespace publication, complete coding-agent namespace/lifetime assembly, and print/RPC/Main integration.

The sealed earlier StreamBase/Module two-root intake and its future validation controls are separate and unchanged. This new root must be admitted and qualified only after its own review and actual source intake.
