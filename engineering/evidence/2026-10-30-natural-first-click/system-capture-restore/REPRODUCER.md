# 最小复现与证据边界

仅在自有无敏感测试窗口中、没有其他桌面输入执行者时运行。不要开启 Riftlet 旧数据根。下列区分本轮实际主动序列与下次应补足的观测。现场脚本与原件留在私有证据归档；公开参数不包含机器 PID/窗口号/路径。

1. 读取 `defaults export com.apple.screencapture -`、`defaults -currentHost read com.apple.screencapture` 与系统快捷键 30；不要写偏好。核对真实源目录与文件元数据基线。
2. 用 Preview 显示自有彩色图。读取实际 WindowServer bounds，不以请求的 AX frame 当实际几何，不对全局逻辑点乘 Retina scale。前台必须仍为该自有窗口，区域在其内部。
3. 旧序列为 `.hidSystemState`、keyCode 21 down/up 均带 Command+Shift，随后 down → 一次 drag → up。三个受限变体依次只增加指针预移动、明确归零自产生的 modifiers、迁移到主屏；保留每个实际全局指针和按钮状态。最后两者鼠标事件中性仍未得到文件。
4. 本轮左屏区域为 `(-650,300,450,320)`、主屏为 `(600,350,450,320)`，仅是已验证自有窗口中的测试坐标，**不可在其他桌面直接照抄**。主屏实际窗口包含区域；原生 touchshield 覆盖两屏。
5. 记录 `screencapture` engine 的 touchshield，分别记录 `com.apple.screencaptureui` 容器。不要把任意 ScreenshotUI 窗口、其关闭或延迟 5 秒消失当作捕获完成。
6. 本轮是在 driver 的 selection_release_posted 记录后轮询新增文件名约 20 秒；该记录比 mouseUp post 晚约 85 ms，不是 OS 释放回执。结束时另查目录 mtime，没有连续监测已有文件改写。下次应使用新观察器同时检查新增和改写；不能回填为本轮已经执行。post() 不是 UI 接收/选区完成回执；T0 保持未知。
7. 独立非交互对照：`screencapture -x -l <已核实自有窗口号> <全新私有控制文件.png>`。不放入监视目录，不输入浏览器；即便有 screenshot metadata，也只标 CLI window control。
8. 若要比较 CLI 选区，使用 `screencapture -i -s -x -t png <全新私有控制文件.png>`，不加会忽略输出参数的 `-p/-u`。本轮该对照在实际启动前被守卫拒绝，**未运行**。应捕获子进程 exit/stderr，并在释放前取得真实选区几何；不能只依赖发出了 drag。避免没有证据的反复试验。

## 可直接运行的只读观察

```sh
swiftc capture-observer.swift -o /tmp/riftlet-capture-observer
/tmp/riftlet-capture-observer --self-check
/tmp/riftlet-capture-observer '<实际系统截图保存目录>' 20 > '<私有输出文件.jsonl>'
```

观察器没有 UI 动作或 App 配置入口。先运行观察器，再由唯一输入所有者操作。输出应留在私有目录；目录内容变化可能来自其他进程，不能仅凭出现新 PNG 就归属本次系统快捷键。`complete_png_observed` 是本观察器读到完整 PNG 的时刻，不是全局最早可读时间，且不验证来源 metadata、私有副本或上传资格。没有此事件也不能独立证明未曾产生完整文件。
