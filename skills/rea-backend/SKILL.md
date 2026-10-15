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
3. **该工具要不要 deep provider？**（`rea-tool-map.json` 的 `requiresProvider`，或按下表判断）
   - **不要**（元数据/原生 macOS 类：`inspect_signature` / `inspect_plist` / `inspect_macho` /
     `demangle_swift` / `analyze_swift_types` / `get_objc_classes` / `decode_interface_builder` …）
     → 直接调用。
   - **要**（反编译/交叉引用/调用图类：`binary_overview` / `analyze_function` /
     `procedure_pseudo_code` / `xrefs` / `batch_decompile` / `trace_feature` …）
     → **先确认至少有一个 provider 就绪**（Ghidra / Hopper / IDA 任一即可，`provider:auto` 会挑）。
     一个都没有就不要发起调用，直接按 `localFallback` 走本地工具链。
4. **逐动作判断**：某个工具缺失只让"那一个动作"退回本地，不影响其余 REA 工具继续使用。

> **ACTION REQUIRED（进入第 3 步"要 provider"分支前跑一次，每个 case 一次就够）**：
> `bash integrations/rea/probe-rea.sh`（只读，不改配置）。看它的「深度 provider 就绪状态」一段。
> 不跑这一步的后果是真实发生过的：provider 缺失只会在**第一次深度调用**时以
> `provider_unavailable` 暴露，那时已经做了十来步，分析计划要中途改道。

### 要 provider 的动作，还有两个前置条件

- **单架构 slice**：Ghidra v1 **不能**导入 universal/fat Mach-O，会返回
  `architecture_unsupported`。先 `lipo -archs <bin>`；多架构就
  `lipo -thin <arch> <bin> -output <slice>`，拿 slice 去分析。
  注意地址从此是该 slice 的 VM 地址，证据链里要写明是哪个 arch。
  元数据类工具不受此限，fat 二进制直接吃。
- **provider 的环境变量必须在 MCP 注册项里**：MCP server 由客户端拉起，**不继承交互式
  shell**，所以 `~/.zshrc` 里的 `GHIDRA_INSTALL_DIR` 到不了它。要写进注册项的 `env` 块
  （见下节），或者放弃 MCP、改用本地 `rea` CLI 并在**同一条命令里** export。

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

# 要用 Ghidra/Hopper/IDA 这类 deep provider，注册时必须显式带上 env，
# 否则 MCP server 看不到你 shell 里的变量（provider 会一直是 not_configured）：
claude mcp add rea \
  --env GHIDRA_INSTALL_DIR="$GHIDRA_INSTALL_DIR" \
  -- npx -y rea-agents@$(tr -d '[:space:]' < integrations/rea/rea.version) mcp
```

走插件路径（`plugins/reverse-skill/.claude-plugin/plugin.json` 的 `mcpServers.rea`）时，
同一件事写在那里的 `env` 块：`"GHIDRA_INSTALL_DIR": "${GHIDRA_INSTALL_DIR}"`。
改完要**重启/重连** MCP 才生效；生效与否用 `probe-rea.sh` 的 provider 段确认，
不要靠"装了就该能用"的假设。

注册/升级后需在 Claude Code 内重启或重连，`tools/list` 出现 `rea` 工具即生效。

## 升级 REA（扩展点）

REA 更新时只动两处 → 见 `integrations/rea/REA-INTEGRATION.md`：
1. 改 `integrations/rea/rea.version` → 跑 `integrations/rea/sync-rea-version.sh`
2. 跑 `integrations/rea/probe-rea.sh` 对账工具名，必要时补 `rea-tool-map.json`
