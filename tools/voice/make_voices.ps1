<#
.SYNOPSIS
  Generates the RotorHUD voice files with the local VOICEVOX engine.

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

.PARAMETER TargetRmsDb
  Loudness every file is brought to (RMS, dBFS). VOICEVOX output sat at
  -22..-28 dB RMS, too quiet on the radio; -14 is clear speech level.
  Peaks above the limiter knee are soft-limited instead of clipping.

.PARAMETER NormalizeOnly
  Don't synthesize: apply the loudness step to the existing WAVs of the
  selected sets/files in place (used once for files made before it existed).

.NOTE
  VOICEVOX terms: each character has its own usage terms; generated audio
  must credit e.g. "VOICEVOX:No.7" when published.
#>
[CmdletBinding()]
param(
    [string[]]$Set,
    [string[]]$Only,
    [double]$TargetRmsDb = -14,
    [switch]$NormalizeOnly,
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

# Loudness: scale 16-bit mono PCM so its RMS is targetRmsDb, then pass
# anything above 0.7 FS through a tanh soft limiter (ceiling 1.0 FS) so the
# extra gain can't clip.
Add-Type -TypeDefinition @"
using System;
public static class RfLoudness {
  public static byte[] Normalize(byte[] wav, double targetRmsDb) {
    int pos = 12, dataOff = -1, dataLen = 0;
    while (pos + 8 <= wav.Length) {
      string id = System.Text.Encoding.ASCII.GetString(wav, pos, 4);
      int len = BitConverter.ToInt32(wav, pos + 4);
      if (id == "data") { dataOff = pos + 8; dataLen = Math.Min(len, wav.Length - dataOff); break; }
      pos += 8 + len + (len & 1);
    }
    if (dataOff < 0) throw new Exception("no data chunk");
    int n = dataLen / 2;
    double sum = 0;
    for (int i = 0; i < n; i++) { double s = BitConverter.ToInt16(wav, dataOff + i * 2) / 32768.0; sum += s * s; }
    if (n == 0 || sum == 0) return wav;
    double gain = Math.Pow(10, targetRmsDb / 20) / Math.Sqrt(sum / n);
    const double knee = 0.7;
    byte[] outWav = (byte[])wav.Clone();
    for (int i = 0; i < n; i++) {
      double x = BitConverter.ToInt16(wav, dataOff + i * 2) / 32768.0 * gain;
      double a = Math.Abs(x);
      if (a > knee) a = knee + (1 - knee) * Math.Tanh((a - knee) / (1 - knee));
      short v = (short)Math.Max(-32767, Math.Min(32767, Math.Round(Math.Sign(x) * a * 32767)));
      byte[] b = BitConverter.GetBytes(v);
      outWav[dataOff + i * 2] = b[0]; outWav[dataOff + i * 2 + 1] = b[1];
    }
    return outWav;
  }
}
"@

function Test-Engine {
    try { Invoke-Engine 'GET' '/version' $null | Out-Null; return $true } catch { return $false }
}

if (-not $NormalizeOnly -and -not (Test-Engine)) {
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
    if ($NormalizeOnly) {
        $count = 0
        foreach ($row in $rows) {
            $path = Join-Path $outDir ($row.file + '.wav')
            if (Test-Path -LiteralPath $path) {
                [System.IO.File]::WriteAllBytes($path, [RfLoudness]::Normalize([System.IO.File]::ReadAllBytes($path), $TargetRmsDb))
                $count++
            }
        }
        Write-Host "== $($vs.set): normalized $count file(s) to $TargetRmsDb dB RMS"
        continue
    }
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
        [System.IO.File]::WriteAllBytes((Join-Path $outDir ($row.file + '.wav')), [RfLoudness]::Normalize($wav, $TargetRmsDb))
    }
    Write-Host "   $(@($rows).Count) file(s) -> $outDir"
}
