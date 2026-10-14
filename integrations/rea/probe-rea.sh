#!/usr/bin/env bash
# probe-rea.sh — 探测 REA (rea-agents) MCP 后端是否可用，并与映射表对账。
# 不改动任何配置；只读探测。退出码: 0=REA 可达, 3=npx/网络不可用, 4=doctor 报告未注册。
# 用法: bash integrations/rea/probe-rea.sh [--client claude_code] [--json]
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VERSION_FILE="$HERE/rea.version"
MAP_FILE="$HERE/rea-tool-map.json"

CLIENT="claude_code"
JSON_OUT=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --client) CLIENT="${2:-claude_code}"; shift 2 ;;
    --json) JSON_OUT=1; shift ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done

VERSION="latest"
[[ -f "$VERSION_FILE" ]] && VERSION="$(tr -d '[:space:]' < "$VERSION_FILE")"
PKG="rea-agents@${VERSION}"

log() { [[ "$JSON_OUT" == 1 ]] || echo "$@"; }

log "== REA probe =="
log "pinned package : $PKG"
log "client         : $CLIENT"
log "mcp launch     : npx -y $PKG mcp"
log ""

if ! command -v npx >/dev/null 2>&1; then
  log "npx 未找到 — 需要 Node.js/npm。REA 不可用，技能将退回本地工具链。"
  [[ "$JSON_OUT" == 1 ]] && echo '{"rea_available":false,"reason":"npx-missing"}'
  exit 3
fi

log "运行 REA doctor（只读，可能触发一次 npx 下载缓存）..."
set +e
DOCTOR_OUT="$(npx -y "$PKG" doctor --client "$CLIENT" --json 2>/dev/null)"
RC=$?
set -e

if [[ $RC -ne 0 || -z "$DOCTOR_OUT" ]]; then
  log "doctor 未能返回 JSON（REA 可能未安装成功或客户端未识别）。按 preferenceRule 退回本地工具链。"
  [[ "$JSON_OUT" == 1 ]] && echo '{"rea_available":false,"reason":"doctor-failed"}'
  exit 4
fi

if [[ "$JSON_OUT" == 1 ]]; then
  echo "$DOCTOR_OUT"
else
  echo "doctor 原始输出:"
  echo "$DOCTOR_OUT"
  echo ""
  echo "映射表覆盖的 reverse-skill 模块:"
  if command -v node >/dev/null 2>&1 && [[ -f "$MAP_FILE" ]]; then
    node -e "const m=require('$MAP_FILE'); const k=Object.keys(m.map); console.log('  '+k.join(', ')); const n=new Set(); Object.values(m.map).forEach(v=>v.reaTools.forEach(t=>n.add(t))); console.log('  引用的 REA 工具数: '+n.size);"
  fi
  echo ""
  echo "下一步: 在 Claude Code 里重启/重连后，用 tools/list 确认 rea 工具已出现；"
  echo "        之后技能按 rea-tool-map.json 的 preferenceRule 自动优先 REA。"
fi
