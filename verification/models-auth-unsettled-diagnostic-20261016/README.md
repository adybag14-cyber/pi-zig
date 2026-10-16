Auth69 diagnostic successor of 31200e04. The recorded native run ended with
JavaScriptPromiseUnsettled and no case identifier. CredentialStore20 and the
shared async/OOM controls passed in that run. Static auth/resolver review did
not yet establish a missing transition or a specific unresolved Promise.

Only the Auth69 test harness changes. It verifies one exact capture declaration
marker in the embedded immutable fixture, then assembles its original capture
body between synchronous enter/complete host log calls. All original work,
awaits, rows, error recording, inventory checks, golden comparisons, and
post-replay assertions remain unchanged. No Promise, scheduling tick, or guest
value clone is introduced. The original fixture and expected file remain byte
identical; production auth/resolver/store code, canonical namespaces, C, ABI,
and shared async flow are untouched.

No Zig, Node, Source, or native job was launched for this checkpoint. The next
authorized exact-head run should report the last entered case without a matching
completion before any behavioral repair is selected.
