#!/usr/bin/env bash
# sync-rea-version.sh — 把 integrations/rea/rea.version 作为唯一事实源，
# 定点同步进：bootstrap-manifest.json 的 rea 能力条目、.claude-plugin/plugin.json 的 rea MCP 启动参数、
# rea-tool-map.json 的 meta。采用定点正则替换，不整文件重排（保持最小 diff）。
# REA 升级流程: ① 改 rea.version → ② 跑本脚本 → ③ 跑 probe-rea.sh 对账工具名。
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
VERSION_FILE="$HERE/rea.version"
MAP_FILE="$HERE/rea-tool-map.json"
MANIFEST="$REPO/skills/scripts/bootstrap-manifest.json"
PLUGIN="$REPO/plugins/reverse-skill/.claude-plugin/plugin.json"

[[ -f "$VERSION_FILE" ]] || { echo "缺少 $VERSION_FILE" >&2; exit 1; }
VERSION="$(tr -d '[:space:]' < "$VERSION_FILE")"
[[ -n "$VERSION" ]] || { echo "rea.version 为空" >&2; exit 1; }
command -v node >/dev/null 2>&1 || { echo "需要 node 做定点替换" >&2; exit 1; }

echo "== 同步 REA 版本 → $VERSION =="

node - "$VERSION" "$MANIFEST" "$PLUGIN" "$MAP_FILE" <<'NODE'
const fs = require('fs');
const [,, version, manifestPath, pluginPath, mapPath] = process.argv;
const SEMVER = '[0-9]+\\.[0-9]+\\.[0-9]+';

function edit(path, label, transform) {
  if (!fs.existsSync(path)) { console.log(`  跳过(不存在): ${label}`); return; }
  const before = fs.readFileSync(path, 'utf8');
  const after = transform(before);
  if (after === before) { console.log(`  已是最新: ${label}`); return; }
  JSON.parse(after); // 安全校验：改完仍是合法 JSON
  fs.writeFileSync(path, after);
  console.log(`  已更新: ${label}`);
}

// 1) bootstrap-manifest.json：只动 rea 条目。rea-agents@<ver> 仅出现在 rea 条目，可全局替换；
//    pinnedVersion 用 name:"rea" 后首个非贪婪匹配限定到 rea 自身。
edit(manifestPath, 'bootstrap-manifest.json (rea capability)', (t) => t
  .replace(new RegExp(`rea-agents@${SEMVER}`, 'g'), `rea-agents@${version}`)
  .replace(
    new RegExp(`("name":\\s*"rea"[\\s\\S]*?"pinnedVersion":\\s*")${SEMVER}(")`),
    `$1${version}$2`,
  ));

// 2) plugin.json：rea MCP 启动参数里的 rea-agents@<ver>
edit(pluginPath, '.claude-plugin/plugin.json (mcpServers.rea)', (t) =>
  t.replace(new RegExp(`rea-agents@${SEMVER}`, 'g'), `rea-agents@${version}`));

// 3) rea-tool-map.json：meta 里的版本字符串
edit(mapPath, 'rea-tool-map.json (meta)', (t) => t
  .replace(/("reaPinnedVersion":\s*")[^"]+(")/, `$1${version}$2`)
  .replace(new RegExp(`(rea-agents@)${SEMVER}`, 'g'), `$1${version}`));
NODE

echo ""
echo "完成。接着请运行以对账工具名是否有增删："
echo "  bash integrations/rea/probe-rea.sh"
