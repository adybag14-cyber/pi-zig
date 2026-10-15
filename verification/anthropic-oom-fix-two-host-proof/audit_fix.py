"""Independently collect and audit exact hosted provider artifacts; no provider requests.

Usage: python audit_provider_ci.py RUN HEAD REPO OUTPUT_DIRECTORY [--expect-failure] [--offline]
Requires gh authentication for artifact downloads. Retained ZIP bytes are verified
against GitHub's SHA256 digest before any receipt is trusted. No product executes.
"""
import base64, hashlib, io, json, pathlib, re, struct, subprocess, sys, tarfile, zipfile

args=sys.argv[1:];expect_failure='--expect-failure' in args;offline='--offline' in args
args=[a for a in args if a not in ['--expect-failure','--offline']]
run_id, head, repo, output = args
root = pathlib.Path(output); root.mkdir(parents=True, exist_ok=True)
base = 'b6589631553bf5f5d3218e47b08cef5e277dd04f'
def gh(endpoint):
    return subprocess.check_output(['gh', 'api', endpoint])
def git(*args):
    return subprocess.check_output(['git', '-c', 'gc.auto=0', '-c', 'maintenance.auto=false', '-C', repo, *args])
def save_json(name, data):
    (root/name).write_text(json.dumps(data, indent=2)+'\n', encoding='utf-8')
def decode_json(data):
    return json.loads(data.decode('utf-8-sig'))
run = decode_json((root/'run.json').read_bytes()) if offline else json.loads(subprocess.check_output(['gh','run','view',run_id,'-R','adybag14-cyber/pi-zig','--json','headSha,status,conclusion,jobs,url']))
save_json('run.json',run)
assert run['headSha']==head and run['status']=='completed' and run['conclusion']==('failure' if expect_failure else 'success')
assert len(run['jobs'])==2 and all(j['status']=='completed' and j['conclusion'] in (['success','failure'] if expect_failure else ['success']) for j in run['jobs'])
artifacts=decode_json((root/'artifacts.json').read_bytes()) if offline else json.loads(gh(f'repos/adybag14-cyber/pi-zig/actions/runs/{run_id}/artifacts'))
save_json('artifacts.json',artifacts); assert artifacts['total_count']==len(artifacts['artifacts'])==2
assert git('diff','--name-only',base,head,'--','src','vendor','build.zig','build.zig.zon')==b''
with tarfile.open(fileobj=io.BytesIO(git('archive',head))) as archive:
    candidate={m.name:archive.extractfile(m).read() for m in archive if m.isfile()}
component_specs=[
 ('headers','native-headers-source',5,['src/extensions/native_headers_source_test.zig'],r'^(Headers Source189|Headers native helper)',['native_headers_source_test.test_0']),
 ('pi-messages','native-ai-pi-messages',5,['src/native_ai_pi_messages_test.zig'],r'^native AI pi messages',[]),
 ('responses','native-ai-responses',4,['src/native_ai_responses_test.zig'],r'^native Responses',[]),
 ('anthropic','native-ai-claude5ab',5,['src/native_ai_claude_request_test.zig'],r'^native Claude5ab (Anthropic|request owner)',[]),
 ('anthropic-allocation','native-ai-claude5ab-allocation',3,['src/native_ai_claude_request_test.zig'],r'^native Claude5ab every host allocation',[]),
 ('generator','native-async-generator',19,['src/native_async_generator_test.zig','src/native_ai_json_parse_test.zig','src/extensions/native_stream.zig'],r'^(native async generator functional|native AI JSON (actual OpenAI request builder|OpenAI decoder|helpers and native partial fallback|genuine b06 delegates|private hooks|ordinary no-hook)|native pi-ai EventStream exports|native AssistantMessageEventStream producer queue overflow|native provider validation|native provider cancellation)',[]),
 ('generator-gpa','native-async-generator-gpa',2,['src/native_async_generator_test.zig'],r'^native async generator host GPA',[])]
component_specs=[c for c in component_specs if c[0] in ['anthropic','anthropic-allocation']]
expected_names={}
for cid,target,count,sources,pattern,extras in component_specs:
    names=[path[4:-4].replace('/','.')+'.test.'+name for path in sources for name in re.findall(r'^test "([^"]+)"',candidate[path].decode(),re.M) if re.match(pattern,name)]
    names+=['extensions.native_durable_storage.test_0']+extras
    assert len(names)==count and len(set(names))==count
    expected_names[cid]=sorted(names)
def rowsmap(rows):
    mapped={r['relative']:r['sha256'] for r in rows}; assert len(mapped)==len(rows);return mapped
def inventory(before,after):
    assert after['before_count']==after['after_count']==len(before['rows'])
    assert after['path_drift']==after['hash_drift']==[] and rowsmap(before['rows'])==rowsmap(after['rows'])
def owner_check(owner,timeout):
    assert owner['status']=='passed' and owner['exit_code']==0 and owner['retained_handle'] and owner['timeout_seconds']==timeout
    live=owner['live_identity']
    assert live['pid']==owner['pid'] and live['created_utc']==owner['created_utc'] and live['executable'].lower()==owner['executable'].lower() and live['command_line']
    if live['command_line_method'].startswith('/proc'):
        assert base64.b64decode(live['command_line'])==b'\0'.join(x.encode() for x in [owner['executable']]+owner['arguments'])+b'\0'
profiles=[]
for artifact in artifacts['artifacts']:
    assert artifact['workflow_run']['head_sha']==head and not artifact['expired'] and artifact['name'].endswith('-'+head)
    archive_path=root/(str(artifact['id'])+'.zip')
    if not archive_path.exists():
        assert not offline, 'Missing retained offline ZIP: '+str(archive_path)
        archive_path.write_bytes(gh(f"repos/adybag14-cyber/pi-zig/actions/artifacts/{artifact['id']}/zip"))
    raw=archive_path.read_bytes();digest='sha256:'+hashlib.sha256(raw).hexdigest();assert digest==artifact['digest']
    with zipfile.ZipFile(io.BytesIO(raw)) as archive:
        paths=[n for n in archive.namelist() if not n.endswith('/')]
        assert len(paths)==len(set(paths)) and all(not n.startswith(('/', '\\')) and '\\' not in n and '..' not in pathlib.PurePosixPath(n).parts for n in paths)
        files={n:archive.read(n) for n in paths}
    doc=lambda n:decode_json(files[n])
    source=doc('source.json');result=doc('result.json') if 'result.json' in files else None
    assert source['head']==head and source['product_base']==base and source['tree']==git('rev-parse',head+'^{tree}').decode().strip()
    if result is not None:
        assert result['head']==head and result['product_base']==base and source['mode']==result['mode'] and result['status']=='passed' and result['tests']==8 and len(result['components'])==2
    else:assert expect_failure
    boundaries=source['boundaries']
    if result is not None:assert boundaries==result['boundaries']
    for flag in ['full_factory_qualified','full_pi_qualified','public_activation','default_responses_websocket_qualified','fresh_posix_source_recapture','anthropic_query_beta_qualified']: assert boundaries[flag] is False
    assert boundaries['funded_provider_requests']==0
    inputs,tools=doc('inputs.json'),doc('tools.json');inventory(inputs,doc('inputs-posthash.json'));inventory(tools,doc('tools-posthash.json'))
    input_map=rowsmap(inputs['rows']);assert set(input_map)==set(candidate) and source['source_files']==len(input_map) and source['compiler_files']==len(tools['rows'])
    newline_checkouts=[]
    for path,data in candidate.items():
        if input_map[path]!=hashlib.sha256(data).hexdigest().upper():
            assert 'Windows' in source['os'] and b'\0' not in data and input_map[path]==hashlib.sha256(data.replace(b'\r\n',b'\n').replace(b'\n',b'\r\n')).hexdigest().upper()
            newline_checkouts.append(path)
    tool_hashes={r['path']:r['sha256'] for r in tools['rows']};components=[];executed_tests=0
    for cid,target,count,_,_,_ in component_specs:
        cd=lambda n:doc(cid+'/'+n)
        if cid+'/compile.json' not in files:
            assert expect_failure
            components.append({'id':cid,'status':'not_reached','planned_tests':count});continue
        info=cd('result.json') if cid+'/result.json' in files else None
        if info is not None:assert info['head']==head and info['status']=='passed' and info['tests']==count and info['component']['id']==cid
        else:assert expect_failure
        meta=cd('selected-inventory.json')
        for phase,timeout in [('compile',1500),('runtime',1200)]:
            owned=cd(phase+'.json')
            if phase=='runtime' and owned['status']=='failed':
                assert expect_failure and owned['exit_code']!=0 and owned['timeout_seconds']==timeout
                checked=dict(owned,status='passed',exit_code=0);owner_check(checked,timeout)
            else:owner_check(owned,timeout)
            assert ('build-' if phase=='compile' else 'test-')+target in owned['arguments']
            assert '-Doptimize='+source['mode'] in owned['arguments'] and '-j1' in owned['arguments']
            assert tool_hashes[owned['executable']]==owned['executable_sha256']
            if 'Windows' in source['os']:assert owned['executable_sha256']=='086CE9D47BA42F33A514E1A6E04EB1D4A8FA1D75E0868E0213CAAD447C91E864'
        queried=cd('inventory.json');owner_check(queried,30)
        assert queried['arguments']==['--listen=-'] and queried['executable_sha256']==meta['binary_sha256']
        if info is not None:assert meta['binary_sha256']==info['binary_sha256']
        assert meta['version']=='0.16.0' and sorted(meta['tests'])==expected_names[cid]
        rawmeta=files[cid+'/inventory.stdout.bin'];offset=0;tags=[];names=None
        while offset<len(rawmeta):
            tag,length=struct.unpack_from('<II',rawmeta,offset);offset+=8;body=rawmeta[offset:offset+length];assert len(body)==length;offset+=length;tags.append(tag)
            if tag==0: assert body==b'0.16.0'
            elif tag==3:
                strings,num=struct.unpack_from('<II',body);assert num==count and length==8+8*num+strings
                offsets=struct.unpack_from('<'+num*'I',body,8);panic=struct.unpack_from('<'+num*'I',body,8+4*num);assert not any(panic)
                text=body[8+8*num:];names=[text[o:text.index(b'\0',o)].decode() for o in offsets]
            else:raise AssertionError('Metadata-only query emitted execution protocol tag '+str(tag))
        assert tags==[0,3] and names==meta['tests']
        log=files[cid+'/runtime.stderr.log'].decode()
        runtime=cd('runtime.json');component={'id':cid,'status':runtime['status'],'planned_tests':count,'binary_sha256':meta['binary_sha256'],'metadata_tags':tags,'exact_selected_names':meta['tests']}
        if runtime['status']=='passed':
            assert info is not None
            assert re.search(r'^Build Summary:.*\b'+str(count)+'/'+str(count)+' tests passed',log,re.M)
            assert re.search(r'run test '+str(count)+r' pass \('+str(count)+r' total\)',log)
            component.update(tests_passed=count,tests_failed=0,allocation_scope=info['component']['allocation_scope'])
        else:
            assert expect_failure and info is None
            summary=re.search(r'run test (\d+) pass, (\d+) fail \((\d+) total\)',log)
            assert summary and int(summary[3])==count and int(summary[1])+int(summary[2])==count
            failures=re.findall(r"error: '([^']+)' failed(?::| without output)",log)
            assert len(failures)==int(summary[2]) and all(name in meta['tests'] for name in failures)
            component.update(tests_passed=int(summary[1]),tests_failed=int(summary[2]),failed_tests=failures,exit_code=runtime['exit_code'],failure_log_sha256=hashlib.sha256(files[cid+'/runtime.stderr.log']).hexdigest())
        if runtime['status']=='passed' and cid=='anthropic-allocation':
            measured=[]
            for label in ['anthropic-request','anthropic-pending']:
                values=re.findall(r'(?m)^EXHAUSTIVE_ALLOCATION_BASELINE '+label+r' total=(\d+)\r?$',log);assert len(values)==1
                total=int(values[0]);assert total>0
                for marker in ['RANGE','COMPLETE']:
                    assert len(re.findall(r'(?m)^'+re.escape(f'EXHAUSTIVE_ALLOCATION_{marker} {label} 0/1 range=[0,{total}) total={total}')+r'\r?$',log))==1
                for marker in ['BEGIN','COMPLETE']:
                    indices=[int(n) for n in re.findall(r'(?m)^EXHAUSTIVE_ALLOCATION_INDEX_'+marker+' '+label+r' (\d+)\r?$',log)]
                    assert indices==list(range(total))
                retained=next(s for s in info['sweeps'] if s['label']==label)
                assert retained['baseline']==retained['completed']==total and retained['gaps']==retained['duplicates']==0
                measured.append(retained)
            assert len(info['sweeps'])==2;component['complete_measured_sweeps']=measured
        executed_tests+=count;components.append(component)
    profiles.append({'artifact_id':artifact['id'],'artifact_name':artifact['name'],'zip_sha256':digest,'zip_bytes':len(raw),'mode':source['mode'],'os':source['os'],'planned_tests':8,'executed_tests':executed_tests,'planned_substantive_tests':6,'planned_declaration_tests':2,'source_files':len(input_map),'compiler_files':len(tools['rows']),'checkout_newline_conversions':len(newline_checkouts),'source_tool_posthash_drift':0,'components':components})
assert len(profiles)==2 and len({(p['mode'],'Windows' if 'Windows' in p['os'] else 'Linux') for p in profiles})==2
assert {p['mode'] for p in profiles}=={'Debug'}
component_outcomes=[]
for cid,_,count,_,_,_ in component_specs:
    statuses=[next(c['status'] for c in p['components'] if c['id']==cid) for p in profiles]
    component_outcomes.append({'id':cid,'selected_tests_per_profile':count,'passed_profiles':statuses.count('passed'),'failed_profiles':statuses.count('failed'),'not_reached_profiles':statuses.count('not_reached'),'both_selected_test_arrays_passed':statuses==['passed']*2})
report={'status':('independent_anthropic_fix_failed_two_host_evidence_audited' if expect_failure else 'independent_anthropic_fix_two_host_audit_passed'),'anthropic_fix_two_host_scope_qualified':not expect_failure,'full_provider_cohort_qualified':False,'run_id':int(run_id),'run_url':run['url'],'head':head,'product_base':base,'profile_count':2,'planned_tests_per_profile':8,'aggregate_executed_tests':sum(p['executed_tests'] for p in profiles),'boundaries':boundaries,'component_profile_outcomes':component_outcomes,'profiles':profiles}
report['aggregate_passed_tests']=sum(c.get('tests_passed',0) for p in profiles for c in p['components'])
report['aggregate_failed_tests']=sum(c.get('tests_failed',0) for p in profiles for c in p['components'])
report['aggregate_not_reached_tests']=16-report['aggregate_executed_tests']
report['added_callback_regression_file_executed_in_this_cohort']=False
save_json('independent-audit.json',report)
print(json.dumps({k:v for k,v in report.items() if k!='profiles'},indent=2))
