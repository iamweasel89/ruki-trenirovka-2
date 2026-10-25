// Practice page for screen reading by recognition: nothing here is visible to UIA.
// Labels are drawn on a canvas (buttons) or baked into a picture (<img> from a data URL).
// URL: ?st=knopki|kartinka|melkij|blednyj&seed=N&m=<JSON array of labels>&dv=<i moving>&mg=<i pulsing>
// Clicks are reported in the window title (codes only, never label text, so reading the
// title bar cannot help or confuse the recogniser):
//   "ocr r1 n<clicks> k<i>,<dx>,<dy>,<in>;..."  i = label index (-1 = nothing),
//   dx/dy = offset from the label centre in CSS px, in = 1 when inside the label box.
(function () {
  var q = {};
  location.search.replace(/^\?/, '').split('&').forEach(function (p) {
    if (!p) return; var i = p.indexOf('='); q[decodeURIComponent(p.slice(0, i))] = decodeURIComponent(p.slice(i + 1));
  });
  var st = q.st || 'knopki';
  var seed = parseInt(q.seed || '1', 10) >>> 0;
  var metki = []; try { metki = JSON.parse(q.m || '[]'); } catch (e) { metki = ['?']; }
  var dv = q.dv === undefined ? -1 : parseInt(q.dv, 10);
  var mg = q.mg === undefined ? -1 : parseInt(q.mg, 10);

  function mulberry(a) { return function () { a |= 0; a = a + 0x6D2B79F5 | 0; var t = Math.imul(a ^ a >>> 15, 1 | a); t = t + Math.imul(t ^ t >>> 7, 61 | t) ^ t; return ((t ^ t >>> 14) >>> 0) / 4294967296; }; }
  var rnd = mulberry(seed * 2654435761);
  function mezhdu(a, b) { return a + rnd() * (b - a); }

  var dpr = window.devicePixelRatio || 1;
  var W = window.innerWidth, H = window.innerHeight;
  var kliki = [], gotovo = false, nazhato = {};
  function obnovitZagolovok() {
    document.title = 'ocr r' + (gotovo ? 1 : 0) + ' n' + kliki.length + ' k' +
      kliki.map(function (k) { return k.i + ',' + k.dx + ',' + k.dy + ',' + k.v; }).join(';');
  }

  var STILI = {
    knopki:   { shrift: [17, 21], ves: '600', fon: '#eef0f2', knopka: ['#2f6fb5', '#3a8a5c', '#8a4f2f', '#5b4f9a', '#6b6f75', '#b03a48'], tekst: '#ffffff' },
    melkij:   { shrift: [10, 11], ves: '400', fon: '#f3f3f3', knopka: ['#e2e2e2', '#dadde3', '#e6e1d8'], tekst: '#333333', ramka: '#b8b8b8' },
    blednyj:  { shrift: [15, 17], ves: '400', fon: '#d4d4d4', knopka: ['#c9c9c9', '#cbc8c2', '#c6c9cc'], tekst: '#8f8f8f' },
    kartinka: { shrift: [22, 30], ves: '700' }
  };
  var S = STILI[st] || STILI.knopki;

  // label boxes in CSS px: {x, y, w, h, f, t}
  var ramki = [];
  function shriftDlya(r) { return S.ves + ' ' + r.f + 'px Segoe UI, Arial, sans-serif'; }
  var izm = document.createElement('canvas').getContext('2d');
  function razlozhit(polosaDv) {
    var verh = 30, niz = H - 20;
    if (polosaDv) niz = H * 0.66;
    for (var i = 0; i < metki.length; i++) {
      var f = Math.round(mezhdu(S.shrift[0], S.shrift[1] + 0.99));
      izm.font = S.ves + ' ' + f + 'px Segoe UI, Arial, sans-serif';
      var tw = izm.measureText(metki[i]).width;
      var padX = st === 'kartinka' ? 8 : Math.max(10, f * 0.9), padY = st === 'kartinka' ? 6 : f * 0.55;
      var w = Math.ceil(tw + 2 * padX), h = Math.ceil(f + 2 * padY);
      var r = { w: w, h: h, f: f, t: metki[i], x: 0, y: 0 };
      if (i === dv) { r.x = mezhdu(20, Math.max(21, W - w - 20)); r.y = H * 0.78; ramki.push(r); continue; }
      var ok = false;
      for (var p = 0; p < 600 && !ok; p++) {
        r.x = mezhdu(24, Math.max(25, W - w - 24)); r.y = mezhdu(verh, Math.max(verh + 1, niz - h));
        ok = ramki.every(function (o) { var z = 26; return r.x + r.w + z < o.x || o.x + o.w + z < r.x || r.y + r.h + z < o.y || o.y + o.h + z < r.y; });
      }
      if (!ok) { r.x = 24 + (i % 3) * (W / 3); r.y = verh + Math.floor(i / 3) * (h + 40); }
      ramki.push(r);
    }
  }

  // moving label: bounces horizontally; pulsing label: opacity goes 0.3 .. 1
  var skorost = 70 + rnd() * 50, napr = rnd() < 0.5 ? -1 : 1, t0 = performance.now(), x0 = 0;
  function pozDv(t) {
    var r = ramki[dv]; var min = 20, max = Math.max(21, W - r.w - 20), d = max - min;
    var s = (x0 - min) + napr * skorost * (t - t0) / 1000;
    s = ((s % (2 * d)) + 2 * d) % (2 * d);
    return min + (s <= d ? s : 2 * d - s);
  }
  function prozrachnost(t) { return 0.65 + 0.35 * Math.cos(2 * Math.PI * (t - t0) / 1600); }

  function ramkaSejchas(i, t) {
    var r = ramki[i];
    if (i === dv) return { x: pozDv(t), y: r.y, w: r.w, h: r.h };
    return r;
  }

  function zapisatKlik(x, y) {
    var t = performance.now(), popal = -1, blizh = -1, bd = 1e9;
    for (var i = 0; i < ramki.length; i++) {
      var r = ramkaSejchas(i, t);
      if (popal < 0 && x >= r.x && x <= r.x + r.w && y >= r.y && y <= r.y + r.h) popal = i;
      var d = Math.abs(x - r.x - r.w / 2) + Math.abs(y - r.y - r.h / 2);
      if (d < bd) { bd = d; blizh = i; }
    }
    var j = popal >= 0 ? popal : blizh;
    var rr = j >= 0 ? ramkaSejchas(j, t) : { x: x, y: y, w: 0, h: 0 };
    kliki.push({ i: popal, dx: Math.round(x - rr.x - rr.w / 2), dy: Math.round(y - rr.y - rr.h / 2), v: popal >= 0 ? 1 : 0 });
    if (popal >= 0) nazhato[popal] = true;
    obnovitZagolovok();
  }

  function holst() {
    var c = document.createElement('canvas');
    c.width = Math.round(W * dpr); c.height = Math.round(H * dpr);
    c.style.width = W + 'px'; c.style.height = H + 'px';
    document.body.appendChild(c);
    return c;
  }

  if (st === 'kartinka') {
    razlozhit(false);
    // the picture: gradient sky, hills, noise and blobs, labels as game-menu text with outline
    var pc = document.createElement('canvas');
    pc.width = Math.round(W * dpr); pc.height = Math.round(H * dpr);
    var g = pc.getContext('2d'); g.setTransform(dpr, 0, 0, dpr, 0, 0);
    var gr = g.createLinearGradient(0, 0, 0, H);
    var h1 = Math.floor(mezhdu(180, 260)), h2 = Math.floor(mezhdu(10, 60));
    gr.addColorStop(0, 'hsl(' + h1 + ',55%,38%)'); gr.addColorStop(1, 'hsl(' + h2 + ',60%,45%)');
    g.fillStyle = gr; g.fillRect(0, 0, W, H);
    for (var b = 0; b < 26; b++) {
      g.fillStyle = 'hsla(' + Math.floor(mezhdu(0, 360)) + ',50%,' + Math.floor(mezhdu(30, 70)) + '%,0.35)';
      g.beginPath(); g.arc(mezhdu(0, W), mezhdu(0, H), mezhdu(15, 120), 0, 7); g.fill();
    }
    g.fillStyle = 'rgba(20,40,20,0.55)'; g.beginPath(); g.moveTo(0, H);
    for (var x = 0; x <= W; x += 40) g.lineTo(x, H * 0.75 + Math.sin(x / 90 + seed) * 30);
    g.lineTo(W, H); g.fill();
    var id = g.getImageData(0, 0, pc.width, pc.height), d = id.data;
    for (var p = 0; p < d.length; p += 4) { var n = (rnd() - 0.5) * 28; d[p] += n; d[p + 1] += n; d[p + 2] += n; }
    g.putImageData(id, 0, 0);
    ramki.forEach(function (r) {
      g.font = shriftDlya(r); g.textBaseline = 'middle'; g.textAlign = 'center';
      g.lineJoin = 'round'; g.lineWidth = Math.max(3, r.f / 6); g.strokeStyle = 'rgba(0,0,0,0.85)';
      g.shadowColor = 'rgba(0,0,0,0.6)'; g.shadowBlur = 6;
      g.strokeText(r.t, r.x + r.w / 2, r.y + r.h / 2);
      g.shadowBlur = 0; g.fillStyle = rnd() < 0.5 ? '#fff6d8' : '#ffffff';
      g.fillText(r.t, r.x + r.w / 2, r.y + r.h / 2);
    });
    var img = new Image();
    img.style.width = W + 'px'; img.style.height = H + 'px';
    img.alt = '';
    img.onload = function () { requestAnimationFrame(function () { gotovo = true; obnovitZagolovok(); }); };
    img.addEventListener('mousedown', function (e) { zapisatKlik(e.offsetX, e.offsetY); });
    img.draggable = false;
    img.src = pc.toDataURL('image/png');
    document.body.appendChild(img);
  } else {
    razlozhit(dv >= 0);
    if (dv >= 0) x0 = ramki[dv].x;
    var c = holst(), g2 = c.getContext('2d');
    var cveta = ramki.map(function () { return S.knopka[Math.floor(rnd() * S.knopka.length)]; });
    var ukrasy = [];
    for (var u = 0; u < 7; u++) ukrasy.push({ x: mezhdu(0, W), y: mezhdu(0, H), r: mezhdu(20, 90), c: 'hsla(' + Math.floor(mezhdu(0, 360)) + ',30%,60%,0.12)' });
    function knopka(r, i, t) {
      var a = (i === mg) ? prozrachnost(t) : 1;
      var pr = nazhato[i];
      g2.globalAlpha = a;
      g2.fillStyle = pr ? '#1d1d1d' : cveta[i];
      var rad = Math.min(8, r.h / 3);
      g2.beginPath();
      g2.moveTo(r.x + rad, r.y); g2.arcTo(r.x + r.w, r.y, r.x + r.w, r.y + r.h, rad); g2.arcTo(r.x + r.w, r.y + r.h, r.x, r.y + r.h, rad);
      g2.arcTo(r.x, r.y + r.h, r.x, r.y, rad); g2.arcTo(r.x, r.y, r.x + r.w, r.y, rad); g2.closePath(); g2.fill();
      if (S.ramka && !pr) { g2.strokeStyle = S.ramka; g2.lineWidth = 1; g2.stroke(); }
      g2.font = shriftDlya(ramki[i]); g2.textBaseline = 'middle'; g2.textAlign = 'center';
      g2.fillStyle = pr ? '#ffffff' : S.tekst;
      g2.fillText(ramki[i].t, r.x + r.w / 2, r.y + r.h / 2 + 1);
      g2.globalAlpha = 1;
    }
    function kadr() {
      var t = performance.now();
      g2.setTransform(dpr, 0, 0, dpr, 0, 0);
      g2.fillStyle = S.fon; g2.fillRect(0, 0, W, H);
      ukrasy.forEach(function (k) { g2.fillStyle = k.c; g2.beginPath(); g2.arc(k.x, k.y, k.r, 0, 7); g2.fill(); });
      for (var i = 0; i < ramki.length; i++) knopka(ramkaSejchas(i, t), i, t);
      if (dv >= 0 || mg >= 0) requestAnimationFrame(kadr);
    }
    c.addEventListener('mousedown', function (e) {
      var b = c.getBoundingClientRect(); zapisatKlik(e.clientX - b.left, e.clientY - b.top);
      if (dv < 0 && mg < 0) kadr();
    });
    kadr();
    requestAnimationFrame(function () { requestAnimationFrame(function () { gotovo = true; obnovitZagolovok(); }); });
  }
  document.addEventListener('contextmenu', function (e) { e.preventDefault(); });
  obnovitZagolovok();
})();
