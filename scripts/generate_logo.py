#!/usr/bin/env python3
"""
Generate the PDF Handler app icon.

Design: a minimal sumi-ink ensō on a warm-paper squircle, with a single
terminal-green cursor dot at the opening. Mirrors DesignSystem.swift.

Runs on any platform with Pillow; emits:
  - logo.png  (1024×1024 master)
  - Resources/Assets.xcassets/AppIcon.appiconset/icon_*.png (full set)
"""
from __future__ import annotations

import math
import os
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

# Palette (matches DesignSystem.swift)
PAPER  = (250, 250, 250, 255)   # #FAFAFA
INK    = (26, 26, 26, 255)      # #1A1A1A
GREEN  = (0, 212, 126, 255)     # #00D47E terminalGreen

MASTER = 1024
SS     = 4  # supersample for smooth edges


def draw_logo(size: int) -> Image.Image:
    """Render the logo at the requested size, supersampled for clean edges."""
    hi = size * SS
    img = Image.new("RGBA", (hi, hi), (0, 0, 0, 0))
    d   = ImageDraw.Draw(img)

    # Squircle background (macOS-ish rounded rect).
    # Inset slightly so the stroke/shadow doesn't kiss the bitmap edge.
    inset  = int(hi * 0.02)
    radius = int(hi * 0.22)
    d.rounded_rectangle(
        [inset, inset, hi - inset, hi - inset],
        radius=radius,
        fill=PAPER,
    )

    # Ensō: a single brushstroke arc. Opening points to upper-right,
    # echoing the calligraphic mark in the app's hero screen.
    cx, cy = hi // 2, hi // 2
    r      = int(hi * 0.30)
    stroke = int(hi * 0.085)
    box    = [cx - r, cy - r, cx + r, cy + r]

    # Single clean sweep — from 300° clockwise around to 260°, leaving a
    # ~40° opening in the upper-right. Constant width reads crisper at
    # every size than a faked tapered brush.
    start, end = -60, 260
    d.arc(box, start=start, end=end, fill=INK, width=stroke)

    # Terminal cursor square at the opening (≈ angle 300°).
    # Skip below 64px output: it becomes a sub-pixel smudge.
    if size > 64:
        gap_deg = 300
        gx = cx + int(r * math.cos(math.radians(gap_deg)))
        gy = cy + int(r * math.sin(math.radians(gap_deg)))
        dot = int(hi * 0.032)
        d.rectangle(
            [gx - dot, gy - dot, gx + dot, gy + dot],
            fill=GREEN,
        )

    # Downsample with Lanczos for crisp edges.
    return img.resize((size, size), Image.LANCZOS)


def main() -> int:
    here = Path(__file__).resolve().parent
    root = here
    # Walk up to repo root if invoked from scripts/
    if (here / "scripts").exists() is False and here.name == "scripts":
        root = here.parent

    master_out = root / "logo.png"
    icons_dir  = root / "PDFHandler" / "PDFHandler" / "Resources" \
                      / "Assets.xcassets" / "AppIcon.appiconset"

    print(f"Writing master: {master_out}")
    draw_logo(MASTER).save(master_out, format="PNG")

    if not icons_dir.exists():
        print(f"Skipping icon set (not found): {icons_dir}")
        return 0

    targets = {
        "icon_16x16.png":        16,
        "icon_16x16@2x.png":     32,
        "icon_32x32.png":        32,
        "icon_32x32@2x.png":     64,
        "icon_128x128.png":     128,
        "icon_128x128@2x.png":  256,
        "icon_256x256.png":     256,
        "icon_256x256@2x.png":  512,
        "icon_512x512.png":     512,
        "icon_512x512@2x.png": 1024,
    }
    for name, px in targets.items():
        out = icons_dir / name
        draw_logo(px).save(out, format="PNG")
        print(f"  {name:<24} {px}×{px}")

    print("Done.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
