# One job of the search trainer: tasks from polygon\poisk\zadachi.json, timed movements, independent check.
param([int]$Seed = 1, [int]$Krugov = 1, [string]$Filtr = '', [string]$Vyhod = 'poisk-rezultat.json')
$ErrorActionPreference = 'Continue'
Add-Type -AssemblyName System.Windows.Forms
$koren = Split-Path -Parent $PSScriptRoot
. (Join-Path $koren 'lib\uia.ps1')
. (Join-Path $koren 'lib\okno.ps1')
. (Join-Path $koren 'lib\poisk.ps1')
$tmp = if ($env:RUNNER_TEMP) { $env:RUNNER_TEMP } else { [IO.Path]::GetTempPath() }
$chrome = @("$env:ProgramFiles\Google\Chrome\Application\chrome.exe", "${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe") | Where-Object { Test-Path $_ } | Select-Object -First 1
$baza = [regex]::Unescape('\u041f\u043e\u043b\u0438\u0433\u043e\u043d \u041f')
$vse = Get-Content -Raw -Encoding UTF8 (Join-Path $koren 'polygon\poisk\zadachi.json') | ConvertFrom-Json
$spisok = @($vse.zadachi)
if ($Filtr) { $f = $Filtr.Split(','); $spisok = @($spisok | Where-Object { $f -contains $_.imya }) }
$rnd = New-Object Random($Seed)
$jobSw = [Diagnostics.Stopwatch]::StartNew()
$progony = @()

function Stop-Lishnee {
  Get-Process chrome, notepad -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
  $t = [Diagnostics.Stopwatch]::StartNew()
  while ((Get-Process chrome -ErrorAction SilentlyContinue) -and $t.ElapsedMilliseconds -lt 4000) { Start-Sleep -Milliseconds 100 }
}

function Get-OknaChrome {
  @(Find-VseKesh $AE::RootElement (New-PropCond $AE::ClassNameProperty 'Chrome_WidgetWin_1') $TS::Children | Where-Object { $_.Cached.Name })
}

# titles of all windows and tabs (the page writes the clicked key into its title)
function Get-Zagolovki {
  $z = @()
  $tc = New-PropCond $AE::ControlTypeProperty $CT::TabItem
  foreach ($w in (Get-OknaChrome)) {
    $z += $w.Cached.Name
    foreach ($t in (Find-VseKesh $w $tc)) { $z += $t.Cached.Name }
  }
  $z
}

function Get-Nazhatiya {
  $kl = @{}; $maxKlikov = 0
  foreach ($s in (Get-Zagolovki)) {
    if ($s -match 'nazhato: (\S+)') { $kl[$Matches[1]] = 1 }
    if ($s -match 'klikov: (\d+)') { $maxKlikov = [Math]::Max($maxKlikov, [int]$Matches[1]) }
  }
  @{ Klyuchi = @($kl.Keys); Klikov = $(if ($kl.Count) { [Math]::Max(1, $maxKlikov) } else { 0 }) }
}

# wait until every page of the scenario is open (not timed as part of the movement)
function Wait-Gotovo([int]$skolko, [string]$rezhim) {
  $t = [Diagnostics.Stopwatch]::StartNew()
  while ($t.ElapsedMilliseconds -lt 20000) {
    $z = @(Get-Zagolovki | Where-Object { $_ -like "$baza*" } | Select-Object -Unique)
    $okon = @(Get-OknaChrome | Where-Object { $_.Cached.Name -like "$baza*" }).Count
    $nado = if ($rezhim -eq 'okna') { $okon -ge $skolko } else { $z.Count -ge $skolko -and $okon -ge 1 }
    if ($nado) { Start-Sleep -Milliseconds 300; return $true }
    Start-Sleep -Milliseconds 150
  }
  return $false
}

# warm-up: the first UIA calls in a process load assemblies and are slow
$null = Get-OknaChrome

$nomer = 0
for ($krug = 0; $krug -lt $Krugov; $krug++) {
  foreach ($zd in $spisok) {
    $nomer++
    $s = $Seed * 1000 + $nomer
    $r = $rnd.Next(1, 21); $i = $rnd.Next(1, 9); $n = $rnd.Next(1, 4)
    $js = ($zd | ConvertTo-Json -Depth 6 -Compress) -replace '\{r\}', $r -replace '\{i\}', $i -replace '\{n\}', $n
    $z = $js | ConvertFrom-Json
    $rezhim = if ($z.rezhim) { $z.rezhim } else { 'odna' }
    # window disturbance before the movement
    $pomeha = @('net', 'svernut', 'bloknot', 'sdvig', 'net')[$rnd.Next(0, 5)]
    Stop-Lishnee
    $prof = Join-Path $tmp "pprof_$Seed"
    $obshchie = @("--user-data-dir=$prof", '--no-first-run', '--no-default-browser-check', '--force-renderer-accessibility',
                  '--disable-features=Translate', '--hide-crash-restore-bubble', '--disable-session-crashed-bubble', '--start-maximized')
    $urls = @($z.stranicy | ForEach-Object {
      $p = ((Join-Path $koren "polygon\poisk") -replace '\\', '/') + '/' + $_
      $sep = if ($_.Contains('?')) { '&' } else { '?' }
      "file:///$p${sep}seed=$s"
    })
    if ($rezhim -eq 'okna') {
      $k = 0
      foreach ($u in $urls) {
        $k++
        $null = Start-Process $chrome -ArgumentList ($obshchie + @('--new-window', $u)) -PassThru
        $null = Wait-Gotovo $k 'okna'
      }
    } else {
      $null = Start-Process $chrome -ArgumentList ($obshchie + $urls) -PassThru
    }
    $gotovo = Wait-Gotovo $urls.Count $rezhim
    $hFront = Get-PerednijRoot
    $bloknot = $null
    switch ($pomeha) {
      'svernut' { $null = [RukiOkno]::ShowWindow($hFront, 6) }
      'bloknot' { $bloknot = Start-Process notepad -PassThru; $t = [Diagnostics.Stopwatch]::StartNew(); while ((Get-PerednijRoot) -eq $hFront -and $t.ElapsedMilliseconds -lt 4000) { Start-Sleep -Milliseconds 50 } }
      'sdvig' { $null = [RukiOkno]::ShowWindow($hFront, 1); Start-Sleep -Milliseconds 200; $sx = [System.Windows.Forms.SystemInformation]::PrimaryMonitorSize.Width
                $null = [RukiMysh]::SetWindowPos($hFront, [IntPtr]::Zero, [int]($sx * 0.7), 40, [int]($sx * 0.9), 600, 0x0044) }
    }
    $log = Join-Path $tmp "plog_$s.txt"; $env:RUKI_LOG = $log; Remove-Item $log -ErrorAction SilentlyContinue
    $dv = $null; $oshibka = $null
    try { $dv = Invoke-Dvizhenie $z } catch { $oshibka = $_.Exception.Message }
    # independent check: what did the pages register
    $ozhid = $z.ozhid
    $pozitiv = $ozhid -is [array] -or $ozhid -is [object[]]
    $t = [Diagnostics.Stopwatch]::StartNew(); $nz = Get-Nazhatiya
    while ($pozitiv -and $nz.Klikov -eq 0 -and $t.ElapsedMilliseconds -lt 2000) { Start-Sleep -Milliseconds 100; $nz = Get-Nazhatiya }
    if (-not $pozitiv) { Start-Sleep -Milliseconds 300; $nz = Get-Nazhatiya }
    $status = if ($dv) { $dv.Status } else { 'isklyuchenie' }
    if ($pozitiv) {
      $verno = ($status -eq 'ok') -and $nz.Klikov -eq 1 -and $nz.Klyuchi.Count -eq 1 -and (@($ozhid) -contains $nz.Klyuchi[0])
    } else {
      $verno = ($status -eq $ozhid) -and $nz.Klikov -eq 0
    }
    # tree dump of the first wrong positive run of the job, for diagnosis
    $damp = $null
    if ($pozitiv -and -not $verno -and -not $script:bylDamp) {
      $script:bylDamp = $true
      $o2 = Select-OknoBrauzera $z.okno 2000
      if ($o2) { $damp = @(Get-DampDereva $o2.Doc 0 12) | Select-Object -First 150 }
    }
    $logTail = @(); if (Test-Path $log) { $logTail = @(Get-Content $log -Encoding UTF8 | Select-Object -Last 12) }
    $progony += [ordered]@{
      nomer = $nomer; zadacha = $z.imya; seed = $s; pomeha = $pomeha; gotovo = $gotovo
      ozhid = $ozhid; status = $status; nazhato = $nz.Klyuchi; klikov = $nz.Klikov; verno = [bool]$verno; pozitiv = [bool]$pozitiv
      ms = $(if ($dv) { $dv.Ms } else { $null }); ozhidanie = $(if ($dv) { $dv.Ozhidanie } else { $null }); etapy = $(if ($dv) { $dv.Etapy } else { $null })
      strategiya = $(if ($dv) { $dv.Strategiya } else { $null }); kandidatov = $(if ($dv) { $dv.Kandidatov } else { $null })
      okno = $(if ($dv) { @($dv.Okno) } else { @() }); prokrutka = $(if ($dv) { $dv.Prokrutka } else { $null })
      oshibka = $oshibka; log = $logTail; damp = $damp
    }
    Write-Host ("[{0}] {1} pomeha={2} status={3} nazhato={4} verno={5} ms={6}" -f $nomer, $z.imya, $pomeha, $status, ($nz.Klyuchi -join ','), $verno, $(if ($dv) { $dv.Ms }))
    if ($bloknot) { $bloknot | Stop-Process -Force -ErrorAction SilentlyContinue }
  }
}
Stop-Lishnee
$itog = [ordered]@{ seed = $Seed; sekund = [int]$jobSw.Elapsed.TotalSeconds; progony = $progony }
($itog | ConvertTo-Json -Depth 8) | Out-File -FilePath $Vyhod -Encoding utf8
exit 0
