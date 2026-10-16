# Native integration checkpoint, 15 October 2026

The reviewed upstream target is Pi commit `4954d760504c11df9b2cbdc040346107b6a8153d`, newer than published Pi `v1.3.0`. This working branch is an integration checkpoint. Complete application parity, final version certification, bridge removal, release and activation remain pending.

## Newly integrated evidence

| Component | Tested source | Published evidence | Scope |
| --- | --- | --- | --- |
| Immediate/check scheduling | `919ef1d81b71e8dc7774d90e5b5bfe636957779b` | `c645ed3b9a900559e98cfdd8b7908ea51275ad4a` | Windows Debug: 21 tests; genuine Node 31-case capture and delayed-poll control |
| JSON and thinking conversion | `928121f0ffd112f3c6173ca6aebbe17390ac0e7e` | `e94845320ab0652220df1259fc242df0efde89b1` | Windows Debug: 2 tests comparing all genuine 51 observations, preserving lone UTF-16 surrogates |
| Responses HTTP retries | `eb1b6520a6306dc3dc199b50fb0374ad6f35ab5d` | `cdceb00262999deca1e02b531266227b5ad61588` | Windows Debug: 12 tests; Source18, SourceRetry14 and owned socket infrastructure |
| Ordinary SDK factory bodies | Source capture candidate `c65ead97c787df9ecefe72dae5beacf4132efe91` | `a32671c058833cc8d965d6325a02c68a0911df49` | Genuine latest-upstream Source27 passed. Native factory code and subsequent promise-ownership corrections have not been compiled or replayed. |
| WritableStream | `8a782321523917137eeaeeb327000d21562ea109` | `6fce4363495bc56b7b1c1fc572aab7c318456f73` | Windows Debug: 2 tests, all 56 genuine Node observations, real GC and allocator leak checks. No allocation fault injection claim. |
| Codex/Radius browser OAuth observations | Source capture candidate `c4a5eb027ceb71402aee5bdf88c5f01b99ef3460` | `b7fc16e00cc16196542bc071093a57042bbc2aed` | Genuine upstream seven-case capture with seven owned listeners and both accepted sockets closed. Native replay remains pending. |
| Shared HTTP worker | `33bf95609592ab84cef4ede9508e2afc082b34bc` | `f193b0b28ed00ecfd3c70df3c834538d68a74372` | Windows Debug: 12 tests, real wire bytes, header deadline, typed failure/cancellation, explicit User-Agent and ownership. Full fetch/redirect/streaming-upload qualification is separate. |
| Response transport and critical ownership | `c9b97c857fb5b1724bc9c5c55a0d0be052739b83` | `65d372665cdf63bf344e9278937f551af6144292` | Windows Debug: basic real HTTP transport 5/5, Headers189 and identity 6/6, selected critical OOM 3/3, tee OOM 2/2, byte regression 14/14. Strict Response projection remains 110/114 with four retained dependency failures. |
| Public model-operation observations | Source capture candidate `f4a9a3937594b8129b90181e136ffcf9945274ec` | `0a0ae5c0e5c51724dafdd024f2a567ac09c0697a` | Genuine latest Source88 passed. Actual ModelsError leaf is now present for native replay; neither that new class nor the helpers are native-qualified yet. |
| URL constructor errors | `416e0a59b029e698bf0257b84738923a995a6086` | `ba7d950a8876e19c6e7a520b8adcd8a3aa212a4e` | Windows Debug: 19/19 tests, all 40 genuine error observations, existing GC/allocation sweeps. Full URL specification parity and combined Response replay remain pending. |
| RuntimeCredentials | `9ceb22363539021b215601a56458b62216afab55` | `bde590a3650c50a45b1a4dce081febca37609f4a` | Windows Debug: 3/3 tests, full genuine Source20 comparison and pending-list receiver retention/release. Full factory, ModelRuntime creation and allocator qualification remain pending. |
| Anthropic continuation | `b6080f3164c85fd4f199548e867afff6485df542` | `89957f4b9d4bd3e18b223ebd46b16f80078eab04` | Windows Debug: 14/14 selected tests; Source25, Source16 and seven supplied-SDK reader cases. Remaining custom-fetch SDK cases, full factory and allocation scope remain separate. |

The portable computational highlighter proof from `239098cf4bfc1ce5e9f4d28e35d037ffba5ba29e` is retained without importing its older interpreter over the current one. It proves exact AEA5/C47996: 250 disjoint ranges covering all 22,272 host-GPA failure indices exactly once, plus Deep7/Core74/Legacy32. It does not qualify the combined Root or the whole191 loader.

These component results apply to their exact tested source and captured inputs. Merging their files does not qualify this combined branch or transfer earlier six-profile results to the new head. Original failed attempts and raw terminal receipts remain retained.

## Resume integration, 16 October 2026

The direct upstream main ref is now `0fbdbd3f8ab1876ac260c0f08226a400759323b8`, four commits after the pinned `4954d760` reference. The latest release remains `v1.3.0`. The new changes include retry classification and per-model compaction policy; their native implementation and new reference qualification are in progress. Existing reference snapshots remain immutable and retain their original source scope.

The Request/fetch composition from tested source `884d47104dfabd4ef1f5a564568e4cd04a600f60` is now integrated. Its published evidence is `7e89e838851da41885c586c5c5b8acdaf7ccf52b`: complete Fetch39 plus real response-body abort/EOF/error ownership, Request55 and selected operation allocation failures, multipart Source3 and selected allocation failures, and Headers189 regressions passed on that exact Windows Debug candidate. Uploads in this scope are buffered finite bodies; arbitrary concurrent streaming upload is not qualified. The complete Body176 replay remains a separate gate. This merge preserves the newer shared HTTP preparation hooks, native callable receiver semantics, Immediate/check scheduling and reviewed QuickJS vendor bytes; the combined integration requires fresh native gates.

The paused Source88 proof tooling has been replaced by PowerShell 7 verification and freezing. Original Python files and the old Python-calling owner are retained byte-for-byte as historical `.txt` data. No historical observation or receipt was rewritten.

The nine-flow OAuth graph at `341032147bcfe06edd3d5720612c3586e9d8885b` is also integrated as source, including its actual Response/Body/readable dependency and captured loader/flow fixtures. Whole-graph native qualification remains pending. The QuickJS change is only the independently reviewed additive 42-line C and four-line header borrowed-view helper, retaining the newer native generator. Combined vendor hashes are C `12A7F02AFADA614EE9AED57F8EE87173F95977AD8FE8723177CACFACA7AB855D` and header `F3B6F51DBDA727A8FAECFE275FC13F283CA3C71E3907593E47B4F8B741318062`. The merged Engine retains both Immediate phase scheduling and the separate ChatGPT callback pump; this combined Engine still needs its own native gates.

## Remaining integration boundaries

The production SDK factory requires actual default ModelRuntime creation, ModelConfig/store classes, provider factories, authentication, resource-loader lifecycle and ordinary AgentSession collaborators. The existing synthetic builtin seeding path is insufficient for default-path parity. The new factory module remains unselected until these real inputs and their native comparisons are complete.

`native_ai_model_operations.create(engine, actualModelsError)` supplies the eight actual public model-operation helpers as one namespace, using the assembler's shared error constructor. Its source preserves ordinary callable metadata, nullish legacy-chat narrowing, assertion getter/coercion order, classifier image checks, result field insertion order, live Error/String/Date behavior and raw exceptions. Formatting, AST checks and the genuine Source88 reference capture are complete; native qualification remains required before activation.

Whole-language highlighter registration, its legacy interpreter and cancellation regressions, writable/readable/transform streams, full Request/Response/fetch behavior, SDK producer timing and the provider families are being qualified independently before the complete application gate. The default WebSocket provider draft requires its own actual loopback integration checks. The JavaScript bridge remains present until the native application passes those gates.

## Build output retention

Only retired, unnecessary build caches or `zig-out` directories whose source is verified on GitHub are eligible for cleanup. Verify normalized containment, absence of reparse points and live process dependencies, and preserve required executables and qualification evidence before moving an eligible directory to the Windows Recycle Bin. Do not permanently delete or empty the bin. A move to the Recycle Bin does not establish additional physical free space.
