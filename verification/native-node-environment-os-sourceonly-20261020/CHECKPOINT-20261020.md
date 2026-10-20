# Modules / I/O source checkpoint — 2026-10-20

No native/Zig/AST/Node/generator/formatter execution occurred. Main and shared Engine/process/QuickJS files were not changed.

## Sealed handoff

Path15 commit: f172af550619d6c6451f6216612d5990e2c8202c (18 exact paths), following Map22 78b8ddf58c9b101a2afd4948ff2ed8f1ded7de63.
Final manifest: native-path-final-manifest.json 1DA7E3AE6D4289ED77EA80A71C59FD06E0C77F071F005DC16A704913590F3D1D.
Path15 source/control/build peers remain closed. Root stack operations and actual Environment installation are separate.

## Newly closed reciprocal peers

- StreamBase18 assigned controls 1–6, 8, 12, 17–18 and helpers, current root E82BD953 / production0A3F / build4C98. Receipt ../native-stream-read-source-peer-20261020/controls-build-receipt.json BB37DB501FD85A96DA54D048E055884D40C659D5625C1BC7CED5DB4FEE65B438.
- StreamFields10 install-only build1FCC74E5 / root8DBF. Receipt ../native-stream-fields-source-peer-20261020/build-receipt.json D3C78B3785E738743730DF837A75BAA52A1880C16AD719C0428BBDB3D6484F6B. SDK sealed this owner as76081364 and Managed12 as7c7e4f07. StreamBase18 is now sealed9c1d897a596a1adeb1498ac0099612f6f527dfb7, manifest31CC4A1E.
- Earlier StreamBase production slice remains receipt0061094E; VM's separate owner/controls review is not replaced.

## Native Permission core draft

Source is written but uncommitted and not closed:
- src/extensions/native_node_permission.cpp:40553FFA8D674EF8893631F6CB2726713858D61B7D4C2CDA89A10F006CDD518D,15177 bytes.
- src/extensions/native_node_permission_internal.hpp:360B921E6E0A38096E739857C78E1F7B620415E6472CAE3D8E65D20B1C852E41,11310 bytes.
- src/extensions/native_node_permission.h:6005CBF37A2FA4A6BF310274AB8338F030E886AAA1461EEC95FED2019E3E3C9B,3314 bytes.
- native-permission-core-draft.json:998B8AF6ACC4640C1A6E9838BB1234D51E848E1DB265AEA2A745B7B6A74282D5.

The core retains all original Permission scope/constructor/Apply/granted and FS radix decisions. Actual shared_ptr/unordered_map/String/vector implementations use the same stateless native allocator. Six policy allocations/eight map insertions follow the original order. Debug is an explicit required borrowed native dependency; no false/noop default is supplied. SDK's bounded algorithm review is closed at6BDA1DAD (11432 bytes), copied unchanged to peers/permission-algorithm-peer.json. VM's placement/native-owner review is closed atDCDA6816 (23555 bytes), copied unchanged to peers/permission-owner-peer.json. Both explicitly exclude the two cleanup defects, Debug integration, controls/build and execution.

The original successful-directory Windows stat request leak and nonterminal-wildcard subtree leak remain in the current draft. SDK independently proved no compensating owner. Complete proof: authority/fs-permission-cleanup-source-peer.json522698C721CBB6328A6CE48DFDE53B6012FFC29E7CFE6F13BDC8AFB4C48E0074.

## Concrete cleanup proposal awaiting Root decision

permission-cleanup-adaptation-proposal-v2.json328ADA249564A2FDA30B6508A93BC0915B0E1B9D4883280724F03434B236716D.
Two behavioral edits:
1. Construct the original wildcard result, then clean the successful-directory request before returning it; preserve failed/non-directory cleanup-before-copy.
2. Recursively free the actual wildcard subtree before deleting its parent.
Two comment edits explicitly identify the native adaptation.
Proposed CPP4DC0D4C70A659B9405E6D4AC6BFC0B008FB48EFB614F811C87F096A105A73EC8 / internalC15AC7ED37DAFB8F672AAFCFCD6FABA2CF87BB64EE26C8CC4AF5A6695D2E712F.
It is not applied. Original draft preimages and earlier proposal44EF44B2 are preserved. These extra releases cannot be called original Source-body equivalence.

## Debug prerequisite

authority/permission-debug-and-policies-source.json56F9E027AFDBD749280A15BFB776E01C36E2F0F43D3F6F308F9A74CAB06F05CD retains13 complete immutable originals.
PERMISSION_MODEL uses per_process EnabledDebugList, distinct from trace_events:
SafeGetenv NODE_DEBUG_NATIVE, original substring category parser, live enabled checks, actual SPrintF/FWrite and Windows console conversion.
Actual per-process debug owner and formatting remain uninstalled. Root was asked whether to assign this separate owner here or supply it from its lane.
Pinned libc++ shared_ptr.h3241AF29 is retained; actual make_shared delegates to allocate_shared and normal allocator_traits construction value-initializes the five deny_all_ fields.

## process.env VM prerequisites

- process-env-exotic-flags-prerequisite.jsonC9901F29: query-only enumerable filtering needs a distinct native input from full Query→Get descriptor.
- process-env-integrity-prerequisite.json48D3AE0372949C22E651EFEB7AD92CBE406F89A1D3436D10E37114479325D16C: actual named-interceptor prevent/seal/freeze rejects before mutation/enumeration, while current QuickJS has no such custom-class hook.
- VM independently closed the original/current-source findings. Exact receipt copied to peers/process-env-operation-prerequisite-peer.json6067F94F050CB80744C022CB17166654E768AE627F77525AC8DDAD2653A1A004.

Neither proposal chooses/implements a shared ABI. Root owns authorization and scheduling; VM Message2a remains separate. No complete process.env or native State publication claim.

## Next work

1. Resolve Root's concrete cleanup adaptation and native Debug ownership choice; apply only the exact approved source successor, obtain its separate finite peer, then author actual dependency-based controls. The unchanged core algorithm/owner slices are independently closed.
2. Implement actual Debug dependency or consume Root's genuine ABI.
3. Complete native State and environment interceptor owners; keep exact six-hunk Engine/process proposal1D08388C unapplied until the owners and VM operation distinctions are ready.
4. Root-only integration/build/runtime qualification.
