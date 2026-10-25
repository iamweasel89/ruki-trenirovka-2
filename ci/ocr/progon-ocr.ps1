# One training job of screen reading by recognition: every plan of plans/ocr at every
# browser scale (100 / 125 / 150 %, Chrome device scale factor), layout seeded per run.
# The page reports clicks in its window title as codes: label index, offset from the
# label centre, inside or not. Skill failures never fail the job: they go into the result.
param([int]$Seed = 1, [string]$Vyhod = 'rezultat.json', [string]$Tolko = '', [string]$Masshtaby = '1,1.25,1.5')
$ErrorActionPreference = 'Continue'
$koren = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
. (Join-Path $koren 'lib\ocr.ps1')
[RukiObraz]::DpiAware()
$tmp = if ($env:RUNNER_TEMP) { $env:RUNNER_TEMP } else { [IO.Path]::GetTempPath() }
$chrome = @("$env:ProgramFiles\Google\Chrome\Application\chrome.exe", "${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe") | Where-Object { Test-Path $_ } | Select-Object -First 1
$plany = @(Get-ChildItem (Join-Path $koren 'plans\ocr') -Filter *.json | Sort-Object Name | ForEach-Object { $_.FullName })
if ($Tolko) { $plany = @($plany | Where-Object { $Tolko.Split(',') -contains [IO.Path]::GetFileNameWithoutExtension($_) }) }
$mash = @($Masshtaby.Split(',') | ForEach-Object { [double]::Parse($_, [Globalization.CultureInfo]::InvariantCulture) })
$vse = @()
$jobSw = [Diagnostics.Stopwatch]::StartNew()
$ekr = [RukiObraz]::Ekran()
$sreda = [ordered]@{ ekran = "$($ekr[2])x$($ekr[3])"; dpi = [RukiObraz]::Dpi; chrome = [bool]$chrome }
$podg = Join-Path $koren 'podgotovka.json'
if (Test-Path $podg) { try { $sreda.podgotovka = Get-Content -Raw -Encoding UTF8 $podg | ConvertFrom-Json } catch {} }

function Stop-Lishnee {
  Get-Process chrome -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
  Start-Sleep -Milliseconds 400
}
function Save-Itog {
  $itog = [ordered]@{ seed = $Seed; sekund = [int]$jobSw.Elapsed.TotalSeconds; sreda = $sreda; progony = $vse }
  try { ($itog | ConvertTo-Json -Depth 9) | Out-File -FilePath $Vyhod -Encoding utf8 }
  catch { "{`"seed`": $Seed, `"oshibka`": `"json`"}" | Out-File -FilePath $Vyhod -Encoding utf8 }
}
function Read-Kliki([string]$z) {
  $m = [regex]::Match($z, 'ocr r(\d) n(\d+) k([^ ]*)')
  if (-not $m.Success) { return $null }
  $k = @()
  foreach ($c in ($m.Groups[3].Value -split ';')) {
    if (-not $c) { continue }
    $p = $c -split ','
    if ($p.Count -ge 4) { $k += [ordered]@{ i = [int]$p[0]; dx = [int]$p[1]; dy = [int]$p[2]; v = [int]$p[3] } }
  }
  return [ordered]@{ gotovo = ($m.Groups[1].Value -eq '1'); n = [int]$m.Groups[2].Value; kliki = $k }
}
function Find-OknoStranicy([int]$TimeoutMs) {
  $sw = [Diagnostics.Stopwatch]::StartNew()
  do {
    $h = [RukiObraz]::NajtiOkno('ocr r1')
    if ($h -ne [IntPtr]::Zero) { return $h }
    Start-Sleep -Milliseconds 200
  } while ($sw.ElapsedMilliseconds -lt $TimeoutMs)
  return [IntPtr]::Zero
}

Save-Itog
$r = 0
$vsegoProgonov = $plany.Count * $mash.Count
foreach ($m in $mash) {
  for ($j = 0; $j -lt $plany.Count; $j++) {
    $plan = $null
    try {
      $planPut = $plany[($Seed + $j) % $plany.Count]
      $plan = Get-Content -Raw -Encoding UTF8 $planPut | ConvertFrom-Json
      $s = $Seed * 1000 + $r
      $metki = @($plan.metki | ForEach-Object { [string]$_ })
      $celI = [array]::IndexOf($metki, [string]$plan.cel)
      $q = 'st=' + $plan.st + '&seed=' + $s + '&m=' + [uri]::EscapeDataString((ConvertTo-Json -InputObject $metki -Compress))
      if ($null -ne $plan.dv) { $q += "&dv=$($plan.dv)" }
      if ($null -ne $plan.mg) { $q += "&mg=$($plan.mg)" }
      $stranica = ((Join-Path $koren 'polygon\ocr\ekran.html') -replace '\\', '/')
      $url = "file:///$stranica`?$q"
      Stop-Lishnee
      $mt = $m.ToString([Globalization.CultureInfo]::InvariantCulture)
      $prof = Join-Path $tmp ("cprof_ocr_" + ($mt -replace '\.', '_'))
      $arg = @("--app=$url", "--user-data-dir=$prof", '--no-first-run', '--no-default-browser-check', '--disable-features=Translate',
               '--disable-session-crashed-bubble', '--start-maximized', "--force-device-scale-factor=$mt")
      $null = Start-Process $chrome -ArgumentList $arg -PassThru
      $okno = Find-OknoStranicy 25000
      $prov = [ordered]@{ uspeh = $false; prichina = ''; est_cel = ($celI -ge 0); kliki = @() }
      $skill = $null; $skMs = 0; $logTail = @()
      if ($okno -eq [IntPtr]::Zero) { $prov.prichina = 'stranica-ne-otkrylas' }
      else {
        Start-Sleep -Milliseconds 300
        [RukiObraz]::Kursor($ekr[0] + $ekr[2] - 2, $ekr[1] + $ekr[3] - 2)
        $out = Join-Path $tmp "skill_$s.json"
        $log = Join-Path $tmp "log_$s.txt"
        $env:RUKI_LOG = $log
        Remove-Item $out, $log -ErrorAction SilentlyContinue
        $skSw = [Diagnostics.Stopwatch]::StartNew()
        $vyvod = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $koren 'skills\klik-po-tekstu.ps1') -Plan $planPut -Vyhod $out 2>&1 | Out-String
        $skMs = $skSw.ElapsedMilliseconds
        $skill = if (Test-Path $out) { Get-Content -Raw -Encoding UTF8 $out | ConvertFrom-Json } else { $null }
        Start-Sleep -Milliseconds 300
        $z = Read-Kliki ([RukiObraz]::Zagolovok($okno))
        if (-not $z) { $z = Read-Kliki ([RukiObraz]::Zagolovok([RukiObraz]::NajtiOkno('ocr r'))) }
        $st = if ($skill) { [string]$skill.status } else { 'net-rezultata' }
        if (-not $z) { $prov.prichina = 'net-zagolovka' }
        else {
          $prov.kliki = @($z.kliki)
          $chuzhie = @($z.kliki | Where-Object { $_.i -ne $celI -or $_.v -ne 1 })
          $prov.lozhnyh = $chuzhie.Count
          if ($celI -ge 0) {
            $prov.uspeh = ($st -eq 'klik') -and ($z.n -eq 1) -and ($chuzhie.Count -eq 0)
            $prov.prichina = if ($prov.uspeh) { 'ok' } elseif ($z.n -eq 0) { "ne-kliknul: $st" } elseif ($chuzhie.Count) { "lozhnyj-klik: $st" } else { "kliknul-$($z.n)-raz" }
          } else {
            $prov.uspeh = ($z.n -eq 0) -and ($st -ne 'klik')
            $prov.prichina = if ($prov.uspeh) { "chestno: $st" } else { "lozhnyj-klik: $st" }
          }
        }
        if (Test-Path $log) { $logTail += @(Get-Content $log -Encoding UTF8 | Select-Object -Last 25) }
        if ($vyvod) { $logTail += @(($vyvod -split "`n") | Where-Object { $_.Trim() } | Select-Object -Last 8) }
      }
      $vse += [ordered]@{ progon = $r; seed = $s; plan = $plan.imya; st = $plan.st; masshtab = $m; cel = [string]$plan.cel; skill_ms = $skMs
                          skill = $skill; proverka = $prov; log = $logTail }
      Write-Host ("[{0}/{1}] {2} x{3} seed={4} uspeh={5} {6} {7} ms" -f ($r + 1), $vsegoProgonov, $plan.imya, $mt, $s, $prov.uspeh, $prov.prichina, $skMs)
    } catch {
      $vse += [ordered]@{ progon = $r; plan = $(if ($plan) { $plan.imya } else { '' }); masshtab = $m; proverka = [ordered]@{ uspeh = $false; prichina = 'sboj-stenda' }
                          log = @("STEND: $($_.Exception.Message)", [string]$_.ScriptStackTrace) }
      Write-Host "STEND: $($_.Exception.Message) $($_.ScriptStackTrace)"
    }
    $r++
    Save-Itog
  }
}
Stop-Lishnee
Save-Itog
exit 0
