"""Audit the exact two-host Anthropic negative diagnostics, online or retained offline.
Usage: python audit_diagnostic.py REPO OUTPUT_DIRECTORY [--offline]
No native product or provider executes. Both real failures must remain failures.
"""
import base64,hashlib,io,json,pathlib,re,struct,subprocess,sys,tarfile,zipfile
args=sys.argv[1:];offline='--offline' in args;args=[a for a in args if a!='--offline'];repo,output=args
root=pathlib.Path(output);root.mkdir(parents=True,exist_ok=True)
head='f9ada04e5e9fca034824a996c5df17cea776b31b';base='4b6d46d4226c8f49fec120132847c0904786ebbc';run_id=38800086916
def load(data):return json.loads(data.decode('utf-8-sig'))
def save(name,data):(root/name).write_text(json.dumps(data,indent=2)+'\n',encoding='utf-8')
def gh(endpoint):return subprocess.check_output(['gh','api',endpoint])
def git(*args):return subprocess.check_output(['git','-c','gc.auto=0','-c','maintenance.auto=false','-C',repo,*args])
run=load((root/'run.json').read_bytes()) if offline else json.loads(subprocess.check_output(['gh','run','view',str(run_id),'-R','adybag14-cyber/pi-zig','--json','headSha,status,conclusion,jobs,url']))
assert run['headSha']==head and run['status']=='completed' and run['conclusion']=='failure' and len(run['jobs'])==2
assert all(j['status']=='completed' and j['conclusion']=='failure' for j in run['jobs']);save('run.json',run)
artifacts=load((root/'artifacts.json').read_bytes()) if offline else json.loads(gh(f'repos/adybag14-cyber/pi-zig/actions/runs/{run_id}/artifacts'))
assert artifacts['total_count']==len(artifacts['artifacts'])==2;save('artifacts.json',artifacts)
assert git('diff','--name-only',base,head,'--','src','vendor','build.zig','build.zig.zon').decode().strip()=='src/native_ai_claude_request_test.zig'
with tarfile.open(fileobj=io.BytesIO(git('archive',head))) as archive:
 candidate={m.name:archive.extractfile(m).read() for m in archive if m.isfile()}
assert hashlib.sha256(candidate['src/native_ai_claude_request_test.zig']).hexdigest().upper()=='A22B2E237BC54EEAAED49AAADF571D6CAF297037F504981CA74FF2D3588BEA38'
expected=['native_ai_claude_request_test.test.'+n for n in re.findall(r'^test "(native Claude5ab every host allocation[^"]+)"',candidate['src/native_ai_claude_request_test.zig'].decode(),re.M)]+['extensions.native_durable_storage.test_0'];assert len(expected)==3
def mapped(rows):
 out={r['relative']:r['sha256'] for r in rows};assert len(out)==len(rows);return out
def frozen(before,after):
 assert after['before_count']==after['after_count']==len(before['rows']) and after['path_drift']==after['hash_drift']==[] and mapped(before['rows'])==mapped(after['rows'])
def owner(record,status,timeout):
 assert record['status']==status and record['timeout_seconds']==timeout and record['retained_handle']
 assert record['exit_code']==(0 if status=='passed' else 1)
 live=record['live_identity'];assert live['pid']==record['pid'] and live['created_utc']==record['created_utc'] and live['executable'].lower()==record['executable'].lower() and live['command_line']
 if live['command_line_method'].startswith('/proc'):assert base64.b64decode(live['command_line'])==b'\0'.join(s.encode() for s in [record['executable']]+record['arguments'])+b'\0'
profiles=[]
for artifact in artifacts['artifacts']:
 assert artifact['workflow_run']['head_sha']==head and artifact['name'].endswith('-'+head) and not artifact['expired']
 path=root/(str(artifact['id'])+'.zip')
 if not path.exists():
  assert not offline;path.write_bytes(gh(f"repos/adybag14-cyber/pi-zig/actions/artifacts/{artifact['id']}/zip"))
 raw=path.read_bytes();digest='sha256:'+hashlib.sha256(raw).hexdigest();assert digest==artifact['digest']
 with zipfile.ZipFile(io.BytesIO(raw)) as archive:
  names=archive.namelist();assert len(names)==len(set(names)) and all('/' not in n and '\\' not in n and '..' not in n for n in names)
  files={n:archive.read(n) for n in names}
 doc=lambda n:load(files[n]);source=doc('source.json');inputs,tools=doc('inputs.json'),doc('tools.json')
 assert source['head']==head and source['product_base']==base and source['tests']==3 and source['mode']=='Debug' and source['diagnostic_only'] and source['full_universe'] and source['shard']==0 and source['shards']==1
 for flag in ['full_pi_qualified','full_factory_qualified','public_activation']:assert source[flag] is False
 frozen(inputs,doc('inputs-posthash.json'));frozen(tools,doc('tools-posthash.json'))
 assert mapped(inputs['rows'])=={p:hashlib.sha256(b).hexdigest().upper() for p,b in candidate.items()}
 assert source['source_files']==len(inputs['rows']) and source['compiler_files']==len(tools['rows'])
 tool_hashes={r['path']:r['sha256'] for r in tools['rows']}
 for phase,status,timeout in [('compile','passed',1500),('runtime','failed',900)]:
  record=doc(phase+'.json');owner(record,status,timeout);assert tool_hashes[record['executable']]==record['executable_sha256']
  assert ('build-' if phase=='compile' else 'test-')+'native-ai-claude5ab-allocation' in record['arguments'] and '-Doptimize=Debug' in record['arguments'] and '-j1' in record['arguments']
 query,metadata=doc('inventory.json'),doc('selected-inventory.json');owner(query,'passed',30)
 assert query['arguments']==['--listen=-'] and query['executable_sha256']==metadata['binary_sha256'] and sorted(metadata['tests'])==sorted(expected) and metadata['version']=='0.16.0'
 data=files['inventory.stdout.bin'];offset=0;tags=[];actual=None
 while offset<len(data):
  tag,size=struct.unpack_from('<II',data,offset);offset+=8;body=data[offset:offset+size];offset+=size;assert len(body)==size;tags.append(tag)
  if tag==0:assert body==b'0.16.0'
  elif tag==3:
   strings,count=struct.unpack_from('<II',body);assert count==3 and size==8+8*count+strings
   offsets=struct.unpack_from('<III',body,8);assert struct.unpack_from('<III',body,20)==(0,0,0);text=body[32:]
   actual=[text[p:text.index(b'\0',p)].decode() for p in offsets]
  else:raise AssertionError('Metadata query emitted test execution protocol tag')
 assert tags==[0,3] and actual==metadata['tests']
 log=files['runtime.stderr.log'].decode();assert re.search(r'run test 1 pass, 2 fail \(3 total\)',log)
 assert sorted(re.findall(r"error: '([^']+)' failed:",log))==sorted(n for n in expected if not n.endswith('test_0'))
 sweeps=[]
 for label,short in [('anthropic-request','request'),('anthropic-pending','pending')]:
  baselines=re.findall(r'EXHAUSTIVE_ALLOCATION_BASELINE '+label+r' total=(\d+)',log);assert len(baselines)==1;total=int(baselines[0])
  lines=re.findall(r'CLAUDE_ALLOCATION_DIAGNOSTIC '+short+r' fail_index=(\d+) outcome=(\S+) allocated=(\d+) freed=(\d+)',log);assert len(lines)==1
  bad,outcome,allocated,freed=lines[0];bad=int(bad);assert allocated==freed and bad<total
  assert [int(n) for n in re.findall(r'EXHAUSTIVE_ALLOCATION_INDEX_BEGIN '+label+r' (\d+)',log)]==list(range(bad+1))
  assert [int(n) for n in re.findall(r'EXHAUSTIVE_ALLOCATION_INDEX_COMPLETE '+label+r' (\d+)',log)]==list(range(bad))
  assert 'EXHAUSTIVE_ALLOCATION_COMPLETE '+label not in log and f'EXHAUSTIVE_ALLOCATION_RANGE {label} 0/1 range=[0,{total}) total={total}' in log
  sweeps.append({'label':label,'baseline':total,'first_failing_index':bad,'outcome':outcome,'allocated_bytes':int(allocated),'freed_bytes':int(freed),'completed_indices_before_failure':bad,'complete_universe_passed':False})
 assert 'CLAUDE_ALLOCATION_BOUNDARY pending-complete raw=JavaScriptException classified=JavaScriptException before=0 after=1 captured_tag=0 diagnostic=none' in log
 assert 'captureValue' in log and 'diagnostic_message' in log and 'native_sdk_prompt_scope.zig:15' in log and 'native_ai_anthropic_decode.zig:307' in log
 profiles.append({'artifact_id':artifact['id'],'name':artifact['name'],'zip_sha256':digest,'zip_bytes':len(raw),'selected_tests':3,'tests_passed':1,'tests_failed':2,'binary_sha256':metadata['binary_sha256'],'source_files':len(inputs['rows']),'compiler_files':len(tools['rows']),'source_tool_drift':0,'metadata_tags':tags,'sweeps':sweeps,'runtime_log_sha256':hashlib.sha256(files['runtime.stderr.log']).hexdigest()})
assert len(profiles)==2 and any('windows-latest' in p['name'] for p in profiles) and any('ubuntu-latest' in p['name'] for p in profiles)
report={'status':'independent_two_host_anthropic_negative_diagnostics_audited','head':head,'product_base':base,'run_id':run_id,'run_url':run['url'],'hosted_components_qualified':False,'public_activation':False,'profiles':profiles}
save('independent-diagnostic-audit.json',report);print(json.dumps(report,indent=2))
