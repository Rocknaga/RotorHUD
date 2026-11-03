<#
.SYNOPSIS
  Copies the contents of sdcard\ (and optionally tools\*\sdcard\) onto the
  radio's SD card, keeping the folder structure (WIDGETS\..., IMAGES\...).

.PARAMETER Target
  SD card root, e.g. E:\  . If omitted, the ROTORHUD_SD environment variable is
  used. If that is empty too, or the value is 'auto', removable drives are
  scanned for something that looks like an EdgeTX SD card (has RADIO+MODELS,
  or WIDGETS).

.PARAMETER Tools
  Also copy tools\diagtest\sdcard\ (font / bitmap diagnostic widget).

.PARAMETER DryRun
  Only list what would be copied.

NOTE: files are only added / overwritten. Nothing on the card is deleted.
Put the radio in USB storage mode (or use a card reader) first, and eject the
drive safely afterwards.
#>
[CmdletBinding()]
param(
    [string]$Target = $env:ROTORHUD_SD,
    [switch]$Tools,
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot

function Test-EdgeTxCard([string]$path) {
    $hasWidgets = Test-Path -LiteralPath (Join-Path $path 'WIDGETS')
    $hasRadio   = Test-Path -LiteralPath (Join-Path $path 'RADIO')
    $hasModels  = Test-Path -LiteralPath (Join-Path $path 'MODELS')
    return ($hasWidgets -or ($hasRadio -and $hasModels))
}

if ([string]::IsNullOrWhiteSpace($Target) -or $Target.Trim() -eq 'auto') {
    $candidates = @(
        Get-CimInstance Win32_LogicalDisk -Filter 'DriveType=2' |
            ForEach-Object { $_.DeviceID + '\' } |
            Where-Object { Test-EdgeTxCard $_ }
    )
    if ($candidates.Count -eq 1) {
        $Target = $candidates[0]
        Write-Host "Auto-detected SD card: $Target"
    } elseif ($candidates.Count -eq 0) {
        throw 'No EdgeTX SD card found among removable drives. Pass -Target E:\ (or set ROTORHUD_SD).'
    } else {
        throw ('Several candidate drives found: ' + ($candidates -join ', ') + '. Pass -Target explicitly.')
    }
}

$Target = $Target.Trim().Trim('"')
if (-not (Test-Path -LiteralPath $Target -PathType Container)) {
    throw "Target not found: $Target"
}
if (-not (Test-EdgeTxCard $Target)) {
    Write-Warning "$Target does not contain WIDGETS or RADIO+MODELS - is this really the radio's SD card?"
}

$sources = @((Join-Path $root 'sdcard'))
if ($Tools) {
    Get-ChildItem -LiteralPath (Join-Path $root 'tools') -Directory | ForEach-Object {
        $s = Join-Path $_.FullName 'sdcard'
        if (Test-Path -LiteralPath $s) { $sources += $s }
    }
}

$count = 0
foreach ($src in $sources) {
    $srcFull = (Resolve-Path -LiteralPath $src).Path.TrimEnd('\')
    Get-ChildItem -LiteralPath $srcFull -Recurse -File | ForEach-Object {
        $rel  = $_.FullName.Substring($srcFull.Length).TrimStart('\')
        $dest = Join-Path $Target $rel
        if ($DryRun) {
            Write-Host "[dry-run] $rel"
        } else {
            $dir = Split-Path -Parent $dest
            if (-not (Test-Path -LiteralPath $dir)) {
                New-Item -ItemType Directory -Path $dir | Out-Null
            }
            Copy-Item -LiteralPath $_.FullName -Destination $dest -Force
            Write-Host "copied  $rel"
        }
        $script:count++
    }
}

# EdgeTX caches compiled scripts as .luac next to the .lua; drop the
# widget's so the radio compiles the files just copied.
if (-not $DryRun) {
    $widgetDir = Join-Path $Target 'WIDGETS\RotorHUD'
    if (Test-Path -LiteralPath $widgetDir) {
        Get-ChildItem -LiteralPath $widgetDir -Filter '*.luac' | Remove-Item -Force
    }
}

if ($DryRun) { Write-Host "$count file(s) would be copied to $Target" }
else         { Write-Host "Done: $count file(s) copied to $Target. Eject the drive safely before using the radio." }
