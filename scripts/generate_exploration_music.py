#!/usr/bin/env python3
"""Original 32-second exploration cue, deterministic and reproducible, no downloads."""
import math
from pathlib import Path

from generate_audio import SAMPLE_RATE, fade_edges, write_wav


def compose():
    rate = SAMPLE_RATE
    length = rate * 32
    left, right = [0.0] * length, [0.0] * length
    chords = [(146.83, 174.61, 220.0), (116.54, 146.83, 174.61),
              (130.81, 155.56, 196.0), (110.0, 164.81, 220.0)]
    # Bowed pads overlap bar boundaries. Tails wrap to the start of the loop.
    for bar in range(8):
        chord = chords[bar % 4]
        for sample in range(rate * 6):
            t = sample / rate
            envelope = math.sin(math.pi * t / 6) ** 2
            signal = sum(math.sin(2 * math.pi * f * t) +
                         0.15 * math.sin(2 * math.pi * f * 2 * t)
                         for f in chord) * envelope * 0.055
            index = (bar * rate * 4 + sample) % length
            left[index] += signal * 0.9
            right[index] += signal
    # Sparse dulcimer motif leaves room for cards and combat sounds.
    motif = [293.66, 349.23, 440.0, 392.0, 349.23, 293.66, 261.63, 220.0]
    for note in range(16):
        frequency = motif[note % len(motif)]
        for sample in range(rate * 3):
            t = sample / rate
            envelope = (1 - math.exp(-t * 75)) * math.exp(-t * 2.6)
            signal = (math.sin(2 * math.pi * frequency * t) +
                      0.23 * math.sin(2 * math.pi * frequency * 3 * t)) * envelope * 0.16
            index = (note * rate * 2 + rate // 2 + sample) % length
            left[index] += signal * (0.72 if note % 2 else 1)
            right[index] += signal * (1 if note % 2 else 0.72)
            # Circular stereo echo also retains its tail across loop boundaries.
            right[(index + int(rate * 0.375)) % length] += signal * 0.2
            left[(index + int(rate * 0.625)) % length] += signal * 0.12
    peak = max(max(map(abs, left)), max(map(abs, right)), 0.001)
    left = [value * 0.72 / peak for value in left]
    right = [value * 0.72 / peak for value in right]
    fade_edges(left, int(rate * 0.015))
    fade_edges(right, int(rate * 0.015))
    return left, right


if __name__ == "__main__":
    write_wav(Path(__file__).resolve().parents[1] / "assets/audio/music_explore.wav", *compose())
