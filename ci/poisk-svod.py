#!/usr/bin/env python3
"""Aggregate search-trainer jobs into itog.json + itog.md.
usage: poisk-svod.py <dir with poisk-*.json> <out dir>"""
import glob, json, os, sys, collections

src, dst = sys.argv[1], sys.argv[2]
os.makedirs(dst, exist_ok=True)

def load(p):
    with open(p, encoding='utf-8-sig') as f:
        return json.load(f)

def kvantil(v, q):
    if not v:
        return None
    v = sorted(v)
    k = max(0, min(len(v) - 1, int(round(q * (len(v) - 1)))))
    return v[k]

raboty, progony = [], []
for p in sorted(glob.glob(os.path.join(src, '**', 'poisk-*.json'), recursive=True)):
    try:
        rb = load(p)
    except Exception as e:
        rb = {'seed': os.path.basename(p), 'oshibka': str(e), 'progony': []}
    pr = rb.get('progony') or []
    if isinstance(pr, dict):
        pr = [pr]
    raboty.append({'seed': rb.get('seed'), 'progonov': len(pr), 'verno': sum(1 for x in pr if x.get('verno')), 'sekund': rb.get('sekund')})
    progony += pr

vsego = len(progony)
verno = sum(1 for x in progony if x.get('verno'))
ms_poz = [x['ms'] for x in progony if x.get('pozitiv') and x.get('ms') is not None]
ms_sob = [x['ms'] - (x.get('ozhidanie') or 0) for x in progony if x.get('pozitiv') and x.get('ms') is not None]
ms_neg = [x['ms'] for x in progony if not x.get('pozitiv') and x.get('ms') is not None]
po_zad = collections.defaultdict(lambda: {'progonov': 0, 'verno': 0, 'ms': []})
po_pomehe = collections.defaultdict(lambda: [0, 0])
etapy = collections.defaultdict(list)
for x in progony:
    z = po_zad[x.get('zadacha')]
    z['progonov'] += 1; z['verno'] += 1 if x.get('verno') else 0
    if x.get('ms') is not None:
        z['ms'].append(x['ms'])
    pp = po_pomehe[x.get('pomeha')]; pp[0] += 1; pp[1] += 1 if x.get('verno') else 0
    for k, v in (x.get('etapy') or {}).items():
        if isinstance(v, (int, float)):
            etapy[k].append(v)

dolya = round(100.0 * verno / vsego, 1) if vsego else 0.0
itog = {
    'run': os.environ.get('GITHUB_RUN_ID'), 'sha': os.environ.get('GITHUB_SHA'),
    'progonov': vsego, 'verno': verno, 'dolya_verno_proc': dolya,
    'ms_mediana': kvantil(ms_poz, .5), 'ms_p95': kvantil(ms_poz, .95),
    'ms_sobstv_mediana': kvantil(ms_sob, .5), 'ms_sobstv_p95': kvantil(ms_sob, .95),
    'ms_otsutstvie_mediana': kvantil(ms_neg, .5), 'ms_otsutstvie_p95': kvantil(ms_neg, .95),
    'etapy_mediana': {k: kvantil(v, .5) for k, v in etapy.items()},
    'etapy_p95': {k: kvantil(v, .95) for k, v in etapy.items()},
    'po_zadacham': {k: {'progonov': v['progonov'], 'verno': v['verno'], 'ms_mediana': kvantil(v['ms'], .5), 'ms_p95': kvantil(v['ms'], .95)} for k, v in sorted(po_zad.items())},
    'po_pomeham': {k: {'progonov': v[0], 'verno': v[1]} for k, v in po_pomehe.items()},
    'po_rabotam': raboty,
    'neudachi': [x for x in progony if not x.get('verno')][:40],
    'medlennye': sorted([x for x in progony if x.get('pozitiv') and x.get('ms')], key=lambda x: -x['ms'])[:8],
}
with open(os.path.join(dst, 'itog.json'), 'w', encoding='utf-8') as f:
    json.dump(itog, f, ensure_ascii=False, indent=1)

L = ['# Itog trenera poiska', '', f"run {itog['run']}, commit {str(itog['sha'])[:10]}", '',
     f"- progonov: {vsego}, verno: {verno}, dolya: **{dolya} %**",
     f"- dvizhenie (najdeno): mediana {itog['ms_mediana']} ms, p95 **{itog['ms_p95']} ms**",
     f"- bez ozhidaniya stranicy: mediana {itog['ms_sobstv_mediana']} ms, p95 {itog['ms_sobstv_p95']} ms",
     f"- otsutstvie (net): mediana {itog['ms_otsutstvie_mediana']} ms, p95 {itog['ms_otsutstvie_p95']} ms",
     '', '## Etapy (mediana / p95, ms)', '']
for k in itog['etapy_mediana']:
    L.append(f"- {k}: {itog['etapy_mediana'][k]} / {itog['etapy_p95'][k]}")
L += ['', '## Po zadacham', '']
for k, v in itog['po_zadacham'].items():
    L.append(f"- {k}: {v['verno']}/{v['progonov']}, mediana {v['ms_mediana']} ms, p95 {v['ms_p95']} ms")
L += ['', '## Po pomeham okna', ''] + [f"- {k}: {v['verno']}/{v['progonov']}" for k, v in itog['po_pomeham'].items()]
L += ['', '## Neudachi', ''] + [f"- {x.get('zadacha')} pomeha={x.get('pomeha')} status={x.get('status')} nazhato={x.get('nazhato')} ozhid={x.get('ozhid')} ms={x.get('ms')}" for x in itog['neudachi'][:20]]
L += ['', '## Po rabotam', ''] + [f"- seed {r['seed']}: {r['verno']}/{r['progonov']}, {r['sekund']} s" for r in raboty]
with open(os.path.join(dst, 'itog.md'), 'w', encoding='utf-8') as f:
    f.write('\n'.join(L) + '\n')
print('\n'.join(L))
