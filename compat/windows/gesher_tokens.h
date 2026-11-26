/* נוצר על ידי tools/ui/generate.py מתוך ui/tokens.json. לא לערוך ביד. */
#ifndef GESHER_TOKENS_H
#define GESHER_TOKENS_H

/* צבעים לפי תפקיד. כל תפקיד מופיע במצב בהיר (_LIGHT) ובמצב כהה (_DARK). */
/* משטח ראשי של חלון */
#define GESHER_SURFACE_LIGHT RGB(0xF7, 0xF8, 0xFA)
#define GESHER_SURFACE_DARK RGB(0x0F, 0x1A, 0x2B)
/* לוח, דיאלוג ושדה קלט */
#define GESHER_SURFACE_RAISED_LIGHT RGB(0xFF, 0xFF, 0xFF)
#define GESHER_SURFACE_RAISED_DARK RGB(0x16, 0x24, 0x3A)
/* שורה נבחרת ברשימה */
#define GESHER_SELECTION_LIGHT RGB(0xED, 0xE4, 0xD3)
#define GESHER_SELECTION_DARK RGB(0x42, 0x39, 0x2A)
/* טקסט ראשי */
#define GESHER_INK_LIGHT RGB(0x14, 0x23, 0x38)
#define GESHER_INK_DARK RGB(0xEA, 0xF0, 0xF7)
/* טקסט משני */
#define GESHER_INK_MUTED_LIGHT RGB(0x55, 0x65, 0x7B)
#define GESHER_INK_MUTED_DARK RGB(0x9D, 0xAA, 0xBD)
/* טקסט מושבת */
#define GESHER_INK_DISABLED_LIGHT RGB(0x8A, 0x96, 0xA8)
#define GESHER_INK_DISABLED_DARK RGB(0x5D, 0x6C, 0x83)
/* רקע של כפתור מושבת */
#define GESHER_FILL_DISABLED_LIGHT RGB(0xEE, 0xF1, 0xF5)
#define GESHER_FILL_DISABLED_DARK RGB(0x1C, 0x2A, 0x40)
/* כפתור ראשי, קישור ופס הכותרת */
#define GESHER_BRAND_LIGHT RGB(0x22, 0x40, 0x6A)
#define GESHER_BRAND_DARK RGB(0x86, 0xA9, 0xDB)
/* כפתור ראשי בריחוף */
#define GESHER_BRAND_HOVER_LIGHT RGB(0x2B, 0x51, 0x85)
#define GESHER_BRAND_HOVER_DARK RGB(0x9D, 0xBA, 0xE3)
/* כפתור ראשי לחוץ */
#define GESHER_BRAND_PRESSED_LIGHT RGB(0x19, 0x30, 0x4F)
#define GESHER_BRAND_PRESSED_DARK RGB(0x6F, 0x95, 0xCC)
/* טקסט על כפתור ראשי */
#define GESHER_ON_BRAND_LIGHT RGB(0xFF, 0xFF, 0xFF)
#define GESHER_ON_BRAND_DARK RGB(0x0F, 0x1A, 0x2B)
/* קו מפריד, רק כשהוא מפריד משמעות */
#define GESHER_LINE_LIGHT RGB(0xDD, 0xE3, 0xEA)
#define GESHER_LINE_DARK RGB(0x26, 0x36, 0x4F)
/* גבול של שדה ושל כפתור משני */
#define GESHER_LINE_STRONG_LIGHT RGB(0x7D, 0x8A, 0x9D)
#define GESHER_LINE_STRONG_DARK RGB(0x6C, 0x7D, 0x97)
/* טבעת פוקוס של מקלדת */
#define GESHER_FOCUS_LIGHT RGB(0x22, 0x40, 0x6A)
#define GESHER_FOCUS_DARK RGB(0x9D, 0xBA, 0xE3)
/* מיתר, ונקודת 'פועלת' */
#define GESHER_STRING_LIGHT RGB(0x9C, 0x72, 0x19)
#define GESHER_STRING_DARK RGB(0xE9, 0xBE, 0x5C)
/* הזוהר של המיתרים, קישוט בלבד */
#define GESHER_STRING_GLOW_LIGHT RGB(0xD9, 0xA4, 0x3B)
#define GESHER_STRING_GLOW_DARK RGB(0xD9, 0xA4, 0x3B)
/* התורן והמסלול של הגשר */
#define GESHER_MAST_LIGHT RGB(0x22, 0x40, 0x6A)
#define GESHER_MAST_DARK RGB(0xFF, 0xFF, 0xFF)
/* פעולה הרסנית ושגיאה */
#define GESHER_DANGER_LIGHT RGB(0xB4, 0x23, 0x18)
#define GESHER_DANGER_DARK RGB(0xF9, 0x70, 0x66)
/* טקסט על כפתור הרסני */
#define GESHER_ON_DANGER_LIGHT RGB(0xFF, 0xFF, 0xFF)
#define GESHER_ON_DANGER_DARK RGB(0x0F, 0x1A, 0x2B)

/* גופנים: נטענים מהתיקייה ui-fonts שליד הקבצים המותקנים, רק לתהליך עצמו. */
#define GESHER_FONT_DISPLAY L"David Libre"
#define GESHER_FONT_DISPLAY_400_GDI_FAMILY L"David Libre"
#define GESHER_FONT_DISPLAY_400_GDI_BOLD 0
#define GESHER_FONT_DISPLAY_500_GDI_FAMILY L"David Libre Medium"
#define GESHER_FONT_DISPLAY_500_GDI_BOLD 0
#define GESHER_FONT_DISPLAY_700_GDI_FAMILY L"David Libre"
#define GESHER_FONT_DISPLAY_700_GDI_BOLD 1
#define GESHER_FONT_UI L"IBM Plex Sans Hebrew"
#define GESHER_FONT_UI_400_GDI_FAMILY L"IBM Plex Sans Hebrew"
#define GESHER_FONT_UI_400_GDI_BOLD 0
#define GESHER_FONT_UI_500_GDI_FAMILY L"IBM Plex Sans Hebrew Medium"
#define GESHER_FONT_UI_500_GDI_BOLD 0
#define GESHER_FONT_UI_600_GDI_FAMILY L"IBM Plex Sans Hebrew SemiBold"
#define GESHER_FONT_UI_600_GDI_BOLD 0
#define GESHER_FONT_UI_700_GDI_FAMILY L"IBM Plex Sans Hebrew"
#define GESHER_FONT_UI_700_GDI_BOLD 1
#define GESHER_FONT_FALLBACK L"Segoe UI"
#define GESHER_FONT_FILES { L"DavidLibre-Regular.ttf", L"DavidLibre-Medium.ttf", L"DavidLibre-Bold.ttf", L"IBMPlexSansHebrew-Regular.ttf", L"IBMPlexSansHebrew-Medium.ttf", L"IBMPlexSansHebrew-SemiBold.ttf", L"IBMPlexSansHebrew-Bold.ttf" }
#define GESHER_FONT_FILE_COUNT 7

/* סולם הטיפוגרפיה, בפיקסלים */
#define GESHER_TYPE_CAPTION_SIZE 12
#define GESHER_TYPE_CAPTION_WEIGHT 400
#define GESHER_TYPE_CAPTION_DISPLAY 0
#define GESHER_TYPE_BODY_SIZE 14
#define GESHER_TYPE_BODY_WEIGHT 400
#define GESHER_TYPE_BODY_DISPLAY 0
#define GESHER_TYPE_LIST_TITLE_SIZE 16
#define GESHER_TYPE_LIST_TITLE_WEIGHT 500
#define GESHER_TYPE_LIST_TITLE_DISPLAY 0
#define GESHER_TYPE_SECTION_SIZE 21
#define GESHER_TYPE_SECTION_WEIGHT 600
#define GESHER_TYPE_SECTION_DISPLAY 0
#define GESHER_TYPE_SCREEN_TITLE_SIZE 24
#define GESHER_TYPE_SCREEN_TITLE_WEIGHT 500
#define GESHER_TYPE_SCREEN_TITLE_DISPLAY 1
#define GESHER_TYPE_WORDMARK_SIZE 36
#define GESHER_TYPE_WORDMARK_WEIGHT 700
#define GESHER_TYPE_WORDMARK_DISPLAY 1

/* מרווחים ורדיוסים, בפיקסלים */
#define GESHER_SPACE_1 4
#define GESHER_SPACE_2 8
#define GESHER_SPACE_3 12
#define GESHER_SPACE_4 16
#define GESHER_SPACE_5 24
#define GESHER_SPACE_6 32
#define GESHER_SPACE_7 48
#define GESHER_RADIUS_WINDOW 10
#define GESHER_RADIUS_PANEL 8
#define GESHER_RADIUS_BUTTON 6
#define GESHER_RADIUS_PILL 999

/* תנועה, באלפיות שנייה */
#define GESHER_MOTION_STRING_DRAW_MS 320
#define GESHER_MOTION_STRING_STAGGER_MS 140
#define GESHER_MOTION_HOLD_MS 700
#define GESHER_MOTION_RELEASE_MS 420

/* הגשר, ביחידות של viewBox בגודל 256 */
#define GESHER_BRIDGE_VIEW_BOX 256.0f
#define GESHER_BRIDGE_MAST_TOP_X 191.0f
#define GESHER_BRIDGE_MAST_TOP_Y 34.0f
#define GESHER_BRIDGE_MAST_BASE_X 166.0f
#define GESHER_BRIDGE_DECK_0_X -12.0f
#define GESHER_BRIDGE_DECK_0_Y 206.0f
#define GESHER_BRIDGE_DECK_1_X 128.0f
#define GESHER_BRIDGE_DECK_1_Y 186.0f
#define GESHER_BRIDGE_DECK_2_X 268.0f
#define GESHER_BRIDGE_DECK_2_Y 206.0f
#define GESHER_BRIDGE_STAY_MAST_T_FIRST 0.14f
#define GESHER_BRIDGE_STAY_MAST_T_LAST 0.34f
#define GESHER_BRIDGE_STAY_DECK_X 226.0f
#define GESHER_BRIDGE_STRING_COUNT 6
#define GESHER_BRIDGE_STRING_MAST_T_FIRST 0.06f
#define GESHER_BRIDGE_STRING_MAST_T_LAST 0.52f
#define GESHER_BRIDGE_STRING_DECK_X_FIRST 34.0f
#define GESHER_BRIDGE_STRING_DECK_X_LAST 146.0f

#endif /* GESHER_TOKENS_H */
