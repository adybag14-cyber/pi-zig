from pathlib import Path
import hashlib,json,re
P=Path(r'C:\Users\adyba\pi-zig\worktrees\sdk-owners-resume-20261018\verification\native-vm-error-constructor-name-sourceonly-20261020')
O=Path(r'C:\Users\adyba\pi-zig\worktrees\modules-io-resume-20261018\verification\native-vm-error-constructor-name-source-peer-20261020')
def digest(b): return hashlib.sha256(b).hexdigest().upper()
def readj(p): return json.loads(Path(p).read_bytes())
pins={}
def verify(r):
 p=Path(r['path'])
 assert p.is_absolute(),str(p)
 b=p.read_bytes()
 assert len(b)==r['bytes'],str(p)
 assert digest(b)==r['sha256'].upper(),str(p)
 rec={'path':str(p),'bytes':len(b),'sha256':digest(b)}
 if str(p) in pins: assert pins[str(p)]==rec
 pins[str(p)]=rec
 return b
def pin(p):
 b=Path(p).read_bytes()
 return {'path':str(p),'bytes':len(b),'sha256':digest(b)}
expected={
 'production-proposal.json':(14336,'B1C179FE0FE38E0F6FC1FB1BF351FE62ED4D85E90FBEED1DDDF995C1345E863C'),
 'source-map.json':(168366,'472E2044C5C441563124CC53A1AAAE2394A5E75A9D53577B453F5F795333BC54'),
 'closure-and-preservation.json':(45378,'DBF5C664507C2BBB12157CDD6B73A2C0AA125C40B7AF6C752E18C5E97C76727B'),
}
docs={}
for name,(size,h) in expected.items():
 docs[name]=json.loads(verify({'path':str(P/name),'bytes':size,'sha256':h}))
manifest=docs['production-proposal.json']; source=docs['source-map.json']; closure=docs['closure-and-preservation.json']
oldaudit=readj(O/'source-audit.json')
assert digest((O/'source-audit.json').read_bytes())=='B1253548E211E8E7BCE2484A39C70819471D6F6DB4D64D1672F2A2471C1D4817'
assert manifest['basis_main_head']==closure['basis_main_head']==source['basis_main_head']==oldaudit['basis_main_head']=='c764130caf2f2c7c63728bec0f6d1e16ac5c59a4'
# Every nested absolute file/length/hash record is checked; explicit paired-source
# schemas that do not use a path key are checked separately below.
def walk(v):
 if isinstance(v,dict):
  if all(k in v for k in ('path','bytes','sha256')) and Path(v['path']).is_absolute(): verify(v)
  for item in v.values(): walk(item)
 elif isinstance(v,list):
  for item in v: walk(item)
for d in docs.values(): walk(d)
for r in oldaudit['pins']: verify(r)
assert len(oldaudit['pins'])==37
for r in closure['existing_support_unchanged']:
 for k in ['source','snapshot']: verify({'path':r[k],'bytes':r['bytes'],'sha256':r['sha256']})
for r in closure['prior_28_sources_unchanged']:
 verify(r)
 if 'snapshot' in r: verify({'path':r['snapshot'],'bytes':r['bytes'],'sha256':r['sha256']})
assert len(closure['prior_28_sources_unchanged'])==28
assert len(closure['prior_3_owner_controls_support_unchanged'])==3
assert len(closure['prior_packets_unchanged'])==6
assert closure['direct_existing_packet_snapshot_pin_count']==len(closure['direct_existing_packet_snapshots'])==79
# Source identity and exact full-line excerpts: decoded UTF-8 splitlines, join LF,
# append one LF; no whitespace trimming or body normalization.
files={a['id']:a for a in source['authorities']}
assert len(files)==len(source['authorities'])==14
files.update(source['host_files'])
assert len(source['host_files'])==9
for a in source['authorities']: assert len(verify(a).decode('utf-8').splitlines())==a['line_count']
refs={}
excerpt_results=[]
for ref in source['references']:
 assert ref['id'] not in refs
 refs[ref['id']]=ref
 expected_file=files[ref['file_id']]
 assert all(ref['file'][k]==expected_file[k] for k in ['path','bytes','sha256'])
 lines=verify(ref['file']).decode('utf-8').splitlines()
 lo,hi=ref['start_line'],ref['end_line']
 assert 1<=lo<=hi<=len(lines)
 excerpt='\n'.join(lines[lo-1:hi])+'\n'
 assert excerpt==ref['excerpt'],ref['id']
 assert digest(excerpt.encode('utf-8'))==ref['excerpt_sha256'],ref['id']
 excerpt_results.append({'id':ref['id'],'file_id':ref['file_id'],'start_line':lo,'end_line':hi,'excerpt_sha256':ref['excerpt_sha256']})
assert len(refs)==76
for row in source['mapping']:
 for k in ['original_source','host_source']:
  assert all(name in refs for name in row[k]),row['subject']
 assert all(isinstance(n,int) and 1<=n<=24 for n in row['control_numbers'])
assert len(source['mapping'])==16
# Exact constructor authorities are either byte-for-byte contained-source copies
# or successful native transport records whose raw body SHA equals the full file.
authority_bindings=[json.loads(verify(p)) for p in manifest['authority_bindings']]
bindings={}
for r in authority_bindings[0]:
 for k in ['source','snapshot']: verify({'path':r[k],'bytes':r['bytes'],'sha256':r['sha256']})
 bindings[r['snapshot']]={'kind':'contained-source-copy','source':r['source'],'sha256':r['sha256']}
consumer=authority_bindings[1]
verify(consumer['source']);verify(consumer['snapshot'])
assert consumer['source']['sha256']==consumer['snapshot']['sha256']
bindings[consumer['snapshot']['path']]={'kind':'contained-source-copy','source':consumer['source']['path'],'sha256':consumer['source']['sha256']}
native_rows=[]
for doc in authority_bindings[2:]:
 assert doc['ok'] is True
 for row in doc['data']['documents']:
  assert row['status']=='ok' and row['http_status']==200
  native_rows.append(row)
authority_results=[]
for authority in source['authorities']:
 if authority['path'] in bindings:
  rec=bindings[authority['path']]
  assert rec['sha256']==authority['sha256']
  authority_results.append({'id':authority['id'],**rec})
 else:
  rows=[r for r in native_rows if r['url']==authority['url'] and r['body_sha256'].upper()==authority['sha256']]
  assert len(rows)==1,authority['id']
  authority_results.append({'id':authority['id'],'kind':'native-http-200-raw-body','url':authority['url'],'sha256':authority['sha256']})
assert sum(r['kind']=='contained-source-copy' for r in authority_results)==8
assert sum(r['kind']=='native-http-200-raw-body' for r in authority_results)==6
# Literal repository closure and declarations only; this does not predict the
# translated C/system headers, compiler-selected anonymous tests or runtime count.
control=verify(source['host_files']['control']).decode('utf-8')
names=re.findall(r'^\s*test\s+"([^"]+)"',control,re.M)
imports=re.findall(r'@import\("([^"]+)"\)',control)
c_names=re.findall(r'@cInclude\("([^"]+)"\)',control)
anon=re.findall(r'^\s*test\s*\{',control,re.M)
assert len(names)==len(set(names))==24 and imports==['std'] and c_names==['engine_abi.h'] and not anon
assert names==manifest['controls']['names']==closure['root_closure']['named_controls']==oldaudit['controls']['names']
assert source['control_numbering']==[{'number':i+1,'name':n} for i,n in enumerate(names)]
assert manifest['controls']['future_accepted_metadata_count'] is None
assert [r['path'] for r in manifest['install_sources']]==[
 'vendor/quickjs/quickjs.c','vendor/quickjs/quickjs.h','src/extensions/native_vm_error_constructor_name.c.inc','src/native_vm_error_constructor_name_test.zig','build.zig']
assert manifest['install_path_count']==5 and manifest['new_paths']==2 and manifest['existing_projected_paths']==3
assert manifest['vm_edits']==oldaudit['exact_edit_count']==closure['vm_edit_count']==22
assert manifest['build_edits']==1 and manifest['run_steps_added']==0
assert manifest['exact_vm_projection']['sha256']==oldaudit['subject_sha256']
assert oldaudit['all_originals_equal_pinned_git_commit'] and oldaudit['per_step_offsets_and_hashes_match'] and oldaudit['whole_forward_and_inverse_match']
out={
 'schema':'pi-zig.independent-native-error-constructor-final-binding-audit.v1',
 'source_only':True,'compiler_native_test_reference_execution':False,
 'subject':pin(P/'production-proposal.json'),
 'prior_source_audit':pin(O/'source-audit.json'),
 'prior_source_audit_inputs_rehashed':37,
 'final_subject_documents':[pin(P/n) for n in expected],
 'basis_main_head':manifest['basis_main_head'],
 'install_paths':[r['path'] for r in manifest['install_sources']],
 'exact_vm_edits_and_build_insertion_bound_to_prior_replay':True,
 'original_main_basis':'Pinned c764130c git blobs in prior independent replay; no claim about later Main state.',
 'authority_bindings':authority_results,
 'exact_source_excerpts':excerpt_results,
 'excerpt_recipe':'UTF-8 full file splitlines; select inclusive one-based bounds; LF join plus one LF; exact text and SHA comparison, no semantic normalization.',
 'all_16_mapping_reference_ids_and_control_numbers_valid':True,
 'controls':{'names':names,'declared_count':24,'literal_repository_modules':1,'literal_imports':imports,'literal_c_include_names':c_names,'literal_anonymous_blocks':0,'future_actual_metadata_count':None},
 'preservation':{'prior_sources':28,'prior_owner_controls_and_support':3,'prior_packets':6,'direct_prior_snapshot_records':79,'support_pairs':2,'all_declared_pairs_rehashed_equal':True},
 'native_acquisition_limit':'Eight reused authority pairs were independently byte-bound to contained originals. Their earlier HTTP provenance is inherited, not reacquired here. Six newly selected authorities match successful native transport raw body SHA.',
 'unique_file_pins':len(pins),'pins':list(pins.values()),
 'no_production_or_main_edit':True,
}
target=O/'final-binding-audit.json'
assert not target.exists()
with target.open('x',encoding='utf-8',newline='\n') as f: json.dump(out,f,ensure_ascii=False,indent=2);f.write('\n')
print(json.dumps({'result':pin(target),'unique_file_pins':len(pins),'authorities':14,'excerpts':76,'controls':24,'preservation':'all selected hashes matched'}))
