"""Build the two localized HD video covers for each cut from the film's original layers."""
from pathlib import Path

from PIL import Image, ImageOps

from film import brandbug, on_disk
from sets import IVORY, ROOT, Set, arrow, txt


def landscape_thumbnail(st):
    # The photograph bleeds off the right trim. Its left edge passes behind the
    # tray, so the original picture and the selected tile share a visual axis.
    result = Image.new('RGB', (1920, 1080), IVORY)
    photo = ImageOps.fit(st.a, (770, 1080), method=Image.Resampling.LANCZOS,
                         centering=(.62, .35))
    result.paste(photo, (1150, 0))
    brandbug(result, 103, 84, 100)

    if st.lang == 'zh-CN':
        txt(result, (96, 346), '点一下，', 153, 'zh-serif', anchor='lt')
        txt(result, (96, 532), '截图进草稿。', 150, 'zh-serif', anchor='lt')
        txt(result, (104, 842), 'Mac 截图直达 Chrome 中的 ChatGPT 草稿', 38, 'zh', anchor='lt')
    else:
        txt(result, (92, 310), 'One click', 203, 'serif', anchor='lt')
        txt(result, (92, 516), 'to your draft.', 182, 'serif', anchor='lt')
        txt(result, (104, 838), 'Mac screenshots to ChatGPT in Chrome', 40, 'medium', anchor='lt')

    # Use the completed movie's first press, prior to attachment START.
    # Preserve the actual two-column plate with its original camera key.
    scale = 2.72
    plate = st.tray.render(13.2)
    plate = plate.resize((round(330*scale), round(296*scale)), Image.Resampling.LANCZOS)
    left, top = 947, 328
    on_disk(result, plate, left, top)
    arrow(result, left+105.75*scale, top+99*scale, 2.95)
    return result


def save_cover(image, destination):
    destination.parent.mkdir(parents=True, exist_ok=True)
    profile = Path('/System/Library/ColorSync/Profiles/sRGB Profile.icc').read_bytes()
    image.save(destination, 'JPEG', quality=95, subsampling=0, optimize=True,
               progressive=True, icc_profile=profile)


def main():
    from portrait_art import portrait_thumbnail

    for lang in ('zh-CN', 'en'):
        st = Set(lang)
        directory = ROOT/'thumbnails'/lang
        save_cover(landscape_thumbnail(st), directory/'riftlet-commercial.jpg')
        save_cover(portrait_thumbnail(st), directory/'riftlet-vertical.jpg')


if __name__ == '__main__':
    main()
