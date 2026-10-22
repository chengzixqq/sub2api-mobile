/* 第 2 轮 · 账号详情变体（槽 accountDetail，变体名 vd）。一个组件按两个开关画出不同样子：
   ctx.v.vdAct   操作放哪：'row' 状态卡下一排按钮（同 base）| 'toolbar' 底部玻璃工具栏（详情页隐藏 Tab 栏）| 'menu' 卡内一个主按钮 + 右上 ⋯ 菜单
   ctx.v.vdInfo  下方信息：'all' 全部展开 | 'seg' 容量 / 用量 / 记录 / 档案 分段 | 'fold' 四张折叠卡（默认只展开容量）
   三种信息组织用同一批区块（vdGroups），内容完全一致，只比怎么摆。截图开关：ctx.v.vdTab（分段初始页）、ctx.v.vdOpen（折叠初始展开的卡）、ctx.v.vdMenu（菜单打开）。
   语义：错误账号出错时后端已把调度关掉（SetError → schedulable=false），主操作“恢复并启用调度”，确认框里另给“仅恢复状态”；
   限流 / 过载 / 临时不可调度用“恢复状态”；暂停用“启用调度”（POST :id/schedulable）；停用（status=inactive）用“启用账号”（PUT :id，status=active）——
   IsSchedulable 还要求 status=active，只开调度开关不会让停用账号参与调度；正常账号只有测试与停止调度。 */

/* ---------- demo data this screen loads beyond GET admin/accounts/:id ---------- */

// GET admin/accounts/:id/usage — upstream 5h / 7d windows (OAuth accounts). Claude-官方-03's 5h window is the same 100% as its window5h.
const VD_UPSTREAM = {
  3: [{ label: '5 小时', ratio: 1, reset: '11:00 重置' }, { label: '7 天', ratio: 0.64, reset: '10/20 重置' }],
  1: [{ label: '5 小时', ratio: 0.58, reset: '12:10 重置' }, { label: '7 天', ratio: 0.41, reset: '10/21 重置' }],
  2: [{ label: '5 小时', ratio: 0.66, reset: '11:40 重置' }, { label: '7 天', ratio: 0.47, reset: '10/19 重置' }],
};
// GET admin/accounts/:id/models
const VD_MODELS = {
  Anthropic: ['claude-opus-4', 'claude-sonnet-4-5', 'claude-haiku-4-5'],
  OpenAI: ['gpt-4.1', 'gpt-4.1-mini', 'gpt-4o'],
  Gemini: ['gemini-2.5-pro', 'gemini-2.5-flash'],
  '智谱 GLM': ['glm-4.6', 'glm-4.5-air'],
  MiniMax: ['MiniMax-M2'],
  DeepSeek: ['deepseek-chat', 'deepseek-reasoner'],
  Kimi: ['kimi-k2'],
  Grok: ['grok-4', 'grok-3-mini'],
};
// GET admin/accounts/:id/scheduled-test-plans + plan results (status, latency_ms, error_message). Rows: [time, ok, latency, message].
const VD_TESTS = {
  3: { plan: '每 10 分钟 · claude-sonnet-4-5', results: [['09:40', false, '0.4s', '429 rate_limit_error'], ['09:30', true, '1.3s'], ['09:20', true, '1.1s']] },
  7: { plan: '每 10 分钟 · gpt-4.1-mini', results: [['09:40', false, '0.2s', '401 invalid_api_key'], ['09:30', true, '0.8s'], ['09:20', true, '0.9s']] },
  11: { plan: '每 15 分钟 · glm-4.6', results: [['09:30', false, '1.2s', '529 overloaded'], ['09:15', true, '2.1s'], ['09:00', true, '1.9s']] },
  12: { plan: '每 15 分钟 · MiniMax-M2', results: [['09:30', false, '1.4s', '529 overloaded'], ['09:15', false, '1.3s', '529 overloaded'], ['09:00', true, '2.4s']] },
  1: { plan: '每 30 分钟 · claude-haiku-4-5', results: [['09:30', true, '0.9s'], ['09:00', true, '1.0s'], ['08:30', true, '1.2s']] },
  2: { plan: '每 30 分钟 · claude-haiku-4-5', results: [['09:30', true, '1.0s'], ['09:00', true, '0.9s'], ['08:30', true, '1.1s']] },
  4: { plan: '每 30 分钟 · gpt-4.1-mini', results: [['09:30', true, '0.7s'], ['09:00', true, '0.8s'], ['08:30', true, '0.7s']] },
};

// Claude-官方-03 (1,204 requests today) and MiniMax-01 (96) have one / no row in the shared sample; add older rows so their
// recent lists and the logs pages they link to agree. All older than 09:25 and appended (not spliced), so every shared id and
// position stays as it was and the site-wide log stays in time order.
const VD_EXTRA_LOGS = [
  { t: '09:24', code: 200, model: 'claude-sonnet-4-5', user: 'ops@studio-k', account: 'Claude-官方-03', cost: 0.0861, dur: '9.2s' },
  { t: '09:22', code: 200, model: 'claude-opus-4', user: 'xm.wang', account: 'Claude-官方-03', cost: 0.612, dur: '31.4s' },
  { t: '09:21', code: 529, model: 'MiniMax-M2', user: 'hao.sun', account: 'MiniMax-01', cost: null, dur: '4.2s', kind: '错误请求',
    failure: { phase: 'upstream', owner: 'provider', severity: 'P2', message: 'overloaded_error: The server cluster is currently under high load. Please retry later. (MiniMax-M2)', attempts: [{ account: 'MiniMax-01', code: 529, dur: '1.4s' }, { account: 'MiniMax-01', code: 529, dur: '1.3s' }, { account: 'MiniMax-01', code: 529, dur: '1.5s' }], clientCode: 529 } },
  { t: '09:19', code: 429, model: 'claude-opus-4', user: 'sy.chen', account: 'Claude-官方-03', cost: null, dur: '0.3s', kind: '上游错误',
    failure: { phase: 'upstream', owner: 'provider', severity: 'P2', message: 'rate_limit_error: Number of request tokens has exceeded your per-minute rate limit (claude-opus-4).', attempts: [{ account: 'Claude-官方-03', code: 429, dur: '0.3s' }, { account: 'Claude-官方-02', code: 200, dur: '12.7s' }], clientCode: 200 } },
  { t: '09:16', code: 200, model: 'claude-haiku-4-5', user: 'na.li', account: 'Claude-官方-03', cost: 0.0007, dur: '0.8s' },
  { t: '09:14', code: 200, model: 'MiniMax-M2', user: 'na.li', account: 'MiniMax-01', cost: 0.0041, dur: '3.1s' },
  { t: '09:12', code: 200, model: 'claude-sonnet-4-5', user: 'yi.lin', account: 'Claude-官方-03', cost: 0.0294, dur: '4.6s' },
  { t: '09:08', code: 200, model: 'MiniMax-M2', user: 'yi.lin', account: 'MiniMax-01', cost: 0.0127, dur: '6.4s' },
];

// Same derivation as shared/data.jsx so these rows open the shared request-detail page.
function vdDeriveLog(l, i) {
  const n = 18 + i;
  const seconds = parseFloat(l.dur);
  const ok = l.code === 200;
  const ttft = ok ? Math.max(0.3, Math.min(seconds * 0.32, 2.4)) : null;
  const inTok = ok ? Math.round((l.cost || 0) * 52000 + 900 + n * 37) : 0;
  const user = DEMO.users.find(u => u.email.startsWith(l.user)) || null;
  const account = DEMO.accounts.find(a => a.name === l.account) || null;
  return {
    ...l,
    id: 9000 - i, // older than every shared sample (9001–9018): 9000 … 8993
    rid: `req_${(0x5f3a91c4 + n * 2654435761 >>> 0).toString(16)}${(0x1b7e + n * 97).toString(16)}`,
    ttft: ttft === null ? null : `${ttft.toFixed(1)}s`,
    stream: ok && i % 3 === 1 ? '非流式' : '流式',
    tokens: ok ? { input: inTok, output: Math.round(seconds * 85 + 40), cacheRead: i % 2 ? Math.round(inTok * 0.6) : 0, cacheWrite: 0 } : null,
    std: l.cost === null ? null : +(l.cost * 1.25).toFixed(4),
    acost: l.cost === null ? null : +(l.cost * 0.42).toFixed(4),
    upstreamModel: UPSTREAM_MODEL[l.model] || l.model,
    key: user && user.keys ? user.keys[0] : { label: '默认', masked: `sk-…${(1000 + n * 7919).toString(36).slice(-4)}` },
    userName: user ? user.name : l.user,
    group: account && account.groups.length ? account.groups[0] : '默认组',
    accountId: account ? account.id : null,
    failure: l.failure || null,
    resolved: false,
  };
}
if (!DEMO.logs.some(l => l.id === 9000)) DEMO.logs = DEMO.logs.concat(VD_EXTRA_LOGS.map(vdDeriveLog));

/* ---------- per-phone memory ---------- */

// SwiftUI keeps a pushed screen's @State while something sits on top of it; this prototype remounts the screen on pop.
// Remember tab / open cards / scroll per account, keyed by the phone's own `initial.v` object so phones never share it.
const vdMemory = new WeakMap();
function vdMem(ctx, id) {
  const key = ctx.v && typeof ctx.v === 'object' ? ctx.v : null;
  if (!key) return {};
  if (!vdMemory.has(key)) vdMemory.set(key, {});
  const all = vdMemory.get(key);
  all[id] = all[id] || {};
  return all[id];
}
function vdForget(ctx, id) {
  const all = ctx.v && vdMemory.get(ctx.v);
  if (all) delete all[id];
}

/* ---------- derived values ---------- */

function vdCaps(a) {
  return [
    a.conc && { label: '并发', used: a.conc[0], limit: a.conc[1] },
    a.rpm && { label: '调度 RPM', used: a.rpm[0], limit: a.rpm[1], note: '自然分钟' },
    a.dayQuota && { label: '日配额', used: a.dayQuota[0], limit: a.dayQuota[1], money: true },
  ].filter(Boolean);
}
const vdRatio = c => (c.ratio !== undefined ? c.ratio : c.used / c.limit);
const vdCapText = c => (c.money ? `${fmt.money(c.used)} / ${fmt.money(c.limit)}` : c.ratio !== undefined ? `${Math.round(c.ratio * 100)}%` : `${c.used}/${c.limit}`);
const vdQuiet = a => ['normal', 'paused', 'inactive'].includes(a.state);

// Counts use the same sources as the logs page each row opens (LOG_SOURCES), so a row's number matches what you land on.
function vdRecords(a) {
  const mine = DEMO.logs.filter(l => l.account === a.name);
  return { recent: mine.slice(0, 5), errors: mine.filter(LOG_SOURCES.errors).length, upstream: mine.filter(LOG_SOURCES.upstream).length };
}

// Hourly actual cost for this account today (dashboard/trend?account_id=); demo spreads todayCost over the site's hourly shape.
function vdHourly(a) {
  const shape = DEMO.hourlyToday;
  const sum = shape.reduce((s, v) => s + v, 0);
  return shape.map(v => (v / sum) * (a.todayCost || 0));
}

// Exhausted windows or quotas: recovering clears the block, but the next request will likely be limited again.
function vdExhausted(a) {
  return [
    ...(VD_UPSTREAM[a.id] || []).filter(w => w.ratio >= 1).map(w => `${w.label}窗口`),
    a.dayQuota && a.dayQuota[0] >= a.dayQuota[1] && '日配额',
  ].filter(Boolean);
}

/* ---------- actions ---------- */

// Every action the account currently offers, plus which one is primary.
function vdModel(ctx, a) {
  const id = a.id;
  const test = { key: 'test', label: '测试连接', short: '测试', icon: 'wave', run: () => ctx.openSheet({ kind: 'test', id }) };
  const pause = { key: 'pause', label: '停止调度', icon: 'pauseFill', run: () => ctx.updateAccount(id, { state: 'paused' }, { text: '已停止调度', undo: true, icon: 'pauseFill', tone: 'neutral' }) };
  const resume = { key: 'resume', label: '启用调度', icon: 'play', run: () => ctx.updateAccount(id, { state: 'normal' }, { text: '已启用调度', undo: true, icon: 'play' }) };
  const enable = { key: 'enable', label: '启用账号', icon: 'play', run: () => ctx.updateAccount(id, { state: 'normal' }, { text: '已启用账号 · 参与调度', undo: true, icon: 'play' }) };
  const refresh = a.type === 'OAuth' ? { key: 'refresh', label: '刷新令牌', icon: 'refresh', run: () => ctx.showToast({ text: '已刷新令牌', icon: 'refresh' }) } : null;
  const full = vdExhausted(a);
  const again = full.length ? `${full.join('、')}已用满，恢复后可能很快再次${a.state === 'rate_limited' ? '限流' : '受限'}。` : '';
  const recover = {
    key: 'recover', label: '恢复状态', icon: 'restore',
    run: () => ctx.confirm({
      title: `恢复「${a.name}」？`,
      message: `${a.modelLimits && a.modelLimits.length ? `清除限流和 ${a.modelLimits.length} 项模型限流` : `清除${STATE_META[a.state].label.replace(/中$/, '')}状态`}，账号立即参与调度。${again}`,
      actions: [
        { label: '恢复状态', role: 'default', onPress: () => ctx.updateAccount(id, { state: 'normal', modelLimits: [] }, { text: '已恢复 · 参与调度' }) },
        { label: '取消', role: 'cancel' },
      ],
    }),
  };
  const restoreOnly = () => ctx.updateAccount(id, { state: 'paused' }, { text: '已恢复 · 仍暂停调度', icon: 'pauseFill', tone: 'neutral' });
  const recoverError = {
    key: 'recoverError', label: '恢复并启用调度', icon: 'restore',
    run: () => ctx.confirm({
      title: `恢复「${a.name}」？`,
      message: '清除错误状态。错误账号恢复后仍暂停调度，可以同时启用；凭据没有更换时可能再次出错。',
      actions: [
        { label: '恢复并启用调度', role: 'default', onPress: () => ctx.updateAccount(id, { state: 'normal' }, { text: '已恢复 · 已启用调度' }) },
        { label: '仅恢复状态', onPress: restoreOnly },
        { label: '取消', role: 'cancel' },
      ],
    }),
  };
  const recoverOnly = {
    key: 'recoverOnly', label: '仅恢复状态', note: '清除错误，保持暂停', icon: 'restore',
    run: () => ctx.confirm({
      title: `只恢复「${a.name}」的状态？`,
      message: '清除错误状态，账号保持暂停调度。',
      actions: [{ label: '恢复状态', role: 'default', onPress: restoreOnly }, { label: '取消', role: 'cancel' }],
    }),
  };
  if (a.state === 'error') return { primary: recoverError, others: [test], test, refresh, recoverOnly };
  if (NEEDS_ACTION.includes(a.state)) return { primary: recover, others: [test, pause], test, pause, refresh };
  if (a.state === 'inactive') return { primary: enable, others: [test], test, refresh };
  if (a.state === 'paused') return { primary: resume, others: [test], test, refresh };
  return { primary: test, others: [pause], test, pause, refresh, calm: true };
}

/* ---------- status card ---------- */

function VdHero({ ctx, a, cta }) {
  const { skin, elapsed } = ctx;
  const meta = STATE_META[a.state];
  const tone = toneOf(a.state);
  if (vdQuiet(a)) {
    return (
      <div className={cx('hero hero-quiet vd-quiet', a.state === 'normal' ? 'tone-ok' : 'tone-neutral')}>
        <skin.Glyph state={a.state} />
        <span className="vd-quiet-text">{a.state === 'normal' ? '正常 · 参与调度' : `${meta.label} · 不参与调度`}</span>
        {cta}
      </div>
    );
  }
  const secs = remaining(a, elapsed);
  const until = fmt.clock(DEMO_CLOCK_BASE + (elapsed + (secs || 0)) * 1000);
  return (
    <div className={cx('hero', `tone-${tone}`, skin.rowClass(tone))}>
      <div className="hero-top"><skin.Badge state={a.state} big /><span className="hero-cause">{a.state === 'error' ? a.errorAgo : a.cause}</span></div>
      {meta.timed ? (
        <>
          <div className="hero-figure"><skin.Num size="xl" className="tone-text">{fmt.countdown(secs)}</skin.Num></div>
          <div className="hero-sub">后自动恢复 · 预计 <span className="num">{until}</span></div>
        </>
      ) : (
        <>
          <div className="hero-error">{a.error}</div>
          <div className="vd-hero-note"><Icon name="pause" size={15} weight={2.2} />出错后已停止调度</div>
        </>
      )}
      {a.modelLimits && a.modelLimits.length > 0 && (
        <div className="hero-models tone-model">
          <div className="hero-models-title"><Icon name="cube" size={15} /> 模型限流 {a.modelLimits.length}</div>
          {a.modelLimits.map(m => (
            <div key={m.model} className="hero-model"><span className="mono">{m.model}</span><span className="num">{fmt.minutesLeft(m.resetIn - elapsed)}后</span></div>
          ))}
        </div>
      )}
      {cta}
    </div>
  );
}

/* ---------- ⋯ menu (pull-down from the nav button) ---------- */

// The shared Icon set has no copy glyph; same 24-grid stroke style.
function VdCopyIcon() {
  return (
    <svg width="18" height="18" viewBox="0 0 24 24" aria-hidden="true" style={{ flex: 'none', display: 'block' }}>
      <g fill="none" stroke="currentColor" strokeWidth="2.1" strokeLinecap="round" strokeLinejoin="round"><rect x="8" y="8" width="12" height="12" rx="2.5" /><path d="M16 8V6a2 2 0 0 0-2-2H6a2 2 0 0 0-2 2v8a2 2 0 0 0 2 2h2" /></g>
    </svg>
  );
}

function VdMenu({ groups, onClose }) {
  return (
    <div className="overlay vd-menu-layer" onClick={onClose}>
      <div className="vd-menu glass" role="menu" onClick={e => e.stopPropagation()}>
        {groups.map((g, gi) => (
          <React.Fragment key={gi}>
            {gi > 0 && <div className="vd-menu-sep" />}
            {g.map(item => (
              <button key={item.key} role="menuitem" className="vd-mi" onClick={() => { onClose(); item.run(); }}>
                {item.icon === 'copy' ? <VdCopyIcon /> : <Icon name={item.icon} size={18} weight={2.1} />}
                <span className="vd-mi-label">{item.label}{item.note && <small>{item.note}</small>}</span>
              </button>
            ))}
          </React.Fragment>
        ))}
      </div>
    </div>
  );
}

/* ---------- information blocks (identical in all three layouts) ---------- */

function VdCapLines({ ctx, caps }) {
  const { skin } = ctx;
  return caps.map(c => (
    <div key={c.label} className="cap-line pad">
      <span className="cap-label">{c.label}</span>
      <skin.Capacity used={c.used} limit={c.limit} ratio={c.ratio} money={c.money} wide />
      {c.note && <small className="cap-note">{c.note}</small>}
    </div>
  ));
}

function VdUpstream({ ctx, windows }) {
  const { skin } = ctx;
  return windows.map(w => (
    <div key={w.label} className="cap-line pad">
      <span className="cap-label">{w.label}</span>
      <skin.Capacity ratio={w.ratio} wide />
      <small className="cap-note num vd-reset">{w.reset}</small>
    </div>
  ));
}

function VdToday({ ctx, a }) {
  const { skin } = ctx;
  return (
    <>
      <div className="grid3 pad">
        <div><small data-kind="actual">实际</small><skin.Money value={a.todayCost} size="l" kind="actual" /></div>
        <div><small data-kind="cost">成本</small><skin.Money value={a.todayAccountCost ?? null} size="l" kind="cost" /></div>
        <div><small data-kind="standard">标准</small><skin.Money value={a.todayStd ?? null} size="l" kind="standard" /></div>
      </div>
      <div className="kv-row pad">
        <span>请求 <b className="num">{fmt.grouped(a.todayReq)}</b></span>
        <span>Tokens <b className="num">{fmt.compact(a.todayTokens ?? null)}</b></span>
      </div>
    </>
  );
}

function VdBars({ a }) {
  const vals = vdHourly(a);
  const W = 329, H = 96, n = 24, slot = (W - 8) / n, base = H - 18;
  const max = Math.max(...vals) * 1.12;
  const x = i => 4 + i * slot + slot / 2;
  const y = v => base - (v / max) * (base - 10);
  const last = vals.length - 1;
  return (
    <svg className="vd-bars" viewBox={`0 0 ${W} ${H}`} width="100%" role="img" aria-label="今天每小时实际扣费">
      <line className="chart-grid" x1="0" x2={W} y1={y(max / 2)} y2={y(max / 2)} />
      <line className="chart-base" x1="0" x2={W} y1={base} y2={base} />
      {vals.map((v, i) => (
        <rect key={i} className={cx('chart-bar', i === last && 'chart-bar-now')} x={x(i) - slot * 0.31} y={y(v)} width={slot * 0.62} height={base - y(v)} rx="1.5" />
      ))}
      {[0, 6, 12, 18].map(h => <text key={h} className="chart-axis" x={x(h) - slot / 2} y={H - 4}>{h}时</text>)}
      <text className="chart-axis" x={x(last) - 8} y={H - 4}>现在</text>
    </svg>
  );
}

function VdRecordLinks({ ctx, a, rec }) {
  const { skin } = ctx;
  const go = scope => () => ctx.push({ kind: 'logs', scope, account: a.name });
  return (
    <>
      <Row skin={skin} tone="none" lead={<span className="lead-icon dim"><Icon name="octagon" /></span>} onClick={go('errors')}>
        <div className="row-top"><span className="row-title">错误请求</span><span className="row-right num">{rec.errors} 条</span></div>
        <div className="row-meta">请求最终失败，客户端收到错误</div>
      </Row>
      <Row skin={skin} tone="none" lead={<span className="lead-icon dim"><Icon name="signal" /></span>} onClick={go('upstream')}>
        <div className="row-top"><span className="row-title">上游错误</span><span className="row-right num">{rec.upstream} 条</span></div>
        <div className="row-meta">上游返回错误，含已自动重试成功的</div>
      </Row>
      <Row skin={skin} tone="none" lead={<span className="lead-icon dim"><Icon name="list" /></span>} onClick={go('usage')}>
        <div className="row-top"><span className="row-title">使用记录</span></div>
      </Row>
    </>
  );
}

// Core LogRow with line 2 = 用户 · Key 名称: inside one account's page the account name would repeat on every row.
function VdLogRow({ ctx, l }) {
  const { skin } = ctx;
  const tone = logTone(l);
  return (
    <div className={cx('row lg-row tappable', skin.rowClass(tone), `tone-${tone === 'none' ? 'ok' : tone}`)} onClick={() => ctx.push({ kind: 'request', id: l.id })}>
      <div className="lg-lead"><span className="num lg-clock">{l.t}</span><skin.Code code={l.code} /></div>
      <div className="lg-main">
        <span className="lg-model mono">{l.model}</span>
        <span className="lg-who">{l.userName} · {l.key.label}</span>
      </div>
      <div className="lg-side">
        <b className={cx('num lg-cost', l.cost === null && 'is-missing')}>{l.cost === null ? '—' : fmt.money(l.cost, { digits: l.cost < 1 ? 4 : 2 })}</b>
        <span className="num lg-time">{l.ttft || '—'}/{l.dur}</span>
      </div>
      <div className="row-chev"><Icon name="chevron" size={13} weight={2.6} /></div>
    </div>
  );
}

function VdTests({ test }) {
  if (!test) return <div className="empty pad vd-empty">没有定时测试计划<small>计划在 Web 中添加</small></div>;
  return test.results.map(([t, ok, ms, msg]) => (
    <div key={t} className={cx('vd-test pad', ok ? 'tone-ok' : 'tone-critical')}>
      <span className="vd-test-ico"><Icon name={ok ? 'checkCircle' : 'octagon'} size={17} weight={2.2} /></span>
      <span className="num vd-test-t">{t}</span>
      <span className={cx('vd-test-msg', !ok && 'mono')}>{ok ? '成功' : msg}</span>
      <span className="num vd-test-ms">{ms}</span>
    </div>
  ));
}

function VdProfile({ a }) {
  return (
    <div className="kv-grid pad">
      <KV label="平台" value={a.platform} /><KV label="类型" value={a.type} />
      <KV label="分组" value={a.groups.join('、') || '未分组'} /><KV label="优先级" value={a.priority} />
      <KV label="代理" value={a.proxy || '—'} /><KV label="到期" value={a.expires || '—'} />
    </div>
  );
}

function VdModels({ ctx, a, models }) {
  const limited = Object.fromEntries((a.modelLimits || []).map(m => [m.model, m]));
  return (
    <div className="vd-models pad">
      {models.map(m => (
        <span key={m} className={cx('vd-model', limited[m] && 'tone-model is-limited')}>
          <span className="mono">{m}</span>
          {limited[m] && <small className="num">限流 {fmt.minutesLeft(limited[m].resetIn - ctx.elapsed)}</small>}
        </span>
      ))}
    </div>
  );
}

// The four groups (= the segmented tabs = the fold cards), each a list of titled blocks; empty blocks drop out.
function vdGroups(ctx, a) {
  const caps = vdCaps(a);
  const up = VD_UPSTREAM[a.id] || [];
  const rec = vdRecords(a);
  const test = VD_TESTS[a.id];
  const models = VD_MODELS[a.platform] || [];
  const peak = Math.max(...vdHourly(a));
  const tight = [...caps.map(c => [c.label, vdCapText(c), vdRatio(c)]), ...up.map(w => [`${w.label}窗口`, `${Math.round(w.ratio * 100)}%`, w.ratio])]
    .sort((p, q) => q[2] - p[2]).slice(0, 2);
  const lastTest = test && test.results[0];
  const groups = [
    { key: 'cap', label: '容量', icon: 'gauge', meta: '刚刚', sum: tight.map(([l, t]) => `${l} ${t}`).join(' · '), blocks: [
      caps.length > 0 && { key: 'caps', title: '容量', meta: '刚刚', body: <VdCapLines ctx={ctx} caps={caps} /> },
      up.length > 0 && { key: 'upstream', title: '上游用量窗口', meta: `${a.platform} · 1 分钟前`, body: <VdUpstream ctx={ctx} windows={up} /> },
    ] },
    { key: 'usage', label: '用量', icon: 'dollar', meta: '00:00 起', sum: `实际 ${fmt.money(a.todayCost)} · 请求 ${fmt.grouped(a.todayReq)}${a.todayCost ? ` · 峰值 ${fmt.money(peak)}` : ''}`, blocks: [
      { key: 'today', title: '今日', meta: '00:00 起', body: <VdToday ctx={ctx} a={a} /> },
      { key: 'hourly', title: '每小时实际扣费', meta: a.todayCost ? `峰值 ${fmt.money(peak)}` : null,
        body: a.todayCost ? <div className="vd-bars-wrap"><VdBars a={a} /></div> : <div className="empty pad">今天还没有扣费</div> },
    ] },
    { key: 'rec', label: '记录', icon: 'list', meta: '近 24 小时', sum: [
      rec.recent.length ? `上游错误 ${rec.upstream} · 错误请求 ${rec.errors}` : '近 24 小时没有请求',
      lastTest ? `测试${lastTest[1] ? '成功' : '失败'}` : '没有定时测试',
    ].join(' · '), blocks: [
      { key: 'links', title: '请求记录', meta: '近 24 小时', body: <VdRecordLinks ctx={ctx} a={a} rec={rec} /> },
      { key: 'recent', title: '最近请求', meta: rec.recent.length ? '金额 · 首字/耗时' : null,
        body: rec.recent.length ? rec.recent.map(l => <VdLogRow key={l.id} ctx={ctx} l={l} />) : <div className="empty pad">近 24 小时没有请求</div> },
      { key: 'tests', title: '定时测试', meta: test ? test.plan : null, body: <VdTests test={test} /> },
    ] },
    { key: 'prof', label: '档案', icon: 'server', meta: `#${a.id}`, sum: `${a.groups.join('、') || '未分组'} · 优先级 ${a.priority} · ${models.length} 个模型`, blocks: [
      { key: 'profile', title: '档案', meta: `#${a.id}`, body: <VdProfile a={a} /> },
      models.length > 0 && { key: 'models', title: '可用模型', meta: `${models.length} 个`, body: <VdModels ctx={ctx} a={a} models={models} /> },
    ] },
  ];
  return groups.map(g => ({ ...g, blocks: g.blocks.filter(Boolean) })).filter(g => g.blocks.length);
}

/* ---------- information layouts ---------- */

function VdSections({ ctx, blocks }) {
  return blocks.map(b => <Section key={b.key} skin={ctx.skin} title={b.title} meta={b.meta}>{b.body}</Section>);
}

function VdAllBody({ ctx, groups }) {
  return <VdSections ctx={ctx} blocks={groups.flatMap(g => g.blocks)} />;
}

// iOS: ScrollView + LazyVStack(pinnedViews: [.sectionHeaders]) with the Picker as the pinned header (cards drawn by hand;
// insetGrouped List headers do not pin). Switching while pinned keeps the control pinned, so each tab has at least a screen of room.
function VdSegBody({ ctx, groups, mem }) {
  const keys = groups.map(g => g.key);
  const [tab, setTab] = useState(() => [mem.tab, ctx.v && ctx.v.vdTab].find(k => keys.includes(k)) || keys[0]);
  const [pinned, setPinned] = useState(false);
  const anchor = useRef(null);
  const where = () => {
    const el = anchor.current;
    const sc = el && el.closest('.scroll');
    return sc ? { sc, top: el.getBoundingClientRect().top - sc.getBoundingClientRect().top + sc.scrollTop } : null;
  };
  useEffect(() => {
    const first = where();
    if (!first) return undefined;
    const onScroll = () => { const w = where(); setPinned(Boolean(w) && w.sc.scrollTop >= w.top - 0.5); };
    onScroll();
    first.sc.addEventListener('scroll', onScroll, { passive: true });
    return () => first.sc.removeEventListener('scroll', onScroll);
  }, []);
  const pick = key => {
    const w = where();
    const wasPinned = Boolean(w) && w.sc.scrollTop >= w.top - 0.5;
    mem.tab = key;
    setTab(key);
    if (wasPinned) requestAnimationFrame(() => { w.sc.scrollTop = w.top; });
  };
  const group = groups.find(g => g.key === tab) || groups[0];
  return (
    <>
      <div ref={anchor} className="vd-seg-anchor" />
      <div className={cx('vd-segbar', pinned && 'is-pinned')}><Segmented items={groups.map(g => ({ key: g.key, label: g.label }))} value={group.key} onChange={pick} /></div>
      <div className="vd-panel" key={group.key}><VdSections ctx={ctx} blocks={group.blocks} /></div>
    </>
  );
}

// iOS: insetGrouped List; each Section holds one DisclosureGroup with a custom label (title + one-line summary).
function VdFoldBody({ ctx, groups, mem }) {
  const want = (ctx.v && ctx.v.vdOpen) || 'cap';
  const [open, setOpen] = useState(() => mem.open || { [groups.some(g => g.key === want) ? want : groups[0].key]: true });
  const toggle = key => {
    const next = { ...open, [key]: !open[key] };
    mem.open = next;
    setOpen(next);
  };
  return (
    <div className="vd-folds">
      {groups.map(g => (
        <section key={g.key} className={cx('vd-fold', open[g.key] && 'open')}>
          <button className="vd-fold-head" aria-expanded={Boolean(open[g.key])} onClick={() => toggle(g.key)}>
            <span className="vd-fold-ico"><Icon name={g.icon} size={17} weight={2.1} /></span>
            <span className="vd-fold-text">
              <span className="vd-fold-title">{g.label}</span>
              <span className="vd-fold-sum num">{open[g.key] ? g.meta : g.sum}</span>
            </span>
            <span className="vd-fold-chev"><Icon name="chevron" size={13} weight={2.6} /></span>
          </button>
          {open[g.key] && (
            <div className="vd-fold-body">
              {g.blocks.map(b => (
                <div key={b.key} className="vd-fold-block">
                  {b.title !== g.label && <div className="vd-sub"><b>{b.title}</b>{b.meta && <span className="num">{b.meta}</span>}</div>}
                  {b.body}
                </div>
              ))}
            </div>
          )}
        </section>
      ))}
    </div>
  );
}

/* ---------- screen ---------- */

function VdAccountDetail({ ctx, id }) {
  const v = ctx.v || {};
  const act = v.vdAct || 'row';
  const info = v.vdInfo || 'all';
  const a = ctx.accounts[id];
  const mem = vdMem(ctx, id);
  const root = useRef(null);
  const [menu, setMenu] = useState(Boolean(v.vdMenu));
  const model = vdModel(ctx, a);
  const groups = vdGroups(ctx, a);
  const quiet = vdQuiet(a);
  const p = model.primary;

  // Restore the remembered scroll offset (see vdMem); leaving with Back forgets it, like a fresh push in SwiftUI.
  React.useLayoutEffect(() => {
    const sc = root.current && root.current.querySelector('.scroll');
    if (!sc) return undefined;
    if (mem.scroll) sc.scrollTop = mem.scroll;
    const save = () => { mem.scroll = sc.scrollTop; };
    sc.addEventListener('scroll', save, { passive: true });
    return () => sc.removeEventListener('scroll', save);
  }, []);
  const navCtx = { ...ctx, pop: () => { vdForget(ctx, id); ctx.pop(); } };

  // In "menu" mode the menu carries every non-primary action; elsewhere it only holds what has no button.
  const inMenu = act === 'menu';
  const menuGroups = [
    [inMenu && model.test, model.refresh],
    [inMenu && model.pause, inMenu && model.recoverOnly],
    [
      { key: 'copy', label: '复制账号 ID', note: `#${a.id}`, icon: 'copy', run: () => ctx.showToast({ text: `已复制账号 ID ${a.id}`, icon: 'check', tone: 'neutral' }) },
      { key: 'web', label: '在 Web 中打开', icon: 'web', run: () => ctx.showToast({ text: '将在 Safari 打开该账号', icon: 'web', tone: 'neutral' }) },
    ],
  ].map(g => g.filter(x => x && x !== p)).filter(g => g.length);

  const cta = inMenu && (quiet
    ? <button className={cx('vd-cta vd-cta-s', model.calm && 'is-plain')} onClick={p.run}><Icon name={p.icon} size={15} weight={2.4} /><span>{p.label}</span></button>
    : <button className="vd-cta" onClick={p.run}><Icon name={p.icon} size={17} weight={2.4} /><span>{p.label}</span></button>);

  const rowItems = [p, ...model.others];
  const row = act === 'row' && (
    <div className="actions">
      {rowItems.map((o, i) => (
        <button key={o.key} className={cx('act', i === 0 && 'act-primary')} onClick={o.run}>
          <Icon name={o.icon} size={16} weight={2.4} /><span>{rowItems.length > 2 ? o.short || o.label : o.label}</span>
        </button>
      ))}
    </div>
  );

  // iOS: .toolbar(.hidden, for: .tabBar) on the pushed detail + ToolbarItemGroup(placement: .bottomBar) for the secondary
  // actions (no dividers inside a group) and the primary in its own group with .glassProminent. Narrow widths / large type:
  // ViewThatFits falls back to icon-only Labels (accessibilityLabel keeps the words).
  const toolbar = act === 'toolbar' && (
    <>
      <div className="vd-edge" aria-hidden="true" />
      <div className="vd-toolbar" role="toolbar" aria-label="账号操作">
        <div className="vd-tb-group glass">
          {model.others.map(o => (
            <button key={o.key} className="vd-tb-btn" onClick={o.run} aria-label={o.label}><Icon name={o.icon} size={17} weight={2.3} /><span>{model.others.length > 1 ? o.short || o.label : o.label}</span></button>
          ))}
        </div>
        <button className="vd-tb-prim" onClick={p.run}><Icon name={p.icon} size={18} weight={2.4} /><span>{p.label}</span></button>
      </div>
    </>
  );

  const more = (
    <button className={cx('glass-btn vd-more', menu && 'on')} aria-label="更多操作" aria-haspopup="menu" aria-expanded={menu} onClick={() => setMenu(m => !m)}>
      <Icon name="more" size={19} weight={2.2} />
    </button>
  );

  const Body = info === 'seg' ? VdSegBody : info === 'fold' ? VdFoldBody : VdAllBody;
  return (
    <div ref={root} className={cx('vd', `vd-act-${act}`, `vd-info-${info}`, act === 'toolbar' && 'vd-hide-tabs')}>
      <Screen ctx={ctx} footer={toolbar} nav={<NavBar ctx={navCtx} back title={a.name} subtitle={`${a.platform} · ${a.type}`} trailing={more} />}>
        <div className="detail-head"><VdHero ctx={ctx} a={a} cta={cta} />{row}</div>
        <Body ctx={ctx} a={a} groups={groups} mem={mem} />
      </Screen>
      {menu && <VdMenu groups={menuGroups} onClose={() => setMenu(false)} />}
    </div>
  );
}

mvRegister('accountDetail', 'vd', VdAccountDetail);
