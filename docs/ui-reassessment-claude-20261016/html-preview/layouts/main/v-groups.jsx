/* 分组（v-groups）：分组列表 screen:groups、分组详情 screen:group（route {kind:'group', id}）、编辑 / 新建分组 sheet:groupEdit、添加账号 sheet:groupPick；
   API 密钥 screen:groupKeys（{id}）、订阅 screen:groupSubs（{id}）、成员批量写入的逐项结果 screen:groupBatch（{id, name, items}）。
   记录（错误请求 / 上游错误 / 使用记录）直接进 core 的使用记录：ctx.push({kind:'logs', scope, group})。
   已定：列表 base（A 三行行：名称 / 可用 x/y + 逐账号色格条 / 费率倍数与今日）、详情 base（A：状态卡 + 按钮行 + 成员列表 + 用量 / 记录 / 配置分区）。
   对比页保留的变体：列表 grid（健康网格）、table（表格）；详情 ring（大环 + 磁贴）、table（状态条 + 成员表）。
   数据：分组 = ctx.groups（core：DEMO.groups 加这台手机上的启停、改名、新建、复制、删除；dto.AdminGroup + groups/usage-summary + groups/capacity-summary），
   成员 = 账号自己的 groups（ctx.accounts），今日 = usage.today（按 Key 所属分组统计实际扣费），API 密钥 = DEMO.keys，
   订阅 = groupSubscriptions(id)（DEMO.subscriptions），到期天数 = daysUntil，告警 = ctx.alerts，删除确认 = core 的 confirmDelete。
   本文件不带任何演示数据（分组、Key、订阅、日期都读 shared/data.jsx），也不改写成员关系。
   字段口径（后端 dto.AdminGroup、Web 语言包）：status（正常 / 停用）、subscription_type（标准（余额）/ 订阅（配额），创建后不能修改）、rate_multiplier（费率倍数）、
   is_exclusive（专属 / 公开）、rpm_limit（每用户每分钟请求数，0 = 不限）、daily/weekly/monthly_limit_usd（订阅限额，按每个订阅计）、claude_code_only + fallback_group_id。
   新建（POST admin/groups）与 Web 的 createForm 一致：后端总是建成“正常”（请求没有 status 字段），默认公开、倍率 1.0、标准计费、RPM 0（不限）、
   平台 Anthropic、订阅限额留空、不限 Claude Code。复制（POST groups/:id/duplicate）建成“停用”，名称加 " (Copy)" / " (Copy n)"，连同成员账号与优先级一起复制。
   成员 = 账号的 group_ids（PUT admin/accounts/:id 整体替换，一个账号一次请求，各自可能失败）。调度按“分组 + 平台”取账号，所以只有同平台账号算可用，
   选择器也只列同平台账号（组合路由 Composite 分组在 Web 中创建）。后端没有“默认分组”标记，所以显示“专属 / 公开”。 */

/* ---------- 展示常量 ---------- */

const GV_BILLING = { standard: '标准（余额）', subscription: '订阅（配额）' };
const GV_BILLING_SHORT = { standard: '标准计费', subscription: '订阅计费' };
// Concrete platforms of domain/platforms.go, labelled by the backend DisplayName (Web language pack where it has one; 智谱 GLM as in DEMO).
const GV_PLATFORMS = ['Anthropic', 'OpenAI', 'Gemini', 'Antigravity', 'Grok', 'Kimi', '智谱 GLM', 'DeepSeek', 'MiniMax', 'OpenCode', 'TypeSafe / Jev', 'Command Code', 'Cline'];
const GV_COMPOSITE = 'Composite';
// Same line as the demo alert rule "可用比例 < 60%" (ops metric group_available_ratio).
const GV_LOW_RATIO = 0.6;
// One colour per bucket everywhere (cells, rings, legend, counts): 受限 = 限流 + 过载 + 临时不可调度, like the accounts tab's 受限 filter
// and groupAvailability() in shared/data.jsx. Member rows and badges keep each account's own state colour.
const GV_BUCKETS = [
  { key: 'ok', label: '可用', states: ['normal'], tone: 'ok' },
  { key: 'limited', label: '受限', states: ['rate_limited', 'overloaded', 'temp_unsched'], tone: 'caution' },
  { key: 'error', label: '错误', states: ['error'], tone: 'critical' },
  { key: 'idle', label: '暂停·停用', states: ['paused', 'inactive'], tone: 'neutral' },
];
const GV_ORDER = { none: 0, low: 1, ok: 2, off: 3 };
// Health words for places that show no badge (table column, card ring centre): status never rides on colour alone.
const GV_HEALTH_SHORT = { none: '无可用', low: '偏低', ok: '正常', off: '停用' };

// user_subscriptions.status, worded as in Web (api_keys.status words are core's KEY_STATUS_WORD). Revoked subscriptions are
// soft-deleted and never come back from groups/:id/subscriptions (only the all-status admin list includes them), so there is no 已撤销 here.
const GV_SUB_STATUS = { active: null, expired: { label: '已过期', tone: 'neutral' }, suspended: { label: '已暂停', tone: 'neutral' } };

/* API 密钥 page = GET admin/groups/:id/api-keys (dto.APIKey + user), read from DEMO.keys (the one key list users, requests and analytics
   read too). Paginated, newest id first (the handler passes no sort); spend = today_actual_cost from dashboard/api-keys-usage, as Web
   does. DEMO.keys is the first page; the group's apiKeys is the total.
   订阅 page = GET admin/groups/:id/subscriptions, read through groupSubscriptions(id) (DEMO.subscriptions: first page, newest first;
   total = rows of every status; active = the group's active count). Days left count from DEMO_TODAY with daysUntil. */

// Member writes are one PUT admin/accounts/:id each, so each can fail on its own. sheet.sim === 'partial' makes the last write fail
// in the demo: the connection dropped before the request went out, so that account is unchanged and a retry is safe.
const GV_FAIL_REASON = '网络连接中断，这个账号没有改动';

/* ---------- 模型 ---------- */

// This phone's groups: core's ctx.groups (DEMO.groups plus 启停、改名、倍率、新建、复制、删除 made here), so every page that reads
// ctx.groupOf sees the same edits. Writes go through ctx.updateGroup / addGroup / removeGroup; memberships stay on the accounts.
function useGvStore(ctx) {
  return { groups: ctx.groups || DEMO.groups };
}

// Ids of groups created here start above every id the phone or DEMO has used, so a new group never picks up a deleted demo group's records.
const gvNextId = groups => Math.max(...groups.map(x => x.id), ...DEMO.groups.map(x => x.id)) + 1;

const gvSum = (xs, f) => xs.reduce((s, x) => s + f(x), 0);
const gvRatio = v => (v.stats.total ? v.stats.ok / v.stats.total : 0);
const gvRate = r => `×${Number.isInteger(Math.round(r * 100) / 10) ? r.toFixed(1) : r.toFixed(2)}`;
const gvRpm = n => (n ? String(n) : '不限');
const gvLimit = x => (x ? fmt.money(x, { digits: 0 }) : '无限制');
const gvBucket = state => GV_BUCKETS.find(b => b.states.includes(state)) || GV_BUCKETS[3];
// A group schedules only accounts of its own platform (a composite group takes any concrete platform).
const gvSchedulable = (a, platform) => a.state === 'normal' && (platform === GV_COMPOSITE || a.platform === platform);
const gvMatch = (v, q) => !q.trim() || (v.name + v.platform).toLowerCase().includes(q.trim().toLowerCase());

function gvHealth(g, s) {
  if (g.status !== 'active') return { key: 'off', tone: 'neutral', label: '已停用' };
  if (s.ok === 0) return { key: 'none', tone: 'critical', label: s.total ? '无可用账号' : '没有账号' };
  if (s.ok / s.total < GV_LOW_RATIO) return { key: 'low', tone: 'caution', label: '可用偏低' };
  return { key: 'ok', tone: 'ok', label: s.ok === s.total ? '全部可用' : '正常' };
}

// capacity-summary (group_capacity_service.go, active groups only): Σ over the schedulable members (state normal) of concurrency, and
// of max_sessions / base_rpm where a member sets them (null when none does). Recomputed from this phone's accounts so it moves with the
// availability figure when members join, leave or stop scheduling here; at load it equals DEMO.groups[].capacity for every group.
function gvCapacity(g, members) {
  if (g.status !== 'active') return null;
  const live = members.filter(a => a.state === 'normal');
  const sum = key => {
    const xs = live.filter(a => a[key]);
    return xs.length ? [gvSum(xs, a => a[key][0]), gvSum(xs, a => a[key][1])] : null;
  };
  return { conc: live.length ? sum('conc') : [0, 0], sessions: sum('sessions'), rpm: sum('rpm') };
}

function gvView(ctx, store, g) {
  const members = sortByUrgency(groupMembers(ctx.accounts, g.name));
  const av = groupAvailability(ctx.accounts, g.name);
  const stats = { total: av.total, ok: av.available, limited: av.limited, error: av.error, idle: av.idle };
  const fallback = g.fallbackGroupId ? (store.groups.find(x => x.id === g.fallbackGroupId) || groupOf(g.fallbackGroupId) || {}).name || null : null;
  return { ...g, members, stats, capacity: gvCapacity(g, members), fallbackName: fallback, health: gvHealth(g, stats) };
}

// Most urgent first: no available account → below the line → healthy → stopped; lower ratio first, then the backend sort order.
function gvList(ctx, store) {
  return store.groups.map(g => gvView(ctx, store, g))
    .sort((a, b) => GV_ORDER[a.health.key] - GV_ORDER[b.health.key] || gvRatio(a) - gvRatio(b) || (a.sortOrder || 0) - (b.sortOrder || 0));
}

const gvBreakText = s => GV_BUCKETS.filter(b => b.key !== 'ok' && s[b.key]).map(b => `${b.label} ${s[b.key]}`).join(' · ');

function gvNextRecovery(v, elapsed) {
  const timed = v.members.filter(a => STATE_META[a.state].timed).map(a => ({ a, secs: remaining(a, elapsed) })).filter(x => x.secs !== null);
  return timed.length ? timed.reduce((m, x) => (x.secs < m.secs ? x : m)) : null;
}

// Alert dimensions carry the group name; matched through the shared table by id so a group renamed on this phone keeps its alert.
// Reads this phone's alerts (ctx.alerts), so an alert resolved on the alert page drops its banner here too.
const gvFiringAlerts = (ctx, v) => {
  const name = (groupOf(v.id) || v).name;
  return (ctx.alerts || DEMO.alerts).filter(al => al.status === 'firing' && al.group === name);
};
const gvByBucket = members => [...members].sort((a, b) => GV_BUCKETS.indexOf(gvBucket(a.state)) - GV_BUCKETS.indexOf(gvBucket(b.state)));

// capacity-summary lines with a real ceiling; a 0 ceiling means nothing in the group can be scheduled right now.
function gvCaps(v) {
  const c = v.capacity;
  if (!c) return [];
  return [['并发', c.conc], ['会话', c.sessions], ['调度 RPM', c.rpm]].filter(([, x]) => x && x[1] > 0).map(([label, x]) => ({ label, used: x[0], limit: x[1] }));
}
// Why there is no capacity line: stopped group, no members, nothing schedulable, or schedulable members without a concurrency figure.
const gvCapNote = v => (v.status !== 'active' ? '停用的分组不统计容量' : !v.stats.total ? '没有成员账号' : !v.stats.ok ? '没有可调度的账号' : '暂无容量数据');
const gvConc = v => (v.capacity && v.capacity.conc && v.capacity.conc[1] > 0 ? v.capacity.conc : null);

// Usage and ops error logs carry group_id (the key's group): core's usage page filtered by the demo group's id, so a group renamed
// here keeps its records; a group created on this phone is matched by name and has none yet. Counts use the same filter as the list.
const gvLogRoute = (v, scope) => ({ kind: 'logs', scope, group: groupOf(v.id) ? v.id : v.name });
const gvLogCount = (v, scope) => logCount({ scope, group: gvLogRoute(v, scope).group });

/* ---------- small pieces ---------- */

function GvGlyph({ v }) {
  const icon = { none: 'octagon', low: 'gauge', ok: 'group', off: 'minus' }[v.health.key];
  return <span className={cx('glyph gv-glyph', `tone-${v.health.tone}`, `gv-glyph-${v.health.key}`)}><Icon name={icon} size={17} weight={2.1} /></span>;
}

// One cell per member account, coloured by its bucket: green cells are the ones that can be scheduled now.
function GvCells({ v, big }) {
  const cells = gvByBucket(v.members);
  return (
    <span className={cx('gv-cells', big && 'gv-cells-big', v.status !== 'active' && 'is-off')} role="img" aria-label={`可用 ${v.stats.ok} / ${v.stats.total}`}>
      {cells.length ? cells.map(a => <i key={a.id} className={`c-${gvBucket(a.state).tone}`} />) : <i className="c-empty" />}
    </span>
  );
}

function GvAvail({ v, size = 'm' }) {
  const t = v.health.tone;
  return (
    <span className={cx('gv-avail num', `gv-avail-${size}`, `tone-${t}`)} aria-label={`可用 ${v.stats.ok} / ${v.stats.total}`}>
      <b className={cx((t === 'critical' || t === 'caution') && 'tone-text')}>{v.stats.ok}</b><span>/{v.stats.total}</span>
    </span>
  );
}

// Segmented ring, one arc per member account (B's ring language), coloured by bucket like the cells and the legend.
function GvRing({ v, size, stroke, children }) {
  const r = (size - stroke) / 2;
  const c = 2 * Math.PI * r;
  const cells = gvByBucket(v.members);
  const seg = cells.length ? c / cells.length : c;
  const gap = cells.length > 1 ? Math.min(4, seg / 3) : 0;
  const mid = size / 2;
  return (
    <span className={cx('gv-ring', v.status !== 'active' && 'is-off')} style={{ width: size, height: size }}>
      <svg width={size} height={size} viewBox={`0 0 ${size} ${size}`} aria-hidden="true">
        <circle className="gv-ring-track" cx={mid} cy={mid} r={r} strokeWidth={stroke} />
        {cells.map((a, i) => (
          <circle key={a.id} className={`gv-ring-seg s-${gvBucket(a.state).tone}`} cx={mid} cy={mid} r={r} strokeWidth={stroke}
            strokeDasharray={`${Math.max(seg - gap, 1)} ${c}`} strokeDashoffset={-i * seg} transform={`rotate(-90 ${mid} ${mid})`} />
        ))}
      </svg>
      <span className="gv-ring-center">{children}</span>
    </span>
  );
}

function GvLegend({ v, className }) {
  return (
    <div className={cx('gv-legend', className)}>
      {GV_BUCKETS.map(b => (
        <span key={b.key} className={cx('gv-leg', `tone-${b.tone}`, !v.stats[b.key] && 'is-zero')}><i />{b.label}<b className="num">{v.stats[b.key]}</b></span>
      ))}
    </div>
  );
}

function GvRecovery({ ctx, v }) {
  const next = gvNextRecovery(v, ctx.elapsed);
  if (!next) return null;
  return <div className="gv-next">最早 <b className="num">{fmt.countdown(next.secs)}</b> 后恢复 1 个 · {next.a.name}</div>;
}

// The whole banner is the tap target (≥ 44pt); “查看” is its visible affordance. Colour follows alertTone (P1 amber, like the home
// screen and 监控 · 告警); tapping pushes the same alert page as the home screen's attention item.
function GvAlertBanner({ ctx, v }) {
  const al = gvFiringAlerts(ctx, v)[0];
  if (!al) return null;
  const tone = alertTone(al);
  const open = () => ctx.push({ kind: 'alert', id: al.id });
  return (
    <div className={cx('banner gv-banner tappable', `tone-${tone}`, ctx.skin.rowClass(tone))} onClick={open} role="button">
      <Icon name="bell" size={18} />
      <div className="banner-text"><b>{al.level} 告警中 · {al.title}</b><span>{al.rule} · {al.since}</span></div>
      <ActionButton small label="查看" onClick={open} />
    </div>
  );
}

// Shown under every member list: an account's “today” adds up every group it serves, and the group's today counts by the key's group.
// The decided detail (A) uses the accounts tab's own three-line row (core accountRow slot), so its money reads “今日”.
const GvMemberNote = ({ table, rows }) => (
  <div className="gv-mnote pad">{table ? '“账号今日”“账号请求”' : rows ? '成员行的“今日”是账号今日，' : '“账号今日”'}含这个账号在其他分组的用量；分组今日按 Key 所属分组统计。</div>
);

/* ---------- 滑动操作（SwiftUI .swipeActions） ---------- */

const GV_SWIPE_W = 74;

// Drag a row left for its trailing actions, right for the leading ones; release past half snaps open. A plain tap still opens the row
// (or closes an open one). The same actions stay in ⋯ / long press, which is also how VoiceOver reaches them. `open` opens one for demos;
// onAct tells the page an action ran, so a demo-opened row does not open again when it re-mounts (e.g. moved section and back by 撤销).
function GvSwipe({ open, leading = [], trailing = [], onContextMenu, onAct, children }) {
  const maxL = leading.length * GV_SWIPE_W;
  const maxR = trailing.length * GV_SWIPE_W;
  const [x, setX] = useState(open === 'trailing' ? -maxR : open === 'leading' ? maxL : 0);
  const [live, setLive] = useState(null);
  const drag = useRef(null);
  const swallowUntil = useRef(0);
  const down = e => {
    if (e.button !== 0 || (!maxL && !maxR)) return;
    drag.current = { sx: e.clientX, sy: e.clientY, base: x, on: false, el: e.currentTarget, pid: e.pointerId };
  };
  const move = e => {
    const d = drag.current;
    if (!d) return;
    const dx = e.clientX - d.sx;
    if (!d.on) {
      if (Math.abs(dx) < 8) return;
      if (Math.abs(e.clientY - d.sy) > Math.abs(dx)) { drag.current = null; return; }
      d.on = true;
      if (d.el.setPointerCapture) d.el.setPointerCapture(d.pid);
    }
    setLive(Math.max(-maxR, Math.min(maxL, d.base + dx)));
  };
  const up = () => {
    const d = drag.current;
    drag.current = null;
    if (!d || !d.on) return;
    swallowUntil.current = Date.now() + 350;
    const v = live === null ? x : live;
    setX(v < -maxR / 2 ? -maxR : v > maxL / 2 ? maxL : 0);
    setLive(null);
  };
  const clickCapture = e => {
    if (Date.now() < swallowUntil.current) { e.stopPropagation(); return; }
    if (x !== 0) { e.stopPropagation(); setX(0); }
  };
  const off = live === null ? x : live;
  const act = a => (
    <button key={a.label} className={cx('gv-swipe-act', `act-${a.tone || 'plain'}`)} style={{ width: GV_SWIPE_W }} onClick={() => { setX(0); if (onAct) onAct(); a.onPress(); }}>
      <Icon name={a.icon} size={18} weight={2.3} /><span>{a.label}</span>
    </button>
  );
  return (
    <div className={cx('gv-swipe', off !== 0 && 'is-open')} onContextMenu={onContextMenu}>
      {off > 0 && <div className="gv-swipe-acts gv-swipe-lead">{leading.map(act)}</div>}
      {off < 0 && <div className="gv-swipe-acts gv-swipe-trail">{trailing.map(act)}</div>}
      <div className={cx('gv-swipe-body', live !== null && 'is-dragging')} style={off ? { transform: `translateX(${off}px)` } : undefined}
        onPointerDown={down} onPointerMove={move} onPointerUp={up} onPointerCancel={up} onClickCapture={clickCapture}>
        {children}
      </div>
    </div>
  );
}

/* ---------- actions ---------- */

const gvEdit = (ctx, v) => ctx.openSheet({ kind: 'groupEdit', id: v.id });
const gvPick = (ctx, v) => ctx.openSheet({ kind: 'groupPick', id: v.id });

// Reversible: applies at once through core's group store, the receipt's 撤销 puts the group back as it was.
function gvSetStatus(ctx, store, v, status) {
  const on = status === 'active';
  ctx.updateGroup(v.id, { status }, { text: on ? `已启用「${v.name}」` : `已停用「${v.name}」`, icon: on ? 'play' : 'pauseFill', tone: on ? 'ok' : 'neutral', undo: true });
}

function gvConfirmStop(ctx, store, v) {
  ctx.confirm({
    title: `停用「${v.name}」？`,
    message: `站点 ${ctx.site}\n使用这个分组的 ${v.apiKeys} 个 API 密钥会被拒绝（提示“所属分组已停用”）。可以随时重新启用。`,
    actions: [{ label: '停用分组', role: 'default', onPress: () => gvSetStatus(ctx, store, v, 'inactive') }, { label: '取消', role: 'cancel' }],
  });
}

// Demo bookkeeping: accounts list group *names* while the backend keys memberships by id, so a rename rewrites the names in place
// (not a member write). Joins and leaves are member writes: one PUT per account, each with its own result. Undo only reverts writes
// that went through, putting each back to the list it had just before (the receipt's undo runs after this render's ctx went stale, so it
// carries the lists rather than reading ctx.accounts again).
function gvApplyMembers(ctx, oldName, newName, memberIds, sim) {
  const rows = Object.values(ctx.accounts).map(a => {
    const was = a.groups.includes(oldName);
    const keep = Boolean(newName) && memberIds.includes(a.id);
    const renamed = was && newName ? a.groups.map(n => (n === oldName ? newName : n)) : a.groups;
    const next = keep ? (was ? renamed : [...a.groups, newName]) : a.groups.filter(n => n !== oldName);
    return { a, was, keep, renamed, next };
  });
  const moves = rows.filter(r => r.was !== r.keep);
  const failId = sim === 'partial' && moves.length ? moves[moves.length - 1].a.id : null;
  const items = [];
  const reverts = [];
  rows.forEach(r => {
    const moved = r.was !== r.keep;
    const ok = r.a.id !== failId;
    const target = ok ? r.next : r.renamed;
    if (moved) items.push({ id: r.a.id, name: r.a.name, join: r.keep, ok, reason: ok ? null : GV_FAIL_REASON });
    if (moved && ok) reverts.push([r.a.id, r.renamed]);
    if (target.join('|') !== r.a.groups.join('|')) ctx.updateAccount(r.a.id, { groups: target });
  });
  const undo = () => reverts.forEach(([id, groups]) => ctx.updateAccount(id, { groups }));
  return { items, undo };
}

// One member write against the current accounts (retry / undo from the results page and from receipts).
function gvMoveOne(ctx, id, name, join) {
  const a = ctx.accounts[id];
  if (!a) return;
  const has = a.groups.includes(name);
  if (join && !has) ctx.updateAccount(id, { groups: [...a.groups, name] });
  if (!join && has) ctx.updateAccount(id, { groups: a.groups.filter(n => n !== name) });
}

// “已加入 2 个账号” / “已加入 1 个，1 个失败” / “加入失败 · 1 个账号没有改动”; empty when no member changed.
function gvMemberText(items) {
  if (!items.length) return '';
  const fail = items.filter(x => !x.ok).length;
  const parts = [['加入', items.filter(x => x.join)], ['移出', items.filter(x => !x.join)]].filter(([, xs]) => xs.length);
  if (!fail) return parts.map(([verb, xs]) => `已${verb} ${xs.length} 个`).join('、') + '账号';
  const okCount = items.length - fail;
  if (!okCount) return `${parts.map(([verb]) => verb).join(' / ')}失败 · ${fail} 个账号没有改动`;
  return `${parts.map(([verb, xs]) => `已${verb} ${xs.filter(x => x.ok).length} 个`).join('、')}，${fail} 个失败`;
}

// Receipt for member writes. Any failure → the receipt's button opens the per-account results (it carries retry and the undo of
// the ones that went through); all fine → plain 撤销 when the caller allows it.
function gvMemberReceipt(ctx, g, res, opts = {}) {
  const fail = res.items.some(x => !x.ok);
  const text = [opts.prefix, gvMemberText(res.items), !fail && opts.suffix].filter(Boolean).join(' · ');
  ctx.showToast({
    text, icon: fail ? 'clockAlert' : opts.icon || 'group', tone: fail ? 'caution' : 'ok',
    action: fail ? { label: '查看', onPress: () => ctx.push({ kind: 'groupBatch', id: g.id, name: g.name, items: res.items }) } : null,
    undo: !fail && opts.undo && res.items.length ? res.undo : null,
  });
}

// Swipe → 移出 on a member row: reversible, so it applies at once with 撤销, unless it takes the group's last available account.
function gvRemoveMember(ctx, v, a) {
  const live = a.state === 'normal';
  const run = () => ctx.updateAccount(a.id, { groups: a.groups.filter(n => n !== v.name) }, {
    text: `已移出「${a.name}」${live ? ` · 可用 ${v.stats.ok} → ${v.stats.ok - 1}` : ''}`, icon: 'group', tone: 'neutral', undo: true,
  });
  if (!(v.status === 'active' && live && v.stats.ok === 1)) { run(); return; }
  ctx.confirm({
    title: `把「${a.name}」移出「${v.name}」？`,
    message: `站点 ${ctx.site}\n它是这个分组唯一可用的账号，移出后这个分组的新请求会失败。账号本身保留。`,
    actions: [{ label: '仍然移出', role: 'destructive', onPress: run }, { label: '取消', role: 'cancel' }],
  });
}

// The member row's state action next to 移出: the same verbs as the account detail's button row.
function gvStateAction(ctx, a) {
  if (NEEDS_ACTION.includes(a.state)) return { label: '恢复状态', icon: 'restore', tone: 'accent', onPress: () => confirmRecover(ctx, a) };
  if (a.state === 'paused') return { label: '启用调度', icon: 'play', tone: 'accent', onPress: () => ctx.setSchedule([a.id], true) };
  if (a.state === 'normal') return { label: '停止调度', icon: 'pauseFill', tone: 'neutral', onPress: () => ctx.setSchedule([a.id], false) };
  return null;
}

/* What DELETE admin/groups/:id does (group_repo deleteCascade), in Web's two wordings (deleteConfirm / deleteConfirmSubscription) with
   the counts: a subscription group soft-deletes every subscription row of any status (groupSubscriptions total) and its keys stop
   working; a standard group's keys no longer belong to any group. account_groups rows go too, so the members leave; the accounts stay.
   One short line per consequence; lines with nothing to say (0 keys, no subscriptions, no members) are left out. */
function gvDeleteMessage(v) {
  const keys = v.apiKeys || 0;
  const subs = v.subscriptionType === 'subscription' ? groupSubscriptions(v.id) : null;
  return [
    keys ? (subs ? `绑定这个分组的 ${keys} 个 API 密钥会失效。` : `${keys} 个 API 密钥将不再属于任何分组。`) : null,
    subs && subs.total ? `删除 ${subs.total} 条订阅记录${subs.active ? `（生效中 ${subs.active} 条）` : ''}。` : null,
    v.stats.total ? `${v.stats.total} 个成员账号移出分组，账号本身保留。` : null,
  ].filter(Boolean).join('\n');
}

// Core's confirmDelete: site line, type the full name (Face ID off) or 用 Face ID 删除, the receipt; ctx.v.deleteTyped prefills the name.
// From the detail page the page pops first; ctx.removeGroup drops the group and takes it out of every account's list.
const gvDelete = (ctx, v, fromList) => confirmDelete(ctx, '分组', v.name, fromList ? null : ctx.pop, { remove: () => ctx.removeGroup(v.id), message: gvDeleteMessage(v) });

// POST groups/:id/duplicate: the copy starts stopped, gets " (Copy)" / " (Copy n)", keeps the source's sort order and copies
// its member accounts with their priorities in the same transaction (admin_group_duplicate.go), so there is no partial result.
// No keys or subscriptions move over.
function gvDuplicate(ctx, store, v) {
  const src = store.groups.find(x => x.id === v.id);
  if (!src) return;
  const id = gvNextId(store.groups);
  const copies = store.groups.filter(x => x.name.startsWith(`${v.name} (Copy`)).length;
  const name = `${v.name} (Copy${copies ? ` ${copies + 1}` : ''})`;
  ctx.addGroup({ ...src, id, name, status: 'inactive', usage: { today: 0, yesterday: 0, total: 0 }, todayStats: { requests: 0, tokens: 0, cost: 0, standard: 0 },
    capacity: null, apiKeys: 0, subscriptions: src.subscriptionType === 'subscription' ? 0 : null });
  v.members.forEach(a => ctx.updateAccount(a.id, { groups: [...ctx.accounts[a.id].groups, name] }));
  ctx.showToast({ text: `已复制为「${name}」· 停用中 · ${v.members.length} 个成员账号`, icon: 'group', tone: 'neutral', action: { label: '查看', onPress: () => ctx.push({ kind: 'group', id }) } });
}

// ⋯ = toolbar menu (SwiftUI Menu, core ctx.menu): edit first, delete last in red behind a divider (decided: deletion lives at the end
// of ⋯ and needs confirmation). The list rows open the same menu on long press (SwiftUI .contextMenu); fromList keeps the list on
// screen after a delete.
function gvMenu(ctx, store, v, fromList) {
  (ctx.menu || ctx.confirm)({
    title: v.name,
    actions: [
      { label: '编辑分组', role: 'default', onPress: () => gvEdit(ctx, v) },
      { label: '添加账号', role: 'default', onPress: () => gvPick(ctx, v) },
      v.status === 'active' ? { label: '停用分组…', role: 'default', onPress: () => gvConfirmStop(ctx, store, v) } : { label: '启用分组', role: 'default', onPress: () => gvSetStatus(ctx, store, v, 'active') },
      { label: '复制分组', role: 'default', onPress: () => gvDuplicate(ctx, store, v) },
      { label: '删除分组…', role: 'destructive', onPress: () => gvDelete(ctx, v, fromList) },
      { label: '取消', role: 'cancel' },
    ],
  });
}

function gvListNav(ctx, list) {
  const none = list.filter(v => v.health.key === 'none').length;
  return (
    <NavBar ctx={ctx} back title="分组" subtitle={`${ctx.site} · ${none ? `${none} 个分组无可用账号` : `${list.length} 个分组`}`}
      trailing={<GlassButton icon="plus" onClick={() => ctx.openSheet({ kind: 'groupEdit', isNew: true })} />} />
  );
}

const gvLongPress = (ctx, store, v) => e => { e.preventDefault(); gvMenu(ctx, store, v, true); };

// route.swipe opens one row for demo states, only until the first swipe action on the page.
function useGvDemoSwipe(route) {
  const [swipe, setSwipe] = useState(route && route.swipe ? route.swipe : null);
  return [swipe, () => setSwipe(null)];
}

// .searchable in SwiftUI; filters by group name or platform.
function GvSearch({ q, setQ }) {
  return (
    <label className="search-field gv-search"><Icon name="search" size={16} />
      <input placeholder="分组名称或平台" value={q} onChange={e => setQ(e.target.value)} aria-label="搜索分组" />
    </label>
  );
}

/* ---------- 列表 ① A 三行行（已定） ---------- */

function GvRow({ ctx, store, v, open, onAct }) {
  const { skin } = ctx;
  const t = v.health.tone;
  const rail = t === 'critical' || t === 'caution';
  const brk = gvBreakText(v.stats);
  const on = v.status === 'active';
  // Leading: 添加账号 (only an active group schedules); trailing: 编辑 + 停用 / 启用. Delete stays in ⋯ / long press.
  const leading = on ? [{ label: '添加账号', icon: 'plus', tone: 'accent', onPress: () => gvPick(ctx, v) }] : [];
  const trailing = [
    { label: '编辑', icon: 'compose', tone: 'plain', onPress: () => gvEdit(ctx, v) },
    on ? { label: '停用', icon: 'pauseFill', tone: 'neutral', onPress: () => gvConfirmStop(ctx, store, v) } : { label: '启用', icon: 'play', tone: 'accent', onPress: () => gvSetStatus(ctx, store, v, 'active') },
  ];
  return (
    <GvSwipe open={open} onAct={onAct} leading={leading} trailing={trailing} onContextMenu={gvLongPress(ctx, store, v)}>
      <Row skin={skin} tone={rail ? t : 'none'} className={cx('gv-row', `tone-${t}`, !on && 'is-idle')} lead={<GvGlyph v={v} />} onClick={() => ctx.push({ kind: 'group', id: v.id })}>
        <div className="row-top">
          <span className="row-title">{v.name}<small className="row-sub">{v.platform}</small></span>
          <span className="gv-flags">
            {v.exclusive && <span className="gv-tag">专属</span>}
            {v.health.key !== 'ok' && <skin.Badge tone={t} label={v.health.label} />}
          </span>
        </div>
        <div className="gv-row-cap">
          <span className="gv-row-avail"><small>可用</small><GvAvail v={v} /></span>
          <GvCells v={v} />
          {brk && <span className="gv-break">{brk}</span>}
        </div>
        <div className="row-foot">
          <span className="row-meta">费率倍数 <b className="num gv-strong">{gvRate(v.rate)}</b> · {GV_BILLING_SHORT[v.subscriptionType]}</span>
          <span className="row-money"><small>今日</small><skin.Money value={v.usage.today} size="s" /></span>
        </div>
      </Row>
    </GvSwipe>
  );
}

function GvListRows({ ctx, route }) {
  const store = useGvStore(ctx);
  const [q, setQ] = useState('');
  const list = gvList(ctx, store);
  const shown = list.filter(v => gvMatch(v, q));
  const parts = [
    ['需处理', shown.filter(v => v.health.key === 'none' || v.health.key === 'low')],
    ['正常', shown.filter(v => v.health.key === 'ok')],
    ['停用', shown.filter(v => v.health.key === 'off')],
  ].filter(([, rows]) => rows.length);
  const [swipe, endSwipe] = useGvDemoSwipe(route);
  const openOf = v => (swipe === v.id ? route.swipeSide || 'trailing' : null);
  return (
    <Screen plain ctx={ctx} nav={gvListNav(ctx, list)}>
      <GvSearch q={q} setQ={setQ} />
      {parts.length === 0 && <div className="empty pad">没有匹配的分组</div>}
      {parts.map(([title, rows]) => (
        <div key={title} className="list-group">
          <div className="list-head"><span>{title}</span><b className="num">{rows.length}</b></div>
          {rows.map(v => <GvRow key={v.id} ctx={ctx} store={store} v={v} open={openOf(v)} onAct={endSwipe} />)}
        </div>
      ))}
      <div className="gv-mnote pad">左滑编辑或停用，右滑添加账号；长按看全部操作。今日按 Key 所属分组统计。</div>
    </Screen>
  );
}

/* ---------- 列表 ② 健康网格 ---------- */

function GvCard({ ctx, store, v }) {
  const { skin } = ctx;
  const t = v.health.tone;
  const flagged = t === 'critical' || t === 'caution';
  const note = v.health.key === 'off' ? '新请求会被拒绝' : v.stats.total === 0 ? '没有成员账号' : gvBreakText(v.stats) || '全部可用';
  const word = { none: '无可用', low: '偏低', ok: '可用', off: '已停用' }[v.health.key];
  return (
    <button className={cx('gv-card', `tone-${t}`, flagged && 'is-flagged tone-rail', v.status !== 'active' && 'is-off')} onClick={() => ctx.push({ kind: 'group', id: v.id })} onContextMenu={gvLongPress(ctx, store, v)}>
      <span className="gv-card-head"><b>{v.name}</b>{v.exclusive && <span className="gv-tag">专属</span>}</span>
      <span className="gv-card-sub">{v.platform} · {GV_BILLING_SHORT[v.subscriptionType]}</span>
      <span className="gv-card-ring">
        <GvRing v={v} size={96} stroke={9}><GvAvail v={v} size="l" /><small className={cx(flagged && 'tone-text gv-ring-word')}>{word}</small></GvRing>
      </span>
      <span className={cx('gv-card-note', flagged && 'tone-text')}>{note}</span>
      <span className="gv-card-foot"><span className="num gv-strong">{gvRate(v.rate)}</span><span className="gv-card-money"><small>今日</small><skin.Money value={v.usage.today} size="s" /></span></span>
    </button>
  );
}

function GvListGrid({ ctx }) {
  const { skin } = ctx;
  const store = useGvStore(ctx);
  const list = gvList(ctx, store);
  const [only, setOnly] = useState(null);
  const [q, setQ] = useState('');
  const cells = [['none', '无可用', 'critical'], ['low', '偏低', 'caution'], ['ok', '正常', 'ok'], ['off', '停用', 'neutral']];
  const shown = list.filter(v => (!only || v.health.key === only) && gvMatch(v, q));
  return (
    <Screen ctx={ctx} nav={gvListNav(ctx, list)}>
      <GvSearch q={q} setQ={setQ} />
      <div className="gv-sum pad">
        {cells.map(([k, label, tone]) => {
          const n = list.filter(v => v.health.key === k).length;
          return (
            <button key={k} className={cx('gv-sum-cell', `tone-${tone}`, tone === 'critical' && n && 'tone-rail', only === k && 'on', !n && 'is-zero')} onClick={() => setOnly(only === k ? null : k)} aria-pressed={only === k}>
              <skin.Num size="l">{n}</skin.Num><small>{label}</small>
            </button>
          );
        })}
      </div>
      {shown.length === 0 && <div className="empty pad">没有匹配的分组</div>}
      <div className="gv-grid pad-x">
        {shown.map(v => <GvCard key={v.id} ctx={ctx} store={store} v={v} />)}
        {!only && !q.trim() && (
          <button className="gv-card gv-card-add" onClick={() => ctx.openSheet({ kind: 'groupEdit', isNew: true })}>
            <Icon name="plus" size={22} weight={2.2} /><span>新建分组</span>
          </button>
        )}
      </div>
    </Screen>
  );
}

/* ---------- 列表 ③ 表格 ---------- */

const GV_LIST_COLS = [
  { key: 'name', label: '分组', w: 150, sort: v => v.name },
  { key: 'avail', label: '可用', w: 58, r: true, sort: v => gvRatio(v) },
  { key: 'health', label: '健康', w: 62, sort: v => GV_ORDER[v.health.key] },
  { key: 'limited', label: '受限', w: 46, r: true, sort: v => v.stats.limited },
  { key: 'error', label: '错误', w: 46, r: true, sort: v => v.stats.error },
  { key: 'idle', label: '暂停·停用', w: 74, r: true, sort: v => v.stats.idle },
  { key: 'rate', label: '倍率', w: 54, r: true, sort: v => v.rate },
  { key: 'today', label: '今日', w: 80, r: true, sort: v => v.usage.today },
  { key: 'yesterday', label: '昨日', w: 80, r: true, sort: v => v.usage.yesterday },
  { key: 'total', label: '累计', w: 92, r: true, sort: v => v.usage.total },
  { key: 'conc', label: '并发', w: 62, r: true, sort: v => (gvConc(v) ? gvConc(v)[0] : -1) },
  { key: 'billing', label: '计费', w: 58, sort: v => v.subscriptionType },
  { key: 'excl', label: '类型', w: 50, sort: v => (v.exclusive ? 1 : 0) },
  { key: 'status', label: '启停', w: 50, sort: v => v.status },
];

function gvListCell(ctx, v, key) {
  const { skin } = ctx;
  const z = n => <span className={cx('num', !n && 'gv-zero')}>{n}</span>;
  const conc = gvConc(v);
  switch (key) {
    case 'name': return <><GvGlyph v={v} /><span className="gv-cell-text">{v.name}</span></>;
    case 'avail': return <GvAvail v={v} size="s" />;
    case 'health': return <span className={cx('gv-health', `tone-${v.health.tone}`, `gv-health-${v.health.key}`)}>{GV_HEALTH_SHORT[v.health.key]}</span>;
    case 'limited': return v.stats.limited ? <span className="num tone-caution tone-text">{v.stats.limited}</span> : z(0);
    case 'error': return v.stats.error ? <span className="num tone-critical tone-text">{v.stats.error}</span> : z(0);
    case 'idle': return z(v.stats.idle);
    case 'rate': return <span className="num">{gvRate(v.rate)}</span>;
    case 'today': return <skin.Money value={v.usage.today} size="s" />;
    case 'yesterday': return <skin.Money value={v.usage.yesterday} size="s" />;
    case 'total': return <skin.Money value={v.usage.total} size="s" />;
    case 'conc': return <span className="num">{conc ? `${conc[0]}/${conc[1]}` : '—'}</span>;
    case 'billing': return GV_BILLING_SHORT[v.subscriptionType].replace('计费', '');
    case 'excl': return v.exclusive ? '专属' : '公开';
    default: return <span className={cx(v.status !== 'active' && 'gv-dim')}>{v.status === 'active' ? '启用' : '停用'}</span>;
  }
}

function GvListTable({ ctx }) {
  const store = useGvStore(ctx);
  const base = gvList(ctx, store);
  const [sort, setSort] = useState(null);
  const [q, setQ] = useState('');
  const col = sort && GV_LIST_COLS.find(c => c.key === sort.key);
  // Stopped groups stay at the bottom whichever way 可用 is sorted.
  const off = v => (col && col.key === 'avail' && v.status !== 'active' ? 1 : 0);
  const sorted = col ? [...base].sort((a, b) => { const x = col.sort(a), y = col.sort(b); return off(a) - off(b) || (x > y ? 1 : x < y ? -1 : 0) * sort.dir; }) : base;
  const list = sorted.filter(v => gvMatch(v, q));
  const tap = key => setSort(s => (s && s.key === key ? (s.dir === 1 ? { key, dir: -1 } : null) : { key, dir: key === 'avail' || key === 'name' || key === 'health' ? 1 : -1 }));
  const active = list.filter(v => v.status === 'active');
  const foot = {
    name: '合计', avail: `${gvSum(active, v => v.stats.ok)}/${gvSum(active, v => v.stats.total)}`,
    limited: gvSum(list, v => v.stats.limited), error: gvSum(list, v => v.stats.error), idle: gvSum(list, v => v.stats.idle),
    today: fmt.money(gvSum(list, v => v.usage.today)), yesterday: fmt.money(gvSum(list, v => v.usage.yesterday)), total: fmt.money(gvSum(list, v => v.usage.total)),
  };
  return (
    <Screen plain ctx={ctx} nav={gvListNav(ctx, base)}>
      <GvSearch q={q} setQ={setQ} />
      <div className="gv-tcap pad"><span>{sort ? `按${col.label}${sort.dir === 1 ? '升序' : '降序'}` : '按紧急程度'} · 点表头排序</span><span>左右滑动 <Icon name="arrowRight" size={12} weight={2.4} /></span></div>
      <div className="gv-tablewrap">
        <div className="gv-table" role="table">
          <div className="gv-tr gv-th gv-th-sort" role="row">
            {GV_LIST_COLS.map((c, i) => (
              <button key={c.key} role="columnheader" className={cx('gv-td', i === 0 && 'sticky', c.r && 'r', sort && sort.key === c.key && 'sorted')} style={{ width: c.w }} onClick={() => tap(c.key)}
                aria-sort={sort && sort.key === c.key ? (sort.dir === 1 ? 'ascending' : 'descending') : 'none'}>
                {c.label}{sort && sort.key === c.key && <Icon name={sort.dir === 1 ? 'chevronUp' : 'chevronDown'} size={11} weight={2.8} />}
              </button>
            ))}
          </div>
          {list.map(v => {
            const t = v.health.tone;
            return (
              <div key={v.id} role="row" className={cx('gv-tr', `tone-${t}`, (t === 'critical' || t === 'caution') && 'is-flagged', v.status !== 'active' && 'is-idle')} onClick={() => ctx.push({ kind: 'group', id: v.id })} onContextMenu={gvLongPress(ctx, store, v)}>
                {GV_LIST_COLS.map((c, i) => <div key={c.key} role="cell" className={cx('gv-td', i === 0 && 'sticky', i === 0 && (t === 'critical' || t === 'caution') && 'tone-rail', c.r && 'r')} style={{ width: c.w }}>{gvListCell(ctx, v, c.key)}</div>)}
              </div>
            );
          })}
          <div className="gv-tr gv-tf" role="row">
            {GV_LIST_COLS.map((c, i) => <div key={c.key} className={cx('gv-td num', i === 0 && 'sticky', c.r && 'r')} style={{ width: c.w }}>{foot[c.key] ?? ''}</div>)}
          </div>
        </div>
      </div>
      {list.length === 0 && <div className="empty pad">没有匹配的分组</div>}
      <div className="gv-tnote pad">“可用”合计只算启用中的分组；同一账号在多个分组时，每个分组各计一次。今日按 Key 所属分组统计，各组之和等于站点今日。</div>
    </Screen>
  );
}

/* ---------- 详情：共用分区 ---------- */

function gvDetailNav(ctx, store, v) {
  return <NavBar ctx={ctx} back title={v.name} subtitle={`${v.platform} · ${GV_BILLING[v.subscriptionType]} · ${v.exclusive ? '专属' : '公开'}`} trailing={<GlassButton icon="more" onClick={() => gvMenu(ctx, store, v)} />} />;
}

function GvUsageSection({ ctx, v, index }) {
  const { skin } = ctx;
  const caps = gvCaps(v);
  const ts = v.todayStats;
  return (
    <Section skin={skin} title="用量与容量" meta="按 Key 所属分组 · 00:00 切分" index={index}>
      <div className="grid3 pad">
        <div><small>今日</small><skin.Money value={v.usage.today} size="l" /></div>
        <div><small>昨日</small><skin.Money value={v.usage.yesterday} size="l" /></div>
        <div><small>累计 · 全部时间</small><skin.Money value={v.usage.total} size="l" /></div>
      </div>
      {ts && (
        <div className="kv-row pad">
          <span>请求 <b className="num">{fmt.grouped(ts.requests)}</b></span>
          <span>Tokens <b className="num">{fmt.compact(ts.tokens)}</b></span>
          <span>成本 <b className="num">{fmt.money(ts.cost)}</b></span>
        </div>
      )}
      {caps.length ? caps.map(c => (
        <div key={c.label} className="cap-line pad"><span className="cap-label">{c.label}</span><skin.Capacity used={c.used} limit={c.limit} wide /></div>
      )) : <div className="cap-line pad"><span className="cap-label">容量</span><span className="dim num">—</span><small className="gv-capnote">{gvCapNote(v)}</small></div>}
    </Section>
  );
}

function GvConfigGrid({ ctx, v }) {
  const edit = () => gvEdit(ctx, v);
  return (
    <>
      <div className="kv-grid pad">
        <KV label="费率倍数" value={<span className="num">{gvRate(v.rate)}</span>} onClick={edit} />
        <KV label="计费类型" value={GV_BILLING[v.subscriptionType]} />
        <KV label="每用户 RPM" value={<span className="num">{gvRpm(v.rpmLimit)}</span>} onClick={edit} />
        <KV label="类型" value={v.exclusive ? '专属' : '公开'} onClick={edit} />
        <KV label="客户端" value={v.claudeCodeOnly ? '仅限 Claude Code' : '所有客户端'} />
        <KV label="降级分组" value={v.claudeCodeOnly ? (v.fallbackName || '直接拒绝') : '—'} />
      </div>
      {v.description && <div className="gv-desc pad"><small>描述</small><span>{v.description}</span></div>}
      {v.subscriptionType === 'subscription' && (
        <div className="gv-quota pad">
          <small>订阅限额 · 每个订阅</small>
          <div className="gv-quota-row">
            <span><small>每日限额</small><b className="num">{gvLimit(v.limits && v.limits.day)}</b></span>
            <span><small>每周限额</small><b className="num">{gvLimit(v.limits && v.limits.week)}</b></span>
            <span><small>每月限额</small><b className="num">{gvLimit(v.limits && v.limits.month)}</b></span>
          </div>
        </div>
      )}
    </>
  );
}

function GvWebRow({ ctx }) {
  return (
    <Row skin={ctx.skin} tone="none" lead={<span className="lead-icon dim"><Icon name="web" /></span>} onClick={() => ctx.showToast({ text: '将在浏览器中打开 Web 分组页', icon: 'web', tone: 'neutral' })}>
      <div className="row-top"><span className="row-title">模型白名单、组合路由、图片计费</span></div>
      <div className="row-meta">在 Web 中编辑</div>
    </Row>
  );
}

function GvAddRow({ ctx, v }) {
  return (
    <Row skin={ctx.skin} tone="none" className="gv-add-row" chevron={false} lead={<span className="lead-icon gv-accent"><Icon name="plus" size={18} weight={2.4} /></span>} onClick={() => gvPick(ctx, v)}>
      <div className="row-top"><span className="row-title gv-accent">添加 {v.platform} 账号</span></div>
    </Row>
  );
}

function GvLinkRow({ ctx, icon, title, right, onClick }) {
  return (
    <Row skin={ctx.skin} tone="none" lead={<span className="lead-icon dim"><Icon name={icon} /></span>} onClick={onClick}>
      <div className="row-top"><span className="row-title">{title}</span>{right && <span className="row-right num gv-link-right">{right}</span>}</div>
    </Row>
  );
}

// Same pattern as the account detail's 记录: core's usage page filtered by this group (usage / ops error logs take group_id),
// then the group's own children (groups/:id/api-keys, groups/:id/subscriptions).
function GvRecordRows({ ctx, v }) {
  const go = scope => ctx.push(gvLogRoute(v, scope));
  return (
    <>
      <GvLinkRow ctx={ctx} icon="octagon" title="错误请求" right={`近 24 小时 ${gvLogCount(v, 'errors')} 条`} onClick={() => go('errors')} />
      <GvLinkRow ctx={ctx} icon="signal" title="上游错误" right={`近 24 小时 ${gvLogCount(v, 'upstream')} 条`} onClick={() => go('upstream')} />
      <GvLinkRow ctx={ctx} icon="list" title="使用记录" onClick={() => go('usage')} />
      <GvLinkRow ctx={ctx} icon="key" title="API 密钥" right={`${v.apiKeys} 个`} onClick={() => ctx.push({ kind: 'groupKeys', id: v.id })} />
      {v.subscriptionType === 'subscription' && <GvLinkRow ctx={ctx} icon="docCheck" title="订阅" right={`生效中 ${v.subscriptions ?? 0} 个`} onClick={() => ctx.push({ kind: 'groupSubs', id: v.id })} />}
    </>
  );
}

function useGvGroup(ctx, route) {
  const store = useGvStore(ctx);
  const g = store.groups.find(x => x.id === route.id) || (route.name && store.groups.find(x => x.name === route.name));
  return { store, v: g ? gvView(ctx, store, g) : null };
}

function GvGone({ ctx }) {
  return <Screen ctx={ctx} nav={<NavBar ctx={ctx} back title="分组" />}><div className="empty pad">这个分组已删除</div></Screen>;
}

// Button row under the status card. A stopped group offers 启用分组 first (reversible, so it applies with 撤销 in the receipt).
function GvActions({ ctx, store, v }) {
  const urgent = v.health.key === 'none' || v.health.key === 'low';
  return (
    <div className="actions">
      {v.status !== 'active'
        ? <ActionButton label="启用分组" icon="play" primary onClick={() => gvSetStatus(ctx, store, v, 'active')} />
        : <ActionButton label="添加账号" icon="plus" primary={urgent} onClick={() => gvPick(ctx, v)} />}
      <ActionButton label="编辑分组" icon="compose" primary={v.status === 'active' && !urgent} onClick={() => gvEdit(ctx, v)} />
    </div>
  );
}

/* ---------- 详情 ① A 状态卡 + 成员列表 + 分区（已定） ---------- */

function GvHero({ ctx, v }) {
  const { skin } = ctx;
  const t = v.health.tone;
  const s = v.stats;
  if (v.health.key === 'off') {
    return <div className="hero hero-quiet tone-neutral"><skin.Glyph state="inactive" /><span>已停用 · 使用此分组的 API 密钥会被拒绝</span></div>;
  }
  const rail = t === 'critical' || t === 'caution';
  const blocked = s.total - s.ok;
  return (
    <div className={cx('hero gv-hero', `tone-${t}`, rail && skin.rowClass(t))}>
      <div className="hero-top">
        {rail ? <skin.Badge tone={t} label={v.health.label} big /> : <span className="gv-hero-ok"><skin.Glyph state="normal" />{v.health.label}</span>}
        <span className="hero-cause">{blocked ? `${blocked} 个不可用` : `共 ${s.total} 个账号`}</span>
      </div>
      <div className="gv-hero-figure">
        <skin.Num size="xl" className={rail ? 'tone-text' : ''}>{s.ok}</skin.Num>
        <span className="gv-hero-of num">/ {s.total}</span>
        <span className="gv-hero-unit">个账号可用</span>
      </div>
      <GvCells v={v} big />
      <GvLegend v={v} />
      <GvRecovery ctx={ctx} v={v} />
      {v.health.key === 'none' && <div className="gv-hero-warn">{s.total ? '没有可用的账号，这个分组的新请求会失败。先让成员账号恢复或启用调度，或加入同平台的可用账号。' : `分组里还没有账号，新请求会失败。${v.apiKeys ? '' : '目前也没有 API 密钥使用它。'}`}</div>}
    </div>
  );
}

function GvDetailRows({ ctx, route }) {
  const { skin } = ctx;
  const { store, v } = useGvGroup(ctx, route);
  const [swipe, endSwipe] = useGvDemoSwipe(route);
  if (!v) return <GvGone ctx={ctx} />;
  return (
    <Screen ctx={ctx} nav={gvDetailNav(ctx, store, v)}>
      <GvAlertBanner ctx={ctx} v={v} />
      <div className="detail-head">
        <GvHero ctx={ctx} v={v} />
        <GvActions ctx={ctx} store={store} v={v} />
      </div>
      <Section skin={skin} title="成员账号" meta={v.stats.total > 1 ? `${v.stats.total} 个 · 不可用在前` : `${v.stats.total} 个`} index="壹">
        {v.members.map(a => {
          const trailing = [gvStateAction(ctx, a), { label: '移出', icon: 'close', tone: 'critical', onPress: () => gvRemoveMember(ctx, v, a) }].filter(Boolean);
          // Same row as the accounts tab; the group is in the title, so line 2 keeps the platform and names only the other groups.
          return <GvSwipe key={a.id} open={swipe === a.id ? 'trailing' : null} onAct={endSwipe} trailing={trailing}><Slot slot="accountRow" ctx={ctx} a={a} omit="group" home={v.name} /></GvSwipe>;
        })}
        <GvAddRow ctx={ctx} v={v} />
      </Section>
      {v.members.some(a => a.state !== 'error' && !STATE_META[a.state].timed) && <GvMemberNote rows />}
      <GvUsageSection ctx={ctx} v={v} index="贰" />
      <Section skin={skin} title="记录与关联" index="叁"><GvRecordRows ctx={ctx} v={v} /></Section>
      <Section skin={skin} title="配置" index="肆">
        <GvConfigGrid ctx={ctx} v={v} />
        <GvWebRow ctx={ctx} />
      </Section>
    </Screen>
  );
}

/* ---------- 详情 ② 大环 + 磁贴 + 成员卡片 ---------- */

function GvMemberTile({ ctx, a }) {
  const { skin } = ctx;
  const tone = toneOf(a.state);
  return (
    <button className={cx('gv-mtile', `tone-${tone}`, (tone === 'critical' || tone === 'caution') && 'is-flagged tone-rail', (a.state === 'paused' || a.state === 'inactive') && 'is-idle')} onClick={() => ctx.push({ kind: 'account', id: a.id })}>
      <span className="gv-mtile-top"><skin.Glyph state={a.state} /><b>{a.name}</b></span>
      <span className="gv-mtile-state">{a.state === 'normal' ? <span className="gv-ok-text">正常</span> : <skin.Badge state={a.state} secs={remaining(a, ctx.elapsed)} />}</span>
      <span className="gv-mtile-foot">
        <span className="num">{a.conc ? `并发 ${a.conc[0]}/${a.conc[1]}` : '并发 —'}</span>
        <span className="gv-mtile-money"><small>账号今日</small><skin.Money value={a.todayCost} size="s" /></span>
      </span>
    </button>
  );
}

const gvCapLevel = r => (r >= 0.9 ? 'critical' : r >= 0.75 ? 'caution' : 'normal');

// Capacity tile: the same lines as the A / C “用量与容量” section, as thin bars.
function GvCapTile({ v }) {
  const caps = gvCaps(v);
  return (
    <div className="gv-tile gv-tile-cap">
      <small>容量</small>
      {caps.length ? caps.map(c => (
        <span key={c.label} className={cx('gv-capmini', `cap-${gvCapLevel(c.used / c.limit)}`)}>
          <span className="gv-capmini-top"><span>{c.label}</span><b className="num">{c.used}/{c.limit}</b></span>
          <span className="cap-track"><span className="cap-fill" style={{ width: `${Math.min(c.used / c.limit, 1) * 100}%` }} /></span>
        </span>
      )) : <><b className="num gv-tile-big">—</b><span className="gv-tile-sub">{gvCapNote(v)}</span></>}
    </div>
  );
}

function GvDetailRing({ ctx, route }) {
  const { skin } = ctx;
  const { store, v } = useGvGroup(ctx, route);
  if (!v) return <GvGone ctx={ctx} />;
  const t = v.health.tone;
  const rail = t === 'critical' || t === 'caution';
  const edit = () => gvEdit(ctx, v);
  const quota = v.subscriptionType === 'subscription';
  const off = v.status !== 'active';
  return (
    <Screen ctx={ctx} nav={gvDetailNav(ctx, store, v)}>
      <GvAlertBanner ctx={ctx} v={v} />
      <div className={cx('gv-big', `tone-${t}`, rail && 'is-flagged tone-rail', off && 'is-off')}>
        <GvRing v={v} size={140} stroke={13}>
          <GvAvail v={v} size="xl" /><small>{off ? '已停用' : '可用'}</small>
        </GvRing>
        <div className="gv-big-side">
          <span className={cx('gv-big-word', rail && 'tone-text')}>{v.health.label}</span>
          <GvLegend v={v} className="gv-legend-col" />
        </div>
        <GvRecovery ctx={ctx} v={v} />
        {v.health.key === 'none' && <div className="gv-hero-warn">没有可用的账号，这个分组的新请求会失败。</div>}
      </div>
      {off && (
        <div className="actions gv-ring-acts pad-x">
          <ActionButton label="启用分组" icon="play" primary onClick={() => gvSetStatus(ctx, store, v, 'active')} />
          <ActionButton label="编辑分组" icon="compose" onClick={edit} />
        </div>
      )}
      <div className="gv-tiles pad-x">
        <div className="gv-tile">
          <small>今日</small><b className="gv-tile-big"><skin.Money value={v.usage.today} size="l" /></b>
          <span className="gv-tile-sub">昨日 <skin.Money value={v.usage.yesterday} size="s" /></span>
          <span className="gv-tile-sub">累计 <skin.Money value={v.usage.total} size="s" /></span>
        </div>
        <button className="gv-tile" onClick={edit}><small>费率倍数</small><b className="num gv-tile-big">{gvRate(v.rate)}</b><span className="gv-tile-sub">{GV_BILLING[v.subscriptionType]}</span><span className="gv-tile-sub">{v.exclusive ? '专属分组' : '公开分组'}</span><i className="gv-tile-edit"><Icon name="compose" size={14} /></i></button>
        <GvCapTile v={v} />
        <button className="gv-tile" onClick={edit}>
          <small>{quota ? '订阅限额 · 每日' : '每用户 RPM'}</small>
          <b className="num gv-tile-big">{quota ? gvLimit(v.limits && v.limits.day) : gvRpm(v.rpmLimit)}</b>
          {quota
            ? <><span className="gv-tile-sub">每周 {gvLimit(v.limits && v.limits.week)}</span><span className="gv-tile-sub">每月 {gvLimit(v.limits && v.limits.month)}</span></>
            : <span className="gv-tile-sub">每位用户每分钟上限</span>}
          <i className="gv-tile-edit"><Icon name="compose" size={14} /></i>
        </button>
      </div>
      <div className="gv-mhead pad"><span>成员账号 <b className="num">{v.stats.total}</b></span><button className="gv-link" onClick={() => gvPick(ctx, v)}><Icon name="plus" size={14} weight={2.6} />添加</button></div>
      <div className="gv-mgrid pad-x">
        {v.members.map(a => <GvMemberTile key={a.id} ctx={ctx} a={a} />)}
        <button className="gv-mtile gv-mtile-add" onClick={() => gvPick(ctx, v)}><Icon name="plus" size={20} weight={2.2} /><span>添加账号</span></button>
      </div>
      {v.members.length > 0 && <GvMemberNote />}
      <Section skin={skin} title="记录与关联" index="壹"><GvRecordRows ctx={ctx} v={v} /></Section>
      <Section skin={skin} title="配置" index="贰">
        <GvConfigGrid ctx={ctx} v={v} />
        <GvWebRow ctx={ctx} />
      </Section>
    </Screen>
  );
}

/* ---------- 详情 ③ 紧凑状态条 + 成员表格 ---------- */

const GV_MEMBER_COLS = [
  { key: 'name', label: '账号', w: 164 },
  { key: 'state', label: '状态', w: 152 },
  { key: 'conc', label: '并发', w: 56, r: true },
  { key: 'today', label: '账号今日', w: 84, r: true },
  { key: 'req', label: '账号请求', w: 72, r: true },
  { key: 'prio', label: '优先级', w: 58, r: true },
  { key: 'type', label: '类型', w: 70 },
];

function gvMemberCell(ctx, a, key) {
  const { skin } = ctx;
  switch (key) {
    case 'name': return <><skin.Glyph state={a.state} /><span className="gv-cell-text">{a.name}</span></>;
    case 'state': return a.state === 'normal' ? <span className="gv-ok-text">正常</span> : <skin.Badge state={a.state} secs={remaining(a, ctx.elapsed)} />;
    case 'conc': return <span className="num">{a.conc ? `${a.conc[0]}/${a.conc[1]}` : '—'}</span>;
    case 'today': return <skin.Money value={a.todayCost} size="s" />;
    case 'req': return <span className="num">{fmt.grouped(a.todayReq)}</span>;
    case 'prio': return <span className="num">{a.priority ?? '—'}</span>;
    default: return a.type;
  }
}

function GvDetailTable({ ctx, route }) {
  const { skin } = ctx;
  const { store, v } = useGvGroup(ctx, route);
  if (!v) return <GvGone ctx={ctx} />;
  const t = v.health.tone;
  const rail = t === 'critical' || t === 'caution';
  const caps = gvCaps(v);
  const conc = gvConc(v);
  // No “today” total: member figures span every group an account serves, so they do not add up to this group's today.
  const foot = { name: `合计 ${v.stats.total} 个`, state: `可用 ${v.stats.ok}`, conc: conc ? `${conc[0]}/${conc[1]}` : '—' };
  return (
    <Screen plain ctx={ctx} nav={gvDetailNav(ctx, store, v)}>
      <GvAlertBanner ctx={ctx} v={v} />
      <div className={cx('gv-tstrip', `tone-${t}`, rail && skin.rowClass(t))}>
        <div className="gv-tstrip-top">
          <GvAvail v={v} size="l" /><span className="gv-tstrip-unit">个账号可用</span>
          {v.health.key !== 'ok' && <skin.Badge tone={t} label={v.health.label} />}
        </div>
        <GvCells v={v} big />
        <div className="gv-tstrip-foot"><GvLegend v={v} /></div>
        <GvRecovery ctx={ctx} v={v} />
      </div>
      <div className="list-head"><span>成员账号</span><b className="num">{v.stats.total} 个 · 左右滑动</b></div>
      <div className="gv-tablewrap">
        <div className="gv-table" role="table">
          <div className="gv-tr gv-th" role="row">
            {GV_MEMBER_COLS.map((c, i) => <div key={c.key} role="columnheader" className={cx('gv-td', i === 0 && 'sticky', c.r && 'r')} style={{ width: c.w }}>{c.label}</div>)}
          </div>
          {v.members.map(a => {
            const tone = toneOf(a.state);
            return (
              <div key={a.id} role="row" className={cx('gv-tr', `tone-${tone}`, (tone === 'critical' || tone === 'caution') && 'is-flagged', (a.state === 'paused' || a.state === 'inactive') && 'is-idle')} onClick={() => ctx.push({ kind: 'account', id: a.id })}>
                {GV_MEMBER_COLS.map((c, i) => <div key={c.key} role="cell" className={cx('gv-td', i === 0 && 'sticky', i === 0 && (tone === 'critical' || tone === 'caution') && 'tone-rail', c.r && 'r')} style={{ width: c.w }}>{gvMemberCell(ctx, a, c.key)}</div>)}
              </div>
            );
          })}
          <div className="gv-tr gv-tf" role="row">
            {GV_MEMBER_COLS.map((c, i) => <div key={c.key} className={cx('gv-td num', i === 0 && 'sticky', c.r && 'r')} style={{ width: c.w }}>{foot[c.key] ?? ''}</div>)}
          </div>
        </div>
      </div>
      {v.members.length > 0 && <GvMemberNote table />}
      <div className="gv-tbtns pad"><GvActions ctx={ctx} store={store} v={v} /></div>
      <div className="list-head"><span>分组用量与容量</span><b className="num">按 Key 所属分组 · 00:00 切分</b></div>
      <div className="kv-row pad gv-kvrow gv-surface">
        <span>今日 <skin.Money value={v.usage.today} size="s" /></span>
        <span>昨日 <skin.Money value={v.usage.yesterday} size="s" /></span>
        <span>累计（全部时间） <skin.Money value={v.usage.total} size="s" /></span>
        {caps.length
          ? caps.map(c => <span key={c.label}>{c.label} <b className="num">{c.used}/{c.limit}</b></span>)
          : <span>容量 <b className="num">—</b>（{gvCapNote(v)}）</span>}
      </div>
      <div className="list-head"><span>记录与关联</span></div>
      <div className="gv-surface"><GvRecordRows ctx={ctx} v={v} /></div>
      <div className="list-head"><span>配置</span></div>
      <div className="gv-surface"><GvConfigGrid ctx={ctx} v={v} /><GvWebRow ctx={ctx} /></div>
    </Screen>
  );
}

/* ---------- 记录与关联的下一级：API 密钥、订阅 ---------- */

// Key row: line 1 = name + status, masked key pinned right; line 2 = owner · last used, today's spend pinned right (the money
// column of the group and user lists); line 3 only for a key with its own quota (quota > 0): quota_used against it.
// Tapping opens the owner, where the key's group and rate limits are changed. Exhausted keys ride the caution rail.
// Key status words are core's KEY_STATUS_WORD (Web's: 已停用 / 额度耗尽 / 已过期); the owner's own status is a user's (已禁用).
function GvKeyRow({ ctx, k }) {
  const { skin } = ctx;
  const u = ctx.users[k.userId];
  const word = KEY_STATUS_WORD[k.status];
  const exhausted = k.status === 'quota_exhausted';
  const idle = k.status === 'disabled' || k.status === 'expired';
  return (
    <Row skin={skin} tone={exhausted ? 'caution' : 'none'} className={cx('gv-key-row', exhausted && 'tone-caution', idle && 'is-idle')}
      lead={<span className="lead-icon dim"><Icon name="key" /></span>} onClick={() => ctx.push({ kind: 'user', id: k.userId })}>
      <div className="row-top"><span className="gv-key-title"><span className="row-title">{k.name}</span>{word && <skin.Badge tone={exhausted ? 'caution' : 'neutral'} label={word} />}</span><span className="row-right mono">{k.masked}</span></div>
      <div className="row-foot">
        <span className="row-meta">{u ? u.name : `用户 #${k.userId}`}{u && u.status === 'disabled' ? '（已禁用）' : ''} · {k.last || '从未使用'}</span>
        <span className="row-money"><small>今日</small><skin.Money value={k.today} size="s" /></span>
      </div>
      {k.quota > 0 && (
        <div className="gv-key-quota"><small>额度</small><skin.Capacity used={k.quotaUsed} limit={k.quota} money wide /></div>
      )}
    </Row>
  );
}

function GvMore({ shown, total, unit }) {
  if (shown >= total) return null;
  return <div className="gv-more pad"><span className="num">已显示 {shown} / {total} {unit}</span> · 滚动到底继续加载</div>;
}

function GvKeysScreen({ ctx, route }) {
  const { v } = useGvGroup(ctx, route);
  if (!v) return <GvGone ctx={ctx} />;
  const rows = DEMO.keys.filter(k => k.groupId === v.id).sort((a, b) => b.id - a.id);
  const total = Math.max(v.apiKeys || 0, rows.length);
  return (
    <Screen plain ctx={ctx} nav={<NavBar ctx={ctx} back title="API 密钥" subtitle={`${v.name} · 共 ${total} 个`} />}>
      <div className="list-group">
        <div className="list-head"><span>新建的在前</span><b className="num">所属用户 · 最近使用 · 今日</b></div>
        {rows.map(k => <GvKeyRow key={k.id} ctx={ctx} k={k} />)}
        {!rows.length && (
          <div className="lg-empty pad"><b className="num lg-empty-dash" aria-hidden="true">—</b><span>还没有 API 密钥使用这个分组</span></div>
        )}
        <GvMore shown={rows.length} total={total} unit="个" />
      </div>
      <div className="gv-mnote pad">点按进入所属用户。给 Key 换分组、重置速率限制在用户的 Key 里操作。</div>
    </Screen>
  );
}

function GvSubWin({ label, used, limit }) {
  const r = limit ? used / limit : 0;
  return (
    <span className={cx('gv-subwin', limit && `cap-${gvCapLevel(r)}`)}>
      <small>{label}</small>
      <b className="num gv-subwin-val">{fmt.money(used, { digits: used >= 100 ? 0 : 2 })}{limit ? <i> / {fmt.money(limit, { digits: 0 })}</i> : null}</b>
      {limit ? <span className="cap-track"><span className="cap-fill" style={{ width: `${Math.min(r, 1) * 100}%` }} /></span> : <span className="gv-subwin-none">无限制</span>}
    </span>
  );
}

// Subscription row: owner, the three usage windows against the group's per-subscription limits, and the end date.
// Ending within 7 days rides the caution rail; expired / suspended rows are dimmed and show no usage.
function GvSubRow({ ctx, s, limits }) {
  const { skin } = ctx;
  const u = ctx.users[s.userId];
  const st = GV_SUB_STATUS[s.status];
  const live = s.status === 'active';
  const left = daysUntil(s.expires);
  const soon = live && left <= 7;
  const end = s.status === 'expired' ? `${s.expires} 已到期` : `至 ${s.expires}`;
  return (
    <Row skin={skin} tone={soon ? 'caution' : 'none'} className={cx('gv-sub-row', soon && 'tone-caution', !live && 'is-idle')}
      lead={<span className="avatar">{u ? u.name.slice(0, 1) : '?'}</span>} onClick={() => ctx.push({ kind: 'user', id: s.userId })}>
      <div className="row-top">
        <span className="row-title">{u ? u.name : `用户 #${s.userId}`}</span>
        {st ? <skin.Badge tone={st.tone} label={st.label} /> : <span className={cx('row-right num', soon && 'tone-text')}>{left > 0 ? `剩余 ${left} 天` : '今天到期'}</span>}
      </div>
      {live && (
        <div className="gv-subq">
          <GvSubWin label="每日" used={s.day} limit={limits && limits.day} />
          <GvSubWin label="每周" used={s.week} limit={limits && limits.week} />
          <GvSubWin label="每月" used={s.month} limit={limits && limits.month} />
        </div>
      )}
      <div className="row-meta"><span className="num">{end}</span>{u ? ` · ${u.email}` : ''}</div>
    </Row>
  );
}

function GvSubsScreen({ ctx, route }) {
  const { skin } = ctx;
  const { v } = useGvGroup(ctx, route);
  if (!v) return <GvGone ctx={ctx} />;
  const quota = v.subscriptionType === 'subscription';
  const { rows, total, active } = quota ? groupSubscriptions(v.id) : { rows: [], total: 0, active: 0 };
  return (
    <Screen plain ctx={ctx} nav={<NavBar ctx={ctx} back title="订阅" subtitle={`${v.name} · 生效中 ${active} 个`} />}>
      {quota && (
        <div className="gv-subhead pad">
          <small>每个订阅的限额</small>
          <span><span>每日 <b className="num">{gvLimit(v.limits && v.limits.day)}</b></span><span>每周 <b className="num">{gvLimit(v.limits && v.limits.week)}</b></span><span>每月 <b className="num">{gvLimit(v.limits && v.limits.month)}</b></span></span>
        </div>
      )}
      <div className="list-group">
        <div className="list-head"><span>新分配的在前</span><b className="num">用量 · 到期</b></div>
        {rows.map(s => <GvSubRow key={s.id} ctx={ctx} s={s} limits={v.limits} />)}
        {!rows.length && (
          <div className="lg-empty pad"><b className="num lg-empty-dash" aria-hidden="true">—</b><span>{quota ? '这个分组还没有订阅' : '标准（余额）分组没有订阅'}</span></div>
        )}
        <GvMore shown={rows.length} total={total} unit="条" />
      </div>
      <div className="gv-mnote pad">点按进入用户。调整有效期、重置配额、撤销在 Web 订阅管理中操作。</div>
    </Screen>
  );
}

/* ---------- 成员批量写入的逐项结果 ---------- */

// Opened from a receipt that reported failures. Each account was one PUT: failed ones are unchanged and can be retried here,
// and the ones that went through can be undone together (the receipt itself had room for only one button).
function GvBatchScreen({ ctx, route }) {
  const { skin } = ctx;
  const store = useGvStore(ctx);
  const [items, setItems] = useState(route.items || []);
  const g = store.groups.find(x => x.id === route.id);
  const name = g ? g.name : route.name;
  const failed = items.filter(x => !x.ok);
  const done = items.filter(x => x.ok && !x.undone);
  const undone = items.filter(x => x.undone);
  const verb = x => (x.join ? '加入' : '移出');
  const retry = () => {
    failed.forEach(x => gvMoveOne(ctx, x.id, name, x.join));
    setItems(xs => xs.map(x => (x.ok ? x : { ...x, ok: true, retried: true, reason: null })));
    ctx.showToast({ text: `重试成功 · ${gvMemberText(failed.map(x => ({ ...x, ok: true })))}`, icon: 'checkCircle' });
  };
  const revert = () => {
    done.forEach(x => gvMoveOne(ctx, x.id, name, !x.join));
    setItems(xs => xs.map(x => (x.ok && !x.undone ? { ...x, undone: true } : x)));
    ctx.showToast({ text: `已撤销 ${done.length} 个账号的改动`, icon: 'restore', tone: 'neutral' });
  };
  const account = x => ctx.accounts[x.id] || { state: 'inactive', name: x.name };
  const row = (x, right, note) => {
    const a = account(x);
    return (
      <Row key={x.id} skin={skin} tone={note ? 'critical' : 'none'} className={cx(note && 'tone-critical')} lead={<skin.Glyph state={a.state} />} onClick={() => ctx.push({ kind: 'account', id: x.id })}>
        <div className="row-top"><span className="row-title">{a.name}</span>{right}</div>
        {note && <div className="row-note">{note}</div>}
      </Row>
    );
  };
  return (
    <Screen ctx={ctx} nav={<NavBar ctx={ctx} back title="逐项结果" subtitle={`${name} · ${items.length} 个账号`} />}>
      <div className="detail-head">
        {failed.length ? (
          <div className={cx('hero tone-caution', skin.rowClass('caution'))}>
            <div className="hero-top"><skin.Badge tone="caution" label={`${failed.length} 个失败`} big />{done.length > 0 && <span className="hero-cause">{done.length} 个成功</span>}</div>
            <div className="gv-batch-text">每个账号单独提交。失败的账号没有改动，可以直接重试，或点开账号单独处理。</div>
          </div>
        ) : (
          <div className="hero hero-quiet tone-ok"><skin.Glyph state="normal" /><span>{done.length ? `全部完成 · ${gvMemberText(done)}` : '已全部撤销'}</span></div>
        )}
        {(failed.length > 0 || done.length > 0) && (
          <div className="actions">
            {failed.length > 0 && <ActionButton label={`重试 ${failed.length} 个`} icon="refresh" primary onClick={retry} />}
            {done.length > 0 && <ActionButton label={`撤销成功的 ${done.length} 个`} icon="restore" onClick={revert} />}
          </div>
        )}
      </div>
      {failed.length > 0 && (
        <Section skin={skin} title="失败" meta={`${failed.length} 个 · 没有改动`} index="壹">
          {failed.map(x => row(x, <skin.Badge tone="critical" label={`${verb(x)}失败`} />, x.reason))}
        </Section>
      )}
      {(done.length > 0 || undone.length > 0) && (
        <Section skin={skin} title="成功" meta={`${done.length} 个`} index={failed.length ? '贰' : '壹'}>
          {[...done, ...undone].map(x => row(x, x.undone ? <span className="row-right dim">已撤销</span> : <span className="gv-ok-text">{x.retried ? `重试后已${verb(x)}` : `已${verb(x)}`}</span>))}
        </Section>
      )}
    </Screen>
  );
}

/* ---------- 编辑 / 新建分组（sheet，内含账号选择页） ---------- */

// Sheet chrome like core's Sheet, but the overlay closes while the leading button can mean "back" on the inner page.
function GvSheet({ title, onClose, leading, trailing, footer, children }) {
  return (
    <div className="overlay overlay-dim sheet-overlay" onClick={onClose}>
      <div className="sheet sheet-tall gv-sheet" onClick={e => e.stopPropagation()}>
        <div className="sheet-grabber" />
        <div className="sheet-bar">{leading}<div className="sheet-title">{title}</div>{trailing || <span className="nav-spacer" />}</div>
        <div className="sheet-body">{children}</div>
        {footer && <div className="gv-sheet-foot">{footer}</div>}
      </div>
    </div>
  );
}

const gvBarBtn = (label, onClick, opts = {}) => (
  <button className={cx('glass-btn glass-btn-text', opts.prominent && 'glass-prominent', opts.back && 'gv-back')} onClick={onClick} disabled={opts.disabled}>
    {opts.back && <Icon name="back" size={17} weight={2.4} />}<span>{label}</span>
  </button>
);

function GvFormSection({ title, foot, children }) {
  return (
    <div className="gv-fsec">
      {title && <div className="gv-fsec-title">{title}</div>}
      <div className="gv-fsec-body">{children}</div>
      {foot && <div className="gv-fsec-foot">{foot}</div>}
    </div>
  );
}

function GvField({ label, children }) {
  return (
    <div className="gv-field">
      <span className="gv-field-label">{label}</span>
      <span className="gv-field-ctl">{children}</span>
    </div>
  );
}

function GvSwitch({ on, onLabel, offLabel, onToggle, label }) {
  return (
    <button className="gv-switch-btn" onClick={onToggle} role="switch" aria-checked={on} aria-label={label}>
      <span className="gv-switch-label">{on ? onLabel : offLabel}</span><span className={cx('st-switch', on && 'on')}><i /></span>
    </button>
  );
}

function GvStepper({ value, onChange }) {
  const n = Number(value);
  const step = d => onChange(String(Math.max(0.1, Math.round(((Number.isFinite(n) ? n : 1) + d) * 10) / 10)));
  return (
    <span className="gv-stepper">
      <button onClick={() => step(-0.1)} aria-label="减少 0.1"><i className="gv-bar" /></button>
      <span className="gv-stepper-val"><i>×</i><input className="num" inputMode="decimal" value={value} onChange={e => onChange(e.target.value.replace(/[^\d.]/g, ''))} aria-label="费率倍数" /></span>
      <button onClick={() => step(0.1)} aria-label="增加 0.1"><Icon name="plus" size={16} weight={2.6} /></button>
    </span>
  );
}

// Menu-style Picker row (SwiftUI Picker .menu, like the new-account form's platform): current value + up/down chevron.
function GvPlatformPicker({ value, onChange }) {
  return (
    <span className="gv-select">
      <select value={value} onChange={e => onChange(e.target.value)} aria-label="平台">
        {GV_PLATFORMS.map(p => <option key={p} value={p}>{p}</option>)}
      </select>
      <span className="gv-select-chev" aria-hidden="true"><Icon name="chevronUp" size={10} weight={2.8} /><Icon name="chevronDown" size={10} weight={2.8} /></span>
    </span>
  );
}

// Empty = 无限制: the “$” only appears once there is an amount.
function GvMoneyInput({ value, onChange, label }) {
  return (
    <span className="gv-money-in">{value !== '' && <i>$</i>}<input className="num" inputMode="decimal" placeholder="无限制" value={value} onChange={e => onChange(e.target.value.replace(/[^\d.]/g, ''))} aria-label={label} /></span>
  );
}

// Account picker shared by the edit sheet (draft) and the direct "添加账号" sheet. Only accounts this group can schedule are listed
// (same platform; a composite group takes any); schedulable accounts first.
function GvPickList({ ctx, platform, exclude, selected, onToggle }) {
  const { skin } = ctx;
  const [q, setQ] = useState('');
  const rank = a => (a.state === 'normal' ? 0 : a.state === 'paused' || a.state === 'inactive' ? 1 : 2);
  const same = Object.values(ctx.accounts).filter(a => platform === GV_COMPOSITE || a.platform === platform);
  const free = same.filter(a => !exclude.includes(a.id));
  const rows = sortByUrgency(free.filter(a => a.name.toLowerCase().includes(q.trim().toLowerCase()))).sort((a, b) => rank(a) - rank(b));
  const emptyText = !same.length ? `还没有 ${platform} 账号` : !free.length ? `${platform} 账号都已在这个分组里` : '没有匹配的账号';
  return (
    <>
      <label className="search-field gv-pick-search"><Icon name="search" size={16} /><input placeholder={`搜索 ${platform} 账号`} value={q} onChange={e => setQ(e.target.value)} aria-label={`搜索 ${platform} 账号`} /></label>
      {rows.length === 0 && <div className="empty">{emptyText}</div>}
      {rows.length > 0 && (
        <div className="gv-pick-group">
          <div className="picker-group">{platform} 账号</div>
          <div className="gv-pick-list">
            {rows.map(a => {
              const on = selected.includes(a.id);
              const stopped = schedLabel(a);
              return (
                <Row key={a.id} skin={skin} tone="none" chevron={false} className={cx(on && 'is-selected')} onClick={() => onToggle(a.id)}
                  lead={<span className={cx('select-ring', on && 'on')}>{on && <Icon name="check" size={14} weight={3} />}</span>}>
                  <div className="row-top"><span className="row-title">{a.name}</span>{a.state === 'normal' ? <span className="gv-ok-text">可调度</span> : <skin.Badge state={a.state} secs={remaining(a, ctx.elapsed)} />}</div>
                  <div className="row-meta">{stopped && <><span className="sched-mark">{stopped}</span> · </>}{a.type} · {a.groups.length ? `已在 ${a.groups.join('、')}` : '未分组'}</div>
                </Row>
              );
            })}
          </div>
        </div>
      )}
      <div className="gv-form-note">只列出 {platform} 账号：其他平台的账号不会被这个分组调度。每个账号单独提交，个别失败不影响其他账号。</div>
    </>
  );
}

const gvOkCount = (ctx, ids, platform) => ids.filter(id => ctx.accounts[id] && gvSchedulable(ctx.accounts[id], platform)).length;

// Direct add from the detail page: reversible, so it applies at once; the receipt offers 撤销, or 查看 when some writes failed.
function GvPickSheet({ ctx, sheet }) {
  const store = useGvStore(ctx);
  const g = store.groups.find(x => x.id === sheet.id);
  const [selected, setSelected] = useState(sheet.preselect || []);
  if (!g) return null;
  const v = gvView(ctx, store, g);
  const ids = v.members.map(a => a.id);
  const toggle = id => setSelected(s => (s.includes(id) ? s.filter(x => x !== id) : [...s, id]));
  const before = v.stats.ok;
  const after = gvOkCount(ctx, [...ids, ...selected], g.platform);
  const add = () => {
    const res = gvApplyMembers(ctx, g.name, g.name, [...ids, ...selected], sheet.sim);
    const reached = gvOkCount(ctx, [...ids, ...res.items.filter(x => x.ok).map(x => x.id)], g.platform);
    ctx.closeSheet();
    gvMemberReceipt(ctx, g, res, { suffix: reached !== before ? `可用 ${before} → ${reached}` : null, undo: true });
  };
  return (
    <GvSheet title={`添加到「${g.name}」`} onClose={ctx.closeSheet} leading={gvBarBtn('取消', ctx.closeSheet)}
      footer={<>
        <div className="gv-pick-preview">{selected.length ? <>加入后可用 <b className="num">{before} → {after}</b> / <span className="num">{ids.length + selected.length}</span></> : '选择要加入的账号'}</div>
        <button className="submit" disabled={!selected.length} onClick={add}>{selected.length ? `加入 ${selected.length} 个账号` : '加入'}</button>
      </>}>
      <GvPickList ctx={ctx} platform={g.platform} exclude={ids} selected={selected} onToggle={toggle} />
    </GvSheet>
  );
}

// New groups follow Web's create form: POST admin/groups always creates an active group (there is no status field), public,
// rate 1.0, standard billing, no RPM limit, platform Anthropic.
const GV_NEW = { name: '', description: '', platform: 'Anthropic', status: 'active', exclusive: false, subscriptionType: 'standard', rate: 1.0, rpmLimit: 0, limits: null,
  claudeCodeOnly: false, fallbackGroupId: null, usage: { today: 0, yesterday: 0, total: 0 }, todayStats: { requests: 0, tokens: 0, cost: 0, standard: 0 },
  capacity: null, apiKeys: 0, subscriptions: null };

const gvNum = s => (s === '' || s === undefined ? null : Number(s));

function gvDiff(g0, next) {
  const lines = [];
  if (next.name !== g0.name) lines.push(`名称 ${g0.name} → ${next.name}`);
  if ((next.description || '') !== (g0.description || '')) lines.push('描述已修改');
  if (next.rate !== g0.rate) lines.push(`费率倍数 ${gvRate(g0.rate)} → ${gvRate(next.rate)}`);
  if (next.rpmLimit !== g0.rpmLimit) lines.push(`每用户 RPM ${gvRpm(g0.rpmLimit)} → ${gvRpm(next.rpmLimit)}`);
  if (next.subscriptionType === 'subscription') {
    [['day', '每日'], ['week', '每周'], ['month', '每月']].forEach(([k, label]) => {
      const a = g0.limits && g0.limits[k], b = next.limits && next.limits[k];
      if ((a || null) !== (b || null)) lines.push(`${label}限额 ${gvLimit(a)} → ${gvLimit(b)}`);
    });
  }
  if (next.exclusive !== g0.exclusive) lines.push(next.exclusive ? '公开 → 专属：之后只有分配了这个分组的用户能选它' : '专属 → 公开：之后所有用户新建 API 密钥时都能选它');
  if (next.status !== g0.status) lines.push(next.status === 'active' ? '启用分组' : `停用分组（${g0.apiKeys} 个 API 密钥会被拒绝）`);
  return lines;
}

function gvDraftOf(g0, v0, preset) {
  const lim = k => (g0.limits && g0.limits[k] ? String(g0.limits[k]) : '');
  return {
    name: g0.name, description: g0.description || '', platform: g0.platform, billing: g0.subscriptionType, status: g0.status, exclusive: g0.exclusive,
    rate: gvRate(g0.rate).slice(1), rpm: g0.rpmLimit ? String(g0.rpmLimit) : '', day: lim('day'), week: lim('week'), month: lim('month'),
    members: v0 ? v0.members.map(a => a.id) : [],
    ...(preset || {}),
  };
}

// The new-group form opens in a known state for demos and smoke routes: sheet.draft overrides fields (e.g. {name, members}).
function GvEditSheet({ ctx, sheet }) {
  const { skin } = ctx;
  const store = useGvStore(ctx);
  const isNew = Boolean(sheet.isNew);
  const g0 = isNew ? GV_NEW : store.groups.find(x => x.id === sheet.id);
  const v0 = !isNew && g0 ? gvView(ctx, store, g0) : null;
  const [d, setD] = useState(() => (g0 ? gvDraftOf(g0, v0, sheet.draft) : null));
  const [page, setPage] = useState(sheet.page || 'form');
  const [picked, setPicked] = useState(sheet.preselect || []);
  if (!g0) return null;
  const set = patch => setD(x => ({ ...x, ...patch }));
  const rate = Number(d.rate);
  const next = {
    name: d.name.trim(), description: d.description.trim(), platform: d.platform, subscriptionType: d.billing, status: isNew ? 'active' : d.status, exclusive: d.exclusive,
    rate, rpmLimit: Math.max(0, parseInt(d.rpm || '0', 10) || 0),
    limits: d.billing === 'subscription' ? { day: gvNum(d.day), week: gvNum(d.week), month: gvNum(d.month) } : null,
  };
  const before = v0 ? v0.members.map(a => a.id) : [];
  const adds = d.members.filter(id => !before.includes(id));
  const removes = before.filter(id => !d.members.includes(id));
  const changes = isNew ? [] : gvDiff(g0, next);
  const dupName = store.groups.some(x => x.name === next.name && x.id !== g0.id);
  const valid = next.name && !dupName && Number.isFinite(rate) && rate > 0;
  const dirty = isNew ? Boolean(next.name) : changes.length + adds.length + removes.length > 0;
  const okBefore = v0 ? v0.stats.ok : 0;
  const okAfter = gvOkCount(ctx, d.members, d.platform);
  const live = next.status === 'active';
  const openToAll = live && !next.exclusive;

  const apply = () => {
    if (isNew) {
      const id = gvNextId(store.groups);
      ctx.addGroup({ ...GV_NEW, ...next, id, sortOrder: id, subscriptions: next.subscriptionType === 'subscription' ? 0 : null });
      const res = gvApplyMembers(ctx, next.name, next.name, d.members, sheet.sim);
      ctx.closeSheet();
      gvMemberReceipt(ctx, { id, name: next.name }, res, { prefix: `已创建「${next.name}」` });
      return;
    }
    // A rename goes through core (it renames the group in every account's list); member joins / leaves are one write per account.
    ctx.updateGroup(g0.id, next);
    const res = gvApplyMembers(ctx, g0.name, next.name, d.members, sheet.sim);
    ctx.closeSheet();
    gvMemberReceipt(ctx, { id: g0.id, name: next.name }, res, { prefix: `已保存「${next.name}」`, icon: 'checkCircle' });
  };
  const emptyAfter = !isNew && live && okBefore > 0 && okAfter === 0;
  const weighty = next.rate !== g0.rate || next.rpmLimit !== g0.rpmLimit || next.exclusive !== g0.exclusive || changes.some(l => l.includes('限额') || l.includes('停用'));
  const save = () => {
    if (isNew) {
      // Created active and public by default (same as Web). Only a public group nobody can serve yet asks first.
      if (!openToAll || okAfter > 0) { apply(); return; }
      ctx.confirm({
        title: `创建公开分组「${next.name}」？`,
        message: `站点 ${ctx.site} · ${next.platform} · 费率倍数 ${gvRate(next.rate)}\n创建后所有用户新建 API 密钥时都能选它，但现在没有可用账号，选它的请求会失败。`,
        actions: [{ label: '仍然创建', role: 'default', onPress: apply }, { label: '取消', role: 'cancel' }],
      });
      return;
    }
    if (!weighty && !emptyAfter) { apply(); return; }
    const memberParts = [adds.length && `加入 ${adds.length} 个`, removes.length && `移出 ${removes.length} 个`].filter(Boolean);
    const memberLine = memberParts.length ? `成员：${memberParts.join(' · ')}（逐个提交）` : null;
    ctx.confirm({
      title: `保存「${next.name}」的修改？`,
      message: [`站点 ${ctx.site} · 分组「${g0.name}」`, ...changes, memberLine,
        next.rate !== g0.rate ? '此后的请求按新倍率计费，已产生的记录不变。' : null,
        emptyAfter ? '保存后这个分组没有可用的账号，新请求会失败。' : null].filter(Boolean).join('\n'),
      actions: [emptyAfter ? { label: '仍然保存', role: 'destructive', onPress: apply } : { label: '保存修改', role: 'default', onPress: apply }, { label: '取消', role: 'cancel' }],
    });
  };

  if (page === 'pick') {
    const toggle = id => setPicked(s => (s.includes(id) ? s.filter(x => x !== id) : [...s, id]));
    const done = () => { set({ members: [...d.members, ...picked] }); setPicked([]); setPage('form'); };
    return (
      <GvSheet title="添加账号" onClose={ctx.closeSheet} leading={gvBarBtn(isNew ? '新建分组' : '编辑分组', () => { setPicked([]); setPage('form'); }, { back: true })}
        trailing={gvBarBtn(picked.length ? `添加 ${picked.length}` : '添加', done, { prominent: picked.length > 0, disabled: !picked.length })}>
        <GvPickList ctx={ctx} platform={d.platform} exclude={d.members} selected={picked} onToggle={toggle} />
      </GvSheet>
    );
  }

  const members = d.members.map(id => ctx.accounts[id]).filter(Boolean);
  // Basic-section footnote: what 专属 / 公开 and 停用 mean right now, plus a warning when a public group nobody can serve would go live.
  const basicFoot = [
    dupName && <span key="dup" className="tone-critical tone-text">已有同名分组。</span>,
    <span key="excl">{next.exclusive ? '专属：只有分配了这个分组的用户能选它。' : '公开：所有用户新建 API 密钥时都能选它。'}</span>,
    isNew && <span key="new">创建后立即可用，需要时可在详情里停用。平台和计费类型创建后不能修改；组合路由（Composite）分组在 Web 中创建。</span>,
    !isNew && !live && <span key="off">停用：使用这个分组的 API 密钥会被拒绝。</span>,
  ].filter(Boolean);
  // An empty public group would take requests it cannot serve: said here in plain words, and asked again on 创建.
  const memberFoot = isNew && members.length === 0
    ? <span>{openToAll ? '公开分组没有可用账号时，选它的请求会失败。' : ''}可以现在添加，也可以创建后在详情里添加。每个账号单独提交。</span>
    : <span className={cx(live && okAfter === 0 && 'tone-critical tone-text')}>{isNew ? '创建后' : '保存后'}可用 <b className="num">{okAfter}</b> / <span className="num">{members.length}</span>{!isNew && okAfter !== okBefore ? `（现在 ${okBefore}）` : ''}</span>;
  return (
    <GvSheet title={isNew ? '新建分组' : '编辑分组'} onClose={ctx.closeSheet} leading={gvBarBtn('取消', ctx.closeSheet)}
      trailing={gvBarBtn(isNew ? '创建' : '保存', save, { prominent: dirty && valid, disabled: !dirty || !valid })}>
      <GvFormSection title="基本" foot={basicFoot}>
        <GvField label="名称"><input className="gv-text" value={d.name} placeholder="必填" onChange={e => set({ name: e.target.value })} aria-label="分组名称" /></GvField>
        <GvField label="描述"><input className="gv-text" value={d.description} placeholder="可选" onChange={e => set({ description: e.target.value })} aria-label="分组描述" /></GvField>
        <GvField label="平台">
          {isNew
            ? <GvPlatformPicker value={d.platform} onChange={p => set({ platform: p, members: p === d.platform ? d.members : [] })} />
            : <span className="gv-ro">{d.platform}</span>}
        </GvField>
        {isNew
          ? <GvField label="状态"><span className="gv-ro">正常</span></GvField>
          : <GvField label="状态"><GvSwitch on={d.status === 'active'} onLabel="正常" offLabel="停用" label="分组状态" onToggle={() => set({ status: d.status === 'active' ? 'inactive' : 'active' })} /></GvField>}
        <GvField label="专属分组"><GvSwitch on={d.exclusive} onLabel="专属" offLabel="公开" label="专属分组" onToggle={() => set({ exclusive: !d.exclusive })} /></GvField>
      </GvFormSection>
      <GvFormSection title="计费" foot="费率倍数：1.0 = 标准费率，0.5 = 半价，2.0 = 双倍。每用户 RPM：每位用户在本分组每分钟最多请求数，留空或 0 = 不限。">
        <GvField label="费率倍数"><GvStepper value={d.rate} onChange={val => set({ rate: val })} /></GvField>
        <GvField label="计费类型">
          {isNew
            ? <Segmented value={d.billing} onChange={b => set({ billing: b })} items={[{ key: 'standard', label: '标准（余额）' }, { key: 'subscription', label: '订阅（配额）' }]} />
            : <span className="gv-ro">{GV_BILLING[d.billing]}<small>创建后不能修改</small></span>}
        </GvField>
        <GvField label="每用户 RPM"><input className="gv-text num gv-text-r" inputMode="numeric" placeholder="不限" value={d.rpm} onChange={e => set({ rpm: e.target.value.replace(/\D/g, '') })} aria-label="每用户 RPM" /></GvField>
      </GvFormSection>
      {d.billing === 'subscription' ? (
        <GvFormSection title="订阅限额 · 每个订阅" foot="留空 = 无限制；超过限额的订阅请求会被拒绝。">
          <GvField label="每日限额"><GvMoneyInput value={d.day} onChange={x => set({ day: x })} label="每日限额（USD）" /></GvField>
          <GvField label="每周限额"><GvMoneyInput value={d.week} onChange={x => set({ week: x })} label="每周限额（USD）" /></GvField>
          <GvField label="每月限额"><GvMoneyInput value={d.month} onChange={x => set({ month: x })} label="每月限额（USD）" /></GvField>
        </GvFormSection>
      ) : <div className="gv-form-note">标准（余额）计费从用户余额扣除，没有订阅限额。</div>}
      <GvFormSection title={`成员账号 ${members.length}`} foot={memberFoot}>
        {members.map(a => (
          <div key={a.id} className={cx('gv-mrow', adds.includes(a.id) && 'is-new')}>
            <button className="gv-remove" onClick={() => set({ members: d.members.filter(x => x !== a.id) })} aria-label={`移出 ${a.name}`}><i className="gv-bar" /></button>
            <skin.Glyph state={a.state} />
            <span className="gv-mrow-name">{a.name}</span>
            {adds.includes(a.id) ? <span className="gv-new-tag">新加入</span> : a.state === 'normal' ? <span className="gv-ok-text">可调度</span> : <skin.Badge state={a.state} secs={remaining(a, ctx.elapsed)} />}
          </div>
        ))}
        {removes.length > 0 && <div className="gv-removed">将移出：{removes.map(id => ctx.accounts[id] && ctx.accounts[id].name).join('、')}</div>}
        <button className="gv-mrow gv-mrow-add" onClick={() => setPage('pick')}><Icon name="plus" size={16} weight={2.6} /><span>添加 {d.platform} 账号…</span></button>
      </GvFormSection>
      <div className="gv-form-note">模型白名单、组合路由、图片计费、客户端限制在 Web 中编辑。</div>
    </GvSheet>
  );
}

mvRegister('screen:groups', 'base', GvListRows);
mvRegister('screen:groups', 'grid', GvListGrid);
mvRegister('screen:groups', 'table', GvListTable);
mvRegister('screen:group', 'base', GvDetailRows);
mvRegister('screen:group', 'ring', GvDetailRing);
mvRegister('screen:group', 'table', GvDetailTable);
mvRegister('screen:groupKeys', 'base', GvKeysScreen);
mvRegister('screen:groupSubs', 'base', GvSubsScreen);
mvRegister('screen:groupBatch', 'base', GvBatchScreen);
mvRegister('sheet:groupEdit', 'base', GvEditSheet);
mvRegister('sheet:groupPick', 'base', GvPickSheet);
