param(
    [Parameter(Mandatory)][string]$CandidateRoot,
    [Parameter(Mandatory)][string]$CandidateHead,
    [Parameter(Mandatory)][string]$ActualNode,
    [Parameter(Mandatory)][string]$ActualNodeSha256
)
# Preparation only. No Start-Process, native invocation, golden acceptance or
# grant is performed here; the admitted Root owner consumes the returned plan.
$ErrorActionPreference = 'Stop'
$taskRoot = [IO.Path]::GetFullPath($CandidateRoot)
$taskLayout = & (Join-Path $taskRoot 'tools/workspace/Resolve-PiZigWorkspace.ps1') -StartPath $taskRoot
if (!$taskRoot.StartsWith($taskLayout.worktrees + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) { throw 'Actual candidate must be a contained isolated worktree' }
if ($CandidateHead -notmatch '^[0-9a-f]{40}$') { throw 'An exact sealed candidate head is required' }
$taskNode = [IO.Path]::GetFullPath($ActualNode)
if (!$taskNode.StartsWith($taskLayout.Container + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) { throw 'Node authority must be contained' }
if ($ActualNodeSha256 -notmatch '^[0-9A-Fa-f]{64}$' -or (Get-FileHash -LiteralPath $taskNode -Algorithm SHA256).Hash -ne $ActualNodeSha256) { throw 'Actual Node authority hash mismatch' }
$taskManifestPath = Join-Path $taskRoot 'verification/node-tty-composition-sourceonly-20261017/original-capture-prepared.json'
$taskManifest = Get-Content -LiteralPath $taskManifestPath -Raw | ConvertFrom-Json
$taskTransitive = [IO.Path]::GetFullPath((Join-Path $taskRoot $taskManifest.transitive_input.path))
if (!$taskTransitive.StartsWith($taskRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase) -or (Get-FileHash -LiteralPath $taskTransitive -Algorithm SHA256).Hash -ne $taskManifest.transitive_input.sha256) { throw 'Original alias caller drift' }
$taskCases = @($taskManifest.cases | ForEach-Object {
    $taskInput = [IO.Path]::GetFullPath((Join-Path $taskRoot $_.input))
    if (!$taskInput.StartsWith($taskRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) { throw 'Original input escapes candidate' }
    if ((Get-FileHash -LiteralPath $taskInput -Algorithm SHA256).Hash -ne $_.sha256) { throw "Original input drift: $($_.name)" }
    [pscustomobject][ordered]@{ name=$_.name; executable=$taskNode; argv=@($taskInput); cwd=$taskRoot; fresh_process=$true; stdin='closed'; stdout='raw_capture'; stderr='raw_capture'; expected=$null }
})
[pscustomobject][ordered]@{
    schema=1; status='PREPARED_PLAN_NOT_ADMISSION'; candidate_root=$taskRoot; candidate_head=$CandidateHead
    actual_node=$taskNode; actual_node_sha256=$ActualNodeSha256.ToUpperInvariant(); required_node_version='24.14.0'
    manifest_sha256=(Get-FileHash -LiteralPath $taskManifestPath -Algorithm SHA256).Hash
    cases=$taskCases; serial_only=$true; execution_grant=$false; capture_accepted=$false
    owner_requirements=@('Root must independently verify exact clean Git head, Node24.14 authority and full source/compiler/controller closure before admission', 'Existing bounded reference owner owns launch, fresh resource admission, actual PID/executable/command/creation identity and terminal full post/absence', 'Each case is a fresh process; preserve raw stdout/stderr and exit. No fallback or modified expected values', 'Physical console output/input cases require a separately reviewed owned private-console fixture and are excluded from redirected reference cases')
}
