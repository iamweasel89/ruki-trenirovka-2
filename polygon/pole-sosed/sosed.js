// "Field next to its label" practice pages. Every field the trainer cares about carries
// data-pole="<id>" (input, textarea or contenteditable, also inside shadow roots: register
// those with S.dobavit). The page checks on its own:
//   - the final value of every field (contenteditable: innerText, NBSP as space, no trailing
//     line break),
//   - how many input events each field received (a field that was not the target must stay
//     at zero: that is "typed into the wrong field"),
//   - the order in which fields received input.
// The summary goes to the read-only field "kontrol" (length + FNV-1a hash, value when short).
// URL parameters: seed=N (disturbances), skroll=1 (page drifts and jumps while the skill works).
(function () {
  var q = new URLSearchParams(location.search);
  var s = (parseInt(q.get('seed') || '1', 10) >>> 0) || 1;
  function rnd() {
    s |= 0; s = (s + 0x6D2B79F5) | 0;
    var t = Math.imul(s ^ (s >>> 15), 1 | s);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  }
  function mezhdu(a, b) { return a + Math.floor(rnd() * (b - a + 1)); }
  function fnv(x) {
    var h = 0x811c9dc5;
    for (var i = 0; i < x.length; i++) { h ^= x.charCodeAt(i); h = Math.imul(h, 16777619) >>> 0; }
    return ('00000000' + h.toString(16)).slice(-8);
  }
  var S = window.S = { rnd: rnd, mezhdu: mezhdu, fnv: fnv, polya: [], nach: {}, vvodov: {}, poryadok: [], pomehi: [] };

  function znach(el) {
    if (el.isContentEditable || el.getAttribute('contenteditable') === 'true') {
      return el.innerText.replace(/ /g, ' ').replace(/\r\n/g, '\n').replace(/\n+$/, '');
    }
    return el.value.replace(/\r\n/g, '\n');
  }
  S.znach = znach;
  function dobavit(el) {
    var id = el.getAttribute('data-pole');
    if (!id || S.polya.indexOf(el) >= 0) return;
    S.polya.push(el);
    S.nach[id] = znach(el);
    S.vvodov[id] = 0;
    el.addEventListener('input', function () {
      S.vvodov[id]++;
      if (S.poryadok[S.poryadok.length - 1] !== id) S.poryadok.push(id);
      obnovit();
    });
  }
  S.dobavit = dobavit;

  function obnovit() {
    var k = document.getElementById('kontrol'); if (!k) return;
    var d = {};
    S.polya.forEach(function (el) {
      var id = el.getAttribute('data-pole'), v = znach(el);
      var z = { dl: v.length, h: fnv(v), vvodov: S.vvodov[id], izmeneno: v !== S.nach[id] };
      if (v.length <= 120) z.v = v;
      d[id] = z;
    });
    k.value = JSON.stringify({ pola: d, poryadok: S.poryadok, pomehi: S.pomehi, skroll: Math.round(window.scrollY) });
  }
  S.obnovit = obnovit;

  // the form appears with a delay, like a page that renders after its data loads
  S.pokazat = function () {
    var f = document.getElementById('forma');
    var zad = mezhdu(150, 1400);
    setTimeout(function () {
      f.hidden = false;
      Array.prototype.forEach.call(document.querySelectorAll('[data-pole]'), dobavit);
      if (S.posle) S.posle();
      obnovit();
      if (q.get('skroll') === '1' || document.body.hasAttribute('data-skroll')) skroll();
    }, zad);
  };

  // scroll disturbance: a jump right away, a jump whenever focus leaves a field, and a slow
  // drift; coordinates read before a click may be stale by the time of the click
  function skroll() {
    S.pomehi.push('skroll');
    var maks = function () { return Math.max(0, document.documentElement.scrollHeight - innerHeight); };
    function prygnut() { window.scrollTo(0, mezhdu(0, maks())); }
    prygnut();
    document.addEventListener('focusout', function () { setTimeout(prygnut, mezhdu(0, 250)); }, true);
    (function drejf() {
      setTimeout(function () { window.scrollBy(0, mezhdu(-260, 260)); drejf(); }, mezhdu(700, 1600));
    })();
  }

  setInterval(obnovit, 400);
  document.addEventListener('DOMContentLoaded', obnovit);
})();
