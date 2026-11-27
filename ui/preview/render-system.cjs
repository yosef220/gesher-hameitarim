// דף מערכת העיצוב של גשר המיתרים: סימן המילים והגשר, הצבעים, הגופנים, רכיבים בבהיר
// ובכהה, ובדיקת הניגודיות. הכל נבנה מ-ui/tokens.json ומהגאומטריה המשותפת, כך שהדף
// מציג בדיוק את הערכים שהמוצר משתמש בהם.
//
// שימוש: node ui/preview/render-system.cjs <תיקיית-פלט>
// כותב design-system.png (הדף המלא) ו-banner.png (הכותרת לבדה), בצפיפות כפולה.

const { chromium } = require('playwright');
const { mkdirSync, writeFileSync, unlinkSync } = require('node:fs');
const { join, resolve } = require('node:path');
const G = require('../bridge-geometry.cjs');

const T = G.tokens;
const hexOf = (name) => (T.palette[name] ? T.palette[name].hex : name).toUpperCase();
const role = (r, mode) => hexOf(T.roles[r][mode]);

function luminance(hex) {
  const c = [1, 3, 5].map((i) => parseInt(hex.slice(i, i + 2), 16) / 255)
    .map((v) => (v <= 0.03928 ? v / 12.92 : ((v + 0.055) / 1.055) ** 2.4));
  return 0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2];
}
const contrast = (a, b) => {
  const [x, y] = [luminance(a), luminance(b)].sort((p, q) => q - p);
  return (x + 0.05) / (y + 0.05);
};

// הגשר הגדול של הכותרת: אותה גאומטריה של האייקון ומסך הפתיחה
function heroBridge() {
  const lift = 2.6;
  const line = (s) => `<line x1="${s.from[0].toFixed(2)}" y1="${s.from[1].toFixed(2)}" x2="${s.to[0].toFixed(2)}" y2="${s.to[1].toFixed(2)}"/>`;
  const strings = G.strings(undefined, undefined, undefined, lift).map(line).join('');
  const stays = G.stays(lift).map(line).join('');
  const mast = G.mastPolygon(5.6, 2.4).map((p) => p.map((v) => v.toFixed(2)).join(',')).join(' ');
  return `<svg class="hero-bridge" viewBox="-20 24 296 196" aria-hidden="true">
    <defs><filter id="glow" x="-30%" y="-30%" width="160%" height="160%"><feGaussianBlur stdDeviation="3.2"/></filter>
      <linearGradient id="strings" x1="190" y1="40" x2="40" y2="200" gradientUnits="userSpaceOnUse">
        <stop offset="0" stop-color="#F7DE9F"/><stop offset="1" stop-color="#D49A2E"/></linearGradient></defs>
    <g stroke="${hexOf('jerusalem-gold')}" stroke-width="7" stroke-linecap="round" opacity="0.38" filter="url(#glow)">${strings}</g>
    <g stroke="url(#strings)" stroke-width="2.4" stroke-linecap="round">${strings}</g>
    <g stroke="url(#strings)" stroke-width="1.5" stroke-linecap="round" opacity="0.45">${stays}</g>
    <path d="${G.DECK_PATH}" fill="none" stroke="#FFFFFF" stroke-width="5.5" stroke-linecap="round"/>
    <polygon points="${mast}" fill="#FFFFFF" stroke="#FFFFFF" stroke-width="1.2" stroke-linejoin="round"/>
  </svg>`;
}

// רוחב יחסי לכל צבע: כמה מהממשק הוא תופס. הזהב הוא הדק, כמו שהוא נדיר
const SPAN = { cable: 2.4, stone: 1.0, steel: 1.0, ink: 1.15, night: 1.15, 'jerusalem-sky': 1.25, 'jerusalem-gold': 0.62 };
const PALETTE_ROLE = {
  cable: 'המשטח הבהיר הראשי', stone: 'שורה נבחרת והדגשה, לא רקע', steel: 'טקסט משני, קווים וגבולות',
  ink: 'טקסט ראשי', night: 'המשטח של המצב הכהה', 'jerusalem-sky': 'כפתור ראשי, קישורים ופס הכותרת',
  'jerusalem-gold': 'המיתרים בלבד, ונקודת "פועלת"',
};
const PALETTE_NAME = { cable: 'כבל', stone: 'אבן', steel: 'פלדה', ink: 'דיו', night: 'לילה', 'jerusalem-sky': 'שמי ירושלים', 'jerusalem-gold': 'זהב ירושלים' };
// לילה בקצה: הוא הצבע של המצב הכהה, ולצד הדיו שני הכחולים הכהים נראים כמעט זהים
const PALETTE_ORDER = ['jerusalem-sky', 'jerusalem-gold', 'ink', 'steel', 'stone', 'cable', 'night'];

function paletteHtml() {
  return PALETTE_ORDER.map((name) => {
    const hex = hexOf(name);
    const light = luminance(hex) > 0.45;
    return `<div class="swatch" style="flex:${SPAN[name]}">
      <div class="chip${light ? ' chip-light' : ''}" style="background:${hex}"></div>
      <div class="swatch-name">${PALETTE_NAME[name]}</div>
      <div class="swatch-hex"><bdi>${hex}</bdi></div>
      <div class="swatch-role">${PALETTE_ROLE[name]}</div></div>`;
  }).join('');
}

// הסולם הטיפוגרפי עם טקסט אמיתי מהממשק
const SCALE = [
  ['wordmark', 'גשר המיתרים', 'סימן המילים'],
  ['screen-title', 'מוביט', 'כותרת מסך'],
  ['section', 'הרשאות', 'כותרת אזור'],
  ['list-title', 'בנק לאומי', 'שורה ברשימה'],
  ['body', 'המצלמה זמינה לאפליקציה רק כשהיא פתוחה.', 'גוף הטקסט'],
  ['caption', 'עודכנה לפני שעתיים', 'הערה'],
];

function scaleHtml() {
  return SCALE.map(([key, sample, what]) => {
    const t = T.type[key];
    const family = t.font === 'display' ? "var(--font-display)" : "var(--font-ui)";
    return `<div class="scale-row"><div class="scale-meta"><span class="scale-size"><bdi>${t.size}</bdi></span>
      <span class="scale-what">${what}</span></div>
      <div class="scale-sample" style="font-family:${family};font-size:${t.size}px;font-weight:${t.weight}">${sample}</div></div>`;
  }).join('');
}

// רכיבים: אותו קטע במצב בהיר ובמצב כהה, מהצבעים לפי תפקיד
function componentsHtml(mode) {
  const c = (r) => role(r, mode);
  const apps = [
    ['מ', 'מוביט', 'פועלת', true, true],
    ['ב', 'בנק לאומי', 'לא פועלת', false, false],
    ['ז', 'זינג', 'מתעדכנת…', false, false],
  ];
  const rows = apps.map(([letter, name, status, selected, running]) => `
    <div class="row" style="background:${selected ? c('selection') : 'transparent'}">
      <div class="app-icon" style="background:${mode === 'light' ? '#DCE3EC' : '#22324A'};color:${c('ink')}">${letter}</div>
      <div class="row-text"><div class="row-name" style="color:${c('ink')}">${name}</div>
        <div class="row-status" style="color:${c('ink-muted')}">${running ? `<span class="dot" style="background:${c('string')}"></span>` : ''}${status}</div></div>
    </div>`).join('');
  return `<div class="panel ${mode}" style="background:${c('surface')};border-color:${c('line')}">
    <div class="panel-head"><div class="panel-title" style="color:${c('ink')}">האפליקציות שלי</div>
      <div class="search" style="background:${c('surface-raised')};border-color:${c('line-strong')};color:${c('ink-muted')}">חיפוש אפליקציה</div></div>
    <div class="rows">${rows}</div>
    <div class="actions">
      <span class="btn primary" style="background:${c('brand')};color:${c('on-brand')}">התקנת אפליקציה</span>
      <span class="btn secondary focus" style="border-color:${c('line-strong')};color:${c('ink')};outline-color:${c('focus')}">פתיחה</span>
      <span class="btn secondary" style="border-color:${c('danger')};color:${c('danger')}">הסרה…</span>
    </div>
    <div class="panel-note" style="color:${c('ink-muted')}">${mode === 'light' ? 'מצב בהיר' : 'מצב כהה, לפי ההגדרה של Windows'}. הכפתור "פתיחה" מוצג עם טבעת הפוקוס של המקלדת.</div>
  </div>`;
}

const CONTRAST_ROWS = [
  ['ink', 'surface', 'טקסט ראשי על המשטח'],
  ['ink-muted', 'surface', 'טקסט משני על המשטח'],
  ['ink-muted', 'selection', 'טקסט משני על שורה נבחרת'],
  ['on-brand', 'brand', 'טקסט על כפתור ראשי'],
  ['brand', 'surface', 'קישור על המשטח'],
  ['danger', 'surface', 'פעולה הרסנית'],
  ['line-strong', 'surface-raised', 'גבול של שדה קלט'],
  ['focus', 'surface', 'טבעת פוקוס'],
  ['string', 'surface', 'מיתר ונקודת "פועלת"'],
];

function contrastHtml() {
  const minimum = Object.fromEntries(T.contrast.pairs.map(([a, b, m]) => [`${a}|${b}`, m]));
  return CONTRAST_ROWS.map(([fg, bg, label]) => {
    const need = minimum[`${fg}|${bg}`];
    const cells = ['light', 'dark'].map((mode) => {
      const r = contrast(role(fg, mode), role(bg, mode));
      const width = Math.min(100, (r / 21) * 100);
      return `<div class="c-cell"><div class="c-sample" style="background:${role(bg, mode)};color:${role(fg, mode)}">אב</div>
        <div class="c-bar"><div class="c-fill" style="width:${width.toFixed(1)}%"></div>
        <div class="c-need" style="inset-inline-start:${((need / 21) * 100).toFixed(1)}%"></div></div>
        <div class="c-num"><bdi>${r.toFixed(1)}:1</bdi></div></div>`;
    }).join('');
    return `<div class="c-row"><div class="c-label">${label}<span class="c-min">לפחות <bdi>${need}:1</bdi></span></div>${cells}</div>`;
  }).join('');
}

function pageHtml() {
  const css = `
    :root { --pad: 88px; }
    html, body { margin: 0; background: var(--surface); }
    body { font-family: var(--font-ui); color: var(--ink); width: 1600px; }
    bdi { unicode-bidi: isolate; direction: ltr; }
    .hero { position: relative; height: 620px; background: ${hexOf('night')}; overflow: hidden; }
    .hero::before { content: ''; position: absolute; inset: 0;
      background: radial-gradient(900px 520px at 18% 108%, rgba(232,176,72,0.22), rgba(232,176,72,0) 70%); }
    .hero-bridge { position: absolute; left: 56px; bottom: 40px; width: 780px; height: auto; }
    .wordmark { position: absolute; right: var(--pad); top: 168px; text-align: right; }
    .wordmark h1 { margin: 0; font-family: var(--font-display); font-weight: 700; font-size: 112px; line-height: 1.05;
      color: #FFFFFF; letter-spacing: 0.005em; }
    .wordmark p { margin: 22px 0 0; font-size: 24px; line-height: 1.5; color: #B9C6D8; max-width: 520px; }
    section { padding: 72px var(--pad) 0; }
    h2 { margin: 0 0 8px; font-family: var(--font-display); font-weight: 500; font-size: 40px; line-height: 1.2; }
    .lede { margin: 0 0 32px; font-size: 17px; line-height: 1.6; color: var(--ink-muted); max-width: 760px; }
    .palette { display: flex; gap: 6px; align-items: flex-start; }
    .chip { height: 300px; border-radius: 2px; }
    .chip-light { box-shadow: inset 0 0 0 1px ${role('line', 'light')}; }
    .swatch-name { margin-top: 16px; font-weight: 500; font-size: 17px; }
    .swatch-hex { margin-top: 2px; font-size: 14px; color: var(--ink-muted); text-align: right; }
    .swatch-role { margin-top: 6px; font-size: 13px; line-height: 1.45; color: var(--ink-muted); padding-inline-end: 10px; }
    .type { display: grid; grid-template-columns: 1fr 1fr; gap: 64px; }
    .font-card .name { font-family: var(--font-display); font-size: 64px; font-weight: 500; line-height: 1.1; }
    .font-card.ui .name { font-family: var(--font-ui); font-weight: 600; font-size: 56px; }
    .font-card .why { margin: 14px 0 0; font-size: 16px; line-height: 1.6; color: var(--ink-muted); max-width: 600px; }
    .font-card .alef { margin-top: 18px; font-size: 26px; line-height: 1.5; }
    .font-card.display .alef { font-family: var(--font-display); }
    .scale { margin-top: 44px; border-top: 1px solid ${role('line', 'light')}; }
    .scale-row { display: grid; grid-template-columns: 220px 1fr; align-items: baseline; padding: 18px 0;
      border-bottom: 1px solid ${role('line', 'light')}; }
    .scale-size { font-weight: 600; font-size: 15px; margin-inline-end: 10px; }
    .scale-what { font-size: 15px; color: var(--ink-muted); }
    .scale-sample { line-height: 1.3; }
    .kit { display: grid; grid-template-columns: 1fr 1fr; gap: 32px; }
    .panel { border: 1px solid; border-radius: 10px; padding: 28px; }
    .panel-head { display: flex; align-items: center; justify-content: space-between; gap: 16px; }
    .panel-title { font-family: var(--font-display); font-weight: 500; font-size: 24px; }
    .search { border: 1px solid; border-radius: 6px; padding: 9px 14px; font-size: 14px; width: 220px; }
    .rows { margin-top: 18px; }
    .row { display: flex; align-items: center; gap: 14px; padding: 10px 12px; border-radius: 8px; }
    .app-icon { width: 44px; height: 44px; border-radius: 10px; display: grid; place-items: center;
      font-family: var(--font-display); font-weight: 700; font-size: 22px; }
    .row-name { font-weight: 500; font-size: 16px; }
    .row-status { font-size: 13px; display: flex; align-items: center; gap: 7px; margin-top: 2px; }
    .dot { width: 8px; height: 8px; border-radius: 999px; display: inline-block; }
    .actions { display: flex; gap: 12px; margin-top: 22px; flex-wrap: wrap; }
    .btn { display: inline-block; padding: 10px 18px; border-radius: 6px; font-size: 15px; font-weight: 500;
      border: 1px solid transparent; }
    .btn.secondary { background: transparent; }
    .btn.focus { outline: 2px solid; outline-offset: 3px; }
    .panel-note { margin-top: 18px; font-size: 13px; line-height: 1.5; }
    .c-head, .c-row { display: grid; grid-template-columns: 360px 1fr 1fr; gap: 28px; align-items: center; }
    .c-head { font-size: 14px; color: var(--ink-muted); padding-bottom: 10px; border-bottom: 1px solid ${role('line', 'light')}; }
    .c-row { padding: 12px 0; border-bottom: 1px solid ${role('line', 'light')}; }
    .c-label { font-size: 16px; }
    .c-min { display: block; font-size: 13px; color: var(--ink-muted); margin-top: 2px; }
    .c-cell { display: grid; grid-template-columns: 52px 1fr 70px; gap: 14px; align-items: center; }
    .c-sample { height: 34px; border-radius: 6px; display: grid; place-items: center; font-weight: 600; font-size: 16px;
      box-shadow: inset 0 0 0 1px rgba(20,35,56,0.08); }
    .c-bar { position: relative; height: 6px; border-radius: 999px; background: ${role('line', 'light')}; }
    .c-fill { position: absolute; inset-block: 0; inset-inline-start: 0; border-radius: 999px; background: ${hexOf('jerusalem-sky')}; }
    .c-need { position: absolute; top: -5px; width: 2px; height: 16px; background: ${role('danger', 'light')}; }
    .c-num { font-size: 15px; font-weight: 600; text-align: left; }
    footer { padding: 56px var(--pad) 72px; font-size: 14px; line-height: 1.6; color: var(--ink-muted); }
  `;
  const fontWhy = {
    display: 'גרסה חופשית של דוד, הגופן העברי הקלאסי של ישמעאל דוד. דוד הוא גם בעל הכינור שהמיתרים שלו נתנו לגשר את שמו. לכותרות, לסימן המילים ולמסך הפתיחה.',
    ui: 'גופן מהונדס ומדויק, קריא בעברית גם בגדלים קטנים, ומטפל טוב בשמות חבילות לועזיים. לכל טקסט הממשק.',
  };
  return `<!doctype html><html lang="he" dir="rtl" data-theme="light"><head><meta charset="utf-8">
    <link rel="stylesheet" href="tokens.css"><style>${css}</style></head><body>
    <header class="hero">${heroBridge()}
      <div class="wordmark"><h1>גשר המיתרים</h1><p>אפליקציות אנדרואיד על Windows, כחלונות רגילים, בעברית.</p></div>
    </header>
    <section><h2>צבעים</h2>
      <p class="lede">שבעה צבעים, ולכל אחד תפקיד. הזהב הוא האור על המיתרים, ולכן הוא הדק מכולם: הוא לא משמש לטקסט ולא לרקע.</p>
      <div class="palette">${paletteHtml()}</div></section>
    <section><h2>גופנים</h2>
      <div class="type">
        <div class="font-card display"><div class="name">David Libre</div><p class="why">${fontWhy.display}</p>
          <div class="alef">אבגדהוזחטיכלמנסעפצקרשת</div></div>
        <div class="font-card ui"><div class="name">IBM Plex Sans Hebrew</div><p class="why">${fontWhy.ui}</p>
          <div class="alef">אבגדהוזחטיכלמנסעפצקרשת 0123456789</div></div>
      </div>
      <div class="scale">${scaleHtml()}</div></section>
    <section><h2>רכיבים</h2>
      <p class="lede">אותם רכיבים בשני המצבים, מאותם טוקנים. פינות לפי תפקיד: חלון 10, לוח 8, כפתור 6, ונקודת מצב עגולה לגמרי.</p>
      <div class="kit">${componentsHtml('light')}${componentsHtml('dark')}</div></section>
    <section><h2>ניגודיות</h2>
      <p class="lede">כל זוג נבדק אוטומטית בכל הפקה של הטוקנים, בשני המצבים. הקו האדום הוא הסף: 4.5:1 לטקסט, ו-3:1 לגבולות ולסימנים.</p>
      <div class="c-head"><div>זוג</div><div>מצב בהיר</div><div>מצב כהה</div></div>
      ${contrastHtml()}</section>
    <footer>הדף נוצר אוטומטית מקובץ העיצוב של התוכנה (ui/tokens.json), כך שהוא מציג בדיוק את הערכים שהתוכנה משתמשת בהם. מרכז הבקרה, הדיאלוגים והמתקין עוד לא נבנו בשפה הזו, ולכן הם לא מופיעים כאן.</footer>
  </body></html>`;
}

async function render(outDir) {
  mkdirSync(outDir, { recursive: true });
  const file = join(__dirname, '_system.html');
  writeFileSync(file, pageHtml());
  const browser = await chromium.launch();
  const page = await (await browser.newContext({ deviceScaleFactor: 2, viewport: { width: 1600, height: 900 } })).newPage();
  await page.goto('file://' + resolve(file));
  await page.evaluate(() => document.fonts.ready);
  await page.screenshot({ path: join(outDir, 'design-system.png'), fullPage: true });
  await page.locator('header.hero').screenshot({ path: join(outDir, 'banner.png') });
  const fonts = await page.evaluate(() => [...document.fonts].filter((f) => f.status === 'loaded').map((f) => `${f.family} ${f.weight}`));
  await browser.close();
  unlinkSync(file);
  console.log(`נכתבו design-system.png ו-banner.png ל-${outDir}. גופנים שנטענו: ${[...new Set(fonts)].join(', ')}`);
}

if (require.main === module) {
  render(process.argv[2] || 'out-system').catch((e) => { console.error(e); process.exit(1); });
}
