"""Exact three-phase Main source intake; no compiler, runtime, generator or push."""
from pathlib import Path, PurePosixPath
import datetime, hashlib, json, os, subprocess, sys
ROOT=Path(r"C:\Users\adyba\pi-zig")
MAIN=ROOT/"main"
BASIS="c764130caf2f2c7c63728bec0f6d1e16ac5c59a4"
BRANCH="work/pi-zig-consolidated-20261016"
MANIFESTS={
 "owner-error":("evidence/pending-file-handle-error-main-intake-20261020/manifest.json","A905E15D794738ADDED8DE272771545D72380B085750175804E82139B78869C4",192,"Port native FileHandle lifecycle and Error constructor provenance"),
 "reqwrap":("evidence/pending-v34-reqwrap-fixture-main-intake-20261020/manifest.json","068136AC825829162A45AB03D9A1F60633EF8AF2D83061BAEC7CD7082FDE60E1",10,"Correct ReqWrap fixture for the actual host error boundary"),
 "fs-init":("evidence/pending-v34-fs-init-observer-main-intake-20261020/manifest.json","8CCF654B605C496E1E188E12EFD8CAFA6BF54B84CEBD58731A3219196DCA6D70",34,"Observe FS request preparation before native completion"),
}
def sha(b): return hashlib.sha256(b).hexdigest().upper()
def raw(p): return Path(p).read_bytes()
def pinned(p,h):
 b=raw(p); assert sha(b)==h,(str(p),sha(b),h); return b
def git(*args,input=None,check=True):
 q=subprocess.run(["git",*args],cwd=MAIN,input=input,capture_output=True)
 if check: assert q.returncode==0,(args,q.returncode,q.stdout.decode("utf-8",errors="replace"),q.stderr.decode("utf-8",errors="replace"))
 return q
def gout(*args): return git(*args).stdout.decode("utf-8").strip()
def inside(p,base):
 p=Path(p).resolve(); base=Path(base).resolve()
 assert p==base or base in p.parents,(str(p),str(base))
 return p
def new_file(p,b):
 p=Path(p); assert not p.exists(),str(p)
 p.parent.mkdir(parents=True,exist_ok=True)
 with p.open("xb") as f: f.write(b)
def new_json(p,v): new_file(p,(json.dumps(v,indent=2,ensure_ascii=False)+"\n").encode("utf-8"))
def blob_many(specs):
 if not specs: return []
 response=git("cat-file","--batch",input=("\n".join(specs)+"\n").encode("utf-8")).stdout
 offset=0; result=[]
 for spec in specs:
  end=response.index(b"\n",offset); header=response[offset:end].split()
  assert len(header)==3 and header[1]==b"blob",(spec,header)
  size=int(header[2]); start=end+1; body=response[start:start+size]
  assert len(body)==size and response[start+size:start+size+1]==b"\n",spec
  result.append(body); offset=start+size+1
 assert offset==len(response)
 return result
def tree_paths(revision):
 return set(x.decode("utf-8") for x in git("ls-tree","-r","--name-only","-z",revision).stdout.split(b"\0") if x)
def no_hooks():
 q=git("config","--get","core.hooksPath",check=False); assert q.returncode==1
 hooks=Path(gout("rev-parse","--git-path","hooks"))
 if not hooks.is_absolute(): hooks=MAIN/hooks
 assert not [p for p in hooks.iterdir() if p.is_file() and not p.name.endswith(".sample")]
 assert gout("config","--get","core.autocrlf")=="false"
assert len(sys.argv)==4,"phase release-path release-sha256"
phase,release_path,release_sha=sys.argv[1:]
assert phase in MANIFESTS
release_path=inside(release_path,ROOT/"evidence")
release=json.loads(pinned(release_path,release_sha))
self_sha=sha(raw(__file__))
assert release["executor_sha256"]==self_sha
assert release["basis_main_head"]==BASIS
assert release["branch"]==BRANCH
assert release["source_intake_authorized"] is True
assert release["native_execution_authorized"] is False
assert release["application_qualified"] is False
assert phase in release["authorized_phases"]
for pin in release["required_current_pins"]:
 b=pinned(inside(pin["path"],ROOT),pin["sha256"]); assert len(b)==pin["bytes"]
proof=inside(release["receipt_directory"],ROOT/"evidence")
receipt_path=proof/(phase+"-receipt.json")
assert not receipt_path.exists()
assert gout("branch","--show-current")==BRANCH
assert git("status","--porcelain=v1","--untracked-files=all").stdout==b""
no_hooks()
manifest_rel,manifest_sha,count,subject=MANIFESTS[phase]
manifest_path=ROOT/manifest_rel; manifest_raw=pinned(manifest_path,manifest_sha)
manifest=json.loads(manifest_raw)
assert release["authorized_phases"][phase]["manifest_sha256"]==manifest_sha
assert release["authorized_phases"][phase]["total_commit_paths"]==count
head=gout("rev-parse","HEAD")
if phase=="owner-error":
 assert head==BASIS
elif phase=="reqwrap":
 prior_raw=raw(proof/"owner-error-receipt.json"); prior=json.loads(prior_raw)
 assert prior["status"]=="exact_source_intake_committed"
 assert prior["executor_sha256"]==self_sha and prior["release_sha256"]==release_sha
 assert prior["manifest_sha256"]==MANIFESTS["owner-error"][1]
 assert prior["before_head"]==BASIS and prior["after_head"]==head
 assert prior["path_count"]==192 and prior["staged_and_committed_bytes_match"] is True
 assert gout("rev-parse",head+"^")==BASIS
else:
 assert phase=="fs-init"
 owner=json.loads(raw(proof/"owner-error-receipt.json"))
 prior=json.loads(raw(proof/"reqwrap-receipt.json"))
 for name,receipt in (("owner-error",owner),("reqwrap",prior)):
  assert receipt["status"]=="exact_source_intake_committed"
  assert receipt["executor_sha256"]==self_sha and receipt["release_sha256"]==release_sha
  assert receipt["manifest_sha256"]==MANIFESTS[name][1]
  assert receipt["path_count"]==MANIFESTS[name][2] and receipt["staged_and_committed_bytes_match"] is True
 assert owner["before_head"]==BASIS and prior["before_head"]==owner["after_head"]
 assert prior["after_head"]==head and gout("rev-parse",head+"^")==owner["after_head"]
 assert gout("rev-parse",owner["after_head"]+"^")==BASIS
 assert manifest["required_predecessor_manifests"]==[MANIFESTS["owner-error"][1],MANIFESTS["reqwrap"][1]]
rows=manifest["rows"]
target_manifest=manifest.get("target_manifest",manifest.get("manifest_target"))
assert target_manifest
allrows=[*rows,{"target":target_manifest,"source":str(manifest_path),"bytes":len(manifest_raw),"sha256":manifest_sha,"before":None,"role":"exact_intake_manifest"}]
assert len(allrows)==count
names=[]; contents=[]; preimages=[]; basis_paths=tree_paths(BASIS); head_paths=tree_paths(head)
for row in allrows:
 rel=row["target"]; pp=PurePosixPath(rel)
 assert not pp.is_absolute() and "\\" not in rel and ":" not in rel and all(x not in ("..",".") for x in pp.parts),rel
 assert rel=="build.zig" or rel.startswith(("src/","vendor/quickjs/","verification/")),rel
 target=inside(MAIN/rel,MAIN); donor=inside(row["source"],ROOT)
 b=pinned(donor,row["sha256"]); assert len(b)==row["bytes"]
 names.append(rel); contents.append(b)
 before=row["before"]
 if before is None:
  assert not target.exists() and rel not in basis_paths and rel not in head_paths,rel
 else:
  old=pinned(target,before["sha256"]); assert len(old)==before["bytes"]
  assert rel in basis_paths and rel in head_paths,rel
  preimages.append((row,old))
assert len(set(x.casefold() for x in names))==count
preimage_reference=head if phase=="fs-init" else BASIS
for (row,old),blob in zip(preimages,blob_many([preimage_reference+":"+row["target"] for row,_ in preimages])):
 assert blob==old,("basis_preimage",row["target"])
for (row,old),blob in zip(preimages,blob_many([head+":"+row["target"] for row,_ in preimages])):
 assert blob==old,("head_preimage",row["target"])
for rel in names:
 parts=PurePosixPath(rel).parts
 for depth in range(1,len(parts)):
  parent=MAIN.joinpath(*parts[:depth])
  assert not parent.is_symlink(),str(parent)
assert gout("rev-parse","HEAD")==head and git("status","--porcelain=v1","--untracked-files=all").stdout==b""
proof.mkdir(parents=True,exist_ok=True)
preflight={"phase":phase,"utc":datetime.datetime.now(datetime.timezone.utc).isoformat(),"before_head":head,"basis_head":BASIS,"release":str(release_path),"release_sha256":release_sha,"executor_sha256":self_sha,"manifest":str(manifest_path),"manifest_sha256":manifest_sha,"path_count":count,"all_donors_live_preimages_and_committed_basis_verified":True,"rows":[{k:r[k] for k in ("target","role","bytes","sha256","before")} for r in allrows],"native_execution_authorized":False,"qualification":False}
new_json(proof/(phase+"-preflight.json"),preflight)
pathspec=proof/(phase+"-paths.nul"); new_file(pathspec,b"\0".join(x.encode("utf-8") for x in names)+b"\0")
message=proof/(phase+"-commit-message.txt"); new_file(message,(subject+"\n\nSource-reviewed intake only. Native runtime and full application qualification remain pending.\n").encode("utf-8"))
for index,(row,b) in enumerate(zip(allrows,contents)):
 target=MAIN/row["target"]; before=row["before"]
 if before is None: new_file(target,b)
 else:
  assert sha(raw(target))==before["sha256"]
  temporary=proof/(phase+"-replacement-"+str(index)+".tmp")
  new_file(temporary,b); os.replace(temporary,target)
 assert raw(target)==b
git("add","--pathspec-from-file="+str(pathspec),"--pathspec-file-nul")
staged=[x.decode("utf-8") for x in git("diff","--cached","--name-only","-z").stdout.split(b"\0") if x]
assert set(staged)==set(names) and len(staged)==count
assert git("diff","--name-only","-z").stdout==b""
assert git("ls-files","--others","--exclude-standard","-z").stdout==b""
for rel,b,blob in zip(names,contents,blob_many([":"+rel for rel in names])):
 assert b==blob,("index",rel)
assert gout("rev-parse","HEAD")==head
new_json(proof/(phase+"-staged.json"),{"before_head":head,"path_count":count,"exact_index_blob_bytes_verified":True,"manifest_sha256":manifest_sha,"executor_sha256":self_sha,"release_sha256":release_sha})
commit=git("commit","--file="+str(message))
after=gout("rev-parse","HEAD")
assert after!=head and gout("rev-parse",after+"^")==head
changed=[x.decode("utf-8") for x in git("diff-tree","--no-commit-id","--name-only","-r","-z",after).stdout.split(b"\0") if x]
assert set(changed)==set(names) and len(changed)==count
for rel,b,blob in zip(names,contents,blob_many([after+":"+rel for rel in names])):
 assert b==blob and raw(MAIN/rel)==b,("committed",rel)
assert git("status","--porcelain=v1","--untracked-files=all").stdout==b""
receipt={"status":"exact_source_intake_committed","phase":phase,"utc":datetime.datetime.now(datetime.timezone.utc).isoformat(),"before_head":head,"after_head":after,"basis_main_head":BASIS,"branch":BRANCH,"manifest":str(manifest_path),"manifest_sha256":manifest_sha,"executor_sha256":self_sha,"release_sha256":release_sha,"path_count":count,"staged_and_committed_bytes_match":True,"clean_worktree":True,"commit_stdout":commit.stdout.decode("utf-8"),"commit_stderr":commit.stderr.decode("utf-8"),"native_execution_authorized":False,"application_qualified":False,"production_bridge_removed":False}
new_json(receipt_path,receipt)
print(json.dumps({"receipt":str(receipt_path),"bytes":receipt_path.stat().st_size,"sha256":sha(raw(receipt_path)),"phase":phase,"commit":after,"paths":count,"clean":True,"qualification":False}))
