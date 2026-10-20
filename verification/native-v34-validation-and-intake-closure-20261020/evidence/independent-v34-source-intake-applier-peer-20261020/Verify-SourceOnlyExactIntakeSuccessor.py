"""Independent read-only finite successor review. Writes only one new evidence report."""
from pathlib import Path, PurePosixPath
import ast, concurrent.futures, copy, hashlib, json, os, stat, subprocess
ROOT=Path(r"C:\Users\adyba\pi-zig"); MAIN=ROOT/"main"; E=ROOT/"evidence"
OUT=E/"independent-v34-source-intake-applier-peer-20261020"/"successor-source-audit.json"
BASIS="c764130caf2f2c7c63728bec0f6d1e16ac5c59a4"
ENV=dict(os.environ,GIT_OPTIONAL_LOCKS="0")
def sha(b): return hashlib.sha256(b).hexdigest().upper()
def inf(p,b=None):
 p=Path(p); b=p.read_bytes() if b is None else b
 return {"path":str(p),"bytes":len(b),"sha256":sha(b)}
pins={}
def pin(p,h,n=None):
 p=Path(p); b=p.read_bytes()
 assert sha(b)==h,(str(p),sha(b),h)
 if n is not None: assert len(b)==n
 pins[str(p)]=inf(p,b); return b
def g(*a,data=None,check=True):
 r=subprocess.run(["git",*a],cwd=MAIN,input=data,capture_output=True,env=ENV)
 if check: assert r.returncode==0,(a,r.returncode,r.stderr.decode(errors="replace"))
 return r
def gt(*a):return g(*a).stdout.decode().strip()
def dump(x):return (json.dumps(x,indent=2,ensure_ascii=False)+"\n").encode()
assert not OUT.exists()
assert gt("rev-parse","HEAD")==BASIS and gt("branch","--show-current")=="work/pi-zig-consolidated-20261016"
assert g("status","--porcelain=v1","--untracked-files=all").stdout==b""
assert gt("config","--get","core.autocrlf")=="false"
assert g("config","--get","core.hooksPath",check=False).returncode==1
hooks=Path(gt("rev-parse","--git-path","hooks"))
if not hooks.is_absolute():hooks=MAIN/hooks
assert not [p for p in hooks.iterdir() if p.is_file() and not p.name.endswith(".sample")]
index=Path(gt("rev-parse","--git-path","index"))
if not index.is_absolute():index=MAIN/index
index_before=inf(index)
attrs_before=inf(MAIN/".gitattributes")
protected=pin(MAIN/"src/extensions/native_node_async_wrap.zig","972B9D098E93A138A8F6333CDAD829CAFE4D6E6855B2E1811B4623F57E39FCA2")
adaptations=[
 ("v34-three-phase-intake-executor-successor.json","EA06B70FD1264C46866B5C98CFBD00F4EF38F8A985E66D952BCB0F7C432F0B63",5),
 ("v34-intake-executor-exact-blob-successor.json","511C9AA1362EEDE9000197415D25EC08E72438B566D23B2DFAF313D4D4220798",7)]
adapt_results=[]
for name,h,n in adaptations:
 d=json.loads(pin(E/name,h)); start=pin(d["baseline"]["path"],d["baseline"]["sha256"],d["baseline"]["bytes"]); end=pin(d["candidate"]["path"],d["candidate"]["sha256"],d["candidate"]["bytes"])
 ast.parse(start);ast.parse(end); current=start
 assert len(d["edits"])==n
 for x in d["edits"]:
  a=x["before"].encode();b=x["after"].encode()
  assert sha(current)==x["before_sha256"] and current.count(a)==x["occurrences"]
  current=current.replace(a,b)
  assert sha(current)==x["after_sha256"]
 assert current==end
 for x in reversed(d["edits"]):
  a=x["before"].encode();b=x["after"].encode()
  assert sha(current)==x["after_sha256"] and current.count(b)==x["occurrences"]
  current=current.replace(b,a)
  assert sha(current)==x["before_sha256"]
 assert current==start
 adapt_results.append({"path":str(E/name),"edits":n,"every_intermediate_hash":True,"complete_forward_and_inverse":True})
configs=[
 ("owner-error","pending-file-handle-error-main-intake-20261020","A905E15D794738ADDED8DE272771545D72380B085750175804E82139B78869C4","5730CB5FA9F17FE33478C128E763287E59A37477B2AF2A0820BBCA002D0FADCF",192),
 ("reqwrap","pending-v34-reqwrap-fixture-main-intake-20261020","068136AC825829162A45AB03D9A1F60633EF8AF2D83061BAEC7CD7082FDE60E1","BA8482D0DA4837630E158C5F345C9D5F58D8AE2614F8F372E164EDB9894EEF73",10),
 ("fs-init","pending-v34-fs-init-observer-main-intake-20261020","8CCF654B605C496E1E188E12EFD8CAFA6BF54B84CEBD58731A3219196DCA6D70","21093750D07017BCA35F42D958AA758B8B4BC030920190ADC003BDA1246371E8",34)]
oldtarget="verification/native-file-handle-error-intake-20261020/sdk/native-file-handle-close-settlement-followup-sourceonly-20261020/support/src/extensions/native_node_operation_scope.zig"
newtarget=oldtarget+".raw"
tree={s.decode() for s in g("ls-tree","-r","--name-only","-z",BASIS).stdout.split(b"\0") if s}
virtual={};live_basis={}; all_jobs=[]; phases=[]; source_targets=set(); cross_phase=[]
for phase,directory,oldh,newh,count in configs:
 oldp=E/directory/"manifest.json";newp=E/directory/"manifest-v2.json"
 oldraw=pin(oldp,oldh);newraw=pin(newp,newh);old=json.loads(oldraw);new=json.loads(newraw)
 assert dump(old)==oldraw and dump(new)==newraw
 inverse=copy.deepcopy(new); successor=inverse.pop("immutable_successor")
 assert successor["previous_manifest"]==inf(oldp,oldraw)
 if phase=="owner-error":
  changed=[i for i,(x,y) in enumerate(zip(old["rows"],new["rows"])) if x!=y]
  assert changed==[72] and len(old["rows"])==len(new["rows"])==191
  assert inverse["rows"][72]["target"]==newtarget
  inverse["rows"][72]["target"]=oldtarget
  assert {k:v for k,v in old["rows"][72].items() if k!="target"}=={k:v for k,v in new["rows"][72].items() if k!="target"}
  assert new["source_build_paths"]==17 and new["declared_new_controls"]==45
 elif phase=="reqwrap":
  assert old["rows"]==new["rows"]
  assert new["preceding_separate_owner_error_intake"]==inf(E/configs[0][1]/"manifest-v2.json")
  inverse["preceding_separate_owner_error_intake"]=old["preceding_separate_owner_error_intake"]
 else:
  assert old["rows"]==new["rows"]
  assert new["required_predecessor_manifests"]==[configs[0][3],configs[1][3]]
  inverse["required_predecessor_manifests"]=old["required_predecessor_manifests"]
 assert inverse==old and dump(inverse)==oldraw
 forward=copy.deepcopy(inverse)
 if phase=="owner-error":forward["rows"][72]["target"]=newtarget
 elif phase=="reqwrap":forward["preceding_separate_owner_error_intake"]=new["preceding_separate_owner_error_intake"]
 else:forward["required_predecessor_manifests"]=new["required_predecessor_manifests"]
 forward["immutable_successor"]=successor
 assert dump(forward)==newraw
 rows=[*new["rows"],{"target":new.get("target_manifest",new.get("manifest_target")),"source":str(newp),"bytes":len(newraw),"sha256":newh,"before":None,"role":"manifest"}]
 assert len(rows)==count
 canonical=set();namekeys=set();pres=[];phase_source=[]
 for r in rows:
  rel=r["target"]; pp=PurePosixPath(rel);target=MAIN/rel;donor=Path(r["source"])
  assert rel and not pp.is_absolute() and "\\" not in rel and ":" not in rel and "\0" not in rel
  assert rel=="build.zig" or rel.startswith(("src/","vendor/quickjs/","verification/"))
  assert all(x not in ("",".","..") and x.rstrip(" .")==x and x.split(".")[0].upper() not in {"CON","PRN","AUX","NUL",*[f"COM{i}" for i in range(1,10)],*[f"LPT{i}" for i in range(1,10)]} for x in pp.parts)
  resolved=target.resolve();assert MAIN.resolve() in resolved.parents
  key=str(resolved).casefold();assert key not in canonical;canonical.add(key)
  assert rel.casefold() not in namekeys;namekeys.add(rel.casefold())
  assert ROOT.resolve() in donor.resolve().parents
  for parent in [target,*target.parents]:
   if parent==MAIN.parent:break
   if parent.exists():assert not parent.is_symlink() and not (getattr(parent.lstat(),"st_file_attributes",0)&stat.FILE_ATTRIBUTE_REPARSE_POINT),str(parent)
  b=pin(donor,r["sha256"],r["bytes"])
  before=r["before"]
  if before is None:
   assert not target.exists() and rel not in tree and rel not in virtual,rel
  else:
   if rel in virtual:
    oldbytes=virtual[rel];cross_phase.append({"phase":phase,"target":rel,"before_sha256":sha(oldbytes),"after_sha256":sha(b)})
   else:
    oldbytes=target.read_bytes();assert rel in tree
    blob=g("show",BASIS+":"+rel).stdout;assert blob==oldbytes,rel
    live_basis[rel]=inf(target,oldbytes)
   assert len(oldbytes)==before["bytes"] and sha(oldbytes)==before["sha256"],rel
   pres.append({"target":rel,"bytes":len(oldbytes),"sha256":sha(oldbytes),"source":"prior_projected_phase" if rel in virtual else "raw_basis_and_current"})
  virtual[rel]=b
  if not rel.startswith("verification/"):source_targets.add(rel);phase_source.append(rel)
  assert not rel.endswith(".gitattributes") and rel!=".gitattributes"
  all_jobs.append((phase,rel,b))
 phases.append({"phase":phase,"manifest":inf(newp,newraw),"path_count":count,"canonical_windows_target_count":len(canonical),"source_build_paths":phase_source,"preimages":pres,"manifest_complete_forward_inverse":True})
assert [len(p["source_build_paths"]) for p in phases]==[17,1,3]
assert len(source_targets)==19 and len(virtual)==234 and len(all_jobs)==236
assert {x["target"] for x in cross_phase}=={"src/extensions/native_uv_fs.h","src/extensions/native_uv_tcp.c"}
assert oldtarget not in virtual and newtarget in virtual
raw=virtual[newtarget];assert len(raw)==7087 and raw.count(b"\r\n")==92 and sha(raw)=="CD8111EE00100BE90E741BD658770EC7E4344EF1EF90689908EDC39C1CE5C1F9"
names=[x[1] for x in all_jobs]; attrs={}
tokens=g("check-attr","-z","--stdin","text","eol","filter","working-tree-encoding","ident",data=b"\0".join(x.encode() for x in names)+b"\0").stdout.split(b"\0")[:-1]
assert len(tokens)==15*len(names)
for i in range(0,len(tokens),3):
 path,attr,value=(x.decode() for x in tokens[i:i+3]);assert path in names
 attrs.setdefault(path,{})[attr]=value
for rel in names:
 assert set(attrs[rel])=={"text","eol","filter","working-tree-encoding","ident"}
 assert all(attrs[rel][x] in ("unspecified","unset") for x in ("filter","working-tree-encoding","ident"))
assert attrs[newtarget]["text"]=="unset" and attrs[newtarget]["eol"]=="unspecified"
def check_blob(item):
 phase,rel,b=item
 expected=hashlib.sha1(b"blob "+str(len(b)).encode()+b"\0"+b).hexdigest()
 actual=g("hash-object","--path="+rel,"--stdin",data=b).stdout.decode().strip()
 assert expected==actual,(rel,expected,actual)
 return {"phase":phase,"target":rel,"bytes":len(b),"sha256":sha(b),"raw_git_blob":expected,"actual_filtered_git_blob":actual,"attributes":attrs[rel]}
with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool: conversions=list(pool.map(check_blob,all_jobs))
pin(E/"independent-v34-source-intake-applier-peer-20261020/source-review-preflight-negative.json","5942BF34E68E5CFE5B6A9738DF55E992111D26EC038F21C96FF334D79AF69AFB")
pin(E/"independent-v34-source-intake-applier-peer-20261020/all-target-git-conversion-observation.json","BFE8403E3AAB65092954842E3B809F523BC124BEBFE1AFFD741EF94174971E04")
pin(E/"independent-v34-fs-request-init-observer-source-peer-20261020/peer.json","01BB78974EAF63864A20ACD1FE17A49E8EF57A1F718D70EC11C1ACABA6E13841")
assert gt("rev-parse","HEAD")==BASIS and g("status","--porcelain=v1","--untracked-files=all").stdout==b""
assert inf(index)==index_before and inf(MAIN/".gitattributes")==attrs_before
assert (MAIN/"src/extensions/native_node_async_wrap.zig").read_bytes()==protected
report={"schema":1,"status":"independent_source_only_exact_intake_successor_checks_passed","candidate_head":BASIS,"executor_sha256":"20E068A4537D96B30823DA910FCBC83587585125CA0CB628C1044F98068A51C4","adaptations":adapt_results,"phase_checks":phases,"cross_phase_preimages":cross_phase,"all_phase_path_occurrences":236,"distinct_targets":234,"distinct_source_build_targets":19,"distinct_raw_basis_preimages":len(live_basis),"all_donors_hash_and_size_verified":True,"conversion_count":0,"actual_git_filtered_blob_checks":conversions,"raw_basis_pins":live_basis,"verified_input_files":list(pins.values()),"index_before_after":index_before,"attributes_before_after":attrs_before,"no_main_index_or_git_object_writes":True,"source_intake_execution_authorized":False,"native_execution_authorized":False,"qualification":False,"original_negative_preserved":True}
body=dump(report);OUT.parent.mkdir(parents=True,exist_ok=True)
with OUT.open("xb") as f:f.write(body)
print(json.dumps({"report":inf(OUT,body),"phase_counts":[p["path_count"] for p in phases],"paths":len(all_jobs),"distinct_targets":len(virtual),"source_targets":len(source_targets),"raw_basis_preimages":len(live_basis),"verified_files":len(pins),"conversions":0,"main_unchanged":True,"execution_authorized":False},indent=2))
