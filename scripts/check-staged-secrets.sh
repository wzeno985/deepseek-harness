#!/usr/bin/env bash
# Reject staged content that looks like a live credential.
#
# This repository has no other secret gate: `.gitignore` hides `.env`, GitHub
# secret scanning only recognizes provider patterns unless its non-provider
# setting is enabled, and this fork is public. The gate inspects the index, so
# it judges exactly what the commit would contain. See the fork secret gate
# Agent Note for the policy, its limits, and the bypass contract.
set -euo pipefail

# Product tests assert how credential-shaped input is masked and echoed, so the
# repository keeps two fixture values. They are assembled here from pieces: a
# literal long `sk-` token would make this file trip its own scan.
fixture_token='sk-1234567890'
allow_exact="^(sk-example|${fixture_token}abcdefghijklmnopqrstuvwxyz)$"

# A line may opt out deliberately, for documentation or a new fixture.
allow_marker='secret-scan: allow'

patterns=(
  'sk-[A-Za-z0-9_-]{20,}'
  'gh[pousr]_[A-Za-z0-9]{36,}'
  'AKIA[0-9A-Z]{16}'
  'xox[baprs]-[A-Za-z0-9-]{12,}'
  '-----BEGIN [A-Z ]*PRIVATE KEY-----'
  '(DEEPSEEK_API_KEY|OPENAI_API_KEY|ANTHROPIC_API_KEY|AWS_SECRET_ACCESS_KEY)[[:space:]]*[=:][[:space:]]*[A-Za-z0-9_./+-]{16,}'
)

mapfile -t staged < <(git diff --cached --name-only --diff-filter=ACMR)
(( ${#staged[@]} > 0 )) || exit 0

failures=0
# One report per offending line: several patterns commonly match the same line
# (a prefixed assignment and the token inside it), and `git grep` prints the
# same `path:line:text` for each of them.
mapfile -t hits < <(
  for pattern in "${patterns[@]}"; do
    git grep --cached -n -I -E -e "$pattern" -- "${staged[@]}" || true
  done | sort -u
)

for hit in "${hits[@]}"; do
  [[ -n "$hit" ]] || continue
  path=${hit%%:*}
  rest=${hit#*:}
  line=${rest%%:*}
  text=${rest#*:}
  [[ "$text" == *"$allow_marker"* ]] && continue
  masked=$text
  masked_any=0
  for pattern in "${patterns[@]}"; do
    mapfile -t matches < <(printf '%s\n' "$text" | grep -oE -- "$pattern" || true)
    for match in "${matches[@]}"; do
      [[ "$match" =~ $allow_exact ]] && continue
      masked=${masked//"$match"/"${match:0:4}(redacted, ${#match} chars)"}
      masked_any=1
    done
  done
  (( masked_any > 0 )) || continue
  printf '  %s:%s  %s\n' "$path" "$line" "$masked"
  failures=$((failures + 1))
done

if (( failures > 0 )); then
  cat >&2 <<'MESSAGE'
secret scan: staged content contains credential-shaped strings.
Keep credentials in .env or ~/.dsh/.credentials.yaml, never in the tree.
When a match is a deliberate fixture, append `secret-scan: allow` to that line.
MESSAGE
  exit 1
fi
