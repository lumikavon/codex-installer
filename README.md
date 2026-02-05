# 🚀 Codex 一键安装器

[![GitHub](https://img.shields.io/badge/GitHub-lumikavon%2Fcodex--installer-blue?logo=github)](https://github.com/lumikavon/codex-installer)
[![License](https://img.shields.io/badge/License-MIT-green)](#license)
[![Supported OS](https://img.shields.io/badge/Supported-Ubuntu%2FDebian%2FRockyLinux%2FOpenEuler-brightgreen)](#%EF%B8%8F-系统支持)

**一行命令部署 Codex**，自动安装 Node.js、配置环境、集成 MCP Servers。

## 🔥 快速开始

### 最简单的方式（推荐）

```bash
export HTTP_PROXY=http://172.27.0.1:7890
export HTTPS_PROXY=$HTTP_PROXY
curl -fsSL https://raw.githubusercontent.com/lumikavon/codex-installer/refs/heads/main/codex.install.sh | bash -s -- --api-key <your-openai-api-key>
```

或者使用 `wget`：

```bash
wget -qO- https://raw.githubusercontent.com/lumikavon/codex-installer/refs/heads/main/codex.install.sh | bash -s -- --api-key <your-openai-api-key>
```

**完成后，运行：**
```bash
source ~/.bashrc
codex -V
```

---

## 📦 安装内容

✅ **Node.js v22.18.0** – 自动下载、解压、配置环境变量  
✅ **npm、Yarn、pnpm** – 配置国内镜像加速  
✅ **@openai/codex** – 官方 Codex 命令行工具  
✅ **Codex 配置** – 自动生成 `~/.codex/auth.json` 和 `config.toml`  
✅ **MCP Servers** – 集成 Context7、Playwright、Chrome DevTools 等  
✅ **环境变量** – 自动写入 `~/.bashrc`  

---

## 🖥️ 系统支持

| 系统 | 版本 | 状态 |
|------|------|------|
| Ubuntu | 20.04+ | ✅ 已测试 |
| Debian | 11+ | ✅ 已测试 |
| RockyLinux | 8+ | ✅ 已测试 |
| OpenEuler | 22.03+ | ✅ 已测试 |
| CentOS | 8+ | ✅ 已测试 |
| Fedora | 36+ | ✅ 已测试 |
| AlmaLinux | 9+ | ✅ 已测试 |

**硬件需求：**
- CPU: x86_64（Intel/AMD）、ARM64（树莓派）、ARMv7
- 内存: 最少 512MB（推荐 2GB+）
- 磁盘: 最少 1GB 空闲空间
- 网络: 能访问 GitHub 和 npm 镜像

---

## 📖 详细用法

### 方式 1：直接执行（推荐）

```bash
curl -fsSL https://raw.githubusercontent.com/lumikavon/codex-installer/refs/heads/main/codex.install.sh | bash -s -- [OPTIONS]
```

### 方式 2：下载后本地执行

```bash
# 下载脚本
curl -fsSL -o codex.install.sh https://raw.githubusercontent.com/lumikavon/codex-installer/refs/heads/main/codex.install.sh

# 赋予执行权限
chmod +x codex.install.sh

# 执行安装
./codex.install.sh --api-key <your-api-key>
```

### 方式 3：Clone 仓库执行

```bash
git clone https://github.com/lumikavon/codex-installer.git
cd codex-installer
chmod +x codex.install.sh
./codex.install.sh --api-key <your-api-key>
```

---

## ⚙️ 参数选项

```bash
用法: codex.install.sh [OPTIONS]

选项：
  --api-key <key>     设置 OpenAI API Key（也可使用环境变量 OPENAI_API_KEY）
  --skip-nodejs       跳过 Node.js 安装（如已安装）
  --skip-codex        跳过 Codex 安装
  --skip-mcp          跳过 MCP Servers 配置
  -h, --help          显示帮助信息
```

### 使用示例

**使用 API Key 参数：**
```bash
curl -fsSL https://raw.githubusercontent.com/lumikavon/codex-installer/refs/heads/main/codex.install.sh | bash -s -- --api-key sk-proj-xxx
```

**使用环境变量：**
```bash
export OPENAI_API_KEY=sk-proj-xxx
curl -fsSL https://raw.githubusercontent.com/lumikavon/codex-installer/refs/heads/main/codex.install.sh | bash
```

**跳过 Node.js 安装（已安装过）：**
```bash
curl -fsSL https://raw.githubusercontent.com/lumikavon/codex-installer/refs/heads/main/codex.install.sh | bash -s -- --skip-nodejs --api-key sk-proj-xxx
```

**跳过 MCP Servers 配置：**
```bash
curl -fsSL https://raw.githubusercontent.com/lumikavon/codex-installer/refs/heads/main/codex.install.sh | bash -s -- --skip-mcp --api-key sk-proj-xxx
```

---

## 📂 目录结构

```
codex-installer/
├── README.md                  # 本文件
├── codex.install.sh           # 融合安装脚本（Node.js + Codex）
├── codex.sh                   # Codex 独立安装脚本（仅安装 Codex）
├── nodejs.sh                  # Node.js 独立安装脚本（仅安装 Node.js）
└── assets/                    # （可选）本地 Node.js 包存放处
    └── node-v22.18.0-linux-x64.tar.xz
```

---

## 🚀 安装完成后

### 1. 刷新环境变量

```bash
source ~/.bashrc
```

### 2. 验证安装

```bash
# 检查 Node.js
node -v
npm -v

# 检查 Codex
codex -V

# 检查 Yarn/Pnpm
yarn -v
pnpm -v
```

### 3. 开始使用

```bash
# 进入项目目录
cd /path/to/your/project

# 运行 Codex
codex
```

### 4. 查看配置

```bash
cat ~/.codex/auth.json
cat ~/.codex/config.toml
```

---

## 🔐 API Key 安全说明

- **不建议在命令行明文传递** API Key
- **推荐方式 1**：使用环境变量
  ```bash
  export OPENAI_API_KEY=sk-proj-xxx
  curl -fsSL https://raw.githubusercontent.com/lumikavon/codex-installer/refs/heads/main/codex.install.sh | bash
  ```

- **推荐方式 2**：交互式输入（使用 `-t 0` 检测 TTY）
  ```bash
  curl -fsSL https://raw.githubusercontent.com/lumikavon/codex-installer/refs/heads/main/codex.install.sh | bash
  # 脚本会提示输入 API Key
  ```

- **配置安全**：`~/.codex/auth.json` 权限自动设置为 `600` 仅所有者可读

---

## 🐛 故障排除

### 问题 1: 找不到 `node` 或 `npm` 命令

**原因**：PATH 未刷新  
**解决方案**：
```bash
source ~/.bashrc
node -v
```

### 问题 2: npm 安装速度慢

**原因**：默认 npm 源在国外  
**解决方案**：脚本已自动配置中国镜像，如需手动切换：
```bash
npm config set registry https://registry.npmmirror.com -g
```

### 问题 3: `codex` 命令不找到

**症状**：`command not found: codex`  
**解决方案**：
1. 确保 npm 全局 bin 在 PATH 中：
   ```bash
   echo $PATH | grep npm-global
   ```
2. 重新刷新环境：
   ```bash
   source ~/.bashrc
   ```
3. 手动检查 Codex 安装状态：
   ```bash
   npm list -g @openai/codex
   ```

### 问题 4: 权限错误（Permission denied）

**原因**：脚本文件无执行权限  
**解决方案**：
```bash
chmod +x codex.install.sh
./codex.install.sh --api-key <key>
```

### 问题 5: Curl/Wget 下载失败

**检查网络连接**：
```bash
# 测试 GitHub 连接
ping github.com

# 测试能否访问脚本
curl -I https://raw.githubusercontent.com/lumikavon/codex-installer/refs/heads/main/codex.install.sh
```

**备选方案**：使用代理
```bash
# 使用 Proxy（如需要）
curl -x [proxy-url] -fsSL https://raw.githubusercontent.com/lumikavon/codex-installer/refs/heads/main/codex.install.sh | bash -s -- --api-key <key>
```

### 问题 6: MCP Server 配置失败

**原因**：npx 或 codex 命令不可用  
**解决方案**：
```bash
# 检查 npx
npm list -g npm
which npx

# 手动配置 MCP Server
codex mcp add context7 -- npx -y @upstash/context7-mcp
```

---

## 📋 独立脚本说明

如果只需要安装某个组件，可使用以下脚本：

### codex.sh - 仅安装 Codex

```bash
# 前置要求：已安装 Node.js 和 npm
./codex.sh --api-key <api-key>
```

**功能**：
- 安装 @openai/codex
- 生成 ~/.codex 配置文件
- 配置环境变量
- 设置 MCP Servers

### nodejs.sh - 仅安装 Node.js

```bash
./nodejs.sh
```

**功能**：
- 下载安装 Node.js v22.18.0
- 安装 Yarn 和 Pnpm
- 配置 npm 镜像源

---

## 🔄 更新升级

### 升级 Codex

```bash
npm install -g @openai/codex@latest --registry=https://registry.npmmirror.com
```

### 升级 Node.js

```bash
# 删除旧版本（可选）
rm -rf ~/.local/node

# 运行安装脚本（会检测已安装，跳过重复下载）
./codex.install.sh --skip-codex --api-key <key>
```

---

## 📖 环境变量说明

脚本会在 `~/.bashrc` 中写入以下环境变量：

```bash
# Node.js 环境
export NODE_HOME="$HOME/.local/node"
export PATH="$NODE_HOME/bin:$HOME/.local/bin:$HOME/.npm-global/bin:$PATH"

# OpenAI 配置
export OPENAI_BASE_URL="https://api.aicodemirror.com/api/codex/backend-api/codex"
export OPENAI_API_KEY="sk-proj-xxx"

# NPM 镜像
npm registry: https://registry.npmmirror.com
```

**手动刷新**：
```bash
source ~/.bashrc
```

---

## 🤝 贡献

欢迎提交 Issue 和 Pull Request！

## 📄 License

MIT License - 详见 [LICENSE](LICENSE) 文件

---

## 📞 获取帮助

1. **查看脚本帮助**：
   ```bash
   ./codex.install.sh --help
   ```

2. **查看日志输出**：脚本使用 ISO 8601 时间戳标注每一步（便于排查问题）

3. **提交 Issue**：[GitHub Issues](https://github.com/lumikavon/codex-installer/issues)

4. **查看官方文档**：
   - [Codex 官方文档](https://github.com/openai/codex)
   - [Node.js 官方网站](https://nodejs.org)

---

## 🎯 快速命令参考

| 任务 | 命令 |
|------|------|
| 完整安装 | `curl -fsSL https://raw.githubusercontent.com/lumikavon/codex-installer/refs/heads/main/codex.install.sh \| bash -s -- --api-key <key>` |
| 仅更新 Codex | `npm install -g @openai/codex@latest` |
| 查看 Codex 版本 | `codex -V` |
| 查看配置 | `cat ~/.codex/config.toml` |
| 重置配置 | `rm -rf ~/.codex && ./codex.install.sh --api-key <key>` |
| 查看 npm 镜像 | `npm config get registry` |

---

**最后更新**: 2026-02-05  
**维护者**: [lumikavon](https://github.com/lumikavon)
