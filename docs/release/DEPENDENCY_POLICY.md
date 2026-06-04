# Dependency Policy

Upmarket treats upstream dependency changes as release changes, not routine maintenance. Scheduled jobs may report drift, but they must not promote or install new runtime versions automatically.

## States

- `current`: exact pins in `requirements.txt`; this is the only dependency state allowed for release builds.
- `candidate`: exact pins in `requirements-candidate.txt`; used for local validation of proposed upstream updates.
- `latest-upstream`: versions reported by `scripts/ci/watch_upstream.py`; informational only.

Promotion is one-way:

```text
latest-upstream -> candidate -> current
```

## Required Gates

Before a candidate can become current:

1. Link an upstream issue, pull request, release, or advisory.
2. Add or identify a local reproduction or corpus fixture.
3. Run `scripts/ci/validate_dependency_lock.py`.
4. Run `scripts/update_dependencies.sh --install-candidate`.
5. Run `scripts/ci/verify_python_bundle.sh` from the packaged app state, including native extension ABI-tag validation against the embedded Python minor version.
6. Run `scripts/ci/smoke_convert_offline.sh`.
7. Run `scripts/ci/validate_corpus.py`, `scripts/ci/validate_corpus_baseline.py`, and the relevant benchmark/corpus comparison.
8. Run `scripts/generate_licenses.sh` and review license changes.
9. Document rollback and security/privacy/App Store impact in the upstream intake issue.
10. Add an ADR for any local upstream patch, including a removal condition.

Conversion-quality changes require a corpus fixture or benchmark before adoption. Packaging, sandbox, model loading, entitlement, or network-behavior changes are P0 until proven safe.

## Script Rules

- `scripts/update_dependencies.sh --check-only` validates locks, runs `pip check`, and writes an upstream watch report.
- `scripts/update_dependencies.sh --install-current` installs only exact pins from `requirements.txt`.
- `scripts/update_dependencies.sh --install-candidate` installs only exact pins from `requirements-candidate.txt`.
- No script may write `requirements.txt` or promote candidate pins automatically.
- `scripts/ci/validate_upstream_watch_workflow.py` keeps the scheduled workflow
  wired to `scripts/ci/watch_upstream.py`, the report artifacts, and the issue
  fields for tracking mode, current version, candidate version, latest version,
  and required adoption gate.

## Local Patch Rules

Local patches to upstream code are allowed only when the patch is small, linked to upstream context, covered by validation, documented in an ADR, and has a defined removal condition.

## Fork and Cherry-Pick Rules

Forking upstream is a last-resort release control, not a normal dependency update path. Use it only when Upmarket has a release-blocking bug, a fix exists or can be made safely, and waiting for upstream would block a mission-critical release.

Preferred order:

1. Use an upstream release.
2. Use an upstream merged commit that is waiting for release.
3. Maintain a short-lived Upmarket fork branch with a cherry-picked fix.
4. Apply a tiny local patch script during packaging.
5. Reject or defer the upstream change.

A fork/cherry-pick candidate must include:

- upstream issue/PR URL and, if relevant, the Upmarket fork URL;
- exact upstream base version, fork branch, commit SHA, and patch summary;
- proof the patch was proposed upstream or a reason it cannot be proposed;
- reproducible corpus or fixture demonstrating the bug and the fix;
- dependency audit, packaged import/offline smoke, and corpus comparison results;
- license/security/privacy/App Store review;
- rollback plan to return to upstream release pins;
- ADR with removal condition, owner, and expiry/review date.

Release builds must remain reproducible. Do not depend on a floating fork branch. If a fork is adopted, pin to an immutable commit or packaged artifact and record the checksum where practical. Remove the fork as soon as the fix is available in an upstream release that passes validation.
