# Click by text seen on the screen (recognition, not UIA): for canvases, custom-drawn
# controls, text in pictures, game-like UI. Finds the phrase, reads it a second time
# (confirms and measures motion), clicks the predicted centre, reads after the action.
# Usage: klik-po-tekstu.ps1 -Tekst 'Save' [-Okno 'part of the window title'] [-TolkoNajti] [-Vyhod out.json]
#        klik-po-tekstu.ps1 -Plan plan.json   (fields: cel, okno, tolko_najti)
# Statuses: klik | nashel (with -TolkoNajti) | ne-nashel | neodnoznachno | poteryal | net-okna | net-dvizhka
param([string]$Tekst = '', [string]$Okno = '', [switch]$TolkoNajti, [string]$Plan = '', [string]$Vyhod = '')
$ErrorActionPreference = 'Stop'
$koren = Split-Path -Parent $PSScriptRoot
. (Join-Path $koren 'lib\ocr.ps1')
. (Join-Path $koren 'lib\okno.ps1')
[RukiObraz]::DpiAware()
$sw = [Diagnostics.Stopwatch]::StartNew()
$rez = [ordered]@{}
try {
  if ($Plan) {
    $pl = Get-Content -Raw -Encoding UTF8 $Plan | ConvertFrom-Json
    if (-not $Tekst) { $Tekst = [string]$pl.cel }
    if (-not $Okno -and $pl.okno) { $Okno = [string]$pl.okno }
    if ($pl.tolko_najti) { $TolkoNajti = $true }
  }
  if (-not $Tekst) { throw 'net teksta dlya poiska' }
  $hwnd = [IntPtr]::Zero
  if ($Okno) {
    $hwnd = [RukiObraz]::NajtiOkno($Okno)
    if ($hwnd -eq [IntPtr]::Zero) { $rez = [ordered]@{ tekst = $Tekst; status = 'net-okna' } }
    else {
      $vid = Confirm-OknoVidimo $hwnd
      Write-RukiLog "okno: ok=$($vid.Ok) bylo=$($vid.Bylo)"
    }
  }
  if (-not $rez.status) {
    $rez = Invoke-KlikPoTekstu -Tekst $Tekst -Okno $hwnd -TolkoNajti:$TolkoNajti
  }
} catch {
  $rez = [ordered]@{ tekst = $Tekst; status = 'oshibka'; oshibka = $_.Exception.Message; gde = [string]$_.ScriptStackTrace }
}
$rez.dpi = [RukiObraz]::Dpi
$rez.dvizhki = [ordered]@{
  win = $(if ($script:WinOcr) { @($script:WinOcr.Yazyki) } else { @() })
  tess = $(if ($script:Tess) { @($script:Tess.Yazyki) } else { @() })
}
$rez.skill_ms = $sw.ElapsedMilliseconds
$json = $rez | ConvertTo-Json -Depth 6
if ($Vyhod) { $json | Out-File -FilePath $Vyhod -Encoding utf8 } else { $json }
exit 0
