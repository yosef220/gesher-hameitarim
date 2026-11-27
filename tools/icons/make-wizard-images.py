#!/usr/bin/env python3
# Copyright (C) 2026 The Gesher HaMeitarim Authors (גשר המיתרים); SPDX-License-Identifier: LicenseRef-PolyForm-Strict-1.0.0
"""ממיר את תמונות אשף ההתקנה ל-BMP של 24 ביט (המבנה ש-Inno Setup קורא).

    node tools/icons/gesher-wizard-images.cjs <תיקייה>
    python3 tools/icons/make-wizard-images.py <תיקייה>

קורא את wizard-<רוחב>x<גובה>.png ואת small-<רוחב>x<גובה>.png מהתיקייה, ומשטח אותם על רקע לבן
(הרקע של כותרת האשף) לקבצי BMP ב-tools/package. הפלט נשמר בריפו; הסקריפט הוא ההוכחה איך נוצר.
בסוף מודפסות שתי שורות ה-[Setup] שצריכות להתאים ל-tools/package/gesher.iss.
"""
import re
import sys
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
PACKAGE = ROOT / "tools" / "package"


def main(folder):
    names = {"wizard": [], "small": []}
    for png in sorted(Path(folder).glob("*.png"), key=lambda p: int(re.search(r"-(\d+)x", p.name).group(1))):
        match = re.fullmatch(r"(wizard|small)-(\d+)x(\d+)\.png", png.name)
        if not match:
            continue
        image = Image.open(png).convert("RGBA")
        flat = Image.new("RGB", image.size, (255, 255, 255))
        flat.paste(image, mask=image.getchannel("A"))
        target = PACKAGE / png.with_suffix(".bmp").name
        flat.save(target, format="BMP")
        names[match.group(1)].append(target.name)
        print(f"נכתב {target.relative_to(ROOT)} ({flat.size[0]}x{flat.size[1]})")
    print("WizardImageFile=" + ",".join(names["wizard"]))
    print("WizardSmallImageFile=" + ",".join(names["small"]))


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    main(sys.argv[1])
