Param(
    [string]$RepoPath = $PSScriptRoot,
    [string]$Branch = "main",
    [int]$DebounceMs = 3000
)

Set-Location $RepoPath

# Discord webhook for push notifications. Replace or leave as empty string to disable.
$DiscordWebhook = 'https://discord.com/api/webhooks/1460583008640827394/AUDDdlPrg9VcLDS6QWqXOx7nP-kSPXviPoX2Ta_ooSoVedo1cuHXpIZZMH5ZlexWGA-P'

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
            if ($LASTEXITCODE -eq 0) {
                Write-Host "Auto-push complete: $msg"
                if ($DiscordWebhook -and $DiscordWebhook.Trim() -ne '') {
                    $hash = (git rev-parse --short HEAD | Out-String).Trim()
                    $commitMsg = (git log -1 --pretty=%B | Out-String).Trim()
                    $repoName = Split-Path -Leaf $RepoPath
                    $changelog = (git log -n 8 --pretty=format:"%h - %s" | Out-String).Trim()
                    if (-not $changelog) { $changelog = $commitMsg }
                    $embed = @{
                        title = "Auto push to $Branch"
                        description = $commitMsg
                        fields = @(
                            @{ name = 'Commit'; value = $hash; inline = $true },
                            @{ name = 'Repo'; value = $repoName; inline = $true },
                            @{ name = 'Recent commits'; value = $changelog; inline = $false }
                        )
                        timestamp = (Get-Date).ToString('o')
                    }
                    $payload = @{ username = 'Auto-Push Bot'; embeds = @($embed) } | ConvertTo-Json -Depth 10
                    try {
                        Invoke-RestMethod -Uri $DiscordWebhook -Method Post -Body $payload -ContentType 'application/json' -ErrorAction Stop
                        Write-Host 'Discord notification sent.'
                    } catch {
                        Write-Host "Failed to send Discord notification: $_"
                    }
                }
            } else {
                Write-Host "Auto-push failed (git push returned exit code $LASTEXITCODE)."
            }
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
