<%
// Featured post: the first item with `featured: true`, or nothing.
const esc = (s) => String(s == null ? "" : s).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;");
const slugOf = (item) => { const parts = String(item.path || "").replace(/\/index\.(html|qmd|ipynb)$/, "").replace(/\.(html|qmd|ipynb)$/, "").split("/").filter(Boolean); return parts.length ? parts[parts.length - 1] : ""; };
const labels = { homelab: "Homelab", apps: "Apps", health: "Health" };
const colours = { homelab: "var(--c-homelab)", apps: "var(--c-apps)", health: "var(--c-health)" };
const unfinished = (it) => ["planned", "coming-soon", "in-progress"].includes(it.status);
const item = items.find((it) => (it.featured === true || it.featured === "true") && !unfinished(it));
let html = "";
if (item) {
  const art = item.image ? `<div class="art"><img src="${esc(item.image)}" alt="" loading="lazy"></div>` : `<div class="art"></div>`;
  const kicker = `<span class="kicker" style="color:${colours[item.pillar] || "inherit"}">Featured${labels[item.pillar] ? " · " + labels[item.pillar] : ""}</span>`;
  const rt = item["reading-time"] ? `<div class="meta" style="margin-top:.6rem"><span>${esc(item["reading-time"])}</span></div>` : "";
  html = `<article class="feat" data-slug="${esc(slugOf(item))}">${art}<div>${kicker}<h2><a class="feat-link" href="${esc(item.path)}">${esc(item.title)}</a></h2>${item.description ? `<p>${esc(item.description)}</p>` : ""}${rt}</div></article>`;
}
%>

```{=html}
<%= html %>
```
