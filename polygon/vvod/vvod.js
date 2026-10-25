// Input-fidelity practice pages. Field kinds by attributes:
//   data-limit="N"        JS length limit (cuts the value, like counters on real sites)
//   data-bez-vstavki      paste is blocked
//   data-lokal="ru|en|de" number field with locale formatting (ru: as you type, others: on blur)
//   data-podskazki="a|b"  autocomplete combobox: a suggestion must be picked from the list
// A live read-only field "kontrol" holds a compact summary: length + FNV-1a hash of every
// field (the value itself only when short), picked flags, parsed numbers, submit count.
(function () {
  var P = window.P || { rnd: Math.random, mezhdu: function (a, b) { return a + Math.floor(Math.random() * (b - a + 1)); }, zhurnal: [] };
  var V = window.V = { otpravok: 0, otpravleno: false };
  function $(id) { return document.getElementById(id); }
  function fnv(s) {
    var h = 0x811c9dc5;
    for (var i = 0; i < s.length; i++) { h ^= s.charCodeAt(i); h = Math.imul(h, 16777619) >>> 0; }
    return ('00000000' + h.toString(16)).slice(-8);
  }
  V.fnv = fnv;

  // numbers
  var RAZD = { ru: { gr: ' ', dec: ',' }, en: { gr: ',', dec: '.' }, de: { gr: '.', dec: ',' } };
  function razobrat(s, lok) {
    var r = RAZD[lok]; if (!r) return null;
    var t = s.replace(/[\s   ]/g, '');
    if (r.gr !== ' ') t = t.split(r.gr).join('');
    t = t.replace(r.dec, '.');
    if (!/^-?\d*(\.\d*)?$/.test(t) || t === '' || t === '.') return null;
    return parseFloat(t);
  }
  function gruppy(cel, gr) { return cel.replace(/\B(?=(\d{3})+(?!\d))/g, gr); }
  function formatirovat(n, lok) {
    var r = RAZD[lok];
    var s = Math.abs(n).toFixed(2).split('.');
    return (n < 0 ? '-' : '') + gruppy(s[0], r.gr) + r.dec + s[1];
  }
  // ru: regroup while typing, keep what the user typed after the decimal comma
  function naLetu(el) {
    var r = RAZD.ru;
    var t = el.value.replace(/[^\d,\-]/g, '');
    var i = t.indexOf(',');
    var cel = i >= 0 ? t.slice(0, i) : t, dr = i >= 0 ? t.slice(i + 1).replace(/,/g, '').slice(0, 2) : null;
    var nov = gruppy(cel.replace(/-/g, ''), r.gr);
    if (cel.charAt(0) === '-') nov = '-' + nov;
    if (dr !== null) nov += ',' + dr;
    if (nov !== el.value) el.value = nov;
  }
  function poBluru(el) {
    var n = razobrat(el.value, el.dataset.lokal);
    if (n !== null) el.value = formatirovat(n, el.dataset.lokal);
  }

  // autocomplete
  var spiski = {};
  function spisokDlya(el) {
    var id = el.id + '_spisok';
    var ul = $(id);
    if (!ul) {
      ul = document.createElement('ul');
      ul.id = id; ul.setAttribute('role', 'listbox'); ul.setAttribute('aria-label', 'Подсказки');
      ul.className = 'podskazki'; ul.hidden = true;
      el.parentNode.appendChild(ul);
      el.setAttribute('aria-controls', id);
    }
    return ul;
  }
  function zakrytSpisok(el) {
    var ul = $(el.id + '_spisok');
    if (ul) { ul.hidden = true; ul.innerHTML = ''; }
    el.setAttribute('aria-expanded', 'false');
    el.removeAttribute('aria-activedescendant');
  }
  function vybrat(el, tekst) {
    el.value = tekst; el.dataset.vybrano = tekst;
    zakrytSpisok(el); obnovit();
  }
  function pokazatSpisok(el) {
    var q = el.value.toLocaleLowerCase();
    var vse = el.dataset.podskazki.split('|');
    var nado = q.length < 2 ? [] : vse.filter(function (x) { return x.toLocaleLowerCase().indexOf(q) === 0; });
    // order shuffled a little, as with relevance ranking
    nado.sort(function () { return P.rnd() - 0.5; });
    var ul = spisokDlya(el);
    ul.innerHTML = '';
    nado.slice(0, 6).forEach(function (x, i) {
      var li = document.createElement('li');
      li.setAttribute('role', 'option'); li.id = el.id + '_o' + i; li.textContent = x;
      li.setAttribute('aria-selected', 'false');
      ul.appendChild(li);
    });
    ul.hidden = nado.length === 0;
    el.setAttribute('aria-expanded', nado.length ? 'true' : 'false');
  }
  document.addEventListener('input', function (e) {
    var el = e.target;
    if (el.dataset && el.dataset.podskazki !== undefined) {
      delete el.dataset.vybrano;
      clearTimeout(spiski[el.id]);
      spiski[el.id] = setTimeout(function () { if (document.body.contains(el)) pokazatSpisok(el); }, P.mezhdu(150, 900));
    }
    if (el.dataset && el.dataset.lokal === 'ru') naLetu(el);
    if (el.dataset && el.dataset.limit) {
      var n = +el.dataset.limit;
      if (el.value.length > n) el.value = el.value.slice(0, n);
    }
    obnovit();
  }, false);
  document.addEventListener('click', function (e) {
    var li = e.target.closest && e.target.closest('[role=option]');
    if (!li) return;
    var el = $(li.parentNode.id.replace(/_spisok$/, ''));
    if (el) vybrat(el, li.textContent);
  });
  document.addEventListener('keydown', function (e) {
    var el = e.target;
    if (!el.dataset || el.dataset.podskazki === undefined) return;
    var ul = $(el.id + '_spisok');
    var opts = ul && !ul.hidden ? Array.prototype.slice.call(ul.children) : [];
    if (!opts.length) return;
    var i = opts.findIndex(function (x) { return x.getAttribute('aria-selected') === 'true'; });
    if (e.key === 'ArrowDown' || e.key === 'ArrowUp') {
      e.preventDefault();
      i = e.key === 'ArrowDown' ? Math.min(i + 1, opts.length - 1) : Math.max(i - 1, 0);
      opts.forEach(function (x, k) { x.setAttribute('aria-selected', k === i ? 'true' : 'false'); });
      el.setAttribute('aria-activedescendant', opts[i].id);
    } else if (e.key === 'Enter' && i >= 0) {
      e.preventDefault(); vybrat(el, opts[i].textContent);
    } else if (e.key === 'Escape') { zakrytSpisok(el); }
  }, true);

  document.addEventListener('paste', function (e) {
    if (e.target.hasAttribute && e.target.hasAttribute('data-bez-vstavki')) { e.preventDefault(); P.zhurnal.push('vstavka-zapreshchena'); }
  }, true);
  document.addEventListener('focusout', function (e) {
    var el = e.target;
    if (el.dataset && el.dataset.lokal && el.dataset.lokal !== 'ru') { poBluru(el); obnovit(); }
  }, true);

  function polya() {
    return Array.prototype.filter.call(document.querySelectorAll('main input, main textarea'), function (x) {
      return x.id && x.id !== 'kontrol' && x.id !== 'poisk' && x.id !== 'itog';
    });
  }
  function obnovit() {
    var k = $('kontrol'); if (!k) return;
    var d = {};
    polya().forEach(function (el) {
      var z = { dl: el.value.length, h: fnv(el.value) };
      if (el.value.length <= 300) z.v = el.value;
      if (el.dataset.podskazki !== undefined) z.vybrano = el.dataset.vybrano === el.value && el.value !== '';
      if (el.dataset.lokal) { var n = razobrat(el.value, el.dataset.lokal); z.chislo = n === null ? null : n; }
      if (el.type === 'number') { z.chislo = el.value === '' ? null : parseFloat(el.value); }
      d[el.id] = z;
    });
    k.value = JSON.stringify({ pola: d, otpravok: V.otpravok, otpravleno: V.otpravleno, pomehi: P.zhurnal });
  }
  V.obnovit = obnovit;
  document.addEventListener('pererisovka', obnovit);
  document.addEventListener('change', obnovit);

  // any real submit (e.g. Enter in a single-line field) is counted: plans with an
  // expected stop must leave it at zero
  document.addEventListener('submit', function (e) { e.preventDefault(); V.otpravok++; obnovit(); }, true);

  V.zavershit = function (forma) {
    polya().forEach(function (el) { if (el.dataset.lokal && el.dataset.lokal !== 'ru') poBluru(el); });
    P.vyklyucheno = true; if (P.zakrytModal) P.zakrytModal();
    V.otpravleno = true; obnovit();
    forma.hidden = true;
    var h = document.createElement('h2'); h.textContent = 'Отправлено';
    var t = document.createElement('textarea');
    t.id = 'itog'; t.readOnly = true; t.setAttribute('aria-label', 'Итог'); t.rows = 2; t.value = 'ok';
    document.querySelector('main').appendChild(h);
    document.querySelector('main').appendChild(t);
    document.title = document.title + ' — отправлено';
  };
  V.knopka = function (forma, id, gotovo) {
    function proverit() { $(id).disabled = !gotovo(); }
    document.addEventListener('input', proverit);
    document.addEventListener('change', proverit);
    document.addEventListener('pererisovka', proverit);
    document.addEventListener('click', function (e) {
      if (e.target.id === id && !e.target.disabled) V.zavershit(forma);
      setTimeout(proverit, 0);
    });
    proverit();
  };
  document.addEventListener('DOMContentLoaded', obnovit);
  setTimeout(obnovit, 0);
})();
