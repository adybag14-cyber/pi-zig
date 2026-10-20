"""Static original-body comparison. No compiler, preprocessor, generator, or native execution."""
from pathlib import Path
import hashlib,json,re
P=Path(__file__).parent
O=P.parents[1]
def digest(b):return hashlib.sha256(b).hexdigest().upper()
def pin(path,expected=None):
 b=path.read_bytes();h=digest(b)
 if expected:assert h==expected,(str(path),h,expected)
 return {'path':str(path),'bytes':len(b),'sha256':h}
header=P/'authority/src__tracing__trace_event.h.txt'
cpp=P/'proposal/src/extensions/native_node_tracing_event_api.cpp'
api=P/'proposal/src/extensions/native_node_tracing_event_api.h'
pins=[
 pin(header,'BD14C8D2C10225377540F5C594ECE93BC49D1041EB393D5D4ED48348513BFCFE'),
 pin(cpp,'8CD4D1AF43AF6C0F80304020EB1027C82F72C9B3BFCA68D72FBF0AB1506837EB'),
 pin(api,'454EE9ECD5E84795751A9D1826FCF18B52E3E43513CE70A200A5F41B01C7194F')]
original=header.read_text(encoding='utf-8')
candidate=cpp.read_text(encoding='utf-8')
def body(text,needle):
 start=text.index(needle);begin=text.index('{',start);depth=1;i=begin+1
 while depth:
  if text[i]=='{':depth+=1
  elif text[i]=='}':depth-=1
  i+=1
 return text[begin+1:i-1],text.count('\n',0,begin)+1,text.count('\n',0,i-1)+1
prefix='\n  DiagnosticContextScope diagnostic(context);\n  AllocationScope allocation(memory_owner);\n'
def admitted_body(name):
 b,lo,hi=body(candidate,name+'(');assert b.startswith(prefix),(name,b[:150])
 assert b.count('DiagnosticContextScope')==1 and b.count('AllocationScope')==1
 return b[len(prefix):],lo,hi
def normalize(text):
 text=text.replace('v8::ConvertableToTraceFormat','ConvertableToTraceFormat')
 text=text.replace('v8::TracingController','TracingController')
 text=text.replace('node::tracing::TraceEventHelper','TraceEventHelper')
 text=text.replace('node::tracing::Agent','Agent')
 text=re.sub(r'//[^\n]*','',text)
 return re.sub(r'\s+','',text)
comparisons=[]
for src,dst in [
 ('static inline const uint8_t* GetCategoryGroupEnabled','pi_node_tracing_event_category_enabled'),
 ('static inline uint64_t AddTraceEventImpl','pi_node_tracing_event_add'),
 ('static V8_INLINE uint64_t AddTraceEventWithTimestampImpl','pi_node_tracing_event_add_with_timestamp'),
 ('static V8_INLINE void AddMetadataEventImpl','pi_node_tracing_event_add_metadata')]:
 a,alo,ahi=body(original,src);b,blo,bhi=admitted_body(dst)
 extra=[]
 if 'GetCategoryGroupEnabled' in src:
  assert a.count(' = GetTracingController();')==1
  a=a.replace(' = GetTracingController();',' = TraceEventHelper::GetTracingController();')
  extra=['Qualify the original class-local GetTracingController call through the same TraceEventHelper class at the free C boundary.']
 assert normalize(a)==normalize(b),(dst,normalize(a),normalize(b))
 comparisons.append({'original_symbol':src,'candidate_symbol':dst,
  'authority_lines':[alo,ahi],'candidate_lines':[blo,bhi],
  'extra_normalization':extra,'normalized_original':normalize(a),
  'normalized_candidate':normalize(b),'equal':True})
lines=original.splitlines()
macro_lines=lines[116:120]
assert macro_lines[0].startswith('#define TRACE_EVENT_API_UPDATE_TRACE_EVENT_DURATION')
macro='\n'.join(macro_lines[1:]).replace('\\','')
scoped_start=original.index('class ScopedTracer')
call_start=original.index('TRACE_EVENT_API_UPDATE_TRACE_EVENT_DURATION(',scoped_start)
call_end=original.index(';',call_start)+1
call=original[call_start:call_end]
expanded=call.replace('TRACE_EVENT_API_UPDATE_TRACE_EVENT_DURATION',macro,1)
for before,after in [('data_.category_group_enabled','category_group_enabled'),('data_.name','name'),('data_.event_handle','handle')]:
 assert expanded.count(before)==1
 expanded=expanded.replace(before,after)
b,blo,bhi=admitted_body('pi_node_tracing_event_update_duration')
assert normalize(expanded)==normalize(b),(normalize(expanded),normalize(b))
comparisons.append({'original_symbol':'TRACE_EVENT_API_UPDATE_TRACE_EVENT_DURATION and ScopedTracer destructor invocation',
 'authority_macro_lines':[117,120],'authority_call_lines':[692,693],
 'caller_guard_retained_outside_raw_entry':'ScopedTracer p_data_ and enabled-byte guard at lines 690-694 belongs to the producer lifetime.',
 'candidate_symbol':'pi_node_tracing_event_update_duration','candidate_lines':[blo,bhi],
 'extra_normalization':['Expand only the exact named macro at the actual ScopedTracer invocation.','Bind its data_.category_group_enabled, data_.name and data_.event_handle operands to the three C parameters.'],
 'normalized_original':normalize(expanded),'normalized_candidate':normalize(b),'equal':True})
names=re.findall(r'\b(pi_node_tracing_event_[a-z_]+)\s*\(',api.read_text(encoding='utf-8'))
definitions=re.findall(r'extern "C" [^{;]*?\b(pi_node_tracing_event_[a-z_]+)\s*\(',candidate)
assert len(names)==len(set(names))==len(definitions)==5
assert sorted(names)==sorted(definitions)
build=json.loads((P/'build-proposal.json').read_text(encoding='utf-8'))
a=Path(build['original']['path']).read_bytes();b=Path(build['projected']['path']).read_bytes()
for record in [build['original'],build['projected']]:pins.append(pin(Path(record['path']),record['sha256']))
e=build['edits'][0];before=e['before'].encode();after=e['after'].encode()
assert a.count(before)==b.count(after)==1
assert a.replace(before,after,1)==b and b.replace(after,before,1)==a
stable=[
 ('src/extensions/native_node_tracing_api.h','6AA6586C71DAE6E72F1A59860E54F550E076AC9BEFFFA67264C59FD6A3CFFEA3'),
 ('src/extensions/native_node_tracing_api.cpp','C747E51D8813DE4697B91B8EA7B723A7D442AF6B1BEE98EAC35499AB3BFF7993'),
 ('src/extensions/native_node_tracing_core.hpp','C41AA33C90695AE0CD3887C052E7FD40E950CE917B808313C392848EA66B7F53'),
 ('src/extensions/native_node_tracing_core.cpp','3C4E500BE25DFD39FC93BFFB61A137CDB4AED95862716413367B85B7E68D5332'),
 ('src/extensions/native_node_tracing_controller.hpp','03B722CC934185543B960EDB5CBEE537786C5C920416E80B019A0B5B481CAB83'),
 ('src/extensions/native_node_tracing_controller.cpp','B80F6BEB5D4B3848214569FF0D871D38C62BC5AEC3D35F9BC8BEEE5B64E8D0BC'),
 ('src/extensions/native_node_tracing_agent.hpp','D7B4F316372F7897E325108D84C2D5645CD49AB718FADC3B152328E3CE82B016'),
 ('src/extensions/native_node_tracing_agent.cpp','14BAE7F832AA2DCFA839C652173D9B13D8E4A380F317C1B34160BCF353BB58B0'),
 ('src/extensions/native_node_tracing_buffer.hpp','3F3A289C1C695AF7BB7A84E1BFC08B2BA6D823D513AEF26C864CF10F94397B32'),
 ('src/extensions/native_node_tracing_buffer.cpp','F8AF213F5F5CEB903651CA0B8D91F2437DE48D1A91E96F1C243FF55FDEEBCB2F'),
 ('src/extensions/native_node_tracing_writer.hpp','A4B15B27A91E5FDDF986B59C7D3C94D595E1C843F4A732484534A3DF31E53376'),
 ('src/extensions/native_node_tracing_writer.cpp','DB994685F7E370ACF1C3423E76DB36E7C37F74DEA48F4B3EF98CFCD36FF08893'),
 ('src/extensions/native_node_tracing_clock.cpp','E0408BD2D94D728FACD1E2B36C7DD831BEF49E12BF53C52FE60D602D001B0064'),
 ('src/extensions/native_node_tracing_clock.hpp','F7AE55D36E54D64AC7FA36CF6F64D06A631889213EE0E43998F8701004338E98'),
 ('tools/build_native_node_tracing.zig','A42B1433A277097BE8FDC7E6A670FEDB94DC5CCC58397C6A864F1BC06206D20A')]
for rel,h in stable:pins.append(pin(O/rel,h))
proof={'schema':'pi-zig.tracing-event-five-body-source-proof.v1',
 'qualification':'Source-only exact body adaptation and one-line recipe projection; not compiled, linked or executed.',
 'inputs':pins,'scopes_first_for_all_five':True,'matching_C_declaration_definition_names':sorted(names),
 'normalization':['Remove exactly the two leading admission-scope declarations, after checking their order.','Map only the four original namespace-qualified type/helper names listed in the checker.','Ignore line comments and whitespace in these string-free operation bodies.'],
 'comparisons':comparisons,'comparison_count':len(comparisons),'all_equal':True,
 'build_one_line_forward_inverse_exact':True,'submitted_old_sources_unchanged':True,
 'main_or_production_writes':False}
out=P/'source-body-proof.json';assert not out.exists();payload=(json.dumps(proof,indent=2)+'\n').encode();out.write_bytes(payload)
print(json.dumps({'path':str(out),'bytes':len(payload),'sha256':digest(payload),'comparisons':len(comparisons),'passed':True}))
