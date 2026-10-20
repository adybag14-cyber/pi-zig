# V24 inspect color fixture ownership correction

The original V24 stderr (10906A1A) and full original root (9AC177CE) remain unchanged beside the exact source delta. Both failures reported an expected JavaScriptException but a successful void result; the original evidence did not identify the native or literal Source iteration.

The two actual fatal producers deliberately consumed their pending exception. Only the native stylizer already had an enclosing Node boundary; the literal Source route had no native invocation to retain the event. The Engine's allocation tracker is diagnostic DATA and cannot restore an event that the fixture removed.

Each producer now enters its own caller-stable NativeInvocation before the genuine fatal producer. The original GetException/free challenge remains. The raw callback returns the actual leaveNativeInvocation result; the void finalizer retires only that returned immediate after the selected reason has been republished. All 15 names, both modes, identity/generation/retirement assertions, and no-later-guest assertions remain exact.

VM closed this two-block ownership correction on DC8C7F14D874CDAE724889661FFDDEA4E018157C60E252437CCACE66211B77DB (12,547 bytes), and verified exact reversal to the retained Main root. No production colors or observer code changes.

A separate concrete VM issue remains: sealed OP_get_array_el and OP_get_field can release the receiver and continue without checking an exception created by that finalizer. VM independently confirmed that issue and owns its separate C/control successor. This fixture commit does not claim that the Source retirement oracle now passes.

No compiler, native, Node, generator, formatter, AST, or test execution was performed. Source-only correction and peer closure are not runtime qualification.
