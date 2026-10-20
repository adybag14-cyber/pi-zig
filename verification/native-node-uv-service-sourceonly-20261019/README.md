# Shared UV service and typed FS requests

This source unit extracts the existing TCP service's Engine-thread owner into one shared Hub/FIFO/stop owner and adds actual asynchronous `uv_fs_open`, `uv_fs_read`, `uv_fs_close` requests on that service. It includes fourteen raw controls over real files, native backing leases, event ownership, cancellation and shutdown. The original twelve TCP controls remain byte-identical.

## Intake boundary

Copy only the six paths listed in `intake-manifest.json` and apply the eight-line `build-intake.patch` inside the existing `native_node_network` guard. The common UV/llhttp library, its admitted sources and its helper are unchanged. The target is `build-native-node-fs-request-transport`; its filter is `native actual FS transport`. The target only installs its artifact.

The private Read, FSReqPromise, AfterScope, FS completion Controller and FileHandle graph remain separate source work. They are deliberately absent from this intake so the raw physical boundary does not depend on unfinished guest-level assembly.

## Source review and exact preservation

VM's finite C/H review is closed on FF046966/B6F8D526/A8E758C4, including the actual rejected-open cancellation correction. Modules' finite generic service/TCP extraction review is closed on 3D1D632D/48601693. Both raw control slices and the eight-line build patch are now finite-peer closed on root 68A71CE9 / patch D579E2A8. The exact declaration manifest records the review split. No native execution has occurred.

The original packets are retained unchanged. Reversing the cancellation successor, then the allocation/admission successor, then the original C edits reproduces the entire current Main E1204E4B/F0FA0E66 pair. Reversing the nine Zig edits reproduces TCP 1DF60228. The baseline TCP12 root is retained and equals Main 3C475C5F. The common network helper remains CAECF005.

## Ownership and shutdown

A request is allocated during native construction, before init hooks and SetReturnValue. Actual asynchronous admission controls the in-flight reference, request list and counter. Every accepted request yields its actual native callback/event; a rejected admission yields none. Cancellation only touches a request whose work was accepted and remains pending.

The request keeps the actual UV request, path and native backing lease until the original cleanup cutpoint. Events hold independent native request references. An OPEN descriptor is a separate resource belonging to its consumer; freeing request bookkeeping does not close it. The control fixture accounts for unclaimed OPEN results and completed CLOSE operations even when an assertion fails.

The one service is joined before late event/endpoint/request retirement. For the later Engine composition, the real Environment must disable JavaScript before shared stop/drain, and its VM and native owners must stay alive through actual completion. Root owns the corresponding phased native-immediate and realm lifecycle integration; this unit does not substitute a queue reset or prematurely disarm pending work.

## Limits

All statements here are source-review results. The controls are authored but unexecuted. This unit does not establish public FS/TCP completeness, physical FileHandle finalizer warnings, or full Environment shutdown qualification.
