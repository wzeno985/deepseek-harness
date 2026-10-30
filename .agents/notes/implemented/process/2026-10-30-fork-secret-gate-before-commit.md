# Agent Note: Fork secret gate before commit

Status: implemented

English | [中文](2026-10-30-fork-secret-gate-before-commit.zh.md)

## Problem

The repository carries no mechanical secret gate. The [pre-commit hooks](../../../../lefthook.yml) check pairing records, archived notes, lint, whitespace, pi-ai metadata, and the vendor manifest, and the CI gate inventory in [run-gates.ts](../../../../scripts/run-gates.ts) contains no credential check at all. What protects credentials today is process: `.gitignore` hides `.env` and the two desktop environment files, the project instructions forbid committing credentials, and reviewers watch for them.

That posture assumes a private review loop. This fork is public, and its CI runs only the static gate set, so nothing between a staged file and a published commit inspects content for credentials. GitHub's own secret scanning covers provider-recognized patterns; its non-provider setting, which would also catch generic token-shaped strings, is off for this repository and cannot be changed through the REST API, only through the web settings page.

## Decision

`scripts/check-staged-secrets.sh` runs as a `pre-commit` job and scans staged content for credential-shaped strings: provider-style token prefixes, private-key armor blocks, and assignment forms such as `DEEPSEEK_API_KEY=` followed by a long value. It reads the index through `git grep --cached`, so it judges exactly what the commit would contain, and it reports one masked line per offending file and line before failing the commit.

Two escape hatches keep the gate usable:

- **Fixture allowlist.** Two product tests assert how credential-shaped input is masked and echoed, so their exact fixture values are allowlisted in the script. The values are assembled from pieces there, because a literal long token would make the script trip its own scan.
- **Inline marker.** Any line may carry `secret-scan: allow`, which announces a deliberate fixture or documentation example at the point a reviewer will read it.

The script deliberately reports only shapes it recognizes. It is a checkpoint against accidental commits, not a determination that a file is credential-free.

## Alternatives considered

- **Rely on GitHub secret scanning alone.** Rejected: provider patterns only, the non-provider setting is off and not settable through the API, and an alert arrives after the commit is already published to a public repository.
- **Add gitleaks or detect-secrets.** Rejected for now: both bring a dependency, a configuration file, and an update obligation for a fork whose only content changes are documentation and CI, while the shapes that matter here are few and stable.
- **Enforce the scan in CI instead of a hook.** Rejected: the fork's fast lane runs static verifiers, so a CI check would delay the signal by minutes and would not stop the content from reaching the public remote in the meantime.
- **Allowlist fixture files by path.** Rejected: a path allowlist silently weakens the gate for every future line in those files, while the value allowlist and the inline marker keep each exception visible.

## Consequences

Bought: credential-shaped content is stopped before it becomes a commit, the check reads the index rather than the working tree, and every exception is visible in the diff that introduces or uses it.

Cost: the pattern list needs extension when a new credential format matters; a long random string in a fixture or a document will fail a commit until it is marked; and the gate cannot see values that are already committed, so a leak that predates it still requires rotation.

## Testing

- The gate was exercised against four staged cases before landing: the script itself, a staged file containing a key-shaped assignment, the two repository fixture files, and a line carrying the inline marker. The first, third, and fourth pass; the second reports one masked line and exits non-zero.
