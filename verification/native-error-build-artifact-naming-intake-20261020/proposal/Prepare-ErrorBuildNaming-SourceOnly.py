"""Source-only exact Error build naming proposal; evidence writes only."""
from pathlib import Path
import ast,datetime,hashlib,json,re,subprocess,os
ROOT=Path(r"C:\Users\adyba\pi-zig");E=ROOT/"evidence";MAIN=ROOT/"main"
OUT=E/"native-error-build-artifact-naming-sourceonly-20261020"
SDK=ROOT/"worktrees/sdk-owners-resume-20261018/verification"
HEAD="160b4e0562f0eb1139bf2e4e9c00f4c10ab6aa64"
sha=lambda b:hashlib.sha256(b).hexdigest().upper()
def info(p,b=None):
 p=Path(p);b=p.read_bytes() if b is None else b
 return dict(path=str(p),bytes=len(b),sha256=sha(b))
def pin(p,h):
 b=Path(p).read_bytes();assert sha(b)==h,(str(p),sha(b),h);return b
def write(p,b):
 assert p.resolve().is_relative_to(OUT.resolve()) and not p.exists()
 p.parent.mkdir(parents=True,exist_ok=True)
 with p.open("xb") as f:f.write(b)
 return info(p,b)
def dump(p,j):return write(p,(json.dumps(j,indent=2)+"\n").encode())
def git(*args):
 return subprocess.check_output(["git",*args],cwd=MAIN,env=dict(os.environ,GIT_OPTIONAL_LOCKS="0"))
assert git("rev-parse","HEAD").decode().strip()==HEAD
assert git("status","--porcelain=v1","--untracked-files=all")==b""
pre_path=E/"pending-file-handle-and-error-intake-20261020/projected/build.zig"
post_path=SDK/"native-file-handle-transfer-sourceonly-20261020/build/combined-after-owner-and-constructor.zig"
pre=pin(pre_path,"399BD2EF5A4360C60478C30A6AB4BD36F151CC538C93174BC3EFA603536E4A52")
post=pin(post_path,"DB9BEE3C8B7C8FF817F1FB2AE761F7A7400EA3250CDD7AF7AFBAA4118FD13909")
assert (MAIN/"build.zig").read_bytes()==post and git("show",HEAD+":build.zig")==post
transfer_path=SDK/"native-file-handle-transfer-sourceonly-20261020/build/proposal.json"
transfer=json.loads(pin(transfer_path,"D662D5DF7D2C21CD8376666E120CAEEA8BB46E0518C5B3560E6A97522D6BB212"))
assert len(transfer["edits"])==1
te=transfer["edits"][0];ta=te["before"].encode();tb=te["after"].encode()
assert pre.count(ta)==post.count(tb)==1 and pre.replace(ta,tb)==post and post.replace(tb,ta)==pre
edits=[
 {"label":"use_canonical_default_test_cache_name","before":'        .name = "native-vm-error-constructor-name",\n',"after":""},
 {"label":"preserve_public_installed_executable_basename","before":'    b.step("build-native-vm-error-constructor-name", "Install actual native Error constructor provenance controls without execution").dependOn(&b.addInstallArtifact(native_error_constructor_name_tests, .{}).step);\n',"after":'    b.step("build-native-vm-error-constructor-name", "Install actual native Error constructor provenance controls without execution").dependOn(&b.addInstallArtifact(native_error_constructor_name_tests, .{ .dest_sub_path = b.fmt("native-vm-error-constructor-name{s}", .{if (target.result.os.tag == .windows) ".exe" else ""}) }).step);\n'}]
def correct(raw):
 result=raw;rows=[]
 for e in edits:
  a=e["before"].encode();b=e["after"].encode();assert result.count(a)==1
  offset=result.index(a);before_hash=sha(result);result=result[:offset]+b+result[offset+len(a):]
  rows.append(dict(e,byte_offset=offset,before_sha256=before_hash,after_sha256=sha(result),occurrences_before=1,after_bytes=len(b)))
 reverse=result
 for e in reversed(rows):
  a=e["before"].encode();b=e["after"].encode();offset=e["byte_offset"]
  assert sha(reverse)==e["after_sha256"] and reverse[offset:offset+len(b)]==b
  reverse=reverse[:offset]+a+reverse[offset+len(b):];assert sha(reverse)==e["before_sha256"]
 assert reverse==raw
 return result,rows
before_transfer,pre_edits=correct(pre);selected,post_edits=correct(post)
assert before_transfer.count(ta)==1 and before_transfer.replace(ta,tb)==selected
assert selected.count(tb)==1 and selected.replace(tb,ta)==before_transfer
assert selected.count(b'const native_error_constructor_name_tests = b.addTest(')==1
assert selected.count(b'"src/native_vm_error_constructor_name_test.zig"')==1
assert selected.count(b'b.step("build-native-vm-error-constructor-name"')==1
assert selected.count(b'.filters = &.{"VM native Error constructor"}')==post.count(b'.filters = &.{"VM native Error constructor"}')==1
assert selected.count(b'addRunArtifact')==post.count(b'addRunArtifact')
for begin,end in [(b'    const native_error_constructor_name_tests = b.addTest(.{\n',b'    const exotic_operation_tests = b.addTest(.{\n')]:
 p0=post.index(begin);p1=post.index(end,p0);n0=selected.index(begin);n1=selected.index(end,n0)
 assert post[:p0]==selected[:n0] and post[p1:]==selected[n1:]
old_block=post[p0:p1];new_block=selected[n0:n1]
control_path=SDK/"native-vm-error-constructor-name-sourceonly-20261020/successor/source/src/native_vm_error_constructor_name_test.zig"
control=pin(control_path,"64BA3A1BF4490255F333960EC1DE80364F8410C59E73BB35C5BA085A1E611525")
names=[x.decode() for x in re.findall(rb'^test "([^"]+)"',control,re.M)]
assert len(names)==24 and len(set(names))==24
assert b'.stack_limit' not in control
toolchain=ROOT/"toolchain/zig-x86_64-windows-0.16.0/lib/std"
specs=[
 ("Build.zig","DFFB5A172899D660C370C6CDECA04C073468C64F28B9BB6FCE919E71D1D5326D",[(858,888)]),
 ("Build/Step/Compile.zig","6239A10E6EF3027173BD108877544E32717DA6E51CBBC1A8FB4485F8F4F6AB84",[(381,410),(1484,1485),(1810,1813),(1836,1850)]),
 ("Build/Step/InstallArtifact.zig","6008437F2DF91E09396B0732B5E10094EF2DF5BE21AA6ABA53F08926FEF685A0",[(78,82),(104,108),(162,165)]),
 ("zig.zig","5445596331AD810FC60057FCE5555477E9317441FB36F69C632F37F0D1DA0824",[(156,161),(979,1010)]),
 ("Target.zig","B830BAC98558E0E6B83AF9917F3FF492452F57F608C3C54F009384C793A6F345",[(100,111),(2119,2121)])]
authority=[]
for rel,h,spans in specs:
 path=toolchain/rel;raw=pin(path,h);lines=raw.splitlines(keepends=True);quotes=[]
 for a,z in spans:
  part=b"".join(lines[a-1:z]);quotes.append(dict(first_line=a,last_line=z,bytes=len(part),sha256=sha(part),text=part.decode()))
 authority.append(dict(original=info(path,raw),snapshot_relative="authority/zig/"+rel,raw=raw,excerpts=quotes))
driver_path=E/"combined-native-batch-v34-prepared-20261020/Run-CombinedNativeBatch.ps1"
auditor_path=driver_path.with_name("Audit-CombinedNativeBatch.py")
driver=pin(driver_path,"1DD3A9D27FA7B54F9383F325792A9E5259C66C32FA6C601F21216B4DBB483601")
auditor=pin(auditor_path,"1436211CABD8D2D2C0A31DB4005C05BA3451E50E381F7EC3AFF8ACC094CAE98B")
assert b"-Filter test.exe" in driver and b"'bin/test.pdb'" in driver and b'Canonical actual cached roles required' in auditor
assert git("rev-parse","HEAD").decode().strip()==HEAD and git("status","--porcelain=v1","--untracked-files=all")==b""
assert (MAIN/"build.zig").read_bytes()==post
assert not (OUT/"proposal.json").exists()
pre_original=write(OUT/"original/before-transfer-build.zig",pre)
post_original=write(OUT/"original/build.zig",post)
pre_selected=write(OUT/"projected/before-transfer-build.zig",before_transfer)
post_selected=write(OUT/"projected/build.zig",selected)
control_copy=write(OUT/"control/src/native_vm_error_constructor_name_test.zig",control)
retained=write(OUT/"original/transfer-build-proposal.json",transfer_path.read_bytes())
for x in authority:
 raw=x.pop("raw");x["snapshot"]=write(OUT/x.pop("snapshot_relative"),raw)
authority_receipt=dump(OUT/"zig-naming-authority.json",dict(schema=1,files=authority,compiler_executed=False))
driver_copy=write(OUT/"original/Run-CombinedNativeBatch.ps1",driver)
auditor_copy=write(OUT/"original/Audit-CombinedNativeBatch.py",auditor)
report=dict(schema=1,status="source_only_exact_error_build_artifact_naming_correction_unissued",created_utc=datetime.datetime.now(datetime.timezone.utc).isoformat(),basis_main_head=HEAD,relative_path="build.zig",original=post_original,projected=post_selected,edits=post_edits,finite_edits=2,whole_forward_exact=True,whole_inverse_exact=True,original_main_and_raw_git_basis_equal=True,production_sources_modified=0,test_sources_modified=0,build_paths_modified=1,
 problem="The reviewed Error addTest custom name derives cached native-vm-error-constructor-name.exe and .pdb, while unchanged strict driver1DD3 and metadata auditor1436211C require test.exe/test.pdb. Installed executable remains native-vm-error-constructor-name.exe.",
 intended_behavior=dict(cached_executable="test.exe",cached_pdb="test.pdb",installed_executable="native-vm-error-constructor-name.exe",installed_pdb="test.pdb",non_windows_installed_executable="native-vm-error-constructor-name",build_step="build-native-vm-error-constructor-name",filter="VM native Error constructor",source_root="src/native_vm_error_constructor_name_test.zig",source_declarations=24,actual_metadata_count=None),
 authority=authority_receipt,unchanged_driver=dict(original=info(driver_path,driver),copy=driver_copy),unchanged_metadata_auditor=dict(original=info(auditor_path,auditor),copy=auditor_copy),
 protected_test_source=dict(original=info(control_path,control),copy=control_copy,named_declarations=names,complete_bytes_unchanged=True,default_engine_guard_unchanged=True),
 transfer_composition=dict(proposal=info(transfer_path),retained_copy=retained,before_transfer_original=pre_original,before_transfer_projected=pre_selected,before_transfer_edits=pre_edits,transfer_then_naming_result=post_selected,naming_then_transfer_result_sha256=sha(before_transfer.replace(ta,tb)),both_orders_byte_equal=True,naming_whole_inverse_after_transfer=True,naming_whole_inverse_before_transfer=True,transfer_whole_inverse_before_naming=True,transfer_whole_inverse_after_naming=True,original_transfer_block_preserved=True),
 exact_build_scope=dict(old_error_block=old_block.decode(),new_error_block=new_block.decode(),all_bytes_outside_error_block_unchanged=True,root_target_filter_link_recipe_unchanged=True,run_steps_added=0,all_other_owner_error_transfer_intakes_preserved=True),
 source_only=True,main_mutated=False,compiler_executed=False,native_executed=False,source_execution_authorized=False,qualification=False)
proposal=dump(OUT/"proposal.json",report)
print(json.dumps(dict(proposal=proposal,selected=post_selected,before_transfer=pre_selected,authority=authority_receipt,edits=2,both_orders_exact=True,main_unchanged=True,native_execution=False),indent=2))
