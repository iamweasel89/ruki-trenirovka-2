# Itog trenirovki raspoznavaniya (OCR)

run 40220731627, commit 47cac7744c

- progonov: 285, verno: 172, dolya: **60.4 %**
- nahozhdenie po tekstu: 53.3 %, popadanie v metku: 52.9 % (celej est: 240)
- chestnoe ne-nashel: 100.0 % (celej net: 45)
- lozhnyh klikov: **1**
- smeshchenie klika ot centra, CSS px: mediana 1, p95 6
- vremya raspoznavaniya, ms: mediana 2091, p95 **3960**
- minut runnera: 61.2

## Po planam

| plan | progonov | verno | p95 ms |
|---|---|---|---|
| blednyj | 15 | 15 | 1250 |
| blednyj-ru | 15 | 9 | 3944 |
| dvizhenie | 15 | 0 | 5560 |
| dvizhenie-en | 15 | 15 | 3398 |
| holst-en | 15 | 15 | 1894 |
| holst-ru | 15 | 2 | 4800 |
| holst-smes | 15 | 0 | 5339 |
| kartinka-en | 15 | 14 | 7327 |
| kartinka-ru | 15 | 1 | 3684 |
| melkij | 15 | 7 | 3109 |
| melkij-en | 15 | 14 | 2782 |
| migaet | 15 | 5 | 4511 |
| net-en | 15 | 15 | 4788 |
| net-kartinka | 15 | 15 | 3552 |
| net-ru | 15 | 15 | 2898 |
| pohozhie-en | 15 | 15 | 1569 |
| pohozhie-en2 | 15 | 15 | 1558 |
| pohozhie-ru | 15 | 0 | 2718 |
| pohozhie-ru2 | 15 | 0 | 2830 |

## Po masshtabu

- x1: 56 iz 95
- x1.25: 57 iz 95
- x1.5: 59 iz 95

## Prohody

- tess-eng-x2.5-otkl: raz 14, nashel 0, mediana 760 ms, p95 1076 ms
- tess-rus+eng-x1.5-otkl: raz 183, nashel 40, mediana 1129 ms, p95 1738 ms
- tess-rus+eng-x2.5-otkl: raz 143, nashel 18, mediana 978 ms, p95 1384 ms
- win-en-x1-net: raz 123, nashel 91, mediana 439 ms, p95 1121 ms
- win-en-x2-seryj: raz 32, nashel 16, mediana 610 ms, p95 1935 ms
- win-en-x2.5-otkl: raz 16, nashel 2, mediana 1024 ms, p95 2019 ms

Reshayushchij prohod: {'win-en-x1-net': 88, 'win-en-x2-seryj': 16, 'tess-rus+eng-x2.5-otkl': 8, 'tess-rus+eng-x1.5-otkl': 16}
Statusy: {'poteryal': 18, 'ne-nashel': 139, 'klik': 128}
Proverka posle klika: {'izmenilos': 117, 'bez-izmenenij': 10, 'propalo': 1}

## Prichiny neudach

- dvizhenie: ne-kliknul: ne-nashel: 15
- pohozhie-ru: ne-kliknul: ne-nashel: 15
- pohozhie-ru2: ne-kliknul: ne-nashel: 15
- kartinka-ru: ne-kliknul: ne-nashel: 14
- holst-smes: ne-kliknul: ne-nashel: 10
- migaet: ne-kliknul: ne-nashel: 10
- holst-ru: ne-kliknul: ne-nashel: 8
- melkij: ne-kliknul: ne-nashel: 8
- blednyj-ru: ne-kliknul: poteryal: 6
- holst-ru: ne-kliknul: poteryal: 5
- holst-smes: ne-kliknul: poteryal: 5
- melkij-en: ne-kliknul: poteryal: 1
- kartinka-en: lozhnyj-klik: klik: 1
