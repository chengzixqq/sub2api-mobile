# HTML 布局预览（Claude 方案）

打开 `index.html`（双击即可，离线可用）：三套布局的对比页 + 逐项对比表，点「打开 6 屏交互」进入每一套。

| 文件 | 布局 | 一句话 |
|---|---|---|
| `a-inbox.html` | A · 收件箱 | 4 个 Tab；首页是待处理队列；三行列表；状态卡详情 |
| `b-dashboard.html` | B · 卡片仪表盘 | 2 个 Tab（摘要 · 浏览）；可编辑卡片墙；磁贴 + 轮播；通行证卡 + 环形容量；数字键盘充值 |
| `c-workbench.html` | C · 表格工作台 | 无 Tab 栏；视图列表；冻结首列的可排序表格 + 合计；检查器 + 上一条 / 下一条；表单 + 算式账目 |
| `style-ledger.html`、`style-signal.html` | 上一轮风格稿 | 与 A 同布局、只换皮，留作参考 |

三套共用游标 Vernier 配色（`shared/vernier-palette.css`，浅色 / 深色）和同一份演示数据；字体、圆角、组件形状各按自己的布局来。URL 参数 `?theme=light|dark` 切主题，`?only=3` 只看第 3 台。

## 目录

```
shared/        ios_frame.jsx（设备框）、data.jsx（演示数据 / 图标）、core.jsx（状态、弹层、预览页）、
               skin-base.jsx（A 的视觉原语）、base.css、vernier-palette.css
layouts/       inbox.jsx（A）、dashboard.jsx/.css（B）、workbench.jsx/.css（C）
directions/    instrument（A 的游标皮肤）、ledger、signal（上一轮风格稿）
screenshots/   每套浅色 / 深色整页截图与手机区截图、index.png
```

## 重新生成

```
node build.cjs                                   # 需要 ../../../build/ui-design-deps/ 里的 React 18.3.1 UMD 与 @babel/standalone
node verify_previews.cjs <playwright-core 路径>    # 交互检查 + 截图，结果写入 VERIFICATION.json
node make_index.cjs                              # 用截图生成 index.html
```

## 边界

- 演示数据全部虚构，不连接任何站点。
- HTML 只比较布局与交互结构。Liquid Glass 真实效果、苹方 / SF 真机渲染、动态字号、触感以 SwiftUI 原型为准；Windows 上用系统字体近似。
- 本轮验证：Chrome 无头浏览器，A 5 项、B 6 项、C 6 项交互 × 浅深两套共 34 项全部通过，0 个控制台错误（`VERIFICATION.json`）。
