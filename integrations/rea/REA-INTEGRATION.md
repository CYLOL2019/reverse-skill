# REA 执行后端集成（reverse-skill × rea-agents）

> reverse-skill 是**大脑**（路由 + SOP + 授权门禁）。REA（npm 包 `rea-agents`）是**手**——一个 MCP server，
> 能真正驱动 Ghidra / IDA / Hopper / apktool / pcap / .NET / JS 等对 **shipped 制品**做反编译、结构分析、
> 跨版本比对、被动运行时取证，并返回带 provenance 的 Evidence。
>
> **设计原则：REA 以"引用方式"接入，不整份拷进本仓。** reverse-skill 为主仓，REA 用固定版本号引用。
> 这样既保持单一产品，又让"REA 更新"只需改动极少的几处。

---

## 1. 架构：它是"叠加"，不是"替换"

```
用户任务
  → RULES.md（授权/scope 门禁，不变）
  → MASTER-ROUTING / master-route（选 PRIMARY，不变）
  → case-init / scope.md（auth 未 granted 禁止 ACT，不变）
  → PRIMARY SKILL.md（执行某类分析）
      └─ 执行某动作前：rea-backend 规则  ← 新增的唯一接线点
           ├─ integrations/rea/rea-tool-map.json 查该 PRIMARY 的 reaTools
           ├─ 会话里 REA MCP(server=rea) 有对应工具？
           │     ├─ 有 → 调 REA 工具（真执行 + Evidence）
           │     └─ 无/缺/被拦 → 退回本地 CLI（tool-index → bootstrap）
  → timeline + Evidence→Finding→Path → 报告（不变）
```

路由、角色、scope 门禁、证据链**全部不变**。REA 只在"工具解析层"多一个优先后端。

---

## 2. 集成清单（本仓新增/改动的全部文件）

| 文件 | 作用 |
|---|---|
| `integrations/rea/rea.version` | **版本单一事实源**（one knob）。当前：`6.4.0`。 |
| `integrations/rea/rea-tool-map.json` | 45 模块 → REA MCP 工具映射 + 回退策略 + 能力分组。**升级 REA 补工具只改这里。** |
| `integrations/rea/sync-rea-version.sh` | 把 `rea.version` 同步进 manifest + plugin.json + map 元信息。 |
| `integrations/rea/probe-rea.sh` | 只读探测 REA 是否可达 + 与映射表对账（不改配置）。 |
| `integrations/rea/REA-INTEGRATION.md` | 本文档。 |
| `skills/rea-backend/SKILL.md` | "优先 REA / 否则本地"的 overlay 规则（被 router 与 MASTER-ROUTING 第 6b 步引用）。 |
| `skills/scripts/bootstrap-manifest.json` | 新增 `rea` 能力条目（`npm-mcp`），让 REA 走既有能力体系。 |
| `skills/MASTER-ROUTING.md` | 执行契约加第 `6b` 步（指向 rea-backend）。 |
| `plugins/reverse-skill/.claude-plugin/plugin.json` | **Claude Code 插件清单**：暴露 router 技能 + 注册 REA MCP(`rea`)。 |
| `.claude-plugin/marketplace.json` | 本地 marketplace，供 `claude plugin install`。 |
| `install-claude.sh` | 一键把插件装进 Claude Code（装插件即注册 REA MCP）。 |

> Codex 侧原有 `plugins/reverse-skill/.codex-plugin/plugin.json` 不动；router 技能已改为 client-neutral，两端共用。

---

## 3. 安装（Claude Code 优先）

```bash
# 推荐：一键（本地 marketplace + 装插件；插件会注册 REA MCP）
bash install-claude.sh

# 开发/调试：改动即时生效，不写全局配置
claude --plugin-dir "$(pwd)/plugins/reverse-skill"

# 只要后端、不要路由插件：
bash install-claude.sh --mcp-only
# 等价于： claude mcp add rea -- npx -y rea-agents@6.4.0 mcp
```

安装后在 Claude Code 内**重启/重连**；首次用到 REA 工具时批准 MCP 启动；`tools/list` 出现 `rea` 即就绪。

前置：Node.js 18+（REA 后端需要）。**没有 Node 时路由大脑照常工作**，只是所有动作走本地工具链。
Native 深度引擎（Ghidra/IDA/Hopper）是 bring-your-own，由 REA 自己的 `npx rea-agents setup` 处理。

---

## 4. 升级 REA（你要的扩展点：改一处，跑两条命令）

```bash
# ① 改版本（唯一事实源）
echo "6.5.0" > integrations/rea/rea.version      # 换成目标版本

# ② 同步到 manifest + plugin.json + map 元信息
bash integrations/rea/sync-rea-version.sh

# ③ 对账工具名有无增删（REA 有时会新增/改名 MCP 工具）
bash integrations/rea/probe-rea.sh
```

- 若 REA **只是修了 bug、工具名没变** → 第 ③ 步无差异，完工。
- 若 REA **新增了工具**（例如多了某 `inspect_xxx`）→ 在 `rea-tool-map.json` 对应模块的 `reaTools` 里补上即可。
  不补也不报错：会话里以 REA 实际 `tools/list` 为准，未映射的工具只是不会被"优先"，不影响回退。
- 若 REA **改了工具名** → 在 `rea-tool-map.json` 把旧名换新名。
- 不要手改 `plugin.json` / `bootstrap-manifest.json` 里的版本，交给 `sync-rea-version.sh`，避免三处漂移。

### 如何拿到 REA 的最新工具清单对账

```bash
# 列出 REA 当前进程暴露的 MCP 工具（需 Node）
npx -y rea-agents@$(tr -d '[:space:]' < integrations/rea/rea.version) doctor --client claude_code --json
# 或在 Claude Code 会话里直接看 rea server 的 tools/list
```

把实际工具名与 `rea-tool-map.json` 的 `capabilityGroups` 比对，差异处补进对应 `map[...]`。

---

## 5. 边界与安全（REA 不放宽任何门禁）

- REA 的存在**不构成授权**。`work/<case>/scope.md` 未 `AuthGranted` 前不得对目标 ACT。
- REA 的静态/被动分析是本地只读；但重放、注入、动态 Frida hook、对远端发包仍受 `case-guard` /
  `network_profile` 约束（见 `skills/ops/scope-contract.md`）。
- Evidence provenance 原样进证据链，不得改写成更强结论（observation vs inference）。
- 纯源码仓库的常规架构分析**不应**启动 REA（见 map 的 `code-audit` 注记）。

---

## 6. 为什么不直接把 REA 合并进来？

- REA 是需要编译/CI 的 TypeScript MCP 引擎（v6.4.0，含 mutation 测试）；reverse-skill 是 markdown 路由包。
  两种制品硬合并会让双方都更难维护。
- 两个都是活跃上游。以 npm 固定版本引用 → 升级 = 改一行版本号 + 对账映射表，随时跟得上上游。
- 解耦也保留了"无 REA 也能用"的能力：Node/REA 不可用时，reverse-skill 完整退回本地工具链。
