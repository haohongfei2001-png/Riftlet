"""Optional, single-language SRTs for the master and portrait edits."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

# Each row has the same action in both scripts. Per-cut in-points follow the
# cursor, capture and attachment events of that particular edit.
MASTER = [
    (0.00, 'Keep the thought. Mac screenshots to ChatGPT in Chrome.',
     '让思路继续。Mac 截图，一点就到 Chrome 中的 ChatGPT 草稿。'),
    (2.83, 'Capture the rider with a Mac screenshot.', '用 Mac 截下骑手入弯的画面。'),
    (5.57, 'The screenshot appears in the Riftlet tray.', '骑手这张，已经进了 Riftlet 托盘。'),
    (7.20, 'Capture the blue inner line.', '再截一张蓝色内道。'),
    (8.57, 'Both screenshots are at hand.', '两张截图，都在手边。'),
    (10.98, 'Click the rider.', '点选骑手这张。'),
    (13.47, 'The rider is in the current ChatGPT draft.', '骑手这张已附加到当前 ChatGPT 草稿。'),
    (17.80, '“What stands out in this photo? Look at the lean.”', '“这张照片最吸引你的是什么？看看车手的倾角。”'),
    (21.27, 'No file hunt. No dragging.', '不用找文件，也不用拖放。'),
    (24.85, 'Riftlet. Capture. Click. Continue.', 'Riftlet。截屏、点选、继续。'),
    (27.07, 'Download the macOS Public Beta at riftlet.com.', '前往 riftlet.com 下载 macOS 公测版。'),
]
PORTRAIT = [
    (0.00, MASTER[0][1], MASTER[0][2]),
    (1.55, 'Capture the rider.', '截下骑手入弯的画面。'),
    (3.04, MASTER[2][1], MASTER[2][2]),
    (4.07, MASTER[3][1], MASTER[3][2]),
    (4.84, MASTER[4][1], MASTER[4][2]),
    (6.60, MASTER[5][1], MASTER[5][2]),
    (7.77, MASTER[6][1], MASTER[6][2]),
    (9.60, 'Keep typing. “Look at the lean.”', '接着写：“看看车手的倾角。”'),
    (12.00, MASTER[9][1], MASTER[9][2]),
    (13.17, MASTER[10][1], MASTER[10][2]),
]

def clock(seconds):
    minutes, milliseconds = divmod(round(seconds * 1000), 60_000)
    sec, ms = divmod(milliseconds, 1000)
    return f'00:{minutes:02}:{sec:02},{ms:03}'

def export(stem, cues, duration, lang):
    destination = ROOT / 'captions' / lang
    destination.mkdir(parents=True, exist_ok=True)
    texts = []
    for i, (start, en, zh) in enumerate(cues):
        end = cues[i + 1][0] if i + 1 < len(cues) else duration
        label = en if lang == 'en' else zh
        texts.append(f'{i + 1}\n{clock(start)} --> {clock(end)}\n{label}')
    (destination / f'{stem}.{lang}.srt').write_text('\n\n'.join(texts) + '\n', encoding='utf-8')

if __name__ == '__main__':
    for lang in ('en','zh-CN'):
        export('riftlet-commercial', MASTER, 30.0, lang)
        export('riftlet-vertical', PORTRAIT, 15.0, lang)
