from pathlib import Path
import datetime,hashlib,json,re,subprocess
own=Path(r'C:\Users\adyba\pi-zig\worktrees\modules-io-resume-20261018')
packet=own/'verification/native-node-tracing-platform-sourceonly-20261020'
vendor=own/'vendor/node-v24.13.0/abseil-cpp'
def sha(b):return hashlib.sha256(b).hexdigest().upper()
def pin(p):
 b=p.read_bytes();return {'path':str(p),'bytes':len(b),'sha256':sha(b)}
def write_new(p,d):
 b=(json.dumps(d,indent=2)+'\n').encode();p.parent.mkdir(parents=True,exist_ok=True);assert not p.exists();p.write_bytes(b);return pin(p)
records={}
receipts=[]
for p in sorted((packet/'acquisition').glob('abseil-*-attempt1.json')):
 d=json.loads(p.read_text());receipts.append(pin(p))
 for x in d['records']:
  assert x['ok'];rel=x['relative_path'];assert rel not in records
  b=(vendor/rel).read_bytes();assert sha(b)==x['sha256'] and len(b)==x['bytes']
  records[rel]={'path':rel,'bytes':len(b),'sha256':sha(b),'url':x['url'],'acquisition':str(p),'method':x['method']}
assert len(records)==350
p=packet/'acquisition/closure-000-004-attempt1.json';receipts.append(pin(p))
for x in json.loads(p.read_text())['records']:
 if 'vendor/node-v24.13.0/abseil-cpp/' not in x['relative_path']:continue
 assert x['ok'];rel=x['relative_path'].split('vendor/node-v24.13.0/abseil-cpp/',1)[1];assert rel not in records
 b=(vendor/rel).read_bytes();assert sha(b)==x['sha256']
 records[rel]={'path':rel,'bytes':len(b),'sha256':sha(b),'url':x['url'],'acquisition':str(p),'method':'bounded_https_original_source_bytes_after_missing_include_discovery'}
assert len(records)==353
assert set(records)=={p.relative_to(vendor).as_posix() for p in vendor.rglob('*') if p.is_file()}
gyp=packet/'authority/tools__v8_gypfiles__abseil.gyp'
gyp_members=re.findall(r"'<\(ABSEIL_ROOT\)/(.*?)'",gyp.read_text())
gyp_cpp=[x for x in gyp_members if x.endswith('.cc')]
recipe=own/'tools/build_native_node_abseil.zig'
recipe_cpp=re.findall(r'"(absl/[^"]+\.cc)"',recipe.read_text())
assert len(gyp_members)==349 and len(gyp_cpp)==110 and gyp_cpp==recipe_cpp
manifest={
 'schema':1,'kind':'Unchanged original Node Abseil dependency cohort',
 'node_version':'v24.13.0','node_revision':'def0bdf8abee441cfcbf793a8dc24a6f3b899573',
 'original_gyp':pin(gyp),'gyp_members':349,'cpp_units':110,
 'additional_literal_headers':sorted(set(records)-set(gyp_members)-{'LICENSE'}),
 'license':'LICENSE','total_original_files':353,'original_bytes_unchanged':True,
 'files':[records[k] for k in sorted(records)],'acquisition_receipts':receipts,
 'compiler_execution':False,'native_execution':False,'source_generator_execution':False,
 'source_graph_only':True,'qualification':False,
}
manifest_pin=write_new(vendor/'SOURCE-MANIFEST.json',manifest)
edges=[];missing=[];nonlocal=[];macro=[]
for rel in sorted(records):
 p=vendor/rel
 for n,line in enumerate(p.read_text(encoding='utf-8').splitlines(),1):
  m=re.match(r'\s*#\s*include\s*[<"]([^>"]+)[>"]',line)
  if m:
   inc=m.group(1)
   if inc.startswith('absl/'):
    edges.append({'source':rel,'line':n,'include':inc})
    if inc not in records:missing.append(edges[-1])
   elif '"' in line and not((p.parent/inc).is_file() or(vendor/inc).is_file()):nonlocal.append({'source':rel,'line':n,'include':inc})
  elif re.match(r'\s*#\s*include\s+',line):macro.append({'source':rel,'line':n,'directive':line.strip()})
assert not missing and not nonlocal
assert macro==[{'source':'absl/debugging/stacktrace.cc','line':51,'directive':'#include ABSL_STACKTRACE_INL_HEADER'}]
graph={
 'kind':'Finite literal header and original compilation membership closure',
 'manifest':manifest_pin,'recipe':pin(recipe),'original_gyp':pin(gyp),
 'compilation_members_exact_in_original_order':True,'cpp_units':110,
 'literal_absl_include_edges':len(edges),'all_literal_absl_and_local_quoted_includes_resolve':True,
 'macro_includes':macro,
 'macro_selection_authority':pin(vendor/'absl/debugging/internal/stacktrace_config.h'),
 'macro_selection_notes':[
  'Windows selects original stacktrace_win32-inl.inc.',
  'Darwin with original detected thread_local selects stacktrace_generic-inl.inc.',
  'Declared Linux x86/x64/aarch64 with NO_FRAME_POINTER undefined select original architecture includes; other original branches are retained.',
  'The unavailable open-source stacktrace_libunwind-inl.inc is referenced only by the original explicit NO_FRAME_POINTER branch for selected Linux architectures. The recipe does not define that macro and does not claim that branch.',
  'This lexical graph includes all conditional literal edges. It does not run a preprocessor or predict selected compiler objects/symbols.'
 ],
 'edges':edges,'unresolved_internal_includes':missing,'unresolved_local_quoted_includes':nonlocal,
 'compiler_execution':False,'native_execution':False,'preprocessor_execution':False,'qualification':False
}
graph_pin=write_new(packet/'abseil-source-graph-proof.json',graph)
v8=own/'vendor/node-v24.13.0/v8-tracing'
v8records=[]
for name,url in [('etw-provider-win.h','deps/v8/src/libplatform/etw/etw-provider-win.h'),('LICENSE','deps/v8/LICENSE')]:
 p=v8/name;item=pin(p);item['path']=name;item['url']='https://raw.githubusercontent.com/nodejs/node/def0bdf8abee441cfcbf793a8dc24a6f3b899573/'+url;v8records.append(item)
v8pin=write_new(v8/'SOURCE-MANIFEST.json',{'schema':1,'kind':'Unchanged original V8 ETW provider declaration and license','revision':'def0bdf8abee441cfcbf793a8dc24a6f3b899573','files':v8records,'original_bytes_unchanged':True,'compiler_execution':False,'native_execution':False})
primary=[
 'src/extensions/native_node_tracing_platform.hpp','src/extensions/native_node_tracing_platform.cpp',
 'src/extensions/native_node_tracing_support.hpp','src/extensions/native_node_tracing_loop.cpp',
 'src/extensions/native_node_tracing_recorder.hpp','src/extensions/native_node_tracing_recorder.cpp',
 'src/extensions/native_node_tracing_recorder_win.cpp','src/extensions/native_node_tracing_recorder_mac.cpp',
 'tools/build_native_node_abseil.zig','tools/build_native_node_tracing.zig',
]
productions=[]
for rel in primary:
 source=own/rel;snapshot=packet/'production'/rel;b=source.read_bytes();snapshot.parent.mkdir(parents=True,exist_ok=True);assert not snapshot.exists();snapshot.write_bytes(b)
 item={'path':rel,'live':pin(source),'snapshot':pin(snapshot)}
 if rel.endswith('native_node_tracing_support.hpp'):item['original']=pin(packet/'original/native_node_tracing_support.hpp')
 else:item['new_file']=True
 productions.append(item)
frozen=[
 ('src/extensions/native_node_tracing_clock.cpp','E0408BD2D94D728FACD1E2B36C7DD831BEF49E12BF53C52FE60D602D001B0064'),
 ('src/extensions/native_node_tracing_clock.hpp','F7AE55D36E54D64AC7FA36CF6F64D06A631889213EE0E43998F8701004338E98'),
 ('src/extensions/native_node_tracing_api.cpp','C747E51D8813DE4697B91B8EA7B723A7D442AF6B1BEE98EAC35499AB3BFF7993'),
 ('src/extensions/native_node_tracing_api.h','6AA6586C71DAE6E72F1A59860E54F550E076AC9BEFFFA67264C59FD6A3CFFEA3'),
]
frozen_pins=[]
for rel,expected in frozen:
 q=pin(own/rel);assert q['sha256']==expected;(frozen_pins.append(q))
drafts=[]
for stem in ['core','controller','buffer','writer','agent']:
 for ext in ['hpp','cpp']:drafts.append(pin(own/f'src/extensions/native_node_tracing_{stem}.{ext}'))
body_pin=pin(packet/'source-body-proof-v2.json');assert body_pin['sha256']=='69154F80BF1982B21A35018964F1B59D110008235B382FC261163A557354378D'
d={
 'schema':1,'kind':'Concrete tracing platform and dependency production proposal for independent source peer',
 'created_utc':datetime.datetime.now(datetime.timezone.utc).isoformat(),
 'owned_worktree':str(own),'owned_head':'1700aeaa800003130cce60106c243f6f293e81a9',
 'source_only':True,'production_files':productions,
 'abseil_manifest':manifest_pin,'abseil_source_graph':graph_pin,'original_etw_manifest':v8pin,
 'source_body_proof':body_pin,'body_comparisons':41,
 'contained_windows_sdk_header':pin(packet/'authority/windows-sdk/10.0.22621.0/shared/TraceLoggingProvider.h'),
 'windows_sdk_acquisition':pin(packet/'acquisition/windows-sdk-10.0.22621.0-contained.json'),
 'untouched_reviewed_clock_and_api':frozen_pins,
 'preexisting_unchanged_tracing_drafts_required_by_build':drafts,
 'external_source_prerequisites':[
  {'worktree':r'C:\Users\adyba\pi-zig\worktrees\provider-af-resume-20261018','commit':'5059d6a04a29232fa3a39614d7e73e3690472c4f','scope':'native_v8_base_fatal.h/.cpp and native_node_tracing_clock_diagnostics.cpp'},
  {'commit':'2afdf5601ce5e47334bd65157d0c6c9ebfa51beb','scope':'existing native_node_diagnostic_context.c/.h/.hpp; proposed single diagnostic library owner'},
  {'main_source_basis':'2a45648545c961f9008a783ae352f233869505b4','scope':'actual network/libuv/Node assert and native-memory owners; no reimplementation'}
 ],
 'selected_peer_scopes':{
  'mutex_recorder':['V8Mutex/LockGuard + signed int DCHECK mapping','genuine ETW/signpost Recorder and SystemInstrumentationTraceWriter','unchanged vendor provider GUID/header'],
  'node_loop':['static AssertionInfo macro and actual borrowed TLS','original complete loop walk and native symbol context paths'],
  'build':['exact original Abseil 110 C++ membership and transitive headers','single ownership composition and genuine Windows SDK input']
 },
 'limits':[
  'No compiler, preprocessor, native target, Node reference or project generator was executed.',
  'No process V8 fatal hooks or tracing bootstrap/observers are installed by this unit.',
  'The ten preexisting Agent/controller/core/buffer/writer drafts are pinned dependencies, not newly qualified by this finite platform peer.',
  'The recipe has not been wired into Main; existing diagnostic-context tests must reuse its proposed single diagnostic owner before global tracing assembly.',
  'Native/link qualification, Windows SDK/MinGW integration, actual callback/runtime/concurrency controls and complete process/environment observer assembly remain unverified.',
  'Darwin Recorder/clock/Abseil source exists; complete Agent assembly still needs admitted Darwin network and native-memory owners.'
 ],
 'main_modified':False,'compiler_execution':False,'native_execution':False,'qualification':False,
}
proposal_pin=write_new(packet/'production-proposal.json',d)
print(json.dumps({'original_Abseil_files':353,'cpp_units':110,'literal_edges':len(edges),'production_files':len(primary),'body_comparisons':41,'manifest':manifest_pin,'graph':graph_pin,'production_proposal':proposal_pin},indent=2))
