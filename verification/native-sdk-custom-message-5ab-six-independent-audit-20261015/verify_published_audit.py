import pathlib,json,hashlib,subprocess,zipfile,io,re,struct,base64,sys
root=pathlib.Path(__file__).resolve().parent;repo=str(root.parents[1])
run_id=int(sys.argv[1]) if len(sys.argv)>1 else 38780046188;head=sys.argv[2] if len(sys.argv)>2 else '0c5dad6539d42617afe0035348c8e3b852069387';base='d0da323437529a19fbb05bb3d3de7855be7f0b93'
load=lambda p:json.loads(pathlib.Path(p).read_text(encoding='utf-8-sig'))
def rowsmap(rows):
 out={r['relative']:r['sha256'] for r in rows};assert len(out)==len(rows);return out
def check_inventory(before,after):
 assert after['before_count']==after['after_count']==len(before['rows']) and after['path_drift']==after['hash_drift']==[] and rowsmap(before['rows'])==rowsmap(after['rows']);return len(before['rows'])
def owner_check(owner,timeout):
 assert owner['status']=='passed' and owner['exit_code']==0 and owner['retained_handle'] and owner['timeout_seconds']==timeout
 live=owner['live_identity'];assert live['pid']==owner['pid'] and live['created_utc']==owner['created_utc'] and live['executable'].lower()==owner['executable'].lower() and live['command_line']
 if live['command_line_method'].startswith('/proc'):assert base64.b64decode(live['command_line'])==b'\0'.join(x.encode() for x in [owner['executable']]+owner['arguments'])+b'\0'
run=load(root/(str(run_id)+'-run.json'));assert run['headSha']==head and run['status']=='completed' and run['conclusion']=='success' and len(run['jobs'])==7 and all(j['status']=='completed' and j['conclusion']=='success' for j in run['jobs'])
artifacts=load(root/(str(run_id)+'-artifacts.json'))['artifacts'];assert len(artifacts)==7
posix=load(root/(str(run_id)+'-independent-posix-audit.json'));assert posix['status']=='independent_genuine_linux_custom_message40_audit_passed' and posix['head']==head
manifest=load(root/'raw-evidence-manifest.json')
for row in manifest['files']:
 data=(root/row['path']).read_bytes();assert len(data)==row['bytes'] and hashlib.sha256(data).hexdigest()==row['sha256']
source_art,=[a for a in artifacts if '-posix-' in a['name']]
source_archive=(root/(str(source_art['id'])+'.zip')).read_bytes();assert 'sha256:'+hashlib.sha256(source_archive).hexdigest()==source_art['digest']
with zipfile.ZipFile(io.BytesIO(source_archive)) as z:source_payload={n:z.read(n) for n in z.namelist() if not n.endswith('/')}
source_doc=lambda name:json.loads(source_payload[name].decode('utf-8-sig'))
source_inputs,source_result=source_doc('inputs.json'),source_doc('result.json');candidate=rowsmap(source_inputs['candidate_controls']['rows']);assert len(candidate)==5611
entries=[x.split(b'\t',1) for x in subprocess.check_output(['git','-C',repo,'ls-tree','-r','-z',head]).split(b'\0') if x]
p=subprocess.Popen(['git','-C',repo,'cat-file','--batch'],stdin=subprocess.PIPE,stdout=subprocess.PIPE);git_hashes={}
for meta,path in entries:
 oid=meta.split()[2];p.stdin.write(oid+b'\n');p.stdin.flush();n=int(p.stdout.readline().split()[2]);data=p.stdout.read(n);assert p.stdout.read(1)==b'\n';git_hashes[path.decode()]=hashlib.sha256(data).hexdigest().upper()
p.stdin.close();assert p.wait(timeout=10)==0 and candidate==git_hashes
for before,after in [('full_source_dependencies_and_links','reference-posthash.json'),('candidate_controls','candidate-posthash.json'),('official_node_tools','node-tools-posthash.json'),('temporary_controls','temporary-controls-posthash.json')]:check_inventory(source_inputs[before],source_doc(after))
historical=json.loads(subprocess.check_output(['git','-C',repo,'show',head+':tools/ci/custom-message-reference/source5ab-full-manifest.json']));historical_map=rowsmap(historical);assert len(historical_map)==1967 and rowsmap(source_inputs['original_source_rows'])==historical_map
source_root=source_inputs['full_source_dependencies_and_links']['root'];files={r['path']:r['sha256'] for r in source_inputs['full_source_dependencies_and_links']['rows'] if r['kind']=='file'};links=[r for r in source_inputs['full_source_dependencies_and_links']['rows'] if r['kind']=='link'];assert len(links)==47
for link in links:assert link['resolved_target'].startswith(source_root+'/') and hashlib.sha256((link['link_target']+'\n'+link['resolved_target']).encode()).hexdigest().upper()==link['sha256']
assert all(files[source_root+'/'+path]==value for path,value in historical_map.items())
with zipfile.ZipFile(io.BytesIO(subprocess.check_output(['git','-C',repo,'show',head+':tools/ci/custom-message-reference/frozen-provider-data.zip']))) as z:
 assert len(z.namelist())==43 and all(name.startswith('packages/ai/src/providers/data/') and hashlib.sha256(z.read(name)).hexdigest().upper()==historical_map[name] for name in z.namelist())
assert source_result['source_head']=='5ab7fe74c400097b386662205cd93900695b8a71' and source_result['source_files']==1967 and source_result['tracked_source_files']==1924 and source_result['fresh_reference_processes']==2 and source_result['source_cases']==40
assert source_result['official_node_archive_sha256']=='41CD79BB7877C81605A9E68EC4C91547774F46A40C67A17E34D7179EF11729DF'
node_hashes=rowsmap(source_inputs['official_node_tools']['rows']);assert len(node_hashes)==4562 and node_hashes['bin/node']==source_result['node_executable_sha256']
install=source_doc('install-exact-locked-dependencies.json');assert install['status']=='passed' and install['exit_code']==0 and install['retained_handle'] and install['executable_sha256']==node_hashes['bin/node'] and all(a in install['arguments'] for a in ['ci','--ignore-scripts','--no-audit','--no-fund'])
golden=json.loads(subprocess.check_output(['git','-C',repo,'show',head+':src/extensions/fixtures/sdk-custom-message-5ab.json']));caller=subprocess.check_output(['git','-C',repo,'show',head+':src/extensions/fixtures/sdk-custom-message-5ab.input.txt']);assert len(golden['rows'])==40 and len(golden['descriptors'])==3 and hashlib.sha256(caller).hexdigest()==golden['inputSha256']
allowed=files|{r['path']:r['sha256'] for r in source_inputs['candidate_controls']['rows']};identities=set();raws=[]
for index in [1,2]:
 owner=source_doc(f'owner-{index}.json');owner_check(owner,300);observed=source_doc(f'original-{index}.json');closure=source_doc(f'closure-{index}.json');raw=source_payload[f'original-{index}.json.rows.bin']
 assert observed['rows']==golden['rows'] and observed['descriptors']==golden['descriptors'] and json.loads(raw)=={'descriptors':golden['descriptors'],'rows':golden['rows']} and hashlib.sha256(raw).hexdigest()==observed['rawSha256'] and observed['inputSha256']==golden['inputSha256']
 assert observed['actualNode']['version']=='v24.14.0' and observed['actualNode']['platform']=='linux' and observed['actualNode']['pid']==owner['pid'] and owner['executable_sha256']==node_hashes['bin/node']
 assert closure['unchanged_default_loader'] is True and closure['exit_code']==0 and closure['post_drift']==[] and closure['node']['pid']==owner['pid']
 loaded=[r for r in closure['records'] if r['kind']=='unchanged-default-module'];assert all(allowed.get(r['path'])==r['file_sha256'] for r in loaded) and len([r for r in loaded if r['path']==source_root+'/packages/coding-agent/src/core/agent-session.ts'])==1
 assert all(m['path'].startswith(source_root+'/packages/') and m['path'] in files for m in closure['workspace_mappings'])
 original,=[r for r in closure['records'] if r['kind']=='unchanged-original-caller'];assert original['sha256']==hashlib.sha256(caller).hexdigest().upper()
 identities.add((owner['pid'],owner['created_utc']));raws.append(raw)
assert len(identities)==2 and raws[0]==raws[1]
for flag in ['full_factory_qualified','latest_catalog_qualified','full_pi_qualified','public_activation']:assert source_result[flag] is False

stem='native_sdk_custom_message_test';code=subprocess.check_output(['git','-C',repo,'show',head+':src/'+stem+'.zig']).decode();expected=[stem+'.test.'+n for n in re.findall(r'^test "([^"]+)"',code,re.M)]+['extensions.native_durable_storage.test_0'];assert len(expected)==4 and len([n for n in expected if not n.endswith('test_0')])==3
assert '"custom-message40", run, .{}' in code and 'native custom messages deferred action retains its arguments across GC and retires them' in code
profiles=[]
for artifact in artifacts:
 assert artifact['workflow_run']['head_sha']==head and not artifact['expired']
 if '-posix-' in artifact['name']:continue
 archive=(root/(str(artifact['id'])+'.zip')).read_bytes();digest='sha256:'+hashlib.sha256(archive).hexdigest();assert digest==artifact['digest']
 with zipfile.ZipFile(io.BytesIO(archive)) as z:payload={name:z.read(name) for name in z.namelist() if not name.endswith('/')}
 doc=lambda name:json.loads(payload[name].decode('utf-8-sig'))
 source,result=doc('source.json'),doc('result.json');assert source['head']==result['head']==head and source['product_base']==result['product_base']==base
 inputs,tools=doc('inputs.json'),doc('tools.json');assert rowsmap(inputs['rows'])==candidate
 assert check_inventory(inputs,doc('inputs-posthash.json'))==5611;tool_count=check_inventory(tools,doc('tools-posthash.json'));assert tool_count==19546
 assert result['status']=='passed' and result['tests']==4 and result['substantive_tests']==3 and result['source_cases']==40 and result['runtime_measured_baseline_authoritative'] is True
 for flag in ['full_factory_qualified','latest_catalog_qualified','full_pi_qualified','public_activation']:assert result[flag] is False
 for phase,timeout,target in [('compile',1320,'build-native-sdk-custom-message'),('runtime',300,'test-native-sdk-custom-message')]:
  owner=doc(phase+'.json');owner_check(owner,timeout)
  assert target in owner['arguments'] and '-Doptimize='+source['mode'] in owner['arguments'] and '-j1' in owner['arguments'] and '--test-timeout' in owner['arguments'] and '120s' in owner['arguments']
  tool_hashes={r['path']:r['sha256'] for r in tools['rows']};assert tool_hashes[owner['executable']]==owner['executable_sha256']
  if 'Windows' in source['os']:assert owner['executable_sha256']=='086CE9D47BA42F33A514E1A6E04EB1D4A8FA1D75E0868E0213CAAD447C91E864'
 metadata=doc('selected-inventory.json');inventory_owner=doc('inventory.json');owner_check(inventory_owner,30)
 assert inventory_owner['arguments']==['--listen=-'] and inventory_owner['executable_sha256']==metadata['binary_sha256'] and metadata['version']=='0.16.0' and sorted(metadata['tests'])==sorted(expected)
 raw=payload['inventory.stdout.bin'];offset=0;tags=[];names=None;version=None
 while offset<len(raw):
  tag,n=struct.unpack_from('<II',raw,offset);offset+=8;body=raw[offset:offset+n];assert len(body)==n;offset+=n;tags.append(tag)
  if tag==0:version=body.decode()
  elif tag==3:
   strings,count=struct.unpack_from('<II',body);assert count==4 and n==8+8*count+strings
   offsets=struct.unpack_from('<'+count*'I',body,8);panic=struct.unpack_from('<'+count*'I',body,8+4*count);assert all(p==0 for p in panic)
   text=body[8+8*count:];names=[text[o:text.index(b'\0',o)].decode() for o in offsets]
  else:raise AssertionError('Metadata query emitted unit-execution protocol tag '+str(tag))
 assert tags==[0,3] and version=='0.16.0' and names==metadata['tests']
 log=payload['runtime.stderr.log'].decode('utf-8-sig').replace('\r\n','\n');assert re.search(r'^Build Summary:.*\b4/4 tests passed',log,re.M)
 baselines=re.findall(r'^EXHAUSTIVE_ALLOCATION_BASELINE custom-message40 total=(\d+)$',log,re.M);assert len(baselines)==1;total=int(baselines[0]);assert total>0
 for marker in ['RANGE','COMPLETE']:assert log.count(f'EXHAUSTIVE_ALLOCATION_{marker} custom-message40 0/1 range=[0,{total}) total={total}')==1
 begin=[int(x) for x in re.findall(r'^EXHAUSTIVE_ALLOCATION_INDEX_BEGIN custom-message40 (\d+)$',log,re.M)];done=[int(x) for x in re.findall(r'^EXHAUSTIVE_ALLOCATION_INDEX_COMPLETE custom-message40 (\d+)$',log,re.M)];assert begin==done==list(range(total))
 assert result['allocation_baseline']==result['allocation_completed']==total and result['allocation_gaps']==result['allocation_duplicates']==0
 profiles.append({'artifact_id':artifact['id'],'artifact':artifact['name'],'zip_digest':digest,'os':source['os'],'mode':source['mode'],'tests':4,'substantive_tests':3,'source_cases':40,'actual_allocation_baseline':total,'completed_allocations':len(done),'missing':0,'duplicates':0,'historical_windows_baseline_informational_only':87,'candidate_exact_git_files':5611,'compiler_frozen_files':tool_count,'post_inventory_hash_drift':0,'metadata_only_protocol_tags':[0,3],'exact_four_selected_names':True,'compile_and_runtime_exit_codes':[0,0]})
assert len(profiles)==6 and len({(p['os'],p['mode']) for p in profiles})==6 and {p['mode'] for p in profiles}=={'Debug','ReleaseSafe'}
report={'status':'independent_custom_message40_six_profile_audit_passed','run_id':run_id,'head':head,'product_base':base,'genuine_linux_source40_qualified':True,'linux_source_audit':str(root/(str(run_id)+'-independent-posix-audit.json')),'profiles':profiles,'allocation_scope':'Complete measured native allocator universe per profile; no exhaustive C malloc claim','latest_catalog_qualified':False,'full_factory_qualified':False,'full_pi_qualified':False,'public_activation':False}
recorded=load(root/(str(run_id)+'-independent-complete-audit.json'));assert all(report[k]==recorded[k] for k in report if k!='linux_source_audit');print(json.dumps({'status':'offline_published_custom40_audit_verified','run_id':run_id,'head':head,'genuine_linux_source40_qualified':True,'profiles':6,'tests_per_profile':4,'substantive_tests_per_profile':3,'actual_profile_allocations':[p['actual_allocation_baseline'] for p in profiles],'latest_catalog_qualified':False,'full_factory_qualified':False,'full_pi_qualified':False},indent=2))