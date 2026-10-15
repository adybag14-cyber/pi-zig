import json, hashlib, subprocess, pathlib, re, zipfile, io
root=pathlib.Path(__file__).resolve().parent
repo=str(root.parents[1])
head='f1a3d9c8095cc2accac2bd84f4a4326328ef1e01'
run=json.loads((root/'run.json').read_text(encoding='utf-8-sig'))
arts=json.loads((root/'artifacts.json').read_text(encoding='utf-8-sig'))['artifacts']
assert run['headSha']==head and run['status']=='completed' and run['conclusion']=='success'
assert len(run['jobs'])==6 and all(j['conclusion']=='success' and j['status']=='completed' for j in run['jobs'])
rawtree=subprocess.check_output(['git','-C',repo,'ls-tree','-r','-z',head])
entries=[item.split(b'\t',1) for item in rawtree.split(b'\0') if item]
blobs=[(meta.split()[2].decode(), path.decode()) for meta,path in entries if meta.split()[1]==b'blob']
proc=subprocess.Popen(['git','-C',repo,'cat-file','--batch'],stdin=subprocess.PIPE,stdout=subprocess.PIPE)
authority={}
for oid,path in blobs:
 proc.stdin.write((oid+'\n').encode());proc.stdin.flush()
 header=proc.stdout.readline().split();n=int(header[2]);data=proc.stdout.read(n);assert proc.stdout.read(1)==b'\n'
 authority[path]=hashlib.sha256(data).hexdigest().upper()
proc.stdin.close();assert proc.wait(timeout=10)==0
assert len(authority)==5599
rows=[]
for art in arts:
 assert art['workflow_run']['head_sha']==head and not art['expired']
 archive=(root/(str(art['id'])+'.zip')).read_bytes()
 digest='sha256:'+hashlib.sha256(archive).hexdigest();assert digest==art['digest']
 with zipfile.ZipFile(io.BytesIO(archive)) as z:
  names=[name for name in z.namelist() if not name.endswith('/')]
  assert len(names)==len(set(names)) and all('/' not in name and '\\' not in name and '..' not in name for name in names)
  payload={name:z.read(name) for name in names}
 doc=lambda name:json.loads(payload[name].decode('utf-8-sig'))
 source,result=doc('source.json'),doc('result.json')
 inputs,tools=doc('inputs.json'),doc('tools.json')
 assert source['head']==head and result['head']==head and source['tree']=='5be6a31c10318b8c06c9fec740ded05b8ea56e15'
 assert len(inputs)==5599 and {r['path']:r['sha256'] for r in inputs}==authority
 assert len({r['path'] for r in tools})==len(tools)==source['tool_count']
 for kind,count in [('inputs',len(inputs)),('tools',len(tools))]:
  post=doc(kind+'-posthash.json');assert post['count']==count and post['drift']==[] and post['inventory_drift']==0
 log=payload['runtime.stderr.log'].decode('utf-8-sig').replace('\r\n','\n')
 inventory=re.findall(r'^CHECK_COMPACTION_TEST_INVENTORY=(\[[^\r\n]*\])$',log,re.M)
 assert len(inventory)==1 and len(set(json.loads(inventory[0])))==10
 baseline=re.findall(r'^EXHAUSTIVE_ALLOCATION_BASELINE check-compaction32 total=(\d+)$',log,re.M);assert len(baseline)==1
 total=int(baseline[0]);begins=[int(x) for x in re.findall(r'^EXHAUSTIVE_ALLOCATION_INDEX_BEGIN check-compaction32 (\d+)$',log,re.M)]
 done=[int(x) for x in re.findall(r'^EXHAUSTIVE_ALLOCATION_INDEX_COMPLETE check-compaction32 (\d+)$',log,re.M)]
 assert begins==done==list(range(total))
 for marker in ['RANGE','COMPLETE']:
  assert log.count(f'EXHAUSTIVE_ALLOCATION_{marker} check-compaction32 0/1 range=[0,{total}) total={total}')==1
 assert re.search(r'^Build Summary:.*\b10/10 tests passed$',log,re.M)
 assert result['status']=='passed' and result['tests']==10 and result['source_cases']==32 and result['baseline']==result['completed']==total and result['missing']==result['duplicates']==0
 assert source['original_cases']==32 and source['original_fixture_platform']=='Windows'
 assert not result['full_pi_qualified'] and not result['public_activation'] and not result['genuine_posix_source_capture_qualified']
 for phase,timeout in [('compile',1320),('runtime',300)]:
  owner=doc(phase+'.process.json');assert owner['status']=='passed' and owner['exit_code']==0 and owner['outer_seconds']==timeout and owner['settle_seconds']==10 and owner['live_command_line']
  assert '-j1' in owner['argv'] and '-Doptimize='+source['mode'] in owner['argv']
  if phase=='runtime':assert '--test-timeout' in owner['argv'] and '120s' in owner['argv']
 rows.append(dict(artifact=art['name'],artifact_id=art['id'],zip_digest=digest,platform=source['platform'],mode=source['mode'],tests=10,source_cases=32,allocation_baseline=total,allocation_completed=len(done),allocation_gaps=0,allocation_duplicates=0,candidate_files_exact_git_blob_sha256=len(inputs),compiler_manifest_files=len(tools),posthash_candidate_and_compiler_drift=0,owner_terminal='passed/exit0'))
report=dict(run_id=38651137459,head=head,tree='5be6a31c10318b8c06c9fec740ded05b8ea56e15',status='independent_artifact_audit_passed',audited_profiles=rows,source_fixture='b06 Windows original32',genuine_posix_source_capture_qualified=False,allocation_scope='Complete measured native allocator universe; does not claim exhaustive C malloc',full_pi_qualified=False,public_activation=False,proof_worktree_edited=False)
assert report==json.loads((root/'independent-audit.json').read_text())
print(json.dumps({'status':'offline_published_audit_verified','run_id':38651137459,'head':head,'profiles':6,'candidate_git_blob_sha256_per_profile':5599,'tests_per_profile':10,'native_allocations_per_profile':895,'genuine_posix_source_capture_qualified':False,'full_pi_qualified':False},indent=2))