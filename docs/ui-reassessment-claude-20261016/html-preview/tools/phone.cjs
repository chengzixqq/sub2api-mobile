// Phone close-up: node phone.cjs <playwright-core> <preview dir> <page key> <light|dark> <phone index 1-6> <out.png> [click selector...]
const path = require('path');
const { chromium } = require(process.argv[2]);
const [here, key, theme, only, out, ...clicks] = process.argv.slice(3);
(async () => {
  const browser = await chromium.launch({ executablePath: 'C:/Program Files/Google/Chrome/Application/chrome.exe', headless: true });
  const page = await browser.newPage({ viewport: { width: 900, height: 1000 }, deviceScaleFactor: 1.5 });
  const errors = [];
  page.on('pageerror', e => errors.push(String(e)));
  page.on('console', m => { if (m.type() === 'error') errors.push(m.text()); });
  const file = path.join(here, key + '.html').split(path.sep).join('/');
  await page.goto('file:///' + file + '?theme=' + theme + '&only=' + only);
  await page.waitForTimeout(700);
  for (const sel of clicks) {
    if (sel.startsWith('scroll:')) {
      const [, css, y] = sel.split(':');
      await page.locator(css).first().evaluate((el, dy) => { el.scrollTop = Number(dy); }, y);
    } else if (sel.startsWith('text:')) {
      await page.getByText(sel.slice(5), { exact: false }).first().click();
    } else {
      await page.locator(sel).first().click();
    }
    await page.waitForTimeout(450);
  }
  await page.locator('.phone-cell').first().screenshot({ path: out });
  console.log('errors:', errors.length ? errors.slice(0, 5) : 'none');
  await browser.close();
})();
