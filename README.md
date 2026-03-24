# codex-installer

Cross-platform installer scripts for setting up OpenAI Codex CLI with API-key based configuration.

## What this repository contains

- `install-codex.ps1`: Windows PowerShell installer
- `install-codex.sh`: Linux installer script

Both scripts install Node.js, install `@openai/codex`, and configure Codex under `~/.codex`.

## What the scripts configure

After installation, the scripts set up:

- `~/.codex/auth.json`
- `~/.codex/config.toml`
- Windows installer also ensures the global npm prefix is present on the user `PATH`
- Linux installer ensures the npm user prefix bin directory is available in future shells

Default `OPENAI_BASE_URL` is:

`https://api.openai.com/v1`

## Prerequisites

- Windows PowerShell 5.1+ (for `install-codex.ps1`) or Bash (for `install-codex.sh`)
- Internet access
- A valid `OPENAI_API_KEY`
- Package manager support:
  - Windows: `winget` / `scoop` / `choco` (at least one)
  - Linux: `apt-get`, `dnf`, `yum`, `zypper`, `pacman`, or fallback via `nvm`

## Quick start

### Windows

Interactive run:

```powershell
powershell -ExecutionPolicy Bypass -File .\install-codex.ps1
```

Non-interactive run:

```powershell
powershell -ExecutionPolicy Bypass -File .\install-codex.ps1 `
  -OpenAIApiKey "sk-xxxx" `
  -OpenAIBaseUrl "https://api.openai.com/v1" `
  -NpmRegistry "https://registry.npmjs.org"
```

### Linux

Interactive run:

```bash
bash ./install-codex.sh
```

Non-interactive run:

```bash
bash ./install-codex.sh \
  --openai-api-key "sk-xxxx" \
  --openai-base-url "https://api.openai.com/v1" \
  --npm-registry "https://registry.npmjs.org"
```

## Script flow

Each installer follows a 5-step flow:

1. Install Node.js (require major version >= 18)
2. Install Codex (`npm install -g @openai/codex`)
3. Read `OPENAI_BASE_URL` and `OPENAI_API_KEY`
4. Write Codex config files under `~/.codex`
5. Print installation summary

## Notes

- Current Codex versions read credentials from `~/.codex/auth.json` and `~/.codex/config.toml`; no separate `env.ps1` / `env.sh` file is required.
- If `codex` is not immediately available in the current shell, reopen your terminal.

