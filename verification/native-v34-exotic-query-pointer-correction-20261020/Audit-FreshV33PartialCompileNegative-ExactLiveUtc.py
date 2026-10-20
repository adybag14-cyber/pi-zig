"""Independent closure of original V33 partial compile negative; no metadata/runtime acceptance."""
from pathlib import Path
import collections,datetime,hashlib,json,struct,subprocess,os,sys
base=Path(r"C:\Users\adyba\pi-zig");main=base/"main"
proof=base/"evidence/root-native-foundation-fresh-v33-buildquery-20261020-193221"
control=base/"evidence/root-native-foundation-fresh-v33-control-20261020-193221"
prep=base/"evidence/combined-native-batch-v33-prepared-20261020"
head="f4c6abbc62ecd18b72ec50ab8fa206fe1664909f"
output=control/"independent-partial-compile-negative-closure.json"
def require(ok,message):
 if not ok:raise RuntimeError(message)

def utc_ticks(value):
 # Preserve the full seven-digit Windows timestamp, permitting only equivalent
 # ISO spelling/offsets. Python datetime alone truncates the seventh digit.
 import re
 m=re.fullmatch(r"(\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d)(?:\.(\d{1,7}))?(Z|[+-]\d\d:\d\d)",value)
 require(m is not None,"Explicit bounded ISO timestamp required")
 stamp=datetime.datetime.fromisoformat(m[1]+("+00:00" if m[3]=="Z" else m[3]))
 delta=stamp-datetime.datetime(1970,1,1,tzinfo=datetime.timezone.utc)
 return (delta.days*86400+delta.seconds)*10000000+int((m[2] or "").ljust(7,"0"))

def read(path):return json.loads(Path(path).read_text(encoding="utf-8-sig"))
def digest(path):
 h=hashlib.sha256()
 with Path(path).open("rb") as f:
  while block:=f.read(1024*1024):h.update(block)
 return h.hexdigest().upper()
def pin(path):return dict(path=str(path),bytes=Path(path).stat().st_size,sha256=digest(path))
cfg_path=control/"independent-partial-compile-negative-audit-inputs.json"
require(digest(cfg_path)=="1AA52BA0BC97B7479E239972BB3EA28253C40E1FAF750596B6C90D53BA3C6D83","Exact independently observed V33 negative inputs")
cfg=read(cfg_path)
require(cfg["candidate_head"]==head and cfg["source_mutation_hold_released"] is False and cfg["metadata_acceptance"] is False and cfg["qualification"] is False,"No source release or acceptance authority")
for name,key in (("before.json","before_sha256"),("final.json","final_sha256")):
 require(digest(proof/name)==cfg[key],"Exact complete original bookend "+name)
require(digest(control/"independent-observed-job-status.json")==cfg["job_observation_sha256"],"Exact original durable terminal observation")
for name,key in (("outer.json","outer_sha256"),("outer-absence.json","outer_absence_sha256")):
 require(digest(control/name)==cfg[key],"Exact original outer evidence "+name)
require(not output.exists(),"Fresh independent closure required")
r=read(proof/"result.json");before=read(proof/"before.json");final=read(proof/"final.json")
grant=read(control/"root-grant.json");matrix=read(prep/"groups.json")
require(digest(proof/"result.json")==cfg["result_sha256"],"Original complete BuildQuery result changed")
require(digest(control/"root-grant.json")=="1C6CE575AC744915FF5AD264947E5AF446C3DBFDE11D0F4C26E321575F6FAAF6","Original grant changed")
require(r["status"]=="failed" and r["mode"]==grant["mode"]=="BuildQuery" and r["candidate_head"]==grant["candidate_head"]==head,"Original exact complete BuildQuery identity")
require(grant["status"]=="root_reviewed_combined_native_batch_release" and grant["execution_authorized"] is True,"Original Root authority")
require(r["driver_sha256"]==grant["driver_sha256"]==digest(prep/"Run-CombinedNativeBatch.ps1")=="1DD3A9D27FA7B54F9383F325792A9E5259C66C32FA6C601F21216B4DBB483601","Unchanged strict controller")
require(r["group_manifest_sha256"]==grant["group_manifest_sha256"]==digest(prep/"groups.json")=="E3BB32B3922EE32712AE3D96558C40F13BFE875FAFC0D7FFA5958D65FA8719B8","Exact strict matrix")
for flag in ("postseal","controller_environment_restored","initial_cache_absence","qualification_requested","fresh_cache_reproduction"):
 require(r[flag] is True,"Required original complete Boolean "+flag)
for flag in ("cache_seeded","runtime_requested","product_qualified","all_groups_closed"):
 require(r[flag] is False,"No runtime or qualification claim")
require(r["cache_mode"]=="fresh_batch" and r["source_seal_scope"]=="whole_batch","Fresh source/cache scope")
require(r["absence"]["native_roots"]==[],"Original global native absence")
require([p["group"] for p in r["groups"]]==grant["groups"][:4]==["native-node-file-handle-read","native-node-fs-callback-template","native-vm-simple-stack-source","native-vm-exotic-operations"] and len(grant["groups"])==len(set(grant["groups"]))==63 and len(r["groups"])==4,"Exact first four attempted groups of sixty-three")
require({p.name for p in (proof/"groups").iterdir() if p.is_dir()}=={g["group"] for g in r["groups"]},"Exact four attempted group directories")
require(subprocess.check_output(["git","--no-optional-locks","rev-parse","HEAD"],cwd=main,text=True).strip()==head,"Main head changed")
require(subprocess.check_output(["git","--no-optional-locks","status","--porcelain"],cwd=main,text=True)=="","Main state changed")
all_pins={}
for seal in (before,final):
 require(seal["candidate_head"]==head and seal["clean"] is True and seal["errors"]==[],"Original complete source identity")
for role in ("source","tree","vendor","compiler","controls"):
 require(before[role]==final[role],"Original bookend mismatch: "+role)
 counts=collections.Counter(row["relative"] for row in final[role])
 require({k:v for k,v in counts.items() if v>1}==({r"C:\Program Files\PowerShell\7\pwsh.exe":2} if role=="controls" else {}),"Unexpected duplicate seal role")
 for row in final[role]:
  path=Path(row["path"]);require(path.is_relative_to(base) or str(path) in (r"C:\Program Files\PowerShell\7\pwsh.exe",r"C:\Program Files\PowerShell\7\pwsh.dll"),"Uncontained sealed path")
  require(str(path) not in all_pins or all_pins[str(path)]==row["sha256"],"Conflicting shared pin")
  all_pins[str(path)]=row["sha256"]
require(len(final["source"])==14078 and len(final["tree"])==14091 and len(final["vendor"])==1489 and len(final["compiler"])==19546 and len(final["controls"])==14,"Complete current source/compiler/control cardinality")
tracked=subprocess.check_output(["git","--no-optional-locks","ls-files","-z"],cwd=main).decode("utf-8").split("\0")[:-1]
require(set(tracked)=={row["relative"]for row in final["source"]},"Independent complete tracked source inventory")
for role,root,excludes in (("tree",main,{".git",".zig-cache","zig-out"}),("vendor",main/"vendor",set()),("compiler",base/"toolchain/zig-x86_64-windows-0.16.0",set())):
 current_paths=[]
 for directory,dirs,files in os.walk(root):
  if Path(directory)==root:dirs[:]=[name for name in dirs if name not in excludes]
  current_paths.extend(str(Path(directory)/name)for name in files if not(Path(directory)==root and name in excludes))
 require(set(current_paths)=={row["path"]for row in final[role]},"Independent current complete directory inventory: "+role)
for path,expected in all_pins.items():require(digest(path)==expected,"Current sealed input changed: "+path)
supplemental=[]
for key in ("preparation_review","combined_build_source_peer","prior_diagnostic_closure","source_intake","prior_compile_negative_closure","macro_correction_intake","backing_correction_intake","fixture_correction_intake","callback_correction_intake","uv_namespace_correction_intake","prior_v31_build_closure","prior_v31_strict_negative_closure","v32_progress","specific_root_configuration","prior_v32_compile_negative_closure","quickjs_correction_intake","quickjs_source_release","v33_progress"):
 row=grant[key];p=Path(row["path"]);require(p.is_relative_to(base) and digest(p)==row["sha256"] and p.stat().st_size==row["bytes"],"Root supplemental preparation pin "+key);supplemental.append(pin(p))
review=read(prep/"preparation-review.json")
for key in ("driver","matrix","auditor","classifier","combined_build_source_peer","metadata_auditor_adaptation"):
 row=review[key];require(digest(row["path"])==row["sha256"],"Exact reviewed preparation evidence "+key)
for key,row in review["provenance"].items():
 p=Path(row["path"]);require(p.is_relative_to(base) and digest(p)==row["sha256"] and p.stat().st_size==row["bytes"],"Exact reviewed preparation provenance "+key);supplemental.append(pin(p))
root_inputs=read(grant["specific_root_configuration"]["path"]);peer=root_inputs["independent_catalog_peer"]
require(digest(peer["path"])==peer["sha256"]=="ECC1F30A8DC13831883031A281563676A1EEB8351F96BF73CD9D8B3EBB3B4E22","Exact independently reviewed emitted catalog")
supplemental.append(pin(peer["path"]))
require(review["candidate_head"]==head and review["selected_groups"]==63 and review["selected_declarations"]==1249 and review["actual_metadata_count"] is None and review["selected_group_names"]==grant["groups"],"Preserved declaration/actual count separation and complete selected order")
queued=read(base/"evidence/fresh-v33-queued-launch-receipt-20261020.json")
require(queued["prepared"]["candidate_head"]==head and queued["prepared"]["grant"]["sha256"]==digest(control/"root-grant.json"),"Exact queued specific Root authority")
for key in ("grant_preparation","queue_wrapper","root_inputs"):
 row=queued[key];require(digest(row["path"])==row["sha256"],"Original queued source changed "+key);supplemental.append(pin(row["path"]))
pids=[];bounds=[];groups=[];receipt_pins=[];aggregate_owners=[];admission_probes=[];completed_artifacts=[]
def owner_identity(owner,step,executable,expected_hash,args,root):
 require((owner["status"]=="passed" and owner["exit_code"]==0) or (step=="compile" and owner["status"]=="failed" and owner["exit_code"]==1 and owner.get("error")=="Owned terminal failed: "+str(executable)),"Actual original terminal owner required")
 require(owner["timeout_seconds"]==(1320 if step=="compile" else 30) and owner["retained_handle"]>0,"Actual bounded retained owner required")
 require(owner["executable"]==str(executable) and owner["executable_sha256"]==expected_hash and owner["arguments"]==args and owner["working_directory"]==str(root),"Actual exact executable/argv/root binding")
 live=owner["live_identity"]
 require(live["pid"]==owner["pid"] and utc_ticks(live["created_utc"])==utc_ticks(owner["created_utc"]) and live["executable"]==owner["executable"] and live["command_line"] and owner["completed_utc"],"Actual live creation identity")
 pids.append(owner["pid"])
 bounds.append(dict(pid=owner["pid"],created=utc_ticks(owner["created_utc"]),completed=utc_ticks(owner["completed_utc"]),role=step))

for part in r["groups"]:
 name=part["group"];group=next(g for g in matrix["groups"] if g["name"]==name);gp=proof/"groups"/name
 require(part["candidate_head"]==head and part["postseal"] is True and part["source_seal_scope"]=="whole_batch","Group source binding")
 require(part["status"]==("partial_batch_not_admissible" if name in grant["groups"][:3] else "failed"),"Original partial/negative statuses retained")
 require(part["owned_started_phases"]==part["attempted_phases"]==list(part["phases"])==(["compile","metadata"] if name in grant["groups"][:3] else ["compile"]),"Exact observed phase sequence")
 require(part["native_selected_tests_started"] is None,"No native test was started")
 require(part["receipt_directory"]==str(gp) and part["output_prefix"]==str(gp/"installed") and part["mode"]=="BuildQuery","Exact per-group original roots and mode")
 require(read(gp/"result.json")==part,"Exact per-group final result is the aggregate group")
 for flag in ("runtime_requested","runtime_owner_launch_attempted","actual_runtime_owner_started"):require(part[flag] is False,"No runtime started")
 for row in group["source_pins"]:require(digest(main/row["path"])==row["sha256"],"Exact test/control source binding")
 summary=dict(group=name,status=part["status"],actual_metadata_count=None,compiler_errors=[])
 exe=None;exe_hash=None
 if part["status"]=="partial_batch_not_admissible":
  artifact=read(gp/"build-artifacts.json");metadata=read(gp/"selected-tests.json")
  require(artifact["errors"]==[] and len(artifact["installed"])==2,"Actual installed artifacts")
  for row in artifact["installed"]:require(digest(row["path"])==row["sha256"],"Installed artifact changed")
  installed=next(row for row in artifact["installed"] if row["path"].endswith(".exe"));exe_hash=installed["sha256"]
  cached=[row for row in artifact["cached_executables"] if row["sha256"]==exe_hash];require(len(cached)==1,"Unique actual cached executable")
  cached=cached[0];exe=Path(cached["path"]);require(exe.is_relative_to(proof/"cache"),"Actual cached executable root")
  require(digest(exe)==exe_hash and digest(cached["pdb_path"])==cached["pdb_sha256"],"Cached executable/PDB changed")
  require(part["cached_executable"]==str(exe) and installed["path"]==part["installed_executable"] and set(row["path"] for row in artifact["installed"])=={part["installed_executable"],part["installed_pdb"]},"Exact cached and installed aggregate artifact identities")
  require(exe.name=="test.exe" and Path(cached["pdb_path"])==exe.with_suffix(".pdb"),"Original adjacent cached test executable/PDB pair")
  pdb=next(row for row in artifact["installed"] if row["path"]==part["installed_pdb"])
  require(pdb["sha256"]==cached["pdb_sha256"],"Installed and original cached PDB equality")
  require({str(p)for p in (gp/"installed").rglob("*")if p.is_file()}=={row["path"]for row in artifact["installed"]},"Exact complete current installed artifact directory")
  for row in artifact["installed"]:require(Path(row["path"]).stat().st_size==row["bytes"],"Original installed artifact lengths")
  completed_artifacts.append(cached)
  require(artifact["cached_executables"]==sorted(completed_artifacts,key=lambda row:row["path"]),"Original serial accumulated cache inventory")
  for journal in ("compile-after-artifacts.json","metadata-before-artifacts.json","metadata-after-artifacts.json"):
   require(read(gp/journal)==artifact,"Complete original artifact journal unchanged between compile and metadata")
   receipt_pins.append(pin(gp/journal))
  pe=artifact["pe"]
  require(pe["reserved_stack_bytes"]==16777216 and pe["committed_stack_bytes"]==4096 and pe["Engine_guard_bytes"]==1048576 and pe["dynamic_stack_measured"] is False,"Original static stack/guard declaration; no dynamic measurement")
  with exe.open("rb") as f:
   dos=f.read(64);require(len(dos)==64 and dos[:2]==b"MZ","Actual executable DOS header")
   pe_offset=struct.unpack_from("<I",dos,60)[0];require(64<=pe_offset<=1024*1024,"Bounded actual PE header")
   f.seek(pe_offset);header=f.read(112)
  require(len(header)==112 and header[:4]==b"PE\0\0" and struct.unpack_from("<H",header,24)[0]==0x20b,"Actual PE32+ image")
  require(struct.unpack_from("<QQ",header,96)==(pe["reserved_stack_bytes"],pe["committed_stack_bytes"]),"Actual PE header stack reservation/commit")
  require(metadata["group"]==name and metadata["version"]=="0.16.0" and metadata["method"]=="Actual query4/exit0 only; no run_test; CI607 owner30","Original metadata-only query protocol")
  receipt_pins.extend([pin(gp/"build-artifacts.json"),pin(gp/"selected-tests.json")])
  require(metadata["binary"]==str(exe) and metadata["binary_sha256"]==exe_hash and metadata["candidate_head"]==head and metadata["runtime_started"] is False,"Actual metadata binding")
  raw=(gp/"metadata.stdout.bin").read_bytes();require((gp/"metadata.stderr.log").read_bytes()==b"","Unexpected metadata stderr")
  offset=0;tags=[];names=None
  while offset<len(raw):
   require(len(raw)-offset>=8,"Truncated raw metadata");tag,size=struct.unpack_from("<II",raw,offset);offset+=8
   require(size<=1024*1024 and size<=len(raw)-offset,"Invalid raw frame bounds")
   data=raw[offset:offset+size];offset+=size;tags.append(tag)
   if tag==0:require(tags==[0] and data==b"0.16.0","Actual pinned compiler version")
   elif tag==3:
    require(tags==[0,3] and len(data)>=8 and names is None,"One actual metadata frame")
    string_bytes,count=struct.unpack_from("<II",data);require(1<=count<=64 and len(data)==8+8*count+string_bytes,"Bounded actual test list")
    table=data[8+8*count:];names=[]
    for i in range(count):
     pos=struct.unpack_from("<I",data,8+4*i)[0];panic=struct.unpack_from("<I",data,8+4*count+4*i)[0]
     require(panic==0 and pos<string_bytes,"Valid test name/panic metadata");end=table.find(b"\0",pos);require(end>=pos,"Terminated test name")
     names.append(table[pos:end].decode("utf-8","strict"))
   else:raise RuntimeError("Runtime/nonmetadata frame appeared")
  require(tags==[0,3] and names and len(names)==len(set(names)) and names==metadata["tests"] and len(names)==metadata["actual_count"],"Independent raw ordered list")
  require(all(names.count(n)==1 for n in group["required_named"]) and all(n in group["required_named"] or n in group["allowed_anonymous"] for n in names),"Preserved actual named controls")
  if group.get("historical_order") is not None:require(names==group["historical_order"],"Original historical order changed")
  summary["actual_metadata_count"]=len(names);summary["actual_tests"]=names
 for phase_name in part["owned_started_phases"]:
  phase=part["phases"][phase_name];e=phase["evidence"];owner=read(gp/(phase_name+".json"))
  require(e["valid"] is True and e["evidence_errors"]==[] and e["current_owner_pid_present"]==0 and e["current_owned_descendants"]==[] and e["absence_error"] is None,"Actual phase evidence/absence")
  require(phase["postchecks"]["source_sealed"] is True and phase["postchecks"]["absence_closed"] is True,"Original complete phase source/absence")
  require(e["owner"]["pid"]==owner["pid"] and utc_ticks(e["owner"]["created_utc"])==utc_ticks(owner["created_utc"]) and utc_ticks(e["owner"]["completed_utc"])==utc_ticks(owner["completed_utc"]),"Aggregate original creation and terminal identity")
  require(set(e["owner"])==set(owner),"Exact aggregate original owner field inventory")
  for key in owner:
   if key not in ("created_utc","completed_utc","live_identity"):require(e["owner"][key]==owner[key],"Exact aggregate original owner field "+key)
  aggregate_live=e["owner"]["live_identity"];standalone_live=owner["live_identity"]
  require(set(aggregate_live)==set(standalone_live),"Exact nested live identity field inventory")
  for key in standalone_live:
   if key=="created_utc":require(utc_ticks(aggregate_live[key])==utc_ticks(standalone_live[key]),"Exact nested live creation UTC100ns identity")
   else:require(aggregate_live[key]==standalone_live[key],"Exact nested live identity field "+key)
  absence=read(gp/(phase_name+"-absence.json"))
  require(absence["phase"]==phase_name and absence["status"]=="closed" and absence["evidence"]==e and absence["global_native"]==[],"Original phase absence evidence is the aggregate evidence")
  aggregate_owners.append(dict(group=name,phase=phase_name,evidence=e))
  require(e["canonical_results"] is None,"No runtime result protocol")
  ignored=e.get("preexisting_pid_ancestry")
  require(isinstance(ignored,list),"Explicit original process-instance ancestry evidence")
  for item in ignored:
   observed=item["observed_process"]
   require(item["reason"]=="Child creation predates this parent instance" and item["parent_pid"]==owner["pid"] and observed["ParentProcessId"]==owner["pid"],"Excluded ancestry must name the actual original parent")
   require(item["parent_created_utc_ticks"]==utc_ticks(owner["created_utc"])+621355968000000000 and item["child_created_utc_ticks"]==utc_ticks(observed["CreationDate"])+621355968000000000,"Independent exact UTC100ns ancestry conversion")
   require(utc_ticks(observed["CreationDate"])<utc_ticks(owner["created_utc"])-10,"Only proven preexisting child instances may be excluded")
  if phase_name=="compile":
   args=["build",group["target"],"-Doptimize=Debug","-Duse-llvm=true","-Ddiagnostic-tests=false","-j1","--test-timeout","120s","--prefix",str(gp/"installed"),"--cache-dir",str(proof/"cache"),"--global-cache-dir",str(proof/"global-cache"),"--summary","all"]
   owner_identity(owner,"compile",base/"toolchain/zig-x86_64-windows-0.16.0/zig.exe","086CE9D47BA42F33A514E1A6E04EB1D4A8FA1D75E0868E0213CAAD447C91E864",args,main)
  else:owner_identity(owner,"metadata",exe,exe_hash,["--listen=-"],main)
  admission=read(gp/(phase_name+"-admission.json"));probe=admission["probe"]
  require(admission["status"]=="admitted" and probe["phase"]==phase_name and probe["free_kib"]>=16777216 and probe["minimum_kib"]==16777216 and probe["native"]==[] and probe["native_roots"]==0 and 0<=utc_ticks(owner["created_utc"])-utc_ticks(probe["utc"])<10*10000000,"Fresh serial sixteen GiB native admission")
  admission_probes.append(probe)
  receipt_pins.append(pin(gp/(phase_name+"-admission.json")))
  require(owner["live_identity"]["command_line"]=='"'+owner["executable"]+'" '+' '.join(owner["arguments"]),"Exact original live command")
  if owner["exit_code"]==0:
   require(phase["owner_binding"]["status"]=="passed" and phase["owner_binding"]["errors"]==[] and phase["failure"] is None and phase["postchecks"]["errors"]==[],"Positive phase cannot hide a failure")
   require(phase["original_execution_failure"] is None and part["errors"]==[] and all(phase["postchecks"][k] is True for k in ("evidence_valid","owner_bound","source_sealed","artifacts_bound","absence_closed")),"Every original positive phase gate remains positive")
  else:
   require(phase_name=="compile" and phase["failure"]==phase["original_execution_failure"]==owner["error"] and phase["owner_binding"]["status"]=="invalid" and phase["owner_binding"]["errors"]==["Exact actual terminal0 owner/deadline required on positive and negative protocol paths"],"Preserved exact compile-negative gate")
   strict_error="Actual terminal owner binding failed: Exact actual terminal0 owner/deadline required on positive and negative protocol paths"
   require(phase["postchecks"]["evidence_valid"] is True and phase["postchecks"]["owner_bound"] is False and phase["postchecks"]["artifacts_bound"] is False and phase["postchecks"]["errors"]==[strict_error] and part["errors"]==[strict_error,owner["error"]],"Preserve every actual strict negative and false qualification gate")
   summary["compiler_errors"]=[line for line in (gp/"compile.stderr.log").read_text(encoding="utf-8").splitlines() if "error:" in line][:20]
  for row in e["raw_outputs"]:
   path=Path(row["path"]);require(path.is_relative_to(gp) and path.stat().st_size==row["bytes"] and digest(path)==row["sha256"],"Original raw phase bytes changed")
  receipt_pins.extend([pin(gp/(phase_name+".json")),pin(gp/(phase_name+"-absence.json"))])
 groups.append(summary)
require(len(pids)==len(r["absence"]["owners"])==7 and len({(v["pid"],v["created"])for v in bounds})==7 and pids==[54760,33068,60900,67932,3776,66236,63812],"All seven actual native process instances reconciled")
require(r["absence"]["owners"]==aggregate_owners and r["admission_probes"]==admission_probes,"Exact complete original owner and admission inventories")
all_cached=sorted(completed_artifacts,key=lambda row:row["path"])
require(len(all_cached)==3 and len({row["path"] for row in all_cached})==3,"Three distinct actual cached artifacts")
require({str(p)for p in (proof/"cache").rglob("test.exe")}=={row["path"]for row in all_cached},"Complete current cached test executable inventory")
require({str(p)for p in (proof/"cache").rglob("test.pdb")}=={row["pdb_path"]for row in all_cached},"Complete current cached test PDB inventory")
for part in r["groups"]:
 gp=proof/"groups"/part["group"]
 if part["status"]=="partial_batch_not_admissible":
  artifact=read(gp/"build-artifacts.json")
  require(read(gp/"final-artifacts.json")==dict(installed=artifact["installed"],cached_executables=all_cached,pe=artifact["pe"],errors=[]),"Complete final installed/cache artifact journal")
  receipt_pins.append(pin(gp/"final-artifacts.json"))
 else:
  require(part["cached_executable"] is None and not Path(part["installed_executable"]).exists() and not Path(part["installed_pdb"]).exists(),"Failed group has no selected or installed executable/PDB")
  require(not any(p.is_file()for p in (gp/"installed").rglob("*")),"Failed group installed directory has no files")
  require(read(gp/"compile-after-artifacts.json")==dict(installed=[],cached_executables=all_cached,pe=None,errors=[]),"Failed compile retains exactly three preceding cache artifacts")
  for name in ("metadata.json","metadata.stdout.bin","metadata.stderr.log","selected-tests.json","build-artifacts.json","final-artifacts.json"):
   require(not (gp/name).exists(),"No failed-group metadata or accepted artifact receipt")
  receipt_pins.append(pin(gp/"compile-after-artifacts.json"))
 receipt_pins.append(pin(gp/"result.json"))
outer=read(control/"outer.json");oa=read(control/"outer-absence.json")
require(outer["pid"]==69304 and outer["status"]=="failed" and outer["exit_code"]==1 and outer["timeout_seconds"]==1800 and outer["retained_handle"]>0,"Bounded original outer negative")
require(outer["arguments"]==["-NoLogo","-NoProfile","-NonInteractive","-File",str(prep/"Run-CombinedNativeBatch.ps1"),"-RootGrant",str(control/"root-grant.json"),"-Mode","BuildQuery"],"Exact outer argv")
require(outer["executable_sha256"]=="FA2C8BB1E35CDD62AD15CD06A1D8F2C5961E9725A9BFA1E7CFD2C322F49E9619" and outer["working_directory"]==str(base),"Exact outer executable/root")
require(outer["executable"]==r"C:\Program Files\PowerShell\7\pwsh.exe","Actual outer executable path")
outer_live=outer["live_identity"]
require(outer_live["pid"]==outer["pid"] and utc_ticks(outer_live["created_utc"])==utc_ticks(outer["created_utc"]) and outer_live["executable"]==outer["executable"],"Actual outer retained/live identity")
require(outer_live["command_line"]=='"'+outer["executable"]+'" '+' '.join(outer["arguments"]),"Actual original outer command binding")
require(utc_ticks(outer["completed_utc"])>=utc_ticks(outer["created_utc"]) and outer.get("error")=="Owned terminal failed: "+outer["executable"],"Actual original outer terminal failure")
require(oa["pid"]==outer["pid"] and utc_ticks(oa["created_utc"])==utc_ticks(outer["created_utc"]) and oa["currently_absent"] is True and oa["current_records"]==[],"Original independent outer absence")
job=read(control/"independent-observed-job-status.json")["data"]
require(job["id"]=="job-op-fed7b95930edb8138ca300a2b086a362a325d9bde6059567fc6631530894919c" and job["status"]=="failed" and job["exitCode"]==1 and job["runnerAlive"] is False and job["runnerPid"]==55140 and job["childPid"]==33936 and job["runnerProcessInstance"]=="134369983404637034" and job["createdAtUtc"]=="2026-10-20T19:32:20.444Z" and job["completedAtUtc"]==cfg["job_completed_utc"],"Independent job terminal observation")
bounds.append(dict(pid=outer["pid"],created=utc_ticks(outer["created_utc"]),completed=utc_ticks(outer["completed_utc"]),role="outer"))
bounds.append(dict(pid=55140,created=int(job["runnerProcessInstance"])-116444736000000000,completed=utc_ticks(job["completedAtUtc"]),role="runner"))
bounds.append(dict(pid=33936,created=utc_ticks(job["createdAtUtc"]),completed=utc_ticks(job["completedAtUtc"]),role="launcher_job_lifetime_envelope"))
pids=[v["pid"] for v in bounds]
require(digest(prep/"Get-ModelsNativeCandidates.ps1")=="3413A2A50B4D4C3BFF8709E4EE08C76BE449AAB1EDCB1E0C5C167DC7A804E301","Exact independent classifier")
query=r"$ErrorActionPreference='Stop';. 'C:\Users\adyba\pi-zig\evidence\combined-native-batch-v33-prepared-20261020\Get-ModelsNativeCandidates.ps1';$taskRows=@(Get-CimInstance Win32_Process -OperationTimeoutSec 5 -ErrorAction Stop);$taskPids=@("+",".join(map(str,pids))+r");$taskLive=@($taskRows|Where-Object {$_.ProcessId -in $taskPids}|Select-Object ProcessId,ParentProcessId,ExecutablePath,CommandLine,CreationDate);$taskDirect=@($taskRows|Where-Object {$_.ParentProcessId -in $taskPids}|Select-Object ProcessId,ParentProcessId,ExecutablePath,CommandLine,CreationDate);$taskNative=@(Get-ModelsNativeCandidates -Rows $taskRows -Container 'C:\Users\adyba\pi-zig');ConvertTo-Json -InputObject ([ordered]@{owners=$taskLive;direct_children=$taskDirect;native=$taskNative;observed_utc=[DateTimeOffset]::UtcNow.ToString('o')}) -Depth 8 -Compress"
current=json.loads(subprocess.check_output([r"C:\Program Files\PowerShell\7\pwsh.exe","-NoLogo","-NoProfile","-NonInteractive","-Command",query],text=True,timeout=15))
require(current["native"]==[],"Current global native absence")
reconciled=[]
for row in current["owners"]:
 candidates=[v for v in bounds if v["pid"]==row["ProcessId"]];born=utc_ticks(row["CreationDate"])
 require(candidates and all(born>v["completed"] for v in candidates),"Exclude only proved later PID reuse")
 reconciled.append(dict(kind="later_process_reusing_retired_pid",current_record=row,prior_terminal_intervals=candidates))
for row in current["direct_children"]:
 candidates=[v for v in bounds if v["pid"]==row["ParentProcessId"]];born=utc_ticks(row["CreationDate"])
 require(candidates and all(born<v["created"]-10 or born>v["completed"] for v in candidates),"No apparent descendant born in actual owned interval")
 reconciled.append(dict(kind="creation_time_excludes_prior_parent_instance",current_record=row,prior_terminal_intervals=candidates))
require([g["actual_metadata_count"] for g in groups]==[15,12,34,None] and sum(g["actual_metadata_count"] or 0 for g in groups)==61,"Only actual partial metadata 61; no fourth-group metadata")
require(cfg["granted_groups"]==63 and cfg["attempted_groups"]==4 and cfg["partial_actual_metadata"]==61 and cfg["actual_full_metadata_count"] is None and cfg["actual_tests_started"]==0 and cfg["native_phase_count"]==7,"Exact outcome counts never imply complete batch metadata or runtime")
require(any("native_vm_exotic_operations_test.zig:99:26: error: expected type '*c_int', found '*allowzero c_int'" in x for x in groups[3]["compiler_errors"]),"Exact retained exotic query callback pointer-type compiler diagnostic")
require(r["errors"]==["Owned terminal failed: "+str(base/"toolchain/zig-x86_64-windows-0.16.0/zig.exe")],"Original strict native failure retained")
for name in ("runtime.json","runtime.stdout.bin","runtime.stderr.log"):
 require(not any((proof/"groups"/p["group"]/name).exists()for p in r["groups"]),"No runtime artifacts")
gp=proof/"groups/native-vm-exotic-operations"
require(digest(gp/"compile.stderr.log")==cfg["compile_stderr_sha256"] and (gp/"compile.stderr.log").stat().st_size==19982,"Exact original exotic callback compiler stderr")
require(digest(gp/"compile.stdout.bin")==cfg["compile_stdout_sha256"] and (gp/"compile.stdout.bin").stat().st_size==0,"Exact original empty compiler stdout")
receipt_pins.extend([pin(gp/"compile.stderr.log"),pin(gp/"compile.stdout.bin"),pin(cfg_path),pin(control/"independent-observed-job-status.json")])
certificate=dict(schema=1,status="independently_closed_partial_compile_negative",candidate_head=head,reviewed_utc=datetime.datetime.now(datetime.timezone.utc).isoformat(),reviewer="Root independent complete inventories/current hashes/original raw metadata and original UTC100ns native process closure",source_seal_scope="whole_batch",whole_bookends_unchanged=True,current_all_sealed_inputs_rehashed=True,current_complete_directory_inventories_verified=True,distinct_current_files_rehashed=len(all_pins),seal_counts={k:len(final[k])for k in ("source","tree","vendor","compiler","controls")},granted_groups=63,attempted_groups=4,unstarted_groups=59,actual_partial_metadata_count=61,actual_full_metadata_count=None,actual_tests_started=0,native_owner_count=7,groups=groups,actual_process_intervals=bounds,current_absence=current,current_actual_process_instances_absent=True,current_process_instance_reconciliations=reconciled,original_receipts=[pin(proof/"result.json"),pin(proof/"before.json"),pin(proof/"final.json"),pin(control/"outer.json"),pin(control/"outer-absence.json"),*receipt_pins],supplemental_current_preparation_pins=supplemental,original_negative_rejections_preserved=True,controller_environment_restored=True,runtime_started=False,metadata_acceptance=False,qualification=False,source_mutation_hold_released=False)
output.write_text(json.dumps(certificate,indent=2)+"\n",encoding="utf-8")
print(json.dumps(dict(status=certificate["status"],closure=str(output),sha256=digest(output),native_owners=7,distinct_current_files_rehashed=len(all_pins),partial_metadata_count=61,attempted_groups=4,unstarted_groups=59,current_owner_absence=True,source_mutation_hold_released=False,qualification=False)))
