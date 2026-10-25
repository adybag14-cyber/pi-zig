"""Root-authored bounded source-only composition. No Main writes or native execution.
Usage: python script.py exact-reviewed-config.json SHA256
The configuration is a specific Root source generator grant, never native authority.
"""
from pathlib import Path
from datetime import datetime,timezone
import difflib,hashlib,json,posixpath,re,subprocess,sys
R=Path(r"C:\Users\adyba\pi-zig");M=R/"main";E=R/"evidence"
HEAD="c248553d15282e1e8ad896382c78132b6a501dd9"
def sha(b):return hashlib.sha256(b).hexdigest().upper()
def pin(p):
 p=Path(p);b=p.read_bytes();return dict(path=str(p),bytes=len(b),sha256=sha(b))
def verify(v):
 p=Path(v["path"]);assert p.is_absolute() and p.resolve().is_relative_to(R.resolve())
 assert pin(p)=={k:v[k] for k in ("path","bytes","sha256")},str(p)
 return p
def read(p):return json.loads(Path(p).read_bytes().decode("utf-8-sig"))
def check_main():
 assert subprocess.check_output(["git","-C",str(M),"rev-parse","HEAD"],text=True).strip()==HEAD
 assert subprocess.check_output(["git","-C",str(M),"status","--porcelain"])==b""
def safe_rel(x):
 assert "\\" not in x and posixpath.normpath(x)==x and not x.startswith(("/","../")) and ":" not in x
 return x
def put(p,b):
 p.parent.mkdir(parents=True,exist_ok=True)
 with p.open("xb") as f:f.write(b)
 assert p.read_bytes()==b
 return pin(p)
def put_json(p,j):return put(p,(json.dumps(j,indent=2)+"\n").encode())
assert __debug__ and len(sys.argv)==3
C=Path(sys.argv[1]);assert C.resolve().is_relative_to(E.resolve()) and pin(C)["sha256"]==sys.argv[2]
cfg=read(C)
assert cfg["schema"]==1 and cfg["status"]=="Root_reviewed_specific_source_composition"
assert cfg["candidate_head"]==HEAD and cfg["source_generation_authorized"] is True
assert cfg["Main_write_authorized"] is False and cfg["native_execution_authorized"] is False
assert cfg["preparer_sha256"]==pin(__file__)["sha256"]
OUT=Path(cfg["output_directory"])
assert OUT.resolve().is_relative_to((E/"resume-20261025-root").resolve()) and not OUT.exists()
closure=read(verify(cfg["original_negative_closure_acceptance"]))
assert cfg["original_native_lease_independently_closed"] is True
assert closure["reviewer"]=="Root" and closure["candidate_head"]==HEAD
assert closure["status"]=="Root_accepted_original_v47_new39_admission_negative_closure"
assert closure["original_job_id"]=="job-1792923870520-42d507d6-ee0"
assert closure["source_mutation_hold_released"] is True
assert closure["native_owners_started"]==closure["actual_metadata_count"]==closure["actual_tests_started"]==0
assert closure["all_39416_current_sealed_files_match"] is True
assert closure["whole_source_compiler_vendor_control_bookends_unchanged"] is True
assert closure["original_three_controller_instances_independently_absent"] is True
assert closure["native_execution_authorized"] is False and closure["complete_buildquery_accepted"] is False
independent=read(verify(closure["independent_closure"]))
assert independent["candidate_head"]==HEAD and independent["status"]=="independently_closed_prelaunch_memory_admission_negative"
assert independent["current_actual_process_instances_absent"] is True and independent["whole_bookends_unchanged"] is True
assert independent["native_owner_count"]==independent["actual_metadata_count"]==independent["actual_tests_started"]==0
assert len(cfg["packets"])==4 and {p["name"] for p in cfg["packets"]}=={"warning44","wrap32","chalk34","diagnostics47"}
check_main()
selected={};build_insertions=[];packet_records=[];names=[];evidence=[]
BASE=(M/"build.zig").read_bytes()
def add_evidence(source,rel,role):
 safe_rel(rel)
 evidence.append(dict(operation="create_exact",source=pin(source),destination_relative_path=rel,precondition=dict(absent=True),role=role))
for packet in cfg["packets"]:
 entry=verify(packet["entry"]);root_accept=verify(packet["Root_source_acceptance"]);peer=verify(packet["independent_peer"])
 j=read(entry);P=entry.parent
 assert (j.get("source_basis_head") or j.get("base"))==HEAD
 accepted=read(root_accept)
 assert accepted["packet"]==pin(entry) and accepted["independent_peer"]==pin(peer)
 assert accepted["source_basis_head"]==HEAD and accepted["runtime_qualification"] is False
 changes=j.get("changes")
 if changes is None:
  changes=[]
  for c in j["projected_changes"]:
   rel=c["relative"]; baseline=None
   if c["base_sha256"] is not None:
    baseline=pin(M/rel);assert baseline["sha256"]==c["base_sha256"] and baseline["bytes"]==c["base_bytes"]
   changes.append(dict(destination_relative_path=rel,baseline=baseline,candidate=c["projected"]))
 for c in changes:
  rel=safe_rel(c["destination_relative_path"]);candidate=verify(c["candidate"])
  baseline=c["baseline"]
  if baseline is None:assert not (M/rel).exists(),rel
  else:
   assert (M/rel).exists()
   assert pin(M/rel)["sha256"]==baseline["sha256"] and pin(M/rel)["bytes"]==baseline["bytes"],rel
  if rel=="build.zig":
   addition=verify(packet["build_addition"]).read_bytes()
   projected=candidate.read_bytes()
   assert projected.count(addition)==1
   at=projected.index(addition)
   assert projected[:at]+projected[at+len(addition):]==BASE
   build_insertions.append(dict(packet=packet["name"],baseline_byte_offset=at,addition=packet["build_addition"]))
  else:
   key=rel.lower();assert key not in selected,("Unreviewed shared source overlap",rel)
   selected[key]=dict(destination_relative_path=rel,operation="replace_exact" if baseline else "create_exact",baseline=pin(M/rel) if baseline else None,candidate=pin(candidate),packet=packet["name"])
 controls=j["controls"];declared=controls["names"] if isinstance(controls,dict) else controls
 assert len(declared)==len(set(declared))
 test_root=safe_rel(packet["test_root"])
 source=verify(selected[test_root.lower()]["candidate"]).read_bytes().decode()
 assert re.findall(r'^test "([^"]+)"',source,re.M)==declared
 names.extend(declared)
 packet_records.append(dict(name=packet["name"],entry=pin(entry),Root_source_acceptance=pin(root_accept),independent_peer=pin(peer),declared_controls=len(declared)))
 # Retain complete compact source evidence, authorities, generators and patch;
 # original/projected large source copies are recoverable from baseline git plus patch.
 listing=subprocess.check_output(["rg","--files","--no-ignore"],cwd=P,text=True).splitlines()
 for name in sorted(listing):
  rel=name.replace("\\","/");safe_rel(rel)
  if rel.split("/")[0] in ("original","projected","__pycache__"):continue
  source=P/rel
  assert source.is_file() and source.stat().st_size<2_000_000,(rel,"unexpected evidence size")
  add_evidence(source,"verification/native-port-consumers-intake-20261025/"+packet["name"]+"/"+rel,packet["name"]+".packet")
 add_evidence(root_accept,"verification/native-port-consumers-intake-20261025/"+packet["name"]+"/references/"+root_accept.name,packet["name"]+".Root_acceptance")
 add_evidence(peer,"verification/native-port-consumers-intake-20261025/"+packet["name"]+"/references/"+peer.name,packet["name"]+".independent_peer")
assert len(names)==len(set(names))
# All four independently projected build files are pure insertions into the same baseline.
combined=bytearray();last=0
for entry in sorted(build_insertions,key=lambda x:x["baseline_byte_offset"]):
 at=entry["baseline_byte_offset"];assert at>=last
 combined+=BASE[last:at]+verify(entry["addition"]).read_bytes();last=at
combined+=BASE[last:]
reconstructed=bytes(combined)
for entry in build_insertions:
 addition=verify(entry["addition"]).read_bytes()
 assert reconstructed.count(addition)==1
 reconstructed=reconstructed.replace(addition,b"",1)
assert reconstructed==BASE
OUT.mkdir()
combined_pin=put(OUT/"projected/build.zig",bytes(combined))
selected["build.zig"]=dict(destination_relative_path="build.zig",operation="replace_exact",baseline=pin(M/"build.zig"),candidate=combined_pin,packet="composition")
ops=sorted(selected.values(),key=lambda x:x["destination_relative_path"])
# Resolve literal imports against the actual final composition, not individual packet baselines.
direct=[];packages=[];embeds=[]
for op in ops:
 rel=op["destination_relative_path"]
 if not rel.endswith(".zig") or rel=="build.zig":continue
 text=verify(op["candidate"]).read_bytes().decode()
 for match in re.finditer(r'@(import|embedFile)\("([^"]+)"\)',text):
  kind,literal=match.groups()
  row=dict(importer=rel,line=text.count("\n",0,match.start())+1,literal=literal)
  if kind=="import" and not literal.endswith(".zig"):
   packages.append(row);continue
  target=posixpath.normpath(posixpath.join(posixpath.dirname(rel),literal));safe_rel(target)
  chosen=selected.get(target.lower())
  path=Path(chosen["candidate"]["path"]) if chosen else M/target
  assert path.is_file(),(rel,literal,target)
  row.update(target=target,selected=pin(path))
  (direct if kind=="import" else embeds).append(row)
patches=[]
for op in ops:
 rel=op["destination_relative_path"]
 before=verify(op["baseline"]).read_bytes() if op["baseline"] else b""
 after=verify(op["candidate"]).read_bytes()
 for line in difflib.unified_diff(before.decode().splitlines(keepends=True),after.decode().splitlines(keepends=True),fromfile="a/"+rel if op["baseline"] else "/dev/null",tofile="b/"+rel,n=3):
  patches.append(line if line.endswith("\n") else line+"\n\\ No newline at end of file\n")
patch=put(OUT/"source-composition.patch","".join(patches).encode())
check=subprocess.run(["git","-C",str(M),"apply","--check","--",patch["path"]],capture_output=True,text=True)
assert check.returncode==0,check.stderr
check_pin=put_json(OUT/"git-apply-check.json",dict(read_only=True,candidate_head=HEAD,exit_code=check.returncode,stdout=check.stdout,stderr=check.stderr))
add_evidence(verify(cfg["original_negative_closure_acceptance"]),"verification/native-port-consumers-intake-20261025/composition/references/"+Path(cfg["original_negative_closure_acceptance"]["path"]).name,"composition.original_native_closure")
for row in cfg.get("additional_evidence",[]):
 source=verify(row)
 add_evidence(source,"verification/native-port-consumers-intake-20261025/composition/references/"+source.name,"composition.reviewed_reference")
keys=[x["destination_relative_path"].lower() for x in evidence]
assert len(keys)==len(set(keys)),"Duplicate evidence destinations"
assert not set(keys)&set(selected)
for op in evidence:assert not (M/op["destination_relative_path"]).exists(),op["destination_relative_path"]
# Pin each dependency advance explicitly. Existing packet baseline pins remain historical.
advances=[]
for op in ops:
 if op["baseline"] and op["destination_relative_path"]!="build.zig":
  advances.append(dict(destination_relative_path=op["destination_relative_path"],before=op["baseline"],selected=op["candidate"],successor_packet=op["packet"],requires_fresh_native_qualification=True))
plan=dict(schema=1,created_utc=datetime.now(timezone.utc).isoformat(),status="reviewable_source_composition_not_materialized",Root_configuration=pin(C),preparer=pin(__file__),baseline_head=HEAD,packets=packet_records,source_file_operations=ops,build_insertions=build_insertions,complete_build_inverse=True,source_patch=patch,git_apply_check=check_pin,final_direct_imports=direct,literal_embeds=embeds,standard_package_imports=packages,explicit_shared_dependency_advances=advances,evidence_operations=evidence,counts=dict(source_build_paths=len(ops),evidence_paths=len(evidence),pending_paths=len(ops)+len(evidence),new_roots=len(packet_records),new_declared_controls=len(names),fresh_selected_roots=39+len(packet_records),fresh_declared_controls=943+len(names),full_catalog_groups=160+len(packet_records),full_catalog_declared_controls=3009+len(names)),control_names=names,original_negative_closure_acceptance=cfg["original_negative_closure_acceptance"],materialization_authorized=False,Main_mutated=False,native_execution_authorized=False,actual_metadata_count=None,runtime_qualification=False,production_bridge_removed=False,application_qualified=False,remaining=["Fresh C-library and all selected native build/metadata/runtime from final committed sources.","Complete diagnostics TracingChannel and genuine uncaught-exception adapter assembly.","Actual canonical node:module assembler and production worker wiring.","Original Main createRuntime and startup selector/input/TUI graph."])
check_main()
plan_pin=put_json(OUT/"source-intake-plan.json",plan)
print(json.dumps(dict(plan=plan_pin,counts=plan["counts"],source_patch=patch,Main_modified=False)))
