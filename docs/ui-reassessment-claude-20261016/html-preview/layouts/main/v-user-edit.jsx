/* 第 3 轮 · 新建用户（screen:userNew，用户页右上 +）与编辑用户（screen:userEdit，用户详情 ⋯ → 编辑用户，route.id）。
   已定（DECISIONS 第 3 轮 Q13–Q15，v-decided 设默认）：tabs「分段」+ ueKeys 'cards'「可展开卡片」；Key 的新建 / 停用 / 删除保留虚线“需后端新增”占位。
   没选中的 base / lean / rows 保留给对比页快照（main-r3.html 不含 v-decided，仍以 base + rows 为默认）。
   保存 / 创建失败：客户端校验与服务器拒绝（409 EMAIL_EXISTS、不能降级最后一个管理员）都标在字段上，tabs 跳到出错的那一段并滚到那一行。
   新建与编辑共用同一结构，三种结构：
   base「分组表单」：一个 Form。顶部通行证卡随滚动离开；要“保存”的 Section 在上，分隔标题“以下操作立即生效”之下是余额、API Key、平台限额、替换分组。
   tabs「分段」：固定身份条（余额大字 + 角色 / 状态徽章 + 充值 / 退款）+ 自定义分段「基础 | 权限与并发 | Key 与限额」。前两段要保存，第三段立即生效。
         表单滚动或输入框获得焦点（键盘弹出）时，身份条收成一行（姓名 + 余额 + 充值 / 退款），分段下的说明行收起，分段始终吸顶；回到顶部再展开。
         “立即生效”只在 Key 与限额段首说一次。新建时只有前两段，底部“下一步 / 创建用户”。
   lean「只放要保存的」：编辑页只有“保存”会提交的字段（约 2 屏，base 的保存区同长、全页约 3.4 屏）；余额、Key、平台限额、替换分组、只读的 RPM 状态留在用户详情页。
   三种结构都：隐藏 Tab 栏（.toolbar(.hidden, for: .tabBar)）；分区头写“已改 n 项 / n 项要修改”，改动行左侧琥珀条、错误行红条。
   开关（initial.v）：ueKeys 'rows'（列表行 + 详情 sheet，默认）| 'cards'（可展开卡片），与结构无关；ueKeyGap 'hide' 去掉“需后端新增”的占位；
   ueNoTotp true 演示管理员自己没开二次验证。route 演示参数：seg（tabs 初始分段）、focus（base 滚到某区）、sheet（打开某个 sheet）、draft（预填改动）。
   字段与接口（不虚构，见 research/02 §1.2、§3.2、§3.4 与后端 handler/admin/user_handler.go、apikey_handler.go、service/admin_user.go）：
   - “保存”= PUT admin/users/:id：email、username、password（留空不改）、notes、role、status、concurrency（adjustment_notes 只写进并发流水）、rpm_limit、
     allowed_groups、restrict_public_groups、group_rates（专属倍率，公开分组也能设，精度 0.001）；自定义属性 PUT :id/attributes。
     设为管理员需要 step-up（TOTP，user_handler.go:357-369），没开二次验证时后端拒绝（Web stepUp.notEnabled）；
     不能降级自己 / 最后一个管理员（user_handler.go:347-350、admin_user.go:177）；管理员不能禁用、不能删除（admin_user.go:461-467）。
   - 新建 = POST admin/users：email、password（≥6）、username、notes、role（admin 需 step-up）、balance（可选，留空按站点默认）、concurrency、rpm_limit、
     allowed_groups、restrict_public_groups。专属倍率、平台限额、Key 要等用户创建后才能设。
   - 立即生效：POST :id/replace-group（迁移绑定旧分组的 Key）；PUT :id/platform-quotas（nil = 不限，0 = 禁止该平台，>0 = 上限；user_handler.go:855-858）、
     POST :id/platform-quotas/reset；PUT admin/api-keys/:id（group_id：0 = 解绑；reset_rate_limit_usage = true 重置 5h/1d/7d 用量）；余额走已定的大数字键盘。
   - 只读：GET :id/rpm-status；GET :id/api-keys（status active / disabled / quota_exhausted / expired、quota（0 = 不限）/ quota_used、rate_limit_5h/1d/7d（0 = 不限）
     与 usage_*、reset_*_at、ip_whitelist / ip_blacklist、current_concurrency、last_used_at / last_used_ip）。
   - 后端缺口：管理端没有替用户新建 / 停用 / 删除 Key 的接口。界面画成虚线占位并标“需后端新增”，点了只弹说明，不给成功回执。
   演示数据：分组读 DEMO.groups（专属 / 公开 = 状态正常的标准分组，同 Web）；当前管理员读 DEMO.me；Key 读 DEMO.users[].keys（状态、额度、
   今日都来自 DEMO.keys，本文件只补有效期、IP、速率限制等明细）；订阅读 DEMO.subscriptions（activeSubscription）。保存与立即生效的操作写回
   ctx.users（keys 保持 DEMO 的形状、主 Key 分组、u.ue 资料），用户详情和再次打开的编辑页一致。
   新建成功 → 进入新用户详情，回执不给撤销（撤回只能删除用户，那是 ⋯ 里需确认的操作）。
   文案对齐 Web：专属分组 / 公开分组、专属倍率、限制可访问的公开分组、替换分组、平台限额、重置该窗口、并发调整备注、速率限制、Key 状态 活跃 / 已停用 / 额度耗尽 / 已过期。 */

/* ---------- demo data (field names follow admin user / api-key / platform-quota DTOs) ---------- */

// Groups are DEMO.groups (AdminGroup). The allowed-groups editor lists active standard groups only (Web UserAllowedGroupsModal), and
// replace-group only accepts an active exclusive standard target (admin_group.go ReplaceUserGroup). A key may be bound to any active
// group (PUT admin/api-keys/:id); a subscription group needs the user's active subscription of it.
const ueBySort = (a, b) => a.sortOrder - b.sortOrder;
const UE_CONFIG_GROUPS = DEMO.groups.filter(g => g.status === 'active' && g.subscriptionType === 'standard').sort(ueBySort);
const UE_EXCLUSIVE = UE_CONFIG_GROUPS.filter(g => g.exclusive);
const UE_PUBLIC = UE_CONFIG_GROUPS.filter(g => !g.exclusive);
const UE_PUBLIC_IDS = UE_PUBLIC.map(g => g.id);
// Exclusive groups that are subscription groups (企业专线): the group pages tag them “专属”, but allowed_groups does not grant them — a user
// gets one through an active subscription (admin/subscriptions assign, Web 订阅管理). The editor says so wherever such a group is missing.
const UE_SUB_EXCLUSIVE = DEMO.groups.filter(g => g.status === 'active' && g.exclusive && g.subscriptionType === 'subscription').sort(ueBySort);
const UE_SUB_NOTE = UE_SUB_EXCLUSIVE.length ? `${UE_SUB_EXCLUSIVE.map(g => g.name).join('、')}是订阅分组，要在 Web 的订阅管理里开通。` : '';
const UE_KEY_GROUPS = DEMO.groups.filter(g => g.status === 'active').sort(ueBySort);
const ueGroup = id => (id == null ? null : groupOf(id));
const ueGroupName = id => (id == null ? '不绑定分组' : (ueGroup(id) || { name: '—' }).name);
const ueGroupNames = ids => ids.map(ueGroupName).join('、');
const ueIsSelf = u => Boolean(u && DEMO.me && u.id === DEMO.me.id);
const ueAdminCount = ctx => Object.values(ctx.users).filter(x => x.role === 'admin').length;
// Emails are unique per site; the check is the server's (409 EMAIL_EXISTS), mirrored here so the demo can show the failure.
const ueEmailTaken = (ctx, email, selfId) => {
  const e = (email || '').trim().toLowerCase();
  return Boolean(e) && Object.values(ctx.users).some(x => x.id !== selfId && (x.email || '').toLowerCase() === e);
};
// Site setting default_balance, used when “初始余额” is left empty (admin_user.go CreateUser). The demo site's default is 0.
const UE_SITE_DEFAULT_BALANCE = 0;
// Every concrete platform, in domain.ConcretePlatformIDs() display order (domain/platforms.go:38-50).
const UE_QUOTA_PLATFORMS = ['Anthropic', 'OpenAI', 'Gemini', 'Antigravity', 'Grok', 'Kimi', '智谱 GLM', 'DeepSeek', 'MiniMax', 'OpenCode', 'TypeSafe / Jev', 'Command Code', 'Cline'];
const UE_WINDOWS = [{ key: 'd', label: '日' }, { key: 'w', label: '周' }, { key: 'm', label: '月' }];
const UE_RL_WINDOWS = [{ key: 'h5', label: '5 小时' }, { key: 'd1', label: '1 天' }, { key: 'd7', label: '7 天' }];
// api_keys.status: the words are core's KEY_STATUS_WORD (Web's), active reads 活跃; the tone is this file's.
const UE_KEY_TONE = { active: 'ok', disabled: 'neutral', quota_exhausted: 'caution', expired: 'neutral' };
const ueKeyStatus = k => ({ label: KEY_STATUS_WORD[k.status] || '活跃', tone: UE_KEY_TONE[k.status] || 'neutral' });
const UE_ROLES = [{ key: 'user', label: '用户' }, { key: 'vendor', label: '供应商' }, { key: 'admin', label: '管理员' }];
const UE_ROLE_LABEL = Object.fromEntries(UE_ROLES.map(r => [r.key, r.label]));
// Site-defined user attributes (admin/user-attributes). Values are read and written with GET / PUT users/:id/attributes.
const UE_ATTRS = [
  { key: 'company', name: '公司', type: 'text' },
  { key: 'source', name: '来源', type: 'select', options: ['官网注册', '渠道商', '老客户介绍'] },
];
const UE_PASSWORDS = ['Qm7v-Tr2p-Hx9k', 'Lw4n-Bz8e-Pc3r', 'Ds6h-Kv2m-Yt5q'];
const UE_NUM = /^\d+(\.\d+)?$/;
const UE_RATE = /^\d+(\.\d{1,3})?$/;
const UE_NO_RL = { h5: { limit: 0, used: 0 }, d1: { limit: 0, used: 0 }, d7: { limit: 0, used: 0 } };
const UE_SEGS = [{ key: 'basic', label: '基础' }, { key: 'access', label: '权限与并发' }, { key: 'keys', label: 'Key 与限额' }];

// What GET admin/users/:id (+ rpm-status, platform-quotas) returns beyond DEMO.users; subscriptions are DEMO.subscriptions.
// allowed = allowed_groups ids: exclusive ones show as 专属分组 — every user holding a key in an exclusive standard group has it
// (陈思远 #5, 林一 #8 and Atlas #22 have Claude Code 组 keys); public ones only count while restrict_public_groups is on (same as Web).
// rates = group_rates: only in groups the user has no key in, because DEMO bills every request at the group's rate (std = actual ÷ rate).
// rpmNow.groups is used per group id this minute (only keys used this minute count: 王小明「默认」刚刚, Studio-K「生产」刚刚; the site does
// 46 a minute in all); rpmNow.overrides = the group page's per-user RPM overrides (groups/:id/rpm-overrides).
// Platform-quota usage agrees with DEMO: today = the user's keys today by platform (王小明 高级组「默认」2.80 + GLM「脚本」0.44 = 3.24),
// this month = the user's month (86.10).
const UE_PROFILES = {
  1: {
    notes: '老客户', active: '2 分钟前', attrs: { company: '', source: '老客户介绍' },
    allowed: [5], rates: { 2: 1.3 }, rpm: 60,
    rpmNow: { used: 2, groups: { 1: 2 }, overrides: { 1: 30 } },
    quotas: [
      { platform: 'Anthropic', d: { used: 2.8, limit: 10, reset: '明天 00:00' }, w: { used: 17.4, limit: 50, reset: '周一 00:00' }, m: { used: 80.4, limit: 100 } },
      { platform: '智谱 GLM', d: { used: 0.44, limit: 5, reset: '明天 00:00' }, w: { used: 1.2, limit: null }, m: { used: 5.7, limit: null } },
    ],
  },
  // Restricted to two public groups; its 企业专线 keys ride on its active subscription (#88).
  3: {
    notes: '团队账号，月结', active: '刚刚', attrs: { company: 'Studio-K', source: '渠道商' },
    allowed: [1, 2], restrictPublic: true, rates: { 2: 0.9 }, rpm: 300,
    rpmNow: { used: 4, groups: { 1: 4 }, overrides: {} },
    quotas: [
      { platform: 'Anthropic', d: { used: 64.3, limit: 80, reset: '明天 00:00' }, w: { used: 402, limit: 500, reset: '周一 00:00' }, m: { used: 1530, limit: null } },
      { platform: 'Gemini', d: { used: 0, limit: 0 }, w: { used: 0, limit: null }, m: { used: 0, limit: null } },
    ],
  },
  // DEMO.me, the signed-in admin: cannot demote themselves, admins cannot be disabled or deleted.
  5: { notes: '运营负责人', active: '刚刚', attrs: { company: '本站', source: '' }, allowed: [5] },
  8: { notes: 'Claude Code 试用', active: '13 分钟前', allowed: [5] },
  22: { allowed: [5] },
};

// Fields of GET :id/api-keys that DEMO.keys does not carry (expiry, IP rules, live concurrency, rate limits), by key id. Rate-limit
// usage is actual cost: the 5-hour window lies inside today, so it never exceeds the key's today (王小明「默认」2.80).
const UE_KEY_DETAIL = {
  4087: { ip: '203.0.113.24', conc: 1, rl: { h5: { limit: 5, used: 2.1, reset: '11:20' }, d1: { limit: 20, used: 9.4, reset: '明天 08:02' }, d7: { limit: 0, used: 0 } } },
  4099: { expires: '2026-12-31', ip: '198.51.100.7', allow: ['198.51.100.0/24'] },
};

// The keys are DEMO.users[].keys (DEMO.keys: id, label, masked, used = last used, group / groupId, status, quota, quotaUsed, today);
// UE_KEY_DETAIL adds the rest, k.ue holds what the editor wrote back (rate-limit usage after a reset).
function ueKeysOf(u) {
  return (u.keys || []).map(k => ({
    expires: null, ip: null, conc: 0, rl: UE_NO_RL, allow: [], deny: [],
    ...(UE_KEY_DETAIL[k.id] || {}), ...(k.ue || {}),
    id: k.id, name: k.label, masked: k.masked, last: k.used || null, group: k.groupId ?? null,
    status: k.status, quota: k.quota || 0, quotaUsed: k.quotaUsed || 0, today: k.today,
  }));
}

// users[].group is the group of the user's main key. The keys come oldest first, so the main one is found by that group
// (Studio-K: 生产, its newest), not by position.
const ueMainKeyId = u => { const k = u && (u.keys || []).find(x => x.group === u.group); return k ? k.id : null; };
// Old demo states (the frozen r3 deck) open a key sheet by the editor's former id, user id × 100 + position (101 = 王小明「默认」).
function ueRouteSheet(sheet, u, keys) {
  if (!sheet || sheet.kid == null || keys.some(k => k.id === sheet.kid)) return sheet || null;
  const k = u && Math.floor(sheet.kid / 100) === u.id ? keys[(sheet.kid % 100) - 1] : null;
  return k ? { ...sheet, kid: k.id } : sheet;
}

// Every user gets a full editable profile; seeds and earlier saves (u.ue) layer over the defaults.
function ueProfile(u) {
  const p = {
    notes: '', active: '—', attrs: { company: '', source: '' }, allowed: [], rates: {}, restrictPublic: false, rpm: 0,
    rpmNow: { used: 0, groups: {}, overrides: {} }, quotas: [],
    ...(UE_PROFILES[u.id] || {}), ...(u.ue || {}),
  };
  return {
    ...p,
    role: u.role || 'user',
    self: ueIsSelf(u),
    exclusive: p.allowed.filter(id => UE_EXCLUSIVE.some(g => g.id === id)),
    publicAllowed: p.restrictPublic ? p.allowed.filter(id => UE_PUBLIC_IDS.includes(id)) : UE_PUBLIC_IDS,
    keys: ueKeysOf(u),
    // users/:id/subscriptions: platform quotas do not bind requests billed to an active subscription.
    activeSubs: subscriptionsOf(u.id).filter(s => s.status === 'active'),
  };
}

const UE_BLANK = { email: '', username: '', password: '', notes: '', attrs: { company: '', source: '' }, role: 'user', status: 'active', conc: 1, concNote: '', rpm: 0, exclusive: [], rates: {}, restrictPublic: false, publicAllowed: UE_PUBLIC_IDS, balance: '' };

// conc stays null when the user record has none (shown as —, never guessed).
function ueDraftOf(u, p) {
  if (!u) return UE_BLANK;
  return { ...UE_BLANK, email: u.email, username: u.name, notes: p.notes, attrs: p.attrs, role: p.role, status: u.status, conc: u.conc ?? null, rpm: p.rpm, exclusive: p.exclusive, rates: p.rates, restrictPublic: p.restrictPublic, publicAllowed: p.publicAllowed };
}

// What a save or an immediate action leaves on ctx.users, so the detail page and a reopened editor agree: the keys (in the shape of
// DEMO.users[].keys, group by name and id), the main key's group, and the saved profile. allowed_groups is built like Web's payload
// (exclusive + restricted public). quotaUsed only exists on a limited key, as in DEMO.keys.
function ueKeyRecord(k) {
  const g = k.group == null ? null : ueGroup(k.group);
  return {
    id: k.id, label: k.name, masked: k.masked, used: k.last, group: g ? g.name : null, groupId: g ? g.id : null,
    status: k.status, quota: k.quota, ...(k.quota > 0 ? { quotaUsed: k.quotaUsed } : {}), today: k.today,
    ue: { rl: k.rl },
  };
}
function ueStored(u, saved, keys, quotas, mainKeyId) {
  const main = keys.find(k => k.id === mainKeyId);
  return {
    ...(u && (u.keys || keys.length) ? { keys: keys.map(ueKeyRecord) } : {}),
    ...(main && main.group != null ? { group: ueGroupName(main.group) } : {}),
    ue: {
      notes: saved.notes, attrs: saved.attrs, rates: saved.rates, rpm: saved.rpm, restrictPublic: saved.restrictPublic, quotas,
      allowed: [...saved.exclusive, ...(saved.restrictPublic ? saved.publicAllowed : [])],
    },
  };
}

// Fields that “保存” / “创建” submits: name in prompts, and the tabs segment that holds them. concNote rides along with conc and is not a change by itself.
const UE_FIELDS = {
  email: { label: '邮箱', seg: 'basic' }, username: { label: '用户名', seg: 'basic' }, notes: { label: '备注', seg: 'basic' }, attrs: { label: '自定义属性', seg: 'basic' },
  password: { label: '密码', seg: 'basic' }, status: { label: '状态', seg: 'basic' }, balance: { label: '初始余额', seg: 'basic' },
  role: { label: '角色', seg: 'access' }, exclusive: { label: '专属分组', seg: 'access' }, rates: { label: '专属倍率', seg: 'access' },
  restrictPublic: { label: '公开分组', seg: 'access' }, publicAllowed: { label: '公开分组', seg: 'access' }, conc: { label: '并发数', seg: 'access' }, rpm: { label: 'RPM 上限', seg: 'access' },
};

function ueValidate(d, isNew) {
  const e = {};
  if (!d.email) e.email = '请输入邮箱';
  else if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(d.email)) e.email = '邮箱格式不对';
  if (isNew && !d.password) e.password = '请输入密码';
  else if (d.password && d.password.length < 6) e.password = '至少 6 位';
  if (isNew && d.balance && !UE_NUM.test(d.balance)) e.balance = '不是合法金额';
  return e;
}

const ueNorm = v => (Array.isArray(v) ? [...v].sort((a, b) => a - b) : v && typeof v === 'object' ? Object.keys(v).sort().map(k => [k, v[k]]) : v);
const ueSame = (a, b) => JSON.stringify(ueNorm(a)) === JSON.stringify(ueNorm(b));
const ueOmit = (obj, key) => Object.fromEntries(Object.entries(obj).filter(([k]) => Number(k) !== key));
const ueMoneyLim = v => fmt.money(v, { digits: Number.isInteger(v) ? 0 : 2 });
// Effective billing rate: the user's own rate when set, otherwise the group default.
function ueRateText(rates, gid) {
  const g = ueGroup(gid);
  if (!g) return '';
  return rates[gid] !== undefined ? `专属倍率 ×${rates[gid]}` : `默认 ×${g.rate}`;
}
function ueScrollTo(root, el) {
  const scroller = root && root.closest('.scroll');
  if (scroller && el) scroller.scrollTop += el.getBoundingClientRect().top - scroller.getBoundingClientRect().top - 8;
}

/* ---------- editor state shared by all layouts ---------- */

function useUeEditor(ctx, route, layout) {
  const isNew = route.kind === 'userNew';
  const u = isNew ? null : ctx.users[route.id];
  const [base] = useState(() => (isNew ? null : ueProfile(u)));
  const [original, setOriginal] = useState(() => ueDraftOf(u, base));
  const [draft, setDraft] = useState(() => ({ ...original, ...(route.draft || {}) }));
  const [keys, setKeys] = useState(() => (base ? base.keys : []));
  const [quotas, setQuotas] = useState(() => (base ? base.quotas : []));
  const [mainKeyId] = useState(() => ueMainKeyId(u));
  const [sheet, setSheet] = useState(() => ueRouteSheet(route.sheet, u, keys));
  const [showErrors, setShowErrors] = useState(Boolean(route.showErrors));
  const [applied, setApplied] = useState([]);
  const [startBalance] = useState(() => (u ? u.balance : 0));
  const [pwIndex, setPwIndex] = useState(0);
  // Errors the server returned for a value ({field: {value, msg}}); they hold while the field still has that value.
  const [serverErr, setServerErr] = useState({});
  // Where a failed save / create sends the eye (tabs: the segment holding the error), set by the caller of save / create.
  const jump = useRef(null);
  // Immediate actions are already on the server: mirror them onto the user record (keys, groups, quotas) as they happen.
  const mounted = useRef(false);
  useEffect(() => {
    if (!mounted.current) { mounted.current = true; return; }
    if (u) ctx.updateUser(u.id, ueStored(u, original, keys, quotas, mainKeyId));
  }, [keys, quotas, original]);
  const set = (k, v) => setDraft(d => ({ ...d, [k]: typeof v === 'function' ? v(d[k]) : v }));
  // A removed group's rate goes with it, so rates only count for groups still in use.
  const live = [...draft.exclusive, ...UE_PUBLIC_IDS];
  const ratesOf = r => Object.fromEntries(Object.entries(r).filter(([g]) => live.includes(Number(g))));
  const changed = Object.keys(UE_FIELDS).filter(k => (k === 'rates' ? !ueSame(ratesOf(draft.rates), ratesOf(original.rates)) : !ueSame(draft[k], original[k])));
  const fromServer = Object.fromEntries(Object.entries(serverErr).filter(([k, x]) => ueSame(draft[k], x.value)).map(([k, x]) => [k, x.msg]));
  const errors = { ...fromServer, ...ueValidate(draft, isNew) };
  const st = {
    ctx, u, base, isNew, layout, draft, original, setOriginal, setDraft, set, changed, errors, showErrors, setShowErrors, setServerErr, jump,
    keys, setKeys, quotas, setQuotas, mainKeyId, sheet, setSheet, applied, setApplied, startBalance,
    valid: Object.keys(errors).length === 0,
    self: Boolean(base && base.self),
    name: draft.username || (u && u.name) || (draft.email ? draft.email.split('@')[0] : '新用户'),
    changedLabels: [...new Set(changed.map(k => UE_FIELDS[k].label))],
    mark: k => (showErrors && errors[k] ? 'is-bad' : !isNew && changed.includes(k) ? 'is-dirty' : ''),
    boundTo: gid => keys.filter(k => k.group === gid).length,
    keysView: (ctx.v && ctx.v.ueKeys) || 'rows',
    showGap: !(ctx.v && ctx.v.ueKeyGap === 'hide'),
    nextPassword: () => { set('password', UE_PASSWORDS[pwIndex % UE_PASSWORDS.length]); setPwIndex(i => i + 1); },
  };
  return { ...st, ...ueFlowActions(st), ...ueImmediateActions(st) };
}

// Save / create / leave. Role → admin (or creating an admin) goes through TOTP step-up, then a final confirmation, like the backend requires.
function ueFlowActions(st) {
  const { ctx, u, isNew, draft, original, keys, quotas, name, mainKeyId } = st;
  const removed = original.exclusive.filter(g => !draft.exclusive.includes(g));
  const lost = keys.filter(k => removed.includes(k.group));
  const typed = draft.balance && UE_NUM.test(draft.balance) ? Number(draft.balance) : 0;
  // The request went out and the server refused one field: mark it, say why in the receipt, and send the eye to it.
  const refused = (k, msg, text) => {
    st.setServerErr(s => ({ ...s, [k]: { value: draft[k], msg } }));
    st.setShowErrors(true);
    ctx.showToast({ text, icon: 'octagon', tone: 'critical' });
    if (st.jump.current) st.jump.current({ [k]: msg });
  };
  // 409 EMAIL_EXISTS (user_repo.go: Create / Update translate the unique email index).
  const emailTaken = () => ueEmailTaken(ctx, draft.email, u && u.id);
  // PUT admin/users/:id. No undo in the receipt: putting the old values back is another full save, not a one-tap reversal.
  const commitSave = () => {
    if (emailTaken()) { refused('email', '已被其他用户使用', '保存失败：这个邮箱已被其他用户使用'); return; }
    // Demoting the site's last admin fails in the service (ensureNotLastAdmin); demoting yourself is refused earlier by the handler.
    if (original.role === 'admin' && draft.role !== 'admin' && ueAdminCount(ctx) <= 1) {
      refused('role', '站点只剩这一位管理员，不能降级', '保存失败：不能降级站点最后一个管理员');
      return;
    }
    const lostGroups = removed.filter(g => lost.some(k => k.group === g));
    const tail = lost.length ? `；绑定在「${ueGroupNames(lostGroups)}」的 ${lost.length} 个 Key 将无法调用` : '';
    ctx.updateUser(u.id, { name: draft.username || u.name, email: draft.email, status: draft.status, conc: draft.conc ?? u.conc, role: draft.role, ...ueStored(u, draft, keys, quotas, mainKeyId) },
      { text: `已保存 ${st.changedLabels.length} 项更改${tail}`, icon: lost.length ? 'clockAlert' : undefined, tone: lost.length ? 'caution' : undefined });
    ctx.pop();
  };
  // POST admin/users, then the new user's detail page (balance, keys and the ⋯ menu live there). The receipt has no undo: the only way
  // back is deleting the user, which stays a confirmed action in the ⋯ menu. Initial balance writes no balance-history entry.
  const commitCreate = () => {
    if (emailTaken()) { refused('email', '这个邮箱已被注册', '创建失败：这个邮箱已被注册'); return; }
    const nid = Math.max(...Object.keys(ctx.users).map(Number)) + 1;
    const balance = typed || (draft.balance ? 0 : UE_SITE_DEFAULT_BALANCE);
    ctx.updateUser(nid, { id: nid, name, email: draft.email, balance, today: 0, status: 'active', conc: draft.conc, role: draft.role, ledger: [], ...ueStored(null, draft, [], []) },
      { text: `已创建用户「${name}」${typed ? `，初始余额 ${fmt.money(typed)}` : ''}`, icon: 'checkCircle' });
    ctx.pop();
    ctx.push({ kind: 'user', id: nid });
  };
  const faceLine = ctx.faceId && typed > FACE_ID_LIMIT ? `\n超过 ${fmt.money(FACE_ID_LIMIT, { digits: 0 })}，确认后验证 Face ID。` : '';
  const money = typed ? `\n初始余额 ${fmt.money(typed)} · 站点 ${ctx.site}${faceLine}` : '';
  const confirmBalance = () => ctx.confirm({
    title: `创建「${name}」并入账 ${fmt.money(typed)}？`,
    message: `站点 ${ctx.site} · 初始余额 ${fmt.money(typed)}。创建时直接写入，不会出现在“充值与调整记录”里。${faceLine}`,
    actions: [{ label: `创建并入账 ${fmt.money(typed)}`, role: 'destructive', onPress: commitCreate }, { label: '取消', role: 'cancel' }],
  });
  // Called by the step-up sheet once the code is accepted: the backend still needs an explicit final confirmation.
  const afterStepUp = purpose => ctx.confirm({
    title: purpose === 'create' ? `创建管理员「${name}」？` : `把「${name}」设为管理员？`,
    message: `二次验证已通过。管理员可以管理全部账号、用户和资金。${purpose === 'create' ? money : `\n同时保存：${st.changedLabels.join('、')}`}`,
    actions: [
      { label: purpose === 'create' ? '创建管理员' : '设为管理员并保存', role: purpose === 'create' && typed ? 'destructive' : 'default', onPress: purpose === 'create' ? commitCreate : commitSave },
      { label: '取消', role: 'cancel' },
    ],
  });
  const guard = (onInvalid, proceed) => {
    st.jump.current = onInvalid || null;
    if (st.valid) { proceed(); return; }
    st.setShowErrors(true);
    ctx.showToast({ text: `还有 ${Object.keys(st.errors).length} 项需要填写或修改`, icon: 'clockAlert', tone: 'caution' });
    if (onInvalid) onInvalid(st.errors);
  };
  return {
    save: onInvalid => guard(onInvalid, () => (draft.role === 'admin' && original.role !== 'admin' ? st.setSheet({ kind: 'stepUp', purpose: 'save' }) : commitSave())),
    create: onInvalid => guard(onInvalid, () => {
      if (draft.role === 'admin') st.setSheet({ kind: 'stepUp', purpose: 'create' });
      else if (typed) confirmBalance();
      else commitCreate();
    }),
    afterStepUp,
    leave: () => {
      if (!st.changed.length) { ctx.pop(); return; }
      const done = [...st.applied, ...(u && ctx.users[u.id].balance !== st.startBalance ? ['余额'] : [])];
      ctx.confirm({
        title: isNew ? '放弃新建用户？' : '放弃未保存的更改？',
        message: isNew ? '已填写的内容不会保留。' : `${st.changedLabels.join('、')}还没保存，会被放弃。${done.length ? `\n已经立即生效、不会撤回：${done.join('、')}。` : ''}`,
        actions: [{ label: isNew ? '放弃' : '放弃更改', role: 'destructive', onPress: ctx.pop }, { label: '继续编辑', role: 'cancel' }],
      });
    },
  };
}

// Server-side actions that take effect at once (not part of “保存”). They move the saved baseline too, and are listed when leaving with unsaved edits.
function ueImmediateActions(st) {
  const { ctx, keys, setKeys, setOriginal, setDraft, original, setQuotas } = st;
  const note = text => st.setApplied(xs => (xs.includes(text) ? xs : [...xs, text]));
  const unnote = text => st.setApplied(xs => xs.filter(x => x !== text));
  const both = fn => { setOriginal(fn); setDraft(fn); };
  // The receipt outlives the page (back to the detail within 4 s), so undo also puts the user record back as it was before the action;
  // while the editor is still open its own state reverts too and the mirror effect writes the same thing again.
  const before = st.u ? { keys: st.u.keys, group: st.u.group, ue: st.u.ue } : null;
  const putBack = () => { if (before) ctx.updateUser(st.u.id, before); };
  return {
    // POST :id/replace-group: grants the new exclusive group, migrates keys bound to the old one, drops the old one (one transaction).
    // It only touches allowed groups and keys; group_rates rows stay, so the old group's own rate comes back with it.
    // Undo = the same call reversed (new → old): one request, it moves the same keys back and withdraws the new group.
    replaceGroup: (oldId, newId) => {
      const moved = keys.filter(k => k.group === oldId).map(k => k.id);
      const apply = (from, to) => {
        both(o => ({ ...o, exclusive: [...o.exclusive.filter(x => x !== from && x !== to), to] }));
        setKeys(ks => ks.map(k => (moved.includes(k.id) ? { ...k, group: to } : k)));
      };
      const label = `替换分组（${ueGroupName(oldId)} → ${ueGroupName(newId)}）`;
      apply(oldId, newId);
      note(label);
      ctx.showToast({ text: `分组替换成功，已迁移 ${moved.length} 个 Key`, icon: 'refresh', undo: () => { apply(newId, oldId); unnote(label); putBack(); } });
    },
    // PUT admin/api-keys/:id { group_id }: 0 unbinds; an exclusive standard group the user lacks is granted in the same transaction
    // (AutoGrantedGroupAccess, same as Web). Undo puts the key back; when a grant happened it also withdraws it with PUT users
    // { allowed_groups } — two requests, because the backend has no single reverse call.
    moveKey: (k, gid) => {
      if (k.group === gid) return;
      const g = gid == null ? null : ueGroup(gid);
      const grant = Boolean(g && g.exclusive && g.subscriptionType === 'standard' && !original.exclusive.includes(gid));
      const from = k.group;
      const label = `Key「${k.name}」换分组`;
      const setTo = (to, granted) => {
        setKeys(ks => ks.map(x => (x.id === k.id ? { ...x, group: to } : x)));
        if (grant) both(o => ({ ...o, exclusive: granted ? [...o.exclusive.filter(x => x !== gid), gid] : o.exclusive.filter(x => x !== gid) }));
      };
      setTo(gid, true);
      note(label);
      const text = !g ? `「${k.name}」已不绑定分组` : grant ? `已改到「${g.name}」，并为用户添加了这个分组` : `「${k.name}」已改到「${g.name}」`;
      ctx.showToast({ text, icon: 'group', undo: () => { setTo(from, false); unnote(label); putBack(); } });
    },
    // PUT admin/api-keys/:id { reset_rate_limit_usage: true }
    resetKeyRl: k => ctx.confirm({
      title: `重置「${k.name}」的速率限制用量？`,
      message: '5 小时、1 天、7 天三个窗口的已用额度会归零，立即生效，不能撤销。',
      actions: [
        { label: '重置用量', role: 'destructive', onPress: () => {
          setKeys(ks => ks.map(x => (x.id === k.id ? { ...x, rl: Object.fromEntries(Object.entries(x.rl).map(([w, v]) => [w, { ...v, used: 0 }])) } : x)));
          note(`「${k.name}」速率限制`);
          ctx.showToast({ text: '速率限制已重置' });
        } },
        { label: '取消', role: 'cancel' },
      ],
    }),
    // No admin endpoint creates, disables or deletes a user's key. Placeholders explain that instead of pretending to succeed.
    keyGap: what => ctx.confirm({
      title: `${what} 需要后端新增接口`,
      message: '管理员现在只能查看用户的 Key、换分组、重置速率限制。替用户新建、停用、删除 Key 要等后端加上管理接口；这里只是占位，不会执行任何操作。',
      actions: [{ label: '知道了', role: 'cancel' }],
    }),
    saveQuota: (platform, next) => {
      const prev = st.quotas;
      setQuotas(qs => {
        const rest = qs.filter(x => x.platform !== platform);
        if (!next) return rest;
        return qs.some(x => x.platform === platform) ? qs.map(x => (x.platform === platform ? next : x)) : [...qs, next];
      });
      const label = `平台限额（${platform}）`;
      note(label);
      ctx.showToast({ text: next ? `已更新 ${platform} 的平台限额` : `已取消 ${platform} 的平台限额`, undo: () => { setQuotas(prev); unnote(label); putBack(); } });
    },
    resetQuota: (platform, w, used) => ctx.confirm({
      title: `重置 ${platform} 的${w.label}用量？`,
      message: `${st.name}在 ${platform} 的${w.label}用量（${fmt.money(used)}）会归零。此操作立即生效。`,
      actions: [
        { label: '重置该窗口', role: 'destructive', onPress: () => {
          setQuotas(qs => qs.map(x => (x.platform === platform ? { ...x, [w.key]: { ...x[w.key], used: 0 } } : x)));
          note(`平台限额（${platform}）`);
          ctx.showToast({ text: `已重置 ${platform} ${w.label}用量` });
        } },
        { label: '取消', role: 'cancel' },
      ],
    }),
  };
}

function ueTopup(ctx, u) {
  const open = () => ctx.openSheet({ kind: 'keypad', userId: u.id, mode: 'topup' });
  if (!u.pending) { open(); return; }
  ctx.confirm({
    title: `上一笔 ${fmt.money(DEMO.pendingOp.amount)} 充值结果未确认`,
    message: '先核对可避免重复入账',
    actions: [{ label: '先核对', role: 'default', onPress: () => reconcileUser(ctx, u) }, { label: '仍要充值', onPress: open }, { label: '取消', role: 'cancel' }],
  });
}

/* ---------- form primitives (SwiftUI: Form / Section / LabeledContent / TextField / Toggle / Stepper / Picker) ---------- */

// Section header meta: unsaved and invalid counts, shaped differently (dot vs “!”), always with words.
function UeSecMeta({ ed, fields, dirty, fallback }) {
  const bad = ed.showErrors && fields ? fields.filter(k => ed.errors[k]).length : 0;
  const n = ed.isNew ? 0 : dirty ?? (fields ? new Set(fields.filter(k => ed.changed.includes(k)).map(k => UE_FIELDS[k].label)).size : 0);
  if (!bad && !n) return fallback || null;
  return (
    <span className="ue-secmeta">
      {bad > 0 && <span className="ue-flag is-bad"><UeBadMark size={16} />{bad} 项要修改</span>}
      {n > 0 && <span className="ue-flag is-dirty"><i aria-hidden="true" />已改 {n} 项</span>}
    </span>
  );
}

// `after` sits under the list and above the footnote (used for the dashed “需后端新增” placeholders).
function UeSec({ ed, title, fields, dirty, meta, foot, after, children, className, anchor }) {
  const { skin } = ed.ctx;
  return (
    <section className={cx('sec-wrap ue-sec', className)} data-ue={anchor}>
      {title && <skin.SectionHead title={title} meta={<UeSecMeta ed={ed} fields={fields} dirty={dirty} fallback={meta} />} />}
      <div className="sec">{children}</div>
      {after}
      {foot && <p className="ue-foot">{foot}</p>}
    </section>
  );
}

function UeBarBtn({ label, on, onClick }) {
  return <button className={cx('glass-btn glass-btn-text ue-bar-btn', on ? 'glass-prominent' : 'is-off')} onClick={onClick}><span>{label}</span></button>;
}

function UeText({ ed, k, label, placeholder, type = 'text' }) {
  const err = ed.showErrors && ed.errors[k];
  return (
    <label className={cx('ue-row ue-field', ed.mark(k))}>
      <span className="ue-label">{label}</span>
      <span className="ue-field-main">
        <input className="ue-input" type={type} value={ed.draft[k]} placeholder={placeholder} onChange={e => ed.set(k, e.target.value)} />
        {err && <span className="ue-err">{err}</span>}
      </span>
    </label>
  );
}

function UeNotes({ ed }) {
  return (
    <label className={cx('ue-row ue-field ue-area', ed.mark('notes'))}>
      <span className="ue-label">备注</span>
      <textarea className="ue-input" rows={2} value={ed.draft.notes} placeholder="仅管理员可见" onChange={e => ed.set('notes', e.target.value)} />
    </label>
  );
}

function UeAttrRows({ ed }) {
  return UE_ATTRS.map(a => {
    const v = ed.draft.attrs[a.key] || '';
    const dirty = !ed.isNew && v !== (ed.original.attrs[a.key] || '');
    if (a.type === 'select') {
      return (
        <button key={a.key} className={cx('ue-row', dirty && 'is-dirty')} onClick={() => ed.setSheet({ kind: 'attr', key: a.key })}>
          <span className="ue-label">{a.name}</span>
          <span className={cx('ue-row-main ue-pickval', !v && 'is-empty')}>{v || '未填'}</span>
          <Icon name="chevronDown" size={13} weight={2.6} />
        </button>
      );
    }
    return (
      <label key={a.key} className={cx('ue-row ue-field', dirty && 'is-dirty')}>
        <span className="ue-label">{a.name}</span>
        <span className="ue-field-main"><input className="ue-input" value={v} placeholder="选填" onChange={e => ed.set('attrs', x => ({ ...x, [a.key]: e.target.value }))} /></span>
      </label>
    );
  });
}

function UePassword({ ed }) {
  const [open, setOpen] = useState(ed.isNew || Boolean(ed.draft.password));
  const [shown, setShown] = useState(false);
  const err = ed.showErrors && ed.errors.password;
  if (!open) {
    return (
      <button className="ue-row" onClick={() => setOpen(true)}>
        <span className="ue-row-main"><span className="ue-row-title">重置密码</span></span>
        <span className="ue-val dim">不修改</span>
        <Icon name="chevronDown" size={13} weight={2.6} />
      </button>
    );
  }
  return (
    <>
      <label className={cx('ue-row ue-field', ed.mark('password'))}>
        <span className="ue-label">{ed.isNew ? '密码' : '新密码'}</span>
        <span className="ue-field-main">
          <input className={cx('ue-input', shown && 'mono')} type={shown ? 'text' : 'password'} value={ed.draft.password}
            placeholder={ed.isNew ? '必填，至少 6 位' : '留空则保持原密码'} onChange={e => ed.set('password', e.target.value)} />
          {err && <span className="ue-err">{err}</span>}
        </span>
        <button className="ue-mini" onClick={e => { e.preventDefault(); setShown(s => !s); }}>{shown ? '隐藏' : '显示'}</button>
      </label>
      <div className="ue-row ue-btnrow">
        <button className="ue-link" onClick={() => { ed.nextPassword(); setShown(true); }}><Icon name="refresh" size={15} weight={2.4} />生成随机密码</button>
        {ed.draft.password && <button className="ue-link" onClick={() => ed.ctx.showToast({ text: '密码已复制', icon: 'check', tone: 'neutral' })}>复制</button>}
        {!ed.isNew && <button className="ue-link is-quiet" onClick={() => { ed.set('password', ''); setOpen(false); }}>不修改</button>}
      </div>
    </>
  );
}

// SwiftUI: Picker(.segmented); options that are not allowed stay visible but disabled.
function UeSegmented({ items, value, onChange, label }) {
  return (
    <div className="seg ue-segc" role="radiogroup" aria-label={label}>
      {items.map(it => (
        <button key={it.key} role="radio" aria-checked={value === it.key} disabled={it.disabled} className={cx('seg-item', value === it.key && 'on')} onClick={() => onChange(it.key)}>{it.label}</button>
      ))}
    </div>
  );
}

function UeRole({ ed }) {
  const items = UE_ROLES.map(r => ({ ...r, disabled: ed.self && r.key !== 'admin' }));
  return (
    <div className={cx('ue-row ue-role', ed.mark('role'))}>
      <span className="ue-label">角色</span>
      <UeSegmented items={items} value={ed.draft.role} onChange={v => ed.set('role', v)} label="角色" />
    </div>
  );
}

function ueRoleFoot(ed) {
  const { draft, original, isNew, self } = ed;
  if (ed.showErrors && ed.errors.role) return <span className="ue-err-inline">{ed.errors.role}。要降级他，先把另一位用户设为管理员。</span>;
  if (self) return `这是你当前登录的账号（${DEMO.me.name}）：不能把自己降级，也不能禁用或删除。`;
  if (draft.role === 'admin' && original.role !== 'admin') return `${isNew ? '创建' : '保存'}时需要输入二次验证码，验证后再确认一次。`;
  if (original.role === 'admin' && draft.role !== 'admin') return '降级后会失去后台权限。如果他是站点最后一个管理员，保存会失败（后端：不能降级最后一个管理员）。';
  if (draft.role === 'vendor') return '供应商只能访问账号、代理、分组和用量，看不到用户与资金。';
  return null;
}

function UeSwitchRow({ title, sub, value, on, onToggle, locked, mark }) {
  return (
    <button className={cx('ue-row ue-switch-row', locked && 'is-locked', mark)} onClick={locked ? undefined : onToggle} aria-pressed={on} aria-disabled={locked}>
      <span className="ue-row-main"><span className="ue-row-title">{title}</span>{sub && <span className="ue-sub">{sub}</span>}</span>
      {value && <span className="ue-val">{value}</span>}
      <span className={cx('st-switch', on && 'on')}><i /></span>
    </button>
  );
}

function UeStatus({ ed }) {
  const on = ed.draft.status !== 'disabled';
  const locked = ed.original.role === 'admin';
  return (
    <UeSwitchRow title="状态" value={on ? '启用' : '禁用'} on={on} locked={locked} mark={ed.mark('status')}
      sub={locked ? '管理员不能禁用' : on ? '可以登录，Key 可以调用' : '不能登录，Key 调用会被拒绝'}
      onToggle={() => ed.set('status', on ? 'disabled' : 'active')} />
  );
}

function UeStepButtons({ onMinus, onPlus, minDisabled }) {
  return (
    <span className="ue-step">
      <button aria-label="减少" disabled={minDisabled} onClick={onMinus}><svg width="16" height="16" viewBox="0 0 24 24" aria-hidden="true"><path d="M5 12h14" stroke="currentColor" strokeWidth="2.4" strokeLinecap="round" /></svg></button>
      <i />
      <button aria-label="增加" onClick={onPlus}><Icon name="plus" size={16} weight={2.4} /></button>
    </span>
  );
}

// A value the record did not return (null) reads “—”; + starts it at one step.
function UeStepper({ ed, k, label, step = 1 }) {
  const v = ed.draft[k];
  const missing = v == null;
  return (
    <div className={cx('ue-row', ed.mark(k))}>
      <span className="ue-row-main"><span className="ue-row-title">{label}</span></span>
      <span className={cx('ue-val num', (missing || v === 0) && 'dim')}>{missing ? '—' : v === 0 ? '不限制' : v}</span>
      <UeStepButtons minDisabled={missing || v <= 0} onMinus={() => ed.set(k, Math.max(0, v - step))} onPlus={() => ed.set(k, missing ? step : v + step)} />
    </div>
  );
}

// Web: 并发调整备注（可选）— only sent when concurrency changes, written to the concurrency ledger, not to the profile.
function UeConcNote({ ed }) {
  if (ed.isNew || ed.draft.conc === ed.original.conc) return null;
  return (
    <label className="ue-row ue-field ue-indent">
      <span className="ue-label">调整备注</span>
      <span className="ue-field-main"><input className="ue-input" value={ed.draft.concNote} placeholder={`可选 · 并发 ${ed.original.conc ?? '—'} → ${ed.draft.conc} 的原因`} onChange={e => ed.set('concNote', e.target.value)} /></span>
    </label>
  );
}

function UeInitBalance({ ed }) {
  const err = ed.showErrors && ed.errors.balance;
  return (
    <label className={cx('ue-row ue-field', ed.mark('balance'))}>
      <span className="ue-label">初始余额</span>
      <span className="ue-field-main">
        <span className="ue-money-in is-inline"><span>$</span><input className="ue-input num" inputMode="decimal" value={ed.draft.balance} placeholder="留空按站点默认" onChange={e => ed.set('balance', e.target.value.replace(/[^\d.]/g, ''))} /></span>
        {err && <span className="ue-err">{err}</span>}
      </span>
    </label>
  );
}

function UeMeter({ used, limit }) {
  const r = limit ? used / limit : null;
  const level = r === null ? 'none' : r >= 0.9 ? 'critical' : r >= 0.75 ? 'caution' : 'normal';
  return <span className={cx('ue-track', `ue-lv-${level}`)}>{r !== null && <i style={{ width: `${Math.min(r, 1) * 100}%` }} />}</span>;
}

// One usage window. limit: null = 不限, 0 = 禁止（platform quotas only）, > 0 = 上限.
function UeWin({ label, win, showReset }) {
  const lim = win.limit;
  const banned = lim === 0;
  return (
    <span className="ue-win">
      <span className="ue-win-top"><small>{label}</small><span className={cx('num', banned && 'ue-ban')}>{banned ? '已禁止' : lim == null ? '不限' : `${Math.round((win.used / lim) * 100)}%`}</span></span>
      {banned ? <span className="ue-track ue-lv-ban" /> : <UeMeter used={win.used} limit={lim} />}
      <span className="ue-win-read num">{banned ? '不能使用' : lim == null ? `已用 ${fmt.money(win.used)}` : `${fmt.money(win.used)} / ${ueMoneyLim(lim)}`}</span>
      {showReset && lim > 0 && win.reset && <span className="ue-win-reset num">{win.reset} 重置</span>}
    </span>
  );
}

function UeBadges({ ed }) {
  const { ctx, u, isNew, draft, original } = ed;
  const { skin } = ctx;
  const status = isNew ? null : original.status === 'disabled' ? <skin.Badge tone="neutral" label="禁用" /> : <skin.Badge tone="ok" label="启用" />;
  return (
    <>
      <skin.Badge tone="neutral" label={UE_ROLE_LABEL[isNew ? draft.role : original.role]} />
      {status}
      {ed.self && <skin.Badge tone="neutral" label="你" />}
      {u && u.pending && <skin.Badge tone="caution" label="待核对" />}
    </>
  );
}

/* ---------- saved sections ---------- */

function UeAccountSec({ ed }) {
  return (
    <UeSec ed={ed} title="账户" fields={['email', 'username', 'notes', 'attrs']}>
      <UeText ed={ed} k="email" label="邮箱" type="email" placeholder="必填" />
      <UeText ed={ed} k="username" label="用户名" placeholder="选填" />
      <UeNotes ed={ed} />
      <UeAttrRows ed={ed} />
    </UeSec>
  );
}

function UeLoginSec({ ed, withStatus }) {
  return (
    <UeSec ed={ed} title={withStatus && !ed.isNew ? '登录与状态' : '登录'} fields={withStatus ? ['password', 'status'] : ['password']}>
      <UePassword ed={ed} />{withStatus && !ed.isNew && <UeStatus ed={ed} />}
    </UeSec>
  );
}

function UeRoleSec({ ed, withStatus }) {
  return (
    <UeSec ed={ed} title="权限" fields={withStatus ? ['role', 'status'] : ['role']} foot={ueRoleFoot(ed)}>
      <UeRole ed={ed} />{withStatus && !ed.isNew && <UeStatus ed={ed} />}
    </UeSec>
  );
}

function UeExclusiveSec({ ed }) {
  const { ctx, draft, original, isNew } = ed;
  const removed = original.exclusive.filter(g => !draft.exclusive.includes(g));
  const rowsChanged = isNew ? 0 : [...new Set([...draft.exclusive, ...original.exclusive])]
    .filter(g => !draft.exclusive.includes(g) || !original.exclusive.includes(g) || draft.rates[g] !== original.rates[g]).length;
  const restore = gid => {
    ed.set('exclusive', xs => [...xs, gid]);
    if (original.rates[gid] !== undefined) ed.set('rates', rs => ({ ...rs, [gid]: original.rates[gid] }));
  };
  // The site may have no active exclusive standard group at all: then there is nothing to grant, so say that instead of offering “添加”.
  // “没有可授予的” rather than “没有专属分组”: the group pages still show 企业专线 as 专属, it is just granted by subscription.
  if (!UE_EXCLUSIVE.length) {
    return (
      <UeSec ed={ed} title="专属分组" meta="0 个" foot="在 Web 的分组管理里把标准分组设为“专属”后，可以在这里授予给用户。">
        <div className="ue-row ue-dim-row">
          <span className="ue-row-main"><span className="ue-row-title">没有可授予的专属分组</span>{UE_SUB_NOTE && <span className="ue-sub">{UE_SUB_NOTE}</span>}</span>
        </div>
      </UeSec>
    );
  }
  const foot = `${isNew ? '专属倍率在创建后设置。' : '倍率、添加、移除在“保存”后生效。'}${UE_SUB_NOTE}`;
  return (
    <UeSec ed={ed} title="专属分组" dirty={rowsChanged} meta={`${draft.exclusive.length} 个`} foot={foot}>
      {draft.exclusive.map(gid => {
        const added = !original.exclusive.includes(gid);
        const dirty = !isNew && (added || draft.rates[gid] !== original.rates[gid]);
        const g = ueGroup(gid);
        return (
          <Row key={gid} skin={ctx.skin} tone="none" className={cx('ue-grow', dirty && 'is-dirty')} lead={<span className="lead-icon dim"><Icon name="group" /></span>} onClick={() => ed.setSheet({ kind: 'group', gid })}>
            <div className="row-top"><span className="row-title">{ueGroupName(gid)}</span><span className={cx('row-right num', draft.rates[gid] === undefined && 'is-dim')}>{ueRateText(draft.rates, gid)}</span></div>
            <div className="row-meta">{g ? `${g.platform} · ` : ''}{isNew ? '专属分组' : added ? '新添加 · 保存后生效' : `绑定 ${ed.boundTo(gid)} 个 Key`}</div>
          </Row>
        );
      })}
      {removed.map(gid => (
        <div key={`x${gid}`} className="ue-row ue-ghost is-dirty">
          <span className="ue-ghost-ico"><Icon name="minus" size={16} weight={2.4} /></span>
          <span className="ue-row-main"><span className="ue-row-title"><s>{ueGroupName(gid)}</s></span><span className="ue-sub">保存后移除{ed.boundTo(gid) ? ` · ${ed.boundTo(gid)} 个 Key 会无法调用` : ''}</span></span>
          <button className="ue-mini" onClick={() => restore(gid)}>撤回</button>
        </div>
      ))}
      {!draft.exclusive.length && !removed.length && <div className="ue-row ue-dim-row">没有专属分组</div>}
      <button className="ue-row ue-add" onClick={() => ed.setSheet({ kind: 'addGroup' })}><Icon name="plus" size={17} weight={2.4} />添加专属分组</button>
    </UeSec>
  );
}

// Turning the restriction off ticks every public group again (Web toggleRestrictPublicGroups), so a later “on” starts from all.
function UePublicSec({ ed }) {
  const { draft, original, isNew } = ed;
  const toggle = id => ed.set('publicAllowed', xs => (xs.includes(id) ? xs.filter(x => x !== id) : [...xs, id]));
  const toggleRestrict = () => {
    const next = !draft.restrictPublic;
    ed.set('restrictPublic', next);
    if (!next) ed.set('publicAllowed', UE_PUBLIC_IDS);
  };
  const rows = UE_PUBLIC.map(g => {
    const allowed = !draft.restrictPublic || draft.publicAllowed.includes(g.id);
    const dirty = !isNew && (draft.rates[g.id] !== original.rates[g.id] || (draft.restrictPublic && draft.publicAllowed.includes(g.id) !== original.publicAllowed.includes(g.id)));
    return { g, allowed, dirty };
  });
  const n = (isNew || draft.restrictPublic === original.restrictPublic ? 0 : 1) + rows.filter(r => r.dirty).length;
  const meta = draft.restrictPublic ? `可用 ${rows.filter(r => r.allowed).length} / ${rows.length}` : `${rows.length} 个`;
  return (
    <UeSec ed={ed} title="公开分组" dirty={n} meta={meta} foot={isNew ? '专属倍率在创建后设置。' : '点分组可以设专属倍率；留空用分组默认倍率。'}>
      <UeSwitchRow title="限制可访问的公开分组" sub={draft.restrictPublic ? '只能使用下面勾选的公开分组' : '关闭时可以使用全部公开分组'}
        on={draft.restrictPublic} mark={ed.mark('restrictPublic')} onToggle={toggleRestrict} />
      {rows.map(({ g, allowed, dirty }) => (
        <div key={g.id} className={cx('ue-row ue-prow', dirty && 'is-dirty', !allowed && 'is-off')}>
          {draft.restrictPublic
            ? <button className="ue-ring-btn" aria-pressed={allowed} aria-label={`${allowed ? '取消勾选' : '勾选'}${g.name}`} onClick={() => toggle(g.id)}><span className={cx('select-ring', allowed && 'on')}>{allowed && <Icon name="check" size={14} weight={3} />}</span></button>
            : <span className="ue-ring-btn is-static" aria-hidden="true"><Icon name="check" size={16} weight={2.6} /></span>}
          <button className="ue-prow-main" onClick={() => ed.setSheet({ kind: 'group', gid: g.id })}>
            <span className="ue-row-main"><span className="ue-row-title">{g.name}</span><span className="ue-sub">{g.platform}{draft.restrictPublic ? (allowed ? ' · 可以使用' : ' · 不能使用') : ''}</span></span>
            <span className={cx('ue-val num', draft.rates[g.id] === undefined && 'dim')}>{ueRateText(draft.rates, g.id)}</span>
            <Icon name="chevron" size={13} weight={2.6} />
          </button>
        </div>
      ))}
    </UeSec>
  );
}

// GET :id/rpm-status: the user-wide count, plus one line per group the user's keys are bound to. A group's line is limited by the
// user's override for that group (source override) or else the group's rpm_limit (source group; 0 = 不限).
function ueRpmGroups(ed) {
  const now = ed.base.rpmNow;
  const ids = [...new Set(ed.keys.map(k => k.group).filter(g => g != null))].sort((a, b) => a - b);
  return ids.map(id => {
    const g = ueGroup(id);
    const o = now.overrides[id];
    return { id, name: g ? g.name : '—', used: now.groups[id] || 0, limit: o != null ? o : g ? g.rpmLimit : 0, source: o != null ? 'override' : 'group' };
  });
}

function UeRpmNow({ ed }) {
  if (ed.isNew) return null;
  const r = ed.base.rpmNow;
  const limit = ed.original.rpm;
  return (
    <div className="ue-rpm">
      <div className="ue-rpm-top"><span>RPM 状态 · 本分钟</span><span className="num"><b>{r.used}</b> / {limit || '不限制'}</span></div>
      {limit > 0 && <UeMeter used={r.used} limit={limit} />}
      {ueRpmGroups(ed).map(g => (
        <div key={g.id} className="ue-rpm-g">
          <span>{g.name}</span><small>{g.source === 'override' ? '专属 RPM' : '分组 RPM'}</small>
          <span className="num">{g.used} / {g.limit || '不限'}</span>
        </div>
      ))}
    </div>
  );
}

// The user's rpm_limit is a hard cap on all of the user's requests per minute and always applies; group limits (or the user's
// per-group override) are checked first, per group (billing_cache_service.go checkRPM).
function UeLimitSec({ ed, noStatus }) {
  const noted = !ed.isNew && ed.draft.conc !== ed.original.conc;
  return (
    <UeSec ed={ed} title="并发与 RPM" fields={['conc', 'rpm']}
      foot={`0 = 不限制。RPM 上限是这个用户每分钟全部请求的总上限，始终生效；分组的 RPM 限制另外按分组计算。${noted ? '调整备注只写进这次的并发流水，不写进用户资料。' : ''}`}>
      <UeStepper ed={ed} k="conc" label="并发数" />
      <UeConcNote ed={ed} />
      <UeStepper ed={ed} k="rpm" label="RPM 上限" step={10} />
      {!noStatus && <UeRpmNow ed={ed} />}
    </UeSec>
  );
}

function UeInitBalanceSec({ ed }) {
  return <UeSec ed={ed} title="余额" fields={['balance']} foot="选填。填写后创建时会再确认一次金额；以后调整余额用充值键盘。"><UeInitBalance ed={ed} /></UeSec>;
}

/* ---------- immediate sections (no “保存”) ---------- */

function UeSubWarn() {
  return <div className="ue-warn tone-caution"><Icon name="clockAlert" size={16} /><span>此用户有活跃订阅：平台限额只在余额模式下生效，订阅模式的请求不受限额约束。</span></div>;
}

function UeQuotaSec({ ed }) {
  return (
    <UeSec ed={ed} title="平台限额" meta="日 · 周 · 月" anchor="quota" foot="留空 = 不限制，0 = 禁止使用该平台。月为 30 天滚动窗口。">
      {ed.base.activeSubs.length > 0 && <UeSubWarn />}
      {ed.quotas.map(q => (
        <button key={q.platform} className="ue-q" onClick={() => ed.setSheet({ kind: 'quota', platform: q.platform })}>
          <span className="ue-q-top"><span className="ue-row-title">{q.platform}</span>{UE_WINDOWS.some(w => q[w.key].limit === 0) && <ed.ctx.skin.Badge tone="critical" label="已禁止使用" />}<Icon name="chevron" size={13} weight={2.6} /></span>
          <span className="ue-q-grid">{UE_WINDOWS.map(w => <UeWin key={w.key} label={w.label} win={q[w.key]} />)}</span>
        </button>
      ))}
      {!ed.quotas.length && <div className="ue-row ue-dim-row">没有设置，各平台不限制</div>}
      <button className="ue-row ue-add" onClick={() => ed.setSheet({ kind: 'addQuota' })}><Icon name="plus" size={17} weight={2.4} />添加平台限额</button>
    </UeSec>
  );
}

function UeBalanceSec({ ed }) {
  const { ctx, u } = ed;
  return (
    <UeSec ed={ed} title="余额" anchor="balance" foot="充值、退款在大数字键盘里确认，立即入账。">
      <div className="ue-bal">
        <div className="ue-bal-top"><small>可用余额</small><span className="num">{fmt.money(u.balance)}</span></div>
        {u.pending && (
          <div className="ue-pending tone-caution">
            <Icon name="docCheck" size={16} />
            <span>上一笔 {fmt.money(DEMO.pendingOp.amount)} 充值结果待核对</span>
            <ActionButton small label="核对" onClick={() => reconcileUser(ctx, u)} />
          </div>
        )}
        <div className="actions">
          <ActionButton label="充值" icon="plus" primary={!u.pending} onClick={() => ueTopup(ctx, u)} />
          <ActionButton label="退款" icon="restore" onClick={() => ctx.openSheet({ kind: 'keypad', userId: u.id, mode: 'refund' })} />
        </div>
      </div>
    </UeSec>
  );
}

// Only users who hold an exclusive group have something to replace; the section is left out otherwise.
function UeReplaceSec({ ed }) {
  const owned = ed.original.exclusive;
  if (!owned.length) return null;
  return (
    <UeSec ed={ed} title="替换分组" anchor="replace" foot="把一个专属分组换成另一个：绑定的 Key 一起迁移，旧分组的权限随之移除。">
      {owned.map(gid => (
        <button key={gid} className="ue-row" onClick={() => ed.setSheet({ kind: 'replace', gid })}>
          <span className="ue-row-main"><span className="ue-row-title">替换「{ueGroupName(gid)}」…</span><span className="ue-sub">绑定 {ed.boundTo(gid)} 个 Key</span></span>
          <Icon name="chevron" size={13} weight={2.6} />
        </button>
      ))}
      {!owned.length && <div className="ue-row ue-dim-row">没有专属分组</div>}
    </UeSec>
  );
}

function UeKeyBadge({ ctx, k, always }) {
  const st = ueKeyStatus(k);
  return k.status === 'active' && !always ? null : <ctx.skin.Badge tone={st.tone} label={st.label} />;
}

// quota_used only grows while quota > 0 (gateway_usage_billing.go shouldDeductAPIKeyQuota): a limited key shows used / quota, an
// unlimited one has no “已用” and shows today's spend instead (dashboard/api-keys-usage).
const ueKeyQuota = k => `${fmt.money(k.quotaUsed)} / ${fmt.money(k.quota)}`;
const ueKeyUse = k => (k.quota > 0 ? ueKeyQuota(k) : `今日 ${fmt.money(k.today)}`);

// Placeholders for what the backend lacks (admin create / disable / delete of a user's key): a dashed group outside the real list,
// each row tagged “需后端新增”; tapping only explains, never a success receipt. Delete stays last, as the decided ⋯ rule will.
function UeGapRow({ ed, label, icon = 'plus' }) {
  return (
    <button className="ue-row ue-gap" onClick={() => ed.keyGap(label)} aria-label={`${label}，需后端新增，点按查看说明`}>
      <Icon name={icon} size={16} weight={2.4} />
      <span className="ue-row-main"><span className="ue-row-title">{label}</span></span>
      <span className="ue-gap-tag" aria-hidden="true">需后端新增</span>
    </button>
  );
}

function UeGaps({ ed, items }) {
  if (!ed.showGap) return null;
  return <div className="ue-gaps" role="group" aria-label="需后端新增的操作">{items.map(it => <UeGapRow key={it.label} ed={ed} {...it} />)}</div>;
}

function UeKeyRows({ ed }) {
  const { ctx } = ed;
  return (
    <>
      {ed.keys.map(k => (
        <Row key={k.id} skin={ctx.skin} tone="none" className={k.status !== 'active' ? 'is-idle' : ''} lead={<span className="lead-icon dim"><Icon name="key" /></span>}
          onClick={() => ed.setSheet({ kind: 'key', kid: k.id })}>
          <div className="row-top"><span className="ue-key-title"><span className="row-title">{k.name}</span><UeKeyBadge ctx={ctx} k={k} /></span><span className="row-right mono">{k.masked}</span></div>
          <div className="row-meta">{ueGroupName(k.group)} · {ueKeyUse(k)} · {k.last || '未使用'}</div>
        </Row>
      ))}
      {!ed.keys.length && <div className="ue-row ue-dim-row">还没有 Key，由用户自己在 Web 端创建</div>}
    </>
  );
}

function UeKeyLimits({ ed, k, plain }) {
  const any = UE_RL_WINDOWS.some(w => k.rl[w.key].limit > 0 || k.rl[w.key].used > 0);
  const wins = UE_RL_WINDOWS.map(w => ({ ...w, win: { ...k.rl[w.key], limit: k.rl[w.key].limit > 0 ? k.rl[w.key].limit : null } }));
  // Nothing set and nothing used: one line instead of three empty meters.
  if (!any) {
    return (
      <div className={cx('ue-rl is-none', !plain && 'ue-list')}>
        <div className="ue-rl-head"><span className="ue-row-title">速率限制</span><small>未设置</small></div>
        <div className="ue-rl-none">5 小时、1 天、7 天都不限额</div>
      </div>
    );
  }
  return (
    <div className={cx('ue-rl', !plain && 'ue-list')}>
      <div className="ue-rl-head"><span className="ue-row-title">速率限制</span><small>滚动窗口 · 0 = 不限</small></div>
      <div className="ue-q-grid">{wins.map(w => <UeWin key={w.key} label={w.label} win={w.win} showReset />)}</div>
      {!plain && <button className="ue-row ue-add" onClick={() => ed.resetKeyRl(k)}><Icon name="restore" size={16} weight={2.4} />重置速率限制用量</button>}
    </div>
  );
}

// ip_whitelist / ip_blacklist, worded like Web (IP 白名单 / IP 黑名单).
const ueIpRule = k => [k.allow.length ? `白名单 ${k.allow.join('、')}` : null, k.deny.length ? `黑名单 ${k.deny.join('、')}` : null].filter(Boolean).join(' · ') || '未设置';

function UeKeyFacts({ k }) {
  const ipRule = ueIpRule(k);
  return (
    <>
      <div className="ue-row"><span className="ue-row-main"><span className="ue-row-title">额度</span></span><span className="ue-val num">{k.quota > 0 ? ueKeyQuota(k) : '不限'}</span></div>
      <div className="ue-row"><span className="ue-row-main"><span className="ue-row-title">今日消费</span></span><span className="ue-val num">{fmt.money(k.today)}</span></div>
      <div className="ue-row"><span className="ue-row-main"><span className="ue-row-title">有效期</span></span><span className="ue-val num">{k.expires ? `至 ${k.expires}` : '永久有效'}</span></div>
      <div className="ue-row"><span className="ue-row-main"><span className="ue-row-title">当前并发</span></span><span className="ue-val num">{k.conc}</span></div>
      <div className="ue-row"><span className="ue-row-main"><span className="ue-row-title">最近使用</span></span><span className="ue-val num">{k.last || '—'}{k.ip ? ` · ${k.ip}` : ''}</span></div>
      <div className="ue-row"><span className="ue-row-main"><span className="ue-row-title">IP 限制</span></span><span className="ue-val num ue-wrapval">{ipRule}</span></div>
    </>
  );
}

function UeKeyCard({ ed, k, open, onToggle }) {
  const { ctx } = ed;
  const st = ueKeyStatus(k);
  const ipRule = ueIpRule(k);
  return (
    <article className={cx('ue-kc', open && 'is-open', k.status !== 'active' && 'is-idle', `tone-${st.tone}`)} data-kid={k.id}>
      <button className="ue-kc-top" onClick={onToggle} aria-expanded={open}>
        <span className="ue-kc-name"><b>{k.name}</b><UeKeyBadge ctx={ctx} k={k} /></span>
        <span className="mono ue-kc-mask">{k.masked}</span>
        <Icon name={open ? 'chevronUp' : 'chevronDown'} size={13} weight={2.6} />
      </button>
      <div className="ue-kc-use">
        <UeMeter used={k.quotaUsed} limit={k.quota > 0 ? k.quota : null} />
        <span className="num">{ueKeyUse(k)}</span>
        <span className="ue-kc-unl">{k.quota > 0 ? `${Math.round((k.quotaUsed / k.quota) * 100)}%` : '不限额度'}</span>
      </div>
      <div className="ue-kc-meta">{ueGroupName(k.group)}{k.group != null && ` · ${ueRateText(ed.original.rates, k.group)}`} · {k.last ? `最近使用 ${k.last}` : '未使用'}</div>
      {open && (
        <div className="ue-kc-more">
          <div className="kv-grid">
            <KV label="有效期" value={k.expires ? `至 ${k.expires}` : '永久有效'} />
            <KV label="当前并发" value={<span className="num">{k.conc}</span>} />
            <KV label="最近 IP" value={<span className="num">{k.ip || '—'}</span>} />
            <KV label="IP 限制" value={<span className="num">{ipRule}</span>} />
          </div>
          <UeKeyLimits ed={ed} k={k} plain />
          <div className="actions">
            <ActionButton label="换分组" icon="group" onClick={() => ed.setSheet({ kind: 'keyGroup', kid: k.id })} />
            {UE_RL_WINDOWS.some(w => k.rl[w.key].limit > 0 || k.rl[w.key].used > 0) && <ActionButton label="重置速率限制" icon="restore" onClick={() => ed.resetKeyRl(k)} />}
          </div>
          {ed.showGap && (
            <div className="ue-kc-gaps">
              <button className="ue-gap-chip" onClick={() => ed.keyGap('停用 Key')}><Icon name="pauseFill" size={14} />停用<span className="ue-gap-tag">需后端新增</span></button>
              <button className="ue-gap-chip" onClick={() => ed.keyGap('删除 Key')}><Icon name="close" size={14} />删除<span className="ue-gap-tag">需后端新增</span></button>
            </div>
          )}
        </div>
      )}
    </article>
  );
}

function UeKeySec({ ed }) {
  const { skin } = ed.ctx;
  const live = ed.keys.filter(k => k.status === 'active').length;
  const meta = ed.keys.length ? `${ed.keys.length} 个 · 活跃 ${live}` : '0 个';
  const [open, setOpen] = useState(ed.keys[0] ? ed.keys[0].id : null);
  const listRef = useRef(null);
  // One card open at a time. Opening one collapses the other, which can push the new card's head above the fold:
  // bring it back (SwiftUI: ScrollViewReader.scrollTo(id, anchor: .top) inside withAnimation).
  const toggle = id => {
    setOpen(o => (o === id ? null : id));
    setTimeout(() => {
      const card = listRef.current && listRef.current.querySelector(`[data-kid="${id}"]`);
      const scroller = card && card.closest('.scroll');
      if (card && scroller && card.getBoundingClientRect().top < scroller.getBoundingClientRect().top) ueScrollTo(listRef.current, card);
    }, 30);
  };
  if (ed.keysView === 'cards') {
    return (
      <section className="sec-wrap ue-sec ue-kcs" data-ue="keys" ref={listRef}>
        <skin.SectionHead title="API Key" meta={meta} />
        {ed.keys.map(k => <UeKeyCard key={k.id} ed={ed} k={k} open={open === k.id} onToggle={() => toggle(k.id)} />)}
        {!ed.keys.length && <div className="ue-empty-card"><b>还没有 Key</b><span>用户在 Web 端「API 密钥」里自己创建；创建后可以在这里换分组、重置速率限制。</span></div>}
        {ed.showGap && <button className="ue-kc-new" onClick={() => ed.keyGap('新建 Key')}><Icon name="plus" size={16} weight={2.4} />新建 Key<span className="ue-gap-tag">需后端新增</span></button>}
        <p className="ue-foot">换分组的回执里可以撤销；重置速率限制不能撤销。</p>
      </section>
    );
  }
  return (
    <UeSec ed={ed} title="API Key" meta={meta} anchor="keys" foot="点 Key 查看详情、换分组、重置速率限制。"
      after={<UeGaps ed={ed} items={[{ label: '新建 Key', icon: 'plus' }]} />}>
      <UeKeyRows ed={ed} />
    </UeSec>
  );
}

/* ---------- sheets (SwiftUI: .sheet with NavigationStack + toolbar 取消 / 完成) ---------- */

function UeRadio({ on }) {
  return <span className={cx('st-radio', on && 'on')}>{on && <Icon name="check" size={12} weight={3.2} />}</span>;
}

// Saved settings of one group: own rate (decimal, 0.001), public-group access, removal. Edits stay local until 完成.
function UeGroupSheet({ ed, gid }) {
  const { ctx, draft } = ed;
  const g = ueGroup(gid);
  const [rate, setRate] = useState(draft.rates[gid] === undefined ? '' : String(draft.rates[gid]));
  const [allowed, setAllowed] = useState(draft.publicAllowed.includes(gid));
  const bad = rate !== '' && (!UE_RATE.test(rate) || Number(rate) <= 0);
  const owned = g.exclusive && draft.exclusive.includes(gid);
  const bound = ed.isNew ? 0 : ed.boundTo(gid);
  const close = () => ed.setSheet(null);
  const done = () => {
    if (bad) return;
    ed.set('rates', rs => (rate === '' ? ueOmit(rs, gid) : { ...rs, [gid]: Number(rate) }));
    if (!g.exclusive && draft.restrictPublic) ed.set('publicAllowed', xs => (allowed ? [...xs.filter(x => x !== gid), gid] : xs.filter(x => x !== gid)));
    close();
  };
  const remove = () => { ed.set('exclusive', xs => xs.filter(x => x !== gid)); ed.set('rates', rs => ueOmit(rs, gid)); close(); };
  const askRemove = () => {
    if (!bound) { remove(); return; }
    const lean = ed.layout === 'lean';
    ctx.confirm({
      title: `移除「${g.name}」？`,
      message: lean
        ? `绑定在「${g.name}」的 ${bound} 个 Key 会无法调用。要保留它们，先取消，到用户详情页用“替换分组”把 Key 迁到新分组。`
        : `绑定在「${g.name}」的 ${bound} 个 Key 会无法调用。要保留请用替换分组。`,
      actions: [
        { label: '仍要移除', role: 'destructive', onPress: remove },
        ...(lean ? [] : [{ label: '改用替换分组', role: 'default', onPress: () => ed.setSheet({ kind: 'replace', gid }) }]),
        { label: '取消', role: 'cancel' },
      ],
    });
  };
  return (
    <Sheet title={g.name} onClose={close} trailing={<UeBarBtn label="完成" on={!bad} onClick={done} />}>
      <p className="ue-note">{g.exclusive ? '专属分组' : '公开分组'} · {g.platform} · 默认倍率 ×{g.rate}{bound ? ` · 绑定 ${bound} 个 Key` : ''}</p>
      <div className="ue-list">
        {!g.exclusive && draft.restrictPublic && <UeSwitchRow title="允许使用" sub={allowed ? '这个用户可以用这个公开分组' : '这个用户不能用这个公开分组'} on={allowed} onToggle={() => setAllowed(v => !v)} />}
        {ed.isNew ? <div className="ue-row ue-dim-row">专属倍率在创建后设置</div> : (
          <label className={cx('ue-qedit', bad && 'is-bad')}>
            <span className="ue-qedit-top">
              <span className="ue-row-main"><span className="ue-row-title">专属倍率</span><span className="ue-sub">只对这个用户生效</span></span>
              <span className={cx('ue-money-in', bad && 'is-bad')}><span>×</span><input className="num" inputMode="decimal" placeholder={`默认 ${g.rate}`} value={rate} onChange={e => setRate(e.target.value.replace(/[^\d.]/g, ''))} aria-label="专属倍率" /></span>
            </span>
            {bad && <span className="ue-err">要大于 0，最多 3 位小数</span>}
          </label>
        )}
        {rate !== '' && <button className="ue-row ue-add" onClick={() => setRate('')}><Icon name="restore" size={16} weight={2.4} />改回默认倍率 ×{g.rate}</button>}
      </div>
      {owned && <div className="ue-list"><button className="ue-row ue-add is-ink" onClick={askRemove}><Icon name="minus" size={16} weight={2.4} />移除这个专属分组</button></div>}
      <p className="ue-foot">{ed.isNew ? '按“完成”回到表单，创建时一起提交。' : '按“完成”回到表单，倍率与移除在“保存”后生效。'}</p>
    </Sheet>
  );
}

function UeAddGroupSheet({ ed }) {
  const [picked, setPicked] = useState([]);
  const options = UE_EXCLUSIVE.filter(g => !ed.draft.exclusive.includes(g.id));
  const done = () => { if (picked.length) ed.set('exclusive', xs => [...xs, ...picked]); ed.setSheet(null); };
  const toggle = id => setPicked(xs => (xs.includes(id) ? xs.filter(x => x !== id) : [...xs, id]));
  return (
    <Sheet title="添加专属分组" onClose={() => ed.setSheet(null)} trailing={<UeBarBtn label={picked.length ? `添加 ${picked.length} 个` : '添加'} on={picked.length > 0} onClick={done} />}>
      <div className="ue-list">
        {options.map(g => (
          <button key={g.id} className="ue-row ue-check" onClick={() => toggle(g.id)} aria-pressed={picked.includes(g.id)}>
            <span className={cx('select-ring', picked.includes(g.id) && 'on')}>{picked.includes(g.id) && <Icon name="check" size={14} weight={3} />}</span>
            <span className="ue-row-main"><span className="ue-row-title">{g.name}</span><span className="ue-sub">{g.platform} · 默认倍率 ×{g.rate}</span></span>
          </button>
        ))}
        {!options.length && <div className="ue-row ue-dim-row">没有其他可授予的专属分组</div>}
      </div>
      <p className="ue-foot">添加后要“保存”才生效。{UE_SUB_NOTE}</p>
    </Sheet>
  );
}

// POST :id/replace-group is immediate, so it confirms first and says what moves.
function UeReplaceSheet({ ed, gid }) {
  const { ctx } = ed;
  const g = ueGroup(gid);
  const [target, setTarget] = useState(null);
  const bound = ed.boundTo(gid);
  const options = UE_EXCLUSIVE.filter(x => !ed.original.exclusive.includes(x.id) && !ed.draft.exclusive.includes(x.id));
  const t = target && ueGroup(target);
  const go = () => ctx.confirm({
    title: `把「${g.name}」替换为「${t.name}」？`,
    message: `${ed.name}绑定在「${g.name}」的 ${bound} 个 Key 会迁移到「${t.name}」，并移除「${g.name}」的使用权限。立即生效，不经过“保存”。`,
    actions: [{ label: '确认替换', role: 'default', onPress: () => { ed.replaceGroup(gid, target); ed.setSheet(null); } }, { label: '取消', role: 'cancel' }],
  });
  return (
    <Sheet title="替换专属分组" onClose={() => ed.setSheet(null)}>
      <p className="ue-note">选择新分组替换「{g.name}」，将自动迁移绑定的 <b className="num">{bound}</b> 个 Key 并更新分组权限。</p>
      <div className="ue-list">
        {options.map(x => (
          <button key={x.id} className="ue-row ue-check" onClick={() => setTarget(x.id)}>
            <UeRadio on={target === x.id} />
            <span className="ue-row-main"><span className="ue-row-title">{x.name}</span><span className="ue-sub">{x.platform} · 专属分组 · 默认倍率 ×{x.rate}</span></span>
          </button>
        ))}
        {!options.length && <div className="ue-row ue-dim-row">没有其他可用的专属分组</div>}
      </div>
      <button className="submit" disabled={!t} onClick={go}>{t ? `替换为「${t.name}」` : '选择目标分组'}</button>
    </Sheet>
  );
}

function UeQuotaSheet({ ed, platform }) {
  const live = ed.quotas.find(q => q.platform === platform);
  const blank = { used: 0, limit: null };
  const q = live || { platform, d: blank, w: blank, m: blank };
  const [start] = useState(() => Object.fromEntries(UE_WINDOWS.map(w => [w.key, q[w.key].limit == null ? '' : String(q[w.key].limit)])));
  const [lim, setLim] = useState(start);
  const bad = UE_WINDOWS.filter(w => lim[w.key] !== '' && !UE_NUM.test(lim[w.key]));
  // 保存 stays off until a window really changes (the PUT would be a no-op otherwise).
  const dirty = UE_WINDOWS.some(w => (lim[w.key] === '' ? null : Number(lim[w.key])) !== (start[w.key] === '' ? null : Number(start[w.key])));
  const close = () => ed.setSheet(null);
  const save = () => {
    if (bad.length || !dirty) return;
    const next = { ...q, ...Object.fromEntries(UE_WINDOWS.map(w => [w.key, { ...q[w.key], limit: lim[w.key] === '' ? null : Number(lim[w.key]) }])) };
    ed.saveQuota(platform, UE_WINDOWS.every(w => next[w.key].limit === null) ? null : next);
    close();
  };
  return (
    <Sheet title={`${platform} 限额`} onClose={close} tall trailing={<UeBarBtn label="保存" on={!bad.length && dirty} onClick={save} />}>
      {ed.base.activeSubs.length > 0 && <UeSubWarn />}
      <p className="ue-note">留空 = 不限制；<b>0 = 禁止使用该平台</b>。月为 30 天滚动窗口。</p>
      <div className="ue-list">
        {UE_WINDOWS.map(w => {
          const win = q[w.key];
          const val = lim[w.key];
          const err = val !== '' && !UE_NUM.test(val);
          const zero = !err && val !== '' && Number(val) === 0;
          return (
            <div key={w.key} className={cx('ue-qedit', err && 'is-bad')}>
              <label className="ue-qedit-top">
                <span className="ue-row-title">{w.label}限额</span>
                <span className={cx('ue-money-in', err && 'is-bad')}><span>$</span><input className="num" inputMode="decimal" placeholder="不限制" value={val} aria-label={`${w.label}限额`}
                  onChange={e => setLim(s => ({ ...s, [w.key]: e.target.value.replace(/[^\d.]/g, '') }))} /></span>
              </label>
              {err && <span className="ue-err">不是合法数字</span>}
              {zero && <span className="ue-zero"><Icon name="octagon" size={14} />填 0 会完全禁止使用 {platform}，不论其他窗口</span>}
              {win.limit > 0 && <UeMeter used={win.used} limit={win.limit} />}
              <div className="ue-qedit-foot">
                <span className="num">已用 {fmt.money(win.used)}{win.limit > 0 ? (w.key === 'm' ? ' · 30 天滚动' : win.reset ? ` · ${win.reset} 重置` : '') : ''}</span>
                {live && win.limit != null && <button className="ue-mini" onClick={() => ed.resetQuota(platform, w, win.used)}>重置该窗口</button>}
              </div>
            </div>
          );
        })}
      </div>
      {bad.length > 0 && <p className="ue-err ue-err-note">以下字段填写不是合法数字，请修正后再保存：{bad.map(w => w.label).join('、')}</p>}
      {live && <div className="ue-list"><button className="ue-row ue-add is-ink" onClick={() => setLim({ d: '', w: '', m: '' })}><Icon name="close" size={15} weight={2.4} />清空三个窗口（取消这个平台的限额）</button></div>}
      <p className="ue-foot">保存和重置都立即生效。</p>
    </Sheet>
  );
}

function UeAddQuotaSheet({ ed }) {
  const options = UE_QUOTA_PLATFORMS.filter(p => !ed.quotas.some(q => q.platform === p));
  return (
    <Sheet title="添加平台限额" onClose={() => ed.setSheet(null)} tall>
      <div className="ue-list">
        {options.map(p => (
          <button key={p} className="ue-row" onClick={() => ed.setSheet({ kind: 'quota', platform: p })}>
            <span className="ue-row-main"><span className="ue-row-title">{p}</span></span>
            <Icon name="chevron" size={13} weight={2.6} />
          </button>
        ))}
      </div>
    </Sheet>
  );
}

// PUT admin/api-keys/:id { group_id }: first option unbinds (group_id = 0, Web “无”); then every active group. Rates shown are what the
// key is billed at. A subscription group needs the user's active subscription of it (else SUBSCRIPTION_REQUIRED), so it is disabled
// with the reason; an exclusive standard group the user lacks is granted along with the move; a public group the user is restricted
// from can be bound, but its calls would be refused, so the row says so.
function ueKeyGroupOption(ed, gid) {
  const g = gid == null ? null : ueGroup(gid);
  if (!g) return { g, sub: '这个 Key 不属于任何分组', blocked: false };
  const rate = ed.original.rates[gid] !== undefined ? `专属倍率 ×${ed.original.rates[gid]}` : `默认倍率 ×${g.rate}`;
  if (g.subscriptionType === 'subscription') {
    const has = Boolean(ed.u && activeSubscription(ed.u.id, gid));
    return { g, sub: has ? `${g.platform} · 订阅分组 · 有效订阅` : `${g.platform} · 订阅分组 · 需要这个分组的有效订阅`, blocked: !has };
  }
  const kind = g.exclusive ? '专属分组' : '公开分组';
  const grant = g.exclusive && !ed.original.exclusive.includes(gid) ? ' · 会同时授予这个分组' : '';
  const refused = !g.exclusive && ed.original.restrictPublic && !ed.original.publicAllowed.includes(gid) ? ' · 用户被限制，调用会被拒绝' : '';
  return { g, sub: `${g.platform} · ${kind} · ${rate}${grant}${refused}`, blocked: false };
}

function UeKeyGroupPick({ ed, k, onDone }) {
  return [null, ...UE_KEY_GROUPS.map(g => g.id)].map(gid => {
    const { g, sub, blocked } = ueKeyGroupOption(ed, gid);
    return (
      <button key={String(gid)} className={cx('ue-row ue-check', blocked && 'is-blocked')} disabled={blocked} aria-disabled={blocked}
        onClick={() => { ed.moveKey(k, gid); if (onDone) onDone(); }}>
        <UeRadio on={k.group === gid} />
        <span className="ue-row-main"><span className="ue-row-title">{g ? g.name : '不绑定分组'}</span><span className="ue-sub">{sub}</span></span>
      </button>
    );
  });
}

function UeKeySheet({ ed, kid }) {
  const { ctx } = ed;
  const k = ed.keys.find(x => x.id === kid);
  if (!k) return null;
  return (
    <Sheet title={`Key「${k.name}」`} onClose={() => ed.setSheet(null)} leadingLabel="关闭" tall>
      <div className="ue-keyhead"><span className="mono">{k.masked}</span><UeKeyBadge ctx={ctx} k={k} always /></div>
      <div className="ue-list">
        <button className="ue-row ue-keygroup" onClick={() => ed.setSheet({ kind: 'keyGroup', kid: k.id, back: true })}>
          <span className="ue-row-main"><span className="ue-row-title">分组</span><span className="ue-sub">{k.group == null ? '未绑定' : ueRateText(ed.original.rates, k.group)}</span></span>
          <span className="ue-val">{ueGroupName(k.group)}</span>
          <Icon name="chevron" size={13} weight={2.6} />
        </button>
        <UeKeyFacts k={k} />
      </div>
      <UeKeyLimits ed={ed} k={k} />
      <UeGaps ed={ed} items={[{ label: '停用 Key', icon: 'pauseFill' }, { label: '删除 Key', icon: 'close' }]} />
      <p className="ue-foot">换分组、重置用量立即生效，不需要保存；换分组的回执里可以撤销。</p>
    </Sheet>
  );
}

// The group choice for one key. From the key sheet it is pushed inside the sheet (SwiftUI: NavigationLink in the sheet's stack), so
// “返回” and a pick both go back to the key; from a card it is its own sheet.
function UeKeyGroupSheet({ ed, kid, back }) {
  const k = ed.keys.find(x => x.id === kid);
  if (!k) return null;
  const close = () => ed.setSheet(back ? { kind: 'key', kid } : null);
  return (
    <Sheet title={`换分组 · ${k.name}`} onClose={close} leadingLabel={back ? '返回' : '取消'} tall>
      <div className="ue-list"><UeKeyGroupPick ed={ed} k={k} onDone={close} /></div>
      <p className="ue-foot">选中即生效；回执里可以撤销。</p>
    </Sheet>
  );
}

function UeAttrSheet({ ed, attrKey }) {
  const def = UE_ATTRS.find(a => a.key === attrKey);
  const cur = ed.draft.attrs[attrKey] || '';
  const pick = v => { ed.set('attrs', a => ({ ...a, [attrKey]: v })); ed.setSheet(null); };
  return (
    <Sheet title={def.name} onClose={() => ed.setSheet(null)}>
      <div className="ue-list">
        {def.options.map(o => (
          <button key={o} className="ue-row ue-check" onClick={() => pick(o)}><UeRadio on={cur === o} /><span className="ue-row-main"><span className="ue-row-title">{o}</span></span></button>
        ))}
        <button className="ue-row ue-check" onClick={() => pick('')}><UeRadio on={!cur} /><span className="ue-row-main"><span className="ue-row-title">不填</span></span></button>
      </div>
      <p className="ue-foot">选项由站点的用户属性定义（在 Web 端维护）。</p>
    </Sheet>
  );
}

// Step-up: 6-digit TOTP (SwiftUI TextField + .textContentType(.oneTimeCode), submits when full) → final confirmation → save.
// Demo: any code passes except 000000. ctx.v.ueNoTotp shows the blocked state (admin has not enabled 2FA).
function UeStepUpSheet({ ed, purpose }) {
  const { ctx } = ed;
  const [code, setCode] = useState('');
  const [err, setErr] = useState('');
  const close = () => ed.setSheet(null);
  const what = purpose === 'create' ? `创建管理员「${ed.name}」` : `把「${ed.name}」设为管理员`;
  if (ctx.v && ctx.v.ueNoTotp) {
    return (
      <Sheet title="二次验证" onClose={close} leadingLabel="关闭">
        <div className="ue-otp-block tone-caution">
          <span className="ue-otp-ico"><Icon name="shield" size={26} /></span>
          <b>需要先在 Web 端开启二次验证</b>
          <p>{what}需要输入身份验证器里的验证码。你的账号还没开启二次验证，请先在 Web 端「个人资料」里启用，再回来保存。</p>
        </div>
        <button className="submit" onClick={close}>知道了</button>
      </Sheet>
    );
  }
  const input = v => {
    const next = v.replace(/\D/g, '').slice(0, 6);
    setErr('');
    if (next.length < 6) { setCode(next); return; }
    if (next === '000000') { setCode(''); setErr('验证码不对，请重新输入'); return; }
    close();
    ed.afterStepUp(purpose);
  };
  return (
    <Sheet title="二次验证" onClose={close}>
      <p className="ue-note">{what}前，输入身份验证器里的 6 位验证码。验证通过后还要再确认一次。</p>
      <label className={cx('ue-otp', err && 'is-bad')}>
        <input autoFocus inputMode="numeric" autoComplete="one-time-code" value={code} onChange={e => input(e.target.value)} aria-label="6 位验证码" />
        {[0, 1, 2, 3, 4, 5].map(i => <span key={i} className={cx('ue-otp-box num', i === code.length && 'is-cur')}>{code[i] || ''}</span>)}
      </label>
      {err ? <p className="ue-err ue-otp-msg">{err}</p> : <p className="ue-foot ue-otp-msg">填满 6 位自动提交；可以从“密码”App 自动填充。</p>}
    </Sheet>
  );
}

// ⋯ menu: core's toolbar menu (ctx.menu = SwiftUI Menu { Button; Divider; Button(role: .destructive).disabled(isAdmin) }). Deletion is
// last and confirmed; DeleteUser removes the user's keys in the same transaction, so the confirmation says how many (as core's userMenu).
function ueOpenMenu(ed) {
  const { ctx, u, original, keys } = ed;
  const isAdmin = original.role === 'admin';
  ctx.menu({
    actions: [
      { label: '复制邮箱', sub: u.email, role: 'default', onPress: () => ctx.showToast({ text: '已复制邮箱', icon: 'check', tone: 'neutral' }) },
      { label: '删除用户…', sub: isAdmin ? '管理员不能删除' : undefined, role: 'destructive', disabled: isAdmin,
        onPress: () => confirmDelete(ctx, '用户', u.name, () => { ctx.pop(); ctx.pop(); }, keys.length ? { message: `名下 ${keys.length} 个 Key 一并删除。` } : {}) },
    ],
  });
}

function UeSheets({ ed }) {
  const s = ed.sheet;
  if (!s) return null;
  if (s.kind === 'group') return <UeGroupSheet ed={ed} gid={s.gid} key={`g${s.gid}`} />;
  if (s.kind === 'addGroup') return <UeAddGroupSheet ed={ed} />;
  if (s.kind === 'replace') return <UeReplaceSheet ed={ed} gid={s.gid} key={`r${s.gid}`} />;
  if (s.kind === 'quota') return <UeQuotaSheet ed={ed} platform={s.platform} key={`q${s.platform}`} />;
  if (s.kind === 'addQuota') return <UeAddQuotaSheet ed={ed} />;
  if (s.kind === 'key') return <UeKeySheet ed={ed} kid={s.kid} key={`k${s.kid}`} />;
  if (s.kind === 'keyGroup') return <UeKeyGroupSheet ed={ed} kid={s.kid} back={Boolean(s.back)} key={`kg${s.kid}`} />;
  if (s.kind === 'attr') return <UeAttrSheet ed={ed} attrKey={s.key} key={`a${s.key}`} />;
  if (s.kind === 'stepUp') return <UeStepUpSheet ed={ed} purpose={s.purpose} />;
  return null;
}

function UeNav({ ed, subtitle, onInvalid, noCreate }) {
  const { ctx, isNew } = ed;
  let trailing = null;
  if (!isNew) trailing = <><GlassButton icon="more" onClick={() => ueOpenMenu(ed)} /><UeBarBtn label="保存" on={ed.changed.length > 0} onClick={() => (ed.changed.length ? ed.save(onInvalid) : null)} /></>;
  else if (!noCreate) trailing = <UeBarBtn label="创建" on={ed.valid} onClick={() => ed.create(onInvalid)} />;
  return <NavBar ctx={ctx} title={isNew ? '新建用户' : '编辑用户'} subtitle={subtitle} leading={<GlassButton icon="back" onClick={ed.leave} />} trailing={trailing} />;
}

// Scroll a route-requested section into view once, and jump to the first invalid row after a failed save.
function useUeScroll(focus) {
  const ref = useRef(null);
  useEffect(() => {
    if (focus && ref.current) ueScrollTo(ref.current, ref.current.querySelector(`[data-ue="${focus}"]`));
  }, []);
  const toFirstBad = () => setTimeout(() => { if (ref.current) ueScrollTo(ref.current, ref.current.querySelector('.is-bad')); }, 30);
  return [ref, toFirstBad];
}

/* ---------- identity: pass card (base), strip (tabs), compact head (lean) ---------- */

function UePassCard({ ed }) {
  const { ctx, u, isNew, draft, base } = ed;
  const initial = draft.balance && UE_NUM.test(draft.balance) ? Number(draft.balance) : null;
  return (
    <div className={cx('ue-pass', isNew && 'is-new')}>
      <div className="ue-pass-top">
        <span className={cx('ue-ava', isNew && !draft.username && !draft.email && 'is-blank')}>{(draft.username || draft.email || (u && u.name) || '新').slice(0, 1).toUpperCase()}</span>
        <span>{isNew ? `新用户 · ${ctx.site}` : `ID ${u.id} · ${ctx.site}`}</span>
        {!isNew && base.active !== '—' && <span className="ue-pass-meta">{base.active}活跃</span>}
      </div>
      <div className="ue-pass-name">{isNew ? ed.name : u.name}</div>
      <div className="ue-pass-mail">{isNew ? draft.email || '填写邮箱后创建' : u.email}</div>
      <div className="ue-pass-foot">
        <span className="ue-pass-bal">
          <small>{isNew ? '初始余额' : '可用余额'}</small>
          {isNew && initial === null ? <span className="ue-pass-def">站点默认</span> : <b className="num">{fmt.money(isNew ? initial : u.balance)}</b>}
        </span>
        <span className="ue-badges"><UeBadges ed={ed} />{isNew && <ctx.skin.Badge tone="neutral" label="创建后启用" />}</span>
      </div>
    </div>
  );
}

// The pill draws 30pt high, but the button itself is 44pt tall (SwiftUI: .frame(minHeight: 44).contentShape(Rectangle())).
function UePill({ ctx, u }) {
  return <button className="ue-pill" onClick={() => ueTopup(ctx, u)}><span className="ue-pill-face">充值 / 退款</span></button>;
}

// compact: the one-line strip shown while the form is scrolled or a field has focus (keyboard up): name, balance, 充值 / 退款.
function UeStrip({ ed, compact }) {
  const { ctx, u, isNew, draft } = ed;
  if (isNew) {
    return (
      <div className="ue-strip is-new">
        <span className={cx('ue-ava sm', !draft.username && !draft.email && 'is-blank')}>{(draft.username || draft.email || '新').slice(0, 1).toUpperCase()}</span>
        <b className="ue-strip-name">{ed.name}</b>
        <span className="ue-strip-tail">{UE_ROLE_LABEL[draft.role]} · 创建后启用</span>
      </div>
    );
  }
  if (compact) {
    return (
      <div className="ue-strip is-compact">
        <b className="ue-strip-name">{u.name}</b>
        <span className="ue-strip-inline"><small>余额</small><b className="num ue-strip-bal">{fmt.money(u.balance)}</b></span>
        <UePill ctx={ctx} u={u} />
      </div>
    );
  }
  return (
    <div className="ue-strip">
      <div className="ue-strip-main">
        <b className="ue-strip-name">{u.name}</b>
        <span className="ue-strip-mail">{u.email}</span>
        <span className="ue-badges"><UeBadges ed={ed} /></span>
      </div>
      <div className="ue-strip-side">
        <small>可用余额</small>
        <b className="num ue-strip-bal">{fmt.money(u.balance)}</b>
        <UePill ctx={ctx} u={u} />
      </div>
    </div>
  );
}

function UeLeanHead({ ed }) {
  const { ctx, u, isNew, draft } = ed;
  return (
    <div className="ue-lhead">
      <span className={cx('ue-ava', isNew && !draft.username && !draft.email && 'is-blank')}>{(draft.username || draft.email || (u && u.name) || '新').slice(0, 1).toUpperCase()}</span>
      <span className="ue-lhead-main">
        <b>{isNew ? ed.name : u.name}</b>
        <span>{isNew ? draft.email || '填写邮箱后创建' : `${u.email} · ID ${u.id}`}</span>
      </span>
      <span className="ue-badges is-col"><UeBadges ed={ed} />{isNew && <ctx.skin.Badge tone="neutral" label="创建后启用" />}</span>
    </div>
  );
}

function UeNowDivider() {
  return (
    <div className="ue-now" role="separator" aria-label="以下操作立即生效，不需要保存">
      <span className="ue-now-rule" />
      <span className="ue-now-text"><b>以下操作立即生效</b><small>不需要保存，也不会随“放弃更改”撤回</small></span>
      <span className="ue-now-rule" />
    </div>
  );
}

function UeLater({ lean }) {
  return (
    <div className="ue-else">
      <b>创建后再设置</b>
      <p>{lean
        ? '创建后进入用户详情：余额调整、Key 换分组、平台限额、替换分组都在那里操作，立即生效。'
        : '创建后进入用户详情，在那里充值。专属倍率和平台限额在 ⋯ → 编辑用户 里设置。Key 由用户自己在 Web 端创建。'}</p>
    </div>
  );
}

// lean: the edit page only holds what “保存” submits; the immediate actions live on the user detail page.
function UeElsewhere({ ed }) {
  const { u, keys, quotas, original } = ed;
  return (
    <div className="ue-else">
      <b>立即生效的操作不在这一页</b>
      <p>余额、API Key、平台限额、替换分组改了就生效，不经过“保存”，放在用户详情页；只读的 RPM 状态也在那里看。</p>
      <div className="ue-else-grid">
        <span><small>余额</small><b className="num">{fmt.money(u.balance)}</b></span>
        <span><small>API Key</small><b className="num">{keys.length} 个</b></span>
        <span><small>平台限额</small><b className="num">{quotas.length} 个平台</b></span>
        <span><small>专属分组</small><b className="num">{original.exclusive.length} 个</b></span>
      </div>
    </div>
  );
}

/* ---------- base「分组表单」：一个 Form，要保存的在上，立即生效的在分隔标题之下 ---------- */

function UeFormScreen({ ctx, route }) {
  const ed = useUeEditor(ctx, route, 'form');
  const [ref, toFirstBad] = useUeScroll(route.focus);
  const { isNew } = ed;
  return (
    <Screen ctx={ctx} nav={<UeNav ed={ed} subtitle={isNew ? ctx.site : `${ed.u.name} · ${ctx.site}`} onInvalid={toFirstBad} />} footer={<UeSheets ed={ed} />}>
      <div className="ue-page ue-form" ref={ref}>
        <UePassCard ed={ed} />
        <UeAccountSec ed={ed} />
        <UeLoginSec ed={ed} />
        <UeRoleSec ed={ed} withStatus />
        <UeExclusiveSec ed={ed} />
        <UePublicSec ed={ed} />
        <UeLimitSec ed={ed} />
        {isNew && <UeInitBalanceSec ed={ed} />}
        {isNew ? <UeLater /> : (
          <>
            <UeNowDivider />
            <UeBalanceSec ed={ed} />
            <UeKeySec ed={ed} />
            <UeQuotaSec ed={ed} />
            <UeReplaceSec ed={ed} />
          </>
        )}
      </div>
    </Screen>
  );
}

/* ---------- tabs「分段」：固定身份条 + 基础 | 权限与并发 | Key 与限额（第三段立即生效） ---------- */

// SF Symbol exclamationmark.circle.fill: a solid disc in --critical-ink with the “!” cut out (even-odd), so the glyph keeps the disc's
// contrast on any segment background (≥ 4.5:1 in both themes) instead of white text on --critical.
function UeBadMark({ size = 18 }) {
  return (
    <svg className="ue-badmark" width={size} height={size} viewBox="0 0 20 20" aria-hidden="true">
      <path fillRule="evenodd" fill="currentColor" d="M10 1a9 9 0 1 1 0 18a9 9 0 1 1 0-18Z M8.9 5.2h2.2l-.35 6.6h-1.5Z M10 12.9a1.35 1.35 0 1 1 0 2.7a1.35 1.35 0 1 1 0-2.7Z" />
    </svg>
  );
}

// Custom segmented control (SwiftUI: HStack of buttons + .glassEffect + matchedGeometryEffect for the selection), so each segment can carry
// its own mark: a dot for unsaved edits, an exclamationmark.circle.fill for errors, an accessibilityLabel with the words (“基础，有 1 项要修改”),
// and a line of words under it while the header is unfolded. compact (scrolled / keyboard up) drops that line; the marks stay.
function UeSegBar({ ed, segs, seg, setSeg, compact }) {
  const marks = segs.map(s => ({
    ...s,
    dirty: ed.isNew ? 0 : new Set(ed.changed.filter(k => UE_FIELDS[k].seg === s.key).map(k => UE_FIELDS[k].label)).size,
    bad: ed.showErrors ? Object.keys(ed.errors).filter(k => UE_FIELDS[k] && UE_FIELDS[k].seg === s.key).length : 0,
  }));
  const say = m => [m.bad && `有 ${m.bad} 项要修改`, m.dirty && `已改 ${m.dirty} 项`].filter(Boolean).join('、');
  const line = marks.filter(m => m.dirty || m.bad);
  // While unfolded the line is always there (a mark landing never changes the header's height): a hint while clean, the marks in words
  // otherwise. The hint only says what “保存” covers; “立即生效” is said once, at the head of the Key 与限额 segment.
  const hint = ed.isNew ? '两段填完后点底部“创建用户”' : '基础、权限与并发改完点右上“保存”，两段一起提交';
  return (
    <>
      <div className="ue-segs" role="tablist">
        {marks.map(m => (
          <button key={m.key} role="tab" aria-selected={seg === m.key} aria-label={[m.label, say(m)].filter(Boolean).join('，')} className={cx('ue-seg', seg === m.key && 'on')} onClick={() => setSeg(m.key)}>
            <span>{m.label}</span>
            {m.count != null && <span className="num ue-seg-count">{m.count}</span>}
            {m.bad ? <span className="ue-seg-bad"><UeBadMark /></span> : m.dirty ? <i className="ue-seg-dot" aria-hidden="true" /> : null}
          </button>
        ))}
      </div>
      <div className={cx('ue-segline', !line.length && 'is-hint')} aria-live="polite" aria-hidden={compact || undefined}>
        {line.length ? line.map((m, i) => (
          <span key={m.key}>{i > 0 && ' · '}{m.label} {m.bad > 0 && <b className="is-bad">{m.bad} 项要修改</b>}{m.bad > 0 && m.dirty > 0 && '、'}{m.dirty > 0 && <b className="is-dirty">已改 {m.dirty} 项</b>}</span>
        )) : hint}
      </div>
    </>
  );
}

// The header folds once the form scrolls or one of its fields takes focus (on the phone that is when the keyboard comes up), so the fields
// keep the room. Two thresholds stop it flapping at the edge. SwiftUI: .onScrollGeometryChange(for: Bool.self) { $0.contentOffset.y > 24 }
// plus @FocusState, compact = scrolled || focused != nil, applied withAnimation(.snappy) to the .safeAreaInset(edge: .top) header.
// Unfolding after a blur waits a moment: a tap that moves focus away (a picker row, a segment) must land before the content shifts down,
// as UIKit keeps a touch on the view it started on. `key` (the segment) re-checks focus after the page swaps its fields.
const UE_FOLD_AT = 24;
const UE_UNFOLD_AT = 2;
const UE_UNFOLD_DELAY = 300;
const ueIsFormField = el => Boolean(el && el.matches && el.matches('input, textarea') && el.closest('.ue-page'));
function useUeCompact(rootRef, key) {
  const [scrolled, setScrolled] = useState(false);
  const [typing, setTyping] = useState(false);
  const timer = useRef(null);
  const recheck = () => {
    clearTimeout(timer.current);
    timer.current = setTimeout(() => setTyping(ueIsFormField(document.activeElement)), UE_UNFOLD_DELAY);
  };
  useEffect(() => {
    const root = rootRef.current;
    const scroller = root && root.closest('.scroll');
    const screen = root && root.closest('.screen');
    if (!scroller || !screen) return undefined;
    const onScroll = () => setScrolled(was => (was ? scroller.scrollTop > UE_UNFOLD_AT : scroller.scrollTop > UE_FOLD_AT));
    // Only the form's own fields count; inputs inside a sheet sit above the keyboard on their own.
    const onIn = e => { if (ueIsFormField(e.target)) { clearTimeout(timer.current); setTyping(true); } };
    const onOut = e => { if (ueIsFormField(e.target)) recheck(); };
    scroller.addEventListener('scroll', onScroll, { passive: true });
    screen.addEventListener('focusin', onIn);
    screen.addEventListener('focusout', onOut);
    return () => {
      clearTimeout(timer.current);
      scroller.removeEventListener('scroll', onScroll);
      screen.removeEventListener('focusin', onIn);
      screen.removeEventListener('focusout', onOut);
    };
  }, []);
  useEffect(() => { if (typing) recheck(); }, [key]);
  return scrolled || typing;
}

function UeTabsScreen({ ctx, route }) {
  const ed = useUeEditor(ctx, route, 'tabs');
  const { isNew } = ed;
  const segs = isNew ? UE_SEGS.slice(0, 2) : UE_SEGS.map(s => (s.key === 'keys' ? { ...s, count: ed.keys.length } : s));
  const [seg, setSeg] = useState(route.seg && segs.some(s => s.key === route.seg) ? route.seg : 'basic');
  const topRef = useRef(null);
  const compact = useUeCompact(topRef, seg);
  useEffect(() => {
    const scroller = topRef.current && topRef.current.closest('.scroll');
    if (scroller) scroller.scrollTop = 0;
  }, [seg]);
  // A failed save / create (client check or server refusal) opens the segment holding the first error, then scrolls to that row.
  const toBad = errs => {
    const k = Object.keys(errs).find(x => UE_FIELDS[x]);
    if (k) setSeg(UE_FIELDS[k].seg);
    setTimeout(() => { const root = topRef.current; if (root) ueScrollTo(root, root.querySelector('.is-bad')); }, 80);
  };
  const head = (
    <>
      <UeNav ed={ed} subtitle={ctx.site} onInvalid={toBad} noCreate />
      <div className={cx('ue-tabhead', isNew && 'is-new', compact && 'is-compact')}><UeStrip ed={ed} compact={compact} /><UeSegBar ed={ed} segs={segs} seg={seg} setSeg={setSeg} compact={compact} /></div>
    </>
  );
  // SwiftUI: .safeAreaInset(edge: .bottom) so the step buttons never sit under the (hidden) tab bar or the toast.
  const bar = isNew && (
    <div className="ue-bar">
      {seg === 'basic'
        ? <button className="submit" onClick={() => setSeg('access')}>下一步：权限与并发<Icon name="arrowRight" size={17} weight={2.4} /></button>
        : <><button className="ue-bar-back" onClick={() => setSeg('basic')}>上一步</button><button className="submit" onClick={() => ed.create(toBad)}>创建用户</button></>}
    </div>
  );
  return (
    <Screen ctx={ctx} nav={head} footer={<>{bar}<UeSheets ed={ed} /></>}>
      <div className={cx('ue-page ue-tabs', isNew && 'has-bar', compact && 'is-compact')} ref={topRef}>
        {seg === 'basic' && (
          <>
            <UeAccountSec ed={ed} />
            <UeLoginSec ed={ed} withStatus />
            {isNew && <UeInitBalanceSec ed={ed} />}
          </>
        )}
        {seg === 'access' && (
          <>
            <UeRoleSec ed={ed} />
            <UeExclusiveSec ed={ed} />
            <UePublicSec ed={ed} />
            <UeLimitSec ed={ed} />
          </>
        )}
        {seg === 'keys' && !isNew && (
          <>
            <div className="ue-nowbar"><b>这一段立即生效</b>，不用保存，也不随“放弃更改”撤回</div>
            <UeKeySec ed={ed} />
            <UeQuotaSec ed={ed} />
            <UeReplaceSec ed={ed} />
          </>
        )}
      </div>
    </Screen>
  );
}

/* ---------- lean「只放要保存的」：编辑页只有“保存”会提交的字段 ---------- */

function UeLeanScreen({ ctx, route }) {
  const ed = useUeEditor(ctx, route, 'lean');
  const [ref, toFirstBad] = useUeScroll(route.focus);
  const { isNew } = ed;
  return (
    <Screen ctx={ctx} nav={<UeNav ed={ed} subtitle={ctx.site} onInvalid={toFirstBad} />} footer={<UeSheets ed={ed} />}>
      <div className="ue-page ue-lean" ref={ref}>
        <UeLeanHead ed={ed} />
        <UeAccountSec ed={ed} />
        <UeLoginSec ed={ed} />
        <UeRoleSec ed={ed} withStatus />
        <UeExclusiveSec ed={ed} />
        <UePublicSec ed={ed} />
        <UeLimitSec ed={ed} noStatus />
        {isNew ? <><UeInitBalanceSec ed={ed} /><UeLater lean /></> : <UeElsewhere ed={ed} />}
      </div>
    </Screen>
  );
}

mvRegister('screen:userNew', 'base', UeFormScreen);
mvRegister('screen:userEdit', 'base', UeFormScreen);
mvRegister('screen:userNew', 'tabs', UeTabsScreen);
mvRegister('screen:userEdit', 'tabs', UeTabsScreen);
mvRegister('screen:userNew', 'lean', UeLeanScreen);
mvRegister('screen:userEdit', 'lean', UeLeanScreen);
