/* Build offline single-file HTML previews. Usage: node build.cjs [page ...] */
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');

const here = __dirname;
const deps = path.resolve(here, '../../../build/ui-design-deps');
const Babel = require(path.join(deps, 'babel.js'));
const runtime = ['react.js', 'react-dom.js'].map(name => fs.readFileSync(path.join(deps, name), 'utf8')).join('\n;\n');
const read = rel => fs.readFileSync(path.join(here, rel), 'utf8');
const safe = text => text.replace(/<\/script/gi, '<\\/script');

const CORE = ['shared/ios_frame.jsx', 'shared/data.jsx', 'shared/core.jsx', 'shared/skin-base.jsx'];
const INBOX = [...CORE, 'layouts/inbox.jsx'];
const PAGES = {
  'a-inbox': { title: 'A · 收件箱（游标）', jsx: [...INBOX, 'directions/instrument.jsx'], css: ['shared/base.css', 'shared/vernier-palette.css', 'directions/instrument.css'] },
  'b-dashboard': { title: 'B · 卡片仪表盘', jsx: [...CORE, 'layouts/dashboard.jsx'], css: ['shared/base.css', 'shared/vernier-palette.css', 'layouts/dashboard.css'] },
  'c-workbench': { title: 'C · 表格工作台', jsx: [...CORE, 'layouts/workbench.jsx'], css: ['shared/base.css', 'shared/vernier-palette.css', 'layouts/workbench.css'] },
  'style-ledger': { title: '风格稿 · 核簿', jsx: [...INBOX, 'directions/ledger.jsx'], css: ['shared/base.css', 'directions/ledger.css'] },
  'style-signal': { title: '风格稿 · 暗舱', jsx: [...INBOX, 'directions/signal.jsx'], css: ['shared/base.css', 'directions/signal.css'] },
};

// Main mode: every file in layouts/main, sorted (00-core first, v-* variants, zz-mount last).
const mainFiles = ext => fs.readdirSync(path.join(here, 'layouts/main')).filter(f => f.endsWith(ext)).sort().map(f => `layouts/main/${f}`);
const ALL_MAIN = {
  jsx: [...CORE, ...mainFiles('.jsx')],
  css: ['shared/base.css', 'shared/vernier-palette.css', 'directions/instrument.css', ...mainFiles('.css')],
};
// Variant files whose every option lost (DECISIONS.md). main.html leaves them out; round snapshots and isolated builds keep them.
const RETIRED = ['v-vis', 'v-detail', 'v-request', 'v-decided-r2'];
const retired = f => RETIRED.some(n => f === `layouts/main/${n}.jsx` || f === `layouts/main/${n}.css`);
PAGES.main = {
  title: '主模式 · 当前版本',
  jsx: ALL_MAIN.jsx.filter(f => !retired(f)),
  css: ALL_MAIN.css.filter(f => !retired(f)),
};

// Any layouts/<key>.jsx not used by PAGES becomes its own page: CORE + that file, Vernier palette, optional layouts/<key>.css.
// The page title comes from an `@title ...` line in the file's header comment.
const used = new Set(Object.values(PAGES).flatMap(p => p.jsx));
const discovered = fs.readdirSync(path.join(here, 'layouts'))
  .filter(f => f.endsWith('.jsx') && !used.has(`layouts/${f}`))
  .map(f => f.slice(0, -'.jsx'.length));

// Round snapshots: the variants a decision deck compares, frozen so later rounds' work-in-progress can't affect it.
const ROUND_SETS = {
  'main-r2': ['v-vis', 'v-today', 'v-accounts', 'v-detail', 'v-users', 'v-request'],
  // Round 3 sits on top of the round-2 decisions only (v-decided-r2), as the deck was shown.
  'main-r3': ['v-today', 'v-accounts', 'v-users', 'v-decided-r2', 'v-analytics', 'v-account-new', 'v-account-edit', 'v-groups', 'v-modules', 'v-user-edit'],
};

function pageFor(key) {
  if (PAGES[key]) return PAGES[key];
  if (ROUND_SETS[key]) return { ...pageFor(`main--${ROUND_SETS[key].join('+')}`), title: `主模式 · ${key}` };
  // main--<a>+<b>: main mode with only the listed layouts/main/v-* variants, so parallel variant work never breaks each other.
  const iso = key.match(/^main--(.+)$/);
  if (iso) {
    const names = iso[1].split('+');
    const only = f => !/^layouts\/main\/v-/.test(f) || names.some(n => f === `layouts/main/${n}.jsx` || f === `layouts/main/${n}.css`);
    return { title: `主模式 · ${iso[1]}`, jsx: ALL_MAIN.jsx.filter(only), css: ALL_MAIN.css.filter(only) };
  }
  const jsx = `layouts/${key}.jsx`;
  if (!fs.existsSync(path.join(here, jsx))) throw new Error(`unknown page ${key} (no ${jsx})`);
  const css = ['shared/base.css', 'shared/vernier-palette.css'];
  if (fs.existsSync(path.join(here, `layouts/${key}.css`))) css.push(`layouts/${key}.css`);
  const title = (read(jsx).match(/@title[ \t]+([^\n*]+)/) || [])[1];
  return { title: title ? title.trim() : key, jsx: [...CORE, jsx], css };
}

const fullBuild = process.argv.slice(2).length === 0;
const keys = fullBuild ? [...Object.keys(PAGES), ...discovered] : process.argv.slice(2);
const records = [];
for (const key of keys) {
  // key@alias builds the same page into <key@alias>.html, so parallel readers never race on one output file.
  const page = pageFor(key.split('@')[0]);
  const compiled = Babel.transform(page.jsx.map(read).join('\n;\n'), { presets: ['react'], comments: false }).code;
  const css = page.css.map(read).join('\n');
  const html = `<!doctype html><html lang="zh-CN"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><title>Sub2 Mobile · ${page.title}</title><style>${css}</style></head><body><div id="root"></div><script>${safe(runtime)}</script><script>${safe(compiled)}</script></body></html>`;
  const out = path.join(here, `${key}.html`);
  fs.writeFileSync(out, html);
  const bytes = fs.readFileSync(out);
  records.push({ key, title: page.title, file: `${key}.html`, bytes: bytes.length, sha256: crypto.createHash('sha256').update(bytes).digest('hex') });
}
// Only a full build rewrites the manifest, so parallel single-page builds never race on it.
if (fullBuild) {
  fs.writeFileSync(path.join(here, 'BUILD_MANIFEST.json'), JSON.stringify({ runtime: 'React/ReactDOM 18.3.1 UMD + @babel/standalone 7.26.9 (precompiled)', pages: records }, null, 2) + '\n');
}
console.log(records.map(r => `${r.file}  ${r.bytes} bytes`).join('\n'));
