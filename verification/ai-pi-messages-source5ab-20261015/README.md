# Native Pi messages candidate

The original oracle ran `packages/ai/src/api/pi-messages.ts` from immutable Pi
Source `5ab7fe74c400097b386662205cd93900695b8a71` on actual Node 24.14.0. The
22 controls comprise 18 supplied-fetch cases and four real owned-loopback HTTP
cases with placeholder credentials. The committed fixture
`src/extensions/fixtures/ai-pi-messages-5ab.json` is the verbatim capture output.
No provider implementation was replaced during the oracle.

The owned process PID 51072 completed with exit 0. Pre/post checks verified all
1,967 latest Source files, 31,064 durable dependency files, 1,774 Node/tool files,
the capture controls, and the 84 historical absent dependency paths without
drift. The observed-module trace is retained alongside the launch receipt and
posthash. Stack strings and numeric `durationMs` values are normalized only when
the respective property exists. Tests also check mutable partial identity and
terminal identity live before serializing snapshots.

The native candidate returns the shared `AssistantMessageEventStream` from
native C ABI functions. It passes the caller's transcript through unchanged,
awaits all three provider hooks, and decodes Pi's own sparse text/thinking/tool
events. Default HTTP uses the common owned worker in byte mode; supplied fetch
uses native async continuations over the supplied response reader. Its SSE
parser retains the first data line, exact `[DONE]` rule, CRLF behavior, and final
unterminated frame. HTTP errors preserve the status phrase and structured
diagnostic details.

Native compilation and runtime qualification are pending the coordinated
resource grant. The source capture is evidence of the original controls only.
The complete native factory, complete Pi application, publication, and public
activation remain unqualified/inactive.
