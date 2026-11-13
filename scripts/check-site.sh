#!/usr/bin/env bash
# Build the site in two profiles and check the output.
#   _site-dev/  : --profile dev  (drafts visible)
#   _site/      : default        (drafts gone; this is what gets published)
# Usage: bash scripts/check-site.sh [check_name ...]     (SKIP_RENDER=1 reuses output)
set -u
cd "$(dirname "$0")/.."
DENYLIST=${DENYLIST:-${XDG_CONFIG_HOME:-$HOME/.config}/site-checks/denylist.txt}
FAILED=0
CURRENT=""

fail() { echo "FAIL $CURRENT: $*"; FAILED=1; CHECK_OK=0; }
assert_file()    { [ -f "$1" ] || fail "missing file $1"; }
assert_grep()    { grep -qE -- "$1" "$2" 2>/dev/null || fail "'$1' not found in $2"; }
assert_no_grep() { if grep -rqE -- "$1" "$2" 2>/dev/null; then fail "'$1' found in $2 ($(grep -rlE -- "$1" "$2" | head -3 | tr '\n' ' '))"; fi; }

# Print the HTML of one homepage row: section data-pillar=<p> ... </section>
row_html() { # file pillar
  awk -v p="data-pillar=\"$2\"" 'index($0,p){on=1} on{print} on && /<\/section>/{exit}' "$1"
}
# Card slugs in order, from stdin
slugs() { grep -oE 'class="card[^"]*" data-slug="[^"]+"' | sed -E 's/.*data-slug="([^"]+)"/\1/'; }

# ---------------------------------------------------------------- checks

check_renders() {
  assert_file _site/index.html
  assert_file _site-dev/index.html
}

check_denylist() {
  if [ ! -s "$DENYLIST" ]; then echo "SKIP $CURRENT (no denylist at $DENYLIST)"; return; fi
  local hits
  hits=$(grep -rliF -f <(grep -v '^[[:space:]]*$' "$DENYLIST") . \
         --exclude-dir=.git --exclude-dir=_site-dev --exclude-dir=.quarto --exclude-dir=site_libs 2>/dev/null)
  [ -z "$hits" ] || fail "denylisted text in: $(echo "$hits" | head -5 | tr '\n' ' ')"
}

# ---------------------------------------------------------------- runner

render() {
  mkdir -p .quarto
  [ "${SKIP_RENDER:-0}" = 1 ] && return
  quarto render --profile dev >.quarto/check-site-render-dev.log 2>&1 || { echo "render (dev) failed, see .quarto/check-site-render-dev.log"; tail -20 .quarto/check-site-render-dev.log; exit 1; }
  quarto render >.quarto/check-site-render.log 2>&1 || { echo "render failed, see .quarto/check-site-render.log"; tail -20 .quarto/check-site-render.log; exit 1; }
}

render
if [ $# -gt 0 ]; then checks=("$@"); else mapfile -t checks < <(declare -F | awk '{print $3}' | grep '^check_'); fi
for c in "${checks[@]}"; do
  CURRENT=$c; CHECK_OK=1
  "$c"
  [ $CHECK_OK = 1 ] && echo "PASS $c"
done
exit $FAILED
