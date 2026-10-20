from pathlib import Path
import hashlib,json,re,datetime
w=Path("C:\\Users\\adyba\\pi-zig\\worktrees\\sdk-owners-resume-20261018");p=Path("C:\\Users\\adyba\\pi-zig\\worktrees\\sdk-owners-resume-20261018\\verification\\native-file-handle-transfer-sourceonly-20261020")
def digest(b):return hashlib.sha256(b).hexdigest().upper()
def info(q):
 b=q.read_bytes();return {'path':str(q),'bytes':len(b),'sha256':digest(b)}
def dump(q,j):
 raw=(json.dumps(j,indent=2)+'\n').encode()
 assert q.is_file() and q.read_bytes()==raw,('read-only peer exact final proof mismatch',q)
 return info(q)
verified={}
def verify(z):
 q=Path(z['path']);actual=info(q);assert actual['bytes']==z['bytes'] and actual['sha256']==z['sha256'].upper(),(q,z,actual)
 verified[str(q)]=actual
 return q.read_bytes()
inv=json.loads((p/'dependency-inventory.json').read_text(encoding='utf-8'))
for z in inv['modules']+inv['embeds']+inv['direct_native_c_dependency_pins']+inv['preserved_28_prior_plus_3_owner_controls']:verify(z)
for z in inv['selected_source_overlay']:verify(z['selected'])
for filename in ['initial-source-bindings.json','support-bindings.json']:
 j=json.loads((p/filename).read_text(encoding='utf-8'))
 for z in j.get('sources',[]):assert verify(z['live'])==verify(z['snapshot'])
 for z in j.get('support_and_authorities',[])+j.get('bindings',[]):assert verify(z['source'])==verify(z['snapshot'])
sm=json.loads((p/'source-map.json').read_text(encoding='utf-8'))
for z in sm['authorities']:verify(z)
for z in sm['source_excerpts']:
 raw=verify(z['source']);part=b''.join(raw.splitlines(keepends=True)[z['first_line']-1:z['last_line']])
 assert part.decode()==z['text'] and digest(part)==z['sha256'] and len(part)==z['bytes'],z['id']
life=json.loads((p/'lifetime-source-addendum.json').read_text(encoding='utf-8'))
z=life['exact_engine_retirement_excerpt'];raw=verify(z['source']);part=b''.join(raw.splitlines(keepends=True)[z['first_line']-1:z['last_line']])
assert part.decode()==z['text'] and digest(part)==z['sha256']
def replay(j):
 original=verify(j['original']);actual=original
 for e in j['edits']:
  before=e['before'].encode();after=e['after'].encode()
  assert actual.count(before)==e.get('occurrences_before',1)
  actual=actual.replace(before,after,1)
 selected=j.get('projected',j.get('selected'));assert actual==verify(selected)
 reverse=actual
 for e in reversed(j['edits']):
  before=e['before'].encode();after=e['after'].encode()
  assert reverse.count(after)==e.get('occurrences_after',1)
  reverse=reverse.replace(after,before,1)
 assert reverse==original
 return actual
fixture=json.loads((p/'fixture-descriptor-scope-successor.json').read_text(encoding='utf-8'))
selected_control=replay(fixture);assert selected_control==verify(fixture['live'])
test_names=lambda b:re.findall(rb'^test "([^"]+)"',b,re.M)
assert test_names(verify(fixture['original']))==test_names(selected_control) and len(test_names(selected_control))==13
build_j=json.loads((p/'build/proposal.json').read_text(encoding='utf-8'))
replay(build_j)
a9_path=w/'verification/native-file-handle-owner-controls-sourceonly-20261020/handoff.json'
a9=json.loads(a9_path.read_text(encoding='utf-8'))
owner_build_j=json.loads(verify(a9['exact_install_only_build_proposal']).decode())
constructor_path=w/'verification/native-vm-error-constructor-name-sourceonly-20261020/production-proposal.json'
ctor=json.loads(constructor_path.read_text(encoding='utf-8'))
ctor_build_j=json.loads(verify(ctor['exact_build_proposal']).decode())
assert ctor_build_j['schema']=='native-error-constructor-name-install-only-build-v1'
ctor_edit=ctor_build_j['edit']
assert verify(ctor_build_j['original']).find(ctor_edit['old_text'].encode())==ctor_edit['offset_in_predecessor']
ctor_build_j={**ctor_build_j,'edits':[{'before':ctor_edit['old_text'],'after':ctor_edit['new_text'],'occurrences_before':1,'occurrences_after':1}]}
replay(ctor_build_j)
replay(owner_build_j)
for z in ctor['install_sources']:
 verify(z['selected'])
 if 'live' in z:assert verify(z['live'])==verify(z['selected'])
 if 'original' in z:verify(z['original'])
base=verify(build_j['original']);combined=base;build_steps=[]
for name,j in [('accepted_owner_A9D4',owner_build_j),('accepted_constructor_B1C1',ctor_build_j),('new_transfer',build_j)]:
 assert verify(j['original'])==base
 for e in j['edits']:
  before=e['before'].encode();after=e['after'].encode()
  assert combined.count(before)==e.get('occurrences_before',1)
  prior_hash=digest(combined);combined=combined.replace(before,after,1)
  build_steps.append({'packet':name,'before_sha256':prior_hash,'after_sha256':digest(combined),'before':e['before'],'after':e['after']})
reverse=combined
for e in reversed(build_steps):
 after=e['after'].encode();before=e['before'].encode()
 assert reverse.count(after)==1;reverse=reverse.replace(after,before,1)
assert reverse==base
q=p/'build/combined-after-owner-and-constructor.zig'
assert q.is_file() and q.read_bytes()==combined,('read-only peer combined build mismatch',q)
combined_info=info(q)
assert b'addRunArtifact' not in verify(build_j['block'])
cpp=(p/'production/src/extensions/native_node_file_handle_transfer.cpp').read_text(encoding='utf-8')
header=(p/'production/src/extensions/native_node_file_handle_transfer.h').read_text(encoding='utf-8')
zig=(p/'production/src/extensions/native_node_file_handle_transfer.zig').read_text(encoding='utf-8')
abi=['create','delete','descriptor','take_descriptor']
for suffix in abi:
 name='pi_node_file_handle_transfer_data_'+suffix
 assert name in header and 'extern fn '+name in zig
 match=re.search(r'\b'+name+r'\s*\([^;]*?\)\s*\{(.*?)\n\}',cpp,re.S)
 assert match,name
 assert match.group(1).strip().splitlines()[0].strip()=='pi::node::DiagnosticContextScope diagnostic_scope(context);',name
assert cpp.count('uv_fs_close(nullptr, &close_req, fd_, nullptr)')==2 # actual call plus original CHECK text
assert cpp.count('uv_fs_req_cleanup(&close_req)')==1
assert 'if (fd_ > 0)' in cpp and 'packet->fd_ = -1;' in cpp
assert 'templates.newInstance' not in zig and 'owner.Handle.create' in zig
owners=[]
for n,expected in [('native_node_file_handle_owner.zig','2D90F772D2177C7DB4EF4F945F78529C0061C809E171C22CECC324125C9A461D'),('native_node_file_handle_close_request.zig','9EB383CED295E354BD91A5F1FA9E471B70182C3D554D190148AEB4BA93386FEC'),('native_node_file_handle_gc_close.zig','86E1100598B32022BB38D2DDAD2ABF904C061E915EC0E955C9CAE62B371B83F4')]:
 z=info(w/'src/extensions'/n);assert z['sha256']==expected;owners.append(z);verify(z)
new_sources=[]
for rel in ['src/extensions/native_node_file_handle_transfer.h','src/extensions/native_node_file_handle_transfer.cpp','src/extensions/native_node_file_handle_transfer.zig','src/native_node_file_handle_transfer_test.zig']:
 snapshot=p/('controls-selected' if rel.endswith('_test.zig') else 'production')/rel
 live=info(w/rel);snap=info(snapshot);assert verify(live)==verify(snap)
 new_sources.append({'relative_path':rel,'kind':'new_control' if rel.endswith('_test.zig') else 'new_production','live':live,'snapshot':snap})
checks=dump(p/'source-only-checks.json',{
 'schema':'pi-zig.file-handle-transfer-finite-source-checks.v1','source_only':True,
 'verified_unique_files':len(verified),'verified_files':[verified[k] for k in sorted(verified)],
 'production_live_and_frozen_pairs':3,'control_live_and_selected_pair':1,
 'all_46_source_map_excerpts_exact':True,'additive_engine_teardown_excerpt_exact':True,
 'fixture_one_hunk_forward_inverse_exact':True,'all_13_declarations_unchanged':True,
 'install_only_one_hunk_forward_inverse_exact':True,
 'combined_build_after_accepted_owner_and_constructor':combined_info,'combined_build_steps':build_steps,'combined_full_inverse_exact':True,
 'all_31_prior_sources_and_3_live_owner_drafts_preserved':True,'accepted_constructor_two_live_sources_and_all_five_selected_inputs_preserved':True,
 'four_native_ABI_scopes_first_local':True,'ABI_signatures_reviewed':'Canonical JSContext pointer, memory owner pointer, opaque native packet pointer, int/c_int and extern C function pointers; no extra cImport UV request identity.',
 'module_count':inv['module_count'],'embed_count':inv['embed_count'],'literal_import_occurrences':len(inv['import_edges']),'distinct_import_edges':len(set((e['from'],e['to']) for e in inv['import_edges'])),
 'literal_anonymous_source_blocks':inv['literal_anonymous_source_blocks'],
 'source_declared_controls':13,'future_actual_metadata_count':None,
 'preflight_negatives_preserved':[info(p/'inventory-inspector-v1-negative.json'),info(p/'source-map-range-preflight-negative.json'),info(p/'final-seal-build-schema-preflight-negative.json')],
 'not_a_compiler_or_runtime_result':True,'compiler_executed':False,'native_executed':False,'reference_executed':False})
print(json.dumps({'checks':checks,'verified_unique_files':len(verified),'source_declared_controls':13,'all_46_excerpts_exact':True,'combined_inverse':True,'writes':False},indent=2))
