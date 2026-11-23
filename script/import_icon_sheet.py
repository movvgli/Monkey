# /// script
# dependencies = ["Pillow==13.0.0", "numpy", "scipy"]
# ///
"""Rebuild the macOS icon catalog from the approved sheet: uv run script/import_icon_sheet.py."""
import json
from pathlib import Path

import numpy as np
from PIL import Image
from scipy.ndimage import distance_transform_edt, label

ROOT = Path(__file__).resolve().parents[1]
CATALOG = ROOT / "Sources/Wookey/Resources/Assets.xcassets"
SHEET = Image.open(ROOT / "Resources/Artwork/WookeyIcons.png").convert("RGBA")

# Bounds include the antialiased edge, excluding stray pixels between illustrations.
ROWS = [
    ("AppIcon FileShelfFolderWookey ImageShelfWookey LightningMascot MenuBarBanana MenuBarWookey WookeyCommandAdd WookeyCommandBold",
     [(18, 19, 117, 119), (162, 17, 245, 120), (297, 15, 383, 121), (446, 17, 506, 118), (567, 24, 654, 113), (691, 23, 804, 112), (838, 24, 930, 115), (978, 20, 1060, 119)]),
    ("WookeyCommandCheck WookeyCommandChevron WookeyCommandClose WookeyCommandCopy WookeyCommandDelete WookeyCommandEdit WookeyCommandItalic WookeyCommandOpen",
     [(21, 165, 116, 246), (173, 158, 231, 251), (298, 164, 382, 249), (435, 160, 515, 248), (573, 158, 650, 249), (707, 158, 793, 249), (850, 165, 916, 245), (980, 166, 1056, 243)]),
    ("WookeyCommandPlay WookeyCommandRefresh WookeyCommandSearch WookeyCommandSettings WookeyCommandStop WookeyCommandUnderline WookeySettingsAccessibility WookeySettingsDiagnostics",
     [(32, 302, 103, 383), (155, 291, 251, 390), (298, 301, 375, 381), (432, 296, 519, 386), (565, 294, 658, 387), (705, 291, 791, 394), (836, 293, 930, 389), (977, 296, 1062, 386)]),
    ("WookeySettingsDownload WookeySettingsInfo WookeySettingsLogin WookeySettingsMenuBar WookeySettingsPalette WookeySettingsPermissions WookeySettingsStorage WookeySettingsSync",
     [(30, 429, 106, 523), (158, 431, 248, 523), (298, 430, 380, 525), (434, 440, 517, 512), (568, 436, 655, 517), (703, 426, 792, 528), (831, 439, 936, 511), (967, 442, 1071, 513)]),
    ("WookeySettingsWarning WookeyShelfFolder WorkflowActionApplication WorkflowActionAttachment WorkflowActionBolt WorkflowActionDocument WorkflowActionKeyboard WorkflowActionLayout",
     [(23, 572, 113, 653), (160, 577, 248, 648), (292, 571, 388, 654), (434, 569, 518, 655), (578, 566, 647, 658), (705, 564, 791, 660), (834, 579, 934, 655), (977, 571, 1063, 654)]),
    ("WorkflowActionLink WorkflowActionPhoto WorkflowActionReturn WorkflowActionTemplate WorkflowActionTemplateNote WorkflowActionWait WookeyCommandPower",
     [(25, 706, 111, 794), (163, 709, 244, 785), (293, 702, 385, 795), (437, 700, 515, 796), (571, 710, 651, 788), (703, 703, 791, 794), (848, 706, 918, 790)]),
]

def remove_background(art):
    # Recover the edge opacity against the sheet's uniform grey background.
    # Preserve the original colors of the solid parts of the illustration.
    rgb = np.asarray(art.convert("RGB"), dtype=float)
    background = np.array([245, 245, 245])
    difference = rgb - background
    flat = np.max(np.abs(difference), axis=2) <= 7
    regions, _ = label(flat)
    flat &= np.bincount(regions.ravel())[regions] >= 6
    interior = distance_transform_edt(~flat) > 1.5
    closest = distance_transform_edt(~interior, return_distances=False, return_indices=True)
    solid = difference[tuple(closest)]
    projection = np.sum(difference * solid, axis=2)
    opacity = np.clip(projection / np.maximum(1, np.sum(solid * solid, axis=2)), 0, 1)
    opacity[interior] = 1
    opacity[flat] = 0
    color = background + difference / np.maximum(opacity[:, :, None], 1 / 255)
    return Image.fromarray(np.dstack((np.clip(color, 0, 255), opacity * 255)).round().astype("uint8"))

def centered_art(art, canvas):
    frame = Image.new("RGBA", (canvas, canvas))
    frame.paste(art, ((canvas-art.width)//2, (canvas-art.height)//2))
    return frame

def save_icon(art, size, destination):
    art.resize((size, size), Image.Resampling.LANCZOS).save(destination)

def import_sheet():
    assert SHEET.size == (1088, 816)
    for row, boxes in ROWS:
        for name, box in zip(row.split(), boxes, strict=True):
            x, y, right, bottom = box
            art = remove_background(SHEET.crop((x-3, y-3, right+3, bottom+3)))
            if name == "AppIcon":
                art = art.crop((3, 3, 3 + right - x, 3 + bottom - y))
                folder = CATALOG / "AppIcon.appiconset"
                for entry in json.loads((folder / "Contents.json").read_text())["images"]:
                    size = int(entry["size"].split("x")[0]) * int(entry["scale"][0])
                    save_icon(art, size, folder / entry["filename"])
                save_icon(art, 1024, ROOT / "website/public/assets/wookey-icon.png")
                continue
            folder = CATALOG / f"{name}.imageset"
            manifest = folder / "Contents.json"
            contents = json.loads(manifest.read_text())
            art = centered_art(art, 124)
            for entry in contents["images"]:
                if name.startswith("MenuBar"):
                    size = 18 * int(entry["scale"][0])
                elif name in ("FileShelfFolderWookey", "ImageShelfWookey", "LightningMascot"):
                    size = 512
                else:
                    size = 192
                save_icon(art, size, folder / entry["filename"])

if __name__ == "__main__":
    import_sheet()
