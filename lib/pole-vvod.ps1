# Typing into a field found by Resolve-PoleUMetki: scroll into view, hit test, click to focus,
# confirm the focus is in this field (or inside it, for contenteditable), clear, type in
# chunks with a focus check before every chunk, read back (TextPattern when ValuePattern is
# missing or cut), and check that no other field changed.
# Set-TekstVPole $ctx $uzel 'text' -> @{ Status = ok|stop; Prichina; Popytki; Podrobno }
# Honest stops: pole-parolya, pole-tolko-dlya-chteniya, perenos-ne-podderzhan, fokus-ne-v-pole,
# ne-sovpalo-posle-popytok, zadeto-drugoe-pole.
# Windows PowerShell 5.1, ASCII only. Needs uia.ps1, okno.ps1, vvod.ps1, mysh.ps1, sosed.ps1.

function Get-ZnachPolya($el) {
  $v = $null
  try { $v = Get-Znachenie $el } catch {}
  if ($null -eq $v -or $v -is [bool]) { $v = Get-ZnachenieTekstom $el }
  return $v
}

# contenteditable reads back with NBSP for some spaces and a trailing line break
function ConvertTo-NormZnach($s) {
  if ($null -eq $s) { return $null }
  $t = ([string]$s) -replace "`r`n", "`n" -replace "`r", "`n"
  $t = $t -replace '\u00A0', ' '
  return ($t -replace "`n+$", '')
}

function Test-ZnachRavno($v, [string]$cel) {
  if ($null -eq $v) { return $false }
  if (([string]$v) -ceq $cel) { return $true }
  return ((ConvertTo-NormZnach $v) -ceq (ConvertTo-NormZnach $cel))
}

# empty, or only showing its own placeholder
function Test-ZnachPusto($v, $uzel) {
  $n = ConvertTo-NormZnach $v
  if ($null -eq $n -or $n -eq '') { return $true }
  foreach ($p in @($uzel.Imya, $uzel.Help)) { if ($p -and $n -ceq (ConvertTo-NormZnach $p)) { return $true } }
  return $false
}

function Test-FokusVPole($el) {
  $f = Get-Fokus
  if (-not $f) { return $false }
  if (Test-TotZhe $f $el) { return $true }
  return (Test-VnutriElementa $f $el 6)
}

function Wait-ZnachRavno($el, [string]$cel, [int]$TimeoutMs) {
  $sw = [Diagnostics.Stopwatch]::StartNew()
  $v = Get-ZnachPolya $el
  while (-not (Test-ZnachRavno $v $cel) -and $sw.ElapsedMilliseconds -lt $TimeoutMs) {
    Start-Sleep -Milliseconds 80
    $v = Get-ZnachPolya $el
  }
  return $v
}

# values of every other writable field, keyed by runtime id
function Get-ZnacheniyaDrugih($doc, $el) {
  $moj = Get-KlyuchElementa $el
  $res = @{}
  $sn = Get-Snimok $doc
  foreach ($u in $sn) {
    if (-not $u.Pisat) { continue }
    $k = Get-KlyuchElementa $u.El
    if ($k -eq $moj) { continue }
    $res[$k] = [pscustomobject]@{ V = (ConvertTo-NormZnach $u.Val); Imya = $u.Imya; R = (Format-Ramka $u.R) }
  }
  return $res
}

# click into the field until the focus is in it. returns 'klik', 'setfocus' or $null
function Set-FokusKlikom($ctx, $uzel) {
  $el = $uzel.El
  for ($i = 1; $i -le 6; $i++) {
    $ok = Confirm-OknoVidimo $ctx.Hwnd
    if ($ok.Bylo) { Add-Pomeha $ctx 'okno' }
    if (Test-FokusVPole $el) { return 'uzhe' }
    if ($i -le 4) {
      $v = Confirm-Dostupno $ctx.Doc $el
      if ($v.Sost -ne 'v-okne') { Write-RukiLog "fokus: pole $($v.Sost)"; Start-Sleep -Milliseconds 200; continue }
      $t = Get-TochkaKlika $v.R
      $pod = Get-ElementVTochke $t.X $t.Y
      if (-not (Test-VnutriElementa $pod $el)) {
        $kto = ''; try { $kto = "$($pod.Current.ControlType.ProgrammaticName) '$($pod.Current.Name)'" } catch {}
        Write-RukiLog ("fokus: v tochke {0},{1} ne nashe pole ({2}), zhdu" -f [int]$t.X, [int]$t.Y, $kto)
        Add-Pomeha $ctx 'tochka-ne-nasha'
        Start-Sleep -Milliseconds 250
        continue
      }
      Invoke-Klik $t.X $t.Y
      $sw = [Diagnostics.Stopwatch]::StartNew()
      do { Start-Sleep -Milliseconds 60 } while (-not (Test-FokusVPole $el) -and $sw.ElapsedMilliseconds -lt 600)
      if (Test-FokusVPole $el) { return 'klik' }
      $f = Get-Fokus
      $kto = ''; try { $kto = "$($f.Current.ControlType.ProgrammaticName) '$($f.Current.Name)'" } catch {}
      Write-RukiLog "fokus: posle klika fokus ne v pole, a v $kto"
      Add-Pomeha $ctx 'klik-mimo'
    } else {
      try { $el.SetFocus() } catch {}
      Start-Sleep -Milliseconds 150
      if (Test-FokusVPole $el) { Add-Pomeha $ctx 'setfocus'; return 'setfocus' }
    }
  }
  return $null
}

function Set-TekstVPole($ctx, $uzel, [string]$Tekst) {
  $el = $uzel.El
  if ($uzel.Parol) { return @{ Status = 'stop'; Prichina = 'pole-parolya'; Popytki = 0 } }
  if (-not $uzel.Pisat) { return @{ Status = 'stop'; Prichina = 'pole-tolko-dlya-chteniya'; Popytki = 0 } }
  if ($Tekst -match "[`r`n]") { return @{ Status = 'stop'; Prichina = 'perenos-ne-podderzhan'; Popytki = 0 } }
  $dlinnyj = $Tekst.Length -gt 200
  $kusok = if ($dlinnyj) { 48 } else { 12 }
  $drugieDo = Get-ZnacheniyaDrugih $ctx.Doc $el
  $sposobFokusa = $null
  for ($pop = 1; $pop -le 4; $pop++) {
    $sposobFokusa = Set-FokusKlikom $ctx $uzel
    if (-not $sposobFokusa) { continue }
    # clear: select all inside the field, delete; only while the focus is in it
    $pusto = $false
    for ($c = 0; $c -lt 3 -and -not $pusto; $c++) {
      if (-not (Test-FokusVPole $el)) { break }
      Send-Klavisha 'CtrlA'
      if (-not (Test-FokusVPole $el)) { break }
      Send-Klavisha 'Delete'
      $sw = [Diagnostics.Stopwatch]::StartNew()
      do { Start-Sleep -Milliseconds 60; $pusto = Test-ZnachPusto (Get-ZnachPolya $el) $uzel } while (-not $pusto -and $sw.ElapsedMilliseconds -lt 700)
    }
    if (-not $pusto) { Write-RukiLog "vvod: pole ne ochistilos, popytka $pop"; continue }
    $i = 0; $sorvano = $false; $nKuskov = 0
    while ($i -lt $Tekst.Length) {
      if (-not (Test-FokusVPole $el)) { $sorvano = $true; Write-RukiLog "vvod: fokus ushel na $i iz $($Tekst.Length)"; Add-Pomeha $ctx 'fokus-ushel'; break }
      $n = [Math]::Min($kusok, $Tekst.Length - $i)
      if ([char]::IsHighSurrogate($Tekst[$i + $n - 1]) -and ($i + $n) -lt $Tekst.Length) { $n++ }
      $null = [RukiKlav]::Stroka($Tekst.Substring($i, $n))
      $i += $n; $nKuskov++
      Start-Sleep -Milliseconds $(if ($dlinnyj) { 30 } else { 15 })
      if ($dlinnyj -and ($nKuskov % 20) -eq 0) {
        $chast = $Tekst.Substring(0, $i)
        $v = Wait-ZnachRavno $el $chast 8000
        if (-not (Test-ZnachRavno $v $chast)) { $sorvano = $true; Write-RukiLog "vvod: sverka kuska ne soshlas na $i"; break }
      }
    }
    if ($sorvano) { continue }
    $v = Wait-ZnachRavno $el $Tekst (2500 + [int]($Tekst.Length / 2))
    if (Test-ZnachRavno $v $Tekst) {
      $drugiePosle = Get-ZnacheniyaDrugih $ctx.Doc $el
      $zadeto = @()
      foreach ($k in $drugieDo.Keys) {
        if ($drugiePosle.ContainsKey($k) -and $drugiePosle[$k].V -cne $drugieDo[$k].V) { $zadeto += "$($drugieDo[$k].Imya) $($drugieDo[$k].R)" }
      }
      if ($zadeto.Count) { return @{ Status = 'stop'; Prichina = 'zadeto-drugoe-pole'; Popytki = $pop; Podrobno = ($zadeto -join '; ') } }
      $dl = 0; try { $dl = ([string]$v).Length } catch {}
      return @{ Status = 'ok'; Popytki = $pop; Fokus = $sposobFokusa; Prochitano = $dl }
    }
    $vl = if ($null -eq $v) { 'null' } else { ([string]$v).Length }
    Write-RukiLog "vvod: posle nabora prochitano $vl iz $($Tekst.Length), popytka $pop"
  }
  if (-not $sposobFokusa) { return @{ Status = 'stop'; Prichina = 'fokus-ne-v-pole'; Popytki = 4 } }
  return @{ Status = 'stop'; Prichina = 'ne-sovpalo-posle-popytok'; Popytki = 4 }
}
