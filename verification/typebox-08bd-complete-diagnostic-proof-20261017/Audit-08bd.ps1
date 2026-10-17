$ErrorActionPreference='Stop'
$container='C:\Users\adyba\pi-zig'
$run=Join-Path $container 'evidence/root-typebox-stack-diagnostic-08bd-v4-20261017-143801'
$parent=Join-Path $container 'evidence/typebox-stack-diagnostic-driver-prepared-20261017'
$id=Split-Path $run -Leaf
function ReadJson($p){Get-Content -Raw -LiteralPath $p|ConvertFrom-Json -Depth 70}
function Hash($p){(Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash}
function Check($ok,$message){if(!$ok){throw $message}}
function Keys($rows){@($rows|ForEach-Object{$_.relative+' '+$_.sha256})}
function Raw($path,[bool]$metadata,[int]$expected){
 $b=[IO.File]::ReadAllBytes($path);$at=0;$version=$null;$names=@();$starts=0;$results=@()
 while($at-lt$b.Length){
  Check ($b.Length-$at-ge8) 'Truncated frame header';$tag=[BitConverter]::ToUInt32($b,$at);$len=[BitConverter]::ToUInt32($b,$at+4);$at+=8
  Check ($len-le$b.Length-$at-and$len-le1MB) 'Invalid frame length'
  if($tag-eq0){Check ($null-eq$version-and$at-eq8) 'Version order';$version=[Text.Encoding]::UTF8.GetString($b,$at,$len)}
  elseif($metadata-and$tag-eq3){
   Check ($version-ceq'0.16.0'-and$names.Count-eq0-and$len-ge8) 'Metadata order';$strings=[BitConverter]::ToUInt32($b,$at);$count=[BitConverter]::ToUInt32($b,$at+4)
   Check ($count-eq$expected-and$len-eq8+8*$count+$strings) 'Metadata shape/count';$base=$at+8+8*$count
   for($i=0;$i-lt$count;$i++){$pos=[BitConverter]::ToUInt32($b,$at+8+4*$i);Check ($pos-lt$strings-and[BitConverter]::ToUInt32($b,$at+8+4*$count+4*$i)-eq0) 'Metadata offset/panic';$end=$pos;while($end-lt$strings-and$b[$base+$end]-ne0){$end++};Check ($end-lt$strings) 'Metadata string termination';$names+=[Text.Encoding]::UTF8.GetString($b,$base+$pos,$end-$pos)}
  }elseif(!$metadata-and$tag-eq5){Check ($version-ceq'0.16.0'-and$len-eq0-and$starts-eq$results.Count-and$starts-lt$expected) 'Start order';$starts++}
  elseif(!$metadata-and$tag-eq4){Check ($len-eq12-and$starts-eq$results.Count+1) 'Result order';$index=[BitConverter]::ToUInt32($b,$at);$flags=[BitConverter]::ToUInt64($b,$at+4);Check ($index-eq$results.Count) 'Result index';$results+=,[ordered]@{index=$index;flags=$flags}}
  else{throw "Unexpected protocol tag $tag"};$at+=$len
 }
 Check ($version-ceq'0.16.0') 'Missing version';if($metadata){Check ($names.Count-eq$expected) 'Incomplete metadata'}else{Check ($starts-eq$expected-and$results.Count-eq$expected) 'Incomplete runtime'}
 [ordered]@{path=$path;bytes=$b.Length;sha256=Hash $path;version=$version;names=$names;starts=$starts;results=$results}
}
function Owner($path,[int]$deadline,[int]$exitCode=0){
 $o=ReadJson $path;Check ($o.status-ceq$(if($exitCode-eq0){'passed'}else{'failed'})-and$o.exit_code-eq$exitCode-and$o.retained_handle-gt0-and$o.timeout_seconds-eq$deadline) 'Owner terminal/bounds'
 Check ($o.pid-eq$o.live_identity.pid-and$o.executable-ceq$o.live_identity.executable-and([DateTimeOffset]$o.created_utc).UtcTicks-eq([DateTimeOffset]$o.live_identity.created_utc).UtcTicks-and$o.live_identity.command_line_method-ceq'Win32_Process.CommandLine') 'Owner identity'
 Check ($o.live_identity.command_line-ceq('"'+$o.executable+'" '+($o.arguments-join' '))) 'Actual command vs intended'
 $elapsed=([DateTimeOffset]$o.completed_utc-[DateTimeOffset]$o.created_utc).TotalSeconds;Check ($elapsed-ge0-and$elapsed-le$deadline) 'Actual owner deadline'
 $rows=@(Get-CimInstance Win32_Process -Filter "ProcessId = $($o.pid)" -OperationTimeoutSec 3 -ErrorAction Stop);$method='PID absent'
 if($rows.Count){Check ($rows.Count-eq1-and$null-ne$rows[0].CreationDate-and[Math]::Abs((([DateTimeOffset]$rows[0].CreationDate)-([DateTimeOffset]$o.created_utc)).TotalMilliseconds)-gt1) 'Original identity present/conflicting';$method='PID reused with different trusted birth; original identity absent'}
 [ordered]@{receipt=$path;pid=$o.pid;creation=$o.created_utc;deadline=$deadline;elapsed=$elapsed;exit_code=$exitCode;original_absent=$true;absence_method=$method;executable=$o.executable;sha256=$o.executable_sha256;arguments=$o.arguments;actual_command_line=$o.live_identity.command_line}
}
$result=ReadJson "$run/result.json";$before=ReadJson "$run/before.json";$grant=ReadJson "$parent/$id-grant.json"
Check ($before.candidate_head-ceq'08bd3b5fa6f162fc5bc86c3af604beafdabd887a'-and$before.clean-eq$true-and$before.errors.Count-eq0) 'Exact clean recorded candidate'
Check ($result.status-ceq'failed'-and$result.postseal-eq$true-and$result.absence.native_roots.Count-eq0-and$result.controller_environment_restored-eq$true) 'Honest final negative/fullpost'
Check ($grant.execution_authorized-eq$true-and$grant.candidate_head-ceq$before.candidate_head-and$grant.driver_sha256-ceq'87054C8DF4DDAB72045EEC23BAE1E52FBA0298AF53D1F71C978AFB1B5300045D'-and$grant.grant_id-ceq$id-and$grant.runtime_outer_actual_seconds-eq120-and$grant.host_await_milliseconds-eq10000-and$grant.frame_and_GPA_execution_granted-eq$false) 'Root scope/grant'
Check ((Hash "$parent/Run-TypeBoxStackDiagnosticCapacityV4.ps1")-ceq$grant.driver_sha256) 'Original driver pin'
$authority=Join-Path $container 'evidence/durable-latest89-full-inspect-53ae-tool-prehash-20261011.json';Check ((Hash $authority)-ceq'DEE259F171F720AB2C08E8DD473975E22C876417CD62E4F016C71A7C662794EB') 'Original compiler authority'
$compiler=ReadJson $authority;$compilerKeys=@($compiler.inputs|ForEach-Object{$_.path.Substring($compiler.root.Length+1).Replace([char]92,[char]47)+' '+$_.sha256})
Check ($before.source.Count-eq10635-and$before.tree.Count-eq10635-and$before.vendor.Count-eq1336-and$before.compiler.Count-eq19546-and$before.controls.Count-eq13) 'Full seal counts'
Check (@(Compare-Object $compilerKeys (Keys $before.compiler) -CaseSensitive).Count-eq0) 'Full compiler original authority'
$seals=@(foreach($file in Get-ChildItem -LiteralPath $run -File|Where-Object{$_.Name-eq'final.json'-or$_.Name-match'^(controls|functional)-(compile|metadata|runtime)-(before|after)\.json$'}){
 $s=ReadJson $file.FullName;Check ($s.candidate_head-ceq$before.candidate_head-and$s.clean-eq$true-and$s.errors.Count-eq0) 'Seal exact head/clean/errors'
 foreach($group in @('source','tree','vendor','compiler','controls')){Check ($s.$group.Count-eq$before.$group.Count-and@(Compare-Object (Keys $before.$group) (Keys $s.$group) -CaseSensitive).Count-eq0-and@($s.$group.relative|Sort-Object -Unique -CaseSensitive).Count-eq$s.$group.Count) "Full seal drift $($file.Name) $group"}
 [ordered]@{path=$file.FullName;sha256=Hash $file.FullName;source=10635;tree=10635;vendor=1336;compiler=19546;controls=13;drift=0}
});Check ($seals.Count-eq13) 'All phase/final seals'
foreach($pin in @(@{p='vendor/quickjs/quickjs.c';h='2FA2E26E35B7D5C45D1FFD3F6F10EE3A5DE9A984738486128399A20BD8E4D88D'},@{p='vendor/quickjs/quickjs.h';h='341CF06F8041B8311D49767026C85C7B859BCFEE3088380F3FFE6D77527052AB'})){$r=@($before.source|Where-Object relative -CEQ $pin.p);Check ($r.Count-eq1-and$r[0].sha256-ceq$pin.h) 'C2 source pin'}
foreach($p in $before.controls|Where-Object{$_.path-notmatch '\.pi-zig-workspace\.json$'}){Check ((Hash $p.path)-ceq$p.sha256) "Current immutable control differs $($p.path)"}
$groups=@();$owners=@();$artifacts=@()
foreach($spec in @(@{name='controls';count=10;flags='0,0,0,0,0,0,0,0,0,0';target='build-native-typebox-stack-observer'},@{name='functional';count=4;flags='0,0,1,0';target='build-native-typebox-production-source'})){
 $name=$spec.name;$selection=ReadJson "$run/$name-selected-tests.json";$command=ReadJson "$run/$name-commands.json";$meta=Raw "$run/$name-metadata.stdout.bin" $true $spec.count;$raw=Raw "$run/$name-runtime.stdout.bin" $false $spec.count
 Check (($meta.names-join'|')-ceq($selection.tests-join'|')-and($meta.names-join'|')-ceq($command.planned_exact_names-join'|')) 'Exact metadata/selection/command names/order'
 Check (($raw.results.flags-join',')-ceq$spec.flags) 'Actual runtime flags'
 $canonical=ReadJson "$run/$name-runtime.results.json";Check ($canonical.expected-eq$spec.count-and$canonical.started-eq$spec.count-and$canonical.completed-eq$spec.count-and($canonical.results.flags-join',')-ceq$spec.flags) 'Raw/canonical agreement'
 Check ((Get-Item -LiteralPath "$run/$name-metadata.stderr.log").Length-eq0) 'Metadata stderr'
 if($name-ceq'controls'){Check ((Get-Item -LiteralPath "$run/$name-runtime.stderr.log").Length-eq0) 'Control runtime stderr'}
 $installed=ReadJson "$run/$name-final-artifacts.json";Check ($installed.installed.Count-eq2-and$installed.errors.Count-eq0-and$installed.pe.reserved_stack_bytes-eq16777216-and$installed.pe.Engine_guard_bytes-eq1048576) 'Artifact roles/PE/guard'
 foreach($entry in $installed.installed){Check ((Get-Item -LiteralPath $entry.path).Length-eq$entry.bytes-and(Hash $entry.path)-ceq$entry.sha256) 'Current installed artifact'}
 $exe=@($installed.installed|Where-Object path -Like '*.exe')[0];$pdb=@($installed.installed|Where-Object path -Like '*.pdb')[0];Check ($selection.binary-ceq$exe.path-and$selection.binary_sha256-ceq$exe.sha256-and$canonical.binary_sha256-ceq$exe.sha256) 'Metadata/runtime installed binary binding'
 $bytes=[IO.File]::ReadAllBytes($exe.path);$pe=[BitConverter]::ToUInt32($bytes,60);Check ([BitConverter]::ToUInt32($bytes,$pe)-eq0x4550-and[BitConverter]::ToUInt16($bytes,$pe+24)-eq0x20b-and[BitConverter]::ToUInt64($bytes,$pe+96)-eq16777216) 'Actual PE32+ stack reserve'
 foreach($file in Get-ChildItem -LiteralPath $run -File|Where-Object{$_.Name-like"$name-*-artifacts.json"}){$snapshot=ReadJson $file.FullName;Check ($snapshot.errors.Count-eq0-and(($snapshot.installed|ForEach-Object{$_.path+' '+$_.bytes+' '+$_.sha256})-join'|')-ceq(($installed.installed|ForEach-Object{$_.path+' '+$_.bytes+' '+$_.sha256})-join'|')) 'Installed artifact phase drift';foreach($cached in $snapshot.cached_executables){Check ((Hash $cached.path)-ceq$cached.sha256) 'Recorded cache executable content changed'}}
 $artifacts+=,[ordered]@{group=$name;exe=$exe;pdb=$pdb;pe_stack_reserve=16777216;engine_guard=1048576;cached_content_sealed=$false}
 foreach($phase in @(@{name='compile';deadline=1320},@{name='metadata';deadline=30},@{name='runtime';deadline=120})){
  $prefix="$name-$($phase.name)";$owner=Owner "$run/$prefix.json" $phase.deadline;$o=ReadJson "$run/$prefix.json";$admit=ReadJson "$run/$prefix-admission.json";Check ($admit.status-ceq'admitted'-and$admit.probe.free_kib-ge16777216-and$admit.probe.native_roots-eq0-and$admit.accepted_elapsed_seconds-lt54) 'Per-phase admission'
  if($phase.name-ceq'compile'){Check (($o.arguments-join'|')-ceq($command.compile-join'|')-and$o.arguments[1]-ceq$spec.target-and$o.arguments-contains'-j1'-and$o.arguments-contains'-Duse-llvm=true'-and$o.arguments-contains'-Doptimize=Debug'-and$o.executable_sha256-ceq'086CE9D47BA42F33A514E1A6E04EB1D4A8FA1D75E0868E0213CAAD447C91E864') 'Actual compile command'}else{Check ($o.executable-ceq$exe.path-and$o.executable_sha256-ceq$exe.sha256-and($o.arguments-join'|')-ceq'--listen=-') 'Actual protocol binary/command'}
  $absence=ReadJson "$run/$prefix-absence.json";Check ($absence.status-ceq'closed'-and$absence.evidence.current_owner_pid_present-eq0-and$absence.evidence.current_owned_descendants.Count-eq0) 'Original phase absence'
  foreach($out in $absence.evidence.raw_outputs){Check ((Get-Item -LiteralPath $out.path).Length-eq$out.bytes-and(Hash $out.path)-ceq$out.sha256) 'Retained raw output binding'}
  $owners+=,$owner
 }
 $groups+=,[ordered]@{group=$name;metadata=$meta;raw_runtime=$raw;named=($spec.count-1);anonymous_storage=1;status=$(if($name-ceq'controls'){'passed'}else{'failed'})}
}
$stderr=Get-Content -Raw -LiteralPath "$run/functional-runtime.stderr.log";Check ($stderr.Contains('TYPEBOX_COMPILE_SOURCE_PARITY cases=80')-and$stderr.Contains('TYPEBOX_PROVIDER_SCHEMA_SOURCE_PARITY cases=52')) 'Source80/52 completion markers'
$line=@($stderr-split"`r?`n"|Where-Object{$_-like'Actual TypeBox Source396 replay: Error: *'});Check ($line.Count-eq1) 'One raw Source396 mismatch';$mismatch=$line[0].Substring('Actual TypeBox Source396 replay: Error: '.Length)|ConvertFrom-Json -Depth 48
Check ($mismatch.index-eq391-and$mismatch.actual.metrics.assign-eq27-and$mismatch.actual.metrics.create-eq180-and$mismatch.expected.metrics.assign-eq129-and$mismatch.expected.metrics.create-eq792) 'Exact mismatch metrics'
Check (($mismatch.actual.value[1]|ConvertTo-Json -Depth 30 -Compress)-ceq($mismatch.expected.value[1]|ConvertTo-Json -Depth 30 -Compress)) 'Recovered literal unchanged'
$tracePath="$run/stack-observation.json"
Check ((Get-Item -LiteralPath $tracePath).Length-eq94433597-and(Hash $tracePath)-ceq'A8564B76FD61326144CF3FB760EFCB78E9293C30214253A15C5CB1B9B0178C43') 'Original complete trace bytes'
$bytes=[IO.File]::ReadAllBytes($tracePath)
$document=[Text.Json.JsonDocument]::Parse([ReadOnlyMemory[byte]]::new($bytes))
$stack=[Collections.Generic.List[object]]::new();$callbacks=[Collections.Generic.HashSet[long]]::new()
$sequence=0L;$enters=0L;$returns=0L;$failures=0L;$roots=0L;$maxDepth=0L;$maxSpan=0L
try{
 $trace=$document.RootElement
 foreach($pair in @(@{p='capacity';v=1048576},@{p='used';v=739888},@{p='attempted';v=739888},@{p='dropped';v=0},@{p='remaining_depth';v=0},@{p='maximum_callback_depth';v=206},@{p='guard_flags';v=0})){Check ($trace.GetProperty($pair.p).GetInt64()-eq$pair.v) 'Complete diagnostic header'}
 Check ($trace.GetProperty('complete').GetBoolean()-and$trace.GetProperty('diagnostic_instrumented_candidate').GetBoolean()-and!$trace.GetProperty('production_stack_peak_measured').GetBoolean()) 'Diagnostic only completion'
 $anchor=$trace.GetProperty('load_anchor_address').GetInt64()
 foreach($event in $trace.GetProperty('events').EnumerateArray()){
  $sequence++;$number=$event.GetProperty('sequence').GetInt64();$depth=$event.GetProperty('depth').GetInt64();$callback=$event.GetProperty('callback').GetInt64();$state=$event.GetProperty('function_state').GetInt64();$frame=$event.GetProperty('frame_address').GetInt64();$kind=$event.GetProperty('event').GetInt32()
  Check ($number-eq$sequence-and$callback-gt0-and$state-gt0-and$frame-gt0-and$kind-in@(0,1,2)) 'Event sequence/identity/legend'
  [void]$callbacks.Add($callback)
  if($kind-eq0){
   Check ($depth-eq$stack.Count+1) 'Actual enter depth';if($stack.Count-eq0){$roots++}else{Check ($frame-lt$stack[$stack.Count-1].frame) 'Downward nested frame addresses'}
   if($stack.Count-gt0){$maxSpan=[Math]::Max($maxSpan,$stack[0].frame-$frame)}
   $stack.Add([pscustomobject]@{depth=$depth;callback=$callback;state=$state;frame=$frame});$enters++;$maxDepth=[Math]::Max($maxDepth,$depth)
  }else{
   Check ($stack.Count-gt0-and$depth-eq$stack.Count) 'Actual unwind depth';$top=$stack[$stack.Count-1]
   Check ($callback-eq$top.callback-and$state-eq$top.state-and$frame-eq$top.frame) 'Exact enter/leave identity'
   $stack.RemoveAt($stack.Count-1);$returns++;if($kind-eq2){$failures++}
  }
 }
 Check ($sequence-eq739888-and$enters-eq369944-and$returns-eq369944-and$failures-eq263-and$roots-eq2665-and$stack.Count-eq0-and$maxDepth-eq206-and$maxSpan-eq1045136-and$callbacks.Count-eq641) 'Complete event grammar counts'
}finally{$document.Dispose();$bytes=$null}
$validation=ReadJson "$run/stack-observation-validation.json"
Check ($validation.status-ceq'complete_instrumented_observation_only'-and$validation.errors.Count-eq0-and$validation.event_grammar_complete-eq$true) 'Honest diagnostic-only observation status'
$traceRecord=[ordered]@{path=$tracePath;sha256=Hash $tracePath;bytes=94433597;capacity=1048576;used=739888;attempted=739888;dropped=0;complete=$true;full_event_grammar_independently_checked=$true;enters=$enters;returns=$returns;native_error_returns=$failures;root_invocations=$roots;distinct_callbacks=$callbacks.Count;maximum_callback_depth=$maxDepth;maximum_observed_entry_span_instrumented_bytes=$maxSpan;remaining_depth=0;guard_flags=0;row_association_claim=$false;production_peak_claim=$false}
$symbols=Join-Path $container 'evidence/root-typebox-08bd-matching-symbols-20261017'
$rawSymbols="$symbols/llvm.stdout.bin"
Check ((Get-Item -LiteralPath $rawSymbols).Length-eq48885076-and(Hash $rawSymbols)-ceq'5DF5CEE728F8DA48DFB82D4910D24BC3FA0216E4F6DABA83EE060F9FC5D384DE') 'Retained matching PDB dump'
$sb=ReadJson "$symbols/before.json";$sa=ReadJson "$symbols/after.json"
Check (@(Compare-Object @($sb|ForEach-Object{$_.path+' '+$_.bytes+' '+$_.sha256}) @($sa|ForEach-Object{$_.path+' '+$_.bytes+' '+$_.sha256}) -CaseSensitive).Count-eq0) 'PDB/tool full pre-post pins'
foreach($row in $sb){Check ((Get-Item -LiteralPath $row.path).Length-eq$row.bytes-and(Hash $row.path)-ceq$row.sha256) 'Retained PDB/tool payload binding'}
$llvmOwner=Owner "$symbols/llvm.json" 60
Check ($llvmOwner.sha256-ceq'EBEFFD8BC9B9098C14FD087FD4CE7671E755B7570A5326AA625B8F9C01907A04'-and($llvmOwner.arguments-join'|')-ceq('dump|-symbols|-section-headers|'+$validation.pdb_sha256).Replace($validation.pdb_sha256,"$run\functional-installed\bin\test.pdb")) 'Exact retained LLVM argv'
Check ((Get-Item -LiteralPath "$symbols/llvm.stderr.log").Length-eq0) 'Retained LLVM stderr'
$correlationPath=Join-Path $container 'evidence/root-typebox-08bd-independent-correlation-20261017.json'
Check ((Hash $correlationPath)-ceq'E8DB5D80CBAFE1FA230D379717FB6A940DE5776F542509EB361EBDFC41E97B75') 'Exact independent Min correlation'
$correlation=ReadJson $correlationPath
Check ($correlation.compiled_source_head-ceq$before.candidate_head-and$correlation.actual_pair_identity.guid_and_age_match-eq$true-and$correlation.anchor.recorded_runtime_address-eq$anchor-and$correlation.independent_compact_scan.distinct_callback_addresses-eq641-and$correlation.independent_compact_scan.unique_exact_procedure_start_matches-eq641-and$correlation.limits.production_stack_peak_measured-eq$false) 'Bounded independent correlation scope'
foreach($input in $correlation.inputs){$path=Join-Path (Join-Path $container 'evidence') $input.path;Check ((Hash $path)-ceq$input.sha256) 'Min correlation raw/source input binding'}
$map=ReadJson (Join-Path $container 'evidence/root-typebox-08bd-trace-analysis-20261017/callback-map.json')
Check ($map.Count-eq641) 'Retained callback map count'
foreach($row in $map){Check ($callbacks.Contains([long]$row.address)-and$row.status-ceq'unique_exact_start'-and$row.frames.Count-eq1-and$row.address-$correlation.anchor.derived_loaded_image_base-eq$row.rva) 'Trace exact-address callback map binding'}
$symbolRecord=[ordered]@{raw_dump=$rawSymbols;raw_dump_sha256=Hash $rawSymbols;raw_dump_bytes=48885076;llvm_owner=$llvmOwner;Min_correlation=$correlationPath;Min_correlation_sha256=Hash $correlationPath;all641_trace_addresses_bound_to_retained_exact_start_map=$true;Min_RSDS_PDB_guid_age_closure_retained=$true;Min_static_frame_parser_not_rerun=$true;no_new_LLVM_or_native_jobs=$true}
$outer=Owner "$parent/$id-outer.json" 4000 1;$outerRecord=ReadJson "$parent/$id-outer.json";Check ($outerRecord.arguments[4]-ceq"$parent\Run-TypeBoxStackDiagnosticCapacityV4.ps1"-and$outerRecord.arguments[6]-ceq"$parent\$id-grant.json") 'Exact external controller argv'
Check ((Hash "$parent/$id-outer.stdout.bin")-ceq(Hash "$run/result.json")) 'Outer rawstdout exact result bytes'
$controller=ReadJson "$run/controller.json";Check ($controller.controller_pid-eq$outer.pid-and$controller.live.Count-eq1-and$controller.live[0].CommandLine-ceq$outer.actual_command_line) 'Controller/outer identity'
$env=ReadJson "$run/diagnostic-runtime-environment.json";Check ($env.restored.present-eq$false-and$env.prior.present-eq$false-and$env.value_during_child-ceq$tracePath.Replace('/','\')) 'Scoped diagnostic environment'
$receipt=[ordered]@{status='independently_audited_complete_instrumentation_control10_pass_functional_negative';candidate=$before.candidate_head;source_count=10635;compiler_count=19546;vendor_count=1336;groups=$groups;full_phase_final_seals=$seals;artifacts=$artifacts;owners=$owners;outer=$outer;functional_mismatch=$mismatch;trace=$traceRecord;symbols=$symbolRecord;limitations=@('Diagnostic instrumented candidate only; no production stack improvement claim','Trace complete for diagnostic instrumentation only; no Source row association or production peak claim','No full TypeBox396 pass, GPA, runtime restoration or full Pi qualification','Compiler caches explicitly mutable/unsealed; only recorded executable bindings checked','Historical layout bytes pinned by original seals; current mutable workspace layout is not rerun authority');jobs_run_by_auditor=$false;completed_utc=[DateTimeOffset]::UtcNow.ToString('o')}
ConvertTo-Json -InputObject $receipt -Depth 60|Set-Content -LiteralPath (Join-Path $PSScriptRoot 'audit.json') -Encoding utf8NoBOM
[pscustomobject]@{status=$receipt.status;path=(Join-Path $PSScriptRoot 'audit.json');sha256=Hash (Join-Path $PSScriptRoot 'audit.json');controls=10;functional_flags='0,0,1,0';seals=$seals.Count;owners=$owners.Count;trace_complete=$true}|ConvertTo-Json
