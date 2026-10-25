# Mouse: DPI awareness (so UIA rectangles and the cursor share physical pixels), a left
# click at a point, and a hit test: is the element under a point the one we mean (or inside
# it). Windows PowerShell 5.1, ASCII only. Needs uia.ps1.
if (-not ('RukiMysh' -as [type])) {
Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class RukiMysh {
  [DllImport("user32.dll")] static extern bool SetProcessDPIAware();
  [DllImport("user32.dll")] static extern bool SetProcessDpiAwarenessContext(IntPtr v);
  [DllImport("user32.dll")] static extern bool SetCursorPos(int x, int y);
  [DllImport("user32.dll", SetLastError = true)] static extern uint SendInput(uint n, MIN[] i, int s);
  [StructLayout(LayoutKind.Sequential)] public struct MI { public int dx; public int dy; public uint data; public uint fl; public uint t; public IntPtr ex; }
  [StructLayout(LayoutKind.Explicit, Size = 40)] public struct MIN { [FieldOffset(0)] public uint type; [FieldOffset(8)] public MI mi; }
  public static string Dpi = "";
  public static void DpiAware() {
    if (Dpi != "") return;
    try { if (SetProcessDpiAwarenessContext(new IntPtr(-4))) { Dpi = "per-monitor-v2"; return; } } catch {}
    try { if (SetProcessDPIAware()) { Dpi = "system"; return; } } catch {}
    Dpi = "net";
  }
  public static uint Klik(int x, int y) {
    SetCursorPos(x, y);
    System.Threading.Thread.Sleep(20);
    var a = new MIN[2];
    a[0].type = 0; a[0].mi.fl = 0x0002;
    a[1].type = 0; a[1].mi.fl = 0x0004;
    return SendInput(2, a, Marshal.SizeOf(typeof(MIN)));
  }
}
'@
}
[RukiMysh]::DpiAware()

# true when $kto is $cel or lies inside it (walks up at most $glubina parents)
function Test-VnutriElementa($kto, $cel, [int]$glubina = 14) {
  if (-not $kto -or -not $cel) { return $false }
  $w = [System.Windows.Automation.TreeWalker]::RawViewWalker
  $x = $kto
  for ($i = 0; $i -le $glubina -and $x; $i++) {
    if (Test-TotZhe $x $cel) { return $true }
    try { $x = $w.GetParent($x) } catch { return $false }
  }
  return $false
}

# element under a screen point
function Get-ElementVTochke([double]$x, [double]$y) {
  try { return $AE::FromPoint((New-Object System.Windows.Point($x, $y))) } catch { return $null }
}

function Invoke-Klik([double]$x, [double]$y) {
  $null = [RukiMysh]::Klik([int][Math]::Round($x), [int][Math]::Round($y))
}
