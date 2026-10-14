# Chord latest breaking-contract source progress

The authority is unmodified Source `1692bba6347a287ab0f3cb554a4430fafffc474b`, in `C:/Users/adyba/pi-upstream-source-1692bba-20261014`. The e622-to-1692 Chord delta changes 43 files, with 5086 inserted and 2915 removed lines. Source and tests were inventoried in `verification/chord-latest-1692-source-20261014/source-api-cases.json`: 74 files with SHA256, 322 API declaration markers and 449 test/describe declaration markers. This is a static inventory, not an executed oracle or assertion count.

`dbe0fa4` preserves the resumed historical e622 Reload work before adaptation. Historical e622 Connection26, Remote, Relay, protocol and Host component receipts retain their original source authority. Their fixtures are unchanged and cannot establish 1692 behavior.

## Actual latest source bodies

The unimported Reload class and its preparation, candidate, service-table, gate, migration, rollback, installation and publication modules now follow the new object/reference/implementation/codeVersion fields. Preparation checks each cell's version, refuses lowering it, gates raised versions, migrates only the relevant cell and computes each run's fresh derivations. Commit adopts kept resource declarations, installs references for host-lifetime objects, releases pins when a type becomes referenced, and queues facet-run changes after installation. Facet runs get individual abort signals, and rollback aborts all candidate runs.

The new retirement body uses actual Host retirement watchers and parent retirement permission. A deadline first aborts roots of the previous code version with `superseded`, then allows at most 1000 milliseconds of grace before retiring its resources. The Source retirement check is evaluated again after every notification and await.

The actual cluster coordinator retires before sending child prepare frames, waits for every local/child result, aborts every participant on failure, and sends FIFO commit frames before any committed work starts. `reconcileChild` waits for a concurrent local reload to end, announces prior retirements before preparing, and retries if the local version changes while waiting for its vote. Longest-prefix module mapping, vote deadlines and private shared reload IDs have concrete bodies. Child preparation registers its operation before awaiting modules and retains cancellation/parent-loss cleanup.

Latest Host reload support includes deferred hello replay, reload waiters, facet-run replacement aborts, coordinator admission, remote-module remembrance, retirement watchers, retirement announcement and dependency-ordered old-implementation cleanup. The source-only Host connection body now fences and defers children that announce during a reload, removes their deferred entry on close, and invokes mandatory actual child reconciliation/parent-loss dependencies.

The actual latest factory `SelfImpl` and `Decls` now have separate unimported modules. They declare state and resources by name, validate per-cell/resource versions, retain old references where their contracts/status allow it, record kept resources for adoption, build optional-selector listeners, and create fresh positional tasks/derivations. Registry declarations require host lifetime. They depend on real Object/Ref/Cell/resource runtime bindings and are not installed into the historical Host factory.

## Remaining qualification boundary

The continuing source work now assembles the actual latest Host/Object/Ref/Ctx/Reload/cluster/Connection/RemoteRef/RelayRef graph in the private native_chord_latest.zig qualification factory. It implements detached linked context signals, WeakMap service/adaptor references, host-lifetime address/principal identity, task restart deadlines and generation fences, listener subscription at activation, disposal completion cleanup, optional method arguments/results, protocol-v2 acknowledgement byte windows, bounded state slots, relay resynchronization and maxCalls.

Payload packing uses allocator-owned direct C zlib selected from Node24.14.0 commit f657bb8ed86365ff3fdbe32e27563e778b41486a. The selected original C/header/license bytes and hashes are retained in vendor/chord-zlib-node-24.14.0. The captured original runtime identifies zlib as 1.3.1-e00f703. No JavaScript, Python or Node implementation is introduced.

Unmodified latest Source produced byte-stable double captures for Object/Reload8, full Host links8, closed Host2 and protocol/packing/flow/maxCalls9: 27 cases. Every capture checked all 1955 Source, 31064 dependency/runtime and 1774 Node distribution files before and after, plus caller/resolver/audit hashes, with zero drift. Actual Source constructor and factory bodies were not replaced. fixture-inventory.json records the exact caller/oracle hashes and case names.

The latest modules are imported only by the private qualification factory/test target. At this checkpoint they have pinned Zig 0.16.0 formatting and AST evidence only. Semantic compile, native execution, Source differential, GC and allocator-failure qualification remain outstanding. No Chord package or default runtime is activated.

The assembled graph requires semantic compilation, execution of the current Source fixtures, generation collection, cancellation and complete allocator-failure qualification. Native nodeLoader, manager and the complete current package export graph remain required. Source capture and syntax checks do not establish native behavior. The private target retains the original 10-second host await guard, 120-second test guard and separate 300-second runtime boundary.
