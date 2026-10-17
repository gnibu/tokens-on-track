#!/usr/bin/env python3
"""Compose 2880x1800 Mac App Store screenshots from window captures.

    OUT=.context/shots .agents/skills/glass-ui-changes/capture.sh   # with sample data
    python3 scripts/store-screenshots.py .context/shots docs/app-store-screenshots

Needs Pillow. Captures come from capture.sh running against the sample cache
written by scripts/sample-usage.py, plus settings-full.png: the whole Settings
tab captured once with the panel's height cap lifted (see docs/app-store-build.md).
"""
import os
import sys

from PIL import Image, ImageChops, ImageDraw, ImageFilter, ImageFont

W, H = 2880, 1800
FONT = "/System/Library/Fonts/SFNS.ttf"

# (capture, crop box or None, title, subtitle, notification banners above it)
SHOTS = [
    ("dropdown-usage.png", None, "Know if your\nquota will last.",
     "Claude and Codex limit you per 5 hours and per week. The white tick shows "
     "where you should be now; green means you are on pace.", []),
    ("settings-full.png", (0, 5560, 860, 6130), "Warned before\nyou hit the wall.",
     "Get an alert when a limit runs ahead of pace or passes your threshold, "
     "and when it resets.", [
         ("Claude week off track",
          "62% used; 38% remaining. 1.6× target (39% expected). Resets Tue 07:15."),
         ("Codex 5h limit reset", "Full quota available again."),
     ]),
    ("settings-full.png", (0, 5072, 860, 5508), "Spread the week\nover your work days.",
     "Working hours spread each quota across the days and hours you choose, "
     "so your target follows your real working week.", []),
    ("desktop-card.png", None, "Your quotas,\nright on the desktop.",
     "An optional card sits behind your windows and keeps every limit in view.", []),
    ("dropdown-settings.png", (0, 0, 860, 1320), "Make it yours.",
     "Choose what the menu bar shows and whether a card stays on your desktop.", []),
]
ICON = os.path.join(os.path.dirname(__file__), "..", "Resources", "AppIcon.png")


def font(size, weight):
    f = ImageFont.truetype(FONT, size)
    f.set_variation_by_name(weight)
    return f


def background():
    # Diagonal navy gradient: cheap to draw at 1/8 scale, then upsampled.
    small = Image.new("RGB", (W // 8, H // 8))
    px = small.load()
    for y in range(small.height):
        for x in range(small.width):
            t = (x / small.width + y / small.height) / 2
            px[x, y] = tuple(int(a + (b - a) * t) for a, b in zip((14, 22, 38), (38, 52, 84)))
    return small.resize((W, H), Image.BICUBIC)


def crop_slice(img, box, radius=44, fade=80):
    """Cut a region out of a capture. Edges that were the panel's own keep its
    rounded corners; edges that were cut fade out instead of ending hard."""
    full_height = img.height
    img = img.crop(box)
    cut_top, cut_bottom = box[1] > 0, box[3] < full_height
    mask = Image.new("L", img.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle(
        (0, -radius if cut_top else 0, img.width - 1, img.height - 1 + (radius if cut_bottom else 0)),
        radius, fill=255,
    )
    ramp = Image.new("L", (1, img.height), 255)
    for y in range(img.height):
        top = y / fade if cut_top else 1
        bottom = (img.height - 1 - y) / fade if cut_bottom else 1
        ramp.putpixel((0, y), round(255 * max(0, min(1, top, bottom))))
    mask = ImageChops.multiply(mask, ramp.resize(img.size))
    img.putalpha(ImageChops.multiply(img.getchannel("A"), mask))
    return img


def wrap(draw, text, face, width):
    lines = [""]
    for word in text.split():
        trial = (lines[-1] + " " + word).strip()
        if draw.textlength(trial, font=face) > width and lines[-1]:
            lines.append(word)
        else:
            lines[-1] = trial
    return lines


def banner(title, body, width=860):
    """A macOS-style notification, with the text the app actually posts."""
    pad, icon_size = 28, 76
    probe = ImageDraw.Draw(Image.new("RGBA", (1, 1)))
    head, text = font(30, "Semibold"), font(28, "Regular")
    lines = wrap(probe, body, text, width - 2 * pad - icon_size - 24)
    height = pad * 2 + 40 + len(lines) * 36
    img = Image.new("RGBA", (width, height), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    draw.rounded_rectangle((0, 0, width - 1, height - 1), 34, fill=(48, 50, 56, 245),
                           outline=(255, 255, 255, 46), width=2)
    icon = Image.open(ICON).convert("RGBA").resize((icon_size, icon_size), Image.LANCZOS)
    img.alpha_composite(icon, (pad, (height - icon_size) // 2))
    x = pad + icon_size + 24
    draw.text((x, pad), title, font=head, fill="white")
    draw.text((width - pad, pad + 4), "now", font=text, fill=(160, 166, 178), anchor="ra")
    for i, line in enumerate(lines):
        draw.text((x, pad + 42 + i * 36), line, font=text, fill=(214, 218, 226))
    return img


def stack(images, gap=36):
    width = max(i.width for i in images)
    out = Image.new("RGBA", (width, sum(i.height for i in images) + gap * (len(images) - 1)))
    y = 0
    for i in images:
        out.alpha_composite(i, ((width - i.width) // 2, y))
        y += i.height + gap
    return out


def compose(capture, crop, title, subtitle, banners):
    canvas = background().convert("RGBA")
    shot = Image.open(capture).convert("RGBA")
    if crop:
        shot = crop_slice(shot, crop)
    if banners:
        shot = stack([banner(*b) for b in banners] + [shot])
    scale = min(1240 / shot.width, 1440 / shot.height)
    shot = shot.resize((round(shot.width * scale), round(shot.height * scale)), Image.LANCZOS)

    x = 2700 - shot.width
    y = (H - shot.height) // 2
    shadow = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    shadow.paste((0, 0, 0, 150), (x, y + 40), shot.getchannel("A"))
    canvas.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(50)))
    canvas.alpha_composite(shot, (x, y))

    draw = ImageDraw.Draw(canvas)
    head, body = font(118, "Bold"), font(54, "Regular")
    left, width = 180, x - 180 - 140
    lines = wrap(draw, subtitle, body, width)
    title_box = draw.multiline_textbbox((0, 0), title, font=head, spacing=24)
    block = title_box[3] + 70 + len(lines) * 76
    top = (H - block) // 2
    draw.multiline_text((left, top), title, font=head, fill="white", spacing=24)
    for i, line in enumerate(lines):
        draw.text((left, top + title_box[3] + 70 + i * 76), line, font=body, fill=(186, 196, 214))
    return canvas.convert("RGB")


def main():
    src, out = sys.argv[1], sys.argv[2]
    os.makedirs(out, exist_ok=True)
    for i, (name, crop, title, subtitle, banners) in enumerate(SHOTS, 1):
        slug = title.split("\n")[0].lower().strip(".,").replace(" ", "-")
        path = os.path.join(out, f"{i}-{slug}.png")
        image = compose(os.path.join(src, name), crop, title, subtitle, banners)
        assert image.size == (W, H)
        image.save(path)
        print(path)


if __name__ == "__main__":
    main()
