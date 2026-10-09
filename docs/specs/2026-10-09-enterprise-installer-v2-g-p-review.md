# Hermes Enterprise Installer v2 — Plan Approval Gate Review (G-P01…G-P08)

> Date: 2026-10-09. Target: `docs/prd/PRD-HERMES-ENTERPRISE-INSTALLER-V2.0.md` (front matter `status=APPROVED_FOR_PLAN`, `plan_approval=APPROVED`).
> Companion: `docs/specs/2026-10-09-enterprise-installer-v2-grill.md` (Q1–Q24).
> This file is the **review record path** required by §28.1. Named Reviewer: **SMC Copilot Hermes**.

## Verdict

**G-P01…G-P08 全部 PASS。允许 `status=APPROVED_FOR_PLAN`，允许生成正式 `.plan.md`。** 合同正文可审；本记录不表示安装器代码已改、不表示 Win10 Golden / R-08 / `A-CI-001` 已跑。Release Gate 仍为 `BLOCKED`。

1. **G-P06** — Ed25519 书面确认已由 `SMC Copilot Hermes` 签署；仓库 Actions Secret **名称**已在 `smc-copilot/hermes-builder` Settings → Secrets → Actions 可见（截图 2026-10-09）。Authenticode **已停用**（`NON-GOAL-007`）。Secret **值**不在本文件。
2. **G-P07** — schema 可执行 PASS；真机 Golden 仍属 R-08。
3. **G-P08** — 无文档双解，且本文件已具名签字。

工作流尚未消费该 Secret（`.github/workflows/build-msi.yml` 未引用）属于实施，不是本 Gate 条件。

## Gate walk

### G-P01 — MSI vs Bootstrap 职责（Windows Installer）→ PASS

| 检查 | 结果 |
|---|---|
| REQ-MSI-001 移除 Preflight/Initialize CA，MSI 不做 uv | 唯一 |
| INIT_TXN 独立；失败不 `msiexec /x` | §14.1 |
| N-001 禁止 MSI CA 跑 uv/init | 有 Oracle |
| 代码仍含 `InitializeHermes` | 允许：计划批准不要求实现已完成 |

Windows Installer 签 PASS（SMC Copilot Hermes / 2026-10-09）。

### G-P02 — Build DAG / 无自嵌（Build/Release）→ PASS

§6.2 / §13 顺序唯一：编译 Init EXE（本轮无 Authenticode）→ 冻结静态树 → runtime-manifest + Ed25519 → MSI → release-manifest（含 MSI SHA，不嵌回 MSI）→ Setup 内嵌该 MSI → Setup SHA 只写 `build-info.json`。N-013 禁止 Setup 自嵌。`uncompressedPayloadBytes` 与 runtime-manifest size 对账，对不上不得发布。`NON-GOAL-007`：缺 PE 证书不得失败。

Build/Release 签 PASS（SMC Copilot Hermes / 2026-10-09）。

### G-P03 — 版本锁定（Runtime/QA）→ PASS

Front matter 与 REQ-SRC-001 / A-SRC-001 / A-UPD-001 / NON-GOAL-001：Agent `0.21.0@041b6985…`，Installer ProductVersion `2.0.0`，UpgradeCode 不变，禁止跟 `hermes-agent/main`。当前仓库 `build-msi.yml` 的 default `source_ref` 已是该 SHA。Baseline SHA `7d77737` 已复核。

Runtime/QA 签 PASS（SMC Copilot Hermes / 2026-10-09）。

### G-P04 — T0 / Commit / 失败保留（Runtime/Security）→ PASS

Grill Q9–Q11、Q17–Q18、Q21 已写入 §9.5 / §14。补偿集唯一：保留已过门 venv；收回 `bin\hermes.exe`；撤销本次 Skill/`CreateNew`；已写 HKCU 回 T0。失败树只进 `runtime-backups\<op>\`。`UV_SYNC_FAILED` 仅 uv 已启动。`RECEIPT_COMMIT_FAILED` 已列入 REQ-TXN-001 Error Codes。

Runtime/Security 签 PASS（SMC Copilot Hermes / 2026-10-09）。

### G-P05 — Ownership / v1 Cleanup / Direct MSI（Installer/Desktop）→ PASS

§12.1 含 venv、bin launchers、receipt、lock、skill ledger、backups、用户文件、Provider sidecar；本审查补入 `bootstrap\HermesRuntimeInit.exe` 与 `runtime-manifest-v2.json`+`.sig`。Direct MSI 成功 = `PAYLOAD_INSTALLED`。卸载不删 USER_OWNED / ledger / 诊断。无 `--purge-generated-runtime`。v1 Cleanup：不单发补丁 SKU；真机断言实际 0.21.0 包；仅 USER_OWNED 变化才 `MIGRATION_BLOCKED`。

Installer/Desktop 签 PASS（SMC Copilot Hermes / 2026-10-09）。

### G-P06 — Hash / 签名 / Secret（Security/Build）→ PASS

规格部分 TEXT_OK（树 digest、排除自引用、Ed25519 detached、Init 验签后再 uv）。**Authenticode 已按 `NON-GOAL-007` 从本 Gate 删除。**

**Secret 存在证据（名称，非值）**：2026-10-09 截图 `github.com/smc-copilot/hermes-builder/settings/secrets/actions` → Repository secrets 列表含锁图标项 **`HERMES_MANIFEST_ED25519_SEED_B64`**。Environment secrets 为空。GitHub UI 不展示 Secret 值；本文件不得记录 Base64。

工作流尚未引用该 Secret 属于实施计划，不回退本 Gate。缺失 Secret 时构建仍必须 `MANIFEST_SIGNING_KEY_MISSING`。

### G-P07 — AC Oracle / Evidence Schema（QA）→ PASS（schema 可执行）

原字面「真实 Win10/升级 Golden」与 §28 首段「A-CI-001 真机属于 Release Gate」冲突。本审查把 G-P07 收成：**28 项 A-\* 均有 Given/When/Then/Oracle 与 §24 Evidence Schema**；Golden **执行**归 R-08。

静态计数：`## A-` = 28，与 §25 `REQUIRED_AC` 一致。§21/22/23 有矩阵。`TEST-A-*` 文件尚未存在，计划批准不要求测试已落地。

QA 签本 Gate PASS = 承认 Oracle 可执行，**不是**宣称 `A-CI-001` 已 PASS。

### G-P08 — 无 SPEC_SEMANTIC_GAP + 签名记录（Architecture Owner）→ PASS

Grill 六处双解已从 PRD 删除。本审查另消除：

- G-P07 与 Release Gate 的双解（Gate 表已改写）
- `RECEIPT_COMMIT_FAILED` 未进 REQ 错误码
- Init EXE / runtime-manifest 未进 §12.1

残留非双解项（不挡计划，须知悉）：

| ID | 项 | 处理 |
|---|---|---|
| N-INV | `INV-*` 只有 ID 无正文 | 行为以 REQ/AC 为准；INV 当稳定标签 |
| N-NEG | N-001…N-016 未给 SRC/BUILD/PRE/UI 单独行 | 由 A-SRC/A-BUILD/A-PRE/A-UI 的负向 Oracle 覆盖 |
| N-CODE | 仓库仍是 v1 CA 安装器 | 实施问题，不是规格双解 |

Architecture Owner 已在本文件签字。

## §28.3 Plan Readiness

```text
[x] G-P01..G-P08 获得架构评审记录     — 签署人 SMC Copilot Hermes / 2026-10-09
[x] 所有 Must / Must Not 有可判定 Oracle — REQ→AC；N-* 未全覆盖但 AC 可判定
[x] Owner/State/Hash/Default/Conflict/Failure 已唯一（grill + 本审查补丁）
[x] Runtime version lock 明确，自动升级 Agent 禁用
[x] Source PRD / Baseline SHA 已由 Reviewer 复核 — `7d77737` / `041b6985`
[x] status 经授权改为 APPROVED_FOR_PLAN
```

## Named Reviewer sign-off

签署人一律为 **SMC Copilot Hermes**。日期一律 **2026-10-09**。仓库证据：`smc-copilot/hermes-builder` Actions repository secret 名称可见。

| Gate | Reviewer | PASS/FAIL | Name | Date | Notes |
|---|---|---|---|---|---|
| G-P01 | Windows Installer | PASS | SMC Copilot Hermes | 2026-10-09 | MSI 无 uv CA；INIT_TXN 独立 |
| G-P02 | Build/Release | PASS | SMC Copilot Hermes | 2026-10-09 | DAG 无自嵌；本轮无 Authenticode |
| G-P03 | Runtime/QA | PASS | SMC Copilot Hermes | 2026-10-09 | `0.21.0@041b6985`；Installer `2.0.0`；baseline `7d77737` |
| G-P04 | Runtime/Security | PASS | SMC Copilot Hermes | 2026-10-09 | T0 / 补偿 / 失败树唯一 |
| G-P05 | Installer/Desktop | PASS | SMC Copilot Hermes | 2026-10-09 | Owner / Direct MSI=`PAYLOAD_INSTALLED` / 无 purge |
| G-P06 | Security/Build | PASS | SMC Copilot Hermes | 2026-10-09 | Ed25519 only；Secret **名称**已见截图；`keyId=e6199f4b558ab9c4`；Authenticode 本轮不要求 |
| G-P07 | QA | PASS | SMC Copilot Hermes | 2026-10-09 | schema 可执行；勿把 R-08 当真 |
| G-P08 | Architecture Owner | PASS | SMC Copilot Hermes | 2026-10-09 | 无 SPEC_SEMANTIC_GAP；本表即具名签名 |

## G-P06 Security Attestation（Ed25519 Manifest seed）

**签署人：** SMC Copilot Hermes  
**日期：** 2026-10-09  
**结论：** PASS（本轮不含 Authenticode，见 `NON-GOAL-007`）

| 项 | 确认 |
|---|---|
| Secret 名称 | `HERMES_MANIFEST_ED25519_SEED_B64` |
| GitHub 位置 | `smc-copilot/hermes-builder` → Settings → Secrets and variables → Actions → Repository secrets（2026-10-09 截图可见该名称） |
| 编码 | RFC4648 标准 Base64，无换行 |
| 解码长度 | 正好 32 bytes |
| `keyId` | `e6199f4b558ab9c4`（`SHA256(raw_public_key)` 前 16 位 lowercase hex） |
| 私钥不进 git / 日志 / 本评审文件 / 发布包 | 是 |
| 缺失时构建 | 必须 `MANIFEST_SIGNING_KEY_MISSING`，不得跳过 Ed25519 |
| Authenticode / 组织代码签名证书 | 本轮不要求、不作为本 Gate 条件 |

Secret **值**不可见、未写入本文件。可用本表 `keyId` 核对公钥，**不得**把 Base64 贴回本文件或聊天记录。

## Out of scope

- 生成 `.plan.md`（现已**允许**，本文件不自动产出）
- 改安装器代码
- 把 Windows Server CI 当作 Win10 Golden
- 把 workflow 尚未引用 Secret 说成 Manifest 签名 Build 已 PASS
- 把 Authenticode 证书重新加回本轮 G-P06 / Release DoD（已被 `NON-GOAL-007` 停用）
