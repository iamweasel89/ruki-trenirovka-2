// Shared code of the search pages: seeded random, click journal in the title.
// Any button click sets document.title to "<base> | nazhato: <key>" (key = data-k or id).
// Inside a frame the click is passed up to the top page with postMessage.
(function () {
  var q = new URLSearchParams(location.search);
  var s = (parseInt(q.get('seed') || '1', 10) >>> 0) || 1;
  function rnd() {
    s |= 0; s = (s + 0x6D2B79F5) | 0;
    var t = Math.imul(s ^ (s >>> 15), 1 | s);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  }
  var O = window.O = { q: q, rnd: rnd, mezhdu: function (a, b) { return a + Math.floor(rnd() * (b - a + 1)); }, baza: document.title, klikov: 0 };
  O.otmetit = function (k) {
    O.klikov++;
    if (window.top !== window) { window.top.postMessage({ nazhato: k }, '*'); return; }
    document.title = O.baza + ' | nazhato: ' + k + (O.klikov > 1 ? ' | klikov: ' + O.klikov : '');
  };
  window.addEventListener('message', function (e) { if (e.data && e.data.nazhato) O.otmetit(e.data.nazhato); });
  document.addEventListener('click', function (e) {
    var b = e.target.closest ? e.target.closest('button,a') : null;
    if (!b || b.disabled) return;
    e.preventDefault();
    O.otmetit(b.getAttribute('data-k') || b.id || b.textContent.trim());
  }, true);
})();
