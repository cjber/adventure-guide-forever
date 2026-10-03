#!/usr/bin/env python3
"""Render docs/screenshots/*.png and demo.gif from what the addon draws headlessly, with the WoW: Forever
client's own art.

    WOWMOCK=/path/to/wow-mock-screenshots python3 tools/screenshots.py

WFA-9: the store and README screenshots come from this script, never from a capture. The panel is
tests/golden/layout.json; every other scene is read from the addon by tests/scenes.lua through
the same harness, so no AGF text or layout is retyped here. Stock templates produce no regions headlessly, so each
one the dumps name has a recipe in screenshots_stock.py citing its Blizzard XML; an unknown stockTemplate fails the run.
The frames around the addon (the world map, the tracker, the tooltip and the menu) are wowmock's
(the wow-mock-screenshots skill), drawn from Blizzard's own layout numbers (WFA-4: the stock look).

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
import io
import json
import re
import subprocess
import sys
import tempfile
from pathlib import Path

import screenshots_art as drawing
from screenshots_art import draw_font_string, draw_texture, fit_text, font, load_wowmock
from screenshots_resolver import effective_scales, lua_rects, map_point, parent_path, resolve, scroll_child_anchors
from screenshots_spf import SPF_SHA, breadcrumbs, goal_pins, map_position, spf_walk, stop_groups
from screenshots_stock import LAYERS, button_font, draw_scroll_frame, stock

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "docs/screenshots"
GOLDEN = ROOT / "tests/golden/layout.json"
PILLOW = "12.3.0"
# Match the owner's 960 px / 800 UI-unit window. FreeType BASIC advances are pixel-hinted:
# measuring at 2x then shrinking gives different widths and hides client wrapping/truncation.
SCALE = 1.2
LAYOUT_PASSES = 8

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


def layout_pass(ui, scenes, known):
    """The client's layout, emulated: rects resolved from a run's dumps go back into the next run (h.SetRects runs
    the addon's OnSizeChanged, then the refresh re-lays the rows) until nothing moves, as the client settles over
    its first frames. The first run carries no input and must be tests/golden/layout.json exactly, so the scenes'
    fixture cannot drift from ui_spec's. Returns the settled run and each scene's rects."""
    data = run_scenes()
    golden = json.loads(GOLDEN.read_text())["layout"]
    if two_places(data["panel"]["layout"]) != golden:
        sys.exit("tests/scenes.lua's panel differs from tests/golden/layout.json: update its fixture to ui_spec's")
    inputs = {"rects": {}, "mapArt": map_tiles(ui)}
    for _ in range(LAYOUT_PASSES):
        data = run_scenes(inputs)
        rects = {scene: layout_rects(ui, data[scene]["layout"], known) for scene in scenes}
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


def explored_art(ui, map_id):
    """A uiMap's base art with every WorldMapOverlay drawn, as a character who has explored the whole zone sees it;
    the base art alone is the unexplored parchment."""
    art = drawing.wm.map_art(ui, map_id)
    for overlay in drawing.wm.map_overlays(ui, map_id):
        drawing.wm.draw_overlay(
            ui, art, overlay.offset_x, overlay.offset_y, overlay.width, overlay.height, overlay.tiles
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

WINDOW = "AdventureGuideForeverWindow"
WINDOW_SIZE = (800, 496)  # Window.lua's WIDTH and HEIGHT
WINDOW_MARGIN = 20  # the metal corners overhang the frame by up to 16
WINDOW_TABS = 30  # the tabs hang below the frame
WINDOWS = (
    "dungeons",
    "dungeons_live",
    "dungeons_empty",
    "dungeons_prep",
    "dungeons_bosses",
    "dungeons_loot",
    "dungeons_bosses_missing",
    "window",
    "window_professions",
    "window_pvp",
    "window_completion",
    "window_missing",
    "window_today",
    "window_context_menu",
    "window_session",
    "window_session_picker",
    "window_full_guide",
    "window_dungeon_maps",
    "window_empty",
    "window_order",
)
PLAYER = {"x": 0.52, "y": 0.30}  # tests/harness.lua's player position in The Barrens


def quest_log(ui, data, rects, scene, pins=()):
    """The world map with the quest log open on the guide's tab: `scene`'s panel dump in the quest pane, the tabs,
    and the map's pins."""
    art = explored_art(ui, data["panel"]["map"])

    def on_map(canvas, frame_rects):
        draw_pins(canvas, frame_rects, pins)
        draw_player(canvas, frame_rects, PLAYER)

    canvas, frame = map_frame(ui, art, True, on_map)
    Layout(data[scene]["layout"], rects[scene]).draw(canvas)
    tabs = [entry for dump in data[scene]["tabs"] for entry in dump]
    Layout(tabs, layout_rects(ui, tabs, known_frames(frame))).draw(canvas)
    return canvas, frame


def shortest_path(ui, data):
    """The map while Shortest Path guides the route AGF handed it: the current leg (player to stop 1) walked with
    Path.FindSync, the later stops joined by the straight preview walk (Route.lua's `preview` path), the numbered
    stops, and the player."""
    stops, map_id = data["map"]["stops"], data["panel"]["map"]
    player = data["map"]["player"]
    walk = spf_walk(ui, map_id, (player["x"], player["y"]), (stops[0]["x"], stops[0]["y"]))
    current = [map_position(ui, map_id, point) for point in walk]
    preview = [(stop["x"], stop["y"]) for stop in stops]

    def on_map(canvas, rects):
        marks = stop_groups(rects, stops)
        breadcrumbs(canvas, rects, [current, preview], marks)
        goal_pins(canvas, stops, marks)
        draw_player(canvas, rects, player)

    canvas, _ = map_frame(ui, explored_art(ui, map_id), False, on_map)
    return canvas


def sha256(path):
    import hashlib

    return hashlib.sha256(path.read_bytes()).hexdigest()


def manifest(paths):
    """docs/screenshots/manifest.txt: what the PNGs were made from and each PNG's sha256, so a stale image or a
    changed input shows in review."""
    lines = [
        f"build {drawing.wm.BUILD}",
        f"shortest-path-forever {SPF_SHA}",
        f"tests/golden/layout.json {sha256(GOLDEN)}",
    ]
    lines += [f"{path.relative_to(ROOT)} {sha256(path)}" for path in sorted(paths)]
    (OUT / "manifest.txt").write_text("\n".join(lines) + "\n")


DEMO_SIZE = (960, 640)  # the GIF's pixels: the README shows it at 640 wide, so text stays sharp on a 1.5x screen
DEMO_SCENES = (  # (image, seconds held): pick a journey, see its route, then the window's tabs
    ("panel", 1.2),
    ("chosen", 1.8),
    ("map", 1.6),
    ("window", 1.2),
    ("window_professions", 1.0),
    ("window_completion", 1.4),
)
DEMO_FADE = (4, 75)  # crossfade frames and milliseconds per frame
DEMO_LIMIT = 3_000_000


def demo(ui, images):
    """docs/screenshots/demo.gif: the stills above in order, each fitted to one frame. Two stills of the same frame
    (the map before and after choosing, the window's tabs) crossfade, so only the part that changes moves and the
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
    ui = drawing.wm.Ui(scale=SCALE)
    _, frame = map_frame(ui, drawing.wm.Image.new("RGBA", (1002, 668)), True)
    known = known_frames(frame) | {WINDOW: (WINDOW_MARGIN, WINDOW_MARGIN, *WINDOW_SIZE)}
    data, rects = layout_pass(
        ui, ("panel", "journeys", "journeys_four", "journeys_overflow", "search", *WINDOWS), known
    )
    images = {}

    # The lead image: no card chosen yet, compact rows with no scrollbar.
    canvas, _ = quest_log(ui, data, rects, "journeys", data["journeys"]["pins"])
    images["panel"] = drawing.wm.scene(ui, [(canvas, 0, 0)])

    # The panel on its own: four journeys, and an overflow link in a shorter sidebar.
    for name, scene in (("panel_four", "journeys_four"), ("panel_overflow", "journeys_overflow")):
        canvas, _ = quest_log(ui, data, rects, scene)
        x, y, width, height = rects[scene]["AdventureGuideForeverPanel"]
        images[name] = drawing.wm.scene(ui, [(crop(canvas, x - 6, y - 6, width + 12, height + 12), 0, 0)])

    # The Barrens story chosen: lit over its numbered steps, their rings on the map, the others folded above it.
    canvas, _ = quest_log(ui, data, rects, "panel", data["panel"]["pins"])
    images["chosen"] = drawing.wm.scene(ui, [(canvas, 0, 0)])

    canvas, frame = quest_log(ui, data, rects, "search", data["panel"]["pins"])
    qx, qy, qw, qh = frame["quests"]
    images["search"] = drawing.wm.scene(ui, [(crop(canvas, qx - 3, qy - 30, qw + 3 + 64, qh + 30 + 22), 0, 0)])

    art = explored_art(ui, data["panel"]["map"])
    canvas = shortest_path(ui, data)
    images["map"] = drawing.wm.scene(ui, [(canvas, 0, 0)])

    hovered = data["tooltip"]["hovered"] - 1

    def hover(canvas, frame_rects):
        draw_pins(canvas, frame_rects, data["tooltip"]["pins"], hovered)
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
            for line in data["tooltip"]["lines"]
        ],
    )
    pin = data["tooltip"]["pins"][hovered]
    px, py = map_point(frame, pin["x"], pin["y"])
    # ANCHOR_RIGHT: the tooltip's BOTTOMLEFT at the pin's TOPRIGHT.
    pin_width, pin_height = pin["layout"][0]["size"]
    tip_x, tip_y = px + pin_width / 2, py - pin_height / 2 - tip.height
    left, top = px - 120, tip_y - 30
    shot = crop(canvas, left, top, tip_x + tip.width + 40 - left, py + 90 - top)
    images["tooltip"] = drawing.wm.scene(ui, [(shot, 0, 0), (tip, tip_x - left, tip_y - top)])

    tracker = data["tracker"]
    blocks = [
        drawing.wm.TrackerBlock(block["header"], [(line["text"], line["dash"]) for line in block["lines"]])
        for block in tracker["blocks"]
    ]
    canvas, tracked = drawing.wm.objective_tracker(
        ui, [drawing.wm.TrackerModule(tracker["header"], blocks)], container=False
    )
    images["tracker"] = drawing.wm.scene(ui, [(canvas, 0, 0)])

    kinds = {"title": drawing.wm.MenuTitle, "button": drawing.wm.MenuButton}
    menu, menu_rects = drawing.wm.context_menu(ui, [kinds[entry["kind"]](entry["text"]) for entry in data["menu"]])
    bx, by, _, _ = tracked["blocks"][0]
    # A right-click on the block header: Blizzard_Menu opens the menu with its TOPLEFT at the cursor.
    fx, fy, _, _ = menu_rects["menu"]
    images["menu"] = drawing.wm.scene(ui, [(canvas, 0, 0), (menu, bx + 60 - fx, by + 8 - fy)])

    # The Adventure Guide window (docs/design.md §2.19) on each of its tabs.
    for scene in WINDOWS:
        width, height = WINDOW_SIZE
        canvas = ui.canvas(width + 2 * WINDOW_MARGIN, height + 2 * WINDOW_MARGIN + WINDOW_TABS)
        Layout(data[scene]["layout"], rects[scene]).draw(canvas)
        images[scene] = drawing.wm.scene(ui, [(canvas, 0, 0)])

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


def main():
    for path in render():
        print(path.relative_to(ROOT))


if __name__ == "__main__":
    main()
