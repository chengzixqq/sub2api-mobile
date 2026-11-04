/* 新建账号向导（槽 screen:accountNew，账号页右上 + 进入）。三种布局共用一套状态、校验与文案：
   form   【已定，v-decided 默认】单页长表单。SwiftUI：从账号页 .sheet 全高弹出 NavigationStack { Form }，
          toolbar .cancellationAction“取消”；分区顺序 平台与认证方式（Picker(.menu) + 单选行）→ 凭据（随方式变化，OAuth 是三步清单）
          → 名称 → 分组（胶囊，FlowLayout）→ 调度 → 网络 → 更多（DisclosureGroup）。底部 .safeAreaInset(edge: .bottom) 放玻璃坞：
          没填齐时写“还差 …”并可点按跳到第一项（ScrollViewReader.scrollTo），标题副行的“还差 N 项”数的是同一份清单；填齐后“创建并测试”。
          测试在 .sheet（.presentationDetents([.large])，进行中 .interactiveDismissDisabled）里：进度四行（创建账号 / 停止调度 /
          测试连接 / 启用调度）→ 结果与出口 → 折叠的测试输出（DisclosureGroup）。没通过时关掉 sheet 回到表单，顶部横幅说明 #21 已创建、
          暂停调度或已被后端标为错误（见 anFailReason），“处理”给 保留 / 停用 / 删除；改了凭据坞上是“保存并重新测试”（PUT :id → 测试），
          没改是“重新测试”。结果 sheet 里的“删除账号…”是流程内处理刚建的 #21，作为最后一个次要文字按钮留在 sheet 里（仍要输入名称确认）。
   base   分步全屏：每步一页（NavigationStack push），顶部刻度步骤条，底部主按钮；平台、方式两步点选即前进
   cards  卡片式分页 sheet：在账号列表上弹出大 sheet，卡片左右翻页。SwiftUI：ScrollView(.horizontal) + LazyHStack，
          .scrollTargetBehavior(.viewAligned) + .contentMargins(.horizontal, 44) 露出相邻卡，.scrollPosition(id:) 控制当前卡；
          没完成的步骤不放进可滚动范围（只在边缘露出一把锁），完成后才追加下一张。不用 TabView(.page)：它不能露边，也不能锁页。
   ctx.v.anOauth  OAuth 授权的呈现：'list' 三步清单（默认）| 'focus' 单卡聚焦（一次只给一个动作）
   stack 项可带 step（0–4 或 platform / type / cred / setup / test）、draft（预填字段）、browser（'consent' | 'result'）、
   demo（'testFail' 测试不通过，凭据改过后重测才通过 | 'oauthExpired' 授权会话过期 | 'pauseFail' 第一次停止调度失败 |
   'noListener' 本机回调监听失败），便于截图。冒烟状态见 tools/routes/account-new.json。

   后端依据（02-backend-capability-map §1.2、§3.1，及 sub2 后端 / Web 源码）：
   · 创建：POST admin/accounts。CreateAccountRequest 没有 schedulable / status，service/admin_account.go 固定 Schedulable: true，
     账号一建好就参与调度（不分组也会被未分组的 Key 调度）。所以要两次请求：创建 → 立刻 POST :id/schedulable {false} 停止调度 →
     POST :id/test（SSE）→ 通过再 POST :id/schedulable {true}。两次请求之间有空窗；停止调度失败时红色提示、可重试，语义同“结果待核对”。
   · 提交前 POST check-mixed-channel：Anthropic 与 Antigravity 账号进同一分组时 has_risk，弹确认后带 confirm_mixed_channel_risk。
     Antigravity 打开“在 /v1/messages 中使用”（extra.mixed_scheduling）后才能选 Anthropic / Gemini 分组（GroupSelector.vue）；
     关掉时已选的 Anthropic / Gemini 分组不再适用，移出后回执可撤销。演示：新建 Antigravity 账号选「高级组」（里面有 Anthropic 账号）。
   · 分组来自 GET groups/all（只返回启用的分组，按 sort_order 排），即 DEMO.groups 里 status 为 active 的；成员和可用数读 ctx.accounts。
   · 测试模型来自 GET :id/models（默认优先 Sonnet）；首字 / 总耗时由 App 按 SSE 事件自己计时（TestEvent 没有这两个字段）。
   · 未通过：PUT :id 保存修改后重测（UpdateAccountRequest 没有 platform，平台只读；type 可改，切换前确认）；
     或保持现状（暂停调度，或被测试标成的错误）、PUT status=inactive 停用、DELETE :id 删除。
   · 代理来自 GET proxies/all?with_count=true（只返回状态正常的代理），即 DEMO.proxies 里 status 为 active 的。
   · OAuth：generate-auth-url（Setup Token 用 generate-setup-token-url）生成 PKCE 链接，会话 30 分钟有效 → 浏览器授权 → exchange-code。
     exchange-code 接收 proxy_id 并优先于会话里存的代理（openai_oauth_service.go “prefer input.ProxyID”），所以代理放在“完成授权”
     旁边，换代理不重置进度；缺代理导致的兑换失败不消耗授权码，换个代理直接重试兑换。
   · 回调：Claude（platform.claude.com/oauth/code/callback）和 Gemini Google One / Code Assist（内置 Gemini CLI client，
     codeassist.google.com/authcode）授权后页面显示授权码，回到 App 用 PasteButton 粘贴（不触发剪贴板授权弹窗）。
     OpenAI（localhost:1455）、Antigravity（localhost:8085）、Grok（127.0.0.1:56121）跳到本机回调：App 打开 Safari sheet
     （SFSafariViewController，App 一直在前台）时用 Network.framework 的 NWListener 临时监听该端口，接住 code 和 state，回一页
     “已交给 App”并关掉 Safari，然后自动兑换。监听失败（端口被占）时退回粘贴：Safari 只显示自己的错误页、页面里没有按钮，
     用户点底部“分享 → 拷贝”再回来粘贴。只有配置了自定义 client 的 AI Studio OAuth 才跳 localhost:1455，这里不涉及。 */

/* ---------- 演示数据（字段与取值对照 02 文档、后端常量与 Web 新建账号弹窗） ---------- */

const AN_NEW_ID = 21;
const AN_EMAIL = 'ops@example.com';

const AN_PLATFORMS = [
  { id: 'anthropic', name: 'Anthropic', mono: 'An', shelf: 'common', short: 'Claude' },
  { id: 'openai', name: 'OpenAI', mono: 'Op', shelf: 'common', short: 'OpenAI' },
  { id: 'gemini', name: 'Gemini', mono: 'Ge', shelf: 'common', short: 'Gemini' },
  { id: 'antigravity', name: 'Antigravity', mono: 'Ag', shelf: 'common', short: 'Antigravity' },
  { id: 'grok', name: 'Grok', mono: 'Gr', shelf: 'common', short: 'Grok' },
  { id: 'kimi', name: 'Kimi', mono: 'Ki', shelf: 'cn', short: 'Kimi', modes: ['payg', 'coding'] },
  { id: 'zhipu', name: '智谱 GLM', mono: '智', shelf: 'cn', short: 'GLM', modes: ['payg', 'coding'] },
  { id: 'deepseek', name: 'DeepSeek', mono: 'De', shelf: 'cn', short: 'DeepSeek', modes: ['payg'] },
  { id: 'minimax', name: 'MiniMax', mono: 'Mi', shelf: 'cn', short: 'MiniMax', modes: ['payg', 'coding'] },
  { id: 'opencode_go', name: 'OpenCode', mono: 'OC', shelf: 'more', short: 'OpenCode', modes: ['zen', 'go'] },
  { id: 'typesafe', name: 'TypeSafe / Jev', mono: 'TS', shelf: 'more', short: 'TypeSafe' },
  { id: 'command_code', name: 'Command Code', mono: 'CC', shelf: 'more', short: 'CommandCode', modes: ['payg'] },
  { id: 'cline', name: 'Cline', mono: 'Cl', shelf: 'more', short: 'Cline', modes: ['payg'] },
];
const AN_SHELVES = [['common', '常用'], ['cn', '国内厂商'], ['more', '更多']];
const AN_MODES = {
  payg: ['按量付费', '消耗账户余额，按 Token 计费'],
  coding: ['Coding Plan', '订阅制编程套餐，按 5 小时 / 每周窗口限流'],
  zen: ['Zen', '按量付费网关，按 Token 计费'],
  go: ['GO', '订阅制网关，按 5 小时 / 周 / 月窗口限流'],
};
const AN_API_LABEL = { oauth: 'OAuth', 'setup-token': 'Setup Token', apikey: 'API Key', upstream: '对接上游', bedrock: 'AWS Bedrock', service_account: 'Vertex' };

const AN_DEMO_KEY = {
  anthropic: 'sk-ant-api03-Qm7Rk2Lw9XcV4bNt8YpE1sH6dJ3fG0aZuK5oT-K7fQ',
  openai: 'sk-proj-4fGh8JkL2mNp6QrS0tUv3WxY7zAb1CdE5fGh-Q2rT',
  gemini: 'AIzaSyD4kL9mN2pQ7rS1tU6vW3xY8zA5bC0dE3f',
  grok: 'xai-7Hk2Lm9Np4Qr8St1Uv6Wx3Yz0Ab5Cd2EfG9hJ',
  other: 'sk-3c9a7f1e5b2d8046a1c7e9f3b5d2a8c4e61f',
};
const AN_KEY_HINT = { anthropic: 'sk-ant-api03-...', openai: 'sk-proj-...', gemini: 'AIza...', grok: 'xai-...' };
const AN_BASE = {
  anthropic: ['https://api.anthropic.com', 'Base URL 留空使用官方 Anthropic API。'],
  openai: ['https://api.openai.com', 'Base URL 留空使用官方 OpenAI API。'],
  gemini: ['https://generativelanguage.googleapis.com', 'Base URL 留空使用官方 Gemini API。'],
  grok: ['https://api.x.ai/v1', 'Base URL 留空使用官方 xAI API。'],
  typesafe: ['https://api.typesafe.ai', 'Base URL 留空使用 TypeSafe 官方地址。'],
};
const AN_ENDPOINT = {
  kimi: { payg: 'api.moonshot.cn', coding: 'api.kimi.com/coding' },
  zhipu: { payg: 'open.bigmodel.cn/api/paas/v4', coding: 'open.bigmodel.cn/api/coding/paas/v4' },
  deepseek: { payg: 'api.deepseek.com' },
  minimax: { payg: 'api.minimaxi.com', coding: 'api.minimaxi.com' },
  opencode_go: { zen: 'opencode.ai/zen/v1', go: 'opencode.ai/zen/go/v1' },
  command_code: { payg: 'api.commandcode.ai/provider/v1' },
  cline: { payg: 'api.cline.bot/api/v1' },
};
// API 协议与端点预设（credentialsBuilder.ts CnApiProtocol / CN_BASE_URL_PRESETS；Cline 只提供 Chat Completions）。
const AN_PROTO = {
  adaptive: ['自适应', '按入站协议用供应商原生端点，没有时再转换'],
  chat_completions: ['Chat Completions', '只走 /chat/completions'],
  anthropic: ['Anthropic', '只走 /v1/messages'],
  responses: ['Responses', '只走 /responses'],
};
const AN_CN_PRESETS = {
  kimi: [
    ['payg', 'chat_completions', 'Moonshot', 'https://api.moonshot.cn/v1'], ['payg', 'anthropic', 'Moonshot Anthropic', 'https://api.moonshot.cn/anthropic'],
    ['payg', 'responses', 'Moonshot Responses', 'https://api.moonshot.cn/v1'], ['coding', 'chat_completions', 'Kimi For Coding', 'https://api.kimi.com/coding/v1'],
    ['coding', 'anthropic', 'Kimi Coding Anthropic', 'https://api.kimi.com/coding'], ['coding', 'responses', 'Kimi Coding Responses', 'https://api.kimi.com/coding/v1'],
  ],
  zhipu: [
    ['payg', 'chat_completions', 'GLM PaaS', 'https://open.bigmodel.cn/api/paas/v4'], ['payg', 'anthropic', 'GLM Anthropic', 'https://open.bigmodel.cn/api/anthropic'],
    ['coding', 'chat_completions', 'GLM Coding', 'https://open.bigmodel.cn/api/coding/paas/v4'], ['coding', 'anthropic', 'GLM Coding Anthropic', 'https://open.bigmodel.cn/api/anthropic'],
  ],
  deepseek: [
    ['payg', 'chat_completions', 'DeepSeek', 'https://api.deepseek.com'], ['payg', 'anthropic', 'DeepSeek Anthropic', 'https://api.deepseek.com/anthropic'],
    ['payg', 'responses', 'DeepSeek Responses', 'https://api.deepseek.com'],
  ],
  minimax: [
    ['payg', 'chat_completions', 'MiniMax CN', 'https://api.minimaxi.com/v1'], ['payg', 'chat_completions', 'MiniMax Intl', 'https://api.minimax.io/v1'],
    ['payg', 'anthropic', 'MiniMax CN Anthropic', 'https://api.minimaxi.com/anthropic'], ['payg', 'anthropic', 'MiniMax Intl Anthropic', 'https://api.minimax.io/anthropic'],
    ['payg', 'responses', 'MiniMax CN Responses', 'https://api.minimaxi.com/v1'], ['payg', 'responses', 'MiniMax Intl Responses', 'https://api.minimax.io/v1'],
    ['coding', 'chat_completions', 'MiniMax Coding CN', 'https://api.minimaxi.com/v1'], ['coding', 'chat_completions', 'MiniMax Coding Intl', 'https://api.minimax.io/v1'],
    ['coding', 'anthropic', 'MiniMax Coding CN Anthropic', 'https://api.minimaxi.com/anthropic'], ['coding', 'anthropic', 'MiniMax Coding Intl Anthropic', 'https://api.minimax.io/anthropic'],
    ['coding', 'responses', 'MiniMax Coding CN Responses', 'https://api.minimaxi.com/v1'], ['coding', 'responses', 'MiniMax Coding Intl Responses', 'https://api.minimax.io/v1'],
  ],
  opencode_go: [['zen', 'chat_completions', 'OpenCode Zen', 'https://opencode.ai/zen/v1'], ['go', 'chat_completions', 'OpenCode Go', 'https://opencode.ai/zen/go/v1']],
  command_code: [['payg', 'chat_completions', 'Command Code', 'https://api.commandcode.ai/provider/v1']],
  cline: [['payg', 'chat_completions', 'Cline', 'https://api.cline.bot/api/v1']],
};
// GET :id/models 的演示返回；测试默认优先 Sonnet。
const AN_MODELS = {
  anthropic: ['claude-sonnet-4-5', 'claude-opus-4-1', 'claude-haiku-4-5'],
  openai: ['gpt-5', 'gpt-5-codex', 'gpt-4.1-mini'],
  gemini: ['gemini-2.5-pro', 'gemini-2.5-flash'],
  antigravity: ['claude-sonnet-4-5', 'gemini-2.5-pro', 'gemini-2.5-flash'],
  grok: ['grok-4', 'grok-code-fast-1'],
  kimi: ['kimi-k2', 'kimi-k2-turbo'],
  zhipu: ['glm-4.6', 'glm-4.5-air'],
  deepseek: ['deepseek-chat', 'deepseek-reasoner'],
  minimax: ['MiniMax-M2'],
  opencode_go: ['qwen3-coder', 'kimi-k2'],
  typesafe: ['claude-sonnet-4-5', 'claude-haiku-4-5'],
  command_code: ['claude-sonnet-4-5', 'gpt-5'],
  cline: ['claude-sonnet-4-5', 'gpt-5'],
};

// back: 'code' = 授权后页面显示授权码，粘贴；'callback' = 跳到本机回调地址 cb，App 临时监听接住。
// 地址对照 backend/internal/pkg/oauth/oauth.go、openai/oauth.go、geminicli/constants.go、antigravity/oauth.go、xai/oauth.go。
const AN_OAUTH = {
  anthropic: { host: 'claude.com', codeHost: 'platform.claude.com', client: 'Claude Code', who: 'Claude', back: 'code',
    demo: 'Kp7vR2mX9qLw4tNb8sYc1dHf6jZ3gA0e#U5oT8rLmN2qWv',
    url: 'https://claude.com/cai/oauth/authorize?code=true&client_id=9d1c250a-e61b-44d9-88ed-5944d1962f5e&response_type=code&redirect_uri=https%3A%2F%2Fplatform.claude.com%2Foauth%2Fcode%2Fcallback&scope=org%3Acreate_api_key+user%3Aprofile+user%3Ainference&code_challenge=…&state=Zr4…',
    expires: { oauth: '今天 17:41 · 到期前自动刷新', setup: `${anExpiry(12).slice(0, 10)} · 长期有效` } },
  openai: { host: 'auth.openai.com', client: 'Codex', who: 'ChatGPT', upstream: 'OpenAI', back: 'callback', cb: 'localhost:1455', needsProxy: true,
    demo: 'http://localhost:1455/auth/callback?code=ac_9Fq2Lm7XvB4nK8sR&state=s8Kd2Wq',
    url: 'https://auth.openai.com/oauth/authorize?response_type=code&client_id=app_…&redirect_uri=http%3A%2F%2Flocalhost%3A1455%2Fauth%2Fcallback&code_challenge=…&state=s8Kd2Wq', expires: `${anLater(10).slice(5)} · 到期前自动刷新` },
  gemini: { host: 'accounts.google.com', codeHost: 'codeassist.google.com', client: 'Gemini CLI', who: 'Google', back: 'code',
    demo: '4/0AVMBsJh7Qm2Lw9XcV4bNt8YpE1sH6dJ3fG0aZuK5oTq8Rk',
    url: 'https://accounts.google.com/o/oauth2/v2/auth?client_id=681255809395-…apps.googleusercontent.com&redirect_uri=https%3A%2F%2Fcodeassist.google.com%2Fauthcode&response_type=code&access_type=offline&code_challenge=…&state=g7Hn3', expires: '今天 10:41 · 到期前自动刷新' },
  antigravity: { host: 'accounts.google.com', client: 'Antigravity', who: 'Google', back: 'callback', cb: 'localhost:8085',
    demo: 'http://localhost:8085/callback?state=a2Lp9&code=4/0AVMBsJc3Rk7Wq2Lm9XvB4',
    url: 'https://accounts.google.com/o/oauth2/v2/auth?client_id=…apps.googleusercontent.com&redirect_uri=http%3A%2F%2Flocalhost%3A8085%2Fcallback&response_type=code&access_type=offline&state=a2Lp9', expires: '今天 10:41 · 到期前自动刷新' },
  grok: { host: 'auth.x.ai', client: 'Grok CLI', who: 'xAI', back: 'callback', cb: '127.0.0.1:56121',
    demo: 'http://127.0.0.1:56121/callback?code=xg_5Tm8Pq2Lw&state=k4Vb1',
    url: 'https://auth.x.ai/oauth2/authorize?response_type=code&client_id=b1a00492-073a-47ea-816f-4c329264a828&redirect_uri=http%3A%2F%2F127.0.0.1%3A56121%2Fcallback&scope=openid+profile+email+offline_access&state=k4Vb1', expires: '今天 15:41 · 到期前自动刷新' },
};
const AN_OAUTH_ERR = {
  code: ['授权码无效或已被使用', '回到浏览器重新授权，或者重新生成链接。'],
  expired: ['授权链接已过期', '链接生成超过 30 分钟，授权会话已失效，需要重新生成。'],
  proxy: ['服务器连不上 {up}', '授权码还没用掉。换一个能访问 {up} 的代理，直接重新兑换。'],
  denied: ['你在浏览器里拒绝了授权', '重新打开链接，登录后点“授权”。'],
};

// GET groups/all: active groups only, in sort_order (a stopped group is not offered). Groups carry display platform names.
const anActiveGroups = () => DEMO.groups.filter(g => g.status === 'active').sort((x, y) => x.sortOrder - y.sortOrder);
const anGroupNames = ids => ids.map(groupOf).filter(Boolean).map(g => g.name);
// GET proxies/all?with_count=true 只返回状态正常的代理（service/admin_proxy.go GetAllProxiesWithAccountCount → ListActiveWithAccountCount），
// 停用、已过期的不在列表里，所以这里不画置灰行。数据就是 DEMO.proxies（与代理页、编辑账号同一份）；到期提示用核心的 proxyExpiry，
// 与代理页同一套文案：进入提醒天数（warnDays）后写“N 天后到期 / 今天到期”，两次巡检之间已过期限但还没被标成已过期的写“已到期 · 等待处理”。
const anProxies = () => DEMO.proxies.filter(p => p.status === 'active');
const anProxyById = id => (id === null || id === undefined ? null : anProxies().find(p => p.id === id) || null);
const anProxyWhere = p => [p.region, proxyProto(p)].filter(Boolean).join(' · ');
// 与 Web 一致：快捷“1 个月 / 1 年”（accountExpiry.ts：从现在起加 N 个月，月底对齐），另可自选日期（按本机时区解释）。
// “现在”取演示时钟 DEMO_CLOCK_BASE（DEMO_TODAY 09:41），时区取设备时区。函数声明会提升，AN_OAUTH 的到期时间也用它们。
function anPad(n) { return String(n).padStart(2, '0'); }
function anStamp(t) { return `${t.getFullYear()}-${anPad(t.getMonth() + 1)}-${anPad(t.getDate())} ${anPad(t.getHours())}:${anPad(t.getMinutes())}`; }
function anExpiry(months) {
  const t = new Date(DEMO_CLOCK_BASE);
  const last = new Date(t.getFullYear(), t.getMonth() + months + 1, 0).getDate();
  t.setMonth(t.getMonth() + months, Math.min(t.getDate(), last));
  return anStamp(t);
}
// N days after the demo clock, same local time (setDate, so a DST change in between does not shift the hour).
function anLater(days) {
  const t = new Date(DEMO_CLOCK_BASE);
  t.setDate(t.getDate() + days);
  return anStamp(t);
}
const AN_NOW = anStamp(new Date(DEMO_CLOCK_BASE));
const AN_EXPIRES = [[null, '不过期'], [anExpiry(1), '1 个月后'], [anExpiry(12), '1 年后']];
function anTzLabel() {
  const off = -new Date(DEMO_CLOCK_BASE).getTimezoneOffset() / 60;
  const zone = Intl.DateTimeFormat().resolvedOptions().timeZone || '本机时区';
  return `${zone}（UTC${off >= 0 ? '+' : '−'}${Math.abs(off)}）`;
}
const AN_TZ = anTzLabel();
const AN_REGIONS = ['us-east-1', 'us-west-2', 'eu-west-1', 'ap-northeast-1'];
const AN_LOCATIONS = ['us-east5', 'europe-west1', 'asia-east1', 'global'];
const AN_VERTEX_FILE = { name: 'sub2-vertex-sa.json', project: 'sub2-prod-4821' };
const AN_BEDROCK_DEMO = { akid: 'AKIA4QZ7N2EXAMPLE8LX', secret: 'wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY', key: 'ABSKQmVkcm9ja0FQSUtleS1leGFtcGxlLTRmMmE5' };
const AN_UPSTREAM_DEMO = { url: 'https://cloudcode-pa.googleapis.com', key: 'ag-5Kq9Lm2Np7Rs4Tv8Wx1Yz6Ab3Cd0Ef' };

const AN_STEPS = [
  { key: 'platform', label: '平台' },
  { key: 'type', label: '方式' },
  { key: 'cred', label: '凭据' },
  { key: 'setup', label: '设置' },
  { key: 'test', label: '测试' },
];
const AN_RUNNING = ['creating', 'pausing', 'saving', 'testing'];

const AN_BLANK = {
  platform: null, type: null, method: 'oauth', gemType: 'google_one', project: '',
  baseUrl: '', apiKey: '', protocol: 'adaptive', endpoint: null, customUrl: '',
  bedrockAuth: 'sigv4', akid: '', secret: '', session: '', bedrockKey: '', region: 'us-east-1',
  vertexFile: null, location: 'us-east5', upstreamUrl: '', upstreamKey: '',
  oauth: { phase: 'idle', at: 0, code: '', error: null, copied: false, auto: false, listenFailed: false },
  name: '', nameAuto: true, notes: '', groups: [], mixed: false, overages: false, conc: 10, prio: 1, rate: '1', proxy: null, expires: null, autoPause: true, load: null,
  testModel: null,
  run: { phase: 'idle', n: 0, ok: true, retry: false },
};

/* ---------- 规则 ---------- */

const anPlatform = id => AN_PLATFORMS.find(p => p.id === id);

function anTypes(pid) {
  const oauth = (title, need) => ({ key: 'oauth', api: 'oauth', flow: 'oauth', icon: 'web', title, sub: '浏览器授权', need });
  const key = (title, sub, need) => ({ key: 'apikey', api: 'apikey', flow: 'key', icon: 'key', title, sub, need });
  const vertex = { key: 'vertex', api: 'service_account', flow: 'vertex', icon: 'docCheck', title: 'Vertex', sub: 'Service Account', need: '从“文件”选择 Service Account JSON' };
  switch (pid) {
    case 'anthropic': return [
      { key: 'claude_code', api: 'oauth', flow: 'oauth', icon: 'web', title: 'Claude Code', sub: 'OAuth / Setup Token', need: '在浏览器登录 Claude 授权' },
      key('Claude Console', 'API Key', '粘贴 sk-ant-api03- 开头的 Key'),
      { key: 'bedrock', api: 'bedrock', flow: 'bedrock', icon: 'shield', title: 'AWS Bedrock', sub: 'SigV4 / API Key', need: 'AWS 访问密钥和 Region' },
      vertex,
    ];
    case 'openai': return [oauth('ChatGPT OAuth', '在浏览器登录 ChatGPT 授权'), key('API Key', 'Responses API', '粘贴 sk- 开头的 Key')];
    case 'gemini': return [{ ...oauth('Google OAuth', '在浏览器登录 Google 授权'), sub: 'Google One / Code Assist' }, key('AI Studio', 'API Key', '粘贴 AIza 开头的 Key'), vertex];
    case 'antigravity': return [
      oauth('Antigravity OAuth', '在浏览器登录 Google 授权'),
      { key: 'upstream', api: 'upstream', flow: 'upstream', icon: 'server', title: '对接上游', sub: 'Base URL + API Key', need: '通过上游地址和 Key 连接' },
    ];
    case 'grok': return [oauth('Grok OAuth', '在浏览器登录 xAI 授权'), key('API Key', 'xAI API', '粘贴 xai- 开头的 Key')];
    default: {
      const p = anPlatform(pid);
      if (!p.modes) return [key('API Key', 'Anthropic 协议', '粘贴站点给的 Key')];
      return p.modes.map(m => ({ ...key(AN_MODES[m][0], 'API Key', AN_MODES[m][1]), key: m, mode: m }));
    }
  }
}

function anTypeSummary(pid) {
  const p = anPlatform(pid);
  if (p.modes) return p.modes.map(m => AN_MODES[m][0]).join(' · ');
  const short = { oauth: 'OAuth', key: 'API Key', bedrock: 'Bedrock', vertex: 'Vertex', upstream: '对接上游' };
  return [...new Set(anTypes(pid).map(t => short[t.flow]))].join(' · ');
}

function anTypeOf(d) { return d.platform && d.type ? anTypes(d.platform).find(t => t.key === d.type) || null : null; }
function anApiType(d) {
  const t = anTypeOf(d);
  if (!t) return null;
  return t.flow === 'oauth' && d.platform === 'anthropic' && d.method === 'setup-token' ? 'setup-token' : t.api;
}
const anCount = (ctx, p) => Object.values(ctx.accounts).filter(a => a.platform === p.name && a.id !== AN_NEW_ID).length;
function anSuggestName(ctx, pid) {
  const p = anPlatform(pid);
  return `${p.short}-${String(anCount(ctx, p) + 1).padStart(2, '0')}`;
}

// API 协议：有多个原生端点时默认“自适应”；只有一个（Cline）时固定。
function anPresets(pid, mode, proto) { return (AN_CN_PRESETS[pid] || []).filter(x => x[0] === mode && (!proto || x[1] === proto)); }
function anProtocols(pid, mode) {
  const native = [...new Set(anPresets(pid, mode).map(x => x[1]))];
  return native.length <= 1 ? native : ['adaptive', ...native];
}
function anDefaultProto(pid, mode) {
  if (!pid || !mode) return 'adaptive';
  const list = anProtocols(pid, mode);
  return list.length === 1 ? list[0] : 'adaptive';
}
function anEndpointOf(d) {
  const t = anTypeOf(d);
  if (!t || !t.mode || d.protocol === 'adaptive') return null;
  if (d.endpoint) return d.endpoint;
  const first = anPresets(d.platform, t.mode, d.protocol)[0];
  return first ? first[3] : null;
}
const anHost = url => (url || '').replace(/^https?:\/\//, '');

function anModels(pid) { return AN_MODELS[pid] || ['claude-sonnet-4-5']; }
function anDefaultModel(pid) { const list = anModels(pid); return list.find(m => /sonnet/.test(m)) || list[0]; }
const anModelOf = d => d.testModel || anDefaultModel(d.platform);

// Web GroupSelector：只列同平台和组合分组；Antigravity 打开混合调度后还能选 Anthropic / Gemini 分组。值是分组的平台展示名。
function anGroupPlatforms(d, mixed = d.mixed) {
  if (!d.platform) return [];
  const own = anPlatform(d.platform).name;
  if (d.platform === 'antigravity' && mixed) return [own, 'Anthropic', 'Gemini', 'composite'];
  return [own, 'composite'];
}
// check-mixed-channel：Anthropic 与 Antigravity 账号进同一分组（service/admin_account.go checkMixedChannelRisk，跳过本账号）。
// Returns the other channel already in group g, or null.
function anGroupClash(ctx, d, g) {
  const cur = { anthropic: 'Anthropic', antigravity: 'Antigravity' }[d.platform];
  if (!cur) return null;
  const other = groupMembers(ctx.accounts, g.id).find(a => a.id !== AN_NEW_ID && ['Anthropic', 'Antigravity'].includes(a.platform) && a.platform !== cur);
  return other ? other.platform : null;
}
function anMixedRisk(ctx, d) {
  const cur = { anthropic: 'Anthropic', antigravity: 'Antigravity' }[d.platform];
  for (const g of d.groups.map(groupOf).filter(Boolean)) {
    const other = anGroupClash(ctx, d, g);
    if (other) return { group: g.name, cur, other };
  }
  return null;
}

function anMask(v) {
  const s = v.trim();
  if (s.length <= 8) return '•'.repeat(s.length);
  const pre = (s.match(/^(sk-ant-api03-|sk-proj-|sk-|AIza|xai-|AKIA|ag-|ABSK)/) || [''])[0];
  return `${pre}••••••••${s.slice(-4)}`;
}

function anCredOk(d) {
  const t = anTypeOf(d);
  if (!t) return false;
  switch (t.flow) {
    case 'oauth': return d.oauth.phase === 'done';
    case 'key': return d.apiKey.trim().length > 0 && !(t.mode && d.protocol !== 'adaptive' && d.endpoint === 'custom' && !d.customUrl.trim());
    case 'bedrock': return d.bedrockAuth === 'sigv4' ? Boolean(d.akid.trim() && d.secret.trim()) : Boolean(d.bedrockKey.trim());
    case 'vertex': return Boolean(d.vertexFile);
    case 'upstream': return Boolean(d.upstreamUrl.trim() && d.upstreamKey.trim());
    default: return false;
  }
}
const anSetupOk = d => d.name.trim().length > 0 && d.conc >= 1 && d.rate !== '' && !Number.isNaN(Number(d.rate)) && Number(d.rate) >= 0;
const anStepOk = (d, i) => [Boolean(d.platform), Boolean(anTypeOf(d)), anCredOk(d), anSetupOk(d), true][i];
function anReach(d) {
  let i = 0;
  while (i < 4 && anStepOk(d, i)) i += 1;
  return i;
}
function anCredLabel(d) {
  const t = anTypeOf(d);
  if (!t) return '凭据';
  if (t.flow === 'key' && d.apiKey.trim()) return '自定义端点';
  return { oauth: '授权', key: 'API Key', bedrock: 'AWS 凭据', vertex: 'JSON 文件', upstream: '上游地址和 Key' }[t.flow];
}
// [label, section] pairs still missing, in form order; the dock names them and jumps to the first, and the title's “还差 N 项”
// counts the same list. Credentials are listed even before a platform is picked (their section is there, waiting for one).
function anMissing(d) {
  const out = [];
  if (!d.platform) out.push(['平台', 'platform']);
  else if (!anTypeOf(d)) out.push([anPlatform(d.platform).modes ? '账号类型' : '认证方式', 'platform']);
  if (!anCredOk(d)) out.push([anCredLabel(d), anTypeOf(d) && anTypeOf(d).flow === 'oauth' && ['anthropic', 'gemini'].includes(d.platform) ? 'oauth' : 'cred']);
  if (!d.name.trim()) out.push(['名称', 'name']);
  if (d.rate === '' || Number.isNaN(Number(d.rate))) out.push(['计费倍率', 'sched']);
  return out;
}
function anStepTitle(i, d) {
  const t = anTypeOf(d);
  const cn = d.platform && anPlatform(d.platform).modes;
  return ['选择平台', cn ? '账号类型' : '认证方式', t && t.flow === 'oauth' ? '授权' : '凭据', '名称与调度', d.run.retry ? '保存并重新测试' : '创建并测试'][i];
}
function anLead(i, d) {
  const p = d.platform && anPlatform(d.platform);
  const t = anTypeOf(d);
  if (i === 0) return d.run.retry ? `账号 #${AN_NEW_ID} 已创建，平台不能更换。` : '认证方式和需要的凭据随平台变化。';
  if (i === 1) return p.modes ? '凭据都是 API Key，按账号类型限流和计费。' : `${p.name} 有 ${anTypes(p.id).length} 种接入方式。`;
  if (i === 2) {
    if (t.flow === 'oauth') return AN_OAUTH[d.platform].back === 'code' ? `在浏览器里登录 ${AN_OAUTH[d.platform].who} 并授权，再把授权码粘贴回来。` : `在浏览器里登录 ${AN_OAUTH[d.platform].who} 并授权，授权完自动回到这里。`;
    if (t.flow === 'vertex') return '从“文件”选择 Service Account JSON。';
    if (t.flow === 'bedrock') return '填写 AWS 访问密钥和 Region。';
    if (t.flow === 'upstream') return '填写上游地址和 Key。';
    return `粘贴${/^[A-Za-z]/.test(p.name) ? ' ' : ''}${p.name} 的 API Key，剪贴板里有就点“粘贴”。`;
  }
  if (i === 3) return '分组决定账号服务哪些用户，并发和优先级影响调度。';
  return {
    idle: d.run.retry ? '核对修改，点“保存并重新测试”。' : '核对一遍，点“创建并测试”。',
    creating: '正在创建账号…', pausing: '账号已创建，正在停止调度…', pauseFailed: '停止调度没有确认，先处理它。', saving: '正在保存修改…',
    testing: '测试通过前不参与调度。', passed: '账号已创建并参与调度。', failed: '测试没通过，选一种处理方式。',
  }[d.run.phase];
}

function anOauthStage(o) {
  if (o.phase === 'failed') return { code: 2, denied: 1, expired: 0, proxy: 2 }[o.error];
  return { idle: 0, generating: 0, link: 1, code: 2, exchanging: 2 }[o.phase] || 0;
}
function anCodeRecognized(code) { return /[?&]code=/.test(code) && /[?&]state=/.test(code); }

// What the server holds for #21: credential fields (a retest only passes in the testFail demo once these change) and the
// whole draft (decides between 重新测试 and 保存并重新测试).
const AN_CRED_KEYS = ['type', 'method', 'gemType', 'project', 'baseUrl', 'apiKey', 'protocol', 'endpoint', 'customUrl', 'bedrockAuth', 'akid', 'secret',
  'session', 'bedrockKey', 'region', 'vertexFile', 'location', 'upstreamUrl', 'upstreamKey'];
const AN_SETUP_KEYS = ['name', 'notes', 'groups', 'mixed', 'overages', 'conc', 'prio', 'rate', 'proxy', 'expires', 'autoPause', 'load'];
const anPickSig = (d, keys) => JSON.stringify(keys.map(k => d[k]));
const anCredSig = d => `${anPickSig(d, AN_CRED_KEYS)}|${d.oauth.at}|${d.oauth.code}`;
const anDraftSig = d => `${anCredSig(d)}|${anPickSig(d, AN_SETUP_KEYS)}`;
// Anything typed into the credential area, so switching platform asks before throwing it away.
const anCredTouched = d => Boolean(d.oauth.phase !== 'idle' || [d.apiKey, d.akid, d.secret, d.bedrockKey, d.upstreamUrl, d.upstreamKey, d.project].some(v => v && v.trim()) || d.vertexFile);
// A key pasted again after a failed test is a different (fixed) one in the demo.
const anFreshKey = v => `${v.slice(0, -4)}R3vZ`;

function anWillPass(d, demo, failedSig) {
  if (demo === 'testFail' && (failedSig === null || failedSig === anCredSig(d))) return false;
  const t = anTypeOf(d);
  if (t.flow === 'key') return d.apiKey.trim().length >= 20;
  if (t.flow === 'upstream') return d.upstreamKey.trim().length >= 20;
  if (t.flow === 'bedrock') return d.bedrockAuth === 'sigv4' ? /^AKIA/.test(d.akid.trim()) && d.secret.trim().length >= 20 : d.bedrockKey.trim().length >= 20;
  return true;
}
/* Why the demo test fails, and whether the backend marks the account 错误. The test service calls SetError (status = error,
   schedulable = false, error_message; repository/account_repo.go SetError) only on these paths (service/account_test_service*.go):
   · Claude OAuth / Setup Token and Anthropic Vertex answering 403 (testClaudeAccountConnection, testClaudeVertexServiceAccountConnection);
   · OpenAI-protocol paths answering 401: OpenAI, the CN providers and OpenCode / Command Code / Cline (Chat Completions / Responses),
     their Anthropic-protocol probe and TypeSafe also on 403.
   Anthropic API Key (401), Bedrock, every Gemini path, Antigravity, Grok and an OpenAI OAuth 403 fail without touching the status:
   #21 stays as it was (paused). The error is kept until a passing test (RecoverAccountAfterSuccessfulTest) or recover-state clears it;
   PUT :id does not clear it. */
function anFailReason(d) {
  const t = anTypeOf(d);
  const pid = d.platform;
  const openaiLike = ['openai', 'kimi', 'zhipu', 'deepseek', 'minimax', 'opencode_go', 'command_code', 'cline', 'typesafe'].includes(pid);
  let r;
  if (t.flow === 'oauth') r = { code: 403, msg: 'permission_error', human: '授权的账号没有可用额度或权限', error: pid === 'anthropic' };
  else if (t.flow === 'vertex') r = { code: 403, msg: 'PERMISSION_DENIED', human: 'Service Account 没有 Vertex AI 权限', error: pid === 'anthropic' };
  else if (t.flow === 'bedrock') r = { code: 403, msg: 'UnrecognizedClientException', human: 'AWS 凭据无效或没有 Bedrock 权限', error: false };
  else if (t.flow === 'upstream') r = { code: 401, msg: 'Invalid API key', human: '上游 API Key 无效或已撤销', error: false };
  else if (pid === 'gemini') r = { code: 400, msg: 'API key not valid', human: 'API Key 无效或已撤销', error: false };
  else r = { code: 401, msg: { anthropic: 'invalid x-api-key', openai: 'Incorrect API key provided' }[pid] || 'Invalid API key', human: 'API Key 无效或已撤销', error: openaiLike };
  return { ...r, raw: `上游返回 ${r.code} · ${r.msg}`, errorText: `${r.code} ${r.human}（${r.msg}）` };
}
// Where #21 is left after a failed test: 错误 when this failure (or an earlier one, still uncleared) set it, otherwise paused.
const anHeldAfter = (fail, prev) => (fail.error || prev === 'error' ? 'error' : 'paused');
const AN_HELD = { error: '错误（已停止调度）', paused: '暂停调度' };
function anTestLines(d, ok) {
  const head = [`开始测试账号：${d.name.trim()}`, `账号类型：${AN_API_LABEL[anApiType(d)]}`, `使用模型：${anModelOf(d)}`, '连接 API 中...'];
  if (ok) return [...head, '已连接到 API', '发送测试消息："hi"', '响应：Hi! How can I help you today?', '测试完成！'];
  return [...head, `错误：${anFailReason(d).raw}`];
}
function anCredSummary(d) {
  const t = anTypeOf(d);
  if (!t) return '—';
  switch (t.flow) {
    case 'oauth': return d.oauth.phase === 'done' ? `已授权 · ${AN_EMAIL}` : '未授权';
    case 'key': return d.apiKey ? anMask(d.apiKey) : '—';
    case 'bedrock': return d.bedrockAuth === 'sigv4' ? (d.akid ? `${anMask(d.akid)} · ${d.region}` : '—') : (d.bedrockKey ? anMask(d.bedrockKey) : '—');
    case 'vertex': return d.vertexFile ? `${d.vertexFile.name} · ${d.location}` : '—';
    default: return d.upstreamUrl ? anHost(d.upstreamUrl) : '—';
  }
}

function anInit(ctx, draft = {}) {
  const d = { ...AN_BLANK, ...draft, oauth: { ...AN_BLANK.oauth, ...(draft.oauth || {}) }, run: { ...AN_BLANK.run, ...(draft.run || {}) } };
  if (d.platform && !draft.name) d.name = anSuggestName(ctx, d.platform);
  if (!draft.protocol) { const t = anTypeOf(d); d.protocol = anDefaultProto(d.platform, t && t.mode); }
  return d;
}

/* ---------- 状态 ---------- */

function useAnWizard(ctx, route) {
  const demo = route.demo || null;
  const first = typeof route.step === 'string' ? AN_STEPS.findIndex(s => s.key === route.step) : route.step || 0;
  const [d, setD] = useState(() => anInit(ctx, route.draft));
  const [step, setStep] = useState(Math.max(0, first));
  const [dir, setDir] = useState(1);
  const [picker, setPicker] = useState(null);
  const [browser, setBrowser] = useState(route.browser || null);
  // What account #21 holds on the server (set once it is created / saved); the cancel dialog acts on this, not on unsaved edits.
  const saved = useRef(d.run.phase !== 'idle' || d.run.retry ? d : null);
  const pauseTries = useRef(0);
  // Credential signature of the last failed test (testFail demo: a retest passes only after the credentials change).
  const failedSig = useRef(d.run.phase === 'failed' || d.run.retry ? anCredSig(d) : null);
  // Groups the admin already accepted the mixed-channel risk for (Web keeps the same flag for the rest of the dialog).
  const mixedOk = useRef(null);
  const set = patch => setD(cur => ({ ...cur, ...(typeof patch === 'function' ? patch(cur) : patch) }));
  const setO = patch => setD(cur => ({ ...cur, oauth: { ...cur.oauth, ...patch } }));
  const setRun = patch => setD(cur => ({ ...cur, run: { ...cur.run, ...patch } }));
  const go = i => { setDir(i >= step ? 1 : -1); setStep(i); };
  const name = d.name.trim();
  const conf = d.platform ? AN_OAUTH[d.platform] : null;

  // Writes account #21 as the server holds it. The schedule switch is on only while it is 'normal' (stopped right after
  // creation, re-enabled after a passing test); 停用 keeps it off. mixed = extra.mixed_scheduling (Antigravity).
  // 'error' = the test service's SetError (status error, schedulable false, error_message); the text goes where list rows and the
  // detail's status card read it. Every failure that sets it is a 401 / 403 (anFailReason), so the core's isCredentialError holds
  // for #21: its detail leads with 更换 API Key… / 重新授权…, and the core test sheet keeps failing until the key is replaced.
  const commit = (state, src = d, fail = null) => {
    const p = anPlatform(src.platform);
    const proxy = anProxyById(src.proxy);
    const ag = src.platform === 'antigravity';
    ctx.updateAccount(AN_NEW_ID, {
      id: AN_NEW_ID, name: src.name.trim(), notes: src.notes.trim() || null, platform: p.name, type: AN_API_LABEL[anApiType(src)], state, schedulable: state === 'normal',
      error: state === 'error' ? (fail || anFailReason(src)).errorText : null, errorAgo: state === 'error' ? '刚刚' : null,
      groups: anGroupNames(src.groups), mixed: ag && src.mixed, overages: ag && src.overages,
      conc: [0, src.conc], priority: src.prio, rate: Number(src.rate), load: src.load, proxy: proxy ? proxy.name : null,
      expires: src.expires, autoPause: src.expires ? src.autoPause : null,
      todayCost: 0, todayAccountCost: 0, todayStd: 0, todayReq: 0, todayTokens: 0, errors24h: 0,
    });
  };
  const created0 = d.run.retry || !['idle', 'creating'].includes(d.run.phase);
  // Unsaved edits to #21 (after a failed test): 保存并重新测试 = PUT :id then test; without edits it is just 重新测试.
  const dirty = created0 && Boolean(saved.current) && anDraftSig(d) !== anDraftSig(saved.current);

  // create (live at once) → stop scheduling → SSE test lines → passed (enable scheduling) / failed (paused, or 错误 when the backend
  // marked it). A retry saves the edits (PUT :id) instead; the account is already off and PUT keeps its status.
  useEffect(() => {
    const r = d.run;
    const after = (ms, fn) => { const t = setTimeout(fn, ms); return () => clearTimeout(t); };
    if (r.phase === 'creating') return after(800, () => { saved.current = d; commit('normal'); setRun({ phase: 'pausing' }); });
    if (r.phase === 'saving') return after(700, () => { saved.current = d; commit(r.held || 'paused', d, r.fail); setRun({ phase: 'testing', n: 1 }); });
    if (r.phase === 'pausing') {
      return after(650, () => {
        if (demo === 'pauseFail' && pauseTries.current === 0) { pauseTries.current += 1; setRun({ phase: 'pauseFailed' }); return; }
        commit('paused');
        setRun({ phase: 'testing', n: 1 });
      });
    }
    if (r.phase !== 'testing') return undefined;
    const total = anTestLines(d, r.ok).length;
    if (r.n < total) return after(480, () => setRun({ n: r.n + 1 }));
    return after(420, () => {
      if (r.ok) {
        // RecoverAccountAfterSuccessfulTest clears a 错误 left by an earlier failure, then the app turns scheduling back on.
        commit('normal');
        setRun({ phase: 'passed', cleared: r.held === 'error', held: null, fail: null });
        return;
      }
      const fail = anFailReason(d);
      const held = anHeldAfter(fail, r.held);
      commit(held, d, fail);
      setRun({ phase: 'failed', held, fail });
      failedSig.current = anCredSig(d);
    });
  }, [d.run.phase, d.run.n]);

  const remain = d.oauth.phase === 'idle' || d.oauth.phase === 'generating' ? null : Math.max(0, 1800 - (ctx.elapsed - d.oauth.at));
  const resetOauth = { ...AN_BLANK.oauth };

  // exchange-code with an explicit code / proxy so callers right after setProxy or an auto callback use fresh values.
  const exchange = (codeArg, proxyArg, auto) => {
    const code = (codeArg === undefined ? d.oauth.code : codeArg).trim();
    const proxyId = proxyArg === undefined ? d.proxy : proxyArg;
    const good = code === conf.demo || anCodeRecognized(code) || (code.length >= 24 && !/\s/.test(code));
    let result = { phase: 'done', error: null };
    if (demo === 'oauthExpired' || remain === 0) result = { phase: 'failed', error: 'expired' };
    else if (conf.needsProxy && !proxyId) result = { phase: 'failed', error: 'proxy' };
    else if (!good) result = { phase: 'failed', error: 'code' };
    setO({ phase: 'exchanging', code, error: null, ...(auto ? { auto: true } : {}) });
    setTimeout(() => setO(result), 900);
  };
  const oauth = {
    generate: () => {
      setO({ phase: 'generating', error: null, code: '', auto: false, listenFailed: false });
      const at = ctx.elapsed;
      setTimeout(() => setO({ phase: 'link', at, code: '', copied: false }), 650);
    },
    open: () => setBrowser('consent'),
    authorize: () => setBrowser(conf.back === 'callback' && demo !== 'noListener' ? 'caught' : 'result'),
    deny: () => { setBrowser(null); setO({ phase: 'failed', error: 'denied' }); },
    caught: () => { setBrowser(null); exchange(conf.demo, undefined, true); },
    closeBrowser: (authorized, copied) => {
      setBrowser(null);
      if (authorized) setO({ phase: 'code', copied, error: null, listenFailed: conf.back === 'callback' });
    },
    paste: () => setO({ code: conf.demo, error: null, phase: d.oauth.phase === 'failed' ? 'code' : d.oauth.phase }),
    setCode: v => setO({ code: v }),
    exchange,
    retryWithProxy: () => setPicker('proxyRetry'),
    reset: () => setO(resetOauth),
  };

  // Receipts that leave this page carry one follow-up (core Toast action): open #21's detail.
  const openNew = { label: '查看', onPress: () => ctx.push({ kind: 'account', id: AN_NEW_ID }) };
  const run = {
    // A retest without edits skips PUT :id. confirm = confirm_mixed_channel_risk already accepted for these groups.
    start: () => {
      const retry = d.run.retry || d.run.phase === 'failed';
      const ok = anWillPass(d, demo, failedSig.current);
      if (retry && !dirty) { setRun({ phase: 'testing', n: 1, ok, retry: true, saved: false }); return; }
      setRun({ phase: retry ? 'saving' : 'creating', n: 0, ok, retry, saved: retry });
    },
    repause: () => setRun({ phase: 'pausing' }),
    reset: () => setRun({ phase: 'idle', n: 0, retry: true }),
    saveInactive: (src = d) => {
      commit('inactive', src);
      ctx.pop();
      ctx.showToast({ text: `已保存「${src.name.trim()}」为停用 · 不参与调度`, icon: 'minus', tone: 'neutral', action: openNew });
    },
    // Leave #21 as the failed test left it: 错误 (SetError) or paused.
    keep: (src = d) => {
      const held = d.run.held || 'paused';
      commit(held, src, d.run.fail);
      ctx.pop();
      ctx.showToast(held === 'error'
        ? { text: `已保留「${src.name.trim()}」· 错误（已停止调度）`, icon: 'octagon', tone: 'critical', action: openNew }
        : { text: `已保留「${src.name.trim()}」· 暂停调度`, icon: 'pauseFill', tone: 'neutral', action: openNew });
    },
    remove: () => confirmDelete(ctx, '账号', (saved.current || d).name.trim(), ctx.pop, { remove: () => ctx.removeAccount(AN_NEW_ID) }),
    view: () => { ctx.pop(); ctx.push({ kind: 'account', id: AN_NEW_ID }); },
    done: () => { ctx.pop(); ctx.showToast({ text: `已创建「${name}」· 参与调度`, action: openNew }); },
    // The test keeps running in an app-level task; the result arrives as a notice (SwiftUI: a Task owned by the store).
    background: () => {
      const src = d;
      const ok = d.run.ok;
      const fail = ok ? null : anFailReason(src);
      const held = ok ? 'normal' : anHeldAfter(fail, d.run.held);
      ctx.pop();
      ctx.showToast({ text: `「${name}」在后台继续测试，完成后通知你`, icon: 'hourglass', tone: 'neutral' });
      setTimeout(() => {
        commit(held, src, fail);
        ctx.showToast(ok ? { text: `「${src.name.trim()}」测试通过 · 已启用调度`, action: openNew }
          : { text: `「${src.name.trim()}」测试未通过 · ${held === 'error' ? '已标为错误（已停止调度）' : '仍暂停调度'}`, icon: 'octagon', tone: 'critical', action: { ...openNew, label: '处理' } });
      }, 2600);
    },
  };

  const started = d.run.phase !== 'idle';
  const running = AN_RUNNING.includes(d.run.phase);
  // Account #21 exists on the server from here on: platform is fixed, a type change must be confirmed.
  const created = created0;
  // #21 exists but did not pass: keep it as it is (paused or 错误), save it as 停用, or delete it (cancel and the form's banner both ask this).
  const resolve = () => {
    const s = saved.current || d;
    const sName = s.name.trim();
    const isError = d.run.held === 'error';
    ctx.confirm({
      title: `账号「${sName}」已创建，怎么处理？`,
      message: `测试没通过，${isError ? `后端已把账号 #${AN_NEW_ID} 标为错误并停止调度` : `账号 #${AN_NEW_ID} 现在暂停调度`}，不会接收请求。${dirty ? `这里的修改还没保存到 #${AN_NEW_ID}。` : ''}`,
      actions: [
        { label: '保存为停用', role: 'default', onPress: () => run.saveInactive(s) },
        { label: isError ? '保留（错误状态）' : '保留，暂停调度', role: 'default', onPress: () => run.keep(s) },
        { label: '删除账号…', role: 'destructive', onPress: run.remove },
        { label: '继续修改', role: 'cancel' },
      ],
    });
  };
  const cancel = () => {
    const r = d.run;
    if (!d.platform) { ctx.pop(); return; }
    if (running) { run.background(); return; }
    if (r.phase === 'passed') { run.done(); return; }
    const s = saved.current || d;
    const sName = s.name.trim();
    if (r.phase === 'pauseFailed') {
      ctx.confirm({
        title: `账号「${sName}」可能还在参与调度`,
        message: `停止调度没有确认，账号 #${AN_NEW_ID} 可能正在用未验证的凭据接收请求。`,
        actions: [
          { label: '重试停止调度', role: 'default', onPress: run.repause },
          { label: '删除账号…', role: 'destructive', onPress: run.remove },
          { label: '继续处理', role: 'cancel' },
        ],
      });
      return;
    }
    if (r.phase === 'failed' || r.retry) { resolve(); return; }
    ctx.confirm({
      title: '放弃新建账号？',
      message: d.oauth.phase === 'done' ? '授权结果和已填写的内容都不会保存。' : '已填写的内容不会保存。',
      actions: [{ label: '放弃', role: 'destructive', onPress: ctx.pop }, { label: '继续填写', role: 'cancel' }],
    });
  };

  /* Mixed channel (Web CreateAccountModal ensureAntigravityMixedChannelConfirmed): for Anthropic / Antigravity with groups, POST
     check-mixed-channel {platform, group_ids, account_id?} first; has_risk + details {group_name, current_platform, other_platform}
     → this dialog (Web zh: mixedChannelWarning) → the POST / PUT carries confirm_mixed_channel_risk: true. If the POST still answers
     409 {error: 'mixed_channel_warning'} (an account joined the group meanwhile; that body has only an English message), the App
     asks check-mixed-channel again for the details, shows the same dialog and resends with the flag. Accepted once, the same
     groups are not asked again in this flow (Web keeps antigravityMixedChannelConfirmed). */
  const submit = then => {
    const go2 = () => { run.start(); if (then) then(); };
    const risk = anMixedRisk(ctx, d);
    const sig = JSON.stringify([...d.groups].sort());
    if (!risk || mixedOk.current === sig) { go2(); return; }
    ctx.confirm({
      title: '混合渠道警告',
      message: `分组「${risk.group}」中同时包含 ${risk.cur} 和 ${risk.other} 账号。混合使用不同渠道可能导致 thinking block 签名验证问题，会自动回退到非 thinking 模式。确定要继续吗？`,
      actions: [
        { label: d.run.retry || d.run.phase === 'failed' ? '继续保存' : '继续创建', role: 'destructive', onPress: () => { mixedOk.current = sig; go2(); } },
        { label: '返回修改分组', role: 'cancel', onPress: then ? () => then('groups') : undefined },
      ],
    });
  };

  // Switching away from a finished authorization discards it; ask first.
  const guardAuth = (title, apply) => {
    if (d.oauth.phase !== 'done') { apply(); return; }
    ctx.confirm({ title, message: '切换会丢弃当前授权，需要重新在浏览器里授权。', actions: [{ label: '切换', role: 'destructive', onPress: apply }, { label: '取消', role: 'cancel' }] });
  };

  return {
    d, set, step, dir, go, demo, picker, browser, remain, oauth, run, started, running, created, dirty, cancel, resolve, submit,
    openPicker: setPicker,
    closePicker: () => setPicker(null),
    // Switching platform clears everything that depends on it; ask first when credentials were already entered.
    pickPlatform: (pid, then) => {
      if (created || pid === d.platform) { if (then && pid === d.platform) then(); return; }
      const apply = () => {
        set(cur => {
          const types = anTypes(pid);
          const auto = cur.nameAuto || !cur.name;
          return {
            ...AN_BLANK, platform: pid, type: types.length === 1 ? types[0].key : null,
            protocol: anDefaultProto(pid, types.length === 1 ? types[0].mode : null),
            name: auto ? anSuggestName(ctx, pid) : cur.name, nameAuto: auto, notes: cur.notes,
            conc: cur.conc, prio: cur.prio, rate: cur.rate, proxy: cur.proxy, expires: cur.expires, autoPause: cur.autoPause, load: cur.load,
          };
        });
        if (then) then();
      };
      if (!d.platform || !anCredTouched(d)) { apply(); return; }
      ctx.confirm({
        title: `换成 ${anPlatform(pid).name}？`,
        message: `已填写的${d.oauth.phase === 'done' ? '授权' : '凭据'}${d.groups.length ? '和选好的分组' : ''}会清空，名称、调度和代理保留。`,
        actions: [{ label: '更换平台', role: 'destructive', onPress: apply }, { label: '取消', role: 'cancel' }],
      });
    },
    // The type can be changed on an existing account (PUT :id accepts type), but its credentials must be redone.
    pickType: (key, then) => {
      const t = anTypes(d.platform).find(x => x.key === key);
      const apply = () => {
        set(cur => (cur.type === key ? {} : { type: key, apiKey: '', oauth: resetOauth, protocol: anDefaultProto(cur.platform, t.mode), endpoint: null, customUrl: '' }));
        if (then) then();
      };
      const what = anPlatform(d.platform).modes ? '账号类型' : '认证方式';
      if (d.type && d.type !== key && (created || anCredTouched(d))) {
        ctx.confirm({
          title: `改成「${t.title}」？`,
          message: created
            ? `账号 #${AN_NEW_ID} 已创建。换${what}后要重新${t.flow === 'oauth' ? '授权' : '填写凭据'}，保存时替换原来的凭据。`
            : `换${what}会清空已填写的${d.oauth.phase === 'done' ? '授权' : '凭据'}。`,
          actions: [{ label: '更换', role: 'destructive', onPress: apply }, { label: '取消', role: 'cancel' }],
        });
        return;
      }
      apply();
    },
    setMethod: m => { if (m !== d.method) guardAuth(`切换到 ${m === 'setup-token' ? 'Setup Token' : 'OAuth'}？`, () => set({ method: m, oauth: resetOauth })); },
    setGemType: v => { if (v !== d.gemType) guardAuth(`切换到 ${v === 'code_assist' ? 'Code Assist' : 'Google One'}？`, () => set({ gemType: v, oauth: resetOauth })); },
    setProtocol: v => set({ protocol: v, endpoint: null, customUrl: '' }),
    // Turning mixed scheduling off drops the Anthropic / Gemini groups it allowed; say so, and let 撤销 put both back.
    setMixed: on => {
      const prev = d.groups;
      const allowed = anGroupPlatforms(d, on);
      const keep = on ? prev : prev.filter(id => allowed.includes((groupOf(id) || {}).platform));
      set({ mixed: on, groups: keep });
      const gone = prev.length - keep.length;
      if (gone > 0) {
        ctx.showToast({
          text: `已移除 ${gone} 个不再适用的分组`,
          icon: 'minus', tone: 'neutral', undo: () => set({ mixed: true, groups: prev }),
        });
      }
    },
    pickModel: m => setD(cur => ({ ...cur, testModel: m, run: { ...cur.run, phase: 'testing', n: 1 } })),
    // exchange-code takes proxy_id over the session's proxy, so a new proxy keeps the progress; a proxy failure becomes retryable.
    setProxy: id => set(cur => (cur.oauth.phase === 'failed' && cur.oauth.error === 'proxy' && id !== null
      ? { proxy: id, oauth: { ...cur.oauth, phase: 'code', error: null } } : { proxy: id })),
  };
}

/* ---------- 小部件 ---------- */

function AnGlyph({ name, size = 18, weight = 2 }) {
  const p = { fill: 'none', stroke: 'currentColor', strokeWidth: weight, strokeLinecap: 'round', strokeLinejoin: 'round' };
  const shapes = {
    eye: <g {...p}><path d="M2.5 12S6 5.5 12 5.5 21.5 12 21.5 12 18 18.5 12 18.5 2.5 12 2.5 12z" /><circle cx="12" cy="12" r="3" /></g>,
    eyeOff: <g {...p}><path d="M2.5 12S6 5.5 12 5.5 21.5 12 21.5 12 18 18.5 12 18.5 2.5 12 2.5 12z" /><circle cx="12" cy="12" r="3" /><path d="M4 4l16 16" /></g>,
    paste: <g {...p}><rect x="8" y="3" width="8" height="4" rx="1.5" /><path d="M8 5H6.5A1.5 1.5 0 0 0 5 6.5v13A1.5 1.5 0 0 0 6.5 21h11a1.5 1.5 0 0 0 1.5-1.5v-13A1.5 1.5 0 0 0 17.5 5H16" /></g>,
    copy: <g {...p}><rect x="9" y="9" width="11" height="11" rx="2" /><path d="M5 15V6a2 2 0 0 1 2-2h8" /></g>,
    lock: <g {...p}><rect x="5" y="11" width="14" height="10" rx="2" /><path d="M8 11V8a4 4 0 0 1 8 0v3" /></g>,
    compass: <g {...p}><circle cx="12" cy="12" r="9" /><path d="M15.5 8.5l-2 5-5 2 2-5z" /></g>,
    file: <g {...p}><path d="M14 3H7a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h10a2 2 0 0 0 2-2V8z" /><path d="M14 3v5h5" /></g>,
    link: <g {...p}><path d="M10 14a4 4 0 0 0 5.7 0l3-3a4 4 0 0 0-5.7-5.7l-1.2 1.2" /><path d="M14 10a4 4 0 0 0-5.7 0l-3 3a4 4 0 0 0 5.7 5.7l1.2-1.2" /></g>,
    dash: <g {...p}><path d="M5 12h14" /></g>,
    share: <g {...p}><path d="M12 3v12" /><path d="M8 7l4-4 4 4" /><path d="M5 12v7a2 2 0 0 0 2 2h10a2 2 0 0 0 2-2v-7" /></g>,
    inbox: <g {...p}><path d="M4 13l2.5-7h11L20 13" /><path d="M4 13v6h16v-6h-5a3 3 0 0 1-6 0z" /></g>,
  };
  return <svg width={size} height={size} viewBox="0 0 24 24" aria-hidden="true">{shapes[name]}</svg>;
}

function AnSec({ id, title, meta, foot, children, className }) {
  return (
    <section className={cx('an-sec', className)} data-sec={id}>
      {title && <div className="sec-head"><span className="sec-title">{title}</span><span className="sec-line" />{meta && <span className="sec-meta">{meta}</span>}</div>}
      <div className="sec an-box">{children}</div>
      {foot && <div className="an-foot">{foot}</div>}
    </section>
  );
}

function AnPasteBtn({ onClick, label = '粘贴' }) {
  return <button type="button" className="an-paste" onClick={onClick}><AnGlyph name="paste" size={15} weight={2.2} />{label}</button>;
}

function AnInput({ label, value, onChange, placeholder, mono, demo, inputMode }) {
  return (
    <label className="an-field">
      <span className="an-field-label">{label}</span>
      <span className="an-field-line">
        <input className={cx('an-input', mono && 'mono')} value={value} placeholder={placeholder} inputMode={inputMode}
          spellCheck={false} autoCapitalize="off" autoComplete="off" onChange={e => onChange(e.target.value)} />
        {demo && !value && <AnPasteBtn onClick={e => { e.preventDefault(); onChange(demo); }} />}
      </span>
    </label>
  );
}

// SecureField: masked as prefix••••last4 when idle, eye to reveal, PasteButton when empty; trims on blur.
function AnKey({ label = 'API Key', value, onChange, placeholder, demo }) {
  const [shown, setShown] = useState(false);
  const [focus, setFocus] = useState(false);
  const [note, setNote] = useState('');
  const masked = value && !shown && !focus;
  const blur = () => {
    setFocus(false);
    if (value !== value.trim()) { onChange(value.trim()); setNote('已去掉首尾空格'); }
  };
  return (
    <div className="an-field">
      <span className="an-field-label">{label}</span>
      <span className="an-field-line">
        {masked
          ? <button type="button" className="an-mask mono" onClick={() => setShown(true)} aria-label={`${label}，已隐藏，点按显示`}>{anMask(value)}</button>
          : <input className="an-input mono" type={shown ? 'text' : 'password'} value={value} placeholder={placeholder} spellCheck={false} autoComplete="off"
              onFocus={() => setFocus(true)} onBlur={blur} onChange={e => { setNote(''); onChange(e.target.value); }} />}
        {value ? (
          <>
            <button type="button" className="an-icon-btn" aria-label={shown ? '隐藏' : '显示'} onClick={() => setShown(v => !v)}><AnGlyph name={shown ? 'eyeOff' : 'eye'} size={19} /></button>
            <button type="button" className="an-icon-btn" aria-label="清除" onClick={() => { onChange(''); setNote(''); setShown(false); }}><Icon name="close" size={14} weight={2.6} /></button>
          </>
        ) : <AnPasteBtn onClick={() => { onChange(demo); setNote('已粘贴'); }} />}
      </span>
      {value && <span className="an-field-hint">{note ? `${note} · ` : ''}<span className="num">{value.trim().length}</span> 个字符</span>}
    </div>
  );
}

function AnPick({ label, value, sub, onClick, tone, mono }) {
  return (
    <button type="button" className="an-pick" onClick={onClick}>
      <span className="an-pick-label">{label}</span>
      <span className={cx('an-pick-value', tone && `tone-${tone} tone-text`)}><span className={cx('an-pick-text', mono && 'mono')}>{value}</span>{sub && <small>{sub}</small>}</span>
      <span className="an-pick-chev"><Icon name="chevron" size={13} weight={2.6} /></span>
    </button>
  );
}

function AnStepper({ label, hint, value, min = 1, max = 999, onChange, nullable }) {
  const dec = () => onChange(value === null ? null : value <= min ? (nullable ? null : min) : value - 1);
  const inc = () => onChange(value === null ? min : Math.min(max, value + 1));
  return (
    <div className="an-row">
      <span className="an-row-text"><span className="an-row-label">{label}</span>{hint && <small>{hint}</small>}</span>
      <span className="an-stepper">
        <button type="button" aria-label={`减少${label}`} onClick={dec} disabled={value === null || (!nullable && value <= min)}><AnGlyph name="dash" size={16} weight={2.4} /></button>
        <b className={cx('num', value === null && 'is-default')}>{value === null ? '默认' : value}</b>
        <button type="button" aria-label={`增加${label}`} onClick={inc} disabled={value !== null && value >= max}><Icon name="plus" size={16} weight={2.4} /></button>
      </span>
    </div>
  );
}

function AnInline({ label, hint, value, onChange, suffix }) {
  return (
    <label className="an-row">
      <span className="an-row-text"><span className="an-row-label">{label}</span>{hint && <small>{hint}</small>}</span>
      <span className="an-inline"><input className="an-input num" inputMode="decimal" value={value} onChange={e => onChange(e.target.value.replace(/[^\d.]/g, ''))} aria-label={label} />{suffix && <i>{suffix}</i>}</span>
    </label>
  );
}

function AnToggle({ label, sub, on, onChange }) {
  return (
    <button type="button" className="an-row an-toggle" role="switch" aria-checked={on} onClick={() => onChange(!on)}>
      <span className="an-row-text"><span className="an-row-label">{label}</span>{sub && <small>{sub}</small>}</span>
      <span className={cx('st-switch', on && 'on')}><i /></span>
    </button>
  );
}

function AnKV({ label, value, mono }) {
  return <div className="an-kv"><span>{label}</span><b className={mono ? 'mono' : ''}>{value}</b></div>;
}

function AnSeg({ items, value, onChange }) {
  return <div className="an-seg-wrap"><Segmented items={items} value={value} onChange={onChange} /></div>;
}

function AnEmpty({ children }) {
  return <div className="an-empty">{children}</div>;
}

/* ---------- 平台与方式 ---------- */

function AnPlatformRow({ ctx, p, on, onClick }) {
  const n = anCount(ctx, p);
  return (
    <button type="button" className={cx('an-opt', on && 'on')} onClick={onClick}>
      <span className="an-mono">{p.mono}</span>
      <span className="an-opt-main"><b>{p.name}</b><small>{anTypeSummary(p.id)}</small></span>
      <span className="an-opt-side">{n > 0 && <span className="num">已有 {n}</span>}{on ? <Icon name="check" size={16} weight={2.8} /> : <Icon name="chevron" size={13} weight={2.6} />}</span>
    </button>
  );
}

function AnPlatformList({ ctx, w, onPick }) {
  return AN_SHELVES.map(([k, label]) => (
    <AnSec key={k} title={label}>
      {AN_PLATFORMS.filter(p => p.shelf === k).map(p => <AnPlatformRow key={p.id} ctx={ctx} p={p} on={w.d.platform === p.id} onClick={() => onPick(p.id)} />)}
    </AnSec>
  ));
}

// After the account exists the platform is fixed: UpdateAccountRequest has no platform field.
function AnPlatformLocked({ p }) {
  return (
    <AnSec id="platform" title="平台" foot="要换平台请删除后重建：在测试结果里选“删除账号…”，再重新新建。">
      <div className="an-opt is-locked">
        <span className="an-mono">{p.mono}</span>
        <span className="an-opt-main"><b>{p.name}</b><small>账号 #{AN_NEW_ID} 已创建，不能更换</small></span>
        <span className="an-opt-side"><AnGlyph name="lock" size={16} weight={2.2} /></span>
      </div>
    </AnSec>
  );
}

function AnPlatformGrid({ ctx, w }) {
  return AN_SHELVES.map(([k, label]) => (
    <div key={k} className="an-grid-shelf">
      <div className="an-grid-title">{label}</div>
      <div className="an-grid">
        {AN_PLATFORMS.filter(p => p.shelf === k).map(p => {
          const n = anCount(ctx, p);
          const on = w.d.platform === p.id;
          return (
            <button type="button" key={p.id} className={cx('an-tile', on && 'on')} onClick={() => w.pickPlatform(p.id)} aria-pressed={on}>
              <span className="an-mono">{p.mono}</span>
              <span className="an-tile-name">{p.name}</span>
              <small className="num">已有 {n}</small>
              {on && <span className="an-tile-check"><Icon name="check" size={12} weight={3.2} /></span>}
            </button>
          );
        })}
      </div>
    </div>
  ));
}

function AnTypeRow({ t, on, onClick, radio }) {
  return (
    <button type="button" className={cx('an-opt an-type', on && 'on', radio && 'is-radio')} onClick={onClick}>
      {radio ? <span className={cx('st-radio', on && 'on')}>{on && <Icon name="check" size={12} weight={3.2} />}</span> : <span className="an-type-ico"><Icon name={t.icon} size={18} weight={2.1} /></span>}
      <span className="an-opt-main"><b>{t.title}<em>{t.sub}</em></b><small>{t.need}</small></span>
      {!radio && <span className="an-opt-side">{on ? <Icon name="check" size={16} weight={2.8} /> : <Icon name="chevron" size={13} weight={2.6} />}</span>}
    </button>
  );
}

function AnTypeCards({ w }) {
  const p = anPlatform(w.d.platform);
  return (
    <div className="an-tcards">
      {anTypes(p.id).map(t => {
        const on = w.d.type === t.key;
        return (
          <button type="button" key={t.key} className={cx('an-tcard', on && 'on')} onClick={() => w.pickType(t.key)} aria-pressed={on}>
            <span className="an-type-ico"><Icon name={t.icon} size={20} weight={2.1} /></span>
            <span className="an-tcard-main"><b>{t.title}</b><em>{t.sub}</em><small>{t.need}</small></span>
            <span className={cx('st-radio', on && 'on')}>{on && <Icon name="check" size={12} weight={3.2} />}</span>
          </button>
        );
      })}
    </div>
  );
}

/* ---------- OAuth ---------- */

function AnLinkBox({ conf }) {
  return <div className="an-link mono" aria-label="授权链接"><span>{conf.url}</span></div>;
}

// Keep the element that needs the next tap visible above the bottom bar, without pushing its top out of view.
function anReveal(el) {
  const box = el && el.closest('.scroll, .an-card-body, .sheet-body');
  if (!box) return;
  const pad = box.classList.contains('has-bar') ? 124 : 16;
  const r = el.getBoundingClientRect();
  const b = box.getBoundingClientRect();
  const over = r.bottom - (b.bottom - pad);
  if (over > 0) box.scrollTop += Math.max(0, Math.min(over, r.top - b.top - 12));
}

function useAnReveal(selector, deps) {
  const ref = useRef(null);
  const first = useRef(true);
  useEffect(() => {
    if (first.current) { first.current = false; return; }
    if (ref.current) anReveal(ref.current.querySelector(selector) || ref.current);
  }, deps);
  return ref;
}

// exchange-code and every later request use this proxy, so it sits next to “完成授权”; changing it keeps the progress.
function AnProxyLine({ w, conf }) {
  const proxy = anProxyById(w.d.proxy);
  const o = w.d.oauth;
  const proxyFail = o.phase === 'failed' && o.error === 'proxy';
  return (
    <div className="an-proxyline-wrap">
      <button type="button" className="an-proxyline" onClick={() => w.openPicker('proxy')}>
        <Icon name="shield" size={15} />
        <span>代理</span>
        <b>{proxy ? `${proxy.name} · ${proxy.region}` : '无代理'}</b>
        <em>更换</em>
      </button>
      {conf.needsProxy && !proxy && !proxyFail && <small className="an-proxyline-hint">服务器连不上 {conf.upstream || conf.who} 时选一个代理。</small>}
    </div>
  );
}

function AnCodeField({ w, conf }) {
  const o = w.d.oauth;
  const recognized = conf.back === 'callback' && anCodeRecognized(o.code);
  return (
    <div className="an-codefield">
      <div className="an-code">
        <input className="an-input mono" value={o.code} spellCheck={false} autoComplete="off" aria-label={conf.back === 'code' ? '授权码' : '回调链接或 Code'}
          placeholder={conf.back === 'code' ? '粘贴页面上的授权码' : '粘贴回调链接或 code'} onChange={e => w.oauth.setCode(e.target.value)} />
        {o.code ? <button type="button" className="an-icon-btn" aria-label="清除" onClick={() => w.oauth.setCode('')}><Icon name="close" size={14} weight={2.6} /></button>
          : <AnPasteBtn onClick={w.oauth.paste} />}
      </div>
      {o.auto && o.code && <small className="an-code-ok"><Icon name="check" size={12} weight={3} /> 已自动接收回调（{conf.cb}），code 和 state 已填好</small>}
      {!o.auto && recognized && <small className="an-code-ok"><Icon name="check" size={12} weight={3} /> 已从链接里识别出 code 和 state</small>}
      {!o.code && o.copied && <small className="an-code-hint">刚才在浏览器里复制过，点“粘贴”即可</small>}
      {!o.code && !o.copied && o.listenFailed && <small className="an-code-hint">没能自动接收回调。重新打开浏览器，在 Safari 的错误页点底部 <b>分享 → 拷贝</b>，再回来点“粘贴”。</small>}
    </div>
  );
}

function AnOAuthFail({ o, conf, children }) {
  const up = conf.upstream || conf.who;
  const [title, text] = AN_OAUTH_ERR[o.error].map(s => s.replace(/\{up\}/g, up));
  return (
    <div className="an-fail tone-critical">
      <Icon name="octagon" size={17} weight={2.3} />
      <div><b>授权失败 · {title}</b><span>{text}</span></div>
      {children}
    </div>
  );
}

function AnCopyBtn({ label = '复制链接' }) {
  const [done, setDone] = useState(false);
  useEffect(() => {
    if (!done) return undefined;
    const t = setTimeout(() => setDone(false), 1800);
    return () => clearTimeout(t);
  }, [done]);
  return <button type="button" className="an-btn" onClick={() => setDone(true)}>{done ? <Icon name="check" size={15} weight={2.8} /> : <AnGlyph name="copy" size={16} />}{done ? '已复制' : label}</button>;
}

function anOauthCopy(conf, o) {
  const code = conf.back === 'code';
  return {
    lastTitle: code ? '粘贴授权码' : '完成授权',
    lastTrack: code ? '粘贴授权码' : '完成授权',
    browserDesc: code ? '授权后页面会显示授权码，复制它' : `授权后自动回到这里（App 临时监听 ${conf.cb}）`,
    lastDesc: code ? '回到这里粘贴，完成授权' : o.auto ? (o.phase === 'exchanging' ? '已自动填入，正在兑换令牌' : '兑换令牌走下面的代理') : '没有自动回来时，粘贴回调链接或 code',
  };
}

// Three numbered steps always visible; the current one carries its controls.
function AnOAuthList({ w, conf, remain }) {
  const o = w.d.oauth;
  const stage = anOauthStage(o);
  const failed = o.phase === 'failed';
  const busy = o.phase === 'generating' || o.phase === 'exchanging';
  const proxyFail = failed && o.error === 'proxy';
  const copy = anOauthCopy(conf, o);
  const ref = useAnReveal('.an-ol-step.on', [stage, o.phase]);
  const steps = [
    { title: '生成授权链接', desc: stage > 0 ? <>已生成 · <span className="num">{fmt.countdown(remain || 0)}</span> 内有效</> : '链接 30 分钟内有效' },
    { title: `在浏览器里登录 ${conf.who} 并授权`, desc: stage > 1 ? (o.auto ? `已授权，App 在 ${conf.cb} 接住了回调` : '已在浏览器完成') : copy.browserDesc },
    { title: copy.lastTitle, desc: copy.lastDesc },
  ];
  const act = [
    <div className="an-ol-act" key="0">
      {failed && <AnOAuthFail o={o} conf={conf} />}
      <button type="button" className="an-btn primary" disabled={busy} onClick={w.oauth.generate}>{busy ? <><span className="an-spin" />生成中…</> : failed ? '重新生成链接' : '生成授权链接'}</button>
    </div>,
    <div className="an-ol-act" key="1">
      {failed && <AnOAuthFail o={o} conf={conf} />}
      <AnLinkBox conf={conf} />
      <div className="an-row-btns">
        <button type="button" className="an-btn primary" onClick={w.oauth.open}><AnGlyph name="compass" size={17} />{failed ? '重新打开链接' : '在浏览器中打开'}</button>
        <AnCopyBtn />
      </div>
    </div>,
    <div className="an-ol-act" key="2">
      {failed && <AnOAuthFail o={o} conf={conf} />}
      <AnCodeField w={w} conf={conf} />
      <AnProxyLine w={w} conf={conf} />
      {proxyFail
        ? <button type="button" className="an-btn primary" onClick={w.oauth.retryWithProxy}><Icon name="shield" size={16} />换个代理再试</button>
        : <button type="button" className="an-btn primary" disabled={!o.code.trim() || busy} onClick={() => w.oauth.exchange()}>{busy ? <><span className="an-spin" />验证中…</> : '完成授权'}</button>}
      {failed && o.error === 'code' && <button type="button" className="an-btn plain" onClick={w.oauth.generate}>重新生成链接</button>}
      {!failed && !o.auto && !o.code && conf.back === 'callback' && <button type="button" className="an-btn plain" onClick={w.oauth.open}>重新打开浏览器</button>}
    </div>,
  ];
  return (
    <div className="an-ol" ref={ref}>
      {steps.map((s, i) => (
        <div key={i} className={cx('an-ol-step', i === stage && 'on', i < stage && 'done')}>
          <span className="an-ol-num num">{i < stage ? <Icon name="check" size={13} weight={3} /> : i + 1}</span>
          <div className="an-ol-body">
            <b>{s.title}</b><small>{s.desc}</small>
            {i === stage && act[i]}
          </div>
        </div>
      ))}
    </div>
  );
}

// One card, one action: the card morphs through 生成链接 → 浏览器授权 → 完成授权, with a slim progress track above.
function AnOAuthFocus({ w, conf, remain }) {
  const o = w.d.oauth;
  const stage = anOauthStage(o);
  const failed = o.phase === 'failed';
  const busy = o.phase === 'generating' || o.phase === 'exchanging';
  const proxyFail = failed && o.error === 'proxy';
  const copy = anOauthCopy(conf, o);
  const cards = [
    {
      glyph: <AnGlyph name="link" size={26} />, title: failed ? '重新生成授权链接' : '生成授权链接',
      text: `站点生成一次性的 ${conf.who} 授权链接，30 分钟内有效。`,
      primary: [busy ? '生成中…' : failed ? '重新生成链接' : '生成授权链接', w.oauth.generate],
    },
    {
      glyph: <AnGlyph name="compass" size={26} />, title: '在浏览器里授权',
      text: conf.back === 'code' ? `登录 ${conf.who} 后点“授权”，页面会显示授权码，复制它。` : `登录 ${conf.who} 后点“授权”。App 在 ${conf.cb} 等回调，授权完自动回来。`,
      body: <span className="an-site"><AnGlyph name="lock" size={12} weight={2.4} />{conf.host}<i>·</i><span className="num">{fmt.countdown(remain || 0)}</span> 内有效</span>,
      primary: [failed ? '重新打开链接' : '在浏览器中打开', w.oauth.open],
      secondary: <AnCopyBtn />,
    },
    {
      glyph: <AnGlyph name={conf.back === 'code' ? 'paste' : 'inbox'} size={26} />, title: copy.lastTitle,
      text: conf.back === 'code' ? '把浏览器里复制的授权码粘贴到这里。' : o.auto ? '已自动接收回调。兑换令牌走下面的代理。' : '没有自动回来时，粘贴回调链接或 code。',
      body: <><AnCodeField w={w} conf={conf} /><AnProxyLine w={w} conf={conf} /></>,
      primary: proxyFail ? ['换个代理再试', w.oauth.retryWithProxy] : [busy ? '验证中…' : '完成授权', () => w.oauth.exchange(), !o.code.trim()],
      secondary: failed && o.error === 'code' ? <button type="button" className="an-btn plain" onClick={w.oauth.generate}>重新生成链接</button>
        : proxyFail || o.auto ? null : <button type="button" className="an-btn plain" onClick={w.oauth.open}>重新打开浏览器</button>,
    },
  ];
  const c = cards[stage];
  const ref = useAnReveal('.an-focus-card .an-btn.primary', [stage, o.phase]);
  return (
    <div className="an-focus" ref={ref}>
      <div className="an-focus-track">
        {['生成链接', '浏览器授权', copy.lastTrack].map((t, i) => (
          <span key={t} className={cx(i < stage && 'done', i === stage && 'on')}><i />{t}</span>
        ))}
      </div>
      <div className="an-focus-card" key={stage}>
        <span className="an-focus-ico">{c.glyph}</span>
        <h3>{c.title}</h3>
        <p>{c.text}</p>
        {failed && <AnOAuthFail o={o} conf={conf} />}
        {c.body}
        <button type="button" className="an-btn primary block" disabled={busy || c.primary[2]} onClick={c.primary[1]}>{busy && <span className="an-spin" />}{c.primary[0]}</button>
        {c.secondary}
      </div>
    </div>
  );
}

function AnOAuthDone({ w, conf }) {
  const d = w.d;
  const setup = d.platform === 'anthropic' && d.method === 'setup-token';
  const proxy = anProxyById(d.proxy);
  const exp = typeof conf.expires === 'string' ? conf.expires : setup ? conf.expires.setup : conf.expires.oauth;
  return (
    <div className="an-authed">
      <div className="an-authed-top tone-ok">
        <span className="an-authed-ico"><Icon name="checkCircle" size={22} weight={2.2} /></span>
        <div><b>授权成功</b><span>{AN_EMAIL}</span></div>
      </div>
      <AnKV label="凭据" value={setup ? 'Setup Token' : '访问令牌 + 刷新令牌'} />
      <AnKV label="到期" value={exp} />
      <AnKV label="代理" value={proxy ? proxy.name : '无代理'} />
      <button type="button" className="an-text-btn" onClick={w.oauth.reset}>重新授权</button>
    </div>
  );
}

function AnOAuth({ ctx, w }) {
  const conf = AN_OAUTH[w.d.platform];
  if (w.d.oauth.phase === 'done') return <AnOAuthDone w={w} conf={conf} />;
  const Comp = ctx.v.anOauth === 'focus' ? AnOAuthFocus : AnOAuthList;
  return <Comp w={w} conf={conf} remain={w.remain} />;
}

// Stand-in for the in-app Safari sheet (SFSafariViewController); the session shares Safari's login.
// 'caught' is the tiny page the app's own NWListener serves on the callback port before it closes the sheet.
function AnBrowser({ w }) {
  const d = w.d;
  const conf = AN_OAUTH[d.platform];
  const page = w.browser;
  const [copied, setCopied] = useState(false);
  const setup = d.platform === 'anthropic' && d.method === 'setup-token';
  useEffect(() => {
    if (page !== 'caught') return undefined;
    const t = setTimeout(w.oauth.caught, 1400);
    return () => clearTimeout(t);
  }, [page]);
  const cbHost = conf.cb ? conf.cb.split(':')[0] : '';
  const host = page === 'consent' ? conf.host : conf.back === 'code' ? conf.codeHost : cbHost;
  const scopes = setup ? ['创建长期有效的推理令牌', '以你的身份调用 Claude'] : [`以你的身份调用 ${conf.who} 模型`, '读取订阅与用量额度'];
  const errorPage = page === 'result' && conf.back === 'callback';
  const done = () => (page === 'caught' ? w.oauth.caught() : w.oauth.closeBrowser(page === 'result', copied));
  let body;
  if (page === 'consent') {
    body = (
      <div className="an-br-page">
        <span className="an-br-logo">{conf.who.slice(0, 1)}</span>
        <h3>{conf.client} 请求访问你的 {conf.who} 账号</h3>
        <div className="an-br-acct">已登录 · {AN_EMAIL}</div>
        <ul>{scopes.map(s => <li key={s}><Icon name="check" size={14} weight={2.6} />{s}</li>)}</ul>
        <button type="button" className="an-br-allow" onClick={w.oauth.authorize}>授权</button>
        <button type="button" className="an-br-deny" onClick={w.oauth.deny}>拒绝</button>
      </div>
    );
  } else if (page === 'caught') {
    body = (
      <div className="an-br-page an-br-caught">
        <span className="an-br-ok"><Icon name="checkCircle" size={34} weight={2} /></span>
        <h3>授权已交给 Sub2</h3>
        <p>这一页由 App 在 {conf.cb} 临时提供，马上自动关闭。</p>
      </div>
    );
  } else if (conf.back === 'code') {
    body = (
      <div className="an-br-page">
        <h3>授权码</h3>
        <p>复制下面的代码，粘贴回应用里完成授权。</p>
        <div className="an-br-code mono">{conf.demo}</div>
        <button type="button" className="an-br-allow" onClick={() => setCopied(true)}>{copied ? '已复制' : '复制代码'}</button>
      </div>
    );
  } else {
    // Safari's own error page: no buttons in the page; the URL can only be copied via the toolbar's share button.
    body = (
      <div className="an-br-page an-br-errpage">
        <div className="an-br-err"><AnGlyph name="compass" size={44} weight={1.4} /><h3>Safari 浏览器打不开该网页</h3><p>因为 Safari 浏览器无法连接服务器“{cbHost}”。</p></div>
      </div>
    );
  }
  return (
    <div className="overlay overlay-dim an-browser">
      <div className="an-br-sheet" role="dialog" aria-label="浏览器">
        <div className="sheet-grabber" />
        <div className="an-br-bar">
          <button type="button" className="an-br-done" onClick={done}>完成</button>
          <span className="an-br-url"><AnGlyph name="lock" size={12} weight={2.4} />{host}</span>
          <span className="an-br-reload"><Icon name="refresh" size={17} /></span>
        </div>
        {body}
        <div className="an-br-tools">
          <Icon name="back" size={20} /><Icon name="chevron" size={18} />
          {errorPage
            ? <button type="button" className={cx('an-br-share', copied && 'done')} aria-label="分享" onClick={() => setCopied(true)}><AnGlyph name="share" size={20} />{copied && <span className="an-br-bubble">已拷贝</span>}</button>
            : <AnGlyph name="share" size={20} />}
          <AnGlyph name="compass" size={20} />
        </div>
      </div>
    </div>
  );
}

/* ---------- 凭据 ---------- */

function AnCred({ ctx, w }) {
  const t = anTypeOf(w.d);
  if (!t) return null;
  const isError = w.d.run.held === 'error';
  return (
    <>
      {w.d.run.retry && (
        <div className={cx('an-retry-note', isError && 'is-error')} data-sec="retry">
          <Icon name={isError ? 'octagon' : 'pauseFill'} size={14} />
          <span>{isError
            ? `账号 #${AN_NEW_ID} 已创建，已被标为错误（已停止调度）；这里的修改会在“保存并重新测试”时保存到它，测试通过后错误自动清除。`
            : `账号 #${AN_NEW_ID} 已创建，暂停调度中；这里的修改会在“保存并重新测试”时保存到它。`}</span>
        </div>
      )}
      <AnCredBody ctx={ctx} w={w} t={t} />
    </>
  );
}

// CN providers: API protocol (adaptive by default); a specific protocol unlocks the endpoint picker (presets + custom).
function AnAccess({ w, t }) {
  const { d, set } = w;
  const protos = anProtocols(d.platform, t.mode);
  const url = anEndpointOf(d);
  const preset = anPresets(d.platform, t.mode, d.protocol).find(x => x[3] === url);
  return (
    <AnSec title="接入" foot={d.protocol === 'adaptive' ? '按入站协议优先使用供应商原生端点，没有对应端点时才转换。' : '请求都转发到这个端点；入站协议不同时由网关转换。'}>
      {protos.length > 1
        ? <AnPick label="API 协议" value={AN_PROTO[d.protocol][0]} onClick={() => w.openPicker('protocol')} />
        : <AnKV label="API 协议" value={AN_PROTO[protos[0] || 'chat_completions'][0]} />}
      {d.protocol === 'adaptive'
        ? <AnKV label="官方端点" value={AN_ENDPOINT[d.platform][t.mode]} mono />
        : <AnPick label="端点" value={d.endpoint === 'custom' ? '自定义' : preset ? preset[2] : anHost(url)} onClick={() => w.openPicker('endpoint')} />}
      {d.protocol !== 'adaptive' && d.endpoint === 'custom' && <AnInput label="自定义端点" mono value={d.customUrl} placeholder="https://" onChange={v => set({ customUrl: v })} />}
    </AnSec>
  );
}

function AnCredBody({ ctx, w, t }) {
  const { d, set } = w;
  // After a failed test, “粘贴” brings the corrected secret (demo), so 保存并重新测试 can pass.
  const fresh = v => (w.created ? anFreshKey(v) : v);
  if (t.flow === 'oauth') {
    return (
      <>
        {d.platform === 'anthropic' && (
          <AnSec id="cred" title="添加方式" foot={d.method === 'setup-token' ? 'Setup Token 长期有效（约 1 年），不需要刷新。' : '访问令牌约 8 小时有效，到期前自动刷新。'}>
            <AnSeg items={[{ key: 'oauth', label: 'OAuth' }, { key: 'setup-token', label: 'Setup Token' }]} value={d.method} onChange={w.setMethod} />
          </AnSec>
        )}
        {d.platform === 'gemini' && (
          <AnSec id="cred" title="授权类型" foot={d.gemType === 'code_assist' ? '企业级，需要激活 GCP 项目并绑定信用卡。' : '个人账号，享受 Google One 订阅配额。'}>
            <AnSeg items={[{ key: 'google_one', label: 'Google One' }, { key: 'code_assist', label: 'Code Assist' }]} value={d.gemType} onChange={w.setGemType} />
            {d.gemType === 'code_assist' && <AnInput label="GCP Project ID" mono value={d.project} placeholder="your-gcp-project-id" onChange={v => set({ project: v })} />}
          </AnSec>
        )}
        <AnSec id={['anthropic', 'gemini'].includes(d.platform) ? 'oauth' : 'cred'} title={`${AN_OAUTH[d.platform].who} 授权`} meta={d.oauth.phase === 'done' ? '已完成' : null}
          foot={d.oauth.phase !== 'done' && anOauthStage(d.oauth) === 2 ? '兑换令牌和之后的请求都走所选代理。' : null}>
          <AnOAuth ctx={ctx} w={w} />
        </AnSec>
      </>
    );
  }
  if (t.flow === 'key') {
    const base = AN_BASE[d.platform];
    const p = anPlatform(d.platform);
    return (
      <>
        <AnSec id="cred" title={t.mode ? `${AN_MODES[t.mode][0]} · 凭据` : '凭据'} foot={base ? `${base[1]}Key 只提交到站点，App 不保存。` : 'Key 只提交到站点，App 不保存。'}>
          <AnKey value={d.apiKey} placeholder={AN_KEY_HINT[d.platform] || 'sk-...'} demo={fresh(AN_DEMO_KEY[d.platform] || AN_DEMO_KEY.other)} onChange={v => set({ apiKey: v })} />
          {base && <AnInput label="Base URL" mono value={d.baseUrl} placeholder={base[0]} onChange={v => set({ baseUrl: v })} />}
        </AnSec>
        {!base && p.modes && <AnAccess w={w} t={t} />}
      </>
    );
  }
  if (t.flow === 'bedrock') {
    return (
      <>
        <AnSec id="cred" title="认证方式">
          <AnSeg items={[{ key: 'sigv4', label: 'SigV4 签名' }, { key: 'apikey', label: 'Bedrock API Key' }]} value={d.bedrockAuth} onChange={v => set({ bedrockAuth: v })} />
        </AnSec>
        <AnSec title="凭据" foot={d.bedrockAuth === 'sigv4' ? 'Session Token 可选，用于临时凭证。' : 'Bearer Token 认证。'}>
          {d.bedrockAuth === 'sigv4' ? (
            <>
              <AnInput label="AWS Access Key ID" mono value={d.akid} placeholder="AKIA..." demo={AN_BEDROCK_DEMO.akid} onChange={v => set({ akid: v })} />
              <AnKey label="AWS Secret Access Key" value={d.secret} placeholder="必填" demo={fresh(AN_BEDROCK_DEMO.secret)} onChange={v => set({ secret: v })} />
              <AnInput label="AWS Session Token" mono value={d.session} placeholder="可选" onChange={v => set({ session: v })} />
            </>
          ) : <AnKey label="Bedrock API Key" value={d.bedrockKey} placeholder="必填" demo={fresh(AN_BEDROCK_DEMO.key)} onChange={v => set({ bedrockKey: v })} />}
          <AnPick label="AWS Region" value={d.region} onClick={() => w.openPicker('region')} />
        </AnSec>
      </>
    );
  }
  if (t.flow === 'vertex') {
    return (
      <>
        <AnSec id="cred" title="Service Account JSON" foot="密钥内容不会显示，只在创建账号时提交。">
          {d.vertexFile ? (
            <div className="an-file">
              <span className="an-file-ico"><AnGlyph name="file" size={20} /></span>
              <span className="an-opt-main"><b>{d.vertexFile.name}</b><small>已读取 · project_id <span className="mono">{d.vertexFile.project}</span></small></span>
              <button type="button" className="an-text-btn" onClick={() => set({ vertexFile: AN_VERTEX_FILE })}>重新选择</button>
            </div>
          ) : (
            <button type="button" className="an-filepick" onClick={() => set({ vertexFile: AN_VERTEX_FILE })}><AnGlyph name="file" size={20} />从“文件”选择 JSON</button>
          )}
        </AnSec>
        <AnSec title="Location" foot="不同模型可用的 location 不同，这里选账号默认的。">
          <AnPick label="Location" value={d.location} onClick={() => w.openPicker('location')} />
        </AnSec>
      </>
    );
  }
  return (
    <AnSec id="cred" title="上游" foot="上游 Antigravity 服务的地址和 Key。">
      <AnInput label="上游 Base URL" mono value={d.upstreamUrl} placeholder="https://cloudcode-pa.googleapis.com" demo={AN_UPSTREAM_DEMO.url} onChange={v => set({ upstreamUrl: v })} />
      <AnKey label="上游 API Key" value={d.upstreamKey} placeholder="必填" demo={fresh(AN_UPSTREAM_DEMO.key)} onChange={v => set({ upstreamKey: v })} />
    </AnSec>
  );
}

/* ---------- 名称与调度 ---------- */

function AnSetup({ ctx, w, chips }) {
  const { d, set } = w;
  const p = d.platform ? anPlatform(d.platform) : null;
  const allowed = anGroupPlatforms(d);
  const groups = anActiveGroups().filter(g => allowed.includes(g.platform)).sort((a, b) => allowed.indexOf(a.platform) - allowed.indexOf(b.platform));
  const toggle = id => set(cur => ({ groups: cur.groups.includes(id) ? cur.groups.filter(x => x !== id) : [...cur.groups, id] }));
  const proxy = anProxyById(d.proxy);
  const [more, setMore] = useState(Boolean(d.expires || d.load || d.overages));
  const ag = d.platform === 'antigravity';
  const gSub = g => {
    const av = groupAvailability(ctx.accounts, g.id);
    // The platform is named only when it differs from the account's own (组合 / the mixed-scheduling Anthropic, Gemini groups).
    return [g.platform === 'composite' ? '组合' : g.platform !== p.name && g.platform, `倍率 ${g.rate}`, g.subscriptionType === 'subscription' && '订阅', g.exclusive && '专属',
      av.total ? `可用 ${av.available}/${av.total}` : '还没有账号'].filter(Boolean).join(' · ');
  };
  const clash = g => (d.groups.includes(g.id) ? anGroupClash(ctx, d, g) : null);
  // Chips have no room for a second line, so a selected group that will raise the mixed-channel dialog is named in the footer.
  const clashed = chips ? groups.filter(clash) : [];
  const groupFoot = !p ? null : (
    <>
      {clashed.map(g => <span key={g.id} className="tone-caution tone-text an-foot-warn">「{g.name}」里已有 {clash(g)} 账号，创建时要确认混合渠道风险。</span>)}
      {ag && d.mixed
        ? <span className="tone-caution tone-text">Antigravity Claude 和 Anthropic Claude 不能在同一上下文里用。开启后请用分组把两类账号隔开。</span>
        : <span>只列出 {p.name} 分组和组合分组；停用的分组不列出。</span>}
    </>
  );
  return (
    <>
      <AnSec id="name" title="名称" meta={chips ? (d.name.trim() ? null : '必填') : null} foot={d.nameAuto && d.name ? '按平台自动起名，可以改。' : null}>
        <AnInput label="名称" value={d.name} placeholder={p ? anSuggestName(ctx, p.id) : '例如 Claude-04'} onChange={v => set({ name: v, nameAuto: false })} />
        <AnInput label="备注" value={d.notes} placeholder="可选" onChange={v => set({ notes: v })} />
      </AnSec>
      <AnSec id="groups" title="分组" meta={d.groups.length ? `已选 ${d.groups.length}${clashed.length ? ` · ${clashed.length} 个需确认` : ''}` : '可不选'} foot={groupFoot}>
        {ag && <AnToggle label="在 /v1/messages 中使用" sub="开启后可加入 Anthropic / Gemini 分组" on={d.mixed} onChange={w.setMixed} />}
        {!p ? <AnEmpty>先选平台</AnEmpty> : !groups.length ? <AnEmpty>没有可选的 {p.name} 分组，不分组也能创建。</AnEmpty> : chips ? (
          <div className="an-chips">
            {groups.map(g => {
              const on = d.groups.includes(g.id);
              const risky = on && clash(g);
              // Selected stays selected (check + accent); the risk is an extra mark after the name and a caution edge.
              return (
                <button type="button" key={g.id} className={cx('chip', on && 'on', risky && 'an-chip-risk')} onClick={() => toggle(g.id)} aria-pressed={on}
                  aria-label={`${g.name}，倍率 ${g.rate}${g.platform !== p.name ? `，${g.platform} 分组` : ''}${risky ? '，有混合渠道风险' : ''}`}>
                  {on && <Icon name="check" size={13} weight={3} />}<span>{g.name}</span>
                  {risky && <span className="an-chip-warn"><Icon name="bell" size={13} weight={2.6} /></span>}
                  {g.platform !== p.name && <small>{g.platform}</small>}<b className="num">×{g.rate}</b>
                </button>
              );
            })}
          </div>
        ) : groups.map(g => (
          <button type="button" key={g.id} className={cx('an-opt an-group', d.groups.includes(g.id) && 'on')} onClick={() => toggle(g.id)} aria-pressed={d.groups.includes(g.id)}>
            <span className={cx('select-ring', d.groups.includes(g.id) && 'on')}>{d.groups.includes(g.id) && <Icon name="check" size={13} weight={3} />}</span>
            <span className="an-opt-main"><b>{g.name}</b><small className="num">{gSub(g)}</small>
              {clash(g) && <small className="an-clash tone-caution tone-text">已有 {clash(g)} 账号，提交时确认混合渠道风险</small>}</span>
          </button>
        ))}
      </AnSec>
      <AnSec id="sched" title="调度">
        <AnStepper label="并发数" value={d.conc} min={1} max={100} onChange={v => set({ conc: v })} />
        <AnStepper label="优先级" hint="数值越小越优先" value={d.prio} min={1} max={99} onChange={v => set({ prio: v })} />
        <AnInline label="账号计费倍率" hint="0 表示不计费，只影响账号计费" value={d.rate} suffix="×" onChange={v => set({ rate: v })} />
      </AnSec>
      <AnSec id="net" title="网络">
        <AnPick label="代理" value={proxy ? proxy.name : '无代理'} sub={proxy ? anProxyWhere(proxy) : null} onClick={() => w.openPicker('proxy')} />
      </AnSec>
      <AnSec id="more" title="更多" foot={more ? '模型白名单与映射、自定义错误码、配额等，创建后在账号详情里设置。' : null}>
        <button type="button" className={cx('an-disclose', more && 'open')} onClick={() => setMore(v => !v)} aria-expanded={more}>
          <span>{ag ? '过期时间、负载因子、AI Credits' : '过期时间、负载因子'}</span>{!more && <small className="num">{d.expires ? `${d.expires} 到期` : '不过期'}</small>}<Icon name="chevron" size={13} weight={2.6} />
        </button>
        {more && <AnPick label="过期时间" value={d.expires || '不过期'} mono={Boolean(d.expires)} onClick={() => w.openPicker('expires')} />}
        {more && d.expires && <AnToggle label="过期自动暂停调度" on={d.autoPause} onChange={v => set({ autoPause: v })} />}
        {more && <AnStepper label="负载因子" hint="提高后调度更频繁" nullable value={d.load} min={1} max={10} onChange={v => set({ load: v })} />}
        {more && ag && <AnToggle label="允许超量请求（AI Credits）" sub="免费配额确认用完后才用 AI Credits，普通 429 不切换" on={d.overages} onChange={v => set({ overages: v })} />}
      </AnSec>
    </>
  );
}

/* ---------- 检查、创建并测试 ---------- */

function AnReview({ w, onEdit }) {
  const d = w.d;
  const p = anPlatform(d.platform);
  const t = anTypeOf(d);
  const proxy = anProxyById(d.proxy);
  const names = anGroupNames(d.groups).join('、');
  if (!p || !t) return <AnSec id="review" title="检查"><AnEmpty>先选平台和认证方式</AnEmpty></AnSec>;
  const ep = anEndpointOf(d);
  const rows = [
    ['平台', `${p.name} · ${t.title}${anApiType(d) === 'setup-token' ? ' · Setup Token' : ''}`, d.run.retry ? 1 : 0],
    [t.flow === 'oauth' ? '授权' : '凭据', anCredSummary(d), 2],
    ...(t.mode ? [['接入', d.protocol === 'adaptive' ? '自适应' : `${AN_PROTO[d.protocol][0]} · ${d.endpoint === 'custom' ? anHost(d.customUrl) || '自定义' : anHost(ep)}`, 2]] : []),
    ['名称', d.name.trim() || '—', 3],
    ['分组', names || '未分组', 3],
    ['调度', `并发 ${d.conc} · 优先级 ${d.prio} · 倍率 ${d.rate || '—'}`, 3],
    ['代理', proxy ? `${proxy.name} · ${proxy.region}` : '无代理', 3],
  ];
  const foot = d.run.retry
    ? <><Icon name="shield" size={13} /><span>保存后重新测试，通过才启用调度。测试会向上游发一次真实请求，可能产生少量费用。</span></>
    : <><Icon name="shield" size={13} /><span>创建后立即停止调度，测试通过再启用。测试会向上游发一次真实请求，可能产生少量费用。</span></>;
  return (
    <AnSec id="review" title="检查" foot={foot}>
      {rows.map(([label, value, step]) => (
        <button type="button" key={label} className="an-rev" onClick={() => onEdit(step)}>
          <span className="an-rev-label">{label}</span>
          <span className={cx('an-rev-value', label === '凭据' && 'mono')}>{value}</span>
          <Icon name="chevron" size={13} weight={2.6} />
        </button>
      ))}
    </AnSec>
  );
}

function AnStage({ state, title, meta, onMeta }) {
  const ico = { done: <Icon name="check" size={13} weight={3.2} />, bad: <Icon name="close" size={12} weight={3.2} />, run: <span className="an-spin" />, wait: null, off: <AnGlyph name="dash" size={12} weight={3} /> }[state];
  return (
    <div className={cx('an-stage', `is-${state}`)}>
      <span className="an-stage-ico">{ico}</span>
      <b>{title}</b>
      {onMeta
        ? <button type="button" className="an-stage-menu" onClick={onMeta} aria-label={`测试模型 ${meta}，点按更换`}><span className="mono">{meta}</span><Icon name="chevronDown" size={11} weight={2.8} /></button>
        : meta && <small className="num">{meta}</small>}
    </div>
  );
}

// The SSE output streams while the test runs; once it ends the result takes its place under 进度 and the output folds into one
// row (SwiftUI: DisclosureGroup) showing its last line, so progress, result and actions fit the sheet without scrolling.
function AnLog({ lines, running }) {
  const [open, setOpen] = useState(false);
  const last = lines[lines.length - 1] || '';
  const tone = l => cx(l.startsWith('错误') && 'bad', l === '测试完成！' && 'good');
  if (running || open) {
    return (
      <div className="an-log">
        {!running && <button type="button" className="an-log-head" onClick={() => setOpen(false)} aria-expanded="true"><span>测试输出</span><small className="num">{lines.length} 行</small><Icon name="chevronUp" size={13} weight={2.6} /></button>}
        <pre className="stream mono an-stream" aria-live="polite">
          {lines.map((l, i) => <span key={i} className={tone(l)}>{l}{'\n'}</span>)}
          {running && <span className="an-caret">▍</span>}
        </pre>
      </div>
    );
  }
  return (
    <button type="button" className="an-log-fold" onClick={() => setOpen(true)} aria-expanded="false">
      <span className="an-log-label">测试输出 <small className="num">{lines.length} 行</small></span>
      <span className={cx('an-log-last mono', tone(last))}>{last}</span>
      <Icon name="chevronDown" size={13} weight={2.6} />
    </button>
  );
}

function AnTest({ w, onEdit, onRetry }) {
  const d = w.d;
  const r = d.run;
  const ref = useRef(null);
  // Follow the output while it streams; afterwards bring the result block in, never pushing its top out of view.
  useEffect(() => {
    if (r.phase === 'idle' || !ref.current) return;
    const el = ref.current.querySelector('.an-outcome') || ref.current.querySelector('.an-stream');
    if (el) anReveal(el);
  }, [r.phase, r.n]);
  if (r.phase === 'idle') return <AnReview w={w} onEdit={onEdit} />;
  const lines = anTestLines(d, r.ok).slice(0, r.n);
  const tested = ['testing', 'passed', 'failed'].includes(r.phase);
  const model = anModelOf(d);
  const fail = r.fail || anFailReason(d);
  const isError = r.held === 'error';
  const pausing = { creating: 'wait', pausing: 'run', pauseFailed: 'bad' }[r.phase] || 'done';
  // Deleting #21 is part of this flow, so it stays in the sheet — as the last, quiet text button (it still asks for the name).
  const del = <button type="button" className="an-text-btn an-del" onClick={w.run.remove}>删除账号…</button>;
  return (
    <div ref={ref} className="an-test">
      <AnSec title="进度" foot={w.running ? '测试会向上游发一次真实请求，可能产生少量费用。' : null}>
        {r.retry
          ? <AnStage state={r.phase === 'saving' ? 'run' : r.saved === false ? 'off' : 'done'} title="保存修改" meta={r.phase === 'saving' ? null : r.saved === false ? '没有改动' : `#${AN_NEW_ID}`} />
          : <AnStage state={r.phase === 'creating' ? 'run' : 'done'} title="创建账号" meta={r.phase === 'creating' ? null : `#${AN_NEW_ID}`} />}
        {r.retry
          ? <AnStage state="done" title="停止调度" meta={r.phase === 'passed' ? null : isError ? '错误 · 不接收请求' : '保持暂停'} />
          : <AnStage state={pausing} title="停止调度" meta={pausing === 'bad' ? '没有确认' : pausing === 'done' && r.phase !== 'passed' ? '不接收请求' : null} />}
        <AnStage state={!tested ? 'wait' : r.phase === 'testing' ? 'run' : r.phase === 'passed' ? 'done' : 'bad'} title="测试连接"
          meta={tested ? model : null} onMeta={r.phase === 'passed' || r.phase === 'failed' ? () => w.openPicker('model') : null} />
        <AnStage state={r.phase === 'passed' ? 'done' : r.phase === 'failed' ? 'off' : 'wait'} title="启用调度" meta={r.phase === 'passed' ? '参与调度' : r.phase === 'failed' ? '未启用' : null} />
      </AnSec>
      {r.phase === 'pauseFailed' && (
        <div className="an-outcome">
          <div className="result tone-critical"><Icon name="octagon" size={20} /><span><b>停止调度没有确认 · 结果待核对</b><small><em>账号 #{AN_NEW_ID} 已创建，可能正在参与调度。</em>凭据还没验证，可能已经在接收请求。重试一次停止调度，成功后自动开始测试。</small></span></div>
          <button type="button" className="an-btn primary block" onClick={w.run.repause}><Icon name="pauseFill" size={15} />重试停止调度</button>
          {del}
        </div>
      )}
      {r.phase === 'passed' && (
        <div className="an-outcome">
          <div className="result tone-ok"><Icon name="checkCircle" size={20} /><span><b>测试通过 · 已启用调度</b><small>{r.cleared ? '错误状态已自动清除。' : ''}本机计时：首字 <span className="num">1.21s</span> · 总耗时 <span className="num">3.42s</span></small></span></div>
          <div className="an-row-btns">
            <button type="button" className="an-btn" onClick={w.run.view}>查看账号</button>
            <button type="button" className="an-btn primary" onClick={w.run.done}>完成</button>
          </div>
        </div>
      )}
      {r.phase === 'failed' && (
        <div className="an-outcome">
          <div className="result tone-critical"><Icon name="octagon" size={20} /><span><b>测试未通过 · {fail.human}</b><small><em className="mono">{fail.raw}</em>
            {isError ? `后端已把账号 #${AN_NEW_ID} 标为“错误”，并停止调度，不会接收请求。` : `账号 #${AN_NEW_ID} 已停止调度，不会接收请求。`}</small></span></div>
          <button type="button" className="an-btn primary block" onClick={onRetry}>修改凭据后重试</button>
          <div className="an-row-btns">
            <button type="button" className="an-btn" onClick={() => w.run.keep()}>{isError ? '保留（错误状态）' : '保留，暂停调度'}</button>
            <button type="button" className="an-btn" onClick={() => w.run.saveInactive()}>保存为停用</button>
          </div>
          <small className="an-after-note">{isError
            ? '保留：以后在详情里改好凭据再测试，通过后错误自动清除，再启用调度。停用：状态改为“停用”。点上面的模型名可以换个模型再测。'
            : '保留：以后在详情里改好凭据再启用调度。停用：状态改为“停用”。点上面的模型名可以换个模型再测。'}</small>
          {del}
        </div>
      )}
      {tested && <AnLog lines={lines} running={r.phase === 'testing'} />}
    </div>
  );
}

/* ---------- 选择器（代理、过期时间、Region、Location、协议、端点、测试模型） ---------- */

function AnChoice({ on, title, sub, onClick, disabled, badge }) {
  return (
    <button type="button" className={cx('an-choice', disabled && 'is-off')} onClick={disabled ? undefined : onClick} disabled={disabled}>
      <span className={cx('st-radio', on && 'on')}>{on && <Icon name="check" size={12} weight={3.2} />}</span>
      <span className="an-opt-main"><b>{title}</b>{sub && <small className="num">{sub}</small>}</span>
      {badge}
    </button>
  );
}

// Presets as in Web (1 个月 / 1 年 / 不过期) plus a DatePicker for any date; interpreted in the device's time zone.
function AnExpiresSheet({ w }) {
  const { d, set } = w;
  const preset = AN_EXPIRES.find(e => e[0] === d.expires);
  const [custom, setCustom] = useState(Boolean(d.expires && !preset));
  const [date, setDate] = useState(d.expires && !preset ? d.expires.slice(0, 10) : anExpiry(2).slice(0, 10));
  const [time, setTime] = useState(d.expires && !preset ? d.expires.slice(11) : '23:59');
  const pick = v => { set({ expires: v }); w.closePicker(); };
  // Must lie in the future (the server would pause an already-expired account right away).
  const future = /^\d{4}-\d{2}-\d{2}$/.test(date) && /^\d{2}:\d{2}$/.test(time) && `${date} ${time}` > AN_NOW;
  return (
    <Sheet title="过期时间" onClose={w.closePicker}
      trailing={custom ? <button type="button" className={cx('glass-btn glass-btn-text', future && 'glass-prominent')} disabled={!future} onClick={() => pick(`${date} ${time}`)}><span>完成</span></button> : null}>
      <div className="an-choices">
        {AN_EXPIRES.map(([v, label]) => <AnChoice key={label} on={!custom && d.expires === v} title={label} sub={v || '一直可用'} onClick={() => pick(v)} />)}
        <AnChoice on={custom} title="自选日期…" sub={custom ? `${date} ${time}` : '选择日期和时间'} onClick={() => setCustom(true)} />
      </div>
      {custom && (
        <div className="an-datepick">
          <label className="an-dp-row"><span>日期</span><input type="date" className="num" value={date} min={DEMO_TODAY} onChange={e => setDate(e.target.value)} /></label>
          <label className="an-dp-row"><span>时间</span><input type="time" className="num" value={time} onChange={e => setTime(e.target.value)} /></label>
        </div>
      )}
      <p className="an-sheet-note">按本机时区（{AN_TZ}）解释。</p>
    </Sheet>
  );
}

function AnOverlays({ w }) {
  const { d, set } = w;
  const pk = w.picker;
  const t = anTypeOf(d);
  const pick = fn => () => { fn(); w.closePicker(); };
  const proxyRetry = pk === 'proxyRetry';
  const chooseProxy = id => { w.setProxy(id); if (proxyRetry) w.oauth.exchange(undefined, id); };
  const model = d.platform ? anModelOf(d) : null;
  return (
    <>
      {(pk === 'proxy' || proxyRetry) && (
        <Sheet title={proxyRetry ? '换个代理再试' : '代理'} onClose={w.closePicker}>
          {proxyRetry && <p className="an-sheet-note">授权码还没用掉。选好代理后，直接用它重新兑换令牌。</p>}
          <div className="an-choices">
            {!proxyRetry && <AnChoice on={d.proxy === null} title="无代理" sub="服务器直连上游" onClick={pick(() => chooseProxy(null))} />}
            {anProxies().map(x => {
              // Only the warning cases get a badge (N 天后到期 / 今天到期 / 已到期 · 等待处理); 剩余 N 天 and 永不过期 stay quiet.
              const due = proxyExpiry(x);
              return (
                <AnChoice key={x.id} on={d.proxy === x.id} title={x.name}
                  sub={`${anProxyWhere(x)} · 延迟 ${x.latency === null ? '—' : `${x.latency} ms`} · ${x.accounts.length} 个账号`}
                  badge={due.tone !== 'none' ? <span className={`badge tone-${due.tone}`}>{due.label}</span> : null}
                  onClick={pick(() => chooseProxy(x.id))} />
              );
            })}
          </div>
          <p className="an-sheet-note an-sheet-foot-note">只列出状态正常的代理；停用、已过期的代理到“代理”里处理。</p>
        </Sheet>
      )}
      {pk === 'expires' && <AnExpiresSheet w={w} />}
      {pk === 'region' && (
        <Sheet title="AWS Region" onClose={w.closePicker}>
          <div className="an-choices">{AN_REGIONS.map(v => <AnChoice key={v} on={d.region === v} title={v} onClick={pick(() => set({ region: v }))} />)}</div>
        </Sheet>
      )}
      {pk === 'location' && (
        <Sheet title="Vertex Location" onClose={w.closePicker}>
          <div className="an-choices">{AN_LOCATIONS.map(v => <AnChoice key={v} on={d.location === v} title={v} onClick={pick(() => set({ location: v }))} />)}</div>
        </Sheet>
      )}
      {pk === 'protocol' && t && (
        <Sheet title="API 协议" onClose={w.closePicker}>
          <div className="an-choices">
            {anProtocols(d.platform, t.mode).map(k => <AnChoice key={k} on={d.protocol === k} title={AN_PROTO[k][0]} sub={AN_PROTO[k][1]} onClick={pick(() => w.setProtocol(k))} />)}
          </div>
        </Sheet>
      )}
      {pk === 'endpoint' && t && (
        <Sheet title="端点" onClose={w.closePicker}>
          <div className="an-choices">
            {anPresets(d.platform, t.mode, d.protocol).map(([, , label, url]) => (
              <AnChoice key={label} on={d.endpoint !== 'custom' && anEndpointOf(d) === url} title={label} sub={anHost(url)} onClick={pick(() => set({ endpoint: url }))} />
            ))}
            <AnChoice on={d.endpoint === 'custom'} title="自定义…" sub="填写其他兼容地址" onClick={pick(() => set({ endpoint: 'custom' }))} />
          </div>
        </Sheet>
      )}
      {pk === 'model' && (
        <Sheet title="测试模型" onClose={w.closePicker}>
          <p className="an-sheet-note">账号 #{AN_NEW_ID} 支持的模型，默认优先 Sonnet。选一个立即重新测试。</p>
          <div className="an-choices">
            {anModels(d.platform).map(m => <AnChoice key={m} on={model === m} title={m} sub={m === anDefaultModel(d.platform) ? '默认' : null} onClick={pick(() => w.pickModel(m))} />)}
          </div>
        </Sheet>
      )}
      {w.browser && <AnBrowser w={w} />}
    </>
  );
}

/* ---------- ① 分步全屏（base） ---------- */

function AnRuler({ step, reach, locked, onJump }) {
  return (
    <div className={cx('an-ruler', locked && 'is-locked')} role="list" aria-label={`第 ${step + 1} 步，共 ${AN_STEPS.length} 步`}>
      {AN_STEPS.map((s, i) => (
        <button type="button" key={s.key} role="listitem" className={cx('an-tick', i < step && 'done', i === step && 'on', i > step && i <= reach && 'ahead')} disabled={locked || i === step || i > reach} onClick={() => onJump(i)}>
          <i /><span>{s.label}</span>
        </button>
      ))}
    </div>
  );
}

function AnHead({ step, d }) {
  return (
    <div className="an-head">
      <small className="num">第 {step + 1} 步 · 共 {AN_STEPS.length} 步</small>
      <h2>{anStepTitle(step, d)}</h2>
      <p>{anLead(step, d)}</p>
    </div>
  );
}

function AnSteps({ ctx, route }) {
  const w = useAnWizard(ctx, route);
  const { d, step } = w;
  const p = d.platform && anPlatform(d.platform);
  const t = anTypeOf(d);
  const later = i => setTimeout(() => w.go(i), 170);
  const pickPlatform = pid => w.pickPlatform(pid, () => later(anTypes(pid).length === 1 ? 2 : 1));
  const retry = () => { w.run.reset(); w.go(2); };
  const body = [
    () => (w.created ? <AnPlatformLocked p={p} /> : <AnPlatformList ctx={ctx} w={w} onPick={pickPlatform} />),
    () => (
      <AnSec title={p.name}>
        {anTypes(p.id).map(x => <AnTypeRow key={x.key} t={x} on={d.type === x.key} onClick={() => w.pickType(x.key, () => later(2))} />)}
      </AnSec>
    ),
    () => <AnCred ctx={ctx} w={w} />,
    () => <AnSetup ctx={ctx} w={w} />,
    () => <AnTest w={w} onEdit={w.go} onRetry={retry} />,
  ][step];
  // OAuth not finished yet: the card's own buttons are the only action; “下一步” appears once authorized.
  const oauthPending = step === 2 && t && t.flow === 'oauth' && !anCredOk(d);
  let bar = null;
  if ((step === 2 && !oauthPending) || step === 3 || (step === 0 && d.run.retry)) bar = <button type="button" className="an-cta" disabled={!anStepOk(d, step)} onClick={() => w.go(step + 1)}>下一步</button>;
  if (step === 4 && !w.started) bar = <button type="button" className="an-cta" onClick={() => w.submit()}>{d.run.retry ? (w.dirty ? '保存并重新测试' : '重新测试') : '创建并测试'}</button>;
  // A single-type platform skipped “方式” on the way in, so going back skips it too.
  const back = () => w.go(step === 2 && d.platform && anTypes(d.platform).length === 1 ? 0 : step - 1);
  let trailing = null;
  if (w.running) trailing = <GlassButton label="后台继续" onClick={w.run.background} />;
  else if ((step > 0 || d.run.retry) && !w.started) trailing = <GlassButton label="取消" onClick={w.cancel} />;
  return (
    <div className="screen an-root an-hide-tabs an-steps">
      <NavBar ctx={ctx} title="新建账号" subtitle={p ? `${p.name}${t ? ` · ${t.title}` : ''}` : ctx.site}
        leading={w.started ? <span className="nav-spacer" /> : <GlassButton icon="back" onClick={step === 0 ? w.cancel : back} />}
        trailing={trailing} />
      <AnRuler step={step} reach={anReach(d)} locked={w.started} onJump={w.go} />
      <div className={cx('scroll an-scroll', bar && 'has-bar')} key={step}>
        <div className={cx('an-pane', w.dir > 0 ? 'an-in-r' : 'an-in-l')}>
          <AnHead step={step} d={d} />
          {body()}
        </div>
      </div>
      {bar && <div className="an-bar">{bar}</div>}
      <AnOverlays w={w} />
    </div>
  );
}

/* ---------- ② 单页长表单 ---------- */

function AnPlatformMenu({ w, top, onClose }) {
  return (
    <div className="an-menu-layer" onClick={onClose}>
      <div className="an-menu" style={{ top, maxHeight: `calc(100% - ${top + 34}px)` }} onClick={e => e.stopPropagation()} role="menu">
        {AN_SHELVES.map(([k, label]) => (
          <div key={k} className="an-menu-group">
            <div className="an-menu-sec">{label}</div>
            {AN_PLATFORMS.filter(p => p.shelf === k).map(p => (
              <button type="button" key={p.id} role="menuitemradio" aria-checked={w.d.platform === p.id} className="an-mi" onClick={() => { w.pickPlatform(p.id); onClose(); }}>
                <span className="an-mi-check">{w.d.platform === p.id && <Icon name="check" size={15} weight={2.8} />}</span>
                <span className="an-mi-label">{p.name}<small>{anTypeSummary(p.id)}</small></span>
                <span className="an-mono">{p.mono}</span>
              </button>
            ))}
          </div>
        ))}
      </div>
    </div>
  );
}

// Same chrome as the shared Sheet, but the leading button and the backdrop act differently while the test runs
// (SwiftUI: .interactiveDismissDisabled(running) + a “后台继续” toolbar button).
function AnTestSheet({ title, running, onBackground, onClose, children }) {
  return (
    <div className="overlay overlay-dim sheet-overlay" onClick={running ? undefined : onClose}>
      <div className="sheet sheet-tall" onClick={e => e.stopPropagation()}>
        <div className="sheet-grabber" />
        <div className="sheet-bar">
          <button type="button" className="glass-btn glass-btn-text" onClick={running ? onBackground : onClose}><span>{running ? '后台继续' : '关闭'}</span></button>
          <div className="sheet-title">{title}</div>
          <span className="nav-spacer" />
        </div>
        <div className="sheet-body">{children}</div>
      </div>
    </div>
  );
}

function AnForm({ ctx, route }) {
  const w = useAnWizard(ctx, route);
  const { d } = w;
  const rootRef = useRef(null);
  const scrollRef = useRef(null);
  const [menuTop, setMenuTop] = useState(null);
  const [sheet, setSheet] = useState(d.run.phase !== 'idle');
  const p = d.platform && anPlatform(d.platform);
  const t = anTypeOf(d);
  const missing = anMissing(d);
  const ready = missing.length === 0;
  const r = d.run;
  const again = r.retry || r.phase === 'failed';
  // Retest without edits skips the save (PUT :id); the button says which one will happen.
  const cta = again ? (w.dirty ? '保存并重新测试' : '重新测试') : '创建并测试';
  // SwiftUI: ScrollViewReader.scrollTo(section id, anchor: .top). keys: first one present wins.
  const jump = (...keys) => {
    const box = scrollRef.current;
    const el = box && keys.map(k => box.querySelector(`[data-sec="${k}"]`)).find(Boolean);
    if (el) box.scrollTop = el.getBoundingClientRect().top - box.getBoundingClientRect().top + box.scrollTop - 6;
  };
  const later = (...keys) => setTimeout(() => jump(...keys), 60);
  const openMenu = e => {
    const rr = e.currentTarget.getBoundingClientRect();
    const root = rootRef.current.getBoundingClientRect();
    setMenuTop(Math.round(rr.bottom - root.top + 6));
  };
  // submit's callback: no argument = go (open the test sheet); 'groups' = the admin backed out of the mixed-channel dialog.
  const start = () => w.submit(where => (where ? later(where) : setSheet(true)));
  const retry = () => { w.run.reset(); setSheet(false); later('retry', 'cred'); };
  const editFrom = step => { setSheet(false); later(['platform', 'platform', 'cred', 'name'][step] || 'name'); };
  const fail = r.fail || (t && anFailReason(d));
  const held = r.held || 'paused';
  // #21 exists and has not passed: the banner says so for as long as the form is open (the sheet itself is closed).
  const unresolved = w.created && !sheet && r.phase !== 'passed';
  let dockText;
  if (r.phase === 'pauseFailed') dockText = <><b>停止调度没有确认</b><small>账号 #{AN_NEW_ID} 可能在接收请求</small></>;
  else if (!ready) {
    dockText = (
      <button type="button" className="an-dock-jump" onClick={() => jump(missing[0][1])} aria-label={`还差${missing.map(m => m[0]).join('、')}，跳到${missing[0][0]}`}>
        <small>还差</small><b>{missing.map(m => m[0]).join('、')}<Icon name="chevron" size={11} weight={2.8} /></b>
      </button>
    );
  } else if (again) dockText = w.dirty ? <><b>保存到账号 #{AN_NEW_ID}</b><small>测试通过才启用调度</small></> : <><b>账号 #{AN_NEW_ID} · {AN_HELD[held]}</b><small>没有改动，用原设置再测一次</small></>;
  else dockText = <><b>可以创建了</b><small>创建后立即停止调度，测试通过再启用</small></>;
  // Title line and dock count the same list (anMissing), so “还差 N 项” always matches the names in the dock.
  const progress = ready ? '必填已填齐' : `还差 ${missing.length} 项`;
  return (
    <div className="screen an-root an-hide-tabs an-form" ref={rootRef}>
      <NavBar ctx={ctx} title="新建账号" leading={<GlassButton label="取消" onClick={w.cancel} />}
        subtitle={w.created && r.phase !== 'passed' ? `${ctx.site} · #${AN_NEW_ID} 已创建 · ${r.phase === 'pauseFailed' ? '调度状态待核对' : AN_HELD[held]}` : `${ctx.site} · ${progress}`} />
      <div className="scroll an-scroll has-bar" ref={scrollRef}>
        {unresolved && (
          <div className="banner tone-critical an-banner" role="status">
            <Icon name="octagon" size={18} />
            <div className="banner-text">
              {r.phase === 'pauseFailed'
                ? <><b>停止调度没有确认 · 结果待核对</b><span>账号 #{AN_NEW_ID} 可能正在参与调度。</span></>
                : held === 'error'
                  ? <><b>测试未通过 · #{AN_NEW_ID} 已标为错误</b><span>{fail ? `${fail.human}。` : ''}已停止调度，不会接收请求；改好凭据后点“{cta}”，或者先保留、停用、删除。</span></>
                  : <><b>测试未通过 · 账号 #{AN_NEW_ID} 已创建</b><span>{fail ? `${fail.human}。` : ''}已停止调度；改好后点“{cta}”，或者先保留、停用、删除。</span></>}
            </div>
            <ActionButton small label="处理" onClick={r.phase === 'pauseFailed' ? () => setSheet(true) : w.resolve} />
          </div>
        )}
        <AnSec id="platform" title="平台与认证方式" meta={t ? '已填' : '必填'} foot={w.created ? `要换平台请删除后重建。${p.modes ? '账号类型' : '认证方式'}可以改，改了要重新${p.modes ? '填写凭据' : '授权或填写凭据'}。` : null}>
          {w.created ? (
            <div className="an-pick an-pick-platform is-locked">
              <span className="an-pick-label">平台</span>
              <span className="an-pick-value"><span className="an-mono">{p.mono}</span>{p.name}<small>已创建，不能更换</small></span>
              <span className="an-pick-chev"><AnGlyph name="lock" size={14} weight={2.2} /></span>
            </div>
          ) : (
            <button type="button" className="an-pick an-pick-platform" onClick={openMenu} aria-haspopup="menu">
              <span className="an-pick-label">平台</span>
              <span className="an-pick-value">{p ? <><span className="an-mono">{p.mono}</span>{p.name}</> : <span className="an-placeholder">选择平台</span>}</span>
              <span className="an-pick-chev"><Icon name="chevronDown" size={13} weight={2.6} /></span>
            </button>
          )}
          {p && anTypes(p.id).map(x => <AnTypeRow key={x.key} t={x} radio on={d.type === x.key} onClick={() => w.pickType(x.key)} />)}
        </AnSec>
        {t ? <AnCred ctx={ctx} w={w} /> : (
          <AnSec id="cred" title="凭据" meta="必填"><AnEmpty>{p ? `选好${p.modes ? '账号类型' : '认证方式'}后，在这里填写凭据` : '先选平台和认证方式'}</AnEmpty></AnSec>
        )}
        <AnSetup ctx={ctx} w={w} chips />
      </div>
      {/* SwiftUI: .safeAreaInset(edge: .bottom) { GlassEffectContainer { … } } */}
      <div className="an-dock glass">
        <span className="an-dock-need">{dockText}</span>
        {r.phase === 'pauseFailed'
          ? <button type="button" className="an-cta" onClick={() => setSheet(true)}>处理</button>
          : <button type="button" className="an-cta" disabled={!ready} onClick={start}>{cta}</button>}
      </div>
      {menuTop !== null && <AnPlatformMenu w={w} top={menuTop} onClose={() => setMenuTop(null)} />}
      {sheet && (
        <AnTestSheet title={r.retry ? (r.saved === false ? '重新测试' : '保存并重新测试') : '创建并测试'} running={w.running} onBackground={w.run.background}
          onClose={r.phase === 'passed' ? w.run.done : () => setSheet(false)}>
          <AnTest w={w} onEdit={editFrom} onRetry={retry} />
        </AnTestSheet>
      )}
      <AnOverlays w={w} />
    </div>
  );
}

/* ---------- ③ 卡片式分页 sheet ---------- */

function AnCards({ ctx, route }) {
  const w = useAnWizard(ctx, route);
  const { d, step } = w;
  const reach = anReach(d);
  const drag = useRef(null);
  const p = d.platform && anPlatform(d.platform);
  const t = anTypeOf(d);
  const r = d.run;
  const retry = () => { w.run.reset(); w.go(2); };
  const canNext = step < 4 && anStepOk(d, step);
  const down = e => { drag.current = e.clientX; };
  const up = e => {
    if (drag.current === null || w.started) { drag.current = null; return; }
    const dx = e.clientX - drag.current;
    drag.current = null;
    if (dx < -50 && canNext) w.go(step + 1);
    if (dx > 50 && step > 0) w.go(step - 1);
  };
  const body = i => [
    () => (w.created ? <AnPlatformLocked p={p} /> : <AnPlatformGrid ctx={ctx} w={w} />),
    () => <AnTypeCards w={w} />,
    () => <AnCred ctx={ctx} w={w} />,
    () => <AnSetup ctx={ctx} w={w} />,
    () => <AnTest w={w} onEdit={w.go} onRetry={retry} />,
  ][i]();
  const chip = i => {
    if (i === 0 && p) return p.name;
    if (i === 1 && t) return t.title;
    if (i === 2 && anCredOk(d)) return t.flow === 'oauth' ? '已授权' : '已填';
    if (i === 3 && anSetupOk(d)) return d.name.trim();
    return null;
  };
  let primary;
  if (step < 4) primary = <button type="button" className="an-btn primary" disabled={!canNext} onClick={() => w.go(step + 1)}>{step === 3 ? '下一步：检查' : '下一步'}</button>;
  else if (!w.started) primary = <button type="button" className="an-btn primary" onClick={() => w.submit()}>{r.retry ? (w.dirty ? '保存并重新测试' : '重新测试') : '创建并测试'}</button>;
  let lead = '取消';
  if (w.running) lead = '后台继续';
  else if (r.phase === 'passed') lead = '关闭';
  return (
    <div className="screen an-root an-cards">
      <Slot slot="accounts" ctx={ctx} />
      <div className="overlay overlay-dim an-cards-ov">
        <div className="an-sheet" role="dialog" aria-label="新建账号">
          <div className="sheet-grabber" />
          <div className="an-sheet-bar">
            <button type="button" className="glass-btn glass-btn-text" onClick={w.cancel}><span>{lead}</span></button>
            <div className="an-sheet-title"><b>新建账号</b><small>{p ? `${p.name}${t ? ` · ${t.title}` : ''}` : ctx.site}</small></div>
            <span className="an-sheet-count num">{step + 1}<i>/{AN_STEPS.length}</i></span>
          </div>
          <div className="an-deck" onPointerDown={down} onPointerUp={up}>
            <div className="an-track" style={{ '--i': step }}>
              {AN_STEPS.map((s, i) => {
                const locked = i > reach;
                const c = chip(i);
                return (
                  <article key={s.key} className={cx('an-card', i === step && 'on', locked && 'locked')} aria-hidden={i !== step}
                    onClick={i !== step && !locked && !w.started ? () => w.go(i) : undefined}>
                    <header className="an-card-head">
                      <span className="an-card-no num">{String(i + 1).padStart(2, '0')}</span>
                      <b>{anStepTitle(i, d)}</b>
                      {c && i !== step && <span className="an-card-chip"><Icon name="check" size={11} weight={3.2} />{c}</span>}
                    </header>
                    <div className="an-card-body">
                      {locked ? null : Math.abs(i - step) <= 1 ? <>{i === step && <p className="an-card-lead">{anLead(i, d)}</p>}{body(i)}</> : null}
                    </div>
                    {locked && <span className="an-card-lockedge" aria-label={`先完成「${anStepTitle(i - 1, d)}」`}><AnGlyph name="lock" size={16} weight={2.2} /></span>}
                  </article>
                );
              })}
            </div>
          </div>
          <div className="an-dots" aria-hidden="true">{AN_STEPS.map((s, i) => <i key={s.key} className={cx(i === step && 'on', i < step && 'done')} />)}</div>
          {(primary || step > 0) && !w.started && (
            <div className="an-sheet-foot">
              <button type="button" className="an-btn" disabled={step === 0} onClick={() => w.go(step - 1)}>上一步</button>
              {primary}
            </div>
          )}
          {w.started && <div className="an-sheet-foot is-quiet" />}
        </div>
      </div>
      <AnOverlays w={w} />
    </div>
  );
}

mvRegister('screen:accountNew', 'base', AnSteps);
mvRegister('screen:accountNew', 'steps', AnSteps);
mvRegister('screen:accountNew', 'form', AnForm);
mvRegister('screen:accountNew', 'cards', AnCards);
