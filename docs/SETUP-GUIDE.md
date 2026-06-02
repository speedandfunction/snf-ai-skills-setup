# S&F AI Skills — Setup Script Guide

A complete guide to working with the automated setup scripts (`setup-snf.sh` for macOS and `setup-snf.ps1` for Windows). These scripts automate the **"Setup — Step by Step"** section of the *Claude Skills — Getting Started* guide.

---

## Table of Contents

1. [What the scripts do](#1-what-the-scripts-do)
2. [Prerequisites](#2-prerequisites)
3. [Installing the script](#3-installing-the-script)
4. [Running on macOS](#4-running-on-macos)
5. [Running on Windows](#5-running-on-windows)
6. [What happens during the run](#6-what-happens-during-the-run)
7. [Interactive steps](#7-interactive-steps)
8. [After installation](#8-after-installation)
9. [Re-running the script](#9-re-running-the-script)
10. [Troubleshooting](#10-troubleshooting)
11. [FAQ](#11-faq)

---

## 1. What the scripts do

A single run installs and configures everything needed to work with the `snf-ai-skills` repository:

| Step | Action |
| --- | --- |
| 1 | Installs **Claude Desktop** |
| 2 | Installs **Git** |
| 3 | Installs **GitHub CLI** (`gh`) |
| 4 | Installs **Node.js (LTS)** — required for MCP servers |
| 5 | Generates an **SSH key** (if one doesn't exist yet) |
| 6 | Authenticates `gh` with GitHub |
| 7 | Adds the SSH key to your GitHub account |
| 8 | Clones the `snf-ai-skills` repository |
| 9 | Prints the versions of the installed tools for verification |

The script detects the operating system on its own: it uses **Homebrew** on macOS and **winget** on Windows.

---

## 2. Prerequisites

- **Access to the `speedandfunction` GitHub organization.** If you don't have access, ask [@Al Shkundia] to add you — without it the clone step won't work.
- **A work Anthropic account** to sign in to Claude Desktop.
- **Internet access** and administrator rights on the machine (to install software).

> You do **not** need to install the tools (Git, Node.js, etc.) beforehand — that's exactly what the script does.

---

## 3. Installing the script

The repository is public, so the script can be run with **a single command straight from GitHub** — no need to download anything manually.

**macOS:**

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/speedandfunction/snf-ai-skills-setup/main/setup-snf.sh)
```

**Windows (PowerShell):**

```powershell
$u="https://raw.githubusercontent.com/speedandfunction/snf-ai-skills-setup/main/setup-snf.ps1"
$f="$env:TEMP\setup-snf.ps1"
irm $u -OutFile $f
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force
& $f
```

> On macOS use `bash <(curl …)`, **not** `curl … | bash` — the interactive steps (`gh auth login`, email prompt) need a real terminal on stdin, which `bash <(…)` preserves.

Per-OS details, passing the email, and running from a local file are covered in the sections below.

### Alternative — download the file manually

If you'd rather work with a local file: open the file on GitHub and click **Download raw file**, or **Code → Download ZIP** for the whole repo. Save it to a convenient folder (e.g. `~/Downloads`):

- **macOS:** `setup-snf.sh`
- **Windows:** `setup-snf.ps1`

---

## 4. Running on macOS

### Option A — one command from GitHub (recommended)

Nothing to download — open **Terminal** and paste:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/speedandfunction/snf-ai-skills-setup/main/setup-snf.sh)
```

With the email for the SSH key up front:

```bash
GIT_EMAIL=you@speedandfunction.com bash <(curl -fsSL https://raw.githubusercontent.com/speedandfunction/snf-ai-skills-setup/main/setup-snf.sh)
```

> Use `bash <(curl …)`, not `curl … | bash`, otherwise the interactive steps (`gh auth login`, email prompt) break. Bonus: running straight from the network means there's no file on disk, so no Gatekeeper quarantine pops up.

### Option B — from a local file

If you downloaded the script manually, change into its folder and run it via `bash` (this bypasses Gatekeeper for downloaded files):

```bash
cd ~/Downloads
bash setup-snf.sh
```

### Option C — with execute permission

```bash
chmod +x setup-snf.sh
xattr -d com.apple.quarantine setup-snf.sh   # removes the "downloaded from the internet" flag
./setup-snf.sh
```

If `xattr` reports `No such xattr`, there's no quarantine flag — just run `./setup-snf.sh`.

> **About Xcode:** the full Xcode is **not required**. You only need the **Command Line Tools** — Homebrew will offer to install them automatically during setup. Accept in the pop-up window (or install them in advance: `xcode-select --install`).

---

## 5. Running on Windows

### Option A — native PowerShell (recommended)

Open **PowerShell** and paste — the command downloads the script from GitHub and runs it:

```powershell
$u="https://raw.githubusercontent.com/speedandfunction/snf-ai-skills-setup/main/setup-snf.ps1"
$f="$env:TEMP\setup-snf.ps1"
irm $u -OutFile $f
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force
& $f
```

To pass the email up front, replace the last line with:

```powershell
& $f -GitEmail you@speedandfunction.com
```

> `Set-ExecutionPolicy -Scope Process` lifts the block only for the current terminal window — nothing permanent. If you downloaded `setup-snf.ps1` manually, just run `& "$HOME\Downloads\setup-snf.ps1"` instead of the first two lines.

### Option B — bash script in Git Bash / WSL

If you already have **Git Bash** or **WSL**, you can run the sh version with the same one-liner as on macOS:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/speedandfunction/snf-ai-skills-setup/main/setup-snf.sh)
```

> On a clean Windows machine without any bash, use Option A (PowerShell), since bash only appears together with Git.

---

## 6. What happens during the run

The script works step by step and logs each action with colored markers:

- `==>` — started a step
- ` ✔ ` (Mac) / ` [+] ` (Win) — success
- ` ! ` / ` [!] ` — warning (non-critical)
- ` ✘ ` / ` [x] ` — error

Each step is **idempotent**: if a tool is already installed, the script detects it and skips the installation.

---

## 7. Interactive steps

A few steps can't be done silently — they require your input:

1. **Email for the SSH key** — if you didn't pass it via `GIT_EMAIL` / `-GitEmail`, the script will ask for it in the console.
2. **`gh auth login`** — the GitHub authentication flow opens. Choose:
   - `GitHub.com`
   - the **SSH** protocol
   - authentication **via the browser**
3. **Confirming the Command Line Tools installation** (macOS only, if they're not present yet).

---

## 8. After installation

At the end the script prints the versions of `git`, `gh`, and `node` for verification. Then, manually:

1. Open **Claude Desktop**.
2. Switch to **Claude Code** mode.
3. Open the `snf-ai-skills` folder.
4. In Claude Desktop settings, connect the connectors:
   - **ClickUp** — tasks
   - **Gmail** — email
   - **Google Calendar** — calendar
   - **Google Docs** — documents
   - **Google Sheets** — spreadsheets

> The connectors are connected manually (via OAuth); the script doesn't do this — it's a one-time setup.

---

## 9. Re-running the script

The script is safe to run as many times as you like:

- already installed tools are **skipped**;
- an existing SSH key is **not overwritten**;
- an already cloned repository is **not cloned again**;
- an already authenticated `gh` **won't ask for login again**.

Handy if something got interrupted halfway — just run it again.

---

## 10. Troubleshooting

### macOS: `zsh: operation not permitted`

Gatekeeper blocked the downloaded file. Easiest fix — run straight from GitHub (no file on disk, no quarantine):

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/speedandfunction/snf-ai-skills-setup/main/setup-snf.sh)
```

If running a local file:

```bash
xattr -d com.apple.quarantine setup-snf.sh && chmod +x setup-snf.sh && ./setup-snf.sh
```

### macOS: `permission denied`

No execute permission:

```bash
chmod +x setup-snf.sh
```

### Windows: `running scripts is disabled on this system`

Allow scripts for the current session:

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
```

### Windows: `winget not found`

Update **App Installer** from the Microsoft Store (winget ships with it), then restart the terminal.

### `command not found` for git / gh / node right after installation

PATH hasn't refreshed yet. **Close and open a new terminal** and run the script again — it will skip what's already installed and finish the rest.

### Clone failed / `Permission denied (publickey)`

- Make sure you've been added to the `speedandfunction` GitHub organization.
- Make sure the SSH key was added to GitHub (the script does this; manually: `gh ssh-key add ~/.ssh/id_ed25519.pub`).
- Test the connection: `ssh -T git@github.com`.

### MCP servers won't connect in Claude Code

Make sure Node.js is installed: `node --version`. MCP servers use `npx`, which requires Node.js.

---

## 11. FAQ

**Do I need the full Xcode on Mac?**
No. Only the Command Line Tools, which Homebrew installs automatically.

**Can I run it without administrator rights?**
Installing software usually requires admin rights. The other steps (SSH, clone) don't.

**Will the script delete or break anything already installed?**
No. It only adds what's missing and doesn't touch what's already configured. An existing SSH key is not overwritten.

**I'm on Linux/WSL — will the script work?**
On clean Linux/WSL, `setup-snf.sh` will exit with a message, because the guide targets macOS and Windows (Claude Desktop exists only for them). On Linux, install git/gh/node manually via `apt`.

**Where do I change the repository name or path?**
At the top of the script — the `Configuration` block (variables `REPO_SSH`, `REPO_DIR`).

---

_Questions — message the team on Slack._