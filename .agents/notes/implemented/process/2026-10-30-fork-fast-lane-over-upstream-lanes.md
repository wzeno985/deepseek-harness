# Agent Note: Fork fast lane over upstream PR lanes

Status: implemented

English | [中文](2026-10-30-fork-fast-lane-over-upstream-lanes.zh.md)

## Problem

This repository's pull-request lanes target organization-owned runner pools — `dsh-ubuntu-24-04-16core` in [CI](../../../../.github/workflows/ci.yml) and `dsh-windows-2025-16core` in [CI Windows](../../../../.github/workflows/ci-windows.yml) — and several workflows depend on organization integrations or secrets: `issue-policy`, `issue-lifecycle`, `weighted-approval`, `pr-check-*`, the Cloudflare preview build, and the real-API e2e suite. A personal fork owns none of that capacity: every lane queues indefinitely on a label the account cannot provide, and the integration workflows fail as soon as they start.

The fork is not a scratch copy. It exists to run this project's own gates against real changes, so it needs a pull-request signal that actually executes on hardware a personal account owns, while keeping the upstream lane definitions intact enough to re-enable one when its capacity becomes available.

## Decision

Four parts: hosted fallbacks, one fast lane, an advisory benchmark lane, and repository-level disablement.

- **Hosted fallbacks.** The final fallback in `ci.yml` (four jobs) and `ci-windows.yml` (three jobs) resolves to `ubuntu-24.04` and `windows-2025`. The `blacksmith` and `selfhosted` branches are unchanged, so any upstream lane runs as written on hosted capacity once its workflow is enabled again.
- **Fast lane.** [Fork fast checks](../../../../.github/workflows/fork-fast-checks.yml) runs on `ubuntu-24.04`: `pnpm run check:ci:static` (the verifier gate set) followed by `scripts/ci-workflow.spec.ts`. Observed wall clock is about eight minutes (8m03s and 8m22s across two runs).
- **Advisory benchmark.** `node-24-bench` carries `continue-on-error: true` on the fork. Measured medians on the shared hosted pool exceed the tightest budgets: 82.55 ms and 87.48 ms against an 80 ms budget for `conversation-fold/streaming-reasoning-leading-whitespace-16384`, and 30.82 ms against 30 ms for the 4096 case.
- **Repository-level disablement.** Workflow enablement is repository metadata, not file content. Enabled: `fork-fast-checks` and `pr-check-on-base-branch`, whose jobs are variable-gated and report as skipped. Disabled: `ci`, `ci-windows`, `ci-python`, `e2e`, `ci-master`, `sandbox`, `build-preview-cloudflare`, `issue-lifecycle`, `issue-policy`, `weighted-approval`, `weighted-approval-review-event`, `pr-check-after-approve`, `pr-check-on-head-branch`, `release`, and `release-vendor`.

That state drifts without a commit: enabling a workflow in the web interface, or changing a workflow file on the default branch, restores a disabled workflow. The fast lane is the intended signal, so a pull request that starts heavier lanes than expected means the enabled list needs re-checking rather than the workflow needing new code.

## Guard-spec coupling

`scripts/ci-workflow.spec.ts` pins the properties this decision changes: the fallback labels of the Linux and Windows lanes, and that `node-24-bench` is not advisory. The fork's expectations therefore differ from upstream in exactly those assertions, and the file states why at each one.

The static gate set is a list of verifier scripts and never loads `scripts/**/*.spec.ts`, so a workflow or guard regression reaches the unit lane. That lane is disabled here, which is why the fast lane runs `scripts/ci-workflow.spec.ts` directly instead of relying on `check:ci:static`.

## Alternatives considered

- **Trim jobs inside `ci.yml`.** Rejected: the guard spec pins each job's `if` and fallback label, so a trim rewrites the guard and hides the fact that the upstream lanes still run as written. A separate workflow keeps both facts true.
- **Scale the benchmark budgets from an environment variable.** Rejected: the benchmark contract requires reviewed source constants and forbids environment overrides, so the fork cannot adjust budgets at run time.
- **Edit the workflow files to delete the heavy lanes.** Rejected: enabled state is repository metadata, so deleting jobs would add permanent file divergence for a result that a repository-level disable already provides.
- **Run the whole `scripts/` suite in the fast lane.** Rejected: the suite is calibrated for a larger runner, and local parallel load produced 21 unrelated failures in specs that pass individually. The guard spec is the invariant class that actually bit this fork.
- **Register a self-hosted laptop runner.** Deferred: a modern laptop's single-thread performance would restore the benchmark gate, but a public fork executes pull-request code on any registered runner, and a laptop sleeps.

## Consequences

Bought: every pull request gets a real signal in about eight minutes on capacity a personal account owns; the upstream lane definitions remain runnable unchanged; and the guard spec keeps the fork's CI configuration honest.

Cost: the unit, coverage, snapshot, Windows, Python, and benchmark lanes no longer gate anything. A regression they would catch surfaces only after its workflow is re-enabled or the suite runs locally, and the fast lane deliberately covers one invariant class rather than the suite.

The named instance of that cost: the advisory benchmark change merged without updating the guard spec, which then failed on the default branch because no enabled lane loads `scripts/**/*.spec.ts`. The follow-up corrected the expectation and moved the spec into the fast lane.

## Testing

- `pnpm exec vitest run scripts/ci-workflow.spec.ts` — 68 of 68 pass, locally and on the merged default branch.
- `fork / static` — 8m03s and 8m22s on hosted `ubuntu-24.04`, the second run including the guard-spec step.
