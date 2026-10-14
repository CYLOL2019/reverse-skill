---
name: rea-backend
description: 逆向/分析类任务的『执行后端选择』规则。当任一 reverse-skill 技能要对 shipped 制品（原生二进制、APK/iOS、.NET、JS/Electron bundle、固件、pcap、Mach-O 等）执行反编译/结构分析/版本比对/被动运行时取证时读此规则：优先调用已注册的 REA (rea-agents) MCP 工具（真执行 + Evidence），缺失则退回该技能原有的本地 CLI/脚本。不改变路由、授权门禁与 Evidence→Finding→Path 契约。
metadata:
  role: tool-resolution-overlay
  appliesTo: analysis-execution
  singleSourceOfTruth: integrations/rea/rea-tool-map.json
---

# REA 执行后端规则（overlay，不是独立场景）

本技能**不是**一个独立的路由终点，而是叠加在工具解析层（MASTER-ROUTING 第 6 步）上的
一条偏好规则。任何被 PRIMARY 技能选中后、准备"动手执行某类分析"的时刻，都适用它。

## 为什么存在

reverse-skill 是"大脑"（决定用什么方法、什么顺序、是否已授权）。
REA (`rea-agents`) 是一套"手"——一个 MCP server，能真正驱动 Ghidra/IDA/Hopper/Frida/
apktool 等，对 shipped 制品做反编译、结构分析、跨版本比对、被动运行时取证，并返回带
provenance 的 Evidence。两者是上下层，不是二选一。

## 判定顺序（ACTION REQUIRED）

对"要执行的那一个分析动作"，按下列顺序：

1. **查映射表** `integrations/rea/rea-tool-map.json` 的 `map[<当前PRIMARY技能>]`，
   取 `reaTools`（该动作对应的 REA 工具候选）。
2. **会话里 REA 是否可用？** 看当前 MCP 工具清单里是否存在名为 `rea` 的 server 及对应工具
   （即 `tools/list` 含该 `reaTools` 成员）。
   - **有** → 调用该 REA 工具执行；把返回的 Evidence 并入 timeline 与 Evidence→Finding→Path。
   - **无 / 该工具缺失 / 被客户端拦截** → 按 `localFallback` 与该技能 SKILL.md 原流程，
     用 `tool-index.md` 解析本地工具执行（缺则 bootstrap，仅 manifest 能力）。
3. **逐动作判断**：某个工具缺失只让"那一个动作"退回本地，不影响其余 REA 工具继续使用。

> 快速自检：`bash integrations/rea/probe-rea.sh`（只读，不改配置）。

## 硬约束（继承 RULES.md / scope-contract，不被 REA 放宽）

- REA 的存在**不构成授权**。`work/<case>/scope.md` 未 `AuthGranted` 前，不得对目标 ACT。
- REA 的静态/被动分析是**本地只读**；但重放、注入、动态 Frida hook、对远端目标发包仍受
  `case-guard` 与 `network_profile` 门禁约束。
- 保留 Evidence provenance：REA 返回的 `operation`/路径/摘要/limitations 原样进证据链，
  不得改写成更强的结论（遵守 observation vs inference 区分）。
- 纯源码仓库的常规架构分析**不应**启动 REA（见映射表 `code-audit` 注记）。

## 安装 / 注册（仅在用户要求时）

本仓库默认不自动注册任何 MCP。要把 REA 接上 Claude Code：

```bash
# 一键（推荐，macOS/Linux）：注册 REA MCP + 启用 reverse-skill 插件
bash install-claude.sh

# 或仅注册 REA MCP（版本取自 integrations/rea/rea.version）
claude mcp add rea -- npx -y rea-agents@$(tr -d '[:space:]' < integrations/rea/rea.version) mcp
```

注册/升级后需在 Claude Code 内重启或重连，`tools/list` 出现 `rea` 工具即生效。

## 升级 REA（扩展点）

REA 更新时只动两处 → 见 `integrations/rea/REA-INTEGRATION.md`：
1. 改 `integrations/rea/rea.version` → 跑 `integrations/rea/sync-rea-version.sh`
2. 跑 `integrations/rea/probe-rea.sh` 对账工具名，必要时补 `rea-tool-map.json`
