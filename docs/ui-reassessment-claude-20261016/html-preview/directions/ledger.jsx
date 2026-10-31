const DIRECTION_TITLE = '核簿 Folio · 账簿编辑';

function FolioGlyph({ state }) {
  const meta = STATE_META[state];
  return (
    <span className={cx('glyph', `tone-${meta.tone}`, `glyph-${state}`)}>
      {state === 'normal' ? <Icon name="checkCircle" size={17} weight={1.8} /> : <Icon name={meta.icon} size={17} weight={1.9} />}
    </span>
  );
}

function FolioSectionHead({ title, meta, index }) {
  return (
    <div className="sec-head">
      <span className="sec-index" aria-hidden="true">{index}</span>
      <span className="sec-title">{title}</span>
      <span className="sec-line" />
      {meta && <span className="sec-meta num">{meta}</span>}
    </div>
  );
}

const FolioSkin = makeSkin({
  key: 'ledger',
  title: '核簿 Folio · 账簿编辑',
  concept: '一本用蓝黑墨水誊写、在页边用朱笔批注异常的账簿。金额用衬线誊写、计量用无衬线、编号用等宽——不看标签也能从字形分辨“这是钱还是数量”。正常的行不上色；需要人处理的行，页边多出一条批注线：实线 = 要人动手，虚线 = 会自己恢复。',
  traits: ['字体即类别：钱 / 量 / 编号', '页边批注线（实线、虚线、点线）', '方形印章 vs 胶囊按钮', '合计双线', '暖纸 + 蓝黑墨水', '大写页序 壹贰叁', '金额不用红绿表涨跌'],
  defaultDark: false,
  chartStyle: 'line',
  canvas: dark => (dark ? '#13161C' : '#F4F0E7'),
  sectionLayout: 'inside',
  rowClass: tone => (tone === 'critical' ? 'annot annot-solid' : tone === 'caution' ? 'annot annot-dashed' : tone === 'model' ? 'annot annot-dotted' : ''),
  Glyph: FolioGlyph,
  SectionHead: FolioSectionHead,
});

mountInbox(FolioSkin);
