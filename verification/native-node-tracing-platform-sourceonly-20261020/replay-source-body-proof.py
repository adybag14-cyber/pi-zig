from pathlib import Path
import hashlib,json
packet=Path(__file__).resolve().parent
audit=packet/'source-body-audit-v2.py'
expected_audit='B05D00CD609C9E4496210F7DE81F2CABAC9B8CEAFBFD70FA2ECCDBBE6A75DABB'
expected_proof='69154F80BF1982B21A35018964F1B59D110008235B382FC261163A557354378D'
def sha(b):return hashlib.sha256(b).hexdigest().upper()
raw=audit.read_bytes();assert sha(raw)==expected_audit
text=raw.decode();marker="\npath=packet/('source-body-proof-v2.json'"
assert text.count(marker)==1
# Execute the pinned read-only body construction only. Its output-writing tail
# is excluded; no original packet or production path is changed by this replay.
namespace={}
exec(compile(text.split(marker,1)[0],str(audit),'exec'),namespace)
record=namespace['record']
replayed=(json.dumps(record,indent=2)+'\n').encode()
assert len(record['checks'])==41 and all(x['equal'] for x in record['checks'])
assert sha(replayed)==expected_proof
assert (packet/'source-body-proof-v2.json').read_bytes()==replayed
print(json.dumps({'kind':'Read-only replay of pinned 41-comparison source auditor','audit_sha256':expected_audit,'proof_sha256':sha(replayed),'checks':41,'equal':41,'byte_identical_to_sealed_proof':True,'production_or_packet_written':False,'compiler_execution':False,'preprocessor_execution':False,'native_execution':False},indent=2))
