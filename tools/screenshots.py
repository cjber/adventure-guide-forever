#!/usr/bin/env python3
"""Render docs/screenshots/*.png from what the addon draws headlessly, with the WoW: Forever client's own art.

    python3 tools/screenshots.py            # WOWMOCK=/path/to/wow-mock-screenshots overrides the skill's copy

WFA-9: the store and README screenshots come from this script, never from a capture. The panel is
tests/golden/layout.json (docs/plan.md §1.3); every other scene is read from the addon by tests/scenes.lua through
the same harness, so no AGF text or layout is retyped here. Stock templates produce no regions headlessly, so each
one the dumps name has a recipe below citing its Blizzard XML; an unknown stockTemplate fails the run. The frames
around the addon (the world map, the tracker, the tooltip and the menu) are wowmock's (the wow-mock-screenshots
skill), drawn from Blizzard's own layout numbers (WFA-4: the stock look).

Art, fonts and DB2 tables come from wago.tools for BUILD and are cached under ~/.cache/wowmock. The game client is
never started or read. Two runs give byte-identical PNGs with this environment (pip is not installed on the
machine that pinned it, so the freeze is importlib.metadata's, limited to what the script imports):

    Python 3.14.7, pillow==12.3.0
    wowmock.py        db11c4fdc3ea7f43e6a754e28da468b3a1008ee89029466f68b9dc4ac2a93e33
    fonts/frizqt__.ttf (fdid 615960)  73de74d5d63690f29c7f97a9225edc8bd6f89e5103806af3714e4d7bfb9474e9
    fonts/arialn.ttf   (fdid 615958)  bd31d0cf2e5a1a3a9074e98ebe4964c641121e9e660f31627614c4acb6c89c1c

Pillow and wowmock are imported inside the render functions only: CI runs the resolver's tests without Pillow.
"""

import importlib.metadata
import json
import os
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "docs/screenshots"
GOLDEN = ROOT / "tests/golden/layout.json"
WOWMOCK = Path(os.environ.get("WOWMOCK", Path.home() / ".claude/skills/wow-mock-screenshots"))
PILLOW = "12.3.0"
SCALE = 2
LAYOUT_PASSES = 8

# ------------------------------------------------------------------------------ anchors to rects (no Pillow)

POINTS = {
    "TOPLEFT": (0, 0),
    "TOP": (0.5, 0),
    "TOPRIGHT": (1, 0),
    "LEFT": (0, 0.5),
    "CENTER": (0.5, 0.5),
    "RIGHT": (1, 0.5),
    "BOTTOMLEFT": (0, 1),
    "BOTTOM": (0.5, 1),
    "BOTTOMRIGHT": (1, 1),
}


def parent_path(path):
    return path.rsplit(".", 1)[0] if "." in path else None


def explicit_size(entry):
    """The size set with SetSize/SetWidth/SetHeight; 0 is unset, as GetSize(true) reports it."""
    width, height = entry.get("size") or (0, 0)
    return width or None, height or None


def resolve(entries, known, intrinsic=None, defaults=None):
    """Rects {path: (left, top, width, height)} for dumped regions, in UI units with y growing downwards.

    Each anchor pins one of the region's nine points to a point of another rect. Anchors on both edges of an axis
    give that axis's extent (Panel.lua sizes its sections this way); otherwise the axis is placed by its one edge,
    else its centre (so TOPLEFT and RIGHT leave the height alone, as BNet.xml's TopLine relies on), and the size is
    the explicit one, else `intrinsic(entry, width)` (a font string's text, its height the lines it wraps to in the
    width laid out, an atlas used at its size, a stock template's <Size>). `known` fixes rects the dump does not
    hold (the stock frames the addon anchors to); `defaults(entry)` supplies anchors
    for a region the dump shows with none (a stock template's own <Anchors>). A region with no anchors at all
    is not drawn, as in the client, and maps to None."""
    by_path = {entry["path"]: entry for entry in entries}
    rects = dict(known)
    visiting = set()

    def axis(constraints, explicit, fallback):
        if 0 in constraints and 1 in constraints:
            return constraints[0], constraints[1] - constraints[0]
        fraction = next(f for f in (0, 1, 0.5) if f in constraints)
        size = fallback() if explicit is None else explicit
        return constraints[fraction] - fraction * size, size

    def rect(path):
        if path in rects:
            return rects[path]
        if path not in by_path:
            raise KeyError(f"no rect for {path}: add it to the scene's known frames")
        if path in visiting:
            raise ValueError(f"anchor cycle through {path}")
        visiting.add(path)
        entry = by_path[path]
        anchors = entry["anchors"] or (defaults(entry) if defaults else [])
        result = None
        horizontal, vertical = {}, {}
        placed = True
        for anchor in anchors:
            relative = rect(anchor["relativeTo"])
            if relative is None:
                placed = False
                break
            fx, fy = POINTS[anchor["point"]]
            rx, ry = POINTS[anchor["relativePoint"]]
            left, top, width, height = relative
            horizontal[fx] = left + rx * width + anchor["x"]
            vertical[fy] = top + ry * height - anchor["y"]
        if anchors and placed:
            width, height = explicit_size(entry)

            def fallback(index, laid_width=None):
                return (intrinsic(entry, laid_width) if intrinsic else (0, 0))[index]

            left, w = axis(horizontal, width, lambda: fallback(0))
            top, h = axis(vertical, height, lambda: fallback(1, w))
            result = (left, top, w, h)
        visiting.discard(path)
        rects[path] = result
        return result

    for entry in entries:
        rect(entry["path"])
    return rects


def scroll_child_anchors(entry):
    """ScrollFrame:SetScrollChild puts the child's TOPLEFT at the scroll frame's, scrolled to the top."""
    if entry["path"].endswith(".scrollChild"):
        return [
            {"point": "TOPLEFT", "relativeTo": parent_path(entry["path"]), "relativePoint": "TOPLEFT", "x": 0, "y": 0}
        ]
    return []


def lua_rects(rects):
    """Rects for h.SetRects: {left, bottom, width, height} with y growing upwards, as the client's edges are."""
    return {
        path: [left, -(top + height), width, height]
        for path, rect in rects.items()
        if rect is not None
        for left, top, width, height in [rect]
    }


# ------------------------------------------------------------------------------------- the addon, headless


def run_scenes(inputs=None):
    """tests/scenes.lua's JSON; `inputs` feeds the layout pass (rects and map art) back to the harness."""
    with tempfile.TemporaryDirectory() as directory:
        command = ["luajit", "tests/scenes.lua"]
        if inputs is not None:
            path = Path(directory) / "input.json"
            path.write_text(json.dumps(inputs, sort_keys=True))
            command.append(str(path))
        result = subprocess.run(command, cwd=ROOT, capture_output=True, text=True, check=True)
    data = json.loads(result.stdout)
    if data["errors"]:
        sys.exit("tests/scenes.lua raised:\n" + "\n".join(data["errors"]))
    return data


def layout_pass(ui, scenes, known):
    """The client's layout, emulated: rects resolved from a run's dumps go back into the next run (h.SetRects runs
    the addon's OnSizeChanged, then the refresh re-lays the rows) until nothing moves, as the client settles over
    its first frames. The first run carries no input and must be tests/golden/layout.json exactly, so the scenes'
    fixture cannot drift from ui_spec's. Returns the settled run and each scene's rects."""
    data = run_scenes()
    golden = json.loads(GOLDEN.read_text())["layout"]
    if data["panel"]["layout"] != golden:
        sys.exit("tests/scenes.lua's panel differs from tests/golden/layout.json: update its fixture to ui_spec's")
    inputs = {"mapArt": {str(m): map_art_layer(ui, m) for m in sorted(set(data["mapArtRequests"]))}, "rects": {}}
    for _ in range(LAYOUT_PASSES):
        data = run_scenes(inputs)
        rects = {scene: layout_rects(ui, data[scene]["layout"], known) for scene in scenes}
        fed = {scene: lua_rects(rects[scene]) for scene in scenes}
        if fed == inputs["rects"]:
            return data, rects
        inputs["rects"] = fed
    sys.exit(f"the layout did not settle in {LAYOUT_PASSES} passes")


# ------------------------------------------------------------------------------------------ art and fonts

wm = None  # wowmock, imported by load_wowmock(): the resolver above and its tests need no Pillow.


def load_wowmock():
    global wm
    if wm is None:
        if not (WOWMOCK / "wowmock.py").is_file():
            sys.exit(f"wowmock.py not found in {WOWMOCK}; set WOWMOCK to the wow-mock-screenshots skill")
        sys.path.insert(0, str(WOWMOCK))
        import wowmock

        wm = wowmock
        # Blizzard_Fonts_Shared/FontStyles.xml: GameFontNormalMed3 (SystemFont_Med3, shadowed) and GameFontDisable;
        # TextStatusBarText is SystemFont_Outline_Small.
        wm.FONTS.setdefault("GameFontNormalMed3", wm.Font(wm.FRIZQT, 14, wm.NORMAL, (1, -1)))
        wm.FONTS.setdefault("GameFontDisable", wm.Font(wm.FRIZQT, 12, (0.5, 0.5, 0.5), (1, -1)))
        wm.FONTS.setdefault("TextStatusBarText", wm.Font(wm.FRIZQT, 10, wm.WHITE, None, True))
    return wm


def map_art_layer(ui, map_id):
    """What C_Map.GetMapArtLayers(map)[1] and GetMapArtLayerTextures(map, 1) return: the base layer's size and tile
    size, and its tiles' file IDs in row-major order."""
    art = wm.map_art_id(ui, map_id)
    style = ui.table("UiMapArt")[art]["UiMapArtStyleID"]
    layer = next(
        r for r in ui.table("UiMapArtStyleLayer").values() if r["UiMapArtStyleID"] == style and r["LayerIndex"] == "0"
    )
    tiles = sorted(
        (int(t["RowIndex"]), int(t["ColIndex"]), int(t["FileDataID"]))
        for t in ui.table("UiMapArtTile").values()
        if t["UiMapArtID"] == art and t["LayerIndex"] == "0"
    )
    keys = {
        "layerWidth": "LayerWidth",
        "layerHeight": "LayerHeight",
        "tileWidth": "TileWidth",
        "tileHeight": "TileHeight",
    }
    return {"layer": {k: int(layer[v]) for k, v in keys.items()}, "textures": [fdid for _, _, fdid in tiles]}


def font(name):
    if name not in wm.FONTS:
        sys.exit(f"font object {name} has no wowmock Font: add it in load_wowmock()")
    return wm.FONTS[name]


def texture(ui, ref):
    return ui.texture(int(ref) if isinstance(ref, (int, float)) else ref.replace("\\", "/").lower() + ".blp")


def fit_text(canvas, text, face, width, wrap):
    """A FontString's lines in `width`: one line cut with '...' under SetWordWrap(false), else word-wrapped."""
    if width <= 0 or canvas.text_width(text, face) <= width + 0.5:
        return [text]
    if wrap is False:
        while text and canvas.text_width(text + "...", face) > width:
            text = text[:-1]
        return [text + "..."]
    return wm.wrap_text(canvas, text, face, width)


# ------------------------------------------------------------------------------------ stock-template recipes

LAYERS = ("BACKGROUND", "BORDER", "ARTWORK", "OVERLAY", "HIGHLIGHT")


def input_border(canvas, x, y, w, h):
    """InputBoxVisualTemplate (Blizzard_SharedXML/Shared/InputBox/InputBoxTemplates.xml:43): common-search-border
    Left 8x20 at LEFT (-5, 0), Right 8x20 at RIGHT, Middle between them."""
    ui = canvas.ui
    top = y + (h - 20) / 2
    canvas.draw(ui.atlas("common-search-border-left"), x - 5, top, 8, 20)
    canvas.draw(ui.atlas("common-search-border-middle"), x + 3, top, w - 8 - 3, 20)
    canvas.draw(ui.atlas("common-search-border-right"), x + w - 8, top, 8, 20)


def draw_input_box(canvas, entry, rect, layer):
    """InputBoxVisualTemplate (InputBoxTemplates.xml:43) on its own, as the step count's box."""
    if layer == "BACKGROUND":
        input_border(canvas, *rect)


def draw_search_box(canvas, entry, rect, layer):
    """SearchBoxTemplate (InputBoxTemplates.xml:206) on InputBoxInstructionsTemplate (:177): the input border, the
    magnifier 10x10 at LEFT (1, -1); while empty the Instructions at TOPLEFT (16, 0) in GameFontDisableSmall
    coloured .35 (InputBoxInstructions_OnTextChanged), else the text in GameFontHighlightSmall at the TextInsets'
    left 16 and the clear button (17x17 at RIGHT (-3, 0), its icon 10x10 at TOPLEFT (3, -3), alpha .5)."""
    ui, (x, y, w, h), text = canvas.ui, rect, entry.get("text", "")
    if layer == "BACKGROUND":
        input_border(canvas, x, y, w, h)
    elif layer == "ARTWORK":
        if text:
            canvas.text(x + 16, y, text, font("GameFontHighlightSmall"), box_height=h)
        else:
            instructions = entry.get("stock", {}).get("Instructions", {}).get("text") or "Search"
            canvas.text(x + 16, y, instructions, font("GameFontDisableSmall"), (0.35, 0.35, 0.35), box_height=h)
    elif layer == "OVERLAY":
        canvas.draw(ui.atlas("common-search-magnifyingglass"), x + 1, y + (h - 10) / 2 + 1, 10, 10)
        if text:
            button_x, button_y = x + w - 3 - 17, y + (h - 17) / 2
            canvas.draw(ui.atlas("common-search-clearbutton"), button_x + 3, button_y + 3, 10, 10, (1, 1, 1, 0.5))


def draw_icon_dropdown(canvas, entry, rect, layer):
    """UIPanelIconDropdownButtonTemplate (Blizzard_SharedXML/Mainline/SharedUIPanelTemplates.xml:2312): 15x16, the
    questlog-icon-setting cog at its atlas size at CENTER."""
    if layer == "ARTWORK":
        icon = canvas.ui.atlas("questlog-icon-setting")
        x, y, w, h = rect
        canvas.draw(icon, x + (w - icon.width) / 2, y + (h - icon.height) / 2)


def draw_quest_log_border(canvas, entry, rect, layer):
    """QuestLogBorderFrameTemplate (Blizzard_UIPanels_Game/Mainline/QuestMapFrame.xml:287): TOPLEFT (-3, 7) to
    BOTTOMRIGHT (3, -6) of its parent at frameLevel 100; questlog-frame over all of it (BORDER) and
    questlog-frame-filigree at TOP (0, 1) (ARTWORK)."""
    ui, (x, y, w, h) = canvas.ui, rect
    if layer == "BORDER":
        canvas.draw(ui.atlas("questlog-frame"), x, y, w, h)
    elif layer == "ARTWORK":
        filigree = ui.atlas("questlog-frame-filigree")
        canvas.draw(filigree, x + (w - filigree.width) / 2, y - 1)


def draw_inset(canvas, entry, rect, layer):
    """InsetFrameTemplate (Mainline/SharedUIPanelTemplates.xml:389): Bg (UI-Background-Marble tiled, BACKGROUND -5)
    unless the addon hid it, and its NineSlice in NineSliceLayouts.InsetFrameTemplate above the frame's regions."""
    x, y, w, h = rect
    if layer == "BACKGROUND" and entry.get("stock", {}).get("Bg", {}).get("shown", True):
        marble = texture(canvas.ui, "Interface\\FrameGeneral\\UI-Background-Marble")
        wm.tiled(canvas, marble, x, y, w, h, marble.width / canvas.ui.scale, marble.height / canvas.ui.scale)
    elif layer == "FRAME":
        canvas.nine_slice(wm.INSET_FRAME_LAYOUT, x, y, w, h)


def backdrop_edges(canvas, x, y, w, h, file, edge, color):
    """Backdrop.lua's border from any edgeFile: eight edge-sized cells (left, right, top, bottom edges, then the four
    corners) with 1/128 horizontal and 1/16 vertical texel insets on the corners, the top and bottom edges the
    vertical strips turned; wowmock.tooltip_backdrop's recipe with the file and size free."""
    ui = canvas.ui
    corners = ((x, y), (x + w - edge, y), (x, y + h - edge), (x + w - edge, y + h - edge))
    for index, (left, top) in enumerate(corners, 4):
        piece = wm.crop_coords(file, index / 8 + 1 / 128, (index + 1) / 8 - 1 / 128, 1 / 16, 15 / 16)
        canvas.draw(piece, left, top, edge, edge, color)
    strips = (
        (x, y + edge, h - 2 * edge, False),
        (x + w - edge, y + edge, h - 2 * edge, False),
        (x + edge, y, w - 2 * edge, True),
        (x + edge, y + h - edge, w - 2 * edge, True),
    )
    for index, (left, top, length, horizontal) in enumerate(strips):
        if length <= 0:
            continue
        piece = wm.crop_coords(file, index / 8 + 1 / 128, (index + 1) / 8 - 1 / 128, 0, 1)
        if horizontal:
            piece = piece.transpose(wm.Image.Transpose.ROTATE_270)
        strip = ui.canvas(length if horizontal else edge, edge if horizontal else length)
        wm.tiled(strip, wm.tint(piece, color), 0, 0, strip.width, strip.height, edge, edge)
        canvas.paste(strip, left, top)


def draw_backdrop(canvas, entry, rect, layer):
    """BackdropTemplate (Blizzard_SharedXML/Backdrop.lua): the edgeFile at edgeSize in the border colour (no bgFile
    is set by the addon)."""
    backdrop = entry.get("backdrop")
    if layer == "BACKGROUND" and backdrop and backdrop.get("edgeFile"):
        color = tuple(entry.get("backdropBorderColor") or (1, 1, 1))
        file = texture(canvas.ui, backdrop["edgeFile"])
        backdrop_edges(canvas, *rect, file, backdrop["edgeSize"], (*color[:3], 1))


def button_font(entry, normal, highlight, disabled):
    if entry.get("disabled"):
        return font(disabled)
    if entry.get("highlightLocked"):
        return font(entry.get("highlightFont") or highlight)
    return font(entry.get("normalFont") or normal)


def draw_menu_button(canvas, entry, rect, layer):
    """UIMenuButtonStretchTemplate (Mainline/SharedUIPanelTemplates.xml:772): UI-Silver-Button-Up in nine pieces
    (12x6 corners), its text at CENTER (0, -1), and while the highlight is locked UI-Silver-Button-Highlight
    (texcoords 0-1 by .03-.7175) added over it."""
    ui, (x, y, w, h) = canvas.ui, rect
    if layer == "BACKGROUND":
        file = texture(ui, "Interface\\Buttons\\UI-Silver-Button-Up")
        columns = ((x, 12, 0, 0.09375), (x + 12, w - 24, 0.09375, 0.53125), (x + w - 12, 12, 0.53125, 0.625))
        rows = ((y, 6, 0, 0.1875), (y + 6, h - 12, 0.1875, 0.625), (y + h - 6, 6, 0.625, 0.8125))
        for left, width, u1, u2 in columns:
            for top, height, v1, v2 in rows:
                canvas.draw(wm.crop_coords(file, u1, u2, v1, v2), left, top, width, height)
    elif layer == "HIGHLIGHT" and entry.get("highlightLocked"):
        glow = wm.crop_coords(texture(ui, "Interface\\Buttons\\UI-Silver-Button-Highlight"), 0, 1, 0.03, 0.7175)
        canvas.draw(glow, x, y, w, h, blend="ADD")
    elif layer == "TEXT" and entry.get("text"):
        face = button_font(entry, "GameFontHighlightSmall", "GameFontHighlightSmall", "GameFontDisableSmall")
        canvas.text(x, y + 1, entry["text"], face, justify="CENTER", width=w, box_height=h)


def draw_panel_button(canvas, entry, rect, layer):
    """UIPanelButtonTemplate (Mainline/SharedUIPanelTemplates.xml:315, on UIPanelButtonNoTooltipTemplate,
    SecureUIPanelTemplates.xml:39): UI-Panel-Button-Up in three slices, 12-unit caps, texcoords to .6875 down
    (UI-Panel-Button-Disabled once disabled), GameFontNormal centred (GameFontDisable when disabled)."""
    x, y, w, h = rect
    if layer == "BACKGROUND":
        file = texture(
            canvas.ui, "Interface\\Buttons\\UI-Panel-Button-" + ("Disabled" if entry.get("disabled") else "Up")
        )
        canvas.draw(wm.crop_coords(file, 0, 0.09375, 0, 0.6875), x, y, 12, h)
        canvas.draw(wm.crop_coords(file, 0.09375, 0.53125, 0, 0.6875), x + 12, y, w - 24, h)
        canvas.draw(wm.crop_coords(file, 0.53125, 0.625, 0, 0.6875), x + w - 12, y, 12, h)
    elif layer == "TEXT" and entry.get("text"):
        face = button_font(entry, "GameFontNormal", "GameFontHighlight", "GameFontDisable")
        canvas.text(x, y, entry["text"], face, justify="CENTER", width=w, box_height=h)


def tab_size(ui):
    """LargeSideTabButtonTemplate's size (SidePanelTabButtonMixin, Mainline/SharedUIPanelTemplates.lua:309):
    common-sidetab's width by its height less 5."""
    art = ui.atlas("common-sidetab")
    return art.width, art.height - 5


def draw_side_tab(canvas, entry, rect, layer):
    """LargeSideTabButtonTemplate (Mainline/SharedUIPanelTemplates.xml:1008): common-sidetab at CENTER; the Icon at
    CENTER (-3, 0) masked by common-sidetab-mask, in the active or inactive atlas at its size when the tab has them
    (SidePanelTabButtonMixin:SetChecked), else as the addon set it; common-sidetab-selected over it while checked."""
    ui, (x, y, w, h) = canvas.ui, rect
    cx, cy = x + w / 2, y + h / 2

    def centred(name, dx=0, size=None):
        art = ui.atlas(name)
        width, height = size or (art.width, art.height)
        return art, cx + dx - width / 2, cy - height / 2, width, height

    if layer == "BACKGROUND":
        canvas.draw(*centred("common-sidetab"))
    elif layer == "ARTWORK":
        icon = entry.get("stock", {}).get("Icon", {})
        atlas = entry.get("activeAtlas" if entry.get("checked") else "inactiveAtlas") or icon.get("atlas")
        if atlas:
            art = canvas.ui.canvas(canvas.width, canvas.height)
            art.draw(*centred(atlas, -3, None if entry.get("activeAtlas") else icon.get("size")))
            mask, mx, my, mw, mh = centred("common-sidetab-mask")
            art.mask(mask.image, mx, my, mw, mh)
            canvas.paste(art, 0, 0)
    elif layer == "OVERLAY" and entry.get("checked"):
        canvas.draw(*centred("common-sidetab-selected"))


def draw_scroll_frame(canvas, entry, rect, layer, child_height=None):
    """ScrollFrameTemplate (SecureUIPanelTemplates.xml:24): ScrollFrame_OnLoad adds MinimalScrollBar
    (Mainline/ScrollDefine.lua:1), here where the addon anchored it; its thumb shows the visible share of the
    scroll child, scrolled to the top."""
    bar = entry.get("stock", {}).get("ScrollBar", {})
    if layer != "FRAME" or not bar.get("shown", True) or not bar.get("anchors"):
        return
    x, y, w, h = rect
    points = {}
    for point in bar["anchors"]:
        rx, ry = POINTS[point["relativePoint"]]
        points[point["point"]] = (x + rx * w + point["x"], y + ry * h - point["y"])
    left, top = points["TOPLEFT"]
    visible = min(1, h / child_height) if child_height else 1
    wm.minimal_scrollbar(canvas, left, top, points["BOTTOMLEFT"][1] - top, visible, 0)


# name: (draw(canvas, entry, rect, layer), its <Size> or None, its own <Anchors> or None, frameLevel)
STOCK = {
    "BackdropTemplate": (draw_backdrop, None, None, 0),
    "InputBoxVisualTemplate": (draw_input_box, None, None, 0),
    "InsetFrameTemplate": (draw_inset, None, None, 0),
    "LargeSideTabButtonTemplate": (draw_side_tab, tab_size, None, 0),
    "QuestLogBorderFrameTemplate": (
        draw_quest_log_border,
        None,
        [("TOPLEFT", -3, 7), ("BOTTOMRIGHT", 3, -6)],
        100,
    ),
    "ScrollFrameTemplate": (draw_scroll_frame, None, None, 0),
    "SearchBoxTemplate": (draw_search_box, None, None, 0),
    "UIMenuButtonStretchTemplate": (draw_menu_button, lambda ui: (40, 26), None, 0),
    "UIPanelButtonTemplate": (draw_panel_button, lambda ui: (40, 22), None, 0),
    "UIPanelIconDropdownButtonTemplate": (draw_icon_dropdown, lambda ui: (15, 16), None, 0),
}


def stock(entry):
    """The recipe for a dumped frame's stock template; one the script has none for fails the run (docs/plan.md
    §1.3), so a new template is drawn from its XML rather than left out."""
    name = entry.get("stockTemplate")
    if name is None:
        return None
    if name not in STOCK:
        sys.exit(f"{entry['path']}: no recipe for stock template {name}: add one to STOCK citing its Blizzard XML")
    return STOCK[name]


# ------------------------------------------------------------------------------------------ layout drawing


def layout_rects(ui, entries, known):
    measure = ui.canvas(1, 1)

    def intrinsic(entry, width=None):
        if entry["type"] == "FontString":
            text = entry.get("text") or ""
            face = font(entry["font"])
            lines = fit_text(measure, text, face, width, entry.get("wordWrap")) if text and width else [text]
            return (measure.text_width(text, face) if text else 0), face.height * len(lines)
        if entry.get("atlas"):
            art = ui.atlas(entry["atlas"])
            return art.width, art.height
        recipe = stock(entry)
        if recipe and recipe[1]:
            return recipe[1](ui)
        return 0, 0

    def defaults(entry):
        recipe = stock(entry)
        if recipe and recipe[2]:
            parent = parent_path(entry["path"])
            return [{"point": p, "relativePoint": p, "relativeTo": parent, "x": x, "y": y} for p, x, y in recipe[2]]
        return scroll_child_anchors(entry)

    return resolve(entries, known, intrinsic, defaults)


def draw_texture(canvas, entry, rect, alpha):
    ui, (x, y, w, h) = canvas.ui, rect
    target = ui.canvas(canvas.width, canvas.height) if entry.get("maskFile") else canvas
    blend = entry.get("alphaMode") or "BLEND"
    if entry.get("atlas"):
        target.draw(ui.atlas(entry["atlas"]), x, y, w, h, (1, 1, 1, alpha), blend)
    elif entry.get("file") is not None:
        image = texture(ui, entry["file"])
        if entry.get("texCoord"):
            image = wm.crop_coords(image, *entry["texCoord"])
        target.draw(image, x, y, w, h, (1, 1, 1, alpha), blend)
    elif entry.get("color"):
        r, g, b, a = entry["color"]
        target.fill(x, y, w, h, (r, g, b, a * alpha))
    if target is not canvas:
        target.mask(texture(ui, entry["maskFile"]), x, y, w, h)
        canvas.paste(target, 0, 0)


def draw_font_string(canvas, entry, rect, alpha):
    """A FontString in its rect: justifyH CENTER unless set, lines centred vertically, one line cut with '...'
    when word wrap is off."""
    text = entry.get("text")
    if not text:
        return
    x, y, w, h = rect
    face = font(entry["font"])
    lines = fit_text(canvas, text, face, w, entry.get("wordWrap"))
    top = y + (h - face.height * len(lines)) / 2
    target = canvas.ui.canvas(canvas.width, canvas.height) if alpha < 1 else canvas
    for index, line in enumerate(lines):
        target.text(x, top + index * face.height, line, face, justify=entry.get("justifyH") or "CENTER", width=w)
    if target is not canvas:
        target.image = wm.tint(target.image, (1, 1, 1, alpha))
        canvas.paste(target, 0, 0)


def draw_status_bar(canvas, entry, rect, alpha):
    """A StatusBar's fill: its texture cropped to the value's share (StatusBar's default fill style)."""
    bar = entry["statusBar"]
    low, high, value = bar.get("min", 0), bar.get("max", 1), bar.get("value", 0)
    if high <= low or value <= low:
        return
    x, y, w, h = rect
    r, g, b, a = bar.get("color") or (1, 1, 1, 1)
    share = min(1, (value - low) / (high - low))
    image = wm.crop_coords(texture(canvas.ui, bar["texture"]), 0, share, 0, 1)
    canvas.draw(image, x, y, w * share, h, (r, g, b, a * alpha))


REGIONS = ("Texture", "FontString", "MaskTexture")


class Layout:
    """Dumped frames drawn as the client composites them: each frame's regions by layer and sublevel (HIGHLIGHT only
    while locked), its stock template's art at its layers, then its children; a raised frameLevel (the quest log's
    border) after everything else; a scroll child clipped to its scroll frame; alpha multiplied down the tree."""

    def __init__(self, entries, rects, highlighted=()):
        self.rects = rects
        self.highlighted = set(highlighted)
        paths = {entry["path"] for entry in entries}
        self.children, self.roots = {}, []
        for entry in entries:
            parent = parent_path(entry["path"])
            while parent is not None and parent not in paths:
                parent = parent_path(parent)
            (self.children.setdefault(parent, []) if parent else self.roots).append(entry)

    def draw(self, canvas):
        self.raised = []
        for root in self.roots:
            self.frame(canvas, root, 1)
        for target, entry, alpha in self.raised:
            self.frame(target, entry, alpha, raised=True)

    def frame(self, canvas, entry, alpha, raised=False):
        recipe = stock(entry)
        if recipe and recipe[3] and not raised:
            self.raised.append((canvas, entry, alpha))
            return
        rect = self.rects.get(entry["path"])
        if rect is None:
            return
        alpha *= entry.get("alpha", 1)
        kids = self.children.get(entry["path"], [])
        regions = sorted(
            (kid for kid in kids if kid["type"] in ("Texture", "FontString")),
            key=lambda r: (LAYERS.index(r.get("layer") or "ARTWORK"), r.get("subLevel") or 0),
        )
        child = next((kid for kid in kids if kid["path"].endswith(".scrollChild")), None)
        child_height = self.rects[child["path"]][3] if child and self.rects.get(child["path"]) else None
        lit = entry.get("highlightLocked") or entry["path"] in self.highlighted

        def art(layer):
            if recipe:
                if recipe[0] is draw_scroll_frame:
                    draw_scroll_frame(canvas, entry, rect, layer, child_height)
                else:
                    recipe[0](canvas, entry, rect, layer)

        for layer in LAYERS:
            art(layer)
            if layer == "ARTWORK" and entry.get("statusBar"):
                draw_status_bar(canvas, entry, rect, alpha)
            if layer == "ARTWORK" and entry.get("normalAtlas"):
                canvas.draw(canvas.ui.atlas(entry["normalAtlas"]), *rect, (1, 1, 1, alpha))
            for region in regions:
                if (region.get("layer") or "ARTWORK") != layer or (layer == "HIGHLIGHT" and not lit):
                    continue
                region_rect = self.rects.get(region["path"])
                if region_rect is None:
                    continue
                region_alpha = alpha * region.get("alpha", 1)
                if region["type"] == "Texture":
                    draw_texture(canvas, region, region_rect, region_alpha)
                else:
                    draw_font_string(canvas, region, region_rect, region_alpha)
        art("TEXT")
        if not recipe and entry["type"] == "Button" and entry.get("text"):
            # A plain Button's text: its normal font object, centred (Button:SetText's FontString).
            face = button_font(entry, "GameFontNormal", "GameFontHighlight", "GameFontDisable")
            canvas.text(rect[0], rect[1], entry["text"], face, justify="CENTER", width=rect[2], box_height=rect[3])
        art("FRAME")
        for kid in kids:
            if kid["type"] in REGIONS:
                continue
            if kid is child:
                # Drawn in place (an ADD texture needs what is under it), then everything outside the scroll
                # frame put back as it was.
                box = tuple(canvas.px(v) for v in (rect[0], rect[1], rect[0] + rect[2], rect[1] + rect[3]))
                before = canvas.image.copy()
                self.frame(canvas, kid, alpha)
                before.paste(canvas.image.crop(box), box[:2])
                canvas.image = before
            else:
                self.frame(canvas, kid, alpha)


# ---------------------------------------------------------------------------------------- the stock frames

QUEST_LOG_WIDTH = 333  # QuestLogOwnerMixin (Blizzard_WorldMap/Blizzard_WorldMap.lua:166): the side panel's width
MAP_NAV = ("World", "Kalimdor", "The Barrens")  # the nav bar down to the fixture's zone, uiMap 1413
PLAYER_ARROW = 27  # the player pin's arrow, as wowmock's NOTES measure it against a capture
GREEN = (0.1, 1.0, 0.1)  # GREEN_FONT_COLOR, what GameTooltip_AddInstructionLine uses


def map_frame(ui, map_image, quest_log, on_map=None):
    """WorldMapFrame minimized as wowmock.world_map_frame draws it, with the quest log shown or not. Shown, the frame
    is QUEST_LOG_WIDTH wider (QuestLogOwnerMixin:SetDisplayState), the canvas container keeps its width (the title
    spacer's BOTTOMRIGHT at TOPRIGHT (-3 - 333, -67)), QuestMapFrame fills TOPRIGHT (-3, -25) to BOTTOMRIGHT (-3,
    3) (Blizzard_WorldMap.lua:1290) and the side panel toggle shows QuestCollapse-Hide-Up. `on_map(canvas, rects)`
    draws on the map before the frame's chrome, clipped to the container. The canvas leaves room on the right for
    the quest log's side tabs. Returns the canvas and rects in its UI units, as world_map_frame's plus "quests"."""
    m = wm.WORLD_MAP_MARGIN
    w, h = wm.WORLD_MAP_WIDTH + (QUEST_LOG_WIDTH if quest_log else 0), wm.WORLD_MAP_HEIGHT
    canvas = ui.canvas(w + 2 * m + (64 if quest_log else 0), h + 2 * m)
    rock = ui.texture("interface/framegeneral/ui-background-rock.blp")
    wm.tiled(canvas, rock, m + 2, m + 21, w - 4, h - 23, rock.width / ui.scale, rock.height / ui.scale)
    container = (m + 2, m + wm.WORLD_MAP_SPACER, wm.WORLD_MAP_WIDTH - 5, h - 2 - wm.WORLD_MAP_SPACER)
    cx, cy, cw, ch = container
    scale = min(cw / map_image.width, ch / map_image.height)
    mw, mh = map_image.width * scale, map_image.height * scale
    mx, my = cx + (cw - mw) / 2, cy + (ch - mh) / 2
    rects = {"frame": (m, m, w, h), "container": container, "map": (mx, my, mw, mh), "scale": scale}
    rects["quests"] = (m + w - 3 - 330, m + 25, 330, h - 25 - 3)
    art = ui.canvas(canvas.width, canvas.height)
    art.draw(map_image, mx, my, mw, mh)
    if on_map:
        on_map(art, rects)
    keep = wm.Image.new("L", art.image.size, 0)
    keep.paste(255, tuple(canvas.px(v) for v in (cx, cy, cx + cw, cy + ch)))
    art.image.putalpha(wm.ImageChops.multiply(art.image.getchannel("A"), keep))
    canvas.paste(art, 0, 0)
    canvas.draw(ui.atlas("_UI-Frame-InnerTopTile"), m + 2, m + 63, cw, 3)
    nav_x, nav_y = m + 2 + 64, m + 25
    nav_w = (m + wm.WORLD_MAP_WIDTH - 3 + wm.WORLD_MAP_NAVBAR_X_OFFSET) - nav_x
    nav_h = (m + wm.WORLD_MAP_SPACER - 9) - nav_y
    wm.nav_bar(canvas, nav_x, nav_y, nav_w, nav_h, MAP_NAV, MAP_NAV[1:])
    options_x, options_y = nav_x + nav_w + 10, nav_y + nav_h / 2 - 16 + 2
    canvas.draw(ui.atlas("common-dropdown-a-button"), options_x + 4, options_y + 6)
    toggle_x, toggle_y = cx + cw - 2 - 32, cy + ch - 1 - 32
    corner = ui.atlas("MapCornerShadow-Right")
    canvas.draw(corner, toggle_x + 32 + 2 - corner.width, toggle_y + 32 + 1 - corner.height)
    canvas.draw(ui.atlas("QuestCollapse-Hide-Up" if quest_log else "QuestCollapse-Show-Up"), toggle_x, toggle_y, 32, 32)
    canvas.nine_slice(wm.camelot_layout(wm.PORTRAIT_FRAME_LAYOUT), m, m, w, h)
    portrait = ui.canvas(canvas.width, canvas.height)
    portrait.draw(ui.texture("interface/questframe/ui-questlog-bookicon.blp"), m - 5, m - 7, 62, 62)
    portrait.mask(ui.texture("interface/characterframe/tempportraitalphamask.blp"), m - 3, m - 7, 58, 58)
    canvas.paste(portrait, 0, 0)
    canvas.text(m + 58, m + 1 + 5, "Map & Quest Log", wm.FONTS["GameFontNormal"], justify="CENTER", width=w - 58 - 24)
    close_x = m + w + 1 - 24
    canvas.draw(ui.atlas("RedButton-Exit"), close_x, m, 24, 24)
    canvas.draw(ui.atlas("RedButton-Expand"), close_x - 1 - 24, m, 24, 24)
    return canvas, rects


def map_point(rects, x, y):
    mx, my, mw, mh = rects["map"]
    return mx + x * mw, my + y * mh


def draw_pins(canvas, rects, pins, hovered=None):
    """The addon's map pins from their dumps, each centred on its map position at 26 units (SetScalingLimits gives
    1.0 at the map's minimum zoom); `hovered` (an index into pins) draws that pin's highlight."""
    for index, pin in enumerate(pins):
        root = pin["layout"][0]
        cx, cy = map_point(rects, pin["x"], pin["y"])
        width, height = root.get("size") or (26, 26)
        known = {root["path"]: (cx - width / 2, cy - height / 2, width, height)}
        placed = layout_rects(canvas.ui, pin["layout"], known)
        Layout(pin["layout"], placed, [root["path"]] if index == hovered else ()).draw(canvas)


def draw_player(canvas, rects, player):
    arrow = canvas.ui.atlas("UI-WorldMapArrow")
    cx, cy = map_point(rects, player["x"], player["y"])
    canvas.draw(arrow, cx - PLAYER_ARROW / 2, cy - PLAYER_ARROW / 2, PLAYER_ARROW, PLAYER_ARROW)


def crop(canvas, x, y, w, h):
    out = canvas.ui.canvas(w, h)
    out.paste(canvas, -x, -y)
    return out


def known_frames(rects):
    """The stock frames the addon anchors to, from the drawn world map."""
    quests = rects["quests"]
    return {"WorldMapFrame": rects["frame"], "QuestMapFrame": quests, "QuestMapFrame.ContentsAnchor": quests}


# ---------------------------------------------------------------------------------------------- the scenes

PLAYER = {"x": 0.52, "y": 0.30}  # tests/harness.lua's player position in The Barrens


def quest_log(ui, data, rects, scene, pins=()):
    """The world map with the quest log open on the guide's tab: `scene`'s panel dump in the quest pane, the tabs,
    and the map's pins."""
    art = wm.map_art(ui, data["panel"]["map"])

    def on_map(canvas, frame_rects):
        draw_pins(canvas, frame_rects, pins)
        draw_player(canvas, frame_rects, PLAYER)

    canvas, frame = map_frame(ui, art, True, on_map)
    Layout(data[scene]["layout"], rects[scene]).draw(canvas)
    tabs = [entry for dump in data[scene]["tabs"] for entry in dump]
    Layout(tabs, layout_rects(ui, tabs, known_frames(frame))).draw(canvas)
    return canvas, frame


# ------------------------------------------------------------------------------ Shortest Path's route (map scene)

# The Shortest Path Forever build the map scene draws (the same sha tests/contract_spec.lua pins); its geometry is
# SPF's own Path.FindSync, run by LuaJIT in an extracted copy (docs/plan.md §1.3).
SPF_SHA = "39d9a986d423557ab13039b45732d0c9dd12bf02"
SPF_TARBALL = f"https://codeload.github.com/cjber/shortest-path-forever/tar.gz/{SPF_SHA}"
SPF_CACHE = ROOT / "tools/.cache" / f"spf-{SPF_SHA}"
# Route.lua: THICKNESS 2 over UNDER_THICKNESS 4 at UNDER_ALPHA .5; walks are DOT 4 breadcrumbs every SPACING 9, each
# over a dark dot RIM 1 wider; the walk colour is NORMAL_FONT_COLOR.
SPF_DOT, SPF_RIM, SPF_SPACING, SPF_UNDER = 4, 1, 9, (0.04, 0.04, 0.04, 0.5)

SPF_PROGRAM = r"""
local ns = {}
for _, name in ipairs({ "Data/Routes", "Data/Transports", "Data/Portals", "Data/Taxi", "Model", "Path", "Planner" }) do
	assert(loadfile(name .. ".lua"))("ShortestPathForever", ns)
end
local walks = {}
for index, leg in ipairs(LEGS) do
	assert(loadfile("tools/load_nav.lua"))(leg.map)
	local points, why = ns.Path.FindSync(leg.map, leg.from, leg.to)
	assert(points, tostring(why))
	local out = {}
	for i, point in ipairs(points) do
		out[i] = string.format("[%.3f,%.3f]", point.x, point.y)
	end
	walks[index] = "[" .. table.concat(out, ",") .. "]"
end
print("[" .. table.concat(walks, ",") .. "]")
"""


def spf_sources():
    """SPF_CACHE, extracted from a local clone ($SPF, else a sibling of this checkout or of its main worktree) with
    `git archive`, else from GitHub's tarball of the sha."""
    if (SPF_CACHE / "Path.lua").is_file():
        return SPF_CACHE
    import io
    import tarfile
    import urllib.request

    common = subprocess.run(["git", "rev-parse", "--git-common-dir"], cwd=ROOT, capture_output=True, text=True)
    candidates = [os.environ.get("SPF"), ROOT.parent / "shortest-path-forever"]
    if common.returncode == 0:
        candidates.append((ROOT / common.stdout.strip()).resolve().parent.parent / "shortest-path-forever")
    archive = None
    for candidate in filter(None, candidates):
        result = subprocess.run(["git", "-C", str(candidate), "archive", SPF_SHA], capture_output=True)
        if result.returncode == 0:
            archive, strip = result.stdout, 0
            break
    if archive is None:
        with urllib.request.urlopen(SPF_TARBALL, timeout=300) as response:
            archive, strip = response.read(), 1
    staging = SPF_CACHE.with_name(SPF_CACHE.name + ".tmp")
    with tarfile.open(fileobj=io.BytesIO(archive)) as tar:
        members = []
        for member in tar.getmembers():
            parts = Path(member.name).parts[strip:]
            if parts:
                member.name = str(Path(*parts))
                members.append(member)
        tar.extractall(staging, members, filter="data")
    staging.rename(SPF_CACHE)
    return SPF_CACHE


def assignment(ui, map_id):
    """The UiMapAssignment row placing a uiMap on its world map, as SPF's own screenshots.py picks it."""
    rows = [
        r
        for r in ui.table("UiMapAssignment").values()
        if r["UiMapID"] == str(map_id) and r["WMODoodadPlacementID"] == "0"
    ]
    return min(rows, key=lambda row: (int(row["OrderIndex"]), int(row["ID"])))


def world_point(ui, map_id, x, y):
    """A uiMap position in world coordinates (x north, y west), inverting SPF's projection; ns.WorldPoint needs the
    client's C_Map."""
    r = assignment(ui, map_id)
    nx = (x - float(r["UiMin_0"])) / (float(r["UiMax_0"]) - float(r["UiMin_0"]))
    ny = (y - float(r["UiMin_1"])) / (float(r["UiMax_1"]) - float(r["UiMin_1"]))
    west = float(r["Region_4"]) - nx * (float(r["Region_4"]) - float(r["Region_1"]))
    north = float(r["Region_3"]) - ny * (float(r["Region_3"]) - float(r["Region_0"]))
    return {"map": int(r["MapID"]), "x": north, "y": west}


def map_position(ui, map_id, point):
    r = assignment(ui, map_id)
    nx = (float(r["Region_4"]) - point[1]) / (float(r["Region_4"]) - float(r["Region_1"]))
    ny = (float(r["Region_3"]) - point[0]) / (float(r["Region_3"]) - float(r["Region_0"]))
    return tuple(
        float(r[f"UiMin_{i}"]) + n * (float(r[f"UiMax_{i}"]) - float(r[f"UiMin_{i}"])) for i, n in enumerate((nx, ny))
    )


def spf_walks(ui, legs):
    """Path.FindSync's points for each (uiMap, from, to) leg, in world coordinates."""
    root = spf_sources()
    entries = []
    for map_id, a, b in legs:
        start, goal = world_point(ui, map_id, *a), world_point(ui, map_id, *b)
        assert start["map"] == goal["map"]
        entries.append(
            f"{{ map = {start['map']}, from = {{ x = {start['x']:.4f}, y = {start['y']:.4f} }}, "
            f"to = {{ x = {goal['x']:.4f}, y = {goal['y']:.4f} }} }}"
        )
    program = "local LEGS = { " + ", ".join(entries) + " }\n" + SPF_PROGRAM
    result = subprocess.run(["luajit", "-"], input=program, text=True, cwd=root, capture_output=True)
    if result.returncode:
        sys.exit("Shortest Path's Path.FindSync failed:\n" + result.stderr)
    return json.loads(result.stdout)


def breadcrumbs(canvas, rects, lines):
    """Route.lua's walk: breadcrumbs every SPF_SPACING along each polyline (normalised map points), the distance
    carried across its bends, each dot over a larger dark rim, every rim beneath every dot (ARTWORK -1)."""
    import math

    dots = []
    for line in lines:
        points = [map_point(rects, x, y) for x, y in line]
        walked = 0.0
        for (ax, ay), (bx, by) in zip(points, points[1:], strict=False):
            length = math.hypot(bx - ax, by - ay)
            distance = math.ceil(walked / SPF_SPACING) * SPF_SPACING - walked
            while length and distance <= length:
                dots.append((ax + (bx - ax) * distance / length, ay + (by - ay) * distance / length))
                distance += SPF_SPACING
            walked += length
    k = canvas.ui.scale
    for radius, color in ((SPF_DOT / 2 + SPF_RIM, SPF_UNDER), (SPF_DOT / 2, (*wm.NORMAL, 1))):
        layer = wm.Image.new("RGBA", canvas.image.size)
        draw = wm.ImageDraw.Draw(layer)
        for x, y in dots:
            draw.ellipse(
                ((x - radius) * k, (y - radius) * k, (x + radius) * k, (y + radius) * k), fill=wm.rgba255(color)
            )
        canvas.image.alpha_composite(layer)


def goal_pins(canvas, rects, stops):
    """SPF's numbered stop pins (Map.xml:23, GoalPinMixin:OnAcquired): 26x26, a black .75 disc 22x22 cut round by
    TempPortraitAlphaMask, the adventureguide-ring over it and services-number-N 22x25 at the centre."""
    ui = canvas.ui
    for number, stop in enumerate(stops, 1):
        cx, cy = map_point(rects, stop["x"], stop["y"])
        disc = ui.canvas(canvas.width, canvas.height)
        disc.fill(cx - 11, cy - 11, 22, 22, (0, 0, 0, 0.75))
        disc.mask(ui.texture("interface/characterframe/tempportraitalphamask.blp"), cx - 11, cy - 11, 22, 22)
        canvas.paste(disc, 0, 0)
        canvas.draw(ui.atlas("adventureguide-ring"), cx - 13, cy - 13, 26, 26)
        canvas.draw(ui.atlas(f"services-number-{number}"), cx - 11, cy - 12.5, 22, 25)


def shortest_path(ui, data):
    """The map while Shortest Path guides the route AGF handed it: the current leg (player to stop 1) walked with
    Path.FindSync, the later stops joined by the straight preview walk (Route.lua's `preview` path), the numbered
    stops, and the player."""
    stops, map_id = data["map"]["stops"], data["panel"]["map"]
    player = data["map"]["player"]
    (walk,) = spf_walks(ui, [(map_id, (player["x"], player["y"]), (stops[0]["x"], stops[0]["y"]))])
    current = [map_position(ui, map_id, point) for point in walk]
    preview = [(stop["x"], stop["y"]) for stop in stops]

    def on_map(canvas, rects):
        breadcrumbs(canvas, rects, [current, preview])
        goal_pins(canvas, rects, stops)
        draw_player(canvas, rects, player)

    canvas, _ = map_frame(ui, wm.map_art(ui, map_id), False, on_map)
    return canvas, len(walk)


def render(out):
    """Every scene into `out`; returns the written paths."""
    load_wowmock()
    version = importlib.metadata.version("pillow")
    if version != PILLOW:
        print(f"warning: Pillow {version}, not the pinned {PILLOW}: the PNGs may not match byte for byte")
    ui = wm.Ui(scale=SCALE)
    _, frame = map_frame(ui, wm.Image.new("RGBA", (1002, 668)), True)
    data, rects = layout_pass(ui, ("panel", "search"), known_frames(frame))
    images = {}

    canvas, _ = quest_log(ui, data, rects, "panel", data["panel"]["pins"])
    images["panel"] = wm.scene(ui, [(canvas, 0, 0)])

    canvas, frame = quest_log(ui, data, rects, "search", data["panel"]["pins"])
    qx, qy, qw, qh = frame["quests"]
    images["search"] = wm.scene(ui, [(crop(canvas, qx - 3, qy - 30, qw + 3 + 64, qh + 30 + 22), 0, 0)])

    art = wm.map_art(ui, data["panel"]["map"])
    canvas, _ = shortest_path(ui, data)
    images["map"] = wm.scene(ui, [(canvas, 0, 0)])

    hovered = data["tooltip"]["hovered"] - 1

    def hover(canvas, frame_rects):
        draw_pins(canvas, frame_rects, data["tooltip"]["pins"], hovered)
        draw_player(canvas, frame_rects, PLAYER)

    canvas, frame = map_frame(ui, art, False, hover)
    colours = {"title": wm.WHITE, "highlight": wm.WHITE, "normal": wm.NORMAL, "instruction": GREEN}
    tip = wm.tooltip(ui, [wm.TooltipLine(line["text"], colours[line["kind"]]) for line in data["tooltip"]["lines"]])
    pin = data["tooltip"]["pins"][hovered]
    px, py = map_point(frame, pin["x"], pin["y"])
    # ANCHOR_RIGHT: the tooltip's BOTTOMLEFT at the pin's TOPRIGHT.
    tip_x, tip_y = px + 13, py - 13 - tip.height
    left, top = px - 120, tip_y - 30
    shot = crop(canvas, left, top, tip_x + tip.width + 40 - left, py + 90 - top)
    images["tooltip"] = wm.scene(ui, [(shot, 0, 0), (tip, tip_x - left, tip_y - top)])

    tracker = data["tracker"]
    blocks = [wm.TrackerBlock(block["header"], block["lines"]) for block in tracker["blocks"]]
    canvas, tracked = wm.objective_tracker(ui, [wm.TrackerModule(tracker["header"], blocks)])
    images["tracker"] = wm.scene(ui, [(canvas, 0, 0)])

    kinds = {"title": wm.MenuTitle, "button": wm.MenuButton}
    menu, menu_rects = wm.context_menu(ui, [kinds[entry["kind"]](entry["text"]) for entry in data["menu"]])
    bx, by, _, _ = tracked["blocks"][0]
    # A right-click on the block header: Blizzard_Menu opens the menu with its TOPLEFT at the cursor.
    fx, fy, _, _ = menu_rects["menu"]
    images["menu"] = wm.scene(ui, [(canvas, 0, 0), (menu, bx + 60 - fx, by + 8 - fy)])

    OUT.mkdir(parents=True, exist_ok=True)
    written = []
    for name, image in images.items():
        path = out / f"{name}.png"
        image.save(path)
        written.append(path)
    return written


def main():
    for path in render(OUT):
        print(path.relative_to(ROOT))


if __name__ == "__main__":
    main()
