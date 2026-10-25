# Skill: type a value into the field named by its neighbour label.
# Input: a JSON task file { stranica: { url_soderzhit, zagolovok_soderzhit }, metka, znachenie }.
# Output: JSON with status ok|stop, the reason of a stop, the chosen field and why, every
# candidate that was considered, timings. Never guesses: an ambiguous label is a stop.
param(
  [Parameter(Mandatory = $true)][string]$Zadanie,
  [Parameter(Mandatory = $true)][string]$Vyhod,
  [int]$TimeoutStranicyMs = 25000
)
$ErrorActionPreference = 'Continue'
$koren = Split-Path -Parent $PSScriptRoot
. (Join-Path $koren 'lib\uia.ps1')
. (Join-Path $koren 'lib\okno.ps1')
. (Join-Path $koren 'lib\vvod.ps1')
. (Join-Path $koren 'lib\mysh.ps1')
. (Join-Path $koren 'lib\sosed.ps1')
. (Join-Path $koren 'lib\pole-vvod.ps1')

$sw = [Diagnostics.Stopwatch]::StartNew()
$zd = [IO.File]::ReadAllText($Zadanie, [Text.Encoding]::UTF8) | ConvertFrom-Json
$rez = [ordered]@{ metka = [string]$zd.metka; status = 'stop'; prichina = ''; podrobno = ''; vybor = $null; kandidaty = @(); otkazy = @(); popytki = 0; fokus = $null; pomehi = @{}; etapy = [ordered]@{}; dpi = [RukiMysh]::Dpi; ms = 0 }
$ctx = @{ Doc = $null; Okno = $null; Hwnd = [IntPtr]::Zero; Pomehi = @{} }
Write-RukiLog "start metka='$($zd.metka)' dlina=$(([string]$zd.znachenie).Length) dpi=$([RukiMysh]::Dpi)"

function Save-Rez {
  $rez.ms = [int]$sw.ElapsedMilliseconds
  $rez.pomehi = $ctx.Pomehi
  try { [IO.File]::WriteAllText($Vyhod, ($rez | ConvertTo-Json -Depth 8), (New-Object Text.UTF8Encoding($false))) }
  catch { [IO.File]::WriteAllText($Vyhod, "{`"status`": `"stop`", `"prichina`": `"json`"}") }
}
function Stop-Skill([string]$prichina, [string]$podrobno = '') {
  $rez.status = 'stop'; $rez.prichina = $prichina; $rez.podrobno = $podrobno
  Write-RukiLog "STOP $prichina $podrobno"
  Save-Rez
  exit 0
}

try {
  $o = Wait-Stranica $zd.stranica $TimeoutStranicyMs
  if (-not $o) { Stop-Skill 'net-stranicy' }
  $ctx.Doc = $o.Doc; $ctx.Okno = $o.Okno; $ctx.Hwnd = $o.Hwnd
  $v = Confirm-OknoVidimo $ctx.Hwnd
  if (-not $v.Ok) { Stop-Skill 'okno-ne-vidno' $v.Bylo }
  $rez.etapy.stranica = [int]$sw.ElapsedMilliseconds

  $res = Resolve-PoleUMetki $ctx.Doc ([string]$zd.metka)
  $rez.etapy.poisk = [int]$sw.ElapsedMilliseconds
  $rez.kandidaty = @($res.Kandidaty)
  $rez.otkazy = @($res.Otkazy)
  if ($res.Status -ne 'ok') { Stop-Skill $res.Prichina ("kandidatov $(@($res.Kandidaty).Count), otkazov $(@($res.Otkazy).Count)") }
  $rez.vybor = $res.Vybor
  Write-RukiLog "vybor: $($res.Vybor.sposob) $($res.Vybor.dostup) | $($res.Vybor.pochemu)"

  $t = Set-TekstVPole $ctx $res.Uzel ([string]$zd.znachenie)
  $rez.etapy.vvod = [int]$sw.ElapsedMilliseconds
  $rez.popytki = $t.Popytki
  $rez.fokus = $t.Fokus
  if ($t.Status -ne 'ok') { Stop-Skill $t.Prichina ([string]$t.Podrobno) }
  $rez.status = 'ok'
  $rez.prichina = ''
  Write-RukiLog "OK popytok $($t.Popytki) fokus $($t.Fokus) prochitano $($t.Prochitano)"
} catch {
  $rez.status = 'stop'; $rez.prichina = 'sboj-skilla'; $rez.podrobno = ($_.Exception.Message + ' ' + [string]$_.ScriptStackTrace)
  Write-RukiLog "SBOJ $($rez.podrobno)"
}
Save-Rez
exit 0
