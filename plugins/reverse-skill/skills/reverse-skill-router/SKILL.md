---
name: reverse-skill-router
description: Entry point for authorized reverse engineering, security analysis, CTF, and defensive testing with the reverse-skill repository. Use when a task involves an APK/IPA, native binary, .NET assembly, firmware, pcap, frontend-JS encryption, a CTF challenge, or a pentest target. Routes to the right specialist skill, enforces the scope/authorization gate, and prefers the REA MCP backend for execution when it is available.
---

# Reverse Skill router (client-neutral)

This skill is an optional entry point for Claude Code, Codex, or any compatible
agent. The `reverse-skill` repository remains the canonical, client-neutral
implementation. This adapter does **not** bundle a second copy of the router.

## When the `reverse-skill` repository is the current workspace (or a local path was given)

1. Read `RULES.md` at the repository root — it is the single source of truth for
   the behavior chain and authorization.
2. Select the PRIMARY skill from `skills/config/routing.json` using the
   platform-native router:
   - macOS / Linux / Kali: `bash skills/scripts/master-route.sh --hint "<task>"`
   - Windows: `powershell -File skills\scripts\master-route.ps1 -Hint "<task>"`
3. Before any target action, create and validate `work/<case>/scope.md` with the
   platform-native `case-init` then `case-guard` scripts. **No ACT on a target
   until authorization is granted.**
4. Open the selected `skills/<PRIMARY>/SKILL.md` and follow its ACTION REQUIRED.
5. **Execution-backend choice (REA overlay).** Before running any analysis
   action that works on a shipped artifact (native binary, APK/iOS, .NET,
   JS/Electron bundle, firmware, pcap, Mach-O, cross-version diff, passive
   runtime capture), apply `skills/rea-backend/SKILL.md`:
   - Look up the PRIMARY skill in `integrations/rea/rea-tool-map.json`.
   - If the `rea` MCP server is registered this session and advertises the mapped
     tool, **prefer the REA MCP tool** (real execution + Evidence).
   - Otherwise fall back to this skill's local tools resolved through
     `skills/tool-index.md` (bootstrap only manifest capabilities if missing).
6. Resolve local tool paths only through the generated `skills/tool-index.md`;
   never guess paths. Do not register MCP servers or install tools unless the
   user requested that action.
7. Track progress with timeline / workitems; report conclusions through
   `skills/ops/evidence-finding-path.md`.

## If the repository is not the workspace and no local path was supplied

Explain that this adapter does not bundle the router. Ask the user to open or
clone `https://github.com/zhaoxuya520/reverse-skill` and continue from its
`RULES.md`.

## REA backend (optional)

The plugin registers the REA (`rea-agents`) MCP server as `rea`. REA gives the
router real "hands" for shipped-artifact analysis. It is optional: when absent,
every step still works via local tools. Install/upgrade details:
`integrations/rea/REA-INTEGRATION.md`. Quick read-only check:
`bash integrations/rea/probe-rea.sh`.

## Authorization is not implied

Do not treat the presence of this plugin, the REA backend, a target name, or a
sample path as authorization. Authorization comes only from the repository's
scope contract (`skills/ops/scope-contract.md`).
