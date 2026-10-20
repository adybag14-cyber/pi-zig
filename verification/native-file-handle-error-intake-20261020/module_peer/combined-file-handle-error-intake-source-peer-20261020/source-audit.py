from pathlib import Path
import hashlib,json,re,subprocess
O=Path(r'C:\Users\adyba\pi-zig\worktrees\modules-io-resume-20261018')
M=Path(r'C:\Users\adyba\pi-zig\main')
P=Path(r'C:\Users\adyba\pi-zig\evidence\pending-file-handle-and-error-intake-20261020/projection.json')
D=O/'verification/combined-file-handle-error-intake-source-peer-20261020'
pins={}
def sha(b):return hashlib.sha256(b).hexdigest().upper()
def pin(p):
 b=Path(p).read_bytes();return {'path':str(p),'bytes':len(b),'sha256':sha(b)}
def verify(r):
 b=Path(r['path']).read_bytes();assert len(b)==r['bytes'] and sha(b)==r['sha256'],r['path'];pins[r['path']]=dict(r);return b
assert P.stat().st_size==25832 and sha(P.read_bytes())=='E1C3AE19CE38CF7FB6B21043F9B154B4DC4AE0952A9B149BD6BE792AFAC7C3B3'
d=json.loads(P.read_bytes());head=d['comparison_main_head']
assert head=='c764130caf2f2c7c63728bec0f6d1e16ac5c59a4'
assert subprocess.check_output(['git','rev-parse','HEAD'],cwd=M).decode().strip()==head
records={r['relative_path']:r for r in d['paths']};assert len(records)==len(d['paths'])==17
evidence=[json.loads(verify(r)) for r in d['composition_evidence']]
owner,error,owner_build,error_build=evidence[:4]
owner_paths={r['relative_path']:r for r in owner['paths']}
error_paths={r['path']:r for r in error['install_sources'] if r['path']!='build.zig'}
assert len(owner_paths)==13 and len(error_paths)==4
assert set(records)==set(owner_paths)|set(error_paths)
results=[]
for rel,row in records.items():
 selected=verify(row['projected'])
 if row['donor'] is not None:assert selected==verify(row['donor'])
 if rel!='build.zig':
  prior=owner_paths[rel]['projected'] if rel in owner_paths else error_paths[rel]['selected']
  assert selected==verify(prior)
 if row['kind']=='replace':
  original=verify(row['before']);assert original==verify(row['original_snapshot'])
  assert Path(row['before']['path'])==M/rel
  blob=subprocess.check_output(['git','show',head+':'+rel],cwd=M)
  assert blob==original and (M/rel).read_bytes()==original
 else:
  assert row['kind']=='new' and row['before'] is None and not (M/rel).exists()
  status=subprocess.run(['git','cat-file','-e',head+':'+rel],cwd=M,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
  assert status.returncode!=0
 results.append({'relative_path':rel,'kind':row['kind'],'selected':pin(Path(row['projected']['path']))})
assert sum(r['kind']=='new' for r in d['paths'])==8
assert sum(r['kind']=='replace' for r in d['paths'])==9
actual={str(p.relative_to(P.parent/'projected')).replace('\\','/') for p in (P.parent/'projected').rglob('*') if p.is_file()}
assert actual==set(records)
base=verify(owner_build['original']);assert base==verify(error_build['original'])==verify(records['build.zig']['original_snapshot'])
oe=owner_build['edits'][0];ee=error_build['edit']
edits=[(oe['before'].encode(),oe['after'].encode()),(ee['old_text'].encode(),ee['new_text'].encode())]
def apply(b,order,reverse=False):
 for n in order:
  old,new=edits[n]
  if reverse:old,new=new,old
  assert b.count(old)==1
  b=b.replace(old,new,1)
 return b
owner_only=apply(base,[0]);error_only=apply(base,[1]);combined=verify(records['build.zig']['projected'])
assert owner_only==verify(owner_build['projected'])
assert error_only==verify(error_build['projected'])
assert apply(base,[0,1])==apply(base,[1,0])==combined
assert apply(combined,[1,0],True)==apply(combined,[0,1],True)==base
assert len(combined)==506940 and sha(combined)=='399BD2EF5A4360C60478C30A6AB4BD36F151CC538C93174BC3EFA603536E4A52'
assert combined.count(b'.addRunArtifact(')==base.count(b'.addRunArtifact(')
names=[]
root_results=[]
for r in d['new_roots']:
 b=verify(r['source']);assert b==verify(records[r['relative_path']]['projected'])
 found=re.findall(r'^\s*test\s+"([^"]+)"',b.decode('utf-8'),re.M)
 assert found==r['names'] and len(found)==r['declared_count']
 assert r['actual_metadata_count'] is None
 root_results.append({'relative_path':r['relative_path'],'declared_count':len(found),'names':found})
 names.extend(found)
assert len(names)==len(set(names))==45
old_control_names=[]
for r in d['new_roots'][:2]:
 old_control_names.extend(re.findall(r'^\s*test\s+"([^"]+)"',verify(owner_paths[r['relative_path']]['projected']).decode('utf-8'),re.M))
assert len(old_control_names)==owner['declared_controls']==21
assert names==old_control_names+error['controls']['names']
assert d['current_frozen_selected_groups']==63 and d['successor_group_total_preserving_all_current_groups']==66
assert d['unchanged_per_batch_group_cap']==64 and d['future_complete_batch_partition_required']
assert not d['batch_selection_or_execution_granted'] and d['future_actual_metadata_count'] is None
result={
 'schema':'pi-zig.independent-combined-file-handle-error-source-composition-peer.v1',
 'subject':pin(P),'basis_main_head':head,'qualification':'Finite byte-composition review only; accepted implementation bodies were not re-reviewed and no native/compiler/reference/test execution occurred.',
 'verdict':'No composition blocker found. Exactly the accepted 13 FileHandle paths and four non-build native Error paths; no extra projected paths or unreviewed combined bytes.',
 'path_count':17,'new_paths':8,'replaced_paths':9,'paths':results,
 'both_build_application_orders_and_both_whole_inverse_orders_exact':True,
 'build_combined':pin(Path(records['build.zig']['projected']['path'])),
 'build_delta_bytes':len(combined)-len(base),'build_install_only_insertions':2,'new_run_steps':0,
 'all_before_paths_equal_current_frozen_Main_and_pinned_git_blobs':True,
 'all_new_paths_absent_from_current_Main_and_pinned_git_tree':True,
 'selected_names_unchanged':True,'declared_controls':45,'root_results':root_results,
 'future_groups':66,'unchanged_batch_cap':64,'future_complete_batch_partition_required':True,
 'future_actual_metadata_count':None,'batch_selection_or_execution_granted':False,
 'reviewed_composition_evidence':[pin(Path(r['path'])) for r in d['composition_evidence']],
 'distinct_input_pin_count':len(pins),'pins':list(pins.values()),
 'Main_edited':False,'source_production_edits':False,'runtime_qualified':False,
 'limits':['Main remains under Root hold until independent V34 closure and separate release.','This composition peer is not new implementation, target layout, GC, native runtime, metadata or application qualification.','Existing 63 roots must be preserved and all 66 assigned to complete future batches under the unchanged 64-group cap.']
}
assert not D.exists();D.mkdir(parents=True)
p=D/'peer.json'
with p.open('x',encoding='utf-8',newline='\n') as f:json.dump(result,f,ensure_ascii=False,indent=2);f.write('\n')
print(json.dumps({'peer':pin(p),'paths':17,'new':8,'replace':9,'controls':45,'input_pins':len(pins)}))
