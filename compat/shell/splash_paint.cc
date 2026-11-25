// מסך הפתיחה של גשר המיתרים: ראו splash_paint.h.
//
// הפריסה, מלמעלה למטה: האייקון של האפליקציה, השם שלה (David Libre), מה קורה עכשיו
// (IBM Plex Sans Hebrew), ובתחתית הגשר כקו אופק. המיתרים נמתחים מהתורן אל המסלול אחד
// אחד, נשארים רגע ונאספים בסדר הפוך. זו התנועה היחידה במוצר.
// הפרויקט מגדיר NOGDI עבור קוד AOSP. מסך הפתיחה מצייר ב-GDI+, שצריך את GDI ואת מה
// ש-WIN32_LEAN_AND_MEAN משמיט, כמו ב-gesher_launch.cc.
#undef NOGDI
#undef WIN32_LEAN_AND_MEAN
#include <windows.h>

#include "splash_paint.h"

#include <algorithm>
#include <cmath>
#include <string>

#if defined(__clang__)
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wunused-parameter"
#pragma clang diagnostic ignored "-Wextra"
#endif
// הכותרות של GDI+ משתמשות ב-min וב-max, והפרויקט מבטל את המאקרו שלהם (NOMINMAX)
namespace Gdiplus {
using std::max;
using std::min;
}  // namespace Gdiplus
#include <gdiplus.h>
#if defined(__clang__)
#pragma clang diagnostic pop
#endif

#include "../windows/gesher_tokens.h"

namespace gesher_splash {
namespace {

using Gdiplus::Color;
using Gdiplus::PointF;
using Gdiplus::RectF;

// ה-viewBox של הגשר במסך הפתיחה: כל המסלול בפנים, כך שהקצוות המעוגלים שלו נראים
constexpr float kViewX = -20.0f, kViewY = 24.0f, kViewW = 296.0f, kViewH = 196.0f;
// עוביים ביחידות של ה-viewBox
constexpr float kDeckWidth = 6.0f, kStringWidth = 2.5f, kStayWidth = 1.6f;
constexpr float kMastBaseHalf = 5.2f, kMastTopHalf = 2.2f, kMastOutline = 1.4f;
constexpr float kStringLift = 2.2f;  // קצה המיתר יושב על השפה העליונה של המסלול
constexpr BYTE kStayAlpha = 97;      // 0.38

constexpr int kStrings = GESHER_BRIDGE_STRING_COUNT;
constexpr unsigned kReleaseStaggerMs = 40;
constexpr unsigned kDrawEnd = (kStrings - 1) * GESHER_MOTION_STRING_STAGGER_MS + GESHER_MOTION_STRING_DRAW_MS;
constexpr unsigned kHoldEnd = kDrawEnd + GESHER_MOTION_HOLD_MS;
constexpr unsigned kCycle = kHoldEnd + (kStrings - 1) * kReleaseStaggerMs + GESHER_MOTION_RELEASE_MS + 160;

float Lerp(float a, float b, float t) { return a + (b - a) * t; }
float Clamp01(float v) { return v < 0.0f ? 0.0f : v > 1.0f ? 1.0f : v; }

// נקודה על המסלול לפי x: חיפוש בינארי על הפרמטר של עקומת הבזייה הריבועית
float DeckY(float x) {
  float lo = 0.0f, hi = 1.0f;
  for (int i = 0; i < 40; ++i) {
    const float t = (lo + hi) / 2.0f;
    const float bx = (1 - t) * (1 - t) * GESHER_BRIDGE_DECK_0_X + 2 * t * (1 - t) * GESHER_BRIDGE_DECK_1_X +
                     t * t * GESHER_BRIDGE_DECK_2_X;
    if (bx < x) lo = t; else hi = t;
  }
  const float t = (lo + hi) / 2.0f;
  return (1 - t) * (1 - t) * GESHER_BRIDGE_DECK_0_Y + 2 * t * (1 - t) * GESHER_BRIDGE_DECK_1_Y +
         t * t * GESHER_BRIDGE_DECK_2_Y;
}

// נקודה על התורן: 0 בקודקוד, 1 בבסיס
PointF MastPoint(float t) {
  return PointF(Lerp(GESHER_BRIDGE_MAST_TOP_X, GESHER_BRIDGE_MAST_BASE_X, t),
                Lerp(GESHER_BRIDGE_MAST_TOP_Y, DeckY(GESHER_BRIDGE_MAST_BASE_X), t));
}

struct Stroke {
  float progress;  // כמה מהמיתר נמתח
  float opacity;
};

Stroke StringState(int i, unsigned long long elapsed, bool reduced) {
  if (reduced) return {1.0f, 1.0f};
  const float t = static_cast<float>(elapsed % kCycle);
  if (t < kHoldEnd) {
    const float p = Clamp01((t - static_cast<float>(i * GESHER_MOTION_STRING_STAGGER_MS)) / GESHER_MOTION_STRING_DRAW_MS);
    return {1.0f - (1.0f - p) * (1.0f - p) * (1.0f - p), 1.0f};
  }
  const float start = static_cast<float>(kHoldEnd + (kStrings - 1 - i) * kReleaseStaggerMs);
  const float q = Clamp01((t - start) / GESHER_MOTION_RELEASE_MS);
  return {1.0f, 1.0f - q * q};
}

Color Rgb(COLORREF c, BYTE alpha = 255) { return Color(alpha, GetRValue(c), GetGValue(c), GetBValue(c)); }

struct Palette {
  COLORREF surface, ink, ink_muted, mast, string, glow;
  bool glow_on;
};

Palette PaletteFor(const Look& look) {
  if (look.high_contrast) {
    const COLORREF text = GetSysColor(COLOR_WINDOWTEXT);
    return {GetSysColor(COLOR_WINDOW), text, text, text, GetSysColor(COLOR_HOTLIGHT), text, false};
  }
  if (look.dark) {
    return {GESHER_SURFACE_DARK, GESHER_INK_DARK, GESHER_INK_MUTED_DARK, GESHER_MAST_DARK,
            GESHER_STRING_DARK, GESHER_STRING_GLOW_DARK, true};
  }
  return {GESHER_SURFACE_LIGHT, GESHER_INK_LIGHT, GESHER_INK_MUTED_LIGHT, GESHER_MAST_LIGHT,
          GESHER_STRING_LIGHT, GESHER_STRING_GLOW_LIGHT, false};
}

void RoundPen(Gdiplus::Pen* pen) {
  pen->SetStartCap(Gdiplus::LineCapRound);
  pen->SetEndCap(Gdiplus::LineCapRound);
  pen->SetLineJoin(Gdiplus::LineJoinRound);
}

// הגשר, בקנה מידה ובמיקום של החלון: ממורכז, בתחתית, לא גבוה מ-28% מהחלון
void PaintBridge(Gdiplus::Graphics* g, int w, int h, const Palette& pal, const Look& look,
                 unsigned long long elapsed) {
  const float s = std::min(w * 0.92f / kViewW, h * 0.28f / kViewH);
  const float ox = (w - kViewW * s) / 2.0f - kViewX * s;
  const float oy = (h - h * 0.06f - kViewH * s) - kViewY * s;
  auto at = [&](PointF p) { return PointF(ox + p.X * s, oy + p.Y * s); };

  // המיתרים
  for (int i = 0; i < kStrings; ++i) {
    const float f = kStrings == 1 ? 0.0f : static_cast<float>(i) / (kStrings - 1);
    const PointF from = MastPoint(Lerp(GESHER_BRIDGE_STRING_MAST_T_FIRST, GESHER_BRIDGE_STRING_MAST_T_LAST, f));
    const float dx = Lerp(GESHER_BRIDGE_STRING_DECK_X_FIRST, GESHER_BRIDGE_STRING_DECK_X_LAST, f);
    const PointF to(dx, DeckY(dx) - kStringLift);
    const Stroke st = StringState(i, elapsed, look.reduced_motion);
    if (st.progress <= 0.0f || st.opacity <= 0.0f) continue;
    const PointF end(Lerp(from.X, to.X, st.progress), Lerp(from.Y, to.Y, st.progress));
    if (pal.glow_on) {
      // זוהר: שלושה מעברים רחבים ושקופים במקום טשטוש, שאין ב-GDI+
      const float widths[] = {7.0f, 5.0f, 3.6f};
      const float alphas[] = {0.10f, 0.12f, 0.14f};
      for (int k = 0; k < 3; ++k) {
        Gdiplus::Pen glow(Rgb(pal.glow, static_cast<BYTE>(255.0f * alphas[k] * st.opacity)), widths[k] * s);
        RoundPen(&glow);
        g->DrawLine(&glow, at(from), at(end));
      }
    }
    Gdiplus::Pen pen(Rgb(pal.string, static_cast<BYTE>(255.0f * st.opacity)), kStringWidth * s);
    RoundPen(&pen);
    g->DrawLine(&pen, at(from), at(end));
  }

  // כבלי העיגון מאחורי התורן
  Gdiplus::Pen stay(Rgb(pal.string, kStayAlpha), kStayWidth * s);
  RoundPen(&stay);
  const float stay_x = GESHER_BRIDGE_STAY_DECK_X;
  const PointF anchor(stay_x, DeckY(stay_x) - kStringLift);
  for (float t : {GESHER_BRIDGE_STAY_MAST_T_FIRST, GESHER_BRIDGE_STAY_MAST_T_LAST}) {
    g->DrawLine(&stay, at(MastPoint(t)), at(anchor));
  }

  // המסלול: עקומת בזייה ריבועית, כמו ב-SVG, בצורה הקובית ש-GDI+ מצייר
  const PointF p0(GESHER_BRIDGE_DECK_0_X, GESHER_BRIDGE_DECK_0_Y);
  const PointF p1(GESHER_BRIDGE_DECK_1_X, GESHER_BRIDGE_DECK_1_Y);
  const PointF p2(GESHER_BRIDGE_DECK_2_X, GESHER_BRIDGE_DECK_2_Y);
  const PointF c1(p0.X + 2.0f / 3.0f * (p1.X - p0.X), p0.Y + 2.0f / 3.0f * (p1.Y - p0.Y));
  const PointF c2(p2.X + 2.0f / 3.0f * (p1.X - p2.X), p2.Y + 2.0f / 3.0f * (p1.Y - p2.Y));
  Gdiplus::Pen deck(Rgb(pal.mast), kDeckWidth * s);
  RoundPen(&deck);
  g->DrawBezier(&deck, at(p0), at(c1), at(c2), at(p2));

  // התורן: מצולע, רחב בבסיס וצר בקודקוד
  const PointF base(GESHER_BRIDGE_MAST_BASE_X, DeckY(GESHER_BRIDGE_MAST_BASE_X));
  const PointF top(GESHER_BRIDGE_MAST_TOP_X, GESHER_BRIDGE_MAST_TOP_Y);
  const float len = std::max(1.0f, std::hypot(top.X - base.X, top.Y - base.Y));
  const float nx = -(top.Y - base.Y) / len, ny = (top.X - base.X) / len;
  const PointF mast[] = {
      at(PointF(base.X - kMastBaseHalf * nx, base.Y - kMastBaseHalf * ny)),
      at(PointF(base.X + kMastBaseHalf * nx, base.Y + kMastBaseHalf * ny)),
      at(PointF(top.X + kMastTopHalf * nx, top.Y + kMastTopHalf * ny)),
      at(PointF(top.X - kMastTopHalf * nx, top.Y - kMastTopHalf * ny)),
  };
  Gdiplus::SolidBrush mast_fill(Rgb(pal.mast));
  g->FillPolygon(&mast_fill, mast, 4);
  Gdiplus::Pen mast_edge(Rgb(pal.mast), kMastOutline * s);
  RoundPen(&mast_edge);
  g->DrawPolygon(&mast_edge, mast, 4);
}

}  // namespace

unsigned CycleMs() { return kCycle; }

Look CurrentLook() {
  Look look;
  HIGHCONTRASTW contrast = {};
  contrast.cbSize = sizeof contrast;
  look.high_contrast = SystemParametersInfoW(SPI_GETHIGHCONTRAST, sizeof contrast, &contrast, 0) &&
                       (contrast.dwFlags & HCF_HIGHCONTRASTON) != 0;
  BOOL animation = TRUE;
  if (SystemParametersInfoW(SPI_GETCLIENTAREAANIMATION, 0, &animation, 0)) look.reduced_motion = !animation;
  DWORD light = 1, size = sizeof light;
  if (RegGetValueW(HKEY_CURRENT_USER, L"Software\\Microsoft\\Windows\\CurrentVersion\\Themes\\Personalize",
                   L"AppsUseLightTheme", RRF_RT_REG_DWORD, nullptr, &light, &size) == ERROR_SUCCESS) {
    look.dark = light == 0;
  }
  return look;
}

void ApplyCaption(HWND window, const Look& look) {
  if (look.high_contrast) return;
  HMODULE module = LoadLibraryExW(L"dwmapi.dll", nullptr, LOAD_LIBRARY_SEARCH_SYSTEM32);
  if (module == nullptr) return;
  using SetAttribute = HRESULT(WINAPI*)(HWND, DWORD, LPCVOID, DWORD);
  auto set = reinterpret_cast<SetAttribute>(reinterpret_cast<void*>(GetProcAddress(module, "DwmSetWindowAttribute")));
  if (set != nullptr) {
    const BOOL dark = look.dark ? TRUE : FALSE;
    const DWORD corner = 2;  // DWMWCP_ROUND
    const COLORREF caption = look.dark ? GESHER_SURFACE_DARK : GESHER_SURFACE_LIGHT;
    const COLORREF text = look.dark ? GESHER_INK_DARK : GESHER_INK_LIGHT;
    set(window, 20, &dark, sizeof dark);         // DWMWA_USE_IMMERSIVE_DARK_MODE
    set(window, 33, &corner, sizeof corner);     // DWMWA_WINDOW_CORNER_PREFERENCE
    set(window, 35, &caption, sizeof caption);   // DWMWA_CAPTION_COLOR
    set(window, 36, &text, sizeof text);         // DWMWA_TEXT_COLOR
  }
  FreeLibrary(module);
}

Art::~Art() {
  delete static_cast<Gdiplus::PrivateFontCollection*>(fonts_);
  fonts_ = nullptr;
  if (started_) Gdiplus::GdiplusShutdown(token_);
}

bool Art::Start(const wchar_t* fonts_dir) {
  Gdiplus::GdiplusStartupInput input;
  if (Gdiplus::GdiplusStartup(&token_, &input, nullptr) != Gdiplus::Ok) return false;
  started_ = true;
  auto* fonts = new Gdiplus::PrivateFontCollection();
  static const wchar_t* const kFiles[] = GESHER_FONT_FILES;
  for (const wchar_t* name : kFiles) {
    const std::wstring path = std::wstring(fonts_dir) + L"\\" + name;
    if (GetFileAttributesW(path.c_str()) != INVALID_FILE_ATTRIBUTES) fonts->AddFontFile(path.c_str());
  }
  fonts_ = fonts;
  return true;
}

void Art::Paint(HDC dc, const RECT& client, const Look& look, HICON icon, int icon_size, const wchar_t* label,
                const wchar_t* status, bool rtl, unsigned long long elapsed_ms) const {
  const int w = client.right - client.left, h = client.bottom - client.top;
  const Palette pal = PaletteFor(look);
  const int size = std::min(icon_size, w / 2);
  const int icon_top = std::max(16, static_cast<int>(h * 0.36f) - size / 2);
  {
    Gdiplus::Graphics g(dc);
    g.SetSmoothingMode(Gdiplus::SmoothingModeAntiAlias);
    g.SetPixelOffsetMode(Gdiplus::PixelOffsetModeHalf);
    g.SetTextRenderingHint(Gdiplus::TextRenderingHintClearTypeGridFit);
    Gdiplus::SolidBrush surface(Rgb(pal.surface));
    g.FillRectangle(&surface, 0, 0, w, h);

    // הגופנים שלנו, ואם לא נטענו: Segoe UI של Windows
    auto* fonts = static_cast<Gdiplus::PrivateFontCollection*>(fonts_);
    Gdiplus::FontFamily display(GESHER_FONT_DISPLAY_500_GDI_FAMILY, fonts);
    Gdiplus::FontFamily ui(GESHER_FONT_UI_400_GDI_FAMILY, fonts);
    Gdiplus::FontFamily fallback(GESHER_FONT_FALLBACK);
    const Gdiplus::FontFamily* title_family = display.IsAvailable() ? &display : &fallback;
    const Gdiplus::FontFamily* text_family = ui.IsAvailable() ? &ui : &fallback;
    Gdiplus::Font title(title_family, GESHER_TYPE_SCREEN_TITLE_SIZE, Gdiplus::FontStyleRegular, Gdiplus::UnitPixel);
    Gdiplus::Font text(text_family, GESHER_TYPE_BODY_SIZE, Gdiplus::FontStyleRegular, Gdiplus::UnitPixel);

    Gdiplus::StringFormat format;
    format.SetAlignment(Gdiplus::StringAlignmentCenter);
    format.SetTrimming(Gdiplus::StringTrimmingEllipsisCharacter);
    if (rtl) format.SetFormatFlags(Gdiplus::StringFormatFlagsDirectionRightToLeft);

    // שם האפליקציה: עד שתי שורות
    const float label_top = static_cast<float>(icon_top + size + 16);
    const RectF label_box(16.0f, label_top, static_cast<float>(std::max(1, w - 32)),
                          2.0f * GESHER_TYPE_SCREEN_TITLE_SIZE * 1.25f);
    RectF used;
    g.MeasureString(label, -1, &title, label_box, &format, &used);
    Gdiplus::SolidBrush ink(Rgb(pal.ink));
    g.DrawString(label, -1, &title, label_box, &format, &ink);

    // מה קורה עכשיו
    Gdiplus::StringFormat line;
    line.SetAlignment(Gdiplus::StringAlignmentCenter);
    line.SetTrimming(Gdiplus::StringTrimmingEllipsisCharacter);
    line.SetFormatFlags((rtl ? Gdiplus::StringFormatFlagsDirectionRightToLeft : 0) | Gdiplus::StringFormatFlagsNoWrap);
    const RectF status_box(16.0f, label_top + used.Height + 6.0f, static_cast<float>(std::max(1, w - 32)),
                           GESHER_TYPE_BODY_SIZE * 1.5f);
    Gdiplus::SolidBrush muted(Rgb(pal.ink_muted));
    g.DrawString(status, -1, &text, status_box, &line, &muted);

    PaintBridge(&g, w, h, pal, look, elapsed_ms);
  }
  if (icon != nullptr) DrawIconEx(dc, (w - size) / 2, icon_top, icon, size, size, 0, nullptr, DI_NORMAL);
}

}  // namespace gesher_splash
