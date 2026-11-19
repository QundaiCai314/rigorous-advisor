[CmdletBinding()]
param(
    [ValidateSet('Install','Upgrade','UpdateAnchor','Status')]
    [string]$Action = 'Status',
    [string]$HomeDir = $HOME,
    [string]$CodexHome = $(if ($env:CODEX_HOME) { $env:CODEX_HOME } else { Join-Path $HomeDir '.codex' }),
    [ValidateSet('Codex','Agents')]
    [string]$InstallRootType = 'Codex',
    [ValidateSet('EN','ZH')]
    [string]$Language = 'EN',
    [switch]$AllowDowngrade,
    [switch]$SimulateCopyFailure
)

$ErrorActionPreference = 'Stop'
$source = Split-Path -Parent $PSScriptRoot
$skillName = 'rigorous-advisor'
$runtime = @('SKILL.md', 'references\evaluation-rubric.md')
$heading = '^## (?:Decision Rigor & Anti-Sycophancy|客观评审与反迎合底线)[ \t]*$'
$startMarker = '<!-- rigorous-advisor:start -->'
$endMarker = '<!-- rigorous-advisor:end -->'
$lf = [string][char]10
$crlf = [string][char]13 + $lf
$strictUtf8 = [Text.UTF8Encoding]::new($false, $true)

function Resolve-FileSystemPath([string]$Path) {
    $provider = $null
    $drive = $null
    $full = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath(
        $Path, [ref]$provider, [ref]$drive
    )
    if ($provider.Name -ne 'FileSystem') { throw "Expected a filesystem path: $Path" }
    [IO.Path]::GetFullPath($full)
}

function Assert-RealPath([string]$Path) {
    for ($entry = $Path; $entry; $entry = [IO.Path]::GetDirectoryName($entry)) {
        $item = Get-Item -LiteralPath $entry -Force -ErrorAction SilentlyContinue
        if ($item -and ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
            throw "Refusing a symlink or junction in managed path: $entry"
        }
    }
}

function New-Stamp { (Get-Date -Format 'yyyyMMdd-HHmmss-fff') + '-' + [guid]::NewGuid().ToString('N') }

function Open-WriteLock([string]$Path) {
    Assert-RealPath $Path
    try {
        [IO.File]::Open($Path, 'OpenOrCreate', 'ReadWrite', 'None')
    } catch {
        throw "Could not acquire installer lock at $($Path): $($_.Exception.Message)"
    }
}

function Ensure-Directory([string]$Path) {
    Assert-RealPath $Path
    [void][IO.Directory]::CreateDirectory($Path)
}

function Get-SkillVersion([string]$Path) {
    $raw = [IO.File]::ReadAllText($Path, $strictUtf8)
    $front = [regex]::Match($raw, '(?s)\A---\r?\n(.*?)\r?\n---(?:\r?\n|$)')
    if ($front.Success -and $front.Groups[1].Value -match '(?m)^  version:[ \t]*["'']?(\d+\.\d+\.\d+)["'']?[ \t]*\r?$') {
        return [version]$Matches[1]
    }
    throw "Missing or invalid skill version: $Path"
}

function Get-Fingerprint([byte[]]$Bytes) {
    $digest = [Security.Cryptography.SHA256]::Create()
    try {
        [BitConverter]::ToString($digest.ComputeHash($Bytes)).Replace('-', '').ToLowerInvariant()
    } finally { $digest.Dispose() }
}

function Copy-VerifiedRuntime([string]$Staging) {
    foreach ($rel in $runtime) {
        $from = Join-Path $source $rel
        $to = Join-Path $Staging $rel
        $expected = Get-Fingerprint ([IO.File]::ReadAllBytes($from))
        [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($to))
        [IO.File]::Copy($from, $to)
        if ((Get-Fingerprint ([IO.File]::ReadAllBytes($to))) -ne $expected) {
            throw "SHA-256 verification failed: $rel"
        }
    }
}

$CodexHome = Resolve-FileSystemPath $CodexHome
$HomeDir = Resolve-FileSystemPath $HomeDir
$profiles = @{ Codex = $CodexHome; Agents = Join-Path $HomeDir '.agents' }

function Get-InstallTarget([string]$Profile) { Join-Path $Profile "skills\$skillName" }
function Get-RecoveryPath([string]$Profile) { Join-Path $Profile ".$skillName-previous" }

if ($Action -eq 'Status') {
    $agents = Join-Path $CodexHome 'AGENTS.md'
    $override = Join-Path $CodexHome 'AGENTS.override.md'
    [pscustomobject]@{
        SourceVersion = Get-SkillVersion (Join-Path $source 'SKILL.md')
        CodexTarget = Get-InstallTarget $profiles.Codex
        AgentsTarget = Get-InstallTarget $profiles.Agents
        Installed = (@($profiles.Values | ForEach-Object { Get-InstallTarget $_ } |
            Select-Object -Unique | Where-Object { Test-Path -LiteralPath $_ }) -join ', ')
        RecoveryPaths = (@($profiles.Values | ForEach-Object { Get-RecoveryPath $_ } |
            Select-Object -Unique | Where-Object { Test-Path -LiteralPath $_ }) -join ', ')
        AnchorFile = $(if (Test-Path -LiteralPath $agents -PathType Leaf) { $agents })
        OverrideFile = $(if (Test-Path -LiteralPath $override -PathType Leaf) { $override })
    } | Format-List
    return
}

if ($Action -in 'Install','Upgrade') {
    $profile = $profiles[$InstallRootType]
    if ($Action -eq 'Upgrade' -and -not $PSBoundParameters.ContainsKey('InstallRootType')) {
        $found = @($profiles.Values | Select-Object -Unique | Where-Object {
            (Test-Path -LiteralPath (Get-InstallTarget $_)) -or (Test-Path -LiteralPath (Get-RecoveryPath $_))
        })
        if ($found.Count -ne 1) {
            throw 'Upgrade requires one existing installation. Select a root with -InstallRootType when both exist.'
        }
        $profile = $found[0]
    }
    $target = Get-InstallTarget $profile
    $rollbackPath = Get-RecoveryPath $profile
    $staging = Join-Path $profile ".ra-stage-$([guid]::NewGuid().ToString('N'))"
    $sourceVersion = Get-SkillVersion (Join-Path $source 'SKILL.md')
    Ensure-Directory ([IO.Path]::GetDirectoryName($target))
    $lock = Open-WriteLock (Join-Path $profile ".$skillName-install.lock")
    try {
        Assert-RealPath $target
        Assert-RealPath $rollbackPath
        if ([IO.Directory]::Exists($rollbackPath) -and -not (Test-Path -LiteralPath $target)) {
            [IO.Directory]::Move($rollbackPath, $target)
            Write-Warning "Recovered interrupted upgrade at $target."
        }
        $exists = Test-Path -LiteralPath $target
        if ($Action -eq 'Install' -and $exists) { throw "Installation already exists: $target" }
        if ($Action -eq 'Upgrade' -and -not $exists) { throw "No installation to upgrade: $target" }
        if ($exists -and -not [IO.Directory]::Exists($target)) { throw "Expected installation directory: $target" }
        if ($exists -and (Test-Path -LiteralPath $rollbackPath)) {
            if (-not [IO.Directory]::Exists($rollbackPath)) { throw "Expected recovery directory: $rollbackPath" }
            $retired = Join-Path $profile ".$skillName-retired-$(New-Stamp)"
            [IO.Directory]::Move($rollbackPath, $retired)
            Write-Warning "Archived an earlier recovery directory at $retired."
        }
        if ($exists) {
            $reparse = Get-ChildItem -LiteralPath $target -Recurse -Force -Attributes ReparsePoint | Select-Object -First 1
            if ($reparse) { throw "Installation contains a symlink or junction: $($reparse.FullName)" }
            $installedEntry = Join-Path $target 'SKILL.md'
            $installedVersion = if ([IO.File]::Exists($installedEntry)) { Get-SkillVersion $installedEntry }
            if ($installedVersion -gt $sourceVersion -and -not $AllowDowngrade) {
                throw "Installed version ($installedVersion) is newer than source ($sourceVersion). Use -AllowDowngrade to override."
            }
        }

        Copy-VerifiedRuntime $staging
        if ($exists) {
            $backups = Join-Path $CodexHome 'backups'
            Ensure-Directory $backups
            $zip = Join-Path $backups "$skillName-backup-$(New-Stamp).zip"
            Add-Type -AssemblyName System.IO.Compression.FileSystem
            [IO.Compression.ZipFile]::CreateFromDirectory($target, $zip, [IO.Compression.CompressionLevel]::Optimal, $true)
            [IO.Directory]::Move($target, $rollbackPath)
        }

        try {
            if ($SimulateCopyFailure) { throw 'Simulated publication failure.' }
            [IO.Directory]::Move($staging, $target)
        } catch {
            $publishError = $_.Exception.Message
            if ($exists) {
                try { [IO.Directory]::Move($rollbackPath, $target) }
                catch { throw "Publication and rollback failed. Target: $target. Previous directory: $rollbackPath. Backup: $zip. $($_.Exception.Message)" }
                throw "Publication failed and the previous directory was restored: $publishError"
            }
            throw
        }

        if ($exists) {
            try {
                Assert-RealPath $rollbackPath
                Remove-Item -LiteralPath $rollbackPath -Recurse -Force
            } catch {
                Write-Warning "New installation is active. Cleanup failed at $rollbackPath. Backup: $zip. $($_.Exception.Message)"
            }
            Write-Output "Upgraded $target to v$sourceVersion (backup: $zip)."
        } else {
            Write-Output "Installed $skillName v$sourceVersion at $target."
        }
    } finally {
        try {
            if ([IO.Directory]::Exists($staging)) {
                Assert-RealPath $staging
                Remove-Item -LiteralPath $staging -Recurse -Force
            }
        } finally { $lock.Dispose() }
    }
    return
}

function Get-VisibleLines([string]$Text) {
    $fence = ''
    $htmlEnd = ''
    foreach ($line in [regex]::Matches($Text, '[^\n]+(?:\n|$)|\n')) {
        $content = $line.Value.TrimEnd([char]13, [char]10)
        if ($fence) {
            if ($content -match ('^ {0,3}' + [regex]::Escape($fence[0].ToString()) +
                    '{' + $fence.Length + ',}[ \t]*$')) { $fence = '' }
            continue
        }
        if ($htmlEnd) {
            if ($content -match $htmlEnd) { $htmlEnd = '' }
            continue
        }
        if ($content -ceq $startMarker -or $content -ceq $endMarker) {
            $line
            continue
        }
        if ($content -match '^ {0,3}<!--') {
            if ($content -notmatch '-->') { $htmlEnd = '-->' }
            continue
        }
        if ($content -match '^ {0,3}<(pre|script|style|textarea)(?:\s|>)') {
            $closing = '</' + $Matches[1] + '\s*>'
            if ($content -notmatch $closing) { $htmlEnd = $closing }
            continue
        }
        if ($content -match '^ {0,3}(\x60{3,}|~{3,})(.*)$') {
            if ($Matches[1][0] -ne [char]96 -or -not $Matches[2].Contains([char]96)) {
                $fence = $Matches[1]
                continue
            }
        }
        $line
    }
    if ($fence -or $htmlEnd) { throw 'AGENTS.md contains an unclosed code fence or HTML block. Review it before updating.' }
}

function Update-AnchorText([string]$Text, [string]$NewBlock) {
    $lines = @(Get-VisibleLines $Text)
    $starts = @($lines | Where-Object { $_.Value.TrimEnd([char]13, [char]10) -ceq $startMarker })
    $ends = @($lines | Where-Object { $_.Value.TrimEnd([char]13, [char]10) -ceq $endMarker })
    $heads = @($lines | Where-Object {
        $_.Value.TrimEnd([char]13, [char]10) -match ('^ {0,3}' + $heading.Substring(1))
    })
    if ($starts.Count -or $ends.Count) {
        if ($starts.Count -ne 1 -or $ends.Count -ne 1 -or $starts[0].Index -ge $ends[0].Index) {
            throw 'Managed anchor markers are incomplete, duplicated, or out of order.'
        }
        $start = $starts[0].Index
        $end = $ends[0].Index + $endMarker.Length
        $existing = $Text.Substring($start, $end - $start)
        $body = $existing -split '\r?\n'
        if ($heads.Count -ne 1 -or $body.Count -lt 4 -or $body[1] -notmatch $heading -or
                @($body[2..($body.Count - 2)] | Where-Object { $_ -notmatch '^- [^\r\n]+' }).Count) {
            throw 'Managed anchor contains unexpected content. Review the marked section manually.'
        }
    } elseif ($heads.Count) {
        if ($heads.Count -ne 1) { throw 'Multiple legacy anchor headings. Review them before updating.' }
        $start = $heads[0].Index
        $legacy = [regex]::Match($Text.Substring($start), '\A[^\r\n]+(?:\r?\n- [^\r\n]+){5}(?=\r?\n|\z)')
        # Unmarked anchors from releases 1.1, 1.3–1.5 and 2.0 (English), and 2.0 (Chinese).
        $known = @(
            '0a5668ae130f10fadb495f48dd7a2ae6cf92e41754d56caa99aee8f0393c9f88',
            '97825bd32adfb0412e743bb4c632733ffef036db66def37f258704765757a30f',
            '2dfdfd9fcd55bd2d5b3eb92cddf5b9637cfe2df4bde09123806813d49f7644b4',
            '8b98a248270dcb9285d37a2bf68ef462dc3c771c92b6126a48b06929b07f0756',
            '368464c2f095e5d9bb028fcf0178f2b62b59cc40708afdb68b02d28aaf2e4132',
            '9f5eb9255a83f9fa79ef387bcd9156038df6e92e2a94b933ed23385309686faf'
        )
        if (-not $legacy.Success -or (Get-Fingerprint ($strictUtf8.GetBytes($legacy.Value.Replace($crlf, $lf)))) -notin $known) {
            throw 'Unrecognized unmarked anchor. Review the section and apply the snippet manually.'
        }
        $existing = $legacy.Value
        $end = $start + $legacy.Length
    } else {
        $nl = if ($Text.Contains($crlf) -or -not $Text.Length) { $crlf } else { $lf }
        $sep = if (-not $Text.Length -or $Text -match '\r?\n\r?\n\z') { '' }
               elseif ($Text.EndsWith($lf)) { $nl } else { $nl + $nl }
        return $Text + $sep + $NewBlock.Replace($lf, $nl) + $nl
    }
    $nl = if ($existing.Contains($crlf)) { $crlf } else { $lf }
    $Text.Substring(0, $start) + $NewBlock.Replace($lf, $nl) + $Text.Substring($end)
}

$rawSnippet = [IO.File]::ReadAllText((Join-Path $source 'AGENTS.snippet.md'), $strictUtf8)
$option = if ($Language -eq 'EN') { 'A' } else { 'B' }
$block = [regex]::Match($rawSnippet, "(?ms)^## Option $option[^\r\n]+\r?\n\s*\x60{3}markdown\r?\n(.*?)\r?\n\x60{3}")
if (-not $block.Success) { throw "Missing $Language block in AGENTS.snippet.md." }
$newBlock = $block.Groups[1].Value.Replace($crlf, $lf)
if (-not $newBlock.StartsWith($startMarker + $lf) -or -not $newBlock.EndsWith($lf + $endMarker)) {
    throw "Missing managed markers in the $Language snippet."
}

Ensure-Directory $CodexHome
$agents = Join-Path $CodexHome 'AGENTS.md'
$override = Join-Path $CodexHome 'AGENTS.override.md'
$temp = Join-Path $CodexHome ".agents-anchor-$(New-Stamp).tmp"
$lock = Open-WriteLock (Join-Path $CodexHome ".$skillName-anchor.lock")
try {
    Assert-RealPath $agents
    if (Test-Path -LiteralPath $override -PathType Leaf) {
        Write-Warning "Codex may prefer $override. Updating $agents only."
    }
    $exists = [IO.File]::Exists($agents)
    $bytes = if ($exists) { [byte[]][IO.File]::ReadAllBytes($agents) }
    $bom = $bytes.Length -ge 3 -and $bytes[0] -eq 239 -and $bytes[1] -eq 187 -and $bytes[2] -eq 191
    $encoding = [Text.UTF8Encoding]::new($bom, $true)
    $text = if ($exists) {
        $data = [byte[]]@($bytes)
        $offset = if ($bom) { 3 } else { 0 }
        $encoding.GetString($data, $offset, $data.Length - $offset)
    } else { '' }
    if ($text.Contains([char]0) -or $text -match '\r(?!\n)') { throw 'AGENTS.md must use UTF-8 with LF or CRLF line endings.' }
    $updated = Update-AnchorText $text $newBlock
    if ($updated -ceq $text) { Write-Output "Anchor already current in $agents."; return }
    [IO.File]::WriteAllText($temp, $updated, $encoding)
    if ($exists) {
        $backups = Join-Path $CodexHome 'backups'
        Ensure-Directory $backups
        $backup = Join-Path $backups "AGENTS-backup-$(New-Stamp).md"
        if ([Convert]::ToBase64String($data) -cne [Convert]::ToBase64String([IO.File]::ReadAllBytes($agents))) {
            throw 'AGENTS.md changed while preparing the update. Retry with the current file.'
        }
        [IO.File]::Replace($temp, $agents, $backup)
        Write-Output "Updated the $Language anchor in $agents (backup: $backup)."
    } else {
        [IO.File]::Move($temp, $agents)
        Write-Output "Created $agents with the $Language anchor."
    }
} finally {
    try { [IO.File]::Delete($temp) }
    finally { $lock.Dispose() }
}
