"""Approval concept, separate from screenshots of the implemented UI.

Render with WOWMOCK configured. Geometry checks run without the art library in CI.
"""

import argparse
from dataclasses import dataclass
from pathlib import Path


@dataclass(frozen=True)
class Rect:
    x: float
    y: float
    width: float
    height: float

    def inset(self, padding):
        return Rect(self.x + padding, self.y + padding, self.width - 2 * padding, self.height - 2 * padding)

    def contains(self, other):
        return (
            self.x <= other.x
            and self.y <= other.y
            and other.x + other.width <= self.x + self.width
            and other.y + other.height <= self.y + self.height
        )


MAP_ASPECT = 1002 / 668
MAP_RIM = 8
MAP = Rect(60, 158, 344, 344 / MAP_ASPECT)
MAP_FRAME = Rect(MAP.x - MAP_RIM, MAP.y - MAP_RIM, MAP.width + 2 * MAP_RIM, MAP.height + 2 * MAP_RIM)
CURRENT = Rect(428, 154, 370, 118)
BUTTONS = (Rect(442, 234, 158, 24), Rect(608, 234, 82, 24))
UPCOMING = tuple(Rect(442, 312 + i * 36, 342, 32) for i in range(5))
PAGE = Rect(48, 94, 760, 416)


def validate_layout(map_rect=MAP, map_frame=MAP_FRAME, buttons=BUTTONS, upcoming=UPCOMING):
    if map_frame.inset(MAP_RIM) != map_rect:
        raise ValueError("Map must align with the frame's inner edges")
    if abs(map_rect.width / map_rect.height - MAP_ASPECT) > 0.001:
        raise ValueError("Map must preserve its full native aspect")
    for rect in (map_frame, CURRENT, *upcoming):
        if not PAGE.contains(rect):
            raise ValueError("Content must fit inside the page")
    for button in buttons:
        if button.height != 24 or not CURRENT.inset(12).contains(button):
            raise ValueError("Buttons must have a consistent height and fit inside the current step")
    if buttons[1].x - buttons[0].x - buttons[0].width != 8:
        raise ValueError("Button gap must be eight pixels")
    if len(upcoming) != 5 or upcoming[-1].y + upcoming[-1].height < PAGE.y + PAGE.height - 30:
        raise ValueError("Upcoming steps must use the available column")
    for first, second in zip(upcoming, upcoming[1:], strict=False):
        if second.y - first.y - first.height != 4:
            raise ValueError("Upcoming steps must have consistent spacing")


def validate_art(width, height, native_width, native_height, sliced=False):
    if sliced:
        if min(width, height) < 16:
            raise ValueError("Sliced frame must fit its fixed eight-pixel corners")
    elif abs((width / height) / (native_width / native_height) - 1) > 0.02:
        raise ValueError("Ordinary artwork must preserve its aspect")


def render(output):
    from screenshots_art import load_wowmock

    w = load_wowmock()
    from PIL import ImageOps

    validate_layout()
    ui = w.Ui("1.60.1.70124", scale=1.5)
    c = ui.canvas(860, 570)
    c.fill(0, 0, 860, 570, (0.025, 0.03, 0.03, 1))
    background = ui.atlas("QuestLog-main-background")
    c.draw(ImageOps.fit(background.image, (c.px(786), c.px(425))), 34, 90, 786, 425)
    c.fill(34, 90, 786, 425, (0, 0, 0, 0.45))

    def text(x, y, label, font="GameFontHighlight", width=None):
        c.text(x, y, label, w.FONTS[font], width=width)

    def icon(name, x, y, size=18):
        art = ui.atlas(name)
        scale = min(size / art.width, size / art.height)
        width, height = art.width * scale, art.height * scale
        validate_art(width, height, art.width, art.height)
        c.draw(art, x + (size - width) / 2, y + (size - height) / 2, width, height)

    # Same Encounter Journal source and fixed rim as WindowWidgets.CreateCard.
    card_image = ui.texture(522972).crop((1, 439, 175, 535))
    card = w.Atlas("journey-card", card_image, 174, 96, False, False, slice=(8, 8, 8, 8))

    def frame(rect):
        validate_art(rect.width, rect.height, card.width, card.height, sliced=True)
        c.fill(rect.x, rect.y, rect.width, rect.height, (0.035, 0.025, 0.015, 1))
        c.draw(card, rect.x, rect.y, rect.width, rect.height)

    text(94, 67, "Ashenvale · level 21")
    icon("questlog-questtypeicon-story", 58, 104, 25)
    text(92, 103, "Ashenvale story", "GameFontNormalLarge")
    text(92, 128, "Questing around Astranaar", "GameFontHighlightSmall")
    w.ui_panel_button(c, 558, 105, 126, 24, "View full guide")
    w.ui_panel_button(c, 692, 105, 104, 24, "No time limit")
    frame(MAP_FRAME)
    art = w.map_art(ui, 1440)
    validate_art(MAP.width, MAP.height, art.width, art.height)
    c.draw(art, MAP.x, MAP.y, MAP.width, MAP.height)
    px, py = MAP.x + MAP.width * 0.36, MAP.y + MAP.height * 0.493
    icon("QuestTurnin", px - 10, py - 10, 20)
    text(px - 25, py + 15, "Astranaar", "GameFontNormalSmall")
    text(60, 405, "At this stop", "GameFontNormal")
    icon("QuestTurnin", 60, 430)
    text(84, 430, "Bathan's Hair")
    text(84, 448, "Ready to hand in", "GameFontHighlightSmall")
    w.ui_panel_button(c, 60, 475, 144, 24, "View quests")
    frame(CURRENT)
    text(442, 166, "Do this next", "GameFontNormal")
    icon("QuestTurnin", 442, 189, 22)
    text(474, 189, "Visit Astranaar", "GameFontNormalLarge")
    text(474, 212, "2 quests to hand in · 1 to pick up", "GameFontHighlightSmall")
    for rect, label in zip(BUTTONS, ("Show on Map", "Stop"), strict=True):
        w.ui_panel_button(c, rect.x, rect.y, rect.width, rect.height, label)
    text(442, 289, "Coming up", "GameFontNormal")
    # Illustrative route content, not a claimed capture of the player's quest state.
    steps = (
        ("QuestNormal", "The Tower of Althalaxx", "Pick up at Astranaar"),
        ("questobjective", "Ilkrud Magthrull's Tome", "Collect the tome · The Tower of Althalaxx"),
        ("QuestTurnin", "The Tower of Althalaxx", "Return the tome"),
        ("questobjective", "Culling the Threat", "Complete the quest objectives"),
        ("QuestTurnin", "Culling the Threat", "Return to Astranaar"),
    )
    for rect, (atlas, title, detail) in zip(UPCOMING, steps, strict=True):
        icon(atlas, rect.x, rect.y + 2)
        text(rect.x + 28, rect.y, title, width=rect.width - 28)
        text(rect.x + 28, rect.y + 17, detail, "GameFontHighlightSmall", width=rect.width - 28)
    w.portrait_frame_art(c, 30, 30, 800, 496, ui.atlas("islands-queue-prop-compass").image, "Adventure Guide")
    w.panel_tabs(c, 46, 523, ["Journey", "Activities", "Progress"], 0)
    output.parent.mkdir(parents=True, exist_ok=True)
    c.save(output)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("output", type=Path)
    render(parser.parse_args().output)
