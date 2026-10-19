# Actual Node filesystem path helpers

Status: source authored. This unit has not run a build, native metadata, Node Source capture or runtime.

## Production change

The genuine internal/fs/utils owner now provides getOptions, assertEncoding and the hidden validatePath wrapper. getOptions retains its actual options/default parameter owners, copies the caller's default object through interleaved own-key/descriptor/get operations, uses ordinary encoding assignment and observes each encoding/signal getter at its separate Source expression. assertEncoding calls the live method on the retained actual Buffer object. validatePath uses the linked runtime's genuine Uint8Array type check and retained String/TypedArray includes functions, followed by the live HideStackFramesError member on the retained genuine Node base constructor. The complete constructor call retires before its returned reason reaches the Source throw.

The bootstrap obtains the same completed argument graph from e74d7915 (Root intake 9e253323), the actual process/Stream/node:buffer graph, one frozen null-prototype internal/util kEmptyObject and the existing realpathCacheKey Symbol. A completed reentrant winner is selected before the losing candidate retires. No public filesystem namespace or replacement import handler is published by this helper unit.

These source changes prepare the actual classic realpath entry. The component walk, URL conversion, followed native status and final encoding composition remain separate work; this unit does not claim filesystem or roadmap completion.

## Authority

authority/fs_utils.js.txt is the exact retained Node v24.13.0 internal/fs/utils.js, raw SHA-256 D8D4D3A3F2A7FF89F14366C9ED02E379FD09351A9A1781D1D552875CC80BFCE7. The selected internal/util excerpt retains its URL, complete-file hash EBD5E67C4B31E484B157239F7A7E38CBE29F175AFB53D2B95E19ACC2520D43B5 and byte/character offsets. It identifies itself as an excerpt, not a complete source file. The actual initializer is ObjectFreeze({ __proto__: null }).

The complete relevant Node and Joyent MIT grants are retained in authority/NODE-SOURCE-LICENSE.txt.

## Declared controls

- Build target: build-native-node-fs-path-helpers
- Root: src/native_node_fs_path_helpers_test.zig
- Filter: native actual fs path
- Installed Windows artifact: native-node-fs-path-helpers.exe
- Eighteen authored declarations: twelve shared Source/native observers and six native controls.

The shared observers cover default identity, null prototype/freeze, spread own-key/descriptor/get order, ordinary assignment setters, repeated options reads, the live Buffer receiver and predicate, the second AbortSignal operand, ordinary reason identity, hidden/raw function shapes, actual view brands/null bytes and retained original includes functions. The invalid-view and null-byte observers also replace each actual base class's hidden-constructor member, observe its getter and selected construction, and check a later getter's exact ordinary thrown value. Native controls add completed-owner identity, a genuine sole-holder finalizer before the second encoding read, that finalizer's actual allocation fatal stopping all later guest progress, ordinary private DATA, successful flagged DATA and a real detached Uint8Array.

The fixture installs real timers, native_process and native_node_os/Stream with std.testing.io. It does not read stdin, perform filesystem IO or spawn a process.

## Review and execution boundary

VM's finite bootstrap/empty-object/key publication peer is closed on 0C9C0C38, 4BD028DC and 08798135, relying on the stated bootstrap-before-guest timing. VM also closed the original fixture/finalizer and first three native controls at C87DC849. Root read observers 1–6 against the genuine fs_utils authority and found no concrete blocker; formal closure is pending. SDK's helper/spread/remaining-control peer identified the live hidden-constructor lookup. SDK closed its correction and the extended observer slice on D5612CB7, 6704C87C and 05A417F7; the original getOptions/spread and observer 7–12/native DATA review remains limited to the previously read bytes. Static whitespace checks and source peers are not compiler or runtime results.

node-source-observer.mjs is an authored entrypoint for pinned Node v24.13.0 with --expose-internals. It consumes the actual internal/fs/utils and internal/util exports and the actual Buffer owner. Root must separately grant and seal any Source invocation. Native build, metadata and runtime qualification likewise remain Root-owned. The Node builtin behavior is the actual pinned Node/V8 reference; a diagnostic draft following an incorrect linked-compiler live-concat behavior is not authority for this unit.
