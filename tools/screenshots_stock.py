"""Blizzard stock-template recipes for headless screenshot layouts."""

import sys

import screenshots_art as drawing
from screenshots_art import cut, font, texture
from screenshots_resolver import POINTS

LAYERS = ("BACKGROUND", "BORDER", "ARTWORK", "OVERLAY", "HIGHLIGHT")
# Every phase a stock recipe is drawn in: the draw layers, then its text, then its frame (before the children) and
# after the children. A recipe's `layer` is always one of these; screenshots_test.py checks the file's comparisons.
PHASES = (*LAYERS, "TEXT", "FRAME", "AFTER")


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


def draw_dropdown(canvas, entry, rect, layer):
    """WowStyle1DropdownTemplate (Blizzard_Menu/Mainline/MenuTemplates.xml:3): 120x25; common-dropdown-textholder
    from TOPLEFT (-8, 7) to BOTTOMRIGHT (8, -9) (BACKGROUND); common-dropdown-a-button at its atlas size at RIGHT
    (1, -3), and Text (GameFontHighlight, 10 high, justifyH LEFT) from TOPLEFT (8, -8) to the arrow's LEFT (OVERLAY)."""
    ui, (x, y, w, h) = canvas.ui, rect
    if layer == "BACKGROUND":
        canvas.draw(ui.atlas("common-dropdown-textholder"), x - 8, y - 7, w + 16, h + 16)
    elif layer == "OVERLAY":
        arrow = ui.atlas("common-dropdown-a-button")
        ax, ay = x + w + 1 - arrow.width, y + h / 2 + 3 - arrow.height / 2
        canvas.draw(arrow, ax, ay)
        text = ((entry.get("stock") or {}).get("Text") or {}).get("text")
        if text:
            face = button_font(entry, "GameFontHighlight", "GameFontHighlight", "GameFontDisable")
            canvas.text(x + 8, y + 8, cut(canvas, text, face, ax - x - 8), face, box_height=10)


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


def button_font(entry, normal, highlight, disabled):
    if entry.get("disabled"):
        return font(disabled)
    if entry.get("highlightLocked"):
        return font(entry.get("highlightFont") or highlight)
    return font(entry.get("normalFont") or normal)


def draw_panel_button(canvas, entry, rect, layer):
    """UIPanelButtonTemplate (Mainline/SharedUIPanelTemplates.xml:315, on UIPanelButtonNoTooltipTemplate,
    SecureUIPanelTemplates.xml:39): UI-Panel-Button-Up in three slices, 12-unit caps, texcoords to .6875 down
    (UI-Panel-Button-Disabled once disabled), GameFontNormal centred (GameFontDisable when disabled)."""
    x, y, w, h = rect
    if layer == "BACKGROUND":
        file = texture(
            canvas.ui, "Interface\\Buttons\\UI-Panel-Button-" + ("Disabled" if entry.get("disabled") else "Up")
        )
        canvas.draw(drawing.wm.crop_coords(file, 0, 0.09375, 0, 0.6875), x, y, 12, h)
        canvas.draw(drawing.wm.crop_coords(file, 0.09375, 0.53125, 0, 0.6875), x + 12, y, w - 24, h)
        canvas.draw(drawing.wm.crop_coords(file, 0.53125, 0.625, 0, 0.6875), x + w - 12, y, 12, h)
    elif layer == "TEXT" and entry.get("text"):
        face = button_font(entry, "GameFontNormal", "GameFontHighlight", "GameFontDisable")
        canvas.text(x, y, entry["text"], face, justify="CENTER", width=w, box_height=h)


def tab_size(ui, entry):
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
    drawing.wm.minimal_scrollbar(canvas, left, top, points["BOTTOMLEFT"][1] - top, visible, 0)


def draw_scroll_box(canvas, entry, rect, layer):
    """WowScrollBoxList (Blizzard_SharedXML/Shared/Scroll/ScrollTemplates.xml:4, on ScrollBoxBaseTemplate): the
    frame draws no chrome of its own; its rows and its MinimalScrollBar draw themselves."""


def draw_minimal_scroll_bar(canvas, entry, rect, layer):
    """MinimalScrollBar (Blizzard_SharedXML/Shared/Scroll/MinimalScrollBar.xml:15, on the VerticalScrollBarTemplate
    of ScrollTemplates.xml:15): the 8-wide track and both steppers. A stock frame carries no pan extent, so the
    thumb is left to the list that owns it."""
    if layer == "BACKGROUND":
        x, y, _, h = rect
        drawing.wm.minimal_scrollbar(canvas, x, y, h, 1, 0)


def draw_portrait_frame(canvas, entry, rect, layer):
    """PortraitFrameTemplate (Blizzard_SharedXML/Mainline/PortraitFrame.xml): the rock Bg tiled TOPLEFT (2, -21) to
    BOTTOMRIGHT (-2, 2) and the TopTileStreaks 43 high at TOPLEFT (6, -21) to TOPRIGHT (-2, -21) under everything;
    after the frame's children (the addon's PortraitContainer is one), the metal NineSlice (frameLevel 500), the
    TitleText and the CloseButton, as wowmock.portrait_frame_art draws them."""
    ui, (x, y, w, h) = canvas.ui, rect
    if layer == "BACKGROUND":
        rock = ui.texture("interface/framegeneral/ui-background-rock.blp")
        drawing.wm.tiled(canvas, rock, x + 2, y + 21, w - 4, h - 23, rock.width / ui.scale, rock.height / ui.scale)
        canvas.draw(ui.atlas("_UI-Frame-TopTileStreaks"), x + 6, y + 21, w - 8, 43)
    elif layer == "AFTER":
        canvas.nine_slice(drawing.wm.PORTRAIT_FRAME_TEMPLATE_LAYOUT, x, y, w, h)
        title = entry.get("stock", {}).get("TitleText", {}).get("text") or ""
        canvas.text(x + 58, y + 1 + 5, title, font("GameFontNormal"), justify="CENTER", width=w - 58 - 24)
        canvas.draw(ui.atlas("RedButton-Exit"), x + w - 2 - 24, y - 1, 24, 24)


def draw_inset_frame(canvas, entry, rect, layer):
    """InsetFrameTemplate (Mainline/SharedUIPanelTemplates.xml): the marble Bg tiled TOPLEFT (2, -2) to BOTTOMRIGHT
    (-2, 2) at BACKGROUND -6, under the addon's own art, and the inner NineSlice over it."""
    ui, (x, y, w, h) = canvas.ui, rect
    if layer == "BACKGROUND":
        marble = ui.texture("interface/framegeneral/ui-background-marble.blp")
        drawing.wm.tiled(canvas, marble, x + 2, y + 2, w - 4, h - 4, marble.width / ui.scale, marble.height / ui.scale)
    elif layer == "FRAME":
        canvas.nine_slice(drawing.wm.INSET_FRAME_LAYOUT, x, y, w, h)


def panel_tab_font(entry):
    """The selected tab is disabled (PanelTemplates_SelectTab) and takes GameFontHighlightSmall; the others their
    normal font (the addon greys a tab with nothing to show)."""
    return font("GameFontHighlightSmall" if entry.get("disabled") else entry.get("normalFont") or "GameFontNormalSmall")


def panel_tab_size(ui, entry):
    """PanelTabButtonMixin:OnShow's TabResize: the text's width plus 20, at least the caps', 32 high."""
    caps = ui.atlas("uiframe-tab-left").width + ui.atlas("uiframe-tab-right").width
    return max(ui.canvas(1, 1).text_width(entry.get("text") or "", panel_tab_font(entry)) + 20, caps), 32


def draw_panel_tab(canvas, entry, rect, layer):
    """PanelTabButtonTemplate (Mainline/SharedUIPanelTemplates.xml:932), as wowmock.panel_tabs draws one: the
    uiframe-activetab art while selected, else uiframe-tab, and the label at CENTER (0, -3) selected, else (0, 2)."""
    ui, (x, y, w, _) = canvas.ui, rect
    active = entry.get("disabled")
    if layer == "BACKGROUND":
        prefix = "uiframe-activetab" if active else "uiframe-tab"
        left, right = ui.atlas(f"{prefix}-left"), ui.atlas(f"{prefix}-right")
        left_x = x + (-1 if active else -3)
        right_x = x + w + (8 if active else 7) - right.width
        canvas.draw(left, left_x, y)
        canvas.draw(right, right_x, y)
        middle = ui.atlas(f"_{prefix}-center")
        canvas.draw(middle, left_x + left.width, y, right_x - left_x - left.width, middle.height)
    elif layer == "TEXT" and entry.get("text"):
        top = y + 16 - 5 + (3 if active else -2)
        canvas.text(x, top, entry["text"], panel_tab_font(entry), justify="CENTER", width=w, box_height=10)


def draw_top_tab(canvas, entry, rect, layer):
    """Shared/TabSystem/TabSystemTemplates.xml's TabSystemTopButtonTemplate: HandleRotation rotates each cap
    and anchors the art to the same bottom edge. AGF centres all labels on one baseline."""
    ui, (x, y, w, h) = canvas.ui, rect
    active = entry.get("disabled")
    if layer == "BACKGROUND":
        prefix = "uiframe-activetab" if active else "uiframe-tab"
        left, right = ui.atlas(f"{prefix}-left"), ui.atlas(f"{prefix}-right")
        left_x = x - (7 if active else 6)
        right_x = x + w - left.width
        canvas.draw(right.image.rotate(180), left_x, y + h - right.height, right.width, right.height)
        canvas.draw(left.image.rotate(180), right_x, y + h - left.height, left.width, left.height)
        middle = ui.atlas(f"_{prefix}-center")
        canvas.draw(
            middle.image.rotate(180),
            left_x + right.width,
            y + h - middle.height,
            right_x - left_x - right.width,
            middle.height,
        )
    elif layer == "TEXT":
        canvas.text(
            x,
            y + h / 2 - 5,
            entry.get("text") or "",
            font(entry.get("normalFont") or "GameFontNormalSmall"),
            justify="CENTER",
            width=w,
            box_height=10,
        )


def draw_collapse_button(canvas, entry, rect, layer):
    """ListTemplates.xml CollapseButtonTemplate, used by QuestLogHeaderTemplate: native plus/minus centred."""
    if layer == "ARTWORK":
        x, y, w, h = rect
        atlas = entry.get("stock", {}).get("Icon", {}).get("atlas")
        if atlas:
            art = canvas.ui.atlas(atlas)
            canvas.draw(art, x + (w - art.width) / 2, y + (h - art.height) / 2)


def draw_page_arrow(side):
    """Blizzard_PagingControls.xml's page buttons: the spellbook's Up art, or its Disabled art at either end."""

    def draw(canvas, entry, rect, layer):
        """Blizzard_PagedContent/Blizzard_PagingControls.xml: the button's NormalTexture or DisabledTexture."""
        if layer == "ARTWORK":
            state = "Disabled" if entry.get("disabled") else "Up"
            canvas.draw(texture(canvas.ui, f"Interface/Buttons/UI-SpellbookIcon-{side}Page-{state}"), *rect)

    return draw


def draw_check_button(canvas, entry, rect, layer):
    """Shared/Button/CheckButtonTemplates.xml: UICheckButtonArtTemplate's square Up and Check textures.
    Text is a template FontString, dumped by the harness at its XML anchor."""
    if layer == "ARTWORK":
        canvas.draw(texture(canvas.ui, "Interface/Buttons/UI-CheckBox-Up"), *rect)
        if entry.get("checked"):
            canvas.draw(texture(canvas.ui, "Interface/Buttons/UI-CheckBox-Check"), *rect)


def draw_alpha_highlight(canvas, entry, rect, layer):
    """AlphaHighlightButtonTemplate (Mainline/SharedUIPanelTemplates.xml:1587): no art of its own; its NormalTexture
    and PushedTexture are the button's regions, and its highlight (the same atlas, added) shows only under the mouse,
    which no scene holds."""


# name: (draw(canvas, entry, rect, layer), its <Size> by (ui, entry) or None, its own <Anchors> or None, frameLevel)
STOCK = {
    "UICheckButtonTemplate": (draw_check_button, lambda ui, entry: (32, 32), None, 0),
    "TabSystemTopButtonTemplate": (draw_top_tab, None, None, 0),
    "CollapseButtonTemplate": (draw_collapse_button, None, None, 0),
    "PagingControlsPrevPageButtonTemplate": (draw_page_arrow("Prev"), None, None, 0),
    "PagingControlsNextPageButtonTemplate": (draw_page_arrow("Next"), None, None, 0),
    "AlphaHighlightButtonTemplate": (draw_alpha_highlight, None, None, 0),
    "InputBoxVisualTemplate": (draw_input_box, None, None, 0),
    "InsetFrameTemplate": (draw_inset_frame, None, None, 0),
    "LargeSideTabButtonTemplate": (draw_side_tab, tab_size, None, 0),
    "PanelTabButtonTemplate": (draw_panel_tab, panel_tab_size, None, 0),
    "PortraitFrameTemplate": (draw_portrait_frame, None, None, 0),
    "QuestLogBorderFrameTemplate": (
        draw_quest_log_border,
        None,
        [("TOPLEFT", -3, 7), ("BOTTOMRIGHT", 3, -6)],
        100,
    ),
    "ScrollFrameTemplate": (draw_scroll_frame, None, None, 0),
    "WowScrollBoxList": (draw_scroll_box, None, None, 0),
    "MinimalScrollBar": (draw_minimal_scroll_bar, None, None, 0),
    "SearchBoxTemplate": (draw_search_box, None, None, 0),
    "UIPanelButtonTemplate": (draw_panel_button, lambda ui, entry: (40, 22), None, 0),
    "UIPanelIconDropdownButtonTemplate": (draw_icon_dropdown, lambda ui, entry: (15, 16), None, 0),
    "WowStyle1DropdownTemplate": (draw_dropdown, lambda ui, entry: (120, 25), None, 0),
}


def stock(entry):
    """The recipe for a dumped frame's stock template; one the script has none for fails the run,
    so a new template is drawn from its XML rather than left out."""
    name = entry.get("stockTemplate")
    if name is None:
        return None
    if name not in STOCK:
        sys.exit(f"{entry['path']}: no recipe for stock template {name}: add one to STOCK citing its Blizzard XML")
    return STOCK[name]
