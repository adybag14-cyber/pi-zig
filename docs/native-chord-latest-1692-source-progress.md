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

These modules are unimported and have pinned Zig 0.16.0 formatting and AST evidence only. No compile, native execution, Source differential, GC or allocator-failure qualification is claimed. No Host connection/reload API, Chord package or default runtime is activated.

The actual latest ObjectImpl/RefImpl/Self/Ctx declaration graph, Host construction/root signals and identity/lifetime handling, Connection/RemoteRef/RelayRef protocol v2, `variant`, optional method arguments/results, acknowledgements/window/coalescing/maxCalls, link size/protocol/IPC failures, native nodeLoader and manager remain required. Merely renaming the old implementations cannot establish these semantics. Full current Source end-to-end callers, negative outcomes, generation collection, cancellation and complete allocator-failure checks must replace historical assumptions before integration qualification. No native qualification job has been launched in this packet.
