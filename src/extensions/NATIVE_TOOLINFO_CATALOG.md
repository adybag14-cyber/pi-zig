# Private canonical ToolInfo catalog API (candidate)

Group.setNativeToolCatalog(context, callback) admits a native producer. Callback signature is fn(?*anyopaque, *Bindings, *native_tool_catalog.CatalogSink) anyerror!void. Group checks the actual calling Bindings membership; the existing API owner token and runtime admission remain authoritative. The producer verifies any actual private SDK lease and copies service records before releasing native locks. Neither caller JSON nor an inferred latest context chooses an owner or lifetime.

CatalogSink.beginScope(scope) is required even for an empty owner catalog. CatalogSink.append(record) accepts trusted native data; CatalogSink.appendVM(definition, source_info, exposure_resolver) handles existing owner-VM SDK definitions directly without JSON. A finished collection returns fresh arrays/ToolInfo rows. Group.retireNativeToolCatalog(scope) retires the actual native service/lease generation. Cache.parameterValue/definitionValue return owned VM references for exact native consumers.

OwnerScope = {owner:*const anyopaque,generation:u64}. The pointer identifies an actual retained native service/lease; generation prevents reuse after retirement. CLI uses its actual Group/runtime ownership; it does not manufacture an SDK lease.

Record fields:

- scope; definition_id: positive native publication identity, renewed for a new definition.
- parameter_identity: remote_json | resource_list | resource_read | codemode | tool_search.
- parameter_id: positive independent identity for remote_json. New parsed tool definitions get new parameter IDs; hidden re-registration of the old definition keeps the old ID.
- metadata: native JSON tool definition metadata; parameters: genuine native JSON schema; source_info: native source metadata. These values do not select any lifetime IDs.
- namespace_id, prompt_guidelines_id, annotations_id: optional positive native identities for intentionally shared original references. Zero keeps per-definition values. New server refresh batches get a new namespace ID; all definitions from that batch share it, and hidden old definitions retain their old namespace ID.
- source_info_id: native shared source identity (default0 for one extension source); optional source_scope uses the actual common builtin extension source lifetime independently of each tool/parameter owner.

Resource list and list-template definitions use the same resource_list parameter key, read uses resource_read. These are plain module-scope Source constants, preserved across every resource definition/exposure replacement. Canonical codemode and tool_search schemas are constructed with real native TypeBox Object/String/Number/Optional constructors, preserving hidden kind/optional metadata. Module constants survive definition and service snapshot replacement until their VM/module retires.

ToolInfo projection preserves original parameters, promptGuidelines, namespace and sourceInfo references. Annotation objects are fresh shallow copies with original nested/symbol references. It reproduces Source object-literal data properties, key order and getter order, including repeated truthy namespace/annotation reads, without invoking inherited setters. Current extension definitions and source metadata are retained before getters can replace/unload registrations. Metadata references stay pinned across nested collections; completed authoritative scopes prune retired definitions only after all active sinks finish.

The Source getAllTools audit uses the actual createAgentSession from the clean built1ced authority, not an authored substitute. AgentSession/loader/tool_search source are unchanged through6fb; codemode's later changes only centralize defaults and do not change schema or identity predicates. Source MCP refresh reference IDs additionally prove batch namespace aliases and parameter retention on withdrawal.

The dedicated `test-native-toolinfo` gate executes actual Source SDK ToolInfo identity predicates, annotation getter/symbol semantics, distinct native definition/parameter/namespace lifetimes, canonical module schema identity, nested catalog pinning and exhaustive GPA unwinding. The stream installer now admits the complete TypeBox module before capturing its shared Type namespace, rather than reserving the module name with a Type-only stub. The full binding gate also checks that fresh ToolInfo rows retain schema identity while settings and command snapshots stay independent. Root's private SDK, factory admission and native typed producer wiring remain separate prerequisites; this private API alone does not qualify that production integration or full Pi parity.
