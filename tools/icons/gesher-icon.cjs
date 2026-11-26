// אייקון גשר המיתרים: SVG פרמטרי, עם רמת פירוט לפי גודל, שמרונדר ב-Chromium.
//
// שימוש:
//   node tools/icons/gesher-icon.cjs <תיקיית-פלט>
// כותב לתיקייה: icon-<גודל>.png לכל גודל ב-ICO, ‏icon-1024.png ו-gesher-strings.svg.
// את קובץ ה-ICO מרכיב tools/icons/make-icons.py מתוך ה-PNG האלה.
//
// מקור הצורה: גשר המיתרים בירושלים. תורן לבן נטוי, ומיתרים מוזהבים שנפרשים
// ממנו אל המסלול מימין לשמאל, בכיוון הקריאה העברי. הרקע הוא שמי ירושלים,
// עם אור ראשון של שחר באופק.
const { chromium } = require('playwright');
const { mkdirSync, writeFileSync } = require('node:fs');
const { join } = require('node:path');

const ICO_SIZES = [16, 20, 24, 32, 40, 48, 64, 96, 128, 256];

const C = {
  skyTop: '#2F5B93', skyBottom: '#132744',   // שמי ירושלים
  light: '232,176,72',                         // אור ראשון (זהב ירושלים, בהיר)
  stringNear: '#F7DE9F', stringFar: '#D49A2E', // מיתרים: בהירים ליד התורן, עמוקים ליד המסלול
  stringSmall: '#EDBE55',                      // מיתר בגודל קטן: צבע אחיד ובהיר, כדי שייראה
  white: '#FFFFFF', whiteShade: '#E3EAF4',
};

// התורן: מבסיס על המסלול אל קודקוד נטוי לאחור (ימינה), כמו בגשר האמיתי.
const MAST_TOP = [191, 34];
// המסלול: עקומה עדינה מתחת למיתרים, שהתורן יושב עליה.
const DECK_P = [[-12, 206], [128, 186], [268, 206]];
const DECK = `M ${DECK_P[0].join(' ')} Q ${DECK_P[1].join(' ')} ${DECK_P[2].join(' ')}`;

const lerp = (a, b, t) => a + (b - a) * t;
const pt = (t) => [lerp(MAST_TOP[0], MAST_BASE[0], t), lerp(MAST_TOP[1], MAST_BASE[1], t)];

// נקודה על המסלול לפי x (פתרון של עקומת בזייה ריבועית, בדיוק מספיק לאייקון)
function deckY(x) {
  let lo = 0, hi = 1;
  for (let i = 0; i < 40; i++) {
    const t = (lo + hi) / 2;
    const bx = (1 - t) ** 2 * DECK_P[0][0] + 2 * t * (1 - t) * DECK_P[1][0] + t * t * DECK_P[2][0];
    if (bx < x) lo = t; else hi = t;
  }
  const t = (lo + hi) / 2;
  return (1 - t) ** 2 * DECK_P[0][1] + 2 * t * (1 - t) * DECK_P[1][1] + t * t * DECK_P[2][1];
}
// התורן יושב על המסלול
const MAST_BASE = [166, deckY(166)];

function mastPolygon(baseHalf, topHalf) {
  const [bx, by] = MAST_BASE, [tx, ty] = MAST_TOP;
  const len = Math.hypot(tx - bx, ty - by);
  const nx = -(ty - by) / len, ny = (tx - bx) / len; // נורמל
  const p = (x, y, h, s) => `${(x + s * h * nx).toFixed(2)},${(y + s * h * ny).toFixed(2)}`;
  return `${p(bx, by, baseHalf, -1)} ${p(bx, by, baseHalf, 1)} ${p(tx, ty, topHalf, 1)} ${p(tx, ty, topHalf, -1)}`;
}

function svg(size) {
  const px = 256 / size;                         // פיקסל אחד ביחידות ה-viewBox
  const lod = size <= 24 ? 0 : size <= 48 ? 1 : 2;
  const count = [2, 4, 6][lod];
  const stringW = lod === 2 ? Math.max(3.2, px * 0.95) : px * (lod === 0 ? 1.35 : 1.1);
  const deckW = lod === 2 ? Math.max(12, px * 2.2) : px * (lod === 0 ? 2.0 : 2.2);
  const baseHalf = lod === 2 ? Math.max(8, px * 1.3) : px * (lod === 0 ? 1.25 : 1.3);
  const topHalf = lod === 2 ? Math.max(3.4, px * 0.7) : px * 0.75;
  const inset = lod === 0 ? 6 : 12, radius = lod === 0 ? 46 : 54;

  // המיתרים: מהקודקוד ומטה לאורך התורן, אל המסלול משמאל. העליון אל הרחוק ביותר.
  const strings = [];
  for (let i = 0; i < count; i++) {
    const f = count === 1 ? 0 : i / (count - 1);
    const [mx, my] = pt(lerp(0.06, lod === 0 ? 0.42 : 0.52, f));
    const dx = lerp(lod === 0 ? 44 : 34, lod === 0 ? 118 : 146, f);
    strings.push(`<line x1="${mx.toFixed(2)}" y1="${my.toFixed(2)}" x2="${dx.toFixed(2)}" y2="${(deckY(dx) - deckW * 0.3).toFixed(2)}"/>`);
  }
  // כבלי עיגון מאחורי התורן (רק בגדלים בינוניים וגדולים)
  const stays = lod === 0 ? '' : [0.14, 0.34].map((t) => {
    const [mx, my] = pt(t);
    return `<line x1="${mx.toFixed(2)}" y1="${my.toFixed(2)}" x2="226" y2="${(deckY(226) - deckW * 0.3).toFixed(2)}"/>`;
  }).join('');

  const stringPaint = lod === 0 ? C.stringSmall : 'url(#strings)';
  return `<svg xmlns="http://www.w3.org/2000/svg" width="${size}" height="${size}" viewBox="0 0 256 256">
  <defs>
    <linearGradient id="sky" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="${C.skyTop}"/><stop offset="1" stop-color="${C.skyBottom}"/>
    </linearGradient>
    <radialGradient id="dawn" cx="70" cy="236" r="190" gradientUnits="userSpaceOnUse">
      <stop offset="0" stop-color="rgb(${C.light})" stop-opacity="${lod === 0 ? 0.35 : 0.55}"/>
      <stop offset="0.55" stop-color="rgb(${C.light})" stop-opacity="0.12"/>
      <stop offset="1" stop-color="rgb(${C.light})" stop-opacity="0"/>
    </radialGradient>
    <linearGradient id="strings" x1="190" y1="40" x2="40" y2="200" gradientUnits="userSpaceOnUse">
      <stop offset="0" stop-color="${C.stringNear}"/><stop offset="1" stop-color="${C.stringFar}"/>
    </linearGradient>
    <linearGradient id="mast" x1="0" y1="0" x2="1" y2="0">
      <stop offset="0" stop-color="${C.white}"/><stop offset="1" stop-color="${C.whiteShade}"/>
    </linearGradient>
    <radialGradient id="halo" cx="184" cy="52" r="150" gradientUnits="userSpaceOnUse">
      <stop offset="0" stop-color="#5C8FD0" stop-opacity="0.55"/><stop offset="1" stop-color="#5C8FD0" stop-opacity="0"/>
    </radialGradient>
    <filter id="glow" x="-20%" y="-20%" width="140%" height="140%"><feGaussianBlur stdDeviation="4"/></filter>
    <filter id="shadow" x="-20%" y="-20%" width="140%" height="140%"><feGaussianBlur stdDeviation="3"/></filter>
    <clipPath id="tile"><rect x="${inset}" y="${inset}" width="${256 - 2 * inset}" height="${256 - 2 * inset}" rx="${radius}"/></clipPath>
  </defs>
  <g clip-path="url(#tile)">
    <rect x="0" y="0" width="256" height="256" fill="url(#sky)"/>
    ${lod === 2 ? '<rect x="0" y="0" width="256" height="256" fill="url(#halo)"/>' : ''}
    ${lod === 2 ? `<g stroke="#FFB743" stroke-width="${(stringW * 2.4).toFixed(2)}" stroke-linecap="round" opacity="0.42" filter="url(#glow)">${strings.join('')}</g>` : ''}
    <g stroke="${stringPaint}" stroke-width="${stringW.toFixed(2)}" stroke-linecap="round" opacity="${lod === 0 ? 1 : 0.95}">${strings.join('')}</g>
    <g stroke="${stringPaint}" stroke-width="${(stringW * 0.85).toFixed(2)}" stroke-linecap="round" opacity="0.7">${stays}</g>
    ${lod === 2 ? `<path d="${DECK}" transform="translate(0 7)" fill="none" stroke="#0A1628" stroke-width="${deckW.toFixed(2)}" opacity="0.45" filter="url(#shadow)"/>` : ''}
    <path d="${DECK}" fill="none" stroke="${C.white}" stroke-width="${deckW.toFixed(2)}" stroke-linecap="round"/>
    <polygon points="${mastPolygon(baseHalf, topHalf)}" fill="${lod === 2 ? 'url(#mast)' : C.white}" stroke="${C.white}" stroke-width="${(topHalf * 0.6).toFixed(2)}" stroke-linejoin="round"/>
  </g>
</svg>`;
}

async function render(outDir) {
  mkdirSync(outDir, { recursive: true });
  writeFileSync(join(outDir, 'gesher-strings.svg'), svg(256));
  const browser = await chromium.launch();
  const page = await browser.newPage({ deviceScaleFactor: 1 });
  for (const size of [...ICO_SIZES, 512, 1024]) {
    await page.setViewportSize({ width: size, height: size });
    await page.setContent(`<!doctype html><html><body style="margin:0;background:transparent">${svg(Math.min(size, 256)).replace(/width="\d+" height="\d+"/, `width="${size}" height="${size}"`)}</body></html>`);
    const png = await page.locator('svg').screenshot({ omitBackground: true });
    writeFileSync(join(outDir, `icon-${size}.png`), png);
  }
  await browser.close();
  console.log(`נכתבו ${ICO_SIZES.length + 2} תמונות ל-${outDir}`);
}

module.exports = { ICO_SIZES, svg, render };

if (require.main === module) {
  render(process.argv[2] || 'out-icons').catch((e) => { console.error(e); process.exit(1); });
}
