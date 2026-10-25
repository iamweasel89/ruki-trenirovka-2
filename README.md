# ruki-trenirovka

Training ground for generic desktop UI movements on Windows: UIA element search,
SendInput unicode typing with focus checks and read-back, Enter/Tab/Esc, window
visibility, and a hard stop on password fields.

- `polygon/` neutral local practice pages with seeded disturbances
  (delay, popping modal, focus moved away, re-render that clears a field)
- `lib/` PowerShell library of movements
- `skills/zapolnit-formu.ps1` fill a form by a JSON plan (`plans/`)
- `ci/progon.ps1` one training job; `ci/svod.py` aggregation
- `ci/proverka-gigieny.ps1` public hygiene check (runs first in CI)

Results of the last run are published to the branch `itog` (`itog.md`, `itog.json`).

## Trainer: field next to its label (branch `trener-pole-sosed`)

- `polygon/pole-sosed/` pages: a replica of a profile form with nameless contenteditable
  fields (one shows the literal text `<div><br></div>`), labels above / left / in wrappers,
  a column layout, hidden copies (collapsed, 1x1 clipped, far off the page), a shadow root,
  six nested wrappers, a page that jumps and drifts. Each page checks itself: final value of
  every field and how many input events each field received.
- `lib/sosed.ps1` label -> field resolution, `lib/pole-vvod.ps1` click, type, read back,
  `lib/mysh.ps1` DPI awareness, click, hit test
- `skills/vvesti-u-metki.ps1` one call: type a value into the field named by a label
- `ci/pole-sosed/` plans generator, harness, aggregation; workflow `pole-sosed.yml`;
  results on the branch `itog-pole-sosed`
