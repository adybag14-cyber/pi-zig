# Native ordinary session input, commands and skills

Implementation f157fa89d30aaee8b27846f9c773dbdb62c95892 ports the original
_runInputHandlers, _tryExecuteExtensionCommand and _expandSkillCommand methods
over ordinary live AgentSession fields. Runner replacement, command receiver,
context creation, asynchronous interception, error emission and original
thrown-object identities follow the Source access order. Known skill files use
the native filesystem and frontmatter parser, with live template-literal
getters and the current runner's skill-expansion error handler.

The e6220e1 fixture contains 35 cases captured through 35 genuine upstream
createAgentSession calls. It checks method descriptors, repeated getters,
thenables, nullish transformed images, handler/context failure boundaries,
ambient String invocation, real skill files and read-error routing. The first
32-case comparator negative is retained: V8 and QuickJS use different built-in
null-property TypeError prose. The observer checks the TypeError category;
separate identity checks and application-generated error messages stay exact.

Windows Debug and ReleaseSafe each passed all 11 selected tests, including
explicit receiver/context collection and all native allocation failures in
the input/command/real-skill-read graph. Runtime limits remain 120 seconds per
test, 10000 ms per host await and 300 seconds outer. Cold ReleaseSafe compilation
has its own 1320 second envelope. Native source/compiler posthashes show zero
drift. All 4762 committed input blobs match the ReleaseSafe snapshot; the extra
file over Debug is a retained, unrelated constructor CI negative log.

Original source, installed runtime and Node posthashes show zero drift over
1945, 31064 and 1774 files. The actual skill file digest and full receipts are
retained in verification/sdk-prompt-handlers-e6220e1-20261013.

The private Windows/Linux/macOS candidate runs the same artifact in both modes;
hosted qualification is pending. Full public prompt execution, runtime binding,
session lifecycle and the complete Pi application still require integration.
This component does not activate the partial class or remove the compatibility
bridge.
