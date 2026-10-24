// Screenshot a decision deck after all iframes have loaded: node deck_shot.cjs <playwright-core> <deck.html> <light|dark> <out.png>
const { chromium } = require(process.argv[2]);
const [file, theme, out] = process.argv.slice(3);
(async () => {
  const browser = await chromium.launch({ executablePath: 'C:/Program Files/Google/Chrome/Application/chrome.exe', headless: true });
  const page = await browser.newPage({ viewport: { width: 1100, height: 1000 } });
  const errors = [];
  page.on('pageerror', e => errors.push(String(e)));
  page.on('console', m => { if (m.type() === 'error') errors.push(m.text()); });
  await page.goto('file:///' + file.split('\\').join('/') + '?theme=' + theme);
  // Lazy iframes only load near the viewport: walk the page, then give React time to mount.
  const h = await page.evaluate(() => document.body.scrollHeight);
  for (let y = 0; y < h; y += 700) { await page.evaluate(v => window.scrollTo(0, v), y); await page.waitForTimeout(250); }
  await page.evaluate(() => window.scrollTo(0, 0));
  await page.waitForTimeout(1500);
  const frames = page.frames().slice(1);
  const empty = [];
  for (const f of frames) {
    const n = await f.evaluate(() => document.querySelectorAll('.app').length).catch(() => -1);
    if (n < 1) empty.push(f.url().slice(0, 80));
    f.on && null;
  }
  for (const f of frames) {
    const errs = await f.evaluate(() => window.__errs || []).catch(() => []);
    errors.push(...errs);
  }
  await page.screenshot({ path: out, fullPage: true });
  console.log(`frames ${frames.length}, empty ${empty.length}`, empty.slice(0, 5), 'errors:', errors.length ? errors.slice(0, 5) : 'none');
  await browser.close();
})();
