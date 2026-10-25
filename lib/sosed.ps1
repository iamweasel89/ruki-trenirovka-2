# "The field named by its neighbour label": resolve a visible label text to the editable
# control it names, for pages where the field itself has no accessible name (contenteditable
# divs, inputs without label-for / aria-labelledby) or has only a placeholder.
#
# Resolve-PoleUMetki $doc 'Your Name' -> @{ Status = ok|stop; Prichina; Uzel; Vybor; Kandidaty }
#
# One snapshot of the document subtree (a single cached UIA request), then, for every label
# candidate (a text whose normalised name equals the wanted one), a cascade:
#   1. imya / podskazka: an editable whose own Name or HelpText is the label (label-for,
#      aria-label, aria-labelledby, placeholder) - checked once for the whole page;
#   2. labeledby: an editable whose UIA LabeledBy is this label;
#   3. derevo: the first editable after the label in tree order inside the same container
#      (the label's parent, climbing up to 4 levels while the container holds no editable
#      after the label); refused when another label-like text stands between them, or when the
#      field is neither below nor to the right of the label;
#   4. geometriya: the nearest editable below (horizontally overlapping or left edges within
#      120 px) or to the right (vertically overlapping) within 120 px, with no other label-like
#      text between them; two candidates within 6 px of each other = ambiguous.
# Candidates are then checked for reachability: a field of 2 px or less, or one that is still
# off screen after ScrollIntoView, is a hidden copy and is dropped. When more than one
# reachable field remains, a hit test at each field drops the covered ones; if more than one
# is still left the answer is an honest stop "neodnoznachno" (never a guess).
# Honest stops: net-metki, net-polya, pole-nedostupno, neodnoznachno.
# Windows PowerShell 5.1, ASCII only. Needs uia.ps1 and mysh.ps1.

$script:VP = [System.Windows.Automation.ValuePattern]
$script:SosedRadius = 120

function Get-NormMetka([string]$s) {
  if ($null -eq $s) { return '' }
  $t = $s -replace '[\u00A0\u2007\u2009\u202F]', ' '
  $t = ($t -replace '\s+', ' ').Trim()
  $t = $t -replace '[\s:*\uFF1A]+$', ''
  return $t.Trim().ToLowerInvariant()
}

function ConvertTo-Ramka($r) {
  $nol = [pscustomobject]@{ X = 0.0; Y = 0.0; W = 0.0; H = 0.0; Pusto = $true }
  try {
    if ($null -eq $r -or $r.IsEmpty) { return $nol }
    if ([double]::IsInfinity($r.X) -or [double]::IsNaN($r.X) -or [double]::IsInfinity($r.Width) -or [double]::IsNaN($r.Width)) { return $nol }
    return [pscustomobject]@{ X = [double]$r.X; Y = [double]$r.Y; W = [double]$r.Width; H = [double]$r.Height; Pusto = ($r.Width -lt 1 -or $r.Height -lt 1) }
  } catch { return $nol }
}

function Format-Ramka($r) { if (-not $r -or $r.Pusto) { return 'pusto' }; return ('{0},{1} {2}x{3}' -f [int]$r.X, [int]$r.Y, [int]$r.W, [int]$r.H) }

function New-ZaprosKesha([bool]$syroj) {
  $cr = New-Object System.Windows.Automation.CacheRequest
  $props = @($AE::NameProperty, $AE::ControlTypeProperty, $AE::BoundingRectangleProperty, $AE::IsOffscreenProperty,
    $AE::AutomationIdProperty, $AE::HelpTextProperty, $AE::IsKeyboardFocusableProperty, $AE::IsPasswordProperty,
    $AE::IsValuePatternAvailableProperty, $AE::IsTextPatternAvailableProperty, $AE::LabeledByProperty,
    $VP::ValueProperty, $VP::IsReadOnlyProperty)
  foreach ($p in $props) { $cr.Add($p) }
  $cr.TreeScope = [System.Windows.Automation.TreeScope]::Subtree
  if ($syroj) { $cr.TreeFilter = [System.Windows.Automation.Automation]::RawViewCondition }
  return $cr
}

function Get-Kesh($el, $prop) {
  try {
    $v = $el.GetCachedPropertyValue($prop, $true)
    if ([object]::ReferenceEquals($v, $AE::NotSupported)) { return $null }
    return $v
  } catch { return $null }
}

$script:KonteynerKnopki = @('Button', 'Hyperlink', 'MenuItem', 'TabItem', 'ListItem', 'TreeItem', 'CheckBox', 'RadioButton')
$script:TipyRedPohozhie = @('Group', 'Custom', 'Pane', 'Text', 'Document')

function Add-UzelSnimka($sn, $el, [int]$roditel, [int]$glub, [bool]$vRed, [bool]$vKnopke) {
  $nomer = $sn.Count
  $c = $el.Cached
  $ct = ''
  try { $ct = ($c.ControlType.ProgrammaticName -replace '^ControlType\.', '') } catch {}
  $fok = $false; try { $fok = [bool]$c.IsKeyboardFocusable } catch {}
  $vpOk = [bool](Get-Kesh $el $AE::IsValuePatternAvailableProperty)
  $tpOk = [bool](Get-Kesh $el $AE::IsTextPatternAvailableProperty)
  $red = $false
  if (-not $vRed -and $glub -gt 0) {
    if ($ct -eq 'Edit') { $red = $true }
    elseif ($fok -and ($vpOk -or $tpOk) -and ($script:TipyRedPohozhie -contains $ct)) { $red = $true }
  }
  $val = $null; $ro = $null; $lab = $null; $pw = $false
  if ($red) {
    $v = Get-Kesh $el $VP::ValueProperty; if ($null -ne $v) { $val = [string]$v }
    $v = Get-Kesh $el $VP::IsReadOnlyProperty; if ($null -ne $v) { $ro = [bool]$v }
    $lab = Get-Kesh $el $AE::LabeledByProperty
    try { $pw = [bool]$c.IsPassword } catch {}
  }
  $imya = ''; try { $imya = [string]$c.Name } catch {}
  $pomoshch = ''; try { $pomoshch = [string]$c.HelpText } catch {}
  $off = $false; try { $off = [bool]$c.IsOffscreen } catch {}
  $ramka = $null; try { $ramka = ConvertTo-Ramka $c.BoundingRectangle } catch { $ramka = ConvertTo-Ramka $null }
  $uzel = [pscustomobject]@{
    I = $nomer; P = $roditel; D = $glub; El = $el; Ct = $ct; Imya = $imya; Norm = (Get-NormMetka $imya)
    Help = $pomoshch; R = $ramka; Off = $off; Red = $red; Pisat = ($red -and ($ro -ne $true)); Val = $val
    Lab = $lab; Parol = $pw; VRed = $vRed; VKnopke = $vKnopke; Konec = $nomer
  }
  $sn.Add($uzel)
  $detiVRed = $vRed -or $red
  $detiVKn = $vKnopke -or ($script:KonteynerKnopki -contains $ct)
  $deti = $null
  try { $deti = $el.CachedChildren } catch {}
  if ($deti) { foreach ($ch in $deti) { Add-UzelSnimka $sn $ch $nomer ($glub + 1) $detiVRed $detiVKn } }
  $uzel.Konec = $sn.Count - 1
}

# flat pre-order list of the document subtree (tree order = list order)
function Get-Snimok($doc, [bool]$syroj = $false) {
  $sn = New-Object System.Collections.Generic.List[object]
  try {
    $koren = $doc.GetUpdatedCache((New-ZaprosKesha $syroj))
    Add-UzelSnimka $sn $koren -1 0 $false $false
  } catch { Write-RukiLog "snimok: $($_.Exception.Message)" }
  return ,$sn
}

# a text that names something: a Text element with a non-empty name (decor like "*" or ":"
# normalises to empty), outside editables and outside buttons/links/items
function Test-MetkoPodobnyj($u) {
  return ($u.Ct -eq 'Text') -and ($u.Norm -ne '') -and -not $u.VRed -and -not $u.VKnopke
}

function Test-PerekrytieV($a, $b) { return ($a.Y -lt ($b.Y + $b.H)) -and (($a.Y + $a.H) -gt $b.Y) }
function Test-PerekrytieH($a, $b) { return ($a.X -lt ($b.X + $b.W)) -and (($a.X + $a.W) -gt $b.X) }

# where the field lies relative to the label: sprava, snizu, net-geometrii or $null (above/left)
function Get-Otnoshenie($metkaR, $poleR) {
  if ($metkaR.Pusto -or $poleR.Pusto) { return 'net-geometrii' }
  $niz = $metkaR.Y + $metkaR.H; $prav = $metkaR.X + $metkaR.W
  if ($poleR.X -ge ($prav - 8) -and (Test-PerekrytieV $poleR $metkaR)) { return 'sprava' }
  if ($poleR.Y -ge ($niz - 8)) { return 'snizu' }
  return $null
}

function Resolve-PoDerevu($sn, $L) {
  $kont = $L.P
  $uroven = 0
  while ($kont -ge 0 -and $uroven -lt 4) {
    $k = $sn[$kont]
    $nashli = -1
    for ($j = $L.Konec + 1; $j -le $k.Konec; $j++) { if ($sn[$j].Red) { $nashli = $j; break } }
    if ($nashli -ge 0) {
      for ($j = $L.Konec + 1; $j -lt $nashli; $j++) {
        $u = $sn[$j]
        if (Test-MetkoPodobnyj $u) { return @{ Uzel = $null; Pochemu = "derevo: mezhdu metkoj i polem tekst '$($u.Imya)'" } }
      }
      $pole = $sn[$nashli]
      $otn = Get-Otnoshenie $L.R $pole.R
      if (-not $otn) { return @{ Uzel = $null; Pochemu = 'derevo: pole ne nizhe i ne pravee metki' } }
      return @{ Uzel = $pole; Sposob = 'derevo'; Pochemu = "pervoe redaktiruemoe posle metki v konteynere urovnya $($uroven + 1) ($otn)" }
    }
    $kont = $k.P
    $uroven++
  }
  return @{ Uzel = $null; Pochemu = 'derevo: v konteynere net redaktiruemogo posle metki' }
}

function Resolve-PoGeometrii($sn, $L) {
  if ($L.R.Pusto) { return @{ Uzel = $null; Pochemu = 'geometriya: u metki net ramki' } }
  $lr = $L.R
  $niz = $lr.Y + $lr.H; $prav = $lr.X + $lr.W
  $tex = @($sn | Where-Object { (Test-MetkoPodobnyj $_) -and -not $_.R.Pusto -and ($_.I -lt $L.I -or $_.I -gt $L.Konec) })
  $kand = New-Object System.Collections.Generic.List[object]
  foreach ($u in $sn) {
    if (-not $u.Red -or $u.R.Pusto) { continue }
    $pr = $u.R
    $kak = $null; $dist = 0.0
    if ($pr.X -ge ($prav - 8) -and (Test-PerekrytieV $pr $lr)) { $kak = 'sprava'; $dist = [Math]::Max(0, $pr.X - $prav) }
    elseif ($pr.Y -ge ($niz - 8) -and ((Test-PerekrytieH $pr $lr) -or [Math]::Abs($pr.X - $lr.X) -le $script:SosedRadius)) { $kak = 'snizu'; $dist = [Math]::Max(0, $pr.Y - $niz) }
    if (-not $kak -or $dist -gt $script:SosedRadius) { continue }
    $mezhdu = $null
    foreach ($t in $tex) {
      $tr = $t.R
      if ($kak -eq 'sprava') {
        if ($tr.X -ge ($prav - 2) -and ($tr.X + $tr.W) -le ($pr.X + 2) -and (Test-PerekrytieV $tr $lr)) { $mezhdu = $t; break }
      } else {
        if ($tr.Y -ge ($niz - 2) -and ($tr.Y + $tr.H) -le ($pr.Y + 2) -and (Test-PerekrytieH $tr $pr)) { $mezhdu = $t; break }
      }
    }
    if ($mezhdu) { Write-RukiLog "geometriya: pole $(Format-Ramka $pr) otbrosheno, mezhdu tekst '$($mezhdu.Imya)'"; continue }
    $kand.Add([pscustomobject]@{ Uzel = $u; Dist = $dist; Kak = $kak })
  }
  if ($kand.Count -eq 0) { return @{ Uzel = $null; Pochemu = "geometriya: net polya nizhe ili pravee v $($script:SosedRadius) px" } }
  $s = @($kand | Sort-Object Dist)
  if ($s.Count -gt 1 -and ($s[1].Dist - $s[0].Dist) -lt 6) {
    return @{ Uzel = $null; Neodnoznachno = $true; Pochemu = ("geometriya: dva polya na odnom rasstoyanii ({0} i {1} px)" -f [int]$s[0].Dist, [int]$s[1].Dist) }
  }
  return @{ Uzel = $s[0].Uzel; Sposob = 'geometriya'; Pochemu = ("blizhajshee {0} v {1} px" -f $s[0].Kak, [int]$s[0].Dist) }
}

function Get-KlyuchElementa($el) {
  try { return (($el.GetRuntimeId()) -join '.') } catch { return [string]$el.GetHashCode() }
}

# live visibility of a field: v-okne (on screen, inside the document viewport), skryto
# (2 px or less), za-oknom (has size but not on screen now)
function Get-Vidimost($doc, $el) {
  $r = $null; $off = $true
  try { $r = ConvertTo-Ramka $el.Current.BoundingRectangle; $off = [bool]$el.Current.IsOffscreen } catch { return [pscustomobject]@{ Sost = 'propalo'; R = (ConvertTo-Ramka $null) } }
  if ($r.Pusto -or $r.W -le 2 -or $r.H -le 2) { return [pscustomobject]@{ Sost = 'skryto'; R = $r } }
  $okno = $null; try { $okno = ConvertTo-Ramka $doc.Current.BoundingRectangle } catch {}
  $vOkne = -not $off
  if ($vOkne -and $okno -and -not $okno.Pusto) {
    $sh = [Math]::Min($r.X + $r.W, $okno.X + $okno.W) - [Math]::Max($r.X, $okno.X)
    $vy = [Math]::Min($r.Y + $r.H, $okno.Y + $okno.H) - [Math]::Max($r.Y, $okno.Y)
    $vOkne = ($sh -ge [Math]::Min(6, $r.W)) -and ($vy -ge [Math]::Min(6, $r.H))
  }
  if ($vOkne) { return [pscustomobject]@{ Sost = 'v-okne'; R = $r } }
  return [pscustomobject]@{ Sost = 'za-oknom'; R = $r }
}

function Invoke-Prokrutka($el) {
  try { $el.GetCurrentPattern([System.Windows.Automation.ScrollItemPattern]::Pattern).ScrollIntoView(); return $true } catch { return $false }
}

# bring the field into the viewport if it can be; returns the visibility after that
function Confirm-Dostupno($doc, $el) {
  $v = Get-Vidimost $doc $el
  if ($v.Sost -ne 'za-oknom') { return $v }
  if (-not (Invoke-Prokrutka $el)) { return [pscustomobject]@{ Sost = 'nedostupno'; R = $v.R; Pochemu = 'net ScrollItem' } }
  $sw = [Diagnostics.Stopwatch]::StartNew()
  do {
    Start-Sleep -Milliseconds 120
    $v = Get-Vidimost $doc $el
  } while ($v.Sost -eq 'za-oknom' -and $sw.ElapsedMilliseconds -lt 900)
  if ($v.Sost -eq 'za-oknom') { return [pscustomobject]@{ Sost = 'nedostupno'; R = $v.R; Pochemu = 'posle prokrutki vsyo eshchyo vne okna' } }
  return $v
}

# a point inside the field (near its start, where a click puts the caret into the text)
function Get-TochkaKlika($r) {
  $x = $r.X + [Math]::Min(14.0, $r.W / 2)
  $y = $r.Y + [Math]::Min(14.0, $r.H / 2)
  return [pscustomobject]@{ X = $x; Y = $y }
}

# is the field what a click at its point would hit (not covered, not clipped)
function Test-NeZakryto($doc, $el, [int]$raz = 3) {
  for ($i = 0; $i -lt $raz; $i++) {
    $v = Get-Vidimost $doc $el
    if ($v.Sost -eq 'v-okne') {
      $t = Get-TochkaKlika $v.R
      $pod = Get-ElementVTochke $t.X $t.Y
      if (Test-VnutriElementa $pod $el) { return $true }
    }
    Start-Sleep -Milliseconds 150
  }
  return $false
}

function Write-Kandidat($r) {
  $u = $r.Uzel
  return [ordered]@{
    sposob = $r.Sposob; pochemu = $r.Pochemu; dostup = $r.Dostup
    metka = $(if ($r.Metka) { [ordered]@{ imya = $r.Metka.Imya; ramka = (Format-Ramka $r.Metka.R); off = $r.Metka.Off } } else { $null })
    pole = [ordered]@{ tip = $u.Ct; imya = $u.Imya; id = $u.Id; ramka = (Format-Ramka $u.R); off = $u.Off; nomer_v_dereve = $u.I }
  }
}

function Find-Metki($sn, [string]$norm) {
  return @($sn | Where-Object { -not $_.VRed -and -not $_.Red -and $_.Norm -eq $norm -and $_.I -gt 0 -and ($script:KonteynerKnopki -notcontains $_.Ct) })
}
function Find-Pryamye($sn, [string]$norm) {
  return @($sn | Where-Object { $_.Red -and (($_.Norm -eq $norm) -or ((Get-NormMetka $_.Help) -eq $norm)) })
}

# pure part of the resolution (no live UIA except LabeledBy comparison): every field some
# label candidate leads to, one entry per field, and the labels that led nowhere
function Find-KandidatyPolya($sn, [string]$norm) {
  $metki = Find-Metki $sn $norm
  $pryamye = Find-Pryamye $sn $norm
  $redakt = @($sn | Where-Object { $_.Red })
  $nayd = New-Object System.Collections.Generic.List[object]
  $otkazy = New-Object System.Collections.Generic.List[object]
  foreach ($u in $pryamye) {
    $kak = if ($u.Norm -eq $norm) { 'imya' } else { 'podskazka' }
    $nayd.Add(@{ Uzel = $u; Sposob = $kak; Pochemu = "u polya svoyo $kak = metka"; Metka = $null })
  }
  foreach ($L in $metki) {
    $res = $null
    foreach ($u in $redakt) {
      if ($u.Lab -and (Test-TotZhe $u.Lab $L.El)) { $res = @{ Uzel = $u; Sposob = 'labeledby'; Pochemu = 'UIA LabeledBy ukazyvaet na metku' }; break }
    }
    if (-not $res) {
      $d = Resolve-PoDerevu $sn $L
      if ($d.Uzel) { $res = $d }
      else {
        $g = Resolve-PoGeometrii $sn $L
        if ($g.Uzel) { $g.Pochemu = $d.Pochemu + '; ' + $g.Pochemu; $res = $g }
        else {
          $otkazy.Add([ordered]@{ metka = $L.Imya; ramka = (Format-Ramka $L.R); neodnoznachno = [bool]$g.Neodnoznachno; pochemu = ($d.Pochemu + '; ' + $g.Pochemu) })
          continue
        }
      }
    }
    $res.Metka = $L
    $nayd.Add($res)
  }
  $bylo = @{}
  $vse = New-Object System.Collections.Generic.List[object]
  foreach ($r in $nayd) {
    $k = [string]$r.Uzel.I
    if (-not $bylo.ContainsKey($k)) { $bylo[$k] = $true; $vse.Add($r) }
  }
  return @{ Metki = $metki; Pryamye = $pryamye; Redakt = $redakt; Vse = $vse.ToArray(); Otkazy = $otkazy.ToArray() }
}

function Resolve-PoleUMetki($doc, [string]$Metka, [int]$OzhidanieMs = 8000) {
  $norm = Get-NormMetka $Metka
  $sw = [Diagnostics.Stopwatch]::StartNew()
  $syroj = $false
  $sn = $null
  while ($true) {
    $sn = Get-Snimok $doc $syroj
    if ((Find-Metki $sn $norm).Count -gt 0 -or (Find-Pryamye $sn $norm).Count -gt 0) { break }
    if ($sw.ElapsedMilliseconds -ge $OzhidanieMs) {
      if ($syroj) { break }
      $syroj = $true; Write-RukiLog 'net metki v control view, probuyu raw view'; continue
    }
    Start-Sleep -Milliseconds 400
  }
  $kp = Find-KandidatyPolya $sn $norm
  Write-RukiLog ("snimok: uzlov {0}, redaktiruemyh {1}, metok '{2}' {3}, pryamyh {4}, {5} ms" -f $sn.Count, $kp.Redakt.Count, $Metka, $kp.Metki.Count, $kp.Pryamye.Count, $sw.ElapsedMilliseconds)
  $otvet = @{ Status = 'stop'; Prichina = ''; Uzel = $null; Vybor = $null; Kandidaty = @(); Otkazy = @($kp.Otkazy); Snimok = $sn }
  if ($kp.Metki.Count -eq 0 -and $kp.Pryamye.Count -eq 0) { $otvet.Prichina = 'net-metki'; return $otvet }
  $vse = @($kp.Vse)
  foreach ($o in $kp.Otkazy) { Write-RukiLog "otkaz metki $($o.metka) $($o.ramka): $($o.pochemu)" }
  Write-RukiLog ("kandidatov-poley {0}, otkazov metok {1}" -f $vse.Count, $kp.Otkazy.Count)
  if ($vse.Count -eq 0) {
    $otvet.Prichina = if (@($kp.Otkazy | Where-Object { $_.neodnoznachno }).Count -gt 0) { 'neodnoznachno' } else { 'net-polya' }
    return $otvet
  }
  # reachability: hidden copies (tiny, or off screen even after scrolling) are dropped
  foreach ($r in $vse) {
    $v = Get-Vidimost $doc $r.Uzel.El
    $r.Dostup = $v.Sost
  }
  foreach ($r in $vse) {
    if ($r.Dostup -eq 'za-oknom') {
      $v = Confirm-Dostupno $doc $r.Uzel.El
      $r.Dostup = $(if ($v.Sost -eq 'v-okne') { 'posle-prokrutki' } else { $v.Sost })
    }
  }
  $dost = @($vse | Where-Object { $_.Dostup -eq 'v-okne' -or $_.Dostup -eq 'posle-prokrutki' })
  if ($dost.Count -gt 1) {
    $otkr = @($dost | Where-Object {
      $null = Confirm-Dostupno $doc $_.Uzel.El
      $ok = Test-NeZakryto $doc $_.Uzel.El
      if (-not $ok) { $_.Dostup = 'zakryto' }
      $ok
    })
    if ($otkr.Count -ge 1) { $dost = $otkr }
  }
  $otvet.Kandidaty = @($vse | ForEach-Object { Write-Kandidat $_ })
  foreach ($r in $vse) { Write-RukiLog ("kandidat: {0} {1} pole {2} {3} | {4}" -f $r.Sposob, $r.Dostup, $r.Uzel.Ct, (Format-Ramka $r.Uzel.R), $r.Pochemu) }
  if ($dost.Count -eq 0) { $otvet.Prichina = 'pole-nedostupno'; return $otvet }
  if ($dost.Count -gt 1) { $otvet.Prichina = 'neodnoznachno'; return $otvet }
  $vyb = $dost[0]
  $otbr = @($vse | Where-Object { -not [object]::ReferenceEquals($_, $vyb) } | ForEach-Object { "$($_.Dostup) $(Format-Ramka $_.Uzel.R)" })
  $otvet.Status = 'ok'
  $otvet.Uzel = $vyb.Uzel
  $otvet.Vybor = [ordered]@{
    sposob = $vyb.Sposob; dostup = $vyb.Dostup
    pochemu = $vyb.Pochemu + $(if ($otbr.Count) { '; otbrosheny: ' + ($otbr -join ', ') } else { '; edinstvennyj kandidat' })
    pole = (Write-Kandidat $vyb).pole
  }
  return $otvet
}
