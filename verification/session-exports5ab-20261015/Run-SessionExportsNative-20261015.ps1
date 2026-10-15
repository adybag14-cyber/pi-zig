param([Parameter(Mandatory)][ValidateSet('compile','runtime')][string]$Phase,[Parameter(Mandatory)][ValidateRange(1,4)][int]$RootSlot,[string]$Attempt='first',[string]$CompileAttempt='first',[string]$ExpectedHead='eff43ebd617c57f68a6a15d16d3bc942be3adf88')
$ErrorActionPreference='Stop'
$evidence=$PSScriptRoot
$root='C:\Users\adyba\pi-zig-session-exports-20261015'
$zig='C:\Users\adyba\pi-zig-toolchain-20261003\zig-x86_64-windows-0.16.0\zig.exe'
$owner=Join-Path $evidence 'Invoke-OwnedEeSourceJob-20261012.ps1'
$name="ordinary-session-exports5ab-native-$Phase-$Attempt-20261015"
if(Test-Path -LiteralPath (Join-Path $evidence "$name.json")){throw 'Immutable receipt exists'}
function Drift($rows){$changed=[Collections.Generic.List[string]]::new();foreach($row in $rows){if(!(Test-Path -LiteralPath $row.path -PathType Leaf)){$changed.Add($row.path);continue};$stream=[IO.File]::OpenRead($row.path);try{$sha=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($stream))}finally{$stream.Dispose()};if($sha -cne $row.sha256.ToUpperInvariant()){$changed.Add($row.path)}};@($changed)}
function Native-Rows{@(git -C $root ls-files --cached --others --exclude-standard|Sort-Object -Unique|Where-Object{Test-Path -LiteralPath (Join-Path $root $_) -PathType Leaf}|ForEach-Object{[ordered]@{relative=$_;path=(Join-Path $root $_);sha256=(Get-FileHash -LiteralPath (Join-Path $root $_)).Hash}})}
function Admit{$free=[long](Get-CimInstance Win32_OperatingSystem).FreePhysicalMemory*1024;$builds=@(Get-CimInstance Win32_Process -Filter "Name='zig.exe'"|Where-Object{$_.CommandLine -match '\sbuild\s'});if($free -lt 16GB -or $builds.Count -ge 4){throw 'Native16GiB/max4 admission denied'};[ordered]@{root_slot=$RootSlot;required_bytes=16GB;free_bytes=$free;other_build_roots=$builds.Count;max_coordinated_jobs=4;compiler_jobs=1;compile_owner_seconds=1320;runtime_owner_seconds=300;test_seconds=120;await_ms=10000;observed_utc=[datetime]::UtcNow.ToString('o')}}
$admission=Admit
$candidateHead=(git -C $root rev-parse HEAD).Trim()
if($candidateHead -cne $ExpectedHead -or @(git -C $root status --porcelain).Count){throw 'Exact clean candidate identity changed'}
$sourceRoot='C:\Users\adyba\pi-upstream-source-5ab7fe7-20261015'
$sourceHead=(git -C $sourceRoot rev-parse HEAD).Trim()
if($sourceHead -cne '5ab7fe74c400097b386662205cd93900695b8a71'){throw 'Original Source HEAD changed'}
$sourceManifest=Join-Path $evidence 'source5ab-full-manifest-20261015.json'
$dependencyManifest=Join-Path $evidence 'durable-19cb534-reference-20261012-all-built-runtime.json'
$nodeManifest=Join-Path $evidence 'root-current8a-npm-tools-before.json'
$sourceRows=@(Get-Content -LiteralPath $sourceManifest -Raw|ConvertFrom-Json)
$dependencies=@(Get-Content -LiteralPath $dependencyManifest -Raw|ConvertFrom-Json)
$nodeTools=@(Get-Content -LiteralPath $nodeManifest -Raw|ConvertFrom-Json)
if($sourceRows.Count -ne 1967 -or $dependencies.Count -ne 31064 -or $nodeTools.Count -ne 1774){throw 'Full Original/dependency/Node inventory count changed'}
if(@(Drift $sourceRows).Count -or @(Drift $dependencies).Count -or @(Drift $nodeTools).Count){throw 'Full Original/dependency/Node prehash drift'}
function Source-Inventory{$tracked=@(git -C $sourceRoot ls-files --cached --others --exclude-standard|Where-Object{Test-Path -LiteralPath (Join-Path $sourceRoot $_) -PathType Leaf});$generated=@(Get-ChildItem -LiteralPath (Join-Path $sourceRoot 'packages/ai/src/providers/data') -File -Force|ForEach-Object{if($_.Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'Source catalog reparse'};[IO.Path]::GetRelativePath($sourceRoot,$_.FullName).Replace('\','/')});@(@($tracked)+@($generated)|Sort-Object -Unique)}
if(Compare-Object @($sourceRows.relative) @(Source-Inventory)){throw 'Original Source inventory drift'}
$manifest=Join-Path $evidence 'durable-latest89-full-inspect-53ae-tool-prehash-20261011.json'
$tools=@((Get-Content -LiteralPath $manifest -Raw|ConvertFrom-Json).inputs)
if($tools.Count -ne 19546){throw 'Compiler full inventory count changed'}
if(@(Drift $tools).Count){throw 'Compiler prehash drift'}
$shellManifest=Join-Path $evidence 'ordinary-session-exports5ab-more-source-first-20261015-shell-tools-before.json'
$shellTools=@(Get-Content -LiteralPath $shellManifest -Raw|ConvertFrom-Json)
if($shellTools.Count -ne 368 -or @(Drift $shellTools).Count){throw 'Actual Source selected Git runtime drift'}
function Shell-Inventory{@(@('C:\Program Files\Git\bin','C:\Program Files\Git\usr\bin')|ForEach-Object{Get-ChildItem -LiteralPath $_ -File}|ForEach-Object{if($_.Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'Selected Git runtime reparse'};$_.FullName})}
if(Compare-Object @($shellTools.path) @(Shell-Inventory)){throw 'Selected Git runtime inventory drift'}
foreach($pair in @(@('ordinary-session-exports5ab-source-first-20261015-artifacts.json','sdk-session-exports5ab-source.json','capture.json'),@('ordinary-session-exports5ab-more-source-first-20261015-artifacts.json','sdk-session-exports5ab-more-source.json','capture.json'),@('ordinary-session-exports5ab-source-first-20261015-artifacts.json','sdk-session-exports5ab-source-session.input.txt','source-session.jsonl'))){$artifacts=@(Get-Content -LiteralPath (Join-Path $evidence $pair[0]) -Raw|ConvertFrom-Json);$capture=@($artifacts|Where-Object{$_.relative -ceq $pair[2]});if($capture.Count -ne 1 -or (Get-FileHash -LiteralPath (Join-Path $root ('src/extensions/fixtures/'+$pair[1]))).Hash -cne $capture[0].sha256.ToUpperInvariant()){throw 'Genuine expected fixture bytes changed'}}
$before=Native-Rows
if($Phase -eq 'runtime'){$compileName="ordinary-session-exports5ab-native-compile-$CompileAttempt-20261015";$compile=Get-Content -LiteralPath (Join-Path $evidence "$compileName-posthash.json") -Raw|ConvertFrom-Json;$rows=@(Get-Content -LiteralPath (Join-Path $evidence "$compileName-native-before.json") -Raw|ConvertFrom-Json);if($compile.status -cne 'passed' -or $compile.native_drift -or $compile.native_inventory_drift -or $compile.compiler_drift -or $compile.control_drift){throw 'Compile prerequisite failed'};if(Compare-Object @($rows|ForEach-Object{"$($_.relative):$($_.sha256)"}) @($before|ForEach-Object{"$($_.relative):$($_.sha256)"})){throw 'Source changed after compile'}}
$controls=@($PSCommandPath,$owner,$manifest,$shellManifest,$sourceManifest,$dependencyManifest,$nodeManifest,(Join-Path $evidence 'ordinary-session-exports5ab-source-first-20261015-posthash.json'),(Join-Path $evidence 'ordinary-session-exports5ab-source-first-20261015-artifacts.json'),(Join-Path $evidence 'ordinary-session-exports5ab-more-source-first-20261015-posthash.json'),(Join-Path $evidence 'ordinary-session-exports5ab-more-source-first-20261015-artifacts.json'),(Join-Path $evidence 'env-exec-native-prerequisites-v2-20261015/source-leaves.json'),(Join-Path $evidence 'env-exec-native-prerequisites-v2-20261015/engine-hub-lifecycle-dc434339.patch'),(Join-Path $evidence 'env-filehandle-webstream-qualified-source8-native10-20261015/qualified-leaves.json'),(Join-Path $evidence 'env-filehandle-webstream-qualified-source8-native10-20261015/qualification-audit.json'),(Join-Path $evidence 'ordinary-session-exports5ab-native-third-prerequisite-closure-20261015.json'))
$controlRows=@($controls|ForEach-Object{[ordered]@{path=$_;sha256=(Get-FileHash -LiteralPath $_).Hash}})
$before|ConvertTo-Json -Depth 5|Set-Content -LiteralPath (Join-Path $evidence "$name-native-before.json") -Encoding utf8NoBOM
$controlRows|ConvertTo-Json -Depth 5|Set-Content -LiteralPath (Join-Path $evidence "$name-controls-before.json") -Encoding utf8NoBOM
$controlDirectory=Join-Path $evidence "$name-frozen-controls"
New-Item -ItemType Directory -Path $controlDirectory|Out-Null
foreach($row in $controlRows){Copy-Item -LiteralPath $row.path -Destination (Join-Path $controlDirectory ([IO.Path]::GetFileName($row.path)))}
$admission=Admit;$admission|ConvertTo-Json -Depth 5|Set-Content -LiteralPath (Join-Path $evidence "$name-admission.json") -Encoding utf8NoBOM
$arguments=@('build',$(if($Phase -eq 'compile'){'build-native-sdk-session-exports'}else{'test-native-sdk-session-exports'}),'-Doptimize=Debug','-j1','--test-timeout','120s','--summary','all')
try{& $owner -Name $name -Executable $zig -WorkingDirectory $root -Arguments $arguments -TimeoutSeconds $(if($Phase -eq 'compile'){1320}else{300}) -EnvironmentOverrides @{}}finally{
 $nativeDrift=@(Drift $before);$originalDrift=@(Drift $sourceRows);$dependencyDrift=@(Drift $dependencies);$nodeDrift=@(Drift $nodeTools);$originalInventoryDrift=@(Compare-Object @($sourceRows.relative) @(Source-Inventory));$sourceHeadAfter=(git -C $sourceRoot rev-parse HEAD).Trim();$compilerDrift=@(Drift $tools);$controlDrift=@(Drift $controlRows);$shellDrift=@(Drift $shellTools);$shellInventoryDrift=@(Compare-Object @($shellTools.path) @(Shell-Inventory));$after=Native-Rows;$inventoryDrift=@(Compare-Object @($before.relative) @($after.relative));$record=if(Test-Path -LiteralPath (Join-Path $evidence "$name.json")){Get-Content -LiteralPath (Join-Path $evidence "$name.json") -Raw|ConvertFrom-Json}else{$null}
 [ordered]@{status=if($record){$record.status}else{'not_launched'};exit_code=if($record){$record.exit_code}else{$null};phase=$Phase;root_slot=$RootSlot;candidate_head=$candidateHead;source_head_before=$sourceHead;source_head_after=$sourceHeadAfter;original=$sourceRows.Count;original_drift=$originalDrift.Count;original_inventory_drift=$originalInventoryDrift.Count;dependencies=$dependencies.Count;dependency_drift=$dependencyDrift.Count;node_tools=$nodeTools.Count;node_tool_drift=$nodeDrift.Count;native_source=$before.Count;native_drift=$nativeDrift.Count;native_inventory_drift=$inventoryDrift.Count;compiler_files=$tools.Count;compiler_drift=$compilerDrift.Count;controls=$controlRows.Count;control_drift=$controlDrift.Count;shell_tools=$shellTools.Count;shell_tool_drift=$shellDrift.Count;shell_inventory_drift=$shellInventoryDrift.Count;full_constructor_qualified=$false;full_pi_qualified=$false;public_activation=$false;completed_utc=[datetime]::UtcNow.ToString('o')}|ConvertTo-Json -Depth 5|Set-Content -LiteralPath (Join-Path $evidence "$name-posthash.json") -Encoding utf8NoBOM
 if($nativeDrift.Count -or $compilerDrift.Count -or $controlDrift.Count -or $inventoryDrift.Count -or $shellDrift.Count -or $shellInventoryDrift.Count -or $originalDrift.Count -or $dependencyDrift.Count -or $nodeDrift.Count -or $originalInventoryDrift.Count -or $sourceHeadAfter -cne $sourceHead){throw 'Full freeze drift'}
}
$post=Get-Content -LiteralPath (Join-Path $evidence "$name-posthash.json") -Raw|ConvertFrom-Json
$post|ConvertTo-Json -Depth 5
if($post.status -cne 'passed'){throw 'Owned native terminal failure'}