# Public ExtensionRunner constructor Source564

The original production constructor capture contains thirteen cases over all 34 own fields, five supplied references, full shared prototype order, constructor descriptors, six alternate newTarget shapes and traps, subclass field definitions, borrowed default arrow callbacks, and async callback results. Original runner TypeScript SHA256 is `2A3BD7F81623928070EB956CDAC37B861A787297046F9CE7AF0522FF6D41A98A`.

Source execution passed with Node 24.14.0, a 64 MiB heap and a 30 second owned deadline. All 25,038 prefrozen inputs and 1,473 actual default-loader module source hashes remained exact. The original output SHA256 is `23187AFB2EC285D859B4BDAD79D6F65C214004B20075C027441BC503FF7BA946`; the observed closure SHA256 is `6A76CD5367A9D4303989938081FBDFC44B747EC1F2B26E8439BFCE09A6A9D3D6`.

The native candidate gives waitForIdleFn, newSessionHandler, forkHandler, navigateTreeHandler, switchSessionHandler and reloadHandler genuine async function prototypes. A constructor whose newTarget.prototype is not an object uses the realm's intrinsic Object.prototype through JS_NewObject, preserving ordinary getter/trap behavior and avoiding mutable global Object lookup. All field definitions still use actual own data properties.

Ten complete rows compare exactly. Three engine-generated TypeError diagnostics retain the original text in the immutable capture and compare their class, exact row structure and nonempty message rather than V8-specific wording. This is an explicit diagnostic wording limit.

Status: Source qualified; native candidate uncompiled. The cumulative gate must contain 36 actual tests: 28 named queue tests and eight imports, retaining every prior assertion. Full SDK parity remains incomplete: factory-owned runner construction and service bridges, AgentSession private state, retry/compaction and global lexical semantics require further original Source evidence and real implementations. Retain the Node bridge.
