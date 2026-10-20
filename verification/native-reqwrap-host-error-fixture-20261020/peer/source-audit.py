import hashlib,json,pathlib,re,subprocess
ROOT=pathlib.Path(r'C:\Users\adyba\pi-zig')
OUT=ROOT/'worktrees/modules-io-resume-20261018/verification/native-reqwrap-host-error-fixture-source-peer-20261020'
PROPOSAL=ROOT/'evidence/v34-reqwrap-host-error-fixture-sourceonly-20261020/proposal.json'
EXPECTED='A81ACE7F278882F45C8C56C3F4C18AEE6244F1B0D1FCB287FFBB24EF311FB34C'
pins={}
def sha(b):return hashlib.sha256(b).hexdigest().upper()
def read(path,expected=None):
 p=pathlib.Path(path);b=p.read_bytes();row={'path':str(p),'bytes':len(b),'sha256':sha(b)}
 if expected:
  assert row['bytes']==expected['bytes'] and row['sha256']==expected['sha256'],str(p)
 pins[str(p)]=row;return b
def git(*args):
 return subprocess.run(['git','-C',str(ROOT/'main'),*args],capture_output=True,check=True).stdout
proposal_raw=read(PROPOSAL)
assert sha(proposal_raw)==EXPECTED
m=json.loads(proposal_raw)
head=git('rev-parse','HEAD').decode().strip()
status=git('status','--porcelain=v1','-uno')
assert head==m['candidate_head']=='c764130caf2f2c7c63728bec0f6d1e16ac5c59a4'
before=read(m['before']['path'],m['before'])
current=read(m['current']['path'],m['current'])
after=read(m['projected']['path'],m['projected'])
assert current==before==git('show',head+':'+m['relative_path'])
assert len(m['hunks'])==1
h=m['hunks'][0];old=h['before'].encode();new=h['after'].encode()
assert before.count(old)==h['occurrences_before']==1
assert after.count(new)==h['occurrences_after']==1
assert before.replace(old,new)==after and after.replace(new,old)==before
assert sha(before)==h['before_sha256'] and sha(after)==h['after_sha256']
names=lambda b:[x.decode() for x in re.findall(rb'^test "([^"]+)"',b,re.M)]
assert names(before)==names(after)==m['declared_names']
assert len(names(before))==m['declared_name_count']==12
assert m['future_actual_metadata_count'] is None
metadata=json.loads(read(m['prior_metadata_acceptance']['path'],m['prior_metadata_acceptance']))
group=[x for x in metadata['groups'] if x['group']=='native-node-reqwrap-callback-routing']
assert len(group)==1
assert group[0]['tests']==m['prior_actual_metadata_names']
assert group[0]['actual_count']==m['prior_actual_metadata_count']==13
assert group[0]['tests']==['native_node_reqwrap_callback_routing_test.test.'+x for x in names(before)]+['extensions.native_durable_storage.test_0']
preflight=json.loads(read(m['retained_preflight']['path'],m['retained_preflight']))
assert preflight['first_attempt_assumption']==13 and preflight['actual_root_declarations']==12
assert preflight['first_attempt_failed_before_any_file_write']
for row in m['failure_evidence'].values():read(row['path'],row)
read(m['negative_closure']['path'],m['negative_closure'])
excerpts=[]
for e in m['source_excerpts']:
 b=read(e['source']['path'],e['source'])
 selected=b''.join(b.splitlines(keepends=True)[e['first_line']-1:e['last_line']])
 assert selected==e['text'].encode() and sha(selected)==e['text_sha256']
 assert git('show',head+':'+pathlib.Path(e['source']['path']).relative_to(ROOT/'main').as_posix())==b
 excerpts.append({'source':e['source'],'first_line':e['first_line'],'last_line':e['last_line'],'text_sha256':sha(selected)})
extra_ranges={
 'src/extensions/engine.zig':[(729,739),(962,964),(1025,1033)],
 'vendor/quickjs/quickjs.c':[(10026,10035),(10090,10114),(13923,13935)],
 'vendor/quickjs/quickjs.h':[(723,723),(1135,1135),(1156,1156)],
 'src/native_node_reqwrap_callback_routing_test.zig':[(203,233)]}
for rel,ranges in extra_ranges.items():
 p=ROOT/'main'/rel;b=read(p);assert git('show',head+':'+rel)==b
 for first,last in ranges:
  v=b''.join(b.splitlines(keepends=True)[first-1:last])
  excerpts.append({'source':pins[str(p)],'first_line':first,'last_line':last,'text':v.decode(),'text_sha256':sha(v)})
old_tail=b'    try std.testing.expectEqual(@as(usize, 1), f.observation_count);\n    try expectRetired(&f, 1);\n    try std.testing.expect(!c.JS_HasException(f.engine.context) and f.engine.captured_exception == null);\n'
assert old+old_tail in before and new+old_tail in after
assert new.count(b'defer f.engine.freeValue(')==6
assert new.count(b'defer f.engine.gpa.free(text);')==1
assert b'try std.testing.expect(c.JS_IsError(reason));' in new
assert b'try std.testing.expect(!c.JS_IsUncatchableError(reason));' in new
assert b'JS_IsStrictEqual(f.engine.context, actual_prototype, expected_prototype)' in new
assert b'Native coding SDK: ActualReqWrapSelectedCallbackFailure' in new
assert git('rev-parse','HEAD').decode().strip()==head
assert git('status','--porcelain=v1','-uno')==status
result={
 'schema':1,'status':'independent_source_only_fixture_projection_checks_passed',
 'proposal':pins[str(PROPOSAL)],'main_head':head,
 'main_status_before_and_after_sha256':sha(status),
 'main_head_and_status_unchanged':True,
 'pin_count':len(pins),'pins':list(pins.values()),
 'one_hunk_forward_and_full_inverse_exact':True,
 'before_current_and_committed_blob_exact':True,
 'all_non_hunk_bytes_preserved':True,
 'declared_names':names(after),'declared_count':12,
 'prior_observed_metadata_count':13,
 'prior_extra_anonymous_name':'extensions.native_durable_storage.test_0',
 'future_actual_metadata_count':None,
 'prior_count_negative_preserved':True,
 'source_excerpt_count':len(excerpts),'source_excerpts':excerpts,
 'owned_js_values_with_immediate_defer':['reason','global','constructor','expected_prototype','actual_prototype','message'],
 'owned_message_bytes_with_defer':True,
 'original_observation_retirement_and_empty_pending_assertions_preserved':True,
 'no_main_or_production_write':True,'no_compiler_native_or_test_execution':True}
raw=(json.dumps(result,indent=2)+'\n').encode()
OUT.mkdir(parents=True,exist_ok=True)
target=OUT/'source-audit.json'
assert not target.exists()
target.write_bytes(raw)
print(json.dumps({'path':str(target),'bytes':len(raw),'sha256':sha(raw),'pins':len(pins),'excerpts':len(excerpts)}))
