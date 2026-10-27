"""Synthesises every sound effect and music loop for Haze Royale.

No samples or downloads: everything is generated from maths, so the audio is
original, license-free and tiny (22.05 kHz mono WAV, ~2 MB in total).

    python tool/gen_audio.py        # writes assets/audio/*.wav

Needs numpy. Re-run after changing a sound; output is deterministic.
"""
import os
import wave

import numpy as np

SR = 22050
OUT = os.path.join(os.path.dirname(__file__), '..', 'assets', 'audio')
rng = np.random.default_rng(2025)


# ----------------------------------------------------------------- building blocks

def secs(d):
    return np.arange(int(d * SR)) / SR


def env(n, attack=0.005, decay=0.1, sustain=0.0, release=None):
    """Attack then exponential decay (time constant `decay`)."""
    t = np.arange(n) / SR
    e = np.exp(-np.maximum(t - attack, 0) / max(decay, 1e-4))
    e = e * (1 - sustain) + sustain
    a = int(attack * SR)
    if a > 0:
        e[:a] *= np.linspace(0, 1, a)
    if release:
        r = min(int(release * SR), n)
        e[-r:] *= np.linspace(1, 0, r)
    return e


def sweep(f0, f1, dur, shape='sine', curve='exp'):
    n = int(dur * SR)
    if curve == 'exp':
        f = f0 * (f1 / f0) ** np.linspace(0, 1, n)
    else:
        f = np.linspace(f0, f1, n)
    ph = 2 * np.pi * np.cumsum(f) / SR
    return wavefn(ph, shape)


def tone(freq, dur, shape='sine'):
    ph = 2 * np.pi * freq * secs(dur)
    return wavefn(ph, shape)


def wavefn(ph, shape):
    if shape == 'sine':
        return np.sin(ph)
    if shape == 'tri':
        return 2 / np.pi * np.arcsin(np.sin(ph))
    if shape == 'saw':
        return 2 * ((ph / (2 * np.pi)) % 1) - 1
    if shape == 'square':
        return np.sign(np.sin(ph))
    raise ValueError(shape)


def noise(dur):
    return rng.uniform(-1, 1, int(dur * SR))


def band(x, lo, hi):
    """Band-pass with soft edges, via FFT."""
    spec = np.fft.rfft(x)
    f = np.fft.rfftfreq(len(x), 1 / SR)
    mask = 1 / (1 + (lo / np.maximum(f, 1)) ** 4) / (1 + (f / hi) ** 4)
    return np.fft.irfft(spec * mask, len(x))


def lowpass(x, cut):
    return band(x, 1, cut)


def highpass(x, cut):
    return band(x, cut, SR / 2)


def mix(length, *parts):
    """parts: (signal, start_seconds, gain)."""
    out = np.zeros(int(length * SR))
    for sig, start, gain in parts:
        i = int(start * SR)
        j = min(len(out), i + len(sig))
        if j > i:
            out[i:j] += sig[: j - i] * gain
    return out


def write(name, x, peak=0.9, fade=True):
    x = np.asarray(x, dtype=np.float64)
    m = np.max(np.abs(x)) or 1
    x = x / m * peak
    # 3 ms fade in/out avoids clicks.
    f = min(len(x) // 4, int(0.003 * SR)) if fade else 0
    if f:
        x[:f] *= np.linspace(0, 1, f)
        x[-f:] *= np.linspace(1, 0, f)
    data = (np.clip(x, -1, 1) * 32767).astype('<i2').tobytes()
    path = os.path.join(OUT, name + '.wav')
    with wave.open(path, 'wb') as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(data)
    return path


def note(name):
    """'A4', 'C#5' -> Hz."""
    names = {'C': -9, 'D': -7, 'E': -5, 'F': -4, 'G': -2, 'A': 0, 'B': 2}
    semi = names[name[0]]
    rest = name[1:]
    if rest.startswith('#'):
        semi += 1
        rest = rest[1:]
    elif rest.startswith('b'):
        semi -= 1
        rest = rest[1:]
    return 440 * 2 ** ((semi + (int(rest) - 4) * 12) / 12)


# ----------------------------------------------------------------- instruments

def bell(freq, dur, bright=1.0):
    """Gamelan-ish metallophone: inharmonic partials with different decays."""
    t = secs(dur)
    partials = [(1.0, 1.0, 1.2), (2.0, 0.45 * bright, 0.6), (2.76, 0.35 * bright, 0.35), (4.07, 0.2 * bright, 0.2)]
    out = np.zeros_like(t)
    for ratio, amp, dec in partials:
        out += amp * np.sin(2 * np.pi * freq * ratio * t) * np.exp(-t / (dec * dur))
    a = int(0.004 * SR)
    out[:a] *= np.linspace(0, 1, a)
    return out


def pluck(freq, dur, brightness=0.6):
    """Plucked string (gambus / sape vibe): harmonics that die away faster when higher."""
    t = secs(dur)
    out = np.zeros_like(t)
    for h in range(1, 8):
        amp = brightness ** (h - 1) / h ** 0.5
        out += amp * np.sin(2 * np.pi * freq * h * t + h) * np.exp(-t * (2.2 + h * 1.6))
    a = int(0.003 * SR)
    out[:a] *= np.linspace(0, 1, a)
    return out


def drum_dum(dur=0.35):
    """Kompang open tone: pitched membrane thump."""
    body = sweep(150, 70, dur) * env(int(dur * SR), 0.002, 0.11)
    slap = lowpass(noise(dur), 900) * env(int(dur * SR), 0.001, 0.02)
    return body + 0.5 * slap


def drum_tak(dur=0.18):
    """Kompang slap: bright skin crack."""
    n = int(dur * SR)
    crack = band(noise(dur), 900, 6000) * env(n, 0.001, 0.025)
    ring = tone(620, dur) * env(n, 0.001, 0.04)
    return crack + 0.35 * ring


def shaker(dur=0.06):
    return highpass(noise(dur), 5000) * env(int(dur * SR), 0.004, 0.018)


def gong(freq=65, dur=4.0):
    t = secs(dur)
    out = np.sin(2 * np.pi * freq * t) + 0.5 * np.sin(2 * np.pi * freq * 2.01 * t) + 0.25 * np.sin(2 * np.pi * freq * 3.2 * t)
    wob = 1 + 0.15 * np.sin(2 * np.pi * 3.5 * t)
    return out * wob * np.exp(-t / 1.6) * np.minimum(1, t / 0.02)


# ----------------------------------------------------------------- sound effects

def water_squirt(dur, lo, hi, f0, f1, pew_gain):
    n = int(dur * SR)
    hiss = band(noise(dur), lo, hi) * env(n, 0.002, dur * 0.28)
    pew = sweep(f0, f1, dur) * env(n, 0.001, dur * 0.3)
    drip = mix(dur, (sweep(1800, 2600, 0.05) * env(int(0.05 * SR), 0.001, 0.015), dur * 0.55, 0.25))
    return hiss + pew_gain * pew + drip


def sfx():
    write('shot_pistol', water_squirt(0.16, 1500, 6500, 1400, 620, 0.55))
    write('shot_rifle', water_squirt(0.2, 2200, 8000, 1900, 760, 0.45) + 0.3 * mix(0.2, (drum_tak(0.08), 0, 0.5)))

    # Bubble launcher: a fat "bloop" with bubbles.
    d = 0.45
    n = int(d * SR)
    bloop = sweep(420, 110, d) * (1 + 0.25 * np.sin(2 * np.pi * 18 * secs(d))) * env(n, 0.004, 0.13)
    fwump = lowpass(noise(d), 600) * env(n, 0.002, 0.05)
    bubbles = mix(d, *[(sweep(f, f * 1.6, 0.04) * env(int(0.04 * SR), 0.001, 0.012), s, 0.25)
                       for f, s in [(700, 0.12), (900, 0.18), (650, 0.24), (1100, 0.3)]])
    write('shot_launcher', bloop + 0.6 * fwump + bubbles)

    # Splash: body of water + flung droplets.
    d = 0.75
    n = int(d * SR)
    body = lowpass(noise(d), 2600) * env(n, 0.004, 0.16)
    hiss = band(noise(d), 3000, 9000) * env(n, 0.002, 0.07)
    drops = mix(d, *[(sweep(f, f * 1.5, 0.045) * env(int(0.045 * SR), 0.001, 0.014), s, 0.3)
                     for f, s in zip(rng.uniform(700, 2200, 9), rng.uniform(0.05, 0.6, 9))])
    write('splash', body + 0.6 * hiss + drops)

    # Hit: wet slap on a target.
    d = 0.2
    n = int(d * SR)
    write('hit', band(noise(d), 400, 3500) * env(n, 0.001, 0.03) + 0.9 * sweep(160, 70, d) * env(n, 0.001, 0.05))

    # Player hurt: deeper thud with a short wobble.
    d = 0.3
    n = int(d * SR)
    thud = sweep(120, 55, d) * env(n, 0.001, 0.09)
    slap = band(noise(d), 300, 2500) * env(n, 0.001, 0.035)
    wob = sweep(330, 220, d, 'tri') * env(n, 0.01, 0.07) * 0.3
    write('hurt', thud + 0.7 * slap + wob)

    # Tagged out: slide whistle down + splash.
    d = 0.95
    n = int(d * SR)
    slide = sweep(950, 190, d, 'tri') * (1 + 0.08 * np.sin(2 * np.pi * 7 * secs(d))) * env(n, 0.01, 0.4, release=0.1)
    write('tag_out', slide + 0.5 * lowpass(noise(d), 2000) * env(n, 0.002, 0.12))

    # Pickup: bright rising pentatonic sparkle.
    parts = [(bell(note(x), 0.3, 1.2), i * 0.06, 1.0) for i, x in enumerate(['C6', 'E6', 'G6'])]
    write('pickup', mix(0.45, *parts), 0.8)

    # Reload: two mechanical clicks.
    def click(d=0.05):
        k = int(d * SR)
        return highpass(noise(d), 2500) * env(k, 0.0005, 0.006) + 0.4 * tone(2400, d) * env(k, 0.0005, 0.01)
    write('reload', mix(0.32, (click(), 0.0, 1.0), (click(), 0.2, 1.1)), 0.7)

    # Plant: soft leafy rustle + rising chime.
    d = 0.9
    n = int(d * SR)
    rustle = band(noise(d), 2000, 7000) * (0.5 + 0.5 * np.sin(2 * np.pi * 9 * secs(d))) * env(n, 0.05, 0.25)
    chime = mix(d, *[(bell(note(x), 0.4, 0.8), 0.15 + i * 0.09, 0.8) for i, x in enumerate(['G5', 'A5', 'C6', 'D6', 'E6'])])
    write('plant', 0.4 * rustle + chime, 0.8)

    # Mine: a block takes a hit and crumbles.
    d = 0.26
    n = int(d * SR)
    crunch = band(noise(d), 260, 4200) * env(n, 0.001, 0.045)
    thud = sweep(190, 80, d) * env(n, 0.001, 0.055)
    grit = mix(d, *[(highpass(noise(0.03), 3000) * env(int(0.03 * SR), 0.001, 0.009), s, 0.5)
                    for s in (0.05, 0.1, 0.16)])
    write('mine', crunch + 0.8 * thud + 0.6 * grit, 0.8)

    # Place: a block set down, woody knock with a short tail.
    d = 0.2
    n = int(d * SR)
    knock = tone(300, d, 'tri') * env(n, 0.001, 0.03)
    tap = band(noise(d), 700, 5200) * env(n, 0.0008, 0.016)
    write('place', knock + 0.7 * tap + 0.4 * sweep(520, 300, d) * env(n, 0.001, 0.025), 0.75)

    # Craft: workbench clack then a satisfied two-note pluck.
    d = 0.7
    parts = [(band(noise(0.08), 500, 4000) * env(int(0.08 * SR), 0.001, 0.02), 0.0, 0.7),
             (pluck(note('E5'), 0.35), 0.08, 0.9),
             (pluck(note('B5'), 0.4), 0.2, 0.8),
             (shaker(), 0.3, 0.5)]
    write('craft', mix(d, *parts), 0.8)

    # Haze warning: low two-tone horn.
    d = 1.7
    horn = np.zeros(int(d * SR))
    for i, f in enumerate([220, 175, 220, 175]):
        seg = lowpass(tone(f, 0.42, 'saw') + 0.5 * tone(f * 1.005, 0.42, 'saw'), 900) * env(int(0.42 * SR), 0.03, 1.0, 1.0, 0.06)
        s = int(i * 0.42 * SR)
        horn[s:s + len(seg)] += seg[: len(horn) - s]
    write('haze_warning', horn, 0.75)

    # UI tick.
    d = 0.06
    write('ui_click', tone(1800, d) * env(int(d * SR), 0.0005, 0.012) + 0.3 * highpass(noise(d), 4000) * env(int(d * SR), 0.0005, 0.005), 0.6)

    # Win: pentatonic fanfare with kompang.
    seq = ['C5', 'E5', 'G5', 'A5', 'C6']
    parts = [(pluck(note(x), 0.5, 0.7), i * 0.13, 0.9) for i, x in enumerate(seq)]
    parts += [(bell(note(x), 1.6), 0.7, 0.5) for x in ['C5', 'E5', 'G5', 'C6']]
    parts += [(drum_dum(), 0.0, 0.6), (drum_tak(), 0.26, 0.5), (drum_dum(), 0.52, 0.6), (drum_tak(), 0.7, 0.6)]
    write('win', mix(2.4, *parts), 0.85)

    # Lose: gentle descending phrase.
    seq = [('G4', 0.0), ('F4', 0.3), ('D#4', 0.6), ('C4', 0.9)]
    parts = []
    for x, s in seq:
        dd = 0.9 if x == 'C4' else 0.35
        v = tone(note(x), dd, 'tri') * (1 + 0.03 * np.sin(2 * np.pi * 5 * secs(dd))) * env(int(dd * SR), 0.02, dd * 0.5, release=0.08)
        parts.append((v, s, 0.8))
    parts.append((gong(98, 1.8), 0.9, 0.35))
    write('lose', mix(2.0, *parts), 0.8)


# ----------------------------------------------------------------- music
#
# Music is laid out on an exact integer-sample grid: every note starts at
# k * step samples, and the loop length is a whole number of steps, so the
# drums, bass and melody stay locked together and the loop point is seamless.

def place(out, sig, at, gain):
    """Adds sig into out at sample index `at`, wrapping past the end (loop)."""
    n = len(out)
    sig = sig * gain
    end = at + len(sig)
    if end <= n:
        out[at:end] += sig
    else:
        first = n - at
        out[at:] += sig[:first]
        rest = sig[first:]
        while len(rest):  # wrap tails into the start of the loop
            k = min(len(rest), n)
            out[:k] += rest[:k]
            rest = rest[k:]


def music_menu():
    beat = 17408                     # samples per beat (~76 bpm at 22.05 kHz)
    bars = 8
    out = np.zeros(bars * 4 * beat)
    b_s = beat / SR
    # Slendro-like pentatonic around C.
    scale = ['C5', 'D5', 'F5', 'G5', 'A5', 'C6', 'D6']
    melody = [0, 2, 3, 4, 3, 2, 0, -1,  2, 3, 4, 6, 5, 4, 3, -1,
              4, 5, 4, 3, 2, 3, 2, 0,  1, 2, 3, 2, 1, 0, -1, -1]
    for i, m in enumerate(melody):
        if m < 0:
            continue
        place(out, bell(note(scale[m]), b_s * 1.8, 0.9), i * beat, 0.55)
        place(out, bell(note(scale[m]) * 2, b_s * 1.0, 0.5), i * beat, 0.10)  # octave shimmer, same time
    for b in range(bars):
        place(out, gong(65.4 if b % 2 == 0 else 73.4, b_s * 4), b * 4 * beat, 0.5)
    t = np.arange(len(out)) / SR
    length = len(out) / SR
    pad = (np.sin(2 * np.pi * note('C3') * t) + 0.6 * np.sin(2 * np.pi * note('G3') * t)) * (
        0.6 + 0.4 * np.sin(2 * np.pi * t / length * 2))
    out += pad * 0.12
    write('music_menu', out, 0.7, fade=False)


def music_match():
    step = 2756                      # samples per 16th note (120 bpm at 22.05 kHz)
    bars = 8
    out = np.zeros(bars * 16 * step)
    st = step / SR
    # Kompang pattern (16 steps per bar).
    dum = {0: 1.0, 6: 0.8, 8: 0.9, 11: 0.7}
    tak = {4: 1.0, 12: 1.0, 14: 0.6}
    for b in range(bars):
        for s16 in range(16):
            at = (b * 16 + s16) * step
            if s16 in dum:
                place(out, drum_dum(), at, 0.55 * dum[s16])
            if s16 in tak:
                place(out, drum_tak(), at, 0.45 * tak[s16])
            if s16 % 2 == 1:
                place(out, shaker(), at, 0.10)
    # Bass line (A minor pentatonic), eighth notes.
    roots = ['A2', 'A2', 'C3', 'G2', 'A2', 'A2', 'D3', 'E3']
    for b, r in enumerate(roots):
        f = note(r)
        for e in range(8):
            ff = f * (2 if e in (3, 7) else 1)
            place(out, pluck(ff, st * 2.2, 0.35), (b * 16 + e * 2) * step, 0.5 if e % 2 == 0 else 0.35)
    # Plucked lead melody, eighth notes.
    scale = ['A4', 'C5', 'D5', 'E5', 'G5', 'A5', 'C6']
    phrase_a = [5, -1, 4, 3, 4, -1, 3, 1, 2, -1, 1, 0, 1, -1, -1, -1]
    phrase_b = [3, 4, 5, -1, 6, 5, 4, -1, 3, 4, 3, 1, 0, -1, -1, -1]
    lead = (phrase_a + phrase_b) * 2
    for i, m in enumerate(lead):
        if m < 0:
            continue
        place(out, pluck(note(scale[m]), st * 3.2, 0.65), i * 2 * step, 0.36)
    write('music_match', out, 0.72, fade=False)


if __name__ == '__main__':
    os.makedirs(OUT, exist_ok=True)
    sfx()
    music_menu()
    music_match()
    total = 0
    for f in sorted(os.listdir(OUT)):
        size = os.path.getsize(os.path.join(OUT, f))
        total += size
        print(f'{f:22s} {size / 1024:8.1f} KB')
    print(f'{"total":22s} {total / 1024:8.1f} KB')
