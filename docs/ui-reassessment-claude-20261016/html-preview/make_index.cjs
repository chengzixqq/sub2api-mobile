// Build index.html: the A / B / C layout comparison page. Usage: node make_index.cjs (after verify_previews.cjs produced screenshots)
const fs = require('fs');
const path = require('path');

const here = __dirname;
const img = name => `data:image/jpeg;base64,${fs.readFileSync(path.join(here, 'screenshots', name)).toString('base64')}`;
const esc = s => String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;');

const LAYOUTS = [
  { key: 'a-inbox', tag: 'A', name: '收件箱', like: '像 Linear 收件箱 / 值班工具', pitch: '打开就是“现在要处理什么”：逐个账号、原因、倒计时，可以直接测试或恢复。四个 Tab 对应四件高频事。', good: '半夜救火最快：0 次点击看到哪个账号坏了，1 次点击处置', cost: '早晚看概况时信息偏少；营收只占顶部一行' },
  { key: 'b-dashboard', tag: 'B', name: '卡片仪表盘', like: '像“健康”/“钱包”', pitch: '一面可以编辑的卡片墙：营收、账号健康环、渠道格、快捷充值各占一块，点卡片下钻。只有“摘要 / 浏览”两个 Tab。', good: '早晚扫一眼最舒服；充值有大键盘；最像 iOS 原生 App', cost: '密度最低，账号多时要多翻；没有好用的批量' },
  { key: 'c-workbench', tag: 'C', name: '表格工作台', like: '像“邮件”的邮箱列表 + 电子表格', pitch: '没有 Tab 栏：根页是一串“视图”（需处理账号、余额低用户、上游错误…），每个视图是一张可排序、可横滑、带合计的表；详情是检查器，可以上一条 / 下一条逐行处理。', good: '账号多、要精确对比和批量时最强；视图可以自己建', cost: '学习成本最高；小屏横滑；不够“一眼看懂”' },
];

const ROWS = [
  ['导航骨架', '底部 4 Tab（今日 · 账号 · 用户 · 监控）+ 搜索', '底部 2 Tab（摘要 · 浏览）+ 搜索', '无 Tab 栏：单一导航栈，根页是视图列表 + 底部工具栏'],
  ['站点切换', '标题下拉菜单', '右上角站点头像 → 站点面板', '根页顶部范围选择（主站 / 备用站 / 全部站点）'],
  ['首页', '待处理队列在前，营收压成一行', '卡片拼贴，可编辑（移除 / 添加）', '视图列表 + 计数，顶部 6 格指标'],
  ['账号列表', '满宽三行列表，按紧急程度分组', '状态磁贴筛选 + 需处理横向轮播 + 按平台两列磁贴', '表格：冻结名称列、横滑更多列、点表头排序、合计行'],
  ['账号详情', '状态卡（倒计时）+ 按钮行 + 分区', '通行证卡 + 控制中心式操作磁贴 + 环形容量', '检查器：状态条 + 属性表；上一条 / 下一条；工具栏操作'],
  ['批量操作', '中：选择模式 + 底部坞', '弱：没有勾选模式', '强：勾选列 + 工具栏批量'],
  ['日志入口', '搜索页目录 / 对象详情', '浏览目录 / 首页请求、错误率卡；先图表后列表', '根页三个视图直达；查询条件条 + 表格'],
  ['充值', '金额输入 + 快捷金额', '钱包卡 → 大数字键盘', '表单 + 算式账目（当前 ± 金额 = 调整后）'],
  ['渠道监控', '列表 + 时间条', '两列磁贴 + 可用率大数', '渠道 × 时间热力矩阵'],
  ['信息密度', '中（账号首屏 ≈ 6–7 个）', '低（账号首屏 ≈ 4 个磁贴）', '高（账号首屏 11 行）'],
  ['最适合', '救火优先', '早晚看概况、偶尔操作', '账号多、要对比、要批量'],
  ['iPad 延展', '侧栏 + 列表 + 详情三栏', '卡片墙天然铺开', '表格直接变宽，检查器做右栏'],
];

const cards = LAYOUTS.map(l => `
<article class="card">
  <a class="shot" href="${l.key}.html"><img alt="${l.tag} ${l.name} 预览" src="${img(`${l.key}-light-phones.jpg`)}"></a>
  <div class="meta">
    <div class="tag">${l.tag}<span>${esc(l.like)}</span></div>
    <h2>${esc(l.name)}</h2>
    <p>${esc(l.pitch)}</p>
    <dl><dt>强</dt><dd>${esc(l.good)}</dd><dt>弱</dt><dd>${esc(l.cost)}</dd></dl>
    <div class="links"><a class="primary" href="${l.key}.html">打开 6 屏交互</a><a href="${l.key}.html?theme=dark">深色</a></div>
  </div>
</article>`).join('');

const table = `<table><thead><tr><th></th>${LAYOUTS.map(l => `<th><b>${l.tag}</b> ${esc(l.name)}</th>`).join('')}</tr></thead><tbody>${ROWS.map(r => `<tr><th>${esc(r[0])}</th>${r.slice(1).map(c => `<td>${esc(c)}</td>`).join('')}</tr>`).join('')}</tbody></table>`;

const page = `<!doctype html><html lang="zh-CN"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><title>Sub2 Mobile · 三套布局对比（Claude）</title>
<style>
*{box-sizing:border-box} body{margin:0;background:#E4E8EA;color:#14181B;font-family:-apple-system,"SF Pro Text","PingFang SC","Microsoft YaHei UI","Segoe UI",sans-serif;-webkit-font-smoothing:antialiased}
header{padding:44px 48px 6px;max-width:1260px} .k{font-size:12px;color:#4A545A} h1{font-size:32px;margin:10px 0 10px;font-weight:650}
header p{margin:0;max-width:860px;line-height:1.7;font-size:15.5px;color:#2C3338}
.same{margin-top:14px;display:flex;flex-wrap:wrap;gap:8px} .same span{font-size:12.5px;padding:5px 10px;border-radius:6px;background:#fff;border:1px solid #C5CCD0;color:#3E474D}
main{padding:24px 48px 8px;display:grid;grid-template-columns:repeat(3,minmax(0,1fr));gap:22px;max-width:1520px}
.card{background:#fff;border-radius:14px;overflow:hidden;border:1px solid #C5CCD0;display:flex;flex-direction:column}
.shot{display:block;aspect-ratio:1440/900;overflow:hidden;background:#E4E8EA;border-bottom:1px solid #D8DDE0} .shot img{width:100%;height:100%;object-fit:cover;object-position:0 0;display:block;transition:transform .35s} .shot:hover img{transform:scale(1.015)}
.meta{padding:16px 20px 20px;display:flex;flex-direction:column;gap:8px;flex:1}
.tag{display:flex;align-items:center;gap:10px;font-weight:700;font-size:22px;color:#0B6E85} .tag span{font-size:12.5px;font-weight:500;color:#4A545A}
h2{margin:0;font-size:22px;font-weight:650} .meta p{margin:0;font-size:14.5px;line-height:1.65;color:#2C3338}
dl{margin:4px 0 0;display:grid;grid-template-columns:24px 1fr;gap:4px 8px;font-size:13.5px;line-height:1.6} dt{font-weight:700;color:#4A545A} dd{margin:0;color:#2C3338}
.links{margin-top:auto;padding-top:10px;display:flex;gap:14px;align-items:center} .links a{font-size:14px;color:#0B6E85}
.links a.primary{padding:9px 16px;border-radius:9px;background:#14181B;color:#fff;text-decoration:none;font-weight:600}
section{padding:22px 48px 8px;max-width:1520px} section h3{font-size:18px;margin:0 0 12px}
table{width:100%;border-collapse:collapse;background:#fff;border:1px solid #C5CCD0;border-radius:12px;overflow:hidden;font-size:13.5px;line-height:1.55}
thead th{background:#14181B;color:#fff;text-align:left;padding:10px 12px;font-weight:600} thead th b{color:#52CBE6;margin-right:4px}
tbody th{width:96px;text-align:left;padding:9px 12px;color:#4A545A;font-weight:600;background:#F1F3F4;vertical-align:top}
td{padding:9px 12px;vertical-align:top;border-left:1px solid #E1E5E8} tr+tr th,tr+tr td{border-top:1px solid #E1E5E8}
.note{padding:14px 48px 48px;max-width:1000px;font-size:12.5px;line-height:1.75;color:#4A545A}
.note a{color:#0B6E85}
@media (max-width:1100px){main{grid-template-columns:1fr}}
</style></head><body>
<header><div class="k">Sub2 Mobile 管理端 · 布局方案对比 · 演示数据 · 2026-10-16</div><h1>三套布局，同一套配色</h1>
<p>这一轮比较的是<b>布局和信息架构</b>：导航骨架、首页怎么组织、列表长什么样、详情怎么排、日志从哪进、充值怎么输。三套都用游标 Vernier 的黑白配色（浅色 / 深色），字体和形状各按自己的布局来。每个文件平铺 6 台可以点的 iPhone。</p>
<div class="same"><span>配色：游标 Vernier 石墨黑白 + 信号青</span><span>同一份演示数据</span><span>状态词与 Web 一致（错误 / 限流中 / 暂停 / 停用）</span><span>可逆操作直接执行 + 撤销</span><span>资金操作再确认，写明对象、站点、金额</span><span>日志不占 Tab</span></div></header>
<main>${cards}</main>
<section><h3>逐项对比</h3>${table}</section>
<p class="note">可以只选一套，也可以拼：例如“A 的首页 + C 的账号表格和检查器”，或“B 的摘要卡片墙 + A 的列表”。HTML 只用来比较结构；Liquid Glass 的真实效果、苹方 / SF 字体渲染、动态字号、手感以选定后的 SwiftUI 原型为准。上一轮的风格稿（只换皮、布局相同）保留在 <a href="style-ledger.html">核簿</a> 和 <a href="style-signal.html">暗舱</a>。</p>
</body></html>`;

fs.writeFileSync(path.join(here, 'index.html'), page);
console.log('index.html', Buffer.byteLength(page));
