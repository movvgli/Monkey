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
     [(38,45,180,191),(219,45,343,189),(398,46,524,188),(591,42,689,192),(747,57,874,179),(913,55,1069,174),(1105,49,1237,184),(1291,48,1409,188)]),
    ("WookeyCommandCheck WookeyCommandChevron WookeyCommandClose WookeyCommandCopy WookeyCommandDelete WookeyCommandEdit WookeyCommandItalic WookeyCommandOpen",
     [(39,244,172,354),(239,237,321,367),(392,239,520,364),(572,233,695,368),(754,230,876,369),(928,231,1057,368),(1119,238,1221,363),(1286,242,1411,365)]),
    ("WookeyCommandPlay WookeyCommandRefresh WookeyCommandSearch WookeyCommandSettings WookeyCommandStop WookeyCommandUnderline WookeySettingsAccessibility WookeySettingsDiagnostics",
     [(45,413,164,544),(210,411,345,547),(389,412,523,545),(571,409,700,544),(748,412,879,545),(933,412,1051,545),(1101,409,1237,549),(1286,412,1423,550)]),
    ("WookeySettingsDownload WookeySettingsInfo WookeySettingsLogin WookeySettingsMenuBar WookeySettingsPalette WookeySettingsPermissions WookeySettingsStorage WookeySettingsSync",
     [(49,585,156,716),(213,583,345,718),(396,575,516,722),(561,594,709,709),(743,588,882,717),(927,580,1053,723),(1095,596,1242,702),(1272,600,1424,702)]),
    ("WookeySettingsWarning WookeyShelfFolder WorkflowActionApplication WorkflowActionAttachment WorkflowActionBolt WorkflowActionDocument WorkflowActionKeyboard WorkflowActionLayout",
     [(33,749,175,877),(209,758,347,876),(385,751,529,876),(574,747,694,880),(761,749,866,880),(929,749,1051,879),(1090,767,1243,870),(1277,751,1420,878)]),
    ("WorkflowActionLink WorkflowActionPhoto WorkflowActionReturn WorkflowActionTemplate WorkflowActionTemplateNote WorkflowActionWait",
     [(34,918,170,1057),(210,926,347,1052),(385,924,524,1053),(577,912,696,1055),(748,926,880,1052),(920,919,1057,1060)]),
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
                art = centered_art(box, 166)
                folder = CATALOG / "AppIcon.appiconset"
                for entry in json.loads((folder / "Contents.json").read_text())["images"]:
                    size = int(entry["size"].split("x")[0]) * int(entry["scale"][0])
                    save_icon(art, size, folder / entry["filename"])
                save_icon(art, 1024, ROOT / "website/public/assets/wookey-icon.png")
                continue
            folder = CATALOG / f"{name}.imageset"
            manifest = folder / "Contents.json"
            contents = json.loads(manifest.read_text())
            art = centered_art(box, 166)
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
