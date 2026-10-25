#!/usr/bin/env python3
"""Aggregate neighbour-label results into itog.json + itog.md.
usage: svod-sosed.py <dir with rezultat-*.json> <out dir> [jobs.json]
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


faily = sorted(glob.glob(os.path.join(src, '**', 'rezultat-*.json'), recursive=True))
raboty, oshibki = [], []
for p in faily:
    try:
        rb = load(p); raboty.append(rb)
        if rb.get('oshibka'): oshibki.append(f"{os.path.basename(p)}: {rb.get('oshibka')}")
    except Exception as e:
        oshibki.append(f'{os.path.basename(p)}: {e}')

vsego = uspeh = 0
shagov = shagov_ok = 0
mimo_shagov = 0          # calls after which input landed in a field that was not the target
mimo_polya = collections.Counter()
po_planu = collections.defaultdict(lambda: {'progonov': 0, 'uspeh': 0, 'skroll': 0})
sposoby = collections.Counter()
dostup = collections.Counter()
ostanovki = collections.Counter()
ozhid_ostanovki = collections.Counter()
pomehi = collections.Counter()
fokus = collections.Counter()
ms = collections.defaultdict(list)
neudachi = []
for rb in raboty:
    for pr in spisok(rb.get('progony')):
        vsego += 1
        pl = pr.get('plan')
        b = po_planu[pl]; b['progonov'] += 1
        if pr.get('skroll'): b['skroll'] += 1
        if pr.get('uspeh'): uspeh += 1; b['uspeh'] += 1
        for m in spisok(pr.get('mimo_itog')): mimo_polya[f'{pl}.{m}'] += 1
        for sh in spisok(pr.get('shagi')):
            shagov += 1
            if sh.get('ok'): shagov_ok += 1
            if spisok(sh.get('mimo')):
                mimo_shagov += 1
                for m in spisok(sh.get('mimo')): mimo_polya[f'{pl}.{m}'] += 1
            vb = sh.get('vybor') or {}
            if vb.get('sposob'): sposoby[vb['sposob']] += 1
            if vb.get('dostup'): dostup[vb['dostup']] += 1
            if sh.get('fokus'): fokus[sh['fokus']] += 1
            if sh.get('status') != 'ok':
                key = f"{sh.get('prichina')}"
                (ozhid_ostanovki if sh.get('ozhid_stop') == sh.get('prichina') else ostanovki)[key] += 1
            for k, v in (sh.get('pomehi') or {}).items(): pomehi[k] += v
            if sh.get('skill_ms'): ms[pl].append(sh['skill_ms'])
        if not pr.get('uspeh'):
            neudachi.append({'seed': pr.get('seed'), 'plan': pl, 'skroll': pr.get('skroll'), 'prichina': pr.get('prichina'),
                             'shagi': [s for s in spisok(pr.get('shagi')) if not s.get('ok')],
                             'log': spisok(pr.get('log'))[-30:]})

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
    'progonov': vsego, 'uspeh': uspeh, 'dolya_uspeha_proc': dolya,
    'vyzovov': shagov, 'vyzovov_ok': shagov_ok, 'vyzovov_mimo_polya': mimo_shagov, 'mimo_polya': dict(mimo_polya),
    'po_planam': {k: {**v, 'mediana_vyzova_ms': int(statistics.median(ms[k])) if ms[k] else None} for k, v in sorted(po_planu.items())},
    'sposob_vybora': dict(sposoby), 'dostup_vybrannogo': dict(dostup), 'fokus': dict(fokus),
    'ozhidaemye_ostanovki': dict(ozhid_ostanovki), 'neozhidannye_ostanovki': dict(ostanovki), 'pomehi': dict(pomehi),
    'minut_runnera': minuty, 'oshibki_chteniya': oshibki, 'neudachi': neudachi[:30],
}
with open(os.path.join(dst, 'itog.json'), 'w', encoding='utf-8') as f:
    json.dump(itog, f, ensure_ascii=False, indent=1)

L = ['# Itog trenirovki: pole u metki', '', f"run {itog['run']}, commit {str(itog['sha'])[:10]}", '',
     f'- progonov: {vsego}, uspeh: {uspeh}, dolya: **{dolya} %**',
     f'- vyzovov skilla: {shagov}, verno: {shagov_ok}',
     f'- vyzovov s vvodom v chuzhoe pole: **{mimo_shagov}**',
     f'- minut runnera (vse raboty): {minuty}', '', '## Po planam', '']
for k, v in itog['po_planam'].items():
    L.append(f"- {k}: {v['uspeh']}/{v['progonov']} (so skrollom {v['skroll']}), mediana vyzova {v['mediana_vyzova_ms']} ms")
L += ['', '## Sposob vybora polya', ''] + [f'- {k}: {v}' for k, v in sposoby.most_common()]
L += ['', '## Dostupnost vybrannogo', ''] + [f'- {k}: {v}' for k, v in dostup.most_common()]
L += ['', '## Fokus', ''] + [f'- {k}: {v}' for k, v in fokus.most_common()]
L += ['', '## Ozhidaemye ostanovki', ''] + ([f'- {k}: {v}' for k, v in ozhid_ostanovki.most_common()] or ['- net'])
L += ['', '## Neozhidannye ostanovki', ''] + ([f'- {k}: {v}' for k, v in ostanovki.most_common()] or ['- net'])
L += ['', '## Vvod v chuzhoe pole', ''] + ([f'- {k}: {v}' for k, v in mimo_polya.most_common()] or ['- net'])
L += ['', '## Pomehi', ''] + [f'- {k}: {v}' for k, v in pomehi.most_common()]
if neudachi:
    L += ['', '## Neudachi (pervye)', '']
    for n in neudachi[:12]:
        L.append(f"- {n['plan']} seed {n['seed']} skroll {n['skroll']}: {n['prichina']}")
        for s in n['shagi'][:3]:
            vb = s.get('vybor') or {}
            L.append(f"  - shag {s.get('n')} '{s.get('metka')}': {s.get('status')} {s.get('prichina')} kuda={s.get('kuda_popalo')} sposob={vb.get('sposob')} {vb.get('pochemu', '')[:160]}")
if oshibki: L += ['', '## Oshibki chteniya', ''] + [f'- {x}' for x in oshibki]
with open(os.path.join(dst, 'itog.md'), 'w', encoding='utf-8') as f:
    f.write('\n'.join(L) + '\n')
print('\n'.join(L))
sys.exit(0 if faily else 1)
