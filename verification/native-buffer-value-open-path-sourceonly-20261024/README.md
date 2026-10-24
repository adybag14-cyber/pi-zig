# Native BufferValue and OpenFileHandle pre-request supplier

This source-only successor implements original Node v24.13 BufferValue and the complete OpenFileHandle argument, namespace, flags, mode and permission portion before GetReqWrap. It installs no public fs namespace and performs no physical request.

## Production behavior

BufferValue accepts primitive strings and actual ArrayBufferView brands. It rejects other values without ToString or property access. Strings use the accepted flat-string owner and exact original Latin1/wide sizing, replacement of isolated surrogates and NUL termination. The owned native bytes survive caller Scope retirement, wrapper release, backing detach and GC; no asynchronous backing-store lease is added.

A narrow QuickJS CopyContents ABI maps V8 stored byte length. Original V8 tracking TypedArrays and tracking DataViews store zero even when ByteLength is nonzero. BufferValue intentionally ignores CopyContents' returned count, retains its original dynamic logical length and terminator, and does not initialize or inspect the unused suffix. Source controls inspect only defined bytes. Replacing this with dynamic-span memcpy would change original behavior.

MaybeStackBuffer grows through the real Environment allocator, preserves the logical stack prefix, retries native allocation once after full GC and retains the original terminal CHECK policy. Smaller requests do not shrink capacity. Three visibility-only tokens expose existing accepted StringBytes helpers; their bodies are unchanged.

The new Arguments owner preserves argc check, BufferValue/null check, ToNamespacedPath, exact V8 IsInt32 checks for flags/mode, then synchronous CheckOpenPermissions. Negative zero, fractional/nonfinite/out-of-range numbers and nonnumbers remain native CHECK cases; no recoverable guest policy is invented. The native namespace function borrows actual same-Engine EnvironmentPath/private Map/trace owners. POSIX and empty Windows paths preserve original no-op behavior. The full native span, including embedded NUL, survives namespacing and permission Error setter reentry.

## Composition

Eight target files are selected in source-intake.json: two new owners, one new test root, additive C/header successors, additive MaybeStackBuffer growth, visibility-only StringBytes successor and one build insertion.

The C/header predecessor is the accepted External packet. MaybeStackBuffer and StringBytes come from accepted Writev. Frozen Main 7947d3a already has those exact donor bytes. The install-only build projection adds 1,553 bytes to its 536,372-byte build; compose only this insertion if Main's build has advanced.

The separately accepted OpenPermissions packet 4EC3F12F is required first: its genuine fs_open_permissions owner and permission_error successor are selected dependencies, not copied into this packet. Its separate 1,491-byte build insertion can compose at the same anchor without rewriting either packet. Current Main's accepted nearest-parent native namespace C/header are required; the older OpenPermissions packet's pre-namespace C/header input pins are historical and not replacements.

## Controls and qualification

The 28 source-declared controls use actual Engine, callback Environment, native Permission, EnvironmentPaths, private Map and charged storage. They cover conversion and stack thresholds, all typed array kinds and DataView, hostile properties/proxies, detached/fixed out-of-bounds/tracking views, pending exception preservation, external release without a lease, heap retirement, foreign-owner refusal, native drive/UNC/NUL paths, exact valid Int32 extremes, request nonselection before denial, and Error setter repair/reentry/GC.

The NativePolicy fixture's prior lifecycle is byte-exact except for an added native private-Map setter. Unselected Environment policies fail explicitly in the fixture; they are not production defaults. Terminal invalid argument/OOM cases are not executed through a fabricated catchable replacement.

All verification is source-only: exact pins, forward/inverse byte transformations, patch reconstruction, direct imports and declared names. No Zig parser, compiler, formatter, metadata binary, runtime, Node capture, generator or candidate helper ran. The new C ABI requires a freshly built actual QuickJS archive under a later Root grant. No prior result qualifies these sources.

## Remaining production integration

GetReqWrap selection, async trace/admission and AfterOpenFileHandle completion still require their real request owner. That owner must compose existing FSReqPromise/request BindingData, uv_fs_open and the complete FileHandle owner/template, while retaining the exact promise and request lifetime and genuine callback Environment policies. The synchronous FSReqWrapSync branch is separate. No incomplete public binding is published here. The next assigned implementation lane is the production cwd/trust-aware runtime factory; broader fs expansion is deferred.
