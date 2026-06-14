#!/bin/bash

# ============================================================
#  Grafana MCP — macOS installer (Claude Code / project-scoped)
#  Grafana Cloud: https://speedandfunction.grafana.net
#  Configures: <repo>/.mcp.json  (project-scoped MCP server)
#  Secret:     ~/.zshenv  →  SNF_GRAFANA_SERVICE_ACCOUNT_API_KEY
#              referenced from .mcp.json as
#              ${SNF_GRAFANA_SERVICE_ACCOUNT_API_KEY}
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
ENV_VAR_NAME="SNF_GRAFANA_SERVICE_ACCOUNT_API_KEY"
ZSHENV="$HOME/.zshenv"

# Project (working) directory that holds .mcp.json.
# Override by passing a path as the first argument:
#   ./install-grafana-mcp.sh /path/to/snf-ai-skills
PROJECT_DIR="${1:-$HOME/snf-ai-skills}"
MCP_JSON="$PROJECT_DIR/.mcp.json"

# ────────────────────────────────────────
header "🔌 Grafana MCP — Installer (project-scoped)"
echo "Grafana Cloud: ${CYAN}$GRAFANA_URL${NC}"
echo "Method:        ${CYAN}uvx (recommended)${NC}"
echo "Project:       ${CYAN}$PROJECT_DIR${NC}"
echo "MCP config:    ${CYAN}$MCP_JSON${NC}"
echo "Secret in:     ${CYAN}$ZSHENV${NC}  →  \$$ENV_VAR_NAME"
echo ""

# ── Check macOS ──────────────────────────────────────────────
if [[ "$(uname)" != "Darwin" ]]; then
  error "This script is for macOS only"
fi

# ── Check project dir ────────────────────────────────────────
if [[ ! -d "$PROJECT_DIR" ]]; then
  error "Project directory not found: $PROJECT_DIR
   Pass the correct path:  ./install-grafana-mcp.sh /path/to/snf-ai-skills"
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

# Confirm uvx is on PATH. We write the bare command "uvx" into .mcp.json
# (not an absolute path) so the committed config stays portable across
# machines — each user just needs uvx on their PATH.
ok "uvx: $(command -v uvx)"

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

# ── Store secret in ~/.zshenv ────────────────────────────────
header "4/5  Storing token in ~/.zshenv"

touch "$ZSHENV"

# Remove any existing export of this var (idempotent re-run)
if grep -q "^export ${ENV_VAR_NAME}=" "$ZSHENV" 2>/dev/null; then
  BACKUP="${ZSHENV}.backup.$(date +%Y%m%d_%H%M%S)"
  cp "$ZSHENV" "$BACKUP"
  ok "Backup saved: $BACKUP"
  # Use a temp file to strip the old line portably
  grep -v "^export ${ENV_VAR_NAME}=" "$ZSHENV" > "${ZSHENV}.tmp"
  mv "${ZSHENV}.tmp" "$ZSHENV"
  log "Replaced existing ${ENV_VAR_NAME} entry"
fi

printf 'export %s=%q\n' "$ENV_VAR_NAME" "$GRAFANA_TOKEN" >> "$ZSHENV"
ok "Token written to $ZSHENV as \$$ENV_VAR_NAME"

# Export into the current shell so 'claude mcp list' below can resolve it
export "${ENV_VAR_NAME}=$GRAFANA_TOKEN"

# ── Configure project .mcp.json ──────────────────────────────
header "5/5  Configuring $MCP_JSON"

if [[ -f "$MCP_JSON" ]]; then
  BACKUP="${MCP_JSON}.backup.$(date +%Y%m%d_%H%M%S)"
  cp "$MCP_JSON" "$BACKUP"
  ok "Backup saved: $BACKUP"
fi

python3 << PYEOF
import json, os

config_path = "$MCP_JSON"
grafana_url = "$GRAFANA_URL"
env_var     = "$ENV_VAR_NAME"

if os.path.exists(config_path):
    with open(config_path, 'r') as f:
        try:
            config = json.load(f)
        except json.JSONDecodeError:
            config = {}
else:
    config = {}

config.setdefault('mcpServers', {})

# The token is NOT stored here — Claude Code expands \${env_var}
# from the environment (sourced via ~/.zshenv) at launch time.
config['mcpServers']['grafana'] = {
    "command": "uvx",
    "args": ["mcp-grafana"],
    "env": {
        "GRAFANA_URL": grafana_url,
        "GRAFANA_SERVICE_ACCOUNT_TOKEN": "\${%s}" % env_var
    }
}

with open(config_path, 'w') as f:
    json.dump(config, f, indent=2)
    f.write('\n')
PYEOF

ok "Grafana MCP added to $MCP_JSON (token via \${$ENV_VAR_NAME})"

# ── Done ─────────────────────────────────────────────────────
echo ""
echo -e "${GREEN}${BOLD}════════════════════════════════════════${NC}"
echo -e "${GREEN}${BOLD}  ✅  Installation complete!${NC}"
echo -e "${GREEN}${BOLD}════════════════════════════════════════${NC}"
echo ""
echo -e "${BOLD}Configured:${NC}"
echo "  ✓ Secret      →  $ZSHENV  (\$$ENV_VAR_NAME)"
echo "  ✓ MCP server  →  $MCP_JSON  (project-scoped)"
echo ""
echo -e "${BOLD}Important:${NC}"
echo "  The token lives only in ~/.zshenv, never in .mcp.json,"
echo "  so .mcp.json is safe to commit to git."
echo ""
echo -e "${BOLD}Next steps:${NC}"
echo "  1. Open a NEW terminal (so ~/.zshenv is sourced), or run:"
echo -e "       ${CYAN}source ~/.zshenv${NC}"
echo "  2. Start Claude Code from the project directory:"
echo -e "       ${CYAN}cd \"$PROJECT_DIR\" && claude${NC}"
echo "  3. Approve the project MCP server if Claude Code prompts you."
echo ""
echo -e "${BOLD}Verify:${NC}"
echo "  claude mcp list"
echo ""
echo -e "${BOLD}Try asking:${NC}"
echo "  \"Show all dashboards in Grafana\""
echo "  \"Are there any active alerts?\""
echo "  \"What datasources are configured?\""
echo ""
