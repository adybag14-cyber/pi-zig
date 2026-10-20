"""Independent closure of exact V34 partial diagnostic runtime with preserved native assertion abort and all strict negatives; original qualification gates remain negative."""
from pathlib import Path
import collections,datetime,hashlib,json,struct,subprocess,os
base=Path(r"C:\Users\adyba\pi-zig");main=base/"main"
control=base/"evidence/root-native-foundation-v34-diagnostic-runtime-control-20261020-211629"
proof=base/"evidence/root-native-foundation-v34-diagnostic-runtime-20261020-211629"
build=base/"evidence/root-native-foundation-fresh-v34-buildquery-20261020-202924"
build_control=base/"evidence/root-native-foundation-fresh-v34-control-20261020-202924"
prep=base/"evidence/combined-native-runtime-diagnostic-v34-prepared-20261020"
head="c764130caf2f2c7c63728bec0f6d1e16ac5c59a4"
output=control/"independent-partial-diagnostic-runtime-closure.json"
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

def normalized_owner(row):
 # Only declared ISO timestamps may change spelling in PowerShell JSON.
 # Preserve every other original field and compare exact100ns UTC instants.
 result=dict(row)
 for key in ("created_utc","completed_utc"):result[key]=utc_ticks(row[key])
 result["live_identity"]=dict(row["live_identity"])
 result["live_identity"]["created_utc"]=utc_ticks(row["live_identity"]["created_utc"])
 return result

require(not output.exists(),"Fresh immutable independent closure required")
cfg_path=control/"independent-diagnostic-runtime-audit-inputs.json";cfg=read(cfg_path)
require(digest(cfg_path)=="7A913995E512F587262BB1A64D82438EC27CB72C706D578741E10004AB55F301","Exact independently captured original V34 partial diagnostic inputs")
require(cfg["control"]==str(control) and cfg["proof"]==str(proof) and cfg["source_mutation_hold_released"] is False and cfg["qualification"] is False,"Exact current nonqualifying diagnostic scope")
require(digest(control/"launch.ps1")==cfg["launch_sha256"]=="FE66BA4B5C8434CAD46FA30ADE9250991D86B3413FB6C082D1D6264E51D3111F","Original exact separate diagnostic outer launch")
r=read(proof/"result.json");before=read(proof/"before.json");final=read(proof/"final.json")
grant=read(control/"root-grant.json");matrix=read(prep/"groups.json")
accept_path=build_control/"independent-metadata-acceptance.json";accept=read(accept_path)
require(digest(accept_path)=="80BCC5A73602A01AFFB9D66B3D1531D730D4B0FD79EFDC73CADAA7D246729D45" and accept["accepted"] is True and accept["candidate_head"]==head and accept["runtime_started"] is False,"Original independent raw metadata acceptance")
require(digest(build_control/"independent-current-seals-and-owners.json")=="28AB425BC5C149E1642C0839CC6FBD590C0F98BD2DB5D844CE4C79BB5748BFF3","Original independent BuildQuery closure")
require(digest(proof/"result.json")=="4ABC6968DFF09B0075791279076C8F8F4891A80B7E5448BD1E83BA681A7E961D","Original exact terminal negative")
require(digest(control/"root-grant.json")=="B9A91A955663A8489ADF9DF99DCB723874863063351ED62D2F2420016A5ECD8F","Original separate runtime grant")
require(r["status"]=="failed" and r["mode"]==grant["mode"]=="DiagnosticRuntimeOnly" and r["candidate_head"]==grant["candidate_head"]==head,"Original actual runtime identity")
require(grant["status"]=="root_reviewed_closed_artifact_runtime_diagnostic" and grant["execution_authorized"] is True and grant["actual_metadata_count"]==1285,"Original exact Root runtime authority")
require(r["driver_sha256"]==grant["driver_sha256"]==digest(prep/"Run-CombinedNativeBatch.ps1")=="9BE0956AD35C6DF1BA88BCA6CC030D2D96F3560585D8B0EF0670EB43565431C1","Exact diagnostic runtime controller, strict owner/protocol failures preserved")
require(r["group_manifest_sha256"]==grant["group_manifest_sha256"]==digest(prep/"groups.json")=="6781CFD769B70925293C6C7B0D7AEECFC0DB87A8790FB5D61379A20A78C6443F","Exact runtime matrix")
for flag in ("postseal","controller_environment_restored","runtime_diagnostic","runtime_requested"):require(r[flag] is True,"Original complete runtime closure flag "+flag)
for flag in ("cache_seeded","product_qualified","all_groups_closed","fresh_cache_reproduction","initial_cache_absence","qualification_requested","diagnostic_closed"):require(r[flag] is False,"Original runtime scope flag "+flag)
require(r["cache_mode"]=="fresh_batch" and r["source_seal_scope"]=="whole_batch" and r["absence"]["native_roots"]==[],"Original runtime cache/source/absence")
require(grant["groups"]==[g["group"]for g in accept["groups"]] and len(grant["groups"])==63 and sum(g["actual_count"]for g in accept["groups"])==1285,"Complete accepted cohort retained")
require([g["group"]for g in r["groups"]]==grant["groups"][:17] and len(r["absence"]["owners"])==17,"Only original first seventeen native runtimes started")
require({p.name for p in (proof/"groups").iterdir()if p.is_dir()}==set(grant["groups"][:17]),"Other forty-six runtime group owners never started")
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
require(len(final["source"])==14088 and len(final["tree"])==14101 and len(final["vendor"])==1489 and len(final["compiler"])==19546 and len(final["controls"])==144,"Complete current source/compiler/control cardinality")
tracked=subprocess.check_output(["git","--no-optional-locks","ls-files","-z"],cwd=main).decode("utf-8").split("\0")[:-1]
require(set(tracked)=={row["relative"]for row in final["source"]},"Independent complete tracked source inventory")
for role,root,excludes in (("tree",main,{".git",".zig-cache","zig-out"}),("vendor",main/"vendor",set()),("compiler",base/"toolchain/zig-x86_64-windows-0.16.0",set())):
 current_paths=[]
 for directory,dirs,files in os.walk(root):
  if Path(directory)==root:dirs[:]=[name for name in dirs if name not in excludes]
  current_paths.extend(str(Path(directory)/name)for name in files if not(Path(directory)==root and name in excludes))
 require(set(current_paths)=={row["path"]for row in final[role]},"Independent current complete directory inventory: "+role)
for path,expected in all_pins.items():require(digest(path)==expected,"Current sealed input changed: "+path)

require(digest(build/"result.json")==grant["build_result_sha256"]==accept["build_result_sha256"]=="21069292FA7D9B724A81EAFAF8F8D16D9BDB3FA8F42A5B579B23D42AF1BB572A","Original accepted BuildQuery result")
require(digest(build/"final.json")==grant["build_source_seal_sha256"]==accept["build_source_seal_sha256"]=="DBBA4C36736487C477B95EC8745AAF1BFBEDBB7B47C74FAC275B09A7589D193B","Original accepted BuildQuery source seal")
build_final=read(build/"final.json")
for role in ("source","tree","vendor","compiler"):require(build_final[role]==final[role],"Exact accepted build inputs changed: "+role)
for accepted in accept["groups"]:
 gp=build/"groups"/accepted["group"]
 require(digest(gp/"build-artifacts.json")==accepted["build_artifacts_sha256"] and digest(gp/"selected-tests.json")==accepted["build_metadata_sha256"] and digest(gp/"metadata.stdout.bin")==accepted["independent_wire_sha256"],"Original accepted metadata/artifact/raw-wire changed")
 for path,sha in ((Path(accepted["cached_executable_path"]),accepted["executable_sha256"]),(Path(accepted["cached_executable_path"]).with_suffix(".pdb"),accepted["pdb_sha256"])):
  require(path.is_relative_to(build/"cache") and digest(path)==sha,"Exact originally compiled cached artifact changed")
 for row in read(gp/"build-artifacts.json")["installed"]:require(digest(row["path"])==row["sha256"],"Original installed artifact changed")
require(digest(proof/"final.json")=="119AE157A7BF3B81A0D08C0B58DCF17B680E3C178BA185F058201344CDF8242B","Exact original final source seal")
require(grant["qualification_requested"] is False and grant["runtime_restoration_claim"] is False and grant["source_build_driver_sha256"]==accept["driver_sha256"]=="1DD3A9D27FA7B54F9383F325792A9E5259C66C32FA6C601F21216B4DBB483601" and grant["diagnostic_groups"]==grant["groups"] and grant["runtime_diagnostic_scope"]=="complete_accepted_build_cohort","Original full diagnostic grant with no qualification")
require(r["errors"]==cfg["original_batch_errors"] and r["errors"][-1]=="Diagnostic cannot continue an incomplete or unclosed runtime failure","All original strict and diagnostic batch errors preserved")
strict_control=base/"evidence/root-native-foundation-v34-runtime-control-20261020-210255"
strict_proof=base/"evidence/root-native-foundation-v34-runtime-20261020-210255"
require(grant["strict_runtime_negative_closure_path"]==str(strict_control/"independent-negative-runtime-closure.json") and digest(strict_control/"independent-negative-runtime-closure.json")==grant["strict_runtime_negative_closure_sha256"]=="038180C2284FB568EEB9368F033BC894A4E4AD8D6CCB3615B0C438AF336BCEDA","Original independently closed V34 strict negative remains immutable")
require(digest(strict_proof/"result.json")==grant["strict_runtime_original_result_sha256"]=="5C19A1B407FF582382AA84D83F4F1E176694D73F202B055EB5E3474465CC10A9" and digest(strict_proof/"final.json")==grant["strict_runtime_original_final_sha256"]=="FD3412DB1E671A6B5E923079AEF917FE292D79E8866A8602EDF4BD913D53BA59","Original strict negative result and complete final seal retained")
require(grant["minimum_free_kib"]==16777216 and grant["initial_grant_max_age_seconds"]==300 and grant["runtime_outer_actual_seconds"]==120 and grant["outer_controller_seconds"]==1800,"Original exact bounded diagnostic authority")
runtime_bounds=[];observations=[];runtime_receipts=[]
selected=cfg["selected"]
require(len(selected)==17 and [g["group"]for g in selected]==grant["groups"][:17] and [g["started"]for g in selected]==[15,12,34,28,10,20,18,14,13,32,19,22,20,15,11,12,17] and [g["completed"]for g in selected]==[15,12,34,28,10,20,18,14,13,32,19,22,20,15,11,12,16] and [g["flags"]for g in selected]==[{},{},{},{},{},{},{},{},{"6":1},{},{},{},{},{},{},{},{}],"Exact actual original V34 starts completions and flags")
require(0<=utc_ticks(selected[0]["created"])-utc_ticks(grant["issued_utc"])<=300*10000000,"Actual first native owner inside the original fresh grant interval")
for number,want in enumerate(selected):
 g=r["groups"][number];accepted=accept["groups"][number];gp=proof/"groups"/g["group"];partial=number==16;failed=bool(want["flags"])
 require(g["group"]==accepted["group"]==want["group"] and g["status"]==("failed" if failed or partial else "diagnostic_tests_passed_unqualified"),"Original group result and whole-batch negative preserved")
 require(g["owned_started_phases"]==g["attempted_phases"]==["runtime"] and g["runtime_owner_launch_attempted"] is True and g["actual_runtime_owner_started"] is True and g["postseal"] is True,"Exact actual native execution scope")
 require((gp/"runtime.results.json").exists() is (not partial),"Canonical completeness is never invented for assertion abort")
 canonical=None if partial else read(gp/"runtime.results.json")
 if not partial:
  require(g["native_selected_tests_started"]==canonical["expected"]==canonical["started"]==canonical["completed"]==want["started"]==want["completed"]==accepted["actual_count"] and canonical["version"]=="0.16.0","Original canonical complete counts/version")
  require(canonical["binary"]==accepted["cached_executable_path"] and canonical["binary_sha256"]==accepted["executable_sha256"] and canonical["owner_receipt"]==str(gp/"runtime.json"),"Original canonical artifact/owner")
  require(canonical["failed_or_skipped_or_logged_or_leaked"]==len(want["flags"]) and canonical["status"]==("failed" if failed else "passed"),"Original canonical negative/passing outcome")
 else:
  require(g["group"]=="native-node-fs-request-owner" and accepted["actual_count"]==26 and g["native_selected_tests_started"] is None and want["started"]==17 and want["completed"]==16,"Actual incomplete FS request owner group remains unqualified")
 phase=g["phases"]["runtime"];owner=read(gp/"runtime.json");absent=read(gp/"runtime-absence.json")
 require(digest(gp/"runtime.json")==want["owner_sha"] and owner["pid"]==want["pid"] and utc_ticks(owner["created_utc"])==utc_ticks(want["created"]) and utc_ticks(owner["completed_utc"])==utc_ticks(want["completed_utc"]),"Exact original native process instance")
 require(owner["status"]==("failed" if partial else "passed") and owner["exit_code"]==want["exit_code"]==(-1073740791 if partial else 0) and owner["timeout_seconds"]==120 and owner["retained_handle"]>0,"Exact bounded original terminal outcome, assertion abort is not terminal0")
 require(owner["executable"]==accepted["cached_executable_path"] and owner["executable_sha256"]==accepted["executable_sha256"] and owner["arguments"]==["--listen=-"] and owner["working_directory"]==str(main),"Exact native artifact/argv/root")
 live=owner["live_identity"];created=utc_ticks(owner["created_utc"]);completed=utc_ticks(owner["completed_utc"])
 require(live["pid"]==owner["pid"] and utc_ticks(live["created_utc"])==created and live["executable"]==owner["executable"] and live["command_line"]=='"'+owner["executable"]+'" --listen=-' and 0<=completed-created<=120*10000000,"Original retained live identity/deadline")
 admission=read(gp/"runtime-admission.json");probe=admission["probe"]
 require(admission["status"]=="admitted" and probe["phase"]=="runtime" and probe["free_kib"]>=16777216 and probe["minimum_kib"]==16777216 and probe["native"]==[] and probe["native_roots"]==0 and 0<=created-utc_ticks(probe["utc"])<10*10000000,"Original fresh serial sixteen GiB admission")
 require(absent["status"]=="closed" and absent["phase"]=="runtime" and absent["global_native"]==[],"Original phase absence")
 for e in (absent["evidence"],phase["evidence"],r["absence"]["owners"][number]["evidence"]):
  require(e["valid"] is True and e["evidence_errors"]==[] and normalized_owner(e["owner"])==normalized_owner(owner) and e["current_owner_pid_present"]==0 and e["current_owned_descendants"]==[] and e["absence_error"] is None and e["canonical_results"]==canonical,"Original exact owner/result/absence binding")
  require(e.get("preexisting_pid_ancestry",[])==[],"Unexpected ancestry requires explicit instance reconciliation")
 expected_error=("Owned terminal failed: "+owner["executable"]) if partial else ("Native test protocol did not report every selected test passing without logs/leaks" if failed else None)
 require(phase["failure"]==phase["original_execution_failure"]==expected_error,"Original execution failure unchanged")
 strict_errors=["Exact actual terminal0 owner/deadline required on positive and negative protocol paths"] if partial else (["Actual metadata/new API or ordinary retained runtime stderr must be empty"] if failed else [])
 require(phase["owner_binding"]["status"]==("invalid" if failed or partial else "passed") and phase["owner_binding"]["errors"]==strict_errors and phase["owner_binding"]["qualification"] is False,"Original strict empty-stderr and terminal0 gates preserved")
 require(phase["postchecks"]["errors"]==["Actual terminal owner binding failed: "+error for error in strict_errors] and g["errors"]==(["Actual terminal owner binding failed: "+error for error in strict_errors]+[expected_error] if failed or partial else []),"Exact original group and postcheck negatives retained without addition or omission")
 for key in ("evidence_valid","source_sealed","artifacts_bound","absence_closed"):require(phase["postchecks"][key] is True,"Original closure postcheck "+key)
 require(phase["postchecks"]["owner_bound"] is (not failed and not partial),"Original qualification rejection retained")
 if failed or partial:
  diagnostic=phase["diagnostic_continuation_binding"]
  require(diagnostic["status"]==("invalid" if partial else "passed") and diagnostic["errors"]==(strict_errors if partial else []) and diagnostic["diagnostic_continuation"] is True and diagnostic["retained_stderr_failure"] is (not partial) and diagnostic["qualification"] is False and diagnostic["expected_deadline"]==120 and diagnostic["expected_executable"]==owner["executable"] and diagnostic["expected_sha256"]==owner["executable_sha256"],"Separate diagnostic continuation closes only complete terminal0 negatives, rejects assertion abort")
 for row in phase["evidence"]["raw_outputs"]:
  path=Path(row["path"]);require(path.is_relative_to(gp) and path.stat().st_size==row["bytes"] and digest(path)==row["sha256"],"Original raw output binding")
 require(digest(gp/"runtime.stdout.bin")==want["stdout_sha"] and digest(gp/"runtime.stderr.log")==want["stderr_sha"] and (gp/"runtime.stderr.log").stat().st_size==want["stderr_bytes"],"Exact original wire and full retained stderr")
 require(bool(want["stderr_bytes"]) is (failed or partial),"Original empty stderr positive rule")
 raw=(gp/"runtime.stdout.bin").read_bytes();offset=0;tags=[];results=[];frames=[]
 while offset<len(raw):
  require(len(raw)-offset>=8,"Complete raw frame header")
  tag,size=struct.unpack_from("<II",raw,offset);offset+=8
  require(size<=1024*1024 and size<=len(raw)-offset,"Bounded full raw frame")
  payload=raw[offset:offset+size];offset+=size;tags.append(tag);frame=dict(tag=tag,length=size)
  if tag==0:
   require(tags==[0] and payload==b"0.16.0","Original Zig version frame");frame["version"]="0.16.0"
  elif tag==5:require(size==0 and len(tags)%2==0,"Actual start frame order")
  elif tag==4:
   require(size==12 and len(tags)%2==1 and tags[-2]==5,"Actual result follows one start")
   index,flags=struct.unpack("<IQ",payload)
   require(index==len(results) and flags==want["flags"].get(str(index),0),"Exact original sequential result flags")
   row=dict(index=index,flags=flags,passed=flags==0);frame.update(index=index,flags=flags)
   if canonical is not None:require(row==canonical["results"][index],"Independent raw equals original canonical")
   results.append(dict(**row,name=accepted["tests"][index]))
  else:raise RuntimeError("Unexpected runtime frame")
  frames.append(frame)
 expected_tags=[0]+[x for _ in range(want["completed"])for x in (5,4)]+([5] if partial else [])
 require(tags==expected_tags and tags.count(5)==want["started"] and len(results)==want["completed"] and offset==len(raw)==want["stdout_bytes"]==14+28*want["completed"]+(8 if partial else 0),"Exact complete frames with single uncompleted assertion-abort test")
 raw_observation=read(gp/"runtime-raw-frame-observation.json")
 require(raw_observation["frames"]==frames and raw_observation["parse_error"] is None and raw_observation["trailing_bytes"]==0,"Independent raw framing agrees with original non-authoritative observation")
 runtime_bounds.append(dict(pid=owner["pid"],created=created,completed=completed,role="runtime",group=g["group"]))
 observations.append(dict(group=g["group"],started=want["started"],completed=want["completed"],flagged=len(want["flags"]),incomplete=partial,results=results,original_group_status=g["status"],canonical=None if partial else pin(gp/"runtime.results.json"),incomplete_test=accepted["tests"][16] if partial else None))
 runtime_receipts.extend(pin(gp/name)for name in ("runtime.json","runtime.stdout.bin","runtime.stderr.log","runtime-absence.json","runtime-raw-frame-observation.json","result.json"))
 if not partial:runtime_receipts.append(pin(gp/"runtime.results.json"))
require(sum(g["started"]for g in observations)==312 and sum(g["completed"]for g in observations)==311 and sum(g["flagged"]for g in observations)==1 and sum(g["incomplete"]for g in observations)==1,"Exact312 started311 completed1 flagged and one incomplete")
failed_names=[dict(group=o["group"],index=row["index"],flags=row["flags"],name=row["name"])for o in observations for row in o["results"]if not row["passed"]]
require(failed_names==[dict(group="native-node-reqwrap-callback-routing",index=6,flags=1,name="native_node_reqwrap_callback_routing_test.test.native ReqWrap routing typed callback failure still retires the final native Wrapper pointer")],"Exact repeated ReqWrap callback routing negative and accepted metadata name")
require(observations[-1]["incomplete_test"]=="native_node_fs_request_owner_test.test.native FS request owner physical Read constructs native storage before init and dispatches the actual view span" and sum(g["actual_count"]for g in accept["groups"][17:])+26-17==973,"Exact FS request owner incomplete name and973 unstarted accepted tests")
require(len({v["pid"]for v in runtime_bounds})==17 and all(runtime_bounds[i]["completed"]<runtime_bounds[i+1]["created"]for i in range(16)),"Original serial nonoverlapping owner intervals")
assertion_stderr=(proof/"groups/native-node-fs-request-owner/runtime.stderr.log").read_bytes()
require(assertion_stderr==b"Assertion failed: atomic_load_explicit(&request->completed, memory_order_acquire), file C:\\Users\\adyba\\pi-zig\\main\\src\\extensions\\native_uv_tcp.c, line 804\n","Original exact157-byte actual FS request owner native completed assertion retained")
outer=read(control/"outer.json");oa=read(control/"outer-absence.json")
require(digest(control/"outer.json")==cfg["outer_sha256"] and digest(control/"outer-absence.json")==cfg["outer_absence_sha256"],"Original outer and absence")
require(outer["status"]=="failed" and outer["exit_code"]==1 and outer["timeout_seconds"]==1800 and outer["retained_handle"]>0 and outer["pid"]==cfg["outer_pid"],"Original bounded outer negative")
require(outer["arguments"]==["-NoLogo","-NoProfile","-NonInteractive","-File",str(prep/"Run-CombinedNativeBatch.ps1"),"-RootGrant",str(control/"root-grant.json"),"-Mode","DiagnosticRuntimeOnly"] and outer["executable_sha256"]=="FA2C8BB1E35CDD62AD15CD06A1D8F2C5961E9725A9BFA1E7CFD2C322F49E9619" and outer["working_directory"]==str(base),"Original exact outer control")
outer_live=outer["live_identity"]
require(outer["executable"]==r"C:\Program Files\PowerShell\7\pwsh.exe" and outer_live["pid"]==outer["pid"] and utc_ticks(outer_live["created_utc"])==utc_ticks(outer["created_utc"]) and outer_live["executable"]==outer["executable"],"Actual original retained outer creation identity")
require(outer_live["command_line"]=='"'+outer["executable"]+'" '+' '.join(outer["arguments"]) and outer.get("error")=="Owned terminal failed: C:\\Program Files\\PowerShell\\7\\pwsh.exe" and 0<=utc_ticks(outer["completed_utc"])-utc_ticks(outer["created_utc"])<=1800*10000000,"Exact actual live outer command, native deadline and original failed termination")
require(oa["pid"]==outer["pid"] and utc_ticks(oa["created_utc"])==utc_ticks(outer["created_utc"]) and oa["currently_absent"] is True and oa["current_records"]==[],"Original outer absence")
job=read(control/"independent-observed-job-status.json")["data"]
require(digest(control/"independent-observed-job-status.json")==cfg["job_status_sha256"] and job==cfg["job"] and job["status"]=="failed" and job["exitCode"]==1 and job["runnerAlive"] is False and job["runnerPid"]>0 and job["childPid"]>0 and job["runnerProcessInstance"] and job["completedAtUtc"],"Independently captured exact actual terminal diagnostic job observation")
bounds=runtime_bounds+[dict(pid=outer["pid"],created=utc_ticks(outer["created_utc"]),completed=utc_ticks(outer["completed_utc"]),role="outer")]
bounds.append(dict(pid=job["runnerPid"],created=int(job["runnerProcessInstance"])-116444736000000000,completed=utc_ticks(job["completedAtUtc"]),role="runner"))
bounds.append(dict(pid=job["childPid"],created=utc_ticks(job["createdAtUtc"]),completed=utc_ticks(job["completedAtUtc"]),role="launcher_job_lifetime_envelope"))
require(len(runtime_bounds)==17 and len({(row["pid"],row["created"])for row in runtime_bounds})==17 and all(row["completed"]>=row["created"]for row in bounds),"All original native process instances distinct and terminal intervals ordered")
pids=[row["pid"]for row in bounds]
require(digest(prep/"Get-ModelsNativeCandidates.ps1")=="3413A2A50B4D4C3BFF8709E4EE08C76BE449AAB1EDCB1E0C5C167DC7A804E301","Original classifier")
query=r"$ErrorActionPreference='Stop';. 'C:\Users\adyba\pi-zig\evidence\combined-native-runtime-diagnostic-v34-prepared-20261020\Get-ModelsNativeCandidates.ps1';$taskRows=@(Get-CimInstance Win32_Process -OperationTimeoutSec 5 -ErrorAction Stop);$taskPids=@("+",".join(map(str,pids))+r");$taskLive=@($taskRows|Where-Object {$_.ProcessId -in $taskPids}|Select-Object ProcessId,ParentProcessId,ExecutablePath,CommandLine,CreationDate);$taskDirect=@($taskRows|Where-Object {$_.ParentProcessId -in $taskPids}|Select-Object ProcessId,ParentProcessId,ExecutablePath,CommandLine,CreationDate);$taskNative=@(Get-ModelsNativeCandidates -Rows $taskRows -Container 'C:\Users\adyba\pi-zig');ConvertTo-Json -InputObject ([ordered]@{owners=$taskLive;direct_children=$taskDirect;native=$taskNative;observed_utc=[DateTimeOffset]::UtcNow.ToString('o')}) -Depth 8 -Compress"
current=json.loads(subprocess.check_output([r"C:\Program Files\PowerShell\7\pwsh.exe","-NoLogo","-NoProfile","-NonInteractive","-Command",query],text=True,timeout=15))
require(current["native"]==[],"Current independent global native absence")
reconciled=[]
for row in current["owners"]:
 candidates=[v for v in bounds if v["pid"]==row["ProcessId"]];born=utc_ticks(row["CreationDate"])
 require(candidates and all(born>v["completed"]for v in candidates),"Only proved later nonoverlapping PID reuse")
 reconciled.append(dict(kind="later_process_reusing_retired_pid",current_record=row,prior_terminal_intervals=candidates))
for row in current["direct_children"]:
 candidates=[v for v in bounds if v["pid"]==row["ParentProcessId"]];born=utc_ticks(row["CreationDate"])
 require(candidates and all(born<v["created"]-10 or born>v["completed"]for v in candidates),"No apparent descendant born within actual owned interval")
 reconciled.append(dict(kind="creation_time_excludes_prior_parent_instance",current_record=row,prior_terminal_intervals=candidates))
certificate=dict(schema=1,status="independently_closed_partial_negative_diagnostic_runtime",candidate_head=head,reviewed_utc=datetime.datetime.now(datetime.timezone.utc).isoformat(),reviewer="Independent complete current inventory/hash, accepted artifacts, complete and partial raw wire, canonical results and actual100ns process-instance audit",source_seal_scope="whole_batch",whole_bookends_unchanged=True,current_all_sealed_inputs_rehashed=True,current_complete_directory_inventories_verified=True,distinct_current_files_rehashed=len(all_pins),current_sealed_inventory_counts={role:len(final[role])for role in ("source","tree","vendor","compiler","controls")},metadata_acceptance=pin(accept_path),accepted_cohort=1285,runtime_owner_count=17,actual_process_intervals=bounds,observed_started=312,observed_completed=311,observed_flagged=1,observed_passed=310,incomplete_tests=1,not_started=973,observed_failed_tests=failed_names,observed_groups=observations,current_absence=current,current_actual_process_instances_absent=True,current_process_instance_reconciliations=reconciled,original_receipts=[pin(proof/"result.json"),pin(proof/"before.json"),pin(proof/"final.json"),pin(control/"outer.json"),pin(control/"outer-absence.json"),pin(control/"root-grant.json"),pin(control/"launch.ps1"),pin(cfg_path),pin(control/"independent-observed-job-status.json"),pin(strict_control/"independent-negative-runtime-closure.json")]+runtime_receipts,controller_environment_restored=True,original_strict_empty_stderr_terminal0_all_tests_passing_rejection_preserved=True,diagnostic_continuation_rejected_original_assertion_abort=True,complete_diagnostic=False,runtime_qualification=False,product_qualification=False,source_mutation_hold_released=False)
with output.open("x",encoding="utf-8",newline="\n")as handle:handle.write(json.dumps(certificate,indent=2)+"\n")
print(json.dumps(dict(status=certificate["status"],closure=str(output),sha256=digest(output),distinct_current_files_rehashed=len(all_pins),runtime_owners=17,actual_started=312,actual_completed=311,flagged=1,passed=310,incomplete=1,not_started=973,current_instances_absent=True,source_mutation_hold_released=False,qualification=False)))
