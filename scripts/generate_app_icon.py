#!/usr/bin/env python3
"""Generate a high-resolution dark fantasy macOS app icon for 灰誓 (Grey Oath)."""
import math
import os
import subprocess
import shutil
from pathlib import Path
from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = Path(__file__).resolve().parents[1]
ART_DIR = ROOT / "assets" / "art"
ICON_PNG = ART_DIR / "icon.png"
ICON_ICNS = ART_DIR / "icon.icns"
ICONSET_DIR = ART_DIR / "icon.iconset"

def create_master_icon() -> Image.Image:
    SIZE = 1024
    img = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    
    # 1. Base Squircle Mask (Apple macOS standard: ~22.5% radius = 230px)
    pad = 52
    rect = [pad, pad, SIZE - pad, SIZE - pad]
    radius = 210
    
    # Create mask for smooth edges
    mask = Image.new("L", (SIZE, SIZE), 0)
    mask_draw = ImageDraw.Draw(mask)
    mask_draw.rounded_rectangle(rect, radius=radius, fill=255)
    
    # Background Canvas with dark fantasy gradient (obsidian to dark moss ash)
    bg = Image.new("RGBA", (SIZE, SIZE), (13, 17, 15, 255))
    bg_draw = ImageDraw.Draw(bg)
    
    # Radial dark vignette from center
    cx, cy = SIZE // 2, SIZE // 2
    for r in range(500, 0, -10):
        factor = r / 500.0
        # Interpolate between deep center (#1c231f) and dark edges (#0a0d0b)
        red = int(10 + (28 - 10) * (1 - factor))
        green = int(13 + (35 - 13) * (1 - factor))
        blue = int(11 + (31 - 11) * (1 - factor))
        bg_draw.ellipse([cx - r, cy - r, cx + r, cy + r], fill=(red, green, blue, 255))
        
    # Apply squircle mask to bg
    canvas = Image.composite(bg, Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0)), mask)
    c_draw = ImageDraw.Draw(canvas)
    
    # 2. Outer Rim & Border (Layered Gold & Dark Iron)
    c_draw.rounded_rectangle(rect, radius=radius, outline=(68, 72, 59, 255), width=10)
    inner_rect = [pad + 12, pad + 12, SIZE - pad - 12, SIZE - pad - 12]
    c_draw.rounded_rectangle(inner_rect, radius=radius - 10, outline=(199, 166, 106, 200), width=4)
    innermost_rect = [pad + 20, pad + 20, SIZE - pad - 20, SIZE - pad - 20]
    c_draw.rounded_rectangle(innermost_rect, radius=radius - 16, outline=(40, 44, 38, 255), width=2)
    
    # Corner rivets / studs
    studs = [
        (pad + 75, pad + 75),
        (SIZE - pad - 75, pad + 75),
        (pad + 75, SIZE - pad - 75),
        (SIZE - pad - 75, SIZE - pad - 75),
    ]
    for sx, sy in studs:
        c_draw.ellipse([sx - 12, sy - 12, sx + 12, sy + 12], fill=(30, 34, 30, 255), outline=(199, 166, 106, 220), width=3)
        c_draw.ellipse([sx - 4, sy - 4, sx + 4, sy + 4], fill=(226, 196, 134, 255))
        
    # 3. Behind Heraldry: Dual Crossed Broken Blades
    sword_color = (130, 136, 132, 230)
    sword_gold = (199, 166, 106, 240)
    sword_shadow = (10, 12, 10, 200)
    
    for angle_deg in [-35, 35]:
        sw = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
        sw_draw = ImageDraw.Draw(sw)
        
        # Blade along vertical, then rotate
        bx = cx
        # Blade points
        blade = [
            (bx - 16, 200),
            (bx, 150),
            (bx + 16, 200),
            (bx + 14, 750),
            (bx - 14, 750),
        ]
        sw_draw.polygon(blade, fill=sword_color, outline=sword_shadow)
        sw_draw.line([(bx, 160), (bx, 740)], fill=(180, 185, 180, 255), width=3)
        
        # Guard
        sw_draw.rectangle([bx - 60, 680, bx + 60, 696], fill=sword_gold, outline=(40, 30, 15, 255), width=2)
        sw_draw.ellipse([bx - 68, 680, bx - 52, 696], fill=sword_gold)
        sw_draw.ellipse([bx + 52, 680, bx + 68, 696], fill=sword_gold)
        
        # Pommel
        sw_draw.ellipse([bx - 18, 770, bx + 18, 806], fill=sword_gold, outline=(40, 30, 15, 255), width=2)
        
        # Rotate sword around center
        rotated = sw.rotate(angle_deg, resample=Image.BICUBIC, center=(cx, cy))
        canvas = Image.alpha_composite(canvas, rotated)
        
    c_draw = ImageDraw.Draw(canvas)
    
    # 4. Central Motif: The Great Bronze Bell (沉钟)
    # Bell base silhouette
    # Top crown at cy - 180, main body flaring down to cy + 180
    bell_top_y = cy - 190
    bell_bot_y = cy + 170
    
    # Bell Crown / Loop
    c_draw.ellipse([cx - 40, bell_top_y - 45, cx + 40, bell_top_y + 15], fill=(70, 56, 38, 255), outline=(199, 166, 106, 255), width=7)
    c_draw.ellipse([cx - 20, bell_top_y - 25, cx + 20, bell_top_y - 5], fill=(20, 24, 20, 255))
    
    # Bell body polygon with curved profile
    bell_pts = []
    # Left curve
    steps = 25
    for i in range(steps + 1):
        t = i / float(steps)
        y = bell_top_y + t * (bell_bot_y - bell_top_y)
        # Flare formula: narrower at top (60px half-width), waist (100px), flaring widely at rim (220px)
        w = 60 + 50 * (t ** 1.5) + 110 * (t ** 4)
        bell_pts.append((cx - w, y))
        
    # Rim bottom arc
    for i in range(steps + 1):
        t = i / float(steps)
        x = (cx - 220) + t * 440
        # subtle curve at bottom lip
        y = bell_bot_y + 25 * math.sin(t * math.pi)
        bell_pts.append((x, y))
        
    # Right curve
    for i in range(steps, -1, -1):
        t = i / float(steps)
        y = bell_top_y + t * (bell_bot_y - bell_top_y)
        w = 60 + 50 * (t ** 1.5) + 110 * (t ** 4)
        bell_pts.append((cx + w, y))
        
    # Draw bell body shadow
    shadow_offset = 12
    shadow_pts = [(x + shadow_offset, y + shadow_offset) for x, y in bell_pts]
    c_draw.polygon(shadow_pts, fill=(8, 10, 8, 180))
    
    # Draw bell body fill (antique tarnished bronze)
    c_draw.polygon(bell_pts, fill=(110, 90, 55, 255), outline=(45, 35, 20, 255))
    
    # Shading on bell (left highlight, right shadow)
    bell_mask = Image.new("L", (SIZE, SIZE), 0)
    b_mask_draw = ImageDraw.Draw(bell_mask)
    b_mask_draw.polygon(bell_pts, fill=255)
    
    bell_shade = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    bs_draw = ImageDraw.Draw(bell_shade)
    # Left metallic specular reflection
    bs_draw.polygon([
        (cx - 150, bell_bot_y + 10),
        (cx - 30, bell_top_y + 10),
        (cx + 10, bell_top_y + 10),
        (cx - 60, bell_bot_y + 10)
    ], fill=(225, 195, 135, 120))
    # Right darkening shadow
    bs_draw.polygon([
        (cx + 30, bell_top_y + 10),
        (cx + 60, bell_top_y + 10),
        (cx + 220, bell_bot_y + 10),
        (cx + 80, bell_bot_y + 10)
    ], fill=(20, 15, 10, 160))
    
    bell_shade = bell_shade.filter(ImageFilter.GaussianBlur(15))
    canvas = Image.alpha_composite(canvas, Image.composite(bell_shade, Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0)), bell_mask))
    c_draw = ImageDraw.Draw(canvas)
    
    # 5. Bell Rim & Clapper
    c_draw.line([(cx - 220, bell_bot_y + 15), (cx + 220, bell_bot_y + 15)], fill=(199, 166, 106, 255), width=8)
    # Clapper (钟舌) hanging slightly below
    c_draw.ellipse([cx - 28, bell_bot_y + 10, cx + 28, bell_bot_y + 60], fill=(50, 40, 28, 255), outline=(199, 166, 106, 255), width=4)
    c_draw.ellipse([cx - 12, bell_bot_y + 25, cx + 12, bell_bot_y + 45], fill=(226, 196, 134, 255))
    
    # 6. Radiant Golden Cracks (誓约裂纹 / Glowing Oath Rune)
    crack_glow = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    cg_draw = ImageDraw.Draw(crack_glow)
    
    # Crack branching points
    crack_segments = [
        # Main central fissure
        ((cx, bell_bot_y + 10), (cx - 20, cy + 90)),
        ((cx - 20, cy + 90), (cx + 15, cy + 20)),
        ((cx + 15, cy + 20), (cx - 10, cy - 60)),
        ((cx - 10, cy - 60), (cx + 5, bell_top_y + 30)),
        # Branches
        ((cx - 20, cy + 90), (cx - 75, cy + 120)),
        ((cx + 15, cy + 20), (cx + 60, cy + 40)),
        ((cx + 60, cy + 40), (cx + 95, cy + 100)),
        ((cx - 10, cy - 60), (cx - 45, cy - 40)),
    ]
    
    # Draw outer glow
    for (p1, p2) in crack_segments:
        cg_draw.line([p1, p2], fill=(255, 180, 60, 200), width=10)
    cg_blurred = crack_glow.filter(ImageFilter.GaussianBlur(8))
    canvas = Image.alpha_composite(canvas, Image.composite(cg_blurred, Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0)), bell_mask))
    
    # Draw core sharp bright crack
    c_draw = ImageDraw.Draw(canvas)
    for (p1, p2) in crack_segments:
        c_draw.line([p1, p2], fill=(255, 235, 170, 255), width=4)
        
    # 7. Rising Embers & Ash Particles
    import random
    rng = random.Random(42)  # Deterministic aesthetic
    for _ in range(70):
        ex = rng.randint(cx - 300, cx + 300)
        ey = rng.randint(cy - 200, cy + 320)
        er = rng.randint(2, 6)
        alpha = rng.randint(120, 240)
        # Golden ember color
        c_draw.ellipse([ex - er, ey - er, ex + er, ey + er], fill=(255, rng.randint(170, 220), 80, alpha))
        
    # 8. Banner Plate at bottom with "灰誓"
    banner_w, banner_h = 320, 78
    bx0, by0 = cx - banner_w // 2, SIZE - pad - 120
    bx1, by1 = cx + banner_w // 2, by0 + banner_h
    
    # Drop shadow
    c_draw.rounded_rectangle([bx0 + 4, by0 + 4, bx1 + 4, by1 + 4], radius=12, fill=(5, 6, 5, 200))
    # Plate background
    c_draw.rounded_rectangle([bx0, by0, bx1, by1], radius=12, fill=(22, 26, 22, 255), outline=(199, 166, 106, 255), width=3)
    c_draw.rounded_rectangle([bx0 + 4, by0 + 4, bx1 - 4, by1 - 4], radius=9, outline=(55, 60, 50, 255), width=2)
    
    # Chinese title text "灰誓"
    font_path = "/System/Library/Fonts/PingFang.ttc"
    if not os.path.exists(font_path):
        font_path = "/System/Library/Fonts/STHeiti Light.ttc"
        
    font = None
    if os.path.exists(font_path):
        try:
            font = ImageFont.truetype(font_path, 42)
        except Exception:
            pass
            
    if font:
        text = "灰 誓"
        bbox = c_draw.textbbox((0, 0), text, font=font)
        tw = bbox[2] - bbox[0]
        th = bbox[3] - bbox[1]
        tx = cx - tw // 2
        ty = by0 + (banner_h - th) // 2 - 4
        # Text shadow
        c_draw.text((tx + 2, ty + 2), text, font=font, fill=(10, 12, 10, 220))
        # Text fill (Antique Gold)
        c_draw.text((tx, ty), text, font=font, fill=(232, 223, 204, 255))
        
    return canvas

def make_iconset(master: Image.Image):
    ART_DIR.mkdir(parents=True, exist_ok=True)
    master.save(ICON_PNG)
    print(f"Saved master PNG: {ICON_PNG}")
    
    if ICONSET_DIR.exists():
        shutil.rmtree(ICONSET_DIR)
    ICONSET_DIR.mkdir(parents=True)
    
    sizes = [
        (16, "icon_16x16.png"),
        (32, "icon_16x16@2x.png"),
        (32, "icon_32x32.png"),
        (64, "icon_32x32@2x.png"),
        (128, "icon_128x128.png"),
        (256, "icon_128x128@2x.png"),
        (256, "icon_256x256.png"),
        (512, "icon_256x256@2x.png"),
        (512, "icon_512x512.png"),
        (1024, "icon_512x512@2x.png"),
    ]
    
    for size, name in sizes:
        resized = master.resize((size, size), Image.Resampling.LANCZOS)
        resized.save(ICONSET_DIR / name)
        
    print(f"Created {len(sizes)} iconset members in {ICONSET_DIR}")
    
    # Run iconutil
    subprocess.run(["/usr/bin/iconutil", "-c", "icns", str(ICONSET_DIR), "-o", str(ICON_ICNS)], check=True)
    print(f"SUCCESS: Generated Apple ICNS icon: {ICON_ICNS} ({ICON_ICNS.stat().st_size} bytes)")
    
    # Clean up iconset folder
    shutil.rmtree(ICONSET_DIR)

if __name__ == "__main__":
    master = create_master_icon()
    make_iconset(master)
