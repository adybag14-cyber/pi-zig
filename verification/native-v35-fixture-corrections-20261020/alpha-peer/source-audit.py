"""Independent finite source peer for the V35 fixture alpha renames.
Only the final output block creates this peer's two evidence files.
No compiler, native, formatter, metadata auditor, grant constructor or project generator is executed.
"""
from pathlib import Path
import re, json, hashlib, subprocess, difflib
B=Path(r"C:\Users\adyba\pi-zig")
M=B/"main"
W=B/"worktrees/modules-io-resume-20261018"
S=B/"worktrees/sdk-owners-resume-20261018"
D=S/"verification/v35-file-handle-fixture-shadowing-sourceonly-20261020"
O=W/"verification/v35-file-handle-fixture-shadowing-independent-peer-20261020"
REL="src/native_node_file_handle_owner_test_support.zig"
HEAD="79c19fc30c886e85b71aca75d1a025397db04fec"
def sha(b): return hashlib.sha256(b).hexdigest().upper()
def jp(o): return (json.dumps(o,indent=2,ensure_ascii=True)+"\n").encode()
def pin(p,b=None):
 p=Path(p); b=p.read_bytes() if b is None else b
 return {"path":str(p),"bytes":len(b),"sha256":sha(b)}
def checked(p,n,h):
 b=Path(p).read_bytes()
 assert len(b)==n and sha(b)==h,str(p)
 return b
def git(*args): return subprocess.check_output(["git",*args],cwd=M)
assert git("rev-parse","HEAD").decode().strip()==HEAD and git("status","--porcelain")==b""
proposal_raw=checked(D/"proposal.json",5249,"9CEEC8BF72B9E955697145E989A65C06AB9DB14B94444332545B4E5A233DD16E")
proposal=json.loads(proposal_raw)
checked_inputs={}
def walk_pins(obj):
 if isinstance(obj,dict):
  if set(["path","bytes","sha256"])<=set(obj):
   p=Path(obj["path"]); b=checked(p,obj["bytes"],obj["sha256"])
   checked_inputs[str(p)]=pin(p,b)
  for v in obj.values(): walk_pins(v)
 elif isinstance(obj,list):
  for v in obj: walk_pins(v)
walk_pins(proposal)
original=checked(D/"original"/REL,32558,"8E1205EAFD05CB18C6FD984258A1D153AE3E6262103EE0E13934FBB54FCC2E60")
candidate=checked(D/"projected"/REL,32741,"50E65ED03D8280B3DC35632D49274BC97A63A1A7012E70C362DB845B2C29878B")
assert original==(M/REL).read_bytes()==(S/REL).read_bytes()==git("show",HEAD+":"+REL)
# Independent reconstruction uses the manually reviewed line/binding table,
# not SDK token offsets or its token lexer.
rules=[
 ("Fixture.init","value","bootstrap_result",[304,305],2),
 ("Fixture.bootstrap","global","global_object",[328,329,341],3),
 ("Fixture.create.offset","value","offset_value",[383],2),
 ("Fixture.create.length","value","length_value",[384],2),
 ("Fixture.createArgs","value","constructor_result",[390,391],2),
 ("Fixture.expose","value","exposed_value",[512,519],2),
 ("Fixture.installInitRecorder","init","init_hook",[569,570,573],3),
 ("Fixture.stopIo","registry","actual_registry",[581],2),
 ("Fixture.drop","value","owned_value",[591],2),
 ("Fixture.deinit.caught","value","caught_value",[610],2),
 ("File.init","status","open_status",[652,655,656],3)]
old_lines=original.splitlines(keepends=True)
expected_lines=old_lines.copy()
bindings=[]
for label,before,after,lines,count in rules:
 pattern=rb"(?<![A-Za-z_0-9.])"+before.encode()+rb"(?![A-Za-z_0-9])"
 changed=0; details=[]
 for line in lines:
  text=expected_lines[line-1]
  replaced,n=re.subn(pattern,after.encode(),text)
  assert n>0
  expected_lines[line-1]=replaced; changed+=n
  details.append({"line":line,"identifier_tokens":n,"before":text.decode(),"after":replaced.decode()})
 assert changed==count,(label,changed)
 bindings.append({"binding":label,"old":before,"new":after,"tokens":count,"lines":details})
expected=b"".join(expected_lines)
assert expected==candidate and sum(x["tokens"] for x in bindings)==25
recovered=candidate.splitlines(keepends=True)
for label,before,after,lines,count in reversed(rules):
 restored=0
 for line in reversed(lines):
  recovered[line-1],n=re.subn(rb"(?<![A-Za-z_0-9.])"+after.encode()+rb"(?![A-Za-z_0-9])",before.encode(),recovered[line-1])
  restored+=n
 assert restored==count
assert b"".join(recovered)==original
selected_lines={line for rule in rules for line in rule[3]}
new_lines=candidate.splitlines(keepends=True)
assert len(old_lines)==len(new_lines)
assert {i+1 for i,(a,b) in enumerate(zip(old_lines,new_lines)) if a!=b}==selected_lines
assert b"".join(a for i,a in enumerate(old_lines,1) if i not in selected_lines)==b"".join(a for i,a in enumerate(new_lines,1) if i not in selected_lines)
patch="".join(difflib.unified_diff(original.decode().splitlines(keepends=True),candidate.decode().splitlines(keepends=True),fromfile="a/"+REL,tofile="b/"+REL)).encode()
assert patch==(D/"fixture-alpha-renames.patch").read_bytes()
for expression in [
 rb"\b(?:pub\s+)?fn\s+([A-Za-z_][A-Za-z_0-9]*)\s*\(",
 rb"\bpub\s+(?:fn|const|var)\s+([A-Za-z_][A-Za-z_0-9]*)",
 rb'@import\s*\(\s*"([^"]+)"\s*\)',rb'@embedFile\s*\(\s*"([^"]+)"\s*\)',
 rb'^\s*test\s+"([^"]+)"']:
 assert re.findall(expression,original,re.M)==re.findall(expression,candidate,re.M)
# These original lifecycle observers are outside every edit and retained byte-exact.
phase_original=b"".join(old_lines[195:215])
assert phase_original==b"".join(new_lines[195:215])
assert b"pi_uv_fs_request_info(request.actual.?).kind" in phase_original
finding=W/"verification/v35-file-handle-close-observer-source-peer-20261020/finding.json"
finding_bytes=checked(finding,1893,"AED0E3E9518D691A36068A6B410B11B1D060718AB313E9921FBC665EFBA68DE1")
# Fully read source-only SDK prefix. Excludes its sole final write phase.
preparation=checked(D/"prepare-proposal.py",16040,"DCF56EAF57BF756CC904DD6A76EA88BB5C961AF902350F36BA33154B3AAD1104")
marker=b"# FINAL OUTPUT PHASE:"
assert preparation.count(marker)==1
prefix=preparation.split(marker)[0]
scope={"__name__":"independent_source_only_replay","__file__":str(D/"prepare-proposal.py")}
exec(prefix,scope)
reproduced=[]
for relative,content in sorted(scope["outputs"].items()):
 path=D/relative
 assert content==path.read_bytes(),relative
 reproduced.append({"relative_path":relative,**pin(path,content)})
assert len(reproduced)==10
proof=scope["proof"]
assert proof["identifier_token_changes"]==25 and proof["bindings_renamed"]==11
assert len(proof["compiler_errors_preserved"])==10
assert proof["current_inputs"]==960 and proof["source_declarations_total"]==58
assert len(proof["graphs"])==4
# Rehash the complete actual input list independently of the SDK replay cache.
inventory=json.loads((D/"input-inventory.json").read_bytes())
assert len(inventory)==960
assert len({p["path"] for p in inventory})==960
for row in inventory: checked(row["path"],row["bytes"],row["sha256"])
# Bind exact original authority slices to their current contained full source.
authority=json.loads((D/"zig-shadowing-authority.json").read_bytes())
for row in authority:
 owner=row["authority"]; b=checked(owner["path"],owner["bytes"],owner["sha256"])
 excerpt=b"".join(b.splitlines(keepends=True)[row["first_line"]-1:row["last_line"]])
 assert len(excerpt)==row["bytes"] and sha(excerpt)==row["sha256"] and excerpt.decode()==row["text"]
assert len(authority)==2
# The separate identity draft remains at its selected pins throughout this peer.
identity=W/"verification/native-node-runtime-template-identity-sourceonly-20261020"
identity_paths=[
 identity/"production/src/extensions/native_node_runtime_template_identity.zig",
 identity/"shared/proposal.json",identity/"build/proposal.json",
 identity/"controls/src/native_node_runtime_template_identity_test.zig"]
identity_rows=[pin(p) for p in identity_paths]
assert identity_rows[0]["sha256"]=="1C029A4C5F220B2668DDC354CDF767C630549E56CA89557BE17234A3DDBFA7A8"
assert identity_rows[1]["sha256"]=="3CBDF1798B9FAFDDCDA77CDE738DA0709A23E7A59831B37B22A3E1849759994F"
assert identity_rows[2]["sha256"]=="B025CC27AE5548CA37063370B94A084BC2993578D7971082F0329F9682A16763"
assert len(re.findall(rb'^test "',identity_paths[3].read_bytes(),re.M))==16
assert git("rev-parse","HEAD").decode().strip()==HEAD and git("status","--porcelain")==b""
assert (M/REL).read_bytes()==original and (S/REL).read_bytes()==original
result={
 "schema":"pi-zig-v35-fixture-shadowing-independent-proof-v1",
 "main_head":HEAD,"proposal":pin(D/"proposal.json",proposal_raw),
 "packet_input_pins":sorted(checked_inputs.values(),key=lambda p:p["path"]),
 "independent_line_reconstruction":bindings,"identifier_tokens":25,"local_bindings":11,
 "all_unselected_lines_exact":True,"complete_forward_and_inverse_exact":True,
 "patch_exact":True,"public_declarations_function_names_imports_embeds_exact":True,
 "source_only_replay":{"preparation_source":pin(D/"prepare-proposal.py",preparation),
 "read_only_prefix_bytes":len(prefix),"read_only_prefix_sha256":sha(prefix),
 "excluded_marker":marker.decode(),"exact_outputs":reproduced},
 "complete_current_input_rehash":{"inventory":pin(D/"input-inventory.json"),"count":960},
 "four_complete_topologies":proof["graphs"],"declared_names_unchanged":58,
 "future_actual_metadata":None,"original_diagnostics":proof["compiler_errors_preserved"],
 "adjacent_length_capture":proof["unreported_adjacent_binding"],
 "contained_zig_authority":authority,
 "separate_phase_observer":{"finding":pin(finding,finding_bytes),
 "alpha_observer_lines":[196,215],"bytes":len(phase_original),"sha256":sha(phase_original),
 "original_bad_begin_read_preserved":True,"no_lifecycle_acceptance_claim":True},
 "preserved_identity_draft":identity_rows,
 "main_clean_before_and_after":True,"live_main_and_sdk_fixture_original":True,
 "execution":{"native":False,"compiler":False,"formatter":False,"metadata_auditor":False,
 "project_generator":False,"grant_constructor":False,"source_only_sdk_prefix":True}}
result_raw=jp(result)
peer={
 "schema":"pi-zig-v35-fixture-shadowing-independent-peer-v1",
 "status":"ACCEPTED FOR THE BOUNDED SOURCE-ONLY IDENTIFIER DELTA",
 "reviewer":"/root/module_io_port","proposal":pin(D/"proposal.json",proposal_raw),
 "original":pin(D/"original"/REL,original),"selected":pin(D/"projected"/REL,candidate),
 "audit_source":pin(Path(__file__)),"audit_result":pin(O/"source-audit.json",result_raw),
 "scope":"Independent full original fixture and entire patch read; exact line-based forward/inverse reconstruction of 25 identifier tokens in eleven bindings; independently rehashed 960 current input files and reproduced all ten SDK artifacts from the fully read output-free source prefix.",
 "findings":[
 "All ten reported Zig shadowing errors map to the intended local bindings. The adjacent line 384 length capture has the same source-level conflict and is explicitly recorded as an additional source finding, not an eleventh compiler diagnostic.",
 "The selected names remain local. The expose parameter changes spelling only; its public method name and type, all other method and field names, all type tokens, literals, operations, assertions, imports, whitespace and comments are preserved.",
 "Four root dependency topologies and all 58 declared control names are unchanged. The Error constructor root does not reach this fixture. Actual future compiler-selected metadata is unknown.",
 "The original beginAsyncClose completion-only observer is deliberately unchanged in this alpha packet. Its separate source finding is retained and must compose through a separately reviewed successor; this receipt does not accept that observer lifecycle.",
 "No concrete blocker remains in the selected alpha-renaming slice."],
 "manual_reads":[
 "Full 32,558-byte original fixture and the entire 7,029-byte unified patch.",
 "Full 16,040-byte SDK preparation source, proposal, token/graph proof and selected Zig language-reference excerpts.",
 "Ten terminal shadowing diagnostic messages and declaration notes, retained without interpreting a source repair as a successful compilation."],
 "proof_totals":{"local_bindings":11,"identifier_tokens":25,"reported_errors":10,
 "adjacent_source_only_binding":1,"reproduced_artifacts":10,"current_input_files":960,
 "root_topologies":4,"declared_controls":58,"authority_excerpts":2},
 "separate_phase_finding":pin(finding,finding_bytes),
 "limits":[
 "No compiler, native, formatter, Node reference, project generator, metadata auditor or grant constructor execution.",
 "No Main, SDK live fixture, build, catalog, cache, lease or unrelated source modification.",
 "No declaration of runtime success, process/artifact closure, full FileHandle correctness or future metadata counts.",
 "Root retains first-compile negative closure, source intake and fresh catalog/grant release authority."],
 "preservation":{"main_head":HEAD,"main_clean":True,"original_sdk_fixture":True,
 "identity_owner_shared_build_and_16_controls_pinned":True}}
peer_raw=jp(peer)
# FINAL OUTPUT PHASE: new peer evidence only.
O.mkdir(parents=True,exist_ok=True)
for name,content in [("source-audit.json",result_raw),("peer.json",peer_raw)]:
 with (O/name).open("xb") as f:f.write(content)
print(json.dumps({"peer":pin(O/"peer.json"),"proof":pin(O/"source-audit.json"),
 "checker":pin(Path(__file__)),"bindings":11,"tokens":25,"inputs":960,"names":58},indent=2))
