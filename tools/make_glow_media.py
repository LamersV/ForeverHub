"""Generates ForeverHub's glow textures (original art) as 32-bit TGA files.

White shapes on alpha: the addon tints them with SetVertexColor. Run:
    python tools/make_glow_media.py Glow/Media
"""
import math
import os
import random
import struct
import sys

OUT = sys.argv[1]
os.makedirs(OUT, exist_ok=True)


def clamp(v, lo=0.0, hi=1.0):
    return lo if v < lo else hi if v > hi else v


def smooth(e0, e1, x):
    t = clamp((x - e0) / (e1 - e0))
    return t * t * (3 - 2 * t)


def write(name, w, h, pixel):
    """pixel(u, v) -> (r, g, b, a) floats 0..1; u, v in -1..1 (v up)."""
    data = bytearray()
    for j in range(h):
        v = 1 - (j + 0.5) / h * 2
        for i in range(w):
            u = (i + 0.5) / w * 2 - 1
            r, g, b, a = pixel(u, v)
            data += bytes((int(clamp(b) * 255 + 0.5), int(clamp(g) * 255 + 0.5),
                           int(clamp(r) * 255 + 0.5), int(clamp(a) * 255 + 0.5)))
    header = struct.pack("<BBBHHBHHHHBB", 0, 0, 2, 0, 0, 0, 0, 0, w, h, 32, 0x28)
    with open(os.path.join(OUT, name + ".tga"), "wb") as f:
        f.write(header + data)
    print(name, w, h)


def white(alpha_fn):
    def pixel(u, v):
        return 1, 1, 1, alpha_fn(u, v)
    return pixel


def polar(u, v):
    return math.sqrt(u * u + v * v), math.atan2(v, u)


def line_alpha(d, half, aa):
    return clamp(1 - (d - half) / aa)


def seg_dist(px, py, ax, ay, bx, by):
    dx, dy = bx - ax, by - ay
    t = clamp(((px - ax) * dx + (py - ay) * dy) / (dx * dx + dy * dy))
    x, y = ax + dx * t - px, ay + dy * t - py
    return math.sqrt(x * x + y * y)


# soft round light
def glow(u, v):
    r = math.hypot(u, v)
    return math.exp(-4.2 * r * r) * (1 - smooth(0.7, 1.0, r))


# wide soft band with a faint filled middle
def halo(u, v):
    r = math.hypot(u, v)
    band = 0.9 * math.exp(-((r - 0.66) / 0.15) ** 2)
    fill = 0.28 * math.exp(-(r / 0.55) ** 2)
    return (band + fill) * (1 - smooth(0.85, 1.0, r))


# thin bright ring at 0.74 of the half width
RING = 0.74


def ring(u, v):
    r = math.hypot(u, v)
    d = abs(r - RING)
    core = line_alpha(d, 0.008, 0.012)
    bloom = 0.5 * math.exp(-(d / 0.06) ** 2)
    return max(core, bloom)


# filaments turning in a band
def wisp(u, v):
    r, t = polar(u, v)
    band = math.exp(-((r - 0.66) / 0.17) ** 2) * (1 - smooth(0.9, 1.0, r))
    a = (0.5 + 0.5 * math.sin(7 * t + 10 * r)) ** 3
    b = 0.55 + 0.45 * math.sin(3 * t - 6 * r + 1.0)
    return band * a * b


# three comets on the ring
def arcs(u, v):
    r, t = polar(u, v)
    best = 0.0
    for i in range(3):
        head = i * 2 * math.pi / 3
        d = (head - t) % (2 * math.pi)
        if d > 2.4:
            continue
        tail = math.exp(-d / 0.7)
        width = 0.025 + 0.02 * (1 - tail)
        radial = math.exp(-((r - RING) / width) ** 2)
        best = max(best, tail * radial)
    return best


# three soft motes on the ring (turned as a whole, they orbit)
def dots(u, v):
    best = 0.0
    for i in range(3):
        a = math.pi / 2 + i * 2 * math.pi / 3
        x, y = math.cos(a) * RING, math.sin(a) * RING
        d = math.hypot(u - x, v - y)
        best = max(best, math.exp(-(d / 0.075) ** 2))
    return best


# four pointed star with faint diagonal rays
def flare(u, v):
    r = math.hypot(u, v)
    core = math.exp(-(r / 0.11) ** 2)
    soft = 0.35 * math.exp(-(r / 0.3) ** 2)
    ray = 0.0
    for x, y, length, strength in ((u, v, 1.0, 1.0), (v, u, 1.0, 1.0)):
        ax = abs(x)
        if ax < length:
            w = 0.035 * (1 - ax / length) + 0.004
            ray = max(ray, strength * (1 - ax / length) ** 1.6 * math.exp(-(y / w) ** 2))
    s = math.sqrt(0.5)
    du, dv = (u + v) * s, (u - v) * s
    for x, y in ((du, dv), (dv, du)):
        ax = abs(x)
        if ax < 0.55:
            w = 0.02 * (1 - ax / 0.55) + 0.003
            ray = max(ray, 0.4 * (1 - ax / 0.55) ** 2 * math.exp(-(y / w) ** 2))
    return clamp(core + soft + ray) * (1 - smooth(0.9, 1.0, r))


# circle of runes: two rings, ticks, dashes and small marks
def sigil(u, v):
    r, t = polar(u, v)
    aa = 0.012
    a = 0.0
    a = max(a, line_alpha(abs(r - 0.93), 0.007, aa))
    a = max(a, line_alpha(abs(r - 0.80), 0.006, aa))
    # ticks between the rings, every 7.5 degrees, longer every 30
    step = math.pi / 24
    k = round(t / step)
    off = abs(t - k * step) * r
    inner = 0.84 if k % 4 else 0.81
    if inner < r < 0.90:
        a = max(a, line_alpha(off, 0.004, aa) * 0.9)
    # dashed inner ring
    dash = (t / (2 * math.pi) * 36) % 1
    if dash < 0.6:
        a = max(a, line_alpha(abs(r - 0.66), 0.006, aa) * 0.85)
    # small diamonds every 45 degrees on the middle band
    for i in range(8):
        ang = i * math.pi / 4 + math.pi / 8
        cx, cy = math.cos(ang) * 0.73, math.sin(ang) * 0.73
        d = abs(u - cx) + abs(v - cy)
        a = max(a, line_alpha(abs(d - 0.035), 0.005, aa))
    bloom = 0.3 * math.exp(-((r - 0.86) / 0.1) ** 2)
    return max(a, bloom) * (1 - smooth(0.97, 1.0, r))


# hexagram in a circle, dots on its points
HEX = []
for i in range(6):
    ang = math.pi / 2 + i * math.pi / 3
    HEX.append((math.cos(ang) * 0.9, math.sin(ang) * 0.9))


def glyph(u, v):
    aa = 0.012
    a = 0.0
    for tri in ((0, 2, 4), (1, 3, 5)):
        for k in range(3):
            p, q = HEX[tri[k]], HEX[tri[(k + 1) % 3]]
            a = max(a, line_alpha(seg_dist(u, v, p[0], p[1], q[0], q[1]), 0.008, aa))
    r = math.hypot(u, v)
    a = max(a, line_alpha(abs(r - 0.2), 0.007, aa))
    for x, y in HEX:
        d = math.hypot(u - x, v - y)
        a = max(a, math.exp(-(d / 0.045) ** 2))
    return a


# four corner brackets
def brackets(u, v):
    aa = 0.012
    half, arm = 0.74, 0.3
    a = 0.0
    for sx in (-1, 1):
        for sy in (-1, 1):
            cx, cy = sx * half, sy * half
            d1 = seg_dist(u, v, cx, cy, cx - sx * arm, cy)
            d2 = seg_dist(u, v, cx, cy, cx, cy - sy * arm)
            d = min(d1, d2)
            a = max(a, line_alpha(d, 0.022, aa), 0.4 * math.exp(-(d / 0.06) ** 2))
    return a


# three arms winding to the middle
def swirl(u, v):
    r, t = polar(u, v)
    if r < 1e-4:
        return 0.0
    arms = (0.5 + 0.5 * math.cos(3 * (t + 2.4 * math.log(r + 0.04)))) ** 3
    envelope = smooth(0.04, 0.3, r) * (1 - smooth(0.62, 1.0, r))
    return arms * envelope * (0.6 + 0.4 * (1 - r))


# flame tongue, base at the bottom (u -1..1 across, v -1..1 up)
def flame(u, v):
    y = (v + 1) / 2  # 0 bottom .. 1 top
    bend = 0.12 * math.sin(math.pi * y * 1.3) * y * y
    bulb = 0.3
    if y < bulb:
        half = 0.82 * math.sqrt(max(0.0, 1 - ((bulb - y) / bulb) ** 2))
    else:
        half = 0.82 * ((1 - y) / (1 - bulb)) ** 1.5
    if half <= 0.002:
        return 0.0
    d = abs(u - bend) / half
    edge = 1 - smooth(0.45, 1.0, d)
    body = (1 - 0.45 * y) * (0.7 + 0.3 * (1 - d))
    return edge * body


# column of light, brighter at its foot
def beam(u, v):
    y = (v + 1) / 2
    across = math.exp(-(u / 0.42) ** 2) * 0.75 + math.exp(-(u / 0.14) ** 2) * 0.35
    along = (1 - y) ** 1.1 * smooth(0.0, 0.06, y) + 0.15 * (1 - y)
    return clamp(across) * clamp(along) * (1 - smooth(0.92, 1.0, abs(u)))


# lightning bolt from top to bottom
random.seed(7)
BOLT = [(0.0, 0.95)]
x = 0.0
for i in range(1, 10):
    y = 0.95 - i * 0.19
    x = clamp(x + random.uniform(-0.32, 0.32), -0.45, 0.45)
    BOLT.append((x, y))
BOLT.append((0.0, -0.95))
BRANCHES = []
for start in (3, 6):
    bx, by = BOLT[start]
    pts = [(bx, by)]
    side = 1 if bx < 0 else -1
    for k in range(3):
        bx += side * random.uniform(0.1, 0.22)
        by -= random.uniform(0.12, 0.2)
        pts.append((bx, by))
    BRANCHES.append(pts)


def bolt(u, v):
    d = 9.0
    for k in range(len(BOLT) - 1):
        a, b = BOLT[k], BOLT[k + 1]
        d = min(d, seg_dist(u, v, a[0], a[1], b[0], b[1]))
    db = 9.0
    for pts in BRANCHES:
        for k in range(len(pts) - 1):
            a, b = pts[k], pts[k + 1]
            db = min(db, seg_dist(u, v, a[0], a[1], b[0], b[1]))
    core = max(line_alpha(d, 0.02, 0.02), 0.7 * line_alpha(db, 0.01, 0.015))
    bloom = max(0.55 * math.exp(-(d / 0.09) ** 2), 0.3 * math.exp(-(db / 0.06) ** 2))
    return max(core, bloom)


# faceted crystal, shaded (drawn with BLEND)
def gem(u, v):
    w, h = 0.55, 0.92
    d = abs(u) / w + abs(v) / h
    if d > 1.04:
        return 0, 0, 0, 0
    alpha = 1 - smooth(0.97, 1.03, d)
    upper = v > 0.18 * (1 - abs(u) / w)
    if upper:
        shade = 1.0 if u < 0 else 0.72
    else:
        shade = 0.62 if u < 0 else 0.42
    inner = abs(u) / w + abs(v - 0.1) / (h * 0.55)
    if inner < 1:
        shade = min(1.0, shade + 0.2 * (1 - inner))
    rim = smooth(0.86, 0.98, d) * 0.35
    s = clamp(shade + rim)
    return s, s, s, alpha


# silhouette mask: hollow middle, solid outside
def hole(u, v):
    r = math.hypot(u, v)
    return smooth(0.55, 1.0, r)


# window portrait: golden star on a dark disc
def icon(u, v):
    r = math.hypot(u, v)
    disc = 1 - smooth(0.9, 0.98, r)
    star = flare(u * 1.15, v * 1.15)
    halo_ = 0.6 * math.exp(-(r / 0.45) ** 2)
    light = clamp(star + halo_ * 0.6)
    base = (0.07, 0.06, 0.1)
    gold = (1.0, 0.82, 0.38)
    col = [base[k] * (1 - light) + gold[k] * light for k in range(3)]
    col = [clamp(c + 0.6 * star) for c in col]
    return col[0], col[1], col[2], disc


write("glow", 128, 128, white(glow))
write("halo", 256, 256, white(halo))
write("ring", 256, 256, white(ring))
write("wisp", 256, 256, white(wisp))
write("arcs", 256, 256, white(arcs))
write("dots", 128, 128, white(dots))
write("flare", 256, 256, white(flare))
write("sigil", 256, 256, white(sigil))
write("glyph", 256, 256, white(glyph))
write("brackets", 256, 256, white(brackets))
write("swirl", 256, 256, white(swirl))
write("flame", 128, 256, white(flame))
write("beam", 64, 256, white(beam))
write("bolt", 128, 256, white(bolt))
write("gem", 128, 128, gem)
write("hole", 128, 128, white(hole))
write("icon", 64, 64, icon)
