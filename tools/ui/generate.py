#!/usr/bin/env python3
"""מפיק את קבצי העיצוב של כל המשטחים מתוך ui/tokens.json.

עורכים רק את ui/tokens.json. ב-CI מריצים עם --check, שנכשל אם קובץ מופק לא
מעודכן. לפני ההפקה הכלי בודק:
  - שכל תפקיד מפנה לצבע בפלטה או לערך hex תקין, בשני המצבים
  - שכל זוג ברשימת הניגודיות עומד בסף שלו, במצב בהיר ובמצב כהה
  - שקבצי הגופנים והרישיונות קיימים ב-tools/package/ui-fonts

הקבצים המופקים:
  compat/windows/gesher_tokens.h           דיאלוגים נייטיב ומסך הפתיחה (C ו-C++)
  tools/package/gesher-tokens-light.xaml   מרכז הבקרה, מצב בהיר
  tools/package/gesher-tokens-dark.xaml    מרכז הבקרה, מצב כהה
  tools/package/gesher-tokens-contrast.xaml מרכז הבקרה, ניגודיות גבוהה (צבעי המערכת של Windows)
  tools/package/gesher-tokens.iss          המתקין
  ui/preview/tokens.css                    אבי-טיפוס בדפדפן, לביקורת עיצובית

שימוש:
  python3 tools/ui/generate.py           # מפיק
  python3 tools/ui/generate.py --check   # רק בודק
"""
import argparse
import json
import re
import struct
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
TOKENS = ROOT / "ui/tokens.json"
FONTS = ROOT / "tools/package/ui-fonts"
HEX = re.compile(r"^#[0-9A-Fa-f]{6}$")
MODES = ("light", "dark")
# צבעי המערכת של Windows שמותר להפנות אליהם במצב ניגודיות גבוהה (System.Windows.SystemColors)
SYSTEM_COLORS = {"Window", "WindowText", "GrayText", "Highlight", "HighlightText", "HotTrack",
                 "Control", "ControlText", "ButtonFace", "ButtonText"}
HEADER_HE = "נוצר על ידי tools/ui/generate.py מתוך ui/tokens.json. לא לערוך ביד."


class TokenError(Exception):
    pass


def font_names(path):
    """שם המשפחה (nameID 1) והסגנון (nameID 2) כפי ש-GDI רואה אותם, מטבלת name של הגופן."""
    data = path.read_bytes()
    count = struct.unpack(">H", data[4:6])[0]
    for i in range(count):
        tag, _, offset, _ = struct.unpack(">4sIII", data[12 + 16 * i:28 + 16 * i])
        if tag != b"name":
            continue
        _, n, storage = struct.unpack(">HHH", data[offset:offset + 6])
        names = {}
        for j in range(n):
            platform, encoding, language, name_id, length, start = struct.unpack(
                ">HHHHHH", data[offset + 6 + 12 * j:offset + 18 + 12 * j])
            if platform == 3 and encoding == 1 and language == 0x409 and name_id in (1, 2):
                raw = data[offset + storage + start:offset + storage + start + length]
                names[name_id] = raw.decode("utf-16-be")
        return names.get(1), names.get(2)
    raise TokenError(f"{path.name}: אין בגופן טבלת name")


def load():
    data = json.loads(TOKENS.read_text(encoding="utf-8"))
    palette = {}
    for name, entry in data["palette"].items():
        if not HEX.match(entry["hex"]):
            raise TokenError(f"פלטה: {name} אינו hex תקין ({entry['hex']})")
        palette[name] = entry["hex"].upper()
    roles = {}
    for role, entry in data["roles"].items():
        roles[role] = {}
        for mode in MODES:
            value = entry.get(mode)
            if value in palette:
                value = palette[value]
            if not isinstance(value, str) or not HEX.match(value):
                raise TokenError(f"תפקיד {role}/{mode}: '{entry.get(mode)}' אינו צבע בפלטה ואינו hex")
            roles[role][mode] = value.upper()
        system = entry.get("contrast")
        if system not in SYSTEM_COLORS:
            raise TokenError(f"תפקיד {role}/contrast: '{system}' אינו צבע מערכת מוכר ({', '.join(sorted(SYSTEM_COLORS))})")
        roles[role]["contrast"] = system
    for kind, font in data["font"].items():
        if kind == "about":
            continue
        for weight, entry in font["files"].items():
            path = FONTS / entry["file"]
            if not path.is_file():
                raise TokenError(f"גופן {kind}/{weight}: הקובץ tools/package/ui-fonts/{entry['file']} חסר")
            family, style = font_names(path)
            if family != entry["gdi-family"] or (style == "Bold") != entry["gdi-bold"]:
                raise TokenError(f"גופן {kind}/{weight}: בקובץ כתוב '{family}' בסגנון '{style}', "
                                 f"ובטוקנים '{entry['gdi-family']}' (מודגש: {entry['gdi-bold']})")
        if not (FONTS / font["license"]).is_file():
            raise TokenError(f"גופן {kind}: הרישיון tools/package/ui-fonts/{font['license']} חסר")
    data["font"] = {k: v for k, v in data["font"].items() if k != "about"}
    for item in data["type"].values():
        if isinstance(item, dict) and item["font"] not in data["font"]:
            raise TokenError(f"סולם: הגופן '{item['font']}' לא מוגדר")
    return data, palette, roles


def luminance(hex_value):
    r, g, b = (int(hex_value[i:i + 2], 16) / 255 for i in (1, 3, 5))
    f = lambda c: c / 12.92 if c <= 0.03928 else ((c + 0.055) / 1.055) ** 2.4
    return 0.2126 * f(r) + 0.7152 * f(g) + 0.0722 * f(b)


def contrast(a, b):
    la, lb = sorted((luminance(a), luminance(b)), reverse=True)
    return (la + 0.05) / (lb + 0.05)


def check_contrast(data, roles):
    failures = []
    for fg, bg, minimum in data["contrast"]["pairs"]:
        for name in (fg, bg):
            if name not in roles:
                raise TokenError(f"ניגודיות: התפקיד '{name}' לא מוגדר")
        for mode in MODES:
            ratio = contrast(roles[fg][mode], roles[bg][mode])
            if ratio < minimum:
                failures.append(f"{fg} על {bg} ({mode}): {ratio:.2f}:1, צריך לפחות {minimum}:1")
    if failures:
        raise TokenError("ניגודיות לא מספיקה:\n  " + "\n  ".join(failures))


def ident(name):
    return re.sub(r"[^A-Za-z0-9]+", "_", name).strip("_").upper()


def camel(name):
    return "".join(part.capitalize() for part in re.split(r"[^A-Za-z0-9]+", name) if part)


def bgr(hex_value):
    return f"$00{hex_value[5:7]}{hex_value[3:5]}{hex_value[1:3]}"


def c_header(data, roles):
    out = [f"/* {HEADER_HE} */", "#ifndef GESHER_TOKENS_H", "#define GESHER_TOKENS_H", "",
           "/* צבעים לפי תפקיד. כל תפקיד מופיע במצב בהיר (_LIGHT) ובמצב כהה (_DARK). */"]
    for role, values in roles.items():
        out.append(f"/* {data['roles'][role]['he']} */")
        for mode in MODES:
            h = values[mode]
            out.append(f"#define GESHER_{ident(role)}_{mode.upper()} "
                       f"RGB(0x{h[1:3]}, 0x{h[3:5]}, 0x{h[5:7]})")
    out += ["", "/* גופנים: נטענים מהתיקייה ui-fonts שליד הקבצים המותקנים, רק לתהליך עצמו. */"]
    for kind, font in data["font"].items():
        out.append(f"#define GESHER_FONT_{ident(kind)} L\"{font['family']}\"")
        for weight, entry in font["files"].items():
            out.append(f"#define GESHER_FONT_{ident(kind)}_{weight}_GDI_FAMILY L\"{entry['gdi-family']}\"")
            out.append(f"#define GESHER_FONT_{ident(kind)}_{weight}_GDI_BOLD {1 if entry['gdi-bold'] else 0}")
    out.append(f"#define GESHER_FONT_FALLBACK L\"{data['font']['ui']['fallback']}\"")
    files = [entry["file"] for font in data["font"].values() for entry in font["files"].values()]
    out.append("#define GESHER_FONT_FILES { " + ", ".join(f'L"{n}"' for n in files) + " }")
    out.append(f"#define GESHER_FONT_FILE_COUNT {len(files)}")
    out += ["", "/* סולם הטיפוגרפיה, בפיקסלים */"]
    for name, item in data["type"].items():
        if not isinstance(item, dict):
            continue
        out.append(f"#define GESHER_TYPE_{ident(name)}_SIZE {item['size']}")
        out.append(f"#define GESHER_TYPE_{ident(name)}_WEIGHT {item['weight']}")
        out.append(f"#define GESHER_TYPE_{ident(name)}_DISPLAY {1 if item['font'] == 'display' else 0}")
    out += ["", "/* מרווחים ורדיוסים, בפיקסלים */"]
    for i, value in enumerate(data["space"], 1):
        out.append(f"#define GESHER_SPACE_{i} {value}")
    for name, value in data["radius"].items():
        out.append(f"#define GESHER_RADIUS_{ident(name)} {value}")
    out += ["", "/* תנועה, באלפיות שנייה */"]
    for name, value in data["motion"].items():
        if name != "about":
            out.append(f"#define GESHER_MOTION_{ident(name)} {value}")
    b = data["bridge"]
    out += ["", f"/* הגשר, ביחידות של viewBox בגודל {b['view-box']} */",
            f"#define GESHER_BRIDGE_VIEW_BOX {b['view-box']}.0f",
            f"#define GESHER_BRIDGE_MAST_TOP_X {b['mast-top'][0]}.0f",
            f"#define GESHER_BRIDGE_MAST_TOP_Y {b['mast-top'][1]}.0f",
            f"#define GESHER_BRIDGE_MAST_BASE_X {b['mast-base-x']}.0f"]
    for i, (x, y) in enumerate(b["deck"]):
        out.append(f"#define GESHER_BRIDGE_DECK_{i}_X {x}.0f")
        out.append(f"#define GESHER_BRIDGE_DECK_{i}_Y {y}.0f")
    s = b["strings"]
    st = b["stays"]
    out += [f"#define GESHER_BRIDGE_STAY_MAST_T_FIRST {st['mast-t'][0]}f",
            f"#define GESHER_BRIDGE_STAY_MAST_T_LAST {st['mast-t'][1]}f",
            f"#define GESHER_BRIDGE_STAY_DECK_X {st['deck-x']}.0f"]
    out += [f"#define GESHER_BRIDGE_STRING_COUNT {s['count']}",
            f"#define GESHER_BRIDGE_STRING_MAST_T_FIRST {s['mast-t'][0]}f",
            f"#define GESHER_BRIDGE_STRING_MAST_T_LAST {s['mast-t'][1]}f",
            f"#define GESHER_BRIDGE_STRING_DECK_X_FIRST {s['deck-x'][0]}.0f",
            f"#define GESHER_BRIDGE_STRING_DECK_X_LAST {s['deck-x'][1]}.0f",
            "", "#endif /* GESHER_TOKENS_H */", ""]
    return "\n".join(out)


# המסגרת של הגשר ביחידות של viewBox, כמו באב-הטיפוס של מסך הפתיחה (ui/preview/render-splash.cjs).
# ב-XAML הקואורדינטות מוזזות כך שהמסגרת מתחילה ב-0,0.
BRIDGE_FRAME = (-20, 24, 296, 196)
BRIDGE_STRING_LIFT = 2.2


def bridge_geometry(b):
    """התורן, המסלול, המיתרים וכבלי העיגון כ-path markup של WPF. אותה נוסחה כמו ui/bridge-geometry.cjs."""
    (p0, p1, p2) = b["deck"]

    def deck_y(x):
        lo, hi = 0.0, 1.0
        for _ in range(40):
            t = (lo + hi) / 2
            bx = (1 - t) ** 2 * p0[0] + 2 * t * (1 - t) * p1[0] + t * t * p2[0]
            if bx < x:
                lo = t
            else:
                hi = t
        t = (lo + hi) / 2
        return (1 - t) ** 2 * p0[1] + 2 * t * (1 - t) * p1[1] + t * t * p2[1]

    lerp = lambda a, c, t: a + (c - a) * t
    top = b["mast-top"]
    base = (b["mast-base-x"], deck_y(b["mast-base-x"]))
    mast_point = lambda t: (lerp(top[0], base[0], t), lerp(top[1], base[1], t))
    fx, fy = -BRIDGE_FRAME[0], -BRIDGE_FRAME[1]
    pt = lambda x, y: f"{x + fx:.2f},{y + fy:.2f}"

    length = ((top[0] - base[0]) ** 2 + (top[1] - base[1]) ** 2) ** 0.5
    nx, ny = -(top[1] - base[1]) / length, (top[0] - base[0]) / length
    corners = [(base, 5.2, -1), (base, 5.2, 1), (top, 2.2, 1), (top, 2.2, -1)]
    mast = "M " + " L ".join(pt(c[0] + s_ * h * nx, c[1] + s_ * h * ny) for c, h, s_ in corners) + " Z"
    deck = f"M {pt(*p0)} Q {pt(*p1)} {pt(*p2)}"
    s_ = b["strings"]
    lines = []
    for i in range(s_["count"]):
        f = 0 if s_["count"] == 1 else i / (s_["count"] - 1)
        mx, my = mast_point(lerp(s_["mast-t"][0], s_["mast-t"][1], f))
        dx = lerp(s_["deck-x"][0], s_["deck-x"][1], f)
        lines.append(f"M {pt(mx, my)} L {pt(dx, deck_y(dx) - BRIDGE_STRING_LIFT)}")
    stays = []
    x = b["stays"]["deck-x"]
    for t in b["stays"]["mast-t"]:
        mx, my = mast_point(t)
        stays.append(f"M {pt(mx, my)} L {pt(x, deck_y(x) - BRIDGE_STRING_LIFT)}")
    return {
        "Mast": mast, "Deck": deck, "Strings": " ".join(lines), "Stays": " ".join(stays),
        "width": BRIDGE_FRAME[2], "height": BRIDGE_FRAME[3], "deck-end-y": p0[1] + fy,
    }


def xaml(data, roles, mode):
    name = {"light": "מצב בהיר", "dark": "מצב כהה", "contrast": "ניגודיות גבוהה: צבעי המערכת בלבד, בלי Color"}[mode]
    out = [f"<!-- {HEADER_HE} {name}. -->",
           '<ResourceDictionary xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"',
           '                    xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"',
           '                    xmlns:sys="clr-namespace:System;assembly=mscorlib">']
    for role, values in roles.items():
        key = "Gesher" + camel(role)
        if mode == "contrast":
            out.append(f'  <SolidColorBrush x:Key="{key}Brush" Color="{{x:Static SystemColors.{values[mode]}Color}}"/>')
            continue
        out.append(f'  <Color x:Key="{key}Color">{values[mode]}</Color>')
        out.append(f'  <SolidColorBrush x:Key="{key}Brush" Color="{values[mode]}"/>')
    for kind, font in data["font"].items():
        out.append(f'  <sys:String x:Key="Gesher{camel(kind)}FontFamily">{font["family"]}</sys:String>')
    out.append(f'  <sys:String x:Key="GesherFallbackFontFamily">{data["font"]["ui"]["fallback"]}</sys:String>')
    for type_name, item in data["type"].items():
        if isinstance(item, dict):
            out.append(f'  <sys:Double x:Key="GesherType{camel(type_name)}Size">{item["size"]}</sys:Double>')
    for radius, value in data["radius"].items():
        out.append(f'  <CornerRadius x:Key="GesherRadius{camel(radius)}">{value}</CornerRadius>')
    bridge = bridge_geometry(data["bridge"])
    out.append(f"  <!-- הגשר: מסגרת של {bridge['width']}x{bridge['height']}, והקצוות של המסלול בגובה GesherBridgeDeckEndY -->")
    out.append(f'  <sys:Double x:Key="GesherBridgeWidth">{bridge["width"]}</sys:Double>')
    out.append(f'  <sys:Double x:Key="GesherBridgeHeight">{bridge["height"]}</sys:Double>')
    out.append(f'  <sys:Double x:Key="GesherBridgeDeckEndY">{bridge["deck-end-y"]}</sys:Double>')
    for part in ("Mast", "Deck", "Strings", "Stays"):
        out.append(f'  <Geometry x:Key="GesherBridge{part}Geometry">{bridge[part]}</Geometry>')
    out += ["</ResourceDictionary>", ""]
    return "\n".join(out)


def inno(data, roles):
    out = [f"; {HEADER_HE}", "; צבעים בתבנית TColor של Inno Setup ($00BBGGRR)"]
    for role, values in roles.items():
        for mode in MODES:
            out.append(f'#define Gesher{camel(role)}{mode.capitalize()} "{bgr(values[mode])}"')
    out.append(f'#define GesherFontDisplay "{data["font"]["display"]["family"]}"')
    out.append(f'#define GesherFontUi "{data["font"]["ui"]["family"]}"')
    out.append("")
    return "\n".join(out)


def css(data, roles):
    out = [f"/* {HEADER_HE} לאבי-טיפוס בדפדפן בלבד. */"]
    for kind, font in data["font"].items():
        for weight, entry in font["files"].items():
            out.append(f"@font-face {{ font-family: '{font['family']}'; font-weight: {weight}; "
                       f"src: url('../../tools/package/ui-fonts/{entry['file']}') format('truetype'); }}")
    for mode in MODES:
        selector = ":root" if mode == "light" else ":root[data-theme='dark']"
        out.append(selector + " {")
        for role, values in roles.items():
            out.append(f"  --{role}: {values[mode]};")
        if mode == "light":
            for kind, font in data["font"].items():
                out.append(f"  --font-{kind}: '{font['family']}', '{font['fallback']}', sans-serif;")
            for type_name, item in data["type"].items():
                if isinstance(item, dict):
                    out.append(f"  --type-{type_name}: {item['size']}px;")
            for radius, value in data["radius"].items():
                out.append(f"  --radius-{radius}: {value}px;")
        out.append("}")
    out.append("")
    return "\n".join(out)


def outputs():
    data, _, roles = load()
    check_contrast(data, roles)
    return {
        ROOT / "compat/windows/gesher_tokens.h": c_header(data, roles),
        ROOT / "tools/package/gesher-tokens-light.xaml": xaml(data, roles, "light"),
        ROOT / "tools/package/gesher-tokens-dark.xaml": xaml(data, roles, "dark"),
        ROOT / "tools/package/gesher-tokens-contrast.xaml": xaml(data, roles, "contrast"),
        ROOT / "tools/package/gesher-tokens.iss": inno(data, roles),
        ROOT / "ui/preview/tokens.css": css(data, roles),
    }


def main():
    parser = argparse.ArgumentParser(description="מפיק את קבצי העיצוב מ-ui/tokens.json")
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    try:
        files = outputs()
    except TokenError as e:
        parser.exit(2, f"שגיאה בטוקנים: {e}\n")
    stale = []
    for path, content in files.items():
        if args.check:
            if not path.exists() or path.read_text(encoding="utf-8") != content:
                stale.append(str(path.relative_to(ROOT)))
        else:
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(content, encoding="utf-8", newline="\n")
    if stale:
        parser.exit(1, "קבצים מופקים לא מעודכנים. הריצו python3 tools/ui/generate.py: " + ", ".join(stale) + "\n")
    print(("הקבצים המופקים מעודכנים" if args.check else f"הופקו {len(files)} קבצים") +
          ", והניגודיות עומדת בסף בשני המצבים.")


if __name__ == "__main__":
    main()
