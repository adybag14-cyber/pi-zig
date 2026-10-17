Source-only correction for the actual retained C3 Core v3 JSON HTTP20 failure.
Baseline d41215cdf57339b2f69f4158c2102203d6f0c177; no new execution here.

Original qualifying candidate ee6ec985acf455004f9600e0ac6e6714a1c310bf ran all
11 JSON tests: index2 HTTP20 failed at first text-stop with the genuine SDK's
missing-global-fetch error, while the other ten passed. Exact original runtime
results/stderr/stdout are copied under retained-negative and hashed alongside
their original evidence location. This negative is preserved, not overwritten
by a new result or treated as a positive observation.

The missing service is a production bootstrap gap as well as fixture setup:
runSdkFileWithEnvironment and runOwner installed timers/text/Node services but
never installed the existing native_web_fetch service. The HTTP20 fixture used
a bare Engine and installed neither fetch nor the SDK's timer dependency.

The entire code delta is four added lines in two files. Both production owners
call actual native_web_fetch.install after their existing text decoder setup.
The HTTP20 test installs actual timers and the same actual fetch service before
constructing the real OpenAI factory. Existing console/text/native IO setup is
retained. No SDK constructor fallback, custom fetch, alternate SDK, host JS
implementation, shared framing change or special-case fixture transport exists.

Actual dependency chain: native_web_fetch.install calls native_web_request
installation and actual native_web_response installation. The shared platform
prepares genuine URL/AbortController/AbortSignal/Headers/Blob/FormData/Readable
bindings and Body services, while Request installs actual TransformStream.
Fetch uses the existing native_ai_http owned worker and genuine Request/Response
objects. Production owners already install the native timers before this call.
The HTTP20 setup now does so too, providing actual setTimeout/clearTimeout for
the SDK request timeout path. No new implementation graph is fabricated.

Intentionally bare Engines remain bare. The SDK defaultFetch missing-global
branch and caller-supplied options.fetch identity/precedence remain unchanged;
neither factory.create nor Engine.init installs/polyfills these dependencies.
All HTTP20 fixtures, callbacks, full intermediate snapshots and expectations
are unchanged. Ten other JSON test bodies are unchanged. Engine/C/H and the
reviewed six genuine SDK files are protected in prepared.json.

Root will separately intake and run the actual HTTP20 JSON group before the
remaining Core continuation. This packet claims source integration only, not
compile success, an HTTP20 pass or whole-production qualification. The frozen
metadata95d worktree and old OpenAI/jiti proofs are untouched.
