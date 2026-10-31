/* Shared demo data, formatters and clock for the three style previews. All values are fictional. */

const DEMO_LOADED_AT = Date.now();
// The demo's day: every page reads “10月16日 周五”, proxies and subscriptions count days from it (daysUntil), whatever day the
// preview is opened on.
const DEMO_TODAY = '2026-10-16';
// The frame's status bar reads 9:41; keep every in-app time on the same fake clock — 2026-10-16 09:41 local time.
const DEMO_CLOCK_BASE = (() => { const [y, m, d] = DEMO_TODAY.split('-').map(Number); return new Date(y, m - 1, d, 9, 41, 0, 0).getTime(); })();

function useDemoClock() {
  const [, tick] = React.useState(0);
  React.useEffect(() => {
    const id = setInterval(() => tick(x => x + 1), 1000);
    return () => clearInterval(id);
  }, []);
  const elapsed = (Date.now() - DEMO_LOADED_AT) / 1000;
  return { elapsed, now: DEMO_CLOCK_BASE + elapsed * 1000 };
}

const fmt = {
  money(value, opts = {}) {
    if (value === null || value === undefined) return '—';
    if (opts.small && value > 0 && value < 0.01) return '< $0.01';
    const digits = opts.digits ?? 2;
    const body = Math.abs(value).toLocaleString('en-US', { minimumFractionDigits: digits, maximumFractionDigits: digits });
    const sign = value < 0 ? '−' : (opts.sign && value > 0 ? '+' : '');
    return `${sign}$${body}`;
  },
  compact(value) {
    if (value === null || value === undefined) return '—';
    const units = [[1e9, 'B'], [1e6, 'M'], [1e3, 'K']];
    for (const [size, unit] of units) {
      if (value >= size) return `${(value / size).toFixed(1).replace(/\.0$/, '')}${unit}`;
    }
    return String(value);
  },
  grouped(value) { return value === null || value === undefined ? '—' : value.toLocaleString('en-US'); },
  countdown(seconds) {
    const s = Math.max(0, Math.round(seconds));
    const h = Math.floor(s / 3600), m = Math.floor((s % 3600) / 60), r = s % 60;
    const pad = n => String(n).padStart(2, '0');
    return h ? `${h}:${pad(m)}:${pad(r)}` : `${m}:${pad(r)}`;
  },
  clock(ms) {
    const d = new Date(ms);
    return `${String(d.getHours()).padStart(2, '0')}:${String(d.getMinutes()).padStart(2, '0')}`;
  },
  minutesLeft(seconds) {
    const m = Math.max(1, Math.ceil(seconds / 60));
    return m >= 60 ? `${Math.floor(m / 60)} 小时 ${m % 60} 分钟` : `${m} 分钟`;
  },
};

// Status vocabulary (aligned with the Web admin terms): value -> label, tone, symbol, whether it auto-recovers.
const STATE_META = {
  normal: { label: '正常', tone: 'ok', icon: 'dot', timed: false },
  rate_limited: { label: '限流中', tone: 'caution', icon: 'hourglass', timed: true },
  overloaded: { label: '过载中', tone: 'critical', icon: 'flame', timed: true },
  temp_unsched: { label: '临时不可调度', tone: 'caution', icon: 'clockAlert', timed: true },
  error: { label: '错误', tone: 'critical', icon: 'octagon', timed: false },
  paused: { label: '暂停', tone: 'neutral', icon: 'pause', timed: false },
  inactive: { label: '停用', tone: 'neutral', icon: 'minus', timed: false },
};
const NEEDS_ACTION = ['error', 'overloaded', 'rate_limited', 'temp_unsched'];
const STATE_ORDER = ['error', 'overloaded', 'rate_limited', 'temp_unsched', 'paused', 'inactive', 'normal'];

/* Demo bookkeeping (keep these true when editing numbers):
   - Σ accounts.todayCost = today.actual; Σ todayAccountCost = today.cost; Σ todayStd = today.standard; Σ todayReq = today.requests;
     Σ todayTokens = today.tokens. Per platform the figures equal v-analytics' model table (claude-* = Anthropic accounts, gpt-* = OpenAI …).
   - groups[].usage.today is counted by the API key's group (groups/usage-summary): Σ = today.actual, and each group's today ≤ the sum of
     its members' today. Membership lives only in accounts[].groups (group names); a group only holds accounts of its own platform.
   - 实际 = 标准 × 分组倍率 (account_usage_service: standard = total_cost, actual = total_cost × rate_multiplier), so every group's
     usage.today = todayStats.standard × rate and each account's todayStd = its actual ÷ the rate of the groups it served.
   - groups[].capacity follows groups/capacity-summary: only schedulable members count (status active, switch on, not rate-limited /
     overloaded / temp-unschedulable), and an account in two groups adds the same figures to both (高级组 = Claude Code 组 = #1 + #2).
   - today.rpm / today.tpm = ops/dashboard/throughput-trend, the last five 1-minute buckets ÷ 5 (request_count incl. errors; token_consumed
     incl. cache tokens), the same source as 统计分析 · RPM / TPM 趋势 (review 2026-10-18; dashboard/stats' tpm leaves cache out). A
     5-minute figure, not a day figure — so it never sits in a “00:00 起” block (the home writes no window suffix). 46 is the morning peak (the day's average is ≈ 31 =
     requests ÷ 581 minutes); server.qps ≈ today.rpm / 60.
   - Σ users.today = today.actual (1284.50), each user's keys add up to the user's today, and each group's keys add up to its
     usage.today (keys are counted by their own group, like groups/usage-summary).
   - schedulable is the backend switch (POST accounts/:id/schedulable), separate from the runtime state. 'paused' is the display state
     of a normal account whose switch is off; an errored account has it off (SetError stops scheduling). */
const DEMO = {
  site: { name: '主站', initial: '主' },
  sites: [{ name: '主站', host: 'api.example.com' }, { name: '备用站', host: 'relay.example.net' }],
  // The signed-in administrator (v-user-edit marks this user as “你”: cannot demote, disable or delete themselves).
  me: { id: 5, name: '陈思远', email: 'sy.chen@example.com', role: 'admin' },
  /* proxy = proxy name (DEMO.proxies; null = 直连 / 无代理). rpm = base_rpm used this minute / limit, sessions = active sticky sessions /
     max_sessions: both live in extra and are Anthropic OAuth only (Web EditAccountModal), so other accounts have none. The upstream-error
     count of the last 24 h (errors24h) is derived from DEMO.logs below with the usage page's own rule — never write it by hand. */
  accounts: [
    { id: 3, name: 'Claude-官方-03', platform: 'Anthropic', type: 'OAuth', groups: ['高级组'], state: 'rate_limited', schedulable: true, resetIn: 277, cause: '上游 429', conc: [0, 4], rpm: [1, 60], sessions: [0, 3], window5h: 1.0, todayCost: 192.62, todayStd: 240.78, todayAccountCost: 76.42, todayReq: 2302, todayTokens: 14.22e6, priority: 1, proxy: 'hk-02', expires: '2026-12-01',
      modelLimits: [{ model: 'claude-opus-4', resetIn: 720 }, { model: 'claude-sonnet-4-5', resetIn: 300 }] },
    { id: 7, name: 'OpenAI-备用-A', platform: 'OpenAI', type: 'API Key', groups: ['标准组', '企业专线'], state: 'error', schedulable: false, error: '401 凭据已失效（invalid_api_key）', errorAgo: '1 分钟前', conc: [0, 4], todayCost: 0, todayStd: 0, todayAccountCost: 0, todayReq: 0, todayTokens: 0, priority: 2, proxy: 'sg-01' },
    { id: 11, name: 'GLM-直连-01', platform: '智谱 GLM', type: 'API Key', groups: ['GLM 组'], state: 'overloaded', schedulable: true, resetIn: 72, cause: '上游 529', conc: [0, 6], todayCost: 18.4, todayStd: 23.0, todayAccountCost: 8.38, todayReq: 290, todayTokens: 1.4e6, priority: 3, proxy: null },
    // temp_unschedulable_rules match one upstream error (error_code + keywords) and pause for duration_minutes: 09:19 + 45 = 10:04.
    // causes stay short — “上游 <code>”, plus the rule as Web's temp-unschedulable detail names it (“规则 #1”) — so the row's third
    // line keeps “… · 10:04 恢复” at 393 pt, even behind the “已停止调度 ·” mark.
    { id: 12, name: 'MiniMax-01', platform: 'MiniMax', type: 'API Key', groups: ['MiniMax 组'], state: 'temp_unsched', schedulable: true, resetIn: 1380, cause: '上游 529 · 规则 #1', conc: [0, 4], todayCost: 0, todayStd: 0, todayAccountCost: 0, todayReq: 0, todayTokens: 0, priority: 3, proxy: null },
    { id: 5, name: 'Gemini-测试-B', platform: 'Gemini', type: 'API Key', groups: ['测试组'], state: 'paused', schedulable: false, conc: [0, 2], todayCost: 10.8, todayStd: 18.0, todayAccountCost: 4.8, todayReq: 152, todayTokens: 0.9e6, priority: 5, proxy: 'jp-tokyo-1' },
    { id: 1, name: 'Claude-官方-01', platform: 'Anthropic', type: 'OAuth', groups: ['高级组', 'Claude Code 组'], state: 'normal', schedulable: true, conc: [2, 4], rpm: [14, 60], sessions: [2, 3], todayCost: 409.38, todayStd: 511.73, todayAccountCost: 162.42, todayReq: 4418, todayTokens: 27.27e6, priority: 1, proxy: 'hk-02' },
    { id: 2, name: 'Claude-官方-02', platform: 'Anthropic', type: 'OAuth', groups: ['高级组', 'Claude Code 组'], state: 'normal', schedulable: true, conc: [3, 4], rpm: [12, 60], sessions: [3, 3], todayCost: 384.05, todayStd: 480.06, todayAccountCost: 152.36, todayReq: 4050, todayTokens: 25.01e6, priority: 1, proxy: 'hk-02' },
    { id: 4, name: 'OpenAI-主力-01', platform: 'OpenAI', type: 'API Key', groups: ['标准组'], state: 'normal', schedulable: true, conc: [2, 8], dayQuota: [96.3, 150], todayCost: 203.5, todayStd: 254.38, todayAccountCost: 82.4, todayReq: 5500, todayTokens: 20.7e6, priority: 1, proxy: 'sg-01' },
    { id: 8, name: 'DeepSeek-01', platform: 'DeepSeek', type: 'API Key', groups: ['默认组'], state: 'normal', schedulable: true, conc: [0, 8], todayCost: 38.6, todayStd: 48.25, todayAccountCost: 14.1, todayReq: 980, todayTokens: 4.6e6, priority: 2, proxy: 'hk-01' },
    { id: 9, name: 'Kimi-01', platform: 'Kimi', type: 'API Key', groups: ['Kimi 组'], state: 'normal', schedulable: true, conc: [1, 4], todayCost: 27.15, todayStd: 33.94, todayAccountCost: 11.2, todayReq: 512, todayTokens: 2.3e6, priority: 2, proxy: 'hk-01' },
    { id: 10, name: 'Grok-旧-01', platform: 'Grok', type: 'API Key', groups: [], state: 'inactive', schedulable: true, conc: [0, 2], todayCost: 0, todayStd: 0, todayAccountCost: 0, todayReq: 0, todayTokens: 0, priority: 9, proxy: null },
  ],
  /* admin/groups (dto.AdminGroup) + groups/usage-summary + groups/capacity-summary. One platform per group (scheduling picks accounts by
     group + platform). Field ↔ backend: rate = rate_multiplier, exclusive = is_exclusive, status = active | inactive,
     subscriptionType = subscription_type ('standard' 标准（余额）| 'subscription' 订阅（配额）), rpmLimit = rpm_limit (0 = 不限),
     limits = daily / weekly / monthly_limit_usd (subscription groups only), claudeCodeOnly = claude_code_only,
     fallbackGroupId = fallback_group_id, usage = today_cost / yesterday_cost / total_cost (actual cost by the key's group),
     todayStats = the same day from dashboard group stats (requests, tokens, account cost, standard cost),
     capacity = concurrency / sessions / rpm [used, max] of the schedulable members (null for a stopped group; sessions / rpm null when
     no member sets max_sessions / base_rpm — the backend's max is 0 then),
     apiKeys = keys bound to the group, subscriptions = active subscriptions (subscription groups). */
  groups: [
    { id: 1, name: '高级组', platform: 'Anthropic', status: 'active', exclusive: false, subscriptionType: 'standard', rate: 0.8, rpmLimit: 0, limits: null, claudeCodeOnly: false, fallbackGroupId: null, sortOrder: 1,
      usage: { today: 933.3, yesterday: 2985.6, total: 186420.55 }, todayStats: { requests: 10194, tokens: 62.94e6, cost: 370.27, standard: 1166.63 },
      capacity: { conc: [5, 8], sessions: [5, 6], rpm: [26, 120] }, apiKeys: 38, subscriptions: null },
    { id: 2, name: '标准组', platform: 'OpenAI', status: 'active', exclusive: false, subscriptionType: 'standard', rate: 0.8, rpmLimit: 600, limits: null, claudeCodeOnly: false, fallbackGroupId: null, sortOrder: 2,
      usage: { today: 203.5, yesterday: 498.2, total: 41310.08 }, todayStats: { requests: 5500, tokens: 20.7e6, cost: 82.4, standard: 254.38 },
      capacity: { conc: [2, 8], sessions: null, rpm: null }, apiKeys: 64, subscriptions: null },
    { id: 3, name: '默认组', platform: 'DeepSeek', status: 'active', exclusive: false, subscriptionType: 'standard', rate: 0.8, rpmLimit: 0, limits: null, claudeCodeOnly: false, fallbackGroupId: null, sortOrder: 3,
      usage: { today: 38.6, yesterday: 121.3, total: 9204.33 }, todayStats: { requests: 980, tokens: 4.6e6, cost: 14.1, standard: 48.25 },
      capacity: { conc: [0, 8], sessions: null, rpm: null }, apiKeys: 21, subscriptions: null },
    { id: 4, name: '企业专线', platform: 'OpenAI', status: 'active', exclusive: true, subscriptionType: 'subscription', rate: 1.2, rpmLimit: 120, limits: { day: 20, week: 100, month: 300 }, claudeCodeOnly: false, fallbackGroupId: null, sortOrder: 4,
      usage: { today: 0, yesterday: 312.5, total: 22386.2 }, todayStats: { requests: 0, tokens: 0, cost: 0, standard: 0 },
      capacity: { conc: [0, 0], sessions: null, rpm: null }, apiKeys: 6, subscriptions: 12 },
    // The demo's exclusive standard group (is_exclusive, subscription_type standard): the only kind replace-group accepts as a target and
    // the only kind a key's group change grants automatically (auto_granted_group_access). 企业专线 is exclusive too, but a subscription group.
    { id: 5, name: 'Claude Code 组', platform: 'Anthropic', status: 'active', exclusive: true, subscriptionType: 'standard', rate: 0.8, rpmLimit: 60, limits: null, claudeCodeOnly: true, fallbackGroupId: 1, sortOrder: 5,
      usage: { today: 52.75, yesterday: 171.4, total: 6630.4 }, todayStats: { requests: 576, tokens: 3.56e6, cost: 20.93, standard: 65.94 },
      capacity: { conc: [5, 8], sessions: [5, 6], rpm: [26, 120] }, apiKeys: 14, subscriptions: null },
    { id: 6, name: '测试组', platform: 'Gemini', status: 'inactive', exclusive: false, subscriptionType: 'standard', rate: 0.6, rpmLimit: 0, limits: null, claudeCodeOnly: false, fallbackGroupId: null, sortOrder: 6,
      usage: { today: 10.8, yesterday: 20.5, total: 912.6 }, todayStats: { requests: 152, tokens: 0.9e6, cost: 4.8, standard: 18.0 },
      capacity: null, apiKeys: 3, subscriptions: null },
    { id: 7, name: 'GLM 组', platform: '智谱 GLM', status: 'active', exclusive: false, subscriptionType: 'standard', rate: 0.8, rpmLimit: 0, limits: null, claudeCodeOnly: false, fallbackGroupId: null, sortOrder: 7,
      usage: { today: 18.4, yesterday: 38.7, total: 1288.1 }, todayStats: { requests: 290, tokens: 1.4e6, cost: 8.38, standard: 23.0 },
      capacity: { conc: [0, 0], sessions: null, rpm: null }, apiKeys: 9, subscriptions: null },
    { id: 8, name: 'Kimi 组', platform: 'Kimi', status: 'active', exclusive: false, subscriptionType: 'standard', rate: 0.8, rpmLimit: 0, limits: null, claudeCodeOnly: false, fallbackGroupId: null, sortOrder: 8,
      usage: { today: 27.15, yesterday: 64.8, total: 2140.6 }, todayStats: { requests: 512, tokens: 2.3e6, cost: 11.2, standard: 33.94 },
      capacity: { conc: [1, 4], sessions: null, rpm: null }, apiKeys: 7, subscriptions: null },
    { id: 9, name: 'MiniMax 组', platform: 'MiniMax', status: 'active', exclusive: false, subscriptionType: 'standard', rate: 0.6, rpmLimit: 0, limits: null, claudeCodeOnly: false, fallbackGroupId: null, sortOrder: 9,
      usage: { today: 0, yesterday: 0, total: 386.25 }, todayStats: { requests: 0, tokens: 0, cost: 0, standard: 0 },
      capacity: { conc: [0, 0], sessions: null, rpm: null }, apiKeys: 2, subscriptions: null },
    // No account yet: the same-platform choice for a new Antigravity account. Picking 高级组 for one instead returns the backend's
    // mixed-channel 409 (Anthropic and Antigravity accounts in one group, admin_account.go checkMixedChannelRisk).
    { id: 10, name: 'Antigravity 组', platform: 'Antigravity', status: 'active', exclusive: false, subscriptionType: 'standard', rate: 1.0, rpmLimit: 0, limits: null, claudeCodeOnly: false, fallbackGroupId: null, sortOrder: 10,
      usage: { today: 0, yesterday: 0, total: 0 }, todayStats: { requests: 0, tokens: 0, cost: 0, standard: 0 },
      capacity: { conc: [0, 0], sessions: null, rpm: null }, apiKeys: 0, subscriptions: null },
  ],
  // errorsSla = ops error_count_sla since 00:00 (v-analytics' error distribution: 317); the day's SLA error rate = errorsSla ÷ (requests + errorsSla).
  // rpm / tpm = throughput-trend's last five 1-minute buckets ÷ 5 (TPM incl. cache tokens; same source as 统计分析 RPM / TPM 趋势), the only live figures in here.
  today: { actual: 1284.5, cost: 512.08, standard: 1610.14, requests: 18204, tokens: 96.4e6, rpm: 46, tpm: 0.24e6, errorsSla: 317 },
  hourlyToday: [120, 112, 96, 84, 79, 88, 110, 152, 214, 229],
  hourlyYesterday: [118, 104, 90, 80, 72, 80, 100, 140, 190, 215, 236, 248, 252, 240, 236, 244, 250, 238, 226, 210, 190, 172, 150, 132],
  run: { health: 94, errorRate: 0.8, errorTrend: [0.6, 0.7, 0.5, 0.9, 1.4, 1.1, 0.8, 0.7, 0.8], r429: 12, r529: 3 },
  /* ops alert-events (OpsAlertEvent) joined with its rule (OpsAlertRule). status firing / resolved / manual_resolved (no "ack");
     actions = 手动解决、静默…. Field ↔ backend: level = severity, title, name = rule name, metric = metric_value and threshold =
     threshold_value (formatted with the rule's metric_type unit), op = rule operator, window = rule window_minutes (null = none),
     firedAt = fired_at (today: HH:MM; earlier days carry the day), resolvedAt = resolved_at, group / platform = dimensions,
     metricType = the rule's metric_type — one of the 16 the backend evaluates (ops_alerts_handler.go: success_rate, error_rate,
     upstream_error_rate, cpu_usage_percent, memory_usage_percent, concurrency_queue_depth, group_available_accounts,
     group_available_ratio, group_rate_limit_ratio, account_rate_limited_count, account_error_count, account_error_ratio,
     account_temp_unscheduled_count, overload_account_count, proxy_expired_count, proxy_expiring_soon_count). There is no latency /
     first-token metric: first-token figures live only in channel monitoring, which never raises an ops alert event.
     rule / since / scope / detail are display lines built from those fields. DEMO.alert (below) is alerts[0], the firing #41.
     Handling on a phone (手动解决, 静默到) lives in ctx (ctx.alertStatus / resolveAlert / silenceAlert), never in DEMO. */
  alerts: [
    { id: 41, level: 'P1', status: 'firing', metricType: 'error_rate', title: '标准组错误率 5.2%', name: '标准组错误率', metric: '5.2%', op: '>', threshold: '5%', window: '5 分钟',
      firedAt: '09:29', resolvedAt: null, group: '标准组', rule: '错误率 > 5%（5 分钟）', since: '12 分钟前', scope: '分组 · 标准组', detail: '阈值 5% · 12 分钟前触发' },
    { id: 40, level: 'P2', status: 'firing', metricType: 'upstream_error_rate', title: 'Gemini 上游错误率 6.1%', name: 'Gemini 上游错误率', metric: '6.1%', op: '>', threshold: '5%', window: '10 分钟',
      firedAt: '09:15', resolvedAt: null, platform: 'Gemini', rule: '上游错误率 > 5%（10 分钟）', since: '26 分钟前', scope: '平台 · Gemini', detail: '阈值 5% · 26 分钟前触发' },
    { id: 37, level: 'P1', status: 'resolved', metricType: 'memory_usage_percent', title: '内存使用率 87%', name: '内存使用率', metric: '87%', op: '>', threshold: '85%', window: '5 分钟',
      firedAt: '08:19', resolvedAt: '08:41', rule: '内存 > 85%（5 分钟）', since: '1 小时前恢复', scope: '服务器', detail: '阈值 85% · 1 小时前恢复' },
    { id: 35, level: 'P2', status: 'manual_resolved', metricType: 'group_available_ratio', title: '高级组可用账号 50%', name: '高级组可用比例', metric: '50%', op: '<', threshold: '60%', window: null,
      firedAt: '昨天 21:52', resolvedAt: '昨天 22:10', group: '高级组', rule: '可用比例 < 60%', since: '昨天 22:10 · 由 admin 手动解决', scope: '分组 · 高级组', detail: '阈值 60% · 昨天 22:10 手动解决' },
  ],
  // ops/dashboard/overview.system_metrics + concurrency + job_heartbeats + */health. Admin only; hidden for vendor and end users.
  server: {
    cpu: 38, mem: 61, qps: 0.77, sla: 99.2,
    // Σ accounts' conc (in use / limit); the queue is requests waiting for a free slot.
    concurrency: { used: 8, cap: 50, queue: 0 },
    cpuTrend: [22, 25, 31, 28, 35, 41, 38, 36, 40, 38],
    memTrend: [58, 58, 59, 60, 60, 61, 61, 62, 61, 61],
    /* job_heartbeats: only the ops jobs write one — job = job_name, last = last_success_at, ok = no last_error after it, note = last_error.
       指标采集 runs every minute, so 4 minutes without a success is the one that needs a look. */
    jobs: [
      { job: 'ops_metrics_collector', name: '指标采集', last: '4 分钟前', ok: false, note: '最近一次失败：redis: connection pool timeout' },
      { job: 'ops_alert_evaluator', name: '告警评估', last: '31 秒前', ok: true },
      { job: 'ops_preaggregation_hourly', name: '预聚合（小时）', last: '41 分钟前', ok: true },
      { job: 'ops_preaggregation_daily', name: '预聚合（天）', last: '今天 00:05', ok: true },
      { job: 'ops_cleanup', name: '清理', last: '今天 03:00', ok: true },
      { job: 'ops_scheduled_reports', name: '定时报告', last: '今天 09:00', ok: true },
    ],
    ingest: { ok: true, lag: '2 秒' },
    rejections: 3,
  },
  pendingOp: { user: '周婷', amount: 50, ago: '2 小时前' },
  channels: [
    { name: 'Claude', provider: 'Anthropic', state: 'ok', avail: 99.6, ttft: '1.4s', strip: 'gggggggggggggggggg' },
    { name: 'GPT', provider: 'OpenAI', state: 'ok', avail: 99.9, ttft: '0.9s', strip: 'gggggggggggggggggg' },
    { name: 'Gemini', provider: 'Google', state: 'caution', avail: 97.1, ttft: '8.6s', strip: 'ggggggggggggcwcwcc' },
    { name: 'DeepSeek', provider: 'DeepSeek', state: 'ok', avail: 99.2, ttft: '1.1s', strip: 'gggggggcgggggggggg' },
    { name: 'Kimi', provider: 'Moonshot', state: 'critical', avail: 68.0, ttft: '—', strip: 'gggggggggcwrrrrrrr', note: '错误率 31%' },
    { name: 'Grok', provider: 'xAI', state: 'neutral', avail: null, ttft: '—', strip: '..................', note: '无样本' },
  ],
  // group = the group of the user's main key (users have no single group in the backend; keys carry group_id).
  // conc = users.concurrency: always set (new users get the default_concurrency setting, 5); 陈思远 redeemed F6B2 (+2 并发).
  // keys = derived below from DEMO.keys (GET admin/users/:id/api-keys).
  /* ledger = admin/users/:id/balance-history: the redeem codes the user used — admin adjustments are codes too (type admin_balance) —
     newest first. kind = Web's getItemTitle wording (余额充值（管理员）/ 余额扣除（管理员）/ 余额充值（兑换）/ 并发增加（兑换）/ 订阅已分配),
     amount = signed dollars or null for concurrency / subscription items, which carry display instead (Web formatValue: “+2”, “7d - 分组”),
     when, note = the code's notes, code = the code's first 8 characters (Web prints code.slice(0, 8) under redeemed items; the same codes
     as v-modules' redeem list). There is no "balance after"; total_recharged = Σ positive money items (王小明 $60).
     low marks a balance under the low-balance line (balance_notify_threshold, fixed; the demo uses $10). The rule is the balance only:
     Mira Labs ($92.40, $156.80 today) and 北辰数据 ($45.20, $48.69 today) hold less than a day's spend but stay above the line.
     #21–#26 are the big customers: they carry most of today's spend (Σ users.today = today.actual). */
  users: [
    { id: 1, name: '王小明', email: 'xm.wang@example.com', balance: 12.5, today: 3.24, month: 86.1, status: 'active', group: '高级组', conc: 2,
      ledger: [
        { kind: '余额充值（兑换）', amount: 10, when: '10/16 09:20', note: '社群活动 · 第 3 批', code: 'e81c6a0f' },
        { kind: '余额充值（管理员）', amount: 50, when: '10/12 14:02', note: '月初预充' },
        { kind: '余额扣除（管理员）', amount: -20, when: '10/08 09:15', note: '退回未用额度' },
      ] },
    { id: 2, name: '李娜', email: 'na.li@example.com', balance: 3.2, today: 1.02, status: 'active', low: true, group: '标准组', conc: 5 },
    { id: 3, name: 'Studio-K 团队', email: 'ops@studio-k.example', balance: 1020, today: 64.3, status: 'active', group: '高级组', conc: 20,
      ledger: [{ kind: '余额充值（兑换）', amount: 50, when: '10/15 21:06', note: '客服补偿 · 工单 #8812', code: '3c0a7f91' }] },
    { id: 4, name: '周婷', email: 'ting.z@example.com', balance: 56.3, today: 0.84, status: 'active', pending: true, group: '标准组', conc: 5 },
    { id: 5, name: '陈思远', email: 'sy.chen@example.com', balance: 248, today: 12.6, status: 'active', group: '标准组', role: 'admin', conc: 7,
      ledger: [{ kind: '并发增加（兑换）', amount: null, display: '+2 并发', when: '10/14 16:20', code: 'f6b2c849' }] },
    { id: 6, name: '赵磊', email: 'lei.zhao@example.com', balance: 0, today: 0, status: 'disabled', group: '默认组', conc: 5 },
    { id: 7, name: '孙浩', email: 'hao.sun@example.com', balance: 8.9, today: 2.1, status: 'active', low: true, group: '默认组', conc: 5 },
    { id: 8, name: '林一', email: 'yi.lin@example.com', balance: 75, today: 4.4, status: 'active', group: 'Claude Code 组', conc: 5,
      ledger: [{ kind: '订阅已分配', amount: null, display: '企业专线 · 7 天', when: '10/09 13:12', code: '4e7c0b95' }] },
    { id: 21, name: 'Nova 工作室', email: 'billing@nova.example', balance: 2310, today: 402.1, status: 'active', group: '高级组', conc: 20 },
    { id: 22, name: 'Atlas 科技', email: 'api@atlas.example', balance: 860.5, today: 289.4, status: 'active', group: '高级组', conc: 20 },
    { id: 23, name: '深蓝 AI', email: 'dev@shenlan.example', balance: 1475, today: 201.35, status: 'active', group: '高级组', conc: 20 },
    { id: 24, name: 'Mira Labs', email: 'team@mira.example', balance: 92.4, today: 156.8, status: 'active', group: '标准组', conc: 20 },
    { id: 25, name: 'Pixel 工坊', email: 'hi@pixel.example', balance: 310, today: 97.66, status: 'active', group: '标准组', conc: 20 },
    { id: 26, name: '北辰数据', email: 'ops@beichen.example', balance: 45.2, today: 48.69, status: 'active', group: '默认组', conc: 20 },
  ],
  /* API keys (dto.APIKey + owner): the one list every page reads — users[].keys, the groups' key pages, request details and analytics.
     id, userId, groupId (group_id), name, masked (key, shown masked), status active | disabled | quota_exhausted | expired,
     quota (0 = 不限) / quotaUsed (only grows while quota > 0: gateway_usage_billing.go shouldDeductAPIKeyQuota, so unlimited keys have
     none), today = today_actual_cost from dashboard/api-keys-usage, last = last_used_at (agrees with DEMO.logs: a key used inside the
     log window 09:19–09:41 has its log there; the others were last used before it). Each user's keys add up to the user's today and each
     group's keys add up to its usage.today (groups[].apiKeys is the group's total; the rest of its keys spent nothing today). */
  keys: [
    { id: 4120, userId: 3, groupId: 1, name: '生产', masked: 'sk-…Kp21', status: 'active', quota: 0, today: 64.3, last: '刚刚' },
    { id: 4113, userId: 5, groupId: 1, name: '自用', masked: 'sk-…Q8vd', status: 'active', quota: 0, today: 1.38, last: '6 分钟前' },
    { id: 4108, userId: 2, groupId: 1, name: 'Claude', masked: 'sk-…r7Tm', status: 'active', quota: 20, quotaUsed: 8.45, today: 0.71, last: '8 分钟前' },
    { id: 4102, userId: 7, groupId: 1, name: '测试', masked: 'sk-…H2pc', status: 'active', quota: 5, quotaUsed: 4.1, today: 0.6, last: '11 分钟前' },
    { id: 4087, userId: 1, groupId: 1, name: '默认', masked: 'sk-…a1F3', status: 'active', quota: 0, today: 2.8, last: '刚刚' },
    { id: 3961, userId: 6, groupId: 1, name: '旧集成', masked: 'sk-…7Lw0', status: 'expired', quota: 0, today: 0, last: '09/29 18:02' },
    { id: 4111, userId: 5, groupId: 2, name: '默认', masked: 'sk-…Vt8b', status: 'active', quota: 0, today: 0.42, last: '1 分钟前' },
    { id: 4096, userId: 4, groupId: 2, name: '默认', masked: 'sk-…Pw3n', status: 'active', quota: 0, today: 0.84, last: '17 分钟前' },
    { id: 4090, userId: 2, groupId: 2, name: '默认', masked: 'sk-…Lm4e', status: 'active', quota: 0, today: 0.31, last: '1 分钟前' },
    { id: 4074, userId: 7, groupId: 3, name: '默认', masked: 'sk-…Dk5s', status: 'active', quota: 0, today: 1.5, last: '2 分钟前' },
    { id: 3902, userId: 6, groupId: 3, name: '默认', masked: 'sk-…Zq1a', status: 'disabled', quota: 0, today: 0, last: '09/30 10:12' },
    { id: 4117, userId: 3, groupId: 4, name: '预发', masked: 'sk-…0dVe', status: 'quota_exhausted', quota: 50, quotaUsed: 50, today: 0, last: '昨天 22:40' },
    { id: 4093, userId: 8, groupId: 4, name: '订阅', masked: 'sk-…Yn6c', status: 'active', quota: 0, today: 0, last: '昨天 18:05' },
    { id: 4031, userId: 3, groupId: 4, name: '企业网关', masked: 'sk-…Gw7k', status: 'active', quota: 0, today: 0, last: '昨天 23:40' },
    { id: 4105, userId: 5, groupId: 5, name: 'Claude Code', masked: 'sk-…Rt2x', status: 'active', quota: 0, today: 0, last: '昨天 21:15' },
    { id: 4066, userId: 8, groupId: 5, name: '默认', masked: 'sk-…Jc9r', status: 'active', quota: 0, today: 3.1, last: '13 分钟前' },
    { id: 4058, userId: 5, groupId: 6, name: 'Gemini 测试', masked: 'sk-…Ge4m', status: 'active', quota: 0, today: 10.8, last: '今天 07:55' },
    { id: 4099, userId: 1, groupId: 7, name: '脚本', masked: 'sk-…9xQ2', status: 'active', quota: 20, quotaUsed: 18.4, today: 0.44, last: '2 分钟前' },
    { id: 4081, userId: 8, groupId: 8, name: 'Kimi', masked: 'sk-…Km8p', status: 'active', quota: 0, today: 1.3, last: '3 分钟前' },
    { id: 4044, userId: 7, groupId: 9, name: 'MiniMax', masked: 'sk-…Mx3v', status: 'active', quota: 0, today: 0, last: '22 分钟前' },
    // The big customers' keys (#21–#26).
    { id: 4121, userId: 21, groupId: 1, name: '生产', masked: 'sk-…Nv4q', status: 'active', quota: 0, today: 402.1, last: '3 分钟前' },
    { id: 4122, userId: 22, groupId: 1, name: '主服务', masked: 'sk-…At7w', status: 'active', quota: 0, today: 239.75, last: '5 分钟前' },
    { id: 4123, userId: 22, groupId: 5, name: 'Claude Code', masked: 'sk-…Ac2k', status: 'active', quota: 0, today: 49.65, last: '26 分钟前' },
    { id: 4124, userId: 23, groupId: 1, name: '推理', masked: 'sk-…Sl9d', status: 'active', quota: 0, today: 201.35, last: '10 分钟前' },
    { id: 4125, userId: 24, groupId: 2, name: '默认', masked: 'sk-…Mr5t', status: 'active', quota: 0, today: 156.8, last: '4 分钟前' },
    { id: 4126, userId: 25, groupId: 2, name: '默认', masked: 'sk-…Px1h', status: 'active', quota: 0, today: 45.13, last: '24 分钟前' },
    { id: 4127, userId: 25, groupId: 8, name: '翻译', masked: 'sk-…Pk6e', status: 'active', quota: 0, today: 25.85, last: '31 分钟前' },
    { id: 4128, userId: 25, groupId: 1, name: 'Claude', masked: 'sk-…Pc3m', status: 'active', quota: 0, today: 20.31, last: '38 分钟前' },
    { id: 4129, userId: 25, groupId: 3, name: 'DeepSeek', masked: 'sk-…Pd8s', status: 'active', quota: 0, today: 6.37, last: '1 小时前' },
    { id: 4130, userId: 26, groupId: 3, name: '批处理', masked: 'sk-…Bc4z', status: 'active', quota: 0, today: 30.73, last: '29 分钟前' },
    { id: 4131, userId: 26, groupId: 7, name: '摘要', masked: 'sk-…Bg2r', status: 'active', quota: 0, today: 17.96, last: '45 分钟前' },
  ],
  /* admin/subscriptions · groups/:id/subscriptions · users/:id/subscriptions (dto.AdminUserSubscription): one row per user and group (unique user_id + group_id), newest first. status
     active | suspended | expired (an active row past expires_at reads as expired), expires = expires_at, day / week / month =
     daily / weekly / monthly_usage_usd against the group's per-subscription limits. This is the first page the demo knows: 企业专线 has
     15 rows in all (subscriptionTotals) and 12 active (groups[].subscriptions). Among the demo's users the active rows are exactly the
     owners of 企业专线 keys — Studio-K (#3: 预发, 企业网关) and 林一 (#8: 订阅) — because a key can only be bound to a subscription group
     while its owner holds an active subscription. 企业专线 has no request today, so every daily usage is 0. 林一's ends in 4 days. */
  subscriptions: [
    { id: 91, userId: 8, groupId: 4, status: 'active', expires: '2026-10-20', day: 0, week: 18.6, month: 41.3 },
    { id: 88, userId: 3, groupId: 4, status: 'active', expires: '2027-01-31', day: 0, week: 64.2, month: 236.4 },
    { id: 79, userId: 7, groupId: 4, status: 'suspended', expires: '2026-12-15', day: 0, week: 0, month: 12.6 },
    { id: 72, userId: 2, groupId: 4, status: 'expired', expires: '2026-10-01', day: 0, week: 0, month: 0 },
  ],
  // Rows groups/:id/subscriptions pages through (every status), by group id.
  subscriptionTotals: { 4: 15 },
  /* admin/proxies (list DTO + latency / quality): protocol, host:port, auth, status active | inactive | expired (ProxyExpiryService),
     latency_ms / latency_status / latency_message (no "tested at" time), exit IP, region, expires_at + expiry_warn_days, expiry fallback
     ('proxy' = move to backupId, 'direct', 'none'), quality grade. accounts (ids) is derived from DEMO.accounts[].proxy below — the link
     lives on the account, so never list it here. probe = what a test run returns in the demo. */
  proxies: [
    { id: 1, name: 'hk-02', protocol: 'socks5', host: '203.0.113.24', port: 1080, username: 'relay', hasPassword: true, status: 'active', latency: 182, latencyOk: true, exitIp: '203.0.113.24', region: '香港', expiresAt: '2026-10-22', warnDays: 7, fallback: 'proxy', backupId: 2, quality: { grade: 'A', score: 92 }, qualityAt: '10/15 22:00', createdAt: '2026-07-22', probe: { latency: 176, quality: { grade: 'A', score: 92 } } },
    { id: 2, name: 'sg-01', protocol: 'https', host: '198.51.100.7', port: 443, username: '', hasPassword: false, status: 'active', latency: 96, latencyOk: true, exitIp: '198.51.100.7', region: '新加坡', expiresAt: '2027-03-01', warnDays: 7, fallback: 'none', quality: { grade: 'A', score: 95 }, qualityAt: '10/14 09:30', createdAt: '2026-08-30', probe: { latency: 101, quality: { grade: 'A', score: 95 } } },
    // expired with fallback = none: the sweep marked it expired but left the account on it — the case that needs a human
    { id: 3, name: 'jp-tokyo-1', protocol: 'socks5h', host: '192.0.2.88', port: 1080, username: 'jp', hasPassword: true, status: 'expired', latency: null, latencyOk: false, latencyMsg: 'dial tcp 192.0.2.88:1080: i/o timeout', exitIp: null, region: null, expiresAt: '2026-10-13', warnDays: 7, fallback: 'none', quality: null, createdAt: '2026-04-13', probe: { fail: 'dial tcp 192.0.2.88:1080: i/o timeout' } },
    { id: 4, name: 'hk-01', protocol: 'http', host: '203.0.113.9', port: 3128, username: 'relay', hasPassword: true, status: 'active', latency: 311, latencyOk: true, exitIp: '203.0.113.9', region: '香港', expiresAt: '2026-11-30', warnDays: 7, fallback: 'proxy', backupId: 1, quality: { grade: 'B', score: 78 }, qualityAt: '10/12 18:20', createdAt: '2026-05-30', probe: { latency: 296, quality: { grade: 'B', score: 77 } } },
    { id: 5, name: 'us-west-3', protocol: 'http', host: '203.0.113.140', port: 8080, username: '', hasPassword: false, status: 'active', latency: 238, latencyOk: true, exitIp: '203.0.113.140', region: '美国', expiresAt: null, warnDays: 7, fallback: 'none', quality: null, createdAt: '2026-09-02', probe: { latency: 244, quality: { grade: 'B', score: 81 } } },
    // expired with fallback = direct: its accounts were already moved to direct (they keep proxy_fallback_origin_id)
    { id: 7, name: 'us-east-2', protocol: 'http', host: '198.51.100.23', port: 3128, username: 'use', hasPassword: true, status: 'expired', latency: null, latencyOk: null, exitIp: null, region: null, expiresAt: '2026-10-11', warnDays: 7, fallback: 'direct', quality: { grade: 'B', score: 80 }, qualityAt: '10/02 11:00', createdAt: '2026-07-11', probe: { fail: 'proxy CONNECT: 407 Proxy Authentication Required' } },
    { id: 6, name: 'de-fra-1', protocol: 'socks5', host: '198.51.100.61', port: 1080, username: 'fra', hasPassword: true, status: 'inactive', latency: null, latencyOk: null, exitIp: null, region: null, expiresAt: '2026-10-19', warnDays: 3, fallback: 'none', quality: null, createdAt: '2026-09-19', probe: { latency: 213, exitIp: '198.51.100.61', region: '德国', quality: { grade: 'C', score: 64 } } },
  ],
  logs: [
    { t: '09:41', code: 200, model: 'claude-sonnet-4-5', user: 'xm.wang', account: 'Claude-官方-01', cost: 0.0124, dur: '3.2s' },
    // A failed attempt retried into a 200: dur is the whole request (Σ attempts), like every other log.
    { t: '09:41', code: 429, model: 'claude-opus-4', user: 'ops@studio-k', account: 'Claude-官方-03', cost: null, dur: '10.2s', kind: '上游错误' },
    { t: '09:40', code: 200, model: 'gpt-4.1-mini', user: 'na.li', account: 'OpenAI-主力-01', cost: 0.0008, dur: '1.1s' },
    { t: '09:40', code: 401, model: 'gpt-4.1', user: 'sy.chen', account: 'OpenAI-备用-A', cost: null, dur: '2.8s', kind: '上游错误' },
    { t: '09:39', code: 200, model: 'deepseek-chat', user: 'hao.sun', account: 'DeepSeek-01', cost: 0.0031, dur: '2.4s' },
    { t: '09:39', code: 504, model: 'glm-4.6-long-context-preview', user: 'xm.wang', account: 'GLM-直连-01', cost: null, dur: '60.0s', kind: '错误请求' },
    // 9012 / 9010 / 9009 / 9005: big customers (Nova, Mira Labs, Atlas, 深蓝 AI) on their 高级组 / 标准组 keys.
    { t: '09:38', code: 200, model: 'claude-sonnet-4-5', user: 'billing@nova', account: 'Claude-官方-02', cost: 0.2410, dur: '18.6s' },
    { t: '09:38', code: 200, model: 'kimi-k2', user: 'yi.lin', account: 'Kimi-01', cost: 0.0052, dur: '2.9s' },
    { t: '09:37', code: 200, model: 'gpt-4.1-mini', user: 'team@mira', account: 'OpenAI-主力-01', cost: 0.0006, dur: '0.9s' },
    { t: '09:36', code: 200, model: 'claude-opus-4', user: 'api@atlas', account: 'Claude-官方-01', cost: 1.0820, dur: '42.1s' },
    { t: '09:35', code: 200, model: 'claude-sonnet-4-5', user: 'sy.chen', account: 'Claude-官方-01', cost: 0.0418, dur: '6.8s' },
    { t: '09:34', code: 529, model: 'claude-sonnet-4-5', user: 'xm.wang', account: 'Claude-官方-01', cost: null, dur: '8.6s', kind: '上游错误' },
    { t: '09:33', code: 200, model: 'claude-haiku-4-5', user: 'na.li', account: 'Claude-官方-01', cost: 0.0009, dur: '0.7s' },
    { t: '09:31', code: 200, model: 'claude-sonnet-4-5', user: 'dev@shenlan', account: 'Claude-官方-01', cost: 0.1932, dur: '15.2s' },
    { t: '09:30', code: 400, model: 'claude-opus-4', user: 'hao.sun', account: 'Claude-官方-01', cost: null, dur: '0.1s', kind: '错误请求' },
    { t: '09:28', code: 200, model: 'claude-sonnet-4-5', user: 'yi.lin', account: 'Claude-官方-01', cost: 0.0207, dur: '4.1s' },
    { t: '09:27', code: 200, model: 'claude-haiku-4-5', user: 'xm.wang', account: 'Claude-官方-01', cost: 0.0004, dur: '0.6s' },
    { t: '09:25', code: 200, model: 'claude-sonnet-4-5', user: 'na.li', account: 'Claude-官方-01', cost: 0.0336, dur: '5.5s' },
    // id 9000: the 标准组 failure inside the 09:24–09:29 window behind the firing alert “标准组错误率 5.2%”.
    { t: '09:24', code: 502, model: 'gpt-4.1', user: 'ting.z', account: 'OpenAI-备用-A', cost: null, dur: '3.9s', kind: '错误请求' },
    // Oldest entry (id 8999): the 529 that matched MiniMax-01's temp-unschedulable rule (45 minutes → back at 10:04).
    { t: '09:19', code: 529, model: 'MiniMax-M2', user: 'hao.sun', account: 'MiniMax-01', cost: null, dur: '1.1s', kind: '错误请求' },
  ],
};

// The firing alert the home screen leads with: the very same object as alerts[0] (event #41), so every page reads one record.
DEMO.alert = DEMO.alerts[0];

/* ---------- derived links (computed once at load; edit the source lists above, never these) ---------- */

// users[].keys = the user's rows of DEMO.keys, oldest first (王小明: 默认, 脚本). Field names of the earlier per-user list stay:
// label = name, used = last (last_used_at), group = group name; the key's own fields (id, groupId, status, quota, quotaUsed, today) ride along.
function demoUserKeys(userId) {
  return DEMO.keys.filter(k => k.userId === userId).sort((a, b) => a.id - b.id).map(k => ({
    id: k.id, label: k.name, masked: k.masked, used: k.last, group: (groupOf(k.groupId) || { name: null }).name, groupId: k.groupId,
    status: k.status, quota: k.quota, ...(k.quotaUsed !== undefined ? { quotaUsed: k.quotaUsed } : {}), today: k.today,
  }));
}
DEMO.users = DEMO.users.map(u => ({ ...u, keys: demoUserKeys(u.id) }));
// proxies[].accounts (ids) follows the accounts' own proxy field.
DEMO.proxies = DEMO.proxies.map(p => ({ ...p, accounts: DEMO.accounts.filter(a => a.proxy === p.name).map(a => a.id) }));

/* Request-detail fields (mirrors usage_logs / ops error logs: first_token_ms, duration_ms, request_type, costs, tokens,
   model mapping, phase / owner / severity, upstream retry chain). Derived deterministically so every log has a detail page.
   Classification as the backend does it (handler/ops_error_logger.go): upstream / account_auth rows are always owner provider;
   severity P1 for ≥ 500 and 429, P2 for other ≥ 400, P3 for client request errors (invalid_request_error …). */
const LOG_FAILURES = {
  '09:41|429': { phase: 'upstream', owner: 'provider', severity: 'P1', message: 'rate_limit_error: This request would exceed the rate limit for your organization (claude-opus-4).', attempts: [{ account: 'Claude-官方-03', code: 429, dur: '0.4s' }, { account: 'Claude-官方-01', code: 200, dur: '9.8s' }], clientCode: 200 },
  '09:40|401': { phase: 'upstream', owner: 'provider', severity: 'P2', message: 'invalid_api_key: Incorrect API key provided. You can find your API key at platform.openai.com.', attempts: [{ account: 'OpenAI-备用-A', code: 401, dur: '0.2s' }, { account: 'OpenAI-主力-01', code: 200, dur: '2.6s' }], clientCode: 200 },
  '09:39|504': { phase: 'upstream', owner: 'provider', severity: 'P1', message: 'upstream request timeout: no response from open.bigmodel.cn after 60s', attempts: [{ account: 'GLM-直连-01', code: 529, dur: '1.2s' }, { account: 'GLM-直连-01', code: 504, dur: '58.8s' }], clientCode: 504 },
  '09:34|529': { phase: 'upstream', owner: 'provider', severity: 'P1', message: 'overloaded_error: Overloaded', attempts: [{ account: 'Claude-官方-01', code: 529, dur: '1.2s' }, { account: 'Claude-官方-02', code: 200, dur: '7.4s' }], clientCode: 200 },
  '09:30|400': { phase: 'request', owner: 'client', severity: 'P3', message: 'invalid_request_error: max_tokens: 200000 > 32000, which is the maximum allowed number of output tokens for claude-opus-4', attempts: [], clientCode: 400 },
  '09:24|502': { phase: 'upstream', owner: 'provider', severity: 'P1', message: 'upstream_error: 502 Bad Gateway — api.openai.com returned an error page instead of a response', attempts: [{ account: 'OpenAI-主力-01', code: 500, dur: '2.1s' }, { account: 'OpenAI-备用-A', code: 502, dur: '1.8s' }], clientCode: 502 },
  '09:19|529': { phase: 'upstream', owner: 'provider', severity: 'P1', message: 'overloaded_error: 当前服务集群负载较高，请稍后重试（529）', attempts: [{ account: 'MiniMax-01', code: 529, dur: '1.1s' }], clientCode: 529 },
};
const UPSTREAM_MODEL = { 'claude-sonnet-4-5': 'claude-sonnet-4-5-20250929', 'claude-opus-4': 'claude-opus-4-20250514', 'claude-haiku-4-5': 'claude-haiku-4-5-20251001', 'gpt-4.1-mini': 'gpt-4.1-mini-2025-04-14', 'gpt-4.1': 'gpt-4.1-2025-04-14' };
// Ids are fixed (newest 9018 … oldest 8999) so routes and decks that name a request keep pointing at the same one.
const LOG_ID_TOP = 9018;
DEMO.logs = DEMO.logs.map((l, i) => {
  const seconds = parseFloat(l.dur);
  const ok = l.code === 200;
  const ttft = ok ? Math.max(0.3, Math.min(seconds * 0.32, 2.4)) : null;
  const out = ok ? Math.round(seconds * 85 + 40) : 0;
  const inTok = ok ? Math.round((l.cost || 0) * 52000 + 900 + i * 37) : 0;
  const failure = LOG_FAILURES[`${l.t}|${l.code}`] || null;
  const user = DEMO.users.find(u => u.email.startsWith(l.user)) || null;
  const account = DEMO.accounts.find(a => a.name === l.account) || null;
  // The request ran in the key's group, so it is one of the account's groups: the user's main group when the account serves it.
  const groups = account ? account.groups : [];
  const group = l.group || (user && groups.includes(user.group) ? user.group : groups[0]) || null;
  const g = groupOf(group);
  // The key is the user's key of that group (DEMO.keys), so the request page and the group's key page show the same key.
  const row = user && g ? DEMO.keys.find(k => k.userId === user.id && k.groupId === g.id) : null;
  const key = row ? { id: row.id, label: row.name, masked: row.masked, group } : { label: '—', masked: '—', group };
  return {
    ...l,
    id: LOG_ID_TOP - i,
    rid: `req_${(0x5f3a91c4 + i * 2654435761 >>> 0).toString(16)}${(0x1b7e + i * 97).toString(16)}`,
    ttft: ttft === null || (ok && i % 4 === 2) ? null : `${ttft.toFixed(1)}s`,
    stream: ok ? (i % 4 === 2 ? '非流式' : '流式') : '流式',
    tokens: ok ? { input: inTok, output: out, cacheRead: i % 3 === 0 ? Math.round(inTok * 0.6) : 0, cacheWrite: i % 5 === 0 ? 1024 : 0 } : null,
    // 标准 = 实际 ÷ the group's rate (actual = total_cost × rate_multiplier).
    std: l.cost === null ? null : +(l.cost / (g ? g.rate : 1)).toFixed(4),
    acost: l.cost === null ? null : +(l.cost * 0.42).toFixed(4),
    upstreamModel: UPSTREAM_MODEL[l.model] || l.model,
    key,
    userName: user ? user.name : l.user,
    userId: user ? user.id : null,
    group,
    accountId: account ? account.id : null,
    failure,
    resolved: false,
  };
});

/* ---------- log scopes and filters: one rule for every list and every count ---------- */

/* The three lists of the usage page, as the backend builds them:
   用量明细 = admin/usage (requests that succeeded); 错误请求 = ops request-errors (the client finally got ≥ 400, any phase);
   上游错误 = ops upstream-errors (phase upstream or account_auth, owner provider — retried into a success or not, IncludeRecoveredUpstream).
   So 9013 (GLM 504) and 9000 (502) sit in both 错误请求 and 上游错误. */
const LOG_SCOPES = {
  usage: l => !l.failure && codeTone(l.code) === 'ok',
  errors: l => (finalCode(l) || 0) >= 400,
  upstream: l => Boolean(l.failure) && ['upstream', 'account_auth'].includes(l.failure.phase),
};
/* Filters and the lists that take them: account (account_id) and group (group_id) work on all three; model only on 用量明细
   (admin/usage matches the requested model exactly, ModelFilterSource=Requested) and 错误请求 (model); user on 用量明细 (user_id) and
   错误请求 (user_query). ops upstream-errors has neither a model nor a user parameter. */
const LOG_MATCH = {
  account: { scopes: ['usage', 'errors', 'upstream'], test: v => l => (typeof v === 'number' ? l.accountId === v : l.account === v) },
  group: { scopes: ['usage', 'errors', 'upstream'], test: v => l => l.group === (groupOf(v) || { name: v }).name },
  model: { scopes: ['usage', 'errors'], test: v => l => l.model === v },
  user: { scopes: ['usage', 'errors'], test: v => l => { const u = userOf(v); return u ? l.userId === u.id : l.user === v; } },
};
// Logs of one list under some filters: logsWhere({scope:'upstream', account: 3}). Filters a list does not take are ignored, as the API would.
function logsWhere(where = {}) {
  const scope = where.scope || 'usage';
  const tests = Object.entries(LOG_MATCH)
    .filter(([k, f]) => where[k] !== undefined && where[k] !== null && where[k] !== '' && f.scopes.includes(scope))
    .map(([k, f]) => f.test(where[k]));
  return DEMO.logs.filter(l => LOG_SCOPES[scope](l) && tests.every(t => t(l)));
}
function logCount(where) {
  return logsWhere(where).length;
}
// Newest upstream error of an account (ops/upstream-errors?account_id=:id&page_size=1): {id, t, code, ago} or null.
function lastUpstreamError(accountId, elapsed = 0) {
  const l = logsWhere({ scope: 'upstream', account: accountId })[0];
  if (!l) return null;
  const base = new Date(DEMO_CLOCK_BASE);
  const [h, m] = l.t.split(':').map(Number);
  const mins = base.getHours() * 60 + base.getMinutes() - (h * 60 + m) + Math.floor(elapsed / 60);
  const ago = mins < 1 ? '刚刚' : mins < 60 ? `${mins} 分钟前` : `${Math.floor(mins / 60)} 小时前`;
  const code = l.failure && l.failure.attempts.length ? (l.failure.attempts.find(x => x.account === l.account) || l.failure.attempts[0]).code : l.code;
  return { id: l.id, t: l.t, code, ago };
}
// Upstream errors in the last 24 h per account: the same count the account page shows and the filtered list it opens.
DEMO.accounts = DEMO.accounts.map(a => ({ ...a, errors24h: logCount({ scope: 'upstream', account: a.id }) }));

/* ---------- vocabulary helpers ---------- */

// One colour rule for every status code: 2xx ok, 429 amber, everything else that failed (4xx, 5xx, 504, 529) red.
// Rows and heroes colour by the code the client finally got (finalCode), so an upstream error that was retried into a 200 reads as ok.
function codeTone(code) {
  if (code === null || code === undefined) return 'neutral';
  if (code >= 200 && code < 300) return 'ok';
  if (code === 429) return 'caution';
  return 'critical';
}
function finalCode(log) {
  return log.failure ? log.failure.clientCode : log.code;
}

// Alert colour, same split as Web's severity badges (OpsAlertEventsCard: P0 red, P1 amber, P2 info, P3 grey): a firing P0 is
// critical, a firing P1 / P2 caution (the palette has no info colour; brand cyan only means “actionable”), P3 neutral; an alert
// that is no longer firing has no tone ('none'). Every alert row, badge and attention item uses it.
function alertTone(alert) {
  if (!alert || alert.status !== 'firing') return 'none';
  return alert.level === 'P0' ? 'critical' : alert.level === 'P3' ? 'neutral' : 'caution';
}

// The schedule switch (backend `schedulable`), separate from the runtime state. 'paused' is a normal account with the switch off and
// 'normal' always has it on (older callers flip state alone); other states read the flag, so a rate-limited account can be stopped
// and keep its countdown.
function isSchedulable(a) {
  if (a.state === 'paused') return false;
  if (a.state === 'normal') return true;
  return a.schedulable !== false;
}
// Extra mark for a blocked account whose switch is off as well; null when the state badge already says it all.
function schedLabel(a) {
  const meta = STATE_META[a.state];
  return meta && meta.timed && !isSchedulable(a) ? '已停止调度' : null;
}

// Groups: look up by id or name; members come from the accounts' own group lists (pass DEMO.accounts or ctx.accounts).
function groupOf(key) {
  return DEMO.groups.find(g => g.id === key || g.name === key) || null;
}
// Users by id, email or the email's local part (DEMO.logs write 'xm.wang'); proxies by id or name.
function userOf(key) {
  if (key === null || key === undefined) return null;
  return DEMO.users.find(u => u.id === key || u.email === key || u.email.startsWith(`${key}@`) || u.email.startsWith(String(key))) || null;
}
/* The user list's order, as Web asks for it (UsersView default sort: created_at desc): newest first. The demo users carry no
   created_at, and ids are auto-increment, so they fall back to id descending — the big customers #26 → #21 come first, #1 王小明
   last, and a user created on the phone (max id + 1) lands on top. Takes an array or ctx.users; returns a new array. */
function usersNewestFirst(users) {
  const list = Array.isArray(users) ? [...users] : Object.values(users);
  return list.sort((a, b) => (a.createdAt && b.createdAt && a.createdAt !== b.createdAt ? (a.createdAt < b.createdAt ? 1 : -1) : b.id - a.id));
}
function proxyOf(key) {
  if (key === null || key === undefined) return null;
  return DEMO.proxies.find(p => p.id === key || p.name === key) || null;
}
// Protocol label as Web prints it (HTTP / HTTPS / SOCKS5 / SOCKS5H).
function proxyProto(p) {
  return p ? p.protocol.toUpperCase() : '';
}
// Whole days from the demo's day (DEMO_TODAY) to an ISO date 'YYYY-MM-DD'; negative once it has passed, null without a date.
function daysUntil(iso) {
  if (!iso) return null;
  const day = s => { const [y, m, d] = s.split('-').map(Number); return Date.UTC(y, m - 1, d); };
  return Math.round((day(iso) - day(DEMO_TODAY)) / 86400000);
}
/* A proxy's expiry in the proxies page's words (Web: 永不过期 / N 天后到期 / 剩余 N 天) → {key, label, tone}. Only an active proxy counts
   down; an expired one is a status (the sweep set status = expired) and a disabled one has nothing to count down to.
   key: lapsed | never | idle | soon | ok; tone: 'critical' | 'caution' | 'none'. */
function proxyExpiry(p) {
  const short = iso => (iso ? iso.slice(5).replace('-', '/') : '—');
  if (p.status === 'expired') return { key: 'lapsed', label: `${short(p.expiresAt)} 已过期`, tone: 'critical' };
  const d = daysUntil(p.expiresAt);
  if (d === null) return { key: 'never', label: '永不过期', tone: 'none' };
  if (p.status !== 'active') return { key: 'idle', label: `${short(p.expiresAt)} 到期`, tone: 'none' };
  if (d < 0) return { key: 'soon', label: '已到期 · 等待处理', tone: 'caution' }; // between two sweeps
  if (d <= p.warnDays) return { key: 'soon', label: d === 0 ? '今天到期' : `${d} 天后到期`, tone: 'caution' };
  return { key: 'ok', label: `剩余 ${d} 天`, tone: 'none' };
}
// Subscriptions of a user (users/:id/subscriptions), newest first; the active one of a user in a group, or null.
function subscriptionsOf(userId) {
  return DEMO.subscriptions.filter(s => s.userId === userId).sort((a, b) => b.id - a.id);
}
function activeSubscription(userId, groupId) {
  const g = groupOf(groupId);
  return DEMO.subscriptions.find(s => s.userId === userId && s.groupId === (g ? g.id : groupId) && s.status === 'active') || null;
}
// One group's subscription page (groups/:id/subscriptions): rows (first page, newest first), total rows of every status, active count.
function groupSubscriptions(groupKey) {
  const g = groupOf(groupKey);
  if (!g) return { rows: [], total: 0, active: 0 };
  const rows = DEMO.subscriptions.filter(s => s.groupId === g.id).sort((a, b) => b.id - a.id);
  return { rows, total: Math.max((DEMO.subscriptionTotals || {})[g.id] || 0, rows.length), active: g.subscriptions || 0 };
}
// Effective rate for a user in a group: the user's own rate (users[].rates, group id → rate) or the group's rate_multiplier.
function effectiveRate(user, groupKey) {
  const g = groupOf(groupKey);
  const own = user && user.rates ? user.rates[g ? g.id : groupKey] : undefined;
  return own !== undefined ? own : g ? g.rate : 1;
}
function groupMembers(accounts, key) {
  const g = groupOf(key);
  const name = g ? g.name : key;
  const list = Array.isArray(accounts) ? accounts : Object.values(accounts);
  return list.filter(a => (a.groups || []).includes(name));
}
// Same buckets as the groups page: 可用 = normal; 受限 = rate limit / overload / temp-unschedulable; 错误; 暂停·停用.
function groupAvailability(accounts, key) {
  const m = groupMembers(accounts, key);
  const n = test => m.filter(test).length;
  return {
    total: m.length,
    available: n(a => a.state === 'normal'),
    limited: n(a => ['rate_limited', 'overloaded', 'temp_unsched'].includes(a.state)),
    error: n(a => a.state === 'error'),
    idle: n(a => a.state === 'paused' || a.state === 'inactive'),
  };
}

function accountsWith(overrides) {
  return DEMO.accounts.map(a => ({ ...a, ...(overrides[a.id] || {}) }));
}
function remaining(account, elapsed) {
  return account.resetIn === undefined ? null : Math.max(0, account.resetIn - elapsed);
}
function sortByUrgency(list) {
  return [...list].sort((a, b) => STATE_ORDER.indexOf(a.state) - STATE_ORDER.indexOf(b.state));
}
// unscheduled = switch off (paused, errored, or a blocked account stopped by hand); stopped = blocked and also switched off.
function accountCounts(list) {
  const c = { total: list.length, needs: 0, error: 0, limited: 0, paused: 0, inactive: 0, normal: 0, unscheduled: 0, stopped: 0 };
  list.forEach(a => {
    if (NEEDS_ACTION.includes(a.state)) c.needs++;
    if (a.state === 'error') c.error++;
    if (['rate_limited', 'overloaded', 'temp_unsched'].includes(a.state)) c.limited++;
    if (a.state === 'paused') c.paused++;
    if (a.state === 'inactive') c.inactive++;
    if (a.state === 'normal') c.normal++;
    if (a.state !== 'inactive' && !isSchedulable(a)) c.unscheduled++;
    if (schedLabel(a)) c.stopped++;
  });
  return c;
}
function tightestCapacity(account) {
  if (!account.conc) return null;
  return { used: account.conc[0], limit: account.conc[1], ratio: account.conc[0] / account.conc[1], label: '并发' };
}
function yesterdaySameTime() {
  const h = DEMO.hourlyYesterday;
  return h.slice(0, 9).reduce((s, v) => s + v, 0) + h[9] * (41 / 60);
}
function todayChange() {
  return (DEMO.today.actual / yesterdaySameTime() - 1) * 100;
}
// 利润 = 实际扣费 − 账号成本 (actual − total_account_cost). Pass any {actual, cost} pair; defaults to today's site totals.
function profitOf(t = DEMO.today) {
  return t.actual - t.cost;
}
// One word per health-score band (ops health_score; Web's diagnosis splits at 90 and 60): ≥ 90 良好, ≥ 60 风险, below 异常.
function healthWord(score) {
  return score >= 90 ? '良好' : score >= 60 ? '风险' : '异常';
}
// Success rate as a display string (one decimal). Default window = DEMO.run.errorRate's (近 5 分钟, the 运行 / 6-cell figures);
// 'today' = since 00:00 on the SLA basis, the same figure as 统计分析 · 今天 (errorsSla ÷ (requests + errorsSla) = 1.7% → 98.3%).
function successRate(window) {
  if (window === 'today') {
    const t = DEMO.today;
    return `${(100 - (t.errorsSla / (t.requests + t.errorsSla)) * 100).toFixed(1)}%`;
  }
  return `${(100 - DEMO.run.errorRate).toFixed(1)}%`;
}
// Error rate as a display string, the complement of successRate. Default = the last 5 minutes (DEMO.run.errorRate, '0.8%': the 运行
// block and the home's 6 cells; the window is no longer written next to them, review 2026-10-18); 'today' = since 00:00 on the SLA basis ('1.7%'), the same figure as 统计分析 · 今天.
function errorRate(window) {
  if (window === 'today') {
    const t = DEMO.today;
    return `${((t.errorsSla / (t.requests + t.errorsSla)) * 100).toFixed(1)}%`;
  }
  return `${DEMO.run.errorRate.toFixed(1)}%`;
}

// Simple SF-Symbols-like glyphs drawn on a 24-unit grid (strokes only, no imagery).
function Icon({ name, size = 18, color = 'currentColor', weight = 2, fill }) {
  const p = { fill: 'none', stroke: color, strokeWidth: weight, strokeLinecap: 'round', strokeLinejoin: 'round' };
  const solid = { fill: color, stroke: 'none' };
  const shapes = {
    dot: <circle cx="12" cy="12" r="5" {...solid} />,
    hourglass: <g {...p}><path d="M7 3h10M7 21h10M8 3c0 5 8 6 8 9s-8 4-8 9M16 3c0 5-8 6-8 9s8 4 8 9" /></g>,
    flame: <g {...p}><path d="M12 3c1 4 6 6 6 11a6 6 0 0 1-12 0c0-3 2-4 3-6 1 2 2 3 3 3-1-3 0-6 0-8z" /></g>,
    clockAlert: <g {...p}><circle cx="11" cy="13" r="7" /><path d="M11 9v4l2.5 2M19 3v4M19 10h0" /></g>,
    octagon: <g {...p}><path d="M8.5 3h7L21 8.5v7L15.5 21h-7L3 15.5v-7z" /><path d="M9.5 9.5l5 5M14.5 9.5l-5 5" /></g>,
    pause: <g {...p}><circle cx="12" cy="12" r="9" /><path d="M10 9v6M14 9v6" /></g>,
    minus: <g {...p}><circle cx="12" cy="12" r="9" /><path d="M8 12h8" /></g>,
    cube: <g {...p}><path d="M12 3l8 4.5v9L12 21l-8-4.5v-9z" /><path d="M4 7.5l8 4.5 8-4.5M12 12v9" /></g>,
    bell: <g {...p}><path d="M6 16V11a6 6 0 0 1 12 0v5l2 2H4z" /><path d="M10 21h4" /></g>,
    group: <g {...p}><rect x="3" y="4" width="18" height="5" rx="1.5" /><rect x="3" y="11" width="18" height="5" rx="1.5" /><path d="M7 6.5h0M7 13.5h0" /></g>,
    docCheck: <g {...p}><path d="M14 3H7a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h4" /><path d="M14 3l5 5h-5z" /><circle cx="16.5" cy="16.5" r="3" /><path d="M19 19l2 2" /></g>,
    home: <g {...p}><path d="M4 11l8-7 8 7v9a1 1 0 0 1-1 1h-4v-6H9v6H5a1 1 0 0 1-1-1z" /></g>,
    gauge: <g {...p}><path d="M4 17a8 8 0 1 1 16 0" /><path d="M12 17l4-5" /></g>,
    server: <g {...p}><rect x="4" y="4" width="16" height="7" rx="2" /><rect x="4" y="13" width="16" height="7" rx="2" /><path d="M8 7.5h0M8 16.5h0" /></g>,
    people: <g {...p}><circle cx="9" cy="8" r="3.5" /><path d="M3 20c0-3.5 2.7-6 6-6s6 2.5 6 6" /><path d="M16 4.5a3.5 3.5 0 0 1 0 7M18 14c2 .8 3 3 3 6" /></g>,
    pulse: <g {...p}><path d="M3 12h4l2-6 4 12 2-6h6" /></g>,
    search: <g {...p}><circle cx="10.5" cy="10.5" r="6.5" /><path d="M15.5 15.5L21 21" /></g>,
    back: <g {...p}><path d="M15 4l-8 8 8 8" /></g>,
    chevron: <g {...p}><path d="M9 5l7 7-7 7" /></g>,
    chevronDown: <g {...p}><path d="M6 9l6 6 6-6" /></g>,
    more: <g {...solid}><circle cx="5" cy="12" r="1.8" /><circle cx="12" cy="12" r="1.8" /><circle cx="19" cy="12" r="1.8" /></g>,
    filter: <g {...p}><path d="M4 7h16M7 12h10M10 17h4" /></g>,
    close: <g {...p}><path d="M6 6l12 12M18 6L6 18" /></g>,
    check: <g {...p}><path d="M5 12.5l4.5 4.5L19 7" /></g>,
    checkCircle: <g {...p}><circle cx="12" cy="12" r="9" /><path d="M8 12.5l2.8 2.8L16 9.8" /></g>,
    play: <g {...solid}><path d="M8 5l11 7-11 7z" /></g>,
    pauseFill: <g {...solid}><rect x="6" y="5" width="4" height="14" rx="1" /><rect x="14" y="5" width="4" height="14" rx="1" /></g>,
    wave: <g {...p}><path d="M3 12h3l2-5 3 10 3-8 2 3h5" /></g>,
    restore: <g {...p}><path d="M4 12a8 8 0 1 0 2.5-5.8" /><path d="M4 4v4h4" /></g>,
    key: <g {...p}><circle cx="8" cy="15" r="4" /><path d="M11 12l9-9M17 6l2 2M15 8l2 2" /></g>,
    arrowRight: <g {...p}><path d="M5 12h14M13 6l6 6-6 6" /></g>,
    up: <g {...p}><path d="M12 19V5M6 11l6-6 6 6" /></g>,
    signal: <g {...p}><path d="M5 18a10 10 0 0 1 0-12M19 6a10 10 0 0 1 0 12M8.5 15a5 5 0 0 1 0-6M15.5 9a5 5 0 0 1 0 6" /><circle cx="12" cy="12" r="1.2" {...solid} /></g>,
    list: <g {...p}><path d="M9 6h11M9 12h11M9 18h11M4.5 6h0M4.5 12h0M4.5 18h0" /></g>,
    chart: <g {...p}><path d="M4 20V10M10 20V4M16 20v-7M21 20H3" /></g>,
    web: <g {...p}><circle cx="12" cy="12" r="9" /><path d="M3 12h18M12 3c3 3 3 15 0 18M12 3c-3 3-3 15 0 18" /></g>,
    gift: <g {...p}><rect x="4" y="9" width="16" height="11" rx="1.5" /><path d="M4 13h16M12 9v11M12 9c-2-4-6-3-5 0M12 9c2-4 6-3 5 0" /></g>,
    megaphone: <g {...p}><path d="M4 10v4h3l7 4V6L7 10z" /><path d="M18 9a4 4 0 0 1 0 6" /></g>,
    shield: <g {...p}><path d="M12 3l7 3v6c0 4-3 7-7 9-4-2-7-5-7-9V6z" /></g>,
    plus: <g {...p}><path d="M12 5v14M5 12h14" /></g>,
    grid: <g {...p}><rect x="4" y="4" width="7" height="7" rx="2" /><rect x="13" y="4" width="7" height="7" rx="2" /><rect x="4" y="13" width="7" height="7" rx="2" /><rect x="13" y="13" width="7" height="7" rx="2" /></g>,
    browse: <g {...p}><rect x="4" y="4" width="16" height="16" rx="3" /><path d="M4 10h16M10 10v10" /></g>,
    deleteLeft: <g {...p}><path d="M9 5h10a2 2 0 0 1 2 2v10a2 2 0 0 1-2 2H9l-6-7z" /><path d="M12 9.5l5 5M17 9.5l-5 5" /></g>,
    chevronUp: <g {...p}><path d="M6 15l6-6 6 6" /></g>,
    columns: <g {...p}><rect x="3.5" y="4" width="17" height="16" rx="2" /><path d="M9.5 4v16M14.5 4v16" /></g>,
    compose: <g {...p}><path d="M12 4H6a2 2 0 0 0-2 2v12a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2v-6" /><path d="M18 3l3 3-8 8H10v-3z" /></g>,
    tray: <g {...p}><path d="M4 13l2.5-7h11L20 13v5a2 2 0 0 1-2 2H6a2 2 0 0 1-2-2z" /><path d="M4 13h4l1.5 2.5h5L16 13h4" /></g>,
    pin: <g {...p}><path d="M9 4h6l-1 6 3 3H7l3-3z" /><path d="M12 13v8" /></g>,
    sort: <g {...p}><path d="M8 4v16M4.5 16.5L8 20l3.5-3.5M16 20V4M12.5 7.5L16 4l3.5 3.5" /></g>,
    dollar: <g {...p}><circle cx="12" cy="12" r="9" /><path d="M15 9.2c-.5-1-1.6-1.6-3-1.6-1.7 0-3 .9-3 2.2 0 3 6 1.5 6 4.5 0 1.3-1.3 2.2-3 2.2-1.5 0-2.6-.7-3.1-1.7M12 6v1.6M12 16.5V18" /></g>,
    sliders: <g {...p}><path d="M4 7h10M18 7h2M4 17h4M12 17h8" /><circle cx="16" cy="7" r="2" /><circle cx="10" cy="17" r="2" /></g>,
    refresh: <g {...p}><path d="M20 12a8 8 0 0 1-14 5.3M4 12a8 8 0 0 1 14-5.3" /><path d="M18 3v4h-4M6 21v-4h4" /></g>,
  };
  return (
    <svg width={size} height={size} viewBox="0 0 24 24" aria-hidden="true" style={{ flex: 'none', display: 'block' }}>
      {shapes[name] || shapes.dot}
    </svg>
  );
}
