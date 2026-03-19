#!/usr/bin/env bash
set -euo pipefail

CODEX_DIR="${HOME}/.codex"
NVM_DIR="${NVM_DIR:-${HOME}/.nvm}"
MANAGED_START="# >>> codex-installer >>>"
MANAGED_END="# <<< codex-installer <<<"

log_step() {
  printf '[STEP] %s\n' "$1"
}

log_info() {
  printf '[INFO] %s\n' "$1"
}

log_warn() {
  printf '[WARN] %s\n' "$1" >&2
}

log_ok() {
  printf '[ OK ] %s\n' "$1"
}

command_exists() {
  command -v "$1" >/dev/null 2>&1
}

# Remove the managed block (between MANAGED_START and MANAGED_END) from a file
remove_managed_block() {
  local file="$1"
  [[ -f "$file" ]] || return 0

  local tmp
  tmp="$(mktemp)"
  awk -v s="$MANAGED_START" -v e="$MANAGED_END" '
    $0 == s { skip=1; next }
    $0 == e { skip=0; next }
    !skip   { print }
  ' "$file" >"$tmp"

  mv "$tmp" "$file"
  log_info "Cleaned managed block from $file"
}

# Remove a specific line pattern from a file
remove_line_pattern() {
  local file="$1"
  local pattern="$2"
  [[ -f "$file" ]] || return 0

  local tmp
  tmp="$(mktemp)"
  grep -v "$pattern" "$file" >"$tmp" || true
  mv "$tmp" "$file"
}

# ── Step 1: Uninstall @openai/codex npm package ──────────────────────────────
uninstall_codex() {
  log_step "1/5 Uninstall @openai/codex"

  # load nvm if present so that npm/node are on PATH
  if [[ -s "${NVM_DIR}/nvm.sh" ]]; then
    # shellcheck disable=SC1090
    . "${NVM_DIR}/nvm.sh"
  fi

  if command_exists npm; then
    npm uninstall -g @openai/codex 2>/dev/null || true
    # also clean up the wrong "codex" package if it was installed by mistake
    npm uninstall -g codex 2>/dev/null || true
    log_ok "@openai/codex removed"
  else
    log_warn "npm not found — skipping npm uninstall"
  fi
}

# ── Step 2: Remove ~/.codex directory (config, auth, env) ────────────────────
remove_codex_config() {
  log_step "2/5 Remove Codex config directory"

  if [[ -d "$CODEX_DIR" ]]; then
    rm -rf "$CODEX_DIR"
    log_ok "Removed $CODEX_DIR"
  else
    log_info "$CODEX_DIR does not exist — nothing to remove"
  fi
}

# ── Step 3: Uninstall nvm and all Node.js versions managed by nvm ────────────
uninstall_nvm() {
  log_step "3/5 Uninstall nvm and nvm-managed Node.js"

  if [[ -d "$NVM_DIR" ]]; then
    rm -rf "$NVM_DIR"
    log_ok "Removed $NVM_DIR"
  else
    log_info "$NVM_DIR does not exist — skipping"
  fi
}

# ── Step 4: Remove npm user-prefix directory and profile script ──────────────
remove_npm_global() {
  log_step "4/5 Remove npm user-prefix directory"

  if [[ -d "${HOME}/.npm-global" ]]; then
    rm -rf "${HOME}/.npm-global"
    log_ok "Removed ~/.npm-global"
  else
    log_info "~/.npm-global does not exist — skipping"
  fi

  # profile.d script written by ensure_npm_user_prefix
  local profile_script="${HOME}/.profile.d/npm-global.sh"
  if [[ -f "$profile_script" ]]; then
    rm -f "$profile_script"
    log_ok "Removed $profile_script"
  fi

  # remove npm cache
  if [[ -d "${HOME}/.npm" ]]; then
    rm -rf "${HOME}/.npm"
    log_ok "Removed ~/.npm (npm cache)"
  fi

  # remove user .npmrc (prefix / registry settings written by installer)
  if [[ -f "${HOME}/.npmrc" ]]; then
    rm -f "${HOME}/.npmrc"
    log_ok "Removed ~/.npmrc"
  fi
}

# ── Step 5: Clean shell rc files ─────────────────────────────────────────────
clean_shell_rc() {
  log_step "5/5 Clean shell profile files"

  # remove codex-installer managed blocks from .bashrc / .zshrc
  remove_managed_block "${HOME}/.bashrc"
  remove_managed_block "${HOME}/.zshrc"

  # remove npm-global PATH lines added to .bashrc
  if [[ -f "${HOME}/.bashrc" ]]; then
    remove_line_pattern "${HOME}/.bashrc" '\.npm-global/bin'
    remove_line_pattern "${HOME}/.bashrc" '# ensure npm global bin in PATH'
    log_info "Cleaned npm-global PATH entries from ~/.bashrc"
  fi

  # remove nvm-injected lines from .bashrc / .zshrc / .profile / .bash_profile
  for rc in "${HOME}/.bashrc" "${HOME}/.zshrc" "${HOME}/.profile" "${HOME}/.bash_profile"; do
    [[ -f "$rc" ]] || continue
    remove_line_pattern "$rc" 'NVM_DIR'
    remove_line_pattern "$rc" 'nvm.sh'
    remove_line_pattern "$rc" 'nvm/bash_completion'
    log_info "Cleaned nvm entries from $rc"
  done

  log_ok "Shell profiles cleaned"
}

# ── Summary ──────────────────────────────────────────────────────────────────
print_summary() {
  cat <<'EOF'

Uninstall complete. The following were removed:
  - @openai/codex (npm global package)
  - ~/.codex/          (config, auth.json, config.toml, env.sh)
  - ~/.nvm/            (nvm + all nvm-managed Node.js versions)
  - ~/.npm-global/     (npm user-prefix directory)
  - ~/.npm/            (npm cache)
  - ~/.npmrc           (npm user config)
  - Shell profile entries added by codex-installer and nvm

Please open a new terminal session (or run "exec bash") to apply changes.
EOF
}

usage() {
  cat <<'EOF'
Uninstall Codex and Node.js (nvm) installed by codex-installer.

Usage:
  bash uninstall.sh [-y|--yes]

Options:
  -y, --yes    Skip confirmation prompt
  -h, --help   Show this help
EOF
}

main() {
  local skip_confirm=false
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -y|--yes) skip_confirm=true; shift ;;
      -h|--help) usage; exit 0 ;;
      *) printf '[ERR ] Unknown argument: %s\n' "$1" >&2; usage; exit 1 ;;
    esac
  done

  if [[ "$skip_confirm" != true ]]; then
    printf 'This will uninstall Codex, nvm, Node.js (nvm-managed), and remove related config.\n'
    printf 'Continue? [y/N] '
    read -r answer
    case "$answer" in
      [yY]|[yY][eE][sS]) ;;
      *) printf 'Aborted.\n'; exit 0 ;;
    esac
  fi

  uninstall_codex
  remove_codex_config
  uninstall_nvm
  remove_npm_global
  clean_shell_rc
  print_summary
}

main "$@"
