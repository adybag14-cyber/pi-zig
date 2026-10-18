# Actual xAI OAuth bodies

This source unit ports the pinned c268154c xAI provider into Zig with the linked
C runtime. It is source work, not live-account, network, application or release
qualification.

## Authority

The exact Git TypeScript, accepted JavaScript and source map are retained under
xai-authority/. The TypeScript is identical to the source map's sourcesContent.
The Source test fixture changes only the sole DeviceCode import. Its dependency
is the actual retained Source DeviceCode implementation in the same C VM.

- TypeScript: D78BC70B7031326D51BF1348266FCD576E77590CEEFDEA9A4ED962E403444A78
- Accepted JavaScript: D34783560DC2AC75D6E717B248136EB75A902FBD53B3E56FB9F2EC50C6C793D7
- Source map: 8F291CF2E40E94D450D8046F8384BD510A1DCAAF064CEC09913CF1A4EE01A573
- Fixture: 73ED40E20DA005A6D9F3051665F695351927E99346A68E247CD9E1630258C012

## Actual implementation

postForm has its two Source Awaits, its named fetch catch and separate empty JSON
catch. The final response getters remain outside both catches. The parser keeps
live property lookup and validation order, including HTTPS-only verification and
optional fields. Request failure invokes the live filter(Boolean).join sequence.

Device requests and token refresh each have one Await. The polling wrapper has
zero Awaits and adopts the real DeviceCode helper. Its retained polling arrow has
one Await. Login has one Await, notifies, then returns/adopts the polling body.
The public refresh property is an ordinary two-argument arrow: a throwing refresh
getter throws synchronously. toAuth is a genuine zero-Await method that preserves
the access value's identity.

Request construction completes the init argument before entering guest fetch.
The headers/body have no extra expression roots when guest code deletes their
properties. Boolean predicate results retire at their condition. Constructors,
Date call operands, filter receivers and catch locals follow the inspected Source
lifetime with AF33/C435 completion boundaries. No production JavaScript body is
embedded or evaluated by this provider implementation.

## Controls and review

Install-only target: build-native-ai-oauth-xai-genuine-af.
Artifact: native-ai-oauth-xai-genuine-af.exe on Windows.
Root: src/native_ai_oauth_xai_genuine_af_test.zig.

There are 16 declared controls. The observer runs actual Source/native comparisons
for 41 login and 18 refresh routes with controlled fetch, URL and timer surfaces.
These are comparisons of actual execution results and operation traces, not
handwritten successful snapshots. Additional controls use real C holder retirement
for request child roots, finite predicate values, URL and Date operands, filter
arguments, empty/named catches and parsed locals, plus actual DATA/fatal behavior.

Production 5B2139CC2BAB5103770B654E756F95165F9EAD1890A541D5DACB9B356A474161
has completed the finite SDK common-body and VM async-body reviews.
Root controls55880AD8, supportF1EA123E, observerBEE9F078 and Source73ED40E2
have completed the split finite control reviews. No build, metadata, runtime or
whole-application acceptance is claimed by those reviews.

The request-child lifetime counterexample was also corrected in Kimi and Meta.
Both finite predicates now return immediate booleans from a completed helper
scope. All prior controls are retained, with two added controls per provider
(Kimi12 declarations; Meta15). The request-root controls distinguish both old
implementations, and the Kimi finite control distinguishes its old helper. The
Meta finite control records contract coverage: its previous nested positiveProperty
scope already retired that value before the next property evaluation. Prior
compile observations remain tied to their original source and do not transfer
to these successors. The combined source must be built, queried and separately run.
