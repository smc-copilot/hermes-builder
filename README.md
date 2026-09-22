# Copilot Hermes v0.21.0 Windows MSI 打包工程（本地源码优先）

本工程用于把 `loudon84/copilot-hermes` 的 Hermes Agent v0.21.0 制作为 **Windows x64、当前用户范围、默认安装到 `%LOCALAPPDATA%\hermes` 的单一 MSI**。

构建方案采用本地源码优先：如果 `src/hermes-agent` 已经存在，则确认它是 `main` 分支的 Git checkout，执行 `git pull --ff-only` 后复制到 MSI payload；如果本地源码不存在，则从配置的远程仓库 clone，并 checkout 配置的 ref。客户端安装阶段不需要 GitHub / PyPI / npm 下载核心依赖。

## 1. 默认锁定基线

- Repository: `https://github.com/loudon84/copilot-hermes.git`
- Hermes: `0.21.0`
- Fallback source ref: `041b6985a00d01b54f830c1607dd370007a306bf`
- Target: Windows x64
- Install scope: per-user
- Install root: `%LOCALAPPDATA%\hermes`
- WiX Toolset SDK: 4.0.6

所有基线都在 `build-config.json` 中可配置。生产发布建议始终锁定到 commit SHA，不建议把 `main` 直接作为正式 MSI 构建输入。

## 2. MSI 内默认包含什么

构建时先准备本地源码（必要时 clone），再复用 Hermes 自己的 `scripts/install.ps1` Stage Protocol 准备稳定运行时：

- uv
- uv-managed Python 3.11
- Portable Git
- Node.js
- Hermes v0.21.0 source tree
- Hermes Python 依赖所需的完整 uv 离线缓存
- Hermes Node dependencies 所需的完整 npm 离线缓存
- Playwright Chromium（固定到 `%LOCALAPPDATA%\hermes\playwright`）
- ripgrep
- ffmpeg / ffprobe
- Hermes bootstrap / repair / verify scripts
- 企业默认配置模板
- Enterprise Skills / Plugins 注入点

Python venv **不会从构建机直接复制到用户电脑**。原因是 Windows venv 中存在与构建路径绑定的 launcher / interpreter path。MSI 安装后通过本地 uv cache 在最终 `%LOCALAPPDATA%\hermes\hermes-agent\venv` 创建 venv，全过程使用 `--offline --locked`。

Node 依赖在构建机先在线安装一次以填充 npm cache，并把 Playwright Chromium 固定下载到 payload；随后删除 `node_modules` 并再执行一次 **npm hard-offline 验证**。客户端安装时在最终用户路径从 MSI 内的 npm cache 本地重建 `node_modules`，避免 npm registry 下载，也避免把构建机路径绑定的 workspace junction 直接复制到另一台电脑。

## 3. 默认不放进 Core MSI 的两类内容

为了保持运行时边界清晰，默认：

- `includeDesktop=false`：不把 Hermes Electron Desktop 当作 Native Runtime 的必选组件。
- `includePlatformSdks=false`：Browser Use / CUA Driver 等上游 best-effort 平台 SDK 不默认预装。它们存在额外二进制、浏览器体积、路径可迁移性以及第三方再分发许可证问题。

这两个开关保留在 `build-config.json` 中，但本工程 v1.0 对正式生产包的验证基线是 Core MSI。若后续要做 `full` 发行包，建议另建 `copilot-hermes-full` MSI SKU，而不是让核心运行时和浏览器/桌面生命周期绑死。

## 4. 构建机要求

建议使用 Windows Server 2022 / Windows 11 x64 构建节点：

- PowerShell 7 或 Windows PowerShell 5.1+
- Git
- .NET 8 SDK
- 能访问 GitHub、PyPI/uv registry、npm registry、nodejs.org、Git for Windows、ffmpeg 下载源

WiX SDK 通过 NuGet 自动恢复，不要求手工安装 WiX。

## 5. 一键构建

在项目根目录执行：

```powershell
Set-ExecutionPolicy -Scope Process Bypass
.\build\Build.ps1
```

源码准备规则：

1. `src/hermes-agent` 存在时，必须是 `main` 分支的 Git checkout；构建执行 `git pull --ff-only`，然后使用更新后的源码。
2. `src/hermes-agent` 不存在时，构建从 `build-config.json` 的仓库 clone 到该路径，并 checkout 配置的 ref。
3. 本地 checkout 不满足 Git、分支或 fast-forward 要求时，构建直接失败，不会静默覆盖本地源码。

本地源码缺失时临时覆盖 fallback ref：

```powershell
.\build\Build.ps1 -SourceRef main
```

正式发布仍应使用 SHA：

```powershell
.\build\Build.ps1 -SourceRef 041b6985a00d01b54f830c1607dd370007a306bf
```

构建完成后输出：

```text
dist/
  copilot-hermes-enterprise-0.21.0-win-x64.msi
  copilot-hermes-enterprise-0.21.0-win-x64.msi.sha256
  build-info.json
```

## 6. 客户端安装

交互安装：

```powershell
msiexec /i .\copilot-hermes-enterprise-0.21.0-win-x64.msi
```

静默安装：

```powershell
msiexec /i .\copilot-hermes-enterprise-0.21.0-win-x64.msi /qn /norestart /l*v hermes-install.log
```

MSI 安装结束前会执行本地初始化：

1. 设置当前用户 `HERMES_HOME=%LOCALAPPDATA%\hermes`
2. 把 `%LOCALAPPDATA%\hermes\bin` 加入当前用户 PATH
3. 使用 MSI 内的 uv + Python + uv cache
4. 在真实用户路径创建 `hermes-agent\venv`
5. `uv sync --offline --locked`
6. 从 MSI 内 npm cache 离线执行 Hermes `node-deps`，并复用已打包 Playwright Chromium
7. 首次 seed `.env` / `config.yaml` / `SOUL.md`，已存在时绝不覆盖
8. 同步 `enterprise/skills` 到 `%LOCALAPPDATA%\hermes\skills`，目录名转为小写连字符，保留分类路径
9. 写入 bundle install marker

## 7. 安装目录

```text
%LOCALAPPDATA%\hermes\
  bin\
    uv.exe
    rg.exe
    ffmpeg.exe
    ffprobe.exe
    hermes.cmd
    hermes.ps1
  python\
  git\
  node\
  hermes-agent\
    venv\                 # 客户端安装时离线生成
    node_modules\         # 客户端安装时从 MSI 内 npm cache 离线生成
    plugins\enterprise\  # 可选企业插件
  offline\
    uv-cache\
    npm-cache\
    bundle-settings.json
  playwright\              # 构建机下载并打入 MSI 的 Chromium
  bootstrap\
  defaults\
  official-source.json
  runtime-manifest.json

  .env                    # 用户状态：MSI 不拥有
  config.yaml             # 用户状态：MSI 不拥有
  SOUL.md                 # 用户状态：MSI 不拥有
  skills\                 # 用户/企业内容
  sessions\               # 用户状态
  memories\               # 用户状态
  logs\                   # 用户状态
  state\                  # 用户状态
```

## 8. Ownership 规则

### PROGRAM_MANAGED

MSI 管理并升级：

- `bin`
- `python`
- `git`
- `node`
- `hermes-agent` 源码与预装 Node 依赖
- `offline`
- `playwright`
- `bootstrap`
- `defaults`
- `official-source.json`
- `runtime-manifest.json`

### USER_STATE

MSI 不把以下文件作为安装 payload，因此升级不会覆盖：

- `.env`
- `config.yaml`
- `SOUL.md`
- `sessions`
- `memories`
- `logs`
- 与企业 Skill 文件路径不冲突的用户自建 Skills

### CONTENT_MANAGED

`enterprise/skills/BaiduSearch` 安装到 `skills/baidu-search`；`enterprise/skills/research/BaiduSearch` 安装到 `skills/research/baidu-search`。支持根目录 Skill 或一层分类下的完整 Skill 包（以 `SKILL.md` 识别）；目录名统一为小写连字符，命名冲突或超过此层级会中止构建。不再增加 `enterprise` 层；安装保留其他用户文件，但同路径文件会被企业版本覆盖。已有安装中的旧 `skills/enterprise` 目录不会自动删除。

`.env.template` 仅检查变量定义格式，不验证值是否为空、密钥有效性或 URL 可达性。首次安装按模板原样初始化 `.env`，已有 `.env` 保留。

## 9. Repair / 验证

强制重建 Python venv：

```powershell
& "$env:LOCALAPPDATA\hermes\bootstrap\Repair-Hermes.ps1"
```

验证：

```powershell
& "$env:LOCALAPPDATA\hermes\bootstrap\Verify-Installation.ps1"
```

附加 `hermes doctor`：

```powershell
& "$env:LOCALAPPDATA\hermes\bootstrap\Verify-Installation.ps1" -RunDoctor
```

Hermes launcher 在自己的进程中设置 `NO_COLOR=1`，用于规避部分 Windows 终端执行 `hermes doctor` 时的 ANSI/编码乱码；不会把 `NO_COLOR` 写成用户全局环境变量。

启动器将 `%HERMES_HOME%\node` 放在进程 PATH 首位，Hermes 及其 MCP 子进程可直接使用随包的 `node`、`npm`、`npx`，优先于系统 Node。此设置不修改用户或系统全局 PATH。构建阶段检查三个命令及 npm/npx 的 JavaScript 入口是否齐全。

## 10. 卸载行为

```powershell
msiexec /x {PRODUCT-CODE}
```

实际 ProductCode 由 WiX 每次 Major Upgrade 生成。卸载时：

- MSI 删除自己管理的程序文件
- Cleanup 脚本删除生成的 `hermes-agent\venv`
- 从当前用户 PATH 移除 Hermes `bin`
- 清理由本包设置且仍指向本安装路径的 `HERMES_HOME` / `HERMES_GIT_BASH_PATH`
- **保留** `.env`、`config.yaml`、`SOUL.md`、sessions、memories、logs、用户 Skills

## 11. 企业配置与资产

把企业默认内容放到：

```text
enterprise/config/.env.template
enterprise/config/config.yaml.template
enterprise/config/SOUL.md.template
enterprise/skills/
enterprise/plugins/
```

`Build.ps1` 会把它们映射进 payload。

注意：模板中不要写真实 API Key、Token、密码或内网凭据。

## 12. 重要部署限制：不要用 SYSTEM 安装这个 per-user MSI

这是“当前登录用户”安装包。`LocalAppDataFolder` 与 HKCU 都跟执行 MSI 的 Windows identity 绑定。

如果通过 OPSI / SCCM / Intune 等终端系统以 `SYSTEM` 身份直接运行，安装目录会落到 SYSTEM profile，而不是交互用户的 `%LOCALAPPDATA%`。

企业批量部署应选择以下之一：

1. 让部署系统在交互用户上下文运行 MSI；或
2. 后续另做 Machine Payload + Per-user Bootstrap 双层安装模型。

## 13. 第三方许可证

本工程只提供下载和封装逻辑，不把第三方二进制直接放进本源码 ZIP。正式对外或跨法人实体分发 MSI 前，必须完成以下组件的 redistribution / NOTICE 审查：

- Python / python-build-standalone（由 uv 管理）
- uv
- Git for Windows
- Node.js / npm
- ripgrep
- ffmpeg build
- Chromium / Browser tooling（若以后启用 full SKU）
- CUA Driver（若以后启用 full SKU）

尤其是 ffmpeg，应根据你实际采用的 build configuration 判断 LGPL/GPL 义务，而不是只依据“ffmpeg”名称判断。
