"""Independent read/hash/excerpt proof for the discovered Close begin observer phase.
Only final output files in this evidence directory are written. No product code,
compiler, native image, service, grant constructor, launcher or auditor is run.
"""
from pathlib import Path
import hashlib,json,subprocess
P=Path(r'C:\Users\adyba\pi-zig\worktrees\modules-io-resume-20261018\verification\v35-file-handle-close-observer-source-peer-20261020')
MAIN=Path(r'C:\Users\adyba\pi-zig\main')
HEAD='79c19fc30c886e85b71aca75d1a025397db04fec'
def sha(b):return hashlib.sha256(b).hexdigest().upper()
def pin(p):
 b=p.read_bytes();return {'path':str(p),'bytes':len(b),'sha256':sha(b)}
rows=[
 ('src/native_node_file_handle_owner_test_support.zig','8E1205EAFD05CB18C6FD984258A1D153AE3E6262103EE0E13934FBB54FCC2E60',[(196,215,'The begin observer uses completion-only info; end observer genuinely runs at completion.')]),
 ('src/extensions/native_node_file_handle_owner.zig','2D90F772D2177C7DB4EF4F945F78529C0061C809E171C22CECC324125C9A461D',[(275,288,'The owned CloseReq is created, begin_async runs synchronously, then dispatchRawClose admits it.')]),
 ('src/extensions/native_node_file_handle_close_request.zig','C2016812A084329BCFC9DC113485F2732B2CC095C9ED6B8B21A18158205C443A',[(127,154,'Create owns a newly allocated typed CLOSE request and returns it after actual State/Global initialization.')]),
 ('src/extensions/native_node_fs_request_io.zig','B6792DCB053DDC2CFBC26350D9AD580CC5419CF3BDBEB595AF1F19B0922AF996',[(125,142,'Only later dispatch installs the callback and calls the native close admission.')]),
 ('src/extensions/native_uv_fs.h','23B85BBB1BD8395D1D5085BE0797F06CE2C323DAACF366F5CF3B587D06EACA6D',[(92,109,'Preparation requires owner-thread retained unsubmitted request; completion info has a different phase contract.')]),
 ('src/extensions/native_uv_tcp.c','8BFEFBB59ADCD7414A8C9358CA2422989784043B3BF651D8006D1C86DED261B2',[
  (19,31,'Native allocation is zero-initialized, including submitted and accepted.'),
  (416,431,'Typed kind and real service reference are retained; completed and cleaned initialize to zero.'),
  (803,835,'Preparation reads only kind/accepted/atomic flags; completion info asserts completed before reading uv.result/path.'),
  (837,855,'Only actual submission sets submitted; immediate failed admission may produce a completed result.'),
  (927,931,'Physical close first requires unsubmitted CLOSE storage and then invokes submission.')]),
]
pins=[];excerpts=[]
for rel,expected,ranges in rows:
 path=MAIN/rel;raw=path.read_bytes();assert sha(raw)==expected,rel
 gitraw=subprocess.check_output(['git','-C',str(MAIN),'show',HEAD+':'+rel])
 assert gitraw==raw,rel
 source=pin(path);source.update({'relative_path':rel,'raw_git_commit':HEAD,'raw_git_blob_equal':True});pins.append(source)
 lines=raw.splitlines(keepends=True)
 for a,b,claim in ranges:
  part=b''.join(lines[a-1:b]);assert len(lines)>=b
  excerpts.append({'source':source,'first_line':a,'last_line':b,'bytes':len(part),'sha256':sha(part),'text':part.decode(),'claim':claim})
path=P.parent/'native-node-stream-public-shutdown-analysis-20261020/authority/node_file.cc'
raw=path.read_bytes();assert sha(raw)=='19C497BF90FAD9E04645FCA423BC727F18F0B4B9E3C898C35AE2678D12047C0F'
original=pin(path);original.update({'upstream_commit':'def0bdf8abee441cfcbf793a8dc24a6f3b899573','upstream_path':'src/node_file.cc'})
pins.append(original);part=b''.join(raw.splitlines(keepends=True)[476:503])
excerpts.append({'source':original,'first_line':477,'last_line':503,'bytes':len(part),'sha256':sha(part),'text':part.decode(),'claim':'Original native trace begin at496 precedes Dispatch at497; this does not grant completion-info access to a test observer.'})
support=Path(pins[0]['path']).read_text(encoding='utf-8')
begin=support[support.index('fn beginAsyncClose('):support.index('fn endAsyncClose(')]
assert begin.count('uv.pi_uv_fs_request_info(request.actual.?).kind')==1
assert 'pi_uv_fs_request_preparation_info' not in begin
caller=Path(pins[1]['path']).read_text(encoding='utf-8')
assert caller.index('self.close_trace.begin_async(self.close_trace.raw, request);')<caller.index('const result = try self.controller.dispatchRawClose')
csource=Path(pins[5]['path']).read_text(encoding='utf-8')
prepare=csource[csource.index('PiUvFsPreparationInfo pi_uv_fs_request_preparation_info('):csource.index('PiUvFsInfo pi_uv_fs_request_info(')]
assert 'assert(!request->submitted);' in prepare
assert 'uv.result' not in prepare and 'uv.path' not in prepare
complete=csource[csource.index('PiUvFsInfo pi_uv_fs_request_info('):csource.index('PiUvResult pi_uv_fs_request_create(')]
assert 'assert(atomic_load_explicit(&request->completed, memory_order_acquire));' in complete
assert len(pins)==7 and len(excerpts)==11
proof={'schema':'pi-zig.v35-close-observer-phase-causal-proof.v1','status':'independent source-only finding; no runtime reproduction',
 'source_pins':pins,'excerpts':excerpts,
 'checks':{'raw_Main79_six_source_pins_equal':True,'original_Node_trace_precedes_dispatch':True,
 'begin_uses_completion_only_info':True,'completed_initially_zero':True,'begin_precedes_first_admission':True,
 'existing_preparation_info_matches_owned_unsubmitted_phase':True,'completion_info_contract_unchanged':True},
 'execution':{'compiler':False,'native':False,'Main_writes':False,'production_edits':False}}
# FINAL OUTPUT: writes only new independent evidence.
def emit(path,raw):
 path.parent.mkdir(parents=True,exist_ok=True);assert not path.exists(),str(path);path.write_bytes(raw)
emit(P/'causal-proof.json',(json.dumps(proof,indent=2)+'\n').encode())
peer={'schema':'pi-zig.independent-close-observer-phase-source-finding.v1',
 'status':'confirmed concrete source defect in existing test observer; candidate correction not yet reviewed',
 'finding':'beginAsyncClose reads completion-only PiUvFsInfo before dispatch. Actual completed is zero at this cutpoint, so the existing assert is inconsistent with this observer call.',
 'source_basis':HEAD,'proof':pin(P/'causal-proof.json'),'independent_checker':pin(P/'source-audit.py'),
 'bounded_correction_basis':'Reuse existing pi_uv_fs_request_preparation_info for this unsubmitted owner-thread kind observation; no production lifecycle/helper or completion-path weakening is required.',
 'ownership_reason':'CloseReq owns the actual request returned from typed CLOSE allocation. The observer is synchronous on the caller/dispatch thread before the first command makes that pointer visible to the service. There is no concurrent admission, cleanup, reset or release in this selected call.',
 'separation':'Identifier alpha-renaming is a different finite proposal. This finding does not alter it and is not a claim that a later compile or runtime cohort passes.',
 'remaining':'A separately sealed fixture correction and exact full inverse still need review before any Root source intake.',
 'no_Main_mutation':True,'no_native_execution':True}
emit(P/'finding.json',(json.dumps(peer,indent=2)+'\n').encode())
print(json.dumps({'finding':pin(P/'finding.json'),'proof':pin(P/'causal-proof.json'),'checker':pin(P/'source-audit.py'),'pins':len(pins),'excerpts':len(excerpts)}))
