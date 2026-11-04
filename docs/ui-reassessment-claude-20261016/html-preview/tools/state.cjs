// Screenshot one phone in an arbitrary state:
//   node tools/state.cjs <playwright-core> <preview dir> <page key> <light|dark> '<initial JSON>' <out.png> [action ...]
// Actions (run in order, 450ms apart): CSS selector → click; "text:充值" → click first element containing the text;
// "scroll:<selector>:<px>" → set scrollTop; "wait:<ms>". Prints page errors; exits 1 if any.
const path = require('path');
const { chromium } = require(process.argv[2]);
const [here, key, theme, initial, out, ...actions] = process.argv.slice(3);
(async () => {
  const browser = await chromium.launch({ executablePath: 'C:/Program Files/Google/Chrome/Application/chrome.exe', headless: true });
  const page = await browser.newPage({ viewport: { width: 440, height: 900 }, deviceScaleFactor: 1.5 });
  const errors = [];
  page.on('pageerror', e => errors.push(String(e)));
  page.on('console', m => { if (m.type() === 'error') errors.push(m.text()); });
  const file = path.join(here, key + '.html').split(path.sep).join('/');
  const q = new URLSearchParams({ bare: '1', theme, initial: JSON.parse(JSON.stringify(initial)) });
  await page.goto('file:///' + file + '?' + q.toString());
  await page.waitForTimeout(700);
  for (const a of actions) {
    if (a.startsWith('scroll:')) {
      const [, css, y] = a.split(':');
      await page.locator(css).first().evaluate((el, dy) => { el.scrollTop = Number(dy); }, y);
    } else if (a.startsWith('wait:')) {
      await page.waitForTimeout(Number(a.slice(5)));
    } else if (a.startsWith('text:')) {
      await page.getByText(a.slice(5), { exact: false }).first().click({ force: true });
    } else {
      await page.locator(a).first().click({ force: true });
    }
    await page.waitForTimeout(450);
  }
  await page.locator('.page-bare').first().screenshot({ path: out });
  console.log('errors:', errors.length ? errors.slice(0, 5) : 'none');
  await browser.close();
  process.exit(errors.length ? 1 : 0);
})();
