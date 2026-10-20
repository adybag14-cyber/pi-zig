"""Independent source audit only. No VM, compiler, preprocessor or test execution."""
from pathlib import Path
import hashlib,json,re,subprocess
S=Path(r'C:\Users\adyba\pi-zig\worktrees\sdk-owners-resume-20261018')
P=S/'verification/native-vm-error-constructor-name-sourceonly-20261020'
O=Path(__file__).parent
def h(b):return hashlib.sha256(b).hexdigest().upper()
def record(path,expected=None):
 b=path.read_bytes();sha=h(b)
 if expected:assert sha==expected,(str(path),sha,expected)
 return {'path':str(path),'bytes':len(b),'sha256':sha}
def raw(path):return path.read_bytes()
subject=P/'vm-projection-successor.json'
pins=[record(subject,'64DB11E161C4AF40DBE7ABC1D981D07F4E6BD74B69B806353EDBA86F5F6A6702')]
d=json.loads(raw(subject))
originals={r['path']:raw(Path(r['original']['path'])) for r in d['files']}
states=dict(originals);steps=[]
for i,e in enumerate(d['edits'],1):
 assert i==e['sequence']
 b=states[e['path']];old=e['old_text'].encode();new=e['new_text'].encode();offset=e['offset_in_predecessor']
 assert h(b)==e['before_file_sha256']
 assert len(old)==e['old_bytes'] and len(new)==e['new_bytes']
 assert b.count(old)==1 and b.find(old)==offset,(e['label'],b.count(old),b.find(old),offset)
 after=b[:offset]+new+b[offset+len(old):];assert h(after)==e['after_file_sha256']
 states[e['path']]=after
 steps.append({'sequence':i,'label':e['label'],'offset':offset,'before_sha256':h(b),'after_sha256':h(after)})
for r in d['files']:
 for kind in ['original','projected']:
  q=r[kind];assert record(Path(q['path']),q['sha256'])['bytes']==q['bytes'];pins.append(record(Path(q['path'])))
 assert states[r['path']]==raw(Path(r['projected']['path']))
 git_original=subprocess.check_output(['git','-C',r'C:\Users\adyba\pi-zig\main','show',d['basis_main_head']+':'+r['path']])
 assert git_original==originals[r['path']]
for e in reversed(d['edits']):
 b=states[e['path']];old=e['old_text'].encode();new=e['new_text'].encode();offset=e['offset_in_predecessor']
 assert h(b)==e['after_file_sha256'];assert b[offset:offset+len(new)]==new
 b=b[:offset]+old+b[offset+len(new):];assert h(b)==e['before_file_sha256'];states[e['path']]=b
assert states==originals
fragment=d['new_fragment'];fragment_path=Path(fragment['snapshot_path']);fragment_raw=raw(fragment_path)
assert record(fragment_path,fragment['sha256'])['bytes']==fragment['bytes']
pins.append(record(fragment_path));pins.append(record(Path(fragment['live_path']),fragment['sha256']))
text=fragment_raw.decode()
symbols=['js_pi_intrinsic_error_constructor','js_pi_cache_error_constructor','js_pi_record_error_constructor','js_pi_record_intrinsic_error','js_pi_constructor_own_data','js_pi_constructor_debug_name','JS_PiGetNativeErrorConstructorName']
for name in symbols:
 assert not re.search(rb'\b'+name.encode()+rb'\b',originals['vendor/quickjs/quickjs.c'])
 assert not re.search(rb'\b'+name.encode()+rb'\b',originals['vendor/quickjs/quickjs.h'])
 assert re.search(r'\b'+name+r'\s*\([^;{}]*\)\s*\{',text)
for prohibited in ['JS_GetProperty(', 'JS_GetPropertyStr(', 'JS_Call(', 'JS_CallConstructor(', 'JS_Throw(', 'JS_NewString(', 'JS_NewObject(', 'JS_GetException(', 'JS_SetProperty(', 'JS_ToString(']:
 assert prohibited not in text,prohibited
build_path=P/'build/proposal.json';pins.append(record(build_path,'54760A19321B0DC5C2B3C036B7942EF2F8F212565C0A1B691E324E94D6F7CD8A'))
build=json.loads(raw(build_path));a=raw(Path(build['original']['path']));b=raw(Path(build['projected']['path']));e=build['edit'];old=e['old_text'].encode();new=e['new_text'].encode();offset=e['offset_in_predecessor']
assert a.find(old)==offset and a.count(old)==1 and b.count(new)==1
assert a.replace(old,new,1)==b and b.replace(new,old,1)==a
assert subprocess.check_output(['git','-C',r'C:\Users\adyba\pi-zig\main','show',build['basis_main_head']+':build.zig'])==a
for k in ['original','projected']:pins.append(record(Path(build[k]['path']),build[k]['sha256']))
control=P/'successor/source/src/native_vm_error_constructor_name_test.zig'
pins.append(record(control,'64BA3A1BF4490255F333960EC1DE80364F8410C59E73BB35C5BA085A1E611525'))
names=re.findall(r'^test "([^"]+)"',control.read_text(encoding='utf-8'),re.M)
assert len(names)==len(set(names))==24
assert all(n.startswith(build['target']['filter']) for n in names)
assert build['target']['declared_named_controls']==len(names)
assert '@import(' not in control.read_text(encoding='utf-8').replace('@import("std")','')
authority_pins=[record(q) for q in sorted((P/'authority').iterdir()) if q.is_file()]
pins.extend(authority_pins)
support=json.loads(raw(P/'support-bindings.json'));pins.append(record(P/'support-bindings.json','D0DF66CE2B2409B3EE19A2A146AA9DC83A419B95B0DBCAA0FA6139D5D5E55002'))
for r in support:
 pins.append(record(Path(r['snapshot']),r['sha256']));pins.append(record(Path(r['source']),r['sha256']))
predecessor=d['retained_predecessor'];pins.append(record(Path(predecessor['path']),predecessor['sha256']))
stack=P/'control-stack-limit-source-choice.json';pins.append(record(stack,'D0FA22D7E0898F4071A96F60B545BC1528328F579D3ACCC0E9388ED7E79722FB'))
choice=json.loads(raw(stack));old_control=P/'source/src/native_vm_error_constructor_name_test.zig'
assert h(raw(old_control))==choice['prior_sha256'];pins.append(record(old_control))
assert raw(old_control).replace(choice['old_text'].encode(),choice['new_text'].encode(),1)==raw(control)
assert raw(old_control).count(choice['old_text'].encode())==1
result={'schema':'pi-zig.independent-native-error-constructor-source-audit.v1',
 'subject':str(subject),'subject_sha256':pins[0]['sha256'],'source_only':True,'native_compiler_test_or_project_execution':False,
 'basis_main_head':d['basis_main_head'],'all_originals_equal_pinned_git_commit':True,
 'exact_edit_count':len(steps),'per_step_offsets_and_hashes_match':True,'whole_forward_and_inverse_match':True,
 'steps':steps,'new_private_symbol_names_absent_in_original_c_and_h':symbols,
 'full_fragment_reviewed_separately':True,
 'lexical_guest_or_allocating_query_entry_names_absent':'Listed direct high-level Get/Call/Throw/New/ToString entry names are absent from the fragment; this lexical observation is composed with manual reads of actual helper bodies, not a general purity proof.',
 'controls':{'count':len(names),'names':names,'filter':build['target']['filter'],'no_non_std_zig_imports':True,
 'stack_limit_successor_is_single_exact_change':True,'actual_execution_metadata_count':None},
 'build_one_insertion_forward_inverse_exact':True,'build_install_only_no_new_run_step':True,
 'pins':pins}
out=O/'source-audit.json';assert not out.exists()
b=(json.dumps(result,indent=2)+'\n').encode();out.write_bytes(b)
print(json.dumps({'path':str(out),'bytes':len(b),'sha256':h(b),'edits':len(steps),'controls':len(names),'pins':len(pins)},indent=2))
