// Quick screenshot helper: node shot.cjs <playwright-core> <preview dir> <page key> <light|dark> <out.png>
const path = require('path');
const { chromium } = require(process.argv[2]);
const [here, key, theme, out] = process.argv.slice(3);
(async () => {
  const browser = await chromium.launch({ executablePath: 'C:/Program Files/Google/Chrome/Application/chrome.exe', headless: true });
  const page = await browser.newPage({ viewport: { width: 1440, height: 1000 } });
  const errors = [];
  page.on('pageerror', e => errors.push(String(e)));
  page.on('console', m => { if (m.type() === 'error') errors.push(m.text()); });
  const file = path.join(here, key + '.html').split(path.sep).join('/');
  await page.goto('file:///' + file + '?theme=' + theme);
  await page.waitForTimeout(900);
  await page.screenshot({ path: out, fullPage: true });
  console.log('errors:', errors.length ? errors.slice(0, 5) : 'none');
  await browser.close();
})();
