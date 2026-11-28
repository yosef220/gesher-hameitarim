/* Copyright (C) 2026 The Gesher HaMeitarim Authors (גשר המיתרים); SPDX-License-Identifier: LicenseRef-PolyForm-Strict-1.0.0 */
/*
 * תצוגה מקדימה של הדיאלוגים הנייטיב של המארח, לביקורת עם צילומי מסך.
 *
 * מציג את הדיאלוגים האמיתיים (אותם קבצי .inc ואותה ערכת נושא כמו במוצר) על
 * שולחן העבודה האינטראקטיבי, בעברית ובאנגלית, במצב בהיר ובמצב כהה, ומצלם כל אחד
 * לקובץ BMP. כל דיאלוג נסגר מעצמו אחרי הצילום. המצב הכהה נקבע בערך
 * AppsUseLightTheme של המשתמש, כמו ש-Windows קובע אותו, וחוזר למה שהיה בסוף.
 *
 * שימוש: host-dialogs-preview.exe תיקיית_פלט
 */
#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#include <windows.h>
#include <stdio.h>
#include <string.h>
#include <wchar.h>
#include "../../compat/locale/ui_locale.h"
#include "../../compat/credentials/permission_dialog.inc"
#include "../../compat/credentials/background_permission_dialog.inc"
#include "../../compat/credentials/exact_alarm_dialog.inc"

#define PERSONALIZE L"Software\\Microsoft\\Windows\\CurrentVersion\\Themes\\Personalize"

static WCHAR g_directory[MAX_PATH];
static char g_name[96];
static int g_captured;
static int g_failures;

/* מצלם את החלון, כולל שורת הכותרת, לקובץ BMP של 32 ביט. */
static BOOL CaptureWindow(HWND window, const char* name) {
  RECT bounds;
  if (!GetWindowRect(window, &bounds)) return FALSE;
  int width = bounds.right - bounds.left, height = bounds.bottom - bounds.top;
  if (width <= 0 || height <= 0) return FALSE;
  HDC screen = GetDC(NULL);
  HDC memory = CreateCompatibleDC(screen);
  BITMAPINFO info;
  ZeroMemory(&info, sizeof(info));
  info.bmiHeader.biSize = sizeof(info.bmiHeader);
  info.bmiHeader.biWidth = width;
  info.bmiHeader.biHeight = -height; /* מלמעלה למטה */
  info.bmiHeader.biPlanes = 1;
  info.bmiHeader.biBitCount = 32;
  info.bmiHeader.biCompression = BI_RGB;
  void* pixels = NULL;
  HBITMAP bitmap = CreateDIBSection(screen, &info, DIB_RGB_COLORS, &pixels, NULL, 0);
  BOOL ok = FALSE;
  if (bitmap != NULL && pixels != NULL) {
    HGDIOBJ old = SelectObject(memory, bitmap);
    /* PW_RENDERFULLCONTENT (2): גם החלקים ש-DWM מצייר, כמו צבע שורת הכותרת. */
    if (PrintWindow(window, memory, 2)) {
      for (int i = 0; i < width * height; ++i) ((DWORD*)pixels)[i] |= 0xff000000u;
      WCHAR path[MAX_PATH + 100];
      swprintf(path, MAX_PATH + 100, L"%ls\\%hs.bmp", g_directory, name);
      HANDLE file = CreateFileW(path, GENERIC_WRITE, 0, NULL, CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, NULL);
      if (file != INVALID_HANDLE_VALUE) {
        BITMAPFILEHEADER header;
        ZeroMemory(&header, sizeof(header));
        DWORD size = (DWORD)width * (DWORD)height * 4, written = 0;
        header.bfType = 0x4d42;
        header.bfOffBits = sizeof(header) + sizeof(info.bmiHeader);
        header.bfSize = header.bfOffBits + size;
        ok = WriteFile(file, &header, sizeof(header), &written, NULL)
            && WriteFile(file, &info.bmiHeader, sizeof(info.bmiHeader), &written, NULL)
            && WriteFile(file, pixels, size, &written, NULL) && written == size;
        CloseHandle(file);
      }
    }
    SelectObject(memory, old);
  }
  if (bitmap != NULL) DeleteObject(bitmap);
  DeleteDC(memory);
  ReleaseDC(NULL, screen);
  return ok;
}

static void CALLBACK Shoot(HWND dialog, UINT message, UINT_PTR timer, DWORD time) {
  (void)message; (void)time;
  KillTimer(dialog, timer);
  if (CaptureWindow(dialog, g_name)) { ++g_captured; printf("צולם: %s\n", g_name); }
  else { ++g_failures; fprintf(stderr, "הצילום נכשל: %s\n", g_name); }
  PostMessageW(dialog, WM_CLOSE, 0, 0);
}

/* אחרי WM_INITDIALOG של כל דיאלוג בחוט הזה: מתזמן את הצילום, אחרי שהוא הוצג וצויר. */
static LRESULT CALLBACK AfterInit(int code, WPARAM wparam, LPARAM lparam) {
  if (code == HC_ACTION) {
    const CWPRETSTRUCT* call = (const CWPRETSTRUCT*)lparam;
    if (call->message == WM_INITDIALOG) SetTimer(call->hwnd, 1, 900, Shoot);
  }
  return CallNextHookEx(NULL, code, wparam, lparam);
}

static void SetAppsLight(DWORD light) {
  HKEY key;
  if (RegCreateKeyExW(HKEY_CURRENT_USER, PERSONALIZE, 0, NULL, 0, KEY_SET_VALUE, NULL, &key, NULL) == ERROR_SUCCESS) {
    RegSetValueExW(key, L"AppsUseLightTheme", 0, REG_DWORD, (const BYTE*)&light, sizeof(light));
    RegCloseKey(key);
  }
}

static void Name(const char* dialog, int hebrew, int dark) {
  snprintf(g_name, sizeof(g_name), "%s-%s-%s", dialog, hebrew ? "he" : "en", dark ? "dark" : "light");
}

static void ShowAll(int hebrew, int dark) {
  enum GesherUiLanguage language = hebrew ? GESHER_UI_HE : GESHER_UI_EN;
  static const WCHAR* he_rows =
      L"צילום תמונות ‪(android.permission.CAMERA)‬\r\n"
      L"הקלטת שמע ‪(android.permission.RECORD_AUDIO)‬\r\n"
      L"גישה למיקום ‪(android.permission.ACCESS_FINE_LOCATION)‬";
  static const WCHAR* en_rows =
      L"Take photos ‪(android.permission.CAMERA)‬\r\n"
      L"Record audio ‪(android.permission.RECORD_AUDIO)‬\r\n"
      L"Access precise location ‪(android.permission.ACCESS_FINE_LOCATION)‬";
  Name("permission", hebrew, dark);
  PermissionDialog(language, L"com.ideomobile.mercantile", hebrew ? he_rows : en_rows);
  Name("background", hebrew, dark);
  BackgroundPermissionDialog(language, L"com.google.android.gms",
      hebrew ? L"גישה למיקום ברקע ‪(android.permission.ACCESS_BACKGROUND_LOCATION)‬"
             : L"Access location in the background ‪(android.permission.ACCESS_BACKGROUND_LOCATION)‬");
  Name("alarm", hebrew, dark);
  const WCHAR* packages[] = {L"com.gesher.test.clock", L"com.gesher.test.reminder"};
  unsigned char allowed[] = {0, 1};
  ExactAlarmDialog(language, packages, allowed, 2);
  Name("account", hebrew, dark);
  GesherHostPrompt(GesherUiText(language, "account_title"),
      hebrew ? L"com.ideomobile.mercantile\r\nהאפליקציה מבקשת את החשבון המחובר שלך."
             : L"com.ideomobile.mercantile\r\nThe app asks for your signed-in account.",
      GesherUiText(language, "permission_allow"), GesherUiText(language, "permission_deny"),
      GesherUiRtl(language), NULL);
  Name("notice", hebrew, dark);
  GesherHostPrompt(GesherUiText(language, "brand"),
      hebrew ? L"ההתקנה נכשלה. הקובץ example.apk לא ניתן לקריאה."
             : L"The install failed. example.apk could not be read.",
      GesherUiText(language, "cp_dialog_ok"), NULL, GesherUiRtl(language), NULL);
  Name("long", hebrew, dark);
  WCHAR many[8193];
  many[0] = 0;
  for (int row = 0; row < 40; ++row)
    wcscat(many, hebrew ? L"שורה ארוכה ביותר של יומן השגיאה\r\n"
                        : L"A long line of the error log\r\n");
  GesherHostPrompt(GesherUiText(language, "brand"), many, GesherUiText(language, "cp_dialog_ok"), NULL,
      GesherUiRtl(language), NULL);
}

int wmain(int argc, wchar_t** argv) {
  SetConsoleOutputCP(CP_UTF8);
  if (argc != 2) { fprintf(stderr, "שימוש: host-dialogs-preview.exe תיקיית_פלט\n"); return 2; }
  wcsncpy(g_directory, argv[1], MAX_PATH - 1);
  CreateDirectoryW(g_directory, NULL);
  HHOOK hook = SetWindowsHookExW(WH_CALLWNDPROCRET, AfterInit, NULL, GetCurrentThreadId());
  if (!hook) return 3;
  DWORD original = 1, size = sizeof(original);
  BOOL had = RegGetValueW(HKEY_CURRENT_USER, PERSONALIZE, L"AppsUseLightTheme", RRF_RT_REG_DWORD, NULL,
                          &original, &size) == ERROR_SUCCESS;
  for (int dark = 0; dark < 2; ++dark) {
    SetAppsLight(dark ? 0 : 1);
    for (int hebrew = 1; hebrew >= 0; --hebrew) ShowAll(hebrew, dark);
  }
  if (had) SetAppsLight(original);
  else {
    HKEY key;
    if (RegOpenKeyExW(HKEY_CURRENT_USER, PERSONALIZE, 0, KEY_SET_VALUE, &key) == ERROR_SUCCESS) {
      RegDeleteValueW(key, L"AppsUseLightTheme");
      RegCloseKey(key);
    }
  }
  UnhookWindowsHookEx(hook);
  printf("סך הצילומים: %d, כשלים: %d\n", g_captured, g_failures);
  return g_failures == 0 && g_captured >= 24 ? 0 : 1;
}
