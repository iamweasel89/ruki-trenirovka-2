# One input-fidelity training job: every plan of plans/vvod once (order rotated by seed),
# an independent check of what the page received (length + FNV hash per field, picked flags,
# no stray submit) and a clipboard check (an operator-like sentinel must survive the run).
# Skill failures never fail the job: they go into the result file.
param([int]$Seed = 1, [string]$Vyhod = 'rezultat.json', [string]$Tolko = '', [int]$LimitSkillaS = 150, [int]$BudzhetS = 1500)
$ErrorActionPreference = 'Continue'
# the clipboard needs a single-threaded apartment
if ([Threading.Thread]::CurrentThread.GetApartmentState() -ne 'STA') {
  & powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File $PSCommandPath -Seed $Seed -Vyhod $Vyhod -Tolko $Tolko -LimitSkillaS $LimitSkillaS -BudzhetS $BudzhetS
  exit 0
}
$koren = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
. (Join-Path $koren 'lib\uia.ps1')
. (Join-Path $koren 'lib\okno.ps1')
. (Join-Path $koren 'lib\bufer.ps1')
. (Join-Path $koren 'lib\tochnost.ps1')
$tmp = if ($env:RUNNER_TEMP) { $env:RUNNER_TEMP } else { [IO.Path]::GetTempPath() }
$chrome = @("$env:ProgramFiles\Google\Chrome\Application\chrome.exe", "${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe") | Where-Object { Test-Path $_ } | Select-Object -First 1
$plany = @(Get-ChildItem (Join-Path $koren 'plans\vvod') -Filter *.json | Sort-Object Name | ForEach-Object { $_.FullName })
if ($Tolko) { $plany = @($plany | Where-Object { $Tolko.Split(',') -contains [IO.Path]::GetFileNameWithoutExtension($_) }) }
$vse = @()
$jobSw = [Diagnostics.Stopwatch]::StartNew()
$KONTROL = [regex]::Unescape('\u041a\u043e\u043d\u0442\u0440\u043e\u043b\u044c')

# last lines of a file as plain strings: Get-Content would attach provider properties that
# ConvertTo-Json in Windows PowerShell walks into (minutes of work and out-of-memory)
function Get-Hvost([string]$put, [int]$n) {
  if (-not (Test-Path $put)) { return @() }
  try { $a = [IO.File]::ReadAllLines($put, [Text.Encoding]::UTF8) } catch { return @() }
  return @($a | Select-Object -Last $n)
}
function Stop-Lishnee {
  Get-Process chrome, notepad -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
  Start-Sleep -Milliseconds 500
}
function Get-Fnv([string]$s) {
  [uint64]$h = 2166136261
  foreach ($c in $s.ToCharArray()) { $h = (($h -bxor [uint64][int]$c) * 16777619) % 4294967296 }
  return ('{0:x8}' -f $h)
}
# sentinel like an operator's clipboard: unicode text + HTML + a private format
$SENT_TEKST = [regex]::Unescape('\u0411\u0443\u0444\u0435\u0440 \u043e\u043f\u0435\u0440\u0430\u0442\u043e\u0440\u0430: \u00ab\u0442\u0435\u0441\u0442\u00bb \ud83e\uddea') + " seed=$Seed`r`n" + [regex]::Unescape('\u0432\u0442\u043e\u0440\u0430\u044f \u0441\u0442\u0440\u043e\u043a\u0430')
function Set-Storozh {
  $o = New-Object System.Windows.Forms.DataObject
  $o.SetData([System.Windows.Forms.DataFormats]::UnicodeText, $false, $SENT_TEKST)
  $o.SetData([System.Windows.Forms.DataFormats]::Html, $false, "Version:0.9`r`n<b>storozh $Seed</b>")
  $o.SetData('RukiStorozh', $false, "metka-$Seed")
  Invoke-SPovtorom { [System.Windows.Forms.Clipboard]::SetDataObject($o, $true, 10, 50) } | Out-Null
}
function Test-Storozh {
  try {
    $do = Invoke-SPovtorom { [System.Windows.Forms.Clipboard]::GetDataObject() }
    $t = [string]$do.GetData([System.Windows.Forms.DataFormats]::UnicodeText)
    $m = [string]$do.GetData('RukiStorozh')
    $h = [string]$do.GetData([System.Windows.Forms.DataFormats]::Html)
    $ok = ($t -ceq $SENT_TEKST) -and ($m -ceq "metka-$Seed") -and ($h -like "*storozh $Seed*")
    return [ordered]@{ ok = $ok; tekst = ($t -ceq $SENT_TEKST); svoj_format = ($m -ceq "metka-$Seed"); html = ($h -like "*storozh $Seed*") }
  } catch { return [ordered]@{ ok = $false; oshibka = $_.Exception.Message } }
}

function Save-Itog {
  $itog = [ordered]@{ seed = $Seed; sekund = [int]$jobSw.Elapsed.TotalSeconds; apartment = [string][Threading.Thread]::CurrentThread.GetApartmentState(); progony = $vse }
  try { ($itog | ConvertTo-Json -Depth 9) | Out-File -FilePath $Vyhod -Encoding utf8 }
  catch {
    $m = ($_.Exception.Message -replace '[\\"\r\n\t]', ' ')
    "{`"seed`": $Seed, `"oshibka`": `"json: $m`", `"progonov`": $($vse.Count)}" | Out-File -FilePath $Vyhod -Encoding utf8
  }
}
Save-Itog
for ($r = 0; $r -lt $plany.Count; $r++) {
  if ($jobSw.Elapsed.TotalSeconds -gt $BudzhetS) { Write-Host "budzhet ischerpan na progone $r"; break }
  try {
  $etapy = @(); $tE = [Diagnostics.Stopwatch]::StartNew()
  $planPut = $plany[($Seed + $r) % $plany.Count]
  $plan = Get-Content -Raw -Encoding UTF8 $planPut | ConvertFrom-Json
  $imya = $plan.imya
  $s = $Seed * 1000 + $r
  $fajl = $plan.stranica.url_soderzhit.TrimStart('/') -replace '/', '\'
  $stranicaPut = (Join-Path $koren $fajl) -replace '\\', '/'
  $url = "file:///$stranicaPut`?seed=$s"
  Stop-Lishnee
  $prof = Join-Path $tmp "cprof_$s"
  $arg = @('--new-window', "--user-data-dir=$prof", '--no-first-run', '--no-default-browser-check',
           '--force-renderer-accessibility', '--disable-features=Translate', '--start-maximized', $url)
  $null = Start-Process $chrome -ArgumentList $arg -PassThru
  $etapy += "chrome=$($tE.ElapsedMilliseconds)"
  $rnd = New-Object Random($s)
  $oknoPomeha = ($rnd.Next(0, 4) -eq 0)
  $job = $null
  if ($oknoPomeha) {
    $cherez = $rnd.Next(3, 12)
    $job = Start-Job -ScriptBlock { param($c) Start-Sleep -Seconds $c; Start-Process notepad } -ArgumentList $cherez
  }
  # a cold browser start is the harness's business, not the skill's: wait for the page first
  $null = Wait-Stranica $plan.stranica 60000
  $etapy += "storozh_pered=$($tE.ElapsedMilliseconds)"
  try { Set-Storozh } catch { Write-Host "storozh: $($_.Exception.Message)" }
  $out = Join-Path $tmp "skill_$s.json"
  $log = Join-Path $tmp "log_$s.txt"
  $env:RUKI_LOG = $log
  Remove-Item $out, $log -ErrorAction SilentlyContinue
  $zapusk = $null
  $skSw = [Diagnostics.Stopwatch]::StartNew()
  try {
    $soF = Join-Path $tmp "so_$s.txt"; $seF = Join-Path $tmp "se_$s.txt"
    $pr = Start-Process powershell.exe -PassThru -WindowStyle Hidden -RedirectStandardOutput $soF -RedirectStandardError $seF -ArgumentList @(
      '-NoProfile', '-STA', '-ExecutionPolicy', 'Bypass', '-File', "`"$(Join-Path $koren 'skills\zapolnit-formu.ps1')`"", '-Plan', "`"$planPut`"", '-Vyhod', "`"$out`"")
    if (-not $pr.WaitForExit($LimitSkillaS * 1000)) {
      try { $pr.Kill() } catch {}
      $zapusk = "ubit-po-limitu ${LimitSkillaS}s"
    } else { $zapusk = "kod=$($pr.ExitCode) ms=$($skSw.ElapsedMilliseconds)" }
    $vyvod = ((@(Get-Hvost $soF 8) + @(Get-Hvost $seF 8)) -join "`n")
  } catch { $zapusk = $_.Exception.Message }
  $skMs = $skSw.ElapsedMilliseconds
  $skill = if (Test-Path $out) { Get-Content -Raw -Encoding UTF8 $out | ConvertFrom-Json } else { $null }
  $etapy += "skill=$($tE.ElapsedMilliseconds)"
  $bufer = Test-Storozh
  $tProv = [Diagnostics.Stopwatch]::StartNew()

  # independent check through the page's control field
  $prov = [ordered]@{ uspeh = $false; prichina = ''; polya = [ordered]@{}; bufer = $bufer; pomehi_stranicy = @() }
  $o = Wait-Stranica $plan.stranica 5000
  $k = if ($o) { Find-Element $o.Doc 'kontrol' $KONTROL 'tekst' 4000 } else { $null }
  $txt = Get-Znachenie $k
  $d = $null
  try { if ($txt) { $d = $txt | ConvertFrom-Json } } catch {}
  if (-not $d) { $prov.prichina = 'net-kontrolya' }
  else {
    $prov.pomehi_stranicy = @($d.pomehi)
    if ($plan.ozhidaetsya_ostanovka) {
      $pr = if ($skill -and $skill.ostanovka) { $skill.ostanovka.prichina } else { '' }
      $prov.uspeh = ($pr -eq $plan.ozhidaetsya_ostanovka) -and ($d.otpravok -eq 0) -and -not $d.otpravleno
      $prov.prichina = "ostanovka=$pr otpravok=$($d.otpravok)"
    } else {
      $rash = @()
      foreach ($sh in $plan.shagi) {
        if ($sh.tip -eq 'knopka') { continue }
        $cel = ConvertTo-Lf ([string]$sh.znachenie)
        $f = $d.pola.($sh.id)
        $ok = $f -and ([int]$f.dl -eq $cel.Length) -and ([string]$f.h -eq (Get-Fnv $cel))
        if ($ok -and $sh.tip -eq 'avtodop') { $ok = [bool]$f.vybrano }
        $zap = [ordered]@{ ok = [bool]$ok; dl_plan = $cel.Length; dl_fakt = $(if ($f) { $f.dl } else { $null }) }
        if (-not $ok -and $f -and $f.v -ne $null) { $zap.fakt = [string]$f.v; if ($cel.Length -le 300) { $zap.plan = $cel } }
        $prov.polya[$sh.id] = $zap
        if (-not $ok) { $rash += $sh.id }
      }
      if (-not $d.otpravleno) { $rash += 'ne-otpravleno' }
      if ($d.otpravok -gt 0) { $rash += 'lishnyaya-otpravka' }
      $prov.uspeh = ($rash.Count -eq 0)
      $prov.prichina = if ($rash.Count) { 'rashozhdenie: ' + ($rash -join ',') } else { 'ok' }
    }
  }
  $etapy += "proverka=$($tE.ElapsedMilliseconds)"
  if (-not $bufer.ok) { $prov.uspeh = $false; $prov.prichina += ' bufer-ne-vosstanovlen' }
  if ($job) { Stop-Job $job -ErrorAction SilentlyContinue; Remove-Job $job -Force -ErrorAction SilentlyContinue }
  $logTail = @(); if (Test-Path $log) { $logTail += @(Get-Hvost $log 30) }
  $logTail += "ZAPUSK: $zapusk"
  if ($vyvod) { $logTail += @(($vyvod -split "`n") | Select-Object -Last 10) }
  $vse += [ordered]@{
    progon = $r; seed = $s; stranica = $imya; okno_pomeha = $oknoPomeha; skill_ms = $skMs; proverka_ms = [int]$tProv.ElapsedMilliseconds
    skill = $skill; proverka = $prov; log = $logTail
  }
  Write-Host ("[{0}/{1}] {2} seed={3} uspeh={4} {5} {6} ms" -f ($r + 1), $plany.Count, $imya, $s, $prov.uspeh, $prov.prichina, $skMs)
  # annotations are the one channel readable without signing in
  $kr = ($logTail | Where-Object { $_ -match 'STOP|shag |vstavka|ZAPUSK|sverka|mnogo|avtodop|pole ' } | Select-Object -Last 8) -join ' / '
  Write-Host ("::notice title=vvod {0} {1}::uspeh={2} {3} skill={4}ms etapy={5} / {6}" -f $Seed, $imya, $prov.uspeh, $prov.prichina, $skMs, ($etapy -join ','), ($kr -replace '[\r\n]', ' '))
  Stop-Lishnee
  } catch {
    $vse += [ordered]@{ progon = $r; stranica = $(if ($plan) { $plan.imya } else { $planPut }); proverka = [ordered]@{ uspeh = $false; prichina = 'sboj-stenda' };
      log = @("STEND: $($_.Exception.Message)", [string]$_.ScriptStackTrace) }
    Write-Host "STEND: $($_.Exception.Message) $($_.ScriptStackTrace)"
    Stop-Lishnee
  }
  Save-Itog
}
Save-Itog
exit 0
