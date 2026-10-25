# Input fidelity: the text in the field must equal the plan exactly, or the movement
# stops with a reason. Strategies: typing for short single-line text, paste through the
# clipboard (saved and restored) for long or multi-line text, typing fallback when paste
# is blocked. Honest stops: perenos-v-odnostrochnom, limit-dliny, perenos-ne-podtverzhdyon,
# net-podskazki. Needs uia.ps1, okno.ps1, vvod.ps1, bufer.ps1.

function ConvertTo-Lf([string]$s) { return ($s -replace "`r`n", "`n") -replace "`r", "`n" }

# canonical number string for a locale: ru "1 234,50" / en "1,234.50" / de "1.234,50" -> "1234.5"
function ConvertTo-KanonChislo([string]$s, [string]$lokal) {
  if ($null -eq $s) { return $null }
  $t = $s -replace '[\s\u00A0\u202F\u2009\u2007'']', ''
  $t = $t -replace '[\u2212\u2012\u2013]', '-'
  switch -regex ($lokal) {
    '^en' { $t = $t -replace ',', '' }
    '^(de|id)' { $t = ($t -replace '\.', '') -replace ',', '.' }
    default { $t = $t -replace ',', '.' }
  }
  $d = 0
  if (-not [decimal]::TryParse($t, [Globalization.NumberStyles]::Number, [Globalization.CultureInfo]::InvariantCulture, [ref]$d)) { return $null }
  return $d.ToString('0.############', [Globalization.CultureInfo]::InvariantCulture)
}

function Get-Cel($shag) { return ConvertTo-Lf ([string]$shag.znachenie) }

# is the read-back equal to the plan: line endings always normalised; numbers with a locale
# are compared by value (group separators and NBSP do not matter)
function Test-Ravno($fakt, [string]$cel, $shag) {
  if ($null -eq $fakt) { return $false }
  $f = ConvertTo-Lf ([string]$fakt)
  if ($f -ceq $cel) { return $true }
  if ($shag -and $shag.lokal) {
    $a = ConvertTo-KanonChislo $f $shag.lokal; $b = ConvertTo-KanonChislo $cel $shag.lokal
    return ($null -ne $a) -and ($a -ceq $b)
  }
  return $false
}

function Wait-Ravno($el, [string]$cel, $shag, [int]$TimeoutMs = 1500) {
  $sw = [Diagnostics.Stopwatch]::StartNew()
  $v = Get-Znachenie $el
  while (-not (Test-Ravno $v $cel $shag) -and $sw.ElapsedMilliseconds -lt $TimeoutMs) {
    Start-Sleep -Milliseconds 60
    $v = Get-Znachenie $el
  }
  return $v
}

# AriaProperties (UIA id 30102) is not in the managed client on every machine
$script:AriaProp = $null
try { $script:AriaProp = [System.Windows.Automation.AutomationProperty]::LookupById(30102) } catch {}
function Get-Aria($el) {
  if (-not $script:AriaProp) { return '' }
  try { return [string]$el.GetCurrentPropertyValue($script:AriaProp) } catch { return '' }
}

# multi-line is confirmed by the accessibility tree (Chrome: AriaProperties multiline=true),
# by an earlier paste that kept the line breaks, or by height: at least 2.2 single-line edits
function Test-Mnogostrochnoe($ctx, $el, $shag) {
  if ($ctx.Mnogo -and $ctx.Mnogo[[string]$shag.id]) { return $true }
  if ((Get-Aria $el) -match 'multiline=true') { return $true }
  try {
    $h = $el.Current.BoundingRectangle.Height
    $min = [double]::MaxValue
    foreach ($e in $ctx.Doc.FindAll($TS::Descendants, (New-PropCond $AE::ControlTypeProperty $CT::Edit))) {
      $eh = $e.Current.BoundingRectangle.Height
      if ($eh -gt 4 -and $eh -lt $min) { $min = $eh }
    }
    Write-RukiLog "mnogostrochnost $($shag.id): vysota $h, min $min"
    if ($min -lt [double]::MaxValue -and $h -ge 2.2 * $min) { return $true }
  } catch {}
  return $false
}

function Write-Opisanie($ctx, $el, $shag) {
  if (-not $ctx.Opisano) { $ctx.Opisano = @{} }
  if ($ctx.Opisano[[string]$shag.id]) { return }
  $ctx.Opisano[[string]$shag.id] = $true
  try {
    $ap = Get-Aria $el
    Write-RukiLog ("pole {0}: tip={1} aria=[{2}] dlina_plana={3}" -f $shag.id, $el.Current.ControlType.ProgrammaticName, $ap, ([string]$shag.znachenie).Length)
  } catch {}
}

# split into chunks that never cut a surrogate pair
function Get-Kusok([string]$s, [int]$n) {
  if ($s.Length -le $n) { return $s }
  if ([char]::IsHighSurrogate($s[$n - 1])) { $n++ }
  return $s.Substring(0, $n)
}

function Clear-Pole($el) {
  Send-Klavisha 'CtrlA'; Send-Klavisha 'Delete'
  return ((Wait-Znachenie $el '' 800) -ceq '')
}

# what a single-line field makes of a multi-line paste
function Test-PerenosSrezan([string]$v, [string]$cel) {
  if ($cel -notmatch "`n") { return $false }
  foreach ($zam in @('', ' ', "`t")) { if ($v -ceq ($cel -replace "`n", $zam)) { return $true } }
  return ($v -cne '' -and $v -notmatch "`n" -and $cel.StartsWith($v))
}

# a stuck prefix: one more character does not get in -> a length limit
function Test-Upor($ctx, $el, [string]$v, [string]$cel) {
  if ($v.Length -ge $cel.Length -or -not $cel.StartsWith($v) -or $v.Length -eq 0) { return $false }
  if ((Confirm-Gotovnost $ctx $el) -ne 'ok') { return $false }
  Send-Klavisha 'CtrlEnd'
  $sled = Get-Kusok $cel.Substring($v.Length) 1
  Send-Tekst $sled
  Start-Sleep -Milliseconds 450
  $v2 = ConvertTo-Lf ([string](Get-ZnachenieUstojchivo $el))
  return ($v2 -ceq $v)
}

function New-Stop([string]$p, [int]$pop, [string]$podr = '') { return @{ Status = 'stop'; Prichina = $p; Popytki = $pop; Podrobno = $podr } }

# paste the whole value. returns @{ Status = ok|stop|zapret|sboj }
function Invoke-Vstavka($ctx, $el, $shag, [string]$cel, [int]$pop) {
  $snimok = Save-Bufer
  $nomer = 0
  $v = $null
  try {
    $nomer = Set-BuferTekst $cel
    if ((Confirm-Gotovnost $ctx $el) -ne 'ok') { return @{ Status = 'sboj' } }
    Send-Klavisha 'CtrlV'
    $v = Wait-Ravno $el $cel $shag 2500
  } finally {
    $r = Restore-Bufer $snimok $nomer
    if ($r -eq 'chuzhoe') { Add-Pomeha $ctx 'bufer-izmenyon-izvne' }
  }
  $v = ConvertTo-Lf ([string]$v)
  if (Test-Ravno $v $cel $shag) { if ($cel -match "`n") { $ctx.Mnogo[[string]$shag.id] = $true }; return @{ Status = 'ok' } }
  Write-RukiLog "vstavka $($shag.id): zhdali $($cel.Length), vidim $($v.Length)"
  if ($v -ceq '' -and (Test-TotZhe (Get-Fokus) $el) -and -not (Find-Dialog $ctx.Doc)) {
    $k = [string]$shag.id
    $ctx.PustoPosleVstavki[$k] = 1 + [int]$ctx.PustoPosleVstavki[$k]
    if ($ctx.PustoPosleVstavki[$k] -ge 2) { Write-RukiLog "vstavka $k zapreshchena, nabirayu"; return @{ Status = 'zapret' } }
    return @{ Status = 'sboj' }
  }
  if (Test-PerenosSrezan $v $cel) {
    $null = Clear-Pole $el
    return New-Stop 'perenos-v-odnostrochnom' $pop "pole prinyalo $($v.Length) iz $($cel.Length) bez perenosov"
  }
  if ($v.Length -lt $cel.Length -and $v.Length -gt 0 -and $cel.StartsWith($v)) {
    Start-Sleep -Milliseconds 300
    $v2 = ConvertTo-Lf ([string](Get-ZnachenieUstojchivo $el))
    if ($v2 -ceq $v) { $null = Clear-Pole $el; return New-Stop 'limit-dliny' $pop "vlezlo $($v.Length) iz $($cel.Length)" }
  }
  return @{ Status = 'sboj' }
}

# type the rest of the value with focus checks and chunk read-back.
# returns @{ Status = ok|stop|sboj }
function Invoke-Nabor($ctx, $el, $shag, [string]$cel, [int]$pop, [int]$kusok) {
  $chislo = [bool]$shag.lokal
  $tek = ConvertTo-Lf ([string](Get-ZnachenieUstojchivo $el))
  if ((-not $chislo) -and $tek -and $cel.StartsWith($tek)) {
    $ost = $cel.Substring($tek.Length)
    Send-Klavisha 'CtrlEnd'
  } else {
    if (-not (Clear-Pole $el)) { return @{ Status = 'sboj' } }
    $ost = $cel
  }
  if ($ost -match "`n" -and -not (Test-Mnogostrochnoe $ctx $el $shag)) {
    # Enter in a single-line field may submit the form: never press it
    return New-Stop 'perenos-ne-podtverzhdyon' $pop 'pole ne podtverzhdeno kak mnogostrochnoe'
  }
  $nabrano = $cel.Substring(0, $cel.Length - $ost.Length)
  $dlinnyj = $cel.Length -gt 200
  $k = if ($ctx.EstParol) { 1 } elseif ($chislo) { 1 } elseif ($dlinnyj) { 48 } else { $kusok }
  $sverok = 0
  while ($ost.Length -gt 0) {
    if (-not (Test-Zhivoj $el)) { return @{ Status = 'sboj' } }
    $f = Get-Fokus
    if (-not (Test-TotZhe $f $el)) {
      if (Test-Parol $f) { Add-Pomeha $ctx 'fokus-v-parol' }
      if ((Confirm-Gotovnost $ctx $el) -ne 'ok') { return @{ Status = 'sboj' } }
    }
    if (-not $ctx.EstParol -and (Find-Dialog $ctx.Doc)) { $null = Close-Dialog $ctx; return @{ Status = 'sboj' } }
    $ch = Get-Kusok $ost $k
    if ($dlinnyj) { $null = [RukiKlav]::Stroka($ch); Start-Sleep -Milliseconds 25 } else { Send-Tekst $ch }
    $nabrano += $ch; $ost = $ost.Substring($ch.Length)
    if ($chislo) { continue }  # the field reformats while typing: only the final value counts
    if ($k -gt 1 -or $ost.Length -eq 0 -or (++$sverok % 8) -eq 0) {
      $v = ConvertTo-Lf ([string](Wait-Znachenie $el $nabrano 900))
      if ($v -cne $nabrano) {
        Write-RukiLog "sverka kuska $($shag.id): zhdali $($nabrano.Length), vidim $($v.Length)"
        if (Test-Upor $ctx $el $v $cel) { $null = Clear-Pole $el; return New-Stop 'limit-dliny' $pop "vlezlo $($v.Length) iz $($cel.Length)" }
        return @{ Status = 'sboj' }
      }
    }
  }
  $v = Wait-Ravno $el $cel $shag 1500
  if (Test-Ravno $v $cel $shag) { return @{ Status = 'ok' } }
  return @{ Status = 'sboj' }
}

# type a value into a text-like field. returns @{ Status = ok|stop; Prichina; Popytki }
function Set-Tekst($ctx, $shag, [int]$kusok = 8) {
  foreach ($k in 'Mnogo', 'PustoPosleVstavki', 'ZapretVstavki') { if (-not $ctx[$k]) { $ctx[$k] = @{} } }
  $cel = Get-Cel $shag
  $id = [string]$shag.id
  # paste for long or multi-line text, tabs, or when the plan asks for it
  $hochuVstavku = (-not $shag.lokal) -and ($shag.sposob -eq 'vstavka' -or ($shag.sposob -ne 'nabor' -and ($cel.Length -gt 120 -or $cel -match "[`n`t]")))
  for ($pop = 1; $pop -le 6; $pop++) {
    $el = Find-Element $ctx.Doc $shag.id $shag.metka $shag.tip 6000
    if (-not $el) { return New-Stop 'net-elementa' $pop }
    if (Test-Parol $el) { return New-Stop 'pole-parolya' $pop }
    Write-Opisanie $ctx $el $shag
    if ((Confirm-Gotovnost $ctx $el) -ne 'ok') { continue }
    $tek = Get-ZnachenieUstojchivo $el
    if (Test-Ravno $tek $cel $shag) { return @{ Status = 'ok'; Popytki = $pop } }
    if ($hochuVstavku -and -not $ctx.ZapretVstavki[$id]) {
      if (-not (Clear-Pole $el)) { continue }
      $r = Invoke-Vstavka $ctx $el $shag $cel $pop
      if ($r.Status -eq 'zapret') { $ctx.ZapretVstavki[$id] = $true; Add-Pomeha $ctx 'vstavka-zapreshchena' }
      elseif ($r.Status -ne 'sboj') { $r.Popytki = $pop; return $r }
      if (-not $ctx.ZapretVstavki[$id]) { continue }
      $el = Find-Element $ctx.Doc $shag.id $shag.metka $shag.tip 3000
      if (-not $el -or (Confirm-Gotovnost $ctx $el) -ne 'ok') { continue }
    }
    $r = Invoke-Nabor $ctx $el $shag $cel $pop $kusok
    if ($r.Status -ne 'sboj') { $r.Popytki = $pop; return $r }
  }
  return New-Stop 'ne-sovpalo-posle-popytok' 6
}

# option of an open suggestion list with the exact name
function Find-Podskazka($doc, [string]$imya, [int]$TimeoutMs) {
  $c = New-AndCond @((New-PropCond $AE::ControlTypeProperty $CT::ListItem), (New-PropCond $AE::NameProperty $imya))
  $sw = [Diagnostics.Stopwatch]::StartNew()
  do {
    try { $o = $doc.FindFirst($TS::Descendants, $c); if ($o -and -not $o.Current.IsOffscreen) { return $o } } catch {}
    Start-Sleep -Milliseconds 120
  } while ($sw.ElapsedMilliseconds -lt $TimeoutMs)
  return $null
}

function Get-Podskazki($doc) {
  try {
    $all = $doc.FindAll($TS::Descendants, (New-PropCond $AE::ControlTypeProperty $CT::ListItem))
    return @($all | Where-Object { -not $_.Current.IsOffscreen } | ForEach-Object { $_.Current.Name })
  } catch { return @() }
}

# autocomplete: type the beginning ($shag.vvod), pick the suggestion equal to $shag.znachenie
function Set-Avtodop($ctx, $shag) {
  $cel = Get-Cel $shag
  $vvod = if ($shag.vvod) { ConvertTo-Lf ([string]$shag.vvod) } else { $cel.Substring(0, [Math]::Min(3, $cel.Length)) }
  if (-not $ctx.Vybrano) { $ctx.Vybrano = @{} }
  $id = [string]$shag.id
  for ($pop = 1; $pop -le 5; $pop++) {
    $el = Find-Element $ctx.Doc $shag.id $shag.metka 'avtodop' 6000
    if (-not $el) { return New-Stop 'net-elementa' $pop }
    if (Test-Parol $el) { return New-Stop 'pole-parolya' $pop }
    Write-Opisanie $ctx $el $shag
    if ((Confirm-Gotovnost $ctx $el) -ne 'ok') { continue }
    $tek = ConvertTo-Lf ([string](Get-ZnachenieUstojchivo $el))
    if ($tek -ceq $cel -and $ctx.Vybrano[$id] -and -not (Find-Podskazka $ctx.Doc $cel 0)) { return @{ Status = 'ok'; Popytki = $pop } }
    $ctx.Vybrano[$id] = $false
    if (-not (Clear-Pole $el)) { continue }
    $r = Invoke-Nabor $ctx $el ([pscustomobject]@{ id = $shag.id; znachenie = $vvod }) $vvod $pop 8
    if ($r.Status -eq 'stop') { $r.Popytki = $pop; return $r }
    if ($r.Status -ne 'ok') { continue }
    $o = Find-Podskazka $ctx.Doc $cel 3500
    if (-not $o) {
      $est = Get-Podskazki $ctx.Doc
      Write-RukiLog "avtodop ${id}: net '$cel', est $($est.Count): $(($est | Select-Object -First 6) -join ' | ')"
      if ($est.Count -gt 0 -and $pop -ge 2) { $null = Clear-Pole $el; return New-Stop 'net-podskazki' $pop "podskazok $($est.Count), nuzhnoj net" }
      continue
    }
    if (Find-Dialog $ctx.Doc) { $null = Close-Dialog $ctx; continue }
    # 1) the accessibility default action on the option
    $sposob = 'select'
    try { $o.GetCurrentPattern([System.Windows.Automation.SelectionItemPattern]::Pattern).Select() }
    catch { try { $o.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke(); $sposob = 'invoke' } catch { $sposob = 'net' } }
    $v = ConvertTo-Lf ([string](Wait-Znachenie $el $cel 1200))
    if ($v -cne $cel -or (Find-Podskazka $ctx.Doc $cel 0)) {
      # 2) keyboard: arrows to the option, Enter only while the list is open and our option is highlighted
      $sposob = 'klaviatura'
      if ((Confirm-Gotovnost $ctx $el) -ne 'ok') { continue }
      for ($i = 0; $i -lt 12; $i++) {
        $o = Find-Podskazka $ctx.Doc $cel 400
        if (-not $o) { break }
        $vyd = $false
        try { $vyd = $o.GetCurrentPattern([System.Windows.Automation.SelectionItemPattern]::Pattern).Current.IsSelected } catch {}
        if ($vyd) { Send-Klavisha 'Enter'; break }
        Send-Klavisha 'Down'; Start-Sleep -Milliseconds 120
      }
      $v = ConvertTo-Lf ([string](Wait-Znachenie $el $cel 1200))
    }
    if ($v -ceq $cel -and -not (Find-Podskazka $ctx.Doc $cel 0)) {
      Write-RukiLog "avtodop $id vybrano ($sposob)"
      $ctx.Vybrano[$id] = $true
      return @{ Status = 'ok'; Popytki = $pop }
    }
    Write-RukiLog "avtodop $id ne vybrano ($sposob), vidim '$v'"
  }
  return New-Stop 'podskazka-ne-vybrana' 5
}
