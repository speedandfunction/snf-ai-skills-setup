#Requires -Version 5.1
<#
.SYNOPSIS
    Automatic installation of tools from the "Claude Skills — Getting Started"
    guide (Speed & Function) — native Windows version.

.DESCRIPTION
    Installs: Claude Desktop, Git, GitHub CLI (gh), Node.js (LTS) via winget,
    generates an SSH key, adds it to GitHub, authenticates gh, and clones the repo.

.PARAMETER GitEmail
    Email used for the SSH key. If omitted, you will be prompted.

.EXAMPLE
    # Run in PowerShell (you may need to allow scripts for this session):
    Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
    .\setup-snf.ps1
    .\setup-snf.ps1 -GitEmail you@speedandfunction.com
#>

[CmdletBinding()]
param(
    [string]$GitEmail = ""
)

$ErrorActionPreference = "Stop"

# ────────────────────────────── Configuration ─────────────────────────────
$RepoSsh = "git@github.com:speedandfunction/snf-ai-skills.git"
$RepoDir = "snf-ai-skills"
$SshKey  = Join-Path $HOME ".ssh\id_ed25519"

# ──────────────────────────────── Logging ─────────────────────────────────
function Write-Log  { param($m) Write-Host "==> $m" -ForegroundColor Cyan }
function Write-Ok   { param($m) Write-Host " [+] $m" -ForegroundColor Green }
function Write-Warn { param($m) Write-Host " [!] $m" -ForegroundColor Yellow }
function Write-Err  { param($m) Write-Host " [x] $m" -ForegroundColor Red }
function Test-Cmd   { param($name) [bool](Get-Command $name -ErrorAction SilentlyContinue) }

# ──────────────────────────── winget helpers ──────────────────────────────
function Install-Winget {
    param([string]$Id, [string]$Friendly = $Id)

    # Already installed?
    $listed = winget list --id $Id -e 2>$null
    if ($LASTEXITCODE -eq 0 -and $listed -match [regex]::Escape($Id)) {
        Write-Ok "$Friendly already installed"
        return
    }
    Write-Log "Installing $Friendly..."
    winget install --id $Id -e --silent `
        --accept-package-agreements --accept-source-agreements
    if ($LASTEXITCODE -ne 0) {
        Write-Warn "Could not install $Friendly via winget (exit $LASTEXITCODE)."
    } else {
        Write-Ok "$Friendly installed"
    }
}

function Install-Tools {
    if (-not (Test-Cmd winget)) {
        Write-Err "winget not found. Update 'App Installer' from the Microsoft Store, then re-run."
        exit 1
    }
    Write-Log "Installing Git, GitHub CLI, Node.js (LTS), Claude Desktop via winget..."
    Install-Winget -Id "Git.Git"          -Friendly "Git"
    Install-Winget -Id "GitHub.cli"       -Friendly "GitHub CLI"
    Install-Winget -Id "OpenJS.NodeJS.LTS" -Friendly "Node.js (LTS)"
    Install-Winget -Id "Anthropic.Claude" -Friendly "Claude Desktop"

    # Refresh PATH for the current session so freshly installed CLIs are usable
    $machine = [System.Environment]::GetEnvironmentVariable("Path","Machine")
    $user    = [System.Environment]::GetEnvironmentVariable("Path","User")
    $env:Path = "$machine;$user"
    Write-Warn "If a command isn't found below, open a NEW terminal so PATH is fully refreshed."
}

# ─────────────────────────────── SSH key ──────────────────────────────────
function Initialize-SshKey {
    $pub = "$SshKey.pub"
    if (Test-Path $pub) {
        Write-Ok "SSH key already exists: $pub"
        return
    }
    Write-Log "No SSH key found — generating a new one..."
    if ([string]::IsNullOrWhiteSpace($GitEmail)) {
        $script:GitEmail = Read-Host "   Enter the email for the key (e.g. you@speedandfunction.com)"
    }
    $sshDir = Split-Path $SshKey -Parent
    if (-not (Test-Path $sshDir)) { New-Item -ItemType Directory -Path $sshDir | Out-Null }
    ssh-keygen -t ed25519 -C $GitEmail -f $SshKey -N '""'
    Write-Ok "Generated: $pub"
}

# ──────────────────── GitHub: auth + key ──────────────────────────────────
function Initialize-GitHub {
    if (-not (Test-Cmd gh)) {
        Write-Warn "gh is not in PATH yet — skipping auth. Open a new terminal and run the script again."
        return
    }

    gh auth status 2>$null | Out-Null
    if ($LASTEXITCODE -eq 0) {
        Write-Ok "GitHub CLI already authenticated"
    } else {
        Write-Log "Authenticating with GitHub (choose GitHub.com -> SSH -> via browser)..."
        gh auth login
    }

    Write-Log "Adding the SSH key to GitHub..."
    $title = "$env:COMPUTERNAME ($(Get-Date -Format yyyy-MM-dd))"
    gh ssh-key add "$SshKey.pub" --title $title 2>$null
    if ($LASTEXITCODE -eq 0) { Write-Ok "Key added" }
    else { Write-Warn "Key is probably already added — skipping." }
}

# ─────────────────────────── Clone repository ─────────────────────────────
function Clone-Repo {
    if (Test-Path (Join-Path $RepoDir ".git")) {
        Write-Ok "Repository already cloned into .\$RepoDir"
        return
    }
    Write-Log "Cloning $RepoSsh..."
    git clone $RepoSsh $RepoDir
    if ($LASTEXITCODE -eq 0) {
        Write-Ok "Done. Open the .\$RepoDir folder in Claude Code."
    } else {
        Write-Err "Clone failed. Check access to the 'speedandfunction' org and your SSH key."
    }
}

# ──────────────────────────────── Verify ──────────────────────────────────
function Test-Versions {
    Write-Log "Checking versions:"
    foreach ($c in @("git","gh","node")) {
        if (Test-Cmd $c) {
            $v = (& $c --version 2>&1 | Select-Object -First 1)
            "    {0,-6} {1}" -f $c, $v | Write-Host
        } else {
            Write-Warn "$c not in PATH (open a new terminal)"
        }
    }
}

# ─────────────────────────────────── Main ─────────────────────────────────
function Main {
    Write-Log "Detected OS: Windows ($([System.Environment]::OSVersion.Version))"

    if (-not $IsWindows -and $PSVersionTable.PSVersion.Major -ge 6) {
        Write-Err "This script is for Windows. On macOS use setup-snf.sh instead."
        exit 1
    }

    Install-Tools
    Initialize-SshKey
    Initialize-GitHub
    Clone-Repo
    Test-Versions

    Write-Host ""
    Write-Ok "Setup complete"
    Write-Host "    Next: open Claude Desktop -> Claude Code mode -> open the .\$RepoDir folder"
    Write-Host "    and connect the connectors: ClickUp, Gmail, Google Calendar/Docs/Sheets."
}

Main