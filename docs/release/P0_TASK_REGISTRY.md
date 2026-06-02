# P0 Task Registry

The source of truth for executable P0 work packages is `docs/release/p0_task_registry.json`.

Use this registry to create scoped GitHub issues for Codex or specialist agents. Each task includes objective, owner, scope, non-goals, acceptance criteria, release gate, risk area, and labels.

## Local Validation

```sh
scripts/ci/validate_task_registry.py
```

For P0-001 architecture work, also read:

```text
docs/release/ARCHITECTURE_BOUNDARIES.md
docs/release/adr/0001-minimalist-monolith-boundaries.md
```

For the core rewrite, use `P0-012`. It is the owner for `ConversionQueue`, `ConversionRunner`, `PythonWorker`, and small `Domain/` models.

## Dry Run GitHub Sync

```sh
scripts/github/sync_task_issues.py
```

## Apply GitHub Sync

```sh
scripts/github/sync_task_issues.py --apply
```

The sync script creates or updates labels and creates or updates one issue per task ID. It does not close issues or mark work complete.

## Operating Rules

- Keep each issue scoped to one task ID.
- Do not edit files outside the task scope unless the issue is updated first.
- Do not mark a task complete without validation evidence.
- Update `docs/IMPLEMENTATION_PLAN.md` when P0 scope changes.
