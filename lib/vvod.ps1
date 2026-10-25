# Keyboard input: SendInput KEYEVENTF_UNICODE with a focus check before each chunk
# and read-back after it. Keys Enter / Tab / Esc. Stop on a password field.
if (-not ('RukiKlav' -as [type])) {
Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class RukiKlav {
  [StructLayout(LayoutKind.Sequential)] public struct KI { public ushort vk; public ushort sc; public uint fl; public uint t; public IntPtr ex; }
  [StructLayout(LayoutKind.Explicit, Size = 40)] public struct IN { [FieldOffset(0)] public uint type; [FieldOffset(8)] public KI ki; }
  [DllImport("user32.dll", SetLastError = true)] public static extern uint SendInput(uint n, IN[] i, int s);
  static int Sz() { return Marshal.SizeOf(typeof(IN)); }
  static IN K(ushort vk, ushort sc, uint fl) { IN x = new IN(); x.type = 1; x.ki = new KI(); x.ki.vk = vk; x.ki.sc = sc; x.ki.fl = fl; return x; }
  public static uint Simvol(char ch) {
    return SendInput(2, new IN[] { K(0, ch, 4), K(0, ch, 6) }, Sz());
  }
  public static uint Klavisha(ushort vk, bool ext) {
    uint e = ext ? 1u : 0u;
    return SendInput(2, new IN[] { K(vk, 0, e), K(vk, 0, e | 2) }, Sz());
  }
  // a whole string in one SendInput call: surrogate pairs stay together, '\n' is Enter
  public static uint Stroka(string s) {
    var a = new System.Collections.Generic.List<IN>();
    foreach (char ch in s) {
      if (ch == '\r') continue;
      if (ch == '\n') { a.Add(K(0x0D, 0, 0)); a.Add(K(0x0D, 0, 2)); continue; }
      a.Add(K(0, ch, 4)); a.Add(K(0, ch, 6));
    }
    if (a.Count == 0) return 0;
    return SendInput((uint)a.Count, a.ToArray(), Sz());
  }
  public static uint SModom(ushort mod, ushort vk, bool ext) {
    uint e = ext ? 1u : 0u;
    return SendInput(4, new IN[] { K(mod, 0, 0), K(vk, 0, e), K(vk, 0, e | 2), K(mod, 0, 2) }, Sz());
  }
}
'@
}

$script:VK = @{ Enter = 0x0D; Tab = 0x09; Esc = 0x1B; End = 0x23; Home = 0x24; Delete = 0x2E; Backspace = 0x08; A = 0x41; V = 0x56; Ctrl = 0x11; Space = 0x20; Down = 0x28; Up = 0x26 }
$script:VKext = @{ End = $true; Home = $true; Delete = $true; Down = $true; Up = $true }

function Send-Klavisha([string]$imya) {
  switch ($imya) {
    'CtrlA'   { $null = [RukiKlav]::SModom($VK.Ctrl, $VK.A, $false); return }
    'CtrlEnd' { $null = [RukiKlav]::SModom($VK.Ctrl, $VK.End, $true); return }
    'CtrlV'   { $null = [RukiKlav]::SModom($VK.Ctrl, $VK.V, $false); return }
    default   { $null = [RukiKlav]::Klavisha([uint16]$VK[$imya], [bool]$VKext[$imya]) }
  }
}

# per character with a pause; a surrogate pair goes as one unit
function Send-Tekst([string]$s, [int]$pauza = 12) {
  $i = 0
  while ($i -lt $s.Length) {
    $n = if ([char]::IsHighSurrogate($s[$i]) -and $i + 1 -lt $s.Length) { 2 } else { 1 }
    $null = [RukiKlav]::Stroka($s.Substring($i, $n))
    $i += $n
    Start-Sleep -Milliseconds $pauza
  }
}

# context: @{ Doc; Okno; Hwnd; Plan; Pomehi = @{}; EstParol = bool }
function Add-Pomeha($ctx, [string]$k) {
  if (-not $ctx.Pomehi.ContainsKey($k)) { $ctx.Pomehi[$k] = 0 }
  $ctx.Pomehi[$k]++
}

# close a modal dialog: Esc first, then a button inside it
function Close-Dialog($ctx) {
  $d = Find-Dialog $ctx.Doc
  if (-not $d) { return $false }
  Add-Pomeha $ctx 'dialog'
  Write-RukiLog "dialog: $($d.Current.Name)"
  Send-Klavisha 'Esc'
  Start-Sleep -Milliseconds 250
  if (-not (Find-Dialog $ctx.Doc)) { return $true }
  try {
    $b = $d.FindFirst($TS::Descendants, (New-PropCond $AE::ControlTypeProperty $CT::Button))
    if ($b) { $b.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke() }
  } catch {}
  Start-Sleep -Milliseconds 250
  return -not (Find-Dialog $ctx.Doc)
}

# environment ready for typing into $el: window in front, no dialog, focus on $el
# returns 'ok', 'parol' or 'net'
function Confirm-Gotovnost($ctx, $el) {
  for ($i = 0; $i -lt 5; $i++) {
    $ok = Confirm-OknoVidimo $ctx.Hwnd
    if ($ok.Bylo) { Add-Pomeha $ctx 'okno' }
    if (-not $ok.Ok) { continue }
    if (Find-Dialog $ctx.Doc) { $null = Close-Dialog $ctx; continue }
    $f = Get-Fokus
    if (Test-TotZhe $f $el) { return 'ok' }
    if (Test-Parol $f) { Write-RukiLog 'fokus v pole parolya' }
    Add-Pomeha $ctx 'fokus'
    try { $el.SetFocus() } catch {}
    Start-Sleep -Milliseconds (80 + 60 * $i)
    $f = Get-Fokus
    if (Test-TotZhe $f $el) { return 'ok' }
    if ($i -ge 2) { Send-Klavisha 'Esc'; Start-Sleep -Milliseconds 150 }
  }
  return 'net'
}

# read back until it equals $ozhid or times out; returns last value
function Wait-Znachenie($el, $ozhid, [int]$TimeoutMs = 1200) {
  $sw = [Diagnostics.Stopwatch]::StartNew()
  $v = Get-Znachenie $el
  while ($v -cne $ozhid -and $sw.ElapsedMilliseconds -lt $TimeoutMs) {
    Start-Sleep -Milliseconds 60
    $v = Get-Znachenie $el
  }
  return $v
}

# stable read: two equal reads in a row
function Get-ZnachenieUstojchivo($el) {
  $a = Get-Znachenie $el
  for ($i = 0; $i -lt 6; $i++) {
    Start-Sleep -Milliseconds 80
    $b = Get-Znachenie $el
    if ($a -ceq $b) { return $b }
    $a = $b
  }
  return $a
}

function Set-Flazhok($ctx, $shag) {
  $cel = [bool]$shag.znachenie
  for ($pop = 1; $pop -le 5; $pop++) {
    $el = Find-Element $ctx.Doc $shag.id $shag.metka 'flazhok' 6000
    if (-not $el) { return @{ Status = 'stop'; Prichina = 'net-elementa'; Popytki = $pop } }
    $ok = Confirm-OknoVidimo $ctx.Hwnd
    if ($ok.Bylo) { Add-Pomeha $ctx 'okno' }
    if (Find-Dialog $ctx.Doc) { $null = Close-Dialog $ctx; continue }
    $v = Get-ZnachenieUstojchivo $el
    if ($v -ceq $cel) { return @{ Status = 'ok'; Popytki = $pop } }
    if (-not $el.Current.IsEnabled) { return @{ Status = 'stop'; Prichina = 'flazhok-nedostupen'; Popytki = $pop } }
    try { $el.GetCurrentPattern([System.Windows.Automation.TogglePattern]::Pattern).Toggle() } catch { continue }
    if ((Wait-Znachenie $el $cel 1000) -ceq $cel) { return @{ Status = 'ok'; Popytki = $pop } }
  }
  return @{ Status = 'stop'; Prichina = 'flazhok-ne-ustanovlen'; Popytki = 5 }
}
