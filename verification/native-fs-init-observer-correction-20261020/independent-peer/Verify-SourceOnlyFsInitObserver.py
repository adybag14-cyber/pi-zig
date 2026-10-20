"""Source-only independent peer checks for the exact V34 FS init observer proposal."""
from pathlib import Path
import datetime,hashlib,json,re,subprocess
root=Path(r"C:\Users\adyba\pi-zig");main=root/"main"
proof=root/"evidence/independent-v34-fs-request-init-observer-source-peer-20261020"
proposal_path=root/"worktrees/sdk-owners-resume-20261018/verification/v34-fs-request-init-observer-correction-sourceonly-20261020/proposal.json"
shared_path=root/"worktrees/sdk-owners-resume-20261018/verification/native-file-handle-owner-sourceonly-20261020/shared/proposal.json"
head="c764130caf2f2c7c63728bec0f6d1e16ac5c59a4"
output=proof/"source-audit.json"
H=lambda b:hashlib.sha256(b).hexdigest().upper()
pins={}
def readpin(row):
 p=Path(row["path"]);assert p.is_relative_to(root),str(p)
 b=p.read_bytes();h=H(b)
 assert h==row["sha256"] and len(b)==row["bytes"],str(p)
 if str(p)in pins:assert pins[str(p)]["sha256"]==h
 pins[str(p)]=dict(path=str(p),bytes=len(b),sha256=h)
 return b
def obj(path,sha):
 b=path.read_bytes();assert H(b)==sha;readpin(dict(path=str(path),bytes=len(b),sha256=sha));return json.loads(b)
def git(*args,input=None):
 r=subprocess.run(["git","--no-optional-locks",*args],cwd=main,input=input,capture_output=True,check=True);return r.stdout
assert not output.exists()
assert git("rev-parse","HEAD").decode().strip()==head and git("status","--porcelain=v1","--untracked-files=all")==b""
proposal=obj(proposal_path,"E22848488C054D9B748CD6A7E078EFECF468D32804F8161842562250F4DBF454")
shared=obj(shared_path,"C195AE5D402ED457AF651D6BEB37B2BB8DBD3DF36CD74106EB172F00B64618FC")
triage=json.loads(readpin(proposal["causal_triage"]))
def allpins(value):
 if isinstance(value,dict):
  if set(("path","bytes","sha256"))<=value.keys():readpin(value)
  for child in value.values():allpins(child)
 elif isinstance(value,list):
  for child in value:allpins(child)
allpins(proposal);allpins(shared);allpins(triage)
assert proposal["basis_main_head"]==triage["basis_main_head"]==head
assert proposal["file_count"]==3 and proposal["sequential_edit_count"]==4
assert shared["file_count"]==5 and shared["sequential_edit_count"]==12
individual=[]
def forward(raw,edits,recorded):
 current=raw
 for e in edits:
  a=e["before"].encode();b=e["after"].encode()
  assert current.count(a)==1,(e["index"],"unique before")
  if recorded:
   assert H(current)==e["input_sha256"] and current.index(a)==e["offset_in_sequential_input"]
  current=current.replace(a,b)
  if recorded:assert H(current)==e["output_sha256"]
 return current
def inverse(raw,edits):
 current=raw
 for e in reversed(edits):
  a=e["before"].encode();b=e["after"].encode()
  assert current.count(b)==1,(e["index"],"unique after")
  current=current.replace(b,a)
 return current
for packet,label in [(proposal,"observer"),(shared,"C195")]:
 for f in packet["files"]:
  old=readpin(f["original"]);new=readpin(f["projected"]);live=readpin(f["source"])
  assert old==live and forward(old,f["edits"],True)==new and inverse(new,f["edits"])==old
  individual.append(dict(packet=label,relative_path=f["relative_path"],edits=len(f["edits"]),before_sha256=H(old),after_sha256=H(new),recorded_offsets_and_intermediate_hashes=True,whole_forward_and_inverse=True))
pmap={f["relative_path"]:f for f in proposal["files"]};smap={f["relative_path"]:f for f in shared["files"]}
union=sorted(pmap.keys()|smap.keys());assert len(union)==6
baselines={};composition=[]
cmap={f["relative_path"]:f for f in proposal["pending_filehandle_composition"]["files"]}
for rel in union:
 pf=pmap.get(rel);sf=smap.get(rel);before=readpin((pf or sf)["original"])
 if pf and sf:assert readpin(pf["original"])==readpin(sf["original"])
 pe=[]if pf is None else pf["edits"];se=[]if sf is None else sf["edits"]
 a=forward(forward(before,se,False),pe,False)
 b=forward(forward(before,pe,False),se,False)
 assert a==b==readpin(cmap[rel]["combined"])
 assert inverse(inverse(a,pe),se)==before and inverse(inverse(b,se),pe)==before
 baselines[rel]=before
 composition.append(dict(relative_path=rel,observer_edits=len(pe),shared_edits=len(se),combined_bytes=len(a),combined_sha256=H(a),both_orders_byte_identical=True,both_inverse_orders_exact=True))
for f in triage["files"]:
 rel=f["relative_path"];b=readpin(f["live"]);assert b==readpin(f["snapshot"])
 if rel in baselines:assert baselines[rel]==b
 baselines[rel]=b
specs=[head+":"+rel for rel in sorted(baselines)]
response=git("cat-file","--batch",input=("\n".join(specs)+"\n").encode());offset=0;git_basis=[]
for rel in sorted(baselines):
 end=response.index(b"\n",offset);header=response[offset:end].split();assert len(header)==3 and header[1]==b"blob"
 count=int(header[2]);start=end+1;blob=response[start:start+count]
 assert response[start+count:start+count+1]==b"\n" and blob==baselines[rel],rel
 git_basis.append(dict(relative_path=rel,bytes=len(blob),sha256=H(blob),raw_git_blob_identical=True));offset=start+count+1
assert offset==len(response)
for e in triage["excerpts"]:
 b=Path(e["path"]).read_bytes();assert H(b)==e["source_sha256"]
 actual=b.decode("utf-8").splitlines(keepends=True)[e["first_line"]-1:e["last_line"]]
 text="".join(actual)
 assert text==e["text"] and H(text.encode())==e["excerpt_sha256"]
def between(b,start,end):return b[b.index(start):b.index(end,b.index(start))]
c_old=readpin(pmap["src/extensions/native_uv_tcp.c"]["original"]);c_new=readpin(pmap["src/extensions/native_uv_tcp.c"]["projected"])
h_old=readpin(pmap["src/extensions/native_uv_fs.h"]["original"]);h_new=readpin(pmap["src/extensions/native_uv_fs.h"]["projected"])
t_old=readpin(pmap["src/native_node_fs_request_owner_test.zig"]["original"]);t_new=readpin(pmap["src/native_node_fs_request_owner_test.zig"]["projected"])
completion_old=between(c_old,b"PiUvFsInfo pi_uv_fs_request_info(",b"PiUvResult pi_uv_fs_request_create(")
completion_new=between(c_new,b"PiUvFsInfo pi_uv_fs_request_info(",b"PiUvResult pi_uv_fs_request_create(")
assert completion_old==completion_new and H(completion_old)==proposal["unchanged"]["completed_only_info_body_sha256"]
assert b"assert(atomic_load_explicit(&request->completed, memory_order_acquire));"in completion_new
layout_old=between(c_old,b"struct PiUvFsRequest {",b"\n};")+b"\n};"
layout_new=between(c_new,b"struct PiUvFsRequest {",b"\n};")+b"\n};"
assert layout_old==layout_new
assert between(h_old,b"typedef struct PiUvFsInfo {",b"} PiUvFsInfo;")==between(h_new,b"typedef struct PiUvFsInfo {",b"} PiUvFsInfo;")
observer=between(c_new,b"PiUvFsPreparationInfo pi_uv_fs_request_preparation_info(",b"PiUvFsInfo pi_uv_fs_request_info(")
assert set(re.findall(rb"request->([a-z_]+)",observer))=={b"submitted",b"kind",b"accepted",b"cleaned",b"completed"}
assert b"assert(request != NULL);"in observer and b"assert(!request->submitted);"in observer
assert not re.search(rb"request->[a-z_]+\s*(?:=(?!=)|\+\+|--)",observer)
assert all(x not in observer for x in [b"uv.result",b"uv.path",b"atomic_store",b"atomic_exchange",b"malloc(",b"pi_uv_alloc("])
assert observer.count(b"atomic_load_explicit(")==2
assert b"not a concurrent lifecycle snapshot" in h_new and b"no concurrent admission, cleanup, reset or release" in h_new
assert b"does not establish thread ownership" in h_new and b"caller must retain the request" in h_new
old_tests=re.findall(rb'^test "([^"]+)"',t_old,re.M);new_tests=re.findall(rb'^test "([^"]+)"',t_new,re.M)
assert old_tests==new_tests and len(new_tests)==len(set(new_tests))==25
assert [x.decode()for x in new_tests]==proposal["unchanged"]["named_declarations"]
assert t_old[t_old.index(b'test "'):] ==t_new[t_new.index(b'test "'):]
assert t_old.count(b"pi_uv_fs_request_info(")-1==t_new.count(b"pi_uv_fs_request_info(")
assert t_new.count(b"pi_uv_fs_request_preparation_info(")==1
for group in triage["runtime"]:assert readpin(group["authority"])==readpin(group["snapshot"])
assert git("rev-parse","HEAD").decode().strip()==head and git("status","--porcelain=v1","--untracked-files=all")==b""
result=dict(schema=1,status="independently_verified_exact_fs_init_observer_source_and_composition",reviewed_utc=datetime.datetime.now(datetime.timezone.utc).isoformat(),candidate_head=head,proposal= pins[str(proposal_path)],shared=pins[str(shared_path)],distinct_pinned_files=len(pins),pins=list(pins.values()),raw_git_basis=git_basis,individual_forward_inverse=individual,both_order_composition=composition,triage_excerpts_exact=len(triage["excerpts"]),completed_only_info_body=dict(bytes=len(completion_old),sha256=H(completion_old),byte_identical=True,assertion_preserved=True),request_layout_unchanged=True,existing_info_layout_unchanged=True,new_observer=dict(bytes=len(observer),sha256=H(observer),only_fields=["submitted","kind","accepted","cleaned","completed"],atomic_acquire_reads=2,payload_reads=False,state_writes=False,allocations=False,declared_owner_thread_precondition=True,concurrent_snapshot_claim=False),named_control_count=25,all_named_test_bodies_byte_identical=True,prior_negative_bytes_retained=True,main_unchanged=True,source_only=True,compiler_runtime_executed=False,qualification=False)
proof.mkdir(parents=True,exist_ok=True)
with output.open("xb")as f:f.write((json.dumps(result,indent=2)+"\n").encode())
print(json.dumps(dict(status=result["status"],path=str(output),bytes=output.stat().st_size,sha256=H(output.read_bytes()),distinct_pinned_files=len(pins),raw_git_basis_files=len(git_basis),observer_edits=4,shared_edits=12,combined_files=6,named_tests=25,main_unchanged=True,source_only=True,qualification=False)))
