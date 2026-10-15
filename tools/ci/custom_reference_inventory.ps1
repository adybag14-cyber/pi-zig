function Get-CustomReferenceInventory {
 param([string]$Root)
 $taskRows=[Collections.Generic.List[object]]::new()
 $taskPending=[Collections.Generic.Stack[string]]::new();$taskPending.Push($Root)
 while($taskPending.Count){
  foreach($taskItem in Get-ChildItem -LiteralPath $taskPending.Pop() -Force){
   $taskRelative=[IO.Path]::GetRelativePath($Root,$taskItem.FullName).Replace('\','/')
   if($taskRelative -ceq '.git' -or $taskRelative.StartsWith('.git/',[StringComparison]::Ordinal)){continue}
   if($taskItem.Attributes -band [IO.FileAttributes]::ReparsePoint){
    $taskTarget=$taskItem.ResolveLinkTarget($true)
    if(!$taskTarget -or !$taskTarget.FullName.StartsWith($Root+[IO.Path]::DirectorySeparatorChar,[StringComparison]::Ordinal)){throw "Reference link escapes frozen root: $taskRelative"}
    $taskLink=[string]$taskItem.LinkTarget
    $taskHash=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($taskLink+"`n"+$taskTarget.FullName)))
    $taskRows.Add(@{relative=$taskRelative;path=$taskItem.FullName;sha256=$taskHash;kind='link';link_target=$taskLink;resolved_target=$taskTarget.FullName})
   }elseif($taskItem.PSIsContainer){$taskPending.Push($taskItem.FullName)}
   else{$taskRows.Add(@{relative=$taskRelative;path=$taskItem.FullName;sha256=(Get-FileHash -LiteralPath $taskItem.FullName).Hash;kind='file'})}
  }
 }
 return @{root=$Root;rows=@($taskRows|Sort-Object relative -CaseSensitive)}
}
function Assert-CustomReferenceInventory {
 param($Inventory,[string]$Output)
 $taskCurrent=Get-CustomReferenceInventory $Inventory.root
 $taskBefore=@($Inventory.rows|ForEach-Object relative);$taskAfter=@($taskCurrent.rows|ForEach-Object relative)
 $taskPaths=@(Compare-Object $taskBefore $taskAfter -CaseSensitive)
 $taskMap=[Collections.Generic.Dictionary[string,string]]::new([StringComparer]::Ordinal)
 foreach($taskRow in $taskCurrent.rows){$taskMap.Add($taskRow.relative,$taskRow.sha256)}
 $taskHashes=@($Inventory.rows|Where-Object {!$taskMap.ContainsKey($_.relative) -or $taskMap[$_.relative] -cne $_.sha256}|ForEach-Object relative)
 @{root=$Inventory.root;before_count=$taskBefore.Count;after_count=$taskAfter.Count;path_drift=$taskPaths;hash_drift=$taskHashes;rows=$taskCurrent.rows}|ConvertTo-Json -Depth 8|Set-Content -LiteralPath $Output -Encoding utf8NoBOM
 if($taskPaths.Count -or $taskHashes.Count){throw 'Frozen full Source/dependency/link inventory drift'}
}
