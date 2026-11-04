/* 编辑账号。已定（第 3 轮 Q5 / Q6）：详情页内联编辑 + 凭据区表单行。
   ③ inline（已定）：账号详情就是这一页——槽 accountDetail 'inline'（props {ctx, id}，所有 {kind:'account', id} 都进这里）
          与 screen:accountEdit 'inline'（对比页用，route 带 id、可带 focus 分区）共用 AeInline。
          上半部分直接用核心 AccountDetailTop（状态卡 + 按钮行、容量、今日、记录；停调度走 ctx.setSchedule，恢复走 confirmRecover），
          下面接 基础 / 调度 / 凭据 / 代理 / 模型 / 高级，取代原来的“档案”。分区里是只读表单行（SwiftUI List + LabeledContent），
          基础 / 调度 / 模型 / 高级 右上“编辑”打开同样表单行的小 sheet（取消 / 保存），各自 PUT，回执可撤销；
          代理选中即 PUT，回执可撤销；代理行写 名称 / 协议 / 到期（与代理页同一套词）和 protocol://host:port，选择器只列启用的代理；
          凭据是表单行：API Key“🔒 已设置 · 不可查看 · 更换”、Base URL“修改”，sheet 底部按钮即生效；
          OAuth 与 Setup Token（核心 isTokenAccount，同 Web：两者都有重新授权 / 刷新令牌，Setup Token 的访问令牌同样 8 小时、自动刷新）
          显示访问令牌剩余时间，下面“刷新令牌”“重新授权…”两行都标“立即生效”；Claude 账号重新授权时第 1 步可选授权方式
          OAuth / Setup Token（同 Web ReAuthAccountModal：按账号类型预选、可改；Setup Token 走 generate-setup-token-url →
          exchange-setup-token-code），改选另一种时授权后账号类型随之改变，说明和回执都写明。更换后回执给“测试”；重新授权后按
          apply-oauth-credentials 的结果更新状态（清除错误 / 限流 / 模型限流，开关不动），仍暂停时回执给“启用调度”。
          停用账号点“重新授权…”先弹确认：apply-oauth-credentials 的 ClearAccountError 会把状态改回 active，授权后账号会被重新启用。
          凭据类错误（核心 isCredentialError：401 / 403 / invalid_api_key / 令牌失效）时，状态卡按钮行的主按钮由核心换成
          “更换 API Key…”（OAuth / Setup Token 为“重新授权…”），这里用 AccountDetailTop 的 extraActions 把它接到本文件的 aeKey / aeReauth sheet；
          换过 Key 后主按钮变“测试连接”（通过才清除错误）。
          ⋯ 菜单（核心 ctx.menu）没有“编辑账号”：更换 API Key… 或 刷新令牌 / 重新授权…（OAuth / Setup Token）、在 Web 中编辑、删除账号…（最后，红字）。
   ① base（未选）分组表单：一张长表单，分区 基础 / 调度 / 配额 / 凭据 / 代理 / 模型 / 高级；左上“取消”、右上“保存”；底部改动条可展开，逐项跳转、逐项还原
   ② seg（未选）分段编辑：顶部自绘分段 基础 | 调度 | 凭据 | 模型 | 高级（原生 Picker(.segmented) 画不出改动点），每段一张短表单；统一保存
   ①② 在 App 里用 .sheet + NavigationStack 呈现；有改动时 .interactiveDismissDisabled，下滑时的确认通过 UIKit
   presentationControllerDidAttemptToDismiss 桥接弹出。原型里是推进页 + “取消 / 保存”。
   ①② 的凭据区三种呈现（initial.v.aeCred）：'row' 表单行，原地更换 | 'card' 凭据状态卡 + 按钮 | 'page' 一行入口 → 独立凭据页。
   ctx.faceId（设置里的“高风险操作需要 Face ID”）打开时，更换 API Key、重新授权在 sheet 的确认按钮之后再验证 Face ID。
   分组：GET groups/all 只返回启用的分组（DEMO.groups 里 active 的，按 sort_order），成员关系只看 accounts[].groups，可用数按成员实时算。
   出错时间：后端没有这个字段——SetError 只写 status / error_message / schedulable，updated_at 任何一次编辑都会刷新。
   所以不写“出错于…”，而是用这个账号最近一条上游错误日志的时间和状态码（核心 lastUpstreamError，已定详情画在状态卡里，
   ①② 的凭据区自己画）：GET ops/upstream-errors?account_id=:id&time_range=24h&page=1&page_size=1（phase upstream / account_auth，
   created_at 倒序，需要运维监控开启）；监控关闭或 24 小时内没有记录时这一行不出现。同一份列表从“记录 · 上游错误”进入。

   字段对照 PUT admin/accounts/:id：name、notes、status、concurrency、priority、rate_multiplier（Web 叫“账号计费倍率”）、load_factor、
   group_ids、expires_at、auto_pause_on_expired、proxy_id、credentials、extra；刷新令牌 POST :id/refresh；
   可选模型来自 GET :id/models。模型限制就是 credentials.model_mapping 一张表：为空支持所有模型，列出后只调度列出的模型，
   映射项把请求模型换成实际模型（通配符 * 只能在末尾）。
   重新授权三步（Web ReAuthAccountModal 同样）：① 按平台生成授权链接 ② exchange-code 换回令牌（只返回，不落库）
   ③ POST admin/accounts/:id/apply-oauth-credentials {type, credentials, extra} 落库。各平台的前两步：
     Anthropic accounts/generate-auth-url → accounts/exchange-code；OpenAI openai/generate-auth-url → openai/exchange-code；
     Gemini / Antigravity / Grok 分别是 gemini/、antigravity/、grok/ 下的 oauth/auth-url → oauth/exchange-code。
   apply-oauth-credentials 落库后调 ClearAccountError：状态改回 active，清除错误、限流、过载、临时不可调度、模型限流
   （Antigravity 另清配额范围），调度开关不动——错误账号（出错时开关已关）恢复后仍是暂停；extra 按键合并，不会丢配置。
   代理：GET admin/proxies/all?with_count=true 只返回启用（status active）的代理，按 created_at 倒序，带 account_count；
   停用、已过期的代理不在可选列表里，账号当前挂着的那一个由 GET :id 的 proxy 字段给出。代理数据一律读 DEMO.proxies。

   保存规则（实现时必须遵守，否则会丢数据）：
   - 顶层字段稀疏提交：只发改过的 name / notes / status / concurrency / priority / rate_multiplier / load_factor / group_ids /
     expires_at / auto_pause_on_expired / proxy_id。
   - credentials 和 extra 是整块覆盖：后端 MergePreservingSensitiveCreds 对非敏感键完全以请求为准，extra 也整体替换，只保留几个受管键
     （service/admin_account.go）。所以要以 GET :id 返回的（已脱敏）整份 credentials / extra 为底，合并改动后整份提交；
     否则会清掉 base_url、api_protocol、account_mode、池模式重试、自定义错误码、临时不可调度规则、请求头覆写等只能在 Web 改的设置。
   - 敏感键（api_key、access_token 等）GET 不返回，只有 credentials_status.has_api_key；只在更换时带上，不带则后端保留旧值。
   - 改了 group_ids 时先 POST check-mixed-channel（Web EditAccountModal 同样先预检），后端 PUT 也会返回 409 mixed_channel_warning
     （Anthropic 与 Antigravity 账号进同一分组，checkMixedChannelRisk 跳过本账号），确认后带 confirm_mixed_channel_risk=true 重发。
     共享 DEMO 里没有 Antigravity 账号，所以只有新建向导造出的 Antigravity 账号 #21 加入「高级组」（里面是 Anthropic 账号）时触发。 */

/* ---------- 演示数据（字段名对照 02 文档，值为虚构） ---------- */

const AE_DEMO_KEY = 'sk-proj-N7c2xQ84m1Lz0aRvT5kd';
// After refresh / re-authorize the server returns the new credentials.expires_at; +8 h is only a demo value and is never shown as a lifetime.
const AE_DEMO_RENEW = 8 * 3600;
/* Proxies come from DEMO.proxies (proxyOf / proxyProto); the expiry wording is core proxyExpiry (the proxies page's words, counted
   from DEMO_TODAY). A disabled proxy reads 已停用 here, like core accountProxyText — it has nothing to count down to. */
const aeProxyWhen = p => (p.status === 'inactive' ? { label: '已停用', tone: 'none' } : proxyExpiry(p));
// Web ProxySelector prints protocol://host:port under the name.
const aeProxyAddr = p => `${p.protocol}://${p.host}:${p.port}`;
// GET proxies/all?with_count=true: active proxies only, newest first; account_count counted live from this phone's accounts.
const aeActiveProxies = () => DEMO.proxies.filter(p => p.status === 'active').sort((x, y) => (x.createdAt < y.createdAt ? 1 : -1));
const aeProxyUsers = (ctx, name) => Object.values(ctx.accounts).filter(a => a.proxy === name).length;
const AE_MODELS = {
  Anthropic: ['claude-opus-4-1', 'claude-opus-4', 'claude-sonnet-4-5', 'claude-sonnet-4', 'claude-haiku-4-5'],
  OpenAI: ['gpt-5', 'gpt-5-mini', 'gpt-4.1', 'gpt-4o', 'o4-mini'],
  Gemini: ['gemini-2.5-pro', 'gemini-2.5-flash'],
  '智谱 GLM': ['glm-4.6', 'glm-4.5', 'glm-4.5-air'],
  MiniMax: ['MiniMax-M2'],
  DeepSeek: ['deepseek-chat', 'deepseek-reasoner'],
  Kimi: ['kimi-k2-0905-preview', 'kimi-k2-turbo-preview'],
  Grok: ['grok-4', 'grok-3-mini'],
};
const AE_WILDCARDS = { Anthropic: ['claude-3-5-sonnet-*', 'claude-3-7-sonnet-*'], OpenAI: ['gpt-4-*', 'gpt-4o-*'] };
// credentialsBuilder.ts CN_BASE_URL_PRESETS: which account modes each provider has, and whether it has a Responses endpoint (cnSupportsNativeResponses).
const AE_CN = {
  '智谱 GLM': { modes: ['payg', 'coding'], responses: false },
  MiniMax: { modes: ['payg', 'coding'], responses: true },
  DeepSeek: { modes: ['payg'], responses: true },
  Kimi: { modes: ['payg', 'coding'], responses: true },
};
// Authorization per platform (same redirects as the new-account wizard). back 'code': the provider's page shows the code
// (Claude platform.claude.com/oauth/code/callback, Gemini CLI client codeassist.google.com/authcode); 'callback': the browser
// lands on a local callback address, and the admin pastes that link (or its code). api = the platform's auth-url / exchange-code pair.
const AE_OAUTH = {
  Anthropic: { api: 'accounts/generate-auth-url · accounts/exchange-code', back: 'code', url: 'https://claude.com/cai/oauth/authorize?code=true&client_id=9d1c250a-…&redirect_uri=https%3A%2F%2Fplatform.claude.com%2Foauth%2Fcode%2Fcallback', code: '授权码', placeholder: '授权页显示的授权码', demo: 'ac_7Q2f…k9Xw' },
  OpenAI: { api: 'openai/generate-auth-url · openai/exchange-code', back: 'callback', cb: 'localhost:1455', url: 'https://auth.openai.com/oauth/authorize?client_id=app_…&redirect_uri=http%3A%2F%2Flocalhost%3A1455%2Fauth%2Fcallback', code: '回调链接或 Code', placeholder: '地址栏里的回调链接，或其中的 code', demo: 'http://localhost:1455/auth/callback?code=ac_9Fq2…&state=s8Kd2Wq' },
  Gemini: { api: 'gemini/oauth/auth-url · gemini/oauth/exchange-code', back: 'code', url: 'https://accounts.google.com/o/oauth2/v2/auth?client_id=681255809395-…&redirect_uri=https%3A%2F%2Fcodeassist.google.com%2Fauthcode', code: '授权码', placeholder: '授权完成页显示的授权码', demo: '4/0AVMBsJc…Lm9X' },
  Antigravity: { api: 'antigravity/oauth/auth-url · antigravity/oauth/exchange-code', back: 'callback', cb: 'localhost:8085', url: 'https://accounts.google.com/o/oauth2/v2/auth?client_id=…&redirect_uri=http%3A%2F%2Flocalhost%3A8085%2Fcallback', code: '回调链接或 Code', placeholder: '地址栏里的回调链接，或其中的 code', demo: 'http://localhost:8085/callback?state=a2Lp9&code=4/0AVMBsJc…' },
  Grok: { api: 'grok/oauth/auth-url · grok/oauth/exchange-code', back: 'callback', cb: '127.0.0.1:56121', url: 'https://auth.x.ai/oauth2/authorize?client_id=b1a00492-…&redirect_uri=http%3A%2F%2F127.0.0.1%3A56121%2Fcallback', code: '回调链接或 Code', placeholder: '地址栏里的回调链接，或其中的 code', demo: 'http://127.0.0.1:56121/callback?code=xg_5Tm8…&state=k4Vb1' },
};
// Claude Setup Token (inference-only scope): its own URL / exchange pair, then apply-oauth-credentials with type 'setup-token'.
const AE_OAUTH_SETUP = {
  ...AE_OAUTH.Anthropic,
  api: 'accounts/generate-setup-token-url · accounts/exchange-setup-token-code',
  url: 'https://claude.com/cai/oauth/authorize?code=true&client_id=9d1c250a-…&scope=user%3Ainference&redirect_uri=https%3A%2F%2Fplatform.claude.com%2Foauth%2Fcode%2Fcallback',
};
// Values only. lastUsed = last_used_at; used = extra.quota_*_used; quota = extra.quota_*_limit.
const AE_SEED = {
  3: {
    notes: 'Max 订阅主力号；限流时先看 01、02', token: 25932,
    models: [{ from: 'claude-opus-4-1', to: 'claude-opus-4' }, { from: 'claude-opus-4' }, { from: 'claude-sonnet-4-5' }, { from: 'claude-3-5-sonnet-*', to: 'claude-sonnet-4-5' }],
  },
  1: { token: 11100 },
  2: { token: 2760, notes: '副号' },
  7: { notes: '备用 Key · 团队账单', rate: '1.2', lastUsed: '42 分钟前' },
  4: { load: '20', lastUsed: '刚刚', used: { weekly: 412.6, total: 3820.4 }, models: [{ from: 'gpt-5' }, { from: 'gpt-5-mini' }, { from: 'gpt-4o' }] },
  11: { adv: { mode: 'coding', protocol: 'anthropic' } },
  9: { adv: { protocol: 'anthropic' } },
};
const AE_PARTS = [
  { key: 'basic', label: '基础' }, { key: 'sched', label: '调度' }, { key: 'cred', label: '凭据' },
  { key: 'models', label: '模型' }, { key: 'adv', label: '高级' },
];
// [field, label, part]; proxy belongs to the 凭据 segment (connection) in the segmented layout.
const AE_FIELDS = [
  ['name', '名称', 'basic'], ['notes', '备注', 'basic'], ['status', '账号状态', 'basic'],
  ['conc', '并发数', 'sched'], ['priority', '优先级', 'sched'], ['rate', '账号计费倍率', 'sched'], ['load', '负载因子', 'sched'],
  ['groups', '分组', 'sched'], ['expires', '过期时间', 'sched'], ['autoPause', '过期自动暂停调度', 'sched'],
  ['quotaDaily', '日限额', 'sched'], ['quotaWeekly', '周限额', 'sched'], ['quotaTotal', '总限额', 'sched'],
  ['key', 'API Key', 'cred'], ['baseUrl', 'Base URL', 'cred'], ['proxy', '代理', 'cred'],
  ['models', '模型', 'models'],
];
const aePartOf = key => (key.startsWith('adv.') ? 'adv' : (AE_FIELDS.find(f => f[0] === key) || [])[2] || 'basic');

/* ---------- model ---------- */

// Token accounts (core isTokenAccount: OAuth and Setup Token) show the token, 刷新令牌 and 重新授权…; everything else holds a key.
const aeIsKey = a => !isTokenAccount(a);
// Anthropic OAuth / Setup Token share Web's quota-control block (EditAccountModal: platform anthropic && type oauth || setup-token).
const aeIsClaudeToken = a => a.platform === 'Anthropic' && isTokenAccount(a);
const AE_POOL = { key: 'pool', label: '池模式', sub: '上游是账号池时开启，错误不标记本账号', kind: 'switch', init: false };
const AE_PROBE = { key: 'probe', label: '自动探测上游声明倍率', sub: '只探测，不改账号计费倍率', kind: 'switch', init: false };

// Provider switches that exist in EditAccountModal.vue, with the same v-if conditions; everything else stays in Web.
function aeAdvDefs(a) {
  if (aeIsClaudeToken(a)) {
    return [
      { key: 'warmup', label: '拦截预热请求', sub: '标题生成等预热请求不消耗上游 Token', kind: 'switch', init: true },
      { key: 'windowCost', label: '5h 窗口费用控制', sub: '达到阈值后不接新请求', kind: 'limit', field: '费用阈值', unit: '$', init: { on: true, v: '50' } },
      { key: 'sessions', label: '会话数量控制', kind: 'limit', field: '最大会话数', init: { on: true, v: '3' } },
      { key: 'rpm', label: 'RPM 限制', kind: 'limit', field: '基础 RPM', init: { on: true, v: '60' } },
      { key: 'tls', label: 'TLS 指纹模拟', kind: 'switch', init: true },
      { key: 'sidMask', label: '会话 ID 伪装', kind: 'switch', init: false },
      { key: 'affinity', label: '客户端亲和调度', kind: 'switch', init: false },
    ];
  }
  const key = aeIsKey(a);
  const cn = AE_CN[a.platform];
  const out = [];
  if (cn && key) {
    if (cn.modes.length > 1) out.push({ key: 'mode', label: '账号类型', kind: 'seg', init: 'payg', options: [['payg', '按量付费'], ['coding', 'Coding Plan']] });
    out.push({
      key: 'protocol', label: 'API 协议', kind: 'menu', init: 'adaptive',
      options: [['adaptive', '自适应'], ['chat', 'Chat Completions'], ['anthropic', 'Anthropic'], ...(cn.responses ? [['responses', 'Responses']] : [])],
    });
  }
  if (a.platform === 'OpenAI') out.push({ key: 'passthrough', label: '自动透传（仅替换认证）', sub: '开启后模型限制不生效', kind: 'switch', init: false });
  if (a.platform === 'OpenAI' && key) out.push({ key: 'responses', label: 'Responses API 支持', kind: 'menu', init: 'auto', options: [['auto', '自动'], ['responses', '强制 Responses'], ['chat', '强制 Chat Completions']] });
  if (key) out.push(AE_POOL, AE_PROBE);
  return out;
}

// Two examples of what only EditAccountModal.vue edits, per account kind. No total: the Web form changes and is the source of truth.
const AE_WEB_ONLY = {
  claudeOAuth: ['自定义错误码', '请求头覆写'],
  openaiKey: ['自定义错误码', '池模式重试'],
  cnKey: ['自定义错误码', '各协议地址'],
  key: ['自定义错误码', '临时不可调度规则'],
  oauth: ['自定义错误码', '临时不可调度规则'],
};
function aeWebOnly(a) {
  const list = aeIsClaudeToken(a) ? AE_WEB_ONLY.claudeOAuth
    : !aeIsKey(a) ? AE_WEB_ONLY.oauth
      : a.platform === 'OpenAI' ? AE_WEB_ONLY.openaiKey
        : AE_CN[a.platform] ? AE_WEB_ONLY.cnKey : AE_WEB_ONLY.key;
  return `${list.join('、')}等其余设置`;
}

function aeProfile(a) {
  const s = AE_SEED[a.id] || {};
  const q = s.quota || {};
  return {
    name: a.name,
    notes: s.notes || '',
    status: a.state === 'error' ? 'error' : a.state === 'inactive' ? 'inactive' : 'active',
    conc: a.conc ? a.conc[1] : null,
    priority: a.priority ?? 1,
    rate: s.rate || '1',
    load: s.load || '',
    groups: [...a.groups],
    expires: a.expires || null,
    autoPause: true,
    // The daily limit is DEMO's dayQuota (the 日配额 bar in 容量), so the bar and this field never disagree.
    quotaDaily: a.dayQuota ? String(a.dayQuota[1]) : (q.daily || ''), quotaWeekly: q.weekly || '', quotaTotal: q.total || '',
    proxy: a.proxy || null,
    key: null,
    baseUrl: s.baseUrl || '',
    models: s.models || [],
    adv: { ...Object.fromEntries(aeAdvDefs(a).map(d => [d.key, d.init])), ...(s.adv || {}) },
  };
}
// Only a key the admin just pasted can be shown (prefix••••last4, like the new-account wizard). A saved key is never returned.
function aeMaskNew(v) {
  const s = (v || '').trim();
  if (s.length <= 8) return '•'.repeat(s.length);
  const pre = (s.match(/^(sk-ant-api03-|sk-proj-|sk-|AIza|xai-|AKIA)/) || [''])[0];
  return `${pre}••••${s.slice(-4)}`;
}
// A Setup Token's access token is short-lived too (expires_in 28800, auto-refreshed like OAuth), so both count down the same way.
const aeTokenAt = a => (isTokenAccount(a) ? ((AE_SEED[a.id] || {}).token ?? 20000) : null);
const aeTokenTone = left => (left >= 3600 ? 'ok' : left > 0 ? 'caution' : 'critical');
const AE_TOKEN_WORD = { ok: '有效', caution: '即将到期', critical: '已过期' };
// Whole hours are rounded (7 h 59 min reads “8 小时后”); under an hour counts minutes up.
const aeLeftTiny = left => (left <= 0 ? '已过期' : left >= 3600 ? `${Math.round(left / 3600)} 小时后` : `${Math.ceil(left / 60)} 分钟后`);
const aeLeftShort = left => (left <= 0 ? '已过期' : `${aeLeftTiny(left)}到期`);
const aeClock = sec => fmt.clock(DEMO_CLOCK_BASE + sec * 1000);
const aeOpt = (def, v) => ((def.options || []).find(o => o[0] === v) || [v, v])[1];
const aeLastUsed = a => (AE_SEED[a.id] || {}).lastUsed || (a.todayReq ? '今天' : '—');

function aeShow(k, v) {
  if (k === 'groups') return v.length ? v.join('、') : '未分组';
  if (k === 'expires') return v || '不过期';
  if (k === 'proxy') return v || '无代理';
  if (k === 'models') return v.length ? `${v.length} 个模型` : '支持所有模型';
  if (k === 'key') return v ? aeMaskNew(v) : '当前密钥';
  if (k === 'autoPause') return v ? '开' : '关';
  if (k === 'load') return v === '' || v === '0' ? '默认' : v;
  if (k === 'rate') return `×${v}`;
  // The account's on/off pair is 正常 / 停用 (文案硬规则; 启用 / 禁用 belongs to users).
  if (k === 'status') return { active: '正常', inactive: '停用', error: '错误' }[v];
  if (k === 'baseUrl') return v || '官方地址';
  if (k === 'notes') return v || '—';
  if (k === 'conc') return v ?? '—';
  if (k.startsWith('quota')) return v ? `$${v}` : '不限';
  return String(v);
}
function aeShowAdv(def, v) {
  if (def.kind === 'switch') return v ? '开' : '关';
  if (def.kind === 'limit') return v.on ? `${def.unit || ''}${v.v || '—'}` : '关';
  return aeOpt(def, v);
}
const aeSame = (x, y) => JSON.stringify(x) === JSON.stringify(y);

// The change list shown to the admin. A key field left empty means "keep the current key".
function aeDiff(a, from, to) {
  const norm = d => ({ ...d, key: d.key || null });
  const f = norm(from), t = norm(to);
  const out = AE_FIELDS.filter(([k]) => !aeSame(f[k], t[k]))
    .map(([k, label, part]) => ({ key: k, label, part, from: aeShow(k, f[k]), to: aeShow(k, t[k]), secret: k === 'key' }));
  aeAdvDefs(a).forEach(def => {
    if (!aeSame(f.adv[def.key], t.adv[def.key])) out.push({ key: `adv.${def.key}`, label: def.label, part: 'adv', from: aeShowAdv(def, f.adv[def.key]), to: aeShowAdv(def, t.adv[def.key]) });
  });
  return out;
}
const AE_MONEY = /^\d+(\.\d+)?$/;
function aeInvalid(d) {
  const e = {};
  if (!d.name.trim()) e.name = '请输入账号名称';
  if (d.load !== '' && !(/^\d+$/.test(d.load) && +d.load <= 10000)) e.load = '负载因子为 1–10000 的整数；留空或 0 恢复默认';
  if (!AE_MONEY.test(String(d.rate))) e.rate = '账号计费倍率需要是不小于 0 的数字';
  ['quotaDaily', 'quotaWeekly', 'quotaTotal'].forEach(k => { if (d[k] !== '' && !AE_MONEY.test(d[k])) e[k] = '填写美元金额，留空表示不限'; });
  return e;
}
// What the demo account list needs to reflect after saving.
function aePatch(a, d) {
  const p = { name: d.name.trim() || a.name, priority: d.priority, groups: d.groups, proxy: d.proxy, expires: d.expires };
  if (aeIsKey(a)) p.dayQuota = d.quotaDaily ? [a.dayQuota ? a.dayQuota[0] : 0, +d.quotaDaily] : null;
  if (d.conc !== null) p.conc = [a.conc ? a.conc[0] : 0, d.conc];
  if (d.status === 'inactive' && a.state !== 'inactive') p.state = 'inactive';
  // status=active leaves the schedule switch as it was: an account stopped before it was disabled comes back paused.
  if (d.status === 'active' && a.state === 'inactive') p.state = isSchedulable(a) ? 'normal' : 'paused';
  return p;
}
const aeSnapshot = a => ({ name: a.name, priority: a.priority, groups: a.groups, proxy: a.proxy, expires: a.expires, conc: a.conc, state: a.state, dayQuota: a.dayQuota });
// Used amounts next to each limit (extra.quota_*_used); the daily one is DEMO's dayQuota[0].
const aeQuotaUsed = a => ({ ...((AE_SEED[a.id] || {}).used || {}), ...(a.dayQuota ? { daily: a.dayQuota[0] } : {}) });
function aePreset(a, init, preset) {
  if (preset === 'dirty') {
    const extra = aeGroupsFor(a).find(g => g.status === 'active' && !g.exclusive && !init.groups.includes(g.name));
    return { ...init, conc: (init.conc || 4) + 2, groups: extra ? [...init.groups, extra.name] : init.groups, proxy: init.proxy === 'sg-01' ? 'hk-02' : 'sg-01' };
  }
  if (preset === 'key') return { ...init, key: AE_DEMO_KEY };
  if (preset === 'noname') return { ...init, name: '' };
  return init;
}
const aeNames = changes => {
  const names = changes.map(c => c.label);
  return names.length > 3 ? `${names.slice(0, 3).join('、')} 等 ${names.length} 项` : names.join('、');
};
// Editor scratch state that must survive pushing the credentials page (only the top screen is mounted).
const AE_CLEAR = { aeDraft: null, aeDid: null, aeKeyReplaced: null };

/* ---------- save pipeline ---------- */

// ctx.faceId is the global “高风险操作需要 Face ID” switch (settings).
const aeGuard = (ctx, run, setFace) => (ctx.faceId ? setFace({ run }) : run());
const aeFaceLine = ctx => (ctx.faceId ? '\n下一步验证 Face ID。' : '');

// The receipt's button runs the connection test (core Toast action: the button text is what VoiceOver reads).
const aeToastTest = (ctx, a, text) => ctx.showToast({
  text, icon: 'checkCircle', tone: 'ok', action: { label: '测试', onPress: () => ctx.openSheet({ kind: 'test', id: a.id }) },
});

// Mirrors checkMixedChannelRisk: only Anthropic ↔ Antigravity, only when group_ids is part of the request; every requested group is
// checked against its other members (the account itself skipped). The app never sees members' platforms, it just receives the 409.
function aeMixedRisk(ctx, a, changes, groups) {
  const mine = a.platform === 'Anthropic' || a.platform === 'Antigravity' ? a.platform : null;
  if (!mine || !changes.some(c => c.key === 'groups')) return null;
  const other = mine === 'Anthropic' ? 'Antigravity' : 'Anthropic';
  const g = groups.find(name => groupMembers(ctx.accounts, name).some(x => x.id !== a.id && x.platform === other));
  return g ? { group: g, mine, other } : null;
}
// PUT; on 409 mixed_channel_warning ask (non-destructive, Web wording) and resend with confirm_mixed_channel_risk=true.
function aePut(ctx, a, changes, groups, done) {
  const risk = aeMixedRisk(ctx, a, changes, groups);
  if (!risk) return done();
  ctx.confirm({
    title: '混合渠道警告',
    message: `警告：分组“${risk.group}”中同时包含 ${risk.mine} 和 ${risk.other} 账号。混合使用不同渠道可能导致 thinking block 签名验证问题，会自动回退到非 thinking 模式。确定要继续吗？`,
    actions: [{ label: '继续保存', role: 'default', onPress: done }, { label: '取消', role: 'cancel' }],
  });
}

// Save ①②: field changes go straight to PUT and the receipt offers 撤销 (PUT the old values again);
// a key change first gets a destructive confirm (+ Face ID when enabled) and has no undo.
function aeCommit(ctx, a, changes, groups, apply, setFace) {
  const secret = changes.some(c => c.secret);
  const before = aeSnapshot(a);
  const finish = () => {
    apply();
    if (secret) aeToastTest(ctx, a, '已保存 · 已更换 API Key');
    else ctx.showToast({ text: `已保存：${aeNames(changes)}`, icon: 'checkCircle', undo: () => ctx.updateAccount(a.id, before) });
  };
  const put = () => aePut(ctx, a, changes, groups, finish);
  if (!secret) return put();
  ctx.confirm({
    title: `保存 ${changes.length} 项改动？`,
    message: `其中包括更换 API Key：保存后站点立即改用新密钥，不能撤销；旧密钥不再保存、不能找回。如果旧密钥泄露，请到上游控制台吊销。${aeFaceLine(ctx)}`,
    actions: [{ label: '保存并更换密钥', role: 'destructive', onPress: () => aeGuard(ctx, put, setFace) }, { label: '取消', role: 'cancel' }],
  });
}

function aeLeave(ctx, changes, onLeave, did) {
  if (!changes.length) return onLeave();
  const now = did && did.length ? `\n本次已${did.join('、')}，这些已立即生效，不会撤回。` : '';
  ctx.confirm({
    title: '放弃未保存的改动？',
    message: `${changes.length} 项改动不会保存：${aeNames(changes)}${now}`,
    actions: [{ label: '放弃改动', role: 'destructive', onPress: onLeave }, { label: '继续编辑', role: 'cancel' }],
  });
}

// What apply-oauth-credentials' ClearAccountError leaves behind: status active (a disabled account comes back enabled), error /
// rate limit / overload / temp-unschedulable / model limits cleared, the schedule switch untouched. In the demo model “switch off,
// nothing blocking” is the paused state.
const AE_CLEARED = { error: '错误', rate_limited: '限流', overloaded: '过载', temp_unsched: '临时不可调度' };
// An account type inside a sentence: “Setup Token” never breaks across lines.
const aeTypeWord = t => t.replace(/ /g, '\u00a0');
// type: the method picked in the re-authorize sheet when it differs from the account's (Claude only). apply-oauth-credentials
// stores that type ('oauth' | 'setup-token') with the new token, so the account becomes that type.
function aeReauthResult(a, type) {
  const models = (a.modelLimits || []).length;
  const on = a.state !== 'error' && isSchedulable(a);
  const touched = Boolean(AE_CLEARED[a.state]) || a.state === 'inactive';
  const patch = { modelLimits: [], ...(type ? { type } : {}), ...(touched ? { state: on ? 'normal' : 'paused', schedulable: on, error: null } : {}) };
  const what = [AE_CLEARED[a.state], models ? ` ${models} 项模型限流` : null].filter(Boolean).join('和');
  const live = (touched ? patch.state : a.state) === 'normal';
  const tail = a.state === 'inactive' ? '已启用账号' : !what ? '令牌已替换' : `已清除${what}`;
  const as = type ? ` · 账号类型改为 ${aeTypeWord(type)}` : '';
  return { patch, live, text: `已重新授权${as} · ${tail}${touched ? (live ? ' · 参与调度' : ' · 仍暂停调度') : ''}` };
}

// Token state lives on the demo account so the editor and the credentials page agree.
function aeToken(ctx, a) {
  const expAt = a.aeTokenAt ?? aeTokenAt(a);
  const left = expAt === null ? null : expAt - ctx.elapsed;
  const renewTo = ctx.elapsed + AE_DEMO_RENEW;
  const did = what => ({ aeTokenAt: renewTo, aeDid: [...new Set([...(a.aeDid || []), what])] });
  return {
    left, at: expAt === null ? null : aeClock(expAt),
    refresh: () => { ctx.updateAccount(a.id, did('刷新令牌')); ctx.showToast({ text: `已刷新令牌 · 新令牌 ${aeClock(renewTo)} 到期`, icon: 'refresh' }); },
    // exchange-code → apply-oauth-credentials: the token is stored and the account's blocks are cleared in the same call;
    // type (optional) converts a Claude account to the method picked in the sheet.
    renew: type => {
      const r = aeReauthResult(a, type);
      ctx.updateAccount(a.id, { ...did('重新授权（令牌已替换）'), ...r.patch });
      if (r.live || a.state === 'normal') aeToastTest(ctx, a, r.text);
      else ctx.showToast({ text: r.text, icon: 'checkCircle', tone: 'ok', action: { label: '启用调度', onPress: () => ctx.setSchedule([a.id], true) } });
    },
  };
}

// The account's newest upstream error log — core lastUpstreamError (ops/upstream-errors?account_id=:id&page_size=1), the same rows as
// the 使用记录 “上游错误” list filtered to this account. Not the moment the account entered 错误: the backend keeps no such time.
const aeLastUpstream = (ctx, a) => lastUpstreamError(a.id, ctx.elapsed);
const aeUpstreamRoute = a => ({ kind: 'logs', scope: 'upstream', account: a.id });
// The status code of a credential error (core isCredentialError: 401 / 403, invalid_api_key, revoked token).
const aeErrCode = a => ((a.error || '').match(/\b(40[13])\b/) || [])[1] || null;

/* ---------- primitives ---------- */

function AeLock() {
  return (
    <svg className="ae-lock" width="11" height="13" viewBox="0 0 11 13" aria-hidden="true">
      <rect x="1" y="5.5" width="9" height="6.8" rx="1.6" fill="currentColor" />
      <path d="M3 5.5V4a2.5 2.5 0 0 1 5 0v1.5" fill="none" stroke="currentColor" strokeWidth="1.5" />
    </svg>
  );
}
function AeMinus({ size = 15 }) {
  return <svg width={size} height={size} viewBox="0 0 24 24" aria-hidden="true" style={{ display: 'block', flex: 'none' }}><path d="M5 12h14" stroke="currentColor" strokeWidth="2.6" strokeLinecap="round" /></svg>;
}
function AeFaceGlyph() {
  return (
    <svg className="ae-face-glyph" width="62" height="62" viewBox="0 0 60 60" fill="none" stroke="currentColor" strokeWidth="3" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
      <path d="M6 20v-8a6 6 0 0 1 6-6h8M40 6h8a6 6 0 0 1 6 6v8M54 40v8a6 6 0 0 1-6 6h-8M20 54h-8a6 6 0 0 1-6-6v-8" />
      <path d="M21 23v4M39 23v4M30.5 23v10H28M22 41c4.5 4 11.5 4 16 0" />
    </svg>
  );
}

// Simulated system Face ID HUD (LAContext.evaluatePolicy in the app).
function AeFaceId({ onDone }) {
  const [ok, setOk] = useState(false);
  useEffect(() => {
    const t1 = setTimeout(() => setOk(true), 1100);
    const t2 = setTimeout(onDone, 1700);
    return () => { clearTimeout(t1); clearTimeout(t2); };
  }, []);
  return (
    <div className="ae-face-ov" role="alert" aria-label="Face ID">
      <div className={cx('ae-face glass', ok && 'is-ok')}>
        {ok ? <Icon name="checkCircle" size={60} weight={1.7} /> : <AeFaceGlyph />}
        <span>{ok ? '已验证' : 'Face ID'}</span>
      </div>
    </div>
  );
}
const aeFaceHud = (face, setFace) => face && <AeFaceId onDone={() => { const run = face.run; setFace(null); run(); }} />;

function AeSec({ title, meta, action, onAction, part, children, foot, changed }) {
  return (
    <section className="ae-sec" data-part={part}>
      <div className="ae-head">
        <span className={cx('sec-title', changed && 'ae-title-changed')}>{title}</span>
        <span className="sec-line" />
        {meta && <span className="sec-meta">{meta}</span>}
        {action && <button className="ae-head-act" onClick={onAction}>{action}</button>}
      </div>
      <div className="ae-form">{children}</div>
      {foot && <div className="ae-foot">{foot}</div>}
    </section>
  );
}

function AeF({ label, sub, changed, children, hint, error, col, indent, onClick, className, field }) {
  return (
    <>
      <div className={cx('ae-f', col && 'ae-f-col', indent && 'ae-f-indent', changed && 'is-changed', onClick && 'tappable', className)} onClick={onClick} data-field={field}>
        {label && <span className="ae-f-label"><span className="ae-f-name">{label}</span>{sub && <small>{sub}</small>}</span>}
        {children}
      </div>
      {(error || hint) && <div className={cx('ae-hint', error && 'is-error')}>{error || hint}</div>}
    </>
  );
}

// LabeledContent + TextField: tapping anywhere on the row focuses the field. A prefixed value (×1, $50) keeps the prefix next to the
// digits inside a ≥ 64 pt wide, 44 pt tall tap area, so a one-digit value is not a 19 pt target.
function AeText({ label, sub, value, onChange, placeholder, changed, error, hint, mono, prefix, inputMode, indent, type, field }) {
  const ref = useRef(null);
  const input = (
    <input ref={ref} className={cx('ae-in', mono && 'mono', prefix && 'has-prefix')} type={type || 'text'} value={value} placeholder={placeholder}
      inputMode={inputMode} onChange={e => onChange(e.target.value)} aria-label={label} aria-invalid={Boolean(error)} />
  );
  return (
    <AeF label={label} sub={sub} changed={changed} error={error} hint={hint} indent={indent} field={field} className="ae-f-text"
      onClick={e => { if (ref.current && e.target !== ref.current) ref.current.focus(); }}>
      <span className="ae-f-val">
        {prefix
          ? <span className="ae-prefixed">{(value !== '' || !placeholder) && <span className="ae-prefix">{prefix}</span>}{input}</span>
          : input}
      </span>
    </AeF>
  );
}

function AeArea({ label, value, onChange, placeholder, changed, field }) {
  return (
    <AeF label={label} changed={changed} col field={field}>
      <textarea className="ae-area" rows={1} value={value} placeholder={placeholder} onChange={e => onChange(e.target.value)} aria-label={label} />
    </AeF>
  );
}

function AeRead({ label, value }) {
  return <AeF label={label}><span className="ae-f-val ae-ro">{value}<AeLock /></span></AeF>;
}

// Stepper for ±1 nudges; the number itself is a text field so large values can be typed (SwiftUI: TextField + Stepper).
function AeStepper({ label, sub, value, onChange, min = 0, max = 999, changed, field }) {
  const v = value ?? null;
  const typed = s => { const n = s.replace(/\D/g, ''); onChange(n === '' ? null : Math.min(max, +n)); };
  return (
    <AeF label={label} sub={sub} changed={changed} field={field}>
      <span className="ae-f-val">
        <input className={cx('ae-step-n num', v === null && 'is-missing')} value={v === null ? '' : String(v)} placeholder="未设置"
          inputMode="numeric" onChange={e => typed(e.target.value)} aria-label={label} />
        <span className="ae-step">
          <button aria-label={`减少${label}`} disabled={v === null || v <= min} onClick={() => onChange(v - 1)}><AeMinus /></button>
          <button aria-label={`增加${label}`} disabled={v !== null && v >= max} onClick={() => onChange(v === null ? min || 1 : v + 1)}><Icon name="plus" size={15} weight={2.6} /></button>
        </span>
      </span>
    </AeF>
  );
}

function AeSwitch({ label, sub, on, onChange, changed, field }) {
  return (
    <AeF label={label} sub={sub} changed={changed} onClick={() => onChange(!on)} field={field}>
      <span className="ae-f-val"><span className={cx('st-switch', on && 'on')} role="switch" aria-checked={on} aria-label={label}><i /></span></span>
    </AeF>
  );
}

function AePick({ label, sub, value, onClick, changed, hint, field }) {
  return (
    <AeF label={label} sub={sub} changed={changed} hint={hint} onClick={onClick} field={field}>
      <span className="ae-f-val">{value}<span className="ae-chev"><Icon name="chevron" size={13} weight={2.6} /></span></span>
    </AeF>
  );
}

function AeSeg2({ options, value, onChange }) {
  return (
    <span className="ae-f-val">
      <span className="ae-seg2" role="radiogroup">
        {options.map(([k, l]) => <button key={k} role="radio" aria-checked={value === k} className={cx(value === k && 'on')} onClick={() => onChange(k)}>{l}</button>)}
      </span>
    </span>
  );
}

// Action row; `now` marks actions that take effect immediately, outside 保存 / 取消.
function AeAct({ icon, label, onClick, now, disabled, sub, field }) {
  return (
    <button className="ae-f ae-act" onClick={onClick} disabled={disabled} data-field={field}>
      <span className="ae-act-icon"><Icon name={icon} size={18} weight={2.2} /></span>
      <span className="ae-act-label"><span>{label}</span>{sub && <small>{sub}</small>}</span>
      {now && <span className="ae-now">立即生效</span>}
    </button>
  );
}

function AeBtn({ label, icon, onClick, primary, disabled }) {
  return (
    <button className={cx('act', primary && 'act-primary')} disabled={disabled} onClick={e => { e.stopPropagation(); if (onClick) onClick(); }}>
      {icon && <Icon name={icon} size={16} weight={2.4} />}<span>{label}</span>
    </button>
  );
}

function AeChipsVal({ items, empty }) {
  if (!items.length) return <span className="dim">{empty}</span>;
  return (
    <span className="ae-chipvals">
      {items.slice(0, 2).map(g => <span key={g} className="ae-chipv">{g}</span>)}
      {items.length > 2 && <span className="ae-chipv">+{items.length - 2}</span>}
    </span>
  );
}

// The account's proxy (GET :id returns it even when it is no longer active): name, then protocol and the proxies page's expiry word.
function AeProxyVal({ name }) {
  if (!name) return <span className="dim">无代理</span>;
  const p = proxyOf(name);
  if (!p) return <span className="ae-pv"><b>{name}</b></span>;
  const ex = aeProxyWhen(p);
  return (
    <span className="ae-pv">
      <b>{p.name}</b>
      <small>{proxyProto(p)} · <span className={cx(ex.tone !== 'none' && `tone-${ex.tone} tone-text`)}>{ex.label}</span></small>
    </span>
  );
}

// Under the proxy row: the address, and what to do when the proxy left the selectable list (expired / disabled).
function aeProxyHint(name) {
  const p = name ? proxyOf(name) : null;
  if (!p) return null;
  const addr = <span className="mono">{aeProxyAddr(p)}</span>;
  if (p.status === 'expired') return <span className="ae-px-warn">{addr}<br />代理已过期，这个账号仍挂在上面。换一个启用中的代理，或改为无代理。</span>;
  if (p.status !== 'active') return <span>{addr}<br />代理已停用，不在可选列表里；可以换一个，或改为无代理。</span>;
  return addr;
}

/* ---------- field kits (shared by every structure) ---------- */
// f = { ctx, a, d, set, setAdv, ch, err, pick }; pick(kind, props) opens a picker (sheet, or a page inside the part sheet).

function AeBasicKit({ f }) {
  const { ctx, a, d, set, ch, err } = f;
  const wasError = a.state === 'error';
  const statusOpts = wasError
    ? [['error', <><i className="ae-sdot tone-critical" />错误</>], ['inactive', '停用']]
    : [['active', '正常'], ['inactive', '停用']];
  return (
    <AeSec title="基础" part="basic">
      <AeText field="name" label="名称" value={d.name} placeholder="账号名称" onChange={v => set('name', v)} changed={ch.name} error={err.name} />
      <AeF field="status" label="账号状态" sub={wasError ? '清除错误用账号详情里的“恢复状态”' : '限流、过载等运行状态不在这里改'} changed={ch.status}>
        <AeSeg2 options={statusOpts} value={d.status} onChange={v => set('status', v)} />
      </AeF>
      <AeRead label="平台" value={a.platform} />
      <AeRead label="类型" value={a.type} />
      <AeArea field="notes" label="备注" value={d.notes} onChange={v => set('notes', v)} placeholder="可选" changed={ch.notes} />
    </AeSec>
  );
}

function AeSchedKit({ f }) {
  const { d, set, ch, err, pick } = f;
  return (
    <AeSec title="调度" part="sched">
      <AeStepper field="conc" label="并发数" value={d.conc} min={1} onChange={v => set('conc', v)} changed={ch.conc} />
      <AeStepper field="priority" label="优先级" sub="越小越优先" value={d.priority} onChange={v => set('priority', v)} changed={ch.priority} />
      <AeText field="rate" label="账号计费倍率" sub="0 表示不计费，仅影响账号计费" prefix="×" value={d.rate} inputMode="decimal" onChange={v => set('rate', v)} changed={ch.rate} error={err.rate} />
      <AeText field="load" label="负载因子" sub="越大越常被选中" value={d.load} placeholder="默认" inputMode="numeric" onChange={v => set('load', v)} changed={ch.load} error={err.load} />
      <AePick field="groups" label="分组" value={<AeChipsVal items={d.groups} empty="未分组" />} changed={ch.groups}
        onClick={() => pick('Groups', { value: d.groups, onDone: v => set('groups', v) })} />
      <AePick field="expires" label="过期时间" value={d.expires ? <span className="num ae-v">{d.expires}</span> : <span className="ae-v">不过期</span>} changed={ch.expires}
        onClick={() => pick('Expiry', { value: d.expires, onDone: v => set('expires', v) })} />
      {d.expires && <AeSwitch field="autoPause" label="过期自动暂停调度" on={d.autoPause} onChange={v => set('autoPause', v)} changed={ch.autoPause} />}
    </AeSec>
  );
}

// extra.quota_daily_limit / quota_weekly_limit / quota_limit — shown for every API Key / Bedrock account, like Web.
function AeQuotaKit({ f }) {
  const { a, d, set, ch, err } = f;
  if (!aeIsKey(a)) return null;
  const used = aeQuotaUsed(a);
  const row = (k, label, u) => (
    <AeText key={k} field={k} label={label} sub={u !== undefined ? `已用 ${fmt.money(u)}` : null} prefix="$" value={d[k]} placeholder="不限"
      inputMode="decimal" onChange={v => set(k, v)} changed={ch[k]} error={err[k]} />
  );
  return (
    <AeSec title="配额" part="sched" meta="留空表示不限" foot="任一项达到后暂停调度；修改限额不重置已用额度。重置时间和用量提醒在 Web 中设置。">
      {row('quotaDaily', '日限额', used.daily)}
      {row('quotaWeekly', '周限额', used.weekly)}
      {row('quotaTotal', '总限额', used.total)}
    </AeSec>
  );
}

// Credential status card. A saved key is write-only (credentials_status.has_api_key), so the card leads with the
// credential's state — error / normal + reason — never with the key itself. Reason = error_message; there is no error
// timestamp (updated_at moves with every edit), so the card cites the newest upstream error log instead (aeLastUpstream).
function AeCredCard({ ctx, a, d, left, at, replaced, proxyDirty, onRefresh, onReauth, onReplace, onUndoKey }) {
  if (!aeIsKey(a)) {
    const tone = aeTokenTone(left);
    return (
      <div className={cx('ae-cred', `tone-${tone}`)} data-field="token">
        <div className="ae-cred-top">
          <span className="ae-cred-kicker"><Icon name="key" size={15} weight={2.2} />{a.type} 访问令牌</span>
          <span className={cx('badge', `tone-${tone}`)}>{AE_TOKEN_WORD[tone]}</span>
        </div>
        <div className="ae-cred-fig"><span className="num readout">{fmt.countdown(left)}</span><span>后到期</span></div>
        <div className="ae-cred-meta">到期时刻 <span className="num">{at}</span> · 到期前自动刷新</div>
        {proxyDirty && <div className="ae-cred-meta ae-cred-warn">代理有未保存的改动，先保存再重新授权</div>}
        <div className="actions">
          <AeBtn label="刷新令牌" icon="refresh" onClick={onRefresh} />
          <AeBtn label="重新授权" icon="restore" onClick={onReauth} disabled={proxyDirty} />
        </div>
      </div>
    );
  }
  const pending = d && d.key;
  const failed = a.state === 'error';
  const test = () => ctx.openSheet({ kind: 'test', id: a.id });
  let tone, word, line, meta, actions;
  if (pending) {
    tone = 'neutral'; word = '新密钥待保存';
    line = <span className="mono">{aeMaskNew(pending)}</span>;
    meta = '保存时替换当前密钥；当前密钥不可查看';
    actions = [<AeBtn key="r" label="重新填写" icon="key" onClick={onReplace} />, <AeBtn key="u" label="撤销更换" icon="restore" onClick={onUndoKey} />];
  } else if (replaced) {
    tone = 'neutral'; word = '已更换';
    line = failed ? '账号仍为错误：测试连接通过后自动清除错误' : '新密钥已生效，建议测试连接';
    meta = failed ? '更换密钥本身不清除错误；清除后仍暂停调度' : null;
    actions = [
      <AeBtn key="t" primary label="测试连接" icon="wave" onClick={test} />,
      failed && <AeBtn key="r" label="恢复状态" icon="restore" onClick={() => confirmRecover(ctx, a)} />,
      <AeBtn key="k" label={failed ? '再换' : '再次更换'} icon="key" onClick={onReplace} />,
    ].filter(Boolean);
  } else if (failed) {
    const last = aeLastUpstream(ctx, a);
    tone = 'critical'; word = '错误'; line = a.error;
    meta = `${last ? `最近上游错误 ${last.ago}（${last.code}）· ` : ''}更换 API Key 后测试连接，通过即清除错误`;
    actions = [<AeBtn key="k" primary label="更换 API Key" icon="key" onClick={onReplace} />, <AeBtn key="t" label="测试" icon="wave" onClick={test} />];
  } else {
    tone = 'ok'; word = '正常'; line = '没有凭据错误';
    meta = `最近使用 ${aeLastUsed(a)}`;
    actions = [<AeBtn key="k" label="更换 API Key" icon="key" onClick={onReplace} />, <AeBtn key="t" label="测试连接" icon="wave" onClick={test} />];
  }
  return (
    <div className={cx('ae-cred', `tone-${tone}`, tone === 'critical' && 'is-failed tone-rail')} data-field="key">
      <div className="ae-cred-top">
        <span className="ae-cred-kicker"><Icon name="key" size={15} weight={2.2} />API Key</span>
        {pending ? <span className="badge tone-neutral">待保存</span> : <span className="ae-cred-has"><AeLock />已设置 · 不可查看</span>}
      </div>
      <div className="ae-cred-word"><i className="ae-sdot" />{word}</div>
      <div className="ae-cred-line">{line}</div>
      {meta && <div className="ae-cred-meta">{meta}</div>}
      <div className="actions">{actions}</div>
    </div>
  );
}

// The error bar of the row presentation: error_message, then the newest upstream error as evidence. When onLogs is given the
// whole bar opens this account's 上游错误 list (the editor parks its draft first); without it the line is plain text.
function AeErrorAlert({ ctx, a, onLogs }) {
  const last = aeLastUpstream(ctx, a);
  const evidence = last && <span className="ae-alert-ev">最近上游错误 <span className="num">{last.t}</span> · {last.ago} · <span className="num">{last.code}</span></span>;
  const body = (
    <>
      <Icon name="octagon" size={18} weight={2.2} />
      <div><b>{a.error}</b>{evidence}<span>更换 API Key 并保存，再测试连接</span></div>
    </>
  );
  if (!last || !onLogs) return <div className="ae-alert tone-critical tone-rail" data-field="error">{body}</div>;
  return (
    <button className="ae-alert tone-critical tone-rail is-link" data-field="error" onClick={onLogs} aria-label={`${a.error}。最近上游错误 ${last.t}，${last.ago}，状态码 ${last.code}。查看上游错误记录`}>
      {body}<span className="ae-alert-chev"><Icon name="chevron" size={13} weight={2.6} /></span>
    </button>
  );
}

// cred = { mode, left, at, replaced, proxyDirty, onRefresh, onReauth, onReplace, onOpenPage, onLogs }
function AeCredKit({ f, cred }) {
  const { ctx, a, d, set, ch } = f;
  const oauth = !aeIsKey(a);
  const failed = a.state === 'error';
  const nowFoot = oauth ? '令牌到期前自动刷新。刷新令牌与重新授权立即生效，不受保存 / 取消影响。' : null;
  const baseUrl = <AeText field="baseUrl" label="Base URL" value={d.baseUrl} placeholder="留空使用官方地址" mono onChange={v => set('baseUrl', v)} changed={ch.baseUrl} />;
  if (cred.mode === 'page') {
    const tone = oauth ? aeTokenTone(cred.left) : null;
    const value = oauth
      ? <span className="ae-v"><span className={`tone-${tone} tone-text`}>{AE_TOKEN_WORD[tone]}</span> · {aeLeftShort(cred.left)}</span>
      : cred.replaced ? <span className="ae-v ae-strong">已更换 · 待测试</span>
        : failed ? <span className="ae-v tone-critical tone-text">错误 · 凭据已失效</span> : <span className="ae-v">已设置</span>;
    return (
      <AeSec title="凭据" part="cred" foot={oauth ? '刷新令牌、重新授权在凭据页里，立即生效。' : '更换 API Key 在凭据页里单独保存。'}>
        <AePick field="key" label={oauth ? `${a.type} 令牌` : 'API Key'} value={value} onClick={cred.onOpenPage} />
      </AeSec>
    );
  }
  if (cred.mode === 'card') {
    return (
      <AeSec title="凭据" part="cred" foot={nowFoot}>
        <AeCredCard ctx={ctx} a={a} d={d} left={cred.left} at={cred.at} proxyDirty={cred.proxyDirty} onRefresh={cred.onRefresh} onReauth={cred.onReauth}
          onReplace={cred.onReplace} onUndoKey={() => set('key', null)} />
        {!oauth && baseUrl}
      </AeSec>
    );
  }
  if (oauth) {
    const tone = aeTokenTone(cred.left);
    return (
      <AeSec title="凭据" part="cred" foot={nowFoot}>
        <AeF field="token" label="访问令牌" sub={<>到期时刻 <span className="num">{cred.at}</span></>}>
          <span className="ae-f-val"><span className={cx('badge', `tone-${tone}`)}>{AE_TOKEN_WORD[tone]}</span><span className="ae-v">{aeLeftTiny(cred.left)}</span></span>
        </AeF>
        <AeAct icon="refresh" label="刷新令牌" now onClick={cred.onRefresh} />
        <AeAct icon="restore" label="重新授权…" now disabled={cred.proxyDirty} sub={cred.proxyDirty ? '代理改动未保存，先保存' : null} onClick={cred.onReauth} />
      </AeSec>
    );
  }
  const replacing = d.key !== null;
  return (
    <AeSec title="凭据" part="cred">
      {cred.replaced && !replacing && (
        <div className="ae-alert tone-neutral">
          <Icon name="checkCircle" size={18} weight={2.2} />
          <div><b>已更换 API Key · 待测试</b><span>{failed ? '账号仍为错误：测试连接通过后自动清除错误（仍暂停调度）' : '建议测试连接确认新密钥可用'}</span>
            <span className="ae-alert-acts">
              <button className="ae-mini is-accent" onClick={() => ctx.openSheet({ kind: 'test', id: a.id })}>测试连接</button>
              {failed && <button className="ae-mini" onClick={() => confirmRecover(ctx, a)}>恢复状态</button>}
            </span>
          </div>
        </div>
      )}
      {failed && !cred.replaced && !replacing && <AeErrorAlert ctx={ctx} a={a} onLogs={cred.onLogs} />}
      {replacing ? (
        <>
          <div className={cx('ae-f ae-f-col ae-newkey', d.key && 'is-changed')} data-field="key">
            <span className="ae-newkey-top"><span className="ae-f-name">新 API Key</span><button className="ae-mini" onClick={() => set('key', null)}>取消更换</button></span>
            <span className="ae-newkey-in">
              <input className="ae-in mono" type="password" value={d.key} placeholder="粘贴新的 API Key" onChange={e => set('key', e.target.value)} aria-label="新 API Key" />
              {!d.key && <button className="ae-mini is-accent" onClick={() => set('key', AE_DEMO_KEY)}>粘贴</button>}
            </span>
          </div>
          <div className="ae-hint">
            {d.key ? <>新密钥 <span className="mono">{aeMaskNew(d.key)}</span> · <span className="num">{d.key.trim().length}</span> 个字符；</> : '留空保持当前密钥；'}
            保存时再次确认{ctx.faceId ? '并验证 Face ID' : ''}
          </div>
        </>
      ) : (
        <AeF field="key" label="API Key" sub="已保存的密钥不可查看">
          <span className="ae-f-val"><span className="ae-has"><AeLock />已设置</span><button className="ae-mini is-accent" onClick={() => set('key', '')}>更换</button></span>
        </AeF>
      )}
      {baseUrl}
    </AeSec>
  );
}

function AeProxyKit({ f }) {
  const { d, set, ch, pick } = f;
  return (
    <AeSec title="代理" part="proxy">
      <AePick field="proxy" label="代理" value={<AeProxyVal name={d.proxy} />} changed={ch.proxy} hint={aeProxyHint(d.proxy)}
        onClick={() => pick('Proxy', { value: d.proxy, onDone: v => set('proxy', v) })} />
    </AeSec>
  );
}

function AeModelRow({ ctx, a, m, onRemove }) {
  const limit = (a.modelLimits || []).find(x => x.model === m.from);
  return (
    <div className="ae-f ae-model">
      <div className="ae-model-main">
        <span className="mono ae-model-from">{m.from}</span>
        {m.to
          ? <span className="ae-model-to"><Icon name="arrowRight" size={12} weight={2.4} /><span className="mono">{m.to}</span></span>
          : <span className="ae-model-to">原样转发</span>}
      </div>
      {limit && <span className="badge tone-model"><Icon name="cube" size={12} weight={2.4} />限流 {fmt.minutesLeft(limit.resetIn - ctx.elapsed)}</span>}
      {onRemove && <button className="ae-del" aria-label={`移除 ${m.from}`} onClick={onRemove}><AeMinus size={14} /></button>}
    </div>
  );
}

function AeModelsKit({ f }) {
  const { ctx, a, d, set, ch, pick } = f;
  const list = d.models;
  return (
    <AeSec title="模型" part="models" changed={ch.models} meta={list.length ? `只调度这 ${list.length} 个` : '未限制'}
      foot="列表为空时支持所有模型；列出后，没列出的模型不会调度到这个账号。映射把请求模型换成实际模型，* 只能放在末尾。">
      {d.adv.passthrough && <div className="ae-note"><Icon name="arrowRight" size={14} weight={2.4} />已开启自动透传，模型限制不生效</div>}
      {list.length === 0 && <div className={cx('ae-f ae-allmodels', ch.models && 'is-changed')} data-field="models">支持所有模型</div>}
      {list.map((m, i) => <AeModelRow key={m.from} ctx={ctx} a={a} m={m} onRemove={() => set('models', list.filter((_, j) => j !== i))} />)}
      <div className="ae-addrow">
        <button onClick={() => pick('Models', { platform: a.platform, value: list, onDone: v => set('models', v) })}><Icon name="plus" size={16} weight={2.6} />添加模型</button>
        <button onClick={() => pick('Map', { platform: a.platform, value: list, onDone: v => set('models', v) })}><Icon name="arrowRight" size={16} weight={2.4} />添加映射</button>
      </div>
    </AeSec>
  );
}

function AeAdvField({ def, v, onChange, changed, pick }) {
  const field = `adv.${def.key}`;
  if (def.kind === 'switch') return <AeSwitch field={field} label={def.label} sub={def.sub} on={v} onChange={onChange} changed={changed} />;
  if (def.kind === 'seg') return <AeF field={field} label={def.label} changed={changed}><AeSeg2 options={def.options} value={v} onChange={onChange} /></AeF>;
  if (def.kind === 'menu') {
    // Picker(.navigationLink) in the Form: the options open as a checkmark list (pushed inside the section sheet), pick pops back.
    const open = () => pick('Option', { title: def.label, options: def.options, value: v, onDone: onChange });
    return <AePick field={field} label={def.label} value={<span className="ae-v">{aeOpt(def, v)}</span>} onClick={open} changed={changed} />;
  }
  return (
    <>
      <AeSwitch field={field} label={def.label} sub={def.sub} on={v.on} onChange={on => onChange({ ...v, on })} changed={changed} />
      {v.on && <AeText indent label={def.field} prefix={def.unit} value={v.v} inputMode="decimal" onChange={x => onChange({ ...v, v: x })} />}
    </>
  );
}

// The phone cannot deep-link into one account's Web edit dialog (AccountsView ignores route params), so it opens the
// account list and copies the name for the search box.
const aeOpenWeb = (ctx, a) => ctx.showToast({ text: `已打开 Web 账号管理 · 已复制「${a.name}」，可直接搜索`, icon: 'web', tone: 'neutral' });

function AeWebRow({ ctx, a }) {
  return (
    <AeF label="在 Web 中编辑" sub={aeWebOnly(a)} onClick={() => aeOpenWeb(ctx, a)}>
      <span className="ae-f-val ae-web"><Icon name="web" size={18} weight={2} /></span>
    </AeF>
  );
}

function AeAdvKit({ f }) {
  const { ctx, a, d, setAdv, ch, pick } = f;
  return (
    <AeSec title="高级" part="adv" meta={`${a.platform} · ${a.type}`}>
      {aeAdvDefs(a).map(def => <AeAdvField key={def.key} def={def} v={d.adv[def.key]} onChange={v => setAdv(def.key, v)} changed={ch[`adv.${def.key}`]} pick={pick} />)}
      <AeWebRow ctx={ctx} a={a} />
    </AeSec>
  );
}

/* ---------- picker bodies (used in sheets, or pushed inside the part sheet) ---------- */

// Web GroupSelector over groups/all (active groups only, sort_order): the account's own platform plus composite groups; an
// Antigravity account with mixed scheduling (extra.mixed_scheduling) also gets Anthropic / Gemini groups. Groups the account is
// already in stay listed even when stopped or of another platform, so they can be taken out.
function aeGroupsFor(a) {
  const plats = [a.platform, 'composite', ...(a.platform === 'Antigravity' && a.mixed ? ['Anthropic', 'Gemini'] : [])];
  return DEMO.groups
    .filter(g => (g.status === 'active' && plats.includes(g.platform)) || (a.groups || []).includes(g.name))
    .sort((x, y) => x.sortOrder - y.sortOrder);
}

function AeGroupsBody({ ctx, a, value, onChange }) {
  const toggle = g => onChange(value.includes(g) ? value.filter(x => x !== g) : [...value, g]);
  const mixedRule = a.platform === 'Anthropic' || a.platform === 'Antigravity';
  const list = aeGroupsFor(a);
  return (
    <>
      <div className="ae-sheet-note">{a.platform === 'Antigravity' && a.mixed ? '已开启“在 /v1/messages 中使用”：列出 Antigravity、Anthropic、Gemini 分组和组合分组' : `只列出 ${a.platform} 分组和组合分组`} · 可多选</div>
      <div className="ae-plist">{!list.length && <div className="ae-f ae-allmodels">没有可加入的 {a.platform} 分组</div>}{list.map(g => {
        const on = value.includes(g.name);
        const off = g.status !== 'active';
        const av = groupAvailability(ctx.accounts, g.id);
        return (
          <Row key={g.name} skin={ctx.skin} tone="none" chevron={false} onClick={() => toggle(g.name)}
            lead={<span className={cx('select-ring', on && 'on')}>{on && <Icon name="check" size={14} weight={3} />}</span>}>
            <div className="row-top"><span className="row-title">{g.name}</span>
              <span className="ae-badges">
                {off && <span className="badge tone-neutral">停用</span>}
                {g.platform !== a.platform && <span className="badge tone-neutral">{g.platform === 'composite' ? '组合' : g.platform}</span>}
                {g.subscriptionType === 'subscription' && <span className="badge tone-neutral">订阅</span>}
                {g.exclusive && <span className="badge tone-neutral">专属</span>}
              </span>
            </div>
            <div className="row-meta">
              {off ? '分组已停用，不接收请求 · 可以移出' : <>倍率 <span className="num">×{g.rate}</span> · {av.total ? <>可用 <span className="num">{av.available}/{av.total}</span></> : '还没有账号'}</>}
            </div>
          </Row>
        );
      })}</div>
      {list.length > 0 && !list.some(g => g.status === 'active') && <div className="ae-sheet-note">没有启用的 {a.platform} 分组可加入；在“分组”里启用或新建后再来。</div>}
      {mixedRule && <div className="ae-sheet-note">Anthropic 与 Antigravity 账号进同一分组时，保存会先提示混合渠道风险</div>}
    </>
  );
}

// Web presets (accountExpiry.ts): now + 1 / 12 months, clamped to the month's end; “now” = the demo clock (today 09:41).
const aePad = n => String(n).padStart(2, '0');
const aeYmd = (y, m, d) => `${y}-${aePad(m + 1)}-${aePad(d)}`;
const aeStamp = t => `${aeYmd(t.getFullYear(), t.getMonth(), t.getDate())} ${aePad(t.getHours())}:${aePad(t.getMinutes())}`;
function aeExpiryIn(months) {
  const t = new Date(DEMO_CLOCK_BASE);
  const last = new Date(t.getFullYear(), t.getMonth() + months + 1, 0).getDate();
  t.setMonth(t.getMonth() + months, Math.min(t.getDate(), last));
  return aeStamp(t);
}
const AE_NOW = aeStamp(new Date(DEMO_CLOCK_BASE));
const AE_EXPIRY = [[null, '不过期'], [aeExpiryIn(1), '1 个月后'], [aeExpiryIn(12), '1 年后']];
// Device time zone (SwiftUI: TimeZone.current).
const AE_TZ = (() => {
  const off = -new Date(DEMO_CLOCK_BASE).getTimezoneOffset() / 60;
  return `${Intl.DateTimeFormat().resolvedOptions().timeZone || '本机时区'}（UTC${off >= 0 ? '+' : '−'}${Math.abs(off)}）`;
})();

// DatePicker(.graphical) + hour/minute, in the device time zone; the server stores expires_at to the second.
function AeCalendar({ value, onBack, onPick }) {
  const start = (value || aeExpiryIn(1)).slice(0, 10).split('-').map(Number);
  const [ym, setYm] = useState([start[0], start[1] - 1]);
  const [day, setDay] = useState(value ? value.slice(0, 10) : null);
  const [time, setTime] = useState(value && value.length > 10 ? value.slice(11, 16) : '23:59');
  const [y, m] = ym;
  const first = (new Date(y, m, 1).getDay() + 6) % 7;
  const days = new Date(y, m + 1, 0).getDate();
  const today = AE_NOW.slice(0, 10);
  // Today is allowed for a time still ahead; the expiry must lie in the future.
  const okTime = /^([01]\d|2[0-3]):[0-5]\d$/.test(time) && (!day || `${day} ${time}` > AE_NOW);
  const shift = n => setYm(([yy, mm]) => { const t = new Date(yy, mm + n, 1); return [t.getFullYear(), t.getMonth()]; });
  return (
    <>
      <button className="ae-cal-back" onClick={onBack}><Icon name="back" size={15} weight={2.4} />快捷选项</button>
      <div className="ae-cal">
        <div className="ae-cal-head">
          <b className="num">{y} 年 {m + 1} 月</b>
          <span>
            <button aria-label="上个月" onClick={() => shift(-1)}><Icon name="back" size={16} weight={2.4} /></button>
            <button aria-label="下个月" onClick={() => shift(1)}><Icon name="chevron" size={16} weight={2.4} /></button>
          </span>
        </div>
        <div className="ae-cal-grid">
          {['一', '二', '三', '四', '五', '六', '日'].map(w => <span key={w} className="ae-cal-w">{w}</span>)}
          {Array.from({ length: first }, (_, i) => <span key={`b${i}`} />)}
          {Array.from({ length: days }, (_, i) => {
            const id = aeYmd(y, m, i + 1);
            return <button key={id} className={cx('num', day === id && 'on', id === today && 'is-today')} disabled={id < today} onClick={() => setDay(id)}>{i + 1}</button>;
          })}
        </div>
      </div>
      <div className="ae-plist ae-cal-rows">
        <AeF label="时间"><span className="ae-f-val"><input className="ae-in num ae-time" value={time} inputMode="numeric" onChange={e => setTime(e.target.value)} aria-label="时间" /></span></AeF>
        <AeF label="时区"><span className="ae-f-val ae-ro">{AE_TZ}</span></AeF>
      </div>
      <button className="submit" disabled={!day || !okTime} onClick={() => onPick(`${day} ${time}`)}>{!day ? '选择日期' : okTime ? `到期时间 ${day} ${time}` : '到期时间要晚于现在'}</button>
    </>
  );
}

function AeExpiryBody({ ctx, value, onPick }) {
  const [cal, setCal] = useState(Boolean(value && value.length > 10 && !AE_EXPIRY.some(([v]) => v === value)));
  if (cal) return <AeCalendar value={value} onBack={() => setCal(false)} onPick={onPick} />;
  const opts = AE_EXPIRY.some(([v]) => v === value) ? AE_EXPIRY : [[value, '保持当前'], ...AE_EXPIRY];
  return (
    <>
      <div className="ae-plist">{opts.map(([v, label]) => (
        <Row key={label} skin={ctx.skin} tone="none" chevron={false} onClick={() => onPick(v)}
          lead={<span className={cx('st-radio', value === v && 'on')}>{value === v && <Icon name="check" size={12} weight={3.2} />}</span>}>
          <div className="row-top"><span className="row-title">{label}</span>{v && <span className="row-right num">{v}</span>}</div>
        </Row>
      ))}
        <Row skin={ctx.skin} tone="none" onClick={() => setCal(true)} lead={<span className="ae-lead-ic"><Icon name="compose" size={16} weight={2.2} /></span>}>
          <div className="row-top"><span className="row-title">自定义日期和时间…</span></div>
        </Row>
      </div>
      <div className="ae-sheet-note">按设备时区 {AE_TZ} 计算</div>
    </>
  );
}

// Picker over GET proxies/all?with_count=true: active proxies only (newest first), name + account count + protocol://host:port like
// Web ProxySelector, plus the expiry word of the proxies page. A current proxy that is no longer active is not in that list, so
// the sheet names it above the list instead of drawing an unselectable row.
function AeProxyBody({ ctx, value, onPick }) {
  const radio = on => <span className={cx('st-radio', on && 'on')}>{on && <Icon name="check" size={12} weight={3.2} />}</span>;
  const cur = value ? proxyOf(value) : null;
  const gone = cur && cur.status !== 'active';
  return (
    <>
      {gone && (
        <div className={cx('ae-px-cur', cur.status === 'expired' ? 'tone-critical' : 'tone-neutral')}>
          <Icon name={cur.status === 'expired' ? 'clockAlert' : 'pause'} size={16} weight={2.2} />
          <span>当前代理 <b>{cur.name}</b> {cur.status === 'expired' ? '已过期' : '已停用'}，不在可选列表里。选一个启用中的代理，或改为无代理。</span>
        </div>
      )}
      <div className="ae-plist">
        <Row skin={ctx.skin} tone="none" chevron={false} onClick={() => onPick(null)} lead={radio(!value)}>
          <div className="row-top"><span className="row-title">无代理</span></div>
          <div className="row-meta">直连上游</div>
        </Row>
        {aeActiveProxies().map(p => {
          const ex = proxyExpiry(p);
          const n = aeProxyUsers(ctx, p.name);
          return (
            <Row key={p.name} skin={ctx.skin} tone="none" chevron={false} onClick={() => onPick(p.name)} lead={radio(value === p.name)}>
              <div className="row-top"><span className="row-title">{p.name}</span>
                {ex.tone === 'caution' && <span className="badge tone-caution">{ex.label}</span>}
              </div>
              <div className="row-meta"><span className="mono">{aeProxyAddr(p)}</span></div>
              <div className="row-meta">{n ? <><span className="num">{n}</span> 个账号在用</> : '没有账号在用'}{p.region ? ` · ${p.region}` : ''}{ex.tone === 'caution' ? '' : ` · ${ex.label}`}</div>
            </Row>
          );
        })}
      </div>
      <div className="ae-sheet-note">只列出启用中的代理；已停用、已过期的代理在“代理”里管理。</div>
    </>
  );
}

// Picker options as a checkmark list (SwiftUI Picker .navigationLink / .inline).
function AeOptionBody({ ctx, options, value, onPick }) {
  return (
    <div className="ae-plist">{options.map(([k, l]) => (
      <Row key={k} skin={ctx.skin} tone="none" chevron={false} onClick={() => onPick(k)}
        lead={<span className={cx('st-radio', value === k && 'on')}>{value === k && <Icon name="check" size={12} weight={3.2} />}</span>}>
        <div className="row-top"><span className="row-title">{l}</span></div>
      </Row>
    ))}</div>
  );
}

function AeModelAddBody({ ctx, platform, value, onChange }) {
  const listed = value.map(m => m.from);
  const toggle = m => onChange(listed.includes(m) ? value.filter(x => x.from !== m) : [...value, { from: m }]);
  return (
    <>
      <div className="picker-group">这个账号可用的模型</div>
      <div className="ae-plist">{(AE_MODELS[platform] || []).map(m => {
        const on = listed.includes(m);
        const mapped = value.find(x => x.from === m && x.to);
        return (
          <Row key={m} skin={ctx.skin} tone="none" chevron={false} onClick={() => toggle(m)}
            lead={<span className={cx('select-ring', on && 'on')}>{on && <Icon name="check" size={14} weight={3} />}</span>}>
            <div className="row-top"><span className="row-title model">{m}</span></div>
            {mapped && <div className="row-meta">映射到 <span className="mono">{mapped.to}</span></div>}
          </Row>
        );
      })}</div>
    </>
  );
}

function AeMapBody({ platform, value, onAdd }) {
  const cands = AE_MODELS[platform] || [];
  const taken = value.map(m => m.from);
  const [from, setFrom] = useState(null);
  const [custom, setCustom] = useState('');
  const [to, setTo] = useState(null);
  const req = custom.trim() || from;
  const badWild = req && req.includes('*') && req.indexOf('*') !== req.length - 1;
  const ok = req && to && !badWild && !taken.includes(req) && req !== to;
  const chip = (m, on, pickIt, disabled) => <button key={m} className={cx('chip mono ae-mchip', on && 'on')} disabled={disabled} onClick={pickIt}>{m}</button>;
  return (
    <>
      <div className="picker-group">请求模型</div>
      <div className="ae-mchips">{[...(AE_WILDCARDS[platform] || []), ...cands].map(m => chip(m, !custom && from === m, () => { setCustom(''); setFrom(m); }, taken.includes(m)))}</div>
      <label className="search-field ae-custom"><Icon name="compose" size={15} /><input className="mono" placeholder="或输入其他请求模型" value={custom} onChange={e => setCustom(e.target.value)} /></label>
      <div className="picker-group">实际模型</div>
      <div className="ae-mchips">{cands.map(m => chip(m, to === m, () => setTo(m), m === req))}</div>
      <div className={cx('ae-map-preview', badWild && 'is-error')}>
        {badWild ? '通配符 * 只能放在末尾' : <><span className="mono">{req || '请求模型'}</span><Icon name="arrowRight" size={14} weight={2.4} /><span className="mono">{to || '实际模型'}</span></>}
      </div>
      <button className="submit" disabled={!ok} onClick={() => onAdd([...value, { from: req, to }])}>添加映射</button>
    </>
  );
}

/* ---------- sheets ---------- */

// Same chrome as core Sheet, but the leading button and the backdrop can do different things (back vs dismiss).
function AeSheetFrame({ title, leadingLabel, onLeading, onDismiss, trailing, children, tall = true }) {
  return (
    <div className="overlay overlay-dim sheet-overlay" onClick={onDismiss}>
      <div className={cx('sheet', tall && 'sheet-tall', 'ae-sheet')} onClick={e => e.stopPropagation()}>
        <div className="sheet-grabber" />
        <div className="sheet-bar">
          <button className="glass-btn glass-btn-text" onClick={onLeading}>{leadingLabel === '返回' && <Icon name="back" size={16} weight={2.4} />}<span>{leadingLabel}</span></button>
          <div className="sheet-title">{title}</div>
          {trailing || <span className="nav-spacer" />}
        </div>
        <div className="sheet-body">{children}</div>
      </div>
    </div>
  );
}
const AeDone = ({ onClick, label = '完成', disabled }) => (
  <button className={cx('glass-btn glass-btn-text ae-save', !disabled && 'glass-prominent')} disabled={disabled} onClick={onClick}><span>{label}</span></button>
);

function AeGroupsSheet({ ctx, sheet }) {
  const [sel, setSel] = useState(sheet.value);
  return (
    <Sheet title="分组" onClose={ctx.closeSheet} tall trailing={<AeDone onClick={() => { sheet.onDone(sel); ctx.closeSheet(); }} />}>
      <AeGroupsBody ctx={ctx} a={ctx.accounts[sheet.id]} value={sel} onChange={setSel} />
    </Sheet>
  );
}
function AeExpirySheet({ ctx, sheet }) {
  return (
    <Sheet title="过期时间" onClose={ctx.closeSheet} tall>
      <AeExpiryBody ctx={ctx} value={sheet.value} onPick={v => { sheet.onDone(v); ctx.closeSheet(); }} />
    </Sheet>
  );
}
function AeProxySheet({ ctx, sheet }) {
  return (
    <Sheet title="代理" onClose={ctx.closeSheet} tall>
      <AeProxyBody ctx={ctx} value={sheet.value} onPick={v => { sheet.onDone(v); ctx.closeSheet(); }} />
    </Sheet>
  );
}
function AeOptionSheet({ ctx, sheet }) {
  return (
    <Sheet title={sheet.title} onClose={ctx.closeSheet} tall>
      <AeOptionBody ctx={ctx} options={sheet.options} value={sheet.value} onPick={v => { sheet.onDone(v); ctx.closeSheet(); }} />
    </Sheet>
  );
}
function AeModelsSheet({ ctx, sheet }) {
  const [sel, setSel] = useState(sheet.value);
  return (
    <Sheet title="添加模型" onClose={ctx.closeSheet} tall trailing={<AeDone onClick={() => { sheet.onDone(sel); ctx.closeSheet(); }} />}>
      <AeModelAddBody ctx={ctx} platform={sheet.platform} value={sel} onChange={setSel} />
    </Sheet>
  );
}
function AeMapSheet({ ctx, sheet }) {
  return (
    <Sheet title="添加映射" onClose={ctx.closeSheet} tall>
      <AeMapBody platform={sheet.platform} value={sheet.value} onAdd={v => { sheet.onDone(v); ctx.closeSheet(); }} />
    </Sheet>
  );
}

// ①② (applyNow false): the key waits for 保存. ③ (applyNow true): the sheet is the confirmation — its red button replaces the
// key at once (Face ID afterwards when enabled). Only what was just pasted is ever shown, as prefix••••last4 plus its length.
function AeKeySheet({ ctx, sheet }) {
  const a = ctx.accounts[sheet.id];
  const [k, setK] = useState('');
  const now = Boolean(sheet.applyNow);
  return (
    <Sheet title="更换 API Key" onClose={ctx.closeSheet}>
      <div className="sheet-target"><span>{a.name}</span><small>{now ? '点按底部按钮后立即生效' : '保存账号时生效，站点不再使用旧密钥'}</small></div>
      <div className="picker-group">新 API Key</div>
      <label className="ae-keyfield">
        <input className="mono" type="password" placeholder="粘贴新的 API Key" value={k} onChange={e => setK(e.target.value)} aria-label="新 API Key" />
        {!k && <button className="ae-mini is-accent" onClick={() => setK(AE_DEMO_KEY)}>粘贴</button>}
      </label>
      <div className="ae-keynote">{k ? <>新密钥 <span className="mono">{aeMaskNew(k)}</span> · <span className="num">{k.trim().length}</span> 个字符</> : '当前密钥已设置，不可查看'}</div>
      <button className={cx('submit', now && k && 'ae-submit-danger')} disabled={!k} onClick={() => { ctx.closeSheet(); sheet.onDone(k); }}>{now ? '更换 API Key' : '使用这个密钥'}</button>
      {now && <div className="ae-keynote ae-center">站点立即改用新密钥，旧密钥不再保存、不能找回；如果旧密钥泄露，请到上游控制台吊销{ctx.faceId ? '。点按后验证 Face ID' : ''}</div>}
    </Sheet>
  );
}

// ③ Base URL (credentials.base_url): same pattern as the key — the button applies it at once; empty = the official address.
function AeUrlSheet({ ctx, sheet }) {
  const a = ctx.accounts[sheet.id];
  const [url, setUrl] = useState(sheet.value || '');
  const v = url.trim();
  const bad = v !== '' && !/^https?:\/\/[^\s/]+/.test(v);
  const changed = v !== (sheet.value || '');
  return (
    <Sheet title="Base URL" onClose={ctx.closeSheet}>
      <div className="sheet-target"><span>{a.name}</span><small>点按底部按钮后立即生效</small></div>
      <div className="picker-group">Base URL</div>
      <label className="ae-keyfield">
        <input className="mono" inputMode="url" placeholder="留空使用官方地址" value={url} onChange={e => setUrl(e.target.value)} aria-label="Base URL" aria-invalid={bad} />
        {url && <button className="ae-mini" onClick={() => setUrl('')}>清空</button>}
      </label>
      <div className={cx('ae-keynote', bad && 'tone-critical tone-text')}>{bad ? '地址要以 http:// 或 https:// 开头' : v ? '请求改发到这个地址' : '留空：使用官方地址'}</div>
      <button className="submit" disabled={!changed || bad} onClick={() => { ctx.closeSheet(); sheet.onDone(v); }}>{changed && !v ? '改回官方地址' : '保存 Base URL'}</button>
    </Sheet>
  );
}

// Re-authorize: the platform's auth-url → the admin signs in on the provider page → paste the code / callback → exchange-code →
// POST :id/apply-oauth-credentials (stores the token and clears the account's blocks; the schedule switch is untouched).
// The sheet is the confirmation: the red button stores the new token right away (Face ID afterwards when enabled), so the
// one-time code is never wasted on a later "are you sure?".
function aeReauthNote(a, type) {
  const models = (a.modelLimits || []).length;
  const what = [AE_CLEARED[a.state], models ? ` ${models} 项模型限流` : null].filter(Boolean).join('和');
  const as = type ? `，账号类型改为 ${aeTypeWord(type)}` : '';
  const clear = a.state === 'inactive' ? '，并重新启用账号' : what ? `，并清除${what}` : '';
  const stays = a.state === 'error' ? '出错时已停止调度，之后仍暂停。' : what && !isSchedulable(a) ? '账号已停止调度，之后仍暂停。' : '';
  return `点按后立即保存新令牌${as}${clear}；调度开关不变。${stays}站点不再使用旧令牌，不能撤回`;
}
// Claude accounts pick the method like Web's ReAuthAccountModal (授权方式 OAuth / Setup Token, preselected from the account type):
// OAuth = generate-auth-url · exchange-code with the full scope, Setup Token = generate-setup-token-url · exchange-setup-token-code
// with user:inference only. apply-oauth-credentials stores the picked type, so picking the other one converts the account.
const AE_REAUTH_METHODS = [{ key: 'OAuth', label: 'OAuth' }, { key: 'Setup Token', label: 'Setup Token' }];
const AE_REAUTH_SCOPE = { OAuth: '完整权限', 'Setup Token': '只授予推理权限' };
function AeReauthSheet({ ctx, sheet }) {
  const a = ctx.accounts[sheet.id];
  const claude = aeIsClaudeToken(a);
  const [method, setMethod] = useState(a.type === 'Setup Token' ? 'Setup Token' : 'OAuth');
  const setup = claude && method === 'Setup Token';
  const switchTo = claude && method !== a.type ? method : null;
  const p = setup ? AE_OAUTH_SETUP : AE_OAUTH[a.platform] || AE_OAUTH.Anthropic;
  const [url, setUrl] = useState(false);
  const [code, setCode] = useState('');
  // A link belongs to its method's auth session, so another method drops the link and the pasted code.
  const pickMethod = m => { if (m === method) return; setMethod(m); setUrl(false); setCode(''); };
  const step = !url ? 1 : !code ? 3 : 4;
  const toast = (text, icon) => ctx.showToast({ text, icon, tone: 'neutral' });
  const back = p.back === 'code'
    ? '登录要授权的那个账号。授权后页面会显示授权码，复制它。'
    : `登录要授权的那个账号。授权后浏览器跳到 ${p.cb} 的页面（打不开是正常的），拷贝地址栏里的链接。`;
  return (
    <Sheet title="重新授权" onClose={ctx.closeSheet} tall>
      <div className="sheet-target"><span>{a.name}</span><small>{sheet.proxy ? `授权走已保存的代理 ${sheet.proxy}；分组、并发和代理设置不变` : '账号没有代理，授权页直连打开'}</small></div>
      <ol className="ae-steps">
        <li className={cx(url && 'is-done', step === 1 && 'is-now')}>
          <span className="ae-step-no num">{url ? <Icon name="check" size={13} weight={3} /> : 1}</span>
          <div className="ae-step-body"><b>授权链接</b>
            {claude && (
              <div className="ae-reauth-method" data-field="reauthMethod">
                <Segmented items={AE_REAUTH_METHODS} value={method} onChange={pickMethod} />
                <span className={cx('ae-reauth-scope', switchTo && 'is-switch')}>{AE_REAUTH_SCOPE[method]}{switchTo ? ` · 授权后账号类型改为 ${aeTypeWord(switchTo)}` : ''}</span>
              </div>
            )}
            {!url && <button className="act act-primary ae-step-btn" onClick={() => setUrl(true)}><span>生成授权链接</span></button>}
            {url && <span className="mono ae-url">{p.url}</span>}
            {url && sheet.proxy && <span>授权页要从代理 {sheet.proxy} 的出口打开；手机做不到时，复制链接到走同一代理的电脑上打开</span>}
            {url && (
              <span className="ae-step-acts">
                <button className="act ae-step-btn" onClick={() => toast('已复制授权链接', 'docCheck')}><span>复制链接</span></button>
                <button className="act ae-step-btn" onClick={() => toast('已在 Safari 打开授权页', 'web')}><Icon name="web" size={16} weight={2.4} /><span>打开</span></button>
              </span>
            )}
          </div>
        </li>
        <li className={cx(url && !code && 'is-now', code && 'is-done')}>
          <span className="ae-step-no num">{code ? <Icon name="check" size={13} weight={3} /> : 2}</span>
          <div className="ae-step-body"><b>登录 {a.platform} 并授权</b><span>{back}</span></div>
        </li>
        <li className={cx(code && 'is-done')}>
          <span className="ae-step-no num">{code ? <Icon name="check" size={13} weight={3} /> : 3}</span>
          <div className="ae-step-body"><b>粘贴{p.code}</b>
            <label className={cx('ae-keyfield ae-codefield', !url && 'is-off')}>
              <input className="mono" placeholder={p.placeholder} value={code} onChange={e => setCode(e.target.value)} aria-label={p.code} disabled={!url} />
              {url && !code && <button className="ae-mini is-accent" onClick={() => setCode(p.demo)}>粘贴</button>}
              {code && <button className="ae-mini" onClick={() => setCode('')}>清空</button>}
            </label>
          </div>
        </li>
      </ol>
      <button className="submit ae-submit-danger" disabled={!url || !code} onClick={() => { ctx.closeSheet(); sheet.onDone(switchTo || undefined); }}>替换令牌</button>
      <div className="ae-keynote ae-center">{aeReauthNote(a, switchTo)}{ctx.faceId ? '；之后验证 Face ID' : ''}</div>
    </Sheet>
  );
}

// Every 重新授权… entry (credential row, ⋯, the state card's primary button) opens the sheet through here. apply-oauth-credentials
// ends in ClearAccountError, which sets status active, so a disabled account asks first (user decision) — before the one-time code
// exists, so nothing is wasted by cancelling.
function aeOpenReauth(ctx, a, proxy, onDone) {
  const open = () => ctx.openSheet({ kind: 'aeReauth', id: a.id, proxy, onDone });
  if (a.state !== 'inactive') return open();
  ctx.confirm({
    title: `重新授权「${a.name}」？`,
    message: `这个账号现在是停用状态。授权后账号会被重新启用${isSchedulable(a) ? '并参与调度' : '，调度仍暂停'}。`,
    actions: [{ label: '继续授权', role: 'default', onPress: open }, { label: '取消', role: 'cancel' }],
  });
}

// ③ one small form per section; pickers push inside this sheet instead of stacking another sheet.
const AE_PART_TITLES = { basic: '编辑基础信息', sched: '编辑调度', models: '编辑模型', adv: '编辑高级设置' };
function AePartSheet({ ctx, sheet }) {
  const a = ctx.accounts[sheet.id];
  const [d, setD] = useState(sheet.value);
  const [sub, setSub] = useState(null);
  const set = (k, v) => setD(s => ({ ...s, [k]: v }));
  const setAdv = (k, v) => setD(s => ({ ...s, adv: { ...s.adv, [k]: v } }));
  const changes = aeDiff(a, sheet.value, d).filter(c => c.part === sheet.part);
  const err = aeInvalid(d);
  const ok = changes.length > 0 && !Object.keys(err).length;
  const f = { ctx, a, d, set, setAdv, ch: Object.fromEntries(changes.map(c => [c.key, true])), err, pick: (kind, props) => setSub({ kind, ...props }) };
  const close = () => aeLeave(ctx, changes, ctx.closeSheet);
  if (sub) {
    const back = () => setSub(null);
    const titles = { Groups: '分组', Expiry: '过期时间', Models: '添加模型', Map: '添加映射', Option: sub.title };
    let body;
    if (sub.kind === 'Groups') body = <AeGroupsBody ctx={ctx} a={a} value={d.groups} onChange={v => set('groups', v)} />;
    else if (sub.kind === 'Expiry') body = <AeExpiryBody ctx={ctx} value={d.expires} onPick={v => { set('expires', v); back(); }} />;
    else if (sub.kind === 'Models') body = <AeModelAddBody ctx={ctx} platform={a.platform} value={d.models} onChange={v => set('models', v)} />;
    else if (sub.kind === 'Option') body = <AeOptionBody ctx={ctx} options={sub.options} value={sub.value} onPick={v => { sub.onDone(v); back(); }} />;
    else body = <AeMapBody platform={a.platform} value={d.models} onAdd={v => { set('models', v); back(); }} />;
    return <AeSheetFrame title={titles[sub.kind]} leadingLabel="返回" onLeading={back} onDismiss={close}>{body}</AeSheetFrame>;
  }
  const kit = {
    basic: <AeBasicKit f={f} />,
    sched: <><AeSchedKit f={f} /><AeQuotaKit f={f} /></>,
    models: <AeModelsKit f={f} />,
    adv: <AeAdvKit f={f} />,
  }[sheet.part];
  return (
    <AeSheetFrame title={AE_PART_TITLES[sheet.part]} leadingLabel="取消" onLeading={close} onDismiss={close} tall={sheet.part !== 'basic'}
      trailing={<AeDone label="保存" disabled={!ok} onClick={() => { ctx.closeSheet(); sheet.onSave(d, changes); }} />}>
      {kit}
    </AeSheetFrame>
  );
}

/* ---------- change bar ---------- */

function AeBar({ changes, open, setOpen, onRevert, onRevertOne, onJump }) {
  if (!changes.length) return null;
  return (
    <div className={cx('ae-bar glass', open && 'is-open')}>
      {open && (
        <div className="ae-bar-list">
          {changes.map(c => (
            <div key={c.key} className="ae-bar-item">
              <button className="ae-bar-go" onClick={() => onJump(c)}>
                <span className="ae-bar-label">{c.label}</span>
                <span className="ae-bar-diff"><span className="ae-from">{c.from}</span><Icon name="arrowRight" size={12} weight={2.4} /><span className="ae-to">{c.to}</span></span>
              </button>
              <button className="ae-bar-one" onClick={() => onRevertOne(c)} aria-label={`还原${c.label}`}>还原</button>
            </div>
          ))}
        </div>
      )}
      <div className="ae-bar-row">
        <button className="ae-bar-sum" onClick={() => setOpen(!open)} aria-expanded={open}>
          <span className="ae-bar-count"><b className="num">{changes.length}</b> 项改动</span>
          <span className="ae-bar-names">{open ? '点按一项跳到那一行' : changes.map(c => c.label).join('、')}</span>
          <Icon name={open ? 'chevronDown' : 'chevronUp'} size={14} weight={2.6} />
        </button>
        <button className="ae-bar-revert" onClick={onRevert}>{open ? '全部还原' : '还原'}</button>
      </div>
    </div>
  );
}

const aeScroller = anchor => anchor && anchor.closest('.scroll');
const aeScrollTo = (anchor, part) => {
  const scroller = aeScroller(anchor);
  const target = scroller && scroller.querySelector(`[data-part="${part}"]`);
  if (target) scroller.scrollTop = target.getBoundingClientRect().top - scroller.getBoundingClientRect().top + scroller.scrollTop - 6;
};
// ScrollViewReader.scrollTo(field id) + a short highlight; focus the input when jumping to an invalid field.
function aeJumpTo(anchor, field, part, focus) {
  const scroller = aeScroller(anchor);
  if (!scroller) return;
  const t = scroller.querySelector(`[data-field="${field}"]`) || scroller.querySelector(`[data-part="${part}"]`);
  if (!t) return;
  const top = t.getBoundingClientRect().top - scroller.getBoundingClientRect().top + scroller.scrollTop;
  scroller.scrollTop = Math.max(0, top - scroller.clientHeight * 0.3);
  t.classList.remove('ae-flash');
  void t.offsetWidth;
  t.classList.add('ae-flash');
  setTimeout(() => t.classList.remove('ae-flash'), 1400);
  const input = focus && t.querySelector('input, textarea');
  if (input) input.focus({ preventScroll: true });
}

/* ---------- structures ① base and ② seg ---------- */

// Compact identity strip under the navigation bar (echoes B's pass card): platform, current state, countdown.
function AeIdStrip({ ctx, a }) {
  const meta = STATE_META[a.state];
  const secs = remaining(a, ctx.elapsed);
  return (
    <div className="ae-id">
      <span className="ae-id-plat"><b>{a.platform}</b> · {a.type}</span>
      <span className="ae-id-state">
        {a.state === 'normal' ? <span className="badge tone-ok">正常</span> : <ctx.skin.Badge state={a.state} />}
        {schedLabel(a) && <span className="badge tone-neutral">{schedLabel(a)}</span>}
        {meta.timed && secs > 0 && <span className="ae-id-time"><span className="num">{fmt.countdown(secs)}</span> 后恢复</span>}
      </span>
    </div>
  );
}

function AeEditor({ ctx, route, layout }) {
  const a = ctx.accounts[route.id];
  const [init] = useState(() => (a.aeDraft ? a.aeDraft.init : aeProfile(a)));
  const [d, setD] = useState(() => (a.aeDraft ? a.aeDraft.d : aePreset(a, init, route.preset)));
  const parked = a.aeDraft;
  const [part, setPart] = useState(() => (parked && parked.part) || (AE_PARTS.some(p => p.key === route.focus) ? route.focus : route.focus === 'proxy' ? 'cred' : 'basic'));
  const [open, setOpen] = useState(Boolean(route.openChanges));
  const [face, setFace] = useState(null);
  const anchor = useRef(null);
  const pending = useRef(null);
  const token = aeToken(ctx, a);
  const changes = aeDiff(a, init, d);
  const err = aeInvalid(d);
  const set = (k, v) => setD(s => ({ ...s, [k]: v }));
  const setAdv = (k, v) => setD(s => ({ ...s, adv: { ...s.adv, [k]: v } }));
  const pick = (kind, props) => ctx.openSheet({ kind: `ae${kind}`, id: a.id, ...props });
  const f = { ctx, a, d, set, setAdv, ch: Object.fromEntries(changes.map(c => [c.key, true])), err, pick };
  const mode = ctx.v.aeCred || 'row';
  // Only the top screen is mounted: park the draft (and where the form was scrolled) before pushing another page over it.
  const pushOver = next => {
    const box = aeScroller(anchor.current);
    ctx.updateAccount(a.id, { aeDraft: { init, d, part, scroll: box ? box.scrollTop : 0 } });
    ctx.push(next);
  };

  useEffect(() => {
    if (parked) {
      ctx.updateAccount(a.id, { aeDraft: null });
      const box = aeScroller(anchor.current);
      if (box) box.scrollTop = parked.scroll || 0;
      return;
    }
    if (layout === 'base' && route.focus) aeScrollTo(anchor.current, route.focus);
  }, []);
  const keepScroll = useRef(Boolean(parked));
  useEffect(() => {
    if (layout !== 'seg' || !anchor.current) return;
    if (keepScroll.current) { keepScroll.current = false; return; }
    if (pending.current) { const j = pending.current; pending.current = null; aeJumpTo(anchor.current, j.key, j.part, j.focus); } else aeScroller(anchor.current).scrollTop = 0;
  }, [part]);

  const goTo = (key, focus) => {
    const p = aePartOf(key);
    setOpen(false);
    if (layout === 'seg' && p !== part) { pending.current = { key, part: p, focus }; setPart(p); } else aeJumpTo(anchor.current, key, p, focus);
  };
  const exit = patch => { ctx.updateAccount(a.id, { ...(patch || {}), ...AE_CLEAR }); ctx.pop(); };
  const cred = {
    mode, left: token.left, at: token.at, replaced: a.aeKeyReplaced, proxyDirty: d.proxy !== init.proxy, onRefresh: token.refresh,
    onReauth: () => aeOpenReauth(ctx, a, init.proxy, type => aeGuard(ctx, () => token.renew(type), setFace)),
    onReplace: () => ctx.openSheet({ kind: 'aeKey', id: a.id, onDone: k => set('key', k) }),
    onOpenPage: () => pushOver({ kind: 'aeCred', id: a.id }),
    onLogs: () => pushOver(aeUpstreamRoute(a)),
  };
  const kits = {
    basic: <AeBasicKit f={f} />,
    sched: <><AeSchedKit f={f} /><AeQuotaKit f={f} /></>,
    cred: <><AeCredKit f={f} cred={cred} /><AeProxyKit f={f} /></>,
    models: <AeModelsKit f={f} />,
    adv: <AeAdvKit f={f} />,
  };
  const errKeys = Object.keys(err);
  // 保存 stays tappable while something is invalid: it jumps to the first invalid field and focuses it.
  const save = () => (errKeys.length ? goTo(errKeys[0], true) : aeCommit(ctx, a, changes, d.groups, () => exit(aePatch(a, d)), setFace));
  const revert = () => {
    const before = d;
    setD(init); setOpen(false);
    ctx.showToast({ text: '已还原全部改动', icon: 'restore', tone: 'neutral', undo: () => setD(before) });
  };
  const revertOne = c => (c.key.startsWith('adv.') ? setAdv(c.key.slice(4), init.adv[c.key.slice(4)]) : set(c.key, init[c.key]));
  const dirtyParts = new Set(changes.map(c => c.part));
  const nav = (
    <>
      <NavBar ctx={ctx} title="编辑账号" subtitle={a.name}
        leading={<GlassButton label="取消" onClick={() => aeLeave(ctx, changes, () => exit(), a.aeDid)} />}
        trailing={<AeDone label="保存" disabled={!changes.length} onClick={save} />} />
      <AeIdStrip ctx={ctx} a={a} />
      {layout === 'seg' && (
        <div className="ae-segbar">
          <div className="seg ae-seg" role="tablist">
            {AE_PARTS.map(p => (
              <button key={p.key} role="tab" aria-selected={part === p.key} className={cx('seg-item', part === p.key && 'on')} onClick={() => setPart(p.key)}>
                {p.label}{dirtyParts.has(p.key) && <i className="ae-seg-dot" aria-label="有改动" />}
              </button>
            ))}
          </div>
        </div>
      )}
    </>
  );
  return (
    <Screen ctx={ctx} nav={nav} footer={<>
      <AeBar changes={changes} open={open} setOpen={setOpen} onRevert={revert} onRevertOne={revertOne} onJump={c => goTo(c.key)} />
      {aeFaceHud(face, setFace)}
    </>}>
      <i className="ae-notabs" ref={anchor} hidden />
      <div className={cx('ae-body', `ae-layout-${layout}`)}>
        {layout === 'seg' ? kits[part] : AE_PARTS.map(p => <React.Fragment key={p.key}>{kits[p.key]}</React.Fragment>)}
      </div>
    </Screen>
  );
}

const AeEditBase = props => <AeEditor {...props} layout="base" />;
const AeEditSeg = props => <AeEditor {...props} layout="seg" />;

/* ---------- ③ inline (decided): the account detail page itself, editable section by section ---------- */

// The sections are the editor, so ⋯ has no 编辑账号. It repeats the credential actions (the 凭据 section sits two screens down,
// and an errored key is the usual reason to open this page); delete stays last (core confirmDelete: name typed, or Face ID).
function aeInlineMenu(ctx, a, cred) {
  const credActions = aeIsKey(a)
    ? [{ label: '更换 API Key…', role: 'default', onPress: cred.onKey }]
    : [{ label: '刷新令牌', role: 'default', onPress: cred.onRefresh }, { label: '重新授权…', role: 'default', onPress: cred.onReauth }];
  ctx.menu({
    title: a.name,
    actions: [
      ...credActions,
      { label: '在 Web 中编辑', role: 'default', onPress: () => aeOpenWeb(ctx, a) },
      { label: '删除账号…', role: 'destructive', onPress: () => confirmDelete(ctx, '账号', a.name, ctx.pop) },
    ],
  });
}

// What the page shows. Fields the demo account carries (name, state, concurrency, groups, proxy, expiry) are read from it, so the
// hero's 启用账号 or the schedule switch stay in sync; the rest (notes, rate, models, advanced …) persists on a.aeSaved because the
// prototype mounts only the top screen (the app keeps one @Observable account model instead).
function aeCurrent(a) {
  const live = aeProfile(a);
  const kept = a.aeSaved || live;
  return { ...kept, name: live.name, status: live.status, conc: live.conc, priority: live.priority, groups: live.groups, proxy: live.proxy, expires: live.expires };
}

// Read-only form row (SwiftUI LabeledContent). onClick adds a chevron; button is a trailing mini button (更换 / 修改).
function AeInfo({ label, sub, field, onClick, button, hint, children }) {
  return (
    <AeF label={label} sub={sub} field={field} onClick={onClick} hint={hint}>
      <span className="ae-f-val">
        {children}{button}
        {onClick && <span className="ae-chev"><Icon name="chevron" size={13} weight={2.6} /></span>}
      </span>
    </AeF>
  );
}
const AeMini = ({ label, onClick }) => (
  <button className="ae-mini is-accent" onClick={e => { e.stopPropagation(); onClick(); }}>{label}</button>
);
const aeTextVal = (text, dim) => <span className={cx('ae-v', dim ? 'ae-dim' : 'ae-ink')}>{text}</span>;
const aeNumVal = text => <span className="ae-v ae-ink num">{text}</span>;

function AeInlineBasic({ a, s, onEdit }) {
  const statusTone = s.status === 'error' ? 'ae-v tone-critical tone-text' : s.status === 'inactive' ? 'ae-v ae-dim' : 'ae-v ae-ink';
  return (
    <AeSec title="基础" part="basic" action="编辑" onAction={onEdit}>
      <AeInfo field="name" label="名称">{aeTextVal(s.name)}</AeInfo>
      <AeInfo field="status" label="账号状态"><span className={statusTone}>{aeShow('status', s.status)}</span></AeInfo>
      <AeInfo label="平台">{aeTextVal(`${a.platform} · ${a.type}`)}</AeInfo>
      {s.notes
        ? <AeF field="notes" label="备注" col className="ae-f-notes"><span className="ae-notes">{s.notes}</span></AeF>
        : <AeInfo field="notes" label="备注">{aeTextVal('—', true)}</AeInfo>}
    </AeSec>
  );
}

function AeInlineSched({ a, s, onEdit }) {
  const used = aeQuotaUsed(a);
  // extra.quota_*_limit: only the limits that are set; none set reads as one 配额 row.
  const limits = [['quotaDaily', '日限额', used.daily], ['quotaWeekly', '周限额', used.weekly], ['quotaTotal', '总限额', used.total]].filter(([k]) => s[k]);
  const quotas = !aeIsKey(a) ? null : limits.length
    ? limits.map(([k, label, u]) => <AeInfo key={k} field={k} label={label} sub={u !== undefined ? `已用 ${fmt.money(u)}` : null}>{aeNumVal(`$${s[k]}`)}</AeInfo>)
    : <AeInfo field="quotaDaily" label="配额" sub="日 / 周 / 总限额">{aeTextVal('不限', true)}</AeInfo>;
  return (
    <AeSec title="调度" part="sched" action="编辑" onAction={onEdit}>
      <AeInfo field="conc" label="并发数">{aeNumVal(s.conc ?? '—')}</AeInfo>
      <AeInfo field="priority" label="优先级" sub="越小越优先">{aeNumVal(s.priority)}</AeInfo>
      <AeInfo field="rate" label="账号计费倍率" sub="0 表示不计费，仅影响账号计费">{aeNumVal(`×${s.rate}`)}</AeInfo>
      <AeInfo field="load" label="负载因子" sub="越大越常被选中">{s.load === '' || s.load === '0' ? aeTextVal('默认', true) : aeNumVal(s.load)}</AeInfo>
      <AeInfo field="groups" label="分组"><AeChipsVal items={s.groups} empty="未分组" /></AeInfo>
      <AeInfo field="expires" label="过期时间" sub={s.expires && s.autoPause ? '到期自动暂停调度' : null}>
        {s.expires ? aeNumVal(s.expires) : aeTextVal('不过期', true)}
      </AeInfo>
      {quotas}
    </AeSec>
  );
}

// Credentials as form rows. A saved key is write-only (credentials_status.has_api_key), so the row says it is set and offers 更换.
// The newest upstream error already sits on the status card (core AccountDetailTop), so this row only says what the key needs.
function AeInlineCred({ ctx, a, s, token, onKey, onUrl, onReauth }) {
  if (!aeIsKey(a)) {
    const tone = aeTokenTone(token.left);
    return (
      <AeSec title="凭据" part="cred" foot="令牌到期前自动刷新。刷新令牌、重新授权都立即生效，不能撤销；重新授权会同时清除错误、限流状态（停用的账号会被重新启用），调度开关不变。">
        <AeInfo field="token" label="访问令牌">
          <span className={cx('badge', `tone-${tone}`)}>{AE_TOKEN_WORD[tone]}</span>
          <span className="ae-v ae-ink">{aeLeftTiny(token.left)}<span className="ae-dim">（到期 <span className="num">{token.at}</span>）</span></span>
        </AeInfo>
        <AeAct field="refresh" icon="refresh" label="刷新令牌" now onClick={token.refresh} />
        <AeAct field="reauth" icon="restore" label="重新授权…" now onClick={onReauth} />
      </AeSec>
    );
  }
  const failed = isCredentialError(a);
  let hint = null;
  if (failed && a.aeKeyReplaced) hint = '已更换：测试连接通过后自动清除错误（仍暂停调度）';
  else if (failed) hint = <span className="ae-evid"><Icon name="octagon" size={13} weight={2.4} />上游拒绝了这个密钥{aeErrCode(a) ? `（${aeErrCode(a)}）` : ''}，需要更换</span>;
  return (
    <AeSec title="凭据" part="cred" foot="已保存的密钥不可查看，只能更换。更换立即生效、不能撤销；站点不再保存旧密钥，但它在上游仍然有效，泄露时请到上游控制台吊销。">
      <AeInfo field="key" label="API Key" hint={hint} button={<AeMini label="更换" onClick={onKey} />}>
        <span className="ae-has"><AeLock />{a.aeKeyReplaced ? <>已更换 · <span className="num">{aeClock(a.aeKeyAt || 0)}</span></> : '已设置 · 不可查看'}</span>
      </AeInfo>
      <AeInfo field="baseUrl" label="Base URL" button={<AeMini label="修改" onClick={onUrl} />}>
        {s.baseUrl ? <span className="ae-v ae-ink mono ae-url-v">{s.baseUrl}</span> : aeTextVal('官方地址', true)}
      </AeInfo>
    </AeSec>
  );
}

function AeInlineModels({ ctx, a, s, onEdit }) {
  return (
    <AeSec title="模型" part="models" action="编辑" onAction={onEdit} meta={s.models.length ? `只调度这 ${s.models.length} 个` : '未限制'}>
      {s.adv.passthrough && <div className="ae-note"><Icon name="arrowRight" size={14} weight={2.4} />已开启自动透传，模型限制不生效</div>}
      {s.models.length === 0
        ? <div className="ae-f ae-allmodels" data-field="models">支持所有模型</div>
        : s.models.map(m => <AeModelRow key={m.from} ctx={ctx} a={a} m={m} />)}
    </AeSec>
  );
}

function AeInlineAdv({ ctx, a, s, onEdit }) {
  const defs = aeAdvDefs(a);
  return (
    <AeSec title="高级" part="adv" action={defs.length ? '编辑' : null} onAction={onEdit}>
      {defs.map(def => (
        <AeInfo key={def.key} field={`adv.${def.key}`} label={def.label}>{aeTextVal(aeShowAdv(def, s.adv[def.key]), aeShowAdv(def, s.adv[def.key]) === '关')}</AeInfo>
      ))}
      <AeWebRow ctx={ctx} a={a} />
    </AeSec>
  );
}

// props: {ctx, id} from slot accountDetail, or {ctx, route} from screen:accountEdit (route.focus scrolls to a section).
function AeInline({ ctx, id, route }) {
  const a = ctx.accounts[id ?? route.id];
  const [face, setFace] = useState(null);
  const anchor = useRef(null);
  useEffect(() => { if (a && route && route.focus) aeScrollTo(anchor.current, route.focus); }, []);
  // Deleted from this phone while still in another tab's stack: the same page the base detail shows.
  if (!a) return <RemovedAccount ctx={ctx} />;
  const s = aeCurrent(a);
  const token = aeToken(ctx, a);
  // One PUT per section; the receipt's 撤销 puts the previous values back.
  const commit = (next, changes) => ctx.updateAccount(a.id, { ...aePatch(a, next), aeSaved: next }, { text: `已保存：${aeNames(changes)}`, icon: 'checkCircle', undo: true });
  const save = (next, changes) => aePut(ctx, a, changes, next.groups, () => commit(next, changes));
  const edit = part => ctx.openSheet({ kind: 'aePart', id: a.id, part, value: s, onSave: save });
  const replaced = () => { ctx.updateAccount(a.id, { aeKeyReplaced: true, aeKeyAt: ctx.elapsed }); aeToastTest(ctx, a, '已更换 API Key'); };
  const onKey = () => ctx.openSheet({ kind: 'aeKey', id: a.id, applyNow: true, onDone: () => aeGuard(ctx, replaced, setFace) });
  const onUrl = () => ctx.openSheet({
    kind: 'aeUrl', id: a.id, value: s.baseUrl,
    onDone: url => { ctx.updateAccount(a.id, { aeSaved: { ...s, baseUrl: url } }); aeToastTest(ctx, a, url ? '已保存 Base URL' : '已改回官方地址'); },
  });
  const onReauth = () => aeOpenReauth(ctx, a, s.proxy, type => aeGuard(ctx, () => token.renew(type), setFace));
  const pickProxy = () => ctx.openSheet({ kind: 'aeProxy', id: a.id, value: s.proxy, onDone: v => v !== s.proxy && commit({ ...s, proxy: v }, [{ label: `代理 → ${v || '无代理'}` }]) });
  return (
    <Screen ctx={ctx} footer={aeFaceHud(face, setFace)}
      nav={<NavBar ctx={ctx} back title={a.name} subtitle={`${a.platform} · ${a.type}`} trailing={<GlassButton icon="more" onClick={() => aeInlineMenu(ctx, a, { onKey, onReauth, onRefresh: token.refresh })} />} />}>
      <i ref={anchor} hidden />
      {/* A credential error makes the card's primary button 更换 API Key… / 重新授权…; it opens this page's own sheets. */}
      <AccountDetailTop ctx={ctx} a={a} extraActions={{ replaceKey: onKey, reauth: onReauth }} />
      <div className="ae-inline">
        <AeInlineBasic a={a} s={s} onEdit={() => edit('basic')} />
        <AeInlineSched a={a} s={s} onEdit={() => edit('sched')} />
        <AeInlineCred ctx={ctx} a={a} s={s} token={token} onKey={onKey} onUrl={onUrl} onReauth={onReauth} />
        <AeSec title="代理" part="proxy" action="编辑" onAction={pickProxy} foot="选中即生效，回执里可撤销。">
          <AePick field="proxy" label="代理" value={<AeProxyVal name={s.proxy} />} hint={aeProxyHint(s.proxy)} onClick={pickProxy} />
        </AeSec>
        <AeInlineModels ctx={ctx} a={a} s={s} onEdit={() => edit('models')} />
        <AeInlineAdv ctx={ctx} a={a} s={s} onEdit={() => edit('adv')} />
      </div>
    </Screen>
  );
}

/* ---------- 'page' credential presentation: a dedicated credentials page (same form rows, saved on its own) ---------- */

function AeCredScreen({ ctx, route }) {
  const a = ctx.accounts[route.id];
  const oauth = !aeIsKey(a);
  const [initBase] = useState(() => (AE_SEED[a.id] || {}).baseUrl || '');
  const [d, setD] = useState({ key: null, baseUrl: initBase });
  const [face, setFace] = useState(null);
  const token = aeToken(ctx, a);
  const set = (k, v) => setD(s => ({ ...s, [k]: v }));
  const changes = [
    d.key && { key: 'key', label: 'API Key', secret: true },
    d.baseUrl !== initBase && { key: 'baseUrl', label: 'Base URL' },
  ].filter(Boolean);
  const save = () => {
    const finish = () => {
      if (d.key) { ctx.updateAccount(a.id, { aeKeyReplaced: true }); aeToastTest(ctx, a, '已更换 API Key'); } else ctx.showToast({ text: '已保存 Base URL', icon: 'checkCircle' });
      ctx.pop();
    };
    if (!d.key) return finish();
    ctx.confirm({
      title: `更换「${a.name}」的 API Key？`,
      message: `保存后站点立即改用新密钥，不能撤销；旧密钥不再保存、不能找回。如果旧密钥泄露，请到上游控制台吊销。${aeFaceLine(ctx)}`,
      actions: [{ label: '更换 API Key', role: 'destructive', onPress: () => aeGuard(ctx, finish, setFace) }, { label: '取消', role: 'cancel' }],
    });
  };
  const f = { ctx, a, d, set, ch: { key: Boolean(d.key), baseUrl: d.baseUrl !== initBase }, err: {} };
  const cred = {
    mode: 'row', left: token.left, at: token.at, replaced: a.aeKeyReplaced, proxyDirty: false, onRefresh: token.refresh,
    onReauth: () => aeOpenReauth(ctx, a, a.proxy, type => aeGuard(ctx, () => token.renew(type), setFace)),
    // This page keeps no parked draft, so the error bar only links out while nothing is pending here.
    onLogs: changes.length ? null : () => ctx.push(aeUpstreamRoute(a)),
  };
  return (
    <Screen ctx={ctx} footer={aeFaceHud(face, setFace)}
      nav={<NavBar ctx={ctx} title="凭据" subtitle={a.name}
        leading={<GlassButton icon="back" onClick={() => aeLeave(ctx, changes, ctx.pop)} />}
        trailing={oauth ? null : <AeDone label="保存" disabled={!changes.length} onClick={save} />} />}>
      <i className="ae-notabs" hidden />
      <div className="ae-body">
        <AeCredKit f={f} cred={cred} />
        <AeSec title="账号" part="who" foot={oauth ? null : '这一页单独保存；编辑页里没保存的改动不受影响。'}>
          <AeRead label="平台" value={a.platform} />
          <AeRead label="类型" value={a.type} />
        </AeSec>
      </div>
    </Screen>
  );
}

mvRegister('screen:accountEdit', 'base', AeEditBase);
mvRegister('screen:accountEdit', 'seg', AeEditSeg);
mvRegister('screen:accountEdit', 'inline', AeInline);
mvRegister('accountDetail', 'inline', AeInline);
mvRegister('screen:aeCred', 'base', AeCredScreen);
mvRegister('sheet:aeGroups', 'base', AeGroupsSheet);
mvRegister('sheet:aeExpiry', 'base', AeExpirySheet);
mvRegister('sheet:aeProxy', 'base', AeProxySheet);
mvRegister('sheet:aeModels', 'base', AeModelsSheet);
mvRegister('sheet:aeOption', 'base', AeOptionSheet);
mvRegister('sheet:aeMap', 'base', AeMapSheet);
mvRegister('sheet:aeKey', 'base', AeKeySheet);
mvRegister('sheet:aeUrl', 'base', AeUrlSheet);
mvRegister('sheet:aeReauth', 'base', AeReauthSheet);
mvRegister('sheet:aePart', 'base', AePartSheet);
