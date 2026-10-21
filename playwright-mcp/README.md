# Playwright MCP for Claude Desktop (macOS)

One command connects the [Playwright MCP](https://github.com/microsoft/playwright-mcp) browser connector to **Claude Desktop on macOS**. With it, Claude can open pages in Chrome (or Chromium), click, fill in forms, read page content and take screenshots.

The script installs anything that is missing, writes the connector into Claude Desktop's config, and then opens a test page to check that the server works.

---

## Quick start

```bash
curl -fsSL https://raw.githubusercontent.com/speedandfunction/snf-ai-skills-setup/main/playwright-mcp/playwright-mcp-setup.sh | bash
```

Then **quit Claude Desktop with Cmd+Q** (closing the window is not enough) and open it again. Go to **Settings → Developer**: the `playwright` server should show **running**.

To use Chromium instead of Google Chrome (see [Chrome or Chromium](#chrome-or-chromium)):

```bash
curl -fsSL https://raw.githubusercontent.com/speedandfunction/snf-ai-skills-setup/main/playwright-mcp/playwright-mcp-setup.sh | PLAYWRIGHT_MCP_BROWSER=chromium bash
```

To check the setup without changing anything:

```bash
curl -fsSL https://raw.githubusercontent.com/speedandfunction/snf-ai-skills-setup/main/playwright-mcp/playwright-mcp-setup.sh | bash -s -- --check
```

> The browser choice is remembered. A plain re-run, or `--check`, keeps using whatever the current config uses.

> `bash <(curl -fsSL …)` works too, and so does downloading the file and running `bash playwright-mcp-setup.sh`.
> Do not run it with `sudo`. It sets things up for your own user account.

---

## What it does

| Step | Action | Skipped when |
| --- | --- | --- |
| 1 | Installs **Claude Desktop** (`brew install --cask claude`) | `Claude.app` is in `/Applications` or `~/Applications` |
| 2 | Installs **Node.js** (`brew install node`) | Node ≥ 18 is already installed |
| 3 | Installs **Google Chrome** (`brew install --cask google-chrome`), the browser Playwright MCP drives | Chrome is already installed, or you chose Chromium |
| 4 | Installs **`@playwright/mcp`** into its own folder (not a global npm install) | that exact version is already installed |
| 4a | With `PLAYWRIGHT_MCP_BROWSER=chromium`: downloads **Playwright's Chromium** instead of step 3 (~190 MB) | the build this `@playwright/mcp` version needs is already there |
| 5 | Writes a small **launcher** that starts the server with a fixed Node path and working folder | the launcher is already up to date |
| 6 | Adds the **`playwright`** server to `claude_desktop_config.json` | the entry is already identical |
| 7 | **Verifies**: starts the server, does the MCP handshake, and opens a test page in the headless browser | — (always runs) |

**Homebrew** is installed only if one of steps 1–3 needs it. Its installer asks for your macOS password, which requires an administrator account.

### Idempotent

Each step checks first and does only what is missing, so you can re-run the script as often as you like:

- Nothing is reinstalled when it is already in place.
- The Claude Desktop config is rewritten **only if the `playwright` entry differs**. In that case a timestamped backup (`claude_desktop_config.json.bak-YYYYMMDD-HHMMSS`) is saved next to it first.
- Other servers and settings in the config are left untouched. A config file that is not valid JSON is never overwritten. The script stops and tells you which file it is.
- If a step fails, the script stops there with a message saying what to do. It never reports success after a failure.

---

## Where things go

| What | Path |
| --- | --- |
| Server install (`@playwright/mcp` + launcher) | `~/.local/share/snf-playwright-mcp/` |
| Screenshots, PDFs, downloads | `~/playwright-mcp/` |
| Claude Desktop config | `~/Library/Application Support/Claude/claude_desktop_config.json` |
| Browser profile (logins and cookies are kept between sessions) | `~/Library/Caches/ms-playwright/mcp-chrome-*` |
| Chromium (only with `PLAYWRIGHT_MCP_BROWSER=chromium`) | `~/Library/Caches/ms-playwright/chromium-<revision>/` |
| Server log | `~/Library/Logs/Claude/mcp-server-playwright.log` |

The entry the script writes:

```json
"playwright": {
  "command": "/Users/<you>/.local/share/snf-playwright-mcp/playwright-mcp",
  "args": ["--browser", "chrome", "--output-dir", "/Users/<you>/playwright-mcp"]
}
```

With Chromium, the entry has `"--browser", "chromium"` instead.

Why a launcher instead of the usual `npx @playwright/mcp@latest`:

- Claude Desktop does not see your shell `PATH`, so a bare `npx` often fails to start. The launcher calls Node by its full path.
- The launcher runs from `~/playwright-mcp`, so files land in one folder you can find.
- A fixed version starts without checking npm on every launch. It changes only when you re-run the script.

---

## Chrome or Chromium

Google Chrome is the default. Use Chromium if you do not want Google Chrome on the Mac.

| | Google Chrome (default) | Chromium (`PLAYWRIGHT_MCP_BROWSER=chromium`) |
| --- | --- | --- |
| What it is | Regular Chrome in `/Applications` | Playwright's own build ("Chrome for Testing"), kept in `~/Library/Caches/ms-playwright` |
| Security updates | Chrome updates itself | **Only when you re-run the script.** The build is tied to the `@playwright/mcp` version. |
| Download | Usually nothing, because most Macs already have Chrome | ~190 MB (~370 MB on disk), and again when an update needs a newer build |
| macOS | Any | **14 Sonoma or newer.** Playwright has no build for older versions. |
| Leaves behind | Chrome and Google's updater | Nothing in `/Applications` |

Claude browses arbitrary sites with this browser, so an outdated build is a real risk. If you choose Chromium, re-run the script regularly, for example once a month.

To switch, re-run with `PLAYWRIGHT_MCP_BROWSER=chrome` or `PLAYWRIGHT_MCP_BROWSER=chromium`. After that, plain re-runs keep the new choice. Each browser has its own profile, so after a switch you have to log in to sites again.

> The Chromium app from Homebrew is not an option: Homebrew disabled it on 2026-09-01 because it fails the macOS Gatekeeper check.

---

## Options

Set these as environment variables before `bash`:

```bash
curl -fsSL https://raw.githubusercontent.com/speedandfunction/snf-ai-skills-setup/main/playwright-mcp/playwright-mcp-setup.sh | PLAYWRIGHT_MCP_VERSION=0.0.83 bash
```

| Variable | Default | Meaning |
| --- | --- | --- |
| `PLAYWRIGHT_MCP_BROWSER` | whatever the current config uses, otherwise `chrome` | `chrome` or `chromium`. See [Chrome or Chromium](#chrome-or-chromium). |
| `PLAYWRIGHT_MCP_VERSION` | `latest` | `@playwright/mcp` version to install (an exact version, or a range like `0.0.x`) |
| `PLAYWRIGHT_MCP_WORKSPACE` | `~/playwright-mcp` | Folder for screenshots, PDFs and downloads |
| `PLAYWRIGHT_MCP_HOME` | `~/.local/share/snf-playwright-mcp` | Install folder |
| `CLAUDE_DESKTOP_CONFIG` | `~/Library/Application Support/Claude/claude_desktop_config.json` | Config file to update |

| Flag | Meaning |
| --- | --- |
| `--check` | Verify only. Exits with `1` if something is missing, and changes nothing. |
| `-h`, `--help` | Show usage |

---

## Using it

- Ask Claude something like *"Open https://speedandfunction.com and summarise the home page"*. A Chrome window opens and Claude works in it.
- If you log in to a site in that window, the login is kept for later sessions.
- The server can only read and write files inside `~/playwright-mcp`. To upload a file through the browser, copy it there first.

## Updating

Re-run the quick-start command. It installs the newest `@playwright/mcp` (or the version you pinned). With Chromium, it also downloads the matching Chromium build. Then restart Claude Desktop (Cmd+Q, then reopen it).

## Removing

1. Claude Desktop → **Settings → Developer → Edit Config**. Delete the `"playwright"` block and save.
2. `rm -rf ~/.local/share/snf-playwright-mcp`
3. Optional: `rm -rf ~/playwright-mcp ~/Library/Caches/ms-playwright/mcp-chrome-*` deletes saved files and browser logins.
4. Chromium only: `rm -rf ~/Library/Caches/ms-playwright/chromium-*`. Skip this if other Playwright tools on the Mac use these builds.
5. Restart Claude Desktop.

Node, Chrome and Claude Desktop stay installed.

---

## Troubleshooting

| Problem | Fix |
| --- | --- |
| `playwright` does not appear in Settings → Developer | Quit Claude Desktop fully with **Cmd+Q** and reopen it. The config is read only at startup. |
| `playwright` shows **failed** | Run the `--check` command above. Then read `~/Library/Logs/Claude/mcp-server-playwright.log`. |
| `Node not found at …` in the log | Node was moved or removed (for example, an nvm version was deleted). Re-run the script. |
| "Browser is already in use" / profile is locked | Another Playwright session holds the profile. Close the leftover Chrome window it opened, or restart Claude Desktop. |
| `… is not valid JSON` | Your Claude Desktop config is broken. Fix the file it names, or move it away, then re-run. |
| `npm … EACCES` | Run `sudo chown -R $(id -u):$(id -g) ~/.npm`, then re-run. |
| `Could not resolve @playwright/mcp@… on npm` | Check your network or VPN, or the `PLAYWRIGHT_MCP_VERSION` value, then re-run. |
