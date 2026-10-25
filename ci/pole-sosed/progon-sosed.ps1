# One neighbour-label training job: every plan of plans/pole-sosed once (order rotated by
# seed). Each step of a plan is a separate call of skills/vvesti-u-metki.ps1, like successive
# calls of the real hands. After every call the harness reads the page's own control field and
# sees which field received input and what it holds now, so "landed in the wrong field" is
# measured by the page, not by the skill. Skill failures never fail the job: they are data.
param([int]$Seed = 1, [string]$Vyhod = 'rezultat.json', [string]$Tolko = '', [int]$LimitSkillaS = 150, [int]$BudzhetS = 1800)
$ErrorActionPreference = 'Continue'
$koren = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
. (Join-Path $koren 'lib\uia.ps1')
. (Join-Path $koren 'lib\okno.ps1')
$tmp = if ($env:RUNNER_TEMP) { $env:RUNNER_TEMP } else { [IO.Path]::GetTempPath() }
$chrome = @("$env:ProgramFiles\Google\Chrome\Application\chrome.exe", "${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe") | Where-Object { Test-Path $_ } | Select-Object -First 1
$plany = @(Get-ChildItem (Join-Path $koren 'plans\pole-sosed') -Filter *.json | Sort-Object Name | ForEach-Object { $_.FullName })
if ($Tolko) { $plany = @($plany | Where-Object { $Tolko.Split(',') -contains [IO.Path]::GetFileNameWithoutExtension($_) }) }
$vse = @()
$jobSw = [Diagnostics.Stopwatch]::StartNew()
$utf8 = New-Object Text.UTF8Encoding($false)

# last lines of a file as plain strings (Get-Content would attach provider properties that
# ConvertTo-Json walks into: minutes of work and out-of-memory)
function Get-Hvost([string]$put, [int]$n) {
  if (-not (Test-Path $put)) { return @() }
  try { $a = [IO.File]::ReadAllLines($put, [Text.Encoding]::UTF8) } catch { return @() }
  return @($a | Select-Object -Last $n)
}
function Read-Json([string]$put) {
  if (-not (Test-Path $put)) { return $null }
  try { return ([IO.File]::ReadAllText($put, [Text.Encoding]::UTF8) | ConvertFrom-Json) } catch { return $null }
}
function Stop-Lishnee {
  Get-Process chrome -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
  Start-Sleep -Milliseconds 500
}
function Get-Fnv([string]$s) {
  [uint64]$h = 2166136261
  foreach ($c in $s.ToCharArray()) { $h = (($h -bxor [uint64][int]$c) * 16777619) % 4294967296 }
  return ('{0:x8}' -f $h)
}
# the page's own summary: { pola: { id: { dl, h, vvodov, izmeneno, v } }, poryadok, pomehi }
function Read-Kontrol($stranica) {
  for ($i = 0; $i -lt 3; $i++) {
    $o = Wait-Stranica $stranica 5000
    $k = if ($o) { Find-Element $o.Doc 'kontrol' 'Kontrol' 'tekst' 3000 } else { $null }
    $txt = Get-Znachenie $k
    try { if ($txt) { return ($txt | ConvertFrom-Json) } } catch {}
    Start-Sleep -Milliseconds 400
  }
  return $null
}
function Get-Vvodov($d) {
  $m = @{}
  if ($d -and $d.pola) { foreach ($p in $d.pola.PSObject.Properties) { $m[$p.Name] = [int]$p.Value.vvodov } }
  return $m
}
function Save-Itog {
  $itog = [ordered]@{ seed = $Seed; sekund = [int]$jobSw.Elapsed.TotalSeconds; progony = $vse }
  try { [IO.File]::WriteAllText($Vyhod, ($itog | ConvertTo-Json -Depth 10), $utf8) }
  catch {
    $m = ($_.Exception.Message -replace '[\\"\r\n\t]', ' ')
    [IO.File]::WriteAllText($Vyhod, "{`"seed`": $Seed, `"oshibka`": `"json: $m`", `"progonov`": $($vse.Count)}", $utf8)
  }
}

Save-Itog
for ($r = 0; $r -lt $plany.Count; $r++) {
  if ($jobSw.Elapsed.TotalSeconds -gt $BudzhetS) { Write-Host "budzhet ischerpan na progone $r"; break }
  $plan = $null
  try {
    $planPut = $plany[($Seed + $r) % $plany.Count]
    $plan = Read-Json $planPut
    $imya = $plan.imya
    $s = $Seed * 1000 + $r
    $rnd = New-Object Random($s)
    $skroll = ($imya -eq 'skroll') -or ($rnd.Next(0, 3) -eq 0)
    $fajl = $plan.stranica.url_soderzhit.TrimStart('/') -replace '/', '\'
    $stranicaPut = (Join-Path $koren $fajl) -replace '\\', '/'
    $url = "file:///$stranicaPut`?seed=$s&skroll=$([int]$skroll)"
    Stop-Lishnee
    $prof = Join-Path $tmp "cprof_$s"
    $arg = @('--new-window', "--user-data-dir=$prof", '--no-first-run', '--no-default-browser-check',
             '--force-renderer-accessibility', '--disable-features=Translate', '--start-maximized', $url)
    $null = Start-Process $chrome -ArgumentList $arg -PassThru
    $null = Wait-Stranica $plan.stranica 60000
    Start-Sleep -Milliseconds 300
    $log = Join-Path $tmp "log_$s.txt"
    Remove-Item $log -ErrorAction SilentlyContinue
    $env:RUKI_LOG = $log
    $bylo = Get-Vvodov (Read-Kontrol $plan.stranica)
    $shagi = @()
    $ozhid = @{}
    $n = 0
    foreach ($sh in $plan.shagi) {
      $n++
      $zad = Join-Path $tmp "zad_${s}_$n.json"
      $out = Join-Path $tmp "sk_${s}_$n.json"
      Remove-Item $out -ErrorAction SilentlyContinue
      [IO.File]::WriteAllText($zad, ([ordered]@{ stranica = $plan.stranica; metka = $sh.metka; znachenie = $sh.znachenie } | ConvertTo-Json -Depth 4), $utf8)
      $skSw = [Diagnostics.Stopwatch]::StartNew()
      $zapusk = ''
      try {
        $pr = Start-Process powershell.exe -PassThru -WindowStyle Hidden -RedirectStandardOutput (Join-Path $tmp "so_${s}_$n.txt") -RedirectStandardError (Join-Path $tmp "se_${s}_$n.txt") -ArgumentList @(
          '-NoProfile', '-STA', '-ExecutionPolicy', 'Bypass', '-File', "`"$(Join-Path $koren 'skills\vvesti-u-metki.ps1')`"", '-Zadanie', "`"$zad`"", '-Vyhod', "`"$out`"")
        if (-not $pr.WaitForExit($LimitSkillaS * 1000)) { try { $pr.Kill() } catch {}; $zapusk = "ubit-po-limitu ${LimitSkillaS}s" }
        else { $zapusk = "kod=$($pr.ExitCode)" }
      } catch { $zapusk = $_.Exception.Message }
      $skMs = [int]$skSw.ElapsedMilliseconds
      $sk = Read-Json $out
      Start-Sleep -Milliseconds 500
      $d = Read-Kontrol $plan.stranica
      $stalo = Get-Vvodov $d
      $kuda = @($stalo.Keys | Where-Object { $stalo[$_] -gt [int]$bylo[$_] } | Sort-Object)
      $bylo = $stalo
      $st = if ($sk) { [string]$sk.status } else { 'net-rezultata' }
      $pri = if ($sk) { [string]$sk.prichina } else { $zapusk }
      $z = [ordered]@{ n = $n; metka = $sh.metka; dlina = ([string]$sh.znachenie).Length; status = $st; prichina = $pri; kuda_popalo = $kuda; skill_ms = $skMs; zapusk = $zapusk }
      if ($sk) {
        $z.vybor = $sk.vybor; $z.kandidatov = @($sk.kandidaty).Count; $z.otkazy = $sk.otkazy; $z.popytki = $sk.popytki; $z.fokus = $sk.fokus; $z.etapy = $sk.etapy; $z.pomehi = $sk.pomehi
        if ($st -ne 'ok') { $z.kandidaty = $sk.kandidaty; $z.podrobno = $sk.podrobno }
      }
      if ($sh.ozhid_stop) {
        $z.ozhid_stop = $sh.ozhid_stop
        $z.ok = ($st -eq 'stop') -and ($pri -eq $sh.ozhid_stop) -and ($kuda.Count -eq 0)
        $z.mimo = @($kuda)
      } else {
        $z.pole = $sh.pole
        $cel = [string]$sh.znachenie
        $f = if ($d) { $d.pola.($sh.pole) } else { $null }
        $znOk = $f -and ([int]$f.dl -eq $cel.Length) -and ([string]$f.h -eq (Get-Fnv $cel))
        $z.mimo = @($kuda | Where-Object { $_ -ne $sh.pole })
        $z.ok = ($st -eq 'ok') -and [bool]$znOk -and ($z.mimo.Count -eq 0) -and ($kuda -contains $sh.pole)
        if (-not $znOk -and $f) { $z.fakt = [ordered]@{ dl = $f.dl; v = $f.v } }
        $ozhid[[string]$sh.pole] = $cel
      }
      $shagi += $z
      Write-Host ("  shag {0} '{1}': {2} {3} kuda=[{4}] ok={5} {6} ms" -f $n, $sh.metka, $st, $pri, ($kuda -join ','), $z.ok, $skMs)
    }
    # final state: target fields hold the last value meant for them, every other field untouched
    $d = Read-Kontrol $plan.stranica
    $rash = @()
    $mimoItog = @()
    if (-not $d) { $rash += 'net-kontrolya' }
    else {
      foreach ($p in $d.pola.PSObject.Properties) {
        $id = $p.Name; $f = $p.Value
        if ($ozhid.ContainsKey($id)) {
          $cel = $ozhid[$id]
          if (-not (([int]$f.dl -eq $cel.Length) -and ([string]$f.h -eq (Get-Fnv $cel)))) { $rash += "znachenie:$id" }
        } elseif ($f.izmeneno -or [int]$f.vvodov -gt 0) { $mimoItog += $id; $rash += "mimo:$id" }
      }
    }
    $plohie = @($shagi | Where-Object { -not $_.ok } | ForEach-Object { "shag$($_.n)" })
    $uspeh = ($rash.Count -eq 0) -and ($plohie.Count -eq 0)
    $logTail = @(Get-Hvost $log 60)
    $vse += [ordered]@{
      progon = $r; seed = $s; plan = $imya; skroll = $skroll; uspeh = $uspeh
      prichina = $(if ($uspeh) { 'ok' } else { (@($plohie) + @($rash)) -join ',' })
      mimo_itog = $mimoItog; pomehi_stranicy = $(if ($d) { @($d.pomehi) } else { @() }); poryadok = $(if ($d) { @($d.poryadok) } else { @() })
      shagi = $shagi; log = $logTail
    }
    Write-Host ("[{0}/{1}] {2} seed={3} skroll={4} uspeh={5} {6}" -f ($r + 1), $plany.Count, $imya, $s, $skroll, $uspeh, $vse[-1].prichina)
    $kr = ($shagi | ForEach-Object { "$($_.n):$($_.status)/$($_.prichina)/$(if ($_.vybor) { $_.vybor.sposob })/[$($_.kuda_popalo -join ' ')]" }) -join ' '
    Write-Host ("::notice title=sosed {0} {1}::uspeh={2} skroll={3} {4} | {5}" -f $Seed, $imya, $uspeh, $skroll, $vse[-1].prichina, $kr)
    if (-not $uspeh) {
      $hv = (($logTail | Where-Object { $_ -match 'STOP|SBOJ|kandidat|vybor|fokus|vvod:|snimok|geometriya' } | Select-Object -Last 10) -join ' / ') -replace '[\r\n]', ' '
      Write-Host ("::warning title=sosed {0} {1} log::{2}" -f $Seed, $imya, $hv)
    }
    Stop-Lishnee
  } catch {
    $vse += [ordered]@{ progon = $r; plan = $(if ($plan) { $plan.imya } else { $planPut }); uspeh = $false; prichina = 'sboj-stenda';
      log = @("STEND: $($_.Exception.Message)", [string]$_.ScriptStackTrace) }
    Write-Host "STEND: $($_.Exception.Message) $($_.ScriptStackTrace)"
    Stop-Lishnee
  }
  Save-Itog
}
Save-Itog
exit 0
