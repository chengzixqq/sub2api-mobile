/* Layout B · 卡片仪表盘：两个 Tab（摘要 · 浏览）+ 搜索。首页是可编辑的卡片拼贴，账号是磁贴 + 轮播，
   详情是通行证卡 + 环形容量 + 控制中心式操作磁贴，充值用大数字键盘。颜色沿用游标，字形与形状独立。 */

const DB_TABS = [
  { key: 'summary', label: '摘要', icon: 'grid' },
  { key: 'browse', label: '浏览', icon: 'browse' },
];

const DB_CARDS = ['attention', 'revenue', 'health', 'channels', 'requests', 'errors', 'quick'];
const DB_CARD_NAMES = { attention: '需要处理', revenue: '今日营收', health: '账号健康', channels: '渠道', requests: '请求', errors: '错误率', quick: '快捷充值' };

function monogram(platform) {
  const latin = platform.replace(/[^A-Za-z]/g, '');
  return (latin || platform).slice(0, 2);
}

/* ---------- small pieces ---------- */

function DbRing({ ratio, size = 56, stroke = 6, children, tone }) {
  const r = (size - stroke) / 2;
  const c = 2 * Math.PI * r;
  const v = ratio === null || ratio === undefined ? 0 : Math.min(ratio, 1);
  const level = tone || (ratio >= 0.9 ? 'critical' : ratio >= 0.75 ? 'caution' : 'normal');
  return (
    <span className={cx('db-ring', `db-ring-${level}`)} style={{ width: size, height: size }}>
      <svg width={size} height={size} viewBox={`0 0 ${size} ${size}`} aria-hidden="true">
        <circle className="db-ring-track" cx={size / 2} cy={size / 2} r={r} strokeWidth={stroke} />
        <circle className="db-ring-fill" cx={size / 2} cy={size / 2} r={r} strokeWidth={stroke}
          strokeDasharray={`${c * v} ${c}`} transform={`rotate(-90 ${size / 2} ${size / 2})`} />
      </svg>
      <span className="db-ring-center">{children}</span>
    </span>
  );
}

function DbDonut({ parts, size = 96, stroke = 12, children }) {
  const r = (size - stroke) / 2;
  const c = 2 * Math.PI * r;
  const total = parts.reduce((s, p) => s + p.value, 0) || 1;
  let offset = 0;
  return (
    <span className="db-donut" style={{ width: size, height: size }}>
      <svg width={size} height={size} viewBox={`0 0 ${size} ${size}`} aria-hidden="true">
        <circle className="db-ring-track" cx={size / 2} cy={size / 2} r={r} strokeWidth={stroke} />
        {parts.filter(p => p.value).map(p => {
          const len = (p.value / total) * c;
          const seg = <circle key={p.key} className={`db-seg db-seg-${p.key}`} cx={size / 2} cy={size / 2} r={r} strokeWidth={stroke}
            strokeDasharray={`${Math.max(len - 2, 1)} ${c}`} strokeDashoffset={-offset} transform={`rotate(-90 ${size / 2} ${size / 2})`} />;
          offset += len;
          return seg;
        })}
      </svg>
      <span className="db-ring-center">{children}</span>
    </span>
  );
}

function DbStatus({ state, secs }) {
  const meta = STATE_META[state];
  return (
    <span className={cx('db-status', `tone-${meta.tone}`)}>
      <i className="db-dot" />{meta.label}{meta.timed && secs !== null && secs !== undefined && <b className="num"> {fmt.countdown(secs)}</b>}
    </span>
  );
}

function DbSection({ title, action, onAction, children }) {
  return (
    <section className="db-section">
      {title && <div className="db-section-head"><h3>{title}</h3>{action && <button onClick={onAction}>{action}</button>}</div>}
      {children}
    </section>
  );
}

function DbCard({ ctx, id, span, className, onClick, children }) {
  const editing = ctx.editing;
  return (
    <div className={cx('db-card', span && 'db-span2', editing && 'db-jiggle', className)} onClick={editing ? undefined : onClick} role={onClick ? 'button' : undefined}>
      {editing && <button className="db-remove" aria-label={`移除${DB_CARD_NAMES[id]}`} onClick={stop(() => ctx.hideCard(id))}>−</button>}
      {children}
    </div>
  );
}

function DbCardHead({ icon, title, tone, right }) {
  return (
    <div className={cx('db-card-head', tone && `tone-${tone}`)}>
      <span className="db-card-icon"><Icon name={icon} size={15} weight={2.3} /></span>
      <span className="db-card-title">{title}</span>
      {right}
      <span className="db-card-chev"><Icon name="chevron" size={12} weight={2.6} /></span>
    </div>
  );
}

/* ---------- 摘要 ---------- */

function DbAttentionCard({ ctx }) {
  const items = deriveAttention(ctx);
  const top = items[0];
  if (!top) {
    return (
      <DbCard ctx={ctx} id="attention" span className="db-calm">
        <DbCardHead icon="checkCircle" title="需要处理" tone="ok" />
        <div className="db-calm-text">全部正常 · 近 1 小时无新错误</div>
      </DbCard>
    );
  }
  const open = () => ctx.push({ kind: 'attention' });
  return (
    <DbCard ctx={ctx} id="attention" span className="db-stack" onClick={open}>
      <span className="db-stack-layer l1" /><span className="db-stack-layer l2" />
      <DbCardHead icon="tray" title="需要处理" tone={top.tone} right={<b className="db-count num">{items.length}</b>} />
      <div className={cx('db-stack-top', `tone-${top.tone}`)}>
        {top.state ? <DbStatus state={top.state} secs={top.secs} /> : <span className="db-status"><i className="db-dot" />{top.badge || '提醒'}</span>}
        <div className="db-stack-title">{top.title}</div>
        <div className="db-stack-detail">{top.detail}</div>
      </div>
      <div className="db-stack-foot">
        <span>另有 {items.length - 1} 项：{items.slice(1, 4).map(i => i.title).join('、')}</span>
      </div>
    </DbCard>
  );
}

function DbRevenueCard({ ctx }) {
  const t = DEMO.today;
  return (
    <DbCard ctx={ctx} id="revenue" span onClick={() => ctx.push({ kind: 'revenue' })}>
      <DbCardHead icon="dollar" title="今日营收" />
      <div className="db-revenue">
        <div>
          <div className="db-big num">{fmt.money(t.actual)}</div>
          <div className="db-delta"><Icon name="up" size={11} weight={2.8} /> {todayChange().toFixed(1)}% 比昨天同时</div>
        </div>
        <div className="db-revenue-chart"><Sparkline values={DEMO.hourlyToday} compare={DEMO.hourlyYesterday} w={150} h={54} area /></div>
      </div>
      <div className="db-revenue-foot">
        <span>成本 <b className="num">{fmt.money(t.cost)}</b></span>
        <span>标准 <b className="num">{fmt.money(t.standard)}</b></span>
        <span>差额 <b className="num">{fmt.money(t.actual - t.cost, { sign: true })}</b></span>
      </div>
    </DbCard>
  );
}

function healthParts(counts) {
  return [
    { key: 'ok', label: '正常', value: counts.normal },
    { key: 'caution', label: '受限', value: counts.limited },
    { key: 'critical', label: '错误', value: counts.error },
    { key: 'neutral', label: '暂停·停用', value: counts.paused + counts.inactive },
  ];
}

function DbHealthCard({ ctx }) {
  const c = ctx.counts;
  const parts = healthParts(c);
  return (
    <DbCard ctx={ctx} id="health" onClick={() => ctx.push({ kind: 'accounts' })}>
      <DbCardHead icon="server" title="账号" />
      <div className="db-health">
        <DbDonut parts={parts} size={72} stroke={9}><b className="num">{c.normal}</b><small>/{c.total}</small></DbDonut>
        <ul className="db-legend">
          {parts.map(p => <li key={p.key} className={`tone-${p.key}`}><i className="db-dot" />{p.label}<b className="num">{p.value}</b></li>)}
        </ul>
      </div>
    </DbCard>
  );
}

function DbChannelsCard({ ctx }) {
  const rank = { critical: 0, caution: 1 };
  const bad = DEMO.channels.filter(ch => ch.state in rank).sort((x, y) => rank[x.state] - rank[y.state]);
  const word = { critical: '不可用', caution: '性能下降' };
  return (
    <DbCard ctx={ctx} id="channels" onClick={() => ctx.push({ kind: 'channels' })}>
      <DbCardHead icon="signal" title="渠道" />
      <div className="db-chan-grid">
        {DEMO.channels.map(ch => <span key={ch.name} className={cx('db-chan-cell', `tone-${ch.state}`)} title={ch.name}>{ch.name.slice(0, 1)}</span>)}
      </div>
      <div className="db-card-line">可用 <b className="num">{DEMO.channels.filter(ch => ch.state === 'ok').length}/{DEMO.channels.length}</b>{bad.length > 0 && <> · <span className={`tone-${bad[0].state} tone-text`}>{bad[0].name} {word[bad[0].state]}</span></>}</div>
    </DbCard>
  );
}

function DbRequestsCard({ ctx }) {
  const bars = DEMO.hourlyToday;
  const max = Math.max(...bars);
  return (
    <DbCard ctx={ctx} id="requests" onClick={() => ctx.push({ kind: 'logs' })}>
      <DbCardHead icon="chart" title="请求" />
      <div className="db-mid num">{fmt.compact(DEMO.today.requests)}</div>
      <div className="db-bars" aria-hidden="true">{bars.map((v, i) => <i key={i} style={{ height: `${(v / max) * 100}%` }} className={i === bars.length - 1 ? 'now' : ''} />)}</div>
      <div className="db-card-line">RPM <b className="num">{DEMO.today.rpm}</b> · TPM <b className="num">{fmt.compact(DEMO.today.tpm)}</b></div>
    </DbCard>
  );
}

function DbErrorsCard({ ctx }) {
  return (
    <DbCard ctx={ctx} id="errors" onClick={() => ctx.push({ kind: 'logs', source: 'errors' })}>
      <DbCardHead icon="octagon" title="错误率" />
      <div className="db-mid num">{DEMO.run.errorRate}%</div>
      <Sparkline values={DEMO.run.errorTrend} w={140} h={30} />
      <div className="db-card-line">健康分 <b className="num">{DEMO.run.health}</b> · 429 <b className="num">{DEMO.run.r429}</b></div>
    </DbCard>
  );
}

function DbQuickTopupCard({ ctx }) {
  const recent = [1, 2, 4, 7].map(id => ctx.users[id]);
  return (
    <DbCard ctx={ctx} id="quick" span>
      <DbCardHead icon="people" title="快捷充值" right={<button className="db-link" onClick={stop(() => ctx.push({ kind: 'users' }))}>全部用户</button>} />
      <div className="db-quick">
        {recent.map(u => (
          <button key={u.id} className={cx('db-quick-user', (u.low || u.pending) && 'is-flag')} onClick={stop(() => (ctx.editing ? null : ctx.openSheet({ kind: 'keypad', userId: u.id, mode: 'topup' })))}>
            <span className="db-avatar">{u.name.slice(0, 1)}<i className="db-plus"><Icon name="plus" size={10} weight={3.2} /></i></span>
            <span className="db-quick-name">{u.name}</span>
            <span className="db-quick-bal num">{fmt.money(u.balance)}</span>
          </button>
        ))}
      </div>
    </DbCard>
  );
}

function DbSummary({ ctx }) {
  const map = {
    attention: DbAttentionCard, revenue: DbRevenueCard, health: DbHealthCard, channels: DbChannelsCard,
    requests: DbRequestsCard, errors: DbErrorsCard, quick: DbQuickTopupCard,
  };
  const visible = DB_CARDS.filter(id => !ctx.hidden.includes(id));
  return (
    <Screen ctx={ctx} nav={
      <NavBar ctx={ctx} large title="摘要" subtitle={`${ctx.site} · 10月16日 周五 · 刚刚更新`}
        leading={<GlassButton label={ctx.editing ? '完成' : '编辑'} prominent={ctx.editing} onClick={ctx.toggleEditing} />}
        trailing={<button className="db-site-btn" onClick={() => ctx.openSheet({ kind: 'sites' })} aria-label="切换站点">{ctx.site.slice(0, 1)}</button>} />
    }>
      <div className="db-grid">
        {visible.map(id => { const C = map[id]; return <C key={id} ctx={ctx} />; })}
        {ctx.editing && (
          <div className="db-card db-span2 db-add">
            <span>添加卡片</span>
            <div className="db-add-list">
              {ctx.hidden.length ? ctx.hidden.map(id => <button key={id} className="db-pill" onClick={() => ctx.showCard(id)}>+ {DB_CARD_NAMES[id]}</button>)
                : <small>已全部显示 · 拖动可排序</small>}
            </div>
          </div>
        )}
      </div>
    </Screen>
  );
}

function DbAttention({ ctx }) {
  const items = deriveAttention(ctx);
  return (
    <Screen ctx={ctx} nav={<NavBar ctx={ctx} back title="需要处理" subtitle={`${items.length} 项 · 最紧急在前`} />}>
      <div className="db-stack-list">
        {items.map(it => {
          const a = it.kind === 'account' ? ctx.accounts[it.id] : null;
          return (
            <div key={it.key} className={cx('db-card db-item', `tone-${it.tone}`)} onClick={() => (a ? ctx.push({ kind: 'account', id: a.id }) : it.kind === 'pending' ? ctx.push({ kind: 'user', id: it.id }) : null)}>
              <div className="db-item-top">
                {it.state ? <DbStatus state={it.state} secs={it.secs} /> : <span className="db-status"><i className="db-dot" />{it.badge || '待核对'}</span>}
                <Icon name="chevron" size={12} weight={2.6} />
              </div>
              <div className="db-item-title">{it.title}</div>
              <div className="db-item-detail">{it.detail}</div>
              {a && (
                <div className="db-item-actions">
                  {a.state !== 'error' && <button className="db-pill primary" onClick={stop(() => confirmRecover(ctx, a))}>恢复状态</button>}
                  <button className="db-pill" onClick={stop(() => ctx.openSheet({ kind: 'test', id: a.id }))}>测试</button>
                </div>
              )}
              {it.kind === 'pending' && <div className="db-item-actions"><button className="db-pill primary" onClick={stop(() => reconcileUser(ctx, ctx.users[it.id]))}>核对</button></div>}
            </div>
          );
        })}
      </div>
    </Screen>
  );
}

/* ---------- 账号：状态磁贴 + 需处理轮播 + 平台分组磁贴 ---------- */

function DbAccountTile({ ctx, a }) {
  const meta = STATE_META[a.state];
  const cap = tightestCapacity(a);
  return (
    <button className={cx('db-tile', `tone-${meta.tone}`, a.state !== 'normal' && 'is-flag')} onClick={() => ctx.push({ kind: 'account', id: a.id })}>
      <div className="db-tile-top">
        <span className="db-mono">{monogram(a.platform)}</span>
        {cap ? <DbRing ratio={cap.ratio} size={30} stroke={3.5}><small className="num">{cap.used}</small></DbRing> : <span className="db-ring-missing num">—</span>}
      </div>
      <div className="db-tile-name">{a.name}</div>
      <div className="db-tile-foot">
        {a.state === 'normal' ? <span className="db-tile-meta">{a.type}</span> : <DbStatus state={a.state} secs={remaining(a, ctx.elapsed)} />}
        <span className="num db-tile-money">{fmt.money(a.todayCost)}</span>
      </div>
    </button>
  );
}

function DbAccounts({ ctx }) {
  const list = Object.values(ctx.accounts);
  const c = ctx.counts;
  const filter = ctx.acctFilter;
  const tiles = [
    { key: 'ok', label: '正常', value: c.normal, match: a => a.state === 'normal' },
    { key: 'caution', label: '受限', value: c.limited, match: a => ['rate_limited', 'overloaded', 'temp_unsched'].includes(a.state) },
    { key: 'critical', label: '错误', value: c.error, match: a => a.state === 'error' },
    { key: 'neutral', label: '暂停·停用', value: c.paused + c.inactive, match: a => ['paused', 'inactive'].includes(a.state) },
  ];
  const active = tiles.find(t => t.key === filter);
  const needs = sortByUrgency(list.filter(a => NEEDS_ACTION.includes(a.state)));
  const shown = active ? list.filter(active.match) : list;
  const platforms = [...new Set(shown.map(a => a.platform))];
  return (
    <Screen ctx={ctx} nav={<NavBar ctx={ctx} back title="账号" subtitle={`${ctx.site} · ${c.total} 个`} trailing={<GlassButton icon="search" />} />}>
      <div className="db-filter-tiles">
        {tiles.map(t => (
          <button key={t.key} className={cx('db-ftile', `tone-${t.key}`, filter === t.key && 'on')} onClick={() => ctx.setAcctFilter(filter === t.key ? null : t.key)}>
            <b className="num">{t.value}</b><span><i className="db-dot" />{t.label}</span>
          </button>
        ))}
      </div>
      {!active && needs.length > 0 && (
        <DbSection title={`需要处理 · ${needs.length}`}>
          <div className="db-carousel">
            {needs.map(a => {
              const meta = STATE_META[a.state];
              const secs = remaining(a, ctx.elapsed);
              return (
                <div key={a.id} className={cx('db-card db-hero-card', `tone-${meta.tone}`)} onClick={() => ctx.push({ kind: 'account', id: a.id })}>
                  <div className="db-hero-top"><DbStatus state={a.state} /><span className="db-mono sm">{monogram(a.platform)}</span></div>
                  {meta.timed ? <div className="db-hero-num num tone-text">{fmt.countdown(secs)}</div> : <div className="db-hero-err">{a.error}</div>}
                  <div className="db-hero-name">{a.name}</div>
                  <div className="db-hero-meta">{meta.timed ? `${a.cause} · 自动恢复` : `${a.platform} · ${a.errorAgo}`}</div>
                  <div className="db-item-actions">
                    {a.state === 'error'
                      ? <button className="db-pill primary" onClick={stop(() => ctx.openSheet({ kind: 'test', id: a.id }))}>测试</button>
                      : <button className="db-pill primary" onClick={stop(() => confirmRecover(ctx, a))}>恢复状态</button>}
                  </div>
                </div>
              );
            })}
          </div>
        </DbSection>
      )}
      {platforms.map(p => {
        const rows = sortByUrgency(shown.filter(a => a.platform === p));
        return (
          <DbSection key={p} title={`${p} · ${rows.length}`}>
            <div className="db-tiles">{rows.map(a => <DbAccountTile key={a.id} ctx={ctx} a={a} />)}</div>
          </DbSection>
        );
      })}
    </Screen>
  );
}

/* ---------- 账号详情：通行证卡 + 环形容量 + 控制磁贴 ---------- */

function DbAccountDetail({ ctx, id }) {
  const a = ctx.accounts[id];
  const meta = STATE_META[a.state];
  const secs = remaining(a, ctx.elapsed);
  const scheduling = !['paused', 'inactive'].includes(a.state);
  const abnormal = NEEDS_ACTION.includes(a.state);
  const until = fmt.clock(DEMO_CLOCK_BASE + (ctx.elapsed + (secs || 0)) * 1000);
  const toggleSchedule = () => (scheduling
    ? ctx.updateAccount(id, { state: 'paused' }, { text: '已停止调度', undo: true, icon: 'pauseFill', tone: 'neutral' })
    : ctx.updateAccount(id, { state: 'normal' }, { text: '已启用调度', undo: true }));
  const rings = [
    a.conc && { label: '并发', ratio: a.conc[0] / a.conc[1], value: `${a.conc[0]}/${a.conc[1]}` },
    a.rpm && { label: '调度 RPM', ratio: a.rpm[0] / a.rpm[1], value: `${a.rpm[0]}/${a.rpm[1]}` },
    a.dayQuota && { label: '日配额', ratio: a.dayQuota[0] / a.dayQuota[1], value: fmt.money(a.dayQuota[0]), sub: `/ ${fmt.money(a.dayQuota[1])}` },
    a.window5h !== undefined && { label: '5 小时窗口', ratio: a.window5h, value: `${Math.round(a.window5h * 100)}%` },
  ].filter(Boolean);
  return (
    <Screen ctx={ctx} nav={<NavBar ctx={ctx} back title="" trailing={<GlassButton icon="more" />} />}>
      <div className={cx('db-pass', `tone-${meta.tone}`, abnormal && 'is-flag')}>
        <div className="db-pass-top"><span className="db-mono">{monogram(a.platform)}</span><span>{a.platform} · {a.type}</span><span className="db-pass-id num">#{a.id}</span></div>
        <div className="db-pass-name">{a.name}</div>
        <div className="db-pass-status">
          <DbStatus state={a.state} />
          {meta.timed && <><div className="db-pass-num num tone-text">{fmt.countdown(secs)}</div><div className="db-pass-sub">{a.cause} · 预计 <span className="num">{until}</span> 自动恢复</div></>}
          {a.state === 'error' && <div className="db-pass-err">{a.error}</div>}
          {!abnormal && <div className="db-pass-sub">{scheduling ? '参与调度 · 2 分钟前使用' : '不参与调度'}</div>}
        </div>
        {a.modelLimits && a.modelLimits.length > 0 && (
          <div className="db-pass-models">
            {a.modelLimits.map(m => <span key={m.model} className="db-chip tone-model"><Icon name="cube" size={12} /> <span className="mono">{m.model}</span> <b className="num">{fmt.minutesLeft(m.resetIn - ctx.elapsed)}</b></span>)}
          </div>
        )}
      </div>
      <DbSection title="操作">
        <div className="db-controls">
          <button className={cx('db-control', scheduling && 'on')} onClick={toggleSchedule}>
            <Icon name={scheduling ? 'play' : 'pauseFill'} size={20} /><b>调度</b><small>{scheduling ? '参与中' : '已暂停'}</small>
          </button>
          <button className={cx('db-control', abnormal && 'accent')} disabled={!abnormal} onClick={() => confirmRecover(ctx, a)}>
            <Icon name="restore" size={20} /><b>恢复</b><small>{abnormal ? '清除阻断' : '无需恢复'}</small>
          </button>
          <button className="db-control" onClick={() => ctx.openSheet({ kind: 'test', id })}>
            <Icon name="wave" size={20} /><b>测试</b><small>真实请求</small>
          </button>
          <button className="db-control" onClick={() => ctx.showToast({ text: '已刷新令牌', icon: 'refresh' })}>
            <Icon name="refresh" size={20} /><b>令牌</b><small>刷新</small>
          </button>
        </div>
      </DbSection>
      {rings.length > 0 && (
        <DbSection title="容量">
          <div className="db-ring-grid">
            {rings.map(r => (
              <div key={r.label} className="db-card db-ring-card">
                <DbRing ratio={r.ratio} size={58} stroke={7}><small className="num">{Math.round(r.ratio * 100)}%</small></DbRing>
                <div><small>{r.label}</small><b className="num">{r.value}</b>{r.sub && <small className="num"> {r.sub}</small>}</div>
              </div>
            ))}
          </div>
        </DbSection>
      )}
      <DbSection title="今日">
        <div className="db-card db-today">
          {[['实际', a.todayCost, 'actual'], ['成本', a.todayAccountCost, 'cost'], ['标准', a.todayStd, 'standard']].map(([k, v, kind]) => (
            <div key={k}><small data-kind={kind}>{k}</small><b className="num">{fmt.money(v ?? null)}</b></div>
          ))}
          <div className="db-today-line">请求 <b className="num">{fmt.grouped(a.todayReq)}</b> · Tokens <b className="num">{fmt.compact(a.todayTokens ?? null)}</b></div>
        </div>
      </DbSection>
      <DbSection title="记录与资料">
        <div className="db-card db-list">
          <button className="db-list-row" onClick={() => ctx.push({ kind: 'logs', source: 'upstream', account: a.name })}><Icon name="octagon" size={17} /><span>错误请求</span><b className="num">{a.errors24h ?? 0}</b><Icon name="chevron" size={12} weight={2.6} /></button>
          <button className="db-list-row" onClick={() => ctx.push({ kind: 'logs', account: a.name })}><Icon name="list" size={17} /><span>使用记录</span><b /><Icon name="chevron" size={12} weight={2.6} /></button>
          <div className="db-list-row static"><Icon name="group" size={17} /><span>分组</span><b>{a.groups.join('、') || '未分组'}</b></div>
          <div className="db-list-row static"><Icon name="shield" size={17} /><span>代理</span><b>{a.proxy || '—'}</b></div>
          <div className="db-list-row static"><Icon name="sliders" size={17} /><span>优先级</span><b className="num">{a.priority}</b></div>
        </div>
      </DbSection>
    </Screen>
  );
}

/* ---------- 用户：钱包卡 + 数字键盘 ---------- */

function DbUsers({ ctx }) {
  const list = Object.values(ctx.users);
  return (
    <Screen ctx={ctx} nav={<NavBar ctx={ctx} back title="用户" subtitle={`${ctx.site} · ${list.length} 位`} trailing={<GlassButton icon="plus" />} />}>
      <div className="search-field"><Icon name="search" size={16} /><span>邮箱、用户名或备注</span></div>
      <div className="db-card db-list db-inset">
        {list.map(u => (
          <button key={u.id} className={cx('db-list-row user', u.status === 'disabled' && 'is-idle')} onClick={() => ctx.push({ kind: 'user', id: u.id })}>
            <span className="db-avatar sm">{u.name.slice(0, 1)}</span>
            <span className="db-user-main"><b>{u.name}</b><small>{u.email}</small></span>
            <span className={cx('db-user-bal num', (u.low || u.pending) && 'tone-caution tone-text')}>{fmt.money(u.balance)}</span>
            <Icon name="chevron" size={12} weight={2.6} />
          </button>
        ))}
      </div>
    </Screen>
  );
}

function DbUserDetail({ ctx, id }) {
  const u = ctx.users[id];
  return (
    <Screen ctx={ctx} nav={<NavBar ctx={ctx} back title="" trailing={<GlassButton icon="more" />} />}>
      <div className="db-wallet">
        <div className="db-wallet-top"><span className="db-avatar inv">{u.name.slice(0, 1)}</span><span><b>{u.name}</b><small>{u.email}</small></span></div>
        <small className="db-wallet-label">可用余额</small>
        <div className="db-wallet-bal num">{fmt.money(u.balance)}</div>
        <div className="db-wallet-actions">
          <button className="db-pill inv primary" onClick={() => ctx.openSheet({ kind: 'keypad', userId: id, mode: 'topup' })}><Icon name="plus" size={14} weight={2.8} /> 充值</button>
          <button className="db-pill inv" onClick={() => ctx.openSheet({ kind: 'keypad', userId: id, mode: 'refund' })}>退款</button>
        </div>
      </div>
      {u.pending && (
        <div className="db-card db-banner tone-caution" onClick={() => reconcileUser(ctx, u)}>
          <Icon name="docCheck" size={18} /><span><b>充值 {fmt.money(DEMO.pendingOp.amount)} 结果待核对</b><small>{DEMO.pendingOp.ago}发起 · 点按核对</small></span>
        </div>
      )}
      <div className="db-ring-grid">
        <div className="db-card db-stat"><small>今日消费</small><b className="num">{fmt.money(u.today)}</b></div>
        <div className="db-card db-stat"><small>本月</small><b className="num">{fmt.money(u.month ?? null)}</b></div>
      </div>
      {u.keys && (
        <DbSection title="API Key">
          <div className="db-card db-list">
            {u.keys.map(k => <div key={k.masked} className="db-list-row static"><Icon name="key" size={17} /><span>{k.label}</span><b className="mono">{k.masked}</b></div>)}
          </div>
        </DbSection>
      )}
      <DbSection title="余额流水">
        <div className="db-card db-list">
          {(u.ledger || []).map((l, i) => (
            <div key={i} className="db-list-row static ledger"><span className="db-ledger-kind"><b>{l.kind}</b><small className="num">{l.when}</small></span><b className="num">{fmt.money(l.amount, { sign: true })}</b></div>
          ))}
          {!(u.ledger || []).length && <div className="db-list-row static"><span className="dim">暂无流水</span></div>}
        </div>
      </DbSection>
    </Screen>
  );
}

function DbKeypadSheet({ ctx, sheet }) {
  const u = ctx.users[sheet.userId];
  const [mode, setMode] = useState(sheet.mode);
  const [amount, setAmount] = useState(sheet.amount || '');
  const value = Number(amount) || 0;
  const after = u.balance + (mode === 'topup' ? value : -value);
  const over = mode === 'refund' && value > u.balance;
  const verb = mode === 'topup' ? '充值' : '退款';
  const press = k => setAmount(cur => {
    if (k === 'del') return cur.slice(0, -1);
    if (k === '.' && (cur.includes('.') || !cur)) return cur;
    if (cur.includes('.') && cur.split('.')[1].length >= 2) return cur;
    if (cur.replace('.', '').length >= 7) return cur;
    return cur === '0' && k !== '.' ? k : cur + k;
  });
  return (
    <Sheet title="" onClose={ctx.closeSheet} tall>
      <Segmented items={[{ key: 'topup', label: '充值' }, { key: 'refund', label: '退款' }]} value={mode} onChange={setMode} />
      <div className="db-pad-user"><span className="db-avatar sm">{u.name.slice(0, 1)}</span>{u.name} · 余额 <span className="num">{fmt.money(u.balance)}</span></div>
      <div className={cx('db-pad-amount num', !amount && 'is-empty')}>{mode === 'refund' && '−'}${amount || '0'}</div>
      <div className={cx('db-pad-preview', over && 'tone-critical tone-text')}>
        {over ? '超过当前余额' : value ? <>{verb}后余额 <b className="num">{fmt.money(after)}</b></> : '输入金额'}
      </div>
      {mode === 'refund' && <button className="db-pill center" onClick={() => setAmount(String(u.balance))}>全部余额 {fmt.money(u.balance)}</button>}
      <div className="db-pad">
        {['1', '2', '3', '4', '5', '6', '7', '8', '9', '.', '0', 'del'].map(k => (
          <button key={k} className="db-key num" onClick={() => press(k)} aria-label={k === 'del' ? '删除' : k}>
            {k === 'del' ? <Icon name="deleteLeft" size={24} weight={1.9} /> : k}
          </button>
        ))}
      </div>
      <button className="submit" disabled={!value || over} onClick={() => submitBalanceChange(ctx, u, mode, value, '', ctx.closeSheet)}>{value ? `${verb} ${fmt.money(value)}` : verb}</button>
    </Sheet>
  );
}

function DbSitesSheet({ ctx }) {
  return (
    <Sheet title="站点" onClose={ctx.closeSheet} leadingLabel="完成">
      <div className="db-card db-list db-inset flat">
        {DEMO.sites.map(s => (
          <button key={s.name} className="db-list-row" onClick={() => { ctx.setSite(s.name); ctx.closeSheet(); }}>
            <span className="db-avatar sm">{s.name.slice(0, 1)}</span>
            <span className="db-user-main"><b>{s.name}</b><small>{s.host}</small></span>
            {ctx.site === s.name && <Icon name="check" size={18} weight={2.6} />}
          </button>
        ))}
      </div>
      <div className="db-card db-list db-inset flat">
        <div className="db-list-row static"><Icon name="plus" size={17} /><span>添加站点</span></div>
        <div className="db-list-row static"><Icon name="key" size={17} /><span>站点与凭据</span></div>
      </div>
    </Sheet>
  );
}

/* ---------- 浏览 / 记录 / 渠道 / 营收 ---------- */

function DbBrowse({ ctx }) {
  const cats = [
    ['server', '账号', ctx.counts.total, { kind: 'accounts' }],
    ['people', '用户', DEMO.users.length, { kind: 'users' }],
    ['list', '使用记录', DEMO.logs.length, { kind: 'logs' }],
    ['octagon', '错误请求', DEMO.logs.filter(l => l.kind).length, { kind: 'logs', source: 'errors' }],
    ['signal', '渠道', DEMO.channels.length, { kind: 'channels' }],
    ['dollar', '营收', null, { kind: 'revenue' }],
    ['group', '分组', 4, null],
    ['bell', '告警', 1, null],
    ['gift', '兑换码', null, null],
    ['shield', '代理', 3, null],
  ];
  return (
    <Screen ctx={ctx} nav={<NavBar ctx={ctx} large title="浏览" subtitle={`${ctx.site} · 全部对象`} />}>
      <div className="search-field big"><Icon name="search" size={17} /><span>搜索账号、用户、请求 ID</span></div>
      <div className="db-cats">
        {cats.map(([icon, label, count, route]) => (
          <button key={label} className="db-card db-cat" onClick={() => (route ? ctx.push(route) : ctx.showToast({ text: `${label}：原型未展开`, icon: 'browse', tone: 'neutral' }))}>
            <span className="db-cat-icon"><Icon name={icon} size={20} /></span>
            <b>{label}</b>
            {count !== null && <small className="num">{count}</small>}
          </button>
        ))}
      </div>
      <DbSection title="在 Web 中打开">
        <div className="db-card db-list">
          {['系统设置', '支付与套餐', '公告'].map(t => <div key={t} className="db-list-row static"><Icon name="web" size={17} /><span>{t}</span><Icon name="arrowRight" size={14} /></div>)}
        </div>
      </DbSection>
    </Screen>
  );
}

function logBucket(t) {
  const m = Number(t.split(':')[1]);
  return Math.floor((m - 15) / 5);
}

function DbLogs({ ctx, route }) {
  const [source, setSource] = useState(route.source || 'usage');
  const [bucket, setBucket] = useState(null);
  const pick = { usage: l => l.code === 200, errors: l => l.kind === '错误请求', upstream: l => l.kind === '上游错误' };
  const base = DEMO.logs.filter(l => !route.account || l.account === route.account);
  const labels = ['09:15', '09:20', '09:25', '09:30', '09:35', '09:40'];
  const buckets = labels.map((_, i) => ({ ok: base.filter(l => logBucket(l.t) === i && l.code === 200).length, bad: base.filter(l => logBucket(l.t) === i && l.code !== 200).length }));
  const max = Math.max(1, ...buckets.map(b => b.ok + b.bad));
  const rows = base.filter(pick[source]).filter(l => bucket === null || logBucket(l.t) === bucket);
  return (
    <Screen ctx={ctx} nav={<NavBar ctx={ctx} back title="使用记录" subtitle={route.account ? `${route.account} · 近 30 分钟` : `${ctx.site} · 近 30 分钟`} trailing={<GlassButton icon="filter" />} />}>
      <div className="pad-x"><Segmented value={source} onChange={setSource} items={[{ key: 'usage', label: '用量明细' }, { key: 'errors', label: '错误请求' }, { key: 'upstream', label: '上游错误' }]} /></div>
      <div className="db-card db-hist">
        <div className="db-hist-head"><b>{bucket === null ? `${base.length} 次请求` : `${labels[bucket]} 起 5 分钟`}</b><small>{bucket === null ? '点柱子按时段筛选' : <button className="db-link" onClick={() => setBucket(null)}>清除时段</button>}</small></div>
        <div className="db-hist-bars">
          {buckets.map((b, i) => (
            <button key={i} className={cx('db-hist-col', bucket === i && 'on', bucket !== null && bucket !== i && 'dim')} onClick={() => setBucket(bucket === i ? null : i)} aria-label={`${labels[i]} 时段`}>
              <span className="db-hist-stack" style={{ height: `${((b.ok + b.bad) / max) * 100}%` }}>
                <i className="bad" style={{ flex: b.bad }} /><i className="ok" style={{ flex: b.ok }} />
              </span>
              <small className="num">{labels[i].slice(3)}</small>
            </button>
          ))}
        </div>
      </div>
      <div className="db-card db-list db-inset">
        {rows.map((l, i) => (
          <div key={i} className="db-list-row log">
            <span className={cx('db-code num', l.code !== 200 && (l.code === 429 || l.code === 504 ? 'tone-caution' : 'tone-critical'))}>{l.code}</span>
            <span className="db-user-main"><b className="mono">{l.model}</b><small>{l.user} · {l.account}</small></span>
            <span className="db-log-right"><b className="num">{l.cost === null ? '—' : fmt.money(l.cost, { small: true, digits: l.cost < 1 ? 4 : 2 })}</b><small className="num">{l.t} · {l.dur}</small></span>
          </div>
        ))}
        {!rows.length && <div className="db-list-row static"><span className="dim">这个范围内没有记录</span></div>}
      </div>
    </Screen>
  );
}

function DbChannels({ ctx }) {
  const order = ['critical', 'caution', 'neutral', 'ok'];
  const label = { ok: '可用', caution: '性能下降', critical: '不可用', neutral: '未知' };
  const list = [...DEMO.channels].sort((a, b) => order.indexOf(a.state) - order.indexOf(b.state));
  return (
    <Screen ctx={ctx} nav={<NavBar ctx={ctx} back large title="渠道" subtitle="近 90 分钟 · 刚刚更新" />}>
      <div className="db-tiles pad-x">
        {list.map(ch => (
          <div key={ch.name} className={cx('db-card db-chan', `tone-${ch.state}`, ch.state !== 'ok' && 'is-flag')}>
            <div className="db-chan-top"><b>{ch.name}</b><span className="db-status"><i className="db-dot" />{label[ch.state]}</span></div>
            <small>{ch.provider}</small>
            <div className="db-chan-num num">{ch.avail === null ? '—' : `${ch.avail}%`}</div>
            <BaseChannelStrip strip={ch.strip} />
            <small className="db-chan-foot">{ch.note || '可用率'} · 首字 <span className="num">{ch.ttft}</span></small>
          </div>
        ))}
      </div>
    </Screen>
  );
}

function DbRevenue({ ctx }) {
  const [range, setRange] = useState('today');
  const t = DEMO.today;
  return (
    <Screen ctx={ctx} nav={<NavBar ctx={ctx} back title="营收" subtitle={`${ctx.site} · 00:00 起`} />}>
      <div className="pad-x"><Segmented value={range} onChange={setRange} items={[{ key: 'today', label: '今天' }, { key: 'week', label: '7 天' }, { key: 'month', label: '30 天' }]} /></div>
      <div className="db-card db-rev-hero">
        <small data-kind="actual">实际扣费</small>
        <div className="db-big num">{fmt.money(t.actual)}</div>
        <div className="db-delta"><Icon name="up" size={11} weight={2.8} /> {todayChange().toFixed(1)}% 比昨天同时</div>
        <TrendChart style="line" />
      </div>
      <div className="db-ring-grid">
        <div className="db-card db-stat"><small data-kind="cost">账号成本</small><b className="num">{fmt.money(t.cost)}</b></div>
        <div className="db-card db-stat"><small data-kind="standard">标准费用</small><b className="num">{fmt.money(t.standard)}</b></div>
        <div className="db-card db-stat"><small>差额（实际 − 成本）</small><b className="num">{fmt.money(t.actual - t.cost, { sign: true })}</b></div>
        <div className="db-card db-stat"><small>请求 · Tokens</small><b className="num">{fmt.compact(t.requests)} · {fmt.compact(t.tokens)}</b></div>
      </div>
    </Screen>
  );
}

/* ---------- phone ---------- */

function DbTabBar({ ctx }) {
  return (
    <nav className="tabbar">
      <div className="tabs glass db-tabs">
        {DB_TABS.map(t => (
          <button key={t.key} className={cx('tab', ctx.tab === t.key && 'on')} onClick={() => ctx.switchTab(t.key)}>
            <span className="tab-icon"><Icon name={t.icon} size={22} weight={2} />{t.key === 'summary' && ctx.counts.error > 0 && <b className="tab-badge num">{ctx.counts.error}</b>}</span>
            <span className="tab-label">{t.label}</span>
          </button>
        ))}
      </div>
      <button className={cx('tab-search glass', ctx.tab === 'search' && 'on')} aria-label="搜索" onClick={() => ctx.switchTab('browse')}><Icon name="search" size={22} weight={2.2} /></button>
    </nav>
  );
}

function DashboardPhone({ dark, initial }) {
  const app = useAppModel(initial);
  const [tab, setTab] = useState(initial.tab || 'summary');
  const [stacks, setStacks] = useState(() => ({ summary: [], browse: [], [initial.tab || 'summary']: initial.stack || [] }));
  const [editing, setEditing] = useState(Boolean(initial.editing));
  const [hidden, setHidden] = useState([]);
  const [acctFilter, setAcctFilter] = useState(null);
  const stack = stacks[tab];
  const ctx = {
    ...app, tab, editing, hidden, acctFilter, depth: stack.length - 1,
    push: route => setStacks(s => ({ ...s, [tab]: [...s[tab], route] })),
    pop: () => setStacks(s => ({ ...s, [tab]: s[tab].slice(0, -1) })),
    switchTab: key => { if (key === tab) setStacks(s => ({ ...s, [key]: [] })); setTab(key); setEditing(false); },
    toggleEditing: () => setEditing(v => !v),
    hideCard: id => setHidden(h => [...h, id]),
    showCard: id => setHidden(h => h.filter(x => x !== id)),
    setAcctFilter,
  };
  const top = stack[stack.length - 1];
  const screens = {
    attention: () => <DbAttention ctx={ctx} />,
    accounts: () => <DbAccounts ctx={ctx} />,
    account: r => <DbAccountDetail ctx={ctx} id={r.id} />,
    users: () => <DbUsers ctx={ctx} />,
    user: r => <DbUserDetail ctx={ctx} id={r.id} />,
    logs: r => <DbLogs ctx={ctx} route={r} key={JSON.stringify(r)} />,
    channels: () => <DbChannels ctx={ctx} />,
    revenue: () => <DbRevenue ctx={ctx} />,
  };
  const screen = top ? screens[top.kind](top) : tab === 'summary' ? <DbSummary ctx={ctx} /> : <DbBrowse ctx={ctx} />;
  return (
    <PhoneFrame dark={dark} canvas={dark ? '#0B0E10' : '#F1F3F4'} className="pal-vernier lay-dashboard">
      {screen}
      <DbTabBar ctx={ctx} />
      <Overlays ctx={ctx}>
        {ctx.sheet && ctx.sheet.kind === 'keypad' && <DbKeypadSheet ctx={ctx} sheet={ctx.sheet} key={ctx.sheet.userId + ctx.sheet.mode} />}
        {ctx.sheet && ctx.sheet.kind === 'sites' && <DbSitesSheet ctx={ctx} />}
      </Overlays>
    </PhoneFrame>
  );
}

mountPage({
  key: 'dashboard',
  pageClass: 'page-vernier page-layout',
  title: 'B · 卡片仪表盘',
  concept: '像“健康”App：只有两个 Tab。“摘要”是一面可以编辑的卡片墙，营收、账号健康、渠道、请求、快捷充值各占一块，点卡片下钻；“浏览”是全部对象的目录，日志、分组、告警都从这里进。账号用磁贴而不是列表，详情像钱包里的一张卡，容量用圆环，操作是控制中心式的磁贴。',
  traits: ['2 个 Tab + 搜索', '可编辑卡片墙（编辑 → 移除 / 添加）', '需处理叠卡', '状态磁贴 + 横向轮播', '平台分组两列磁贴', '通行证卡详情', '环形容量', '控制中心式操作', '大数字键盘充值'],
  structure: [
    ['导航', '底部 2 个 Tab（摘要 · 浏览）+ 搜索；站点切换是右上角头像 → 站点面板'],
    ['首页', '卡片拼贴：需处理叠卡、营收、账号环、渠道格、请求、错误率、快捷充值；可编辑'],
    ['账号列表', '四个状态磁贴当筛选 → 需处理横向轮播 → 按平台分组的两列磁贴'],
    ['账号详情', '通行证式状态卡（倒计时）→ 4 个控制磁贴 → 2×2 环形容量 → 今日 → 记录与资料'],
    ['批量', '弱：没有勾选模式（磁贴不适合多选），需要时只能逐个或长按'],
    ['日志', '浏览 → 使用记录，或点首页“请求 / 错误率”卡；先柱状图（点柱筛时段）后列表'],
    ['充值', '钱包卡上的按钮 → 大数字键盘（Apple Cash 式），也能从首页快捷充值直接打开'],
  ],
  defaultDark: false,
  phones: [
    { label: '摘要 · 卡片墙，点“编辑”可移除 / 添加卡片', initial: { tab: 'summary' } },
    { label: '账号 · 状态磁贴 + 需处理轮播 + 平台磁贴', initial: { tab: 'summary', stack: [{ kind: 'accounts' }] } },
    { label: '账号详情 · 通行证卡、控制磁贴、环形容量', initial: { tab: 'summary', stack: [{ kind: 'accounts' }, { kind: 'account', id: 3 }] } },
    { label: '充值 · 钱包卡 + 大数字键盘', initial: { tab: 'summary', stack: [{ kind: 'user', id: 1 }], sheet: { kind: 'keypad', userId: 1, mode: 'topup', amount: '50' } } },
    { label: '浏览 · 全部对象目录（日志从这里进）', initial: { tab: 'browse' } },
    { label: '渠道 · 两列磁贴，可用率大数', initial: { tab: 'summary', stack: [{ kind: 'channels' }] } },
  ],
  App: DashboardPhone,
});
