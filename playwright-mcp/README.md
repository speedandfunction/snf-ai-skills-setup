# Playwright MCP for Claude Desktop and Claude Code (macOS)

One command connects the [Playwright MCP](https://github.com/microsoft/playwright-mcp) browser connector to **Claude Desktop on macOS**, and also to the **Claude Code CLI** if `claude` is installed. With it, Claude can open pages in Chrome (or Chromium), click, fill in forms, read page content and take screenshots.

The script installs anything that is missing and writes the connector into Claude Desktop's config. It also registers the connector for Claude Code at user scope. Then it opens a test page to check that the server works.

> Claude Desktop and Claude Code keep **separate** server lists. Claude Code never reads `claude_desktop_config.json`, which is why the script sets up both.

---

## Quick start

```bash
curl -fsSL https://raw.githubusercontent.com/speedandfunction/snf-ai-skills-setup/main/playwright-mcp/playwright-mcp-setup.sh | bash
```

Then **quit Claude Desktop with Cmd+Q** (closing the window is not enough) and open it again. Go to **Settings → Developer**: the `playwright` server should show **running**.

In the **Claude Code CLI**, run `claude mcp list`, or type `/mcp` in a **new** session. `playwright` should show as connected. Sessions that were already open do not pick it up.

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

To do everything by hand instead, follow [Manual installation](#manual-installation-step-by-step).

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
| 6a | Registers the same server for the **Claude Code CLI**: `claude mcp add --scope user`, so it works in every folder and in the Desktop app's Code tab | `claude` is not installed, or the entry is already identical |
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
| Claude Code config (user scope, written by `claude mcp add`) | `~/.claude.json` |
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

## Manual installation (step by step)

These steps produce the same setup as the script, with the same paths. You can run the script's `--check` afterwards to confirm the result, and running the script later just takes over this install.

Run the commands in **Terminal** (Applications → Utilities → Terminal). Do one step at a time, and check the result before you move on.

### Step 1. Homebrew

```bash
brew --version
```

If it prints a version, go to step 2. If it says `command not found`, install Homebrew. It asks for your macOS password, so you need an administrator account:

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

At the end the installer prints **Next steps**. Run the two commands it shows. On Apple Silicon they are:

```bash
echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> ~/.zprofile
eval "$(/opt/homebrew/bin/brew shellenv)"
```

On an Intel Mac, use `/usr/local/bin/brew` instead of `/opt/homebrew/bin/brew`. Then run `brew --version` again.

### Step 2. Claude Desktop

```bash
ls -d /Applications/Claude.app
```

If the app is not found, install it, then open it once and sign in:

```bash
brew install --cask claude
```

You can also download it from <https://claude.ai/download>.

### Step 3. Node.js 18 or newer

```bash
node --version
```

You need `v18` or higher. If `node` is missing, install it. If the version is lower than 18, run `brew upgrade node` instead:

```bash
brew install node
```

Then see where Node lives. You will need this path in step 7:

```bash
command -v node
```

The usual answer is `/opt/homebrew/bin/node` on Apple Silicon or `/usr/local/bin/node` on Intel. If the path contains `.nvm`, the connector stops working once that nvm version is removed. In that case, redo step 7 after switching versions.

### Step 4. Browser: Chrome or Chromium

Pick one. The differences are explained in [Chrome or Chromium](#chrome-or-chromium).

**Google Chrome (default).** Check that it is in `/Applications`:

```bash
ls -d "/Applications/Google Chrome.app"
```

If it is missing, install it:

```bash
brew install --cask google-chrome
```

Chrome must be in `/Applications`, not `~/Applications`. Playwright only looks there.

**Chromium.** Skip this step. You download Chromium in step 6, once the server is installed. Chromium needs macOS 14 Sonoma or newer.

### Step 5. Install `@playwright/mcp`

The server goes into its own folder, not into a global npm install:

```bash
mkdir -p ~/.local/share/snf-playwright-mcp
cd ~/.local/share/snf-playwright-mcp
[ -f package.json ] || echo '{ "name": "snf-playwright-mcp", "private": true }' > package.json
npm install --save-exact --no-audit --no-fund @playwright/mcp@latest
node node_modules/@playwright/mcp/cli.js --version
```

The last command should print `Version 0.0.…`.

### Step 6. Chromium only: download the browser

Skip this step if you use Chrome.

```bash
node ~/.local/share/snf-playwright-mcp/node_modules/@playwright/mcp/cli.js install-browser chromium --no-shell
```

This downloads about 190 MB to `~/Library/Caches/ms-playwright/chromium-<revision>/`.

### Step 7. Create the launcher

Claude Desktop does not see your Terminal `PATH`, so a small launcher calls Node by its full path. It also starts the server from `~/playwright-mcp`. Copy the whole block. The paths are filled in automatically when you run it:

```bash
NODE_BIN="$(command -v node)"
cat > ~/.local/share/snf-playwright-mcp/playwright-mcp <<EOF
#!/bin/bash
mkdir -p "$HOME/playwright-mcp" && cd "$HOME/playwright-mcp" || exit 1
exec "$NODE_BIN" "$HOME/.local/share/snf-playwright-mcp/node_modules/@playwright/mcp/cli.js" "\$@"
EOF
chmod 755 ~/.local/share/snf-playwright-mcp/playwright-mcp
~/.local/share/snf-playwright-mcp/playwright-mcp --version
```

The last command should print the same `Version 0.0.…` as in step 5.

### Step 8. Add the server to the Claude Desktop config

Make a backup of the config, print your home folder (you need it below), and open the file in TextEdit:

```bash
CFG="$HOME/Library/Application Support/Claude/claude_desktop_config.json"
mkdir -p "$(dirname "$CFG")"
[ -f "$CFG" ] || echo '{}' > "$CFG"
cp "$CFG" "$CFG.bak-$(date +%Y%m%d-%H%M%S)"
echo "$HOME"
open -a TextEdit "$CFG"
```

Add the `playwright` block inside `"mcpServers"`. Replace `/Users/<you>` with what `echo "$HOME"` printed. `~` does not work in this file. For Chromium, write `"chromium"` instead of `"chrome"`.

- **The file is just `{}`.** Replace its content with:

  ```json
  {
    "mcpServers": {
      "playwright": {
        "command": "/Users/<you>/.local/share/snf-playwright-mcp/playwright-mcp",
        "args": ["--browser", "chrome", "--output-dir", "/Users/<you>/playwright-mcp"]
      }
    }
  }
  ```

- **The file already has `"mcpServers"`.** Add the block as one more server. Put a comma after the server before it, and leave the other servers and keys as they are:

  ```json
  {
    "mcpServers": {
      "some-other-server": { "...": "..." },
      "playwright": {
        "command": "/Users/<you>/.local/share/snf-playwright-mcp/playwright-mcp",
        "args": ["--browser", "chrome", "--output-dir", "/Users/<you>/playwright-mcp"]
      }
    },
    "preferences": { "...": "..." }
  }
  ```

- **The file has other keys but no `"mcpServers"`.** Add `"mcpServers": { "playwright": { … } },` as the first key, right after the opening `{`.

If a `"playwright"` entry is already there (for example `npx @playwright/mcp@latest`), replace it rather than adding a second one.

**Paste the text instead of typing it.** TextEdit can turn typed quotes into curly quotes, which break the file. Save with Cmd+S and close the window. Then check that the file is still valid JSON:

```bash
node -e 'JSON.parse(require("fs").readFileSync(process.argv[1], "utf8")); console.log("JSON OK")' "$CFG"
```

If you get an error instead of `JSON OK`, fix the place it points to, or restore the backup you made above.

### Step 9. Claude Code CLI

Skip this step if you do not use the Claude Code CLI (`claude`). Claude Code does not read the Desktop config, so register the same server for it:

```bash
claude mcp add --scope user playwright -- "$HOME/.local/share/snf-playwright-mcp/playwright-mcp" --browser chrome --output-dir "$HOME/playwright-mcp"
claude mcp get playwright
```

For Chromium, write `chromium` instead of `chrome`. The second command should show `Status: ✔ Connected`. If a `playwright` entry already exists, first run `claude mcp remove playwright --scope user`.

### Step 10. Restart Claude Desktop and check

1. Quit Claude Desktop with **Cmd+Q**. Closing the window is not enough.
2. Open it again and go to **Settings → Developer**. The `playwright` server should show **running**.
3. If it shows **failed**, read `~/Library/Logs/Claude/mcp-server-playwright.log`.
4. In a chat, ask: *"Open https://speedandfunction.com and summarise the home page."*

### Step 11 (optional). Let the script confirm the setup

```bash
curl -fsSL https://raw.githubusercontent.com/speedandfunction/snf-ai-skills-setup/main/playwright-mcp/playwright-mcp-setup.sh | bash -s -- --check
```

It changes nothing. It reports what is missing, then opens a test page in the headless browser.

### Updating a manual install

```bash
cd ~/.local/share/snf-playwright-mcp
npm install --save-exact --no-audit --no-fund @playwright/mcp@latest
# Chromium only: download the build the new version needs
node node_modules/@playwright/mcp/cli.js install-browser chromium --no-shell
```

Then restart Claude Desktop with Cmd+Q and reopen it. You can also run the quick-start command, which does the same.

---

## Using it

- Ask Claude something like *"Open https://speedandfunction.com and summarise the home page"*. A Chrome window opens and Claude works in it.
- If you log in to a site in that window, the login is kept for later sessions.
- The server can only read and write files inside `~/playwright-mcp`. To upload a file through the browser, copy it there first.

## Updating

Re-run the quick-start command. It installs the newest `@playwright/mcp` (or the version you pinned). With Chromium, it also downloads the matching Chromium build. Then restart Claude Desktop (Cmd+Q, then reopen it).

## Removing

1. Claude Desktop → **Settings → Developer → Edit Config**. Delete the `"playwright"` block and save.
2. Claude Code CLI: `claude mcp remove playwright --scope user`
3. `rm -rf ~/.local/share/snf-playwright-mcp`
4. Optional: `rm -rf ~/playwright-mcp ~/Library/Caches/ms-playwright/mcp-chrome-*` deletes saved files and browser logins.
5. Chromium only: `rm -rf ~/Library/Caches/ms-playwright/chromium-*`. Skip this if other Playwright tools on the Mac use these builds.
6. Restart Claude Desktop.

Node, Chrome and Claude Desktop stay installed.

---

## Troubleshooting

| Problem | Fix |
| --- | --- |
| `playwright` does not appear in Settings → Developer | Quit Claude Desktop fully with **Cmd+Q** and reopen it. The config is read only at startup. |
| The Claude Code CLI does not see `playwright` | Re-run the script, or do manual step 9. It only takes effect in a **new** `claude` session. If the script said `claude` was not found, install Claude Code and re-run. |
| Claude Code uses a different `playwright` in one project | That project defines its own `playwright` in `.mcp.json` or at local scope, and that overrides the user-scope entry. Check with `claude mcp get playwright` inside that folder. |
| `playwright` shows **failed** | Run the `--check` command above. Then read `~/Library/Logs/Claude/mcp-server-playwright.log`. |
| `Node not found at …` in the log | Node was moved or removed (for example, an nvm version was deleted). Re-run the script. |
| "Browser is already in use" / profile is locked | Another Playwright session holds the profile. Close the leftover Chrome window it opened, or restart Claude Desktop. |
| `… is not valid JSON` | Your Claude Desktop config is broken. Fix the file it names, or move it away, then re-run. |
| `npm … EACCES` | Run `sudo chown -R $(id -u):$(id -g) ~/.npm`, then re-run. |
| `Could not resolve @playwright/mcp@… on npm` | Check your network or VPN, or the `PLAYWRIGHT_MCP_VERSION` value, then re-run. |
