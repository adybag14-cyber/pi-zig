# Pi messages bounded native qualification

Exact code head `051d921bbcd1aeff34cd6db21af73ad274d7920a` passed the native
compile/runtime pair in Windows x86_64 Debug with pinned Zig 0.16.0. The runtime
reported **5/5 tests passed**, covering all original Source22 controls, arrow/GC
behavior and the complete induced host-allocation probe. Both posthashes retain
zero drift across candidate 6,109 / vendor 1,316 / compiler 19,546 / controls 4,
with the exact code head unchanged. No shared C async-generator repair was
intaken or needed for these controls.

The original Source22 artifact and snapshots were not changed. Stack strings
and numeric duration values are normalized only when present. Partial message
and terminal aliases are checked before snapshots. The default-wire controls
check the original requests' parsed body and selected functional headers at
the original paths. A separate supplemental capture and comparison audit will
strengthen explicit request-method and origin-only URL binding; that later work
does not enlarge this receipt's scope retroactively.

Negative receipts are retained. They identified the test helper's missing
filename sentinel, incomplete native TextDecoder composition, error property
ordering, and a pre-provider TextEncoder host-allocation failure whose private
origin tag was absent. The TextEncoder correction uses the existing engine OOM
identity path and preserves the public Error class/message. It does not treat
user exceptions or OOM text lookalikes as host allocation failures.

The exhaustive probe includes native fixture byte encoding, actual provider
request/hook/event state, decoder allocations, queue publication and GC. It does
not inject failures into the raw worker's separate page allocator. See the
machine-readable scope in `qualification.json`.

This is a bounded provider component qualification. Other platforms/modes,
the new image/classifier candidates, complete provider/factory/application
assembly, publication and public activation remain unqualified or inactive.
