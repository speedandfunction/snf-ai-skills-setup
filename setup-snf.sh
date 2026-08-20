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
#   bash <(curl -fsSL https://raw.githubusercontent.com/speedandfunction/snf-ai-skills-setup/main/setup-snf.sh)
#
#   NOTE: use `bash <(curl ...)`, NOT `curl ... | bash` — the script asks questions
#   and needs a real terminal on stdin.
#
# Optional environment overrides:
#   GIT_EMAIL=you@speedandfunction.com   # skip the email prompt
#   TARGET_DIR=/path/to/checkout         # default: $HOME/snf-ai-skills
#
set -euo pipefail

# ────────────────────────────── Configuration ─────────────────────────────
REPO_SSH="git@github.com:speedandfunction/snf-ai-skills.git"
REPO_ORG="speedandfunction"
SSH_KEY="$HOME/.ssh/id_ed25519"
GIT_EMAIL="${GIT_EMAIL:-}"
TARGET_DIR="${TARGET_DIR:-$HOME/snf-ai-skills}"

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

# Hard stop with an actionable message. Never leave the user guessing.
die() { err "$*"; echo >&2; err "Setup did NOT complete. Fix the above and re-run — the script is idempotent."; exit 1; }

# Any unhandled failure reports where it happened instead of exiting silently.
trap 'rc=$?; err "Unexpected failure at line ${LINENO} (exit ${rc})."; err "Re-run the script — it is safe to run repeatedly."' ERR

# Guard every interactive prompt: `curl ... | bash` gives us a pipe on stdin,
# `read` then returns non-zero and set -e kills the script with no explanation.
need_tty() {
  [ -t 0 ] && return 0
  err "stdin is not a terminal, so this step cannot ask you anything."
  err "Run it like this instead:"
  err "    bash <(curl -fsSL https://raw.githubusercontent.com/speedandfunction/snf-ai-skills-setup/main/setup-snf.sh)"
  die  "(the '$(printf 'curl ... | bash')' form does not work here)"
}

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
brew_shellenv_path() {
  if   [ -x /opt/homebrew/bin/brew ]; then echo /opt/homebrew/bin/brew
  elif [ -x /usr/local/bin/brew   ]; then echo /usr/local/bin/brew
  else echo ""; fi
}

# Homebrew's installer does NOT touch your shell profile. Without this, every new
# terminal can lose brew/gh/node from PATH and the guide's later steps "mysteriously"
# fail. Only writes when nothing already puts Homebrew on PATH, so it never duplicates.
brew_on_path_persistently() {
  local brew_bin bin_dir f
  brew_bin="$(brew_shellenv_path)"; [ -n "$brew_bin" ] || return 0
  bin_dir="$(dirname "$brew_bin")"
  # System-wide: /etc/paths and /etc/paths.d/*
  grep -qxF "$bin_dir" /etc/paths /etc/paths.d/* 2>/dev/null && return 0
  # Per-user shell startup files
  for f in "$HOME/.zprofile" "$HOME/.zshrc" "$HOME/.zshenv" "$HOME/.bash_profile" "$HOME/.profile"; do
    [ -e "$f" ] || continue
    grep -qE "brew shellenv|${bin_dir//\//\\/}" "$f" 2>/dev/null && return 0
  done
  return 1
}

persist_brew_shellenv() {
  local brew_bin line
  brew_bin="$(brew_shellenv_path)"; [ -n "$brew_bin" ] || return 0
  if brew_on_path_persistently; then
    ok "Homebrew is already on PATH for new terminals"
    return
  fi
  line="eval \"\$(${brew_bin} shellenv)\""
  printf '\n# Added by setup-snf.sh — put Homebrew on PATH\n%s\n' "$line" >> "$HOME/.zprofile"
  ok "Added Homebrew to PATH in $HOME/.zprofile"
}

ensure_brew() {
  if ! has brew; then
    log "Homebrew not found — installing…"
    need_tty  # the Homebrew installer asks for your sudo password
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" \
      || die "Homebrew install failed. Install it manually from https://brew.sh and re-run this script."
    local brew_bin; brew_bin="$(brew_shellenv_path)"
    [ -n "$brew_bin" ] || die "Homebrew installed but 'brew' is not at /opt/homebrew or /usr/local. Open a new terminal and re-run."
    eval "$("$brew_bin" shellenv)"
    hash -r 2>/dev/null || true
  fi
  persist_brew_shellenv
  ok "Homebrew is ready"
}

# install_formula <command> <brew-formula>
install_formula() {
  local cmd="$1" formula="$2"
  if has "$cmd"; then ok "$cmd already available ($(command -v "$cmd")) — skipping"; return; fi
  if brew list --formula "$formula" >/dev/null 2>&1; then
    ok "$formula already installed"
  else
    brew install "$formula" || die "brew install $formula failed. Run 'brew doctor', then re-run this script."
  fi
  hash -r 2>/dev/null || true
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
    die "winget not found. Update App Installer from the Microsoft Store, or install the tools manually per the guide."
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
  else
    log "No SSH key found — generating a new one…"
    if [ -z "$GIT_EMAIL" ]; then
      need_tty
      read -rp "   Enter the email for the key (e.g. you@speedandfunction.com): " GIT_EMAIL \
        || die "Could not read the email. Re-run with: GIT_EMAIL=you@speedandfunction.com bash <(curl -fsSL ...)"
      [ -n "$GIT_EMAIL" ] || die "Email must not be empty."
    fi
    mkdir -p "$HOME/.ssh"; chmod 700 "$HOME/.ssh"
    ssh-keygen -t ed25519 -C "$GIT_EMAIL" -f "$SSH_KEY" -N "" \
      || die "ssh-keygen failed. Check that $HOME/.ssh is writable."
    ok "Generated: ${SSH_KEY}.pub"
  fi

  # macOS: load into the agent + keychain so git never prompts.
  if [ "$OS" = "mac" ]; then
    ssh-add --apple-use-keychain "$SSH_KEY" >/dev/null 2>&1 \
      || ssh-add "$SSH_KEY" >/dev/null 2>&1 \
      || warn "Could not add the key to ssh-agent (harmless — git reads $SSH_KEY directly)."
  fi
}

# Pre-seed github.com so the first SSH connection never stops on
# "The authenticity of host 'github.com' can't be established… (yes/no)".
trust_github_host() {
  mkdir -p "$HOME/.ssh"; chmod 700 "$HOME/.ssh"
  touch "$HOME/.ssh/known_hosts"; chmod 600 "$HOME/.ssh/known_hosts"
  if ssh-keygen -F github.com >/dev/null 2>&1; then
    ok "github.com already in known_hosts"
  else
    log "Adding github.com to known_hosts…"
    ssh-keyscan -t rsa,ecdsa,ed25519 github.com >> "$HOME/.ssh/known_hosts" 2>/dev/null \
      && ok "github.com host key recorded" \
      || warn "ssh-keyscan failed — you may be asked to confirm github.com's fingerprint."
  fi
}

# ──────────────────── GitHub: auth + key ──────────────────────────────────
gh_has_key_scope() {
  gh auth status --hostname github.com 2>&1 | grep -q "admin:public_key"
}

gh_login() {
  if gh auth status --hostname github.com >/dev/null 2>&1; then
    ok "GitHub CLI already authenticated"
  else
    log "Authenticating with GitHub — a browser window will open…"
    need_tty
    # Explicit flags instead of a free-form wizard: the old interactive prompt let
    # people pick HTTPS, which silently produced a token WITHOUT admin:public_key
    # and broke the key upload two steps later.
    # --skip-ssh-key: we upload the key ourselves below, with a real success check.
    gh auth login \
      --hostname github.com \
      --git-protocol ssh \
      --scopes admin:public_key \
      --skip-ssh-key \
      --web \
      || die "GitHub login failed or was cancelled. Re-run the script to try again."
    gh auth status --hostname github.com >/dev/null 2>&1 \
      || die "GitHub login reported success but 'gh auth status' disagrees. Run 'gh auth login' manually, then re-run this script."
    ok "Authenticated with GitHub"
  fi

  if ! gh_has_key_scope; then
    log "Your token is missing the 'admin:public_key' scope — requesting it…"
    need_tty
    gh auth refresh --hostname github.com --scopes admin:public_key \
      || die "Could not add the 'admin:public_key' scope. Run: gh auth refresh -h github.com -s admin:public_key"
    gh_has_key_scope || die "Scope 'admin:public_key' still missing. Run: gh auth refresh -h github.com -s admin:public_key"
  fi
  ok "Token has the 'admin:public_key' scope"
}

# Compare against the keys already on the account instead of guessing from a
# non-zero exit code — the old code reported "probably already added" for
# genuine permission failures.
key_already_on_github() {
  local body
  body="$(awk '{print $1" "$2}' "${SSH_KEY}.pub")"
  gh api user/keys --paginate --jq '.[].key' 2>/dev/null | grep -qxF "$body"
}

upload_ssh_key() {
  if key_already_on_github; then
    ok "This SSH key is already registered on your GitHub account"
    return
  fi
  log "Adding the SSH key to GitHub…"
  local title output
  title="$(hostname -s 2>/dev/null || hostname) ($(date +%Y-%m-%d))"
  if output="$(gh ssh-key add "${SSH_KEY}.pub" --title "$title" 2>&1)"; then
    ok "Key added as \"$title\""
  else
    err "$output"
    die "Failed to add the SSH key to GitHub. Add it manually at https://github.com/settings/ssh/new — the key is:
$(cat "${SSH_KEY}.pub")"
  fi
}

# Prove the key works BEFORE cloning, so a failure names the real cause.
# 'ssh -T git@github.com' always exits 1, hence the '|| true'.
verify_github_ssh() {
  log "Verifying SSH access to GitHub…"
  local out
  out="$(ssh -o StrictHostKeyChecking=accept-new -o IdentitiesOnly=yes -i "$SSH_KEY" -T git@github.com 2>&1 || true)"
  case "$out" in
    *"successfully authenticated"*)
      ok "SSH to GitHub works ($(printf '%s' "$out" | head -n1))" ;;
    *)
      err "$out"
      die "SSH authentication to GitHub failed. Check that ${SSH_KEY}.pub is listed at https://github.com/settings/keys" ;;
  esac
}

check_org_access() {
  if gh api "repos/${REPO_ORG}/snf-ai-skills" --jq '.full_name' >/dev/null 2>&1; then
    ok "You have access to ${REPO_ORG}/snf-ai-skills"
  else
    die "Your GitHub account cannot see ${REPO_ORG}/snf-ai-skills.
Ask an org owner to invite you to the '${REPO_ORG}' organisation, accept the invite, then re-run this script."
  fi
}

# ─────────────────────────── Clone repository ─────────────────────────────
clone_repo() {
  if [ -d "$TARGET_DIR/.git" ]; then
    ok "Repository already cloned into $TARGET_DIR"
    return
  fi
  if [ -e "$TARGET_DIR" ]; then
    die "$TARGET_DIR already exists but is not a git checkout. Move or remove it, then re-run."
  fi
  log "Cloning ${REPO_SSH} into ${TARGET_DIR}…"
  git clone "$REPO_SSH" "$TARGET_DIR" \
    || die "Clone failed. Check access to the '${REPO_ORG}' org and your SSH key."
  ok "Cloned into $TARGET_DIR"
}

# ──────────────────────────────── Verify ──────────────────────────────────
verify() {
  log "Checking versions:"
  local missing=0
  for c in git gh node; do
    if has "$c"; then printf "    %-6s %s\n" "$c" "$($c --version 2>&1 | head -n1)"; else warn "$c not in PATH (open a new terminal)"; missing=1; fi
  done
  [ "$missing" -eq 0 ] || warn "Some tools are missing from this shell's PATH — open a new terminal and re-run to confirm."
}

# ─────────────────────────────────── Main ─────────────────────────────────
main() {
  log "Detected OS: ${OS}"
  case "$OS" in
    mac)     install_mac ;;
    windows) install_windows ;;
    wsl|linux)
      die "This guide targets macOS and Windows. For WSL/Linux install git, gh, node manually (apt) — Claude Desktop is Windows/Mac only." ;;
    *)
      die "Unknown OS. Only macOS and Windows are supported." ;;
  esac

  has gh || die "'gh' is not in this shell's PATH yet. Open a NEW terminal and re-run the script — it will pick up where it left off."

  setup_ssh_key
  trust_github_host
  gh_login
  upload_ssh_key
  verify_github_ssh
  check_org_access
  clone_repo
  verify

  echo
  ok "Setup complete 🎉"
  echo "    Repository: $TARGET_DIR"
  echo "    Next: open Claude Desktop → Claude Code mode → open the $TARGET_DIR folder"
  echo "    and connect the connectors: ClickUp, Gmail, Google Calendar/Docs/Sheets."
}

main "$@"
