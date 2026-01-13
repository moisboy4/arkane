Param(
    [string]$RepoPath = $PSScriptRoot,
    [string]$Branch = "main",
    [int]$DebounceMs = 3000
)

Set-Location $RepoPath

$fsw = New-Object System.IO.FileSystemWatcher $RepoPath, '*.*'
$fsw.IncludeSubdirectories = $true
$fsw.EnableRaisingEvents = $true
$fsw.NotifyFilter = [IO.NotifyFilters]'FileName, LastWrite, Size, DirectoryName'

$exclude = @('.git','\\.vs\\','\\bin\\','\\obj\\','\\intermediate\\','\\packages\\')

$pending = $false
$timer = $null

function MatchesExclude($path) {
    foreach ($e in $using:exclude) {
        if ($path -like "*$e*") { return $true }
    }
    return $false
}

$action = {
    param($src, $e)
    $full = $e.FullPath
    if (MatchesExclude $full) { return }
    $script:pending = $true
    if ($script:timer) { $script:timer.Stop(); $script:timer.Dispose() }
    $script:timer = New-Object Timers.Timer $using:DebounceMs
    $script:timer.AutoReset = $false
    $script:timer.add_elapsed({
        $script:pending = $false
        try {
            Write-Host "Detected changes. Staging, committing and pushing..."
            git add -A
            $msg = "Auto commit: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
            git commit -m $msg 2>$null | Out-Null
            git push origin $using:Branch
            Write-Host "Auto-push complete: $msg"
        } catch {
            Write-Host "Auto-push failed:`n$_"
        }
    })
    $script:timer.Start()
}

Register-ObjectEvent $fsw Changed -Action $action | Out-Null
Register-ObjectEvent $fsw Created -Action $action | Out-Null
Register-ObjectEvent $fsw Renamed -Action $action | Out-Null
Register-ObjectEvent $fsw Deleted -Action $action | Out-Null

Write-Host "Watching $RepoPath for changes. Press Ctrl+C to stop."
while ($true) { Start-Sleep -Seconds 1 }
