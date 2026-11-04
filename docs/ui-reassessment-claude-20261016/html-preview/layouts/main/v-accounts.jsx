/* 账号列表 · 第 2 轮变体（v-accounts）。两个维度互相独立：
   维度一 · 分组方式（accounts 槽）：base 按紧急程度；platform 按平台；group 按分组；flat 不分组 + 右上“排序与筛选”菜单。
   维度二 · 行样式（accountRow 槽）：base 三行；side 右侧固定列；compact 两行紧凑。
   分组变体里的每一行仍按 ctx.v.accountRow 选行样式，所以任意分组方式都能配任意行样式；组内的行会省掉组头已经写明的维度
   （按平台时不再写平台，按分组时只写“另属”的其他分组）：一律走 <Slot slot="accountRow" omit home />，三行版就是核心 AccountRow，
   第二行文字由核心 accountWhere 生成（本文件的 side / compact 两种行也用它），不再复制。
   导航栏：左“选择”，右“+”新建账号（{kind:'accountNew'}，已定的单页长表单）；不分组时右侧另有“排序与筛选”。筛选胶囊里的“平台”
   是一个菜单（SwiftUI：Menu 里一个 Picker），选中后只看这个平台，胶囊显示“平台：X”，与状态胶囊叠加。
   开关（initial.v）：acctSort = urgency|amount|name（flat 初始排序），acctSortMenu = true（初始展开菜单），
   acctCollapsed = ['标准组', …]（初始收起的组）。旧开关 acctMultiDemo 已退役（对比页选项里还带着，不再起作用）：跨分组直接用共享 DEMO
   里的多分组账号（#1、#2 高级组 + Claude Code 组，#7 标准组 + 企业专线），本文件不再改写任何账号。
   分组顺序 ← DEMO.groups 的 sortOrder；按平台时，平台内按账号所属分组里 sortOrder 最小的那个排在一起，再按紧急程度（已定 acctOrder = 'group'）。
   调度开关（schedulable）与状态分开：受限账号被停调度后，状态牌与倒计时照常，第三行最前面加“已停止调度”（同核心 AccountRow）；
   组头的计数直接用核心的 accountCounts（需处理、暂停、停用、已停止调度），按分组时用 groupAvailability，口径与核心一致。
   按分组时组头的告警牌读写核心的告警状态（ctx.alertOpen / alertStatus / resolveAlert / silenceAlert），与首页、监控 · 告警、告警页同步。
   实现备注（SwiftUI 落地）：组头的可用 / 需处理计数取 ops/account-availability（服务端按平台、分组统计，不受分页影响）；
   金额排行先拉全量 lite 列表再配 today-stats/batch；“全选”只作用于已加载的行，或先补全列表再执行。 */

const VA_UNGROUPED = '未分组';
const VA_SORTS = [
  { key: 'urgency', label: '紧急度', hint: '错误、受限在前' },
  { key: 'amount', label: '今日金额', hint: '从高到低' },
  { key: 'name', label: '名称', hint: 'A 到 Z' },
];
const VA_DIMS = [
  { key: 'platform', label: '平台', of: a => [a.platform] },
  { key: 'group', label: '分组', of: a => (a.groups.length ? a.groups : [VA_UNGROUPED]) },
  { key: 'type', label: '类型', of: a => [a.type] },
];
const VA_PICK = {
  needs: a => NEEDS_ACTION.includes(a.state),
  limited: a => ['rate_limited', 'overloaded', 'temp_unsched'].includes(a.state),
  paused: a => ['paused', 'inactive'].includes(a.state),
};
const VA_IDLE = ['paused', 'inactive'];

const vaAll = ctx => Object.values(ctx.accounts);
const vaGroupsOf = a => (a.groups.length ? a.groups : [VA_UNGROUPED]);
// The site's own group order (admin/groups sort_order); 未分组 last, unknown names just before it.
const vaGroupRank = g => (g === VA_UNGROUPED ? 1e6 : (groupOf(g) || { sortOrder: 1e5 }).sortOrder);
const vaGroupCmp = (x, y) => vaGroupRank(x) - vaGroupRank(y) || x.localeCompare(y, 'zh-Hans-CN');

// Accounts left after the filter chips (state chip, then the 平台 menu chip), most urgent first. Every grouping variant groups this list.
function vaFiltered(ctx, platform) {
  const list = sortByUrgency(vaAll(ctx)).filter(a => !platform || a.platform === platform);
  const pick = VA_PICK[ctx.acctFilter];
  return pick ? list.filter(pick) : list;
}

function vaSorted(list, sort) {
  if (sort === 'amount') return [...list].sort((a, b) => (b.todayCost ?? -1) - (a.todayCost ?? -1));
  if (sort === 'name') return [...list].sort((a, b) => a.name.localeCompare(b.name, 'zh-Hans-CN', { numeric: true }));
  return list;
}

// Menu values for one filter dimension: groups in their usual order, everything else by account count.
function vaDimValues(all, dim) {
  const count = v => all.filter(a => dim.of(a).includes(v)).length;
  const values = [...new Set(all.flatMap(dim.of))];
  return dim.key === 'group' ? values.sort(vaGroupCmp) : values.sort((x, y) => count(y) - count(x) || x.localeCompare(y, 'zh-Hans-CN'));
}

function vaTally(list) {
  const t = { ok: 0, caution: 0, critical: 0, neutral: 0 };
  list.forEach(a => { t[toneOf(a.state)] += 1; });
  return t;
}

function vaRecoverAt(ctx, secs) {
  return fmt.clock(DEMO_CLOCK_BASE + (ctx.elapsed + (secs || 0)) * 1000);
}

/* List state that must survive a pushed detail page. Core mounts only the top page of a stack, while in SwiftUI the list stays alive
   under the detail, so collapsed sections, the 平台 pick and the frozen section order live here, keyed by ctx.confirm (the phone's own
   useState setter, stable for the phone's lifetime). `init` may be a function; it runs once, on first read. */
const VA_MEMO = new WeakMap();

function useVaMemo(ctx, key, init) {
  const [, rerender] = useState(0);
  const anchor = ctx.confirm;
  if (!(key in (VA_MEMO.get(anchor) || {}))) {
    VA_MEMO.set(anchor, { ...(VA_MEMO.get(anchor) || {}), [key]: typeof init === 'function' ? init() : init });
  }
  const write = next => {
    const box = VA_MEMO.get(anchor);
    VA_MEMO.set(anchor, { ...box, [key]: typeof next === 'function' ? next(box[key]) : next });
    rerender(n => n + 1);
  };
  return [VA_MEMO.get(anchor)[key], write];
}

function useVaCollapsed(ctx) {
  const [closed, setClosed] = useVaMemo(ctx, 'collapsed', () => ctx.v.acctCollapsed || []);
  const isClosed = k => closed.includes(k);
  const toggle = k => setClosed(s => (s.includes(k) ? s.filter(x => x !== k) : [...s, k]));
  return [isClosed, toggle];
}

/* ---------- 告警：组头上的告警牌是独立按钮，点开是处置面板（手动解决 / 静默） ---------- */

// Wording, durations (core ALERT_SILENCE) and the confirm step match the alert page (screen:alert) and core's 监控 · 告警; colour is
// alertTone. The handling is core's (ctx.alertStatus / resolveAlert / silenceAlert), so resolving here clears the home's alert row and
// 监控 · 告警 too, and the other way round.
function useVaAlert(ctx) {
  const [open, setOpen] = useState(false);
  const alert = DEMO.alert;
  const until = ctx.alertStatus(alert.id).silencedUntil;
  const live = ctx.alertOpen;
  const match = (dim, value) => live && alert[dim] === value;
  // A silenced event is still firing (silence only stops new events), so it keeps its colour, as in 监控 · 告警 and on the home row.
  const tone = alertTone(alert);
  const where = alert.group || (alert.platform ? `${alert.platform} 平台` : '');
  const silence = () => ctx.confirm({
    title: '静默这条规则多久？',
    message: `静默期间，这条规则${where ? `在${where}` : ''}不再产生新的告警事件。当前这条仍需手动解决。`,
    actions: [
      ...ALERT_SILENCE.map(([span, to]) => ({ label: `静默 ${span}`, onPress: () => { setOpen(false); ctx.silenceAlert(alert.id, to, { text: `已静默 ${span}`, icon: 'hourglass', tone: 'neutral' }); } })),
      { label: '取消', role: 'cancel' },
    ],
  });
  const resolve = () => ctx.confirm({
    title: '手动解决这条告警？',
    message: `「${alert.title}」会标记为已手动解决。条件仍满足时，规则会再次触发。`,
    actions: [
      { label: '手动解决', role: 'default', onPress: () => { setOpen(false); ctx.resolveAlert(alert.id, { text: '已手动解决', icon: 'checkCircle' }); } },
      { label: '取消', role: 'cancel' },
    ],
  });
  const sheet = open && live && (
    <Sheet title="告警" leadingLabel="关闭" onClose={() => setOpen(false)}>
      <div className={cx('va-alert-card tone-rail', `tone-${tone}`)}>
        <div className="row-top"><span className="va-alert-title">{alert.title}</span><ctx.skin.Badge tone={tone} label={until ? `${alert.level} 已静默` : alert.level} /></div>
        <div className="va-alert-detail">{alert.detail}</div>
      </div>
      <div className="kv-grid">
        <KV label="维度" value={alert.scope} />
        <KV label="状态" value={until ? <>告警中 · 已静默至 <span className="num">{until}</span></> : '告警中'} />
      </div>
      <div className="va-alert-note">告警只精确到分组或平台，不指向具体账号；先看本组需处理的账号。</div>
      <div className="actions">
        <ActionButton label="手动解决" icon="check" primary onClick={resolve} />
        <ActionButton label={until ? '改静默时长…' : '静默…'} icon="hourglass" onClick={silence} />
      </div>
      <button className="va-alert-link" onClick={() => { setOpen(false); ctx.setAcctFilter('needs'); }}>
        <span>只看需处理的账号</span><Icon name="chevron" size={13} weight={2.6} />
      </button>
      <button className="va-alert-link" onClick={() => { setOpen(false); ctx.push({ kind: 'alert', id: alert.id }); }}>
        <span>告警详情</span><Icon name="chevron" size={13} weight={2.6} />
      </button>
    </Sheet>
  );
  const button = (dim, value) => match(dim, value) && (
    <button className="va-alert-btn" aria-label={`${alert.level} 告警：${alert.title}${until ? `，已静默至 ${until}` : ''}，打开处置`} onClick={() => setOpen(true)}>
      <ctx.skin.Badge tone={tone} label={`${alert.level} ${until ? '已静默' : '告警'}`} />
    </button>
  );
  return { sheet, button };
}

/* ---------- shell shared by the grouping variants: nav, filter chips, selection dock ---------- */

// The 平台 chip's menu (SwiftUI: Menu { Picker }): 全部平台 + every platform by account count. Narrows rows only; header counts stay whole.
function VaPlatformMenu({ ctx, value, onPick, onClose }) {
  const all = vaAll(ctx);
  const platforms = vaDimValues(all, VA_DIMS[0]);
  return (
    <div className="overlay" onClick={onClose}>
      <div className="menu glass va-sort-menu va-plat-menu" role="menu" aria-label="平台" onClick={e => e.stopPropagation()}>
        {[null, ...platforms].map(p => (
          <button key={p || 'all'} className="menu-item" role="menuitemradio" aria-checked={value === p} onClick={() => { onPick(p); onClose(); }}>
            <span className="menu-check">{value === p && <Icon name="check" size={16} weight={2.6} />}</span>
            <span className="menu-label">{p || '全部平台'}</span>
            <span className="va-menu-value num">{p ? all.filter(a => a.platform === p).length : all.length}</span>
          </button>
        ))}
      </div>
    </div>
  );
}

// platform / setPlatform: the 平台 chip's pick (null = all), owned by the variant so it can filter its rows.
function VaShell({ ctx, trailing, overlay, platform = null, setPlatform, children }) {
  const counts = ctx.counts;
  const [menu, setMenu] = useState(false);
  const chips = [
    { key: 'needs', label: '需处理', count: counts.needs, alert: counts.needs > 0 },
    { key: 'all', label: '全部', count: counts.total },
    { key: 'limited', label: '受限', count: counts.limited },
    { key: 'paused', label: '暂停·停用', count: counts.paused + counts.inactive },
  ];
  // Same markup as core Chips plus the 平台 menu chip at the end. A picked platform also leads the row as a removable token
  // (“平台：Anthropic ✕”, the same pattern as the usage-log filters); picking scrolls the row back to its start so the token
  // is in view (SwiftUI: ScrollViewReader.scrollTo the first chip).
  const chipsRef = useRef(null);
  useEffect(() => { if (chipsRef.current) chipsRef.current.scrollLeft = 0; }, [platform]);
  const chipRow = (
    <div ref={chipsRef} className={cx('chips', platform && 'tokens')}>
      {platform && (
        <button className="chip on token va-plat-token" onClick={() => setPlatform(null)} aria-label={`移除平台筛选 ${platform}`}>
          <span>平台：{platform}</span><Icon name="close" size={12} weight={2.8} />
        </button>
      )}
      {chips.map(c => (
        <button key={c.key} className={cx('chip', ctx.acctFilter === c.key && 'on', c.alert && 'chip-alert')} onClick={() => ctx.setAcctFilter(c.key)}>
          <span>{c.label}</span><b className="num">{c.count}</b>
        </button>
      ))}
      <button className="chip va-plat-chip" aria-haspopup="menu" aria-expanded={menu} onClick={() => setPlatform && setMenu(true)}>
        <span>平台</span><Icon name="chevronDown" size={12} weight={2.6} />
      </button>
    </div>
  );
  const platformMenu = menu && !ctx.selecting && <VaPlatformMenu ctx={ctx} value={platform} onPick={setPlatform} onClose={() => setMenu(false)} />;
  const add = (
    <button className="glass-btn" aria-label="新建账号" onClick={() => ctx.push({ kind: 'accountNew' })}>
      <Icon name="plus" size={19} weight={2.2} />
    </button>
  );
  const dock = ctx.selecting && (
    <div className="dock glass">
      <span className="dock-count">已选 <b className="num">{ctx.selected.length}</b> 个</span>
      <button className="dock-btn" disabled={!ctx.selected.length} onClick={() => ctx.bulkSchedule(false)}><Icon name="pauseFill" size={15} />停止调度</button>
      <button className="dock-btn dock-primary" disabled={!ctx.selected.length} onClick={() => ctx.bulkSchedule(true)}><Icon name="play" size={15} />启用调度</button>
    </div>
  );
  // .va-lead marks the nav row so CSS can pin the title to the centre (SwiftUI: .principal). Trailing: the variant's own control
  // (the flat list's 排序与筛选), then + 新建账号. Grouped lists have no extra control: the chips and the section headers filter.
  return (
    <Screen plain ctx={ctx} footer={<>{dock}{overlay}{platformMenu}</>} nav={
      <NavBar ctx={ctx} title="账号" subtitle={`${ctx.site} · ${counts.total} 个 · 刚刚更新`}
        leading={<span className="va-lead"><GlassButton label={ctx.selecting ? '完成' : '选择'} onClick={ctx.toggleSelecting} prominent={ctx.selecting} /></span>}
        trailing={!ctx.selecting && <>{trailing}{add}</>} />
    }>
      {chipRow}
      {children}
    </Screen>
  );
}

function VaEmpty() {
  return <div className="list-group"><div className="empty pad">没有符合条件的账号</div></div>;
}

// Rows inside a section drop the dimension the header already shows: every row style (core's three-row base included) takes omit / home.
function VaRow(props) {
  return <Slot slot="accountRow" {...props} />;
}

/* One collapsible section. The header is a full-width toggle button with sibling buttons on top of it
   (告警牌, 全选) — no nested controls. Header numbers always describe the whole group; the filter chips
   only decide which rows show underneath. */
function VaSection({ ctx, label, summary, lead, badge, stats, rows, collapsed, onToggle, omit, home }) {
  const ids = rows.map(a => a.id);
  const picked = ids.filter(i => ctx.selected.includes(i)).length;
  const allOn = ids.length > 0 && picked === ids.length;
  const selectAll = () => ids.forEach(i => { if (allOn || !ctx.selected.includes(i)) ctx.toggleSelect(i); });
  const spoken = [label, summary, collapsed ? '已收起' : '已展开', ctx.selecting && picked ? `已选 ${picked} 个` : ''].filter(Boolean).join('，');
  return (
    <section className="va-section">
      <div className={cx('va-head', collapsed && 'is-collapsed')}>
        <button className="va-head-hit" aria-expanded={!collapsed} aria-label={spoken} onClick={onToggle} />
        <span className="va-head-part" aria-hidden="true">{lead}</span>
        {badge}
        <span className="va-head-spacer" />
        <span className="va-head-part" aria-hidden="true">{stats}</span>
        {ctx.selecting && collapsed && picked > 0 && <span className="va-picked" aria-hidden="true">已选 <b className="num">{picked}</b></span>}
        {ctx.selecting && <button className="va-selall" aria-label={`${label}：${allOn ? '取消全选' : '全选'}`} onClick={selectAll}>{allOn ? '取消全选' : '全选'}</button>}
        <span className="va-head-chev" aria-hidden="true"><Icon name="chevronDown" size={13} weight={2.6} /></span>
      </div>
      {!collapsed && <div className="list-group">{rows.map(a => <VaRow key={a.id} ctx={ctx} a={a} omit={omit} home={home} />)}</div>}
    </section>
  );
}

/* ---------- 维度一 · 按平台：组头 = 平台名 + 个数 + 需处理数（或全停时的暂停 / 停用数） ---------- */

// Section subtotals use core's accountCounts, so 需处理 / 暂停 / 停用 / 已停止调度 mean exactly what the chips and the tab badge mean.
function vaPlatformStats(all, p) {
  const list = all.filter(a => a.platform === p);
  const c = accountCounts(list);
  const bad = list.filter(VA_PICK.needs);
  const idle = c.paused + c.inactive === c.total;
  return { p, list, c, bad, idle, hot: bad.some(a => toneOf(a.state) === 'critical') };
}
const vaPlatformRank = g => (g.hot ? 0 : g.bad.length ? 1 : g.idle ? 3 : 2);
const vaPlatformCmp = (x, y) => vaPlatformRank(x) - vaPlatformRank(y) || y.bad.length - x.bad.length || y.list.length - x.list.length;

// An account in several groups clusters under the first of them in the site's group order.
const vaHomeGroup = a => [...vaGroupsOf(a)].sort(vaGroupCmp)[0];

// Round 2 decision (acctOrder = 'group'): inside a platform, accounts of the same group stay together, then urgency
// (the incoming rows are already most-urgent-first and the sort is stable).
function vaPlatformRows(ctx, rows, p) {
  const inPlatform = rows.filter(a => a.platform === p);
  if (ctx.v.acctOrder !== 'group') return inPlatform;
  return [...inPlatform].sort((x, y) => vaGroupCmp(vaHomeGroup(x), vaHomeGroup(y)));
}

function vaIdleText(c) {
  return [c.paused && `暂停 ${c.paused}`, c.inactive && `停用 ${c.inactive}`].filter(Boolean).join(' · ');
}

// Blocked accounts that were also stopped by hand: they still count as 需处理; the header says how many won't come back on their own.
// `compact` (group headers, which also carry the availability bar) uses a shorter label. The header button speaks the full summary.
function VaStoppedFlag({ c, compact }) {
  if (!(c.stopped > 0)) return null;
  return (
    <span className="va-flag tone-neutral va-flag-sched" aria-hidden="true">
      <Icon name="pauseFill" size={11} />{compact ? '停调度' : '已停止调度'} <b className="num">{c.stopped}</b>
    </span>
  );
}

function VaByPlatform({ ctx }) {
  const [isClosed, toggle] = useVaCollapsed(ctx);
  const [platform, setPlatform] = useVaMemo(ctx, 'platform', null);
  const alerts = useVaAlert(ctx);
  const all = vaAll(ctx);
  const rows = vaFiltered(ctx, platform);
  // Order is fixed while the list is alive (a pushed detail and back keeps it; pull to refresh re-ranks), so sections never jump under a finger.
  const [frozen] = useVaMemo(ctx, 'platformOrder', () => [...new Set(all.map(a => a.platform))].map(p => vaPlatformStats(all, p)).sort(vaPlatformCmp).map(g => g.p));
  const order = [...frozen, ...[...new Set(all.map(a => a.platform))].filter(p => !frozen.includes(p))];
  const groups = order.map(p => vaPlatformStats(all, p)).filter(g => rows.some(a => a.platform === g.p));
  return (
    <VaShell ctx={ctx} overlay={alerts.sheet} platform={platform} setPlatform={setPlatform}>
      {groups.length === 0 && <VaEmpty />}
      {groups.map(g => {
        const idleText = !g.bad.length && g.idle ? vaIdleText(g.c) : '';
        const summary = [`${g.c.total} 个`, g.bad.length ? `需处理 ${g.c.needs}` : idleText, g.c.stopped ? `其中已停止调度 ${g.c.stopped}` : ''].filter(Boolean).join('，');
        return (
          <VaSection key={g.p} ctx={ctx} label={g.p} summary={summary} rows={vaPlatformRows(ctx, rows, g.p)} omit="platform" home={g.p}
            collapsed={isClosed(g.p)} onToggle={() => toggle(g.p)}
            lead={<><span className="va-head-title">{g.p}</span><span className="va-head-count num">{g.c.total}</span></>}
            badge={alerts.button('platform', g.p)}
            stats={g.bad.length > 0
              ? <><VaStoppedFlag c={g.c} /><span className={cx('va-flag', g.hot ? 'tone-critical' : 'tone-caution')}>需处理 <b className="num">{g.c.needs}</b></span></>
              : idleText && <span className="va-flag tone-neutral">{idleText}</span>} />
        );
      })}
    </VaShell>
  );
}

/* ---------- 维度一 · 按分组：组头 = 分组名 + 告警牌 + 状态构成条 + 可用 / 总数 ---------- */

function VaAvailBar({ tally, total }) {
  return (
    <span className="va-bar">
      {['ok', 'caution', 'critical', 'neutral'].filter(k => tally[k]).map(k => <i key={k} className={`va-bar-${k}`} style={{ flexGrow: tally[k] / total }} />)}
    </span>
  );
}

// square.stack.3d.up — reads as “a pool of accounts”, distinct from the server glyph on the 账号 tab.
function VaStackGlyph() {
  return (
    <svg width="16" height="16" viewBox="0 0 24 24" aria-hidden="true" style={{ display: 'block', flex: 'none' }}>
      <g fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
        <path d="M12 3.5l8.5 4.3L12 12 3.5 7.8z" /><path d="M3.5 12.2L12 16.5l8.5-4.3" /><path d="M3.5 16.4L12 20.7l8.5-4.3" />
      </g>
    </svg>
  );
}

function VaByGroup({ ctx }) {
  const [isClosed, toggle] = useVaCollapsed(ctx);
  const [platform, setPlatform] = useVaMemo(ctx, 'platform', null);
  const alerts = useVaAlert(ctx);
  const all = vaAll(ctx);
  const rows = vaFiltered(ctx, platform);
  const names = [...new Set(all.flatMap(vaGroupsOf))].sort(vaGroupCmp)
    .filter(g => rows.some(a => vaGroupsOf(a).includes(g)));
  return (
    <VaShell ctx={ctx} overlay={alerts.sheet} platform={platform} setPlatform={setPlatform}>
      {names.length === 0 && <VaEmpty />}
      {names.map(g => {
        const none = g === VA_UNGROUPED;
        const members = none ? all.filter(a => !a.groups.length) : groupMembers(all, g);
        const tally = vaTally(members);
        // 可用 = state normal, the same bucket as core's groupAvailability (and the groups page).
        const avail = none ? tally.ok : groupAvailability(all, g).available;
        const tone = avail === members.length ? '' : avail * 2 >= members.length ? 'tone-caution' : 'tone-critical';
        const stopped = accountCounts(members).stopped;
        return (
          <VaSection key={g} ctx={ctx} label={g} summary={[none ? `${members.length} 个` : `可用 ${avail}/${members.length}`, stopped ? `其中已停止调度 ${stopped}` : ''].filter(Boolean).join('，')}
            rows={rows.filter(a => vaGroupsOf(a).includes(g))} omit="group" home={g} collapsed={isClosed(g)} onToggle={() => toggle(g)}
            lead={<><span className={cx('va-gicon', none && 'is-none')}><VaStackGlyph /></span><span className="va-head-title">{g}</span></>}
            badge={!none && alerts.button('group', g)}
            stats={none
              ? <span className="va-head-count num">{members.length} 个</span>
              : <><VaStoppedFlag c={{ stopped }} compact /><span className={cx('va-avail', tone)}><VaAvailBar tally={tally} total={members.length} /><span>可用 <b className="num">{avail}</b><span className="num">/{members.length}</span></span></span></>} />
        );
      })}
    </VaShell>
  );
}

/* ---------- 维度一 · 不分组 + 右上“排序与筛选”菜单（SwiftUI：Menu 内一个 Picker + 三个子 Menu） ---------- */

function VaFlatMenu({ ctx, sort, setSort, narrow, setNarrow, onClose }) {
  const [sub, setSub] = useState(null);
  const dim = VA_DIMS.find(d => d.key === sub);
  const check = on => <span className="menu-check">{on && <Icon name="check" size={16} weight={2.6} />}</span>;
  let body;
  if (dim) {
    const values = vaDimValues(vaAll(ctx), dim);
    body = (
      <>
        <button className="menu-item va-menu-back" onClick={() => setSub(null)}>
          <span className="menu-check"><Icon name="back" size={15} weight={2.6} /></span><span className="menu-label">{dim.label}</span>
        </button>
        <div className="menu-sep" />
        {[null, ...values].map(val => (
          <button key={val || 'all'} className="menu-item" role="menuitemradio" aria-checked={narrow[dim.key] === val}
            onClick={() => { setNarrow({ ...narrow, [dim.key]: val }); onClose(); }}>
            {check(narrow[dim.key] === val)}<span className="menu-label">{val || '全部'}</span>
          </button>
        ))}
      </>
    );
  } else {
    body = (
      <>
        <div className="va-menu-title">排序方式</div>
        {VA_SORTS.map(s => (
          <button key={s.key} className="menu-item" role="menuitemradio" aria-checked={sort === s.key} onClick={() => { setSort(s.key); onClose(); }}>
            {check(sort === s.key)}<span className="menu-label">{s.label}<small>{s.hint}</small></span>
          </button>
        ))}
        <div className="menu-sep" />
        <div className="va-menu-title">筛选</div>
        {VA_DIMS.map(d => (
          <button key={d.key} className="menu-item va-menu-sub" aria-haspopup="menu" onClick={() => setSub(d.key)}>
            <span className="menu-check" /><span className="menu-label">{d.label}</span>
            <span className={cx('va-menu-value', narrow[d.key] && 'is-on')}>{narrow[d.key] || '全部'}</span>
            <Icon name="chevron" size={12} weight={2.6} />
          </button>
        ))}
      </>
    );
  }
  return (
    <div className="overlay" onClick={onClose}>
      <div className="menu glass va-sort-menu" role="menu" onClick={e => e.stopPropagation()}>{body}</div>
    </div>
  );
}

function VaFlat({ ctx }) {
  const [sort, setSort] = useState(ctx.v.acctSort || 'urgency');
  const [menu, setMenu] = useState(Boolean(ctx.v.acctSortMenu));
  const [narrow, setNarrow] = useState({});
  const meta = VA_SORTS.find(s => s.key === sort);
  const active = VA_DIMS.filter(d => narrow[d.key]);
  const rows = vaSorted(vaFiltered(ctx).filter(a => active.every(d => d.of(a).includes(narrow[d.key]))), sort);
  const overlay = menu && !ctx.selecting && (
    <VaFlatMenu ctx={ctx} sort={sort} setSort={setSort} narrow={narrow} setNarrow={setNarrow} onClose={() => setMenu(false)} />
  );
  const trailing = (
    <button className={cx('glass-btn va-menu-btn', active.length && 'is-on')} aria-label={`排序与筛选，当前按${meta.label}`} aria-haspopup="menu" aria-expanded={menu} onClick={() => setMenu(true)}>
      <Icon name="filter" size={19} weight={2.2} />
    </button>
  );
  return (
    <VaShell ctx={ctx} overlay={overlay} trailing={trailing}
      platform={narrow.platform || null} setPlatform={p => setNarrow({ ...narrow, platform: p })}>
      {rows.length === 0 ? <VaEmpty /> : (
        <div className="list-group">
          <div className="list-head va-sort-head">
            <span>按{meta.label} · {meta.hint}{active.map(d => ` · 仅 ${narrow[d.key]}`).join('')}</span>
            <b className="num">{rows.length} 个</b>
          </div>
          {rows.map(a => <Slot slot="accountRow" key={a.id} ctx={ctx} a={a} />)}
        </div>
      )}
    </VaShell>
  );
}

/* ---------- 维度二 · 行样式 ---------- */

function vaRowBits(ctx, a) {
  const tone = toneOf(a.state);
  const selected = ctx.selected.includes(a.id);
  return {
    tone,
    selected,
    secs: remaining(a, ctx.elapsed),
    onClick: ctx.selecting ? () => ctx.toggleSelect(a.id) : () => ctx.push({ kind: 'account', id: a.id }),
    lead: ctx.selecting
      ? <span className={cx('select-ring', selected && 'on')}>{selected && <Icon name="check" size={14} weight={3} />}</span>
      : <ctx.skin.Glyph state={a.state} />,
    cls: cx('row tappable', ctx.skin.rowClass(ctx.selecting ? 'none' : tone), `tone-${tone}`, VA_IDLE.includes(a.state) && 'is-idle', selected && 'is-selected'),
  };
}

function VaChev({ ctx }) {
  return ctx.selecting ? null : <div className="row-chev"><Icon name="chevron" size={13} weight={2.6} /></div>;
}

// The stop mark of a blocked account switched off by hand (schedLabel); it always leads its line, as in core's AccountRow.
function VaSchedMark({ a }) {
  const label = schedLabel(a);
  return label ? <><span className="sched-mark">{label}</span> · </> : null;
}

// 右侧固定列（像日志行）：左 = 名称 / 平台 · 分组；右 = 今日金额 / 并发 x/y 或状态 + 倒计时。
function VaRowSide({ ctx, a, omit, home }) {
  const b = vaRowBits(ctx, a);
  const meta = STATE_META[a.state];
  const cap = tightestCapacity(a);
  let sub;
  if (a.state !== 'normal') {
    sub = (
      <span className="va-state tone-text">
        <Icon name={meta.icon} size={12} weight={2.4} />{meta.label}
        {meta.timed && b.secs !== null && <b className="num">{fmt.countdown(b.secs)}</b>}
      </span>
    );
  } else if (cap) {
    sub = <ctx.skin.Capacity used={cap.used} limit={cap.limit} label="并发" />;
  } else {
    sub = <span className="cap-missing"><span className="num">—</span> 并发</span>;
  }
  return (
    <div className={cx(b.cls, 'va-side')} onClick={b.onClick}>
      <div className="row-lead">{b.lead}</div>
      <div className="va-left">
        <span className="row-title">{a.name}</span>
        <span className="va-where"><VaSchedMark a={a} />{accountWhere(a, omit, home, true)}</span>
      </div>
      <div className="va-right">
        <ctx.skin.Money value={a.todayCost} size="m" />
        <span className="va-right-sub">{sub}</span>
      </div>
      <VaChev ctx={ctx} />
    </div>
  );
}

// 两行紧凑：名称 + 状态牌 / 平台 · 分组 · （正常：并发；受限：几点恢复；错误：简短原因） · 今日。
function vaCompactSeg(ctx, a, secs) {
  if (a.state === 'error') return <span className="tone-text">{(a.error || '上游返回错误').split('（')[0]}</span>;
  if (STATE_META[a.state].timed && secs !== null) return <span className="tone-text"><VaSchedMark a={a} /><span className="num">{vaRecoverAt(ctx, secs)}</span> 恢复</span>;
  if (VA_IDLE.includes(a.state)) return null;
  const cap = tightestCapacity(a);
  const hot = cap && cap.ratio >= 0.9 ? 'tone-critical tone-text' : cap && cap.ratio >= 0.75 ? 'tone-caution tone-text' : '';
  return <span><span className={cx('num', hot)}>{cap ? `${cap.used}/${cap.limit}` : '—'}</span> 并发</span>;
}

function VaRowCompact({ ctx, a, omit, home }) {
  const b = vaRowBits(ctx, a);
  const seg = vaCompactSeg(ctx, a, b.secs);
  return (
    <div className={cx(b.cls, 'va-compact')} onClick={b.onClick}>
      <div className="row-lead">{b.lead}</div>
      <div className="va-left">
        <div className="row-top"><span className="row-title">{a.name}</span><ctx.skin.Badge state={a.state} secs={b.secs} /></div>
        <div className="va-line">
          <span className="va-where">{accountWhere(a, omit, home, true)}</span>
          <span className="va-figs">
            {seg && <><span className="va-dot">·</span>{seg}</>}
            <span className="va-dot">·</span><span>今日</span><b className="num">{fmt.money(a.todayCost)}</b>
          </span>
        </div>
      </div>
      <VaChev ctx={ctx} />
    </div>
  );
}

mvRegister('accounts', 'platform', VaByPlatform);
mvRegister('accounts', 'group', VaByGroup);
mvRegister('accounts', 'flat', VaFlat);
mvRegister('accountRow', 'side', VaRowSide);
mvRegister('accountRow', 'compact', VaRowCompact);
