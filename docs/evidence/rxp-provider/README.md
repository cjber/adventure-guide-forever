# RestedXP provider mark evidence

The guide card draws RestedXP's own installed logo (#713). Everything here is a source-rendered mock from the addon's
headless scenes and the installed logo asset: these are not in-game captures. This directory holds review evidence,
not store or README images; the shipped images stay `docs/screenshots/*.png` at the repository's 1.2 scale.

## Source

- Upstream release: RestedXP/RXPGuides `v4.11.36` (`8cff2f62751651f3d34311f1c00efd235e1c7e65`), CurseForge file
  9566650.
- v2 theme logo (`Themes.lua`, `RXP Blue V2`): `Textures/v2/rxp-icon-logo.blp`, 256x256 BLP2,
  sha256 `a1b118be54154ea5a9511d25162d84f1b7b228e07a3bb3b1e7f2fdfbbc42ed2b`.
- Legacy fallback: `Textures/rxp_logo-64.blp`, 64x64 BLP2,
  sha256 `c3640667641c5a01ab3671b9851686e1d79593d1ac4554317549ee924954a019`.
- The renderer reads the installed addon from `AGF_ADDONS_ROOT` when set, else the verified cache under
  `tools/.cache/rxp-<sha>/`; an unpinned or changed file stops the render. No logo is copied into this addon.

## `scale-1.0/`

Actual 1.0-scale renders from the same renderer as the shipped images (not resized from 1.2):

```sh
FOREVER_CORE=/path/to/forever-core /path/to/pillow-12.3.0/python - <<'PY'
import sys
sys.path.insert(0, "tools")
import screenshots

screenshots.SCALE = 1.0
screenshots.OUT = (screenshots.ROOT / "tools/.cache/rxp-scale-1.0").resolve()
screenshots.render()
PY
```

The command completed and wrote all 28 images, manifest included, under `tools/.cache/rxp-scale-1.0/` (ignored by
git); the seven `rxp_*` files were copied here unchanged. `rxp_overview.png` and `rxp_information.png` are byte-identical
on purpose: information mode changes what a click does and the chosen view's controls, not the overview's cards.
`rxp_information_chosen.png` shows the chosen guide with the Stop control gone.

## `before/`

`f61e299b`'s UI/Panel.lua with this branch's fixture, scenes and asset resolver copied in, rendered at the default 1.2
scale. `rxp_compact.png` shows the "new" quill drawn over the provider logo; the current
`docs/screenshots/rxp_compact.png` shows the 4px gap.

## Hashes

```
05645820cb1e3a2d02be799baad76ff281385b2b55dda7ef9d42050c117ec86d  scale-1.0/rxp_chosen.png
73d4fc8dde6d34bb2c9915065e65254932e55c82bf2e18e7ee2af36220717aab  scale-1.0/rxp_compact.png
6a414c058a3d9202d95ebb73d91b03b49e77c77003e6e2dc30186a0037692855  scale-1.0/rxp_information_chosen.png
757dc7b9ecf93c887d1f133de87e343155567a52345d02222a10939e1cb17a95  scale-1.0/rxp_information.png
7e061c5f526f0c0afea8083bc5e8b787b45dc71492e542990932ad05a80b58a1  scale-1.0/rxp_legacy.png
757dc7b9ecf93c887d1f133de87e343155567a52345d02222a10939e1cb17a95  scale-1.0/rxp_overview.png
6d52b4f637e393128aee34fda2fd4284552f46fc7f43076dc26679ec251e5f9e  scale-1.0/rxp_tooltip.png
01755f6197d7e1bbeb319aa19ffc3b6c20755ca59c0e4ede72c43aad806b6bde  before/rxp_chosen.png
3f1998121fd4f633bf7fb6137786b5830597ea8d077386d0767f2415d4bdca74  before/rxp_compact.png
```
