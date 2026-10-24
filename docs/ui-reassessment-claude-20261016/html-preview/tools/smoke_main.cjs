// Smoke-check the main mode: load every route state and report page errors, missing app roots, placeholder pages and clicks that
// land somewhere else.
//   node tools/smoke_main.cjs <playwright-core> <preview dir> <page key> [light|dark] [shots dir | -] [name regex]
// States come from tools/routes/*.json (each: [{name, initial, actions?}], one file per owner) plus every option of
// decks/r2-details.json and decks/r3-new-screens.json, all loaded into <page key> instead of the deck's own page.
// Actions use the same syntax as tools/state.cjs. Exits 1 if anything fails.
//
// Click audit: clicks are forced (no actionability wait), so a target hidden under the tab bar, a sheet or a dialog — or a text that
// first matches some other element — used to "pass" while the click hit something else. Before every click the target is scrolled
// into view (as the click itself would) and the topmost element at its centre must be the target or one of its descendants;
// otherwise the state fails with what was hit instead. The click still runs, so later actions behave as before.
// A `text:` match is often a label inside its control (the span in a chip / button); the control's own 44 pt hit area (::after) sits
// on top of that span, so the hit is the control itself. That counts as on target: the element that handles the click (the nearest
// button / link / role / .tappable around the hit) must be the same one that owns the target — a button nested inside a target row
// does not count.
const fs = require('fs');
const path = require('path');
const { chromium } = require(process.argv[2]);
const [here, key, theme = 'light', shotsArg, filter] = process.argv.slice(3);
const shots = shotsArg && shotsArg !== '-' ? shotsArg : null;

const states = [];
const routesDir = path.join(here, 'tools/routes');
for (const f of fs.existsSync(routesDir) ? fs.readdirSync(routesDir).filter(n => n.endsWith('.json')).sort() : []) {
  for (const s of JSON.parse(fs.readFileSync(path.join(routesDir, f), 'utf8'))) states.push({ ...s, name: `${f.slice(0, -5)} · ${s.name}` });
}
for (const deck of ['decks/r2-details.json', 'decks/r3-new-screens.json']) {
  const spec = JSON.parse(fs.readFileSync(path.join(here, deck), 'utf8'));
  spec.questions.forEach((q, qi) => q.options.forEach((o, oi) => states.push({ name: `${path.basename(deck, '.json')} · Q${qi + 1}-${oi + 1} ${o.title}`, initial: o.initial || {} })));
}

const picked = filter ? states.filter(s => new RegExp(filter).test(s.name)) : states;

// Runs in the page: is the topmost element at the target's centre the target itself or inside it?
function hitTest(el) {
  const b = el.getBoundingClientRect();
  const desc = n => {
    if (!n) return '（什么也没有）';
    const cls = n.className && n.className.baseVal !== undefined ? n.className.baseVal : n.className;
    const name = `${n.tagName.toLowerCase()}${String(cls || '').split(' ').filter(Boolean).slice(0, 3).map(c => `.${c}`).join('')}`;
    const text = (n.innerText || n.textContent || '').replace(/\s+/g, ' ').trim().slice(0, 24);
    return text ? `${name}「${text}」` : name;
  };
  if (!b.width || !b.height) return { ok: false, reason: `目标没有大小（${Math.round(b.width)}×${Math.round(b.height)}，可能被隐藏）`, self: desc(el) };
  const x = b.left + b.width / 2;
  const y = b.top + b.height / 2;
  if (x < 0 || y < 0 || x >= innerWidth || y >= innerHeight) return { ok: false, reason: `目标中心 (${Math.round(x)}, ${Math.round(y)}) 在视口之外`, self: desc(el) };
  const hit = document.elementFromPoint(x, y);
  // The element that handles a click on n: the nearest control around it (null when there is none).
  const owner = n => (n ? n.closest('button, a[href], input, select, textarea, label, summary, [role="button"], [role="menuitem"], [role="menuitemradio"], [role="switch"], [role="tab"], [role="option"], [role="link"], .tappable') : null);
  const own = owner(el);
  const scope = own || el;
  if (hit && scope.contains(hit) && owner(hit) === own) return { ok: true };
  const where = hit && hit.closest('.tabbar, .toast, .dialog, .menu, .sheet, .dock, .overlay, .nav');
  const cover = where ? `（被 ${desc(where).split('「')[0]} 挡住）` : '';
  return { ok: false, reason: `点到的是 ${desc(hit)}${cover}`, self: desc(el) };
}

(async () => {
  const browser = await chromium.launch({ executablePath: 'C:/Program Files/Google/Chrome/Application/chrome.exe', headless: true });
  const page = await browser.newPage({ viewport: { width: 409, height: 868 } });
  let errors = [];
  page.on('pageerror', e => errors.push(String(e).slice(0, 240)));
  page.on('console', m => { if (m.type() === 'error') errors.push(m.text().slice(0, 240)); });
  const file = 'file:///' + path.join(here, `${key}.html`).split(path.sep).join('/');
  const bad = [];
  let clicks = 0;
  for (const [i, s] of picked.entries()) {
    errors = [];
    const misses = [];
    const q = new URLSearchParams({ bare: '1', theme, initial: JSON.stringify(s.initial) });
    await page.goto(`${file}?${q.toString()}`);
    await page.waitForTimeout(500);
    for (const [ai, a] of (s.actions || []).entries()) {
      try {
        if (a.startsWith('scroll:')) { const [, css, y] = a.split(':'); await page.locator(css).first().evaluate((el, dy) => { el.scrollTop = Number(dy); }, y); }
        else if (a.startsWith('wait:')) await page.waitForTimeout(Number(a.slice(5)));
        else {
          const loc = (a.startsWith('text:') ? page.getByText(a.slice(5), { exact: false }) : page.locator(a)).first();
          await loc.scrollIntoViewIfNeeded({ timeout: 3000 });
          const r = await loc.evaluate(hitTest);
          clicks++;
          if (!r.ok) misses.push(`点击 #${ai + 1} ${a} 没有落在目标上：${r.reason}；目标 ${r.self}`);
          await loc.click({ force: true, timeout: 3000 });
        }
        await page.waitForTimeout(350);
      } catch (e) { errors.push(`action #${ai + 1} ${a} failed: ` + String(e).split('\n')[0].slice(0, 200)); break; }
    }
    const n = await page.evaluate(() => document.querySelectorAll('.app').length);
    const text = await page.evaluate(() => document.body.innerText);
    const placeholder = /下一轮出布局对比|这一页的布局正在设计/.test(text);
    if (shots) await page.screenshot({ path: path.join(shots, `smoke-${String(i + 1).padStart(3, '0')}.png`) });
    if (n < 1 || errors.length || placeholder || misses.length) bad.push({ i: i + 1, name: s.name, app: n, placeholder, errors, misses });
  }
  console.log(JSON.stringify(bad, null, 1));
  console.log(`checked ${picked.length} states (${clicks} clicks audited) on ${key}.html (${theme}), failed ${bad.length}`);
  await browser.close();
  process.exit(bad.length ? 1 : 0);
})();
