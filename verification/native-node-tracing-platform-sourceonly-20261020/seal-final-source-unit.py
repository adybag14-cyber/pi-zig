from pathlib import Path
import datetime,hashlib,json,subprocess
own=Path(r'C:\Users\adyba\pi-zig\worktrees\modules-io-resume-20261018')
p=own/'verification/native-node-tracing-platform-sourceonly-20261020'
def sha(b):return hashlib.sha256(b).hexdigest().upper()
def pin(x):
 b=x.read_bytes();return {'path':str(x),'bytes':len(b),'sha256':sha(b)}
head=subprocess.check_output(['git','rev-parse','HEAD'],cwd=own,text=True).strip()
assert head=='1700aeaa800003130cce60106c243f6f293e81a9'
production=json.loads((p/'production-proposal.json').read_text())
primary=[own/item['path'] for item in production['production_files']]
for item in production['production_files']:
 assert pin(own/item['path'])['sha256']==item['snapshot']['sha256']
for frozen in production['untouched_reviewed_clock_and_api']:
 assert pin(Path(frozen['path']))==frozen
for draft in production['preexisting_unchanged_tracing_drafts_required_by_build']:
 assert pin(Path(draft['path']))==draft
absl=own/'vendor/node-v24.13.0/abseil-cpp'
absl_manifest=json.loads((absl/'SOURCE-MANIFEST.json').read_text())
assert len(absl_manifest['files'])==353
for entry in absl_manifest['files']:
 b=(absl/entry['path']).read_bytes();assert len(b)==entry['bytes'] and sha(b)==entry['sha256']
v8=own/'vendor/node-v24.13.0/v8-tracing'
v8_manifest=json.loads((v8/'SOURCE-MANIFEST.json').read_text())
for entry in v8_manifest['files']:
 b=(v8/entry['path']).read_bytes();assert len(b)==entry['bytes'] and sha(b)==entry['sha256']
packet_files=sorted(x for x in p.rglob('*') if x.is_file())
vendor_files=sorted(x for root in [absl,v8] for x in root.rglob('*') if x.is_file())
paths=primary+vendor_files+packet_files
assert len(paths)==len(set(paths))
scope=[]
for x in paths:
 q=pin(x);q['repository_path']=x.relative_to(own).as_posix()
 q['category']='primary_production' if x in primary else ('original_vendor_or_manifest' if x in vendor_files else 'verification_packet')
 scope.append(q)
tracked=subprocess.check_output(['git','diff','--name-only'],cwd=own,text=True).splitlines()
expected=[
 'src/extensions/native_node_commonjs_find_path.zig','src/extensions/native_node_commonjs_packages.zig',
 'src/extensions/native_node_commonjs_prototype.zig','src/extensions/native_node_commonjs_resolve_filename.zig',
 'src/extensions/native_node_commonjs_state.zig','src/extensions/native_node_commonjs_try_files.zig',
 'src/extensions/native_node_object_spread.zig']
assert tracked==expected
proof_names=[
 'production-proposal.json','source-body-proof-v2.json','abseil-source-graph-proof.json',
 'toolchain-and-sdk-selection-proof.json','build-composition/proposal.json',
 'acquisition-path-schema-bindings.json','instrumentation-debug-and-inherited-constructor-proof.json','README.md'
]
d={
 'schema':1,'kind':'Sealed finite native tracing platform/dependency source-only unit inventory',
 'created_utc':datetime.datetime.now(datetime.timezone.utc).isoformat(),'owned_worktree':str(own),'owned_head':head,
 'primary_production_files':10,'original_abseil_files':353,'original_Abseil_cpp_units':110,
 'original_V8_provider_and_license_files':2,'contained_original_SDK_headers':1,
 'body_comparisons':41,'lexical_Abseil_include_edges':1420,
 'proofs':[pin(p/name) for name in proof_names],
 'vendor_manifests':[pin(absl/'SOURCE-MANIFEST.json'),pin(v8/'SOURCE-MANIFEST.json')],
 'scope_inventory_excludes_this_manifest':scope,
 'scope_path_count_excluding_this_manifest':len(scope),
 'scope_path_count_including_this_manifest':len(scope)+1,
 'new_peer_receipts_may_be_added_separately':True,
 'previous_reviewed_clock_and_API_commits':['88fe6ba2883acf3b9b546d7ea37125e95ebf946a','1700aeaa800003130cce60106c243f6f293e81a9'],
 'external_reviewed_fatal_commit':'5059d6a04a29232fa3a39614d7e73e3690472c4f',
 'preexisting_draft_dependencies_are_not_new_unit_source_qualification':production['preexisting_unchanged_tracing_drafts_required_by_build'],
 'preexisting_tracked_dirty_paths_preserved':tracked,
 'review_state':'Root independently replayed 41 body checks; full finite source review and queued SDK/Handover slices remain separate receipts. No commit authorization or native lease is asserted.',
 'build_proposal_only':True,'build_basis':'f4c6abbc62ecd18b72ec50ab8fa206fe1664909f',
 'source_closure_is_not_link_or_bootstrap_completion':True,
 'new_test_roots':0,'compiler_execution':False,'preprocessor_execution':False,'native_execution':False,
 'project_source_generator_execution':False,'Node_reference_execution':False,'main_modified':False,'qualification':False
}
dest=p/'manifest.json';assert not dest.exists();dest.write_text(json.dumps(d,indent=2)+'\n',encoding='utf-8',newline='\n')
print(json.dumps({'manifest':pin(dest),'primary':len(primary),'vendor_files_including_manifests':len(vendor_files),'packet_files_excluding_manifest':len(packet_files),'total_unit_paths_including_manifest':len(scope)+1,'tracked_unrelated_dirty_paths':len(tracked),'HEAD':head},indent=2))
