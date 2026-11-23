# /// script
# dependencies = ["Pillow==13.0.0", "numpy", "scipy"]
# ///
"""Import the numbered 3D originals with uv run script/import_icon_pack.py PACK_DIR."""
import argparse
import json
from pathlib import Path

import numpy as np
from PIL import Image
from scipy.ndimage import binary_dilation, label

ROOT = Path(__file__).resolve().parents[1]
CATALOG = ROOT / "Sources/Wookey/Resources/Assets.xcassets"
# Asset names in the order of the supplied PNGs. The classic banana (05)
# is skipped because the menu uses the same banana bolt as the app.
ASSET_NAMES = """
AppIcon FileShelfFolderWookey ImageShelfWookey LightningMascot - MenuBarWookey WookeyCommandAdd WookeyCommandBold
WookeyCommandCheck WookeyCommandChevron WookeyCommandClose WookeyCommandCopy WookeyCommandDelete WookeyCommandEdit WookeyCommandItalic WookeyCommandOpen
WookeyCommandPlay WookeyCommandRefresh WookeyCommandSearch WookeyCommandSettings WookeyCommandStop WookeyCommandUnderline WookeySettingsAccessibility WookeySettingsDiagnostics
WookeySettingsDownload WookeySettingsInfo WookeySettingsLogin WookeySettingsMenuBar WookeySettingsPalette WookeySettingsPermissions WookeySettingsStorage WookeySettingsSync
WookeySettingsWarning WookeyShelfFolder WorkflowActionApplication WorkflowActionAttachment WorkflowActionBolt WorkflowActionDocument WorkflowActionKeyboard WorkflowActionLayout
WorkflowActionLink WorkflowActionPhoto WorkflowActionReturn WorkflowActionTemplate WorkflowActionTemplateNote WorkflowActionWait WookeyCommandPower
FileShelfFolderSharkey CoralMascot
""".split()
MASCOT_SIZES = {
    "FileShelfFolderWookey": .86,
    "ImageShelfWookey": .86,
    "LightningMascot": .86,
    "FileShelfFolderSharkey": .953,
    "CoralMascot": .953,
}
MENU_VARIANTS = {
    "LightningMascot": "MenuBarBanana",
    "FileShelfFolderSharkey": "MenuBarSharkey",
    "CoralMascot": "MenuBarCoral",
}


def crop_artwork(path):
    with Image.open(path) as image:
        art = image.convert("RGBA")
    alpha = np.asarray(art.getchannel("A"))
    # Remove isolated specks and keep the soft edges around the main shapes.
    regions, _ = label(alpha > 30, structure=np.ones((3, 3)))
    counts = np.bincount(regions.ravel())
    counts[0] = 0
    major = counts[regions] > counts.max() * .018
    surround = binary_dilation(major, iterations=5)
    mask = Image.fromarray(np.where(surround, alpha, 0))
    bounds = mask.getbbox()
    if bounds is None:
        raise ValueError(f"{path.name} has no visible artwork")
    art.putalpha(mask)
    return art.crop(bounds)


def fit(art, size, coverage):
    ratio = round(size * coverage) / max(art.size)
    dimensions = tuple(max(1, round(side * ratio)) for side in art.size)
    scaled = art.resize(dimensions, Image.Resampling.LANCZOS)
    frame = Image.new("RGBA", (size, size))
    frame.paste(scaled, ((size - scaled.width) // 2, (size - scaled.height) // 2))
    return frame


def export_asset(art, name):
    suffix = "appiconset" if name == "AppIcon" else "imageset"
    folder = CATALOG / f"{name}.{suffix}"
    entries = json.loads((folder / "Contents.json").read_text())["images"]
    for entry in entries:
        if name == "AppIcon":
            size = int(entry["size"].split("x")[0]) * int(entry["scale"][0])
            # Fill both axes of the Dock icon; the artwork retains its own rounded corners.
            icon = art.resize((size, size), Image.Resampling.LANCZOS)
        elif name.startswith("MenuBar"):
            icon = fit(art, 18 * int(entry["scale"][0]), .94)
        elif name in MASCOT_SIZES:
            icon = fit(art, 512, MASCOT_SIZES[name])
        else:
            icon = fit(art, 192, .77)
        icon.save(folder / entry["filename"])


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("pack", type=Path)
    args = parser.parse_args()
    paths = {}
    for number, name in enumerate(ASSET_NAMES, start=1):
        if name == "-":
            continue
        candidates = list(args.pack.glob(f"{number:02}-*.png"))
        if len(candidates) != 1:
            parser.error(f"Expected exactly one PNG starting with {number:02}- in {args.pack}")
        paths[name] = candidates[0]
    artwork = {name: crop_artwork(path) for name, path in paths.items()}
    for name, art in artwork.items():
        export_asset(art, name)
        if name in MENU_VARIANTS:
            export_asset(art, MENU_VARIANTS[name])


if __name__ == "__main__":
    main()
