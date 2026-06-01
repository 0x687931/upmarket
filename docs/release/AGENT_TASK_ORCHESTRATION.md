# Agent Task Orchestration

## Purpose

Upmarket will use multiple Codex agents for audits, implementation, tests, release validation, and documentation. This only works if tasks are small, owned, and hooked into release gates.

The goal is not more process. The goal is preventing agents from duplicating work, trampling files, or finishing code that cannot ship.

## Task Units

Every task should be an issue or checklist item with:

- `Objective`: one sentence describing the outcome.
- `Owner`: human, Codex main, or named sub-agent.
- `Scope`: files or modules the owner may edit.
- `Non-goals`: what must not be changed.
- `Acceptance`: commands, tests, or manual checks required.
- `Release Gate`: P0, Gate A, Gate B, Gate C, Gate D, Gate E, or v1.1.
- `Risk`: safety, operability, security, maintainability, UX, or App Store.

Example:

```text
Objective: Replace singleton conversion result with per-job queue state.
Owner: Codex main
Scope: Services/ConversionQueue.swift, Services/ConversionRunner.swift, Views/ShelfView.swift
Non-goals: Do not change StoreKit, paywall, or Python packaging.
Acceptance: Unit tests for two queued files; shelf displays distinct results; xcodebuild test passes.
Release Gate: P0 - Conversion Job Correctness
Risk: operability
```

## Agent Roles

Use focused roles:

- `Architect`: narrows scope and removes unnecessary abstraction.
- `Swift/App Store`: SwiftUI, StoreKit, entitlements, Info.plist, sandbox.
- `Python Runtime`: Python worker, packaging, dependency lock, model validation.
- `Security/Privacy`: file access, logging redaction, App Privacy, supply chain.
- `Operability`: CI, diagnostics, liveness, fault injection, release gates.
- `UX`: shelf, paywall, accessibility, errors, progress, onboarding.

Each agent must return findings with file references, severity, and concrete remediation.

## Parallel Work Rules

- Assign disjoint write sets before launching workers.
- Only one agent owns a file at a time.
- Agents may read anything, but edits must stay in scope.
- Main Codex integrates results and resolves conflicts.
- Do not merge a worker result unless its acceptance checks are clear.

## Labels

Use these task labels:

- `p0-blocker`
- `gate-a-build`
- `gate-b-conversion`
- `gate-c-stability`
- `gate-d-storekit`
- `gate-e-listing`
- `area-swift`
- `area-python`
- `area-security`
- `area-release`
- `area-ux`
- `agent-ready`
- `needs-human`
- `upstream-blocked`
- `upstream-watch`
- `upstream-candidate`
- `upstream-adopted`
- `upstream-rejected`

## Task Registry Automation

P0 implementation work is tracked in `docs/release/p0_task_registry.json`. Validate it locally before editing scoped tasks:

```sh
scripts/ci/validate_task_registry.py
scripts/ci/validate_p0_plan_sync.py
```

Create or update GitHub labels and task issues with:

```sh
scripts/github/sync_task_issues.py --apply
```

Run without `--apply` first to preview the labels and issues that would be touched.

## Main Codex Integration Gate

The main Codex session owns final integration. Worker output, audit findings, and GitHub issue changes are not done until the main session has:

- reconciled changed scope with `docs/release/p0_task_registry.json`;
- updated `docs/IMPLEMENTATION_PLAN.md` when P0 scope, acceptance, or completion state changes;
- run `scripts/ci/validate_task_registry.py` and `scripts/ci/validate_p0_plan_sync.py`;
- synced GitHub task issues when registry content changes;
- recorded validation evidence in the commit, issue comment, or handoff.

This gate is intentionally small: it prevents the implementation plan, registry, and GitHub issues from drifting while still keeping tasks lightweight.

## Release Hooks

Every PR should declare which hooks it affects:

- `pre-commit`: formatting, static checks, generated files unchanged.
- `pr-ci`: build, unit tests, plist, entitlements, Python import, offline smoke.
- `rc-ci`: archive, packaged app launch, StoreKit, corpus smoke, diagnostics.
- `nightly-upstream`: dependency candidate validation.
- `manual`: App Store Connect, TestFlight, screenshots, privacy answers.

Hooks are allowed to start as scripts before they are wired into GitHub Actions. A hook is not considered real until it has a command and expected output.

## Handoff Template

```md
## Agent Handoff

Objective:
Files changed:
Files intentionally not changed:
Validation run:
Validation not run:
Risks:
Next recommended task:
```

## Done Definition

A task is done only when:

- code/docs are changed within declared scope;
- tests or checks were run, or the gap is explicitly stated;
- release gate impact is updated;
- privacy and App Store implications are considered;
- no unrelated cleanup is mixed in.
