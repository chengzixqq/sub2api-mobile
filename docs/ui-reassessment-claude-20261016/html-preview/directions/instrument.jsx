const DIRECTION_TITLE = '游标 Vernier · 精密仪器';

const VernierSkin = makeSkin({
  key: 'instrument',
  title: 'A · 收件箱（游标 Vernier）',
  concept: '先回答“现在有什么要我处理”。四个 Tab 对应四个高频任务；“今日”首页就是一条待处理队列：哪个账号、什么原因、几点恢复，可以直接点“测试”，营收压成顶部一行。账号是满宽三行列表，按紧急程度分组；详情先给状态卡和倒计时，再给容量、今日、记录。视觉是游标：石墨黑白，只有异常才亮。',
  traits: ['4 个 Tab + 搜索', '首页 = 待处理队列', '营收压成一行', '三行列表按紧急分组', '状态卡 + 倒计时', '选择模式 + 底部坞', '日志进搜索目录'],
  defaultDark: false,
  chartStyle: 'bars',
  canvas: dark => (dark ? '#0B0E10' : '#F1F3F4'),
  appClass: 'pal-vernier',
  pageClass: 'page-vernier',
});

mountInbox(VernierSkin);
