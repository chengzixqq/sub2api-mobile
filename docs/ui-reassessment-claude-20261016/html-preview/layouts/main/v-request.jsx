/* v-request：请求详情（槽 request）的两种替代设计，base 是 00-core.jsx 里的分区式。
   receipt  —— 收据式：票根放大金额（成功）或大状态码（失败），失败时错误信息和“标记已处理”紧跟在状态下面；
               撕口下面是一条条“标签—值”明细行；标记已处理后在票根上盖章（写标记人与时间）。
   timeline —— 时间线式：收到请求 → 进入分组 → 每次上游尝试（429 / 200 …）→ 首字 → 完成 / 返回客户端，
               节点旁标相对请求开始的时间，尝试节点下画瀑布条；标记已处理作为最后一个节点出现。
   成功页和失败页可以分开选：initial.v = { request: 'mix', requestOk: 'receipt', requestFail: 'timeline' }；
   requestOk / requestFail 缺省时回落到 v.request（'base' 即分区式）。

   实现备注（数据口径，后端不存在的不画）：
   - 每段尝试的位置：上游错误事件只有 at_unix_ms（错误发生时写入），没有单段耗时。每段的起点 = 上一段 at_unix_ms 相对
     请求开始的偏移，终点 = 本段 at_unix_ms 的偏移；最后一段截到整条请求的耗时。整条请求耗时：错误请求取自身耗时，
     上游错误记录取同 request_id 用量明细的 duration_ms（GET admin/usage?request_id=），界面上标“整个请求”。
     演示数据只给了每段时长，这里按首尾相接换算成偏移，并截到总耗时，所以三处总耗时一致。
   - 首字：first_token_ms 只在流式分支赋值，非流式为 null → 不画首字节点和刻度，统计格显示“—”。
   - 上游尝试只来自 request-errors/:id/upstream-errors（owner=provider，phase 为 upstream / account_auth）；
     请求校验等其他阶段不画编号尝试节点。
   - 标记已处理：PUT …/resolve 后服务端保存 resolved / resolved_at / resolved_by_user_name；原型用每台手机一份的内存表模拟，
     去别的页面再回来仍保留。
   - SwiftUI：收据外形用自定义 Shape（两侧半圆缺口 + 底部锯齿）+ stroke + shadow；印章 overlay + rotationEffect，
     弹入动画在“减弱动态效果”下关闭；时间轴连接线用 overlay，瀑布条用 GeometryReader。“标签—值”行和节点标题行用
     ViewThatFits，辅助功能字号下改成上下两行；每个时间线节点 accessibilityElement(children: .combine)，读成
     “第 2 次尝试，GLM-直连-01，504”；“收到请求”行 accessibilityLabel“收到请求，用户王小明”+ accessibilityHint“打开用户”。 */

const VRQ_CODE_TEXT = { 200: '成功', 400: '请求参数错误', 401: '凭据无效', 429: '上游限流', 504: '上游超时', 529: '上游过载' };
const VRQ_UPSTREAM_PHASES = ['upstream', 'account_auth'];
const VRQ_ME = 'admin'; // resolved_by_user_name of the signed-in admin (demo)

// 演示数据：三条“上游错误、重试成功”的记录，在用量明细里各有一条同 request_id 的成功记录。共享的 18 条日志没有收录，
// 这里按同一请求补出来：账号 = 成功那次尝试的账号，耗时 = 整条请求，首字从请求开始计。
const VRQ_TWIN_USAGE = {
  9017: { ttft: '2.3s', cost: 0.2612, tokens: { input: 4120, output: 907, cacheRead: 2470, cacheWrite: 0 } },
  9015: { ttft: '0.9s', cost: 0.0046, tokens: { input: 1530, output: 278, cacheRead: 0, cacheWrite: 0 } },
  9007: { ttft: '2.6s', cost: 0.0581, tokens: { input: 6840, output: 771, cacheRead: 4100, cacheWrite: 1024 } },
};

function vrqSecs(text) { return text ? parseFloat(text) : null; }
function vrqDur(s) { return s === null || s === undefined ? '—' : `${s.toFixed(1)}s`; }

// Same colouring as the status-code chip on log rows.
function vrqCodeTone(code) {
  if (code === 200) return 'ok';
  return code === 429 || code === 504 ? 'caution' : 'critical';
}

function vrqTwin(src) {
  const extra = src && src.failure && VRQ_TWIN_USAGE[src.id];
  if (!extra) return null;
  const tries = src.failure.attempts;
  const winner = tries[tries.length - 1];
  const account = DEMO.accounts.find(a => a.name === winner.account);
  const secs = tries.reduce((s, a) => s + vrqSecs(a.dur), 0);
  return {
    ...src, ...extra, id: `u${src.id}`, twinOf: src.id, code: 200, kind: undefined, failure: null, resolved: false,
    account: winner.account, accountId: account ? account.id : null, dur: `${secs.toFixed(1)}s`, stream: '流式',
    std: +(extra.cost * 1.25).toFixed(4), acost: +(extra.cost * 0.42).toFixed(4), retries: tries,
  };
}

// Route ids are numbers for the shared logs and "u<id>" for the usage record behind an upstream error.
function vrqLog(id) {
  if (typeof id === 'string' && id[0] === 'u') return vrqTwin(DEMO.logs.find(x => x.id === Number(id.slice(1))));
  return DEMO.logs.find(x => x.id === id);
}

// Attempts are laid end to end on the request's own clock and clipped to the request total.
function vrqAttempts(l, tries, total) {
  const recordIndex = l.kind === '上游错误' ? tries.findIndex(a => a.code === l.code) : -1;
  let at = 0;
  return tries.map((a, i) => {
    const last = i === tries.length - 1;
    const start = Math.min(at, total);
    const end = last ? total : Math.min(at + vrqSecs(a.dur), total);
    at = end;
    const next = tries[i + 1];
    const account = DEMO.accounts.find(x => x.name === a.account);
    const note = a.code === 200 ? '结果返回客户端'
      : !next ? '错误返回客户端'
        : next.account === a.account ? '同一账号重试' : `切换到 ${next.account}`;
    return { ...a, start, end, last, accountId: account ? account.id : null, note, tone: vrqCodeTone(a.code), isRecord: i === recordIndex };
  });
}

// One normalised view of a log entry shared by both variants.
function vrqModel(l) {
  const f = l.failure;
  const ok = l.code === 200;
  const upstreamRecord = l.kind === '上游错误';
  const viaUpstream = !f || VRQ_UPSTREAM_PHASES.includes(f.phase);
  const tries = !viaUpstream ? [] : f ? f.attempts : l.retries || [{ account: l.account, code: 200, dur: l.dur }];
  const total = upstreamRecord ? tries.reduce((s, a) => s + vrqSecs(a.dur), 0) : vrqSecs(l.dur);
  const clientCode = f ? f.clientCode : l.code;
  const ss = String(7 + ((l.twinOf || l.id) % 50)).padStart(2, '0');
  return {
    l, f, ok, clientCode, viaUpstream, total,
    attempts: vrqAttempts(l, tries, total),
    totalLabel: upstreamRecord ? '整个请求' : '总耗时',
    recovered: !ok && clientCode === 200,
    failed: clientCode !== 200,
    switched: tries.length > 1 && tries[0].account !== tries[tries.length - 1].account,
    first: ok && l.stream !== '非流式' ? vrqSecs(l.ttft) : null,
    twin: upstreamRecord && clientCode === 200 ? vrqTwin(l) : null,
    user: DEMO.users.find(u => u.name === l.userName) || null,
    time: `${l.t}:${ss}`,
    clock: `10/16 ${l.t}:${ss}`,
    title: ok ? '请求详情' : upstreamRecord ? '上游错误' : '失败请求',
  };
}


/* ---------- 成功 / 失败分开选 ---------- */

const VRQ_IMPL = {}; // filled with VrqReceipt / VrqTimeline below

function vrqPickKey(ctx, ok) {
  const v = ctx.v || {};
  return (ok ? v.requestOk : v.requestFail) || v.request || 'base';
}

function VrqDispatch({ ctx, id }) {
  const l = vrqLog(id);
  const key = vrqPickKey(ctx, l.code === 200);
  const slots = MV.slots.request || {};
  // A synthetic usage record only exists in these variants; base looks rows up in DEMO.logs.
  const Comp = VRQ_IMPL[key] || (l.twinOf ? VRQ_IMPL.receipt : slots[key] || slots.base);
  return <Comp ctx={ctx} id={id} />;
}

// "对应用量明细": the usage record with the same request_id when the success page is one of ours, otherwise the
// usage list filtered to the account that finally answered.
function vrqUsageRoute(ctx, m) {
  if (VRQ_IMPL[vrqPickKey(ctx, true)] && m.twin) return { kind: 'request', id: m.twin.id };
  const winner = m.attempts[m.attempts.length - 1];
  return { kind: 'logs', scope: 'usage', account: winner ? winner.account : m.l.account };
}


/* ---------- 标记已处理（离开再回来仍保留） ---------- */

// ctx.v is the phone's own initial.v object, so each phone keeps its own table, like one server per phone.
const VRQ_RESOLVED = new WeakMap();

function vrqResolvedTable(ctx) {
  if (!VRQ_RESOLVED.has(ctx.v)) VRQ_RESOLVED.set(ctx.v, new Map());
  return VRQ_RESOLVED.get(ctx.v);
}

function useVrqResolve(ctx, l) {
  const table = vrqResolvedTable(ctx);
  const [state, setState] = useState(() => (table.has(l.id) ? table.get(l.id) : l.resolved ? { at: '—', by: '—' } : null));
  const write = next => { table.set(l.id, next); setState(next); };
  const mark = () => {
    write({ at: fmt.clock(DEMO_CLOCK_BASE + ctx.elapsed * 1000), by: VRQ_ME });
    ctx.showToast({ text: '已标记为已处理', icon: 'checkCircle', undo: () => write(null) });
  };
  const unmark = () => { write(null); ctx.showToast({ text: '已改回未处理', icon: 'restore', tone: 'neutral' }); };
  return { resolved: state !== null, at: state && state.at, by: state && state.by, mark, unmark };
}


/* ---------- 共用 ---------- */

function VrqNav({ ctx, m }) {
  return <NavBar ctx={ctx} back title={m.title} subtitle={`${m.clock} · ${m.l.kind || '用量明细'}`} trailing={<GlassButton icon="more" />} />;
}

function VrqActions({ ctx, m, res }) {
  if (m.ok) return null;
  return (
    <div className="actions">
      {res.resolved
        ? <ActionButton label="已处理" icon="check" onClick={res.unmark} />
        : <ActionButton label="标记已处理" icon="check" primary onClick={res.mark} />}
      {m.f && m.f.owner === 'client'
        ? m.user && <ActionButton label="查看用户" icon="people" onClick={() => ctx.push({ kind: 'user', id: m.user.id })} />
        : m.l.accountId && <ActionButton label="查看账号" icon="server" onClick={() => ctx.push({ kind: 'account', id: m.l.accountId })} />}
    </div>
  );
}

function vrqCopy(ctx) {
  return () => ctx.showToast({ text: '已复制请求 ID', icon: 'check', tone: 'neutral' });
}

function vrqGoAccount(ctx, accountId) {
  return accountId ? () => ctx.push({ kind: 'account', id: accountId }) : undefined;
}


/* ---------- 收据式 ---------- */

function VrqLine({ label, kind, children, onClick, tag, chevron = true, a11y }) {
  return (
    <div className={cx('rqr-line', onClick && 'tappable')} onClick={onClick} role={onClick ? 'button' : undefined} aria-label={a11y}>
      <span className="rqr-label">{kind ? <small data-kind={kind}>{label}</small> : label}{tag && <em className="rqr-tag">{tag}</em>}</span>
      <span className="rqr-value">{children}</span>
      {onClick && chevron && <span className="rqr-chev"><Icon name="chevron" size={12} weight={2.6} /></span>}
    </div>
  );
}

function VrqReceiptStub({ ctx, m, res }) {
  const { l, f } = m;
  if (m.ok) {
    return (
      <div className="rqr-stub tone-ok">
        <div className="rqr-merchant mono">{l.model}</div>
        <div className="rqr-big-label">实际扣费</div>
        <div className="rqr-big num">{fmt.money(l.cost, { digits: 4 })}</div>
        <div className="rqr-status tone-text"><Icon name="checkCircle" size={15} weight={2.4} />成功</div>
      </div>
    );
  }
  const record = m.attempts.find(a => a.isRecord);
  return (
    <div className={cx('rqr-stub', `tone-${vrqCodeTone(l.code)}`)}>
      {res.resolved && (
        <div className="rqr-stamp" aria-label={`已处理，${res.by}，${res.at}`}><b>已处理</b><span className="num">{res.at}</span><small>{res.by}</small></div>
      )}
      <div className="rqr-merchant mono">{l.model}</div>
      <div className="rqr-big num tone-text">{l.code}</div>
      <div className="rqr-status tone-text">
        <Icon name="octagon" size={15} weight={2.4} />{VRQ_CODE_TEXT[l.code] || '上游错误'} · {record ? record.account : '已返回客户端'}
      </div>
      {m.recovered && (
        <div className="rqr-saved tone-ok"><Icon name="checkCircle" size={14} weight={2.4} />{m.switched ? '已切换账号' : '同一账号'}重试成功，客户端收到 200</div>
      )}
      <div className="rqr-error mono">{f ? f.message : '上游返回错误'}</div>
      <VrqActions ctx={ctx} m={m} res={res} />
    </div>
  );
}

function VrqReceiptAttempts({ ctx, m }) {
  if (!m.attempts.length || (m.ok && m.attempts.length < 2)) return null;
  return (
    <div className="rqr-group">
      {m.attempts.map((a, i) => (
        <VrqLine key={i} label={`尝试 ${i + 1}`} tag={a.isRecord ? '本条' : null} onClick={vrqGoAccount(ctx, a.accountId)}
          a11y={`第 ${i + 1} 次尝试，${a.account}，${a.code}，第 ${a.end.toFixed(1)} 秒`}>
          <span className="rqr-acct">{a.account}</span>
          <span className={cx('rqr-code num', `tone-${a.tone}`)}>{a.code}</span>
          <span className="num rqr-dur">+{vrqDur(a.end)}</span>
        </VrqLine>
      ))}
    </div>
  );
}

function VrqReceiptLinks({ ctx, m }) {
  const { l } = m;
  return (
    <div className="rqr-group">
      <VrqLine label="用户" onClick={m.user ? () => ctx.push({ kind: 'user', id: m.user.id }) : undefined}>{l.userName}</VrqLine>
      <VrqLine label="Key">{l.key.label} · <span className="mono">{l.key.masked}</span></VrqLine>
      <VrqLine label="分组">{l.group}</VrqLine>
      <VrqLine label="账号" onClick={vrqGoAccount(ctx, l.accountId)}>{l.account}</VrqLine>
    </div>
  );
}

function VrqReceiptOk({ ctx, m }) {
  const { l } = m;
  return (
    <>
      <div className="rqr-group">
        {l.upstreamModel !== l.model && <VrqLine label="上游模型"><span className="mono">{l.upstreamModel}</span></VrqLine>}
        <VrqLine label="方式">{l.stream}</VrqLine>
        <VrqLine label="首字 / 耗时"><span className="num">{vrqDur(m.first)} / {vrqDur(m.total)}</span></VrqLine>
      </div>
      <VrqReceiptAttempts ctx={ctx} m={m} />
      <div className="rqr-group">
        <VrqLine label="输入 / 输出 Token"><span className="num">{fmt.grouped(l.tokens.input)} / {fmt.grouped(l.tokens.output)}</span></VrqLine>
        <VrqLine label="缓存读 / 写"><span className="num">{fmt.grouped(l.tokens.cacheRead)} / {fmt.grouped(l.tokens.cacheWrite)}</span></VrqLine>
      </div>
      <div className="rqr-group">
        <VrqLine label="账号成本" kind="cost"><span className="num">{fmt.money(l.acost, { digits: 4 })}</span></VrqLine>
        <VrqLine label="标准" kind="standard"><span className="num">{fmt.money(l.std, { digits: 4 })}</span></VrqLine>
      </div>
    </>
  );
}

function VrqReceiptFail({ ctx, m }) {
  const { l, f } = m;
  return (
    <>
      <div className="rqr-group">
        <VrqLine label="阶段">{PHASE_LABEL[f.phase]}</VrqLine>
        <VrqLine label="责任方">{OWNER_LABEL[f.owner]}</VrqLine>
        <VrqLine label="级别"><span className="num">{f.severity}</span></VrqLine>
      </div>
      <VrqReceiptAttempts ctx={ctx} m={m} />
      <div className="rqr-group">
        {l.upstreamModel !== l.model && <VrqLine label="上游模型"><span className="mono">{l.upstreamModel}</span></VrqLine>}
        <VrqLine label="方式">{l.stream}</VrqLine>
        <VrqLine label={m.totalLabel}><span className="num">{vrqDur(m.total)}</span></VrqLine>
        {m.recovered && (
          <VrqLine label="对应用量明细" onClick={() => ctx.push(vrqUsageRoute(ctx, m))} a11y="打开对应用量明细">
            {m.twin && <span className="num">{fmt.money(m.twin.cost, { digits: 4 })}</span>}
          </VrqLine>
        )}
      </div>
    </>
  );
}

function VrqReceipt({ ctx, id }) {
  const l = vrqLog(id);
  const m = vrqModel(l);
  const res = useVrqResolve(ctx, l);
  return (
    <Screen ctx={ctx} nav={<VrqNav ctx={ctx} m={m} />}>
      <div className="rqr-wrap">
        <VrqReceiptStub ctx={ctx} m={m} res={res} />
        <div className="rqr-body">
          {m.ok ? <VrqReceiptOk ctx={ctx} m={m} /> : <VrqReceiptFail ctx={ctx} m={m} />}
          <VrqReceiptLinks ctx={ctx} m={m} />
          <div className="rqr-group">
            <VrqLine label="请求 ID" onClick={vrqCopy(ctx)} chevron={false} a11y={`请求 ID ${l.rid}，复制`}>
              <span className="mono rqr-rid">{l.rid}</span>
              <span className="rqr-copy">复制</span>
            </VrqLine>
          </div>
        </div>
      </div>
    </Screen>
  );
}
VRQ_IMPL.receipt = VrqReceipt;


/* ---------- 时间线式 ---------- */

function VrqNode({ tone, hollow, strong, step, title, tag, right, meta, extra, onClick, dashed, a11y }) {
  return (
    <li className={cx('rqt-node', `tone-${tone}`, hollow && 'is-hollow', strong && 'is-strong', step && 'is-step', dashed && 'is-dashed', onClick && 'tappable')}
      onClick={onClick} role={onClick ? 'button' : undefined} aria-label={a11y}>
      <span className="rqt-pin" aria-hidden="true">{step ? <i className="num">{step}</i> : <i />}</span>
      <div className="rqt-body">
        <div className="rqt-top">
          <span className="rqt-title">{title}</span>
          {tag && <em className="rqt-tag">{tag}</em>}
          <span className="rqt-right">{right}</span>
          {onClick && <span className="rqt-chev"><Icon name="chevron" size={12} weight={2.6} /></span>}
        </div>
        {meta && <div className="rqt-meta">{meta}</div>}
        {extra}
      </div>
    </li>
  );
}

function VrqWaterfall({ m, a }) {
  const pct = v => `${(v / m.total) * 100}%`;
  return (
    <div className="rqt-bar" aria-hidden="true">
      <i style={{ left: pct(a.start), width: `max(4px, ${pct(a.end - a.start)})` }} />
      {a.code === 200 && m.first !== null && <b style={{ left: pct(m.first) }} />}
    </div>
  );
}

function VrqDone({ l }) {
  return (
    <div className="rqt-receipt">
      <div className="rqt-cells rqt-cells-4">
        <span><small>输入</small><b className="num">{fmt.grouped(l.tokens.input)}</b></span>
        <span><small>输出</small><b className="num">{fmt.grouped(l.tokens.output)}</b></span>
        <span><small>缓存读</small><b className="num">{fmt.grouped(l.tokens.cacheRead)}</b></span>
        <span><small>缓存写</small><b className="num">{fmt.grouped(l.tokens.cacheWrite)}</b></span>
      </div>
      <div className="rqt-cells rqt-cells-2">
        <span><small data-kind="cost">账号成本</small><b className="num">{fmt.money(l.acost, { digits: 4 })}</b></span>
        <span><small data-kind="standard">标准</small><b className="num">{fmt.money(l.std, { digits: 4 })}</b></span>
      </div>
    </div>
  );
}

function vrqAttemptNode(ctx, m, a, i) {
  const { l } = m;
  const single = m.attempts.length === 1;
  const reason = VRQ_CODE_TEXT[a.code] || '上游错误';
  return (
    <VrqNode key={`try${i}`} tone={a.tone} tag={a.isRecord ? '本条记录' : null} step={single ? null : i + 1}
      title={single ? `账号 ${a.account}` : a.account}
      right={<><span className={cx('rqt-code num', `tone-${a.tone}`)}>{a.code}</span>{!a.last && <span className="num">+{vrqDur(a.end)}</span>}</>}
      meta={a.code === 200 ? <>上游模型 <span className="mono">{l.upstreamModel}</span></> : `${reason} · ${a.note}`}
      extra={<VrqWaterfall m={m} a={a} />}
      dashed={a.code !== 200 && !a.last}
      onClick={vrqGoAccount(ctx, a.accountId)}
      a11y={`${single ? '上游' : `第 ${i + 1} 次尝试`}，${a.account}，${a.code}${a.code === 200 ? '' : `，${reason}`}${a.accountId ? '，打开账号' : ''}`} />
  );
}

function vrqEndNode(ctx, m) {
  const { l, f } = m;
  if (m.ok) {
    return <VrqNode key="done" tone="ok" strong title={`完成 · ${l.stream}`} right={<span className="num">+{vrqDur(m.total)}</span>} extra={<VrqDone l={l} />} />;
  }
  if (m.recovered) {
    return (
      <VrqNode key="done" tone="ok" strong title="返回客户端 200" right={<span className="num">+{vrqDur(m.total)}</span>}
        meta={<>对应用量明细{m.twin && <> · 扣费 <span className="num">{fmt.money(m.twin.cost, { digits: 4 })}</span></>}</>}
        onClick={() => ctx.push(vrqUsageRoute(ctx, m))} a11y="返回客户端 200，打开对应用量明细" />
    );
  }
  return (
    <VrqNode key="done" tone={vrqCodeTone(m.clientCode)} strong title={`返回客户端 ${m.clientCode}`} tag={l.kind === '错误请求' ? '本条记录' : null}
      right={<span className="num">+{vrqDur(m.total)}</span>} meta={`${VRQ_CODE_TEXT[m.clientCode] || '请求失败'} · 责任方 ${OWNER_LABEL[f.owner]}`} />
  );
}

function vrqNodes(ctx, m, res) {
  const { l } = m;
  const nodes = [
    <VrqNode key="in" tone="neutral" hollow title={`收到请求 · ${l.userName}`} right={<span className="num">{m.time}</span>}
      meta={<>Key {l.key.label} <span className="mono">{l.key.masked}</span></>}
      onClick={m.user ? () => ctx.push({ kind: 'user', id: m.user.id }) : undefined}
      a11y={`收到请求，用户${l.userName}，打开用户`} />,
    <VrqNode key="grp" tone="neutral" hollow title={`进入分组「${l.group}」`} />,
    ...m.attempts.map((a, i) => vrqAttemptNode(ctx, m, a, i)),
  ];
  if (m.ok && m.first !== null) nodes.push(<VrqNode key="ttft" tone="ok" title="首字返回" right={<span className="num">+{vrqDur(m.first)}</span>} />);
  nodes.push(vrqEndNode(ctx, m));
  if (res.resolved) nodes.push(<VrqNode key="res" tone="ok" title="已标记处理" right={<span className="num">{res.at}</span>} meta={res.by} />);
  return nodes;
}

function vrqStats(m) {
  const { l } = m;
  const big = v => <b className="num">{v}</b>;
  if (m.ok) return [['首字', big(vrqDur(m.first))], ['总耗时', big(vrqDur(m.total))], ['实际扣费', big(fmt.money(l.cost, { digits: 4 }))]];
  const third = m.viaUpstream
    ? ['上游尝试', <b className="num">{m.attempts.length}<small> 次</small></b>]
    : ['阶段', <b className="is-word">{PHASE_LABEL[m.f.phase]}</b>];
  return [['返回客户端', <b className={cx('num tone-text', `tone-${vrqCodeTone(m.clientCode)}`)}>{m.clientCode}</b>], [m.totalLabel, big(vrqDur(m.total))], third];
}

function VrqTimelineTags({ m }) {
  const { l, f } = m;
  const codeTone = vrqCodeTone(l.code);
  return (
    <div className="rqt-tags">
      {m.ok && <span className="rqt-chip tone-ok"><Icon name="checkCircle" size={14} weight={2.4} />成功 <span className="num">200</span></span>}
      {m.ok && m.attempts.length > 1 && <span className="rqt-cause">上游重试 {m.attempts.length - 1} 次</span>}
      {m.failed && <span className={cx('rqt-chip', `tone-${codeTone}`)}><Icon name="octagon" size={14} weight={2.4} />失败 · {PHASE_LABEL[f.phase]}</span>}
      {m.recovered && (
        <>
          <span className={cx('rqt-chip', `tone-${codeTone}`)}><Icon name="octagon" size={14} weight={2.4} />上游 <span className="num">{l.code}</span></span>
          <Icon name="arrowRight" size={14} weight={2.4} />
          <span className="rqt-chip tone-ok"><Icon name="checkCircle" size={14} weight={2.4} />重试成功 <span className="num">200</span></span>
        </>
      )}
      {!m.ok && <span className="rqt-cause">{OWNER_LABEL[f.owner]} · {f.severity}</span>}
    </div>
  );
}

function VrqTimeline({ ctx, id }) {
  const { skin } = ctx;
  const l = vrqLog(id);
  const m = vrqModel(l);
  const res = useVrqResolve(ctx, l);
  return (
    <Screen ctx={ctx} nav={<VrqNav ctx={ctx} m={m} />}>
      <div className="rqt-head">
        <VrqTimelineTags m={m} />
        <div className="rqt-model mono">{l.model}</div>
        <div className="rqt-stats">{vrqStats(m).map(([k, v]) => <div key={k}><small>{k}</small>{v}</div>)}</div>
        {!m.ok && <div className="rqt-error mono">{m.f.message}</div>}
        <VrqActions ctx={ctx} m={m} res={res} />
      </div>
      <Section skin={skin} title="时间线" index="壹">
        <ol className="rqt-rail">{vrqNodes(ctx, m, res)}</ol>
      </Section>
      <Section skin={skin} title="标识" index="贰">
        <Row skin={skin} tone="none" lead={<span className="lead-icon dim"><Icon name="list" /></span>} onClick={vrqCopy(ctx)} chevron={false}>
          <div className="row-top"><span className="row-title">请求 ID</span><span className="row-right mono rq-rid">{l.rid}</span><span className="rqt-copy">复制</span></div>
        </Row>
      </Section>
    </Screen>
  );
}
VRQ_IMPL.timeline = VrqTimeline;

mvRegister('request', 'receipt', VrqDispatch);
mvRegister('request', 'timeline', VrqDispatch);
mvRegister('request', 'mix', VrqDispatch);
