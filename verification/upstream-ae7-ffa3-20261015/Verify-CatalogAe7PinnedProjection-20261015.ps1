$ErrorActionPreference='Stop'
$taskPrivate='C:/Users/adyba/pi-zig-upstream-catalog-ae7-20261015'
$taskRawPath=Join-Path $PSScriptRoot 'catalog-ae7-preparation-20261015/official-pinned-models.all.json'
$taskNativePath=Join-Path $taskPrivate 'src/ai/catalog_source.json'
$taskOldPath='C:/Users/adyba/pi-zig-upstream-catalog-20261015/src/ai/catalog_source.json'
$taskRaw=Get-Content -LiteralPath $taskRawPath -Raw|ConvertFrom-Json -AsHashtable -DateKind String
$taskNative=Get-Content -LiteralPath $taskNativePath -Raw|ConvertFrom-Json -AsHashtable -DateKind String
$taskOld=Get-Content -LiteralPath $taskOldPath -Raw|ConvertFrom-Json -AsHashtable -DateKind String
$taskFlat=@($taskRaw.Values|ForEach-Object{foreach($taskModel in $_){$taskModel}})
if($taskFlat.Count -ne 1705 -or $taskRaw.Count -ne 42){throw 'Actual typed1705/providers42 required'}
$taskMismatch=@()
for($taskIndex=0;$taskIndex -lt $taskFlat.Count;$taskIndex++){if(($taskFlat[$taskIndex]|ConvertTo-Json -Compress -Depth 100) -cne ($taskNative.models[$taskIndex]|ConvertTo-Json -Compress -Depth 100)){$taskMismatch+=$taskIndex}}
if($taskMismatch.Count){throw 'Rawtyped/native full metadata/order mismatch'}
if($taskNative.upstreamCommit -cne 'ae7b16d43b7c78c5b6fa3213fdd1215bb339729d' -or $taskNative.upstreamVersion -cne '1.3.0' -or $taskNative.catalogSha256 -cne 'ffa3e98626230f378f80200debb736c4a2238b5f2ba246a92cfc7d8e19604678'){throw 'Canonical authority mismatch'}
$taskOldMap=@{};$taskNewMap=@{}
foreach($taskModel in $taskOld.models){$taskOldMap["$($taskModel.provider)/$($taskModel.type)/$($taskModel.id)"]=$taskModel}
foreach($taskModel in $taskNative.models){$taskNewMap["$($taskModel.provider)/$($taskModel.type)/$($taskModel.id)"]=$taskModel}
$taskAdded=@($taskNewMap.Keys|Where-Object{!$taskOldMap.ContainsKey($_)}|Sort-Object)
$taskRemoved=@($taskOldMap.Keys|Where-Object{!$taskNewMap.ContainsKey($_)}|Sort-Object)
$taskChanged=@($taskNewMap.Keys|Where-Object{$taskOldMap.ContainsKey($_) -and ($taskOldMap[$_]|ConvertTo-Json -Compress -Depth 100) -cne ($taskNewMap[$_]|ConvertTo-Json -Compress -Depth 100)}|Sort-Object)
$taskManifest=Get-Content -LiteralPath (Join-Path $taskPrivate 'src/ai/catalog_builtin_manifest.json') -Raw|ConvertFrom-Json -AsHashtable -DateKind String
$taskReceipt=@{source='ae7b16d43b7c78c5b6fa3213fdd1215bb339729d';raw_typed_models=$taskFlat.Count;raw_native_metadata_mismatches=$taskMismatch.Count;added=$taskAdded;removed=$taskRemoved;changed=$taskChanged;chat=@($taskNative.models|Where-Object type -ceq 'chat').Count;image=@($taskNative.models|Where-Object type -ceq 'image').Count;classifier=@($taskNative.models|Where-Object type -ceq 'classifier').Count;providers=$taskRaw.Count;chat_apis=@($taskNative.models|Where-Object type -ceq 'chat'|ForEach-Object api|Sort-Object -Unique);generatedAt=$taskManifest.generatedAt;structureHash=$taskManifest.structureHash;raw_sha256=(Get-FileHash -LiteralPath $taskRawPath).Hash;native_source_sha256=(Get-FileHash -LiteralPath $taskNativePath).Hash;manifest_sha256=(Get-FileHash -LiteralPath (Join-Path $taskPrivate 'src/ai/catalog_builtin_manifest.json')).Hash;full_pi=$false;observed_utc=[DateTimeOffset]::UtcNow.ToString('o')}
if($taskReceipt.chat -ne 1608 -or $taskReceipt.image -ne 59 -or $taskReceipt.classifier -ne 38 -or $taskReceipt.chat_apis.Count -ne 10 -or $taskReceipt.generatedAt -cne '1970-01-01T00:00:00.000Z'){throw 'Exact typedcounts/APIs/manifest required'}
$taskReceipt|ConvertTo-Json -Depth 10|Set-Content -LiteralPath (Join-Path $PSScriptRoot 'catalog-ae7-ffa3-native-data-delta-20261015.json') -Encoding utf8NoBOM
Write-Output 'CANONICAL_AE7_TYPED1705_METADATA_AND_ORDER_VERIFIED'
