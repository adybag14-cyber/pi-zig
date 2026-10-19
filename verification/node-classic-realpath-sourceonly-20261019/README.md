# Actual classic fs.realpathSync source unit

This source unit installs the genuine Node v24.13 classic realpath walk on the public filesystem graph. It is authored and statically reviewed; it has not been compiled, queried for test metadata, executed natively, or captured under Node in this unit.

## Public composition

- `node_fs.installWithStreams` receives the actual process object, installs the actual Stream owner, obtains the actual CommonJS `node:path` default through `Engine.requireBuiltin`, and completes the classic function before publishing the four filesystem namespaces.
- The public CommonJS object and the initial ESM named export retain the same classic function. Its `.native` member retains the pre-existing native operation. The existing filesystem-only installer keeps its previous profile.
- `native_sdk_application_bootstrap.installPlatform` obtains the completed actual `node:process` default and enters that Stream-backed filesystem installer. No caller-supplied replacement filesystem or path handlers are added.
- Public stat/lstat metadata updates the already completed, shared numeric or BigInt stat array before creating its public Stats object. Internal lstat/stat use those same array owners.
- The actual caller keeps getOptions, file-URL conversion, generic path addition, path validation, live path.resolve, private cache, and final Buffer encoding in Source order.
- The component walk preserves Source loop slots, separate cache equality/resolution reads, symlink identity, root checks, suffix restarts, and live public resolve calls. Native namespace conversion happens after the public resolve opportunities.
- Private OS errors consume latched status and original operation path through the intrinsic Error constructor. Node's actual Set order is errno, code, syscall, path; namespace stripping and message creation occur at their original private boundary.

The physical status producers are the separate dependency `dc9d4f569a90a79bd430cff76215840341b5e0fa`; this unit does not duplicate their operating-system implementation.

## Exact authorities

| Authority | Retained bytes / full source pin |
| --- | --- |
| Node v24.13.0 lib/fs.js | Full SHA-256 `A278A9082B2CD97BBB0638413F81838E5DE691E7562AEF5DE81F29B4CC7990D4`, 88,482 bytes |
| Selected classic Source JSON | `6C79695B2E03BF56525F2AD5EB31E8CBF2BC91A68A109729A060BB3DC7F7ECF7`, 6,122 bytes |
| Node src/api/exceptions.cc | `954E7DCCB7150C9EE2F7A00970EDF13FF62CA6073858DFC9C370F7684696FDA1`, 7,498 bytes |
| UV_ERRNO_MAP excerpt | `8610B952AF5F89384958BC61505AA102018B63DA1669BCC99FAC787F8994D61E`, 6,880 bytes |
| libuv unknown-error fallback excerpt | `38B70F31AD410375E98EC55D7C281E92B8DEDBEE3B345896C76C2436D9CB11B4`, 1,313 bytes |

The 5,511-byte fs.js selection starts at byte 69,310 of the original source, covering splitRoot, encodeRealpathResult, nextPart, realpathSync and its native property. A source-only byte comparison against the retained full file verified this exact range before composition. It is not a generated implementation.

All sources are from the Node v24.13.0 tag:
- https://raw.githubusercontent.com/nodejs/node/v24.13.0/lib/fs.js
- https://raw.githubusercontent.com/nodejs/node/v24.13.0/src/api/exceptions.cc
- https://raw.githubusercontent.com/nodejs/node/v24.13.0/deps/uv/include/uv.h
- https://raw.githubusercontent.com/nodejs/node/v24.13.0/deps/uv/src/uv-common.c

The UV_ERRNO_MAP excerpt begins at byte 2,422 of uv.h (full SHA-256 `FDDEC8C096616675B4578D85222663C8624DCE3EE67F5BE1C33BA83EB02A827C`). The fallback excerpt begins at byte 4,770 of uv-common.c (full SHA-256 `C311E17AE0F891C9EBA52626ADF9EA33A91B7459654EB1C20E56C24D30D6B446`). Both libuv excerpts end at the final definition's newline, excluding the following blank source separators. The retained Node license accompanies these excerpts.

## Qualification surface

| Field | Authored value |
| --- | --- |
| Build target | `build-native-node-fs-realpath-classic` |
| Filter | `native actual classic realpath` |
| Root | `src/native_node_fs_realpath_classic_test.zig` |
| Installed Windows artifact | `native-node-fs-realpath-classic.exe` |
| Declared controls | 21 |
| Genuine Node observer routes | 16 |
| Native-only ownership/stat controls | 5 |

The target is install-only, with no run edge and no addTest name override. Declared counts are source counts, not metadata or runtime results.

The sixteen shared observers cover ordinary paths; file/directory link chains; options, Buffer and URL inputs; actual CJS/named identity; live path.resolve; truthy cache DATA; strict-equality/cache restart order; six encoding accesses; real Buffer encoding; native ENOENT/loop failures; captured primordials; and final-cache failure before encoding.

The five native controls use actual C holders and the real pending/fatal producers. They check sole cache-operand retirement before the next getter, exact first-fatal identity with host progress 1/0/0, same-operation private DATA, successful flagged DATA, and actual shared stat arrays.

Both fixtures create only their own two files and eight symlinks in a fresh contained directory. The native fixture uses its real TmpDir owner. The authored Node runner takes an existing absolute parent inside `C:/Users/adyba/pi-zig`, verifies its canonical containment, creates a fresh `classic-realpath-` child, and removes only that child in its finalizer. Symlink creation requires actual host support; no junction or fabricated-stat fallback is provided.

The Node runner requires the independently pinned Node v24.13.0 executable, `--expose-internals`, and Root's separate source-capture grant. It validates the exact authority and observer hashes, executes the actual built-in fs function, and emits observations only after completion and fixture removal. Native build, metadata, and RuntimeOnly each remain under Root's resource and source-seal protocol.

## Bounded source reviews and open qualification

- SDK reviewed the original component walk/reset/cache control flow (DD915ABE) and actual caller/encoding (607D02AF); no concrete blocker remained in those slices.
- VM reviewed private UV error ownership and throw order (D9E0BA79) against exceptions.cc; raw error-map completeness remains outside that peer.
- SDK reviewed observer routes 9–16 against the actual fs.js body (root 833D3942 / observer 8FBDAB8C), with no concrete blocker.
- VM reviewed the genuine fixture and native declarations 17–21 on those same pins, with no concrete blocker.
- Root's requested observer routes 1–8 and public-installation/namespaced-producer composition review is pending at authoring.

These bounded reviews do not establish physical Windows/Linux runtime behavior, complete native-realpath or file-URL/IDN parity, process permission modes, complete libuv error-map coverage, or full Module/Jiti/TypeScript/ESM/TLA behavior. Those remain distinct work and qualification steps on the same actual public graph.
