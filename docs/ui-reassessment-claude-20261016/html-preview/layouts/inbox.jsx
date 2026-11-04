/* Layout A · 收件箱：四个 Tab + 搜索，首页是待处理队列，列表是三行行，详情是状态卡 + 分区。
   Visual identity comes from a skin (directions/*.jsx); structure lives here. */

const TAB_DEFS = [
  { key: 'today', label: '今日', icon: 'home' },
  { key: 'accounts', label: '账号', icon: 'server' },
  { key: 'users', label: '用户', icon: 'people' },
  { key: 'monitor', label: '监控', icon: 'pulse' },
];

function TabBar({ ctx }) {
  if (ctx.selecting) return null;
  return (
    <nav className="tabbar">
      <div className="tabs glass">
        {TAB_DEFS.map(t => (
          <button key={t.key} className={cx('tab', ctx.tab === t.key && 'on')} onClick={() => ctx.switchTab(t.key)}>
            <span className="tab-icon">
              <Icon name={t.icon} size={22} weight={2} />
              {t.key === 'accounts' && ctx.counts.error > 0 && <b className="tab-badge num">{ctx.counts.error}</b>}
            </span>
            <span className="tab-label">{t.label}</span>
          </button>
        ))}
      </div>
      <button className={cx('tab-search glass', ctx.tab === 'search' && 'on')} onClick={() => ctx.switchTab('search')} aria-label="搜索">
        <Icon name="search" size={22} weight={2.2} />
      </button>
    </nav>
  );
}


/* ---------- shared building blocks ---------- */

function Section({ skin, title, meta, index, children, plain, className }) {
  const head = title ? <skin.SectionHead title={title} meta={meta} index={index} /> : null;
  if (skin.sectionLayout === 'inside') {
    return <section className={cx('sec', plain && 'sec-plain', className)}>{head}{children}</section>;
  }
  return (
    <section className={cx('sec-wrap', className)}>
      {head}
      <div className={cx('sec', plain && 'sec-plain')}>{children}</div>
    </section>
  );
}

function Row({ skin, tone, lead, children, onClick, className, chevron = true }) {
  return (
    <div className={cx('row', skin.rowClass(tone), onClick && 'tappable', className)} onClick={onClick}>
      <div className="row-lead">{lead}</div>
      <div className="row-main">{children}</div>
      {onClick && chevron && <div className="row-chev"><Icon name="chevron" size={13} weight={2.6} /></div>}
    </div>
  );
}


/* ---------- 今日 ---------- */

function TodayScreen({ ctx }) {
  const { skin, accounts, elapsed } = ctx;
  const list = Object.values(accounts);
  const errors = list.filter(a => a.state === 'error');
  const overloads = list.filter(a => a.state === 'overloaded');
  const limited = list.filter(a => ['rate_limited', 'temp_unsched'].includes(a.state));
  const earliest = limited.length ? Math.min(...limited.map(a => remaining(a, elapsed))) : null;
  const pendingUser = Object.values(ctx.users).find(u => u.pending);

  const items = [];
  if (ctx.alertOpen) {
    items.push(
      <Row key="alert" skin={skin} tone="caution" className="tone-caution" lead={<span className="lead-icon"><Icon name="bell" /></span>}
        onClick={() => ctx.switchTab('accounts', { filter: 'needs' })}>
        <div className="row-top"><span className="row-title">{DEMO.alert.title}</span><skin.Badge tone="caution" label={DEMO.alert.level} /></div>
        <div className="row-meta">{DEMO.alert.detail}</div>
      </Row>
    );
  }
  errors.forEach(a => items.push(
    <Row key={a.id} skin={skin} tone="critical" className="tone-critical" lead={<skin.Glyph state="error" />} onClick={() => ctx.push({ kind: 'account', id: a.id })}>
      <div className="row-top"><span className="row-title">{a.name}</span><skin.Badge state="error" /></div>
      <div className="row-note">{a.error}</div>
      <div className="row-foot"><span className="row-meta">{a.platform} · {a.errorAgo}</span><ActionButton small label="测试" icon="wave" onClick={() => ctx.openSheet({ kind: 'test', id: a.id })} /></div>
    </Row>
  ));
  overloads.forEach(a => items.push(
    <Row key={a.id} skin={skin} tone="critical" className="tone-critical" lead={<skin.Glyph state="overloaded" />} onClick={() => ctx.push({ kind: 'account', id: a.id })}>
      <div className="row-top"><span className="row-title">{a.name}</span><skin.Badge state="overloaded" secs={remaining(a, elapsed)} /></div>
      <div className="row-meta">{a.cause} · {a.platform}</div>
    </Row>
  ));
  if (limited.length) {
    items.push(
      <Row key="limited" skin={skin} tone="caution" className="tone-caution" lead={<skin.Glyph state="rate_limited" />} onClick={() => ctx.switchTab('accounts', { filter: 'limited' })}>
        <div className="row-top"><span className="row-title">受限 {limited.length} 个账号</span><span className="row-right num tone-text">最早 {fmt.countdown(earliest)}</span></div>
        <div className="row-meta">{limited.map(a => a.name).join('、')}</div>
      </Row>
    );
  }
  if (pendingUser) {
    items.push(
      <Row key="pending" skin={skin} tone="caution" className="tone-caution" lead={<span className="lead-icon"><Icon name="docCheck" /></span>}
        onClick={() => ctx.push({ kind: 'user', id: pendingUser.id })}>
        <div className="row-top"><span className="row-title">充值结果待核对</span><skin.Money value={DEMO.pendingOp.amount} size="m" /></div>
        <div className="row-meta">{pendingUser.name} · {DEMO.pendingOp.ago} · 未确认是否入账</div>
      </Row>
    );
  }
  const normalCount = list.filter(a => a.state === 'normal').length;

  return (
    <Screen ctx={ctx} nav={<NavBar ctx={ctx} large title={ctx.site} titleMenu subtitle="10月16日 周五 · 刚刚更新" trailing={<GlassButton icon="more" />} />}>
      <skin.LedgerStrip ctx={ctx} />
      <Section skin={skin} title="待处理" meta={`${items.length} 项`} index="壹">
        {items.length ? items : (
          <Row skin={skin} tone="ok" lead={<skin.Glyph state="normal" />} chevron={false}>
            <div className="row-top"><span className="row-title">全部正常</span></div>
            <div className="row-meta">{normalCount} 个账号可调度 · 近 1 小时无新错误</div>
          </Row>
        )}
      </Section>
      <Section skin={skin} title="今日" meta="00:00 起" index="贰"><skin.TodayBlock ctx={ctx} /></Section>
      <Section skin={skin} title="运行" meta="近 5 分钟" index="叁">
        <div className="pad"><skin.Health score={DEMO.run.health} /></div>
        <div className="kv-row pad">
          <span>错误率 <b className="num">{DEMO.run.errorRate}%</b></span>
          <span>上游 429 <b className="num">{DEMO.run.r429}</b></span>
          <span>529 <b className="num">{DEMO.run.r529}</b></span>
        </div>
        <Row skin={skin} tone="none" lead={<span className="lead-icon dim"><Icon name="signal" /></span>} onClick={() => ctx.switchTab('monitor')}>
          <div className="row-top"><span className="row-title">渠道</span></div>
          <div className="row-meta">可用 3 · <span className="tone-caution tone-text">性能下降 1</span> · <span className="tone-critical tone-text">不可用 1</span> · 未知 1</div>
        </Row>
      </Section>
    </Screen>
  );
}

/* ---------- 账号 ---------- */

function AccountRow({ ctx, a }) {
  const { skin, elapsed } = ctx;
  const tone = toneOf(a.state);
  const meta = STATE_META[a.state];
  const secs = remaining(a, elapsed);
  const cap = tightestCapacity(a);
  const selected = ctx.selected.includes(a.id);
  const onClick = ctx.selecting ? () => ctx.toggleSelect(a.id) : () => ctx.push({ kind: 'account', id: a.id });
  const lead = ctx.selecting
    ? <span className={cx('select-ring', selected && 'on')}>{selected && <Icon name="check" size={14} weight={3} />}</span>
    : <skin.Glyph state={a.state} />;
  let third;
  if (a.state === 'error') third = <div className="row-note">{a.error}</div>;
  else if (meta.timed) third = <div className="row-note">{a.cause} · <span className="num">{fmt.clock(DEMO_CLOCK_BASE + (elapsed + secs) * 1000)}</span> 恢复{a.modelLimits && a.modelLimits.length ? ` · 另有模型限流 ${a.modelLimits.length}` : ''}</div>;
  else third = (
    <div className="row-cap">
      {cap ? <skin.Capacity used={cap.used} limit={cap.limit} label={cap.label} /> : <span className="cap-missing"><span className="num">—</span> 并发</span>}
      <span className="row-money"><small>今日</small><skin.Money value={a.todayCost} size="s" /></span>
    </div>
  );
  return (
    <Row skin={skin} tone={ctx.selecting ? 'none' : tone} className={cx(`tone-${tone}`, a.state === 'paused' || a.state === 'inactive' ? 'is-idle' : '', selected && 'is-selected')} lead={lead} onClick={onClick} chevron={!ctx.selecting}>
      <div className="row-top"><span className="row-title">{a.name}</span><skin.Badge state={a.state} secs={secs} /></div>
      <div className="row-meta">{a.platform} · {a.groups.length ? a.groups.join('、') : '未分组'} · {a.type}</div>
      {third}
    </Row>
  );
}

function AccountsScreen({ ctx }) {
  const { skin } = ctx;
  const list = sortByUrgency(Object.values(ctx.accounts));
  const counts = ctx.counts;
  const filter = ctx.acctFilter;
  const chips = [
    { key: 'needs', label: '需处理', count: counts.needs, alert: counts.needs > 0 },
    { key: 'all', label: '全部', count: counts.total },
    { key: 'limited', label: '受限', count: counts.limited },
    { key: 'paused', label: '暂停·停用', count: counts.paused + counts.inactive },
    { key: 'platform', label: '平台', menu: true },
  ];
  const pick = {
    needs: a => NEEDS_ACTION.includes(a.state),
    limited: a => ['rate_limited', 'overloaded', 'temp_unsched'].includes(a.state),
    paused: a => ['paused', 'inactive'].includes(a.state),
  };
  let body;
  if (filter === 'all') {
    const groups = [
      ['需处理', list.filter(pick.needs)],
      ['暂停与停用', list.filter(pick.paused)],
      ['正常', list.filter(a => a.state === 'normal')],
    ].filter(([, rows]) => rows.length);
    body = groups.map(([title, rows]) => (
      <div key={title} className="list-group">
        <div className="list-head"><span>{title}</span><b className="num">{rows.length}</b></div>
        {rows.map(a => <AccountRow key={a.id} ctx={ctx} a={a} />)}
      </div>
    ));
  } else {
    const rows = list.filter(pick[filter] || (() => true));
    body = <div className="list-group">{rows.map(a => <AccountRow key={a.id} ctx={ctx} a={a} />)}</div>;
  }
  const dock = ctx.selecting && (
    <div className="dock glass">
      <span className="dock-count">已选 <b className="num">{ctx.selected.length}</b> 个</span>
      <button className="dock-btn" disabled={!ctx.selected.length} onClick={() => ctx.bulkSchedule(false)}><Icon name="pauseFill" size={15} />停止调度</button>
      <button className="dock-btn dock-primary" disabled={!ctx.selected.length} onClick={() => ctx.bulkSchedule(true)}><Icon name="play" size={15} />启用调度</button>
    </div>
  );
  return (
    <Screen plain ctx={ctx} footer={dock} nav={
      <NavBar ctx={ctx} title="账号" subtitle={`${ctx.site} · ${counts.total} 个 · 刚刚更新`}
        leading={<GlassButton label={ctx.selecting ? '完成' : '选择'} onClick={ctx.toggleSelecting} prominent={ctx.selecting} />}
        trailing={!ctx.selecting && <GlassButton icon="filter" />} />
    }>
      <Chips items={chips} value={filter} onChange={k => k !== 'platform' && ctx.setAcctFilter(k)} />
      {body}
    </Screen>
  );
}

function AccountDetail({ ctx, id }) {
  const { skin, elapsed } = ctx;
  const a = ctx.accounts[id];
  const meta = STATE_META[a.state];
  const tone = toneOf(a.state);
  const secs = remaining(a, elapsed);
  const until = fmt.clock(DEMO_CLOCK_BASE + (elapsed + (secs || 0)) * 1000);

  const recover = () => ctx.confirm({
    title: `恢复「${a.name}」？`,
    message: a.modelLimits && a.modelLimits.length ? `清除限流和 ${a.modelLimits.length} 项模型限流，账号立即参与调度。` : '清除当前阻断，账号立即参与调度。',
    actions: [
      { label: '恢复状态', role: 'default', onPress: () => ctx.updateAccount(id, { state: 'normal', modelLimits: [] }, { text: '已恢复 · 参与调度' }) },
      { label: '取消', role: 'cancel' },
    ],
  });
  const pause = () => ctx.updateAccount(id, { state: 'paused' }, { text: '已停止调度', undo: true, icon: 'pauseFill', tone: 'neutral' });
  const resume = () => ctx.updateAccount(id, { state: 'normal' }, { text: '已启用调度', undo: true });
  const test = () => ctx.openSheet({ kind: 'test', id });

  let hero;
  if (a.state === 'normal') {
    hero = <div className="hero hero-quiet tone-ok"><skin.Glyph state="normal" /><span>正常 · 参与调度</span></div>;
  } else if (a.state === 'paused' || a.state === 'inactive') {
    hero = <div className="hero hero-quiet tone-neutral"><skin.Glyph state={a.state} /><span>{meta.label} · 不参与调度</span></div>;
  } else {
    hero = (
      <div className={cx('hero', `tone-${tone}`, skin.rowClass(tone))}>
        <div className="hero-top"><skin.Badge state={a.state} big /><span className="hero-cause">{a.cause || '上游返回错误'}</span></div>
        {meta.timed ? (
          <>
            <div className="hero-figure"><skin.Num size="xl" className="tone-text">{fmt.countdown(secs)}</skin.Num></div>
            <div className="hero-sub">后自动恢复 · 预计 <span className="num">{until}</span></div>
          </>
        ) : <div className="hero-error">{a.error}</div>}
        {a.modelLimits && a.modelLimits.length > 0 && (
          <div className="hero-models tone-model">
            <div className="hero-models-title"><Icon name="cube" size={15} /> 模型限流 {a.modelLimits.length}</div>
            {a.modelLimits.map(m => (
              <div key={m.model} className="hero-model"><span className="mono">{m.model}</span><span className="num">{fmt.minutesLeft(m.resetIn - elapsed)}后</span></div>
            ))}
          </div>
        )}
      </div>
    );
  }

  const actions = a.state === 'normal'
    ? [<ActionButton key="t" label="测试连接" icon="wave" onClick={test} primary />, <ActionButton key="p" label="停止调度" icon="pauseFill" onClick={pause} />]
    : a.state === 'paused' || a.state === 'inactive'
      ? [<ActionButton key="r" label="启用调度" icon="play" onClick={resume} primary />, <ActionButton key="t" label="测试" icon="wave" onClick={test} />]
      : [<ActionButton key="r" label="恢复状态" icon="restore" onClick={recover} primary />, <ActionButton key="t" label="测试" icon="wave" onClick={test} />, <ActionButton key="p" label="停止调度" icon="pauseFill" onClick={pause} />];

  const caps = [
    a.conc && { label: '并发', used: a.conc[0], limit: a.conc[1] },
    a.rpm && { label: '调度 RPM', used: a.rpm[0], limit: a.rpm[1], note: '自然分钟' },
    a.dayQuota && { label: '日配额', used: a.dayQuota[0], limit: a.dayQuota[1], money: true },
    a.window5h !== undefined && { label: '5 小时窗口', ratio: a.window5h },
  ].filter(Boolean);

  return (
    <Screen ctx={ctx} nav={<NavBar ctx={ctx} back title={a.name} subtitle={`${a.platform} · ${a.type}`} trailing={<GlassButton icon="more" />} />}>
      <div className="detail-head">{hero}<div className="actions">{actions}</div></div>
      {caps.length > 0 && (
        <Section skin={skin} title="容量" meta="刚刚" index="壹">
          {caps.map(c => (
            <div key={c.label} className="cap-line pad">
              <span className="cap-label">{c.label}</span>
              <skin.Capacity used={c.used} limit={c.limit} ratio={c.ratio} money={c.money} wide />
              {c.note && <small className="cap-note">{c.note}</small>}
            </div>
          ))}
        </Section>
      )}
      <Section skin={skin} title="今日" index="贰">
        <div className="grid3 pad">
          <div><small data-kind="actual">实际</small><skin.Money value={a.todayCost} size="l" kind="actual" /></div>
          <div><small data-kind="cost">成本</small><skin.Money value={a.todayAccountCost ?? null} size="l" kind="cost" /></div>
          <div><small data-kind="standard">标准</small><skin.Money value={a.todayStd ?? null} size="l" kind="standard" /></div>
        </div>
        <div className="kv-row pad">
          <span>请求 <b className="num">{fmt.grouped(a.todayReq)}</b></span>
          <span>Tokens <b className="num">{fmt.compact(a.todayTokens ?? null)}</b></span>
        </div>
      </Section>
      <Section skin={skin} title="记录" index="叁">
        <Row skin={skin} tone="none" lead={<span className="lead-icon dim"><Icon name="octagon" /></span>} onClick={() => ctx.push({ kind: 'logs', scope: 'upstream', account: a.name })}>
          <div className="row-top"><span className="row-title">错误请求</span><span className="row-right num">{a.errors24h ?? 0} 条</span></div>
        </Row>
        <Row skin={skin} tone="none" lead={<span className="lead-icon dim"><Icon name="list" /></span>} onClick={() => ctx.push({ kind: 'logs', scope: 'usage', account: a.name })}>
          <div className="row-top"><span className="row-title">使用记录</span></div>
        </Row>
      </Section>
      <Section skin={skin} title="档案" index="肆">
        <div className="kv-grid pad">
          <KV label="平台" value={a.platform} /><KV label="类型" value={a.type} />
          <KV label="分组" value={a.groups.join('、') || '未分组'} /><KV label="优先级" value={a.priority} />
          <KV label="代理" value={a.proxy || '—'} /><KV label="到期" value={a.expires || '—'} />
        </div>
      </Section>
    </Screen>
  );
}


/* ---------- 用户 ---------- */

function UsersScreen({ ctx }) {
  const { skin } = ctx;
  const list = Object.values(ctx.users);
  return (
    <Screen plain ctx={ctx} nav={<NavBar ctx={ctx} title="用户" subtitle={`${ctx.site} · ${list.length} 位`} trailing={<GlassButton icon="plus" />} />}>
      <div className="search-field"><Icon name="search" size={16} /><span>邮箱、用户名或备注</span></div>
      <div className="list-group">
        {list.map(u => {
          const tone = u.status === 'disabled' ? 'neutral' : u.pending ? 'caution' : u.low ? 'caution' : 'none';
          return (
            <Row key={u.id} skin={skin} tone={u.pending ? 'caution' : 'none'} className={cx(`tone-${tone}`, u.status === 'disabled' && 'is-idle')}
              lead={<span className="avatar">{u.name.slice(0, 1)}</span>} onClick={() => ctx.push({ kind: 'user', id: u.id })}>
              <div className="row-top">
                <span className="row-title">{u.name}</span>
                <skin.Money value={u.balance} size="m" />
              </div>
              <div className="row-foot">
                <span className="row-meta">{u.email}</span>
                {u.status === 'disabled' && <skin.Badge tone="neutral" label="禁用" />}
                {u.pending && <skin.Badge tone="caution" label="待核对" />}
                {u.low && !u.pending && <skin.Badge tone="caution" label="余额低" />}
              </div>
            </Row>
          );
        })}
      </div>
    </Screen>
  );
}

function UserDetail({ ctx, id }) {
  const { skin } = ctx;
  const u = ctx.users[id];
  const reconcile = () => ctx.updateUser(id, { pending: false, balance: u.balance + DEMO.pendingOp.amount, ledger: [{ kind: '管理员充值', amount: DEMO.pendingOp.amount, when: '10/16 07:38', after: u.balance + DEMO.pendingOp.amount }, ...(u.ledger || [])] }, { text: '已核对：服务器已入账 $50.00' });
  return (
    <Screen ctx={ctx} nav={<NavBar ctx={ctx} back title={u.name} subtitle={u.email} trailing={<GlassButton icon="more" />} />}>
      {u.pending && (
        <div className={cx('banner tone-caution', skin.rowClass('caution'))}>
          <Icon name="docCheck" size={18} />
          <div className="banner-text"><b>充值 $50.00 结果待核对</b><span>{DEMO.pendingOp.ago}发起，未收到服务器确认</span></div>
          <ActionButton small label="核对" onClick={reconcile} />
        </div>
      )}
      <div className="balance-hero">
        <small>可用余额</small>
        <skin.Money value={u.balance} size="xl" />
        <div className="balance-sub">今日消费 <skin.Money value={u.today} size="s" /> {u.month !== undefined && <>· 本月 <skin.Money value={u.month} size="s" /></>}</div>
        <div className="actions">
          <ActionButton label="充值" icon="plus" primary onClick={() => ctx.openSheet({ kind: 'topup', userId: id, mode: 'topup' })} />
          <ActionButton label="退款" icon="restore" onClick={() => ctx.openSheet({ kind: 'topup', userId: id, mode: 'refund' })} />
        </div>
      </div>
      {u.keys && (
        <Section skin={skin} title="API Key" meta={`${u.keys.length} 个`} index="壹">
          {u.keys.map(k => (
            <Row key={k.masked} skin={skin} tone="none" lead={<span className="lead-icon dim"><Icon name="key" /></span>} chevron={false}>
              <div className="row-top"><span className="row-title">{k.label}</span><span className="row-right mono">{k.masked}</span></div>
              <div className="row-meta">最近使用 {k.used}</div>
            </Row>
          ))}
        </Section>
      )}
      <Section skin={skin} title="余额流水" index="贰">
        {(u.ledger || []).length ? (u.ledger || []).map((l, i) => (
          <div key={i} className="ledger-line pad">
            <div className="ledger-top"><span>{l.kind}</span><skin.Money value={l.amount} size="m" sign /></div>
            <div className="row-meta"><span className="num">{l.when}</span> · 余额 <skin.Money value={l.after} size="s" /></div>
          </div>
        )) : <div className="empty pad">暂无流水</div>}
      </Section>
      <Section skin={skin} title="档案" index="叁">
        <div className="kv-grid pad">
          <KV label="状态" value={u.status === 'disabled' ? '禁用' : '启用'} /><KV label="分组" value={u.group || '—'} />
          <KV label="并发上限" value={u.conc ?? '—'} /><KV label="角色" value="用户" />
        </div>
      </Section>
    </Screen>
  );
}

function TopupSheet({ ctx, sheet }) {
  const { skin } = ctx;
  const u = ctx.users[sheet.userId];
  const [mode, setMode] = useState(sheet.mode);
  const [amount, setAmount] = useState(sheet.amount || '');
  const [note, setNote] = useState('');
  const value = Number(amount) || 0;
  const signed = mode === 'topup' ? value : -value;
  const after = u.balance + signed;
  const invalid = !value || (mode === 'refund' && value > u.balance);
  const verb = mode === 'topup' ? '充值' : '退款';
  const submit = () => ctx.confirm({
    title: `向「${u.name}」${verb} ${fmt.money(value)}？`,
    message: `站点 ${ctx.site} · 余额 ${fmt.money(u.balance)} → ${fmt.money(after)}${note ? `\n备注：${note}` : ''}`,
    actions: [
      { label: `${verb} ${fmt.money(value)}`, role: 'destructive', onPress: () => {
        ctx.closeSheet();
        ctx.updateUser(u.id, { balance: after, ledger: [{ kind: mode === 'topup' ? '管理员充值' : '退款', amount: signed, when: '10/16 09:41', after }, ...(u.ledger || [])] }, { text: `已${verb} ${fmt.money(value)}` });
      } },
      { label: '取消', role: 'cancel' },
    ],
  });
  return (
    <Sheet title={verb} onClose={ctx.closeSheet} tall>
      <Segmented items={[{ key: 'topup', label: '充值' }, { key: 'refund', label: '退款' }]} value={mode} onChange={setMode} />
      <div className="sheet-target"><span>{u.name}</span><small>{u.email} · 当前余额 {fmt.money(u.balance)}</small></div>
      <label className={cx('amount', !amount && 'is-empty')}>
        <span className="amount-sign">{mode === 'refund' ? '−$' : '$'}</span>
        <input inputMode="decimal" value={amount} placeholder="0.00" onChange={e => setAmount(e.target.value.replace(/[^\d.]/g, ''))} aria-label="金额" />
      </label>
      <div className="quick">
        {(mode === 'topup' ? ['10', '20', '50', '100'] : ['5', '10']).map(v => <button key={v} className={cx('chip', amount === v && 'on')} onClick={() => setAmount(v)}>${v}</button>)}
        {mode === 'refund' && <button className="chip" onClick={() => setAmount(String(u.balance))}>全部余额</button>}
      </div>
      <input className="note" placeholder="备注（可选）" value={note} onChange={e => setNote(e.target.value)} />
      <div className={cx('preview', mode === 'refund' && value > u.balance && 'tone-critical')}>
        {mode === 'refund' && value > u.balance ? '退款金额超过当前余额' : <>{verb}后余额 <skin.Money value={value ? after : null} size="m" /></>}
      </div>
      <button className="submit" disabled={invalid} onClick={submit}>{value ? `${verb} ${fmt.money(value)}` : `输入${verb}金额`}</button>
    </Sheet>
  );
}

/* ---------- 监控 ---------- */

function MonitorScreen({ ctx }) {
  const { skin } = ctx;
  const order = ['critical', 'caution', 'neutral', 'ok'];
  const list = [...DEMO.channels].sort((a, b) => order.indexOf(a.state) - order.indexOf(b.state));
  const label = { ok: '可用', caution: '性能下降', critical: '不可用', neutral: '未知' };
  return (
    <Screen ctx={ctx} nav={<NavBar ctx={ctx} large title="监控" subtitle="渠道 · 近 90 分钟 · 刚刚更新" trailing={<GlassButton icon="more" />} />}>
      <div className="chan-summary pad">
        {['ok', 'caution', 'critical', 'neutral'].map(s => (
          <div key={s} className={`chan-stat tone-${s}`}><skin.Num size="l">{DEMO.channels.filter(c => c.state === s).length}</skin.Num><small>{label[s]}</small></div>
        ))}
      </div>
      <Section skin={skin} title="渠道" meta="可用率 · 首字" index="壹">
        {list.map(c => (
          <Row key={c.name} skin={skin} tone={c.state === 'ok' ? 'ok' : c.state} className={`tone-${c.state}`}
            lead={<skin.Glyph state={{ ok: 'normal', caution: 'rate_limited', critical: 'error', neutral: 'inactive' }[c.state]} />} onClick={() => {}}>
            <div className="row-top">
              <span className="row-title">{c.name}<small className="row-sub">{c.provider}</small></span>
              {c.state === 'ok'
                ? <span className="row-right num">{c.avail}%</span>
                : <skin.Badge tone={c.state} label={label[c.state]} />}
            </div>
            <skin.ChannelStrip strip={c.strip} />
            <div className="row-meta">{c.note ? c.note : `可用率 ${c.avail ?? '—'}%`} · 首字 <span className="num">{c.ttft}</span></div>
          </Row>
        ))}
      </Section>
    </Screen>
  );
}

/* ---------- 搜索与日志 ---------- */

function SearchHome({ ctx }) {
  const { skin } = ctx;
  const groups = [
    ['记录', [['list', '使用记录', () => ctx.push({ kind: 'logs', scope: 'usage' })], ['octagon', '错误请求', () => ctx.push({ kind: 'logs', scope: 'errors' })], ['bell', '告警事件', null]]],
    ['资源', [['group', '分组', null], ['chart', '统计分析', null], ['gift', '兑换码', null], ['shield', '代理', null], ['megaphone', '公告', null]]],
    ['在 Web 中打开', [['web', '系统设置', null], ['web', '支付与套餐', null]]],
  ];
  return (
    <Screen ctx={ctx} nav={<NavBar ctx={ctx} large title="搜索" subtitle="账号、用户、请求 ID、Key 片段" />}>
      <div className="search-field big"><Icon name="search" size={17} /><span>搜索全部对象</span></div>
      {groups.map(([title, items], gi) => (
        <Section key={title} skin={skin} title={title} index={['壹', '贰', '叁'][gi]}>
          {items.map(([icon, label, go]) => (
            <Row key={label} skin={skin} tone="none" lead={<span className="lead-icon dim"><Icon name={icon} /></span>} onClick={go || (() => {})}>
              <div className="row-top"><span className="row-title">{label}</span></div>
            </Row>
          ))}
        </Section>
      ))}
    </Screen>
  );
}

function LogsScreen({ ctx, route }) {
  const { skin } = ctx;
  const scope = ctx.logScope || route.scope || 'usage';
  const account = ctx.logAccount !== undefined ? ctx.logAccount : route.account || null;
  const pick = {
    usage: l => l.code === 200,
    errors: l => l.kind === '错误请求',
    upstream: l => l.kind === '上游错误',
  };
  const all = DEMO.logs.filter(l => !account || l.account === account);
  const rows = all.filter(pick[scope]);
  const count = k => all.filter(pick[k]).length;
  return (
    <Screen plain ctx={ctx} nav={<NavBar ctx={ctx} back title="使用记录" subtitle={`${ctx.site} · 近 24 小时`} trailing={<GlassButton icon="filter" />} />}>
      <div className="pad-x"><Segmented value={scope} onChange={ctx.setLogScope} items={[
        { key: 'usage', label: '用量明细', count: count('usage') },
        { key: 'errors', label: '错误请求', count: count('errors') },
        { key: 'upstream', label: '上游错误', count: count('upstream') },
      ]} /></div>
      <div className="chips tokens">
        <button className="chip on token"><span>近 24 小时</span><Icon name="chevronDown" size={12} weight={2.6} /></button>
        {account && <button className="chip on token" onClick={() => ctx.setLogAccount(null)}><span>账号：{account}</span><Icon name="close" size={12} weight={2.8} /></button>}
        <button className="chip token-add" onClick={() => ctx.openSheet({ kind: 'picker' })}><Icon name="plus" size={13} weight={2.6} /><span>筛选</span></button>
      </div>
      <div className="list-group">
        <div className="list-head"><span>今天</span><b className="num">{rows.length}</b></div>
        {rows.length === 0 && <div className="empty pad">这个范围内没有记录</div>}
        {rows.map((l, i) => {
          const tone = l.code === 200 ? 'none' : l.code === 429 || l.code === 504 ? 'caution' : 'critical';
          return (
            <Row key={i} skin={skin} tone={tone} className={`tone-${tone === 'none' ? 'ok' : tone}`} lead={<skin.Code code={l.code} />} onClick={() => {}}>
              <div className="row-top"><span className="row-title model">{l.model}</span><span className="row-right num dim">{l.t}</span></div>
              <div className="row-meta">{l.user} · {l.account} · {l.cost !== null ? <skin.Money value={l.cost} size="s" small /> : <span className="num">—</span>} · <span className="num">{l.dur}</span></div>
            </Row>
          );
        })}
      </div>
    </Screen>
  );
}

function PickerSheet({ ctx }) {
  const { skin } = ctx;
  const [q, setQ] = useState('');
  const accounts = DEMO.accounts.filter(a => a.name.toLowerCase().includes(q.toLowerCase())).slice(0, 6);
  const users = DEMO.users.filter(u => (u.name + u.email).toLowerCase().includes(q.toLowerCase())).slice(0, 3);
  const choose = name => { ctx.setLogAccount(name); ctx.closeSheet(); };
  return (
    <Sheet title="按对象筛选" onClose={ctx.closeSheet} tall>
      <label className="search-field"><Icon name="search" size={16} /><input autoFocus placeholder="账号名、邮箱或分组" value={q} onChange={e => setQ(e.target.value)} /></label>
      <div className="picker-group">账号</div>
      {accounts.map(a => (
        <Row key={a.id} skin={skin} tone="none" lead={<skin.Glyph state={a.state} />} onClick={() => choose(a.name)} chevron={false}>
          <div className="row-top"><span className="row-title">{a.name}</span><span className="row-right dim">#{a.id}</span></div>
          <div className="row-meta">{a.platform} · {a.groups.join('、') || '未分组'}</div>
        </Row>
      ))}
      <div className="picker-group">用户</div>
      {users.map(u => (
        <Row key={u.id} skin={skin} tone="none" lead={<span className="avatar">{u.name.slice(0, 1)}</span>} onClick={ctx.closeSheet} chevron={false}>
          <div className="row-top"><span className="row-title">{u.name}</span></div>
          <div className="row-meta">{u.email}</div>
        </Row>
      ))}
    </Sheet>
  );
}


/* ---------- phone state machine ---------- */

function InboxPhone({ skin, dark, initial }) {
  const app = useAppModel(initial);
  const [tab, setTab] = useState(initial.tab);
  const [stacks, setStacks] = useState(() => ({ today: [], accounts: [], users: [], monitor: [], search: [], [initial.tab]: initial.stack || [] }));
  const [acctFilter, setAcctFilter] = useState(initial.acctFilter || 'all');
  const [logScope, setLogScope] = useState(null);
  const [logAccount, setLogAccount] = useState(undefined);
  const [selecting, setSelecting] = useState(Boolean(initial.selecting));
  const [selected, setSelected] = useState([]);

  const ctx = {
    ...app, skin, tab, acctFilter, logScope, logAccount, selecting, selected,
    push: route => setStacks(s => ({ ...s, [tab]: [...s[tab], route] })),
    pop: () => { setStacks(s => ({ ...s, [tab]: s[tab].slice(0, -1) })); setLogScope(null); setLogAccount(undefined); },
    switchTab: (key, opts = {}) => {
      if (key === tab && !opts.filter) setStacks(s => ({ ...s, [key]: [] }));
      setTab(key);
      if (opts.filter) { setAcctFilter(opts.filter); setStacks(s => ({ ...s, accounts: [] })); }
      setSelecting(false);
    },
    setAcctFilter, setLogScope, setLogAccount,
    toggleSelecting: () => { setSelecting(v => !v); setSelected([]); },
    toggleSelect: id => setSelected(s => (s.includes(id) ? s.filter(x => x !== id) : [...s, id])),
    bulkSchedule: enable => { app.setSchedule(selected, enable); setSelecting(false); setSelected([]); },
  };

  const stack = stacks[tab];
  const top = stack[stack.length - 1];
  let screen;
  if (top && top.kind === 'account') screen = <AccountDetail ctx={ctx} id={top.id} />;
  else if (top && top.kind === 'user') screen = <UserDetail ctx={ctx} id={top.id} />;
  else if (top && top.kind === 'logs') screen = <LogsScreen ctx={ctx} route={top} />;
  else if (tab === 'today') screen = <TodayScreen ctx={ctx} />;
  else if (tab === 'accounts') screen = <AccountsScreen ctx={ctx} />;
  else if (tab === 'users') screen = <UsersScreen ctx={ctx} />;
  else if (tab === 'monitor') screen = <MonitorScreen ctx={ctx} />;
  else screen = <SearchHome ctx={ctx} />;

  return (
    <PhoneFrame dark={dark} canvas={skin.canvas(dark)} className={cx(`dir-${skin.key}`, skin.appClass)}>
      {screen}
      <TabBar ctx={ctx} />
      <Overlays ctx={ctx}>
        {ctx.sheet && ctx.sheet.kind === 'topup' && <TopupSheet ctx={ctx} sheet={ctx.sheet} />}
        {ctx.sheet && ctx.sheet.kind === 'picker' && <PickerSheet ctx={ctx} />}
      </Overlays>
    </PhoneFrame>
  );
}

const INBOX_PHONES = [
  { label: '今日 · 待处理在前，营收不被挤掉', initial: { tab: 'today' } },
  { label: '账号 · 需处理优先，限流带倒计时', initial: { tab: 'accounts', acctFilter: 'all' } },
  { label: '账号详情 · 现在怎么了、何时恢复、能做什么', initial: { tab: 'accounts', stack: [{ kind: 'account', id: 3 }] } },
  { label: '充值 · 无默认金额，余额预览，资金确认', initial: { tab: 'users', stack: [{ kind: 'user', id: 1 }], sheet: { kind: 'topup', userId: 1, mode: 'topup', amount: '50' } } },
  { label: '使用记录 · 名称筛选替代手输 ID', initial: { tab: 'search', stack: [{ kind: 'logs', scope: 'usage', account: 'Claude-官方-01' }] } },
  { label: '监控 · 渠道状态，灯只为异常而亮', initial: { tab: 'monitor' } },
];

const INBOX_STRUCTURE = [
  ['导航', '底部 4 个 Tab（今日 · 账号 · 用户 · 监控）+ 搜索；站点切换在标题菜单'],
  ['首页', '待处理队列在前（逐个账号、原因、倒计时、可直接测试），营收压成顶部一行'],
  ['账号列表', '满宽三行列表，按“需处理 / 暂停与停用 / 正常”分组，筛选胶囊在顶部'],
  ['账号详情', '状态卡（倒计时大数）+ 一排按钮 + 容量 / 今日 / 记录 / 档案分区'],
  ['批量', '“选择”进入勾选模式，底部浮出操作坞'],
  ['日志', '不占 Tab：从搜索页目录或对象详情进入；分段 + 筛选胶囊 + 对象选择器'],
  ['充值', '金额输入 + 快捷金额 + 余额预览 + 确认对话框'],
];

function mountInbox(skin, extra = {}) {
  mountPage({
    key: skin.key,
    pageClass: cx(`page-${skin.key}`, skin.pageClass),
    title: skin.title,
    concept: skin.concept,
    traits: skin.traits,
    defaultDark: skin.defaultDark,
    phones: INBOX_PHONES,
    structure: INBOX_STRUCTURE,
    App: props => <InboxPhone skin={skin} {...props} />,
    ...extra,
  });
}
