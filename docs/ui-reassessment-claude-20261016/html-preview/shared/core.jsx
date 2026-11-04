/* Core shared by every layout: app model, chrome (nav, sheets, dialogs, toasts) and the preview page.
   Layouts (layouts/*.jsx) own their navigation structure and screens. */

const { useState, useEffect, useRef } = React;

function cx(...names) { return names.filter(Boolean).join(' '); }
function toneOf(state) { return (STATE_META[state] || STATE_META.inactive).tone; }
function stop(fn) { return e => { e.stopPropagation(); fn && fn(); }; }

/* ---------- shell chrome ---------- */

// What VoiceOver reads for an icon-only toolbar button (SwiftUI: Label("更多操作", systemImage: "ellipsis").labelStyle(.iconOnly)).
// Callers may pass their own a11yLabel; data-icon keeps a stable hook for scripts that used to select [aria-label="more"].
const GLASS_ICON_LABEL = { back: '返回', more: '更多操作', plus: '新建', filter: '筛选', close: '关闭', search: '搜索', refresh: '刷新', sort: '排序', compose: '编辑', sliders: '设置' };

function GlassButton({ icon, label, onClick, prominent, a11yLabel }) {
  return (
    <button className={cx('glass-btn', label && 'glass-btn-text', prominent && 'glass-prominent')} onClick={onClick}
      aria-label={a11yLabel || label || GLASS_ICON_LABEL[icon] || icon} data-icon={icon || undefined}>
      {icon && <Icon name={icon} size={19} weight={2.2} />}
      {label && <span>{label}</span>}
    </button>
  );
}

function NavBar({ ctx, title, subtitle, large, back, leading, trailing, titleMenu }) {
  const left = back
    ? <GlassButton icon="back" onClick={ctx.pop} />
    : leading || <span className="nav-spacer" />;
  const right = trailing ? <div className="nav-trailing">{trailing}</div> : <span className="nav-spacer" />;
  const titleNode = (
    <button className={cx('nav-title', titleMenu && 'has-menu')} onClick={titleMenu ? ctx.toggleSiteMenu : undefined} disabled={!titleMenu}>
      <span className="nav-title-text">{title}{titleMenu && <Icon name="chevronDown" size={13} weight={2.6} />}</span>
      {subtitle && <span className="nav-subtitle">{subtitle}</span>}
    </button>
  );
  if (large) {
    return (
      <header className="nav nav-large">
        <div className="nav-row">{left}{right}</div>
        <div className="nav-large-title">
          <button className={cx('large-title', titleMenu && 'has-menu')} onClick={titleMenu ? ctx.toggleSiteMenu : undefined}>
            {title}{titleMenu && <Icon name="chevronDown" size={18} weight={2.6} />}
          </button>
          {subtitle && <div className="nav-subtitle">{subtitle}</div>}
        </div>
      </header>
    );
  }
  return <header className="nav"><div className="nav-row">{left}{titleNode}{right}</div></header>;
}

function Screen({ nav, children, plain, ctx, footer }) {
  return (
    <div className={cx('screen', plain && 'screen-plain')}>
      {nav}
      <div className={cx('scroll', ctx && ctx.selecting && 'scroll-dock')}>{children}</div>
      {footer}
    </div>
  );
}

// One trailing button at most: a custom action ({label, onPress}) wins over undo. The button's text is what VoiceOver reads.
function Toast({ toast, onUndo, onAction }) {
  const action = toast.action && toast.action.label ? toast.action : null;
  return (
    <div className={cx('toast glass', `tone-${toast.tone || 'ok'}`)} key={toast.id} role="status">
      <span className="toast-icon"><Icon name={toast.icon || 'checkCircle'} size={18} weight={2.2} /></span>
      <span className="toast-text">{toast.text}</span>
      {action
        ? <button className="toast-undo toast-action" onClick={onAction}>{action.label}</button>
        : toast.undo && <button className="toast-undo" onClick={onUndo}>撤销</button>}
    </div>
  );
}

function SiteMenu({ ctx }) {
  return (
    <div className="overlay" onClick={ctx.toggleSiteMenu}>
      <div className="menu glass" onClick={e => e.stopPropagation()}>
        {DEMO.sites.map(s => (
          <button key={s.name} className="menu-item" onClick={() => { ctx.setSite(s.name); ctx.toggleSiteMenu(); }}>
            <span className="menu-check">{ctx.site === s.name && <Icon name="check" size={16} weight={2.6} />}</span>
            <span className="menu-label">{s.name}<small>{s.host}</small></span>
          </button>
        ))}
        <div className="menu-sep" />
        <button className="menu-item"><span className="menu-check" /><span className="menu-label">添加站点…</span></button>
        <button className="menu-item"><span className="menu-check" /><span className="menu-label">站点与凭据</span></button>
      </div>
    </div>
  );
}

/* A confirm (SwiftUI .alert / .confirmationDialog). Optional dialog.input = {label, placeholder, match, value?, caseInsensitive?}: a text
   field (SwiftUI: .alert with a TextField); actions with needsMatch stay disabled until the text equals match (.disabled(text != name));
   caseInsensitive compares without case (a code's hex tail typed as “D4E8” or “d4e8”). dialog.menu = true draws the same spec as a
   toolbar menu instead (ActionMenu). */
function dialogInputMatches(input, text) {
  if (!input) return true;
  const typed = text.trim();
  const want = String(input.match ?? '');
  return input.caseInsensitive ? typed.toLowerCase() === want.toLowerCase() : typed === want;
}

function Dialog({ dialog, close }) {
  const input = dialog.input || null;
  const [text, setText] = useState(input && input.value ? input.value : '');
  if (dialog.menu) return <ActionMenu menu={dialog} close={close} />;
  const matched = dialogInputMatches(input, text);
  return (
    <div className="overlay overlay-dim" onClick={close}>
      <div className="dialog glass" onClick={e => e.stopPropagation()} role="alertdialog" aria-label={dialog.title}>
        <div className="dialog-title">{dialog.title}</div>
        {dialog.message && <div className="dialog-message">{dialog.message}</div>}
        {input && (
          <label className="dialog-input">
            <span className="dialog-input-label">{input.label}</span>
            <input value={text} onChange={e => setText(e.target.value)} placeholder={input.placeholder || input.match} aria-label={input.label}
              autoComplete="off" spellCheck={false} />
          </label>
        )}
        <div className="dialog-actions">
          {dialog.actions.map(a => {
            const off = Boolean(a.needsMatch && !matched);
            return (
              <button key={a.label} className={cx('dialog-btn', a.role && `role-${a.role}`)} disabled={off} aria-disabled={off || undefined}
                onClick={() => { if (off) return; close(); a.onPress && a.onPress(); }}>{a.label}</button>
            );
          })}
        </div>
      </div>
    </div>
  );
}

/* Toolbar ⋯ menu (SwiftUI Menu attached to the button): drops from the top-right corner, plain rows, destructive rows red and last
   behind a divider, no cancel row (tapping outside dismisses). Same spec as ctx.confirm: {title?, message?, actions}. */
function ActionMenu({ menu, close }) {
  const items = menu.actions.filter(a => a.role !== 'cancel');
  const plain = items.filter(a => a.role !== 'destructive');
  const danger = items.filter(a => a.role === 'destructive');
  const row = a => (
    <button key={a.label} role="menuitem" className={cx('menu-item action-menu-item', a.role === 'destructive' && 'is-destructive')}
      disabled={a.disabled} onClick={() => { close(); a.onPress && a.onPress(); }}>
      <span className="menu-label">{a.label}{a.sub && <small>{a.sub}</small>}</span>
    </button>
  );
  return (
    <div className="overlay" onClick={close}>
      <div className="menu glass action-menu" role="menu" aria-label={menu.title} onClick={e => e.stopPropagation()}>
        {menu.title && <div className="action-menu-title">{menu.title}</div>}
        {menu.message && <div className="action-menu-note">{menu.message}</div>}
        {plain.map(row)}
        {danger.length > 0 && plain.length > 0 && <div className="menu-sep" />}
        {danger.map(row)}
      </div>
    </div>
  );
}

function Sheet({ title, onClose, children, leadingLabel = '取消', trailing, tall }) {
  return (
    <div className="overlay overlay-dim sheet-overlay" onClick={onClose}>
      <div className={cx('sheet', tall && 'sheet-tall')} onClick={e => e.stopPropagation()}>
        <div className="sheet-grabber" />
        <div className="sheet-bar">
          <button className="glass-btn glass-btn-text" onClick={onClose}><span>{leadingLabel}</span></button>
          <div className="sheet-title">{title}</div>
          {trailing || <span className="nav-spacer" />}
        </div>
        <div className="sheet-body">{children}</div>
      </div>
    </div>
  );
}


function Chips({ items, value, onChange }) {
  return (
    <div className="chips">
      {items.map(item => (
        <button key={item.key} className={cx('chip', value === item.key && 'on', item.alert && 'chip-alert')} onClick={() => onChange && onChange(item.key)}>
          <span>{item.label}</span>
          {item.count !== undefined && <b className="num">{item.count}</b>}
          {item.menu && <Icon name="chevronDown" size={12} weight={2.6} />}
        </button>
      ))}
    </div>
  );
}

function Segmented({ items, value, onChange }) {
  return (
    <div className="seg">
      {items.map(item => (
        <button key={item.key} className={cx('seg-item', value === item.key && 'on')} onClick={() => onChange(item.key)}>
          {item.label}{item.count !== undefined && <span className="num seg-count">{item.count}</span>}
        </button>
      ))}
    </div>
  );
}

function ActionButton({ label, icon, onClick, primary, small }) {
  return (
    <button className={cx('act', primary && 'act-primary', small && 'act-small')} onClick={stop(onClick)}>
      {icon && <Icon name={icon} size={small ? 14 : 16} weight={2.4} />}<span>{label}</span>
    </button>
  );
}

function KV({ label, value, mono, onClick }) {
  return (
    <div className={cx('kv', onClick && 'tappable')} onClick={onClick}>
      <span className="kv-label">{label}</span>
      <span className={cx('kv-value', mono && 'mono')}>{value}{onClick && <Icon name="chevron" size={12} weight={2.6} />}</span>
    </div>
  );
}


/* 测试连接 (POST admin/accounts/:id/test, SSE). The model is what Web's AccountTestModal preselects from GET :id/models: a Sonnet when
   the list has one, otherwise the list's first model — per platform below. Outcomes as the backend has them:
   - pass → RecoverAccountAfterSuccessfulTest → RecoverAccountState: clears error, rate limit, overload, temp-unschedulable and model
     limits; the schedule switch is untouched, so an errored account (SetError switched it off) ends up 暂停 and needs 启用调度;
   - fail with OpenAI 401 / Claude · Vertex 403 → SetError (state error, switch off).
   A credential error keeps failing until the key is replaced (v-account-edit sets aeKeyReplaced); a.testFail = {code, message} lets a
   page script another failure (the new-account flow's #21). */
const TEST_MODEL = { Anthropic: 'claude-sonnet-4-5', Antigravity: 'claude-sonnet-4-5', OpenAI: 'gpt-4.1', Gemini: 'gemini-2.5-flash', '智谱 GLM': 'glm-4.6', Kimi: 'kimi-k2', DeepSeek: 'deepseek-chat', MiniMax: 'MiniMax-M2', Grok: 'grok-4' };
const TEST_CLEARS = { error: '错误', rate_limited: '限流', overloaded: '过载', temp_unsched: '临时不可调度' };

function testModelOf(a) {
  return TEST_MODEL[a.platform] || 'claude-sonnet-4-5';
}

/* An error the credentials caused (OpenAI 401 / Claude · Vertex 403, invalid_api_key, a revoked OAuth token): recovering the state
   alone cannot fix it — the next request fails again — so the fix is 更换 API Key (API Key accounts) or 重新授权 (token accounts:
   OAuth and Setup Token, see isTokenAccount). True even after the key was replaced (aeKeyReplaced): the error stays until a test passes. */
function isCredentialError(a) {
  return Boolean(a) && a.state === 'error' && /\b40[13]\b|invalid_api_key|凭据|token/i.test(a.error || '');
}

/* Accounts whose credential is an OAuth token: type OAuth or Setup Token (backend Account.IsOAuth). Web treats the two alike —
   AccountActionMenu offers 重新授权 / 刷新令牌 for type oauth || setup-token, and ReAuthAccountModal keeps the account's own method
   (Setup Token: generate-setup-token-url → exchange-setup-token-code → apply-oauth-credentials {type: 'setup-token'}). A Setup Token's
   access token is short-lived as well (expires_in 28800, refreshed by ClaudeTokenRefresher), so both show the token's remaining time,
   and a credential error on either is fixed with 重新授权…, never 更换 API Key…. */
function isTokenAccount(a) {
  return Boolean(a) && (a.type === 'OAuth' || a.type === 'Setup Token');
}

function testOutcome(a) {
  if (a.testFail) return { ok: false, code: a.testFail.code || 401, message: a.testFail.message || '上游拒绝了这次测试请求', credential: Boolean(a.testFail.credential) };
  if (isCredentialError(a) && !a.aeKeyReplaced) {
    const code = Number(((a.error || '').match(/\b(40[13])\b/) || [null, a.platform === 'OpenAI' ? '401' : '403'])[1]);
    // The upstream's wording follows the credential kind: a revoked token for OAuth / Setup Token, a rejected key for API Key accounts.
    const message = isTokenAccount(a) ? 'permission_error: OAuth token has been revoked.'
      : a.platform === 'OpenAI' ? 'invalid_api_key: Incorrect API key provided.' : 'authentication_error: invalid api key';
    return { ok: false, code, message, credential: true };
  }
  return { ok: true };
}

// What a passing test clears, and where the switch leaves the account: null when there is nothing to clear.
function testRecovery(a) {
  const models = a.modelLimits && a.modelLimits.length ? a.modelLimits.length : 0;
  if (!TEST_CLEARS[a.state] && !models) return null;
  const live = a.state !== 'error' && isSchedulable(a);
  const what = [TEST_CLEARS[a.state], models ? `${models} 项模型限流` : null].filter(Boolean).join('和');
  const patch = { modelLimits: [], ...(TEST_CLEARS[a.state] ? { state: live ? 'normal' : 'paused', schedulable: live } : {}), ...(a.state === 'error' ? { error: null } : {}) };
  return { patch, what, live };
}

function TestSheet({ ctx, id }) {
  const a = ctx.accounts[id];
  const [outcome] = useState(() => testOutcome(a));
  const [recovery] = useState(() => (outcome.ok ? testRecovery(a) : null));
  const lines = [
    `→ 测试 ${a.platform} · ${a.name}`,
    `→ 模型 ${testModelOf(a)}`,
    ...(outcome.ok
      ? ['← 首字 1.21s', '← 收到 128 tokens', '← 完成 · 总耗时 3.42s']
      : [`← HTTP ${outcome.code}`, `← ${outcome.message}`, '✕ 测试未通过']),
  ];
  const [n, setN] = useState(1);
  const applied = useRef(false);
  useEffect(() => {
    if (n >= lines.length) return;
    const t = setTimeout(() => setN(n + 1), 650);
    return () => clearTimeout(t);
  }, [n]);
  const done = n >= lines.length;
  useEffect(() => {
    if (!done || applied.current) return;
    applied.current = true;
    if (outcome.ok && recovery) ctx.updateAccount(id, recovery.patch);
    // SetError on a credential failure (an already-errored account stays as it is).
    if (!outcome.ok && outcome.credential && a.state !== 'error') ctx.updateAccount(id, { state: 'error', schedulable: false, error: `${outcome.code} ${outcome.message}`, errorAgo: '刚刚' });
  }, [done]);
  const enable = () => { ctx.closeSheet(); ctx.setSchedule([id], true); };
  let result = null;
  if (done && outcome.ok) {
    result = (
      <div className="result tone-ok ts-result">
        <Icon name="checkCircle" size={20} />
        <span className="ts-result-text">
          <span>测试通过 · 总耗时 <b className="num">3.42s</b></span>
          {recovery && <small>{recovery.live ? `已自动清除${recovery.what}，账号恢复调度` : `已自动清除${recovery.what}，仍暂停调度`}</small>}
        </span>
        {recovery && !recovery.live && <button className="ts-result-act" onClick={enable}>启用调度</button>}
      </div>
    );
  } else if (done) {
    result = (
      <div className="result tone-critical ts-result">
        <Icon name="octagon" size={20} />
        <span className="ts-result-text">
          <span>测试未通过 · <b className="num">{outcome.code}</b></span>
          <small>{!outcome.credential ? '账号状态没有改变，可以稍后重试'
            : isTokenAccount(a) ? '令牌无效，账号保持错误。重新授权后再测试连接' : '凭据无效，账号保持错误。更换 API Key 后再测试连接'}</small>
        </span>
      </div>
    );
  }
  return (
    <Sheet title="测试连接" onClose={ctx.closeSheet} leadingLabel="关闭">
      <div className="sheet-target"><span>{a.name}</span><small>测试会向上游发送一次真实请求，可能产生少量费用</small></div>
      <pre className="stream mono">{lines.slice(0, n).join('\n')}{!done && '\n…'}</pre>
      {result}
    </Sheet>
  );
}


/* ---------- app model shared by all layouts ---------- */

// Settings → 高风险操作需要 Face ID → 金额门槛. Above it, top-ups / refunds and balance redeem codes ask for Face ID after the confirm.
const FACE_ID_LIMIT = 100;

function useAppModel(initial) {
  const iv = initial.v || {};
  // initial.accounts = {[id]: patch}: demo states that start from an edited account (e.g. {7: {aeKeyReplaced: true}}).
  const [accounts, setAccounts] = useState(() => Object.fromEntries(DEMO.accounts.map(a => [a.id, { ...a, ...((initial.accounts || {})[a.id] || {}) }])));
  const [users, setUsers] = useState(() => Object.fromEntries(DEMO.users.map(u => [u.id, { ...u }])));
  const [sheet, setSheet] = useState(initial.sheet || null);
  const [dialog, setDialog] = useState(null);
  const [toast, setToast] = useState(null);
  const [site, setSite] = useState(DEMO.site.name);
  const [siteMenu, setSiteMenu] = useState(Boolean(initial.siteMenu));
  const [faceId, setFaceId] = useState(Boolean(iv.faceId));
  // A redeem-code generation whose result never came back: null | {count, total, ago}. Set by the generator, cleared after 核对.
  const [redeemPending, setRedeemPending] = useState(initial.redeemPending || iv.redeemPending || null);
  // Group edits of this phone (启停、改名、倍率、新建、复制、删除) — every page that shows a group reads ctx.groups / ctx.groupOf.
  const [groups, setGroups] = useState(() => DEMO.groups.map(g => ({ ...g })));
  // Alert handling of this phone: {[event id]: {resolved, silencedUntil}} (PUT alert-events/:id/status, POST alert-silences).
  const [alertMarks, setAlertMarks] = useState(() => initial.alertMarks || {});
  const { elapsed } = useDemoClock();

  useEffect(() => {
    if (!toast) return;
    const t = setTimeout(() => setToast(null), 4200);
    return () => clearTimeout(t);
  }, [toast && toast.id]);

  const showToast = t => setToast({ ...t, id: Math.random() });
  // Undo puts back exactly the accounts it touched, so unrelated edits made meanwhile survive.
  const restore = (before, ids) => setAccounts(s => ({ ...s, ...Object.fromEntries(ids.map(id => [id, before[id]])) }));
  // Each confirm / menu gets its own id, so a dialog opened from another one starts with a fresh text field. ctx.confirm must stay
  // the same function for the phone's lifetime: variant files key their per-phone memory (WeakMap) by it.
  const openDialog = useRef(d => setDialog(d ? { ...d, id: Math.random() } : null)).current;
  // Renaming a group renames it in every member's list (membership is stored by name on the accounts).
  const renameInAccounts = (from, to) => setAccounts(s => Object.fromEntries(Object.entries(s).map(([k, a]) => [k,
    (a.groups || []).includes(from) ? { ...a, groups: to ? a.groups.map(g => (g === from ? to : g)) : a.groups.filter(g => g !== from) } : a])));
  const alerts = DEMO.alerts.map(a => {
    const m = alertMarks[a.id];
    if (!m) return a;
    if (m.resolved && a.status === 'firing') return { ...a, status: 'manual_resolved', resolvedAt: '09:41', since: '刚刚 · 由你手动解决', silencedUntil: m.silencedUntil || null };
    return { ...a, silencedUntil: m.silencedUntil || null };
  });
  const mark = (id, patch) => setAlertMarks(s => ({ ...s, [id]: { resolved: false, silencedUntil: null, ...(s[id] || {}), ...patch } }));
  return {
    accounts, users, elapsed, site, sheet, dialog, toast, siteMenu, faceId, redeemPending, groups,
    // Alerts as this phone sees them (DEMO.alerts plus the handling above); alertOpen = the home's alert (#41) is still firing.
    alerts,
    alertOpen: (alerts.find(a => a.id === DEMO.alert.id) || DEMO.alert).status === 'firing',
    alertStatus: id => ({ resolved: false, silencedUntil: null, ...(alertMarks[id] || {}) }),
    resolveAlert: (id, feedback) => { mark(id, { resolved: true }); if (feedback) showToast(feedback); },
    silenceAlert: (id, until, feedback) => { mark(id, { silencedUntil: until }); if (feedback) showToast(feedback); },
    counts: accountCounts(Object.values(accounts)),
    showToast,
    dismissToast: () => setToast(null),
    openSheet: setSheet,
    closeSheet: () => setSheet(null),
    confirm: openDialog,
    // The same spec drawn as the toolbar ⋯ menu (SwiftUI Menu): ctx.menu({title?, message?, actions}).
    menu: spec => openDialog({ ...spec, menu: true }),
    closeDialog: () => setDialog(null),
    toggleSiteMenu: () => setSiteMenu(v => !v),
    setSite: name => { setSite(name); showToast({ text: `已切换到 ${name}`, icon: 'server' }); },
    setFaceId,
    setRedeemPending,
    groupOf: key => groups.find(g => g.id === key || g.name === key) || null,
    updateGroup: (id, patch, feedback) => {
      const before = groups.find(g => g.id === id);
      if (!before) return;
      setGroups(gs => gs.map(g => (g.id === id ? { ...g, ...patch } : g)));
      if (patch.name && patch.name !== before.name) renameInAccounts(before.name, patch.name);
      if (feedback) showToast({ ...feedback, undo: feedback.undo ? () => {
        setGroups(gs => gs.map(g => (g.id === id ? before : g)));
        if (patch.name && patch.name !== before.name) renameInAccounts(patch.name, before.name);
      } : null });
    },
    addGroup: (group, feedback) => { setGroups(gs => [...gs, group]); if (feedback) showToast(feedback); },
    removeGroup: (id, feedback) => {
      const before = groups.find(g => g.id === id);
      if (!before) return;
      setGroups(gs => gs.filter(g => g.id !== id));
      renameInAccounts(before.name, null);
      if (feedback) showToast(feedback);
    },
    updateAccount: (id, patch, feedback) => {
      const before = accounts[id];
      setAccounts(s => ({ ...s, [id]: { ...s[id], ...patch } }));
      if (feedback) showToast({ ...feedback, undo: feedback.undo ? () => setAccounts(s => ({ ...s, [id]: before })) : null });
    },
    // DELETE admin/accounts/:id. Callers leave the account's own page first (pop in the same handler) — nothing reads it afterwards.
    removeAccount: id => setAccounts(s => Object.fromEntries(Object.entries(s).filter(([k]) => Number(k) !== id))),
    // The schedule switch only: a normal account shows as 暂停 while it is off; a blocked one keeps its state and countdown
    // and gains the “已停止调度” mark. opts.text replaces the receipt text (single-account callers).
    setSchedule: (ids, enable, opts = {}) => {
      const before = accounts;
      setAccounts(s => {
        const next = { ...s };
        ids.forEach(id => {
          const a = next[id];
          const state = enable ? (a.state === 'paused' ? 'normal' : a.state) : (a.state === 'normal' ? 'paused' : a.state);
          next[id] = { ...a, state, schedulable: enable };
        });
        return next;
      });
      const text = opts.text || (ids.length === 1 ? `已${enable ? '启用' : '停止'}调度` : `已${enable ? '启用' : '停止'}调度 ${ids.length} 个账号`);
      showToast({ text, undo: () => restore(before, ids), icon: enable ? 'play' : 'pauseFill', tone: enable ? 'ok' : 'neutral' });
    },
    // feedback.undo = true puts the user back as it was (same as updateAccount).
    updateUser: (id, patch, feedback) => {
      const before = users[id];
      setUsers(s => ({ ...s, [id]: { ...s[id], ...patch } }));
      if (feedback) showToast({ ...feedback, undo: feedback.undo === true ? () => setUsers(s => ({ ...s, [id]: before })) : feedback.undo || null });
    },
  };
}

// balance-history item titles as Web words them (UserBalanceHistoryModal getItemTitle, type admin_balance by the value's sign).
const LEDGER_KIND = { topup: '余额充值（管理员）', refund: '余额扣除（管理员）' };
// The code under a redeemed item, as Web prints it under the value (UserBalanceHistoryModal: code.slice(0, 8) + '...'); admin
// adjustments (admin_balance / admin_concurrency) carry no code here, so they show none. null when there is nothing to show.
const ledgerCode = l => (l && l.code ? `${l.code.slice(0, 8)}...` : null);

// Pending reconciliation resolves to "server already credited" in the demo.
function reconcileUser(ctx, u) {
  const after = u.balance + DEMO.pendingOp.amount;
  ctx.updateUser(u.id, { pending: false, balance: after, ledger: [{ kind: LEDGER_KIND.topup, amount: DEMO.pendingOp.amount, when: '10/16 07:38' }, ...(u.ledger || [])] }, { text: `已核对：服务器已入账 ${fmt.money(DEMO.pendingOp.amount)}` });
}

// Money moves always confirm with object, site and amount. The note (balance API `notes`) rides along into the confirm and the record.
// A disabled user can still be credited or refunded, but the confirm says so.
function submitBalanceChange(ctx, u, mode, value, note, onDone) {
  const signed = mode === 'topup' ? value : -value;
  const after = u.balance + signed;
  const verb = mode === 'topup' ? '充值' : '退款';
  const memo = (note || '').trim();
  const lines = [`站点 ${ctx.site} · 余额 ${fmt.money(u.balance)} → ${fmt.money(after)}`];
  if (memo) lines.push(`备注：${memo}`);
  if (u.status === 'disabled') lines.push(mode === 'topup' ? '该用户已禁用。\n充值后仍不能调用，需先启用。' : '该用户已禁用。');
  if (ctx.faceId && value > FACE_ID_LIMIT) lines.push(`超过 ${fmt.money(FACE_ID_LIMIT, { digits: 0 })}，确认后验证 Face ID。`);
  ctx.confirm({
    title: `向「${u.name}」${verb} ${fmt.money(value)}？`,
    message: lines.join('\n'),
    actions: [
      { label: `${verb} ${fmt.money(value)}`, role: 'destructive', onPress: () => {
        if (onDone) onDone();
        const entry = { kind: LEDGER_KIND[mode], amount: signed, when: '10/16 09:41', ...(memo ? { note: memo } : {}) };
        ctx.updateUser(u.id, { balance: after, ledger: [entry, ...(u.ledger || [])] }, { text: `已向 ${u.name} ${verb} ${fmt.money(value)}` });
      } },
      { label: '取消', role: 'cancel' },
    ],
  });
}

const RECOVER_WHAT = { rate_limited: '限流', overloaded: '过载', temp_unsched: '临时不可调度' };

function confirmRecover(ctx, a) {
  // recover-state clears error / rate limit / overload / temp-unschedulable / model limits but never touches the schedule switch.
  // An errored account had it switched off (SetError sets schedulable=false); a blocked account may have been stopped by hand.
  // Either way it stays paused after recovery unless scheduling is re-enabled in the same step.
  const models = a.modelLimits && a.modelLimits.length ? a.modelLimits.length : 0;
  const what = a.state === 'error' ? '错误状态' : `${RECOVER_WHAT[a.state] || '当前阻断'}${models ? `和 ${models} 项模型限流` : ''}`;
  const live = { text: '已恢复 · 参与调度' };
  if (!isSchedulable(a)) {
    ctx.confirm({
      title: `恢复「${a.name}」？`,
      message: a.state === 'error'
        ? `清除${what}。出错时账号已被停止调度，恢复后仍是暂停，除非同时启用调度。`
        : `清除${what}。这个账号已停止调度，恢复后仍是暂停，除非同时启用调度。`,
      actions: [
        { label: '恢复并启用调度', role: 'default', onPress: () => ctx.updateAccount(a.id, { state: 'normal', schedulable: true, modelLimits: [] }, live) },
        { label: '只恢复状态（保持暂停）', role: 'default', onPress: () => ctx.updateAccount(a.id, { state: 'paused', schedulable: false, modelLimits: [] }, {
          text: '已恢复 · 仍暂停调度', icon: 'pauseFill', tone: 'neutral',
          // One-tap follow-up once the admin has checked the account (setSchedule's own receipt then offers 撤销).
          action: ctx.setSchedule ? { label: '启用调度', onPress: () => ctx.setSchedule([a.id], true) } : null,
        }) },
        { label: '取消', role: 'cancel' },
      ],
    });
    return;
  }
  ctx.confirm({
    title: `恢复「${a.name}」？`,
    message: `清除${what}，账号立即参与调度。`,
    actions: [
      { label: '恢复状态', role: 'default', onPress: () => ctx.updateAccount(a.id, { state: 'normal', schedulable: true, modelLimits: [] }, live) },
      { label: '取消', role: 'cancel' },
    ],
  });
}

// Everything that needs a human, most urgent first. Each layout presents the same list differently.
// Every item: {key, kind, tone, title, detail, route} plus kind-specific fields; `route` is where tapping goes (ctx.push(route)).
// The alert item routes to {kind:'alert', id} (event #41): main mode renders slot screen:alert (core base = the alert list with
// that event first; a variant may register a fuller alert page under the same slot).
function deriveAttention(ctx) {
  const list = Object.values(ctx.accounts);
  const items = [];
  const acct = a => ({ key: `a${a.id}`, kind: 'account', id: a.id, state: a.state, title: a.name, sched: schedLabel(a), route: { kind: 'account', id: a.id } });
  list.filter(a => a.state === 'error').forEach(a => items.push({ ...acct(a), tone: 'critical', detail: a.error, meta: `${a.platform} · ${a.errorAgo || ''}` }));
  if (ctx.alertOpen) items.push({ key: 'alert', kind: 'alert', id: DEMO.alert.id, tone: alertTone(DEMO.alert), icon: 'bell', title: DEMO.alert.title, detail: DEMO.alert.detail, badge: DEMO.alert.level, route: { kind: 'alert', id: DEMO.alert.id } });
  list.filter(a => a.state === 'overloaded').forEach(a => items.push({ ...acct(a), tone: 'critical', detail: a.cause, secs: remaining(a, ctx.elapsed) }));
  list.filter(a => ['rate_limited', 'temp_unsched'].includes(a.state)).forEach(a => items.push({ ...acct(a), tone: 'caution', detail: a.cause, secs: remaining(a, ctx.elapsed) }));
  Object.values(ctx.users).filter(u => u.pending).forEach(u => items.push({ key: `u${u.id}`, kind: 'pending', id: u.id, tone: 'caution', icon: 'docCheck', title: '充值结果待核对', detail: `${u.name} · ${DEMO.pendingOp.ago} · ${fmt.money(DEMO.pendingOp.amount)}`, amount: DEMO.pendingOp.amount, route: { kind: 'user', id: u.id } }));
  const rp = ctx.redeemPending;
  // Concurrency, subscription and invitation batches carry no money: total null → no “合计” part.
  if (rp) items.push({ key: 'redeem', kind: 'redeemPending', tone: 'caution', icon: 'docCheck', title: '兑换码生成结果待核对', detail: [`${rp.count} 个`, rp.total === null || rp.total === undefined ? null : `合计 ${fmt.money(rp.total)}`, rp.ago].filter(Boolean).join(' · '), amount: rp.total ?? null, route: { kind: 'redeem', reconcile: true } });
  return items;
}

function Overlays({ ctx, children }) {
  // Dismiss first, so an action that raises its own receipt keeps it (both updates land in the same batch, last one wins).
  const dismiss = run => () => { ctx.dismissToast(); if (run) run(); };
  return (
    <>
      {ctx.toast && <Toast toast={ctx.toast} onUndo={dismiss(ctx.toast.undo)} onAction={dismiss(ctx.toast.action && ctx.toast.action.onPress)} />}
      {ctx.siteMenu && <SiteMenu ctx={ctx} />}
      {children}
      {ctx.sheet && ctx.sheet.kind === 'test' && <TestSheet ctx={ctx} id={ctx.sheet.id} />}
      {ctx.dialog && <Dialog dialog={ctx.dialog} close={ctx.closeDialog} key={ctx.dialog.id} />}
    </>
  );
}

function PhoneFrame({ dark, canvas, className, children }) {
  return (
    <IosFrame darkMode={dark} screenBackground={canvas} fullBleed>
      <div className={cx('app', className, dark ? 'dark' : 'light')}>{children}</div>
    </IosFrame>
  );
}

function Sparkline({ values, compare, w = 140, h = 36, area, className, max }) {
  const top = max || Math.max(...values, ...(compare || [])) * 1.08;
  const step = w / ((compare ? compare.length : values.length) - 1);
  const y = v => (h - 2 - (v / top) * (h - 4)).toFixed(1);
  const path = vals => vals.map((v, i) => `${i ? 'L' : 'M'}${(i * step).toFixed(1)},${y(v)}`).join(' ');
  const line = path(values);
  const lastX = ((values.length - 1) * step).toFixed(1);
  return (
    <svg className={cx('spark', className)} viewBox={`0 0 ${w} ${h}`} width="100%" height={h} preserveAspectRatio="none" aria-hidden="true">
      {compare && <path className="spark-compare" d={path(compare)} />}
      {area && <path className="spark-area" d={`${line} L${lastX},${h} L0,${h} Z`} />}
      <path className="spark-line" d={line} />
    </svg>
  );
}

/* ---------- preview page ---------- */

// URL params: theme=light|dark, only=N (one phone), initial=<JSON> (one phone in that state), bare=1 (phone only, for embedding).
function PreviewPage({ page }) {
  const params = new URLSearchParams(location.search);
  const [dark, setDark] = useState(() => {
    const q = params.get('theme');
    return q ? q === 'dark' : page.defaultDark;
  });
  const only = params.get('only');
  const initialParam = params.get('initial');
  const phones = initialParam ? [{ label: '', initial: JSON.parse(initialParam) }]
    : only ? page.phones.filter((_, i) => String(i + 1) === only) : page.phones;
  const App = page.App;
  if (params.get('bare')) {
    return (
      <div className={cx('page page-bare', page.pageClass, dark ? 'page-dark' : 'page-light')}>
        {phones.map(p => <App key={dark} dark={dark} initial={p.initial} />)}
      </div>
    );
  }
  return (
    <div className={cx('page', page.pageClass, dark ? 'page-dark' : 'page-light')}>
      <header className="page-head">
        <div className="page-kicker">{page.kicker || 'Sub2 Mobile · 布局方案 · 概念初稿 · 演示数据'}</div>
        <h1>{page.title}</h1>
        <p className="page-concept">{page.concept}</p>
        {page.traits && <ul className="page-traits">{page.traits.map(t => <li key={t}>{t}</li>)}</ul>}
        {page.structure && (
          <dl className="page-structure">
            {page.structure.map(([k, v]) => <div key={k}><dt>{k}</dt><dd>{v}</dd></div>)}
          </dl>
        )}
        <div className="page-controls">
          <div className="page-toggle">
            <button className={cx(!dark && 'on')} onClick={() => setDark(false)}>浅色</button>
            <button className={cx(dark && 'on')} onClick={() => setDark(true)}>深色</button>
          </div>
          <a href="index.html">← 返回对比页</a>
        </div>
      </header>
      <main className="phones">
        {phones.map((p, i) => (
          <figure key={p.label + dark} className="phone-cell">
            <figcaption><b>{only || i + 1}</b>{p.label}</figcaption>
            <App dark={dark} initial={p.initial} />
          </figure>
        ))}
      </main>
      <footer className="page-foot">{page.footnote || 'HTML 只用于比较布局与交互结构；系统玻璃、苹方/SF 字体渲染、动态字号与真机手感以 SwiftUI 原型为准。'}</footer>
    </div>
  );
}

function mountPage(page) {
  ReactDOM.createRoot(document.getElementById('root')).render(<PreviewPage page={page} />);
}
