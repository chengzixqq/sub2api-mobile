/* 主模式（main）：以 A 收件箱为骨架，叠加已定决策（DECISIONS.md）——充值用 B 的大数字键盘、日志行右侧固定金额与耗时、
   成功 / 失败请求都有详情页。待定的选择通过“变体槽”比较：每个槽有一个 base 实现，layouts/main/v-*.jsx 注册替代实现，
   手机用 initial.v = { 槽名: 变体名, vis: 外观名 } 选择。 */

const TAB_DEFS = [
  { key: 'today', label: '概览', icon: 'home' },
  { key: 'accounts', label: '账号', icon: 'server' },
  { key: 'users', label: '用户', icon: 'people' },
  { key: 'monitor', label: '监控', icon: 'pulse' },
];

/* ---------- variant slots ---------- */

const MV = { slots: {} };

// Register a component as variant `key` of `slot`. `base` is the decided default and is registered in this file.
function mvRegister(slot, key, Comp) {
  MV.slots[slot] = MV.slots[slot] || {};
  MV.slots[slot][key] = Comp;
}

// Render the variant of `slot` chosen by ctx.v[slot], falling back to base.
function Slot({ slot, ctx, ...props }) {
  const table = MV.slots[slot] || {};
  const key = (ctx.v && ctx.v[slot]) || 'base';
  const Comp = table[key] || table.base;
  return <Comp ctx={ctx} {...props} />;
}

const MainSkin = makeSkin({ key: 'instrument', chartStyle: 'bars', canvas: dark => (dark ? '#0B0E10' : '#F1F3F4'), appClass: 'pal-vernier' });

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
    const at = alertTone(DEMO.alert);
    items.push(
      <Row key="alert" skin={skin} tone={at} className={`tone-${at}`} lead={<span className="lead-icon"><Icon name="bell" /></span>}
        onClick={() => ctx.push({ kind: 'alert', id: DEMO.alert.id })}>
        <div className="row-top"><span className="row-title">{DEMO.alert.title}</span><skin.Badge tone={at} label={DEMO.alert.level} /></div>
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
  // Same rule as the top-up: a generation whose answer never came back must be checked before generating again.
  const rp = ctx.redeemPending;
  if (rp) {
    items.push(
      <Row key="redeem" skin={skin} tone="caution" className="tone-caution" lead={<span className="lead-icon"><Icon name="docCheck" /></span>}
        onClick={() => ctx.push({ kind: 'redeem', reconcile: true })}>
        {/* Concurrency, subscription and invitation batches carry no money (total null): no amount on the right. */}
        <div className="row-top"><span className="row-title">兑换码生成结果待核对</span>{rp.total !== null && rp.total !== undefined && <skin.Money value={rp.total} size="m" />}</div>
        <div className="row-meta">{rp.count} 个兑换码 · {rp.ago} · 未收到结果</div>
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
      <Section skin={skin} title="今日" meta="00:00 起" index="贰"><skin.TodayBlock ctx={ctx} />
        <Row skin={skin} tone="none" lead={<span className="lead-icon dim"><Icon name="chart" /></span>} onClick={() => ctx.push({ kind: 'analytics' })}>
          <div className="row-top"><span className="row-title">更多统计</span><span className="row-right dim">模型 · 用户 · 分组排行</span></div>
        </Row>
      </Section>
      <Section skin={skin} title="运行" index="叁">
        <div className="pad"><skin.Health score={DEMO.run.health} /></div>
        <div className="kv-row pad">
          <span>错误率 <b className="num">{errorRate()}</b></span>
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

/* Second line of an account row: “平台 · 分组”. Inside a section whose header already names a dimension, drop it:
   omit 'platform' → only the groups; omit 'group' (with home = that section's group name) → the platform plus “另属 …” for the
   account's other groups. short = true folds several groups into “X 等 n 组” / “另属 n 组” for the narrow row styles. */
function accountWhere(a, omit, home, short) {
  const groups = a.groups.length ? a.groups : ['未分组'];
  const list = gs => (short && gs.length > 1 ? `${gs[0]} 等 ${gs.length} 组` : gs.join('、'));
  if (omit === 'platform') return list(groups);
  if (omit === 'group') {
    const others = a.groups.filter(g => g !== home);
    if (!others.length) return a.platform;
    return `${a.platform} · 另属 ${short && others.length > 1 ? `${others.length} 组` : others.join('、')}`;
  }
  return `${a.platform} · ${list(groups)}`;
}

// omit / home: see accountWhere. Grouped list variants pass them through Slot so every row style can drop the header's dimension.
function AccountRow({ ctx, a, omit, home }) {
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
  const stopped = schedLabel(a);
  let third;
  if (a.state === 'error') third = <div className="row-note">{a.error}</div>;
  // The stop mark leads the line so truncation only ever cuts the model-limit tail. The tail reads “模型限流 N” (the detail
  // page's heading) so “已停止调度 · 上游 429 · 09:45 恢复 · 模型限流 2” still fits a 393pt row.
  else if (meta.timed) third = <div className="row-note">{stopped && <><span className="sched-mark">{stopped}</span> · </>}{a.cause} · <span className="num">{fmt.clock(DEMO_CLOCK_BASE + (elapsed + secs) * 1000)}</span> 恢复{a.modelLimits && a.modelLimits.length ? ` · 模型限流 ${a.modelLimits.length}` : ''}</div>;
  else third = (
    <div className="row-cap">
      {cap ? <skin.Capacity used={cap.used} limit={cap.limit} label={cap.label} /> : <span className="cap-missing"><span className="num">—</span> 并发</span>}
      <span className="row-money"><small>今日</small><skin.Money value={a.todayCost} size="s" /></span>
    </div>
  );
  return (
    <Row skin={skin} tone={ctx.selecting ? 'none' : tone} className={cx(`tone-${tone}`, a.state === 'paused' || a.state === 'inactive' ? 'is-idle' : '', selected && 'is-selected')} lead={lead} onClick={onClick} chevron={!ctx.selecting}>
      <div className="row-top"><span className="row-title">{a.name}</span><skin.Badge state={a.state} secs={secs} /></div>
      <div className="row-meta">{accountWhere(a, omit, home)} · {a.type}</div>
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
        {rows.map(a => <Slot slot="accountRow" key={a.id} ctx={ctx} a={a} />)}
      </div>
    ));
  } else {
    const rows = list.filter(pick[filter] || (() => true));
    body = <div className="list-group">{rows.map(a => <Slot slot="accountRow" key={a.id} ctx={ctx} a={a} />)}</div>;
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
        trailing={!ctx.selecting && <><GlassButton icon="filter" /><GlassButton icon="plus" onClick={() => ctx.push({ kind: 'accountNew' })} /></>} />
    }>
      <Chips items={chips} value={filter} onChange={k => k !== 'platform' && ctx.setAcctFilter(k)} />
      {body}
    </Screen>
  );
}

/* The fix for a credential error when the page hands AccountDetailTop no handler of its own (the base detail): the decided inline
   page's 凭据 section (screen:accountEdit, focus 'cred') when the build has it, otherwise a note saying where the fix lives. */
function accountCredentialFix(ctx, a) {
  // OAuth and Setup Token both re-authorize (isTokenAccount); only API Key accounts take a new key.
  const oauth = isTokenAccount(a);
  if (MV.slots['screen:accountEdit']) { ctx.push({ kind: 'accountEdit', id: a.id, focus: 'cred' }); return; }
  ctx.confirm({
    title: oauth ? `重新授权「${a.name}」` : `更换「${a.name}」的 API Key`,
    message: oauth
      ? '令牌已失效。在编辑账号的“凭据”里重新授权：生成授权链接 → 浏览器授权 → 粘贴授权码。授权后自动清除错误，调度开关不变。'
      : '上游拒绝了当前密钥。在编辑账号的“凭据”里填入新的 API Key，保存后立即生效；再测试连接，通过后自动清除错误（仍暂停调度）。\n只恢复状态的话，下一次请求还会出错。',
    actions: [{ label: '知道了', role: 'cancel' }],
  });
}

/* Everything of the account page above 档案: state card + button row, 容量, 今日, 记录 (upstream errors / usage, filtered by
   this account). Shared by the base page and variants that replace only what follows (the decided inline-edit page), so the
   card, the schedule switch and the recovery choices never drift apart.
   A credential error (isCredentialError: 401 / 403, invalid_api_key, revoked token) leads with the fix — 更换 API Key… (OAuth and
   Setup Token, isTokenAccount: 重新授权…, as Web's AccountActionMenu) — and 恢复状态 steps back, because recovering alone fails again on the next request. extraActions = {replaceKey?, reauth?}
   lets a variant open its own sheet for them (v-account-edit); without it the base fix (accountCredentialFix) runs. Once the key was
   replaced (aeKeyReplaced) the error stays until a test passes, so 测试连接 leads instead. */
function AccountDetailTop({ ctx, a, extraActions }) {
  const { skin, elapsed } = ctx;
  const id = a.id;
  const meta = STATE_META[a.state];
  const tone = toneOf(a.state);
  const secs = remaining(a, elapsed);
  const until = fmt.clock(DEMO_CLOCK_BASE + (elapsed + (secs || 0)) * 1000);
  const on = isSchedulable(a);
  const stopped = schedLabel(a);
  const lastErr = a.state === 'error' ? lastUpstreamError(id, elapsed) : null;
  // Same rule as the list it opens (logsWhere = the usage page's scope + account filter), so the count and the rows always agree.
  const upstream24h = logCount({ scope: 'upstream', account: id });

  // The schedule switch never overwrites a runtime state: stopping a rate-limited account keeps the countdown and adds a mark.
  const recover = () => confirmRecover(ctx, a);
  const pause = () => ctx.setSchedule([id], false);
  const resume = () => ctx.setSchedule([id], true);
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
        {/* The backend keeps no “errored at” time; the newest upstream error log of this account stands in (upstream-errors?account_id&page_size=1). */}
        {a.state === 'error' && lastErr && (
          <button className="hero-last" onClick={() => ctx.push({ kind: 'request', id: lastErr.id })}>
            <span>最近上游错误 <b className="num">{lastErr.t}</b> · {lastErr.ago} · <span className="num">{lastErr.code}</span></span>
            <Icon name="chevron" size={12} weight={2.6} />
          </button>
        )}
        {stopped && <div className="hero-sched"><Icon name="pauseFill" size={13} /><span><b>{stopped}</b> · 到时恢复后也不参与调度</span></div>}
        {a.state === 'error' && <div className="hero-sched"><Icon name="pauseFill" size={13} /><span><b>出错时已自动停止调度</b> · 恢复时可一并启用</span></div>}
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

  // One name for the action everywhere (文案硬规则: 测试连接), whether the row holds two buttons or three.
  const testBtn = <ActionButton key="t" label="测试连接" icon="wave" onClick={test} />;
  // 启用账号 is reversible (PUT status active ⇄ inactive), so the receipt offers 撤销 like the schedule switch.
  const enableAccount = () => ctx.updateAccount(id, { state: on ? 'normal' : 'paused' }, { text: `已启用账号「${a.name}」`, icon: 'play', undo: true });
  let actions;
  if (a.state === 'normal') actions = [<ActionButton key="t" label="测试连接" icon="wave" onClick={test} primary />, <ActionButton key="p" label="停止调度" icon="pauseFill" onClick={pause} />];
  else if (a.state === 'inactive') actions = [<ActionButton key="r" label="启用账号" icon="play" onClick={enableAccount} primary />, testBtn];
  else if (a.state === 'paused') actions = [<ActionButton key="r" label="启用调度" icon="play" onClick={resume} primary />, testBtn];
  // Credential error: the fix first, 恢复状态 second (it would only fail again); after the key was replaced, the test clears the error.
  else if (isCredentialError(a) && !a.aeKeyReplaced) {
    const oauth = isTokenAccount(a);
    const own = extraActions && (oauth ? extraActions.reauth : extraActions.replaceKey);
    const fix = own || (() => accountCredentialFix(ctx, a));
    actions = [<ActionButton key="f" label={oauth ? '重新授权…' : '更换 API Key…'} icon="key" onClick={fix} primary />,
      <ActionButton key="r" label="恢复状态" icon="restore" onClick={recover} />, testBtn];
  }
  else if (isCredentialError(a)) actions = [<ActionButton key="t" label="测试连接" icon="wave" onClick={test} primary />, <ActionButton key="r" label="恢复状态" icon="restore" onClick={recover} />];
  // Errored: scheduling is already off and turning it on alone would not help, so recovery offers both choices instead.
  else if (a.state === 'error') actions = [<ActionButton key="r" label="恢复状态" icon="restore" onClick={recover} primary />, testBtn];
  else actions = [<ActionButton key="r" label="恢复状态" icon="restore" onClick={recover} primary />, testBtn,
    on ? <ActionButton key="p" label="停止调度" icon="pauseFill" onClick={pause} /> : <ActionButton key="p" label="启用调度" icon="play" onClick={resume} />];

  // rpm (base_rpm) and sessions (max_sessions) exist only where the account sets them (Anthropic OAuth / Setup Token); the group's capacity sums them.
  const caps = [
    a.conc && { label: '并发', used: a.conc[0], limit: a.conc[1] },
    a.rpm && { label: '调度 RPM', used: a.rpm[0], limit: a.rpm[1], note: '自然分钟' },
    a.sessions && { label: '会话', used: a.sessions[0], limit: a.sessions[1], note: '空闲 5 分钟释放' },
    a.dayQuota && { label: '日配额', used: a.dayQuota[0], limit: a.dayQuota[1], money: true },
    a.window5h !== undefined && { label: '5 小时窗口', ratio: a.window5h },
  ].filter(Boolean);

  return (
    <>
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
          <div><small data-kind="cost">账号成本</small><skin.Money value={a.todayAccountCost ?? null} size="l" kind="cost" /></div>
          <div><small data-kind="standard">标准</small><skin.Money value={a.todayStd ?? null} size="l" kind="standard" /></div>
        </div>
        <div className="kv-row pad">
          <span>请求 <b className="num">{fmt.grouped(a.todayReq)}</b></span>
          <span>Tokens <b className="num">{fmt.compact(a.todayTokens ?? null)}</b></span>
        </div>
      </Section>
      <Section skin={skin} title="记录" index="叁">
        <Row skin={skin} tone="none" lead={<span className="lead-icon dim"><Icon name="octagon" /></span>} onClick={() => ctx.push({ kind: 'logs', scope: 'upstream', account: a.id })}>
          <div className="row-top"><span className="row-title">上游错误</span><span className="row-right num">近 24 小时 {upstream24h} 条</span></div>
        </Row>
        <Row skin={skin} tone="none" lead={<span className="lead-icon dim"><Icon name="list" /></span>} onClick={() => ctx.push({ kind: 'logs', scope: 'usage', account: a.id })}>
          <div className="row-top"><span className="row-title">使用记录</span></div>
        </Row>
      </Section>
    </>
  );
}

// A removed account (ctx.removeAccount) can still sit in another tab's stack; that page says so instead of breaking.
function RemovedAccount({ ctx }) {
  return (
    <Screen ctx={ctx} nav={<NavBar ctx={ctx} back title="账号" subtitle="已删除" />}>
      <div className="empty pad">这个账号已删除。</div>
    </Screen>
  );
}

// Proxy line of the account (DEMO.proxies via the account's proxy name): “hk-02 · SOCKS5 · 6 天后到期” / “无代理”. The expiry part is
// the proxies page's wording (proxyExpiry), shown only when it needs a look (expired, or within warnDays); a disabled proxy says 已停用.
function accountProxyText(a) {
  if (!a.proxy) return '无代理';
  const p = proxyOf(a.proxy);
  if (!p) return a.proxy;
  const e = proxyExpiry(p);
  const when = p.status === 'inactive' ? '已停用' : e.tone !== 'none' ? e.label : null;
  return [p.name, proxyProto(p), when].filter(Boolean).join(' · ');
}

function AccountDetail({ ctx, id }) {
  const { skin } = ctx;
  const a = ctx.accounts[id];
  if (!a) return <RemovedAccount ctx={ctx} />;
  return (
    <Screen ctx={ctx} nav={<NavBar ctx={ctx} back title={a.name} subtitle={`${a.platform} · ${a.type}`} trailing={<GlassButton icon="more" onClick={() => accountMenu(ctx, a)} />} />}>
      <AccountDetailTop ctx={ctx} a={a} />
      <Section skin={skin} title="档案" index="肆">
        <div className="kv-grid pad">
          <KV label="平台" value={a.platform} /><KV label="类型" value={a.type} />
          <KV label="分组" value={a.groups.join('、') || '未分组'} /><KV label="优先级" value={a.priority} />
          <KV label="代理" value={accountProxyText(a)} /><KV label="到期" value={a.expires || '—'} />
        </div>
      </Section>
    </Screen>
  );
}


/* ---------- 用户 ---------- */

// api_keys.status words as Web has them; active needs no word.
const KEY_STATUS_WORD = { disabled: '已停用', quota_exhausted: '额度耗尽', expired: '已过期' };

function UsersScreen({ ctx }) {
  const { skin } = ctx;
  // Newest first, like Web (created_at desc; the demo falls back to id desc).
  const list = usersNewestFirst(ctx.users);
  return (
    <Screen plain ctx={ctx} nav={<NavBar ctx={ctx} title="用户" subtitle={`${ctx.site} · ${list.length} 位`} trailing={<GlassButton icon="plus" onClick={() => ctx.push({ kind: 'userNew' })} />} />}>
      <div className="search-field"><Icon name="search" size={16} /><span>邮箱、用户名或备注</span></div>
      <div className="list-group">
        {list.map(u => {
          const low = u.status !== 'disabled' && u.balance < 10;
          const tone = u.status === 'disabled' ? 'neutral' : u.pending ? 'caution' : low ? 'caution' : 'none';
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
                {low && !u.pending && <skin.Badge tone="caution" label="余额低" />}
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
  const reconcile = () => reconcileUser(ctx, u);
  return (
    <Screen ctx={ctx} nav={<NavBar ctx={ctx} back title={u.name} subtitle={u.email} trailing={<GlassButton icon="more" onClick={() => userMenu(ctx, u)} />} />}>
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
          <ActionButton label="充值" icon="plus" primary onClick={() => ctx.openSheet({ kind: 'keypad', userId: id, mode: 'topup' })} />
          <ActionButton label="退款" icon="restore" onClick={() => ctx.openSheet({ kind: 'keypad', userId: id, mode: 'refund' })} />
        </div>
      </div>
      {/* users[].keys = the user's rows of DEMO.keys (every user has the list; it may be empty). */}
      <Section skin={skin} title="API Key" meta={`${(u.keys || []).length} 个`} index="壹">
        {(u.keys || []).map(k => {
          const st = KEY_STATUS_WORD[k.status];
          return (
            <Row key={k.masked} skin={skin} tone="none" className={st ? 'is-idle' : undefined} lead={<span className="lead-icon dim"><Icon name="key" /></span>} chevron={false}>
              <div className="row-top"><span className="row-title">{k.label}</span><span className="row-right mono">{k.masked}</span></div>
              <div className="row-meta">{k.group || '未绑定分组'}{st ? ` · ${st}` : ''} · 最近使用 {k.used || '—'}</div>
            </Row>
          );
        })}
        {!(u.keys || []).length && <div className="empty pad">还没有 Key，由用户在 Web 端创建</div>}
      </Section>
      {/* balance-history: kind, amount, time, admin note. It has no "balance after", so the line never shows one. Items without an
          amount (concurrency, subscription) carry their own display text (Web formatValue: “+2”、“30d - 分组”). Redeemed items show
          the code's first 8 characters under the value (ledgerCode, as Web), pinned right on line 2. */}
      <Section skin={skin} title="充值与调整记录" index="贰">
        {(u.ledger || []).length ? (u.ledger || []).map((l, i) => (
          <div key={i} className="ledger-line pad">
            <div className="ledger-top"><span>{l.kind}</span>{l.amount === null || l.amount === undefined ? <span className="num ledger-display">{l.display || '—'}</span> : <skin.Money value={l.amount} size="m" sign />}</div>
            <div className="ledger-sub">
              <div className="row-meta"><span className="num">{l.when}</span>{l.note && <span className="ledger-note">· {l.note}</span>}</div>
              {ledgerCode(l) && <span className="ledger-code mono" aria-label={`兑换码 ${l.code.slice(0, 8)} 开头`}>{ledgerCode(l)}</span>}
            </div>
          </div>
        )) : <div className="empty pad">暂无记录</div>}
      </Section>
      <Section skin={skin} title="档案" index="叁">
        <div className="kv-grid pad">
          <KV label="状态" value={u.status === 'disabled' ? '禁用' : '启用'} /><KV label="分组" value={u.group || '—'} />
          <KV label="并发上限" value={u.conc ?? '—'} /><KV label="角色" value={u.role === 'admin' ? '管理员' : '用户'} />
        </div>
      </Section>
    </Screen>
  );
}

// Decided in round 1: B's big-number keypad (Apple Cash style). No default amount; refund offers "全部余额".
// Round 3: an optional note line above the amount (balance API `notes`), shown again in the confirm and in the record.
function KeypadSheet({ ctx, sheet }) {
  const u = ctx.users[sheet.userId];
  const [mode, setMode] = useState(sheet.mode);
  const [amount, setAmount] = useState(sheet.amount || '');
  const [note, setNote] = useState(sheet.note || '');
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
      <div className="kp-user"><span className="kp-avatar">{u.name.slice(0, 1)}</span>{u.name} · 余额 <span className="num">{fmt.money(u.balance)}</span>{u.status === 'disabled' && <ctx.skin.Badge tone="neutral" label="已禁用" />}</div>
      <label className="kp-note">
        <span className="kp-note-label">备注</span>
        <input value={note} onChange={e => setNote(e.target.value)} placeholder="可选，写进充值记录" aria-label="备注（可选）" />
        {note && <button className="kp-note-clear" onClick={e => { e.preventDefault(); setNote(''); }} aria-label="清除备注"><Icon name="close" size={13} weight={2.6} /></button>}
      </label>
      <div className={cx('kp-amount num', !amount && 'is-empty')}>{mode === 'refund' && '−'}${amount || '0'}</div>
      <div className={cx('kp-preview', over && 'tone-critical tone-text')}>
        {over ? '超过当前余额' : value ? <>{verb}后余额 <b className="num">{fmt.money(after)}</b></> : '输入金额'}
      </div>
      {mode === 'refund' && <button className="kp-pill" onClick={() => setAmount(String(u.balance))}>全部余额 {fmt.money(u.balance)}</button>}
      <div className="kp-pad">
        {['1', '2', '3', '4', '5', '6', '7', '8', '9', '.', '0', 'del'].map(k => (
          <button key={k} className="kp-key num" onClick={() => press(k)} aria-label={k === 'del' ? '删除' : k}>
            {k === 'del' ? <Icon name="deleteLeft" size={24} weight={1.9} /> : k}
          </button>
        ))}
      </div>
      <button className="submit" disabled={!value || over} onClick={() => submitBalanceChange(ctx, u, mode, value, note, ctx.closeSheet)}>{value ? `${verb} ${fmt.money(value)}` : verb}</button>
    </Sheet>
  );
}

/* ---------- 监控 ---------- */

// Decided in round 2: three segments 概况 | 渠道 | 告警. 概况 carries a server-status block for admins only
// (ops overview system_metrics, concurrency, job heartbeats, ingest health); vendors and end users never see it.
const ALERT_STATUS = { firing: '告警中', resolved: '已恢复', manual_resolved: '已手动解决' };

function MonServer({ ctx }) {
  const { skin } = ctx;
  const s = DEMO.server;
  const bad = s.jobs.filter(j => !j.ok);
  const meter = (label, value, trend) => (
    <div className="mo-meter">
      <div className="mo-meter-top"><span>{label}</span><b className="num">{value}%</b></div>
      <skin.Capacity ratio={value / 100} wide />
      <Sparkline values={trend} w={120} h={22} max={100} className="mo-spark" />
    </div>
  );
  return (
    <Section skin={skin} title="服务器" meta="仅管理员可见" index="贰">
      <div className="mo-meters pad">{meter('CPU', s.cpu, s.cpuTrend)}{meter('内存', s.mem, s.memTrend)}</div>
      <div className="kv-row pad">
        <span>并发 <b className="num">{s.concurrency.used}/{s.concurrency.cap}</b></span>
        <span>排队 <b className="num">{s.concurrency.queue}</b></span>
        <span>QPS <b className="num">{s.qps.toFixed(1)}</b></span>{/* backend overview rounds QPS to 1 dp (roundTo1DP), same as 统计分析 */}
        <span>SLA <b className="num">{s.sla}%</b></span>
      </div>
      {s.jobs.map(j => (
        <Row key={j.job || j.name} skin={skin} tone={j.ok ? 'none' : 'caution'} className={j.ok ? '' : 'tone-caution'} chevron={false}
          lead={<skin.Glyph state={j.ok ? 'normal' : 'temp_unsched'} />}>
          <div className="row-top"><span className="row-title">{j.name}</span><span className={cx('row-right num', !j.ok && 'tone-text')}>{j.ok ? j.last : `最近成功 ${j.last}`}</span></div>
          {j.note && <div className="row-note">{j.note}</div>}
        </Row>
      ))}
      <Row skin={skin} tone="none" chevron={false} lead={<skin.Glyph state={s.ingest.ok ? 'normal' : 'error'} />}>
        <div className="row-top"><span className="row-title">日志采集</span><span className="row-right num">延迟 {s.ingest.lag}</span></div>
        <div className="row-meta">入口拒绝 {s.rejections} 次（1 小时）{bad.length ? ` · ${bad.length} 个任务需留意` : ''}</div>
      </Row>
    </Section>
  );
}

function MonOverview({ ctx }) {
  const { skin } = ctx;
  const firing = ctx.alerts.filter(a => a.status === 'firing');
  return (
    <>
      <Section skin={skin} title="运行" index="壹">
        <div className="pad"><skin.Health score={DEMO.run.health} /></div>
        <div className="kv-row pad">
          <span>错误率 <b className="num">{errorRate()}</b></span>
          <span>上游 429 <b className="num">{DEMO.run.r429}</b></span>
          <span>529 <b className="num">{DEMO.run.r529}</b></span>
        </div>
        <div className="mo-trend pad"><small>错误率 · 近 45 分钟</small><Sparkline values={DEMO.run.errorTrend} w={300} h={40} area /></div>
        <Row skin={skin} tone={firing.length ? 'caution' : 'none'} className={firing.length ? 'tone-caution' : ''} lead={<span className="lead-icon"><Icon name="bell" /></span>} onClick={() => ctx.setMonSeg('alerts')}>
          <div className="row-top"><span className="row-title">告警中 {firing.length} 条</span></div>
          <div className="row-meta mo-wrap">{firing.map(a => a.title).join('、') || '没有告警'}</div>
        </Row>
      </Section>
      {ctx.role === 'admin' && <MonServer ctx={ctx} />}
    </>
  );
}

function MonChannels({ ctx }) {
  const { skin } = ctx;
  const order = ['critical', 'caution', 'neutral', 'ok'];
  const list = [...DEMO.channels].sort((a, b) => order.indexOf(a.state) - order.indexOf(b.state));
  const label = { ok: '可用', caution: '性能下降', critical: '不可用', neutral: '未知' };
  return (
    <>
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
    </>
  );
}

// Silence durations as on Web (OpsAlertEventsCard: 1h / 24h / 7d); the second item is now + duration on the demo clock (10/16 09:41).
const ALERT_SILENCE = [['1 小时', '10:41'], ['24 小时', '明天 09:41'], ['7 天', '10月23日 09:41']];

/* Alert rows of 监控 · 告警 and of the pushed 告警 page. Handling lives in ctx (ctx.alerts / resolveAlert / silenceAlert), so every page
   of the phone — home, monitor, alert page — agrees. focus = an event id listed first in its group; open = tapping a row opens
   {kind:'alert', id} (screen:alert: v-today's full alert page, or core's list as the fallback). The pushed list itself passes no open. */
function MonAlerts({ ctx, focus, open }) {
  const { skin } = ctx;
  const alerts = focus ? [...ctx.alerts].sort((x, y) => (y.id === focus) - (x.id === focus)) : ctx.alerts;
  const resolve = a => ctx.confirm({
    title: `手动解决「${a.title}」？`,
    message: '告警会标记为已手动解决；如果条件仍然满足，下一次评估会重新触发。',
    actions: [
      { label: '手动解决', role: 'default', onPress: () => ctx.resolveAlert(a.id, { text: '已手动解决', icon: 'checkCircle' }) },
      { label: '取消', role: 'cancel' },
    ],
  });
  const silence = a => ctx.confirm({
    title: `静默「${a.title}」多久？`,
    message: '静默期间这条规则不再产生新的告警事件。当前这条仍需手动解决。',
    actions: [
      ...ALERT_SILENCE.map(([span, until]) => ({ label: span, role: 'default', onPress: () => ctx.silenceAlert(a.id, until, { text: `已静默 ${span}`, icon: 'hourglass', tone: 'neutral' }) })),
      { label: '取消', role: 'cancel' },
    ],
  });
  const groups = [['告警中', alerts.filter(a => a.status === 'firing')], ['最近结束', alerts.filter(a => a.status !== 'firing')]];
  return groups.map(([title, rows], gi) => (
    <Section key={title} skin={skin} title={title} meta={`${rows.length} 条`} index={['壹', '贰'][gi]}>
      {rows.length === 0 && <div className="empty pad">没有告警</div>}
      {rows.map(a => {
        const tone = alertTone(a);
        return (
          <Row key={a.id} skin={skin} tone={tone} className={tone === 'none' ? 'is-idle' : `tone-${tone}`} chevron={Boolean(open)}
            onClick={open ? () => ctx.push({ kind: 'alert', id: a.id }) : undefined}
            lead={<span className={cx('lead-icon', tone === 'none' && 'dim')}><Icon name={a.status === 'firing' ? 'bell' : 'checkCircle'} /></span>}>
            <div className="row-top"><span className="row-title">{a.title}</span><skin.Badge tone={tone === 'none' ? 'neutral' : tone} label={`${a.level} · ${ALERT_STATUS[a.status]}`} /></div>
            <div className="row-meta mo-wrap">{a.scope} · {a.rule}</div>
            {a.status === 'firing' && a.silencedUntil && <div className="row-meta mo-silenced"><Icon name="hourglass" size={13} weight={2.4} />已静默至 <span className="num">{a.silencedUntil}</span></div>}
            <div className="row-foot"><span className="row-meta">{a.since}</span>
              {a.status === 'firing' && <span className="mo-actions"><ActionButton small label={a.silencedUntil ? '改静默…' : '静默…'} onClick={() => silence(a)} /><ActionButton small primary label="手动解决" onClick={() => resolve(a)} /></span>}
            </div>
          </Row>
        );
      })}
    </Section>
  ));
}

/* Route {kind:'alert', id} (deriveAttention's alert item, the base home's alert row, monitor rows). Core base = the 告警 segment as a
   pushed page with that event first; a variant can register a fuller alert page as screen:alert (it receives {ctx, route}). */
function AlertsScreen({ ctx, route }) {
  const firing = ctx.alerts.filter(a => a.status === 'firing').length;
  return (
    <Screen ctx={ctx} nav={<NavBar ctx={ctx} back title="告警" subtitle={`${firing} 条进行中`} />}>
      <MonAlerts ctx={ctx} focus={route.id} />
    </Screen>
  );
}
mvRegister('screen:alert', 'base', AlertsScreen);

function MonitorScreen({ ctx }) {
  const seg = ctx.monSeg;
  const firing = ctx.alerts.filter(a => a.status === 'firing').length;
  const sub = { overview: '运行与服务器 · 刚刚更新', channels: '渠道 · 近 90 分钟 · 刚刚更新', alerts: `告警 · ${firing} 条进行中` }[seg];
  return (
    <Screen ctx={ctx} nav={<NavBar ctx={ctx} large title="监控" subtitle={sub} trailing={<GlassButton icon="more" />} />}>
      <div className="pad-x mo-seg"><Segmented value={seg} onChange={ctx.setMonSeg} items={[
        { key: 'overview', label: '概况' },
        { key: 'channels', label: '渠道', count: DEMO.channels.filter(c => c.state === 'critical' || c.state === 'caution').length || undefined },
        { key: 'alerts', label: '告警', count: firing || undefined },
      ]} /></div>
      {seg === 'overview' && <MonOverview ctx={ctx} />}
      {seg === 'channels' && <MonChannels ctx={ctx} />}
      {seg === 'alerts' && <MonAlerts ctx={ctx} open />}
    </Screen>
  );
}

/* ---------- 设置 ---------- */

// Decided in round 2: global mode switch in settings; appearance follows the system by default.
function SettingsScreen({ ctx }) {
  const { skin, faceId } = ctx;
  const [mode, setMode] = useState('main');
  const [theme, setTheme] = useState('system');
  const toggleFaceId = () => ctx.setFaceId(!faceId);
  const choice = (value, current, set, label, sub) => (
    <Row skin={skin} tone="none" chevron={false} onClick={() => set(value)}
      lead={<span className={cx('st-radio', current === value && 'on')}>{current === value && <Icon name="check" size={12} weight={3.2} />}</span>}>
      <div className="row-top"><span className="row-title">{label}</span></div>
      {sub && <div className="row-meta">{sub}</div>}
    </Row>
  );
  return (
    <Screen ctx={ctx} nav={<NavBar ctx={ctx} back title="界面与模式" subtitle="设置" />}>
      <Section skin={skin} title="界面模式" index="壹">
        {choice('main', mode, setMode, '主模式', '概览 · 账号 · 用户 · 监控，适合日常处理')}
        {choice('simple', mode, v => { setMode(v); ctx.showToast({ text: '简化模式还在设计中，原型里不切换', icon: 'columns', tone: 'neutral' }); }, '简化模式（表格）', '视图列表 + 表格，适合快速筛查大量数据')}
      </Section>
      <Section skin={skin} title="外观" index="贰">
        {choice('system', theme, setTheme, '跟随系统')}
        {choice('light', theme, setTheme, '浅色')}
        {choice('dark', theme, setTheme, '深色')}
      </Section>
      <Section skin={skin} title="安全" index="叁">
        <Row skin={skin} tone="none" chevron={false} onClick={toggleFaceId} className="st-wrap"
          lead={<span className="lead-icon dim"><Icon name="shield" /></span>}>
          <div className="row-top"><span className="row-title">高风险操作需要 Face ID</span><span className={cx('st-switch', faceId && 'on')} role="switch" aria-checked={faceId} aria-label="高风险操作需要 Face ID"><i /></span></div>
          <div className="row-meta">删除、批量操作、超过门槛的充值 / 退款、生成余额兑换码和发放余额补偿</div>
        </Row>
        {faceId && (
          <Row skin={skin} tone="none" onClick={() => {}} lead={<span className="lead-icon dim"><Icon name="dollar" /></span>}>
            <div className="row-top"><span className="row-title">金额门槛</span><span className="row-right num">{fmt.money(FACE_ID_LIMIT, { digits: 0 })}</span></div>
            <div className="row-meta">单笔或合计超过这个金额时验证</div>
          </Row>
        )}
      </Section>
      <Section skin={skin} title="站点" index="肆">
        {DEMO.sites.map(s => (
          <Row key={s.name} skin={skin} tone="none" lead={<span className="avatar">{s.name.slice(0, 1)}</span>} onClick={() => {}}>
            <div className="row-top"><span className="row-title">{s.name}</span>{ctx.site === s.name && <span className="row-right dim">当前</span>}</div>
            <div className="row-meta mono">{s.host}</div>
          </Row>
        ))}
        <Row skin={skin} tone="none" lead={<span className="lead-icon dim"><Icon name="plus" /></span>} onClick={() => {}}>
          <div className="row-top"><span className="row-title">添加站点</span></div>
        </Row>
      </Section>
    </Screen>
  );
}

/* ---------- 搜索与日志 ---------- */

function SearchHome({ ctx }) {
  const { skin } = ctx;
  const groups = [
    ['记录', [['list', '使用记录', () => ctx.push({ kind: 'logs', scope: 'usage' })], ['octagon', '错误请求', () => ctx.push({ kind: 'logs', scope: 'errors' })], ['bell', '告警事件', null]]],
    ['资源', [['group', '分组', () => ctx.push({ kind: 'groups' })], ['chart', '统计分析', () => ctx.push({ kind: 'analytics' })], ['gift', '兑换码', () => ctx.push({ kind: 'redeem' })], ['shield', '代理', () => ctx.push({ kind: 'proxies' })], ['megaphone', '公告', () => ctx.push({ kind: 'announcements' })]]],
    // Decided in round 2: settings (incl. the main / simple mode switch) live in the search directory.
    ['设置', [['sliders', '界面与模式', () => ctx.push({ kind: 'settings' })], ['key', '站点与凭据', () => ctx.push({ kind: 'settings', focus: 'sites' })]]],
    ['在 Web 中打开', [['web', '系统设置', null], ['web', '支付与套餐', null]]],
  ];
  return (
    <Screen ctx={ctx} nav={<NavBar ctx={ctx} large title="搜索" subtitle="账号、用户、请求 ID、Key 片段" />}>
      <div className="search-field big"><Icon name="search" size={17} /><span>搜索全部对象</span></div>
      {groups.map(([title, items], gi) => (
        <Section key={title} skin={skin} title={title} index={['壹', '贰', '叁', '肆'][gi]}>
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

// The three lists' rules live in shared/data.jsx (LOG_SCOPES): 上游错误 = phase upstream / account_auth whether or not a retry saved the
// request; 错误请求 = the client finally got ≥ 400. Kept under this name for the files that count with it.
const LOG_SOURCES = LOG_SCOPES;

// Row / hero tone follows what the client finally got (codeTone of finalCode): an upstream 429 retried into a 200 stays calm,
// a 504 handed to the client is red. 'none' = success (no rail). The code badge itself keeps its own code's colour.
function logTone(l) {
  const tone = codeTone(finalCode(l));
  return tone === 'ok' ? 'none' : tone;
}

// Decided (rounds 1–2): time sits top-left above the status code; the right column is pinned like B —
// line 1 = amount, line 2 = "首字/耗时". Everything else lives on the request detail page.
function LogRow({ ctx, l }) {
  const { skin } = ctx;
  const tone = logTone(l);
  return (
    <div className={cx('row lg-row tappable', skin.rowClass(tone), `tone-${tone === 'none' ? 'ok' : tone}`)} onClick={() => ctx.push({ kind: 'request', id: l.id })}>
      <div className="lg-lead">
        <span className="num lg-clock">{l.t}</span>
        <skin.Code code={l.code} />
      </div>
      <div className="lg-main">
        <span className="lg-model mono">{l.model}</span>
        <span className="lg-who">{l.user} · {l.account}</span>
      </div>
      <div className="lg-side">
        <b className={cx('num lg-cost', l.cost === null && 'is-missing')}>{l.cost === null ? '—' : fmt.money(l.cost, { digits: l.cost < 1 ? 4 : 2 })}</b>
        <span className="num lg-time">{l.ttft || '—'}/{l.dur}</span>
      </div>
      <div className="row-chev"><Icon name="chevron" size={13} weight={2.6} /></div>
    </div>
  );
}
mvRegister('logRow', 'base', LogRow);

/* Filters of the usage page: route {kind:'logs', scope, account?, model?, group?, user?} sets them; each shows as a removable chip.
   account = account name or id; group = group name or id; user = user id or email; model = the requested model, exact.
   Which list takes which filter follows the APIs (LOG_MATCH in shared/data.jsx): admin/usage takes account_id, group_id, user_id and
   model (requested model only); ops request-errors takes account_id, group_id, user_query and model; ops upstream-errors takes only
   account_id and group_id (plus platform / q). A filter the current list cannot apply stays as a greyed chip with a note and is not applied.
   ctx.logAccount / logModel / logGroup / logUser override the route (undefined = follow the route, null = removed) and reset on leaving. */
const LOG_FILTERS = [
  { key: 'account', label: '账号', ctxKey: 'logAccount', set: 'setLogAccount',
    name: v => (typeof v === 'number' ? (DEMO.accounts.find(a => a.id === v) || { name: `#${v}` }).name : v) },
  { key: 'model', label: '模型', ctxKey: 'logModel', set: 'setLogModel', mono: true,
    name: v => v },
  { key: 'group', label: '分组', ctxKey: 'logGroup', set: 'setLogGroup',
    name: v => (groupOf(v) || { name: String(v) }).name },
  { key: 'user', label: '用户', ctxKey: 'logUser', set: 'setLogUser',
    name: v => (userOf(v) || { name: String(v) }).name },
].map(f => ({ ...f, scopes: LOG_MATCH[f.key].scopes, test: LOG_MATCH[f.key].test }));

function logFilterValues(ctx, route) {
  return LOG_FILTERS.map(f => ({ ...f, value: ctx[f.ctxKey] !== undefined ? ctx[f.ctxKey] : route[f.key] ?? null }))
    .filter(f => f.value !== null && f.value !== '');
}

const LOG_SCOPE_LABEL = { usage: '用量明细', errors: '错误请求', upstream: '上游错误' };

function LogsScreen({ ctx, route }) {
  const scope = ctx.logScope || route.scope || 'usage';
  const filters = logFilterValues(ctx, route);
  const where = Object.fromEntries(filters.map(f => [f.key, f.value]));
  const rows = logsWhere({ ...where, scope });
  const count = k => logCount({ ...where, scope: k });
  const ignored = filters.filter(f => !f.scopes.includes(scope));
  const applied = filters.filter(f => f.scopes.includes(scope));
  const clear = () => LOG_FILTERS.forEach(f => ctx[f.set] && ctx[f.set](null));
  return (
    <Screen plain ctx={ctx} nav={<NavBar ctx={ctx} back title="使用记录" subtitle={`${ctx.site} · 近 24 小时`} trailing={<GlassButton icon="filter" />} />}>
      <div className="pad-x"><Segmented value={scope} onChange={ctx.setLogScope} items={[
        { key: 'usage', label: '用量明细', count: count('usage') },
        { key: 'errors', label: '错误请求', count: count('errors') },
        { key: 'upstream', label: '上游错误', count: count('upstream') },
      ]} /></div>
      <div className="chips tokens">
        <button className="chip on token"><span>近 24 小时</span><Icon name="chevronDown" size={12} weight={2.6} /></button>
        {filters.map(f => {
          const name = f.name(f.value);
          const off = !f.scopes.includes(scope);
          return (
            <button key={f.key} className={cx('chip on token', off && 'token-off')} onClick={() => ctx[f.set](null)}
              aria-label={`移除筛选：${f.label} ${name}${off ? `（${LOG_SCOPE_LABEL[scope]}不支持，未生效）` : ''}`}>
              <span>{f.label}：<span className={cx(f.mono && 'mono')}>{name}</span></span><Icon name="close" size={12} weight={2.8} />
            </button>
          );
        })}
        <button className="chip token-add" onClick={() => ctx.openSheet({ kind: 'picker' })}><Icon name="plus" size={13} weight={2.6} /><span>筛选</span></button>
      </div>
      {ignored.length > 0 && (
        <div className="lg-filter-note pad">{LOG_SCOPE_LABEL[scope]}不能按{ignored.map(f => f.label).join('、')}筛选，这里显示全部{ignored.map(f => f.label).join('、')}</div>
      )}
      <div className="list-group">
        <div className="list-head"><span>今天</span><b className="num lg-head-cols">金额 · 首字/耗时</b></div>
        {rows.length === 0 && (
          <div className="lg-empty pad">
            <b className="num lg-empty-dash" aria-hidden="true">—</b>
            <span>{applied.length ? '近 24 小时内，这些条件下没有记录' : '近 24 小时内没有记录'}</span>
            {applied.length > 0 && <button className="lg-empty-clear" onClick={clear}>清除筛选</button>}
          </div>
        )}
        {rows.map(l => <Slot key={l.id} slot="logRow" ctx={ctx} l={l} />)}
      </div>
    </Screen>
  );
}

/* ---------- 请求详情（成功与失败） ---------- */

const PHASE_LABEL = { request: '请求校验', auth: '鉴权', account_auth: '账号鉴权', routing: '路由', upstream: '上游', network: '网络', internal: '网关内部' };
const OWNER_LABEL = { client: '客户端', provider: '上游服务商', platform: '平台配置' };

function ReqTiming({ l }) {
  const total = parseFloat(l.dur);
  const first = l.ttft ? parseFloat(l.ttft) : null;
  return (
    <div className="rq-timing pad">
      <div className="rq-bar" aria-hidden="true">
        {first !== null && <i className="rq-bar-first" style={{ width: `${Math.max(4, (first / total) * 100)}%` }} />}
        <i className="rq-bar-rest" />
      </div>
      <div className="rq-timing-legend">
        <span><small>首字</small><b className="num">{l.ttft || '—'}</b></span>
        <span><small>总耗时</small><b className="num">{l.dur}</b></span>
        <span><small>方式</small><b>{l.stream}</b></span>
      </div>
    </div>
  );
}

function ReqLinks({ ctx, l }) {
  const { skin } = ctx;
  const user = DEMO.users.find(u => u.name === l.userName);
  const group = (ctx.groupOf || groupOf)(l.group);
  const openGroup = group && MV.slots['screen:group'] ? () => ctx.push({ kind: 'group', id: group.id }) : undefined;
  return (
    <>
      <Row skin={skin} tone="none" lead={<span className="lead-icon dim"><Icon name="people" /></span>} onClick={user ? () => ctx.push({ kind: 'user', id: user.id }) : undefined}>
        <div className="row-top"><span className="row-title">{l.userName}</span><span className="row-right dim">用户</span></div>
      </Row>
      <Row skin={skin} tone="none" lead={<span className="lead-icon dim"><Icon name="key" /></span>}>
        <div className="row-top"><span className="row-title">{l.key.label}</span><span className="row-right mono">{l.key.masked}</span></div>
      </Row>
      <Row skin={skin} tone="none" lead={<span className="lead-icon dim"><Icon name="group" /></span>} onClick={openGroup}>
        <div className="row-top"><span className="row-title">{l.group || '—'}</span><span className="row-right dim">分组</span></div>
      </Row>
      <Row skin={skin} tone="none" lead={<span className="lead-icon dim"><Icon name="server" /></span>} onClick={l.accountId ? () => ctx.push({ kind: 'account', id: l.accountId }) : undefined}>
        <div className="row-top"><span className="row-title">{l.account}</span><span className="row-right dim">账号</span></div>
      </Row>
    </>
  );
}

function RequestDetail({ ctx, id }) {
  const { skin } = ctx;
  const l = DEMO.logs.find(x => x.id === id);
  const [resolved, setResolved] = useState(l.resolved);
  const ok = l.code === 200;
  const f = l.failure;
  const tone = logTone(l);
  // Upstream failed but a retry delivered: the request reads as a success (final 200); the upstream code keeps its own colour.
  const saved = !ok && codeTone(finalCode(l)) === 'ok';
  const copy = () => ctx.showToast({ text: '已复制请求 ID', icon: 'check', tone: 'neutral' });
  const resolve = () => { setResolved(true); ctx.showToast({ text: '已标记为已处理', icon: 'checkCircle', undo: () => setResolved(false) }); };
  return (
    <Screen ctx={ctx} nav={<NavBar ctx={ctx} back title={ok ? '请求详情' : l.kind === '上游错误' ? '上游错误' : '失败请求'} subtitle={`10/16 ${l.t}:${String(7 + (id % 50)).padStart(2, '0')} · ${l.kind || '用量明细'}`} trailing={<GlassButton icon="more" />} />}>
      <div className="detail-head">
        <div className={cx('hero rq-hero', `tone-${tone === 'none' ? 'ok' : tone}`, tone !== 'none' && skin.rowClass(tone))}>
          <div className="hero-top">
            {ok ? <span className="rq-status ok"><Icon name="checkCircle" size={15} weight={2.4} /> 成功 <span className="num">200</span></span>
              : saved ? <span className="rq-status is-upstream">上游失败 <skin.Code code={l.code} /></span>
                : <span className="rq-status"><Icon name="octagon" size={15} weight={2.4} /> 失败 <span className="num">{finalCode(l)}</span></span>}
            {!ok && f && <span className="hero-cause">{PHASE_LABEL[f.phase]} · {OWNER_LABEL[f.owner]} · {f.severity}</span>}
          </div>
          <div className="rq-model mono">{l.model}</div>
          {l.upstreamModel !== l.model && <div className="rq-map"><span>上游模型</span><span className="mono">{l.upstreamModel}</span></div>}
          {ok ? (
            <div className="rq-cost">
              <div><small data-kind="actual">实际扣费</small><b className="num">{fmt.money(l.cost, { digits: 4 })}</b></div>
              <div><small data-kind="cost">账号成本</small><span className="num">{fmt.money(l.acost, { digits: 4 })}</span></div>
              <div><small data-kind="standard">标准</small><span className="num">{fmt.money(l.std, { digits: 4 })}</span></div>
            </div>
          ) : (
            <>{saved && <div className="rq-saved"><Icon name="checkCircle" size={14} weight={2.4} /> 已自动重试成功，客户端收到 {finalCode(l)}</div>}<div className="rq-error mono">{f ? f.message : '上游返回错误'}</div></>
          )}
        </div>
        {!ok && (
          <div className="actions">
            {resolved ? <ActionButton label="已处理" icon="check" onClick={() => setResolved(false)} /> : <ActionButton label="标记已处理" icon="check" primary onClick={resolve} />}
            {l.accountId && <ActionButton label="查看账号" icon="server" onClick={() => ctx.push({ kind: 'account', id: l.accountId })} />}
          </div>
        )}
      </div>
      <Section skin={skin} title="耗时" index="壹"><ReqTiming l={l} /></Section>
      {f && f.attempts && f.attempts.length > 0 && (
        <Section skin={skin} title="上游尝试" meta={`${f.attempts.length} 次 · 返回客户端 ${f.clientCode}`} index="贰">
          {f.attempts.map((a, i) => {
            const at = codeTone(a.code);
            return (
              <Row key={i} skin={skin} tone="none" lead={<span className={cx('rq-step num', at === 'ok' ? 'ok' : at === 'caution' ? 'caution' : 'bad')}>{i + 1}</span>}>
                <div className="row-top"><span className="row-title">{a.account}</span><span className={cx('row-right num', at !== 'ok' && `tone-${at} tone-text`)}>{a.code} · {a.dur}</span></div>
                <div className="row-meta">{at === 'ok' ? '成功，结果返回客户端' : i === f.attempts.length - 1 ? '失败，错误返回客户端' : f.attempts[i + 1].account === a.account ? '失败，同一账号重试' : `失败，切换到 ${f.attempts[i + 1].account} 重试`}</div>
              </Row>
            );
          })}
        </Section>
      )}
      {ok && l.tokens && (
        <Section skin={skin} title="Token" index="贰">
          <div className="kv-grid pad">
            <KV label="输入" value={<span className="num">{fmt.grouped(l.tokens.input)}</span>} />
            <KV label="输出" value={<span className="num">{fmt.grouped(l.tokens.output)}</span>} />
            <KV label="缓存读" value={<span className="num">{fmt.grouped(l.tokens.cacheRead)}</span>} />
            <KV label="缓存写" value={<span className="num">{fmt.grouped(l.tokens.cacheWrite)}</span>} />
          </div>
        </Section>
      )}
      <Section skin={skin} title="关联" index="叁"><ReqLinks ctx={ctx} l={l} /></Section>
      <Section skin={skin} title="标识" index="肆">
        <Row skin={skin} tone="none" lead={<span className="lead-icon dim"><Icon name="list" /></span>} onClick={copy} chevron={false}>
          <div className="row-top"><span className="row-title">请求 ID</span><span className="row-right mono rq-rid">{l.rid}</span></div>
          <div className="row-meta">复制</div>
        </Row>
      </Section>
    </Screen>
  );
}
mvRegister('request', 'base', RequestDetail);

function PickerSheet({ ctx }) {
  const { skin } = ctx;
  const [q, setQ] = useState('');
  const accounts = DEMO.accounts.filter(a => a.name.toLowerCase().includes(q.toLowerCase())).slice(0, 6);
  const groups = DEMO.groups.filter(g => g.name.toLowerCase().includes(q.toLowerCase())).slice(0, 4);
  const users = DEMO.users.filter(u => (u.name + u.email).toLowerCase().includes(q.toLowerCase())).slice(0, 3);
  const choose = name => { ctx.setLogAccount(name); ctx.closeSheet(); };
  const chooseGroup = name => { ctx.setLogGroup(name); ctx.closeSheet(); };
  const chooseUser = id => { ctx.setLogUser(id); ctx.closeSheet(); };
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
      {groups.length > 0 && <div className="picker-group">分组</div>}
      {groups.map(g => (
        <Row key={g.id} skin={skin} tone="none" className="pk-group" lead={<span className="lead-icon dim"><Icon name="group" /></span>} onClick={() => chooseGroup(g.name)} chevron={false}>
          <div className="row-top"><span className="row-title">{g.name}</span><span className="row-right dim">{g.platform}</span></div>
        </Row>
      ))}
      <div className="picker-group">用户</div>
      {users.map(u => (
        <Row key={u.id} skin={skin} tone="none" className="pk-user" lead={<span className="avatar">{u.name.slice(0, 1)}</span>} onClick={() => chooseUser(u.id)} chevron={false}>
          <div className="row-top"><span className="row-title">{u.name}</span></div>
          <div className="row-meta">{u.email}</div>
        </Row>
      ))}
    </Sheet>
  );
}


/* ---------- menus and placeholder for screens not built yet ---------- */

/* Decided (round 2): deletion is offered, last in the ⋯ menu, and needs the object's name typed — or Face ID when 设置 → 高风险操作需要
   Face ID is on. The confirm names the site. SwiftUI: .alert with a TextField and the destructive button .disabled(text != name); with
   Face ID, LAContext.evaluatePolicy before the DELETE.
   onDone runs first (usually ctx.pop, leaving the object's page); opts.remove performs the deletion in this phone — for 账号 without
   opts.remove the account of that name is removed (ctx.removeAccount). opts.typed / ctx.v.deleteTyped prefill the name (demo states).
   opts.message = what the deletion takes with it (“2 个 Key 一并删除”), on its own line after the site line. opts.match / opts.label /
   opts.placeholder swap what must be typed (a redeem code's last 4 characters instead of the name); opts.caseInsensitive compares
   without case. */
function confirmDelete(ctx, what, name, onDone, opts = {}) {
  const account = what === '账号' && !opts.remove && ctx.removeAccount ? Object.values(ctx.accounts).find(a => a.name === name) : null;
  const remove = opts.remove || (account ? () => ctx.removeAccount(account.id) : null);
  const done = verified => {
    if (onDone) onDone();
    if (remove) remove();
    ctx.showToast({ text: `${verified ? '已通过 Face ID · ' : ''}已删除${what}「${name}」${remove ? '' : '（原型里不真的删除）'}`, icon: 'close', tone: 'critical' });
  };
  const site = [`站点 ${ctx.site} · 删除后不能恢复。`, opts.message].filter(Boolean).join('\n');
  if (ctx.faceId) {
    ctx.confirm({
      title: `删除${what}「${name}」？`,
      message: `${site}\n确认后验证 Face ID。`,
      actions: [
        { label: `用 Face ID 删除`, role: 'destructive', onPress: () => done(true) },
        { label: '取消', role: 'cancel' },
      ],
    });
    return;
  }
  const match = opts.match !== undefined ? String(opts.match) : name;
  const typed = opts.typed !== undefined ? opts.typed : ctx.v && ctx.v.deleteTyped ? match : '';
  ctx.confirm({
    title: `删除${what}「${name}」？`,
    message: site,
    input: { label: opts.label || `输入「${match}」确认删除`, placeholder: opts.placeholder || `${what}名称`, match, value: typed, caseInsensitive: Boolean(opts.caseInsensitive) },
    actions: [
      { label: `删除${what}`, role: 'destructive', needsMatch: true, onPress: () => done(false) },
      { label: '取消', role: 'cancel' },
    ],
  });
}

// ⋯ of the base account page: a toolbar menu (SwiftUI Menu), delete last.
function accountMenu(ctx, a) {
  (ctx.menu || ctx.confirm)({
    title: a.name,
    actions: [
      { label: '编辑账号', role: 'default', onPress: () => ctx.push({ kind: 'accountEdit', id: a.id }) },
      // Only token accounts (OAuth / Setup Token) have a token to refresh, as in Web's AccountActionMenu.
      ...(isTokenAccount(a) ? [{ label: '刷新令牌', role: 'default', onPress: () => ctx.showToast({ text: '已刷新令牌', icon: 'refresh' }) }] : []),
      { label: '删除账号…', role: 'destructive', onPress: () => confirmDelete(ctx, '账号', a.name, ctx.pop) },
      { label: '取消', role: 'cancel' },
    ],
  });
}

/* ⋯ of the user page (every user-detail variant uses it). Admins cannot be disabled or deleted (admin_user.go: cannot disable /
   delete admin user), so those rows are absent for any role=admin user; the signed-in admin (DEMO.me) is told it is their own account.
   启用 / 禁用 is reversible: it runs at once and the receipt offers 撤销 (禁用 stops login and every key of the user at once, so the
   receipt says so). 发放兑换码（补偿）opens sheet redeemGrant (create-and-redeem), shown only when a variant registered that sheet. */
function userMenu(ctx, u) {
  const admin = u.role === 'admin';
  const self = Boolean(DEMO.me) && u.id === DEMO.me.id;
  const disabled = u.status === 'disabled';
  const live = (u.keys || []).filter(k => k.status === 'active').length;
  const toggle = () => ctx.updateUser(u.id, { status: disabled ? 'active' : 'disabled' }, {
    text: disabled ? `已启用 ${u.name}` : `已禁用 ${u.name}${live ? ` · ${live} 个 Key 停止调用` : ''}`,
    icon: disabled ? 'play' : 'pauseFill', tone: disabled ? 'ok' : 'neutral', undo: true,
  });
  const actions = [{ label: '编辑用户', role: 'default', onPress: () => ctx.push({ kind: 'userEdit', id: u.id }) }];
  if (!admin) actions.push({ label: disabled ? '启用用户' : '禁用用户', role: 'default', onPress: toggle });
  if (MV.slots['sheet:redeemGrant']) actions.push({ label: '发放兑换码（补偿）…', role: 'default', onPress: () => ctx.openSheet({ kind: 'redeemGrant', userId: u.id }) });
  // DeleteUser removes the user's API keys in the same transaction (admin_user.go deleteUserWithAPIKeys), so the confirm says so.
  const keyCount = (u.keys || []).length;
  if (!admin) actions.push({ label: '删除用户…', role: 'destructive', onPress: () => confirmDelete(ctx, '用户', u.name, ctx.pop, keyCount ? { message: `名下 ${keyCount} 个 Key 一并删除。` } : {}) });
  actions.push({ label: '取消', role: 'cancel' });
  const message = self ? '这是你当前登录的账号。管理员不能禁用或删除。' : admin ? '管理员不能禁用或删除。' : undefined;
  (ctx.menu || ctx.confirm)({ title: u.name, message, actions });
}

const PENDING_TITLES = { analytics: '统计分析', accountNew: '新建账号', accountEdit: '编辑账号', groups: '分组', group: '分组详情', redeem: '兑换码', proxies: '代理', announcements: '公告', userNew: '新建用户', userEdit: '编辑用户' };

function PendingScreen({ ctx, route }) {
  return (
    <Screen ctx={ctx} nav={<NavBar ctx={ctx} back title={PENDING_TITLES[route.kind] || route.kind} subtitle="下一轮出布局对比" />}>
      <div className="empty pad">这一页的布局正在设计，会在下一轮对比页里给你选。</div>
    </Screen>
  );
}

/* ---------- phone state machine ---------- */

// Decided choices merged in by layouts/main/v-decided.jsx; round snapshots that exclude it keep the plain base.
const MAIN_DEFAULTS = {};

function MainPhone({ dark, initial }) {
  const skin = MainSkin;
  const app = useAppModel(initial);
  // ctx.v.faceId mirrors the global setting so variant files that read the switch follow the settings page.
  const v = { ...MAIN_DEFAULTS, ...(initial.v || {}), faceId: app.faceId };
  const [tab, setTab] = useState(initial.tab);
  const [stacks, setStacks] = useState(() => ({ today: [], accounts: [], users: [], monitor: [], search: [], [initial.tab]: initial.stack || [] }));
  const [acctFilter, setAcctFilter] = useState(initial.acctFilter || 'all');
  const [logScope, setLogScope] = useState(null);
  const [logAccount, setLogAccount] = useState(undefined);
  const [logModel, setLogModel] = useState(undefined);
  const [logGroup, setLogGroup] = useState(undefined);
  const [logUser, setLogUser] = useState(undefined);
  const [selecting, setSelecting] = useState(Boolean(initial.selecting));
  const [selected, setSelected] = useState([]);
  const [monSeg, setMonSeg] = useState(initial.monSeg || 'channels');
  const resetLogs = () => { setLogScope(null); setLogAccount(undefined); setLogModel(undefined); setLogGroup(undefined); setLogUser(undefined); };

  const ctx = {
    ...app, skin, v, tab, acctFilter, logScope, logAccount, logModel, logGroup, logUser, selecting, selected, monSeg, setMonSeg,
    role: initial.role || 'admin',
    push: route => setStacks(s => ({ ...s, [tab]: [...s[tab], route] })),
    pop: () => { setStacks(s => ({ ...s, [tab]: s[tab].slice(0, -1) })); resetLogs(); },
    switchTab: (key, opts = {}) => {
      if (key === tab && !opts.filter) setStacks(s => ({ ...s, [key]: [] }));
      setTab(key);
      if (opts.filter) { setAcctFilter(opts.filter); setStacks(s => ({ ...s, accounts: [] })); }
      setSelecting(false);
    },
    setAcctFilter, setLogScope, setLogAccount, setLogModel, setLogGroup, setLogUser,
    toggleSelecting: () => { setSelecting(v => !v); setSelected([]); },
    toggleSelect: id => setSelected(s => (s.includes(id) ? s.filter(x => x !== id) : [...s, id])),
    bulkSchedule: enable => { app.setSchedule(selected, enable); setSelecting(false); setSelected([]); },
  };

  const stack = stacks[tab];
  const top = stack[stack.length - 1];
  let screen;
  if (top && top.kind === 'account' && !ctx.accounts[top.id]) screen = <RemovedAccount ctx={ctx} />;
  else if (top && top.kind === 'account') screen = <Slot slot="accountDetail" ctx={ctx} id={top.id} key={`a${top.id}`} />;
  else if (top && top.kind === 'user') screen = <Slot slot="userDetail" ctx={ctx} id={top.id} key={`u${top.id}`} />;
  else if (top && top.kind === 'logs') screen = <LogsScreen ctx={ctx} route={top} />;
  else if (top && top.kind === 'request') screen = <Slot slot="request" ctx={ctx} id={top.id} key={`r${top.id}`} />;
  else if (top && top.kind === 'settings') screen = <SettingsScreen ctx={ctx} />;
  else if (top && MV.slots[`screen:${top.kind}`]) screen = <Slot slot={`screen:${top.kind}`} ctx={ctx} route={top} key={JSON.stringify(top)} />;
  else if (top) screen = <PendingScreen ctx={ctx} route={top} />;
  else if (tab === 'today') screen = <Slot slot="today" ctx={ctx} />;
  else if (tab === 'accounts') screen = <Slot slot="accounts" ctx={ctx} />;
  else if (tab === 'users') screen = <Slot slot="users" ctx={ctx} />;
  else if (tab === 'monitor') screen = <MonitorScreen ctx={ctx} />;
  else screen = <SearchHome ctx={ctx} />;

  return (
    <PhoneFrame dark={dark} canvas={skin.canvas(dark)} className={cx(`dir-${skin.key}`, skin.appClass, 'lay-main', `vis-${v.vis || 'base'}`)}>
      {screen}
      <TabBar ctx={ctx} />
      <Overlays ctx={ctx}>
        {ctx.sheet && ctx.sheet.kind === 'keypad' && <KeypadSheet ctx={ctx} sheet={ctx.sheet} key={ctx.sheet.userId + ctx.sheet.mode} />}
        {ctx.sheet && ctx.sheet.kind === 'picker' && <PickerSheet ctx={ctx} />}
        {ctx.sheet && MV.slots[`sheet:${ctx.sheet.kind}`] && <Slot slot={`sheet:${ctx.sheet.kind}`} ctx={ctx} sheet={ctx.sheet} key={JSON.stringify(ctx.sheet)} />}
      </Overlays>
    </PhoneFrame>
  );
}

mvRegister('today', 'base', TodayScreen);
mvRegister('accounts', 'base', AccountsScreen);
mvRegister('accountRow', 'base', AccountRow);
mvRegister('accountDetail', 'base', AccountDetail);
mvRegister('userDetail', 'base', UserDetail);
mvRegister('users', 'base', UsersScreen);
