"""Finder layout for the drag-install volume. Shipping and verifying it require only Python's standard library."""
import datetime
from pathlib import Path
import re
import struct

ARTWORK = Path(__file__).resolve().parents[1] / "packaging/release/finder"
BACKGROUND = ".background/Install.tiff"
MAC_EPOCH_DELTA = 2082844800
# The template contains a Finder v2 alias. Its two creation dates and two HFS
# catalog IDs belong to the finished volume, so bind them after creating HFS+.
VOLUME_BIRTH, IMAGE_BIRTH, FOLDER_ID, IMAGE_ID = range(0xEDF00001, 0xEDF00005)
FIELD_COUNTS = {VOLUME_BIRTH: 2, IMAGE_BIRTH: 2, FOLDER_ID: 2, IMAGE_ID: 1}


def settings(volume):
    image = volume / BACKGROUND
    values = {
        VOLUME_BIRTH: int(volume.stat().st_birthtime) + MAC_EPOCH_DELTA,
        IMAGE_BIRTH: int(image.stat().st_birthtime) + MAC_EPOCH_DELTA,
        FOLDER_ID: image.parent.stat().st_ino,
        IMAGE_ID: image.stat().st_ino,
    }
    # V2 dates occur in both the seconds header and the 16.16 extended
    # records. HFS+ stores integral seconds. CNIDs also occur in the path.
    template = (ARTWORK / "FinderLayout.bin").read_bytes()
    markers = {struct.pack(">I", key): struct.pack(">I", value) for key, value in values.items()}
    for key, count in FIELD_COUNTS.items():
        if template.count(struct.pack(">I", key)) != count:
            raise ValueError("Unexpected Finder layout template")
    return re.sub(b"|".join(re.escape(key) for key in markers), lambda match: markers[match[0]], template)


def generate_template(output):
    """Artist/developer-only regeneration: ds_store==1.3.4, mac_alias==2.2.4."""
    from ds_store import DSStore
    from mac_alias import Alias, TargetInfo, VolumeInfo
    epoch = datetime.datetime(1904, 1, 1, tzinfo=datetime.timezone.utc)
    volume = VolumeInfo("Riftlet", epoch + datetime.timedelta(seconds=VOLUME_BIRTH),
                        b"H+", 0, 0, b"\0\0", posix_path="/Volumes/Riftlet")
    target = TargetInfo(0, "Install.tiff", FOLDER_ID, IMAGE_ID, epoch + datetime.timedelta(seconds=IMAGE_BIRTH),
                        b"\0" * 4, b"\0" * 4, folder_name=".background", cnid_path=[FOLDER_ID],
                        carbon_path=b"Riftlet:.background:\0Install.tiff", posix_path="/" + BACKGROUND)
    alias = Alias(volume=volume, target=target).to_bytes()
    with DSStore.open(str(output), "w+") as store:
        store["."]["vSrn"] = ("long", 1)
        store["."]["vstl"] = ("type", b"icnv")
        store["."]["bwsp"] = {
            "WindowBounds": "{{150, 120}, {620, 328}}", "ShowToolbar": False,
            "ShowStatusBar": False, "ShowSidebar": False, "ShowPathbar": False,
            "ShowTabView": False, "ContainerShowSidebar": False, "SidebarWidth": 0,
        }
        store["."]["icvp"] = {
            "viewOptionsVersion": 1, "backgroundType": 2, "backgroundImageAlias": alias,
            "iconSize": 92.0, "textSize": 13.0, "arrangeBy": "none",
            "gridSpacing": 100.0, "gridOffsetX": 0.0, "gridOffsetY": 0.0,
            "showItemInfo": False, "showIconPreview": False, "labelOnBottom": True,
        }
        store["Riftlet.app"]["Iloc"] = (155, 202)
        store["Applications"]["Iloc"] = (465, 202)


if __name__ == "__main__":
    generate_template(ARTWORK / "FinderLayout.bin")
