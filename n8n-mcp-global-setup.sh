#!/usr/bin/env bash
#
# n8n-mcp-global-setup.sh — install & verify the n8n-mcp server for Claude on macOS,
#                           across both surfaces:
#     • Claude Desktop  → ~/Library/Application Support/Claude/claude_desktop_config.json
#     • Claude Code CLI → user scope in ~/.claude.json (available in every project)
#
# The API key lives ONLY in ~/.zshenv as `export SNF_N8N_API_KEY=...`. Neither
# config file stores the secret:
#   • Claude Code expands the reference ${SNF_N8N_API_KEY} at launch.
#   • Claude Desktop is a GUI app that does NOT read ~/.zshenv and does NOT expand
#     ${VAR}, so the server is launched through a small zsh wrapper
#         /bin/zsh -lc 'N8N_API_KEY="$SNF_N8N_API_KEY" exec npx -y n8n-mcp'
#     which sources ~/.zshenv itself and maps the key into the child process.
#
# What it does:
#   1. Checks prerequisites (macOS, Homebrew, Node/npx, /bin/zsh, login shell;
#      Claude Code CLI only if the --code path is used). Missing pieces are offered
#      as Homebrew installs — Claude Code via `brew install --cask claude-code`.
#   2. Stores the n8n API key in ~/.zshenv (chmod 600, idempotent).
#   3. Writes the `n8n` entry into the Claude Desktop config (JSON-merged with the
#      existing file via node — no jq needed; every other key is preserved).
#   4. Registers `n8n` at Claude Code user scope via `claude mcp add --scope user`.
#   5. Verifies: key valid against the n8n REST API, npx starts n8n-mcp, the zsh
#      wrapper resolves the key, and both configs contain the entry.
#
# No jq dependency — JSON is edited with node (already required for npx). Needs only
# what macOS provides (bash 3.2, curl, /bin/zsh) plus Node. Safe to re-run.
#
# Usage:
#   ./n8n-mcp-global-setup.sh                    # set up Desktop + Claude Code (interactive)
#   ./n8n-mcp-global-setup.sh --check            # verify only, no changes
#   ./n8n-mcp-global-setup.sh --no-code          # Claude Desktop only
#   ./n8n-mcp-global-setup.sh --no-desktop       # Claude Code only
#   ./n8n-mcp-global-setup.sh --desktop-config <path>   # write to a specific file
#                                                       # (e.g. to prepare a teammate's)
#   ./n8n-mcp-global-setup.sh --url https://n8n.example.com
#   ./n8n-mcp-global-setup.sh --key KEY --yes    # non-interactive
#   echo KEY | ./n8n-mcp-global-setup.sh --yes
#
set -euo pipefail

# ---------------------------------------------------------------- configuration
SERVER_NAME="n8n"
ENV_VAR="SNF_N8N_API_KEY"
N8N_API_URL="https://n8n.gluzdov.com"
ZSHENV="$HOME/.zshenv"
DESKTOP_CFG="$HOME/Library/Application Support/Claude/claude_desktop_config.json"

CHECK_ONLY=0
FORCE=0
CLI_KEY=""
ASSUME_YES=0
DO_DESKTOP=1
DO_CODE=1

while [[ $# -gt 0 ]]; do
  case "$1" in
    --check)           CHECK_ONLY=1; shift ;;
    --force|--force-key) FORCE=1; shift ;;
    --key)             CLI_KEY="${2:?--key needs a value}"; shift 2 ;;
    --yes|-y)          ASSUME_YES=1; shift ;;
    --url)             N8N_API_URL="${2:?--url needs a value}"; shift 2 ;;
    --desktop-config)  DESKTOP_CFG="${2:?--desktop-config needs a value}"; shift 2 ;;
    --no-desktop)      DO_DESKTOP=0; shift ;;
    --no-code)         DO_CODE=0; shift ;;
    -h|--help)         sed -n '2,45p' "$0"; exit 0 ;;
    *) echo "Unknown option: $1 (try --help)" >&2; exit 2 ;;
  esac
done

[[ $DO_DESKTOP -eq 1 || $DO_CODE -eq 1 ]] || { echo "Nothing to do: --no-desktop and --no-code together." >&2; exit 2; }

# ---------------------------------------------------------------------- helpers
BOLD=$'\033[1m'; RED=$'\033[31m'; GRN=$'\033[32m'; YLW=$'\033[33m'; DIM=$'\033[2m'; RST=$'\033[0m'
FAILURES=0

info() { printf '%s==>%s %s\n' "$BOLD" "$RST" "$*"; }
ok()   { printf '  %s✓%s %s\n' "$GRN" "$RST" "$*"; }
warn() { printf '  %s!%s %s\n' "$YLW" "$RST" "$*"; }
bad()  { printf '  %s✗%s %s\n' "$RED" "$RST" "$*"; FAILURES=$((FAILURES + 1)); }
die()  { printf '%s✗ %s%s\n' "$RED" "$*" "$RST" >&2; exit 1; }

# Interactive input on fd 3: the controlling terminal when there is one, else stdin
# (so `echo KEY | ./script --yes` and CI runs still work). Silence the harmless
# "Device not configured" that opening /dev/tty prints when there is no terminal.
HAS_TTY=0
exec 4>&2 2>/dev/null
if exec 3</dev/tty; then HAS_TTY=1; else exec 3<&0; fi
exec 2>&4 4>&-

confirm() { # confirm "question" -> 0 yes / 1 no
  local reply
  if [[ $ASSUME_YES -eq 1 ]]; then
    printf '  %s [y/N] y %s(--yes)%s\n' "$1" "$DIM" "$RST"; return 0
  fi
  if [[ $HAS_TTY -eq 0 ]]; then
    printf '  %s [y/N] n %s(no terminal — pass --yes to auto-confirm)%s\n' "$1" "$DIM" "$RST"; return 1
  fi
  read -r -p "  $1 [y/N] " reply <&3 || return 1
  [[ "$reply" == [yY]* ]]
}

# The zsh wrapper the Desktop config launches. Sourcing ~/.zshenv happens
# automatically for every zsh; -l also loads the profile so npx is on PATH.
WRAPPER_ARG='N8N_API_KEY="$'"$ENV_VAR"'" exec npx -y n8n-mcp'

# desktop_write <config-path> <url> — JSON-merge the n8n entry via node (no jq).
# Creates the file if missing, preserves every other key, errors on non-object JSON.
desktop_write() {
  local tmp; tmp="$(mktemp)"
  cat > "$tmp" <<'JS'
const fs = require('fs');
const [, , path, url, wrapper] = process.argv;
let cfg = {};
try { cfg = JSON.parse(fs.readFileSync(path, 'utf8')); }
catch (e) { if (e.code !== 'ENOENT') { console.error('NOT_JSON:' + e.message); process.exit(3); } }
if (cfg === null || typeof cfg !== 'object' || Array.isArray(cfg)) { console.error('NOT_OBJECT'); process.exit(3); }
if (cfg.mcpServers === null || typeof cfg.mcpServers !== 'object' || Array.isArray(cfg.mcpServers)) cfg.mcpServers = {};
cfg.mcpServers.n8n = {
  command: '/bin/zsh',
  args: ['-lc', wrapper],
  env: { MCP_MODE: 'stdio', LOG_LEVEL: 'error', DISABLE_CONSOLE_OUTPUT: 'true', N8N_API_URL: url }
};
fs.writeFileSync(path, JSON.stringify(cfg, null, 2) + '\n');
JS
  node "$tmp" "$1" "$2" "$WRAPPER_ARG"; local rc=$?
  rm -f "$tmp"; return $rc
}

# desktop_has_n8n <config-path> — exit 0 if mcpServers.n8n exists
desktop_has_n8n() {
  node -e 'try{const c=JSON.parse(require("fs").readFileSync(process.argv[1],"utf8"));process.exit(c&&c.mcpServers&&c.mcpServers.n8n?0:1)}catch(e){process.exit(1)}' "$1" 2>/dev/null
}

# ------------------------------------------------------------- 1. prerequisites
info "Checking prerequisites"

[[ "$(uname -s)" == "Darwin" ]] || die "This script targets macOS (found $(uname -s))."
ok "macOS $(sw_vers -productVersion)"

if command -v brew >/dev/null 2>&1; then
  ok "Homebrew $(brew --version | head -1 | awk '{print $2}')"
  HAS_BREW=1
else
  HAS_BREW=0
  for BREW_BIN in /opt/homebrew/bin/brew /usr/local/bin/brew; do
    if [[ -x "$BREW_BIN" ]]; then
      eval "$("$BREW_BIN" shellenv)"
      ok "Homebrew found at $BREW_BIN (added to PATH for this run)"
      HAS_BREW=1
      break
    fi
  done
  if [[ $HAS_BREW -eq 0 ]]; then
    warn "Homebrew not found. Install it first, then re-run this script:"
    echo '     /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"'
  fi
fi

brew_install() { # brew_install <formula-args...>
  [[ $HAS_BREW -eq 1 ]] || return 1
  brew install "$@" || return 1
  hash -r 2>/dev/null || true
}

# /bin/zsh — the Desktop wrapper launches the server through it (macOS default shell)
if [[ $DO_DESKTOP -eq 1 ]]; then
  [[ -x /bin/zsh ]] && ok "/bin/zsh present (used by the Desktop launch wrapper)" \
                    || bad "/bin/zsh not found — required for the Claude Desktop wrapper"
fi

# Node / npx — n8n-mcp runs via `npx n8n-mcp`, and we edit JSON with node
if command -v npx >/dev/null 2>&1 && command -v node >/dev/null 2>&1; then
  ok "Node $(node --version 2>/dev/null) / npx $(npx --version 2>/dev/null)"
else
  bad "Node/npx not found — required to run n8n-mcp and to edit the Desktop config"
  if [[ $CHECK_ONLY -eq 0 ]] && confirm "Install Node via Homebrew (brew install node)?"; then
    brew_install node && { ok "Node $(node --version 2>/dev/null)"; FAILURES=$((FAILURES - 1)); } \
      || die "Node install failed. Install it manually:  brew install node"
  else
    echo "     Install with:  brew install node"
    [[ $CHECK_ONLY -eq 1 ]] || die "Node/npx is required."
  fi
fi

# Claude Code CLI — only needed for the --code path
if [[ $DO_CODE -eq 1 ]]; then
  if command -v claude >/dev/null 2>&1; then
    ok "Claude Code $(claude --version 2>/dev/null | head -1)"
  else
    warn "Claude Code CLI (\`claude\`) not found"
    if [[ $CHECK_ONLY -eq 0 && $HAS_BREW -eq 1 ]] && confirm "Install Claude Code via Homebrew (brew install --cask claude-code)?"; then
      brew install --cask claude-code || die "Claude Code install failed."
      hash -r 2>/dev/null || true
      command -v claude >/dev/null 2>&1 && ok "Claude Code installed: $(claude --version 2>/dev/null | head -1)" \
        || die "Install finished but \`claude\` is still not on PATH — open a new terminal and re-run."
    else
      warn "skipping Claude Code setup (install it with: brew install --cask claude-code, or pass --no-code)"
      DO_CODE=0
    fi
  fi
fi

# Claude Desktop app — config is pointless without it (non-fatal: you may be
# preparing a config for another machine via --desktop-config)
if [[ $DO_DESKTOP -eq 1 ]]; then
  [[ -d /Applications/Claude.app ]] && ok "Claude Desktop app installed" \
    || warn "Claude Desktop app not found in /Applications (writing config anyway)"
fi

# Login shell — ~/.zshenv is only sourced by zsh
case "${SHELL:-}" in
  *zsh) ok "login shell is zsh — $ZSHENV will be sourced" ;;
  "")   warn "\$SHELL is unset — make sure $ZSHENV is sourced by your login shell" ;;
  *)    warn "login shell is $SHELL, not zsh. The Desktop wrapper still uses /bin/zsh, but"
        echo "     for Claude Code make sure you launch it from a shell that sources $ZSHENV." ;;
esac

# ------------------------------------------------------------------- 2. API key
info "n8n API key (\$$ENV_VAR in $ZSHENV)"

KEY_IN_ENV="${!ENV_VAR:-}"
KEY_IN_FILE=""
if [[ -f "$ZSHENV" ]] && grep -qE "^[[:space:]]*export[[:space:]]+$ENV_VAR=" "$ZSHENV"; then
  KEY_IN_FILE="$(grep -E "^[[:space:]]*export[[:space:]]+$ENV_VAR=" "$ZSHENV" | tail -1 | cut -d= -f2- | tr -d "\"' ")"
fi
API_KEY="${KEY_IN_FILE:-$KEY_IN_ENV}"

if [[ $CHECK_ONLY -eq 1 ]]; then
  [[ -n "$KEY_IN_FILE" ]] && ok "key present in $ZSHENV (${#KEY_IN_FILE} chars)" || bad "no \`export $ENV_VAR=\` line in $ZSHENV"
  [[ -n "$KEY_IN_ENV" ]]  && ok "\$$ENV_VAR resolves in this shell"            || warn "\$$ENV_VAR not set in this shell (source $ZSHENV or open a new terminal)"
else
  NEW_KEY=""
  if [[ -n "$CLI_KEY" ]]; then
    NEW_KEY="$CLI_KEY"; ok "using key passed via --key (replacing any existing one)"
  elif [[ -n "$API_KEY" ]]; then
    ok "key already configured (${#API_KEY} chars) — pass --key to replace it"
  else
    echo "  Create a key in n8n: Settings → n8n API → Create an API key"
    if [[ $HAS_TTY -eq 1 ]]; then
      echo "  ${DIM}Input is hidden; the key is written only to $ZSHENV (chmod 600).${RST}"
      read -r -s -p "  Paste n8n API key: " NEW_KEY <&3 || die "Could not read the key."
      echo
    else
      echo "  ${DIM}No terminal detected — reading the key from stdin.${RST}"
      read -r NEW_KEY <&3 || true
      [[ -n "${NEW_KEY:-}" ]] || die "No terminal and nothing on stdin. Run the script from Terminal, or pass the key non-interactively:
     ./$(basename "$0") --key <n8n-api-key> --yes
     echo <n8n-api-key> | ./$(basename "$0") --yes
     export $ENV_VAR=<n8n-api-key> && ./$(basename "$0")"
    fi
  fi

  if [[ -n "$NEW_KEY" ]]; then
    NEW_KEY="${NEW_KEY//[$'\t\r\n ']/}"
    [[ -n "$NEW_KEY" ]] || die "Empty key — aborting."
    touch "$ZSHENV"; chmod 600 "$ZSHENV"
    cp "$ZSHENV" "$ZSHENV.bak.$(date +%Y%m%d%H%M%S)"
    grep -vE "^[[:space:]]*export[[:space:]]+$ENV_VAR=" "$ZSHENV" > "$ZSHENV.tmp" || true
    mv "$ZSHENV.tmp" "$ZSHENV"; chmod 600 "$ZSHENV"
    printf '\n# n8n MCP (%s)\nexport %s="%s"\n' "$N8N_API_URL" "$ENV_VAR" "$NEW_KEY" >> "$ZSHENV"
    ok "key written to $ZSHENV (backup kept alongside)"
    API_KEY="$NEW_KEY"; export "$ENV_VAR=$NEW_KEY"
  fi
fi

# ------------------------------------------------- 3. Claude Desktop config file
if [[ $DO_DESKTOP -eq 1 ]]; then
  info "Claude Desktop config ($DESKTOP_CFG)"

  if [[ $CHECK_ONLY -eq 1 ]]; then
    if [[ -f "$DESKTOP_CFG" ]] && desktop_has_n8n "$DESKTOP_CFG"; then
      ok "\"$SERVER_NAME\" entry present"
      node -e 'const c=JSON.parse(require("fs").readFileSync(process.argv[1],"utf8"));const n=c.mcpServers.n8n;console.log("     command: "+n.command);console.log("     args:    "+JSON.stringify(n.args));console.log("     env:     "+JSON.stringify(n.env));' "$DESKTOP_CFG" 2>/dev/null || true
      node -e 'const c=JSON.parse(require("fs").readFileSync(process.argv[1],"utf8"));const s=JSON.stringify(c.mcpServers.n8n);process.exit(/N8N_API_KEY"?\s*:\s*"(?!\$)/.test(s)?1:0)' "$DESKTOP_CFG" 2>/dev/null \
        && ok "no plaintext key in the config (key comes from \$$ENV_VAR via the zsh wrapper)" \
        || bad "the config appears to contain a literal N8N_API_KEY value"
    else
      bad "no \"$SERVER_NAME\" entry in $DESKTOP_CFG (run without --check to add it)"
    fi
  else
    DCFG_DIR="$(dirname "$DESKTOP_CFG")"
    mkdir -p "$DCFG_DIR" 2>/dev/null || mkdir -p "$DESKTOP_CFG/../" 2>/dev/null || true
    [[ -d "$DCFG_DIR" ]] || die "Cannot create config directory: $DCFG_DIR"
    if [[ -f "$DESKTOP_CFG" ]]; then
      node -e 'JSON.parse(require("fs").readFileSync(process.argv[1],"utf8"))' "$DESKTOP_CFG" 2>/dev/null \
        || die "$DESKTOP_CFG exists but is not valid JSON — fix or move it, then re-run."
      if desktop_has_n8n "$DESKTOP_CFG" && [[ $FORCE -eq 0 ]]; then
        ok "\"$SERVER_NAME\" already present — refreshing entry"
      fi
      cp "$DESKTOP_CFG" "$DESKTOP_CFG.bak.$(date +%Y%m%d%H%M%S)"
    fi
    desktop_write "$DESKTOP_CFG" "$N8N_API_URL" \
      && ok "\"$SERVER_NAME\" merged into Desktop config (no secret in file; launched via /bin/zsh wrapper)" \
      || die "Failed to write $DESKTOP_CFG"
    [[ -f "$DESKTOP_CFG.bak."* ]] 2>/dev/null && echo "     ${DIM}backup kept alongside${RST}" || true
    warn "restart Claude Desktop completely (Cmd+Q, then reopen) to load the new server"
  fi
fi

# --------------------------------------------- 4. Claude Code (user scope)
if [[ $DO_CODE -eq 1 ]]; then
  info "Claude Code user (global) scope"

  if [[ $CHECK_ONLY -eq 1 ]]; then
    if claude mcp get "$SERVER_NAME" >/dev/null 2>&1; then
      ok "\"$SERVER_NAME\" is registered"
      claude mcp get "$SERVER_NAME" 2>/dev/null | grep -iE 'scope|command|args|N8N_API_URL' | sed 's/^/     /' || true
    else
      bad "\"$SERVER_NAME\" is not registered (run without --check to add it)"
    fi
  else
    if claude mcp get "$SERVER_NAME" >/dev/null 2>&1; then
      if [[ $FORCE -eq 1 ]]; then
        claude mcp remove "$SERVER_NAME" --scope user >/dev/null 2>&1 || claude mcp remove "$SERVER_NAME" >/dev/null 2>&1 || true
        ok "removed existing registration (--force)"
      else
        ok "\"$SERVER_NAME\" already registered — use --force to re-register"
      fi
    fi
    if ! claude mcp get "$SERVER_NAME" >/dev/null 2>&1; then
      # single-quote the key env so the shell does NOT expand it; Claude Code stores
      # the literal reference and expands it at launch.
      claude mcp add "$SERVER_NAME" --scope user \
        -e MCP_MODE=stdio -e LOG_LEVEL=error -e DISABLE_CONSOLE_OUTPUT=true \
        -e "N8N_API_URL=$N8N_API_URL" \
        -e 'N8N_API_KEY=${'"$ENV_VAR"'}' \
        -- npx -y n8n-mcp \
        && ok "registered at user scope (key referenced as \${$ENV_VAR})" \
        || die "\`claude mcp add\` failed."
    fi
  fi
fi

# ------------------------------------------------------------- 5. verification
info "Verification"

# 5a. n8n REST API reachable and the key accepted
VERIFY_KEY="${!ENV_VAR:-$API_KEY}"
if [[ -z "${VERIFY_KEY:-}" ]]; then
  warn "skipping API check — no key available in this shell"
else
  HTTP_CODE="$(curl -s -o /dev/null -w '%{http_code}' --max-time 20 \
    -H "X-N8N-API-KEY: $VERIFY_KEY" "$N8N_API_URL/api/v1/workflows?limit=1" || echo 000)"
  case "$HTTP_CODE" in
    200) ok "n8n API $N8N_API_URL responded 200 — key is valid" ;;
    401|403) bad "n8n API rejected the key (HTTP $HTTP_CODE) — regenerate it and re-run with --key <new>" ;;
    000) bad "could not reach $N8N_API_URL (network/VPN/DNS?)" ;;
    *)   bad "n8n API returned HTTP $HTTP_CODE" ;;
  esac
fi

# 5b. the zsh wrapper (what Desktop runs) resolves the key from ~/.zshenv + finds npx
if [[ $DO_DESKTOP -eq 1 && -x /bin/zsh ]]; then
  WRAP_OUT="$(env -i HOME="$HOME" /bin/zsh -lc 'printf "%s|%s" "${#'"$ENV_VAR"'}" "$(command -v npx || true)"' 2>/dev/null || true)"
  WRAP_LEN="${WRAP_OUT%%|*}"; WRAP_NPX="${WRAP_OUT#*|}"
  if [[ "${WRAP_LEN:-0}" -gt 0 && -n "$WRAP_NPX" ]]; then
    ok "Desktop wrapper OK — /bin/zsh -l resolves \$$ENV_VAR (${WRAP_LEN} chars) and finds npx"
  else
    [[ "${WRAP_LEN:-0}" -gt 0 ]] || bad "Desktop wrapper: \$$ENV_VAR not set from ~/.zshenv in a fresh zsh login shell"
    [[ -n "$WRAP_NPX" ]]         || bad "Desktop wrapper: npx not on PATH in a fresh zsh login shell (Node PATH not in ~/.zprofile/.zshrc?)"
  fi
fi

# 5c. n8n-mcp package starts under npx
if command -v npx >/dev/null 2>&1; then
  printf '  %s…%s starting n8n-mcp via npx (first run downloads the package, may take a minute)\n' "$DIM" "$RST"
  if MCP_MODE=stdio LOG_LEVEL=error DISABLE_CONSOLE_OUTPUT=true npx -y n8n-mcp --version >/dev/null 2>&1 \
     || npx -y n8n-mcp --help >/dev/null 2>&1; then
    ok "n8n-mcp resolves and starts via npx"
  else
    bad "\`npx -y n8n-mcp\` failed — check network / npm registry access"
  fi
fi

# 5d. Claude Code sees the server
if [[ $DO_CODE -eq 1 ]] && command -v claude >/dev/null 2>&1; then
  if MCP_LIST="$(claude mcp list 2>&1)"; then
    LINE="$(grep -iE "(^|[[:space:]/])$SERVER_NAME:" <<<"$MCP_LIST" | head -1)"
    [[ -n "$LINE" ]] && { ok "\`claude mcp list\` reports \"$SERVER_NAME\""; echo "     ${LINE#"${LINE%%[![:space:]]*}"}"; } \
                     || warn "\"$SERVER_NAME\" not listed yet — restart Claude Code to pick it up"
  fi
fi

# ------------------------------------------------------------------ 6. summary
echo
if [[ $FAILURES -eq 0 ]]; then
  printf '%s✓ n8n MCP set up%s%s%s.%s\n' "$GRN$BOLD" \
    "$([[ $DO_DESKTOP -eq 1 ]] && echo ' for Claude Desktop')" \
    "$([[ $DO_DESKTOP -eq 1 && $DO_CODE -eq 1 ]] && echo ' and')" \
    "$([[ $DO_CODE -eq 1 ]] && echo ' Claude Code (user scope)')" "$RST"
else
  printf '%s✗ %d check(s) failed — see above.%s\n' "$RED$BOLD" "$FAILURES" "$RST"
fi

cat <<EOF

${BOLD}Next steps${RST}
  1. Open a NEW terminal (or run: source $ZSHENV) so \$$ENV_VAR is exported.
EOF
[[ $DO_DESKTOP -eq 1 ]] && cat <<EOF
  2. ${BOLD}Claude Desktop:${RST} fully quit (Cmd+Q) and reopen it — the config is read
     only at launch. Then check Settings → Developer for the "$SERVER_NAME" server.
EOF
[[ $DO_CODE -eq 1 ]] && cat <<EOF
  3. ${BOLD}Claude Code:${RST} start \`claude\` in any project, run  /mcp , confirm "$SERVER_NAME"
     is connected (~39 tools).  Details:  claude mcp get $SERVER_NAME
EOF
cat <<EOF
  •  Re-verify any time:  $(basename "$0") --check
  •  Remove later:  claude mcp remove $SERVER_NAME --scope user   (Claude Code)
     and delete the "$SERVER_NAME" block from $DESKTOP_CFG   (Desktop)
EOF

exit $(( FAILURES > 0 ? 1 : 0 ))
