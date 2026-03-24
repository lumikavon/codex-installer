#!/usr/bin/env bash
set -euo pipefail

OPENAI_API_KEY="${OPENAI_API_KEY:-}"
OPENAI_BASE_URL="${OPENAI_BASE_URL:-}"
NPM_REGISTRY="${NPM_REGISTRY:-https://registry.npmjs.org}"

DEFAULT_OPENAI_BASE_URL="https://api.openai.com/v1"
CODEX_DIR="${HOME}/.codex"
AUTH_FILE="${CODEX_DIR}/auth.json"
CONFIG_FILE="${CODEX_DIR}/config.toml"
ENV_FILE="${CODEX_DIR}/env.sh"
MANAGED_START="# >>> codex-installer >>>"
MANAGED_END="# <<< codex-installer <<<"

usage() {
  cat <<'EOF'
Install Codex on Linux major distributions.

Usage:
  bash install-codex.sh [--openai-api-key <key>] [--openai-base-url <url>] [--npm-registry <url>]

GitHub one-line install (replace owner/repo/ref):
  curl -fsSL https://raw.githubusercontent.com/<owner>/<repo>/<ref>/install-codex.sh | bash
EOF
}

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

log_err() {
  printf '[ERR ] %s\n' "$1" >&2
}

command_exists() {
  command -v "$1" >/dev/null 2>&1
}

get_node_major() {
  local v
  v="$(node --version 2>/dev/null || true)"
  if [[ "$v" =~ ^v([0-9]+) ]]; then
    printf '%s' "${BASH_REMATCH[1]}"
  else
    printf '0'
  fi
}

ensure_npm_user_prefix() {
  # When nvm is managing Node.js, do NOT set a custom prefix — nvm handles
  # global installs itself and a conflicting prefix in ~/.npmrc breaks PATH.
  if [[ -n "${NVM_DIR:-}" ]] && [[ -s "${NVM_DIR}/nvm.sh" ]]; then
    log_info "nvm detected — skipping npm prefix override (nvm manages globals)"
    return 0
  fi

  mkdir -p "${HOME}/.npm-global/bin"
  npm config set prefix "${HOME}/.npm-global" --location=user >/dev/null 2>&1 || \
    npm config set prefix "${HOME}/.npm-global" >/dev/null 2>&1 || true
  # always ensure the npm-global bin directory is in PATH for future shells
  export PATH="${HOME}/.npm-global/bin:${PATH}"

  # write a profile.d script so that login shells see it automatically
  local profile_script="${HOME}/.profile.d/npm-global.sh"
  mkdir -p "$(dirname "$profile_script")"
  cat >"$profile_script" <<'EOF'
# added by codex-installer
export PATH="$HOME/.npm-global/bin:$PATH"
EOF
  chmod 644 "$profile_script" 2>/dev/null || true

  # also update bashrc if present
  if [[ -f "${HOME}/.bashrc" ]]; then
    if ! grep -q '\.npm-global/bin' "${HOME}/.bashrc"; then
      cat >>"${HOME}/.bashrc" <<'EOF'
# ensure npm global bin in PATH
export PATH="$HOME/.npm-global/bin:$PATH"
EOF
    fi
  fi
}

install_nodejs() {
  log_step "1/5 Install Node.js"

  # if node is present and high enough version, we're done
  if command_exists node && command_exists npm; then
    local major
    major="$(get_node_major)"
    if [[ -n "$major" && "$major" -ge 24 ]]; then
      ensure_npm_user_prefix
      npm config set registry "$NPM_REGISTRY" --location=global >/dev/null 2>&1 || npm config set registry "$NPM_REGISTRY" -g >/dev/null 2>&1 || true
      log_ok "Node.js ready: $(node --version) / npm $(npm --version)"
      return 0
    fi
    log_warn "Existing Node.js is too old: $(node --version). Need >= 24."
  fi

  # try installing via package manager first (may still be old)
  local sudo_cmd=""
  if [[ "$(id -u)" -ne 0 ]] && command_exists sudo; then
    sudo_cmd="sudo"
  fi

  if command_exists apt-get; then
    ${sudo_cmd} apt-get update
    ${sudo_cmd} apt-get install -y nodejs npm
  elif command_exists dnf; then
    ${sudo_cmd} dnf install -y nodejs npm
  elif command_exists yum; then
    ${sudo_cmd} yum install -y nodejs npm
  elif command_exists zypper; then
    ${sudo_cmd} zypper --non-interactive install -y nodejs npm
  elif command_exists pacman; then
    ${sudo_cmd} pacman -Sy --noconfirm nodejs npm
  else
    log_warn "No supported package manager detected."
  fi

  # if after package manager node is still missing or <24 use nvm to install/replace
  if ! command_exists node || ! command_exists npm || [[ "$(get_node_major)" -lt 24 ]]; then
    log_info "Installing Node.js >=24 with nvm and replacing existing installation"
    if ! command_exists curl; then
      log_err "curl is required to install nvm."
      exit 1
    fi

    export NVM_DIR="${HOME}/.nvm"
    if [[ ! -s "${NVM_DIR}/nvm.sh" ]]; then
      curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh | bash
    fi

    # shellcheck disable=SC1090
    . "${NVM_DIR}/nvm.sh"
    nvm install 24
    nvm alias default 24
  fi

  if ! command_exists node || ! command_exists npm; then
    log_err "Node.js/npm not found after installation."
    exit 1
  fi

  if [[ "$(get_node_major)" -lt 24 ]]; then
    log_err "Node.js major version is still < 24."
    exit 1
  fi

  ensure_npm_user_prefix
  npm config set registry "$NPM_REGISTRY" --location=global >/dev/null 2>&1 || npm config set registry "$NPM_REGISTRY" -g >/dev/null 2>&1 || true
  log_ok "Node.js ready: $(node --version) / npm $(npm --version)"
}

install_codex() {
  log_step "2/5 Install Codex"
  npm install -g @openai/codex --registry="$NPM_REGISTRY"

  if command_exists codex; then
    log_ok "Codex installed: $(codex --version)"
  else
    log_warn "codex command is not visible in current shell. Reopen terminal and retry."
  fi
}

prompt_openai() {
  log_step "3/5 Prompt OPENAI_BASE_URL and OPENAI_API_KEY"

  if [[ -z "$OPENAI_BASE_URL" ]]; then
    local entered_base
    read -r -p "OPENAI_BASE_URL [${DEFAULT_OPENAI_BASE_URL}]: " entered_base
    OPENAI_BASE_URL="${entered_base:-$DEFAULT_OPENAI_BASE_URL}"
  fi

  if [[ -z "$OPENAI_API_KEY" ]]; then
    read -r -s -p "OPENAI_API_KEY: " OPENAI_API_KEY
    echo
  fi

  if [[ -z "$OPENAI_API_KEY" ]]; then
    log_err "OPENAI_API_KEY cannot be empty."
    exit 1
  fi
}

escape_single() {
  printf '%s' "$1" | sed "s/'/'\"'\"'/g"
}

upsert_block() {
  local file="$1"
  local start="$2"
  local end="$3"
  local payload tmp
  payload="$(cat)"

  mkdir -p "$(dirname "$file")"
  [[ -f "$file" ]] || touch "$file"

  tmp="$(mktemp)"
  awk -v s="$start" -v e="$end" '
    $0 == s {skip=1; next}
    $0 == e {skip=0; next}
    !skip {print}
  ' "$file" >"$tmp"

  {
    if [[ -s "$tmp" ]]; then
      cat "$tmp"
      echo
    fi
    echo "$start"
    printf '%s\n' "$payload"
    echo "$end"
  } >"$file"

  rm -f "$tmp"
}

ensure_shell_profile_sources_env() {
  local source_line='[ -f "$HOME/.codex/env.sh" ] && source "$HOME/.codex/env.sh"'

  upsert_block "${HOME}/.bashrc" "$MANAGED_START" "$MANAGED_END" <<EOF
$source_line
EOF

  if [[ -f "${HOME}/.zshrc" || "${SHELL:-}" == *"zsh"* ]]; then
    upsert_block "${HOME}/.zshrc" "$MANAGED_START" "$MANAGED_END" <<EOF
$source_line
EOF
  fi
}

write_codex_config() {
  log_step "4/5 Configure Codex"

  mkdir -p "$CODEX_DIR"

  # write auth.json exactly as required
  cat >"$AUTH_FILE" <<EOF
{
  "OPENAI_API_KEY": "${OPENAI_API_KEY}"
}
EOF

  cat >"$CONFIG_FILE" <<EOF
model_provider = "aicodemirror"
model = "gpt-5.4"
model_reasoning_effort = "xhigh"
disable_response_storage = true
preferred_auth_method = "apikey"
personality = "pragmatic"

[model_providers.aicodemirror]
name = "aicodemirror"
base_url = "${OPENAI_BASE_URL}"
wire_api = "responses"
EOF

  chmod 600 "$AUTH_FILE" "$CONFIG_FILE" 2>/dev/null || true

  log_ok "Codex config written to ${CODEX_DIR}"
}

mask_secret() {
  local v="$1"
  local len="${#v}"
  if [[ "$len" -eq 0 ]]; then
    printf ''
    return 0
  fi
  if [[ "$len" -le 8 ]]; then
    printf '********'
    return 0
  fi
  printf '%s****%s' "${v:0:4}" "${v:len-4:4}"
}

print_summary() {
  log_step "5/5 Print install summary"

  local node_ver npm_ver codex_ver env_script_status
  node_ver="$(command_exists node && node --version || printf 'not found')"
  npm_ver="$(command_exists npm && npm --version || printf 'not found')"
  codex_ver="$(command_exists codex && codex --version || printf 'not found')"
  env_script_status="not used (Codex reads auth.json/config.toml)"

  cat <<EOF

Install Result
  node             : ${node_ver}
  npm              : ${npm_ver}
  codex            : ${codex_ver}
  OPENAI_BASE_URL  : ${OPENAI_BASE_URL}
  OPENAI_API_KEY   : $(mask_secret "$OPENAI_API_KEY")
  auth.json        : ${AUTH_FILE}
  config.toml      : ${CONFIG_FILE}
  env script       : ${env_script_status}

GitHub one-line install (replace owner/repo/ref):
  curl -fsSL https://raw.githubusercontent.com/<owner>/<repo>/<ref>/install-codex.sh | bash
EOF
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --openai-api-key)
        OPENAI_API_KEY="${2:-}"
        shift 2
        ;;
      --openai-base-url)
        OPENAI_BASE_URL="${2:-}"
        shift 2
        ;;
      --npm-registry)
        NPM_REGISTRY="${2:-}"
        shift 2
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        log_err "Unknown argument: $1"
        usage
        exit 1
        ;;
    esac
  done
}

main() {
  parse_args "$@"
  install_nodejs
  install_codex
  prompt_openai
  write_codex_config
  print_summary
}

main "$@"
