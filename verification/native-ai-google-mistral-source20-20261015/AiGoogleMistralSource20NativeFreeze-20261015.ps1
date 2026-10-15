$taskNativeConfigPath=Join-Path $PSScriptRoot 'ai-google-mistral-source20-native-config-20261015.json'
$taskNativeCandidates=@(Get-Content -LiteralPath $taskNativeConfigPath -Raw|ConvertFrom-Json)
function Check-NativeCandidates{
 $taskResults=@()
 foreach($candidate in $taskNativeCandidates){
  $manifest=Join-Path $PSScriptRoot ("ai-google-mistral-source20-native-"+$candidate.name+"-before-20261015.json")
  $rows=@(Get-Content -LiteralPath $manifest -Raw|ConvertFrom-Json)
  $inventory=@(git -C $candidate.root ls-files --cached --others --exclude-standard|Sort-Object -Unique|Where-Object{Test-Path -LiteralPath (Join-Path $candidate.root $_) -PathType Leaf})
  $taskResults+=@{name=$candidate.name;head=$candidate.head;head_drift=(git -C $candidate.root rev-parse HEAD) -cne $candidate.head;count=$rows.Count;vendor=@($rows|Where-Object relativePath -like 'vendor/*').Count;drift=@(Check-Rows $rows).Count;inventory_drift=@(Compare-Object @($rows.relativePath) $inventory).Count}
 }
 return $taskResults
}
