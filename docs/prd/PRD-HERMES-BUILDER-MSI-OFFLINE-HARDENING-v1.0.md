---
title: "Hermes Builder Windows MSI 严格离线安装与跨终端一致性工程改造 PRD"
subtitle: "MSI Offline Install / Deterministic Build / Runtime Diagnostics / Rollback Governance"
prd_id: "PRD-HERMES-BUILDER-MSI-OFFLINE-V1.0"
version: "1.0"
status: "APPROVED_FOR_PLAN"
template_version: "需求PRD工程模板 v1.0"
product: "SMC Copilot Hermes Enterprise Runtime"
repository: "https://github.com/smc-copilot/hermes-builder"
branch: "master"
baseline_commit: "07db1c6f64a706034a2268d4da235b7ba070aa3b"
owner: "Hermes Builder / Windows Runtime Packaging"
reviewers: ["Architecture", "Windows Installer", "Hermes Runtime", "Security", "QA", "Desktop Integration"]
created_at: "2026-10-08"
updated_at: "2026-10-09"
target_release: "hermes-builder MSI Offline Hardening v1.0 (Hermes 0.21.0 core SKU)"
change_type: ["BUGFIX", "BROWNFIELD_CHANGE", "ARCHITECTURE_CHANGE", "GOVERNANCE"]
golden_consumer: "smc-copilot 桌面端本地 Hermes Runtime + Win10/Win11 独立终端 MSI 安装"
related_docs:
  - "需求PRD工程模板.md"
  - "docs/SMC_Copilot_Hermes_MSI_CustomAction_1603修复方案_PRD.md"
  - "docs/specs/2026-10-08-msi-offline-hardening-grill.md"
  - "用户提供 2026-10-08 hermes-install(2).log（失败样本）"
  - "https://github.com/smc-copilot/hermes-builder"
  - "https://github.com/loudon84/copilot-hermes"
supersedes: null
---

# Hermes Builder Windows MSI 严格离线安装与跨终端一致性工程改造 PRD

> 本文为 **工程实施契约（Engineering Contract）**，不表示代码已改动或测试已通过。本文采用《需求PRD工程模板.md》v1.0 的 **0—36 章**及 Req → Acceptance → Test → Evidence 闭环。`status=APPROVED_FOR_PLAN`（2026-10-09，§28.1 的 G-01…G-09 全部 PASS），允许生成正式 `.plan.md`，范围仅限 §4.4 与 §34.2 点名的 13 项 Phase 1 Required AC。发布门槛与发布 DoD 仍分别由 §25、§35 判定，与本状态无关。

# 0. PRD 使用原则

## 0.1 WHY / WHAT / BOUNDARY / STATE / INPUT / OUTPUT / SIDE EFFECT / FAILURE / ACCEPTANCE / EVIDENCE

- **WHY**：同名/同一 MSI 在部分 Windows 10 终端安装末段失败、回滚；现有客户端执行路径不满足严格离线要求，诊断证据不足。
- **WHAT**：可实施范围只有 §4.4 Phase 1：固定 SHA；构建期离线重建证明；8 个关键文件哈希；终端 `uv sync --offline --no-config` 加两处 `--version`；`%TEMP%` 两个日志。**终端不调用上游 `install.ps1`、不跑 node/npm、不 `git clone`。** 全量树摘要、8GiB、T0 字节快照、Commit Custom Action、终端 Node 安装、Chromium smoke 不是本版口径。
- **BOUNDARY**：仅修改 `hermes-builder` 的构建/安装/测试协议和必要的 MSI 引导，不改 Hermes 模型业务逻辑。
- **STATE**：`build-info.json`（发布侧）、`runtime-manifest.json`（打包侧）、`bundle-install.json`（客户端提交记录）、本机实际文件（观测）；具体优先级见 §7。
- **INPUT**：固定源码 SHA、Python/uv/npm 锁与离线缓存、构建配置、Windows MSI 参数及现有受管/用户数据。
- **OUTPUT**：可验证 MSI + SHA256 + 离线包内容摘要 + 诊断日志 + 执行证据。
- **SIDE EFFECT**：只允许明确列出的受管目录、用户级环境变量和独立诊断/恢复目录。
- **FAILURE**：不可将缺失 `hermes.exe`、部分 npm 安装失败或回滚失败写为 PASS。
- **ACCEPTANCE**：使用确定的退出码、文件检查、哈希、真实离线终端安装及回滚注入作 Oracle。
- **EVIDENCE**：逐项输出与仓库 SHA 绑定的 JSON 结果、原始日志、完整性摘要；不能以“CI 绿色”代替。

## 0.2 Normative Keywords

`MUST` 必须实现/测试/有证据；`MUST NOT` 违反即失败；`SHOULD` 默认执行，偏离需批准；`SHOULD NOT` 原则禁止；`MAY` 非发布阻断可选。本文所有 `MUST/MUST NOT` 归入对应 Requirement 并映射 §20—27 验收。

## 0.3 No-Inference Rule

如 Plan/Coding Agent 发现本文无法唯一确定：安装路径、网络边界、状态优先级、缓存摘要、身份、恢复备份、文件所有权、错误返回、验收 Oracle，则 **MUST 报 `SPEC_SEMANTIC_GAP`，MUST BLOCK 实施计划，不得自行推断**。

**本规则的作用域限定在 Phase 1 实施口径之内。** 显式标注为 `PHASE 2` / 「后续阶段草稿，非 normative」的章节（§9.2、§11 中标 `PHASE 2` 的行、§12.2、§12.3、§15、§16.2、§16.3，以及 §20 中非 Phase 1 Required 的 AC）**不参与**唯一性判定：它们与 §4.4 不一致是设计使然，**MUST NOT** 据此触发 `SPEC_SEMANTIC_GAP`。仅「优先级声明」不足以解除本规则——冲突文本必须带上述显式降级标注才算出域。

# 1. 文档元数据

- 元数据见 YAML Front Matter。
- **源码读取基线**：`smc-copilot/hermes-builder` 的 `master@07db1c6f64a706034a2268d4da235b7ba070aa3b`（2026-10-08 获取）；关联构建配置指向 Hermes 0.21.0，`source.ref=041b6985a00d01b54f830c1607dd370007a306bf`。注意：现有本地源码流程会 `git pull --ff-only`，故**配置 SHA 不保证当前构建一定使用该 SHA**。
- 当前 `installer/HermesEnterprise.Setup.wixproj` 为 `WixToolset.Sdk/5.0.2` + `WixToolset.Util.wixext 5.0.2`，而非 README/ARCHITECTURE 文案里的 WiX 4；实现必须以工程文件为准。
- 本文为待实施方案，所有验收状态默认为 `NOT_RUN`（与 Release Gate 的 `BLOCKED` 对应）。

# 2. 一句话目标

让 **Windows 10/11 上使用 SMC Copilot Hermes 的终端用户与部署系统**，在 **x64、交互式 per-user 身份、已取得完整 MSI、无需互联网访问** 的前置条件下，通过 **同一构建标识的 MSI** 完成安装。

**Phase 1 的完成定义**是 §4.4：MSI 自带完整 `hermes-agent` 源码树与全部离线缓存；构建机已证明该包可在无网环境下重建出可运行的 CLI；终端安装只做「校验包完整性 → 在真实 per-user 路径上用随包 uv 离线重建 venv → 两处 `hermes.exe --version` 通过」，期间**不执行任何第三方安装脚本、不联网、不改动用户已有文件**。本文不写 `COMMITTED`，不做全量树摘要，不做 T0 字节快照，终端不安装 Node / Browser Use / CUA / Chromium。

# 3. 背景与问题定义

## 3.1 Current State（源码/日志事实）

1. WiX `Package.wxs` 为 `Scope="perUser"`，目标 `%LOCALAPPDATA%\hermes`；`PreflightHermes`、`InitializeHermes` 为 deferred `WixQuietExec`，失败可触发 MSI `1603` 回滚。
2. `build/Prepare-OfflineDependencies.ps1` 在构建机在线 `uv sync --locked` 填充缓存、删除 venv、再 `uv sync --offline --locked` 校验 `venv\Scripts\hermes.exe`，**随后再次删除 venv**；安装机需要在最终路径重建。
3. 构建机还在线填充 npm 缓存与 Chromium；客户端 `Initialize-Hermes.ps1` 设 `npm_config_offline=true`，仍调用上游 `scripts/install.ps1 -Stage node-deps`，该 Stage 会调用 Browser Use CLI 和 CUA Driver 的独立安装逻辑。
4. `build/Prepare-Source.ps1` 在本地源码存在时执行 `git pull --ff-only`，不强制输出与 `source.ref` 相等；构建产物名称可相同而 SHA 不同。
5. `build/Generate-Manifest.ps1` 当前只对部分关键文件求 SHA256，没有完整离线缓存树摘要。`Install-EnterpriseSkills.ps1` 使用 `robocopy /E` 合并，存在同路径用户内容被覆盖的潜在风险。
6. 用户提供的 2026-10-08 失败日志显示：`Preflight OK`、uv 日志 `Resolved 255 packages` / `Building hermes-agent`、Node 部分子任务失败但 Stage 返回 `ok:true`，最后报 `Hermes executable missing after offline sync: ...\venv\Scripts\hermes.exe`，`InitializeHermes` 返回 1603 并回滚。**直接故障点确定；缺失入口的底层原因未确定**。
7. 成功机器截图有 `hermes.exe` / `hermes-acp.exe` / `hermes-agent.exe`；截图时间戳不能证明是本次 MSI 新生成，需检查 `state\bundle-install.json`、构建 SHA、两机环境和实际执行路径。

## 3.2 可证伪问题陈述

- **P-001**：`uv sync` 与最终 CLI 检查之间存在 Node 执行窗口，未在 uv 后立刻记录 CLI 是否存在，因此无法判断“未生成”还是“后续丢失”。
- **P-002**：当前 `node-deps` 把部分 npm/browser/cua 失败视为非致命，`stage ok=true` 不足以证明 Core 组件齐备。**更严重的是调用它本身**——上游 `install.ps1` 的 `Install-Repository` 会把 MSI 释放的源码树改名为 `hermes-agent.broken-*` 并尝试 `git clone`（payload 无可用 `.git`，该分支必然触发），这既破坏安装又违反离线约束。开发机残留的 `hermes-agent.broken-20260922-223058` 是直接物证。
- **P-006**：终端 `uv sync` 既无 `--no-config` 也不屏蔽继承的 `UV_*`。`UV_NO_INSTALL_PROJECT` / `UV_NO_SYNC` / 用户级 `uv.toml` 会让 uv 跳过「安装项目本身」这一步，而 `hermes.exe` 的 console script entry point 正由该步生成——这精确对应失败样本中「`Resolved 255 packages`、`Building hermes-agent`，随后 `venv\Scripts\hermes.exe` 不存在」的现象，且可在构建机上注入复现。
- **P-003**：客户端调用的上游脚本可能发起互联网请求，违反 Core MSI 严格离线目标。
- **P-004**：构建过程未强制锁定本地源码提交，无法从文件名或版本名证明二进制一致性。
- **P-005**：MSI 失败后被自动回滚，诊断文件若只写在安装根目录会被移除，恢复/日志所有权与回滚覆盖范围不清晰。

## 3.3 Impact

业务：部分终端不能完成 Hermes 安装。工程：跨 Windows 机器差异不可定位。安全：远程安装脚本与可选组件隐式下载。运维：终端重试成本高。AI Coding：缺少可机器判定的需求/测试/证据使修复不可复现。

# 4. Scope

## 4.1 In Scope

| Scope | 具体内容 | Requirement |
|---|---|---|
| SCOPE-001 | 固定 source SHA、产物身份与构建来源 | REQ-SRC-001 |
| SCOPE-002 | uv 缓存与目标环境重建一致性、即时 CLI 验证 | REQ-PY-001 |
| SCOPE-003 | Phase 1：终端不调用上游 `install.ps1`、不跑 node/npm。npm 缓存自足性由构建期证明 | REQ-NODE-001（PHASE 2）、REQ-BUILD-001 |
| SCOPE-011 | 构建期离线重建证明与 Build Gate | REQ-BUILD-001 |
| SCOPE-004 | 环境变量/命令/安装上下文隔离 | REQ-ENV-001 |
| SCOPE-005 | 完整离线内容树摘要和版本化 schema | REQ-BUNDLE-001 |
| SCOPE-006 | 用户内容所有权、迁移、冲突与漂移 | REQ-OWN-001 |
| SCOPE-007 | MSI 失败事务、回滚和恢复保留 | REQ-TXN-001 |
| SCOPE-008 | 安装日志、错误分类、Support Bundle | REQ-OBS-001 |
| SCOPE-009 | 安装期无外网请求、权限与供应链控制 | REQ-SEC-001 |
| SCOPE-010 | Windows 安装矩阵、真实 Consumer、Release Gate | REQ-CI-001 |

## 4.2 Out of Scope

- `NON-GOAL-001`：本版本 MUST NOT 修改 `copilot-hermes` Agent 内部业务逻辑、LLM Provider 或模型配置。
- `NON-GOAL-002`：MUST NOT 将 Core per-user MSI 改为 SYSTEM/per-machine 安装；opsi/SYSTEM 部署另设 SKU 与 PRD。
- `NON-GOAL-003`：MUST NOT 在 Core MSI 初始化时下载 Browser Use CLI、CUA Driver、第三方模型或外部 SDK。
- `NON-GOAL-004`：MUST NOT 将失败视为成功、禁用 MSI 回滚或关闭 `InitializeHermes Return=check`。
- `NON-GOAL-005`：不对已完成安装后的模型 API、Skills 在线业务调用承诺无网络。

## 4.3 Architecture Boundary

| Domain | Owner | Input | Output | 不负责 |
|---|---|---|---|---|
| 需求 | 本 PRD | 日志/源码/用户目标 | Requirements/AC | 运行时模型行为 |
| Spec | Builder 构建规则 | SHA/锁/配置 | bundle manifest | 自行修改 upstream |
| Plan | 经批准的 `.plan.md` | 本 PRD | 代码任务 | 补全缺失语义 |
| Execution | build、scripts、WiX | 包与客户端状态 | MSI/Receipt | 非授权用户文件 |
| Governance | QA/Security/Release | Tests/Evidence | PASS/FAIL | 用手工口头放行 |

## 4.4 Phase 1 已拍板契约

来源：`docs/specs/2026-10-08-msi-offline-hardening-grill.md`（2026-10-08 grilling）及第二轮 grilling（2026-10-08）。本节是第一版可实施范围的权威口径。后文 REQ/AC 与本节冲突时，以本节为准，且冲突文本必须已按 §0.3 显式降级为 `PHASE 2`。本文已于 2026-10-09 按 §28.1 完成准入评审并标为 `APPROVED_FOR_PLAN`。

Phase 1 **MUST** 同时满足：

1. **固定源码 SHA。** Release 构建使用的 Hermes 源码 commit 等于 `build-config.json` 的 `source.ref`（当前锁定 `041b6985a00d01b54f830c1607dd370007a306bf`）。HEAD 不等或工作树不干净则构建失败，错误码 `SOURCE_REF_MISMATCH` 或 `SOURCE_DIRTY`。
2. **终端绝不调用上游 `scripts/install.ps1`。** Phase 1 的 Endpoint 初始化 **MUST NOT** 以任何 `-Stage` 调用 `<HermesRoot>\hermes-agent\scripts\install.ps1`，**MUST NOT** 运行 `npm` / `npx` / `node`，**MUST NOT** 调用 `uv tool install browser-use` 或 CUA 安装脚本。Node、Browser Use、CUA、Chromium、TUI 都不是 Phase 1 的交付物，它们缺失不是失败条件。

   理由不是「测不了」，而是**该脚本本身不安全**：上游 `install.ps1` 的 `Install-Repository` 会把它判定为「非法 git 仓库」的源码树改名为 `hermes-agent.broken-*` 并尝试 `git clone`。MSI payload 里的 `hermes-agent` 恰好没有可用的 `.git`（`build/Prepare-Source.ps1` 的 `Copy-Tree` 排除了它），因此该分支在终端必然触发，会掏空已安装的源码树。本仓库作者已在 `scripts/Initialize-Hermes.ps1` 的注释中记录过这一机理，开发机上也留有 `hermes-agent.broken-20260922-223058` 的实物残留。一个「严格离线安全安装」的 MSI **不能**在终端执行会改名源码树并发起 `git clone` 的第三方脚本。

   Node 的离线可行性改为**构建期证明**，见第 14 条。终端 Node 安装整体顺延 PHASE 2，届时必须用随包 `npm.cmd` 直接执行、不得经由上游 `install.ps1`。
3. **源码树缺失即失败，且不依赖 MSI 修复。** `%LOCALAPPDATA%\hermes\hermes-agent\pyproject.toml` 不存在时，初始化 **MUST** 以 `HERMES_SOURCE_TREE_MISSING` 失败。**MUST NOT** 从 `hermes-agent.broken-*` 恢复，**MUST NOT** 删除这些备份，**MUST NOT** 执行 `git clone` 或上游 `Install-Repository`。现有 `Initialize-Hermes.ps1` 的 `Restore-HermesAgentFromBrokenBackup` 函数及其调用 **MUST** 整体删除。

   失败时 **MUST** 向 `%TEMP%\hermes-msi-initialize.log` 写出确定的人工处置指令：卸载后重新安装同一 MSI；`hermes-agent.broken-*` 由用户自行保留或删除，安装器不碰。**Phase 1 MUST NOT 把「MSI 修复会把文件写回原路径」当作失败后的恢复路径**——那是未经观测的 Windows Installer 行为，不得作为设计依赖。既然第 2 条已禁止调用上游脚本，终端也不再会产生新的 `.broken-*`。
4. **禁止 relocatable venv。** `uv sync` 之后若 `hermes-agent\venv\pyvenv.cfg` 含 `relocatable=true`，**MUST** 以 `VENV_RELOCATABLE` 失败。**MUST NOT** 删除 `bin\hermes.exe` 并改写 `bin\hermes.cmd` 当作成功。
5. **两处 CLI 都要可运行。** `uv sync` 退出码为 0 之后、写成功标记之前，依次执行：
   - `<HermesRoot>\hermes-agent\venv\Scripts\hermes.exe --version`
   - 将该 exe 复制到 `<HermesRoot>\bin\hermes.exe` 之后，再执行 `<HermesRoot>\bin\hermes.exe --version`
   
   两次进程退出码都必须为 0。判定版本时只读 stdout 第一行，它必须匹配 `^Hermes Agent v` + 锁定版本 + ` \(`。只存在 `bin\hermes.cmd`、或只存在 `venv\Scripts\hermes.exe`，都 **MUST** 失败。桌面 `smc-copilot` 探针路径是 `%LOCALAPPDATA%\hermes\bin\hermes.exe`。

   **已实测（2026-10-08，开发机 `%LOCALAPPDATA%\hermes` 现网安装）**：两条命令退出码都是 `0`，stdout 第一行都是 `Hermes Agent v0.21.0 (2026.8.31)`。括号内日期不参与比较，后续行（Install directory、Install method、Python）不参与比较。该实测同时确认 `bin\hermes.exe` 可以是 `venv\Scripts\hermes.exe` 的直接副本：当前 venv **非** relocatable，其 console script 内嵌绝对路径 shebang `#!<HermesRoot>\hermes-agent\venv\Scripts\python.exe`，副本放在 `bin\` 下仍能解析到同一个解释器。第 4 条禁止 relocatable 的前提由此成立——relocatable venv 的 shebang 是相对的 `#!python.exe`，副本放进 `bin\` 会失效，这也是现有代码在该分支改写 `.cmd` 的原因。
6. **失败码。** 复制前 `venv\Scripts\hermes.exe` 不存在：`HERMES_CLI_MISSING_POST_SYNC`。文件存在但任一 `--version` 退出码非 0 或第一行不匹配：`HERMES_CLI_VERIFY_FAILED`。`bin\hermes.exe` 复制失败：`HERMES_CLI_VERIFY_FAILED`。
7. **MSI 组件形状保持不变。** `installer/Package.wxs` 使用 `<Files Include="$(var.PayloadDir)\**" />`，每个打包文件是独立组件，KeyPath 就是该文件。`InstallFiles` 在 `PreflightHermes`、`InitializeHermes` 之前执行。`hermes-agent.broken-*` 不是组件路径，MSI **MUST NOT** 删除它，也 **MUST NOT** 把备份改回 `hermes-agent`。Phase 1 不改事务形状、不加 Custom Action。

   本条**不对 MSI 修复行为作任何断言**。第 3 条的失败策略已改为「确定性失败 + 人工重装指令」，不依赖「KeyPath 缺失时安装或修复会把文件写回原路径」这一未观测行为，因此该行为不再是 Phase 1 的设计依赖，也不需要为它取证。
8. **Phase 1 完整性。** `uv sync` 之前只核对 `runtime-manifest.json` 里这 **8** 个路径的 SHA256：`bin\uv.exe`、`bin\rg.exe`、`bin\ffmpeg.exe`、`bin\ffprobe.exe`、`node\node.exe`、`hermes-agent\pyproject.toml`、`hermes-agent\uv.lock`、`offline\bundle-settings.json`。任一缺失或哈希不等则 `BUNDLE_INTEGRITY_FAILED`，且不得启动 `uv`。全量文件树摘要不在 Phase 1。

   清单与现有 `build/Generate-Manifest.ps1` 的 `$keyFiles` 一致。`node\npm.cmd` **不**进本清单——第 2 条已禁止终端运行 npm，它在 Phase 1 不是任何 Oracle 的执行体；`node\node.exe` 保留，因为现有 `Preflight-HermesInstall.ps1` 已把它当作 payload 完整性信号。

   这 8 个路径 **MUST** 全部出现在 `runtime-manifest.json` 的 `hashes` 中。构建时任一路径缺失 **MUST** 使构建失败（`BUILD_PROVENANCE_MISSING`），**MUST NOT** 静默跳过——否则 Endpoint 侧「任一缺失即失败」无法成立（见 §34.1 对 `build/Generate-Manifest.ps1` 的改动要求）。
9. **Phase 1 不做 T0 字节快照。** 不复制受管目录，不要求 8GiB 空闲。磁盘门槛沿用 `Preflight-HermesInstall.ps1` 的默认值 `4GB`（4294967296 字节）。低于该值返回 `DISK_SPACE_INSUFFICIENT`。`8589934592` 不是 Phase 1 门槛。
10. **网络 Oracle。** 只统计 `InitializeHermes` 拉起的进程：`powershell.exe`、`uv.exe`、`python.exe`、`hermes.exe`。这些进程的连接尝试计数必须为 0，否则 `OFFLINE_EGRESS_DETECTED`。`msiexec`、CRL、OCSP、SmartScreen 不计入。`node.exe` 与 `npm.cmd` 不在 Phase 1 的统计范围内，因为第 2 条已禁止终端运行它们。

    第 2 条生效后，本 Oracle 与终端执行图不再有张力：Phase 1 的终端执行图只有 `powershell.exe -> uv.exe -> python.exe` 与两次 `hermes.exe --version`，其中 `uv sync` 已带 `--offline`，不存在任何主动联网代码路径。取证仍留在 PHASE 2（REQ-SEC-001），因为它需要网络观测器；但 Phase 1 通过「终端执行图里不存在联网命令」这一**静态事实**满足，由 `tests/validate_project.py` 断言 `Initialize-Hermes.ps1` 不含 `install.ps1`、`npm`、`npx`、`node`、`git clone`、`Invoke-RestMethod`、`Invoke-WebRequest` 等调用（并入 A-ENV-001 的 Evidence）。
11. **Phase 1 不写 `COMMITTED`。** 不新增 Commit Custom Action，不把 `bundle-install.json` 的 `status` 写成 `COMMITTED`。安装成功由两处 `--version` 通过与 `msiexec` 退出码 0 共同表示。诊断日志不是提交回执。
12. **诊断只写 `%TEMP%`。** 预检日志是 `%TEMP%\hermes-msi-preflight.log`，初始化日志是 `%TEMP%\hermes-msi-initialize.log`。不创建 `%LOCALAPPDATA%\SMC\HermesInstaller\diagnostics`，不新增 `Collect-HermesInstallDiagnostics.ps1`。
13. **`uv` 子进程环境隔离。** `uv sync` **MUST** 带 `--no-config`，并在显式 allowlist 环境下启动：只保留 `UV_CACHE_DIR`、`UV_PROJECT_ENVIRONMENT`、`UV_PYTHON_INSTALL_DIR`、`HERMES_HOME`、`NO_COLOR`，以及 OS 必需项（`SystemRoot`、`TEMP`、`TMP`、`USERPROFILE`、`LOCALAPPDATA`、`APPDATA`、`PATH`、`PATHEXT`、`COMSPEC`、`NUMBER_OF_PROCESSORS`、`PROCESSOR_ARCHITECTURE`）。其余继承的 `UV_*` 与 `VIRTUAL_ENV` **MUST** 在子进程中清除，特别是 `UV_NO_INSTALL_PROJECT`、`UV_NO_INSTALL_WORKSPACE`、`UV_NO_INSTALL_LOCAL`、`UV_NO_SYNC`、`UV_CONFIG_FILE`、`UV_INDEX_URL`、`UV_DEFAULT_INDEX`、`UV_OFFLINE`、`UV_PYTHON`、`UV_SYSTEM_PYTHON`。

    **这是 §3.2 `P-001` 的首要可检验机理。** 失败样本的日志是 `Resolved 255 packages` / `Building hermes-agent` 之后 `venv\Scripts\hermes.exe` 不存在——`hermes-agent` 自身是本地项目，它的 console script entry point 由「安装项目本身」这一步生成。任何让 uv 跳过项目安装的继承变量或用户级 `uv.toml`，都会产生「`uv sync` 退出码 0 但没有 CLI」这一**完全吻合**的现象。现有 `scripts/Initialize-Hermes.ps1` 既没有 `--no-config`，也没有清理任何继承的 `UV_*`，对该机理毫无防御。本条由 `A-ENV-001` 在构建机上用注入测试取证，不需要终端。
14. **离线可行性在构建期证明。** `build/Prepare-OfflineDependencies.ps1` 已经在构建机上完整执行过一次「与终端等价的离线安装」，但 PRD 此前未把它写成契约。Phase 1 **MUST** 把下列既有断言固化为 Build Gate，任一不成立即构建失败：
    - 清空 venv 后执行 `uv sync --offline --locked`（不带网络），必须产出 `venv\Scripts\hermes.exe`，且 `hermes.exe --version` 退出码为 0。
    - 离线 `node-deps` 必须产出 `node_modules`（证明 npm 缓存自足）。该产物随后被删除，**不**随 MSI 分发，也**不**在终端重建（第 2 条）。
    - Playwright Chromium 必须已落在 `payload\playwright`，否则构建失败（沿用现有行为，见 REQ-BUILD-001）。

    Build Gate 的意义：**「这个包能不能离线装成」在构建机上就有确定答案和 Evidence，不必等终端。** 终端侧的 Phase 1 只需证明「同一个包在真实 per-user 路径上重建后两处 CLI 可运行」。

Phase 1 不把 `COMMITTED` 当作成功。桌面 Consumer 仍以 `bin\hermes.exe --version` 为运行时探针。

## 4.5 Phase 1 缺口确认结果

全部缺口已闭合，**没有 `NOT_RUN` 的批准前置项**。原 `VERIFY-01` 已实测闭合，原 `VERIFY-02` 已由 §4.4 第 3 条、第 7 条的口径变更**设计消除**。Phase 1 计划只允许实现 §4.4。后文若仍出现全量树摘要、8GiB、T0 字节快照、Commit Custom Action、Chromium smoke、终端 Node 安装，或把 `msiexec` 计入零网络，那些句子描述的是后续阶段草稿，已按 §0.3 的作用域条款降级为非 normative 附录，**不得**当作 Phase 1 的实施口径。

| ID | 确认结果 | 依据 |
|---|---|---|
| GAP-COMMIT | 已闭合。Phase 1 不写 `COMMITTED`，也不新增 Commit Custom Action。成功只看 §4.4 的两处 `--version` 与 `msiexec` 退出码 0 | §4.4 第 11 条 |
| GAP-HASH | 已闭合。Phase 1 只核 §4.4 第 8 条的 8 个关键文件，与现有 `$keyFiles` 一致。构建侧必须在任一路径缺失时失败，不得静默跳过。全量树摘要不在 Phase 1 | `build/Generate-Manifest.ps1` 的 `$keyFiles` |
| GAP-T0 | 已闭合。Phase 1 不做受管目录字节快照；最低空闲空间为 4GB（4294967296）。8GiB 不进入 Phase 1 | `scripts/Preflight-HermesInstall.ps1` 默认 `4GB` |
| GAP-NET | 已闭合。统计范围是 InitializeHermes 拉起的 powershell/uv/python/hermes。终端不跑 node/npm 后张力消失；Phase 1 用「执行图中不存在联网命令」的静态断言满足，动态取证留 PHASE 2 | §4.4 第 2 条、第 10 条 |
| GAP-NODE | 已闭合。**终端不跑 Node**，恢复 round-1 grilling 的原始决定。上游 `install.ps1` 会把源码树改名为 `.broken-*` 并 `git clone`，不得在终端执行。npm 缓存自足性改由第 14 条的 Build Gate 证明 | §4.4 第 2 条、第 14 条；`Initialize-Hermes.ps1` 注释；开发机 `hermes-agent.broken-20260922-223058` |
| GAP-NODE-ORACLE | 已闭合（实测后作废）。2026-10-08 在开发机实测 `npm.cmd ls --offline --depth=0` 退出码为 `0`；但终端已不跑 Node，该 Oracle 退出 Phase 1 口径 | 开发机 `%LOCALAPPDATA%\hermes\hermes-agent` 实测 |
| GAP-CHROMIUM | 已闭合。终端不安装、不检查 Chromium；缺失不是失败。Chromium 沿用现有行为随 payload 分发，第 14 条的 Build Gate 把它从「顺手做」升格为「缺失即构建失败」，不改变打包口径 | §4.4 第 2 条、第 14 条；REQ-BUILD-001 |
| GAP-OWN | 已闭合。§15 已区分两种情况：内容被改是 `MANAGED_CONTENT_DRIFT`（A-OWN-002）；同内容但 owner 不明是 `OWNERSHIP_UNKNOWN`。M-09 必须使用后者，不得再引用 A-OWN-002 | §15、M-09 |
| GAP-REPAIR | 已闭合（设计消除）。失败策略改为「确定性失败 + 人工重装指令」，不再依赖 MSI 修复把文件写回原路径，因此无需为该行为取证 | §4.4 第 3 条、第 7 条 |
| GAP-VER-MATCH | 已闭合。只比较 stdout 第一行前缀，不比较整段输出，不比较括号内日期。2026-10-08 实测两处 `--version` 退出码均为 `0`，第一行均为 `Hermes Agent v0.21.0 (2026.8.31)` | 开发机 `bin\hermes.exe` 与 `venv\Scripts\hermes.exe` |
| GAP-UV-ENV（新开并闭合） | 已闭合。`uv sync` 必须带 `--no-config` 并在 allowlist 环境下运行；这是「exit 0 但无 CLI」的首要机理，由 A-ENV-001 在构建机注入取证 | §4.4 第 13 条；`Initialize-Hermes.ps1` 现无任何防御 |

# 5. Terminology / Domain Model

- **Core SKU**：仅供本地 Hermes Agent Runtime 的 per-user MSI，不包含桌面 UI 和外部工具在线安装。
- **Build Host**：允许访问受控网络、生成离线包的 Windows 构建机。
- **Endpoint**：安装 MSI 的 Windows 10/11 用户终端。
- **Offline Payload**：打包进 MSI 的 Python、uv、Node、npm 缓存、Hermes 源码及所需资产。
- **Core Dependency（Phase 1）**：不具备即必须阻断安装的是固定源码树、`venv\Scripts\hermes.exe` 与 `bin\hermes.exe`。Node、browser、TUI 不是 Phase 1 的 Core。
- **Core Dependency（后续阶段）**：Node 基础组件与 browser/TUI。Chromium 不是 Phase 1 检查项；要列入后续 Core 必须先改本 PRD 并写明离线 smoke 命令。
- **Optional Tool**：Browser Use CLI、CUA Driver 等不在核心安装成功判定内的组件。
- **Install Operation**：单次 MSI 运行的 `operation_id`（UUID v4），贯穿阶段和证据。
- **Staged**：依赖和受管文件已存在但尚未写成功 Receipt。
- **Verified**：已满足所有 Required CLI、文件、无网及完整性检查。
- **User-Owned**：预存用户数据、未在 ledger 证明由本安装器创建的文件/配置/Skills。
- **Managed**：本安装器创建并在 ledger 明确列出的资源；未登记的资源一律视为未知所有权。
- **Release Digest**：MSI 字节的 SHA256，发布证据的唯一身份；文件名不是身份。

# 6. System Context

## 6.1 Context Diagram

```text
Fixed Hermes Git SHA + build-config + locks
                |
                v
Windows Build Host (online) -- fetch/prepare/validate --> offline payload
                |                                         |
                +---- SHA / tree manifest / build-info ---+
                |
                v
WiX 5 MSI (per-user) -> Endpoint (network blocked)
                      |        |
                      |        +-- Phase 1: Preflight(8 hashes) -> uv sync(--no-config, allowlist)
                      |        |              -> venv hermes.exe --version -> bin\hermes.exe --version
                      |        +-- PHASE 2: Node / Browser Use / CUA（终端不执行；离线可行性已在 Build Host 证明）
                      |        +-- Generated managed files / User state preservation
                      v
              MSI result / receipt / support bundle
                      |
                      v
            QA Golden Consumer + Release Gate
```

## 6.2 Boundary

- Inside：本仓库 `build/`、`scripts/`、`installer/`、`tests/`、`.github/workflows`、构建产物与受管安装目录。
- Outside：远端 `copilot-hermes` 代码仓库内容、opsi/SYSTEM 安装、桌面前端与模型服务。
- External dependency：GitHub 源码/构建工具、PyPI、npm、Playwright **仅 Build Host 可访问**；Endpoint Core Install 为网络拒绝环境。
- Trusted input：经 SHA/签名校验的 MSI + 固定源码提交 + 锁文件；Untrusted input：预存 `%LOCALAPPDATA%\hermes` 内容、环境变量、缓存文件、外部安装参数。

# 7. Authoritative State / Source of Truth

| State | Phase | 分类 | Authority | Writer | Reader | 自动覆盖 |
|---|---|---|---|---|---|---|
| `build-config.json` 的 `source.ref`（40 位 SHA） | PHASE 1 | DESIRED_STATE | YES | 版本控制 | Build/CI | NO（必须代码审核） |
| `dist/build-info.json` + MSI SHA256 | PHASE 1 | RESOLVED_STATE | YES（发布身份） | Build | Release/QA | NO |
| MSI 内 `runtime-manifest.json`（schemaVersion 1，8 条哈希） | PHASE 1 | RESOLVED_STATE | YES（关键文件清单） | Build | Preflight/QA | NO |
| `dist/build-info.json` 的 `offlineProof` | PHASE 1 | EVIDENCE_STATE | YES（构建期离线重建证明） | Build | Release/QA | NO（每次构建重算） |
| Endpoint 文件/CLI/进程和网络观察 | PHASE 1 | OBSERVED_STATE | YES（实际状态） | OS/验收工具 | Preflight/Verify | 非文件状态 |
| `%TEMP%\hermes-msi-preflight.log`、`%TEMP%\hermes-msi-initialize.log` | PHASE 1 | EVIDENCE_STATE | YES（安装日志） | Preflight/Initializer | Support/CI | 每次安装覆盖 |
| 现有 `.env`、`config.yaml`、`SOUL.md`、用户 Skills | PHASE 1 | USER_OWNED | YES（用户文件原字节） | User | Installer 只读 | NO |
| ~~`%LOCALAPPDATA%\hermes\state\bundle-install.json` v2~~ | PHASE 2 | LAST_APPLIED_STATE | YES（提交后） | Initializer | Installer/desktop | 验证成功后允许原子替换 |
| ~~`%LOCALAPPDATA%\SMC\HermesInstaller\recovery\...`~~ | PHASE 2 | RUNTIME_STATE | YES（恢复基线） | Txn manager | Rollback/Support | 未确认成功前 NO |
| ~~`%LOCALAPPDATA%\SMC\HermesInstaller\diagnostics\...`~~ | PHASE 2 | EVIDENCE_STATE | YES（安装日志） | Logger | Support/CI | NO（每 operation 唯一） |

**优先级**：安装验收以实际 OBSERVED_STATE 为准。Manifest 与实际 Payload 不一致时 `BUNDLE_INTEGRITY_FAILED`，不得继续执行缓存安装。用户文件的本机字节优先于任何默认模板。

Phase 1 **没有**权威 Receipt：现有 `state\bundle-install.json`（schemaVersion 1）只被 `Initialize-Hermes.ps1` 用作「是否需要重新 `uv sync`」的提示，**MUST NOT** 被任何一方当作安装成功的证明（§4.4 第 11 条）。关于 `DRIFTED` 的 Receipt 比对规则属 PHASE 2。

# 8. State Machine

```text
构建期（Build Host，§4.4 第 14 条）：
SOURCE_PIN_VERIFIED -> CACHE_POPULATED -> OFFLINE_REBUILD_PROVEN -> MANIFEST_SEALED -> MSI_BUILT

终端（Endpoint）唯一合法转移：
NOT_STARTED -> INSTALL_FILES -> PREFLIGHT -> PAYLOAD_VERIFIED
 -> PYTHON_SYNC -> PYTHON_VERIFIED -> PHASE1_CLI_READY
       | 任一失败
       +--> FAILING（InitializeHermes 非 0，由现有 MSI 事务回滚 InstallFiles）
```

- 上图是本文唯一授权的状态机。`PHASE1_CLI_READY` 是 Phase 1 的终态。`EARLY_PREFLIGHT`、`OWNERSHIP_GUARD`、`NODE_DEPS`、`NODE_SMOKE_OK`、`FINAL_VERIFIED`、`COMMITTED` 都不是 Phase 1 状态；`NODE_DEPS` 与 `NODE_SMOKE_OK` 已随 §4.4 第 2 条整体移入 PHASE 2。
- **`INSTALL_FILES` 在 `PREFLIGHT` 之前，这与现有 `installer/Package.wxs` 一致**：`SetPreflightHermes` 的序列位置是 `After="InstallFiles"`，`PreflightHermes`、`SetInitializeHermes`、`InitializeHermes` 依次排在其后。Phase 1 **MUST NOT** 把 Preflight 提前到 `InstallFiles` 之前——payload 尚未落盘时 §4.4 第 8 条的 8 个文件均不存在，会导致每次安装都误报 `BUNDLE_INTEGRITY_FAILED`。§4.4 第 8 条所说的「`uv sync` 之前」指的是 `InstallFiles` 之后、`uv` 启动之前这个窗口，不是文件落盘之前。
- `PHASE1_CLI_READY` 只表示 §4.4 的两处 `--version` 通过。Phase 1 **MUST NOT** 写入 `bundle-install.json` 的 `status=COMMITTED` 或 `FINAL_VERIFIED`，**MUST NOT** 新增 Commit Custom Action。安装成功对外只由这两次版本检查通过以及 `msiexec` 退出码 0 表示。
- 诊断写在 `%TEMP%` 的 preflight/initialize 日志。这些日志不是提交回执。
- 幂等重跑仍执行 §4.4 的检查。不得只凭旧 marker 跳过，也不得因为缺少 `COMMITTED` 而另写一张成功回执。

# 9. Data / Schema Contract

## 9.1 Schema Rule

Phase 1 继续使用现有 `runtime-manifest.json`（`schemaVersion` 1）和其中的 8 个文件哈希。不生成 `manifest.v2`，不生成 `receipt.v2`，不写 `payloadTreeDigest`。

> **§9.2 是后续阶段草稿，非 normative。** 下面的 `manifest.v2` / `receipt.v2` / `event.v1` / `evidence.v1` 字段表**不是**本版要落地的 schema，Phase 1 不实现其中任何字段。保留它只为给后续阶段留设计底稿。Plan / Coding Agent **MUST NOT** 据此生成任务，也 **MUST NOT** 因本节与 §4.4 不一致而触发 §0.3 的 `SPEC_SEMANTIC_GAP`——本节已显式声明不参与 Phase 1 语义判定。`status` 枚举中的 `COMMITTED` / `FINAL_VERIFIED` 在 Phase 1 不得被写入（§4.4 第 11 条）。

## 9.2 Field Semantic Table

| Schema | Field | Type | Required | Default | Authority | Meaning |
|---|---|---|---:|---|---|---|
| manifest.v2 | `schemaVersion` | int enum `2` | YES | 无 | Build | 版本 |
| manifest.v2 | `sourceCommit` | string regex `^[a-f0-9]{40}$` | YES | 无 | Build | Hermes 源码 SHA |
| manifest.v2 | `builderCommit` | string regex `^[a-f0-9]{40}$` | YES | 无 | Build | Builder SHA |
| manifest.v2 | `payloadTreeDigest` | lower-hex SHA256 | YES | 无 | Build | §13 的受管文件摘要 |
| manifest.v2 | `managedFiles` | array of `{path,size,sha256}` | YES | `[]` | Build | 有序 payload 完整清单 |
| manifest.v2 | `runtime` | object `{pythonVersion,uvVersion,nodeVersion,extras}` | YES | 无 | Build | 构建工具与依赖身份 |
| manifest.v2 | `offlineContract` | enum `CORE_NO_NETWORK_V1` | YES | 无 | Build | 客户端严格离线协议 |
| receipt.v2 | `schemaVersion` | int enum `2` | YES | 无 | Initializer | 版本 |
| receipt.v2 | `operationId` | UUID string | YES | 无 | Initializer | 安装关联 ID |
| receipt.v2 | `sourceCommit` | 40-hex | YES | 无 | Initializer | 来源 SHA |
| receipt.v2 | `payloadTreeDigest` | 64-hex | YES | 无 | Initializer | 安装时验证的源摘要 |
| receipt.v2 | `status` | enum `FINAL_VERIFIED` / `COMMITTED` | YES | 无 | Initializer/Txn | 提交状态 |
| receipt.v2 | `managedLedgerDigest` | 64-hex | YES | 无 | Initializer | 受管文件 ledger 摘要 |
| receipt.v2 | `verifiedAtUtc` | UTC timestamp | YES | 无 | Initializer | 完成核验时间 |
| event.v1 | `operationId,stage,status,timestampUtc,sourceCommit,errorCode` | strings/enums | YES | 无 | Logger | 阶段事件 |
| event.v1 | `result` | object（仅白名单字段） | YES | `{}` | Logger | 非敏感统计 |
| evidence.v1 | `acceptanceId,requirementIds,testIds,command,exitCode,oracle,evidenceFiles,repoCommit,toolVersions,timestampUtc,status` | typed | YES | 无 | QA | 可执行验收证明 |

`status` 的 Schema 枚举仅规定持久 Receipt：失败中间状态 **MUST NOT** 写入成功 Receipt。诊断 `event.v1.status` 枚举为 `STARTED/PASS/FAIL/BLOCKED`，`stage` 枚举为 §19 定义阶段。Manifest `managedFiles` 必须记录所有构建归属的普通文件；目录本身不入摘要。

## 9.3 示例（仅表达契约，不代表已生成）

```json
{
  "schemaVersion": 2,
  "sourceCommit": "041b6985a00d01b54f830c1607dd370007a306bf",
  "builderCommit": "07db1c6f64a706034a2268d4da235b7ba070aa3b",
  "payloadTreeDigest": "<computed_sha256_hex>",
  "managedFiles": [],
  "runtime": {"pythonVersion":"3.11", "uvVersion":"<captured>", "nodeVersion":"<captured>", "extras":["messaging","mcp","web","google","voice","edge-tts","hindsight"]},
  "offlineContract": "CORE_NO_NETWORK_V1"
}
```

示例中尖括号是解释占位符，**不允许将示例 JSON 直接用于生产**；真实产物由 Build 计算所有字段；`managedFiles=[]` 只能在零文件测试 fixture 使用。

# 10. Requirement Unit

> 10 个 Required Requirement。每个遵循模板的 Goal / Normative / Inputs / Preconditions / SOT / State Transition / Allow / Deny / Ownership / Idempotency / Failure / Postconditions / Invariants / Error Codes / Acceptance / Evidence 完整单元。每项均具有机器判定 Oracle。

## REQ-SRC-001 — 固定源码与确定性 MSI 身份

### Goal
消除本地 `git pull` 导致“相同版本名不同源码”的不确定性。
### Normative Requirement
- MUST 在 release 构建中对本地 checkout 或 clone 输入校验 `HEAD == source.ref(40-hex)`；不等则阻断构建。
- MUST 在 release 模式检测工作树/子模块均 clean，记录 builder/source SHA、构建工具版本、MSI SHA256。
- MUST NOT 在 release 构建中自动 `pull`、`checkout main` 或以 mutable branch 代替 pinned SHA；开发模式可显式 `-DevelopmentMode`，但其产物标 `unreleasable` 并禁止通过 Gate。
### Inputs
`build-config.json.source.ref`；`src/hermes-agent` checkout；Builder HEAD；lock 文件。
### Preconditions
Git 可用，commit 存在，可读取 local checkout；构建配置 schema 通过。
### Authoritative State
SOT=`source.ref` + Builder HEAD；Observed=`git rev-parse HEAD`/工作区状态；Derived=`build-info.json`。
### State Transition
`UNRESOLVED -> SOURCE_PIN_VERIFIED -> BUILD_ALLOWED`；SHA 不等 -> `BUILD_BLOCKED`。
### Allowed Side Effects
ALLOW：Build Host `src/` 的 clone（仅缺失时）、`.work/`、`payload/`、`dist/`；CI 证据。
### Forbidden Side Effects
DENY：静默修改本地 checkout、tag/branch 写入、远端 push。
### Ownership Scope
FILE / GENERATED_ONLY：构建中间目录与 dist；开发者源码仓库 USER_OWNED。
### Idempotency
first run：同输入生成同源码内容清单；second run：不改变 checkout HEAD；若二进制时间戳不同可导致 MSI SHA 改变，发布必须记录实际 SHA，不声称字节可复现，除非另行验证。
### Failure Semantics
F-SRC-001：HEAD 不符 → `SOURCE_REF_MISMATCH`，build exit !=0，清理新建的临时产物，源 checkout 不变；retryable=YES（校正 checkout/config 后）。
### Postconditions
`sourceCommit` 与 pinned ref 相等；产物输出完整 SHA。
### Invariants
`INV-SRC-001`: Release 不能使用 floating HEAD；`INV-SRC-002`: Release identity = MSI byte SHA256。
### Error Codes
`SOURCE_REF_MISMATCH`, `SOURCE_DIRTY`, `BUILD_PROVENANCE_MISSING`。
### Acceptance
`A-SRC-001`、`A-SRC-002`。
### Evidence
`TEST-A-SRC-001/002`；构建 stdout、`build-info.json`、Git SHA、`*.msi.sha256`。

## REQ-PY-001 — Python 离线环境与 CLI 即时闭环校验

### Goal
在任何 Node 命令之前判定 Hermes CLI 已由 uv 生成，并且桌面探针路径上的 `bin\hermes.exe` 可运行。Phase 1 的权威步骤是 §4.4。
### Normative Requirement
- MUST 使用内置 Python 3.11、内置 uv、`UV_CACHE_DIR`、`UV_PROJECT_ENVIRONMENT=<HermesRoot>\hermes-agent\venv`，并执行 `uv sync --offline --locked --link-mode copy --no-config --python <bundled-python> --project <agent-dir> --directory <agent-dir>` 与 manifest 中固定 extras。`--no-config` 与 §4.4 第 13 条的环境 allowlist **MUST** 同时成立；现有实现两者皆无，是必须修复的缺陷。
- MUST 在 `uv sync` 之前确认 `<HermesRoot>\hermes-agent\pyproject.toml` 与 `uv.lock` 存在。缺失则 `HERMES_SOURCE_TREE_MISSING`，并向 `%TEMP%\hermes-msi-initialize.log` 写出「卸载后重装同一 MSI」的确定指令。MUST NOT 恢复或删除 `hermes-agent.broken-*`，MUST NOT 执行 `git clone` 或 `Install-Repository`，MUST NOT 依赖 MSI 修复作为恢复路径。现有 `Restore-HermesAgentFromBrokenBackup` 函数及其调用 MUST 删除。
- MUST 在 uv 退出码 0 后、任何 Node 命令之前检查 `pyvenv.cfg`。出现 `relocatable=true` 则 `VENV_RELOCATABLE`，不得改用 `.cmd`。
- MUST 按 §4.4 第 5 条依次验证 `venv\Scripts\hermes.exe --version` 与复制后的 `bin\hermes.exe --version`。两次退出码都为 0，且 stdout 第一行都匹配 `^Hermes Agent v` + 锁定版本 + ` \(`。当前锁定版本是 `0.21.0`。
- MUST 将 uv stderr/stdout/exit 与两次 `--version` 的 stdout/exit 写入独立 operation 日志，不能以仅 `Resolved N packages` 为安装成功。
- MUST NOT 自动切换到 sibling `.venv`；发现路径冲突应报错并给出可定位证据。
### Inputs
`runtime-manifest.json`、`offline/uv-cache`、`pyproject.toml`、`uv.lock`、内置 Python/uv、Windows account。
### Preconditions
`PAYLOAD_VERIFIED` 且目标处于已校验安装身份；磁盘/ACL 通过 Preflight。
### Authoritative State
SOT=manifest Python/extras + 目标 venv 实际文件；Observed=CLI/metadata/exit；Derived=Python verified event。
### State Transition
`PAYLOAD_VERIFIED -> PYTHON_SYNC -> PYTHON_VERIFIED -> PHASE1_CLI_READY`；失败进入 `FAILING`。Phase 1 **不能**启动 Node Stage。
### Allowed Side Effects
ALLOW：受管 `hermes-agent\venv`、operation 诊断、临时构建目录。
### Forbidden Side Effects
DENY：外网访问、系统 Python/全局 site-packages 修改、未知用户 venv 自动删除、Node 下载。
### Ownership Scope
GENERATED_ONLY / FILE（只操作经 ledger 或首次安装确认属受管的 venv）。
### Idempotency
同 manifest + 完整健康 CLI = 校验后跳过重同步；不存在或部分存在 = 在安全 staging 中重建并校验后原子替换受管 venv；未知所有权 = BLOCK。
### Failure Semantics
F-PY-001：uv exit !=0 → `UV_SYNC_FAILED`；F-PY-002：exit=0 且 `venv\Scripts\hermes.exe` 不存在 → `HERMES_CLI_MISSING_POST_SYNC`；F-PY-003：任一 `--version` 失败或 `bin\hermes.exe` 未复制成功 → `HERMES_CLI_VERIFY_FAILED`；F-PY-004：`pyproject.toml` 缺失 → `HERMES_SOURCE_TREE_MISSING`；F-PY-005：`relocatable=true` → `VENV_RELOCATABLE`。Phase 1 失败时不恢复 `.broken-*`。retryable=源码树与环境修复后 YES。
### Postconditions
`venv\Scripts\hermes.exe` 与 `bin\hermes.exe` 都以锁定版本运行；整个初始化期间 Node / npm / npx 与上游 `install.ps1` 的调用次数为 0（REQ-NODE-001）。
### Invariants
`INV-PY-001`: `PHASE1_CLI_READY` 前不得运行 node/npm；`INV-PY-002`: CLI 文件存在不能替代 `--version` 退出码 0。
### Error Codes
`UV_SYNC_FAILED`, `HERMES_CLI_MISSING_POST_SYNC`, `HERMES_CLI_VERIFY_FAILED`, `UV_ENV_CONFLICT`, `HERMES_SOURCE_TREE_MISSING`, `VENV_RELOCATABLE`。
### Acceptance
`A-PY-001`、`A-PY-002`、`A-PY-003`、`A-PY-004`、`A-PY-005`。
### Evidence
`TEST-A-PY-001` 至 `TEST-A-PY-005`；uv 详细日志、两次 `--version` 输出、阶段事件。

## REQ-BUILD-001 — 构建期离线重建证明（Build Gate）

### Goal
把「这个 MSI 能不能在无网环境装成」变成**构建机上的确定答案**，而不是终端上的开放问题。`build/Prepare-OfflineDependencies.ps1` 今天已经执行了等价流程，本 Requirement 把它固化为契约并要求产出 Evidence。
### Normative Requirement
- MUST 在填充 `offline\uv-cache` 之后，**删除 venv**，再以 `uv sync --offline --locked --no-config` 重建，并断言产出 `venv\Scripts\hermes.exe`、其 `--version` 退出码为 0。该步骤 MUST 在无网络可达性的前提下成立（`--offline` 强制），失败即构建失败。
- MUST 在该离线重建之后**删除 venv**，不把构建机路径绑定的 venv 打进 payload。理由是实测事实：非 relocatable venv 的 console script 内嵌绝对路径 shebang（`#!<build-path>\venv\Scripts\python.exe`），搬到终端后失效。
- MUST 在 `npm_config_offline=true` 下跑通一次 `node-deps` 并断言产出 `node_modules`，随后删除它（含所有 workspace junction）。该断言只证明 npm 缓存自足，**不**授权终端重建。
- MUST 断言 `payload\playwright` 下存在 `chrome.exe` 或 `headless_shell.exe`，否则构建失败。该断言沿用现有 `build/Prepare-OfflineDependencies.ps1` 的行为，**不改变** Chromium 的打包口径——它今天就在 payload 里，本 Requirement 只是把它从「顺手做」变成「缺失即构建失败」。
- MUST 记录 Build Gate 的每一步命令、退出码、工具版本与 UTC 时间，写入 `dist/build-info.json` 的 `offlineProof` 段。
- MUST NOT 以「构建机联网能装成」代替离线重建证明；联网填充缓存与离线重建验证 MUST 是两次独立执行。
### Inputs
固定 source SHA 的源码树、`uv.lock`、`build-config.json` 的 extras、随包 Python/uv/Node。
### Preconditions
`SOURCE_PIN_VERIFIED`；构建机可访问受控网络用于**填充缓存**阶段。
### Authoritative State
SOT=Build Gate 各步退出码；Derived=`build-info.json.offlineProof`。
### State Transition
`CACHE_POPULATED -> OFFLINE_REBUILD_PROVEN -> MANIFEST_SEALED`；任一断言失败 -> `BUILD_BLOCKED`。
### Allowed Side Effects
ALLOW：Build Host 的 `.work/`、`payload/`、`dist/`、构建期临时 venv 与 `node_modules`（都在打包前删除）。
### Forbidden Side Effects
DENY：把构建期 venv 或 `node_modules` 打进 payload；跳过离线重建直接打包；用上一次构建的证明冒充本次。
### Ownership Scope
GENERATED_ONLY（构建中间目录与 dist）。
### Idempotency
同一 source SHA + 同一 lock + 同一缓存，重复构建产生同样的 Build Gate 结论；MSI 字节 SHA 可因时间戳不同而变化，以实际记录为准。
### Failure Semantics
F-BUILD-001：离线重建未产出 `hermes.exe` 或 `--version` 非 0 -> `OFFLINE_REBUILD_FAILED`，构建 exit!=0，不产出 MSI。F-BUILD-002：离线 `node-deps` 未产出 `node_modules` -> `NPM_CACHE_INSUFFICIENT`。F-BUILD-003：Chromium 未落盘 -> `BROWSER_PAYLOAD_MISSING`。retryable=补齐缓存后 YES。
### Postconditions
MSI 内的缓存被证明足以在无网环境重建出可运行的 Hermes CLI。
### Invariants
`INV-BUILD-001`: 没有离线重建证明的 payload 不得打包；`INV-BUILD-002`: 构建期 venv 与 `node_modules` 不得出现在 payload 中。
### Error Codes
`OFFLINE_REBUILD_FAILED`, `NPM_CACHE_INSUFFICIENT`, `BROWSER_PAYLOAD_MISSING`。
### Acceptance
`A-BUILD-001`、`A-BUILD-002`。
### Evidence
`TEST-A-BUILD-001/002`；`dist/build-info.json` 的 `offlineProof`、构建 stdout、payload 文件清单。

## REQ-NODE-001 — 终端 Node 边界（Phase 1 为纯禁止类约束）

### Goal
Phase 1 的终端**完全不碰 Node**，也不执行任何第三方安装脚本。Node 运行时的离线安装整体顺延 PHASE 2。
### Phase 1 Normative Requirement
- **MUST NOT** 以任何 `-Stage` 调用 `<HermesRoot>\hermes-agent\scripts\install.ps1`。该脚本的 `Install-Repository` 会把 MSI 释放的源码树改名为 `hermes-agent.broken-*` 并尝试 `git clone`（payload 内无可用 `.git`，该分支必然触发），属于破坏性且联网的操作。
- **MUST NOT** 在终端运行 `node.exe` / `npm.cmd` / `npx.cmd`，**MUST NOT** 执行 `uv tool install browser-use` 或 CUA 安装脚本，**MUST NOT** 执行 `git clone`。
- **MUST NOT** 因 `node_modules`、Browser Use、CUA、Chromium、TUI 缺失而判定安装失败。
- npm 缓存与 Chromium 仍随 MSI 分发，其自足性由 REQ-BUILD-001 在构建期证明。
### Inputs
无（本 Requirement 在 Phase 1 不产生终端行为）。
### Preconditions
不适用。
### Authoritative State
Observed=`scripts/Initialize-Hermes.ps1` 的静态执行图（是否出现被禁命令）。
### State Transition
不引入状态。`NODE_DEPS` 与 `NODE_SMOKE_OK` 已移出 Phase 1 状态机（§8）。
### Allowed Side Effects
无。
### Forbidden Side Effects
DENY：调用上游 `install.ps1`、运行 node/npm/npx、`git clone`、改名或删除 `hermes-agent*` 目录。
### Ownership Scope
NONE。
### Idempotency
重复安装一律不产生 Node 相关副作用。
### Failure Semantics
本 Requirement 在 Phase 1 不产生运行时错误码。实现中若出现被禁调用，属实现不合格，由 A-ENV-001 的静态断言捕获。
### Postconditions
`Initialize-Hermes.ps1` 的执行图中被禁命令出现次数为 0。
### Invariants
`INV-NODE-001`: 终端执行图不含上游 `install.ps1`；`INV-NODE-002`: Chromium / Node 组件缺失不导致 Phase 1 失败。
### Error Codes
Phase 1 无。`NODE_SMOKE_FAILED`、`INVALID_STATE_TRANSITION` 保留给 PHASE 2。
### Acceptance
Phase 1 由 `A-ENV-001` 的静态断言覆盖。`A-NODE-001`、`A-NODE-002`、`A-NODE-003` 属 PHASE 2。
### Evidence
`A-ENV-001` 的静态扫描报告。

## REQ-ENV-001 — 环境/权限/路径隔离

### Goal
消除用户 `UV_*`、系统 Node/Python、PowerShell 和 Windows 安装身份差异对结果的隐性影响。
### Normative Requirement
- MUST 按 §4.4 第 13 条在 uv 子进程边界采用明确 allowlist 环境并传 `--no-config`，屏蔽会跳过项目安装、改变环境根、改变索引或发起联网的继承变量；`UV_NO_INSTALL_PROJECT`、`UV_NO_INSTALL_LOCAL`、`UV_NO_INSTALL_WORKSPACE`、`UV_NO_SYNC`、`UV_CONFIG_FILE`、`UV_INDEX_URL`、`UV_DEFAULT_INDEX`、`VIRTUAL_ENV` 等不得影响受管同步。**这是 Phase 1 Required，不可顺延**：它是「`uv sync` 退出码 0 但 `venv\Scripts\hermes.exe` 不存在」的首要可检验机理。现有 `Initialize-Hermes.ps1` 既无 `--no-config` 也无任何 `UV_*` 清理。
- MUST 用绝对路径调用随包 `uv.exe` 与内置 `python.exe`。Phase 1 不调用 `node.exe` / `npm.cmd` / `npx.cmd`（REQ-NODE-001）。
- MUST 保证 `scripts/Initialize-Hermes.ps1` 的静态执行图中不出现上游 `install.ps1`、`npm`、`npx`、`node`、`git clone`、`Invoke-RestMethod`、`Invoke-WebRequest`、`iwr`、`irm`。
- MUST 在 Preflight 对 SYSTEM 执行、非 x64、低于 Win10、非 PowerShell 5.1、目标路径不安全和空闲空间低于 `4294967296`（4GB）返回独立错误码。Phase 1 不做 T0 字节快照，不使用 `8589934592`。检查通过前不能做 `uv sync`。`InstallFiles` 仍早于初始化；Phase 1 不新增 InstallFiles 之前的全树 OwnershipGuard。
- MUST NOT 将 SYSTEM 账户转成 per-user 伪安装，MUST NOT 修改 Machine PATH/全局 Python/npm 配置。
### Inputs
当前 OS/UserSID、操作进程 env、安装根、bundle config。
### Preconditions
MSI 已验证，操作 ID 已建立，获取运行用户身份。
### Authoritative State
SOT=固定工具路径 + manifest / policy；Observed=有效环境快照（白名单脱敏）。
### State Transition
`NOT_STARTED -> INSTALL_FILES -> PREFLIGHT`（与 §8、§14.2、`Package.wxs` 一致）。无效身份、非 x64、低于 Win10 或空闲空间低于 4GB 时，在 `uv sync` 前 `FAILING`。不新增 InstallFiles 之前的 OwnershipGuard。
### Allowed Side Effects
ALLOW：临时子进程 env；成功后由用户级受管 PATH/HERMES_HOME 策略写入。
### Forbidden Side Effects
DENY：Machine env、SYSTEM 身份安装、修改用户自有的重复 PATH 条目。
### Ownership Scope
ENTRY（仅准确匹配由安装器添加的 User env entry），RESOURCE（子进程环境）。
### Idempotency
相同 User PATH 条目只插入一次；前后不同的用户条目原值保持。
### Failure Semantics
F-ENV-001：权限或路径不合法 -> `INSTALL_CONTEXT_UNSUPPORTED`；F-ENV-002：低磁盘 -> `DISK_SPACE_INSUFFICIENT`；rollback=此前用户级写入恢复原值；retryable=环境修复后 YES。
### Postconditions
所有工具路径可定位；无继承 uv 行为覆盖；User PATH/HERMES_HOME 精准记录。
### Invariants
`INV-ENV-001`: MSI per-user = interactive user account；`INV-ENV-002`: 任何未授权全局环境写入数=0；`INV-ENV-003`: 受管 `uv sync` 的行为不受任何继承 `UV_*` 变量或用户级 `uv.toml` 影响。
### Error Codes
`INSTALL_CONTEXT_UNSUPPORTED`, `DISK_SPACE_INSUFFICIENT`, `UV_ENV_CONFLICT`, `PATH_UNSAFE`。
### Acceptance
**Phase 1 Required：`A-ENV-001`**（uv 环境隔离注入测试 + 终端执行图静态断言）。`A-ENV-002`（SYSTEM / 低磁盘 / 非 Win10 的 Preflight 拒绝）属 PHASE 2——现有 `Preflight-HermesInstall.ps1` 已实现该行为，本版不改。
### Evidence
`TEST-A-ENV-001`；注入环境快照、uv 命令行、`venv\Scripts\hermes.exe` 存在性、`Initialize-Hermes.ps1` 静态扫描报告。

## REQ-BUNDLE-001 — 离线资产树完整性与版本化 Manifest

### Goal
防止“构建机离线校验通过、MSI 包却缺失文件或目标端缓存不全”。
### Normative Requirement
- MUST 让 `runtime-manifest.json` 继续记录 §4.4 第 8 条的 8 个路径及其 SHA256。不生成全量 `payloadTreeDigest`，不把 schema 升到 v2。
- MUST 在构建期对这 8 个路径逐一求 SHA256；任一路径在 payload 中缺失时 MUST 使构建失败并返回 `BUILD_PROVENANCE_MISSING`，MUST NOT 静默跳过该条目。
- Endpoint 在 `uv sync` 之前核对这 8 个文件。任一缺失、manifest 中无该条目、或哈希不等则 `BUNDLE_INTEGRITY_FAILED`，且不得启动 `uv`。
- 不在这 8 个路径里的缓存字节变化，不是 Phase 1 的失败条件。
- MUST NOT 把「只核这 8 个文件」再写成失败。这也是 Phase 1 的完整性 Oracle。
- 实现归属见 §34.1：构建侧为 `build/Generate-Manifest.ps1`，Endpoint 侧为 `scripts/Preflight-HermesInstall.ps1`。
### Inputs
payload、最终 MSI、runtime-manifest、release SHA、安装根。
### Preconditions
源码/工具已固定；构建目录稳定；不含用户自有数据。
### Authoritative State
SOT=manifest v2 + Release SHA；Observed=解包实际 tree；Derived=验证结果。
### State Transition
`INSTALL_FILES -> PREFLIGHT -> PAYLOAD_VERIFIED`；不匹配 -> `FAILING`，无 Python/Node mutation，MSI 自有的 InstallFiles 写入必须回滚。
### Allowed Side Effects
ALLOW：Build Host 新生成 manifest、验证结果；Endpoint 日志，临时校验缓存。
### Forbidden Side Effects
DENY：修改 manifest 来匹配被篡改的文件；Hash 排除核心缓存；以旧 marker 代替验证。
### Ownership Scope
FILE / GENERATED_ONLY（payload）；用户文件不纳入构建 payload digest。
### Idempotency
同一文件字节与规范化路径输入产生相同摘要；重复校验 0 mutation（不含诊断文件）。
### Failure Semantics
F-BUNDLE-001：文件缺失/篡改/重复路径 -> `BUNDLE_INTEGRITY_FAILED`，rollback=无业务变动（如果 MSI 已释放受管文件，交 MSI rollback）；retryable=换包重装 YES。
### Postconditions
Manifest 与 MSI 实际分发字节一致，所有核心缓存存在且可验证。
### Invariants
`INV-BUNDLE-001`: 任何 Core payload file tamper 导致 FAIL；`INV-BUNDLE-002`: Hash 排除清单固定不可动态扩张。
### Error Codes
`BUNDLE_INTEGRITY_FAILED`, `BUNDLE_SCHEMA_UNSUPPORTED`。
### Acceptance
`A-BUNDLE-001`、`A-BUNDLE-002`。
### Evidence
`TEST-A-BUNDLE-001/002`；manifest、提取文件清单、树摘要、MSI SHA。

## REQ-OWN-001 — 配置/Skills 所有权保护与升级兼容

### Goal
本版不实现所有权账本，也不在 `InstallFiles` 之前做 OwnershipGuard。
### Normative Requirement
- 初始化脚本 MUST NOT 删除 `hermes-agent.broken-*`、用户 skills、配置、memory、sessions。
- 错误码含义固定，供以后使用，本版安装流程不产生它们：内容被改 = `MANAGED_CONTENT_DRIFT`；同路径同内容但 owner 不明 = `OWNERSHIP_UNKNOWN`。
- MUST NOT 为了安装成功去覆盖或删除无法证明归属的文件。
### Inputs
初始化脚本可见的现有路径。
### Preconditions
无 EarlyPreflight，无 ledger。
### Authoritative State
没有 ledger。观测是文件是否被初始化脚本删除。
### State Transition
不进入 `EARLY_OWNERSHIP_VERIFIED` 或 `USER_CONTENT_STAGED`。
### Allowed Side Effects
ALLOW：`uv` 创建的受管 `venv`，以及复制 `bin\hermes.exe`。
### Forbidden Side Effects
DENY：删除未知文件、删除 `.broken-*`、无检查的 `robocopy /E` 覆盖用户 skills。
### Ownership Scope
未登记文件保持不动。
### Idempotency
重复安装不删除未知文件。
### Failure Semantics
本版不因 ownership 分类失败。若脚本删除了 `.broken-*`，该实现不合格。
### Postconditions
`.broken-*` 在初始化前后仍在。
### Invariants
`INV-OWN-001`: 初始化不删除未知用户文件；`INV-OWN-002`: 无法证明所有权时不覆盖。
### Error Codes
`MANAGED_CONTENT_DRIFT` 与 `OWNERSHIP_UNKNOWN` 只保留定义，不是 Phase 1 的触发条件。
### Acceptance
`A-OWN-001` 与 `A-OWN-002` 不是本版发布门槛。`A-PY-005` 覆盖 `.broken-*` 不被删除。
### Evidence
`A-PY-005` 的目录清单。

## REQ-TXN-001 — 安装事务、Rollback 和恢复

### Goal
Phase 1 的事务就是现有 MSI 事务。`InitializeHermes` 保持 deferred、`Impersonate=yes`、`Return=check`。
### Normative Requirement
- 初始化脚本返回非 0 时，由 Windows Installer 回滚本次 `InstallFiles`。不新增 rollback Custom Action，不复制受管目录做 T0 字节快照，不写 `COMMITTED` 或 `FINAL_VERIFIED`。
- 不新增 `scripts/Rollback-HermesInstall.ps1`。失败诊断留在 `%TEMP%` 的 preflight/initialize 日志。
- MUST NOT 禁用 MSI rollback，MUST NOT 把 `InitializeHermes` 改成 `Return="ignore"`。
### Inputs
`InitializeHermes` 退出码、`msiexec` 退出码。
### Preconditions
`Package.wxs` 中初始化动作仍是 `Return=check`。
### Authoritative State
Observed=`msiexec` 退出码与两处 `--version`。没有 Receipt 状态机。
### State Transition
失败停在 `FAILING`。不进入 `COMMITTED`。
### Allowed Side Effects
ALLOW：MSI 自己的文件回滚；`%TEMP%` 诊断日志。
### Forbidden Side Effects
DENY：Commit Custom Action、T0 整树快照、把 `bundle-install.json` 标成 `COMMITTED`。
### Ownership Scope
Phase 1 不建所有权账本。用户已有文件的覆盖规则不在本版实现；未知文件不得被初始化脚本删除。
### Idempotency
重复失败安装不产生 `COMMITTED`。
### Failure Semantics
F-TXN-001：初始化非 0 -> MSI 回滚，`msiexec` 退出码非 0，且不存在 `status=COMMITTED` 的回执。
### Postconditions
成功时 `msiexec` 退出码为 0 且 §4.4 的两次 `--version` 通过。失败时没有 `COMMITTED`。
### Invariants
`INV-TXN-001`: 初始化失败后不存在 `COMMITTED` 回执；`INV-TXN-002`: 不新增 rollback Custom Action。
### Error Codes
沿用 §4.4 的初始化错误码。不使用 `ROLLBACK_INCOMPLETE` 作为 Phase 1 验收。
### Acceptance
Phase 1 不把 `A-TXN-001`、`A-TXN-002` 列为发布门槛。失败路径由 `A-PY-002` 至 `A-PY-005` 覆盖。
### Evidence
`msiexec` 日志与 `%TEMP%\hermes-msi-initialize.log`。

## REQ-OBS-001 — 安装诊断、错误分类与 Support Bundle

### Goal
确保回滚后仍能定位失败阶段和真实外部命令退出码。
### Normative Requirement
- MUST 把预检（含 8 个哈希逐项结果）写到 `%TEMP%\hermes-msi-preflight.log`，把初始化（含完整 uv 命令行、allowlist 后的 `UV_*` 快照、uv 退出码、两次 `--version` 的 stdout 第一行与退出码）写到 `%TEMP%\hermes-msi-initialize.log`。
- MUST NOT 创建 `%LOCALAPPDATA%\SMC\HermesInstaller\diagnostics`，MUST NOT 新增 `scripts/Collect-HermesInstallDiagnostics.ps1`。
- MUST NOT 只输出 `1603` 而丢弃子错误。MUST NOT 把 `uv sync` 退出码 0 本身当作 Python 环境就绪——必须另行记录 `venv\Scripts\hermes.exe` 的存在性与两次 `--version` 结果。
### Inputs
operationId、Windows Installer logging、阶段子进程 stdout/stderr/exit、event log。
### Preconditions
`%TEMP%` 可写。Phase 1 **不要求**任何 `%LOCALAPPDATA%\SMC\HermesInstaller\diagnostics` 目录，也不使用 `DIAGNOSTICS_UNAVAILABLE`——该错误码属 PHASE 2，与本节 Normative 的「MUST NOT 创建该目录」不冲突。
### Authoritative State
SOT=`%TEMP%` 两个日志的原始文本；Derived=summary（不能覆盖原始错误码）。
### State Transition
任何 Stage `STARTED -> PASS/FAIL`，结果写入 `%TEMP%` 日志；成功/失败皆保留。`SUPPORT_BUNDLE_CREATED` 属 PHASE 2。
### Allowed Side Effects
ALLOW：`%TEMP%\hermes-msi-preflight.log`、`%TEMP%\hermes-msi-initialize.log`。PHASE 2 才引入独立诊断目录与用户发起的 ZIP。
### Forbidden Side Effects
DENY：上传日志到公网、记录明文密钥、重写其他 operation 日志、访问不在白名单的私人文件。
### Ownership Scope
GENERATED_ONLY / FILE；日志 append-only（同 operation），收集只读。
### Idempotency
每个 operation 新目录；重复收集生成相同源文件清单，不改变源文件。
### Failure Semantics
Phase 1：初始化以非 0 退出时，`%TEMP%\hermes-msi-initialize.log` MUST 已落盘并含本节 Error Codes 中的具体错误码。F-OBS-001（`DIAGNOSTICS_UNAVAILABLE`）与 F-OBS-002（`SUPPORT_BUNDLE_REDACTION_FAILED`）属 PHASE 2，Phase 1 不产生。
### Postconditions
失败安装之后仍能读到 `%TEMP%\hermes-msi-preflight.log` 或 `%TEMP%\hermes-msi-initialize.log` 里的退出码与错误码。
### Invariants
`INV-OBS-001`: 失败时日志里的错误码非空；`INV-OBS-002`: 这两个日志不在 MSI 会回滚的安装目录里。
### Error Codes
Phase 1 写入上述日志的错误码取自 §4.4：`HERMES_SOURCE_TREE_MISSING`、`VENV_RELOCATABLE`、`HERMES_CLI_MISSING_POST_SYNC`、`HERMES_CLI_VERIFY_FAILED`、`UV_SYNC_FAILED`、`BUNDLE_INTEGRITY_FAILED`、`DISK_SPACE_INSUFFICIENT`、`INSTALL_CONTEXT_UNSUPPORTED`。不使用 `NODE_SMOKE_FAILED`、`DIAGNOSTICS_UNAVAILABLE` 与 `SUPPORT_BUNDLE_REDACTION_FAILED`。
### Acceptance
日志路径以 §4.4 第 12 条为准。**Phase 1 Required：`A-OBS-003`**（失败安装后日志存在且错误码非空）。`A-OBS-001` 与 `A-OBS-002` 属 PHASE 2，不是本版发布门槛。
### Evidence
`TEST-A-OBS-003`；`%TEMP%\hermes-msi-initialize.log`。

## REQ-SEC-001 — Core 安装期网络与安全边界

### Goal
严格离线安装不接触公网或局域网依赖，不扩大权限/执行范围。
### Normative Requirement
- MUST 只统计 `InitializeHermes` 拉起的 `powershell.exe`、`uv.exe`、`python.exe`、`hermes.exe`、`node.exe`、`npm.cmd`。这些进程的连接尝试计数必须为 0，否则 `OFFLINE_EGRESS_DETECTED`。`msiexec`、CRL、OCSP、SmartScreen 不计入。
- MUST 使用固定 SHA 来源、明确下载/构建命令；`Invoke-RestMethod | Invoke-Expression` 不得出现在 Core Endpoint 安装执行图中。
- MUST 在写目标路径前拒绝 path traversal、junction/symlink/reparse point 指向安装根外、并发同目录安装；必须按照 per-user 权限运行。
- MUST NOT 上传配置与凭据；日志须红线过滤 secrets；如果仅为测试环境使用未签名 MSI，不得被标记为 production release PASS。
### Inputs
安装包、Endpoint 安全/网络状态、路径与文件属性、发布元数据。
### Preconditions
manifest 已验证；安装日志可写；网络观测器/CI 设备可用。
### Authoritative State
SOT=Core Offline Policy + 签名/摘要；Observed=网络连接尝试事件、路径规范化检查、签名验证。
### State Transition
`PREFLIGHT -> PAYLOAD_VERIFIED`；网络/路径/身份失败 -> `FAILING`。
### Allowed Side Effects
ALLOW：Build Host 网络下载；Endpoint 本地文件与用户注册表；受控诊断。
### Forbidden Side Effects
DENY：Endpoint 网络请求（含失败连接尝试）、管理员越权、远程脚本执行、未经批准的文件修改。
### Ownership Scope
RESOURCE / FILE / NONE（对外网）。
### Idempotency
多次安装无联网尝试，受限路径保持一致；不同主机不能被签名之外的同名 MSI 欺骗。
### Failure Semantics
F-SEC-001：网络尝试 -> `OFFLINE_EGRESS_DETECTED`；F-SEC-002：越界路径 -> `INSTALL_PATH_ESCAPE`；F-SEC-003：来源验签失败 -> `PACKAGE_TRUST_FAILED`，0 核心安装 mutation，retryable=使用可信包 YES。
### Postconditions
Core 计数范围内的连接尝试 count=0。`msiexec` 的证书检查不计入。
### Invariants
`INV-SEC-001`: no endpoint network attempts；`INV-SEC-002`: no write outside ownership allowlist。
### Error Codes
`OFFLINE_EGRESS_DETECTED`, `INSTALL_PATH_ESCAPE`, `PACKAGE_TRUST_FAILED`。
### Acceptance
`A-SEC-001`、`A-SEC-002`。
### Evidence
`TEST-A-SEC-001/002`；网络事件归属报告、文件写入快照、包签名/摘要检查。

## REQ-CI-001 — 多终端 Golden Consumer 与 Release Gate

### Goal
构建成功不再替代安装成功；消除“一台 Win10 成功另一台失败”的盲区。
### Normative Requirement
- MUST 在 Windows 10 x64 与 Windows 11 x64 的 per-user 安装上跑通 §34.2 点名的终端验收：8 个关键文件哈希与两次 `--version`。构建期验收（A-BUILD-001/002、A-SRC-001/002、A-ENV-001）在 CI 的构建 job 内完成，不占用终端矩阵。不把终端 Node、升级回滚专项、Chromium smoke 或所有权账本列入本版门槛。
- MUST 绑定 `msiSHA256`、Builder/Source SHA、Windows build、环境对比、每个 AC 的 test/exit/oracle/evidence。
- MUST NOT 将 `SKIPPED`、`BLOCKED`、`NOT_RUN` 当作 PASS；任一 Required AC != PASS 时 release job exit !=0。
- MUST 使用 Synthetic Fault Injection + 至少 1 个实际 smc-copilot 桌面 Hermes Consumer 验证；真实 Consumer 版本/HEAD/clean status 与用户目录 digest 必须记录。
### Inputs
CI MSI artifact、VM 基线、故障夹具、真实 Desktop Consumer。
### Preconditions
已完成静态测试、源码/包摘要准确，VM 可复位。
### Authoritative State
SOT=Release Gate evidence JSON + 实际 exit；Observed=真实 Endpoint 状态。
### State Transition
`BUILD_COMPLETED -> TEST_RUNNING -> VERIFIED/RELEASE_BLOCKED`；`VERIFIED -> RELEASED` 需人工审批发布。
### Allowed Side Effects
ALLOW：隔离 VM 安装/卸载、Evidence 目录、标注结果。
### Forbidden Side Effects
DENY：将机器污染快照充当干净机、在 Golden Consumer 有未提交源码时忽略差异、绕过 required AC。
### Ownership Scope
GENERATED_ONLY / EVIDENCE_STATE；测试用户目录必须快照恢复。
### Idempotency
重跑相同 MSI 使用全新 VM 快照；所有测试计算可比较 SHA/Oracle。
### Failure Semantics
F-CI-001：任何 Required AC !=PASS -> `RELEASE_GATE_FAILED`，发布 0 次，retryable=修复后重新跑全量 Required。
### Postconditions
每个 Required AC 可追踪到测试与 Evidence；Release PASS 时真实 Consumer 安装与 CLI 调用通过。
### Invariants
`INV-CI-001`: REQUIRED!=PASS -> release exit!=0；`INV-CI-002`: Golden Consumer 不可被 Synthetic 替代。
### Error Codes
`RELEASE_GATE_FAILED`, `GOLDEN_CONSUMER_FAILED`。
### Acceptance
`A-CI-001`、`A-CI-002`。
### Evidence
`TEST-A-CI-001/002`；安装日志、Consumer 测试输出、VM OS/网络与 SHA 报告。

# 11. Side-Effect Contract

`Phase` 列指出该 Operation 是否在本版执行。标 `PHASE 2` 的行是后续阶段草稿，Phase 1 **不执行、不实现**，Plan / Coding Agent **MUST NOT** 据此生成任务，也 **MUST NOT** 因其与 §4.4 不一致而触发 §0.3 的 `SPEC_SEMANTIC_GAP`。

| Operation | Phase | DB Write | File Write | Network | Cache | User Data | Business Source |
|---|---|---:|---:|---:|---:|---:|---:|
| `build.resolve_source` | PHASE 1 | NO | Build Host only | Build Host MAY | Build Host MAY | NO | NO |
| `build.populate_cache` | PHASE 1 | NO | Build Host only | Build Host YES | Build Host YES | NO | NO |
| `build.offline_rebuild_proof` | PHASE 1 | NO | Build Host 临时 venv / node_modules（打包前删除） | NO | 已填充缓存只读 | NO | NO |
| `build.generate_manifest` | PHASE 1 | NO | Build Host only（8 个路径的 SHA256） | NO | NO | NO | NO |
| ~~`msi.early_preflight_guard`~~ | PHASE 2 | NO | 独立诊断/T0 recovery snapshot；不触及安装根 | NO | NO | 原文件只读 | NO |
| `msi.post_file_preflight` | PHASE 1 | NO | MSI InstallFiles 已执行、仅诊断（`%TEMP%` 日志） | NO | NO | NO | NO |
| `msi.verify_payload` | PHASE 1 | NO | 仅诊断 | NO | NO | NO | NO |
| `msi.uv_sync` | PHASE 1 | NO | `venv` staging | NO | 已打包缓存只读 | 仅受管 venv | NO |
| `msi.stage_launchers` | PHASE 1 | NO | `bin\hermes.exe` 等受管 trampoline | NO | NO | NO | NO |
| ~~`msi.node_core`~~ | PHASE 2 | NO | `node_modules` staging | NO | 已打包缓存只读 | 仅受管 Node | NO |
| `msi.install_default` | PHASE 1 | NO | 仅缺失模板与无冲突 managed Skill | NO | NO | 新用户文件仅缺失时创建 | NO |
| ~~`msi.commit`~~ | PHASE 2 | NO | Receipt/ledger/用户级注册表 | NO | NO | NO（已有用户文件不改） | NO |
| ~~`msi.rollback`~~ | PHASE 2 | NO | 受管内容与注册表精确恢复 | NO | NO | 用户内容恢复原字节 | NO |
| ~~`collect_diagnostics`~~ | PHASE 2 | NO | 仅用户指定 ZIP | NO | NO | 只读且脱敏 | NO |

Phase 1 的回滚由现有 Windows Installer 事务对本次 `InstallFiles` 执行，没有 `msi.rollback` 这个独立 Operation（§4.4 第 11 条、§14.3）。

`cache/telemetry/log` 属于 side effect：MSI 安装缓存根不得访问公网。Phase 1 的诊断写入只允许 `%TEMP%\hermes-msi-preflight.log` 与 `%TEMP%\hermes-msi-initialize.log`（§4.4 第 12 条）；上文提到的 `diagnostics/<operationId>` 目录属 PHASE 2。只读分析不含修改其他目录。安装期对 OS Application 日志为只读。

# 12. Ownership Contract

## 12.1 Ownership Type

`GENERATED_ONLY`：`venv/`、Node modules、诊断/恢复工件；`FILE`：manifest、ledger、receipt；`ENTRY`：用户级 PATH/HERMES_HOME/ Git Bash 项；`USER_OWNED`：`.env`、`config.yaml`、`SOUL.md`、已有用户 Skills/Memory/Sessions；`SHARED`：`skills/` 下混合归属逐文件判定。

## 12.2 Ownership Rule（PHASE 2 草稿，非 normative）

**Phase 1 的全部所有权约束只有一条**：初始化脚本 **MUST NOT** 删除 `hermes-agent.broken-*`、用户 skills、配置、memory、sessions（REQ-OWN-001），由 `A-PY-005` 覆盖。

以下规则是 PHASE 2 草稿，Phase 1 **不实现**，Plan / Coding Agent **MUST NOT** 据此生成任务，也 **MUST NOT** 因其与 §4.4 不一致而触发 §0.3 的 `SPEC_SEMANTIC_GAP`。Phase 1 不创建 ledger，错误码只保留定义：
- 更新后：仅 ledger 显示 `currentHash==lastAppliedHash` 的 managed file 允许替换；换代后写新 applied hash。
- 用户修改后：drift 检测为 `MANAGED_CONTENT_DRIFT`，保留原字节，停止覆盖。
- 升级时：对未知归属执行 `PRESERVE + REPORT + BLOCK on same-path conflict`，不允许 last-writer-wins。
- remove 时：只删除 ledger 证明的受管生成文件，配置/用户文件不删除；未知目录不递归删除。

## 12.3 Drift（PHASE 2 草稿，非 normative）

`current==lastApplied -> managed_unchanged`；`current!=lastApplied -> drifted`；无 owner proof -> unknown；两者默认 `BLOCK` 冲突写入，保留资源及诊断记录。Phase 1 不做 drift 判定。

# 13. Hash / Identity Contract

Phase 1 的文件哈希 Oracle 只有 §4.4 第 8 条的 8 个路径。下面关于全量树拼接的算法不是本版要求，不得据此把未列入这 8 个路径的文件判为 `BUNDLE_INTEGRITY_FAILED`。

- MSI 发布身份：`SHA256(raw .msi bytes)`，十六进制小写；`dist/*.sha256` 的 hex 与文件计算值必须一致。
- Builder/source identity：固定 Git commit 40 位小写 hex；发布来源以 SHA 不以 tag/branch 命名。
- `managedFiles[].path`：相对 payload 根，斜线统一 `/`、Unicode NFC、大小写保留，路径不得包含 `..`、绝对路径、结尾空格/点或 reparse point；Windows 大小写折叠重复路径拒绝；按 UTF-8 路径原始字节升序排序。
- 单文件：`fileSha256 = SHA256(file bytes)`；不包含 mtime、owner、ACL 或 NTFS alternate data streams；符号链接/reparse point 禁止在归属树中，不允许计算到目录外。
- 树摘要：对每个普通文件依次拼接 `relative_path_utf8 + NUL + lowercase_sha256_ascii + NUL + decimal_size_ascii + LF`，最终 `SHA256(concatenated bytes)`，输出 hex lowercase。`runtime-manifest.json` 本身排除以避免自引用；`state/`、`logs/`、用户生成文件不属于 payload tree；`official-source.json` 如果参与摘要，必须先于 manifest 生成。
- 安装后 managed ledger digest：同路径与内容规则，作用域仅安装器确权的 managed files；用户内容只计算对比摘要，不写入 Release Manifest。
- 任何 manifest 未列出的打包普通文件或列出文件缺失都为 `BUNDLE_INTEGRITY_FAILED`；路径排序规则为确定值。
- SHA256 完整性不等于真实性：生产放行必须关联可信签名或企业可信发布通道的 MSI SHA；未签名仅可测试，不可标为 production PASS。

# 14. Transaction Contract

## 14.1 Transaction Boundary

TXN includes：本次 MSI InstallFiles 下受管文件释放、Python/Node staging、用户级 PATH/HERMES_HOME 受管项、默认模板首次创建、无冲突企业 Skills、Receipt/ledger 的受控提交。TXN excludes：用户已拥有的配置、未知 Skills、历史数据、未明确确权的现存目录、独立诊断/恢复证据（刻意保留）。

## 14.2 Commit Order

Phase 1 的顺序只有这一条，且与 `installer/Package.wxs` 现有的 `InstallExecuteSequence` 完全一致：

构建期：`固定 source SHA -> 填充 uv/npm 缓存与 Chromium -> 离线重建证明（§4.4 第 14 条）-> 生成 8 条哈希的 manifest -> 打包 MSI 并记录字节 SHA256`。

终端：`MSI InstallFiles -> Preflight（身份、架构、PowerShell、路径长度、4GB，并核对 §4.4 的 8 个文件哈希）-> uv sync --offline --locked --no-config（allowlist 环境）-> venv\Scripts\hermes.exe --version -> 复制 bin\hermes.exe -> bin\hermes.exe --version -> PHASE1_CLI_READY`。

终端序列到此为止。**不调用上游 `install.ps1`，不运行 node/npm/npx，不执行 `git clone`。**

**`Preflight` 在 `InstallFiles` 之后**，因为它校验的正是 `InstallFiles` 刚释放到 `[HermesRoot]` 下的 payload（现有 `Preflight-HermesInstall.ps1` 对 `bin\uv.exe`、`offline\uv-cache`、`hermes-agent\pyproject.toml` 等路径的 `Test-Path` 已依赖这一点）。任何把 Preflight 提前到 `InstallFiles` 之前的实现都是错误的，见 §8。

不插入 EarlyPreflight、T0 快照、所有权账本、`FINAL_VERIFIED` 或 `COMMITTED`。不使用 Commit Custom Action，也不在 `msiexec` 返回后另写提交回执。

## 14.3 Failure Atomicity

本版不使用 T0 字节快照。初始化失败时只依赖 Windows Installer 对本次 `InstallFiles` 的回滚，加上 `%TEMP%` 里的诊断日志。

## 14.4 Rollback Failure

本版不定义 `ROLLBACK_INCOMPLETE`，不创建 `%LOCALAPPDATA%\SMC\HermesInstaller\recovery`，也不给 `Repair-Hermes.ps1` 增加 `-RecoverOperationId`。

# 15. Conflict Contract

下表只固定错误码含义，属 PHASE 2 草稿。Phase 1 不执行这张表，不因此阻断安装。Plan / Coding Agent **MUST NOT** 据此生成任务，也 **MUST NOT** 因其与 §4.4 不一致而触发 §0.3 的 `SPEC_SEMANTIC_GAP`。例外：`SOURCE_REF_MISMATCH` 一行在 Phase 1 生效（构建期，REQ-SRC-001）。

| Conflict | Detection | Default Behavior | Error | Mutation |
|---|---|---|---|---|
| 同路径不同 content | new hash != current hash 且无归属证明 | BLOCK+PRESERVE | `USER_CONTENT_CONFLICT` | 0 用户字节 |
| 同路径相同内容不同 owner | ledger owner 缺失/矛盾 | BLOCK+PRESERVE | `OWNERSHIP_UNKNOWN` | 0 用户字节 |
| managed drift | current != ledger.lastApplied | BLOCK+PRESERVE | `MANAGED_CONTENT_DRIFT` | 0 用户字节 |
| 预存未知 venv | 无 ledger 且路径存在 | BLOCK | `OWNERSHIP_UNKNOWN` | 0 |
| 并发 MSI | 同根锁占用 | BLOCK | `INSTALL_CONCURRENT` | 0 |
| Payload 重解析路径 | 检测到 symlink/junction 逃逸 | BLOCK | `INSTALL_PATH_ESCAPE` | 0 |
| Source mutable ref | actual HEAD != pinned SHA | BLOCK | `SOURCE_REF_MISMATCH` | 0 发布产物 |

任何冲突不得采用 last-writer-wins、默认覆盖或 best-effort。

# 16. Compatibility / Migration

## 16.1 Existing State

既有 Core SKU 0.21.0：`%LOCALAPPDATA%\hermes`、`runtime-manifest.json` v1、`state/bundle-install.json` v1；用户配置文件和 `skills/` 与受管内容混存；WiX `UpgradeCode` 已固定。旧版本 `WixToolset.Sdk/5.0.2`，Core SKU 为 per-user。

## 16.2 Migration

**Phase 1 的迁移行为只有一条**：沿用现有 MSI `MajorUpgrade` 与 `Package.wxs` 的组件级覆盖规则，初始化脚本对已存在的 `.env` / `config.yaml` / `SOUL.md` 继续「仅缺失时创建」，并且不删除任何未知文件。Phase 1 不做 `adopt`、不建 ledger、不生成 v2 receipt、不做 T0 快照。

下列五步是 PHASE 2 草稿，Phase 1 **不实现**，Plan / Coding Agent **MUST NOT** 据此生成任务，也 **MUST NOT** 因其与 §4.4 不一致而触发 §0.3 的 `SPEC_SEMANTIC_GAP`：

1. `detect`：读取注册 MSI 产品身份、manifest/receipt v1、目标文件、用户数据与旧 User PATH 值。
2. `adopt`：旧 v1 的 managed ownership **不自动推定**；只有已受信 MSI 元数据能证明文件归属、且当前文件 SHA 匹配时才可登记。
3. `migrate`：先建立 T0 与诊断快照；将可确认的受管生成目录重新构建并验证；生成 v2 ledger/receipt；保留用户文件原字节。
4. `preserve`：旧 `.env/config.yaml/SOUL.md`、未知 Skills、sessions/memory、unknown venv 不覆盖。
5. `remove`：仅去除完成迁移且已核验可替换的旧受管工件，不删除未知目录。

## 16.3 Unknown Ownership（PHASE 2 草稿，非 normative）

无法证明 owner：`PRESERVE + REPORT + MUST NOT DELETE`，如新旧路径冲突则 `OWNERSHIP_UNKNOWN` 阻断升级。发布测试包含“既有成功安装机器”与“失败回滚残留机器”。Phase 1 只保证不删除未知文件。

# 17. External Dependency Contract

| Dependency | Source/endpoint | Version/identity | Build Host | Endpoint offline / failure |
|---|---|---|---|---|
| Hermes source | `https://github.com/loudon84/copilot-hermes` | `041b6985a00d01b54f830c1607dd370007a306bf`（配置示例；Release 实际 MUST 固定） | 可 clone | 仅读内置源码；缺失→`BUNDLE_INTEGRITY_FAILED` |
| Builder source | `smc-copilot/hermes-builder` | 基线 `07db1c6f...70aa3b` | Git checkout | 只看 manifest/hash |
| WiX | WiX SDK + Util | `5.0.2` | dotnet restore | 不运行 WiX |
| Python | uv 管理 Python | 3.11 + 记录 runtime identity | 在线安装/复制 | 内置，不访问 python.org |
| uv | 内置 `bin/uv.exe` | 实际版本写 manifest | PyPI/缓存填充 | `--offline --no-config`，失败即停 |
| npm/Node | 内置 `node/` | Node 22.23.2 仅为失败样本实测；真实版本以构建时记录 | registry.npmjs.org 可用 | `npm_config_offline=true`，绝无网络 fallback |
| Playwright Chromium | 构建机预装 | SHA 实际记录 | 联网下载 | 内置可执行，缺失 Core 如果被声明为 required 则失败 |
| Browser Use CLI | upstream `uv tool install browser-use` | 非 Core | Build Host 可预热但不打进 Core Required | Core MUST NOT 启动该命令 |
| CUA Driver | upstream GitHub raw 安装脚本 | 非 Core | Build Host 可分析 | Core MUST NOT 发起远程下载 |

`package-lock.json`、`uv.lock` 必须与打包源码同一固定 SHA/树内容。绝不由 AI Agent 自行升级供应商依赖版本。

# 18. Security Contract

| Threat | Control | Acceptance |
|---|---|---|
| 路径穿越 | 标准化路径，拒绝 `..`、绝对路径、无效 NTFS 名称 | `A-SEC-002` |
| Junction / symlink | staging/payload/recovery 路径拒绝跳出受管根 | `A-SEC-002` |
| 远程脚本与任意执行 | Core 不执行 `irm|iex`、`Invoke-RestMethod|Invoke-Expression`，不调用 optional tooling | `A-NODE-002`、`A-SEC-001` |
| 凭据暴露 | env/config 不进入日志/ZIP，支持敏感文本脱敏扫描 | `A-OBS-002` |
| 写入越界 | 受管 FILE/ENTRY 白名单、T0 digest | `A-OWN-001`、`A-TXN-001` |
| 供应链篡改 | pinned commit、lock、manifest digest、MSI release SHA/签名 | `A-SRC-001`、`A-BUNDLE-002` |
| 不可信环境变量 | child process allowlist，强制内置工具路径 | `A-ENV-001` |
| 数据外泄 | Endpoint Core 安装进程树零连接尝试、日志不上传 | `A-SEC-001` |
| 权限越界 | per-user 限定，不允许 SYSTEM、Machine PATH 变更 | `A-ENV-002` |

# 19. Observability

Phase 1 的可观测性只有两份纯文本日志（§4.4 第 12 条），不发 JSONL 事件、不建 operation 目录、不生成 support bundle。

- `%TEMP%\hermes-msi-preflight.log`：身份 / 架构 / PowerShell / 路径长度 / 4GB 空闲 / 8 个文件哈希的逐项结果，失败时含 `BUNDLE_INTEGRITY_FAILED`、`DISK_SPACE_INSUFFICIENT` 或 `INSTALL_CONTEXT_UNSUPPORTED`。
- `%TEMP%\hermes-msi-initialize.log`：阶段 `UV_SYNC`（完整命令行含 `--no-config`、allowlist 后的 `UV_*` 快照、退出码）与 `VERIFY_PYTHON`（两次 `--version` 的 stdout 第一行与退出码），失败时含 §4.4 的对应错误码。Phase 1 没有 `NODE_DEPS` 阶段。
- 错误归因优先级：原始命令 exit / 具体缺失路径 / 阶段级 code > WiX 1603 汇总码；跨进程的 stdout/stderr 归属必须保留（A-OBS-003 的 Oracle 依赖这一点）。
- 这两份日志 **MUST** 在初始化以非 0 退出时已完成落盘。参考 §34.1 对 `Initialize-Hermes.ps1` 的 `Stop-Transcript` 改动要求。

> **以下属 PHASE 2，非 normative：** 每阶段 JSONL（`operationId`, `stage`, `status`, `timestampUtc`, `builderCommit`, `sourceCommit`, `msiSha256`, `result`, `errorCode`, `elapsedMs`）；`msi.log` / `uv-sync.log` / `node-core.log` / `events.jsonl` / `summary.json` 分文件保留；脱敏 `support-bundle.zip`。

# 20. Acceptance Design Standard

> 每项 AC 的 `Oracle` 均是机器判定。**Phase 1 Required（13 项）**：A-BUILD-001、A-BUILD-002、A-SRC-001、A-SRC-002、A-BUNDLE-001、A-BUNDLE-002、A-PY-001 至 A-PY-005、A-ENV-001、A-OBS-003。其中 **A-BUILD-001/002 与 A-ENV-001 在构建机上执行，不需要终端**；A-PY-001 与 A-OBS-003 需要一次无网安装。A-NODE-001 已随 §4.4 第 2 条移入 PHASE 2。其余 AC 标 `PHASE 2`，不是本版发布门槛，Plan **MUST NOT** 为它们生成任务。实际 Evidence 文件须含 `repoCommit`, `testId`, `command`, `exitCode`, `timestampUtc`, `toolVersions`，具体文件命名为 `evidence/<acceptanceId>.json`。测试执行结果目前均为 NOT_RUN。

| Acceptance / Requirement refs | Given | When | Then | Oracle | Evidence (Test ID / artifact) |
|---|---|---|---|---|---|
| **A-BUILD-001（Phase 1 Required，构建机）** / REQ-BUILD-001 | uv 缓存已填充，venv 已删除，构建机断网或强制 `--offline` | `uv sync --offline --locked --no-config` | 离线重建出可运行 CLI | uv exit=0；`venv\Scripts\hermes.exe` 存在；其 `--version` exit=0 且第一行匹配锁定版本；打包前该 venv 已被删除 | TEST-A-BUILD-001 / build-info.json `offlineProof` |
| **A-BUILD-002（Phase 1 Required，构建机）** / REQ-BUILD-001 | npm 缓存已填充，`node_modules` 已删除 | `npm_config_offline=true` 下跑 `node-deps` | 缓存自足，Chromium 已落盘 | node-deps exit=0；`node_modules` 存在；`payload\playwright` 下存在 `chrome.exe` 或 `headless_shell.exe`；打包前 `node_modules` 已被删除 | TEST-A-BUILD-002 / build-info.json `offlineProof` |
| A-SRC-001 / REQ-SRC-001 | 本地 HEAD 不等于 source.ref | release build | 拒绝构建 | exit!=0; code=`SOURCE_REF_MISMATCH`; dist 新 MSI 数=0 | TEST-A-SRC-001 / source-diff.json |
| A-SRC-002 / REQ-SRC-001 | 本地 HEAD 等于 pinned SHA、clean | release build | 元数据含精确 commit 与 sha | commit exact match; SHA256(msi)==*.sha256 | TEST-A-SRC-002 / build-info.json |
| A-PY-001 / REQ-PY-001 | 干净 Win10、内置缓存完整、源码树含 pyproject.toml | 断网 MSI 安装 | uv 后两处 CLI 可运行，且已复制到 bin | 两次 `--version` 退出码都为 0；两次 stdout 第一行都匹配 `^Hermes Agent v0.21.0 \(`；整个初始化期间 `install.ps1`/npm/npx/node/`git clone` 调用计数=0 | TEST-A-PY-001 / uv-sync.log |
| A-PY-002 / REQ-PY-001 | 注入 uv exit0 但缺少 `venv\Scripts\hermes.exe` | 执行初始化 | Node/npm 不执行、报独立错误 | code=`HERMES_CLI_MISSING_POST_SYNC`; npm/node invocation count=0 | TEST-A-PY-002 / events.jsonl |
| A-PY-003 / REQ-PY-001 | uv 后 `venv\Scripts\hermes.exe` 存在，复制前被删除 | 启动阶段 | 不写成功标记 | 复制前 exists=false；code=`HERMES_CLI_MISSING_POST_SYNC` | TEST-A-PY-003 / file-snapshots.json |
| A-PY-004 / REQ-PY-001 | `pyvenv.cfg` 含 `relocatable=true` | uv 成功后检查 | 安装失败，不留仅有的 `.cmd` | code=`VENV_RELOCATABLE`；`bin\hermes.cmd` 不得被当作成功 | TEST-A-PY-004 / pyvenv.cfg |
| A-PY-005 / REQ-PY-001 | `hermes-agent\pyproject.toml` 缺失，旁路存在 `.broken-*` | 执行初始化 | 失败且不改动备份 | code=`HERMES_SOURCE_TREE_MISSING`；`.broken-*` 仍在；git clone 调用计数=0 | TEST-A-PY-005 / source-tree.json |
| A-NODE-001（PHASE 2） / REQ-NODE-001 | 两次 --version 已通过，npm cache 可用 | 用随包 `npm.cmd` 直接安装（不经上游 `install.ps1`） | Node smoke 通过 | `hermes-agent\node_modules` 存在；`npm ls --offline --depth=0` 退出码=0（2026-10-08 开发机实测该命令在健康安装上为 0）；`ok:true` 单独出现不算通过 | TEST-A-NODE-001 / initialize.log |
| A-NODE-002 / REQ-NODE-001 | Browser Use、CUA 均未安装 | Core MSI 安装 | 不尝试下载 | network attempt count=0；这两个安装命令调用计数=0 | TEST-A-NODE-002 / process-tree.json |
| A-NODE-003 / REQ-NODE-001 | 注入缺失 npm tarball/模块 | Core Node 安装 | 拒绝继续但不误报成功 | code=`NODE_CORE_INSTALL_FAILED`/`NODE_CORE_VERIFY_FAILED`; Receipt not COMMITTED | TEST-A-NODE-003 / failure.json |
| **A-ENV-001（Phase 1 Required，构建机可执行）** / REQ-ENV-001, REQ-NODE-001 | ①注入 `UV_NO_INSTALL_PROJECT=1`、`UV_NO_SYNC=1`、`UV_CONFIG_FILE=<恶意 toml>`、`VIRTUAL_ENV=<他处>`；②`Initialize-Hermes.ps1` 源文件 | ①在 allowlist 环境下跑受管 `uv sync`；②静态扫描 | ①注入无效化，CLI 仍生成；②执行图干净 | ①uv exit=0 **且** `venv\Scripts\hermes.exe` 存在、`--version` exit=0；所用 uv/python 为随包绝对路径；命令行含 `--no-config`。**对照组**：不加 allowlist 与 `--no-config` 时必须能复现「exit=0 但无 CLI」，否则该机理证伪、需重查 P-001。②脚本中 `install.ps1`/`npm`/`npx`/`node`/`git clone`/`Invoke-RestMethod`/`Invoke-WebRequest` 匹配数=0 | TEST-A-ENV-001 / env-snapshot.json, static-scan.json |
| A-ENV-002（PHASE 2） / REQ-ENV-001 | SYSTEM 或低磁盘或非 Win10 | 执行 Preflight | 提前拒绝并保留日志 | specific error code; no user-owned digest change | TEST-A-ENV-002 / preflight.log |
| A-BUNDLE-001 / REQ-BUNDLE-001 | MSI 无篡改 | `InstallFiles` 之后、`uv` 之前由 Preflight 核对 manifest | 8 个关键文件哈希一致 | `runtime-manifest.json` 的 `hashes` 含全部 8 条；这 8 个路径都存在且 SHA256 相等；Preflight exit=0；然后才允许 uv | TEST-A-BUNDLE-001 / manifest-hashes.json |
| A-BUNDLE-002 / REQ-BUNDLE-001 | 改动这 8 个文件之一的字节 | Preflight 核对 | 停止 uv | Preflight exit!=0; code=`BUNDLE_INTEGRITY_FAILED`; uv invocations=0 | TEST-A-BUNDLE-002 / tamper-evidence.json |
| A-OWN-001 / REQ-OWN-001 | 预存用户配置/非冲突 Skills | 首次/重复/升级 | 用户内容不变 | protected file digests equal | TEST-A-OWN-001 / ownership-digests.json |
| A-OWN-002 / REQ-OWN-001 | 同路径 Skill 被用户修改 | 安装升级 | 保留冲突文件、阻止覆盖 | code=`MANAGED_CONTENT_DRIFT`; target hash same T0 | TEST-A-OWN-002 / conflicts.json |
| A-TXN-001 / REQ-TXN-001 | 运行中阶段失败 | MSI rollback | 恢复原 managed 状态 | managed digest after==T0; no COMMITTED receipt | TEST-A-TXN-001 / rollback-digest.json |
| A-TXN-002 / REQ-TXN-001 | 注入 rollback 自身失败 | MSI rollback | 保留 recovery 且阻止静默重试 | code=`ROLLBACK_INCOMPLETE`; recovery files retained; state RECOVERY_REQUIRED | TEST-A-TXN-002 / recovery.json |
| A-OBS-001 / REQ-OBS-001 | MSI 初始化 uv/npm 失败 | rollback + 收集 | 保留真实错误日志 | summary.errorCode nonempty; logs outside MSI root | TEST-A-OBS-001 / support-bundle.zip |
| A-OBS-002 / REQ-OBS-001 | 日志含假 token、账号/路径 | 收集 Support Bundle | 无敏感原文 | fixture secrets grep hits=0; .env files=0 | TEST-A-OBS-002 / redaction-report.json |
| **A-OBS-003（Phase 1 Required）** / REQ-OBS-001 | 注入 A-PY-002 至 A-PY-005 任一失败场景并触发 MSI 回滚 | 回滚结束后读取 `%TEMP%` | 日志仍在且含具体错误码 | `%TEMP%\hermes-msi-initialize.log` 存在；其内容含 §4.4 定义的错误码之一且非空；该路径不在 `%LOCALAPPDATA%\hermes` 下 | TEST-A-OBS-003 / initialize.log |
| A-SEC-001 / REQ-SEC-001 | 断开网络并捕获失败连接尝试 | 运行完整 MSI | 不执行任何安装期网络调用 | installer process tree connection attempts=0 | TEST-A-SEC-001 / network-events.json |
| A-SEC-002 / REQ-SEC-001 | 路径 junction 指向根外/包篡改 | 安装 | BLOCK、0 越界写入 | code=`INSTALL_PATH_ESCAPE`/`PACKAGE_TRUST_FAILED`; outside writes=0 | TEST-A-SEC-002 / fs-trace.json |
| A-CI-001 / REQ-CI-001 | Win10/Win11 干净 VM + Required AC | CI/离线复测 | 全部 PASS 才可发布 | requiredFailed=0, requiredSkipped=0, releaseExit=0 | TEST-A-CI-001 / release-gate.json |
| A-CI-002 / REQ-CI-001 | 实际 smc-copilot Consumer、同 MSI SHA | 启动本地 Hermes | 桌面探针通过 | `bin\hermes.exe --version` exit=0 且第一行匹配 `^Hermes Agent v0.21.0 \(`；Consumer probe 的 `executablePath` 指向该文件且 exit=0 | TEST-A-CI-002 / golden-consumer.json |

# 21. Acceptance Input Matrix

| Case | 初始状态/输入 | 网络 | 注入 | Expected | Refs |
|---|---|---|---|---|---|
| M-01 | 干净 Win10 x64 普通用户 | blocked | none | full PASS | A-PY-001,A-CI-001 |
| M-02 | 干净 Win11 x64 管理员交互用户 | blocked | none | full PASS | A-PY-001,A-CI-001 |
| M-03 | 旧 v1 receipt/现存 venv | blocked | same release | 不盲目信任 receipt，重新 verify/adopt | A-OWN-001,A-CI-001 |
| M-04 | 同机重复安装相同 SHA | blocked | none | 幂等；配置 hash 不变 | A-OWN-001,A-CI-001 |
| M-05 | 当前 uv 缓存缺文件 | blocked | remove one cached file | integrity FAIL、Node 不执行 | A-BUNDLE-002 |
| M-06 | uv exit0、CLI 文件 absent | blocked | delete at post uv | CLI FAIL、Node count=0 | A-PY-002 |
| M-07 | uv 完成 venv exe exists、复制前消失 | blocked | delete before bin copy | 最终 FAIL，无成功标记 | A-PY-003 |
| M-07b | pyvenv relocatable=true | blocked | none | VENV_RELOCATABLE | A-PY-004 |
| M-07c | pyproject.toml 缺失且存在 .broken-* | blocked | none | HERMES_SOURCE_TREE_MISSING，备份保留，无 git clone | A-PY-005 |
| M-08 | 继承 `UV_NO_INSTALL_PROJECT=1` / `UV_NO_SYNC=1` / 恶意 `UV_CONFIG_FILE` | blocked | env injection | allowlist + `--no-config` 使其失效，CLI 仍生成；对照组可复现 exit=0 无 CLI | A-ENV-001 |
| M-08b（PHASE 2） | node-deps 退出码 0 但没有 node_modules | blocked | delete node_modules before npm ls | NODE_SMOKE_FAILED | A-NODE-001（PHASE 2） |
| M-09 | User skill 同路径同内容但 owner 不明 | blocked | unknown ownership | BLOCK，0 用户变化；code=`OWNERSHIP_UNKNOWN` | §15；不是 A-OWN-002 |
| M-10 | User skill drift | blocked | edit skill before upgrade | BLOCK & PRESERVE | A-OWN-002 |
| M-11 | `%LOCALAPPDATA%` 目标 junction 指向外部 | blocked | reparse escape | BLOCK，outside writes=0 | A-SEC-002 |
| M-12 | SYSTEM 身份 | blocked | run under SYSTEM | INSTALL_CONTEXT_UNSUPPORTED | A-ENV-002 |
| M-13 | C: 低于 4GB（4294967296） | blocked | set disk fixture | DISK_SPACE_INSUFFICIENT | A-ENV-002（PHASE 2） |
| M-14 | 既有恶意 UV_NO_INSTALL_PROJECT | blocked | env injection | 环境无效化，CLI PASS | A-ENV-001 |
| M-15 | Browser Use、CUA、`node_modules` 均缺失 | blocked | optional absent | Phase 1 PASS；上游 `install.ps1`、npm、npx、node、`git clone`、`uv tool install browser-use` 的调用计数全为 0 | A-ENV-001, A-PY-001 |
| M-16 | Python 安装中断 | blocked | kill uv child | rollback or RECOVERY_REQUIRED | A-TXN-001,A-TXN-002 |
| M-17 | Windows Installer 安装后事务失败 | blocked | inject at finalize | 不保留 COMMITTED | A-TXN-001 |
| M-18 | 网络拦截失败连接 | blocked | inject outbound attempt | OFFLINE_EGRESS_DETECTED | A-SEC-001 |
| M-19 | 空目录/重复路径/大小写冲突 | blocked | invalid manifest | BUNDLE_INTEGRITY_FAILED | A-BUNDLE-002 |
| M-20 | Golden Consumer 真实桌面端 | blocked during install | none | 本地 Runtime Probe PASS | A-CI-002 |

# 22. Negative Acceptance

所有 MUST NOT 映射。**Phase 1 Required 是 NEG-001、NEG-002、NEG-003、NEG-009、NEG-013、NEG-014、NEG-015**；其余 NEG 行引用的 AC 已标 `PHASE 2`，本版不取证，**MUST NOT** 据此触发 §0.3 的 `SPEC_SEMANTIC_GAP`。

| Negative Test | Forbidden Behavior | Error / Oracle | Refs |
|---|---|---|---|
| NEG-001 | 构建使用 floating main 而非固定 SHA | `SOURCE_REF_MISMATCH` + dist new MSI=0 | A-SRC-001 |
| NEG-002 | `uv sync` exit 0 但无 CLI 时仍继续写成功标记 | `HERMES_CLI_MISSING_POST_SYNC`；后续阶段执行次数=0 | A-PY-002 |
| NEG-003 | 终端调用上游 `install.ps1` / npm / npx / node / `git clone` / Browser Use / CUA | `Initialize-Hermes.ps1` 静态扫描匹配数=0；运行时这些进程创建数=0 | A-ENV-001, A-PY-001 |
| NEG-004 | 安装期网络访问（包括被拦截） | attempted connection count=0 | A-SEC-001 |
| NEG-005 | 覆盖已存在用户配置/Skills | user-owned pre/post digest identical | A-OWN-001,A-OWN-002 |
| NEG-006 | SYSTEM 或机器级 PATH 写入 | registry Machine PATH digest identical | A-ENV-002 |
| NEG-007 | MSI 1603 时仍有成功 Receipt | receipt status != COMMITTED | A-TXN-001 |
| NEG-008 | rollback 失败删除恢复备份 | recovery retained=true | A-TXN-002 |
| NEG-009 | 缓存篡改仍同步 | uv invocation count=0 | A-BUNDLE-002 |
| NEG-010 | Support ZIP 泄露假 API Key | marker count=0 | A-OBS-002 |
| NEG-011 | SKIPPED/BLOCKED Required AC 放行 | release exit !=0 | A-CI-001 |
| NEG-012 | MSI 路径穿越外部写 | outside writes=0 | A-SEC-002 |
| NEG-013 | 把构建期 venv 或 `node_modules` 打进 payload | payload 中 `hermes-agent\venv` 与任意 `node_modules` 的数量=0 | A-BUILD-001, A-BUILD-002 |
| NEG-014 | 不做离线重建证明就打包 | `offlineProof` 缺失或任一步非 0 时 dist 新 MSI 数=0 | A-BUILD-001 |
| NEG-015 | 继承 `UV_*` 或用户 `uv.toml` 改变受管同步行为 | 注入后 `venv\Scripts\hermes.exe` 仍生成；uv 命令行含 `--no-config` | A-ENV-001 |

# 23. Failure Injection

**Phase 1 要执行的注入点**是引用 A-BUNDLE-002、A-PY-002、A-PY-004、A-PY-005、A-ENV-001 的那五行，外加 A-OBS-003 复用其中任一行验证日志落盘。其余行引用 T0 快照、`COMMITTED`、recovery 目录或网络 Oracle，均属 `PHASE 2`，本版不执行，**MUST NOT** 据此触发 §0.3 的 `SPEC_SEMANTIC_GAP`。

| Point | Injection | Required Postcondition | Error | AC |
|---|---|---|---|---|
| before uv（Phase 1） | 设置 `UV_NO_INSTALL_PROJECT=1` / `UV_NO_SYNC=1` / 恶意 `UV_CONFIG_FILE` / `VIRTUAL_ENV` | allowlist + `--no-config` 使注入失效，`venv\Scripts\hermes.exe` 仍生成 | 无（正例）；对照组须复现 `HERMES_CLI_MISSING_POST_SYNC` | A-ENV-001 |
| build time（Phase 1） | 从 uv 缓存移除一个必需 wheel | 离线重建失败，不产出 MSI | `OFFLINE_REBUILD_FAILED` | A-BUILD-001 |
|---|---|---|---|---|
| before first write | manifest mismatch | no uv/node invocations；仅诊断 | BUNDLE_INTEGRITY_FAILED | A-BUNDLE-002 |
| after first runtime file write | kill uv child | staging 回滚，managed digest==T0 | UV_SYNC_FAILED / INSTALL_ROLLED_BACK | A-TXN-001 |
| after Nth dependency write | remove npm cached package | no committed receipt, rollback or recovery | NODE_CORE_INSTALL_FAILED | A-NODE-003,A-TXN-001 |
| after uv exit before bin copy | remove venv\Scripts\hermes.exe | npm 不启动、错误立即给出 | HERMES_CLI_MISSING_POST_SYNC | A-PY-002 |
| after venv --version before bin copy | pyvenv relocatable=true | 不复制为成功、不改写 .cmd | VENV_RELOCATABLE | A-PY-004 |
| before uv | delete pyproject.toml, leave .broken-* | 不恢复、不删除备份、不 git clone | HERMES_SOURCE_TREE_MISSING | A-PY-005 |
| before receipt | crash initializer | 没有 COMMITTED、managed digest=T0 | INSTALL_ROLLED_BACK | A-TXN-001 |
| after temporary receipt | fail MSI finalization | Receipt 不得被 Desktop 判为成功 | INSTALL_ROLLED_BACK | A-TXN-001 |
| during verify | CLI --version exit !=0 | Node 不开始，保留 stderr | HERMES_CLI_VERIFY_FAILED | A-PY-001,A-PY-002 |
| during rollback | ACL deny recovery write | RECOVERY_REQUIRED，备份保留 | ROLLBACK_INCOMPLETE | A-TXN-002 |
| during network denied | dummy optional download attempt | 网络事件记录并阻断 Release | OFFLINE_EGRESS_DETECTED | A-SEC-001 |

# 24. Evidence Contract

## 24.1 Evidence schema

每个 **Phase 1 Required** 的 `A-*`（§27 中 `Phase 1 Gate = REQUIRED` 的 13 项）必须生成 `evidence/<A-ID>.json`。`PHASE 2` 的 AC 本版不产生 Evidence，其缺失不构成 Phase 1 的 `BLOCKED`（§27 映射规则）。Schema 至少包含：

```json
{
  "schemaVersion": 1,
  "acceptanceId": "A-PY-002",
  "status": "PASS",
  "requirementIds": ["REQ-PY-001"],
  "testIds": ["TEST-A-PY-002"],
  "command": "<test entrypoint + parameters>",
  "exitCode": 0,
  "oracle": {"type": "error_and_stage_count", "expected": {"error":"HERMES_CLI_MISSING_POST_SYNC","nodeCount":0}, "actual": {"error":"<observed>","nodeCount":0}},
  "evidenceFiles": ["uv-sync.log", "events.jsonl"],
  "repoCommit": "<current builder sha>",
  "sourceCommit": "<fixed Hermes sha>",
  "msiSha256": "<real artifact hash>",
  "toolVersions": {"wix":"5.0.2", "uv":"<real>", "node":"<real>"},
  "timestampUtc": "<real ISO8601 time>"
}
```

以上为字段示意，真实 Evidence 必须由测试运行生成，不能用示例值表示已通过；Oracle 的 `expected` / `actual` 必须为类型正确、与 test 对应的机器可比对值。

## 24.2 Evidence integrity

- Required：Builder HEAD、Hermes source SHA、MSI SHA256、Windows build、安装身份、网络隔离配置/观察方法、真实日志、测试命令、退出码、工具版本、UTC 时间。
- 安装日志、用户状态快照使用用户路径脱敏副本；失败分支证据保留原始错误和诊断编码。
- 证据保留：CI release evidence >=90 天，终端失败诊断默认 >=30 天；清理不得删除 `RECOVERY_REQUIRED` 的恢复资产。

# 25. Release Gate

> **§25 是发布门槛，不是计划批准门槛。** 计划批准（`status -> APPROVED_FOR_PLAN`）的唯一条件在 §28.1，不要求本节任何一项为 PASS。

- 状态：`PASS/FAIL/SKIPPED/BLOCKED`。`NOT_RUN` 在执行状态汇总中按 `BLOCKED` 处理。
- Phase 1 发布门槛是 §27 中 `Phase 1 Gate = REQUIRED` 的 13 项 AC（= §34.2 点名的集合），其中 11 项可在构建机或开发机取证，只有 A-PY-001 与 A-OBS-003 需要真实无网安装。§20 里其余 AC 标 `PHASE 2`，不是 Phase 1 Required。
- 全文后续阶段仍要求其 AC 全部 PASS 才能做完整 Release。任意已纳入当前阶段门槛的 AC `!=PASS` => `RELEASE_GATE_FAILED`。
- Release PASS 必须具备：固定源码 SHA、完整 manifest SHA、成功 Win10+Win11 离线安装、回滚/反例、网络尝试计数 0、真实 smc-copilot consumer、可下载 Evidence ZIP。
- 生产发布的身份信任：可信证书签名的 MSI 或组织批准的可信 SHA 发布链记录；不能仅由未签名 MSI 本身的自述 manifest 自我证明真实性。
- 在尚未执行测试时，Release Gate = `BLOCKED`。这与 `status` 字段无关：`APPROVED_FOR_PLAN` 只表示可以生成 `.plan.md`（§28.1），不表示任何 AC 已 PASS。

# 26. Golden Consumer / Real-world Acceptance

- Consumer：`smc-copilot` 桌面应用的本地 Hermes Runtime（客户端连接本机 Hermes Gateway/CLI）。
- 记录 Consumer repo URL、精确 HEAD、clean/dirty、测试账号的安装前/后 User-Owned digest、Bundle identity、`hermes --version`、Desktop Runtime Probe 输出、安装时网络观测。
- 先干净 Windows VM 安装，再执行真实 Desktop consumer smoke；禁止在 Consumer 非干净时无说明复用旧 venv；必须单列“冷安装”和“预存旧 venv 升级”测试。
- 如果无法取得真实 Consumer 测试环境，`A-CI-002=BLOCKED`，不能由合成 fixture 替代发布验收。

# 27. Requirement Traceability Matrix

`Phase 1 Gate` 列是本版唯一生效的发布门槛判定。标 `PHASE 2` 的 Requirement 其 normative 条款已在对应章节降级为后续阶段草稿，**不参与 Phase 1 的 Gate 计算**，也不触发下文的映射规则。

| Requirement | Phase 1 Gate | 取证位置 | Phase 1 Acceptance | Test | Evidence | Invariant | PHASE 2 顺延项 |
|---|---|---|---|---|---|---|---|
| REQ-BUILD-001 | REQUIRED | 构建机 | A-BUILD-001, A-BUILD-002 | TEST-A-BUILD-001, TEST-A-BUILD-002 | EVID-A-BUILD-001, EVID-A-BUILD-002 | INV-BUILD-001, INV-BUILD-002 | — |
| REQ-SRC-001 | REQUIRED | 构建机 | A-SRC-001, A-SRC-002 | TEST-A-SRC-001, TEST-A-SRC-002 | EVID-A-SRC-001, EVID-A-SRC-002 | INV-SRC-001, INV-SRC-002 | — |
| REQ-ENV-001 | REQUIRED | 构建机 | A-ENV-001 | TEST-A-ENV-001 | EVID-A-ENV-001 | INV-ENV-001 … INV-ENV-003 | A-ENV-002 |
| REQ-BUNDLE-001 | REQUIRED | 构建机 + 终端 | A-BUNDLE-001, A-BUNDLE-002 | TEST-A-BUNDLE-001, TEST-A-BUNDLE-002 | EVID-A-BUNDLE-001, EVID-A-BUNDLE-002 | INV-BUNDLE-001, INV-BUNDLE-002 | 全量 `payloadTreeDigest` |
| REQ-PY-001 | REQUIRED | 终端（A-PY-001）+ 注入夹具 | A-PY-001 … A-PY-005 | TEST-A-PY-001 … TEST-A-PY-005 | EVID-A-PY-001 … EVID-A-PY-005 | INV-PY-001, INV-PY-002 | — |
| REQ-OBS-001 | REQUIRED | 终端 | A-OBS-003 | TEST-A-OBS-003 | EVID-A-OBS-003 | INV-OBS-001, INV-OBS-002 | A-OBS-001, A-OBS-002 |
| REQ-NODE-001 | PHASE 2 | — | 无（Phase 1 为纯禁止类约束，由 A-ENV-001 的静态断言覆盖） | — | — | INV-NODE-001, INV-NODE-002 | A-NODE-001, A-NODE-002, A-NODE-003 |
| REQ-OWN-001 | PHASE 2 | — | 无（`.broken-*` 不被删除由 A-PY-005 覆盖） | — | — | INV-OWN-001, INV-OWN-002 | A-OWN-001, A-OWN-002 |
| REQ-TXN-001 | PHASE 2 | — | 无（失败路径由 A-PY-002 … A-PY-005 覆盖） | — | — | INV-TXN-001, INV-TXN-002 | A-TXN-001, A-TXN-002 |
| REQ-SEC-001 | PHASE 2 | — | 无（执行图无联网命令由 A-ENV-001 静态断言覆盖） | — | — | INV-SEC-001, INV-SEC-002 | A-SEC-001, A-SEC-002 |
| REQ-CI-001 | PHASE 2 | — | 无 | — | — | INV-CI-001, INV-CI-002 | A-CI-001, A-CI-002 |

映射规则（**仅作用于 `Phase 1 Gate = REQUIRED` 的行**）：任何 Phase 1 `MUST` 无 AC、任何 Phase 1 AC 无 Test、任何 Test 无 Oracle、任何 Phase 1 Required AC 无真实 Evidence => 对应 Gate `BLOCKED`。`PHASE 2` 行缺 AC / Test / Evidence **不构成** Phase 1 的 `BLOCKED`。

**取证位置分布**：13 项 Phase 1 Required 中，A-BUILD-001/002、A-SRC-001/002、A-ENV-001、A-BUNDLE-001/002 共 7 项在**构建机**上产生 Evidence；A-PY-002 至 A-PY-005 是注入夹具，可在构建机或任意一台开发机上跑；只有 A-PY-001 与 A-OBS-003 需要一次真实的无网 per-user 安装。这是把「离线可行性」前移到构建期（REQ-BUILD-001）的直接收益。

REQ-SEC-001、REQ-CI-001 在 Phase 1 内仍有生效的 `MUST NOT`（不得 `irm|iex`、不得把 `NOT_RUN` 当 PASS）。这些是**禁止类约束**，Phase 1 通过 A-ENV-001 的静态断言与「不新增相应代码路径」满足，动态取证由 §22 的 NEG-004、NEG-011 在后续阶段完成。

# 28. Plan Generation Contract

仅当 `status=APPROVED_FOR_PLAN` 才生成 `.plan.md`。Phase 1 计划只允许覆盖 §4.4 与 §34.2 点名的 13 项 AC。标注为 `PHASE 2` / 非 normative 的后续阶段草稿（§7 的 PHASE 2 行、§9.2、§11 的 PHASE 2 行、§12.2、§12.3、§15、§16.2、§16.3、§19 末段、§22 的非 Phase 1 行、§23 的非 Phase 1 注入点、§24.1 的非 Required AC）不是实施口径。Phase 1 的副作用、失败码和 Oracle 以 §4.4 为准。若实际 MSI 行为与本文不符，应先更新 PRD。

## 28.1 Plan 批准准入条件（`REVIEW -> APPROVED_FOR_PLAN`）

**本节是 `status` 字段唯一的翻转条件，与 §35 的 Definition of Done 是两件事。** §35 是**发布**准入（必须有真实 Evidence、真机安装通过），§28.1 是**计划**准入（只要求文档自洽 + 事实已核）。把 §35 当作计划准入会造成「要批准才能实施、要实施完才能批准」的循环，本节即为消解该循环而设。

下列 `G-*` 全部满足时，评审人（Architecture + Windows Installer + QA 各一人）方可将 Front Matter 的 `status` 改为 `APPROVED_FOR_PLAN`。本节**不要求**任何测试已执行、任何 Evidence 已产生、任何 AC 已 PASS——那些是 §25 / §35 的发布门槛。**本节也不包含任何需要真实终端的前置项**：凡是「不实测就不知道」的问题，都已经通过改口径消除或已在开发机取证完毕（见 §4.5）。

| ID | 准入条件 | 判定方式 | 状态 |
|---|---|---|---|
| G-01 | §4.4 的 14 条与 §34.2 的 Phase 1 清单逐条一致，无互相矛盾 | 人工逐条对读 | **PASS**（2026-10-09 对读；一处 Chromium 口径措辞已就地修正） |
| G-02 | §20 中标 `Phase 1 Required` 的 13 项 AC，每一项都在 §34.1 有明确的实现文件归属 | 人工核对 §20 与 §34.1 | **PASS**（2026-10-09；13/13 均有归属，见下） |
| G-03 | §27 中 `Phase 1 Gate = REQUIRED` 的每一行都有 Acceptance、Test、Evidence 三列非空 | 读 §27 表 | **PASS**（2026-10-09；6 行 REQUIRED 全部三列非空） |
| G-04 | 与 Phase 1 冲突的后续阶段草稿段落均已标注为非 normative 且声明不触发 §0.3 | 检查 §7、§9.2、§11、§12.2、§12.3、§15、§16.2、§16.3、§19、§22、§23、§24.1 | **PASS**（2026-10-09；各段均有显式降级标注） |
| G-05 | §8 状态机、§14.2 Commit Order 与 `installer/Package.wxs` 的 `InstallExecuteSequence` 三者顺序一致 | 对读三处 | **PASS**（2026-10-09；均为 `InstallFiles -> Preflight -> Initialize`） |
| G-06 | 终端执行图中不存在上游 `install.ps1`、node/npm/npx、`git clone`、联网命令；§4.4 第 2 条与 §34.1 对 `Initialize-Hermes.ps1` 的改动要求一致 | 读 §4.4 第 2 条、REQ-NODE-001、§34.1 | **PASS**（2026-10-09；§34.1 要求删除 Node 段与 `Restore-HermesAgentFromBrokenBackup`，`validate_project.py` 负责静态断言） |
| G-07 | Phase 1 不存在依赖未观测 Windows Installer 行为的设计点；失败路径全部是「确定性失败 + 明确人工指令」 | 读 §4.4 第 3 条、第 7 条 | **PASS**（2026-10-09；第 7 条已显式声明不对 MSI 修复行为作断言） |
| G-08 | 锁定版本号在全文的出现位置与 `build-config.json` 的 `source.expectedVersion` 一致 | 见 §28.2 | **PASS**（2026-10-09；全文字面量均为 `0.21.0`，与 `expectedVersion` 一致，且 §28.2 已声明派生关系） |
| G-09 | 每项 Phase 1 Required AC 在 §27 标明了取证位置，且需要真实终端的不超过 2 项 | 读 §27 的「取证位置」列 | **PASS**（2026-10-09；仅 A-PY-001 与 A-OBS-003 需真实终端） |

**G-02 归属明细**（13/13）：A-BUILD-001/002 → `build/Prepare-OfflineDependencies.ps1` + `build/Build.ps1` + `tests/Test-BuildOfflineProof.ps1`；A-SRC-001/002 → `build/Prepare-Source.ps1` + `build-config.json`；A-BUNDLE-001/002 → `build/Generate-Manifest.ps1` + `scripts/Preflight-HermesInstall.ps1` + `tests/Test-BundleIntegrity.ps1`；A-PY-001…005 → `scripts/Initialize-Hermes.ps1` + `scripts/Verify-Installation.ps1` + `tests/Test-PythonOfflineInstall.ps1`；A-ENV-001 → `scripts/Initialize-Hermes.ps1` + `tests/validate_project.py` + `tests/Test-UvEnvIsolation.ps1`；A-OBS-003 → `scripts/Initialize-Hermes.ps1`（`Stop-Transcript` 移入 `finally`）+ `tests/Test-PythonOfflineInstall.ps1`。

**已在 2026-10-08 于开发机闭合的事实**（无需再测，记录在 §4.5）：两处 `hermes.exe --version` 退出码均为 0、第一行 `Hermes Agent v0.21.0 (2026.8.31)`；`npm.cmd ls --offline --depth=0` 退出码 0；当前 venv 非 relocatable 且 console script 内嵌绝对路径 shebang；`uv venv --relocatable` 产出的 shebang 为相对 `#!python.exe`。

**评审结论（2026-10-09）**：G-01 … G-09 全部 PASS。按本节约定，`status` 可翻转为 `APPROVED_FOR_PLAN`。翻转后允许生成 `.plan.md`，其范围受 §28 第一段约束（仅 §4.4 与 §34.2 点名的 13 项 AC）。

**已在 2026-10-08 于开发机闭合的事实**（无需再测，记录在 §4.5）：两处 `hermes.exe --version` 退出码均为 0、第一行 `Hermes Agent v0.21.0 (2026.8.31)`；`npm.cmd ls --offline --depth=0` 退出码 0；当前 venv 非 relocatable 且 console script 内嵌绝对路径 shebang；`uv venv --relocatable` 产出的 shebang 为相对 `#!python.exe`。

## 28.2 版本号派生规则

Phase 1 的锁定版本号**派生自** `build-config.json` 的 `source.expectedVersion`（当前 `0.21.0`），不是 PRD 的独立常量。`build/Prepare-Source.ps1` 已在构建期比对源码 `pyproject.toml` 的 version 与该字段并在不等时中止，这是该派生关系的执行保障。

全文出现字面量 `0.21.0` 的位置（§4.4 第 5 条、§20 的 A-PY-001 与 A-CI-002、§32、§35、§36 第 2 条）**MUST** 理解为「当前 `source.expectedVersion` 的值」。升版时这些位置 **MUST** 同步更新，否则 `G-08` 不通过。版本匹配正则为 `^Hermes Agent v<expectedVersion> \(`——注意它要求 stdout 第一行**必须含左括号**，若上游未来去掉括号内的构建日期，该正则会失配，届时 **MUST** 先改 PRD。

# 29. `.plan.md` 输出标准

实施 Plan 的每个 Todo **必须**具有：

```yaml
id: PLAN-HB-001
requirement_refs: ["REQ-PY-001"]
acceptance_refs: ["A-PY-001", "A-PY-002", "A-PY-003"]
files_or_symbols: ["scripts/Initialize-Hermes.ps1", "tests/Test-PythonOfflineInstall.ps1"]
implementation_goal: "uv 后立即 CLI smoke，并输出独立诊断/失败码"
preconditions: ["REQ-BUNDLE-001 PASS", "已确定目标 venv ownership"]
state_transition: "PYTHON_SYNC -> PYTHON_VERIFIED | FAILING"
side_effect_scope: "managed venv staging + diagnostics only"
failure_cases: ["UV_SYNC_FAILED", "HERMES_CLI_MISSING_POST_SYNC", "HERMES_CLI_VERIFY_FAILED"]
verification: ["TEST-A-PY-001", "TEST-A-PY-002", "TEST-A-PY-003"]
status: planned
evidence: []
```

`implemented=代码完成`，`verified=执行对应 AC 并产生合格 Evidence`；禁止等同。

# 30. Code Review Contract

按顺序 Review：需求覆盖 → 状态 authority → mutation 越界 → failure 路径 → AC 实现 → Evidence 真实性 → edge cases → 代码质量。Phase 1 的审查必须核实 `InstallExecuteSequence` 的实际顺序（`InstallFiles` → `PreflightHermes` → `InitializeHermes`）、失败时 `%TEMP%` 日志是否真的落盘，以及子进程 stdout/stderr 的归属；不能只检查 PowerShell 语法。ownership ledger 与 rollback CA 的审查项属 PHASE 2。

# 31. PRD Quality Gate

| Gate | 本文状态 | 判定依据 |
|---|---|---|
| Architecture | SPECIFIED | 唯一 Goal、Scope 与边界 §2—6 |
| State | SPECIFIED | SOT/机器状态/合法转移 §7—9 |
| Semantics | SPECIFIED | 默认/owner/hash/冲突 §10—17 |
| Side Effects | SPECIFIED | §11、§12 |
| Failure | SPECIFIED | §14、§22—23 |
| Acceptance | SPECIFIED（未执行） | §20 共 25 项 AC，其中 Phase 1 Required 13 项（§27），仅 2 项需真实终端 |
| Evidence | SCHEMA_DEFINED（无真实 PASS） | §24/27 |
| Fact Verification | 0 项 NOT_RUN | 原 `VERIFY-01` 已于 2026-10-08 在开发机实测闭合；原 `VERIFY-02` 已由 §4.4 第 3、7 条设计消除。见 §4.5 |
| Plan Readiness | APPROVED_FOR_PLAN（2026-10-09） | §28.1 的 G-01…G-09 全部 PASS，均为文档自洽项。允许生成 `.plan.md`，范围仅限 §4.4 与 §34.2 的 13 项 Phase 1 Required AC |

# 32. PRD 禁止写法

本项目禁止把“安装正常”“离线尽量成功”“失败时合理恢复”“兼容性良好”写成验收项。Phase 1 的可判定结果是：构建期离线重建产出 `venv\Scripts\hermes.exe` 且 `--version` 退出码 0；8 个关键文件哈希一致；终端两次 `--version` 退出码 0 且第一行匹配 `^Hermes Agent v0.21.0 \(`（版本号派生见 §28.2）；终端 `install.ps1`/npm/npx/node/`git clone` 调用计数为 0；注入 `UV_*` 后仍产出 CLI；失败时 `msiexec` 非 0 且 `%TEMP%\hermes-msi-initialize.log` 中错误码非空。

# 33. 推荐 ID 体系（本项目固定）

Requirement：`REQ-SRC-001`, `REQ-PY-001`, `REQ-NODE-001`, `REQ-ENV-001`, `REQ-BUNDLE-001`, `REQ-OWN-001`, `REQ-TXN-001`, `REQ-OBS-001`, `REQ-SEC-001`, `REQ-CI-001`。Invariant：`INV-<domain>-xxx`。Acceptance：`A-<domain>-xxx`。Test：`TEST-A-<domain>-xxx`。Evidence：`EVID-A-<domain>-xxx`。新需求必须新建唯一 ID，不得复用已发布 ID 表达不同语义。

# 34. PRD 最小完整结构核对与文件改造清单

## 34.1 文件级实施清单（MODIFY / ADD）

| 路径 | 类型 | 主要改动 | Refs |
|---|---|---|---|
| `build-config.json` | MODIFY | 固定 source ref + Core offline policy/schema/最低剩余空间 | REQ-SRC-001,REQ-ENV-001 |
| `build/Prepare-Source.ps1` | MODIFY | Release 不自动 `git pull --ff-only`；改为校验 `HEAD == source.ref` 并要求工作树与子模块 clean，不等则 `SOURCE_REF_MISMATCH` / `SOURCE_DIRTY`。**现有「必须在 `defaultBranch` 分支上」的校验（`git branch --show-current` 与 `source.defaultBranch` 比较）与 pinned SHA 的 detached HEAD 互斥，Release 模式 MUST 移除该校验**；`-DevelopmentMode` 下保留旧行为并给产物标 `unreleasable`。保留现有 `expectedVersion` 与源码 `pyproject.toml` version 的比对（§28.2 的执行保障） | REQ-SRC-001 / A-SRC-001, A-SRC-002 |
| `build/Prepare-OfflineDependencies.ps1` | MODIFY | 现有离线断言（删 venv 后 `uv sync --offline --locked` 产出 `hermes.exe` 并跑 `--version`；`npm_config_offline=true` 下 `node-deps` 产出 `node_modules`；Chromium 落在 `payload\playwright`）**升格为正式 Build Gate**：给离线那次 `uv sync` 补 `--no-config`，为每步记录命令/退出码/UTC 时间，输出到 `build-info.json` 的 `offlineProof`。继续在打包前删除构建期 venv 与 `node_modules` | REQ-BUILD-001 / A-BUILD-001, A-BUILD-002 |
| `build/Generate-Manifest.ps1` | MODIFY | `$keyFiles` 维持现有 8 项不变；把现有 `if (Test-Path $full) { ... }` 的静默跳过改为**缺失即 throw `BUILD_PROVENANCE_MISSING`**，保证 manifest 的 `hashes` 恒含全部 8 条。不升 schema v2，不算全量树摘要 | REQ-BUNDLE-001 / A-BUNDLE-001 |
| `build/Build.ps1` | MODIFY | 发布身份仍是 MSI 字节 SHA256；新增把 `offlineProof` 写入 `dist/build-info.json`，Build Gate 任一步失败即 exit!=0 且不产出 MSI | REQ-SRC-001, REQ-BUILD-001 |
| `scripts/Preflight-HermesInstall.ps1` | MODIFY | 最低空闲空间维持 4GB（4294967296），不改为 8GiB。**新增 §4.4 第 8 条的 8 个路径 SHA256 核对**：读 `[HermesRoot]\runtime-manifest.json` 的 `hashes`，8 条有任一缺条目、文件缺失或哈希不等即以 `BUNDLE_INTEGRITY_FAILED` 非 0 退出。本动作序列在 `InstallFiles` 之后、`InitializeHermes` 之前，是 A-BUNDLE-001/002 的 Endpoint 实现归属 | REQ-BUNDLE-001 / A-BUNDLE-001, A-BUNDLE-002 |
| `scripts/Initialize-Hermes.ps1` | MODIFY（本版核心改动） | ①**删除整个 Node 段**（第 180–212 行调用上游 `install.ps1 -Stage node-deps` 的块）与相关 npm 环境变量设置——该脚本的 `Install-Repository` 会把源码树改名为 `.broken-*` 并 `git clone`；②**删除 `Restore-HermesAgentFromBrokenBackup` 函数及其调用**（第 32–83、106 行）；③`uv sync` 补 `--no-config` 并改为 allowlist 环境启动（§4.4 第 13 条）；④uv 后两处 `--version` 并复制 `bin\hermes.exe`；⑤`relocatable=true` 与缺 `pyproject.toml` 直接失败，后者附「卸载后重装」指令；⑥不写 `COMMITTED`；⑦**保证失败路径日志落盘**：现有 `Start-Transcript` 对应的 `Stop-Transcript` 在脚本尾部、不在 `try/finally` 内，`throw` 会跳过它，必须改为 `finally` 并在抛出前显式写入 §4.4 错误码 | REQ-PY-001, REQ-ENV-001, REQ-NODE-001, REQ-OBS-001 / A-PY-001…005, A-ENV-001, A-OBS-003 |
| `scripts/Install-CoreNodeOffline.ps1` | 不新增 | 本版没有 Endpoint npm 安装器 | REQ-NODE-001 |
| `scripts/Install-EnterpriseSkills.ps1` | 不改 | 本版不实现所有权账本 | REQ-OWN-001 |
| `scripts/Cleanup-Hermes.ps1` | 不改 | 不按新账本删除文件 | REQ-OWN-001 |
| `scripts/Rollback-HermesInstall.ps1` | 不新增 | 回滚只用现有 MSI 事务 | REQ-TXN-001 |
| `scripts/Repair-Hermes.ps1` | 不改 | 不增加 RecoverOperationId 账本流程 | REQ-TXN-001 |
| `scripts/Verify-Installation.ps1` | MODIFY | 现实现只检查并运行 `hermes-agent\venv\Scripts\hermes.exe`，**缺 `bin\hermes.exe`**，与 §4.4 第 5 条的两处 `--version` 不符。补上 `bin\hermes.exe` 的存在性与 `--version` 校验，并按 §28.2 的正则比对 stdout 第一行。不读 `COMMITTED` | REQ-PY-001 / A-PY-001 |
| `scripts/Collect-HermesInstallDiagnostics.ps1` | 不新增 | 诊断只用 %TEMP% 的两个日志 | REQ-OBS-001 |
| `installer/Package.wxs` | 不改事务形状 | 保持现有 deferred Preflight/Initialize、Return=check。不嵌入 payload-index，不加 EarlyPreflight、T0 或 Commit Custom Action | REQ-TXN-001 |
| `.github/workflows/build-msi.yml` | MODIFY | 发布 artifact；构建 job 内执行 A-BUILD-001/002、A-SRC-001/002、A-ENV-001、A-BUNDLE-001/002 并产出阻断式 Evidence；Windows 真机/VM Gate 只承载 A-PY-001 与 A-OBS-003 | REQ-CI-001 |
| `tests/validate_project.py` | MODIFY | 断言 `Generate-Manifest.ps1` 的 `$keyFiles` 恰为 §4.4 第 8 条的 8 项；**断言 `scripts/Initialize-Hermes.ps1` 不含 `install.ps1`、`npm`、`npx`、`node`、`git clone`、`Invoke-RestMethod`、`Invoke-WebRequest`、`iwr`、`irm`、`Restore-HermesAgentFromBrokenBackup`，且 `uv sync` 参数含 `--no-config`**（A-ENV-001 的静态半部）；source/manifest contract 静态断言 | REQ-SRC-001, REQ-BUNDLE-001, REQ-ENV-001, REQ-NODE-001 |
| `tests/Test-BuildOfflineProof.ps1` | ADD | A-BUILD-001/002：校验 `build-info.json` 的 `offlineProof` 各步退出码为 0；断言 payload 内不存在 `hermes-agent\venv` 与任何 `node_modules`；断言 `payload\playwright` 下有 `chrome.exe` 或 `headless_shell.exe` | REQ-BUILD-001 |
| `tests/Test-UvEnvIsolation.ps1` | ADD | A-ENV-001 的动态半部：注入 `UV_NO_INSTALL_PROJECT` / `UV_NO_SYNC` / `UV_CONFIG_FILE` / `VIRTUAL_ENV` 后跑受管 `uv sync`，断言仍产出 `venv\Scripts\hermes.exe`；并跑对照组确认不加防御时可复现「exit=0 但无 CLI」 | REQ-ENV-001, REQ-PY-001 |
| `tests/Test-PythonOfflineInstall.ps1` | ADD | Python 正反例 + after-uv checks（A-PY-001…005）；并覆盖 A-OBS-003（失败注入后断言 `%TEMP%\hermes-msi-initialize.log` 存在且错误码非空） | REQ-PY-001, REQ-OBS-001 |
| `tests/Test-BundleIntegrity.ps1` | ADD | A-BUNDLE-001/002：8 个路径齐备时 Preflight 退出 0；篡改任一字节时退出非 0、错误码 `BUNDLE_INTEGRITY_FAILED`、`uv` 调用计数 0 | REQ-BUNDLE-001 |
| `tests/Test-CoreNodeOffline.ps1` | 不新增（PHASE 2） | 终端 Node 整体顺延。届时必须用随包 `npm.cmd` 直接安装，不得经由上游 `install.ps1` | REQ-NODE-001（PHASE 2） |
| `tests/Test-InstallRollback.ps1` | 不新增 | 失败路径由 MSI `Return=check` 覆盖 | REQ-TXN-001 |
| `tests/Test-OfflineNetwork.ps1` | 不新增（PHASE 2） | 网络 Oracle 在 Phase 1 只有定义、不取证（§4.4 第 10 条）。该测试与 A-NODE-001 的交集须先在 PHASE 2 用一条合并 AC 消解 | REQ-SEC-001（PHASE 2） |
| `tests/Test-OwnershipMigration.ps1` | 不新增 | 本版不实现所有权账本 | REQ-OWN-001 |
| `docs/ARCHITECTURE.md`, `README.md` | MODIFY | WiX 5、Core 离线定义、问题诊断、网络边界 | REQ-OBS-001,REQ-SEC-001 |

Phase 1 不要求把 `Install-CoreNodeOffline.ps1` 或 `Rollback-HermesInstall.ps1` 打进 MSI。这两份脚本本版不新增。

## 34.2 分阶段交付顺序（不是 `.plan.md`）

- **Phase 1（已于 2026-10-09 批准为 `APPROVED_FOR_PLAN`）**：§4.4 的 14 条。
  - **构建期**：固定 source SHA；填充缓存后删 venv 再 `uv sync --offline --locked --no-config` 重建并跑通 `--version`；离线 `node-deps` 证明 npm 缓存自足；Chromium 落盘；打包前删除构建期 venv 与 `node_modules`；生成含 8 条哈希的 manifest（任一缺失即构建失败）；把 `offlineProof` 写进 `build-info.json`。
  - **终端**：`InstallFiles` → Preflight 核 8 个哈希 → allowlist 环境下 `uv sync --offline --locked --no-config` → `venv\Scripts\hermes.exe --version` → 复制 `bin\hermes.exe` → `bin\hermes.exe --version`。`relocatable=true` 失败；缺 `pyproject.toml` 失败并给出重装指令，不恢复、不删除 `.broken-*`、不 `git clone`、不依赖 MSI 修复；**全程不调用上游 `install.ps1`，不跑 node/npm/npx**；日志只在 `%TEMP%` 且失败时错误码非空；不写 `COMMITTED`。
  - 对应 13 项 Required AC：A-BUILD-001、A-BUILD-002、A-SRC-001、A-SRC-002、A-BUNDLE-001、A-BUNDLE-002、A-PY-001 至 A-PY-005、A-ENV-001、A-OBS-003。
- **本版不实施**：终端 Node / Browser Use / CUA / Chromium 安装、全量文件树摘要、8GiB、T0 字节快照、Commit Custom Action、所有权账本、SMC 诊断目录。
- **PHASE 2 的首要议题**：终端 Node 离线安装必须绕开上游 `install.ps1`，改用随包 `npm.cmd` 直接在 `hermes-agent` 下安装，并补一条同时覆盖 A-NODE-001 与 A-SEC-001 的合并 AC。

# 35. Definition of Done（**发布**准入，非计划准入）

> 本节是「可以发布」的条件，**不是**「可以生成 `.plan.md`」的条件。计划准入见 §28.1。两者分开，是为了消除「要批准才能实施、要实施完才能批准」的循环依赖。

## 35.1 Phase 1 发布 DoD

- [ ] §27 中 `Phase 1 Gate = REQUIRED` 的 13 项 AC 全部为 `PASS`，没有 `SKIPPED` / `BLOCKED` / `NOT_RUN`，且每项都有真实 Evidence。
- [ ] 构建期 Build Gate 全通过：离线 `uv sync` 重建出可运行 CLI；离线 `node-deps` 产出 `node_modules`；Chromium 已落盘；打包前构建期 venv 与 `node_modules` 均已删除；`build-info.json` 含完整 `offlineProof`。
- [ ] 终端两处 `hermes.exe --version` 退出码都为 0，且 stdout 第一行都匹配 `^Hermes Agent v<expectedVersion> \(`（§28.2）。
- [ ] 终端初始化期间 `install.ps1`、`npm`、`npx`、`node`、`git clone` 的调用次数均为 0；`.broken-*` 恢复调用次数为 0。
- [ ] 注入 `UV_NO_INSTALL_PROJECT` 等变量后 CLI 仍被生成（A-ENV-001），且对照组能复现「exit=0 但无 CLI」。
- [ ] §4.4 第 8 条的 8 个路径在 `runtime-manifest.json` 中齐备，且 Endpoint 实测哈希全部相等；任一被篡改时 `uv` 调用次数为 0。
- [ ] Windows 10 x64 与 Windows 11 x64 各完成一次无网冷安装。
- [ ] 任一 Phase 1 必需组件失效时安装 FAIL，且能从 `%TEMP%\hermes-msi-initialize.log` 读到具体命令 exit 与 §4.4 的错误码（A-OBS-003）。
- [ ] MSI 发布身份 = MSI 字节 SHA256，且与固定 source SHA 在 `build-info.json` 中绑定。
- [ ] 发布成功 `msiexec exit=0`；任一 Phase 1 Required AC 未 PASS 时 `release job exit!=0`。

## 35.2 PHASE 2 发布 DoD（本版不适用）

- [ ] 所有 `MUST/MUST NOT`（含 PHASE 2 条款）都有机器可判定 AC，并已产生真实 Evidence。
- [ ] 重复安装、旧环境升级成功；用户内容 digest 保持。
- [ ] 单 MSI 文件身份与 manifest 全量 `payloadTreeDigest` 一致。
- [ ] 失败回滚 managed scope 恢复 T0；回滚失败保留恢复目录并阻断重试。
- [ ] 所有 Negative Acceptance 与 Failure Injection 有 Evidence。
- [ ] Golden Consumer 为真实 smc-copilot 桌面端。

# 36. 最终原则

1. 同名 MSI 不构成同一制品身份；以 MSI SHA256 + pinned Git SHA 为事实源。
2. `uv sync` exit 0 不足以证明 CLI 可运行。Phase 1 必须在复制 `bin\hermes.exe` 前后各跑一次 `--version`，两次退出码为 0，且 stdout 第一行都匹配 `^Hermes Agent v0.21.0 \(`。
3. **终端绝不执行第三方安装脚本。** 上游 `install.ps1` 会把 MSI 释放的源码树改名为 `.broken-*` 并 `git clone`，它不属于「离线安全安装」。Phase 1 的终端只跑随包 `uv` 与 `hermes.exe`；Node / Browser Use / CUA / Chromium 顺延 PHASE 2，缺失不是失败。
4. **离线可行性在构建期证明，不在终端猜。** 构建机必须删掉 venv 后用 `--offline` 重建出可运行 CLI，并离线跑通 `node-deps`；这两件事任一不成立就不许打包。终端只负责「同一个包在真实 per-user 路径上重建后 CLI 可运行」。
5. **`uv sync` exit 0 不等于项目被安装。** `--no-config` 与 `UV_*` allowlist 是 Phase 1 Required，不可顺延：继承变量让 uv 跳过项目安装，会精确产生「exit 0 但没有 `hermes.exe`」的失败样本现象。
6. 离线 Oracle 的统计范围是 `InitializeHermes` 拉起的 powershell、uv、python、hermes.exe，连接尝试必须为 0；`msiexec`、CRL、OCSP、SmartScreen 不计入。Phase 1 用「执行图中不存在联网命令」的静态断言满足，动态取证留 PHASE 2。
7. **失败路径不得依赖未观测的 Windows Installer 行为。** 缺源码树就确定性失败并给出「卸载后重装」指令，不赌 MSI 修复会把文件写回来。
8. 诊断只写 `%TEMP%\hermes-msi-preflight.log` 和 `%TEMP%\hermes-msi-initialize.log`。不新增收集脚本。
9. 初始化失败由现有 MSI 事务回滚。不新增 rollback Custom Action，不复制 T0 字节快照，不写 `COMMITTED`。不删除 `hermes-agent.broken-*` 和无法证明归属的文件。
10. 成功与失败两台 Win10 的差异必须通过 immutable bundle 身份、实际运行时环境与 CLI 文件时间线验证，而不是凭单张截图推定。
11. 只有 Phase 1 Required 的 Requirement → Test → Oracle → Evidence → Release Gate 全部闭环，才允许宣称 Phase 1 工程改造完成。
12. 「可以生成计划」「可以发布」「工程改造完成」是三个不同的门：分别由 §28.1、§25、§35.1 判定。把它们混为一谈会产生无法退出的循环依赖，本文明确禁止。
13. **验收 Oracle 的取证位置是设计选择。** 能在构建机上证明的，不要推到终端；需要终端的，必须少到可以真的跑完。13 项 Phase 1 Required 中只有 2 项需要真实无网安装，这是本版的刻意结果。
