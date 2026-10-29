"""Synthesizes the App Preview's original background music (no samples, no licensing).
Soft keys pad + arpeggio + sub bass over Cmaj7 / Am7 / Fmaj7 / G6 at 96 BPM.
    python3 tools/make_music.py <out.wav> [seconds]
"""
import sys, wave
import numpy as np

out = sys.argv[1]
seconds = float(sys.argv[2]) if len(sys.argv) > 2 else 26.0
SR, BPM = 44100, 96
beat = 60 / BPM
bar = 4 * beat
t = np.arange(int(seconds * SR)) / SR

def hz(midi):
    return 440.0 * 2 ** ((midi - 69) / 12)

# One chord per bar: (bass root, chord tones)
chords = [(48, [60, 64, 67, 71]),   # Cmaj7
          (45, [57, 60, 64, 67]),   # Am7
          (41, [57, 60, 64, 65]),   # Fmaj7 (voiced around A)
          (43, [55, 59, 62, 64])]   # G6  (bass in octave 3: audible on laptop speakers)

def keys(freq, length, decay):
    """Electric-piano-ish tone: fundamental plus soft overtones, quick attack, exponential decay."""
    n = int(length * SR)
    x = np.arange(n) / SR
    env = np.minimum(x / 0.01, 1) * np.exp(-x / decay)
    tone = np.sin(2 * np.pi * freq * x) + 0.25 * np.sin(4 * np.pi * freq * x) + 0.08 * np.sin(6 * np.pi * freq * x)
    return tone * env

left = np.zeros_like(t)
right = np.zeros_like(t)

def add(sig, start, gain, pan):
    i = int(start * SR)
    if i >= len(t):
        return
    sig = sig[: len(t) - i]
    left[i:i + len(sig)] += sig * gain * (1 - pan)
    right[i:i + len(sig)] += sig * gain * (1 + pan)

b = 0
while b * bar < seconds:
    root, tones = chords[b % len(chords)]
    start = b * bar
    for k, m in enumerate(tones):                       # pad: the whole chord, long decay
        add(keys(hz(m), bar + 1.5, 1.6), start + 0.012 * k, 0.10, -0.3 + 0.2 * k)
    add(keys(hz(root), bar, 1.2), start, 0.22, 0.0)     # bass
    arp = [tones[0] + 12, tones[2] + 12, tones[1] + 12, tones[3] + 12]
    for s in range(8):                                  # eighth-note arpeggio, an octave up
        add(keys(hz(arp[s % 4]), beat, 0.35), start + s * beat / 2, 0.045, 0.35 if s % 2 else -0.35)
    b += 1

# Gentle low-pass (one-pole) to keep it warm, then fades and normalize to -3 dBFS
def lowpass(x, cutoff=3500.0):
    a = np.exp(-2 * np.pi * cutoff / SR)
    y = np.empty_like(x)
    acc = 0.0
    for i, v in enumerate(x):
        acc = (1 - a) * v + a * acc
        y[i] = acc
    return y

def highpass(x, cutoff=70.0):   # remove rumble the bass and note onsets leave below ~70 Hz
    return x - lowpass(x, cutoff)

left, right = highpass(lowpass(left)), highpass(lowpass(right))
fade = np.ones_like(t)
fin, fout = int(1.0 * SR), int(2.5 * SR)
fade[:fin] = np.linspace(0, 1, fin)
fade[-fout:] = np.linspace(1, 0, fout)
stereo = np.stack([left * fade, right * fade], axis=1)
stereo *= 10 ** (-3 / 20) / np.max(np.abs(stereo))

with wave.open(out, "wb") as w:
    w.setnchannels(2)
    w.setsampwidth(2)
    w.setframerate(SR)
    w.writeframes((stereo * 32767).astype("<i2").tobytes())
print(f"Wrote {out} ({seconds:.1f}s)")
