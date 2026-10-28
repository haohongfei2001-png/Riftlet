from pathlib import Path
import subprocess

BASE='d6a083dec660990bd65124e7acd78f2d900b5013'
INCOMING='b30bb80d5af5cc12b0640c3609f70292709738a1'
def git(*args):
    return subprocess.check_output(['git',*args],text=True)
conflicts=set(git('diff','--name-only','--diff-filter=U').splitlines())
if conflicts != {'docs/INTEGRATION_HANDOFF.md'}:
    raise SystemExit(f'Unexpected conflicts: {sorted(conflicts)}')
old=git('show',BASE+':docs/INTEGRATION_HANDOFF.md')
round8=git('show',INCOMING+':docs/INTEGRATION_HANDOFF.md').split('\n---\n',1)[0]
header='''# 正式工程交接：第八、九轮与真实系统截图候选合流 · 2026-10-28

本节为当前入口；下方旧交接仅作历史。基线 `d6a083dec660990bd65124e7acd78f2d900b5013` 与固定第九轮 `b30bb80d5af5cc12b0640c3609f70292709738a1` 保留双亲历史；共同祖先 b839230，第八轮 8914c702 已是第九轮祖先，不再 cherry-pick。最终正式 SHA、组合 CI 与审查结果以 PR #1 的本轮交接记录为准，来源 CI 40555899978 不替代组合 CI。

## 本轮组合范围

- 第八轮：原视觉/AX 窗口忽略鼠标，图片与编号为独立非激活输入窗口；外部 CLEAR padding 可由 WindowServer 路由给底层窗口，无事件转发。原按下身份、隐藏、吞噬及补位生命周期保留。AX 提示注册移到当前捕获尝试之后，不产生 ACK 或权限。
- 第九轮：v13 只借用同 root、明确匹配的完整 v10/v12 原监视器；保留原 accessor、旧 operation/proof 和 v6–v12 只读恢复。新旧 generation 权限分离，不重建缺失证明。沿用已声明的 MAIN-world registry 完整性假设；不是对恶意闭包替换的认证。
- 真实截图候选的精确程序版本同步为 v13，仍要求自己的 origin/profile/journal；加入旧 sourceID 拒绝回归，不能放宽为任意程序。Core、SQLite v3、preflight、accepted+30 截止修复、独立数据根、首观察审计及三份空准入映射保留。
- 第九轮 helper 在原系统双击时间界内等待真实窗口几何再投递第二对软件事件；它验证既有补位防误选，不替代物理鼠标双击分类。

## 直接交给本地 Codex：先取得真实截图原始证据

无需重新研究架构，也无需先实现失败安全重试。从本轮最终正式 SHA 新建独立 worktree；保留所有现有工作树、数据库、原图、私有媒体、UNKNOWN、补偿及旧观察器。只用新截图，不重传旧未决。

```bash
bash scripts/build-macos.sh
./build/Riftlet.app/Contents/MacOS/Riftlet --system-screenshot-candidate --acceptance-trace
```

也可从普通 App 菜单选择“打开真实截图内部候选…”。核对 `Riftlet REAL TEST` 与独立 `Riftlet-System-Screenshot-Candidate` 数据根。普通实例仍只收录；测试时避免两个实例的裂缝叠放。首次授权、Chrome JavaScript 开关沿用已有原生引导，不安装扩展，不强制聚焦编辑器。

第一轮顺序与判断：

1. **SC-INPUT**：新系统 PNG 的来源、原字节/私有副本/hash、大小/像素、原点击、先行完整 ACK、完整 target、asset/operation/attempt 和目标文件 `inputCount=1`。不得自动发送消息。
2. **SC-START**：同一原操作/附件的正向进度观察及原文件身份；保存现有 candidate checkpoint，排除 files/change/占位和错目标/错图。不要因当前仍可见而重复点击。
3. **SC-COMPLETE**：同一原附件实际完成与精确内容证明；原正文、选区及已有附件不变。分别记录页面事实、候选观察和本地可见性/UNKNOWN，不把这三个层次混在一起。

**三份候选 start/completion/safe-failure 映射仍为空。** 即使真实页面已正确收到附件，本地仍 UNKNOWN、仍可见，是当前未准入策略的预期结果，不是输入失败；同草稿锁不能被清除来演示连续上传。取得原始 SC-START/SC-COMPLETE 并独立审查后，可以分别准入受限内部候选，复用现成快吞噬；普通生产和 safe-retry 不随之开启。证据公开前移除真实截图内容、私有正文、浏览器认证与完整目标秘密。

## 继承的范围，不扩大为 Beta 通过

第八轮 CLEAR/GAP/IMAGE/NUMBER 与按住补位是限定 CGEvent 软件路由 PASS；不是物理鼠标或图片 alpha/圆角逐像素透传。第九轮保留真实 Chrome v10/v12 只读识别恢复，以及第二击确实到 B、B 零选择的软件双击结果。没有本轮新真实截图/上传/GUI 证据。

无先行完整 ACK 的冷首击仍安全拒绝；第九轮该样本 ACK 晚约209ms，禁止晚到 ACK 补造原授权。业务 ABA/同 URL 无可观察切换、MID、真实安全失败、物理 GUI/显示器矩阵、系统截图自包含与 T0/T1/T2 继续开放，不阻止先取 SC-INPUT/START/COMPLETE。浏览器扩展实验只原样归档，不进入 App/bundle 或正常使用前提。

---

## 前一候选工程交接（历史原文）

'''
Path('docs/INTEGRATION_HANDOFF.md').write_text((header+old+'\n\n---\n\n## 第八轮独立交接（历史原文）\n\n'+round8+'\n').rstrip()+'\n')
p=Path('Sources/RiftletAdapters/SystemScreenshotWebCandidate.swift')
s=p.read_text()
assert s.count('chatgpt-web-zh-20261027-integrated-v12')==1
p.write_text(s.replace('exact bundled v12','exact reviewed bundled v13').replace('chatgpt-web-zh-20261027-integrated-v12','chatgpt-web-zh-20261027-integrated-v13'))
p=Path('Tests/RiftletAdaptersTests/SystemScreenshotWebCandidateTests.swift')
s=p.read_text()
needle='        for client in [noJournal, syntheticProfile] {'
assert s.count(needle)==1
s=s.replace(needle,'''        // A reviewed version change is explicit: neither a stale identifier
        // nor a generated-image profile can enter the real-origin candidate.
        let staleProgram = WebPageProgram(sourceID: "chatgpt-web-zh-20261027-integrated-v12",
            functionSource: page.functionSource, maximumChunkBytes: page.maximumChunkBytes)
        let staleCandidate = WebAttachmentAdapter(mediaDirectory: directory, executor: bridge, program: staleProgram,
            mode: .systemScreenshotCandidate, profile: SystemScreenshotWebCandidate.profile,
            candidateJournal: SystemScreenshotObservationJournal(store: store))
        for client in [noJournal, syntheticProfile, staleCandidate] {''')
p.write_text(s)
p=Path('.github/workflows/native-foundation.yml')
s=p.read_text(); needle='          swift test --skip-build --filter RiftLifecycleTests 2>&1 | tee test-results/rift-lifecycle-detailed.log\n'
assert s.count(needle)==1
p.write_text(s.replace(needle,needle+'          swift test --skip-build --filter RiftInputIslandTests 2>&1 | tee test-results/rift-input-islands-detailed.log\n          swift test --skip-build --filter DeferredChromeActivityBindingTests 2>&1 | tee test-results/deferred-chrome-binding-detailed.log\n'))
p=Path('Tests/RiftletAdaptersTests/Fixtures/LegacyWeb/v12-dom-fixture.cjs')
s=p.read_text(); assert s.count('context.__riftletWebAcceptance20261027v11?.head')==1
p.write_text(s.replace('context.__riftletWebAcceptance20261027v11?.head',"context['__riftletWebAcceptance20261027'+version]?.head"))
subprocess.run(['git','add','docs/INTEGRATION_HANDOFF.md','Sources/RiftletAdapters/SystemScreenshotWebCandidate.swift','Tests/RiftletAdaptersTests/SystemScreenshotWebCandidateTests.swift','.github/workflows/native-foundation.yml','Tests/RiftletAdaptersTests/Fixtures/LegacyWeb/v12-dom-fixture.cjs'],check=True)
actual=git('write-tree').strip()
assert actual=='e1d5eec20a267efa9f9dab1ac8dc31c312dd5d95',actual
print('Exact reviewed merged tree:',actual)
