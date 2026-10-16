Actual Models compound native gate: strict runtime negative retained
==================================================================

Candidate c22af0996a4ec032a0c244b91b2c2eac162a0fcc compiled155/155steps.
Actual Zig0.16 metadata contains exactly the15 intended named tests and
extensions.native_durable_storage.test_0. The artifact is61,704,192bytes,
SHA256451DD450F0682FE2F4366834E705CA7C0FF84B394FBF6D111817365E8AB6917F.
It is retained unchanged both in the cache path recorded by metadata and
the independent evidence copy recorded in retained-artifact.json.

Runtime was11pass/5fail, not a qualified compound gate. All259 original
observations and assertions remain unchanged. The five failures are:

1. Class Source18 row5, query push lookup precedes provider callback:
   one additional observable Array.prototype.push getter in native output.
2. Auth Source69: JavaScriptPromiseUnsettled, no diagnostic/current case yet.
3. Refresh Source60 row17, phase-publish-live-provider-id: native generic
   TypeError message versus Source's this.modelsStore.read expression label.
4. Complete refresh host-allocation sweep: healthy baseline reported300
   allocation positions, then JavaScriptPromiseUnsettled during an induced
   failure. The baseline is not an allocation-sweep pass.
5. Factory Source92 row18, azureProvider: native deepseek-v4-pro precedes
   Azure response models; Source concatenates that model after them.

The first stack for all observation failures reaches Engine.awaitValueImpl,
Engine.awaitValue, Engine.evalModule and the respective strict replay test.
The full runtime stderr retains actual/source rows and complete stacks.

Credential Source20, queued publication GC, three shared recorder OOM/guest
cases, five rejected-allocation identity cases and the imported anonymous
declaration passed. No broader Models/auth/refresh/factory parity is claimed.

Every before/between/final file hash, complete path inventory, vendor1316,
compiler19546, original Source1970/runtime31064/Node1774, candidate,
controls, ten fixture pins,84absences and exact artifact had zero drift.
Compile73868, metadata68296 and runtime70784 independently disappeared;
their remaining descendants and the global Zig/build/test inventory were
empty at final release. The Root serial lease is released. No further
Zig, Node or native launch is authorized without a new Root grant.
