#!/usr/bin/env python3
"""Render docs/screenshots/*.png and demo.gif from what the addon draws headlessly, with the WoW: Forever
client's own art.

    FOREVER_CORE=/path/to/forever-core python3 tools/screenshots.py

WFA-9: the store and README screenshots come from this script, never from a capture. The panel is
tests/golden/layout.json; every other scene is read from the addon by tests/scenes.lua through
the same harness, so no AGF text or layout is retyped here. Stock templates produce no regions headlessly, so each
one the dumps name has a recipe in screenshots_stock.py citing its Blizzard XML; an unknown stockTemplate fails the run.
The frames around the addon (the world map, the tracker, the tooltip and the menu) are wowmock's
(the forever-core shared renderer), drawn from Blizzard's own layout numbers (WFA-4: the stock look).
Shortest Path's walked route and the steps it plans are its own pinned sources (screenshots_spf.py).

UI art and fonts come from wago.tools for UI_ART_BUILD; generated map and content tables come from DATA_BUILD.
They are cached under ~/.cache/wowmock. The game client is never started or read. Two runs give byte-identical PNGs
with this environment (pip is not installed on the machine that pinned it, so the freeze is importlib.metadata's,
limited to what the script imports):

    Python 3.14.7, pillow==12.3.0
    wowmock.py        503b024c0c2aae953044fd2e041691809a9e55109a6b54b31005e32cc52bd57e
    fonts/frizqt__.ttf (fdid 615960)  73de74d5d63690f29c7f97a9225edc8bd6f89e5103806af3714e4d7bfb9474e9
    fonts/arialn.ttf   (fdid 615958)  bd31d0cf2e5a1a3a9074e98ebe4964c641121e9e660f31627614c4acb6c89c1c
    fonts/morpheus.ttf (fdid 615962)  0df28ca8a5e6fc14ee53de7b7f8ed7cf128108766b97d13d5ba60296cb517fd7

Pillow and wowmock are imported inside the render functions only: CI runs the resolver's tests without Pillow.
"""

import importlib.metadata
import io
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

import screenshots_art as drawing
from gen_quests import BUILD as DATA_BUILD
from screenshots_art import draw_font_string, draw_texture, fit_text, font, load_wowmock
from screenshots_resolver import effective_scales, lua_rects, map_point, parent_path, resolve, scroll_child_anchors
from screenshots_spf import (
    SPF_SHA,
    assignment,
    breadcrumbs,
    goal_pins,
    map_position,
    marker,
    spf_itinerary,
    spf_walk,
    stop_groups,
)
from screenshots_stock import LAYERS, button_font, draw_scroll_frame, stock

ROOT = Path(__file__).resolve().parent.parent
FOREVER_CORE = Path(os.environ.get("FOREVER_CORE", ROOT.parent / "forever-core")).expanduser()
OUT = ROOT / "docs/screenshots"
GOLDEN = ROOT / "tests/golden/layout.json"
PILLOW = "12.3.0"
# Match the owner's 960 px / 800 UI-unit window. FreeType BASIC advances are pixel-hinted:
# measuring at 2x then shrinking gives different widths and hides client wrapping/truncation.
SCALE = 1.2
LAYOUT_PASSES = 8
UI_ART_BUILD = "1.60.1.70124"

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


def two_places(value):
    """`value` with every number as tests/golden/layout.json writes it ("%.2f"), for comparing a run with it."""
    if isinstance(value, dict):
        return {key: two_places(item) for key, item in value.items()}
    if isinstance(value, list):
        return [two_places(item) for item in value]
    if isinstance(value, float | int) and not isinstance(value, bool):
        return float(f"{value:.2f}")
    return value


def layout_pass(ui, content_ui, scenes, known):
    """The client's layout, emulated: rects resolved from a run's dumps go back into the next run (h.SetRects runs
    the addon's OnSizeChanged, then the refresh re-lays the rows) until nothing moves, as the client settles over
    its first frames. The first run carries no input and must be tests/golden/layout.json exactly, so the scenes'
    fixture cannot drift from ui_spec's. Returns the settled run and each scene's rects."""
    data = run_scenes()
    golden = json.loads(GOLDEN.read_text())["layout"]
    if two_places(data["panel"]["layout"]) != golden:
        sys.exit("tests/scenes.lua's panel differs from tests/golden/layout.json: update its fixture to ui_spec's")
    inputs = {"rects": {}, "mapArt": map_tiles(content_ui)}
    for _ in range(LAYOUT_PASSES):
        data = run_scenes(inputs)
        rects = {
            scene: layout_rects(
                ui,
                data[scene]["layout"],
                known
                | ({data[scene]["layout"][0]["path"]: (50, 10, 300, 101)} if scene == "story_complete" else {})
                | ({data[scene]["layout"][0]["path"]: (0, 0, 454, 294)} if scene == "guide_setup" else {}),
            )
            for scene in scenes
        }
        fed = {
            scene: lua_rects(rects[scene], text_measures(ui, data[scene]["layout"], rects[scene])) for scene in scenes
        }
        if fed == inputs["rects"]:
            return data, rects
        inputs["rects"] = fed
    sys.exit(f"the layout did not settle in {LAYOUT_PASSES} passes")


def map_tiles(ui):
    """C_Map.GetMapArtLayerTextures(uiMap, 1) for every zone Data/ZoneArt.lua has: its base art's UiMapArtTile files,
    row-major, as the client gives them; the harness makes some up without."""
    zones = re.findall(r"^\t\[(\d+)\] = \{$", (ROOT / "Data/ZoneArt.lua").read_text(), re.M)
    tiles = {}
    for zone in zones:
        art = drawing.wm.map_art_id(ui, int(zone))
        rows = [r for r in ui.table("UiMapArtTile").values() if r["UiMapArtID"] == art and r["LayerIndex"] == "0"]
        rows.sort(key=lambda r: (int(r["RowIndex"]), int(r["ColIndex"])))
        tiles[zone] = [int(r["FileDataID"]) for r in rows]
    return tiles


# ------------------------------------------------------------------------------------------ layout drawing


def layout_rects(ui, entries, known):
    measure = ui.canvas(1, 1)

    def intrinsic(entry, width=None):
        if entry["type"] == "FontString":
            text = entry.get("text") or ""
            face = font(entry["font"])
            wrap, most = entry.get("wordWrap"), entry.get("maxLines")
            lines = fit_text(measure, text, face, width, wrap, most) if text and width else [text]
            return (measure.text_width(text, face) if text else 0), face.height * len(lines) + (
                entry.get("spacing") or 0
            ) * (len(lines) - 1)
        if entry.get("atlas"):
            art = ui.atlas(entry["atlas"])
            return art.width, art.height
        recipe = stock(entry)
        if recipe and recipe[1]:
            return recipe[1](ui, entry)
        return 0, 0

    def defaults(entry):
        recipe = stock(entry)
        if recipe and recipe[2]:
            parent = parent_path(entry["path"])
            return [{"point": p, "relativePoint": p, "relativeTo": parent, "x": x, "y": y} for p, x, y in recipe[2]]
        return scroll_child_anchors(entry)

    return resolve(entries, known, intrinsic, defaults)


def text_measures(ui, entries, rects):
    """Each font string's text width in the client's font, whatever width it is laid out in, and the lines it wraps
    to in the width it is laid out in."""
    measure = ui.canvas(1, 1)
    measures = {}
    for entry in entries:
        if entry["type"] == "FontString" and entry.get("text"):
            face = font(entry["font"])
            rect = rects.get(entry["path"])
            width = rect[2] if rect else 0
            lines = fit_text(measure, entry["text"], face, width, entry.get("wordWrap"), entry.get("maxLines"))
            measures[entry["path"]] = [measure.text_width(entry["text"], face), len(lines)]
    return measures


REGIONS = ("Texture", "FontString", "MaskTexture")


class Layout:
    """Dumped frames drawn as the client composites them: each frame's regions by layer and sublevel (HIGHLIGHT only
    while locked), its stock template's art at its layers, then its children; a raised frameLevel (the quest log's
    border) after everything else; a scroll child clipped to its scroll frame; alpha multiplied down the tree."""

    def __init__(self, entries, rects, highlighted=()):
        self.rects = rects
        self.highlighted = set(highlighted)
        self.scales = effective_scales(entries)
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
        # A texture's AddMaskTexture: the frame's MaskTexture (ZoneIcon.lua has one per frame).
        masks = [kid for kid in kids if kid["type"] == "MaskTexture" and self.rects.get(kid["path"])]
        mask = (masks[0], self.rects[masks[0]["path"]]) if masks else None
        if entry.get("clipsChildren"):
            # SetClipsChildren: what the frame and its children draw outside its rect is put back as it was.
            box = tuple(canvas.px(v) for v in (rect[0], rect[1], rect[0] + rect[2], rect[1] + rect[3]))
            before = canvas.image.copy()

        def art(layer):
            if recipe:
                if recipe[0] is draw_scroll_frame:
                    draw_scroll_frame(canvas, entry, rect, layer, child_height)
                else:
                    recipe[0](canvas, entry, rect, layer)

        for layer in LAYERS:
            art(layer)
            if layer == "ARTWORK" and entry.get("normalAtlas"):
                canvas.draw(canvas.ui.atlas(entry["normalAtlas"]), *rect, (1, 1, 1, alpha))
            if layer == "HIGHLIGHT" and lit and entry.get("highlightAtlas"):
                # Button:SetHighlightAtlas's texture: the button's size, blended ADD (the client's default).
                canvas.draw(canvas.ui.atlas(entry["highlightAtlas"]), *rect, (1, 1, 1, alpha), "ADD")
            for region in regions:
                if (region.get("layer") or "ARTWORK") != layer or (layer == "HIGHLIGHT" and not lit):
                    continue
                region_rect = self.rects.get(region["path"])
                if region_rect is None:
                    continue
                region_alpha = alpha * region.get("alpha", 1)
                if region["type"] == "Texture":
                    masked = mask if region.get("masked") else None
                    draw_texture(canvas, region, region_rect, region_alpha, self.scales[region["path"]], masked)
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
        art("AFTER")
        if entry.get("clipsChildren"):
            before.paste(canvas.image.crop(box), box[:2])
            canvas.image = before


# ---------------------------------------------------------------------------------------- the stock frames

QUEST_LOG_WIDTH = 333  # QuestLogOwnerMixin (Blizzard_WorldMap/Blizzard_WorldMap.lua:166): the side panel's width
MAP_NAV = ("World", "Kalimdor", "The Barrens")  # the nav bar down to the fixture's zone, uiMap 1413
PLAYER_ARROW = 27  # the player pin's arrow, as wowmock's NOTES measure it against a capture
GREEN = (0.1, 1.0, 0.1)  # GREEN_FONT_COLOR, what GameTooltip_AddInstructionLine uses


def explored_art(content_ui, map_id):
    """A uiMap's base art with every WorldMapOverlay drawn, as a character who has explored the whole zone sees it;
    the base art alone is the unexplored parchment."""
    art = drawing.wm.map_art(content_ui, map_id)
    for overlay in drawing.wm.map_overlays(content_ui, map_id):
        drawing.wm.draw_overlay(
            content_ui, art, overlay.offset_x, overlay.offset_y, overlay.width, overlay.height, overlay.tiles
        )
    return art


def map_frame(ui, map_image, quest_log, on_map=None):
    """WorldMapFrame minimized as wowmock.world_map_frame draws it, with the quest log shown or not. Shown, the frame
    is QUEST_LOG_WIDTH wider (QuestLogOwnerMixin:SetDisplayState), the canvas container keeps its width (the title
    spacer's BOTTOMRIGHT at TOPRIGHT (-3 - 333, -67)), QuestMapFrame fills TOPRIGHT (-3, -25) to BOTTOMRIGHT (-3,
    3) (Blizzard_WorldMap.lua:1290) and the side panel toggle shows QuestCollapse-Hide-Up. `on_map(canvas, rects)`
    draws on the map before the frame's chrome, clipped to the container. The canvas leaves room on the right for
    the quest log's side tabs. Returns the canvas and rects in its UI units, as world_map_frame's plus "quests"."""
    m = drawing.wm.WORLD_MAP_MARGIN
    w, h = drawing.wm.WORLD_MAP_WIDTH + (QUEST_LOG_WIDTH if quest_log else 0), drawing.wm.WORLD_MAP_HEIGHT
    canvas = ui.canvas(w + 2 * m + (64 if quest_log else 0), h + 2 * m)
    rock = ui.texture("interface/framegeneral/ui-background-rock.blp")
    drawing.wm.tiled(canvas, rock, m + 2, m + 21, w - 4, h - 23, rock.width / ui.scale, rock.height / ui.scale)
    container = (
        m + 2,
        m + drawing.wm.WORLD_MAP_SPACER,
        drawing.wm.WORLD_MAP_WIDTH - 5,
        h - 2 - drawing.wm.WORLD_MAP_SPACER,
    )
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
    keep = drawing.wm.Image.new("L", art.image.size, 0)
    keep.paste(255, tuple(canvas.px(v) for v in (cx, cy, cx + cw, cy + ch)))
    art.image.putalpha(drawing.wm.ImageChops.multiply(art.image.getchannel("A"), keep))
    canvas.paste(art, 0, 0)
    canvas.draw(ui.atlas("_UI-Frame-InnerTopTile"), m + 2, m + 63, cw, 3)
    nav_x, nav_y = m + 2 + 64, m + 25
    nav_w = (m + drawing.wm.WORLD_MAP_WIDTH - 3 + drawing.wm.WORLD_MAP_NAVBAR_X_OFFSET) - nav_x
    nav_h = (m + drawing.wm.WORLD_MAP_SPACER - 9) - nav_y
    drawing.wm.nav_bar(canvas, nav_x, nav_y, nav_w, nav_h, MAP_NAV, MAP_NAV[1:])
    options_x, options_y = nav_x + nav_w + 10, nav_y + nav_h / 2 - 16 + 2
    canvas.draw(ui.atlas("common-dropdown-a-button"), options_x + 4, options_y + 6)
    toggle_x, toggle_y = cx + cw - 2 - 32, cy + ch - 1 - 32
    corner = ui.atlas("MapCornerShadow-Right")
    canvas.draw(corner, toggle_x + 32 + 2 - corner.width, toggle_y + 32 + 1 - corner.height)
    canvas.draw(ui.atlas("QuestCollapse-Hide-Up" if quest_log else "QuestCollapse-Show-Up"), toggle_x, toggle_y, 32, 32)
    canvas.nine_slice(drawing.wm.camelot_layout(drawing.wm.PORTRAIT_FRAME_LAYOUT), m, m, w, h)
    portrait = ui.canvas(canvas.width, canvas.height)
    portrait.draw(ui.texture("interface/questframe/ui-questlog-bookicon.blp"), m - 5, m - 7, 62, 62)
    portrait.mask(ui.texture("interface/characterframe/tempportraitalphamask.blp"), m - 3, m - 7, 58, 58)
    canvas.paste(portrait, 0, 0)
    canvas.text(
        m + 58, m + 1 + 5, "Map & Quest Log", drawing.wm.FONTS["GameFontNormal"], justify="CENTER", width=w - 58 - 24
    )
    close_x = m + w + 1 - 24
    canvas.draw(ui.atlas("RedButton-Exit"), close_x, m, 24, 24)
    canvas.draw(ui.atlas("RedButton-Expand"), close_x - 1 - 24, m, 24, 24)
    return canvas, rects


def draw_pins(canvas, rects, pins, hovered=None):
    """The addon's map pins from their dumps, centred on their map positions at a fixed scale of 1;
    `hovered` (an index into pins) draws that pin's highlight."""
    for index, pin in enumerate(pins):
        root = pin["layout"][0]
        cx, cy = map_point(rects, pin["x"], pin["y"])
        width, height = root["size"]
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


def quest_log(ui, content_ui, data, rects, scene, pins=()):
    """The world map with the quest log open on the guide's tab: `scene`'s panel dump in the quest pane, the tabs,
    and the map's pins."""
    art = explored_art(content_ui, data["panel"]["map"])

    def on_map(canvas, frame_rects):
        draw_pins(canvas, frame_rects, pins)
        draw_player(canvas, frame_rects, PLAYER)

    canvas, frame = map_frame(ui, art, True, on_map)
    Layout(data[scene]["layout"], rects[scene]).draw(canvas)
    tabs = [entry for dump in data[scene]["tabs"] for entry in dump]
    Layout(tabs, layout_rects(ui, tabs, known_frames(frame))).draw(canvas)
    return canvas, frame


MINIMAP_SIZE = 198  # the minimap face's UI units, as SPF's own minimap scene draws it
MINIMAP_RADIUS = 233 + 1 / 3  # world yards it shows
MINIMAP_CENTRE = (150, 155)  # the face's centre in the 300x285 cluster
MINIMAP_REACH = 170  # yards before the stop the minimap looks from


def tracker_module(ui, dump):
    """A tracker section from a tests/scenes.lua dump: its header, then each block's header and its lines."""
    blocks = [
        drawing.wm.TrackerBlock(block["header"], [(line["text"], line["dash"]) for line in block["lines"]])
        for block in dump["blocks"]
    ]
    return drawing.wm.TrackerModule(dump["header"], blocks)


TRACKER_HIDDEN_GAP = 6  # UI/Tracker.lua's HIDDEN_GAP, between the count and the collapse button


def tracker_hidden(canvas, rects, text):
    """The grey count UI/Tracker.lua anchors left of the module's collapse button, in the tracker dump's own words."""
    if not text:
        return
    x, y, _, height = rects["modules"][0]
    minimize = canvas.ui.atlas("ui-questtrackerbutton-secondary-collapse")
    right = x + drawing.wm.TRACKER_WIDTH + 1 - minimize.width - TRACKER_HIDDEN_GAP
    canvas.text(0, y, text, font("GameFontDisableSmall"), box_height=height, justify="RIGHT", width=right)


def spf_map(ui, content_ui, data, rects):
    """The world map with the guide's journey card and Shortest Path's walked route to the first stop: the guide's
    own panel, its numbered stops, and the walk Shortest Path took up when the route was handed over."""
    map_id = data["panel"]["map"]
    stops, player = data["map"]["stops"], data["map"]["player"]
    walk = spf_walk(content_ui, map_id, (player["x"], player["y"]), (stops[0]["x"], stops[0]["y"]))
    current = [map_position(content_ui, map_id, point) for point in walk]
    preview = [(stop["x"], stop["y"]) for stop in stops]

    def on_map(canvas, frame):
        marks = stop_groups(frame, stops)
        breadcrumbs(canvas, frame, [current, preview], marks)
        # While Shortest Path guides, the guide's own rings stay down and Shortest Path draws the numbered stops.
        goal_pins(canvas, stops, marks)
        draw_player(canvas, frame, player)

    canvas, frame = map_frame(ui, explored_art(content_ui, map_id), True, on_map)
    Layout(data["map_panel"]["layout"], rects["map_panel"]).draw(canvas)
    tabs = [entry for dump in data["map_panel"]["tabs"] for entry in dump]
    Layout(tabs, layout_rects(ui, tabs, known_frames(frame))).draw(canvas)
    return canvas


def before_stop(points, yards):
    """A walk of (x, y) world points cut `yards` before its end: the point there, and the walk from there on."""
    lengths = [((b[0] - a[0]) ** 2 + (b[1] - a[1]) ** 2) ** 0.5 for a, b in zip(points, points[1:], strict=False)]
    left = yards
    for index in range(len(points) - 2, -1, -1):
        if lengths[index] >= left:
            a, b, t = points[index], points[index + 1], left / lengths[index] if lengths[index] else 0
            here = (a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t)
            return here, [here, *points[index + 1 :]]
        left -= lengths[index]
    return points[0], points


def minimap_icon(canvas, name, x, y, size=None):
    """An icon centred on (x, y), its native aspect fitted inside `size` (WFA-27)."""
    art = canvas.ui.atlas(name)
    factor = size / max(art.width, art.height) if size else 1
    width, height = art.width * factor, art.height * factor
    canvas.draw(art, x - width / 2, y - height / 2, width, height)


def spf_minimap(ui, content_ui, data):
    """The minimap on the walk's last stretch into the first stop, Shortest Path's breadcrumbs and the guide's numbered
    marker for that stop on it, with the guide's tracker beside it."""
    map_id = data["panel"]["map"]
    stops, player = data["map"]["stops"], data["map"]["player"]
    walk = spf_walk(content_ui, map_id, (player["x"], player["y"]), (stops[0]["x"], stops[0]["y"]))
    here, remaining = before_stop(walk, MINIMAP_REACH)
    size, radius = MINIMAP_SIZE, MINIMAP_RADIUS
    face = ui.canvas(size, size)
    # minimap_art stitches the world map's WDT tiles, which the world map id names (1 for Kalimdor).
    world_map = int(assignment(content_ui, map_id)["MapID"])
    face.draw(drawing.wm.minimap_art(content_ui, world_map, here[0], here[1], radius), 0, 0, size, size)

    def project(point):
        return (
            size / 2 + (here[1] - point[1]) * size / (2 * radius),
            size / 2 - (point[0] - here[0]) * size / (2 * radius),
        )

    # Breadcrumbs take normalised map points: here they are the face's own 0..1 square.
    breadcrumbs(
        face,
        {"map": (0, 0, size, size)},
        [[tuple(value / size for value in project(point)) for point in remaining]],
        [],
    )
    face.mask(ui.atlas("ui-hud-minimap-frame-generic-mask").image, 0, 0, size, size)
    cx, cy = MINIMAP_CENTRE
    canvas = ui.canvas(300, 285)
    canvas.paste(face, cx - size / 2, cy - size / 2)
    minimap_icon(canvas, "UI-HUD-Minimap-Frame", cx, cy)
    minimap_icon(canvas, "UI-HUD-Minimap-NightCycle", cx + 63, cy - 72)
    minimap_icon(canvas, "UI-HUD-Minimap-Frame-Cycle", cx + 63, cy - 72)
    minimap_icon(canvas, "MinimapArrow", cx, cy, 16)
    # Pins.lua: the first stop wears our numbered marker at MINIMAP_ICON (24), pinned through HereBeDragons without
    # floatOnEdge, which hides it once its centre leaves the minimap's radius.
    stop = project(walk[-1])
    if (here[0] - walk[-1][0]) ** 2 + (here[1] - walk[-1][1]) ** 2 <= radius**2:
        canvas.draw(marker(1), cx - size / 2 + stop[0] - 12, cy - size / 2 + stop[1] - 12, 24, 24)
    canvas.text(0, 13, data["map"]["zone"], drawing.wm.FONTS["GameFontNormal"], justify="CENTER", width=300)
    tracker, _ = drawing.wm.objective_tracker(ui, [tracker_module(ui, data["map"]["tracker"])], container=False)
    # The minimap sits on the screen's right edge, so the column to its left is what a crop of that corner shows.
    return drawing.wm.scene(ui, [(tracker, 0, 6), (canvas, tracker.width + 24, 0)])


def spf_steps(ui, data):
    """The guide's tracker over Shortest Path's own: the steps it plans for the journey, the boat and the flight
    included, as its tracker words them."""
    dump = data["steps"]
    plan = spf_itinerary(ui, dump["player"], dump["stops"][0], dump["zone"])
    count = len(dump["stops"])
    title = f"Stop 1 of {count}: {dump['stops'][0]['title']}" if count > 1 else f"Journey to {dump['zone']}"
    # Route.lua's current row is OBJECTIVE_TRACKER_COLOR.NormalHighlight (white), the rest Normal.
    rows = [(f"|cffffffff{row['text']}|r" if row["current"] else row["text"], True) for row in plan["rows"]]
    module = drawing.wm.TrackerModule(plan["header"], [drawing.wm.TrackerBlock(title, rows)])
    canvas, _ = drawing.wm.objective_tracker(ui, [tracker_module(ui, dump["tracker"]), module], container=False)
    return canvas


def shortest_path(ui, content_ui, data):
    """The map while Shortest Path guides the route AGF handed it: the current leg (player to stop 1) walked with
    Path.FindSync, the later stops joined by the straight preview walk (Route.lua's `preview` path), the numbered
    stops, and the player."""
    stops, map_id = data["map"]["stops"], data["panel"]["map"]
    player = data["map"]["player"]
    walk = spf_walk(content_ui, map_id, (player["x"], player["y"]), (stops[0]["x"], stops[0]["y"]))
    current = [map_position(content_ui, map_id, point) for point in walk]
    preview = [(stop["x"], stop["y"]) for stop in stops]

    def on_map(canvas, rects):
        marks = stop_groups(rects, stops)
        breadcrumbs(canvas, rects, [current, preview], marks)
        goal_pins(canvas, stops, marks)
        draw_player(canvas, rects, player)

    canvas, _ = map_frame(ui, explored_art(content_ui, map_id), False, on_map)
    return canvas


def sha256(path):
    import hashlib

    return hashlib.sha256(path.read_bytes()).hexdigest()


def manifest(paths):
    """docs/screenshots/manifest.txt: what the PNGs were made from and each PNG's sha256, so a stale image or a
    changed input shows in review."""
    lines = [
        f"data build {DATA_BUILD}, art build {UI_ART_BUILD}",
        f"shortest-path-forever {SPF_SHA}",
        f"tests/golden/layout.json {sha256(GOLDEN)}",
    ]
    lines += [f"{path.relative_to(ROOT)} {sha256(path)}" for path in sorted(paths)]
    (OUT / "manifest.txt").write_text("\n".join(lines) + "\n")


DEMO_SIZE = (960, 640)  # the GIF's pixels: the README shows it at 640 wide, so text stays sharp on a 1.5x screen
DEMO_SCENES = (  # (image, seconds held): pick a journey, see its route, then its map route
    ("panel", 1.2),
    ("chosen", 1.8),
    ("map", 1.6),
)
DEMO_FADE = (4, 75)  # crossfade frames and milliseconds per frame
DEMO_LIMIT = 3_000_000


def demo(ui, images):
    """docs/screenshots/demo.gif: the stills above in order, each fitted to one frame. Two stills of the same frame
    (the map before and after choosing, the map route) crossfade, so only the part that changes moves and the
    GIF stores just that; the others cut. Holds are single long frames on one shared palette, so two runs match."""
    width, height = DEMO_SIZE
    stills = []
    for name, seconds in DEMO_SCENES:
        frame = drawing.wm.backdrop(ui, width, height).image.convert("RGB")
        image = images[name].image.convert("RGB")
        fit = min(frame.width / image.width, frame.height / image.height)
        size = (round(image.width * fit), round(image.height * fit))
        offset = ((frame.width - size[0]) // 2, (frame.height - size[1]) // 2)
        frame.paste(image.resize(size, drawing.wm.Image.Resampling.LANCZOS), offset)
        stills.append((frame.resize(DEMO_SIZE, drawing.wm.Image.Resampling.LANCZOS), round(seconds * 1000), image.size))
    frames, durations = [], []
    fades, step = DEMO_FADE
    for index, (still, hold, size) in enumerate(stills):
        frames.append(still)
        durations.append(hold)
        following, _, following_size = stills[(index + 1) % len(stills)]
        if following_size == size:
            for fade in range(1, fades + 1):
                frames.append(drawing.wm.Image.blend(still, following, fade / (fades + 1)))
                durations.append(step)
    sheet = drawing.wm.Image.new("RGB", (width, height * len(stills)))
    for index, (still, _, _) in enumerate(stills):
        sheet.paste(still, (0, height * index))
    palette = sheet.quantize(colors=256, method=drawing.wm.Image.Quantize.MEDIANCUT)
    indexed = [frame.quantize(palette=palette, dither=drawing.wm.Image.Dither.NONE) for frame in frames]
    buffer = io.BytesIO()
    indexed[0].save(buffer, format="GIF", save_all=True, append_images=indexed[1:], duration=durations, loop=0)
    content = buffer.getvalue()
    assert len(content) <= DEMO_LIMIT, f"demo.gif is {len(content):,} bytes, over {DEMO_LIMIT:,}"
    return content


def render():
    """Every scene into OUT; returns the written paths."""
    load_wowmock()

    version = importlib.metadata.version("pillow")
    if version != PILLOW:
        print(f"warning: Pillow {version}, not the pinned {PILLOW}: the PNGs may not match byte for byte")
    ui = drawing.wm.Ui(build=UI_ART_BUILD, scale=SCALE)
    content_ui = drawing.wm.Ui(build=DATA_BUILD, scale=SCALE)
    _, frame = map_frame(ui, drawing.wm.Image.new("RGBA", (1002, 668)), True)
    known = known_frames(frame)
    data, rects = layout_pass(
        ui,
        content_ui,
        (
            "panel",
            "journeys",
            "journeys_four",
            "journeys_overflow",
            "search",
            "story_complete",
            "restedxp",
            "guide_setup",
            "map_panel",
            "information_only",
            "information_fallback",
            "information_off",
        ),
        known,
    )
    images = {}
    setup_canvas = ui.canvas(454, 294)
    Layout(data["guide_setup"]["layout"], rects["guide_setup"]).draw(setup_canvas)
    images["guide_setup"] = drawing.wm.scene(ui, [(setup_canvas, 0, 0)])
    canvas, _ = quest_log(ui, content_ui, data, rects, "restedxp", data["restedxp"]["pins"])
    images["restedxp"] = drawing.wm.scene(ui, [(canvas, 0, 0)])

    # The lead images: the guide driving Shortest Path. The route on the map is the one it handed over, walked by
    # Shortest Path's own planner; the tracker beside the minimap is the step it heads for.
    images["spf_map"] = drawing.wm.scene(ui, [(spf_map(ui, content_ui, data, rects), 0, 0)])
    images["spf_minimap"] = drawing.wm.scene(ui, [(spf_minimap(ui, content_ui, data), 0, 0)])
    images["spf_steps"] = drawing.wm.scene(ui, [(spf_steps(ui, data), 0, 0)])

    # The lead image: no card chosen yet, compact rows with no scrollbar.
    canvas, _ = quest_log(ui, content_ui, data, rects, "journeys", data["journeys"]["pins"])
    images["panel"] = drawing.wm.scene(ui, [(canvas, 0, 0)])

    # The panel on its own: four journeys, and an overflow link in a shorter sidebar.
    for name, scene in (("panel_four", "journeys_four"), ("panel_overflow", "journeys_overflow")):
        canvas, _ = quest_log(ui, content_ui, data, rects, scene)
        x, y, width, height = rects[scene]["AdventureGuideForeverPanel"]
        images[name] = drawing.wm.scene(ui, [(crop(canvas, x - 6, y - 6, width + 12, height + 12), 0, 0)])

    # The Barrens story chosen: lit over its numbered steps, their rings on the map, the others folded above it.
    canvas, _ = quest_log(ui, content_ui, data, rects, "panel", data["panel"]["pins"])
    images["chosen"] = drawing.wm.scene(ui, [(canvas, 0, 0)])

    for scene in ("information_only", "information_fallback"):
        canvas, _ = quest_log(ui, content_ui, data, rects, scene, data[scene]["pins"])
        images[scene] = drawing.wm.scene(ui, [(canvas, 0, 0)])

    canvas, frame = quest_log(ui, content_ui, data, rects, "search", data["panel"]["pins"])
    qx, qy, qw, qh = frame["quests"]
    images["search"] = drawing.wm.scene(ui, [(crop(canvas, qx - 3, qy - 30, qw + 3 + 64, qh + 30 + 22), 0, 0)])

    art = explored_art(content_ui, data["panel"]["map"])
    canvas = shortest_path(ui, content_ui, data)
    images["map"] = drawing.wm.scene(ui, [(canvas, 0, 0)])

    images["tooltip"] = pin_tooltip(ui, art, data["tooltip"])
    images["information_tooltip"] = pin_tooltip(ui, art, data["information_tooltip"])
    images["information_off"] = pin_tooltip(ui, art, data["information_off"])

    canvas, tracked = drawing.wm.objective_tracker(ui, [tracker_module(ui, data["tracker"])], container=False)

    kinds = {"title": drawing.wm.MenuTitle, "button": drawing.wm.MenuButton}
    loot, _ = drawing.wm.context_menu(ui, [kinds[entry["kind"]](entry["text"]) for entry in data["loot_menu"]])
    images["loot"] = drawing.wm.scene(ui, [(loot, 0, 0)])
    menu, menu_rects = drawing.wm.context_menu(ui, [kinds[entry["kind"]](entry["text"]) for entry in data["menu"]])
    bx, by, _, _ = tracked["blocks"][0]
    # A right-click on the block header: Blizzard_Menu opens the menu with its TOPLEFT at the cursor.
    fx, fy, _, _ = menu_rects["menu"]
    images["menu"] = drawing.wm.scene(ui, [(canvas, 0, 0), (menu, bx + 60 - fx, by + 8 - fy)])

    # The tracker on the journey that hides two of the player's own quests, with the grey count beside its header.
    watch = data["tracker_watch"]
    canvas, tracked = drawing.wm.objective_tracker(ui, [tracker_module(ui, watch)], container=False)
    tracker_hidden(canvas, tracked, watch["hidden"])
    images["tracker"] = drawing.wm.scene(ui, [(canvas, 0, 0)])

    canvas = ui.canvas(400, 122)
    Layout(data["story_complete"]["layout"], rects["story_complete"]).draw(canvas)
    images["story_complete"] = drawing.wm.scene(ui, [(canvas, 0, 0)])

    OUT.mkdir(parents=True, exist_ok=True)
    written = []
    for name, image in images.items():
        path = OUT / f"{name}.png"
        image.save(path)
        written.append(path)
    path = OUT / "demo.gif"
    path.write_bytes(demo(ui, images))
    written.append(path)
    manifest(written)
    return written


def pin_tooltip(ui, art, scene):
    """Draw the runtime pin tooltip on its native map in either mode."""
    hovered = scene["hovered"] - 1

    def hover(canvas, frame_rects):
        draw_pins(canvas, frame_rects, scene["pins"], hovered)
        draw_player(canvas, frame_rects, PLAYER)

    canvas, frame = map_frame(ui, art, False, hover)
    colours = {
        "title": drawing.wm.WHITE,
        "highlight": drawing.wm.WHITE,
        "normal": drawing.wm.NORMAL,
        "instruction": GREEN,
    }
    tip = drawing.wm.tooltip(
        ui,
        [
            drawing.wm.TooltipLine(line["text"], tuple(line["color"]) if line.get("color") else colours[line["kind"]])
            for line in scene["lines"]
        ],
    )
    pin = scene["pins"][hovered]
    px, py = map_point(frame, pin["x"], pin["y"])
    # ANCHOR_RIGHT: the tooltip's BOTTOMLEFT at the pin's TOPRIGHT.
    pin_width, pin_height = pin["layout"][0]["size"]
    tip_x, tip_y = px + pin_width / 2, py - pin_height / 2 - tip.height
    left, top = px - 120, tip_y - 30
    shot = crop(canvas, left, top, tip_x + tip.width + 40 - left, py + 90 - top)
    return drawing.wm.scene(ui, [(shot, 0, 0), (tip, tip_x - left, tip_y - top)])


def main():
    for path in render():
        print(path.relative_to(ROOT))
    render_minimap_button_scenes()
    # What each image was drawn from, for CI's stale-screenshot check (tools/check_screenshots.py). Every image was
    # just drawn, so one whose pixels came out the same is recorded too, but only with the pinned Pillow: another
    # version's bytes are not the ones to keep.
    import check_screenshots
    from forever_tools import screens

    screens.record(OUT, check_screenshots.SCENES, force=importlib.metadata.version("pillow") == PILLOW)


def render_minimap_button_scenes():
    """The Adventure Guide button on the minimap rim, drawn by forever-core's shared renderer."""
    renderer = FOREVER_CORE / "docs/handoff/minimap-buttons/render.py"
    with tempfile.TemporaryDirectory(prefix="adventure-guide-minimap-") as directory:
        subprocess.run([sys.executable, str(renderer)], cwd=directory, check=True)
        shutil.copy2(Path(directory) / "minimap-adventure-guide.png", OUT / "minimap-adventure-guide.png")


if __name__ == "__main__":
    main()
