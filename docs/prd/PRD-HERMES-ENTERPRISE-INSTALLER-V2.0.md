---
title: "Hermes Enterprise Installer v2.0 工程解决方案 PRD"
subtitle: "Windows MSI Files-Only + Tauri Setup + Independent Offline Runtime Bootstrap"
prd_id: "PRD-HERMES-ENTERPRISE-INSTALLER-V2"
version: "2.0.0"
status: "APPROVED_FOR_PLAN"
template_version: "需求PRD工程模板 v1.0"
product: "SMC Copilot Hermes Enterprise Runtime"
repository: "https://github.com/smc-copilot/hermes-builder"
branch: "master"
baseline_commit: "7d77737353d134b5169f85f73f71d094a74635dc"
reference_runtime_repository: "https://github.com/smc-copilot/hermes-agent"
reference_runtime_commit: "c16cc4ca7597ce9b52944bbecea450c51e9781dc"
actual_packaged_source: "https://github.com/loudon84/copilot-hermes"
actual_packaged_commit: "041b6985a00d01b54f830c1607dd370007a306bf"
actual_packaged_agent_version: "0.21.0"
owner: "Hermes Builder / Windows Installer Engineering"
reviewers: ["Windows Installer", "Hermes Runtime", "SMC Copilot Desktop", "Ops/OPSI", "Security", "QA/Release"]
created_at: "2026-10-09"
updated_at: "2026-10-09"
target_release: "Hermes Enterprise Installer v2.0 (Agent 0.21.0 fixed-source baseline)"
change_type: ["BROWNFIELD_CHANGE", "ARCHITECTURE_CHANGE", "BUGFIX", "INTEGRATION", "GOVERNANCE"]
golden_consumer: "Windows 10 x64 clean machine + smc-copilot Desktop Native Hermes Runtime + interactive user"
related_docs:
  - "需求PRD工程模板.md"
  - "docs/prd/PRD-HERMES-BUILDER-MSI-OFFLINE-HARDENING-v1.0.md"
  - "docs/specs/2026-10-08-msi-offline-hardening-grill.md"
  - "docs/specs/2026-10-09-enterprise-installer-v2-grill.md"
  - "docs/specs/2026-10-09-enterprise-installer-v2-g-p-review.md"
  - "https://github.com/smc-copilot/hermes-agent/tree/main/apps/bootstrap-installer"
supersedes: null
plan_approval: "APPROVED"
release_gate: "BLOCKED"
---

# Hermes Enterprise Installer v2.0 — Engineering Contract PRD

> **审阅状态**：`APPROVED_FOR_PLAN`（2026-10-09，G-P01…G-P08 PASS，记录 `docs/specs/2026-10-09-enterprise-installer-v2-g-p-review.md`）。本文定义目标行为，不表示已完成代码修改或 Windows 10 真机验收。语义合同已按 `docs/specs/2026-10-09-enterprise-installer-v2-grill.md`（Q1–Q24）收成唯一口径。本文不覆盖且不撤销已批准的 v1 MSI Offline Hardening PRD；v2 是下一阶段独立架构变更。**本版 MUST NOT 随 Installer 升级自动升级 Hermes Agent；固定打包源码仍为 `loudon84/copilot-hermes@041b6985…`，Agent 版本 `0.21.0`。** Release Gate 仍为 `BLOCKED`。
>
> **证据等级**：`CODE_OBSERVED` = 固定 SHA 的仓库代码；`DESIGN_DECIDED` = 本 PRD 新工程规范，尚未实现；`LIVE_UNVERIFIED` = 必须进行 Win10 真机测试。任何源代码事实与本 PRD 新要求不同，按“现状 vs 目标差异”记录，不能把目标写成已实现。

# 0. PRD 使用原则

- **WHY**：同一 MSI 在部分 Windows 10 设备安装末段失败，`InitializeHermes` Custom Action 返回通用 MSI 错误后回滚；用户不能看出具体 uv/文件权限/进程占用原因。
- **WHAT**：采用 `Files-Only MSI + 独立 Runtime Bootstrap + Tauri Setup UI`；安装失败后保留文件和取证，提供重试/修复；保证核心安装离线；保持 Hermes Agent v0.21.0。
- **BOUNDARY**：WiX 管理程序文件；独立 Init 管理生成的 venv/启动器与 Bootstrap receipt；UI 只编排；Hermes CLI 管理 Gateway；smc-copilot 管理登录后模型 Provider。
- **STATE**：MSI 产品注册事实、Runtime Receipt、日志 Evidence 为不同 SOT；不得把“文件已安装”推断为“Runtime 可用”。
- **INPUT**：固定 Source SHA、release manifest、MSI / Runtime Bundle、当前 Windows 用户身份、已有 Hermes Root。
- **OUTPUT**：可离线安装并诊断的用户入口与企业 MSI 入口；每次安装都有 `operation_id`、状态、错误码和完整诊断包。
- **SIDE EFFECT**：限定程序文件、Bootstrap 生成文件、按需写入的用户级环境变量；严禁自动修改已存在模型配置。
- **FAILURE**：MSI 文件安装失败使用标准回滚；Bootstrap 初始化失败保留已安装 payload，进入 `REPAIR_REQUIRED`；恢复失败保留 T0 备份。
- **ACCEPTANCE/EVIDENCE**：每项 `MUST/MUST NOT` 映射到 §20 的 AC、§24 的实际命令/Oracle/原始文件、§27 的 Traceability。

本文 `MUST`、`MUST NOT`、`SHOULD`、`MAY` 均按模板的含义解释。对关键路径、版本、状态、回滚或错误码出现多个合理解释时，Plan Agent 返回 `SPEC_SEMANTIC_GAP` 并阻止生成 `.plan.md`，不得补全猜测。`SKIPPED` 与 `BLOCKED` 绝不等同 `PASS`。

# 1. 文档元数据

见 YAML Front Matter。评审对象为 **Installer v2 设计**，不是 Runtime v0.21.0 新功能 PRD。工程实施不得以当前 `smc-copilot/hermes-agent/main` 替换实际锁定源码。计划批准与发布批准是两道独立 Gate：`APPROVED_FOR_PLAN` 仅允许生成 `.plan.md`，不等于通过真实安装与 Golden Consumer 发布验收。

# 2. 一句话目标

让 **Windows 10/11 x64 的交互式用户或企业部署系统**，在 **持有 SHA 与 Ed25519 Manifest 校验通过、来源固定且依赖完整的离线安装包** 时，通过 **一次点击 Hermes-Setup.exe，或两条显式企业部署命令** 安装并初始化 Hermes Agent v0.21.0；若 Runtime 初始化失败，**已成功提交的 MSI payload 不回滚、用户状态不被覆盖、可立即读取错误码并重新初始化**。本轮不要求 Authenticode。

# 3. 背景与问题定义

## 3.1 Current State（源码事实 / CODE_OBSERVED）

1. `installer/Package.wxs`：WiX SDK 5.0.2，`Scope=perUser`，`InstallFiles → PreflightHermes → InitializeHermes`，后两个是 `WixQuietExec` deferred CA 且 `Return=check`；脚本失败触发 MSI 通用失败和回滚。
2. `scripts/Initialize-Hermes.ps1`：使用 `Start-Process -ArgumentList $syncArgs` 运行随包 uv，`--offline --frozen --link-mode copy`，再检查 `venv\Scripts\hermes.exe` / `bin\hermes.exe`、`import yaml, openai`，在初始化中修改用户 HERMES_HOME/PATH。`Start-Transcript -Force` 使用固定 `%TEMP%` 日志名；失败映射到顶层 exit 1。
3. `scripts/Preflight-HermesInstall.ps1`：安装文件释放后验证 8 个关键文件的哈希、4 GiB 空闲、Python/Node/uv cache；实际预检晚于 MSI 文件修改。
4. `scripts/Install-HermesMsi.ps1`：可包装 `msiexec /l*v` 并复制四份诊断日志，但用户直接双击 MSI 时不会执行该包装脚本。
5. `build/Prepare-OfflineDependencies.ps1`：构建机填充并离线验证 uv/npm 缓存；最终删除构建机 venv 和 node_modules；客户端需在最终用户路径重建 Python venv。
6. `build/Build.ps1` / `build-config.json`：构建锁定 Hermes Agent `0.21.0` 且源仓库为 `loudon84/copilot-hermes` 的固定 SHA。当前发布物以 Agent 版本名命名 MSI，尚未独立表达 Installer v2 ProductVersion。
7. `.github/workflows/build-msi.yml`：有静态/模拟测试和 Windows Server 构建，但未执行真实交互用户 `msiexec` 与真实 Windows 10 离线初始化。
8. `smc-copilot/hermes-agent/apps/bootstrap-installer` 已有 Tauri/Rust 安装状态、stdout/stderr 流、进度、失败页和日志路径。它是**参考实现**；该项目包含下载脚本和可选 Desktop 构建行为，不能不加限制地复制到 Core 离线安装器。
9. `smc-copilot` 桌面端按 `%LOCALAPPDATA%\hermes\bin\hermes.exe` 和 Gateway `127.0.0.1:8642` 定位 Native Hermes；v2 MUST 兼容这些路径，不在此 PRD 重写用户登录/Nodeskclaw 模型投影。

## 3.2 可证伪问题

- `P-001`：同一 MSI 的 Python 初始化在不同 Win10 用户目录、权限或进程状态下可能结果不同，现有 CI 未真实覆盖。
- `P-002`：`InitializeHermes` 在 MSI 提交前构建 Python venv；其任何异常都会触发整个 Payload 的事务回滚。
- `P-003`：MSI 1603 不是 Python 失败的业务错误码；直接双击缺乏固定入口的全量日志与失败分阶段说明。
- `P-004`：当前客户端存在隐藏的用户环境变量、副本启动器、运行中 Gateway、数据所有权等交叉影响。
- `P-005`：Installer 与 Hermes Agent 版本未严格拆分，容易把修复安装器等同升级 Agent。

## 3.3 Impact

| 领域 | 影响 |
|---|---|
| 业务 | 部分新机器无法独立完成安装，需复制其他机器文件或重复 MSI |
| 工程 | 文件释放、Runtime 初始化和产品事务重叠，错误难复现 |
| 安全 | 错误日志丢失时难审计进程、文件和网络行为 |
| 运维 | MSI 回滚浪费终端下载/解包时间；OPSI per-user 部署需清楚身份边界 |
| AI Coding | 实现容易误把 Tauri 登录/安装进程当成 venv 生命周期 Owner，缺少可验证边界 |

# 4. Scope

## 4.1 In Scope

| Scope | 行为 | Requirement |
|---|---|---|
| SCOPE-001 | 锁定 Agent SHA、Installer MSI 版本与构建证据 | REQ-SRC-001 |
| SCOPE-002 | 构建签名/摘要明确的离线 Payload 与两种安装发行入口 | REQ-BUILD-001、REQ-ENTRY-001 |
| SCOPE-003 | MSI 仅负责程序文件的标准安装/卸载，不再执行长时 uv 初始化 | REQ-MSI-001 |
| SCOPE-004 | 安装前只读系统检查（只允许写独立诊断目录）与确定性冲突分类 | REQ-PRE-001、REQ-GW-001 |
| SCOPE-005 | 离线 uv 重建、CLI 双路径校验、初始化事务与 Receipt | REQ-PY-001、REQ-TXN-001 |
| SCOPE-006 | 环境变量、用户状态及企业 Skills 所有权 | REQ-ENV-001、REQ-OWN-001、REQ-SKILL-001 |
| SCOPE-007 | 诊断持久化、错误码及 Bootstrap 重试/修复 | REQ-OBS-001、REQ-REPAIR-001 |
| SCOPE-008 | Tauri UI 阶段交互、失败页与人机入口 | REQ-UI-001 |
| SCOPE-009 | Win10 真机测试、离线网络门槛、与 Desktop 黄金链路 | REQ-SEC-001、REQ-CI-001 |
| SCOPE-010 | v1 → v2 MajorUpgrade 规则及 Agent 版本治理 | REQ-MIG-001、REQ-UPD-001 |

## 4.2 Out of Scope / Hard Exclusion

- `NON-GOAL-001`：v2.0 **MUST NOT** 将 Hermes Agent 从 `0.21.0@041b6985…` 自动升级至当前 `smc-copilot/hermes-agent/main`；主线 Runtime 版本迁移另立已签发的 Change/Bundle，不随 Installer 产品版本提升发生。
- `NON-GOAL-002`：不得修改 Hermes Agent 模型业务、Nodeskclaw 登录/Provider 投影逻辑，或向 `config.yaml` 注入企业密钥。
- `NON-GOAL-003`：不交付 SYSTEM/per-machine MSI；OPSI 必须在目标**交互用户**上下文安装；Machine Payload + Per-user Provisioning 属下一独立需求。
- `NON-GOAL-004`：Core 初始化期间不得执行上游 `install.ps1`、`npm/npx install`、`git clone`、Browser Use/CUA 安装、Playwright 下载。
- `NON-GOAL-005`：不在本版强行替换 Python venv 为预构建可迁移 Runtime Image；该能力限研究 PoC，不进入 Release Gate。
- `NON-GOAL-006`：不承诺安装完成后的模型推理、企业认证及联网业务请求零网络；该网络边界在 §17、§18 单独描述。
- `NON-GOAL-007`：**本轮 v2.0 MUST NOT 要求 Authenticode / 组织代码签名证书。** Init EXE、Core MSI、Setup EXE 允许无 PE 签名发布；G-P06、Release Gate、AC Oracle **不得**把 SignTool/`signature_valid`(Authenticode) 当作 PASS 条件。身份与完整性以 Release Manifest SHA + runtime-manifest Ed25519 为准。Authenticode 属后续独立 Change，本版不得因缺证书阻断计划或发布。

## 4.3 Architecture Boundary

| Domain | Owner | Input | Output | 不负责 |
|---|---|---|---|---|
| Spec | 本 PRD | 源码+验收约束 | Architecture/Requirements/AC | 替实施者补充未知语义 |
| Build | `hermes-builder` | 固定 SHA+锁+缓存 | MSI、Setup EXE、Manifest、Evidence | 终端用户配置 |
| Package | WiX MSI | 已核验 Payload | 文件注册、程序落盘 | Python venv 构建、Gateway 启动、模型密钥 |
| Bootstrap Engine | 新 Rust CLI | MSI Product State + Runtime Manifest | venv、CLI、receipt、logs | 下载 Python 或隐式升级 Agent |
| Install UI | 新 Tauri GUI | Bootstrap Engine Events | 进度、错误、导出诊断 | 直接操作受管文件 |
| Hermes Runtime | `hermes-agent` | CLI、环境变量、用户配置 | Gateway 服务与 CLI | 软件包 MSI 产品管理 |
| Business Consumer | `smc-copilot` | Native Hermes CLI/Gateway | 本地 Agent 能力 | 修改 MSI/Bootstrap 生命周期状态 |
| Governance | QA / Security / Release | Tests/Evidence | Gate 判定 | 以 CI 成功替代真机证据 |

# 5. Terminology / Domain Model

| Term | 唯一定义 |
|---|---|
| `Core MSI` | `Hermes-Core-2.0.0-win-x64.msi`：WiX 安装包，仅管理 Program Payload；不进行 uv sync |
| `Hermes-Setup.exe` | 用户级 Tauri GUI 安装入口，自带经 SHA 验证的 Core MSI；执行显式安装流程 |
| `HermesRuntimeInit.exe` | 被 Core MSI 安装的无界面引导执行器，支持 `--initialize/--repair/--status/--export-diagnostics`；GUI 与其共享 Rust Engine 库而非复制逻辑 |
| `Program Payload` | MSI 文件组件拥有的静态 `bin/python/git/node/hermes-agent` 源码与 `offline` 缓存等，排除生成 venv 与用户状态 |
| `Runtime Generated State` | `hermes-agent/venv`、复制产生的 CLI launcher、Bootstrap Receipt、部分安装器环境设置；不由 MSI 文件组件直接所有 |
| `User State` | 既有 `.env`、`config.yaml`、`SOUL.md`、Sessions、Memories、用户 Skills、业务 Provider JSON；默认 PRESERVE |
| `PAYLOAD_INSTALLED` | MSI 在当前用户上下文成功提交；尚无 READY receipt，且没有已动过 Generated 的失败 operation record；不意味着 CLI/Gateway 可用 |
| `PAYLOAD_INSTALLED_REBOOT_REQUIRED` | 探针状态：MSI 已提交，但 HermesRoot 仍有待替换文件或 Restart Manager 对该树报 reboot-required；不得开始 Init |
| `READY` | Bundle SHA、venv/python imports、两个 CLI `--version` 和 Runtime Receipt 均匹配且最后一次校验通过；Gateway 未必常驻 |
| `REPAIR_REQUIRED` | Program Payload 存在，且 Bootstrap 已对 Generated 做过失败 mutation 或 receipt/观测不匹配；保留程序与取证、可 `--initialize` 收敛或 `--repair` 重建。零 mutation 的预检阻断不得升成此状态 |
| `INTERRUPTED` | 仅探针：`runtime-init.lock` 存在且 holder PID 已死；receipt 不得写此值 |
| `INITIALIZING` | 仅探针：锁存在且 holder PID 仍活且 exe 匹配 |
| `DESIRED_STATE` | 固定的签名 Manifest（目标 Agent/Installer/Bundled Runtime），不是当前机器文件 |
| `OBSERVED_STATE` | MSI 注册、文件检查、版本命令输出、进程和授权状态 |
| `LAST_APPLIED_STATE` | Bootstrap `runtime-receipt-v2.json`，由引擎原子发布 |
| `Evidence` | 含实测命令/原始日志/版本 SHA/Oracle 的不可伪造或可复核记录；标签本身不是证据 |
| `Golden Consumer` | 干净 Win10 x64 真机 + 当前目标 smc-copilot Native Adapter 验证；不等于 Stub 测试 |

# 6. System Context

## 6.1 Context Diagram

```text
                                     BUILD MACHINE (NETWORK ALLOWED)
  Fixed source SHA + uv.lock + extras + tools
                      │
          hermes-builder/Build.ps1
                      │
       offline payload + manifest/SHA/signature
                      │
                ┌─────┴────────────────────┐
                │                          │
          Hermes-Core.msi            Hermes-Setup.exe
                │                (Tauri + embedded Core MSI)
                │                          │
        Enterprise per-user       Interactive end-user
                │                          │
        msiexec /i (files-only) ────────────┘
                │
         MSI PRODUCT COMMITTED ── Windows Installer SOT
                │
     HermesRuntimeInit.exe --initialize
                │
        offline uv sync at final path
                │
       CLI version + dependency checks
                │
    runtime-receipt-v2.json (Bootstrap SOT)
                │
         Hermes Gateway CLI / smc-copilot Native Adapter
                │
         Diagnostics / Evidence (outside MSI payload)
```

## 6.2 Boundary

- **Inside**：固定版本构建、MSI 文件事务、Runtime 初始化/修复、Install UI、诊断。
- **Outside**：NodeDeskClaw 账号模型策略、Agent 主线自主升级、SYSTEM 安装、模型在线推理。
- **External dependencies**：构建阶段可访问固定源码/依赖仓库；终端 `Core MSI + Bootstrap` 不访问互联网。
- **Trusted inputs**：Release Manifest 的 MSI SHA、runtime-manifest 的 Ed25519 验签、Windows 当前身份、实际 MSI ProductCode；不信任用户 PATH、未签名缓存、自定义 HERMES_HOME 路径、远程响应。本轮不把 Authenticode 当作信任输入。
- **Executable distribution design (DESIGN_DECIDED)**：构建顺序 `Rust Engine → HermesRuntimeInit.exe（本轮无 Authenticode）→ MSI Payload → Core MSI → Tauri Setup EXE(内嵌 Core MSI)`，避免把 Setup.exe 同时嵌入它自身所承载的 MSI，造成递归打包。Direct MSI 包含 Init.exe，不含 Tauri GUI。发布两种入口但同一 MSI SHA。本轮 PE 无组织证书不得失败。

# 7. Authoritative State / SOT

| State | Role | Authoritative? | Writer | Reader | 自动覆盖 |
|---|---|---|---|---|---|
| `dist/release-manifest-v2.json` | DESIRED_STATE | YES（构建输出） | Builder | Setup/Engine/QA | 不可在终端修改 |
| `MSI ProductCode/UpgradeCode` 注册 | OBSERVED_STATE（Payload installed） | YES（Windows Installer） | msiexec | Setup/Engine/OPSI | 仅 msiexec |
| 程序文件+`runtime-manifest.json` | OBSERVED_STATE | NO（可被验证） | MSI | Preflight/Bootstrap | MSI Repair/Upgrade |
| `state/runtime-receipt-v2.json` | LAST_APPLIED_STATE（CLI ready） | YES（Runtime 初始化） | Init Engine | Setup/Runtime Probe | 仅完整验证成功后替换 |
| `state/bootstrap-operation-v2.json` | RUNTIME_STATE（当前操作） | YES（仅单操作进行中） | Init Engine | GUI/CLI/Support | 操作独占更新 |
| 当前 Gateway PID + 健康探针 | OBSERVED_STATE | NO（即时观测） | Hermes Runtime | Init/GUI | 只读 |
| 用户 `config.yaml/.env` | USER_OWNED | YES（用户/Agent） | Hermes Setup/用户 | Runtime | v2 安装不覆盖 |
| `runtime-provider-*.json` | USER_OWNED | YES（Desktop 业务侧） | smc-copilot | Provider Orchestrator | 安装器不覆盖 |
| `InstallerLogs/<operation_id>` | EVIDENCE_STATE | YES（该操作日志） | Setup/Init | Support/QA | 不覆写历史 operation |
| `state/bundle-install.json`（v1） | 旧状态 | NO（仅迁移输入） | v1 初始化 | v2 检测器 | 不写新 v1 schema |

**权威优先级**：MSI 未注册 → `ABSENT`，不得判 `PAYLOAD_INSTALLED`。已注册、无 READY receipt、也无「已动过 Generated」的失败 operation record → `PAYLOAD_INSTALLED`（Direct MSI 成功后、尚未 `--initialize` 即此态）。已注册且 HermesRoot 仍有待替换文件 / RM reboot-required → `PAYLOAD_INSTALLED_REBOOT_REQUIRED`。receipt 存在但 SHA/CLI 观测不匹配，或上次 Init/Repair 已对 Generated 失败 → `REPAIR_REQUIRED`。仅文件存在、CLI 可执行但不匹配 release identity，也不可自动判 READY。`--status` 可计算状态但 **MUST NOT** 创建、修改或删除任何状态/配置/注册表/锁/日志文件；诊断落盘只允许 `--export-diagnostics`。

# 8. State Machine

```text
ABSENT
  ├─ setup/install preflight accepted → INSTALLING_PAYLOAD
  │     ├─ MSI exit 0 or 3010 AND product registered → PAYLOAD_INSTALLED
  │     └─ MSI failure/rollback → ABSENT or PREVIOUS_PAYLOAD_INSTALLED
  └─ invalid identity/path/locks → BLOCKED (no payload mutation)
PAYLOAD_INSTALLED
  ├─ initialize (exclusive) → INITIALIZING
  │     ├─ verification+receipt committed → READY
  │     ├─ Generated mutation 已发生后的失败 → REPAIR_REQUIRED
  │     └─ 零 Generated mutation 的预检 BLOCK → 仍为 PAYLOAD_INSTALLED
  ├─ direct MSI only → PAYLOAD_INSTALLED (not READY)
  ├─ HermesRoot pending replace / RM reboot-required → PAYLOAD_INSTALLED_REBOOT_REQUIRED
  └─ uninstall MSI → ABSENT (user data retained)
PAYLOAD_INSTALLED_REBOOT_REQUIRED
  ├─ 重启后 pending 消失 → PAYLOAD_INSTALLED（然后显式 Init）
  └─ 未重启就 Init → REBOOT_REQUIRED，零 Generated mutation
REPAIR_REQUIRED
  ├─ --initialize（收敛，venv 门通过则跳过 uv）→ INITIALIZING → READY or REPAIR_REQUIRED
  ├─ --repair（强制 T0 重建 Generated）→ INITIALIZING → READY or REPAIR_REQUIRED
  └─ uninstall MSI → ABSENT (diagnostics retained)
READY
  ├─ health mismatch（探针观测）→ REPAIR_REQUIRED
  ├─ repeat same identity --initialize → READY (no venv mutation)
  ├─ --repair → INITIALIZING（强制重建）
  ├─ 零 mutation 预检 BLOCK（占用/磁盘等）→ 仍为 READY，last error 记在 operation record
  └─ MSI major upgrade (preflight) → PAYLOAD_INSTALLED → INITIALIZING
```

- `BLOCKED` 是一次安装操作结果，不是改写用户 Runtime 的永久状态。零 Generated mutation 的 BLOCK **不得**把 `PAYLOAD_INSTALLED` 或 `READY` 改写成 `REPAIR_REQUIRED`。
- `3010` 表示 Windows Installer 需重启：Setup / 企业包装 **MUST NOT** 调用 Init。Init 用 HermesRoot 的 `PendingFileRenameOperations` / Restart Manager reboot-required 自行判定，**不得**把「机器任意待重启」（例如 Windows Update）当成 Hermes 阻断。UI 不能显示 READY。
- 非法转移：`ABSENT→READY`、`INSTALLING_PAYLOAD→READY`、`REPAIR_REQUIRED→READY`（没有验证）都返回 `STATE_TRANSITION_DENIED`，0 Program/Runtime mutation。
- `INITIALIZING` 只能有一个 operation id 持有本用户本 root 的独占锁文件 `%LOCALAPPDATA%\hermes\state\runtime-init.lock`（字段：`operationId`、pid、exe、`startedAtUtc`）。**没有墙钟超时。** holder PID 仍在且 exe 匹配 → `INSTALL_BUSY`，不得强制覆盖。`--status` 绝不创建/替换/删除该锁；`--initialize`/`--repair` 仅在 PID 不存在或 exe 不匹配时用新 `operationId` 替换后继续。
- App 或机器异常终止后，下次 `--status` 若观察到锁或操作记录为 `INITIALIZING` 且持有者进程不存在，**只上报 `runtimeState=INTERRUPTED`、`errorCode=ENGINE_INTERRUPTED`，并建议 `--initialize` 收敛或 `--repair` 重建**；`--status` 不自动修复、不收尸锁。

# 9. Data / Schema Contract

## 9.1 Schema 列表

| Schema ID | Version | Persisted path | additionalProperties | Authority | 兼容规则 |
|---|---:|---|---|---|---|
| `smc.hermes.release-manifest` | 2 | dist/release-manifest-v2.json + Setup embedded copy | false | Build | v2 reader 不接受未知 version |
| `smc.hermes.runtime-manifest` | 2 | `%LOCALAPPDATA%\hermes\runtime-manifest-v2.json` + `.sig` | false | Signed MSI Payload | 未签名 / 不识别版本拒绝运行 |
| `smc.hermes.runtime-receipt` | 2 | `%LOCALAPPDATA%\hermes\state\runtime-receipt-v2.json` | false | Init | 不将 v1 marker 当作 READY |
| `smc.hermes.operation` | 2 | `%LOCALAPPDATA%\hermes\state\bootstrap-operation-v2.json` | false | Init | 只存当前操作简报；审计在日志目录 |
| `smc.hermes.diagnostic` | 2 | `InstallerLogs/<operation_id>/diagnostics.json` | false | Installer/Init | 任何失败也生成，可写失败则 `DIAGNOSTICS_UNAVAILABLE` |
| `smc.hermes.evidence` | 1 | `evidence/<AC>/<run>.json` | false | QA | 不允许只写 `{status:PASS}` |

## 9.2 Release Manifest（完整示例，值为示意且构建时须真实填充）

```json
{
  "schemaVersion": 2,
  "installerVersion": "2.0.0",
  "msiProductVersion": "2.0.0",
  "msiUpgradeCode": "7F5E14D8-61A1-48D3-9EA5-503A84C61F6F",
  "msiSha256": "<64-hex-at-build>",
  "source": {
    "repository": "https://github.com/loudon84/copilot-hermes.git",
    "commit": "041b6985a00d01b54f830c1607dd370007a306bf",
    "agentVersion": "0.21.0"
  },
  "runtime": {
    "pythonVersion": "3.11",
    "architecture": "x64",
    "offline": true,
    "payloadTreeSha256": "<64-hex-at-build>",
    "uncompressedPayloadBytes": 0,
    "venvEstimatedBytes": 0
  },
  "policy": {"autoUpdateAgent": false, "requiresInteractiveUser": true}
}
```

`venvEstimatedBytes` **构建时 MUST 填成构建机完成离线 uv 重建后 venv 文件大小求和的整数**（不含目录元数据）；`uncompressedPayloadBytes` **MUST** 等于已签名 `runtime-manifest-v2.json` 文件列表的 size 之和。上例 0 只表示字段形状，在发布产物中这两个整数都必须大于 0，且两者必须与 runtime-manifest 对账，对不上则构建失败、不得发布。Setup 预检的磁盘公式只用 Manifest 字段，禁止另估 MSI 体积。`<...>` 是示例占位符，正式 Manifest 中禁止出现。Manifest 按 JSON Schema 严格校验必填、enum、SHA、Commit、版本、URI，`additionalProperties=false`；本版无用户可设置的默认覆盖值。

## 9.3 Runtime Receipt（成功后原子发布）

```json
{
  "schemaVersion": 2,
  "runtimeState": "READY",
  "installerVersion": "2.0.0",
  "agentVersion": "0.21.0",
  "sourceCommit": "041b6985a00d01b54f830c1607dd370007a306bf",
  "payloadTreeSha256": "<manifest-payload-tree-hash>",
  "msiProductCode": "<actual-msi-guid>",
  "activeProfile": "default",
  "cliVersionFirstLine": "Hermes Agent v0.21.0 (2026.8.31)",
  "verifiedAtUtc": "<RFC3339>",
  "operationId": "<UUID-v4>"
}
```

要求：`runtimeState` enum 只能为 `READY`（失败状态存 operation record，不伪造成功 receipt）；`activeProfile` 固定 `default`，避免在安装器里悄悄接管 Named Profiles。全部 SHA 与构建 Manifest 相等；`verifiedAtUtc` 是 UTC RFC3339。若目录已有同 schema 的 receipt 且身份一致，重复 verify 只更新日志，不重写 receipt。

## 9.4 Operation Record / Error Envelope

```json
{
  "schemaVersion": 2,
  "operationId": "<UUID-v4>",
  "phase": "INITIALIZING",
  "status": "RUNNING",
  "startedAtUtc": "<RFC3339>",
  "updatedAtUtc": "<RFC3339>",
  "exitCode": null,
  "errorCode": null,
  "diagnosticsDir": "<absolute-path>",
  "manifestTreeSha256": "<64-hex>"
}
```

`phase` enum = `PREFLIGHT|MSI_INSTALL|INITIALIZING|VERIFYING|COMPLETED|FAILED|INTERRUPTED|REPAIRING`；`status` enum = `RUNNING|PASS|FAIL|BLOCKED|INTERRUPTED`；`exitCode` 为 int 或 null；`errorCode` enum 来自 §14；error-only 文件 `diagnostics.json` 还包含 `lastStage`, `underlyingProcessExit`, `lastStderrLines`, `supportGuidance`，但不得含 Token/API Key。Schema 不允许附加字段；读取旧版本返回 `OPERATION_SCHEMA_UNSUPPORTED` 而非猜字段。

## 9.5 CLI interface

```text
Hermes-Setup.exe                          # GUI; MSI embedded
HermesRuntimeInit.exe --initialize --quiet --manifest <absolute-manifest-path>
HermesRuntimeInit.exe --repair --quiet --manifest <absolute-manifest-path>
HermesRuntimeInit.exe --status --json
HermesRuntimeInit.exe --export-diagnostics --output <directory> [--operation-id <UUID>]
```

- `--initialize`：把本机收敛到 READY。venv 门通过（活路径 `venv\Scripts\hermes.exe` 存在，且 `import yaml, openai` 与 `hermes.exe --version` 均满足 Agent `0.21.0`）则 **MUST NOT** 改名/重建 venv，从第一个失败阶段继续。从未初始化则全量 Init。同一身份 READY 则只校验并退出 0。GUI「重试」MUST 调用此命令。
- `--repair`：占用检查通过后，对 Generated Scope 做 T0 改名并重建（即使 CLI 当前能跑）。GUI「重建运行时」MUST 调用此命令。本版 **MUST NOT** 提供 `--purge-generated-runtime`。
- `--status`：只读 stdout JSON，字段 `schemaVersion/runtimeState/installerVersion/agentVersion/sourceCommit/errorCode/lastOperationId`。**MUST NOT** 创建、修改或删除任何文件（含锁与诊断目录）。Receipt 的 `runtimeState` 只能是 `READY`；下表是探针枚举与进程退出码：

| `--status` `runtimeState` | 退出码 |
|---|---|
| `READY` | 0 |
| `ABSENT` | 20 |
| `PAYLOAD_INSTALLED` | 21 |
| `REPAIR_REQUIRED` | 22 |
| `INTERRUPTED` | 23 |
| `INITIALIZING` | 24 |
| `PAYLOAD_INSTALLED_REBOOT_REQUIRED` | 25 |

- `--initialize` / `--repair` 退出码：到达 READY = 0；产品未注册 = 20；`INSTALL_BUSY` = 24；`REBOOT_REQUIRED` = 25；其他失败 = **1**。`--quiet` 同样向 stdout 打印一行 JSON。失败 envelope 为 `{"ok":false,"errorCode":"...","operationId":"...","diagnosticsDir":"..."}`。`UV_SYNC_FAILED` / `RUNTIME_IN_USE` / `SKILL_OWNERSHIP_CONFLICT` 等只靠 `errorCode` 区分。PowerShell 包装或企业工具不得把该退出码吞掉。
- `--export-diagnostics`：复制 `InstallerLogs\<operationId>\`（默认最近一次，或 `--operation-id`）、`runtime-receipt-v2.json`、`bootstrap-operation-v2.json`、`enterprise-skill-ledger-v2.json` 以及 redacted 诊断。**MUST NOT** 复制 `hermes-agent\venv`、`state\runtime-backups`、`.env` 原文、用户 sessions/memories。`--output` 目录已存在且非空 → `EXPORT_TARGET_NOT_EMPTY`，零覆盖。
- `--manifest` 必须是当前 MSI Program Payload 释放在 `<HermesRoot>\runtime-manifest-v2.json` 的规范绝对路径；Init 必须先验证相邻 `.sig` 的 Ed25519 签名，才允许使用其 file list；GUI 必须先以外层 Release Manifest 核对 MSI SHA，再传此内部 Runtime Manifest，拒绝任意用户指定的未签名网络资源或仓库 JSON。企业与 GUI 调用 Init 必须使用 `%LOCALAPPDATA%\hermes\bootstrap\HermesRuntimeInit.exe` 绝对路径，不得依赖用户 PATH（PATH 仅在 READY 后由 Init 附加）。

# 10. Requirement Unit — 完整实施需求

下方每个 REQ 均具有 Goal / Normative / Inputs / Preconditions / SOT / State Transition / Allowed & Forbidden Side Effects / Ownership / Idempotency / Failure / Postconditions / Invariants / Error Codes / Acceptance / Evidence，构成 Plan 的最小实现单位。

## REQ-SRC-001 — 源码与版本身份锁定

### Goal
避免安装器升级夹带 Agent 更新。

### Normative Requirement
Release 构建 MUST 使用 `loudon84/copilot-hermes@041b6985a00d01b54f830c1607dd370007a306bf` 和 Agent `0.21.0`；MUST 把 MSI ProductVersion 改为 `2.0.0`，保留现有 UpgradeCode；MUST NOT 读取 `smc-copilot/hermes-agent/main` 作为动态打包源。

### Inputs
build-config.json, Git HEAD, version policy

### Preconditions
构建机有固定源码或允许 clone 固定 SHA

### Authoritative State
SOT：builder/build-info+Git HEAD；Derived：仅可由 Read-only probe 计算瞬时状态。

### State Transition
`SOURCE_VERIFIED → BUILD_READY`；所有变更记录 `operationId`。

### Allowed Side Effects
ALLOW：构建工作目录、release metadata。

### Forbidden Side Effects
DENY：用户 Hermes Root、Git main 动态引用。

### Ownership Scope
`FILE: build artifacts`。

### Idempotency
同样源码和锁定的版本配置重建的 source identity 不变。

### Failure Semantics
源码不匹配构建失败，`SOURCE_REF_MISMATCH` 或 `SOURCE_DIRTY`。`retryable`：仅在消除阻断输入、保持原身份或显式修复后重试；不对任意失败自动无限重试。

### Postconditions
构建信息来源唯一，agentVersion 与 installerVersion 分开。

### Invariants
`INV-ID-001`。

### Error Codes
`SOURCE_REF_MISMATCH`, `SOURCE_DIRTY`。

### Acceptance
`A-SRC-001`（详见 §20）。

### Evidence
Required test：`TEST-A-SRC-001`；Required artifact：`EVID-A-SRC-001.json`；原始 CLI/MSI/Engine 日志与 Release SHA 的引用必须在 Evidence 中填写。

## REQ-BUILD-001 — 离线 Bundle 与构建证据

### Goal
把运行依赖错误从终端提前到构建门槛。

### Normative Requirement
Builder MUST 完成 uv 离线重建、两个必要 Python import、CLI 版本验证；MUST 形成列出 Program Payload 全部文件的 tree digest、`uncompressedPayloadBytes`（等于 runtime-manifest 文件 size 之和）、`venvEstimatedBytes` 和离线构建证据；两字段必须 `>0` 且对账，对不上则构建失败。MUST NOT 发布缺少必需 cache/二进制的 MSI。

### Inputs
Source SHA、uv.lock、extras、Build.ps1

### Preconditions
Windows x64 构建节点已提供 NuGet/WiX 和构建阶段联网

### Authoritative State
SOT：release-manifest-v2.json + payload manifest；Derived：仅可由 Read-only probe 计算瞬时状态。

### State Transition
`BUILD_READY→BUNDLE_VERIFIED`；所有变更记录 `operationId`。

### Allowed Side Effects
ALLOW：payload/、dist/、evidence/。

### Forbidden Side Effects
DENY：目标机器文件、用户内容、发布失败后伪造 PASS。

### Ownership Scope
`FILE: 生成的 payload/dist`。

### Idempotency
重复构建验证逻辑一致；digest 反映真实字节。

### Failure Semantics
离线重建失败则不发布安装包，`BUNDLE_INCOMPLETE`。`retryable`：仅在消除阻断输入、保持原身份或显式修复后重试；不对任意失败自动无限重试。

### Postconditions
必需文件数>0、所有 hashes 有值，离线证明可复核。

### Invariants
`INV-BUNDLE-001`。

### Error Codes
`BUNDLE_INCOMPLETE`, `BUNDLE_HASH_MISMATCH`。

### Acceptance
`A-BUILD-001`, `A-BUILD-002`（详见 §20）。

### Evidence
Required test：`TEST-A-BUILD-001`, `TEST-A-BUILD-002`；Required artifact：`EVID-A-BUILD-001.json`, `EVID-A-BUILD-002.json`；原始 CLI/MSI/Engine 日志与 Release SHA 的引用必须在 Evidence 中填写。

## REQ-MSI-001 — MSI Files-Only

### Goal
避免 uv 初始化失败引发 MSI Payload 全回滚。

### Normative Requirement
`Package.wxs` MUST 移除 `SetInitializeHermes/InitializeHermes`、`SetPreflightHermes/PreflightHermes` 长时 Custom Action；MUST 只使用标准 MSI 文件、注册和标准安装生命周期；MUST NOT 直接运行 uv、Node、上游 install.ps1 或删除用户 State。

### Inputs
Program Payload、UpgradeCode、UserSID

### Preconditions
Current User 非 SYSTEM，MSI SHA 与 Release Manifest 一致

### Authoritative State
SOT：MSI 产品注册状态；Derived：仅可由 Read-only probe 计算瞬时状态。

### State Transition
`ABSENT→INSTALLING_PAYLOAD→PAYLOAD_INSTALLED`；所有变更记录 `operationId`。

### Allowed Side Effects
ALLOW：MSI 管理的静态文件和产品注册。

### Forbidden Side Effects
DENY：生成 venv、Gateway、config.yaml、.env、runtime-provider JSON。

### Ownership Scope
`WHOLE_RESOURCE: Program Payload`。

### Idempotency
重复安装由 MSI Repair/MajorUpgrade 语义处理；不得重入 Bootstrap。

### Failure Semantics
标准 MSI 事务失败回滚静态文件，错误 `MSI_INSTALL_FAILED`。`retryable`：仅在消除阻断输入、保持原身份或显式修复后重试；不对任意失败自动无限重试。

### Postconditions
`msiexec` 成功后只表示 Payload Installed。

### Invariants
`INV-MSI-001`。

### Error Codes
`MSI_INSTALL_FAILED`, `INSTALL_IDENTITY_DENIED`。

### Acceptance
`A-MSI-001`, `A-MSI-002`（详见 §20）。

### Evidence
Required test：`TEST-A-MSI-001`, `TEST-A-MSI-002`；Required artifact：`EVID-A-MSI-001.json`, `EVID-A-MSI-002.json`；原始 CLI/MSI/Engine 日志与 Release SHA 的引用必须在 Evidence 中填写。

## REQ-ENTRY-001 — 单文件 GUI 与企业命令入口

### Goal
既支持双击易用性，也支持 OPSI 透明部署。

### Normative Requirement
Release MUST 同时发布内嵌同一 Core MSI 的 Tauri `Hermes-Setup.exe` 和单独 MSI；Direct MSI MUST 安装 `HermesRuntimeInit.exe`，但不自动初始化；GUI 必须先执行 MSI、确认产品注册、再调用 Init；MUST NOT 把 Setup.exe 本体装回其内嵌 MSI 导致递归打包。

### Inputs
Release Manifest、embedded MSI、用户/OPSI 调用参数

### Preconditions
Exe/MSI SHA 匹配，当前身份可写 LocalAppData

### Authoritative State
SOT：MSI registry + operation result；Derived：仅可由 Read-only probe 计算瞬时状态。

### State Transition
`ENTRY→PREFLIGHT→MSI_INSTALL→INIT`；所有变更记录 `operationId`。

### Allowed Side Effects
ALLOW：受管 installer cache 与 GUI 日志。

### Forbidden Side Effects
DENY：动态下载 MSI、下载 Code、间接执行安装脚本。

### Ownership Scope
`GENERATED_ONLY: installer cache`。

### Idempotency
重复入口检查 MSI 产品状态并显示修复而不是盲目二次安装。

### Failure Semantics
来源错配阻断，`RELEASE_IDENTITY_MISMATCH`。`retryable`：仅在消除阻断输入、保持原身份或显式修复后重试；不对任意失败自动无限重试。

### Postconditions
`Core MSI` SHA 与 embedded 包相同。

### Invariants
`INV-ID-002`。

### Error Codes
`RELEASE_IDENTITY_MISMATCH`。

### Acceptance
`A-ENTRY-001`（详见 §20）。

### Evidence
Required test：`TEST-A-ENTRY-001`；Required artifact：`EVID-A-ENTRY-001.json`；原始 CLI/MSI/Engine 日志与 Release SHA 的引用必须在 Evidence 中填写。

## REQ-PRE-001 — 先行只读 Preflight

### Goal
将常见 Win10 阻断在 MSI File Mutation 之前。

### Normative Requirement
GUI/企业预检 MUST 在 `msiexec` 前检查交互身份、OS/架构、路径、NTFS/同卷重命名能力、可用空间、MSI SHA、已有安装状态；MUST NOT 提前修改 Hermes 用户模型文件；Setup 前空间阈值为 `max(8GiB,ceil(1.5*(uncompressedPayloadBytes+venvEstimatedBytes)))`，字段来自已签名 Release Manifest。`--initialize`/`--repair` 在第一次 Generated mutation 前 MUST 重测可用空间：强制重建 Generated 时 `2 * venvEstimatedBytes + 512MiB`；首次创建 venv 时 `1 * venvEstimatedBytes + 512MiB`；跳过 `UV_SYNC` 的收敛只要求 `512MiB`。不足 → `DISK_SPACE_INSUFFICIENT`，零 Generated mutation。

### Inputs
OS properties、manifest、current user、GetDiskFreeSpace

### Preconditions
Release Manifest 校验成功

### Authoritative State
SOT：OS/FS observed + product registration；Derived：仅可由 Read-only probe 计算瞬时状态。

### State Transition
`PREFLIGHT→PASS/BLOCKED`；所有变更记录 `operationId`。

### Allowed Side Effects
ALLOW：新 operationId 日志与只读 OS 访问。

### Forbidden Side Effects
DENY：改写现有 config/env 或删除程序文件。

### Ownership Scope
`NONE (diagnostics generated only)`。

### Idempotency
重复预检 0 用户/程序数据改动。

### Failure Semantics
任何未通过：退出 `PRECHECK_FAILED`（具体子码），无 MSI 执行。`retryable`：仅在消除阻断输入、保持原身份或显式修复后重试；不对任意失败自动无限重试。

### Postconditions
通过不等于 Runtime Ready。

### Invariants
`INV-PRE-001`。

### Error Codes
`PRECHECK_FAILED`, `DISK_SPACE_INSUFFICIENT`, `UNSUPPORTED_FILESYSTEM`, `RUNTIME_IN_USE`, `REBOOT_REQUIRED`。

### Acceptance
`A-PRE-001`, `A-PRE-002`（详见 §20）。

### Evidence
Required test：`TEST-A-PRE-001`, `TEST-A-PRE-002`；Required artifact：`EVID-A-PRE-001.json`, `EVID-A-PRE-002.json`；原始 CLI/MSI/Engine 日志与 Release SHA 的引用必须在 Evidence 中填写。

## REQ-GW-001 — Gateway 与 venv 占用处理

### Goal
防止占用中的 EXE/venv 被删除或改写。

### Normative Requirement
任何 Runtime 变更以及 Setup 启动 `msiexec` 之前 MUST 对 `hermes-agent\venv` 整树和 `bin\hermes*.exe` 做 holder 扫描（Restart Manager 注册这些路径，并辅以同用户已加载模块路径）。命中任何 PID（包括 `python.exe` 加载 `.pyd`、Gateway、CLI、MCP 子进程）MUST 以 `RUNTIME_IN_USE` 阻断，报告 PID 与完整可执行路径，**不启动** msiexec、不改 venv。MUST NOT 按进程名白名单过滤、MUST NOT 强制 taskkill、MUST NOT 仅凭端口号杀进程。检视失败 MUST 返回 `PROCESS_INSPECTION_FAILED` 并禁止改 venv。无 venv 且无 `bin\hermes*.exe` 时可跳过占用检查。对 venv / `bin\hermes*.exe` 的 rename、delete、overwrite 若返回 `ERROR_ACCESS_DENIED` 或 sharing violation，一律 `RUNTIME_IN_USE`（能列出 PID 就列出），不得记成 `UV_SYNC_FAILED`。

### Inputs
venv 路径、`bin\hermes*.exe`、Restart Manager / 模块路径、进程表

### Preconditions
目标 Root 所属用户身份确认

### Authoritative State
SOT：live process observation；Derived：仅可由 Read-only probe 计算瞬时状态。

### State Transition
`PREFLIGHT→BLOCKED or INITIALIZING`；所有变更记录 `operationId`。

### Allowed Side Effects
ALLOW：只读进程扫描与日志。

### Forbidden Side Effects
DENY：强制结束进程、越权访问其他 root。

### Ownership Scope
`NONE`。

### Idempotency
再次检测占用消失才执行。

### Failure Semantics
检测权限不足：`PROCESS_INSPECTION_FAILED`，不盲目继续更改已有 venv。`retryable`：仅在消除阻断输入、保持原身份或显式修复后重试；不对任意失败自动无限重试。

### Postconditions
对未安装 venv 可跳过占用检查。

### Invariants
`INV-PROC-001`。

### Error Codes
`RUNTIME_IN_USE`, `PROCESS_INSPECTION_FAILED`。

### Acceptance
`A-GW-001`（详见 §20）。

### Evidence
Required test：`TEST-A-GW-001`；Required artifact：`EVID-A-GW-001.json`；原始 CLI/MSI/Engine 日志与 Release SHA 的引用必须在 Evidence 中填写。

## REQ-PY-001 — 可靠的离线 Python 初始化

### Goal
在最终用户路径明确重建并验证完整 Hermes CLI。

### Normative Requirement
Init MUST 通过受控 argv 调用随包 uv，清理继承 `UV_*`/`VIRTUAL_ENV`，使用 `--offline --frozen --link-mode copy`、固定 Python 与项目路径；MUST 验证 `import yaml,openai`、venv 与（receipt 前最后阶段的）`bin\hermes.exe --version`；MUST NOT 调用上游 install.ps1、npm/node、下载 CLI；路径含空格/中文 MUST 使用 Windows 正确 argv 编码。`--initialize` 跳过 `UV_SYNC` 当且仅当活路径 `venv\Scripts\hermes.exe` 存在且上述 import 与 venv `--version` 均已满足 Agent `0.21.0`；`state\runtime-backups` 中的失败树 MUST NOT 当活 venv。`UV_SYNC_FAILED` 只在随包 `uv.exe` **已经启动**且进程退出码非 0 时使用。

### Inputs
runtime-manifest、HermesRoot、uv/python/lock/cache

### Preconditions
MSI Payload 已注册、Root 受信且可写、无占用

### Authoritative State
SOT：Installed payload + uv output + CLI verification；Derived：仅可由 Read-only probe 计算瞬时状态。

### State Transition
`PAYLOAD_INSTALLED→INITIALIZING→VERIFYING`；所有变更记录 `operationId`。

### Allowed Side Effects
ALLOW：仅 `hermes-agent/venv`、`bin/hermes*.exe` 及日志。

### Forbidden Side Effects
DENY：用户 config.yaml、.env、network、未知文件。

### Ownership Scope
`GENERATED_ONLY: venv and bin launchers`。

### Idempotency
相同 identity 且有效 Receipt/CLI 时不重建。

### Failure Semantics
uv/CLI/import 失败 → REPAIR_REQUIRED，保留诊断，参照事务恢复。`retryable`：仅在消除阻断输入、保持原身份或显式修复后重试；不对任意失败自动无限重试。

### Postconditions
每个成功初始化都双路径 CLI 版本匹配 Agent 0.21.0。

### Invariants
`INV-CLI-001`。

### Error Codes
`UV_SYNC_FAILED`, `HERMES_CLI_MISSING`, `HERMES_CLI_VERIFY_FAILED`, `RUNTIME_IN_USE`。

### Acceptance
`A-PY-001`, `A-PY-002`（详见 §20）。

### Evidence
Required test：`TEST-A-PY-001`, `TEST-A-PY-002`；Required artifact：`EVID-A-PY-001.json`, `EVID-A-PY-002.json`；原始 CLI/MSI/Engine 日志与 Release SHA 的引用必须在 Evidence 中填写。

## REQ-TXN-001 — 独立 Runtime 事务与 T0 恢复

### Goal
初始化失败不引起 MSI 回滚，又不破坏既有 Runtime。

### Normative Requirement
Init MUST 在首次受管 Runtime mutation 前采集 T0（原 venv/`bin/hermes*.exe`/receipt/用户环境变量/skill ledger），对旧 venv 先校验进程空闲、同卷改名保留备份，再在原路径创建新 venv；活路径永远只有 `hermes-agent\venv`。`--initialize` 在 venv 门通过时 MUST NOT 改名重建 venv。失败 MUST 按 §14.3 补偿集处理或标记 ROLLBACK_FAILED 并保留备份；MUST NOT 把 MSI 注册状态当作 Runtime READY；MUST NOT 在失败路径上 `Remove-Item` 删除半成品。

### Inputs
T0 owned paths、manifest、operation id

### Preconditions
Product installed and preflight pass

### Authoritative State
SOT：runtime receipt + explicit rollback journal；Derived：仅可由 Read-only probe 计算瞬时状态。

### State Transition
`INITIALIZING→READY/REPAIR_REQUIRED/ROLLBACK_FAILED`；所有变更记录 `operationId`。

### Allowed Side Effects
ALLOW：Runtime generated scope 与 T0 backup。

### Forbidden Side Effects
DENY：用户文件、MSI payload 文件、其他 profile。

### Ownership Scope
`GENERATED_ONLY with T0 provenance`。

### Idempotency
重复 READY 无变更；REPAIR 必须生成独立 operationId。

### Failure Semantics
新装失败无旧 T0 → 把本次生成目录同卷改名到 `state\runtime-backups\<op>\`，**禁止删除**；不得被下次初始化当作上次成功 venv。默认只保留最近一次失败树；`RUNTIME_ROLLBACK_FAILED` 备份除外，必须人工确认后才删。旧装恢复失败保持备份。Skill/Env/bin 阶段失败 **MUST NOT** 拆掉已通过门的 venv。`retryable`：仅在消除阻断输入、保持原身份或显式修复后重试；不对任意失败自动无限重试。

### Postconditions
成功 receipt 在全部 CLI 校验后原子替换；失败绝不写 READY。

### Invariants
`INV-TXN-001|INV-TXN-002`。

### Error Codes
`RUNTIME_ROLLBACK_FAILED`, `RUNTIME_INITIALIZATION_FAILED`, `RECEIPT_COMMIT_FAILED`。

### Acceptance
`A-TXN-001`, `A-TXN-002`（详见 §20）。

### Evidence
Required test：`TEST-A-TXN-001`, `TEST-A-TXN-002`；Required artifact：`EVID-A-TXN-001.json`, `EVID-A-TXN-002.json`；原始 CLI/MSI/Engine 日志与 Release SHA 的引用必须在 Evidence 中填写。

## REQ-OWN-001 — 用户与 Program Ownership

### Goal
避免 MSI/Bootstrap/桌面端互相覆盖。

### Normative Requirement
v2 MUST 将 PROGRAM_MANAGED、GENERATED_ONLY、USER_OWNED 分开；初始化和卸载 MUST NOT 覆盖已有 `config.yaml/.env/SOUL.md`、Sessions、Memories、runtime-provider JSON；首装只允许以 CreateNew 创建缺失模板，目标已存在（即使空文件）保持原字节。

### Inputs
Existing Hermes Root, release inventory, owner ledger

### Preconditions
路径 canonicalize 且安全

### Authoritative State
SOT：User-owned bytes are SOT；Derived：仅可由 Read-only probe 计算瞬时状态。

### State Transition
`ABSENT→INIT_SEED or PRESERVE`；所有变更记录 `operationId`。

### Allowed Side Effects
ALLOW：缺失初始模板（exclusive create）、安装器自己的 marker。

### Forbidden Side Effects
DENY：已有用户数据（含空文件）。

### Ownership Scope
`USER_OWNED file scope`。

### Idempotency
第二次初始化用户内容 SHA 不变。

### Failure Semantics
ownership 不明则 PRESERVE + `OWNERSHIP_UNKNOWN`。`retryable`：仅在消除阻断输入、保持原身份或显式修复后重试；不对任意失败自动无限重试。

### Postconditions
用户配置的 SHA 前后相同。

### Invariants
`INV-OWN-001`。

### Error Codes
`OWNERSHIP_UNKNOWN`, `USER_DATA_CONFLICT`。

### Acceptance
`A-OWN-001`, `A-OWN-002`（详见 §20）。

### Evidence
Required test：`TEST-A-OWN-001`, `TEST-A-OWN-002`；Required artifact：`EVID-A-OWN-001.json`, `EVID-A-OWN-002.json`；原始 CLI/MSI/Engine 日志与 Release SHA 的引用必须在 Evidence 中填写。

## REQ-SKILL-001 — 企业 Skills 合并冲突语义

### Goal
防止重试/升级静默覆盖用户 Skill。

### Normative Requirement
企业 Skill 安装 MUST 把 last-applied SHA 写入 `%LOCALAPPDATA%\hermes\state\enterprise-skill-ledger-v2.json`（Init 原子替换，schemaVersion=2，`additionalProperties=false`，属 Init Ledger 而非 USER_OWNED；卸载 MSI 不删）；同路径已存在且不属于同一企业来源时 MUST BLOCK 该路径，返回 `SKILL_OWNERSHIP_CONFLICT`；不得继续其他 Skills 的部分写入；如果同企业文件被用户改过则保留当前字节并 BLOCK。

### Inputs
enterprise/skills inventory、last-applied manifest

### Preconditions
skill path normalized and safe

### Authoritative State
SOT：skill ownership ledger + file bytes；Derived：仅可由 Read-only probe 计算瞬时状态。

### State Transition
`STAGED→MERGE_VERIFIED→APPLY or BLOCKED`；所有变更记录 `operationId`。

### Allowed Side Effects
ALLOW：仅企业来源且未漂移的文件。

### Forbidden Side Effects
DENY：用户自建 Skills、未知文件。

### Ownership Scope
`ENTRY per enterprise Skill`。

### Idempotency
完全相同 bytes 二次同步不写文件。

### Failure Semantics
冲突导致 Skill 子事务 0 mutation，**不得**发布 READY receipt；`--status` 为 `REPAIR_REQUIRED`，`errorCode=SKILL_OWNERSHIP_CONFLICT`。已建成且通过 venv 门的 `hermes-agent\venv` **MUST** 保留，供随后 `--initialize` 从 Skill 阶段继续；**MUST NOT** 为此拆 venv。`retryable`：仅在消除阻断输入、保持原身份或显式修复后重试；不对任意失败自动无限重试。

### Postconditions
Skills 不允许 last-writer-wins。

### Invariants
`INV-SKILL-001`。

### Error Codes
`SKILL_OWNERSHIP_CONFLICT`。

### Acceptance
`A-SKILL-001`（详见 §20）。

### Evidence
Required test：`TEST-A-SKILL-001`；Required artifact：`EVID-A-SKILL-001.json`；原始 CLI/MSI/Engine 日志与 Release SHA 的引用必须在 Evidence 中填写。

## REQ-ENV-001 — 用户环境变量所有权

### Goal
避免 MSI 回滚与初始化失败后留下错误 PATH。

### Normative Requirement
Bootstrap MUST 在 `IMPORT_VERIFY` 与 `CLI_VERIFY_VENV` 成功之后、`CLI_STAGE_BIN` 之前设置用户 `HERMES_HOME`、`HERMES_GIT_BASH_PATH` 和 PATH；先记录每项 T0 的完整原值；失败 MUST 恢复原值，仅移除由本次 Init 添加的精确 Path entry；MUST NOT 写系统级 PATH。PATH 指向的 `bin\` 在 Env 提交时已含 MSI 的 `uv.exe`；`bin\hermes.exe` 尚未落地。

### Inputs
User environment T0、HermesRoot、manifest

### Preconditions
CLI verified and no policy deny

### Authoritative State
SOT：HKCU environment；Derived：仅可由 Read-only probe 计算瞬时状态。

### State Transition
`VERIFYING→ENV_COMMITTED`；所有变更记录 `operationId`。

### Allowed Side Effects
ALLOW：当前用户上述 3 个值。

### Forbidden Side Effects
DENY：HKLM/System PATH、其他用户 Profile 环境。

### Ownership Scope
`FIELD: user env 3 keys`。

### Idempotency
再次运行相同值不增加 PATH 重复项。

### Failure Semantics
恢复失败生成 `ENV_ROLLBACK_FAILED` 与 recovery report。`retryable`：仅在消除阻断输入、保持原身份或显式修复后重试；不对任意失败自动无限重试。

### Postconditions
修改前后字段集合被限定。

### Invariants
`INV-ENV-001`。

### Error Codes
`ENV_ROLLBACK_FAILED`。

### Acceptance
`A-ENV-001`（详见 §20）。

### Evidence
Required test：`TEST-A-ENV-001`；Required artifact：`EVID-A-ENV-001.json`；原始 CLI/MSI/Engine 日志与 Release SHA 的引用必须在 Evidence 中填写。

## REQ-OBS-001 — 证据不随 MSI 回滚消失

### Goal
每次失败都能定位到原生错误而非只看到 1603。

### Normative Requirement
Setup/Init MUST 在第一个外部操作前创建唯一 operationId 日志目录于 `%LOCALAPPDATA%\SMC\HermesInstaller\InstallerLogs\<UUID>`，持续落盘 `msiexec.log/uv stdout/stderr/engine.jsonl/diagnostics.json`；MUST NOT 重用固定名覆盖前次日志；日志写入不可用时在继续变更前阻断。`--export-diagnostics` 契约见 §9.5；其错误码包含 `EXPORT_TARGET_NOT_EMPTY`。`--status` MUST NOT 写该目录。

### Inputs
operationId、stage/result/exitCode/stderr

### Preconditions
Current user logs root可创建

### Authoritative State
SOT：append-only logs + diagnostics schema；Derived：仅可由 Read-only probe 计算瞬时状态。

### State Transition
`NEW_OPERATION→LOG_READY→STAGED/FAILED`；所有变更记录 `operationId`。

### Allowed Side Effects
ALLOW：该 operation 目录、Windows Installer log。

### Forbidden Side Effects
DENY：用户配置/凭据、其他 operation 日志。

### Ownership Scope
`GENERATED_ONLY diagnostic`。

### Idempotency
第二次操作新目录，新 UUID。

### Failure Semantics
Log open/fsync 失败→`DIAGNOSTICS_UNAVAILABLE`，不得开始 MSI/Bootstrap mutation。`retryable`：仅在消除阻断输入、保持原身份或显式修复后重试；不对任意失败自动无限重试。

### Postconditions
exit!=0 输出 errorCode，回滚后原始证据仍在。

### Invariants
`INV-OBS-001`。

### Error Codes
`DIAGNOSTICS_UNAVAILABLE`, `EXPORT_TARGET_NOT_EMPTY`。

### Acceptance
`A-OBS-001`, `A-OBS-002`（详见 §20）。

### Evidence
Required test：`TEST-A-OBS-001`, `TEST-A-OBS-002`；Required artifact：`EVID-A-OBS-001.json`, `EVID-A-OBS-002.json`；原始 CLI/MSI/Engine 日志与 Release SHA 的引用必须在 Evidence 中填写。

## REQ-SEC-001 — 终端离线与安全边界

### Goal
避免恢复逻辑隐式下载/执行未经批准的代码。

### Normative Requirement
Core 终端操作 MUST 不调用网络下载 API、git clone、npm/npx/UV 在线索引；离线 Win10 上仍可完成安装和本地 CLI 版本验证；MUST 校验 runtime-manifest Ed25519 与包 SHA、以及路径包含关系；MUST NOT 要求 Authenticode；MUST NOT 跟随指向 Root 外部的 junction/symlink 进行删除或覆写。

### Inputs
signed MSI, payload digest, path, process network telemetry

### Preconditions
Release identity 校验通过

### Authoritative State
SOT：Manifest+Windows current identity；Derived：仅可由 Read-only probe 计算瞬时状态。

### State Transition
`CHECK→TRUSTED/BLOCKED`；所有变更记录 `operationId`。

### Allowed Side Effects
ALLOW：只允许已校验 Payload 和离线缓存。

### Forbidden Side Effects
DENY：公网请求、跨 Root 访问、凭据上报。

### Ownership Scope
`NONE + permitted Program Scope`。

### Idempotency
相同请求相同 trusted identity。

### Failure Semantics
签名/路径/流量违规→阻断，`OFFLINE_EGRESS_DETECTED`/`PATH_ESCAPE_DENIED`。`retryable`：仅在消除阻断输入、保持原身份或显式修复后重试；不对任意失败自动无限重试。

### Postconditions
安装执行进程树 egress attempt=0（OS 签名/CRL 流量单列）。

### Invariants
`INV-SEC-001`。

### Error Codes
`OFFLINE_EGRESS_DETECTED`, `PATH_ESCAPE_DENIED`, `SIGNATURE_INVALID`。

### Acceptance
`A-SEC-001`, `A-SEC-002`（详见 §20）。

### Evidence
Required test：`TEST-A-SEC-001`, `TEST-A-SEC-002`；Required artifact：`EVID-A-SEC-001.json`, `EVID-A-SEC-002.json`；原始 CLI/MSI/Engine 日志与 Release SHA 的引用必须在 Evidence 中填写。

## REQ-REPAIR-001 — 可重试修复与卸载边界

### Goal
失败机器不再只能复制开发机文件。

### Normative Requirement
Runtime Init MUST 支持 `--initialize` 收敛与 `--repair` 强制重建，并复用本机 MSI Payload；只允许修复 Generated Scope，Program Payload 缺损必须通过 MSI 标准 repair 后再调用 Runtime Init；`--status` MUST 只读且零文件写入；卸载 MUST 保留全部 USER_OWNED、skill ledger 与诊断日志。`--repair` 不得在零 mutation 预检失败时把 `PAYLOAD_INSTALLED` 标成 `REPAIR_REQUIRED`。

### Inputs
Product registration, receipt, prior failure code

### Preconditions
没有活跃的同根 Init operation

### Authoritative State
SOT：Product State + receipt + file verification；Derived：仅可由 Read-only probe 计算瞬时状态。

### State Transition
`REPAIR_REQUIRED→INITIALIZING→READY/REPAIR_REQUIRED`；所有变更记录 `operationId`。

### Allowed Side Effects
ALLOW：venv、boot launchers、new receipt。

### Forbidden Side Effects
DENY：用户模型、MSI owned files、其他用户数据。

### Ownership Scope
`GENERATED_ONLY + MSI controlled repair`。

### Idempotency
重复 `--repair` 成功后变为幂等 READY。

### Failure Semantics
Program Payload 缺损→`PAYLOAD_REPAIR_REQUIRED`，不尝试 Repo clone。`retryable`：仅在消除阻断输入、保持原身份或显式修复后重试；不对任意失败自动无限重试。

### Postconditions
坏状态不会被直接标 READY。

### Invariants
`INV-REPAIR-001`。

### Error Codes
`PAYLOAD_REPAIR_REQUIRED`, `INSTALL_BUSY`。

### Acceptance
`A-REPAIR-001`, `A-REPAIR-002`（详见 §20）。

### Evidence
Required test：`TEST-A-REPAIR-001`, `TEST-A-REPAIR-002`；Required artifact：`EVID-A-REPAIR-001.json`, `EVID-A-REPAIR-002.json`；原始 CLI/MSI/Engine 日志与 Release SHA 的引用必须在 Evidence 中填写。

## REQ-UI-001 — Tauri 可观察安装向导

### Goal
使普通员工不必依赖终端命令判断错误。

### Normative Requirement
GUI MUST 展示 Preflight、Install Payload、Initialize Python、Verify CLI、Complete 五个明确阶段；失败页 MUST 展示 errorCode、operationId、日志目录与「重试」「重建运行时」「打开日志」入口。「重试」MUST 调用 `--initialize`；「重建运行时」MUST 调用 `--repair`。状态来自 Engine 事件且不得伪造进度=100%。

### Inputs
engine structured events

### Preconditions
GUI handshake with local Engine

### Authoritative State
SOT：Event protocol + engine state；Derived：仅可由 Read-only probe 计算瞬时状态。

### State Transition
`UI_IDLE→INSTALLING→SUCCESS/FAILURE`；所有变更记录 `operationId`。

### Allowed Side Effects
ALLOW：GUI 本地 UI 状态、日志按钮。

### Forbidden Side Effects
DENY：直接修改 config/venv/registry。

### Ownership Scope
`NONE (UI)`。

### Idempotency
同一 operation 重绘不重复执行。

### Failure Semantics
引擎异常退出显示 `ENGINE_INTERRUPTED`，导出日志可用。`retryable`：仅在消除阻断输入、保持原身份或显式修复后重试；不对任意失败自动无限重试。

### Postconditions
READY 前不显示 Success。

### Invariants
`INV-UI-001`。

### Error Codes
`ENGINE_INTERRUPTED`。

### Acceptance
`A-UI-001`（详见 §20）。

### Evidence
Required test：`TEST-A-UI-001`；Required artifact：`EVID-A-UI-001.json`；原始 CLI/MSI/Engine 日志与 Release SHA 的引用必须在 Evidence 中填写。

## REQ-MIG-001 — v1 MSI 到 v2 的可控升级

### Goal
保证老版 MSI 安装用户不被升级操作重装破坏。

### Normative Requirement
v2 MSI MUST 使用原有 UpgradeCode 和更高的独立 Installer ProductVersion `2.0.0`；升级前 MUST 使用与 Init 相同的 venv 整树 + `bin\hermes*.exe` holder 扫描。保留 v1 User State 和 v1 marker 作为只读迁移输入；MUST NOT 假定 MSI Repair 会恢复被重命名的源码目录；必须对**实际分发的** 0.21.0 MSI 做 Windows 真机升级断言。本版 **MUST NOT** 为 Cleanup 条件单发 v1 补丁 SKU。仅当 USER_OWNED 字节在升级中变化才 `MIGRATION_BLOCKED`；旧 Cleanup 若误删 venv，视为可重建，不挡 v2 设计。

### Inputs
v1 product registration + version + owner state

### Preconditions
real v1 installation on Win10 VM; T0 snapshot

### Authoritative State
SOT：MSI state + User Data bytes；Derived：仅可由 Read-only probe 计算瞬时状态。

### State Transition
`V1_INSTALLED→UPGRADE_PAYLOAD→RUNTIME_REVALIDATE`；所有变更记录 `operationId`。

### Allowed Side Effects
ALLOW：旧 MSI 标准卸载 + 新 MSI 静态文件 + init receipt。

### Forbidden Side Effects
DENY：v1 用户 config/env/Provider sidecar。

### Ownership Scope
`Program files, not user config`。

### Idempotency
重复 v2 相同版本按 repair 路径。

### Failure Semantics
USER_OWNED 字节在升级中变化→`MIGRATION_BLOCKED`，不得发布 v2。旧 Cleanup 误删 venv 不构成该错误（可重建）。`retryable`：仅在消除阻断输入、保持原身份或显式修复后重试；不对任意失败自动无限重试。

### Postconditions
升级前后用户内容 hash不变。

### Invariants
`INV-MIG-001`。

### Error Codes
`MIGRATION_BLOCKED`。

### Acceptance
`A-MIG-001`（详见 §20）。

### Evidence
Required test：`TEST-A-MIG-001`；Required artifact：`EVID-A-MIG-001.json`；原始 CLI/MSI/Engine 日志与 Release SHA 的引用必须在 Evidence 中填写。

## REQ-CI-001 — Windows 真机发布 Gate

### Goal
消除 Stub 绿灯等于安装可用的误判。

### Normative Requirement
Release Pipeline MUST 收集真实 Win10 x64 冷安装、无网安装、已装旧版升级、Win11 验证、无管理员用户、非 ASCII 路径、进程占用/故障注入以及 smc-copilot Golden Consumer Evidence；Required AC 任一 SKIPPED/BLOCKED/FAIL 必须 Release FAIL 并返回非零进程退出码。

### Inputs
signed Release artifacts + clean VM snapshots

### Preconditions
实际 Windows 用户 context, diagnostics persistence

### Authoritative State
SOT：Evidence records + QA release gate；Derived：仅可由 Read-only probe 计算瞬时状态。

### State Transition
`CANDIDATE→GATE_PASS/FAIL`；所有变更记录 `operationId`。

### Allowed Side Effects
ALLOW：CI evidence/ reports。

### Forbidden Side Effects
DENY：修改用户源数据或伪造测试输出。

### Ownership Scope
`EVIDENCE only`。

### Idempotency
再次跑产生新 runID。

### Failure Semantics
无 Win10 Runner 则 `GOLDEN_CONSUMER_BLOCKED`，不得标 PASS。`retryable`：仅在消除阻断输入、保持原身份或显式修复后重试；不对任意失败自动无限重试。

### Postconditions
只有所有 Required PASS 才发布。

### Invariants
`INV-CI-001`。

### Error Codes
`GOLDEN_CONSUMER_BLOCKED`。

### Acceptance
`A-CI-001`, `A-CI-002`（详见 §20）。

### Evidence
Required test：`TEST-A-CI-001`, `TEST-A-CI-002`；Required artifact：`EVID-A-CI-001.json`, `EVID-A-CI-002.json`；原始 CLI/MSI/Engine 日志与 Release SHA 的引用必须在 Evidence 中填写。

## REQ-UPD-001 — Installer/Runtime 双版本治理

### Goal
消除“Installer 改版=Agent 升级”的误解。

### Normative Requirement
v2 Release MUST 独立记录 InstallerVersion=2.0.0、AgentVersion=0.21.0、SourceCommit=041b6985…、Build Revision/SHA；MUST NOT 自动从 `smc-copilot/hermes-agent/main` 更新或在 smc-copilot 登录时更新 Agent；未来 Runtime Update 入口保持 disabled，直到独立 Runtime Update PRD 获批准。

### Inputs
version contract + source lock

### Preconditions
installer v2 release branch

### Authoritative State
SOT：Release Manifest；Derived：仅可由 Read-only probe 计算瞬时状态。

### State Transition
`INSTALLED unchanged Agent Version`；所有变更记录 `operationId`。

### Allowed Side Effects
ALLOW：构建版本元数据。

### Forbidden Side Effects
DENY：更新现有 Agent 二进制至另一个 commit。

### Ownership Scope
`FILE: release metadata`。

### Idempotency
重复安装版本数据相同。

### Failure Semantics
发现未经批准来源→`AGENT_VERSION_CHANGE_DENIED`，不打包。`retryable`：仅在消除阻断输入、保持原身份或显式修复后重试；不对任意失败自动无限重试。

### Postconditions
InstallerVersion≠AgentVersion 可共存且在 UI 显示。

### Invariants
`INV-UPD-001`。

### Error Codes
`AGENT_VERSION_CHANGE_DENIED`。

### Acceptance
`A-UPD-001`（详见 §20）。

### Evidence
Required test：`TEST-A-UPD-001`；Required artifact：`EVID-A-UPD-001.json`；原始 CLI/MSI/Engine 日志与 Release SHA 的引用必须在 Evidence 中填写。

# 11. Side-Effect Contract

**矩阵内的 `YES` 表示唯一允许的写入目标，`NO` 表示一旦出现即为违规。日志、缓存、进程启动同样属于 side effect。**

| Operation | DB/Registry Write | File Write | Network | Cache | User Data | Business Source |
|---|---|---|---|---|---|---|
| `builder/build`（构建机） | NO | YES `payload/dist/evidence` | YES（仅构建机） | YES（构建机工作区） | NO | NO |
| `setup --preflight` | NO | YES `InstallerLogs/<operation>` | NO（安装器进程树） | NO | NO | NO |
| `msiexec /i` | YES（MSI 标准注册） | YES（静态 Program Payload） | NO（自有 CA 不联网；系统 SmartScreen/证书独立测） | Windows Installer 内部允许 | NO | NO |
| `runtime-init --initialize` | YES（HKCU user env，验证通过后） | YES（venv/CLI/receipt/Logs） | NO | YES（仅既有离线 uv cache 的读取、venv 写入） | `CreateNew` 缺失模板，不覆写已有 | NO |
| `runtime-init --repair` | YES（仅自有 HKCU env） | YES（Runtime Generated、T0 备份、Log） | NO | YES（同上） | PRESERVE | NO |
| `runtime-init --status` | NO | NO | NO | NO | NO | NO |
| `runtime-init --export-diagnostics` | NO | YES（仅指定 Export dir） | NO | NO | READ with secret redaction | NO |
| `msiexec /x` | YES（MSI 产品注册） | YES（删除 MSI-owned Payload） | NO | Windows Installer 内部允许 | PRESERVE | NO |
| `Hermes Gateway start`（显式用户行为） | MAY（Hermes 自有状态） | MAY（Hermes 自有状态） | Gateway 可按配置联网 | MAY | Hermes Runtime 拥有 | NO |

**过程边界**：以上“安装离线”断言只针对 Setup GUI、Rust Init、PowerShell/uv/CLI 子进程及本工程 Custom Action；Windows 的 SmartScreen、CRL、OCSP/证书验证不计入安装器进程树的网络 Oracle，但网络流量分析报告 MUST 单独记录其来源。模型连通性不是离线步骤：独立“在线 Golden Consumer”测试必须在标记 READY 后由 QA 明确执行。

# 12. Ownership Contract

## 12.1 Ownership Table

| Path/Resource | Owner | Lifecycle | Drift action |
|---|---|---|---|
| `%LOCALAPPDATA%\hermes\bin\uv.exe` 等 | MSI `PROGRAM_MANAGED` | 安装/升级 MSI | MSI 修复；Init 不写 |
| `%LOCALAPPDATA%\hermes\bootstrap\HermesRuntimeInit.exe` | MSI `PROGRAM_MANAGED` | 安装/升级 MSI | MSI 修复；Init 不改自身 |
| `%LOCALAPPDATA%\hermes\runtime-manifest-v2.json` 与 `.sig` | MSI `PROGRAM_MANAGED` | 安装/升级 MSI | 签名失败 → 拒绝 Init |
| `%LOCALAPPDATA%\hermes\hermes-agent\` 除 venv 外的打包内容 | MSI `PROGRAM_MANAGED` | 安装/升级 MSI | 源码修改漂移 → BLOCK |
| `%LOCALAPPDATA%\hermes\offline\uv-cache` | MSI `PROGRAM_MANAGED` | 安装/卸载 MSI | Hash drift → `BUNDLE_HASH_MISMATCH` |
| `%LOCALAPPDATA%\hermes\hermes-agent\venv` | Init `GENERATED_ONLY` | 初始化/修复 | T0 backup → rebuild → verify |
| `%LOCALAPPDATA%\hermes\bin\hermes*.exe` | Init `GENERATED_ONLY` | 初始化/修复 | 精确 identity 变更，不改静态 bin |
| `%LOCALAPPDATA%\hermes\state\runtime-receipt-v2.json` | Init `LAST_APPLIED_STATE` | READY 时原子替换 | Drift→REPAIR_REQUIRED |
| `%LOCALAPPDATA%\hermes\state\runtime-init.lock` | Init lease | `--initialize`/`--repair` 持有；`--status` 零写入 | PID 活→`INSTALL_BUSY`；PID 死→探针 `INTERRUPTED` |
| `%LOCALAPPDATA%\hermes\state\enterprise-skill-ledger-v2.json` | Init Ledger | 原子替换；卸载 MSI 不删 | 冲突→`SKILL_OWNERSHIP_CONFLICT`，0 Skill writes |
| `%LOCALAPPDATA%\hermes\state\runtime-backups` | Init 恢复备份 | 最近一次失败树 + `RUNTIME_ROLLBACK_FAILED`；成功 T0 在 READY 后删除 | 失败/ROLLBACK_FAILED 不得自动删除 |
| `%LOCALAPPDATA%\SMC\HermesInstaller\InstallerLogs` | Installer diagnostics | 每次 operation | 历史永不覆写；保留直至显式清理 |
| `%LOCALAPPDATA%\hermes\.env,config.yaml,SOUL.md` | 用户/Hermes | 保留/缺失时 CreateNew | PRESERVE |
| `%LOCALAPPDATA%\hermes\runtime-provider-*.json` | smc-copilot Provider | 安装器禁写 | PRESERVE |
| `%LOCALAPPDATA%\hermes\sessions,memories,logs` | 用户/Hermes | 持久 | PRESERVE |
| `%LOCALAPPDATA%\hermes\skills` | 用户 + last-applied 企业条目 | 分条目记录 owner | 未知与漂移 → BLOCK |
| HKCU `PATH,HERMES_HOME,HERMES_GIT_BASH_PATH` | 用户值 + Init 明确附加 | 记录 T0 后才改 | 比较 before/after 恢复 |

## 12.2 Ownership Lifecycle

创建时：只给由 MSI 释放的静态文件标 `PROGRAM_MANAGED`；预存用户文件无论内容是否等于模板，都属于 `USER_OWNED`。更新时：MSI 只能升级它的静态组件，Bootstrap 只能重建 `GENERATED_ONLY`，任何其他同路径存在冲突都记录并 BLOCK。用户修改后：用户状态永久 PRESERVE；企业 Skills 的 last-applied digest 不等即阻断同步。删除时：Direct MSI uninstall 只删除 MSI 组件，允许由独立 Bootstrap 创建的 `venv`/Launcher 残留（不自动递归删除 `%LOCALAPPDATA%\hermes`）；Bootstrap 保留用户资料、skill ledger 和历史诊断。本版 CLI **MUST NOT** 提供 `--purge-generated-runtime` 或任何清除全部用户状态的命令；强制重建 Generated 的唯一入口是 `--repair`。

## 12.3 Program Payload / venv Drift

`current != lastApplied` 不做静默覆盖：`PROGRAM_MANAGED` 以 Manifest 校验失败并给 `PAYLOAD_REPAIR_REQUIRED`，由 MSI 修复；`GENERATED_ONLY` 启动受控 repair；`USER_OWNED` 原字节保留；`SHARED` Skills 按条目 last-applied 算法处理。路径指向 Root 外部时 `PATH_ESCAPE_DENIED`，0 删除。

# 13. Hash / Identity Contract

- 文件 SHA：`SHA256(raw file bytes)`，以 64 位 lowercase hexadecimal UTF-8 文本序列化；目录不可直接哈希。
- `payload_files` 覆盖 MSI 要发布的全部**静态文件**，相对路径一律转换 `/`、Unicode NFC 后以 lowercase 比较**冲突**；Manifest 中最终 canonical 路径保留原始大小写，但任何两条路径经 Windows casefold 等价则构建失败。
- Tree Digest：按 canonical path 的 UTF-8 字节升序排列。每条序列化为 `UTF8(relative_path) + NUL + ASCII(lowercase-file-sha256) + NUL + ASCII(decimal-size) + LF`；对完整字节流求 SHA256。
- 排除 `runtime-manifest-v2.json` 自身（避免哈希自引用），排除 `.work/`、`dist/`、`evidence/`、客户端 `venv` 和任何用户配置；所有被 MSI 真正装载的静态文件（包括 `HermesRuntimeInit.exe`）必须在树清单中。
- `runtime-manifest-v2.json` 内含 `payloadTreeSha256`、SourceCommit 和 file list，必须附带 `runtime-manifest-v2.sig`（对 Manifest UTF-8 原始字节的 Ed25519 detached signature；`.sig` 是原始 64-byte signature 的 RFC4648 标准 Base64，无换行；验签公钥为 32-byte Ed25519 public key，在 **未要求 Authenticode** 的 `HermesRuntimeInit.exe` 里固化，`keyId=SHA256(raw_public_key)` 的首 16 位 lowercase hex）。Build 签名私钥为 CI Secret `HERMES_MANIFEST_ED25519_SEED_B64`（解码必须正好 32 bytes），不在代码、构建日志或发布包中保存，缺失时 `MANIFEST_SIGNING_KEY_MISSING` 并中止 Release Build；不能静默回退未签名。**两个 Manifest 文件及 detached signature 均排除在 Payload Tree Digest 之外以避免自引用**。客户端 Direct MSI Init、GUI Init、Repair 必须在执行 uv 前验证该 Ed25519 签名。构建顺序：**编译 Init EXE（本轮不做 Authenticode）→ 冻结全部静态文件 → 生成 Manifest → Ed25519 签 Manifest**；此后不得再修改 tree 范围中的文件。
- `release-manifest-v2.json` 在 Core MSI 构建完成后生成，写入最终 MSI 的 SHA 和 `runtime-manifest-v2.json` SHA；Release Manifest 不嵌入 MSI，避免 `MSI hash → embedded Manifest hash → MSI hash` 循环；只嵌入最终 Setup EXE 并作为旁路 Release 文件发布。本轮 MSI/Setup **MUST NOT** 因缺少 Authenticode 而构建失败。
- `Setup.exe` 构建完成后计算其独立 SHA，写入 `build-info.json`；不得要求将 Setup SHA 写回 Setup 内部资源。本轮不对该 EXE 做 Authenticode。
- 版本身份：MSI ProductVersion `2.0.0`（Windows Installer 三段数）、Agent `0.21.0`、SourceCommit `041b6985…`、Payload Tree SHA、MSI SHA、Setup SHA；每个维度在报告中分列。
- Runtime Receipt 校验需要 `payloadTreeSha256`、`sourceCommit`、MSI ProductCode 与当前实际观察完全相同，不能只看 `hermes.exe` 文件存在。
- `hash` / `identity` 对端点的显式 user-state 内容不适用“加入 Bundle”；用户配置用于升级前后比较时另算 `SHA256` 并在 Evidence 仅存 digest，不保存原文/密钥。

# 14. Transaction Contract

## 14.1 分离两个事务

**MSI_TXN（Windows Installer 标准事务）**

```text
T_MSI_0 = MSI-owned static Program files + MSI registration
Verify signature/identity → InstallFiles → Windows Installer commit
Failure before commit → Windows Installer rollback MSI-owned components
```

MSI_TXN **不包含** uv sync、venv 生成、Gateway start、企业模型配置变更、修改用户 PATH。`Core MSI` 在 Direct Mode 成功时只报告 `PAYLOAD_INSTALLED`；此前 v1 的 `InitializeHermes` CustomAction MUST 从包中移除。

**INIT_TXN（独立 Runtime 事务）**

```text
Read-only inspect → reserve diagnostics/lock → verify payload hashes
→ process holder check → capture T0
→ UV_SYNC in FINAL venv path (skip if venv gate passes) → IMPORT_VERIFY → CLI_VERIFY_VENV
→ seed missing user templates (exclusive create, log created digest)
→ SKILLS_MERGE → ENV_APPLY → CLI_STAGE_BIN → CLI_VERIFY_BIN
→ atomically publish READY receipt → delete this op's successful T0 → release lock
```

- `T0` 在第一次 Runtime Generated 或用户环境 mutation 之前采集：完整旧 venv（仅 `--repair` 或 venv 门失败的 `--initialize` 才同卷 rename 到 `state/runtime-backups/<op>/`）、`bin/hermes*.exe` 原 bytes + SHA、旧 Runtime Receipt 原 bytes + SHA、3 项 HKCU 原值、Skills 现有 last-applied bytes/digests。用户原有配置只读哈希，不作为安装器可恢复/可覆写数据；**仅本操作使用 `CreateNew` 新建的模板**纳入本次 T0 账本，若后续失败且其字节仍等于本次创建 digest，则删除该新文件以恢复“原本不存在”的 T0；若期间被外部修改则 PRESERVE、标记 `RUNTIME_ROLLBACK_FAILED`，不得删除用户更改。
- 不允许在不同路径创建将来移动到最终路径的 Python venv：Windows `hermes.exe` launcher/shebang 可能内嵌解释器绝对路径；**重建必须发生在最终 `hermes-agent/venv` 位置**。活路径永远只有 `hermes-agent\venv`。旧 venv 应先移动到同卷恢复目录，已被锁定的旧 venv 不允许强制移动；sharing violation → `RUNTIME_IN_USE`。
- 新装没有 T0 venv：失败后本次生成目录 MUST 同卷改名到 `state/runtime-backups/<op>/` 以支持故障采证，**禁止 `Remove-Item` 删除**；不得被下次初始化当作上次成功 venv。默认只保留最近一次失败树。`--repair` 在占用检查通过后可替换非 `RUNTIME_ROLLBACK_FAILED` 的失败树并强制重建 Generated。`--status` 不删备份。
- 本操作到达 READY 且 receipt 已发布后，删除**本次成功**的 T0 备份。`RUNTIME_ROLLBACK_FAILED` 备份必须人工确认后才删。
- 旧装恢复失败：保留 `runtime-backups/<op>` 不覆盖、不清理；记录 `RUNTIME_ROLLBACK_FAILED`，`runtimeState=REPAIR_REQUIRED`，向用户说明手工恢复具体路径；**不得自动再次重试 destructive operation**。
- Python/CLI/Skill/Env 任一检查失败时不得发布新 READY Receipt；写成功 Receipt 必须采用同目录临时文件 + flush + replace，不能使用截断原文件的 fallback。
- **非事务外部副作用**：MSI 已成功提交不在 INIT_TXN 中，Bootstrap failure 不执行 `msiexec /x`。Windows Installer MajorUpgrade 一旦 Commit，不承诺恢复旧 MSI；v2 只在 Runtime Generated Scope 上回滚。

## 14.2 Commit Order / Idempotency

成功标记发布顺序严格唯一为：`UV_SYNC → IMPORT_VERIFY → CLI_VERIFY_VENV → SKILLS_MERGE → ENV_APPLY → CLI_STAGE_BIN → CLI_VERIFY_BIN → RECEIPT_COMMIT`。`bin\hermes.exe` MUST 在 Skill/Env 之后、receipt 之前落地；未 READY 不得让桌面契约路径可启动。若新版本源 SHA 不等于锁定 Manifest，禁止构建与客户端应用。`--initialize` 在同一身份 READY 时先读 Receipt 并验证 CLI，不做任何重建/删除。venv 门通过时跳过 `UV_SYNC`，从第一个失败阶段继续。

## 14.3 Failure Atomicity

receipt 发布前任何失败的补偿集（**不是**把整个 Generated 滚回 T0）：

- **保留** 已通过门的 `hermes-agent\venv`（供 `--initialize` 继续；跳过 uv 的条件见 §9.5）。
- **恢复** `bin\hermes*.exe` 到 T0（新装则删除本次 copy）。
- **撤销** 本次已写入的受管 Skill，以及本次 `CreateNew` 且字节仍等于创建 digest 的模板。
- **恢复** 本次已经写出的 HKCU 三项到 T0；本次尚未提交的 HKCU 不动。
- 新装失败的半成品 venv MUST 隔离到 `runtime-backups\<op>\`，活路径不得指向失败实例。
- 用户-owned 文件始终 byte-equal（非安装器 mutation）。

Skill 冲突时 Skill 子树 0 writes，venv 仍保留，状态为 `REPAIR_REQUIRED`。禁止把「Skill/Env 失败」解释成拆掉 venv。

## 14.4 Rollback Failure Retention

`RUNTIME_ROLLBACK_FAILED`：不删除 `state/runtime-backups/<op>`、`InstallerLogs/<op>`；导出 `recovery.json` 列每条 T0 文件源路径、原 SHA、当前存在性、实际还原成功与否。默认保留到用户/运维显式确认修复且另一条独立操作验证成功为止；日志清理命令不删除未关闭 recovery backup。

# 15. Conflict Contract

| Conflict | Detection | Default | Error | Program/User Mutation |
|---|---|---|---|---|
| per-user MSI 以 SYSTEM 安装 | SID `S-1-5-18` | BLOCK | INSTALL_IDENTITY_DENIED | 0 |
| 任意进程占用 `venv` 整树或 `bin\hermes*.exe`（含 `python.exe` 加载 `.pyd`、Gateway、CLI、MCP） | Restart Manager + 同用户模块路径 | BLOCK 并列出 PID 与完整 exe 路径 | RUNTIME_IN_USE | 0 |
| venv / `bin\hermes*.exe` 的 rename/delete/overwrite 返回 access denied 或 sharing violation | Win32 错误 | BLOCK；能列 PID 则列出 | RUNTIME_IN_USE | 0 |
| 无法检视进程权限 | OS 返回 AccessDenied | BLOCK（升级或修复时） | PROCESS_INSPECTION_FAILED | 0 |
| `HERMES_HOME` 指向非本用户 Native Root | Root 路径与 `%LOCALAPPDATA%\hermes` 不一致 | BLOCK，不重定向旧 Root | HERMES_ROOT_CONFLICT | 0 |
| MSI 与 Embedded release SHA 不一致 | 原始 MSI SHA | BLOCK | RELEASE_IDENTITY_MISMATCH | 0 |
| Program Payload 文件被用户改写 | Tree/File hash 不等 | BLOCK，提示 MSI Repair | BUNDLE_HASH_MISMATCH | 0 Init |
| 同路径既有用户 `config.yaml/.env` | exists 即 OWNER=USER | PRESERVE | 无错误 | 0 对该文件 |
| Skill 路径与未知所有者相同 | Ledger/Path 检查 | BLOCK entire Skill sub-TXN；venv 保留；不发布 READY | SKILL_OWNERSHIP_CONFLICT | 0 Skill writes |
| v1 `hermes-agent.broken-*` 目录 | basename scan | PRESERVE + REPORT | 无错误（不恢复） | 0 对该目录 |
| 同时双启动 Setup/Init | `runtime-init.lock` PID+exe | BLOCK 次级 | INSTALL_BUSY | 0 Runtime writes |
| HermesRoot 待替换文件或 RM reboot-required | PendingFileRenameOperations / RM | BLOCK Init；不把机器任意待重启当阻断 | REBOOT_REQUIRED | 0 |
| Manifest 与当前 MSI 注册版本不匹配 | ProductCode/Version/SHA | BLOCK | RELEASE_IDENTITY_MISMATCH | 0 Init |
| Root 内 symlink 指向外部 | reparse point + resolved path | BLOCK | PATH_ESCAPE_DENIED | 0 |
| HKCU PATH 已有同一条目 | case-insensitive normalized exact entry | REUSE，不追加 | 无错误 | 0 PATH writes |

默认绝不采用 last-writer-wins、隐式 `git clone` 或从 `.broken-*` 自动恢复。

# 16. Compatibility / Migration

## 16.1 Current and Target Layout

```text
Existing v1  %LOCALAPPDATA%\hermes\
  bin\uv.exe, hermes.exe (generated)
  python\ ; git\ ; node\ ; hermes-agent\ ; offline\
  state\bundle-install.json (v1)
  .env, config.yaml, SOUL.md, sessions/, memories/, runtime-provider-*.json

Target v2   %LOCALAPPDATA%\hermes\  # preserve path for smc-copilot
  same Core CLI path at bin\hermes.exe
  bootstrap\HermesRuntimeInit.exe (MSI owned)
  runtime-manifest-v2.json (MSI owned)
  state\runtime-receipt-v2.json (generated)
  state\bootstrap-operation-v2.json (generated)
  state\runtime-init.lock (generated lease)
  state\enterprise-skill-ledger-v2.json (Init ledger)
  state\runtime-backups\<operation-id>\ (generated/retained)
  existing user files unchanged

Diagnostics outside MSI:
  %LOCALAPPDATA%\SMC\HermesInstaller\InstallerLogs\<operation-id>\
```

## 16.2 Migration Contract

1. GUI 在 MSI 前检查：是否存在同一 UpgradeCode 的 v1 用户级产品；对 `hermes-agent\venv` 整树和 `bin\hermes*.exe` 做与 Init 相同的 holder 扫描；T0 user data digests。
2. 若存在占用，拒绝继续升级，直到用户**显式停止**持有进程后再次预检；Setup 不执行自动 kill。不得只按 Gateway EXE 名匹配。
3. `Core MSI v2` 使用旧 UpgradeCode，通过 `MajorUpgrade` 标准行为提升 MSI ProductVersion 至 `2.0.0`。不为 Cleanup 条件单发 v1 补丁 SKU。旧版 MSI 的 `CleanupHermes` 仅在真正卸载而非 `UPGRADINGPRODUCTCODE` 时应运行，**必须对实际分发的 0.21.0 MSI 做 Windows 真机断言**，不能由静态语句推断为通过。仅 USER_OWNED 字节变化才 `MIGRATION_BLOCKED`；venv 被旧 Cleanup 删除视为可重建。
4. v1 `bundle-install.json` 仅作为迁移读取证据，新 Runtime Ready 以 v2 Receipt 决定。v2 不复制 `hermes-agent.broken-*` 文件夹，不以 MSI Repair 能恢复文件作为前提。
5. v1 `.env/config.yaml/SOUL.md/sessions/memories/skills` 及 `runtime-provider*.json` 的原 SHA 必须保持。对未知 owner 只保留、上报，不做启发式覆盖。
6. v2 MSI Commit 后如果 Runtime Init 失败，不撤销 MSI MajorUpgrade；保持本机可通过 `HermesRuntimeInit.exe --initialize` 收敛或 `--repair` 重建，并保留快照/日志。不能向用户宣称“已回到原 MSI 版本”。

## 16.3 Unknown Ownership

任何目录归属不明或未在 Manifest/ownership ledger 中出现：`PRESERVE + REPORT + MUST NOT DELETE`。相同文件名但不同 owner 也必须拒绝覆盖。用户 `config.yaml` 若缺失只按模板 CreateNew；若存在但 YAML 格式无效不由 Installer 自动修复；用 `USER_CONFIGURATION_INVALID` 警告并将 Runtime Core Ready 与模型配置可用性区分展示，不启动模型投影。

# 17. External Dependency Contract

| Dependency | Repo / endpoint | Version / immutable identity | Required | Offline / Failure |
|---|---|---|---|---|
| Hermes source actual | `loudon84/copilot-hermes` | `041b6985a00d01b54f830c1607dd370007a306bf`, Agent 0.21.0 | REQUIRED build | 构建时获取；终端 0 Git |
| Hermes source reference | `smc-copilot/hermes-agent` | `c16cc4ca7597ce9b52944bbecea450c51e9781dc`（仅代码参考） | NOT packaged | 版本改变不触发更新 |
| WiX Toolset | `WixToolset.Sdk` | `5.0.2` 源码现状 | REQUIRED build | 构建阶段 NuGet restore；终端不需 WiX |
| uv executable | MSI `bin/uv.exe` | Build Manifest SHA | REQUIRED runtime-init | `uv sync --offline --frozen --link-mode copy`，不得使用公网 fallback |
| Python | MSI `python/**/python.exe` | 3.11 + Build Manifest path/SHA | REQUIRED | 终端不下载 Python |
| Node/Portable Git | MSI 本地运行时 | Build Manifest hashes | STATIC payload | Core Init 不运行 Node/npm/Git Clone |
| Tauri GUI | 从 `smc-copilot/hermes-agent/apps/bootstrap-installer` 参考交互/事件 | 采用固定参考 Commit，代码需本项目移植维护 | REQUIRED Setup mode | 新 GUI 不使用上游在线脚本编排；无网仍可安装 |
| Windows Installer | OS `msiexec.exe` | 系统内置 v5.x | REQUIRED | 离线文件事务；exitCode 0/3010 规范 |
| Win10 Native Adapter | `smc-copilot/apps/work` | Golden Consumer 测试固定 HEAD（QA Evidence 记录） | REQUIRED Release Golden | 验证本机 `bin/hermes.exe` 和 Gateway；在线模型另阶段 |
| OPSI | 企业终端管理 | 用户登录 Session Mode | OPTIONAL deployment | `SYSTEM` 下直接 per-user MSI 必须拒绝 |

版本漂移规则：外部 Repo 更新不能自动改 Builder source SHA；若提议升级 Agent，必须新 PRD、单独 Runtime Bundle、数据迁移测试、独立 Release Gate。目标 Win10 x64 在官方最低支持的系统更新级别进行真实测试，实际构建号写入 Evidence，而不是只记录“Windows 10”。

# 18. Security Contract

| Threat | Control | Acceptance |
|---|---|---|
| 路径穿越与 junction/symlink 外逃 | 路径必须 canonicalize、拒绝 reparse 到 Root 外、拒绝 UNC/network drive 作为 Runtime Root | A-SEC-002 |
| 不受信任 Setup/MSI | 本轮：GUI/企业通道核对内嵌 MSI SHA 与 runtime-manifest Ed25519；**不**核验 Authenticode 证书主体。后续独立 Change 才可加 PE 签名 | A-ENTRY-001、A-SEC-002 |
| 任意命令执行 | Init Rust Engine 固定命令和 argv（不用 `Invoke-Expression`），不运行远程 install.ps1 | A-PY-002、A-SEC-001 |
| 凭据泄漏 | `diagnostics.json/engine.jsonl` mask `api_key/token/secret/authorization` 与模型 URL query；不记录 `.env` 原值 | A-OBS-001 |
| 缓存/锁被篡改 | SourceCommit、全量静态树摘要、签名验证后才启动 Init | A-BUILD-001、A-SEC-002 |
| 用户数据丢失 | MSI/Runtime Generated/User-Owned 分域；T0 backup 和回滚 | A-OWN-001、A-TXN-002 |
| per-user/SYSTEM 权限混淆 | SID 校验 `S-1-5-18`；仅 HKCU，非 HKLM 修改 PATH | A-MSI-002、A-ENV-001 |
| DLL sideload / uv 路径 | 固定执行 MSI 路径中的 uv/python；受控进程环境；不依赖系统 PATH 解析 Python | A-PY-001、A-SEC-001 |
| 服务器隐式流量 | 终端安装进程树 zero egress，OS 签名验证流量单独披露 | A-SEC-001 |

不要求完全禁用 Windows 安全产品；发现 AV/EDR 隔离时保留原始 Windows Event、Defender Detection ID 摘要，提示管理员处理，不自动添加杀软排除项。供应链 License/NOTICE 在发布时验证；ffmpeg/Chromium 的分发许可另纳入 Release Checklist。**本轮停用 Authenticode 要求**（`NON-GOAL-007`）：PE 无组织证书不得视为构建/发布失败。Manifest Ed25519 私钥只存在构建 CI Secret `HERMES_MANIFEST_ED25519_SEED_B64`，授权使用由 Security Owner 审核；G-P06 只确认该 Secret 已实际准备，**不得**把 Authenticode 证书列入本 Gate；Secret 缺失则保持 REVIEW，不允许虚构 Ed25519 签名 Build PASS。

# 19. Observability

阶段名唯一且顺序固定：`PRECHECK`、`MSI_INSTALL`、`PAYLOAD_VERIFY`、`PROCESS_HOLDER_CHECK`、`SNAPSHOT_T0`、`UV_SYNC`、`IMPORT_VERIFY`、`CLI_VERIFY_VENV`、`SKILLS_MERGE`、`ENV_APPLY`、`CLI_STAGE_BIN`、`CLI_VERIFY_BIN`、`RECEIPT_COMMIT`、`COMPLETE`、`ROLLBACK`、`FAILED`。`CLI_STAGE_BIN` 不得早于 `SKILLS_MERGE` 与 `ENV_APPLY`。

每条 `engine.jsonl` 必备：`operationId`(UUID)、`sequence`(单调递增)、`timestampUtc`、`stage`、`status`、`installerVersion`、`agentVersion`、`sourceCommit`、`manifestSha256`、`commandId`、`exitCode`(nullable)、`errorCode`(nullable)、`elapsedMs`。stdio 原始日志按阶段分文件写入、只允许追加、不覆盖，写盘异常视作失败。stdout/stderr 必须显式分流，Windows PowerShell 5.1 下记录 raw bytes 与 lossy UTF-8 展示版本，确保中文/CP936 不会让最后几行日志截断。

默认路径 `InstallerLogs/<operationId>/`：

```text
operation.json              # session/build/OS identity (no secrets)
msiexec.log                 # /L*V! first line to final exit
engine.jsonl                # staged structured events
uv-stdout.log / uv-stderr.log
preflight.json              # disk/arch/identity/gateway/PID
rollback.json               # T0/recovery status (on failure)
diagnostics.json            # sanitized human+machine summary
errors.txt                  # last 200 stderr lines, redacted
```

用户直接双击单独 MSI 时，自动记录 MSI 故障能力应通过 Windows Installer 的 `MsiLogging` 属性与 Event Log 验证，但不保证能获得 Init 日志——**Direct MSI 根本不执行 Init**。生产推荐入口是 Setup.exe；企业推荐 `msiexec /L*V!` + Init `--quiet`。UI 提供“打开日志”和“导出诊断 ZIP”，不得只显示 `1603`。日志保留策略：永不自动覆盖历史操作；按管理员显式清理且非未关闭恢复备份，不能静默删除故障证据。

# 20. Acceptance Design Standard（Given / When / Then / Oracle / Evidence）

下列验收全部为 **Required**。`PASS` 必须是执行证据，不能只由存在测试文件判定。命令规范：`TEST-<AC-ID>` 代表 §34.2 指定的自动化/手工封装测试；Runner 必须写真实命令及退出码到 `EVID-<AC-ID>.json`。每个测试单独运行并留存独立 operationId；禁止复用别的场景的 `PASS` 文件。

## A-SRC-001 — 锁定双版本与 Source Commit

- **Requirement Refs**：`REQ-SRC-001`。
- **Given**：Release Build 的 build-config 指向正确 SHA，工作树 clean。
- **When**：运行完整 Build 并查看最终 Manifest。
- **Then**：Agent=0.21.0、Installer=2.0.0；不存在对 `smc-copilot/hermes-agent/main` 的执行式 fetch。
- **Oracle**：``manifest.source.commit == pinned_sha AND installerVersion == 2.0.0 AND git HEAD == pinned_sha`；注入源 SHA 不匹配时 build exit !=0`。
- **Evidence**：`TEST-A-SRC-001`；`EVID-A-SRC-001.json`；包含实际命令、exit code、pre/post digest、原始 log paths、repository SHA、Windows build、工具版本。所需原始证据：构建机 Git HEAD、build-info、SHA manifest、静态源扫描。

## A-BUILD-001 — 完整离线 payload 实证

- **Requirement Refs**：`REQ-BUILD-001`。
- **Given**：构建机已锁定依赖，缓存按 Manifest 准备。
- **When**：清空构建 venv 再执行离线 uv sync 和 CLI/import 检验。
- **Then**：bundle proof 每项含命令、执行结果、时间；无缓存缺项。
- **Oracle**：``uv_exit==0 AND import_exit==0 AND hermes_exit==0 AND venvEstimatedBytes>0``。
- **Evidence**：`TEST-A-BUILD-001`；`EVID-A-BUILD-001.json`；包含实际命令、exit code、pre/post digest、原始 log paths、repository SHA、Windows build、工具版本。所需原始证据：离线构建 stdout/stderr、build-info、依赖 lock hash。

## A-BUILD-002 — 全树摘要与缺损拒绝

- **Requirement Refs**：`REQ-BUILD-001`。
- **Given**：生成完整 MSI Payload 清单与 Tree SHA。
- **When**：随机篡改单个非8项文件、缺失关键文件分别进入验证。
- **Then**：篡改者被拦截，未发布 MSI/Init 不执行 uv。
- **Oracle**：``payloadFileCount==actualFiles AND sha_tree_equal`; 注入后 `BUNDLE_HASH_MISMATCH``。
- **Evidence**：`TEST-A-BUILD-002`；`EVID-A-BUILD-002.json`；包含实际命令、exit code、pre/post digest、原始 log paths、repository SHA、Windows build、工具版本。所需原始证据：文件枚举、两组 digest、构建 exit code。

## A-MSI-001 — MSI 与 uv 初始化解耦

- **Requirement Refs**：`REQ-MSI-001`。
- **Given**：干净 Win10 且有匹配 MSI。
- **When**：仅运行 `msiexec /i`，不运行 Init。
- **Then**：返回 MSI 成功且 Program Payload 存在，无 venv/CLI 初始化副作用。
- **Oracle**：``msiexec_exit==0 AND registeredProduct==true AND uv_spawn_count==0 AND init_process_count==0``。
- **Evidence**：`TEST-A-MSI-001`；`EVID-A-MSI-001.json`；包含实际命令、exit code、pre/post digest、原始 log paths、repository SHA、Windows build、工具版本。所需原始证据：真实 Win10 MSI log、进程跟踪、文件目录对比。

## A-MSI-002 — SYSTEM 身份拒绝

- **Requirement Refs**：`REQ-MSI-001`。
- **Given**：安装身份是 `S-1-5-18`。
- **When**：执行 per-user MSI 安装。
- **Then**：安装失败，未写 SYSTEM LocalAppData 下 Hermes 程序。
- **Oracle**：``MSI != 0 AND installedProductCount==0 AND noProgramFilesCreated``。
- **Evidence**：`TEST-A-MSI-002`；`EVID-A-MSI-002.json`；包含实际命令、exit code、pre/post digest、原始 log paths、repository SHA、Windows build、工具版本。所需原始证据：CI 实验账户安全执行记录、MSI verbose log。

## A-ENTRY-001 — GUI 内嵌 MSI 与 Direct MSI 一致

- **Requirement Refs**：`REQ-ENTRY-001`。
- **Given**：发布同时有 Setup.exe、Core MSI、Release Manifest。
- **When**：从 EXE 提取 MSI 与独立 MSI 按 bytes 比对，并校验 runtime-manifest Ed25519。
- **Then**：MSI SHA 完全相同；不含递归的 Setup GUI；Ed25519 验签通过。本轮 **MUST NOT** 把 Authenticode 缺失判失败。
- **Oracle**：``sha(embedded_msi)==sha(core_msi)==release.msiSha256 AND ed25519_manifest_valid``。
- **Evidence**：`TEST-A-ENTRY-001`；`EVID-A-ENTRY-001.json`；包含实际命令、exit code、pre/post digest、原始 log paths、repository SHA、Windows build、工具版本。所需原始证据：Setup 解包 SHA、runtime-manifest 验签结果。**禁止**把 SignTool Authenticode 失败当作本 AC FAIL。

## A-PRE-001 — Preflight 提前阻断

- **Requirement Refs**：`REQ-PRE-001`。
- **Given**：用户目录可写，Windows 10 x64，磁盘低于规定阈值。
- **When**：通过 GUI Preflight。
- **Then**：显示磁盘不足；msiexec 不启动，用户配置无修改。
- **Oracle**：``errorCode==DISK_SPACE_INSUFFICIENT AND msi_spawn==0 AND user_digest_before==after``。
- **Evidence**：`TEST-A-PRE-001`；`EVID-A-PRE-001.json`；包含实际命令、exit code、pre/post digest、原始 log paths、repository SHA、Windows build、工具版本。所需原始证据：Preflight.json、事件和文件 hash。

## A-PRE-002 — 复杂路径兼容与身份限制

- **Requirement Refs**：`REQ-PRE-001`。
- **Given**：Win10 用户目录分别含空格/中文/括号且容量合规。
- **When**：运行 Preflight + 完整离线 Init。
- **Then**：路径解析成功；实测 Hermes 双 CLI 版本成功。
- **Oracle**：``all(case.exit==0 AND case.cli_versions==0.21.0)`；SYSTEM/UNC case 必须非0`。
- **Evidence**：`TEST-A-PRE-002`；`EVID-A-PRE-002.json`；包含实际命令、exit code、pre/post digest、原始 log paths、repository SHA、Windows build、工具版本。所需原始证据：Win10 真实路径、argv 捕获、stderr、exit。

## A-GW-001 — 运行时进程占用不强杀

- **Requirement Refs**：`REQ-GW-001`。
- **Given**：真实 Gateway 与加载 `venv\**\*.pyd` 的 `python.exe` 持有进程存活（不必名为 `hermes.exe`）。
- **When**：请求 Repair/Upgrade。
- **Then**：阻断且保留持有 PID，旧 Gateway 继续可用。
- **Oracle**：``errorCode==RUNTIME_IN_USE AND old_pid_alive==true AND old_venv_sha_equal``。
- **Evidence**：`TEST-A-GW-001`；`EVID-A-GW-001.json`；包含实际命令、exit code、pre/post digest、原始 log paths、repository SHA、Windows build、工具版本。所需原始证据：进程快照、双向 pid 观察、未修改字节哈希。

## A-PY-001 — 离线 uv + 双路径 CLI

- **Requirement Refs**：`REQ-PY-001`。
- **Given**：真实 Win10 干净用户，MSI Payload 已注册且断网。
- **When**：Init `--initialize --quiet`。
- **Then**：生成合法 venv、导入包、两处 hermes version 成功。
- **Oracle**：``uv_exit=0 AND import_exit=0 AND cli1_exit=cli2_exit=0 AND versions==0.21.0``。
- **Evidence**：`TEST-A-PY-001`；`EVID-A-PY-001.json`；包含实际命令、exit code、pre/post digest、原始 log paths、repository SHA、Windows build、工具版本。所需原始证据：uv raw logs、2x CLI stdout、Win10 OS build。

## A-PY-002 — 非法命令/继承变量不会干扰

- **Requirement Refs**：`REQ-PY-001`。
- **Given**：用户设置 UV_NO_INSTALL_PROJECT/UV_NO_SYNC/VIRTUAL_ENV，并对 PATH 放置假 uv/npm；用户名含空格。
- **When**：启动 Init 并追踪实际进程 argv。
- **Then**：仍使用随包 uv，且未启动 npm/node/install.ps1/git clone。
- **Oracle**：``cli_path==manifest_cli AND allowed_argv_valid AND forbidden_spawn_count==0``。
- **Evidence**：`TEST-A-PY-002`；`EVID-A-PY-002.json`；包含实际命令、exit code、pre/post digest、原始 log paths、repository SHA、Windows build、工具版本。所需原始证据：ETW/Procmon 进程路径、uv args、CLI SHA、进程树。

## A-TXN-001 — 初始化失败不回滚 MSI

- **Requirement Refs**：`REQ-TXN-001`。
- **Given**：MSI 注册存在，uv 被注入失败。
- **When**：Init 独立运行产生失败。
- **Then**：Runtime=REPAIR_REQUIRED，MSI 注册和静态 payload 保留。
- **Oracle**：``init_exit!=0 AND msi_registered==true AND static_sha_after==before AND receipt != READY``。
- **Evidence**：`TEST-A-TXN-001`；`EVID-A-TXN-001.json`；包含实际命令、exit code、pre/post digest、原始 log paths、repository SHA、Windows build、工具版本。所需原始证据：MSI 产品查询、Engine logs、runtime status。

## A-TXN-002 — T0 回滚及失败保留

- **Requirement Refs**：`REQ-TXN-001`。
- **Given**：已有有效 venv/CLI/receipt/env，并人为注入 uv 失败及 rollback rename 错误。
- **When**：显式 Repair，分别触发正常失败和回滚失败。
- **Then**：正常失败恢复 T0；恢复失败保留 backup/recovery.json 且不写 READY。
- **Oracle**：``normal_after_T0_hash==before_T0_hash`; rollback-error `RUNTIME_ROLLBACK_FAILED AND backup_exists``。
- **Evidence**：`TEST-A-TXN-002`；`EVID-A-TXN-002.json`；包含实际命令、exit code、pre/post digest、原始 log paths、repository SHA、Windows build、工具版本。所需原始证据：T0 ledger、SHA、rollback.json 和 VM 快照。

## A-OWN-001 — 用户资料字节保留

- **Requirement Refs**：`REQ-OWN-001`。
- **Given**：用户 .env/config.yaml/Provider sidecar 已存在，含零字节文件、UTF-8 BOM 和非 ASCII。
- **When**：执行 MSI/Init/Repair/Uninstall。
- **Then**：每个 USER_OWNED 文件完全不变。
- **Oracle**：``for_all user_paths: SHA256(before)==SHA256(after) AND exists_after``。
- **Evidence**：`TEST-A-OWN-001`；`EVID-A-OWN-001.json`；包含实际命令、exit code、pre/post digest、原始 log paths、repository SHA、Windows build、工具版本。所需原始证据：pre/post 摘要 CSV、权限与相对路径列表。

## A-OWN-002 — 缺失模板创建不覆写

- **Requirement Refs**：`REQ-OWN-001`。
- **Given**：缺失 config.yaml/.env/SOUL.md；其他同路径文件已存在。
- **When**：首次 Init + 二次 Init。
- **Then**：仅缺失文件 CreateNew；二次 no-write。
- **Oracle**：``created_files == initially_absent_templates AND preexisting_digest_equal``。
- **Evidence**：`TEST-A-OWN-002`；`EVID-A-OWN-002.json`；包含实际命令、exit code、pre/post digest、原始 log paths、repository SHA、Windows build、工具版本。所需原始证据：文件存在性表、mtime+hash、trace。

## A-SKILL-001 — 企业 Skills 占用与漂移

- **Requirement Refs**：`REQ-SKILL-001`。
- **Given**：skills/同路径分别为企业 owner、未知 owner、已改动企业文件。
- **When**：执行企业 Skills merge。
- **Then**：已知 unchanged 可更新；未知或 drift 阻断且 Skill 子事务零写；不发布 READY receipt；`--status` 为 `REPAIR_REQUIRED`；`hermes-agent\venv` 仍保留；`bin\hermes.exe` 不存在或已回到 T0。
- **Oracle**：``conflict -> SKILL_OWNERSHIP_CONFLICT AND runtimeState==REPAIR_REQUIRED AND skill_tree_digest_equal_T0 AND venv_gate_still_pass AND bin_hermes_absent_or_T0``。
- **Evidence**：`TEST-A-SKILL-001`；`EVID-A-SKILL-001.json`；包含实际命令、exit code、pre/post digest、原始 log paths、repository SHA、Windows build、工具版本。所需原始证据：企业 ledger、原树/后树 SHA、Engine event。

## A-ENV-001 — 用户环境 T0 与系统 PATH 隔离

- **Requirement Refs**：`REQ-ENV-001`。
- **Given**：已有复杂 HKCU PATH，含 Hermes 的重复形式；HKLM 值已固定。
- **When**：Init 成功、再重复，另注入 Env commit 中途失败。
- **Then**：正常去重且只有受管 HKCU entry；失败恢复 T0；HKLM byte-equal。
- **Oracle**：``HKLM_after==HKLM_before AND HKCU_after contains exactly_one_managed_entry`; failure `HKCU_after==T0``。
- **Evidence**：`TEST-A-ENV-001`；`EVID-A-ENV-001.json`；包含实际命令、exit code、pre/post digest、原始 log paths、repository SHA、Windows build、工具版本。所需原始证据：注册表导出 hash、回滚报告。

## A-OBS-001 — 完整诊断不随文件回滚丢失

- **Requirement Refs**：`REQ-OBS-001`。
- **Given**：真实 Win10，uv 模拟 exit=17 + MSI 出错分别独立触发。
- **When**：GUI/CLI 执行，并检查日志磁盘位置。
- **Then**：存在不同 operationId 目录、可读取 raw uv stderr、msiexec.log、最终 ErrorCode。
- **Oracle**：``operationId unique AND diag_exists AND log_outside_MSI_root AND stderr_contains_injected_code``。
- **Evidence**：`TEST-A-OBS-001`；`EVID-A-OBS-001.json`；包含实际命令、exit code、pre/post digest、原始 log paths、repository SHA、Windows build、工具版本。所需原始证据：两次真实操作日志、错误码 JSON。

## A-OBS-002 — 日志不可用时拒绝破坏性操作

- **Requirement Refs**：`REQ-OBS-001`。
- **Given**：Diagnostics Root 被 ACL 故意拒绝或磁盘不可写。
- **When**：调用 Preflight/Init。
- **Then**：返回 DIAGNOSTICS_UNAVAILABLE，msiexec 或 uv 未启动。
- **Oracle**：``errorCode==DIAGNOSTICS_UNAVAILABLE AND spawn_count==0 AND user_SHA_same``。
- **Evidence**：`TEST-A-OBS-002`；`EVID-A-OBS-002.json`；包含实际命令、exit code、pre/post digest、原始 log paths、repository SHA、Windows build、工具版本。所需原始证据：ACL/权限注入记录、进程跟踪、Error envelope。

## A-SEC-001 — 断网终端零主动联网

- **Requirement Refs**：`REQ-SEC-001`。
- **Given**：Win10 VM 限制公网，存在监听进程 telemetry。
- **When**：执行 Setup 一次完整 Core Install+Init。
- **Then**：不请求外部下载、仍能完成 CLI Ready。
- **Oracle**：``child_egress_attempts==0 AND status==READY`；独立记录 OS CA/OCSP`。
- **Evidence**：`TEST-A-SEC-001`；`EVID-A-SEC-001.json`；包含实际命令、exit code、pre/post digest、原始 log paths、repository SHA、Windows build、工具版本。所需原始证据：WFP/ETW/Wireshark 网络证据、进程树与 CLI logs。

## A-SEC-002 — Manifest 验签与路径防逃逸

- **Requirement Refs**：`REQ-SEC-001`。
- **Given**：篡改 MSI SHA、Root 内建立指向外部的 junction、伪造 runtime-manifest 或破坏 `.sig`。
- **When**：运行校验及 Init。
- **Then**：任一非法情形被 BLOCK，外部哨兵文件 byte-equal。本轮缺少 Authenticode **不是**失败。
- **Oracle**：``errorCode in {SIGNATURE_INVALID,RELEASE_IDENTITY_MISMATCH,PATH_ESCAPE_DENIED} AND sentinel_sha_same`；`authenticode_absent` 不得单独导致 FAIL``。
- **Evidence**：`TEST-A-SEC-002`；`EVID-A-SEC-002.json`；包含实际命令、exit code、pre/post digest、原始 log paths、repository SHA、Windows build、工具版本。所需原始证据：Ed25519 验签记录、Path dump、哨兵 SHA。禁止要求 SignTool PASS。

## A-REPAIR-001 — 初始化失败后可无网修复

- **Requirement Refs**：`REQ-REPAIR-001`。
- **Given**：MSI 已提交，uv 故障触发 REPAIR_REQUIRED，排除故障后保持断网。
- **When**：调用 `--repair`。
- **Then**：READY 且 Program MSI 无需重装。
- **Oracle**：``msi_product_code_unchanged AND repair_exit==0 AND READY AND cli_version_ok``。
- **Evidence**：`TEST-A-REPAIR-001`；`EVID-A-REPAIR-001.json`；包含实际命令、exit code、pre/post digest、原始 log paths、repository SHA、Windows build、工具版本。所需原始证据：两次 operationId、前后状态、MSI 注册信息。

## A-REPAIR-002 — Status 只读与卸载保留

- **Requirement Refs**：`REQ-REPAIR-001`。
- **Given**：READY 且存在用户文件与 runtime-receipt。
- **When**：调用 `--status`，然后直接 `msiexec /x`。
- **Then**：Status 不修改任何字节（含锁、诊断目录、用户文件）；卸载后用户文件、skill ledger 与诊断仍在。
- **Oracle**：``status_before_hash==after_hash AND uninstall_msi_removed AND user_SHA_equal``。
- **Evidence**：`TEST-A-REPAIR-002`；`EVID-A-REPAIR-002.json`；包含实际命令、exit code、pre/post digest、原始 log paths、repository SHA、Windows build、工具版本。所需原始证据：Status stdout、Procmon 文件监控、MSI log。

## A-UI-001 — 可诊断 UI 失败/成功显示

- **Requirement Refs**：`REQ-UI-001`。
- **Given**：分别模拟 uv 失败、msiexec 失败、成功。
- **When**：GUI 执行并捕获屏幕与 Engine 事件。
- **Then**：失败显示分阶段错误与日志入口；「重试」调用 `--initialize`，「重建运行时」调用 `--repair`；只有 READY 显示成功。
- **Oracle**：``UI.success => engine.runtimeState==READY`; `UI.failed.errorCode == engine.last.errorCode`; `UI.retry => initialize`; `UI.rebuild => repair``。
- **Evidence**：`TEST-A-UI-001`；`EVID-A-UI-001.json`；包含实际命令、exit code、pre/post digest、原始 log paths、repository SHA、Windows build、工具版本。所需原始证据：UI E2E 截图/DOM 断言、事件 JSON。

## A-MIG-001 — v1 MajorUpgrade 用户保留

- **Requirement Refs**：`REQ-MIG-001`。
- **Given**：Win10 VM 已安装 v1 0.21.0 并配置用户数据。
- **When**：通过 v2 MSI MajorUpgrade+Init。
- **Then**：v2 产品注册、旧 MSI 升级路径正确、用户 SHA 不变。
- **Oracle**：``new_product_version=2.0.0 AND v1_product_absent AND user_hash_same`; old cleanup 审计无用户删除`。
- **Evidence**：`TEST-A-MIG-001`；`EVID-A-MIG-001.json`；包含实际命令、exit code、pre/post digest、原始 log paths、repository SHA、Windows build、工具版本。所需原始证据：v1/v2 MSI log、v1 前快照、后 manifest+用户 digest。

## A-CI-001 — Win10 真机 Golden Consumer

- **Requirement Refs**：`REQ-CI-001`。
- **Given**：独立 Win10 22H2 x64 VM 与干净 smc-copilot Desktop。
- **When**：先离线安装 Init，再启动本地 Hermes、探测 Desktop Native Adapter。
- **Then**：Gateway/CLI 可启动，Desktop 识别本机而非复制开发机文件。
- **Oracle**：``win10_real==true AND cli_exit=0 AND adapter.state==ready AND foreign_file_copy_count==0``。
- **Evidence**：`TEST-A-CI-001`；`EVID-A-CI-001.json`；包含实际命令、exit code、pre/post digest、原始 log paths、repository SHA、Windows build、工具版本。所需原始证据：Win10 版本信息、Adapter log、Gateway health、Runner SHA。

## A-CI-002 — Release Gate 失败退出

- **Requirement Refs**：`REQ-CI-001`。
- **Given**：故意标记一个 Required AC 为 BLOCKED、一个为 SKIPPED。
- **When**：执行 Release Gate Evaluator。
- **Then**：拒绝发布且非零退出码；所有 Required PASS 才给 0。
- **Oracle**：``any(required.status!=PASS)=>release_exit!=0`; `all PASS=>release_exit==0``。
- **Evidence**：`TEST-A-CI-002`；`EVID-A-CI-002.json`；包含实际命令、exit code、pre/post digest、原始 log paths、repository SHA、Windows build、工具版本。所需原始证据：Gate JSON、CI step exit、Required AC 明细。

## A-UPD-001 — Installer 改版不升级 Agent

- **Requirement Refs**：`REQ-UPD-001`。
- **Given**：构建 config pinned Agent v0.21.0 与 MSI ProductVersion 2.0.0。
- **When**：安装并读取 GUI/CLI/Manifest，检查网络与源码来源。
- **Then**：Agent `0.21.0@041b...` 且 autoUpdateAgent=false。
- **Oracle**：``version(agent)==0.21.0 AND commit==041b... AND upgrade_spawn_count==0``。
- **Evidence**：`TEST-A-UPD-001`；`EVID-A-UPD-001.json`；包含实际命令、exit code、pre/post digest、原始 log paths、repository SHA、Windows build、工具版本。所需原始证据：Release manifest、CLI stdout、process trace。

# 21. Acceptance Input Matrix

| Case | Fresh/Existing | Path/Env | Fault | Expected State | AC |
|---|---|---|---|---|---|
| M-01 | Clean Win10 | `Administrator`，正常磁盘 | 无 | READY | A-PY-001、A-CI-001 |
| M-02 | Clean Win10 | `Zhang San`（空格） | 无 | READY | A-PRE-002 |
| M-03 | Clean Win10 | `张 三(测试)`（Unicode+括号） | 无 | READY | A-PRE-002 |
| M-04 | Clean Win10 | 有 `UV_NO_INSTALL_PROJECT/UV_NO_SYNC/VIRTUAL_ENV` | 敌对环境变量 | READY，仍用随包 uv | A-PY-002 |
| M-05 | Clean Win10 | Offline WFP deny | 无 | READY，进程树 egress=0 | A-SEC-001 |
| M-06 | Clean Win10 | Free bytes < threshold | 空间不足 | BLOCKED，0 MSI mutation | A-PRE-001 |
| M-07 | Installed v1 | 旧 Gateway 在运行 | 进程占用 | BLOCKED，旧进程仍可用 | A-GW-001 |
| M-08 | Installed v1 | Gateway 停止 | MajorUpgrade | v2 Payload+READY，用户数据保留 | A-MIG-001 |
| M-09 | Installed v2 | 用户配置已有且空文件 | 初始化/修复 | 不修改该文件 | A-OWN-001 |
| M-10 | Installed v2 | 部分模板文件缺失 | 初始化 | 仅缺失文件 CreateNew | A-OWN-002 |
| M-11 | Installed v2 | 企业 Skill 路径未知 owner | 同名冲突 | `REPAIR_REQUIRED` + `SKILL_OWNERSHIP_CONFLICT`，Skill 0 mutation，venv 保留 | A-SKILL-001 |
| M-12 | Installed v2 | venv 生成中 | uv exit 17 | REPAIR_REQUIRED，MSI intact | A-TXN-001 |
| M-13 | Installed v2 | 存在有效旧 venv | uv 失败 + rollback 失败 | ROLLBACK_FAILED，备份保留 | A-TXN-002 |
| M-14 | Installed v2 | 旧用户 PATH 复杂 | Env commit error | 恢复 HKCU T0 | A-ENV-001 |
| M-15 | Installed v2 | Logs root ACL deny | 无法写证据 | BLOCKED，0 destructive mutation | A-OBS-002 |
| M-16 | Clean Win10 | MSI SHA 被改写 | 包不可信 | BLOCKED | A-ENTRY-001、A-SEC-002 |
| M-17 | Clean Win10 | Root junction 指向外部 | 外逃路径 | BLOCKED，哨兵不变 | A-SEC-002 |
| M-18 | Installed v2 | MSI payload 缺损 | repair 请求 | PAYLOAD_REPAIR_REQUIRED | A-REPAIR-001 |
| M-19 | Installed v2 | Init 已 READY | 重复 initialize | 不重建 venv、无新 PATH entry | A-REPAIR-001、A-ENV-001 |
| M-20 | Win11 x64 | 正常 | 无 | READY，证据独立 | A-CI-001 |
| M-21 | Any | SYSTEM SID | Direct MSI | 非零退出，无 SYSTEM Hermes 注册 | A-MSI-002 |
| M-22 | Any | 已完成 MSI，未运行 Init | Direct MSI only | PAYLOAD_INSTALLED，非 READY | A-MSI-001 |

**输入集合**：`normal/empty/missing/existing/duplicate/drifted/partial/invalid/boundary/retry/failure/rollback` 均有可执行行。Win10/11 的真实版本号、补丁号、登录身份、语言、磁盘剩余空间必须存入 Evidence。2026 年 Windows 10 22H2 支持状态由企业 IT 生命周期政策单独管理，本 PRD 的兼容性验证针对明确安装基线，并不意味着微软仍提供普通技术支持。

# 22. Negative Acceptance

| Negative ID | Requirement | 禁止行为 | Injection | Oracle |
|---|---|---|---|---|
| N-001 | REQ-MSI-001 | MSI CA 执行 uv/init | `msiexec /i` 过程跟踪 | `init_spawn_count=0` |
| N-002 | REQ-SEC-001 | 终端下载脚本/npm/git clone | 断网 + 进程树追踪 | `forbidden_spawn_count=0 AND child_egress_attempts=0` |
| N-003 | REQ-UPD-001 | Installer 2.0 把 Agent 变成新 main | Source Manifest 注入新 SHA | build FAIL，`AGENT_VERSION_CHANGE_DENIED` |
| N-004 | REQ-OWN-001 | 覆写现有用户 `.env/config.yaml` | 放置异常但存在的文件 | `sha_before==sha_after` |
| N-005 | REQ-SEC-001 | junction 指向 Root 外被清理 | 外部哨兵 | `sha_external_before==after` |
| N-006 | REQ-OBS-001 | 失败只返回 MSI 1603、无原生 ErrorCode | 强制 uv exit 17 | error envelope 非空 + uv.stderr 存在 |
| N-007 | REQ-TXN-001 | Init 失败执行 MSI uninstall | uv exit 17 | MSI ProductCode 仍注册 |
| N-008 | REQ-REPAIR-001 | `--status` 改用户数据、锁或诊断目录 | 文件监控 | 0 writes |
| N-009 | REQ-GW-001 | 强制结束占用中的 Gateway | 运行中 Gateway PID | PID 存活 + venv SHA 不变 |
| N-010 | REQ-SKILL-001 | 不明 Owner 的 Skill 被覆盖 | 同路径未知 owner | Skill sub-TXN 0 writes |
| N-011 | REQ-CI-001 | BLOCKED/SKIPPED 变 Release PASS | 修改 Gate Evidence | Release 进程 exit !=0 |
| N-012 | REQ-TXN-001 | rollback 失败时删除恢复备份 | 注入 rename access denied | Backup remains, receipt != READY |
| N-013 | REQ-ENTRY-001 | GUI 二次把自身嵌入 MSI | 构建依赖 DAG 检查 | `Setup EXE` 不在 `MSI static file manifest` |
| N-014 | REQ-PY-001 | 带空格目录参数拆分 | 带空格真实 Win10 路径 | argv boundary intact, CLI exits 0 |
| N-015 | REQ-ENV-001 | PATH 修改 HKLM/其他用户 | 检查 Registry diff | HKLM SHA 不变 |
| N-016 | REQ-MIG-001 | 默认删除 `.broken-*` | 制造已有目录 | byte hash 不变 |

所有 Negative Oracle 均由对应 Required AC 的测试命令或 §23 的故障注入执行；负向测试失败视为 Required AC FAIL，不得标为“optional”。

# 23. Failure Injection

| Point | Trigger | Expected status | Rollback/retention | Evidence / AC |
|---|---|---|---|---|
| FI-01 before Preflight log | ACL deny log dir | `DIAGNOSTICS_UNAVAILABLE` | 0 payload writes | A-OBS-002 |
| FI-02 before MSI InstallFiles | bad signature / wrong hash | `RELEASE_IDENTITY_MISMATCH` | 0 MSI writes | A-ENTRY-001 |
| FI-03 during MSI InstallFiles | Windows Installer simulated file copy failure | MSI nonzero | MSI 标准事务回滚，用户状态保留 | A-MSI-001 |
| FI-04 after MSI commit before Init | 故意跳过 Init | `PAYLOAD_INSTALLED` | 程序文件保留；Init 可单独执行 | A-MSI-001、A-TXN-001 |
| FI-05 before T0 snapshot | 任意进程占用 venv 树或 `bin\hermes*.exe`（含 `python.exe`+`.pyd`） | `RUNTIME_IN_USE` | 0 venv delete/move；状态不升成 `REPAIR_REQUIRED`（若尚未 mutation） | A-GW-001 |
| FI-05b before uv argv | 对已有 venv `Remove-Item`/`rename` 访问拒绝 | `RUNTIME_IN_USE`（**不是** `UV_SYNC_FAILED`） | 0 半成品删除 | A-GW-001、A-TXN-001 |
| FI-06 after T0 snapshot / uv started | uv.exe 退出17 | `UV_SYNC_FAILED` | 新装隔离到 `runtime-backups\<op>\`；旧装恢复 T0；MSI 保留 | A-TXN-001、A-TXN-002 |
| FI-07 during uv | 断网+缓存缺 wheel | `UV_SYNC_FAILED` | 旧 venv 恢复；日志保留 | A-PY-001、A-TXN-002 |
| FI-08 after venv generated before CLI verify | 删除 `venv/Scripts/hermes.exe` | `HERMES_CLI_MISSING` | 不发布 READY；T0 恢复 | A-PY-001 |
| FI-09 after bin copy before receipt | `bin/hermes.exe` 错版本 | `HERMES_CLI_VERIFY_FAILED` | bin 回到 T0；venv 保留；本次 Env/Skill 按 §14.3 补偿 | A-TXN-002 |
| FI-10 during Skill merge | 模拟同路径 drift | `SKILL_OWNERSHIP_CONFLICT` + `REPAIR_REQUIRED` | Skill sub-TXN 0 writes；venv 保留；不 copy `bin\hermes.exe` | A-SKILL-001 |
| FI-11 after first HKCU env write | 拒绝下一字段写入 | `ENV_ROLLBACK_FAILED` 或原始失败 | T0 恢复；失败日志保留 | A-ENV-001 |
| FI-12 during receipt atomic replace | ACL deny rename | `RECEIPT_COMMIT_FAILED` | 保留旧 receipt/T0 | A-TXN-002 |
| FI-13 during T0 rollback | 恢复 rename fail | `RUNTIME_ROLLBACK_FAILED` | backup 不删除 + recovery.json | A-TXN-002 |
| FI-14 after Ready on repeat | 第二次 Init 同 identity | READY | 不重建 venv/修改 PATH | A-REPAIR-001 |
| FI-15 during v1 MajorUpgrade | v1 Cleanup 卸载事件发生 | `MIGRATION_BLOCKED` 如果 USER_OWNED SHA 变化 | VM 快照恢复；不发布 | A-MIG-001 |

**测试隔离**：任何 destructive fault injection 必须在具备快照恢复能力的专用 Windows VM 内进行；不能在员工生产电脑上注入 venv 删除、MSI 卸载或拒绝 ACL。FI-11 原错误与回滚错误必须分别记录：若恢复成功，原操作错误为主、`rollbackOk=true`；若恢复失败，顶层 `ENV_ROLLBACK_FAILED` 并在 `causes[]` 留原错误。

# 24. Evidence Contract

## 24.1 Machine-readable Evidence Schema v1

```json
{
  "schemaVersion": 1,
  "acceptanceId": "A-TXN-001",
  "status": "PASS",
  "requirementIds": ["REQ-TXN-001"],
  "testIds": ["TEST-A-TXN-001"],
  "repository": "https://github.com/smc-copilot/hermes-builder",
  "branch": "master",
  "commitSha": "<real-current-40hex>",
  "runtimeSourceCommit": "041b6985a00d01b54f830c1607dd370007a306bf",
  "releaseManifestSha256": "<64hex>",
  "msiSha256": "<64hex>",
  "runId": "<UUID-v4>",
  "operationId": "<UUID-v4>",
  "executedAtUtc": "<RFC3339>",
  "platform": {"osName": "Windows 10", "osBuild": "19045", "arch": "AMD64", "userSid": "<redacted-sid-reference>"},
  "tools": {"powershell": "5.1", "wix": "5.0.2", "uv": "<from-bundle>", "msiexec": "<actual-version>"},
  "command": "<actual-test-command>",
  "exitCode": 0,
  "oracle": {"type": "registered_product_and_receipt", "expected": "REPAIR_REQUIRED", "actual": "REPAIR_REQUIRED", "pass": true},
  "preDigests": [{"pathClass": "PROGRAM_MANAGED", "sha256": "<64hex>"}],
  "postDigests": [{"pathClass": "PROGRAM_MANAGED", "sha256": "<64hex>"}],
  "evidenceFiles": ["<relative-path-to-raw-log>"],
  "evidenceFilesSha256": ["<sha256-of-corresponding-raw-file>"]
}
```

示例含 `<...>` 的字段仅用于说明 schema；生产 Evidence 任何字段若保留占位符一律 `FAIL`。`status` enum：`PASS|FAIL|SKIPPED|BLOCKED`；`additionalProperties=false`。所有 Required AC 必须有 `command/exitCode/oracle(expected,actual,pass)/repo/commit/branch/timestamp/tools/platform/msiSha256`，原始日志文件 SHA 非空；只含 `{"status":"PASS"}` 的 Evidence 无效。`EVID-A-*.json` 由独立 QA Runner 根据命令真实输出产生，运行中的安装器不得自行写 QA PASS。

## 24.2 Evidence Integrity / Retention

- 真实 Win10 Oracle 不允许用 GitHub `windows-2022`、`windows-latest`（可能是 Windows Server）或 PowerShell Stub 冒充。
- 单独保存 Build Gate 的 `offlineProof` 与真实 install transcript；构建机使用 `git diff --exit-code` 确认源码和受控工作树状态。
- 以 `runId` 将 Win10、Win11、MSI v1 Upgrade、GUI/企业静默、强制故障注入的证据隔离。
- 证据不得包含任何 API Key、`.env` 明文、用户模型推理数据；路径中用户名输出采用稳定匿名 ID，但必须可判定是否包含空格/中文/括号。
- 对于失败的操作，`EVID` 可以合法为 `FAIL` 或 `BLOCKED`，但不能填充假 `PASS`；原始日志和恢复目录保留。

# 25. Release Gate

**Release Gate 定义**：`REQUIRED_AC = §20 的全部 A-*（共 28 项）`。任何一项不是 `PASS`，Release 总状态必须为 `FAIL`（用户界面展示时可标 `BLOCKED`，但发行入口 `process exit != 0`），不得创建正式发布 Tag / 安装包 Release。若 `A-CI-001` 未获取真 Win10 证据，必须 `BLOCKED`，不能用 Stub PASS。

| Gate | Required Evidence Group | 判定 | 当前状态 |
|---|---|---|---|
| R-01 Build Identity | A-SRC-001 / A-BUILD-001 / A-BUILD-002 / A-UPD-001 | 全部 PASS | BLOCKED：v2 未实施 |
| R-02 MSI / Distribution | A-MSI-001/002 / A-ENTRY-001 / A-PRE-001/002 | 全部 PASS | BLOCKED |
| R-03 Runtime / Transactions | A-GW-001 / A-PY-001/002 / A-TXN-001/002 | 全部 PASS | BLOCKED |
| R-04 Ownership | A-OWN-001/002 / A-SKILL-001 / A-ENV-001 | 全部 PASS | BLOCKED |
| R-05 Offline / Security | A-SEC-001/002（Ed25519 + 路径；**不含** Authenticode） | 全部 PASS | BLOCKED |
| R-06 Diagnostics / Repair / UI | A-OBS-001/002 / A-REPAIR-001/002 / A-UI-001 | 全部 PASS | BLOCKED |
| R-07 Upgrade | A-MIG-001 | PASS | BLOCKED：无 v1→v2 真机证据 |
| R-08 Golden / Governance | A-CI-001/002 | PASS | BLOCKED：无 Win10 Native Adapter 证据 |

Release Evaluator 接收验证过 schema 的 Evidence list：缺失 AC → `BLOCKED`，oracle.pass=false → `FAIL`，`SKIPPED` → `FAIL`。计算 `all(status==PASS)` 作为唯一成功条件，其他情况进程非零退出。**本 PRD 仅是规范，不表示 v2 产物存在或上述 Gate 通过。**

# 26. Golden Consumer / Real-world Acceptance

## 26.1 Real Windows Matrix

| Golden ID | OS / Environment | Login context | Path | Purpose |
|---|---|---|---|---|
| GC-W10-01 | Win10 22H2 x64，记录 OS Build+补丁 | 标准非 SYSTEM 交互用户 | Administrator | Clean MSI+Bootstrap+Gateway |
| GC-W10-02 | Win10 22H2 x64 | 带空格和中文用户名 | `%LOCALAPPDATA%\hermes` | uv argv/CP936/Unicode 路径 |
| GC-W10-03 | Win10 22H2 x64 | 管理员交互用户（非 SYSTEM） | AppData Local | v1→v2 MajorUpgrade |
| GC-W10-04 | Win10 22H2 x64 | 交互用户 | 非生产测试 VHD | 离线/WFP 网络审计、故障注入 |
| GC-W11-01 | Win11 x64 | 标准用户 | AppData Local | 跨 Windows 回归 |
| GC-DESKTOP | 与上述 Win10 相同机器 | smc-copilot 已安装用户 | native Hermes path | Native adapter 识别 / Gateway local probe |

## 26.2 Golden Consumer Execution Protocol

1. QA 对 Win10 VM 建立干净快照，记 `smc-copilot`、`hermes-builder`、Hermes Source 的真实 Repo URL / HEAD SHA / clean status。
2. 记录用户状态基线（`.env`、`config.yaml`、Skills、`runtime-provider-*.json`）的存在性与 SHA；对没有用户文件的全新 VM 明确记 EMPTY SET。
3. 禁用终端公网访问的测试必须从 MSI 安装前开始，结束于 Runtime Ready/错误码采集后；OS 验证流量单独归因。
4. 用发行 Setup EXE 完成一次安装，再从独立干净快照测试 Direct MSI + `HermesRuntimeInit.exe --initialize --quiet` 两步。
5. 对 `Hermes Agent v0.21.0` 两处 CLI version 采集 process exit 和首行；在显式测试配置下启动/检查本地 Gateway，登录前后不得靠复制另一个机器的 `venv/config.yaml/runtime-provider-*.json`。
6. 打开指定 SHA 的 `smc-copilot` Desktop，调用本机 Native Runtime Probe：`runtimeFound=true/cliAvailable=true/gatewayHealthy=true/authenticated=true`；测试 API server credential 应从受控的 QA fixture 获取，**Installer 自身绝不写企业模型 Provider**。
7. 如需测试 Nodeskclaw 用户登录与模型 Provider 投影，另在通过 Runtime Ready 后执行**在线**业务 Golden；它不能充当离线安装证明。对于业务登录失败，写独立 Failure Evidence，不把问题归咎于 MSI。
8. 保存所有前后快照、用户数据摘要、MSI ProductCode、文件真实路径、进程树、网络证据和完整日志；人工执行结果也必须转成机器可验证的 Evidence Schema。

## 26.3 Golden Acceptance

`GC-W10-01/02/03/04` 与 `GC-DESKTOP` 未执行时 `A-CI-001=BLOCKED`，**不能**将 Windows Server 构建机的测试声明为兼容 Windows 10。只有真实系统镜像和 Desktop Probe 输出，才是 Runtime/业务集成的 Golden Consumer Evidence。

# 27. Requirement Traceability Matrix

以下表为完整 Req → Invariant → AC → Test → Evidence → Release Gate；每个 Required AC 在 §20 有 Given/When/Then/Oracle，在 §24 有 Evidence schema。

| Requirement | Invariant | Acceptance | Test | Evidence | Release Gate |
|---|---|---|---|---|---|
| `REQ-SRC-001` | `INV-ID-001` | `A-SRC-001` | `TEST-A-SRC-001` | `EVID-A-SRC-001.json` | `R-01` REQUIRED |
| `REQ-BUILD-001` | `INV-BUNDLE-001` | `A-BUILD-001` | `TEST-A-BUILD-001` | `EVID-A-BUILD-001.json` | `R-01` REQUIRED |
| `REQ-BUILD-001` | `INV-BUNDLE-001` | `A-BUILD-002` | `TEST-A-BUILD-002` | `EVID-A-BUILD-002.json` | `R-01` REQUIRED |
| `REQ-MSI-001` | `INV-MSI-001` | `A-MSI-001` | `TEST-A-MSI-001` | `EVID-A-MSI-001.json` | `R-02` REQUIRED |
| `REQ-MSI-001` | `INV-MSI-001` | `A-MSI-002` | `TEST-A-MSI-002` | `EVID-A-MSI-002.json` | `R-02` REQUIRED |
| `REQ-ENTRY-001` | `INV-ID-002` | `A-ENTRY-001` | `TEST-A-ENTRY-001` | `EVID-A-ENTRY-001.json` | `R-02` REQUIRED |
| `REQ-PRE-001` | `INV-PRE-001` | `A-PRE-001` | `TEST-A-PRE-001` | `EVID-A-PRE-001.json` | `R-02` REQUIRED |
| `REQ-PRE-001` | `INV-PRE-001` | `A-PRE-002` | `TEST-A-PRE-002` | `EVID-A-PRE-002.json` | `R-02` REQUIRED |
| `REQ-GW-001` | `INV-PROC-001` | `A-GW-001` | `TEST-A-GW-001` | `EVID-A-GW-001.json` | `R-03` REQUIRED |
| `REQ-PY-001` | `INV-CLI-001` | `A-PY-001` | `TEST-A-PY-001` | `EVID-A-PY-001.json` | `R-03` REQUIRED |
| `REQ-PY-001` | `INV-CLI-001` | `A-PY-002` | `TEST-A-PY-002` | `EVID-A-PY-002.json` | `R-03` REQUIRED |
| `REQ-TXN-001` | `INV-TXN-001|INV-TXN-002` | `A-TXN-001` | `TEST-A-TXN-001` | `EVID-A-TXN-001.json` | `R-03` REQUIRED |
| `REQ-TXN-001` | `INV-TXN-001|INV-TXN-002` | `A-TXN-002` | `TEST-A-TXN-002` | `EVID-A-TXN-002.json` | `R-03` REQUIRED |
| `REQ-OWN-001` | `INV-OWN-001` | `A-OWN-001` | `TEST-A-OWN-001` | `EVID-A-OWN-001.json` | `R-04` REQUIRED |
| `REQ-OWN-001` | `INV-OWN-001` | `A-OWN-002` | `TEST-A-OWN-002` | `EVID-A-OWN-002.json` | `R-04` REQUIRED |
| `REQ-SKILL-001` | `INV-SKILL-001` | `A-SKILL-001` | `TEST-A-SKILL-001` | `EVID-A-SKILL-001.json` | `R-04` REQUIRED |
| `REQ-ENV-001` | `INV-ENV-001` | `A-ENV-001` | `TEST-A-ENV-001` | `EVID-A-ENV-001.json` | `R-04` REQUIRED |
| `REQ-OBS-001` | `INV-OBS-001` | `A-OBS-001` | `TEST-A-OBS-001` | `EVID-A-OBS-001.json` | `R-06` REQUIRED |
| `REQ-OBS-001` | `INV-OBS-001` | `A-OBS-002` | `TEST-A-OBS-002` | `EVID-A-OBS-002.json` | `R-06` REQUIRED |
| `REQ-SEC-001` | `INV-SEC-001` | `A-SEC-001` | `TEST-A-SEC-001` | `EVID-A-SEC-001.json` | `R-05` REQUIRED |
| `REQ-SEC-001` | `INV-SEC-001` | `A-SEC-002` | `TEST-A-SEC-002` | `EVID-A-SEC-002.json` | `R-05` REQUIRED |
| `REQ-REPAIR-001` | `INV-REPAIR-001` | `A-REPAIR-001` | `TEST-A-REPAIR-001` | `EVID-A-REPAIR-001.json` | `R-06` REQUIRED |
| `REQ-REPAIR-001` | `INV-REPAIR-001` | `A-REPAIR-002` | `TEST-A-REPAIR-002` | `EVID-A-REPAIR-002.json` | `R-06` REQUIRED |
| `REQ-UI-001` | `INV-UI-001` | `A-UI-001` | `TEST-A-UI-001` | `EVID-A-UI-001.json` | `R-06` REQUIRED |
| `REQ-MIG-001` | `INV-MIG-001` | `A-MIG-001` | `TEST-A-MIG-001` | `EVID-A-MIG-001.json` | `R-07` REQUIRED |
| `REQ-CI-001` | `INV-CI-001` | `A-CI-001` | `TEST-A-CI-001` | `EVID-A-CI-001.json` | `R-08` REQUIRED |
| `REQ-CI-001` | `INV-CI-001` | `A-CI-002` | `TEST-A-CI-002` | `EVID-A-CI-002.json` | `R-08` REQUIRED |
| `REQ-UPD-001` | `INV-UPD-001` | `A-UPD-001` | `TEST-A-UPD-001` | `EVID-A-UPD-001.json` | `R-01` REQUIRED |

# 28. Plan Generation Contract

**当前 front matter `status=APPROVED_FOR_PLAN`。** 允许生成正式 `.plan.md`。设计审查 Gate 与实际 Release Gate 分离；`A-CI-001` 的 Win10 真机结果属于 Release Gate，不能伪装成计划批准证据。

## 28.1 Plan Approval Gate（Design Review，2026-10-09 全部 PASS）

签署人一律为 **SMC Copilot Hermes**。记录：`docs/specs/2026-10-09-enterprise-installer-v2-g-p-review.md`。

| Gate | 唯一可审标准 | 当前状态 | 审核主体 |
|---|---|---|---|
| G-P01 | MSI 与 Bootstrap 的代码执行职责无重叠，MSI 不再含 uv Custom Action | PASS | Windows Installer |
| G-P02 | GUI 内嵌 MSI / Direct MSI 的 Build DAG 无哈希循环与 EXE 自嵌 | PASS | Build/Release |
| G-P03 | `SourceCommit=041b...`、Agent v0.21.0、Installer ProductVersion=2.0.0 均锁定 | PASS | Runtime/QA |
| G-P04 | 新旧 venv/CLI/Env/Skills 的 T0、Commit、Rollback Failure 和备份保留均唯一 | PASS | Runtime/Security |
| G-P05 | Program/User/Generated 文件 Owner 明确，包括 v1 Cleanup 与 Direct MSI 语义 | PASS | Installer/Desktop |
| G-P06 | 全量 Hash scope、Ed25519 Manifest 签名次序、路径规范、禁读写界限一致；**且** CI Secret `HERMES_MANIFEST_ED25519_SEED_B64` 已真实存在。**本 Gate MUST NOT 要求 Authenticode 证书**（`NON-GOAL-007`） | PASS（`keyId=e6199f4b558ab9c4`；仓库 Actions Secret 名称已见 `smc-copilot/hermes-builder`）。Authenticode 不在本 Gate | Security/Build |
| G-P07 | §20–27 全部 Required AC（28 项）有 Given/When/Then/Oracle 与 Evidence Schema。**本 Gate 不要求 Golden 已跑完**；Win10/升级真机执行属于 Release Gate R-08 / `A-CI-001` | PASS（schema only） | QA |
| G-P08 | 不存在文档内 `SPEC_SEMANTIC_GAP`，No-Inference Rule 生效，受控审查结论有**具名 Reviewer 签名记录** | PASS | Architecture Owner |

**状态变更算法**：只有 G-P01…G-P08 全部由对应 Reviewer 标记 PASS 并附评审记录路径，才允许 `status=APPROVED_FOR_PLAN`；任一 Gate FAIL/REVIEW/BLOCKED 时不得生成 `.plan.md`。Plan Approval 不要求实现已经完成，不要求全部 Release AC PASS。

## 28.2 Semantic Gap and Coverage

Grill `docs/specs/2026-10-09-enterprise-installer-v2-grill.md` Q1–Q24 已写入本文，原 GAP-SKILL-READY / GAP-FRESH-FAIL / GAP-HOLDER / GAP-PURGE / GAP-DIRECT-STATE / GAP-STATUS-WRITE 不得再作第二种解读。任何实施方若仍发现例如 UI 打包体积/签名执行链、不明 MSI 组件 Owner、OPSI 执行身份有两种解读，必须返回 `SPEC_SEMANTIC_GAP` 并定位具体 §/Req；不能依赖开发者常识“择优实现”。`MUST/MUST NOT → Req → AC → Oracle → Evidence` 静态检查必须 100% 覆盖。

## 28.3 Plan Readiness

```text
[x] G-P01..G-P08 获得架构评审记录（docs/specs/2026-10-09-enterprise-installer-v2-g-p-review.md；签署人 SMC Copilot Hermes / 2026-10-09）
[x] 所有 Must / Must Not 有可判定 Oracle（REQ→AC；N-* 未全覆盖但 AC 可判定）
[x] 无未界定的 Owner/State/Hash/Default/Conflict/Failure（grill Q1–Q24 + G-P 审查补丁）
[x] Runtime version lock 明确，自动升级 Agent 被禁用
[x] Source PRD / Baseline SHA 已由 Reviewer 复核（G-P03：`7d77737` / `041b6985`）
[x] status 经授权改为 APPROVED_FOR_PLAN
```

# 29. `.plan.md` 输出标准

每个 Plan Todo 必须含字段：

```yaml
id: PLAN-PHASE-A-001
requirement_refs: ["REQ-MSI-001"]
acceptance_refs: ["A-MSI-001", "A-MSI-002"]
files_or_symbols: ["installer/Package.wxs"]
implementation_goal: "移除两个长时 Custom Action，保留 MSI 标准文件安装"
preconditions: ["PRD status APPROVED_FOR_PLAN", "固定 Source SHA"]
state_transition: "ABSENT -> PAYLOAD_INSTALLED"
side_effect_scope: ["MSI PROGRAM_MANAGED files only"]
failure_cases: ["MSI_INSTALL_FAILED", "INSTALL_IDENTITY_DENIED"]
verification: ["TEST-A-MSI-001", "TEST-A-MSI-002"]
status: planned
evidence: []
```

`status` 只能为 `planned|implemented|verified|blocked`：`implemented` 仅代表代码存在；只有具体 AC 已真实执行且 Evidence Schema 校验 PASS，才允许 `verified`。Plan 不得把 `TEST-*.ps1` 文件存在或 CI 绿灯当作 Golden Consumer 完成。

# 30. Code Review Contract

Review 顺序固定为 `(1) Requirements (2) State Authority (3) Side Effects (4) Failure Postcondition (5) Ownership (6) Drift (7) AC Coverage (8) Evidence Integrity (9) Edge Cases (10) Code Quality`。针对本项目额外检查：是否意外更改 Agent Source SHA；是否把 uv sync 放回 MSI Transaction；是否使 `hermes.exe` 路径偏离 Desktop Native Adapter；是否存在 `Start-Process -ArgumentList` 的带空格路径引用错误；是否存在旧 Tauri Bootstrap 的下载入口；是否只有 1603 而缺少 ErrorCode；是否丢失 user-state 与 Gateway 进程占用保护。

# 31. PRD Quality Gate

| Category | Static rule | Design readiness | Release Evidence |
|---|---|---|---|
| Architecture | Goal/Scope/Owner/Boundary 无重叠 | PASS（G-P08） | v2 尚未实现 |
| State | MSI SOT / Runtime Receipt / User SOT 分离 | PASS（G-P04/G-P05） | BLOCKED |
| Semantics | Default/Owner/Hash/Conflict 唯一 | PASS（G-P08） | BLOCKED |
| Side Effects | 每个外部进程/Registry/File 都有作用域 | PASS（G-P01/G-P05） | BLOCKED |
| Failure | Runtime T0、回滚失败保留、错误码与退出码 | PASS（G-P04） | BLOCKED |
| Acceptance | Req/AC/Negative/Failure Matrix 覆盖 | PASS（G-P07 schema） | BLOCKED |
| Evidence | SHA/Repo/RunId/Oracle/Command/OS Build | PASS（schema）；真机未跑 | BLOCKED |
| Plan | 仅 APPROVED_FOR_PLAN 可生成正式 plan | APPROVED_FOR_PLAN | 不适用 |

静态“SPECIFIED”不等于“经审核无语义缺口”，更不等于任何代码已完成；不得因为阅读本文的模型判断其可行就静默更改状态。

# 32. PRD 禁止写法与工程约束

本 PRD 中出现的 `MUST` 均对应 §10 的具体 Req、§20 的 AC 和 §22 的 Negative。禁止把如下语义作为可发布定义：`稳定安装`、`安全更新`、`合理回滚`、`自动解决冲突`、`安装正常`、`测试通过即可`。本版必须以 `ExitCode/ErrorCode`、文件原始 SHA、MSI Product Registry、Receipt Identity、0 network attempts、T0/rollback Digest 等机器可判定条件代替。

**不允许的 PRD 改动**：在实施计划中将 `Installer 2.0.0` 偷换为 `Hermes Agent 2.0.0`；把当前 `smc-copilot/hermes-agent/main` 当成默认打包源；仅删除 `InitializeHermes` 而不提供 Direct MSI 后续初始化命令；用 Windows Server CI 代替 Win10 Golden；将现有 v1 `status=APPROVED_FOR_PLAN` 视为 v2 已批准。

# 33. ID 体系

- Requirement：`REQ-{SRC|BUILD|MSI|ENTRY|PRE|GW|PY|TXN|OWN|SKILL|ENV|OBS|SEC|REPAIR|UI|MIG|CI|UPD}-001`。
- Invariant：`INV-{category}-001/002`，对照 §10。
- Acceptance：`A-{category}-001/002`，全部 Required；Test：`TEST-A-*`；Evidence：`EVID-A-*.json`。
- Fault Injection：`FI-01...FI-15` 与 `FI-05b`；Negative：`N-001...N-016`；Release Gate：`R-01...R-08`；Plan Approval Gate：`G-P01...G-P08`。
- Operation ID：符合 RFC 4122 UUIDv4，整个一次 GUI/CLI 安装生命周期唯一；QA RunID 与用户 OperationID 分列。

# 34. PRD 最小完整结构与代码改造清单

## 34.1 逐文件落地清单（基于 `hermes-builder@7d777373`）

| File/Directory | Action | Precise change | Refs |
|---|---|---|---|
| `installer/Package.wxs` | MODIFY | 去除四项 Set*/deferred Preflight/Initialize CA；保留 Files-only/旧 UpgradeCode；Standard per-user MSI；检查 old Cleanup 条件 | REQ-MSI-001、REQ-MIG-001 |
| `installer/HermesEnterprise.Setup.wixproj` | MODIFY | 独立 MSI ProductVersion 2.0.0，Installer/Agent 版本分离；产品名称及输出目录 | REQ-SRC-001 |
| `build-config.json` | MODIFY | `product.version=2.0.0`、`source.expectedVersion=0.21.0`、`source.ref=041b...` 不变；加入 v2 offline/identity schema | REQ-SRC-001、REQ-UPD-001 |
| `build/Build.ps1` | MODIFY | 依次编译 Rust Init（本轮无 Authenticode）、复制至 Payload、冻结静态树、Ed25519 签名 Runtime Manifest、构建 MSI、写 Release Manifest、编译 Tauri Setup | REQ-ENTRY-001、REQ-BUILD-001 |
| `build/Prepare-Source.ps1` | VERIFY/MODIFY | Release 继续 pinned SHA、clean tree，无 pull；区分 reference repo 与 actual packaged source | REQ-SRC-001 |
| `build/Prepare-OfflineDependencies.ps1` | MODIFY | 同终端 argv 的构建机离线 proof；记录 venvEstimatedBytes/树哈希；标明 Core 不在终端跑 Node/npm | REQ-BUILD-001 |
| `build/Generate-Manifest.ps1` | MODIFY | 增加全量 Payload tree manifest v2 + detached Ed25519 签名；排除自引用、添加路径 canonicalization/case-collision 校验 | REQ-BUILD-001 |
| `build/Prepare-EnterpriseContent.ps1` | MODIFY | Stage `HermesRuntimeInit.exe`；不把 GUI EXE 反向打包到 MSI | REQ-ENTRY-001 |
| `scripts/Initialize-Hermes.ps1` | DEPRECATE from MSI | 不再被 WiX/安装器调用；Runtime Engine 实现等价但增强的离线 uv/事务；仅保留旧版本兼容测试样例 | REQ-MSI-001、REQ-PY-001 |
| `scripts/Preflight-HermesInstall.ps1` | DEPRECATE from MSI | Preflight 职责移到 MSI 前 Rust Engine，manifest payload verify 在 MSI 后 | REQ-PRE-001 |
| `scripts/Cleanup-Hermes.ps1` | MODIFY | 不允许新 MSI 调用 deferred `Return=ignore` 做生成文件静默清理；迁移/卸载规则由 Runtime Init 显式管理 | REQ-REPAIR-001 |
| `scripts/Install-HermesMsi.ps1` | MODIFY | 企业入口调用文件安装后 `HermesRuntimeInit.exe --initialize --quiet`；必要时保留两个退出码、按 operationId 创建持久日志 | REQ-ENTRY-001、REQ-OBS-001 |
| `scripts/Repair-Hermes.ps1` | MODIFY | Wrapper 改调用 Rust `--repair`；若 Program Payload 缺损只提示标准 MSI 修复步骤 | REQ-REPAIR-001 |
| `scripts/Verify-Installation.ps1` | MODIFY | 实际源路径两处 CLI、receipt/manifest、Program ProductRegistration 全部验证；无模型 API 请求 | REQ-PY-001、REQ-REPAIR-001 |
| `enterprise/skills/**` / `scripts/Install-EnterpriseSkills.ps1` | MODIFY | Owner Ledger、last-applied SHA、冲突 0 mutation | REQ-SKILL-001 |
| `installer-core/` (new Rust crate) | CREATE | State Machine、T0 Journal、Process Holder Scan、Process Launcher、Path Protection、Diagnostics、Error Envelope、Receipt | REQ-TXN-001 等 |
| `installer-cli/` (new Rust binary) | CREATE | `HermesRuntimeInit.exe` CLI / status / repair / diagnostics；通过共享 Engine 复用 | REQ-ENTRY-001、REQ-REPAIR-001 |
| `installer-ui/` (new Tauri package) | CREATE | 移植参考仓库 Tauri stage stream 与失败页面，但替换为离线 Engine API，不再下载 install.ps1 | REQ-UI-001 |
| `tests/windows-live/*` | CREATE | 真实 Win10 的 `msiexec /i` 原生 MSI 测试、PowerShell 5.1 与实际 Windows 用户环境 | REQ-CI-001 |
| `.github/workflows/build-msi.yml` | MODIFY | Build + Static Proof 与独立真实 Win10 Release Gate；没有 Win10 runner 时不可 Release | REQ-CI-001 |
| `docs/runbooks/hermes-installer-v2.md` | CREATE | 用户安装、企业 Direct MSI 双步骤、故障码表、日志导出、OPSI Context 限制 | REQ-OBS-001、REQ-ENTRY-001 |

**边界说明**：`installer-core/` 与 `installer-ui/` 是建议新目录，由本仓库实现/持有；允许借鉴 `smc-copilot/hermes-agent/apps/bootstrap-installer` 的 UI/事件形态，但该源中的 `install.ps1 -Stage` 在线编排不得进入终端 v2。上游 `hermes_cli/_scan_venv_blockers.py` 可以作为 Windows 进程扫描行为的参考，但发布后代码归 `installer-core`，禁止运行时依赖 Python 模块先存在才能扫描。

## 34.2 实施批次（不是 `.plan.md`）

| Batch | Scope | Implementation Gate | Required Tests |
|---|---|---|---|
| B0 Baseline | SHA/Manifest/Build Proof、签名/包产物冻结 | 确认可构建 single MSI 与独立版本 | TEST-A-SRC-001、TEST-A-BUILD-001/002、TEST-A-UPD-001 |
| B1 MSI Core | WiX Files-only，Init Rust CLI，先行 Preflight | Direct MSI→PAYLOAD_INSTALLED，Init 独立可执行 | TEST-A-MSI-001/002、TEST-A-ENTRY-001、TEST-A-PRE-001/002 |
| B2 Runtime | uv/CLI、占用扫描、T0、Env、用户/Skills、日志 | 失败可修复、MSI 保留、Runtime Ready 有 Receipt | TEST-A-GW-001、TEST-A-PY-001/002、TEST-A-TXN-001/002、TEST-A-ENV-001 |
| B3 UI | Tauri GUI，详细进度、日志、修复入口 | 单一 Setup EXE 支持用户安装 | TEST-A-UI-001、TEST-A-OBS-001/002、TEST-A-REPAIR-001/002 |
| B4 Migration | 原 v1 MajorUpgrade、OPSI per-user contract | v1 用户 SHA 不变 | TEST-A-MIG-001、TEST-A-OWN-001/002、TEST-A-SKILL-001 |
| B5 Release | Win10/11 零网、故障注入、Desktop Golden、CI Gate | 全部 Required AC PASS | TEST-A-SEC-001/002、TEST-A-CI-001/002 |

每个 Batch 进入具体 `.plan.md` 前必须满足 `status=APPROVED_FOR_PLAN`；本表不替代正式 Plan。

## 34.3 交付包、命令与用户体验的严格口径

发布目录：

```text
dist/
  Hermes-Setup-2.0.0-win-x64.exe          # primary end-user one-click entry
  Hermes-Core-2.0.0-win-x64.msi           # enterprise per-user direct install
  release-manifest-v2.json               # binds MSI hash / source identity
  build-info.json                        # signed/unreleasable/build proof
  *.sha256
  evidence/                              # QA evidence, not user delivery unless explicitly requested
```

使用者双击 Setup.exe：Preflight → MSI Payload → offline Init → CLI verify → READY 或错误页（日志可导出）。企业在当前交互用户 Session 内：

```powershell
$msi = 'D:\Release\Hermes-Core-2.0.0-win-x64.msi'
$home = Join-Path $env:LOCALAPPDATA 'hermes'
$log = Join-Path $env:LOCALAPPDATA 'SMC\HermesInstaller\InstallerLogs\enterprise-msi.log'
& msiexec.exe /i "$msi" /qn /norestart /L*V! "$log"
if ($LASTEXITCODE -eq 3010) { exit 3010 }
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
& (Join-Path $home 'bootstrap\HermesRuntimeInit.exe') --initialize --quiet --manifest (Join-Path $home 'runtime-manifest-v2.json')
exit $LASTEXITCODE
```

上例是 **v2 目标 CLI**，旧版本仓库尚不存在 `HermesRuntimeInit.exe`；不能在未开发完成的终端上直接执行。企业实际脚本还必须先通过发布 Manifest 的 MSI SHA 与 runtime-manifest Ed25519 预检（本轮不做 Authenticode 预检），并把每次执行日志放到 UUID session，而不是在生产中沿用示例的固定 `enterprise-msi.log`。

# 35. Definition of Done

| DoD | Condition | Current |
|---|---|---|
| D-01 | §10 每个 REQ 对应 §20 Given/When/Then/Oracle/Evidence | SPECIFIED（未评审） |
| D-02 | §12 Ownership 全路径分组且未知归属 PRESERVE | SPECIFIED |
| D-03 | §13 全量 Tree SHA、Source/Agent/Installer 版本分离 | SPECIFIED |
| D-04 | §14 MSI_TXN 与 INIT_TXN、T0/Commit/Rollback/Failure 全定义 | SPECIFIED |
| D-05 | §15 所有冲突默认动作、0 mutation 范围明确 | SPECIFIED |
| D-06 | §21/22/23 含边界输入、负向测试、故障注入 | SPECIFIED |
| D-07 | §24 每个 Required AC 有真实命令+Oracle+原始 Evidence | BLOCKED（未运行） |
| D-08 | §25 Release Gate 全 Required=PASS，否则非零 | BLOCKED（v2 未实现） |
| D-09 | §26 真 Win10、v1 MajorUpgrade、Desktop Golden 验证 | BLOCKED（未执行） |
| D-10 | §28 G-P01..G-P08 批准，front matter APPROVED_FOR_PLAN | PASS（2026-10-09） |
| D-11 | Installer v2 产品发布与 Agent v0.21.0 源码保持锁定 | BLOCKED（新产物未创建） |
| D-12 | 重新安装、Repair、失败、Uninstall 后 User State digest 不变 | BLOCKED（未执行） |

**Plan DoD**：满足 §28 全部 G-P01..G-P08、`status=APPROVED_FOR_PLAN`，才允许产出正式 `.plan.md`。**Release DoD**：满足 §25 八个 Release Gate、全部 Required AC 有真实 PASS 证据且 Ed25519/审计/Golden Consumer 真实可复核，才允许发布 Hermes Enterprise Installer v2。本轮 Release DoD **MUST NOT** 含 Authenticode。

# 36. 最终原则

1. **InstallerVersion 与 AgentVersion 双轴独立**：`Installer v2.0.0` 没有授权 `Hermes Agent v0.21.0` 升级到新 Commit。
2. **MSI 只负责 Program Payload**：uv/venv/Gateway 初始化必须在独立事务内完成。
3. **MSI COMMIT != Runtime READY**：Runtime Receipt 与 CLI 观测必须共同满足才显示 READY。
4. **失败时程序留存、日志可查、修复可重试**：但不通过禁用 Windows Installer 自身文件事务回滚来实现。
5. **Python venv 最终路径构建**：不能无验证地跨路径复制构建机 venv，也不能移动新 venv 后假定 shebang 可用。
6. **Windows 占用先检查后变更**：不自动杀 Gateway、不越权替其他用户清理进程。
7. **用户数据保持字节级所有权**：`config.yaml/.env`、Provider sidecar、Skills 冲突路径都不得隐式覆盖。
8. **离线网络边界精确限定于安装进程树**：构建机联网和安装后的模型业务请求不属于该 Oracle。
9. **同一 MSI 多机安装必须有真 Win10 Evidence**：构建/Stub 测试不能替代端点验证。
10. **No Inference / No Fake PASS**：代码或测试未执行时不得将 PRD、Plan、Release 状态标成 VERIFIED。

---

## 源码定位索引（固定审阅 Commit）

- Builder：`https://github.com/smc-copilot/hermes-builder/tree/7d77737353d134b5169f85f73f71d094a74635dc`
- Builder WiX：`installer/Package.wxs` / `installer/HermesEnterprise.Setup.wixproj`
- Builder Init：`scripts/Initialize-Hermes.ps1` / `scripts/Preflight-HermesInstall.ps1`
- Builder Pipeline：`build/Prepare-OfflineDependencies.ps1` / `build/Build.ps1` / `.github/workflows/build-msi.yml`
- Builder v1 工程契约：`docs/prd/PRD-HERMES-BUILDER-MSI-OFFLINE-HARDENING-v1.0.md`
- Runtime reference：`https://github.com/smc-copilot/hermes-agent/tree/c16cc4ca7597ce9b52944bbecea450c51e9781dc`
- Tauri reference：`apps/bootstrap-installer/src-tauri/src/bootstrap.rs`、`events.rs`、`powershell.rs`、`src/routes/failure.tsx`
- 当前打包源（与 Runtime reference **不是同一仓库**）：`https://github.com/loudon84/copilot-hermes/tree/041b6985a00d01b54f830c1607dd370007a306bf`
- 模板：`需求PRD工程模板.md` v1.0。

**授权边界**：本 PRD 是目标状态 Engineering Contract，不是已完成的 GitHub 修改、构建签名、Win10 测试结果或 `.plan.md`。任何工程提交必须经 Plan Gate 与代码审查后实施。

