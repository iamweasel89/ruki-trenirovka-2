# Screen reading by recognition, the fallback for when UIA does not see the elements:
# a canvas, custom-drawn controls, text in a picture, game-like UI, trimmed accessibility.
# Engines: Windows OCR (Windows.Media.Ocr through WinRT) first, Tesseract when installed.
# Find a phrase, click its centre, check by a second read. Windows PowerShell 5.1, ASCII only.
#
# Main entry points:
#   Find-TekstNaEkrane -Tekst 'Save' [-Okno <hwnd>]   -> @{ Status = nashel|ne-nashel|neodnoznachno; Ramka; ... }
#   Invoke-KlikPoTekstu -Tekst 'Save' [-Okno <hwnd>]  -> find, second read (motion), click, read again
# Honest stops: ne-nashel (absent after every pass), neodnoznachno (several equal matches),
# poteryal (found once, gone on the second read: nothing is clicked).

Add-Type -AssemblyName System.Drawing
if (-not ('RukiObraz' -as [type])) {
Add-Type -ReferencedAssemblies System.Drawing @'
using System;
using System.Drawing;
using System.Drawing.Imaging;
using System.Drawing.Drawing2D;
using System.Runtime.InteropServices;
using System.Text;
public static class RukiObraz {
  [DllImport("user32.dll")] static extern bool SetProcessDPIAware();
  [DllImport("user32.dll")] static extern bool SetProcessDpiAwarenessContext(IntPtr v);
  [DllImport("user32.dll")] static extern bool SetCursorPos(int x, int y);
  [DllImport("user32.dll")] static extern int GetSystemMetrics(int i);
  [DllImport("user32.dll")] static extern bool GetClientRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] static extern bool ClientToScreen(IntPtr h, ref POINT p);
  [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] static extern IntPtr GetForegroundWindow();
  public delegate bool EnumProc(IntPtr h, IntPtr l);
  [DllImport("user32.dll")] static extern bool EnumWindows(EnumProc f, IntPtr l);
  [DllImport("user32.dll", SetLastError = true)] static extern uint SendInput(uint n, MIN[] i, int s);
  [StructLayout(LayoutKind.Sequential)] public struct POINT { public int X; public int Y; }
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int L; public int T; public int R; public int B; }
  [StructLayout(LayoutKind.Sequential)] public struct MI { public int dx; public int dy; public uint data; public uint fl; public uint t; public IntPtr ex; }
  [StructLayout(LayoutKind.Explicit, Size = 40)] public struct MIN { [FieldOffset(0)] public uint type; [FieldOffset(8)] public MI mi; }

  public static string Dpi = "";
  public static void DpiAware() {
    try { if (SetProcessDpiAwarenessContext(new IntPtr(-4))) { Dpi = "per-monitor-v2"; return; } } catch {}
    try { if (SetProcessDPIAware()) { Dpi = "system"; return; } } catch {}
    Dpi = "net";
  }
  // virtual screen: x, y, w, h (physical pixels once DPI aware)
  public static int[] Ekran() { return new int[] { GetSystemMetrics(76), GetSystemMetrics(77), GetSystemMetrics(78), GetSystemMetrics(79) }; }

  public static string Zagolovok(IntPtr h) { var sb = new StringBuilder(1024); GetWindowText(h, sb, 1024); return sb.ToString(); }
  static string iskomoe; static IntPtr najdeno;
  static bool Shag(IntPtr h, IntPtr l) {
    if (!IsWindowVisible(h)) return true;
    if (Zagolovok(h).IndexOf(iskomoe, StringComparison.OrdinalIgnoreCase) >= 0) { najdeno = h; return false; }
    return true;
  }
  public static IntPtr NajtiOkno(string chast) {
    iskomoe = chast; najdeno = IntPtr.Zero;
    EnumWindows(new EnumProc(Shag), IntPtr.Zero);
    return najdeno;
  }
  public static IntPtr Perednee() { return GetForegroundWindow(); }
  // client area in screen coordinates, clipped to the virtual screen: x, y, w, h
  public static int[] Ramka(IntPtr h) {
    RECT c; if (!GetClientRect(h, out c)) return null;
    POINT p = new POINT(); ClientToScreen(h, ref p);
    int[] e = Ekran();
    int x1 = Math.Max(p.X, e[0]), y1 = Math.Max(p.Y, e[1]);
    int x2 = Math.Min(p.X + c.R - c.L, e[0] + e[2]), y2 = Math.Min(p.Y + c.B - c.T, e[1] + e[3]);
    if (x2 - x1 < 8 || y2 - y1 < 8) return null;
    return new int[] { x1, y1, x2 - x1, y2 - y1 };
  }

  public static Bitmap Snimok(int x, int y, int w, int h) {
    var b = new Bitmap(w, h, PixelFormat.Format32bppArgb);
    using (var g = Graphics.FromImage(b)) g.CopyFromScreen(x, y, 0, 0, new Size(w, h), CopyPixelOperation.SourceCopy);
    return b;
  }
  // BGRA bytes with stride = 4 * width (what SoftwareBitmap.CreateCopyFromBuffer wants)
  public static byte[] Bgra(Bitmap b) {
    var d = b.LockBits(new Rectangle(0, 0, b.Width, b.Height), ImageLockMode.ReadOnly, PixelFormat.Format32bppArgb);
    try {
      int n = b.Width * 4; var a = new byte[n * b.Height];
      for (int y = 0; y < b.Height; y++) Marshal.Copy(new IntPtr(d.Scan0.ToInt64() + (long)y * d.Stride), a, y * n, n);
      for (int i = 3; i < a.Length; i += 4) a[i] = 255;
      return a;
    } finally { b.UnlockBits(d); }
  }
  static Bitmap IzBgra(byte[] a, int w, int h) {
    var b = new Bitmap(w, h, PixelFormat.Format32bppArgb);
    var d = b.LockBits(new Rectangle(0, 0, w, h), ImageLockMode.WriteOnly, PixelFormat.Format32bppArgb);
    try { for (int y = 0; y < h; y++) Marshal.Copy(a, y * w * 4, new IntPtr(d.Scan0.ToInt64() + (long)y * d.Stride), w * 4); }
    finally { b.UnlockBits(d); }
    return b;
  }
  public static Bitmap Vyrez(Bitmap src, int x, int y, int w, int h) {
    int x1 = Math.Max(0, x), y1 = Math.Max(0, y), x2 = Math.Min(src.Width, x + w), y2 = Math.Min(src.Height, y + h);
    if (x2 - x1 < 1 || y2 - y1 < 1) return null;
    var b = new Bitmap(x2 - x1, y2 - y1, PixelFormat.Format32bppArgb);
    using (var g = Graphics.FromImage(b)) g.DrawImage(src, new Rectangle(0, 0, x2 - x1, y2 - y1), new Rectangle(x1, y1, x2 - x1, y2 - y1), GraphicsUnit.Pixel);
    return b;
  }
  public static Bitmap Masshtab(Bitmap src, double k) {
    int w = Math.Max(1, (int)Math.Round(src.Width * k)), h = Math.Max(1, (int)Math.Round(src.Height * k));
    var b = new Bitmap(w, h, PixelFormat.Format32bppArgb);
    using (var g = Graphics.FromImage(b)) {
      g.InterpolationMode = InterpolationMode.HighQualityBicubic; g.PixelOffsetMode = PixelOffsetMode.HighQuality;
      g.DrawImage(src, new Rectangle(0, 0, w, h), 0, 0, src.Width, src.Height, GraphicsUnit.Pixel);
    }
    return b;
  }
  static float[] Yarkost(byte[] a, int n) {
    var l = new float[n];
    for (int i = 0; i < n; i++) l[i] = 0.114f * a[4 * i] + 0.587f * a[4 * i + 1] + 0.299f * a[4 * i + 2];
    return l;
  }
  // grey; mode 0 = plain grey, 1 = local contrast (value minus local mean, amplified),
  // always dark text on a light ground (inverted when the ground is dark)
  public static Bitmap Obrabotka(Bitmap src, int rezhim, int radius, double usilenie) {
    int w = src.Width, h = src.Height, n = w * h;
    byte[] a = Bgra(src);
    float[] l = Yarkost(a, n);
    float[] o = new float[n];
    if (rezhim == 1) {
      var s = new double[(w + 1) * (h + 1)];
      for (int y = 0; y < h; y++) { double r = 0; for (int x = 0; x < w; x++) { r += l[y * w + x]; s[(y + 1) * (w + 1) + x + 1] = s[y * (w + 1) + x + 1] + r; } }
      for (int y = 0; y < h; y++) {
        int y1 = Math.Max(0, y - radius), y2 = Math.Min(h, y + radius + 1);
        for (int x = 0; x < w; x++) {
          int x1 = Math.Max(0, x - radius), x2 = Math.Min(w, x + radius + 1);
          double sum = s[y2 * (w + 1) + x2] - s[y1 * (w + 1) + x2] - s[y2 * (w + 1) + x1] + s[y1 * (w + 1) + x1];
          double m = sum / ((x2 - x1) * (y2 - y1));
          o[y * w + x] = (float)(128 + (l[y * w + x] - m) * usilenie);
        }
      }
    } else { Array.Copy(l, o, n); }
    // ground polarity: the median decides
    var hist = new int[256];
    for (int i = 0; i < n; i++) { int v = (int)Math.Max(0, Math.Min(255, o[i])); hist[v]++; o[i] = v; }
    int acc = 0, med = 0; for (int v = 0; v < 256; v++) { acc += hist[v]; if (acc >= n / 2) { med = v; break; } }
    bool inv = rezhim == 0 ? med < 110 : false;
    for (int i = 0; i < n; i++) {
      byte v = (byte)(inv ? 255 - o[i] : o[i]);
      a[4 * i] = v; a[4 * i + 1] = v; a[4 * i + 2] = v; a[4 * i + 3] = 255;
    }
    return IzBgra(a, w, h);
  }
  // mean absolute luminance difference 0..255 of two crops (the second is scaled to the first)
  public static double Raznica(Bitmap a, Bitmap b) {
    Bitmap bb = (a.Width == b.Width && a.Height == b.Height) ? b : Masshtab(b, (double)a.Width / b.Width);
    int w = Math.Min(a.Width, bb.Width), h = Math.Min(a.Height, bb.Height);
    var aa = Bgra(a); var cc = Bgra(bb);
    double s = 0;
    for (int y = 0; y < h; y++) for (int x = 0; x < w; x++) {
      int i = 4 * (y * a.Width + x), j = 4 * (y * bb.Width + x);
      double la = 0.114 * aa[i] + 0.587 * aa[i + 1] + 0.299 * aa[i + 2];
      double lb = 0.114 * cc[j] + 0.587 * cc[j + 1] + 0.299 * cc[j + 2];
      s += Math.Abs(la - lb);
    }
    return s / Math.Max(1, w * h);
  }
  // words into phrases: same line (vertical overlap) and a gap below k * height
  public static int[] Gruppy(double[] x, double[] y, double[] w, double[] h, double k) {
    int n = x.Length; var p = new int[n];
    for (int i = 0; i < n; i++) p[i] = i;
    Func<int, int> kor = null;
    kor = delegate(int i) { while (p[i] != i) { p[i] = p[p[i]]; i = p[i]; } return i; };
    for (int i = 0; i < n; i++) for (int j = i + 1; j < n; j++) {
      double ov = Math.Min(y[i] + h[i], y[j] + h[j]) - Math.Max(y[i], y[j]);
      double mh = Math.Min(h[i], h[j]), bh = Math.Max(h[i], h[j]);
      if (ov < 0.45 * mh) continue;
      if (bh > 2.2 * mh) continue;
      double gap = Math.Max(x[i], x[j]) - Math.Min(x[i] + w[i], x[j] + w[j]);
      if (gap > k * bh) continue;
      int a = kor(i), b = kor(j); if (a != b) p[a] = b;
    }
    var r = new int[n]; for (int i = 0; i < n; i++) r[i] = kor(i);
    return r;
  }
  public static void Kursor(int x, int y) { SetCursorPos(x, y); }
  public static uint Klik(int x, int y) {
    SetCursorPos(x, y);
    System.Threading.Thread.Sleep(15);
    var a = new MIN[2];
    a[0].type = 0; a[0].mi.fl = 0x0002;
    a[1].type = 0; a[1].mi.fl = 0x0004;
    return SendInput(2, a, Marshal.SizeOf(typeof(MIN)));
  }
}
'@
}

if (-not (Get-Command Write-RukiLog -ErrorAction SilentlyContinue)) {
  function Write-RukiLog([string]$s) {
    if ($env:RUKI_LOG) { try { Add-Content -Path $env:RUKI_LOG -Value ("{0:HH:mm:ss.fff} {1}" -f (Get-Date), $s) -Encoding UTF8 } catch {} }
  }
}

$script:OcrSw = [Diagnostics.Stopwatch]::StartNew()
function Get-OcrMs { return [int64]$script:OcrSw.ElapsedMilliseconds }

# ---------- Windows OCR through WinRT ----------
$script:WinOcr = $null      # $null = not tried, $false = unavailable, hashtable = ready
function Initialize-WinOcr {
  if ($null -ne $script:WinOcr) { return [bool]$script:WinOcr }
  try {
    Add-Type -AssemblyName System.Runtime.WindowsRuntime
    foreach ($tip in 'Windows.Media.Ocr.OcrEngine', 'Windows.Media.Ocr.OcrResult', 'Windows.Globalization.Language',
                     'Windows.Graphics.Imaging.SoftwareBitmap', 'Windows.Graphics.Imaging.BitmapDecoder',
                     'Windows.Graphics.Imaging.BitmapPixelFormat', 'Windows.Storage.Streams.IRandomAccessStream') {
      $zagr = $null
      foreach ($sb in 'Windows.Foundation', 'Windows.Media', 'Windows.Globalization', 'Windows.Graphics', 'Windows.Storage.Streams', 'Windows.Storage') {
        try { $zagr = [Type]::GetType("$tip, $sb, ContentType=WindowsRuntime") } catch {}
        if ($zagr) { break }
      }
      if (-not $zagr) { throw "WinRT tip ne zagruzhen: $tip" }
    }
    $asTask = [System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object {
      $_.Name -eq 'AsTask' -and $_.GetParameters().Count -eq 1 -and $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncOperation`1' } | Select-Object -First 1
    $yazyki = @([Windows.Media.Ocr.OcrEngine]::AvailableRecognizerLanguages | ForEach-Object { $_.LanguageTag })
    $script:WinOcr = @{ AsTask = $asTask; Yazyki = $yazyki; Dvizhki = @{}; MaxRazmer = [int][Windows.Media.Ocr.OcrEngine]::MaxImageDimension }
    Write-RukiLog ("winocr: yazyki [{0}] max {1}" -f ($yazyki -join ','), $script:WinOcr.MaxRazmer)
    return $true
  } catch {
    Write-RukiLog "winocr nedostupen: $($_.Exception.Message)"
    $script:WinOcr = $false
    return $false
  }
}
function Wait-WinRt($operaciya, [type]$tipRezultata) {
  $zadacha = $script:WinOcr.AsTask.MakeGenericMethod($tipRezultata).Invoke($null, @($operaciya))
  $null = $zadacha.Wait(-1)
  return $zadacha.Result
}
# engine for a language prefix ('ru', 'en'); $null when not installed
function Get-WinOcrDvizhok([string]$pref) {
  if (-not (Initialize-WinOcr)) { return $null }
  if ($script:WinOcr.Dvizhki.ContainsKey($pref)) { return $script:WinOcr.Dvizhki[$pref] }
  $d = $null
  $tag = $script:WinOcr.Yazyki | Where-Object { $_ -like "$pref*" } | Select-Object -First 1
  if ($tag) {
    try { $d = [Windows.Media.Ocr.OcrEngine]::TryCreateFromLanguage((New-Object Windows.Globalization.Language $tag)) } catch { $d = $null }
  }
  $script:WinOcr.Dvizhki[$pref] = $d
  return $d
}
function ConvertTo-SoftwareBitmap([System.Drawing.Bitmap]$bmp) {
  try {
    $bajty = [RukiObraz]::Bgra($bmp)
    $buf = [System.Runtime.InteropServices.WindowsRuntime.WindowsRuntimeBufferExtensions]::AsBuffer($bajty)
    return [Windows.Graphics.Imaging.SoftwareBitmap]::CreateCopyFromBuffer($buf, [Windows.Graphics.Imaging.BitmapPixelFormat]::Bgra8, $bmp.Width, $bmp.Height)
  } catch {
    Write-RukiLog "softwarebitmap iz bufera: $($_.Exception.Message); probuyu cherez png"
    $ms = New-Object IO.MemoryStream
    $bmp.Save($ms, [System.Drawing.Imaging.ImageFormat]::Png)
    $null = $ms.Seek(0, 'Begin')
    $ras = [System.IO.WindowsRuntimeStreamExtensions]::AsRandomAccessStream($ms)
    $dek = Wait-WinRt ([Windows.Graphics.Imaging.BitmapDecoder]::CreateAsync($ras)) ([Windows.Graphics.Imaging.BitmapDecoder])
    return Wait-WinRt ($dek.GetSoftwareBitmapAsync()) ([Windows.Graphics.Imaging.SoftwareBitmap])
  }
}
# words of one image (already within the engine size limit): @{ t; x; y; w; h } in image pixels
function Read-WinOcrOdin($dvizhok, [System.Drawing.Bitmap]$bmp) {
  $sb = ConvertTo-SoftwareBitmap $bmp
  $res = Wait-WinRt ($dvizhok.RecognizeAsync($sb)) ([Windows.Media.Ocr.OcrResult])
  $slova = New-Object System.Collections.ArrayList
  foreach ($ln in $res.Lines) {
    foreach ($sl in $ln.Words) {
      $r = $sl.BoundingRect
      $null = $slova.Add(@{ t = [string]$sl.Text; x = [double]$r.X; y = [double]$r.Y; w = [double]$r.Width; h = [double]$r.Height })
    }
  }
  try { $sb.Dispose() } catch {}
  return ,$slova
}

# ---------- Tesseract ----------
$script:Tess = $null
function Initialize-Tess {
  if ($null -ne $script:Tess) { return [bool]$script:Tess }
  $exe = $null
  $c = Get-Command tesseract -ErrorAction SilentlyContinue
  if ($c) { $exe = $c.Source }
  if (-not $exe) {
    foreach ($p in @("$env:ProgramFiles\Tesseract-OCR\tesseract.exe", "${env:ProgramFiles(x86)}\Tesseract-OCR\tesseract.exe")) { if ($p -and (Test-Path $p)) { $exe = $p; break } }
  }
  if (-not $exe) { $script:Tess = $false; Write-RukiLog 'tesseract ne ustanovlen'; return $false }
  $yazyki = @()
  try { $yazyki = @(& $exe --list-langs 2>$null | Select-Object -Skip 1 | ForEach-Object { $_.Trim() } | Where-Object { $_ }) } catch {}
  $script:Tess = @{ Exe = $exe; Yazyki = $yazyki }
  Write-RukiLog ("tesseract: yazyki [{0}]" -f ($yazyki -join ','))
  return $true
}
function Read-Tess([string]$yazyk, [System.Drawing.Bitmap]$bmp) {
  $tmp = if ($env:RUNNER_TEMP) { $env:RUNNER_TEMP } else { [IO.Path]::GetTempPath() }
  $baza = Join-Path $tmp ("ruki-ocr-{0}" -f [guid]::NewGuid().ToString('N'))
  $png = "$baza.png"
  $bmp.Save($png, [System.Drawing.Imaging.ImageFormat]::Png)
  $slova = New-Object System.Collections.ArrayList
  try {
    # output into a file: console code pages would spoil Cyrillic
    $null = & $script:Tess.Exe $png $baza -l $yazyk --psm 11 tsv 2>&1
    $tsv = if (Test-Path "$baza.tsv") { Get-Content -Encoding UTF8 "$baza.tsv" } else { @() }
    foreach ($str in $tsv) {
      $c = $str -split "`t"
      if ($c.Count -lt 12 -or $c[0] -ne '5') { continue }
      $t = $c[11].Trim()
      if (-not $t -or [double]$c[10] -lt 10) { continue }
      $null = $slova.Add(@{ t = $t; x = [double]$c[6]; y = [double]$c[7]; w = [double]$c[8]; h = [double]$c[9] })
    }
  } finally { Remove-Item $png, "$baza.tsv" -ErrorAction SilentlyContinue }
  return ,$slova
}

# ---------- passes ----------
# a pass = engine + preprocessing. Returns words in the coordinates of the source bitmap.
function Read-Prohod($prohod, [System.Drawing.Bitmap]$ishod) {
  $k = [double]$prohod.k
  # Tesseract slows down sharply on big images: keep the long side within 3000 px
  if ($prohod.dvizhok -eq 'tess') { $k = [Math]::Min($k, 3000.0 / [Math]::Max($ishod.Width, $ishod.Height)); if ($k -lt 1) { $k = 1 } }
  $img = if ($k -ne 1) { [RukiObraz]::Masshtab($ishod, $k) } else { $ishod }
  if ($prohod.obr -eq 'seryj') { $n = [RukiObraz]::Obrabotka($img, 0, 0, 1); if ($img -ne $ishod) { $img.Dispose() }; $img = $n }
  elseif ($prohod.obr -eq 'kontrast') { $n = [RukiObraz]::Obrabotka($img, 1, [int](12 * $k), 4.0); if ($img -ne $ishod) { $img.Dispose() }; $img = $n }
  $vse = New-Object System.Collections.ArrayList
  try {
    if ($prohod.dvizhok -eq 'win') {
      $d = Get-WinOcrDvizhok $prohod.yazyk
      $max = [Math]::Max(400, $script:WinOcr.MaxRazmer - 8)
      $nahl = 120
      $xs = @(0); $ys = @(0)
      if ($img.Width -gt $max) { $xs = @(); $x = 0; while ($true) { $xs += $x; if ($x + $max -ge $img.Width) { break }; $x += $max - $nahl } }
      if ($img.Height -gt $max) { $ys = @(); $y = 0; while ($true) { $ys += $y; if ($y + $max -ge $img.Height) { break }; $y += $max - $nahl } }
      foreach ($ty in $ys) { foreach ($tx in $xs) {
        $plitka = if ($xs.Count -eq 1 -and $ys.Count -eq 1) { $img } else { [RukiObraz]::Vyrez($img, $tx, $ty, $max, $max) }
        foreach ($s in (Read-WinOcrOdin $d $plitka)) {
          $s.x += $tx; $s.y += $ty
          # words cut by a tile edge are dropped: the overlapping tile has them whole
          $kraj = ($xs.Count -gt 1 -and (($s.x -le $tx + 2 -and $tx -gt 0) -or ($s.x + $s.w -ge $tx + $max - 2 -and $tx + $max -lt $img.Width))) -or
                  ($ys.Count -gt 1 -and (($s.y -le $ty + 2 -and $ty -gt 0) -or ($s.y + $s.h -ge $ty + $max - 2 -and $ty + $max -lt $img.Height)))
          if (-not $kraj) { $null = $vse.Add($s) }
        }
        if ($plitka -ne $img) { $plitka.Dispose() }
      } }
    } else {
      foreach ($s in (Read-Tess $prohod.yazyk $img)) { $null = $vse.Add($s) }
    }
  } finally { if ($img -ne $ishod) { $img.Dispose() } }
  # back to source pixels; duplicates from tile overlap removed
  $itog = New-Object System.Collections.ArrayList
  foreach ($s in $vse) {
    $s.x /= $k; $s.y /= $k; $s.w /= $k; $s.h /= $k
    $dubl = $false
    foreach ($o in $itog) {
      if ($o.t -ceq $s.t -and [Math]::Abs($o.x - $s.x) -lt 4 -and [Math]::Abs($o.y - $s.y) -lt 4) { $dubl = $true; break }
    }
    if (-not $dubl) { $null = $itog.Add($s) }
  }
  return ,$itog
}

# ---------- text matching ----------
$script:CyrIzLat = @{}
$script:LatIzCyr = @{}
foreach ($p in @('a0430', 'b0432', 'c0441', 'e0435', 'h043d', 'k043a', 'm043c', 'o043e', 'p0440', 't0442', 'x0445', 'y0443', 'n043f', 'u0438', 'r0433')) {
  $script:CyrIzLat[[string]$p[0]] = [string][char][Convert]::ToInt32($p.Substring(1), 16)
}
foreach ($p in @('0430a', '0432b', '0441c', '0435e', '043dh', '043ak', '043cm', '043eo', '0440p', '0442t', '0445x', '0443y', '043fn', '0438u', '0433r', '044cb', '0456i')) {
  $script:LatIzCyr[[string][char][Convert]::ToInt32($p.Substring(0, 4), 16)] = $p.Substring(4)
}
$script:YO = [string][char]0x0451; $script:YE = [string][char]0x0435
$script:IK = [string][char]0x0439; $script:II = [string][char]0x0438

function Get-Pismo([string]$s) {
  $cyr = 0; $lat = 0
  foreach ($ch in $s.ToCharArray()) { if ($ch -ge [char]0x0400 -and $ch -le [char]0x04FF) { $cyr++ } elseif ($ch -match '[A-Za-z]') { $lat++ } }
  if ($cyr -ge $lat -and $cyr -gt 0) { return 'cyr' }
  return 'lat'
}
# skeleton for comparison: lower case, one script (homoglyphs folded to the target's script),
# a few OCR confusions folded (e/yo, i/short i, l/I/1/|), punctuation and spaces normalised
function ConvertTo-Skelet([string]$s, [string]$pismo) {
  if ($null -eq $s) { return '' }
  $s = $s.Normalize([Text.NormalizationForm]::FormC).ToLowerInvariant()
  $sb = New-Object Text.StringBuilder
  foreach ($ch in $s.ToCharArray()) {
    $c = [string]$ch
    if ($pismo -eq 'cyr' -and $script:CyrIzLat.ContainsKey($c)) { $c = $script:CyrIzLat[$c] }
    elseif ($pismo -eq 'lat' -and $script:LatIzCyr.ContainsKey($c)) { $c = $script:LatIzCyr[$c] }
    if ($c -eq $script:YO) { $c = $script:YE }
    elseif ($c -eq $script:IK) { $c = $script:II }
    elseif ($pismo -eq 'lat' -and ($c -eq 'i' -or $c -eq '1' -or $c -eq '|' -or $c -eq '!')) { $c = 'l' }
    elseif ($c -eq '0' -and $pismo -eq 'lat') { $c = 'o' }
    if ($c -match '[\p{L}\p{N}]') { $null = $sb.Append($c) } else { $null = $sb.Append(' ') }
  }
  return (($sb.ToString() -replace '\s+', ' ').Trim())
}

# words -> phrases @{ t; x; y; w; h } (gap between words of one phrase below 0.9 of the height)
function Get-Frazy($slova) {
  $n = $slova.Count
  $frazy = New-Object System.Collections.ArrayList
  if ($n -eq 0) { return ,$frazy }
  $xs = New-Object double[] $n; $ys = New-Object double[] $n; $ws = New-Object double[] $n; $hs = New-Object double[] $n
  for ($i = 0; $i -lt $n; $i++) { $xs[$i] = $slova[$i].x; $ys[$i] = $slova[$i].y; $ws[$i] = $slova[$i].w; $hs[$i] = [Math]::Max(1, $slova[$i].h) }
  $g = [RukiObraz]::Gruppy($xs, $ys, $ws, $hs, 0.9)
  $po = @{}
  for ($i = 0; $i -lt $n; $i++) { $k = [string]$g[$i]; if (-not $po.ContainsKey($k)) { $po[$k] = New-Object System.Collections.ArrayList }; $null = $po[$k].Add($slova[$i]) }
  foreach ($k in $po.Keys) {
    $sp = @($po[$k] | Sort-Object { $_.x })
    $x1 = ($sp | ForEach-Object { $_.x } | Measure-Object -Minimum).Minimum
    $y1 = ($sp | ForEach-Object { $_.y } | Measure-Object -Minimum).Minimum
    $x2 = ($sp | ForEach-Object { $_.x + $_.w } | Measure-Object -Maximum).Maximum
    $y2 = ($sp | ForEach-Object { $_.y + $_.h } | Measure-Object -Maximum).Maximum
    $null = $frazy.Add(@{ t = (($sp | ForEach-Object { $_.t }) -join ' '); x = $x1; y = $y1; w = $x2 - $x1; h = $y2 - $y1 })
  }
  return ,$frazy
}

function Find-Sovpadeniya($frazy, [string]$cel, [string]$pismo) {
  $sk = ConvertTo-Skelet $cel $pismo
  return @($frazy | Where-Object { (ConvertTo-Skelet $_.t $pismo) -ceq $sk })
}

# passes for the target's script; Windows OCR first, Tesseract last
function Get-Prohody([string]$pismo) {
  $p = @()
  $win = if ($pismo -eq 'cyr') { 'ru' } else { 'en' }
  if (Get-WinOcrDvizhok $win) {
    $p += @{ dvizhok = 'win'; yazyk = $win; k = 1; obr = 'net' }
    $p += @{ dvizhok = 'win'; yazyk = $win; k = 2; obr = 'seryj' }
    $p += @{ dvizhok = 'win'; yazyk = $win; k = 2.5; obr = 'kontrast' }
  }
  if (Initialize-Tess) {
    $tl = if ($pismo -eq 'cyr') { 'rus' } else { 'eng' }
    if ($script:Tess.Yazyki -contains $tl) {
      $l = if ($script:Tess.Yazyki -contains 'eng' -and $tl -ne 'eng') { "$tl+eng" } else { $tl }
      if ($p.Count -eq 0) { $p += @{ dvizhok = 'tess'; yazyk = $l; k = 1.5; obr = 'seryj' } }
      $p += @{ dvizhok = 'tess'; yazyk = $l; k = 2; obr = 'kontrast' }
    }
  }
  return $p
}
function Get-ImyaProhoda($p) { return ('{0}-{1}-x{2}-{3}' -f $p.dvizhok, $p.yazyk, $p.k, $p.obr) }

# a candidate is re-read on a crop around it with a stronger preprocessing; rejected when
# that read shows a different (e.g. longer) phrase in its place
function Confirm-Kandidat($kand, [System.Drawing.Bitmap]$snimok, $prohod, [string]$cel, [string]$pismo) {
  $h = [Math]::Max(8, $kand.h)
  $px = [int](3 * $h); $py = [int](1.2 * $h)
  $vy = [RukiObraz]::Vyrez($snimok, [int]($kand.x - $px), [int]($kand.y - $py), [int]($kand.w + 2 * $px), [int]($kand.h + 2 * $py))
  if (-not $vy) { return 'slabo' }
  $ox = [Math]::Max(0, [int]($kand.x - $px)); $oy = [Math]::Max(0, [int]($kand.y - $py))
  try {
    $k = if ($h -lt 14) { 3 } elseif ($h -lt 24) { 2 } else { 1.5 }
    $pp = @{ dvizhok = $prohod.dvizhok; yazyk = $prohod.yazyk; k = $k; obr = $(if ($prohod.obr -eq 'kontrast') { 'seryj' } else { 'kontrast' }) }
    $fr = Get-Frazy (Read-Prohod $pp $vy)
  } finally { $vy.Dispose() }
  $cx = $kand.x + $kand.w / 2 - $ox; $cy = $kand.y + $kand.h / 2 - $oy
  $tam = @($fr | Where-Object { $cx -ge $_.x - 2 -and $cx -le $_.x + $_.w + 2 -and $cy -ge $_.y - 2 -and $cy -le $_.y + $_.h + 2 })
  if ($tam.Count -eq 0) { return 'slabo' }
  if (@(Find-Sovpadeniya $tam $cel $pismo).Count -gt 0) { return 'da' }
  # only a longer phrase that contains the target rejects it ("Save as", "Saved");
  # a garbled re-read is no evidence against the first one
  $sk = ConvertTo-Skelet $cel $pismo
  $dlinnee = @($tam | Where-Object { $t = ConvertTo-Skelet $_.t $pismo; $t.Length -gt $sk.Length -and $t.Contains($sk) })
  if ($dlinnee.Count -gt 0) {
    Write-RukiLog ("kandidat otvergnut: na meste vidno [{0}]" -f (($dlinnee | ForEach-Object { $_.t }) -join ' | '))
    return 'net'
  }
  return 'slabo'
}

function Get-OblastOkna([IntPtr]$Okno) {
  if ($Okno -ne [IntPtr]::Zero) { $r = [RukiObraz]::Ramka($Okno); if ($r) { return $r } }
  return [RukiObraz]::Ekran()
}

# find a phrase. Each pass takes a fresh screenshot (animated text gets several chances).
# returns @{ Status; Ramka = @(x, y, w, h) screen px; T = capture time ms; Prohod; Prohody; Ms }
function Find-TekstNaEkrane {
  param([string]$Tekst, [IntPtr]$Okno = [IntPtr]::Zero, [int[]]$Oblast = $null)
  $start = Get-OcrMs
  $pismo = Get-Pismo $Tekst
  $prohody = @(Get-Prohody $pismo)
  $zhurnal = @()
  if ($prohody.Count -eq 0) { return @{ Status = 'net-dvizhka'; Prohody = @(); Ms = 0 } }
  foreach ($p in $prohody) {
    $ob = if ($Oblast) { $Oblast } else { Get-OblastOkna $Okno }
    $t0 = Get-OcrMs
    $sn = [RukiObraz]::Snimok($ob[0], $ob[1], $ob[2], $ob[3])
    try {
      $slova = Read-Prohod $p $sn
      $fr = Get-Frazy $slova
      $sov = @(Find-Sovpadeniya $fr $Tekst $pismo)
      $ok = @()
      foreach ($s in $sov) {
        $c = Confirm-Kandidat $s $sn $p $Tekst $pismo
        if ($c -ne 'net') { $ok += @{ f = $s; c = $c } }
      }
      $zap = [ordered]@{ prohod = (Get-ImyaProhoda $p); ms = (Get-OcrMs) - $t0; slov = $slova.Count; fraz = $fr.Count; sovpalo = $sov.Count; podtverzhdeno = $ok.Count }
      $zhurnal += $zap
      Write-RukiLog ("prohod {0}: {1} ms, slov {2}, fraz {3}, sovpalo {4}, podtverzhdeno {5}" -f $zap.prohod, $zap.ms, $zap.slov, $zap.fraz, $zap.sovpalo, $zap.podtverzhdeno)
      if ($ok.Count -eq 0 -and $fr.Count -gt 0) {
        Write-RukiLog ("  frazy: {0}" -f ((@($fr | Select-Object -First 25 | ForEach-Object { $_.t })) -join ' | '))
      }
      if ($ok.Count -gt 1) {
        # one and the same place read twice is not ambiguity
        $raznye = @($ok | ForEach-Object { '{0}:{1}' -f [int](($_.f.x + $_.f.w / 2) / 20), [int](($_.f.y + $_.f.h / 2) / 20) } | Select-Object -Unique)
        if ($raznye.Count -gt 1) {
          return @{ Status = 'neodnoznachno'; Kolichestvo = $raznye.Count; Prohody = $zhurnal; Ms = (Get-OcrMs) - $start; Prohod = $p }
        }
      }
      if ($ok.Count -ge 1) {
        $f = $ok[0].f
        return @{ Status = 'nashel'; Ramka = @(($ob[0] + $f.x), ($ob[1] + $f.y), $f.w, $f.h); Tekst = $f.t; T = $t0; Prohod = $p
                  Uverennost = $ok[0].c; Prohody = $zhurnal; Ms = (Get-OcrMs) - $start }
      }
    } finally { $sn.Dispose() }
  }
  return @{ Status = 'ne-nashel'; Prohody = $zhurnal; Ms = (Get-OcrMs) - $start }
}

# re-read around a known place (smaller area, so faster): the same phrase nearest to the old centre
function Read-Ryadom($ramka, $prohod, [string]$Tekst, [int]$zapasX, [int]$zapasY) {
  $ekr = [RukiObraz]::Ekran()
  $x = [Math]::Max($ekr[0], [int]($ramka[0] - $zapasX)); $y = [Math]::Max($ekr[1], [int]($ramka[1] - $zapasY))
  $x2 = [Math]::Min($ekr[0] + $ekr[2], [int]($ramka[0] + $ramka[2] + $zapasX)); $y2 = [Math]::Min($ekr[1] + $ekr[3], [int]($ramka[1] + $ramka[3] + $zapasY))
  $t0 = Get-OcrMs
  $sn = [RukiObraz]::Snimok($x, $y, $x2 - $x, $y2 - $y)
  try {
    $pismo = Get-Pismo $Tekst
    $pp = @{ dvizhok = $prohod.dvizhok; yazyk = $prohod.yazyk; k = [Math]::Max(2, [double]$prohod.k); obr = $prohod.obr }
    $sov = @(Find-Sovpadeniya (Get-Frazy (Read-Prohod $pp $sn)) $Tekst $pismo)
    if ($sov.Count -eq 0) { return $null }
    $cx = $ramka[0] + $ramka[2] / 2 - $x; $cy = $ramka[1] + $ramka[3] / 2 - $y
    $f = $sov | Sort-Object { [Math]::Abs($_.x + $_.w / 2 - $cx) + [Math]::Abs($_.y + $_.h / 2 - $cy) } | Select-Object -First 1
    $vyr = [RukiObraz]::Vyrez($sn, [int]$f.x - 4, [int]$f.y - 4, [int]$f.w + 8, [int]$f.h + 8)
    return @{ Ramka = @(($x + $f.x), ($y + $f.y), $f.w, $f.h); T = $t0; Vyrez = $vyr; Ms = (Get-OcrMs) - $t0 }
  } finally { $sn.Dispose() }
}

function Get-Centr($r) { return @(($r[0] + $r[2] / 2.0), ($r[1] + $r[3] / 2.0)) }

# find, read again (confirms and measures motion), click the predicted centre, read again
function Invoke-KlikPoTekstu {
  param([string]$Tekst, [IntPtr]$Okno = [IntPtr]::Zero, [switch]$TolkoNajti, [int]$Popytok = 2)
  $vsegoSw = [Diagnostics.Stopwatch]::StartNew()
  $rez = [ordered]@{ tekst = $Tekst; status = ''; poisk_ms = 0; prohody = @() }
  $f = $null
  for ($p = 1; $p -le $Popytok; $p++) {
    $f = Find-TekstNaEkrane -Tekst $Tekst -Okno $Okno
    $rez.prohody += $f.Prohody
    $rez.poisk_ms += [int]$f.Ms
    if ($f.Status -ne 'nashel') { break }
    # second read: same phrase near the same place
    $zx = [int][Math]::Max(3 * $f.Ramka[2], 260); $zy = [int][Math]::Max(2 * $f.Ramka[3], 40)
    $v2 = $null
    for ($i = 0; $i -lt 4 -and -not $v2; $i++) {
      $v2 = Read-Ryadom $f.Ramka $f.Prohod $Tekst $zx $zy
      if (-not $v2) { Start-Sleep -Milliseconds 180 }
    }
    if ($v2) { break }
    Write-RukiLog "vtoroe chtenie ne nashlo, popytka $p"
    $f.Status = 'poteryal'
  }
  $rez.status = $f.Status
  $rez.poisk_ms_posl = [int]$f.Ms
  if ($f.Status -ne 'nashel') { $rez.vsego_ms = $vsegoSw.ElapsedMilliseconds; return $rez }
  $rez.prohod = Get-ImyaProhoda $f.Prohod
  $rez.uverennost = $f.Uverennost
  $rez.prochitano = $f.Tekst
  $rez.ramka = @($v2.Ramka | ForEach-Object { [int]$_ })
  $rez.vtoroe_ms = $v2.Ms
  # motion: centre shift between the two captures
  $c1 = Get-Centr $f.Ramka; $c2 = Get-Centr $v2.Ramka
  $dt = [Math]::Max(1, $v2.T - $f.T) / 1000.0
  $vx = ($c2[0] - $c1[0]) / $dt; $vy = ($c2[1] - $c1[1]) / $dt
  if ([Math]::Sqrt($vx * $vx + $vy * $vy) -lt 25) { $vx = 0; $vy = 0 }
  $rez.skorost = @([int]$vx, [int]$vy)
  if ($TolkoNajti) { $rez.status = 'nashel'; $rez.vsego_ms = $vsegoSw.ElapsedMilliseconds; if ($v2.Vyrez) { $v2.Vyrez.Dispose() }; return $rez }
  $tk = Get-OcrMs
  $lead = ($tk - $v2.T + 20) / 1000.0
  $kx = [int][Math]::Round($c2[0] + $vx * $lead); $ky = [int][Math]::Round($c2[1] + $vy * $lead)
  $null = [RukiObraz]::Klik($kx, $ky)
  $rez.klik = @($kx, $ky)
  $rez.status = 'klik'
  # read after the action: the same place (moved on by the measured speed) compared with before
  Start-Sleep -Milliseconds 350
  try {
    $dt2 = ((Get-OcrMs) - $v2.T) / 1000.0
    $r3 = @(($v2.Ramka[0] + $vx * $dt2 - 4), ($v2.Ramka[1] + $vy * $dt2 - 4), ($v2.Ramka[2] + 8), ($v2.Ramka[3] + 8))
    $posle = [RukiObraz]::Snimok([int]$r3[0], [int]$r3[1], [int]$r3[2], [int]$r3[3])
    $rez.izmenenie = if ($v2.Vyrez) { [Math]::Round([RukiObraz]::Raznica($v2.Vyrez, $posle), 1) } else { $null }
    $posle.Dispose()
    $v3 = Read-Ryadom @([int]$r3[0], [int]$r3[1], [int]$r3[2], [int]$r3[3]) $f.Prohod $Tekst 40 16
    $rez.posle_vidno = [bool]$v3
    if ($v3 -and $v3.Vyrez) { $v3.Vyrez.Dispose() }
    $rez.proverka = if ($rez.izmenenie -ge 12) { 'izmenilos' } elseif ($v3) { 'bez-izmenenij' } else { 'propalo' }
  } catch { $rez.proverka = "sboj: $($_.Exception.Message)" }
  if ($v2.Vyrez) { $v2.Vyrez.Dispose() }
  $rez.vsego_ms = $vsegoSw.ElapsedMilliseconds
  return $rez
}
