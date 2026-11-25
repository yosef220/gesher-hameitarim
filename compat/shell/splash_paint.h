// מסך הפתיחה של גשר המיתרים: המראה, הגופנים, הציור והתנועה.
// הלוגיקה של ההפעלה (גילוי חלון האפליקציה, זמנים וביטול) נשארת ב-gesher_launch.cc.
//
// הצבעים, הגופנים, המידות והגאומטריה של הגשר באים מ-compat/windows/gesher_tokens.h,
// שמופק מ-ui/tokens.json. אב-הטיפוס בדפדפן (ui/preview/render-splash.cjs) מצייר את
// אותה פריסה מאותם ערכים, לביקורת עיצובית.
#ifndef GESHER_SHELL_SPLASH_PAINT_H
#define GESHER_SHELL_SPLASH_PAINT_H

#include <windows.h>

namespace gesher_splash {

// איך Windows מבקש שהמסך ייראה עכשיו
struct Look {
  bool dark = false;            // מצב כהה לאפליקציות
  bool high_contrast = false;   // ניגודיות גבוהה: צבעי המערכת בלבד
  bool reduced_motion = false;  // "אפקטי הנפשה" כבויים: המיתרים מלאים ובלי תנועה
};

Look CurrentLook();

// צבע הכותרת של החלון לפי המראה. דרך DWM, ב-Windows 11. במקום אחר הכותרת נשארת כמו שהיא,
// ובניגודיות גבוהה לא נוגעים בה.
void ApplyCaption(HWND window, const Look& look);

// משך מחזור התנועה, באלפיות שנייה
unsigned CycleMs();

// GDI+ והגופנים של גשר המיתרים, לתהליך הזה בלבד. בלי הגופנים הציור נעשה ב-Segoe UI.
class Art {
 public:
  Art() = default;
  Art(const Art&) = delete;
  Art& operator=(const Art&) = delete;
  ~Art();

  // false: אין GDI+, והקורא נשאר עם הציור הקודם
  bool Start(const wchar_t* fonts_dir);

  // מצייר את כל המסך ל-dc (מומלץ: dc של bitmap בזיכרון), ברגע elapsed_ms מתחילת התנועה
  void Paint(HDC dc, const RECT& client, const Look& look, HICON icon, int icon_size, const wchar_t* label,
             const wchar_t* status, bool rtl, unsigned long long elapsed_ms) const;

 private:
  ULONG_PTR token_ = 0;
  void* fonts_ = nullptr;  // Gdiplus::PrivateFontCollection
  bool started_ = false;
};

}  // namespace gesher_splash

#endif  // GESHER_SHELL_SPLASH_PAINT_H
