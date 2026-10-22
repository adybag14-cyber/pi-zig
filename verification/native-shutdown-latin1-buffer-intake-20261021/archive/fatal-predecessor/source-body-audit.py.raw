from pathlib import Path
import re,json,hashlib,difflib
p=Path(r"C:\Users\adyba\pi-zig\worktrees\provider-af-resume-20261018")
a=p/"verification/native-v8-fatal-tracing-sourceonly-20261020/authority"
cc=(p/"src/extensions/native_v8_base_fatal.cpp").read_text(encoding="utf-8")
diag=(p/"src/extensions/native_node_tracing_clock_diagnostics.cpp").read_text(encoding="utf-8")
log=(a/"deps__v8__src__base__logging.cc").read_text(encoding="utf-8")
win=(a/"deps__v8__src__base__platform__platform-win32.cc").read_text(encoding="utf-8")
pos=(a/"deps__v8__src__base__platform__platform-posix.cc").read_text(encoding="utf-8")
lh=(a/"deps__v8__src__base__logging.h").read_text(encoding="utf-8")
token=re.compile(r'//[^\n]*|/\*[\s\S]*?\*/|"(?:\\.|[^"\\])*"|\'(?:\\.|[^\'\\])*\'|[A-Za-z_]\w*|\d+|\S')
def toks(s):return [m.group() for m in token.finditer(s) if not m.group().startswith(("//","/*"))]
def body(s,mark):
 start=s.index("{",s.index(mark));depth=0
 for m in token.finditer(s,start):
  x=m.group()
  if x=="{":depth+=1
  elif x=="}":
   depth-=1
   if depth==0:return s[start+1:m.start()]
 raise AssertionError(mark)
def rename(s):
 for old,new in [
  ("v8::base::OS::",""),("v8::base::ControlledCrashesAreHarmless","ControlledCrashesAreHarmless"),
  ("v8::base::DcheckFailuresAreIgnored","DcheckFailuresAreIgnored"),
  ("v8::base::g_fatal_function","g_fatal_function"),("v8::base::g_print_stack_trace","g_print_stack_trace"),
  ("v8::base::g_dcheck_function","g_dcheck_function"),("OS::Abort()","pi_v8_base_abort()"),
  ("Abort();","pi_v8_base_abort();"),("V8_Fatal(","pi_v8_base_fatal("),
  ("AbortMode::kExitWithSuccessAndIgnoreDcheckFailures","PI_V8_BASE_EXIT_WITH_SUCCESS_AND_IGNORE_DCHECK_FAILURES"),
  ("AbortMode::kExitWithFailureAndIgnoreDcheckFailures","PI_V8_BASE_EXIT_WITH_FAILURE_AND_IGNORE_DCHECK_FAILURES"),
  ("AbortMode::kImmediateCrash","PI_V8_BASE_IMMEDIATE_CRASH_MODE"),
  ("AbortMode::kDefault","PI_V8_BASE_DEFAULT_ABORT_MODE"),("g_abort_mode","pi_v8_base_g_abort_mode"),
  ("IMMEDIATE_CRASH()","PI_V8_BASE_IMMEDIATE_CRASH()"),("OS::",""),
  ("LOG_TAG",'"v8"'),("OOMType::kProcess","PI_V8_BASE_OOM_PROCESS")]:
  s=s.replace(old,new)
 return re.sub(r"(?<!:)\bDebugBreak\(\);","DebugBreakNative();",s)
results=[]
def check(name,left,right):
 x=toks(rename(left));y=toks(right)
 ok=x==y
 results.append({"check":name,"match":ok,"original_tokens":len(x),"production_tokens":len(y)})
 if not ok:
  sm=difflib.SequenceMatcher(a=x,b=y)
  results[-1]["differences"]=[{"original":x[i:j],"production":y[k:l]} for op,i,j,k,l in sm.get_opcodes() if op!="equal"][:5]
orig=log[log.index("  va_list arguments;",log.index("#ifdef DEBUG\nvoid V8_Fatal")):log.index("\n}\n\nvoid V8_Dcheck")]
new=cc[cc.index("  va_list arguments;",cc.index('#ifdef DEBUG\nextern "C" void pi_v8_base_fatal')):cc.index('\n}\n\nextern "C" void pi_v8_base_dcheck')]
check("fatal complete body after build-selected signature",orig,new)
check("Dcheck dispatch/ignored mode",body(log,"void V8_Dcheck("),body(cc,'extern "C" void pi_v8_base_dcheck('))
check("DefaultDcheck handler",body(log,"void DefaultDcheckHandler(const char* file, int line, const char* message) {"),body(cc,"void DefaultDcheckHandler(const char* file, int line, const char* message) {"))
check("print-stack setter",body(log,"void SetPrintStackTrace("),body(cc,'extern "C" void pi_v8_base_set_print_stack_trace('))
check("Dcheck setter",body(log,"void SetDcheckFunction("),body(cc,'extern "C" void pi_v8_base_set_dcheck_function('))
check("fatal setter",body(log,"void SetFatalFunction("),body(cc,'extern "C" void pi_v8_base_set_fatal_function('))
check("FatalOOM",body(log,"void FatalOOM("),body(cc,'extern "C" void pi_v8_base_fatal_oom('))
check("Windows HasConsole",body(win,"static bool HasConsole("),body(cc,"static bool HasConsole("))
check("Windows VPrintHelper",body(win,"static void VPrintHelper("),body(cc,"static void VPrintHelper("))
check("Windows and POSIX PrintError",body(win,"void OS::PrintError("),body(cc,"void PrintError("))
check("POSIX PrintError agrees with Windows",body(pos,"void OS::PrintError("),body(cc,"void PrintError("))
new_abort=body(cc,'extern "C" void pi_v8_base_abort(')
a_win=new_abort.split("#if defined(_WIN32) && !defined(__CYGWIN__)\n",1)[1].split("#else\n",1)[0]
a_pos=new_abort.split("#else\n",1)[1].rsplit("#endif",1)[0]
check("Windows OS Abort",body(win,"void OS::Abort("),a_win)
check("POSIX OS Abort",body(pos,"void OS::Abort("),a_pos)
old_op=body(lh,"V8_NOINLINE std::string* MakeCheckOpString(").replace("PrintCheckOperand<Lhs>","PrintCheckOperand").replace("PrintCheckOperand<Rhs>","PrintCheckOperand")
check("integral MakeCheckOpString",old_op,body(diag,"PI_V8_BASE_NOINLINE std::string* MakeCheckOpString("))


hdr=(p/"src/extensions/native_v8_base_fatal.h").read_text(encoding="utf-8")
imm=(a/"deps__v8__src__base__immediate-crash.h").read_text(encoding="utf-8")
aborth=(a/"deps__v8__src__base__abort-mode.h").read_text(encoding="utf-8")
def toks(s):
 s=re.sub(r'\\\r?\n','',s)
 return [m.group() for m in token.finditer(s) if not m.group().startswith(("//","/*"))]
new_vsn=body(cc,"int VSNPrintF(")
before,tail=new_vsn.split("#if defined(_WIN32) && !defined(__CYGWIN__)\n",1)
w,tail=tail.split("#else\n",1)
q,after=tail.split("#endif\n",1)
check("Windows VSNPrintF complete selected body",body(win,"int OS::VSNPrintF("),before+w+after)
check("POSIX VSNPrintF complete selected body",body(pos,"int OS::VSNPrintF("),before+q+after)
check("Windows debugger break",body(win,"void OS::DebugBreak(").replace("V8_CC_MSVC","defined(_MSC_VER)"),body(cc,"void DebugBreakNative("))
check("ControlledCrashesAreHarmless",body(aborth,"bool ControlledCrashesAreHarmless("),body(cc,"bool ControlledCrashesAreHarmless("))
check("DcheckFailuresAreIgnored",body(aborth,"bool DcheckFailuresAreIgnored("),body(cc,"bool DcheckFailuresAreIgnored("))
check("FailureMessage complete marker/buffer class",body(log,"class FailureMessage {").replace("arraysize(message_)","sizeof(message_)"),body(cc,"class FailureMessage {"))
vp=body(cc,"void VPrintError(")
_,tail=vp.split("#if defined(_WIN32) && !defined(__CYGWIN__)\n",1)
win_vp,pos_vp=tail.split("#elif defined(ANDROID) && !defined(V8_ANDROID_LOG_STDOUT)\n",1)
check("Windows VPrintError selected body",body(win,"void OS::VPrintError("),win_vp)
check("POSIX VPrintError including Android guard",body(pos,"void OS::VPrintError("),"#if defined(ANDROID) && !defined(V8_ANDROID_LOG_STDOUT)\n"+pos_vp)
names={
 "V8_CC_GNU":"defined(__GNUC__)","V8_CC_MSVC":"defined(_MSC_VER)",
 "V8_HOST_ARCH_X64":"defined(_M_X64) || defined(__x86_64__)",
 "V8_HOST_ARCH_IA32":"defined(_M_IX86) || defined(__i386__)",
 "V8_HOST_ARCH_ARM":"defined(__ARMEL__)",
 "V8_HOST_ARCH_ARM64":"defined(__AARCH64EL__) || defined(_M_ARM64)",
 "V8_HOST_ARCH_PPC64":"defined(__PPC64__) || defined(_ARCH_PPC64)",
 "V8_HOST_ARCH_S390X":"defined(__s390x__)",
 "V8_OS_DARWIN":"defined(__APPLE__)","V8_OS_AIX":"defined(_AIX)","V8_OS_ZOS":"defined(__MVS__)",
 "TRAP_SEQUENCE1_":"PI_V8_BASE_TRAP_SEQUENCE1_","TRAP_SEQUENCE2_":"PI_V8_BASE_TRAP_SEQUENCE2_",
 "TRAP_SEQUENCE_":"PI_V8_BASE_TRAP_SEQUENCE_","WRAPPED_TRAP_SEQUENCE_":"PI_V8_BASE_WRAPPED_TRAP_SEQUENCE_",
 "IMMEDIATE_CRASH":"PI_V8_BASE_IMMEDIATE_CRASH"}
def remap(s,d):return re.sub(r"\b[A-Za-z_]\w*\b",lambda m:d.get(m.group(),m.group()),s)
im_body=imm[imm.index("#if V8_CC_GNU\n"):imm.rindex("#endif  // V8_BASE_IMMEDIATE_CRASH_H_")]
new_im=hdr[hdr.index("#if defined(__GNUC__)\n"):hdr.index("// logging.h preserves")]
x=toks(remap(im_body,names));y=toks(new_im)
results.append({"check":"complete immediate-crash macro body with v8config native compiler/host predicate projection","match":x==y,"original_tokens":len(x),"production_tokens":len(y),"mapping":names})
if x!=y:
 results[-1]["differences"]=[{"original":x[i:j],"production":y[k:l]} for op,i,j,k,l in difflib.SequenceMatcher(a=x,b=y).get_opcodes() if op!="equal"][:5]
mn={"FATAL":"PI_V8_BASE_FATAL","FATAL_HELPER":"PI_V8_BASE_FATAL_HELPER_","FATAL_DISCARD_ARG":"PI_V8_BASE_FATAL_DISCARD_ARG_","GRACEFUL_FATAL":"PI_V8_BASE_GRACEFUL_FATAL","CHECK_FAILED_HANDLER":"PI_V8_BASE_CHECK_FAILED_HANDLER","V8_Fatal":"pi_v8_base_fatal","IMMEDIATE_CRASH":"PI_V8_BASE_IMMEDIATE_CRASH"}
def selected_macros(s,want):
 s=re.sub(r'\\\r?\n','',s)
 return [m.group() for m in re.finditer(r"^#define\s+([A-Za-z_]\w*)[^\n]*",s,re.M) if m.group(1) in want]
wanted_macros={"FATAL","GRACEFUL_FATAL","FATAL_HELPER","FATAL_DISCARD_ARG","CHECK_FAILED_HANDLER"}
origdefs=selected_macros(lh,wanted_macros)
newdefs=selected_macros(hdr,{mn[k] for k in wanted_macros})
x=[toks(remap(s,mn)) for s in origdefs];y=[toks(s) for s in newdefs]
results.append({"check":"all nine selected FATAL/GRACEFUL/CHECK_FAILED macro definitions in original order","match":x==y,"original_definitions":len(x),"production_definitions":len(y),"mapping":mn})
if x!=y:results[-1]["different_definitions"]=[{"original":u,"production":v}for u,v in zip(x,y)if u!=v]
declared=set(re.findall(r"\b(pi_v8_base_(?:set_print_stack_trace|set_dcheck_function|set_fatal_function|dcheck|fatal|fatal_oom|abort))\s*\(",hdr.split("#endif  // __cplusplus")[0].split('}  // extern "C"')[0]))
defined=set(re.findall(r'extern "C" void (pi_v8_base_\w+)\s*\(',cc))
results.append({"check":"seven direct C owner declaration/definition names","match":declared==defined and len(defined)==7,"declarations":sorted(declared),"definitions":sorted(defined)})

packet=p/"verification/native-v8-fatal-tracing-sourceonly-20261020"
pins=[]
paths=[
 p/"src/extensions/native_v8_base_fatal.h",
 p/"src/extensions/native_v8_base_fatal.cpp",
 p/"src/extensions/native_node_tracing_clock_diagnostics.cpp",
 a/"deps__v8__src__base__logging.cc",
 a/"deps__v8__src__base__logging.h",
 a/"deps__v8__src__base__abort-mode.h",
 a/"deps__v8__src__base__immediate-crash.h",
 a/"deps__v8__src__base__platform__platform-win32.cc",
 a/"deps__v8__src__base__platform__platform-posix.cc",
 a/"deps__v8__include__v8config.h",
 a/"deps__v8__src__base__build_config.h",
 a/"deps__v8__src__base__abort-mode.cc",
]
for path in paths:
 b=path.read_bytes()
 pins.append({"path":str(path),"bytes":len(b),"sha256":hashlib.sha256(b).hexdigest().upper()})
receipt=packet/"source-body-proof.json"
obj={"schema":1,"source_only":True,"native_or_compiler_executed":False,
 "validation_kind":"read-only lexical source body comparison; comments and C line splices/whitespace removed; string literal content retained",
 "whole_original_function_renames":"V8/OS names mapped to the prefixed owner and local helpers; original enum names mapped to the identical ordinal C API names; template operand types specialized to int64_t; arraysize(message_) maps to sizeof(char[512]); native DebugBreak remains ::DebugBreak",
 "pins":pins,"checks":results,"count":len(results),"all_source_matches":all(x["match"]for x in results),
 "retained_attempt":{"path":"source-body-proof-attempt1.json","sha256":"6125C5548D56B69F385DCB65F4021FBB37232402ADAF0A77E7D8FAC92D5680ED",
 "failures":[
 "The broad FATAL selector included two separately audited IMMEDIATE_CRASH definitions. It is narrowed to the five intended owner macro names, producing nine definitions in original order.",
 "The general DebugBreak rename also renamed the original ::DebugBreak API token inside the helper. The corrected rename excludes colon-qualified native API names."],
 "production_changes":"none; both failures were audit projection defects"},
 "limitations":["No C/C++ preprocessing, compilation, native execution, death test, concurrency test, platform qualification, target inclusion, linkage or runtime result.",
 "Predicate substitutions refer to the mutually coherent native compiler/host selections in pinned v8config.h; arbitrary contradictory manually defined host/compiler macros are outside this bounded projection.",
 "The runtime entry and default hook installation remain separate process-bootstrap integration work."]}
b=(json.dumps(obj,indent=2)+"\n").encode()
if receipt.exists():assert receipt.read_bytes()==b
else:receipt.write_bytes(b)
assert obj["all_source_matches"], [x for x in results if not x["match"]]
print(json.dumps({"proof":str(receipt),"bytes":len(b),"sha256":hashlib.sha256(b).hexdigest().upper(),"source_checks":len(results),"all_source_matches":True,"native_or_compiler_executed":False}))

