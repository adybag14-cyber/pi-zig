from pathlib import Path
import hashlib,json,re,subprocess
root=Path(r"C:\Users\adyba\pi-zig");main=root/"main"
p=root/"worktrees/sdk-owners-resume-20261018/verification/v37-file-handle-runtime-fixtures-sourceonly-20261021/proposal.json"
def sha(b):return hashlib.sha256(b).hexdigest().upper()
b=p.read_bytes();assert len(b)==21669 and sha(b)=="2933A7AB4CCC196984FC27419B3E4A64DCCEB99B0834734AA7B357EE1280C7FC";v=json.loads(b)
def rawpin(x):
 b=Path(x["path"]).read_bytes();assert len(b)==x["bytes"] and sha(b)==x["sha256"];return b
def git(*a):
 q=subprocess.run(["git",*a],cwd=main,capture_output=True);assert q.returncode==0,(a,q.stderr);return q.stdout
assert git("status","--porcelain=v1","--untracked-files=all")==b""
assert git("rev-parse","HEAD").strip().decode()==v["main_basis"]
checks=[]
for row in v["files"]:
 original=rawpin(row["original"]);current=rawpin(row["current"]);candidate=rawpin(row["candidate"])
 assert original==current==git("show",v["main_basis"]+":"+row["relative_path"])
 step=original
 for edit in row["edits"]:
  old=edit["old"].encode();new=edit["new"].encode();at=edit["offset"]
  assert sha(step)==edit["before_sha256"] and step[at:at+len(old)]==old
  step=step[:at]+new+step[at+len(old):]
  assert sha(step)==edit["after_sha256"]
 assert step==candidate
 for edit in reversed(row["edits"]):
  old=edit["old"].encode();new=edit["new"].encode();at=edit["offset"]
  assert sha(step)==edit["after_sha256"] and step[at:at+len(new)]==new
  step=step[:at]+old+step[at+len(new):]
  assert sha(step)==edit["before_sha256"]
 assert step==original
 names=lambda x:re.findall(rb'\btest\s+"((?:\\.|[^"\\])*)"',x)
 imports=lambda x:re.findall(rb'@(import|cInclude)\s*\(\s*"((?:\\.|[^"\\])*)"\s*\)',x)
 assert names(original)==names(candidate) and imports(original)==imports(candidate)
 checks.append({"path":row["relative_path"],"edits":len(row["edits"]),"names":len(names(candidate)),"imports":len(imports(candidate)),"full_forward_inverse_exact":True,"current_committed_preimage_exact":True})
cohort=[]
for group in v["cohort"]:
 original=rawpin(group["source"]);relative=str(Path(group["source"]["path"]).relative_to(main)).replace("\\","/")
 selected=next((rawpin(x["candidate"]) for x in v["files"] if x["relative_path"]==relative),original)
 names=re.findall(rb'\btest\s+"((?:\\.|[^"\\])*)"',selected);module=Path(relative).stem
 assert [module+".test."+n.decode() for n in names]==group["named"]
 assert [n.decode() for n in re.findall(rb'@import\s*\(\s*"((?:\\.|[^"\\])*)"\s*\)',selected)]==group["imports"]
 cohort.append({"name":group["name"],"declared":len(names),"current_imports_unchanged":True})
assert sum(g["declared"] for g in cohort)==58
rawpin(v["selected_catalog"])
print(json.dumps({"proposal_rehashed":True,"main_clean":True,"files":checks,"cohort":cohort,"native_execution":False}))
support=rawpin(v["files"][1]["candidate"]).decode().splitlines()
for start,end in [(70,135)]:
 print(json.dumps({"source":v["files"][1]["candidate"],"start":start,"lines":[str(i)+": "+support[i-1] for i in range(start,min(end,len(support))+1)]}))
