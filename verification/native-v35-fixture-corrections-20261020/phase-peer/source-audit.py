"""Independent source-only peer of the separate V35 close-begin observer correction.
No live source changes, compiler/native tooling, project generator or runtime auditor.
"""
from pathlib import Path
import json,re,hashlib,subprocess,difflib
B=Path(r"C:\Users\adyba\pi-zig");M=B/"main"
W=B/"worktrees/modules-io-resume-20261018";S=B/"worktrees/sdk-owners-resume-20261018"
D=S/"verification/v35-file-handle-close-observer-sourceonly-20261020"
A=S/"verification/v35-file-handle-fixture-shadowing-sourceonly-20261020"
AP=W/"verification/v35-file-handle-fixture-shadowing-independent-peer-20261020"
F=W/"verification/v35-file-handle-close-observer-source-peer-20261020"
O=W/"verification/v35-file-handle-close-observer-candidate-peer-20261020"
HEAD="79c19fc30c886e85b71aca75d1a025397db04fec"
REL="src/native_node_file_handle_owner_test_support.zig"
def sha(b):return hashlib.sha256(b).hexdigest().upper()
def jp(o):return (json.dumps(o,indent=2,ensure_ascii=True)+"\n").encode()
def pin(p,b=None):
 p=Path(p);b=p.read_bytes() if b is None else b
 return {"path":str(p),"bytes":len(b),"sha256":sha(b)}
def exact(p,n,h):
 b=Path(p).read_bytes();assert len(b)==n and sha(b)==h,str(p);return b
def git(*a):return subprocess.check_output(["git",*a],cwd=M)
assert git("rev-parse","HEAD").decode().strip()==HEAD and git("status","--porcelain")==b""
proposal_raw=exact(D/"proposal.json",3791,"4D8BAC94FF3A5CD4F27F9F4BB19C944F672EBA816A8D73E7453B819870B5EAFA")
proposal=json.loads(proposal_raw)
checked={}
def pins(obj):
 if isinstance(obj,dict):
  if set(["path","bytes","sha256"])<=set(obj):
   b=exact(obj["path"],obj["bytes"],obj["sha256"]);checked[obj["path"]]=pin(obj["path"],b)
  for v in obj.values():pins(v)
 elif isinstance(obj,list):
  for v in obj:pins(v)
pins(proposal)
raw=exact(A/"original"/REL,32558,"8E1205EAFD05CB18C6FD984258A1D153AE3E6262103EE0E13934FBB54FCC2E60")
alpha=exact(A/"projected"/REL,32741,"50E65ED03D8280B3DC35632D49274BC97A63A1A7012E70C362DB845B2C29878B")
candidate=exact(D/"projected"/REL,33137,"0D09BBA76254B22996F4D6B8EB7C43B8487FE4F9C22A02709B4839580AD29127")
assert raw==(M/REL).read_bytes()==(S/REL).read_bytes()==git("show",HEAD+":"+REL)
alpha_peer=exact(AP/"peer.json",4707,"EB41FE47065EA84F89B08E477965F6F0BDFFCF16527DA9AF948E3C5B1DEA9C2F")
alpha_proof_raw=exact(AP/"source-audit.json",39142,"E2ABF53DA669E604E25556948F2F71640DAF11556070FC663325A725EC29580C")
alpha_proof=json.loads(alpha_proof_raw)
before=b"    f.close_begin_kind = uv.pi_uv_fs_request_info(request.actual.?).kind;\n"
after=b"""    // ClosePromise calls this synchronously on the dispatch owner thread,
    // while CloseReq owns the native storage and before its first submission.
    std.debug.assert(!request.entry.dispatched and !request.entry.counted);
    const preparation = uv.pi_uv_fs_request_preparation_info(request.actual.?);
    std.debug.assert(preparation.accepted == 0 and preparation.cleaned == 0 and
        preparation.completed == 0);
    f.close_begin_kind = preparation.kind;
"""
assert raw.count(before)==alpha.count(before)==1
offset=alpha.index(before);assert offset==raw.index(before)==8928
assert alpha.replace(before,after)==candidate
assert candidate.count(after)==1 and candidate.replace(after,before)==alpha
assert candidate[:offset]==alpha[:offset] and candidate[offset+len(after):]==alpha[offset+len(before):]
phase_only=raw.replace(before,after)
assert phase_only==(D/"composition/phase-only-from-Main79.zig").read_bytes()
line_delta=after.count(b"\n")-before.count(b"\n")
assert line_delta==6 and len(after)-len(before)==396
# Reuse only the independently accepted literal line records, not SDK byte offsets.
def apply_alpha(data,reverse=False,has_phase=False):
 lines=data.splitlines(keepends=True)
 for binding in alpha_proof["independent_line_reconstruction"]:
  for edit in binding["lines"]:
   line=edit["line"];assert line>=304
   index=line-1+(line_delta if has_phase else 0)
   a=edit["after" if reverse else "before"].encode()
   z=edit["before" if reverse else "after"].encode()
   assert lines[index]==a,(line,reverse,has_phase)
   lines[index]=z
 return b"".join(lines)
assert apply_alpha(raw)==alpha
assert apply_alpha(phase_only,has_phase=True)==candidate
assert apply_alpha(candidate,reverse=True,has_phase=True)==phase_only
assert apply_alpha(candidate.replace(after,before),reverse=True)==raw
assert apply_alpha(candidate,reverse=True,has_phase=True).replace(after,before)==raw
def body(data,start,end):
 lo=data.index(start);hi=data.index(end,lo);return data[lo:hi]
completion=body(raw,b"fn endAsyncClose(",b"fn onRead(")
assert completion==body(alpha,b"fn endAsyncClose(",b"fn onRead(")==body(candidate,b"fn endAsyncClose(",b"fn onRead(")
assert len(completion)==593 and sha(completion)=="9FF6EFA60530AAC84182CC7A254B709009605E3471FE420C677590DCF859F07F"
old_begin=body(alpha,b"fn beginAsyncClose(",b"fn endAsyncClose(")
new_begin=body(candidate,b"fn beginAsyncClose(",b"fn endAsyncClose(")
assert old_begin.replace(before,after)==new_begin
for retained in [
 b"f.close_begins += 1;",b"f.close_actual = @intFromPtr(request.actual.?);",
 b"f.close_begin_provider = request.wrap.provider;",
 b"f.close_begin_unsubmitted = !request.entry.dispatched and !request.entry.counted;",
 b"f.close_begin_globals = request.promise != null and request.reference != null;"]:
 assert old_begin.count(retained)==new_begin.count(retained)==1
assert b"pi_uv_fs_request_info(" not in new_begin
assert new_begin.count(b"pi_uv_fs_request_preparation_info(")==1
assert new_begin.count(b"std.debug.assert(")==2
assert b"preparation.accepted == 0 and preparation.cleaned == 0 and\n        preparation.completed == 0" in new_begin
for expression in [rb'@import\s*\(\s*"([^"]+)"\s*\)',rb'@embedFile\s*\(\s*"([^"]+)"\s*\)',
 rb"\b(?:pub\s+)?fn\s+([A-Za-z_][A-Za-z_0-9]*)\s*\("]:
 assert re.findall(expression,alpha)==re.findall(expression,candidate)
patch="".join(difflib.unified_diff(alpha.decode().splitlines(keepends=True),candidate.decode().splitlines(keepends=True),fromfile="a/"+REL,tofile="b/"+REL)).encode()
assert patch==(D/"close-observer-phase.patch").read_bytes()
mapping_raw=exact(D/"source-map.json",43721,"35266857348314A8481F98107CB6B94421FFF9A97A04C38A41DC0779F64F4B0A")
mapping=json.loads(mapping_raw);pins(mapping)
assert len(mapping["sources"])==11 and len(mapping["excerpts"])==22
source_data={}
for r in mapping["sources"]:
 b=exact(r["path"],r["bytes"],r["sha256"]);source_data[r["path"]]=b
 assert b==exact(r["snapshot"]["path"],r["snapshot"]["bytes"],r["snapshot"]["sha256"])
 if "relative_path" in r:assert git("show",HEAD+":"+r["relative_path"])==b
for e in mapping["excerpts"]:
 b=source_data[e["source"]["path"]]
 excerpt=b"".join(b.splitlines(keepends=True)[e["first_line"]-1:e["last_line"]])
 assert len(excerpt)==e["bytes"] and sha(excerpt)==e["sha256"] and excerpt.decode()==e["text"]
# Exact actual helper and original Node ordering; the caller was read with its
# retained Controller, owner-thread check, completed constructor and initial Reset.
c_source=source_data[str(M/"src/extensions/native_uv_tcp.c")]
helper=body(c_source,b"PiUvFsPreparationInfo pi_uv_fs_request_preparation_info(",b"PiUvFsInfo pi_uv_fs_request_info(")
assert b"assert(!request->submitted);" in helper
assert b"request->uv" not in helper and b"request->accepted" in helper
assert b"atomic_load_explicit(&request->cleaned, memory_order_acquire)" in helper
assert b"atomic_load_explicit(&request->completed, memory_order_acquire)" in helper
info=body(c_source,b"PiUvFsInfo pi_uv_fs_request_info(",b"PiUvResult pi_uv_fs_request_create(")
assert b"assert(atomic_load_explicit(&request->completed, memory_order_acquire));" in info
owner_source=source_data[str(M/"src/extensions/native_node_file_handle_owner.zig")]
assert owner_source.index(b"self.close_trace.begin_async(")<owner_source.index(b"self.controller.dispatchRawClose(")
node_source=next(source_data[r["path"]] for r in mapping["sources"] if r.get("upstream_path")=="src/node_file.cc")
assert node_source.index(b"FS_ASYNC_TRACE_BEGIN0(UV_FS_CLOSE, req)")<node_source.index(b"req->Dispatch(uv_fs_close, fd_, AfterClose)")
control=source_data[str(M/"src/native_node_file_handle_owner_test.zig")]
assert b"std.testing.expect(f.close_begin_unsubmitted and f.close_begin_globals)" in control
assert b"std.testing.expectEqual(@as(c_int, uv.PI_UV_FS_CLOSE), f.close_begin_kind)" in control
assert b"try expectDrainedClose(&f, actual);" in control
preparation=exact(D/"prepare-proposal.py",13869,"0F68B9BEA1D83CEF49929883FAADEC44475A67FD3324191209891D961DEA13D9")
marker=b"# FINAL OUTPUT PHASE:";assert preparation.count(marker)==1
prefix=preparation.split(marker)[0]
scope={"__name__":"independent_source_only_replay","__file__":str(D/"prepare-proposal.py")}
exec(prefix,scope)
reproduced=[]
for relative,data in sorted(scope["outputs"].items()):
 assert data==(D/relative).read_bytes(),relative
 reproduced.append({"relative_path":relative,**pin(D/relative,data)})
assert len(reproduced)==18
assert scope["candidate"]==candidate and scope["phase_only"]==phase_only
assert scope["proof"]["actual_current_input_pins_reverified"]==960
assert scope["proof"]["all58_declared_names_unchanged"]
assert scope["proof"]["four_graphs"]==json.loads((A/"token-and-graph-proof.json").read_bytes())["graphs"]
assert (M/REL).read_bytes()==raw and (S/REL).read_bytes()==raw
assert git("rev-parse","HEAD").decode().strip()==HEAD and git("status","--porcelain")==b""
for r in alpha_proof["preserved_identity_draft"]:exact(r["path"],r["bytes"],r["sha256"])
result={
 "schema":"pi-zig-v35-close-observer-independent-candidate-proof-v1","main_head":HEAD,
 "proposal":pin(D/"proposal.json",proposal_raw),"packet_and_source_pins":sorted(checked.values(),key=lambda p:p["path"]),
 "selected_candidate":pin(D/"projected"/REL,candidate),
 "accepted_alpha_peer":pin(AP/"peer.json",alpha_peer),
 "accepted_alpha_line_proof":pin(AP/"source-audit.json",alpha_proof_raw),
 "independent_phase_hunk":{"before":before.decode(),"after":after.decode(),"offset":offset,
 "added_bytes":396,"added_lines":6,"exact_prefix_and_suffix":True},
 "independent_alpha_then_phase_equals_phase_then_alpha":True,
 "independent_both_whole_inverses_recover_main79":True,
 "completion_observer":{"bytes":len(completion),"sha256":sha(completion),"all_bytes_unchanged":True},
 "retained_begin_observations":True,"actual_zero_phase_assertions":True,
 "native_completion_helper_unchanged":pin(M/"src/extensions/native_uv_tcp.c",c_source),
 "source_binding":{"sources":11,"raw_main_sources":10,"original_node_authority":1,"exact_excerpts":22},
 "reproduced_output_free_sdk_prefix":{"source":pin(D/"prepare-proposal.py",preparation),
 "bytes":len(prefix),"sha256":sha(prefix),"exact_outputs":reproduced},
 "current_input_pins_reverified":960,"declared_names_unchanged":58,
 "four_topologies":scope["proof"]["four_graphs"],"future_actual_metadata":None,
 "identity_draft_preserved":alpha_proof["preserved_identity_draft"],
 "main_and_sdk_fixture_unchanged":True,"main_clean":True,
 "execution":{"compiler":False,"native":False,"formatter":False,"project_generator":False,
 "metadata_auditor":False,"grant_constructor":False,"source_only_sdk_prefix":True}}
result_raw=jp(result)
peer={
 "schema":"pi-zig-v35-close-observer-independent-candidate-peer-v1",
 "status":"ACCEPTED FOR THE BOUNDED SOURCE-ONLY PHASE OBSERVER SUCCESSOR",
 "reviewer":"/root/module_io_port",
 "proposal":pin(D/"proposal.json",proposal_raw),"selected_candidate":pin(D/"projected"/REL,candidate),
 "alpha_predecessor_peer":pin(AP/"peer.json",alpha_peer),
 "original_causal_finding":pin(F/"finding.json"),"original_causal_proof":pin(F/"causal-proof.json"),
 "audit_source":pin(Path(__file__)),"audit_result":pin(O/"source-audit.json",result_raw),
 "findings":[
 "The original beginAsyncClose observation violates the completion-info contract by reading before first Dispatch. This is a source finding; V35 stopped at compilation and did not reproduce this assertion at runtime.",
 "The selected one-hunk correction uses the existing preparation ABI through the actual shared uv namespace. The caller's ClosePromise retains Controller admission, whose enter path checks the actual owner thread. CloseReq creation owns typed native storage and completes Entry/Reset/Global initialization before the synchronous observer.",
 "The native allocation zeroes submitted and accepted and initializes atomic cleaned/completed to zero. Initial request_reset returns without setting these fields. Thus the selected actual Entry assertions and accepted/cleaned/completed zero assertions correspond to this first-admission cutpoint.",
 "The preparation helper asserts unsubmitted and reads only kind, accepted and the two atomic phase flags. It does not access uv.result/path, change state, acquire completion entitlement or create a concurrent lifecycle snapshot.",
 "All original begin counters, actual pointer/provider, unsubmitted and Global observations remain. The complete 593-byte endAsyncClose body is identical, including the genuine completion-only info call, result, native-reference, waiting-count, accepted and cleanup observations.",
 "Existing close controls, production C/H owners, helper contract and assertions, build and all 58 source names remain unchanged. The new assertions are fixture phase checks, not added upstream Node policy.",
 "Independent line-based alpha/phase composition succeeds in both orders and both whole inverses recover raw Main79. The fully read source-only prefix reproduces all 18 packet outputs, 11 sources/22 excerpts and rechecks 960 current inputs.",
 "No concrete blocker remains in this bounded observer correction."],
 "manual_reads":[
 "Full SDK preparation source and one-hunk patch, entire source map including all 22 selected excerpts, and the selected begin/end observer context.",
 "Original Node trace-before-Dispatch and host ClosePromise/CloseReq ownership, actual Controller owner-thread gate, Entry initialization/reset, native allocation/admission/reset and both info helper contracts/bodies.",
 "The retained actual explicit-close test's Promise/request/typed-kind, unsubmitted/Global, completion, cleanup and repeat-close assertions."],
 "limits":[
 "No compiler/native/Node reference/formatter/project generator/metadata auditor/grant constructor execution.",
 "No Main, live SDK fixture, production helper, build, catalog, cache, lease or unrelated draft modification.",
 "No runtime success, process closure, full FileHandle lifecycle qualification or future metadata-count prediction.",
 "Root retains terminal V35 negative closure, exact source intake and fresh-head catalog/grant release authority."],
 "preservation":{"base_head":HEAD,"main_clean":True,"alpha_packet_preserved":True,
 "original_phase_finding_preserved":True,"identity_owner_and_16_controls_preserved":True}}
peer_raw=jp(peer)
# FINAL OUTPUT PHASE: only this new independent evidence is created.
O.mkdir(parents=True,exist_ok=True)
for name,data in [("source-audit.json",result_raw),("peer.json",peer_raw)]:
 with (O/name).open("xb") as f:f.write(data)
print(json.dumps({"peer":pin(O/"peer.json"),"proof":pin(O/"source-audit.json"),
 "checker":pin(Path(__file__)),"outputs":18,"sources":11,"excerpts":22,"current_inputs":960},indent=2))
