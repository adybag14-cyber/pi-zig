# InitialModel guest-operation adoption

Source-only successor to the existing actual c268154c findInitialModel body. The body and its existing actual-owner controls are unchanged. This unit changes the resolver-local value adapter to use the shared AF33 SDK Boundary for property reads, ToPropertyKey, iterator symbol, calls, definitions, binary operators and coercion. The existing nested invokeOwned scope remains intact.

Only raw JS_New* / JS_ThrowTypeError operations use an allocation-generation span. The adapter checks actual pending/current completion before root storage or retirement and marks only a genuine fresh native allocation reason in that non-guest span. Direct property definitions no longer blanket-mark pending reasons as fatal.

Dependencies: native_sdk_guest_operation.zig SHA AF33D462D6B1573DB869E5F583A289EA105B6C1CF910948E418FBE85834DBD8C; native_sdk_owned_completion.zig SHA C4354FAE45DB2C30E64EC8161C3F9E5EE7C27D73C3DB53F8ED4E79515368E04F. Neither shared file changes here.

The previous adapter bytes are preserved in initial-model-values-before-guest-adoption.zig.txt. Existing source controls include same-operation successful private DATA A, actual B1, historical diagnostic DATA, pending entry and genuine native holder retirement. They require the actual application owner; they have not been compiled or run for this successor. No Source, runtime or production qualification is claimed.
