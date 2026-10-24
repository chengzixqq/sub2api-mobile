const DIRECTION_TITLE = '暗舱 Dark Cockpit · 夜航信号';

function CockpitGlyph({ state }) {
  const meta = STATE_META[state];
  if (state === 'normal') return <span className="glyph tone-ok glyph-normal"><span className="dim-dot" /></span>;
  return (
    <span className={cx('glyph', `tone-${meta.tone}`, `glyph-${state}`)}>
      <Icon name={meta.icon} size={17} weight={2.2} />
    </span>
  );
}

const CockpitSkin = makeSkin({
  key: 'signal',
  title: '暗舱 Dark Cockpit · 夜航信号',
  concept: '借用民航“暗驾驶舱”原则：一切正常时面板上没有一盏灯亮着，亮度就是注意力预算。正常账号只有一个暗点；会自己恢复的异常是着色胶囊 + 倒计时；需要人动手的错误是实心胶囊。深色是设计起点（半夜被叫醒时不刺眼），浅色同等质量。品牌“航电青”只表示可操作。',
  traits: ['强调四级：熄灭 / 描边 / 着色 / 实心', '左缘信号轨', '深色下徽标微光', '圆体读数', '同心圆角面板', '品牌青 = 可操作', '“全部正常”只是一行字'],
  defaultDark: true,
  chartStyle: 'line',
  canvas: dark => (dark ? '#080B11' : '#EEF1F5'),
  Glyph: CockpitGlyph,
});

mountInbox(CockpitSkin);
