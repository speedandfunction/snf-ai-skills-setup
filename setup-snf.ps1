#Requires -Version 5.1
<#
.SYNOPSIS
    Automatic installation of tools from the "Claude Skills — Getting Started"
    guide (Speed & Function) — native Windows version.

.DESCRIPTION
    Installs: Claude Desktop, Git, GitHub CLI (gh), Node.js (LTS) via winget,
    generates an SSH key, adds it to GitHub, authenticates gh, and clones the repo.

    Every step is idempotent — re-running the script after a failure picks up
    where it left off.

.PARAMETER GitEmail
    Email used for the SSH key. If omitted, you will be prompted.

.PARAMETER TargetDir
    Where to clone the repository. Defaults to $HOME\snf-ai-skills.

.EXAMPLE
    # Run in PowerShell (you may need to allow scripts for this session):
    Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
    .\setup-snf.ps1
    .\setup-snf.ps1 -GitEmail you@speedandfunction.com
#>

[CmdletBinding()]
param(
    [string]$GitEmail = "",
    [string]$TargetDir = ""
)

$ErrorActionPreference = "Stop"

# ────────────────────────────── Configuration ─────────────────────────────
$RepoSsh  = "git@github.com:speedandfunction/snf-ai-skills.git"
$RepoOrg  = "speedandfunction"
$RepoName = "snf-ai-skills"
$SshKey   = Join-Path $HOME ".ssh\id_ed25519"
if ([string]::IsNullOrWhiteSpace($TargetDir)) { $TargetDir = Join-Path $HOME $RepoName }

# ──────────────────────────────── Logging ─────────────────────────────────
function Write-Log  { param($m) Write-Host "==> $m" -ForegroundColor Cyan }
function Write-Ok   { param($m) Write-Host " [+] $m" -ForegroundColor Green }
function Write-Warn { param($m) Write-Host " [!] $m" -ForegroundColor Yellow }
function Write-Err  { param($m) Write-Host " [x] $m" -ForegroundColor Red }
function Test-Cmd   { param($name) [bool](Get-Command $name -ErrorAction SilentlyContinue) }

# Hard stop with an actionable message. Never print "Setup complete" over a failure.
function Stop-Setup {
    param($m)
    Write-Err $m
    Write-Host ""
    Write-Err "Setup did NOT complete. Fix the above and re-run — the script is idempotent."
    exit 1
}

# IMPORTANT: $ErrorActionPreference = "Stop" does NOT apply to native executables
# (gh / git / ssh / winget). Their failures surface only in $LASTEXITCODE, so every
# native call below checks it explicitly instead of assuming success.

# Guard every prompt: in a non-interactive session Read-Host either throws or hangs.
function Assert-Interactive {
    if ([Environment]::UserInteractive) { return }
    Write-Err "This step needs to ask you something, but the session is not interactive."
    Write-Err "Run the script from an interactive PowerShell window, or pass the answer up front:"
    Stop-Setup "    .\setup-snf.ps1 -GitEmail you@speedandfunction.com"
}

# ──────────────────────────── winget helpers ──────────────────────────────
function Install-Winget {
    param(
        [string]$Id,
        [string]$Friendly = $Id,
        [string]$Cmd = "",
        [switch]$Required
    )

    if ($Cmd -and (Test-Cmd $Cmd)) {
        Write-Ok "$Friendly already available ($Cmd) — skipping"
        return
    }

    $listed = winget list --id $Id -e 2>$null
    if ($LASTEXITCODE -eq 0 -and $listed -match [regex]::Escape($Id)) {
        Write-Ok "$Friendly already installed"
        return
    }
    Write-Log "Installing $Friendly..."
    winget install --id $Id -e --silent `
        --accept-package-agreements --accept-source-agreements
    if ($LASTEXITCODE -ne 0) {
        if ($Required) {
            Stop-Setup "Could not install $Friendly via winget (exit $LASTEXITCODE). Install it manually, then re-run."
        }
        Write-Warn "Could not install $Friendly via winget (exit $LASTEXITCODE)."
    } else {
        Write-Ok "$Friendly installed"
    }
}

function Install-Tools {
    if (-not (Test-Cmd winget)) {
        Stop-Setup "winget not found. Update 'App Installer' from the Microsoft Store, then re-run."
    }
    Write-Log "Installing Git, GitHub CLI, Node.js (LTS), Claude Desktop via winget..."
    Install-Winget -Id "Git.Git"           -Friendly "Git"           -Cmd git  -Required
    Install-Winget -Id "GitHub.cli"        -Friendly "GitHub CLI"     -Cmd gh   -Required
    Install-Winget -Id "OpenJS.NodeJS.LTS" -Friendly "Node.js (LTS)"  -Cmd node -Required
    Install-Winget -Id "Anthropic.Claude"  -Friendly "Claude Desktop"

    # Refresh PATH for the current session so freshly installed CLIs are usable
    $machine = [System.Environment]::GetEnvironmentVariable("Path","Machine")
    $user    = [System.Environment]::GetEnvironmentVariable("Path","User")
    $env:Path = "$machine;$user"
}

# ─────────────────────────────── SSH key ──────────────────────────────────
function Initialize-SshKey {
    $pub = "$SshKey.pub"
    if (Test-Path $pub) {
        Write-Ok "SSH key already exists: $pub"
    } else {
        Write-Log "No SSH key found — generating a new one..."
        if ([string]::IsNullOrWhiteSpace($GitEmail)) {
            Assert-Interactive
            $script:GitEmail = Read-Host "   Enter the email for the key (e.g. you@speedandfunction.com)"
        }
        if ([string]::IsNullOrWhiteSpace($GitEmail)) { Stop-Setup "Email must not be empty." }
        $sshDir = Split-Path $SshKey -Parent
        if (-not (Test-Path $sshDir)) { New-Item -ItemType Directory -Path $sshDir | Out-Null }
        ssh-keygen -t ed25519 -C $GitEmail -f $SshKey -N '""'
        if ($LASTEXITCODE -ne 0 -or -not (Test-Path $pub)) {
            Stop-Setup "ssh-keygen failed. Check that $sshDir is writable."
        }
        Write-Ok "Generated: $pub"
    }

    # Optional convenience: the ssh-agent service ships Disabled on Windows, so a
    # failure here is harmless — git reads the key file directly.
    $svc = Get-Service ssh-agent -ErrorAction SilentlyContinue
    if ($svc -and $svc.Status -eq "Running") {
        ssh-add $SshKey 2>$null | Out-Null
        if ($LASTEXITCODE -eq 0) { Write-Ok "Key loaded into ssh-agent" }
    } else {
        Write-Warn "ssh-agent is not running (harmless — git reads the key file directly)."
    }
}

# Pre-seed github.com so the first SSH connection never stops on
# "The authenticity of host 'github.com' can't be established... (yes/no)".
function Add-GitHubHostKey {
    $sshDir = Split-Path $SshKey -Parent
    if (-not (Test-Path $sshDir)) { New-Item -ItemType Directory -Path $sshDir | Out-Null }
    $knownHosts = Join-Path $sshDir "known_hosts"
    if (-not (Test-Path $knownHosts)) { New-Item -ItemType File -Path $knownHosts | Out-Null }

    ssh-keygen -F github.com 2>$null | Out-Null
    if ($LASTEXITCODE -eq 0) { Write-Ok "github.com already in known_hosts"; return }

    Write-Log "Adding github.com to known_hosts..."
    $scan = ssh-keyscan -t rsa,ecdsa,ed25519 github.com 2>$null
    if ($LASTEXITCODE -eq 0 -and $scan) {
        Add-Content -Path $knownHosts -Value $scan
        Write-Ok "github.com host key recorded"
    } else {
        Write-Warn "ssh-keyscan failed — you may be asked to confirm github.com's fingerprint."
    }
}

# ──────────────────── GitHub: auth + key ──────────────────────────────────
function Test-GhKeyScope {
    $status = gh auth status --hostname github.com 2>&1 | Out-String
    return ($status -match "admin:public_key")
}

function Initialize-GitHub {
    gh auth status --hostname github.com 2>$null | Out-Null
    if ($LASTEXITCODE -eq 0) {
        Write-Ok "GitHub CLI already authenticated"
    } else {
        Write-Log "Authenticating with GitHub — a browser window will open..."
        Assert-Interactive
        # Explicit flags instead of a free-form wizard: the old interactive prompt let
        # people pick HTTPS, which silently produced a token WITHOUT admin:public_key
        # and broke the key upload two steps later.
        # --skip-ssh-key: we upload the key ourselves below, with a real success check.
        gh auth login `
            --hostname github.com `
            --git-protocol ssh `
            --scopes admin:public_key `
            --skip-ssh-key `
            --web
        if ($LASTEXITCODE -ne 0) {
            Stop-Setup "GitHub login failed or was cancelled. Re-run the script to try again."
        }
        gh auth status --hostname github.com 2>$null | Out-Null
        if ($LASTEXITCODE -ne 0) {
            Stop-Setup "GitHub login reported success but 'gh auth status' disagrees. Run 'gh auth login' manually, then re-run this script."
        }
        Write-Ok "Authenticated with GitHub"
    }

    if (-not (Test-GhKeyScope)) {
        Write-Log "Your token is missing the 'admin:public_key' scope — requesting it..."
        Assert-Interactive
        gh auth refresh --hostname github.com --scopes admin:public_key
        if ($LASTEXITCODE -ne 0 -or -not (Test-GhKeyScope)) {
            Stop-Setup "Could not add the 'admin:public_key' scope. Run: gh auth refresh -h github.com -s admin:public_key"
        }
    }
    Write-Ok "Token has the 'admin:public_key' scope"
}

# Compare against the keys already on the account instead of guessing from an exit
# code — the old code reported "probably already added" for genuine failures.
function Test-KeyOnGitHub {
    $parts = ((Get-Content "$SshKey.pub" -Raw).Trim()) -split '\s+'
    if ($parts.Count -lt 2) { return $false }
    $body = "$($parts[0]) $($parts[1])"
    $remote = gh api user/keys --paginate --jq '.[].key' 2>$null
    if ($LASTEXITCODE -ne 0) { return $false }
    foreach ($k in $remote) {
        if ($k.Trim() -eq $body) { return $true }
    }
    return $false
}

function Add-SshKeyToGitHub {
    if (Test-KeyOnGitHub) {
        Write-Ok "This SSH key is already registered on your GitHub account"
        return
    }
    Write-Log "Adding the SSH key to GitHub..."
    $title = "$env:COMPUTERNAME ($(Get-Date -Format yyyy-MM-dd))"
    $out = gh ssh-key add "$SshKey.pub" --title $title 2>&1 | Out-String
    if ($LASTEXITCODE -eq 0) {
        Write-Ok "Key added as `"$title`""
    } else {
        Write-Err $out.Trim()
        Write-Err "Add it manually at https://github.com/settings/ssh/new — the key is:"
        Write-Host (Get-Content "$SshKey.pub" -Raw)
        Stop-Setup "Failed to add the SSH key to GitHub."
    }
}

# Prove the key works BEFORE cloning, so a failure names the real cause.
function Test-GitHubSsh {
    Write-Log "Verifying SSH access to GitHub..."
    # 'ssh -T git@github.com' always exits 1, so match on the output, not the code.
    $out = ssh -o StrictHostKeyChecking=accept-new -o IdentitiesOnly=yes -i $SshKey -T git@github.com 2>&1 | Out-String
    if ($out -match "successfully authenticated") {
        $first = (($out.Trim() -split "`n")[0]).Trim()
        Write-Ok "SSH to GitHub works ($first)"
    } else {
        Write-Err $out.Trim()
        Stop-Setup "SSH authentication to GitHub failed. Check that $SshKey.pub is listed at https://github.com/settings/keys"
    }
}

function Test-OrgAccess {
    gh api "repos/$RepoOrg/$RepoName" --jq ".full_name" 2>$null | Out-Null
    if ($LASTEXITCODE -eq 0) {
        Write-Ok "You have access to $RepoOrg/$RepoName"
    } else {
        Stop-Setup "Your GitHub account cannot see $RepoOrg/$RepoName. Ask an org owner to invite you to the '$RepoOrg' organisation, accept the invite, then re-run this script."
    }
}

# ─────────────────────────── Clone repository ─────────────────────────────
function Clone-Repo {
    if (Test-Path (Join-Path $TargetDir ".git")) {
        Write-Ok "Repository already cloned into $TargetDir"
        return
    }
    if (Test-Path $TargetDir) {
        Stop-Setup "$TargetDir already exists but is not a git checkout. Move or remove it, then re-run."
    }
    Write-Log "Cloning $RepoSsh into $TargetDir..."
    git clone $RepoSsh $TargetDir
    if ($LASTEXITCODE -ne 0) {
        Stop-Setup "Clone failed. Check access to the '$RepoOrg' org and your SSH key."
    }
    Write-Ok "Cloned into $TargetDir"
}

# ──────────────────────────────── Verify ──────────────────────────────────
function Test-Versions {
    Write-Log "Checking versions:"
    $missing = $false
    foreach ($c in @("git","gh","node")) {
        if (Test-Cmd $c) {
            $v = (& $c --version 2>&1 | Select-Object -First 1)
            "    {0,-6} {1}" -f $c, $v | Write-Host
        } else {
            Write-Warn "$c not in PATH (open a new terminal)"
            $missing = $true
        }
    }
    if ($missing) {
        Write-Warn "Some tools are missing from this session's PATH — open a NEW terminal and re-run to confirm."
    }
}

# ─────────────────────────────────── Main ─────────────────────────────────
function Main {
    Write-Log "Detected OS: Windows ($([System.Environment]::OSVersion.Version))"

    if (-not $IsWindows -and $PSVersionTable.PSVersion.Major -ge 6) {
        Stop-Setup "This script is for Windows. On macOS use setup-snf.sh instead."
    }

    Install-Tools

    if (-not (Test-Cmd gh)) {
        Stop-Setup "'gh' is not in this session's PATH yet. Open a NEW PowerShell window and re-run the script — it will pick up where it left off."
    }

    Initialize-SshKey
    Add-GitHubHostKey
    Initialize-GitHub
    Add-SshKeyToGitHub
    Test-GitHubSsh
    Test-OrgAccess
    Clone-Repo
    Test-Versions

    Write-Host ""
    Write-Ok "Setup complete"
    Write-Host "    Repository: $TargetDir"
    Write-Host "    Next: open Claude Desktop -> Claude Code mode -> open the $TargetDir folder"
    Write-Host "    and connect the connectors: ClickUp, Gmail, Google Calendar/Docs/Sheets."
}

Main
