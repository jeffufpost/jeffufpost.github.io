// Run with: quarto run tests/cv_link_test.ts
// Loads assets/cv-link.js in a minimal fake browser and checks cvSubject()
// and the link rewriting. Exits non-zero on any failure.
const here = new URL(".", import.meta.url);
const src = await Deno.readTextFile(new URL("../assets/cv-link.js", here));

type Link = { classList: { contains: (c: string) => boolean }; href: string; listeners: Array<() => void>; addEventListener: (e: string, f: () => void) => void; textContent: string };

function load(search: string, stored: Record<string, string> = {}) {
  const store: Record<string, string> = { ...stored };
  const added: string[] = [];
  const link: Link = {
    classList: { contains: (c) => c === "cv-link", add: (...cs: string[]) => { added.push(...cs); } },
    href: "mailto:contact@jeffreypost.dev?subject=CV%20request",
    listeners: [],
    addEventListener(_e, f) { this.listeners.push(f); },
    textContent: "Request CV",
  };
  const gtagCalls: unknown[][] = [];
  const win: Record<string, unknown> = {
    location: { search },
    sessionStorage: { getItem: (k: string) => store[k] ?? null, setItem: (k: string, v: string) => { store[k] = v; } },
    gtag: (...a: unknown[]) => gtagCalls.push(a),
  };
  const doc = {
    readyState: "complete",
    querySelectorAll: (sel: string) => (sel.includes("cv-link") && sel.includes('a[href^="mailto:contact@jeffreypost.dev?subject=CV"]') ? [link] : []),
    addEventListener: () => {},
  };
  const fn = new Function("window", "document", "location", "sessionStorage", "gtag", src + "\nreturn typeof cvSubject === 'function' ? cvSubject : window.cvSubject;");
  const cvSubject = fn(win, doc, win.location, win.sessionStorage, win.gtag) as (r: string | null) => string;
  return { cvSubject, link, store, gtagCalls, added };
}

let failures = 0;
function eq(name: string, got: unknown, want: unknown) {
  if (got === want) console.log(`PASS ${name}`);
  else { console.log(`FAIL ${name}: got ${JSON.stringify(got)}, want ${JSON.stringify(want)}`); failures++; }
}

const { cvSubject } = load("");
eq("null ref", cvSubject(null), "CV request");
eq("empty ref", cvSubject(""), "CV request");
eq("plain ref", cvSubject("acme-health"), "CV request (via acme-health)");
eq("uppercase ref is lowercased", cvSubject("ACME-Health"), "CV request (via acme-health)");
eq("trimmed ref", cvSubject("  acme  "), "CV request (via acme)");
eq("space rejected", cvSubject("a b"), "CV request");
eq("markup rejected", cvSubject("<script>"), "CV request");
eq("quote rejected", cvSubject('a"b'), "CV request");
eq("41 chars rejected", cvSubject("x".repeat(41)), "CV request");
eq("40 chars accepted", cvSubject("x".repeat(40)), `CV request (via ${"x".repeat(40)})`);

const a = load("?ref=acme-health");
eq("ref stored", a.store["ref"], "acme-health");
eq("link rewritten", a.link.href, "mailto:contact@jeffreypost.dev?subject=" + encodeURIComponent("CV request (via acme-health)"));
eq("link text untouched", a.link.textContent, "Request CV");
eq("plausible class added", a.added.join(" "), "cv-link plausible-event-name=Request+CV");
a.link.listeners.forEach((f) => f());
eq("gtag event sent", JSON.stringify(a.gtagCalls[0]), JSON.stringify(["event", "request_cv"]));

const b = load("?other=1", { ref: "kept-co" });
eq("stored ref survives later pages", b.link.href, "mailto:contact@jeffreypost.dev?subject=" + encodeURIComponent("CV request (via kept-co)"));

const c = load("?ref=%3Cscript%3E");
eq("hostile ref gives plain subject", c.link.href, "mailto:contact@jeffreypost.dev?subject=" + encodeURIComponent("CV request"));

if (failures) { console.log(`${failures} FAILED`); Deno.exit(1); }
console.log("ALL PASS");
