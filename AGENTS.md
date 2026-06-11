# Repository Guidelines

**Read `CLAUDE.md` first.** It is the canonical guide to this repository: project overview and philosophy, build/test commands (`scripts/ci/gate.sh`), architecture (native-first conversion + the separate `UpmarketRuntimeHelper` Python process), layers, targets, the "do not revisit" decisions, key constraints (sandbox, exact pins, redacted diagnostics, no toolkit names in user-facing copy), coding conventions, and workflow.

This file adds only what is specific to multi-agent work. It does not repeat `CLAUDE.md`.

## Agent Task Rules

Use GitHub issues or checklist items for agent work. Every task needs an objective, scope, non-goals, acceptance criteria, release gate, and risk area. See `docs/release/AGENT_TASK_ORCHESTRATION.md` for scoped multi-agent work.

- Assign **disjoint write sets** before launching multiple agents. Only one agent owns a file at a time.
- Agents may **read broadly but must edit narrowly**. Do not mix unrelated cleanup into a scoped task.
- The main integrating session merges results and resolves conflicts.
- Before a task is "done": identify the affected release gate in `docs/IMPLEMENTATION_PLAN.md`, run the matching `scripts/ci/gate.sh` mode, and state explicitly in the handoff if validation could not be run.
