# Native SDK provider callbacks and tool image normalization

The implementation at `cd0d9a781ddb582c21fc71562392a14eab34ec74` ports
these original Pi 1.2 components into Zig through the QuickJS and linked C codec
interfaces:

- Provider attribution and install telemetry, including live header merges,
  hostname handling, symbols and guest exception identities: 96 Source cases.
- SDK factory request options, captured header runners, live payload/context/
  response/stream hooks, cache decision promises and transcript-prefix closures:
  24 Source cases over actual native Agent, SettingsManager, SessionManager and
  CacheWarmer collaborators.
- Image MIME normalization, PNG conversion, native resize workers, conversion
  and dimension hints, tool-result identity, live getters and iterator closing:
  36 Source cases, including byte-exact resized PNG output and promise ordering.

Source captures execute the original latest upstream modules and codec
implementations, with caller-owned inputs. The factory capture observes the
incoming context closure and calls the original installer once with unchanged
receiver and arguments. It does not replace or skip the original method body.

Local Windows Debug and ReleaseSafe each passed all 21 selected tests. Those
runs include explicit collection, retained callback and byte graphs, rejection
identity and exhaustive native allocation-failure checks. All 4,689 committed
source blobs match the successful ReleaseSafe input bytes. Full source and
19,546 compiler-file posthashes show zero drift. Original Source/runtime/tool
posthashes cover 1,945, 31,064 and 1,774 files, respectively, with zero drift.

The accompanying workflow compiles the three artifacts separately, preserves
the 120-second per-test and 10-second VM await guards, and requires all selected
tests in both modes on Windows, Linux and macOS. Hosted qualification is pending
until that exact-commit matrix finishes.

These callbacks are private dependencies for the complete native session
factory. The fixture adapter is test input and assembles actual native
collaborators without activating the public factory. The full AgentSession
constructor, loadout, lifecycle and remaining integration work must still pass
before removing the implementation bridge or claiming complete Pi parity.
