/* Shared primitives. Directions override only what their visual language changes; CSS carries most of the identity. */

const BADGE_LEVEL = { normal: 0, paused: 1, inactive: 1, rate_limited: 2, overloaded: 2, temp_unsched: 2, error: 3 };

function BaseBadge({ state, secs, tone, label, big }) {
  const meta = state ? STATE_META[state] : null;
  if (state === 'normal') return null;
  const t = tone || meta.tone;
  const level = state ? BADGE_LEVEL[state] : t === 'neutral' ? 1 : t === 'critical' ? 3 : 2;
  return (
    <span className={cx('badge', `tone-${t}`, `lv${level}`, big && 'badge-big')}>
      {meta && <Icon name={meta.icon} size={big ? 15 : 12} weight={2.4} />}
      <span>{label || meta.label}</span>
      {meta && meta.timed && secs !== null && secs !== undefined && <span className="num badge-time">{fmt.countdown(secs)}</span>}
    </span>
  );
}

function BaseGlyph({ state }) {
  const meta = STATE_META[state];
  return (
    <span className={cx('glyph', `tone-${meta.tone}`, `glyph-${state}`)}>
      <Icon name={meta.icon} size={state === 'normal' ? 8 : 17} weight={2.1} />
    </span>
  );
}

function BaseMoney({ value, size = 'm', kind, sign, small }) {
  return (
    <span className={cx('money', `money-${size}`, kind && `kind-${kind}`, value === null || value === undefined ? 'is-missing' : '')}
      aria-label={value === null || value === undefined ? '未返回' : undefined}>
      {fmt.money(value, { sign, small, digits: small && value > 0 && value < 1 ? 4 : 2 })}
    </span>
  );
}

function BaseNum({ size = 'l', children, className }) {
  return <span className={cx('num readout', `readout-${size}`, className)}>{children}</span>;
}

function BaseCapacity({ used, limit, ratio, money, wide, label }) {
  const r = ratio !== undefined ? ratio : used / limit;
  const level = r >= 0.9 ? 'critical' : r >= 0.75 ? 'caution' : 'normal';
  const text = money ? `${fmt.money(used)} / ${fmt.money(limit)}` : ratio !== undefined ? `${Math.round(r * 100)}%` : `${used}/${limit}`;
  return (
    <span className={cx('cap', wide && 'cap-wide', `cap-${level}`, r > 1 && 'cap-over')}>
      <span className="cap-track"><span className="cap-fill" style={{ width: `${Math.min(r, 1) * 100}%` }} /></span>
      <span className="cap-read num">{text}{label && <span className="cap-unit"> {label}</span>}</span>
    </span>
  );
}

function BaseHealth({ score }) {
  const tone = score >= 90 ? 'ok' : score >= 60 ? 'caution' : 'critical';
  const word = healthWord(score);
  return (
    <div className={cx('health', `tone-${tone}`)}>
      <span className="health-label">健康分</span>
      <span className="health-scale">
        <span className="health-zone" style={{ left: '60%' }} />
        <span className="health-zone" style={{ left: '90%' }} />
        <span className="health-fill" style={{ width: `${score}%` }} />
        <span className="health-needle" style={{ left: `${score}%` }} />
      </span>
      <BaseNum size="l">{score}</BaseNum>
      <span className="health-word tone-text">{word}</span>
    </div>
  );
}

function TrendChart({ style }) {
  const W = 343, H = 104, n = 24, max = 270, left = 4, slot = (W - 8) / n;
  const x = i => left + i * slot + slot / 2;
  const y = v => H - 18 - (v / max) * (H - 30);
  const today = DEMO.hourlyToday;
  const yest = DEMO.hourlyYesterday;
  const yPath = yest.map((v, i) => `${i ? 'L' : 'M'}${x(i).toFixed(1)},${y(v).toFixed(1)}`).join(' ');
  const tPath = today.map((v, i) => `${i ? 'L' : 'M'}${x(i).toFixed(1)},${y(v).toFixed(1)}`).join(' ');
  const last = today.length - 1;
  return (
    <svg className="chart" viewBox={`0 0 ${W} ${H}`} width="100%" role="img" aria-label="每小时实际扣费，今天与昨天对比">
      {[0.33, 0.66].map(f => <line key={f} className="chart-grid" x1="0" x2={W} y1={y(max * f)} y2={y(max * f)} />)}
      <line className="chart-base" x1="0" x2={W} y1={H - 18} y2={H - 18} />
      {style === 'bars'
        ? today.map((v, i) => (
          <rect key={i} className={cx('chart-bar', i === last && 'chart-bar-now')} x={x(i) - slot * 0.31} y={y(v)} width={slot * 0.62} height={H - 18 - y(v)} rx="1.5" />
        ))
        : <>
          <path className="chart-area" d={`${tPath} L${x(last)},${H - 18} L${x(0)},${H - 18} Z`} />
          <path className="chart-line" d={tPath} />
          <circle className="chart-end" cx={x(last)} cy={y(today[last])} r="3.4" />
        </>}
      <path className="chart-compare" d={yPath} />
      {[0, 6, 12, 18].map(h => <text key={h} className="chart-axis" x={x(h) - slot / 2} y={H - 4}>{h}时</text>)}
      <text className="chart-axis" x={x(last) - 8} y={H - 4}>现在</text>
    </svg>
  );
}

function BaseSectionHead({ title, meta, index }) {
  return (
    <div className="sec-head">
      <span className="sec-index">{index}</span>
      <span className="sec-title">{title}</span>
      <span className="sec-line" />
      {meta && <span className="sec-meta num">{meta}</span>}
    </div>
  );
}

// Colour comes from codeTone (shared/data.jsx): 2xx quiet, 429 amber, every other failure red.
function BaseCode({ code }) {
  const tone = codeTone(code);
  return <span className={cx('code', `code-${tone === 'neutral' ? 'ok' : tone}`)}>{code ?? '—'}</span>;
}

function BaseChannelStrip({ strip }) {
  return <div className="strip18" aria-hidden="true">{strip.split('').map((c, i) => <i key={i} className={`s-${c === '.' ? 'n' : c}`} />)}</div>;
}

function makeSkin(spec) {
  const skin = {
    sectionLayout: 'outside',
    chartStyle: 'line',
    defaultDark: false,
    rowClass: tone => (['caution', 'critical', 'model'].includes(tone) ? 'rail' : ''),
    SectionHead: BaseSectionHead,
    Badge: BaseBadge,
    Glyph: BaseGlyph,
    Money: BaseMoney,
    Num: BaseNum,
    Capacity: BaseCapacity,
    Health: BaseHealth,
    Code: BaseCode,
    ChannelStrip: BaseChannelStrip,
    ...spec,
  };
  skin.LedgerStrip = spec.LedgerStrip || function LedgerStrip({ ctx }) {
    const t = DEMO.today;
    return (
      <div className="strip">
        <div className="strip-main">
          <small data-kind="actual">今日实际扣费</small>
          <skin.Money value={t.actual} size="xl" kind="hero" />
          <span className="strip-delta"><Icon name="up" size={12} weight={2.6} /> {todayChange().toFixed(1)}% · 比昨天同时</span>
        </div>
        <div className="strip-side">
          <span><small>请求</small><b className="num">{fmt.compact(t.requests)}</b></span>
          <span><small>RPM</small><b className="num">{t.rpm}</b></span>
        </div>
      </div>
    );
  };
  skin.TodayBlock = spec.TodayBlock || function TodayBlock() {
    const t = DEMO.today;
    return (
      <>
        <div className="chart-head pad">
          <span className="chart-title">每小时实际扣费</span>
          <span className="chart-legend"><i className="lg-today" />今天<i className="lg-yest" />昨天</span>
        </div>
        <div className="chart-wrap"><TrendChart style={skin.chartStyle} /></div>
        {/* Plain labels: the chart draws only today's bars and yesterday's dotted line, so a line legend here would read as one of them. */}
        <div className="grid3 pad">
          <div><small>账号成本</small><skin.Money value={t.cost} size="l" kind="cost" /></div>
          <div><small>标准</small><skin.Money value={t.standard} size="l" kind="standard" /></div>
          {/* 利润 = 实际扣费 − 账号成本, the same figure and word as the home metric cells (no “+”; a loss still shows “−”). */}
          <div><small>利润</small><skin.Money value={profitOf(t)} size="l" /></div>
        </div>
        <div className="double-rule" />
        {/* This block is “今日 · 00:00 起”: day figures only. The success rate is today's SLA figure (统计分析 · 今天), and TPM — a
            5-minute average (throughput-trend, the 6-cell figure) — stays out. */}
        <div className="kv-row pad">
          <span>Tokens <b className="num">{fmt.compact(t.tokens)}</b></span>
          <span>成功率 <b className="num">{successRate('today')}</b></span>
        </div>
      </>
    );
  };
  return skin;
}
