$ErrorActionPreference='Stop'
$taskEvidence=$PSScriptRoot
$taskConfig=@(Get-Content -LiteralPath (Join-Path $taskEvidence 'ai-google-mistral-source20-native-config-20261015.json') -Raw|ConvertFrom-Json)
foreach($candidate in $taskConfig){
 if((git -C $candidate.root rev-parse HEAD) -cne $candidate.head -or (git -C $candidate.root status --porcelain)){throw 'Exact clean native candidate required'}
 $rows=@(git -C $candidate.root ls-files --cached --others --exclude-standard|Sort-Object -Unique|Where-Object{Test-Path -LiteralPath (Join-Path $candidate.root $_) -PathType Leaf}|ForEach-Object{[ordered]@{path=Join-Path $candidate.root $_;relativePath=$_;sha256=(Get-FileHash -LiteralPath (Join-Path $candidate.root $_)).Hash}})
 $rows|ConvertTo-Json -Depth 5|Set-Content -LiteralPath (Join-Path $taskEvidence ("ai-google-mistral-source20-native-"+$candidate.name+"-before-20261015.json")) -Encoding utf8NoBOM
}
$taskSequence=@(@{runner='Run-AiMistralFraming8Source-20261015.ps1';name='ai-mistral8-framing-5ab-source8-first-20261015';cases=8},@{runner='Run-AiGoogleLive4Source-20261015.ps1';name='ai-google4-live-5ab-source4-first-20261015';cases=4},@{runner='Run-AiMistralFetch8Source-20261015.ps1';name='ai-mistral-fetch8-5ab-source8-first-20261015';cases=8})
$taskResults=@();$taskFailure=$null
try{
 foreach($job in $taskSequence){
  & (Join-Path $taskEvidence $job.runner)
  $owner=Get-Content -LiteralPath (Join-Path $taskEvidence ($job.name+'.json')) -Raw|ConvertFrom-Json
  $post=Get-Content -LiteralPath (Join-Path $taskEvidence ($job.name+'-posthash.json')) -Raw|ConvertFrom-Json
  if($owner.status -cne 'passed' -or @($post.manifests|Where-Object drift -ne 0).Count -or $post.extra_control_drift.Count -or $post.control_manifest_drift -or $post.absent_dependency_drift.Count -or @($post.native_candidates|Where-Object{$_.head_drift -or $_.drift -or $_.inventory_drift}).Count){throw 'Serial Source terminal/full post0 required before next capture'}
  $taskResults+=@{name=$job.name;cases=$job.cases;pid=$owner.pid;status=$owner.status;posthash='zero';completed_utc=$owner.completed_utc}
 }
}catch{$taskFailure=$_.Exception.Message}finally{
 [ordered]@{slot=3;authority='Root explicit LIGHT3 grant sequential SourceFraming8 GoogleLive4 MistralFetch8';results=$taskResults;status=if($taskFailure){'failed'}else{'passed'};failure=$taskFailure;native_builds=0;goldens_published=$false;completed_utc=[DateTimeOffset]::UtcNow.ToString('o')}|ConvertTo-Json -Depth 8|Tee-Object -FilePath (Join-Path $taskEvidence 'ai-google-mistral-source20-series-first-20261015.json')
}
if($taskFailure){exit 1}
