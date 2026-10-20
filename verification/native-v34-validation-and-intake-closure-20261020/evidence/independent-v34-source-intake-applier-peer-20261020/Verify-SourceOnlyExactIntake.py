"""Independent read-only exact-manifest and source review support; never executes the intake applier."""
from pathlib import Path,PurePosixPath
import ast,collections,datetime,hashlib,json,os,re,stat,subprocess
root=Path(r"C:\Users\adyba\pi-zig");main=root/"main";proof=root/"evidence/independent-v34-source-intake-applier-peer-20261020"
head="c764130caf2f2c7c63728bec0f6d1e16ac5c59a4"
executor=root/"evidence/Apply-ExactV34ReviewedSourceIntakes-20261020.py"
H=lambda b:hashlib.sha256(b).hexdigest().upper()
def git(*args,input=None,allowed=(0,)):
 r=subprocess.run(["git","--no-optional-locks",*args],cwd=main,input=input,capture_output=True);assert r.returncode in allowed,(args,r.stderr.decode());return r.stdout
pins={}
def pin(p,expected=None,size=None):
 p=Path(p);assert p.resolve().is_relative_to(root.resolve()),str(p)
 b=p.read_bytes();h=H(b)
 if expected is not None:assert h==expected,(str(p),h)
 if size is not None:assert len(b)==size,(str(p),len(b))
 pins[str(p)]=dict(path=str(p),bytes=len(b),sha256=h)
 return b
assert not (proof/"source-audit.json").exists()
assert git("rev-parse","HEAD").decode().strip()==head and git("status","--porcelain=v1","--untracked-files=all")==b""
assert git("branch","--show-current").decode().strip()=="work/pi-zig-consolidated-20261016"
executor_bytes=pin(executor,"2DBB8B373038AD54095AB7E1EADB09594C593F923321F461000CEFBCE2283F1A",9547);ast.parse(executor_bytes)
specs=[("owner-error",root/"evidence/pending-file-handle-error-main-intake-20261020/manifest.json","A905E15D794738ADDED8DE272771545D72380B085750175804E82139B78869C4",192),("reqwrap",root/"evidence/pending-v34-reqwrap-fixture-main-intake-20261020/manifest.json","068136AC825829162A45AB03D9A1F60633EF8AF2D83061BAEC7CD7082FDE60E1",10)]
tree_rows=git("ls-tree","-r","-z",head).split(b"\0")[:-1];tree={}
for row in tree_rows:
 meta,name=row.split(b"\t",1);mode,kind,oid=meta.split();tree[name.decode()]=dict(mode=mode.decode(),type=kind.decode(),oid=oid.decode())
names=[];preimages=[];phase_summaries=[];contents={}
reserved={"CON","PRN","AUX","NUL",*[f"COM{i}"for i in range(1,10)],*[f"LPT{i}"for i in range(1,10)]}
parent_checks=set()
for phase,path,sha,count in specs:
 raw=pin(path,sha);j=json.loads(raw)
 assert (j.get("basis_main_head")or j.get("comparison_head"))==head
 target_manifest=j.get("target_manifest",j.get("manifest_target"));assert target_manifest
 rows=j["rows"]+[dict(target=target_manifest,source=str(path),bytes=len(raw),sha256=sha,before=None,role="exact_intake_manifest")]
 assert len(rows)==count
 phase_names=[]
 for row in rows:
  rel=row["target"];parts=PurePosixPath(rel).parts
  assert rel==PurePosixPath(rel).as_posix()and not PurePosixPath(rel).is_absolute()and "\\"not in rel
  assert parts and all(part and part not in(".","..")and part==part.rstrip(" .")and not re.search(r'[\x00-\x1f<>:"|?*]',part)and part.split(".")[0].upper()not in reserved for part in parts),rel
  assert rel=="build.zig"or rel.startswith(("src/","vendor/quickjs/","verification/"))
  target=main/rel;assert target.resolve().is_relative_to(main.resolve())
  for depth in range(1,len(parts)+1):
   ancestor=main.joinpath(*parts[:depth])
   if ancestor.exists():
    parent_checks.add(str(ancestor));assert not ancestor.is_symlink()and not(ancestor.lstat().st_file_attributes&stat.FILE_ATTRIBUTE_REPARSE_POINT),str(ancestor)
  data=pin(row["source"],row["sha256"],row["bytes"]);contents[rel]=data
  if row["before"]is None:
   assert rel not in tree and not target.exists(),rel
  else:
   old=pin(target,row["before"]["sha256"],row["before"]["bytes"])
   assert rel in tree and tree[rel]["type"]=="blob"and tree[rel]["mode"]in("100644","100755")
   assert data!=old,rel
   preimages.append(dict(relative_path=rel,bytes=len(old),sha256=H(old),data=old))
  names.append(rel);phase_names.append(rel)
 phase_summaries.append(dict(phase=phase,manifest=pins[str(path)],path_count=count,existing_count=sum(row["before"]is not None for row in rows),new_count=sum(row["before"]is None for row in rows),roles=dict(collections.Counter(row["role"]for row in rows)),targets=phase_names))
assert len(names)==len(set(names))==len({n.casefold()for n in names})==202
response=git("cat-file","--batch",input=("\n".join(head+":"+p["relative_path"]for p in preimages)+"\n").encode());offset=0
for p in preimages:
 end=response.index(b"\n",offset);header=response[offset:end].split();assert len(header)==3 and header[1]==b"blob"
 size=int(header[2]);start=end+1;data=response[start:start+size]
 assert data==p.pop("data")and response[start+size:start+size+1]==b"\n",p["relative_path"]
 p["exact_raw_git_basis"]=True;offset=start+size+1
assert offset==len(response)
attributes=git("check-attr","-z","filter","working-tree-encoding","ident","text","eol","--stdin",input=b"\0".join(n.encode()for n in names)+b"\0").split(b"\0")[:-1]
assert len(attributes)==len(names)*15
attrs={n:{}for n in names}
for i in range(0,len(attributes),3):
 path,key,value=(x.decode()for x in attributes[i:i+3]);attrs[path][key]=value
assert all(a["filter"]in("unspecified","unset")and a["working-tree-encoding"]in("unspecified","unset")and a["ident"]in("unspecified","unset")for a in attrs.values())
autocrlf=git("config","--get","core.autocrlf").decode().strip();assert autocrlf=="false"
assert git("config","--get","core.hooksPath",allowed=(1,))==b""
assert git("config","--get","core.fsmonitor",allowed=(1,))==b""
assert git("config","--get","commit.gpgsign",allowed=(1,))==b""
hooks_path=Path(git("rev-parse","--git-path","hooks").decode().strip())
if not hooks_path.is_absolute():hooks_path=main/hooks_path
active_hooks=[str(p)for p in hooks_path.iterdir()if p.is_file()and not p.name.endswith(".sample")]
assert not active_hooks
newlines=[]
for rel,b in contents.items():
 if b"\r"in b and attrs[rel]["text"]not in("unspecified","unset"):
  newlines.append(dict(path=rel,bytes=len(b),text=attrs[rel]["text"],eol=attrs[rel]["eol"]))
assert not newlines,("possible explicit text normalization",newlines)
assert "src/extensions/native_node_async_wrap.zig"not in names
protected=pin(main/"src/extensions/native_node_async_wrap.zig","972B9D098E93A138A8F6333CDAD829CAFE4D6E6855B2E1811B4623F57E39FCA2")
assert git("rev-parse","HEAD").decode().strip()==head and git("status","--porcelain=v1","--untracked-files=all")==b""
result=dict(schema=1,status="independently_checked_exact_v34_192_10_intake_manifests_and_executor_source",reviewed_utc=datetime.datetime.now(datetime.timezone.utc).isoformat(),candidate_head=head,executor=pins[str(executor)],phases=phase_summaries,total_distinct_targets=len(names),windows_canonical_aliases_absent=True,existing_reparse_targets_and_ancestors_absent=True,checked_existing_paths=len(parent_checks),raw_git_preimages=preimages,all_donors_rehashed=True,distinct_pinned_files=len(pins),pins=list(pins.values()),effective_autocrlf=autocrlf,active_hooks=active_hooks,external_filter_encoding_ident_attributes_absent=True,target_attribute_summary=dict(collections.Counter(json.dumps(a,sort_keys=True)for a in attrs.values())),possible_explicit_text_newline_conversion=[],fsmonitor_config_absent=True,commit_gpgsign_config_absent=True,protected_async_wrap_unchanged=True,phase_target_sets_disjoint=True,source_only=True,executor_executed=False,main_mutated=False,git_index_changed=False,commits_created=False,native_execution=False,source_mutation_hold_released=False,qualification=False)
proof.mkdir(parents=True,exist_ok=True);output=proof/"source-audit.json"
with output.open("xb")as f:f.write((json.dumps(result,indent=2)+"\n").encode())
print(json.dumps(dict(status=result["status"],path=str(output),bytes=output.stat().st_size,sha256=H(output.read_bytes()),distinct_pinned_files=len(pins),phases=[{k:p[k]for k in("phase","path_count","existing_count","new_count","roles")}for p in phase_summaries],total_targets=len(names),raw_git_preimages=len(preimages),source_only=True,executor_executed=False,main_mutated=False)))
