#!/usr/bin/env python3
"""Synthesized PLACEHOLDER wake sounds for milestone 1 (stdlib only, no numpy).

These are not the real sound pairs — they exist so the alarm chain has six distinct
30-second files that follow DESIGN.md §6's shape: a soft fading pad for phase 1 and an
escalating A–E chain for phase 2, with E composed to loop cleanly. Replace with
composed pairs per DESIGN.md §6.

Usage: python3 tools/gen_placeholder_sounds.py [out_dir]
"""
import math, os, struct, sys, wave

SR = 22050
DUR = 30.0
N = int(SR * DUR)
TWO_PI = 2 * math.pi

# A major-ish voicing: warm, no tension.
PAD = [110.0, 164.81, 220.0, 277.18]                     # A2 E3 A3 C#4
ARP = [440.0, 554.37, 659.25, 880.0, 659.25, 554.37, 440.0, 329.63]  # A4 C#5 E5 A5 ...


def pad_track(amp, bright, fade_in, fade_out_start):
    buf = [0.0] * N
    for i in range(N):
        t = i / SR
        env = min(1.0, t / fade_in)
        if t > fade_out_start:
            env *= max(0.0, 1.0 - (t - fade_out_start) / (DUR - fade_out_start))
        trem = 1.0 + 0.06 * math.sin(TWO_PI * 0.18 * t)
        s = 0.0
        for f in PAD:
            s += math.sin(TWO_PI * f * t)
            if bright > 0:
                s += bright * 0.5 * math.sin(TWO_PI * 2 * f * t)
                s += bright * 0.2 * math.sin(TWO_PI * 3 * f * t)
        buf[i] = amp * env * trem * s / len(PAD)
    return buf


def pluck_track(rate_per_sec, amp, bright, octave, fade_in):
    """Decaying-sine arpeggio. rate_per_sec notes per second; period divides 30 s for looping."""
    buf = [0.0] * N
    if rate_per_sec <= 0:
        return buf
    step = 1.0 / rate_per_sec
    count = int(DUR * rate_per_sec)
    length = int(SR * 0.9)
    for k in range(count):
        t0 = k * step
        f = ARP[k % len(ARP)] * (2 if octave and k % 2 == 0 else 1)
        start = int(t0 * SR)
        vel = amp * min(1.0, t0 / fade_in if fade_in > 0 else 1.0)
        for j in range(length):
            i = start + j
            if i >= N:
                break
            tj = j / SR
            env = math.exp(-4.0 * tj)
            s = math.sin(TWO_PI * f * tj) + bright * 0.4 * math.sin(TWO_PI * 2 * f * tj)
            buf[i] += vel * env * s
    return buf


def write(path, tracks):
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        frames = bytearray()
        for i in range(N):
            s = sum(t[i] for t in tracks)
            s = math.tanh(s * 1.2)  # soft clip
            frames += struct.pack("<h", int(max(-1.0, min(1.0, s)) * 32767))
        w.writeframes(bytes(frames))
    print("wrote", path)


def main():
    out = sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(__file__), "..", "Fathom", "Resources", "Sounds")
    os.makedirs(out, exist_ok=True)
    # Phase 1: quiet pad, slow fade in, fully faded out by 30 s.
    write(os.path.join(out, "phase1_gentle.wav"), [pad_track(0.22, 0.0, 4.0, 20.0)])
    # Phase 2 A–E: arrangement escalates; loudness only modestly.
    write(os.path.join(out, "phase2_a.wav"), [pad_track(0.30, 0.15, 1.5, 27.0), pluck_track(0.5, 0.25, 0.1, False, 2.0)])
    write(os.path.join(out, "phase2_b.wav"), [pad_track(0.32, 0.30, 1.0, 27.0), pluck_track(1.0, 0.30, 0.3, False, 1.0)])
    write(os.path.join(out, "phase2_c.wav"), [pad_track(0.34, 0.45, 0.5, 27.0), pluck_track(2.0, 0.34, 0.5, False, 0.5)])
    write(os.path.join(out, "phase2_d.wav"), [pad_track(0.36, 0.60, 0.5, 27.0), pluck_track(2.0, 0.38, 0.7, True, 0.5)])
    # E: plateau — no fade-out so it loops; pattern period (8 notes @ 4/s = 2 s) divides 30 s.
    write(os.path.join(out, "phase2_e.wav"), [pad_track(0.38, 0.75, 0.01, DUR), pluck_track(4.0, 0.40, 0.8, True, 0.0)])


if __name__ == "__main__":
    main()
