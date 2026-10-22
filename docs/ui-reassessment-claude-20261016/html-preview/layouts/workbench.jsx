/* Layout C · 表格工作台：没有 Tab 栏，根页是“视图”列表（像邮件的邮箱列表），对象都在可排序的表格里，
   详情是检查器（属性表 + 上一条/下一条），操作在底部工具栏。颜色沿用游标，字形与形状独立。 */

/* ---------- table ---------- */

function WbGlyph({ state }) {
  const meta = STATE_META[state];
  return <span className={cx('wb-glyph', `tone-${meta.tone}`, `is-${state}`)}><Icon name={meta.icon} size={state === 'normal' ? 7 : 14} weight={2.3} /></span>;
}

function WbState({ a, secs }) {
  const meta = STATE_META[a.state];
  const short = { rate_limited: '限流', overloaded: '过载', temp_unsched: '临时', error: '错误', paused: '暂停', inactive: '停用', normal: '正常' }[a.state];
  return (
    <span className={cx('wb-state', `tone-${meta.tone}`)}>
      {short}{meta.timed && secs !== null && secs !== undefined && <b className="num"> {fmt.countdown(secs)}</b>}
    </span>
  );
}

function WbTable({ columns, rows, rowKey, sort, onSort, onRow, selecting, selected, onToggle, footer, rowClass }) {
  const cols = columns;
  return (
    <div className="wb-table" role="table">
      <div className="wb-tr wb-th" role="row">
        {cols.map((c, i) => (
          <button key={c.key} role="columnheader" className={cx('wb-td', i === 0 && 'sticky', c.align === 'right' && 'r', sort && sort.key === c.key && 'sorted')}
            style={{ width: i === 0 && selecting ? c.w + 26 : c.w }} onClick={() => c.sort && onSort && onSort(c.key)} disabled={!c.sort}>
            <span>{c.label}</span>
            {sort && sort.key === c.key && <Icon name={sort.dir > 0 ? 'chevronUp' : 'chevronDown'} size={10} weight={3} />}
          </button>
        ))}
      </div>
      {rows.map(r => {
        const id = rowKey(r);
        const on = selecting && selected.includes(id);
        return (
          <div key={id} role="row" className={cx('wb-tr', on && 'is-selected', rowClass && rowClass(r))} onClick={() => (selecting ? onToggle(id) : onRow && onRow(r))}>
            {cols.map((c, i) => (
              <div key={c.key} role="cell" className={cx('wb-td', i === 0 && 'sticky', c.align === 'right' && 'r', c.mono && 'num')} style={{ width: i === 0 && selecting ? c.w + 26 : c.w }}>
                {i === 0 && selecting && <span className={cx('wb-check', on && 'on')}>{on && <Icon name="check" size={11} weight={3.4} />}</span>}
                {c.render(r)}
              </div>
            ))}
          </div>
        );
      })}
      {footer && (
        <div className="wb-tr wb-tf" role="row">
          {cols.map((c, i) => <div key={c.key} className={cx('wb-td', i === 0 && 'sticky', c.align === 'right' && 'r', 'num')} style={{ width: i === 0 && selecting ? c.w + 26 : c.w }}>{footer[c.key] ?? ''}</div>)}
        </div>
      )}
    </div>
  );
}

function sortRows(rows, columns, sort) {
  const col = columns.find(c => c.key === sort.key);
  if (!col || !col.sort) return rows;
  return [...rows].sort((a, b) => {
    const x = col.sort(a), y = col.sort(b);
    return (x > y ? 1 : x < y ? -1 : 0) * sort.dir;
  });
}

function WbToolbar({ children, center }) {
  return (
    <div className="wb-toolbar">
      <div className="wb-toolbar-inner glass">{children}{center !== undefined && <span className="wb-toolbar-center">{center}</span>}</div>
    </div>
  );
}

function WbToolButton({ icon, label, onClick, primary, disabled }) {
  return (
    <button className={cx('wb-tool', primary && 'primary')} onClick={onClick} disabled={disabled} aria-label={label}>
      {icon && <Icon name={icon} size={18} weight={2.2} />}{label && <span>{label}</span>}
    </button>
  );
}

function WbQueryBar({ tokens, onAdd }) {
  return (
    <div className="wb-query">
      {tokens.map(t => (
        <span key={t.key} className={cx('wb-token', t.onClick && 'tappable')} onClick={t.onClick}>
          <i>{t.field}</i><em>{t.op}</em><b>{t.value}</b>
          {t.menu && <Icon name="chevronDown" size={10} weight={3} />}
          {t.onRemove && <button className="wb-token-x" aria-label={`移除条件 ${t.field}`} onClick={stop(t.onRemove)}><Icon name="close" size={10} weight={3} /></button>}
        </span>
      ))}
      <button className="wb-token add" onClick={onAdd}><Icon name="plus" size={11} weight={3} /> 条件</button>
    </div>
  );
}

/* ---------- 根：视图列表 ---------- */

function WbRoot({ ctx }) {
  const c = ctx.counts;
  const users = Object.values(ctx.users);
  const t = DEMO.today;
  const count = kind => DEMO.logs.filter(l => (kind ? l.kind === kind : l.code === 200)).length;
  const groups = [
    ['置顶', [
      ['tray', '需处理账号', c.needs, 'critical', { kind: 'accounts', view: 'needs' }],
      ['docCheck', '待核对写操作', users.filter(u => u.pending).length, 'caution', { kind: 'users', view: 'pending' }],
      ['dollar', '余额低于 $10', users.filter(u => u.balance < 10 && u.status !== 'disabled').length, null, { kind: 'users', view: 'low' }],
      ['octagon', '近 24 小时上游错误', count('上游错误'), null, { kind: 'logs', source: 'upstream' }],
    ]],
    ['账号', [
      ['server', '全部账号', c.total, null, { kind: 'accounts', view: 'all' }],
      ['hourglass', '受限中', c.limited, null, { kind: 'accounts', view: 'limited' }],
      ['pause', '暂停与停用', c.paused + c.inactive, null, { kind: 'accounts', view: 'paused' }],
    ]],
    ['用户', [
      ['people', '全部用户', users.length, null, { kind: 'users', view: 'all' }],
      ['minus', '已禁用', users.filter(u => u.status === 'disabled').length, null, { kind: 'users', view: 'disabled' }],
    ]],
    ['记录', [
      ['list', '用量明细', count(), null, { kind: 'logs', source: 'usage' }],
      ['octagon', '错误请求', count('错误请求'), null, { kind: 'logs', source: 'errors' }],
      ['bell', '告警事件', 1, null, null],
    ]],
    ['监控与资源', [
      ['signal', '渠道矩阵', DEMO.channels.length, null, { kind: 'channels' }],
      ['chart', '营收逐小时', 24, null, { kind: 'report' }],
      ['group', '分组', 4, null, null],
      ['gift', '兑换码', 12, null, null],
    ]],
  ];
  return (
    <div className="screen">
      <NavBar ctx={ctx} large title="工作台" trailing={<GlassButton label="编辑" />} />
      <div className="scroll">
        <div className="wb-sites">
          {[...DEMO.sites.map(s => s.name), '全部站点'].map(name => (
            <button key={name} className={cx('wb-site', ctx.site === name && 'on')} onClick={() => ctx.setSite(name)}>{name}</button>
          ))}
        </div>
        <button className="wb-ticker" onClick={() => ctx.push({ kind: 'report' })}>
          <span><small>今日实际</small><b className="num">{fmt.money(t.actual)}</b><em className="num">▲{todayChange().toFixed(1)}%</em></span>
          <span><small>请求</small><b className="num">{fmt.compact(t.requests)}</b></span>
          <span><small>错误率</small><b className="num">{DEMO.run.errorRate}%</b></span>
          <span><small>成本</small><b className="num">{fmt.money(t.cost)}</b></span>
          <span><small>RPM</small><b className="num">{t.rpm}</b></span>
          <span><small>健康</small><b className="num">{DEMO.run.health}</b></span>
        </button>
        {groups.map(([title, rows]) => (
          <section key={title} className="wb-group">
            <h4>{title}</h4>
            <div className="wb-views">
              {rows.map(([icon, label, n, tone, route]) => (
                <button key={label} className="wb-view" onClick={() => (route ? ctx.push(route) : ctx.showToast({ text: `${label}：原型未展开`, icon: 'browse', tone: 'neutral' }))}>
                  <span className="wb-view-icon"><Icon name={icon} size={17} /></span>
                  <span className="wb-view-label">{label}</span>
                  <b className={cx('num wb-view-count', tone && n > 0 && `tone-${tone}`)}>{n}</b>
                  <Icon name="chevron" size={11} weight={2.8} />
                </button>
              ))}
            </div>
          </section>
        ))}
      </div>
      <WbToolbar center={<><b>刚刚更新</b><small>{ctx.site} · 2 个站点</small></>}>
        <WbToolButton icon="filter" label="筛选视图" onClick={() => ctx.showToast({ text: '只看有计数的视图', icon: 'filter', tone: 'neutral' })} />
        <WbToolButton icon="compose" label="新建视图" onClick={() => ctx.showToast({ text: '新建视图：选对象、加条件、选列，保存后出现在置顶', icon: 'compose', tone: 'neutral' })} />
      </WbToolbar>
    </div>
  );
}

/* ---------- 账号表 ---------- */

const WB_ACCOUNT_VIEWS = {
  all: { title: '全部账号', match: () => true, tokens: [] },
  needs: { title: '需处理账号', match: a => NEEDS_ACTION.includes(a.state), tokens: [{ key: 'state', field: '状态', op: '∈', value: '错误 · 过载 · 限流 · 临时' }] },
  limited: { title: '受限中', match: a => ['rate_limited', 'overloaded', 'temp_unsched'].includes(a.state), tokens: [{ key: 'state', field: '状态', op: '∈', value: '过载 · 限流 · 临时' }] },
  paused: { title: '暂停与停用', match: a => ['paused', 'inactive'].includes(a.state), tokens: [{ key: 'state', field: '状态', op: '∈', value: '暂停 · 停用' }] },
};

function accountColumns(ctx) {
  return [
    { key: 'name', label: '账号', w: 148, sort: a => a.name, render: a => <><WbGlyph state={a.state} /><span className="wb-cell-text">{a.name}</span></> },
    { key: 'state', label: '状态', w: 92, sort: a => STATE_ORDER.indexOf(a.state), render: a => <WbState a={a} secs={remaining(a, ctx.elapsed)} /> },
    { key: 'today', label: '今日', w: 74, align: 'right', mono: true, sort: a => a.todayCost, render: a => fmt.money(a.todayCost) },
    { key: 'conc', label: '并发', w: 54, align: 'right', mono: true, sort: a => (a.conc ? a.conc[0] / a.conc[1] : -1), render: a => (a.conc ? `${a.conc[0]}/${a.conc[1]}` : '—') },
    { key: 'rpm', label: 'RPM', w: 62, align: 'right', mono: true, sort: a => (a.rpm ? a.rpm[0] : -1), render: a => (a.rpm ? <span className={a.rpm[0] / a.rpm[1] >= 0.75 ? 'tone-caution tone-text' : ''}>{a.rpm[0]}/{a.rpm[1]}</span> : '—') },
    { key: 'platform', label: '平台', w: 86, sort: a => a.platform, render: a => a.platform },
    { key: 'group', label: '分组', w: 70, sort: a => a.groups.join(), render: a => a.groups.join('、') || '—' },
    { key: 'type', label: '类型', w: 70, sort: a => a.type, render: a => a.type },
    { key: 'prio', label: '优先级', w: 58, align: 'right', mono: true, sort: a => a.priority, render: a => a.priority },
  ];
}

function WbAccounts({ ctx, route }) {
  const view = WB_ACCOUNT_VIEWS[route.view] || WB_ACCOUNT_VIEWS.all;
  const all = accountColumns(ctx);
  const columns = all.filter(c => !ctx.hiddenCols.includes(c.key));
  const sort = ctx.sorts.accounts;
  const rows = sortRows(Object.values(ctx.accounts).filter(view.match), all, sort);
  const order = rows.map(a => a.id);
  const sum = rows.reduce((s, a) => s + a.todayCost, 0);
  const conc = rows.filter(a => a.conc).reduce((s, a) => [s[0] + a.conc[0], s[1] + a.conc[1]], [0, 0]);
  const tokens = view.tokens.map(t => ({ ...t, onRemove: () => ctx.replaceTop({ ...route, view: 'all' }) }));
  return (
    <div className="screen">
      <NavBar ctx={ctx} back title={view.title} subtitle={`${ctx.site} · ${rows.length} 行 · 按${all.find(c => c.key === sort.key).label}${sort.dir > 0 ? '升序' : '降序'}`} trailing={<GlassButton icon="search" />} />
      <WbQueryBar tokens={tokens} onAdd={() => ctx.openSheet({ kind: 'conditions', target: 'accounts' })} />
      <div className="wb-scroll">
        <WbTable columns={columns} rows={rows} rowKey={a => a.id} sort={sort} onSort={k => ctx.setSort('accounts', k)}
          onRow={a => ctx.push({ kind: 'account', id: a.id, order })} selecting={ctx.selecting} selected={ctx.selected} onToggle={ctx.toggleSelect}
          rowClass={a => (a.state === 'paused' || a.state === 'inactive' ? 'is-idle' : '')}
          footer={{ name: `合计 ${rows.length} 行`, today: fmt.money(sum), conc: `${conc[0]}/${conc[1]}` }} />
        <div className="wb-hint">← 左右滑动查看平台、分组、类型、优先级 · 点表头排序</div>
      </div>
      {ctx.selecting ? (
        <WbToolbar center={<b>已选 {ctx.selected.length} 行</b>}>
          <WbToolButton label="完成" onClick={ctx.toggleSelecting} />
          <WbToolButton icon="pauseFill" label="停止调度" disabled={!ctx.selected.length} onClick={() => ctx.bulkSchedule(false)} />
          <WbToolButton icon="play" label="启用" primary disabled={!ctx.selected.length} onClick={() => ctx.bulkSchedule(true)} />
        </WbToolbar>
      ) : (
        <WbToolbar center={<><b>{rows.length} 行</b><small>今日 {fmt.money(sum)}</small></>}>
          <WbToolButton label="选择" onClick={ctx.toggleSelecting} />
          <WbToolButton icon="columns" label="列" onClick={() => ctx.openSheet({ kind: 'columns', target: 'accounts' })} />
        </WbToolbar>
      )}
    </div>
  );
}

/* ---------- 检查器 ---------- */

function WbProps({ title, children, action }) {
  return (
    <section className="wb-group">
      <h4>{title}{action}</h4>
      <div className="wb-props">{children}</div>
    </section>
  );
}

function WbProp({ label, children, mono, tone, onClick }) {
  return (
    <div className={cx('wb-prop', onClick && 'tappable', tone && `tone-${tone}`)} onClick={onClick}>
      <span className="wb-prop-label">{label}</span>
      <span className={cx('wb-prop-value', mono && 'num', tone && 'tone-text')}>{children}</span>
      {onClick && <Icon name="chevron" size={11} weight={2.8} />}
    </div>
  );
}

function WbBar({ ratio }) {
  const level = ratio >= 0.9 ? 'critical' : ratio >= 0.75 ? 'caution' : 'normal';
  return <span className={cx('wb-bar', `lv-${level}`)}><i style={{ width: `${Math.min(ratio, 1) * 100}%` }} /></span>;
}

function WbSwitch({ on, onChange, label }) {
  return <button role="switch" aria-checked={on} aria-label={label} className={cx('wb-switch', on && 'on')} onClick={stop(onChange)}><i /></button>;
}

function WbAccount({ ctx, route }) {
  const order = route.order || sortByUrgency(Object.values(ctx.accounts)).map(a => a.id);
  const idx = order.indexOf(route.id);
  const a = ctx.accounts[route.id];
  const meta = STATE_META[a.state];
  const secs = remaining(a, ctx.elapsed);
  const abnormal = NEEDS_ACTION.includes(a.state);
  const scheduling = !['paused', 'inactive'].includes(a.state);
  const until = fmt.clock(DEMO_CLOCK_BASE + (ctx.elapsed + (secs || 0)) * 1000);
  const go = d => ctx.replaceTop({ ...route, id: order[idx + d], order });
  const toggle = () => (scheduling
    ? ctx.updateAccount(a.id, { state: 'paused' }, { text: '已停止调度', undo: true, icon: 'pauseFill', tone: 'neutral' })
    : ctx.updateAccount(a.id, { state: 'normal' }, { text: '已启用调度', undo: true }));
  const logs = DEMO.logs.filter(l => l.account === a.name).slice(0, 4);
  return (
    <div className="screen">
      <NavBar ctx={ctx} back title={a.name} subtitle={`第 ${idx + 1} / ${order.length} 行 · #${a.id}`}
        trailing={<><GlassButton icon="chevronUp" onClick={() => idx > 0 && go(-1)} /><GlassButton icon="chevronDown" onClick={() => idx < order.length - 1 && go(1)} /></>} />
      <div className="scroll wb-inspector">
        <div className={cx('wb-strip', `tone-${meta.tone}`)}>
          <WbGlyph state={a.state} />
          <span className="wb-strip-text">
            <b>{meta.label}</b>
            {meta.timed && <> · <span className="num">{fmt.countdown(secs)}</span> 后恢复（<span className="num">{until}</span>）</>}
            {a.state === 'error' && <> · {a.errorAgo}</>}
            {!abnormal && <> · {scheduling ? '参与调度' : '不参与调度'}</>}
          </span>
          {abnormal && a.state !== 'error' && <button className="wb-strip-btn" onClick={() => confirmRecover(ctx, a)}>恢复</button>}
        </div>
        <WbProps title="状态">
          <WbProp label="调度"><WbSwitch on={scheduling} onChange={toggle} label="参与调度" /></WbProp>
          {a.cause && <WbProp label="原因">{a.cause}</WbProp>}
          {a.error && <WbProp label="错误" tone="critical">{a.error}</WbProp>}
          {meta.timed && <WbProp label="恢复于" mono>{until}</WbProp>}
          {(a.modelLimits || []).map(m => <WbProp key={m.model} label="模型限流" tone="model"><span className="mono">{m.model}</span> <span className="num">{fmt.minutesLeft(m.resetIn - ctx.elapsed)}</span></WbProp>)}
        </WbProps>
        <WbProps title="容量">
          {a.conc && <WbProp label="并发" mono><WbBar ratio={a.conc[0] / a.conc[1]} />{a.conc[0]} / {a.conc[1]}</WbProp>}
          {a.rpm && <WbProp label="调度 RPM" mono><WbBar ratio={a.rpm[0] / a.rpm[1]} />{a.rpm[0]} / {a.rpm[1]}</WbProp>}
          {a.dayQuota && <WbProp label="日配额" mono><WbBar ratio={a.dayQuota[0] / a.dayQuota[1]} />{fmt.money(a.dayQuota[0])} / {fmt.money(a.dayQuota[1])}</WbProp>}
          {a.window5h !== undefined && <WbProp label="5 小时窗口" mono><WbBar ratio={a.window5h} />{Math.round(a.window5h * 100)}%</WbProp>}
          {!a.conc && <WbProp label="并发" mono>—</WbProp>}
        </WbProps>
        <WbProps title="今日">
          <WbProp label="请求" mono>{fmt.grouped(a.todayReq)}</WbProp>
          <WbProp label="Tokens" mono>{fmt.compact(a.todayTokens ?? null)}</WbProp>
          <WbProp label="实际" mono>{fmt.money(a.todayCost)}</WbProp>
          <WbProp label="成本" mono>{fmt.money(a.todayAccountCost ?? null)}</WbProp>
          <WbProp label="标准" mono>{fmt.money(a.todayStd ?? null)}</WbProp>
        </WbProps>
        <WbProps title="最近请求">
          {logs.length ? (
            <div className="wb-mini">
              {logs.map((l, i) => (
                <div key={i} className="wb-mini-row"><span className="num">{l.t}</span><span className={cx('num', l.code !== 200 && 'tone-critical tone-text')}>{l.code}</span><span className="mono wb-mini-model">{l.model}</span><span className="num r">{l.cost === null ? '—' : fmt.money(l.cost, { digits: 4 })}</span></div>
              ))}
            </div>
          ) : <WbProp label="近 30 分钟">没有请求</WbProp>}
          <WbProp label="在使用记录中打开" onClick={() => ctx.push({ kind: 'logs', source: 'usage', account: a.name })}>{a.errors24h ? `错误 ${a.errors24h}` : ''}</WbProp>
        </WbProps>
        <WbProps title="档案">
          <WbProp label="平台">{a.platform}</WbProp>
          <WbProp label="类型">{a.type}</WbProp>
          <WbProp label="分组">{a.groups.join('、') || '未分组'}</WbProp>
          <WbProp label="优先级" mono>{a.priority}</WbProp>
          <WbProp label="代理">{a.proxy || '—'}</WbProp>
          <WbProp label="到期" mono>{a.expires || '—'}</WbProp>
        </WbProps>
      </div>
      <WbToolbar>
        <WbToolButton icon="wave" label="测试" onClick={() => ctx.openSheet({ kind: 'test', id: a.id })} />
        {abnormal && a.state !== 'error'
          ? <WbToolButton icon="restore" label="恢复状态" primary onClick={() => confirmRecover(ctx, a)} />
          : <WbToolButton icon={scheduling ? 'pauseFill' : 'play'} label={scheduling ? '停止调度' : '启用调度'} onClick={toggle} />}
        <WbToolButton icon="more" label="更多" />
      </WbToolbar>
    </div>
  );
}

/* ---------- 用户 ---------- */

const WB_USER_VIEWS = {
  all: { title: '全部用户', match: () => true, tokens: [] },
  low: { title: '余额低于 $10', match: u => u.balance < 10 && u.status !== 'disabled', tokens: [{ key: 'bal', field: '余额', op: '<', value: '$10' }, { key: 'st', field: '状态', op: '=', value: '启用' }] },
  pending: { title: '待核对写操作', match: u => u.pending, tokens: [{ key: 'p', field: '写操作', op: '=', value: '待核对' }] },
  disabled: { title: '已禁用', match: u => u.status === 'disabled', tokens: [{ key: 'st', field: '状态', op: '=', value: '禁用' }] },
};

function WbUsers({ ctx, route }) {
  const view = WB_USER_VIEWS[route.view] || WB_USER_VIEWS.all;
  const columns = [
    { key: 'name', label: '用户', w: 124, sort: u => u.name, render: u => <><span className="wb-avatar">{u.name.slice(0, 1)}</span><span className="wb-cell-text">{u.name}</span></> },
    { key: 'bal', label: '余额', w: 84, align: 'right', mono: true, sort: u => u.balance, render: u => <span className={u.balance < 10 && u.status !== 'disabled' ? 'tone-caution tone-text' : ''}>{fmt.money(u.balance)}</span> },
    { key: 'today', label: '今日', w: 68, align: 'right', mono: true, sort: u => u.today, render: u => fmt.money(u.today) },
    { key: 'status', label: '状态', w: 62, sort: u => u.status, render: u => (u.pending ? <span className="wb-state tone-caution">待核对</span> : u.status === 'disabled' ? <span className="wb-state tone-neutral">禁用</span> : <span className="wb-state">启用</span>) },
    { key: 'email', label: '邮箱', w: 176, sort: u => u.email, render: u => <span className="mono wb-email">{u.email}</span> },
    { key: 'group', label: '分组', w: 70, render: u => u.group || '—' },
  ];
  const sort = route.view === 'low' ? { key: 'bal', dir: 1 } : ctx.sorts.users;
  const rows = sortRows(Object.values(ctx.users).filter(view.match), columns, sort);
  const order = rows.map(u => u.id);
  return (
    <div className="screen">
      <NavBar ctx={ctx} back title={view.title} subtitle={`${ctx.site} · ${rows.length} 行`} trailing={<GlassButton icon="plus" />} />
      <WbQueryBar tokens={view.tokens.map(t => ({ ...t, onRemove: () => ctx.replaceTop({ ...route, view: 'all' }) }))} onAdd={() => ctx.openSheet({ kind: 'conditions', target: 'users' })} />
      <div className="wb-scroll">
        <WbTable columns={columns} rows={rows} rowKey={u => u.id} sort={sort} onSort={k => ctx.setSort('users', k)} onRow={u => ctx.push({ kind: 'user', id: u.id, order })}
          rowClass={u => (u.status === 'disabled' ? 'is-idle' : '')}
          footer={{ name: `合计 ${rows.length} 行`, bal: fmt.money(rows.reduce((s, u) => s + u.balance, 0)), today: fmt.money(rows.reduce((s, u) => s + u.today, 0)) }} />
      </div>
      <WbToolbar center={<b>{rows.length} 行</b>}>
        <WbToolButton label="选择" />
        <WbToolButton icon="columns" label="列" />
      </WbToolbar>
    </div>
  );
}

function WbUser({ ctx, route }) {
  const order = route.order || Object.keys(ctx.users).map(Number);
  const idx = order.indexOf(route.id);
  const u = ctx.users[route.id];
  const go = d => ctx.replaceTop({ ...route, id: order[idx + d], order });
  return (
    <div className="screen">
      <NavBar ctx={ctx} back title={u.name} subtitle={`第 ${idx + 1} / ${order.length} 行 · ${u.email}`}
        trailing={<><GlassButton icon="chevronUp" onClick={() => idx > 0 && go(-1)} /><GlassButton icon="chevronDown" onClick={() => idx < order.length - 1 && go(1)} /></>} />
      <div className="scroll wb-inspector">
        {u.pending && (
          <div className="wb-strip tone-caution">
            <span className="wb-glyph"><Icon name="docCheck" size={14} weight={2.3} /></span>
            <span className="wb-strip-text"><b>充值 {fmt.money(DEMO.pendingOp.amount)} 待核对</b> · {DEMO.pendingOp.ago}</span>
            <button className="wb-strip-btn" onClick={() => reconcileUser(ctx, u)}>核对</button>
          </div>
        )}
        <WbProps title="余额">
          <WbProp label="可用余额" mono><b className="wb-balance">{fmt.money(u.balance)}</b></WbProp>
          <WbProp label="今日消费" mono>{fmt.money(u.today)}</WbProp>
          <WbProp label="本月消费" mono>{fmt.money(u.month ?? null)}</WbProp>
        </WbProps>
        <WbProps title="余额流水">
          <div className="wb-mini">
            <div className="wb-mini-row head"><span>时间</span><span>类型</span><span className="r">金额</span><span className="r">余额</span></div>
            {(u.ledger || []).map((l, i) => (
              <div key={i} className="wb-mini-row ledger"><span className="num">{l.when}</span><span>{l.kind}</span><span className="num r">{fmt.money(l.amount, { sign: true })}</span><span className="num r">{fmt.money(l.after)}</span></div>
            ))}
            {!(u.ledger || []).length && <div className="wb-mini-row"><span className="dim">暂无流水</span></div>}
          </div>
        </WbProps>
        <WbProps title="账户">
          <WbProp label="状态" tone={u.status === 'disabled' ? 'neutral' : null}>{u.status === 'disabled' ? '禁用' : '启用'}</WbProp>
          <WbProp label="分组">{u.group || '—'}</WbProp>
          <WbProp label="并发上限" mono>{u.conc ?? '—'}</WbProp>
          <WbProp label="API Key" mono>{u.keys ? u.keys.length : 0}</WbProp>
        </WbProps>
      </div>
      <WbToolbar>
        <WbToolButton icon="plus" label="充值" primary onClick={() => ctx.openSheet({ kind: 'adjust', userId: u.id, mode: 'topup' })} />
        <WbToolButton icon="restore" label="退款" onClick={() => ctx.openSheet({ kind: 'adjust', userId: u.id, mode: 'refund' })} />
        <WbToolButton icon="more" label="更多" />
      </WbToolbar>
    </div>
  );
}

function WbAdjustSheet({ ctx, sheet }) {
  const u = ctx.users[sheet.userId];
  const [mode, setMode] = useState(sheet.mode);
  const [amount, setAmount] = useState(sheet.amount || '');
  const [note, setNote] = useState('');
  const value = Number(amount) || 0;
  const after = u.balance + (mode === 'topup' ? value : -value);
  const over = mode === 'refund' && value > u.balance;
  const verb = mode === 'topup' ? '充值' : '退款';
  const submit = () => submitBalanceChange(ctx, u, mode, value, note, ctx.closeSheet);
  return (
    <Sheet title="调整余额" onClose={ctx.closeSheet} tall
      trailing={<button className="glass-btn glass-btn-text glass-prominent" disabled={!value || over} onClick={submit}><span>提交</span></button>}>
      <Segmented items={[{ key: 'topup', label: '充值' }, { key: 'refund', label: '退款' }]} value={mode} onChange={setMode} />
      <div className="wb-props">
        <WbProp label="用户">{u.name}</WbProp>
        <label className="wb-prop">
          <span className="wb-prop-label">金额</span>
          <span className="wb-input num"><i>{mode === 'refund' ? '−$' : '$'}</i><input inputMode="decimal" value={amount} placeholder="0.00" aria-label="金额" onChange={e => setAmount(e.target.value.replace(/[^\d.]/g, ''))} /></span>
        </label>
        <label className="wb-prop">
          <span className="wb-prop-label">备注</span>
          <span className="wb-input"><input value={note} placeholder="可选，写进流水" aria-label="备注" onChange={e => setNote(e.target.value)} /></span>
        </label>
      </div>
      <div className={cx('wb-ledger', over && 'tone-critical')}>
        <div><span>当前余额</span><b className="num">{fmt.money(u.balance)}</b></div>
        <div><span>{verb}</span><b className="num">{value ? `${mode === 'topup' ? '+' : '−'} ${fmt.money(value)}` : '—'}</b></div>
        <div className="sum"><span>调整后余额</span><b className="num">{value ? fmt.money(after) : '—'}</b></div>
        {over && <div className="err">退款金额超过当前余额</div>}
      </div>
      <div className="wb-note">提交后会再确认一次，写明对象、站点和金额。结果不明时会出现在“待核对写操作”视图里。</div>
    </Sheet>
  );
}

/* ---------- 记录 ---------- */

const WB_SOURCES = { usage: '用量明细', errors: '错误请求', upstream: '上游错误' };

function WbLogs({ ctx, route }) {
  const [menu, setMenu] = useState(false);
  const pick = { usage: l => l.code === 200, errors: l => l.kind === '错误请求', upstream: l => l.kind === '上游错误' };
  const columns = [
    { key: 't', label: '时间', w: 62, mono: true, sort: l => l.t, render: l => l.t },
    { key: 'code', label: '码', w: 46, mono: true, sort: l => l.code, render: l => <span className={cx('wb-code', l.code !== 200 && (l.code === 429 || l.code === 504 ? 'tone-caution' : 'tone-critical'))}>{l.code}</span> },
    { key: 'model', label: '模型', w: 156, sort: l => l.model, render: l => <span className="mono wb-cell-text">{l.model}</span> },
    { key: 'cost', label: '费用', w: 74, align: 'right', mono: true, sort: l => l.cost ?? -1, render: l => (l.cost === null ? '—' : fmt.money(l.cost, { digits: 4 })) },
    { key: 'dur', label: '耗时', w: 58, align: 'right', mono: true, sort: l => parseFloat(l.dur), render: l => l.dur },
    { key: 'user', label: '用户', w: 104, sort: l => l.user, render: l => l.user },
    { key: 'account', label: '账号', w: 124, sort: l => l.account, render: l => l.account },
  ];
  const sort = ctx.sorts.logs;
  const rows = sortRows(DEMO.logs.filter(pick[route.source]).filter(l => !route.account || l.account === route.account), columns, sort);
  const cost = rows.reduce((s, l) => s + (l.cost || 0), 0);
  const avg = rows.length ? rows.reduce((s, l) => s + parseFloat(l.dur), 0) / rows.length : 0;
  const tokens = [
    { key: 'src', field: '来源', op: '=', value: WB_SOURCES[route.source], menu: true, onClick: () => setMenu(v => !v) },
    { key: 'time', field: '时间', op: '≥', value: '近 24 小时' },
    ...(route.account ? [{ key: 'acct', field: '账号', op: '=', value: route.account, onRemove: () => ctx.replaceTop({ ...route, account: null }) }] : []),
  ];
  return (
    <div className="screen">
      <NavBar ctx={ctx} back title="使用记录" subtitle={`${ctx.site} · ${rows.length} 行`} trailing={<GlassButton icon="search" />} />
      <WbQueryBar tokens={tokens} onAdd={() => ctx.openSheet({ kind: 'conditions', target: 'logs' })} />
      {menu && (
        <div className="wb-pop glass">
          {Object.entries(WB_SOURCES).map(([k, v]) => (
            <button key={k} className="menu-item" onClick={() => { setMenu(false); ctx.replaceTop({ ...route, source: k }); }}>
              <span className="menu-check">{route.source === k && <Icon name="check" size={14} weight={2.8} />}</span><span className="menu-label">{v}</span>
            </button>
          ))}
        </div>
      )}
      <div className="wb-scroll">
        <WbTable columns={columns} rows={rows} rowKey={l => l.t + l.model + l.user} sort={sort} onSort={k => ctx.setSort('logs', k)} onRow={() => ctx.showToast({ text: '请求详情：原型未展开', icon: 'list', tone: 'neutral' })}
          footer={{ t: `${rows.length} 行`, cost: fmt.money(cost), dur: `${avg.toFixed(1)}s` }} />
      </div>
      <WbToolbar center={<><b>{rows.length} 行</b><small>费用 {fmt.money(cost)}</small></>}>
        <WbToolButton icon="sort" label="排序" onClick={() => ctx.setSort('logs', 'cost')} />
        <WbToolButton icon="columns" label="列" />
      </WbToolbar>
    </div>
  );
}

function WbConditionsSheet({ ctx, sheet }) {
  const top = ctx.top;
  const choose = patch => { ctx.closeSheet(); ctx.replaceTop({ ...top, ...patch }); };
  const presets = {
    accounts: [['状态 ∈ 错误 · 过载 · 限流 · 临时', { view: 'needs' }], ['状态 ∈ 过载 · 限流 · 临时', { view: 'limited' }], ['状态 ∈ 暂停 · 停用', { view: 'paused' }]],
    users: [['余额 < $10 且 启用', { view: 'low' }], ['写操作 = 待核对', { view: 'pending' }], ['状态 = 禁用', { view: 'disabled' }]],
    logs: DEMO.accounts.slice(0, 6).map(a => [`账号 = ${a.name}`, { account: a.name }]),
  }[sheet.target];
  return (
    <Sheet title="添加条件" onClose={ctx.closeSheet}>
      <div className="wb-props">
        {presets.map(([label, patch]) => <WbProp key={label} label={<span className="mono wb-cond">{label}</span>} onClick={() => choose(patch)} />)}
      </div>
      <div className="wb-note">条件可以组合，保存后成为工作台里的一个视图。</div>
    </Sheet>
  );
}

function WbColumnsSheet({ ctx }) {
  const cols = accountColumns(ctx).slice(1);
  return (
    <Sheet title="显示的列" onClose={ctx.closeSheet} leadingLabel="完成">
      <div className="wb-props">
        {cols.map(c => (
          <WbProp key={c.key} label={c.label}><WbSwitch on={!ctx.hiddenCols.includes(c.key)} label={`显示 ${c.label}`} onChange={() => ctx.toggleCol(c.key)} /></WbProp>
        ))}
      </div>
      <div className="wb-note">第一列（账号名）固定在左侧，其余列可以左右滑动。</div>
    </Sheet>
  );
}

/* ---------- 渠道矩阵 / 营收逐小时 ---------- */

function WbChannels({ ctx }) {
  const order = ['critical', 'caution', 'neutral', 'ok'];
  const list = [...DEMO.channels].sort((a, b) => order.indexOf(a.state) - order.indexOf(b.state));
  const glyph = { ok: 'normal', caution: 'rate_limited', critical: 'error', neutral: 'inactive' };
  return (
    <div className="screen">
      <NavBar ctx={ctx} back title="渠道矩阵" subtitle="每格 5 分钟 · 近 90 分钟" />
      <div className="wb-scroll">
        <div className="wb-table wb-matrix">
          <div className="wb-tr wb-th">
            <div className="wb-td sticky" style={{ width: 104 }}>渠道</div>
            <div className="wb-td wb-heat-head" style={{ width: 18 * 13 }}><span>−90 分</span><span>现在</span></div>
            <div className="wb-td r" style={{ width: 62 }}>可用率</div>
            <div className="wb-td r" style={{ width: 52 }}>首字</div>
          </div>
          {list.map(ch => (
            <div key={ch.name} className="wb-tr" onClick={() => ctx.showToast({ text: `${ch.name}：原型未展开`, icon: 'signal', tone: 'neutral' })}>
              <div className="wb-td sticky" style={{ width: 104 }}><WbGlyph state={glyph[ch.state]} /><span className="wb-cell-text">{ch.name}</span></div>
              <div className="wb-td wb-heat" style={{ width: 18 * 13 }}>{ch.strip.split('').map((c, i) => <i key={i} className={`h-${c === '.' ? 'n' : c}`} />)}</div>
              <div className={cx('wb-td r num', ch.state !== 'ok' && `tone-${ch.state} tone-text`)} style={{ width: 62 }}>{ch.avail === null ? '—' : `${ch.avail}%`}</div>
              <div className="wb-td r num" style={{ width: 52 }}>{ch.ttft}</div>
            </div>
          ))}
        </div>
        <div className="wb-legend"><span><i className="h-g" />正常</span><span><i className="h-w" />偶发错误</span><span><i className="h-c" />性能下降</span><span><i className="h-r" />不可用</span><span><i className="h-n" />无样本</span></div>
      </div>
      <WbToolbar center={<><b>6 个渠道</b><small>2 个异常</small></>}>
        <WbToolButton icon="sliders" label="阈值" />
        <WbToolButton icon="refresh" label="刷新" onClick={() => ctx.showToast({ text: '已刷新', icon: 'refresh' })} />
      </WbToolbar>
    </div>
  );
}

function WbReport({ ctx }) {
  const hours = DEMO.hourlyYesterday.map((y, h) => ({ h, today: DEMO.hourlyToday[h] ?? null, y }));
  const columns = [
    { key: 'h', label: '时段', w: 74, mono: true, render: r => `${String(r.h).padStart(2, '0')}:00` },
    { key: 'today', label: '今日', w: 80, align: 'right', mono: true, render: r => (r.today === null ? '—' : fmt.money(r.today)) },
    { key: 'y', label: '昨日', w: 80, align: 'right', mono: true, render: r => fmt.money(r.y) },
    { key: 'd', label: '差', w: 78, align: 'right', mono: true, render: r => (r.today === null ? '—' : fmt.money(r.today - r.y, { sign: true })) },
    { key: 'p', label: '环比', w: 64, align: 'right', mono: true, render: r => (r.today === null ? '—' : `${(((r.today / r.y) - 1) * 100).toFixed(1)}%`) },
  ];
  const sumT = DEMO.hourlyToday.reduce((s, v) => s + v, 0);
  const sumY = DEMO.hourlyYesterday.slice(0, DEMO.hourlyToday.length).reduce((s, v) => s + v, 0);
  return (
    <div className="screen">
      <NavBar ctx={ctx} back title="营收逐小时" subtitle="实际扣费 · 今日 vs 昨日" />
      <div className="wb-scroll">
        <WbTable columns={columns} rows={hours} rowKey={r => r.h} rowClass={r => (r.today === null ? 'is-idle' : '')}
          footer={{ h: '至 09 时', today: fmt.money(sumT), y: fmt.money(sumY), d: fmt.money(sumT - sumY, { sign: true }) }} />
      </div>
      <WbToolbar center={<b>24 行</b>}><WbToolButton icon="sort" label="排序" /><WbToolButton icon="columns" label="列" /></WbToolbar>
    </div>
  );
}

/* ---------- phone ---------- */

function WorkbenchPhone({ dark, initial }) {
  const app = useAppModel(initial);
  const [stack, setStack] = useState(initial.stack || []);
  const [selecting, setSelecting] = useState(Boolean(initial.selecting));
  const [selected, setSelected] = useState([]);
  const [hiddenCols, setHiddenCols] = useState([]);
  const [sorts, setSorts] = useState({ accounts: { key: 'state', dir: 1 }, users: { key: 'name', dir: 1 }, logs: { key: 't', dir: -1 } });
  const top = stack[stack.length - 1];
  const ctx = {
    ...app, top, selecting, selected, hiddenCols, sorts,
    push: route => { setStack(s => [...s, route]); setSelecting(false); },
    pop: () => { setStack(s => s.slice(0, -1)); setSelecting(false); },
    replaceTop: route => setStack(s => [...s.slice(0, -1), route]),
    setSort: (table, key) => setSorts(s => ({ ...s, [table]: { key, dir: s[table].key === key ? -s[table].dir : (['today', 'cost', 'dur', 'bal', 'conc', 'rpm'].includes(key) ? -1 : 1) } })),
    toggleSelecting: () => { setSelecting(v => !v); setSelected([]); },
    toggleSelect: id => setSelected(s => (s.includes(id) ? s.filter(x => x !== id) : [...s, id])),
    bulkSchedule: enable => { app.setSchedule(selected, enable); setSelecting(false); setSelected([]); },
    toggleCol: key => setHiddenCols(h => (h.includes(key) ? h.filter(x => x !== key) : [...h, key])),
  };
  const screens = {
    accounts: r => <WbAccounts ctx={ctx} route={r} />,
    account: r => <WbAccount ctx={ctx} route={r} />,
    users: r => <WbUsers ctx={ctx} route={r} />,
    user: r => <WbUser ctx={ctx} route={r} />,
    logs: r => <WbLogs ctx={ctx} route={r} key={r.source} />,
    channels: () => <WbChannels ctx={ctx} />,
    report: () => <WbReport ctx={ctx} />,
  };
  return (
    <PhoneFrame dark={dark} canvas={dark ? '#0B0E10' : '#F1F3F4'} className="pal-vernier lay-workbench">
      {top ? screens[top.kind](top) : <WbRoot ctx={ctx} />}
      <Overlays ctx={ctx}>
        {ctx.sheet && ctx.sheet.kind === 'adjust' && <WbAdjustSheet ctx={ctx} sheet={ctx.sheet} key={ctx.sheet.userId + ctx.sheet.mode} />}
        {ctx.sheet && ctx.sheet.kind === 'conditions' && <WbConditionsSheet ctx={ctx} sheet={ctx.sheet} />}
        {ctx.sheet && ctx.sheet.kind === 'columns' && <WbColumnsSheet ctx={ctx} />}
      </Overlays>
    </PhoneFrame>
  );
}

mountPage({
  key: 'workbench',
  pageClass: 'page-vernier page-layout',
  title: 'C · 表格工作台',
  concept: '像“邮件”加电子表格：没有 Tab 栏。根页是“视图”列表——需处理账号、余额低用户、上游错误……每个视图是一张带条件的表，计数直接写在旁边，可以自己新建和置顶。账号、用户、日志都是可排序、可横滑、首列冻结的表格，带合计行；点一行进入检查器，用上一条 / 下一条在同一张表里逐行处理，操作在底部工具栏。',
  traits: ['无 Tab 栏：视图列表 + 底部工具栏', '视图 = 条件 + 列，可新建 / 置顶', '首列冻结、可横滑的表格', '点表头排序 + 合计行', '勾选列批量', '检查器：属性表', '上一条 / 下一条逐行处理', '充值用表单 + 算式账目', '渠道热力矩阵'],
  structure: [
    ['导航', '没有 Tab 栏；单一导航栈，根页是视图列表；站点切换是根页顶部的范围选择（含“全部站点”）'],
    ['首页', '视图列表（置顶 / 账号 / 用户 / 记录 / 监控与资源），每行带计数；顶部一块 6 格指标'],
    ['账号列表', '表格：冻结账号名，状态 · 今日 · 并发 · RPM · 平台 · 分组 …可横滑；点表头排序；合计行'],
    ['账号详情', '检查器：状态条 + 属性表（状态 / 容量 / 今日 / 最近请求 / 档案）；上一条 / 下一条；操作在工具栏'],
    ['批量', '强：“选择”出勾选列，工具栏换成批量操作'],
    ['日志', '根页的“用量明细 / 错误请求 / 上游错误”直接进；查询条件条（来源、时间、账号）+ 表格'],
    ['充值', '用户检查器工具栏 → 表单（金额、备注）+ 算式账目（当前 ± 金额 = 调整后）→ 提交再确认'],
  ],
  defaultDark: false,
  phones: [
    { label: '工作台 · 视图列表代替 Tab，计数一眼可见', initial: { stack: [] } },
    { label: '全部账号 · 冻结首列、横滑看更多列、点表头排序', initial: { stack: [{ kind: 'accounts', view: 'all' }] } },
    { label: '账号检查器 · 属性表，上一条 / 下一条逐行处理', initial: { stack: [{ kind: 'accounts', view: 'all' }, { kind: 'account', id: 3 }] } },
    { label: '调整余额 · 表单 + 算式账目', initial: { stack: [{ kind: 'users', view: 'all' }, { kind: 'user', id: 1 }], sheet: { kind: 'adjust', userId: 1, mode: 'topup', amount: '50' } } },
    { label: '使用记录 · 查询条件条 + 表格 + 合计', initial: { stack: [{ kind: 'logs', source: 'usage', account: 'Claude-官方-01' }] } },
    { label: '渠道矩阵 · 渠道 × 时间热力表', initial: { stack: [{ kind: 'channels' }] } },
  ],
  App: WorkbenchPhone,
});
