# Obsidian 客户画像库统一归档工作流（2026-08-10 实战验证）

> 场景：把分散在 `exports/`、workspace 根目录的客户画像报告统一归档进 Obsidian 知识库
> `/data/hermes/obsidian-vault/客户画像/`，命名统一为 `YYYYMMDD_公司简称_客户画像报告.md`。
> 2026-08-10 一次性归档 20 家报告成功。

## 一、盘点（防遗漏，强制）

```bash
# 1. 按文件名搜「画像」——覆盖 exports + 根目录 + drafts
search_files(pattern="*画像*", path="/data/hermes/workspace", target="files")
search_files(pattern="*画像*", path="/data/hermes/obsidian-vault", target="files")

# 2. 按内容搜「客户画像」——抓命名不规范的（如无「报告」后缀）
search_files(pattern="客户画像报告|客户画像", path="/data/hermes/obsidian-vault", output_mode="files_only")

# 3. 全量兜底：所有 md 文件（materials 通常为空）
search_files(pattern="**/*", path="/data/hermes/workspace/exports", target="files")
search_files(pattern="**/*", path="/data/hermes/workspace/drafts", target="files")

# 4. 全局兜底：排除已归档目录
find /data/hermes -name "*客户画像*" -name "*.md" -not -path "*/obsidian-vault/客户画像/*"
```

盘点结果（2026-08-10 基线）：
- `exports/`：15 份规范命名（20260807_×11 + 20260810_×4）+ 御美高标（无日期前缀）+ 蓝之洋两版
- workspace 根目录：冰恒物联、杉川 v3.0、国际交易中心 3 份散件
- Obsidian 库已有：蓝之洋、冰恒物联、杉川 3 份（旧命名）
- **materials/ 为空，不检查**

## 二、命名规范

```
YYYYMMDD_公司简称_客户画像报告.md
```
- 日期取报告内「报告生成时间」（如 `20260601_冰恒物联`、`20260608_国际交易中心`、`20260616_杉川机器人`）
- 无日期前缀的历史文件按报告头时间补前缀
- 旧命名（全称无日期 / `_客户画像.md` / `_v3.0_芯片供应链深度版.md`）一律重命名

## 三、去重判定表

| 情况 | 处理 |
|------|------|
| 同公司多版本（如蓝之洋） | 保留更完整的「研究总监整合版」（含名称说明/分析师整合标注），不覆盖 |
| 同内容散件（冰恒/杉川，md5 相同） | 不重复复制，根目录散件收拢进 exports/ |
| 库内已有旧命名 | mv 重命名为规范名 |

蓝之洋案例：exports 20260803 版（28,156B, DDGS后端）vs Obsidian 原版（28,429B, 研究总监整合）→ 保留 Obsidian 原版并重命名，exports 版不覆盖。

## 四、执行命令

```bash
set -e
DEST="/data/hermes/obsidian-vault/客户画像"
mkdir -p "$DEST"
cd /data/hermes/workspace

# 1) 批量复制（逐份 cp，不用通配符避免误收 .docx）
for f in 20260810_邦特绝缘_客户画像报告.md ... ; do
  cp "exports/$f" "$DEST/$f"
done

# 2) 无日期前缀 → 补日期
cp "exports/深圳市御美高标科技有限公司_客户画像报告.md" "$DEST/20260803_御美高标_客户画像报告.md"
cp "电子元器件和集成电路国际交易中心_客户画像报告.md" "$DEST/20260608_国际交易中心_客户画像报告.md"

# 3) 重命名库内旧文件
mv "$DEST/杉川机器人_客户画像.md" "$DEST/20260616_杉川机器人_客户画像报告.md"
mv "$DEST/深圳市蓝之洋科技有限公司_客户画像报告.md" "$DEST/20260803_蓝之洋科技_客户画像报告.md"
mv "$DEST/清远市冰恒物联网络科技有限公司_客户画像报告.md" "$DEST/20260601_冰恒物联_客户画像报告.md"

# 4) 根目录散件收拢进 exports
mv "清远市冰恒物联网络科技有限公司_客户画像报告.md" "exports/20260601_冰恒物联_客户画像报告.md"
mv "杉川机器人_客户画像_v3.0_芯片供应链深度版.md" "exports/20260616_杉川机器人_客户画像报告.md"
mv "电子元器件和集成电路国际交易中心_客户画像报告.md" "exports/20260608_国际交易中心_客户画像报告.md"
```

## 五、完整性校验（强制）

```bash
# md5 对比 exports vs obsidian，预期除「有意保留的整合版」外全部 MATCH
cd /data/hermes/workspace/exports
for f in 20260*.md 202608*.md; do
  a=$(md5sum "$f" | cut -d' ' -f1)
  b=$(md5sum "$DEST/$f" | cut -d' ' -f1)
  [ "$a" = "$b" ] && echo "MATCH: $f" || echo "DIFF: $f"
done
```
> DIFF 属正常仅当：该文件在 Obsidian 侧为有意保留的整合版（如蓝之洋）。其余 DIFF 必须排查。

## 六、索引维护

生成/更新 `客户画像/README_索引.md`：
- 标题 + 命名规范 + 更新日期 + 来源说明
- 表格：`# | 报告日期 | 客户简称 | 文件`
- 说明区：双格式（docx 留在 exports）、原厂画像不属客户画像目录、去重记录

## 七、关键坑

1. **`mcp_workspace_*` 无法访问 obsidian-vault**（Access denied，allowed dirs 只有 /data/hermes/workspace）→ 用原生 `terminal`/`write_file`/`search_files` 操作 vault。
2. **文件名搜「画像」会漏掉命名不规范的** → 必须叠加内容搜索 + 全量列目录 + find 全局兜底。
3. **docx 不归档进 Obsidian**（笔记库只收 .md），docx 留在 exports。
4. **原厂画像（manufacturer-profiling）与客户画像不同目录**：恒烁半导体的 `_原厂画像报告` 不进 `客户画像/`。
5. **记忆中的历史画像（欧文斯/天钺/英码等）当前文件系统可能已无 md 文件** → 归档前用 find 全局确认，找不到的如实告知用户，不编造。
