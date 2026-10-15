param([string]$Bundle=$PSScriptRoot)
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath($Bundle).TrimEnd([IO.Path]::DirectorySeparatorChar)
$prefix=$root+[IO.Path]::DirectorySeparatorChar
function Require([bool]$Condition,[string]$Message){if(!$Condition){throw $Message}}
function Local-Path([string]$Relative){
 Require (![IO.Path]::IsPathRooted($Relative)) 'Manifest must use relative paths'
 $path=[IO.Path]::GetFullPath((Join-Path $root $Relative))
 Require ($path.StartsWith($prefix,[StringComparison]::OrdinalIgnoreCase)) 'Manifest path escapes bundle'
 return $path
}
function Json([string]$Relative){return Get-Content -Raw -LiteralPath (Local-Path $Relative)|ConvertFrom-Json}
function Evidence-Json([string]$Name){return Json ('payloads/evidence/'+$Name+'.json')}
function Owner([string]$Name,[string]$Status,[string]$ExecutableSha){
 $owner=Evidence-Json $Name
 Require ($owner.status -ceq $Status) "Wrong terminal status: $Name"
 Require ($owner.identity_captured -eq $true) "Raw process identity absent: $Name"
 Require ($owner.executable_sha256 -ceq $ExecutableSha) "Executable identity differs: $Name"
 Require ($owner.pid -gt 0 -and $owner.command_line -and $owner.created_utc -and $owner.completed_utc) "Owner identity incomplete: $Name"
 if($Status -ceq 'passed'){Require ($owner.exit_code -eq 0) "Nonzero passing owner: $Name"}
 else{Require ($owner.exit_code -ne 0) "Failed owner missing nonzero exit: $Name"}
}
function Native-Post([string]$Name,[string]$Candidate,[string]$Runtime){
 $post=Evidence-Json ($Name+'-posthash')
 Require ($post.candidate -ceq $Candidate) "Candidate identity differs: $Name"
 Require ($post.compile -ceq 'passed' -and $post.runtime -ceq $Runtime) "Pair terminal state differs: $Name"
 foreach($field in @('source_drift','tool_drift','control_drift')){Require ($post.$field -eq 0) "Captured drift in $Name/$field"}
 Require ($post.source -eq 6323 -and $post.source_after -eq 6323 -and $post.tools -eq 19546 -and $post.controls -eq 9) "Full native inventory missing: $Name"
 $expected=@{source=1968;dependencies=31064;node_tools=1774}
 Require (@($post.latest_source_references).Count -eq 3) "Full Source references missing: $Name"
 foreach($reference in $post.latest_source_references){Require ($expected[$reference.name] -eq $reference.files -and $reference.drift -eq 0) "Source cohort posthash differs: $Name"}
 if($post.PSObject.Properties.Name -contains 'process_artifact_drift'){Require ($post.process_artifact_drift -eq 0) "Built artifact drift: $Name"}
 $before=Evidence-Json ($Name+'-source-before')
 Require (@($before).Count -eq 6323) "Candidate prehash inventory missing: $Name"
}
$manifestPath=Local-Path 'proof-manifest.json'
$expectedManifest=((Get-Content -Raw -LiteralPath (Local-Path 'proof-manifest.sha256')).Trim() -split '\s+')[0]
Require ((Get-FileHash -LiteralPath $manifestPath).Hash -ceq $expectedManifest) 'Proof manifest identity differs'
$manifest=Json 'proof-manifest.json'
Require ($manifest.schema_version -eq 1 -and $manifest.qualified_candidate -ceq '039f31088beaa1f42252bcd6f1df1ac67c5a53f8') 'Unexpected proof authority'
Require ($manifest.payload_files -eq @($manifest.files).Count) 'Proof manifest inventory differs'
$listed=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
$shaSet=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
foreach($row in $manifest.files){
 Require ($listed.Add($row.path)) "Duplicate manifest path: $($row.path)"
 $path=Local-Path $row.path
 Require (Test-Path -LiteralPath $path -PathType Leaf) "Payload absent: $($row.path)"
 Require ((Get-Item -LiteralPath $path).Length -eq $row.bytes) "Payload size differs: $($row.path)"
 Require ((Get-FileHash -LiteralPath $path).Hash -ceq $row.sha256) "Payload SHA256 differs: $($row.path)"
 [void]$shaSet.Add($row.sha256)
}
foreach($file in Get-ChildItem -LiteralPath $root -Recurse -Force -File){
 $relative=[IO.Path]::GetRelativePath($root,$file.FullName).Replace('\','/')
 if($relative -in @('proof-manifest.json','proof-manifest.sha256')){continue}
 Require ($listed.Contains($relative)) "Unmanifested bundle file: $relative"
}
$source=Json 'payloads/evidence/ui-overlay-ae7-source12-first-20261015-output.json'
Require ($source.sourceCommit -ceq 'ae7b16d43b7c78c5b6fa3213fdd1215bb339729d' -and @($source.rows).Count -eq 12) 'Genuine Source12 scope differs'
Require ($source.actualNode.version -ceq 'v24.14.0' -and $source.methodSha256 -ceq 'e47f572a19acf40c8df3c6efaea9bc37ef09514dcfa430a1eba1dd9d399c874d') 'Source method or Node identity differs'
Require ((Get-FileHash -LiteralPath (Local-Path 'payloads/evidence/ui-overlay-ae7-source12-first-20261015-output.json')).Hash -ceq 'CBC8607F5645ABB7B277F99C9D5A03C0AF46721700576213728CEDA280BDEF50') 'Original Source output identity differs'
Owner 'ui-overlay-ae7-source12-first-20261015' 'passed' '63C259C81E5D472B5F11C8D506070130CB04A1ECF84B80377A34ED6EC9048088'
$sourcePost=Evidence-Json 'ui-overlay-ae7-source12-first-20261015-posthash'
$sourceCounts=@{source=1968;dependencies=31064;node_tools=1774}
foreach($reference in $sourcePost.manifests){Require ($sourceCounts[$reference.name] -eq $reference.files -and $reference.drift -eq 0) 'Source capture full posthash differs'}
Require (@($sourcePost.manifests).Count -eq 3 -and @($sourcePost.extra_control_drift).Count -eq 0 -and !$sourcePost.control_manifest_drift -and @($sourcePost.absent_dependency_drift).Count -eq 0 -and $sourcePost.historical_absence_records -eq 84) 'Source capture controls or absence proof differ'
foreach($spec in @(
 @{file='sourceae7-full-manifest-20261015.json';count=1968},
 @{file='sourceae7-runtime-manifest-20261015.json';count=31064},
 @{file='sourceae7-node-tools-before-20261015.json';count=1774}
)){
 Require (@(Json ('payloads/references/'+$spec.file)).Count -eq $spec.count) "Frozen reference inventory differs: $($spec.file)"
}
$tools=Json 'payloads/references/durable-latest89-full-inspect-53ae-tool-prehash-20261011.json'
Require (@($tools.inputs).Count -eq 19546) 'Compiler full inventory differs'
$bodySha=(Get-FileHash -LiteralPath (Local-Path 'payloads/original-source/packages/coding-agent/src/modes/interactive/interactive-mode.ts')).Hash
Require ($bodySha -ceq 'B1000CCC60AC715D8483F00AD6CB8E6CD56665418B3738EFA47A77EC4FCE5043') 'Original InteractiveMode source bytes differ'
$observed=@(Get-Content -LiteralPath (Local-Path 'payloads/references/sourceae7-modules-55332-0-20261015.jsonl')|ForEach-Object{$_|ConvertFrom-Json})
Require (@($observed|Where-Object{$_.kind -ceq 'observed-module' -and $_.sha256 -ieq $bodySha}).Count -eq 1) 'Actual primary Source load observation absent'
$zig='086CE9D47BA42F33A514E1A6E04EB1D4A8FA1D75E0868E0213CAAD447C91E864'
$unit='ui-overlay-ae7-unit-controller-fences-debug-20261015'
$process='ui-overlay-ae7-process-invocation-markers-memory-retry-debug-20261015'
foreach($pair in @(@{name=$unit;candidate='d04dbecd983c26d277215b7089a969867c49f9c1'},@{name=$process;candidate='039f31088beaa1f42252bcd6f1df1ac67c5a53f8'})){
 Owner ($pair.name+'-compile') 'passed' $zig;Owner ($pair.name+'-runtime') 'passed' $zig
 Native-Post $pair.name $pair.candidate 'passed'
 $admission=Evidence-Json ($pair.name+'-admission')
 Require ($admission.status -ceq 'admitted' -and $admission.free_kib -ge 16777216 -and $admission.threshold_kib -eq 16777216 -and $admission.jobs -eq 1) 'Normal native resource admission differs'
}
Require ((Get-Content -Raw -LiteralPath (Local-Path ('payloads/evidence/'+$unit+'-runtime.stderr.log'))) -match '31/31 tests passed') 'Actual Controller unit count absent'
Require ((Get-Content -Raw -LiteralPath (Local-Path ('payloads/evidence/'+$process+'-runtime.stderr.log'))) -match '1/1 tests passed') 'Real worker terminal pass absent'
$artifacts=(Evidence-Json ($process+'-posthash')).process_artifacts
Require (@($artifacts).Count -eq 3) 'Worker and ConPTY artifact identities absent'
Require (@($artifacts|Where-Object{$_.sha256 -ceq 'DA5A8F91474A55B285E9160E1A4863737C36752FCBEC83C71B7DE500C8E29E47'}).Count -eq 1) 'Final native worker executable identity differs'
foreach($negative in @(
 @{name='ui-overlay-ae7-unit-first-debug-20261015';candidate='0a9e72d1b669a54733893f308bf2bf8b2cf3ebf5'},
 @{name='ui-overlay-ae7-process-first-debug-20261015';candidate='a9efc5ad83086c6bfd13c2cad1bf651fbbdde942'},
 @{name='ui-overlay-ae7-process-controller-fences-debug-20261015';candidate='d04dbecd983c26d277215b7089a969867c49f9c1'}
)){
 Owner ($negative.name+'-compile') 'passed' $zig;Owner ($negative.name+'-runtime') 'failed' $zig
 Native-Post $negative.name $negative.candidate 'failed'
}
$denied=Evidence-Json 'ui-overlay-ae7-process-invocation-markers-debug-20261015-admission'
Require ($denied.status -ceq 'admission_failed' -and $denied.native_launched -eq $false -and $denied.free_kib -lt 16777216 -and $denied.threshold_kib -eq 16777216) 'Preserved normal-floor admission denial differs'
foreach($controlManifest in Get-ChildItem -LiteralPath (Local-Path 'payloads/evidence') -File|Where-Object{$_.Name -like '*-controls-before.json' -or $_.Name -like '*-extra-before.json'}){
 foreach($pin in @(Get-Content -Raw -LiteralPath $controlManifest.FullName|ConvertFrom-Json)){
  Require ($shaSet.Contains($pin.sha256)) "Raw control version absent: $($pin.path) / $($pin.sha256)"
 }
}
$changed=(Get-Content -Raw -LiteralPath (Local-Path 'payloads/unit-to-final-paths.txt')).Trim()
Require ($changed -ceq 'src/fullscreen_frontend_process_test.zig') 'Unit-to-final source delta scope differs'
$handoff=Evidence-Json 'ui-overlay-ae7-final-handoff-20261015'
Require ($handoff.head -ceq $manifest.qualified_candidate -and !$handoff.full_pi_qualified -and !$handoff.public_activation -and $handoff.native_slot_4_released -and @($handoff.remaining_owned_pi_processes).Count -eq 0) 'Checkpoint qualification boundary differs'
[ordered]@{status='portable_offline_proof_verified';files=@($manifest.files).Count;bytes=($manifest.files|Measure-Object bytes -Sum).Sum;source_cases=12;unit_tests=31;terminal_tests=1;terminal_modes=@('regular','fullscreen');qualified_candidate=$manifest.qualified_candidate;unit_candidate=$manifest.unit_candidate;retained_failed_runtime_pairs=3;retained_admission_denials=1;new_source_or_native_execution=$false;full_pi_qualified=$false;public_activation=$false}|ConvertTo-Json -Depth 4
