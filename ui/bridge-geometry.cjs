// הגאומטריה של הגשר, מחושבת מ-ui/tokens.json (המפתח bridge).
// משותפת לאייקון (tools/icons/gesher-icon.cjs) ולאבי-הטיפוס בדפדפן. המימוש
// הנייטיב (compat/shell/splash_bridge.h) מחשב אותה נוסחה מ-gesher_tokens.h.
//
// היחידות הן של viewBox בגודל 256. התורן עולה מהמסלול אל קודקוד נטוי לאחור
// (ימינה), והמיתרים יורדים ממנו אל המסלול משמאל, בכיוון הקריאה העברי.

const { readFileSync } = require('node:fs');
const { join } = require('node:path');

const tokens = JSON.parse(readFileSync(join(__dirname, 'tokens.json'), 'utf8'));
const B = tokens.bridge;

const lerp = (a, b, t) => a + (b - a) * t;

// נקודה על המסלול (עקומת בזייה ריבועית) לפי x, בחיפוש בינארי על הפרמטר
function deckY(x) {
  const [p0, p1, p2] = B.deck;
  let lo = 0, hi = 1;
  for (let i = 0; i < 40; i++) {
    const t = (lo + hi) / 2;
    const bx = (1 - t) ** 2 * p0[0] + 2 * t * (1 - t) * p1[0] + t * t * p2[0];
    if (bx < x) lo = t; else hi = t;
  }
  const t = (lo + hi) / 2;
  return (1 - t) ** 2 * p0[1] + 2 * t * (1 - t) * p1[1] + t * t * p2[1];
}

const MAST_TOP = B['mast-top'];
const MAST_BASE = [B['mast-base-x'], deckY(B['mast-base-x'])];
const DECK_PATH = `M ${B.deck[0].join(' ')} Q ${B.deck[1].join(' ')} ${B.deck[2].join(' ')}`;

// נקודה על התורן: 0 בקודקוד, 1 בבסיס
const mastPoint = (t) => [lerp(MAST_TOP[0], MAST_BASE[0], t), lerp(MAST_TOP[1], MAST_BASE[1], t)];

// התורן כמצולע: רחב בבסיס וצר בקודקוד
function mastPolygon(baseHalf, topHalf) {
  const [bx, by] = MAST_BASE, [tx, ty] = MAST_TOP;
  const len = Math.hypot(tx - bx, ty - by);
  const nx = -(ty - by) / len, ny = (tx - bx) / len;
  const p = (x, y, h, s) => [x + s * h * nx, y + s * h * ny];
  return [p(bx, by, baseHalf, -1), p(bx, by, baseHalf, 1), p(tx, ty, topHalf, 1), p(tx, ty, topHalf, -1)];
}

// המיתרים: מהקודקוד ומטה לאורך התורן, אל המסלול משמאל. העליון מגיע הכי רחוק.
// deckLift מרים את קצה המיתר אל השפה העליונה של המסלול.
function strings(count = B.strings.count, mastT = B.strings['mast-t'], deckX = B.strings['deck-x'], deckLift = 0) {
  const out = [];
  for (let i = 0; i < count; i++) {
    const f = count === 1 ? 0 : i / (count - 1);
    const [mx, my] = mastPoint(lerp(mastT[0], mastT[1], f));
    const dx = lerp(deckX[0], deckX[1], f);
    out.push({ from: [mx, my], to: [dx, deckY(dx) - deckLift] });
  }
  return out;
}

// כבלי העיגון מאחורי התורן
function stays(deckLift = 0) {
  const x = B.stays['deck-x'];
  return B.stays['mast-t'].map((t) => ({ from: mastPoint(t), to: [x, deckY(x) - deckLift] }));
}

module.exports = { tokens, deckY, MAST_TOP, MAST_BASE, DECK_PATH, mastPoint, mastPolygon, strings, stays, lerp };
