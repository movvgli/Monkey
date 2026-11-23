# /// script
# dependencies = ["Pillow==13.0.0"]
# ///
"""Rebuild the macOS icon catalog from the approved sheet: uv run script/import_icon_sheet.py."""
import json
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
CATALOG = ROOT / "Sources/Wookey/Resources/Assets.xcassets"
SHEET = Image.open(ROOT / "Resources/Artwork/WookeyIcons.png").convert("RGBA")

# Bounds include the antialiased edge, excluding stray pixels between illustrations.
ROWS = [
    ("AppIcon FileShelfFolderWookey ImageShelfWookey LightningMascot MenuBarBanana MenuBarWookey WookeyCommandAdd WookeyCommandBold",
     [(32,39,187,204),(216,43,352,199),(394,43,528,199),(591,37,694,204),(741,56,878,188),(909,48,1084,185),(1110,48,1252,194),(1288,46,1415,198)]),
    ("WookeyCommandCheck WookeyCommandChevron WookeyCommandClose WookeyCommandCopy WookeyCommandDelete WookeyCommandEdit WookeyCommandItalic WookeyCommandOpen",
     [(35,252,176,365),(240,245,324,376),(393,246,526,377),(567,237,703,382),(750,237,879,382),(926,239,1059,381),(1123,246,1225,375),(1282,247,1413,375)]),
    ("WookeyCommandPlay WookeyCommandRefresh WookeyCommandSearch WookeyCommandSettings WookeyCommandStop WookeyCommandUnderline WookeySettingsAccessibility WookeySettingsDiagnostics",
     [(42,419,166,557),(209,418,343,556),(383,419,524,555),(566,419,702,559),(746,422,881,558),(929,422,1053,557),(1096,419,1235,559),(1278,424,1422,560)]),
    ("WookeySettingsDownload WookeySettingsInfo WookeySettingsLogin WookeySettingsMenuBar WookeySettingsPalette WookeySettingsPermissions WookeySettingsStorage WookeySettingsSync",
     [(48,590,158,726),(209,592,346,731),(392,589,520,734),(563,602,708,722),(741,597,885,727),(926,591,1053,731),(1092,603,1241,714),(1274,608,1425,713)]),
    ("WookeySettingsWarning WookeyShelfFolder WorkflowActionApplication WorkflowActionAttachment WorkflowActionBolt WorkflowActionDocument WorkflowActionKeyboard WorkflowActionLayout",
     [(32,761,172,890),(207,767,347,888),(383,767,529,889),(573,760,699,892),(759,760,863,896),(924,761,1053,890),(1092,778,1242,882),(1276,766,1419,892)]),
    ("WorkflowActionLink WorkflowActionPhoto WorkflowActionReturn WorkflowActionTemplate WorkflowActionTemplateNote WorkflowActionWait",
     [(33,923,174,1063),(207,930,347,1055),(384,926,524,1058),(570,917,693,1060),(740,929,882,1060),(915,922,1058,1068)]),
]

def centered_art(box, canvas):
    x, y, right, bottom = box
    art = SHEET.crop((x-2, y-2, right+2, bottom+2))
    frame = Image.new("RGBA", (canvas, canvas))
    frame.paste(art, ((canvas-art.width)//2, (canvas-art.height)//2))
    return frame

def save_icon(art, size, destination):
    art.resize((size, size), Image.Resampling.LANCZOS).save(destination)

def import_sheet():
    assert SHEET.size == (1448, 1086)
    for row, boxes in ROWS:
        for name, box in zip(row.split(), boxes, strict=True):
            if name == "AppIcon":
                art = SHEET.crop(box)
                folder = CATALOG / "AppIcon.appiconset"
                for entry in json.loads((folder / "Contents.json").read_text())["images"]:
                    size = int(entry["size"].split("x")[0]) * int(entry["scale"][0])
                    save_icon(art, size, folder / entry["filename"])
                save_icon(art, 1024, ROOT / "website/public/assets/wookey-icon.png")
                continue
            folder = CATALOG / f"{name}.imageset"
            manifest = folder / "Contents.json"
            contents = json.loads(manifest.read_text())
            art = centered_art(box, 186)
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
