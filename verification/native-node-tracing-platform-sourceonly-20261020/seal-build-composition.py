from pathlib import Path
import datetime,hashlib,json,re,subprocess
own=Path(r'C:\Users\adyba\pi-zig\worktrees\modules-io-resume-20261018')
main=Path(r'C:\Users\adyba\pi-zig\main')
provider=Path(r'C:\Users\adyba\pi-zig\worktrees\provider-af-resume-20261018')
packet=own/'verification/native-node-tracing-platform-sourceonly-20261020'
out=packet/'build-composition';out.mkdir(parents=True,exist_ok=True)
base='f4c6abbc62ecd18b72ec50ab8fa206fe1664909f'
def sha(b):return hashlib.sha256(b).hexdigest().upper()
def pin(p):
 b=p.read_bytes();return {'path':str(p),'bytes':len(b),'sha256':sha(b)}
def snapshot_git(rel,base=base):
 b=subprocess.check_output(['git','show',base+':'+rel],cwd=main)
 p=out/'original'/rel;p.parent.mkdir(parents=True,exist_ok=True);assert not p.exists();p.write_bytes(b)
 return {'repository_path':rel,'commit':base,'snapshot':pin(p)}
original=subprocess.check_output(['git','show',base+':build.zig'],cwd=main)
anchor=b'    if (native_node_network) |network| quickjs.root_module.linkLibrary(network);\n'
assert original.count(anchor)==1
addition="""    // Source-only tracing assembly: the dedicated target installs archives.
    // Final binary linkage and process bootstrap remain separate admission.
    if (native_node_memory) |memory| {
        if (native_node_network) |network| {
            const tracing_build = @import("tools/build_native_node_tracing.zig");
            const tracing_abseil = @import("tools/build_native_node_abseil.zig").add(b, target, optimize);
            const tracing_diagnostic = tracing_build.addDiagnosticOwner(b, target, optimize);
            const tracing_library = tracing_build.add(b, target, optimize, .{
                .network = network,
                .native_memory = memory,
                .diagnostic = tracing_diagnostic,
                .abseil = tracing_abseil,
            });
            const tracing_archives = b.step(
                "build-native-node-tracing",
                "Build and install the original tracing, Abseil and diagnostic archives",
            );
            inline for (.{ tracing_abseil, tracing_diagnostic, tracing_library }) |archive| {
                tracing_archives.dependOn(&b.addInstallArtifact(archive, .{}).step);
            }
        }
    }
""".encode()
offset=original.index(anchor)+len(anchor);projected=original[:offset]+addition+original[offset:]
assert projected[:offset]+projected[offset+len(addition):]==original
assert b'addRunArtifact' not in addition and b'addSystemCommand' not in addition
assert projected.count(b'native_node_diagnostic_context.c')==original.count(b'native_node_diagnostic_context.c')==1
orig=out/'original/build.zig';orig.parent.mkdir(parents=True,exist_ok=True);assert not orig.exists();orig.write_bytes(original)
proj=out/'projected/build.zig';proj.parent.mkdir(parents=True,exist_ok=True);assert not proj.exists();proj.write_bytes(projected)
refs=[]
for rel in [
 'tools/build_native_node_memory.zig','tools/build_native_node_network.zig',
 'src/extensions/engine_abi.c','src/extensions/engine_abi.h',
 'src/extensions/native_simdjson_memory.cpp','src/extensions/native_simdjson_memory.hpp',
 'src/extensions/native_node_standard_allocator.hpp',
 'src/extensions/native_node_check_failure.c','src/extensions/native_node_check_failure.h',
 'src/extensions/native_node_diagnostic_context.c','src/extensions/native_node_diagnostic_context.h',
 'src/extensions/native_node_diagnostic_context.hpp',
]:
 refs.append(snapshot_git(rel))
fatal_pins=[]
for rel,expected in [
 ('src/extensions/native_v8_base_fatal.h','C5B2D6E6F7B8DA0E8C9D70E8934392B10BB638DA5C209870385FCE1AC71D3CBF'),
 ('src/extensions/native_v8_base_fatal.cpp','1C83C0523655ACD3FF64CA067AE2CB5131C98B36A2E60910AEF4C64699BD3BBC'),
 ('src/extensions/native_node_tracing_clock_diagnostics.cpp','05E4B163D86C32C17A5E9DE57332FD08EA102878654272FA399FF168AE38EC61'),
]:
 v=pin(provider/rel);assert v['sha256']==expected;fatal_pins.append(v)
proposal=json.loads((packet/'production-proposal.json').read_text())
for item in proposal['production_files']:
 assert pin(own/item['path'])['sha256']==item['snapshot']['sha256']
for item in proposal['preexisting_unchanged_tracing_drafts_required_by_build']:
 assert pin(Path(item['path']))['sha256']==item['sha256']
assert (own/'src/extensions/native_node_standard_allocator.hpp').read_bytes()==(out/'original/src/extensions/native_node_standard_allocator.hpp').read_bytes()
cunits={'all_targets':['src/extensions/native_node_diagnostic_context.c']}
cppunits={
 'all_targets':[
 'src/extensions/native_node_tracing_core.cpp','src/extensions/native_node_tracing_controller.cpp',
 'src/extensions/native_node_tracing_buffer.cpp','src/extensions/native_node_tracing_writer.cpp',
 'src/extensions/native_node_tracing_agent.cpp','src/extensions/native_node_tracing_clock.cpp',
 'src/extensions/native_node_tracing_api.cpp','src/extensions/native_node_tracing_platform.cpp',
 'src/extensions/native_node_tracing_loop.cpp','src/extensions/native_v8_base_fatal.cpp',
 'src/extensions/native_node_tracing_clock_diagnostics.cpp'],
 'windows':['src/extensions/native_node_tracing_recorder.cpp','src/extensions/native_node_tracing_recorder_win.cpp'],
 'macos':['src/extensions/native_node_tracing_recorder.cpp','src/extensions/native_node_tracing_recorder_mac.cpp'],
}
absl=json.loads((own/'vendor/node-v24.13.0/abseil-cpp/SOURCE-MANIFEST.json').read_text())
assert absl['cpp_units']==110
d={
 'schema':1,'kind':'Finite install-only tracing archive composition proposal; not applied',
 'created_utc':datetime.datetime.now(datetime.timezone.utc).isoformat(),
 'main_basis':base,'build_original':pin(orig),'build_projected':pin(proj),
 'edit':{'kind':'single insertion','byte_offset':offset,'anchor':anchor.decode(),'insert':addition.decode(),'insert_bytes':len(addition),'insert_lines':addition.count(b'\n')},
 'inverse_recovers_complete_original':True,
 'new_step':'build-native-node-tracing','step_behavior':'Only addInstallArtifact dependencies for the three new archives; no command, generator, run artifact, test, process startup or global QuickJS link is introduced.',
 'new_archives':['pi-node-abseil','pi-node-tracing-diagnostic','pi-node-tracing'],
 'reused_existing_archives':['pi-node-native-memory','pi-node-network'],
 'existing_QuickJS_final_binary_owner':'pi-quickjs contains engine_abi.c. A later final binary must link that existing owner when consuming tracing; this install-only target does not attempt final binary linkage.',
 'source_counts':{
  'abseil_cpp':110,'new_diagnostic_c':1,'new_diagnostic_cpp':2,'tracing_common_cpp':9,
  'windows_recorder_cpp':2,'linux_recorder_cpp':0,'darwin_recorder_cpp':2,
  'windows_total_new_cpp_units':123,'linux_total_new_cpp_units':121,
  'existing_network_memory_recompiled_as_duplicate_sources':False,
  'counts_are_source_declarations_not_observed_compiler_objects':True
 },
 'actual_source_membership':{'c':cunits,'cpp':cppunits,'abseil_manifest':pin(own/'vendor/node-v24.13.0/abseil-cpp/SOURCE-MANIFEST.json')},
 'single_owner_mapping':[
  {'owner':'pi-node-abseil','sources':'110 unchanged original Abseil .cc units','consumers':'V8Mutex and original Abseil synchronization dependencies','sharing':'One new archive object passed into tracing; no forced alternate mutex or waiter.'},
  {'owner':'pi-node-native-memory (existing)','sources':'native_simdjson_memory.cpp','consumers':'NativeAllocated, rebound STL allocator, Agent native allocation scopes','sharing':'Pass the existing Main memory compile pointer; no second TLS or allocation owner.'},
  {'owner':'pi-node-network (existing)','sources':'existing unchanged libuv cohort and native_node_check_failure.c','consumers':'uv loops/mutex/conditions/worker/fs, Node assertion path','sharing':'Pass the existing network compile pointer; no libuv copy or Node assertion substitute.'},
  {'owner':'pi-node-tracing-diagnostic (new)','sources':'one existing native_node_diagnostic_context.c plus reviewed V8 fatal and clock diagnostic bodies','consumers':'29 immediate C ABI scopes, loop CHECKs, V8 mutex DCHECK, clock fatal checks','sharing':'Exactly one borrowed diagnostic TLS owner per final tracing binary; context-control rewiring needed only if it later shares this owner.'},
  {'owner':'pi-quickjs (existing final binary dependency)','sources':'engine_abi.c owns retain/release/reserve/release functions for native memory','consumers':'Agent::NativeMemoryOwner and native_simdjson_memory.cpp','sharing':'Link existing owner in any future native consumer; never supply stub memory callbacks.'},
  {'owner':'platform imports/runtime','sources':'existing Zig libc/libc++, selected Windows system imports or POSIX/Darwin imports','consumers':'genuine ETW/signpost, clock, native symbol diagnostics and original Abseil','sharing':'Exact contained SDK declaration selection is separately pinned; actual import/metadata validation is pending.'}
 ],
 'link_owner_symbols':[
  {'symbols':['pi_js_retain_memory_owner','pi_js_release_memory_owner','pi_js_native_memory_reserve','pi_js_native_memory_release'],'defined_in':'src/extensions/engine_abi.c','state':'Existing real implementation, required by later final binary; not copied into tracing.'},
  {'symbols':['pi_simd::allocate','pi_simd::release','pi_simd::Scope'],'defined_in':'src/extensions/native_simdjson_memory.cpp','state':'Existing shared native memory owner passed once.'},
  {'symbols':['pi_node_assert_failure'],'defined_in':'src/extensions/native_node_check_failure.c','state':'Existing network owner; selected original static AssertionInfo and guard abort path preserved.'},
  {'symbols':['pi_node_diagnostic_context_current','pi_node_diagnostic_context_enter','pi_node_diagnostic_context_leave'],'defined_in':'src/extensions/native_node_diagnostic_context.c','state':'Existing borrowed TLS source proposed in the sole tracing diagnostic archive.'},
  {'symbols':['ClockCheckFailure','ClockCheckFailureOperands','Unreachable','pi_v8_base_dcheck'],'defined_in':'reviewed provider 5059d6a fatal/clock source unit','state':'Real source exists, not in Main; exact intake prerequisite before this proposal can build.'},
  {'symbols':['V8Mutex::{Lock,Unlock,TryLock}','CheckedUvLoopClose','Recorder::{Recorder,~Recorder,IsEnabled,AddEvent}','TraceWriter::CreateSystemInstrumentationTraceWriter'],'defined_in':'this ten-file platform production packet','state':'Concrete native implementations and body maps supplied; uncompiled.'}
 ],
 'remaining_link_and_bootstrap_owners':[
  {'item':'Complete intake before archive compilation','detail':'Frozen clock/API commits 88fe6ba/1700aeaa, provider fatal 5059d6a and the ten preexisting Agent/controller/core/buffer/writer drafts must be present with this new platform/dependency cohort. The old drafts are pinned dependencies, not newly algorithm-qualified by this platform peer.'},
  {'item':'Executable link consumer','detail':'No final binary or ABI test executable is added. The actual existing pi-quickjs engine_abi memory functions and native Node diagnostic dependencies must resolve at the final executable link. Static archive installation alone cannot establish this.'},
  {'item':'Shared diagnostic test composition','detail':'Current Main diagnostic-context control directly compiles native_node_diagnostic_context.c. Before attaching tracing to that same final binary, replace the direct compilation with a link to this sole diagnostic owner; retain the actual TLS address/lifetime controls. This proposal leaves that standalone test untouched.'},
  {'item':'Process Agent ownership and publication','detail':'Create the process-owned actual Agent with a retained real memory owner, publish/unpublish with existing pi_node_tracing_set_agent in the original initialization/shutdown order, and preserve global category registry single-controller lifetime. None is installed here.'},
  {'item':'Process/environment observer and writer selection','detail':'Actual original trace-state observers and environment async notifications, CLI category/file/SystemInstrumentation writer selection and shutdown/flush ordering remain separate source work. Recorder bodies do not install those observers or choose the active writer.'},
  {'item':'Trace event C ABI / environment callbacks','detail':'The reviewed 29 APIs admit strings/categories/Agent/writer handles and category lookup. They do not yet expose the actual AddTraceEvent/metadata/duration and state-observer lifetime operations required by FS/AsyncWrap/module event owners. No fake callback or generic host bridge is supplied.'},
  {'item':'V8 fatal bootstrap hooks','detail':'The real fatal owner retains null stack/fatal callbacks and original default dcheck; process-selected genuine hook installation remains explicit and unimplemented by this archive recipe.'},
  {'item':'Nonselected ring-buffer factory','detail':'TraceBuffer::CreateTraceBufferRingBuffer is declared in the preexisting private header without a definition in this selection. The selected Node Agent instantiates its actual NodeTraceBuffer and does not call that factory. Broader V8 ring-buffer admission would need its original body.'},
  {'item':'Darwin owners','detail':'Original clock/Recorder/Abseil source is retained, but Main currently supplies network/native-memory owners only for 64-bit Windows/Linux. The proposed build step is created only when both actual owners exist, so it does not claim Darwin Agent assembly.'},
  {'item':'Actual SDK/compiler/link/runtime qualification','detail':'Zig/Clang acceptance of original Microsoft extensions, ETW sections/import linkage, Abseil/Node concurrency, observer callbacks and real Recorder behavior are future admission gates; none was executed.'}
 ],
 'source_only_validation':{
  'single_insertion_forward_inverse':True,'new_run_edges':0,'new_test_roots':0,
  'existing_build_bytes_other_than_insertion_unchanged':True,'all_primary_snapshot_pins_still_match':True,
  'native_allocator_header_matches_Main_basis':True,'fatal_production_pins_match':True,
  'main_modified':False,'compiler_execution':False,'preprocessor_execution':False,'native_execution':False
 },
 'production_proposal':pin(packet/'production-proposal.json'),
 'toolchain_selection':pin(packet/'toolchain-and-sdk-selection-proof.json'),
 'original_Main_owner_sources':refs,'reviewed_external_fatal_sources':fatal_pins,
 'qualification':False
}
outp=out/'proposal.json';assert not outp.exists();outp.write_text(json.dumps(d,indent=2)+'\n',encoding='utf-8',newline='\n')
print(json.dumps({'proposal':pin(outp),'base':base,'build_original':pin(orig),'build_projected':pin(proj),'insert_lines':addition.count(b'\n'),'new_build_steps':1,'new_test_roots':0},indent=2))
