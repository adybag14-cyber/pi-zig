param([ValidateSet('build','test')][string]$Phase='build',[ValidateSet('all','transport','source','oom','byte','stream-oom','headers')][string]$Scope='all',[string]$Attempt='first',[string]$BuildAttempt='first',[Parameter(Mandatory)][string]$CandidateHead)
$ErrorActionPreference='Stop'
$taskRoot='C:/Users/adyba/pi-zig-web-response-qualification-20261015'
$taskEvidence='C:/Users/adyba/pi-zig-update-evidence-20261003'
$taskName="web-response-debug-$Phase-$Scope-$Attempt-20261015"
$taskBase=Join-Path $taskEvidence $taskName
if(Test-Path -LiteralPath "$taskBase-frozen.json"){throw 'Immutable Response phase already exists'}
$taskOwner=Join-Path $PSScriptRoot 'run-owner.ps1'
if((git -c gc.auto=0 -c maintenance.auto=false -c pack.threads=2 -c pack.windowMemory=64m -C $taskRoot rev-parse HEAD).Trim()-cne$CandidateHead-or@(git -c gc.auto=0 -c maintenance.auto=false -c pack.threads=2 -c pack.windowMemory=64m -C $taskRoot status --porcelain).Count){throw 'Exact clean Response candidate mismatch'}
$taskSteps=if($Phase-eq'build'){@('build-native-web-response-source','build-native-web-response-transport','build-native-web-response-oom','build-hosted-native-readable-byte-source','build-hosted-native-readable-host-oom','build-native-headers-source')}else{if($Scope-eq'all'){throw 'Runtime requires explicit scope'};switch($Scope){'byte'{@('test-native-readable-byte-source')};'stream-oom'{@('test-native-readable-host-oom')};'headers'{@('test-native-headers-source')};default{@("test-native-web-response-$Scope")}}}
[ordered]@{candidate_head=$CandidateHead;scope=$Scope;phase=$Phase;case_scope='Strict unchanged Body176 Response114 and Headers189, genuine OAuth header-gated wire, transport clone/GC/guest exception identity, selected5 strict OOM, unchanged SourceByte12 and deterministic permanent host OOM tee retirement; actual native stream graph incomplete shared prototypes/BYOB tee; no full Body qualification';source_authority='Node24.14.0 bundledUndici7.21.0 Body176 and Headers189 immutable';compile_targets=@('source','transport','oom','byte','stream-oom','headers');build_attempt=$BuildAttempt;max_native_roots=4;minimum_free_gib=16;slot='NATIVE1';host_await_seconds=10;test_timeout_seconds=120;owner_settle_seconds=10}|ConvertTo-Json -Depth 5|Set-Content -LiteralPath "$taskBase-metadata.json" -Encoding utf8NoBOM
$taskAudit=Join-Path $taskEvidence 'source5ab-dependency-contract-audit-20261015.json'
$taskRuntime='C:/Users/adyba/pi-upstream-runtime-19cb534-20261012'
$taskContract=Get-Content -LiteralPath $taskAudit -Raw|ConvertFrom-Json
$taskAbsent=@($taskContract.pins|Where-Object status -eq 'platform_optional_absent'|ForEach-Object{Join-Path $taskRuntime $_.path})+@($taskContract.mismatches|ForEach-Object{Join-Path $taskRuntime $_.path})
if($taskAbsent.Count-ne84-or@($taskAbsent|Where-Object{Test-Path -LiteralPath $_}).Count){throw 'Original absent dependency inventory drift'}
if((Get-FileHash -LiteralPath 'C:/Users/adyba/pi-zig-toolchain-20261003/zig-x86_64-windows-0.16.0/zig.exe').Hash-cne'086CE9D47BA42F33A514E1A6E04EB1D4A8FA1D75E0868E0213CAAD447C91E864'){throw 'Pinned Zig0.16 executable drift'}
$taskExpected=Join-Path $taskRoot 'src/extensions/fixtures/web-body-node24.json'
$taskInput=Join-Path $taskRoot 'src/extensions/fixtures/web-body-node24.input.txt'
$taskSourceOutput=Join-Path $taskEvidence 'web-body-node24-source-first-20261015-output.json'
$taskSourceMeta=Get-Content -LiteralPath $taskExpected -Raw|ConvertFrom-Json
$taskHeaderExpected=Join-Path $taskRoot 'src/extensions/fixtures/web-headers-node24.json'
$taskHeaderInput=Join-Path $taskRoot 'src/extensions/fixtures/web-headers-node24.input.txt'
$taskHeaderOutput=Join-Path $taskEvidence 'web-headers-node24-source-first-20261015-output.json'
$taskHeaderMeta=Get-Content -LiteralPath $taskHeaderExpected -Raw|ConvertFrom-Json
$taskNode='C:/Program Files/nodejs/node.exe'
$taskSupplement=Join-Path $taskEvidence 'web-body-node-builtin-inventory-second-20261015-output.json'
$taskSupplementOwner=Join-Path $taskEvidence 'web-body-node-builtin-inventory-second-20261015.json'
$taskAuthorityFiles=@($taskExpected,$taskInput,$taskSourceOutput,$taskSourceMeta.nodeBuiltins.path,$taskSourceMeta.bundledUndici.path,(Join-Path $taskRoot 'verification/web-body-node24-20261015/receipts/web-body-node24-source-first-20261015-node-builtin-authorities.json'),(Join-Path $taskRoot 'verification/web-body-node24-20261015/receipts/web-body-node24-source-first-20261015-bundled-undici.js.txt'),$taskNode,$taskSupplement,$taskSupplementOwner,(Join-Path $taskRoot 'src/extensions/fixtures/env-readable-byte-stream-source-24.json'),(Join-Path $taskRoot 'src/extensions/fixtures/env-readable-byte-stream-source-24.input.txt'),(Join-Path $taskEvidence 'env-stream-span-prerequisite-3f0cce9a-20261015/independent-span-static-review.json'))
$taskAuthorityFiles+=@($taskHeaderExpected,$taskHeaderInput,$taskHeaderOutput,$taskHeaderMeta.bundledUndici.path)
function Verify-Authority {
 if($taskHeaderMeta.cases-ne189-or$taskHeaderMeta.actualGcCalls-ne6-or$taskHeaderMeta.actualNode.version-cne'v24.14.0'-or$taskHeaderMeta.actualNode.undici-cne'7.21.0'){throw 'Genuine unchanged Headers189 authority mismatch'}
 if((Get-FileHash -LiteralPath $taskHeaderExpected).Hash-cne(Get-FileHash -LiteralPath $taskHeaderOutput).Hash-or(Get-FileHash -LiteralPath $taskHeaderInput).Hash-ine'8f3be8d9c250eec0048331c461490704207b6e9375fb45c4d4e47ede9bc0b83b'){throw 'Genuine unchanged Headers189 packet/input drift'}
 if((Get-FileHash -LiteralPath $taskHeaderMeta.bundledUndici.path).Hash-ine'c62030f1e505a4010d9972ecbf40155eddeb355f2a53a9f019a447214e1a9600'){throw 'Actual Headers bundled authority drift'}
 if($taskSourceMeta.cases-ne176-or$taskSourceMeta.actualGcCalls-ne6-or$taskSourceMeta.actualNode.version-cne'v24.14.0'-or$taskSourceMeta.actualNode.undici-cne'7.21.0'){throw 'Genuine Body176 identity mismatch'}
 if((Get-FileHash -LiteralPath $taskExpected).Hash-cne(Get-FileHash -LiteralPath $taskSourceOutput).Hash){throw 'Genuine Body176 expected bytes drift'}
 if((Get-FileHash -LiteralPath $taskInput).Hash-ine'b20eca3d00631d8b7745c8769de4790f5fc2e82ca0589cbe633f2c8901756cea'){throw 'Genuine Body176 input drift'}
 if((Get-FileHash -LiteralPath $taskNode).Hash-ine'63c259c81e5d472b5f11c8d506070130cb04a1ecf84b80377a34ed6ec9048088'){throw 'Pinned actual Node executable drift'}
 foreach($taskFile in @($taskSourceMeta.nodeBuiltins.path,$taskAuthorityFiles[5])){if((Get-FileHash -LiteralPath $taskFile).Hash-ine'0cd86676bb2a46a4e772d1fd8bb3d00fca658383bc388846dcc796547dc79263'){throw 'All Node builtin source body identity drift'}}
 foreach($taskFile in @($taskSourceMeta.bundledUndici.path,$taskAuthorityFiles[6])){if((Get-FileHash -LiteralPath $taskFile).Hash-ine'c62030f1e505a4010d9972ecbf40155eddeb355f2a53a9f019a447214e1a9600'){throw 'Bundled Undici source body identity drift'}}
 $taskBuiltins=Get-Content -LiteralPath $taskSourceMeta.nodeBuiltins.path -Raw|ConvertFrom-Json -AsHashtable
 if($taskBuiltins.Count-ne368-or@($taskBuiltins.Values|Where-Object{$_-isnot[string]}).Count){throw 'Actual368 Node builtin string-body inventory drift'}
 $taskInventory=Get-Content -LiteralPath $taskSupplement -Raw|ConvertFrom-Json
 $taskInventoryOwner=Get-Content -LiteralPath $taskSupplementOwner -Raw|ConvertFrom-Json
 if($taskInventoryOwner.status-cne'passed'-or$taskInventoryOwner.exit_code-ne0-or$taskInventory.enumerated_entries-ne369-or$taskInventory.string_bodies-ne368-or$taskInventory.undefined_keys.Count-ne1-or$taskInventory.undefined_keys[0]-cne'configs'-or$taskInventory.serialized_entries-ne368-or$taskInventory.serialized_includes_configs){throw 'Actual undefined configs supplement mismatch'}
 if(!$taskInventory.configs_descriptor.enumerable-or!$taskInventory.configs_descriptor.writable-or!$taskInventory.configs_descriptor.configurable-or$taskInventory.serialized_sha256-cne'0cd86676bb2a46a4e772d1fd8bb3d00fca658383bc388846dcc796547dc79263'){throw 'Actual builtin supplement identity drift'}
 foreach($taskKey in @('internal/blob','internal/file','internal/webstreams/readablestream','internal/deps/undici/undici')){if(!$taskBuiltins.ContainsKey($taskKey)){throw 'Mandatory actual builtin body absent'}}
 return [ordered]@{source_cases=176;actual_gc_calls=6;node_builtin_bodies=368;enumerated_native_entries=369;undefined_native_entries=1;node_builtin_bytes=9294918;drift=0}
}
function Candidate-Rows {
    @(git -c gc.auto=0 -c maintenance.auto=false -c pack.threads=2 -c pack.windowMemory=64m -C $taskRoot ls-files --cached --others --exclude-standard | Sort-Object -Unique | ForEach-Object { $taskFile=Join-Path $taskRoot $_; [ordered]@{path=$taskFile;sha256=(Get-FileHash -LiteralPath $taskFile).Hash} })
}
$taskCandidate=Candidate-Rows
$taskCandidatePath="$taskBase-candidate.json"
$taskCandidate|ConvertTo-Json -Depth 4|Set-Content -LiteralPath $taskCandidatePath -Encoding utf8NoBOM
if($Phase-eq'test'){
 $taskBuildBase=Join-Path $taskEvidence "web-response-debug-build-all-$BuildAttempt-20261015"
 $taskBuildOwner=Get-Content -LiteralPath "$taskBuildBase.process.json" -Raw|ConvertFrom-Json
 if($taskBuildOwner.status-cne'passed'-or$taskBuildOwner.exit_code-ne0-or!$taskBuildOwner.owned_identity_absent){throw 'Matching compile did not pass or owned root remains'}
 $taskBuildMetadata=Get-Content -LiteralPath "$taskBuildBase-metadata.json" -Raw|ConvertFrom-Json
 if($taskBuildMetadata.candidate_head-cne$CandidateHead-or$taskBuildMetadata.scope-cne'all'){throw 'Matching all-target compile head/scope mismatch'}
 $taskBuildAfter=Get-Content -LiteralPath "$taskBuildBase-after.json" -Raw|ConvertFrom-Json
 if(@($taskBuildAfter|Where-Object drift -ne 0).Count){throw 'Matching compile full posthash failed'}
 $taskBuildCandidate=Get-Content -LiteralPath "$taskBuildBase-candidate.json" -Raw|ConvertFrom-Json
 if(@(Compare-Object ($taskBuildCandidate|ForEach-Object{"$($_.path):$($_.sha256)"}) ($taskCandidate|ForEach-Object{"$($_.path):$($_.sha256)"})).Count){throw 'Between compile/runtime candidate drift'}
 $taskBuildControls=Get-Content -LiteralPath "$taskBuildBase-controls.json" -Raw|ConvertFrom-Json
 foreach($taskControl in $taskBuildControls){if($taskControl.path.EndsWith('-metadata.json')){continue};if((Get-FileHash -LiteralPath $taskControl.path).Hash-cne$taskControl.sha256){throw 'Between compile/runtime owner/control drift'}}
}
$taskVendor=@(Get-ChildItem -LiteralPath (Join-Path $taskRoot 'vendor') -File -Recurse -Force|ForEach-Object{[ordered]@{path=$_.FullName;sha256=(Get-FileHash -LiteralPath $_.FullName).Hash}})
$taskVendorPath="$taskBase-vendor.json"
$taskVendor|ConvertTo-Json -Depth 4|Set-Content -LiteralPath $taskVendorPath -Encoding utf8NoBOM
$taskToolsPath=Join-Path $taskEvidence 'durable-latest89-full-inspect-53ae-tool-prehash-20261011.json'
$taskTools=@((Get-Content -LiteralPath $taskToolsPath -Raw|ConvertFrom-Json).inputs)
if($taskTools.Count-ne19546){throw 'Complete compiler/library19546 inventory mismatch'}
$taskToolRows="$taskBase-tools.json"
$taskTools|ConvertTo-Json -Depth 4|Set-Content -LiteralPath $taskToolRows -Encoding utf8NoBOM
$taskControls=@($PSCommandPath,$taskOwner,$taskToolsPath,$taskAudit,(Join-Path $taskRoot 'verification/web-body-node24-20261015/source-capture.mjs'),(Join-Path $taskRoot 'verification/web-body-node24-20261015/run-source.ps1'),(Join-Path $taskEvidence 'env-stream-span-prerequisite-3f0cce9a-20261015/borrowed-live-view-span-only.patch'),(Join-Path $taskEvidence 'web-body-dependencies-debug-build-second-20261015.process.json'),(Join-Path $taskEvidence 'web-body-dependencies-debug-build-second-20261015-after.json'),(Join-Path $taskEvidence 'web-body-dependencies-debug-test-first-20261015.process.json'),(Join-Path $taskEvidence 'web-body-dependencies-debug-test-first-20261015-after.json'),"$taskBase-metadata.json")|ForEach-Object{[ordered]@{path=$_;sha256=(Get-FileHash -LiteralPath $_).Hash}}
$taskControlPath="$taskBase-controls.json"
$taskControls|ConvertTo-Json -Depth 4|Set-Content -LiteralPath $taskControlPath -Encoding utf8NoBOM
$taskAuthorityPath="$taskBase-authorities.json"
@($taskAuthorityFiles|ForEach-Object{[ordered]@{path=$_;sha256=(Get-FileHash -LiteralPath $_).Hash}})|ConvertTo-Json -Depth 4|Set-Content -LiteralPath $taskAuthorityPath -Encoding utf8NoBOM
$taskManifestPaths=@((Join-Path $taskEvidence 'source5ab-full-manifest-20261015.json'),(Join-Path $taskEvidence 'durable-19cb534-reference-20261012-all-built-runtime.json'),(Join-Path $taskEvidence 'root-current8a-npm-tools-before.json'),$taskCandidatePath,$taskVendorPath,$taskToolRows,$taskControlPath,$taskAuthorityPath)
$taskManifests=@($taskManifestPaths|ForEach-Object{[ordered]@{name=[IO.Path]::GetFileName($_);path=$_;sha256=(Get-FileHash -LiteralPath $_).Hash}})
$taskFrozen="$taskBase-frozen.json"
$taskManifests|ConvertTo-Json -Depth 4|Set-Content -LiteralPath $taskFrozen -Encoding utf8NoBOM
$taskFrozenHash=(Get-FileHash -LiteralPath $taskFrozen).Hash
function Verify-Frozen {
    if((Get-FileHash -LiteralPath $taskFrozen).Hash-cne$taskFrozenHash){throw 'Frozen registry identity drift'}
    $taskChecks=@()
    foreach($taskManifest in $taskManifests){
        if((Get-FileHash -LiteralPath $taskManifest.path).Hash -cne $taskManifest.sha256){throw 'Manifest identity drift'}
        $taskRows=@(Get-Content -LiteralPath $taskManifest.path -Raw|ConvertFrom-Json)
        foreach($taskRow in $taskRows){if(!(Test-Path -LiteralPath $taskRow.path -PathType Leaf) -or (Get-FileHash -LiteralPath $taskRow.path).Hash -ine $taskRow.sha256){throw "Frozen file drift $($taskRow.path)"}}
        $taskChecks+=[ordered]@{manifest=$taskManifest.name;count=$taskRows.Count;drift=0}
    }
    if($taskChecks[0].count -ne 1967 -or $taskChecks[1].count -ne 31064 -or $taskChecks[2].count -ne 1774){throw 'Original complete inventory mismatch'}
    if(@($taskAbsent|Where-Object{Test-Path -LiteralPath $_}).Count){throw 'Absent dependency state drift'}
    $taskAuthority=Verify-Authority
    $taskChecks+=[ordered]@{manifest='actual-Body176-Node369-entry-authority';count=$taskAuthority.node_builtin_bodies;enumerated_entries=369;undefined_configs_entries=1;source_cases=$taskAuthority.source_cases;actual_gc_calls=$taskAuthority.actual_gc_calls;drift=0}
    return $taskChecks
}
$taskBefore=Verify-Frozen
$taskBefore|ConvertTo-Json -Depth 5|Set-Content -LiteralPath "$taskBase-before.json" -Encoding utf8NoBOM
$taskFree=(Get-CimInstance Win32_OperatingSystem).FreePhysicalMemory*1024
$taskExisting=@(Get-CimInstance Win32_Process|Where-Object{$_.ExecutablePath -and ($_.ExecutablePath.EndsWith('\zig.exe') -or $_.ExecutablePath -like 'C:\Users\adyba\pi-zig*\.zig-cache\*\build.exe' -or $_.ExecutablePath -like 'C:\Users\adyba\pi-zig*\.zig-cache\*\test.exe')})
$taskIds=@($taskExisting|ForEach-Object ProcessId)
$taskRoots=@($taskExisting|Where-Object{$_.ParentProcessId -notin $taskIds})
[ordered]@{minimum_free_bytes=16GB;available_bytes=$taskFree;existing_native_roots=$taskRoots.Count;existing_native_processes=@($taskExisting|Select-Object ProcessId,ParentProcessId,ExecutablePath,CommandLine,CreationDate);checked_utc=[DateTimeOffset]::UtcNow.ToString('o')}|ConvertTo-Json -Depth 5|Set-Content -LiteralPath "$taskBase-admission.json" -Encoding utf8NoBOM
if($taskFree -lt 16GB -or $taskRoots.Count -ge 4){throw 'Normal16GiB/max4 native root admission rejected'}
[ordered]@{candidate_head=(git -c gc.auto=0 -c maintenance.auto=false -c pack.threads=2 -c pack.windowMemory=64m -C $taskRoot rev-parse HEAD).Trim();owner_script_sha256=(Get-FileHash -LiteralPath $taskOwner).Hash;runner_sha256=(Get-FileHash -LiteralPath $PSCommandPath).Hash;compiler_sha256='086CE9D47BA42F33A514E1A6E04EB1D4A8FA1D75E0868E0213CAAD447C91E864';frozen_registry_sha256=$taskFrozenHash;argv=(@('build')+$taskSteps+@('-Doptimize=Debug','-Duse-llvm=true','-j1','--test-timeout','120s','--summary','all'));launch_intent_utc=[DateTimeOffset]::UtcNow.ToString('o')}|ConvertTo-Json -Depth 5|Set-Content -LiteralPath "$taskBase-launch-intent.json" -Encoding utf8NoBOM
$taskFailure=$null
try{& $taskOwner -Executable 'C:/Users/adyba/pi-zig-toolchain-20261003/zig-x86_64-windows-0.16.0/zig.exe' -WorkingDirectory $taskRoot -Arguments (@('build')+$taskSteps+@('-Doptimize=Debug','-Duse-llvm=true','-j1','--test-timeout','120s','--summary','all')) -ReceiptBase $taskBase -TimeoutSeconds $(if($Phase -eq 'build'){1320}else{300})}catch{$taskFailure=$_}
$taskAfter=Verify-Frozen
$taskAfter|ConvertTo-Json -Depth 5|Set-Content -LiteralPath "$taskBase-after.json" -Encoding utf8NoBOM
$taskCandidateAfter=Candidate-Rows
if(@(Compare-Object ($taskCandidate|ForEach-Object{"$($_.path):$($_.sha256)"}) ($taskCandidateAfter|ForEach-Object{"$($_.path):$($_.sha256)"})).Count){throw 'Candidate inventory drift'}
if($taskFailure){throw $taskFailure}
Write-Output "NATIVE_RESPONSE_$($Phase.ToUpper())_PASSED candidate=$($taskCandidate.Count) vendor=$($taskVendor.Count) toolchain=$($taskTools.Count)"
