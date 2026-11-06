#!/usr/bin/env python3
"""Offline illustration generator for the 灰誓 starter cards.

Deterministic Pillow + numpy pipeline, no network and no external assets. Every
card shares the same gothic vignette template so the twenty pieces read as one
series:

    night sky + eclipse moon -> distant silhouettes -> fog/ground
    -> class halo -> engraved emblem -> embers/ash
    -> colour grade, engraving hatch, grain, vignette

Usage:
    python3 scripts/generate_card_art.py                 # all twenty cards
    python3 scripts/generate_card_art.py --only warden_01,medium_03
    python3 scripts/generate_card_art.py --sheet         # + contact sheet
"""

from __future__ import annotations

import argparse
import json
import math
import random
import zlib
from pathlib import Path

import numpy as np
from PIL import Image, ImageChops, ImageDraw, ImageFilter, ImageFont

ROOT = Path(__file__).resolve().parent.parent
CARD_DIR = ROOT / "assets" / "art" / "cards"
CATALOG = ROOT / "data" / "catalog.json"
SHEET_PATH = ROOT / "docs" / "evidence" / "card-art-20261104" / "card-art-contact-sheet.png"

W, H = 1024, 576
SS = 2
CW, CH = W * SS, H * SS

INK = (10, 11, 10)
GOLD = (199, 166, 106)
BONE = (232, 223, 204)


# ---------------------------------------------------------------- palettes ---

ROLES = {
    "warden": dict(
        accent=(199, 107, 87), hot=(240, 176, 120),
        sky_top=(8, 9, 10), sky_bot=(50, 31, 25), moon=(214, 198, 168),
        mist=(126, 100, 82), deep=(20, 15, 13), metal=(54, 50, 46), rim=(226, 208, 176),
    ),
    "ranger": dict(
        accent=(142, 174, 130), hot=(196, 222, 168),
        sky_top=(7, 10, 9), sky_bot=(26, 38, 31), moon=(206, 216, 190),
        mist=(96, 118, 100), deep=(14, 19, 16), metal=(46, 54, 46), rim=(210, 222, 198),
    ),
    "sister": dict(
        accent=(121, 185, 214), hot=(176, 232, 246),
        sky_top=(7, 10, 12), sky_bot=(24, 40, 50), moon=(198, 214, 222),
        mist=(88, 110, 124), deep=(12, 18, 21), metal=(44, 52, 58), rim=(204, 222, 232),
    ),
    "arcanist": dict(
        accent=(215, 182, 92), hot=(248, 218, 140),
        sky_top=(10, 9, 8), sky_bot=(50, 38, 20), moon=(224, 208, 164),
        mist=(126, 110, 78), deep=(20, 16, 10), metal=(58, 52, 38), rim=(236, 218, 176),
    ),
    "medium": dict(
        accent=(181, 155, 203), hot=(214, 196, 236),
        sky_top=(8, 8, 11), sky_bot=(34, 29, 44), moon=(206, 198, 216),
        mist=(104, 96, 120), deep=(16, 14, 20), metal=(50, 46, 58), rim=(220, 212, 232),
    ),
    "bellscribe": dict(
        accent=(115, 197, 181), hot=(184, 242, 228),
        sky_top=(6, 10, 10), sky_bot=(18, 48, 44), moon=(196, 220, 214),
        mist=(96, 126, 120), deep=(10, 18, 18), metal=(44, 62, 60), rim=(214, 238, 230),
    ),
    "ashlamper": dict(
        accent=(219, 145, 98), hot=(255, 206, 138),
        sky_top=(9, 8, 7), sky_bot=(50, 32, 26), moon=(222, 200, 172),
        mist=(130, 106, 86), deep=(20, 14, 11), metal=(58, 46, 38), rim=(240, 220, 196),
    ),
}

# card id -> role, emblem, scenery, fx, rotation, horizon, moon offset
CARDS = {
    "warden_01": dict(role="warden", emblem="greatsword", scene="ruins", fx="embers", angle=17, horizon=0.75, moon_x=0.50, float=True, float_y=0.46),
    "warden_02": dict(role="warden", emblem="tower_shield", scene="ruins", fx="ash", angle=-4, horizon=0.76, moon_x=0.46),
    "warden_03": dict(role="warden", emblem="broken_plate", scene="ruins", fx="sparks", angle=8, horizon=0.77, moon_x=0.55),
    "warden_04": dict(role="warden", emblem="brazier", scene="ruins", fx="embers", angle=0, horizon=0.76, moon_x=0.44),
    "ranger_01": dict(role="ranger", emblem="dagger", scene="forest", fx="dust", angle=-26, horizon=0.78, moon_x=0.54, float=True, float_y=0.47),
    "ranger_02": dict(role="ranger", emblem="feather", scene="forest", fx="leaves", angle=-24, horizon=0.78, moon_x=0.47, float=True, float_y=0.47),
    "ranger_03": dict(role="ranger", emblem="sickle", scene="forest", fx="drips", angle=12, horizon=0.77, moon_x=0.52),
    "ranger_04": dict(role="ranger", emblem="campfire", scene="forest", fx="embers", angle=0, horizon=0.79, moon_x=0.42),
    "sister_01": dict(role="sister", emblem="gauntlet", scene="machinery", fx="lightning", angle=-6, horizon=0.75, moon_x=0.50),
    "sister_02": dict(role="sister", emblem="hex_barrier", scene="machinery", fx="sparks", angle=0, horizon=0.75, moon_x=0.46),
    "sister_03": dict(role="sister", emblem="core_orb", scene="machinery", fx="lightning", angle=0, horizon=0.74, moon_x=0.53),
    "sister_04": dict(role="sister", emblem="twin_orbs", scene="machinery", fx="sparks", angle=0, horizon=0.76, moon_x=0.48),
    "arcanist_01": dict(role="arcanist", emblem="scepter", scene="court", fx="motes", angle=10, horizon=0.78, moon_x=0.52, float=True, float_y=0.47),
    "arcanist_02": dict(role="arcanist", emblem="knight_vow", scene="court", fx="dust", angle=0, horizon=0.79, moon_x=0.50),
    "arcanist_03": dict(role="arcanist", emblem="falling_star", scene="court", fx="stars", angle=0, horizon=0.78, moon_x=0.58, float=True, float_y=0.42),
    "arcanist_04": dict(role="arcanist", emblem="anvil", scene="court", fx="sparks", angle=0, horizon=0.79, moon_x=0.44),
    "medium_01": dict(role="medium", emblem="bone_spikes", scene="graveyard", fx="dust", angle=0, horizon=0.77, moon_x=0.50),
    "medium_02": dict(role="medium", emblem="tomb_gate", scene="graveyard", fx="wisps", angle=0, horizon=0.78, moon_x=0.55),
    "medium_03": dict(role="medium", emblem="gargoyle", scene="graveyard", fx="wisps", angle=0, horizon=0.77, moon_x=0.46),
    "medium_04": dict(role="medium", emblem="sigil", scene="graveyard", fx="wisps", angle=0, horizon=0.78, moon_x=0.54),
    "bellscribe_01": dict(role="bellscribe", emblem="tuning_fork", scene="bell_tower", fx="motes", angle=0, horizon=0.76, moon_x=0.50),
    "bellscribe_02": dict(role="bellscribe", emblem="handbell", scene="bell_tower", fx="dust", angle=-5, horizon=0.76, moon_x=0.54, float=True, float_y=0.47),
    "bellscribe_03": dict(role="bellscribe", emblem="stele", scene="bell_tower", fx="sparks", angle=3, horizon=0.77, moon_x=0.46),
    "bellscribe_04": dict(role="bellscribe", emblem="corridor", scene="bell_tower", fx="motes", angle=0, horizon=0.77, moon_x=0.52),
    "ashlamper_01": dict(role="ashlamper", emblem="lamp_needle", scene="ash_road", fx="embers", angle=0, horizon=0.77, moon_x=0.50),
    "ashlamper_02": dict(role="ashlamper", emblem="lantern_guard", scene="ash_road", fx="ash", angle=0, horizon=0.78, moon_x=0.45),
    "ashlamper_03": dict(role="ashlamper", emblem="ember_bed", scene="ash_road", fx="embers", angle=0, horizon=0.79, moon_x=0.56),
    "ashlamper_04": dict(role="ashlamper", emblem="split_flame", scene="ash_road", fx="sparks", angle=0, horizon=0.78, moon_x=0.47),
}


# ----------------------------------------------------------------- helpers ---

def mix(a, b, t):
    t = max(0.0, min(1.0, t))
    return tuple(int(round(a[i] * (1.0 - t) + b[i] * t)) for i in range(3))


def alpha(color, a):
    return (color[0], color[1], color[2], int(max(0, min(255, a))))


def value_noise(rng, shape, cell):
    h, w = shape
    sh = max(2, int(h / cell) + 1)
    sw = max(2, int(w / cell) + 1)
    small = np.array([[rng.random() for _ in range(sw)] for _ in range(sh)], dtype=np.float32)
    im = Image.fromarray((small * 255).astype(np.uint8)).resize((w, h), Image.BICUBIC)
    return np.asarray(im).astype(np.float32) / 255.0


def screen_add(base, layer, strength=1.0):
    """Additive screen of an RGBA PIL layer onto a PIL RGBA image."""
    a = np.asarray(layer).astype(np.float32) / 255.0
    b = np.asarray(base).astype(np.float32) / 255.0
    rgb = a[..., :3] * (a[..., 3:4] * strength)
    out = b[..., :3] + rgb * (1.0 - b[..., :3])
    b[..., :3] = np.clip(out, 0.0, 1.0)
    return Image.fromarray((b * 255.0).astype(np.uint8))


def shade_vertical(layer, top=1.18, bottom=0.62):
    a = np.asarray(layer).astype(np.float32)
    h = a.shape[0]
    g = np.linspace(top, bottom, h, dtype=np.float32)[:, None, None]
    a[..., :3] = np.clip(a[..., :3] * g, 0, 255)
    return Image.fromarray(a.astype(np.uint8))


class Pen:
    """Local emblem canvas: coordinates in [-1, 1], y up is negative."""

    MARGIN = 1.5

    def __init__(self, size):
        self.S = float(size)
        self.L = int(round(size * self.MARGIN))
        self.c = self.L / 2.0
        self.u = size / 2.0
        self.img = Image.new("RGBA", (self.L, self.L), (0, 0, 0, 0))
        self.d = ImageDraw.Draw(self.img)
        self.glow = Image.new("RGBA", (self.L, self.L), (0, 0, 0, 0))
        self.g = ImageDraw.Draw(self.glow)

    def p(self, x, y):
        return (self.c + x * self.u, self.c + y * self.u)

    def pts(self, seq):
        return [self.p(x, y) for x, y in seq]

    def poly(self, seq, fill, edge=None, rim=0.005, closed=True):
        pts = self.pts(seq)
        if edge is not None:
            w = max(1, int(rim * self.S * 2))
            self.d.polygon(pts, fill=edge)
            self.d.line(pts + [pts[0]] if closed else pts, fill=edge, width=w, joint="curve")
        self.d.polygon(pts, fill=fill)

    def circle(self, x, y, r, fill, edge=None, rim=0.005):
        box = [self.c + (x - r) * self.u, self.c + (y - r) * self.u,
               self.c + (x + r) * self.u, self.c + (y + r) * self.u]
        if edge is not None:
            w = max(1, int(rim * self.S * 2))
            self.d.ellipse(box, fill=edge)
            self.d.ellipse(box, outline=edge, width=w)
        self.d.ellipse(box, fill=fill)

    def line(self, seq, col, width, glow=None):
        pts = self.pts(seq)
        w = max(1, int(width * self.S))
        self.d.line(pts, fill=col, width=w, joint="curve")
        if glow is not None:
            self.g.line(pts, fill=glow, width=max(1, int(w * 1.6)), joint="curve")

    def arc(self, x, y, r, start, end, col, width, glow=None):
        box = [self.c + (x - r) * self.u, self.c + (y - r) * self.u,
               self.c + (x + r) * self.u, self.c + (y + r) * self.u]
        w = max(1, int(width * self.S))
        self.d.arc(box, start, end, fill=col, width=w)
        if glow is not None:
            self.g.arc(box, start, end, fill=glow, width=max(1, int(w * 1.5)))

    def dot_glow(self, x, y, r, col):
        px, py = self.p(x, y)
        rr = max(1.0, r * self.u)
        self.g.ellipse([px - rr, py - rr, px + rr, py + rr], fill=col)


# ---------------------------------------------------------------- backdrop ---

def sky(pal, cfg, rng):
    hz = cfg["horizon"]
    yy = np.linspace(0.0, 1.0, CH, dtype=np.float32)[:, None]
    t = np.clip(yy / max(hz, 0.01), 0, 1) ** 1.35
    top = np.array(pal["sky_top"], np.float32) / 255.0
    bot = np.array(pal["sky_bot"], np.float32) / 255.0
    arr = top[None, None, :] + (bot - top)[None, None, :] * t[..., None]

    cloud = np.clip(value_noise(rng, (CH, CW), 42) * 0.55
                    + value_noise(rng, (CH, CW), 13) * 0.75 - 0.36, 0, 1)
    arr = arr * (0.90 + 0.20 * cloud[..., None])

    gy = np.exp(-((np.arange(CH, dtype=np.float32)[:, None] / CH - hz * 0.99) ** 2) / (2 * 0.055 ** 2))
    gx = np.exp(-((np.arange(CW, dtype=np.float32)[None, :] / CW - 0.5) ** 2) / (2 * 0.26 ** 2))
    glow = (gy * gx)[..., None] * (np.array(pal["hot"], np.float32) / 255.0) * 0.34
    arr = 1 - (1 - arr) * (1 - glow)

    img = Image.fromarray((np.clip(arr, 0, 1) * 255).astype(np.uint8)).convert("RGBA")
    d = ImageDraw.Draw(img)
    for _ in range(42):
        x = rng.uniform(0, CW)
        y = rng.uniform(0, hz * CH * 0.78)
        r = rng.uniform(0.6, 1.8)
        d.ellipse([x - r, y - r, x + r, y + r], fill=(222, 216, 198, int(rng.uniform(16, 74))))
    return img


def moon(img, pal, cfg, rng):
    hz = cfg["horizon"]
    r = CW * 0.090
    cx = CW * cfg.get("moon_x", 0.5)
    cy = CH * (hz * 0.34)

    glow = Image.new("RGBA", (CW, CH), (0, 0, 0, 0))
    gd = ImageDraw.Draw(glow)
    for k, a in ((2.3, 16), (1.7, 26), (1.3, 40), (1.0, 64)):
        gd.ellipse([cx - r * k, cy - r * k, cx + r * k, cy + r * k], fill=alpha(pal["moon"], a))
    glow = glow.filter(ImageFilter.GaussianBlur(CW * 0.022))
    img.alpha_composite(glow)

    d = ImageDraw.Draw(img)
    d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=alpha(pal["moon"], 132))
    d.ellipse([cx - r * 0.86, cy - r * 0.86, cx + r * 0.86, cy + r * 0.86], fill=alpha(mix(pal["moon"], pal["rim"], 0.5), 72))
    for _ in range(11):
        ang = rng.uniform(0, math.tau)
        rad = rng.uniform(0.12, 0.62) * r
        px = cx + math.cos(ang) * rad
        py = cy + math.sin(ang) * rad
        cr = rng.uniform(0.03, 0.085) * r
        d.ellipse([px - cr, py - cr, px + cr, py + cr], fill=alpha(mix(pal["moon"], INK, 0.20), 70))

    band = Image.new("RGBA", (CW, CH), (0, 0, 0, 0))
    bd = ImageDraw.Draw(band)
    for _ in range(3):
        y = cy + rng.uniform(-0.62, 0.58) * r
        bd.rounded_rectangle([cx - r * 1.7, y - r * 0.11, cx + r * 1.7, y + r * 0.11],
                             radius=r * 0.11, fill=alpha(mix(INK, pal["deep"], 0.45), 132))
    band = band.filter(ImageFilter.GaussianBlur(r * 0.11))
    img.alpha_composite(band)


def haze(img, pal, rng, hz):
    layer = Image.new("RGBA", (CW, CH), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    for _ in range(8):
        y = CH * hz + rng.uniform(-0.07, 0.16) * CH
        h = rng.uniform(0.025, 0.09) * CH
        x0 = rng.uniform(-0.25, 0.55) * CW
        w = rng.uniform(0.45, 1.05) * CW
        col = mix(pal["mist"], pal["moon"], rng.uniform(0.08, 0.32))
        d.ellipse([x0, y - h, x0 + w, y + h], fill=alpha(col, rng.uniform(12, 30)))
    layer = layer.filter(ImageFilter.GaussianBlur(CW * 0.013))
    img.alpha_composite(layer)


def ground(img, pal, rng, hz):
    layer = Image.new("RGBA", (CW, CH), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    pts = [(0, CH * hz)]
    x = 0.0
    while x <= CW:
        pts.append((x, CH * (hz - 0.004 + 0.007 * math.sin(x / CW * 8.0 + 1.3) + rng.uniform(-0.004, 0.004))))
        x += CW / 18.0
    pts += [(CW, CH), (0, CH)]
    d.polygon(pts, fill=mix(pal["deep"], INK, 0.30) + (255,))

    lit = Image.new("RGBA", (CW, CH), (0, 0, 0, 0))
    ld = ImageDraw.Draw(lit)
    ld.ellipse([CW * 0.18, CH * hz, CW * 0.82, CH * (hz + 0.20)],
               fill=alpha(mix(pal["mist"], pal["moon"], 0.42), 54))
    lit = lit.filter(ImageFilter.GaussianBlur(CW * 0.035))
    img.alpha_composite(lit)
    # rubble and cracks give the ground plane a texture instead of a flat band
    for _ in range(46):
        x = CW * rng.uniform(0.0, 1.0)
        y = CH * rng.uniform(hz + 0.012, hz + 0.17)
        w = rng.uniform(3.0, 22.0)
        h = rng.uniform(1.5, 5.0)
        d.ellipse([x, y, x + w, y + h],
                  fill=alpha(mix(pal["deep"], pal["metal"], rng.uniform(0.15, 0.55)), rng.uniform(50, 120)))
    for _ in range(12):
        x = CW * rng.uniform(0.02, 0.98)
        y = CH * rng.uniform(hz + 0.02, hz + 0.14)
        pts = [(x, y)]
        for _ in range(3):
            x += rng.uniform(-0.02, 0.02) * CW
            y += rng.uniform(0.004, 0.012) * CH
            pts.append((x, y))
        d.line(pts, fill=alpha(INK, 110), width=max(1, int(CW * 0.0015)))
    img.alpha_composite(shade_vertical(layer, 1.0, 0.35))


def foreground(img, pal, rng, hz):
    layer = Image.new("RGBA", (CW, CH), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    col = mix(INK, pal["deep"], 0.25) + (255,)
    for side in (-1, 1):
        base_x = 0.0 if side < 0 else 1.0
        for _ in range(3):
            w = rng.uniform(0.10, 0.24) * CW
            h = rng.uniform(0.05, 0.11) * CH
            x0 = base_x * CW - (w if side < 0 else 0)
            y0 = CH - h * rng.uniform(0.7, 1.2)
            d.polygon([(x0, CH), (x0 + w, CH), (x0 + w * 0.72, y0), (x0 + w * 0.30, y0 - h * 0.25)], fill=col)
    # grass tufts
    for _ in range(26):
        x = rng.uniform(0, CW)
        y = CH * rng.uniform(hz + 0.02, 1.0)
        hgt = rng.uniform(0.01, 0.035) * CH
        d.line([(x, y), (x + rng.uniform(-6, 6), y - hgt)], fill=col, width=max(1, int(rng.uniform(1, 3))))
    layer = layer.filter(ImageFilter.GaussianBlur(0.6))
    img.alpha_composite(layer)


# --------------------------------------------------------------- scenery ----

def sil(pal, depth=0.55):
    return mix(pal["sky_bot"], INK, depth) + (255,)


def sc_ruins(pal, rng, hz):
    layer = Image.new("RGBA", (CW, CH), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    far = sil(pal, 0.52)
    near = sil(pal, 0.78)

    ridge = [(0, CH * hz)]
    x = 0.0
    while x <= CW:
        ridge.append((x, CH * (hz - 0.03 - 0.02 * math.sin(x / CW * 6.3) - rng.uniform(0, 0.012))))
        x += CW / 16.0
    ridge += [(CW, CH * hz)]
    d.polygon(ridge, fill=far)

    # ruined arcade: columns + pointed arches
    for i in range(5):
        x0 = CW * (0.08 + i * 0.19)
        top = CH * (hz - rng.uniform(0.13, 0.26))
        w = CW * 0.018
        d.rectangle([x0, top, x0 + w, CH * hz], fill=near)
        if i < 4:
            x1 = CW * (0.08 + (i + 1) * 0.19)
            apex = CH * (hz - rng.uniform(0.20, 0.30))
            d.line([(x0 + w, top), ((x0 + x1) / 2, apex), (x1, top)], fill=near,
                   width=max(2, int(CW * 0.005)), joint="curve")
    # cathedral tower
    tx, tw = CW * 0.70, CW * 0.075
    ttop = CH * (hz - 0.34)
    d.rectangle([tx, ttop, tx + tw, CH * hz], fill=far)
    d.polygon([(tx - tw * 0.2, ttop), (tx + tw * 0.5, ttop - CH * 0.10), (tx + tw * 1.2, ttop)], fill=far)
    for wx in (0.24, 0.5, 0.76):
        d.rectangle([tx + tw * wx - 3, ttop + CH * 0.05, tx + tw * wx + 3, ttop + CH * 0.085],
                    fill=alpha(pal["hot"], 120))
    # broken wall
    wall_x = CW * 0.02
    d.polygon([(wall_x, CH * hz), (wall_x + CW * 0.13, CH * hz),
               (wall_x + CW * 0.12, CH * (hz - 0.12)), (wall_x + CW * 0.08, CH * (hz - 0.15)),
               (wall_x + CW * 0.05, CH * (hz - 0.11)), (wall_x, CH * (hz - 0.14))], fill=near)

    layer = layer.filter(ImageFilter.GaussianBlur(CW * 0.0012))
    return layer


def sc_forest(pal, rng, hz):
    layer = Image.new("RGBA", (CW, CH), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    far = sil(pal, 0.50)
    near = sil(pal, 0.80)

    treeline = [(0, CH * hz)]
    x = 0.0
    while x <= CW:
        treeline.append((x, CH * (hz - 0.035 - 0.02 * abs(math.sin(x / CW * 11.0)) - rng.uniform(0, 0.02))))
        x += CW / 26.0
    treeline += [(CW, CH * hz)]
    d.polygon(treeline, fill=far)

    def tree(x, y, ang, length, width, depth, col):
        x2 = x + math.cos(ang) * length
        y2 = y - math.sin(ang) * length
        d.line([(x, y), (x2, y2)], fill=col, width=max(1, int(width)))
        if depth <= 0:
            return
        for _ in range(2 if depth < 3 else 3):
            tree(x2, y2, ang + rng.uniform(-0.65, 0.65), length * rng.uniform(0.58, 0.76),
                 width * 0.63, depth - 1, col)

    for bx, by, ln in ((0.13, 0.80, 0.20), (0.86, 0.82, 0.23), (0.70, 0.84, 0.16)):
        tree(CW * bx, CH * by, math.pi / 2 + rng.uniform(-0.15, 0.15), CH * ln, CW * 0.010, 4, near)

    # pines
    for px, ph in ((0.32, 0.10), (0.46, 0.13), (0.60, 0.09), (0.78, 0.11)):
        base_y = CH * hz
        w = CW * 0.030
        for k in range(4):
            y0 = base_y - ph * CH * (k * 0.24)
            d.polygon([(CW * px - w * (1 - k * 0.18), y0), (CW * px, y0 - ph * CH * 0.45),
                       (CW * px + w * (1 - k * 0.18), y0)], fill=near)

    layer = layer.filter(ImageFilter.GaussianBlur(CW * 0.0011))
    return layer


def sc_machinery(pal, rng, hz):
    layer = Image.new("RGBA", (CW, CH), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    far = sil(pal, 0.55)
    near = sil(pal, 0.80)

    # chimneys
    for cx, cw, chh in ((0.08, 0.055, 0.34), (0.88, 0.045, 0.30)):
        d.rectangle([CW * cx, CH * (hz - chh), CW * (cx + cw), CH * hz], fill=far)
        d.rectangle([CW * (cx - 0.008), CH * (hz - chh - 0.012), CW * (cx + cw + 0.008), CH * (hz - chh)], fill=far)
    # machine hall
    d.rectangle([CW * 0.18, CH * (hz - 0.17), CW * 0.82, CH * hz], fill=near)
    for i in range(7):
        wx = 0.22 + i * 0.085
        d.rectangle([CW * wx, CH * (hz - 0.13), CW * (wx + 0.03), CH * (hz - 0.075)],
                    fill=alpha(pal["hot"], 70))
    # pipes
    for y, x0, x1 in ((0.04, 0.10, 0.90), (0.09, 0.05, 0.95)):
        d.line([(CW * x0, CH * (hz - 0.20 - y)), (CW * x1, CH * (hz - 0.20 - y))],
               fill=near, width=max(3, int(CW * 0.008)))
    # gear
    gx, gy, gr = CW * 0.16, CH * (hz - 0.10), CW * 0.085
    pts = []
    for i in range(28):
        ang = i * math.tau / 28.0
        rr = gr * (1.0 if i % 2 == 0 else 0.82)
        pts.append((gx + math.cos(ang) * rr, gy + math.sin(ang) * rr))
    d.polygon(pts, fill=near)
    d.ellipse([gx - gr * 0.26, gy - gr * 0.26, gx + gr * 0.26, gy + gr * 0.26], fill=far)
    # antenna
    ax = CW * 0.66
    d.line([(ax, CH * (hz - 0.17)), (ax, CH * (hz - 0.42))], fill=near, width=max(2, int(CW * 0.004)))
    d.line([(ax - CW * 0.03, CH * (hz - 0.34)), (ax + CW * 0.03, CH * (hz - 0.34))], fill=near,
           width=max(2, int(CW * 0.003)))
    # lit vents
    for _ in range(6):
        x = CW * rng.uniform(0.2, 0.8)
        y = CH * (hz - rng.uniform(0.02, 0.16))
        r = rng.uniform(1.5, 3.5)
        d.ellipse([x - r, y - r, x + r, y + r], fill=alpha(pal["hot"], rng.uniform(90, 170)))

    layer = layer.filter(ImageFilter.GaussianBlur(CW * 0.0012))
    return layer


def sc_court(pal, rng, hz):
    layer = Image.new("RGBA", (CW, CH), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    far = sil(pal, 0.52)
    near = sil(pal, 0.76)

    # rear arch window
    ax0, ax1 = CW * 0.30, CW * 0.70
    ay = CH * (hz - 0.42)
    d.line([(ax0, CH * hz), (ax0, ay + CH * 0.10), (CW * 0.5, ay), (ax1, ay + CH * 0.10), (ax1, CH * hz)],
           fill=far, width=max(3, int(CW * 0.006)), joint="curve")
    d.line([(ax0 + CW * 0.02, CH * hz), (ax0 + CW * 0.02, ay + CH * 0.12), (CW * 0.5, ay + CH * 0.025),
            (ax1 - CW * 0.02, ay + CH * 0.12), (ax1 - CW * 0.02, CH * hz)],
           fill=far, width=max(2, int(CW * 0.003)), joint="curve")

    # side colonnade
    for side in (0.03, 0.09, 0.15, 0.85, 0.91, 0.97):
        x = CW * side
        d.rectangle([x, CH * (hz - 0.30), x + CW * 0.022, CH * hz], fill=near)
        d.rectangle([x - CW * 0.006, CH * (hz - 0.31), x + CW * 0.028, CH * (hz - 0.285)], fill=near)
        d.rectangle([x - CW * 0.006, CH * (hz - 0.02), x + CW * 0.028, CH * hz], fill=near)
    # steps
    for i in range(3):
        y = CH * (hz + i * 0.035)
        d.rectangle([CW * (0.12 - i * 0.02), y, CW * (0.88 + i * 0.02), y + CH * 0.035], fill=near)
    # hanging banners
    for bx in (0.20, 0.80):
        top = CH * (hz - 0.44)
        w = CW * 0.045
        col = mix(pal["accent"], INK, 0.55) + (255,)
        d.polygon([(CW * bx - w, top), (CW * bx + w, top), (CW * bx + w * 0.86, CH * (hz - 0.12)),
                   (CW * bx, CH * (hz - 0.16)), (CW * bx - w * 0.86, CH * (hz - 0.12))], fill=col)
        d.line([(CW * bx, top), (CW * bx, CH * (hz - 0.155))], fill=alpha(GOLD, 150),
               width=max(2, int(CW * 0.002)))
    layer = layer.filter(ImageFilter.GaussianBlur(CW * 0.0012))
    return layer


def sc_graveyard(pal, rng, hz):
    layer = Image.new("RGBA", (CW, CH), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    far = sil(pal, 0.52)
    near = sil(pal, 0.78)

    # distant mausoleum
    mx = CW * 0.14
    d.rectangle([mx, CH * (hz - 0.20), mx + CW * 0.14, CH * hz], fill=far)
    d.polygon([(mx - CW * 0.012, CH * (hz - 0.20)), (mx + CW * 0.07, CH * (hz - 0.28)),
               (mx + CW * 0.152, CH * (hz - 0.20))], fill=far)
    for i in range(3):
        d.rectangle([mx + CW * (0.025 + i * 0.042), CH * (hz - 0.13), mx + CW * (0.035 + i * 0.042), CH * (hz - 0.02)],
                    fill=near)
    # fence
    fence_y = CH * (hz - 0.02)
    for i in range(26):
        x = CW * (0.02 + i * 0.038)
        d.line([(x, fence_y), (x, fence_y - CH * 0.05)], fill=near, width=max(1, int(CW * 0.0022)))
        d.line([(x - 3, fence_y - CH * 0.05), (x, fence_y - CH * 0.058), (x + 3, fence_y - CH * 0.05)],
               fill=near, width=max(1, int(CW * 0.002)))
    d.line([(0, fence_y - CH * 0.028), (CW, fence_y - CH * 0.028)], fill=near, width=max(1, int(CW * 0.002)))
    # tombstones
    for tx, th, tw in ((0.64, 0.10, 0.028), (0.78, 0.075, 0.022), (0.90, 0.12, 0.030)):
        x = CW * tx
        y = CH * (hz + 0.02)
        if tx > 0.85:
            d.line([(x, y), (x, y - CH * th)], fill=near, width=max(2, int(CW * 0.006)))
            d.line([(x - CW * 0.018, y - CH * th * 0.72), (x + CW * 0.018, y - CH * th * 0.72)],
                   fill=near, width=max(2, int(CW * 0.005)))
        else:
            d.rounded_rectangle([x - CW * tw, y - CH * th, x + CW * tw, y], radius=CW * 0.012, fill=near)
    # yew tree
    d.line([(CW * 0.955, CH * (hz + 0.05)), (CW * 0.95, CH * (hz - 0.30))], fill=near,
           width=max(3, int(CW * 0.008)))
    for _ in range(16):
        ang = rng.uniform(-2.7, -0.4)
        ln = rng.uniform(0.03, 0.08) * CH
        x = CW * 0.95
        y = CH * (hz - 0.28)
        d.line([(x, y), (x + math.cos(ang) * ln, y + math.sin(ang) * ln)], fill=near,
               width=max(2, int(CW * 0.004)))
    layer = layer.filter(ImageFilter.GaussianBlur(CW * 0.0012))
    return layer


def sc_bell_tower(pal, rng, hz):
    layer = Image.new("RGBA", (CW, CH), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    far = sil(pal, 0.48)
    near = sil(pal, 0.86)

    # far arcade, three lancet openings
    for i in range(3):
        cx = CW * (0.26 + i * 0.24)
        w = CW * 0.075
        top = CH * (hz - 0.40)
        d.rectangle([cx - w, top + w, cx + w, CH * hz], fill=far)
        d.pieslice([cx - w, top, cx + w, top + 2 * w], 180, 360, fill=far)
        d.rectangle([cx - w * 0.72, top + w * 0.8, cx + w * 0.72, CH * hz], fill=mix(pal["deep"], INK, 0.2))
    # the great bell, hanging in the central opening
    bx, by = CW * 0.50, CH * (hz - 0.30)
    d.line([(bx, CH * (hz - 0.43)), (bx, by - CH * 0.05)], fill=near, width=max(2, int(CW * 0.004)))
    d.polygon([(bx - CW * 0.040, by - CH * 0.05), (bx + CW * 0.040, by - CH * 0.05),
               (bx + CW * 0.058, by + CH * 0.02), (bx + CW * 0.072, by + CH * 0.07),
               (bx - CW * 0.072, by + CH * 0.07), (bx - CW * 0.058, by + CH * 0.02)], fill=near)
    d.arc([bx - CW * 0.09, by + CH * 0.04, bx + CW * 0.09, by + CH * 0.16], 0, 180,
          fill=alpha(pal["accent"], 90), width=max(2, int(CW * 0.003)))

    # foreground piers and the arch they carry
    for sx in (-0.02, 0.94):
        x = CW * sx
        d.rectangle([x, CH * (hz - 0.58), x + CW * 0.08, CH * hz], fill=near)
        d.rectangle([x - CW * 0.012, CH * (hz - 0.50), x + CW * 0.092, CH * (hz - 0.46)], fill=near)
        for k in range(4):
            y = CH * (hz - 0.44 + k * 0.11)
            d.line([(x, y), (x + CW * 0.08, y)], fill=alpha(mix(pal["deep"], INK, 0.4), 160),
                   width=max(1, int(CW * 0.002)))
    d.arc([CW * 0.04, CH * (hz - 0.86), CW * 0.96, CH * (hz + 0.02)], 180, 360, fill=near,
          width=max(4, int(CW * 0.012)))
    # floor flags
    for i in range(7):
        y = CH * (hz + 0.03 + i * 0.045)
        d.line([(0, y), (CW, y)], fill=alpha(mix(pal["deep"], pal["metal"], 0.30), 110),
               width=max(1, int(CW * 0.0018)))
    for i in range(9):
        x = CW * (0.06 + i * 0.11)
        d.line([(x, CH * hz), (CW * 0.5 + (x - CW * 0.5) * 2.6, CH)], fill=alpha(INK, 70),
               width=max(1, int(CW * 0.0016)))
    layer = layer.filter(ImageFilter.GaussianBlur(CW * 0.0012))
    return layer


def sc_ash_road(pal, rng, hz):
    layer = Image.new("RGBA", (CW, CH), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    far = sil(pal, 0.50)
    near = sil(pal, 0.82)

    # broken boundary wall on the horizon
    x = 0.0
    while x < 1.0:
        h = 0.035 + 0.02 * abs(math.sin(x * 9.0))
        d.rectangle([CW * x, CH * (hz - h), CW * (x + 0.045), CH * hz], fill=far)
        x += 0.055
    # dead trees flanking the road
    def snag(bx, by, ang, length, width, depth, col):
        x2 = bx + math.cos(ang) * length
        y2 = by - math.sin(ang) * length
        d.line([(bx, by), (x2, y2)], fill=col, width=max(1, int(width)))
        if depth <= 0:
            return
        for _ in range(2):
            snag(x2, y2, ang + rng.uniform(-0.7, 0.7), length * rng.uniform(0.55, 0.75),
                 width * 0.6, depth - 1, col)
    for bx, by, ln in ((0.10, 0.82, 0.22), (0.90, 0.84, 0.24), (0.28, 0.80, 0.12)):
        snag(CW * bx, CH * by, math.pi / 2 + rng.uniform(-0.12, 0.12), CH * ln, CW * 0.011, 4, near)
    # road narrowing to the horizon
    d.polygon([(CW * 0.02, CH), (CW * 0.98, CH), (CW * 0.58, CH * hz), (CW * 0.42, CH * hz)],
              fill=mix(pal["mist"], pal["deep"], 0.55) + (60,))
    for i in range(6):
        t = i / 5.0
        y = CH * (hz + t * t * (0.24))
        w = 0.10 + t * 0.38
        d.line([(CW * (0.5 - w), y), (CW * (0.5 + w), y)], fill=alpha(mix(pal["mist"], BONE, 0.3), 30),
               width=max(1, int(CW * 0.0018)))
    # lamp posts, each with a small shuttered lantern
    for lx, lh in ((0.20, 0.26), (0.80, 0.30), (0.64, 0.14)):
        x = CW * lx
        base = CH * hz
        d.line([(x, base), (x, base - CH * lh)], fill=near, width=max(2, int(CW * 0.005)))
        d.line([(x - CW * 0.012, base - CH * lh), (x + CW * 0.012, base - CH * lh)],
               fill=near, width=max(2, int(CW * 0.004)))
        ly = base - CH * (lh + 0.03)
        d.rectangle([x - CW * 0.020, ly - CH * 0.012, x + CW * 0.020, ly + CH * 0.030], fill=near)
        d.rectangle([x - CW * 0.013, ly, x + CW * 0.013, ly + CH * 0.020],
                    fill=alpha(pal["hot"], 150))
        glow = Image.new("RGBA", (CW, CH), (0, 0, 0, 0))
        gd = ImageDraw.Draw(glow)
        gd.ellipse([x - CW * 0.055, ly - CH * 0.045, x + CW * 0.055, ly + CH * 0.065],
                   fill=alpha(pal["hot"], 60))
        layer.alpha_composite(glow.filter(ImageFilter.GaussianBlur(CW * 0.02)))
    layer = layer.filter(ImageFilter.GaussianBlur(CW * 0.0012))
    return layer


SCENES = {"ruins": sc_ruins, "forest": sc_forest, "machinery": sc_machinery,
          "court": sc_court, "graveyard": sc_graveyard, "bell_tower": sc_bell_tower,
          "ash_road": sc_ash_road}


# ---------------------------------------------------------------- emblems ---

def e_greatsword(p, pal):
    rim, gold, accent = pal["rim"], GOLD, pal["accent"]
    steel = mix(pal["metal"], (255, 255, 255), 0.16)
    p.poly([(0.0, -0.80), (0.068, -0.52), (0.060, 0.24), (0.0, 0.30), (-0.060, 0.24), (-0.056, -0.52)],
           fill=steel, edge=rim, rim=0.0045)
    p.line([(0.0, -0.70), (0.0, 0.16)], mix(pal["metal"], INK, 0.55), 0.010)
    p.line([(0.044, -0.74), (0.050, -0.52), (0.045, 0.20)], BONE, 0.0028)
    p.poly([(-0.27, 0.28), (-0.25, 0.37), (0.25, 0.37), (0.27, 0.28), (0.06, 0.31), (-0.06, 0.31)],
           fill=mix(gold, INK, 0.35), edge=gold, rim=0.005)
    p.poly([(-0.035, 0.37), (0.035, 0.37), (0.030, 0.60), (-0.030, 0.60)],
           fill=mix(pal["deep"], (60, 48, 36), 0.45), edge=gold, rim=0.0035)
    for i in range(4):
        y = 0.41 + i * 0.046
        p.line([(-0.030, y), (0.030, y + 0.014)], mix(gold, BONE, 0.3), 0.0035)
    p.circle(0.0, 0.635, 0.055, fill=mix(gold, INK, 0.55), edge=gold, rim=0.005)
    p.circle(0.0, 0.635, 0.019, fill=accent)
    p.poly([(0.050, -0.36), (0.070, -0.30), (0.046, -0.24)], fill=mix(INK, steel, 0.15))
    for sx, sy, dx, dy in ((-0.15, -0.62, -0.04, -0.09), (0.13, -0.55, 0.05, -0.08),
                           (0.02, -0.82, 0.0, -0.06), (0.20, -0.40, 0.06, -0.03)):
        p.line([(sx, sy), (sx + dx, sy + dy)], (250, 222, 160), 0.0045, glow=(255, 176, 96))


def e_tower_shield(p, pal):
    rim, gold, accent = pal["rim"], GOLD, pal["accent"]
    steel = mix(pal["metal"], BONE, 0.34)
    shield = [(-0.44, -0.62), (0.44, -0.62), (0.50, -0.20), (0.34, 0.30), (0.0, 0.80),
              (-0.34, 0.30), (-0.50, -0.20)]
    p.poly(shield, fill=steel, edge=rim, rim=0.008)
    inner = [(-0.36, -0.54), (0.36, -0.54), (0.41, -0.19), (0.28, 0.26), (0.0, 0.67),
             (-0.28, 0.26), (-0.41, -0.19)]
    p.poly(inner, fill=mix(steel, INK, 0.30), edge=mix(gold, INK, 0.25), rim=0.0035)
    p.circle(0.0, -0.10, 0.145, fill=mix(steel, gold, 0.40), edge=gold, rim=0.006)
    p.circle(0.0, -0.10, 0.058, fill=mix(steel, INK, 0.60), edge=rim, rim=0.003)
    for i in range(8):
        ang = i * math.tau / 8.0
        p.circle(math.cos(ang) * 0.385, math.sin(ang) * 0.47 - 0.03, 0.021,
                 fill=mix(steel, BONE, 0.35), edge=mix(gold, INK, 0.2), rim=0.002)
    p.line([(-0.30, 0.30), (-0.16, 0.10), (-0.22, -0.06), (-0.05, -0.24), (0.06, -0.42)],
           mix(INK, steel, 0.20), 0.006)
    # arrows lodging in the upper-left face
    for tx, ty, sx, sy in ((-0.26, -0.44, -0.90, -1.00), (-0.05, -0.54, -0.66, -1.04),
                           (-0.38, -0.24, -1.02, -0.76)):
        dx, dy = tx - sx, ty - sy
        d = math.hypot(dx, dy) or 1.0
        ux, uy = dx / d, dy / d
        p.line([(sx, sy), (tx - ux * 0.02, ty - uy * 0.02)],
               mix((128, 104, 76), pal["deep"], 0.30), 0.013)
        for s in (-1, 1):
            p.line([(sx + ux * 0.04, sy + uy * 0.04),
                    (sx - ux * 0.09 + s * uy * 0.055, sy - uy * 0.09 - s * ux * 0.055)],
                   (176, 162, 136), 0.011)
        p.line([(sx - ux * 0.02 - uy * 0.032, sy - uy * 0.02 + ux * 0.032),
                (sx - ux * 0.02 + uy * 0.032, sy - uy * 0.02 - ux * 0.032)], (152, 140, 118), 0.008)
        bx, by = tx - ux * 0.11, ty - uy * 0.11
        p.poly([(tx, ty), (bx + uy * 0.033, by - ux * 0.033), (bx - uy * 0.033, by + ux * 0.033)],
               fill=mix(steel, BONE, 0.30), edge=alpha(INK, 210), rim=0.002)
        p.line([(tx - ux * 0.02, ty - uy * 0.02), (bx, by)], alpha(INK, 120), 0.007)


def e_broken_plate(p, pal):
    rim, gold, accent = pal["rim"], GOLD, pal["accent"]
    steel = mix(pal["metal"], BONE, 0.10)
    plate = [(-0.46, -0.50), (0.46, -0.50), (0.36, 0.10), (0.22, 0.42), (0.0, 0.60),
             (-0.22, 0.42), (-0.36, 0.10)]
    p.poly(plate, fill=steel, edge=rim, rim=0.007)
    p.poly([(-0.30, -0.38), (0.30, -0.38), (0.24, 0.02), (0.12, 0.30), (0.0, 0.42),
            (-0.12, 0.30), (-0.24, 0.02)], fill=mix(steel, INK, 0.22), edge=mix(gold, INK, 0.4), rim=0.003)
    hole = [(-0.02, -0.26), (0.12, -0.32), (0.20, -0.16), (0.16, 0.02), (0.24, 0.10),
            (0.12, 0.16), (0.06, 0.04), (-0.04, 0.08), (-0.10, -0.08)]
    p.poly(hole, fill=mix(INK, pal["deep"], 0.35), edge=mix(rim, gold, 0.5), rim=0.004)
    for cx, cy, ex, ey in ((-0.30, -0.20, -0.60, -0.34), (0.10, -0.44, 0.06, -0.70),
                           (0.30, 0.06, 0.56, 0.22), (-0.10, 0.30, -0.24, 0.62)):
        p.line([(cx, cy), ((cx + ex) / 2 + 0.03, (cy + ey) / 2), (ex, ey)],
               mix(INK, steel, 0.25), 0.005)
    frags = [(0.40, -0.62, 0.06), (0.52, -0.48, 0.05), (0.32, -0.76, 0.04),
             (0.60, -0.30, 0.045), (0.48, -0.18, 0.035), (0.66, -0.56, 0.03)]
    for fx, fy, s in frags:
        p.poly([(fx, fy - s), (fx + s * 0.9, fy), (fx, fy + s * 0.8), (fx - s * 0.7, fy - s * 0.2)],
               fill=steel, edge=rim, rim=0.0025)
    # hammer entering top right
    p.line([(0.95, -0.85), (0.55, -0.60)], mix((90, 70, 52), INK, 0.25), 0.030)
    p.poly([(0.42, -0.72), (0.66, -0.86), (0.74, -0.72), (0.50, -0.58)], fill=steel, edge=rim, rim=0.005)
    for i in range(7):
        ang = i * math.tau / 7.0
        p.line([(0.16, -0.04), (0.16 + math.cos(ang) * 0.16, -0.04 + math.sin(ang) * 0.16)],
               (255, 226, 170), 0.004, glow=(255, 168, 92))


def e_brazier(p, pal):
    rim, gold, accent = pal["rim"], GOLD, pal["accent"]
    p.line([(0.0, 0.52), (0.0, -0.34)], mix(pal["metal"], INK, 0.35), 0.045)
    p.line([(0.0, 0.52), (0.0, -0.34)], gold, 0.012)
    p.poly([(-0.30, 0.10), (0.30, 0.10), (0.22, 0.36), (-0.22, 0.36)],
           fill=mix(pal["metal"], INK, 0.30), edge=gold, rim=0.006)
    p.poly([(-0.36, 0.06), (0.36, 0.06), (0.34, 0.16), (-0.34, 0.16)], fill=mix(gold, INK, 0.45), edge=rim, rim=0.004)
    p.line([(-0.20, 0.36), (-0.24, 0.66)], mix(pal["metal"], INK, 0.45), 0.016)
    p.line([(0.20, 0.36), (0.24, 0.66)], mix(pal["metal"], INK, 0.45), 0.016)
    p.line([(0.0, 0.38), (0.0, 0.68)], mix(pal["metal"], INK, 0.45), 0.016)
    flames = [
        (0.0, 0.04, 0.34, 0.66), (-0.20, 0.08, 0.18, 0.44), (0.20, 0.08, 0.18, 0.42),
    ]
    for fx, fy, w, h in flames:
        p.poly([(fx, fy - h), (fx + w * 0.55, fy - h * 0.52), (fx + w, fy),
                (fx + w * 0.4, fy + 0.03), (fx - w * 0.4, fy + 0.03), (fx - w, fy),
                (fx - w * 0.5, fy - h * 0.48)],
               fill=accent, edge=mix(pal["hot"], BONE, 0.3), rim=0.003)
    p.poly([(0.0, -0.50), (0.09, -0.22), (0.05, 0.02), (-0.05, 0.02), (-0.09, -0.22)],
           fill=mix(pal["hot"], (255, 255, 255), 0.25))
    for _ in range(9):
        p.dot_glow(0.0 + 0.0, 0.0, 0.0, (255, 180, 110, 0))
    for sx, sy in ((-0.12, -0.52), (0.14, -0.44), (0.02, -0.66), (-0.22, -0.30), (0.24, -0.24)):
        p.line([(sx, sy), (sx + 0.01, sy - 0.06)], (255, 208, 140), 0.004, glow=(255, 170, 90))


def e_dagger(p, pal):
    rim, gold, accent = pal["rim"], GOLD, pal["accent"]
    steel = mix(pal["metal"], BONE, 0.22)
    p.poly([(0.0, -0.86), (0.075, -0.58), (0.052, 0.10), (0.0, 0.16), (-0.045, 0.08), (-0.062, -0.58)],
           fill=steel, edge=rim, rim=0.004)
    p.line([(0.0, -0.76), (0.0, 0.06)], mix(pal["metal"], INK, 0.55), 0.008)
    p.line([(0.042, -0.80), (0.034, -0.58), (0.028, 0.06)], BONE, 0.0025)
    p.poly([(-0.18, 0.12), (0.18, 0.12), (0.18, 0.21), (-0.18, 0.21)], fill=mix(gold, INK, 0.35), edge=gold, rim=0.004)
    p.poly([(-0.05, 0.21), (0.05, 0.21), (0.045, 0.52), (-0.045, 0.52)],
           fill=mix(pal["deep"], (66, 50, 36), 0.4), edge=gold, rim=0.0035)
    for i in range(3):
        y = 0.26 + i * 0.07
        p.line([(-0.042, y), (0.042, y + 0.02)], mix(gold, BONE, 0.35), 0.004)
    p.circle(0.0, 0.565, 0.065, fill=mix(gold, INK, 0.5), edge=gold, rim=0.004)
    for i, off in enumerate((-0.10, -0.02, 0.06)):
        p.line([(-0.55 + i * 0.02, 0.55 + off), (-0.05 + i * 0.02, 0.20 + off)],
               alpha(mix(pal["accent"], BONE, 0.4), 90), 0.014)
    p.poly([(-0.62, 0.52), (-0.52, 0.46), (-0.48, 0.54), (-0.58, 0.60)], fill=accent, edge=mix(accent, BONE, 0.5), rim=0.002)


def e_feather(p, pal):
    rim, gold, accent = pal["rim"], GOLD, pal["accent"]
    left, right = [], []
    for i in range(19):
        t = i / 18.0
        x = 0.03 - 0.055 * t
        y = 0.78 - 1.48 * t
        ln = 0.045 + 0.335 * math.sin(math.pi * (0.11 + 0.83 * t)) ** 0.85
        left.append((x - ln, y - ln * 0.60))
        right.append((x + ln, y - ln * 0.58))
    vane = left + right[::-1]
    p.poly(vane, fill=mix(accent, pal["deep"], 0.42), edge=alpha(rim, 220), rim=0.0045)
    for i in range(19):
        t = i / 18.0
        x = 0.03 - 0.055 * t
        y = 0.78 - 1.48 * t
        ln = 0.045 + 0.335 * math.sin(math.pi * (0.11 + 0.83 * t)) ** 0.85
        p.line([(x, y), (x - ln * 0.92, y - ln * 0.54)], alpha(mix(BONE, accent, 0.25), 135), 0.0028)
        p.line([(x, y), (x + ln * 0.92, y - ln * 0.52)], alpha(mix(BONE, accent, 0.25), 135), 0.0028)
    p.line([(0.04, 0.92), (0.06, 0.52), (0.03, 0.10), (-0.01, -0.30), (-0.06, -0.80)],
           mix(gold, BONE, 0.45), 0.016)
    p.dot_glow(0.05, 0.62, 0.10, alpha(pal["hot"], 90))
    for i, r in enumerate((0.52, 0.63, 0.74)):
        p.arc(-0.12, 0.06, r, 128, 268, alpha(mix(accent, BONE, 0.3), 78 - i * 18), 0.006)
    for lx, ly, s in ((0.44, 0.34, 0.05), (0.52, 0.18, 0.04), (-0.34, 0.52, 0.04), (0.28, 0.58, 0.035)):
        p.poly([(lx, ly - s), (lx + s * 0.9, ly), (lx, ly + s), (lx - s * 0.55, ly)],
               fill=mix(accent, pal["hot"], 0.25), edge=alpha(rim, 150), rim=0.0016)


def e_sickle(p, pal):
    rim, gold, accent = pal["rim"], GOLD, pal["accent"]
    steel = mix(pal["metal"], BONE, 0.18)
    outer, inner = [], []
    for i in range(24):
        t = i / 23.0
        ang = math.radians(200 + t * 150)
        ro = 0.66 - 0.06 * t
        ri = ro - 0.13 + 0.03 * math.sin(t * 3.0)
        outer.append((math.cos(ang) * ro, math.sin(ang) * ro + 0.02))
        inner.append((math.cos(ang) * ri, math.sin(ang) * ri + 0.02))
    p.poly(outer + inner[::-1], fill=steel, edge=rim, rim=0.004)
    p.line(outer, BONE, 0.0032)
    for i in range(5):
        t = 0.18 + i * 0.16
        x, y = outer[int(t * 23)]
        p.line([(x, y), (x * 0.90, y * 0.90)], mix(accent, BONE, 0.3), 0.006, glow=(150, 210, 140))
    p.line([(0.44, 0.42), (0.62, 0.62)], mix(gold, INK, 0.4), 0.045)
    p.line([(0.46, 0.44), (0.62, 0.62)], gold, 0.018)
    p.circle(0.40, 0.38, 0.055, fill=mix(gold, INK, 0.5), edge=gold, rim=0.004)
    for dx, dy in ((0.10, 0.44), (0.22, 0.52), (-0.02, 0.52)):
        p.poly([(dx, dy), (dx + 0.035, dy + 0.08), (dx + 0.055, dy + 0.02)],
               fill=mix(accent, pal["hot"], 0.35), edge=mix(accent, BONE, 0.5), rim=0.0015)
    for i in range(4):
        p.line([(-0.20 + i * 0.10, -0.44), (-0.24 + i * 0.10, -0.50)], mix(accent, BONE, 0.3), 0.004,
               glow=(140, 200, 130))


def e_campfire(p, pal):
    rim, gold, accent = pal["rim"], GOLD, pal["accent"]
    wood = mix((74, 54, 36), INK, 0.15)
    for i in range(7):
        ang = i * math.tau / 7.0
        p.circle(math.cos(ang) * 0.42, 0.60 + math.sin(ang) * 0.10, 0.055,
                 fill=mix(pal["metal"], INK, 0.35), edge=mix(rim, INK, 0.45), rim=0.0025)
    for ang in (0.32, -0.28):
        p.line([(-0.34 + ang, 0.68), (0.34 + ang, 0.48)], wood, 0.055)
        p.line([(-0.34 + ang, 0.68), (0.34 + ang, 0.48)], mix(gold, INK, 0.55), 0.008)
    for fx, fy, w, h in ((0.0, 0.40, 0.26, 0.64), (-0.16, 0.44, 0.14, 0.40), (0.16, 0.44, 0.14, 0.38)):
        p.poly([(fx, fy - h), (fx + w * 0.5, fy - h * 0.55), (fx + w, fy),
                (fx + w * 0.35, fy + 0.02), (fx - w * 0.35, fy + 0.02), (fx - w, fy),
                (fx - w * 0.5, fy - h * 0.5)],
               fill=accent, edge=mix(pal["hot"], BONE, 0.35), rim=0.003)
    p.poly([(0.0, 0.12), (0.07, 0.28), (0.04, 0.40), (-0.04, 0.40), (-0.07, 0.28)],
           fill=mix(pal["hot"], (255, 255, 255), 0.3))
    # leaning bow
    p.arc(0.62, 0.24, 0.30, 170, 350, mix(wood, BONE, 0.15), 0.012)
    p.line([(0.62 - 0.30, 0.24), (0.62 + 0.30, 0.24)], alpha(BONE, 110), 0.004)
    for i in range(8):
        p.dot_glow(0, 0, 0, (0, 0, 0, 0))
    for sx, sy in ((-0.20, -0.34), (0.12, -0.52), (0.26, -0.18), (-0.30, -0.06), (0.05, -0.70)):
        p.line([(sx, sy), (sx + 0.01, sy - 0.05)], (255, 206, 140), 0.0035, glow=(255, 168, 88))


def e_gauntlet(p, pal):
    rim, gold, accent = pal["rim"], GOLD, pal["accent"]
    steel = mix(pal["metal"], (255, 255, 255), 0.12)
    p.poly([(-0.26, 0.46), (0.26, 0.46), (0.32, 0.84), (-0.32, 0.84)], fill=mix(steel, INK, 0.30), edge=gold, rim=0.005)
    fist = [(-0.28, 0.50), (-0.34, 0.06), (-0.26, -0.26), (0.16, -0.30), (0.30, -0.04),
            (0.30, 0.10), (0.22, 0.20), (0.26, 0.50)]
    p.poly(fist, fill=steel, edge=rim, rim=0.006)
    for i in range(3):
        y = -0.20 + i * 0.13
        p.line([(-0.20, y), (0.24, y - 0.02)], mix(pal["metal"], INK, 0.55), 0.006)
    for i in range(3):
        p.circle(-0.16 + i * 0.16, -0.26, 0.045, fill=mix(steel, BONE, 0.20), edge=mix(gold, INK, 0.2), rim=0.0025)
    p.poly([(-0.34, 0.12), (-0.46, -0.02), (-0.42, -0.16), (-0.28, -0.10)], fill=steel, edge=rim, rim=0.004)
    p.line([(0.24, -0.16), (0.46, -0.42), (0.34, -0.52), (0.56, -0.74)], (240, 214, 150), 0.006, glow=(160, 236, 255))
    p.line([(0.34, -0.52), (0.18, -0.62)], (240, 214, 150), 0.005, glow=(160, 236, 255))
    p.line([(0.46, -0.42), (0.60, -0.30)], (240, 214, 150), 0.004, glow=(160, 236, 255))
    for i in range(3):
        p.arc(-0.30, -0.02, 0.34 + i * 0.10, 150, 260, alpha(accent, 120), 0.006)


def e_hex_barrier(p, pal):
    rim, gold, accent = pal["rim"], GOLD, pal["accent"]
    def hexpts(r, cx=0.0, cy=0.0, rot=0.0):
        return [(cx + math.cos(rot + i * math.tau / 6) * r, cy + math.sin(rot + i * math.tau / 6) * r) for i in range(6)]
    p.poly(hexpts(0.74), fill=mix(pal["deep"], pal["metal"], 0.28) + (110,), edge=mix(accent, BONE, 0.35), rim=0.009)
    p.poly(hexpts(0.74), fill=(0, 0, 0, 0), edge=accent, rim=0.005)
    for ang in (0, 60, 120, 180, 240, 300):
        cx = math.cos(math.radians(ang)) * 0.44
        cy = math.sin(math.radians(ang)) * 0.44
        p.poly(hexpts(0.22, cx, cy), fill=(0, 0, 0, 0), edge=alpha(accent, 150), rim=0.0025)
    for ang in (0, 60, 120, 180, 240, 300):
        p.dot_glow(math.cos(math.radians(ang)) * 0.74, math.sin(math.radians(ang)) * 0.74, 0.05,
                   alpha(pal["hot"], 200))
    for ang in (30, 150, 270):
        x, y = math.cos(math.radians(ang)) * 0.60, math.sin(math.radians(ang)) * 0.60
        p.line([(x, y), (x * 1.10, y * 1.10)], (240, 226, 190), 0.003, glow=(150, 230, 255))
    for fx, fy, s in ((0.80, -0.50, 0.06), (-0.80, 0.40, 0.05), (0.72, 0.54, 0.045)):
        p.poly([(fx, fy - s), (fx + s, fy), (fx, fy + s * 0.9), (fx - s * 0.8, fy)], fill=mix(pal["metal"], BONE, 0.2),
               edge=alpha(accent, 200), rim=0.002)


def e_core_orb(p, pal):
    rim, gold, accent = pal["rim"], GOLD, pal["accent"]
    steel = mix(pal["metal"], INK, 0.15)
    p.poly([(-0.24, 0.58), (0.24, 0.58), (0.32, 0.76), (-0.32, 0.76)], fill=steel, edge=gold, rim=0.005)
    for sx in (-1, 1):
        p.line([(sx * 0.16, 0.58), (sx * 0.30, 0.30), (sx * 0.26, 0.10)], mix(steel, BONE, 0.18), 0.022)
    p.circle(0.0, -0.02, 0.34, fill=mix(pal["deep"], (10, 24, 30), 0.65), edge=alpha(accent, 235), rim=0.009)
    for r, al, col in ((0.30, 26, accent), (0.245, 44, mix(accent, pal["hot"], 0.4)),
                       (0.185, 78, mix(accent, pal["hot"], 0.55)), (0.125, 130, mix(pal["hot"], BONE, 0.35)),
                       (0.070, 200, (250, 252, 246))):
        p.circle(0.0, -0.02, r, fill=alpha(col, al))
    p.circle(0.0, -0.02, 0.032, fill=(255, 255, 252))
    for i in range(6):
        ang = math.radians(i * 60 + 15)
        p.line([(math.cos(ang) * 0.20, -0.02 + math.sin(ang) * 0.20),
                (math.cos(ang) * 0.30, -0.02 + math.sin(ang) * 0.30)], alpha(pal["hot"], 110), 0.004)
    p.dot_glow(0.0, -0.02, 0.36, alpha(pal["hot"], 120))
    p.arc(0.0, -0.02, 0.27, 200, 330, alpha(BONE, 170), 0.006)
    p.line([(-0.60, 0.36), (-0.36, 0.36), (-0.30, 0.20)], steel, 0.022)
    p.line([(0.60, 0.30), (0.36, 0.30), (0.30, 0.14)], steel, 0.022)
    p.circle(-0.60, 0.36, 0.035, fill=accent)
    p.circle(0.60, 0.30, 0.035, fill=accent)
    p.line([(0.30, -0.06), (0.44, -0.28), (0.38, -0.32), (0.52, -0.50)], (250, 230, 180), 0.005,
           glow=(150, 232, 255))
    p.line([(-0.30, 0.02), (-0.46, -0.14), (-0.42, -0.22), (-0.56, -0.34)], (250, 230, 180), 0.004,
           glow=(150, 232, 255))
    for ang in (20, 140, 260):
        p.dot_glow(math.cos(math.radians(ang)) * 0.40, math.sin(math.radians(ang)) * 0.40, 0.03,
                   alpha(pal["hot"], 200))


def e_twin_orbs(p, pal):
    rim, gold, accent = pal["rim"], GOLD, pal["accent"]
    for cx, cy in ((-0.30, 0.04), (0.30, -0.06)):
        p.circle(cx, cy, 0.19, fill=mix(pal["deep"], (20, 34, 40), 0.55), edge=alpha(accent, 235), rim=0.007)
        p.circle(cx, cy, 0.11, fill=mix(accent, BONE, 0.4))
        p.arc(cx, cy, 0.27, 150, 330, alpha(accent, 130), 0.004)
        p.arc(cx, cy, 0.30, 20, 160, alpha(pal["hot"], 90), 0.003)
    p.arc(0.0, -0.02, 0.62, 205, 335, alpha(pal["hot"], 170), 0.006, glow=(140, 226, 255))
    p.line([(-0.12, -0.02), (0.0, -0.20), (0.12, -0.02)], alpha(pal["hot"], 210), 0.005, glow=(150, 230, 255))
    p.circle(0.0, -0.20, 0.035, fill=mix(pal["hot"], (255, 255, 255), 0.4))
    for ang in (15, 75, 135, 195, 255, 315):
        x = math.cos(math.radians(ang)) * 0.56
        y = math.sin(math.radians(ang)) * 0.56
        p.circle(x, y, 0.012, fill=alpha(pal["hot"], 200))


def e_scepter(p, pal):
    rim, gold, accent = pal["rim"], GOLD, pal["accent"]
    p.line([(0.42, 0.78), (-0.06, -0.36)], mix(gold, INK, 0.35), 0.035)
    p.line([(0.42, 0.78), (-0.06, -0.36)], gold, 0.014)
    for t in (0.2, 0.45, 0.7):
        x = 0.42 + (-0.06 - 0.42) * t
        y = 0.78 + (-0.36 - 0.78) * t
        p.line([(x - 0.03, y + 0.02), (x + 0.03, y - 0.02)], BONE, 0.006)
    cw = 0.24
    p.poly([(-0.06 - cw, -0.36), (-0.06 + cw, -0.36), (-0.06 + cw, -0.46), (-0.06 - cw, -0.46)],
           fill=mix(gold, INK, 0.30), edge=gold, rim=0.005)
    for i in range(5):
        x = -0.06 - cw * 0.85 + i * cw * 0.425
        h = 0.16 if i % 2 == 0 else 0.11
        p.poly([(x - 0.035, -0.46), (x, -0.46 - h), (x + 0.035, -0.46)],
               fill=mix(gold, BONE, 0.15), edge=alpha(BONE, 200), rim=0.0025)
    p.circle(-0.06, -0.54, 0.045, fill=accent, edge=mix(BONE, accent, 0.4), rim=0.003)
    p.dot_glow(-0.06, -0.54, 0.14, alpha(pal["hot"], 210))
    for i in range(3):
        p.line([(0.30 - i * 0.05, 0.62 - i * 0.28), (0.14 - i * 0.05, 0.30 - i * 0.28)],
               alpha(accent, 110 - i * 25), 0.012)
    for sx, sy, s in ((0.50, -0.62, 0.035), (0.70, -0.30, 0.025), (-0.62, -0.72, 0.03), (0.34, -0.82, 0.022)):
        p.line([(sx - s, sy), (sx + s, sy)], alpha(pal["hot"], 220), 0.003, glow=(255, 226, 150))
        p.line([(sx, sy - s), (sx, sy + s)], alpha(pal["hot"], 220), 0.003, glow=(255, 226, 150))


def e_knight_vow(p, pal):
    rim, gold, accent = pal["rim"], GOLD, pal["accent"]
    steel = mix(pal["metal"], BONE, 0.16)
    for side in (-1, 1):
        x = side * 0.62
        p.poly([(x - 0.14, -0.70), (x + 0.14, -0.70), (x + 0.12, 0.30), (x, 0.22), (x - 0.12, 0.30)],
               fill=mix(accent, INK, 0.55), edge=mix(gold, INK, 0.2), rim=0.004)
        p.line([(x, -0.68), (x, 0.26)], alpha(gold, 180), 0.004)
    helm = [(-0.30, -0.62), (0.30, -0.62), (0.34, -0.30), (0.28, 0.06), (0.16, 0.16),
            (-0.16, 0.16), (-0.28, 0.06), (-0.34, -0.30)]
    p.poly(helm, fill=steel, edge=rim, rim=0.007)
    p.poly([(-0.26, -0.24), (0.26, -0.24), (0.24, -0.14), (-0.24, -0.14)], fill=mix(INK, pal["deep"], 0.3))
    for y in (-0.06, 0.02):
        for x in (-0.10, 0.0, 0.10):
            p.circle(x, y, 0.012, fill=mix(INK, steel, 0.4))
    p.line([(0.0, -0.62), (0.0, -0.30)], mix(rim, gold, 0.4), 0.006)
    # sword planted point-down
    p.poly([(0.0, 0.76), (0.065, 0.60), (0.055, -0.10), (0.0, -0.16), (-0.055, -0.10), (-0.065, 0.60)],
           fill=steel, edge=rim, rim=0.0045)
    p.poly([(-0.24, -0.12), (0.24, -0.12), (0.24, -0.04), (-0.24, -0.04)], fill=mix(gold, INK, 0.35),
           edge=gold, rim=0.004)
    p.poly([(-0.035, -0.12), (0.035, -0.12), (0.03, -0.42), (-0.03, -0.42)], fill=mix(pal["deep"], (60, 46, 32), 0.4),
           edge=gold, rim=0.003)
    p.circle(0.0, -0.44, 0.055, fill=mix(gold, INK, 0.5), edge=gold, rim=0.004)
    p.dot_glow(0.0, -0.20, 0.10, alpha(accent, 90))


def e_falling_star(p, pal):
    rim, gold, accent = pal["rim"], GOLD, pal["accent"]
    cx, cy = 0.14, -0.30
    tail = [(cx + 0.02, cy + 0.03), (cx - 0.06, cy + 0.22), (-0.20, 0.40), (-0.40, 0.58),
            (-0.54, 0.70), (-0.50, 0.56), (-0.34, 0.40), (-0.16, 0.22), (cx - 0.02, cy + 0.05)]
    p.poly(tail, fill=alpha(mix(accent, pal["hot"], 0.40), 110),
           edge=alpha(mix(BONE, accent, 0.4), 80), rim=0.002)
    for k, w in ((0, 0.030), (1, 0.017), (2, 0.009)):
        p.line([(cx - 0.02, cy + 0.06), (-0.28 - k * 0.05, 0.36 + k * 0.10), (-0.60 - k * 0.04, 0.62 + k * 0.10)],
               alpha(mix(pal["hot"], BONE, 0.5), 150 - k * 35), w)
    pts = []
    for i in range(16):
        ang = i * math.tau / 16 + math.radians(10)
        r = 0.22 if i % 2 == 0 else 0.085
        pts.append((cx + math.cos(ang) * r, cy + math.sin(ang) * r))
    p.poly(pts, fill=mix(accent, BONE, 0.30), edge=(255, 244, 210), rim=0.004)
    p.circle(cx, cy, 0.055, fill=(255, 250, 230))
    p.dot_glow(cx, cy, 0.30, alpha(pal["hot"], 110))
    for i in range(2):
        p.arc(cx, cy, 0.36 + i * 0.10, 200, 330, alpha(accent, 80 - i * 25), 0.004)
    for ang, dist in ((30, 0.5), (100, 0.6), (210, 0.55), (300, 0.62), (160, 0.44)):
        x = cx + math.cos(math.radians(ang)) * dist
        y = cy + math.sin(math.radians(ang)) * dist
        p.line([(x - 0.02, y), (x + 0.02, y)], alpha(pal["hot"], 190), 0.0025, glow=(255, 232, 160))
        p.line([(x, y - 0.02), (x, y + 0.02)], alpha(pal["hot"], 190), 0.0025, glow=(255, 232, 160))


def e_anvil(p, pal):
    rim, gold, accent = pal["rim"], GOLD, pal["accent"]
    steel = mix(pal["metal"], INK, 0.10)
    anvil = [(-0.52, -0.08), (-0.30, -0.08), (0.28, -0.08), (0.44, -0.14), (0.56, -0.10),
             (0.52, 0.02), (0.38, 0.08), (0.20, 0.10), (0.16, 0.34), (0.34, 0.36), (0.36, 0.52),
             (-0.36, 0.52), (-0.34, 0.36), (-0.16, 0.34), (-0.20, 0.10), (-0.40, 0.06), (-0.56, 0.04)]
    p.poly(anvil, fill=steel, edge=rim, rim=0.005)
    p.line([(-0.40, 0.02), (0.34, 0.02)], mix(pal["metal"], BONE, 0.18), 0.004)
    p.line([(-0.26, 0.24), (0.26, 0.24)], alpha(gold, 120), 0.003)
    # blade across the anvil
    p.poly([(-0.62, -0.24), (-0.50, -0.36), (0.30, -0.44), (0.40, -0.34), (0.28, -0.28), (-0.52, -0.18)],
           fill=mix(pal["metal"], BONE, 0.25), edge=rim, rim=0.0035)
    p.line([(-0.48, -0.30), (0.30, -0.37)], alpha(BONE, 180), 0.003)
    p.poly([(0.38, -0.44), (0.50, -0.54), (0.56, -0.44), (0.44, -0.34)], fill=mix(gold, INK, 0.3),
           edge=gold, rim=0.003)
    # hammer
    p.line([(0.86, -0.88), (0.50, -0.52)], mix((90, 70, 52), INK, 0.2), 0.026)
    p.poly([(0.30, -0.62), (0.52, -0.76), (0.62, -0.62), (0.40, -0.48)], fill=steel, edge=rim, rim=0.005)
    for i in range(9):
        ang = i * math.tau / 9.0
        p.line([(0.18, -0.24), (0.18 + math.cos(ang) * 0.17, -0.24 + math.sin(ang) * 0.17)],
               (255, 232, 180), 0.004, glow=(255, 180, 96))
    p.dot_glow(0.18, -0.24, 0.12, alpha(pal["hot"], 120))


def e_bone_spikes(p, pal):
    rim, gold, accent = pal["rim"], GOLD, pal["accent"]
    bone = mix(BONE, (150, 140, 118), 0.45)
    spikes = ((-0.50, 0.62, 0.30, -0.30), (-0.24, 0.66, 0.22, 0.10), (0.02, 0.62, 0.26, -0.56),
              (0.30, 0.64, 0.20, -0.02), (0.52, 0.66, 0.26, -0.38))
    for x, base, w, tip in spikes:
        p.poly([(x - w * 0.5, base), (x - w * 0.14, tip + 0.10), (x, tip), (x + w * 0.16, tip + 0.12),
                (x + w * 0.5, base), (x + w * 0.3, base + 0.10), (x - w * 0.3, base + 0.10)],
               fill=mix(bone, pal["deep"], 0.35), edge=rim, rim=0.004)
        p.line([(x - w * 0.2, base - 0.04), (x, tip + 0.16)], alpha(BONE, 120), 0.003)
        p.circle(x - w * 0.20, base + 0.04, 0.035, fill=mix(bone, INK, 0.25), edge=alpha(rim, 160), rim=0.002)
    # half buried skull
    sx, sy = -0.62, 0.52
    p.circle(sx, sy, 0.15, fill=mix(bone, pal["deep"], 0.30), edge=rim, rim=0.004)
    p.poly([(sx - 0.10, sy + 0.10), (sx + 0.10, sy + 0.10), (sx + 0.08, sy + 0.22), (sx - 0.06, sy + 0.22)],
           fill=mix(bone, pal["deep"], 0.30))
    p.circle(sx - 0.06, sy - 0.02, 0.045, fill=mix(INK, pal["deep"], 0.2))
    p.circle(sx + 0.06, sy - 0.02, 0.045, fill=mix(INK, pal["deep"], 0.2))
    p.dot_glow(sx, sy, 0.12, alpha(accent, 100))
    for _ in range(6):
        p.line([(-0.6, 0.66), (-0.2, 0.56)], alpha(pal["mist"], 40), 0.004)


def e_tomb_gate(p, pal):
    rim, gold, accent = pal["rim"], GOLD, pal["accent"]
    stone = mix(pal["metal"], pal["deep"], 0.35)
    for side in (-1, 1):
        x = side * 0.46
        p.poly([(x - 0.10, 0.70), (x + 0.10, 0.70), (x + 0.09, -0.28), (x - 0.09, -0.28)],
               fill=stone, edge=rim, rim=0.005)
        p.poly([(x - 0.14, -0.28), (x + 0.14, -0.28), (x + 0.10, -0.38), (x - 0.10, -0.38)],
               fill=stone, edge=rim, rim=0.004)
    p.line([(-0.46, -0.30), (-0.18, -0.66), (0.0, -0.82), (0.18, -0.66), (0.46, -0.30)],
           stone, 0.060, glow=(150, 120, 200))
    p.line([(-0.46, -0.30), (-0.18, -0.66), (0.0, -0.82), (0.18, -0.66), (0.46, -0.30)],
           mix(rim, BONE, 0.3), 0.012)
    for i in range(5):
        x = -0.32 + i * 0.16
        p.line([(x, 0.62), (x, -0.44)], alpha(mix(stone, BONE, 0.3), 200), 0.010)
    p.line([(-0.42, 0.62), (0.42, 0.62)], alpha(stone, 255), 0.018)
    # hanging lantern
    lx, ly = 0.0, -0.42
    p.line([(0.0, -0.52), (0.0, ly - 0.06)], alpha(gold, 220), 0.006)
    p.poly([(lx - 0.05, ly - 0.06), (lx + 0.05, ly - 0.06), (lx + 0.07, ly + 0.08), (lx - 0.07, ly + 0.08)],
           fill=mix(pal["hot"], BONE, 0.3), edge=mix(gold, INK, 0.2), rim=0.003)
    p.dot_glow(lx, ly, 0.16, alpha(pal["hot"], 200))
    for gx, gw in ((-0.28, 0.10), (0.30, 0.08)):
        p.poly([(gx - gw, 0.70), (gx + gw, 0.70), (gx + gw, 0.46), (gx, 0.38), (gx - gw, 0.46)],
               fill=mix(stone, INK, 0.25), edge=alpha(rim, 200), rim=0.003)


def e_gargoyle(p, pal):
    rim, gold, accent = pal["rim"], GOLD, pal["accent"]
    stone = mix(pal["metal"], BONE, 0.30)
    dark = mix(pal["deep"], (26, 28, 32), 0.45)
    # pedestal
    p.poly([(-0.50, 0.88), (0.50, 0.88), (0.42, 0.68), (-0.42, 0.68)],
           fill=mix(stone, INK, 0.42), edge=rim, rim=0.004)
    p.poly([(-0.38, 0.68), (0.38, 0.68), (0.30, 0.58), (-0.30, 0.58)],
           fill=mix(stone, INK, 0.28), edge=alpha(rim, 190), rim=0.003)
    # spread wings
    for s in (-1, 1):
        wing = [(s * 0.07, -0.34), (s * 0.30, -0.72), (s * 0.50, -0.64), (s * 0.44, -0.42),
                (s * 0.64, -0.34), (s * 0.42, -0.18), (s * 0.54, -0.02), (s * 0.26, -0.06), (s * 0.11, 0.06)]
        p.poly(wing, fill=dark, edge=alpha(accent, 200), rim=0.005)
        for k in range(3):
            p.line([(s * 0.20, -0.40 + k * 0.04), (s * (0.44 - k * 0.04), -0.58 + k * 0.12)],
                   alpha(rim, 120), 0.0032)
    # torso
    p.poly([(-0.13, -0.30), (0.13, -0.30), (0.19, 0.10), (0.13, 0.60), (-0.13, 0.60), (-0.19, 0.10)],
           fill=dark, edge=rim, rim=0.005)
    # horned head
    p.poly([(-0.12, -0.40), (0.12, -0.40), (0.14, -0.26), (0.06, -0.16), (-0.06, -0.16), (-0.14, -0.26)],
           fill=stone, edge=alpha(rim, 235), rim=0.004)
    p.poly([(-0.10, -0.40), (-0.16, -0.56), (-0.04, -0.46)], fill=stone, edge=alpha(rim, 150), rim=0.002)
    p.poly([(0.10, -0.40), (0.16, -0.56), (0.04, -0.46)], fill=stone, edge=alpha(rim, 150), rim=0.002)
    p.circle(-0.05, -0.30, 0.020, fill=accent)
    p.circle(0.05, -0.30, 0.020, fill=accent)
    p.dot_glow(-0.05, -0.30, 0.055, alpha(pal["hot"], 210))
    p.dot_glow(0.05, -0.30, 0.055, alpha(pal["hot"], 210))
    # claws on the rim of the plinth
    for s in (-1, 1):
        p.line([(s * 0.18, 0.54), (s * 0.30, 0.66)], stone, 0.016)
        p.line([(s * 0.24, 0.61), (s * 0.26, 0.68)], stone, 0.011)
    # sword planted through the plinth
    p.poly([(0.0, 0.82), (0.065, 0.56), (0.055, 0.02), (0.0, -0.04), (-0.055, 0.02), (-0.065, 0.56)],
           fill=mix(stone, BONE, 0.28), edge=rim, rim=0.0045)
    p.poly([(-0.23, 0.0), (0.23, 0.0), (0.23, 0.09), (-0.23, 0.09)],
           fill=mix(gold, INK, 0.30), edge=gold, rim=0.0035)
    p.poly([(-0.035, 0.09), (0.035, 0.09), (0.03, 0.34), (-0.03, 0.34)],
           fill=mix(dark, gold, 0.25), edge=gold, rim=0.0025)
    p.circle(0.0, 0.38, 0.055, fill=mix(gold, INK, 0.45), edge=gold, rim=0.003)
    p.line([(0.0, 0.20), (0.0, 0.72)], alpha(BONE, 120), 0.003)


def e_sigil(p, pal):
    rim, gold, accent = pal["rim"], GOLD, pal["accent"]
    p.circle(0.0, -0.02, 0.76, fill=(0, 0, 0, 0), edge=alpha(accent, 190), rim=0.007)
    p.circle(0.0, -0.02, 0.62, fill=(0, 0, 0, 0), edge=alpha(accent, 120), rim=0.0035)
    p.circle(0.0, -0.02, 0.30, fill=alpha(mix(pal["deep"], accent, 0.25), 120), edge=alpha(pal["hot"], 210), rim=0.005)
    for i in range(24):
        ang = i * math.tau / 24
        r0, r1 = 0.68, 0.76
        p.line([(math.cos(ang) * r0, -0.02 + math.sin(ang) * r0),
                (math.cos(ang) * r1, -0.02 + math.sin(ang) * r1)], alpha(accent, 170), 0.0035)
    glyph_rng = random.Random(7)
    for i in range(8):
        ang = i * math.tau / 8 + 0.1
        cx = math.cos(ang) * 0.46
        cy = -0.02 + math.sin(ang) * 0.46
        for _ in range(3):
            a0 = glyph_rng.uniform(0, math.tau)
            ln = glyph_rng.uniform(0.03, 0.06)
            p.line([(cx, cy), (cx + math.cos(a0) * ln, cy + math.sin(a0) * ln)], alpha(pal["hot"], 200), 0.0035)
    for ang in (0, 60, 120):
        x0 = math.cos(math.radians(ang)) * 0.30
        y0 = -0.02 + math.sin(math.radians(ang)) * 0.30
        x1 = math.cos(math.radians(ang + 180)) * 0.30
        y1 = -0.02 + math.sin(math.radians(ang + 180)) * 0.30
        p.line([(x0, y0), (x1, y1)], alpha(accent, 90), 0.004)
    # chain
    for i in range(5):
        t = i / 4.0
        x = -0.72 + t * 0.62
        y = 0.58 - t * 1.04
        p.circle(x, y, 0.045, fill=(0, 0, 0, 0), edge=alpha(BONE, 130), rim=0.004)
    for sx, sy, s in ((0.86, -0.44, 0.05), (-0.86, 0.34, 0.04), (0.74, 0.52, 0.035)):
        p.poly([(sx, sy - s), (sx + s, sy), (sx, sy + s), (sx - s, sy)], fill=alpha(accent, 160),
               edge=alpha(pal["hot"], 200), rim=0.002)


def e_tuning_fork(p, pal):
    rim, gold, accent = pal["rim"], GOLD, pal["accent"]
    bronze = mix(pal["metal"], accent, 0.52)
    p.poly([(-0.055, 0.94), (0.055, 0.94), (0.045, 0.34), (-0.045, 0.34)],
           fill=bronze, edge=gold, rim=0.004)
    p.circle(0.0, 0.96, 0.075, fill=(0, 0, 0, 0), edge=gold, rim=0.006)
    p.poly([(-0.21, 0.40), (0.21, 0.40), (0.175, 0.24), (-0.175, 0.24)],
           fill=mix(bronze, INK, 0.25), edge=gold, rim=0.005)
    for s in (-1, 1):
        pts = [(s * 0.145, 0.26), (s * 0.235, -0.16), (s * 0.200, -0.70)]
        p.line(pts, mix(gold, INK, 0.30), 0.120)
        p.line(pts, mix(bronze, BONE, 0.20), 0.092)
        p.line([(s * 0.200, -0.70), (s * 0.180, -0.80)], mix(gold, INK, 0.20), 0.092)
    for i in range(3):
        p.arc(0.0, -0.16, 0.36 + i * 0.13, 118, 242, alpha(accent, 120 - i * 32), 0.005)
        p.arc(0.0, -0.16, 0.36 + i * 0.13, -62, 62, alpha(accent, 120 - i * 32), 0.005)
    for x, y, s in ((-0.44, -0.36, 0.036), (0.46, -0.10, 0.032), (-0.38, 0.18, 0.026)):
        p.circle(x, y + s, s * 0.62, fill=alpha(pal["hot"], 210))
        p.line([(x + s * 0.5, y + s), (x + s * 0.5, y - s * 1.7)], alpha(pal["hot"], 210), 0.004)
    p.dot_glow(0.0, -0.30, 0.34, alpha(accent, 70))


def e_handbell(p, pal):
    rim, gold, accent = pal["rim"], GOLD, pal["accent"]
    bronze = mix(pal["metal"], accent, 0.55)
    bell = [(-0.15, -0.40), (-0.22, -0.20), (-0.30, 0.10), (-0.38, 0.30), (-0.42, 0.36),
            (0.42, 0.36), (0.38, 0.30), (0.30, 0.10), (0.22, -0.20), (0.15, -0.40)]
    p.poly(bell, fill=bronze, edge=gold, rim=0.007)
    p.line([(-0.42, 0.34), (0.42, 0.34)], mix(gold, BONE, 0.30), 0.013)
    p.line([(-0.36, 0.14), (0.36, 0.14)], alpha(mix(gold, INK, 0.15), 225), 0.006)
    p.line([(-0.31, -0.04), (0.31, -0.04)], alpha(mix(gold, INK, 0.15), 200), 0.006)
    for s in (-1, 1):
        p.line([(s * 0.14, -0.34), (s * 0.20, -0.06), (s * 0.26, 0.20)], alpha(BONE, 80), 0.005)
    p.circle(0.0, -0.47, 0.075, fill=(0, 0, 0, 0), edge=gold, rim=0.007)
    p.line([(0.0, -0.55), (0.0, -0.88)], mix(BONE, (120, 108, 88), 0.45), 0.018)
    p.line([(0.0, 0.36), (0.0, 0.46)], mix(gold, INK, 0.40), 0.020)
    p.circle(0.0, 0.50, 0.065, fill=mix(bronze, BONE, 0.22), edge=gold, rim=0.004)
    for i in range(3):
        p.arc(0.0, 0.08, 0.52 + i * 0.13, 205, 335, alpha(accent, 100 - i * 27), 0.005)
        p.arc(0.0, 0.08, 0.52 + i * 0.13, 25, 155, alpha(accent, 100 - i * 27), 0.005)
    p.dot_glow(0.0, 0.50, 0.14, alpha(pal["hot"], 95))


def e_stele(p, pal):
    rim, gold, accent = pal["rim"], GOLD, pal["accent"]
    stone = mix(pal["metal"], pal["rim"], 0.24)
    pts = [(-0.34, 0.46), (-0.34, -0.34)]
    for a in range(200, 341, 20):
        pts.append((0.34 * math.cos(math.radians(a)), -0.34 + 0.34 * math.sin(math.radians(a))))
    pts.append((0.34, 0.46))
    p.poly(pts, fill=stone, edge=rim, rim=0.006)
    p.poly([(-0.46, 0.46), (0.46, 0.46), (0.42, 0.58), (-0.42, 0.58)],
           fill=mix(stone, INK, 0.22), edge=alpha(rim, 210), rim=0.004)
    p.poly([(-0.52, 0.58), (0.52, 0.58), (0.48, 0.70), (-0.48, 0.70)],
           fill=mix(stone, INK, 0.34), edge=alpha(rim, 180), rim=0.004)
    for r, a in ((0.115, 210), (0.175, 150), (0.235, 100)):
        p.circle(0.0, -0.14, r, fill=(0, 0, 0, 0), edge=alpha(accent, a), rim=0.004)
    for i in range(10):
        ang = i * math.tau / 10 + 0.2
        p.line([(math.cos(ang) * 0.255, -0.14 + math.sin(ang) * 0.255),
                (math.cos(ang) * 0.290, -0.14 + math.sin(ang) * 0.290)], alpha(accent, 180), 0.0035)
    p.line([(0.0, -0.30), (0.0, 0.40)], alpha(accent, 120), 0.004)
    p.line([(-0.26, 0.30), (0.26, 0.30)], alpha(accent, 90), 0.003)
    # chisel biting the face, hammer behind
    p.line([(-0.80, -0.66), (-0.10, -0.14)], mix(pal["metal"], BONE, 0.25), 0.040)
    p.poly([(-0.16, -0.20), (-0.02, -0.08), (-0.10, 0.02), (-0.24, -0.10)],
           fill=mix(BONE, pal["metal"], 0.25), edge=rim, rim=0.003)
    p.line([(-0.80, -0.66), (-0.96, -0.80)], mix((92, 70, 50), INK, 0.25), 0.028)
    p.poly([(-0.90, -0.92), (-0.66, -0.80), (-0.74, -0.66), (-0.98, -0.78)],
           fill=mix(pal["metal"], INK, 0.2), edge=rim, rim=0.0035)
    for cx, cy, s in ((0.04, -0.02, 0.030), (-0.10, -0.06, 0.022), (0.14, -0.10, 0.018)):
        p.poly([(cx, cy - s), (cx + s, cy), (cx, cy + s * 0.8), (cx - s * 0.7, cy - s * 0.2)],
               fill=mix(stone, BONE, 0.20), edge=alpha(rim, 150), rim=0.0018)
    p.dot_glow(-0.06, -0.10, 0.12, alpha(pal["hot"], 70))


def e_corridor(p, pal):
    rim, gold, accent = pal["rim"], GOLD, pal["accent"]
    stone = mix(pal["metal"], pal["rim"], 0.14)
    for i in range(4):
        j = 3 - i
        w = 0.30 + j * 0.18
        top = 0.02 - j * 0.10
        depth = 0.20 + j * 0.13
        col = mix(stone, INK, depth)
        p.line([(-w, 0.86), (-w, top)], col, 0.030)
        p.line([(w, 0.86), (w, top)], col, 0.030)
        p.arc(0.0, top, w, 180, 360, col, 0.030)
        p.line([(w, 0.86), (-w, 0.86)], alpha(mix(col, BONE, 0.18), 120), 0.008)
    for s in (-1, 1):
        p.line([(s * 0.96, 0.94), (0.0, 0.04)], alpha(mix(stone, BONE, 0.30), 70), 0.003)
        p.line([(s * 0.70, 0.94), (0.0, 0.04)], alpha(mix(stone, BONE, 0.30), 50), 0.0025)
    # bell at the vanishing point
    p.line([(0.0, -0.20), (0.0, -0.02)], alpha(mix(gold, BONE, 0.3), 200), 0.006)
    p.poly([(-0.045, -0.02), (0.045, -0.02), (0.070, 0.10), (0.090, 0.16),
            (-0.090, 0.16), (-0.070, 0.10)], fill=mix(accent, pal["deep"], 0.25),
           edge=alpha(pal["hot"], 220), rim=0.004)
    p.circle(0.0, 0.20, 0.020, fill=alpha(BONE, 200))
    for i in range(3):
        p.arc(0.0, 0.04, 0.22 + i * 0.10, 190, 350, alpha(accent, 130 - i * 35), 0.004)
        p.arc(0.0, 0.04, 0.22 + i * 0.10, 10, 170, alpha(accent, 130 - i * 35), 0.004)
    p.dot_glow(0.0, 0.04, 0.22, alpha(pal["hot"], 80))


def e_lamp_needle(p, pal):
    rim, gold, accent = pal["rim"], GOLD, pal["accent"]
    iron = mix(pal["metal"], INK, 0.15)
    p.poly([(-0.105, 0.44), (0.105, 0.44), (0.105, -0.40), (-0.105, -0.40)],
           fill=mix(BONE, (198, 184, 150), 0.55), edge=alpha(rim, 200), rim=0.0035)
    p.line([(-0.075, 0.40), (-0.075, -0.36)], alpha(BONE, 120), 0.006)
    for s, h in ((-1, 0.10), (1, 0.16)):
        p.poly([(s * 0.100, 0.36), (s * 0.128, 0.36 - h), (s * 0.100, 0.30 - h)],
               fill=mix(BONE, accent, 0.35), edge=alpha(rim, 160), rim=0.0018)
    p.poly([(-0.10, 0.44), (0.10, 0.44), (0.14, 0.56), (0.0, 0.90), (-0.14, 0.56)],
           fill=iron, edge=gold, rim=0.005)
    p.line([(0.0, 0.56), (0.0, 0.86)], alpha(BONE, 90), 0.004)
    p.line([(0.0, -0.40), (0.0, -0.50)], mix(INK, pal["deep"], 0.2), 0.012)
    p.poly([(0.0, -0.92), (0.062, -0.74), (0.075, -0.60), (0.0, -0.50),
            (-0.075, -0.60), (-0.062, -0.74)], fill=alpha(mix(accent, pal["hot"], 0.55), 235),
           edge=alpha(pal["hot"], 240), rim=0.004)
    p.poly([(0.0, -0.80), (0.040, -0.68), (0.0, -0.57), (-0.040, -0.68)],
           fill=alpha(mix(pal["hot"], BONE, 0.55), 240))
    p.dot_glow(0.0, -0.70, 0.24, alpha(pal["hot"], 120))
    for x, y, s, a in ((-0.34, -0.52, 0.024, 200), (0.30, -0.36, 0.018, 170), (0.22, 0.12, 0.014, 140)):
        p.circle(x, y, s, fill=alpha(pal["hot"], a))


def e_lantern_guard(p, pal):
    rim, gold, accent = pal["rim"], GOLD, pal["accent"]
    iron = mix(pal["metal"], INK, 0.12)
    p.circle(0.0, -0.52, 0.075, fill=(0, 0, 0, 0), edge=gold, rim=0.007)
    p.arc(0.0, -0.52, 0.16, 200, 340, alpha(mix(gold, BONE, 0.3), 180), 0.005)
    p.poly([(-0.26, -0.40), (0.26, -0.40), (0.19, -0.26), (-0.19, -0.26)],
           fill=iron, edge=gold, rim=0.005)
    p.poly([(-0.20, -0.24), (0.20, -0.24), (0.22, 0.26), (-0.22, 0.26)],
           fill=alpha(pal["hot"], 34), edge=gold, rim=0.004)
    for bx in (-0.20, -0.07, 0.07, 0.20):
        p.line([(bx, -0.24), (bx, 0.26)], alpha(mix(gold, INK, 0.25), 230), 0.005)
    p.poly([(-0.26, 0.28), (0.26, 0.28), (0.19, 0.42), (-0.19, 0.42)],
           fill=iron, edge=gold, rim=0.005)
    p.line([(0.0, 0.42), (0.0, 0.56)], iron, 0.022)
    p.poly([(0.0, 0.62), (0.36, 0.56), (0.44, 0.44), (0.0, 0.50)],
           fill=alpha(mix(gold, INK, 0.15), 210), edge=alpha(gold, 180), rim=0.003)
    p.poly([(0.0, 0.02), (0.075, 0.14), (0.090, 0.22), (0.0, 0.30),
            (-0.090, 0.22), (-0.075, 0.14)], fill=alpha(mix(pal["hot"], BONE, 0.35), 235))
    p.dot_glow(0.0, 0.14, 0.22, alpha(pal["hot"], 150))
    for i in range(3):
        y = -0.02 + i * 0.16
        p.line([(-0.98, y + 0.10), (-0.62, y - 0.06), (-0.30, y + 0.08), (0.02, y - 0.02)],
               alpha(mix(pal["rim"], pal["hot"], 0.5), 90 - i * 20), 0.006)
        p.line([(0.98, y + 0.04), (0.60, y + 0.14), (0.30, y - 0.02)], alpha(pal["rim"], 70 - i * 15), 0.005)


def e_ember_bed(p, pal):
    rim, gold, accent = pal["rim"], GOLD, pal["accent"]
    ash = mix(pal["metal"], pal["mist"], 0.35)
    p.poly([(-0.66, 0.60), (-0.46, 0.26), (-0.20, 0.12), (0.28, 0.14), (0.56, 0.30),
            (0.68, 0.60), (0.20, 0.66), (-0.30, 0.66)], fill=ash, edge=alpha(rim, 120), rim=0.003)
    p.poly([(-0.48, 0.34), (-0.20, 0.22), (0.26, 0.24), (0.50, 0.36), (0.22, 0.44), (-0.22, 0.42)],
           fill=alpha(mix(pal["deep"], pal["hot"], 0.18), 220))
    for pts in ([(-0.40, 0.44), (-0.22, 0.34), (-0.02, 0.40), (0.18, 0.30), (0.38, 0.38)],
                [(-0.10, 0.46), (0.06, 0.34), (0.24, 0.42)],
                [(-0.50, 0.38), (-0.34, 0.30), (-0.26, 0.40)]):
        p.line(pts, (255, 176, 96), 0.007, glow=(255, 120, 50))
    for x, y, r in ((-0.34, 0.38, 0.027), (-0.12, 0.40, 0.020), (0.10, 0.34, 0.030),
                    (0.32, 0.38, 0.018), (-0.52, 0.48, 0.016), (0.46, 0.46, 0.014)):
        p.circle(x, y, r, fill=alpha(mix(pal["hot"], (255, 210, 130), 0.5), 235))
        p.dot_glow(x, y, r * 2.4, alpha(pal["hot"], 120))
    for fx, fw, fh in ((-0.22, 0.10, 0.20), (0.18, 0.07, 0.14), (0.02, 0.05, 0.10)):
        p.poly([(fx, 0.40 - fh), (fx + fw * 0.6, 0.40 - fh * 0.45), (fx + fw, 0.40),
                (fx, 0.44), (fx - fw, 0.40), (fx - fw * 0.55, 0.40 - fh * 0.42)],
               fill=alpha(mix(pal["hot"], BONE, 0.20), 200))
    p.line([(0.72, -0.54), (0.30, 0.10), (0.16, 0.36)], mix(pal["metal"], INK, 0.30), 0.026)
    p.arc(0.16, 0.36, 0.10, 40, 200, mix(pal["metal"], INK, 0.30), 0.022)
    p.dot_glow(0.12, 0.36, 0.14, alpha(pal["hot"], 90))


def e_split_flame(p, pal):
    rim, gold, accent = pal["rim"], GOLD, pal["accent"]
    iron = mix(pal["metal"], INK, 0.18)
    p.poly([(-0.40, 0.58), (0.40, 0.58), (0.30, 0.72), (-0.30, 0.72)],
           fill=iron, edge=gold, rim=0.005)
    p.line([(0.0, 0.72), (0.0, 0.94)], iron, 0.030)
    p.poly([(-0.20, 0.92), (0.20, 0.92), (0.14, 0.98), (-0.14, 0.98)],
           fill=mix(iron, gold, 0.25), edge=alpha(gold, 180), rim=0.003)
    for cx, tip, base, w, col in (
        (0.0, -0.44, 0.58, 0.115, mix(pal["hot"], BONE, 0.30)),
        (-0.30, 0.02, 0.56, 0.075, mix(pal["hot"], accent, 0.25)),
        (0.30, 0.04, 0.56, 0.070, mix(pal["hot"], accent, 0.30)),
    ):
        p.poly([(cx, tip), (cx + w * 0.6, base - (base - tip) * 0.45), (cx + w, base),
                (cx + w * 0.3, base + 0.02), (cx - w * 0.3, base + 0.02), (cx - w, base),
                (cx - w * 0.55, base - (base - tip) * 0.42)],
               fill=alpha(col, 225), edge=alpha(pal["hot"], 210), rim=0.003)
        p.dot_glow(cx, (tip + base) / 2, w * 2.6, alpha(pal["hot"], 80))
    p.arc(0.0, 0.44, 0.34, 250, 290, alpha(mix(pal["hot"], accent, 0.3), 190), 0.005)
    p.arc(0.0, 0.44, 0.34, 70, 110, alpha(mix(pal["hot"], accent, 0.3), 190), 0.005)
    for x, y, s in ((-0.46, 0.14, 0.020), (0.44, 0.22, 0.016), (-0.20, -0.10, 0.013), (0.24, -0.06, 0.012)):
        p.circle(x, y, s, fill=alpha(pal["hot"], 190))
        p.dot_glow(x, y, s * 2.5, alpha(pal["hot"], 90))


EMBLEMS = {
    "greatsword": e_greatsword, "tower_shield": e_tower_shield, "broken_plate": e_broken_plate,
    "brazier": e_brazier, "dagger": e_dagger, "feather": e_feather, "sickle": e_sickle,
    "campfire": e_campfire, "gauntlet": e_gauntlet, "hex_barrier": e_hex_barrier,
    "core_orb": e_core_orb, "twin_orbs": e_twin_orbs, "scepter": e_scepter,
    "knight_vow": e_knight_vow, "falling_star": e_falling_star, "anvil": e_anvil,
    "bone_spikes": e_bone_spikes, "tomb_gate": e_tomb_gate, "gargoyle": e_gargoyle,
    "sigil": e_sigil, "tuning_fork": e_tuning_fork, "handbell": e_handbell, "stele": e_stele,
    "corridor": e_corridor, "lamp_needle": e_lamp_needle, "lantern_guard": e_lantern_guard,
    "ember_bed": e_ember_bed, "split_flame": e_split_flame,
}


# --------------------------------------------------------------------- fx ----

def fx_layer(pal, rng, kind, emblem_center):
    img = Image.new("RGBA", (CW, CH), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    warm = pal["hot"]
    if kind == "embers":
        for _ in range(46):
            x = CW * rng.uniform(0.18, 0.82)
            y = CH * rng.uniform(0.28, 0.86)
            r = rng.uniform(0.8, 3.2)
            d.ellipse([x - r, y - r, x + r, y + r], fill=alpha(mix(warm, (255, 190, 120), rng.random()), rng.uniform(90, 210)))
    elif kind == "ash":
        for _ in range(70):
            x = CW * rng.uniform(0.0, 1.0)
            y = CH * rng.uniform(0.10, 0.95)
            r = rng.uniform(0.7, 2.2)
            d.ellipse([x - r, y - r, x + r, y + r], fill=alpha(mix(pal["mist"], BONE, rng.uniform(0.2, 0.7)), rng.uniform(30, 110)))
    elif kind == "sparks":
        cx, cy = emblem_center
        for _ in range(26):
            ang = rng.uniform(0, math.tau)
            dist = rng.uniform(0.18, 0.55) * CH
            x = cx + math.cos(ang) * dist
            y = cy + math.sin(ang) * dist * 0.6
            ln = rng.uniform(0.01, 0.045) * CH
            d.line([(x, y), (x + math.cos(ang) * ln, y + math.sin(ang) * ln)],
                   fill=alpha(warm, rng.uniform(120, 230)), width=max(1, int(rng.uniform(1, 3))))
    elif kind == "dust":
        for _ in range(55):
            x = CW * rng.uniform(0.1, 0.9)
            y = CH * rng.uniform(0.2, 0.92)
            r = rng.uniform(0.6, 2.0)
            d.ellipse([x - r, y - r, x + r, y + r], fill=alpha(mix(BONE, pal["mist"], 0.4), rng.uniform(26, 90)))
    elif kind == "leaves":
        for _ in range(14):
            x = CW * rng.uniform(0.1, 0.9)
            y = CH * rng.uniform(0.18, 0.8)
            s = rng.uniform(0.008, 0.022) * CH
            ang = rng.uniform(0, math.tau)
            pts = [(x + math.cos(ang + t) * s, y + math.sin(ang + t) * s * 0.55) for t in (-0.9, 0.0, 0.9)]
            d.polygon(pts, fill=alpha(mix(pal["accent"], BONE, 0.25), rng.uniform(60, 140)))
    elif kind == "lightning":
        for _ in range(3):
            x, y = CW * rng.uniform(0.25, 0.75), CH * rng.uniform(0.25, 0.55)
            pts = [(x, y)]
            for _ in range(5):
                x += rng.uniform(-0.05, 0.05) * CW
                y += rng.uniform(0.02, 0.08) * CH
                pts.append((x, y))
            d.line(pts, fill=alpha(mix(warm, (255, 255, 255), 0.3), 220), width=max(1, int(CW * 0.0022)))
    elif kind == "drips":
        for _ in range(12):
            x = CW * rng.uniform(0.3, 0.7)
            y = CH * rng.uniform(0.35, 0.7)
            r = rng.uniform(1.5, 4.0)
            d.polygon([(x, y), (x + r, y + r * 2.2), (x, y + r * 3.0), (x - r, y + r * 2.2)],
                      fill=alpha(mix(pal["hot"], (150, 220, 140), 0.5), 170))
    elif kind == "motes":
        for _ in range(40):
            x = CW * rng.uniform(0.15, 0.85)
            y = CH * rng.uniform(0.15, 0.8)
            r = rng.uniform(0.7, 2.6)
            d.ellipse([x - r, y - r, x + r, y + r], fill=alpha(warm, rng.uniform(70, 180)))
    elif kind == "stars":
        for _ in range(18):
            x = CW * rng.uniform(0.05, 0.95)
            y = CH * rng.uniform(0.05, 0.55)
            r = rng.uniform(1.0, 3.0)
            d.line([(x - r * 2, y), (x + r * 2, y)], fill=alpha(BONE, 120), width=1)
            d.line([(x, y - r * 2), (x, y + r * 2)], fill=alpha(BONE, 120), width=1)
    elif kind == "wisps":
        for _ in range(9):
            x = CW * rng.uniform(0.12, 0.88)
            y = CH * rng.uniform(0.45, 0.9)
            r = rng.uniform(0.02, 0.05) * CH
            d.ellipse([x - r, y - r * 1.5, x + r, y + r * 1.5], fill=alpha(mix(pal["hot"], BONE, 0.3), rng.uniform(30, 80)))
    return img.filter(ImageFilter.GaussianBlur(CW * 0.0018))


# ------------------------------------------------------------------- build ---

def render(card_id, cfg):
    pal = ROLES[cfg["role"]]
    rng = random.Random(zlib.crc32(card_id.encode("utf-8")))
    hz = cfg["horizon"]

    img = sky(pal, cfg, rng)
    moon(img, pal, cfg, rng)
    ground(img, pal, rng, hz)
    img.alpha_composite(SCENES[cfg["scene"]](pal, rng, hz))
    haze(img, pal, rng, hz)

    size = CH * 0.67
    pen = Pen(size)
    EMBLEMS[cfg["emblem"]](pen, pal)
    pen.img = shade_vertical(pen.img, 1.30, 0.66)
    lifted = np.asarray(pen.img).astype(np.float32)
    lifted[..., :3] = np.clip(lifted[..., :3] * 1.14 + 7.0, 0, 255)
    pen.img = Image.fromarray(lifted.astype(np.uint8))

    angle = cfg.get("angle", 0.0)
    if abs(angle) > 0.01:
        pen.img = pen.img.rotate(angle, resample=Image.BICUBIC, center=(pen.L / 2, pen.L / 2))
        pen.glow = pen.glow.rotate(angle, resample=Image.BICUBIC, center=(pen.L / 2, pen.L / 2))

    bbox = pen.img.getbbox() or (0, 0, pen.L, pen.L)
    if cfg.get("float"):
        art_cx = CW * 0.5
        art_cy = CH * float(cfg.get("float_y", 0.46))
    else:
        ground_y = CH * (hz + 0.02)
        art_cy = ground_y - (bbox[3] - pen.L / 2.0)
        art_cx = CW * 0.5 - ((bbox[0] + bbox[2]) / 2.0 - pen.L / 2.0)
    headroom = art_cy - pen.L / 2.0 + bbox[1]
    if headroom < CH * 0.05:
        art_cy += CH * 0.05 - headroom

    # halo behind the emblem: wide accent bloom + a crisp moonlit contour
    alpha_mask = pen.img.split()[3]
    for blur, strength in ((size * 0.045, 80), (size * 0.14, 32)):
        halo = Image.new("RGBA", pen.img.size, alpha(pal["accent"], 0))
        halo.putalpha(alpha_mask.filter(ImageFilter.GaussianBlur(blur)).point(lambda v: int(v * strength / 255)))
        img.alpha_composite(halo, (int(art_cx - pen.L / 2), int(art_cy - pen.L / 2)))

    grown = alpha_mask.filter(ImageFilter.MaxFilter(9))
    ring = ImageChops.subtract(grown, alpha_mask).filter(ImageFilter.GaussianBlur(2.4))
    contour = Image.new("RGBA", pen.img.size, (0, 0, 0, 0))
    contour.paste(mix(pal["rim"], pal["hot"], 0.35),
                  (0, 0), ring.point(lambda v: int(v * 0.60)))
    pen.img = Image.alpha_composite(pen.img, contour)

    img.alpha_composite(pen.img, (int(art_cx - pen.L / 2), int(art_cy - pen.L / 2)))

    glow = pen.glow.filter(ImageFilter.GaussianBlur(size * 0.020))
    canvas_glow = Image.new("RGBA", (CW, CH), (0, 0, 0, 0))
    canvas_glow.alpha_composite(glow, (int(art_cx - pen.L / 2), int(art_cy - pen.L / 2)))
    img = screen_add(img, canvas_glow, 0.9)

    img = screen_add(img, fx_layer(pal, rng, cfg["fx"], (art_cx, art_cy)), 0.75)
    foreground(img, pal, rng, hz)

    img = img.convert("RGB").resize((W, H), Image.LANCZOS)
    return grade(img, pal, zlib.crc32((card_id + ":grade").encode("utf-8")))


def grade(img, pal, seed):
    rng = np.random.default_rng(seed)
    a = np.asarray(img).astype(np.float32) / 255.0
    lum = a[..., 0] * 0.2126 + a[..., 1] * 0.7152 + a[..., 2] * 0.0722

    yy, xx = np.mgrid[0:H, 0:W].astype(np.float32)
    # engraving hatch, kept to the midtones so highlights stay clean
    hatch = np.sin(xx * 0.80 + yy * 1.65) * np.sin(xx * 0.29 - yy * 0.86)
    mask = np.clip((lum - 0.03) / 0.16, 0, 1) * np.clip((0.60 - lum) / 0.32, 0, 1)
    a += (hatch * mask)[..., None] * 0.028

    # colour grade: cool the shadows, keep class light in the highs
    shadow = np.clip(1.0 - lum / 0.34, 0, 1)[..., None]
    a *= 1.0 - shadow * 0.16
    a += shadow * (np.array(mix(pal["deep"], pal["accent"], 0.35), np.float32) / 255.0) * 0.10
    a += np.clip(lum - 0.55, 0, 1)[..., None] * (np.array(pal["rim"], np.float32) / 255.0) * 0.05

    # film grain
    grain = rng.normal(0.0, 1.0, (H, W, 1)).astype(np.float32)
    a += grain * 0.012

    # vignette
    cx, cy = W * 0.5, H * 0.48
    dist = np.sqrt(((xx - cx) / (W * 0.62)) ** 2 + ((yy - cy) / (H * 0.66)) ** 2)
    vig = np.clip(1.0 - 0.62 * dist ** 2.4, 0, 1)[..., None]
    a *= vig

    a = np.clip(a, 0, 1)
    a = a ** 1.02
    return Image.fromarray((a * 255.0).astype(np.uint8))


def card_names():
    names = {}
    if CATALOG.exists():
        try:
            data = json.loads(CATALOG.read_text(encoding="utf-8"))
            for card in data.get("cards", []):
                names[card.get("id", "")] = card.get("name", "")
        except Exception:
            pass
    return names


def contact_sheet(ids):
    names = card_names()
    tw, th = 320, 180
    pad, label_h = 18, 44
    cols, rows = 4, 5
    sheet_w = pad + cols * (tw + pad)
    sheet_h = pad + rows * (th + label_h + pad)
    sheet = Image.new("RGB", (sheet_w, sheet_h), (14, 15, 14))
    d = ImageDraw.Draw(sheet)
    font = small = ImageFont.load_default()
    for path in ("/System/Library/Fonts/Hiragino Sans GB.ttc",
                 "/System/Library/Fonts/STHeiti Light.ttc",
                 "/System/Library/Fonts/Supplemental/Songti.ttc"):
        try:
            font = ImageFont.truetype(path, 24)
            small = ImageFont.truetype(path, 17)
            break
        except Exception:
            continue
    for i, card_id in enumerate(ids):
        role = CARDS[card_id]["role"]
        col, row = i % cols, i // cols
        x = pad + col * (tw + pad)
        y = pad + row * (th + label_h + pad)
        art = Image.open(CARD_DIR / f"{card_id}.webp").convert("RGB").resize((tw, th), Image.LANCZOS)
        sheet.paste(art, (x, y))
        d.rectangle([x, y, x + tw - 1, y + th - 1], outline=mix(ROLES[role]["accent"], GOLD, 0.45), width=1)
        d.text((x + 2, y + th + 4), f"{card_id}", font=small, fill=mix(ROLES[role]["accent"], BONE, 0.55))
        d.text((x + 2, y + th + 22), names.get(card_id, ""), font=font, fill=BONE)
    SHEET_PATH.parent.mkdir(parents=True, exist_ok=True)
    sheet.save(SHEET_PATH)
    return SHEET_PATH


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--only", default="")
    parser.add_argument("--sheet", action="store_true")
    args = parser.parse_args()

    ids = [c.strip() for c in args.only.split(",") if c.strip()] or list(CARDS)
    CARD_DIR.mkdir(parents=True, exist_ok=True)
    for card_id in ids:
        if card_id not in CARDS:
            raise SystemExit(f"unknown card id: {card_id}")
        image = render(card_id, CARDS[card_id])
        path = CARD_DIR / f"{card_id}.webp"
        image.save(path, "WEBP", quality=92, method=6)
        print(f"{card_id:12s} {path.relative_to(ROOT)}  {path.stat().st_size/1024:.1f} KiB")
    if args.sheet:
        print("contact sheet:", contact_sheet(list(CARDS)).relative_to(ROOT))


if __name__ == "__main__":
    main()
