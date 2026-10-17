//! Expanded f912/c43 compile/link-only composition; prospective/uncompiled. No Subject, fixture, Engine
//! or namespace is created. These exported typed actual calls require body
//! analysis/emission WHEN compiled; source preparation is not a compile result.
//! No runtime/query/reference use is approved. The sentinel must never execute.
const std = @import("std");

fn Anchor(comptime function: anytype) type {
    const info = @typeInfo(@TypeOf(function)).@"fn";
    const Args = std.meta.ArgsTuple(@TypeOf(function));
    const Return = info.return_type orelse @compileError("Explicit control return type required");
    if (@typeInfo(Return) != .error_union) @compileError("This compile anchor requires an actual fallible control/body");
    const Payload = @typeInfo(Return).error_union.payload;
    return struct {
        fn entry(raw_args: *const anyopaque, raw_result: ?*anyopaque) callconv(.c) c_int {
            // Opaque pointers avoid inventing runtime inputs or a replacement
            // ABI for private Subject types. An approved real caller would own
            // this exact ArgsTuple and any returned payload; none runs here.
            const args: *const Args = @ptrCast(@alignCast(raw_args));
            if (Payload == void) {
                @call(.never_inline, function, args.*) catch return 1;
            } else {
                const result: *Payload = @ptrCast(@alignCast(raw_result orelse return 2));
                result.* = @call(.never_inline, function, args.*) catch return 1;
            }
            return 0;
        }
    };
}
fn retain(comptime module: type, comptime prefix: []const u8, comptime names: anytype) void {
    inline for (names) |name| {
        @export(&Anchor(@field(module, name)).entry, .{ .name = "current_main_compile_only_" ++ prefix ++ "_" ++ name });
    }
}
// Actual comptime Source variants need concrete typed instantiations, rather
// than an invented ArgsTuple value for their comptime parameter. These wrappers
// call the genuine factory; its actual AF callbacks/await bodies are retained.
fn createAgentPrompt(engine: *@import("extensions/engine.zig").Engine) !@import("extensions/engine.zig").c.JSValue {
    return @import("extensions/native_agent_prompt_async.zig").create(engine, .prompt);
}
fn createAgentContinue(engine: *@import("extensions/engine.zig").Engine) !@import("extensions/engine.zig").c.JSValue {
    return @import("extensions/native_agent_prompt_async.zig").create(engine, .continue_run);
}
comptime {
    @setEvalBranchQuota(100_000);
    retain(@import("native_jiti_core_factory_controls.zig"), "core_control", .{
        "verifyUnlinkedNotExposed", "verifyForeignEngineRejected", "verifyCanonicalCycleAndOnce", "verifyWrapFailureAfterPublication", "verifyCompileFailureReturnsThroughRealTail", "verifyAcceptedTrace",
    });
    retain(@import("native_jiti_eval_module_controls.zig"), "eval_control", .{
        "verifyRealModuleAndCaches", "verifyAsyncPublicationAndFinish", "verifyAcceptedReturningOnError", "verifyMissingBindingBeforePublication", "verifyUnsupportedBeforePublication",
    });
    retain(@import("native_jiti_import_rejected_data_controls.zig"), "import_control", .{
        "verifyOldFlaggedData", "verifySameObjectOrdinaryRethrow", "installFreshFaultProbe", "verifyFreshResumedOOM", "verifyPendingHookFatalWins", "verifyDeferredBudgetInterrupt",
    });
    retain(@import("native_jiti_options_controls.zig"), "options_control", .{
        "verifyDirectHostCatchBeforeDiagnostics", "verifyDefaultsOverridesAndCallable", "verifyInheritedSettersAndSymbols", "verifyAcceptedGetterAndCatchTrace",
    });
    retain(@import("native_jiti_utils_controls.zig"), "utils_control", .{
        "verifyPhysicalDirectoryAndHashes", "verifyHashTemporaryRetirement", "verifyAcceptedCaller",
    });
    retain(@import("native_node_module_constructor_controls.zig"), "module_control", .{
        "verifyConstructorAndPrivateParents", "verifyEffectsAndPrimordials", "verifyActualPathReference", "verifyActualCachePublication", "verifyExactThrownReasons", "verifyPendingDeprecation",
    });
    retain(@import("native_get_tsconfig_test.zig"), "tsconfig_control", .{ "compareOriginal", "retainedMatcher" });
    retain(@import("native_mlly_syntax_controls.zig"), "syntax_control", .{ "observeActualExport", "observeAfterGc", "verifyAcceptedOriginalObservation" });

    // Cache/transform have actual production leaves but no dedicated control
    // module in this Root base. Retain their real exports, never fake subjects.
    retain(@import("extensions/native_jiti_fs_cache.zig"), "fs_cache", .{ "create", "getCache", "prepareCacheDir", "getCacheDir" });
    retain(@import("extensions/native_jiti_transform.zig"), "transform", .{ "create", "transform" });
    retain(@import("extensions/native_jiti_module_cache.zig"), "module_cache", .{ "forRequire", "lookup", "publishBeforeEval", "afterEvalFailure", "afterNativeSuccess", "loadedExports" });
    retain(@import("extensions/native_jiti_interop.zig"), "interop", .{ "jitiInteropDefault", "interopDefault", "jsonSelfDefault", "importDefault" });
    retain(@import("extensions/native_jiti_import.zig"), "import", .{"create"});
    retain(@import("extensions/native_jiti_require.zig"), "require", .{ "create", "require", "nativeImportOrRequire" });
    retain(@import("extensions/native_jiti_resolve.zig"), "resolve", .{ "createConstants", "create", "resolve" });
    retain(@import("extensions/native_jiti_core_factory.zig"), "core", .{ "validate", "instantiate" });
    retain(@import("extensions/native_jiti_core_graph.zig"), "graph", .{ "declare", "create" });
    retain(@import("extensions/native_jiti_module_cells.zig"), "cells", .{ "declare", "link", "initialize", "exports", "coreImports", "frontendImports", "isWindows" });
    retain(@import("extensions/native_jiti_eval_frontend.zig"), "frontend", .{ "validate", "evaluate" });
    retain(@import("extensions/native_jiti_eval_module.zig"), "evaluation", .{ "evaluateTransformed", "evaluateLowered" });
    retain(@import("extensions/native_jiti_options.zig"), "options", .{ "create", "resolve" });
    retain(@import("extensions/native_get_tsconfig.zig"), "tsconfig", .{"create"});
    retain(@import("extensions/native_mlly_syntax.zig"), "syntax", .{ "create", "hasESMSyntax" });
    retain(@import("extensions/native_jiti_colors.zig"), "colors", .{"create"});
    retain(@import("extensions/native_jiti_crypto.zig"), "crypto", .{"create"});
    retain(@import("extensions/native_jiti_utils.zig"), "utils", .{"create"});
    retain(@import("extensions/native_jiti_budget.zig"), "budget", .{ "check", "next" });

    // Current public factory/profile and the real native Graph0/lowering tail.
    retain(@import("extensions/native_jiti_public_factory.zig"), "public_factory", .{"create"});
    retain(@import("extensions/native_jiti_profile.zig"), "profile", .{ "prepare", "complete" });
    retain(@import("extensions/native_jiti_default_transform.zig"), "default_transform", .{ "create", "transform" });
    retain(@import("extensions/native_jiti_native_import.zig"), "native_import", .{"create"});
    retain(@import("extensions/native_jiti_import_meta.zig"), "import_meta", .{"rewrite"});
    retain(@import("extensions/native_jiti_escape_regexp.zig"), "escape_regexp", .{ "create", "escape" });
    retain(@import("extensions/native_jiti_cjs_eval.zig"), "cjs_eval", .{ "prepare", "compile", "invoke" });
    retain(@import("extensions/native_jiti_cjs_lower.zig"), "cjs_lower", .{"lower"});

    // Real consumed MLLY/Pathe operations. Callback addresses passed by these
    // actual factories retain their real ordinary/arrow/AF implementations.
    retain(@import("extensions/native_mlly_resolve.zig"), "mlly_resolve", .{"create"});
    retain(@import("extensions/native_mlly_module_resolve.zig").Resolver, "mlly_package", .{ "moduleResolve", "tryStat", "finalize", "importsResolve", "packageResolve" });
    retain(@import("extensions/native_mlly_package_reader.zig"), "mlly_reader", .{ "read", "getPackageScopeConfig" });
    retain(@import("extensions/native_mlly_urls.zig"), "mlly_urls", .{ "create", "normalizeSlash", "fileURLToPath", "pathToFileURL", "normalizeId" });
    retain(@import("extensions/native_mlly_format.zig"), "mlly_format", .{ "initialize", "defaultGetFormatWithoutErrors" });
    retain(@import("extensions/native_mlly_errors.zig"), "mlly_errors", .{ "template", "create" });
    retain(@import("extensions/native_mlly_values.zig"), "mlly_values", .{ "initialize", "collect", "advance", "closeNormal", "caught", "trusted", "budget", "array" });
    retain(@import("extensions/native_mlly_function.zig"), "owned_callable", .{ "create", "createArrow", "createMethod" });
    retain(@import("extensions/native_pathe.zig"), "pathe", .{"create"});
    retain(@import("extensions/native_ufo_join_url.zig"), "ufo", .{"join"});

    // Genuine SDK application/ordinary session composition and both Agent AF
    // factory instantiations. No inputs or completed collaborator are invented.
    retain(@import("extensions/native_sdk_application_assembly.zig"), "sdk_application", .{"create"});
    retain(@import("extensions/native_sdk_default_real_assembly.zig"), "sdk_default", .{ "create", "select" });
    retain(@import("extensions/native_sdk_factory_production.zig"), "sdk_factory", .{ "compose", "create" });
    retain(@import("extensions/native_sdk_session_production.zig"), "sdk_session", .{ "validateInputs", "constructor" });
    retain(@import("extensions/native_agent_core.zig"), "agent_core", .{"installFoundations"});
    @export(&Anchor(createAgentPrompt).entry, .{ .name = "current_main_compile_only_agent_prompt_af" });
    @export(&Anchor(createAgentContinue).entry, .{ .name = "current_main_compile_only_agent_continue_af" });

    // Actual current control bodies: the supplied pointers retain each real
    // ArgsTuple/return type; no Subject value or result is manufactured here.
    retain(@import("native_jiti_public_factory_controls.zig"), "public_control", .{
        "verifyCapturedQueue", "verifyActualNamespaceAndConstruction", "verifyUnpublishedModuleRejected", "verifyPendingBeforeProfile", "verifyPendingLazyLoadAndRetry", "verifyPendingModuleGetterBeforeNamespace", "verifyPendingBeforeComplete",
    });
    retain(@import("native_jiti_canonical_assembly_controls.zig"), "canonical_control", .{
        "verifyActualCanonicalCycle", "verifyMissingDependencyNoCommit", "verifyMismatchedRealImportsNoCommit", "verifyBudgetDenialRollbackAndRetry", "verifyActualCycleMarkingAndLedgerRelease", "verifyPendingEventsBeforeConstructionAndInitialization",
    });
    retain(@import("native_jiti_frontend_fallback_controls.zig"), "fallback_control", .{
        "verifyHistoricalDataRawFallback", "verifySameObjectOrdinarySpreadRethrow", "installNativeFaultProbes", "verifyFreshSpreadOOM", "verifyActualPendingEventWins", "verifyRealSpreadInterrupt",
    });
    retain(@import("native_jiti_native_import_controls.zig"), "native_import_control", .{
        "verifyCanonicalTwoRealDeclarations", "verifyRealRawThenReturn", "verifySyncUsesRealRequireWithoutImportRead", "verifyActualSynchronousThrow", "verifyActualPendingEventBeforeGetters", "installNativeEventProbes", "verifyPendingEventOverSuccessValue", "verifyFreshCurrentNativeOOM", "verifySecondDeclarationRollbackAndRetry",
    });
    retain(@import("native_sdk_application_assembly_test.zig"), "sdk_application_control", .{ "verifyActualAiIdentity", "compareFullFactorySource" });
    retain(@import("native_agent_prompt_async_test.zig"), "agent_prompt_control", .{"compareActualSource"});
    retain(@import("native_jiti_mlly_boundary_test.zig"), "mlly_boundary_control", .{ "verifyActualFormatDispatch", "verifyActualPostdecrementNumeric", "verifyActualURLWrapperReentry", "verifyActualDescriptorOrder" });
    retain(@import("native_jiti_pathe_policy_test.zig"), "pathe_policy_control", .{"verifyActualCrossNamespaceReentry"});

    // Their real selected test declarations have no public named control entry.
    // Build filters retain those actual bodies; nothing executes this artifact.
    _ = @import("native_jiti_mlly_test.zig");
    _ = @import("native_jiti_pathe_test.zig");
    _ = @import("native_jiti_pathe_supplement_test.zig");
    _ = @import("native_jiti_pathe_cache_test.zig");
    _ = @import("native_jiti_public_factory_test.zig");
}

// New actual full-Agent create paths. Arguments remain actual typed pointers;
// no Engine, namespace, Completed graph or fake Subject is constructed here.
fn createAgentExecution(engine: *@import("extensions/engine.zig").Engine, actual_loop: @import("extensions/engine.zig").c.JSValue) !@import("extensions/engine.zig").c.JSValue {
    return @import("extensions/native_agent_execution_async.zig").create(engine, false, actual_loop);
}
fn createAgentContinuation(engine: *@import("extensions/engine.zig").Engine, actual_loop: @import("extensions/engine.zig").c.JSValue) !@import("extensions/engine.zig").c.JSValue {
    return @import("extensions/native_agent_execution_async.zig").create(engine, true, actual_loop);
}
comptime {
    @setEvalBranchQuota(100_000);
    retain(@import("extensions/native_agent_complete.zig"), "agent_complete", .{"install"});
    @export(&Anchor(createAgentExecution).entry, .{ .name = "current_main_compile_only_agent_execution_af" });
    @export(&Anchor(createAgentContinuation).entry, .{ .name = "current_main_compile_only_agent_continuation_af" });
    retain(@import("extensions/native_agent_lifecycle_async.zig"), "agent_lifecycle_af", .{"create"});
    retain(@import("extensions/native_agent_failure_async.zig"), "agent_failure_af", .{"create"});
    retain(@import("extensions/native_agent_events_async.zig"), "agent_events_af", .{"create"});
    retain(@import("extensions/native_agent_config_async.zig"), "agent_config_af", .{"create"});
    retain(@import("extensions/native_agent_loop_config.zig"), "agent_loop_config", .{"create"});
    retain(@import("extensions/native_agent_executor_fatal.zig"), "agent_executor_fatal", .{ "create", "construct" });
    retain(@import("native_agent_full_async_test.zig"), "agent_full_control", .{"compareActualSource"});

    retain(@import("extensions/native_sdk_application_bootstrap.zig"), "sdk_bootstrap", .{ "installPlatform", "create" });
    retain(@import("extensions/native_node_os.zig"), "node_os", .{ "create", "install" });
    retain(@import("native_sdk_application_native_test.zig"), "sdk_native_control", .{ "verifyFullApplication", "compareActualOsSource" });

    // Actual constructor/prototype/_load/provider/compiler declarations. Each
    // complete function body is called by an emitted never-inline typed anchor.
    retain(@import("extensions/native_node_module_constructor.zig"), "module_constructor", .{"create"});
    retain(@import("extensions/native_node_commonjs_prototype.zig"), "commonjs_prototype", .{"create"});
    retain(@import("extensions/native_node_commonjs_state.zig"), "commonjs_state", .{ "create", "known" });
    retain(@import("extensions/native_node_commonjs_wrapper.zig"), "commonjs_wrapper", .{"install"});
    retain(@import("extensions/native_node_commonjs_script.zig"), "commonjs_script", .{ "prepare", "run" });
    retain(@import("extensions/native_node_commonjs_load.zig"), "commonjs_load", .{ "create", "loadWithCleanup" });
    retain(@import("extensions/native_node_commonjs_converted_module.zig"), "converted_module", .{"publish"});
    retain(@import("extensions/native_node_commonjs_converted_provider.zig"), "converted_provider", .{ "register", "ready", "compiledBody" });

    // Actual f912 once-owned dependency graph and immediate pending boundaries.
    retain(@import("extensions/native_jiti_shared_dependencies.zig"), "shared_dependencies", .{ "create", "prepareJiti" });
    retain(@import("native_jiti_shared_dependencies_controls.zig"), "shared_control", .{
        "verifyCanonicalRepeatedGraph", "verifyChangedCanonicalInputRejected", "verifyPendingBeforeInitialization", "verifyRealColorReentry", "verifyRealColorInitializationRollback",
    });
    retain(@import("native_jiti_initialization_pending_controls.zig"), "initialization_pending_control", .{
        "verifyTtyImmediateBoundary", "verifySharedImmediateRollback", "verifyEachActualColorCall", "verifyActualColorGetter",
    });

    // Real existing native tests are retained by the build filters. These do
    // not execute during compile-only qualification. Later runtime admission
    // must separately provide the genuine completed inputs/references required
    // by their actual callers; no absence is turned into a passing test here.
    _ = @import("native_agent_af_correction_test.zig");
    _ = @import("native_node_commonjs_script_test.zig");
    _ = @import("native_node_commonjs_load_failure_test.zig");
    _ = @import("native_node_commonjs_converted_module_test.zig");
}

test "EXPANDED_MAIN_COMPILE_LINK_ONLY_SENTINEL_NEVER_EXECUTE" {
    return error.CompileOnlyArtifactMustNotRun;
}
