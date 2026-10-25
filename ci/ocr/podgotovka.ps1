# Prepares a CI runner for recognition training: screen 1920x1080, Windows OCR language
# for Russian, Tesseract with rus+eng. Never fails: what worked goes into podgotovka.json.
param([string]$Vyhod = 'podgotovka.json', [switch]$BezTess)
$ErrorActionPreference = 'Continue'
$itog = [ordered]@{}
$sw = [Diagnostics.Stopwatch]::StartNew()

# 1. screen resolution
if (-not ('RukiDisplej' -as [type])) {
Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class RukiDisplej {
  [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
  public struct DEVMODE {
    [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string dmDeviceName;
    public short dmSpecVersion; public short dmDriverVersion; public short dmSize; public short dmDriverExtra; public int dmFields;
    public int dmPositionX; public int dmPositionY; public int dmDisplayOrientation; public int dmDisplayFixedOutput;
    public short dmColor; public short dmDuplex; public short dmYResolution; public short dmTTOption; public short dmCollate;
    [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string dmFormName;
    public short dmLogPixels; public int dmBitsPerPel; public int dmPelsWidth; public int dmPelsHeight;
    public int dmDisplayFlags; public int dmDisplayFrequency; public int dmICMMethod; public int dmICMIntent; public int dmMediaType;
    public int dmDitherType; public int dmReserved1; public int dmReserved2; public int dmPanningWidth; public int dmPanningHeight;
  }
  [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern bool EnumDisplaySettings(string d, int m, ref DEVMODE dm);
  [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern int ChangeDisplaySettings(ref DEVMODE dm, int f);
  public static string Sejchas() { var d = new DEVMODE(); d.dmSize = (short)Marshal.SizeOf(typeof(DEVMODE)); EnumDisplaySettings(null, -1, ref d); return d.dmPelsWidth + "x" + d.dmPelsHeight; }
  public static int Postavit(int w, int h) {
    var d = new DEVMODE(); d.dmSize = (short)Marshal.SizeOf(typeof(DEVMODE));
    if (!EnumDisplaySettings(null, -1, ref d)) return -100;
    d.dmPelsWidth = w; d.dmPelsHeight = h; d.dmFields = 0x80000 | 0x100000;
    return ChangeDisplaySettings(ref d, 0);
  }
}
'@
}
$itog.ekran_bylo = [RukiDisplej]::Sejchas()
$kod = [RukiDisplej]::Postavit(1920, 1080)
if ($kod -ne 0 -and (Get-Command Set-DisplayResolution -ErrorAction SilentlyContinue)) {
  try { Set-DisplayResolution -Width 1920 -Height 1080 -Force -ErrorAction Stop; $kod = 'cmdlet' } catch { $kod = "$kod; cmdlet: $($_.Exception.Message)" }
}
Start-Sleep -Milliseconds 800
$itog.ekran_kod = [string]$kod
$itog.ekran = [RukiDisplej]::Sejchas()
Write-Host "ekran: $($itog.ekran_bylo) -> $($itog.ekran) (kod $kod)"

# 2. Tesseract in the background (choco + rus data)
$tessJob = $null
if (-not $BezTess) {
  $tessJob = Start-Job -ScriptBlock {
    $t = [Diagnostics.Stopwatch]::StartNew()
    $o = @()
    $o += (& choco install tesseract -y --no-progress 2>&1 | Select-Object -Last 3 | Out-String)
    $dir = "$env:ProgramFiles\Tesseract-OCR\tessdata"
    if (Test-Path $dir) {
      foreach ($l in 'rus', 'eng') {
        if (-not (Test-Path "$dir\$l.traineddata")) {
          try { Invoke-WebRequest -UseBasicParsing "https://github.com/tesseract-ocr/tessdata_fast/raw/main/$l.traineddata" -OutFile "$dir\$l.traineddata"; $o += "skachan $l" }
          catch { $o += "$l ne skachan: $($_.Exception.Message)" }
        }
      }
    } else { $o += 'net papki tessdata' }
    [pscustomobject]@{ sekund = [int]$t.Elapsed.TotalSeconds; vyvod = ($o -join ' | ') }
  }
}

# 3. Windows OCR language for Russian
function Get-OcrYazyki {
  $kod = @'
try {
  Add-Type -AssemblyName System.Runtime.WindowsRuntime
  $t = [Type]::GetType('Windows.Media.Ocr.OcrEngine, Windows.Foundation, ContentType=WindowsRuntime')
  ($t::AvailableRecognizerLanguages | ForEach-Object { $_.LanguageTag }) -join ','
} catch { 'oshibka: ' + $_.Exception.Message }
'@
  return (& powershell.exe -NoProfile -Command $kod 2>&1 | Out-String).Trim()
}
$itog.winocr_bylo = Get-OcrYazyki
Write-Host "winocr bylo: $($itog.winocr_bylo)"
if ($itog.winocr_bylo -notmatch 'ru') {
  $t = [Diagnostics.Stopwatch]::StartNew()
  try {
    $cap = Get-WindowsCapability -Online -ErrorAction Stop | Where-Object { $_.Name -like 'Language.OCR*ru-RU*' } | Select-Object -First 1
    $itog.winocr_paket = if ($cap) { "$($cap.Name) $($cap.State)" } else { 'net-v-spiske' }
    $imya = if ($cap) { $cap.Name } else { ('Language.OCR~~~ru-RU~0.0.1' + '.0') }
    $null = Add-WindowsCapability -Online -Name $imya -ErrorAction Stop
    $itog.winocr_ustanovka = 'ok'
  } catch { $itog.winocr_ustanovka = "oshibka: $($_.Exception.Message)" }
  $itog.winocr_ustanovka_sek = [int]$t.Elapsed.TotalSeconds
  $itog.winocr = Get-OcrYazyki
} else { $itog.winocr = $itog.winocr_bylo }
Write-Host "winocr: $($itog.winocr) ($($itog.winocr_ustanovka))"

if ($tessJob) {
  $null = Wait-Job $tessJob -Timeout 600
  $tr = Receive-Job $tessJob -ErrorAction SilentlyContinue | Select-Object -Last 1
  Remove-Job $tessJob -Force -ErrorAction SilentlyContinue
  $itog.tess_ustanovka = if ($tr) { "$($tr.sekund) s: $($tr.vyvod)" } else { 'net-otveta' }
  $exe = "$env:ProgramFiles\Tesseract-OCR\tesseract.exe"
  $itog.tess = if (Test-Path $exe) { ((& $exe --list-langs 2>&1 | Select-Object -Skip 1) -join ',') } else { 'net' }
}
Write-Host "tesseract: $($itog.tess)"
$itog.sekund = [int]$sw.Elapsed.TotalSeconds
($itog | ConvertTo-Json -Depth 4) | Out-File -FilePath $Vyhod -Encoding utf8
exit 0
