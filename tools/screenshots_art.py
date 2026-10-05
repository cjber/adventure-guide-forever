"""Load wowmock and draw textures and font strings from dumped regions."""

import dataclasses
import os
import sys
from pathlib import Path

WOWMOCK = Path(os.environ["WOWMOCK"]).expanduser() if os.environ.get("WOWMOCK") else None

wm = None  # Imported by load_wowmock so headless tests need no Pillow.


def load_wowmock():
    global wm
    if wm is None:
        if WOWMOCK is None:
            sys.exit("Set WOWMOCK to the directory containing wowmock.py from the wow-mock-screenshots library")
        if not (WOWMOCK / "wowmock.py").is_file():
            sys.exit(f"wowmock.py not found in {WOWMOCK}; set WOWMOCK to the wow-mock-screenshots skill")
        sys.path.insert(0, str(WOWMOCK))
        import wowmock

        wm = wowmock
        # Blizzard_Fonts_Shared/FontStyles.xml: GameFontNormalMed3 (SystemFont_Med3, shadowed) and GameFontDisable.
        wm.FONTS.setdefault("GameFontNormalMed3", wm.Font(wm.FRIZQT, 14, wm.NORMAL, (1, -1)))
        wm.FONTS.setdefault("GameFontDisable", wm.Font(wm.FRIZQT, 12, (0.5, 0.5, 0.5), (1, -1)))
        # GameFontNormalMed2 is SystemFont_Shadow_Med2 (Fonts.xml: FRIZQT at 13) in gold.
        wm.FONTS.setdefault("GameFontNormalMed2", wm.Font(wm.FRIZQT, 13, wm.NORMAL, (1, -1)))
        # GameFontRedSmall: SystemFont_Shadow_Small (FRIZQT at 10) in RED_FONT_COLOR.
        wm.FONTS.setdefault("GameFontRedSmall", wm.Font(wm.FRIZQT, 10, (1.0, 0.1, 0.1), (1, -1)))
        # NumberFontNormalSmall: NumberFont_OutlineThick_Mono_Small (ARIALN at 12, outlined) in white.
        wm.FONTS.setdefault("NumberFontNormalSmall", wm.Font(wm.ARIALN, 12, (1, 1, 1), None, True))
        # GameFontNormalHuge: SystemFont_Huge1 (FRIZQT at 20, shadowed) in gold.
        wm.FONTS.setdefault("GameFontNormalHuge", wm.Font(wm.FRIZQT, 20, wm.NORMAL, (1, -1)))
        # Game15Font_Shadow: the stock list header's font (Fonts.xml: FRIZQT at 15, shadowed) in gold, as the
        # overview's quest log headers draw it.
        wm.FONTS.setdefault("Game15Font_Shadow", wm.Font(wm.FRIZQT, 15, wm.NORMAL, (1, -1)))
        # GameFontNormalLarge2: SystemFont_Shadow_Large2 (Fonts.xml: FRIZQT at 18, shadowed) in gold.
        wm.FONTS.setdefault("GameFontNormalLarge2", wm.Font(wm.FRIZQT, 18, wm.NORMAL, (1, -1)))
        # QuestTitleFontBlackShadow (GameFontStyles.xml:228) inherits QuestFont_Huge (MORPHEUS at 18) in gold on a
        # black shadow; the Encounter Journal names its instance buttons with it.
        wm.FONTS.setdefault("QuestTitleFontBlackShadow", wm.Font("fonts/morpheus.ttf", 18, wm.NORMAL, (1, -1)))
        # GameFontBlack: SystemFont_Med1 (FRIZQT at 12) in black, no shadow; the journal loot row's metadata.
        wm.FONTS.setdefault("GameFontBlack", wm.Font(wm.FRIZQT, 12, (0, 0, 0)))
    return wm


def font(name):
    if name not in wm.FONTS:
        sys.exit(f"font object {name} has no wowmock Font: add it in load_wowmock()")
    return wm.FONTS[name]


def texture(ui, ref):
    return ui.texture(int(ref) if isinstance(ref, (int, float)) else ref.replace("\\", "/").lower() + ".blp")


def fit_text(canvas, text, face, width, wrap, max_lines=None):
    """A FontString's lines in `width`: one line cut with '...' under SetWordWrap(false), else word-wrapped, the last
    of SetMaxLines' lines cut with '...' when more would follow."""
    if width <= 0 or canvas.text_width(text, face) <= width + 0.5:
        return [text]
    if wrap is False:
        return [cut(canvas, text, face, width)]
    lines = wm.wrap_text(canvas, text, face, width)
    if max_lines and len(lines) > max_lines:
        lines = lines[: max_lines - 1] + [cut(canvas, " ".join(lines[max_lines - 1 :]), face, width)]
    return lines


def cut(canvas, text, face, width):
    """One line cut short with '...' to fit `width`."""
    if canvas.text_width(text, face) <= width + 0.5:
        return text
    while text and canvas.text_width(text + "...", face) > width:
        text = text[:-1]
    return text + "..."


def gradient(color, spec):
    """Texture:SetGradient on a colour texture: its colour times the vertex colours, `minColor` to `maxColor` left
    to right (HORIZONTAL) or bottom to top (VERTICAL), as a 256-step strip the draw stretches."""
    orientation, low, high = spec
    steps = [
        tuple(round(255 * c * (lo + (hi - lo) * i / 255)) for c, lo, hi in zip(color, low, high, strict=True))
        for i in range(256)
    ]
    if orientation == "HORIZONTAL":
        image = wm.Image.new("RGBA", (256, 1))
        image.putdata(steps)
    else:
        image = wm.Image.new("RGBA", (1, 256))
        image.putdata(steps[::-1])
    return image


def draw_texture(canvas, entry, rect, alpha, scale=1, mask=None):
    """A texture in its rect. An atlas keeps its slice margins (the atlas's, else SetTextureSliceMargins') at its
    frame's `scale`; `mask` is (MaskTexture entry, rect) for one AddMaskTexture put on it."""
    ui, (x, y, w, h) = canvas.ui, rect
    r, g, b, *vertex_alpha = entry.get("vertexColor") or (1, 1, 1)
    tint = (r, g, b, alpha * (vertex_alpha[0] if vertex_alpha else 1))
    target = ui.canvas(canvas.width, canvas.height) if entry.get("maskFile") or mask else canvas
    blend = entry.get("alphaMode") or "BLEND"
    if entry.get("atlas"):
        art = ui.atlas(entry["atlas"])
        if entry.get("desaturated"):
            art = dataclasses.replace(art, image=art.image.convert("LA").convert("RGBA"))
        if entry.get("slice"):
            art = dataclasses.replace(art, slice=tuple(entry["slice"]))
        if entry.get("texCoord"):
            # Art.lua's crops and slices: the harness gives each atlas its own whole sheet, so the coords are within it.
            target.draw(wm.crop_coords(art.image, *entry["texCoord"]), x, y, w, h, tint, blend)
        elif art.slice and scale != 1:
            # The margins keep their size in the frame's own units: drawn at that size, then scaled with the frame.
            full = ui.canvas(w / scale, h / scale)
            full.draw(art, 0, 0, w / scale, h / scale)
            target.draw(full.image, x, y, w, h, tint, blend)
        else:
            # Never stretched: whole art with no slice keeps its own shape (tiling strips aside), within 2%.
            tiles = entry["atlas"].startswith(("_", "!")) or entry.get("horizTile") or entry.get("vertTile")
            if not (art.slice or tiles) and w > 0 and h > 0 and abs(w / h * art.height / art.width - 1) > 0.02:
                sys.exit(
                    f"{entry['path']}: {entry['atlas']} is {art.width}x{art.height}, drawn {w:g}x{h:g}: "
                    "art is never stretched (UI/Art.lua)"
                )
            target.draw(art, x, y, w, h, tint, blend)
    elif entry.get("file") is not None:
        if entry.get("gradient"):
            sys.exit(f"{entry['path']}: SetGradient on a file texture: draw it in draw_texture")
        image = texture(ui, entry["file"])
        if entry.get("desaturated"):
            image = image.convert("LA").convert("RGBA")
        if entry.get("texCoord"):
            image = wm.crop_coords(image, *entry["texCoord"])
        target.draw(image, x, y, w, h, tint, blend)
    elif entry.get("color") and entry.get("gradient"):
        target.draw(gradient(entry["color"], entry["gradient"]), x, y, w, h, (1, 1, 1, alpha), blend)
    elif entry.get("color"):
        r, g, b, a = entry["color"]
        target.fill(x, y, w, h, (r, g, b, a * alpha))
    if entry.get("maskFile"):
        target.mask(texture(ui, entry["maskFile"]), x, y, w, h)
    if mask:
        mask_entry, (mx, my, mw, mh) = mask
        image = ui.atlas(mask_entry["atlas"]).image if mask_entry.get("atlas") else texture(ui, mask_entry["file"])
        target.mask(image, mx, my, mw, mh)
    if target is not canvas:
        canvas.paste(target, 0, 0)


def draw_font_string(canvas, entry, rect, alpha):
    """A FontString in its rect: justifyH CENTER unless set, lines centred vertically, one line cut with '...'
    when word wrap is off."""
    text = entry.get("text")
    if not text:
        return
    x, y, w, h = rect
    face = font(entry["font"])
    lines = fit_text(canvas, text, face, w, entry.get("wordWrap"), entry.get("maxLines"))
    top = y + (h - face.height * len(lines) - (entry.get("spacing") or 0) * (len(lines) - 1)) / 2
    target = canvas.ui.canvas(canvas.width, canvas.height) if alpha < 1 else canvas
    for index, line in enumerate(lines):
        colour = tuple(entry["textColor"][:3]) if entry.get("textColor") else None
        target.text(
            x,
            top + index * (face.height + (entry.get("spacing") or 0)),
            line,
            face,
            colour,
            justify=entry.get("justifyH") or "CENTER",
            width=w,
        )
    if target is not canvas:
        target.image = wm.tint(target.image, (1, 1, 1, alpha))
        canvas.paste(target, 0, 0)
