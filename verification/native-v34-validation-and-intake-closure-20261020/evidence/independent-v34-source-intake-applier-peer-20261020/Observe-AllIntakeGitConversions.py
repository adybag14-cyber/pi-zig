"""Observe Git clean conversion for every exact proposed intake target without writing the object store or index."""
from pathlib import Path
from concurrent.futures import ThreadPoolExecutor
import hashlib,json,subprocess,datetime
root=Path(r"C:\Users\adyba\pi-zig");main=root/"main";proof=root/"evidence/independent-v34-source-intake-applier-peer-20261020"
head="c764130caf2f2c7c63728bec0f6d1e16ac5c59a4"
H=lambda b:hashlib.sha256(b).hexdigest().upper()
def git(*args,input=None):
 p=subprocess.run(["git","--no-optional-locks",*args],cwd=main,input=input,capture_output=True,check=True);return p.stdout
assert git("rev-parse","HEAD").decode().strip()==head and git("status","--porcelain=v1","--untracked-files=all")==b""
specs=[("owner-error",root/"evidence/pending-file-handle-error-main-intake-20261020/manifest.json","A905E15D794738ADDED8DE272771545D72380B085750175804E82139B78869C4",192),("reqwrap",root/"evidence/pending-v34-reqwrap-fixture-main-intake-20261020/manifest.json","068136AC825829162A45AB03D9A1F60633EF8AF2D83061BAEC7CD7082FDE60E1",10)]
rows=[];manifests=[]
for phase,p,sha,count in specs:
 raw=p.read_bytes();assert H(raw)==sha;j=json.loads(raw)
 selected=j["rows"]+[dict(target=j.get("target_manifest",j.get("manifest_target")),source=str(p),bytes=len(raw),sha256=sha,before=None,role="exact_intake_manifest")]
 assert len(selected)==count
 rows.extend(dict(**r,phase=phase)for r in selected)
 manifests.append(dict(phase=phase,path=str(p),sha256=sha,bytes=len(raw),targets=count))
names=[r["target"]for r in rows];assert len(names)==len(set(names))==202
attr_tokens=git("check-attr","-z","filter","working-tree-encoding","ident","text","eol","--stdin",input=b"\0".join(n.encode()for n in names)+b"\0").split(b"\0")[:-1]
assert len(attr_tokens)==len(names)*15
attrs={n:{}for n in names}
for i in range(0,len(attr_tokens),3):
 name,key,value=(x.decode()for x in attr_tokens[i:i+3]);attrs[name][key]=value
assert all(x[k]in("unspecified","unset")for x in attrs.values()for k in("filter","working-tree-encoding","ident"))
def observe(row):
 raw=Path(row["source"]).read_bytes();assert len(raw)==row["bytes"]and H(raw)==row["sha256"]
 raw_oid=hashlib.sha1(b"blob "+str(len(raw)).encode()+b"\0"+raw).hexdigest()
 filtered_oid=git("hash-object","--path="+row["target"],"--stdin",input=raw).decode().strip()
 return dict(phase=row["phase"],target=row["target"],source=row["source"],bytes=len(raw),sha256=H(raw),crlf_count=raw.count(b"\r\n"),lone_cr_count=raw.count(b"\r")-raw.count(b"\r\n"),raw_git_blob=raw_oid,filtered_git_blob=filtered_oid,converts=raw_oid!=filtered_oid,attributes=attrs[row["target"]])
with ThreadPoolExecutor(max_workers=4)as workers:observed=list(workers.map(observe,rows))
assert git("rev-parse","HEAD").decode().strip()==head and git("status","--porcelain=v1","--untracked-files=all")==b""
conversions=[r for r in observed if r["converts"]]
result=dict(schema=1,status="observed_all_exact_intake_git_clean_conversions_read_only",observed_utc=datetime.datetime.now(datetime.timezone.utc).isoformat(),candidate_head=head,manifests=manifests,observed_target_count=len(observed),phase_counts={phase:sum(r["phase"]==phase for r in observed)for phase,_,_,_ in specs},conversion_counts={phase:sum(r["phase"]==phase for r in conversions)for phase,_,_,_ in specs},conversions=conversions,all_targets=observed,method="Each donor SHA256/length verified; raw Git blob SHA1 independently computed; actual git hash-object --path=<exact target> --stdin result compared without -w. External filter/encoding/ident attributes verified absent before invoking Git.",main_clean_and_unchanged=True,object_store_write_requested=False,index_mutated=False,applier_executed=False,qualification=False)
p=proof/"all-target-git-conversion-observation.json";assert not p.exists()
with p.open("xb")as f:f.write((json.dumps(result,indent=2)+"\n").encode())
print(json.dumps(dict(path=str(p),bytes=p.stat().st_size,sha256=H(p.read_bytes()),phase_counts=result["phase_counts"],conversion_counts=result["conversion_counts"],conversions=conversions,main_unchanged=True)))
