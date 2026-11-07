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

输出目录必须不存在，保留每张 PNG、工具日志及生成清单。系统 `iconutil` 将标准 16、32、128、256、512 point 各 1×/2× 共十张图组成 `Riftlet.icns`，最高 1024px。检查输出后才显式复制到 `Resources/Riftlet.icns`；生成器不覆盖源码或 App。精确原稿、生成器、lockfile、iconutil、十张 PNG 和 ICNS 散列见 [generation.json](generation.json)。同一环境已实际重复生成两次，ICNS 字节一致；不泛称不同版本 iconutil 的容器编码也逐字节相同。

## 两条构建路径

`Resources/Info.plist` 声明 `CFBundleIconFile=Riftlet.icns`。`build-macos.sh` 和 `release-tool.py build` 均复制相同资源，由共享 verifier 核对声明、ICNS 容器、十个尺寸槽和完整源字节。新的 release inventory 自动包含该资源；离线包和 ZIP 校验都会拒绝声明存在而图标缺失的自洽清单。

历史包若既无图标声明也无图标文件，仍按原合同验证；不得将新资源要求倒灌已安装 Beta 3 或回退包。带图标的新源码包必须保留声明和精确资源。已有 source/manifest pin、Developer ID、STAPLED、公证和数据兼容门槛不变。

此增量不证明真实安装、Dock/Finder 缓存刷新、Gatekeeper、公证、公开分发或截图上传通过。两条实际构建记录和后续独立源审分别由正式交付证据绑定；既有失败日志不覆盖。
