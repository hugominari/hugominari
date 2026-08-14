#!/usr/bin/env bash
# The commit-convention check itself. Extracted from action.yml so it can be RUN and TESTED
# outside GitHub Actions -- action.yml now does nothing but set three env vars and call this.
# Inlined in the YAML, the only testable part was a copy of the regex, which is how a
# `git log` that exits 128 shipped as a green check.
set -euo pipefail

: "${BASE_SHA:?BASE_SHA is required}"
: "${HEAD_SHA:?HEAD_SHA is required}"
: "${PR_TITLE?PR_TITLE is required}"

# The trailing $ is load-bearing: without it .{1,60} matches a PREFIX and a
# 200-character subject passes the gate.
pattern='^(feat|fix|refactor|perf|test|docs|chore|style|ci|build|revert)(\([^)]+\))?!?: .{1,60}$'
hint='expected "<type>[(scope)][!]: <subject, 1-60 chars>". Note git revert writes "Revert \"...\"", which does NOT pass -- reword it to "revert: <original subject>".'

failed=0
if ! printf '%s' "$PR_TITLE" | grep -qE "$pattern"; then
  echo "::error::PR title is not a conventional commit: ${PR_TITLE} -- ${hint}"
  failed=1
fi

# Captured into a variable, NOT piped into the loop via `< <(...)`. Process substitution
# discards the exit status and `set -e` does not cover it, so a git log that exits 128
# (base force-pushed, shallow fetch, missing object) left `failed` at 0 and the check passed
# having read zero commits. As an assignment, `set -e` aborts here instead.
subjects="$(git log --no-merges --format=%s "${BASE_SHA}..${HEAD_SHA}")"

# --no-merges: 19g mandates --merge, so merge commits are created BY the merge and are
# exempt by construction. Every other commit lands on the integration branch verbatim.
while IFS= read -r subject; do
  [ -n "$subject" ] || continue
  if ! printf '%s' "$subject" | grep -qE "$pattern"; then
    echo "::error::commit subject is not conventional: ${subject} -- ${hint}"
    failed=1
  fi
done <<< "$subjects"

exit "$failed"
