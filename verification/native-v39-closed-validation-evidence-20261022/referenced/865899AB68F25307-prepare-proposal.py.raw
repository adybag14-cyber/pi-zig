"""Source-only successor for the FileHandle trace-begin fixture observer.
No live source writes or native tooling. FINAL OUTPUT PHASE creates only immutable evidence.
"""
from pathlib import Path
import json,re,hashlib,subprocess,difflib
B=Path(r"C:\Users\adyba\pi-zig");M=B/"main";W=B/"worktrees/sdk-owners-resume-20261018"
D=W/"verification/v35-file-handle-close-observer-sourceonly-20261020"
A=W/"verification/v35-file-handle-fixture-shadowing-sourceonly-20261020"
P=B/"worktrees/modules-io-resume-20261018/verification/v35-file-handle-close-observer-source-peer-20261020"
HEAD="79c19fc30c886e85b71aca75d1a025397db04fec"
REL="src/native_node_file_handle_owner_test_support.zig"
def sha(b):return hashlib.sha256(b).hexdigest().upper()
def jp(o):return (json.dumps(o,indent=2,ensure_ascii=True)+"\n").encode()
def row(p,b=None):
 p=Path(p);b=p.read_bytes() if b is None else b
 return {"path":str(p),"bytes":len(b),"sha256":sha(b)}
def exact(p,h):
 b=Path(p).read_bytes();assert sha(b)==h,str(p);return b
def git(*args):return subprocess.check_output(["git",*args],cwd=M)
assert git("rev-parse","HEAD").decode().strip()==HEAD and git("status","--porcelain")==b""
alpha_proposal=exact(A/"proposal.json","9CEEC8BF72B9E955697145E989A65C06AB9DB14B94444332545B4E5A233DD16E")
alpha_proof=exact(A/"token-and-graph-proof.json","68C99BF537F7A9EBDAEEDB9472A4A511E0951DD9AB3F4372FA02B192AD5A6104")
ap=json.loads(alpha_proposal);pf=json.loads(alpha_proof)
original=exact(A/"original"/REL,"8E1205EAFD05CB18C6FD984258A1D153AE3E6262103EE0E13934FBB54FCC2E60")
alpha=exact(A/"projected"/REL,"50E65ED03D8280B3DC35632D49274BC97A63A1A7012E70C362DB845B2C29878B")
assert (M/REL).read_bytes()==original and (W/REL).read_bytes()==original
assert git("show",HEAD+":"+REL)==original
before=b"    f.close_begin_kind = uv.pi_uv_fs_request_info(request.actual.?).kind;\n"
after=b"""    // ClosePromise calls this synchronously on the dispatch owner thread,
    // while CloseReq owns the native storage and before its first submission.
    std.debug.assert(!request.entry.dispatched and !request.entry.counted);
    const preparation = uv.pi_uv_fs_request_preparation_info(request.actual.?);
    std.debug.assert(preparation.accepted == 0 and preparation.cleaned == 0 and
        preparation.completed == 0);
    f.close_begin_kind = preparation.kind;
"""
assert original.count(before)==alpha.count(before)==1
phase_offset=original.index(before)
assert phase_offset==alpha.index(before)
phase_delta=len(after)-len(before)
candidate=alpha.replace(before,after)
phase_only=original.replace(before,after)
assert candidate.count(after)==phase_only.count(after)==1
assert candidate.replace(after,before)==alpha and phase_only.replace(after,before)==original
def alpha_apply(b,reverse=False,phase=False):
 result=b
 for e in reversed(pf["identifier_token_edits"]):
  pos=e["new_offset"] if reverse else e["old_offset"]
  old=e["after"] if reverse else e["before"]
  new=e["before"] if reverse else e["after"]
  assert pos>=phase_offset+len(before)
  if phase:pos+=phase_delta
  assert result[pos:pos+len(old)]==old.encode()
  result=result[:pos]+new.encode()+result[pos+len(old):]
 return result
assert alpha_apply(original)==alpha
assert alpha_apply(phase_only,phase=True)==candidate
assert alpha_apply(candidate,reverse=True,phase=True)==phase_only
assert alpha_apply(candidate.replace(after,before),reverse=True)==original
assert alpha_apply(candidate,reverse=True,phase=True).replace(after,before)==original
assert alpha_apply(alpha,reverse=True)==original
assert candidate[:phase_offset]==alpha[:phase_offset]
assert candidate[phase_offset+len(after):]==alpha[phase_offset+len(before):]
# The entire completion observer remains byte-identical, including its actual
# completion-only info call, accepted/cleaned checks and reference observations.
def end_observer(b):
 lo=b.index(b"fn endAsyncClose(");hi=b.index(b"fn onRead(",lo);return b[lo:hi]
assert end_observer(original)==end_observer(alpha)==end_observer(candidate)
assert candidate.count(b"const info = uv.pi_uv_fs_request_info(request.actual.?);")==1
assert b"f.close_begin_unsubmitted = !request.entry.dispatched and !request.entry.counted;" in candidate
for pattern in [rb'@import\s*\(\s*"([^"]+)"\s*\)',rb'@embedFile\s*\(\s*"([^"]+)"\s*\)',
 rb"\b(?:pub\s+)?fn\s+([A-Za-z_][A-Za-z_0-9]*)\s*\("]:
 assert re.findall(pattern,original)==re.findall(pattern,alpha)==re.findall(pattern,candidate)
assert not re.findall(rb'^\s*test\s+"([^"]+)"',candidate,re.M)
finding=exact(P/"finding.json","AED0E3E9518D691A36068A6B410B11B1D060718AB313E9921FBC665EFBA68DE1")
causal=exact(P/"causal-proof.json","9AE461824CBBEB0E87F450FE0E6660EE6A83AF3F3FEBA820D97B8F5ECBBAD724")
causal_object=json.loads(causal)
snapshots={};source_rows=[];excerpts=[]
for r in causal_object["source_pins"]:
 p=Path(r["path"]);b=exact(p,r["sha256"]);assert len(b)==r["bytes"]
 if "relative_path" in r:
  assert git("show",HEAD+":"+r["relative_path"])==b
  out="authority/"+r["relative_path"]
 else:out="authority/node_file.cc.v24.13"
 snapshots[out]=b
 source_rows.append({**r,"snapshot":row(D/out,b)})
for e in causal_object["excerpts"]:
 p=Path(e["source"]["path"]);b=p.read_bytes()
 text=b"".join(b.splitlines(keepends=True)[e["first_line"]-1:e["last_line"]])
 assert sha(text)==e["sha256"] and len(text)==e["bytes"] and text.decode()==e["text"]
 excerpts.append(e)
extra=[
 ("src/extensions/native_node_file_handle_owner.zig","2D90F772D2177C7DB4EF4F945F78529C0061C809E171C22CECC324125C9A461D",243,246,"ClosePromise retains Controller busy admission across the synchronous body, including the trace observer."),
 ("src/extensions/native_node_fs_request_io.zig","B6792DCB053DDC2CFBC26350D9AD580CC5419CF3BDBEB595AF1F19B0922AF996",43,59,"Controller.enter verifies the actual Hub dispatch thread before incrementing busy."),
 ("src/extensions/native_env_io.zig","4BC66694AB6B22FC9A51A0943192BDCD61F0213C6846B0A69E0B459C26EF120E",45,56,"Hub.assertOwner compares the current native thread ID with the concrete owner."),
 ("src/extensions/native_node_file_handle_close_request.zig","C2016812A084329BCFC9DC113485F2732B2CC095C9ED6B8B21A18158205C443A",99,122,"Completed CloseReq construction initializes its queue entry, resets the native storage and installs both actual Globals."),
 ("src/extensions/native_node_request_state.zig","6FACD1ACF162570BF3435E4F962BAB5CA8BAF4237673CD04D66A708F4CC371AF",59,108,"Actual Entry defaults and Reset leave dispatched/count false; only later admission sets them."),
 ("src/extensions/native_uv_tcp.c","8BFEFBB59ADCD7414A8C9358CA2422989784043B3BF651D8006D1C86DED261B2",856,881,"Initial request_reset checks cleaned and returns without setting completed or accepted."),
 ("src/extensions/native_uv_fs.h","23B85BBB1BD8395D1D5085BE0797F06CE2C323DAACF366F5CF3B587D06EACA6D",15,27,"The existing preparation ABI contains only kind and accepted/cleaned/completed integers."),
 ("src/extensions/native_node_uv_service.zig","CDA7A2AEBD9B752E38521E72A33F4BEE3A7A7453AA8DA38F33F04A61D0E369D5",4,12,"Controller.uv is the canonical shared cImport of native_uv_fs.h; no new ABI owner or type is introduced."),
 ("src/extensions/native_node_fs_request_io.zig","B6792DCB053DDC2CFBC26350D9AD580CC5419CF3BDBEB595AF1F19B0922AF996",5,15,"FS request I/O exports that shared canonical UV namespace."),
 ("src/extensions/native_node_file_handle_close_request.zig","C2016812A084329BCFC9DC113485F2732B2CC095C9ED6B8B21A18158205C443A",237,245,"The unchanged genuine completion callback reads completion info only after actual callback-wrapper admission."),
 ("src/native_node_file_handle_owner_test.zig","93D00DE989F6F675E862A61FB93BE2EF91FD6FC7D85CC59FC769CB4842543422",141,168,"Existing named control still asserts typed CLOSE, unsubmitted entry and Globals, then actual completion/result and cleanup.")
]
for rel,h,lo,hi,claim in extra:
 b=exact(M/rel,h);assert git("show",HEAD+":"+rel)==b
 out="authority/"+rel;snapshots[out]=b
 if not any(r["path"]==str(M/rel) for r in source_rows):
  source_rows.append({**row(M/rel,b),"relative_path":rel,"raw_git_commit":HEAD,"raw_git_blob_equal":True,"snapshot":row(D/out,b)})
 text=b"".join(b.splitlines(keepends=True)[lo-1:hi])
 excerpts.append({"source":row(M/rel,b),"first_line":lo,"last_line":hi,"bytes":len(text),"sha256":sha(text),"text":text.decode(),"claim":claim})
inventory=json.loads((A/"input-inventory.json").read_text("utf-8"))
assert sha((A/"input-inventory.json").read_bytes())==pf["input_inventory_sha256"]
for r in inventory:
 b=Path(r["path"]).read_bytes();assert len(b)==r["bytes"] and sha(b)==r["sha256"],r["path"]
# All four root bytes/names and all transitive import sources retain their exact
# alpha-packet pins. This one fixture hunk has identical import/embed literals,
# so the already fully compared complete topologies remain the same.
for g in pf["graphs"]:
 b=Path(g["root_pin"]["path"]).read_bytes()
 assert sha(b)==g["root_pin"]["sha256"]
 names=re.findall(rb'^test "([^"]+)"',b,re.M)
 assert [Path(g["source_root"]).stem+".test."+n.decode() for n in names]==g["required_named"]
patch="".join(difflib.unified_diff(alpha.decode().splitlines(keepends=True),candidate.decode().splitlines(keepends=True),fromfile="a/"+REL,tofile="b/"+REL)).encode()
mapping={"schema":"pi-zig-v35-close-observer-phase-source-map-v1","source_basis_head":HEAD,
 "sources":source_rows,"excerpts":excerpts,
 "causal_conclusion":"The trace-begin call is synchronous after owned typed CLOSE construction and its initial Reset, before first dispatch. The caller's retained Controller has verified the owner thread. Native allocation zeros accepted, completed and cleaned; initial Reset preserves them. Existing preparation-info is valid at this retained unsubmitted cutpoint and exposes those actual flags without uv.result/path, mutation or entitlement. Completion-info still requires completed and remains unchanged at endAsyncClose.",
 "original_policy_scope":"Original Node calls trace begin before Dispatch. The added assertions are fixture observations of the host storage/entry phase, not added original Node policy.",
 "native_ABI_changed":False,"production_source_changed":False}
proof={"schema":"pi-zig-v35-close-observer-phase-proof-v1","base_head":HEAD,
 "original":row(A/"original"/REL,original),"alpha_predecessor":row(A/"projected"/REL,alpha),
 "selected_candidate":row(D/"projected"/REL,candidate),
 "phase_only_for_commutation":row(D/"composition/phase-only-from-Main79.zig",phase_only),
 "phase_hunk":{"before":before.decode(),"after":after.decode(),"old_offset":phase_offset,"new_offset":phase_offset},
 "alpha_then_phase_equals_phase_then_alpha":True,
 "inverse_phase_then_alpha_recovers_Main79":True,
 "inverse_alpha_then_phase_recovers_Main79":True,
 "complete_selected_predecessor_inverse_exact":True,
 "whole_byte_comparison_outside_single_phase_hunk":True,
 "completion_observer_unchanged":{"bytes":len(end_observer(original)),"sha256":sha(end_observer(original))},
 "native_completion_assertion_preserved":True,
 "existing_test_assertions_preserved":True,
 "added_assertions":[
  "!request.entry.dispatched and !request.entry.counted",
  "preparation.accepted == 0 and preparation.cleaned == 0 and preparation.completed == 0"],
 "phase_assertions_use_actual_fields_only":True,
 "function_names_and_import_embed_literals_unchanged":True,
 "four_graphs":pf["graphs"],
 "actual_current_input_pins_reverified":len(inventory),
 "all58_declared_names_unchanged":True,
 "future_actual_metadata":None,"Main_written":False,"compiler_executed":False,
 "native_executed":False,"formatter_executed":False,"metadata_auditor_executed":False,
 "scope":"Separate one-hunk fixture successor; no production, ABI, build, cache, catalog or lease change. Both-order full inverses bind the disjoint identifier proposal."}
proposal={"schema":"pi-zig-v35-close-observer-phase-proposal-v1",
 "status":"UNEXECUTED SOURCE PROPOSAL; no compile/runtime qualification",
 "base_head":HEAD,"target":REL,
 "identifier_predecessor_proposal":row(A/"proposal.json",alpha_proposal),
 "original_alpha_fixture":row(D/"original"/REL,alpha),
 "projected_fixture":row(D/"projected"/REL,candidate),
 "patch":row(D/"close-observer-phase.patch",patch),
 "proof":row(D/"composition-and-phase-proof.json",jp(proof)),
 "source_map":row(D/"source-map.json",jp(mapping)),
 "independent_finding":row(P/"finding.json",finding),
 "independent_causal_proof":row(P/"causal-proof.json",causal),
 "input_inventory":row(A/"input-inventory.json"),
 "preparation_source":row(Path(__file__)),
 "scope":"Replace only the beginAsyncClose completion-only kind observation with existing preparation-info and actual phase assertions. Retain every completion-path check and all 58 control names; preserve the identifier proposal separately.",
 "pending":["Independent candidate peer","Root review and terminal V35 failure closure","Separate authorized source intake and exact new-head catalog/grant","Fresh compiler and runtime validation"]}
outputs={"original/"+REL:alpha,"projected/"+REL:candidate,
 "composition/phase-only-from-Main79.zig":phase_only,
 "close-observer-phase.patch":patch,"composition-and-phase-proof.json":jp(proof),
 "source-map.json":jp(mapping),"proposal.json":jp(proposal),**snapshots}
assert (M/REL).read_bytes()==original and (W/REL).read_bytes()==original
assert git("rev-parse","HEAD").decode().strip()==HEAD and git("status","--porcelain")==b""
# FINAL OUTPUT PHASE: only new packet evidence is created.
for rel,b in outputs.items():
 p=D/rel;p.parent.mkdir(parents=True,exist_ok=True)
 with p.open("xb") as f:f.write(b)
print(json.dumps({"proposal":row(D/"proposal.json"),"candidate":row(D/"projected"/REL),
 "proof":row(D/"composition-and-phase-proof.json"),"source_map":row(D/"source-map.json"),
 "source_pins":len(source_rows),"excerpts":len(excerpts),"current_inputs":len(inventory),
 "all_live_sources_preserved":True},indent=2))
