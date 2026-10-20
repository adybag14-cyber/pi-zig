# StreamFields native wrapper ownership

This finite source unit adds the actual FileHandle wrapper's internal onread value and native StreamBase slot to the existing Registry/State owner. The wrapper owns one traced onread edge and a native Registry entitlement. Native State retirement clears the State/StreamBase slots while the JavaScript wrapper can retain its onread value. Native State retirement clears its slot before derived cleanup can reenter wrapper retirement. The wrapper finalizer then clears opaque metadata and retires the onread edge before releasing its native fields and Registry entitlement; the Environment stays alive through that cleanup.

The original strong native wrapper root and independent context-frame root remain external roots. This unit does not turn them into traced wrapper edges. The actual prior-pending gate runs before native StreamFields allocation; the native fields attach before the genuine VM allocation result is reduced, so allocation failure retires the attached owner exactly once.

## Exact source changes

- Production: `src/extensions/native_node_async_wrap_state.zig`, SHA-256 `4912FF07128124D77D896B9E1271A5F6D7D8F3323C90DE7B718735B94E137C25`.
- Ten controls: `src/native_node_stream_wrapper_test.zig`, SHA-256 `8DBFA1F6946ACFBDC32186EFFC440A8F6CDD47A16838DCE40C7BED73D034C8B9`.
- The nine exact production replacements are in `stream-wrapper-fields-delta.json`. The subsequent two-position prior-pending-gate movement is in `stream-wrapper-admission-successor.json`. Reversing the successor then the original nine replacements returns the complete retained B53C4D0C source.
- `stream-wrapper-fields-source.json` retains the selected original wrapper allocation, internal-field, StreamBase and BaseObject bodies, with full-file hashes and bounded source ranges.

## Control scope

The controls exercise internal default undefined and native slots, traced onread reachability, replacement-before-retirement reentry, native detachment with retained onread, the external strong native wrapper cycle, weak finalization order, real realm cleanup, late wrapper retirement, prior-pending allocation admission and actual VM allocation rollback. They use the genuine Registry, State, Environment, VM and GC. Hook, checkpoint and native CHECK operations that are outside this selected slice are explicit unselected operations; their success is not asserted.

VM and Modules independently closed their production and control slices. Their retained receipts are under `peers/`. The install-only build proposal is `stream-fields-build-intake.json`; it adds one ten-control root using the existing network and Engine dependency graph. This worktree has not modified the shared build or Main.

## Deliberate boundaries

This unit supplies the internal wrapper owner, not a public FileHandle constructor or public onread accessor. The original accessor uses lazy FunctionTemplate components, and its separate VM materialization/signature owner is required before public assembly. It also does not qualify StreamBase allocation/read operations, backing allocation retry/GC policy, trace emission, or complete Node bootstrap/lifecycle integration.

No compiler, test, Node process, generator or formatter was run for this unit. Source review and exact forward/inverse/readback checks are not runtime qualification.
