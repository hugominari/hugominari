#!/usr/bin/env bash
# Every case runs the REAL validate.sh. Nothing here re-declares the regex, so the test
# cannot drift from the code the way an inlined-in-YAML copy could.
set -uo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
validate="$here/validate.sh"
fails=0

# Runs validate.sh over a range with no commits, so only the title is under test.
title_exit() {
  BASE_SHA=HEAD HEAD_SHA=HEAD PR_TITLE="$1" "$validate" >/dev/null 2>&1
  echo $?
}
accept() { [ "$(title_exit "$1")" = 0 ] || { echo "FAIL: should accept title: $1"; fails=1; }; }
reject() { [ "$(title_exit "$1")" = 1 ] || { echo "FAIL: should reject title: $1"; fails=1; }; }

accept "feat: add the sweeper"
accept "fix(board): stop overwriting Heartbeat"
accept "feat(api)!: drop the legacy route"
accept "revert: feat: add the sweeper"
reject "feature: add the sweeper"                 # 19i bumps on feat:, not feature:
reject "add the sweeper"
reject "feat add the sweeper"
reject "feat: "
reject 'Revert "feat: add the sweeper"'           # git revert's own subject form
reject "feat: $(printf 'x%.0s' {1..61})"          # 61 chars -> over the 60 limit
accept "feat: $(printf 'x%.0s' {1..60})"          # exactly 60 -> allowed

# A git log that cannot resolve its range must FAIL the check, not pass it having read
# nothing. This is the regression for the `< <(git log ...)` form, where process
# substitution discarded git's exit status and the step exited 0.
out="$(BASE_SHA=0000000000000000000000000000000000000000 HEAD_SHA=HEAD \
       PR_TITLE="feat: a valid title" "$validate" 2>&1)"; rc=$?
[ "$rc" -ne 0 ] || { echo "FAIL: unresolvable BASE_SHA must fail, got exit 0"; echo "$out"; fails=1; }

# Commit subjects, not just the title: a scratch repo with one good and one bad commit.
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
(
  cd "$tmp"
  git init -q . && git config user.email t@t && git config user.name t
  git commit -q --allow-empty -m "feat: the base commit"
  base="$(git rev-parse HEAD)"
  git commit -q --allow-empty -m "feat: a well formed commit"
  cd "$tmp" && BASE_SHA="$base" HEAD_SHA=HEAD PR_TITLE="feat: a valid title" "$validate" >/dev/null 2>&1 \
    || { echo "FAIL: a conventional commit in range should pass"; exit 1; }
  git commit -q --allow-empty -m "sloppy commit with no type"
  if BASE_SHA="$base" HEAD_SHA=HEAD PR_TITLE="feat: a valid title" "$validate" >/dev/null 2>&1; then
    echo "FAIL: a non-conventional commit in range should fail"; exit 1
  fi
) || fails=1

[ "$fails" -eq 0 ] && echo "commit-convention: all cases pass"
exit "$fails"
