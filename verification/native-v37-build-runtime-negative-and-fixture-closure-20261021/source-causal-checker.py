"""Read-only source checks; only --write adds a new causal-proof.json in this owned packet."""
from pathlib import Path
import hashlib,json,re,subprocess,sys
OUT=Path(__file__).resolve().parent
MAIN=Path(r'C:\Users\adyba\pi-zig\main')
HEAD='b13be24e44cc1bbc361639eb35900a368ae60eac'
def sha(b): return hashlib.sha256(b).hexdigest().upper()
def pin(path,b): return {'path':str(path),'bytes':len(b),'sha256':sha(b)}
def encode(x): return (json.dumps(x,indent=2,ensure_ascii=False)+'\n').encode()
def git(*args): return subprocess.check_output(['git','--no-optional-locks','-C',str(MAIN),*args])
def imports(b): return re.findall(rb'@(import|cInclude)\("([^"]+)"\)',b)
def names(b): return re.findall(rb'(?m)^test "([^"]+)"',b)
def segment(b,start,end): return b[b.index(start):b.index(end,b.index(start))]
assert git('rev-parse','HEAD').decode().strip()==HEAD
old_input=OUT/'authority-inputs.json';old_raw=old_input.read_bytes()
selected=OUT/'authority-inputs-v2.json';input_raw=selected.read_bytes()
assert sha(old_raw)=='940ED7F295FDE2A6D4F2F7770B7041E15F810B2A3D6C8FF8CCA8B5079A1B7727'
assert sha(input_raw)=='B97468E1DD34137C80A6199BABE6E227FEBDB5BD3FD0654B31EA3F05CF8C123F'
old_span=b'"first_line": 84,\n          "last_line": 96,\n          "role": "INIT/POST connect every public FS call to request initialization and sync/async execution"'
new_span=old_span.replace(b': 84,',b': 74,').replace(b': 96,',b': 97,')
assert old_raw.count(old_span)==1
span_offset=old_raw.index(old_span)
assert old_raw[:span_offset]+new_span+old_raw[span_offset+len(old_span):]==input_raw
assert input_raw[:span_offset]+old_span+input_raw[span_offset+len(new_span):]==old_raw
rows=json.loads(input_raw)['sources'];data={};pins=[];excerpts=[];snapshots=[]
for row in rows:
    p=Path(row['path']);b=p.read_bytes()
    assert len(b)==row['bytes'] and sha(b)==row['sha256'],row['key']
    data[row['key']]=b;pins.append({'key':row['key'],**pin(p,b)})
    if row['snapshot']:
        q=OUT/'authority'/row['snapshot'];qb=q.read_bytes()
        assert qb==b
        snapshots.append({'key':row['key'],'installed_original':pin(p,b),'immutable_snapshot':pin(q,qb)})
    if row['ranges']:
        lines=b.splitlines(keepends=True)
        for item in row['ranges']:
            a,z=item['first_line'],item['last_line'];assert 1<=a<=z<=len(lines)
            excerpt=b''.join(lines[a-1:z])
            excerpts.append({'source_key':row['key'],**item,'bytes':len(excerpt),'sha256':sha(excerpt),'text':excerpt.decode('utf-8')})
proposal=json.loads(data['proposal'])
assert proposal['main_basis']==HEAD and proposal['finite_edits']==8
expected_ids=[
 ['invalid-descriptor-constant','accepted-close-input','accepted-close-observation','gc-close-input','gc-exact-error-message','before-hook-rejected-close-input'],
 ['native-immediate-plain-object','native-immediate-resource-lifetime']]
file_checks=[]
for i,row in enumerate(proposal['files']):
    before=Path(row['original']['path']).read_bytes();after=Path(row['candidate']['path']).read_bytes()
    assert pin(Path(row['original']['path']),before)==row['original']
    assert pin(Path(row['candidate']['path']),after)==row['candidate']
    assert (MAIN/row['relative_path']).read_bytes()==before
    assert git('show',HEAD+':'+row['relative_path'])==before
    assert [x['id']for x in row['edits']]==expected_ids[i]
    current=before;edits=[];fragments=[]
    for edit in row['edits']:
        old=edit['old'].encode();new=edit['new'].encode();at=edit['offset']
        assert sha(current)==edit['before_sha256'] and current.count(old)==1 and current[at:at+len(old)]==old
        result=current[:at]+new+current[at+len(old):]
        assert sha(result)==edit['after_sha256']
        assert result[:at]+old+result[at+len(new):]==current
        fragments.append({'id':edit['id'],'prefix_bytes':at,'prefix_sha256':sha(current[:at]),'suffix_bytes':len(current)-at-len(old),'suffix_sha256':sha(current[at+len(old):])})
        edits.append({'id':edit['id'],'offset':at,'old_bytes':len(old),'new_bytes':len(new),'before_sha256':sha(current),'after_sha256':sha(result)})
        current=result
    assert current==after
    for edit in reversed(row['edits']):
        at=edit['offset'];old=edit['old'].encode();new=edit['new'].encode()
        assert sha(current)==edit['after_sha256'] and current[at:at+len(new)]==new
        current=current[:at]+old+current[at+len(new):]
        assert sha(current)==edit['before_sha256']
    assert current==before and imports(before)==imports(after) and names(before)==names(after)
    file_checks.append({'relative_path':row['relative_path'],'original':row['original'],'candidate':row['candidate'],'raw_Main_and_committed_preimage_exact':True,'intermediate_edits':edits,'untouched_fragments':fragments,'complete_inverse_exact':True,'imports_exact':[[a.decode(),b.decode()]for a,b in imports(before)],'named_controls_exact':[n.decode()for n in names(before)]})
old_test,new_test=data['original_test'],data['candidate_test']
old_fixture,new_fixture=data['original_fixture'],data['candidate_fixture']
assert b'-2' not in new_test
assert b'const invalid_descriptor: c_int = std.math.maxInt(c_int);' in new_test
assert b"'EBADF: Closing file descriptor 2147483647 on garbage collection failed, close' && " in new_test
assert new_test.count(b'f.create(invalid_descriptor, null, null)')==2
assert new_test.count(b'expectClosed(&f, invalid_descriptor)')==1
assert b'if (reject) invalid_descriptor else file.take()' in new_test
std_assert=lambda b:re.findall(rb'(?:try )?std\.testing\.expect\w*\([\s\S]*?;\n',b)
assert std_assert(old_test)==std_assert(new_test)
guest_assert=lambda b:re.findall(rb'try f\.expect\([\s\S]*?;\n',b)
assert guest_assert(old_test)==guest_assert(new_test.replace(b'file descriptor 2147483647 on',b'file descriptor -2 on'))
assert segment(old_fixture,b'fn finishImmediate(',b'fn caughtImmediate(')==segment(new_fixture,b'fn finishImmediate(',b'fn caughtImmediate(')
assert segment(old_fixture,b'    errdefer {\n        if (frame.scope.initialized)',b'    try frame.scope.init')==segment(new_fixture,b'    errdefer {\n        if (frame.scope.initialized)',b'    const resource = ')
assert segment(old_fixture,b'fn selectedHookException(',b'fn warningFlag(')==segment(new_fixture,b'fn selectedHookException(',b'fn warningFlag(')
assert b'self.outer.init(self.env(), outer_resource,' in old_fixture
assert sum(k==b'import' and v.endswith(b'.zig')for k,v in imports(new_fixture))==16
matrix=json.loads(data['catalog']);cohort=[];total=0
for group in matrix['groups'][113:117]:
    rel=group['source_root'];b=(MAIN/rel).read_bytes()
    root_pins=[x for x in group['source_pins'] if x['path']==rel]
    assert len(root_pins)==1 and sha(b)==root_pins[0]['sha256'].upper()
    declared=[Path(rel).stem+'.test.'+s.decode()for s in names(b)]
    assert declared==group['required_named']
    if rel==proposal['files'][0]['relative_path']:assert names(b)==names(new_test)
    cohort.append({'name':group['name'],'source':pin(MAIN/rel,b),'declared':len(declared),'named_sha256':sha(encode(declared))})
    total+=len(declared)
assert total==58
future_rows=[];selected_paths={x['relative_path']:x['candidate']for x in proposal['files']}
for gi,g in enumerate(matrix['groups']):
    for ri,row in enumerate(g['source_pins']):
        if row['path'] in selected_paths:
            candidate=selected_paths[row['path']]
            future_rows.append({'group':g['name'],'group_index':gi,'row_index':ri,'path':row['path'],'before':row['sha256'].upper(),'after':candidate['sha256'],'candidate_bytes':candidate['bytes']})
assert len(future_rows)==4
assert {x['group_index']for x in future_rows}=={113,114,116}
# Source/primary documentation proof of actual CRT behavior, with no target execution.
low=data['ucrt_lowio'];l2=int(re.search(rb'#define IOINFO_L2E\s+(\d+)',low)[1])
arrays=int(re.search(rb'#define IOINFO_ARRAYS\s+(\d+)',low)[1]);bound=arrays*(1<<l2)
assert bound==8192 and (1<<31)-1>bound
assert b'(__pioinfo[(i) >> IOINFO_L2E] + ((i) & (IOINFO_ARRAY_ELTS - 1)))' in low
assert b'(fh >= 0 && (unsigned)fh < (unsigned)_nhandle)' in data['ucrt_close']
assert data['ucrt_close'].index(b'(fh >= 0 && (unsigned)fh < (unsigned)_nhandle)')<data['ucrt_close'].index(b'(_osfile(fh) & FOPEN)')
mh=data['mingw_header'].replace(b'\r\n',b'\n')
assert b'# else\n#  define __MSVCRT_VERSION__ 0xE00\n# endif' in mh
assert b'#define _UCRT' in mh
assert not re.search(rb'-D(?:__MSVCRT_VERSION__|__CRTDLL__|_UCRT)',data['network_build'])
assert b'"src/win/core.c"' in data['network_build'] and b'"src/win/fs.c"' in data['network_build']
assert b'#if !defined(__MINGW32__) || __MSVCRT_VERSION__ >= 0x800' in data['uv_core']
assert b'_set_invalid_parameter_handler(uv__crt_invalid_parameter_handler);' in data['uv_core']
assert b'uv_once(&uv_init_guard_, uv__init);' in data['uv_core']
assert b'uv__fs_req_init(loop, req, subtype, cb);' in data['uv_fs']
assert b'uv__once_init();' in segment(data['uv_fs'],b'INLINE static void uv__fs_req_init(',b'void fs__open(')
assert b'uv_loop_init(&service->loop)' in data['uv_service']
assert b'if (fd > 2)\n    result = _close(fd);\n  else\n    result = 0;' in data['uv_fs'].replace(b'\r\n',b'\n')
assert b'if (state.fd == -1) check.assertion' in data['gc_close']
assert b'if (self.read_state.fd == -1) check.assertion' in data['owner']
assert b'.task = .{ .refed = result < 0,' in data['gc_close']
doc_ledger=json.loads(data['doc_acquisition'])
for key,tail in [('doc_setmaxstdio','/setmaxstdio.md'),('doc_close','/close.md')]:
    matches=[x for x in doc_ledger['data']['documents'] if x['url'].endswith(tail)]
    assert len(matches)==1
    doc=matches[0]
    assert doc['status']=='ok' and doc['http_status']==200 and not doc['content_truncated']
    assert doc['body_sha256'].upper()==sha(data[key]) and doc['excerpt'].encode()==data[key]
native_message='Closing file descriptor 2147483647 on garbage collection failed'
assert len(native_message.encode())<70
# This is the actual retained failed run, not an inference about a new run.
result=json.loads(data['runtime_result'])
observed=result['phases']['runtime']['evidence']['canonical_results']
flags=[x['index']for x in observed['results']if x['flags']!=0]
assert flags==[5,10,11,12,16]
assert observed['expected']==observed['started']==observed['completed']==19
assert observed['failed_or_skipped_or_logged_or_leaked']==5 and result['status']=='failed'
owner=json.loads(data['runtime_owner'])
assert owner['pid']==48028 and owner['exit_code']==0 and owner['created_utc']=='2026-10-21T13:30:33.3955731Z'
assert owner['executable_sha256']=='BF100B0B3CFB386757E0415DAFC8A7BEFF430ED96166AD5AA06E9129E0F8DB7F'
stderr=data['runtime_stderr'].decode().splitlines()
markers=[{'line':i+1,'text':line}for i,line in enumerate(stderr)if re.search(r'expected |beginImmediate|UnselectedConcrete| in pushBody|owner_test\.zig:',line)]
assert sum(' in beginImmediate ' in x['text']for x in markers)==2
assert any(x['text']=='expected -4083, found 0'for x in markers)
assert any(x['text']=='expected 1, found 0'for x in markers)
assert any(x['text']=='expected 2, found 1'for x in markers)
proof={
 'schema':'pi-zig.v37-file-handle-runtime-fixture-causal-proof.v1',
 'main_basis':HEAD,'proposal':pin(OUT/'proposal.json',data['proposal']),
 'selected_authority_inputs':pin(selected,input_raw),'preserved_authority_inputs':pin(old_input,old_raw),
 'source_mapping_only_correction':{'before':[84,96],'after':[74,97],'source_key':'uv_fs','role':'Include actual INIT as well as POST','complete_one_hunk_inverse':True,'candidate_changes':False},
 'input_pins':pins,'installed_SDK_authority_snapshots':snapshots,'exact_excerpts':excerpts,
 'file_checks':file_checks,'cohort_controls':cohort,'declared_control_count':58,
 'literal_import_topology_unchanged':True,'compiler_selected_reachability_claimed':False,
 'standard_assertions_byte_identical':{'count':len(std_assert(old_test)),'sha256':sha(b''.join(std_assert(old_test)))},
 'guest_assertions_exact_except_matching_bad_descriptor_message':{'count':len(guest_assert(old_test)),'inverse_sha256':sha(b''.join(guest_assert(old_test)))},
 'frame_errdefer_finishImmediate_and_selected_hook_policy_byte_identical':True,
 'production_files_changed':False,'future_catalog_source_rows_if_separately_integrated':future_rows,
 'future_catalog_or_inventory_written':False,
 'observed_negative':{'group':result['group'],'candidate_head':result['candidate_head'],'expected':19,'started':19,'completed':19,'flagged_indices':flags,'zero_flag_results':14,'native_owner_pid':owner['pid'],'native_owner_created_utc':owner['created_utc'],'native_owner_exit_code':0,'status':'failed','stderr_markers':markers,'other_group_outcomes_inferred':False,'independent_negative_closure_is_separate':True},
 'causal_findings':[
  {'indices':[5,12,16],'cause':'Input -2 passes VERIFY_FD and takes the Windows fd<=2 success branch. The real result is0, so the accepted close fulfills, GC creates an unrefed success-warning ticket, and the before-hook rejection branch observes fulfillment. Production result-based behavior is consistent with this input.','correction':'Use INT_MAX rather than -1 or any recycled real descriptor. Preserve EBADF/rejected/refed/identity assertions and change only the matching exact decimal message.'},
  {'indices':[10,11],'cause':'The actual beginImmediate fixture passes present undefined to CallbackScope; pushBody rejects it as invalid_resource. The fixed outer fixture initialization already succeeds and is unchanged.','correction':'Use a fresh plain object through the existing expression/allocation boundary while canCallIntoJs; otherwise retain the early-return undefined case. Production strict check remains unchanged.'}
 ],
 'descriptor_source_inference':{'selected_C_int_max':2147483647,'UCRT_lowio_table_entries':bound,'predicate':'0<=fd<_nhandle before table access, with nhandle bounded by 128 arrays of64','avoids_live_fd_reuse':True,'avoids_owner_sentinel_minus_one':True,'selected_header_default':'__MSVCRT_VERSION__=0xE00 and _UCRT','libuv_condition':'0xE00>=0x800','initialization':'Every FS INIT invokes uv__fs_req_init then uv__once_init; service loop creation also invokes once before worker publication.','invalid_handler':'Original libuv returning global handler is installed. Selected fixture and source files do not introduce a thread-local handler. Installed SDK implementation checks thread-local then global; primary docs say continuing returns-1/EBADF.','provenance_limit':'Installed Microsoft SDK source and official docs support the bounded UCRT behavior; they are not a byte identity claim for the loaded Windows DLL. No new runtime behavior has been observed.','native_error_message_bytes':len(native_message.encode()),'native_message_buffer_capacity':70},
 'resource_ownership':[
  'Pinned Node env.cc1392-1399 allocates a plain object only while can_call_into_js, before InternalCallbackScope.',
  'a.expression always finishes the body result. Scope.object uses real JS_NewObject and checked allocation ownership; duplicate creates the separately escaped entitlement.',
  'The temporary plain object has no fixture BindingData or FileHandle property/capture. Scope.init duplicates it into stable NativeCallback scope storage and retains Environment.',
  'The local defer frees the escaped entitlement after init or on error. Successful init leaves the Scope duplicate until unchanged finishImmediate calls deinit; the existing initialized-aware errdefer handles partial init and native frame retirement.',
  'If canCallIntoJs is false, no JS object allocation occurs and the unchanged Scope.init returns before present-resource validation. The cleanup JS-disallow interval and finish/caught behavior are unchanged.',
  'All existing checked allocation/pending/fatal semantics remain in the selected real boundary; no returned-Error shortcut, fake handler, production gate relaxation or new permanent JS root is introduced.'
 ],
 'qualification':{'source_only':True,'candidate_or_preparer_executed':False,'compiler_native_Node_reference_executed':False,'Main_or_index_written':False,'actual_future_metadata_count':None,'runtime_accepted':False,'previous_full_template_bootstrap_tracing_hook_policy_gaps_unchanged':True},
 'initial_proposal_pending_authority_resolved_for_source_review_only':True}
# Recheck all observed input bytes and exact source head before any optional receipt.
for row in rows:
    assert sha(Path(row['path']).read_bytes())==row['sha256'],row['key']
assert git('rev-parse','HEAD').decode().strip()==HEAD
raw=encode(proof);destination=OUT/'causal-proof.json'
if '--write' in sys.argv[1:]:
    assert not destination.exists()
    with destination.open('xb')as f:f.write(raw)
    assert destination.read_bytes()==raw
else:
    assert destination.read_bytes()==raw,'existing proof reproduction differs'
print(json.dumps({'status':'source-checks-passed','proof':pin(destination,raw),'inputs':len(pins),'SDK_snapshots':len(snapshots),'excerpts':len(excerpts),'finite_edits':8,'names':58,'future_catalog_rows':future_rows,'Main_written':False,'native_executed':False,'runtime_accepted':False}))
