# העיצוב של מיתר: המקור

התיקייה הזו היא המקור של השפה החזותית. כל משטח (מסך הפתיחה, הדיאלוגים, מרכז הבקרה והמתקין) מקבל ממנה את הצבעים, הגופנים, המידות והגאומטריה של הגשר. הנימוקים בתוכנית העיצוב: [`docs/he/design/01-design-plan.md`](../docs/he/design/01-design-plan.md).

| קובץ | תפקיד |
|---|---|
| `tokens.json` | **המקור היחיד.** פלטה, צבעים לפי תפקיד (בהיר וכהה), זוגות ניגודיות שנבדקים, גופנים, סולם טיפוגרפי, מרווחים, רדיוסים, תנועה וגאומטריית הגשר |
| `bridge-geometry.cjs` | הגאומטריה של הגשר (תורן, מסלול ומיתרים) מתוך `tokens.json`, לאייקון ולאבי-הטיפוס |
| `preview/render-splash.cjs` | אב-טיפוס של מסך הפתיחה בדפדפן, לביקורת עם צילומי מסך בכל מצב וגודל |
| `preview/tokens.css` | מופק. משתני CSS לאבי-הטיפוס |

## הפקה

```bash
python3 tools/ui/generate.py
```

המחולל בודק לפני ההפקה שכל תפקיד מפנה לצבע תקין, שכל זוג ניגודיות עומד בסף (4.5:1 לטקסט, 3:1 לגבולות ולסימנים) בשני המצבים, ושקבצי הגופנים קיימים ושהשם שלהם תואם למה ש-Windows יראה. ב-CI מריצים אותו עם `--check`.

הקבצים המופקים: `compat/windows/gesher_tokens.h` (‏C ו-C++), ‏`tools/package/gesher-tokens-light.xaml`, ‏`gesher-tokens-dark.xaml` ו-`gesher-tokens-contrast.xaml` (‏WPF: מרכז הבקרה, כולל הגאומטריה של הגשר), ‏`tools/package/gesher-tokens.iss` (המתקין) ו-`ui/preview/tokens.css`.

במצב ניגודיות גבוהה כל תפקיד מפנה לצבע מערכת של Windows (המפתח `contrast` בכל תפקיד), והממשק משתמש רק בהם.

## הגופנים

`tools/package/ui-fonts/`: ‏David Libre ו-IBM Plex Sans Hebrew, שניהם ברישיון SIL Open Font License 1.1, והרישיונות לידם. המתקין מעתיק אותם ל-`{app}\ui-fonts`, והתוכנות טוענות אותם לתהליך שלהן בלבד, בלי להתקין גופן במערכת. התיקייה `fonts` שליד הקבצים המותקנים שייכת לגופנים של אנדרואיד, ולכן לא משתמשים בה.

## אב-הטיפוס

```bash
node ui/preview/render-splash.cjs <תיקיית-פלט>
```

## מרכז הבקרה

החלונות של מרכז הבקרה (`tools/package/gesher-panel-*.xaml`) מקבלים מ-`New-PanelView` (‏`gesher-panel-view.ps1`) את הצבעים של המצב הנוכחי ואת הסגנונות המשותפים (`gesher-panel-styles.xaml`), לפני הטעינה. הצילומים לביקורת מגיעים מהמשימה "מרכז הבקרה על Windows" ב-`hameitarim-design.yml`:

```powershell
tools/ui/control-center-preview.ps1 -OutDir <תיקיית-פלט>
```
