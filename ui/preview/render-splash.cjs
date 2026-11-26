// אב-טיפוס של מסך הפתיחה בדפדפן, לביקורת עיצובית עם צילומי מסך.
// המסך האמיתי מצויר ב-GDI+ (compat/shell/splash_paint.cc) מאותם טוקנים ואותה
// גאומטריה. כאן אפשר לבדוק פריסה, צבעים, גופנים ותנועה בלי Windows.
//
// שימוש: node ui/preview/render-splash.cjs <תיקיית-פלט>
// כותב צילום לכל שילוב של גרסה, מצב תצוגה, רגע בתנועה וגודל חלון.

const { chromium } = require('playwright');
const { mkdirSync, writeFileSync } = require('node:fs');
const { join, resolve } = require('node:path');
const G = require('../bridge-geometry.cjs');

const M = G.tokens.motion;
const N = G.tokens.bridge.strings.count;
const RELEASE_STAGGER = 40;
const DRAW_END = (N - 1) * M['string-stagger-ms'] + M['string-draw-ms'];
const HOLD_END = DRAW_END + M['hold-ms'];
const CYCLE = HOLD_END + (N - 1) * RELEASE_STAGGER + M['release-ms'] + 160;

const clamp = (v) => Math.max(0, Math.min(1, v));
const easeOut = (p) => 1 - (1 - p) ** 3;
const easeIn = (p) => p ** 2;

// מצב מיתר i ברגע t: כמה ממנו נמתח (p) ומה השקיפות שלו (o)
function stringState(i, t, reduced) {
  if (reduced) return { p: 1, o: 1 };
  t %= CYCLE;
  if (t < HOLD_END) return { p: easeOut(clamp((t - i * M['string-stagger-ms']) / M['string-draw-ms'])), o: 1 };
  const start = HOLD_END + (N - 1 - i) * RELEASE_STAGGER;
  return { p: 1, o: 1 - easeIn(clamp((t - start) / M['release-ms'])) };
}

const THEMES = {
  light: { attr: 'light', glow: false },
  dark: { attr: 'dark', glow: true },
  // ניגודיות גבוהה של Windows: צבעי המערכת בלבד, בלי זוהר
  contrast: { attr: 'contrast', glow: false },
};

// viewBox שמכיל את כל המסלול, כך שהקצוות המעוגלים שלו נראים בתוך החלון
const VB = { x: -20, y: 24, w: 296, h: 196 };

function bridgeSvg(t, theme, reduced, width) {
  const lift = 2.2;
  const lines = G.strings(undefined, undefined, undefined, lift).map((s, i) => {
    const { p, o } = stringState(i, t, reduced);
    if (p <= 0 || o <= 0) return '';
    const x2 = G.lerp(s.from[0], s.to[0], p), y2 = G.lerp(s.from[1], s.to[1], p);
    return `<line x1="${s.from[0].toFixed(2)}" y1="${s.from[1].toFixed(2)}" x2="${x2.toFixed(2)}" y2="${y2.toFixed(2)}" opacity="${o.toFixed(3)}"/>`;
  }).join('');
  const stays = G.stays(lift).map((s) => `<line x1="${s.from[0].toFixed(2)}" y1="${s.from[1].toFixed(2)}" x2="${s.to[0].toFixed(2)}" y2="${s.to[1].toFixed(2)}"/>`).join('');
  const mast = G.mastPolygon(5.2, 2.2).map((p) => p.map((v) => v.toFixed(2)).join(',')).join(' ');
  const glow = THEMES[theme].glow
    ? `<g stroke="var(--string-glow)" stroke-width="7" stroke-linecap="round" opacity="0.32" filter="url(#glow)">${lines}</g>` : '';
  return `<svg class="bridge" width="${width}" height="${Math.round(width * VB.h / VB.w)}" viewBox="${VB.x} ${VB.y} ${VB.w} ${VB.h}" aria-hidden="true">
    <defs><filter id="glow" x="-30%" y="-30%" width="160%" height="160%"><feGaussianBlur stdDeviation="3"/></filter></defs>
    ${glow}
    <g stroke="var(--string)" stroke-width="2.5" stroke-linecap="round">${lines}</g>
    <g stroke="var(--string)" stroke-width="1.6" stroke-linecap="round" opacity="0.38">${stays}</g>
    <path d="${G.DECK_PATH}" fill="none" stroke="var(--mast)" stroke-width="6" stroke-linecap="round"/>
    <polygon points="${mast}" fill="var(--mast)" stroke="var(--mast)" stroke-width="1.4" stroke-linejoin="round"/>
  </svg>`;
}

function page({ variant, theme, t, reduced, w, h, icon, name, status }) {
  const bridgeW = variant === 'a' ? 132 : Math.round(Math.min(w * 0.92, (h * 0.28) * VB.w / VB.h));
  const css = `
    html, body { margin: 0; background: var(--surface); }
    :root[data-theme='contrast'] { --surface: #000000; --ink: #FFFFFF; --ink-muted: #FFFFFF; --string: #FFFF00; --mast: #FFFFFF; }
    .splash { position: relative; width: ${w}px; height: ${h}px; overflow: hidden; background: var(--surface);
      font-family: var(--font-ui); color: var(--ink); }
    .app { position: absolute; inset-inline: 0; top: ${Math.round(h * 0.36 - 64)}px; display: flex;
      flex-direction: column; align-items: center; }
    .app img { width: 128px; height: 128px; display: block; }
    .app h1 { font-family: var(--font-display); font-weight: 500; font-size: var(--type-screen-title);
      line-height: 1.25; margin: 16px 0 0; color: var(--ink); }
    .meter { display: flex; flex-direction: column; align-items: center; margin-top: 40px; }
    .status { font-size: var(--type-body); line-height: 1.5; color: var(--ink-muted); margin-top: 10px; }
    .horizon { position: absolute; inset-inline: 0; bottom: ${Math.round(h * 0.06)}px; display: flex;
      justify-content: center; }
    .app .status { margin-top: 6px; }
  `;
  const bridge = bridgeSvg(t, theme, reduced, bridgeW);
  const meter = variant === 'a'
    ? `<div class="meter">${bridge}<div class="status">${status}</div></div>` : '';
  const horizon = variant === 'b' ? `<div class="horizon">${bridge}</div>` : '';
  const below = variant === 'b' ? `<div class="status">${status}</div>` : '';
  return `<!doctype html><html lang="he" dir="rtl" data-theme="${THEMES[theme].attr}"><head><meta charset="utf-8">
    <link rel="stylesheet" href="tokens.css"><style>${css}</style></head>
    <body><div class="splash"><div class="app"><img src="${icon}" alt=""><h1>${name}</h1>${below}${meter}</div>${horizon}</div></body></html>`;
}

async function render(outDir) {
  mkdirSync(outDir, { recursive: true });
  const here = resolve(__dirname);
  const icon = 'file://' + resolve(here, '../../tests/apps/lifecycle/res/mipmap-xxxhdpi/ic_launcher.png');
  const browser = await chromium.launch();
  const ctx = await browser.newContext({ deviceScaleFactor: 1 });
  const p = await ctx.newPage();
  const shots = [];
  const cases = [];
  const v = process.env.SPLASH_VARIANT || 'b';
  for (const theme of ['light', 'dark', 'contrast'])
    cases.push({ variant: v, theme, t: 1300, reduced: false, w: 400, h: 800 });
  for (const t of [200, 480, 820, 2000, 2250]) cases.push({ variant: v, theme: 'dark', t, reduced: false, w: 400, h: 800 });
  cases.push({ variant: v, theme: 'light', t: 200, reduced: true, w: 400, h: 800 });
  for (const [w, h] of [[1280, 800], [360, 640], [800, 1280]])
    cases.push({ variant: v, theme: 'light', t: 1300, reduced: false, w, h });
  for (const c of cases) {
    const html = page({ ...c, icon, name: 'אפליקציית בדיקה', status: 'נפתחת…' });
    const file = join(here, `_case.html`);
    writeFileSync(file, html);
    await p.setViewportSize({ width: c.w, height: c.h });
    await p.goto('file://' + file);
    await p.evaluate(() => document.fonts.ready);
    const name = `splash-${c.variant}-${c.theme}-${c.w}x${c.h}-t${c.t}${c.reduced ? '-reduced' : ''}.png`;
    await p.screenshot({ path: join(outDir, name) });
    shots.push(name);
  }
  const fonts = await p.evaluate(() => [...document.fonts].filter((f) => f.status === 'loaded').map((f) => `${f.family} ${f.weight}`));
  await browser.close();
  console.log(`נכתבו ${shots.length} צילומים ל-${outDir}. גופנים שנטענו: ${[...new Set(fonts)].join(', ')}`);
  console.log(`מחזור התנועה: ${CYCLE} אלפיות שנייה (מתיחה ${DRAW_END}, החזקה עד ${HOLD_END})`);
}

module.exports = { stringState, CYCLE, DRAW_END, HOLD_END };

if (require.main === module) {
  render(process.argv[2] || 'out-splash').catch((e) => { console.error(e); process.exit(1); });
}
