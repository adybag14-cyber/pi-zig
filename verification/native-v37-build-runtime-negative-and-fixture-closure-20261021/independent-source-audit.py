"""Independent bounded V37 fixture source audit. Only byte/source reads and read-only Git; own create-only JSON output."""
from pathlib import Path
import hashlib,json,re,subprocess,os,struct
B=Path(r'C:\Users\adyba\pi-zig')
MAIN=B/'main'
OWN=B/'worktrees/modules-io-resume-20261018/verification/v37-file-handle-runtime-fixtures-peer-20261021'
SDK=B/'worktrees/sdk-owners-resume-20261018/verification/v37-file-handle-runtime-fixtures-sourceonly-20261021'
HEAD='b13be24e44cc1bbc361639eb35900a368ae60eac'
PROPOSAL={'path':str(SDK/'proposal.json'),'bytes':21669,'sha256':'2933A7AB4CCC196984FC27419B3E4A64DCCEB99B0834734AA7B357EE1280C7FC'}
MANUAL_PINS=[{"path":"C:\\Users\\adyba\\pi-zig\\main\\src\\extensions\\native_sdk_owned_completion.zig","bytes":15176,"sha256":"BED505F14A7E0E0792802DA8EB915404C2E7AAFC77D8274108A6B916A8C0E6CC"},{"path":"C:\\Users\\adyba\\pi-zig\\main\\vendor\\node-v24.13.0\\uv\\src\\win\\fs-fd-hash-inl.h","bytes":6886,"sha256":"1365F18D01C4117B0F42CFB2E0065F37AD62E4F5214B150CBF660F986955BB2D"}]
AUTHORITY_INPUTS_PIN={"path":"C:\\Users\\adyba\\pi-zig\\worktrees\\sdk-owners-resume-20261018\\verification\\v37-file-handle-runtime-fixtures-sourceonly-20261021\\authority-inputs-v2.json","bytes":16810,"sha256":"B97468E1DD34137C80A6199BABE6E227FEBDB5BD3FD0654B31EA3F05CF8C123F"}
seen={}
def sha(b): return hashlib.sha256(b).hexdigest().upper()
def record(p,b=None):
 p=Path(p);b=p.read_bytes() if b is None else b
 return {'path':str(p),'bytes':len(b),'sha256':sha(b)}
def check(row):
 p=Path(row['path']);b=p.read_bytes()
 assert len(b)==row['bytes'] and sha(b)==row['sha256'].upper(),str(p)
 out=record(p,b);old=seen.get(str(p).casefold())
 assert old is None or old==out,str(p)
 seen[str(p).casefold()]=out
 return b
def pin_tree(x):
 if isinstance(x,dict):
  if all(k in x for k in ('path','bytes','sha256')):check(x)
  for v in x.values():pin_tree(v)
 elif isinstance(x,list):
  for v in x:pin_tree(v)
def git(*args):
 env=dict(os.environ);env['GIT_OPTIONAL_LOCKS']='0'
 return subprocess.check_output(['git','-C',str(MAIN),*args],env=env)
assert git('rev-parse','HEAD').decode().strip()==HEAD
assert git('status','--porcelain=v1','--untracked-files=all')==b''
p=json.loads(check(PROPOSAL))
assert p['main_basis']==HEAD and p['finite_edits']==8
assert p['declared_controls']==58 and p['actual_metadata_prediction'] is None
assert all(p[k] is False for k in ('native_execution','compiler_execution','Main_written','candidate_execution'))
assert [x['relative_path']for x in p['files']]==['src/native_node_file_handle_owner_test.zig','src/native_node_file_handle_owner_test_support.zig']
pin_tree(p)
for row in MANUAL_PINS:check(row)
auth=json.loads(check(AUTHORITY_INPUTS_PIN));pin_tree(auth)
authority_original_pin={'path':str(SDK/'authority-inputs.json'),'bytes':16810,'sha256':'940ED7F295FDE2A6D4F2F7770B7041E15F810B2A3D6C8FF8CCA8B5079A1B7727'}
old_authority=check(authority_original_pin);new_authority=check(AUTHORITY_INPUTS_PIN)
old_range=b'"first_line": 84,\n          "last_line": 96,'
new_range=b'"first_line": 74,\n          "last_line": 97,'
assert old_authority.count(old_range)==1 and new_authority.count(new_range)==1
assert old_authority.replace(old_range,new_range,1)==new_authority
assert new_authority.replace(new_range,old_range,1)==old_authority
snapshot_rows=[]
for row in auth['sources']:
 if row.get('snapshot'):
  snap=SDK/'authority'/row['snapshot'];raw=check(row)
  selected={'path':str(snap),'bytes':row['bytes'],'sha256':row['sha256']}
  assert check(selected)==raw
  snapshot_rows.append({'original':record(row['path'],raw),'contained':selected})
assert len(snapshot_rows)==3
node_rows=[r for r in auth['sources']if r['key']=='node_authority']
assert len(node_rows)==1
acquisition=json.loads(check(node_rows[0]))
assert any(x.get('url')=='https://raw.githubusercontent.com/nodejs/node/v24.13.0/src/env.cc' and x.get('body_sha256','').upper()=='081F46DB425F5FEA9095F68E25D6C9BC89CF16BB800872A65A3D04C62FEDB4A9' and x.get('decoded_bytes')==84987 and x.get('status')=='ok' for x in acquisition['data']['documents'])
edits=[];source_results=[]
name_rx=rb'(?m)^test\s+"([^"]+)"'
import_rx=rb'@(import|cInclude)\("([^"]+)"\)'
def names(b): return [x.decode() for x in re.findall(name_rx,b)]
def imports(b):return [[a.decode(),z.decode()] for a,z in re.findall(import_rx,b)]
for entry in p['files']:
 old=check(entry['original']);new=check(entry['candidate']);cur=check(entry['current'])
 assert old==cur==git('show',HEAD+':'+entry['relative_path'])
 x=old;per=[]
 for e in entry['edits']:
  before=e['old'].encode();after=e['new'].encode();off=e['offset']
  assert sha(x)==e['before_sha256'] and x.count(before)==1 and x.find(before)==off,e['id']
  x=x[:off]+after+x[off+len(before):]
  assert sha(x)==e['after_sha256'],e['id']
  per.append({'id':e['id'],'offset':off,'before_sha256':e['before_sha256'],'after_sha256':sha(x),'before_bytes':len(before),'after_bytes':len(after)})
 assert x==new
 for e in reversed(entry['edits']):
  before=e['old'].encode();after=e['new'].encode();off=e['offset']
  assert sha(x)==e['after_sha256'] and x[off:off+len(after)]==after,e['id']
  x=x[:off]+before+x[off+len(after):]
  assert sha(x)==e['before_sha256'],e['id']
 assert x==old
 assert names(old)==names(new)==entry['named_controls_exact']
 assert imports(old)==imports(new)==entry['imports_exact']
 # The changed descriptor expectation is intentional; all other assert lines remain exact.
 old_assert=[z for z in old.splitlines() if b'std.testing.expect' in z]
 new_assert=[z for z in new.splitlines() if b'std.testing.expect' in z]
 assert old_assert==new_assert
 source_results.append({'relative_path':entry['relative_path'],'original':entry['original'],'candidate':entry['candidate'],'current_and_raw_git_equal':True,'whole_forward_and_inverse_exact':True,'named_controls':names(new),'imports':imports(new),'std_testing_expect_lines_exact':len(old_assert),'edits':per})
 edits.extend(per)
assert len(edits)==8
cohort=[]
for row in p['cohort']:
 raw=check(row['source']);filename=Path(row['source']['path']).stem
 named=[filename+'.test.'+n for n in names(raw)]
 assert named==row['named']
 imp=[z[1] for z in imports(raw) if z[0]=='import']
 assert imp==row['imports']
 if filename=='native_node_file_handle_owner_test':
  candidate=check(p['files'][0]['candidate'])
  assert names(candidate)==names(raw)
 cohort.append({'name':row['name'],'source':row['source'],'declarations':len(named),'names':named,'imports':imp})
assert [r['declarations']for r in cohort]==[18,3,24,13]
assert sum(r['declarations']for r in cohort)==58
# Independently bind the critical unchanged functions and local failure cleanup.
support_old=check(p['files'][1]['original']);support_new=check(p['files'][1]['candidate'])
def between(b,a,z):return b.split(a,1)[1].split(z,1)[0]
finish=between(support_old,b'fn finishImmediate(',b'fn caughtImmediate(')
assert finish==between(support_new,b'fn finishImmediate(',b'fn caughtImmediate(')
err=between(support_old,b'    errdefer {\n        if (frame.scope.initialized)',b'    try frame.scope.init')
new_err=between(support_new,b'    errdefer {\n        if (frame.scope.initialized)',b'    const resource =')
assert err==new_err
assert b'return a.duplicate(s.engine, try s.object());' in support_new
assert b'const resource = if (f.env().canCallIntoJs())\n        try a.expression(engine, immediateResource, .{}) else c.pi_js_undefined();\n    defer engine.freeValue(resource);\n    try frame.scope.init(f.env(), resource,' in support_new
root=check(p['files'][0]['candidate'])
assert b'const invalid_descriptor: c_int = std.math.maxInt(c_int);' in root
assert b"'EBADF: Closing file descriptor 2147483647 on garbage collection failed, close'" in root
# Preserve actual original negative artifacts; no replay, source result or future acceptance is inferred.
negative_base=B/'evidence/root-native-foundation-v37-new4-runtime-20261021-132912'
negative_rows=[
{'path':str(negative_base/'result.json'),'bytes':16657,'sha256':'66E9CE52981B6DA16C7A1F79EE596FA98754E5F69E435FDF0A36EB3AB8139165'},
{'path':str(negative_base/'groups/native-node-file-handle-owner/runtime.stdout.bin'),'bytes':546,'sha256':'28AC47910B5D5309DD1A1454816A2C051A0E420C51BD0827D4EC61F5D5528C9E'},
{'path':str(negative_base/'groups/native-node-file-handle-owner/runtime.stderr.log'),'bytes':68389,'sha256':'1BB42117F374DECBF5C91100686DF7DA7D686A285ECF9F874423D5799AF945ED'}]
for row in negative_rows:check(row)
# Read only the previously accepted PE artifact, never invoke it.
exe=B/'evidence/root-native-foundation-fresh-v37-new4-buildquery-20261021-131435/cache/o/c4d8e30b697e1e299b33fef4aed6127d/test.exe'
raw=check({'path':str(exe),'bytes':49019392,'sha256':'BF100B0B3CFB386757E0415DAFC8A7BEFF430ED96166AD5AA06E9129E0F8DB7F'})
u16=lambda p:struct.unpack_from('<H',raw,p)[0]
u32=lambda p:struct.unpack_from('<I',raw,p)[0]
u64=lambda p:struct.unpack_from('<Q',raw,p)[0]
pe=u32(0x3c);assert raw[pe:pe+4]==b'PE\0\0' and u16(pe+4)==0x8664
n=u16(pe+6);opt=pe+24;osz=u16(pe+20);assert u16(opt)==0x20b
sections=[]
for i in range(n):
 s=opt+osz+i*40;vs,va,rs,r=struct.unpack_from('<IIII',raw,s+8);sections.append((va,max(vs,rs),r,rs))
def off(rva):
 for va,sz,r,rs in sections:
  if va<=rva<va+sz:
   assert rva-va<rs
   return r+rva-va
 raise AssertionError(rva)
def zstr(o):return raw[o:raw.index(b'\0',o)].decode('ascii')
d=off(u32(opt+120));dlls=[]
while any(raw[d:d+20]):
 oft,stamp,forward,name,ft=struct.unpack_from('<IIIII',raw,d)
 t=off(oft or ft);syms=[]
 while u64(t):
  v=u64(t);syms.append({'ordinal':v&65535} if v>>63 else {'name':zstr(off(v)+2)});t+=8
 dlls.append({'dll':zstr(off(name)),'symbols':syms});d+=20
inventory_sha=sha(json.dumps(dlls,sort_keys=True,separators=(',',':')).encode())
assert inventory_sha=='FB62DE635650479F63C2DCDB8F9C5A24C9E610C59626EECFD699AC42C9F47A57'
imports_map={s['name']:d['dll'] for d in dlls for s in d['symbols'] if 'name'in s}
assert imports_map['_close']=='api-ms-win-crt-stdio-l1-1-0.dll'
assert imports_map['_set_invalid_parameter_handler']=='api-ms-win-crt-runtime-l1-1-0.dll'
assert '_set_thread_local_invalid_parameter_handler' not in imports_map
# Pin exact lines independently read for the source causal/ownership result.
range_specs=[]
for row in auth['sources']:
 selected=SDK/'authority'/row['snapshot'] if row.get('snapshot') else Path(row['path'])
 range_specs.append((str(selected),[(r['first_line'],r['last_line'])for r in row['ranges']]))
range_specs.extend([["C:\\Users\\adyba\\pi-zig\\main\\src\\extensions\\native_node_commonjs_owned_boundary.zig",[[122,163]]],["C:\\Users\\adyba\\pi-zig\\main\\src\\extensions\\native_sdk_owned_completion.zig",[[162,169],[215,227]]],["C:\\Users\\adyba\\pi-zig\\main\\src\\extensions\\native_node_callback_scope.zig",[[699,732]]],["C:\\Users\\adyba\\pi-zig\\main\\vendor\\node-v24.13.0\\uv\\src\\win\\fs-fd-hash-inl.h",[[93,120],[167,194]]],["C:\\Users\\adyba\\pi-zig\\main\\src\\extensions\\native_uv_tcp.c",[[927,939]]]])
ranges=[]
for path,rs in range_specs:
 path=Path(path);b=path.read_bytes();ls=b.splitlines(keepends=True)
 for first,last in rs:
  value=b''.join(ls[first-1:last]);assert value
  ranges.append({'path':str(path),'file_sha256':sha(b),'first_line':first,'last_line':last,'bytes':len(value),'sha256':sha(value),'text':value.decode()})
# The complete source/receipt input set is re-read; no included Python is imported/executed.
for row in list(seen.values()):check(row)
assert git('rev-parse','HEAD').decode().strip()==HEAD
assert git('status','--porcelain=v1','--untracked-files=all')==b''
proof={'schema':1,'status':'passed_bounded_static_fixture_source_checks','candidate_proposal':PROPOSAL,'authority_inputs':AUTHORITY_INPUTS_PIN,'authority_original':authority_original_pin,'authority_range_single_edit_inverse_exact':True,'contained_SDK_snapshots':snapshot_rows,'main_head':HEAD,'main_clean_before_and_after':True,'exact_files':2,'exact_edits':8,'source_files':source_results,'cohort':cohort,'declared_controls':58,'future_actual_metadata':None,'finishImmediate_byte_sha256':sha(finish),'existing_init_errdefer_byte_sha256':sha(err),'original_negative_artifacts':negative_rows,'pe_imports':{'artifact':record(exe,raw),'full_import_inventory_sha256':inventory_sha,'selected':{k:imports_map[k]for k in ['_close','_set_invalid_parameter_handler']},'thread_local_handler_import_present':False,'binary_executed':False},'source_ranges':ranges,'inputs':sorted(seen.values(),key=lambda r:r['path'].casefold()),'all_inputs_rehashed_at_end':True,'source_only':True,'candidate_executed':False,'target_prefix_or_helper_executed':False,'native_execution':False,'compiler_execution':False,'Main_written':False,'application_qualified':False}
out=json.dumps(proof,indent=2,ensure_ascii=False).encode()+b'\n'
OWN.mkdir(parents=True,exist_ok=True)
with (OWN/'source-audit.json').open('xb') as f:f.write(out)
print(json.dumps({'path':str(OWN/'source-audit.json'),'bytes':len(out),'sha256':sha(out),'inputs':len(seen),'edits':8,'declarations':58,'ranges':len(ranges),'main_clean':True}))
