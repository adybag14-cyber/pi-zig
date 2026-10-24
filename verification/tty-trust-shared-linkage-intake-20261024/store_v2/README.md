# Private ProjectTrustStore source packet

Selected production source and controls are under projected-v2. The original drafts under projected are immutable. Only the build projection under projected/build.zig is selected from that directory.

This packet implements the complete original private ProjectTrustStore class and its read, validation, ancestor lookup, update, sorted write, directory-lock acquisition, retry, and finally behavior. It requires genuine filesystem, path, path-utility, text-utility, and lockfile owners. The actual fixture supplies these existing native owners on one Engine and uses real temporary directories.

Reads acquire the same file-specific directory lock as writes. Missing files return an empty object only after acquiring that lock. Exactly ten ELOCKED attempts and nine live Date waits are retained. Errors from release replace ordinary body completion; actual native fatal completion keeps the existing fatal boundary behavior. Named imports are captured once; the default lockfile object's lockSync property remains live per attempt.

The v2 source makes the object-binding ToObject conversion once before the path and decision Gets. Its additional primitive-row control requires both strict getters to observe the same wrapper. All 36 original controls remain an exact prefix, giving 37 source declarations. Original uncaptured loop-head bindings remain live until their actual assignments, matching the retained QuickJS parser and bytecode ordering.

## Integration

Add the two selected source files and compose only the 1,054-byte build insertion. The install target is build-native-sdk-project-trust-store; the default artifact stem is test, producing test.exe and test.pdb on Windows under the batch's per-group prefix. Do not replace a newer composed build with the standalone projection.

The production authenticated trust-module assembly and shared import evaluation are a separate next slice. This packet does not publish a complete trust-manager namespace or connect createRuntime. Event emission, trust resolution, and full runtime-factory assembly remain separate original behaviors.

## Verification status

Raw source, patch, import, selected-draft, and build inverses were inspected only. No Zig parser, formatter, compiler, metadata enumeration, runtime, Node reference capture, or candidate generator was executed. Thirty-seven is the source declaration count; actual metadata and runtime results remain null.
