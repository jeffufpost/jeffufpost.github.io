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

check_rows() {
  local f
  for f in _site/index.html _site-dev/index.html; do
    [ "$(pillar_order $f)" = "homelab apps health " ] || fail "pillar order in $f is '$(pillar_order $f)'"
    # the featured slot shows the first written post
    assert_grep '<article class="feat" data-slug="securing-the-homelab">' $f
    assert_grep 'class="feat".*href="(/|\./)?homelab/securing-the-homelab/' $f
  done
}

check_apps_order() {
  local got; got=$(row_html _site-dev/index.html apps | slugs | tr '\n' ' ')
  [ "$got" = "toiture-solaire dvf-map solar-ev-simulator " ] || fail "apps row is '$got'"
}

check_chips() {
  local f=_site-dev/index.html c
  c=$(card_html $f toiture-solaire)
  grep -q '<span class="chip chip-live">Live</span>' <<<"$c" || fail "toiture-solaire has no Live chip"
  grep -q '<a class="card-link"' <<<"$c" || fail "toiture-solaire card not linked"
  c=$(card_html _site-dev/apps/index.html couch-remote)   # off the homepage row since toiture-solaire
  grep -q 'data-status="planned"' <<<"$c" || fail "couch-remote not planned"
  grep -q '<span class="chip chip-planned">Planned</span>' <<<"$c" || fail "couch-remote has no Planned chip"
  grep -q '<a ' <<<"$c" && fail "planned card contains a link"
  c=$(card_html $f dvf-map)
  grep -q '<span class="chip chip-in-progress">In progress</span>' <<<"$c" || fail "dvf-map has no In progress chip"
  grep -q '<a class="card-link"' <<<"$c" || fail "dvf-map card not linked"
}

check_coming_soon() {
  local f=_site/index.html s c got
  got=$(row_html $f homelab | slugs | tr "\n" " ")
  # written posts first, then coming-soon; limit 3, featured post excluded
  [ "$got" = "homelab-tour self-hosting-plausible tls-and-cloudflare-access " ] || fail "homelab row is '$got'"
  c=$(card_html $f tls-and-cloudflare-access)
  grep -q 'data-status="coming-soon"' <<<"$c" || fail "tls-and-cloudflare-access is not coming-soon"
  grep -q '<span class="chip chip-coming-soon">Coming soon</span>' <<<"$c" || fail "tls-and-cloudflare-access has no Coming soon chip"
  grep -q '<a ' <<<"$c" && fail "coming-soon card tls-and-cloudflare-access is linked"
  assert_grep '<meta name="robots" content="noindex"' _site/homelab/tls-and-cloudflare-access/index.html
  assert_no_grep 'Draft\.' _site/homelab/tls-and-cloudflare-access/index.html
}

check_new_homelab_posts() {
  local s f n
  for s in underfloor-heating-home-assistant self-hosting-plausible homelab-tour; do
    f=_site/homelab/$s/index.html
    assert_file $f
    [ -f $f ] || continue
    assert_no_grep 'name="robots" content="noindex"' $f
    assert_no_grep 'chip-coming-soon' $f
    assert_grep 'contact@jeffreypost\.dev' $f
    if grep -oE '192\.168\.[0-9]+\.[0-9]+' $f | grep -vqx '192\.168\.1\.10'; then fail "real-looking LAN IP in $f"; fi
    assert_no_grep '/mount/|/home/|cloudflareaccess\.com' $f
    assert_no_grep '(PASSWORD|SECRET|KEY)[A-Z_]*[=:][ "'"'"']*[A-Za-z0-9+/]{6,}' $f
    grep -q '<article class="card[^"]*" data-slug="'$s'"' _site/homelab/index.html || fail "$s not listed on the homelab page"
  done
  f=_site/homelab/underfloor-heating-home-assistant/index.html
  n=$(grep -o 'class="plotly-graph-div' $f | wc -l); [ "$n" -eq 3 ] || fail "heating post has $n figures, expected 3"
  [ "$(grep -o 'plotly-2\.35\.2\.min\.js' $f | wc -l)" -eq 1 ] || fail "plotly not loaded exactly once in $f"
  [ "$(grep -o 'role="tab"' $f | wc -l)" -eq 3 ] || fail "heating post should have 3 figure tabs"
  f=_site/homelab/self-hosting-plausible/index.html
  n=$(grep -o 'class="plotly-graph-div' $f | wc -l); [ "$n" -eq 1 ] || fail "plausible post has $n figures, expected 1"
  f=_site/homelab/homelab-tour/index.html
  [ "$(grep -o '<section>' $f | wc -l)" -ge 7 ] || fail "tour stack grid has fewer than 7 groups"
  assert_grep '<article class="feat" data-slug="securing-the-homelab">' _site/index.html
}

check_security_post() {
  local f=_site/homelab/securing-the-homelab/index.html id
  assert_file $f
  [ -f $f ] || return
  assert_no_grep 'name="robots" content="noindex"' $f
  assert_grep '<svg[^>]*role="img"' $f
  # every in-page link in the diagram lands on a real section
  for id in $(grep -oE 'href="#[A-Za-z0-9_-]+"' $f | sed -E 's/href="#(.*)"/\1/' | sort -u); do
    grep -qE "id=\"$id\"" $f || fail "diagram/link target #$id has no id in $f"
  done
  [ "$(grep -oE 'class="netlink"' $f | wc -l)" -ge 5 ] || fail "diagram has fewer than 5 linked boxes"
  # sanitised configs: placeholder LAN IP and token only
  if grep -oE '192\.168\.[0-9]+\.[0-9]+' $f | grep -vqx '192\.168\.1\.10'; then fail "real-looking LAN IP in $f"; fi
  assert_no_grep 'TUNNEL_TOKEN[=:][ "'"'"']*[A-Za-z0-9_-]{20,}' $f
  assert_no_grep '(PASSWORD|SECRET)[A-Z_]*[=:][ "'"'"']*[A-Za-z0-9]{6,}' $f
}

check_thesis_post() {
  local d=_site/health/hiv-ssa-thesis f=_site/health/hiv-ssa-thesis/index.html
  assert_file $f
  assert_file $d/thesis.pdf
  [ -f $f ] || return
  assert_no_grep 'name="robots" content="noindex"' $f
  [ "$(grep -o 'class="plotly-graph-div' $f | wc -l)" -ge 5 ] || fail "fewer than 5 interactive figures in $f"
  [ "$(grep -o 'plotly-2\.35\.2\.min\.js' $f | wc -l)" -eq 1 ] || fail "plotly.js must be loaded exactly once (pinned 2.35.2) in $f"
  assert_no_grep 'plotly\.js v[0-9]' $f
  assert_grep "Revisiting my master" $f
  assert_grep 'href="thesis\.pdf"' $f
  assert_grep 'subject=Thesis%20code%20request' $f
  assert_grep 'stochastic-hiv-model' $f
  assert_grep 'Three changes were needed' $f
  assert_grep 'male circumcision and attitudes to wife beating along the second' $f
  assert_grep 'fell only slowly until about 1995' $f
  assert_no_grep 'Two changes were needed' $f
  assert_grep 'id="correction"' $f
  assert_grep '0\.276' $f
  assert_grep 'hiv-ssa-thesis/#correction' _site/health/hiv-ssa-after-2019/index.html
  [ "$(grep -o 'role="tab"' $f | wc -l)" -eq 11 ] || fail "expected 11 figure tabs in $f"
  assert_no_grep 'the menu' $f
  assert_grep '\.thesis-tabs button\[aria-selected=.?true.?\]' "$(ls _site/site_libs/bootstrap/bootstrap-*.min.css | head -1)"
  assert_grep 'hiv-ssa-thesis' _site/health/stochastic-hiv-model/index.html
  assert_no_grep '342-576|/mount/|/home/' $d
  # not featured: the homelab security post keeps the slot
  assert_grep '<article class="feat" data-slug="securing-the-homelab">' _site/index.html
}

check_followup_post() {
  local d=_site/health/hiv-ssa-after-2019 f=_site/health/hiv-ssa-after-2019/index.html
  assert_file $f
  [ -f $f ] || return
  assert_no_grep 'name="robots" content="noindex"' $f
  [ "$(grep -o 'class="plotly-graph-div' $f | wc -l)" -ge 5 ] || fail "fewer than 5 interactive figures in $f"
  [ "$(grep -o 'plotly-2\.35\.2\.min\.js' $f | wc -l)" -eq 1 ] || fail "plotly.js must be loaded exactly once (pinned 2.35.2) in $f"
  assert_no_grep 'plotly\.js v[0-9]' $f
  [ "$(grep -o 'role="tab"' $f | wc -l)" -eq 11 ] || fail "expected 11 figure tabs in $f"
  assert_grep 'What happened after 2019' $f
  assert_grep 'subject=Thesis%20code%20request' $f
  assert_grep 'href="../hiv-ssa-thesis/' $f
  assert_grep 'Liberia' $f
  assert_grep 'no newer' $f
  assert_grep 'COVID-19' $f
  # numbers quoted in the prose (from the local numbers script)
  assert_grep '1\.08' $f
  assert_grep '48%' $f
  assert_grep '47%' $f
  assert_grep '6 of 28' $f
  assert_grep 'hiv-ssa-after-2019' _site/health/hiv-ssa-thesis/index.html
  assert_no_grep '/mount/|/home/' $d
  assert_grep '<article class="feat" data-slug="securing-the-homelab">' _site/index.html
}

check_no_construction_notice() {
  assert_no_grep '<p class="notice">' _site/index.html
  assert_no_grep 'under construction' _site/index.html
}

check_toiture_solaire() {
  local f=_site/apps/toiture-solaire/index.html
  assert_file $f
  assert_file _site/apps/toiture-solaire/thumb.png
  assert_file _site/apps/toiture-solaire/art-map.jpg
  assert_file _site/apps/toiture-solaire/art-plan.jpg
  assert_grep 'chip-live' $f
  assert_grep 'href="https://toiture-solaire\.jeffreypost\.dev"' $f
  assert_grep 'plausible-event-name=Open\+Toiture\+solaire' $f
  assert_grep 'class="math display"' $f
  assert_grep 'Sources' $f
  assert_no_grep 'noindex' $f
  assert_grep 'data-slug="toiture-solaire" data-status="live"' _site/index.html
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
  [ "$got" = "couch-remote dvf-map health-data-app solar-ev-simulator toiture-solaire " ] || fail "apps index lists '$got'"
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
  [ "$got" = "hiv-mixing measles-elimination-model health-data-app " ] || fail "health row is '$got'"
  got=$(slugs < _site/health/index.html | tr '\n' ' ')
  for s in hiv-mixing measles-elimination-model health-aid-cuts-exposure overdose-decline-moving-west hiv-ssa-after-2019 hiv-ssa-thesis stochastic-hiv-model epidemic-modelling 2020-04-15-web-scraping 2020-04-12-on-testing 2020-03-12-COVID-19-Tracker health-data-app; do
    grep -qw -- "$s" <<<"$got" || fail "health index lacks $s"
  done
  grep -qw 2020-03-15-compartmentalization <<<"$got" && fail "series part listed on health index"
}

check_new_health_posts() {
  # slug:figures:tabs, then a few numbers quoted in each post (from the local numbers scripts)
  local spec s figs tabs f
  for spec in measles-elimination-model:4:9 health-aid-cuts-exposure:3:5 overdose-decline-moving-west:4:6; do
    IFS=: read -r s figs tabs <<<"$spec"
    f=_site/health/$s/index.html
    assert_file $f
    [ -f $f ] || continue
    assert_no_grep 'name="robots" content="noindex"' $f
    [ "$(grep -o 'class="plotly-graph-div' $f | wc -l)" -eq "$figs" ] || fail "$s should have $figs interactive figures"
    [ "$(grep -o 'role="tab"' $f | wc -l)" -eq "$tabs" ] || fail "$s should have $tabs figure tabs"
    [ "$(grep -o 'plotly-2\.35\.2\.min\.js' $f | wc -l)" -eq 1 ] || fail "plotly.js must be loaded exactly once (pinned 2.35.2) in $f"
    assert_no_grep 'plotly\.js v[0-9]' $f
    assert_grep 'code%20request' $f
    assert_grep 'What it can' $f
    assert_grep 'id="sources"' $f
    [ "$(sed -n '/id="sources"/,$p' $f | grep -o 'href="https://' | wc -l)" -ge 6 ] || fail "$s lists fewer than 6 source links"
    assert_no_grep '/mount/|/home/' _site/health/$s
    assert_file _site/health/images/covers/$s.svg
  done
  f=_site/health/measles-elimination-model/index.html
  assert_grep '92\.4%' $f; assert_grep '5,087' $f; assert_grep '8\.8%' $f; assert_grep 'epidemic-modelling' $f
  f=_site/health/health-aid-cuts-exposure/index.html
  assert_grep '38%' $f; assert_grep '131 million' $f; assert_grep '46%' $f; assert_grep 'hiv-ssa-after-2019' $f
  f=_site/health/overdose-decline-moving-west/index.html
  assert_grep '112,418' $f; assert_grep '65,724' $f; assert_grep '5\.8 years' $f; assert_grep 'hiv-ssa-thesis' $f
  # not featured: the homelab security post keeps the slot
  assert_grep '<article class="feat" data-slug="securing-the-homelab">' _site/index.html
}

check_hiv_mixing() {
  local d=_site/health/hiv-mixing f=_site/health/hiv-mixing/index.html
  assert_file $f
  [ -f $f ] || return
  assert_no_grep 'name="robots" content="noindex"' $f
  [ "$(grep -o 'class="plotly-graph-div' $f | wc -l)" -eq 5 ] || fail "hiv-mixing should have 5 interactive figures"
  [ "$(grep -o 'role="tab"' $f | wc -l)" -eq 7 ] || fail "hiv-mixing should have 7 figure tabs"
  [ "$(grep -o 'plotly-2\.35\.2\.min\.js' $f | wc -l)" -eq 1 ] || fail "plotly.js must be loaded exactly once (pinned 2.35.2) in $f"
  assert_no_grep 'plotly\.js v[0-9]' $f
  assert_grep 'class="math' $f
  assert_grep 'id="sources"' $f
  [ "$(sed -n '/id="sources"/,$p' $f | grep -o 'href="https://' | wc -l)" -ge 6 ] || fail "hiv-mixing lists fewer than 6 source links"
  assert_grep 'code%20request' $f
  local s
  for s in hiv-ssa-thesis hiv-ssa-after-2019 stochastic-hiv-model measles-elimination-model 2020-03-15-compartmentalization; do assert_grep "$s" $f; done
  # numbers quoted in the prose (from the local numbers script)
  assert_grep '56%' $f; assert_grep '0\.128' $f
  assert_no_grep 'settles around <strong>64%|peaks higher the more uneven|would have to come from' $f; assert_grep '0\.047' $f; assert_grep '0\.83' $f
  assert_no_grep '/mount/|/home/|/zpool' $d
  assert_file _site/health/images/covers/hiv-mixing.svg
  assert_grep '<article class="feat" data-slug="securing-the-homelab">' _site/index.html
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

check_home_single_headline() {
  # Quarto always emits an empty header element; it must stay empty
  grep -oE '<header id="title-block-header"[^>]*>.{0,40}' _site/index.html | grep -vqE '>(</header>)?$' && fail "homepage title block has content"
  local n; n=$(grep -o '<h1' _site/index.html | wc -l)
  [ "$n" -eq 1 ] || fail "homepage has $n <h1> elements"
}

check_gitignore_keeps_posts() {
  local p
  for p in homelab/secrets-management/index.qmd homelab/managing-secrets-with-sops/index.qmd health/token-bucket/index.qmd; do
    git check-ignore -q "$p" && fail ".gitignore would hide $p"
  done
  for p in .env app/.env.local secrets.env deploy/server.key; do
    git check-ignore -q "$p" || fail ".gitignore does not cover $p"
  done
}

check_series_card_meta() {
  local c
  c=$(card_html _site/health/index.html epidemic-modelling)  # off the homepage row since the thesis post
  grep -q 'min</span>' <<<"$c" && fail "series card shows a reading time"
  grep -q '<span>8 parts · 2020</span>' <<<"$c" || fail "series card does not say '8 parts · 2020'"
  c=$(card_html _site/health/index.html stochastic-hiv-model)  # off the homepage row since the follow-up post
  grep -q '<span>2 parts · 2021</span>' <<<"$c" || fail "hiv series card does not say '2 parts · 2021'"
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
