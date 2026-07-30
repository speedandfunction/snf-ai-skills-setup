#!/usr/bin/env bash
#
# n8n-mcp-global-setup.sh — install & verify the n8n-mcp server for Claude Code
#                           at the USER (global) scope on macOS.
#
# Unlike a project-level `.mcp.json` entry, a user-scope server is available in
# EVERY project you open with Claude Code. It is registered via
# `claude mcp add --scope user` and stored in ~/.claude.json.
#
# What it does:
#   1. Checks prerequisites (macOS, Homebrew, Node/npx, Claude Code CLI, login shell).
#      Missing pieces are offered as Homebrew installs — Claude Code via
#      `brew install --cask claude-code`.
#   2. Asks for the n8n API key (hidden input) and stores it in ~/.zshenv as
#      `export SNF_N8N_API_KEY=...` (idempotent — an existing line is replaced).
#   3. Registers the `n8n` server at user scope with
#      `claude mcp add n8n --scope user ... -- npx -y n8n-mcp`.
#      The key is stored as the reference ${SNF_N8N_API_KEY}, never in plaintext —
#      Claude Code expands it from the environment at launch.
#   4. Verifies: env var resolves, n8n REST API answers with the key,
#      `npx n8n-mcp` starts, and `claude mcp list` reports the server connected.
#
# No jq required — everything goes through the `claude mcp` CLI. Needs only what
# macOS provides (bash 3.2, curl, sed/grep). Safe to re-run: every step is idempotent.
#
# Usage:
#   ./n8n-mcp-global-setup.sh                 # full install (interactive)
#   ./n8n-mcp-global-setup.sh --check         # verification only, no changes
#   ./n8n-mcp-global-setup.sh --url https://n8n.example.com
#   ./n8n-mcp-global-setup.sh --force         # re-register even if it already exists
#   ./n8n-mcp-global-setup.sh --key KEY --yes # non-interactive
#   echo KEY | ./n8n-mcp-global-setup.sh --yes
#
set -euo pipefail

# ---------------------------------------------------------------- configuration
SERVER_NAME="n8n"
ENV_VAR="SNF_N8N_API_KEY"
N8N_API_URL="https://n8n.gluzdov.com"
ZSHENV="$HOME/.zshenv"

CHECK_ONLY=0
FORCE=0
CLI_KEY=""
ASSUME_YES=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --check)          CHECK_ONLY=1; shift ;;
    --force|--force-key) FORCE=1; shift ;;
    --key)            CLI_KEY="${2:?--key needs a value}"; shift 2 ;;
    --yes|-y)         ASSUME_YES=1; shift ;;
    --url)            N8N_API_URL="${2:?--url needs a value}"; shift 2 ;;
    -h|--help)        sed -n '2,33p' "$0"; exit 0 ;;
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

# ------------------------------------------------------------- 1. prerequisites
info "Checking prerequisites"

[[ "$(uname -s)" == "Darwin" ]] || die "This script targets macOS (found $(uname -s))."
ok "macOS $(sw_vers -productVersion)"

if command -v brew >/dev/null 2>&1; then
  ok "Homebrew $(brew --version | head -1 | awk '{print $2}')"
  HAS_BREW=1
else
  HAS_BREW=0
  # Installed but not on PATH yet? Add it for this run.
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
  # Decide whether we need to obtain/replace the key. --key always replaces;
  # otherwise an existing key is kept (--force re-registers the server, not the key).
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
    # drop any previous line for this var, then append the new one
    grep -vE "^[[:space:]]*export[[:space:]]+$ENV_VAR=" "$ZSHENV" > "$ZSHENV.tmp" || true
    mv "$ZSHENV.tmp" "$ZSHENV"; chmod 600 "$ZSHENV"
    printf '\n# n8n MCP (%s)\nexport %s="%s"\n' "$N8N_API_URL" "$ENV_VAR" "$NEW_KEY" >> "$ZSHENV"
    ok "key written to $ZSHENV (backup kept alongside)"
    API_KEY="$NEW_KEY"; export "$ENV_VAR=$NEW_KEY"
  fi
fi

# --------------------------------------------------- 3. register at user scope
info "Registering \"$SERVER_NAME\" MCP server at user (global) scope"

if [[ $CHECK_ONLY -eq 1 ]]; then
  if claude mcp get "$SERVER_NAME" >/dev/null 2>&1; then
    ok "\"$SERVER_NAME\" is registered"
    claude mcp get "$SERVER_NAME" 2>/dev/null \
      | grep -iE 'scope|command|args|N8N_API_URL|MCP_MODE' | sed 's/^/     /' || true
    # If jq + ~/.claude.json available, confirm the key is a reference, not plaintext.
    if command -v jq >/dev/null 2>&1 && [[ -f "$HOME/.claude.json" ]]; then
      kref="$(jq -r --arg n "$SERVER_NAME" '.mcpServers[$n].env.N8N_API_KEY // empty' "$HOME/.claude.json" 2>/dev/null)"
      case "$kref" in
        '${'*'}') ok "N8N_API_KEY stored as env reference ($kref) — no plaintext secret" ;;
        "")       : ;;  # not at user scope in ~/.claude.json; nothing to assert
        *)        bad "N8N_API_KEY looks like a literal value in ~/.claude.json — re-run without --check to fix" ;;
      esac
    fi
  else
    bad "\"$SERVER_NAME\" is not registered (run without --check to add it)"
  fi
else
  if claude mcp get "$SERVER_NAME" >/dev/null 2>&1; then
    if [[ $FORCE -eq 1 ]]; then
      claude mcp remove "$SERVER_NAME" --scope user >/dev/null 2>&1 \
        || claude mcp remove "$SERVER_NAME" >/dev/null 2>&1 || true
      ok "removed existing \"$SERVER_NAME\" registration (--force)"
    else
      ok "\"$SERVER_NAME\" already registered — use --force to re-register"
    fi
  fi

  if ! claude mcp get "$SERVER_NAME" >/dev/null 2>&1; then
    # NOTE: single-quote the key env so the shell does NOT expand ${SNF_N8N_API_KEY};
    # Claude Code stores the literal reference and expands it at launch time.
    claude mcp add "$SERVER_NAME" --scope user \
      -e MCP_MODE=stdio \
      -e LOG_LEVEL=error \
      -e DISABLE_CONSOLE_OUTPUT=true \
      -e "N8N_API_URL=$N8N_API_URL" \
      -e 'N8N_API_KEY=${'"$ENV_VAR"'}' \
      -- npx -y n8n-mcp \
      && ok "registered \"$SERVER_NAME\" at user scope (key referenced as \${$ENV_VAR})" \
      || die "\`claude mcp add\` failed."
  fi
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
    401|403) bad "n8n API rejected the key (HTTP $HTTP_CODE) — regenerate it and re-run with --force" ;;
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
  elif npx -y n8n-mcp --help >/dev/null 2>&1; then
    ok "n8n-mcp resolves and starts via npx"
  else
    bad "\`npx -y n8n-mcp\` failed — check network / npm registry access"
  fi
fi

# 4c. Claude Code sees the server
if command -v claude >/dev/null 2>&1; then
  if MCP_LIST="$(claude mcp list 2>&1)"; then
    LINE="$(grep -iE "(^|[[:space:]/])$SERVER_NAME:" <<<"$MCP_LIST" | head -1)"
    if [[ -n "$LINE" ]]; then
      ok "\`claude mcp list\` reports \"$SERVER_NAME\""
      echo "     ${LINE#"${LINE%%[![:space:]]*}"}"
    else
      warn "\"$SERVER_NAME\" not listed yet — restart Claude Code to pick it up"
    fi
  else
    warn "\`claude mcp list\` failed:"; sed 's/^/     /' <<<"$MCP_LIST"
  fi
fi

# ------------------------------------------------------------------ 5. summary
echo
if [[ $FAILURES -eq 0 ]]; then
  printf '%s✓ n8n MCP is set up globally (user scope).%s\n' "$GRN$BOLD" "$RST"
else
  printf '%s✗ %d check(s) failed — see above.%s\n' "$RED$BOLD" "$FAILURES" "$RST"
fi

cat <<EOF

${BOLD}Next steps${RST}
  1. Open a NEW terminal (or run: source $ZSHENV) so \$$ENV_VAR is exported.
     Claude Code must be launched from a shell that sources ~/.zshenv —
     otherwise \${$ENV_VAR} expands to nothing and the server fails auth.
  2. Start Claude Code in ANY project:  claude
  3. Inside the session run  /mcp  and confirm "$SERVER_NAME" is connected
     (expect ~39 tools). Details:  claude mcp get $SERVER_NAME
  4. Re-verify any time:  $(basename "$0") --check
  5. To remove it later:  claude mcp remove $SERVER_NAME --scope user
EOF

exit $(( FAILURES > 0 ? 1 : 0 ))
