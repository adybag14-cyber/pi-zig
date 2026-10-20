from pathlib import Path
import hashlib,json,re
w=Path("C:\\Users\\adyba\\pi-zig\\worktrees\\sdk-owners-resume-20261018");p=Path("C:\\Users\\adyba\\pi-zig\\worktrees\\sdk-owners-resume-20261018\\verification\\native-file-handle-transfer-sourceonly-20261020")
def info(q):
 b=q.read_bytes();return {'path':str(q),'bytes':len(b),'sha256':hashlib.sha256(b).hexdigest().upper()}
def excerpt(label,rel,a,b,required=None):
 q=p/rel;raw=q.read_bytes();lines=raw.splitlines(keepends=True)
 assert 1<=a<=b<=len(lines),(label,a,b,len(lines))
 block=b''.join(lines[a-1:b]);text=block.decode()
 if required:assert required in text,(label,required)
 return {'id':label,'source':info(q),'first_line':a,'last_line':b,'bytes':len(block),'sha256':hashlib.sha256(block).hexdigest().upper(),'text':text}
excerpts=[]
def add(label,rel,a,b,required=None):excerpts.append(excerpt(label,rel,a,b,required))
add('node.fs.global_sync_trace','authority/node_file.v24.13.cc',148,159,'FS_SYNC_TRACE_BEGIN')
add('node.fs.actual_new','authority/node_file.v24.13.cc',228,249,'fd_constructor_template')
add('node.fs.destructor','authority/node_file.v24.13.cc',281,285,'Close()')
add('node.fs.transfer_mode','authority/node_file.v24.13.cc',298,302,'reading_ || closing_ || closed_')
add('node.fs.transfer_send','authority/node_file.v24.13.cc',304,309,'closed_ = true')
add('node.fs.transfer_native_storage','authority/node_file.v24.13.cc',311,322,'uv_fs_close(nullptr, &close_req, fd_, nullptr)')
add('node.fs.transfer_receive','authority/node_file.v24.13.cc',324,334,'fd_ = -1')
add('node.fs.full_template','authority/node_file.v24.13.cc',3959,3968,'StreamBase::AddMethods')
add('node.fs.transfer_class','authority/node_file.v24.13.h',374,396,'int fd_')
add('node.base.transfer_mode','authority/base_object.v24.13.h',142,176,'kTransferable = 1 << 0')
add('node.base.pointer_contract','authority/base_object.v24.13.h',256,263,'not thread')
add('node.base.pointer_destruction','authority/base_object-inl.v24.13.h',171,201,'get()->increase_refcount()')
add('node.base.pointer_copy_move','authority/base_object-inl.v24.13.h',204,246,'data_(other.data_)')
add('node.base.make_weak','authority/base_object.v24.13.cc',52,72,'persistent_handle_.Reset()')
add('node.base.refcount_and_cleanup','authority/base_object.v24.13.cc',129,154,'persistent_handle_.ClearWeak()')
add('node.messaging.transfer_contract','authority/node_messaging.v24.13.h',22,43,'should not hold any more Isolate-specific data')
add('uv.windows.admission','authority/libuv/src/win/fs.c',74,97,'cb != NULL')
add('uv.windows.request_fields','authority/libuv/src/win/fs.c',397,410,'req->loop = loop')
add('uv.windows.actual_close','authority/libuv/src/win/fs.c',668,695,'if (fd > 2)')
add('uv.windows.cleanup','authority/libuv/src/win/fs.c',3192,3221,'UV_FS_CLEANEDUP')
add('uv.windows.close_entry','authority/libuv/src/win/fs.c',3241,3245,'POST')
add('uv.unix.request_fields','authority/libuv/src/unix/fs.c',90,104,'req->loop = loop')
add('uv.unix.admission','authority/libuv/src/unix/fs.c',139,155,'cb != NULL')
add('uv.unix.actual_close','authority/libuv/src/unix/fs.c',158,167,'uv__close_nocancel')
add('uv.unix.close_entry','authority/libuv/src/unix/fs.c',1814,1821,'if (cb != NULL)')
add('uv.unix.cleanup','authority/libuv/src/unix/fs.c',2239,2269,'req->ptr = NULL')
add('uv.request_init','authority/libuv/src/uv-common.h',344,358,'UV_REQ_INIT')
add('uv.canonical_fs_api','authority/libuv/include/uv.h',1462,1466,'uv_fs_close')
add('libcpp.native_new_retry','authority/zig-0.16/lib/libcxx/src/new.cpp',30,51,'std::get_new_handler')
add('libcpp.bad_alloc_without_exceptions','authority/zig-0.16/lib/libcxx/src/new_helpers.cpp',20,26,'_LIBCPP_VERBOSE_ABORT')
add('libcpp.bad_alloc_declaration','authority/zig-0.16/lib/libcxx/include/__new/exceptions.h',62,70,'__throw_bad_alloc')
add('zig.native_thread_spawn','authority/zig-0.16/lib/std/Thread.zig',344,351,'Impl.spawn')
add('zig.native_thread_join','authority/zig-0.16/lib/std/Thread.zig',365,372,'self.impl.join')
add('host.standard_allocation','support/src/extensions/native_node_standard_allocator.hpp',24,41,'allocateStandard')
add('host.native_prefix_allocation','support/src/extensions/native_simdjson_memory.cpp',13,75,'pi_js_release_memory_owner(owner)')
add('host.memory_owner_atomics','support/src/extensions/engine_abi.c',20,55,'memory_order_acq_rel')
add('host.memory_owner_create_and_observe','support/src/extensions/engine_abi.c',395,437,'pi_js_native_memory_used')
add('host.diagnostic_scope','support/src/extensions/native_node_diagnostic_context.hpp',1,25,'DiagnosticContextScope')
add('host.diagnostic_tls','support/src/extensions/native_node_diagnostic_context.c',1,21,'_Thread_local')
add('host.actual_state_native_refs','support/src/extensions/native_node_async_wrap_state.zig',404,452,'pub fn releaseNative')
add('host.actual_handle_constructor','support/src/extensions/native_node_file_handle_owner.zig',149,220,'templates.newInstance')
add('host.actual_handle_retire','support/src/extensions/native_node_file_handle_owner.zig',96,145,'self.binding_data = null')
add('host.actual_template_boundary','support/src/extensions/native_node_async_wrap.zig',142,146,'ActualFileHandleCallbackTemplateRequired')
for rel in ['src/extensions/native_node_file_handle_transfer.h','src/extensions/native_node_file_handle_transfer.cpp','src/extensions/native_node_file_handle_transfer.zig']:
 q=p/'production'/rel
 add('selected.'+q.suffix.lstrip('.'),'production/'+rel,1,len(q.read_bytes().splitlines()))
ids={x['id'] for x in excerpts};assert len(ids)==len(excerpts)
def row(name,authority,selected,behavior,limit=None):
 assert set(authority)<=ids
 return {'operation':name,'authority_excerpts':authority,'selected':selected,'preserved_behavior':behavior,'qualification_limit':limit}
rows=[
row('Transfer admission',['node.fs.transfer_mode','node.base.transfer_mode'],'Zig getTransferMode','Reads the actual Handle.read_state reading/closing/closed fields. Returns only original values 0 and 1. current_read by itself is not a new transfer prohibition.'),
row('Sender transition',['node.fs.transfer_send'],'Zig transferForMessaging','Original admission CHECK is retained. Actual native allocation completes before the only mutation closed=true. fd, current_read, offsets, binding, context frame and stream are not reset or copied.','The same-engine validation is a bounded host API precondition, not an added Node transfer policy. Worker dispatcher is still absent.'),
row('Native descriptor owner',['node.fs.transfer_class','node.fs.transfer_native_storage','node.messaging.transfer_contract'],'C++ PiNodeFileHandleTransferData','Opaque C++ packet stores the real fd member and mandatory process-lifetime code addresses; copy construction/assignment is deleted. Allocation prefix owns native memory independently. No JS value, Engine, Environment, service or lease is in the packet.','This selected opaque ABI is not the full original worker TransferData/MemoryRetainer virtual interface, serializer broker or memory tracker assembly.'),
row('Native destructor',['node.fs.transfer_native_storage','uv.windows.admission','uv.windows.request_fields','uv.windows.actual_close','uv.windows.cleanup','uv.windows.close_entry','uv.unix.admission','uv.unix.close_entry','uv.unix.actual_close','uv.unix.cleanup','uv.request_init','uv.canonical_fs_api'],'C++ destructor','Exact strict fd>0 gate, caller-owned canonical uv_fs_t, original CHECK_NE, begin trace, actual uv_fs_close(NULL,req,fd,NULL), original CHECK_EQ 0, end trace then uv_fs_req_cleanup. No async registration, synthetic completion or service allocation.','No fd0 policy repair. Windows original fs__close fd<=2 behavior also stays intact. Fatal close failure is not dynamically exercised in these source controls.'),
row('Global tracing dependency',['node.fs.global_sync_trace'],'H PiNodeFileHandleTransferTrace and Zig Trace','Two mandatory process-lifetime function entrypoints must each consult the real global fs,sync category and original fs.sync.close event at invocation time. No captured Environment/raw callback data or no-op production default.','Current tracing event ABI packet lacks installed global FS begin/end wrapper and Agent bootstrap. Test observation callbacks do not provide or qualify it.'),
row('Native allocation lifetime',['libcpp.native_new_retry','libcpp.bad_alloc_without_exceptions','libcpp.bad_alloc_declaration','host.standard_allocation','host.native_prefix_allocation','host.memory_owner_atomics','host.memory_owner_create_and_observe'],'C++ operator new/delete','Existing allocateStandard keeps new-handler retry and native bad_alloc policy. Each successful prefix atomically retains and charges the actual memory domain; delete releases its prefix charge and last owner without accessing a retired Engine.','Allocation failure remains the native library policy; no JavaScript Error shortcut or injected fake allocator is installed.'),
row('Synchronous diagnostic admission',['host.diagnostic_scope','host.diagnostic_tls'],'All four C ABI functions','DiagnosticContextScope is the first local in every C ABI body. Borrowed caller context lives only for the synchronous call; null masks outer admission. Native allocation scope is nested inside it.','No context is retained across messages/threads. Callers must not supply a retired context pointer.'),
row('Unique packet movement',['node.messaging.transfer_contract'],'Zig Owned.move/deinit/deserialize','move clears the old slot. deinit clears the slot before native delete. deserialize consumes the caller slot immediately and always deletes the native packet on exit, corresponding to the source unique_ptr self parameter.','Zig aggregate move-only ownership remains caller discipline; copying Owned by value outside move is not an authorized duplication operation.'),
row('Missing receiver BindingData',['node.fs.transfer_receive','node.messaging.transfer_contract'],'Zig Owned.deserialize','Actual binding.get(registry) returns null when its real weak BindingData is gone; packet is consumed and native destructor closes fd>0. No replacement BindingData is fabricated.','Registry/Scope same-engine validation is a host precondition. Cross-environment or invalid-context registry inputs are not claimed as original-policy cases.'),
row('Receiver ownership handoff',['node.fs.transfer_receive','node.fs.actual_new','host.actual_handle_constructor','host.actual_template_boundary','node.fs.full_template'],'Zig Owned.deserialize','Takes the actual native fd, writes packet fd=-1 before the real absent-object Handle.create path, supplies no offset/length override and does not restore packet ownership if later construction fails.','Full FileHandle constructor/StreamBase::AddMethods template remains missing. The selected host error is an explicit dependency boundary, not an assertion that Node New always fails or an alternative production receiver.'),
row('Actual strong receiver edge',['node.base.pointer_destruction','node.base.pointer_copy_move','node.base.refcount_and_cleanup','node.base.make_weak','node.base.pointer_contract','host.actual_state_native_refs','host.actual_handle_retire'],'Zig StrongHandle and successful receiver tail','Successful actual Handle.create is retained before the native Scope releases its local wrapper. clone increments the SAME State native references and real strong persistent; move clears the prior pointer; deinit releases that same edge, allowing actual detach retirement or return to weak.','StrongHandle stays on the receiving Engine thread, just as source BaseObjectPtr is not thread-safe. The cross-thread control moves only the independent native descriptor packet, never StrongHandle. Successful template deserialization awaits the genuine template.'),
row('Focused descriptor observations',['uv.windows.actual_close','zig.native_thread_spawn','zig.native_thread_join','host.memory_owner_atomics'],'Thirteen selected source controls','Existing fixture owns real descriptors and native Handle/BindingData/request/service/immediate objects. Assertions inspect actual fstat status, queued read completion, real memory-domain counts, native TLS admission, actual pending exception identity and real State strong references.','Controls explicitly select fd>2, use labeled process trace observers and present-object constructor. No compiled/runtime acceptance is implied.')]
inventory=json.loads((p/'dependency-inventory.json').read_text(encoding='utf-8'))
authority_files=[info(q) for q in sorted((p/'authority').rglob('*')) if q.is_file() and q.suffix not in ['.json']]
control_rows=[]
test_map=[
['node.fs.transfer_send','node.fs.transfer_mode'],
['node.fs.transfer_mode','node.fs.transfer_send'],
['node.fs.transfer_mode'],
['node.fs.transfer_mode'],
['node.fs.transfer_native_storage','host.native_prefix_allocation'],
['node.fs.destructor','node.fs.transfer_native_storage'],
['host.native_prefix_allocation','host.memory_owner_atomics'],
['node.messaging.transfer_contract','host.memory_owner_atomics','zig.native_thread_join'],
['host.diagnostic_scope','host.diagnostic_tls'],
['host.diagnostic_scope','host.diagnostic_tls'],
['node.fs.transfer_receive'],
['node.fs.transfer_receive','node.fs.actual_new','host.actual_template_boundary'],
['node.base.pointer_copy_move','node.base.refcount_and_cleanup','host.actual_state_native_refs']]
for name,refs in zip(inventory['named_declarations'],test_map,strict=True):
 control_rows.append({**name,'authority_excerpts':refs,'selected_source':info(p/'controls-selected/src/native_node_file_handle_transfer_test.zig')})
result={
 'schema':'pi-zig.file-handle-transfer-source-map.v1','source_only':True,
 'primary_version':'Node v24.13.0 plus its exact vendored libuv, and project pinned Zig 0.16 libc++ source',
 'authorities':authority_files,'source_excerpts':excerpts,'semantic_mapping':rows,
 'control_source_map':control_rows,'source_declared_controls':13,'future_actual_metadata_count':None,
 'no_complete_FileHandle_or_worker_messaging_claim':True,
 'explicit_open_dependencies':['Complete original StreamBase::AddMethods and FileHandle stored constructor template','Actual worker message transfer broker and receiving realm dispatch, including original worker::TransferData/MemoryRetainer integration','Real global FS synchronous tracing entrypoints and process Agent bootstrap','Receiver inputs supplied by real Environment/service/immediate/allocation/hook-policy bootstrap','Separately authorized compiler/build/runtime validation'],
 'compiler_executed':False,'native_executed':False,'reference_executed':False}
q=p/'source-map.json';raw=(json.dumps(result,indent=2)+'\n').encode()
with q.open('xb') as f:f.write(raw)
print(json.dumps({'source_map':info(q),'authority_files':len(authority_files),'excerpts':len(excerpts),'semantic_rows':len(rows),'control_rows':len(control_rows)},indent=2))
