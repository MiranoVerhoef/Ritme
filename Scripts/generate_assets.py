#!/usr/bin/env python3
"""Render Ritme's original route mark into its app icon (requires Pillow)."""
from pathlib import Path
import json
from PIL import Image, ImageDraw

root = Path(__file__).resolve().parents[1]
size = 2048
image = Image.new("RGB", (size, size), (22, 39, 61))
draw = ImageDraw.Draw(image)

def bezier(a, b, c, d):
    return [tuple(int((1-t)**3*a[k] + 3*(1-t)**2*t*b[k] + 3*(1-t)*t*t*c[k] + t**3*d[k]) for k in (0,1)) for t in (i/180 for i in range(181))]

points = bezier((760, 570), (300, 570), (500, 1080), (1040, 1040))
points += bezier((1040, 1040), (1580, 1000), (1760, 1510), (1288, 1510))
draw.line(points, fill=(246, 248, 252), width=100, joint="curve")
for x,y in [(760,570),(1288,1510)]:
    draw.ellipse((x-155,y-155,x+155,y+155), fill=(246,248,252))
    draw.ellipse((x-65,y-65,x+65,y+65), fill=(22,39,61))

catalog = root / "Ritme/Resources/Assets.xcassets"
catalog.mkdir(parents=True, exist_ok=True)
(catalog / "Contents.json").write_text(json.dumps({"info": {"author": "xcode", "version": 1}}, indent=2))
icon = catalog / "AppIcon.appiconset"
icon.mkdir(exist_ok=True)
image.resize((1024,1024), Image.Resampling.LANCZOS).save(icon / "AppIcon.png")
(icon / "Contents.json").write_text(json.dumps({"images": [{"filename": "AppIcon.png", "idiom": "universal", "platform": "ios", "size": "1024x1024"}], "info": {"author": "xcode", "version": 1}}, indent=2))
print("Generated", icon)
