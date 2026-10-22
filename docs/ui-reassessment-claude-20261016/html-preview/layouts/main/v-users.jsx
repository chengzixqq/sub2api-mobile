/* 用户列表与用户详情。已定（DECISIONS 第 2 轮 Q10–Q12）：users 'quick' + usersRows 'cols'（快捷充值头像 + 右侧固定列），userDetail 'hero'（余额大数）。
   其余变体留给对比页快照，不删。
   userDetail：base（A：余额大数 + 充值/退款按钮，在 00-core）、hero（已定：A 的布局，加上待核对 / 已禁用横幅、待核对拦截、余额低标记、Key 摘要、总充值）、wallet（B 式钱包卡：头像、姓名、大余额、按钮都在卡上；滚过卡片后导航栏淡入姓名）、
               compact（紧凑头部：余额和按钮一行、今日/本月收在同一块面板里，下面直接是充值与调整记录，再是 API Key）。
   users：base（A，在 00-core）、rows（同 A 的布局，余额低按阈值实时计算，对比页用它代表 A）、cols（右侧固定列：第一行余额、第二行今日消费；余额低 = 实心点、待核对 = docCheck 图标 + 左竖条、禁用 = minus 图标）、
          quick（顶部一排快捷充值头像，点头像直接打开大数字键盘；ctx.v.usersRows === 'cols' 时下面的列表用右侧固定列）。
   充值、退款都打开已定的大数字键盘（sheet kind 'keypad'，由 00-core 的 KeypadSheet 渲染；备注、禁用用户提示、Face ID 门槛都由核心处理）。
   用户状态词是「启用 / 禁用」（同 Web；句中写“已禁用”），「正常 / 停用」只用于账号、Key 等，不用于用户。
   数据口径：“充值与调整记录”（第 3 轮改名，原“余额流水”）来自 GET admin/users/:id/balance-history（类型、金额、时间、备注 notes，
   另有 total_recharged = “总充值”），**没有变动后余额**，所以记录行只写时间与备注，不写“余额 $X”；详情页只放最近 5 条，更多进
   screen:userLedger（分页）。本月消费来自 usage/stats 按用户查询（原生端已在用），演示数据只有王小明有，其他人缺失时整格不显示（与 base 相同）。
   API Key：已定的写法是“编辑用户 · Key 与限额”里的可展开卡片（v-user-edit，ueKeys 'cards'）。详情页不再画第三种 Key 列表，
   只放一行摘要（名称、所在分组、不能调用的 Key 及其状态、最近使用；状态读 k.status，活跃数写在分区标题上），点进
   {kind:'userEdit', id, seg:'keys'}；没注册 screen:userEdit 的构建里这行不可点。已定的 hero 在摘要下面再放一行“使用记录 ›”，
   直接进 core 的 {kind:'logs', scope:'usage', user: id}（用量明细、错误请求按用户筛选；上游错误接口没有用户参数，胶囊置灰）。
   用户没有“分组”字段（分组跟着 Key 走），所以档案里不再写分组。
   列表与 Web 一致：最新在前（created_at 倒序，请求传 sort_by=created_at&sort_order=desc）；演示数据没有 created_at，按 id 倒序
   （data.jsx usersNewestFirst），#26–#21 大客户在前、#1 王小明在最后。快捷充值头像不受影响。
   充值与调整记录里兑换得来的条目，在金额下面显示兑换码前 8 位 + “...”（core ledgerCode，同 Web UserBalanceHistoryModal）。
   ⋯ 菜单统一用 core 的 userMenu(ctx, u)（编辑用户、启用 / 禁用、发放兑换码（补偿）、删除），三种详情都接同一个；列表右上 + 进入 screen:userNew。 */

/* ---------- helpers ---------- */

// Low-balance line. The real app reads each user's balance_notify_threshold (falling back to the site default); the demo uses one line,
// the same $10 as DEMO.users[].low. It is computed from the live balance, not read from `low`, so a top-up on this phone clears it.
const VU_LOW_LINE = 10;
const vuIsLow = u => u.status !== 'disabled' && u.balance < VU_LOW_LINE;

// One status per user, most urgent first. Pending reconciliation outranks everything: a second top-up could double-credit.
function vuUserFlag(u) {
  if (u.pending) return { key: 'pending', tone: 'caution', label: '待核对' };
  if (u.status === 'disabled') return { key: 'disabled', tone: 'neutral', label: '禁用' };
  if (vuIsLow(u)) return { key: 'low', tone: 'caution', label: '余额低' };
  return null;
}

// "$1,020.00" → currency / whole / cents, so big readouts can set the currency and cents smaller.
function vuMoneyParts(value) {
  const m = fmt.money(value).match(/^([−+]?\$)([\d,]+)(\.\d+)?$/);
  return m ? { cur: m[1], whole: m[2], cents: m[3] || '' } : null;
}

function VuBalance({ value, className }) {
  const p = vuMoneyParts(value);
  if (!p) return <span className={cx('vu-bal num is-missing', className)} aria-label="未返回">—</span>;
  return (
    <span className={cx('vu-bal num', className)} aria-label={fmt.money(value)}>
      <span className="vu-bal-cur">{p.cur}</span>
      {p.whole.split(',').map((g, i) => <React.Fragment key={i}>{i > 0 && <span className="vu-bal-sep">,</span>}{g}</React.Fragment>)}
      <span className="vu-bal-cents">{p.cents}</span>
    </span>
  );
}

// Status mark with three genuinely different shapes, so status never relies on colour alone:
// 余额低 = filled dot, 待核对 = docCheck glyph (same symbol as the banner and the quick-avatar badge), 禁用 = minus glyph.
function VuMark({ flag }) {
  if (flag.key === 'low') return <i className="vu-dot tone-caution" role="img" aria-label={flag.label} />;
  return (
    <span className={cx('vu-mark', `tone-${flag.tone}`)} role="img" aria-label={flag.label}>
      <Icon name={flag.key === 'pending' ? 'docCheck' : 'minus'} size={13} weight={2.3} />
    </span>
  );
}

function vuOpenKeypad(ctx, u, mode) {
  ctx.openSheet({ kind: 'keypad', userId: u.id, mode });
}

// Top-up guard: while the previous top-up is unconfirmed, a second one could double-credit, so ask first (same rule as the quick strip).
function vuTopup(ctx, u) {
  if (!u.pending) { vuOpenKeypad(ctx, u, 'topup'); return; }
  ctx.confirm({
    title: `上一笔 ${fmt.money(DEMO.pendingOp.amount)} 充值结果未确认`,
    message: '先核对可避免重复入账',
    actions: [
      { label: '先核对', role: 'default', onPress: () => reconcileUser(ctx, u) },
      { label: '仍要充值', onPress: () => vuOpenKeypad(ctx, u, 'topup') },
      { label: '取消', role: 'cancel' },
    ],
  });
}

// balance-history `notes` (admin note on the change). DEMO ledger entries and keypad top-ups carry it as `note`.
const vuLedgerNote = l => (l.note || '').trim();
const VU_LEDGER_TITLE = '充值与调整记录';
// balance-history also lists concurrency and subscription changes (a redeem grant from v-modules writes those with
// amount null and a ready-made `display`, e.g. “+2 并发”, “企业专线 · 30 天”); only balance entries are money.
const vuIsMoneyEntry = l => typeof l.amount === 'number';
// The detail page shows the newest few; the rest is one tap away (balance-history is paginated, Web uses 15 a page).
const VU_LEDGER_PEEK = 5;
// balance-history's total_recharged (sum of positive balance changes). The demo sums the records it has.
const vuRecharged = ledger => ledger.reduce((sum, l) => sum + (vuIsMoneyEntry(l) && l.amount > 0 ? l.amount : 0), 0);
const VU_ROLE_LABEL = { admin: '管理员', vendor: '供应商', user: '用户' };
const vuIsSelf = u => Boolean(DEMO.me) && u.id === DEMO.me.id;

// last_used_at as the demo writes it (刚刚 · N 分钟前 · N 小时前 · 今天 07:55 · 昨天 22:40 · 09/29 18:02) → minutes before the demo
// clock (DEMO_CLOCK_BASE), so the summary can name the latest use across keys (SwiftUI: max(last_used_at)). Unknown text → Infinity.
const VU_AGO_UNIT = { 分钟: 1, 小时: 60, 天: 1440 };
function vuMinutesAgo(text) {
  if (!text) return Infinity;
  if (text === '刚刚') return 0;
  const rel = text.match(/^(\d+)\s*(分钟|小时|天)前$/);
  if (rel) return Number(rel[1]) * VU_AGO_UNIT[rel[2]];
  const abs = text.match(/^(?:(今天|昨天)|(\d{2})\/(\d{2}))\s+(\d{1,2}):(\d{2})$/);
  if (!abs) return Infinity;
  const days = abs[1] === '今天' ? 0 : abs[1] === '昨天' ? 1 : -daysUntil(`${DEMO_TODAY.slice(0, 4)}-${abs[2]}-${abs[3]}`);
  const now = new Date(DEMO_CLOCK_BASE);
  return days * 1440 + (now.getHours() * 60 + now.getMinutes()) - (Number(abs[4]) * 60 + Number(abs[5]));
}
// The most recent of several last-used texts (a reduce, so two unknown texts never compare as NaN).
const vuLatestUse = texts => texts.filter(Boolean).reduce((best, t) => (best === null || vuMinutesAgo(t) < vuMinutesAgo(best) ? t : best), null);

/* ---------- 用户详情：三种头部共用的分区（横幅、Key 摘要、充值与调整记录、档案） ---------- */

function VuPendingBanner({ ctx, u }) {
  const { skin } = ctx;
  if (!u.pending) return null;
  return (
    <div className={cx('banner tone-caution vu-banner', skin.rowClass('caution'))}>
      <Icon name="docCheck" size={18} />
      <div className="banner-text"><b>充值 {fmt.money(DEMO.pendingOp.amount)} 结果待核对</b><span>{DEMO.pendingOp.ago}发起，未收到服务器确认</span></div>
      <ActionButton small label="核对" onClick={() => reconcileUser(ctx, u)} />
    </div>
  );
}

// A disabled user is rejected by both jwt_auth (login) and api_key_auth (every key), so say that plainly.
// Re-enabling is reversible, so it runs at once with 撤销 in the receipt (same rule as the schedule switch).
function VuDisabledBanner({ ctx, u }) {
  if (u.status !== 'disabled') return null;
  const enable = () => ctx.updateUser(u.id, { status: 'active' }, {
    text: `已启用「${u.name}」`, icon: 'checkCircle', tone: 'ok', undo: () => ctx.updateUser(u.id, { status: 'disabled' }),
  });
  return (
    <div className="banner tone-neutral vu-banner">
      <Icon name="minus" size={18} weight={2.4} />
      <div className="banner-text"><b>已禁用</b><span>不能登录，名下的 Key 也不能调用</span></div>
      <ActionButton small label="启用" onClick={enable} />
    </div>
  );
}

// One summary line, not a third way of drawing keys: the decided presentation is the expandable cards in
// 编辑用户 · Key 与限额 (换分组、重置速率限制、平台限额, all immediate). The line names the keys, the groups they bill in, the keys
// that cannot call (with their status word) and the latest use; tapping opens that segment. Builds without screen:userEdit keep the
// line but make it inert. `logs` (the decided hero) adds 使用记录 under it.
function VuKeySummary({ ctx, u, index, logs }) {
  const { skin } = ctx;
  const keys = u.keys || [];
  const canEdit = Boolean(MV.slots['screen:userEdit']);
  const open = canEdit ? () => ctx.push({ kind: 'userEdit', id: u.id, seg: 'keys', focus: 'keys' }) : undefined;
  // api_keys.status (DEMO.keys → users[].keys; the user editor writes it back the same way): only active keys can call (Web's 活跃);
  // the others carry core's KEY_STATUS_WORD (已停用 / 额度耗尽 / 已过期).
  const live = keys.filter(k => k.status === 'active').length;
  const groups = [...new Set(keys.map(k => k.group || '未绑定分组'))];
  const idle = keys.filter(k => KEY_STATUS_WORD[k.status]).map(k => `${k.label} ${KEY_STATUS_WORD[k.status]}`);
  const latest = vuLatestUse(keys.map(k => k.used));
  // The line wraps (four groups do not fit one line). Each piece stays whole — CJK text would otherwise break inside 已过期 or
  // 最近使用 — and lines break only between pieces: a space after “·”, a zero-width space after “、” (SwiftUI: a flow layout of Text).
  const meta = [groups, idle, [latest ? `最近使用 ${latest}` : '未使用']].filter(list => list.length)
    .flatMap((list, li, all) => list.map((t, i) => t + (i < list.length - 1 ? '、' : li < all.length - 1 ? ' ·' : '')));
  return (
    <>
      <Section skin={skin} title="API Key" meta={keys.length ? `${keys.length} 个 · 活跃 ${live}` : '0 个'} index={index} className={canEdit ? 'vu-has-foot' : undefined}>
        <Row skin={skin} tone="none" className="vu-keysum" lead={<span className="lead-icon dim"><Icon name="key" /></span>} onClick={open}>
          {keys.length ? (
            <>
              <div className="row-top"><span className="row-title">{keys.map(k => k.label).join('、')}</span></div>
              <div className="row-meta">{meta.map((t, i) => <React.Fragment key={i}>{i > 0 && (meta[i - 1].endsWith('·') ? ' ' : '\u200b')}<span className="vu-keep">{t}</span></React.Fragment>)}</div>
            </>
          ) : (
            <>
              <div className="row-top"><span className="row-title vu-dim">还没有 Key</span></div>
              <div className="row-meta">用户在 Web 端创建 Key 后显示在这里</div>
            </>
          )}
        </Row>
        {logs && <VuLogsRow ctx={ctx} u={u} />}
      </Section>
      {canEdit && <p className="vu-sec-foot">换分组、速率限制、平台限额都在“编辑用户 · Key 与限额”，立即生效。</p>}
    </>
  );
}

// 使用记录 filtered to this user: core's logs page takes `user` (admin/usage user_id, ops request-errors user_query); 上游错误 has no
// user parameter, so its chip greys out there. No count: the demo's log window is 09:19–09:41, not the user's whole day.
function VuLogsRow({ ctx, u }) {
  return (
    <Row skin={ctx.skin} tone="none" className="vu-logs" lead={<span className="lead-icon dim"><Icon name="list" /></span>}
      onClick={() => ctx.push({ kind: 'logs', scope: 'usage', user: u.id })}>
      <div className="row-top"><span className="row-title">使用记录</span><span className="row-right dim">用量明细 · 错误请求</span></div>
    </Row>
  );
}

// Same line as core UserDetail: balance-history has no "balance after", so line 2 is time · note; a redeemed item adds the code's
// first 8 characters under the value (core ledgerCode, as Web's UserBalanceHistoryModal), pinned right.
function VuLedgerLines({ ctx, ledger }) {
  const { skin } = ctx;
  return ledger.map((l, i) => {
    const note = vuLedgerNote(l);
    const code = ledgerCode(l);
    return (
      <div key={i} className="ledger-line pad">
        <div className="ledger-top"><span>{l.kind}</span>{vuIsMoneyEntry(l) ? <skin.Money value={l.amount} size="m" sign /> : <span className="num vu-ledger-val">{l.display || '—'}</span>}</div>
        <div className="ledger-sub">
          <div className="row-meta vu-ledger-meta"><span className="num">{l.when}</span>{note && <span className="ledger-note">· {note}</span>}</div>
          {code && <span className="ledger-code mono" aria-label={`兑换码 ${l.code.slice(0, 8)} 开头`}>{code}</span>}
        </div>
      </div>
    );
  });
}

function VuLedger({ ctx, u, index }) {
  const { skin } = ctx;
  const ledger = u.ledger || [];
  const more = ledger.length > VU_LEDGER_PEEK;
  return (
    <Section skin={skin} title={VU_LEDGER_TITLE} meta={ledger.length ? `总充值 ${fmt.money(vuRecharged(ledger))}` : undefined} index={index}>
      {ledger.length ? <VuLedgerLines ctx={ctx} ledger={ledger.slice(0, VU_LEDGER_PEEK)} /> : <div className="empty pad">暂无记录</div>}
      {more && (
        <button className="vu-more" onClick={() => ctx.push({ kind: 'userLedger', id: u.id })}>
          <span>全部 <span className="num">{ledger.length}</span> 条</span><Icon name="chevron" size={13} weight={2.6} />
        </button>
      )}
    </Section>
  );
}

// The full record list (screen:userLedger). SwiftUI: List with .task paging through balance-history (page_size 20).
function VuLedgerScreen({ ctx, route }) {
  const { skin } = ctx;
  const u = ctx.users[route.id];
  const ledger = u.ledger || [];
  return (
    <Screen ctx={ctx} nav={<NavBar ctx={ctx} back title={VU_LEDGER_TITLE} subtitle={u.name} />}>
      <Section skin={skin} title={ledger.length ? `${ledger.length} 条` : undefined} meta={ledger.length ? `总充值 ${fmt.money(vuRecharged(ledger))}` : undefined}>
        {ledger.length ? <VuLedgerLines ctx={ctx} ledger={ledger} /> : <div className="empty pad">暂无记录</div>}
      </Section>
    </Screen>
  );
}

// Users have no group of their own (groups follow keys), so the profile is identity and limits only.
function VuProfile({ ctx, u, index }) {
  const role = VU_ROLE_LABEL[u.role] || '用户';
  return (
    <Section skin={ctx.skin} title="档案" index={index}>
      <div className="kv-grid pad">
        <KV label="用户 ID" value={<span className="num">{u.id}</span>} /><KV label="状态" value={u.status === 'disabled' ? '禁用' : '启用'} />
        <KV label="角色" value={vuIsSelf(u) ? `${role} · 你` : role} /><KV label="并发上限" value={<span className="num">{u.conc ?? '—'}</span>} />
      </div>
    </Section>
  );
}

// ⋯ is core's userMenu for every detail variant, so 编辑用户 / 启用·禁用 / 发放兑换码（补偿）/ 删除 stay one menu.
const VuMore = ({ ctx, u }) => <GlassButton icon="more" onClick={() => userMenu(ctx, u)} />;

/* ---------- 用户详情 · A 余额大数（已定，第 2 轮 Q10） ---------- */

// Top to bottom: banners (待核对 → 已禁用), balance hero with 充值 / 退款, API Key summary + 使用记录 ›, 充值与调整记录, 档案.
// 充值 loses its fill while a top-up is unconfirmed (vuTopup asks to reconcile first).
function VuHeroDetail({ ctx, id }) {
  const { skin } = ctx;
  const u = ctx.users[id];
  return (
    <Screen ctx={ctx} nav={<NavBar ctx={ctx} back title={u.name} subtitle={u.email} trailing={<VuMore ctx={ctx} u={u} />} />}>
      <VuPendingBanner ctx={ctx} u={u} />
      <VuDisabledBanner ctx={ctx} u={u} />
      <div className="balance-hero">
        <small>可用余额</small>
        <skin.Money value={u.balance} size="xl" />
        <div className="balance-sub">
          今日消费 <skin.Money value={u.today} size="s" /> {u.month !== undefined && <>· 本月 <skin.Money value={u.month} size="s" /></>}
          {vuIsLow(u) && <span className="vu-hero-flag"><skin.Badge tone="caution" label="余额低" /></span>}
        </div>
        <div className="actions">
          <ActionButton label="充值" icon="plus" primary={!u.pending} onClick={() => vuTopup(ctx, u)} />
          <ActionButton label="退款" icon="restore" onClick={() => vuOpenKeypad(ctx, u, 'refund')} />
        </div>
      </div>
      <VuKeySummary ctx={ctx} u={u} index="壹" logs />
      <VuLedger ctx={ctx} u={u} index="贰" />
      <VuProfile ctx={ctx} u={u} index="叁" />
    </Screen>
  );
}

/* ---------- 用户详情 · 钱包卡（B 式） ---------- */

// True once `ref`'s element has scrolled under the nav bar. SwiftUI: onScrollGeometryChange driving a ToolbarItem(.principal) opacity.
function useVuScrolledPast(ref) {
  const [past, setPast] = useState(false);
  useEffect(() => {
    const el = ref.current;
    const scroller = el && el.closest('.scroll');
    if (!scroller) return undefined;
    const onScroll = () => setPast(el.getBoundingClientRect().bottom <= scroller.getBoundingClientRect().top + 4);
    onScroll();
    scroller.addEventListener('scroll', onScroll, { passive: true });
    return () => scroller.removeEventListener('scroll', onScroll);
  }, []);
  return past;
}

function VuWalletDetail({ ctx, id }) {
  const u = ctx.users[id];
  const disabled = u.status === 'disabled';
  const low = vuIsLow(u);
  const idRef = useRef(null);
  const past = useVuScrolledPast(idRef);
  const navTitle = <span className={cx('vu-navtitle', past && 'is-shown')} aria-hidden={!past}>{u.name}</span>;
  return (
    <Screen ctx={ctx} nav={<NavBar ctx={ctx} back title={navTitle} trailing={<VuMore ctx={ctx} u={u} />} />}>
      <VuPendingBanner ctx={ctx} u={u} />
      <div className={cx('vu-wallet', disabled && 'is-disabled')}>
        <div className="vu-wallet-top" ref={idRef}>
          <span className="vu-wallet-avatar">{u.name.slice(0, 1)}</span>
          <span className="vu-wallet-id"><b>{u.name}</b><small>{u.email}</small></span>
          {disabled && <span className="vu-wallet-tag">禁用</span>}
          {low && <span className="vu-wallet-tag is-low">余额低</span>}
        </div>
        <small className="vu-wallet-label">可用余额</small>
        <VuBalance value={u.balance} className="vu-bal-xl" />
        <div className="vu-wallet-stats">
          <span><small>今日消费</small><b className="num">{fmt.money(u.today)}</b></span>
          {u.month !== undefined && <span><small>本月</small><b className="num">{fmt.money(u.month)}</b></span>}
        </div>
        <div className="vu-wallet-actions">
          <button className={cx('vu-pill', !u.pending && 'primary')} onClick={() => vuTopup(ctx, u)}><Icon name="plus" size={15} weight={2.8} />充值</button>
          <button className="vu-pill" onClick={() => vuOpenKeypad(ctx, u, 'refund')}><Icon name="restore" size={15} weight={2.4} />退款</button>
        </div>
      </div>
      <VuKeySummary ctx={ctx} u={u} index="壹" />
      <VuLedger ctx={ctx} u={u} index="贰" />
      <VuProfile ctx={ctx} u={u} index="叁" />
    </Screen>
  );
}

/* ---------- 用户详情 · 紧凑头部 + 流水在前 ---------- */

// Ledger row with amount (line 1) and time (line 2) pinned right like the decided log row; type and note on the left.
function VuLedgerRow({ l }) {
  const credit = !vuIsMoneyEntry(l) || l.amount > 0;
  const note = vuLedgerNote(l);
  return (
    <div className="row vu-lg-row">
      <div className="row-lead"><span className="vu-lg-icon"><Icon name={credit ? 'plus' : 'restore'} size={14} weight={2.6} /></span></div>
      <div className="vu-lg-main">
        <span className="vu-lg-kind">{l.kind}</span>
        {note && <span className="vu-lg-note">{note}</span>}
      </div>
      <div className="vu-lg-side">
        <b className="num">{vuIsMoneyEntry(l) ? fmt.money(l.amount, { sign: true }) : l.display || '—'}</b>
        <span className="num">{l.when}</span>
      </div>
    </div>
  );
}

// Head panel: balance + buttons on one line (wrapping the buttons under the balance when they no longer fit — SwiftUI:
// ViewThatFits / AnyLayout(HStack ↔ VStack) for accessibility sizes), then today / month / status as the panel's second line.
function VuCompactHead({ ctx, u }) {
  const { skin } = ctx;
  return (
    <div className="vu-head">
      <div className="vu-head-top">
        <div className="vu-head-bal"><small>可用余额</small><VuBalance value={u.balance} className="vu-bal-m" /></div>
        <div className="vu-head-acts">
          <button className={cx('vu-btn', !u.pending && 'primary')} onClick={() => vuTopup(ctx, u)}><Icon name="plus" size={15} weight={2.8} />充值</button>
          <button className="vu-btn" onClick={() => vuOpenKeypad(ctx, u, 'refund')}><Icon name="restore" size={15} weight={2.4} />退款</button>
        </div>
      </div>
      <div className="vu-head-sub">
        <span>今日消费 <b className="num">{fmt.money(u.today)}</b></span>
        {u.month !== undefined && <span>本月 <b className="num">{fmt.money(u.month)}</b></span>}
        {u.status === 'disabled' && <skin.Badge tone="neutral" label="禁用" />}
        {vuIsLow(u) && <skin.Badge tone="caution" label="余额低" />}
      </div>
    </div>
  );
}

function VuCompactDetail({ ctx, id }) {
  const { skin } = ctx;
  const u = ctx.users[id];
  const ledger = u.ledger || [];
  return (
    <Screen ctx={ctx} nav={<NavBar ctx={ctx} back title={u.name} subtitle={u.email} trailing={<VuMore ctx={ctx} u={u} />} />}>
      <VuPendingBanner ctx={ctx} u={u} />
      <VuCompactHead ctx={ctx} u={u} />
      <Section skin={skin} title={VU_LEDGER_TITLE} meta={ledger.length ? `${ledger.length} 笔` : undefined} index="壹">
        {ledger.length ? ledger.map((l, i) => <VuLedgerRow key={i} l={l} />) : <div className="empty pad">暂无记录</div>}
      </Section>
      <VuKeySummary ctx={ctx} u={u} index="贰" />
      <VuProfile ctx={ctx} u={u} index="叁" />
    </Screen>
  );
}

/* ---------- 用户列表：行 ---------- */

// Same as the base row (A): name + balance on line 1, email + status badge on line 2. Low balance is computed, not a stored flag.
function VuBaseRow({ ctx, u }) {
  const { skin } = ctx;
  const flag = vuUserFlag(u);
  return (
    <Row skin={skin} tone={u.pending ? 'caution' : 'none'} className={cx(`tone-${flag ? flag.tone : 'none'}`, u.status === 'disabled' && 'is-idle')}
      lead={<span className="avatar">{u.name.slice(0, 1)}</span>} onClick={() => ctx.push({ kind: 'user', id: u.id })}>
      <div className="row-top"><span className="row-title">{u.name}</span><skin.Money value={u.balance} size="m" /></div>
      <div className="row-foot">
        <span className="row-meta">{u.email}</span>
        {u.status === 'disabled' && <skin.Badge tone="neutral" label="禁用" />}
        {u.pending && <skin.Badge tone="caution" label="待核对" />}
        {vuIsLow(u) && !u.pending && <skin.Badge tone="caution" label="余额低" />}
      </div>
    </Row>
  );
}

// Right column pinned like the log row: line 1 balance (with status mark), line 2 today's spend. Pending keeps base's amber rail.
function VuColsRow({ ctx, u }) {
  const { skin } = ctx;
  const flag = vuUserFlag(u);
  return (
    <div className={cx('row tappable vu-urow', u.pending && cx('tone-caution', skin.rowClass('caution')), u.status === 'disabled' && 'is-idle')}
      onClick={() => ctx.push({ kind: 'user', id: u.id })}>
      <div className="row-lead"><span className="avatar">{u.name.slice(0, 1)}</span></div>
      <div className="vu-urow-main">
        <span className="row-title">{u.name}</span>
        <span className="vu-urow-mail">{u.email}</span>
      </div>
      <div className="vu-urow-side">
        <span className="vu-urow-bal">{flag && <VuMark flag={flag} />}<b className="num">{fmt.money(u.balance)}</b></span>
        <span className="vu-urow-today">今日 <span className="num">{fmt.money(u.today)}</span></span>
      </div>
      <div className="row-chev"><Icon name="chevron" size={13} weight={2.6} /></div>
    </div>
  );
}

const VU_LEGEND = [
  { key: 'low', tone: 'caution', label: '余额低' },
  { key: 'pending', tone: 'caution', label: '待核对' },
  { key: 'disabled', tone: 'neutral', label: '禁用' },
];

function VuColsHead() {
  return (
    <div className="list-head vu-cols-head">
      <span className="vu-legend">
        {VU_LEGEND.map(f => <span key={f.key}><VuMark flag={f} />{f.label}</span>)}
      </span>
      <b>余额 / 今日消费</b>
    </div>
  );
}

function VuUsersNav({ ctx, count }) {
  return <NavBar ctx={ctx} title="用户" subtitle={`${ctx.site} · ${count} 位`} trailing={<GlassButton icon="plus" onClick={() => ctx.push({ kind: 'userNew' })} />} />;
}

/* ---------- 用户列表 · 快捷充值头像 + 列表 ---------- */

// Recent balance adjustments (admin/user-adjustments) and low balances. Disabled users never appear; a pending user goes last,
// because tapping it opens the user to reconcile instead of topping up.
const VU_QUICK_IDS = [1, 2, 7, 4];

function VuQuickStrip({ ctx }) {
  const users = VU_QUICK_IDS.map(id => ctx.users[id])
    .filter(u => u && u.status !== 'disabled')
    .sort((a, b) => Number(Boolean(a.pending)) - Number(Boolean(b.pending)));
  return (
    <section className="vu-quick" aria-label="快捷充值">
      <div className="vu-quick-head"><span>快捷充值</span><small>最近调整 · 余额低</small></div>
      <div className="vu-quick-row">
        {users.map(u => {
          const flag = vuUserFlag(u);
          // A pending top-up must be reconciled first, so that avatar opens the user (with the 核对 banner) instead of the keypad.
          const go = u.pending ? () => ctx.push({ kind: 'user', id: u.id }) : () => vuOpenKeypad(ctx, u, 'topup');
          return (
            <button key={u.id} className={cx('vu-q', flag && `is-flag tone-${flag.tone}`, u.pending && 'is-pending')} onClick={go}
              aria-label={u.pending ? `${u.name}，上一笔充值待核对，打开详情去核对` : `给${u.name}充值，余额 ${fmt.money(u.balance)}`}>
              <span className="vu-q-avatar">
                {u.name.slice(0, 1)}
                <i className="vu-q-badge"><Icon name={u.pending ? 'docCheck' : 'plus'} size={u.pending ? 12 : 11} weight={u.pending ? 2.4 : 3.2} /></i>
              </span>
              <span className="vu-q-name">{u.name}</span>
              <span className="vu-q-sub num">{u.pending ? '去核对' : fmt.money(u.balance)}</span>
            </button>
          );
        })}
      </div>
    </section>
  );
}

/* ---------- 用户列表：三个变体共用一个外壳 ---------- */

// rows: 'rows' = A two-line rows, 'cols' = right pinned column. strip: show the quick top-up avatars above the list.
// Order: newest first, as Web lists users (UsersView default sort: created_at desc; ask with sort_by=created_at&sort_order=desc).
// The demo has no created_at, so usersNewestFirst falls back to id desc: the big customers #26 → #21 first, #1 王小明 last.
// The quick strip above keeps its own order (recent adjustments).
function VuUsersList({ ctx, rows, strip }) {
  const list = usersNewestFirst(ctx.users);
  const cols = rows === 'cols';
  return (
    <Screen plain ctx={ctx} nav={<VuUsersNav ctx={ctx} count={list.length} />}>
      <div className="search-field"><Icon name="search" size={16} /><span>邮箱、用户名或备注</span></div>
      {strip && <VuQuickStrip ctx={ctx} />}
      <div className="list-group">
        {cols ? <VuColsHead /> : strip && <div className="list-head"><span>全部用户</span><b className="num">{list.length}</b></div>}
        {list.map(u => (cols ? <VuColsRow key={u.id} ctx={ctx} u={u} /> : <VuBaseRow key={u.id} ctx={ctx} u={u} />))}
      </div>
    </Screen>
  );
}

// A two-line rows (same layout as base, with the computed low-balance flag), right pinned column, and the quick strip on top of either.
const VuUsersRows = ({ ctx }) => <VuUsersList ctx={ctx} rows="rows" />;
const VuUsersCols = ({ ctx }) => <VuUsersList ctx={ctx} rows="cols" />;
const VuUsersQuick = ({ ctx }) => <VuUsersList ctx={ctx} rows={ctx.v && ctx.v.usersRows === 'cols' ? 'cols' : 'rows'} strip />;

mvRegister('userDetail', 'hero', VuHeroDetail);
mvRegister('userDetail', 'wallet', VuWalletDetail);
mvRegister('userDetail', 'compact', VuCompactDetail);
mvRegister('users', 'rows', VuUsersRows);
mvRegister('users', 'cols', VuUsersCols);
mvRegister('users', 'quick', VuUsersQuick);
mvRegister('screen:userLedger', 'base', VuLedgerScreen);
