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

# 优先用本机已装的 rea CLI（快、不走网络）；没有再退回 npx。
if command -v rea >/dev/null 2>&1; then
  REA_CMD=(rea)
elif [[ -x "$HOME/.npm-global/bin/rea" ]]; then
  REA_CMD=("$HOME/.npm-global/bin/rea")
elif command -v npx >/dev/null 2>&1; then
  REA_CMD=(npx -y "$PKG")
else
  log "既没有 rea CLI 也没有 npx — 需要 Node.js/npm。REA 不可用，技能将退回本地工具链。"
  [[ "$JSON_OUT" == 1 ]] && echo '{"rea_available":false,"reason":"npx-missing"}'
  exit 3
fi
log "doctor 执行器   : ${REA_CMD[*]}"
log ""

log "运行 REA doctor（只读，可能触发一次 npx 下载缓存）..."
set +e
# 两个坑，都会造成"REA 不可用"的假阴性：
#   1. rea 6.x 没有 --json，是 --format json；用 --json 会被当未知参数，整条命令失败。
#   2. 加了 --client 会把"该客户端的注册项必须就绪"变成硬要求。REA 由 reverse-skill
#      插件的 mcpServers 提供时，注册不在 rea doctor 检查的那些文件里（~/.claude.json 等），
#      于是 doctor 以非零退出——但 REA 本身完全可用。
# 所以：不带 --client 跑，判定依据是"有没有拿到可解析的 JSON"，注册状态只作为提示。
DOCTOR_OUT="$("${REA_CMD[@]}" doctor --format json 2>/dev/null)"
RC=$?
set -e

if [[ -z "$DOCTOR_OUT" ]] || ! printf '%s' "$DOCTOR_OUT" | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{try{JSON.parse(s)}catch(e){process.exit(1)}})' 2>/dev/null; then
  log "doctor 没有返回可解析的 JSON（rc=$RC）。REA 可能未安装成功。按 preferenceRule 退回本地工具链。"
  [[ "$JSON_OUT" == 1 ]] && echo '{"rea_available":false,"reason":"doctor-failed"}'
  exit 4
fi
[[ $RC -ne 0 ]] && log "（doctor 退出码 ${RC}，表示有必需项未就绪，见下面的清单；不代表 REA 不可用。）"

if [[ "$JSON_OUT" == 1 ]]; then
  echo "$DOCTOR_OUT"
else
  # 原来这里直接 echo 整份 doctor JSON（约 60KB），人和 agent 都读不动。改为只列未通过项。
  echo "doctor 未通过的检查项（完整 JSON 用 --json 取）:"
  printf '%s' "$DOCTOR_OUT" | node -e '
    let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{
      let d;try{d=JSON.parse(s)}catch(e){console.log("  (解析失败)");return}
      const rows=[...(d.scope_checks||[]),...(d.checks||[])].filter(c=>c&&c.ok===false);
      if(!rows.length){console.log("  全部通过");return}
      const seen=new Set();
      for(const c of rows){
        if(seen.has(c.name))continue;seen.add(c.name);
        console.log(`  [缺] ${c.name}${c.detail?" — "+c.detail:""}`);
      }
      console.log(`  healthy=${d.healthy} environment_healthy=${d.environment_healthy}`);
    });'
  echo ""
  echo "映射表覆盖的 reverse-skill 模块:"
  if command -v node >/dev/null 2>&1 && [[ -f "$MAP_FILE" ]]; then
    node -e "const m=require('$MAP_FILE'); const k=Object.keys(m.map); console.log('  '+k.join(', ')); const n=new Set(); Object.values(m.map).forEach(v=>v.reaTools.forEach(t=>n.add(t))); console.log('  引用的 REA 工具数: '+n.size);"
  fi
  echo ""
  echo "深度 provider 就绪状态（决定 binary_overview / analyze_function / xrefs 这类工具能不能用）:"
  if command -v node >/dev/null 2>&1; then
    printf '%s' "$DOCTOR_OUT" | node -e '
      let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{
        let d;try{d=JSON.parse(s)}catch(e){console.log("  (doctor JSON 解析失败，跳过)");return}
        const find=(o,k,out=[])=>{if(o&&typeof o==="object"){if(Array.isArray(o[k]))out.push(...o[k]);for(const v of Object.values(o))find(v,k,out)}return out};
        const ins=find(d,"providerInspections");
        if(!ins.length){console.log("  (doctor 未返回 providerInspections)");return}
        let any=false;
        for(const p of ins){
          const ok=p.available===true;if(ok)any=true;
          console.log(`  ${ok?"[OK]  ":"[缺] "} ${p.id}${p.providerVersion?" "+p.providerVersion:""}`);
          for(const c of (p.checks||[])) if(!c.ok) console.log(`          ${c.code}: ${c.detail||""}${c.remediation?" -> "+c.remediation:""}`);
        }
        console.log(any
          ? "  => 至少一个 provider 可用：只要一个就够，REA 的 provider:auto 会挑它。"
          : "  => 没有任何 provider 可用：需要 provider 的动作会返回 provider_unavailable，\n     按 overlay 逐动作退回本地工具链（元数据类工具不受影响）。");
      });'
  else
    echo "  (需要 node 才能解析，跳过)"
  fi
  echo ""
  echo "前置条件提醒（provider 装好了也会卡在这里）:"
  echo "  * Mach-O 必须是单架构 slice。Ghidra v1 导入 universal/fat Mach-O 会返回"
  echo "    architecture_unsupported。先 lipo -archs <bin>，多架构就 lipo -thin <arch> -output <slice>。"
  echo ""
  echo "下一步: 在 Claude Code 里重启/重连后，用 tools/list 确认 rea 工具已出现；"
  echo "        之后技能按 rea-tool-map.json 的 preferenceRule 自动优先 REA。"
  echo "注意: MCP server 的环境变量不继承交互式 shell。provider 的 env"
  echo "      （GHIDRA_INSTALL_DIR 等）必须写进 MCP 注册项的 env 块，"
  echo "      或改用本地 rea CLI 并在同一条命令里 export。"
fi
