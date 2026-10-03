"""Resolve dumped frame anchors and map coordinates without Pillow."""

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


def explicit_size(entry, scale=1):
    """The size set with SetSize/SetWidth/SetHeight; 0 is unset, as GetSize(true) reports it. `scale` is the
    region's effective scale: its size is in its own units."""
    width, height = entry.get("size") or (0, 0)
    return (width * scale if width else None), (height * scale if height else None)


def effective_scales(entries):
    """Each region's effective scale (Frame:SetScale down the tree): what its offsets and sizes are multiplied by."""
    own = {entry["path"]: entry.get("scale") or 1 for entry in entries}
    scales = {}

    def effective(path):
        if path not in scales:
            parent = parent_path(path)
            while parent is not None and parent not in own:
                parent = parent_path(parent)
            scales[path] = own[path] * (effective(parent) if parent else 1)
        return scales[path]

    for path in own:
        effective(path)
    return scales


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
    scales = effective_scales(entries)
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
            horizontal[fx] = left + rx * width + anchor["x"] * scales[path]
            vertical[fy] = top + ry * height - anchor["y"] * scales[path]
        if anchors and placed:
            width, height = explicit_size(entry, scales[path])

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


def lua_rects(rects, widths):
    """Rects for h.SetRects: {left, bottom, width, height} with y growing upwards, as the client's edges are, and a
    font string's text width in the client's font fifth (its GetUnboundedStringWidth), the lines it wraps to in its
    rect sixth (its GetNumLines)."""
    return {
        path: [left, -(top + height), width, height] + list(widths.get(path, ()))
        for path, rect in rects.items()
        if rect is not None
        for left, top, width, height in [rect]
    }


def map_point(rects, x, y):
    mx, my, mw, mh = rects["map"]
    return mx + x * mw, my + y * mh
