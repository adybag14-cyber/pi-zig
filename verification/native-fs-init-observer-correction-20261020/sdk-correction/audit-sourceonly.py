from pathlib import Path
import hashlib,json,re,sys
out=Path(sys.argv[1])
def sha(b):return hashlib.sha256(b).hexdigest().upper()
def check_pin(record):
 p=Path(record["path"]);b=p.read_bytes()
 assert len(b)==record["bytes"] and sha(b)==record["sha256"],str(p)
 return b
proposal_path=out/"proposal.json"
proposal_bytes=proposal_path.read_bytes()
assert sha(proposal_bytes)=="E22848488C054D9B748CD6A7E078EFECF468D32804F8161842562250F4DBF454"
proposal=json.loads(proposal_bytes)
original={};selected={};own_edits={}
for f in proposal["files"]:
 rel=f["relative_path"];before=check_pin(f["original"]);after=check_pin(f["projected"])
 current=before;items=[]
 for e in f["edits"]:
  a=e["before"].encode();b=e["after"].encode()
  assert sha(current)==e["input_sha256"] and current.count(a)==1
  assert current.index(a)==e["offset_in_sequential_input"]
  current=current.replace(a,b,1);assert sha(current)==e["output_sha256"]
  items.append((a,b))
 assert current==after
 for a,b in reversed(items):
  assert current.count(b)==1;current=current.replace(b,a,1)
 assert current==before
 original[rel]=before;selected[rel]=after;own_edits[rel]=items
c195=json.loads(check_pin(proposal["pending_filehandle_composition"]["predecessor_packet"]))
shared={};shared_edits={}
for f in c195["files"]:
 rel=f["relative_path"];before=check_pin(f["original"]);after=check_pin(f["projected"])
 current=before;items=[]
 for e in f["edits"]:
  a=e["before"].encode();b=e["after"].encode()
  assert sha(current)==e["input_sha256"] and current.count(a)==1
  assert current.index(a)==e["offset_in_sequential_input"]
  current=current.replace(a,b,1);assert sha(current)==e["output_sha256"]
  items.append((a,b))
 assert current==after
 for a,b in reversed(items):
  assert current.count(b)==1;current=current.replace(b,a,1)
 assert current==before
 if rel in original:assert original[rel]==before
 shared[rel]=before;shared_edits[rel]=items
union={**shared,**original}
def apply(values,groups,inverse=False):
 result=dict(values)
 for rel,items in groups.items():
  current=result[rel]
  for a,b in ([(b,a) for a,b in reversed(items)] if inverse else items):
   assert current.count(a)==1
   current=current.replace(a,b,1)
  result[rel]=current
 return result
left=apply(apply(union,shared_edits),own_edits)
right=apply(apply(union,own_edits),shared_edits)
assert left==right
assert apply(apply(left,own_edits,True),shared_edits,True)==union
assert apply(apply(right,shared_edits,True),own_edits,True)==union
for f in proposal["pending_filehandle_composition"]["files"]:
 assert check_pin(f["combined"])==left[f["relative_path"]]
triage=json.loads(check_pin(proposal["causal_triage"]))
for f in triage["files"]:check_pin(f["snapshot"])
for r in triage["runtime"]:check_pin(r["authority"]);check_pin(r["snapshot"])
for e in triage["excerpts"]:
 b=Path(e["path"]).read_bytes();assert sha(b)==e["source_sha256"]
 text="\n".join(b.decode("utf-8").splitlines()[e["first_line"]-1:e["last_line"]])+"\n"
 assert text==e["text"] and sha(text.encode())==e["excerpt_sha256"]
test="src/native_node_fs_request_owner_test.zig";source="src/extensions/native_uv_tcp.c"
sig=b"PiUvFsInfo pi_uv_fs_request_info(const PiUvFsRequest *request) {"
def fn(b):
 at=b.index(sig);end=b.index(b"\n}\n",at)+3;return b[at:end]
assert fn(original[source])==fn(selected[source])
assert sha(fn(original[source]))==proposal["unchanged"]["completed_only_info_body_sha256"]
assert original[test][original[test].index(b'\ntest "'):]==selected[test][selected[test].index(b'\ntest "'):]
names=re.findall(r'^test "([^"]+)"',selected[test].decode(),re.M)
assert names==proposal["unchanged"]["named_declarations"]==triage["named_declarations"]
print(json.dumps({"schema":"v34-fs-init-observer-static-replay-v1","source_only":True,
 "proposal_sha256":sha(proposal_bytes),"own_files":len(original),"own_edits":sum(map(len,own_edits.values())),
 "c195_files":len(shared),"c195_edits":sum(map(len,shared_edits.values())),"combined_files":len(union),
 "both_forward_orders_identical":True,"both_full_inverses_exact":True,
 "completed_info_body_unchanged":True,"entire_test_declaration_section_unchanged":True,
 "declared_names":len(names),"runtime_negative_files_preserved":len(triage["runtime"]),
 "exact_causal_excerpts":len(triage["excerpts"]),"native_compiler_execution":False},indent=2))
