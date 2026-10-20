from pathlib import Path
import datetime,hashlib,json,re
own=Path(r'C:\Users\adyba\pi-zig\worktrees\modules-io-resume-20261018')
p=own/'verification/native-node-tracing-platform-sourceonly-20261020'
old=own/'verification/native-node-tracing-sourceonly-20261020/authority'
zig=Path(r'C:\Users\adyba\pi-zig\toolchain\zig-x86_64-windows-0.16.0')
def sha(b):return hashlib.sha256(b).hexdigest().upper()
def pin(x):
 b=x.read_bytes();return {'path':str(x),'bytes':len(b),'sha256':sha(b)}
def excerpt(x,a,b):
 ls=x.read_text().splitlines();return {'source':pin(x),'start':a,'end':b,'lines':[{'line':n,'text':ls[n-1]} for n in range(a,b+1)]}
copied=[]
for name,expected in [
 ('src__node_mutex.h.txt','79FC7058F5380DA98638682684E77F72D4B413753C0BECD621B0D0E2F69600E5'),
 ('deps__v8__src__libplatform__tracing__trace-writer.cc.txt','8E12C3F0978C3E152285F411013A27932A746B13A7A9F0E9FED171EC54002E3E'),
 ('deps__v8__src__libplatform__tracing__trace-writer.h.txt','C3B92D03DEE9F57BA2BC21FC05059C250C405044A4462F49B1D4848832F5F714')
]:
 src=old/name;dest=p/'authority'/name.removesuffix('.txt')
 assert sha(src.read_bytes())==expected and not dest.exists();dest.write_bytes(src.read_bytes())
 copied.append({'original_prior_authority':pin(src),'contained_original':pin(dest),'method':'Byte-exact reuse of existing pinned Node def0bdf8 original; no reacquisition or production change.'})
rec=p/'acquisition/reused-trace-writer-and-node-mutex.json'
assert not rec.exists();rec.write_text(json.dumps({'revision':'def0bdf8abee441cfcbf793a8dc24a6f3b899573','records':copied},indent=2)+'\n',encoding='utf-8',newline='\n')
tracefiles=[x for x in sorted((own/'src/extensions').glob('native_node_tracing*')) if x.suffix in ('.h','.hpp','.cpp','.c')]
guardlines=[];includes=[];lockuses=[];unlocks=[]
for f in tracefiles:
 for n,line in enumerate(f.read_text().splitlines(),1):
  if 'V8_ENABLE_SYSTEM_INSTRUMENTATION' in line:guardlines.append({'path':str(f),'line':n,'text':line})
  if re.match(r'\s*#\s*include\s+"native_node_tracing_recorder.hpp"',line):includes.append({'path':str(f),'line':n,'text':line})
  if f.name!='native_node_tracing_support.hpp':
   if 'ScopedUnlock' in line:unlocks.append({'path':str(f),'line':n,'text':line})
   if re.search(r'Mutex::ScopedLock\s+\w+\(',line):lockuses.append({'path':str(f),'line':n,'text':line})
assert len(guardlines)==2 and all(x['path'].endswith('native_node_tracing_recorder.hpp') for x in guardlines)
assert len(includes)==3 and {Path(x['path']).name for x in includes}=={'native_node_tracing_recorder.cpp','native_node_tracing_recorder_win.cpp','native_node_tracing_recorder_mac.cpp'}
assert len(lockuses)==20 and not unlocks
orig=(p/'authority/src__node_mutex.h').read_text()
live=(own/'src/extensions/native_node_tracing_support.hpp').read_text()
ctor='MutexBase<Traits>::ScopedLock::ScopedLock(const ScopedUnlock& scoped_unlock)\n    : MutexBase(scoped_unlock.mutex_) {}'
assert ctor in orig and ctor in live
core=own/'src/extensions/native_node_tracing_core.hpp'
assert 'static TraceWriter* CreateSystemInstrumentationTraceWriter();' in core.read_text()
d={
 'schema':1,'kind':'Additive source response to independent instrumentation/DEBUG/ScopedLock review questions',
 'created_utc':datetime.datetime.now(datetime.timezone.utc).isoformat(),
 'production_proposal':pin(p/'production-proposal.json'),
 'instrumentation':{
  'all_examined_selected_tracing_files':[pin(f) for f in tracefiles],
  'all_instrumentation_macro_occurrences':guardlines,
  'all_recorder_header_includes':includes,
  'core_factory_declaration':excerpt(core,150,166),
  'conclusion':'The only selected project-header instrumentation guard is the Recorder header requirement. The three Recorder source files include it, and each selected platform compiles the common plus its own Recorder source with V8_ENABLE_SYSTEM_INSTRUMENTATION. Agent/controller/core/buffer/writer/clock/API/loop/platform TUs contain no guard that requires that macro. The private core factory declaration is unconditional. No missing macro propagation was found in this finite selected source graph.',
  'compiler_selection_observed':False
 },
 'debug_mapping':{
  'original_v8_Debug':excerpt(p/'authority/tools__v8_gypfiles__toolchain.gypi',602,606),
  'original_dcheck_always_on':excerpt(p/'authority/tools__v8_gypfiles__features.gypi',453,457),
  'zig_Build_optimize_emission':excerpt(zig/'lib/std/Build/Module.zig',579,585),
  'resource_compiler_separate_rule':excerpt(zig/'lib/std/Build/Module.zig',131,143),
  'recipes':[pin(own/'tools/build_native_node_abseil.zig'),pin(own/'tools/build_native_node_tracing.zig')],
  'explicit_new_Cpp_preprocessor_defines':['_WIN32_WINNT=0x0A00 (Windows)','_GNU_SOURCE (Linux)','V8_ENABLE_SYSTEM_INSTRUMENTATION (selected Windows/Darwin Recorder units)'],
  'not_explicitly_defined_by_recipes':['DEBUG','_DEBUG','NDEBUG','OFFICIAL_BUILD','ABSL_FORCE_WAITER_MODE','ABSL_FORCE_THREAD_IDENTITY_MODE','NO_FRAME_POINTER'],
  'conclusion':'Passing Zig optimize Debug emits -ODebug in the Build layer, not the original V8 GYP DEBUG definition. The documented automatic /D_DEBUG or /DNDEBUG applies to RcSourceFile, which is not used here. These recipes preserve the existing native C++ flag policy and do not claim original V8 Debug-mode equivalence. Actual compiler predefined macros have not been observed.',
  'whole_tracing_DEBUG_limit':'The old core/controller drafts explicitly use their bounded non-DEBUG PI_TRACE_DCHECK selection; they are not upgraded by this platform unit. The new V8Mutex and fatal owner preserve explicit DEBUG branches, but no complete DEBUG tracing admission is claimed.',
  'Abseil_assertion_limit':'Unchanged Abseil sources retain their own NDEBUG/assert predicates. Since no NDEBUG setting is forced, this source work does not claim exact upstream release-build assertion configuration or runtime cost.',
  'SDK_debug_limit':'The genuine SDK TLG_DEBUG selection also considers DBG/DEBUG/_DEBUG/NDEBUG; actual compiler predefines and SDK behavior remain unobserved.'
 },
 'inherited_ScopedLock_constructor':{
  'original':excerpt(p/'authority/src__node_mutex.h',281,295),
  'production':excerpt(own/'src/extensions/native_node_tracing_support.hpp',252,266),
  'exact_original_initializer_preserved':True,
  'selected_ordinary_lock_uses':lockuses,'selected_ordinary_lock_count':20,
  'ScopedUnlock_uses_outside_support':unlocks,
  'source_status':'The unusual constructor is inherited verbatim from pinned src/node_mutex.h, not a newly introduced initializer. The selected tracing call sites only construct ScopedLock from actual Mutex members; no selected consumer mentions ScopedUnlock. Whether the constructor is rejected or remains uninstantiated under a future compiler invocation is not established by this lexical inspection. No speculative correction or compiler-qualification claim is made.'
 },
 'reused_authority_receipt':pin(rec),
 'read_only_replay_wrapper':pin(p/'replay-source-body-proof.py'),
 'sealed_packets_modified':False,'production_modified':False,
 'compiler_execution':False,'preprocessor_execution':False,'native_execution':False,'main_modified':False,'qualification':False
}
dest=p/'instrumentation-debug-and-inherited-constructor-proof.json';assert not dest.exists();dest.write_text(json.dumps(d,indent=2)+'\n',encoding='utf-8',newline='\n')
print(json.dumps({'proof':pin(dest),'replay_wrapper':pin(p/'replay-source-body-proof.py'),'reused_authority':pin(rec)},indent=2))
