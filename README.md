# snf-ai-skills-setup

One-command setup for the **snf-ai-skills** environment. Installs Claude Desktop, Git, GitHub CLI (`gh`), and Node.js (LTS), generates an SSH key, authenticates GitHub, and clones the repository — on both **macOS** and **Windows**.

The script detects your OS automatically: it uses **Homebrew** on macOS and **winget** on Windows.

---

## Quick start

### macOS

```bash
cd ~/Downloads        # the folder where you saved the script
bash setup-snf.sh
```

> Running via `bash` bypasses the Gatekeeper block on downloaded files.
> You can pass the email for the SSH key up front: `GIT_EMAIL=you@speedandfunction.com bash setup-snf.sh`

### Windows (PowerShell)

```powershell
cd ~\Downloads
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
.\setup-snf.ps1
```

> `-Scope Process` lifts the script block only for the current terminal window — nothing permanent.
> Pass the email up front: `.\setup-snf.ps1 -GitEmail you@speedandfunction.com`

---

## What it does

1. Installs **Claude Desktop**
2. Installs **Git**
3. Installs **GitHub CLI** (`gh`)
4. Installs **Node.js (LTS)** — required for MCP servers
5. Generates an **SSH key** (if one doesn't exist yet)
6. Authenticates `gh` with GitHub
7. Adds the SSH key to your GitHub account
8. Clones the **snf-ai-skills** repository
9. Prints installed tool versions for verification

Every step is **idempotent** — anything already installed is skipped, so the script is safe to re-run if something gets interrupted.

---

## Prerequisites

- Access to the `speedandfunction` GitHub organization (ask to be added if you don't have it — the clone step needs it).
- A work Anthropic account for signing in to Claude Desktop.
- Internet access and administrator rights on the machine.

> macOS: the full Xcode is **not** required — only the Command Line Tools, which Homebrew installs automatically.

---

## After installation

1. Open **Claude Desktop** and switch to **Claude Code** mode.
2. Open the `snf-ai-skills` folder.
3. Connect the connectors in Claude Desktop settings: **ClickUp**, **Gmail**, **Google Calendar**, **Google Docs**, **Google Sheets** (one-time OAuth setup, not handled by the script).

---

## Documentation

| Document | Description |
| --- | --- |
| [`docs/SETUP-GUID.md`](docs/SETUP-GUIDE.md) | Full guide (English) — detailed steps, troubleshooting, FAQ |


---

## Troubleshooting (quick)

| Problem | Fix |
| --- | --- |
| macOS `operation not permitted` | `bash setup-snf.sh` (bypasses Gatekeeper) |
| Windows `running scripts is disabled` | `Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass` |
| `command not found` for git/gh/node | Open a new terminal (PATH refresh) and re-run |
| `Permission denied (publickey)` | Confirm org access; `ssh -T git@github.com` to test |

Full troubleshooting lives in the [docs](docs/SETUP-GUIDE.md#10-troubleshooting).

---

_Questions — message the team on Slack._