# Selected native StreamBase read composition

This source unit composes the selected StreamResource read dispatch, the default StreamBase listener, the actual managed-buffer table, the wrapper's internal onread edge, and the genuine AsyncWrap/InternalMakeCallback path. Its eighteen controls operate on those real owners. They do not install a public FileHandle constructor or a substitute checkpoint, native trace controller, or backing allocation retry policy.

## Resulting native order

The live listener head receives allocation and read calls. A positive read increments the native byte counter before calling that head. The default allocator requests the actual uninitialized native backing before the Environment constructs uv_buf_t and inserts it into the managed table. The read callback creates the caller's real HandleScope, removes the exact native backing owner from that table, and preserves the original zero/negative/positive branches.

For a short positive read, the original native backing stays alive while the exact-sized uninitialized replacement is allocated and filled. The old backing retires at the end of that block, before the later intrinsic ArrayBuffer wrapper is created. The consuming VM adoption API receives a native duplicate entitlement so the original local can remain owned until an actual failed intrinsic result plus a fresh OOM occurrence has selected the genuine terminal heap owner. This does not allocate an earlier wrapper or copy bytes during adoption.

CallJSOnread writes the shared signed read count/error field and array-buffer offset in original order, obtains the actual virtual AsyncWrap, then reads the wrapper's internal onread edge. It applies the actual native IsFunction CHECK and passes the one original buffer argument to AsyncWrap MakeCallback. The public property called onread is not used for this internal lookup.

The AsyncWrap helper invokes the required native before trace operation, snapshots provider and async context, and calls the existing InternalMakeCallback owner using genuine resource/receiver/frame handles. The completed native result remains owned through the after trace operation. After the callback it uses only the snapshots; the callback may already have deleted its native StreamBase/State. The enclosing caller HandleScope retains its selected callback, ArrayBuffer and ignored result through the original teardown order.

## Concrete files and source evidence

- `native_node_async_wrap_make_callback.zig`: AE550CB8, caller-scope result and native trace composition.
- `native_node_stream_base.zig`: 0A3F4EB5, selected default allocation/read and internal onread call.
- `native_node_stream_resource.zig`: 6CA4CF5C, four exact changes adding native read dispatch to the already reviewed Resource owner.
- `native_node_stream_read_test.zig`: E82BD953, eighteen actual controls. The API-only three-site correction from CB3263C5 is retained with its exact preimage and inverse packet.

The original selected bodies and full-file pins are in `stream-read-composition-draft.json`. Both complete production/control peer slices and the install-only build peer are retained under `peers/`. The current status is recorded in `stream-read-intake.json`; earlier draft records remain unchanged as history.

## Required graph before compilation and installation

This unit depends on StreamFields10, the native backing token/adoption ABI, the shared standard allocator and managed-buffer table, the six shared Int32 alias edits, and the ten proposed Environment managed-table edits. Root must compose the Environment packets at their exact real owner. The source unit does not overwrite the worktree's Environment dependency copy into Main.

Allocation and trace are required native operations with no fallback implementation. The test allocator covers first-attempt success through the actual VM primitive and fails honestly on an unexpected native outcome; it does not qualify the original GC/retry/default-fatal policy. Trace callbacks in the controls observe ordering and ownership; they do not qualify category admission, trace output, controller, or writer lifecycle. The controls use a real outer callback scope with skip_task_queues for the deliberately unselected checkpoint/hook composition.

The public onread accessor remains a distinct native FunctionTemplate prerequisite. `lazy-accessor-source-prerequisite.json` records the actual normal Get/Set versus descriptor-materialization branches; eager JS getter/setter allocation is not substituted for them. Full FileHandle ReadStart/ReadWrap, constructor, shutdown, warning scheduling and Node bootstrap are separate work.

The build proposal adds fifteen install-only lines and a separate exact uv include for the existing Resource8 root, reusing the one network graph. No Main/build mutation or compiler, test, Node, formatter, or generator execution occurred in this source unit.
