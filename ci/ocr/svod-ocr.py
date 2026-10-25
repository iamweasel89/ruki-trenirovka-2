#!/usr/bin/env python3
"""Aggregate recognition-training results into itog.json + itog.md.
usage: svod-ocr.py <dir with rezultat-*.json> <out dir> [jobs.json]
Measures: share of correct runs (hit for a present target, honest 'not found' and no click
for an absent one), finding accuracy, click offset from the label centre, false clicks,
recognition time p95, per plan / per scale / per pass."""
import glob, json, os, sys, collections, datetime, math

src, dst = sys.argv[1], sys.argv[2]
jobs_api = sys.argv[3] if len(sys.argv) > 3 else None
os.makedirs(dst, exist_ok=True)

def load(p):
    with open(p, encoding='utf-8-sig') as f:
        return json.load(f)

def spisok(x):
    if x is None: return []
    return x if isinstance(x, list) else [x]

def pct(a, q):
    if not a: return None
    a = sorted(a); k = (len(a) - 1) * q
    lo, hi = math.floor(k), math.ceil(k)
    return int(round(a[lo] + (a[hi] - a[lo]) * (k - lo)))

raboty, oshibki = [], []
for p in sorted(glob.glob(os.path.join(src, '**', 'rezultat-*.json'), recursive=True)):
    try: raboty.append(load(p))
    except Exception as e: oshibki.append(f'{os.path.basename(p)}: {e}')

vsego = uspeh = 0
est_n = est_nashel = est_popal = 0
net_n = net_chestno = 0
lozhnyh = 0
lozhnye = []
smesh = []        # click offset from the label centre, CSS px
poisk_ms = []     # recognition time to the decision
po_planu = collections.defaultdict(lambda: {'progonov': 0, 'uspeh': 0, 'ms': []})
po_mash = collections.defaultdict(lambda: {'progonov': 0, 'uspeh': 0})
prohody = collections.defaultdict(lambda: {'raz': 0, 'nashel': 0, 'ms': []})
reshil = collections.Counter()
statusy = collections.Counter()
proverka_posle = collections.Counter()
prichiny = collections.Counter()
neudachi = []
sredy = []
for rb in raboty:
    if rb.get('sreda'): sredy.append({'seed': rb.get('seed'), **rb['sreda']})
    for pr in spisok(rb.get('progony')):
        vsego += 1
        prov = pr.get('proverka') or {}
        sk = pr.get('skill') or {}
        st = sk.get('status') or 'net-rezultata'
        statusy[st] += 1
        plan = pr.get('plan'); m = str(pr.get('masshtab'))
        b = po_planu[plan]; b['progonov'] += 1
        po_mash[m]['progonov'] += 1
        if sk.get('poisk_ms') is not None:
            poisk_ms.append(int(sk['poisk_ms'])); b['ms'].append(int(sk['poisk_ms']))
        for z in spisok(sk.get('prohody')):
            pp = prohody[z.get('prohod')]; pp['raz'] += 1; pp['ms'].append(z.get('ms') or 0)
            if z.get('podtverzhdeno'): pp['nashel'] += 1
        if sk.get('prohod'): reshil[sk['prohod']] += 1
        if sk.get('proverka'): proverka_posle[sk['proverka']] += 1
        kl = spisok(prov.get('kliki'))
        lz = int(prov.get('lozhnyh') or 0)
        lozhnyh += lz
        if lz: lozhnye.append({'plan': plan, 'masshtab': m, 'seed': pr.get('seed'), 'kliki': kl, 'prochitano': sk.get('prochitano'), 'prohod': sk.get('prohod')})
        if prov.get('est_cel'):
            est_n += 1
            if st in ('klik', 'nashel'): est_nashel += 1
            dobryj = [k for k in kl if k.get('v') == 1 and lz == 0]
            if prov.get('uspeh'): est_popal += 1
            for k in kl:
                if k.get('v') == 1: smesh.append(math.hypot(k.get('dx', 0), k.get('dy', 0)))
        else:
            net_n += 1
            if prov.get('uspeh'): net_chestno += 1
        if prov.get('uspeh'):
            uspeh += 1; b['uspeh'] += 1; po_mash[m]['uspeh'] += 1
            continue
        prichiny[f"{plan}: {prov.get('prichina')}"] += 1
        neudachi.append({'seed': pr.get('seed'), 'plan': plan, 'masshtab': m, 'cel': pr.get('cel'), 'proverka': prov.get('prichina'),
                         'status': st, 'oshibka': sk.get('oshibka'), 'prohody': spisok(sk.get('prohody')), 'kliki': kl,
                         'log': spisok(pr.get('log'))[-14:]})

minuty = None
if jobs_api and os.path.exists(jobs_api):
    try:
        tot = 0.0
        for j in load(jobs_api).get('jobs', []):
            if j.get('started_at') and j.get('completed_at'):
                a = datetime.datetime.fromisoformat(j['started_at'].replace('Z', '+00:00'))
                c = datetime.datetime.fromisoformat(j['completed_at'].replace('Z', '+00:00'))
                tot += max(0, (c - a).total_seconds())
        minuty = round(tot / 60, 1)
    except Exception:
        pass

def d(a, b): return round(100.0 * a / b, 1) if b else None
itog = {
    'run': os.environ.get('GITHUB_RUN_ID'), 'sha': os.environ.get('GITHUB_SHA'),
    'progonov': vsego, 'verno': uspeh, 'dolya_verno_proc': d(uspeh, vsego) or 0.0,
    'nahozhdenie_proc': d(est_nashel, est_n), 'popadanie_proc': d(est_popal, est_n), 'est_celej': est_n,
    'chestnoe_ne_nashel_proc': d(net_chestno, net_n), 'net_celej': net_n,
    'lozhnyh_klikov': lozhnyh,
    'smeshchenie_px': {'mediana': pct(smesh, 0.5), 'p95': pct(smesh, 0.95), 'maks': int(max(smesh)) if smesh else None},
    'raspoznavanie_ms': {'mediana': pct(poisk_ms, 0.5), 'p95': pct(poisk_ms, 0.95), 'maks': max(poisk_ms) if poisk_ms else None},
    'po_planam': {k: {'progonov': v['progonov'], 'uspeh': v['uspeh'], 'p95_ms': pct(v['ms'], 0.95)} for k, v in sorted(po_planu.items())},
    'po_masshtabu': dict(sorted(po_mash.items())),
    'prohody': {k: {'raz': v['raz'], 'nashel': v['nashel'], 'mediana_ms': pct(v['ms'], 0.5), 'p95_ms': pct(v['ms'], 0.95)} for k, v in sorted(prohody.items(), key=lambda x: str(x[0]))},
    'reshayushchij_prohod': dict(reshil), 'statusy': dict(statusy), 'proverka_posle_klika': dict(proverka_posle),
    'prichiny_neudach': dict(prichiny), 'lozhnye': lozhnye[:20], 'sredy': sredy,
    'minut_runnera': minuty, 'oshibki_chteniya': oshibki, 'neudachi': neudachi[:40],
}
with open(os.path.join(dst, 'itog.json'), 'w', encoding='utf-8') as f:
    json.dump(itog, f, ensure_ascii=False, indent=1)

L = ['# Itog trenirovki raspoznavaniya (OCR)', '', f"run {itog['run']}, commit {str(itog['sha'])[:10]}", '',
     f"- progonov: {vsego}, verno: {uspeh}, dolya: **{itog['dolya_verno_proc']} %**",
     f"- nahozhdenie po tekstu: {itog['nahozhdenie_proc']} %, popadanie v metku: {itog['popadanie_proc']} % (celej est: {est_n})",
     f"- chestnoe ne-nashel: {itog['chestnoe_ne_nashel_proc']} % (celej net: {net_n})",
     f"- lozhnyh klikov: **{lozhnyh}**",
     f"- smeshchenie klika ot centra, CSS px: mediana {itog['smeshchenie_px']['mediana']}, p95 {itog['smeshchenie_px']['p95']}",
     f"- vremya raspoznavaniya, ms: mediana {itog['raspoznavanie_ms']['mediana']}, p95 **{itog['raspoznavanie_ms']['p95']}**",
     f"- minut runnera: {minuty}", '', '## Po planam', '', '| plan | progonov | verno | p95 ms |', '|---|---|---|---|']
for k, v in itog['po_planam'].items(): L.append(f"| {k} | {v['progonov']} | {v['uspeh']} | {v['p95_ms']} |")
L += ['', '## Po masshtabu', '']
for k, v in itog['po_masshtabu'].items(): L.append(f"- x{k}: {v['uspeh']} iz {v['progonov']}")
L += ['', '## Prohody', '']
for k, v in itog['prohody'].items(): L.append(f"- {k}: raz {v['raz']}, nashel {v['nashel']}, mediana {v['mediana_ms']} ms, p95 {v['p95_ms']} ms")
L += ['', f"Reshayushchij prohod: {itog['reshayushchij_prohod']}", f"Statusy: {itog['statusy']}", f"Proverka posle klika: {itog['proverka_posle_klika']}", '']
if prichiny:
    L += ['## Prichiny neudach', ''] + [f'- {k}: {v}' for k, v in prichiny.most_common()]
if oshibki: L += ['', '## Oshibki chteniya', ''] + [f'- {e}' for e in oshibki]
with open(os.path.join(dst, 'itog.md'), 'w', encoding='utf-8') as f:
    f.write('\n'.join(L) + '\n')
print('\n'.join(L[:12]))
sys.exit(0 if vsego else 1)
