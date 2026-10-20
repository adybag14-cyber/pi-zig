from pathlib import Path
import datetime,hashlib,json,re
own=Path(r'C:\Users\adyba\pi-zig\worktrees\modules-io-resume-20261018')
packet=own/'verification/native-node-tracing-platform-sourceonly-20261020'
vendor=own/'vendor/node-v24.13.0/abseil-cpp'
zig=Path(r'C:\Users\adyba\pi-zig\toolchain\zig-x86_64-windows-0.16.0')
mingw=zig/'lib/libc/include/any-windows-any'
def sha(b):return hashlib.sha256(b).hexdigest().upper()
def pin(p):
 b=p.read_bytes();return {'path':str(p),'bytes':len(b),'sha256':sha(b)}
def excerpts(p,ranges):
 ls=p.read_text(encoding='utf-8-sig').splitlines()
 return [dict(start=a,end=min(b,len(ls)),lines=[{'line':n,'text':ls[n-1]} for n in range(a,min(b,len(ls))+1)]) for a,b in ranges]
def around(p,pattern,pad=3):
 ls=p.read_text(encoding='utf-8-sig').splitlines();hits=[]
 for n,l in enumerate(ls,1):
  if re.search(pattern,l):hits.append((max(1,n-pad),min(len(ls),n+pad)))
 ranges=[]
 for a,b in hits:
  if ranges and a<=ranges[-1][1]+1:ranges[-1]=(ranges[-1][0],max(b,ranges[-1][1]))
  else:ranges.append((a,b))
 return excerpts(p,ranges)
def source(p,ranges=None,pattern=None):
 d=pin(p)
 d['excerpts']=around(p,pattern) if pattern else excerpts(p,ranges or [])
 return d
sdk=packet/'authority/windows-sdk/10.0.22621.0/shared/TraceLoggingProvider.h'
assert pin(sdk)['sha256']=='C060AF7E8703386736C651A62686908D509B8B9CB627D898D72A4CA6506901A4'
assert {q.name for q in sdk.parent.iterdir() if q.is_file()}=={'TraceLoggingProvider.h'}
sdk_text=sdk.read_text(encoding='utf-8-sig')
sdk_without_comments=re.sub(r'/\*.*?\*/',lambda m:'\n'*m[0].count('\n'),sdk_text,flags=re.S)
sdk_actual_includes=[{'line':n,'include':m.group(1)} for n,line in enumerate(sdk_without_comments.splitlines(),1) if (m:=re.match(r'\s*#\s*include\s*[<"]([^>"]+)[>"]',line))]
assert sdk_actual_includes==[{'line':80,'include':'evntprov.h'}]
recipes=[own/'tools/build_native_node_abseil.zig',own/'tools/build_native_node_tracing.zig']
for r in recipes:
 assert not re.search(r'"-D(?:ABSL_FORCE_|ABSL_WAITER_MODE|ABSL_THREAD_IDENTITY_MODE|NO_FRAME_POINTER|DEBUG|OFFICIAL_BUILD)',r.read_text())
sources=[
 source(vendor/'absl/synchronization/internal/waiter.h',[(26,66)]),
 source(vendor/'absl/synchronization/internal/win32_waiter.h',[(19,35)]),
 source(vendor/'absl/synchronization/internal/futex_waiter.h',[(19,35)]),
 source(vendor/'absl/synchronization/internal/futex.h',pattern=r'__linux__|ABSL_INTERNAL_HAVE_FUTEX'),
 source(vendor/'absl/synchronization/internal/sem_waiter.h',[(19,36)]),
 source(vendor/'absl/synchronization/internal/pthread_waiter.h',[(19,31)]),
 source(vendor/'absl/synchronization/internal/stdcpp_waiter.h',[(19,49)]),
 source(vendor/'absl/base/config.h',pattern=r'ABSL_HAVE_SEMAPHORE_H|define ABSL_HAVE_THREAD_LOCAL|defined\(__APPLE__\)'),
 source(vendor/'absl/base/internal/thread_identity.h',[(220,288)]),
 source(vendor/'absl/base/internal/thread_identity.cc',[(17,61),(76,122),(130,158)]),
 source(vendor/'absl/debugging/internal/stacktrace_config.h',[(24,93)]),
 source(zig/'lib/std/zig/target.zig',[(291,299),(334,347)]),
 source(zig/'lib/std/Build/Module.zig',[(363,378)]),
 source(zig/'lib/libc/include/any-windows-any/pthread.h',pattern=r'pthread_key_create|pthread_key_delete|pthread_setspecific|pthread_getspecific'),
 source(zig/'lib/libc/mingw/winpthreads/thread.c',pattern=r'^int pthread_key_create|^int pthread_key_delete|^int pthread_setspecific|^void \*pthread_getspecific'),
 source(sdk,[(1,17),(76,90),(149,166),(251,265),(293,315),(2780,2822),(2834,2844),(2964,2972),(3881,3887),(3941,3959),(4483,4519)]),
 source(mingw/'evntprov.h',[(29,43),(56,87),(111,139)]),
 source(mingw/'winapifamily.h',[(1,26)]),
 source(mingw/'guiddef.h',[(1,25)]),
 source(mingw/'windows.h',[(5,10),(63,77)]),
 source(mingw/'windef.h',[(5,22)]),
 source(mingw/'minwindef.h',[(1,8),(155,169)]),
 source(mingw/'winnt.h',[(9,27),(150,163)]),
 source(mingw/'specstrings.h',[(1,17)]),
 source(mingw/'sal.h',pattern=r'#define _IRQL_requires_max_|#define _Inout_cap_|#define _In_reads_bytes_opt_|#define _In_opt_'),
 source(mingw/'sdkddkver.h',[(170,198)]),
 source(mingw/'_mingw.h',[(5,17)]),
 source(mingw/'_mingw_mac.h',pattern=r'MINGW32|MINGW64'),
 source(mingw/'_mingw_secapi.h',[(1,45)]),
 source(mingw/'vadefs.h',[(1,35)]),
 source(packet/'authority/tools__v8_gypfiles__toolchain.gypi',[(505,521)]),
 source(packet/'authority/tools__v8_gypfiles__v8.gyp',[(1649,1696)]),
 source(packet/'authority/tools__v8_gypfiles__features.gypi',[(1,45),(510,525)]),
]
sources.extend(pin(r) for r in recipes)
d={
 'schema':1,'kind':'Pinned original Abseil, contained Windows SDK, and Zig dependency selection source proof',
 'created_utc':datetime.datetime.now(datetime.timezone.utc).isoformat(),
 'production_proposal':pin(packet/'production-proposal.json'),
 'sdk':{
  'version':'10.0.22621.0','contained_original':pin(sdk),'acquisition':pin(packet/'acquisition/windows-sdk-10.0.22621.0-contained.json'),
  'installed_path_is_provenance_not_include_path':True,
  'actual_sdk_includes_after_removing_comments':sdk_actual_includes,
  'selected_evntprov':pin(mingw/'evntprov.h'),
  'include_precedence':'The one-file contained SDK directory provides TraceLoggingProvider.h only. Its evntprov.h resolves to the pinned Zig MinGW family. The original V8 provider includes windows.h before the SDK header. No SDK shared/um/ucrt directory is added.',
  'required_windows_declaration_edges':[
   ['original V8 etw-provider-win.h','Zig MinGW windows.h'],
   ['original V8 etw-provider-win.h','contained SDK TraceLoggingProvider.h'],
   ['contained SDK TraceLoggingProvider.h','Zig MinGW evntprov.h'],
   ['Zig MinGW evntprov.h','Zig MinGW winapifamily.h'],
   ['Zig MinGW evntprov.h','Zig MinGW guiddef.h'],
   ['Zig MinGW guiddef.h','Zig MinGW _mingw.h'],
   ['Zig MinGW windows.h','Zig MinGW sdkddkver.h'],
   ['Zig MinGW windows.h','Zig MinGW windef.h'],
   ['Zig MinGW windef.h','Zig MinGW minwindef.h'],
   ['Zig MinGW minwindef.h','Zig MinGW winnt.h'],
   ['Zig MinGW winnt.h','Zig MinGW specstrings.h'],
   ['Zig MinGW specstrings.h','Zig MinGW sal.h'],
  ],
  'selected_API_path':'Recipe sets original _WIN32_WINNT=0x0A00. sdkddkver.h supplies WINVER from that macro; MinGW evntprov.h declares EventRegister/EventUnregister/EventWriteTransfer/EventSetInformation and defines EVENT_FILTER_TYPE_SCHEMATIZED. Original SDK therefore chooses TLG_HAVE_EVENT_SET_INFORMATION=1 under these declarations, with the direct EventSetInformation path.',
  'original_descriptor_compatibility':'Selected SDK body uses EVENT_DATA_DESCRIPTOR Ptr/Size/Reserved fields and (EVENT_INFO_CLASS)2 rather than requiring a named EventProviderSetTraits enumerator. These fields and EVENT_INFO_CLASS exist in the pinned MinGW header.',
  'additional_SDK_headers_selected':[],
  'MS_extensions':'Recorder sources request -fms-extensions for original SDK __pragma/__declspec. The original __annotation, __fastfail and metadata section emission are retained and still require future actual Zig Clang/MinGW compile/link validation.',
 },
 'waiter_matrix':[
  {'selection':'Windows GNU / MinGW 64-bit','required_predicates':['_WIN32','__MINGW32__','not __linux__'],'waiter':'original StdcppWaiter','thread_identity':'original POSIX_SETSPECIFIC','reason':'Win32 waiter excludes MinGW, pthread waiter excludes Windows/MinGW, futex/semaphore availability is absent on this selection; unchanged priority order reaches StdcppWaiter. ThreadIdentity Windows CPP11 branch also excludes MinGW.'},
  {'selection':'Windows native non-MinGW predicate branch (retained original, not qualified here)','required_predicates':['_WIN32','not __MINGW32__','_WIN32_WINNT>=VISTA'],'waiter':'original Win32Waiter','thread_identity':'original CPP11'},
  {'selection':'Linux non-GRTE selected 64-bit source','required_predicates':['__linux__','not _WIN32','not __GOOGLE_GRTE_VERSION__ special branch'],'waiter':'original FutexWaiter','thread_identity':'original POSIX_SETSPECIFIC'},
  {'selection':'Darwin 64-bit with detected original thread_local','required_predicates':['__APPLE__','ABSL_HAVE_THREAD_LOCAL','not _WIN32'],'waiter':'original PthreadWaiter','thread_identity':'original CPP11','assembly_limit':'Main network and native-memory owners still only admit Windows/Linux; this source selection is not whole-Agent Darwin admission.'},
 ],
 'minGW_pthread_link_owner':{
  'recipe':'build_native_node_abseil.zig requests pthread only for target.result.isMinGW().',
  'Zig_resolution':'lib/std/Build/Module.zig calls isLibCLibName; lib/std/zig/target.zig recognizes pthread and winpthread for MinGW, enabling the existing libc owner instead of creating another archive.',
  'original_implementation_present':pin(zig/'lib/libc/mingw/winpthreads/thread.c'),
  'no_external_pthread_archive_added':True,
 },
 'stacktrace_macro_selection':{
  'macro':'ABSL_STACKTRACE_INL_HEADER',
  'selected_windows':'absl/debugging/internal/stacktrace_win32-inl.inc',
  'selected_darwin_thread_local':'absl/debugging/internal/stacktrace_generic-inl.inc',
  'selected_linux_x64':'absl/debugging/internal/stacktrace_x86-inl.inc',
  'selected_linux_arm64':'absl/debugging/internal/stacktrace_aarch64-inl.inc',
  'NO_FRAME_POINTER':'Not defined by recipe. Original explicit NO_FRAME_POINTER x86/x64/aarch64 libunwind include is not available to open-source users and is not claimed by this finite closure.',
 },
 'sources':sources,
 'method':'Read-only exact hashes and original predicate/declaration inspection. Deductions above are conditional on the recorded target macro family; no preprocessor/compiler was executed.',
 'limits':[
  'The transitive selection records the concrete SDK/MinGW declaration boundary, not a compiler-selected complete Windows header graph.',
  'Compiler built-ins, C++ ABI, Microsoft extension handling, ETW metadata sections, import linkage and runtime provider behavior remain unqualified.',
  'No forced waiter/thread identity, no replacement std mutex, no patched SDK original, no synthesized provider or no-op event path is added.',
  'The entire original Abseil mutex/condition implementation remains present; Node tracing conditions separately retain their original uv_cond_* owner.',
 ],
 'compiler_execution':False,'preprocessor_execution':False,'native_execution':False,'main_modified':False,'qualification':False
}
out=packet/'toolchain-and-sdk-selection-proof.json';assert not out.exists();out.write_text(json.dumps(d,indent=2)+'\n',encoding='utf-8',newline='\n')
print(json.dumps({'proof':pin(out),'source_pins':len(sources),'contained_SDK_files':1,'compiler_execution':False},indent=2))
