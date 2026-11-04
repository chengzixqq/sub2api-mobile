/* 已定选择（DECISIONS.md）：合成 main.html 时作为默认变体。对比页的轮次快照（main-r2 等）不包含本文件，保持当时的样子。 */
Object.assign(MAIN_DEFAULTS, {
  // 第 2 轮
  today: 'x', homeRev: 'ticker', homeCalm: 'stage',            // 首页：顶部 6 格指标、待处理合并、没事时专门的平静布局
  accounts: 'platform', acctOrder: 'group',                    // 账号：按平台分组，平台内同分组在一起，再按紧急程度
  users: 'quick', usersRows: 'cols', userDetail: 'hero',       // 用户：顶部快捷充值头像 + 右侧固定列；详情余额大数
  // 第 3 轮（以对比页 HTML 里的选择为准；统计、更多图表、分组、代理、公告都是 base）
  'screen:accountNew': 'form', anOauth: 'list',                // 新建账号：单页长表单，OAuth 三步清单
  'screen:accountEdit': 'inline', accountDetail: 'inline',     // 编辑账号：详情页内联编辑（账号详情就是这一页）
  aeCred: 'row',                                               // 内联编辑里的凭据区用表单行
  'screen:redeem': 'inline',                                   // 兑换码：列表行内展开 + 编辑 sheet（代理、公告仍是列表 + 详情页）
  'sheet:redeemGenerate': 'steps',                             // 批量生成兑换码：分步向导
  'screen:userEdit': 'tabs', 'screen:userNew': 'tabs',         // 新建 / 编辑用户：分段
  ueKeys: 'cards',                                             // Key：可展开卡片；新建 / 停用 / 删除保留“需后端新增”占位
});
