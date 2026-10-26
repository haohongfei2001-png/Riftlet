# Riftlet · 第一轮视觉探索归档

> 历史候选归档。A 待改进，B 淘汰，C 淘汰；三者均未批准。最新裁决见 [CURRENT_DISPOSITION.md](CURRENT_DISPOSITION.md)。

## 保存范围

本目录实际保存第一轮三方向主图、对照板、用户收到的原始评审册、两段影片及原始 ZIP，并保留完整文件清单、字节大小与 SHA-256。原始图像、PDF、影片与 ZIP 未经重制。原始规格 [REVIEW_MANIFEST.json](REVIEW_MANIFEST.json) 按字节原样保存；其中的阶段、推荐与参数均属于第一轮历史，不代表最新批准。

**本次实际提交 8 个原始二进制文件：4 张 PNG、1 份 PDF、2 段 MP4、1 个原始 ZIP。** 每个文件的 Git blob SHA-1 均已与本地原件一致核对。其余图像完整保留在原 ZIP 中，不重复展开四十多张同内容图片。

下表主成果已指向本目录的实际公开文件。其余保留的个人 ChatGPT Library 备份链接须通过拥有访问权限的本人账号打开；这些备份链接不会因仓库公开而自动变成公开文件。Figma 链接同样遵循原文件访问权限。

## 原始成果入口

| 成果 | 原始访问链接 |
| --- | --- |
| 完整第一轮压缩包（原字节；含43张PNG） | [Riftlet_Review_Package.zip](Riftlet_Review_Package.zip) |
| 用户实际收到并重新附上的原始评审册 | [Riftlet_Design_Review.pdf](Riftlet_Design_Review.pdf) |
| 三个方向对照板 | [Riftlet_Directions.png](Riftlet_Directions.png) |
| A · 切面：1440×900原尺度 | [Riftlet_A_Cut_1440.png](Riftlet_A_Cut_1440.png) |
| B · 转轴：1440×900原尺度 | [Riftlet_B_Hinge_1440.png](Riftlet_B_Hinge_1440.png) |
| C · 隙口：1440×900原尺度 | [Riftlet_C_Aperture_1440.png](Riftlet_C_Aperture_1440.png) |
| A完整交互影片 | [Riftlet_A_Interaction_Film.mp4](Riftlet_A_Interaction_Film.mp4) |
| 三个方向运动对照影片 | [Riftlet_Direction_Motion_Comparison.mp4](Riftlet_Direction_Motion_Comparison.mp4) |
| 几何与命中规格板 | [Riftlet_Geometry.png](https://chatgpt.com/library?file_id=libfile_e924a3ed24f48191b43708a13c461377&account_id=personal) |
| 连续交互关键帧 | [Riftlet_Interaction_Keyframes.png](https://chatgpt.com/library?file_id=libfile_c8a891ff51c4819181d703e4a1be8b1f&account_id=personal) |
| 管理界面：历史 | [Riftlet_Manager_History.png](https://chatgpt.com/library?file_id=libfile_059fc1c650d48191b4b23f2adcad4dc8&account_id=personal) |
| 管理界面：设置 | [Riftlet_Manager_Settings.png](https://chatgpt.com/library?file_id=libfile_02bb7e2c2a748191b313e2205057266f&account_id=personal) |

可编辑原始方向图稿：[Figma 设计文件](https://www.figma.com/design/ALMiLuDJ8em0BXPxJ9XIXG)。本归档没有修改该文件。

完整的18个原始交付访问链接、47个 ZIP 成员及校验值见 [ARCHIVE_MANIFEST.json](ARCHIVE_MANIFEST.json)；纯校验清单见 [SHA256SUMS.txt](SHA256SUMS.txt)。

## 原始 PDF 的两个来源

用户本轮提供的原 PDF 为优先评审原件：`3632891` 字节，SHA-256 `f51f1fe3f10c8df3f3fcf6cdc3d9755e143e6c4f4ecf844b98c54ec448142601`。

原始 ZIP 内同名 PDF 为 `3607899` 字节，SHA-256 `6f842474ed1c792fc7e07b0208016898c653935c913484b114a2cdf7a4e7d368`。两者字节不同；本归档分别记录来源，不推断差异原因、不声称字节一致，也没有为了统一文件而改写原 ZIP。

## 阅读时的边界

- 原 PDF 和评价板保留原文；其中任何“保留 B/C”或其他旧推荐都只是历史判断，已被最新用户裁决取代。
- 图像是合成桌面中的设计作品，影片使用合成状态时间；它们不是已运行软件或真实上传测试的证据。
- 原始材料参考主分支 `a773d19e93ced206d0b87b41b6d8dd504535ecfe`；本归档仅新增 `design/explorations/round-01/` 文件。
- 正式产品、技术与决策文件不在本次改动范围内。
