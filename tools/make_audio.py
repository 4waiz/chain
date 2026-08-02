"""Generates every sound effect and the music bed for Chain Reaction City.

All audio is synthesised from scratch here, so the game ships with no
third-party samples and no licensing questions: the source of truth for every
sound is this file.

The palette is deliberately soft and toy-like to match the art — wooden clicks,
plastic knocks, little bell tones, gentle whooshes. Nothing harsh, nothing
cinematic.

Run:  python tools/make_audio.py
"""

import math
import os
import struct
import wave

import numpy as np

SR = 22050
REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(REPO, "assets", "audio")

rng = np.random.default_rng(20260803)  # fixed seed: builds are reproducible


# ------------------------------------------------------------------ helpers
def t(dur):
    return np.linspace(0, dur, int(SR * dur), endpoint=False)


def env(x, attack=0.005, decay=0.25, power=2.0):
    """Percussive envelope: near-instant attack, exponential-ish decay."""
    n = len(x)
    a = max(1, int(SR * attack))
    e = np.ones(n)
    e[:a] = np.linspace(0, 1, a)
    d = np.linspace(0, 1, n - a) if n > a else np.zeros(0)
    e[a:] = (1 - d) ** power
    return x * e


def sine(freq, dur, phase=0.0):
    return np.sin(2 * np.pi * freq * t(dur) + phase)


def sweep(f0, f1, dur, kind="exp"):
    x = t(dur)
    if kind == "exp":
        f = f0 * (f1 / f0) ** (x / max(1e-6, dur))
    else:
        f = np.linspace(f0, f1, len(x))
    return np.sin(2 * np.pi * np.cumsum(f) / SR)


def noise(dur):
    return rng.uniform(-1, 1, int(SR * dur))


def lowpass(x, cutoff):
    """One-pole low pass — enough to take the fizz off noise."""
    a = math.exp(-2 * math.pi * cutoff / SR)
    y = np.empty_like(x)
    acc = 0.0
    for i in range(len(x)):
        acc = a * acc + (1 - a) * x[i]
        y[i] = acc
    return y


def highpass(x, cutoff):
    return x - lowpass(x, cutoff)


def mix(*parts):
    n = max(len(p) for p in parts)
    out = np.zeros(n)
    for p in parts:
        out[: len(p)] += p
    return out


def pad(x, dur):
    n = int(SR * dur)
    if len(x) >= n:
        return x[:n]
    return np.concatenate([x, np.zeros(n - len(x))])


def normalise(x, peak=0.85):
    m = np.max(np.abs(x))
    if m < 1e-9:
        return x
    return x / m * peak


def save(name, x, peak=0.85):
    x = normalise(np.asarray(x, dtype=np.float64), peak)
    # Short fade at both ends so nothing clicks on loop or cut-off.
    f = min(120, len(x) // 8)
    if f > 1:
        x[:f] *= np.linspace(0, 1, f)
        x[-f:] *= np.linspace(1, 0, f)
    data = (np.clip(x, -1, 1) * 32767).astype("<i2")
    os.makedirs(OUT, exist_ok=True)
    path = os.path.join(OUT, f"{name}.wav")
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(data.tobytes())
    return path, len(data)


# ------------------------------------------------------------------- sounds
def ui_tap():
    # Soft wooden tick: two quick partials plus a whisper of noise.
    return mix(
        env(sine(880, 0.07), 0.001, 0.07, 3.0) * 0.5,
        env(sine(1320, 0.05), 0.001, 0.05, 3.5) * 0.25,
        env(lowpass(noise(0.03), 3000), 0.001, 0.03, 3.0) * 0.2,
    )


def button_press():
    return mix(
        env(sweep(700, 420, 0.10), 0.001, 0.10, 2.2) * 0.6,
        env(sine(240, 0.14), 0.002, 0.14, 2.5) * 0.35,
        env(lowpass(noise(0.05), 2200), 0.001, 0.05, 2.0) * 0.18,
    )


def cannon_fire():
    # A toy pop, not artillery: low thump, air puff, tiny whistle.
    body = env(sweep(180, 60, 0.30), 0.002, 0.30, 1.6) * 0.9
    air = env(lowpass(noise(0.35), 1400), 0.004, 0.35, 1.4) * 0.5
    pop = env(sine(520, 0.08), 0.001, 0.08, 3.0) * 0.35
    return mix(body, air, pop)


def ball_roll():
    # Loopable rumble.
    d = 0.9
    n = lowpass(noise(d), 700) * 0.6
    wob = (1 + 0.25 * np.sin(2 * np.pi * 7 * t(d)))
    return n * wob


def domino_impact():
    # Hollow plastic knock.
    return mix(
        env(sine(430, 0.11), 0.001, 0.11, 3.0) * 0.55,
        env(sine(660, 0.07), 0.001, 0.07, 3.5) * 0.3,
        env(highpass(lowpass(noise(0.05), 5000), 700), 0.001, 0.05, 3.0) * 0.35,
    )


def toy_car():
    d = 0.8
    hum = sine(120, d) * 0.35 + sine(181, d) * 0.18
    rattle = lowpass(noise(d), 900) * 0.25
    return (hum + rattle) * (1 + 0.15 * np.sin(2 * np.pi * 5.5 * t(d)))


def spring():
    return env(sweep(280, 1500, 0.22), 0.002, 0.22, 1.5) * 0.8


def fan():
    d = 1.0
    return lowpass(noise(d), 1100) * (0.5 + 0.12 * np.sin(2 * np.pi * 11 * t(d)))


def balloon():
    return mix(
        env(sweep(1600, 300, 0.09), 0.001, 0.09, 2.6) * 0.7,
        env(highpass(noise(0.10), 1500), 0.001, 0.10, 2.4) * 0.5,
    )


def bridge_move():
    d = 0.7
    creak = sine(150, d) * 0.3 + sine(226, d) * 0.15
    wobble = 1 + 0.35 * np.sin(2 * np.pi * 3.5 * t(d))
    return env(creak * wobble, 0.03, d, 1.1) + env(lowpass(noise(d), 500), 0.03, d, 1.2) * 0.3


def gears():
    d = 0.9
    x = t(d)
    clicks = np.zeros(len(x))
    step = int(SR * 0.075)
    for i in range(0, len(x) - step, step):
        clicks[i:i + int(SR * 0.02)] += np.linspace(1, 0, int(SR * 0.02)) ** 2
    return clicks * (0.5 + 0.5 * np.sin(2 * np.pi * 300 * x)) * 0.8


def magnet():
    return env(sweep(90, 340, 0.45), 0.02, 0.45, 1.3) * 0.7


def electricity():
    d = 0.35
    buzz = np.sign(np.sin(2 * np.pi * 90 * t(d))) * 0.3
    fizz = highpass(noise(d), 3000) * 0.5
    return env(buzz + fizz, 0.002, d, 2.0)


def glass_break():
    parts = [env(sine(2200 + i * 700, 0.22), 0.001, 0.22, 2.6) * (0.30 - i * 0.05)
             for i in range(5)]
    return mix(env(highpass(noise(0.30), 2500), 0.001, 0.30, 1.8) * 0.6, *parts)


def block_break():
    return mix(
        env(sine(190, 0.24), 0.002, 0.24, 2.2) * 0.6,
        env(lowpass(noise(0.26), 1800), 0.002, 0.26, 1.9) * 0.7,
        env(sine(380, 0.12), 0.001, 0.12, 3.0) * 0.3,
    )


def water_splash():
    d = 0.45
    return mix(
        env(lowpass(noise(d), 2400), 0.004, d, 1.6) * 0.8,
        env(sweep(900, 320, 0.25), 0.004, 0.25, 2.0) * 0.3,
    )


def bell():
    # Struck bell: inharmonic partials, long ring.
    d = 1.6
    ratios = (1.0, 2.01, 2.98, 4.07, 5.43)
    gains = (0.55, 0.30, 0.20, 0.12, 0.07)
    parts = [env(sine(660 * r, d), 0.001, d, 1.0 + i * 0.35) * g
             for i, (r, g) in enumerate(zip(ratios, gains))]
    return mix(*parts)


def flag():
    d = 0.55
    return mix(
        env(sweep(300, 900, d), 0.01, d, 1.4) * 0.45,
        env(lowpass(noise(d), 1600), 0.01, d, 1.6) * 0.35,
    )


def chest_open():
    return mix(
        env(sweep(200, 520, 0.35), 0.01, 0.35, 1.5) * 0.5,
        pad(np.concatenate([np.zeros(int(SR * 0.22)),
                            env(sine(1046, 0.5), 0.002, 0.5, 1.4) * 0.4]), 0.75),
    )


def _arp(freqs, note=0.11, dur_each=0.22, gain=0.5):
    total = note * (len(freqs) - 1) + dur_each
    out = np.zeros(int(SR * total) + 8)
    for i, f in enumerate(freqs):
        seg = env(sine(f, dur_each) * 0.7 + sine(f * 2, dur_each) * 0.2,
                  0.004, dur_each, 1.8)
        s = int(SR * note * i)
        out[s:s + len(seg)] += seg * gain
    return out


def success():
    return _arp([523.25, 659.25, 783.99], note=0.085, dur_each=0.28)


def failure():
    return _arp([392.0, 349.23, 293.66], note=0.11, dur_each=0.34, gain=0.42)


def star_reward():
    return _arp([880, 1108.7, 1318.5], note=0.06, dur_each=0.30, gain=0.42)


def level_complete():
    return _arp([523.25, 659.25, 783.99, 1046.5], note=0.10, dur_each=0.55, gain=0.5)


def city_upgrade():
    return _arp([392.0, 523.25, 659.25, 783.99], note=0.12, dur_each=0.6, gain=0.45)


def fireworks():
    out = np.zeros(int(SR * 1.4))
    for i, delay in enumerate((0.0, 0.22, 0.46, 0.72)):
        burst = mix(
            env(highpass(noise(0.45), 1800), 0.002, 0.45, 1.7) * 0.55,
            env(sweep(1400 - i * 180, 300, 0.28), 0.002, 0.28, 2.2) * 0.35,
        )
        s = int(SR * delay)
        out[s:s + len(burst)] += burst[: len(out) - s]
    return out


def coin_pickup():
    return _arp([1318.5, 1760.0], note=0.05, dur_each=0.18, gain=0.45)


def whoosh():
    d = 0.35
    return env(lowpass(noise(d), 1500) * (1 + np.linspace(0, 1.6, int(SR * d))),
               0.02, d, 1.6) * 0.6


def music_loop():
    """A light, unobtrusive 8-bar loop in C major — soft marimba-ish plucks
    over a gentle bass, mixed low so it sits under the sound effects."""
    bpm = 96
    beat = 60.0 / bpm
    bars = 8
    dur = beat * 4 * bars
    out = np.zeros(int(SR * dur) + 16)

    melody = [
        (0, 523.25, 1.0), (1, 659.25, 1.0), (2, 783.99, 1.0), (3, 659.25, 1.0),
        (4, 587.33, 1.0), (5, 783.99, 1.0), (6, 880.00, 1.5), (8, 783.99, 1.0),
        (9, 659.25, 1.0), (10, 523.25, 1.5), (12, 587.33, 1.0), (13, 659.25, 1.0),
        (14, 523.25, 2.0),
    ]
    bass = [(0, 130.81), (4, 174.61), (8, 196.00), (12, 130.81)]

    for rep in range(2):
        off = rep * beat * 16
        for b, f, ln in melody:
            d = beat * ln * 0.9
            seg = env(sine(f, d) * 0.6 + sine(f * 2, d) * 0.18 + sine(f * 3, d) * 0.06,
                      0.006, d, 2.4)
            s = int(SR * (off + b * beat))
            if s + len(seg) < len(out):
                out[s:s + len(seg)] += seg * 0.20
        for b, f in bass:
            d = beat * 3.6
            seg = env(sine(f, d) * 0.7 + sine(f * 2, d) * 0.12, 0.02, d, 1.5)
            s = int(SR * (off + b * beat))
            if s + len(seg) < len(out):
                out[s:s + len(seg)] += seg * 0.16

    return out


SOUNDS = {
    "ui_tap": ui_tap, "button_press": button_press, "cannon_fire": cannon_fire,
    "ball_roll": ball_roll, "domino_impact": domino_impact, "toy_car": toy_car,
    "spring": spring, "fan": fan, "balloon": balloon, "bridge_move": bridge_move,
    "gears": gears, "magnet": magnet, "electricity": electricity,
    "glass_break": glass_break, "block_break": block_break,
    "water_splash": water_splash, "bell": bell, "flag": flag,
    "chest_open": chest_open, "success": success, "failure": failure,
    "star_reward": star_reward, "level_complete": level_complete,
    "city_upgrade": city_upgrade, "fireworks": fireworks,
    "coin_pickup": coin_pickup, "whoosh": whoosh,
}


def main():
    total = 0
    for name, fn in SOUNDS.items():
        path, n = save(name, fn())
        total += os.path.getsize(path)
        print(f"{name:18s} {n/SR:5.2f}s  {os.path.getsize(path)/1024:6.1f} KB")
    path, n = save("music_loop", music_loop(), peak=0.55)
    total += os.path.getsize(path)
    print(f"{'music_loop':18s} {n/SR:5.2f}s  {os.path.getsize(path)/1024:6.1f} KB")
    print(f"\n{len(SOUNDS)+1} files, {total/1024:.0f} KB total")


if __name__ == "__main__":
    main()
