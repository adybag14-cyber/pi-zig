from pathlib import Path
import hashlib,json,re,sys,difflib
own=Path(r'C:\Users\adyba\pi-zig\worktrees\modules-io-resume-20261018')
packet=own/'verification/native-node-tracing-platform-sourceonly-20261020'
old=own/'verification/native-node-tracing-sourceonly-20261020/authority'
def sha(b):return hashlib.sha256(b).hexdigest().upper()
def pin(p):
 b=p.read_bytes();return {'path':str(p),'bytes':len(b),'sha256':sha(b)}
token=re.compile(r'//[^\n]*|/\*.*?\*/|(?:u8|u|U|L)?"(?:\\.|[^"\\])*"|(?:u8|u|U|L)?\'(?:\\.|[^\'\\])*\'|[A-Za-z_][A-Za-z_0-9]*|(?:[0-9]+(?:\.[0-9]*)?)|[^\s]',re.S)
def lex(text):return [m.group() for m in token.finditer(text) if not m.group().startswith(('//','/*'))]
def body(text,anchor,after=None):
 start=text.index(anchor,text.index(after) if after else 0)
 brace=text.index('{',start)
 depth=0
 for match in token.finditer(text,brace):
  t=match.group()
  if t=='{':depth+=1
  elif t=='}':
   depth-=1
   if depth==0:
    end=match.end()
    return text[brace:end],{'first_line':text.count('\n',0,start)+1,'last_line':text.count('\n',0,end)+1}
 raise AssertionError(('unclosed body',anchor))
auth=packet/'authority'
src=own/'src/extensions'
paths={
 'mutex_original':auth/'deps__v8__src__base__platform__mutex.cc',
 'mutex_header_original':auth/'deps__v8__src__base__platform__mutex.h',
 'mutex':src/'native_node_tracing_platform.cpp',
 'mutex_header':src/'native_node_tracing_platform.hpp',
 'win_original':auth/'deps__v8__src__libplatform__tracing__recorder-win.cc',
 'win':src/'native_node_tracing_recorder_win.cpp',
 'mac_original':auth/'deps__v8__src__libplatform__tracing__recorder-mac.cc',
 'mac':src/'native_node_tracing_recorder_mac.cpp',
 'writer_original':old/'deps__v8__src__libplatform__tracing__trace-writer.cc.txt',
 'writer':src/'native_node_tracing_recorder.cpp',
 'loop_original':auth/'src__debug_utils.cc',
 'loop':src/'native_node_tracing_loop.cpp',
 'support_original':packet/'original/native_node_tracing_support.hpp',
 'support':src/'native_node_tracing_support.hpp',
 'node_util':auth/'src__util.h',
 'node_exit':auth/'src__node_exit_code.h',
 'v8_logging':auth/'deps__v8__src__base__logging.h',
}
texts={k:p.read_text() for k,p in paths.items()}
checks=[]
def check(name,left,right,la,ra=None,la_after=None,ra_after=None,project=None):
 a,al=body(texts[left],la,la_after);b,bl=body(texts[right],ra or la,ra_after)
 projected=project(a) if project else a
 aa=lex(projected);bb=lex(b);ok=aa==bb
 record={'name':name,'original':left,'projected':right,'original_lines':al,'projected_lines':bl,'original_body_sha256':sha(a.encode()),'projected_body_sha256':sha(b.encode()),'compared_token_count':len(aa),'equal':ok}
 if not ok:
  record['difference']=list(difflib.unified_diff(aa,bb,fromfile='original projected tokens',tofile='production tokens',n=5))[:70]
 checks.append(record)
for name in ('Lock','Unlock','TryLock'):
 prefix='bool ' if name=='TryLock' else 'void '
 check('V8 Mutex '+name,'mutex_original','mutex',prefix+'Mutex::'+name+'(',prefix+'V8Mutex::'+name+'(')
check('V8 Mutex constructor','mutex_original','mutex','Mutex::Mutex()','V8Mutex::V8Mutex()')
for name in ('AssertHeld','AssertHeldAndUnmark','AssertUnheldAndMark'):
 check('V8 Mutex header '+name,'mutex_header_original','mutex_header','void '+name+'(','void '+name+'(',project=lambda s:s.replace('DCHECK_EQ','PI_TRACE_V8_DCHECK_EQ'))
for la,ra in [('explicit LockGuard(Mutex* mutex)','explicit V8LockGuard(Mutex* mutex)'),('explicit LockGuard(Mutex& mutex)','explicit V8LockGuard(Mutex& mutex)'),('LockGuard(LockGuard&& other)','V8LockGuard(V8LockGuard&& other)'),('~LockGuard()','~V8LockGuard()')]:
 check('V8 guard '+la,'mutex_header_original','mutex_header',la,ra,project=lambda s:s.replace('DCHECK_NOT_NULL','PI_TRACE_V8_DCHECK_NOT_NULL'))
for platform in ('win','mac'):
 for anchor in ('Recorder::Recorder()','Recorder::~Recorder()','bool Recorder::IsEnabled()','bool Recorder::IsEnabled(const uint8_t level)','void Recorder::AddEvent('):
  def select(s):
   if platform!='win' or '#if defined(V8_USE_PERFETTO)' not in s:return s
   a=s.index('#if defined(V8_USE_PERFETTO)')
   b=s.index('#else  // defined(V8_USE_PERFETTO)',a)
   c=s.index('#endif  // !defined(V8_USE_PERFETTO)',b)
   return s[:a]+s[b+len('#else  // defined(V8_USE_PERFETTO)'):c]+s[c+len('#endif  // !defined(V8_USE_PERFETTO)'):]
  check('Recorder '+platform+' '+anchor,platform+'_original',platform,anchor,project=select)
for anchor in ('SystemInstrumentationTraceWriter::SystemInstrumentationTraceWriter()','SystemInstrumentationTraceWriter::~SystemInstrumentationTraceWriter()','void SystemInstrumentationTraceWriter::AppendTraceEvent(','void SystemInstrumentationTraceWriter::Flush()','TraceWriter* TraceWriter::CreateSystemInstrumentationTraceWriter()'):
 check('System writer '+anchor,'writer_original','writer',anchor)
for cls,anchors in {
 'class PosixSymbolDebuggingContext':('PosixSymbolDebuggingContext()','SymbolInfo LookupSymbol(void* address)','bool IsMapped(void* address)','int GetStackTrace(void** frames, int count)'),
 'class Win32SymbolDebuggingContext':('Win32SymbolDebuggingContext()','~Win32SymbolDebuggingContext()','NameAndDisplacement WrappedSymFromAddr(','SymbolInfo WrappedGetLine(','std::string WrappedUnDecorateSymbolName(','SymbolInfo LookupSymbol(void* address)','bool IsMapped(void* address)','int GetStackTrace(void** frames, int count)'),
}.items():
 for anchor in anchors:
  check('Loop symbol '+cls+' '+anchor,'loop_original','loop',anchor,anchor.replace('std::string','String'),la_after=cls,ra_after=cls,project=lambda s:s.replace('USE(','static_cast<void>('))
check('Loop SymbolInfo Display','loop_original','loop','std::string NativeSymbolDebuggingContext::SymbolInfo::Display()','String NativeSymbolDebuggingContext::SymbolInfo::Display()',project=lambda s:s.replace('std::ostringstream','OutputStringStream'))
check('Complete libuv handle diagnostic walk','loop_original','loop','void PrintLibuvHandleInformation(')
check('Checked loop close complete failure sequence','loop_original','loop','void CheckedUvLoopClose(',project=lambda s:s.replace('UNREACHABLE("uv_loop_close() while having open handles")','PI_NODE_TRACE_ERROR_AND_ABORT("Unreachable code reached" ": " "uv_loop_close() while having open handles")'))
marker='namespace pi_node::tracing {\ntemplate <typename Traits> class ConditionVariableBase;'
assert texts['support_original'][texts['support_original'].index(marker):]==texts['support'][texts['support'].index(marker):]
assert '[[noreturn]] void NodeAssertFailure' not in texts['support']
assert 'static const PiNodeAssertionInfo error_and_abort_args' in texts['support']
assert 'pi_node_assert_failure(pi_node_diagnostic_context_current(),' in texts['support']
assert '#define PI_NODE_TRACE_ABORT_NO_BACKTRACE() _exit(134)' in texts['support']
assert 'V(Abort, 134)' in texts['node_exit']
assert 'return new std::string(ss.str());' in texts['v8_logging']
assert 'delete _msg;' in texts['v8_logging']
assert 'delete message;' in texts['mutex']
assert 'std::string* message = new std::string(ss.str());' in texts['mutex']
record={
 'kind':'Finite original C++ body and Node CHECK source proof; no preprocessing or execution',
 'revision':'def0bdf8abee441cfcbf793a8dc24a6f3b899573',
 'input_pins':{k:pin(p) for k,p in paths.items()},
 'comparison':'C++ lexical tokens preserve literal contents; comments and whitespace ignored. Only stated original-name/allocator/selected-feature/diagnostic macro mappings are applied.',
 'checks':checks,'all_body_checks_equal':all(x['equal'] for x in checks),
 'additional_checks':{
  'all_existing_Node_uv_mutex_condvar_and_ContainerOf_bytes_preserved':True,
  'original_undefined_noreturn_assert_helper_removed':True,
  'static_assertion_record_and_actual_borrowed_context_call':True,
  'original_Windows_Node_abort_code_134':True,
  'actual_V8_dcheck_allocated_message_and_delete_on_hook_return':True
 },
 'manual_mapping_notes':[
  'V8 Mutex adds only the existing empty NativeAllocated base; its actual absl::Mutex field and conditional signed int debug level remain original. The release sizeof/alignof assertions are uncompiled controls, not observed results.',
  'V8MutexDcheckEq selects original int/int equality, ordinary ostringstream operand text, the 50-character MakeCheckOpString branch, new std::string, shared pi_v8_base_dcheck, and deletion if the callback returns. The diagnostic expression and file/line are supplied at each actual calling site.',
  'The guard null DCHECK is the original simple boolean DCHECK_NOT_NULL, not an operand-printing comparison. Release macros do not evaluate operands.',
  'The original native symbol object is private to the loop walk. Its ordinary string/stringstream containers and object new use the already admitted native allocation owner; no guest engine pointer is stored. USE return-value discards map to static_cast<void>.',
  'The original Node UNREACHABLE expands ERROR_AND_ABORT with three adjacent string literal tokens; these exact tokens are preserved because ERROR_AND_ABORT stringifies its argument.',
  'The original non-Perfetto Recorder branch is selected. The original empty Darwin destructor and empty SystemInstrumentationTraceWriter::Flush bodies are preserved; they are not invented no-op substitutes.',
  'Node tracing conditions already use the original LibuvMutexTraits uv_cond_* owner in the byte-preserved support suffix. No tracing consumer calls V8 ConditionVariable; the original Abseil CondVar remains part of the unmodified dependency cohort.'
 ],
 'compiler_execution':False,'native_execution':False,'preprocessor_execution':False,'main_modified':False,'qualification':False
}
path=packet/('source-body-proof.json' if record['all_body_checks_equal'] else 'source-body-proof-attempt1.json')
raw=(json.dumps(record,indent=2)+'\n').encode()
assert not path.exists();path.write_bytes(raw)
print(json.dumps({'path':str(path),'sha256':sha(raw),'bytes':len(raw),'checks':len(checks),'equal':sum(x['equal'] for x in checks),'failures':[x for x in checks if not x['equal']]},indent=2))
if not record['all_body_checks_equal']:sys.exit(1)
