# Genuine OAuth device-code source unit

This unit replaces the previous manual polling continuation with the actual c268 async declaration and preserves abortableSleep as an ordinary constructible Promise producer.

The accepted runtime JavaScript is copied byte-for-byte for differential controls. Its source-map content equals the frozen c268 TypeScript Git blob; the license and source hashes are retained in source-authority.json. No Node capture, source generator, native build, metadata query or runtime test is claimed by this source commit.

The implementation preserves the live global Promise constructor used by sleep, its two arrow callbacks, timeout temporal dead zone, signal callback order, and synchronous constructor behavior. Polling uses the genuine resumable AsyncFunction actor for exactly the first-wait, poll and loop-sleep Await edges. Error objects returned successfully by a guest constructor travel as ordinary throw/reject values. Current native fatal events use the canonical guest and cleanup boundaries.

Declared controls compare 16 real poll routes and seven sleep routes against the preserved Source, check function metadata and zero-Await state, exercise actual private DATA and current native fatal producers, retain options/result values across held Awaits, and use actual C native holder finalizers to observe status and replaced-interval retirement.

The first finite production review identified an old interval root spanning its reassignment. The corrected helper reads that binding inside its local expression and retires it before the following Date.now. Controls explicitly cover that point.

The install-only target is build-native-ai-oauth-device-code-genuine-af. It declares 11 named tests; the real compiler metadata must determine the complete execution list. Full application/provider acceptance remains incomplete.
