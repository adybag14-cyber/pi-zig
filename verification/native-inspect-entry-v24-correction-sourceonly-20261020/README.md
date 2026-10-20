# V24 inspect-entry fatal producer ownership correction

Status: source only. No native build, runtime, Node, generator or formatter was run.

The V24 diagnostic reached the JSON fatal control's existing no-later-guest assertion. The original raw probe created a genuine native fatal, deliberately took and freed its pending exception, and returned successful undefined. An enclosing native owner could restore the event later, after the guest toJSON body had already continued.

This unit changes only that raw producer. A caller-stable NativeInvocation starts immediately before the genuine producer, retains its actual event across the unchanged GetException/free challenge, and returns the actual invocation-leave result. No retained diagnostic allocation value is treated as a new event.

All 37 declarations, exact reason identity and generation assertions, no-later-guest/no-guest-catch assertions, successful DATA producers and typed-holder finalizers are unchanged. The complete original Main root and runtime stderr are retained. The one exact inverse replacement restores Main A465E66D byte for byte.

VM Foundation closed the complete changed function and its ownership on successor 690B098C / packet EDB6D3FC. Production formatter F40A4D0C is unchanged. The separately proposed VM receiver-retirement correction is not part of this unit.

Root intake should apply the one replacement to the retained Main control root, verify the complete successor hash, and retain the existing build target. The SDK branch did not previously contain this later inspector control root; the full successor file is included solely as the exact Main-based artifact. No formatter implementation or new test assertions are bundled.
