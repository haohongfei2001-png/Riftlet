"""Localized 9:16 cover. Source images, typography and tray come from the edit."""
from PIL import Image, ImageOps
from sets import IVORY, arrow, mark, txt


def portrait_thumbnail(st):
    size = (1080, 1920)
    # Preserve the sweeping track lines in the original photograph while
    # keeping the title and the translucent tray legible over the same surface.
    photograph = ImageOps.fit(st.b, size, method=Image.Resampling.LANCZOS, centering=(.46, .5))
    background = Image.blend(photograph, Image.new('RGB', size, '#102A27'), .60)
    background = Image.blend(background, Image.new('RGB', size, '#081B18'), .22)
    icon = mark(103)
    background.paste(icon, (77, 113), icon)
    txt(background, (207, 164), 'Riftlet', 114, 'serif', IVORY, 'lm')

    if st.lang == 'zh-CN':
        txt(background, (75, 388), '截图，', 142, 'zh-serif', IVORY, 'lt')
        txt(background, (74, 572), '一点就到草稿。', 129, 'zh-serif', IVORY, 'lt')
    else:
        txt(background, (73, 359), 'One click', 175, 'serif', IVORY, 'lt')
        txt(background, (73, 545), 'to your draft.', 174, 'serif', IVORY, 'lt')

    # On this time step in the master the first two screenshots are collected
    # and the violet camera key is in its actual lower-left slot.
    tray = st.tray.render(13.2)
    tray = tray.resize((1242, 1114), Image.Resampling.LANCZOS)
    background.paste(tray, (-81, 692), tray)
    arrow(background, 406, 1129, 4.4)

    if st.lang == 'zh-CN':
        txt(background, (82, 1757), '从 Mac 截屏到 ChatGPT 草稿', 45, 'zh-light', IVORY, 'lt')
    else:
        txt(background, (82, 1759), 'Mac screenshots to ChatGPT drafts.', 47, 'medium', IVORY, 'lt')
    return background
