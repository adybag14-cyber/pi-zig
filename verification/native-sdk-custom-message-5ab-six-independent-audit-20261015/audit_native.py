import pathlib,json,hashlib,subprocess,zipfile,io,re,struct,base64,sys
root=pathlib.Path('C:/Users/adyba/pi-zig-update-evidence-20261003/custom-message-ci-qualification-20261015');repo='C:/Users/adyba/pi-zig-custom-message-ci-20261015'
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
candidate=rowsmap(load(root/(str(run_id)+'-posix-reference')/'inputs.json')['candidate_controls']['rows']);assert len(candidate)==5611
stem='native_sdk_custom_message_test';code=subprocess.check_output(['git','-C',repo,'show',head+':src/'+stem+'.zig']).decode();expected=[stem+'.test.'+n for n in re.findall(r'^test "([^"]+)"',code,re.M)]+['extensions.native_durable_storage.test_0'];assert len(expected)==4 and len([n for n in expected if not n.endswith('test_0')])==3
assert '"custom-message40", run, .{}' in code and 'native custom messages deferred action retains its arguments across GC and retires them' in code
profiles=[]
for artifact in artifacts:
 assert artifact['workflow_run']['head_sha']==head and not artifact['expired']
 if '-posix-' in artifact['name']:continue
 archive=(root/(str(artifact['id'])+'.zip')).read_bytes();digest='sha256:'+hashlib.sha256(archive).hexdigest();assert digest==artifact['digest']
 folder=root/(str(run_id)+'-download')/artifact['name']
 with zipfile.ZipFile(io.BytesIO(archive)) as z:
  for name in z.namelist():
   if not name.endswith('/'):assert z.read(name)==(folder/name).read_bytes()
 doc=lambda n:load(folder/n)
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
 raw=(folder/'inventory.stdout.bin').read_bytes();offset=0;tags=[];names=None;version=None
 while offset<len(raw):
  tag,n=struct.unpack_from('<II',raw,offset);offset+=8;body=raw[offset:offset+n];assert len(body)==n;offset+=n;tags.append(tag)
  if tag==0:version=body.decode()
  elif tag==3:
   strings,count=struct.unpack_from('<II',body);assert count==4 and n==8+8*count+strings
   offsets=struct.unpack_from('<'+count*'I',body,8);panic=struct.unpack_from('<'+count*'I',body,8+4*count);assert all(p==0 for p in panic)
   text=body[8+8*count:];names=[text[o:text.index(b'\0',o)].decode() for o in offsets]
  else:raise AssertionError('Metadata query emitted unit-execution protocol tag '+str(tag))
 assert tags==[0,3] and version=='0.16.0' and names==metadata['tests']
 log=(folder/'runtime.stderr.log').read_text();assert re.search(r'^Build Summary:.*\b4/4 tests passed',log,re.M)
 baselines=re.findall(r'^EXHAUSTIVE_ALLOCATION_BASELINE custom-message40 total=(\d+)$',log,re.M);assert len(baselines)==1;total=int(baselines[0]);assert total>0
 for marker in ['RANGE','COMPLETE']:assert log.count(f'EXHAUSTIVE_ALLOCATION_{marker} custom-message40 0/1 range=[0,{total}) total={total}')==1
 begin=[int(x) for x in re.findall(r'^EXHAUSTIVE_ALLOCATION_INDEX_BEGIN custom-message40 (\d+)$',log,re.M)];done=[int(x) for x in re.findall(r'^EXHAUSTIVE_ALLOCATION_INDEX_COMPLETE custom-message40 (\d+)$',log,re.M)];assert begin==done==list(range(total))
 assert result['allocation_baseline']==result['allocation_completed']==total and result['allocation_gaps']==result['allocation_duplicates']==0
 profiles.append({'artifact_id':artifact['id'],'artifact':artifact['name'],'zip_digest':digest,'os':source['os'],'mode':source['mode'],'tests':4,'substantive_tests':3,'source_cases':40,'actual_allocation_baseline':total,'completed_allocations':len(done),'missing':0,'duplicates':0,'historical_windows_baseline_informational_only':87,'candidate_exact_git_files':5611,'compiler_frozen_files':tool_count,'post_inventory_hash_drift':0,'metadata_only_protocol_tags':[0,3],'exact_four_selected_names':True,'compile_and_runtime_exit_codes':[0,0]})
assert len(profiles)==6 and len({(p['os'],p['mode']) for p in profiles})==6 and {p['mode'] for p in profiles}=={'Debug','ReleaseSafe'}
report={'status':'independent_custom_message40_six_profile_audit_passed','run_id':run_id,'head':head,'product_base':base,'genuine_linux_source40_qualified':True,'linux_source_audit':str(root/(str(run_id)+'-independent-posix-audit.json')),'profiles':profiles,'allocation_scope':'Complete measured native allocator universe per profile; no exhaustive C malloc claim','latest_catalog_qualified':False,'full_factory_qualified':False,'full_pi_qualified':False,'public_activation':False}
(root/(str(run_id)+'-independent-complete-audit.json')).write_text(json.dumps(report,indent=2)+'\n');print(json.dumps(report,indent=2))