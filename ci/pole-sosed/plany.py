#!/usr/bin/env python3
"""Generate the neighbour-label plans into plans/pole-sosed/ (deterministic). usage: plany.py
A plan is one page and a list of skill calls. Each call names a label and a value; `pole` is
the data-pole id the value must land in (known to the harness only, never to the skill);
`ozhid_stop` is the honest stop expected instead (no field may change)."""
import json, os, random

koren = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
out = os.path.join(koren, 'plans', 'pole-sosed')
os.makedirs(out, exist_ok=True)


def stranica(imya, zag):
    return {'url_soderzhit': f'/polygon/pole-sosed/{imya}.html', 'zagolovok_soderzhit': f'Poligon - Pole sosed: {zag}'}


def v(metka, znachenie, pole):
    return {'metka': metka, 'znachenie': znachenie, 'pole': pole}


def stop(metka, prichina, znachenie='x'):
    return {'metka': metka, 'znachenie': znachenie, 'ozhid_stop': prichina}


def dlinnyj(n, seed=5):
    r = random.Random(seed)
    slova = ['опыт', 'работы', 'с', 'автоматизацией', 'интерфейсов', 'и', 'проверкой', 'результата',
             'пишу', 'скрипты', 'для', 'рабочего', 'стола', 'браузера', 'Windows', 'UIA', 'данных', 'форм']
    s = []
    while sum(len(x) + 1 for x in s) < n:
        s.append(r.choice(slova))
    t = ' '.join(s)
    return t[:n].rstrip() + '.'


PROFIL = stranica('kwork', 'profil')
plany = {
    # the real case: labels as plain text, nameless contenteditable fields, one of them shows
    # the literal text <div><br></div>; a copy of "About You" sits off the page
    'kwork': {'stranica': PROFIL, 'shagi': [
        v('Your Name', 'Иван Петров', 'imya'),
        v('What do you do?', 'Desktop automation and scripts', 'specialnost'),
        v('About You', 'I build reliable UI automation for Windows desktops.', 'o-sebe'),
    ]},
    # successive calls must land in the same field: placeholder first, then the label twice
    'kwork-povtor': {'stranica': PROFIL, 'shagi': [
        v('I have over 5 years of experience in...', 'First version', 'o-sebe'),
        v('About You', 'Second version, replaced', 'o-sebe'),
        v('About You', 'Третья, окончательная версия', 'o-sebe'),
        v('Your Name', 'Anna', 'imya'),
    ]},
    # a label with no field of its own: the next field belongs to another label
    'kwork-foto-stop': {'stranica': PROFIL, 'shagi': [
        stop('Profile Picture', 'net-polya'),
        v('What do you do?', 'Testing', 'specialnost'),
    ]},
    # long value: more than 10000 UTF-8 bytes, ValuePattern is cut, read back via TextPattern
    'kwork-dlinnyj': {'stranica': PROFIL, 'shagi': [
        v('About You', dlinnyj(6200), 'o-sebe'),
    ]},
    'sverhu': {'stranica': stranica('sverhu', 'metka sverhu'), 'shagi': [
        v('First name', 'Ivan', 'imya'),
        v('Last name', 'Petrov', 'familiya'),
        v('Postal code', '12345', 'indeks'),
        v('Email address', 'ivan.petrov.example', 'pochta'),
        v('Message', 'Please call after six, thank you.', 'soobshchenie'),
        v('Signature', 'И. Петров', 'podpis'),
    ]},
    'sleva': {'stranica': stranica('sleva', 'metka sleva'), 'shagi': [
        v('City', 'Springfield', 'gorod'),
        v('Street', 'Main Street', 'ulica'),
        v('House', '12', 'dom'),
        v('Flat', '7', 'kvartira'),
        v('Fax', '0200 000 222', 'faks'),
        v('Phone', '0900 000 111', 'telefon'),
        v('Courier note', 'Ring twice', 'zametka'),
    ]},
    'obertka': {'stranica': stranica('obertka', 'obertka'), 'shagi': [
        v('Company name', 'Polygon Works', 'firma'),
        v('Registration number', '12345678', 'nomer'),
        v('Website', 'polygon.example', 'sajt'),
        v('Short description', 'Small team, reliable tools.', 'opisanie'),
    ]},
    # hidden copies: collapsed, clipped 1x1, and far off the page
    'dubl': {'stranica': stranica('dubl', 'dubli'), 'shagi': [
        v('Anything we should know', 'Leave at the door', 'zametka'),
        v('Company', 'Polygon Works', 'firma'),
        v('Email', 'orders.example', 'pochta'),
        v('Order note', 'Ring twice', 'zametka'),
    ]},
    # two visible fields with the same label, and a label that is not on the page
    'dubl-stop': {'stranica': stranica('dubl', 'dubli'), 'shagi': [
        stop('Comment', 'neodnoznachno'),
        stop('Fax number', 'net-metki'),
        v('Email', 'after.stops', 'pochta'),
    ]},
    'ten': {'stranica': stranica('ten', 'ten'), 'shagi': [
        v('Project title', 'Neighbour label', 'nazvanie'),
        v('Budget', '1500', 'byudzhet'),
        v('Deadline', '30.11.2026', 'srok'),
        v('Requirements', 'Zero typing into the wrong field.', 'trebovaniya'),
    ]},
    # the page jumps and drifts between and during calls
    'skroll': {'stranica': stranica('skroll', 'skroll'), 'shagi': [
        v('Position held', 'Operator', 'dolzhnost'),
        v('Applicant name', 'Ivan', 'imya'),
        v('Cover letter', 'I would like to apply.', 'pismo'),
        v('Previous employer', 'Polygon Works', 'rabota'),
        v('Applicant name', 'Ivan Petrov', 'imya'),
    ]},
}

for imya, p in plany.items():
    p = {'imya': imya, **p}
    with open(os.path.join(out, imya + '.json'), 'w', encoding='utf-8', newline='\n') as f:
        json.dump(p, f, ensure_ascii=False, indent=1)
        f.write('\n')
print('plans:', ', '.join(plany))
