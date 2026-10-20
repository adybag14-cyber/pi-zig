"""Independent finite source review only. Reads inputs and creates one new evidence proof."""
from pathlib import Path
import hashlib,json,re,subprocess,ntpath,datetime
B=Path(r"C:\Users\adyba\pi-zig")
W=B/"worktrees/modules-io-resume-20261018"
D=W/"verification/native-node-tracing-event-bootstrap-analysis-20261020"
OUT=B/"evidence/independent-tracing-event-bootstrap-source-peer-20261020"
REV="def0bdf8abee441cfcbf793a8dc24a6f3b899573"
HEAD="c764130caf2f2c7c63728bec0f6d1e16ac5c59a4"
inputs={}
def sha(b):return hashlib.sha256(b).hexdigest().upper()
def key(p):return ntpath.normcase(ntpath.normpath(str(p)))
def pin(p,h=None,n=None):
 p=Path(p);b=p.read_bytes();v=dict(path=str(p),bytes=len(b),sha256=sha(b))
 if h is not None:assert v["sha256"]==h.upper(),("hash",str(p),v["sha256"],h)
 if n is not None:assert len(b)==n,("length",str(p),len(b),n)
 k=key(p)
 if k in inputs:assert inputs[k]==v,("changed-or-alias",str(p))
 else:inputs[k]=v
 return b
def record(r):return pin(r["path"],r["sha256"],r["bytes"])
def js(p):return json.loads(Path(p).read_bytes())
def git(p,*args):return subprocess.run(["git","-C",str(p),*args],check=True,capture_output=True).stdout.decode().strip()
assert git(B/"main","rev-parse","HEAD")==HEAD
assert git(W,"rev-parse","HEAD")=="5e4646ad8268fdfc8007691ccbda28b6d6985807"
assert git(W,"diff","--cached","--name-only")==""
m=json.loads(pin(D/"manifest.json","74315CAA31B176DCDAC1C2407C23CB2610E0E93FB8EA45F72B2E878B7A527893",29093))
assert len(m["inventory"])==48 and len(m["external_input_pins"])==19
assert len({key(r["path"])for r in m["inventory"]})==48
for r in m["inventory"]:
 assert Path(r["path"]).relative_to(D).as_posix()==r["relative_path"]
 record(r)
for r in m["external_input_pins"]:record(r)
ab=js(D/"authority-bindings.json")
assert ab["revision"]==REV and len(ab["bindings"])==19
def select(x,s):
 if s=="$":return x
 for name,index in re.findall(r"([A-Za-z_][A-Za-z_0-9]*)(?:\[(\d+)\])?",s):
  x=x[name]
  if index:x=x[int(index)]
 return x
provenance=[]
for b in ab["bindings"]:
 assert b["revision"]==REV
 raw=record(b["authority"]);record(b["receipt"])
 if "contained_original"in b:
  original=record(b["contained_original"]);assert raw==original
  r=select(js(b["receipt"]["path"]),b["receipt_selector"])
  assert key(r["path"])==key(b["authority"]["path"]) and key(r["source_path"])==key(b["contained_original"]["path"])
  assert r["sha256"]==sha(raw) and r["bytes"]==len(raw) and r["revision"]==REV
  method="complete contained-original equality"
 else:
  record(b["native_receipt"])
  r=select(js(b["native_receipt"]["path"]),b["native_selector"])
  assert r["http_status"]==200 and r["url"]==b["url"]
  assert r["body_sha256"].upper()==b["native_body_sha256"]==sha(raw)
  assert b["url"].startswith("https://raw.githubusercontent.com/nodejs/node/"+REV+"/")
  method="pinned successful native HTTP body digest; excerpt length not treated as full source"
 provenance.append(dict(authority=b["authority"],method=method,receipt=b["receipt"]))
assert sum("contained_original"in b for b in ab["bindings"])==14
assert sum("native_receipt"in b for b in ab["bindings"])==5
cb=js(D/"consumer-basis.json");assert cb["main_head_read_before_and_after"]==HEAD and len(cb["records"])==9
for r in cb["records"]:
 a=pin(r["source_path"],r["sha256"],r["bytes"]);z=pin(r["snapshot"],r["sha256"],r["bytes"]);assert a==z
# Existing selected dependencies, admission scope identity, and recipe flags.
extra=[
 (B/"main/src/extensions/native_node_diagnostic_context.hpp","7EA7700F4EDCC6ED5C27DF98574BE27A572AFF01E151B9F39667E6737ACC30B9",914),
 (W/"verification/native-node-tracing-platform-sourceonly-20261020/build-composition/original/src/extensions/native_node_diagnostic_context.hpp","7EA7700F4EDCC6ED5C27DF98574BE27A572AFF01E151B9F39667E6737ACC30B9",914),
 (W/"src/extensions/native_node_standard_allocator.hpp","16D82D2C2143DFAF3861B722BD2E9775FB0BD7D6C9BE400D0ECE37E0674E709B",2562),
 (W/"src/extensions/native_simdjson_memory.hpp","7554ED1DDCA28FAE7B11E025BD9D7EEF560DB657086A40029E5D95DBEFAE5291",2449),
 (W/"tools/build_native_node_abseil.zig","8053B6A69B570372A9A895787C66F76FF055A6225D333C5A55F8E307293AF9F1",7328)]
for p,h,n in extra:pin(p,h,n)
assert Path(extra[0][0]).read_bytes()==Path(extra[1][0]).read_bytes()
flags=Path(extra[-1][0]).read_text()
assert all("-D"+s not in flags for s in ("DEBUG","NDEBUG","OFFICIAL_BUILD"))
assert '"-std=gnu++20", "-fno-exceptions", "-fno-rtti", "-fno-strict-aliasing"' in flags
# Independently reproduce exact selected bodies using tokens, not the author's normalized string output.
original=(D/"authority/src__tracing__trace_event.h.txt").read_text()
candidate=(D/"proposal/src/extensions/native_node_tracing_event_api.cpp").read_text()
api=(D/"proposal/src/extensions/native_node_tracing_event_api.h").read_text()
def body(s,needle):
 assert s.count(needle)==1,(needle,s.count(needle))
 start=s.index(needle);a=s.index("{",start);depth=1;i=a+1
 while depth:
  if s[i]=="{":depth+=1
  if s[i]=="}":depth-=1
  i+=1
 return s[a+1:i-1],[s.count("\n",0,a)+1,s.count("\n",0,i-1)+1]
def tokens(s):
 s=re.sub(r"//[^\n]*","",s)
 assert '"' not in s and "'" not in s and "/*" not in s,("non-string-free-body",s)
 for a,b in [
  ("v8::ConvertableToTraceFormat","ConvertableToTraceFormat"),
  ("v8::TracingController","TracingController"),
  ("node::tracing::TraceEventHelper","TraceEventHelper"),
  ("node::tracing::Agent","Agent")]:s=s.replace(a,b)
 return re.findall(r"[A-Za-z_][A-Za-z_0-9]*|\d+|::|->|==|!=|>=|<=|&&|\|\||\+\+|--|<<|>>|\S",s)
prefix="\n  DiagnosticContextScope diagnostic(context);\n  AllocationScope allocation(memory_owner);\n"
def candidate_body(name):
 b,lines=body(candidate,name+"(")
 assert b.startswith(prefix) and b.count("DiagnosticContextScope")==b.count("AllocationScope")==1
 assert tokens(b[:len(prefix)])==["DiagnosticContextScope","diagnostic","(","context",")",";","AllocationScope","allocation","(","memory_owner",")",";"]
 return b[len(prefix):],lines
comparisons=[]
pairs=[
 ("static inline const uint8_t* GetCategoryGroupEnabled","pi_node_tracing_event_category_enabled"),
 ("static inline uint64_t AddTraceEventImpl","pi_node_tracing_event_add"),
 ("static V8_INLINE uint64_t AddTraceEventWithTimestampImpl","pi_node_tracing_event_add_with_timestamp"),
 ("static V8_INLINE void AddMetadataEventImpl","pi_node_tracing_event_add_metadata")]
for old,new in pairs:
 a,al=body(original,old);b,bl=candidate_body(new)
 if new.endswith("category_enabled"):
  assert a.count(" = GetTracingController();")==1
  a=a.replace(" = GetTracingController();"," = TraceEventHelper::GetTracingController();",1)
 at,bt=tokens(a),tokens(b);assert at==bt,("body mismatch",new)
 comparisons.append(dict(original_symbol=old,candidate_symbol=new,authority_lines=al,candidate_lines=bl,tokens=at,tokens_exact=True))
lines=original.splitlines()
assert lines[116].startswith("#define TRACE_EVENT_API_UPDATE_TRACE_EVENT_DURATION")
macro="\n".join(lines[117:120]).replace("\\","")
assert tokens(macro)==["if","(","auto","controller","=","TraceEventHelper","::","GetTracingController","(",")",")","controller","->","UpdateTraceEventDuration"]
classpos=original.index("class ScopedTracer")
start=original.index("TRACE_EVENT_API_UPDATE_TRACE_EVENT_DURATION(",classpos)
end=original.index(";",start)+1
call=original[start:end]
for old,new in [("data_.category_group_enabled","category_group_enabled"),("data_.name","name"),("data_.event_handle","handle")]:
 assert call.count(old)==1;call=call.replace(old,new)
expanded=call.replace("TRACE_EVENT_API_UPDATE_TRACE_EVENT_DURATION",macro,1)
b,bl=candidate_body("pi_node_tracing_event_update_duration")
assert tokens(expanded)==tokens(b)
comparisons.append(dict(original_symbol="TRACE_EVENT_API_UPDATE_TRACE_EVENT_DURATION at ScopedTracer destructor",candidate_symbol="pi_node_tracing_event_update_duration",authority_macro_lines=[117,120],authority_call_lines=[692,693],candidate_lines=bl,tokens=tokens(b),tokens_exact=True))
assert "if (p_data_ && *data_.category_group_enabled)" in original
names=re.findall(r"\b(pi_node_tracing_event_[a-z_]+)\s*\(",api)
defs=re.findall(r'extern "C" [^{;]*?\b(pi_node_tracing_event_[a-z_]+)\s*\(',candidate)
assert len(names)==len(set(names))==len(defs)==5 and sorted(names)==sorted(defs)==m["five_declarations_and_definitions"]
for name in ("pi_node_tracing_event_add","pi_node_tracing_event_add_with_timestamp","pi_node_tracing_event_add_metadata"):
 b,_=candidate_body(name);adopt=b.index("arg_convertibles[1].reset");lookup=b.index("TraceEventHelper::")
 assert adopt<lookup and b.count("arg_convertibles[0].reset")==b.count("arg_convertibles[1].reset")==1
 assert "static_cast<intptr_t>(arg_values[0])"in b and "static_cast<intptr_t>(arg_values[1])"in b
# Full one-member recipe forward and inverse, and unchanged donor recipe.
bp=js(D/"build-proposal.json");assert len(bp["edits"])==1
a=record(bp["original"]);b=record(bp["projected"])
e=bp["edits"][0];old=e["before"].encode();new=e["after"].encode()
assert a.count(old)==b.count(new)==1 and a.replace(old,new,1)==b and b.replace(new,old,1)==a
assert pin(bp["live_source"],bp["original"]["sha256"],bp["original"]["bytes"])==a
assert b.count(b'"src/extensions/native_node_tracing_event_api.cpp"')==1
assert not (W/"src/extensions/native_node_tracing_event_api.h").exists()
assert not (W/"src/extensions/native_node_tracing_event_api.cpp").exists()
# Rehash all predecessor-preserved files without requiring the donor's later independent evidence to disappear.
pre=js(W/"verification/native-node-tracing-platform-commit-closure-20261020/preflight.json")
preserved={}
for field,want in [("preserved_tracked_dirty",7),("preserved_old_drafts",10),("preserved_other_untracked",134)]:
 values=pre[field];assert len(values)==want
 for rel,v in values.items():
  if isinstance(v,str):pin(W/rel,v)
  else:
   assert isinstance(v,dict)
   pin(W/rel,v["sha256"],v.get("bytes"))
 preserved[field]=want
assert git(B/"main","rev-parse","HEAD")==HEAD and git(W,"rev-parse","HEAD")==m["head"]
assert git(W,"diff","--cached","--name-only")==""
# Recheck every pinned input before publishing only a new evidence proof.
for r in list(inputs.values()):record(r)
proof=dict(schema="pi-zig.independent-tracing-event-bootstrap-source-audit.v1",
 status="finite_source_checks_passed",source_only=True,
 manifest_sha256="74315CAA31B176DCDAC1C2407C23CB2610E0E93FB8EA45F72B2E878B7A527893",
 main_head=HEAD,donor_head=m["head"],upstream_revision=REV,
 input_count=len(inputs),inputs=sorted(inputs.values(),key=lambda r:key(r["path"])),
 source_comparisons=comparisons,source_comparison_count=5,
 first_scopes_order=["DiagnosticContextScope","AllocationScope"],
 c_declarations_equal_definitions=sorted(names),
 original_convertible_adoption_before_global_lookup=True,
 duration_scoped_tracer_guard_remains_external=True,
 source_authority_bindings=provenance,complete_contained_equalities=14,native_body_digest_bindings=5,
 consumer_snapshot_current_equalities=9,recipe_complete_forward_and_inverse=True,
 recipe_new_member_count=1,existing_live_candidates_absent=True,
 preserved_predecessor_file_sets=preserved,
 diagnostic_scope_main_and_contained_copy_identical=True,
 standalone_donor_diagnostic_header_present=(W/"src/extensions/native_node_diagnostic_context.hpp").exists(),
 standalone_or_composite_build_admission=False,compiler_execution=False,native_execution=False,Main_modified=False,
 source_mutation_hold_released=False,
 created_utc=datetime.datetime.now(datetime.timezone.utc).isoformat())
OUT.mkdir(exist_ok=True)
payload=(json.dumps(proof,indent=2)+"\n").encode()
with (OUT/"source-audit.json").open("xb")as f:f.write(payload)
print(json.dumps(dict(path=str(OUT/"source-audit.json"),bytes=len(payload),sha256=sha(payload),inputs=len(inputs),comparisons=5,contained_originals=14,native_receipts=5,consumer_equalities=9,preserved=preserved,passed=True)))
