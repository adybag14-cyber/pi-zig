# Native SDK project trust path, resource and option suppliers

This packet implements the complete bounded path/resource/options portion of the retained coding-agent trust-manager source and connects its creation to the genuine private SDK application owner. It does not publish a trust store, choose project policy, or fabricate a complete Main runtime factory.

## Selected sources

The new native_sdk_project_trust_paths.zig owns the original eight-name project-resource array and the imported filesystem/path/OS/path-utility functions for one Engine evaluation. Its ordinary function exports are getProjectTrustParentPath, getProjectTrustOptions and hasTrustRequiringProjectResources. A private cache retains the evaluation and verifies the same genuine module identities on reuse. Cold reentry cannot observe a partial cache.

The application-owner successor adds createProjectTrustPaths and its native entry/body only. It authenticates the existing captured application owner, roots its actual runtime-import graph before any guest-capable property access, then obtains the real filesystem, path, pathUtilities, node:os and CONFIG_DIR_NAME providers. No borrowed host owner field is accessed after those Gets can reenter.

## Original observable behavior

Path normalization calls the real imported resolvePath and canonicalizePath. Option creation repeats normalization for the parent path, preserves fresh arrays/rows and property order, evaluates includeSessionOnly twice, and performs ordinary Array.push lookup/calls. The original mutable module resource array remains observable to a guest-replaced Array.some implementation, including mutations and a retained predicate callback.

Resource detection reads live process.env.HOME before normalization and calls the captured homedir fallback only for a falsy HOME. It probes the exact eight configuration entries in order, then each .agents/skills directory from cwd through ancestors, skipping the canonical user-home skills path without a filesystem probe. It does not inspect ancestor .pi directories or add packages.json, npm, or git policy.

All guest values use existing charged/traced native function captures, native public-value scopes and the SDK source-local Frame owner. Assignment and retirement preserve pending completions, escaped callbacks and reentry. Cache publication happens only after complete construction, local retirement and export acquisition.

## Source controls and build

Twenty-two actual-VM controls cover genuine modules and temporary disk paths; exact options and Get order; repeated normalization with a changed cwd; root handling; canonicalization; all eight resource entries; ancestor/home exclusions; captured imports; escaped predicates and private-array mutation; thrown identity; pending completion; cold creation reentry; retired application owners; allocator failure; and ordinary push/property behavior. They use existing real native process, filesystem, path, OS, Source path utilities and Engine owners.

The additive 1,054-byte build insertion creates one install-only target, build-native-sdk-project-trust-paths, filtered by native project trust paths. It uses the existing actual SDK owner link dependencies. It adds no execution step. Compose this insertion with newer build files instead of replacing unrelated later additions.

## Reviewable evidence

source-diff.patch reconstructs exactly four selected targets. application-owner-source-inverse.json records the two additive owner insertions. build-source-inverse.json records the one additive build insertion. static-source-checks.json records all 43 relative import occurrences, two standard package imports, 22 unique declarations and limited source-name checks. These checks are textual checks, not a Zig parse or compilation.

The application-owner donor was captured on 7947d3a0 and remains byte-identical on the current a2261329 baseline; both snapshots remain immutable. The build donor is the actual a2261329 build. Current C/header and provider pins are dependencies only; this packet adds no ABI.

## Remaining integration

The original ProjectTrustStore file/lock/read/write owner, emitProjectTrustEvent snapshot/await/error behavior, and resolveProjectTrust event/store/default/UI precedence remain separate missing suppliers. Main createRuntime must then retain its genuine captured CLI/startup/trust/model/session collaborators and observable construction order. The existing native coding_agent/trust.zig differs from the retained Source semantics and is not selected as a substitute.

This packet has not run a Zig parser, formatter, compiler, metadata query, runtime test, Node capture or source generator. Main and all predecessor packets remain unchanged. Twenty-two is the number of declared controls, not an observed metadata or passing-test count.
