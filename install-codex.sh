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
  curl -fsSL https://raw.githubusercontent.com/<owner>/<repo>/<ref>/.agents/skills/agents-installer/scripts/install-codex.sh | bash
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
  mkdir -p "${HOME}/.npm-global/bin"
  npm config set prefix "${HOME}/.npm-global" --location=user >/dev/null 2>&1 || \
    npm config set prefix "${HOME}/.npm-global" >/dev/null 2>&1 || true
  export PATH="${HOME}/.npm-global/bin:${PATH}"
}

install_nodejs() {
  log_step "1/5 Install Node.js"

  if command_exists node && command_exists npm; then
    local major
    major="$(get_node_major)"
    if [[ -n "$major" && "$major" -ge 18 ]]; then
      ensure_npm_user_prefix
      npm config set registry "$NPM_REGISTRY" --location=global >/dev/null 2>&1 || npm config set registry "$NPM_REGISTRY" -g >/dev/null 2>&1 || true
      log_ok "Node.js ready: $(node --version) / npm $(npm --version)"
      return 0
    fi
    log_warn "Existing Node.js is too old: $(node --version). Need >= 18."
  fi

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

  if ! command_exists node || ! command_exists npm || [[ "$(get_node_major)" -lt 18 ]]; then
    log_info "Falling back to nvm for Node.js LTS"
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
    nvm install --lts
    nvm alias default 'lts/*'
  fi

  if ! command_exists node || ! command_exists npm; then
    log_err "Node.js/npm not found after installation."
    exit 1
  fi

  if [[ "$(get_node_major)" -lt 18 ]]; then
    log_err "Node.js major version is still < 18."
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

  node -e 'const fs=require("fs"); fs.writeFileSync(process.argv[1], JSON.stringify({OPENAI_API_KEY:process.argv[2]}, null, 2)+"\n");' \
    "$AUTH_FILE" "$OPENAI_API_KEY"

  upsert_block "$CONFIG_FILE" "$MANAGED_START" "$MANAGED_END" <<EOF
model = "gpt-5-codex"
model_provider = "openai"
model_reasoning_effort = "high"
preferred_auth_method = "apikey"

[model_providers.openai]
name = "OpenAI"
base_url = "${OPENAI_BASE_URL}"
env_key = "OPENAI_API_KEY"
wire_api = "responses"
EOF

  local escaped_key escaped_base
  escaped_key="$(escape_single "$OPENAI_API_KEY")"
  escaped_base="$(escape_single "$OPENAI_BASE_URL")"
  cat >"$ENV_FILE" <<EOF
#!/usr/bin/env bash
export OPENAI_API_KEY='${escaped_key}'
export OPENAI_BASE_URL='${escaped_base}'
EOF
  chmod 600 "$AUTH_FILE" "$CONFIG_FILE" "$ENV_FILE" 2>/dev/null || true

  ensure_shell_profile_sources_env

  export OPENAI_API_KEY
  export OPENAI_BASE_URL

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

  local node_ver npm_ver codex_ver
  node_ver="$(command_exists node && node --version || printf 'not found')"
  npm_ver="$(command_exists npm && npm --version || printf 'not found')"
  codex_ver="$(command_exists codex && codex --version || printf 'not found')"

  cat <<EOF

Install Result
  node             : ${node_ver}
  npm              : ${npm_ver}
  codex            : ${codex_ver}
  OPENAI_BASE_URL  : ${OPENAI_BASE_URL}
  OPENAI_API_KEY   : $(mask_secret "$OPENAI_API_KEY")
  auth.json        : ${AUTH_FILE}
  config.toml      : ${CONFIG_FILE}
  env script       : ${ENV_FILE}

GitHub one-line install (replace owner/repo/ref):
  curl -fsSL https://raw.githubusercontent.com/<owner>/<repo>/<ref>/.agents/skills/agents-installer/scripts/install-codex.sh | bash
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
