/* 首页（今日）变体 · 第 2 轮。注册为 today 槽的 'x'，同一个组件按 ctx.v 的开关画出不同样子：
   homeRev        计费区：'ticker'（已定，顶部 6 格）| 'line'（= 现有，顶部一行）| 'card'（B 式计费卡，放在待处理之后）| 'hero'（顶部大数 + 图，待处理紧随其后）
                  （评审 2026-10-18 第 4 条：“营收”统一改叫“计费”；开关名 homeRev 不改，免得各对比页的 initial 失效）
   homePend       待处理粒度：'merge'（= 现有，受限账号合并一条）| 'each'（逐个列出，带倒计时与“恢复状态”）| 'group'（按分组聚合）
   calm           true = 假设没有任何异常（只影响首页这一屏的演示数据）；'soft' = 只剩限流 / 临时不可调度（自检平静布局的滞后规则）
   homeCalm       'stage' = 没事时换成专门的平静布局；不设 = 沿用计费布局，只把待处理收起
   homeCalmQueue  'section' = 收起后仍保留“待处理 0 项”分区；不设 = 收成一张“全部正常”状态卡
   数据来源：分组可用数 / 总数 ← ops/account-availability（按分组的 available / total）；错误、过载、限流、临时不可调度 ← 同一接口逐账号的
   has_error、is_overloaded、is_rate_limited、temp_unschedulable_until，账号的全部分组归属 ← admin/accounts（account_groups 多对多）；
   分组卡阈值 ← ops/alert-rules 里按分组配置的 group_available_ratio / group_available_accounts；告警 ← ops/alert-events（只带分组 / 平台维度），
   手动解决 ← PUT alert-events/:id/status，静默 ← POST alert-silences（1 小时 / 24 小时 / 7 天，与 Web 一致）；
   每小时扣费与昨日对比 ← dashboard/trend；账号今日扣费 ← accounts/today-stats/batch；恢复 ← accounts/:id/recover-state；分组内账号 ← admin/accounts?group=。
   演示数据一律读共享 DEMO：分组与排序 ← DEMO.groups（sortOrder），成员关系只看 accounts[].groups（跨分组：#1、#2 高级组 + Claude Code 组，
   #7 标准组 + 企业专线），本文件不再改写任何账号。调度开关（schedulable）与运行状态分开：限流 / 过载 / 临时不可调度的账号被手动停调度后，
   状态牌和倒计时照常，另加“已停止调度”标记（schedLabel）；计数与核心 accountCounts / deriveAttention 一致（仍算受限）。平静布局里它和
   其他限流账号一起留在“自动恢复中”那一行，名字后注明“（已停止调度）”：限流到点会自己解除，但账号之后仍不参与调度。
   待处理另有两条资金类核对：充值结果待核对（users[].pending）、兑换码生成结果待核对（ctx.redeemPending → {kind:'redeem', reconcile:true}）；
   任何一条都会结束平静布局。
   告警详情页注册为槽 screen:alert 的 base（覆盖核心的告警列表页，BUILDER_GUIDE 约定由概览负责人做）：首页告警行、分组卡告警行与 core
   deriveAttention 的告警项都进 {kind:'alert', id}；告警读 ctx.alerts（DEMO.alerts 加上这台手机的处理），手动解决 / 静默走
   ctx.resolveAlert / ctx.silenceAlert，与监控 · 告警、账号分组视图的告警牌是同一份状态；颜色一律 alertTone，静默时长用核心 ALERT_SILENCE。
   “利润”= profitOf()（实际扣费 − 账号成本），健康词 healthWord()，成功率 successRate()、错误率 errorRate()，都用核心的，不再各自计算。
   时间窗口：顶部 6 格 = 今日实际扣费、请求、错误率、利润、RPM、TPM（用户评审 2026-10-18 第 1、2 条：健康换成 TPM）。今日实际扣费 /
   请求 / 利润 是今天 00:00 起；错误率（errorRate() = DEMO.run.errorRate）、RPM、TPM 口径仍是近 5 分钟，
   但首页任何地方都不再写“近 5 分钟”这类窗口后缀（格内标签只写“错误率”“RPM”“TPM”，运行区、渠道区的标题也不写窗口）。
   统计分析 · 今天才用今日 SLA 口径 errorRate('today')。既然不写窗口，就靠分区区分：写在“00:00 起”区里的数一律今日口径
   （successRate('today') / errorRate('today')），近 5 分钟的数（RPM、TPM、错误率、健康分）不放进“00:00 起”的区。健康分只留在“运行”区。
   RPM / TPM 的来源 = 点进去的统计分析“RPM / TPM 趋势”同一个接口：ops/dashboard/throughput-trend（近 1 小时，1 分钟一桶）最近 5 桶的
   request_count、token_consumed 之和 ÷ 5（RPM 取整）。所以 RPM 含成功和错误请求，TPM 是成功请求的含缓存 Tokens（input + output +
   cache_creation + cache_read）。演示：(230 成功 + 2 错误) ÷ 5 = 46、1,200K ÷ 5 = 240K（= DEMO.today.rpm / tpm），也正好等于图上
   最新一桶 09:40。不用 dashboard/stats 的 tpm：它只算 input + output、不含缓存，同一时刻约 95K，和点进去的图差 2.5 倍
   （现有 App 首页读的是 stats.tpm，落地时改成这里的口径）。
   站点没开运维监控时 throughput-trend 不可用，两格退回 dashboard/stats 的 rpm / tpm（只算成功请求、不含缓存）；这时点进去是
   “运维监控未开启”提示，没有图可比，不会出现两个数对不上。
   点 6 格进统计分析；点 RPM、TPM 两格进 {kind:'analytics', focus:'perf', metric:'rpm' | 'tpm'}（统计分析的“RPM / TPM 趋势”，
   并切到点的那个指标——图里的指标在本机记住，不带 metric 会停在上次看的那个）。
   SwiftUI 落地：大数字加 .minimumScaleFactor(0.5).lineLimit(1)；行内小按钮视觉高 30pt，用 .frame(minHeight: 44) + .contentShape 扩大点击区，
   List 里设 .buttonStyle(.borderless)，避免和整行导航冲突。 */

const VT_TIMED = ['overloaded', 'rate_limited', 'temp_unsched'];
// Auto-recovering blocks: they keep the calm layout. Errors, overloads, open alerts and pending top-ups end it.
const VT_TRANSIENT = ['rate_limited', 'temp_unsched'];
// Fallback card threshold for a group without its own availability rule: fewer than half of its accounts can be scheduled.
const VT_SHORT_RATIO = 0.5;
// Availability rules are scoped to one group (rule.filters.group_id → DEMO.groups[].id). Read from the rules behind DEMO.alerts (today
// only #35: 高级组 可用比例 < 60%), not a local copy; threshold_value is stored with its unit ('60%').
const VT_AVAIL_METRICS = ['group_available_ratio', 'group_available_accounts'];
const VT_GROUP_RULES = DEMO.alerts
  .filter(x => x.group && VT_AVAIL_METRICS.includes(x.metricType))
  .map(x => ({ groupId: (groupOf(x.group) || {}).id, metric: x.metricType, op: x.op, threshold: parseFloat(x.threshold) }));
// Up to this many members the meter draws one cell per account; larger groups get proportional segments.
const VT_METER_CELLS_MAX = 20;
// Same order as the per-account cells: available first, then STATE_ORDER.
const VT_METER_BUCKETS = [
  ['可用', 'ok', a => a.state === 'normal'],
  ['错误', 'critical', a => a.state === 'error'],
  ['过载中', 'critical', a => a.state === 'overloaded'],
  ['限流中', 'caution', a => a.state === 'rate_limited'],
  ['临时不可调度', 'caution', a => a.state === 'temp_unsched'],
  ['暂停·停用', 'neutral', a => a.state === 'paused' || a.state === 'inactive'],
];
// Home drill-downs pushed on the today stack (core renders slot screen:<kind>). 'vtAlert' is the round-2 alias of {kind:'alert'}
// (no id = DEMO.alert); the home itself now pushes {kind:'alert', id}, the route core's deriveAttention uses.
const VT_GROUP_ROUTE = 'vtGroupAccounts';
const VT_ALERT_ROUTE = 'vtAlert';
const VT_CHANNEL_WORDS = [['ok', '可用'], ['caution', '性能下降'], ['critical', '不可用'], ['neutral', '未知']];
// Where the 6 cells lead: the analytics page, and for the live rates its RPM / TPM trend (the analytics owner's focus), switched to the
// metric of the cell tapped (route.metric) — the chart remembers its metric per phone, so without it a tap on TPM could open on RPM.
const VT_ANALYTICS_ROUTE = { kind: 'analytics' };
const VT_PERF_ROUTE_RPM = { kind: 'analytics', focus: 'perf', metric: 'rpm' };
const VT_PERF_ROUTE_TPM = { kind: 'analytics', focus: 'perf', metric: 'tpm' };

/* ---------- 告警状态：读写核心的 ctx.alerts / alertStatus / resolveAlert / silenceAlert ---------- */

// The event as this phone sees it (manual_resolved after 手动解决, silencedUntil after 静默…); unknown id → the home's own (#41).
function vtAlertOf(ctx, id) {
  return ctx.alerts.find(x => x.id === id) || ctx.alerts.find(x => x.id === DEMO.alert.id) || DEMO.alert;
}

function vtSilencedNote(ctx, id) {
  return ctx.alertStatus(id).silencedUntil ? ' · 已静默' : '';
}

/* ---------- model ---------- */

// Calm is a what-if for the home screen only. true: every blocked account reads as normal, no alert, no pending top-up.
// 'soft': only errors and overloads clear, so rate limits stay and the calm layout's tolerance can be checked.
// A pending redeem batch is opt-in (initial.redeemPending), so it stays in either what-if: the calm layout must give way to it.
function vtModel(ctx) {
  const v = ctx.v || {};
  const calm = v.calm === true ? 'all' : v.calm === 'soft' ? 'soft' : null;
  const cleared = calm === 'all' ? NEEDS_ACTION : calm === 'soft' ? ['error', 'overloaded'] : [];
  const list = Object.values(ctx.accounts).map(a => (cleared.includes(a.state) ? { ...a, state: 'normal', schedulable: true } : a));
  const channels = calm ? DEMO.channels.map(c => (c.state === 'caution' || c.state === 'critical' ? { ...c, state: 'ok' } : c)) : DEMO.channels;
  return {
    v,
    calm,
    list,
    channels,
    alertOpen: ctx.alertOpen && !calm,
    pendingUser: calm ? null : Object.values(ctx.users).find(u => u.pending) || null,
    redeem: ctx.redeemPending || null,
    normalCount: list.filter(a => a.state === 'normal').length,
  };
}

// Only problems a human must act on end the calm layout: errors, overloads, a firing alert and either money check
// (top-up or redeem batch). Rate limits recover by themselves within minutes.
function vtIsBusy(m) {
  return m.alertOpen || Boolean(m.pendingUser) || Boolean(m.redeem) || m.list.some(a => a.state === 'error' || a.state === 'overloaded');
}

// Auto-recovering blocks keep the calm layout. A blocked account stopped by hand still counts here (its limit still clears
// by itself); its row says it stays out of scheduling afterwards.
function vtTransient(list) {
  return list.filter(a => VT_TRANSIENT.includes(a.state));
}

function vtUntil(ctx, a) {
  return fmt.clock(DEMO_CLOCK_BASE + (ctx.elapsed + (remaining(a, ctx.elapsed) || 0)) * 1000);
}

function vtByUrgency(ctx) {
  return (a, b) => {
    const rank = s => (toneOf(s) === 'critical' ? 0 : 1);
    return rank(a.state) - rank(b.state) || (remaining(a, ctx.elapsed) || 0) - (remaining(b, ctx.elapsed) || 0);
  };
}

function vtCompare(value, op, threshold) {
  return op === '<' ? value < threshold : op === '<=' ? value <= threshold : op === '>' ? value > threshold : value >= threshold;
}

// A group is short when the site's own rule for it says so; without a rule the client falls back to "below half".
function vtShortOf(group, available, total) {
  const rule = VT_GROUP_RULES.find(r => r.groupId === group.id);
  if (!rule) return available / total < VT_SHORT_RATIO;
  const value = rule.metric === 'group_available_ratio' ? (available / total) * 100 : available;
  return vtCompare(value, rule.op, rule.threshold);
}

// Groups with problems, cards first (lowest availability first, ties in the site's group order), then the groups that still
// have capacity. A cross-group account is listed once, in the first group above that holds it (the lowest-availability card);
// every other group still counts it and says where it is listed.
function vtGroups(m) {
  const ratio = g => g.available / g.members.length;
  const groups = [...DEMO.groups].sort((a, b) => a.sortOrder - b.sortOrder).map(def => {
    const members = groupMembers(m.list, def.id);
    const problems = members.filter(a => NEEDS_ACTION.includes(a.state)).sort((a, b) => STATE_ORDER.indexOf(a.state) - STATE_ORDER.indexOf(b.state));
    const { available } = groupAvailability(m.list, def.id);
    const alert = m.alertOpen && DEMO.alert.group === def.name ? DEMO.alert : null;
    const lacking = members.length > 0 && vtShortOf(def, available, members.length);
    return { id: def.id, name: def.name, members, problems, available, alert, lacking, short: lacking || Boolean(alert) };
  }).filter(g => g.members.length && (g.problems.length || g.alert))
    .sort((a, b) => Number(b.short) - Number(a.short) || ratio(a) - ratio(b));
  const home = {};
  groups.forEach(g => g.problems.forEach(a => { if (!(a.id in home)) home[a.id] = g.name; }));
  return groups.map(g => ({
    ...g,
    listed: g.problems.filter(a => home[a.id] === g.name),
    elsewhere: g.problems.filter(a => home[a.id] !== g.name).map(a => ({ a, at: home[a.id] })),
  }));
}

function vtElsewhereText(g) {
  if (!g.elsewhere.length) return '';
  const at = [...new Set(g.elsewhere.map(e => e.at))].join('、');
  return `${g.listed.length ? '另有 ' : ''}${g.elsewhere.length} 个跨组账号见${at}`;
}

function vtOtherGroups(a, here) {
  const others = a.groups.filter(name => name !== here);
  return others.length ? ` · 也在${others.join('、')}` : '';
}

// Rows with an inline button have room for one group name; the rest collapse to "+N" (the account detail lists them all).
function vtGroupsShort(a) {
  if (!a.groups.length) return '未分组';
  return a.groups.length > 1 ? `${a.groups[0]} +${a.groups.length - 1}` : a.groups[0];
}

function VtModelNote({ a }) {
  const n = a.modelLimits ? a.modelLimits.length : 0;
  return n ? <> · <span className="tone-model tone-text">模型限流 {n}</span></> : null;
}

// Same mark and place as core's AccountRow: it leads the note so truncation only ever cuts the tail.
function VtSchedMark({ a }) {
  const label = schedLabel(a);
  return label ? <><span className="sched-mark">{label}</span> · </> : null;
}

// The group itself: the decided group detail (screen:group, from the groups page) when this build has it,
// otherwise the home's own "accounts of this group" list.
function vtGroupRoute(name) {
  const g = groupOf(name);
  return g && MV.slots['screen:group'] ? { kind: 'group', id: g.id } : { kind: VT_GROUP_ROUTE, group: g ? g.name : name };
}

/* ---------- 待处理：行 ---------- */

// Same item, tone and route as core's deriveAttention alert entry ({kind:'alert', id} → this file's alert page).
function VtAlertRow({ ctx }) {
  const { skin } = ctx;
  const tone = alertTone(DEMO.alert);
  return (
    <Row skin={skin} tone={tone} className={`tone-${tone}`} lead={<span className="lead-icon"><Icon name="bell" /></span>}
      onClick={() => ctx.push({ kind: 'alert', id: DEMO.alert.id })}>
      <div className="row-top"><span className="row-title">{DEMO.alert.title}</span><skin.Badge tone={tone} label={DEMO.alert.level} /></div>
      <div className="row-meta">{DEMO.alert.detail}{vtSilencedNote(ctx, DEMO.alert.id)}</div>
    </Row>
  );
}

function VtErrorRow({ ctx, a }) {
  const { skin } = ctx;
  return (
    <Row skin={skin} tone="critical" className="tone-critical vt-hit" lead={<skin.Glyph state="error" />} onClick={() => ctx.push({ kind: 'account', id: a.id })}>
      <div className="row-top"><span className="row-title">{a.name}</span><skin.Badge state="error" /></div>
      <div className="row-note">{a.error}</div>
      <div className="row-foot"><span className="row-meta">{a.platform} · {a.errorAgo}</span><ActionButton small label="测试" icon="wave" onClick={() => ctx.openSheet({ kind: 'test', id: a.id })} /></div>
    </Row>
  );
}

function VtOverloadRow({ ctx, a }) {
  const { skin } = ctx;
  return (
    <Row skin={skin} tone="critical" className="tone-critical" lead={<skin.Glyph state="overloaded" />} onClick={() => ctx.push({ kind: 'account', id: a.id })}>
      <div className="row-top"><span className="row-title">{a.name}</span><skin.Badge state="overloaded" secs={remaining(a, ctx.elapsed)} /></div>
      <div className="row-meta"><span className="vt-clip"><VtSchedMark a={a} />{a.cause} · {a.platform}</span></div>
    </Row>
  );
}

// Accounts stopped by hand get their own line, mark first (as in core's AccountRow), so a long name list can only
// truncate the names, never the mark. Their limit still clears on time; the account detail says they stay out of scheduling.
function VtLimitedRow({ ctx, limited }) {
  const { skin } = ctx;
  const earliest = Math.min(...limited.map(a => remaining(a, ctx.elapsed)));
  const stopped = limited.filter(a => schedLabel(a));
  return (
    <Row skin={skin} tone="caution" className="tone-caution" lead={<skin.Glyph state="rate_limited" />} onClick={() => ctx.switchTab('accounts', { filter: 'limited' })}>
      <div className="row-top"><span className="row-title">受限 {limited.length} 个账号</span><span className="row-right num tone-text">最早 {fmt.countdown(earliest)}</span></div>
      <div className="row-meta">{limited.map(a => a.name).join('、')}</div>
      {stopped.length > 0 && (
        <div className="row-meta vt-sched-line"><span className="vt-clip"><span className="sched-mark">已停止调度</span> · {stopped.map(a => a.name).join('、')}</span></div>
      )}
    </Row>
  );
}

// One row per blocked account: countdown on the lamp, recovery time in the note, "恢复状态" inline.
function VtTimedRow({ ctx, a }) {
  const { skin } = ctx;
  const tone = toneOf(a.state);
  return (
    <Row skin={skin} tone={tone} className={`tone-${tone} vt-hit`} lead={<skin.Glyph state={a.state} />} onClick={() => ctx.push({ kind: 'account', id: a.id })}>
      <div className="row-top"><span className="row-title">{a.name}</span><skin.Badge state={a.state} secs={remaining(a, ctx.elapsed)} /></div>
      <div className="row-note"><VtSchedMark a={a} />{a.cause} · <span className="num">{vtUntil(ctx, a)}</span> 恢复<VtModelNote a={a} /></div>
      <div className="row-foot">
        <span className="row-meta">{a.platform} · {vtGroupsShort(a)}</span>
        <ActionButton small label="恢复状态" icon="restore" onClick={() => confirmRecover(ctx, a)} />
      </div>
    </Row>
  );
}

function VtPendingRow({ ctx, u }) {
  const { skin } = ctx;
  return (
    <Row skin={skin} tone="caution" className="tone-caution" lead={<span className="lead-icon"><Icon name="docCheck" /></span>}
      onClick={() => ctx.push({ kind: 'user', id: u.id })}>
      <div className="row-top"><span className="row-title">充值结果待核对</span><skin.Money value={DEMO.pendingOp.amount} size="m" /></div>
      <div className="row-meta">{u.name} · {DEMO.pendingOp.ago} · 未确认是否入账</div>
    </Row>
  );
}

// Core's attention item for a redeem batch whose answer never came back (deriveAttention kind 'redeemPending'): same shape as the
// top-up check, and it opens the redeem list straight into 核对 ({kind:'redeem', reconcile:true}).
function VtRedeemRow({ ctx, rp }) {
  const { skin } = ctx;
  const item = deriveAttention(ctx).find(i => i.kind === 'redeemPending');
  const route = (item && item.route) || { kind: 'redeem', reconcile: true };
  return (
    <Row skin={skin} tone="caution" className="tone-caution" lead={<span className="lead-icon"><Icon name="docCheck" /></span>}
      onClick={() => ctx.push(route)}>
      <div className="row-top"><span className="row-title">{(item && item.title) || '兑换码生成结果待核对'}</span>{rp.total !== null && rp.total !== undefined && <skin.Money value={rp.total} size="m" />}</div>
      <div className="row-meta">{rp.count} 个 · {rp.ago} · 未确认是否生成</div>
    </Row>
  );
}

/* ---------- 待处理：按分组聚合 ---------- */

function VtSubRow({ ctx, a, group }) {
  const { skin } = ctx;
  const meta = STATE_META[a.state];
  const secs = remaining(a, ctx.elapsed);
  return (
    <div className={cx('vt-sub tappable vt-hit', `tone-${meta.tone}`)} onClick={() => ctx.push({ kind: 'account', id: a.id })}>
      <span className="row-lead"><skin.Glyph state={a.state} /></span>
      <span className="vt-sub-name">{a.name}</span>
      {meta.timed
        ? <ActionButton small label="恢复状态" icon="restore" onClick={() => confirmRecover(ctx, a)} />
        : <ActionButton small label="测试" icon="wave" onClick={() => ctx.openSheet({ kind: 'test', id: a.id })} />}
      <span className="vt-sub-note">
        <b className="tone-text">{meta.label}{meta.timed && <span className="num"> {fmt.countdown(secs)}</span>}</b>
        {' · '}<VtSchedMark a={a} />{a.state === 'error' ? a.error : `${a.cause} · ${vtUntil(ctx, a)} 恢复`}<VtModelNote a={a} />{vtOtherGroups(a, group)}
      </span>
    </div>
  );
}

// One cell per account for small groups; proportional segments by status once a group is too large for cells.
function VtMeter({ members }) {
  if (members.length <= VT_METER_CELLS_MAX) {
    const cells = [...members].sort((a, b) => (a.state === 'normal' ? -1 : 0) - (b.state === 'normal' ? -1 : 0) || STATE_ORDER.indexOf(a.state) - STATE_ORDER.indexOf(b.state));
    return <div className="vt-meter" aria-hidden="true">{cells.map(a => <i key={a.id} className={`tone-${toneOf(a.state)}`} />)}</div>;
  }
  const parts = VT_METER_BUCKETS.map(([label, tone, test]) => ({ label, tone, n: members.filter(test).length })).filter(p => p.n > 0);
  return (
    <div className="vt-meter is-ratio" role="img" aria-label={parts.map(p => `${p.label} ${p.n}`).join('，')}>
      {parts.map(p => <i key={p.label} className={`tone-${p.tone}`} style={{ flexGrow: p.n }} />)}
    </div>
  );
}

function VtGroupCard({ ctx, g }) {
  const { skin } = ctx;
  const [open, setOpen] = useState(Boolean(ctx.v && ctx.v.homeGroupOpen));
  const tone = g.problems.some(a => toneOf(a.state) === 'critical') || g.lacking ? 'critical' : 'caution';
  const tally = STATE_ORDER.filter(s => g.listed.some(a => a.state === s)).map(s => ({ s, n: g.listed.filter(a => a.state === s).length }));
  const elsewhere = vtElsewhereText(g);
  return (
    <div className={cx('row vt-grp', skin.rowClass(tone), `tone-${tone}`)}>
      <button className="vt-grp-head" onClick={() => ctx.push(vtGroupRoute(g.name))}>
        <span className="row-lead"><span className="lead-icon"><Icon name="group" /></span></span>
        <span className="vt-grp-name"><b>{g.name}</b><small>{g.lacking ? '可用账号不足' : '告警中'}</small></span>
        <span className={cx('vt-grp-count', g.lacking && 'is-short')}><b className="vt-figure">{g.available}</b><span className="num">/{g.members.length}</span> 可用</span>
        <span className="row-chev"><Icon name="chevron" size={13} weight={2.6} /></span>
      </button>
      <VtMeter members={g.members} />
      {g.alert && (
        <button className="vt-grp-alert" onClick={() => ctx.push({ kind: 'alert', id: g.alert.id })}>
          <span className={`tone-${alertTone(g.alert)} vt-grp-alert-icon`}><Icon name="bell" size={16} /></span>
          <span className="vt-grp-alert-text"><b>{g.alert.title.replace(g.name, '')}</b><small>{g.alert.detail}{vtSilencedNote(ctx, g.alert.id)}</small></span>
          <skin.Badge tone={alertTone(g.alert)} label={g.alert.level} />
          <span className="row-chev"><Icon name="chevron" size={13} weight={2.6} /></span>
        </button>
      )}
      {g.listed.length > 0 && (
        <button className="vt-grp-fold" onClick={() => setOpen(o => !o)} aria-expanded={open}>
          <span className="vt-grp-fold-text">{g.listed.length} 个账号受影响</span>
          <span className="vt-tally" aria-label={tally.map(t => `${STATE_META[t.s].label} ${t.n}`).join('，')}>
            {tally.map(t => <span key={t.s} className={`tone-${STATE_META[t.s].tone}`}><Icon name={STATE_META[t.s].icon} size={14} weight={2.3} /><b className="num">{t.n}</b></span>)}
          </span>
          <span className="vt-grp-fold-more">{open ? '收起' : '展开'}<Icon name={open ? 'chevronUp' : 'chevronDown'} size={13} weight={2.6} /></span>
        </button>
      )}
      {open && <div className="vt-grp-subs">{g.listed.map(a => <VtSubRow key={a.id} ctx={ctx} a={a} group={g.name} />)}</div>}
      {elsewhere && <div className={cx('vt-grp-elsewhere', !g.listed.length && 'is-alone')}>{elsewhere}</div>}
    </div>
  );
}

// Groups that still have capacity: one quiet line under "其他分组", not counted as a pending item.
function VtGroupQuiet({ ctx, g }) {
  const { skin } = ctx;
  const names = g.listed.map(a => `${a.name} ${STATE_META[a.state].label}${STATE_META[a.state].timed ? ` ${fmt.countdown(remaining(a, ctx.elapsed))}` : ''}${schedLabel(a) ? `（${schedLabel(a)}）` : ''}`);
  const elsewhere = vtElsewhereText(g);
  return (
    <Row skin={skin} tone="none" className="vt-quiet" lead={<span className="lead-icon dim"><Icon name="group" /></span>} onClick={() => ctx.push(vtGroupRoute(g.name))}>
      <div className="row-top"><span className="row-title">{g.name}</span><span className="row-right vt-quiet-count"><b className="num">{g.available}/{g.members.length}</b> 可用</span></div>
      <div className="row-meta">{[...names, elsewhere].filter(Boolean).join(' · ')}</div>
    </Row>
  );
}

/* ---------- 待处理：三种粒度 ---------- */

// The two money checks close every granularity, in core's order (deriveAttention: top-up, then redeem batch).
function vtMoneyChecks(ctx, m) {
  const rows = [];
  if (m.pendingUser) rows.push(<VtPendingRow key="pending" ctx={ctx} u={m.pendingUser} />);
  if (m.redeem) rows.push(<VtRedeemRow key="redeem" ctx={ctx} rp={m.redeem} />);
  return rows;
}

function vtMergeItems(ctx, m) {
  const items = [];
  const limited = vtTransient(m.list);
  if (m.alertOpen) items.push(<VtAlertRow key="alert" ctx={ctx} />);
  m.list.filter(a => a.state === 'error').forEach(a => items.push(<VtErrorRow key={a.id} ctx={ctx} a={a} />));
  m.list.filter(a => a.state === 'overloaded').forEach(a => items.push(<VtOverloadRow key={a.id} ctx={ctx} a={a} />));
  if (limited.length) items.push(<VtLimitedRow key="limited" ctx={ctx} limited={limited} />);
  vtMoneyChecks(ctx, m).forEach(row => items.push(row));
  return { items, quiet: [] };
}

function vtEachItems(ctx, m) {
  const items = [];
  if (m.alertOpen) items.push(<VtAlertRow key="alert" ctx={ctx} />);
  m.list.filter(a => a.state === 'error').forEach(a => items.push(<VtErrorRow key={a.id} ctx={ctx} a={a} />));
  m.list.filter(a => VT_TIMED.includes(a.state)).sort(vtByUrgency(ctx)).forEach(a => items.push(<VtTimedRow key={a.id} ctx={ctx} a={a} />));
  vtMoneyChecks(ctx, m).forEach(row => items.push(row));
  return { items, quiet: [] };
}

function vtGroupItems(ctx, m) {
  const groups = vtGroups(m);
  const loose = m.list.filter(a => NEEDS_ACTION.includes(a.state) && !a.groups.length);
  const items = groups.filter(g => g.short).map(g => <VtGroupCard key={`g-${g.name}`} ctx={ctx} g={g} />);
  loose.forEach(a => items.push(a.state === 'error' ? <VtErrorRow key={a.id} ctx={ctx} a={a} /> : <VtTimedRow key={a.id} ctx={ctx} a={a} />));
  if (m.alertOpen && !groups.some(g => g.alert)) items.push(<VtAlertRow key="alert" ctx={ctx} />);
  vtMoneyChecks(ctx, m).forEach(row => items.push(row));
  const quiet = groups.filter(g => !g.short).map(g => <VtGroupQuiet key={`q-${g.name}`} ctx={ctx} g={g} />);
  return { items, quiet };
}

/* ---------- 计费与用量 ---------- */

// Hourly actual charge: today as a line (or bars), yesterday dotted across the whole day. Legend sits inside the plot;
// the dotted line is also labelled at its end, where it runs on alone after "现在".
function VtPlot({ kind = 'line', w = 343, h = 64, legend, endLabel, className }) {
  const today = DEMO.hourlyToday;
  const yest = DEMO.hourlyYesterday;
  const top = Math.max(...today, ...yest) * 1.12;
  const slot = w / yest.length;
  const x = i => i * slot + slot / 2;
  const y = val => h - 1 - (val / top) * (h - 6);
  const path = vals => vals.map((val, i) => `${i ? 'L' : 'M'}${x(i).toFixed(1)},${y(val).toFixed(1)}`).join(' ');
  const last = today.length - 1;
  const line = path(today);
  return (
    <div className={cx('vt-plot', className)}>
      {legend && <div className="vt-plot-legend"><VtLegend kind={kind} /></div>}
      <svg className="vt-chart" viewBox={`0 0 ${w} ${h}`} width="100%" role="img" aria-label="每小时实际扣费，今天与昨天对比">
        <line className="vt-chart-base" x1="0" x2={w} y1={h - 0.5} y2={h - 0.5} />
        {kind === 'bars'
          ? today.map((val, i) => <rect key={i} className={cx('vt-chart-bar', i === last && 'is-now')} x={x(i) - slot * 0.32} y={y(val)} width={slot * 0.64} height={h - 1 - y(val)} rx="1.5" />)
          : <><path className="vt-chart-area" d={`${line} L${x(last).toFixed(1)},${h - 1} L${x(0).toFixed(1)},${h - 1} Z`} /><path className="vt-chart-line" d={line} /></>}
        <path className="vt-chart-yest" d={path(yest)} />
        {kind === 'line' && <circle className="vt-chart-now" cx={x(last)} cy={y(today[last])} r="3.5" />}
      </svg>
      {endLabel && <span className="vt-plot-end" style={{ top: `${(y(yest[yest.length - 1]) / h) * 100}%` }}>昨天</span>}
    </div>
  );
}

function VtAxis() {
  const now = ((DEMO.hourlyToday.length - 0.5) / DEMO.hourlyYesterday.length) * 100;
  return (
    <div className="vt-axis num" aria-hidden="true">
      {[0, 6, 12, 18].map(hh => <span key={hh} style={{ left: `${(hh / 24) * 100}%` }}>{hh}时</span>)}
      <span className="vt-axis-now" style={{ left: `${now}%` }}>现在</span>
    </div>
  );
}

// Legend keys copy the marks: a solid line or a bar for today, the same dotted line as the plot for yesterday.
function VtLegend({ kind = 'line' }) {
  return <span className="vt-legend"><i className={cx('vt-key', kind === 'bars' && 'is-bar')} />今天<i className="vt-key yest" />昨天</span>;
}

function VtDelta({ withValue }) {
  return (
    <span className="strip-delta"><Icon name="up" size={12} weight={2.6} /> {todayChange().toFixed(1)}% · 比昨天同时{withValue && <span className="num">&nbsp;{fmt.money(yesterdaySameTime())}</span>}</span>
  );
}

// 账号成本 / 标准 / 利润 are plain labels: the plot draws neither line, so they carry no line marker. The basis names stay the
// BUILDER_GUIDE ones (实际扣费 / 账号成本 / 标准), the same words as the analytics 利润明细.
// 利润 = 实际扣费 − 账号成本 (profitOf), the same word and figure as the 6-cell ticker: no "+", a loss still shows "−".
function VtBases({ className }) {
  const t = DEMO.today;
  return (
    <div className={cx('vt-bases', className)}>
      <span><small>账号成本</small><b className="num">{fmt.money(t.cost)}</b></span>
      <span><small>标准</small><b className="num">{fmt.money(t.standard)}</b></span>
      <span><small>利润</small><b className="num">{fmt.money(profitOf(t))}</b></span>
    </div>
  );
}

// 顶部大数 + 图：今日实际扣费大字、今昨折线和三口径在最上面，待处理紧随其后。
function VtRevenueHero() {
  return (
    <div className="vt-hero">
      <small className="vt-hero-label">今日实际扣费</small>
      <span className="vt-figure vt-hero-num">{fmt.money(DEMO.today.actual)}</span>
      <VtDelta withValue />
      <div className="vt-hero-chart"><VtPlot kind="line" h={70} legend endLabel /><VtAxis /></div>
      <VtBases className="vt-hero-bases" />
    </div>
  );
}

// B 式计费卡：大数 + 今昨迷你折线 + 账号成本/标准/利润，下面两块用量磁贴。放在待处理之后。
// 区标题叫“今日计费”（评审 2026-10-18 第 4 条：营收统一改叫计费，与统计分析的“计费趋势”“计费明细”同一个词）。
function VtRevenueCard({ ctx }) {
  const { skin } = ctx;
  const t = DEMO.today;
  return (
    <section className="sec-wrap vt-card-wrap">
      <skin.SectionHead title="今日计费" meta="00:00 起" index="贰" />
      <div className="sec vt-rev">
        <div className="vt-rev-body">
          <div className="vt-rev-figure">
            <small>实际扣费</small>
            <span className="vt-figure vt-rev-num">{fmt.money(t.actual)}</span>
            <VtDelta />
          </div>
          <div className="vt-rev-spark"><VtLegend /><VtPlot kind="line" w={128} h={58} /></div>
        </div>
        <VtBases className="vt-rev-foot" />
      </div>
      {/* Both tiles sit under “今日计费 · 00:00 起”, so both feet are today's too (success rate on the SLA basis, tokens per request);
          the live per-minute rates stay out of this zone now that no window is written next to them. */}
      <div className="vt-tiles">
        <div className="vt-tile"><small>请求</small><b className="vt-figure">{fmt.compact(t.requests)}</b><span>成功率 <b className="num">{successRate('today')}</b></span></div>
        <div className="vt-tile"><small>Tokens</small><b className="vt-figure">{fmt.compact(t.tokens)}</b><span>每次请求 <b className="num">{fmt.compact(Math.round(t.tokens / t.requests))}</b></span></div>
      </div>
      <div className="sec vt-more"><VtMoreStats ctx={ctx} /></div>
    </section>
  );
}

// “用量 · 00:00 起” holds today's figures only (success rate on today's SLA basis); the live RPM / TPM are not mixed in here.
function VtUsageCells() {
  const t = DEMO.today;
  const cells = [['请求', fmt.compact(t.requests)], ['Tokens', fmt.compact(t.tokens)], ['成功率', successRate('today')]];
  return <div className="vt-usage">{cells.map(([k, val]) => <span key={k}><small>{k}</small><b className="vt-figure">{val}</b></span>)}</div>;
}

function VtUsageSection({ ctx }) {
  return (
    <Section skin={ctx.skin} title="用量" meta="00:00 起" index="贰">
      <VtUsageCells />
      <VtMoreStats ctx={ctx} />
    </Section>
  );
}

// row-meta is a flex row (every node gets a gap), so plain words and separators are merged into single text runs.
function VtChannelsLine({ channels }) {
  const count = s => channels.filter(c => c.state === s).length;
  const nodes = [];
  const text = t => { if (typeof nodes[nodes.length - 1] === 'string') nodes[nodes.length - 1] += t; else nodes.push(t); };
  VT_CHANNEL_WORDS.filter(([s]) => count(s) > 0).forEach(([s, word], i) => {
    if (i > 0) text(' · ');
    if (s === 'caution' || s === 'critical') nodes.push(<span key={s} className={`tone-${s} tone-text`}>{word} {count(s)}</span>);
    else text(`${word} ${count(s)}`);
  });
  return <>{nodes}</>;
}

// Live figures (health score, error rate, upstream 429 / 529): still the last 5 minutes, but the heading no longer says so.
function VtRunSection({ ctx, m, index }) {
  const { skin } = ctx;
  return (
    <Section skin={skin} title="运行" index={index}>
      <div className="pad"><skin.Health score={DEMO.run.health} /></div>
      <div className="kv-row pad">
        <span>错误率 <b className="num">{errorRate()}</b></span>
        <span>上游 429 <b className="num">{DEMO.run.r429}</b></span>
        <span>529 <b className="num">{DEMO.run.r529}</b></span>
      </div>
      <Row skin={skin} tone="none" lead={<span className="lead-icon dim"><Icon name="signal" /></span>} onClick={() => ctx.switchTab('monitor')}>
        <div className="row-top"><span className="row-title">渠道</span></div>
        <div className="row-meta"><VtChannelsLine channels={m.channels} /></div>
      </Row>
    </Section>
  );
}

// "Nothing to do" is backed by two facts: every account can be scheduled and no alert event is firing.
function vtCalmLine(m) {
  return `${m.normalCount} 个账号可调度 · 没有未解决的告警`;
}

// Empty queue, default: one status card in the queue's place.
function VtCalmStrip({ m }) {
  return (
    <div className="vt-calm tone-ok" role="status">
      <span className="vt-calm-icon"><Icon name="checkCircle" size={20} weight={2.2} /></span>
      <span className="vt-calm-text"><b>全部正常</b><span>{vtCalmLine(m)}</span></span>
    </div>
  );
}

// Empty queue, homeCalmQueue 'section': the 待处理 heading stays where it always is, with one "全部正常" row.
function VtCalmSection({ ctx, m }) {
  const { skin } = ctx;
  return (
    <Section skin={skin} title="待处理" meta="0 项" index="壹">
      <Row skin={skin} tone="ok" lead={<skin.Glyph state="normal" />} chevron={false}>
        <div className="row-top"><span className="row-title">全部正常</span></div>
        <div className="row-meta">{vtCalmLine(m)}</div>
      </Row>
    </Section>
  );
}

/* ---------- 专门的平静布局：待处理区消失，计费与用量是主角 ---------- */

// Holds while only rate limits remain (they show as one "自动恢复中" line); the chart keeps the type of the chosen billing layout.
// Under the 6-cell ticker (decided) the 用量 grid would repeat 请求, so it folds into one line under the chart, the same line as core's
// TodayBlock: Tokens and successRate('today'), both since 00:00 like the chart (the live RPM / TPM / 错误率 already sit in the ticker);
// the sections renumber. Without the ticker the 用量 section keeps today's three figures only: no window is written any more, so the
// live rates and the health score stay out of a "00:00 起" section.
function VtStage({ ctx, m }) {
  const { skin } = ctx;
  const t = DEMO.today;
  const ticker = m.v.homeRev === 'ticker';
  const kind = (m.v.homeRev || 'line') === 'line' ? 'bars' : 'line';
  const transient = vtTransient(m.list);
  const n = ticker ? ['壹', '贰', '叁'] : ['壹', '叁', '肆'];
  const top = [...m.list].filter(a => a.todayCost > 0).sort((a, b) => b.todayCost - a.todayCost).slice(0, 4);
  const max = top.length ? top[0].todayCost : 1;
  return (
    <Screen ctx={ctx} nav={<NavBar ctx={ctx} large title={ctx.site} titleMenu subtitle="10月16日 周五 · 刚刚更新" trailing={<GlassButton icon="more" />} />}>
      {m.calm && <span className="vt-calm-flag" hidden />}
      <div className="vt-stage-hero">
        <span className="vt-stage-flag tone-ok" role="status">
          <Icon name="checkCircle" size={15} weight={2.4} />{transient.length ? '无需处理' : '全部正常'}<span>· {m.normalCount} 个账号可调度</span>
        </span>
        {ticker ? null : <>
          <small>今日实际扣费</small>
          <span className="vt-figure vt-stage-num">{fmt.money(t.actual)}</span>
          <VtDelta withValue />
        </>}
      </div>
      {ticker && <VtTicker ctx={ctx} />}
      {transient.length > 0 && <Section skin={skin} title="自动恢复中" meta={`${transient.length} 个`}><VtLimitedRow ctx={ctx} limited={transient} /></Section>}
      <Section skin={skin} title="每小时实际扣费" meta="00:00 起" index={n[0]}>
        <div className="vt-stage-chart pad">
          <div className="vt-stage-legend"><VtLegend kind={kind} /></div>
          <VtPlot kind={kind} h={104} />
          <VtAxis />
        </div>
        <VtBases className="vt-stage-bases" />
        {ticker && (
          <div className="kv-row pad vt-stage-usage">
            <span>Tokens <b className="num">{fmt.compact(t.tokens)}</b></span>
            <span>成功率 <b className="num">{successRate('today')}</b></span>
          </div>
        )}
      </Section>
      {!ticker && (
        <Section skin={skin} title="用量" meta="00:00 起" index="贰">
          <VtUsageCells />
        </Section>
      )}
      <Section skin={skin} title="按账号" meta="今日实际扣费 · 前 4" index={n[1]}>
        {top.map(a => (
          <div key={a.id} className="row vt-rank tappable" onClick={() => ctx.push({ kind: 'account', id: a.id })}>
            <div className="vt-rank-main">
              <div className="row-top"><span className="row-title">{a.name}</span><skin.Money value={a.todayCost} size="m" /></div>
              <div className="vt-rank-bar"><i style={{ width: `${(a.todayCost / max) * 100}%` }} /></div>
              <div className="row-meta">{a.platform} · <span className="num">{fmt.grouped(a.todayReq)}</span> 次请求</div>
            </div>
            <div className="row-chev"><Icon name="chevron" size={13} weight={2.6} /></div>
          </div>
        ))}
        <VtMoreStats ctx={ctx} />
      </Section>
      <Section skin={skin} title="渠道" index={n[2]}>
        <Row skin={skin} tone="none" lead={<span className="lead-icon dim"><Icon name="signal" /></span>} onClick={() => ctx.switchTab('monitor')}>
          <div className="row-top"><span className="row-title">{m.channels.length} 个渠道</span></div>
          <div className="row-meta"><VtChannelsLine channels={m.channels} /></div>
        </Row>
      </Section>
    </Screen>
  );
}

/* ---------- 首页下钻：分组内账号、告警详情（推入概览 Tab 的导航栈） ---------- */

// Accounts of one group (GET admin/accounts?group=). The group sits in the filter row as a removable token.
// Used when this build has no group detail page (screen:group); see vtGroupRoute.
function VtGroupScreen({ ctx, route }) {
  const m = vtModel(ctx);
  const def = groupOf(route.group);
  const name = def ? def.name : route.group;
  const [scope, setScope] = useState('needs');
  const [scoped, setScoped] = useState(true);
  const pool = sortByUrgency(scoped ? groupMembers(m.list, name) : m.list);
  const needs = pool.filter(a => NEEDS_ACTION.includes(a.state));
  const rows = scope === 'needs' ? needs : pool;
  const available = pool.filter(a => a.state === 'normal').length;
  const chip = (key, label, count, alert) => (
    <button key={key} className={cx('chip', scope === key && 'on', alert && 'chip-alert')} onClick={() => setScope(key)}><span>{label}</span><b className="num">{count}</b></button>
  );
  return (
    <Screen plain ctx={ctx} nav={<NavBar ctx={ctx} back title={scoped ? name : '账号'} subtitle={`${ctx.site} · ${pool.length} 个 · ${available} 个可用`} />}>
      <div className="chips tokens">
        {scoped && <button className="chip on token" onClick={() => setScoped(false)} aria-label={`移除分组筛选 ${name}`}><span>分组：{name}</span><Icon name="close" size={12} weight={2.8} /></button>}
        {chip('needs', '需处理', needs.length, needs.length > 0)}
        {chip('all', '全部', pool.length)}
      </div>
      {/* While the group token is on, the title already names the group, so rows say only the platform and "另属 …" (core accountWhere). */}
      <div className="list-group">
        {rows.length
          ? rows.map(a => <Slot slot="accountRow" key={a.id} ctx={ctx} a={a} omit={scoped ? 'group' : undefined} home={scoped ? name : undefined} />)
          : <div className="empty pad">没有需要处理的账号</div>}
      </div>
    </Screen>
  );
}

/* ---------- 告警详情（槽 screen:alert，route {kind:'alert', id}） ---------- */

// fired_at / resolved_at as stored on the demo event: today's are bare HH:MM, earlier ones already carry their day.
function vtDayTime(t) {
  if (!t) return '—';
  return /^\d{1,2}:\d{2}$/.test(t) ? `今天 ${t}` : t;
}

// The rule's condition without its window: rule = '错误率 > 5%（5 分钟）' → '错误率 > 5%' (the window has its own row).
function vtCondition(alert) {
  return alert.rule.replace(/（[^（）]*）$/, '');
}

// Where a silence applies: the event's own dimensions (group_id / platform), as Web's silence request sends them.
function vtSilenceScope(alert) {
  return alert.group || (alert.platform ? `${alert.platform} 平台` : '');
}

// What the alert is about. Group: availability + (for error-rate rules) the group's failed requests; platform: its channel on the
// monitor tab; anything else (server metrics): the monitor overview.
function VtAlertScope({ ctx, m, alert }) {
  const { skin } = ctx;
  const openMonitor = seg => { ctx.setMonSeg(seg); ctx.switchTab('monitor'); };
  if (alert.group) {
    const group = groupOf(alert.group);
    const { total, available, limited, error } = groupAvailability(m.list, alert.group);
    const affected = limited + error;
    // The evidence behind an error-rate alert: this group's failed requests (logs are counted by the key's group, like the rule).
    // Same query as the list the row opens (core logCount / logsWhere), so the count and the rows always agree.
    const errorsOf = { scope: 'errors', group: group ? group.id : alert.group };
    const failed = /错误率/.test(alert.name) ? logCount(errorsOf) : null;
    return (
      <Section skin={skin} title="范围" index="壹">
        <Row skin={skin} tone="none" lead={<span className="lead-icon dim"><Icon name="group" /></span>} onClick={() => ctx.push(vtGroupRoute(alert.group))}>
          <div className="row-top"><span className="row-title">{alert.group}</span><span className="row-right vt-quiet-count"><b className="num">{available}/{total}</b> 可用</span></div>
          <div className="row-meta">{group ? `${group.platform} · ` : ''}{affected ? `${affected} 个账号受影响` : '账号都可调度'}</div>
        </Row>
        {failed !== null && (
          <Row skin={skin} tone="none" lead={<span className="lead-icon dim"><Icon name="octagon" /></span>}
            onClick={() => ctx.push({ kind: 'logs', ...errorsOf })}>
            <div className="row-top"><span className="row-title">错误请求</span><span className="row-right num">近 24 小时 {failed} 条</span></div>
          </Row>
        )}
      </Section>
    );
  }
  if (alert.platform) {
    const channel = DEMO.channels.find(c => c.name === alert.platform);
    const word = channel ? Object.fromEntries(VT_CHANNEL_WORDS)[channel.state] : null;
    return (
      <Section skin={skin} title="范围" index="壹">
        <Row skin={skin} tone="none" lead={<span className="lead-icon dim"><Icon name="signal" /></span>} onClick={() => openMonitor('channels')}>
          <div className="row-top"><span className="row-title">{alert.platform} 渠道</span>{channel && <span className={cx('row-right', channel.state !== 'ok' && `tone-${channel.state} tone-text`)}>{word}</span>}</div>
          <div className="row-meta">{channel ? <>可用率 <span className="num">{channel.avail ?? '—'}%</span> · 首字 <span className="num">{channel.ttft}</span></> : '没有这个平台的渠道探测'}</div>
        </Row>
      </Section>
    );
  }
  return (
    <Section skin={skin} title="范围" index="壹">
      <Row skin={skin} tone="none" lead={<span className="lead-icon dim"><Icon name="server" /></span>} onClick={() => openMonitor('overview')}>
        <div className="row-top"><span className="row-title">服务器</span><span className="row-right dim">监控 · 概况</span></div>
      </Row>
    </Section>
  );
}

// One alert event (ops alert-events + its rule): 手动解决 (PUT alert-events/:id/status manual_resolved) and 静默…
// (POST alert-silences with the rule and the event's dimensions, until now + 1h / 24h / 7d as on Web). There is no ack.
// An event that is no longer firing shows how it ended and has no actions. The handling is core's (ctx.resolveAlert / silenceAlert),
// so the home, 监控 · 告警 and the accounts' group badges see the same result.
function VtAlertScreen({ ctx, route }) {
  const { skin } = ctx;
  const m = vtModel(ctx);
  const alert = vtAlertOf(ctx, route && route.id);
  const firing = alert.status === 'firing';
  const tone = firing ? alertTone(alert) : 'neutral';
  const where = vtSilenceScope(alert);
  const resolve = () => ctx.confirm({
    title: '手动解决这条告警？',
    message: `「${alert.title}」会标记为已手动解决。条件仍满足时，规则会再次触发。`,
    actions: [
      { label: '手动解决', role: 'default', onPress: () => ctx.resolveAlert(alert.id, { text: '已手动解决', icon: 'checkCircle' }) },
      { label: '取消', role: 'cancel' },
    ],
  });
  const silence = () => ctx.confirm({
    title: '静默这条规则多久？',
    message: `静默期间，这条规则${where ? `在${where}` : ''}不再产生新的告警事件。当前这条仍需手动解决。`,
    actions: [
      ...ALERT_SILENCE.map(([span, until]) => ({ label: `静默 ${span}`, onPress: () => ctx.silenceAlert(alert.id, until, { text: `已静默 ${span}`, icon: 'hourglass', tone: 'neutral' }) })),
      { label: '取消', role: 'cancel' },
    ],
  });
  return (
    <Screen ctx={ctx} nav={<NavBar ctx={ctx} back title="告警" subtitle={`${alert.level} · ${alert.scope}`} />}>
      <div className="detail-head">
        <div className={cx('hero', `tone-${tone}`, firing && skin.rowClass(tone))}>
          <div className="hero-top">
            <skin.Badge tone={tone} label={ALERT_STATUS[alert.status]} big />
            <span className="hero-cause">{alert.level} · <span className="num">{alert.firedAt}</span> 触发</span>
          </div>
          <div className="vt-al-title">{alert.name}</div>
          <div className="vt-al-metric"><b className="vt-figure">{alert.metric}</b><span>阈值 <b className="num">{alert.threshold}</b>{alert.window ? ` · 近 ${alert.window}` : ''}</span></div>
          {firing && alert.silencedUntil && <div className="vt-al-note"><Icon name="hourglass" size={14} weight={2.4} />已静默至 <span className="num">{alert.silencedUntil}</span></div>}
          {!firing && <div className="vt-al-note"><Icon name="checkCircle" size={14} weight={2.4} />{alert.since}</div>}
        </div>
        {firing && (
          <div className="actions">
            <ActionButton label="手动解决" icon="check" primary onClick={resolve} />
            <ActionButton label={alert.silencedUntil ? '改静默时长…' : '静默…'} icon="hourglass" onClick={silence} />
          </div>
        )}
      </div>
      <VtAlertScope ctx={ctx} m={m} alert={alert} />
      <Section skin={skin} title="规则" index="贰">
        <div className="kv-grid pad">
          <KV label="条件" value={vtCondition(alert)} />
          <KV label="窗口" value={alert.window || '—'} />
          <KV label="级别" value={alert.level} />
          <KV label="触发" value={<span className="num">{vtDayTime(alert.firedAt)}</span>} />
          {!firing && <KV label="结束" value={<span className="num">{vtDayTime(alert.resolvedAt)}</span>} />}
        </div>
      </Section>
    </Screen>
  );
}

/* ---------- 第 2 轮决定：顶部 6 格指标（来自 C 的工作台），homeRev = 'ticker' ---------- */

// 今日实际扣费 · 请求 · 错误率 · 利润（profitOf：实际 − 账号成本）· RPM · TPM, in the order the user listed them (review 2026-10-18:
// 健康 gave its place to TPM; the health score stays in the 运行 section). 今日实际扣费 / 请求 / 利润 count from 00:00; 错误率
// (core errorRate() = DEMO.run.errorRate), RPM and TPM are still the last 5 minutes, but no label says so any more — the user wants
// just “RPM”, “错误率”. RPM / TPM come from the same throughput-trend as the chart they open (last five 1-minute buckets ÷ 5; TPM
// counts cache tokens), so each cell equals the chart's latest bucket; see the header for the dashboard/stats fallback.
// The change against yesterday at the same time is a direction, not a judgement: ▲ / ▼ in ink, never green or red. Each cell is its
// own button (SwiftUI: a 3 × 2 Grid of NavigationLinks): RPM and TPM open the analytics RPM / TPM trend on their own metric, the
// other four open the analytics page itself.
function VtTicker({ ctx }) {
  const t = DEMO.today;
  const change = todayChange();
  const cells = [
    { label: '今日实际扣费', value: fmt.money(t.actual), note: `${change < 0 ? '▼' : '▲'}${Math.abs(change).toFixed(1)}%`, spoken: `比昨天同时${change < 0 ? '下降' : '上升'} ${Math.abs(change).toFixed(1)}%` },
    { label: '请求', value: fmt.compact(t.requests) },
    { label: '错误率', value: errorRate() },
    { label: '利润', value: fmt.money(profitOf(t)) },
    { label: 'RPM', value: String(t.rpm), route: VT_PERF_ROUTE_RPM },
    { label: 'TPM', value: fmt.compact(t.tpm), route: VT_PERF_ROUTE_TPM },
  ];
  return (
    <div className="vt-ticker" role="group" aria-label="今日指标">
      {cells.map(c => (
        <button key={c.label} className={cx('vt-tk-cell', c.route && 'is-perf')} onClick={() => ctx.push({ ...(c.route || VT_ANALYTICS_ROUTE) })}
          aria-label={`${[c.label, c.value, c.spoken || c.note].filter(Boolean).join(' ')}。${c.route ? `打开 ${c.label} 趋势` : '打开统计分析'}`}>
          <small>{c.label}</small>
          <span className="vt-tk-val"><b className="num">{c.value}</b>{c.note && <em className="num">{c.note}</em>}</span>
        </button>
      ))}
    </div>
  );
}

/* ---------- 概览整屏 ---------- */

function VtQueue({ ctx, m, items }) {
  if (items.length) return <Section skin={ctx.skin} title="待处理" meta={`${items.length} 项`} index="壹">{items}</Section>;
  return m.v.homeCalmQueue === 'section' ? <VtCalmSection ctx={ctx} m={m} /> : <VtCalmStrip m={m} />;
}

// Same entry as the base home: model, user and group rankings live on the analytics page.
function VtMoreStats({ ctx }) {
  return (
    <Row skin={ctx.skin} tone="none" lead={<span className="lead-icon dim"><Icon name="chart" /></span>} onClick={() => ctx.push({ ...VT_ANALYTICS_ROUTE })}>
      <div className="row-top"><span className="row-title">更多统计</span><span className="row-right dim">模型 · 用户 · 分组排行</span></div>
    </Row>
  );
}

function VtHome({ ctx, m }) {
  const { skin } = ctx;
  const rev = m.v.homeRev || 'line';
  const pend = m.v.homePend || 'merge';
  const { items, quiet } = pend === 'each' ? vtEachItems(ctx, m) : pend === 'group' ? vtGroupItems(ctx, m) : vtMergeItems(ctx, m);
  return (
    <Screen ctx={ctx} nav={<NavBar ctx={ctx} large title={ctx.site} titleMenu subtitle="10月16日 周五 · 刚刚更新" trailing={<GlassButton icon="more" />} />}>
      {m.calm && <span className="vt-calm-flag" hidden />}
      {rev === 'line' && <skin.LedgerStrip ctx={ctx} />}
      {rev === 'ticker' && <VtTicker ctx={ctx} />}
      {rev === 'hero' && <VtRevenueHero />}
      <VtQueue ctx={ctx} m={m} items={items} />
      {quiet.length > 0 && <Section skin={skin} title="其他分组" meta="容量充足">{quiet}</Section>}
      {(rev === 'line' || rev === 'ticker') && <Section skin={skin} title="今日" meta="00:00 起" index="贰"><skin.TodayBlock ctx={ctx} /><VtMoreStats ctx={ctx} /></Section>}
      {rev === 'card' && <VtRevenueCard ctx={ctx} />}
      {rev === 'hero' && <VtUsageSection ctx={ctx} />}
      <VtRunSection ctx={ctx} m={m} index="叁" />
    </Screen>
  );
}

function VtToday({ ctx }) {
  const m = vtModel(ctx);
  if (m.v.homeCalm === 'stage' && !vtIsBusy(m)) return <VtStage ctx={ctx} m={m} />;
  return <VtHome ctx={ctx} m={m} />;
}

mvRegister('today', 'x', VtToday);
mvRegister(`screen:${VT_GROUP_ROUTE}`, 'base', VtGroupScreen);
// The full alert page replaces core's base list page for {kind:'alert', id} (BUILDER_GUIDE: the home owner registers it).
mvRegister('screen:alert', 'base', VtAlertScreen);
mvRegister(`screen:${VT_ALERT_ROUTE}`, 'base', VtAlertScreen);
