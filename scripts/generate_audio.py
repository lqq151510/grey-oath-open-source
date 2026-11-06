#!/usr/bin/env python3
"""Procedural Dark Fantasy Audio Synthesizer for 灰誓 (Grey Oath).
Generates high-quality looping music and sound effects (16-bit 44.1kHz Stereo WAV).
"""
import math
import random
import struct
import wave
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
AUDIO_DIR = ROOT / "assets" / "audio"
SAMPLE_RATE = 44100

def clamp(v, low=-1.0, high=1.0):
    return max(low, min(high, v))

def fade_edges(samples: list[float], fade_samples: int) -> None:
    fade = min(fade_samples, len(samples) // 4)
    if fade <= 0:
        return
    for i in range(fade):
        weight = i / fade
        samples[i] *= weight
        samples[-1 - i] *= weight


def write_wav(path: Path, samples_left: list[float], samples_right: list[float]):
    assert len(samples_left) == len(samples_right)
    path.parent.mkdir(parents=True, exist_ok=True)
    with wave.open(str(path), "wb") as f:
        f.setnchannels(2)
        f.setsampwidth(2)
        f.setframerate(SAMPLE_RATE)
        frames = bytearray()
        for i in range(len(samples_left)):
            sl = int(clamp(samples_left[i]) * 32767)
            sr = int(clamp(samples_right[i]) * 32767)
            frames.extend(struct.pack("<hh", sl, sr))
        f.writeframes(frames)
    print(f"Generated {path.name} ({len(samples_left) / SAMPLE_RATE:.2f}s, {path.stat().st_size} bytes)")

def bell_tone(freq: float, duration: float, volume: float = 0.5) -> list[float]:
    """Modal synthesis of an ancient gothic bronze bell."""
    n = int(SAMPLE_RATE * duration)
    # Bell partials (fundamental, tierce, quint, octave, etc.)
    ratios = [1.0, 1.2, 1.5, 2.0, 2.76, 3.4, 4.15, 5.8]
    weights = [0.4, 0.25, 0.2, 0.15, 0.1, 0.08, 0.05, 0.03]
    decays = [1.2, 1.8, 2.2, 3.0, 4.5, 6.0, 8.0, 12.0]
    out = [0.0] * n
    for r, w, d in zip(ratios, weights, decays):
        f = freq * r
        d_rate = d / duration
        phase_inc = 2 * math.pi * f / SAMPLE_RATE
        phase = 0.0
        for i in range(n):
            t = i / SAMPLE_RATE
            env = math.exp(-t * d_rate)
            out[i] += math.sin(phase) * w * env
            phase += phase_inc
    return [s * volume for s in out]

def synth_sfx_click() -> tuple[list[float], list[float]]:
    duration = 0.10
    n = int(SAMPLE_RATE * duration)
    out_l = [0.0] * n
    out_r = [0.0] * n
    rng = random.Random(101)
    for i in range(n):
        t = i / SAMPLE_RATE
        env = math.exp(-t * 60)
        # Snap + low thud
        snap = (rng.random() * 2 - 1) * math.exp(-t * 120) * 0.3
        thud = math.sin(2 * math.pi * 180 * (1 - t * 4) * t) * 0.4 * env
        click = math.sin(2 * math.pi * 1200 * t) * 0.2 * math.exp(-t * 150)
        s = (snap + thud + click) * 0.7
        out_l[i] = s
        out_r[i] = s * 0.95
    return out_l, out_r

def synth_sfx_card() -> tuple[list[float], list[float]]:
    duration = 0.30
    n = int(SAMPLE_RATE * duration)
    out_l = [0.0] * n
    out_r = [0.0] * n
    rng = random.Random(202)
    # Filtered noise whoosh + parchment flutter
    noise = [rng.random() * 2 - 1 for _ in range(n)]
    # Soft low-pass
    filtered = [0.0] * n
    val = 0.0
    for i in range(n):
        val += (noise[i] - val) * 0.15
        filtered[i] = val
    for i in range(n):
        t = i / SAMPLE_RATE
        # Swell and decay envelope
        env = math.sin(t / duration * math.pi) ** 1.5
        wh = filtered[i] * env * 0.7
        # Subtle parchment flap frequency modulation
        tone = math.sin(2 * math.pi * (320 + 100 * math.sin(2 * math.pi * 15 * t)) * t) * 0.15 * env
        out_l[i] = wh * 0.85 + tone
        out_r[i] = wh + tone * 0.8
    return out_l, out_r

def synth_sfx_slash() -> tuple[list[float], list[float]]:
    duration = 0.40
    n = int(SAMPLE_RATE * duration)
    out_l = [0.0] * n
    out_r = [0.0] * n
    rng = random.Random(303)
    for i in range(n):
        t = i / SAMPLE_RATE
        # Swift pitch drop from 2400Hz to 120Hz
        freq = 2400 * math.exp(-t * 14) + 120
        blade = math.sin(2 * math.pi * freq * t) * math.exp(-t * 12) * 0.6
        # Metallic noise transient
        noise = (rng.random() * 2 - 1) * math.exp(-t * 25) * 0.4
        # Heavy meat/armor impact
        impact = math.sin(2 * math.pi * 85 * t) * math.exp(-t * 8) * 0.5 if t > 0.05 else 0.0
        s = blade + noise + impact
        out_l[i] = s * (0.8 + 0.2 * math.sin(t * 10))
        out_r[i] = s * (0.9 - 0.2 * math.sin(t * 10))
    return out_l, out_r

def synth_sfx_shield() -> tuple[list[float], list[float]]:
    duration = 0.55
    n = int(SAMPLE_RATE * duration)
    out_l = [0.0] * n
    out_r = [0.0] * n
    # Metallic clang: 480Hz, 820Hz, 1450Hz
    partials = [(480, 0.45, 10.0), (820, 0.35, 14.0), (1450, 0.25, 20.0), (220, 0.5, 6.0)]
    rng = random.Random(404)
    for i in range(n):
        t = i / SAMPLE_RATE
        val = 0.0
        for f, amp, dec in partials:
            val += math.sin(2 * math.pi * f * t) * amp * math.exp(-t * dec)
        # Heavy clang impact
        clang = (rng.random() * 2 - 1) * math.exp(-t * 40) * 0.4
        s = (val + clang) * 0.8
        out_l[i] = s
        out_r[i] = s * 0.92
    return out_l, out_r

def synth_sfx_bell() -> tuple[list[float], list[float]]:
    duration = 2.4
    raw = bell_tone(146.83, duration, 0.8) # D3 bell
    n = len(raw)
    out_l = [0.0] * n
    out_r = [0.0] * n
    for i in range(n):
        t = i / SAMPLE_RATE
        # Rich stereo spread
        out_l[i] = raw[i] * (1.0 + 0.1 * math.sin(2 * math.pi * 1.5 * t))
        out_r[i] = raw[i] * (1.0 - 0.1 * math.sin(2 * math.pi * 1.5 * t))
    return out_l, out_r

def synth_sfx_heal() -> tuple[list[float], list[float]]:
    duration = 0.85
    n = int(SAMPLE_RATE * duration)
    out_l = [0.0] * n
    out_r = [0.0] * n
    # Arpeggio of shimmering notes: D5 (587), F#5 (740), A5 (880), D6 (1175)
    notes = [587.33, 739.99, 880.0, 1174.66]
    for idx, f in enumerate(notes):
        start_t = idx * 0.12
        start_i = int(start_t * SAMPLE_RATE)
        for i in range(start_i, n):
            t = (i - start_i) / SAMPLE_RATE
            env = math.exp(-t * 5.0) * math.sin(min(1.0, t * 20.0) * math.pi * 0.5)
            tone = (math.sin(2 * math.pi * f * t) + 0.3 * math.sin(2 * math.pi * f * 2 * t)) * env * 0.25
            out_l[i] += tone * (0.6 if idx % 2 == 0 else 0.9)
            out_r[i] += tone * (0.9 if idx % 2 == 0 else 0.6)
    return out_l, out_r

def synth_sfx_victory() -> tuple[list[float], list[float]]:
    duration = 2.2
    n = int(SAMPLE_RATE * duration)
    out_l = [0.0] * n
    out_r = [0.0] * n
    # Majestic gothic brass chord (D major - triumphant redemption)
    chord = [146.83, 220.0, 293.66, 369.99, 440.0, 587.33] # D3, A3, D4, F#4, A4, D5
    for i in range(n):
        t = i / SAMPLE_RATE
        env = math.sin(min(1.0, t / 0.4) * math.pi * 0.5) * math.exp(-t * 0.9)
        val = 0.0
        for f in chord:
            # Brass rich harmonics
            val += (math.sin(2 * math.pi * f * t) + 0.5 * math.sin(2 * math.pi * f * 2 * t) + 0.2 * math.sin(2 * math.pi * f * 3 * t)) * 0.12
        out_l[i] = val * env
        out_r[i] = val * env * 0.95
    return out_l, out_r

def synth_sfx_defeat() -> tuple[list[float], list[float]]:
    duration = 2.4
    n = int(SAMPLE_RATE * duration)
    out_l = [0.0] * n
    out_r = [0.0] * n
    # Descending gloomy dissonance (D -> C# -> C -> low drone)
    for i in range(n):
        t = i / SAMPLE_RATE
        freq = 110.0 - t * 25.0
        env = math.sin(min(1.0, t / 0.3) * math.pi * 0.5) * math.exp(-t * 0.8)
        drone = (math.sin(2 * math.pi * freq * t) + 0.6 * math.sin(2 * math.pi * (freq * 0.5) * t)) * env * 0.4
        diss = math.sin(2 * math.pi * (freq * 1.07) * t) * env * 0.2
        s = drone + diss
        out_l[i] = s
        out_r[i] = s * 0.9
    return out_l, out_r

def synth_music_title() -> tuple[list[float], list[float]]:
    """Atmospheric dark fantasy title theme (20 seconds seamless loop)."""
    duration = 20.0
    n = int(SAMPLE_RATE * duration)
    out_l = [0.0] * n
    out_r = [0.0] * n
    
    # 1. Low Cello / Drone (D2: 73.4Hz + A2: 110Hz + D3: 146.8Hz)
    print("Synthesizing Title BGM: Low drone & swells...", flush=True)
    for i in range(n):
        t = i / SAMPLE_RATE
        # Slow breathing envelope for loop
        swell = 0.7 + 0.3 * math.sin(2 * math.pi * (1.0 / duration) * t)
        drone = (
            math.sin(2 * math.pi * 73.41 * t) * 0.28 +
            math.sin(2 * math.pi * 110.0 * t) * 0.18 +
            math.sin(2 * math.pi * 146.83 * t) * 0.14 +
            0.05 * math.sin(2 * math.pi * 220.0 * t)
        ) * swell
        out_l[i] += drone * (0.95 + 0.05 * math.sin(t * 0.5))
        out_r[i] += drone * (0.95 - 0.05 * math.sin(t * 0.5))
        
    # 2. Gothic Minor Chord Progression (D min -> Bb maj -> G min -> A sus/min)
    # 4 bars of 5 seconds each
    chords = [
        # D min (D3, F3, A3, D4)
        ([146.83, 174.61, 220.0, 293.66], 0.0, 5.0),
        # Bb maj (Bb2, D3, F3, Bb3)
        ([116.54, 146.83, 174.61, 233.08], 5.0, 10.0),
        # G min (G2, Bb2, D3, G3)
        ([98.0, 116.54, 146.83, 196.0], 10.0, 15.0),
        # A min (A2, C3, E3, A3)
        ([110.0, 130.81, 164.81, 220.0], 15.0, 20.0),
    ]
    
    for freqs, start_t, end_t in chords:
        start_i = int(start_t * SAMPLE_RATE)
        end_i = int(end_t * SAMPLE_RATE)
        chord_dur = end_t - start_t
        for i in range(start_i, end_i):
            t_chord = (i - start_i) / SAMPLE_RATE
            # Smooth attack and release envelope
            env = math.sin(t_chord / chord_dur * math.pi)
            val = 0.0
            for f in freqs:
                val += (math.sin(2 * math.pi * f * (i / SAMPLE_RATE)) + 0.2 * math.sin(2 * math.pi * f * 2 * (i / SAMPLE_RATE))) * 0.08
            out_l[i] += val * env * 0.85
            out_r[i] += val * env * 1.15

    # 3. Solitary Gothic Bells at t=1.0s and t=11.0s
    print("Synthesizing Title BGM: Distant bells...", flush=True)
    bell_times = [1.0, 11.0]
    for bt in bell_times:
        b_samples = bell_tone(220.0, 6.0, 0.35)
        b_start = int(bt * SAMPLE_RATE)
        for idx in range(len(b_samples)):
            pos = (b_start + idx) % n
            out_l[pos] += b_samples[idx] * 0.7
            out_r[pos] += b_samples[idx] * 0.9
            
    # Soft normalize
    max_amp = max(max(abs(s) for s in out_l), max(abs(s) for s in out_r), 0.01)
    norm = 0.85 / max_amp
    out_l = [s * norm for s in out_l]
    out_r = [s * norm for s in out_r]
    return out_l, out_r

def synth_music_battle() -> tuple[list[float], list[float]]:
    """Driving dark fantasy combat theme (16 seconds seamless loop at 120 BPM = 32 beats)."""
    duration = 16.0
    n = int(SAMPLE_RATE * duration)
    out_l = [0.0] * n
    out_r = [0.0] * n
    
    bpm = 120.0
    beat_sec = 60.0 / bpm # 0.5 sec per beat
    total_beats = 32
    
    print("Synthesizing Battle BGM: War drums & rhythm...", flush=True)
    rng = random.Random(505)
    
    # 1. War Drums (Bass Drum on beats 1, 2.5, 3, 4 of every bar)
    for beat in range(total_beats):
        bar_beat = beat % 4
        # Drum pattern
        drum_triggers = [0.0]
        if bar_beat in [0, 2]:
            drum_triggers.append(0.5) # syncopation
            
        for dt in drum_triggers:
            t_hit = (beat + dt) * beat_sec
            if t_hit >= duration:
                continue
            hit_i = int(t_hit * SAMPLE_RATE)
            drum_len = int(0.4 * SAMPLE_RATE)
            for di in range(drum_len):
                idx = (hit_i + di) % n
                t_d = di / SAMPLE_RATE
                f = 110.0 * math.exp(-t_d * 22) + 38.0
                env = math.exp(-t_d * 9.0)
                d_val = math.sin(2 * math.pi * f * t_d) * env * 0.55
                noise = (rng.random() * 2 - 1) * math.exp(-t_d * 30.0) * 0.15
                s = d_val + noise
                out_l[idx] += s * 0.95
                out_r[idx] += s * 0.95

    # 2. Heavy Cello / Bass Ostinato (16th note rhythmic drive)
    print("Synthesizing Battle BGM: Cello ostinato...", flush=True)
    # Bass notes sequence across 4 bars:
    # Bar 1: D2 (73.4)
    # Bar 2: F2 (87.3)
    # Bar 3: G2 (98.0)
    # Bar 4: A2 (110.0) / C#2
    bar_roots = [73.41, 87.31, 98.0, 110.0]
    total_16ths = total_beats * 4
    step_sec = beat_sec / 4.0 # 0.125s per 16th note
    
    for step in range(total_16ths):
        bar = (step // 16) % 4
        step_in_bar = step % 16
        root = bar_roots[bar]
        # Arpeggiate root and octave/fifth
        note_freq = root if (step_in_bar % 4 != 3) else root * 1.5
        t_step = step * step_sec
        step_i = int(t_step * SAMPLE_RATE)
        step_len = int(0.12 * SAMPLE_RATE)
        for si in range(step_len):
            idx = (step_i + si) % n
            t_s = si / SAMPLE_RATE
            env = math.exp(-t_s * 25.0)
            # Sawtooth-like rich string bass
            tone = (
                math.sin(2 * math.pi * note_freq * t_s) * 0.4 +
                math.sin(2 * math.pi * note_freq * 2 * t_s) * 0.25 +
                math.sin(2 * math.pi * note_freq * 3 * t_s) * 0.12
            ) * env * 0.4
            out_l[idx] += tone * 0.9
            out_r[idx] += tone * 1.1

    # 3. Tense Staccato Chords on Accents (D minor, F major, G minor, A dim)
    chords_battle = [
        ([146.83, 220.0, 261.63, 349.23], 0.0),  # Dm7
        ([174.61, 220.0, 261.63, 349.23], 4.0),  # F
        ([196.0, 233.08, 293.66, 392.0], 8.0),   # Gm
        ([220.0, 277.18, 329.63, 440.0], 12.0),  # A
    ]
    for freqs, start_t in chords_battle:
        # Hit on beats 1, 2.5, 3
        for beat_off in [0.0, 1.5, 2.0]:
            t_stab = start_t + beat_off * beat_sec
            stab_i = int(t_stab * SAMPLE_RATE)
            stab_len = int(0.35 * SAMPLE_RATE)
            for si in range(stab_len):
                idx = (stab_i + si) % n
                t_s = si / SAMPLE_RATE
                env = math.exp(-t_s * 10.0)
                val = 0.0
                for f in freqs:
                    val += (math.sin(2 * math.pi * f * t_s) + 0.4 * math.sin(2 * math.pi * f * 2 * t_s)) * 0.08
                out_l[idx] += val * env
                out_r[idx] += val * env * 0.85

    # Soft normalize
    max_amp = max(max(abs(s) for s in out_l), max(abs(s) for s in out_r), 0.01)
    norm = 0.88 / max_amp
    out_l = [s * norm for s in out_l]
    out_r = [s * norm for s in out_r]
    return out_l, out_r

def main():
    AUDIO_DIR.mkdir(parents=True, exist_ok=True)
    print(f"Generating dark fantasy game audio assets in {AUDIO_DIR}...")
    
    # 1. Music. Edge fade keeps the loop from clicking when it restarts.
    loop_fade = int(SAMPLE_RATE * 0.04)
    l, r = synth_music_title()
    fade_edges(l, loop_fade)
    fade_edges(r, loop_fade)
    write_wav(AUDIO_DIR / "music_title.wav", l, r)
    
    l, r = synth_music_battle()
    fade_edges(l, loop_fade)
    fade_edges(r, loop_fade)
    write_wav(AUDIO_DIR / "music_battle.wav", l, r)
    
    # 2. Sound Effects
    l, r = synth_sfx_click()
    write_wav(AUDIO_DIR / "sfx_click.wav", l, r)
    
    l, r = synth_sfx_card()
    write_wav(AUDIO_DIR / "sfx_card_play.wav", l, r)
    
    l, r = synth_sfx_slash()
    write_wav(AUDIO_DIR / "sfx_slash.wav", l, r)
    
    l, r = synth_sfx_shield()
    write_wav(AUDIO_DIR / "sfx_shield.wav", l, r)
    
    l, r = synth_sfx_bell()
    write_wav(AUDIO_DIR / "sfx_bell.wav", l, r)
    
    l, r = synth_sfx_heal()
    write_wav(AUDIO_DIR / "sfx_heal.wav", l, r)
    
    l, r = synth_sfx_victory()
    write_wav(AUDIO_DIR / "sfx_victory.wav", l, r)
    
    l, r = synth_sfx_defeat()
    write_wav(AUDIO_DIR / "sfx_defeat.wav", l, r)
    
    print("\nALL AUDIO ASSETS SUCCESSFULLY GENERATED!")

if __name__ == "__main__":
    main()
