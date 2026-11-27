// Copyright (C) 2026 The Gesher HaMeitarim Authors (גשר המיתרים); SPDX-License-Identifier: LicenseRef-PolyForm-Strict-1.0.0
// מיתר: התמונות של אשף ההתקנה, מאותו גשר ומיתרים של האייקון (tools/icons/gesher-icon.cjs).
//
// שימוש:
//   node tools/icons/gesher-wizard-images.cjs <תיקיית-פלט>
//   python3 tools/icons/make-wizard-images.py <תיקיית-פלט>     (ממיר ל-BMP ב-tools/package)
// כותב לתיקייה: wizard-<רוחב>x<גובה>.png (התמונה הגדולה בעמוד הפתיחה) ו-small-<רוחב>x<גובה>.png (הסמל הקטן
// בראש שאר העמודים), בגדלים ש-Inno Setup ממליץ עליהם לכל DPI.
//
// התמונה הגדולה: שמי ערב ירושלמיים והגשר בחלק התחתון, והמיתרים נפרשים שמאלה. בלי טקסט: השם והשורה
// "מבוסס על Gesher" כבר בטקסט של העמוד, בעברית ובאנגלית, ותמונה אחת משמשת את שני כיווני האשף.
const { chromium } = require('playwright');
const { mkdirSync, writeFileSync } = require('node:fs');
const { join } = require('node:path');
const { svg } = require('./gesher-icon.cjs');

// הגדלים המומלצים של Inno Setup ל-96, 144 ו-192 DPI (100%, 150% ו-200%). בגדלים אחרים Inno מותח את הקרובה ביותר
const WIZARD = [[164, 314], [246, 459], [328, 604]];
const SMALL = [[55, 55], [83, 80], [110, 106]];

// מרכיבים את הגשר מהאייקון עצמו: ה-defs והתורן, המיתרים והמסלול, בלי רקע השמיים והאריח המעוגל
function bridgeParts() {
  const icon = svg(256);
  const defs = icon.match(/<defs>[\s\S]*?<\/defs>/)[0];
  const group = icon.match(/<g clip-path="url\(#tile\)">([\s\S]*)<\/g>\s*<\/svg>/)[1];
  const body = group.replace(/<rect x="0" y="0" width="256" height="256" fill="url\(#(sky|halo)\)"\/>/g, '');
  return { defs, body };
}

function panelSvg(w, h) {
  const { defs, body } = bridgeParts();
  const k = h / 314;                       // כל המידות מחושבות לתמונה של 164x314 ומוגדלות
  const s = 1.3;                           // גודל הגשר ביחס לאייקון, כך שהתורן מגיע גבוה
  const tx = -96, ty = 28;                 // התורן קרוב לקצה הימני אך שלם, והמיתרים נפרשים שמאלה
  return `<svg xmlns="http://www.w3.org/2000/svg" width="${w}" height="${h}" viewBox="0 0 164 314" preserveAspectRatio="xMidYMid slice">
  ${defs}
  <defs>
    <linearGradient id="panelSky" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="#2F5B93"/><stop offset="0.62" stop-color="#1D3C69"/><stop offset="1" stop-color="#132744"/>
    </linearGradient>
    <radialGradient id="panelDawn" cx="30" cy="318" r="230" gradientUnits="userSpaceOnUse">
      <stop offset="0" stop-color="rgb(232,176,72)" stop-opacity="0.6"/>
      <stop offset="0.5" stop-color="rgb(232,176,72)" stop-opacity="0.14"/>
      <stop offset="1" stop-color="rgb(232,176,72)" stop-opacity="0"/>
    </radialGradient>
    <radialGradient id="panelHalo" cx="120" cy="70" r="150" gradientUnits="userSpaceOnUse">
      <stop offset="0" stop-color="#5C8FD0" stop-opacity="0.5"/><stop offset="1" stop-color="#5C8FD0" stop-opacity="0"/>
    </radialGradient>
  </defs>
  <rect width="164" height="314" fill="url(#panelSky)"/>
  <rect width="164" height="314" fill="url(#panelHalo)"/>
  <rect width="164" height="314" fill="url(#panelDawn)"/>
  <g transform="translate(${tx} ${ty}) scale(${s})">${body}</g>
</svg>`;
}

// הסמל הקטן: אותו אייקון, ממורכז על רקע לבן (כותרת העמוד של האשף לבנה)
function smallSvg(w, h) {
  const side = Math.round(Math.min(w, h) * 0.9);
  const inner = svg(256).replace(/width="\d+" height="\d+"/, `width="${side}" height="${side}"`);
  return `<div style="width:${w}px;height:${h}px;background:#fff;display:flex;align-items:center;justify-content:center">${inner}</div>`;
}

async function render(outDir) {
  mkdirSync(outDir, { recursive: true });
  const browser = await chromium.launch();
  const page = await browser.newPage({ deviceScaleFactor: 1 });
  for (const [w, h] of WIZARD) {
    await page.setViewportSize({ width: w, height: h });
    await page.setContent(`<!doctype html><html><body style="margin:0;background:#fff">${panelSvg(w, h)}</body></html>`);
    writeFileSync(join(outDir, `wizard-${w}x${h}.png`), await page.locator('svg').first().screenshot());
  }
  for (const [w, h] of SMALL) {
    await page.setViewportSize({ width: w, height: h });
    await page.setContent(`<!doctype html><html><body style="margin:0;background:#fff">${smallSvg(w, h)}</body></html>`);
    writeFileSync(join(outDir, `small-${w}x${h}.png`), await page.locator('div').first().screenshot());
  }
  await browser.close();
  console.log(`נכתבו ${WIZARD.length + SMALL.length} תמונות ל-${outDir}`);
}

module.exports = { WIZARD, SMALL, panelSvg, render };

if (require.main === module) {
  render(process.argv[2] || 'out-wizard').catch((e) => { console.error(e); process.exit(1); });
}
