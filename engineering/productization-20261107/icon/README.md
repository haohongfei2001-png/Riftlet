# 原 SVG 的原生 App 图标打包

本包只补原有图标资源与构建集成，不重新设计视觉，不修改已安装 App。

原稿是 `website-assets/riftlet.svg`，SHA-256 为 `f31d71318e1aaef2464bbcc25c5a105fa6959d10006eb7c64d30aac42fbb3e90`，原字节未改。生成器将完整的 112×112 viewBox 等比例栅格化；保留原圆角、透明角、`#19B7A4` 与 `#102A27`，不裁切、补白、加阴影或更换图形。

![原 SVG 的 512 像素直接渲染](preview-512.png)

## 可复现生成

仅开发工具使用精确锁定的 `@resvg/resvg-js@2.6.2`（MPL-2.0，见 [上游源码与说明](https://github.com/thx/resvg-js)），依赖包和平台二进制由 `scripts/icon-generator/package-lock.json` 的 integrity 绑定；不执行 npm 安装脚本。它不成为 App 运行时依赖，也不改变 Swift Package。普通构建和 CI 直接使用已提交的 ICNS，无需下载 npm 包。

```bash
npm ci --prefix scripts/icon-generator --ignore-scripts --no-audit --no-fund
node scripts/icon-generator/generate.cjs /absolute/new/icon-output
```

输出目录必须不存在，保留每张 PNG、工具日志及生成清单。标准 16、32、128、256、512 point 各 1×/2× 共十张图组成 `Riftlet.icns`，最高 1024px。八个 PNG 槽直接保留原 PNG 字节；16/32pt 1× 原生 `ic04/ic05` 槽按 ARGB 格式存入同次 resvg 渲染的原始预乘像素，只使用无损 literal 编码，不重新绘制或调整颜色。检查输出后才显式复制到 `Resources/Riftlet.icns`；生成器不覆盖源码或 App。

生成器必须调用系统 `iconutil` 解码实际 ICNS 的全部十个槽，再逐 RGBA 字节与原始 PNG 比较；缺槽、尺寸或任何像素差异都报失败。精确原稿、生成器、lockfile、iconutil、十张 PNG 和 ICNS 散列见 [generation.json](generation.json)。同环境的重复生成另有记录，不泛称任意工具链版本渲染结果相同。

保留的第一轮工具失败：本机 `iconutil` 直接编码时，把小 PNG 的非预乘 RGB 写入 ARGB 槽，解码后两个小槽半透明边缘变亮；八个 PNG 槽仍逐字节一致。16px 有 81 个 RGBA 通道值不同，32px 有 132 个，最大通道差 223。随后 `icp4/icp5` PNG 试验也未通过本机原生解码，未作为最终资源。最终改为直接保存原始预乘像素，实际十槽解码与原 PNG **全部像素完全相等**。原 SVG、首包与失败证据均保留；首包构建成功不代表该轮视觉验证通过。

## 两条构建路径

`Resources/Info.plist` 声明 `CFBundleIconFile=Riftlet.icns`。`build-macos.sh` 和 `release-tool.py build` 均复制相同资源，由共享 verifier 核对声明、ICNS 容器、十个尺寸槽和完整源字节。新的 release inventory 自动包含该资源；离线包和 ZIP 校验都会拒绝声明存在而图标缺失的自洽清单。

历史包若既无图标声明也无图标文件，仍按原合同验证；不得将新资源要求倒灌已安装 Beta 3 或回退包。带图标的新源码包必须保留声明和精确资源。已有 source/manifest pin、Developer ID、STAPLED、公证和数据兼容门槛不变。

此增量不证明真实安装、Dock/Finder 缓存刷新、Gatekeeper、公证、公开分发或截图上传通过。两条实际构建记录和后续独立源审分别由正式交付证据绑定；既有失败日志不覆盖。
