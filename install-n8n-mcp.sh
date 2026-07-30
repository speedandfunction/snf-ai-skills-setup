#!/usr/bin/env bash
#
# install-n8n-mcp.sh — install & verify the n8n-mcp server for Claude Code on macOS.
#
# What it does:
#   1. Checks prerequisites (macOS, Homebrew, jq, Node/npx, Claude Code CLI, login shell).
#      Missing pieces are offered as Homebrew installs — Claude Code via
#      `brew install --cask claude-code`.
#   2. Asks for the n8n API key (hidden input) and stores it in ~/.zshenv
#      as `export SNF_N8N_API_KEY=...` (idempotent — an existing line is replaced).
#   3. Writes the `n8n` MCP server entry into the project's .mcp.json, referencing
#      the env var (`${SNF_N8N_API_KEY}`) — never the plaintext key.
#   4. Verifies: env var resolves, n8n REST API answers with the key,
#      `npx n8n-mcp` starts, and `claude mcp list` reports the server.
#
# Requires only what macOS provides (bash 3.2, curl, sed/grep) plus jq.
# Safe to re-run: every step is idempotent.
#
# Usage:
#   ./scripts/n8n/install-n8n-mcp.sh              # full install (interactive)
#   ./scripts/n8n/install-n8n-mcp.sh --check      # verification only, no changes
#   ./scripts/n8n/install-n8n-mcp.sh --url https://n8n.example.com
#   ./scripts/n8n/install-n8n-mcp.sh --force-key  # re-prompt even if a key exists
#   ./scripts/n8n/install-n8n-mcp.sh --key KEY --yes   # non-interactive
#   echo KEY | ./scripts/n8n/install-n8n-mcp.sh --yes  # non-interactive via stdin
#   --mcp-json <path>                             # target another repo's .mcp.json
#
set -euo pipefail

# ---------------------------------------------------------------- configuration
SERVER_NAME="n8n"
ENV_VAR="SNF_N8N_API_KEY"
N8N_API_URL="https://n8n.gluzdov.com"
ZSHENV="$HOME/.zshenv"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
MCP_JSON="$REPO_ROOT/.mcp.json"

CHECK_ONLY=0
FORCE_KEY=0
CLI_KEY=""
ASSUME_YES=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --check)      CHECK_ONLY=1; shift ;;
    --force-key)  FORCE_KEY=1; shift ;;
    --key)        CLI_KEY="${2:?--key needs a value}"; shift 2 ;;
    --yes|-y)     ASSUME_YES=1; shift ;;
    --url)        N8N_API_URL="${2:?--url needs a value}"; shift 2 ;;
    --mcp-json)   MCP_JSON="${2:?--mcp-json needs a value}"; shift 2 ;;
    -h|--help)    sed -n '2,30p' "$0"; exit 0 ;;
    *) echo "Unknown option: $1 (try --help)" >&2; exit 2 ;;
  esac
done

# ---------------------------------------------------------------------- helpers
BOLD=$'\033[1m'; RED=$'\033[31m'; GRN=$'\033[32m'; YLW=$'\033[33m'; DIM=$'\033[2m'; RST=$'\033[0m'
FAILURES=0

info() { printf '%s==>%s %s\n' "$BOLD" "$RST" "$*"; }
ok()   { printf '  %s✓%s %s\n' "$GRN" "$RST" "$*"; }
warn() { printf '  %s!%s %s\n' "$YLW" "$RST" "$*"; }
bad()  { printf '  %s✗%s %s\n' "$RED" "$RST" "$*"; FAILURES=$((FAILURES + 1)); }
die()  { printf '%s✗ %s%s\n' "$RED" "$*" "$RST" >&2; exit 1; }

# Interactive input on fd 3: the controlling terminal when there is one, else stdin
# (so `echo KEY | ./install-n8n-mcp.sh --yes` and CI runs still work).
HAS_TTY=0
if exec 3</dev/tty 2>/dev/null; then
  HAS_TTY=1
else
  exec 3<&0
fi

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

# ------------------------------------------------------------- 1. prerequisites
info "Checking prerequisites"

[[ "$(uname -s)" == "Darwin" ]] || die "This script targets macOS (found $(uname -s))."
ok "macOS $(sw_vers -productVersion)"

if command -v brew >/dev/null 2>&1; then
  ok "Homebrew $(brew --version | head -1 | awk '{print $2}')"
  HAS_BREW=1
else
  HAS_BREW=0
  # Not on PATH yet? Homebrew may be installed but the shell wasn't re-inited.
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

# brew_install <formula-args...> — install and refresh the command hash table
brew_install() {
  [[ $HAS_BREW -eq 1 ]] || return 1
  brew install "$@" || return 1
  hash -r 2>/dev/null || true
}

# jq — used to edit .mcp.json. Shipped with macOS 15+, absent on 13/14.
HAS_JQ=1
if command -v jq >/dev/null 2>&1; then
  ok "jq $(jq --version 2>/dev/null)"
else
  HAS_JQ=0
  bad "jq not found (macOS 15+ ships it; older versions do not)"
  if [[ $CHECK_ONLY -eq 0 ]] && confirm "Install jq via Homebrew (brew install jq)?"; then
    brew_install jq && { ok "jq installed"; HAS_JQ=1; FAILURES=$((FAILURES - 1)); } \
      || die "jq install failed. Install it manually:  brew install jq"
  else
    echo "     Install with:  brew install jq"
    [[ $CHECK_ONLY -eq 1 ]] || die "jq is required to edit .mcp.json."
  fi
fi

# Node / npx — n8n-mcp runs via `npx n8n-mcp`
if command -v npx >/dev/null 2>&1; then
  ok "Node $(node --version 2>/dev/null || echo '?') / npx $(npx --version 2>/dev/null || echo '?')"
else
  bad "npx not found — n8n-mcp is run through npx"
  if [[ $CHECK_ONLY -eq 0 ]] && confirm "Install Node via Homebrew (brew install node)?"; then
    brew_install node && { ok "Node $(node --version 2>/dev/null)"; FAILURES=$((FAILURES - 1)); } \
      || die "Node install failed. Install it manually:  brew install node"
  else
    echo "     Install with:  brew install node"
    [[ $CHECK_ONLY -eq 1 ]] || die "Node/npx is required."
  fi
fi

# Claude Code CLI
if command -v claude >/dev/null 2>&1; then
  ok "Claude Code $(claude --version 2>/dev/null | head -1)"
else
  bad "Claude Code CLI (\`claude\`) not found"
  if [[ $CHECK_ONLY -eq 0 ]]; then
    if confirm "Install Claude Code via Homebrew (brew install --cask claude-code)?"; then
      [[ $HAS_BREW -eq 1 ]] || die "Homebrew is required for this. Install Homebrew first (see above), then re-run."
      brew install --cask claude-code || die "Claude Code install failed."
      hash -r 2>/dev/null || true
      command -v claude >/dev/null 2>&1 \
        && { ok "Claude Code installed: $(claude --version 2>/dev/null | head -1)"; FAILURES=$((FAILURES - 1)); } \
        || die "Install finished but \`claude\` is still not on PATH — open a new terminal and re-run."
    else
      die "Claude Code is required. Install it with:  brew install --cask claude-code"
    fi
  else
    echo "     Install with:  brew install --cask claude-code"
  fi
fi

# Login shell — ~/.zshenv is only sourced by zsh
case "${SHELL:-}" in
  *zsh) ok "login shell is zsh — $ZSHENV will be sourced" ;;
  "")   warn "\$SHELL is unset — make sure $ZSHENV is sourced by your login shell" ;;
  *)    warn "login shell is $SHELL, not zsh — $ZSHENV will NOT be sourced automatically."
        echo "     Either switch to zsh (default on macOS since 10.15) or add this line to your"
        echo "     shell's rc file:  source $ZSHENV" ;;
esac

# ------------------------------------------------------------------- 2. API key
info "n8n API key (\$$ENV_VAR in $ZSHENV)"

# Value already exported in this shell, or persisted in ~/.zshenv?
KEY_IN_ENV="${!ENV_VAR:-}"
KEY_IN_FILE=""
if [[ -f "$ZSHENV" ]] && grep -qE "^[[:space:]]*export[[:space:]]+$ENV_VAR=" "$ZSHENV"; then
  KEY_IN_FILE="$(grep -E "^[[:space:]]*export[[:space:]]+$ENV_VAR=" "$ZSHENV" | tail -1 | cut -d= -f2- | tr -d "\"' ")"
fi

API_KEY="${KEY_IN_FILE:-$KEY_IN_ENV}"

if [[ $CHECK_ONLY -eq 1 ]]; then
  [[ -n "$KEY_IN_FILE" ]] && ok "key present in $ZSHENV (${#KEY_IN_FILE} chars)" || bad "no \`export $ENV_VAR=\` line in $ZSHENV"
  [[ -n "$KEY_IN_ENV" ]]  && ok "\$$ENV_VAR resolves in this shell"            || bad "\$$ENV_VAR is not set in this shell (source $ZSHENV or open a new terminal)"
else
  if [[ -n "$API_KEY" && $FORCE_KEY -eq 0 ]]; then
    ok "key already configured (${#API_KEY} chars) — use --force-key to replace it"
  else
    if [[ -n "$CLI_KEY" ]]; then
      API_KEY="$CLI_KEY"
      ok "using key passed via --key"
    else
      echo "  Create a key in n8n: Settings → n8n API → Create an API key"
      if [[ $HAS_TTY -eq 1 ]]; then
        echo "  ${DIM}Input is hidden; the key is written only to $ZSHENV (chmod 600).${RST}"
        read -r -s -p "  Paste n8n API key: " API_KEY <&3 || die "Could not read the key."
        echo
      else
        # No terminal (curl | bash, CI, remote run): take the key from stdin.
        echo "  ${DIM}No terminal detected — reading the key from stdin.${RST}"
        read -r API_KEY <&3 || true
        [[ -n "${API_KEY:-}" ]] || die "No terminal and nothing on stdin. Run the script directly from Terminal, or pass the key non-interactively:
     ./$(basename "$0") --key <n8n-api-key> --yes
     echo <n8n-api-key> | ./$(basename "$0") --yes
     export $ENV_VAR=<n8n-api-key> && ./$(basename "$0")"
      fi
    fi
    API_KEY="${API_KEY//[$'\t\r\n ']/}"
    [[ -n "$API_KEY" ]] || die "Empty key — aborting."

    touch "$ZSHENV"; chmod 600 "$ZSHENV"
    cp "$ZSHENV" "$ZSHENV.bak.$(date +%Y%m%d%H%M%S)"
    # drop any previous line for this var, then append the new one
    grep -vE "^[[:space:]]*export[[:space:]]+$ENV_VAR=" "$ZSHENV" > "$ZSHENV.tmp" || true
    mv "$ZSHENV.tmp" "$ZSHENV"; chmod 600 "$ZSHENV"
    printf '\n# n8n MCP (%s)\nexport %s="%s"\n' "$N8N_API_URL" "$ENV_VAR" "$API_KEY" >> "$ZSHENV"
    ok "key written to $ZSHENV (backup kept alongside)"
    export "$ENV_VAR=$API_KEY"
  fi
fi

# --------------------------------------------------------------- 3. .mcp.json
info "MCP server entry in $(basename "$MCP_JSON")"

if [[ $HAS_JQ -eq 0 ]]; then
  warn "skipping .mcp.json inspection — jq is not installed"
elif [[ $CHECK_ONLY -eq 1 ]]; then
  if [[ -f "$MCP_JSON" ]] && jq -e --arg n "$SERVER_NAME" '.mcpServers[$n]' "$MCP_JSON" >/dev/null 2>&1; then
    ok "\"$SERVER_NAME\" entry present"
    jq -r --arg n "$SERVER_NAME" '.mcpServers[$n].env | to_entries[] | "     \(.key)=\(.value)"' "$MCP_JSON"
    jq -e --arg n "$SERVER_NAME" '.mcpServers[$n].env.N8N_API_KEY | test("^\\$\\{.*\\}$")' "$MCP_JSON" >/dev/null 2>&1 \
      && ok "N8N_API_KEY uses env expansion (no plaintext secret)" \
      || bad "N8N_API_KEY looks like a literal value — replace it with \${$ENV_VAR}"
  else
    bad "no \"$SERVER_NAME\" entry in $MCP_JSON"
  fi
else
  MCP_DIR="$(dirname "$MCP_JSON")"
  [[ -d "$MCP_DIR" ]] || die "Directory does not exist: $MCP_DIR (pass --mcp-json <path>)"
  if [[ ! -f "$MCP_JSON" ]]; then
    # Creating a fresh file — make sure we're not scattering one into a random folder
    # (e.g. the script was copied out of the repo and run from ~/Downloads).
    if [[ ! -d "$MCP_DIR/.git" ]]; then
      warn "$MCP_DIR is not a git repository root and has no .mcp.json yet."
      confirm "Create a new .mcp.json there anyway?" || die "Aborted. Run the script from inside the repo, or pass --mcp-json <path>."
    fi
    echo '{"mcpServers":{}}' > "$MCP_JSON"
  fi
  jq -e . "$MCP_JSON" >/dev/null 2>&1 || die "$MCP_JSON is not valid JSON — fix it before re-running."
  jq --arg n "$SERVER_NAME" --arg url "$N8N_API_URL" --arg key "\${$ENV_VAR}" '
    .mcpServers[$n] = {
      command: "npx",
      args: ["-y", "n8n-mcp"],
      env: {
        MCP_MODE: "stdio",
        LOG_LEVEL: "error",
        DISABLE_CONSOLE_OUTPUT: "true",
        N8N_API_URL: $url,
        N8N_API_KEY: $key
      }
    }' "$MCP_JSON" > "$MCP_JSON.tmp" && mv "$MCP_JSON.tmp" "$MCP_JSON"
  ok "\"$SERVER_NAME\" entry written (API key referenced as \${$ENV_VAR})"
fi

# ------------------------------------------------------------- 4. verification
info "Verification"

# 4a. n8n REST API reachable and the key accepted
VERIFY_KEY="${!ENV_VAR:-$API_KEY}"
if [[ -z "${VERIFY_KEY:-}" ]]; then
  warn "skipping API check — no key available in this shell"
else
  HTTP_CODE="$(curl -s -o /dev/null -w '%{http_code}' --max-time 20 \
    -H "X-N8N-API-KEY: $VERIFY_KEY" \
    "$N8N_API_URL/api/v1/workflows?limit=1" || echo 000)"
  case "$HTTP_CODE" in
    200) ok "n8n API $N8N_API_URL responded 200 — key is valid" ;;
    401|403) bad "n8n API rejected the key (HTTP $HTTP_CODE) — regenerate it and re-run with --force-key" ;;
    000) bad "could not reach $N8N_API_URL (network/VPN/DNS?)" ;;
    *)   bad "n8n API returned HTTP $HTTP_CODE" ;;
  esac
fi

# 4b. n8n-mcp package starts under npx
if command -v npx >/dev/null 2>&1; then
  printf '  %s…%s fetching/starting n8n-mcp via npx (first run downloads the package, may take a minute)\n' "$DIM" "$RST"
  MCP_VER="$(MCP_MODE=stdio LOG_LEVEL=error DISABLE_CONSOLE_OUTPUT=true \
             npx -y n8n-mcp --version 2>/dev/null | tail -1 || true)"
  if [[ -n "$MCP_VER" ]]; then
    ok "n8n-mcp runs via npx (${MCP_VER})"
  else
    # --version is not guaranteed; fall back to resolving the package
    if npx -y n8n-mcp --help >/dev/null 2>&1; then
      ok "n8n-mcp resolves and starts via npx"
    else
      bad "\`npx -y n8n-mcp\` failed — check network / npm registry access"
    fi
  fi
fi

# 4c. Claude Code sees the server
if command -v claude >/dev/null 2>&1; then
  if MCP_LIST="$(cd "$REPO_ROOT" && claude mcp list 2>&1)"; then
    if grep -q "^$SERVER_NAME\b\|[[:space:]]$SERVER_NAME:" <<<"$MCP_LIST"; then
      ok "\`claude mcp list\` reports \"$SERVER_NAME\""
      grep -i "$SERVER_NAME" <<<"$MCP_LIST" | sed 's/^/     /'
    else
      warn "\"$SERVER_NAME\" not listed yet — restart Claude Code to pick up .mcp.json"
    fi
  else
    warn "\`claude mcp list\` failed:"; sed 's/^/     /' <<<"$MCP_LIST"
  fi
fi

# ------------------------------------------------------------------ 5. summary
echo
if [[ $FAILURES -eq 0 ]]; then
  printf '%s✓ n8n MCP is ready.%s\n' "$GRN$BOLD" "$RST"
else
  printf '%s✗ %d check(s) failed — see above.%s\n' "$RED$BOLD" "$FAILURES" "$RST"
fi

cat <<EOF

${BOLD}Next steps${RST}
  1. Open a NEW terminal (or run: source $ZSHENV) so \$$ENV_VAR is exported.
     Claude Code must be launched from a shell that sources ~/.zshenv —
     otherwise \${$ENV_VAR} in .mcp.json expands to nothing.
  2. Start Claude Code in the repo:  cd $REPO_ROOT && claude
  3. Inside the session run  /mcp  and confirm "$SERVER_NAME" is connected
     (expect ~39 tools). Details:  claude mcp get $SERVER_NAME
  4. Re-verify any time:  $0 --check
EOF

exit $(( FAILURES > 0 ? 1 : 0 ))
