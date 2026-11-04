// Interaction + screenshot verification for the layout previews.
// Usage: node verify_previews.cjs <path-to-playwright-core> [page ...]
const path = require('path');
const fs = require('fs');
const { chromium } = require(process.argv[2]);

const here = __dirname;
const CHROME = 'C:/Program Files/Google/Chrome/Application/chrome.exe';
const url = (key, q) => 'file:///' + path.join(here, `${key}.html`).split(path.sep).join('/') + q;
const T = { timeout: 2500 };

const SUITES = {
  'a-inbox': [
    ['今日 → 点错误账号进入详情 → 返回', async ph => {
      await ph(0).locator('.row', { hasText: 'OpenAI-备用-A' }).first().click();
      await ph(0).locator('.nav-title-text', { hasText: 'OpenAI-备用-A' }).waitFor(T);
      await ph(0).locator('.glass-btn').first().click();
    }],
    ['账号 → 选择 2 个 → 批量停止调度 → 撤销', async ph => {
      await ph(1).getByRole('button', { name: '选择' }).click();
      await ph(1).locator('.row', { hasText: 'Claude-官方-01' }).click();
      await ph(1).locator('.row', { hasText: 'Claude-官方-02' }).click();
      await ph(1).locator('.dock-btn', { hasText: '停止调度' }).click();
      await ph(1).locator('.toast', { hasText: '已停止调度 2 个账号' }).waitFor(T);
      await ph(1).locator('.toast-undo').click();
    }],
    ['详情 → 恢复状态 → 确认 → 回执', async ph => {
      await ph(2).locator('.act', { hasText: '恢复状态' }).click();
      await ph(2).locator('.dialog-btn', { hasText: '恢复状态' }).click();
      await ph(2).locator('.toast', { hasText: '已恢复' }).waitFor(T);
    }],
    ['充值 → 确认写明对象与金额 → 入账', async ph => {
      await ph(3).locator('.submit').click();
      await ph(3).locator('.dialog-title', { hasText: '王小明' }).waitFor(T);
      await ph(3).locator('.dialog-btn.role-destructive').click();
      await ph(3).locator('.balance-hero .money', { hasText: '$62.50' }).waitFor(T);
    }],
    ['记录 → 移除账号筛选 → 选择器重选', async ph => {
      await ph(4).locator('.chip.token', { hasText: '账号' }).click();
      await ph(4).locator('.token-add').click();
      await ph(4).locator('.sheet .row', { hasText: 'Claude-官方-03' }).click();
      await ph(4).locator('.chip.token', { hasText: 'Claude-官方-03' }).waitFor(T);
    }],
  ],
  'b-dashboard': [
    ['摘要 → 编辑 → 移除营收卡 → 添加回来', async ph => {
      await ph(0).getByRole('button', { name: '编辑' }).click();
      await ph(0).locator('[aria-label="移除今日营收"]').click({ force: true }); // edit mode jiggles continuously, so the element never reports "stable"
      await ph(0).locator('.db-pill', { hasText: '今日营收' }).click();
      await ph(0).getByRole('button', { name: '完成' }).click();
      await ph(0).locator('.db-card', { hasText: '今日营收' }).waitFor(T);
    }],
    ['摘要 → 需要处理叠卡 → 列表 → 恢复', async ph => {
      await ph(0).locator('.db-stack').click();
      await ph(0).locator('.nav-title-text', { hasText: '需要处理' }).waitFor(T);
      await ph(0).locator('.db-item', { hasText: 'GLM-直连-01' }).locator('.db-pill', { hasText: '恢复状态' }).click();
      await ph(0).locator('.dialog-btn', { hasText: '恢复状态' }).click();
      await ph(0).locator('.toast', { hasText: '已恢复' }).waitFor(T);
    }],
    ['账号 → 点“错误”磁贴筛选 → 进入磁贴详情', async ph => {
      await ph(1).locator('.db-ftile', { hasText: '错误' }).click();
      await ph(1).locator('.db-tile', { hasText: 'OpenAI-备用-A' }).click();
      await ph(1).locator('.db-pass-name', { hasText: 'OpenAI-备用-A' }).waitFor(T);
    }],
    ['详情 → 调度磁贴停止 → 撤销', async ph => {
      await ph(2).locator('.db-control', { hasText: '调度' }).click();
      await ph(2).locator('.toast', { hasText: '已停止调度' }).waitFor(T);
      await ph(2).locator('.toast-undo').click();
    }],
    ['数字键盘 → 输入 20 → 充值确认 → 入账', async ph => {
      await ph(3).locator('[aria-label="删除"]').click();
      await ph(3).locator('[aria-label="删除"]').click();
      await ph(3).locator('.db-key', { hasText: /^2$/ }).click();
      await ph(3).locator('.db-key', { hasText: /^0$/ }).click();
      await ph(3).locator('.submit', { hasText: '$20.00' }).click();
      await ph(3).locator('.dialog-btn.role-destructive').click();
      await ph(3).locator('.db-wallet-bal', { hasText: '$32.50' }).waitFor(T);
    }],
    ['浏览 → 错误请求 → 点柱子筛时段', async ph => {
      await ph(4).locator('.db-cat', { hasText: '错误请求' }).click();
      await ph(4).locator('.db-hist-col').nth(3).click();
      await ph(4).locator('.db-hist-head', { hasText: '09:30' }).waitFor(T);
    }],
  ],
  'c-workbench': [
    ['工作台 → 需处理账号视图 → 移除条件', async ph => {
      await ph(0).locator('.wb-view', { hasText: '需处理账号' }).click();
      await ph(0).locator('.nav-title-text', { hasText: '需处理账号' }).waitFor(T);
      await ph(0).locator('[aria-label="移除条件 状态"]').click();
      await ph(0).locator('.nav-title-text', { hasText: '全部账号' }).waitFor(T);
    }],
    ['账号表 → 点“今日”表头排序 → 选择 2 行 → 批量停 → 撤销', async ph => {
      await ph(1).locator('.wb-th .wb-td', { hasText: '今日' }).click();
      await ph(1).locator('.nav-subtitle', { hasText: '按今日降序' }).waitFor(T);
      await ph(1).locator('.wb-tool', { hasText: '选择' }).click();
      await ph(1).locator('.wb-tr', { hasText: 'Claude-官方-01' }).click();
      await ph(1).locator('.wb-tr', { hasText: 'Claude-官方-02' }).click();
      await ph(1).locator('.wb-tool', { hasText: '停止调度' }).click();
      await ph(1).locator('.toast', { hasText: '已停止调度 2 个账号' }).waitFor(T);
      await ph(1).locator('.toast-undo').click();
    }],
    ['账号表 → 列 → 关闭“平台”列', async ph => {
      await ph(1).locator('.wb-tool', { hasText: '列' }).click();
      await ph(1).locator('[aria-label="显示 平台"]').click();
      await ph(1).getByRole('button', { name: '完成' }).click();
      if (await ph(1).locator('.wb-th .wb-td', { hasText: '平台' }).count()) throw new Error('平台列仍在');
    }],
    ['检查器 → 下一条 → 上一条', async ph => {
      await ph(2).locator('.nav-trailing .glass-btn').nth(1).click();
      await ph(2).locator('.nav-subtitle', { hasText: '第 4 /' }).waitFor(T);
      await ph(2).locator('.nav-trailing .glass-btn').nth(0).click();
      await ph(2).locator('.nav-title-text', { hasText: 'Claude-官方-03' }).waitFor(T);
    }],
    ['调整余额 → 提交 → 确认 → 入账', async ph => {
      await ph(3).locator('.sheet .glass-prominent').click();
      await ph(3).locator('.dialog-title', { hasText: '王小明' }).waitFor(T);
      await ph(3).locator('.dialog-btn.role-destructive').click();
      await ph(3).locator('.wb-balance', { hasText: '$62.50' }).waitFor(T);
    }],
    ['记录 → 来源菜单切到上游错误 → 移除账号条件', async ph => {
      await ph(4).locator('.wb-token', { hasText: '来源' }).click();
      await ph(4).locator('.wb-pop .menu-item', { hasText: '上游错误' }).click();
      await ph(4).locator('.wb-token', { hasText: '上游错误' }).waitFor(T);
      await ph(4).locator('[aria-label="移除条件 账号"]').click();
      await ph(4).locator('.wb-tr', { hasText: '429' }).waitFor(T);
    }],
  ],
};

// Layout-owned suites: layouts/<key>.verify.cjs exports [[label, async (ph, page) => {...}], ...].
for (const f of fs.readdirSync(path.join(here, 'layouts')).filter(n => n.endsWith('.verify.cjs'))) {
  SUITES[f.slice(0, -'.verify.cjs'.length)] = require(path.join(here, 'layouts', f));
}

(async () => {
  const fullRun = process.argv.slice(3).length === 0;
  const keys = fullRun ? Object.keys(SUITES) : process.argv.slice(3);
  const browser = await chromium.launch({ executablePath: CHROME, headless: true });
  const report = {};
  for (const key of keys) {
    for (const theme of ['light', 'dark']) {
      const page = await browser.newPage({ viewport: { width: 1500, height: 1000 } });
      const errors = [];
      page.on('pageerror', e => errors.push(String(e)));
      page.on('console', m => { if (m.type() === 'error') errors.push(m.text()); });
      await page.goto(url(key, `?theme=${theme}`));
      await page.waitForSelector('.phone-cell');
      const ph = i => page.locator('.phone-cell').nth(i);
      const results = [];
      for (const [label, fn] of SUITES[key] || []) {
        try { await fn(ph, page); results.push({ check: label, ok: true }); }
        catch (e) { results.push({ check: label, ok: false, error: String(e.message || e).split('\n')[0] }); }
      }
      report[`${key}-${theme}`] = { results, errors };
      await page.close();
    }
  }
  fs.mkdirSync(path.join(here, 'screenshots'), { recursive: true });
  for (const key of keys) {
    for (const theme of ['light', 'dark']) {
      const page = await browser.newPage({ viewport: { width: 1440, height: 1000 } });
      await page.goto(url(key, `?theme=${theme}`));
      await page.waitForSelector('.phone-cell');
      await page.waitForTimeout(700);
      await page.screenshot({ path: path.join(here, 'screenshots', `${key}-${theme}.png`), fullPage: true });
      const box = await page.locator('.phones').boundingBox();
      await page.screenshot({ path: path.join(here, 'screenshots', `${key}-${theme}-phones.jpg`), type: 'jpeg', quality: 84, clip: { x: 0, y: box.y - 30, width: 1440, height: 900 } });
      await page.close();
    }
  }
  await browser.close();
  // Per-page results always; the aggregate file only on a full run, so parallel single-page runs never race.
  const meta = { browser: 'Chrome (headless, playwright-core 1.56)', scope: 'HTML layout previews only; not SwiftUI, not device' };
  fs.mkdirSync(path.join(here, 'verification'), { recursive: true });
  for (const key of keys) {
    const part = Object.fromEntries(Object.entries(report).filter(([k]) => k === `${key}-light` || k === `${key}-dark`));
    fs.writeFileSync(path.join(here, 'verification', `${key}.json`), JSON.stringify({ ...meta, report: part }, null, 2) + '\n');
  }
  if (fullRun) fs.writeFileSync(path.join(here, 'VERIFICATION.json'), JSON.stringify({ ...meta, report }, null, 2) + '\n');
  for (const [k, v] of Object.entries(report)) {
    const failed = v.results.filter(r => !r.ok);
    console.log(`${k}: ${v.results.length - failed.length}/${v.results.length} passed, ${v.errors.length} console/page errors`);
    failed.forEach(f => console.log('   FAIL', f.check, '→', f.error));
    v.errors.slice(0, 3).forEach(e => console.log('   ERR', e.slice(0, 200)));
  }
})();
