// "Request CV" links: any <a class="cv-link">.
// Remembers ?ref=<company-slug> for the visit and puts it in the email subject,
// so a CV request says which resume link it came from. The ref is only ever
// used inside the encoded mailto: URL, never written into the page.
var CV_EMAIL = "contact@jeffreypost.dev";

function cvSubject(ref) {
  var r = (ref == null ? "" : String(ref)).trim().toLowerCase();
  return /^[a-z0-9-]{1,40}$/.test(r) ? "CV request (via " + r + ")" : "CV request";
}

(function () {
  var stored = null;
  try {
    var m = /[?&]ref=([^&#]*)/.exec(window.location.search || "");
    if (m) window.sessionStorage.setItem("ref", decodeURIComponent(m[1].replace(/\+/g, " ")));
    stored = window.sessionStorage.getItem("ref");
  } catch (e) { /* storage blocked: fall back to a plain subject */ }

  function wire() {
    var links = document.querySelectorAll('a.cv-link, a[href^="mailto:' + CV_EMAIL + '?subject=CV"]');
    for (var i = 0; i < links.length; i++) {
      links[i].classList.add("cv-link", "plausible-event-name=Request+CV");
      links[i].href = "mailto:" + CV_EMAIL + "?subject=" + encodeURIComponent(cvSubject(stored));
      links[i].addEventListener("click", function () {
        if (typeof window.gtag === "function") window.gtag("event", "request_cv");
      });
    }
  }
  if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", wire);
  else wire();
})();
