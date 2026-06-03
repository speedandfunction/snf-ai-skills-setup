#!/usr/bin/env bash
#
# setup-snf.sh — automatic installation of tools from the
#                "Claude Skills — Getting Started" guide (Speed & Function).
#
# Installs: Claude Desktop, Git, GitHub CLI (gh), Node.js (LTS),
# generates an SSH key, adds it to GitHub, authenticates gh, and clones the repo.
#
# Supports:
#   • macOS    — via Homebrew
#   • Windows  — via winget (run in Git Bash / MSYS2 / WSL)
#
# Usage:
#   chmod +x setup-snf.sh && ./setup-snf.sh
#
set -euo pipefail

# ────────────────────────────── Configuration ─────────────────────────────
REPO_SSH="git@github.com:speedandfunction/snf-ai-skills.git"
REPO_DIR="snf-ai-skills"
SSH_KEY="$HOME/.ssh/id_ed25519"
GIT_EMAIL="${GIT_EMAIL:-}"   # can be preset: GIT_EMAIL=you@speedandfunction.com ./setup-snf.sh

# ──────────────────────────────── Logging ─────────────────────────────────
if [ -t 1 ]; then
  C_BLUE="\033[1;34m"; C_GREEN="\033[1;32m"; C_YELLOW="\033[1;33m"
  C_RED="\033[1;31m"; C_RESET="\033[0m"
else
  C_BLUE=""; C_GREEN=""; C_YELLOW=""; C_RED=""; C_RESET=""
fi
log()  { printf "${C_BLUE}==>${C_RESET} %s\n" "$*"; }
ok()   { printf "${C_GREEN} ✔ ${C_RESET} %s\n" "$*"; }
warn() { printf "${C_YELLOW} ! ${C_RESET} %s\n" "$*"; }
err()  { printf "${C_RED} ✘ ${C_RESET} %s\n" "$*" >&2; }
has()  { command -v "$1" >/dev/null 2>&1; }

# ─────────────────────────── OS detection ─────────────────────────────────
detect_os() {
  case "$(uname -s)" in
    Darwin) echo "mac" ;;
    Linux)
      if grep -qiE "(microsoft|wsl)" /proc/version 2>/dev/null; then echo "wsl"; else echo "linux"; fi ;;
    MINGW*|MSYS*|CYGWIN*) echo "windows" ;;
    *) echo "unknown" ;;
  esac
}
OS="$(detect_os)"

# ──────────────────────────── macOS: Homebrew ─────────────────────────────
ensure_brew() {
  if ! has brew; then
    log "Homebrew not found — installing…"
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    # Add brew to PATH for the current session (Apple Silicon vs Intel)
    if [ -x /opt/homebrew/bin/brew ]; then eval "$(/opt/homebrew/bin/brew shellenv)"
    elif [ -x /usr/local/bin/brew ]; then eval "$(/usr/local/bin/brew shellenv)"; fi
  fi
  ok "Homebrew is ready"
}
# install_formula <command> <brew-formula>
# Skips if the command is already available anywhere in PATH (e.g. Node installed
# via the .pkg installer or nvm), otherwise installs via Homebrew.
install_formula() {
  local cmd="$1" formula="$2"
  if has "$cmd"; then ok "$cmd already available ($(command -v "$cmd")) — skipping"; return; fi
  brew list --formula "$formula" >/dev/null 2>&1 && ok "$formula already installed" || brew install "$formula"
}
brew_cask() { brew list --cask "$1" >/dev/null 2>&1 && ok "$1 already installed" || brew install --cask "$1"; }

install_mac() {
  ensure_brew
  log "Installing Git, GitHub CLI, Node.js (LTS)…"
  install_formula git  git
  install_formula gh   gh
  install_formula node node
  log "Installing Claude Desktop…"
  brew_cask claude || warn "Could not install Claude via brew — download manually: https://claude.ai/download"
}

# ──────────────────────────── Windows: winget ─────────────────────────────
# winget_install <winget-id> [command]
# If [command] is given and already in PATH, skips (e.g. Node installed manually).
winget_install() {
  local id="$1" cmd="${2:-}"
  if [ -n "$cmd" ] && has "$cmd"; then ok "$cmd already available — skipping"; return; fi
  if winget list --id "$id" -e >/dev/null 2>&1; then
    ok "$id already installed"
  else
    winget install --id "$id" -e --silent \
      --accept-package-agreements --accept-source-agreements
  fi
}

install_windows() {
  if ! has winget; then
    err "winget not found. Update App Installer from the Microsoft Store, or install the tools manually per the guide."
    exit 1
  fi
  log "Installing Git, GitHub CLI, Node.js (LTS), Claude Desktop via winget…"
  winget_install Git.Git           git
  winget_install GitHub.cli        gh
  winget_install OpenJS.NodeJS.LTS node
  winget_install Anthropic.Claude || warn "Claude not found via winget — download manually: https://claude.ai/download"
  warn "Restart your terminal after installation so PATH is refreshed."
}

# ─────────────────────────────── SSH key ──────────────────────────────────
setup_ssh_key() {
  if [ -f "${SSH_KEY}.pub" ]; then
    ok "SSH key already exists: ${SSH_KEY}.pub"
    return
  fi
  log "No SSH key found — generating a new one…"
  if [ -z "$GIT_EMAIL" ]; then
    read -rp "   Enter the email for the key (e.g. you@speedandfunction.com): " GIT_EMAIL
  fi
  mkdir -p "$HOME/.ssh"
  ssh-keygen -t ed25519 -C "$GIT_EMAIL" -f "$SSH_KEY" -N ""
  ok "Generated: ${SSH_KEY}.pub"
}

# ──────────────────── GitHub: auth + key ──────────────────────────────────
setup_github() {
  if ! has gh; then warn "gh is not in PATH yet — skipping auth. Restart the terminal and run the script again."; return; fi

  if gh auth status >/dev/null 2>&1; then
    ok "GitHub CLI already authenticated"
  else
    log "Authenticating with GitHub (choose GitHub.com → SSH → via browser)…"
    gh auth login
  fi

  log "Adding the SSH key to GitHub…"
  gh ssh-key add "${SSH_KEY}.pub" --title "$(hostname) ($(date +%Y-%m-%d))" \
    && ok "Key added" \
    || warn "Key is probably already added — skipping."
}

# ─────────────────────────── Clone repository ─────────────────────────────
clone_repo() {
  if [ -d "$REPO_DIR/.git" ]; then
    ok "Repository already cloned into ./$REPO_DIR"
  else
    log "Cloning git@github.com:speedandfunction/snf-ai-skills.git…"
    git clone "git@github.com:speedandfunction/snf-ai-skills.git" "snf-ai-skills" \
      && ok "Done. Open the ./$REPO_DIR folder in Claude Code." \
      || err "Clone failed. Check access to the 'speedandfunction' org and your SSH key."
  fi
}

# ──────────────────────────────── Verify ──────────────────────────────────
verify() {
  log "Checking versions:"
  for c in git gh node; do
    if has "$c"; then printf "    %-6s %s\n" "$c" "$($c --version 2>&1 | head -n1)"; else warn "$c not in PATH (restart the terminal)"; fi
  done
}

# ─────────────────────────────────── Main ─────────────────────────────────
main() {
  log "Detected OS: ${OS}"
  case "$OS" in
    mac)     install_mac ;;
    windows) install_windows ;;
    wsl|linux)
      err "This guide targets macOS and Windows. For WSL/Linux install git, gh, node manually (apt) — Claude Desktop is Windows/Mac only."
      exit 1 ;;
    *)
      err "Unknown OS. Only macOS and Windows are supported."
      exit 1 ;;
  esac

  setup_ssh_key
  setup_github
  clone_repo
  verify

  echo
  ok "Setup complete 🎉"
  echo "    Next: open Claude Desktop → Claude Code mode → open the ./$REPO_DIR folder"
  echo "    and connect the connectors: ClickUp, Gmail, Google Calendar/Docs/Sheets."
}

main "$@"