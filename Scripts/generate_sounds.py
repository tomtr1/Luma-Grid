"""Synthesizes LumaGrid's original sound effects (soft sine/bell tones). Output: 16-bit mono WAV."""
import numpy as np, wave, sys, os
SR = 44100
out = sys.argv[1]
os.makedirs(out, exist_ok=True)

def env(n, attack=0.005, release=0.12):
    t = np.arange(n) / SR
    a = np.clip(t / attack, 0, 1)
    r = np.exp(-t / release)
    return a * r

def tone(freq, dur, amp=0.5, release=0.12, harmonics=((1, 1.0), (2, 0.25), (3, 0.08))):
    n = int(SR * dur)
    t = np.arange(n) / SR
    s = sum(w * np.sin(2 * np.pi * freq * h * t) for h, w in harmonics)
    return amp * s * env(n, release=release)

def seq(parts):
    """parts: (signal, seconds until the next note starts)."""
    starts, pos = [], 0
    for sig, step in parts:
        starts.append(pos)
        pos += int(SR * step)
    total = max(st + len(sig) for st, (sig, _) in zip(starts, parts))
    buf = np.zeros(total)
    for st, (sig, _) in zip(starts, parts):
        buf[st:st + len(sig)] += sig
    return buf

def write(name, sig):
    sig = sig / max(1e-9, np.max(np.abs(sig))) * 0.6
    # fade tail to avoid clicks
    tail = min(len(sig), 400)
    sig[-tail:] *= np.linspace(1, 0, tail)
    data = (sig * 32767).astype(np.int16)
    with wave.open(os.path.join(out, name + ".wav"), "wb") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR); w.writeframes(data.tobytes())

write("place", tone(520, 0.12, release=0.04, harmonics=((1, 1.0), (2, 0.15))))
write("invalid", tone(180, 0.14, release=0.05, harmonics=((1, 1.0), (1.5, 0.3))))
write("clear", seq([(tone(660, 0.25, release=0.10), 0.06), (tone(880, 0.3, release=0.14), 0.0)]))
write("combo", seq([(tone(660, 0.2, release=0.08), 0.05), (tone(830, 0.2, release=0.08), 0.05), (tone(990, 0.35, release=0.18), 0.0)]))
write("charge", seq([(tone(1046, 0.3, amp=0.4, release=0.15, harmonics=((1, 1.0), (2.76, 0.3), (5.4, 0.1))), 0.0)]))
write("pulse", seq([(tone(392, 0.5, release=0.25), 0.04), (tone(587, 0.5, release=0.25), 0.04), (tone(784, 0.6, release=0.3), 0.0)]))
write("gameover", seq([(tone(523, 0.3, release=0.15), 0.12), (tone(440, 0.3, release=0.15), 0.12), (tone(349, 0.6, release=0.3), 0.0)]))
print("ok")
