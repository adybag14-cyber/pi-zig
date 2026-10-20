from pathlib import Path
import hashlib,json,datetime
own=Path(r'C:\Users\adyba\pi-zig\worktrees\modules-io-resume-20261018')
packet=own/'verification/native-node-tracing-platform-sourceonly-20261020'
vendor=own/'vendor/node-v24.13.0/abseil-cpp'
def sha(b):return hashlib.sha256(b).hexdigest().upper()
def pin(p):
 b=p.read_bytes();return {'path':str(p),'bytes':len(b),'sha256':sha(b)}
manifest_path=vendor/'SOURCE-MANIFEST.json';manifest=json.loads(manifest_path.read_text())
assert pin(manifest_path)['sha256']=='0B91065B9E2B4F79929FF2245DE802AF87C01BEB2F572B274491343DC1C94706'
prefix='vendor/node-v24.13.0/abseil-cpp/'
indexed={};receipts=[];other=[]
for reference in manifest['acquisition_receipts']:
 receipt=Path(reference['path']);assert pin(receipt)==reference
 document=json.loads(receipt.read_text());receipts.append(reference)
 mixed=receipt.name=='closure-000-004-attempt1.json'
 for index,row in enumerate(document['records']):
  assert row['ok'] is True
  original=row['relative_path']
  if mixed:
   if not original.startswith(prefix):
    other.append({'receipt':str(receipt),'row_index':index,'relative_path':original,'reason':'Node utility authority row, outside Abseil vendor cohort'});continue
   normalized=original[len(prefix):];basis='worktree-relative; remove exact fixed vendor prefix'
  else:
   normalized=original;basis='Abseil vendor-root-relative; no rewrite'
  assert normalized not in indexed
  indexed[normalized]={'manifest_path':normalized,'receipt_path':str(receipt),'receipt_sha256':reference['sha256'],'row_index':index,'acquisition_relative_path':original,'acquisition_path_basis':basis,'url':row['url'],'bytes':row['bytes'],'sha256':row['sha256'],'ok':True}
assert len(indexed)==353
bindings=[]
for entry in manifest['files']:
 actual=indexed[entry['path']]
 for field in ['url','bytes','sha256']:assert actual[field]==entry[field],(entry['path'],field)
 assert actual['receipt_path']==entry['acquisition']
 b=(vendor/entry['path']).read_bytes();assert len(b)==entry['bytes'] and sha(b)==entry['sha256']
 bindings.append(actual)
assert len(bindings)==353 and len(other)==2
d={
 'schema':1,'kind':'Additive explicit binding for mixed acquisition path schemas',
 'created_utc':datetime.datetime.now(datetime.timezone.utc).isoformat(),
 'original_manifest':pin(manifest_path),'original_receipts':receipts,
 'review_negative_retained':{
  'finding':'An index comparing raw relative_path values without schema normalization could not match addresses.h from the manifest to the successful closure receipt.',
  'cause':'The first fifteen homogeneous Abseil batches use vendor-root-relative paths; the five-file closure receipt mixes Abseil headers and Node utility originals and uses worktree-relative paths.',
  'resolution':'For the closure receipt only, strip exactly vendor/node-v24.13.0/abseil-cpp/ for its three Abseil header rows. The two utility rows remain separately identified. No source bytes, original receipt or manifest is changed.',
 },
 'matched_vendor_originals':353,'mixed_closure_header_rows':3,'non_Abseil_authority_rows':other,
 'all_manifest_url_bytes_hash_and_successful_row_bindings_match':True,
 'bindings':bindings,'source_or_original_record_modified':False,
 'compiler_execution':False,'native_execution':False,'main_modified':False,'qualification':False
}
out=packet/'acquisition-path-schema-bindings.json';assert not out.exists();out.write_text(json.dumps(d,indent=2)+'\n',encoding='utf-8',newline='\n')
print(json.dumps({'receipt':pin(out),'matched_originals':len(bindings),'mixed_header_rows':[x for x in bindings if x['acquisition_path_basis'].startswith('worktree')]},indent=2))
