// מצייר את מסך הפתיחה האמיתי (compat/shell/splash_paint.cc) לקובצי PNG, לביקורת עם צילומי
// מסך. לא חלק מהמוצר: ה-CI בונה אותו עם llvm-mingw ומריץ אותו על Windows
// (.github/workflows/hameitarim-design.yml), כי GDI+ קיים רק ב-Windows.
//
// שימוש: splash_preview.exe <תיקיית ui-fonts> <אייקון PNG של אפליקציה> <תיקיית פלט>
//
// כל מצב נכתב לקובץ משלו. הכלי נכשל (קוד יציאה שאינו 0) אם הגופנים לא נטענו, או אם
// ציור יצא כמעט כולו בצבע הרקע.
#undef NOGDI
#undef WIN32_LEAN_AND_MEAN
#include <windows.h>

#include <algorithm>
#include <cstdio>
#include <string>
#include <vector>

#if defined(__clang__)
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wunused-parameter"
#pragma clang diagnostic ignored "-Wextra"
#endif
namespace Gdiplus {
using std::max;
using std::min;
}  // namespace Gdiplus
#include <gdiplus.h>
#if defined(__clang__)
#pragma clang diagnostic pop
#endif

#include "../../compat/shell/splash_paint.h"

namespace {

struct Case {
  const wchar_t* name;
  int width, height;
  bool dark, high_contrast, reduced_motion, rtl;
  unsigned long long elapsed_ms;
};

// המצבים: שלושה מראות, תנועה בכמה רגעים, הפחתת תנועה, ארבעה גדלים ואנגלית
const Case kCases[] = {
    {L"light-400x800", 400, 800, false, false, false, true, 1300},
    {L"dark-400x800", 400, 800, true, false, false, true, 1300},
    {L"system-colors-400x800", 400, 800, false, true, false, true, 1300},
    {L"reduced-motion-400x800", 400, 800, false, false, true, true, 200},
    {L"motion-dark-t0200", 400, 800, true, false, false, true, 200},
    {L"motion-dark-t0480", 400, 800, true, false, false, true, 480},
    {L"motion-dark-t0820", 400, 800, true, false, false, true, 820},
    {L"motion-dark-t2000", 400, 800, true, false, false, true, 2000},
    {L"light-1280x800", 1280, 800, false, false, false, true, 1300},
    {L"light-360x640", 360, 640, false, false, false, true, 1300},
    {L"light-800x1280", 800, 1280, false, false, false, true, 1300},
    {L"english-light-400x800", 400, 800, false, false, false, false, 1300},
};

bool PngEncoder(CLSID* clsid) {
  UINT count = 0, size = 0;
  if (Gdiplus::GetImageEncodersSize(&count, &size) != Gdiplus::Ok || size == 0) return false;
  std::vector<BYTE> buffer(size);
  auto* encoders = reinterpret_cast<Gdiplus::ImageCodecInfo*>(buffer.data());
  if (Gdiplus::GetImageEncoders(count, size, encoders) != Gdiplus::Ok) return false;
  for (UINT i = 0; i < count; ++i) {
    if (std::wstring(encoders[i].MimeType) == L"image/png") {
      *clsid = encoders[i].Clsid;
      return true;
    }
  }
  return false;
}

}  // namespace

int wmain(int argc, wchar_t** argv) {
  if (argc < 4) {
    std::fwprintf(stderr, L"usage: splash_preview <ui-fonts> <icon.png> <out-dir>\n");
    return 2;
  }
  gesher_splash::Art art;
  if (!art.Start(argv[1])) {
    std::fwprintf(stderr, L"GDI+ did not start\n");
    return 3;
  }
  const int families = art.FontFamiliesLoaded();
  std::wprintf(L"font families loaded: %d\n", families);
  if (families < 2) return 4;

  HICON icon = nullptr;
  {
    Gdiplus::Bitmap png(argv[2]);
    if (png.GetLastStatus() != Gdiplus::Ok || png.GetHICON(&icon) != Gdiplus::Ok) return 5;
  }
  CLSID encoder;
  if (!PngEncoder(&encoder)) return 6;

  int failures = 0;
  for (const Case& c : kCases) {
    BITMAPINFO info = {};
    info.bmiHeader.biSize = sizeof info.bmiHeader;
    info.bmiHeader.biWidth = c.width;
    info.bmiHeader.biHeight = -c.height;  // מלמעלה למטה
    info.bmiHeader.biPlanes = 1;
    info.bmiHeader.biBitCount = 32;
    info.bmiHeader.biCompression = BI_RGB;
    void* bits = nullptr;
    HDC dc = CreateCompatibleDC(nullptr);
    HBITMAP bitmap = CreateDIBSection(dc, &info, DIB_RGB_COLORS, &bits, nullptr, 0);
    if (dc == nullptr || bitmap == nullptr || bits == nullptr) return 7;
    HGDIOBJ previous = SelectObject(dc, bitmap);

    gesher_splash::Look look;
    look.dark = c.dark;
    look.high_contrast = c.high_contrast;
    look.reduced_motion = c.reduced_motion;
    const RECT client = {0, 0, c.width, c.height};
    art.Paint(dc, client, look, icon, 128, c.rtl ? L"אפליקציית בדיקה" : L"Test app",
              c.rtl ? L"נפתחת…" : L"Starting…", c.rtl, c.elapsed_ms);
    GdiFlush();

    // ציור שכמעט כולו בצבע הפינה (הרקע) אומר שמשהו לא צויר
    const auto* pixels = static_cast<const DWORD*>(bits);
    const DWORD background = pixels[0] & 0x00FFFFFF;
    long long different = 0;
    const long long total = static_cast<long long>(c.width) * c.height;
    for (long long i = 0; i < total; ++i) {
      if ((pixels[i] & 0x00FFFFFF) != background) ++different;
    }
    const double share = 100.0 * static_cast<double>(different) / static_cast<double>(total);

    SelectObject(dc, previous);
    const std::wstring path = std::wstring(argv[3]) + L"\\splash-" + c.name + L".png";
    Gdiplus::Bitmap image(bitmap, nullptr);
    const bool saved = image.Save(path.c_str(), &encoder, nullptr) == Gdiplus::Ok;
    std::wprintf(L"%ls: %.2f%% drawn%ls\n", c.name, share, saved ? L"" : L" (not saved)");
    if (!saved || share < 1.0) ++failures;
    DeleteObject(bitmap);
    DeleteDC(dc);
  }
  DestroyIcon(icon);
  return failures == 0 ? 0 : 8;
}
