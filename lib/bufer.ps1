# Clipboard of the operator: save every format, put our text (excluded from clipboard
# history and cloud sync), restore the previous content afterwards.
# Restore is skipped if someone else changed the clipboard after us (their new content wins).
Add-Type -AssemblyName System.Windows.Forms
if (-not ('RukiBufer' -as [type])) {
Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class RukiBufer {
  [DllImport("user32.dll")] public static extern uint GetClipboardSequenceNumber();
}
'@
}

function Invoke-SPovtorom([scriptblock]$b, [int]$raz = 10) {
  for ($i = 0; $i -lt $raz; $i++) {
    try { return (& $b) } catch { Start-Sleep -Milliseconds (30 + 20 * $i) }
  }
  throw "bufer zanyat"
}

# snapshot: list of @{ F = format; D = data }, or empty list for an empty clipboard
function Save-Bufer {
  $snimok = New-Object System.Collections.ArrayList
  $do = Invoke-SPovtorom { [System.Windows.Forms.Clipboard]::GetDataObject() }
  if ($do) {
    foreach ($f in $do.GetFormats($false)) {
      try {
        $d = $do.GetData($f, $false)
        if ($null -eq $d) { continue }
        if ($d -is [System.IO.Stream]) {
          $ms = New-Object System.IO.MemoryStream
          $d.CopyTo($ms); $ms.Position = 0; $d = $ms
        }
        $null = $snimok.Add(@{ F = $f; D = $d })
      } catch { Write-RukiLog "bufer: format $f ne sohranyon" }
    }
  }
  Write-RukiLog "bufer: sohranyon, formatov $($snimok.Count)"
  return ,$snimok
}

function New-ObektBezIstorii {
  $o = New-Object System.Windows.Forms.DataObject
  # keep our text out of Win+V history and cloud clipboard
  $nol = New-Object System.IO.MemoryStream (, [byte[]](0, 0, 0, 0))
  $o.SetData('ExcludeClipboardContentFromMonitorProcessing', $false, (New-Object System.IO.MemoryStream (, [byte[]](0))))
  $o.SetData('CanIncludeInClipboardHistory', $false, $nol)
  $o.SetData('CanUploadToCloudClipboard', $false, (New-Object System.IO.MemoryStream (, [byte[]](0, 0, 0, 0))))
  return $o
}

# put text; returns the clipboard sequence number after our write
function Set-BuferTekst([string]$s) {
  $o = New-ObektBezIstorii
  $o.SetData([System.Windows.Forms.DataFormats]::UnicodeText, $false, $s)
  Invoke-SPovtorom { [System.Windows.Forms.Clipboard]::SetDataObject($o, $false, 10, 40) } | Out-Null
  return [RukiBufer]::GetClipboardSequenceNumber()
}

# restore the snapshot unless the clipboard changed after our own write ($nashNomer)
function Restore-Bufer($snimok, [uint32]$nashNomer = 0) {
  if ($nashNomer -and [RukiBufer]::GetClipboardSequenceNumber() -ne $nashNomer) {
    Write-RukiLog 'bufer: izmenyon kem-to posle nas, ne trogayu'
    return 'chuzhoe'
  }
  if (-not $snimok -or $snimok.Count -eq 0) {
    Invoke-SPovtorom { [System.Windows.Forms.Clipboard]::Clear() } | Out-Null
    Write-RukiLog 'bufer: vosstanovlen pustym'
    return 'pusto'
  }
  $o = New-Object System.Windows.Forms.DataObject
  foreach ($x in $snimok) {
    try {
      if ($x.D -is [System.IO.MemoryStream]) { $x.D.Position = 0 }
      $o.SetData($x.F, $false, $x.D)
    } catch { Write-RukiLog "bufer: format $($x.F) ne vosstanovlen" }
  }
  Invoke-SPovtorom { [System.Windows.Forms.Clipboard]::SetDataObject($o, $true, 10, 40) } | Out-Null
  Write-RukiLog "bufer: vosstanovlen, formatov $($snimok.Count)"
  return 'ok'
}
