<%
// One template for every row and section page.
// template-params (all optional):
//   pillar: homelab|apps|health   keep items with this pillar
//   kind: app                     keep apps only
//   series: <id>                  show only that series (in the order given by the listing's sort)
//   limit: 3                      0 or missing = no limit; 3 also applies the placeholder slot rule
//   exclude-featured: true
//   heading, blurb, more-href, more-text   row header (only rendered when heading is set)
//   section: homelab|apps|health  colour scheme when pillar is not set
// Items arrive sorted by date desc (or asc for series) from the listing's `sort`.
const p = templateParams || {};
const esc = (s) => String(s == null ? "" : s).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;");
const slugOf = (item) => { const parts = String(item.path || "").replace(/\/index\.(html|qmd|ipynb)$/, "").replace(/\.(html|qmd|ipynb)$/, "").split("/").filter(Boolean); return parts.length ? parts[parts.length - 1] : ""; };
const statusOf = (item) => item.status || "published";
const rank = { published: 0, live: 0, "in-progress": 1, planned: 2 };

function selectItems(all) {
  let xs = all.filter((it) => !p.pillar || it.pillar === p.pillar);
  if (p.kind) xs = xs.filter((it) => it.kind === p.kind);
  if (p.series) return xs.filter((it) => it.series === p.series && !it["series-page"]);
  xs = xs.filter((it) => !it.series || it["series-page"]);
  if (p["exclude-featured"]) xs = xs.filter((it) => !it.featured);
  const done = xs.filter((it) => rank[statusOf(it)] === 0);
  const wip = xs.filter((it) => statusOf(it) === "in-progress");
  const planned = xs.filter((it) => statusOf(it) === "planned");
  const pending = wip.concat(planned);
  let out = done.concat(pending);
  const limit = Number(p.limit || 0);
  if (limit > 0) {
    // Slot rule: with a 3-card row, keep the last slot for the first unfinished item.
    if (limit === 3 && pending.length > 0 && done.length >= 3) out = done.slice(0, 2).concat(pending.slice(0, 1));
    out = out.slice(0, limit);
  }
  return out;
}

const chosen = selectItems(items);
const section = p.pillar || p.section || "";
const chipText = { live: "Live", "in-progress": "In progress", planned: "Planned" };

function meta(item) {
  const bits = [];
  const st = statusOf(item);
  if (chipText[st]) bits.push(`<span class="chip chip-${st}">${chipText[st]}</span>`);
  if (Array.isArray(item.stack) && item.stack.length) bits.push(`<span>${item.stack.map(esc).join(" · ")}</span>`);
  else if (item.kind !== "app") {
    if (item["reading-time"]) bits.push(`<span>${esc(item["reading-time"])}</span>`);
    else if (item.date) bits.push(`<span>${esc(String(item.date).slice(-4))}</span>`);
  }
  return bits.length ? `<div class="meta">${bits.join("")}</div>` : "";
}

function card(item) {
  const st = statusOf(item);
  const title = st === "planned"
    ? `<h3>${esc(item.title)}</h3>`
    : `<h3><a class="card-link" href="${esc(item.path)}">${esc(item.title)}</a></h3>`;
  const art = item.image && st !== "planned"
    ? `<div class="art"><img src="${esc(item.image)}" alt="" loading="lazy"></div>`
    : `<div class="art"></div>`;
  const desc = item.description ? `<p>${esc(item.description)}</p>` : "";
  return `<article class="card" data-slug="${esc(slugOf(item))}" data-status="${esc(st)}">${art}<div class="body">${title}${desc}${meta(item)}</div></article>`;
}

let html = "";
if (chosen.length > 0) {
  let head = "";
  if (p.heading) {
    const more = p["more-href"] ? `<a href="${esc(p["more-href"])}">${esc(p["more-text"] || "See all →")}</a>` : "";
    head = `<div class="phead"><h2>${esc(p.heading)}</h2>${p.blurb ? `<p>${esc(p.blurb)}</p>` : ""}${more}</div>`;
  }
  html = `<section class="pillar" data-pillar="${esc(section)}">${head}<div class="cards">${chosen.map(card).join("")}</div></section>`;
}
%>

```{=html}
<%= html %>
```
