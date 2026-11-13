#!/usr/bin/env bash
# Tests for scripts/check-secrets.sh. Each case runs in a throwaway git repo.
set -u
here=$(cd "$(dirname "$0")/.." && pwd)
script="$here/scripts/check-secrets.sh"
fails=0

run_case() { # name expect(pass|fail) file content [grep-for-in-output]
  local name=$1 expect=$2 file=$3 content=$4 needle=${5:-}
  local tmp; tmp=$(mktemp -d)
  ( cd "$tmp" && git init -q && mkdir -p "$(dirname "$file")" && printf '%s\n' "$content" > "$file" && git add "$file" )
  local out rc
  out=$(cd "$tmp" && DENYLIST="$tmp/denylist.txt" bash "$script" 2>&1); rc=$?
  rm -rf "$tmp"
  local got=pass; [ $rc -ne 0 ] && got=fail
  if [ "$got" != "$expect" ] || { [ -n "$needle" ] && ! grep -qi -- "$needle" <<<"$out"; }; then
    echo "FAIL $name (expected $expect, got $got: $out)"; fails=$((fails+1))
  else
    echo "PASS $name"
  fi
}

run_case env_file          fail .env               'API_KEY=abc'                        '.env'
run_case nested_env        fail app/.env.local     'X=1'                                '.env.local'
run_case pem_file          fail certs/site.pem     'x'                                  'site.pem'
run_case private_key       fail notes.md           '-----BEGIN OPENSSH PRIVATE KEY-----' 'PRIVATE KEY'
run_case password_assign   fail compose.yml        'POSTGRES_PASSWORD=hunter2hunter2'   'compose.yml'
run_case github_token      fail post.md            'token ghp_abcdefghijklmnopqrstuvwxyz12' 'post.md'
run_case aws_key           fail post.md            'AKIAABCDEFGHIJKLMNOP'               'post.md'
run_case clean_file        pass index.qmd          'Hello homelab'
run_case placeholder_ok    pass compose.yml        'POSTGRES_PASSWORD=${POSTGRES_PASSWORD}'

# denylist: a forbidden word in staged content is rejected
tmp=$(mktemp -d); ( cd "$tmp" && git init -q && echo 'I worked at Acmecorp' > a.md && git add a.md && echo 'acmecorp' > deny.txt )
if (cd "$tmp" && DENYLIST="$tmp/deny.txt" bash "$script" >/dev/null 2>&1); then echo "FAIL denylist"; fails=$((fails+1)); else echo "PASS denylist"; fi
rm -rf "$tmp"

[ $fails -eq 0 ] && echo "ALL PASS" || { echo "$fails FAILED"; exit 1; }
