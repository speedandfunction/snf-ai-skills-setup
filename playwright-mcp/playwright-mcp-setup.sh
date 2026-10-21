#!/usr/bin/env bash
#
# playwright-mcp-setup.sh — set up the Playwright MCP connector for Claude Desktop
#                           on macOS, with everything it needs.
#
# Installs (only what is missing):
#   • Homebrew              — only if one of the items below has to be installed
#   • Claude Desktop        — brew cask "claude"
#   • Node.js >= 18         — brew formula "node"
#   • Google Chrome         — brew cask "google-chrome" (the browser Playwright MCP drives),
#                             or, with PLAYWRIGHT_MCP_BROWSER=chromium, Playwright's own
#                             Chromium build instead (~190 MB, macOS 14+)
#   • @playwright/mcp       — into its own folder, not a global npm install
# Then writes the "playwright" server into Claude Desktop's config and checks that
# the server starts and can actually open a page in Chrome.
#
# Idempotent: every step checks first and skips what is already in place. The
# Claude Desktop config is rewritten only when the "playwright" entry differs, and
# a timestamped backup is kept next to it. Other servers and settings are untouched.
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/speedandfunction/snf-ai-skills-setup/main/playwright-mcp/playwright-mcp-setup.sh | bash
#   curl -fsSL .../playwright-mcp-setup.sh | bash -s -- --check     # verify only, change nothing
#
# Optional environment overrides (put them before `bash`):
#   PLAYWRIGHT_MCP_BROWSER=chromium   # default: what the config already uses, else chrome
#   PLAYWRIGHT_MCP_VERSION=0.0.83     # default: latest (re-running upgrades)
#   PLAYWRIGHT_MCP_WORKSPACE=~/dir    # where screenshots/PDFs/downloads land (default: ~/playwright-mcp)
#   PLAYWRIGHT_MCP_HOME=~/dir         # install folder (default: ~/.local/share/snf-playwright-mcp)
#   CLAUDE_DESKTOP_CONFIG=/path.json  # default: ~/Library/Application Support/Claude/claude_desktop_config.json
#
set -Eeuo pipefail

# ────────────────────────────── Configuration ─────────────────────────────
SERVER_NAME="playwright"
PKG="@playwright/mcp"
PW_VERSION="${PLAYWRIGHT_MCP_VERSION:-latest}"
BROWSER="${PLAYWRIGHT_MCP_BROWSER:-}"   # empty: keep what the config already uses, else chrome
BROWSER_LABEL=""
INSTALL_DIR="${PLAYWRIGHT_MCP_HOME:-$HOME/.local/share/snf-playwright-mcp}"
WORKSPACE="${PLAYWRIGHT_MCP_WORKSPACE:-$HOME/playwright-mcp}"
DESKTOP_CFG="${CLAUDE_DESKTOP_CONFIG:-$HOME/Library/Application Support/Claude/claude_desktop_config.json}"
LAUNCHER="$INSTALL_DIR/playwright-mcp"
CLI_JS="$INSTALL_DIR/node_modules/@playwright/mcp/cli.js"
NODE_MIN_MAJOR=18
SCRIPT_URL="https://raw.githubusercontent.com/speedandfunction/snf-ai-skills-setup/main/playwright-mcp/playwright-mcp-setup.sh"

CHECK_ONLY=0
FAILURES=0
BREW=""
NODE_BIN=""
CHROME_EXEC=""
CHANGED_RUNTIME=0
HELPERS=""

# ──────────────────────────────── Logging ─────────────────────────────────
if [ -t 1 ]; then
  C_BLUE=$'\033[1;34m'; C_GREEN=$'\033[1;32m'; C_YELLOW=$'\033[1;33m'
  C_RED=$'\033[1;31m'; C_BOLD=$'\033[1m'; C_RESET=$'\033[0m'
else
  C_BLUE=""; C_GREEN=""; C_YELLOW=""; C_RED=""; C_BOLD=""; C_RESET=""
fi
log()  { printf '%s==>%s %s\n' "$C_BLUE" "$C_RESET" "$*"; }
ok()   { printf '%s ✔ %s %s\n' "$C_GREEN" "$C_RESET" "$*"; }
warn() { printf '%s ! %s %s\n' "$C_YELLOW" "$C_RESET" "$*"; }
err()  { printf '%s ✘ %s %s\n' "$C_RED" "$C_RESET" "$*" >&2; }
bad()  { err "$*"; FAILURES=$((FAILURES + 1)); }
die()  { err "$*"; echo >&2; err "Setup did NOT complete. Fix the above and re-run — the script is idempotent."; exit 1; }
has()  { command -v "$1" >/dev/null 2>&1; }

trap 'rc=$?; err "Unexpected failure at line ${LINENO} (exit ${rc}). Re-run the script — it is safe to run repeatedly."' ERR
trap '[ -z "$HELPERS" ] || rm -rf "$HELPERS"' EXIT

usage() {
  cat <<EOF
Set up the Playwright MCP connector for Claude Desktop (macOS).

  curl -fsSL $SCRIPT_URL | bash
  curl -fsSL $SCRIPT_URL | bash -s -- --check

Options:
  --check     verify the setup, change nothing
  -h, --help  this help

Environment: PLAYWRIGHT_MCP_BROWSER (chrome | chromium), PLAYWRIGHT_MCP_VERSION,
             PLAYWRIGHT_MCP_WORKSPACE, PLAYWRIGHT_MCP_HOME, CLAUDE_DESKTOP_CONFIG
             (see README.md).
EOF
}

# A terminal is needed only if Homebrew has to be installed (it asks for the
# password). `curl | bash` still has one, even though stdin is the pipe.
have_tty() { ( : </dev/tty ) 2>/dev/null; }

# ──────────────────────────────── Homebrew ────────────────────────────────
find_brew() {
  if   [ -x /opt/homebrew/bin/brew ]; then echo /opt/homebrew/bin/brew
  elif [ -x /usr/local/bin/brew   ]; then echo /usr/local/bin/brew
  elif has brew; then command -v brew
  fi
}

# Homebrew's installer does not touch the shell profile; without this, `brew`
# vanishes from new terminals. Writes only if nothing already sets it up.
persist_brew_shellenv() {
  local bin_dir f
  bin_dir="$(dirname "$BREW")"
  grep -qxF "$bin_dir" /etc/paths /etc/paths.d/* 2>/dev/null && return 0
  for f in "$HOME/.zprofile" "$HOME/.zshrc" "$HOME/.zshenv" "$HOME/.bash_profile" "$HOME/.profile"; do
    [ -e "$f" ] && grep -qE "brew shellenv|$bin_dir" "$f" 2>/dev/null && return 0
  done
  printf '\n# Added by playwright-mcp-setup.sh — put Homebrew on PATH\neval "$(%s shellenv)"\n' "$BREW" >> "$HOME/.zprofile"
  ok "Added Homebrew to PATH in ~/.zprofile"
}

# Called lazily: Homebrew is installed only when something else is missing.
need_brew() {
  [ -n "$BREW" ] && return 0
  BREW="$(find_brew)"
  if [ -z "$BREW" ]; then
    log "Homebrew not found — installing it (asks for your macOS password)…"
    have_tty || die "Homebrew needs your password, but there is no terminal. Run this script from Terminal.app."
    # The installer talks to the terminal itself (password, "Press RETURN"); under
    # `curl | bash` stdin is the script, so hand it /dev/tty instead.
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" </dev/tty \
      || die "Homebrew install failed. It needs a macOS administrator account. Install it from https://brew.sh and re-run."
    BREW="$(find_brew)"
    [ -n "$BREW" ] || die "Homebrew installed but 'brew' was not found. Open a new terminal and re-run."
    persist_brew_shellenv
  fi
  eval "$("$BREW" shellenv)"
  hash -r 2>/dev/null || true
}

brew_cask() { # brew_cask <cask> <human name>
  need_brew
  "$BREW" install --cask "$1" </dev/null || die "brew install --cask $1 failed. Run 'brew doctor', or install $2 manually, then re-run."
}

# ──────────────────────────────── Claude Desktop ──────────────────────────
ensure_claude() {
  if [ -d /Applications/Claude.app ] || [ -d "$HOME/Applications/Claude.app" ]; then
    ok "Claude Desktop installed"
  elif [ "$CHECK_ONLY" -eq 1 ]; then
    bad "Claude Desktop not found in /Applications"
  else
    log "Installing Claude Desktop…"
    brew_cask claude "Claude Desktop (https://claude.ai/download)"
    ok "Claude Desktop installed"
  fi
}

# ──────────────────────────────── Node.js ─────────────────────────────────
node_major() { "$1" -p 'process.versions.node.split(".")[0]' 2>/dev/null || echo 0; }

# Absolute path, because Claude Desktop does not see your shell PATH. Homebrew's
# and the official installer's paths are stable across Node upgrades, so prefer them.
find_node() {
  local c
  for c in /opt/homebrew/bin/node /usr/local/bin/node "$(command -v node 2>/dev/null || true)"; do
    [ -n "$c" ] && [ -x "$c" ] || continue
    [ "$(node_major "$c")" -ge "$NODE_MIN_MAJOR" ] && { echo "$c"; return 0; }
  done
  return 0
}

ensure_node() {
  NODE_BIN="$(find_node)"
  if [ -z "$NODE_BIN" ]; then
    if [ "$CHECK_ONLY" -eq 1 ]; then bad "Node.js >= $NODE_MIN_MAJOR not found"; return; fi
    log "Installing Node.js…"
    need_brew
    if "$BREW" list --formula node >/dev/null 2>&1; then
      "$BREW" upgrade node </dev/null || die "brew upgrade node failed. Run 'brew doctor', then re-run."
    else
      "$BREW" install node </dev/null || die "brew install node failed. Run 'brew doctor', then re-run."
    fi
    NODE_BIN="$("$BREW" --prefix)/bin/node"
    [ -x "$NODE_BIN" ] || die "Node was installed but $NODE_BIN is missing. Open a new terminal and re-run."
    CHANGED_RUNTIME=1
  fi
  ok "Node.js $("$NODE_BIN" --version) ($NODE_BIN)"
  case "$NODE_BIN" in
    "$HOME"/.nvm/*) warn "Node comes from nvm: if you remove or switch this version, re-run the script." ;;
  esac
}

# ──────────────────────────────── Browser choice ──────────────────────────
# Without PLAYWRIGHT_MCP_BROWSER, keep the browser the existing entry uses, so a
# plain re-run (e.g. to update) never switches a Chromium setup back to Chrome.
resolve_browser() {
  if [ -z "$BROWSER" ] && [ -n "$NODE_BIN" ] && [ -f "$DESKTOP_CFG" ]; then
    BROWSER="$("$NODE_BIN" -e '
try {
  const a = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8")).mcpServers[process.argv[2]].args;
  const i = a.indexOf("--browser");
  if (i >= 0 && a[i + 1] === "chromium") console.log("chromium");
} catch (e) {}
' "$DESKTOP_CFG" "$SERVER_NAME" 2>/dev/null || true)"
    [ -z "$BROWSER" ] || ok "Browser: Chromium, kept from the current config (PLAYWRIGHT_MCP_BROWSER=chrome switches back)"
  fi
  BROWSER="${BROWSER:-chrome}"
  if [ "$BROWSER" = "chromium" ]; then BROWSER_LABEL="Chromium"; else BROWSER_LABEL="Chrome"; fi
}

# ──────────────────────────────── Google Chrome ───────────────────────────
# Playwright MCP's default browser is the "chrome" channel and looks for it in
# /Applications only; a copy in ~/Applications is passed explicitly.
ensure_chrome() {
  if [ -d "/Applications/Google Chrome.app" ]; then
    ok "Google Chrome $(chrome_version "/Applications/Google Chrome.app")"
  elif [ -d "$HOME/Applications/Google Chrome.app" ]; then
    CHROME_EXEC="$HOME/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
    ok "Google Chrome $(chrome_version "$HOME/Applications/Google Chrome.app") (in ~/Applications)"
  elif [ "$CHECK_ONLY" -eq 1 ]; then
    bad "Google Chrome not found in /Applications"
  else
    log "Installing Google Chrome…"
    brew_cask google-chrome "Google Chrome (https://www.google.com/chrome/)"
    [ -d "/Applications/Google Chrome.app" ] || die "Chrome install finished but /Applications/Google Chrome.app is missing."
    ok "Google Chrome $(chrome_version "/Applications/Google Chrome.app")"
  fi
}
chrome_version() { defaults read "$1/Contents/Info" CFBundleShortVersionString 2>/dev/null || echo "(version unknown)"; }

# ──────────────────────────────── Chromium (opt-in) ───────────────────────
# Playwright's own build ("Chrome for Testing"). It does not update itself: its
# revision follows @playwright/mcp, so this runs on every pass and downloads only
# when the revision the installed package needs is not there yet.

# Prints "<version>|<directory>|yes|no" for the revision the installed package expects.
chromium_info() {
  "$NODE_BIN" -e '
const path = require("path"), fs = require("fs"), os = require("os");
const core = path.dirname(require.resolve("playwright-core/package.json", { paths: [path.dirname(process.argv[1])] }));
const b = require(path.join(core, "browsers.json")).browsers.find((x) => x.name === "chromium");
const env = process.env.PLAYWRIGHT_BROWSERS_PATH;
const root = env === "0" ? path.join(core, ".local-browsers") : env || path.join(os.homedir(), "Library/Caches/ms-playwright");
const dir = path.join(root, "chromium-" + b.revision);
console.log(b.browserVersion + "|" + dir + "|" + (fs.existsSync(path.join(dir, "INSTALLATION_COMPLETE")) ? "yes" : "no"));
' "$CLI_JS" 2>/dev/null || true
}

ensure_chromium() {
  local info version dir
  [ -f "$CLI_JS" ] || return 0   # --check on a fresh Mac: the missing package is already reported
  info="$(chromium_info)"
  [ -n "$info" ] || die "Could not read Playwright's browser list from $INSTALL_DIR. Delete that folder and re-run."
  version="${info%%|*}"; dir="${info#*|}"; dir="${dir%|*}"
  if [ "${info##*|}" = "yes" ]; then
    ok "Chromium $version (Playwright build) in $dir"
    return
  fi
  if [ "$CHECK_ONLY" -eq 1 ]; then
    bad "Chromium $version (Playwright build) not installed — expected in $dir"
    return
  fi
  log "Downloading Chromium $version (Playwright build, ~190 MB download, ~370 MB on disk)…"
  "$NODE_BIN" "$CLI_JS" install-browser chromium --no-shell </dev/null \
    || die "Chromium download failed. Check the network/VPN and re-run."
  [ "$(chromium_info | sed 's/.*|//')" = "yes" ] || die "Chromium download finished but $dir is incomplete. Re-run the script."
  ok "Chromium $version installed in $dir"
  CHANGED_RUNTIME=1
}

# ──────────────────────────────── @playwright/mcp ─────────────────────────
installed_pkg_version() {
  [ -f "$INSTALL_DIR/node_modules/@playwright/mcp/package.json" ] || return 0
  "$NODE_BIN" -p 'require(process.argv[1]).version' "$INSTALL_DIR/node_modules/@playwright/mcp/package.json" 2>/dev/null || true
}

ensure_package() {
  local npm current target
  current="$(installed_pkg_version)"
  if [ "$CHECK_ONLY" -eq 1 ]; then
    [ -n "$current" ] && ok "$PKG $current installed in $INSTALL_DIR" || bad "$PKG not installed in $INSTALL_DIR"
    return
  fi

  npm="$(dirname "$NODE_BIN")/npm"
  [ -x "$npm" ] || die "npm not found next to $NODE_BIN. Reinstall Node (brew reinstall node) and re-run."
  export PATH="$(dirname "$NODE_BIN"):$PATH"   # npm's shebang is `env node`

  # --json: a range like "0.0.x" returns a list; take the newest match.
  target="$("$npm" view "$PKG@$PW_VERSION" version --json </dev/null 2>/dev/null \
    | "$NODE_BIN" -e 'let d="";process.stdin.on("data",c=>d+=c).on("end",()=>{try{let v=JSON.parse(d);if(Array.isArray(v))v=v[v.length-1];if(typeof v==="string")console.log(v)}catch(e){}})' \
    || true)"
  if [ -z "$target" ]; then
    [ -n "$current" ] || die "Could not resolve $PKG@$PW_VERSION on npm. Check the network/VPN (or the PLAYWRIGHT_MCP_VERSION value) and re-run."
    warn "Could not resolve $PKG@$PW_VERSION on npm — keeping the installed $current"
    return
  fi
  if [ "$current" = "$target" ]; then
    ok "$PKG $current already installed"
    return
  fi

  log "Installing $PKG $target${current:+ (was $current)}…"
  mkdir -p "$INSTALL_DIR"
  [ -f "$INSTALL_DIR/package.json" ] || printf '{\n  "name": "snf-playwright-mcp",\n  "private": true\n}\n' > "$INSTALL_DIR/package.json"
  "$npm" install --prefix "$INSTALL_DIR" --save-exact --no-audit --no-fund --loglevel=error "$PKG@$target" </dev/null \
    || die "npm install $PKG@$target failed. If it mentions EACCES, run: sudo chown -R \$(id -u):\$(id -g) ~/.npm — then re-run."
  [ "$(installed_pkg_version)" = "$target" ] || die "npm finished but $PKG $target is not in $INSTALL_DIR."
  ok "$PKG $target installed in $INSTALL_DIR"
  CHANGED_RUNTIME=1
}

# ──────────────────────────────── Launcher ────────────────────────────────
# Claude Desktop starts servers without your shell PATH and without a working
# folder of your choosing. The launcher pins Node and runs from $WORKSPACE, so
# screenshots, PDFs and downloads land in one known, writable place.
launcher_content() {
  echo '#!/bin/bash'
  echo '# Generated by playwright-mcp-setup.sh (speedandfunction/snf-ai-skills-setup).'
  echo '# Do not edit: re-run the setup script, it rewrites this file.'
  printf '[ -x %q ] || { echo "playwright-mcp: Node not found at %s. Re-run playwright-mcp-setup.sh." >&2; exit 1; }\n' "$NODE_BIN" "$NODE_BIN"
  # Claude Desktop does not see shell variables; keep a custom browser location visible to it.
  [ -z "${PLAYWRIGHT_BROWSERS_PATH:-}" ] || printf 'export PLAYWRIGHT_BROWSERS_PATH=%q\n' "$PLAYWRIGHT_BROWSERS_PATH"
  printf 'mkdir -p %q && cd %q || exit 1\n' "$WORKSPACE" "$WORKSPACE"
  printf 'exec %q %q "$@"\n' "$NODE_BIN" "$CLI_JS"
}

ensure_launcher() {
  if [ "$CHECK_ONLY" -eq 1 ]; then
    [ -x "$LAUNCHER" ] && ok "Launcher present: $LAUNCHER" || bad "Launcher missing: $LAUNCHER"
    return
  fi
  local want; want="$(launcher_content)"
  if [ -f "$LAUNCHER" ] && [ "$(cat "$LAUNCHER")" = "$want" ] && [ -x "$LAUNCHER" ]; then
    ok "Launcher up to date: $LAUNCHER"
  else
    mkdir -p "$INSTALL_DIR"
    printf '%s\n' "$want" > "$LAUNCHER.tmp" && chmod 755 "$LAUNCHER.tmp" && mv "$LAUNCHER.tmp" "$LAUNCHER"
    ok "Launcher written: $LAUNCHER"
    CHANGED_RUNTIME=1
  fi
  mkdir -p "$WORKSPACE"
}

# ──────────────────────────────── Node helpers ────────────────────────────
write_helpers() {
  HELPERS="$(mktemp -d)"

  # desktop-config.js <check|write> <file> <name> <command> [args...]
  # Prints: same | missing | different | added | updated. Exit 3 on unusable JSON.
  cat > "$HELPERS/desktop-config.js" <<'JS'
const fs = require('fs');
const [mode, file, name, command, ...args] = process.argv.slice(2);
const fail = (m) => { console.error(m); process.exit(3); };
let raw = null, cfg = {};
try { raw = fs.readFileSync(file, 'utf8'); } catch (e) { if (e.code !== 'ENOENT') fail('cannot read: ' + e.message); }
if (raw !== null && raw.trim() !== '') { try { cfg = JSON.parse(raw); } catch (e) { fail('not valid JSON: ' + e.message); } }
if (!cfg || typeof cfg !== 'object' || Array.isArray(cfg)) fail('top level is not a JSON object');
const want = { command, args };
const servers = cfg.mcpServers && typeof cfg.mcpServers === 'object' && !Array.isArray(cfg.mcpServers) ? cfg.mcpServers : null;
const have = servers ? servers[name] : undefined;
const state = JSON.stringify(have) === JSON.stringify(want) ? 'same' : have ? 'different' : 'missing';
if (mode === 'check' || state === 'same') { console.log(state); process.exit(0); }
cfg.mcpServers = servers || {};
cfg.mcpServers[name] = want;
let fileMode = 0o644;
try { fileMode = fs.statSync(file).mode & 0o777; } catch (e) {}
const tmp = file + '.tmp-' + process.pid;
fs.writeFileSync(tmp, JSON.stringify(cfg, null, 2) + '\n', { mode: fileMode });
fs.renameSync(tmp, file);
console.log(state === 'missing' ? 'added' : 'updated');
JS

  # smoke.js <launcher> [args...] — MCP handshake over stdio, then open a page.
  cat > "$HELPERS/smoke.js" <<'JS'
const { spawn } = require('child_process');
const [launcher, ...args] = process.argv.slice(2);
const child = spawn(launcher, args, { stdio: ['pipe', 'pipe', 'pipe'] });
let buf = '', stderr = '', nextId = 1, finished = false;
const pending = new Map();
const finish = (code, msg) => {
  if (finished) return; finished = true;
  if (msg) console.log(msg);
  try { child.stdin.end(); } catch (e) {}
  setTimeout(() => { try { child.kill('SIGKILL'); } catch (e) {} process.exit(code); }, code === 0 ? 3000 : 0).unref();
  child.once('exit', () => process.exit(code));
};
setTimeout(() => finish(1, 'ERROR=timed out after 120s'), 120000).unref();
child.on('error', (e) => finish(1, 'ERROR=cannot start launcher: ' + e.message));
child.stderr.on('data', (d) => { stderr += d; });
child.on('exit', (c) => finish(1, 'ERROR=server exited (code ' + c + ') ' + stderr.trim().split('\n').slice(-3).join(' | ')));
child.stdout.on('data', (d) => {
  buf += d;
  let i;
  while ((i = buf.indexOf('\n')) >= 0) {
    const line = buf.slice(0, i).trim(); buf = buf.slice(i + 1);
    let msg; try { msg = JSON.parse(line); } catch (e) { continue; }
    const cb = pending.get(msg.id); if (cb) { pending.delete(msg.id); cb(msg); }
  }
});
const send = (m) => child.stdin.write(JSON.stringify(Object.assign({ jsonrpc: '2.0' }, m)) + '\n');
const call = (method, params) => new Promise((res) => { const id = nextId++; pending.set(id, res); send({ id, method, params }); });
(async () => {
  const init = await call('initialize', { protocolVersion: '2025-06-18', capabilities: {}, clientInfo: { name: 'snf-playwright-mcp-setup', version: '1' } });
  if (init.error) return finish(1, 'ERROR=initialize failed: ' + init.error.message);
  console.log('SERVER=' + init.result.serverInfo.name + ' ' + init.result.serverInfo.version);
  send({ method: 'notifications/initialized', params: {} });
  const list = await call('tools/list', {});
  const tools = ((list.result && list.result.tools) || []).map((t) => t.name);
  console.log('TOOLS=' + tools.length);
  if (!tools.includes('browser_navigate')) return finish(1, 'ERROR=browser_navigate tool missing');
  const marker = 'snf-playwright-ok';
  const nav = await call('tools/call', { name: 'browser_navigate', arguments: { url: 'data:text/html,<title>' + marker + '</title>ok' } });
  const text = JSON.stringify(nav.result || nav.error || {});
  if (nav.error || (nav.result && nav.result.isError) || !text.includes(marker)) return finish(1, 'ERROR=browser check failed: ' + text.slice(0, 500));
  await call('tools/call', { name: 'browser_close', arguments: {} });
  child.removeAllListeners('exit');
  finish(0, 'BROWSER=ok');
})();
JS
}

# ──────────────────────────────── Claude Desktop config ───────────────────
server_args() {
  SERVER_ARGS=(--browser "$BROWSER" --output-dir "$WORKSPACE")
  [ -z "$CHROME_EXEC" ] || SERVER_ARGS+=(--executable-path "$CHROME_EXEC")
}

ensure_desktop_config() {
  local state
  state="$("$NODE_BIN" "$HELPERS/desktop-config.js" check "$DESKTOP_CFG" "$SERVER_NAME" "$LAUNCHER" "${SERVER_ARGS[@]}")" \
    || die "$DESKTOP_CFG cannot be used (see above). Fix or move it, then re-run."

  if [ "$state" = "same" ]; then
    ok "Claude Desktop config already has the \"$SERVER_NAME\" server"
    return
  fi
  if [ "$CHECK_ONLY" -eq 1 ]; then
    bad "Claude Desktop config: \"$SERVER_NAME\" entry is $state ($DESKTOP_CFG)"
    return
  fi

  mkdir -p "$(dirname "$DESKTOP_CFG")"
  if [ -f "$DESKTOP_CFG" ]; then
    cp -p "$DESKTOP_CFG" "$DESKTOP_CFG.bak-$(date +%Y%m%d-%H%M%S)"
  fi
  "$NODE_BIN" "$HELPERS/desktop-config.js" write "$DESKTOP_CFG" "$SERVER_NAME" "$LAUNCHER" "${SERVER_ARGS[@]}" >/dev/null \
    || die "Could not write $DESKTOP_CFG."
  if [ "$state" = "different" ]; then
    ok "Replaced the existing \"$SERVER_NAME\" entry in the Claude Desktop config (backup kept alongside)"
  else
    ok "Added \"$SERVER_NAME\" to the Claude Desktop config"
  fi
  CHANGED_RUNTIME=1
}

# ──────────────────────────────── Verification ────────────────────────────
verify_server() {
  [ -x "$LAUNCHER" ] && [ -n "$NODE_BIN" ] || return 0
  local out
  if out="$("$LAUNCHER" --version 2>&1)"; then
    ok "Server starts: $out"
  else
    bad "Launcher failed: $out"
    return
  fi
  log "Opening a test page in headless $BROWSER_LABEL (takes a few seconds)…"
  # --isolated: never touch the persistent profile Claude Desktop may be using.
  # Own --output-dir: keep the test's page snapshot out of the user's folder.
  local smoke_args=(--browser "$BROWSER" --output-dir "$HELPERS/out" --headless --isolated)
  [ -z "$CHROME_EXEC" ] || smoke_args+=(--executable-path "$CHROME_EXEC")
  out="$("$NODE_BIN" "$HELPERS/smoke.js" "$LAUNCHER" "${smoke_args[@]}" 2>&1 || true)"
  if [[ "$out" == *BROWSER=ok* ]]; then
    ok "MCP handshake OK, $(printf '%s\n' "$out" | sed -n 's/^TOOLS=//p') tools, $BROWSER_LABEL opened a page"
  else
    bad "Browser check failed:"
    printf '%s\n' "$out" | sed 's/^/      /' >&2
  fi
}

# ─────────────────────────────────── Main ─────────────────────────────────
main() {
  while [ $# -gt 0 ]; do
    case "$1" in
      --check)   CHECK_ONLY=1 ;;
      -h|--help) usage; exit 0 ;;
      *) err "Unknown option: $1"; usage; exit 2 ;;
    esac
    shift
  done

  [ "$(uname -s)" = "Darwin" ] || die "This script is for macOS (found $(uname -s))."
  [ "$(id -u)" -ne 0 ] || die "Do not run this with sudo — it configures your own user account."
  case "$BROWSER" in
    ""|chrome) ;;
    chromium)
      [ "$(sw_vers -productVersion | cut -d. -f1)" -ge 14 ] \
        || die "Playwright's Chromium needs macOS 14 or newer (this Mac: $(sw_vers -productVersion)). Run without PLAYWRIGHT_MCP_BROWSER to use Google Chrome." ;;
    *) die "PLAYWRIGHT_MCP_BROWSER must be chrome or chromium (got: $BROWSER)." ;;
  esac

  log "Playwright MCP for Claude Desktop — macOS $(sw_vers -productVersion) ($(uname -m))$([ "$CHECK_ONLY" -eq 1 ] && echo ', check only')"

  ensure_claude
  ensure_node
  resolve_browser
  [ "$BROWSER" = "chromium" ] || ensure_chrome
  if [ -z "$NODE_BIN" ]; then
    die "Node.js is required for the remaining checks. Run without --check to install it."
  fi
  ensure_package
  [ "$BROWSER" = "chrome" ] || ensure_chromium
  ensure_launcher
  write_helpers
  server_args
  ensure_desktop_config
  verify_server

  echo
  if [ "$FAILURES" -gt 0 ]; then
    err "$FAILURES check(s) failed — see above."
    [ "$CHECK_ONLY" -eq 1 ] && err "Run without --check to fix: curl -fsSL $SCRIPT_URL | bash"
    exit 1
  fi
  ok "${C_BOLD}Playwright MCP is set up for Claude Desktop${C_RESET}"
  if [ "$BROWSER" = "chromium" ]; then
    echo "    Browser:    Chromium (Playwright build — re-run this script now and then for security updates)"
  else
    echo "    Browser:    Google Chrome"
  fi
  echo "    Config:     $DESKTOP_CFG"
  echo "    Files land: $WORKSPACE"
  if [ "$CHECK_ONLY" -eq 0 ] && [ "$CHANGED_RUNTIME" -eq 1 ]; then
    echo
    # No `grep -q`: it exits on the first match, ps gets SIGPIPE and pipefail reports failure.
    if ps -axo comm= | grep '/Claude\.app/Contents/MacOS/Claude$' >/dev/null; then
      warn "Claude Desktop is running: quit it fully (Cmd+Q) and open it again to load the change."
    else
      echo "    Open Claude Desktop — the \"$SERVER_NAME\" server starts with it."
    fi
  fi
  echo "    Check: Claude Desktop → Settings → Developer → \"$SERVER_NAME\" shows \"running\"."
}

main "$@"
