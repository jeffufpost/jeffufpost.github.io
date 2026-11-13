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
  sed -E "s#<section#\n<section#g; s#</section>#</section>\n#g" "$1" | awk -v p="data-pillar=\"$2\"" 'index($0,p){on=1} on{print} on && /<\/section>/{exit}'
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

PLAUSIBLE_SRC='plausible.jeffreypost.dev/js/script.file-downloads.outbound-links.pageview-props.tagged-events.js'

check_analytics() {
  local f n=0
  while IFS= read -r f; do
    n=$((n+1))
    grep -qF "$PLAUSIBLE_SRC" "$f" || fail "no Plausible in $f"
    grep -qF 'G-V0G8PBVM3Y' "$f" || fail "no GA in $f"
  done < <(find _site -name '*.html' -not -path '*/site_libs/*' -not -path '*/scattered-thoughts/*')
  [ $n -gt 0 ] || fail "no html pages found"
  assert_no_grep 'G-M3QJE9ZPZT' _site
}

check_cv_link() {
  assert_grep 'class="cv-link plausible-event-name=Request\+CV"' _site/index.html
  assert_grep 'assets/cv-link\.js' _site/index.html
  assert_file _site/assets/cv-link.js
}

check_light_only() {
  assert_no_grep 'quarto-color-scheme-toggle' _site/index.html
  assert_no_grep 'quarto-color-scheme-toggle' _site/404.html
}

check_404() {
  assert_file _site/404.html
  assert_grep 'href="/(\./)?homelab/"' _site/404.html
  assert_grep 'href="/(\./)?apps/"' _site/404.html
  assert_grep 'href="/(\./)?health/"' _site/404.html
}

check_fonts_and_theme() {
  assert_grep 'family=Instrument\+Sans' _site/index.html
  assert_grep 'IBM\+Plex\+Mono' _site/index.html
  local css; css=$(ls _site/site_libs/bootstrap/bootstrap*.min.css 2>/dev/null | grep -v icons | head -1)
  [ -n "$css" ] || { fail "no bootstrap css"; return; }
  grep -qi 'f8fafc' "$css" || fail "page background #f8fafc not in theme css"
  grep -qi '16202b' "$css" || fail "text colour #16202b not in theme css"
}

# Print the HTML of one card: from its <article ... data-slug="<slug>"> to </article>
card_html() { # file slug
  sed -E "s#<article#\n<article#g; s#</article>#</article>\n#g" "$1" | awk -v s="data-slug=\"$2\"" 'index($0,s) && /<article/{on=1} on{print} on && /<\/article>/{exit}'
}
pillar_order() { grep -oE '<section class="pillar" data-pillar="[a-z]+"' "$1" | sed -E 's/.*data-pillar="([a-z]+)"/\1/' | tr '\n' ' '; }

check_rows_dev() {
  local f=_site-dev/index.html
  [ "$(pillar_order $f)" = "homelab apps health " ] || fail "pillar order is '$(pillar_order $f)'"
  assert_grep '<article class="feat" data-slug="homelab-tour"' $f
  row_html $f homelab | grep -q 'data-slug="homelab-tour"' && fail "featured post repeated in homelab row"
  [ "$(row_html $f homelab | slugs | wc -l)" -ge 1 ] || fail "homelab row has no cards"
}

check_apps_order() {
  local got; got=$(row_html _site-dev/index.html apps | slugs | tr '\n' ' ')
  [ "$got" = "dvf-map solar-ev-simulator couch-remote " ] || fail "apps row is '$got'"
}

check_chips() {
  local f=_site-dev/index.html c
  c=$(card_html $f couch-remote)
  grep -q 'data-status="planned"' <<<"$c" || fail "couch-remote not planned"
  grep -q '<span class="chip chip-planned">Planned</span>' <<<"$c" || fail "couch-remote has no Planned chip"
  grep -q '<a ' <<<"$c" && fail "planned card contains a link"
  c=$(card_html $f dvf-map)
  grep -q '<span class="chip chip-in-progress">In progress</span>' <<<"$c" || fail "dvf-map has no In progress chip"
  grep -q '<a class="card-link"' <<<"$c" || fail "dvf-map card not linked"
}

check_drafts_gone() {
  [ -e _site/homelab/homelab-tour ] && fail "draft homelab-tour rendered in production"
  assert_no_grep 'self-hosting-plausible' _site
  assert_no_grep 'homelab-tour' _site
  assert_no_grep '<section class="pillar" data-pillar="homelab"' _site/index.html
  assert_no_grep 'class="feat"' _site/index.html
}

check_no_empty_rows() {
  local f p
  for f in _site/index.html _site-dev/index.html; do
    for p in $(pillar_order $f); do
      [ "$(row_html $f $p | slugs | wc -l)" -ge 1 ] || fail "empty $p row in $f"
    done
  done
}

check_planned_page() {
  local f=_site/apps/couch-remote/index.html
  assert_file $f
  assert_grep 'Planned' $f
  assert_grep '<meta name="robots" content="noindex"' $f
  if grep -rqi 'iptv' _site --include='*.html' --include='*.xml' --include='*.json'; then fail "IPTV mentioned in site"; fi
}

check_about() {
  local f=_site/about/index.html
  assert_file $f
  assert_grep 'M\.Sc\. in Public Health' $f
  assert_grep 'contact@jeffreypost\.dev' $f
  assert_grep 'cv-link' $f
}

check_section_pages() {
  assert_file _site/homelab/index.html
  assert_file _site/apps/index.html
  assert_file _site/health/index.html
  local got; got=$(cat _site/apps/index.html | slugs | sort | tr '\n' ' ')
  [ "$got" = "couch-remote dvf-map health-data-app solar-ev-simulator " ] || fail "apps index lists '$got'"
}

check_no_nested_output() {
  [ -e _site/_site-dev ] && fail "_site-dev copied into _site"
  [ -e _site/_site ] && fail "_site copied into _site"
  [ -e _site-dev/_site ] && fail "_site copied into _site-dev"
  local stray; stray=$(find _site -path "*/scripts/*" -o -path "*/tests/*" -o -name "*.ejs.md" -o -name "_quarto*.yml" | head -3)
  [ -z "$stray" ] || fail "source files in output: $stray"
}

# Old Scattered Thoughts URLs (posts/<dir>/<file>.html) -> new /health/<dir>/<file>.html
OLD_POSTS=(
  2021-09-23-stochastic-HIV-model-fast/2021-09-23-stochastic-HIV-model-fast.html
  2021-05-05-stochastic-HIV-model/2021-05-05-stochastic-HIV-model.html
  2020-06-02-real-world/2020-06-02-real-world.html
  2020-04-15-web-scraping/2020-04-15-web-scraping.html
  2020-04-12-on-testing/2020-04-12-on-testing.html
  2020-04-02-convolution/2020-04-02-convolution.html
  2020-04-02-control-measures/2020-04-02-control-measures.html
  2020-04-01-diagnosing-R0-and-peak-infectious/2020-04-01-diagnosing-R0-and-peak-infectious.html
  2020-03-31-stochastic_model/2020-03-31-stochastic_model.html
  2020-03-25-proba-distrib/2020-03-25-proba-distrib.html
  2020-03-18-deterministic-numerical-solutions/2020-03-18-deterministic-numerical-solutions.html
  2020-03-15-compartmentalization/2020-03-15-compartmentalization.html
  2020-03-12-COVID-19-Tracker/2020-03-12-COVID-19-Tracker.html
)
# Legacy copies the old blog also served; they point at the 2021-05-05 HIV post.
LEGACY_HIV=(
  2021_05_05_stochastic_HIV_model/2021_05_05_stochastic_HIV_model.html
  2021-05-07-stochastic_HIV_model/2021-05-07-stochastic-HIV-model.html
  2021-05-07-stochastic_HIV_model/2021-05-07-stochastic_HIV_model.html
)

assert_redirect() { # old-file target-substring
  local f="_site/scattered-thoughts/$1"
  [ -f "$f" ] || { fail "no redirect page at /scattered-thoughts/$1"; return; }
  grep -qF "window.location.replace(redirect)" "$f" || fail "/scattered-thoughts/$1 is not a redirect"
  grep -qF "$2" "$f" || fail "/scattered-thoughts/$1 does not point to $2"
}

check_redirects() {
  local p
  for p in "${OLD_POSTS[@]}"; do assert_redirect "posts/$p" "health/$p"; [ -f "_site/health/$p" ] || fail "missing migrated page health/$p"; done
  for p in "${LEGACY_HIV[@]}"; do assert_redirect "posts/$p" "health/2021-05-05-stochastic-HIV-model/2021-05-05-stochastic-HIV-model.html"; done
  assert_redirect index.html "health/"
  assert_redirect about.html "about/"
}

check_local_links() {
  # every relative or root-relative src/href in rendered pages must exist
  local f dir ref target bad=0
  while IFS= read -r f; do
    dir=$(dirname "$f")
    while IFS= read -r ref; do
      ref=${ref%%#*}; ref=${ref%%\?*}
      [ -z "$ref" ] && continue
      [[ $ref =~ ^[A-Za-z0-9_./%~+-]+$ ]] || continue   # skip strings from inline scripts
      case "$ref" in http:*|https:*|mailto:*|data:*|javascript:*|//*) continue;; esac
      if [[ $ref == /* ]]; then target="_site$ref"; else target="$dir/$ref"; fi
      [[ $target == */ ]] && target="${target}index.html"
      [ -e "$target" ] || [ -e "$target/index.html" ] || { fail "broken link in $f: $ref"; bad=$((bad+1)); }
      [ $bad -gt 10 ] && return
    done < <(grep -oE '(src|href)="[^"]+"' "$f" | sed -E 's/^(src|href)="(.*)"$/\2/')
  done < <(find _site -name '*.html' -not -path '*/site_libs/*' -not -path '*/scattered-thoughts/*')
}

check_series() {
  local got
  got=$(slugs < _site/health/epidemic-modelling/index.html | tr '\n' ' ')
  [ "$got" = "2020-03-15-compartmentalization 2020-03-18-deterministic-numerical-solutions 2020-03-25-proba-distrib 2020-03-31-stochastic_model 2020-04-01-diagnosing-R0-and-peak-infectious 2020-04-02-control-measures 2020-04-02-convolution 2020-06-02-real-world " ] || fail "epidemic-modelling series is '$got'"
  got=$(slugs < _site/health/stochastic-hiv-model/index.html | tr '\n' ' ')
  [ "$got" = "2021-05-05-stochastic-HIV-model 2021-09-23-stochastic-HIV-model-fast " ] || fail "hiv series is '$got'"
}

check_health_row() {
  local got; got=$(row_html _site/index.html health | slugs | tr '\n' ' ')
  [ "$got" = "stochastic-hiv-model epidemic-modelling health-data-app " ] || fail "health row is '$got'"
  got=$(slugs < _site/health/index.html | tr '\n' ' ')
  for s in stochastic-hiv-model epidemic-modelling 2020-04-15-web-scraping 2020-04-12-on-testing 2020-03-12-COVID-19-Tracker health-data-app; do
    grep -qw -- "$s" <<<"$got" || fail "health index lacks $s"
  done
  grep -qw 2020-03-15-compartmentalization <<<"$got" && fail "series part listed on health index"
}

check_workflow() {
  local w=.github/workflows/publish.yml ver
  assert_file $w
  ver=$(grep -oE 'version [0-9]+\.[0-9]+\.[0-9]+' README.md | head -1 | cut -d' ' -f2)
  [ -n "$ver" ] || fail "no Quarto version in README"
  assert_grep 'quarto-dev/quarto-actions/setup@v2' $w
  assert_grep "version: *\"?$ver\"?" $w
  assert_grep 'actions/upload-pages-artifact@v3' $w
  assert_grep 'actions/deploy-pages@v4' $w
  assert_grep 'pages: write' $w
  assert_grep 'id-token: write' $w
  assert_no_grep 'secrets\.' $w
  [ "$(cat _site/CNAME 2>/dev/null | head -1)" = "jeffreypost.dev" ] || fail "_site/CNAME is not jeffreypost.dev"
  assert_file _site/sitemap.xml
  assert_grep '^Sitemap: https://jeffreypost.dev/sitemap.xml' _site/robots.txt
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
