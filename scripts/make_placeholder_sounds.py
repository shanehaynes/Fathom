#!/usr/bin/env python3
"""Synthesize placeholder sound pairs for milestone 3 (§8: three screens with
placeholder audio). Real pairs are composed in Logic per §6 (milestone 4);
these only need to make the two-phase mechanic audible and testable.

Follows the §6 envelope rules that matter to the alarm layer:
- phase 1: 30 s exactly, fade-in >= 3 s, full fade-out baked in, ~-4 dB vs chain
- chain A-E: 30 s each, escalating energy via added layers, not loudness tricks
- E: seamless loop (every component has an integer number of cycles in 30 s)

Outputs .caf (48 kHz, 16-bit) for the alarm/notification layer and .m4a for
in-app continuous playback, into Fathom/Resources/Sounds/.
"""

import math
import os
import struct
import subprocess
import wave

SR = 48000
OUT = os.path.join(os.path.dirname(__file__), "..", "Fathom", "Resources", "Sounds")
TMP = "/tmp/fathom-sounds"


def render(duration, layers, fade_in=0.0, fade_out=0.0, gain=0.5, drive=1.0):
    """layers: list of (freq, amp, tremolo_rate, tremolo_depth). Integer freqs
    and tremolo rates that divide evenly into the duration keep loops seamless."""
    n = int(duration * SR)
    out = [0.0] * n
    for freq, amp, trate, tdepth in layers:
        w = 2 * math.pi * freq / SR
        tw = 2 * math.pi * trate / SR
        for i in range(n):
            trem = 1.0 - tdepth * (0.5 + 0.5 * math.sin(tw * i))
            out[i] += amp * trem * math.sin(w * i)
    peak = max(abs(x) for x in out) or 1.0
    if drive > 1.0:
        # Soft clip: raises RMS (loudness) without raising peaks. Placeholder-only
        # trick; real pairs get their loudness from arrangement (§6).
        k = math.tanh(drive)
        out = [math.tanh(drive * x / peak) / k * peak for x in out]
    scale = gain / peak
    fi = int(fade_in * SR)
    fo = int(fade_out * SR)
    for i in range(n):
        f = 1.0
        if fi and i < fi:
            f *= i / fi
        if fo and i >= n - fo:
            f *= (n - i) / fo
        out[i] *= scale * f
    return out


def mix(*parts):
    n = max(len(p) for p in parts)
    out = [0.0] * n
    for p in parts:
        for i, x in enumerate(p):
            out[i] += x
    return out


def crossfade(a, b, fade):
    """5 s of a -> crossfade -> 5 s of b (the Alarm-screen preview clip, §6)."""
    nf = int(fade * SR)
    n = len(a) + len(b) - nf
    out = [0.0] * n
    for i, x in enumerate(a):
        f = 1.0 if i < len(a) - nf else (len(a) - i) / nf
        out[i] += x * f
    off = len(a) - nf
    for i, x in enumerate(b):
        f = i / nf if i < nf else 1.0
        out[off + i] += x * f
    return out


def write_wav(path, samples):
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        frames = bytearray()
        for x in samples:
            frames += struct.pack("<h", max(-32767, min(32767, int(x * 32767))))
        w.writeframes(bytes(frames))


def convert(wav, name, m4a=False):
    subprocess.run(
        ["afconvert", "-f", "caff", "-d", "LEI16@48000", wav,
         os.path.join(OUT, f"{name}.caf")], check=True)
    if m4a:
        subprocess.run(
            ["afconvert", "-f", "m4af", "-d", "aac", "-b", "128000", wav,
             os.path.join(OUT, f"{name}.m4a")], check=True)


# --- Pairs -------------------------------------------------------------------
# Dawn: warm strings -> chimes. Warm low-mid triad, chimes join octave by octave.
# Fountain: water -> bright bells. Detuned low shimmer, pentatonic bells above.

def dawn_gentle():
    # Octave doublings (440, 554) so the gentle phase survives an iPhone speaker,
    # which rolls off below ~300 Hz.
    return [(110, 0.9, 1, 0.35), (165, 0.7, 2, 0.3), (220, 0.6, 1, 0.3), (277, 0.35, 3, 0.4),
            (440, 0.5, 1, 0.3), (554, 0.3, 3, 0.4)]

def dawn_chain(step):
    base = [(110, 0.9, 1, 0.25), (220, 0.8, 2, 0.25), (330, 0.6, 2, 0.3)]
    bright = [(440, 0.5, 4, 0.5), (554, 0.4, 5, 0.5), (660, 0.35, 4, 0.5),
              (880, 0.3, 6, 0.6), (1108, 0.25, 8, 0.6)]
    return base + bright[: step + 1]

def fountain_gentle():
    return [(98, 0.9, 2, 0.5), (147, 0.7, 3, 0.5), (196, 0.5, 2, 0.4), (294, 0.3, 5, 0.6),
            (392, 0.5, 2, 0.4), (588, 0.3, 5, 0.6)]

def fountain_chain(step):
    base = [(98, 0.9, 3, 0.4), (196, 0.7, 4, 0.4), (392, 0.5, 3, 0.4)]
    bells = [(523, 0.5, 6, 0.6), (587, 0.4, 7, 0.6), (784, 0.35, 8, 0.6),
             (1046, 0.3, 9, 0.7), (1568, 0.22, 10, 0.7)]
    return base + bells[: step + 1]


def build_pair(pid, gentle_layers, chain_fn):
    # §6 gains: chain climbs A->D then holds at E; escalation is layers + a
    # modest energy rise, never a mastering trick.
    chain_gain = [0.90, 0.92, 0.94, 0.95, 0.95]
    # Even loudness steps A->E come from rising drive, not peaks (all near 0 dBFS).
    chain_drive = [1.4, 2.1, 2.5, 2.9, 4.0]

    p1 = render(30, gentle_layers, fade_in=3.5, fade_out=4, gain=0.50)
    write_wav(f"{TMP}/{pid}-phase1.wav", p1)
    convert(f"{TMP}/{pid}-phase1.wav", f"{pid}-phase1")

    for i, step in enumerate("abcde"):
        seamless = step == "e"
        s = render(30, chain_fn(i),
                   fade_in=0 if seamless else 0.15,
                   fade_out=0 if seamless else 0.25,
                   gain=chain_gain[i], drive=chain_drive[i])
        write_wav(f"{TMP}/{pid}-{step}.wav", s)
        convert(f"{TMP}/{pid}-{step}.wav", f"{pid}-{step}")

    cont = render(60, chain_fn(4), gain=0.95, drive=4.0)
    write_wav(f"{TMP}/{pid}-continuous.wav", cont)
    convert(f"{TMP}/{pid}-continuous.wav", f"{pid}-continuous", m4a=True)

    g5 = render(5, gentle_layers, fade_in=0.8, gain=0.50)
    f5 = render(5, chain_fn(3), fade_out=0.8, gain=0.90, drive=2.5)
    write_wav(f"{TMP}/{pid}-preview.wav", crossfade(g5, f5, 1.5))
    convert(f"{TMP}/{pid}-preview.wav", f"{pid}-preview", m4a=True)

    sleep = render(60, gentle_layers, gain=0.30)
    write_wav(f"{TMP}/{pid}-sleep.wav", sleep)
    convert(f"{TMP}/{pid}-sleep.wav", f"{pid}-sleep", m4a=True)


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    os.makedirs(TMP, exist_ok=True)
    build_pair("dawn", dawn_gentle(), dawn_chain)
    build_pair("fountain", fountain_gentle(), fountain_chain)
    print("wrote", len(os.listdir(OUT)), "files to", os.path.abspath(OUT))
