# snf-ai-skills-setup

One-command setup for the **snf-ai-skills** environment. Installs Claude Desktop, Git, GitHub CLI (`gh`), and Node.js (LTS), generates an SSH key, authenticates GitHub, and clones the repository — on both **macOS** and **Windows**.

The script detects your OS automatically: it uses **Homebrew** on macOS and **winget** on Windows.

---

## Quick start

### macOS

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/speedandfunction/snf-ai-skills-setup/main/setup-snf.sh)
```

> Use `bash <(curl …)` rather than `curl … | bash` — the interactive steps (`gh auth login`, email prompt) need a real terminal on stdin. The script detects the `curl … | bash` form and tells you so instead of failing silently.
> Pass the email for the SSH key up front: prefix with `GIT_EMAIL=you@speedandfunction.com `
> Clone somewhere other than `~/snf-ai-skills`: prefix with `TARGET_DIR=/path/to/checkout `

### Windows (PowerShell)

```powershell
$u="https://raw.githubusercontent.com/speedandfunction/snf-ai-skills-setup/main/setup-snf.ps1"
$f="$env:TEMP\setup-snf.ps1"
irm $u -OutFile $f
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force
& $f                          # or:  & $f -GitEmail you@speedandfunction.com
```

> Clone somewhere other than `$HOME\snf-ai-skills`: add `-TargetDir C:\path\to\checkout`

> `-Scope Process` lifts the script block only for the current terminal window — nothing permanent.

Prefer a local file? Download it from the repo (**Download raw file**) and run `bash setup-snf.sh` / `& .\setup-snf.ps1`.

---

## What it does

1. Installs **Claude Desktop**
2. Installs **Git**
3. Installs **GitHub CLI** (`gh`)
4. Installs **Node.js (LTS)** — required for MCP servers
5. Generates an **SSH key** (if one doesn't exist yet)
6. Authenticates `gh` with GitHub (SSH protocol, requesting the `admin:public_key` scope needed for step 7)
7. Adds the SSH key to your GitHub account — skipped if that exact key is already on the account
8. Verifies that SSH to GitHub actually works and that you can see the repo, **before** attempting the clone
9. Clones the **snf-ai-skills** repository into `~/snf-ai-skills` (override with `TARGET_DIR` / `-TargetDir`)
10. Prints installed tool versions for verification

Every step is **idempotent** — anything already installed is skipped, so the script is safe to re-run if something gets interrupted.

If any step fails, the script **stops there** with an actionable message. It never prints "Setup complete" over a failure.

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
| [`docs/SETUP-GUIDE.md`](docs/SETUP-GUIDE.md) | Full guide (English) — detailed steps, troubleshooting, FAQ |


---

## Troubleshooting (quick)

| Problem | Fix |
| --- | --- |
| macOS `operation not permitted` | `bash setup-snf.sh` (bypasses Gatekeeper) |
| Windows `running scripts is disabled` | `Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass` |
| `command not found` for git/gh/node | Open a new terminal (PATH refresh) and re-run |
| `Permission denied (publickey)` | Confirm org access; `ssh -T git@github.com` to test |
| `insufficient OAuth scopes` when adding the key | `gh auth refresh -h github.com -s admin:public_key`, then re-run |

Full troubleshooting lives in the [docs](docs/SETUP-GUIDE.md#10-troubleshooting).

---

_Questions — message the team on Slack._