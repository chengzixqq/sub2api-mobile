/* 统计分析 · 第 3 轮新页面（走查后修订；2026-10-18 评审：营收 → 计费、加利润明细、加 RPM / TPM 趋势）：计费趋势、利润明细、
   RPM / TPM 趋势、模型 / 用户 / 分组排行，以及 Web 仪表盘、使用记录、运维监控里的其余图表。
   注册的槽：
     screen:analytics       base「卡片流」| tabs「分段」| report「报表式」。route.focus = 'perf'：卡片流进入后直接滚到“RPM / TPM 趋势”卡
                            （首页 6 格点 RPM、TPM 用它）；可选 route.metric = 'rpm' | 'tpm'，进入时切到这个指标
     screen:analyticsMore   base「按主题分组的图表列表」| pager「单图全屏 + 左右切换」| catalog「图表目录网格」
     screen:analyticsChart  目录网格点进来的单图页（catalog 用；卡片流的“计费明细”“利润明细”也进这里）；route.chart
     screen:analyticsRank   全部排行（模型 / 用户 / 分组），三种结构共用；route.dim = 'model' | 'user' | 'group'
     screen:analyticsModel  模型对象页（排行里点模型进入）；route.model。“这个模型的使用记录”直接进 core 的 {kind:'logs', scope:'usage', model, group?}
   手机开关（initial.v）：axRange 'today' | '7d' | '30d' | 'custom'，axCustom 'month' | '14d' | 'lastMonth'，axOffset（往前步进几段），
     axSeg（分段变体当前段），axOpen（报表式默认展开的折叠区，逗号分隔），axFilter（'group:1' / 'model:claude-opus-4'），
     axOps=false（站点没开运维监控），axCardDim（卡片流排行卡当前维度）。
   入口：概览“更多统计”进来默认“今天”（接着首页“今日”区看）；搜索目录进来默认“近 7 天”。选过的范围、筛选、翻页在本机记住，二级页沿用；
     RPM / TPM 的窗口（近 1 / 6 / 24 小时）和指标也在本机记住，卡片和更多图表里的同一张图共用。
   数据来源（不虚构，演示数据按这些字段编）：
     计费趋势 ← admin/dashboard/trend（date、requests、input / output / cache_creation / cache_read_tokens、total_tokens、cost = 标准、actual_cost = 实际）。
       趋势点没有账号成本：图上只画实际与标准；账号成本、利润（profitOf = 实际 − 账号成本，不加“+”，亏损写“−”）的范围合计
       ← usage/stats 的 total_account_cost（或 dashboard/models 的 account_cost 求和）。今天的利润 = 首页 6 格的“利润”。
     利润明细（逐小时 / 逐日的 实际、账号成本、利润）← 每个时段一次 usage/stats?start_time=&end_time=（RFC3339，任意时段都接受）：
       total_actual_cost − total_account_cost。dashboard/trend 没有 account_cost，所以今天 10 次、近 7 天 7 次、近 30 天 30 次；
       建议后端给 dashboard/trend 的点加 account_cost，一次取回。演示数据逐段四舍五入到分、余数按最大余额分配，各段之和 = 合计
       （今天：实际 $1,284.50 − 账号成本 $512.08 = 利润 $772.42，与首页 6 格一致）。
     RPM / TPM 趋势 ← ops/dashboard/throughput-trend?start_time=&end_time=&mode=auto（与现有 App 的“性能指标”同一接口、同一口径）：
       点 = { bucket_start, request_count（成功 + 错误）, token_consumed（成功请求的 input + output + cache_creation + cache_read） }；
       桶长由后端按窗口定（pickThroughputBucketSeconds：≤ 2 小时 60 秒、≤ 24 小时 300 秒，更长 3600 秒）：近 1 小时 1 分钟一桶，近 6 / 24 小时
       5 分钟一桶；后端从 floor(start_time) 到 floor(end_time − 1ns) 逐桶补齐空桶（0）（ops_repo_trends.go fillOpsThroughputBuckets）。
       速率一律按桶实际覆盖的时长算，和桶长无关（1 分钟、5 分钟、1 小时的桶都一样）：
         每桶 RPM = request_count × 60 ÷ 覆盖秒数，TPM = token_consumed × 60 ÷ 覆盖秒数，覆盖秒数 = min(桶末, end_time) − max(桶首, start_time)。
       窗口是“现在 − N 小时 → 现在”，真实的现在带秒，所以首尾两桶通常都不满：09:41:23 请求近 1 小时，返回 08:41–09:41 共 61 个 1 分钟桶，
       首桶只覆盖 37 秒、末桶只覆盖 23 秒；近 6 小时 03:41:23 起的首桶只覆盖 3 分 37 秒。桶数、“只覆盖 N 秒”都按返回的点算，不要写死“60 桶”。
       现有 App 的 PerformanceTrend.rate 统一除以 bucket.seconds，首尾会骤降（近 1 小时的最新一桶只剩真实值的约 23/60，和首页 RPM 46 对不上），
       落地时 1 分钟桶也要改成按覆盖时长。另一种做法是请求时把 end_time 向下取整到整分钟、start_time = end_time − N 小时：近 1 小时就没有残桶，
       5 分钟桶的首尾仍按覆盖时长折算。演示时钟正好是 09:41:00，所以这里近 1 小时恰好 60 个整桶；近 6 / 24 小时首桶（03:41 / 昨天 09:41 起）
       只覆盖 4 分钟、末桶 09:40 只覆盖 1 分钟，按覆盖时长折算。
       最新一桶（09:40）= RPM 46 · TPM 240K，与首页 6 格对得上：首页取同一接口最近 5 个 1 分钟桶之和 ÷ 5（TPM 含缓存），
       09:36–09:40 五分钟 request_count 232（成功 230 + 错误 2）÷ 5 ≈ 46、token_consumed 1,200K ÷ 5 = 240K。dashboard/stats 的 tpm 不含缓存，用它就对不上。
       受运维监控开关控制；分组筛选传 group_id，按模型筛选时显示全站（同其他运行类图表）。前台每 30 秒刷新，离开页面停止。
     合计 ← usage/stats（任意范围：total_actual_cost、total_account_cost、total_cost、total_requests、total_tokens、average_duration_ms）。
     对比：含今天的范围和上一段的“同一时刻”比（同期），例如近 7 天 = 10/10 00:00–10/16 09:41 对 10/3 00:00–10/9 09:41；过去的整段和上一整段比；月按自然月。
     模型分布 ← dashboard/models（model_source = requested / upstream / mapping；requests、total_tokens、cost、actual_cost、account_cost）；
     分组使用分布 ← dashboard/groups（group_id、group_name、requests、total_tokens、cost、actual_cost、account_cost）；今天的数字就是 DEMO.groups 的
       usage.today / todayStats（groups/usage-summary 同一口径），所以“分组排行 → 分组详情”两边今日一致；
     用户排行 ← dashboard/users-ranking（limit 默认 12、最多 50；行里 user_id、email、username、actual_cost、requests、tokens；另给 total_actual_cost 等范围合计；
       没有账号成本，也不给“有用量的用户总数”，所以只写“前 N 位”，“其余”= total − 前 N 之和）；
       带 group_id 时按请求那一刻 Key 所属的分组（usage_logs.group_id）统计：一个用户的几个 Key 分属不同分组时，会出现在几个分组的排行里，各自只算那个分组的 Key；
     三个排行是同一批 usage_logs 的三个投影：演示数据用一个“用户 × 分组 × 模型”立方体（见下），筛选、排行、模型页、分组详情的数字互相对得上；
     模型对象页 ← dashboard/trend?model=、dashboard/user-breakdown?model=；速度 ← ops/dashboard/openai-token-stats（全部模型，只支持 30m / 1h / 1d / 15d / 30d 滚动窗口）；
     用户用量趋势 ← dashboard/users-trend（limit 12，metric = tokens | actual_cost）；端点分布 ← usage/stats 的 endpoints / upstream_endpoints；
     请求类型 ← usage/stats?request_type=（sync、stream、ws_v2、live、cyber 各取一次合计；Web 没有这张图，是拼出来的）；
     运行类图表要求站点开启运维监控（RequireMonitoringEnabled：配置文件 ops.enabled 是硬开关，再看系统设置 ops_monitoring_enabled；Web 设置页
       目前没有这个开关的界面，Web 运维页关闭时直接跳回设置页），关闭时整组换成“未开启”，不写 Web 菜单路径。
       原来的“吞吐趋势 · QPS / TPS”已并入上面的 RPM / TPM 趋势（同一个组件、同一套口径），不再单独出图；监控 · 概况里的 QPS（overview 的 qps）不变。
       其余运行类图表的点仍按后端的桶：一天以内（今天 / 昨天 / 某一天）按 5 分钟画，更长按小时画（switch_count 同样来自 throughput-trend）。
       平均账号切换 = switch_count / request_count；请求时长分布 ← ops/dashboard/latency-histogram（成功请求，0-100ms … 2000ms+）+ overview 的 duration / ttft 分位；
       错误趋势 ← ops/dashboard/error-trend（桶长同上：一天以内按小时合计 12 个 5 分钟桶，更长按天合计 24 个 1 小时桶，卡底写明）；错误率 = error_count_sla ÷ (成功 + error_count_sla)；
       错误分布 ← ops/dashboard/error-distribution（status_code、total、sla、business_limited）。状态码颜色一律走 codeTone：429 琥珀，其余失败（含 504、529）红，业务限制灰。
   筛选：trend / models / groups / users-ranking / users-trend / usage/stats 都接受 group_id、model（以及 user_id、account_id）；
     ops/dashboard/* 只接受 platform、group_id —— 按模型筛选时运行类图表显示全站并在卡头写明；按分组筛选时传 group_id，当前 / 峰值 / 平均 / 图一起变。
     筛选后的合计按字段分别等于排行里这一行（请求、Tokens、实际、成本、标准各用自己的比例），模型页直接用同一份数据。
   SwiftUI：范围 = Picker(.segmented)，自定义另给入口（日期说明行是 Button，打开 sheet；sheet 里开始、结束各一行，各自展开一个 DatePicker(.graphical)，
     一次只选一天、不画区间底色，和系统控件一致）；分类图的第三类横纹在 Swift Charts 里用 .foregroundStyle(ImagePaint) 或自绘，做不到就退回“描边 + 透明度”；
     分段 / 单图页的范围 = Menu（今天 / 近 7 天 / 近 30 天 + Button“自定义…”）；指标与模型口径 = Menu 内 Picker；
     图 = Swift Charts（BarMark + LineMark；卡片流 / 报表式用 .chartXSelection，单图翻页用 chartGesture + SpatialTapGesture 点选，不和翻页手势抢）；
     柱图和折线一样，整张图是一个点按 / 拖动区，按 x 坐标落到对应的桶（.chartXSelection），不按单根柱子做点按区——近 30 天的柱子只有约 10pt 宽；
     利润柱可以是负值（亏损）：BarMark 天然从 0 往下画，再加 RuleMark(y: 0) 零线，y 轴范围含 0；金额照常写“−$12.30”，柱子不换红色；
     整段都是 0（没有扣费）才显示空态，全部亏损不算空；
     排行 = List 行 + NavigationLink；报表式折叠区 = DisclosureGroup；单图全屏 = TabView(.page)；目录网格 = LazyVGrid。 */

/* ---------- calendar and daily series ---------- */

const AX_WEEK = ['周日', '周一', '周二', '周三', '周四', '周五', '周六'];
// The site went live on 7/17: the daily series covers every day since (the last entry is today, partial up to 09:41) and adds up to
// the groups' lifetime usage (Σ DEMO.groups usage.total), so a long custom range never exceeds 累计. Days before 7/17 have no data.
const AX_DAYS = 92;
const AX_LAST = AX_DAYS - 1;
const AX_LIFETIME = DEMO.groups.reduce((s, g) => s + g.usage.total, 0);
const AX_STD_RATIO = DEMO.today.standard / DEMO.today.actual;
const AX_COST_RATIO = DEMO.today.cost / DEMO.today.actual;
const AX_REQ_PER_USD = DEMO.today.requests / DEMO.today.actual;
const AX_TOK_PER_USD = DEMO.today.tokens / DEMO.today.actual;
const AX_TOKEN_MIX = [31.2, 6.8, 52.1, 6.3].map(v => v / 96.4); // input, output, cache read, cache write (sums to today's 96.4M)
const AX_TOKEN_KEYS = ['输入', '输出', '缓存读', '缓存写'];
// At most three greys plus an outline: dark, hatched, mid grey, outline. Adjacent stack segments differ by fill pattern and are split by a surface gap.
const AX_TOKEN_CLS = ['ax-k1', 'ax-k3', 'ax-k2', 'ax-k4'];
const AX_TODAY_SECONDS = (() => { const t = new Date(DEMO_CLOCK_BASE); return t.getHours() * 3600 + t.getMinutes() * 60; })(); // 00:00 → 09:41
const AX_YDAY_FULL = DEMO.hourlyYesterday.reduce((s, v) => s + v, 0);
const AX_SAME_TIME = yesterdaySameTime() / AX_YDAY_FULL; // share of a whole day done by 09:41

// Calendar positions are whole days from the demo's day (DEMO_TODAY, 10月16日 周五): axDay(offset) → that local date, axOff(date) → daysUntil.
const AX_YMD = DEMO_TODAY.split('-').map(Number);
function axDay(offset) { return new Date(AX_YMD[0], AX_YMD[1] - 1, AX_YMD[2] + offset); }
function axIso(d) { return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`; }
function axOff(date) { return daysUntil(axIso(date)); }
function axMD(d) { return `${d.getMonth() + 1}月${d.getDate()}日`; }
function axSlash(d) { return `${d.getMonth() + 1}/${d.getDate()}`; }
function axCompact(v) { return v === null || v === undefined ? '—' : fmt.compact(v < 1000 ? Math.round(v) : v); }

// Last seven days are fixed so the 7-day view reads well; yesterday equals DEMO.hourlyYesterday summed (= Σ groups usage.yesterday),
// today equals DEMO.today. Earlier days ramp up from the launch and are scaled so the whole series equals AX_LIFETIME.
const AX_DAILY = (() => {
  const last = [3412.6, 3288.4, 4105.7, 4236.9, 4318.2, AX_YDAY_FULL, DEMO.today.actual];
  const early = [];
  for (let i = 0; i < AX_DAYS - last.length; i++) {
    const back = AX_LAST - i;
    const dow = axDay(-back).getDay();
    const weekend = dow === 0 || dow === 6 ? 0.8 : 1;
    early.push((3980 - back * 18 + Math.sin(i * 1.7) * 160 + Math.cos(i * 0.6) * 90) * weekend);
  }
  const rest = AX_LIFETIME - last.reduce((s, v) => s + v, 0);
  const k = rest / early.reduce((s, v) => s + v, 0);
  const scaled = early.map(v => Math.round(v * k * 100) / 100);
  scaled[0] = Math.round((rest - scaled.slice(1).reduce((s, v) => s + v, 0)) * 100) / 100;
  return [...scaled, ...last];
})();

const axStdAt = i => (i === AX_LAST ? AX_STD_RATIO : AX_STD_RATIO + 0.012 * Math.cos(i));
const axCostAt = i => (i === AX_LAST ? AX_COST_RATIO : AX_COST_RATIO + 0.009 * Math.sin(i * 0.9));
const axReqAt = i => (i === AX_LAST ? AX_REQ_PER_USD : AX_REQ_PER_USD * (1 + 0.03 * Math.sin(i * 1.3)));
const axTokAt = i => (i === AX_LAST ? AX_TOK_PER_USD : AX_TOK_PER_USD * (1 + 0.04 * Math.cos(i * 0.7)));

function axBucket(label, short, tag, actual, idx, seconds, j) {
  const tokens = actual * axTokAt(idx);
  const shift = 0.035 * Math.sin(idx * 2.1 + j * 0.9);
  const mix = [AX_TOKEN_MIX[0] - shift, AX_TOKEN_MIX[1], AX_TOKEN_MIX[2] + shift, AX_TOKEN_MIX[3]].map(m => m * tokens);
  return { label, short, tag, actual, standard: actual * axStdAt(idx), cost: actual * axCostAt(idx), requests: Math.round(actual * axReqAt(idx)), tokens, mix, seconds, j, day: idx };
}

function axSum(buckets) {
  const t = { actual: 0, standard: 0, cost: 0, requests: 0, tokens: 0, mix: [0, 0, 0, 0] };
  buckets.forEach(b => { t.actual += b.actual; t.standard += b.standard; t.cost += b.cost; t.requests += b.requests; t.tokens += b.tokens; b.mix.forEach((m, k) => { t.mix[k] += m; }); });
  return t;
}

// One day's totals (frac < 1 = only up to 09:41). Today's entry is already partial.
function axDayTotals(idx, frac = 1) {
  if (idx < 0 || idx > AX_LAST) return null;
  const actual = AX_DAILY[idx] * frac;
  return { actual, standard: actual * axStdAt(idx), cost: actual * axCostAt(idx), requests: actual * axReqAt(idx), tokens: actual * axTokAt(idx) };
}

// Totals for days first..last; with `partial` the last day only counts up to 09:41 (same-period comparison).
function axSpan(first, last, partial) {
  if (first < 0) return null;
  const t = { actual: 0, standard: 0, cost: 0, requests: 0, tokens: 0 };
  for (let i = first; i <= last; i++) {
    const d = axDayTotals(i, partial && i === last && i !== AX_LAST ? AX_SAME_TIME : 1);
    Object.keys(t).forEach(k => { t[k] += d[k]; });
  }
  return t;
}

const AX_PRESETS = { month: '本月', '14d': '近 14 天', lastMonth: '上月' };
const AX_RANGE_LABEL = { today: '今天', '7d': '近 7 天', '30d': '近 30 天' };

function axPresetDates(k) {
  if (k === 'month') return { from: axOff(axMonthStart(0)), to: 0 };
  if (k === '14d') return { from: -13, to: 0 };
  return { from: axOff(axMonthStart(-1)), to: axOff(axMonthEnd(-1)) };
}
function axCustomLabel(sel) { return sel.custom === 'dates' ? `自选 ${sel.to - sel.from + 1} 天` : AX_PRESETS[sel.custom]; }

// One calendar day split by hour. Today stops at 09:41; earlier days reuse yesterday's shape scaled to that day's total.
function axHourRange(offset) {
  const idx = AX_LAST + offset;
  const d = axDay(offset);
  const live = offset === 0;
  const raw = live ? DEMO.hourlyToday : DEMO.hourlyYesterday.map(v => v * (AX_DAILY[idx] / AX_YDAY_FULL));
  const fix = live ? DEMO.today.actual - raw.reduce((s, v) => s + v, 0) : 0;
  const buckets = raw.map((v, h) => {
    const last = live && h === raw.length - 1;
    const tag = `${h}:00–${last ? '9:41' : `${h + 1}:00`}`;
    return axBucket(`${axMD(d)} ${tag}`, `${h}时`, tag, last ? v + fix : v, idx, last ? 41 * 60 : 3600, h);
  });
  const totals = live ? { ...axSum(buckets), actual: DEMO.today.actual, standard: DEMO.today.standard, cost: DEMO.today.cost, requests: DEMO.today.requests, tokens: DEMO.today.tokens } : axSum(buckets);
  return {
    ...totals, buckets, unit: 'hour', live, first: idx, last: idx,
    caption: live ? `${axMD(d)} ${AX_WEEK[d.getDay()]} · 00:00 至 09:41 · 按小时` : `${axMD(d)} ${AX_WEEK[d.getDay()]} · 按小时`,
    prev: live ? axDayTotals(idx - 1, AX_SAME_TIME) : axDayTotals(idx - 1),
    compare: live ? '比昨天同时' : '比前一天',
    seconds: live ? AX_TODAY_SECONDS : 86400,
    canPrev: idx - 2 >= 0,
  };
}

function axDaysRange(first, last) {
  const buckets = [];
  for (let i = first; i <= last; i++) {
    const d = axDay(i - AX_LAST);
    const label = `${axMD(d)} ${AX_WEEK[d.getDay()]}`;
    buckets.push(axBucket(label, axSlash(d), label, AX_DAILY[i], i, i === AX_LAST ? AX_TODAY_SECONDS : 86400, i - first));
  }
  const a = axDay(first - AX_LAST);
  const b = axDay(last - AX_LAST);
  const live = last === AX_LAST;
  return {
    ...axSum(buckets), buckets, unit: 'day', live, first, last,
    caption: `${axMD(a)} – ${a.getMonth() === b.getMonth() ? `${b.getDate()}日` : axMD(b)}${live ? '（今天到 09:41）' : ''} · 按天`,
    seconds: buckets.reduce((s, x) => s + x.seconds, 0),
  };
}

// Month m relative to the demo's month (0 = this month, −1 = last month); this month ends today.
function axMonthStart(m) { return new Date(AX_YMD[0], AX_YMD[1] - 1 + m, 1); }
function axMonthEnd(m) { return m === 0 ? axDay(0) : new Date(AX_YMD[0], AX_YMD[1] + m, 0); }
const axMonthName = d => `${d.getMonth() + 1} 月`;

// sel → one window (unfiltered). Months step by calendar month; everything else steps by its own length.
function axRangeBase(sel) {
  const off = sel.offset || 0;
  if (sel.key === 'today') {
    return { ...axHourRange(off), label: off === 0 ? '今天' : off === -1 ? '昨天' : axMD(axDay(off)) };
  }
  if (sel.key === 'custom' && (sel.custom === 'month' || sel.custom === 'lastMonth')) {
    const m = (sel.custom === 'lastMonth' ? -1 : 0) + off;
    const r = axDaysRange(AX_LAST + axOff(axMonthStart(m)), AX_LAST + axOff(axMonthEnd(m)));
    const pm = axMonthStart(m - 1);
    const pFirst = AX_LAST + axOff(pm);
    const pLastDay = r.live ? new Date(pm.getFullYear(), pm.getMonth(), Math.min(axDay(0).getDate(), axMonthEnd(m - 1).getDate())) : axMonthEnd(m - 1);
    return {
      ...r, prev: axSpan(pFirst, AX_LAST + axOff(pLastDay), r.live),
      compare: r.live ? '比上月同期' : `比 ${axMonthName(pm)}`,
      label: m === 0 ? '本月' : m === -1 ? '上月' : axMonthName(axMonthStart(m)),
      canPrev: pFirst >= 0,
    };
  }
  const dates = sel.key === 'custom' && sel.custom === 'dates';
  // A single chosen day reads like 今天 / 昨天: by hour, and the ops charts get the backend's 5-minute buckets (window ≤ 24 h).
  if (dates && sel.from === sel.to) {
    const day = sel.to + off;
    return { ...axHourRange(day), label: day === 0 ? '今天' : day === -1 ? '昨天' : axMD(axDay(day)) };
  }
  const days = sel.key === '7d' ? 7 : sel.key === '30d' ? 30 : dates ? sel.to - sel.from + 1 : 14;
  const last = AX_LAST + (dates ? sel.to : 0) + off * days;
  const first = last - days + 1;
  const r = axDaysRange(first, last);
  const name = sel.key === 'custom' ? (dates ? `自选 ${days} 天` : '近 14 天') : AX_RANGE_LABEL[sel.key];
  return {
    ...r, prev: axSpan(first - days, last - days, r.live),
    compare: r.live ? `比前 ${days} 天同期` : `比前 ${days} 天`,
    label: off === 0 ? name : off === -1 ? `上一个 ${days} 天` : `往前推 ${-off * days} 天`,
    canPrev: first - days >= 0,
  };
}

// sel = { key, custom, from, to, offset, filter } → everything a screen needs for that window. r.base = the same window without the filter.
function axRangeData(sel) {
  const offset = sel.offset || 0;
  const r0 = { ...axRangeBase(sel), key: sel.key, offset, canNext: offset < 0, filter: null };
  return sel.filter ? axFocus(r0, [sel.filter]) : { ...r0, base: r0 };
}

/* ---------- objects: one cube of user × group × model, so every ranking, filter and drill-down adds up ----------
   dashboard/models, dashboard/groups and users-ranking are three projections of the same usage_logs rows, and the group is the API key's
   group at request time (usage_logs.group_id). The demo keeps that cube:
   - groups: DEMO.groups usage.today for today (= groups/usage-summary, so 分组排行 → 分组详情 shows the same 今日), usage.yesterday's split for
     every earlier day; one platform per group;
   - models: a group spends on its platform's models in this table's shares (the platform totals equal the accounts' today in DEMO);
   - users: AX_USER_SPEND = today's spend by key group, read from DEMO.keys `today` (big customers #21–#26 included), so it agrees with
     the groups' key pages and users[].keys (Σ per group = usage.today, Σ per user = the user's today); earlier days keep each group's
     split of users; AX_PAST_ONLY names who spent in a group that is idle today.
   Field totals of a window (requests, Tokens, account cost, standard) come from the daily series; the cube only splits them. */

const AX_MODEL_PLATFORM = { claude: 'Anthropic', gpt: 'OpenAI', deepseek: 'DeepSeek', kimi: 'Kimi', glm: '智谱 GLM', gemini: 'Gemini' };
// dashboard/models today. Per platform the totals equal the accounts' today in DEMO (Anthropic 986.05, OpenAI 203.50 …), and
// standard = actual ÷ the serving group's rate (测试组 ×0.6 for gemini-2.5-pro: 10.80 → 18.00; every other group with usage today ×0.8).
const AX_MODELS = [
  { key: 'claude-sonnet-4-5', actual: 612.40, cost: 238.20, standard: 765.50, requests: 7420, tokens: 46.2e6, speed: [62.4, 1180, 6420] },
  { key: 'claude-opus-4', actual: 318.75, cost: 131.60, standard: 398.44, requests: 1210, tokens: 14.1e6, speed: [38.1, 2140, 18300] },
  { key: 'gpt-4.1', actual: 142.30, cost: 58.10, standard: 177.88, requests: 2380, tokens: 11.8e6, speed: [71.8, 820, 3900] },
  { key: 'gpt-4.1-mini', actual: 61.20, cost: 24.30, standard: 76.50, requests: 3120, tokens: 8.9e6, speed: [118.5, 410, 1620] },
  { key: 'claude-haiku-4-5', actual: 54.90, cost: 21.40, standard: 68.63, requests: 2140, tokens: 6.2e6, speed: [142.3, 360, 1100] },
  { key: 'deepseek-chat', actual: 38.60, cost: 14.10, standard: 48.25, requests: 980, tokens: 4.6e6, speed: [34.6, 1420, 5200] },
  { key: 'kimi-k2', actual: 27.15, cost: 11.20, standard: 33.94, requests: 512, tokens: 2.3e6, speed: [41.0, 1650, 6100] },
  { key: 'glm-4.6', actual: 18.40, cost: 8.38, standard: 23.00, requests: 290, tokens: 1.4e6, speed: [29.3, 2380, 9800] },
  { key: 'gemini-2.5-pro', actual: 10.80, cost: 4.80, standard: 18.00, requests: 152, tokens: 0.9e6, speed: [88.0, 3100, 7400] },
].map(m => ({ ...m, name: m.key, upstream: UPSTREAM_MODEL[m.key] || m.key, platform: AX_MODEL_PLATFORM[m.key.split('-')[0]] }));
const AX_MODEL_BY_KEY = Object.fromEntries(AX_MODELS.map(m => [m.key, m]));
const AX_PLATFORM_ACTUAL = AX_MODELS.reduce((o, m) => ({ ...o, [m.platform]: (o[m.platform] || 0) + m.actual }), {});

const axCents = v => Math.round(v * 100) / 100;

/* Today's spend by key group (user id → group name → actual) = users-ranking?group_id= for today: every user's DEMO.keys `today` summed
   by the key's group — the same numbers as the groups' key pages and users[].keys (王小明 = 高级组「默认」2.80 + GLM 组「脚本」0.44;
   陈思远 = 测试组 10.80 + 高级组 1.38 + 标准组 0.42; Pixel 工坊 = 标准组 45.13 + Kimi 组 25.85 + 高级组 20.31 + 默认组 6.37). DEMO.keys
   adds up to DEMO.groups usage.today per group and to the user's today per user, so nothing here fills a gap. */
const AX_USER_SPEND = DEMO.keys.reduce((out, k) => {
  const g = groupOf(k.groupId);
  if (!g || !(k.today > 0)) return out;
  const u = out[k.userId] || {};
  return { ...out, [k.userId]: { ...u, [g.name]: axCents((u[g.name] || 0) + k.today) } };
}, {});

// Groups idle today but busy yesterday (企业专线: its only account is in error): yesterday's spenders are the owners of the keys there
// last used 昨天, weighted by how many such keys they hold (Studio-K「预发」「企业网关」2 : 林一「订阅」1). group name → [[user id, weight]].
const AX_PAST_ONLY = Object.fromEntries(DEMO.groups
  .filter(g => !g.usage.today && g.usage.yesterday)
  .map(g => {
    const w = {};
    DEMO.keys.filter(k => k.groupId === g.id && /^昨天/.test(k.last)).forEach(k => { w[k.userId] = (w[k.userId] || 0) + 1; });
    return [g.name, Object.entries(w).map(([id, n]) => [Number(id), n])];
  })
  .filter(([, users]) => users.length));

// Who a ranking row is (name, email). Values are added by axRankItems. Users are DEMO.users (by id), the same records as the user tab.
function axObject(dim, key) {
  if (dim === 'group') { const g = groupOf(key); return { key, id: key, name: g ? g.name : String(key) }; }
  if (dim === 'model') { const m = AX_MODEL_BY_KEY[key]; return { key, name: key, upstream: m ? m.upstream : key, platform: m ? m.platform : null }; }
  const u = userOf(key) || { name: `#${key}`, email: '' };
  return { key, id: key, name: u.name, email: u.email };
}

const AX_FIELDS = ['actual', 'requests', 'tokens', 'cost', 'standard'];

// Raw cells per (user, group, model): today's values (…T) and an earlier day's (…P, yesterday's split). A group spends on its
// platform's models in the model table's shares; every field follows that model's own per-dollar ratio.
const AX_CELLS = (() => {
  const out = [];
  DEMO.groups.forEach(g => {
    const pAct = AX_PLATFORM_ACTUAL[g.platform];
    if (!pAct) return;
    const spend = Object.keys(AX_USER_SPEND).map(Number).filter(id => AX_USER_SPEND[id][g.name]).map(id => [id, AX_USER_SPEND[id][g.name]]);
    const past = AX_PAST_ONLY[g.name] || [];
    const users = spend.length ? spend : past.map(([id]) => [id, 0]);
    const todaySum = spend.reduce((s, x) => s + x[1], 0);
    const pastSum = past.reduce((s, x) => s + x[1], 0);
    users.forEach(([user, t], i) => {
      const p = g.usage.yesterday * (todaySum ? t / todaySum : past[i][1] / pastSum);
      AX_MODELS.filter(m => m.platform === g.platform).forEach(m => {
        const cell = { user, group: g.id, model: m.key, platform: g.platform };
        AX_FIELDS.forEach(f => { const per = m[f] / pAct; cell[`${f}T`] = t * per; cell[`${f}P`] = p * per; });
        out.push(cell);
      });
    });
  });
  return out;
})();
const AX_CELL_SUM = Object.fromEntries(['T', 'P'].map(part => [part, Object.fromEntries(AX_FIELDS.map(f => [f, AX_CELLS.reduce((s, c) => s + c[`${f}${part}`], 0)]))]));

// A window's totals split into today's part (when the window reaches today) and the earlier days' part.
function axParts(base) {
  const today = base.last === AX_LAST ? axDayTotals(AX_LAST) : null;
  return { today, past: Object.fromEntries(AX_FIELDS.map(f => [f, Math.max(0, base[f] - (today ? today[f] : 0))])) };
}

// Cells scaled to one window: each field adds up to the window's totals; today's and earlier days' parts stay apart.
function axWindowCells(base) {
  const { today, past } = axParts(base);
  const kT = Object.fromEntries(AX_FIELDS.map(f => [f, today && AX_CELL_SUM.T[f] ? today[f] / AX_CELL_SUM.T[f] : 0]));
  const kP = Object.fromEntries(AX_FIELDS.map(f => [f, AX_CELL_SUM.P[f] ? past[f] / AX_CELL_SUM.P[f] : 0]));
  return AX_CELLS.map(c => {
    const o = { user: c.user, group: c.group, model: c.model, platform: c.platform };
    AX_FIELDS.forEach(f => { o[f] = c[`${f}T`] * kT[f] + c[`${f}P`] * kP[f]; });
    return o;
  });
}

function axMatch(c, filters) { return filters.every(f => (f.kind === 'group' ? c.group === f.key : c.model === f.key)); }
function axFilters(r) { return r.filters || (r.filter ? [r.filter] : []); }
const axRatio = (a, b) => (b ? a / b : 0);
function axPer(a, b) { return b ? a / b : null; }

// Narrow an unfiltered window to a slice (a group, a model, or both). Today's bar shrinks by the slice's share of today and earlier
// bars by its share of an earlier day, so a group idle today shows an empty today bar; the comparison period shrinks the same way.
function axFocus(base, filters) {
  const cells = AX_CELLS.filter(c => axMatch(c, filters));
  const part = p => Object.fromEntries(AX_FIELDS.map(f => [f, axRatio(cells.reduce((s, c) => s + c[`${f}${p}`], 0), AX_CELL_SUM[p][f])]));
  const sT = part('T');
  const sP = part('P');
  const { today, past } = axParts(base);
  const scale = (x, s) => x && { ...x, ...Object.fromEntries(AX_FIELDS.map(f => [f, x[f] * s[f]])) };
  const buckets = base.buckets.map(b => {
    const s = b.day === AX_LAST ? sT : sP;
    return { ...scale(b, s), requests: Math.round(b.requests * s.requests), mix: b.mix.map(m => m * s.tokens) };
  });
  const totals = Object.fromEntries(AX_FIELDS.map(f => [f, (today ? today[f] * sT[f] : 0) + past[f] * sP[f]]));
  const last = filters[filters.length - 1];
  return {
    ...base, ...totals, buckets, base, filters,
    mix: [0, 1, 2, 3].map(k => buckets.reduce((s, b) => s + b.mix[k], 0)),
    prev: scale(base.prev, sP),
    filter: { ...last, name: axObject(last.kind, last.key).name, share: Object.fromEntries(AX_FIELDS.map(f => [f, axRatio(totals[f], base[f])])) },
  };
}

const AX_DIMS = {
  model: { title: '模型排行', full: '模型分布', unit: '个模型', short: '模型', icon: 'cube', mono: true, of: c => c.model },
  user: { title: '用户排行', full: '用户排行', unit: '位用户', short: '用户', icon: 'people', of: c => c.user },
  group: { title: '分组排行', full: '分组使用分布', unit: '个分组', short: '分组', icon: 'group', of: c => c.group },
};
const AX_METRICS = {
  actual: { label: '实际扣费', get: x => x.actual, show: v => fmt.money(v), axis: v => axShortMoney(v) },
  requests: { label: '请求', get: x => x.requests, show: v => fmt.grouped(Math.round(v)), axis: v => axCompact(v) },
  tokens: { label: 'Tokens', get: x => x.tokens, show: v => axCompact(v), axis: v => axCompact(v) },
};
const AX_SOURCES = [['requested', '请求模型'], ['upstream', '上游模型'], ['mapping', '映射（请求 → 上游）']];

// Rank one dimension inside a window and its filters: a projection of the cube, so rows add up to the window (or slice) totals.
function axRankItems(dim, r, metric = 'actual') {
  const filters = axFilters(r);
  const sums = new Map();
  axWindowCells(r.base || r).filter(c => axMatch(c, filters)).forEach(c => {
    const k = AX_DIMS[dim].of(c);
    const acc = sums.get(k) || Object.fromEntries(AX_FIELDS.map(f => [f, 0]));
    AX_FIELDS.forEach(f => { acc[f] += c[f]; });
    sums.set(k, acc);
  });
  const get = AX_METRICS[metric].get;
  const items = [...sums].map(([k, v]) => ({ ...axObject(dim, k), ...v })).filter(x => x.actual >= 0.005 || x.requests >= 0.5);
  const total = items.reduce((s, x) => s + get(x), 0);
  // users-ranking has no account cost or standard, so user rows do not carry them.
  return items
    .map(x => ({ ...x, requests: Math.round(x.requests), cost: dim === 'user' ? undefined : x.cost, standard: dim === 'user' ? undefined : x.standard, share: axRatio(get(x), total) }))
    .sort((a, b) => get(b) - get(a));
}

function axOpenItem(ctx, dim, it) {
  if (dim === 'user') {
    // Every ranked user is in DEMO.users (big customers #21–#26 included), so ctx.users already has the record.
    ctx.push({ kind: 'user', id: it.id });
  } else if (dim === 'group') {
    // The group page (v-groups) reads the same usage.today. A build without it falls back to that group's usage log.
    ctx.push(MV.slots['screen:group'] ? { kind: 'group', id: it.id } : { kind: 'logs', scope: 'usage', group: it.id });
  } else {
    ctx.push({ kind: 'analyticsModel', model: it.key });
  }
}

/* ---------- ops-side series (ops/dashboard/* take platform + group_id only) ----------
   Points follow the backend's buckets: one calendar day → 5-minute points, longer → hourly points. A point's rate = its requests ÷ the
   seconds it covers. Requests per hour follow the revenue series (DEMO.hourlyToday / hourlyYesterday); inside an hour a little texture. */

const AX_REQ_TYPES = [['流式', 13120], ['同步', 4310], ['WS', 612], ['安全策略', 162], ['Live', 0]];
// usage/stats endpoints / upstream_endpoints today, split by platform: [path, requests, actual]. Per platform the rows add up to that
// platform's models (Anthropic 10,770 · $986.05 …), so a group or model filter keeps only its platform's endpoints; Σ over platforms = the
// site's table (inbound /v1/messages 10,980 · $931.40, chat/completions 4,892 · $286.10, responses 2,180 · $56.20, generateContent 152 · $10.80;
// upstream /v1/messages 10,770, responses 3,862, chat/completions 3,420, generateContent 152). Some Claude clients come in through
// chat/completions, some GLM / Kimi clients through /v1/messages; OpenAI's gpt-4.1 runs upstream as /v1/responses.
const AX_ENDPOINT_SPLIT = {
  inbound: {
    Anthropic: [['/v1/messages', 10590, 917.10], ['/v1/chat/completions', 180, 68.95]],
    OpenAI: [['/v1/chat/completions', 3320, 147.30], ['/v1/responses', 2180, 56.20]],
    DeepSeek: [['/v1/chat/completions', 980, 38.60]],
    Kimi: [['/v1/messages', 270, 6.70], ['/v1/chat/completions', 242, 20.45]],
    '智谱 GLM': [['/v1/messages', 120, 7.60], ['/v1/chat/completions', 170, 10.80]],
    Gemini: [['/v1beta/models/*:generateContent', 152, 10.80]],
  },
  upstream: {
    Anthropic: [['/v1/messages', 10770, 986.05]],
    OpenAI: [['/v1/responses', 3862, 142.30], ['/v1/chat/completions', 1638, 61.20]],
    DeepSeek: [['/v1/chat/completions', 980, 38.60]],
    Kimi: [['/v1/chat/completions', 512, 27.15]],
    '智谱 GLM': [['/v1/chat/completions', 290, 18.40]],
    Gemini: [['/v1beta/models/*:generateContent', 152, 10.80]],
  },
};
const AX_PLATFORM_REQ = AX_MODELS.reduce((o, m) => ({ ...o, [m.platform]: (o[m.platform] || 0) + m.requests }), {});

// Endpoint rows for a window and its filters: each platform's share of the slice, spread over that platform's endpoints.
function axEndpointRows(r, side) {
  const plat = {};
  axWindowCells(r.base || r).filter(c => axMatch(c, axFilters(r))).forEach(c => {
    const p = plat[c.platform] || (plat[c.platform] = { requests: 0, actual: 0 });
    p.requests += c.requests;
    p.actual += c.actual;
  });
  const m = new Map();
  Object.entries(AX_ENDPOINT_SPLIT[side]).forEach(([p, rows]) => {
    const s = plat[p];
    if (!s) return;
    rows.forEach(([path, n, usd]) => {
      const acc = m.get(path) || { requests: 0, actual: 0 };
      acc.requests += s.requests * (n / AX_PLATFORM_REQ[p]);
      acc.actual += s.actual * (usd / AX_PLATFORM_ACTUAL[p]);
      m.set(path, acc);
    });
  });
  return [...m].map(([path, v]) => ({ path, ...v })).filter(x => x.requests >= 0.5).sort((a, b) => b.requests - a.requests);
}
const AX_LAT_BUCKETS = [['0-100ms', '<100ms', 0.018], ['100-200ms', '100–200', 0.031], ['200-500ms', '200–500', 0.064], ['500-1000ms', '0.5–1s', 0.118], ['1000-2000ms', '1–2s', 0.214], ['2000ms+', '≥2s', 0.555]];
const AX_PCTL = { duration: [2400, 9800, 15200, 41600, 4100, 182000], ttft: [1100, 2900, 4200, 8600, 1500, 31000] }; // p50 p90 p95 p99 avg max
// error-distribution today: [status_code, total, sla, business_limited]. 502 includes request 9000 (标准组, behind the firing alert).
const AX_ERR_CODES = [[429, 186, 120, 66], [529, 64, 64, 0], [400, 58, 58, 0], [504, 31, 31, 0], [401, 22, 22, 0], [403, 14, 0, 14], [502, 13, 13, 0], [500, 9, 9, 0]];
const AX_ERR_TODAY = AX_ERR_CODES.reduce((s, x) => s + x[1], 0); // error_count_total = 397
const AX_ERR_SLA_SHARE = AX_ERR_CODES.reduce((s, x) => s + x[2], 0) / AX_ERR_TODAY; // error_count_sla = 317
// error-trend splits error_count_total: upstream 429 · upstream 529 · other upstream (provider 502 / 504 / 500) · non-upstream SLA errors (400, 401) ·
// business-limited (the user's own balance, quota or rate limit). Colours: codeTone of the code, neutral for business-limited.
const AX_ERR_PARTS = [['上游 429', 120, 'ax-epart tone-caution'], ['上游 529', 64, 'ax-epart tone-critical'], ['其他上游', 53, 'ax-epart ax-epart-soft tone-critical'], ['非上游', 80, 'ax-epart ax-epart-faint tone-critical'], ['业务限制', 80, 'ax-ebiz']];

function axOpsOn(ctx) { return !(ctx.v && ctx.v.axOps === false); }

// Which data the ops charts can show for this filter: a model filter falls back to the whole site, a group filter passes group_id.
function axOpsScope(r) {
  if (r.filter && r.filter.kind === 'model') return { src: r.base, k: 1, siteWide: true };
  if (r.filter && r.filter.kind === 'group') return { src: r, k: r.filter.share.requests, siteWide: false };
  return { src: r, k: 1, siteWide: false };
}

function axShare(r) { return r.requests / DEMO.today.requests; }

// Integer split of `total` in proportion to `weights` (largest remainder), so the parts add up exactly. Also used for cents.
function axSplitInt(total, weights) {
  const s = weights.reduce((a, b) => a + b, 0);
  if (!(s > 0) || !(total > 0)) return weights.map(() => 0);
  const raw = weights.map(w => (total * w) / s);
  const out = raw.map(Math.floor);
  let left = Math.round(total) - out.reduce((a, b) => a + b, 0);
  raw.map((v, i) => [v - Math.floor(v), i]).sort((a, b) => b[0] - a[0]).forEach(([, i]) => { if (left > 0) { out[i] += 1; left -= 1; } });
  return out;
}

/* ---------- RPM / TPM: throughput-trend minute by minute, yesterday 00:00 → today 09:40 ----------
   Minute m counts from today 00:00 (yesterday is negative); the demo's now is 09:41:00, so the newest minute is 09:40. Each hour keeps its
   own successful requests and Tokens (axHourRange of today and yesterday = the billing series), spread over its minutes with the rate
   interpolated between neighbouring hours so hour edges do not step. 09:00–09:35 carries the morning peak (≈ 100 RPM around 09:17); the last
   five minutes are fixed so the home's 6 cells (these five buckets ÷ 5, errors and cache tokens included) give RPM 46 · TPM 240K and the 09:40 bucket reads the same
   (DEMO.today.rpm / tpm). Errors (request_count also counts them) run at today's error_count_total ÷ successes (≈ 2.2 %), 2 in the last 5 minutes. */
const AX_NOW_MIN = AX_TODAY_SECONDS / 60; // 581 = 09:41
const AX_PERF_BASE = 1440; // AX_PERF[m + AX_PERF_BASE] is minute m
const AX_PERF_TAIL = { req: [47, 45, 48, 44, 46], err: [0, 1, 0, 1, 0], tok: [246.1e3, 236.8e3, 251.3e3, 225.8e3, 240e3] };
const AX_ERR_PER_REQ = AX_ERR_TODAY / DEMO.today.requests;

const AX_PERF = (() => {
  const hours = [...axHourRange(-1).buckets, ...axHourRange(0).buckets]; // 24 + 10 hours, oldest first
  const perMin = hours.map(b => b.requests / (b.seconds / 60));
  const sum = xs => xs.reduce((a, b) => a + b, 0);
  const out = [];
  hours.forEach((b, i) => {
    const first = (i - 24) * 60;
    const live = b.seconds < 3600;
    const body = b.seconds / 60 - (live ? AX_PERF_TAIL.req.length : 0);
    const w = Array.from({ length: body }, (_, k) => {
      if (live) return (46 + 54 * Math.sin((Math.PI * (k + 3)) / 40)) * (1 + 0.12 * axNoise(first + k + 5));
      const f = (k + 0.5) / 60;
      const near = perMin[f < 0.5 ? Math.max(0, i - 1) : Math.min(hours.length - 1, i + 1)];
      return (perMin[i] + (near - perMin[i]) * Math.abs(f - 0.5)) * (1 + 0.3 * axNoise(first + k + 5));
    });
    const tail = live ? AX_PERF_TAIL : { req: [], err: [], tok: [] };
    const req = axSplitInt(b.requests - sum(tail.req), w);
    const tw = req.map((n, k) => n * (1 + 0.14 * axNoise(first + k + 23)));
    const tokLeft = b.tokens - sum(tail.tok);
    const twSum = sum(tw) || 1;
    req.forEach((n, k) => out.push({ req: n, err: Math.floor(n * AX_ERR_PER_REQ + axNoise(first + k + 41) + 0.5), tok: (tokLeft * tw[k]) / twSum }));
    tail.req.forEach((n, k) => out.push({ req: n, err: tail.err[k], tok: tail.tok[k] }));
  });
  return out;
})();

// Today 09:00–09:41 minute by minute (shares of that hour's successes): the same shape as the RPM / TPM series, so the 5-minute ops points agree.
const AX_LAST_HOUR = (() => {
  const w = AX_PERF.slice(AX_PERF_BASE + 540, AX_PERF_BASE + AX_NOW_MIN).map(x => x.req);
  const s = w.reduce((a, b) => a + b, 0);
  return w.map(x => x / s);
})();

// Deterministic noise in [-0.5, 0.5) for point g, so 5-minute and hourly series look like samples rather than sine waves.
function axNoise(g) { const x = Math.sin(g * 12.9898 + 78.233) * 43758.5453; return x - Math.floor(x) - 0.5; }

// g = a stable index of the point (day, hour, slot), used only for texture.
function axPoint(b, share, seconds, label, g, tick) {
  const requests = b.requests * share;
  const switchRate = requests > 0 ? 0.034 + 0.005 * Math.sin(g * 0.11) + 0.014 * axNoise(g + 7) : 0;
  return { label, tick, seconds, requests, switchRate };
}

// Shares that add up to 1, each base weight roughened by ±amp/2.
function axRough(base, amp, seed) {
  const w = base.map((v, i) => v * (1 + amp * axNoise(seed + i)));
  const s = w.reduce((a, x) => a + x, 0);
  return w.map(x => x / s);
}

// One calendar day in 5-minute points (288 for a whole day, 117 for today up to 09:41; the last one covers a single minute).
function axFiveMinute(src) {
  const pts = [];
  const hh = (h, k) => `${h}:${String(k * 5).padStart(2, '0')}`;
  src.buckets.forEach((b, h) => {
    if (b.seconds < 3600) {
      for (let k = 0; k * 5 < 41; k++) {
        const mins = AX_LAST_HOUR.slice(k * 5, k * 5 + 5);
        pts.push(axPoint(b, mins.reduce((a, x) => a + x, 0), mins.length * 60, hh(h, k), b.day * 288 + h * 12 + k));
      }
      return;
    }
    axRough(Array(12).fill(1), 0.3, b.day * 288 + h * 12).forEach((x, k) => pts.push(axPoint(b, x, 300, hh(h, k), b.day * 288 + h * 12 + k)));
  });
  return pts;
}

// Several days in hourly points; a day's requests split like that day's revenue by hour.
function axHourly(src) {
  const pts = [];
  src.buckets.forEach(b => {
    const live = b.day === AX_LAST;
    // Today keeps its own hours; earlier days follow yesterday's shape, roughened per day so no two days are identical.
    const shape = live ? axRough(DEMO.hourlyToday, 0, 0) : axRough(DEMO.hourlyYesterday, 0.18, b.day * 24);
    shape.forEach((v, h) => pts.push(axPoint(b, v, live && h === shape.length - 1 ? 41 * 60 : 3600, `${b.short} ${h}时`, b.day * 24 + h, h === 0 ? b.short : null)));
  });
  return pts;
}

// The window is exactly today (00:00–09:41): 今天, or a custom range of that one day.
function axIsToday(r) { return r.unit === 'hour' && r.live; }

function axOps(r) {
  const { src, k, siteWide } = axOpsScope(r);
  const fine = src.unit === 'hour';
  const today = axIsToday(src);
  // Today for the whole site (no filter, or a model filter, which ops ignores): the shared 今日 SLA figures (DEMO.today.errorsSla, errorRate('today')).
  const todaySite = today && k === 1;
  const points = fine ? axFiveMinute(src) : axHourly(src);
  // error-trend: summed per hour (one day) or per day (longer) — the chart foot says so.
  const raw = src.buckets.map((b, i) => {
    const spike = today && (i === 4 || i === 5) ? 0.022 : 0;
    return { ...b, errorsRaw: b.requests * (0.019 + 0.006 * Math.sin(i * 1.9 + src.buckets.length) + spike) };
  });
  const rawSum = raw.reduce((s, b) => s + b.errorsRaw, 0);
  const errors = today ? Math.round(AX_ERR_TODAY * k) : Math.round(rawSum);
  const buckets = raw.map(b => ({ ...b, errors: rawSum ? b.errorsRaw * (errors / rawSum) : 0 }));
  const sla = todaySite ? DEMO.today.errorsSla : Math.round(errors * AX_ERR_SLA_SHARE);
  return {
    points, fine, buckets, errors, sla, src, siteWide,
    errorRateText: todaySite ? errorRate('today') : axPct(axPer(sla, src.requests + sla)),
    switches: Math.round(points.reduce((s, p) => s + p.requests * p.switchRate, 0)),
  };
}

// Axis marks for the ops lines: every 3 or 6 hours on a day (plus 现在 on today), the start of every k-th day on longer ranges.
function axOpsTicks(o) {
  const n = o.points.length;
  if (o.fine) {
    const every = o.src.live ? 3 : 6;
    const marks = o.points.map((p, i) => i).filter(i => i % (12 * every) === 0).map(i => [i, `${i / 12}时`]);
    return o.src.live ? [...marks.filter(([i]) => i < n * 0.85), [n - 1, '现在']] : marks;
  }
  const days = o.points.map((p, i) => [i, p.tick]).filter(x => x[1]);
  const step = Math.ceil(days.length / 4);
  return days.filter((_, i) => (days.length - 1 - i) % step === 0);
}

function axGrain(o) { return o.fine ? '每 5 分钟一点' : '每小时一点'; }

/* ---------- RPM / TPM windows (rolling, ending now; independent of the page's range) ---------- */

const AX_PERF_RANGES = [{ hours: 1, label: '近 1 小时', bucket: 1 }, { hours: 6, label: '近 6 小时', bucket: 5 }, { hours: 24, label: '近 24 小时', bucket: 5 }];
const AX_PERF_METRICS = [{ key: 'rpm', label: 'RPM' }, { key: 'tpm', label: 'TPM' }];

function axMinLabel(m) {
  const d = ((m % 1440) + 1440) % 1440;
  return `${m < 0 ? '昨天 ' : ''}${String(Math.floor(d / 60)).padStart(2, '0')}:${String(d % 60).padStart(2, '0')}`;
}
// RPM: whole numbers from 10 up, one decimal below (a quiet group), 0 stays 0; TPM: compact (240K).
function axPerfFmt(metric, v) {
  if (metric === 'tpm') return axCompact(v);
  if (v === null || v === undefined || !isFinite(v)) return '—';
  return v >= 10 ? v.toFixed(0) : String(Math.round(v * 10) / 10);
}

// A group filter passes group_id: today's minutes shrink by the group's share of today, yesterday's by its share of an earlier day.
// A model filter is not supported by ops endpoints, so the series stays site-wide (AxOpsNote says so).
function axPerfShare(r) {
  const one = { req: 1, tok: 1 };
  if (!(r && r.filter && r.filter.kind === 'group')) return { T: one, P: one };
  const cells = AX_CELLS.filter(c => c.group === r.filter.key);
  const part = p => ({ req: axRatio(cells.reduce((s, c) => s + c[`requests${p}`], 0), AX_CELL_SUM[p].requests), tok: axRatio(cells.reduce((s, c) => s + c[`tokens${p}`], 0), AX_CELL_SUM[p].tokens) });
  return { T: part('T'), P: part('P') };
}

// One window as throughput-trend returns it: buckets from floor(now − N h) to the bucket holding 09:40, each with the minutes it actually covers.
function axPerfSeries(hours, r) {
  const range = AX_PERF_RANGES.find(x => x.hours === hours) || AX_PERF_RANGES[0];
  const B = range.bucket;
  const start = AX_NOW_MIN - hours * 60;
  const share = axPerfShare(r);
  const points = [];
  for (let s = Math.floor(start / B) * B; s < AX_NOW_MIN; s += B) {
    let count = 0;
    let tokens = 0;
    let covered = 0;
    for (let m = Math.max(s, start); m < Math.min(s + B, AX_NOW_MIN); m++) {
      const x = AX_PERF[m + AX_PERF_BASE];
      const k = m < 0 ? share.P : share.T;
      count += (x.req + x.err) * k.req;
      tokens += x.tok * k.tok;
      covered += 1;
    }
    points.push({ m: s, label: axMinLabel(s), covered, partial: covered < B, count, tokens, rpm: count / covered, tpm: tokens / covered });
  }
  const total = points.reduce((a, x) => ({ count: a.count + x.count, tokens: a.tokens + x.tokens }), { count: 0, tokens: 0 });
  const every = { 1: 15, 6: 120, 24: 360 }[hours];
  return {
    range, points,
    peak: { rpm: Math.max(...points.map(x => x.rpm)), tpm: Math.max(...points.map(x => x.tpm)) },
    avg: { rpm: total.count / (hours * 60), tpm: total.tokens / (hours * 60) },
    ticks: points.map((x, i) => [i, x]).filter(([, x]) => x.m % every === 0).map(([i, x]) => [i, axMinLabel(x.m).replace('昨天 ', '')]),
    from: axMinLabel(start), bucketLabel: B === 1 ? '1 分钟' : '5 分钟',
  };
}

// openai-token-stats (all models, despite the name) only takes time_range = 30m | 1h | 1d | 15d | 30d, each ending now: pick the
// smallest window that reaches back to the range's first day 00:00 (k days before today + 09:41). 30m / 1h never cover a whole day.
const AX_SPEED_WINDOWS = [[1, '近 1 天'], [15, '近 15 天'], [30, '近 30 天']];
function axSpeedFit(r) {
  const back = AX_LAST - r.first + AX_TODAY_SECONDS / 86400;
  const fit = AX_SPEED_WINDOWS.find(([d]) => d >= back);
  return { label: (fit || AX_SPEED_WINDOWS[AX_SPEED_WINDOWS.length - 1])[1], covers: !!fit };
}
function axSpeedWindow(r) { return axSpeedFit(r).label; }
function axSpeedNote(r) {
  const f = axSpeedFit(r);
  return f.covers
    ? `统计窗口${f.label}，截至现在：后端只有 30 分钟、1 小时、1 天、15 天、30 天这几种滚动窗口，这里取能盖住所选范围的最小一个。`
    : `统计窗口${f.label}，截至现在：后端最长只到 30 天，盖不住所选范围，这里只是最近 30 天的速度。`;
}

/* ---------- formatting ---------- */

const axPct = (v, digits = 1) => (v === null || v === undefined || !isFinite(v) ? '—' : `${(v * 100).toFixed(digits)}%`);
// Axis money: $1.2K, $40; a loss reads −$40 (the same minus sign as fmt.money).
function axShortMoney(v) {
  if (v < 0) return `−${axShortMoney(-v)}`;
  return v >= 1000 ? `$${(v / 1000).toFixed(v >= 10000 ? 0 : 1).replace(/\.0$/, '')}K` : `$${Math.round(v)}`;
}
function axMs(ms) { return ms === null || ms === undefined ? '—' : ms >= 1000 ? `${(ms / 1000).toFixed(ms >= 10000 ? 0 : 1)}s` : `${Math.round(ms)}ms`; }

/* ---------- per-phone memory: range, filter, open folds survive a drill-down and the way back ---------- */

const AX_MEMO = new WeakMap();

function useAxMemo(ctx, key, initial) {
  const [, rerender] = useState(0);
  const anchor = ctx.confirm; // the phone's own useState setter: stable for the phone's lifetime
  const read = () => {
    const box = AX_MEMO.get(anchor) || {};
    return key in box ? box[key] : initial;
  };
  const write = next => {
    const value = typeof next === 'function' ? next(read()) : next;
    AX_MEMO.set(anchor, { ...(AX_MEMO.get(anchor) || {}), [key]: value });
    rerender(n => n + 1);
  };
  return [read(), write];
}

function axFilterFrom(code) {
  if (!code) return null;
  const [kind, raw] = code.split(':');
  const key = kind === 'group' ? Number(raw) : raw;
  if (kind === 'group' ? !groupOf(key) : !AX_MODEL_BY_KEY[key]) return null;
  return { kind, key, name: axObject(kind, key).name };
}

function useAxRange(ctx, route) {
  const v = ctx.v || {};
  const custom = v.axCustom || 'month';
  const initial = { key: v.axRange || (route && route.range) || (ctx.tab === 'today' ? 'today' : '7d'), custom, ...axPresetDates(custom === 'dates' ? 'month' : custom), offset: v.axOffset || 0, filter: axFilterFrom(v.axFilter) };
  const [sel, setSel] = useAxMemo(ctx, 'sel', initial);
  return [axRangeData(sel), sel, patch => setSel(s => ({ ...s, ...patch }))];
}

/* ---------- small pieces ---------- */

// A change from or to a loss (利润 ≤ 0 on either side) has no meaningful percentage: with fmtAbs it shows the amount instead
// (↑ $86.20 · 比昨天同时), without it a dash.
function AxDelta({ cur, prev, label, fmtAbs }) {
  const none = <span className="ax-delta">{label} —</span>;
  if (prev === null || prev === undefined || (!prev && !cur)) return none;
  const cross = prev <= 0 || cur < 0;
  if (cross && !fmtAbs) return none;
  const d = cross ? cur - prev : (cur / prev - 1) * 100;
  return (
    <span className="ax-delta">
      <span className={cx('ax-arrow', d < 0 && 'down')}><Icon name="up" size={12} weight={2.6} /></span>
      <span className="num">{cross ? fmtAbs(Math.abs(d)) : `${Math.abs(d).toFixed(1)}%`}</span><span>· {label}</span>
    </span>
  );
}

// Legend keys follow the chart: actual = grey bar, standard = dotted line. Account cost has no line on the chart, so no key.
function AxKey({ kind }) { return kind ? <i className={cx('ax-key', `ax-key-${kind}`)} /> : null; }

function AxLegend({ items }) {
  return (
    <span className="ax-legend">
      {items.map(([kind, label]) => <span key={label} className="ax-legend-item"><AxKey kind={kind} />{label}</span>)}
    </span>
  );
}
const AX_REV_LEGEND = [['bar', '实际'], ['std', '标准（点线）']];

function AxTrack({ share, tone }) {
  return <span className={cx('ax-track', tone)}><i style={{ width: `${Math.max(0.6, Math.min(1, share) * 100)}%` }} /></span>;
}

function AxBases({ ctx, r }) {
  const { skin } = ctx;
  return (
    <div className="grid3 pad ax-bases">
      <div><small>账号成本</small><skin.Money value={r.cost} size="l" /></div>
      <div><small><AxKey kind="std" />标准</small><skin.Money value={r.standard} size="l" /></div>
      <div><small>利润</small><skin.Money value={profitOf(r)} size="l" /></div>
    </div>
  );
}

function AxFilterChip({ filter, onClear }) {
  return (
    <button className="chip on token ax-filter-chip" onClick={onClear} aria-label="清除筛选">
      <span>{filter.kind === 'group' ? '分组' : '模型'}：{filter.name}</span><Icon name="close" size={12} weight={2.8} />
    </button>
  );
}

// Shown instead of a ranking whose dimension is the active filter (one row "100%" carries no information).
function AxSameFilter({ filter, onClear }) {
  return (
    <div className="ax-same pad">
      <span className="ax-same-text">已筛选{filter.kind === 'group' ? '分组' : '模型'}：<b className={cx(filter.kind === 'model' && 'mono')}>{filter.name}</b></span>
      <button className="ax-same-clear" onClick={onClear}>清除筛选</button>
    </div>
  );
}

function AxOpsNote({ r }) {
  if (!axOpsScope(r).siteWide) return null;
  return <div className="ax-ops-note pad"><Icon name="filter" size={14} weight={2.2} /><span>运行类图表不支持按模型筛选，这里显示全站</span></div>;
}

const AX_OPS_OFF_TEXT = '这个站点关闭了运维监控，RPM / TPM、时长、错误等 6 张图没有数据。开关在服务器端（配置文件与系统设置），手机端不能打开。';

function AxOpsOff({ text = AX_OPS_OFF_TEXT }) {
  return (
    <div className="ax-opsoff">
      <span className="ax-opsoff-icon"><Icon name="pulse" size={18} weight={2.2} /></span>
      <div className="ax-opsoff-text"><b>运维监控未开启</b><span>{text}</span></div>
    </div>
  );
}

// Small calendar glyph for the "date caption" button (Icon has no calendar).
function AxCalGlyph() {
  return (
    <svg className="ax-cal-glyph" width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.1" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
      <rect x="3.5" y="5" width="17" height="15.5" rx="2.5" /><path d="M3.5 10h17M8 3v4M16 3v4" />
    </svg>
  );
}

/* ---------- charts (SVG on a 100-wide viewBox stretched to the card; axis and value labels are HTML) ---------- */

let AX_PID = 0;
function useAxPatternId() { return React.useMemo(() => `axh${++AX_PID}`, []); }

// Horizontal stripes survive the horizontal stretch of the 100-wide viewBox; one pattern per chart so each phone keeps its own theme colours.
function AxHatchDef({ id }) {
  return (
    <defs>
      <pattern id={id} patternUnits="userSpaceOnUse" width="6" height="3">
        <rect className="ax-hatch-bg" width="6" height="3" /><rect className="ax-hatch-ln" width="6" height="1.4" />
      </pattern>
    </defs>
  );
}

// Grid values inside (min, max), zero excluded (the zero line is drawn on its own). min < 0 only for profit with a loss.
function axTicks(max, min = 0) {
  const raw = (max - min) / 3;
  const p = Math.pow(10, Math.floor(Math.log10(raw || 1)));
  const step = [1, 2, 2.5, 5, 10].map(m => m * p).find(s => s >= raw);
  const out = [];
  for (let v = step; v < max * 0.98; v += step) out.push(v);
  for (let v = -step; v > min * 0.98; v -= step) out.push(v);
  return out;
}

function axTickIdx(n, anchorLast) {
  const step = n <= 8 ? 1 : n <= 12 ? 3 : n <= 24 ? 6 : 7;
  return Array.from({ length: n }, (_, i) => i).filter(i => (anchorLast ? (n - 1 - i) % step === 0 : i % step === 0));
}

function axPath(values, max, h, min = 0) {
  const n = values.length;
  const span = max - min || 1;
  return values.map((v, i) => `${i ? 'L' : 'M'}${(((i + 0.5) / n) * 100).toFixed(2)},${(h - ((v - min) / span) * h).toFixed(2)}`).join(' ');
}

// kind: 'bars' (values) | 'stack' (stacks + classes) | 'line' (values, optional area). `line` = dotted overlay (标准).
// ticks = [[index, text], …] replaces the automatic axis marks (the ops lines have hundreds of points).
// nowLast marks the last slot as the one still running (darker bar, axis label nowText: 现在 for an hour, 今天 for a day).
// Bars may go below zero (利润 with a loss): the y range always holds 0, bars grow from the zero line up or down and the zero line is
// the strong rule (Swift Charts: BarMark + RuleMark(y: 0)). Empty means every value is 0; a window that is all loss is still data.
function AxChart({ kind = 'bars', values, stacks, classes, line, labels, h = 120, fmtY, pick, onPick, nowLast, nowText = '现在', anchorLast, area, ticks, emptyText = '这个范围内没有用量' }) {
  const pid = useAxPatternId();
  const n = labels.length;
  const totals = kind === 'stack' ? stacks.map(s => s.reduce((a, b) => a + b, 0)) : values;
  const hi = Math.max(0, ...totals, ...(line || [0]));
  const lo = kind === 'bars' ? Math.min(0, ...totals) : 0;
  // Nothing at all in the window (a group idle today): keep the axis, drop the scale, say so — Swift Charts would show the same overlay.
  const empty = !(hi > 0 || lo < 0);
  const max = empty ? 1 : hi * 1.1;
  const min = lo * 1.1;
  const span = max - min || 1;
  const grid = empty ? [] : axTicks(max, min);
  const y = v => h - ((v - min) / span) * h;
  const zero = lo < 0 ? y(0) : h - 0.5;
  const slot = 100 / n;
  const gap = slot * (n > 20 ? 0.2 : 0.28);
  const marks = ticks || axTickIdx(n, anchorLast).map(i => [i, nowLast && i === n - 1 ? nowText : labels[i]]);
  const picked = pick !== null && pick !== undefined;
  // A picked point on a line (RPM / TPM): a rule through it and a dot on the line (HTML, so the stretched viewBox does not squash it).
  const lineMark = kind === 'line' && !empty && picked ? { x: ((pick + 0.5) / n) * 100, y: (1 - (values[pick] - min) / span) * 100 } : null;
  // One bar from `from` to `to` (either side of zero); stacked segments above the first leave a surface gap of `inset`.
  const rect = (key, i, from, to, cls, inset) => {
    const a = y(to);
    const b = y(from);
    return <rect key={key} className={cls} style={cls && cls.startsWith('ax-k3') ? { fill: `url(#${pid})` } : undefined} x={i * slot + gap / 2} width={slot - gap} y={Math.min(a, b)} height={Math.max(0, Math.abs(b - a) - inset)} />;
  };
  // The whole plot is one target, as .chartXSelection: the tap's x picks the slot, tapping the picked slot again clears it. One button
  // per bar would be far under 44 pt (30 days ≈ 10 pt each, a line has up to 289 points). Keyboard: ←/→ step, Enter picks the newest / clears.
  const pickAt = e => {
    if (e.detail === 0) { onPick(picked ? null : n - 1); return; }
    const b = e.currentTarget.getBoundingClientRect();
    const i = Math.max(0, Math.min(n - 1, Math.floor(((e.clientX - b.left) / b.width) * n)));
    onPick(pick === i ? null : i);
  };
  const stepKey = e => {
    if (e.key !== 'ArrowLeft' && e.key !== 'ArrowRight') return;
    e.preventDefault();
    const d = e.key === 'ArrowRight' ? 1 : -1;
    onPick(Math.max(0, Math.min(n - 1, (picked ? pick : d > 0 ? -1 : n) + d)));
  };
  return (
    <div className="ax-chart">
      <div className="ax-plot-row">
        <div className="ax-plot" style={{ height: h }}>
          <svg className="ax-svg" viewBox={`0 0 100 ${h}`} preserveAspectRatio="none" aria-hidden="true">
            {kind === 'stack' && <AxHatchDef id={pid} />}
            {grid.map(g => <line key={g} className="ax-grid" x1="0" x2="100" y1={y(g)} y2={y(g)} />)}
            {kind === 'bars' && values.map((v, i) => rect(i, i, 0, v, cx('ax-bar', (picked ? pick === i : nowLast && i === n - 1) && 'on'), 0))}
            {kind === 'stack' && stacks.map((s, i) => {
              let acc = 0;
              return s.map((v, k) => { const el = rect(`${i}-${k}`, i, acc, acc + v, cx(classes[k], picked && pick !== i && 'dimmed'), k > 0 ? 1.5 : 0); acc += v; return el; });
            })}
            {kind === 'line' && area && <path className="ax-area" d={`${axPath(values, max, h, min)} L${(((n - 0.5) / n) * 100).toFixed(2)},${y(0)} L${((0.5 / n) * 100).toFixed(2)},${y(0)} Z`} />}
            {kind === 'line' && <path className="ax-line" d={axPath(values, max, h, min)} />}
            {line && <path className="ax-std" d={axPath(line, max, h, min)} />}
            {lineMark && <line className="ax-pick-rule" x1={lineMark.x} x2={lineMark.x} y1="0" y2={h} />}
            <line className="ax-base" x1="0" x2="100" y1={zero} y2={zero} />
          </svg>
          {lineMark && <i className="ax-pick-dot" style={{ left: `${lineMark.x}%`, top: `${lineMark.y}%` }} />}
          {empty && <div className="ax-plot-empty">{emptyText}</div>}
          {onPick && !empty && (
            <button className={cx('ax-hit', kind === 'line' && 'ax-hit-line')} aria-label={picked ? `已选 ${labels[pick]}` : kind === 'line' ? '点按图上的时间' : '点按图上的时段'} onClick={pickAt} onKeyDown={stepKey}>
              {/* Slots are only the hover guide (and where a route taps a given bar); the button is the one target. */}
              {kind !== 'line' && labels.map((l, i) => <i key={i} className={cx('ax-slot', pick === i && 'on')} />)}
            </button>
          )}
        </div>
        <div className="ax-gutter" style={{ height: h }}>
          {(lo < 0 ? [...grid, 0] : grid).map(g => <span key={g} className="num" style={{ top: `${(1 - (g - min) / span) * 100}%` }}>{fmtY(g)}</span>)}
        </div>
      </div>
      <div className="ax-axis">
        {marks.map(([i, text]) => (
          <span key={i} className={cx(nowLast && i === n - 1 && 'ax-axis-now')} style={{ left: `${((i + 0.5) / n) * 100}%` }}>{text}</span>
        ))}
      </div>
    </div>
  );
}

function AxTrend({ r, pick, onPick, h = 120, metric = 'actual' }) {
  const m = AX_METRICS[metric];
  return (
    <AxChart values={r.buckets.map(m.get)} line={metric === 'actual' ? r.buckets.map(b => b.standard) : null} labels={r.buckets.map(b => b.short)}
      h={h} fmtY={m.axis} pick={pick} onPick={onPick} {...axNowProps(r)} anchorLast={r.unit === 'day'} />
  );
}

// A window that reaches now: its last bar is still filling (the current hour, or today up to 09:41).
function axNowProps(r) { return { nowLast: r.live, nowText: r.unit === 'hour' ? '现在' : '今天' }; }

// The line under the big number when a bar is selected: follows the metric on show.
function axPickLine(b, metric, withTag = true) {
  const tag = withTag ? `${b.tag} · ` : '';
  if (metric === 'requests') return <span>{tag}实际 <b className="num">{fmt.money(b.actual)}</b> · Tokens <b className="num">{axCompact(b.tokens)}</b></span>;
  if (metric === 'tokens') return <span>{tag}输入 <b className="num">{axCompact(b.mix[0])}</b> · 缓存读 <b className="num">{axCompact(b.mix[2])}</b></span>;
  return <span>{tag}标准 <b className="num">{fmt.money(b.standard)}</b> · 请求 <b className="num">{fmt.grouped(b.requests)}</b></span>;
}

/* ---------- menus, range controls, custom range and filter sheets ---------- */

// A chip that opens a popover menu (SwiftUI Menu). sections = [{ id, title, items: [{ key, label, on, sub }] }].
function AxMenu({ label, sections, onPick, className, ariaLabel }) {
  const [menu, setMenu] = useState(null);
  const open = e => {
    const screen = e.currentTarget.closest('.screen').getBoundingClientRect();
    const b = e.currentTarget.getBoundingClientRect();
    const right = Math.max(12, screen.right - b.right);
    setMenu({ top: b.bottom - screen.top + 6, right: Math.min(right, screen.width - 232) });
  };
  return (
    <>
      <button className={cx('chip on ax-menu-btn', className)} onClick={open} aria-haspopup="menu" aria-label={ariaLabel}><span>{label}</span><Icon name="chevronDown" size={12} weight={2.6} /></button>
      {menu && (
        <div className="overlay" onClick={() => setMenu(null)}>
          <div className="menu glass ax-menu" style={{ top: menu.top, right: menu.right }} onClick={e => e.stopPropagation()} role="menu">
            {sections.map((s, si) => (
              <React.Fragment key={s.id || si}>
                {si > 0 && <div className="menu-sep" />}
                {s.title && <div className="ax-menu-title">{s.title}</div>}
                {s.items.map(it => (
                  <button key={it.key} className="menu-item" onClick={() => { setMenu(null); onPick(it.key, s.id); }}>
                    <span className="menu-check">{it.on && <Icon name="check" size={16} weight={2.6} />}</span>
                    <span className="menu-label">{it.label}{it.sub && <small>{it.sub}</small>}</span>
                  </button>
                ))}
              </React.Fragment>
            ))}
          </div>
        </div>
      )}
    </>
  );
}

function axRangeLabel(sel) { return sel.key === 'custom' ? axCustomLabel(sel) : AX_RANGE_LABEL[sel.key]; }

function AxRangeMenu({ r, sel, update, onCustom }) {
  const sections = [
    { id: 'range', items: Object.entries(AX_RANGE_LABEL).map(([k, l]) => ({ key: k, label: l, on: sel.key === k })) },
    { id: 'custom', items: [{ key: 'custom', label: '自定义…', on: sel.key === 'custom', sub: sel.key === 'custom' ? axCustomLabel(sel) : null }] },
  ];
  return <AxMenu label={sel.offset ? r.label : axRangeLabel(sel)} sections={sections} ariaLabel="时间范围" onPick={k => (k === 'custom' ? onCustom() : update({ key: k, offset: 0 }))} className="ax-range-btn" />;
}

// Segmented range for the cards / ranking / chart screens. Re-tapping a selected segment does nothing (as Picker(.segmented));
// the date caption is the way back into the custom sheet.
function AxRangeBar({ r, sel, update, onCustom, onFilterClear }) {
  const items = [
    { key: 'today', label: '今天' }, { key: '7d', label: '7 天' }, { key: '30d', label: '30 天' },
    { key: 'custom', label: sel.key === 'custom' ? axCustomLabel(sel) : '自定义' },
  ];
  const pick = k => {
    if (k === 'custom') { if (sel.key !== 'custom') onCustom(); return; }
    if (k !== sel.key || sel.offset) update({ key: k, offset: 0 });
  };
  return (
    <div className="ax-range pad-x">
      <Segmented items={items} value={sel.key} onChange={pick} />
      <div className="ax-range-cap">
        <button className="ax-cap-btn" onClick={onCustom} aria-label="选择日期范围"><AxCalGlyph /><span className="num">{r.caption}</span><Icon name="chevron" size={11} weight={2.6} /></button>
        {sel.filter && <AxFilterChip filter={sel.filter} onClear={onFilterClear} />}
      </div>
    </div>
  );
}

// Tabs variant: one caption line with a range menu, so the segment picker above stays the only segmented control.
function AxRangeMenuRow({ r, sel, update, onCustom, onFilterClear }) {
  return (
    <div className="ax-range-mini pad-x">
      <span className="num ax-range-mini-cap">{r.caption}</span>
      {sel.filter && <AxFilterChip filter={sel.filter} onClear={onFilterClear} />}
      <AxRangeMenu r={r} sel={sel} update={update} onCustom={onCustom} />
    </div>
  );
}

// Month grid like DatePicker(.graphical): one selected day (the edge being edited), no range shading — the system control has none.
// Days before the site went live (7/17) and after today are disabled, as DatePicker(in: launch...today).
function AxCalendar({ value, onPick }) {
  const [month, setMonth] = useState(() => { const d = axDay(value); return [d.getFullYear(), d.getMonth()]; });
  const [y, m] = month;
  const lead = new Date(y, m, 1).getDay();
  const count = new Date(y, m + 1, 0).getDate();
  const minOff = -AX_LAST;
  const canBack = axOff(new Date(y, m, 1)) > minOff;
  const canFwd = axOff(new Date(y, m + 1, 1)) <= 0;
  const cells = [...Array(lead).fill(null), ...Array.from({ length: count }, (_, i) => i + 1)];
  return (
    <div className="ax-cal">
      <div className="ax-cal-head">
        <b className="num">{y}年{m + 1}月</b>
        <span className="ax-cal-nav">
          <button disabled={!canBack} onClick={() => setMonth([m === 0 ? y - 1 : y, (m + 11) % 12])} aria-label="上个月"><Icon name="back" size={15} weight={2.4} /></button>
          <button disabled={!canFwd} onClick={() => setMonth([m === 11 ? y + 1 : y, (m + 1) % 12])} aria-label="下个月"><Icon name="chevron" size={15} weight={2.4} /></button>
        </span>
      </div>
      <div className="ax-cal-grid">
        {['日', '一', '二', '三', '四', '五', '六'].map(w => <span key={w} className="ax-cal-w">{w}</span>)}
        {cells.map((d, i) => {
          if (!d) return <span key={`e${i}`} />;
          const off = axOff(new Date(y, m, d));
          const out = off > 0 || off < minOff;
          return (
            <button key={d} disabled={out} className={cx('ax-cal-d num', off === value && 'edge', off === 0 && 'today')} aria-pressed={off === value} onClick={() => onPick(off)}>{d}</button>
          );
        })}
      </div>
    </div>
  );
}

function axDateLine(off) { const d = axDay(off); return `${axMD(d)} ${AX_WEEK[d.getDay()]}`; }

function AxCustomSheet({ r, sel, update, onClose }) {
  const start = sel.key === 'custom' ? { preset: sel.offset ? 'dates' : sel.custom, from: r.first - AX_LAST, to: r.last - AX_LAST } : { preset: 'month', ...axPresetDates('month') };
  const [preset, setPreset] = useState(start.preset);
  const [from, setFrom] = useState(start.from);
  const [to, setTo] = useState(start.to);
  const [editing, setEditing] = useState(null);
  const match = (f, t) => (Object.keys(AX_PRESETS).find(k => { const p = axPresetDates(k); return p.from === f && p.to === t; }) || 'dates');
  const pickPreset = k => { const p = axPresetDates(k); setPreset(k); setFrom(p.from); setTo(p.to); setEditing(null); };
  const pickDay = off => {
    let f = from, t = to;
    if (editing === 'from') { f = off; if (f > t) t = f; } else { t = off; if (t < f) f = t; }
    setFrom(f); setTo(t); setPreset(match(f, t));
  };
  const apply = () => { update(preset === 'dates' ? { key: 'custom', custom: 'dates', from, to, offset: 0 } : { key: 'custom', custom: preset, offset: 0 }); onClose(); };
  const row = (id, label, off, tail) => (
    <button className={cx('ax-date-row', editing === id && 'on')} onClick={() => setEditing(editing === id ? null : id)} aria-expanded={editing === id}>
      <span className="ax-date-k">{label}</span>
      <span className="ax-date-v num">{axDateLine(off)}<small>{tail}</small></span>
    </button>
  );
  return (
    <Sheet title="自定义范围" onClose={onClose} tall trailing={<button className="glass-btn glass-btn-text glass-prominent" onClick={apply}><span>应用</span></button>}>
      <div className="ax-sheet">
        <Chips items={Object.entries(AX_PRESETS).map(([k, l]) => ({ key: k, label: l }))} value={preset} onChange={pickPreset} />
        <div className="ax-date-form">
          {row('from', '开始', from, '00:00')}
          {editing === 'from' && <AxCalendar value={from} onPick={pickDay} key="from" />}
          {row('to', '结束', to, to === 0 ? '现在（09:41）' : '24:00')}
          {editing === 'to' && <AxCalendar value={to} onPick={pickDay} key="to" />}
        </div>
        <div className="ax-sheet-note">共 <span className="num">{to - from + 1}</span> 天，{to === from ? '按小时' : '按天'}统计；按本机时区计算。点开始或结束各选一天，上面的快捷项会跟着取消。站点 {axMD(axDay(-AX_LAST))}开通，更早没有数据。</div>
      </div>
    </Sheet>
  );
}

function AxFilterSheet({ sel, update, onClose }) {
  const [kind, setKind] = useState(sel.filter ? sel.filter.kind : 'group');
  // Every group can be picked (the backend filter takes any group_id); the share is today's actual, so idle groups read 0.0%.
  const list = kind === 'group'
    ? [...DEMO.groups].sort((a, b) => a.sortOrder - b.sortOrder).map(g => ({ kind, key: g.id, name: g.name, today: g.usage.today / DEMO.today.actual, off: g.status !== 'active' }))
    : AX_MODELS.map(m => ({ kind, key: m.key, name: m.key, today: m.actual / DEMO.today.actual }));
  const current = sel.filter && sel.filter.kind === kind ? sel.filter.key : null;
  const choose = f => { update({ filter: f && { kind: f.kind, key: f.key, name: f.name } }); onClose(); };
  const radio = on => <span className={cx('st-radio', on && 'on')}>{on && <Icon name="check" size={12} weight={3.2} />}</span>;
  return (
    <Sheet title="筛选" onClose={onClose} tall>
      <div className="ax-sheet">
        <Segmented items={[{ key: 'group', label: '分组' }, { key: 'model', label: '模型' }]} value={kind} onChange={setKind} />
        <div className="ax-picks">
          <button className="ax-pick" onClick={() => choose(null)}>{radio(current === null)}<span>全部{kind === 'group' ? '分组' : '模型'}</span></button>
          {list.map(f => (
            <button key={f.key} className="ax-pick" onClick={() => choose(f)}>
              {radio(current === f.key)}<span className={cx(kind === 'model' && 'mono')}>{f.name}</span>{f.off && <em className="ax-pick-tag">停用</em>}<small className="num">{axPct(f.today)}</small>
            </button>
          ))}
        </div>
        <div className="ax-sheet-note">右侧是今天的实际扣费占比。{kind === 'model'
          ? '按模型筛选时，运行类图表（RPM / TPM、时长、错误）后端不支持，仍显示全站。'
          : '筛选后趋势、合计、排行和运行类图表都只算这个分组。分组按请求时 Key 所属的分组算：用户排行只算各用户在这个分组 Key 上的用量，一个用户的 Key 分属几个分组时，会出现在几个分组里。'}</div>
      </div>
    </Sheet>
  );
}

// Shared by every analytics screen: range state, the two sheets, and the nav filter button.
function useAxChrome(ctx, route) {
  const [r, sel, update] = useAxRange(ctx, route);
  const [sheet, setSheet] = useState(null);
  const close = () => setSheet(null);
  const openCustom = () => setSheet('custom');
  const clearFilter = () => update({ filter: null });
  const bar = <AxRangeBar r={r} sel={sel} update={update} onCustom={openCustom} onFilterClear={clearFilter} />;
  const mini = <AxRangeMenuRow r={r} sel={sel} update={update} onCustom={openCustom} onFilterClear={clearFilter} />;
  const menu = <AxRangeMenu r={r} sel={sel} update={update} onCustom={openCustom} />;
  const sheets = (
    <>
      {sheet === 'custom' && <AxCustomSheet r={r} sel={sel} update={update} onClose={close} />}
      {sheet === 'filter' && <AxFilterSheet sel={sel} update={update} onClose={close} />}
    </>
  );
  const filterBtn = <GlassButton icon="filter" onClick={() => setSheet('filter')} />;
  return { r, sel, update, bar, mini, menu, sheets, filterBtn, openCustom, clearFilter };
}

/* ---------- ranking rows ---------- */

function AxRankRow({ ctx, dim, it, i, metric = 'actual', meta }) {
  const m = AX_METRICS[metric];
  const spec = AX_DIMS[dim];
  return (
    <div className="row tappable ax-rank" onClick={() => axOpenItem(ctx, dim, it)}>
      <span className={cx('ax-rank-no num', i < 3 && 'top')}>{i + 1}</span>
      <div className="ax-rank-main">
        <div className="ax-rank-top">
          <span className={cx('ax-rank-name', spec.mono && 'mono')}>{it.name}</span>
          <span className="num ax-rank-val">{m.show(m.get(it))}</span>
        </div>
        <div className="ax-rank-bar"><AxTrack share={it.share} /><span className="num ax-rank-share">{axPct(it.share)}</span></div>
        {meta && <div className="ax-rank-meta num">{meta}</div>}
      </div>
      <div className="row-chev"><Icon name="chevron" size={13} weight={2.6} /></div>
    </div>
  );
}

// One-line row for the cards variant: rank · name · thin share bar · amount.
function AxRankLine({ ctx, dim, it, i }) {
  return (
    <button className="ax-line" onClick={() => axOpenItem(ctx, dim, it)}>
      <span className={cx('ax-line-no num', i < 3 && 'top')}>{i + 1}</span>
      <span className={cx('ax-line-name', AX_DIMS[dim].mono && 'mono')}>{it.name}</span>
      <span className="ax-line-bar"><AxTrack share={it.share} /></span>
      <span className="num ax-line-val">{fmt.money(it.actual)}</span>
    </button>
  );
}

function axRankMeta(dim, it, metric, source) {
  const parts = [];
  if (dim === 'model' && source === 'mapping' && it.upstream !== it.key) parts.push(`→ ${it.upstream}`);
  if (dim === 'user') parts.push(it.email);
  if (metric !== 'actual') parts.push(`实际 ${fmt.money(it.actual)}`);
  if (metric !== 'requests') parts.push(`请求 ${fmt.grouped(it.requests)}`);
  if (metric !== 'tokens') parts.push(`${axCompact(it.tokens)} Tokens`);
  if (dim !== 'user') parts.push(`成本 ${fmt.money(it.cost)}`);
  return parts.join(' · ');
}

// users-ranking?group_id= counts the requests made with that group's keys, not the user's "main" group.
function axKeyGroupNote(r) {
  return r.filter && r.filter.kind === 'group' ? `按请求时 Key 所属的分组统计：只算各用户在「${r.filter.name}」Key 上的用量。` : '';
}

function axRankLink(dim, count) { return dim === 'user' ? '查看前 50 位用户' : `全部 ${count} ${AX_DIMS[dim].unit}`; }

// Full ranking body: composition strip, one sort menu in the list header (metric + model source), every row.
function AxRankFull({ ctx, dim, r, onClearFilter }) {
  const [metric, setMetric] = useAxMemo(ctx, `metric:${dim}`, 'actual');
  const [source, setSource] = useAxMemo(ctx, 'modelSource', 'requested');
  if (r.filter && r.filter.kind === dim) return <div className="list-group"><AxSameFilter filter={r.filter} onClear={onClearFilter} /></div>;
  const spec = AX_DIMS[dim];
  const m = AX_METRICS[metric];
  const items = axRankItems(dim, r, metric).map(it => (dim === 'model' && source === 'upstream' ? { ...it, name: it.upstream } : it));
  const top = items.slice(0, 3);
  const rest = Math.max(0, 1 - top.reduce((s, x) => s + x.share, 0));
  const sections = [{ id: 'metric', title: '排序', items: Object.entries(AX_METRICS).map(([k, x]) => ({ key: k, label: `按${x.label}`, on: metric === k })) }];
  if (dim === 'model') sections.push({ id: 'source', title: '模型口径', items: AX_SOURCES.map(([k, l]) => ({ key: k, label: l, on: source === k })) });
  const sourceTag = dim === 'model' && source !== 'requested' ? ` · ${source === 'upstream' ? '上游模型' : '映射'}` : '';
  return (
    <>
      {items.length > 1 && <div className="ax-strip-wrap pad-x">
        <div className="ax-strip-cap"><span>前 3 占 <b className="num">{axPct(1 - rest)}</b></span><span>合计 <b className="num">{m.show(m.get(r))}</b></span></div>
        <div className="ax-strip" aria-hidden="true">
          {top.map((it, k) => <i key={it.key} className={`ax-k${k + 1}`} style={{ width: `${it.share * 100}%` }} />)}
          {rest > 0.002 && <i className="ax-k4" style={{ width: `${rest * 100}%` }} />}
        </div>
        <div className="ax-strip-legend">
          {top.map((it, k) => <span key={it.key}><i className={`ax-sq ax-k${k + 1}`} /><em className={cx(spec.mono && 'mono')}>{it.name}</em></span>)}
          {rest > 0.002 && <span><i className="ax-sq ax-k4" /><em>{dim === 'user' ? `其余用户 ${axPct(rest)}` : `其余 ${items.length - 3} ${spec.unit}`}</em></span>}
        </div>
      </div>}
      <div className="list-group ax-rank-list">
        <div className="list-head ax-rank-head">
          <span>{dim === 'user' ? `前 ${items.length} 位` : `${items.length} ${spec.unit}`}{sourceTag}</span>
          <AxMenu label={`按${m.label}`} sections={sections} ariaLabel="排序与口径" onPick={(k, id) => (id === 'source' ? setSource(k) : setMetric(k))} />
        </div>
        {items.map((it, i) => <AxRankRow key={it.key} ctx={ctx} dim={dim} it={it} i={i} metric={metric} meta={axRankMeta(dim, it, metric, source)} />)}
        {dim === 'user' && <div className="ax-list-note pad">用户排行按实际扣费取前 50 位{metric === 'actual' ? '' : `，这里在其中按${m.label}重排`}。{axKeyGroupNote(r)}</div>}
      </div>
    </>
  );
}

/* ---------- 1 · 卡片流（base）：B 的卡头 + 大数字，排行合成一张卡，更多图表是磁贴 ---------- */

function AxBCard({ icon, title, right, children, className, dataAx }) {
  return (
    <section className={cx('ax-bcard', className)} data-ax={dataAx}>
      <div className="ax-bcard-head pad">
        <span className="ax-bcard-icon"><Icon name={icon} size={15} weight={2.2} /></span>
        <span className="ax-bcard-title">{title}</span>
        {right && <span className="ax-bcard-right">{right}</span>}
      </div>
      {children}
    </section>
  );
}

function AxCardFoot({ icon, title, meta, onClick }) {
  return (
    <button className="ax-card-foot pad" onClick={onClick}>
      <span className="ax-card-foot-icon"><Icon name={icon} size={17} /></span>
      <span className="ax-card-foot-title">{title}</span>
      {meta && <em className="num">{meta}</em>}
      <Icon name="chevron" size={12} weight={2.6} />
    </button>
  );
}

function AxRevenueCard({ ctx, r }) {
  const [pick, setPick] = useState(null);
  const b = pick === null ? null : r.buckets[pick];
  return (
    <AxBCard icon="dollar" title="计费趋势" right={<AxLegend items={AX_REV_LEGEND} />} dataAx="revenue">
      <div className="ax-hero pad">
        <small className="ax-hero-label">{b ? b.label : `实际扣费 · ${r.label}`}</small>
        <div className="ax-fig ax-fig-xl num">{fmt.money(b ? b.actual : r.actual)}</div>
        <div className="ax-hero-sub">{b ? <span>{axPickLine(b, 'actual', false)} · 再点一下取消</span> : <AxDelta cur={r.actual} prev={r.prev && r.prev.actual} label={r.compare} />}</div>
      </div>
      <div className="pad"><AxTrend r={r} pick={pick} onPick={setPick} h={118} /></div>
      <AxBases ctx={ctx} r={r} />
      <div className="kv-row pad ax-kv">
        <span>请求 <b className="num">{fmt.grouped(Math.round(r.requests))}</b></span>
        <span>Tokens <b className="num">{axCompact(r.tokens)}</b></span>
        <span>平均耗时 <b className="num">{r.requests >= 1 ? axMs(AX_PCTL.duration[4]) : '—'}</b></span>
      </div>
      <AxCardFoot icon="list" title={axAllBuckets(r)} meta="计费明细" onClick={() => ctx.push({ kind: 'analyticsChart', chart: 'revenue' })} />
    </AxBCard>
  );
}

// The foot of the two money cards: “全部 10 小时 · 计费明细 ›” / “全部 7 天 · 利润明细 ›” — what the next page lists, then its name.
function axAllBuckets(r) { return `全部 ${r.buckets.length} ${r.unit === 'hour' ? '小时' : '天'}`; }

/* ---------- 利润明细：逐段的 实际扣费 − 账号成本（每段一次 usage/stats）---------- */

// Rows in cents that add up: actual and account cost are each split from the window's rounded total by the buckets' own values,
// so Σ rows = the totals and Σ profit = the window's profit (today: 1,284.50 − 512.08 = 772.42, the home cell).
function axProfitRows(r) {
  const cents = (total, xs) => axSplitInt(Math.round(total * 100), xs.map(x => x * 100)).map(c => c / 100);
  const actual = cents(r.actual, r.buckets.map(b => b.actual));
  const cost = cents(r.cost, r.buckets.map(b => b.cost));
  return r.buckets.map((b, i) => ({ ...b, actual: actual[i], cost: cost[i], profit: axCents(actual[i] - cost[i]) }));
}
function axProfitTotal(r) {
  const actual = axCents(r.actual);
  const cost = axCents(r.cost);
  return { actual, cost, profit: axCents(actual - cost) };
}

function AxProfitTable({ rows, unit, limit, total, pick, more = true }) {
  const [all, setAll] = useState(!limit);
  const list = rows.map((x, i) => [x, i]).reverse();
  const shown = all ? list : list.slice(0, limit);
  return (
    <div className="list-group ax-table ax-profit-table">
      <div className="ax-trow ax-thead"><span>{unit === 'hour' ? '时段' : '日期'}</span><span>实际</span><span>账号成本</span><span>利润</span></div>
      {shown.map(([x, i]) => (
        <div key={x.label} className={cx('ax-trow', pick === i && 'on')}>
          <span className="num">{unit === 'hour' ? x.tag : x.label.replace(/^\d+月/, '')}</span>
          <span className="num">{fmt.money(x.actual)}</span>
          <span className="num dim">{fmt.money(x.cost)}</span>
          <span className="num ax-profit-v">{fmt.money(x.profit)}</span>
        </div>
      ))}
      {more && !all && list.length > limit && <button className="ax-fold-all" onClick={() => setAll(true)}>展开全部 {list.length} {unit === 'hour' ? '小时' : '天'}<Icon name="chevronDown" size={12} weight={2.6} /></button>}
      {total && (
        <div className="ax-trow ax-total">
          <span>合计</span><span className="num">{fmt.money(total.actual)}</span><span className="num">{fmt.money(total.cost)}</span><span className="num ax-profit-v">{fmt.money(total.profit)}</span>
        </div>
      )}
    </div>
  );
}

// A loss draws below the zero line (AxChart's signed scale); only a window with no charges at all is empty.
function AxProfitChart({ r, rows, pick, onPick, h }) {
  return <AxChart values={rows.map(x => x.profit)} labels={rows.map(x => x.short)} h={h} fmtY={axShortMoney} pick={pick} onPick={onPick} {...axNowProps(r)} anchorLast={r.unit === 'day'} emptyText="这个范围内没有扣费" />;
}

function axProfitPickLine(x) {
  return <span>实际 <b className="num">{fmt.money(x.actual)}</b> · 账号成本 <b className="num">{fmt.money(x.cost)}</b></span>;
}

function AxProfitCard({ ctx, r }) {
  const [pick, setPick] = useState(null);
  const rows = axProfitRows(r);
  const tot = axProfitTotal(r);
  const b = pick === null ? null : rows[pick];
  return (
    <AxBCard icon="columns" title="利润明细" right={<span className="ax-bcard-meta">实际扣费 − 账号成本</span>} dataAx="profit">
      <div className="ax-hero pad">
        <small className="ax-hero-label">{b ? b.label : `利润 · ${r.label}`}</small>
        <div className="ax-fig ax-fig-l num">{fmt.money(b ? b.profit : tot.profit)}</div>
        <div className="ax-hero-sub">{b ? <span>{axProfitPickLine(b)} · 再点一下取消</span> : <AxDelta cur={tot.profit} prev={r.prev && profitOf(r.prev)} label={r.compare} fmtAbs={fmt.money} />}</div>
      </div>
      <div className="pad"><AxProfitChart r={r} rows={rows} pick={pick} onPick={setPick} h={100} /></div>
      <AxProfitTable rows={rows} unit={r.unit} limit={4} pick={pick} more={false} />
      <AxCardFoot icon="list" title={axAllBuckets(r)} meta="利润明细" onClick={() => ctx.push({ kind: 'analyticsChart', chart: 'profit' })} />
    </AxBCard>
  );
}

/* ---------- RPM / TPM 趋势（同现有 App 的“性能指标”）：卡片流和更多图表共用 AxPerfBody ---------- */

function AxPerfSheet({ p, onPick, onClose }) {
  const rows = p.points.map((x, i) => [x, i]).reverse();
  return (
    <Sheet title="性能明细" onClose={onClose} leadingLabel="关闭" tall>
      <div className="ax-sheet">
        <div className="ax-sheet-note">最新在上 · {p.range.label} · 每桶 {p.bucketLabel}。点一行，图上选中这个时间。</div>
        <div className="ax-perf-list">
          {rows.map(([x, i]) => (
            <button key={x.m} className="ax-perf-row" onClick={() => onPick(i)}>
              <small className="num">{x.label}{x.partial ? ` · 只覆盖 ${x.covered} 分钟` : ''}</small>
              <span className="num">RPM <b>{axPerfFmt('rpm', x.rpm)}</b> · TPM <b>{axPerfFmt('tpm', x.tpm)}</b></span>
            </button>
          ))}
        </div>
      </div>
    </Sheet>
  );
}

// startMetric: route.metric of {kind:'analytics', focus:'perf', metric:'tpm'} — lets an entry (e.g. home's TPM cell) open on that metric.
function AxPerfBody({ ctx, r, size, startMetric }) {
  const [hours, setHours] = useAxMemo(ctx, 'perfHours', 1);
  const [metric, setMetric] = useAxMemo(ctx, 'perfMetric', 'rpm');
  const [pick, setPick] = useState(null);
  const [list, setList] = useState(false);
  useEffect(() => { if (AX_PERF_METRICS.some(x => x.key === startMetric)) setMetric(startMetric); }, []);
  const p = axPerfSeries(hours, r);
  const pts = p.points;
  const latest = pts[pts.length - 1];
  const sel = pick === null ? null : pts[pick];
  const name = metric.toUpperCase();
  const show = x => axPerfFmt(metric, x[metric]);
  return (
    <>
      <div className="pad ax-perf-range"><Segmented items={AX_PERF_RANGES.map(x => ({ key: x.hours, label: x.label }))} value={hours} onChange={k => { setHours(k); setPick(null); }} /></div>
      <div className="ax-perf-hero pad">
        <div className="ax-perf-fig">
          <small className="ax-hero-label">{sel ? `${name} · ${sel.label}` : `${name} · 最新一桶 ${latest.label}`}</small>
          <div className="ax-fig ax-fig-l num">{show(sel || latest)}</div>
        </div>
        <div className="ax-perf-metric"><Segmented items={AX_PERF_METRICS} value={metric} onChange={setMetric} /></div>
      </div>
      <div className="ax-hero-sub ax-perf-sub pad num">{sel
        ? <span className="ax-perf-pick">{sel.label} · {name} {show(sel)}<em> · 再点一下取消</em></span>
        : <span>峰值 <b>{axPerfFmt(metric, p.peak[metric])}</b> · 平均 <b>{axPerfFmt(metric, p.avg[metric])}</b> · {p.range.label}</span>}</div>
      <div className="pad"><AxChart kind="line" area values={pts.map(x => x[metric])} labels={pts.map(x => x.label)} ticks={p.ticks} h={size === 'full' ? 170 : 128} fmtY={v => axPerfFmt(metric, v)} pick={pick} onPick={setPick} emptyText="这个时间范围内没有请求" /></div>
      <div className="ax-body-foot pad">
        {/* One rule for every bucket length (1 minute, 5 minutes): rate = count × 60 ÷ the seconds this bucket really covers. */}
        每桶 {p.bucketLabel}，速率 = 数量 × 60 ÷ 这一桶实际覆盖的秒数；窗口从{/^\d/.test(p.from) ? ' ' : ''}{p.from} 到现在，首尾不满一桶的按覆盖时长折算。RPM 含成功请求和错误请求，TPM 为成功请求的含缓存 Tokens。
      </div>
      <div className="ax-perf-upd pad num">更新于 {fmt.clock(DEMO_CLOCK_BASE)}:00 · 前台每 30 秒刷新</div>
      <AxCardFoot icon="list" title="性能明细" meta={`${pts.length} 桶 · 最新在上`} onClick={() => setList(true)} />
      {list && <AxPerfSheet p={p} onPick={i => { setPick(i); setList(false); }} onClose={() => setList(false)} />}
    </>
  );
}

function AxPerfCard({ ctx, r, startMetric }) {
  const on = axOpsOn(ctx);
  return (
    <AxBCard icon="signal" title="RPM / TPM 趋势" right={<span className="ax-bcard-meta">{on ? '截至现在 · 运维监控' : '运维监控'}</span>} dataAx="perf">
      {on ? <><AxOpsNote r={r} /><AxPerfBody ctx={ctx} r={r} size="card" startMetric={startMetric} /></> : <AxOpsOff text="这个站点关闭了运维监控，RPM / TPM 趋势（吞吐趋势接口）没有数据。开关在服务器端（配置文件与系统设置），手机端不能打开。" />}
    </AxBCard>
  );
}

const AX_CARD_DIMS = [{ key: 'model', label: '模型' }, { key: 'user', label: '用户' }, { key: 'group', label: '分组' }];

function AxRankCard({ ctx, r, onClear }) {
  const [dim, setDim] = useAxMemo(ctx, 'cardDim', (ctx.v && ctx.v.axCardDim) || 'model');
  const items = axRankItems(dim, r);
  const same = r.filter && r.filter.kind === dim;
  return (
    <AxBCard icon="sort" title="排行" right={<span className="ax-bcard-meta">实际扣费 · 前 5</span>}>
      <div className="pad ax-card-seg"><Segmented items={AX_CARD_DIMS} value={dim} onChange={setDim} /></div>
      {dim === 'user' && axKeyGroupNote(r) && <div className="ax-card-note pad">{axKeyGroupNote(r)}</div>}
      {same ? <AxSameFilter filter={r.filter} onClear={onClear} /> : (
        <div className="ax-lines">
          {items.length === 0 && <div className="empty">这个范围内没有{AX_DIMS[dim].short}用量</div>}
          {items.slice(0, 5).map((it, i) => <AxRankLine key={it.key} ctx={ctx} dim={dim} it={it} i={i} />)}
        </div>
      )}
      {!same && items.length > 5 && <AxCardFoot icon={AX_DIMS[dim].icon} title={axRankLink(dim, items.length)} meta={dim === 'model' ? '含上游口径' : null} onClick={() => ctx.push({ kind: 'analyticsRank', dim })} />}
    </AxBCard>
  );
}

function AxMoreCard({ ctx, r }) {
  const charts = axCharts(ctx);
  // Profit and RPM / TPM have their own cards above, so the tiles show four of the rest.
  const keys = axOpsOn(ctx) ? ['tokens', 'userTrend', 'errTrend', 'latency'] : ['tokens', 'userTrend', 'endpoints', 'reqType'];
  return (
    <AxBCard icon="chart" title="更多图表" right={<span className="ax-bcard-meta num">{charts.length} 张</span>}>
      <div className="ax-tiles ax-tiles-in pad">
        {keys.map(k => <AxTile key={k} c={AX_CHARTS.find(x => x.key === k)} r={r} onClick={() => ctx.push({ kind: 'analyticsMore', chart: k })} />)}
      </div>
      <AxCardFoot icon="grid" title="全部图表" meta={AX_TOPICS.map(t => `${t.label} ${t.key === 'ops' && !axOpsOn(ctx) ? '未开启' : AX_CHARTS.filter(c => c.topic === t.key).length}`).join(' · ')} onClick={() => ctx.push({ kind: 'analyticsMore' })} />
    </AxBCard>
  );
}

// Order: the range-driven money cards (计费 → 利润), the ranking, then the live RPM / TPM card (its own rolling window), then more charts.
// route.focus === 'perf' (home's RPM / TPM cells) lands on the RPM / TPM card.
function AxCardsScreen({ ctx, route }) {
  const ch = useAxChrome(ctx, route);
  const top = useRef(null);
  const rangeKey = JSON.stringify([ch.sel.key, ch.sel.custom, ch.sel.from, ch.sel.to, ch.sel.offset]);
  useEffect(() => {
    if (!route || route.focus !== 'perf') return;
    const box = top.current && top.current.closest('.scroll');
    const el = box && box.querySelector('[data-ax="perf"]');
    if (el) box.scrollTop = axOffsetIn(box, el) - 8;
  }, []);
  return (
    <Screen ctx={ctx} nav={<NavBar ctx={ctx} back title="统计分析" subtitle={`${ctx.site} · 刚刚更新`} trailing={ch.filterBtn} />}>
      <div ref={top}>{ch.bar}</div>
      <AxRevenueCard ctx={ctx} r={ch.r} key={`rev${rangeKey}`} />
      <AxProfitCard ctx={ctx} r={ch.r} key={`profit${rangeKey}`} />
      <AxRankCard ctx={ctx} r={ch.r} onClear={ch.clearFilter} />
      <AxPerfCard ctx={ctx} r={ch.r} startMetric={route && route.focus === 'perf' ? route.metric : null} />
      <AxMoreCard ctx={ctx} r={ch.r} />
      {ch.sheets}
    </Screen>
  );
}

/* ---------- 2 · 分段（tabs）---------- */

function AxBucketTable({ r, limit }) {
  const [all, setAll] = useState(!limit);
  const rows = [...r.buckets].reverse();
  const shown = all ? rows : rows.slice(0, limit);
  return (
    <div className="list-group ax-table">
      <div className="ax-trow ax-thead"><span>{r.unit === 'hour' ? '时段' : '日期'}</span><span>实际</span><span>标准</span><span>请求</span></div>
      {shown.map(b => (
        <div key={b.label} className="ax-trow">
          <span className="num">{r.unit === 'hour' ? b.tag : b.label.replace(/^\d+月/, '')}</span>
          <span className="num">{fmt.money(b.actual)}</span>
          <span className="num dim">{fmt.money(b.standard)}</span>
          <span className="num">{fmt.grouped(b.requests)}</span>
        </div>
      ))}
      {!all && rows.length > limit && <button className="ax-fold-all" onClick={() => setAll(true)}>展开全部 {rows.length} {r.unit === 'hour' ? '小时' : '天'}<Icon name="chevronDown" size={12} weight={2.6} /></button>}
    </div>
  );
}

function AxTabsRevenue({ ctx, r }) {
  const [metric, setMetric] = useAxMemo(ctx, 'tabsMetric', 'actual');
  const [pick, setPick] = useState(null);
  const b = pick === null ? null : r.buckets[pick];
  const m = AX_METRICS[metric];
  const sections = [{ id: 'metric', items: Object.entries(AX_METRICS).map(([k, x]) => ({ key: k, label: x.label, on: metric === k })) }];
  return (
    <>
      <div className="ax-tabs-hero pad">
        <div className="ax-hero-top">
          <AxMenu label={m.label} sections={sections} ariaLabel="指标" onPick={k => { setMetric(k); setPick(null); }} className="ax-metric-btn" />
          {metric === 'actual' && <AxLegend items={AX_REV_LEGEND} />}
        </div>
        <div className="ax-fig ax-fig-xl num">{m.show(m.get(b || r))}</div>
        <div className="ax-hero-sub">{b ? axPickLine(b, metric) : <AxDelta cur={m.get(r)} prev={r.prev && m.get(r.prev)} label={r.compare} />}</div>
      </div>
      <div className="pad ax-tabs-chart"><AxTrend r={r} pick={pick} onPick={setPick} h={168} metric={metric} /></div>
      <AxBases ctx={ctx} r={r} />
      <div className="list-head ax-list-head"><span>{r.unit === 'hour' ? '逐小时' : '逐日'}</span><b className="num">{r.buckets.length} 段</b></div>
      <AxBucketTable r={r} />
    </>
  );
}

function AxMoreDirectory({ ctx }) {
  const { skin } = ctx;
  const on = axOpsOn(ctx);
  return AX_TOPICS.map((t, ti) => (
    <Section key={t.key} skin={skin} title={t.label} meta={t.key === 'ops' ? (on ? t.note : '未开启') : `${AX_CHARTS.filter(c => c.topic === t.key).length} 张`} index={['壹', '贰', '叁'][ti]} className="ax-sec">
      {t.key === 'ops' && !on ? <AxOpsOff /> : AX_CHARTS.filter(c => c.topic === t.key).map(c => (
        <Row key={c.key} skin={skin} tone="none" lead={<span className="lead-icon dim"><Icon name={c.icon} /></span>} onClick={() => ctx.push({ kind: 'analyticsMore', chart: c.key })}>
          <div className="row-top"><span className="row-title">{c.title}</span><span className="row-right dim">{c.sub}</span></div>
        </Row>
      ))}
    </Section>
  ));
}

const AX_SEGS = [{ key: 'revenue', label: '计费' },{ key: 'model', label: '模型' }, { key: 'user', label: '用户' }, { key: 'group', label: '分组' }, { key: 'more', label: '更多' }];

function AxTabsScreen({ ctx, route }) {
  const ch = useAxChrome(ctx, route);
  const [seg, setSeg] = useAxMemo(ctx, 'seg', (ctx.v && ctx.v.axSeg) || 'revenue');
  const r = ch.r;
  return (
    <Screen ctx={ctx} nav={<NavBar ctx={ctx} back title="统计分析" subtitle={`${ctx.site} · ${r.label}`} trailing={ch.filterBtn} />}>
      <div className="pad-x ax-segbar"><Segmented items={AX_SEGS} value={seg} onChange={setSeg} /></div>
      {seg !== 'more' && ch.mini}
      {seg === 'revenue' && <AxTabsRevenue ctx={ctx} r={r} key={JSON.stringify([ch.sel.key, ch.sel.custom, ch.sel.from, ch.sel.to])} />}
      {['model', 'user', 'group'].includes(seg) && <AxRankFull ctx={ctx} dim={seg} r={r} onClearFilter={ch.clearFilter} />}
      {seg === 'more' && <><div className="ax-more-intro pad">不常看的图都在这里，范围沿用“{r.label}”。</div><AxMoreDirectory ctx={ctx} /></>}
      {ch.sheets}
    </Screen>
  );
}

/* ---------- 3 · 报表式（report）---------- */

function AxStepper({ r, update, sel, onCustom }) {
  return (
    <div className="ax-stepper pad-x">
      <button className="ax-step" disabled={!r.canPrev} onClick={() => update({ offset: sel.offset - 1 })} aria-label="上一段"><Icon name="back" size={16} weight={2.4} /></button>
      <button className="ax-step-label" onClick={onCustom}>
        <b className="num">{r.caption.split(' · ')[0].replace('（今天到 09:41）', '')}</b>
        <small>{r.label}{r.live ? ' · 到 09:41' : ''} · {r.unit === 'hour' ? '按小时' : '按天'}</small>
      </button>
      <button className="ax-step" disabled={!r.canNext} onClick={() => update({ offset: sel.offset + 1 })} aria-label="下一段"><Icon name="chevron" size={16} weight={2.4} /></button>
    </div>
  );
}

function AxKpis({ r }) {
  const tiles = [
    ['实际扣费', fmt.money(r.actual), <AxDelta cur={r.actual} prev={r.prev && r.prev.actual} label={r.compare} />, 'bar'],
    ['账号成本', fmt.money(r.cost), <span>占实际 <b className="num">{axPct(axPer(r.cost, r.actual), 0)}</b></span>, null],
    ['标准', fmt.money(r.standard), <span>实际是标准的 <b className="num">{axPct(axPer(r.actual, r.standard), 0)}</b></span>, 'std'],
    ['利润', fmt.money(profitOf(r)), <span>实际扣费 − 账号成本</span>, null],
    ['请求', fmt.grouped(Math.round(r.requests)), <span>平均 <b className="num">{fmt.money(axPer(r.actual, r.requests), { digits: 3 })}</b> / 次</span>, null],
    ['Tokens', axCompact(r.tokens), <span>缓存读 <b className="num">{axPct(axPer(r.mix[2], r.tokens), 0)}</b></span>, null],
  ];
  return (
    <div className="ax-kpis">
      {tiles.map(([label, value, sub, kind]) => (
        <div key={label} className="ax-kpi">
          <small><AxKey kind={kind} />{label}</small>
          <b className="ax-fig num">{value}</b>
          <span className="ax-kpi-sub">{sub}</span>
        </div>
      ))}
    </div>
  );
}

function AxFold({ id, title, summary, open, onToggle, children }) {
  return (
    <section className={cx('ax-fold', open && 'open')}>
      <button className="ax-fold-head" onClick={() => onToggle(id)} aria-expanded={open}>
        <span className="ax-fold-chev"><Icon name="chevron" size={13} weight={2.8} /></span>
        <span className="ax-fold-title">{title}</span>
        {!open && <span className="ax-fold-sum">{summary}</span>}
      </button>
      {open && <div className="ax-fold-body">{children}</div>}
    </section>
  );
}

function AxRankTable({ ctx, dim, r }) {
  const items = axRankItems(dim, r);
  return (
    <div className="ax-rtable">
      <div className="ax-rtrow ax-thead"><span>#</span><span>{AX_DIMS[dim].short}</span><span>请求</span><span>实际</span><span>占比</span></div>
      {items.slice(0, 5).map((it, i) => (
        <button key={it.key} className="ax-rtrow" onClick={() => axOpenItem(ctx, dim, it)}>
          <span className="num dim">{i + 1}</span>
          <span className={cx('ax-rt-name', AX_DIMS[dim].mono && 'mono')}>{it.name}</span>
          <span className="num">{axCompact(it.requests)}</span>
          <span className="num">{fmt.money(it.actual)}</span>
          <span className="num dim">{axPct(it.share)}</span>
        </button>
      ))}
      {items.length > 5 && <button className="ax-fold-all" onClick={() => ctx.push({ kind: 'analyticsRank', dim })}>{axRankLink(dim, items.length)}<Icon name="chevron" size={12} weight={2.6} /></button>}
    </div>
  );
}

function AxReportScreen({ ctx, route }) {
  const ch = useAxChrome(ctx, route);
  const r = ch.r;
  const on = axOpsOn(ctx);
  const initialOpen = ((ctx.v && ctx.v.axOpen) || 'trend').split(',');
  const [open, setOpen] = useAxMemo(ctx, 'folds', initialOpen);
  const toggle = id => setOpen(o => (o.includes(id) ? o.filter(x => x !== id) : [...o, id]));
  const leader = dim => {
    if (r.filter && r.filter.kind === dim) return `已筛选 · ${r.filter.name}`;
    const it = axRankItems(dim, r)[0];
    return it ? `${it.name} 居首 · ${axPct(it.share)}` : '—';
  };
  return (
    <Screen ctx={ctx} nav={<NavBar ctx={ctx} back title="统计分析" subtitle={`${ctx.site} · 刚刚更新`} trailing={ch.filterBtn} />}>
      <AxStepper r={r} update={ch.update} sel={ch.sel} onCustom={ch.openCustom} />
      <div className="chips ax-presets">
        {[['today', '今天'], ['7d', '7 天'], ['30d', '30 天'], ['custom', ch.sel.key === 'custom' ? axCustomLabel(ch.sel) : '自定义…']].map(([k, l]) => (
          <button key={k} className={cx('chip', ch.sel.key === k && 'on')} onClick={() => (k === 'custom' ? ch.openCustom() : ch.update({ key: k, offset: 0 }))}>{l}</button>
        ))}
      </div>
      {ch.sel.filter && <div className="ax-filter-row pad-x"><AxFilterChip filter={ch.sel.filter} onClear={ch.clearFilter} /></div>}
      <AxKpis r={r} />
      <div className="ax-folds">
        <AxFold id="trend" title="计费趋势" summary={`${r.unit === 'hour' ? '按小时' : '按天'} · 实际 / 标准`} open={open.includes('trend')} onToggle={toggle}>
          <div className="ax-fold-legend"><AxLegend items={AX_REV_LEGEND} /></div>
          <AxTrend r={r} h={112} />
          <button className="ax-fold-all" onClick={() => ctx.push({ kind: 'analyticsChart', chart: 'revenue' })}>{r.unit === 'hour' ? '逐小时' : '逐日'}明细<Icon name="chevron" size={12} weight={2.6} /></button>
        </AxFold>
        {['model', 'user', 'group'].map(dim => (
          <AxFold key={dim} id={dim} title={AX_DIMS[dim].title} summary={leader(dim)} open={open.includes(dim)} onToggle={toggle}>
            {r.filter && r.filter.kind === dim ? <AxSameFilter filter={r.filter} onClear={ch.clearFilter} /> : <AxRankTable ctx={ctx} dim={dim} r={r} />}
          </AxFold>
        ))}
        <AxFold id="more" title="更多图表" summary={AX_TOPICS.map(t => `${t.label} ${t.key === 'ops' && !on ? '未开启' : AX_CHARTS.filter(c => c.topic === t.key).length}`).join(' · ')} open={open.includes('more')} onToggle={toggle}>
          {AX_TOPICS.map(t => (
            <div key={t.key} className="ax-fold-group">
              <small>{t.label}{t.note && on ? ` · ${t.note}` : ''}</small>
              {t.key === 'ops' && !on ? <AxOpsOff /> : AX_CHARTS.filter(c => c.topic === t.key).map(c => (
                <button key={c.key} className="ax-fold-link" onClick={() => ctx.push({ kind: 'analyticsMore', chart: c.key })}><span>{c.title}</span><em>{c.sub}</em><Icon name="chevron" size={12} weight={2.6} /></button>
              ))}
            </div>
          ))}
        </AxFold>
      </div>
      {ch.sheets}
    </Screen>
  );
}

/* ---------- 全部排行 · 模型对象页 ---------- */

function AxRankScreen({ ctx, route }) {
  const ch = useAxChrome(ctx, route);
  const spec = AX_DIMS[route.dim];
  return (
    <Screen plain ctx={ctx} nav={<NavBar ctx={ctx} back title={spec.full} subtitle={`${ctx.site} · ${ch.r.label}`} trailing={ch.filterBtn} />}>
      {ch.bar}
      <AxRankFull ctx={ctx} dim={route.dim} r={ch.r} onClearFilter={ch.clearFilter} />
      {ch.sheets}
    </Screen>
  );
}

function AxModelScreen({ ctx, route }) {
  const { skin } = ctx;
  const ch = useAxChrome(ctx, route);
  const m = AX_MODEL_BY_KEY[route.model] || AX_MODELS[0];
  // Same slice as filtering the whole page by this model — inside the active group filter, if there is one.
  const groupF = ch.r.filter && ch.r.filter.kind === 'group' ? ch.r.filter : null;
  const scope = groupF ? ch.r : ch.r.base;
  const mf = { kind: 'model', key: m.key };
  const r = axFocus(ch.r.base, groupF ? [groupF, mf] : [mf]);
  const users = axRankItems('user', r).slice(0, 3);
  const win = axSpeedWindow(ch.r);
  const [tps, ttft, dur] = m.speed;
  const logs = { kind: 'logs', scope: 'usage', model: m.key, ...(groupF ? { group: groupF.key } : {}) };
  return (
    <Screen ctx={ctx} nav={<NavBar ctx={ctx} back title={m.key} subtitle={`模型 · ${m.platform} · ${ch.r.label}`} />}>
      {ch.bar}
      <div className="ax-model-head pad">
        <small className="ax-hero-label">实际扣费 · 占{groupF ? groupF.name : '全部'} {axPct(axPer(r.actual, scope.actual))}</small>
        <div className="ax-fig ax-fig-xl num">{fmt.money(r.actual)}</div>
        <div className="ax-hero-sub"><AxDelta cur={r.actual} prev={r.prev && r.prev.actual} label={r.compare} /></div>
        {m.upstream !== m.key && <div className="ax-hero-sub">上游模型 <span className="mono">{m.upstream}</span></div>}
      </div>
      <Section skin={skin} title="趋势" meta="实际 / 标准（点线）" index="壹" className="ax-sec">
        <div className="pad ax-pad-top"><AxTrend r={r} h={100} /></div>
        <AxBases ctx={ctx} r={r} />
      </Section>
      <Section skin={skin} title="用量" meta={ch.r.label} index="贰" className="ax-sec">
        <div className="kv-grid pad">
          <KV label="请求" value={<span className="num">{fmt.grouped(Math.round(r.requests))}</span>} />
          <KV label="Tokens" value={<span className="num">{axCompact(r.tokens)}</span>} />
          <KV label="缓存读占比" value={<span className="num">{axPct(axPer(r.mix[2], r.tokens), 0)}</span>} />
          <KV label="平均每次" value={<span className="num">{fmt.money(axPer(r.actual, r.requests), { digits: 3 })}</span>} />
        </div>
      </Section>
      <Section skin={skin} title="速度" meta={`${win} · 滚动窗口`} index="叁" className="ax-sec">
        <div className="kv-grid pad">
          <KV label="输出 Tokens/秒" value={<span className="num">{tps}</span>} />
          <KV label="平均首 Token" value={<span className="num">{axMs(ttft)}</span>} />
          <KV label="平均时长" value={<span className="num">{axMs(dur)}</span>} />
        </div>
        <div className="ax-body-foot pad">{axSpeedNote(ch.r)}</div>
      </Section>
      <Section skin={skin} title="用得最多的用户" meta="实际扣费" index="肆" className="ax-sec">
        {users.length === 0 && <div className="empty pad">这个范围内没有用户用量</div>}
        {users.map((it, i) => <AxRankRow key={it.key} ctx={ctx} dim="user" it={it} i={i} />)}
        <Row skin={skin} tone="none" lead={<span className="lead-icon dim"><Icon name="list" /></span>} onClick={() => ctx.push(logs)}>
          <div className="row-top"><span className="row-title">这个模型的使用记录</span></div>
          <div className="row-meta">近 24 小时 · 带上{groupF ? '模型和分组' : '模型'}筛选，可以去掉</div>
        </Row>
      </Section>
      {ch.sheets}
    </Screen>
  );
}

/* ---------- chart bodies for “更多图表”（size: 'card' in lists, 'full' for one chart per screen）---------- */

function AxNums({ items }) {
  return (
    <div className="ax-nums pad">
      {items.map(([label, value]) => <span key={label}><small>{label}</small><b className="num">{value}</b></span>)}
    </div>
  );
}

function AxRevenueBody({ r, size }) {
  const [pick, setPick] = useState(null);
  const b = pick === null ? null : r.buckets[pick];
  return (
    <>
      <div className="ax-body-head pad"><span className="ax-body-pick num">{b ? `${b.label} · ${fmt.money(b.actual)}` : `实际 ${fmt.money(r.actual)}`}</span><AxLegend items={AX_REV_LEGEND} /></div>
      <div className="pad"><AxTrend r={r} pick={pick} onPick={setPick} h={size === 'full' ? 170 : 112} /></div>
      <AxNums items={[['账号成本', fmt.money(r.cost)], ['标准', fmt.money(r.standard)], ['利润', fmt.money(profitOf(r))]]} />
      <AxBucketTable r={r} limit={size === 'full' ? null : 6} key={r.caption} />
    </>
  );
}

function AxProfitBody({ r, size }) {
  const [pick, setPick] = useState(null);
  const rows = axProfitRows(r);
  const tot = axProfitTotal(r);
  const b = pick === null ? null : rows[pick];
  return (
    <>
      <div className="ax-body-head pad"><span className="ax-body-pick num">{b ? `${b.label} · 利润 ${fmt.money(b.profit)}` : `利润 ${fmt.money(tot.profit)}`}</span><span className="ax-legend">实际扣费 − 账号成本</span></div>
      <div className="pad"><AxProfitChart r={r} rows={rows} pick={pick} onPick={setPick} h={size === 'full' ? 170 : 112} /></div>
      <AxNums items={[['实际扣费', fmt.money(tot.actual)], ['账号成本', fmt.money(tot.cost)], ['利润', fmt.money(tot.profit)]]} />
      <AxProfitTable rows={rows} unit={r.unit} limit={size === 'full' ? null : 6} total={size === 'full' ? tot : null} pick={pick} key={r.caption} />
      {size === 'full' && <div className="ax-body-foot pad">每{r.unit === 'hour' ? '小时' : '天'}的利润 = 这段的实际扣费 − 账号成本，逐段相加等于合计。</div>}
    </>
  );
}

function AxTokensBody({ r, size }) {
  const [pick, setPick] = useState(null);
  const [only, setOnly] = useState(null);
  const b = pick === null ? null : r.buckets[pick];
  const mix = b ? b.mix : r.mix;
  return (
    <>
      <div className="ax-token-legend ax-lg-btns pad">
        {AX_TOKEN_KEYS.map((k, i) => (
          <button key={k} className={cx('ax-lg-btn', only === i && 'on', only !== null && only !== i && 'off')} onClick={() => { setOnly(only === i ? null : i); setPick(null); }} aria-pressed={only === i}>
            <i className={cx('ax-sq', AX_TOKEN_CLS[i])} />{k}<b className="num">{axCompact(mix[i])}</b>
          </button>
        ))}
      </div>
      <div className="pad">{only === null
        ? <AxChart kind="stack" stacks={r.buckets.map(x => x.mix)} classes={AX_TOKEN_CLS} labels={r.buckets.map(x => x.short)} h={size === 'full' ? 170 : 112} fmtY={axCompact} pick={pick} onPick={setPick} anchorLast={r.unit === 'day'} {...axNowProps(r)} />
        : <AxChart values={r.buckets.map(x => x.mix[only])} labels={r.buckets.map(x => x.short)} h={size === 'full' ? 170 : 112} fmtY={axCompact} pick={pick} onPick={setPick} anchorLast={r.unit === 'day'} {...axNowProps(r)} />}</div>
      <div className="ax-body-foot pad">{b ? `${b.label} · 合计 ${axCompact(b.tokens)}` : only !== null ? `只看${AX_TOKEN_KEYS[only]}，再点一次图例恢复全部` : `合计 ${axCompact(r.tokens)} · 缓存读占 ${axPct(axPer(r.mix[2], r.tokens), 0)} · 点图例只看一项`}</div>
      {size === 'full' && (
        <div className="list-group ax-table ax-table5">
          <div className="ax-trow ax-thead"><span>{r.unit === 'hour' ? '时段' : '日期'}</span>{AX_TOKEN_KEYS.map(k => <span key={k}>{k}</span>)}</div>
          {[...r.buckets].reverse().map(x => (
            <div key={x.label} className="ax-trow"><span>{x.short}</span>{x.mix.map((m, i) => <span key={i} className="num">{axCompact(m)}</span>)}</div>
          ))}
        </div>
      )}
    </>
  );
}

function AxUserTrendBody({ ctx, r, size }) {
  const [metric, setMetric] = useState('tokens');
  const users = axRankItems('user', r, metric).slice(0, size === 'full' ? 12 : 5);
  const series = (u, k) => r.buckets.map((b, i) => (metric === 'tokens' ? b.tokens : b.actual) * u.share * (1 + 0.35 * Math.sin(i * (k + 1.4) + k)));
  return (
    <>
      <div className="pad ax-body-ctl"><Segmented items={[{ key: 'tokens', label: 'Tokens' }, { key: 'actual', label: '实际扣费' }]} value={metric} onChange={setMetric} /></div>
      {users.length === 0 && <div className="empty">这个范围内没有用户用量</div>}
      {users.map((u, k) => (
        <div key={u.key} className="row tappable ax-multi" onClick={() => axOpenItem(ctx, 'user', u)}>
          <span className="ax-rank-no num">{k + 1}</span>
          <span className="ax-multi-name">{u.name}</span>
          <span className="ax-multi-spark"><Sparkline values={series(u, k)} w={100} h={26} /></span>
          <b className="num ax-multi-val">{metric === 'tokens' ? axCompact(u.tokens) : fmt.money(u.actual)}</b>
        </div>
      ))}
      <div className="ax-body-foot pad">按{metric === 'tokens' ? ' Tokens ' : '实际扣费'}取前 12 位{size === 'full' ? '' : '，这里显示前 5 位'}；每条线用自己的刻度，只看走势。</div>
    </>
  );
}

function AxShareRows({ rows, mono, tone }) {
  return rows.map(([name, value, share, extra]) => (
    <div key={name} className="ax-share-row pad">
      <div className="ax-share-top"><span className={cx('ax-share-name', mono && 'mono')}>{name}</span><b className="num">{value}</b></div>
      <div className="ax-rank-bar"><AxTrack share={share} tone={tone} /><span className="num ax-rank-share">{axPct(share)}</span></div>
      {extra && <div className="ax-rank-meta num">{extra}</div>}
    </div>
  ));
}

function AxEndpointsBody({ r }) {
  const [side, setSide] = useState('inbound');
  const list = axEndpointRows(r, side);
  const total = list.reduce((s, x) => s + x.requests, 0);
  const rows = list.map(x => [x.path, fmt.grouped(Math.round(x.requests)), axRatio(x.requests, total), `实际 ${fmt.money(x.actual)}`]);
  return (
    <>
      <div className="pad ax-body-ctl"><Segmented items={[{ key: 'inbound', label: '入站端点' }, { key: 'upstream', label: '上游端点' }]} value={side} onChange={setSide} /></div>
      {rows.length ? <AxShareRows rows={rows} mono /> : <div className="empty pad">这个范围内没有用量</div>}
    </>
  );
}

function AxReqTypeBody({ r }) {
  const f = axShare(r);
  const total = AX_REQ_TYPES.reduce((s, x) => s + x[1], 0);
  if (r.requests < 0.5) return <div className="empty pad">这个范围内没有用量</div>;
  return (
    <>
      <div className="ax-strip-wrap pad">
        <div className="ax-strip ax-strip-tall">{AX_REQ_TYPES.filter(x => x[1]).map(([k, n], i) => <i key={k} className={`ax-k${i + 1}`} style={{ width: `${(n / total) * 100}%` }} />)}</div>
      </div>
      {AX_REQ_TYPES.map(([k, n], i) => (
        <div key={k} className="ax-type-row pad">
          <i className={cx('ax-sq', n ? `ax-k${i + 1}` : 'ax-k-empty')} /><span>{k}</span><b className="num">{fmt.grouped(Math.round(n * f))}</b><em className="num">{axPct(n / total)}</em>
        </div>
      ))}
    </>
  );
}

function AxSwitchBody({ r, size }) {
  const o = axOps(r);
  const per = v => (v === null || !isFinite(v) ? '—' : v.toFixed(3));
  const busy = o.points.filter(p => p.requests > 0);
  return (
    <>
      <AxNums items={[['切换次数', fmt.grouped(o.switches)], ['平均 · 次/请求', per(axPer(o.switches, o.src.requests))], ['最高 · 次/请求', per(busy.length ? Math.max(...busy.map(p => p.switchRate)) : null)]]} />
      <div className="pad"><AxChart kind="line" values={o.points.map(p => p.switchRate)} labels={o.points.map(p => p.label)} ticks={axOpsTicks(o)} h={size === 'full' ? 150 : 96} fmtY={v => v.toFixed(2)} nowLast={o.src.live && o.fine} /></div>
      <div className="ax-body-foot pad">曲线{axGrain(o)}。请求因限流、过载或错误换到另一个账号，记一次切换。</div>
    </>
  );
}

function AxLatencyBody({ r, size }) {
  const o = axOps(r);
  const max = Math.max(...AX_LAT_BUCKETS.map(x => x[2]));
  const none = o.src.requests < 0.5;
  const row = (label, p) => (
    <div className="ax-pctl-row"><span>{label}</span>{p.slice(0, size === 'full' ? 6 : 4).map((v, i) => <b key={i} className="num">{none ? '—' : axMs(v)}</b>)}</div>
  );
  return (
    <>
      {none ? <div className="ax-hist ax-hist-empty pad"><span>这个范围内没有成功请求</span></div> : <div className="ax-hist pad">
        {AX_LAT_BUCKETS.map(([key, label, p]) => (
          <div key={key} className="ax-hist-col">
            <span className="num ax-hist-n">{axPct(p, 0)}</span>
            <span className="ax-hist-bar"><i style={{ height: `${(p / max) * 100}%` }} /></span>
            <span className="ax-hist-l num">{label}</span>
          </div>
        ))}
      </div>}
      {!none && <div className="ax-body-foot pad">成功请求 <span className="num">{fmt.grouped(Math.round(o.src.requests))}</span> 次的总耗时分布</div>}
      <div className={cx('ax-pctl pad', size === 'full' && 'wide')}>
        <div className="ax-pctl-row ax-thead"><span /><span>P50</span><span>P90</span><span>P95</span><span>P99</span>{size === 'full' && <><span>平均</span><span>最长</span></>}</div>
        {row('总耗时', AX_PCTL.duration)}
        {row('首字', AX_PCTL.ttft)}
      </div>
    </>
  );
}

function AxErrTrendBody({ r, size }) {
  const o = axOps(r);
  const total = AX_ERR_PARTS.reduce((s, x) => s + x[1], 0);
  const stacks = o.buckets.map((b, i) => AX_ERR_PARTS.map(([, n], k) => b.errors * (n / total) * (1 + 0.25 * Math.sin(i * 1.7 + k))));
  return (
    <>
      <AxNums items={[['错误', fmt.grouped(o.errors)], ['错误率 · SLA', o.errorRateText], ['SLA 口径', fmt.grouped(o.sla)]]} />
      <div className="pad"><AxChart kind="stack" stacks={stacks} classes={AX_ERR_PARTS.map(x => x[2])} labels={o.src.buckets.map(b => b.short)} h={size === 'full' ? 150 : 100} fmtY={v => fmt.compact(Math.round(v))} anchorLast={o.src.unit === 'day'} {...axNowProps(o.src)} emptyText="这个范围内没有错误" /></div>
      <div className="ax-token-legend pad">
        {AX_ERR_PARTS.map(([label, n, cls]) => <span key={label}><i className={cx('ax-sq', cls)} />{label}<b className="num">{fmt.grouped(Math.round(o.errors * (n / total)))}</b></span>)}
      </div>
      <div className="ax-body-foot pad">后端{o.fine ? '每 5 分钟一桶，这里按小时合计' : '每小时一桶，这里按天合计'}。错误率 = SLA 口径错误 ÷（成功 + SLA 口径错误），不算业务限制（用户自己的余额、额度、频率限制）。</div>
    </>
  );
}

// Bar colours come from codeTone, the same rule as the status badge in the row: 429 amber, every other failure (504, 529 …) red;
// the business-limited part of a code is grey.
function AxErrDistBody({ ctx, r }) {
  const { skin } = ctx;
  const o = axOps(r);
  const k = o.errors / AX_ERR_TODAY;
  const top = AX_ERR_CODES[0][1];
  if (!o.errors) return <div className="empty pad">这个范围内没有错误</div>;
  return (
    <>
      {AX_ERR_CODES.map(([code, n, sla, biz]) => (
        <div key={code} className="ax-code-row pad">
          <skin.Code code={code} />
          <span className="ax-code-bar">
            {sla > 0 && <i className={cx('ax-code-sla', `tone-${codeTone(code)}`)} style={{ width: `${(sla / top) * 100}%` }} />}
            {biz > 0 && <i className="ax-code-biz" style={{ width: `${(biz / top) * 100}%` }} />}
          </span>
          <b className="num">{fmt.grouped(Math.round(n * k))}</b>
          <em className="num">{axPct(n / AX_ERR_TODAY, 0)}</em>
        </div>
      ))}
      <div className="ax-token-legend pad">
        <span><i className={cx('ax-sq ax-code-sla', `tone-${codeTone(429)}`)} />429 限流</span>
        <span><i className={cx('ax-sq ax-code-sla', `tone-${codeTone(504)}`)} />其他错误（含 504、529）</span>
        <span><i className="ax-sq ax-code-biz" />业务限制（不计 SLA）</span>
      </div>
    </>
  );
}

function AxTokenSpeedBody({ r, size }) {
  const [sort, setSort] = useState('requests');
  const focus = r.filter && r.filter.kind === 'model' ? r.filter.key : null;
  const inGroup = r.filter && r.filter.kind === 'group' ? new Set(axRankItems('model', r).map(x => x.key)) : null;
  const key = { requests: m => m.requests, speed: m => m.speed[0], ttft: m => -m.speed[1] }[sort];
  const sorted = AX_MODELS.filter(m => !inGroup || inGroup.has(m.key)).sort((a, b) => key(b) - key(a));
  const rows = sorted.slice(0, size === 'full' ? 9 : 5);
  if (focus && !rows.some(m => m.key === focus)) rows.push(sorted.find(m => m.key === focus));
  return (
    <>
      <div className="pad ax-body-ctl"><Segmented items={[{ key: 'requests', label: '按请求' }, { key: 'speed', label: '按速度' }, { key: 'ttft', label: '按首 Token' }]} value={sort} onChange={setSort} /></div>
      <div className="ax-speed">
        <div className="ax-speed-row ax-thead"><span>模型</span><span>输出/秒</span><span>首 Token</span><span>平均时长</span></div>
        {rows.map(m => (
          <div key={m.key} className={cx('ax-speed-row', focus === m.key && 'is-focus')}>
            <span className="mono ax-rt-name">{m.key}</span><span className="num">{m.speed[0]}</span><span className="num">{axMs(m.speed[1])}</span><span className="num">{axMs(m.speed[2])}</span>
          </div>
        ))}
      </div>
      {rows.length === 0 && <div className="empty pad">这个分组在窗口内没有模型用量</div>}
      <div className="ax-body-foot pad">{axSpeedNote(r)}{inGroup ? `只列「${r.filter.name}」用到的模型。` : ''}</div>
    </>
  );
}

const AX_TOPICS = [
  { key: 'revenue', label: '计费', icon: 'dollar' },
  { key: 'usage', label: '用量', icon: 'cube' },
  { key: 'ops', label: '运行', icon: 'pulse', note: '需开启运维监控' },
];

function axFastest() { return [...AX_MODELS].sort((a, b) => b.speed[0] - a.speed[0])[0]; }

// head(r) → [value, unit, label] for tiles; thumb(r) → { kind, values | stacks } for the tile sketch.
const AX_CHARTS = [
  { key: 'revenue', topic: 'revenue', title: '计费明细', sub: '实际 · 标准 · 逐段', icon: 'list', Body: AxRevenueBody,
    head: r => [fmt.money(r.actual), '', '实际扣费'], thumb: r => ({ kind: 'bars', values: r.buckets.map(b => b.actual) }) },
  { key: 'profit', topic: 'revenue', title: '利润明细', sub: '实际 − 账号成本 · 逐段', icon: 'columns', Body: AxProfitBody,
    head: r => [fmt.money(axProfitTotal(r).profit), '', '利润'], thumb: r => ({ kind: 'bars', values: axProfitRows(r).map(x => x.profit) }) },
  { key: 'tokens', topic: 'usage', title: 'Token 使用趋势', sub: '输入 · 输出 · 缓存', icon: 'cube', Body: AxTokensBody,
    head: r => [axCompact(r.tokens), 'Tokens', `缓存读占 ${axPct(axPer(r.mix[2], r.tokens), 0)}`], thumb: r => ({ kind: 'stack', stacks: r.buckets.map(b => b.mix), classes: AX_TOKEN_CLS }) },
  { key: 'userTrend', topic: 'usage', title: '用户用量趋势', sub: '前 12 位', icon: 'people', Body: AxUserTrendBody,
    head: r => { const u = axRankItems('user', r, 'tokens')[0]; return u ? [axCompact(u.tokens), 'Tokens', `第 1 · ${u.name}`] : ['—', '', '没有用户用量']; },
    thumb: r => ({ kind: 'line', values: r.buckets.map((b, i) => b.tokens * (1 + 0.3 * Math.sin(i * 1.4))) }) },
  { key: 'endpoints', topic: 'usage', title: '端点分布', sub: '入站 · 上游', icon: 'web', Body: AxEndpointsBody,
    head: r => {
      const rows = axEndpointRows(r, 'inbound');
      return rows.length ? [axPct(rows[0].requests / rows.reduce((s, x) => s + x.requests, 0), 0), '', `${rows[0].path} 占请求`] : ['—', '', '没有用量'];
    },
    thumb: r => ({ kind: 'hbar', values: axEndpointRows(r, 'inbound').map(x => x.requests) }) },
  { key: 'reqType', topic: 'usage', title: '请求类型', sub: '流式 · 同步 · WS', icon: 'wave', Body: AxReqTypeBody,
    head: r => [r.requests >= 0.5 ? axPct(AX_REQ_TYPES[0][1] / AX_REQ_TYPES.reduce((s, x) => s + x[1], 0), 0) : '—', '', '流式占请求'], thumb: () => ({ kind: 'hbar', values: AX_REQ_TYPES.map(x => x[1]) }) },
  // The same chart as the RPM / TPM card (own rolling window, ignores the page range); the tile reads the 1-hour window.
  { key: 'perf', topic: 'ops', title: 'RPM / TPM 趋势', sub: '近 1 / 6 / 24 小时', icon: 'signal', Body: AxPerfBody,
    head: r => { const p = axPerfSeries(1, r); const x = p.points[p.points.length - 1]; return [axPerfFmt('rpm', x.rpm), 'RPM', `最新一桶 · ${x.label}`]; },
    thumb: r => ({ kind: 'line', values: axPerfSeries(1, r).points.map(x => x.rpm) }) },
  { key: 'switch', topic: 'ops', title: '平均账号切换', sub: '次 / 请求', icon: 'refresh', Body: AxSwitchBody,
    head: r => { const o = axOps(r); const v = axPer(o.switches, o.src.requests); return [v === null ? '—' : v.toFixed(3), '', '平均 · 次/请求']; },
    thumb: r => ({ kind: 'line', values: axOps(r).points.map(p => p.switchRate) }) },
  { key: 'latency', topic: 'ops', title: '请求时长分布', sub: '分布 · 分位', icon: 'hourglass', Body: AxLatencyBody,
    head: r => [axOps(r).src.requests >= 0.5 ? axMs(AX_PCTL.duration[0]) : '—', '', 'P50 总耗时'], thumb: () => ({ kind: 'bars', values: AX_LAT_BUCKETS.map(x => x[2]) }) },
  { key: 'errTrend', topic: 'ops', title: '错误趋势', sub: '429 · 529 · 其他', icon: 'octagon', Body: AxErrTrendBody,
    head: r => [axOps(r).errorRateText, '', '错误率 · SLA'], thumb: r => ({ kind: 'bars', values: axOps(r).buckets.map(b => b.errors), tone: 'err' }) },
  { key: 'errDist', topic: 'ops', title: '错误分布', sub: '按状态码', icon: 'filter', Body: AxErrDistBody,
    head: r => [axOps(r).errors ? axPct(AX_ERR_CODES[0][1] / AX_ERR_TODAY, 0) : '—', '', '429 占错误'], thumb: () => ({ kind: 'hbar', values: AX_ERR_CODES.map(x => x[1]), tone: 'err' }) },
  { key: 'tokenSpeed', topic: 'ops', title: 'Token 请求统计', sub: '按模型速度', icon: 'gauge', Body: AxTokenSpeedBody,
    head: () => { const m = axFastest(); return [String(m.speed[0]), '输出/秒', `最快 · ${m.key}`]; },
    thumb: () => ({ kind: 'hbar', values: [...AX_MODELS].sort((a, b) => b.speed[0] - a.speed[0]).slice(0, 5).map(m => m.speed[0]) }) },
];

function axCharts(ctx) { return axOpsOn(ctx) ? AX_CHARTS : AX_CHARTS.filter(c => c.topic !== 'ops'); }

function AxThumb({ spec }) {
  const pid = useAxPatternId();
  const h = 38;
  if (spec.kind === 'hbar') {
    const max = Math.max(...spec.values);
    return <div className={cx('ax-thumb-h', spec.tone && 'err')}>{spec.values.slice(0, 5).map((v, i) => <i key={i} style={{ width: `${Math.max(3, (v / max) * 100)}%` }} />)}</div>;
  }
  const n = spec.kind === 'stack' ? spec.stacks.length : spec.values.length;
  const totals = spec.kind === 'stack' ? spec.stacks.map(s => s.reduce((a, b) => a + b, 0)) : spec.values;
  // Same signed scale as AxChart: a profit sketch with a loss dips below its zero line.
  const lo = spec.kind === 'bars' ? Math.min(0, ...totals) : 0;
  const max = Math.max(0, ...totals) * 1.05 || (lo < 0 ? 0 : 1);
  const min = lo * 1.05;
  const span = max - min || 1;
  const slot = 100 / n;
  const y = v => h - ((v - min) / span) * h;
  return (
    <svg className={cx('ax-thumb', spec.tone && 'err')} viewBox={`0 0 100 ${h}`} preserveAspectRatio="none" aria-hidden="true">
      {spec.kind === 'stack' && <AxHatchDef id={pid} />}
      {spec.kind === 'bars' && spec.values.map((v, i) => <rect key={i} className="ax-bar" x={i * slot + slot * 0.15} width={slot * 0.7} y={Math.min(y(v), y(0))} height={Math.abs(y(0) - y(v))} />)}
      {spec.kind === 'stack' && spec.stacks.map((s, i) => {
        let acc = 0;
        return s.map((v, k) => {
          const cls = spec.classes[k];
          const top = y(acc + v);
          const height = Math.max(0, y(acc) - top - (k > 0 ? 1 : 0));
          acc += v;
          return <rect key={`${i}${k}`} className={cls} style={cls === 'ax-k3' ? { fill: `url(#${pid})` } : undefined} x={i * slot + slot * 0.15} width={slot * 0.7} y={top} height={height} />;
        });
      })}
      {spec.kind === 'line' && <path className="ax-line" d={axPath(spec.values, max, h, min)} />}
    </svg>
  );
}

function AxTile({ c, r, onClick }) {
  const [value, unit, label] = c.head(r);
  const site = c.topic === 'ops' && axOpsScope(r).siteWide;
  return (
    <button className="ax-tile" onClick={onClick}>
      <span className="ax-tile-title">{c.title}</span>
      <span className="ax-tile-val"><b className="ax-fig num">{value}</b>{unit && <small>{unit}</small>}</span>
      <small className="ax-tile-label">{site && <em className="ax-site-tag">全站</em>}{label}</small>
      <span className="ax-tile-thumb"><AxThumb spec={c.thumb(r)} /></span>
    </button>
  );
}

function AxChartHead({ c, r }) {
  return (
    <>
      <div className="ax-card-head pad">
        <span className="ax-card-title">{c.title}</span>
        <span className="ax-card-meta">{axChartWindow(c, r)}{c.topic === 'ops' ? ' · 运维监控' : ''}</span>
      </div>
      {c.topic === 'ops' && <AxOpsNote r={r} />}
    </>
  );
}

// The window a chart shows: the page range, except the rolling ones (Token 请求统计: 30m … 30d; RPM / TPM: its own 1 / 6 / 24 h).
function axChartWindow(c, r) { return c.key === 'tokenSpeed' ? axSpeedWindow(r) : c.key === 'perf' ? '截至现在' : r.label; }

function axOffsetIn(box, el) { return el.getBoundingClientRect().top - box.getBoundingClientRect().top + box.scrollTop; }

/* ---------- 更多图表 · ① 按主题分组的图表列表（base）：主题跳转 + 范围菜单吸顶 ---------- */

function AxMoreList({ ctx, route }) {
  const ch = useAxChrome(ctx, route);
  const on = axOpsOn(ctx);
  const bar = useRef(null);
  const target = route.chart || route.topic;
  const startTopic = route.topic || (route.chart ? AX_CHARTS.find(c => c.key === route.chart).topic : 'revenue');
  const [active, setActive] = useState(startTopic);
  const box = () => bar.current && bar.current.closest('.scroll');
  const jump = id => {
    const b = box();
    const el = b && b.querySelector(`[data-ax="${id}"]`);
    if (b && el) b.scrollTop = axOffsetIn(b, el) - bar.current.offsetHeight - 6;
  };
  useEffect(() => {
    if (target) jump(target);
    const b = box();
    if (!b) return undefined;
    const spy = () => {
      if (b.scrollTop + b.clientHeight >= b.scrollHeight - 4 && b.scrollTop > 0) { setActive(AX_TOPICS[AX_TOPICS.length - 1].key); return; }
      const line = b.getBoundingClientRect().top + bar.current.offsetHeight + 40;
      let cur = AX_TOPICS[0].key;
      AX_TOPICS.forEach(t => { const el = b.querySelector(`[data-ax="${t.key}"]`); if (el && el.getBoundingClientRect().top <= line) cur = t.key; });
      setActive(cur);
    };
    b.addEventListener('scroll', spy);
    return () => b.removeEventListener('scroll', spy);
  }, []);
  return (
    <Screen ctx={ctx} nav={<NavBar ctx={ctx} back title="更多图表" subtitle={`${ctx.site} · ${ch.r.label}`} trailing={ch.filterBtn} />}>
      <div className="ax-jumpbar pad-x" ref={bar}>
        <div className="ax-jumps">
          {AX_TOPICS.map(t => (
            <button key={t.key} className={cx('chip', active === t.key && 'on')} onClick={() => { setActive(t.key); jump(t.key); }}>
              <span>{t.label}</span><b className="num">{t.key === 'ops' && !on ? '—' : AX_CHARTS.filter(c => c.topic === t.key).length}</b>
            </button>
          ))}
        </div>
        {ch.menu}
      </div>
      <div className="ax-range-cap ax-list-cap pad-x">
        <button className="ax-cap-btn" onClick={ch.openCustom} aria-label="选择日期范围"><AxCalGlyph /><span className="num">{ch.r.caption}</span><Icon name="chevron" size={11} weight={2.6} /></button>
        {ch.sel.filter && <AxFilterChip filter={ch.sel.filter} onClear={ch.clearFilter} />}
      </div>
      {AX_TOPICS.map(t => (
        <div key={t.key} data-ax={t.key} className="ax-topic">
          <div className="ax-topic-head pad-x"><span>{t.label}</span>{t.note && on && <small>{t.note}</small>}</div>
          {t.key === 'ops' && !on ? <div className="ax-card"><AxOpsOff /></div> : AX_CHARTS.filter(c => c.topic === t.key).map(c => (
            <section key={c.key} data-ax={c.key} className={cx('ax-card', route.chart === c.key && 'is-target')}>
              <AxChartHead c={c} r={ch.r} />
              <c.Body ctx={ctx} r={ch.r} size="card" />
            </section>
          ))}
        </div>
      ))}
      {ch.sheets}
    </Screen>
  );
}

/* ---------- 更多图表 · ② 单图全屏 + 左右切换（pager）---------- */

function AxDirectorySheet({ ctx, charts, current, onPick, onClose }) {
  const on = axOpsOn(ctx);
  return (
    <Sheet title="全部图表" onClose={onClose} leadingLabel="关闭" tall>
      <div className="ax-sheet">
        {AX_TOPICS.map(t => (
          <div key={t.key} className="ax-dir-group">
            <small>{t.label}{t.note && on ? ` · ${t.note}` : ''}</small>
            {t.key === 'ops' && !on ? <AxOpsOff /> : charts.map((c, i) => c.topic === t.key && (
              <button key={c.key} className={cx('ax-pick', i === current && 'is-current')} onClick={() => { onPick(i); onClose(); }}>
                <span className="lead-icon dim"><Icon name={c.icon} size={17} /></span><span>{c.title}</span><small>{c.sub}</small>
              </button>
            ))}
          </div>
        ))}
      </div>
    </Sheet>
  );
}

function AxMorePager({ ctx, route }) {
  const ch = useAxChrome(ctx, route);
  const charts = axCharts(ctx);
  const startKey = route.chart || (route.topic && (charts.find(c => c.topic === route.topic) || {}).key);
  const [index, setIndex] = useState(Math.max(0, charts.findIndex(c => c.key === startKey)));
  const [dir, setDir] = useState(false);
  const track = useRef(null);
  const n = charts.length;
  useEffect(() => { if (track.current) track.current.scrollLeft = index * track.current.clientWidth; }, []);
  const go = i => {
    const j = Math.max(0, Math.min(n - 1, i));
    setIndex(j);
    if (track.current) track.current.scrollTo({ left: j * track.current.clientWidth, behavior: 'smooth' });
  };
  const onScroll = e => { const j = Math.round(e.currentTarget.scrollLeft / e.currentTarget.clientWidth); if (j !== index) setIndex(j); };
  const c = charts[index];
  const topic = AX_TOPICS.find(t => t.key === c.topic);
  const cap = c.key === 'tokenSpeed' ? `${axSpeedWindow(ch.r)} · 滚动窗口` : c.key === 'perf' ? '截至现在 · 窗口在图里选' : ch.r.caption.replace(/ · 按(小时|天)$/, '');
  return (
    <div className="screen ax-pager-screen">
      <NavBar ctx={ctx} back title={c.title} subtitle={`${index + 1} / ${n} · ${topic.label}`} trailing={<><GlassButton icon="list" onClick={() => setDir(true)} />{ch.filterBtn}</>} />
      <div className="ax-pager-head">
        <div className="ax-pager-nav pad-x">
          <button className="ax-step" disabled={index === 0} onClick={() => go(index - 1)} aria-label="上一张"><Icon name="back" size={16} weight={2.4} /></button>
          <div className="ax-pager-mid">
            {ch.menu}
            <small className="num">{cap}</small>
          </div>
          <button className="ax-step" disabled={index === n - 1} onClick={() => go(index + 1)} aria-label="下一张"><Icon name="chevron" size={16} weight={2.4} /></button>
        </div>
        {ch.sel.filter && <div className="ax-pager-filter pad-x"><AxFilterChip filter={ch.sel.filter} onClear={ch.clearFilter} /></div>}
        <div className="ax-dots">{charts.map((x, i) => <button key={x.key} className={cx(i === index && 'on', x.topic === 'ops' && 'ops')} onClick={() => go(i)} aria-label={x.title} />)}</div>
      </div>
      <div className="ax-pages" ref={track} onScroll={onScroll}>
        {charts.map(x => (
          <div key={x.key} className="ax-page scroll">
            <div className="ax-page-card">{x.topic === 'ops' && <AxOpsNote r={ch.r} />}<x.Body ctx={ctx} r={ch.r} size="full" /></div>
          </div>
        ))}
      </div>
      {dir && <AxDirectorySheet ctx={ctx} charts={charts} current={index} onPick={go} onClose={() => setDir(false)} />}
      {ch.sheets}
    </div>
  );
}

/* ---------- 更多图表 · ③ 图表目录网格（catalog）→ 单图页 ---------- */

// A deep link to one chart (from 计费明细 / 利润明细 or a directory row) opens that chart's page; otherwise show the grid.
function AxMoreCatalog({ ctx, route }) {
  return route.chart ? <AxChartScreen ctx={ctx} route={route} /> : <AxCatalogGrid ctx={ctx} route={route} />;
}

function AxCatalogGrid({ ctx, route }) {
  const ch = useAxChrome(ctx, route);
  const on = axOpsOn(ctx);
  const scroller = useRef(null);
  useEffect(() => {
    const box = scroller.current && scroller.current.closest('.scroll');
    const el = box && route.topic && box.querySelector(`[data-ax="${route.topic}"]`);
    if (el) box.scrollTop = axOffsetIn(box, el) - 8;
  }, []);
  return (
    <Screen ctx={ctx} nav={<NavBar ctx={ctx} back title="更多图表" subtitle={`${ctx.site} · ${ch.r.label}`} trailing={ch.filterBtn} />}>
      <div ref={scroller}>{ch.bar}</div>
      {AX_TOPICS.map(t => (
        <div key={t.key} data-ax={t.key} className="ax-topic">
          <div className="ax-topic-head pad-x"><span>{t.label}</span>{t.note && on && <small>{t.note}</small>}</div>
          {t.key === 'ops' && !on ? <div className="ax-card"><AxOpsOff /></div> : (
            <div className="ax-tiles pad-x">
              {AX_CHARTS.filter(c => c.topic === t.key).map(c => <AxTile key={c.key} c={c} r={ch.r} onClick={() => ctx.push({ kind: 'analyticsChart', chart: c.key })} />)}
            </div>
          )}
        </div>
      ))}
      {ch.sheets}
    </Screen>
  );
}

function AxChartScreen({ ctx, route }) {
  const ch = useAxChrome(ctx, route);
  const c = AX_CHARTS.find(x => x.key === route.chart) || AX_CHARTS[0];
  const t = AX_TOPICS.find(x => x.key === c.topic);
  return (
    <Screen ctx={ctx} nav={<NavBar ctx={ctx} back title={c.title} subtitle={`${t.label} · ${axChartWindow(c, ch.r)}`} trailing={ch.filterBtn} />}>
      {/* RPM / TPM picks its own rolling window inside the chart, so the page's range bar would not apply; only the filter chip stays. */}
      {c.key === 'perf' ? (ch.sel.filter && <div className="ax-filter-row ax-perf-filter pad-x"><AxFilterChip filter={ch.sel.filter} onClear={ch.clearFilter} /></div>) : ch.bar}
      {c.topic === 'ops' && !axOpsOn(ctx) ? <div className="ax-page-card"><AxOpsOff /></div> : (
        <div className="ax-page-card">{c.topic === 'ops' && <AxOpsNote r={ch.r} />}<c.Body ctx={ctx} r={ch.r} size="full" /></div>
      )}
      {ch.sheets}
    </Screen>
  );
}

/* ---------- registration ---------- */

mvRegister('screen:analytics', 'base', AxCardsScreen);
mvRegister('screen:analytics', 'tabs', AxTabsScreen);
mvRegister('screen:analytics', 'report', AxReportScreen);
mvRegister('screen:analyticsMore', 'base', AxMoreList);
mvRegister('screen:analyticsMore', 'pager', AxMorePager);
mvRegister('screen:analyticsMore', 'catalog', AxMoreCatalog);
mvRegister('screen:analyticsChart', 'base', AxChartScreen);
mvRegister('screen:analyticsRank', 'base', AxRankScreen);
mvRegister('screen:analyticsModel', 'base', AxModelScreen);
