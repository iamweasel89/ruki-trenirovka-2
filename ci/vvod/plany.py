#!/usr/bin/env python3
"""Generate the input-fidelity plans into plans/vvod/ (deterministic). usage: plany.py"""
import json, os, random

koren = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
out = os.path.join(koren, 'plans', 'vvod')
os.makedirs(out, exist_ok=True)
NB = ' '

def u16(s):
    return len(s.encode('utf-16-le')) // 2

def stranica(imya, zag):
    return {'url_soderzhit': f'/polygon/vvod/{imya}.html', 'zagolovok_soderzhit': f'Полигон — Ввод: {zag}'}

FRAZY = [
    'Съешь же ещё этих мягких французских булок, да выпей чаю.',
    'Ёжик в тумане сказал: «Лошадка!» — и замолчал…',
    'Saya tinggal di Jl. Pèndhèk No. 7, Kebayoran Baru — Jakarta Selatan.',
    'Bahasa Jawa: “Sugeng énjing, piyé kabaré?” — ‘apik’, jawabé.',
    'Slovenčina: Ďakujem, že ste prišli včas; ľúbim kôň a ťavu.',
    f'Цена: 1{NB}000{NB}₽, скидка 15{NB}%, итог — 850{NB}₽.',
    'Kutipan „Jerman“ dan «Prancis» serta "lurus" dan \'tunggal\'.',
    'Тире – короткое, — длинное, ‑ неразрывный дефис, − минус.',
    'Эмодзи: 👍🏽 👨‍👩‍👧 🇸🇰 🧪 ✅ — и снова текст.',
    'Combining: café vs café, ё vs ё.',
    'Числа: 3,14 и 3.14; 1 000 000 и 1,000,000; 2026-10-25.',
    'Kode:\tkolom1\tkolom2\tkolom3',
    'Скобки (а) [б] {в} <г> и знаки ?!;:%#@&*_+=~^|\\/',
]

def dlinnyj_tekst(n, seed=7):
    r = random.Random(seed)
    stroki, dl = [], 0
    while True:
        s = ' '.join(r.choice(FRAZY) for _ in range(r.randint(1, 4)))
        if r.random() < 0.15:
            s = '\t' + s
        if dl + u16(s) + 1 > n:
            break
        stroki.append(s); dl += u16(s) + 1
    t = '\n'.join(stroki)
    hvost = n - u16(t) - 1
    t += '\n' + ('Конец.' + 'я' * n)[:max(0, hvost)]
    assert u16(t) == n, (u16(t), n)
    return t

KOD = 'def summa(spisok):\n\titogo = 0\n\tfor x in spisok:\n\t\titogo += x  # «складываем»\n\treturn itogo\n\n\tstroka\tс\tтабами\tи пробелами   в конце   \nПоследняя строка — без перевода'

PISMO = ('Здравствуйте, Ольга Петровна!\n'
         'Пишу по поводу заявки № 417 — «Ремонт подъезда».\n'
         'Saya setuju dengan jadwalnya; Ďakujem.\n'
         '\n'
         'С уважением, Ж. Щукин 👍🏽')

def otzyv(n):
    baza = 'Отличный сервис 👍🏽 — быстро, «вежливо», без лишних слов. Pelayanan cepat dan ramah, terima kasih! '
    s = (baza * 5)
    while u16(s) > n: s = s[:-1]
    if u16(s) < n:
        s = s + 'x' * (n - u16(s))
    # do not end on half a surrogate pair
    if '\ud800' <= s[-1] <= '\udbff':
        s = s[:-1] + 'y'
    assert u16(s) == n
    return s

plany = {
    'dlinnyj': {
        'stranica': stranica('dlinnyj', 'длинный текст'),
        'shagi': [
            {'tip': 'tekst', 'id': 'dlinnyj', 'metka': 'Длинный текст', 'znachenie': dlinnyj_tekst(20000)},
            {'tip': 'tekst', 'id': 'kod', 'metka': 'Код с табуляцией', 'znachenie': KOD},
            {'tip': 'knopka', 'id': 'sohranit', 'metka': 'Сохранить текст', 'final': True, 'posle': {'tip': 'tekst', 'id': 'itog', 'metka': 'Итог'}},
        ]},
    'srednij': {
        'stranica': stranica('dlinnyj', 'длинный текст'),
        'shagi': [
            {'tip': 'tekst', 'id': 'dlinnyj', 'metka': 'Длинный текст', 'znachenie': dlinnyj_tekst(3000, seed=11)},
            {'tip': 'tekst', 'id': 'kod', 'metka': 'Код с табуляцией', 'znachenie': 'a\tb\nв\tг'},
            {'tip': 'knopka', 'id': 'sohranit', 'metka': 'Сохранить текст', 'final': True, 'posle': {'tip': 'tekst', 'id': 'itog', 'metka': 'Итог'}},
        ]},
    'unikod': {
        'stranica': stranica('unikod', 'юникод'),
        'shagi': [
            {'tip': 'tekst', 'id': 'imya', 'metka': 'Имя', 'znachenie': 'Ёлка-Мария д’Артаньян-Щукина'},
            {'tip': 'tekst', 'id': 'alamat', 'metka': 'Alamat', 'znachenie': 'Jl. Pèndhèk No. 7 — Kebayoran Baru, Jakarta Selatan'},
            {'tip': 'tekst', 'id': 'citata', 'metka': 'Цитата', 'znachenie': f'«Ёжик» сказал: „Привет“ – “hi” ‘ok’… 1{NB}000{NB}₽'},
            {'tip': 'tekst', 'id': 'emodzi', 'metka': 'Эмодзи', 'znachenie': 'Ура 👍🏽 👨‍👩‍👧 🇸🇰 café ✅'},
            {'tip': 'tekst', 'id': 'pismo', 'metka': 'Письмо без вставки', 'znachenie': PISMO},
            {'tip': 'knopka', 'id': 'sohranit', 'metka': 'Сохранить', 'final': True, 'posle': {'tip': 'tekst', 'id': 'itog', 'metka': 'Итог'}},
        ]},
    'limit-ok': {
        'stranica': stranica('limit', 'ограничения'),
        'shagi': [
            {'tip': 'tekst', 'id': 'kod', 'metka': 'Код до 12', 'znachenie': 'AB-12_ЖЮ-345'},
            {'tip': 'tekst', 'id': 'tema', 'metka': 'Тема', 'znachenie': 'Тема — одной строкой, без переносов'},
            {'tip': 'tekst', 'id': 'otzyv', 'metka': 'Отзыв до 140', 'znachenie': otzyv(140)},
            {'tip': 'knopka', 'id': 'sohranit', 'metka': 'Отправить отзыв', 'final': True, 'posle': {'tip': 'tekst', 'id': 'itog', 'metka': 'Итог'}},
        ]},
    'limit-stop': {
        'ozhidaetsya_ostanovka': 'limit-dliny',
        'stranica': stranica('limit', 'ограничения'),
        'shagi': [
            {'tip': 'tekst', 'id': 'kod', 'metka': 'Код до 12', 'znachenie': 'ABCDEFGHIJKLMNO'},
            {'tip': 'knopka', 'id': 'sohranit', 'metka': 'Отправить отзыв', 'final': True},
        ]},
    'limit-stop-vstavka': {
        'ozhidaetsya_ostanovka': 'limit-dliny',
        'stranica': stranica('limit', 'ограничения'),
        'shagi': [
            {'tip': 'tekst', 'id': 'otzyv', 'metka': 'Отзыв до 140', 'znachenie': otzyv(210)},
            {'tip': 'knopka', 'id': 'sohranit', 'metka': 'Отправить отзыв', 'final': True},
        ]},
    'perenos-stop': {
        'ozhidaetsya_ostanovka': 'perenos-v-odnostrochnom',
        'stranica': stranica('limit', 'ограничения'),
        'shagi': [
            {'tip': 'tekst', 'id': 'tema', 'metka': 'Тема', 'znachenie': 'Первая строка темы\nвторая строка'},
            {'tip': 'knopka', 'id': 'sohranit', 'metka': 'Отправить отзыв', 'final': True},
        ]},
    'avtodop': {
        'stranica': stranica('avtodop', 'подсказки'),
        'shagi': [
            {'tip': 'avtodop', 'id': 'kota', 'metka': 'Kota', 'vvod': 'Band', 'znachenie': 'Bandar Lampung'},
            {'tip': 'avtodop', 'id': 'ulica', 'metka': 'Улица', 'vvod': 'Брат', 'znachenie': 'Братиславская'},
            {'tip': 'avtodop', 'id': 'krajina', 'metka': 'Krajina', 'vvod': 'Slov', 'znachenie': 'Slovenská republika'},
            {'tip': 'knopka', 'id': 'sohranit', 'metka': 'Сохранить адрес', 'final': True, 'posle': {'tip': 'tekst', 'id': 'itog', 'metka': 'Итог'}},
        ]},
    'chislo': {
        'stranica': stranica('chislo', 'числа'),
        'shagi': [
            {'tip': 'chislo', 'id': 'summa_ru', 'metka': 'Сумма ru', 'lokal': 'ru', 'znachenie': f'1{NB}234{NB}567,89'},
            {'tip': 'chislo', 'id': 'summa_en', 'metka': 'Amount en', 'lokal': 'en', 'znachenie': '12,345.60'},
            {'tip': 'chislo', 'id': 'summa_de', 'metka': 'Betrag de', 'lokal': 'de', 'znachenie': '9.876,05'},
            {'tip': 'chislo', 'id': 'kolichestvo', 'metka': 'Количество', 'znachenie': '12.75'},
            {'tip': 'knopka', 'id': 'sohranit', 'metka': 'Сохранить суммы', 'final': True, 'posle': {'tip': 'tekst', 'id': 'itog', 'metka': 'Итог'}},
        ]},
}

for imya, p in plany.items():
    p = {'imya': imya, **p}
    with open(os.path.join(out, imya + '.json'), 'w', encoding='utf-8', newline='\n') as f:
        json.dump(p, f, ensure_ascii=False, indent=1)
        f.write('\n')
print('plans:', ', '.join(plany))
