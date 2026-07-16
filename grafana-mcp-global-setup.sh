#!/bin/bash

# ============================================================
#  Grafana MCP — macOS installer
#  Grafana Cloud: https://speedandfunction.grafana.net
#  Configures: Claude Desktop + Claude Code
#  Uses: uvx (recommended by grafana/mcp-grafana)
# ============================================================

set -e

BOLD='\033[1m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0m'

log()    { echo -e "${CYAN}▶${NC} $1"; }
ok()     { echo -e "${GREEN}✓${NC} $1"; }
warn()   { echo -e "${YELLOW}⚠${NC}  $1"; }
error()  { echo -e "${RED}✗${NC} $1"; exit 1; }
header() { echo -e "\n${BOLD}$1${NC}"; echo "────────────────────────────────────────"; }

GRAFANA_URL="https://speedandfunction.grafana.net"

# ────────────────────────────────────────
header "🔌 Grafana MCP — Installer"
echo "Grafana Cloud: ${CYAN}$GRAFANA_URL${NC}"
echo "Method:        ${CYAN}uvx (recommended)${NC}"
echo "Targets:       ${CYAN}Claude Desktop + Claude Code${NC}"
echo ""

# ── Check macOS ──────────────────────────────────────────────
if [[ "$(uname)" != "Darwin" ]]; then
  error "This script is for macOS only"
fi

# ── Install uv ───────────────────────────────────────────────
header "1/5  Checking uv"

if ! command -v uv &>/dev/null; then
  log "uv not found — installing..."
  curl -LsSf https://astral.sh/uv/install.sh | sh

  export PATH="$HOME/.local/bin:$PATH"
  [ -f "$HOME/.local/bin/env" ] && source "$HOME/.local/bin/env"

  if ! command -v uv &>/dev/null; then
    error "uv installed but not found in PATH. Open a new terminal and re-run the script."
  fi
  ok "uv installed: $(uv --version)"
else
  ok "uv: $(uv --version)"
fi

if ! command -v uvx &>/dev/null; then
  error "uvx not found. Try opening a new terminal and re-running the script."
fi

# Resolve absolute path — Claude Desktop/Code need full path
UVX_BIN="$(command -v uvx)"
ok "uvx: $UVX_BIN"

# ── Get token ────────────────────────────────────────────────
header "2/5  Service Account Token"

echo ""
echo -e "${BOLD}How to get a token for Grafana Cloud:${NC}"
echo ""
echo -e "  1. Open: ${CYAN}https://speedandfunction.grafana.net/org/serviceaccounts${NC}"
echo "  2. Click  → Add service account"
echo "  3. Name: claude-mcp   Role: Viewer (or Editor)"
echo "  4. Click  → Add service account token"
echo "  5. Copy the token (it is shown only once!)"
echo ""
echo -e "${YELLOW}Token looks like: glsa_xxxxxxxxxxxxxxxxxxxx_xxxxxxxx${NC}"
echo ""

read -rsp "$(echo -e "${BOLD}Paste token here${NC}: ")" GRAFANA_TOKEN
echo ""

if [[ -z "$GRAFANA_TOKEN" ]]; then
  error "Token cannot be empty"
fi

# ── Verify connection ────────────────────────────────────────
header "3/5  Verifying connection"

log "Testing token against $GRAFANA_URL ..."
HTTP_CODE=$(curl -s -o /tmp/grafana_check.json -w "%{http_code}" \
  -H "Authorization: Bearer $GRAFANA_TOKEN" \
  "$GRAFANA_URL/api/org" 2>/dev/null || echo "000")

if [[ "$HTTP_CODE" == "200" ]]; then
  ORG_NAME=$(python3 -c "import json; d=json.load(open('/tmp/grafana_check.json')); print(d.get('name','?'))" 2>/dev/null || echo "?")
  ok "Connection successful! Organization: ${BOLD}$ORG_NAME${NC}"
elif [[ "$HTTP_CODE" == "401" ]]; then
  warn "HTTP 401 — token is invalid or expired"
  read -rp "Continue anyway? (y/n): " CONTINUE
  [[ "$CONTINUE" != "y" ]] && exit 1
elif [[ "$HTTP_CODE" == "403" ]]; then
  warn "HTTP 403 — token is valid but lacks permissions. Check service account role."
else
  warn "HTTP $HTTP_CODE — unexpected response. Continuing..."
fi
rm -f /tmp/grafana_check.json

# ── Configure Claude Desktop ─────────────────────────────────
header "4/5  Configuring Claude Desktop"

CLAUDE_DESKTOP_DIR="$HOME/Library/Application Support/Claude"
CLAUDE_DESKTOP_CONFIG="$CLAUDE_DESKTOP_DIR/claude_desktop_config.json"
mkdir -p "$CLAUDE_DESKTOP_DIR"

if [[ -f "$CLAUDE_DESKTOP_CONFIG" ]]; then
  BACKUP="${CLAUDE_DESKTOP_CONFIG}.backup.$(date +%Y%m%d_%H%M%S)"
  cp "$CLAUDE_DESKTOP_CONFIG" "$BACKUP"
  ok "Backup saved: $BACKUP"
fi

python3 << PYEOF
import json, os

config_path   = "$CLAUDE_DESKTOP_CONFIG"
uvx_bin       = "$UVX_BIN"
grafana_url   = "$GRAFANA_URL"
grafana_token = "$GRAFANA_TOKEN"

if os.path.exists(config_path):
    with open(config_path, 'r') as f:
        try:
            config = json.load(f)
        except json.JSONDecodeError:
            config = {}
else:
    config = {}

if 'mcpServers' not in config:
    config['mcpServers'] = {}

config['mcpServers']['grafana'] = {
    "command": uvx_bin,
    "args": ["mcp-grafana"],
    "env": {
        "GRAFANA_URL": grafana_url,
        "GRAFANA_SERVICE_ACCOUNT_TOKEN": grafana_token
    }
}

with open(config_path, 'w') as f:
    json.dump(config, f, indent=2)
PYEOF

ok "Claude Desktop configured: $CLAUDE_DESKTOP_CONFIG"

# ── Configure Claude Code ────────────────────────────────────
header "5/5  Configuring Claude Code"

CLAUDE_CODE_CONFIGURED=false

# Try claude CLI first (preferred — works across all config locations)
if command -v claude &>/dev/null; then
  log "Claude Code CLI found — adding via 'claude mcp add'..."

  # Remove existing entry if present to avoid duplicates
  claude mcp remove grafana 2>/dev/null || true

  claude mcp add grafana \
    --env GRAFANA_URL="$GRAFANA_URL" \
    --env GRAFANA_SERVICE_ACCOUNT_TOKEN="$GRAFANA_TOKEN" \
    -- "$UVX_BIN" mcp-grafana

  ok "Claude Code configured via CLI"
  CLAUDE_CODE_CONFIGURED=true
fi

# Fallback: write to ~/.claude.json directly
if [[ "$CLAUDE_CODE_CONFIGURED" == false ]]; then
  log "Claude Code CLI not found — writing to ~/.claude.json directly..."

  CLAUDE_CODE_CONFIG="$HOME/.claude.json"

  python3 << PYEOF
import json, os

config_path   = os.path.expanduser("$CLAUDE_CODE_CONFIG")
uvx_bin       = "$UVX_BIN"
grafana_url   = "$GRAFANA_URL"
grafana_token = "$GRAFANA_TOKEN"

if os.path.exists(config_path):
    with open(config_path, 'r') as f:
        try:
            config = json.load(f)
        except json.JSONDecodeError:
            config = {}
else:
    config = {}

if 'mcpServers' not in config:
    config['mcpServers'] = {}

config['mcpServers']['grafana'] = {
    "command": uvx_bin,
    "args": ["mcp-grafana"],
    "env": {
        "GRAFANA_URL": grafana_url,
        "GRAFANA_SERVICE_ACCOUNT_TOKEN": grafana_token
    }
}

with open(config_path, 'w') as f:
    json.dump(config, f, indent=2)
PYEOF

  ok "Claude Code configured: $CLAUDE_CODE_CONFIG"
  CLAUDE_CODE_CONFIGURED=true
fi

# Verify Claude Code sees the MCP
if command -v claude &>/dev/null; then
  echo ""
  log "Verifying Claude Code MCP list..."
  if claude mcp list 2>/dev/null | grep -q "grafana"; then
    ok "Grafana MCP visible in Claude Code"
  else
    warn "Could not verify — run 'claude mcp list' manually to check"
  fi
fi

# ── Done ─────────────────────────────────────────────────────
echo ""
echo -e "${GREEN}${BOLD}════════════════════════════════════════${NC}"
echo -e "${GREEN}${BOLD}  ✅  Installation complete!${NC}"
echo -e "${GREEN}${BOLD}════════════════════════════════════════${NC}"
echo ""
echo -e "${BOLD}Configured:${NC}"
echo "  ✓ Claude Desktop  →  $CLAUDE_DESKTOP_CONFIG"
if command -v claude &>/dev/null; then
echo "  ✓ Claude Code     →  via 'claude mcp add'"
else
echo "  ✓ Claude Code     →  $HOME/.claude.json"
fi
echo ""
echo -e "${BOLD}Next steps:${NC}"
echo "  Claude Desktop: Quit and reopen the app"
echo "  Claude Code:    No restart needed — MCP active immediately"
echo ""
echo -e "${BOLD}Verify Claude Code:${NC}"
echo "  claude mcp list"
echo ""
echo -e "${BOLD}Try asking:${NC}"
echo "  \"Show all dashboards in Grafana\""
echo "  \"Are there any active alerts?\""
echo "  \"What datasources are configured?\""
echo ""