<#
.SYNOPSIS
  Runs RFTelem in the EdgeTX Companion 2.12 simulator (TX16S MK3, 800x480)
  with CONFIG.simulate = true, so the scripted flight in simulateTelemetry()
  drives every screen without a CRSF link.

.DESCRIPTION
  1. First run: downloads the EdgeTX v2.12.0 c800x480 SD package into
     sim\sdcard and adds RADIO/MODELS from scripts\sim-template (one model,
     "S2 Ultra", Layout1x1 with RF Telem full-screen, no top bar/trims).
  2. Ensures a Companion 2.12 radio profile named "RFTelem Sim (TX16S MK3)"
     exists (HKCU registry) pointing at sim\sdcard.
  3. Copies sdcard\ into sim\sdcard and flips simulate = true in that copy
     only (sdcard\ itself is never modified).
  4. Sets the widget's Theme option, restarts the simulator.

.PARAMETER Theme
  0 = color, 1 = mono, 2 = cyan.

.PARAMETER NoLaunch
  Only prepare sim\sdcard.

.PARAMETER Reset
  Delete sim\sdcard and rebuild it from scratch.
#>
[CmdletBinding()]
param(
    [ValidateRange(0, 2)][int]$Theme = 0,
    [switch]$NoLaunch,
    [switch]$Reset
)

$ErrorActionPreference = 'Stop'
$root      = Split-Path -Parent $PSScriptRoot
$simSd     = Join-Path $root 'sim\sdcard'
$template  = Join-Path $PSScriptRoot 'sim-template'
$simExe    = 'C:\Program Files (x86)\EdgeTX\Companion 2.12\bin\simulator.exe'
$sdZipUrl  = 'https://github.com/EdgeTX/edgetx-sdcard/releases/download/v2.12.0/c800x480.zip'
$profKey   = 'HKCU:\Software\EdgeTX\Companion 2.12\Profiles'
$profName  = 'RFTelem Sim (TX16S MK3)'
$utf8NoBom = New-Object System.Text.UTF8Encoding $false

if (-not (Test-Path -LiteralPath $simExe)) { throw "Companion 2.12 simulator not found: $simExe" }

Get-Process simulator -ErrorAction SilentlyContinue | Stop-Process -Force

# --- 1. SD image ---------------------------------------------------------
if ($Reset -and (Test-Path -LiteralPath $simSd)) { Remove-Item -LiteralPath $simSd -Recurse -Force }
if (-not (Test-Path -LiteralPath (Join-Path $simSd 'RADIO\radio.yml'))) {
    $zip = Join-Path $env:TEMP 'rftelem-c800x480.zip'
    Write-Host "Downloading $sdZipUrl"
    $ProgressPreference = 'SilentlyContinue'
    Invoke-WebRequest $sdZipUrl -OutFile $zip
    Expand-Archive -LiteralPath $zip -DestinationPath $simSd -Force
    Remove-Item -LiteralPath $zip
    Copy-Item (Join-Path $template '*') $simSd -Recurse -Force
    Write-Host "Created $simSd"
}

# --- 2. Companion profile ------------------------------------------------
$sdForward = $simSd -replace '\\', '/'
$profIndex = $null
if (Test-Path $profKey) {
    foreach ($k in Get-ChildItem $profKey) {
        if ((Get-ItemProperty $k.PSPath).Name -eq $profName) { $profIndex = [int]($k.PSChildName -replace '\D', '') }
    }
}
if ($null -eq $profIndex) {
    $used = @()
    if (Test-Path $profKey) { $used = @(Get-ChildItem $profKey | ForEach-Object { [int]($_.PSChildName -replace '\D', '') }) }
    $profIndex = 0
    while ($used -contains $profIndex) { $profIndex++ }
    New-Item -Path "$profKey\profile$profIndex" -Force | Out-Null
    Write-Host "Created Companion profile $profIndex '$profName'"
}
$k = "$profKey\profile$profIndex"
Set-ItemProperty $k Name $profName
Set-ItemProperty $k fwType 'edgetx-tx16smk3-en'
Set-ItemProperty $k sdPath $sdForward

# --- 3. Widget files (simulate = true in the copy only) --------------------
Copy-Item (Join-Path $root 'sdcard\*') $simSd -Recurse -Force
$mainLua = Join-Path $simSd 'WIDGETS\RFTelem\main.lua'
$src = [IO.File]::ReadAllText($mainLua)
$patched = $src -replace '(?m)^(\s*simulate\s*=\s*)false,', '${1}true,'
if ($patched -eq $src) { throw "Could not find 'simulate = false,' in main.lua" }
[IO.File]::WriteAllText($mainLua, $patched, $utf8NoBom)
# Force a recompile in case a stale main.luac is newer than the copy.
Remove-Item -LiteralPath (Join-Path $simSd 'WIDGETS\RFTelem\main.luac') -ErrorAction SilentlyContinue

# --- 4. Theme option ------------------------------------------------------
$modelYml = Join-Path $simSd 'MODELS\model1.yml'
$yml = [IO.File]::ReadAllText($modelYml)
$re = '(widgetName: RF Telem\s+widgetData:\s+options:\s+0:\s+type: Signed\s+value:\s+signedValue: )-?\d+'
if ($yml -notmatch $re) { throw "RF Telem Theme option not found in $modelYml" }
[IO.File]::WriteAllText($modelYml, ($yml -replace $re, "`${1}$Theme"), $utf8NoBom)

if ($NoLaunch) { Write-Host "Prepared $simSd (Theme=$Theme)"; return }

Start-Process $simExe -ArgumentList '-p', $profIndex, '-s', "`"$simSd`"", '-w', 'sd'
Write-Host "Simulator started (profile $profIndex, Theme=$Theme). The scenario loops every 140s."
