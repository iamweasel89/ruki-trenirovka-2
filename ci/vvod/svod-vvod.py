#!/usr/bin/env python3
"""Aggregate input-fidelity results into itog.json + itog.md.
usage: svod-vvod.py <dir with rezultat-*.json> <out dir> [jobs.json]
Exit code is non-zero only when there is nothing to aggregate (harness broken)."""
import glob, json, os, sys, collections, datetime, statistics

src, dst = sys.argv[1], sys.argv[2]
jobs_api = sys.argv[3] if len(sys.argv) > 3 else None
os.makedirs(dst, exist_ok=True)

def load(p):
    with open(p, encoding='utf-8-sig') as f:
        return json.load(f)

def spisok(x):
    if x is None: return []
    return x if isinstance(x, list) else [x]

raboty, oshibki = [], []
for p in sorted(glob.glob(os.path.join(src, '**', 'rezultat-*.json'), recursive=True)):
    try:
        rb = load(p); raboty.append(rb)
        if rb.get('oshibka'): oshibki.append(f"{os.path.basename(p)}: {rb.get('oshibka')}")
    except Exception as e: oshibki.append(f'{os.path.basename(p)}: {e}')

vsego = uspeh = bufer_ploho = 0
po_planu = collections.defaultdict(lambda: {'progonov': 0, 'uspeh': 0, 'ms': []})
prichiny = collections.Counter()
polya_mimo = collections.Counter()
pomehi = collections.Counter()
neudachi = []
for rb in raboty:
    for pr in spisok(rb.get('progony')):
        vsego += 1
        st = pr.get('stranica')
        prov = pr.get('proverka') or {}
        sk = pr.get('skill') or {}
        b = po_planu[st]; b['progonov'] += 1
        if pr.get('skill_ms'): b['ms'].append(pr['skill_ms'])
        for k, v in (sk.get('pomehi') or {}).items(): pomehi[k] += v
        if not (prov.get('bufer') or {}).get('ok'): bufer_ploho += 1
        if prov.get('uspeh'):
            uspeh += 1; b['uspeh'] += 1
            continue
        ost = sk.get('ostanovka') or {}
        prichiny[f"{st}: {ost.get('prichina') or prov.get('prichina') or 'net-rezultata'}"] += 1
        for fid, z in (prov.get('polya') or {}).items():
            if not z.get('ok'): polya_mimo[f'{st}.{fid}'] += 1
        neudachi.append({'seed': pr.get('seed'), 'plan': st, 'ostanovka': ost, 'proverka': prov.get('prichina'),
                         'polya': {k: v for k, v in (prov.get('polya') or {}).items() if not v.get('ok')},
                         'log': spisok(pr.get('log'))[-18:]})

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

dolya = round(100.0 * uspeh / vsego, 1) if vsego else 0.0
itog = {
    'run': os.environ.get('GITHUB_RUN_ID'), 'sha': os.environ.get('GITHUB_SHA'),
    'progonov': vsego, 'tochno': uspeh, 'dolya_tochno_proc': dolya, 'bufer_ne_vosstanovlen': bufer_ploho,
    'po_planam': {k: {'progonov': v['progonov'], 'uspeh': v['uspeh'], 'mediana_ms': int(statistics.median(v['ms'])) if v['ms'] else None} for k, v in sorted(po_planu.items())},
    'prichiny_neudach': dict(prichiny), 'polya_mimo': dict(polya_mimo), 'pomehi_vstrecheno': dict(pomehi),
    'minut_runnera': minuty, 'oshibki_chteniya': oshibki, 'neudachi': neudachi[:40],
    'primer_progona': next((pr for rb in raboty for pr in spisok(rb.get('progony'))), None),
}
with open(os.path.join(dst, 'itog.json'), 'w', encoding='utf-8') as f:
    json.dump(itog, f, ensure_ascii=False, indent=1)

L = ['# Itog trenirovki vvoda', '', f"run {itog['run']}, commit {str(itog['sha'])[:10]}", '',
     f'- progonov: {vsego}, tochno (ili chestnaya ostanovka): {uspeh}, dolya: **{dolya} %**',
     f'- bufer ne vosstanovlen: {bufer_ploho}',
     f'- minut runnera (vse raboty): {minuty}', '', '## Po planam', '']
for k, v in itog['po_planam'].items():
    L.append(f"- {k}: {v['uspeh']}/{v['progonov']}, mediana {v['mediana_ms']} ms")
L += ['', '## Prichiny neudach', ''] + ([f'- {k}: {v}' for k, v in prichiny.most_common()] or ['- net'])
L += ['', '## Polya mimo', ''] + ([f'- {k}: {v}' for k, v in polya_mimo.most_common()] or ['- net'])
L += ['', '## Pomehi', ''] + [f'- {k}: {v}' for k, v in pomehi.most_common()]
if oshibki: L += ['', '## Oshibki chteniya', ''] + [f'- {x}' for x in oshibki]
with open(os.path.join(dst, 'itog.md'), 'w', encoding='utf-8') as f:
    f.write('\n'.join(L) + '\n')
print('\n'.join(L))
files = glob.glob(os.path.join(src, '**', 'rezultat-*.json'), recursive=True)
sys.exit(0 if files else 1)
