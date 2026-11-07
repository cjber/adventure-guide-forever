"""Export the route step markers from their generated sources in tools/number_source.

The sources are AI-assisted originals on a flat magenta (#FF00FF) background, made for this addon with no Blizzard
art. This keys the magenta to alpha, crops to the marker, centres it at its native aspect on a square canvas and
writes media/Numbers/<n>.tga for steps 1 to 10, plus Ring.tga, the empty ring a place visited twice stacks behind.
"""

import sys
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
SIZE = 64
MARKERS = [(f"{number}.png", f"{number}.tga") for number in range(1, 11)] + [("ring.png", "Ring.tga")]


def key_magenta(image: Image.Image) -> Image.Image:
    """Magenta to alpha, with a soft edge and the magenta spill pulled out of the rim."""
    image = image.convert("RGBA")
    pixels = image.load()
    for y in range(image.height):
        for x in range(image.width):
            r, g, b, _ = pixels[x, y]
            distance = max(abs(r - 255), g, abs(b - 255))
            if distance < 60:
                pixels[x, y] = (r, g, b, 0)
            elif distance < 120:
                pixels[x, y] = (min(r, g + 40), g, min(b, g + 40), int(255 * (distance - 60) / 60))
    return image


def export(source: Path, target: Path) -> None:
    marker = key_magenta(Image.open(source))
    marker = marker.crop(marker.getbbox())
    scale = SIZE / max(marker.size)  # one factor for both axes: the marker keeps its shape
    marker = marker.resize((round(marker.width * scale), round(marker.height * scale)), Image.Resampling.LANCZOS)
    canvas = Image.new("RGBA", (SIZE, SIZE))
    canvas.paste(marker, ((SIZE - marker.width) // 2, (SIZE - marker.height) // 2))
    canvas.save(target, compression=None)


def main() -> int:
    target_dir = ROOT / "media" / "Numbers"
    target_dir.mkdir(parents=True, exist_ok=True)
    for source, target in MARKERS:
        export(ROOT / "tools/number_source" / source, target_dir / target)
        print(f"wrote media/Numbers/{target}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
