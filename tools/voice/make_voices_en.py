"""English voice files for RotorHUD with Piper (https://github.com/rhasspy/piper).

Reads tools/voice/voices_en.csv (file,group,text - the same file names as
the Japanese voices.csv) and, for each English voice set below, writes one
WAV per row to sdcard/SOUNDS/rf/<set>/<file>.wav: 32 kHz / 16-bit / mono
(Piper's 22.05 kHz resampled; the Japanese sets are 32 kHz too), loudness
brought to -14 dBFS RMS with the same tanh soft limiter as make_voices.ps1.

Usage:
  python make_voices_en.py --piper <dir with piper.exe> --models <dir with .onnx> [--set en_male] [--only armed,land]

Voices (rhasspy/piper-voices v1.0.0, models MIT): chosen for public-domain
training data with no restricted voice in their lineage, so the WAVs can
ship with the GPL project (see each MODEL_CARD):
  en_male   = en_US-john-medium   (LibriVox recordings, public domain; finetuned
                                   from kristin, also LibriVox / from scratch)
  en_female = en_US-ljspeech-high (LJ Speech, public domain, from scratch)
(norman-medium, also public domain, babbled for seconds on one-word lines
such as "Armed." - not used.)
"""
import argparse
import csv
import os
import subprocess
import tempfile
import wave

import numpy as np

SETS = {
    "en_male": ("en_US-john-medium", 1.0),  # model, length scale (>1 = slower)
    "en_female": ("en_US-ljspeech-high", 1.0),
}
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT = os.path.join(ROOT, "sdcard", "SOUNDS", "rf")
RATE = 32000


def synth(piper, model, text, length_scale):
    """Piper -> (samples float -1..1, sample rate). Through a file: piper.exe's
    stdout on Windows is in text mode (every 0x0A byte becomes 0D 0A), which
    garbled the PCM into loud crackle."""
    fd, tmp = tempfile.mkstemp(suffix=".wav")
    os.close(fd)
    try:
        subprocess.run(
            [os.path.join(piper, "piper.exe"), "--model", model, "--output_file", tmp,
             "--length_scale", str(length_scale), "--sentence_silence", "0.1"],
            input=text.encode("utf-8"), capture_output=True, check=True)
        with wave.open(tmp) as w:
            rate = w.getframerate()
            pcm = np.frombuffer(w.readframes(w.getnframes()), dtype="<i2").astype(np.float64) / 32768.0
    finally:
        os.remove(tmp)
    return pcm, rate


def resample(x, src, dst):
    """Band-limited resampling (FFT), fine for short clips."""
    if src == dst:
        return x
    n = int(round(len(x) * dst / src))
    spec = np.fft.rfft(x)
    out = np.zeros(n // 2 + 1, dtype=complex)
    k = min(len(spec), len(out))
    out[:k] = spec[:k]
    return np.fft.irfft(out, n) * (n / len(x))


def loudness(x, target_db=-14.0, knee=0.7):
    """RMS to target_db, then tanh soft limit above knee (as make_voices.ps1)."""
    rms = np.sqrt(np.mean(x * x))
    if rms == 0:
        return x
    y = x * (10 ** (target_db / 20) / rms)
    a = np.abs(y)
    over = a > knee
    a[over] = knee + (1 - knee) * np.tanh((a[over] - knee) / (1 - knee))
    return np.sign(y) * a


def write_wav(path, x):
    pcm = np.clip(np.round(x * 32767), -32767, 32767).astype("<i2")
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(pcm.tobytes())


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--piper", required=True)
    ap.add_argument("--models", required=True)
    ap.add_argument("--set", default="")
    ap.add_argument("--only", default="")
    ap.add_argument("--takes", type=int, default=3)
    a = ap.parse_args()
    sets = [s for s in a.set.split(",") if s] or list(SETS)
    only = {s for s in a.only.split(",") if s}
    with open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "voices_en.csv"), encoding="utf-8") as f:
        rows = list(csv.DictReader(f))
    for name in sets:
        model, scale = SETS[name]
        out = os.path.join(OUT, name)
        os.makedirs(out, exist_ok=True)
        count = 0
        for r in rows:
            if only and r["file"] not in only:
                continue
            # Piper varies from take to take and now and then babbles on a
            # short line ("Armed." came out as two words): the shortest of a
            # few takes
            takes = [synth(a.piper, os.path.join(a.models, model + ".onnx"), r["text"], scale)
                     for _ in range(a.takes)]
            x, rate = min(takes, key=lambda t: len(t[0]))
            write_wav(os.path.join(out, r["file"] + ".wav"), loudness(resample(x, rate, RATE)))
            count += 1
        print(f"== {name}: {count} file(s)")


if __name__ == "__main__":
    main()
