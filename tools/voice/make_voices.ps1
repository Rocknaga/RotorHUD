<#
.SYNOPSIS
  Generates the RFTelem voice files with the local VOICEVOX engine.

.DESCRIPTION
  Reads tools\voice\voices.csv (file,group,text) and, for each voice set in
  tools\voice\voicesets.csv (index,set,speaker,speed,label), writes one WAV
  per row to sdcard\SOUNDS\rf\<set>\<file>.wav as 32 kHz / 16-bit / mono PCM
  (set through the engine's outputSamplingRate/outputStereo, so no ffmpeg is
  needed). The widget's "Voice" option picks the set by its index.
  Starts C:\Program Files\VOICEVOX\vv-engine\run.exe hidden if the engine
  is not already listening on 127.0.0.1:50021.

.PARAMETER Set
  Voice set names to generate (e.g. -Set no7,ryusei). Default: all sets.

.PARAMETER Only
  Generate only these file names (e.g. -Only gov_active,armed).

.NOTE
  VOICEVOX terms: each character has its own usage terms; generated audio
  must credit e.g. "VOICEVOX:No.7" when published.
#>
[CmdletBinding()]
param(
    [string[]]$Set,
    [string[]]$Only,
    [switch]$ListSpeakers,
    [string]$EngineExe = 'C:\Program Files\VOICEVOX\vv-engine\run.exe'
)

$ErrorActionPreference = 'Stop'
$root   = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$csv    = Join-Path $PSScriptRoot 'voices.csv'
$setCsv = Join-Path $PSScriptRoot 'voicesets.csv'
$outRoot = Join-Path $root 'sdcard\SOUNDS\rf'
$base   = 'http://127.0.0.1:50021'
$utf8   = New-Object System.Text.UTF8Encoding $false

function Invoke-Engine([string]$method, [string]$path, [byte[]]$body) {
    $req = [System.Net.HttpWebRequest]::Create("$base$path")
    $req.Method = $method
    $req.Timeout = 60000
    if ($body) {
        $req.ContentType = 'application/json'
        $req.ContentLength = $body.Length
        $s = $req.GetRequestStream(); $s.Write($body, 0, $body.Length); $s.Close()
    } elseif ($method -eq 'POST') {
        $req.ContentLength = 0
    }
    $resp = $req.GetResponse()
    $ms = New-Object System.IO.MemoryStream
    $resp.GetResponseStream().CopyTo($ms)
    $resp.Close()
    return ,$ms.ToArray()
}

function Test-Engine {
    try { Invoke-Engine 'GET' '/version' $null | Out-Null; return $true } catch { return $false }
}

if (-not (Test-Engine)) {
    if (-not (Test-Path -LiteralPath $EngineExe)) { throw "VOICEVOX engine not found: $EngineExe" }
    Write-Host 'Starting VOICEVOX engine...'
    Start-Process $EngineExe -WindowStyle Hidden
    for ($i = 0; $i -lt 60 -and -not (Test-Engine); $i++) { Start-Sleep -Seconds 1 }
    if (-not (Test-Engine)) { throw 'VOICEVOX engine did not start.' }
}

if ($ListSpeakers) {
    $json = $utf8.GetString((Invoke-Engine 'GET' '/speakers' $null)) | ConvertFrom-Json
    foreach ($sp in $json) { foreach ($st in $sp.styles) { '{0,4}  {1} / {2}' -f $st.id, $sp.name, $st.name } }
    return
}

# "-Only a,b" / "-Set a,b" arrive as one string when run with -File.
function Split-List($list) { @($list | ForEach-Object { $_ -split ',' } | ForEach-Object { $_.Trim() } | Where-Object { $_ }) }

$rows = Import-Csv -LiteralPath $csv -Encoding UTF8
if ($Only) { $names = Split-List $Only; $rows = $rows | Where-Object { $names -contains $_.file } }
$sets = Import-Csv -LiteralPath $setCsv -Encoding UTF8
if ($Set) { $wanted = Split-List $Set; $sets = $sets | Where-Object { $wanted -contains $_.set } }
if (-not $sets) { throw "No matching voice set in $setCsv" }

foreach ($vs in $sets) {
    $outDir = Join-Path $outRoot $vs.set
    New-Item -ItemType Directory -Force $outDir | Out-Null
    Write-Host "== [$($vs.index)] $($vs.set): $($vs.label) (speaker $($vs.speaker), speed $($vs.speed))"
    foreach ($row in $rows) {
        $q = '/audio_query?speaker={0}&text={1}' -f $vs.speaker, [uri]::EscapeDataString($row.text)
        $query = $utf8.GetString((Invoke-Engine 'POST' $q $null)) | ConvertFrom-Json
        $query.outputSamplingRate = 32000
        $query.outputStereo = $false
        $query.speedScale = [double]$vs.speed
        $query.prePhonemeLength = 0.05
        $query.postPhonemeLength = 0.05
        $body = $utf8.GetBytes(($query | ConvertTo-Json -Depth 20 -Compress))
        $wav = Invoke-Engine 'POST' "/synthesis?speaker=$($vs.speaker)" $body
        [System.IO.File]::WriteAllBytes((Join-Path $outDir ($row.file + '.wav')), $wav)
    }
    Write-Host "   $(@($rows).Count) file(s) -> $outDir"
}
