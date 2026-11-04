// Build a decision deck: one page, several questions, each question shows its options side by side as live phones.
// Usage: node make_deck.cjs decks/<name>.json   → writes deck-<name>.html
const fs = require('fs');
const path = require('path');

const here = __dirname;
const specPath = path.resolve(here, process.argv[2]);
const spec = JSON.parse(fs.readFileSync(specPath, 'utf8'));
const name = path.basename(specPath, '.json');
const esc = s => String(s ?? '').replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/"/g, '&quot;');
const LETTERS = ['1', '2', '3', '4', '5'];

function src(opt) {
  const q = new URLSearchParams({ bare: '1', theme: '__THEME__', initial: JSON.stringify(opt.initial || {}) });
  return `${opt.page}.html?${q.toString()}`;
}

const nav = spec.questions.map((q, i) => `<a href="#q${i + 1}"><b>Q${i + 1}</b>${esc(q.short || q.title)}<i data-pick="q${i + 1}"></i></a>`).join('');
const sections = spec.questions.map((q, i) => {
  const id = `q${i + 1}`;
  const opts = q.options.map((o, j) => `
    <figure class="opt" data-q="${id}" data-o="${LETTERS[j]}">
      <figcaption>
        <div class="opt-head"><span class="opt-no">${LETTERS[j]}</span><b>${esc(o.title)}</b>${o.from ? `<span class="opt-from">${esc(o.from)}</span>` : ''}</div>
        ${o.points ? `<ul>${o.points.map(p => `<li>${esc(p)}</li>`).join('')}</ul>` : ''}
      </figcaption>
      <div class="phone"><iframe loading="lazy" title="${esc(q.title)} · 选项 ${LETTERS[j]}" data-src="${esc(src(o))}"></iframe></div>
      <div class="opt-foot"><button class="pick" data-q="${id}" data-o="${LETTERS[j]}" data-label="${esc(o.title)}">选这个</button><a target="_blank" data-href="${esc(src(o).replace('bare=1&', ''))}">单独打开</a></div>
    </figure>`).join('');
  return `
  <section class="q" id="${id}">
    <div class="q-head"><span class="q-no">Q${i + 1}</span><div><h2>${esc(q.title)}</h2><p>${esc(q.look)}</p></div></div>
    <div class="opts n${q.options.length}">${opts}</div>
  </section>`;
}).join('');

const html = `<!doctype html><html lang="zh-CN"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><title>Sub2 Mobile · ${esc(spec.title)}</title>
<style>
*{box-sizing:border-box} body{margin:0;background:#E4E8EA;color:#14181B;font-family:-apple-system,"SF Pro Text","PingFang SC","Microsoft YaHei UI","Segoe UI",sans-serif;-webkit-font-smoothing:antialiased}
body.dark{background:#050708;color:#E7EBED}
.top{position:sticky;top:0;z-index:10;background:rgba(228,232,234,.92);backdrop-filter:blur(14px);border-bottom:1px solid #C5CCD0;padding:10px 40px;display:flex;gap:18px;align-items:center;flex-wrap:wrap}
body.dark .top{background:rgba(5,7,8,.9);border-color:#2B3237}
.top h1{font-size:17px;margin:0;font-weight:650}
.qnav{display:flex;gap:6px;flex-wrap:wrap} .qnav a{font-size:13px;color:inherit;text-decoration:none;padding:5px 9px;border-radius:7px;border:1px solid #C5CCD0;display:inline-flex;gap:5px;align-items:center}
body.dark .qnav a{border-color:#2B3237} .qnav a b{color:#0B6E85} body.dark .qnav a b{color:#52CBE6}
.qnav i{font-style:normal;font-weight:700;color:#fff;background:#0B6E85;border-radius:5px;padding:0 5px;font-size:12px} .qnav i:empty{display:none}
.toggle{margin-left:auto;display:flex;border:1px solid #C5CCD0;border-radius:8px;padding:2px} body.dark .toggle{border-color:#2B3237}
.toggle button{font:inherit;font-size:13px;border:0;background:none;color:inherit;padding:5px 12px;border-radius:6px;cursor:pointer} .toggle button.on{background:#14181B;color:#fff} body.dark .toggle button.on{background:#E7EBED;color:#050708}
.intro{padding:28px 40px 4px;max-width:1100px} .intro p{margin:6px 0 0;line-height:1.7;font-size:15px;color:#2C3338} body.dark .intro p{color:#A8B1B7}
.q{padding:30px 40px 10px} .q-head{display:flex;gap:14px;align-items:flex-start;margin-bottom:16px;max-width:1100px}
.q-no{font-size:24px;font-weight:700;color:#0B6E85;line-height:1.2} body.dark .q-no{color:#52CBE6}
.q h2{margin:0;font-size:22px;font-weight:650} .q p{margin:4px 0 0;font-size:14.5px;line-height:1.6;color:#4A545A} body.dark .q p{color:#A8B1B7}
.opts{display:flex;gap:22px;align-items:flex-start;flex-wrap:wrap}
.opt{margin:0;width:316px;background:#fff;border:2px solid #D8DDE0;border-radius:16px;padding:12px;display:flex;flex-direction:column;gap:10px;transition:border-color .2s,box-shadow .2s}
body.dark .opt{background:#15191C;border-color:#2B3237}
.opt.picked{border-color:#0B6E85;box-shadow:0 0 0 4px rgba(11,110,133,.18)} body.dark .opt.picked{border-color:#52CBE6}
.opt-head{display:flex;gap:8px;align-items:center;flex-wrap:wrap} .opt-no{width:26px;height:26px;border-radius:7px;background:#14181B;color:#fff;display:inline-flex;align-items:center;justify-content:center;font-weight:700}
body.dark .opt-no{background:#E7EBED;color:#050708}
.opt-head b{font-size:16px} .opt-from{font-size:12px;color:#4A545A;border:1px solid #D8DDE0;border-radius:5px;padding:1px 6px} body.dark .opt-from{color:#A8B1B7;border-color:#2B3237}
.opt ul{margin:0;padding-left:18px;font-size:13px;line-height:1.6;color:#2C3338} body.dark .opt ul{color:#C6CED3}
.phone{width:292px;height:625px;overflow:hidden;border-radius:12px;align-self:center}
.phone iframe{width:409px;height:868px;border:0;transform:scale(.714);transform-origin:0 0;display:block;background:transparent}
.opt-foot{display:flex;gap:10px;align-items:center} .pick{font:inherit;font-size:14px;font-weight:600;border:0;border-radius:9px;padding:8px 14px;background:#EBEEF0;color:#14181B;cursor:pointer}
body.dark .pick{background:#1E2327;color:#E7EBED} .opt.picked .pick{background:#0B6E85;color:#fff}
.opt-foot a{font-size:13px;color:#0B6E85} body.dark .opt-foot a{color:#52CBE6}
.summary{margin:30px 40px 60px;padding:18px 20px;background:#fff;border:1px solid #C5CCD0;border-radius:14px;max-width:900px}
body.dark .summary{background:#15191C;border-color:#2B3237}
.summary h3{margin:0 0 8px;font-size:17px} .summary pre{margin:0;white-space:pre-wrap;font-size:14px;line-height:1.7;font-family:inherit}
.summary button{margin-top:12px;font:inherit;font-size:14px;font-weight:600;border:0;border-radius:9px;padding:8px 14px;background:#14181B;color:#fff;cursor:pointer}
</style></head><body>
<div class="top"><h1>${esc(spec.title)}</h1><nav class="qnav">${nav}</nav><div class="toggle"><button data-theme="light" class="on">浅色</button><button data-theme="dark">深色</button></div></div>
<div class="intro"><p>${esc(spec.intro)}</p></div>
${sections}
<div class="summary"><h3>你的选择</h3><pre id="sum">还没选。每题点「选这个」，也可以不选、直接在对话里说想法。</pre><button id="copy">复制选择</button></div>
<script>
const KEY = 'sub2-deck-${name}';
const picks = JSON.parse(localStorage.getItem(KEY) || '{}');
const titles = ${JSON.stringify(Object.fromEntries(spec.questions.map((q, i) => [`q${i + 1}`, q.short || q.title])))};
function render() {
  document.querySelectorAll('.opt').forEach(el => el.classList.toggle('picked', picks[el.dataset.q] && picks[el.dataset.q].o === el.dataset.o));
  document.querySelectorAll('[data-pick]').forEach(el => { el.textContent = picks[el.dataset.pick] ? picks[el.dataset.pick].o : ''; });
  const lines = Object.keys(titles).filter(k => picks[k]).map(k => titles[k] + '：选项 ' + picks[k].o + '（' + picks[k].label + '）');
  document.getElementById('sum').textContent = lines.length ? lines.join('\\n') : '还没选。每题点「选这个」，也可以不选、直接在对话里说想法。';
}
document.querySelectorAll('.pick').forEach(b => b.onclick = () => {
  const cur = picks[b.dataset.q];
  if (cur && cur.o === b.dataset.o) delete picks[b.dataset.q]; else picks[b.dataset.q] = { o: b.dataset.o, label: b.dataset.label };
  localStorage.setItem(KEY, JSON.stringify(picks)); render();
});
document.getElementById('copy').onclick = () => navigator.clipboard && navigator.clipboard.writeText(document.getElementById('sum').textContent);
function setTheme(t) {
  document.body.classList.toggle('dark', t === 'dark');
  document.querySelectorAll('.toggle button').forEach(b => b.classList.toggle('on', b.dataset.theme === t));
  document.querySelectorAll('iframe').forEach(f => { f.src = f.dataset.src.replace('__THEME__', t); });
  document.querySelectorAll('[data-href]').forEach(a => { a.href = a.dataset.href.replace('__THEME__', t); });
}
document.querySelectorAll('.toggle button').forEach(b => b.onclick = () => setTheme(b.dataset.theme));
setTheme(new URLSearchParams(location.search).get('theme') || 'light');
render();
</script></body></html>`;

const out = path.join(here, `deck-${name}.html`);
fs.writeFileSync(out, html);
console.log(`deck-${name}.html  ${spec.questions.length} questions, ${spec.questions.reduce((s, q) => s + q.options.length, 0)} options`);
