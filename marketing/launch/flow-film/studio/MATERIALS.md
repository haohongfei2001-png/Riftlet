# 画面中的两份工作手记

官网的「那些让你停留的片刻」并列呈现配色、代码排错与阅读。边缘演示用横图、竖图和代码图说明截图保留原始比例。本片抽取代码及数学两条线，各自保留同一份未发送的问题。

| 场景 | 连续三次截图 | 对应问题 |
|---|---|---|
| 程序排错 | app.js 的原始三行代码 → 控制台读取 response.items → 调用 map 后的 TypeError | 为什么不能调用 map？ |
| 微积分阅读 | 抛物线和切线上方的误差 → 教材中的局部近似摘记 → 二阶余项的展开式 | 为什么误差是 h²？ |

[官网首页](https://riftlet.com/) · [官网交互及三个场景的页面源码](https://github.com/haohongfei2001-png/Riftlet/blob/9fd8ad15fca043915069904113e5fb67d82b4948/index.html)

## 原图与改编

- 官网的 [报错图](https://github.com/haohongfei2001-png/Riftlet/blob/9fd8ad15fca043915069904113e5fb67d82b4948/website-assets/error.svg) 使用空对象的 items 属性与 map 调用构成可独立理解的示例。两种语言都保留源码和错误字符串。源图 Git blob 为 7ae4e464d40b0fca66a92c7be38ba0aed0fecf44。
- 官网的 [阅读图](https://github.com/haohongfei2001-png/Riftlet/blob/9fd8ad15fca043915069904113e5fb67d82b4948/website-assets/reading.svg) 描绘 y=x² 在 x=1 处的切线。中文替换原图三处英文说明，公式、曲线、配色和原始长宽比沿用官网。源图 Git blob 为 336ad5196625501271106b8f82561c45759c2750。
- 源码提供官网[配色静物](https://github.com/haohongfei2001-png/Riftlet/blob/9fd8ad15fca043915069904113e5fb67d82b4948/website-assets/glass-study.png)的原始比例取图接口。源图 Git blob 为 2f4593262ab240d0b16e2b2c2b6ea098dbfdf492。
- 其余源码页、属性求值、曲线与误差图、展开式、手记版式均为本片的新绘制。摄影、账户数据与私人代码均不进入这些页面。英文版与中文版各自排字。
- 完整手记画面是设计合成。制作用的每张截图，都可从 1440 × 960 的相应手记页面在指定矩形中无重采样裁出。两语言六个页面均通过像素一致性检查。缩略图和附件可复用同一输入。

官网 Pages 公布的源为 main 根目录。开工的 main 314f42e 与随后更新网站版本的 main 9fd8ad1 两个对象中，上述三张图的 Git blob 一致。核查使用官网源码与 GitHub Pages 元数据，直连域名在本机连接重置。
