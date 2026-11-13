#!/usr/bin/env bash
# Pre-commit guard: refuse to commit secrets or forbidden strings.
# Scans the names and the added lines of everything staged.
# Install locally with:  printf '#!/bin/sh\nexec bash scripts/check-secrets.sh\n' > .git/hooks/pre-commit && chmod +x .git/hooks/pre-commit
# Optional denylist (one fixed string per line, kept OUTSIDE the repo):
#   DENYLIST=/path/to/denylist.txt, default ~/.config/site-checks/denylist.txt
set -u
denylist=${DENYLIST:-${XDG_CONFIG_HOME:-$HOME/.config}/site-checks/denylist.txt}
problems=()

name_re='(^|/)\.env|\.pem$|\.key$|\.p12$|(^|/)id_(rsa|ed25519)'
while IFS= read -r f; do
  [ -z "$f" ] && continue
  if grep -qE "$name_re" <<<"$f"; then problems+=("forbidden file: $f"); fi
done < <(git diff --cached --name-only --diff-filter=ACMR)

# High-confidence patterns: checked on every added line.
strong_re='-----BEGIN [A-Z ]*PRIVATE KEY-----|ghp_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}|AKIA[0-9A-Z]{16}'
# Loose "password=..." style pattern: skipped on minified lines (>1000 chars),
# e.g. plotting libraries embedded in notebook outputs, where it only hits identifiers.
loose_re='(api[_-]?key|secret|token|passwd|password)[A-Za-z_]*[[:space:]]*[:=][[:space:]]*[^[:space:]$]{8,}'

# Added lines, tagged with their file: "file<TAB>line"
added=$(git diff --cached -U0 --diff-filter=ACMR | awk '
  /^\+\+\+ b\// { file = substr($0, 7); next }
  /^\+/ && !/^\+\+\+/ { print file "\t" substr($0, 2) }')

if [ -n "$added" ]; then
  while IFS= read -r hit; do problems+=("possible secret: $hit"); done \
    < <( { grep -E -- "$strong_re" <<<"$added"; grep -iE -- "$loose_re" <<<"$added" | awk 'length($0) <= 1000'; } | sort -u | grep -v '^scripts/check-secrets\.sh	' | grep -v '^tests/check_secrets_test\.sh	' | cut -c1-160)
  if [ -s "$denylist" ]; then
    while IFS= read -r hit; do problems+=("denylisted text in: ${hit%%	*}"); done \
      < <(grep -iF -f <(grep -v '^[[:space:]]*$' "$denylist") <<<"$added")
  fi
fi

if [ ${#problems[@]} -gt 0 ]; then
  echo "check-secrets: commit refused" >&2
  printf '  %s\n' "${problems[@]}" >&2
  exit 1
fi
exit 0
