<#
.SYNOPSIS
  Saves the simulator LCD (800x480, native pixels) as PNG files.

.DESCRIPTION
  Clicks the simulator's screenshot button (camera icon in the left toolbar),
  which copies the LCD to the clipboard, then saves the clipboard image.
  With -Count > 1 it repeats every -Interval seconds and also writes
  sheet.png (all frames tiled at half size) into the output folder.

  The button position (-ButtonX/-ButtonY, relative to the window's top-left)
  was measured on a 2560x1440 display at the default Companion layout. If no
  image comes back, take a full screenshot and re-measure.

.EXAMPLE
  scripts\sim-capture.ps1 -Count 25 -Interval 6   # one full 140s scenario
#>
[CmdletBinding()]
param(
    [string]$OutDir = '',
    [int]$Count = 1,
    [double]$Interval = 6,
    [int]$ButtonX = 43,
    [int]$ButtonY = 497
)

$ErrorActionPreference = 'Stop'
# $PSScriptRoot is empty inside param() defaults on Windows PowerShell 5.1.
if (-not $OutDir) { $OutDir = Join-Path (Split-Path -Parent $PSScriptRoot) 'sim\captures' }
Add-Type -AssemblyName System.Windows.Forms, System.Drawing
Add-Type @"
using System; using System.Runtime.InteropServices;
public class RfSimWin {
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
  [DllImport("user32.dll")] public static extern void mouse_event(int f, int dx, int dy, int d, int e);
  [DllImport("user32.dll")] public static extern void keybd_event(byte vk, byte scan, int f, int e);
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  public struct RECT { public int L, T, R, B; }
}
"@
[RfSimWin]::SetProcessDPIAware() | Out-Null

# Allow a just-launched simulator up to 30s to open its window.
$proc = $null
for ($i = 0; $i -lt 60 -and -not $proc; $i++) {
    $proc = Get-Process simulator -ErrorAction SilentlyContinue | Where-Object MainWindowHandle -ne 0 | Select-Object -First 1
    if (-not $proc) { Start-Sleep -Milliseconds 500 }
}
if (-not $proc) { throw 'Simulator is not running (start it with scripts\sim.ps1).' }
New-Item -ItemType Directory -Force $OutDir | Out-Null

$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$files = @()
$t0 = Get-Date
for ($i = 0; $i -lt $Count; $i++) {
    $due = $t0.AddSeconds($i * $Interval)
    $wait = ($due - (Get-Date)).TotalMilliseconds
    if ($wait -gt 0) { Start-Sleep -Milliseconds $wait }

    $img = $null
    for ($try = 0; $try -lt 3 -and -not $img; $try++) {
        # Another app can briefly hold the clipboard; a failed Clear just
        # means this try may pick up a stale image, so retry instead.
        try { [System.Windows.Forms.Clipboard]::Clear() } catch { Start-Sleep -Milliseconds 300; continue }
        # Windows refuses SetForegroundWindow from a background process unless
        # a key event just happened - a bare ALT tap lifts that lock.
        if ([RfSimWin]::GetForegroundWindow() -ne $proc.MainWindowHandle) {
            [RfSimWin]::keybd_event(0x12, 0, 0, 0); [RfSimWin]::keybd_event(0x12, 0, 2, 0)
            [RfSimWin]::SetForegroundWindow($proc.MainWindowHandle) | Out-Null
            Start-Sleep -Milliseconds 300
        }
        $r = New-Object RfSimWin+RECT
        [RfSimWin]::GetWindowRect($proc.MainWindowHandle, [ref]$r) | Out-Null
        [RfSimWin]::SetCursorPos($r.L + $ButtonX, $r.T + $ButtonY) | Out-Null
        Start-Sleep -Milliseconds 80
        [RfSimWin]::mouse_event(2, 0, 0, 0, 0); Start-Sleep -Milliseconds 80; [RfSimWin]::mouse_event(4, 0, 0, 0, 0)
        Start-Sleep -Milliseconds 700
        try { $img = [System.Windows.Forms.Clipboard]::GetImage() } catch { $img = $null }
    }
    if (-not $img) {
        Write-Warning "Frame $i skipped: no image on the clipboard (simulator still booting, or -ButtonX/-ButtonY off)."
        continue
    }
    $name = if ($Count -eq 1) { "lcd-$stamp.png" } else { "lcd-$stamp-{0:D2}.png" -f $i }
    $path = Join-Path $OutDir $name
    $img.Save($path, [System.Drawing.Imaging.ImageFormat]::Png)
    $img.Dispose()
    $files += $path
    Write-Host ("{0,5:N1}s  {1}" -f ((Get-Date) - $t0).TotalSeconds, $path)
}

if ($Count -gt 1) {
    $W = 400; $H = 240; $cols = 5; $rows = [math]::Ceiling($files.Count / $cols)
    $sheet = New-Object System.Drawing.Bitmap ($W * $cols), ($H * $rows)
    $g = [System.Drawing.Graphics]::FromImage($sheet)
    $font = New-Object System.Drawing.Font 'Arial', 14
    for ($i = 0; $i -lt $files.Count; $i++) {
        $im = [System.Drawing.Image]::FromFile($files[$i])
        $x = ($i % $cols) * $W; $y = [math]::Floor($i / $cols) * $H
        $g.DrawImage($im, $x, $y, $W, $H)
        $g.FillRectangle([System.Drawing.Brushes]::Yellow, $x, $y, 30, 20)
        $g.DrawString(('{0:D2}' -f $i), $font, [System.Drawing.Brushes]::Black, $x + 2, $y)
        $im.Dispose()
    }
    $sheetPath = Join-Path $OutDir "sheet-$stamp.png"
    $sheet.Save($sheetPath, [System.Drawing.Imaging.ImageFormat]::Png)
    Write-Host "Sheet: $sheetPath"
}
