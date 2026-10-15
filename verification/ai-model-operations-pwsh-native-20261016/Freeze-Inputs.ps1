#requires -Version 7.0
param([Parameter(Mandatory)][ValidateSet('Pre','Post')][string]$Phase,[Parameter(Mandatory)][ValidatePattern('^[a-z0-9-]+$')][string]$Name,[string]$Root=(Split-Path (Split-Path $PSScriptRoot -Parent) -Parent),[string]$Evidence='C:/Users/adyba/pi-zig-update-evidence-20261003',[string[]]$ExtraControls=@())
$ErrorActionPreference='Stop'
$taskSource='C:/Users/adyba/pi-upstream-source-4954d76-20261015'
$taskRuntime='C:/Users/adyba/pi-upstream-runtime-19cb534-20261012'
$taskCompiler='C:/Users/adyba/pi-zig-toolchain-20261003/zig-x86_64-windows-0.16.0'
function Get-Hash([string]$Path){$stream=[IO.File]::OpenRead($Path);$algorithm=[Security.Cryptography.SHA256]::Create();try{return [BitConverter]::ToString($algorithm.ComputeHash($stream)).Replace('-','')}finally{$algorithm.Dispose();$stream.Dispose()}}
function Get-Rows([string[]]$Paths){@(foreach($path in $Paths|Sort-Object -Unique){[ordered]@{path=[IO.Path]::GetFullPath($path);sha256=Get-Hash $path}})}
function Check-Rows($Rows){@(foreach($row in $Rows){if(!(Test-Path -LiteralPath $row.path -PathType Leaf)-or(Get-Hash $row.path) -cne $row.sha256.ToUpperInvariant()){$row.path}})}
function Inventory([string]$Directory,[string[]]$Excluded=@()){
 $files=[Collections.Generic.List[string]]::new();$links=[Collections.Generic.List[object]]::new();$pending=[Collections.Generic.Stack[string]]::new();$pending.Push([IO.Path]::GetFullPath($Directory))
 while($pending.Count){foreach($item in Get-ChildItem -LiteralPath $pending.Pop() -Force){$relative=[IO.Path]::GetRelativePath($Directory,$item.FullName).Replace('\','/');if($relative -in $Excluded){continue};if($item.Attributes-band[IO.FileAttributes]::ReparsePoint){$links.Add([ordered]@{path=$item.FullName;target=@($item.Target);link_type=$item.LinkType});continue};if($item.PSIsContainer){$pending.Push($item.FullName)}elseif($item.Name -ne '.git'){$files.Add($item.FullName)}}}
 return @{files=@($files|Sort-Object -CaseSensitive);links=@($links|Sort-Object path)}
}
function Candidate-Paths{@(git -C $Root ls-files|ForEach-Object{[IO.Path]::GetFullPath((Join-Path $Root $_))})}
function Equal-Inventory($Before,$After){(@(Compare-Object $Before.files $After.files -CaseSensitive).Count -eq 0)-and(($Before.links|ConvertTo-Json -Depth 6 -Compress) -ceq ($After.links|ConvertTo-Json -Depth 6 -Compress))}
function Absences{
 $audit=Get-Content -LiteralPath (Join-Path $Evidence 'source4954-dependency-contract-audit-20261015.json') -Raw|ConvertFrom-Json -AsHashtable
 if($audit.latestHead -cne '4954d760504c11df9b2cbdc040346107b6a8153d'){throw 'Exact4954 dependency authority required'}
 $relative=@($audit.pins|Where-Object status -ceq 'platform_optional_absent'|ForEach-Object path)+@($audit.mismatches|ForEach-Object path)
 if($relative.Count -ne 84){throw 'Exactly84 declared absent records required'}
 @(foreach($directory in @($taskSource,$taskRuntime)){foreach($path in $relative){Join-Path $directory $path}})
}
$taskPre=Join-Path $Evidence "$Name-prehash.json"
if($Phase -ceq 'Pre'){
 if(Test-Path -LiteralPath $taskPre){throw 'Fresh unique frozen attempt required'}
 if(git -C $Root status --porcelain){throw 'Clean committed native candidate required'}
 if((git -C $taskSource rev-parse HEAD)-cne'4954d760504c11df9b2cbdc040346107b6a8153d'){throw 'Exact immutable Source4954 head required'}
 $taskSets=[ordered]@{candidate=Get-Rows (Candidate-Paths);source=@(Get-Content -LiteralPath (Join-Path $Evidence 'source4954-full-manifest-20261015.json') -Raw|ConvertFrom-Json -AsHashtable);dependencies=@(Get-Content -LiteralPath (Join-Path $Evidence 'source4954-runtime-manifest-20261015.json') -Raw|ConvertFrom-Json -AsHashtable);node=@(Get-Content -LiteralPath (Join-Path $Evidence 'source4954-node-tools-before-20261015.json') -Raw|ConvertFrom-Json -AsHashtable)}
 if($taskSets.source.Count -ne 1970-or$taskSets.dependencies.Count -ne 31064-or$taskSets.node.Count -ne 1774){throw 'Full1970/31064/1774 references required'}
 $taskCompilerInventory=Inventory $taskCompiler
 if($taskCompilerInventory.files.Count -ne 19546){throw 'Full19546 compiler inventory required'}
 $taskSets.compiler=Get-Rows $taskCompilerInventory.files
 $taskNodeInventory=Inventory 'C:/Program Files/nodejs/node_modules/npm'
 $taskNodeInventory.files=@($taskNodeInventory.files)+@([IO.Path]::GetFullPath('C:/Program Files/nodejs/node.exe'))
 $taskNodeInventory.files=@($taskNodeInventory.files|Sort-Object -CaseSensitive)
 if(@(Compare-Object @($taskSets.node|ForEach-Object path|Sort-Object) $taskNodeInventory.files).Count){throw 'Complete pinned Node/npm path inventory mismatch'}
 $taskControlPaths=@($PSCommandPath,(Join-Path $PSScriptRoot 'Verify-SourceProof.ps1'),(Join-Path $PSScriptRoot 'Invoke-OwnedProcess.ps1'),(Join-Path $PSScriptRoot 'Run-Native.ps1'),(Join-Path $PSScriptRoot 'Read-TestMetadata.ps1'),(Join-Path $PSScriptRoot 'expected-tests.json'),(Join-Path $Root 'src/native_ai_model_operations_source_test.zig'),(Join-Path $Root 'src/extensions/fixtures/ai-model-operations-4954.json'),(Join-Path $Root 'src/extensions/fixtures/ai-model-operations-4954.input.txt'),(Join-Path $Root 'verification/ai-model-operations-4954-20261015/source88-proof.zip'))+@('source4954-full-manifest-20261015.json','source4954-runtime-manifest-20261015.json','source4954-node-tools-before-20261015.json','source4954-dependency-contract-audit-20261015.json','source4954-reference-controls-20261015.json','source4954-observe-20261015.mjs'|ForEach-Object{Join-Path $Evidence $_})+$ExtraControls
 $taskSets.controls=Get-Rows $taskControlPaths
 foreach($key in $taskSets.Keys){$changed=@(Check-Rows $taskSets[$key]);if($changed.Count){throw "Frozen prehash drift: $key"}}
 if((Get-Hash (Join-Path $taskCompiler 'zig.exe')) -cne '086CE9D47BA42F33A514E1A6E04EB1D4A8FA1D75E0868E0213CAAD447C91E864'-or(Get-Hash 'C:/Program Files/nodejs/node.exe') -cne '63C259C81E5D472B5F11C8D506070130CB04A1ECF84B80377A34ED6EC9048088'){throw 'Pinned compiler/Node executable changed'}
 $taskSourceInventory=Inventory $taskSource @('.git','node_modules');$taskRuntimeInventory=Inventory $taskRuntime @('.git')
 if(@(Compare-Object @($taskSets.source|ForEach-Object path|Sort-Object) $taskSourceInventory.files).Count-or@(Compare-Object @($taskSets.dependencies|ForEach-Object path|Sort-Object) $taskRuntimeInventory.files).Count){throw 'Complete Source/dependency path inventory mismatch'}
 $taskAbsences=@(Absences);if(@($taskAbsences|Where-Object{Test-Path -LiteralPath $_}).Count){throw 'Absent package appeared'}
 $taskJunction=Get-Item -LiteralPath (Join-Path $taskSource 'node_modules');if($taskJunction.LinkType -cne 'Junction'-or[IO.Path]::GetFullPath(@($taskJunction.Target)[0]) -ine [IO.Path]::GetFullPath((Join-Path $taskRuntime 'node_modules'))){throw 'Source dependency junction changed'}
 [ordered]@{candidate_head=(git -C $Root rev-parse HEAD);source_head=(git -C $taskSource rev-parse HEAD);sets=$taskSets;candidate_paths=Candidate-Paths;source_inventory=$taskSourceInventory;dependency_inventory=$taskRuntimeInventory;compiler_inventory=$taskCompilerInventory;node_inventory=$taskNodeInventory;absences=$taskAbsences;source_junction_target=@($taskJunction.Target);created_utc=[DateTimeOffset]::UtcNow.ToString('o');implementation='PowerShell7/.NET only'}|ConvertTo-Json -Depth 12|Set-Content -LiteralPath $taskPre -Encoding utf8NoBOM
}else{
 $before=Get-Content -LiteralPath $taskPre -Raw|ConvertFrom-Json -AsHashtable
 $report=[ordered]@{manifests=@(foreach($key in $before.sets.Keys){$changed=@(Check-Rows $before.sets[$key]);@{name=$key;files=$before.sets[$key].Count;drift=$changed.Count;changed=$changed}});candidate_head_drift=((git -C $Root rev-parse HEAD) -cne $before.candidate_head);candidate_inventory_drift=(@(Compare-Object $before.candidate_paths (Candidate-Paths) -CaseSensitive).Count -ne 0);source_inventory_drift=!(Equal-Inventory $before.source_inventory (Inventory $taskSource @('.git','node_modules')));dependency_inventory_drift=!(Equal-Inventory $before.dependency_inventory (Inventory $taskRuntime @('.git')));compiler_inventory_drift=!(Equal-Inventory $before.compiler_inventory (Inventory $taskCompiler));absence_drift=@($before.absences|Where-Object{Test-Path -LiteralPath $_});declared_absence_records=84;source_junction_drift=(@(Compare-Object $before.source_junction_target @((Get-Item -LiteralPath (Join-Path $taskSource 'node_modules')).Target)).Count -ne 0);completed_utc=[DateTimeOffset]::UtcNow.ToString('o');implementation='PowerShell7/.NET only'}
 $taskNodeInventory=Inventory 'C:/Program Files/nodejs/node_modules/npm';$taskNodeInventory.files=@($taskNodeInventory.files)+@([IO.Path]::GetFullPath('C:/Program Files/nodejs/node.exe'));$taskNodeInventory.files=@($taskNodeInventory.files|Sort-Object -CaseSensitive)
 $report.node_inventory_drift=!(Equal-Inventory $before.node_inventory $taskNodeInventory)
 $report.source_head_drift=((git -C $taskSource rev-parse HEAD)-cne$before.source_head)
 $report|ConvertTo-Json -Depth 10|Set-Content -LiteralPath (Join-Path $Evidence "$Name-posthash.json") -Encoding utf8NoBOM
 if(@($report.manifests|Where-Object drift -ne 0).Count){throw 'Frozen file drift'};foreach($key in $report.Keys){if($key.EndsWith('_drift')-and$report[$key]){throw "Frozen inventory drift: $key"}}
 $report
}
