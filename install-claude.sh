#!/usr/bin/env bash
# install-claude.sh — 把 reverse-skill(路由大脑) + REA(rea-agents 执行后端) 作为
# 一个 Claude Code 插件装好。幂等；装插件即同时注册 REA MCP（见 plugin.json mcpServers）。
# 用法:
#   bash install-claude.sh              # 通过本地 marketplace 安装插件（推荐）
#   bash install-claude.sh --dev        # 只打印 dev 模式用法（--plugin-dir，改动即时生效）
#   bash install-claude.sh --mcp-only   # 只注册 REA MCP，不装路由插件
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VERSION_FILE="$REPO/integrations/rea/rea.version"
REA_VERSION="latest"
[[ -f "$VERSION_FILE" ]] && REA_VERSION="$(tr -d '[:space:]' < "$VERSION_FILE")"

MODE="install"
case "${1:-}" in
  --dev) MODE="dev" ;;
  --mcp-only) MODE="mcp-only" ;;
  "" ) MODE="install" ;;
  *) echo "unknown arg: $1" >&2; exit 2 ;;
esac

echo "== reverse-skill × REA · Claude Code 安装器 =="
echo "repo        : $REPO"
echo "REA version : rea-agents@$REA_VERSION  (source: integrations/rea/rea.version)"
echo ""

# 先把 rea.version 同步进 plugin.json / bootstrap-manifest（保证版本一致）
if [[ -f "$REPO/integrations/rea/sync-rea-version.sh" ]] && command -v node >/dev/null 2>&1; then
  bash "$REPO/integrations/rea/sync-rea-version.sh" >/dev/null 2>&1 || true
fi

require_node() {
  if ! command -v npx >/dev/null 2>&1; then
    echo "⚠️  未找到 npx (Node.js/npm)。REA 后端需要 Node。先安装 Node 18+："
    echo "    macOS:  brew install node   或  https://nodejs.org/"
    echo "    之后重跑本脚本。路由大脑本身不依赖 Node（可照常用本地工具链）。"
    return 1
  fi
}

if [[ "$MODE" == "dev" ]]; then
  cat <<EOF
Dev 模式（插件改动即时生效，不写入全局配置）：

  cd <你的分析项目目录>
  claude --plugin-dir "$REPO/plugins/reverse-skill"

会话内 /plugin 可见 reverse-skill；首次用到 REA 工具时 Claude 会提示批准 MCP。
EOF
  exit 0
fi

if [[ "$MODE" == "mcp-only" ]]; then
  require_node || exit 3
  if command -v claude >/dev/null 2>&1; then
    echo "注册 REA MCP (server name: rea) 到 Claude Code..."
    claude mcp add rea -- npx -y "rea-agents@$REA_VERSION" mcp \
      && echo "✓ 已注册。重启/重连 Claude Code 后，tools/list 应出现 rea。" \
      || echo "（若提示已存在，先 'claude mcp remove rea' 再重试。）"
  else
    echo "未找到 claude CLI。手动注册："
    echo "  claude mcp add rea -- npx -y rea-agents@$REA_VERSION mcp"
  fi
  exit 0
fi

# 默认：本地 marketplace + 安装插件（插件 mcpServers 会一并注册 REA）
if ! command -v claude >/dev/null 2>&1; then
  cat <<EOF
未找到 claude CLI。两种手动方式二选一：

A) Dev 模式（最快，改动即时生效）：
   claude --plugin-dir "$REPO/plugins/reverse-skill"

B) 从本地 marketplace 安装：
   在 Claude Code 会话里执行：
     /plugin marketplace add $REPO
     /plugin install reverse-skill@reverse-skill
EOF
  exit 3
fi

require_node || echo "（继续安装插件；REA 后端待装好 Node 后自动可用）"

echo "添加本地 marketplace: $REPO"
claude plugin marketplace add "$REPO" 2>/dev/null \
  || echo "（marketplace 可能已存在，跳过）"

echo "安装插件 reverse-skill@reverse-skill ..."
claude plugin install reverse-skill@reverse-skill \
  && echo "✓ 插件已安装。" \
  || echo "（若已安装，可用 'claude plugin list' 查看，或 /plugin 管理。）"

cat <<EOF

完成。下一步：
  1. 重启 / 重连 Claude Code。
  2. 首次用到 REA 工具时批准 MCP 启动（server name: rea）。
  3. /plugin 确认 reverse-skill 已启用；tools/list 出现 rea 即后端就绪。
  4. 只读自检：bash "$REPO/integrations/rea/probe-rea.sh"

用法：对 Claude 说「用 reverse-skill 路由这个授权任务：<目标/样本>」。
路由大脑会先读 RULES.md 做 scope 门禁，再按 rea-tool-map.json 优先调用 REA。
EOF
