---
title: "Project Windsurf Rules"
scope: personal
tool: windsurf
updated: 2026-06-05
tags:
  - tool-context
  - personal-project
---

# Windsurf Operating Context

You are executing within a RahulOS project workspace. Follow these rules to ensure perfect coordination and automated discovery.

### 1. Boot Order
1. Read `AGENTS.md` and `.agent/BOOTSTRAP.md` immediately to load roles, rules, and platforms.
2. Read `CLAUDE.md` and `README-AI.md` to map the workspace directories and commands.
3. Read the state files: `PROJECT-STATE.md` (human-readable), `ACTIVE_TASK.md` (current session context), and `STATE.json` (machine-readable).

### 2. State & Handoff Maintenance
- `PROJECT-STATE.md` is the canonical developer checklist and phase state. Update it as you make progress.
- At the end of every agent session, you MUST write your handoff notes to `ACTIVE_TASK.md` and stamp the session timestamp, agent name, and success status in `STATE.json`.

### 3. Project Packet Approval Pack
- Project scope, PRD, POC, boss summary, client scope, and approval readiness are defined in `.agent/plan/PROJECT-PACKET.md`.
- Project phases, tasks, gates, and roadmap data are defined in `.agent/plan/PHASES.md`.
- Keep PROJECT-PACKET and PHASES clean and parseable for the central approval portal.
- Storing approval evidence belongs in `.agent/approvals/`. Never directly mutate `PROJECT-STATE.md` to fake stakeholder sign-off.
