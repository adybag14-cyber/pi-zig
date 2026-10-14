$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'Assert-ChordExpandedStatePartitions.ps1')
$total=2061
$rows=@(0..3|ForEach-Object {[pscustomobject]@{partition=$_;start=[long][math]::Floor($total*$_/4.0);end=[long][math]::Floor($total*($_+1)/4.0);baseline=$total;completed=[long][math]::Floor($total*($_+1)/4.0)-[long][math]::Floor($total*$_/4.0);leaks=0;unexpected_errors=0}})
function Make-Log($inputRows,$baselines){
 $lines=@($inputRows|ForEach-Object {'CHORD_EXPANDED_STATE_GPA_PARTITION='+($_|ConvertTo-Json -Compress)})
 $lines+=@($baselines|ForEach-Object {'CHORD_EXPANDED_STATE_GPA_BASELINE_ALLOCATIONS='+$_})
 $lines -join [Environment]::NewLine
}
$positive=Assert-ChordExpandedStatePartitions -Log (Make-Log $rows @(2061,2061,2061,2061))
if($positive.completed -ne 2061){throw 'Positive complete partition rejected'}
$negative=@(
 @{name='missing partition';change={param($r,$b) [pscustomobject]@{rows=@($r[0..2]);baselines=$b}}},
 @{name='extra duplicate partition';change={param($r,$b) [pscustomobject]@{rows=@($r)+@($r[0]);baselines=$b}}},
 @{name='duplicate partition id';change={param($r,$b) $r[1].partition=0;[pscustomobject]@{rows=$r;baselines=$b}}},
 @{name='range gap';change={param($r,$b) $r[1].start++;[pscustomobject]@{rows=$r;baselines=$b}}},
 @{name='range overlap';change={param($r,$b) $r[1].start--;[pscustomobject]@{rows=$r;baselines=$b}}},
 @{name='baseline mismatch';change={param($r,$b) $r[2].baseline--;[pscustomobject]@{rows=$r;baselines=$b}}},
 @{name='incomplete index count';change={param($r,$b) $r[3].completed--;[pscustomobject]@{rows=$r;baselines=$b}}},
 @{name='leak';change={param($r,$b) $r[2].leaks=1;[pscustomobject]@{rows=$r;baselines=$b}}},
 @{name='unexpected error';change={param($r,$b) $r[1].unexpected_errors=1;[pscustomobject]@{rows=$r;baselines=$b}}},
 @{name='boolean numeric field';change={param($r,$b) $r[0].start=$false;[pscustomobject]@{rows=$r;baselines=$b}}},
 @{name='fractional numeric field';change={param($r,$b) $r[0].start=0.5;[pscustomobject]@{rows=$r;baselines=$b}}},
 @{name='negative numeric field';change={param($r,$b) $r[0].start=-1;[pscustomobject]@{rows=$r;baselines=$b}}},
 @{name='missing baseline marker';change={param($r,$b) [pscustomobject]@{rows=$r;baselines=@($b[0..2])}}},
 @{name='wrong measured baseline';change={param($r,$b) $b[0]=2060;[pscustomobject]@{rows=$r;baselines=$b}}}
)
$results=@()
foreach($case in $negative){
 $copy=@($rows|ConvertTo-Json|ConvertFrom-Json)
 $changed=& $case.change $copy @(2061,2061,2061,2061)
 $log=Make-Log $changed.rows $changed.baselines
 $markerCount=[regex]::Matches($log,'CHORD_EXPANDED_STATE_GPA_PARTITION=').Count
 $baselineCount=[regex]::Matches($log,'CHORD_EXPANDED_STATE_GPA_BASELINE_ALLOCATIONS=').Count
 $expectedMarkers=if($case.name -ceq 'missing partition'){3}elseif($case.name -ceq 'extra duplicate partition'){5}else{4}
 $expectedBaselines=if($case.name -ceq 'missing baseline marker'){3}else{4}
 if($markerCount -ne $expectedMarkers -or $baselineCount -ne $expectedBaselines){throw ('Malformed negative fixture '+$case.name)}
 $rejected=$false
 $reason=''
 try {$null=Assert-ChordExpandedStatePartitions -Log $log}catch{$rejected=$true;$reason=$_.Exception.Message}
 if(!$rejected){throw ('Collector accepted negative '+$case.name)}
 $results+=@([ordered]@{name=$case.name;rejected=$true;reason=$reason;partition_markers=$markerCount;baseline_markers=$baselineCount})
}
[ordered]@{positive_passed=$true;negative_passed=$results.Count;negative_cases=$results;native_executed=$false;original_probe_modified=$false;completed_utc=[DateTimeOffset]::UtcNow.ToString('o')}|ConvertTo-Json -Depth 6|Set-Content -LiteralPath (Join-Path $PSScriptRoot 'expanded-state-partition-collector-validation.json') -Encoding utf8NoBOM
[pscustomobject]@{positive_passed=$true;negative_passed=$results.Count;native_executed=$false}|ConvertTo-Json
