/* 兑换码 / 代理 / 公告：三个低频管理模块。
   已定（DECISIONS 第 3 轮）：兑换码 = inline「列表行内展开 + 编辑 sheet」；代理、公告 = base「列表 + 详情页 + 编辑 sheet」；
   批量生成 = steps 分步向导。没选中的变体（兑换码 base 与详情页、代理 / 公告 inline、生成 base）保留给对比页快照。
   - base「列表 + 详情页 + 新建 sheet」：List(.plain) 列表 → NavigationStack push 详情页；新建、编辑都是 sheet（Form）。
   - inline「列表行内展开 + 编辑 sheet」：卡片列表（List .insetGrouped，每张卡一个 Section），点卡片头原地展开，同一时间只展开一张
     （@State openID: Int?），展开后自动滚到能看全；不进二级页；编辑、新建用 sheet。
     兑换码展开后：码值框（默认遮罩，显示 / 复制）→ 使用与有效期 → 备注 → 按钮行。按钮行按状态：
     未使用「禁用 · 编辑 · ···」、已禁用「启用 · 编辑 · ···」、已过期「续期 · ···」（续期 = 编辑 sheet 选新过期时间，保存时一并改回未使用）、
     已使用「编辑备注 · ···」（batch-update 碰 status / expires_at / group_id 会返回 REDEEM_CODE_USED）。··· = 复制兑换码、查看使用者（已使用）、
     删除兑换码…（最后，红字）。删除确认用核心 confirmDelete（带输入框的 alert）：输入兑换码末 4 位（列表里露出的就是这 4 位，
     opts.match + caseInsensitive，大小写都算对）才能点删除；打开“高风险操作需要 Face ID”后不要输入，确认后由系统 Face ID 验证。
     滑动操作只挂在收起的卡片上（展开后按钮已经在卡片里，滑动会和卡片内的控件抢手势）：.swipeActions(edge: .trailing) =
     禁用 / 启用（未使用、已禁用）或 续期（已过期，打开编辑 sheet），.swipeActions(edge: .leading) = 复制兑换码；删除不放进滑动，
     只走 ··· 和输入末 4 位的确认。HTML 原型不演示滑动。
   批量生成兑换码（sheet:redeemGenerate）：base = 一页 Form；steps = 分步（类型 → 面额与数量 → 有效期与确认，NavigationStack in sheet）。生成后同一个 sheet 显示结果 + 全部复制。
   字段与能力对照 research/02 与 Sub2 源码，不虚构：
   - 兑换码 admin/redeem-codes：generate（count 1–100、type balance/concurrency/subscription/invitation、value、group_id、validity_days、expires_in_days；
     走 executeAdminIdempotentJSON 幂等执行），batch-update（status 只能 unused/disabled、expires_at 必须在将来、notes、group_id；
     已使用的码只要碰 status / expires_at / group_id 就返回 REDEEM_CODE_USED，所以已使用的码只能改备注），DELETE :id。
     状态词按 Web：未使用 / 已使用 / 已过期 / 已禁用。码值 = 32 位小写十六进制、不带横杠（generate → GenerateRedeemCodes →
     GenerateRedeemCode()：hex.EncodeToString(16 字节)，service/redeem_code.go）；带横杠的大写格式出自 RedeemService.GenerateRandomCode，
     只被没有调用方的 GenerateCodes 用到，不是管理端生成的样子。显示时 16 + 16 两行、每 4 位留一点空隙（只是排版，复制的是原码）。
     generate 没有“前缀”和备注参数，所以这里不做前缀。
   - 代理 admin/proxies：name、protocol http/https/socks5/socks5h、host、port、username、password、status active/inactive/expired（正常 / 停用 / 已过期）、
     expires_at、expiry_warn_days、fallback_mode none/proxy/direct + backup_proxy_id、account_count、latency_ms/latency_status/latency_message、
     出口 IP 与地区、quality_score/grade/quality_checked；POST :id/test、:id/quality-check；GET :id/accounts。没有“上次延迟测试时间”字段。
     ProxyExpiryService 周期扫描：active 代理一过期就改成 expired，并按 fallback_mode 把在用的账号改投直连 / 备用代理（none 则账号不动）；
     账号保留 proxy_fallback_origin_id，可在账号详情“恢复原代理”（revert-proxy-fallback）。回退链跳过停用或过期的代理。
     停用（inactive）不影响已绑定账号的流量（网关取 account.Proxy.URL() 不看状态），只是账号编辑里选不到它（/proxies/all 只返回 active）、也不会被选作回退目标。
     有账号在用的代理不能删除（Web：该代理已有账号使用，无法删除）。PUT 只接受 active/inactive，所以编辑已过期的代理时状态预设为“停用”（同 Web）。
   - 公告 admin/announcements：title、content（Markdown）、status draft/active/archived（草稿 / 展示中 / 已归档）、notify_mode silent/popup（静默 / 弹窗）、
     targeting any_of[all_of[订阅套餐 in / 余额 比较]]（空 = 所有用户）、starts_at/ends_at（空 = 立即 / 永久）。
     GET :id/read-status 是全部用户的分页列表（search、sort_by email/username/balance），每行 email、username、balance、eligible、read_at；
     没有“已读 N / 符合条件 M”的汇总，也不能按已读筛选或按 read_at 排序，所以列表和详情不画已读进度。
   - 兑换码列表的搜索 = GET redeem-codes?search=：码值包含（不分大小写）或使用者邮箱包含（CodeContainsFold / HasUserWith(EmailContainsFold)），不搜备注。
   - 发放兑换码（补偿）POST admin/redeem-codes/create-and-redeem（handler/admin/redeem_handler.go CreateAndRedeem）：
     code（必填 3–128，手机端随机生成，同时是幂等依据：同一码已被同一用户兑换时直接返回，被别人用了返回 REDEEM_CODE_CONFLICT）、
     type balance / concurrency / subscription（invitation 在兑换时报 REDEEM_CODE_UNSUPPORTED_TYPE，只能注册时用，所以不提供；不传 type 默认 balance）、
     value（binding:"required"，float64 不能为 0；订阅类型兑换时不读它，手机端传有效天数，Web 的记录在 validity_days 缺失时也拿 value 当天数）、
     user_id（> 0）、group_id + validity_days（订阅必填，天数非 0；负数是扣减，补偿只给正数）、notes；expires_at / expires_in_days 对立即兑换的码没有意义，不传。
     请求走 executeAdminIdempotentJSON（RequireKey: true，必须带 Idempotency-Key 头；手机端在 sheet 打开时生成，重试沿用）。
     兑换走 RedeemForAdminFulfillment：不计入用户的兑换失败次数；余额类正数会照常触发邀请返利（返利开启时给邀请人记一笔，和用户自己兑换一样）。
     兑换后在用户的 balance-history 里出现一条（Web 文案：余额充值（兑换）/ 并发增加（兑换）/ 订阅已分配；数值列 Web 显示 +$20.00 / +2 / 30d - 企业专线）。
   - 订阅类分组只认 DEMO.groups 里 subscriptionType = subscription 的分组（generate 校验 group must be subscription type）；公告的订阅条件也是这些分组。
   - Face ID 读全局 ctx.faceId 和 core 的 FACE_ID_LIMIT：生成余额兑换码、发放余额补偿超过门槛时，确认后再验证。
   - 生成请求没有应答时写 ctx.setRedeemPending（概览“待处理”出现一条），核对或用同一编号重试成功后清除；列表顶部同时给核对横幅。
   - 代理读 DEMO.proxies（本文件只把它复制进每台手机的可变数据）；代理 ↔ 账号的关系以账号的 proxy（代理名称）为准，每次渲染从
     ctx.accounts 现算（vmoProxies），所以账号编辑页换了代理，这里的“使用该 IP 的账号”跟着变；代理改名时同步改这些账号的 proxy。
   - ⋯ 一律是菜单（SwiftUI Menu）：工具栏的 ⋯ 用 ctx.menu；展开卡片里的 ⋯ 用同样的行（普通项在前、删除红字在最后、没有“取消”），
     但从这个按钮下方弹出（VmoMoreBtn）。ctx.confirm 只用于确认框。
   每台手机一份可变演示数据：按 ctx.openSheet（每台手机稳定的 setState）分开存放。 */

/* ---------- per-phone store ---------- */

const VMO_STORES = new WeakMap();

function vmoStore(ctx) {
  let s = VMO_STORES.get(ctx.openSheet);
  if (!s) {
    s = { data: { codes: VMO_CODES, proxies: VMO_PROXIES, notices: VMO_NOTICES, busy: {} }, subs: new Set() };
    VMO_STORES.set(ctx.openSheet, s);
  }
  return s;
}

function useVmo(ctx) {
  const s = vmoStore(ctx);
  const [, bump] = useState(0);
  useEffect(() => {
    const f = () => bump(x => x + 1);
    s.subs.add(f);
    return () => { s.subs.delete(f); };
  }, [s]);
  return s;
}

function vmoSet(s, key, fn) {
  s.data = { ...s.data, [key]: fn(s.data[key]) };
  s.subs.forEach(f => f());
}
const vmoPatch = (s, key, id, patch) => vmoSet(s, key, list => list.map(x => (x.id === id ? { ...x, ...patch } : x)));
const vmoRemove = (s, key, id) => vmoSet(s, key, list => list.filter(x => x.id !== id));
const vmoBusy = (s, key, on) => vmoSet(s, 'busy', b => { const next = { ...b }; if (on) next[key] = true; else delete next[key]; return next; });

/* ---------- demo data (the demo's day = DEMO_TODAY, at the frame's 09:41) ---------- */

// Dates count from core's DEMO_TODAY (daysUntil / proxyExpiry); this file only needs to print them. 'YYYY-MM-DD' → 'MM/DD'
// ('—' without a date), n days after an ISO date, and the demo's "now" in the 'MM/DD HH:MM' stamps the lists store.
const vmoMD = iso => (iso ? iso.slice(5, 10).replace('-', '/') : '—');
const vmoIsoPlus = (iso, n) => { const [y, m, d] = iso.split('-').map(Number); return new Date(Date.UTC(y, m - 1, d + n)).toISOString().slice(0, 10); };
const VMO_YEAR = DEMO_TODAY.slice(0, 4);
const VMO_NOW = `${vmoMD(DEMO_TODAY)} ${fmt.clock(DEMO_CLOCK_BASE)}`;
const VMO_NOW_ISO = `${DEMO_TODAY}T${fmt.clock(DEMO_CLOCK_BASE)}`;
// Subscription redeem codes and announcement conditions point at subscription-type groups (group_id); read them from DEMO.
const VMO_SUB_GROUPS = DEMO.groups.filter(g => g.subscriptionType === 'subscription' && g.status === 'active').map(g => g.name);
const VMO_SUB = VMO_SUB_GROUPS[0] || '—';

const VMO_CODES = [
  { id: 2046, code: 'a3f09c1e7b2d44af90c1e3b75b20d4e8', type: 'balance', value: 10, status: 'unused', createdAt: '10/16 09:12', expiresAt: '10/23 09:12', notes: '社群活动 · 第 3 批' },
  { id: 2045, code: '5d7e21b0c4a9f3e20b88d61c7fa3e519', type: 'balance', value: 10, status: 'unused', createdAt: '10/16 09:12', expiresAt: '10/23 09:12', notes: '社群活动 · 第 3 批' },
  { id: 2044, code: 'e81c6a0f339b7d25c0f4a1e82d6b90c3', type: 'balance', value: 10, status: 'used', usedBy: 1, usedAt: '10/16 09:20', createdAt: '10/16 09:12', expiresAt: '10/23 09:12', notes: '社群活动 · 第 3 批' },
  { id: 2038, code: '9b4d0e72a1c83f567e2b94d0c5f81a36', type: 'subscription', group: VMO_SUB, days: 30, status: 'unused', createdAt: '10/15 18:40', expiresAt: '10/31 18:40', notes: '' },
  { id: 2036, code: '3c0a7f91d25e8b461f9c3a07b8e46d2f', type: 'balance', value: 50, status: 'used', usedBy: 3, usedAt: '10/15 21:06', createdAt: '10/15 21:05', expiresAt: null, notes: '客服补偿 · 工单 #8812' },
  { id: 2031, code: 'f6b2c8490e7a13d59c4f68b12a0e7d93', type: 'concurrency', value: 2, status: 'used', usedBy: 5, usedAt: '10/14 16:20', createdAt: '10/14 16:02', expiresAt: null, notes: '' },
  { id: 2027, code: '72e0d5a3b9c14f863d7a20e5c18b6f04', type: 'invitation', status: 'unused', createdAt: '10/13 11:00', expiresAt: null, notes: '内测邀请' },
  { id: 2019, code: '0d9f3b6c82a5e147f3c0b9d26e14a8c7', type: 'balance', value: 20, status: 'expired', createdAt: '10/03 10:00', expiresAt: '10/10 10:00', notes: '' },
  { id: 2015, code: 'b5a81e3d6f0c92b74e3d15a90c7f28e6', type: 'balance', value: 5, status: 'disabled', createdAt: '10/02 15:30', expiresAt: null, notes: '误发，已禁用' },
  { id: 2012, code: '4e7c0b95d3a26f18b0e95c4a7d21f6e3', type: 'subscription', group: VMO_SUB, days: 7, status: 'used', usedBy: 8, usedAt: '10/09 13:12', createdAt: '10/08 20:00', expiresAt: null, notes: '' },
];

// Proxies are DEMO.proxies (admin/proxies list DTO: latency_ms / latency_status / latency_message, no "tested at" time, so the UI
// never prints when the last test ran; qualityAt mirrors quality_checked; probe = what a test run returns in the demo). Each phone
// keeps its own editable copy; `accounts` is not stored here — vmoProxies() derives it from the accounts' own proxy field.
const VMO_PROXIES = DEMO.proxies.map(({ accounts, ...p }) => p);

// The account ↔ proxy link lives on the account (ctx.accounts[id].proxy = proxy name), so a proxy changed on the account page shows
// up here at once. Account ids ascend, like GET proxies/:id/accounts.
function vmoAccountsOn(ctx, name) {
  return Object.values(ctx.accounts).filter(a => a.proxy === name).map(a => a.id).sort((x, y) => x - y);
}
const vmoProxies = (ctx, s) => s.data.proxies.map(p => ({ ...p, accounts: vmoAccountsOn(ctx, p.name) }));

// List DTO has no read counts; read status is a separate paginated per-user list (VMO_READ_ROWS).
const VMO_NOTICES = [
  { id: 31, title: '10 月 18 日凌晨维护通知', status: 'active', notify: 'popup', target: null, startsAt: '10/16 08:00', endsAt: '10/18 06:00', createdAt: '10/15 22:10', updatedAt: '10/16 07:55',
    content: '**维护时间**：10 月 18 日 02:00–04:00（北京时间）\n\n维护期间：\n- API 请求可能短暂返回 502，请在客户端开启重试\n- 控制台暂停充值与兑换\n\n如有问题，请在[工单中心](https://example.com/ticket)联系我们。' },
  { id: 30, title: '企业专线新增 gpt-4.1 长上下文', status: 'active', notify: 'silent', target: [[{ type: 'subscription', groups: [VMO_SUB] }]], startsAt: null, endsAt: null, createdAt: '10/14 10:30', updatedAt: '10/14 10:30',
    content: `**${VMO_SUB}**订阅用户现在可以使用 gpt-4.1 的长上下文。\n\n- 计费倍率与原来相同\n- 每日、每周、每月限额不变` },
  { id: 29, title: '余额不足提醒', status: 'draft', notify: 'popup', target: [[{ type: 'balance', op: 'lt', value: 5 }]], startsAt: null, endsAt: null, createdAt: '10/13 17:02', updatedAt: '10/16 09:05',
    content: '你的余额已低于 **$5.00**。为避免请求中断，请及时充值。' },
  { id: 27, title: '国庆期间客服时间调整', status: 'archived', notify: 'silent', target: null, startsAt: '10/01 00:00', endsAt: '10/08 23:59', createdAt: '09/28 15:20', updatedAt: '10/09 09:00',
    content: '10 月 1 日至 8 日，客服在线时间调整为 **10:00–18:00**。\n\n工单仍然 24 小时受理。' },
  { id: 24, title: '新模型计费说明', status: 'archived', notify: 'silent', target: [[{ type: 'subscription', groups: [VMO_SUB] }, { type: 'balance', op: 'gte', value: 10 }], [{ type: 'balance', op: 'gte', value: 500 }]], startsAt: '09/20 09:00', endsAt: '10/05 23:59', createdAt: '09/19 18:44', updatedAt: '10/06 08:12',
    content: '## 计费口径\n\n- 实际扣费 = 标准价 × 分组倍率\n- 缓存读取按官方折扣计费' },
];

// GET /admin/announcements/:id/read-status rows: one per user (all users, not only eligible), email / username / balance /
// eligible / read_at. The demo users stand for page 1 of the list; read_at is demo data per notice, eligible is worked out like the
// server does (AnnouncementTargeting.Matches against the user's balance and active subscriptions, see vmoEligible).
const VMO_READ_TOTAL = 1036;
const VMO_READ_AT = {
  31: { 3: '10/16 08:03', 1: '10/16 08:12', 8: '10/16 08:40', 5: '10/16 09:15' },
  30: { 3: '10/14 11:02', 8: '10/15 19:47' },
  27: { 1: '10/01 09:20', 2: '10/02 13:05', 3: '10/01 10:11', 5: '10/03 08:44', 8: '10/04 21:30' },
  24: { 3: '09/21 10:02', 8: '09/22 16:18' },
};
function vmoReadRows(n) {
  const read = VMO_READ_AT[n.id] || {};
  return DEMO.users.map(u => ({ id: u.id, email: u.email, username: u.name, balance: u.balance, eligible: vmoEligible(n.target, u), readAt: read[u.id] || null }));
}

/* ---------- vocabulary ---------- */

const VMO_TYPE = {
  balance: { label: '余额', icon: 'dollar', hint: '余额金额（美元），兑换后计入用户余额。' },
  concurrency: { label: '并发数', icon: 'gauge', hint: '并发数增量，兑换后提高用户的并发上限。' },
  subscription: { label: '订阅', icon: 'group', hint: '兑换后开通或延长所选订阅分组。' },
  invitation: { label: '邀请码', icon: 'people', hint: '邀请码用于限制用户注册，使用后自动标记为已使用。' },
};
const VMO_CODE_STATUS = {
  unused: { label: '未使用', tone: 'ok', icon: 'dot' },
  used: { label: '已使用', tone: 'neutral', icon: 'check' },
  expired: { label: '已过期', tone: 'neutral', icon: 'hourglass' },
  disabled: { label: '已禁用', tone: 'neutral', icon: 'minus' },
};
const VMO_PROTO = { http: 'HTTP', https: 'HTTPS', socks5: 'SOCKS5', socks5h: 'SOCKS5H' };
const VMO_PROXY_STATUS = {
  active: { label: '正常', tone: 'ok', icon: 'dot' },
  inactive: { label: '停用', tone: 'neutral', icon: 'minus' },
  expired: { label: '已过期', tone: 'critical', icon: 'clockAlert' },
};
// An expired proxy is only red while accounts still ride on it; once nothing uses it (or the sweep moved them) it is a quiet fact.
const vmoProxyBadge = p => (p.status === 'expired' && !p.accounts.length ? { ...VMO_PROXY_STATUS.expired, tone: 'neutral' } : VMO_PROXY_STATUS[p.status]);
const VMO_FALLBACK = { none: '不回退', proxy: '指定备用代理', direct: '回退直连' };
const VMO_NOTICE_STATUS = {
  draft: { label: '草稿', tone: 'neutral', icon: 'compose' },
  active: { label: '展示中', tone: 'ok', icon: 'dot' },
  archived: { label: '已归档', tone: 'neutral', icon: 'tray' },
};
const VMO_NOTIFY = { silent: '静默', popup: '弹窗' };
const VMO_OPS = { gt: '>', gte: '≥', lt: '<', lte: '≤', eq: '=' };
const VMO_EXPIRY = [['never', '永不过期'], ['1', '1 天'], ['3', '3 天'], ['7', '7 天'], ['custom', '自定义']];

/* ---------- helpers ---------- */

const vmoShort = code => `${code.slice(0, 4)}····${code.slice(-4)}`;
// 32 hex characters as two 16-character lines, each in four groups of 4 (the gap between groups is spacing, not a character, so
// copying by hand or by selection gives the raw code). Masked, only what the list already shows stays: the first 4 and the last 4.
// SwiftUI: two monospaced Text lines; VoiceOver reads the whole code (accessibilityLabel).
const vmoQuads = text => text.match(/.{1,4}/g) || [];
const vmoCodeLines = (code, shown) => {
  const lines = [code.slice(0, 16), code.slice(16)];
  if (shown) return lines.map(vmoQuads);
  return [[code.slice(0, 4), '••••', '••••', '••••'], ['••••', '••••', '••••', code.slice(-4)]];
};
function VmoCodeText({ code, shown = true, className }) {
  return (
    <span className={cx('mono vmo-code-text', className)} role="text" aria-label={shown ? code : `兑换码已遮罩，结尾 ${code.slice(-4)}`}>
      {vmoCodeLines(code, shown).map((quads, i) => (
        <span key={i} className="vmo-code-line" aria-hidden="true">
          {quads.map((q, j) => <span key={j} className={cx('vmo-quad', q === '••••' && 'vmo-dots')}>{q}</span>)}
        </span>
      ))}
    </span>
  );
}
const vmoUser = id => DEMO.users.find(u => u.id === id) || null;
const vmoUserName = id => (vmoUser(id) ? vmoUser(id).name : `用户 #${id}`);
const vmoDay = stamp => (stamp ? stamp.split(' ')[0] : '—');

function vmoCodeValue(c) {
  if (c.type === 'balance') return fmt.money(c.value);
  if (c.type === 'concurrency') return `+${c.value} 并发`;
  if (c.type === 'subscription') return `${c.days} 天`;
  return '注册邀请';
}

// One line under the code: who used it and on which day (the time of day lives in the detail / expanded card).
function vmoCodeLine(c) {
  const head = c.type === 'subscription' ? c.group : VMO_TYPE[c.type].label;
  if (c.status === 'used') return `${head} · ${vmoUserName(c.usedBy)} · ${vmoDay(c.usedAt)}`;
  if (c.status === 'expired') return `${head} · ${vmoDay(c.expiresAt)} 已过期`;
  if (c.status === 'disabled') return `${head} · ${vmoDay(c.createdAt)} 生成`;
  return `${head} · ${c.expiresAt ? `${vmoDay(c.expiresAt)} 过期` : '永不过期'}`;
}

// The demo's today plus n days, as a 'MM/DD HH:MM' stamp at the demo's time of day
const vmoAddDays = n => `${vmoMD(vmoIsoPlus(DEMO_TODAY, n))} ${VMO_NOW.split(' ')[1]}`;

// 'MM/DD HH:MM' (demo year) → 'YYYY-MM-DD', and whole days from the demo's today to it (daysUntil); null when there is no stamp.
const vmoStampIso = stamp => `${VMO_YEAR}-${stamp.split(' ')[0].replace('/', '-')}`;
const vmoStampDays = stamp => (stamp ? daysUntil(vmoStampIso(stamp)) : null);

// A date in another year than the demo's keeps its year: '10/20', '2027/01/31'.
const vmoDate = iso => (iso && iso.slice(0, 4) !== VMO_YEAR ? iso.replace(/-/g, '/') : vmoMD(iso));

// Proxy expiry wording and countdown = core proxyExpiry (Web: 永不过期 / N 天后到期 / 剩余 N 天).
// Needs a human: expired but accounts are still on it, or an active proxy with accounts about to expire.
const vmoNeedsCare = p => p.accounts.length > 0 && (p.status === 'expired' || (p.status === 'active' && proxyExpiry(p).key === 'soon'));
const vmoLinkFailed = p => p.status !== 'inactive' && p.latencyOk === false && (p.status === 'active' || p.accounts.length > 0);

function vmoProxyTone(p) {
  if (p.status === 'inactive') return 'none';
  if (p.status === 'expired') return p.accounts.length ? 'critical' : 'none';
  if (p.latencyOk === false) return 'critical';
  if (proxyExpiry(p).key === 'soon') return 'caution';
  return 'none';
}

// What the expiry did / will do, in one sentence.
function vmoExpiryNote(p, backup) {
  const n = p.accounts.length;
  // non-breaking hyphen so a name like sg-01 never wraps at its hyphen
  const to = p.fallback === 'direct' ? '直连' : backup ? ` ${backup.name.replace(/-/g, '‑')}` : '备用代理';
  if (p.status === 'expired') {
    if (n) return { tone: 'critical', text: `已过期，${n} 个账号仍在用这个代理。到期回退设的是“不回退”，所以账号没被改走；续期，或到账号编辑页换代理。` };
    if (p.fallback === 'none') return { tone: 'neutral', text: '已过期，没有账号在用。' };
    return { tone: 'neutral', text: `到期后已把在用的账号改为${to}。要改回来，在账号详情里点“恢复原代理”。` };
  }
  const e = proxyExpiry(p);
  if (e.key !== 'soon') return null;
  if (p.fallback === 'none') return { tone: 'caution', text: `${e.label}。到期后不回退${n ? `，在用的 ${n} 个账号会继续挂在这个过期代理上` : ''}。` };
  return { tone: 'caution', text: `${e.label}。到期后把在用的账号改为${to}。` };
}

const vmoAddr = p => `${VMO_PROTO[p.protocol]} · ${p.host}:${p.port}`;
const vmoCond = c => (c.type === 'subscription' ? `订阅 ${c.groups.join('、')}` : `余额 ${VMO_OPS[c.op]} ${fmt.money(c.value)}`);
const vmoTarget = t => (!t || !t.length ? '所有用户' : t.map(g => g.map(vmoCond).join(' 且 ')).join(' 或 '));
const vmoRange = n => `${n.startsAt || '立即'} – ${n.endsAt || '永久'}`;
const vmoSimpleTarget = t => !t || (t.length === 1 && t[0].length === 1);

// Whether a user meets a notice's targeting, the way read-status computes eligible (domain AnnouncementTargeting.Matches): no rule =
// everyone; any_of groups, each needing all of its conditions; 订阅 = an active subscription (DEMO.subscriptions) in one of the groups.
const VMO_OP_TEST = { gt: (a, b) => a > b, gte: (a, b) => a >= b, lt: (a, b) => a < b, lte: (a, b) => a <= b, eq: (a, b) => a === b };
const vmoCondMet = (c, u) => (c.type === 'subscription'
  ? c.groups.some(g => activeSubscription(u.id, g))
  : Boolean(VMO_OP_TEST[c.op] && VMO_OP_TEST[c.op](u.balance, c.value)));
const vmoEligible = (t, u) => !t || !t.length || t.some(g => g.length > 0 && g.every(c => vmoCondMet(c, u)));

// '10/16 08:00' ⇄ '2026-10-16T08:00' (the demo's year) for the date pickers
const vmoIso = stamp => `${vmoStampIso(stamp)}T${stamp.split(' ')[1]}`;
const vmoStamp = iso => `${iso.slice(5, 10).replace('-', '/')} ${iso.slice(11, 16)}`;

function vmoGroupByDay(list) {
  const today = vmoMD(DEMO_TODAY);
  const yesterday = vmoMD(vmoIsoPlus(DEMO_TODAY, -1));
  const groups = [['今天', l => l.startsWith(today)], ['昨天', l => l.startsWith(yesterday)], ['更早', () => true]];
  const used = new Set();
  return groups.map(([title, test]) => {
    const rows = list.filter(c => !used.has(c.id) && test(c.createdAt));
    rows.forEach(c => used.add(c.id));
    return [title, rows];
  }).filter(([, rows]) => rows.length);
}

// Where one code is shown: the decided inline list opens that card; the base variant has a detail page.
function vmoShowCode(ctx, id) {
  if ((ctx.v && ctx.v['screen:redeem']) === 'inline') ctx.push({ kind: 'redeem', open: id });
  else ctx.push({ kind: 'redeemDetail', id });
}

function vmoCopy(ctx, what) {
  ctx.showToast({ text: `已复制${what}`, icon: 'check', tone: 'neutral' });
}

// Global setting (Settings → 高风险操作需要 Face ID) and core's FACE_ID_LIMIT; wording matches submitBalanceChange.
const vmoNeedsFace = (ctx, amount) => Boolean(ctx.faceId) && amount > FACE_ID_LIMIT;
const vmoFaceLine = (what = '') => `${what}超过 ${fmt.money(FACE_ID_LIMIT, { digits: 0 })}，确认后验证 Face ID。`;

// 16 random bytes → 32 lower-case hex characters, no hyphens: what admin/redeem-codes/generate returns (GenerateRedeemCode =
// hex.EncodeToString). create-and-redeem takes a code from the phone; it is made the same way so both look alike in the list.
function vmoNewCode(seed) {
  let x = (seed * 2654435761) >>> 0 || 1;
  let hex = '';
  while (hex.length < 32) {
    x ^= x << 13; x >>>= 0; x ^= x >>> 17; x ^= x << 5; x >>>= 0;
    hex += (x % 16).toString(16);
  }
  return hex;
}

/* ---------- small UI pieces ---------- */

const VMO_SHAPES = {
  copy: <><rect x="8.5" y="8.5" width="11.5" height="11.5" rx="2.5" /><path d="M15.5 8.5V6a2 2 0 0 0-2-2H6a2 2 0 0 0-2 2v7.5a2 2 0 0 0 2 2h2.5" /></>,
  eye: <><path d="M2.5 12s3.5-6.5 9.5-6.5 9.5 6.5 9.5 6.5-3.5 6.5-9.5 6.5S2.5 12 2.5 12z" /><circle cx="12" cy="12" r="3" /></>,
  eyeOff: <><path d="M4 4l16 16" /><path d="M9.9 5.8A9.6 9.6 0 0 1 12 5.5c6 0 9.5 6.5 9.5 6.5a17 17 0 0 1-2.6 3.4M6.4 7.4C3.9 9.2 2.5 12 2.5 12s3.5 6.5 9.5 6.5a9.4 9.4 0 0 0 4.4-1.1" /><path d="M10 10a3 3 0 0 0 4 4" /></>,
  bold: <path d="M7 5h6a3.5 3.5 0 0 1 0 7H7zM7 12h7a3.5 3.5 0 0 1 0 7H7z" />,
  bullets: <path d="M9 7h11M9 12h11M9 17h11M4.5 7h.01M4.5 12h.01M4.5 17h.01" />,
  heading: <path d="M6 5v14M18 5v14M6 12h12" />,
  link: <><path d="M10 14a4 4 0 0 0 5.7 0l3-3a4 4 0 0 0-5.7-5.7l-1 1" /><path d="M14 10a4 4 0 0 0-5.7 0l-3 3a4 4 0 0 0 5.7 5.7l1-1" /></>,
  minusSign: <path d="M6 12h12" />,
};

function VmoIcon({ name, size = 16, weight = 2 }) {
  if (!VMO_SHAPES[name]) return <Icon name={name} size={size} weight={weight} />;
  return (
    <svg width={size} height={size} viewBox="0 0 24 24" aria-hidden="true" style={{ flex: 'none', display: 'block' }}>
      <g fill="none" stroke="currentColor" strokeWidth={weight} strokeLinecap="round" strokeLinejoin="round">{VMO_SHAPES[name]}</g>
    </svg>
  );
}

function VmoBadge({ tone, icon, label }) {
  return (
    <span className={cx('badge', `tone-${tone}`, tone === 'neutral' && 'lv1')}>
      {icon && <Icon name={icon} size={icon === 'dot' ? 10 : 12} weight={2.4} />}<span>{label}</span>
    </span>
  );
}

function VmoAct({ label, icon, onClick, primary, small, disabled }) {
  return (
    <button className={cx('act vmo-act', primary && 'act-primary', small && 'act-small')} onClick={stop(onClick)} disabled={disabled}>
      {icon && <VmoIcon name={icon} size={small ? 14 : 16} weight={2.4} />}<span>{label}</span>
    </button>
  );
}

// ⋯ inside an open card = SwiftUI Menu on that button: the same spec as ctx.menu ({title?, message?, actions}; plain rows first,
// destructive ones last behind a divider, no 取消 row — tapping outside closes it), dropped from the button instead of the toolbar
// corner, and flipped above it when there is no room below. `menu` builds the spec when opened. The menu is portaled to the
// phone's screen so the card's clipping can't cut it.
function VmoMoreBtn({ menu }) {
  const ref = useRef(null);
  const [at, setAt] = useState(null);
  const host = at && ref.current ? ref.current.closest('.screen') : null;
  return (
    <>
      <button ref={ref} className="act vmo-more" data-icon="more" aria-label="更多操作" aria-haspopup="menu" aria-expanded={Boolean(at)}
        onClick={stop(() => setAt(vmoAnchor(ref.current, true)))}><Icon name="more" size={18} /></button>
      {host && ReactDOM.createPortal(<VmoActionMenu at={at} spec={menu()} onClose={() => setAt(null)} />, host)}
    </>
  );
}

function VmoActionMenu({ at, spec, onClose }) {
  const box = useRef(null);
  const [up, setUp] = useState(false);
  React.useLayoutEffect(() => {
    const el = box.current;
    if (el && at.top + el.offsetHeight > at.room - 12) setUp(true);
  }, []);
  const items = spec.actions.filter(a => a.role !== 'cancel');
  const plain = items.filter(a => a.role !== 'destructive');
  const danger = items.filter(a => a.role === 'destructive');
  const row = a => (
    <button key={a.label} role="menuitem" className={cx('menu-item action-menu-item', a.role === 'destructive' && 'is-destructive')}
      disabled={a.disabled} onClick={() => { onClose(); if (a.onPress) a.onPress(); }}>
      <span className="menu-label">{a.label}{a.sub && <small>{a.sub}</small>}</span>
    </button>
  );
  const pos = up ? { top: 'auto', bottom: at.above, right: at.right, transformOrigin: 'bottom right' } : { top: at.top, right: at.right };
  return (
    <div className="overlay vmo-menu-layer" onClick={onClose}>
      <div ref={box} className="menu glass action-menu vmo-anchor-menu" style={pos} role="menu" aria-label={spec.title} onClick={e => e.stopPropagation()}>
        {spec.title && <div className="action-menu-title">{spec.title}</div>}
        {spec.message && <div className="action-menu-note">{spec.message}</div>}
        {plain.map(row)}
        {danger.length > 0 && plain.length > 0 && <div className="menu-sep" />}
        {danger.map(row)}
      </div>
    </div>
  );
}

// System-like sheet with a free leading action (取消 / 上一步 / 完成); tapping the dimmed area dismisses.
// `locked` (Face ID in progress) holds the sheet: SwiftUI .interactiveDismissDisabled + a disabled leading button.
function VmoSheet({ title, leading, onDismiss, trailing, tall, children, className, locked }) {
  return (
    <div className="overlay overlay-dim sheet-overlay" onClick={locked ? undefined : onDismiss}>
      <div className={cx('sheet', tall && 'sheet-tall', 'vmo-sheet', className)} onClick={e => e.stopPropagation()}>
        <div className="sheet-grabber" />
        <div className="sheet-bar">
          <button className="glass-btn glass-btn-text" onClick={leading.onPress} disabled={locked}>{leading.back && <Icon name="back" size={15} weight={2.6} />}<span>{leading.label}</span></button>
          <div className="sheet-title">{title}</div>
          {trailing || <span className="nav-spacer" />}
        </div>
        <div className="sheet-body">{children}</div>
      </div>
    </div>
  );
}

function VmoBarBtn({ label, onClick, disabled }) {
  return <button className="glass-btn glass-btn-text glass-prominent vmo-barbtn" onClick={onClick} disabled={disabled}><span>{label}</span></button>;
}

function VmoFsec({ title, foot, children }) {
  return (
    <div className="vmo-fsec">
      {title && <div className="vmo-fsec-head">{title}</div>}
      <div className="vmo-form">{children}</div>
      {foot && <div className="vmo-fsec-foot">{foot}</div>}
    </div>
  );
}

function VmoField({ label, value, onChange, placeholder, mono, type = 'text', inputMode }) {
  return (
    <label className="vmo-frow">
      <span className="vmo-flabel">{label}</span>
      <input className={cx(mono && 'mono')} type={type} inputMode={inputMode} value={value} placeholder={placeholder} onChange={e => onChange(e.target.value)} />
    </label>
  );
}

// SwiftUI: Stepper. `bare` hides the number when a TextField beside it already shows the value.
function VmoStepper({ value, min = 1, max = 100, onChange, label, bare }) {
  return (
    <span className={cx('vmo-stepper', bare && 'is-bare')} role="group" aria-label={label}>
      <button onClick={() => onChange(Math.max(min, value - 1))} disabled={value <= min} aria-label="减少"><VmoIcon name="minusSign" size={18} weight={2.4} /></button>
      {!bare && <b className="num">{value}</b>}
      <button onClick={() => onChange(Math.min(max, value + 1))} disabled={value >= max} aria-label="增加"><Icon name="plus" size={18} weight={2.4} /></button>
    </span>
  );
}

// SwiftUI: TextField(.numberPad) + Stepper on one Form row; typing is clamped on blur.
function VmoCountField({ label, value, min = 1, max = 100, onChange, unit }) {
  const [text, setText] = useState(String(value));
  useEffect(() => { setText(String(value)); }, [value]);
  const commit = raw => {
    const n = Math.min(max, Math.max(min, Number(raw) || min));
    setText(String(n));
    onChange(n);
  };
  return (
    <div className="vmo-frow">
      <span className="vmo-flabel">{label}</span>
      <span className="vmo-fill" />
      <input className="num vmo-count-input" inputMode="numeric" aria-label={label} value={text}
        onChange={e => { const t = e.target.value.replace(/\D/g, '').slice(0, String(max).length); setText(t); if (Number(t) >= min && Number(t) <= max) onChange(Number(t)); }}
        onBlur={e => commit(e.target.value)} />
      {unit && <span className="vmo-unit">{unit}</span>}
      <VmoStepper bare value={value} min={min} max={max} onChange={onChange} label={label} />
    </div>
  );
}

// items: [key, label, disabled?, note?]; multi = value is an array (toggle each)
function VmoChoice({ items, value, onChange, multi }) {
  const isOn = key => (multi ? (value || []).includes(key) : value === key);
  const press = key => (multi ? onChange(isOn(key) ? value.filter(k => k !== key) : [...(value || []), key]) : onChange(key));
  return (
    <div className="vmo-choice">
      {items.map(([key, label, disabled, note]) => (
        <button key={key} className={cx('chip', isOn(key) && 'on', disabled && 'is-off')} disabled={disabled} onClick={() => press(key)} aria-pressed={isOn(key)}>
          {multi && isOn(key) && <Icon name="check" size={13} weight={3} />}{label}{note && <small>{note}</small>}
        </button>
      ))}
    </div>
  );
}

// A pull-down like SwiftUI Menu, anchored under the control that opened it.
function VmoMenu({ menu, onClose }) {
  if (!menu) return null;
  return (
    <div className="overlay vmo-menu-layer" onClick={onClose}>
      <div className="menu glass vmo-menu" style={{ top: menu.top, ...(menu.right != null ? { right: menu.right } : { left: menu.left }) }} onClick={e => e.stopPropagation()} role="menu">
        {menu.items.map(it => (
          <button key={it.key} className="menu-item" role="menuitemradio" aria-checked={it.on} onClick={() => { onClose(); it.onPress(); }}>
            <span className="menu-check">{it.on && <Icon name="check" size={16} weight={2.6} />}</span>
            <span className="menu-label">{it.label}{it.sub && <small>{it.sub}</small>}</span>
          </button>
        ))}
      </div>
    </div>
  );
}

// Anchor a menu under an element, in the phone screen's own (unscaled) coordinates. `above` / `room` let a menu flip upward
// when it would run past the bottom of the screen.
function vmoAnchor(el, alignRight) {
  const screen = el.closest('.screen');
  const r = el.getBoundingClientRect();
  const s = screen.getBoundingClientRect();
  const k = s.width / screen.offsetWidth || 1;
  const top = (r.bottom - s.top) / k + 6;
  const extra = { above: (s.bottom - r.top) / k + 6, room: screen.offsetHeight };
  return alignRight ? { top, right: (s.right - r.right) / k, ...extra } : { top, left: Math.max(12, (r.left - s.left) / k), ...extra };
}

function VmoCodeBox({ ctx, code, big }) {
  const [shown, setShown] = useState(false);
  return (
    <div className={cx('vmo-codebox', big && 'is-big')}>
      <VmoCodeText code={code} shown={shown} className="vmo-codebox-text" />
      <button className="vmo-icon-btn" onClick={stop(() => setShown(v => !v))} aria-label={shown ? '隐藏兑换码' : '显示兑换码'}><VmoIcon name={shown ? 'eyeOff' : 'eye'} size={19} /></button>
      <button className="vmo-icon-btn" onClick={stop(() => vmoCopy(ctx, '兑换码'))} aria-label="复制兑换码"><VmoIcon name="copy" size={19} /></button>
    </div>
  );
}

function VmoCard({ id, open, onToggle, tone, lead, idle, head, children }) {
  return (
    <div data-vmo-card={id} className={cx('vmo-card', open && 'is-open', tone && tone !== 'none' && `tone-${tone} tone-rail`, idle && 'is-idle')}>
      <div className="vmo-card-head" role="button" tabIndex={0} aria-expanded={open} onClick={onToggle} onKeyDown={e => (e.key === 'Enter' || e.key === ' ') && onToggle()}>
        <span className="row-lead">{lead}</span>
        <div className="row-main">{head}</div>
        <span className="vmo-card-chev"><Icon name="chevronDown" size={14} weight={2.6} /></span>
      </div>
      {open && <div className="vmo-card-body">{children}</div>}
    </div>
  );
}

function VmoGone({ ctx, title }) {
  return <Screen ctx={ctx} nav={<NavBar ctx={ctx} back title={title} />}><div className="empty pad">已删除</div></Screen>;
}

/* ====================================================================== */
/* ---------- 兑换码 ---------- */

function vmoToggleCode(ctx, s, c) {
  const next = c.status === 'disabled' ? 'unused' : 'disabled';
  vmoPatch(s, 'codes', c.id, { status: next });
  ctx.showToast({ text: next === 'disabled' ? '已禁用 · 不能再兑换' : '已启用 · 可以兑换', icon: next === 'disabled' ? 'minus' : 'checkCircle', tone: next === 'disabled' ? 'neutral' : 'ok', undo: () => vmoPatch(s, 'codes', c.id, { status: c.status }) });
}

// Codes have no name and are shown masked, so the delete confirmation (core confirmDelete) asks for the last 4 characters — what
// the list shows — instead of a name, either case (codes are lower-case hex), or Face ID when the global setting is on.
// SwiftUI: .alert with TextField("末 4 位") (.textInputAutocapitalization(.never)) and the destructive button
// .disabled(text.lowercased() != last4). `typed` only seeds demo states.
// DELETE redeem-codes/:id has no status check: used codes can be deleted too (the user keeps what they redeemed).
function vmoConfirmDeleteCode(ctx, s, c, afterDelete, typed) {
  const tail = c.code.slice(-4);
  confirmDelete(ctx, '兑换码', `····${tail}`, afterDelete, {
    remove: () => vmoRemove(s, 'codes', c.id),
    message: `${VMO_TYPE[c.type].label} · ${vmoCodeValue(c)} · ${VMO_CODE_STATUS[c.status].label}`,
    match: tail, label: '输入末 4 位确认删除', placeholder: '末 4 位', caseInsensitive: true,
    ...(typed !== undefined ? { typed } : {}),
  });
}

// ⋯ of one code (a Menu, never a confirm): on the detail page (base) it carries everything; on an open inline card the visible
// buttons (禁用 / 编辑 / 续期) are not repeated. Delete is last and red.
function vmoCodeMenu(ctx, s, c, afterDelete, inline) {
  const actions = [];
  if (!inline) actions.push({ label: c.status === 'used' ? '编辑备注' : c.status === 'expired' ? '续期…' : '编辑兑换码', role: 'default', onPress: () => ctx.openSheet({ kind: 'redeemEdit', id: c.id }) });
  actions.push({ label: '复制兑换码', role: 'default', onPress: () => vmoCopy(ctx, '兑换码') });
  if (c.usedBy && vmoUser(c.usedBy)) actions.push({ label: `查看使用者 ${vmoUserName(c.usedBy)}`, role: 'default', onPress: () => ctx.push({ kind: 'user', id: c.usedBy }) });
  if (!inline && (c.status === 'unused' || c.status === 'disabled')) actions.push({ label: c.status === 'disabled' ? '启用' : '禁用', role: 'default', onPress: () => vmoToggleCode(ctx, s, c) });
  actions.push({ label: '删除兑换码…', role: 'destructive', onPress: () => vmoConfirmDeleteCode(ctx, s, c, afterDelete) });
  return { title: vmoShort(c.code), message: `${VMO_TYPE[c.type].label} · ${vmoCodeValue(c)} · ${VMO_CODE_STATUS[c.status].label}`, actions };
}

function vmoCodeChips(codes, type) {
  const n = k => codes.filter(c => c.status === k).length;
  return [
    { key: 'all', label: '全部', count: codes.length },
    { key: 'unused', label: '未使用', count: n('unused') },
    { key: 'used', label: '已使用', count: n('used') },
    { key: 'expired', label: '已过期', count: n('expired') },
    { key: 'disabled', label: '已禁用', count: n('disabled') },
    { key: 'type', label: type === 'all' ? '类型' : VMO_TYPE[type].label, menu: true },
  ];
}

// Mirrors GET redeem-codes?search=: the code contains the text (case-insensitive) or the user who used it has a matching email.
function vmoCodeMatches(c, key) {
  if (!key) return true;
  const u = c.usedBy ? vmoUser(c.usedBy) : null;
  return c.code.toLowerCase().includes(key) || Boolean(u && u.email.toLowerCase().includes(key));
}

// SwiftUI: .searchable on the list. The clear button is the field's own ✕.
function VmoSearchField({ value, onChange, placeholder }) {
  return (
    <label className="search-field vmo-search">
      <Icon name="search" size={16} />
      <input value={value} placeholder={placeholder} onChange={e => onChange(e.target.value)} aria-label={placeholder} />
      {value && <button className="vmo-search-clear" onClick={e => { e.preventDefault(); onChange(''); }} aria-label="清除搜索"><Icon name="close" size={11} weight={3} /></button>}
    </label>
  );
}

// Search + status chips + a 类型 pull-down (SwiftUI: a Menu with a Picker inside). Chip counts follow the search.
function useVmoCodeFilter(ctx, route, codes) {
  const [filter, setFilter] = useState(route.filter || 'all');
  const [type, setType] = useState(route.type || 'all');
  const [q, setQ] = useState(route.q || '');
  const [menu, setMenu] = useState(null);
  const key = q.trim().toLowerCase();
  const found = codes.filter(c => vmoCodeMatches(c, key));
  const rows = found.filter(c => (filter === 'all' || c.status === filter) && (type === 'all' || c.type === type));
  const openMenu = el => setMenu({
    ...vmoAnchor(el, true),
    items: [['all', '全部类型'], ...Object.entries(VMO_TYPE).map(([k, t]) => [k, t.label])].map(([k, label]) => ({ key: k, label, on: type === k, onPress: () => setType(k) })),
  });
  const chips = (
    <div className={cx('vmo-chips', type !== 'all' && 'has-type')} onClickCapture={e => { const b = e.target.closest('.chip'); if (b && b === b.parentNode.lastElementChild) { e.stopPropagation(); openMenu(b); } }}>
      <Chips items={vmoCodeChips(found, type)} value={filter} onChange={k => k !== 'type' && setFilter(k)} />
    </div>
  );
  const search = <VmoSearchField value={q} onChange={setQ} placeholder="搜索兑换码或邮箱" />;
  // same empty state as the filtered usage records (core LogsScreen): dash, sentence, one way out
  const empty = rows.length === 0 && (
    <div className="lg-empty pad">
      <b className="num lg-empty-dash" aria-hidden="true">—</b>
      <span>{key ? `没有匹配“${q.trim()}”的兑换码` : '没有这类兑换码'}</span>
      {key && <button className="lg-empty-clear" onClick={() => setQ('')}>清除搜索</button>}
    </div>
  );
  return { rows, chips, search, empty, menu: <VmoMenu menu={menu} onClose={() => setMenu(null)} /> };
}

/* ---------- 生成结果待核对（ctx.redeemPending） ---------- */

// ctx.redeemPending = {count, total, ago} (core reads these) plus what this file needs to rebuild the batch: spec, key, at.
// A record seeded from initial.redeemPending only has count / total / ago, so it stands for a balance batch.
function vmoPendingSpec(rp) {
  if (rp.spec) return rp.spec;
  const each = rp.total != null && rp.count ? Math.round((rp.total / rp.count) * 100) / 100 : 0;
  return { ...VMO_GEN_DEFAULT, type: 'balance', value: String(each), count: rp.count || 1 };
}
const vmoPendingKey = rp => rp.key || vmoIdemKey(vmoPendingSpec(rp));
// [what, when]: "20 个 × $10.00 · 合计 $200.00", "5 分钟前发起"
function vmoPendingLines(rp) {
  const spec = vmoPendingSpec(rp);
  const sum = vmoGenSummary(spec);
  return [`${spec.count} 个 × ${sum.each}${sum.total !== null ? ` · 合计 ${fmt.money(sum.total)}` : ''}`, `${rp.ago}发起`];
}
const vmoPendingRecord = (spec, key) => ({ count: spec.count, total: vmoGenSummary(spec).total, ago: '刚刚', at: VMO_NOW, key, spec });

// 核对 = list the codes created since the request and look for this batch. In the demo the server did create it
// (like reconcileUser), unless the record says found: false — then the sheet offers 用同一编号重试 / 放弃.
function vmoReconcile(ctx, s, rp) {
  if (s.data.busy.reconcile) return;
  vmoBusy(s, 'reconcile', true);
  setTimeout(() => {
    vmoBusy(s, 'reconcile', false);
    if (rp.found === false) { ctx.openSheet({ kind: 'redeemReconcile', missing: true }); return; }
    const spec = vmoPendingSpec(rp);
    const fresh = vmoMakeCodes(s, spec, vmoGenSummary(spec), rp.at || '10/16 09:36');
    vmoSet(s, 'codes', list => [...fresh, ...list]);
    ctx.setRedeemPending(null);
    ctx.openSheet({ kind: 'redeemReconcile', ids: fresh.map(c => c.id) });
  }, 900);
}

// Shown on the list whenever a batch is unresolved; 概览 → 待处理 lands here ({kind:'redeem', reconcile:true}).
function VmoPendingBanner({ ctx, s, focus }) {
  const rp = ctx.redeemPending;
  if (!rp) return null;
  const busy = Boolean(s.data.busy.reconcile);
  const [what, when] = vmoPendingLines(rp);
  return (
    <div className={cx('banner vmo-banner vmo-banner-wrap tone-caution', ctx.skin.rowClass('caution'), focus && 'is-focus')} role="status">
      <Icon name="docCheck" size={18} />
      <div className="banner-text"><b>兑换码生成结果待核对</b><span className="num">{what}</span><span>{when}，未确认是否已生成</span></div>
      <VmoAct small primary={focus} label={busy ? '核对中…' : '核对'} disabled={busy} onClick={() => vmoReconcile(ctx, s, rp)} />
    </div>
  );
}

// A batch whose result never came back is checked before a new one starts (same rule as a pending top-up).
function vmoOpenGenerate(ctx, s) {
  const rp = ctx.redeemPending;
  if (!rp) { ctx.openSheet({ kind: 'redeemGenerate' }); return; }
  const [what, when] = vmoPendingLines(rp);
  ctx.confirm({
    title: '上一批兑换码的生成结果未确认',
    message: `${what}\n${when}。先核对，避免重复生成。`,
    actions: [
      { label: '先核对', role: 'default', onPress: () => vmoReconcile(ctx, s, rp) },
      { label: '仍要生成新的一批', onPress: () => ctx.openSheet({ kind: 'redeemGenerate' }) },
      { label: '取消', role: 'cancel' },
    ],
  });
}

function VmoRedeemNav({ ctx, s, count }) {
  return <NavBar ctx={ctx} back title="兑换码" subtitle={`${ctx.site} · ${count} 个`} trailing={<GlassButton icon="plus" onClick={() => vmoOpenGenerate(ctx, s)} />} />;
}

function VmoCodeRow({ ctx, c }) {
  const st = VMO_CODE_STATUS[c.status];
  return (
    <Row skin={ctx.skin} tone="none" className={cx(c.status !== 'unused' && 'is-idle')} onClick={() => ctx.push({ kind: 'redeemDetail', id: c.id })}
      lead={<span className="lead-icon dim"><Icon name={VMO_TYPE[c.type].icon} /></span>}>
      <div className="row-top"><span className="row-title mono vmo-code-title">{vmoShort(c.code)}</span><span className={cx('row-right num vmo-val', c.type === 'invitation' && 'dim')}>{vmoCodeValue(c)}</span></div>
      <div className="row-foot"><span className="row-meta vmo-ellip">{vmoCodeLine(c)}</span><VmoBadge {...st} /></div>
    </Row>
  );
}

// base: plain list → detail page
function VmoRedeemList({ ctx, route }) {
  const s = useVmo(ctx);
  const codes = s.data.codes;
  const { rows, chips, search, empty, menu } = useVmoCodeFilter(ctx, route, codes);
  return (
    <Screen plain ctx={ctx} nav={<VmoRedeemNav ctx={ctx} s={s} count={codes.length} />}>
      <VmoPendingBanner ctx={ctx} s={s} focus={route.reconcile} />
      {search}
      {chips}
      {vmoGroupByDay(rows).map(([title, list]) => (
        <div key={title} className="list-group">
          <div className="list-head"><span>{title}生成</span><b className="num">{list.length}</b></div>
          {list.map(c => <VmoCodeRow key={c.id} ctx={ctx} c={c} />)}
        </div>
      ))}
      {empty}
      {menu}
    </Screen>
  );
}

function VmoTicket({ ctx, c }) {
  const st = VMO_CODE_STATUS[c.status];
  const t = VMO_TYPE[c.type];
  const figure = c.type === 'balance' ? fmt.money(c.value) : c.type === 'concurrency' ? `+${c.value}` : c.type === 'subscription' ? `${c.days} 天` : '邀请';
  const sub = c.type === 'balance' ? '兑换后计入余额' : c.type === 'concurrency' ? '并发数增量' : c.type === 'subscription' ? `${c.group} · 开通或延长` : '注册时填写，用过即失效';
  return (
    <div className={cx('vmo-ticket', `is-${c.status}`)}>
      <div className="vmo-ticket-top">
        <span className="vmo-ticket-type"><Icon name={t.icon} size={15} weight={2.2} />{c.type === 'invitation' ? '邀请码' : `${t.label}兑换码`}</span>
        <VmoBadge {...st} />
      </div>
      <div className="vmo-ticket-value num">{figure}</div>
      <div className="vmo-ticket-sub">{sub}</div>
      <div className="vmo-perf" aria-hidden="true" />
      <VmoCodeBox ctx={ctx} code={c.code} big />
    </div>
  );
}

// 过期时间 with what it means today: "10/23 09:12 · 还剩 7 天" for a live code, "（已过期）" for an expired one.
function vmoExpiryValue(c) {
  if (!c.expiresAt) return '永不过期';
  const d = vmoStampDays(c.expiresAt);
  const tail = c.status === 'expired' ? '已过期' : c.status === 'unused' || c.status === 'disabled' ? (d <= 0 ? '今天到期' : `还剩 ${d} 天`) : null;
  return <><span className="num">{c.expiresAt}</span>{tail && <small className={cx('vmo-kv-sub', c.status === 'unused' && d <= 1 && 'tone-caution tone-text')}>{tail}</small>}</>;
}

// 使用与有效期: who / when only once the code is used (an unused code has nothing to show there), then 生成 / 过期,
// and for subscription codes the group and days. SwiftUI: LabeledContent rows in the card's Section.
function VmoCodeFacts({ ctx, c, inline }) {
  const u = c.usedBy ? vmoUser(c.usedBy) : null;
  const used = c.status === 'used';
  return (
    <div className={cx('kv-grid', !inline && 'pad', inline && 'vmo-code-facts')}>
      {(used || !inline) && <>
        <KV label="使用者" value={c.usedBy ? vmoUserName(c.usedBy) : '—'} onClick={u ? () => ctx.push({ kind: 'user', id: u.id }) : undefined} />
        <KV label="使用时间" value={c.usedAt ? <span className="num">{c.usedAt}</span> : '—'} />
      </>}
      <KV label="生成时间" value={<span className="num">{c.createdAt}</span>} />
      <KV label="过期时间" value={vmoExpiryValue(c)} />
      {c.type === 'subscription' && <><KV label="订阅分组" value={c.group} /><KV label="有效天数" value={`${c.days} 天`} /></>}
    </div>
  );
}

function VmoRedeemDetail({ ctx, route }) {
  const s = useVmo(ctx);
  const { skin } = ctx;
  const c = s.data.codes.find(x => x.id === route.id);
  if (!c) return <VmoGone ctx={ctx} title="兑换码" />;
  const toggleable = c.status === 'unused' || c.status === 'disabled';
  return (
    <Screen ctx={ctx} nav={<NavBar ctx={ctx} back title="兑换码" subtitle={`#${c.id} · ${VMO_TYPE[c.type].label}`} trailing={<GlassButton icon="more" onClick={() => ctx.menu(vmoCodeMenu(ctx, s, c, ctx.pop))} />} />}>
      <div className="detail-head">
        <VmoTicket ctx={ctx} c={c} />
        <div className="actions">
          <VmoAct label="复制" icon="copy" primary onClick={() => vmoCopy(ctx, '兑换码')} />
          {toggleable && <VmoAct label={c.status === 'disabled' ? '启用' : '禁用'} icon={c.status === 'disabled' ? 'play' : 'minus'} onClick={() => vmoToggleCode(ctx, s, c)} />}
          <VmoAct label={c.status === 'used' ? '备注' : c.status === 'expired' ? '续期' : '编辑'} icon={c.status === 'expired' ? 'restore' : 'compose'} onClick={() => ctx.openSheet({ kind: 'redeemEdit', id: c.id })} />
        </div>
      </div>
      <Section skin={skin} title="使用与有效期" index="壹"><VmoCodeFacts ctx={ctx} c={c} /></Section>
      <Section skin={skin} title="备注" index="贰"><div className={cx('vmo-note-text pad', !c.notes && 'dim')}>{c.notes || '没有备注'}</div></Section>
    </Screen>
  );
}

// Bring an opened card fully into view (SwiftUI: ScrollViewReader.scrollTo(id, anchor: nil) after the expand animation).
// The floating tab bar covers the bottom of the scroll area, so that strip doesn't count as visible. `from` is any element in
// this phone's list, so the lookup stays inside one phone when the page shows several.
const VMO_TABBAR_CLEAR = 104;
function vmoRevealCard(from, id) {
  requestAnimationFrame(() => {
    const box = from && from.closest('.scroll');
    const el = box && box.querySelector(`[data-vmo-card="${id}"]`);
    if (!el) return;
    const r = el.getBoundingClientRect();
    const b = box.getBoundingClientRect();
    const k = b.height / box.clientHeight || 1; // the phone is drawn scaled
    const over = (r.bottom - (b.bottom - VMO_TABBAR_CLEAR * k)) / k;
    const room = (r.top - b.top) / k - 8;
    if (over > 0) box.scrollBy({ top: Math.min(over, Math.max(0, room)), behavior: 'smooth' });
  });
}

// The buttons under an open card, by status (see the header comment). 续期 opens the edit sheet, where a new expiry also
// sends status = unused.
function VmoCodeActions({ ctx, s, c, onDeleted }) {
  return (
    <div className="vmo-card-actions">
      {(c.status === 'unused' || c.status === 'disabled') && <VmoAct label={c.status === 'disabled' ? '启用' : '禁用'} icon={c.status === 'disabled' ? 'play' : 'minus'} onClick={() => vmoToggleCode(ctx, s, c)} />}
      {c.status === 'expired'
        ? <VmoAct label="续期" icon="restore" primary onClick={() => ctx.openSheet({ kind: 'redeemEdit', id: c.id })} />
        : <VmoAct label={c.status === 'used' ? '编辑备注' : '编辑'} icon="compose" onClick={() => ctx.openSheet({ kind: 'redeemEdit', id: c.id })} />}
      <VmoMoreBtn menu={() => vmoCodeMenu(ctx, s, c, onDeleted, true)} />
    </div>
  );
}

// inline (decided): cards expand in place, no second-level page. SwiftUI: each card is its own Section (.listSectionSpacing(.compact)),
// the header row toggles @State openID (one open at a time); buttons inside use .buttonStyle(.borderless) so taps don't hit the
// whole row. Collapsed cards carry the swipe actions described in the header comment.
// route: {kind:'redeem', open?, q?, filter?, type?, reconcile?} plus demo seeds del (id: open the delete alert) and typed.
function VmoRedeemInline({ ctx, route }) {
  const s = useVmo(ctx);
  const [open, setOpen] = useState(route.open ?? null);
  const anchor = useRef(null);
  const codes = s.data.codes;
  const { rows, chips, search, empty, menu } = useVmoCodeFilter(ctx, route, codes);
  const toggle = id => {
    const next = open === id ? null : id;
    setOpen(next);
    if (next !== null) vmoRevealCard(anchor.current, next);
  };
  useEffect(() => {
    if (route.open) vmoRevealCard(anchor.current, route.open); // e.g. 补偿回执 → 查看兑换码
    const c = route.del ? codes.find(x => x.id === route.del) : null;
    if (c) vmoConfirmDeleteCode(ctx, s, c, () => setOpen(null), route.typed);
  }, []);
  return (
    <Screen ctx={ctx} nav={<VmoRedeemNav ctx={ctx} s={s} count={codes.length} />}>
      <i ref={anchor} hidden />
      <VmoPendingBanner ctx={ctx} s={s} focus={route.reconcile} />
      {search}
      {chips}
      {vmoGroupByDay(rows).map(([title, list]) => (
        <div key={title} className="vmo-cards">
          <div className="vmo-cards-head"><span>{title}生成</span><b className="num">{list.length}</b></div>
          {list.map(c => {
            const isOpen = open === c.id;
            return (
              <VmoCard key={c.id} id={c.id} open={isOpen} onToggle={() => toggle(c.id)} idle={c.status !== 'unused'}
                lead={<span className="lead-icon dim"><Icon name={VMO_TYPE[c.type].icon} /></span>}
                head={<>
                  <div className="row-top"><span className="row-title mono vmo-code-title">{vmoShort(c.code)}</span><span className={cx('row-right num vmo-val', c.type === 'invitation' && 'dim')}>{vmoCodeValue(c)}</span></div>
                  <div className="row-foot"><span className="row-meta vmo-ellip">{vmoCodeLine(c)}</span><VmoBadge {...VMO_CODE_STATUS[c.status]} /></div>
                </>}>
                <VmoCodeBox ctx={ctx} code={c.code} />
                <VmoCodeFacts ctx={ctx} c={c} inline />
                <div className="vmo-note-inline"><small>备注</small><span className={cx(!c.notes && 'dim')}>{c.notes || '—'}</span></div>
                <VmoCodeActions ctx={ctx} s={s} c={c} onDeleted={() => setOpen(null)} />
              </VmoCard>
            );
          })}
        </div>
      ))}
      {empty}
      {menu}
    </Screen>
  );
}

function VmoReadonlyRow({ label, value }) {
  return <div className="vmo-frow"><span className="vmo-flabel">{label}</span><span className="vmo-fvalue vmo-ro">{value}</span></div>;
}

// batch-update rules: status only unused/disabled; expires_at must be in the future; a used code rejects any change to
// status / expires_at / group_id (REDEEM_CODE_USED), so a used code can only get new notes. An expired code is renewed:
// a new expiry (or 永不过期 = expires_at null) is sent together with status = unused; saving it with 保持 only changes the notes.
// SwiftUI: Form in a sheet; 自定义 = DatePicker(in: Date()...) for date and time.
const VMO_EDIT_EXPIRY = [['never', '永不过期'], ['1', '1 天'], ['3', '3 天'], ['7', '7 天'], ['30', '30 天'], ['custom', '自定义']];

function vmoEditExpiresAt(c, expiry, customAt) {
  if (expiry === 'keep') return c.expiresAt;
  if (expiry === 'never') return null;
  if (expiry === 'custom') return vmoStamp(customAt);
  return vmoAddDays(Number(expiry));
}

function VmoRedeemEdit({ ctx, sheet }) {
  const s = useVmo(ctx);
  const c = s.data.codes.find(x => x.id === sheet.id);
  const [status, setStatus] = useState(c ? c.status : 'unused');
  const [expiry, setExpiry] = useState(sheet.expiry || (c && c.expiresAt ? 'keep' : 'never'));
  const [customAt, setCustomAt] = useState('2026-10-23T23:59');
  const [group, setGroup] = useState(c ? c.group : null);
  const [notes, setNotes] = useState(c ? c.notes || '' : '');
  if (!c) return null;
  const used = c.status === 'used';
  const expired = c.status === 'expired';
  const toggleable = c.status === 'unused' || c.status === 'disabled';
  const renewing = expired && expiry !== 'keep';
  const customOk = expiry !== 'custom' || customAt > VMO_NOW_ISO;
  const keepLabel = c.expiresAt ? `保持 ${c.expiresAt}${expired ? '（已过期）' : ''}` : null;
  const expiryItems = [...(keepLabel ? [['keep', keepLabel]] : []), ...VMO_EDIT_EXPIRY];
  const nextAt = vmoEditExpiresAt(c, expiry, customAt);
  const save = () => {
    if (!customOk) return;
    if (used) {
      vmoPatch(s, 'codes', c.id, { notes: notes.trim() });
    } else {
      const nextStatus = toggleable ? status : renewing ? 'unused' : c.status;
      vmoPatch(s, 'codes', c.id, { status: nextStatus, expiresAt: nextAt, notes: notes.trim(), group: c.type === 'subscription' ? group : c.group });
    }
    ctx.closeSheet();
    ctx.showToast({ text: renewing ? `已续期 · ${nextAt ? `${vmoDay(nextAt)} 过期` : '永不过期'}，改回未使用` : used ? '已保存备注' : '已保存兑换码' });
  };
  const expirySec = !used && (
    <VmoFsec key="expiry" title={expired ? '新的过期时间' : '过期时间'}
      foot={!customOk ? '过期时间要晚于现在。' : expired ? (renewing ? `保存后 ${nextAt ? `${nextAt} 过期` : '永不过期'}，状态改回“未使用”。` : '选一个新的过期时间即可续期；保持原时间只改备注。') : '从现在算起；永不过期 = 一直可兑换。'}>
      <div className="vmo-frow vmo-frow-full"><VmoChoice items={expiryItems} value={expiry} onChange={setExpiry} /></div>
      {expiry === 'custom' && <div className="vmo-frow"><span className="vmo-flabel">过期于</span><span className="vmo-fill" /><VmoDateTime value={customAt} onChange={setCustomAt} label="过期于" /></div>}
    </VmoFsec>
  );
  const statusSec = !used && (
    <VmoFsec key="status" title="状态" foot={toggleable ? '禁用后不能再兑换，可以随时重新启用。' : null}>
      {toggleable
        ? <div className="vmo-frow vmo-frow-full"><Segmented items={[{ key: 'unused', label: '未使用' }, { key: 'disabled', label: '已禁用' }]} value={status} onChange={setStatus} /></div>
        : <VmoReadonlyRow label="状态" value={renewing ? <>已过期 <Icon name="arrowRight" size={13} weight={2.4} /> <b>未使用</b></> : '已过期'} />}
    </VmoFsec>
  );
  const groupSec = !used && c.type === 'subscription' && (
    <VmoFsec key="group" title="订阅分组"><div className="vmo-frow vmo-frow-full"><VmoChoice items={VMO_SUB_GROUPS.map(g => [g, g])} value={group} onChange={setGroup} /></div></VmoFsec>
  );
  // renewing is the job at hand for an expired code, so its expiry comes first
  const order = expired ? [expirySec, statusSec, groupSec] : [statusSec, groupSec, expirySec];
  return (
    <VmoSheet title={used ? '编辑备注' : expired ? '续期兑换码' : '编辑兑换码'} leading={{ label: '取消', onPress: ctx.closeSheet }} onDismiss={ctx.closeSheet}
      trailing={<VmoBarBtn label={renewing ? '续期' : '保存'} onClick={save} disabled={!customOk} />}>
      <div className="vmo-sheet-target"><span className="mono">{vmoShort(c.code)}</span><small>{VMO_TYPE[c.type].label} · {vmoCodeValue(c)} · 面值生成后不能改</small></div>
      {used && (
        <div className="vmo-note-banner"><Icon name="check" size={15} weight={2.6} /><span>已使用的兑换码只能改备注。<small>使用者 {vmoUserName(c.usedBy)} · {c.usedAt}</small></span></div>
      )}
      {used && (
        <VmoFsec title="兑换码">
          <VmoReadonlyRow label="状态" value="已使用" />
          {c.type === 'subscription' && <VmoReadonlyRow label="订阅分组" value={c.group} />}
          <VmoReadonlyRow label="过期时间" value={c.expiresAt || '永不过期'} />
        </VmoFsec>
      )}
      {order}
      <VmoFsec title="备注" foot="只有管理员看得到。">
        <textarea className="vmo-textarea vmo-textarea-s" value={notes} placeholder="例如：活动批次、工单号" aria-label="备注" onChange={e => setNotes(e.target.value)} />
      </VmoFsec>
    </VmoSheet>
  );
}

/* ---------- 批量生成兑换码 ---------- */

// Web defaults: count 1, subscription validity 30 days (free number input).
const VMO_GEN_DEFAULT = { type: 'balance', value: '', conc: 1, group: VMO_SUB, days: 30, customSubDays: '', count: 1, expiry: 'never', customDays: '', sim: '' };
const VMO_SUB_DAYS = [[7, '7 天'], [30, '30 天'], [90, '90 天'], ['custom', '自定义']];
const VMO_COUNT_PICKS = [1, 10, 20, 50, 100];

function vmoGenSpec(sheet) {
  return { ...VMO_GEN_DEFAULT, ...Object.fromEntries(Object.entries(sheet).filter(([k]) => k in VMO_GEN_DEFAULT)) };
}

const vmoSubDays = spec => (spec.days === 'custom' ? Number(spec.customSubDays) || 0 : spec.days);

function vmoGenSummary(spec) {
  const days = spec.expiry === 'never' ? null : spec.expiry === 'custom' ? Number(spec.customDays) || null : Number(spec.expiry);
  const subDays = vmoSubDays(spec);
  const each = spec.type === 'balance' ? fmt.money(Number(spec.value) || 0) : spec.type === 'concurrency' ? `+${spec.conc} 并发` : spec.type === 'subscription' ? `${spec.group} · ${subDays || '—'} 天` : '注册邀请';
  const total = spec.type === 'balance' ? (Number(spec.value) || 0) * spec.count : null;
  const expiry = days ? `${days} 天后过期（${vmoAddDays(days).split(' ')[0]}）` : '永不过期';
  const valid = spec.count >= 1 && spec.count <= 100
    && (spec.type !== 'balance' || Number(spec.value) > 0)
    && (spec.type !== 'subscription' || (spec.group && subDays >= 1 && subDays <= 3650))
    && (spec.expiry !== 'custom' || (Number(spec.customDays) >= 1 && Number(spec.customDays) <= 3650));
  return { each, total, expiry, days, valid };
}

// One idempotency key per generate attempt, kept on the device until the result is known (same rule as balance changes),
// so 用同一编号重试 can never create a second batch.
const vmoIdemKey = spec => `gen-${vmoNewCode(spec.count * 977 + (Number(spec.value) || 3) * 31).slice(0, 12)}`;

function vmoMakeCodes(s, spec, sum, at = VMO_NOW) {
  const base = Math.max(...s.data.codes.map(c => c.id)) + 1;
  return Array.from({ length: spec.count }, (_, i) => ({
    id: base + i, code: vmoNewCode(base * 31 + i * 7 + spec.count), type: spec.type, status: 'unused', createdAt: at,
    expiresAt: sum.days ? vmoAddDays(sum.days) : null, notes: '',
    ...(spec.type === 'balance' ? { value: Number(spec.value) } : spec.type === 'concurrency' ? { value: spec.conc } : spec.type === 'subscription' ? { group: spec.group, days: vmoSubDays(spec) } : {}),
  })).reverse();
}

// Generating balance codes creates money: confirm with site, count, face value and total (destructive role, like top-ups).
// Above the Face ID threshold (global setting ctx.faceId, core's FACE_ID_LIMIT) the confirm is followed by Face ID.
// `phase` drives the sheet: 'faceid' → (result | 'pending'). The demo's sim = 'timeout' stands for "request sent, no answer";
// the pending view itself records ctx.redeemPending so 概览 → 待处理 shows it.
function vmoConfirmGen(ctx, s, spec, setPhase) {
  const sum = vmoGenSummary(spec);
  const money = spec.type === 'balance';
  const label = VMO_TYPE[spec.type].label;
  const face = money && vmoNeedsFace(ctx, sum.total);
  const run = () => {
    if (spec.sim === 'timeout') { setPhase({ kind: 'pending', key: vmoIdemKey(spec) }); return; }
    const fresh = vmoMakeCodes(s, spec, sum);
    vmoSet(s, 'codes', list => [...fresh, ...list]);
    setPhase({ kind: 'done', codes: fresh });
  };
  ctx.confirm({
    title: money ? `生成 ${spec.count} 个余额兑换码，合计 ${fmt.money(sum.total)}？` : `生成 ${spec.count} 个${label}兑换码？`,
    message: `站点 ${ctx.site} · 每个 ${sum.each}\n${sum.expiry}${face ? `\n${vmoFaceLine('合计')}` : ''}`,
    actions: [
      { label: money ? `生成 ${fmt.money(sum.total)}` : `生成 ${spec.count} 个`, role: money ? 'destructive' : 'default', onPress: () => {
        if (!face) { run(); return; }
        setPhase({ kind: 'faceid' });
        setTimeout(run, 1100);
      } },
      { label: '取消', role: 'cancel' },
    ],
  });
}

function VmoFaceId({ text = '验证后生成兑换码' }) {
  return (
    <div className="vmo-faceid" role="status" aria-live="polite">
      <span className="vmo-faceid-glyph" aria-hidden="true">
        <svg width="54" height="54" viewBox="0 0 54 54" fill="none" stroke="currentColor" strokeWidth="2.6" strokeLinecap="round">
          <path d="M4 16V9a5 5 0 0 1 5-5h7M38 4h7a5 5 0 0 1 5 5v7M50 38v7a5 5 0 0 1-5 5h-7M16 50H9a5 5 0 0 1-5-5v-7" />
          <path d="M19 20v4M35 20v4M27 21v9h-3M20 37c4 3.5 10 3.5 14 0" />
        </svg>
      </span>
      <b>Face ID</b>
      <span>{text}</span>
    </div>
  );
}

// One line under the headline, from the codes themselves (works for a batch rebuilt by 核对 too).
function vmoBatchLine(codes) {
  const c = codes[0];
  return `${VMO_TYPE[c.type].label} · 每个 ${vmoCodeValue(c)}${c.type === 'subscription' ? `（${c.group}）` : ''} · ${c.expiresAt ? `${vmoDay(c.expiresAt)} 过期` : '永不过期'}`;
}

function VmoGenResult({ ctx, codes, title = '生成结果', headline, foot }) {
  const [copied, setCopied] = useState(null);
  return (
    <VmoSheet tall title={title} leading={{ label: '完成', onPress: ctx.closeSheet }} onDismiss={ctx.closeSheet}>
      <div className="vmo-done tone-ok">
        <span className="vmo-done-icon"><Icon name="checkCircle" size={26} weight={2.2} /></span>
        <b>{headline || `已生成 ${codes.length} 个兑换码`}</b>
        <span>{vmoBatchLine(codes)}</span>
      </div>
      <button className={cx('submit vmo-copyall', copied === 'all' && 'is-done')} onClick={() => setCopied('all')}>
        {copied === 'all' ? <><Icon name="check" size={18} weight={2.8} />已复制全部 {codes.length} 个</> : <><VmoIcon name="copy" size={18} weight={2.2} />{codes.length > 1 ? `全部复制（${codes.length} 个，每行一个）` : '复制兑换码'}</>}
      </button>
      <div className="vmo-codelist">
        {codes.map((c, i) => (
          <div key={c.id} className="vmo-codeline">
            <span className="num vmo-codeline-no">{i + 1}</span>
            <VmoCodeText code={c.code} className="vmo-codeline-text" />
            <button className="vmo-icon-btn" onClick={() => setCopied(c.id)} aria-label={`复制第 ${i + 1} 个`}>{copied === c.id ? <Icon name="check" size={17} weight={2.8} /> : <VmoIcon name="copy" size={17} />}</button>
          </div>
        ))}
      </div>
      <div className="vmo-fsec-foot">{foot || '关闭后在列表的“今天生成”里能找到它们；导出 CSV 请在 Web 操作。'}</div>
    </VmoSheet>
  );
}

// The request may or may not have reached the server (timeout / app sent to background). Never offer a fresh "生成":
// 核对 lists what the server created since the request; 用同一编号重试 re-sends with the same idempotency key, so a batch the
// server already made comes back instead of a second one. Until one of them succeeds the record stays in ctx.redeemPending
// (概览 → 待处理, and the banner on the list). `missing` = 核对 found nothing, so the choices are 重试 or 放弃.
function VmoGenPending({ ctx, s, spec, idemKey, at = VMO_NOW, missing, onResolved }) {
  const sum = vmoGenSummary(spec);
  const [busy, setBusy] = useState(null);
  useEffect(() => { if (!ctx.redeemPending && !missing) ctx.setRedeemPending(vmoPendingRecord(spec, idemKey)); }, []);
  // core keeps one record; only clear it when it is this batch (an older unresolved batch keeps its reminder)
  const isMine = missing || !ctx.redeemPending || ctx.redeemPending.key === idemKey;
  const resolve = how => {
    setBusy(how);
    setTimeout(() => {
      const fresh = vmoMakeCodes(s, spec, sum, at);
      vmoSet(s, 'codes', list => [...fresh, ...list]);
      if (isMine) ctx.setRedeemPending(null);
      onResolved(fresh, how);
    }, 900);
  };
  const giveUp = () => {
    ctx.setRedeemPending(null);
    ctx.closeSheet();
    ctx.showToast({ text: '已放弃这一批 · 不再提醒', icon: 'close', tone: 'neutral' });
  };
  return (
    <VmoSheet tall title={missing ? '核对结果' : '结果待核对'} leading={{ label: '关闭', onPress: ctx.closeSheet }} onDismiss={ctx.closeSheet}>
      <div className="vmo-done tone-caution">
        <span className="vmo-done-icon"><Icon name={missing ? 'search' : 'hourglass'} size={26} weight={2.2} /></span>
        <b>{missing ? '服务器上没有这一批' : '请求可能已提交'}</b>
        <span>{missing ? '这次生成没有生效。用同一编号重试，或者放弃。' : '没有收到服务器确认。不要重新生成，先核对。'}</span>
      </div>
      <div className="vmo-receipt">
        <div><span>内容</span><b className="num">{spec.count} 个 × {sum.each}</b></div>
        {sum.total !== null && <div><span>合计</span><b className="num">{fmt.money(sum.total)}</b></div>}
        <div><span>发起</span><b>{ctx.site} · <span className="num">{at}</span></b></div>
        <div><span>幂等编号</span><b className="mono">{idemKey}</b></div>
      </div>
      <div className="vmo-pending-acts">
        {missing ? (
          <>
            <button className="submit" disabled={Boolean(busy)} onClick={() => resolve('retry')}>{busy ? '正在用同一编号重试…' : '用同一编号重试'}</button>
            <button className="act" disabled={Boolean(busy)} onClick={giveUp}>放弃这一批</button>
          </>
        ) : (
          <>
            <button className="submit" disabled={Boolean(busy)} onClick={() => resolve('check')}>{busy === 'check' ? '正在核对…' : '核对生成结果'}</button>
            <button className="act" disabled={Boolean(busy)} onClick={() => resolve('retry')}>{busy === 'retry' ? '正在用同一编号重试…' : '用同一编号重试'}</button>
          </>
        )}
      </div>
      <div className="vmo-fsec-foot">{missing
        ? '重试用的是本机保存的同一个编号，服务器最多生成一批。'
        : '编号已保存在本机。核对会按发起时间在服务器列表里找这一批；用同一编号重试时，服务器生成过就直接返回那一批，不会重复生成。关闭后，概览“待处理”和兑换码列表顶部会一直提醒，直到核对完成。'}</div>
    </VmoSheet>
  );
}

const vmoResolvedHeadline = (codes, how) => (how === 'check' ? `已核对：服务器已生成 ${codes.length} 个` : null);

// Shared tail of both generate sheets: Face ID → result / 待核对.
function VmoGenPhase({ ctx, s, spec, phase, setPhase }) {
  if (phase.kind === 'done') return <VmoGenResult ctx={ctx} codes={phase.codes} headline={vmoResolvedHeadline(phase.codes, phase.how)} />;
  if (phase.kind === 'pending') return <VmoGenPending ctx={ctx} s={s} spec={spec} idemKey={phase.key} onResolved={(codes, how) => setPhase({ kind: 'done', codes, how })} />;
  return null;
}

// 概览 → 待处理 → 核对 (or the banner on the list) ends here: the batch the server made, or — when it made none — 重试 / 放弃.
function VmoReconcileSheet({ ctx, sheet }) {
  const s = useVmo(ctx);
  const [done, setDone] = useState(null);
  const rp = ctx.redeemPending;
  if (done) return <VmoGenResult ctx={ctx} codes={done.codes} title="核对结果" headline={vmoResolvedHeadline(done.codes, done.how)} />;
  if (sheet.missing) {
    if (!rp) return null;
    return <VmoGenPending ctx={ctx} s={s} spec={vmoPendingSpec(rp)} idemKey={vmoPendingKey(rp)} at={rp.at || '10/16 09:36'} missing onResolved={(codes, how) => setDone({ codes, how })} />;
  }
  const codes = (sheet.ids || []).map(id => s.data.codes.find(c => c.id === id)).filter(Boolean);
  if (!codes.length) return null;
  return <VmoGenResult ctx={ctx} codes={codes} title="核对结果" headline={vmoResolvedHeadline(codes, 'check')}
    foot={`这一批是 ${codes[0].createdAt} 发起时生成的，已在列表的“今天生成”里；导出 CSV 请在 Web 操作。`} />;
}

function VmoGenReceipt({ spec }) {
  const sum = vmoGenSummary(spec);
  return (
    <div className="vmo-receipt">
      <div><span>类型</span><b>{VMO_TYPE[spec.type].label}</b></div>
      <div><span>每个</span><b className="num">{sum.each}</b></div>
      <div><span>数量</span><b className="num">× {spec.count}</b></div>
      <div><span>过期</span><b>{sum.expiry}</b></div>
      {sum.total !== null && <div className="vmo-receipt-total"><span>合计</span><b className="num">{fmt.money(sum.total)}</b></div>}
    </div>
  );
}

function VmoValueFields({ spec, set }) {
  if (spec.type === 'balance') {
    return (
      <label className="vmo-frow vmo-money-row">
        <span className="vmo-flabel">面值</span>
        <span className="vmo-cur">$</span>
        <input className="num" inputMode="decimal" value={spec.value} placeholder="0.00" onChange={e => set('value', e.target.value.replace(/[^\d.]/g, '').slice(0, 8))} />
      </label>
    );
  }
  if (spec.type === 'concurrency') {
    return <div className="vmo-frow"><span className="vmo-flabel">增加并发</span><span className="vmo-fill" /><VmoStepper value={spec.conc} max={50} onChange={v => set('conc', v)} label="并发数" /></div>;
  }
  if (spec.type === 'subscription') {
    return (
      <>
        <div className="vmo-frow vmo-frow-stack"><span className="vmo-flabel">订阅分组</span><VmoChoice items={VMO_SUB_GROUPS.map(g => [g, g])} value={spec.group} onChange={v => set('group', v)} /></div>
        <div className="vmo-frow vmo-frow-stack"><span className="vmo-flabel">有效天数</span><VmoChoice items={VMO_SUB_DAYS} value={spec.days} onChange={v => set('days', v)} /></div>
        {spec.days === 'custom' && <VmoField label="天数" value={spec.customSubDays} inputMode="numeric" placeholder="1–3650" onChange={v => set('customSubDays', v.replace(/\D/g, '').slice(0, 4))} />}
      </>
    );
  }
  return null;
}

function VmoExpiryField({ spec, set }) {
  return (
    <>
      <div className="vmo-frow vmo-frow-full"><VmoChoice items={VMO_EXPIRY} value={spec.expiry} onChange={v => set('expiry', v)} /></div>
      {spec.expiry === 'custom' && <VmoField label="天数" value={spec.customDays} inputMode="numeric" placeholder="1–3650" onChange={v => set('customDays', v.replace(/\D/g, '').slice(0, 4))} />}
    </>
  );
}

function useVmoGen(sheet) {
  const [spec, setSpec] = useState(() => vmoGenSpec(sheet));
  const [phase, setPhase] = useState(() => (sheet.phase === 'pending' ? { kind: 'pending', key: vmoIdemKey(vmoGenSpec(sheet)) } : { kind: 'edit' }));
  const set = (k, v) => setSpec(x => ({ ...x, [k]: v }));
  return { spec, set, phase, setPhase };
}

function vmoFaceNote(ctx, spec, sum) {
  return spec.type === 'balance' && vmoNeedsFace(ctx, sum.total) ? vmoFaceLine('合计') : '';
}

// base: one Form page
function VmoGenForm({ ctx, sheet }) {
  const s = useVmo(ctx);
  const { spec, set, phase, setPhase } = useVmoGen(sheet);
  if (phase.kind === 'done' || phase.kind === 'pending') return <VmoGenPhase ctx={ctx} s={s} spec={spec} phase={phase} setPhase={setPhase} />;
  const sum = vmoGenSummary(spec);
  const face = vmoFaceNote(ctx, spec, sum);
  return (
    <VmoSheet title="生成兑换码" leading={{ label: '取消', onPress: ctx.closeSheet }} onDismiss={ctx.closeSheet} className={cx(phase.kind === 'faceid' && 'is-verifying')} locked={phase.kind === 'faceid'}>
      <VmoFsec foot={`${VMO_TYPE[spec.type].hint}一次最多 100 个。`}>
        <div className="vmo-frow vmo-frow-full"><Segmented items={Object.entries(VMO_TYPE).map(([key, t]) => ({ key, label: t.label }))} value={spec.type} onChange={v => set('type', v)} /></div>
        <VmoValueFields spec={spec} set={set} />
        <VmoCountField label="数量" value={spec.count} min={1} max={100} onChange={v => set('count', v)} unit="个" />
      </VmoFsec>
      <VmoFsec title="兑换码过期"><VmoExpiryField spec={spec} set={set} /></VmoFsec>
      <div className="vmo-gen-foot">
        <div className="vmo-gen-total">
          <span>{spec.count} 个 × {sum.each}<small>{sum.expiry}</small></span>
          {sum.total !== null && <b className="num">{fmt.money(sum.total)}</b>}
        </div>
        {face && <div className="vmo-face-note"><Icon name="shield" size={14} weight={2.4} />{face}</div>}
        <button className="submit" disabled={!sum.valid} onClick={() => vmoConfirmGen(ctx, s, spec, setPhase)}>生成 {spec.count} 个兑换码</button>
      </div>
      {phase.kind === 'faceid' && <VmoFaceId />}
    </VmoSheet>
  );
}

const VMO_STEPS = ['类型', '面额与数量', '有效期'];

// Big-number keypad input (same rules as core's KeypadSheet): two decimals, no leading zero, at most 6 digits.
function vmoKeypadNext(cur, k) {
  if (k === 'del') return cur.slice(0, -1);
  if (k === '.' && (cur.includes('.') || !cur)) return cur;
  if (cur.includes('.') && cur.split('.')[1].length >= 2) return cur;
  if (cur.replace('.', '').length >= 6) return cur;
  return cur === '0' && k !== '.' ? k : cur + k;
}

function VmoKeypad({ onPress }) {
  return (
    <div className="kp-pad vmo-kp-pad">
      {['1', '2', '3', '4', '5', '6', '7', '8', '9', '.', '0', 'del'].map(k => (
        <button key={k} className="kp-key num" onClick={() => onPress(k)} aria-label={k === 'del' ? '删除' : k}>{k === 'del' ? <Icon name="deleteLeft" size={24} weight={1.9} /> : k}</button>
      ))}
    </div>
  );
}

function VmoStepBar({ steps, step }) {
  return (
    <div className="vmo-steps" aria-label={`第 ${step} 步，共 ${steps.length} 步`}>
      {steps.map((label, i) => <span key={label} className={cx('vmo-step', i + 1 === step && 'is-on', i + 1 < step && 'is-done')}><i />{label}</span>)}
    </div>
  );
}

// steps: 类型 → 面额与数量 → 有效期与确认
function VmoGenSteps({ ctx, sheet }) {
  const s = useVmo(ctx);
  const { spec, set, phase, setPhase } = useVmoGen(sheet);
  const [step, setStep] = useState(sheet.step || 1);
  if (phase.kind === 'done' || phase.kind === 'pending') return <VmoGenPhase ctx={ctx} s={s} spec={spec} phase={phase} setPhase={setPhase} />;
  const sum = vmoGenSummary(spec);
  const face = vmoFaceNote(ctx, spec, sum);
  const step2Ok = (spec.type !== 'balance' || Number(spec.value) > 0) && (spec.type !== 'subscription' || vmoSubDays(spec) >= 1);
  return (
    <VmoSheet tall title={step === 3 ? '有效期与确认' : VMO_STEPS[step - 1]} onDismiss={ctx.closeSheet} className={cx(phase.kind === 'faceid' && 'is-verifying')} locked={phase.kind === 'faceid'}
      leading={step > 1 ? { label: '上一步', back: true, onPress: () => setStep(step - 1) } : { label: '取消', onPress: ctx.closeSheet }}>
      <VmoStepBar steps={VMO_STEPS} step={step} />
      {step === 1 && (
        <div className="vmo-type-grid">
          {Object.entries(VMO_TYPE).map(([key, t]) => (
            <button key={key} className={cx('vmo-type-tile', spec.type === key && 'is-on')} onClick={() => { set('type', key); setStep(2); }}>
              <span className="vmo-type-icon"><Icon name={t.icon} size={20} weight={2.1} /></span>
              <b>{t.label}</b>
              <small>{t.hint}</small>
            </button>
          ))}
        </div>
      )}
      {step === 1 && <div className="vmo-fsec-foot">点一个类型进入下一步；生成前会再确认一次。</div>}
      {step === 2 && (
        <>
          {spec.type === 'balance' && (
            <>
              <div className={cx('kp-amount num vmo-kp-amount', !spec.value && 'is-empty')}>${spec.value || '0'}</div>
              <div className="kp-preview">每个兑换码的面值 · 合计 <b className="num">{fmt.money(sum.total)}</b></div>
            </>
          )}
          {spec.type !== 'balance' && spec.type !== 'invitation' && <VmoFsec foot={VMO_TYPE[spec.type].hint}><VmoValueFields spec={spec} set={set} /></VmoFsec>}
          {spec.type === 'invitation' && <div className="vmo-fsec-foot">{VMO_TYPE.invitation.hint}</div>}
          {/* the keypad already owns the amount, so the count is picked, not typed: common counts + a stepper */}
          <VmoFsec>
            <div className="vmo-frow"><span className="vmo-flabel">数量</span><span className="vmo-fill" /><VmoStepper value={spec.count} onChange={v => set('count', v)} label="数量" /></div>
            <div className="vmo-frow vmo-frow-full vmo-count-picks"><VmoChoice items={VMO_COUNT_PICKS.map(n => [n, `${n} 个`])} value={spec.count} onChange={v => set('count', v)} /></div>
          </VmoFsec>
          {spec.type === 'balance' && <VmoKeypad onPress={k => set('value', vmoKeypadNext(String(spec.value), k))} />}
          <button className="submit" disabled={!step2Ok} onClick={() => setStep(3)}>下一步</button>
        </>
      )}
      {step === 3 && (
        <>
          <VmoFsec title="兑换码过期"><VmoExpiryField spec={spec} set={set} /></VmoFsec>
          <VmoGenReceipt spec={spec} />
          {face && <div className="vmo-face-note"><Icon name="shield" size={14} weight={2.4} />{face}</div>}
          <button className="submit" disabled={!sum.valid} onClick={() => vmoConfirmGen(ctx, s, spec, setPhase)}>生成 {spec.count} 个兑换码</button>
        </>
      )}
      {phase.kind === 'faceid' && <VmoFaceId />}
    </VmoSheet>
  );
}

/* ---------- 发放兑换码（补偿）：用户详情 ⋯ → sheet:redeemGrant ---------- */

// POST redeem-codes/create-and-redeem: one code, made and redeemed for this user in the same request. Invitation codes are
// left out (redeeming one fails with REDEEM_CODE_UNSUPPORTED_TYPE). `kind` is the Web wording of the balance-history entry.
const VMO_GRANT_TYPES = {
  balance: { label: '余额', icon: 'dollar', hint: '直接计入余额，按资金操作确认。', title: '余额补偿', kind: '余额充值（兑换）' },
  concurrency: { label: '并发', icon: 'gauge', hint: '提高这个用户的并发上限。', title: '并发补偿', kind: '并发增加（兑换）' },
  subscription: { label: '订阅', icon: 'group', hint: '开通或延长一个订阅分组。', title: '订阅补偿', kind: '订阅已分配' },
};
const VMO_GRANT_STEPS = ['类型', '数值', '备注'];
const VMO_GRANT_DEFAULT = { type: null, value: '', conc: 1, group: VMO_SUB, days: 30, customSubDays: '', note: '' };

// What the grant is, in the words the sheet, the confirm, the receipt and the user's record use.
function vmoGrantSummary(spec, u) {
  if (spec.type === 'balance') {
    const amount = Number(spec.value) || 0;
    return { money: true, amount, what: `${fmt.money(amount)} 余额`, short: fmt.money(amount), value: fmt.money(amount),
      after: fmt.money(u.balance + amount), change: `余额 ${fmt.money(u.balance)} → ${fmt.money(u.balance + amount)}`, valid: amount > 0 };
  }
  if (spec.type === 'concurrency') {
    const n = spec.conc;
    return { money: false, amount: n, what: `+${n} 并发`, short: `+${n} 并发`, value: `+${n} 并发`, display: `+${n} 并发`,
      change: typeof u.conc === 'number' ? `并发上限 ${u.conc} → ${u.conc + n}` : `并发上限 +${n}`, valid: n >= 1 };
  }
  const days = vmoSubDays(spec);
  const plan = vmoSubPlan(u, spec.group, days);
  return { money: false, amount: days, what: `${spec.group} ${days} 天订阅`, short: `${days} 天订阅`, value: `${spec.group} · ${days} 天`, display: `${spec.group} · ${days} 天`,
    change: plan.change, plan, valid: Boolean(spec.group) && days >= 1 && days <= 3650 };
}

// What redeeming a subscription code does to this user (AssignOrExtendSubscription, one row per user and group in DEMO.subscriptions):
// no row → a new one from today; a row still before its expiry (the active one, activeSubscription, or a suspended one) → the days
// are added to that expiry, and a suspended one becomes active again; a row past its expiry → a fresh term from today, usage reset
// (the server decides by expires_at, not by status). now = the who line; change = the receipt / confirm line;
// note = the value step's footnote.
function vmoSubPlan(u, group, days) {
  const g = groupOf(group);
  const row = activeSubscription(u.id, group) || (g ? subscriptionsOf(u.id).find(x => x.groupId === g.id) : null) || null;
  const running = Boolean(row) && daysUntil(row.expires) > 0;
  const to = vmoDate(vmoIsoPlus(running ? row.expires : DEMO_TODAY, days || 0));
  if (!row) return { now: `${group} 未订阅`, change: `新开通 · 到期 ${to}`, note: '还没有这个订阅：从今天开通。' };
  const was = vmoDate(row.expires);
  if (!running) return { now: `${group} ${was} 已过期`, change: `重新开通 · 到期 ${to}`, note: `订阅 ${was} 已过期：从今天重新算，用量清零。` };
  if (row.status === 'suspended') return { now: `${group} 已暂停，至 ${was}`, change: `恢复生效 · 到期 ${was} → ${to}`, note: '订阅暂停中：在原到期日上延长，并恢复为生效。' };
  return { now: `${group} 至 ${was}`, change: `到期 ${was} → ${to}`, note: `已有生效中的订阅：在原到期日 ${was} 上延长。` };
}

// Funds rule: object, site, type and value in the confirm; balance grants are destructive-styled like top-ups and ask for
// Face ID above the threshold. A disabled user can still be compensated, but the confirm says so.
function vmoConfirmGrant(ctx, u, spec, onGo) {
  const sum = vmoGrantSummary(spec, u);
  const memo = spec.note.trim();
  const face = sum.money && vmoNeedsFace(ctx, sum.amount);
  const lines = [`站点 ${ctx.site} · ${sum.change}`];
  if (memo) lines.push(`备注：${memo}`);
  if (u.status === 'disabled') lines.push('该用户已禁用。\n发放后仍不能调用，需先启用。');
  if (face) lines.push(vmoFaceLine());
  ctx.confirm({
    title: `向「${u.name}」发放 ${sum.what}？`,
    message: lines.join('\n'),
    actions: [
      { label: `发放 ${sum.short}`, role: sum.money ? 'destructive' : 'default', onPress: () => onGo(face) },
      { label: '取消', role: 'cancel' },
    ],
  });
}

// The server answers with the redeemed code; the user's balance-history then lists it (with the notes). Non-money entries
// carry `display` for the value column. The receipt offers the code itself.
function vmoApplyGrant(ctx, s, u, spec, code) {
  const sum = vmoGrantSummary(spec, u);
  const memo = spec.note.trim();
  const id = Math.max(...s.data.codes.map(c => c.id)) + 1;
  const value = spec.type === 'subscription' ? { group: spec.group, days: sum.amount } : { value: sum.amount };
  vmoSet(s, 'codes', list => [{ id, code, type: spec.type, ...value, status: 'used', usedBy: u.id, usedAt: VMO_NOW, createdAt: VMO_NOW, expiresAt: null, notes: memo }, ...list]);
  // same shape as DEMO.users[].ledger: code = the code's first 8 characters (Web prints them under redeemed items)
  const entry = { kind: VMO_GRANT_TYPES[spec.type].kind, amount: sum.money ? sum.amount : null, when: VMO_NOW, ...(sum.display ? { display: sum.display } : {}), ...(memo ? { note: memo } : {}), code: code.slice(0, 8) };
  const patch = spec.type === 'balance' ? { balance: u.balance + sum.amount } : spec.type === 'concurrency' && typeof u.conc === 'number' ? { conc: u.conc + sum.amount } : {};
  ctx.closeSheet();
  ctx.updateUser(u.id, { ...patch, ledger: [entry, ...(u.ledger || [])] }, {
    text: `已向 ${u.name} 发放 ${sum.what}`, icon: 'gift',
    action: { label: '查看兑换码', onPress: () => vmoShowCode(ctx, id) },
  });
}

// Who gets it, with the figure this grant changes: balance, concurrency limit, or the user's subscription in the chosen group.
function VmoGrantWho({ ctx, u, type, sum }) {
  const line = type === 'balance' ? <>余额 <span className="num">{fmt.money(u.balance)}</span></>
    : type === 'concurrency' ? <>并发上限 <span className="num">{u.conc ?? '—'}</span></>
      : type === 'subscription' && sum ? sum.plan.now : u.email;
  return (
    <div className="kp-user vmo-grant-who">
      <span className="kp-avatar">{u.name.slice(0, 1)}</span><span className="vmo-ellip vmo-grant-who-text">{u.name} · {line}</span>
      {u.status === 'disabled' && <ctx.skin.Badge tone="neutral" label="禁用" />}
    </div>
  );
}

function VmoGrantValue({ spec, set, sum }) {
  if (spec.type === 'balance') {
    return (
      <>
        <div className={cx('kp-amount num vmo-kp-amount', !spec.value && 'is-empty')}>${spec.value || '0'}</div>
        <div className="kp-preview">{sum.amount ? <>发放后余额 <b className="num">{sum.after}</b></> : '输入金额'}</div>
        <VmoKeypad onPress={k => set('value', vmoKeypadNext(String(spec.value), k))} />
      </>
    );
  }
  if (spec.type === 'concurrency') {
    return (
      <VmoFsec foot={`${VMO_GRANT_TYPES.concurrency.hint}发放后：${sum.change}。`}>
        <div className="vmo-frow"><span className="vmo-flabel vmo-flabel-w">增加并发</span><span className="vmo-fill" /><VmoStepper value={spec.conc} max={50} onChange={v => set('conc', v)} label="增加并发" /></div>
      </VmoFsec>
    );
  }
  return (
    <VmoFsec foot={`只列出订阅类型的分组。${sum.plan.note}`}>
      <div className="vmo-frow vmo-frow-stack"><span className="vmo-flabel">订阅分组</span><VmoChoice items={VMO_SUB_GROUPS.map(g => [g, g])} value={spec.group} onChange={v => set('group', v)} /></div>
      <div className="vmo-frow vmo-frow-stack"><span className="vmo-flabel">有效天数</span><VmoChoice items={VMO_SUB_DAYS} value={spec.days} onChange={v => set('days', v)} /></div>
      {spec.days === 'custom' && <VmoField label="天数" value={spec.customSubDays} inputMode="numeric" placeholder="1–3650" onChange={v => set('customSubDays', v.replace(/\D/g, '').slice(0, 4))} />}
    </VmoFsec>
  );
}

function VmoGrantReceipt({ ctx, u, spec, sum, code }) {
  return (
    <div className="vmo-receipt">
      <div><span>对象</span><b className="vmo-ellip">{u.name} · {u.email}</b></div>
      <div><span>站点</span><b>{ctx.site}</b></div>
      <div><span>类型</span><b>{VMO_GRANT_TYPES[spec.type].label}</b></div>
      {!sum.money && <div><span>数值</span><b className="num">{sum.value}</b></div>}
      <div><span>变化</span><b>{sum.change}</b></div>
      <div><span>兑换码</span><b className="mono">{vmoShort(code)}</b></div>
      {sum.money && <div className="vmo-receipt-total"><span>发放</span><b className="num">{sum.value}</b></div>}
    </div>
  );
}

// Wizard like the decided batch generator: 类型 → 数值（余额 = big keypad）→ 备注 → confirm → receipt.
// sheet: {kind:'redeemGrant', userId, type?, value?, conc?, group?, days?, note?, step?} (the extra fields only seed demo states).
function VmoGrantSheet({ ctx, sheet }) {
  const s = useVmo(ctx);
  const u = ctx.users[sheet.userId];
  const [spec, setSpec] = useState(() => ({ ...VMO_GRANT_DEFAULT, ...Object.fromEntries(Object.entries(sheet).filter(([k]) => k in VMO_GRANT_DEFAULT)) }));
  const [step, setStep] = useState(sheet.step || (sheet.type ? 2 : 1));
  const [verifying, setVerifying] = useState(false);
  // The code is made on the device and kept for the whole sheet: it is also what makes a retry safe (same user → same result).
  // So a grant whose answer never came back is simply re-sent with the same code + Idempotency-Key (the server returns the
  // code it already redeemed instead of granting twice); unlike a generated batch it needs no 待核对 record.
  const [code] = useState(() => vmoNewCode((sheet.userId || 1) * 7919 + 977));
  if (!u) return null;
  const set = (k, v) => setSpec(x => ({ ...x, [k]: v }));
  const sum = spec.type ? vmoGrantSummary(spec, u) : null;
  const go = face => {
    if (!face) { vmoApplyGrant(ctx, s, u, spec, code); return; }
    setVerifying(true);
    setTimeout(() => vmoApplyGrant(ctx, s, u, spec, code), 1100);
  };
  const title = step === 1 || !spec.type ? '发放兑换码' : step === 2 ? VMO_GRANT_TYPES[spec.type].title : '备注与确认';
  return (
    <VmoSheet tall title={title} onDismiss={ctx.closeSheet} className={cx('vmo-grant', verifying && 'is-verifying')} locked={verifying}
      leading={step > 1 ? { label: '上一步', back: true, onPress: () => setStep(step - 1) } : { label: '取消', onPress: ctx.closeSheet }}>
      <VmoStepBar steps={VMO_GRANT_STEPS} step={step} />
      <VmoGrantWho ctx={ctx} u={u} type={step === 1 ? null : spec.type} sum={sum} />
      {(step === 1 || !sum) && (
        <>
          <div className="vmo-type-grid is-list">
            {Object.entries(VMO_GRANT_TYPES).map(([key, t]) => {
              const off = key === 'subscription' && !VMO_SUB_GROUPS.length;
              return (
                <button key={key} className={cx('vmo-type-tile', spec.type === key && 'is-on')} disabled={off} onClick={() => { set('type', key); setStep(2); }}>
                  <span className="vmo-type-icon"><Icon name={t.icon} size={20} weight={2.1} /></span>
                  <span className="vmo-type-text"><b>{t.label}</b><small>{off ? '没有订阅类型的分组' : t.hint}</small></span>
                  <Icon name="chevron" size={13} weight={2.6} />
                </button>
              );
            })}
          </div>
          <div className="vmo-fsec-foot">发放会生成一个兑换码并立即替这个用户兑换，记录出现在用户的“充值与调整记录”和兑换码列表里。邀请码只能在注册时使用，不能发放。</div>
        </>
      )}
      {step === 2 && sum && (
        <>
          <VmoGrantValue spec={spec} set={set} sum={sum} />
          <button className="submit" disabled={!sum.valid} onClick={() => setStep(3)}>下一步</button>
        </>
      )}
      {step === 3 && sum && (
        <>
          <VmoFsec title="备注" foot="可选。写进兑换码的备注，也显示在用户的“充值与调整记录”里。">
            <textarea className="vmo-textarea vmo-textarea-s" value={spec.note} placeholder="例如：故障补偿 · 工单 #8812" aria-label="备注（可选）" onChange={e => set('note', e.target.value)} />
          </VmoFsec>
          <VmoGrantReceipt ctx={ctx} u={u} spec={spec} sum={sum} code={code} />
          {/* RedeemForAdminFulfillment keeps the redeem-level invite rebate whenever affiliate is on; a plain top-up only rebates
              when the separate setting 管理员充值参与返利 is on (tryAccrueAffiliateRebateForAdminRecharge) */}
          {sum.money && <div className="vmo-fsec-foot">按兑换处理：开启邀请返利时，邀请人会照常得到返利（和用户自己兑换一样，不看“管理员充值参与返利”开关）。</div>}
          {sum.money && vmoNeedsFace(ctx, sum.amount) && <div className="vmo-face-note"><Icon name="shield" size={14} weight={2.4} />{vmoFaceLine()}</div>}
          <button className="submit" disabled={!sum.valid || verifying} onClick={() => vmoConfirmGrant(ctx, u, spec, go)}>发放 {sum.short}</button>
        </>
      )}
      {verifying && <VmoFaceId text="验证后发放" />}
    </VmoSheet>
  );
}

/* ====================================================================== */
/* ---------- 代理 ---------- */

function vmoTestProxy(s, id) {
  if (s.data.busy[`t${id}`]) return;
  vmoBusy(s, `t${id}`, true);
  setTimeout(() => {
    const p = s.data.proxies.find(x => x.id === id);
    if (p) {
      const r = p.probe || {};
      vmoPatch(s, 'proxies', id, r.fail
        ? { latencyOk: false, latency: null, latencyMsg: r.fail, justTested: true }
        : { latencyOk: true, latency: r.latency, latencyMsg: null, justTested: true, exitIp: r.exitIp || p.exitIp || p.host, region: r.region || p.region });
    }
    vmoBusy(s, `t${id}`, false);
  }, 1300);
}

function vmoTestAll(ctx, s) {
  const list = s.data.proxies;
  list.forEach((p, i) => setTimeout(() => vmoTestProxy(s, p.id), i * 260));
  setTimeout(() => {
    const failed = s.data.proxies.filter(p => p.latencyOk === false).length;
    ctx.showToast({ text: `已测试 ${list.length} 个代理${failed ? ` · ${failed} 个失败` : ''}`, icon: 'wave', tone: failed ? 'critical' : 'ok' });
  }, list.length * 260 + 1400);
}

function vmoQualityCheck(ctx, s, p) {
  vmoBusy(s, `q${p.id}`, true);
  setTimeout(() => {
    const q = (p.probe && p.probe.quality) || null;
    vmoPatch(s, 'proxies', p.id, q ? { quality: q, qualityAt: VMO_NOW } : { quality: null });
    vmoBusy(s, `q${p.id}`, false);
    ctx.showToast(q ? { text: `质量检测完成：评分 ${q.score}（${q.grade}）`, icon: 'shield' } : { text: '代理质量检测失败', icon: 'octagon', tone: 'critical' });
  }, 1600);
}

// Disabling does not cut off accounts already on the proxy (the gateway uses account.Proxy.URL() regardless of status);
// it only hides the proxy from account editing (/proxies/all returns active only) and from fallback chains.
// So it runs directly with an undo. An expired proxy is renewed in the edit sheet instead (new expiry + 正常).
function vmoToggleProxy(ctx, s, p) {
  if (p.status === 'expired') { ctx.openSheet({ kind: 'proxyEdit', id: p.id }); return; }
  const off = p.status === 'active';
  vmoPatch(s, 'proxies', p.id, { status: off ? 'inactive' : 'active' });
  ctx.showToast({
    text: off ? (p.accounts.length ? `已停用 ${p.name} · 在用的 ${p.accounts.length} 个账号不受影响` : `已停用 ${p.name}`) : `已启用 ${p.name}`,
    icon: off ? 'minus' : 'checkCircle', tone: off ? 'neutral' : 'ok', undo: () => vmoPatch(s, 'proxies', p.id, { status: p.status }),
  });
}

const vmoToggleLabel = p => (p.status === 'active' ? '停用' : p.status === 'expired' ? '续期' : '启用');

// ⋯ of one proxy (a Menu spec): toolbar → ctx.menu, open inline card → VmoMoreBtn.
function vmoProxyMenu(ctx, s, p, afterDelete) {
  const del = () => {
    if (p.accounts.length) {
      ctx.confirm({
        title: `不能删除「${p.name}」`,
        message: `该代理已有 ${p.accounts.length} 个账号使用，无法删除。先在这些账号的编辑页里换掉代理。`,
        actions: [{ label: '知道了', role: 'cancel' }],
      });
      return;
    }
    confirmDelete(ctx, '代理', p.name, afterDelete, { remove: () => vmoRemove(s, 'proxies', p.id) });
  };
  return {
    title: p.name,
    message: vmoAddr(p),
    actions: [
      { label: '编辑代理', role: 'default', onPress: () => ctx.openSheet({ kind: 'proxyEdit', id: p.id }) },
      { label: '复制代理 URL', role: 'default', onPress: () => vmoCopy(ctx, '代理 URL') },
      { label: '质量检测', role: 'default', onPress: () => vmoQualityCheck(ctx, s, p) },
      { label: p.status === 'expired' ? '续期…' : p.status === 'active' ? '停用代理' : '启用代理', role: 'default', onPress: () => vmoToggleProxy(ctx, s, p) },
      { label: '删除代理…', role: 'destructive', onPress: del },
    ],
  };
}

function VmoProxyGlyph({ ctx, p }) {
  const { skin } = ctx;
  if (p.status === 'inactive') return <skin.Glyph state="inactive" />;
  if (p.status === 'expired') return p.accounts.length ? <skin.Glyph state="error" /> : <skin.Glyph state="inactive" />;
  if (p.latencyOk === false) return <skin.Glyph state="error" />;
  if (p.latencyOk === null) return <span className="glyph tone-neutral"><Icon name="dot" size={8} /></span>;
  return <skin.Glyph state="normal" />;
}

function VmoLatency({ p, testing }) {
  if (testing) return <span className="row-right vmo-testing">测试中</span>;
  if (p.latencyOk === false) return <VmoBadge tone="critical" icon="octagon" label="链接失败" />;
  if (p.latencyOk === null) return <span className="row-right dim">未测试</span>;
  return <span className="row-right num vmo-lat-s">{p.latency}<small>ms</small></span>;
}

// Row right side: an expired / disabled proxy shows its status (there is no point timing it); otherwise the latency.
// An open inline card shows the status here too, because its body already carries the big latency figure.
function VmoProxyRight({ p, testing, open }) {
  if (testing) return <VmoLatency p={p} testing />;
  if (open || p.status !== 'active') return <VmoBadge {...vmoProxyBadge(p)} />;
  return <VmoLatency p={p} />;
}

function VmoProxyFoot({ p }) {
  const exp = proxyExpiry(p);
  const n = p.accounts.length;
  const use = p.status === 'expired' ? (n ? `${n} 个账号仍在用` : '没有账号在用') : n ? `${n} 个账号在用` : '没有账号在用';
  const tail = p.status === 'expired' ? ` · ${vmoMD(p.expiresAt)} 到期` : p.status === 'inactive' ? '' : p.region ? ` · ${p.region}` : '';
  return (
    <div className="row-foot">
      <span className="row-meta vmo-ellip">{use}{tail}</span>
      {exp.key === 'soon' && <VmoBadge tone={exp.tone} icon="clockAlert" label={exp.label} />}
      {p.status === 'expired' && p.latencyOk === false && n > 0 && <VmoBadge tone="critical" icon="octagon" label="链接失败" />}
    </div>
  );
}

// Only proxies that still carry accounts: expired ones (status) first, then active ones about to expire.
function VmoExpiryBanner({ ctx, list, onShow }) {
  const { skin } = ctx;
  const hits = list.filter(vmoNeedsCare)
    .sort((a, b) => (a.status === 'expired' ? -1 : 0) - (b.status === 'expired' ? -1 : 0) || daysUntil(a.expiresAt) - daysUntil(b.expiresAt));
  if (!hits.length) return null;
  const lapsed = hits.filter(p => p.status === 'expired');
  const tone = lapsed.length ? 'critical' : 'caution';
  const line = p => (p.status === 'expired' ? `${p.name} 已过期，仍有 ${p.accounts.length} 个账号在用` : `${p.name} ${proxyExpiry(p).label}，${p.accounts.length} 个账号在用`);
  const short = p => (p.status === 'expired' ? `${p.name} 已过期仍在用` : `${p.name} ${proxyExpiry(p).label}`);
  const title = hits.length === 1 ? line(hits[0]) : `${hits.length} 个代理需要处理`;
  const rest = hits.length === 1 ? (hits[0].status === 'expired' ? '续期，或给这些账号换代理' : '到期前续期，或设置到期回退') : hits.map(short).join(' · ');
  return (
    <div className={cx('banner vmo-banner vmo-banner-wrap', `tone-${tone}`, skin.rowClass(tone))}>
      <Icon name="clockAlert" size={18} />
      <div className="banner-text"><b>{title}</b><span>{rest}</span></div>
      {onShow && <VmoAct small label="查看" onClick={onShow} />}
    </div>
  );
}

function vmoProxyChips(list) {
  const soon = list.filter(p => p.status === 'active' && p.accounts.length > 0 && proxyExpiry(p).key === 'soon').length;
  const expired = list.filter(p => p.status === 'expired');
  return [
    { key: 'all', label: '全部', count: list.length },
    { key: 'expired', label: '已过期', count: expired.length, alert: expired.some(p => p.accounts.length > 0) },
    { key: 'soon', label: '即将到期', count: soon, alert: soon > 0 && !expired.some(p => p.accounts.length > 0) },
    { key: 'failed', label: '链接失败', count: list.filter(vmoLinkFailed).length },
    { key: 'inactive', label: '停用', count: list.filter(p => p.status === 'inactive').length },
  ];
}

const VMO_PROXY_PICK = {
  expired: p => p.status === 'expired',
  soon: p => p.status === 'active' && p.accounts.length > 0 && proxyExpiry(p).key === 'soon',
  failed: vmoLinkFailed,
  inactive: p => p.status === 'inactive',
};
// "查看" on the banner: the expired filter when something expired still has accounts, otherwise 即将到期
const vmoBannerFilter = list => (list.some(p => p.status === 'expired' && p.accounts.length) ? 'expired' : 'soon');

function VmoProxyNav({ ctx, s }) {
  const busy = Object.keys(s.data.busy).some(k => k.startsWith('t'));
  return (
    <NavBar ctx={ctx} back title="代理" subtitle={`${ctx.site} · ${s.data.proxies.length} 个`}
      trailing={<><GlassButton label={busy ? '测试中…' : '全部测试'} onClick={() => !busy && vmoTestAll(ctx, s)} /><GlassButton icon="plus" onClick={() => ctx.openSheet({ kind: 'proxyEdit' })} /></>} />
  );
}

function VmoProxyList({ ctx, route }) {
  const s = useVmo(ctx);
  const [filter, setFilter] = useState(route.filter || 'all');
  const list = vmoProxies(ctx, s);
  const rows = list.filter(VMO_PROXY_PICK[filter] || (() => true));
  return (
    <Screen plain ctx={ctx} nav={<VmoProxyNav ctx={ctx} s={s} />}>
      {filter === 'all' && <VmoExpiryBanner ctx={ctx} list={list} onShow={() => setFilter(vmoBannerFilter(list))} />}
      <Chips items={vmoProxyChips(list)} value={filter} onChange={setFilter} />
      <div className="list-group">
        <div className="list-head"><span>代理</span><b className="lg-head-cols">延迟 / 状态</b></div>
        {rows.map(p => {
          const tone = vmoProxyTone(p);
          return (
            <Row key={p.id} skin={ctx.skin} tone={tone} className={cx(`tone-${tone === 'none' ? 'ok' : tone}`, (p.status === 'inactive' || (p.status === 'expired' && !p.accounts.length)) && 'is-idle')}
              lead={<VmoProxyGlyph ctx={ctx} p={p} />} onClick={() => ctx.push({ kind: 'proxyDetail', id: p.id })}>
              <div className="row-top"><span className="row-title">{p.name}</span><VmoProxyRight p={p} testing={s.data.busy[`t${p.id}`]} /></div>
              <div className="row-meta mono vmo-addr">{vmoAddr(p)}</div>
              <VmoProxyFoot p={p} />
            </Row>
          );
        })}
        {rows.length === 0 && <div className="empty pad">没有这类代理</div>}
      </div>
    </Screen>
  );
}

// 0–500 ms vernier scale with a needle; ink only (latency has no status colour of its own)
function VmoLatScale({ ms }) {
  const at = Math.min(ms, 500) / 5;
  return (
    <div className="vmo-scale" aria-hidden="true">
      <div className="vmo-scale-ticks" />
      <i className="vmo-scale-needle" style={{ left: `${at}%` }} />
      <div className="vmo-scale-labels num">{[0, 100, 200, 300, 400, 500].map(v => <span key={v} style={{ left: `${v / 5}%` }}>{v}</span>)}</div>
    </div>
  );
}

// Latency figure (or 测试中 / 链接失败 / 未测试) with an optional control beside it; the error text or scale goes full width below.
function VmoLatencyBlock({ p, testing, side }) {
  let head;
  let extra = null;
  if (testing) head = <div className="vmo-lat-fig"><span className="vmo-testing vmo-testing-l">测试中</span></div>;
  else if (p.latencyOk === false) { head = <div className="vmo-lat-fail">链接失败</div>; extra = <div className="rq-error mono">{p.latencyMsg}</div>; }
  else if (p.latencyOk === null) head = <div className="vmo-lat-fig"><span className="vmo-lat-missing">—</span><small>还没测试过</small></div>;
  else { head = <div className="vmo-lat-fig"><span className="num readout">{p.latency}</span><small>ms</small></div>; extra = <VmoLatScale ms={p.latency} />; }
  return <>{side ? <div className="vmo-lat-row">{head}{side}</div> : head}{extra}</>;
}

function VmoProxyFacts({ p, quality }) {
  return (
    <div className="vmo-facts">
      <span><small>出口 IP</small><b className={cx(p.exitIp && 'mono')}>{p.exitIp || '—'}</b></span>
      <span><small>地区</small><b>{p.region || '—'}</b></span>
      <span><small>质量{p.qualityAt && !quality ? ` · ${vmoDay(p.qualityAt)}` : ''}</small><b className={cx(p.quality && !quality && 'num')}>{quality ? '检测中…' : p.quality ? `${p.quality.grade} · ${p.quality.score}` : '—'}</b></span>
    </div>
  );
}

const vmoFallbackText = (p, backup) => (p.fallback === 'proxy' ? `备用 ${backup ? backup.name : '—'}` : VMO_FALLBACK[p.fallback]);

function VmoExpiryCallout({ p, backup, className }) {
  const note = vmoExpiryNote(p, backup);
  if (!note) return null;
  return <div className={cx('vmo-exp-line', `tone-${note.tone}`, className)}><Icon name={p.status === 'expired' && !p.accounts.length ? 'restore' : 'clockAlert'} size={16} /><span>{note.text}</span></div>;
}

function VmoProxyDetail({ ctx, route }) {
  const s = useVmo(ctx);
  const { skin } = ctx;
  const all = vmoProxies(ctx, s);
  const p = all.find(x => x.id === route.id);
  if (!p) return <VmoGone ctx={ctx} title="代理" />;
  const testing = s.data.busy[`t${p.id}`];
  const exp = proxyExpiry(p);
  const backup = p.backupId ? all.find(x => x.id === p.backupId) : null;
  const accounts = p.accounts.map(id => ctx.accounts[id]).filter(Boolean);
  const failing = p.latencyOk === false && (p.status === 'active' || accounts.length > 0);
  // No test time exists in the DTO, so nothing here says when the figure was measured; a test run on this screen is
  // only marked as this session's result.
  const cause = testing ? '正在测试连通性' : p.justTested ? '本次测试结果' : p.status === 'inactive' ? (accounts.length ? '在用的账号不受影响' : '账号编辑里选不到它') : '';
  return (
    <Screen ctx={ctx} nav={<NavBar ctx={ctx} back title={p.name} subtitle={vmoAddr(p)} trailing={<GlassButton icon="more" onClick={() => ctx.menu(vmoProxyMenu(ctx, s, p, ctx.pop))} />} />}>
      <div className="detail-head">
        <div className={cx('hero vmo-lat-hero', failing && cx('tone-critical', skin.rowClass('critical')))}>
          <div className="hero-top">
            <VmoBadge {...vmoProxyBadge(p)} />
            <span className="hero-cause">{cause}</span>
          </div>
          <VmoLatencyBlock p={p} testing={testing} />
          <VmoProxyFacts p={p} quality={s.data.busy[`q${p.id}`]} />
        </div>
        <div className="actions">
          {p.status === 'expired' && <VmoAct label="续期" icon="restore" primary onClick={() => ctx.openSheet({ kind: 'proxyEdit', id: p.id })} />}
          <VmoAct label={testing ? '测试中…' : '测试连接'} icon="wave" primary={p.status !== 'expired'} disabled={testing} onClick={() => vmoTestProxy(s, p.id)} />
          {p.status !== 'expired' && <VmoAct label="编辑" icon="compose" onClick={() => ctx.openSheet({ kind: 'proxyEdit', id: p.id })} />}
        </div>
      </div>
      <Section skin={skin} title="有效期" index="壹">
        <VmoExpiryCallout p={p} backup={backup} className="pad" />
        <div className="kv-grid pad">
          <KV label="到期日" value={p.expiresAt ? <span className="num">{p.expiresAt}</span> : '永不过期'} />
          <KV label="到期提醒" value={`提前 ${p.warnDays} 天`} />
          {/* when the callout is shown it already says how long and what happens after */}
          {!vmoExpiryNote(p, backup) && <>
            <KV label="剩余" value={exp.key === 'never' ? '不限' : exp.key === 'idle' ? '—' : exp.label} />
            <KV label="到期回退" value={vmoFallbackText(p, backup)} />
          </>}
        </div>
      </Section>
      <Section skin={skin} title="使用该 IP 的账号" meta={`${accounts.length} 个`} index="贰">
        {accounts.length === 0 && <div className="empty pad">暂无账号使用此代理</div>}
        {accounts.map(a => (
          <Row key={a.id} skin={skin} tone="none" lead={<skin.Glyph state={a.state} />} onClick={() => ctx.push({ kind: 'account', id: a.id })}>
            <div className="row-top"><span className="row-title">{a.name}</span><skin.Badge state={a.state} secs={remaining(a, ctx.elapsed)} /></div>
            <div className="row-meta">{a.platform} · {a.type}</div>
          </Row>
        ))}
      </Section>
      <Section skin={skin} title="连接" index="叁">
        <div className="kv-grid pad">
          <KV label="协议" value={VMO_PROTO[p.protocol]} /><KV label="端口" value={<span className="num">{p.port}</span>} />
          <KV label="主机" value={p.host} mono /><KV label="用户名" value={p.username || '—'} mono={Boolean(p.username)} />
          <KV label="密码" value={p.hasPassword ? '••••••' : '未设置'} /><KV label="创建时间" value={<span className="num">{p.createdAt}</span>} />
        </div>
      </Section>
    </Screen>
  );
}

function VmoProxyInline({ ctx, route }) {
  const s = useVmo(ctx);
  const [filter, setFilter] = useState(route.filter || 'all');
  const [open, setOpen] = useState(route.open ?? null);
  const list = vmoProxies(ctx, s);
  const rows = list.filter(VMO_PROXY_PICK[filter] || (() => true));
  return (
    <Screen ctx={ctx} nav={<VmoProxyNav ctx={ctx} s={s} />}>
      {filter === 'all' && <VmoExpiryBanner ctx={ctx} list={list} onShow={() => setFilter(vmoBannerFilter(list))} />}
      <Chips items={vmoProxyChips(list)} value={filter} onChange={setFilter} />
      <div className="vmo-cards">
        {rows.map(p => {
          const isOpen = open === p.id;
          const testing = s.data.busy[`t${p.id}`];
          const exp = proxyExpiry(p);
          const backup = p.backupId ? list.find(x => x.id === p.backupId) : null;
          return (
            <VmoCard key={p.id} open={isOpen} onToggle={() => setOpen(isOpen ? null : p.id)} tone={vmoProxyTone(p)} idle={p.status === 'inactive' || (p.status === 'expired' && !p.accounts.length)}
              lead={<VmoProxyGlyph ctx={ctx} p={p} />}
              head={<>
                <div className="row-top"><span className="row-title">{p.name}</span><VmoProxyRight p={p} testing={testing} open={isOpen} /></div>
                <div className="row-meta mono vmo-addr">{vmoAddr(p)}</div>
                {!isOpen && <VmoProxyFoot p={p} />}
              </>}>
              <div className="vmo-inline-lat">
                <VmoLatencyBlock p={p} testing={testing} side={<VmoAct small label={testing ? '测试中…' : '测试连接'} icon="wave" primary disabled={testing} onClick={() => vmoTestProxy(s, p.id)} />} />
              </div>
              <VmoExpiryCallout p={p} backup={backup} className="vmo-exp-inline" />
              <VmoProxyFacts p={p} quality={s.data.busy[`q${p.id}`]} />
              <div className="kv-grid vmo-kv">
                <KV label="到期日" value={<span className={cx(exp.tone !== 'none' && `tone-${exp.tone} tone-text`)}>{p.expiresAt ? <><span className="num">{vmoMD(p.expiresAt)}</span>{exp.key === 'ok' ? ` · ${exp.label}` : ''}</> : '永不过期'}</span>} />
                <KV label="到期回退" value={vmoFallbackText(p, backup)} />
                <KV label="认证" value={p.username ? <span className="mono">{p.username} / ••••</span> : '无'} />
                <KV label="创建时间" value={<span className="num">{p.createdAt}</span>} />
              </div>
              <div className="vmo-acct">
                <small>使用该 IP 的账号 · {p.accounts.length}</small>
                <div className="vmo-acct-chips">
                  {p.accounts.length === 0 && <span className="dim">暂无</span>}
                  {p.accounts.map(id => ctx.accounts[id]).filter(Boolean).map(a => (
                    <button key={a.id} className={cx('chip vmo-acct-chip', `tone-${toneOf(a.state)}`)} onClick={() => ctx.push({ kind: 'account', id: a.id })}>
                      <ctx.skin.Glyph state={a.state} />{a.name}
                    </button>
                  ))}
                </div>
              </div>
              <div className="vmo-card-actions">
                {p.status === 'expired'
                  ? <VmoAct label="续期" icon="restore" primary onClick={() => vmoToggleProxy(ctx, s, p)} />
                  : <VmoAct label="编辑" icon="compose" onClick={() => ctx.openSheet({ kind: 'proxyEdit', id: p.id })} />}
                {p.status !== 'expired' && <VmoAct label={vmoToggleLabel(p)} icon={p.status === 'active' ? 'minus' : 'play'} onClick={() => vmoToggleProxy(ctx, s, p)} />}
                <VmoMoreBtn menu={() => vmoProxyMenu(ctx, s, p, () => setOpen(null))} />
              </div>
            </VmoCard>
          );
        })}
        {rows.length === 0 && <div className="empty pad">没有这类代理</div>}
      </div>
    </Screen>
  );
}

const VMO_PROXY_BLANK = { name: '', protocol: 'socks5', host: '', port: '', username: '', password: '', expiry: 'never', customDays: '', warnDays: 7, fallback: 'none', backupId: null, status: 'active' };

// A backup is only a valid fallback target while it is active and not past its expiry (ResolveProxyFallbackTarget skips the rest).
const vmoUsableBackup = x => x.status === 'active' && !(x.expiresAt && daysUntil(x.expiresAt) < 0);

function VmoProxyEdit({ ctx, sheet }) {
  const s = useVmo(ctx);
  const all = vmoProxies(ctx, s);
  const p = sheet.id ? all.find(x => x.id === sheet.id) : null;
  const wasExpired = Boolean(p && p.status === 'expired');
  // PUT accepts only active / inactive; like Web, an expired proxy opens as 停用 until it gets a new expiry.
  const [f, setF] = useState(() => (p
    ? { ...VMO_PROXY_BLANK, name: p.name, protocol: p.protocol, host: p.host, port: String(p.port), username: p.username, expiry: p.expiresAt ? 'keep' : 'never', warnDays: p.warnDays, fallback: p.fallback, backupId: p.backupId || null, status: wasExpired ? 'inactive' : p.status }
    : { ...VMO_PROXY_BLANK, ...(sheet.draft || {}) }));
  const set = (k, v) => setF(x => ({ ...x, [k]: v }));
  // renewing an expired proxy: picking a new expiry also switches it back to 正常 (still changeable below)
  const setExpiry = v => setF(x => ({ ...x, expiry: v, ...(wasExpired && v !== 'keep' ? { status: 'active' } : {}) }));
  const port = Number(f.port);
  const lapsedKeep = wasExpired && f.expiry === 'keep';
  const valid = f.name.trim() && f.host.trim() && port >= 1 && port <= 65535 && (f.fallback !== 'proxy' || f.backupId) && !(lapsedKeep && f.status === 'active');
  const others = all.filter(x => !p || x.id !== p.id);
  const backupItems = others.map(x => [x.id, x.name, !vmoUsableBackup(x), vmoUsableBackup(x) ? null : x.status === 'inactive' ? '停用' : '已过期']);
  const expiryItems = [...(p && p.expiresAt ? [['keep', `保持 ${p.expiresAt}${wasExpired ? '（已过期）' : ''}`]] : []), ['never', '永不过期'], ['30', '30 天'], ['90', '90 天'], ['custom', '自定义']];
  const statusFoot = lapsedKeep
    ? (f.status === 'active' ? '有效期已过，改回“正常”前先在上面选新的有效期。' : '已过期的代理保存后仍是停用；选新的有效期即可续期。')
    : f.status === 'inactive'
      ? `停用后：账号编辑里选不到它，也不会被选作备用代理；${p && p.accounts.length ? `正在用它的 ${p.accounts.length} 个账号照常走这个代理，要更换请到账号编辑页。` : '已经在用它的账号照常走这个代理。'}`
      : wasExpired ? '续期后状态改回“正常”。' : null;
  const save = () => {
    const days = f.expiry === 'custom' ? Number(f.customDays) : Number(f.expiry);
    const expiresAt = f.expiry === 'keep' ? p.expiresAt : f.expiry === 'never' ? null : vmoIsoPlus(DEMO_TODAY, days);
    const patch = { name: f.name.trim(), protocol: f.protocol, host: f.host.trim(), port, username: f.username.trim(), expiresAt, warnDays: f.warnDays, fallback: f.fallback, backupId: f.fallback === 'proxy' ? f.backupId : null, status: f.status };
    if (p) {
      // an expired proxy saved without a new expiry stays expired on the server side of the demo
      vmoPatch(s, 'proxies', p.id, { ...patch, status: lapsedKeep ? 'expired' : patch.status, hasPassword: f.password ? true : p.hasPassword });
      // the backend links accounts by proxy_id; the demo links them by name, so a rename carries the accounts along
      if (patch.name !== p.name) p.accounts.forEach(id => ctx.updateAccount(id, { proxy: patch.name }));
      ctx.closeSheet();
      ctx.showToast({ text: wasExpired && !lapsedKeep ? `已续期 · ${patch.name} 恢复正常` : '代理更新成功' });
      return;
    }
    const id = Math.max(...s.data.proxies.map(x => x.id)) + 1;
    vmoSet(s, 'proxies', list => [...list, { id, ...patch, hasPassword: Boolean(f.password), latency: null, latencyOk: null, exitIp: null, region: null, quality: null, createdAt: DEMO_TODAY, probe: { latency: 158, exitIp: f.host.trim(), region: '—' } }]);
    ctx.closeSheet();
    ctx.showToast({ text: '代理添加成功', undo: () => vmoRemove(s, 'proxies', id) });
  };
  const basics = (
    <React.Fragment key="basics">
      <VmoFsec title="名称与协议" foot={f.protocol === 'socks5h' ? 'SOCKS5H 由代理服务器解析域名（远程 DNS）。' : null}>
        <VmoField label="名称" value={f.name} placeholder="请输入代理名称" onChange={v => set('name', v)} />
        <div className="vmo-frow vmo-frow-full"><Segmented items={Object.entries(VMO_PROTO).map(([key, label]) => ({ key, label }))} value={f.protocol} onChange={v => set('protocol', v)} /></div>
      </VmoFsec>
      <VmoFsec title="地址" foot={f.port && !(port >= 1 && port <= 65535) ? '端口必须在 1-65535 之间' : null}>
        <VmoField label="主机" value={f.host} mono placeholder="请输入主机地址" onChange={v => set('host', v)} />
        <VmoField label="端口" value={f.port} mono inputMode="numeric" placeholder="请输入端口" onChange={v => set('port', v.replace(/\D/g, '').slice(0, 5))} />
      </VmoFsec>
      <VmoFsec title="认证（可选）">
        <VmoField label="用户名" value={f.username} mono placeholder="请输入用户名" onChange={v => set('username', v)} />
        <VmoField label="密码" type="password" value={f.password} placeholder={p ? '留空保持不变' : '请输入密码'} onChange={v => set('password', v)} />
      </VmoFsec>
    </React.Fragment>
  );
  const expirySec = (
    <VmoFsec key="expiry" title={wasExpired ? '有效期 · 续期' : '有效期'} foot={wasExpired ? `${p.expiresAt} 已过期。选一个新的有效期来续期。` : '到期前按提醒天数在代理列表和告警里提示。'}>
      <div className="vmo-frow vmo-frow-full"><VmoChoice items={expiryItems} value={f.expiry} onChange={setExpiry} /></div>
      {f.expiry === 'custom' && <VmoField label="天数" value={f.customDays} inputMode="numeric" placeholder="自定义天数" onChange={v => set('customDays', v.replace(/\D/g, '').slice(0, 4))} />}
      <div className="vmo-frow"><span className="vmo-flabel vmo-flabel-w">到期提醒提前</span><span className="vmo-fill" /><VmoStepper value={f.warnDays} min={1} max={30} onChange={v => set('warnDays', v)} label="提前天数" /><span className="vmo-unit">天</span></div>
    </VmoFsec>
  );
  const fallbackSec = (
    <VmoFsec key="fallback" title="到期回退" foot={f.fallback === 'proxy' ? '回退链会跳过停用或已过期的代理，所以它们不能选作备用。' : f.fallback === 'direct' ? '到期后把在用的账号改为直连，可在账号详情里“恢复原代理”。' : '到期后账号留在这个过期代理上，需要手动处理。'}>
      <div className="vmo-frow vmo-frow-full"><Segmented items={Object.entries(VMO_FALLBACK).map(([key, label]) => ({ key, label: key === 'proxy' ? '备用代理' : label }))} value={f.fallback} onChange={v => set('fallback', v)} /></div>
      {f.fallback === 'proxy' && <div className="vmo-frow vmo-frow-stack"><span className="vmo-flabel">备用代理</span><VmoChoice items={backupItems} value={f.backupId} onChange={v => set('backupId', v)} /></div>}
    </VmoFsec>
  );
  const statusSec = p && (
    <VmoFsec key="status" title="状态" foot={statusFoot}>
      <div className="vmo-frow vmo-frow-full"><Segmented items={[{ key: 'active', label: '正常' }, { key: 'inactive', label: '停用' }]} value={f.status} onChange={v => set('status', v)} /></div>
    </VmoFsec>
  );
  // renewing an expired proxy is the job at hand, so its expiry and status come first
  const order = wasExpired ? [expirySec, statusSec, fallbackSec, basics] : [basics, expirySec, fallbackSec, statusSec];
  return (
    <VmoSheet tall title={wasExpired ? '续期代理' : p ? '编辑代理' : '添加代理'} leading={{ label: '取消', onPress: ctx.closeSheet }} onDismiss={ctx.closeSheet} trailing={<VmoBarBtn label={wasExpired && !lapsedKeep ? '续期' : p ? '保存' : '添加'} onClick={save} disabled={!valid} />}>
      {wasExpired && <div className="vmo-sheet-target"><span>{p.name}</span><small>{vmoAddr(p)} · {p.accounts.length ? `${p.accounts.length} 个账号仍在用` : '没有账号在用'}</small></div>}
      {order}
    </VmoSheet>
  );
}

/* ====================================================================== */
/* ---------- 公告 ---------- */

function vmoInline(text) {
  const out = [];
  const re = /\*\*([^*]+)\*\*|\[([^\]]+)\]\(([^)]+)\)/g;
  let last = 0;
  let m;
  while ((m = re.exec(text))) {
    if (m.index > last) out.push(text.slice(last, m.index));
    out.push(m[1] ? <b key={m.index}>{m[1]}</b> : <span key={m.index} className="vmo-md-link">{m[2]}</span>);
    last = re.lastIndex;
  }
  if (last < text.length) out.push(text.slice(last));
  return out;
}

// Minimal Markdown (what the Web editor commonly produces): ## heading, - list, **bold**, [link](url), blank-line paragraphs.
function VmoMarkdown({ text, className }) {
  const blocks = [];
  let list = null;
  (text || '').split('\n').forEach(line => {
    if (/^- /.test(line)) {
      if (!list) { list = []; blocks.push({ type: 'ul', items: list }); }
      list.push(line.slice(2));
      return;
    }
    list = null;
    if (!line.trim()) return;
    if (/^#{1,3} /.test(line)) blocks.push({ type: 'h', text: line.replace(/^#{1,3} /, '') });
    else blocks.push({ type: 'p', text: line });
  });
  return (
    <div className={cx('vmo-md', className)}>
      {blocks.length === 0 && <p className="dim">还没有正文</p>}
      {blocks.map((b, i) => (b.type === 'ul'
        ? <ul key={i}>{b.items.map((it, j) => <li key={j}>{vmoInline(it)}</li>)}</ul>
        : b.type === 'h' ? <h4 key={i}>{vmoInline(b.text)}</h4> : <p key={i}>{vmoInline(b.text)}</p>))}
    </div>
  );
}

function vmoPublish(ctx, s, n) {
  ctx.confirm({
    title: `发布「${n.title}」？`,
    message: `${vmoTarget(n.target)} · ${n.notify === 'popup' ? '用户打开时弹窗提示' : '静默出现在通知里'}\n有效期 ${vmoRange(n)}`,
    actions: [
      { label: '发布', role: 'default', onPress: () => { vmoPatch(s, 'notices', n.id, { status: 'active', updatedAt: VMO_NOW }); ctx.showToast({ text: '已发布 · 符合条件的用户能看到', icon: 'megaphone' }); } },
      { label: '取消', role: 'cancel' },
    ],
  });
}

function vmoArchive(ctx, s, n) {
  vmoPatch(s, 'notices', n.id, { status: 'archived' });
  ctx.showToast({ text: '已归档 · 用户不再看到', icon: 'tray', tone: 'neutral', undo: () => vmoPatch(s, 'notices', n.id, { status: n.status }) });
}

// ⋯ of one announcement (a Menu spec): toolbar → ctx.menu, open inline card → VmoMoreBtn.
function vmoNoticeMenu(ctx, s, n, afterDelete) {
  return {
    title: n.title,
    message: `${VMO_NOTICE_STATUS[n.status].label} · ${VMO_NOTIFY[n.notify]}`,
    actions: [
      { label: '编辑公告', role: 'default', onPress: () => ctx.openSheet({ kind: 'announcementEdit', id: n.id }) },
      n.status === 'active'
        ? { label: '归档', role: 'default', onPress: () => vmoArchive(ctx, s, n) }
        : { label: n.status === 'draft' ? '发布' : '重新发布', role: 'default', onPress: () => vmoPublish(ctx, s, n) },
      ...(n.status !== 'draft' ? [{ label: '已读情况', role: 'default', onPress: () => ctx.push({ kind: 'announcementReads', id: n.id }) }] : []),
      { label: '删除公告…', role: 'destructive', onPress: () => confirmDelete(ctx, '公告', n.title, afterDelete, { remove: () => vmoRemove(s, 'notices', n.id) }) },
    ],
  };
}

function VmoNoticeSeg({ list, seg, setSeg }) {
  const n = k => list.filter(x => x.status === k).length;
  return (
    <div className="pad-x vmo-seg"><Segmented value={seg} onChange={setSeg} items={[
      { key: 'all', label: '全部', count: list.length },
      { key: 'active', label: '展示中', count: n('active') },
      { key: 'draft', label: '草稿', count: n('draft') },
      { key: 'archived', label: '已归档', count: n('archived') },
    ]} /></div>
  );
}

function VmoNoticeNav({ ctx, count }) {
  return <NavBar ctx={ctx} back title="公告" subtitle={`${ctx.site} · ${count} 条`} trailing={<GlassButton icon="compose" onClick={() => ctx.openSheet({ kind: 'announcementEdit' })} />} />;
}

// Row: title + status, who sees it, then how and when (notify_mode · starts_at – ends_at). No read counts: the list DTO has none.
function VmoNoticeHead({ n }) {
  return (
    <>
      <div className="row-top"><span className="row-title">{n.title}</span><VmoBadge {...VMO_NOTICE_STATUS[n.status]} /></div>
      <div className="row-meta vmo-ellip">{vmoTarget(n.target)}</div>
      <div className="row-meta vmo-when"><Icon name={n.notify === 'popup' ? 'megaphone' : 'bell'} size={12} weight={2.4} /><span className="num vmo-ellip">{VMO_NOTIFY[n.notify]} · {n.status === 'draft' ? `更新于 ${n.updatedAt}` : vmoRange(n)}</span></div>
    </>
  );
}

function VmoNoticeList({ ctx, route }) {
  const s = useVmo(ctx);
  const [seg, setSeg] = useState(route.seg || 'all');
  const list = s.data.notices;
  const rows = list.filter(n => seg === 'all' || n.status === seg);
  return (
    <Screen plain ctx={ctx} nav={<VmoNoticeNav ctx={ctx} count={list.length} />}>
      <VmoNoticeSeg list={list} seg={seg} setSeg={setSeg} />
      <div className="list-group">
        {rows.map(n => (
          <Row key={n.id} skin={ctx.skin} tone="none" className={cx(n.status === 'archived' && 'is-idle')} onClick={() => ctx.push({ kind: 'announcementDetail', id: n.id })}
            lead={<span className="lead-icon dim"><Icon name="megaphone" /></span>}>
            <VmoNoticeHead n={n} />
          </Row>
        ))}
        {rows.length === 0 && <div className="empty pad">没有这类公告</div>}
      </div>
    </Screen>
  );
}

// What end users see: popup = a centred card with a dismiss button; silent = an entry in the bell list.
function VmoNoticePreview({ n, compact }) {
  return (
    <div className={cx('vmo-pv', `is-${n.notify}`, compact && 'is-compact')}>
      <div className="vmo-pv-label"><Icon name={n.notify === 'popup' ? 'megaphone' : 'bell'} size={13} weight={2.4} />用户看到的样子 · {VMO_NOTIFY[n.notify]}</div>
      <div className={cx('vmo-pv-card', n.notify === 'silent' && 'tone-rail')}>
        <div className="vmo-pv-title">{n.title || '未命名公告'}</div>
        <VmoMarkdown text={n.content} />
        {n.notify === 'popup' && <div className="vmo-pv-btn">知道了</div>}
      </div>
    </div>
  );
}

function VmoNoticeActions({ ctx, s, n }) {
  return (
    <>
      {n.status === 'draft' && <VmoAct label="发布" icon="megaphone" primary onClick={() => vmoPublish(ctx, s, n)} />}
      {n.status === 'active' && <VmoAct label="归档" icon="tray" onClick={() => vmoArchive(ctx, s, n)} />}
      {n.status === 'archived' && <VmoAct label="重新发布" icon="megaphone" onClick={() => vmoPublish(ctx, s, n)} />}
      <VmoAct label="编辑" icon="compose" primary={n.status !== 'draft'} onClick={() => ctx.openSheet({ kind: 'announcementEdit', id: n.id })} />
    </>
  );
}

// One tappable row into the paginated per-user list; nothing is summarised because the API has no totals.
function VmoReadsLink({ ctx, n, skin }) {
  return (
    <Row skin={skin} tone="none" lead={<span className="lead-icon dim"><Icon name="people" /></span>} onClick={() => ctx.push({ kind: 'announcementReads', id: n.id })}>
      <div className="row-top"><span className="row-title">已读情况</span></div>
      <div className="row-meta">逐个用户看：是否符合条件、什么时候读的</div>
    </Row>
  );
}

function VmoNoticeDetail({ ctx, route }) {
  const s = useVmo(ctx);
  const { skin } = ctx;
  const n = s.data.notices.find(x => x.id === route.id);
  if (!n) return <VmoGone ctx={ctx} title="公告" />;
  return (
    <Screen ctx={ctx} nav={<NavBar ctx={ctx} back title="公告" subtitle={`${VMO_NOTICE_STATUS[n.status].label} · ${VMO_NOTIFY[n.notify]}`} trailing={<GlassButton icon="more" onClick={() => ctx.menu(vmoNoticeMenu(ctx, s, n, ctx.pop))} />} />}>
      <div className="detail-head">
        <VmoNoticePreview n={n} />
        <div className="actions"><VmoNoticeActions ctx={ctx} s={s} n={n} /></div>
      </div>
      <Section skin={skin} title="投放" index="壹">
        <div className="kv-grid pad vmo-kv-wrap">
          <KV label="可见对象" value={vmoTarget(n.target)} /><KV label="通知方式" value={VMO_NOTIFY[n.notify]} />
          <KV label="开始时间" value={<span className="num">{n.startsAt || '立即'}</span>} /><KV label="结束时间" value={<span className="num">{n.endsAt || '永久'}</span>} />
        </div>
        {n.status !== 'draft' && <VmoReadsLink ctx={ctx} n={n} skin={skin} />}
      </Section>
      <Section skin={skin} title="档案" index="贰">
        <div className="kv-grid pad">
          <KV label="创建时间" value={<span className="num">{n.createdAt}</span>} /><KV label="更新时间" value={<span className="num">{n.updatedAt}</span>} />
        </div>
      </Section>
    </Screen>
  );
}

const VMO_READ_SORT = [['email', '邮箱'], ['username', '用户名'], ['balance', '余额']];

// Mirrors Web's AnnouncementReadStatusDialog: search + paginated List of every user, sortable by email / username / balance
// (server-side); each row shows balance, 符合条件 / 不符合, and read_at or 未读. No read / unread filter: the API has none.
function VmoNoticeReads({ ctx, route }) {
  const s = useVmo(ctx);
  const n = s.data.notices.find(x => x.id === route.id);
  const [q, setQ] = useState('');
  const [sort, setSort] = useState(route.sort || 'email');
  const [menu, setMenu] = useState(null);
  if (!n) return <VmoGone ctx={ctx} title="已读情况" />;
  const key = q.trim().toLowerCase();
  const rows = vmoReadRows(n)
    .filter(r => !key || r.email.toLowerCase().includes(key) || r.username.toLowerCase().includes(key))
    .sort((a, b) => (sort === 'balance' ? b.balance - a.balance : String(a[sort]).localeCompare(String(b[sort]), 'zh')));
  const openSort = el => setMenu({ ...vmoAnchor(el, true), items: VMO_READ_SORT.map(([k, label]) => ({ key: k, label: `按${label}`, sub: k === 'balance' ? '从高到低' : '升序', on: sort === k, onPress: () => setSort(k) })) });
  return (
    <Screen plain ctx={ctx} nav={<NavBar ctx={ctx} back title="已读情况" subtitle={n.title} />}>
      <label className="search-field vmo-search"><Icon name="search" size={16} /><input value={q} placeholder="搜索邮箱或用户名" onChange={e => setQ(e.target.value)} aria-label="搜索用户" /></label>
      <div className="vmo-reads-bar">
        <span className="num">{key ? `找到 ${rows.length} 位` : `第 1 页 · 共 ${fmt.grouped(VMO_READ_TOTAL)} 位用户`}</span>
        <button className="vmo-sort-btn" onClick={e => openSort(e.currentTarget)} aria-haspopup="menu"><Icon name="sort" size={15} weight={2.4} />按{VMO_READ_SORT.find(([k]) => k === sort)[1]}<Icon name="chevronDown" size={12} weight={2.6} /></button>
      </div>
      <div className="list-group">
        {rows.map(r => (
          <Row key={r.id} skin={ctx.skin} tone="none" className={cx(!r.eligible && 'is-idle')} lead={<span className="avatar">{r.username.slice(0, 1)}</span>} onClick={() => ctx.push({ kind: 'user', id: r.id })}>
            <div className="row-top"><span className="row-title vmo-ellip">{r.email}</span><span className="row-right num vmo-bal">{fmt.money(r.balance)}</span></div>
            <div className="row-foot">
              <span className="row-meta vmo-ellip">{r.username}</span>
              <span className="vmo-read-state">
                {r.eligible ? <VmoBadge tone="ok" label="符合条件" /> : <VmoBadge tone="neutral" label="不符合" />}
                <span className={cx('num', r.readAt ? 'vmo-read-at' : 'dim')}>{r.readAt || '未读'}</span>
              </span>
            </div>
          </Row>
        ))}
        {rows.length === 0 && <div className="empty pad">没有匹配的用户</div>}
      </div>
      {!key && <div className="vmo-more-row"><span className="vmo-spinner" aria-hidden="true" />滚到底自动加载下一页</div>}
      <VmoMenu menu={menu} onClose={() => setMenu(null)} />
    </Screen>
  );
}

function VmoNoticeInline({ ctx, route }) {
  const s = useVmo(ctx);
  const [seg, setSeg] = useState(route.seg || 'all');
  const [open, setOpen] = useState(route.open ?? null);
  const list = s.data.notices;
  const rows = list.filter(n => seg === 'all' || n.status === seg);
  return (
    <Screen ctx={ctx} nav={<VmoNoticeNav ctx={ctx} count={list.length} />}>
      <VmoNoticeSeg list={list} seg={seg} setSeg={setSeg} />
      <div className="vmo-cards">
        {rows.map(n => {
          const isOpen = open === n.id;
          return (
            <VmoCard key={n.id} open={isOpen} onToggle={() => setOpen(isOpen ? null : n.id)} idle={n.status === 'archived'}
              lead={<span className="lead-icon dim"><Icon name="megaphone" /></span>} head={<VmoNoticeHead n={n} />}>
              <VmoNoticePreview n={n} compact />
              {n.status !== 'draft' && (
                <button className="vmo-inline-link" onClick={() => ctx.push({ kind: 'announcementReads', id: n.id })}>
                  <Icon name="people" size={17} /><span>已读情况<small>逐个用户看是否已读</small></span><Icon name="chevron" size={13} weight={2.6} />
                </button>
              )}
              <div className="vmo-card-actions">
                <VmoNoticeActions ctx={ctx} s={s} n={n} />
                <VmoMoreBtn menu={() => vmoNoticeMenu(ctx, s, n, () => setOpen(null))} />
              </div>
            </VmoCard>
          );
        })}
        {rows.length === 0 && <div className="empty pad">没有这类公告</div>}
      </div>
    </Screen>
  );
}

const VMO_NOTICE_COND = { type: 'balance', op: 'lt', value: '5', groups: [VMO_SUB_GROUPS[0]] };
const VMO_NOTICE_BLANK = { title: '', content: '', notify: 'silent', targetMode: 'all', cond: VMO_NOTICE_COND, startMode: 'now', startAt: '2026-10-17T09:00', endMode: 'forever', endAt: '2026-10-23T23:59' };
const vmoCondFrom = c => (c.type === 'subscription' ? { ...VMO_NOTICE_COND, type: 'subscription', groups: c.groups } : { ...VMO_NOTICE_COND, type: 'balance', op: c.op, value: String(c.value) });
const vmoCondTo = c => (c.type === 'subscription' ? { type: 'subscription', groups: c.groups } : { type: 'balance', op: c.op, value: Number(c.value) || 0 });
const VMO_WEEK = '日一二三四五六';

// SwiftUI DatePicker(.compact): two grey capsules (date, time). The native input sits invisibly on top to edit.
function VmoDateTime({ value, onChange, label }) {
  const [d, t] = value.split('T');
  const day = new Date(`${d}T00:00:00Z`);
  return (
    <span className="vmo-dt" role="group" aria-label={label}>
      <label className="vmo-dt-cap num">{`${day.getUTCMonth() + 1}月${day.getUTCDate()}日 周${VMO_WEEK[day.getUTCDay()]}`}<input type="date" value={d} onChange={e => e.target.value && onChange(`${e.target.value}T${t}`)} aria-label={`${label}日期`} /></label>
      <label className="vmo-dt-cap num">{t}<input type="time" value={t} onChange={e => e.target.value && onChange(`${d}T${e.target.value}`)} aria-label={`${label}时间`} /></label>
    </span>
  );
}

// Form rows "开始：立即 | 指定时间" / "结束：永久 | 指定时间"; 立即 / 永久 send starts_at / ends_at as empty.
function VmoWhenRow({ label, mode, setMode, at, setAt, empty }) {
  return (
    <div className="vmo-frow vmo-when-row">
      <div className="vmo-when-top">
        <span className="vmo-flabel">{label}</span>
        <span className="vmo-when-seg"><Segmented items={[{ key: empty[0], label: empty[1] }, { key: 'at', label: '指定时间' }]} value={mode} onChange={setMode} /></span>
      </div>
      {mode === 'at' && <VmoDateTime value={at} onChange={setAt} label={label} />}
    </div>
  );
}

// Targeting on the phone: 所有用户, or ONE condition (订阅套餐 in … / 余额 比较 金额). Multi-condition rules stay read-only
// here and are edited on Web (research/02 suggests the phone mainly publishes, archives and checks reads).
function VmoTargetFields({ f, set, complex }) {
  const c = f.cond;
  const setCond = (k, v) => set('cond', { ...c, [k]: v });
  if (f.targetMode !== 'custom') return null;
  if (complex) {
    return (
      <>
        {f.target.map((g, gi) => (
          <div key={gi} className="vmo-frow vmo-cond">
            <span className="vmo-cond-or">{gi === 0 ? '条件' : '或'}</span>
            <span className="vmo-cond-text">{g.map(vmoCond).join(' 且 ')}</span>
          </div>
        ))}
      </>
    );
  }
  return (
    <>
      <div className="vmo-frow vmo-frow-full"><Segmented items={[{ key: 'subscription', label: '订阅套餐' }, { key: 'balance', label: '余额' }]} value={c.type} onChange={v => setCond('type', v)} /></div>
      {c.type === 'subscription' ? (
        <div className="vmo-frow vmo-frow-stack"><span className="vmo-flabel vmo-flabel-w">持有以下任一套餐</span><VmoChoice multi items={VMO_SUB_GROUPS.map(g => [g, g])} value={c.groups} onChange={v => setCond('groups', v)} /></div>
      ) : (
        <div className="vmo-frow vmo-cond-bal">
          <span className="vmo-flabel">余额</span>
          <VmoChoice items={Object.entries(VMO_OPS).filter(([k]) => k !== 'eq').map(([k, sym]) => [k, sym])} value={c.op} onChange={v => setCond('op', v)} />
          <span className="vmo-cur-s">$</span>
          <input className="num vmo-cond-amt" inputMode="decimal" value={c.value} placeholder="0.00" aria-label="余额阈值" onChange={e => setCond('value', e.target.value.replace(/[^\d.]/g, '').slice(0, 8))} />
        </div>
      )}
    </>
  );
}

function VmoNoticeEdit({ ctx, sheet }) {
  const s = useVmo(ctx);
  const n = sheet.id ? s.data.notices.find(x => x.id === sheet.id) : null;
  const complex = Boolean(n && !vmoSimpleTarget(n.target));
  const [mode, setMode] = useState(sheet.mode || 'edit');
  const [f, setF] = useState(() => (n
    ? { title: n.title, content: n.content, notify: n.notify, targetMode: n.target ? 'custom' : 'all', target: n.target, cond: n.target && !complex ? vmoCondFrom(n.target[0][0]) : VMO_NOTICE_COND,
      startMode: n.startsAt ? 'at' : 'now', startAt: n.startsAt ? vmoIso(n.startsAt) : VMO_NOTICE_BLANK.startAt, endMode: n.endsAt ? 'at' : 'forever', endAt: n.endsAt ? vmoIso(n.endsAt) : VMO_NOTICE_BLANK.endAt }
    : { ...VMO_NOTICE_BLANK, ...(sheet.draft || {}) }));
  const ref = useRef(null);
  const set = (k, v) => setF(x => ({ ...x, [k]: v }));
  const live = n && n.status === 'active';
  const condOk = f.targetMode === 'all' || complex || (f.cond.type === 'subscription' ? f.cond.groups.length > 0 : Number(f.cond.value) > 0);
  const rangeOk = !(f.startMode === 'at' && f.endMode === 'at' && f.endAt <= f.startAt);
  const valid = f.title.trim() && f.content.trim() && condOk && rangeOk;
  const insert = (before, after, sample) => {
    const el = ref.current;
    const a = el ? el.selectionStart : f.content.length;
    const b = el ? el.selectionEnd : f.content.length;
    const sel = f.content.slice(a, b) || sample;
    set('content', f.content.slice(0, a) + before + sel + after + f.content.slice(b));
    requestAnimationFrame(() => { if (el) { el.focus(); el.setSelectionRange(a + before.length, a + before.length + sel.length); } });
  };
  const record = status => ({
    title: f.title.trim(), content: f.content, notify: f.notify,
    target: f.targetMode === 'all' ? null : complex ? f.target : [[vmoCondTo(f.cond)]],
    startsAt: f.startMode === 'at' ? vmoStamp(f.startAt) : null, endsAt: f.endMode === 'at' ? vmoStamp(f.endAt) : null,
    status, updatedAt: VMO_NOW,
  });
  const save = status => {
    if (n) vmoPatch(s, 'notices', n.id, record(status));
    else vmoSet(s, 'notices', list => [{ id: Math.max(...list.map(x => x.id)) + 1, ...record(status), createdAt: VMO_NOW }, ...list]);
    ctx.closeSheet();
    ctx.showToast({ text: status === 'active' ? (live ? '已保存 · 用户看到的是新内容' : '已发布公告') : '已存为草稿', icon: status === 'active' ? 'megaphone' : 'compose' });
  };
  const publish = () => {
    const r = record('active');
    ctx.confirm({
      title: `发布「${r.title}」？`,
      message: `${vmoTarget(r.target)} · ${r.notify === 'popup' ? '用户打开时弹窗提示' : '静默出现在通知里'}\n有效期 ${vmoRange(r)}`,
      actions: [{ label: '发布', role: 'default', onPress: () => save('active') }, { label: '取消', role: 'cancel' }],
    });
  };
  const targetFoot = f.targetMode === 'all' ? '所有用户都能看到。'
    : complex ? '这条公告的条件有多组 / 多条，手机上只读；要修改请在 Web 编辑。'
      : '手机上设一个条件；多个条件组合请在 Web 编辑。';
  return (
    <VmoSheet tall title={n ? '编辑公告' : '新建公告'} leading={{ label: '取消', onPress: ctx.closeSheet }} onDismiss={ctx.closeSheet}
      trailing={<VmoBarBtn label={live || (n && n.status === 'archived') ? '保存' : '存草稿'} disabled={!valid} onClick={() => save(live ? 'active' : n ? n.status === 'archived' ? 'archived' : 'draft' : 'draft')} />}>
      <Segmented items={[{ key: 'edit', label: '编辑' }, { key: 'preview', label: '预览' }]} value={mode} onChange={setMode} />
      {mode === 'edit' ? (
        <>
          <VmoFsec title="内容" foot="支持 Markdown：**粗体**、- 列表、## 小标题、[链接](地址)。">
            <input className="vmo-title-input" value={f.title} placeholder="标题" onChange={e => set('title', e.target.value)} />
            <div className="vmo-md-tools" role="toolbar" aria-label="格式">
              <button onClick={() => insert('**', '**', '粗体')} aria-label="粗体"><VmoIcon name="bold" size={17} weight={2.3} /></button>
              <button onClick={() => insert('\n- ', '', '列表项')} aria-label="列表"><VmoIcon name="bullets" size={17} weight={2.3} /></button>
              <button onClick={() => insert('\n## ', '', '小标题')} aria-label="小标题"><VmoIcon name="heading" size={17} weight={2.3} /></button>
              <button onClick={() => insert('[', '](https://)', '链接文字')} aria-label="链接"><VmoIcon name="link" size={17} weight={2.3} /></button>
              <span className="vmo-md-count num">{f.content.length} 字</span>
            </div>
            <textarea ref={ref} className="vmo-textarea" value={f.content} placeholder="写点什么…" onChange={e => set('content', e.target.value)} />
          </VmoFsec>
          <VmoFsec title="可见对象" foot={targetFoot}>
            <div className="vmo-frow vmo-frow-full"><Segmented items={[{ key: 'all', label: '所有用户' }, { key: 'custom', label: '按条件' }]} value={f.targetMode} onChange={v => set('targetMode', v)} /></div>
            <VmoTargetFields f={f} set={set} complex={complex} />
          </VmoFsec>
          <VmoFsec title="通知方式" foot={f.notify === 'popup' ? '弹窗模式会自动弹出通知给用户。' : '静默：只出现在用户的通知列表里。'}>
            <div className="vmo-frow vmo-frow-full"><Segmented items={[{ key: 'silent', label: '静默' }, { key: 'popup', label: '弹窗' }]} value={f.notify} onChange={v => set('notify', v)} /></div>
          </VmoFsec>
          <VmoFsec title="有效期" foot={rangeOk ? '立即 = 开始时间留空；永久 = 结束时间留空。时间按本机时区。' : '结束时间要晚于开始时间。'}>
            <VmoWhenRow label="开始" mode={f.startMode} setMode={v => set('startMode', v)} at={f.startAt} setAt={v => set('startAt', v)} empty={['now', '立即']} />
            <VmoWhenRow label="结束" mode={f.endMode} setMode={v => set('endMode', v)} at={f.endAt} setAt={v => set('endAt', v)} empty={['forever', '永久']} />
          </VmoFsec>
        </>
      ) : (
        <VmoNoticePreview n={{ title: f.title, content: f.content, notify: f.notify }} />
      )}
      {!live && <button className="submit" disabled={!valid} onClick={publish}>{n && n.status === 'archived' ? '重新发布' : '发布'}</button>}
    </VmoSheet>
  );
}

/* ---------- registration ---------- */

mvRegister('screen:redeem', 'base', VmoRedeemList);
mvRegister('screen:redeem', 'inline', VmoRedeemInline);
mvRegister('screen:redeemDetail', 'base', VmoRedeemDetail);
mvRegister('sheet:redeemGenerate', 'base', VmoGenForm);
mvRegister('sheet:redeemGenerate', 'steps', VmoGenSteps);
mvRegister('sheet:redeemEdit', 'base', VmoRedeemEdit);
mvRegister('sheet:redeemReconcile', 'base', VmoReconcileSheet);
mvRegister('sheet:redeemGrant', 'base', VmoGrantSheet);

mvRegister('screen:proxies', 'base', VmoProxyList);
mvRegister('screen:proxies', 'inline', VmoProxyInline);
mvRegister('screen:proxyDetail', 'base', VmoProxyDetail);
mvRegister('sheet:proxyEdit', 'base', VmoProxyEdit);

mvRegister('screen:announcements', 'base', VmoNoticeList);
mvRegister('screen:announcements', 'inline', VmoNoticeInline);
mvRegister('screen:announcementDetail', 'base', VmoNoticeDetail);
mvRegister('screen:announcementReads', 'base', VmoNoticeReads);
mvRegister('sheet:announcementEdit', 'base', VmoNoticeEdit);
