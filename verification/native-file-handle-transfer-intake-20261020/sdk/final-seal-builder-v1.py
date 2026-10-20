from pathlib import Path
import hashlib,json,re,datetime
w=Path("C:\\Users\\adyba\\pi-zig\\worktrees\\sdk-owners-resume-20261018");p=Path("C:\\Users\\adyba\\pi-zig\\worktrees\\sdk-owners-resume-20261018\\verification\\native-file-handle-transfer-sourceonly-20261020")
def digest(b):return hashlib.sha256(b).hexdigest().upper()
def info(q):
 b=q.read_bytes();return {'path':str(q),'bytes':len(b),'sha256':digest(b)}
def dump(q,j):
 raw=(json.dumps(j,indent=2)+'\n').encode();q.parent.mkdir(parents=True,exist_ok=True)
 with q.open('xb') as f:f.write(raw)
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
with q.open('xb') as f:f.write(combined)
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
 'preflight_negatives_preserved':[info(p/'inventory-inspector-v1-negative.json'),info(p/'source-map-range-preflight-negative.json')],
 'not_a_compiler_or_runtime_result':True,'compiler_executed':False,'native_executed':False,'reference_executed':False})
manifest={
 'schema':'pi-zig.file-handle-transfer-production-source-proposal.v1',
 'created_utc':datetime.datetime.now(datetime.timezone.utc).isoformat(),
 'comparison_main_head':inv['comparison_main_head'],
 'qualification':'Finite new native FileHandle descriptor transfer source and thirteen unexecuted controls, ready for independent source review. No full FileHandle, worker broker, compiler or runtime acceptance.',
 'selected_new_sources':new_sources,'new_production_paths':3,'new_control_paths':1,'existing_source_paths_modified':0,'shared_State_Handle_Registry_template_edits':0,
 'source_map':info(p/'source-map.json'),'additive_post_engine_lifetime_source':info(p/'lifetime-source-addendum.json'),
 'dependency_inventory':info(p/'dependency-inventory.json'),'source_only_checks':checks,
 'exact_install_only_build_proposal':info(p/'build/proposal.json'),
 'build_integration':'One new install-only block in build.zig. The artifact directly compiles this production C++ owner and the existing diagnostic C TLS owner, then links the existing genuine QuickJS/network/native-memory graph. No production tracing or worker bootstrap is installed.',
 'required_accepted_owner_source_cohort':info(a9_path),
 'owner_dependency_packets':a9['dependencies'],
 'not_required_but_composition_checked_constructor_packet':info(constructor_path),
 'controls':{'root':'src/native_node_file_handle_transfer_test.zig','filter':'native FileHandle transfer','install_step':'build-native-node-file-handle-transfer','artifact_basename':'native-node-file-handle-transfer','source_declared_names':inv['named_declarations'],'source_declared_count':13,'repository_literal_anonymous_blocks':inv['literal_anonymous_source_blocks'],'future_actual_metadata_count':None,'whole_future_cohort_selected':False},
 'production_admission_and_ownership':[
  'getTransferMode reads the same actual reading/closing/closed members; successful transfer only sets closed after native allocation.',
  'The packet owns a native fd and independently charged prefix. No Engine, JSValue, Environment, Controller, loop or lease is retained.',
  'Native destructor preserves fd>0, actual canonical stack uv_fs_t, NULL loop/callback, both original CHECKs, global trace boundaries and cleanup.',
  'Receiver consumes the unique packet, checks actual BindingData, writes fd=-1 before real absent-object Handle.create and strengthens the actual receiver State only after construction.',
  'StrongHandle retains/releases the existing same-thread State and real persistent. Only the native descriptor packet may cross threads.'
 ],
 'host_preconditions_and_supported_boundaries':[
  'Caller Scope and sender/receiver registry must refer to the same live Engine for their synchronous operation. Environment-mismatch checks are host API preconditions, not additions to original transfer eligibility policy.',
  'Supplied context is borrowed and must remain live for that call; NULL is required after Engine retirement.',
  'Owned is move-only by caller discipline. StrongHandle is receiver-thread-only, matching original non-thread-safe BaseObjectPtr.',
  'Missing complete template is an explicit host dependency error. The preserved take-before-New order does not assert that original Node always fails receiver construction.'
 ],
 'known_open_production_dependencies':sm['explicit_open_dependencies'],
 'important_control_limits':[
  'Trace callbacks are named TEST observations of real fd and diagnostic state; they do not substitute for actual global production tracing.',
  'The fixture uses the reviewed present-object constructor; successful deserialization is not claimed while full template is absent.',
  'Physical close controls select fd>2. Original fd0 strict-gate and Windows stdio behavior remain source-mapped, unaltered and not dynamically exercised.',
  'The original disallow-transfer and failed-native-close fatal CHECKs remain unchanged; this packet does not execute their terminal paths.',
  'No serialization format, worker transfer-list admission, MemoryRetainer virtual assembly or complete production bootstrap is supplied.'
 ],
 'retained_control_predecessor':info(p/'controls/src/native_node_file_handle_transfer_test.zig'),
 'finite_fixture_scope_successor':info(p/'fixture-descriptor-scope-successor.json'),
 'preservation':{'all_28_prior_sources_plus_3_owner_controls':True,'three_existing_live_owner_files':owners,'accepted_constructor_live_and_selected_sources':True,'initial_transfer_production_snapshots_unchanged':True,'initial_control_E707_preserved':True,'main_modified':False},
 'compiler_executed':False,'native_executed':False,'reference_executed':False,'test_executed':False,'runtime_accepted':False}
proposal=dump(p/'production-proposal.json',manifest)
print(json.dumps({'proposal':proposal,'checks':checks,'new_sources':[(x['relative_path'],x['snapshot']['sha256']) for x in new_sources],'verified_unique_files':len(verified),'source_controls':13,'source_roots':1,'modules':inv['module_count'],'embeds':inv['embed_count'],'build':info(p/'build/proposal.json')},indent=2))
