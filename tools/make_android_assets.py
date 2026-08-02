"""Generates Android launcher icons and the splash screen from logo.png.

`logo.png` is a square card with the wordmark on top and the toy diorama
below. A launcher icon wants the diorama alone (text is unreadable at 48dp),
so the diorama is cropped out for the adaptive foreground while the full card
is used for the legacy square icon and the splash.

Run:  python tools/make_android_assets.py
"""

import os

from PIL import Image, ImageDraw, ImageFilter

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LOGO = os.path.join(REPO, "logo.png")
RES = os.path.join(REPO, "android", "app", "src", "main", "res")

STUDIO = (242, 242, 243, 255)

# Legacy square/round launcher icon sizes.
LEGACY = {"mdpi": 48, "hdpi": 72, "xhdpi": 96, "xxhdpi": 144, "xxxhdpi": 192}
# Adaptive foreground is a 108dp canvas with a 72dp safe zone.
ADAPTIVE = {"mdpi": 108, "hdpi": 162, "xhdpi": 216, "xxhdpi": 324, "xxxhdpi": 432}
# Splash logo, drawn centred on the studio background.
SPLASH = {"mdpi": 160, "hdpi": 240, "xhdpi": 320, "xxhdpi": 480, "xxxhdpi": 640}

# Fraction of logo.png occupied by the diorama (measured from the source art).
DIORAMA = (0.05, 0.29, 0.98, 0.86)

# The full diorama is roughly 2:1, so fitting it into a square icon canvas
# leaves it tiny and unreadable at 48dp. This tighter, near-square window keeps
# the instantly recognisable part — block tower, toppling dominoes, the car —
# and fills the icon properly.
ICON_CROP = (0.30, 0.28, 0.95, 0.86)


def ensure(path):
    os.makedirs(path, exist_ok=True)
    return path


def flatten(img):
    bg = Image.new("RGBA", img.size, STUDIO)
    return Image.alpha_composite(bg, img.convert("RGBA"))


def rounded(img, radius_frac=0.22):
    """Applies the same soft rounded-square mask the source art already uses,
    so the legacy icon matches on launchers that do not mask it themselves."""
    w, h = img.size
    mask = Image.new("L", (w * 4, h * 4), 0)
    ImageDraw.Draw(mask).rounded_rectangle(
        (0, 0, w * 4 - 1, h * 4 - 1), radius=int(w * 4 * radius_frac), fill=255
    )
    mask = mask.resize((w, h), Image.LANCZOS)
    out = img.convert("RGBA")
    out.putalpha(mask)
    return out


def crop_diorama(src, window=DIORAMA):
    w, h = src.size
    l, t, r, b = window
    box = (int(w * l), int(h * t), int(w * r), int(h * b))
    d = src.crop(box)

    # Trim any near-background border so the toy set fills the safe zone.
    bg = d.convert("RGB").resize((1, 1)).getpixel((0, 0))
    diff = Image.new("L", d.size, 0)
    px = d.convert("RGB").load()
    dp = diff.load()
    for y in range(d.size[1]):
        for x in range(d.size[0]):
            r_, g_, b_ = px[x, y]
            if abs(r_ - bg[0]) + abs(g_ - bg[1]) + abs(b_ - bg[2]) > 26:
                dp[x, y] = 255
    bbox = diff.getbbox()
    if bbox:
        pad = 6
        bbox = (
            max(0, bbox[0] - pad), max(0, bbox[1] - pad),
            min(d.size[0], bbox[2] + pad), min(d.size[1], bbox[3] + pad),
        )
        d = d.crop(bbox)
    return d


def fit_square(img, size, fill_frac, background=None):
    """Scales `img` to occupy `fill_frac` of a `size` square, centred."""
    canvas = Image.new("RGBA", (size, size), background or (0, 0, 0, 0))
    target = int(size * fill_frac)
    w, h = img.size
    scale = min(target / w, target / h)
    nw, nh = max(1, int(w * scale)), max(1, int(h * scale))
    resized = img.resize((nw, nh), Image.LANCZOS)
    canvas.paste(resized, ((size - nw) // 2, (size - nh) // 2), resized)
    return canvas


def main():
    src = Image.open(LOGO).convert("RGBA")
    card = flatten(src)
    diorama = crop_diorama(card, ICON_CROP)

    # --- legacy square + round icons --------------------------------------
    for dens, size in LEGACY.items():
        d = ensure(os.path.join(RES, f"mipmap-{dens}"))
        icon = fit_square(diorama, size, 0.90, background=STUDIO)
        rounded(icon, 0.22).save(os.path.join(d, "ic_launcher.png"))

        rnd = fit_square(diorama, size, 0.80, background=STUDIO)
        mask = Image.new("L", (size * 4, size * 4), 0)
        ImageDraw.Draw(mask).ellipse((0, 0, size * 4 - 1, size * 4 - 1), fill=255)
        mask = mask.resize((size, size), Image.LANCZOS)
        rnd.putalpha(mask)
        rnd.save(os.path.join(d, "ic_launcher_round.png"))

    # --- adaptive foreground ----------------------------------------------
    for dens, size in ADAPTIVE.items():
        d = ensure(os.path.join(RES, f"drawable-{dens}"))
        # 0.66 == the 72dp safe zone inside the 108dp adaptive canvas, so the
        # composition survives even the most aggressive circular mask.
        # The padding is filled with the studio colour rather than left
        # transparent so it matches ic_launcher_background exactly and no seam
        # can appear on launchers that tint or shadow the layers.
        fit_square(diorama, size, 0.66, background=STUDIO).save(
            os.path.join(d, "ic_launcher_foreground.png")
        )

    v26 = ensure(os.path.join(RES, "mipmap-anydpi-v26"))
    for name in ("ic_launcher", "ic_launcher_round"):
        with open(os.path.join(v26, f"{name}.xml"), "w", encoding="utf-8") as f:
            f.write(
                '<?xml version="1.0" encoding="utf-8"?>\n'
                '<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">\n'
                '    <background android:drawable="@color/ic_launcher_background"/>\n'
                '    <foreground android:drawable="@drawable/ic_launcher_foreground"/>\n'
                '    <monochrome android:drawable="@drawable/ic_launcher_foreground"/>\n'
                "</adaptive-icon>\n"
            )

    values = ensure(os.path.join(RES, "values"))
    with open(os.path.join(values, "ic_launcher_background.xml"), "w", encoding="utf-8") as f:
        f.write(
            '<?xml version="1.0" encoding="utf-8"?>\n'
            "<resources>\n"
            '    <color name="ic_launcher_background">#F2F2F3</color>\n'
            "</resources>\n"
        )

    # --- splash ------------------------------------------------------------
    for dens, size in SPLASH.items():
        d = ensure(os.path.join(RES, f"drawable-{dens}"))
        fit_square(card, size, 1.0).save(os.path.join(d, "splash.png"))

    drawable = ensure(os.path.join(RES, "drawable"))
    for folder in (drawable, ensure(os.path.join(RES, "drawable-v21"))):
        with open(os.path.join(folder, "launch_background.xml"), "w", encoding="utf-8") as f:
            f.write(
                '<?xml version="1.0" encoding="utf-8"?>\n'
                '<layer-list xmlns:android="http://schemas.android.com/apk/res/android">\n'
                '    <item android:drawable="@color/splash_background"/>\n'
                "    <item>\n"
                '        <bitmap android:gravity="center" android:src="@drawable/splash"/>\n'
                "    </item>\n"
                "</layer-list>\n"
            )
    with open(os.path.join(values, "splash_background.xml"), "w", encoding="utf-8") as f:
        f.write(
            '<?xml version="1.0" encoding="utf-8"?>\n'
            "<resources>\n"
            '    <color name="splash_background">#F2F2F3</color>\n'
            "</resources>\n"
        )

    # A copy of the splash art for the in-app loading screen.
    ui = ensure(os.path.join(REPO, "assets", "images"))
    fit_square(card, 512, 1.0).save(os.path.join(ui, "logo_card.png"))

    print("icons + splash generated")


if __name__ == "__main__":
    main()
