# 准确文件清单

本目录共 56 个文件。MANIFEST.json 记录除其自身以外所有文件的字节数及 SHA-256；源码源文件哈希/归档变更见 PROVENANCE.json。

| 文件 | 用途 |
|---|---|
| [FILES.md](FILES.md) | 交接说明、范围、来源、检查或离线入口 |
| [INTEGRATION.md](INTEGRATION.md) | 交接说明、范围、来源、检查或离线入口 |
| [LIMITATIONS.md](LIMITATIONS.md) | 交接说明、范围、来源、检查或离线入口 |
| [MANIFEST.json](MANIFEST.json) | 交接说明、范围、来源、检查或离线入口 |
| [OFFLINE_RESULTS.md](OFFLINE_RESULTS.md) | 交接说明、范围、来源、检查或离线入口 |
| [PROVENANCE.json](PROVENANCE.json) | 交接说明、范围、来源、检查或离线入口 |
| [README.md](README.md) | 交接说明、范围、来源、检查或离线入口 |
| [cases.csv](cases.csv) | 交接说明、范围、来源、检查或离线入口 |
| [environment.json](environment.json) | 交接说明、范围、来源、检查或离线入口 |
| [evidence/exceptions/events.ndjson](evidence/exceptions/events.ndjson) | 交接说明、范围、来源、检查或离线入口 |
| [evidence/exceptions/main/attached-exception-audit.json](evidence/exceptions/main/attached-exception-audit.json) | 真实并发/打字/故障/恢复及审计结果 |
| [evidence/exceptions/main/concurrent-preview-proof.json](evidence/exceptions/main/concurrent-preview-proof.json) | 真实并发/打字/故障/恢复及审计结果 |
| [evidence/exceptions/main/config.json](evidence/exceptions/main/config.json) | 真实并发/打字/故障/恢复及审计结果 |
| [evidence/exceptions/main/final-observation.json](evidence/exceptions/main/final-observation.json) | 真实并发/打字/故障/恢复及审计结果 |
| [evidence/exceptions/main/identity-observation.json](evidence/exceptions/main/identity-observation.json) | 真实并发/打字/故障/恢复及审计结果 |
| [evidence/exceptions/main/mid-final-before-bridge-refinement.json](evidence/exceptions/main/mid-final-before-bridge-refinement.json) | 真实并发/打字/故障/恢复及审计结果 |
| [evidence/exceptions/main/network-cleanup.json](evidence/exceptions/main/network-cleanup.json) | 真实并发/打字/故障/恢复及审计结果 |
| [evidence/exceptions/main/pixel-proof.json](evidence/exceptions/main/pixel-proof.json) | 真实并发/打字/故障/恢复及审计结果 |
| [evidence/exceptions/main/post100-final.json](evidence/exceptions/main/post100-final.json) | 真实并发/打字/故障/恢复及审计结果 |
| [evidence/exceptions/main/recovery-verification.json](evidence/exceptions/main/recovery-verification.json) | 真实并发/打字/故障/恢复及审计结果 |
| [evidence/exceptions/transition/config.json](evidence/exceptions/transition/config.json) | 真实临时聊天目标切换证据 |
| [evidence/exceptions/transition/transition-final.json](evidence/exceptions/transition/transition-final.json) | 真实临时聊天目标切换证据 |
| [evidence/input/ae-observations.ndjson](evidence/input/ae-observations.ndjson) | 最初真实自动附加、保留与刷新恢复证据 |
| [evidence/input/final-composer-snapshot.json](evidence/input/final-composer-snapshot.json) | 最初真实自动附加、保留与刷新恢复证据 |
| [evidence/input/fixtures-original.json](evidence/input/fixtures-original.json) | 最初真实自动附加、保留与刷新恢复证据 |
| [evidence/input/replay-guard-event.json](evidence/input/replay-guard-event.json) | 最初真实自动附加、保留与刷新恢复证据 |
| [evidence/normal/classifier-input.json](evidence/normal/classifier-input.json) | 真实手动上传及历史 ATTACHED 证据 |
| [evidence/normal/events.ndjson](evidence/normal/events.ndjson) | 真实手动上传及历史 ATTACHED 证据 |
| [evidence/normal/receipt-profile-historical.json](evidence/normal/receipt-profile-historical.json) | 真实手动上传及历史 ATTACHED 证据 |
| [evidence/normal/trace-checks.json](evidence/normal/trace-checks.json) | 真实手动上传及历史 ATTACHED 证据 |
| [fixtures/manifest.json](fixtures/manifest.json) | 合成图/字节与元数据清单 |
| [fixtures/synthetic-blue.png](fixtures/synthetic-blue.png) | 合成图/字节与元数据清单 |
| [fixtures/synthetic-noise.png](fixtures/synthetic-noise.png) | 合成图/字节与元数据清单 |
| [fixtures/synthetic-orange.png](fixtures/synthetic-orange.png) | 合成图/字节与元数据清单 |
| [replay.py](replay.py) | 交接说明、范围、来源、检查或离线入口 |
| [src/attached/attached-verdict-v1.cjs](src/attached/attached-verdict-v1.cjs) | 历史或异常轨迹判定器/离线回归 |
| [src/attached/attached_exception_audit.py](src/attached/attached_exception_audit.py) | 历史或异常轨迹判定器/离线回归 |
| [src/attached/test-attached-v1.cjs](src/attached/test-attached-v1.cjs) | 历史或异常轨迹判定器/离线回归 |
| [src/input/ae_probe.py](src/input/ae_probe.py) | 真实运行过的输入/防重复/只读恢复实现 |
| [src/input/dispatch_fixture.py](src/input/dispatch_fixture.py) | 真实运行过的输入/防重复/只读恢复实现 |
| [src/input/recovery-query.js](src/input/recovery-query.js) | 真实运行过的输入/防重复/只读恢复实现 |
| [src/input/shared-adapter.js](src/input/shared-adapter.js) | 真实运行过的输入/防重复/只读恢复实现 |
| [src/input/web-evaluate.applescript](src/input/web-evaluate.applescript) | 真实运行过的输入/防重复/只读恢复实现 |
| [src/lab-only/dispatch-case.py](src/lab-only/dispatch-case.py) | 仅实验用途，禁止进入生产路径 |
| [src/lab-only/javascript-url-probe.applescript](src/lab-only/javascript-url-probe.applescript) | 仅实验用途，禁止进入生产路径 |
| [src/lab-only/network-fault-bridge-v1.template.js](src/lab-only/network-fault-bridge-v1.template.js) | 仅实验用途，禁止进入生产路径 |
| [src/lab-only/network-fault-bridge-v2.template.js](src/lab-only/network-fault-bridge-v2.template.js) | 仅实验用途，禁止进入生产路径 |
| [src/lab-only/prepare-transition.js](src/lab-only/prepare-transition.js) | 仅实验用途，禁止进入生产路径 |
| [src/lab-only/run.py](src/lab-only/run.py) | 仅实验用途，禁止进入生产路径 |
| [src/lab-only/stop-network-bridge.js](src/lab-only/stop-network-bridge.js) | 仅实验用途，禁止进入生产路径 |
| [src/observers/check-concurrent-preview-bytes.js](src/observers/check-concurrent-preview-bytes.js) | 身份、ARMED、附件事件和内容证明探针 |
| [src/observers/compare-source-preview-pixels.template.js](src/observers/compare-source-preview-pixels.template.js) | 身份、ARMED、附件事件和内容证明探针 |
| [src/observers/error-observer.js](src/observers/error-observer.js) | 身份、ARMED、附件事件和内容证明探针 |
| [src/observers/exception-observer.template.js](src/observers/exception-observer.template.js) | 身份、ARMED、附件事件和内容证明探针 |
| [src/observers/hash-final-preview.template.js](src/observers/hash-final-preview.template.js) | 身份、ARMED、附件事件和内容证明探针 |
| [src/observers/normal-bound-observer.template.js](src/observers/normal-bound-observer.template.js) | 身份、ARMED、附件事件和内容证明探针 |
