"""מיתר: מסך הרישיון של אשף ההתקנה (LicenseFile), בעברית ובאנגלית.

הקבצים license.he.rtf ו-license.en.rtf נבנים מכאן: תקציר במילים פשוטות (מה מותר, מה אסור,
ולשימוש בעסק), ואחריו הנוסח המחייב מ-LICENSE בשורש המאגר, כמו שהוא. העיצוב לפי
docs/he/design/01-design-plan.md: ‏Segoe UI (‏Inno לא מאפשר גופן מוטמע), דיו לגוף, שמי ירושלים
לשורה הפותחת ולכותרות, פלדה לנוסח המשפטי.

    python3 tools/package/license_rtf.py           כותב את שני הקבצים
    python3 tools/package/license_rtf.py --check   נכשל אם הם לא תואמים ל-LICENSE ולתקציר
"""
import argparse
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[2]
PACKAGE = ROOT / 'tools/package'

# הצבעים מ-ui/tokens.json (מצב בהיר): דיו, שמי ירושלים, פלדה.
COLORS = ((0x14, 0x23, 0x38), (0x22, 0x40, 0x6A), (0x55, 0x65, 0x7B))
INK, SKY, STEEL = 1, 2, 3

SUMMARY = {
    'he': {
        'lead': 'מיתר חינמי לשימוש אישי',
        'groups': (
            ('מה מותר', (
                'להתקין ולהשתמש בבית, ללימוד ולתחביב.',
                'גם עמותות, מוסדות חינוך, מוסדות בריאות ומוסדות ממשלה רשאים להשתמש בו.',
                'לשלוח לאחרים קישור לדף ההורדה הרשמי.',
            )),
            ('מה אסור', (
                'להעביר לאחרים את המתקין או את התוכנה, או לפרסם אותם.',
                'לשנות את התוכנה או לבנות ממנה גרסה אחרת.',
                'להשתמש בו בעסק בלי אישור בכתב.',
            )),
        ),
        'notes': (
            'לשימוש בעסק אפשר לבקש רישיון מבעל המאגר: github.com/yosef220',
            'החלקים שמקורם ב-Gesher נשארים תחת Apache 2.0. כל הרישיונות נמצאים גם בתיקייה licenses שבתיקיית ההתקנה.',
            'זה תקציר. הנוסח המחייב הוא הנוסח האנגלי שלמטה.',
        ),
        'legal': 'הנוסח המחייב (באנגלית)',
    },
    'en': {
        'lead': 'Meitar is free for personal use',
        'groups': (
            ('You may', (
                'Install it and use it at home, for study and for hobbies.',
                'Use it at a charity, school, health or government institution.',
                'Send others a link to the official download page.',
            )),
            ('You may not', (
                'Pass the installer or the software on to others, or publish them.',
                'Change the software or build another version of it.',
                'Use it in a business without written permission.',
            )),
        ),
        'notes': (
            'For business use, ask the repository owner for a license: github.com/yosef220',
            'The parts that come from Gesher remain under the Apache License 2.0. All the licenses are also in the licenses folder of the installation.',
            'This is a summary. The binding text follows.',
        ),
        'legal': 'The binding text',
    },
}


def text(value):
    """RTF של 7 ביט: תווים מחוץ ל-ASCII נכתבים כ-\\uN? (מספר עם סימן של 16 ביט)."""
    out = []
    for ch in value:
        code = ord(ch)
        if ch in '\\{}':
            out.append('\\' + ch)
        elif 32 <= code < 127:
            out.append(ch)
        elif code > 0xFFFF:
            raise ValueError(f'תו מחוץ ל-BMP: {ch!r}')
        else:
            out.append(f'\\u{code - 65536 if code > 32767 else code}?')
    return ''.join(out)


def inline(value):
    """ההדגשות של Markdown בנוסח של PolyForm: ***...*** ו-**...** מודגשים, <url> בלי הסוגריים."""
    parts = []
    for piece in re.split(r'(\*\*\*.+?\*\*\*|\*\*.+?\*\*)', value):
        if piece.startswith('***'):
            parts.append('{\\b\\i ' + text(piece[3:-3]) + '}')
        elif piece.startswith('**'):
            parts.append('{\\b ' + text(piece[2:-2]) + '}')
        else:
            parts.append(text(re.sub(r'<(https?://[^>]+)>', r'\1', piece)))
    return ''.join(parts)


def paragraph(body, *, rtl, size, color, semibold=False, before=0, after=120, line=264):
    font = (3 if semibold else 1) if rtl else (2 if semibold else 0)
    direction = '\\rtlpar\\qr' if rtl else '\\ltrpar\\ql'
    run = '\\rtlch' if rtl else '\\ltrch'
    return (f'\\pard{direction}\\sb{before}\\sa{after}\\sl{line}\\slmult1'
            f'{{{run}\\f{font}\\af{font}\\fs{round(size * 2)}\\afs{round(size * 2)}\\cf{color} {body}}}\\par\n')


def legal_blocks():
    """הנוסח המחייב מ-LICENSE: הפסקאות באנגלית שלפני --- (בלי התקציר העברי), ואחריהן PolyForm."""
    license_text = (ROOT / 'LICENSE').read_text(encoding='utf-8')
    preface, separator, polyform = license_text.partition('\n---\n')
    if not separator or '# PolyForm Strict License 1.0.0' not in polyform:
        raise ValueError('ב-LICENSE חסרים הקו המפריד או הנוסח של PolyForm Strict 1.0.0')
    blocks = []
    for block in re.split(r'\n\s*\n', preface.strip()):
        if re.search('[\u0590-\u05FF]', block) and not block.startswith('Meitar ('):
            continue
        lines = block.splitlines() if block.startswith('Meitar (') else [' '.join(block.split())]
        blocks.extend(('body', line) for line in lines)
    for block in re.split(r'\n\s*\n', polyform.strip()):
        block = ' '.join(block.split())
        if block.startswith('# '):
            blocks.append(('title', block[2:]))
        elif block.startswith('## '):
            blocks.append(('heading', block[3:]))
        else:
            blocks.append(('body', block))
    return blocks


def render(language):
    summary = SUMMARY[language]
    rtl = language == 'he'
    colors = ''.join(f'\\red{r}\\green{g}\\blue{b};' for r, g, b in COLORS)
    out = ['{\\rtf1\\ansi\\ansicpg1252\\deff0\\uc1\n',
           '{\\fonttbl{\\f0\\fswiss\\fcharset0 Segoe UI;}{\\f1\\fswiss\\fcharset177 Segoe UI;}'
           '{\\f2\\fswiss\\fcharset0 Segoe UI Semibold;}{\\f3\\fswiss\\fcharset177 Segoe UI Semibold;}}\n',
           '{\\colortbl;' + colors + '}\n',
           '\\viewkind4\\deflang1033\n']
    out.append(paragraph(text(summary['lead']), rtl=rtl, size=11, color=SKY, semibold=True, after=80))
    for heading, items in summary['groups']:
        out.append(paragraph(text(heading), rtl=rtl, size=9.5, color=SKY, semibold=True, before=80, after=20))
        for item in items:
            out.append(paragraph(text('\u2022 ' + item), rtl=rtl, size=9, color=INK, after=10))
    for index, note in enumerate(summary['notes']):
        out.append(paragraph(text(note), rtl=rtl, size=9, color=INK if index < 2 else STEEL,
                             before=120 if index == 0 else 0, after=60))
    out.append(paragraph(text(summary['legal']), rtl=rtl, size=9.5, color=SKY, semibold=True, before=200, after=80))
    for kind, value in legal_blocks():
        if kind == 'title':
            out.append(paragraph('{\\b ' + inline(value) + '}', rtl=False, size=9, color=INK, before=60, after=40, line=252))
        elif kind == 'heading':
            out.append(paragraph('{\\b ' + inline(value) + '}', rtl=False, size=8.5, color=INK, before=100, after=20, line=252))
        else:
            out.append(paragraph(inline(value), rtl=False, size=8.5, color=STEEL, after=60, line=252))
    out.append('}\n')
    return ''.join(out).encode('ascii')


def main():
    parser = argparse.ArgumentParser(description='בונה את מסך הרישיון של המתקין מ-LICENSE')
    parser.add_argument('--check', action='store_true', help='רק בודק שהקבצים מעודכנים')
    args = parser.parse_args()
    stale = []
    for language in SUMMARY:
        path = PACKAGE / f'license.{language}.rtf'
        data = render(language)
        if args.check:
            if not path.exists() or path.read_bytes() != data:
                stale.append(path.relative_to(ROOT).as_posix())
        else:
            path.write_bytes(data)
    if stale:
        sys.exit('לא מעודכן (להריץ python3 tools/package/license_rtf.py): ' + ', '.join(stale))


if __name__ == '__main__':
    main()
